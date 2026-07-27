import { API } from '@/constants/api';
import { post } from './client';
import type {
  SearchHistoryItem,
  PlayHistoryItem,
  PlayHistoryListResp,
  FavoriteItem,
  FavoriteListResp,
  FavoriteCheckResp,
  PlayHistoryGetReq,
} from '@/types/api';

// ── 搜索历史 ────────────────────────────────────────────────────────────────

/** 获取搜索历史列表 */
export function getSearchHistoryList(limit?: number): Promise<SearchHistoryItem[]> {
  return post<SearchHistoryItem[]>(API.SEARCH_HISTORY_LIST, { limit: limit ?? 20 });
}

/** 新增搜索记录 */
export function addSearchHistory(keyword: string): Promise<SearchHistoryItem> {
  return post<SearchHistoryItem>(API.SEARCH_HISTORY_ADD, { keyword });
}

/** 删除单条搜索记录 */
export function deleteSearchHistory(id: number): Promise<void> {
  return post(API.SEARCH_HISTORY_DELETE, { id });
}

/** 清空搜索历史 */
export function clearSearchHistory(): Promise<void> {
  return post(API.SEARCH_HISTORY_CLEAR);
}

// ── 播放历史 ────────────────────────────────────────────────────────────────

/** 查询单条播放记录（记录不存在返回 null） */
export function getPlayHistory(params: PlayHistoryGetReq): Promise<PlayHistoryItem | null> {
  return post<PlayHistoryItem | null>(API.PLAY_HISTORY_GET, params as unknown as Record<string, unknown>);
}

/** 获取播放历史列表 */
export function getPlayHistoryList(limit?: number, offset?: number): Promise<PlayHistoryListResp> {
  return post<PlayHistoryListResp>(API.PLAY_HISTORY_LIST, {
    limit: limit ?? 20,
    offset: offset ?? 0,
  });
}

/** 新增/更新播放记录（完整 upsert） */
export function upsertPlayHistory(record: {
  vod_id: number;
  vod_name: string;
  vod_pic: string;
  resource_domain: string;
  resource_name: string;
  group_key: string;
  source_index: number;
  ep_index: number;
  ep_name: string;
  progress: number;
  current_time: number;
  duration: number;
}): Promise<PlayHistoryItem> {
  return post<PlayHistoryItem>(API.PLAY_HISTORY_UPSERT, record as unknown as Record<string, unknown>);
}

/** 更新播放进度（upsert 语义：记录不存在时自动创建） */
export function updatePlayProgress(params: {
  vod_id: number;
  vod_name: string;
  vod_pic: string;
  resource_domain: string;
  resource_name: string;
  group_key: string;
  source_index: number;
  ep_index: number;
  ep_name: string;
  progress: number;
  current_time: number;
  duration: number;
  // 流调度相关字段（可选，代理开启时附带）
  session?: string;
  current_index?: number;
  buffered_ahead?: number;
}): Promise<void> {
  return post(API.PLAY_HISTORY_PROGRESS, params as unknown as Record<string, unknown>);
}

/** 删除单条播放记录 */
export function deletePlayHistory(id: number): Promise<void> {
  return post(API.PLAY_HISTORY_DELETE, { id });
}

/** 清空播放历史 */
export function clearPlayHistory(): Promise<void> {
  return post(API.PLAY_HISTORY_CLEAR);
}

// ── 收藏 ────────────────────────────────────────────────────────────────────

/** 获取收藏列表 */
export function getFavoritesList(limit?: number, offset?: number, keyword?: string): Promise<FavoriteListResp> {
  return post<FavoriteListResp>(API.FAVORITES_LIST, {
    limit: limit ?? 50,
    offset: offset ?? 0,
    keyword: keyword ?? "",
  });
}

/** 添加收藏 */
export function addFavorite(record: {
  vod_id: number;
  vod_name: string;
  vod_pic: string;
  douban_id: string;
  group_key: string;
  site: string;
  resource_domain: string;
  resource_name: string;
}): Promise<FavoriteItem> {
  return post<FavoriteItem>(API.FAVORITES_ADD, record as unknown as Record<string, unknown>);
}

/** 取消收藏 */
export function removeFavorite(params: {
  vod_id: number;
  resource_domain: string;
  douban_id: string;
}): Promise<void> {
  return post(API.FAVORITES_REMOVE, params);
}

/** 切换收藏状态 */
export function toggleFavorite(record: {
  vod_id: number;
  vod_name: string;
  vod_pic: string;
  douban_id: string;
  group_key: string;
  site: string;
  resource_domain: string;
  resource_name: string;
}): Promise<FavoriteCheckResp> {
  return post<FavoriteCheckResp>(API.FAVORITES_TOGGLE, record as unknown as Record<string, unknown>);
}

/** 检查是否已收藏 */
export function checkFavorite(params: {
  vod_id: number;
  resource_domain: string;
  douban_id: string;
}): Promise<FavoriteCheckResp> {
  return post<FavoriteCheckResp>(API.FAVORITES_CHECK, params);
}

/** 清空收藏 */
export function clearFavorites(): Promise<void> {
  return post(API.FAVORITES_CLEAR);
}
