import { API } from '@/constants/api';
import { post } from './client';
import { useAuthStore } from '@/stores/auth';
import type {
  DownloadCreateReq,
  DownloadCreateResp,
  DownloadListResp,
  DownloadCheckReq,
  DownloadCheckResp,
  DownloadConfigResp,
  DownloadConfigUpdateReq,
} from '@/types/api';

// ── 用户端 ──────────────────────────────────────────────────────────────────

/** 创建下载任务 */
export function createDownload(req: DownloadCreateReq): Promise<DownloadCreateResp> {
  return post<DownloadCreateResp>(API.DOWNLOAD_CREATE, req as unknown as Record<string, unknown>);
}

/** 获取下载任务列表 */
export function getDownloadList(status?: number, limit?: number, offset?: number): Promise<DownloadListResp> {
  return post<DownloadListResp>(API.DOWNLOAD_LIST, {
    status,
    limit: limit ?? 50,
    offset: offset ?? 0,
  });
}

/** 取消下载任务 */
export function cancelDownload(taskId: number): Promise<void> {
  return post(API.DOWNLOAD_CANCEL, { task_id: taskId });
}

/** 删除下载任务 */
export function deleteDownload(taskId: number): Promise<void> {
  return post(API.DOWNLOAD_DELETE, { task_id: taskId });
}

/** 重试下载任务 */
export function retryDownload(taskId: number): Promise<void> {
  return post(API.DOWNLOAD_RETRY, { task_id: taskId });
}

/** 检查是否有本地下载文件 */
export function checkDownload(req: DownloadCheckReq): Promise<DownloadCheckResp> {
  return post<DownloadCheckResp>(API.DOWNLOAD_CHECK, req as unknown as Record<string, unknown>);
}

/** 获取已下载文件的播放 URL（附加 JWT token 用于 video 元素认证） */
export function getDownloadFileUrl(taskId: number): string {
  const token = useAuthStore.getState().accessToken || '';
  return `${API.DOWNLOAD_FILE}/${taskId}${token ? `?token=${encodeURIComponent(token)}` : ''}`;
}

// ── 管理端 ──────────────────────────────────────────────────────────────────

/** 管理端获取所有下载任务 */
export function adminGetDownloadList(status?: number, limit?: number, offset?: number): Promise<DownloadListResp> {
  return post<DownloadListResp>(API.ADMIN_DOWNLOAD_LIST, {
    status,
    limit: limit ?? 50,
    offset: offset ?? 0,
  });
}

/** 管理端获取下载配置 */
export function adminGetDownloadConfig(): Promise<DownloadConfigResp> {
  return post<DownloadConfigResp>(API.ADMIN_DOWNLOAD_CONFIG);
}

/** 管理端更新下载配置 */
export function adminUpdateDownloadConfig(req: DownloadConfigUpdateReq): Promise<void> {
  return post(API.ADMIN_DOWNLOAD_CONFIG_UPDATE, req as unknown as Record<string, unknown>);
}
