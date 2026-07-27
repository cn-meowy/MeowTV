import { API } from '@/constants/api';
import { post } from './client';
import type {
  CreateUserReq,
  CreateUserResp,
  UpdateUserReq,
  ResetPasswordReq,
  UserListReq,
  UserListItem,
  PaginatedData,
  DeleteUserReq,
  KickUserReq,
} from '@/types/api';

/** 创建用户 */
export function createUser(req: CreateUserReq): Promise<CreateUserResp> {
  return post<CreateUserResp>(API.ADMIN_USER_CREATE, req as unknown as Record<string, unknown>);
}

/** 编辑用户 */
export function updateUser(req: UpdateUserReq): Promise<void> {
  return post(API.ADMIN_USER_UPDATE, req as unknown as Record<string, unknown>);
}

/** 重置密码 */
export function resetPassword(req: ResetPasswordReq): Promise<void> {
  return post(API.ADMIN_USER_RESET_PASSWORD, req as unknown as Record<string, unknown>);
}

/** 用户列表 */
export function getUserList(req: UserListReq): Promise<PaginatedData<UserListItem>> {
  return post<PaginatedData<UserListItem>>(API.ADMIN_USER_LIST, req as unknown as Record<string, unknown>);
}

/** 删除用户 */
export function deleteUser(req: DeleteUserReq): Promise<void> {
  return post(API.ADMIN_USER_DELETE, req as unknown as Record<string, unknown>);
}

/** 踢用户下线 */
export function kickUser(req: KickUserReq): Promise<void> {
  return post(API.ADMIN_USER_KICK, req as unknown as Record<string, unknown>);
}
