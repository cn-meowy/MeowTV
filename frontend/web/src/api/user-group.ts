import { API } from '@/constants/api';
import { post } from './client';
import type {
  UserGroupListReq,
  UserGroupListResp,
  CreateUserGroupReq,
  UpdateUserGroupReq,
  DeleteUserGroupReq,
  GroupDetailResp,
  SetGroupResourcesReq,
  SetUserGroupReq,
} from '@/types/api';

/** 用户组列表 */
export function getUserGroupList(req: UserGroupListReq): Promise<UserGroupListResp> {
  return post<UserGroupListResp>(API.ADMIN_GROUP_LIST, req as unknown as Record<string, unknown>);
}

/** 创建用户组 */
export function createUserGroup(req: CreateUserGroupReq): Promise<void> {
  return post(API.ADMIN_GROUP_CREATE, req as unknown as Record<string, unknown>);
}

/** 更新用户组 */
export function updateUserGroup(req: UpdateUserGroupReq): Promise<void> {
  return post(API.ADMIN_GROUP_UPDATE, req as unknown as Record<string, unknown>);
}

/** 删除用户组 */
export function deleteUserGroup(req: DeleteUserGroupReq): Promise<void> {
  return post(API.ADMIN_GROUP_DELETE, req as unknown as Record<string, unknown>);
}

/** 用户组详情 */
export function getGroupDetail(req: { id: number }): Promise<GroupDetailResp> {
  return post<GroupDetailResp>(API.ADMIN_GROUP_DETAIL, req as unknown as Record<string, unknown>);
}

/** 设置用户组关联资源站点 */
export function setGroupResources(req: SetGroupResourcesReq): Promise<void> {
  return post(API.ADMIN_GROUP_SET_RESOURCES, req as unknown as Record<string, unknown>);
}

/** 设置用户所属用户组 */
export function setUserGroup(req: SetUserGroupReq): Promise<void> {
  return post(API.ADMIN_GROUP_SET_USER, req as unknown as Record<string, unknown>);
}
