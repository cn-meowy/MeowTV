import { API } from '@/constants/api';
import { post } from './client';
import type { LoginReq, LoginResp, RefreshReq, RefreshResp, QRCodeRequestReq, QRCodeRequestResp, QRCodePollReq, QRCodePollResp } from '@/types/api';

/** 账号密码登录 */
export function login(req: LoginReq): Promise<LoginResp> {
  return post<LoginResp>(API.AUTH_LOGIN, req as unknown as Record<string, unknown>);
}

/** 刷新 Token */
export function refresh(req: RefreshReq): Promise<RefreshResp> {
  return post<RefreshResp>(API.AUTH_REFRESH, req as unknown as Record<string, unknown>);
}

/** 登出 */
export function logout(): Promise<void> {
  return post(API.AUTH_LOGOUT);
}

/** 请求扫码登录码 */
export function qrcodeRequest(req: QRCodeRequestReq): Promise<QRCodeRequestResp> {
  return post<QRCodeRequestResp>(API.AUTH_QRCODE_REQUEST, req as unknown as Record<string, unknown>);
}

/** 轮询扫码登录状态 */
export function qrcodePoll(req: QRCodePollReq): Promise<QRCodePollResp> {
  return post<QRCodePollResp>(API.AUTH_QRCODE_POLL, req as unknown as Record<string, unknown>);
}
