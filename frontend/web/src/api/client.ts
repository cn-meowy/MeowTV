import ky from 'ky';
import type { ApiResponse } from '@/types/api';

/**
 * 业务错误类
 */
export class ApiError extends Error {
  code: number;
  constructor(code: number, msg: string) {
    super(msg);
    this.code = code;
    this.name = 'ApiError';
  }
}

/**
 * 获取存储的 access_token（从 auth store 延迟读取，避免循环依赖）
 */
let _getAccessToken: () => string | null = () => null;
let _getRefreshToken: () => string | null = () => null;
let _onRefreshSuccess: (accessToken: string, refreshToken: string) => void = () => {};
let _onRefreshFailure: () => void = () => {};

/**
 * Token 刷新去重锁：多个并发 401 共享同一个 refresh Promise，
 * 避免同时发出多个 refresh 请求
 */
let _refreshInFlight: Promise<{ access_token: string; refresh_token: string }> | null = null;

export function configureAuthHooks(hooks: {
  getAccessToken: () => string | null;
  getRefreshToken: () => string | null;
  onRefreshSuccess: (accessToken: string, refreshToken: string) => void;
  onRefreshFailure: () => void;
}) {
  _getAccessToken = hooks.getAccessToken;
  _getRefreshToken = hooks.getRefreshToken;
  _onRefreshSuccess = hooks.onRefreshSuccess;
  _onRefreshFailure = hooks.onRefreshFailure;
}

/**
 * 创建 ky 实例
 */
const apiClient = ky.create({
  timeout: 15_000,
  hooks: {
    beforeRequest: [
      (request) => {
        const token = _getAccessToken();
        if (token) {
          request.headers.set('Authorization', `Bearer ${token}`);
        }
      },
    ],
    afterResponse: [
      async (request, options, response) => {
        // 只处理 401
        if (response.status !== 401) return response;

        // 尝试用 refresh_token 刷新
        const refreshToken = _getRefreshToken();
        if (!refreshToken) {
          _onRefreshFailure();
          return response;
        }

        try {
          // 去重锁：多个并发 401 共享同一个 refresh Promise，
          // 避免同时发出多个 refresh 请求导致后端拒绝或 token 混乱
          if (!_refreshInFlight) {
            _refreshInFlight = (async () => {
              const refreshResp = await fetch('/api/auth/refresh', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ refresh_token: _getRefreshToken() }),
              });

              if (!refreshResp.ok) {
                throw new Error('Refresh failed');
              }

              const json = await refreshResp.json();
              if (json.code !== 200 || !json.data) {
                throw new Error('Refresh returned error');
              }

              return json.data as { access_token: string; refresh_token: string };
            })();

            _refreshInFlight.finally(() => {
              _refreshInFlight = null;
            });
          }

          const data = await _refreshInFlight;
          _onRefreshSuccess(data.access_token, data.refresh_token);

          // 用新 token 重试原请求
          const retryRequest = request.clone();
          retryRequest.headers.set('Authorization', `Bearer ${data.access_token}`);
          return ky(retryRequest, options);
        } catch {
          _onRefreshFailure();
          return response;
        }
      },
    ],
  },
});

/**
 * 获取当前 access_token（供非 ky 请求使用，如 SSE fetch）
 */
export function getAccessToken(): string | null {
  return _getAccessToken();
}

/**
 * 通用 POST 请求方法
 * 后端所有接口均为 POST + JSON Body
 */
export async function post<T = unknown>(url: string, json?: Record<string, unknown>): Promise<T> {
  const resp = await apiClient.post(url, { json }).json<ApiResponse<T>>();

  if (resp.code !== 200) {
    throw new ApiError(resp.code, resp.msg);
  }

  return resp.data;
}

export default apiClient;
