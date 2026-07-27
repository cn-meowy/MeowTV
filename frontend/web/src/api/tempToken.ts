import { API } from '@/constants/api';
import apiClient from './client';
import type { TempTokenResp } from '@/types/api';

// ── 临时 Token 缓存（统一，供图片代理和流代理复用）──────────────────────────

interface TempTokenCache {
  token: string;
  expiresAt: number; // ms 时间戳
}

let tokenCache: TempTokenCache | null = null;
let inFlight: Promise<string> | null = null;

/** 获取临时 Token（带缓存 + 并发去重）
 *
 * - 缓存有效时直接返回，不发起网络请求
 * - 缓存过期时才调用 /api/token/temp
 * - 多个调用并发时共享同一个 Promise，避免重复请求
 * - 提前 30 秒视为过期，避免边界问题
 */
export async function getTempToken(): Promise<string> {
  // 1. 缓存有效，直接返回
  if (tokenCache && Date.now() < tokenCache.expiresAt) {
    return tokenCache.token;
  }

  // 2. 已有进行中的请求，复用同一个 Promise
  if (inFlight) {
    return inFlight;
  }

  // 3. 发起新请求
  inFlight = (async () => {
    try {
      const resp = await apiClient.post(API.TOKEN_TEMP).json<{ code: number; data: TempTokenResp }>();
      if (resp.code !== 200) {
        throw new Error('Failed to get temp token');
      }
      // 提前 30 秒视为过期，避免边界问题
      const bufferMs = 30 * 1000;
      const tokenData = resp.data;
      tokenCache = {
        token: tokenData.token,
        expiresAt: Date.now() + tokenData.expires_in * 1000 - bufferMs,
      };
      return tokenData.token;
    } finally {
      inFlight = null;
    }
  })();

  return inFlight;
}

/** 使临时 Token 缓存失效
 *
 * 当后端返回 401（token 过期/无效）时调用，强制下次 getTempToken() 发起新请求。
 * 场景：用户暂停播放很久后恢复，tempToken 已被后端清除，但前端缓存尚未过期。
 */
export function invalidateTempTokenCache(): void {
  tokenCache = null;
}
