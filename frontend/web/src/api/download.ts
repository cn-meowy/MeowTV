import { API } from '@/constants/api';
import { post } from './client';
import { getTempToken } from './tempToken';
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

/**
 * 给任意 URL 追加临时 Token（用于 video 元素认证）
 *
 * /api/download/file/:id 改用临时 Token 认证（query param token），
 * 因为 Artplayer 通过 video.src 加载，无法设置 Authorization header。
 * 临时 Token 由 /api/token/temp 获取（带缓存 + 并发去重）。
 *
 * 已含 query 参数的 URL 会用 & 拼接，否则用 ? 拼接。
 */
export async function appendTempToken(url: string): Promise<string> {
  const token = await getTempToken();
  const sep = url.includes('?') ? '&' : '?';
  return `${url}${sep}token=${encodeURIComponent(token)}`;
}

/**
 * 构建已下载文件的播放 URL（异步，附加临时 Token）
 * 用于 checkDownload 命中后的本地文件播放。
 */
export async function buildDownloadFileUrlWithToken(taskId: number): Promise<string> {
  return appendTempToken(`${API.DOWNLOAD_FILE}/${taskId}`);
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
