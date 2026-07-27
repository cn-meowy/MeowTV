import { create } from 'zustand';
import type { ProfileResp, LoginResp } from '@/types/api';
import { DeviceType } from '@/types/api';
import * as authApi from '@/api/auth';
import * as userApi from '@/api/user';
import { configureAuthHooks } from '@/api/client';
import QRCode from 'qrcode';

const ACCESS_TOKEN_KEY = 'meowtv_at';
const REFRESH_TOKEN_KEY = 'meowtv_rt';
const DEVICE_ID_KEY = 'meowtv_device_id';

/** 获取浏览器唯一指纹，优先从 localStorage 缓存 */
async function getDeviceId(): Promise<string> {
  const cached = localStorage.getItem(DEVICE_ID_KEY);
  if (cached) return cached;

  try {
    const { getFingerprint } = await import('thumbmarkjs');
    const fingerprint = await getFingerprint();
    localStorage.setItem(DEVICE_ID_KEY, fingerprint);
    return fingerprint;
  } catch {
    // ThumbmarkJS 不可用时，使用随机 ID
    const fallback = crypto.randomUUID();
    localStorage.setItem(DEVICE_ID_KEY, fallback);
    return fallback;
  }
}

/** 解析 User-Agent 生成设备显示名称，如 "Chrome 120 / macOS" */
function getDeviceName(): string {
  const ua = navigator.userAgent;

  // 浏览器
  let browser = 'Unknown Browser';
  if (ua.includes('Edg/')) {
    const m = ua.match(/Edg\/([\d.]+)/);
    browser = `Edge ${m?.[1] ?? ''}`.trim();
  } else if (ua.includes('Chrome/') && !ua.includes('Edg/')) {
    const m = ua.match(/Chrome\/([\d.]+)/);
    browser = `Chrome ${m?.[1] ?? ''}`.trim();
  } else if (ua.includes('Firefox/')) {
    const m = ua.match(/Firefox\/([\d.]+)/);
    browser = `Firefox ${m?.[1] ?? ''}`.trim();
  } else if (ua.includes('Safari/') && !ua.includes('Chrome/')) {
    const m = ua.match(/Version\/([\d.]+)/);
    browser = `Safari ${m?.[1] ?? ''}`.trim();
  }

  // 操作系统
  let os = 'Unknown OS';
  if (ua.includes('Mac OS X')) {
    const m = ua.match(/Mac OS X ([\d_]+)/);
    os = `macOS ${m?.[1]?.replace(/_/g, '.') ?? ''}`.trim();
  } else if (ua.includes('Windows NT')) {
    const m = ua.match(/Windows NT ([\d.]+)/);
    os = `Windows ${m?.[1] ?? ''}`.trim();
  } else if (ua.includes('Linux') && ua.includes('Android')) {
    const m = ua.match(/Android ([\d.]+)/);
    os = `Android ${m?.[1] ?? ''}`.trim();
  } else if (ua.includes('Linux')) {
    os = 'Linux';
  } else if (ua.includes('iPhone') || ua.includes('iPad')) {
    const m = ua.match(/OS ([\d_]+)/);
    os = `iOS ${m?.[1]?.replace(/_/g, '.') ?? ''}`.trim();
  }

  return `${browser} / ${os}`;
}

/** 扫码登录状态 */
export type QRCodeLoginState = 'idle' | 'loading' | 'showing' | 'scanned' | 'expired' | 'error';

interface AuthState {
  accessToken: string | null;
  refreshToken: string | null;
  user: ProfileResp | null;
  isAuthenticated: boolean;
  isInitializing: boolean;
  isLoading: boolean;

  // 扫码登录相关
  qrcodeState: QRCodeLoginState;
  qrcodeUrl: string | null;
  qrcodeCode: string | null;
  qrcodeExpiresIn: number;

  login: (username: string, password: string) => Promise<void>;
  logout: () => Promise<void>;
  refreshTokens: () => Promise<void>;
  fetchProfile: () => Promise<void>;
  initializeAuth: () => Promise<void>;
  setTokens: (accessToken: string, refreshToken: string) => void;
  clearAuth: () => void;

  // 扫码登录方法
  startQRCodeLogin: () => Promise<void>;
  stopQRCodeLogin: () => void;
  refreshQRCode: () => Promise<void>;
}

/** 轮询定时器 ID */
let _qrcodePollTimer: ReturnType<typeof setInterval> | null = null;
/** 过期倒计时定时器 ID */
let _qrcodeExpireTimer: ReturnType<typeof setInterval> | null = null;
/** 防重入标志 */
let _qrcodeStarting = false;

export const useAuthStore = create<AuthState>((set, get) => {
  // 从 localStorage 恢复初始状态
  const initialAccessToken = localStorage.getItem(ACCESS_TOKEN_KEY);
  const initialRefreshToken = localStorage.getItem(REFRESH_TOKEN_KEY);

  const store = {
    accessToken: initialAccessToken,
    refreshToken: initialRefreshToken,
    user: null as ProfileResp | null,
    isAuthenticated: !!initialAccessToken,
    isInitializing: !!initialRefreshToken,
    isLoading: false,

    // 扫码登录初始状态
    qrcodeState: 'idle' as QRCodeLoginState,
    qrcodeUrl: null as string | null,
    qrcodeCode: null as string | null,
    qrcodeExpiresIn: 0,

    setTokens: (accessToken: string, refreshToken: string) => {
      localStorage.setItem(ACCESS_TOKEN_KEY, accessToken);
      localStorage.setItem(REFRESH_TOKEN_KEY, refreshToken);
      set({ accessToken, refreshToken, isAuthenticated: true });
    },

    clearAuth: () => {
      localStorage.removeItem(ACCESS_TOKEN_KEY);
      localStorage.removeItem(REFRESH_TOKEN_KEY);
      set({ accessToken: null, refreshToken: null, user: null, isAuthenticated: false });
    },

    initializeAuth: async () => {
      const rt = get().refreshToken;
      if (!rt) {
        set({ isInitializing: false });
        return;
      }
      try {
        await get().refreshTokens();
        await get().fetchProfile();
      } catch {
        get().clearAuth();
      } finally {
        set({ isInitializing: false });
      }
    },

    login: async (username: string, password: string) => {
      set({ isLoading: true });
      try {
        const deviceId = await getDeviceId();
        const deviceName = getDeviceName();
        const resp: LoginResp = await authApi.login({
          username,
          password,
          device_type: DeviceType.Web,
          device_id: deviceId,
          device_name: deviceName,
        });
        get().setTokens(resp.access_token, resp.refresh_token);
        await get().fetchProfile();
      } finally {
        set({ isLoading: false });
      }
    },

    logout: async () => {
      try {
        await authApi.logout();
      } catch {
        // 即使 logout API 失败也要清理本地状态
      }
      get().clearAuth();
    },

    refreshTokens: async () => {
      const rt = get().refreshToken;
      if (!rt) {
        get().clearAuth();
        throw new Error('No refresh token');
      }
      const resp = await authApi.refresh({ refresh_token: rt });
      get().setTokens(resp.access_token, resp.refresh_token);
    },

    fetchProfile: async () => {
      const profile = await userApi.getProfile();
      set({ user: profile });
    },

    // ── 扫码登录 ──────────────────────────────────────────────────────────

    startQRCodeLogin: async () => {
      // 防重入
      if (_qrcodeStarting) return;
      _qrcodeStarting = true;

      // 先停止已有的轮询
      get().stopQRCodeLogin();

      set({ qrcodeState: 'loading', qrcodeUrl: null, qrcodeCode: null, qrcodeExpiresIn: 0 });

      try {
        const deviceId = await getDeviceId();
        const deviceName = getDeviceName();

        const resp = await authApi.qrcodeRequest({
          device_id: deviceId,
          device_name: deviceName,
          device_type: DeviceType.Web,
        });

        // 用 qr_url 生成二维码图片
        const qrcodeUrl = await QRCode.toDataURL(resp.qr_url, {
          width: 240,
          margin: 2,
          color: { dark: '#000000', light: '#ffffff' },
          errorCorrectionLevel: 'M',
        });

        set({
          qrcodeState: 'showing',
          qrcodeUrl,
          qrcodeCode: resp.code,
          qrcodeExpiresIn: resp.expires_in,
        });

        // 启动过期倒计时
        let remaining = resp.expires_in;
        _qrcodeExpireTimer = setInterval(() => {
          remaining -= 1;
          if (remaining <= 0) {
            get().stopQRCodeLogin();
            set({ qrcodeState: 'expired' });
            return;
          }
          set({ qrcodeExpiresIn: remaining });
        }, 1000);

        // 启动轮询
        _qrcodePollTimer = setInterval(async () => {
          const code = get().qrcodeCode;
          if (!code) return;

          try {
            const pollResp = await authApi.qrcodePoll({
              code,
              device_id: deviceId,
              device_name: deviceName,
              device_type: DeviceType.Web,
            });

            if (pollResp.status === 'confirmed' && pollResp.access_token && pollResp.refresh_token) {
              // 扫码确认成功
              get().stopQRCodeLogin();
              set({ qrcodeState: 'scanned' });
              get().setTokens(pollResp.access_token, pollResp.refresh_token);
              await get().fetchProfile();
            } else if (pollResp.status === 'expired') {
              get().stopQRCodeLogin();
              set({ qrcodeState: 'expired' });
            }
            // waiting 状态继续轮询
          } catch {
            // 轮询网络错误不中断，继续重试
          }
        }, 2000);
      } catch {
        set({ qrcodeState: 'error' });
      } finally {
        _qrcodeStarting = false;
      }
    },

    stopQRCodeLogin: () => {
      if (_qrcodePollTimer) {
        clearInterval(_qrcodePollTimer);
        _qrcodePollTimer = null;
      }
      if (_qrcodeExpireTimer) {
        clearInterval(_qrcodeExpireTimer);
        _qrcodeExpireTimer = null;
      }
    },

    refreshQRCode: async () => {
      get().stopQRCodeLogin();
      set({ qrcodeState: 'idle' });
      await get().startQRCodeLogin();
    },
  };

  // 配置 API 客户端的 auth hooks
  configureAuthHooks({
    getAccessToken: () => get().accessToken,
    getRefreshToken: () => get().refreshToken,
    onRefreshSuccess: (at, rt) => get().setTokens(at, rt),
    onRefreshFailure: () => get().clearAuth(),
  });

  return store;
});
