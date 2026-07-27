import { API } from '@/constants/api';
import { post } from './client';
import type {
  ProfileResp,
  UpdateProfileReq,
  ChangePasswordReq,
  DeviceListResp,
  KickDeviceReq,
} from '@/types/api';

/** 获取个人信息 */
export function getProfile(): Promise<ProfileResp> {
  return post<ProfileResp>(API.USER_PROFILE);
}

/** 修改个人信息 */
export function updateProfile(req: UpdateProfileReq): Promise<void> {
  return post(API.USER_UPDATE, req as unknown as Record<string, unknown>);
}

/** 修改密码 */
export function changePassword(req: ChangePasswordReq): Promise<void> {
  return post(API.USER_PASSWORD, req as unknown as Record<string, unknown>);
}

/** 查看在线设备 */
export function getDevices(): Promise<DeviceListResp> {
  return post<DeviceListResp>(API.USER_DEVICES);
}

/** 踢掉指定设备 */
export function kickDevice(req: KickDeviceReq): Promise<void> {
  return post(API.USER_KICK_DEVICE, req as unknown as Record<string, unknown>);
}
