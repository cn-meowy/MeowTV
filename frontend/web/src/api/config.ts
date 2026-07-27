import { API } from '@/constants/api';
import { post } from './client';
import type {
  ConfigListReq, ConfigListResp,
  ConfigCreateReq, ConfigUpdateReq, ConfigDeleteReq,
  SubscribeFetchResp,
} from '@/types/api';

/** 获取配置列表（按 group） */
export function getConfigList(req: ConfigListReq): Promise<ConfigListResp> {
  return post<ConfigListResp>(API.ADMIN_CONFIG_LIST, req as unknown as Record<string, unknown>);
}

/** 创建配置项 */
export function createConfig(req: ConfigCreateReq): Promise<void> {
  return post(API.ADMIN_CONFIG_CREATE, req as unknown as Record<string, unknown>);
}

/** 更新配置项（按 config_key） */
export function updateConfig(req: ConfigUpdateReq): Promise<void> {
  return post(API.ADMIN_CONFIG_UPDATE, req as unknown as Record<string, unknown>);
}

/** 删除配置项 */
export function deleteConfig(req: ConfigDeleteReq): Promise<void> {
  return post(API.ADMIN_CONFIG_DELETE, req as unknown as Record<string, unknown>);
}

/** 刷新配置缓存 */
export function refreshConfigCache(): Promise<void> {
  return post(API.ADMIN_CONFIG_REFRESH_CACHE);
}

/** 手动拉取订阅 */
export function fetchSubscribe(): Promise<SubscribeFetchResp> {
  return post<SubscribeFetchResp>(API.ADMIN_RESOURCE_SUBSCRIBE_FETCH);
}

/** 测试代理连通性 */
export function testProxyConnectivity(): Promise<string> {
  return post<string>(API.ADMIN_RESOURCE_PROXY_TEST);
}
