import { API } from '@/constants/api';
import { post, getAccessToken } from './client';
import type { SearchReq, SearchResultItem, SearchDoneData, SearchCompleteData, SearchErrorData, ResourceSiteItem, ResourceDetailReq, ResourceDetailResp, ResourcePageReq, ResourcePageResp, PlayEpisode, PlaySource } from '@/types/api';

/** 获取用户可用的资源站点列表 */
export function getResourceSites(): Promise<ResourceSiteItem[]> {
  return post<ResourceSiteItem[]>(API.RESOURCE_SITES, {});
}

/** SSE 搜索事件回调 */
export interface SearchCallbacks {
  onResult?: (item: SearchResultItem) => void;
  onDone?: (data: SearchDoneData) => void;
  onComplete?: (data: SearchCompleteData) => void;
  onError?: (data: SearchErrorData) => void;
}

/**
 * 执行聚合搜索（SSE 流式）
 * 使用 POST + fetch + ReadableStream 解析 SSE 事件
 */
export async function searchSSE(req: SearchReq, callbacks: SearchCallbacks, signal?: AbortSignal): Promise<void> {
  const token = getAccessToken() || '';

  const response = await fetch(API.RESOURCE_SEARCH, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
    },
    body: JSON.stringify(req),
    signal,
  });

  if (!response.ok) {
    const errorData = await response.json().catch(() => ({ msg: '搜索请求失败' }));
    callbacks.onError?.({
      resource_domain: '',
      message: errorData.msg || `搜索请求失败 (${response.status})`,
    });
    return;
  }

  const reader = response.body?.getReader();
  if (!reader) {
    callbacks.onError?.({ resource_domain: '', message: '无法读取响应流' });
    return;
  }

  const decoder = new TextDecoder();
  let buffer = '';
  let currentEventType = '';

  while (true) {
    if (signal?.aborted) break;
    const { done, value } = await reader.read();
    if (done) break;

    buffer += decoder.decode(value, { stream: true });

    // 解析 SSE 事件
    const lines = buffer.split('\n');
    buffer = '';

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];

      if (line.startsWith('event: ')) {
        currentEventType = line.slice(7).trim();
      } else if (line.startsWith('data: ')) {
        const dataStr = line.slice(6);
        try {
          const data = JSON.parse(dataStr);
          switch (currentEventType) {
            case 'result':
              callbacks.onResult?.(data as SearchResultItem);
              break;
            case 'done':
              callbacks.onDone?.(data as SearchDoneData);
              break;
            case 'complete':
              callbacks.onComplete?.(data as SearchCompleteData);
              break;
            case 'error':
              callbacks.onError?.(data as SearchErrorData);
              break;
          }
        } catch {
          // JSON 解析失败，忽略
        }
        currentEventType = '';
      } else if (line === '') {
        // 空行表示事件结束
        currentEventType = '';
      } else {
        // 不完整的行，放回 buffer
        buffer = line;
      }
    }
  }
}

/** 构建资源站图片代理 URL */
export function buildResourceImageUrl(originalUrl: string): string {
  if (!originalUrl) return '';
  return `${API.RESOURCE_IMAGE_PROXY}?url=${encodeURIComponent(originalUrl)}`;
}

/** 查询资源详情 */
export function getResourceDetail(req: ResourceDetailReq): Promise<ResourceDetailResp> {
  return post<ResourceDetailResp>(API.RESOURCE_DETAIL, req as unknown as Record<string, unknown>);
}

/** 资源分页查询 */
export function resourcePaginate(req: ResourcePageReq): Promise<ResourcePageResp> {
  return post<ResourcePageResp>(API.RESOURCE_PAGINATE, req as unknown as Record<string, unknown>);
}

/**
 * 解析 vod_play_url 字符串为单源剧集列表（兼容旧调用）
 * 格式: 第1集$url1#第2集$url2  (多源用 $$$ 分隔，只取第一段)
 */
export function parsePlayUrl(vodPlayUrl: string): PlayEpisode[] {
  const sources = parsePlaySources(vodPlayUrl);
  return sources.length > 0 ? sources[0].episodes : [];
}

/**
 * 解析 vod_play_url 字符串为多源剧集列表
 * 格式: 源1名称$第1集$url1#第2集$url2$$$源2名称$第1集$url1#第2集$url2
 * 也可以配合 vod_play_from（源名用$$$分隔）来确定每个源名称
 */
export function parsePlaySources(vodPlayUrl: string, vodPlayFrom?: string): PlaySource[] {
  if (!vodPlayUrl) return [];

  const sourceSegments = vodPlayUrl.split('$$$');
  const fromNames = vodPlayFrom ? vodPlayFrom.split('$$$') : [];

  const sources: PlaySource[] = [];

  for (let si = 0; si < sourceSegments.length; si++) {
    const segment = sourceSegments[si].trim();
    if (!segment) continue;

    const sourceName = fromNames[si]?.trim() || `线路${si + 1}`;
    const episodes: PlayEpisode[] = [];

    for (const part of segment.split('#')) {
      const trimmed = part.trim();
      if (!trimmed) continue;
      const dollarIdx = trimmed.indexOf('$');
      let epName: string;
      let epUrl: string;
      if (dollarIdx === -1) {
        epName = `第${episodes.length + 1}集`;
        epUrl = trimmed;
      } else {
        epName = trimmed.slice(0, dollarIdx).trim() || `第${episodes.length + 1}集`;
        epUrl = trimmed.slice(dollarIdx + 1).trim();
      }
      // 仅保留 m3u8 和 mp4 播放链接，过滤掉 iframe 嵌入页等不可直接播放的链接
      if (!epUrl) continue;
      const isM3u8 = epUrl.includes('.m3u8');
      const isMp4 = /\.mp4(\?.*)?$/i.test(epUrl);
      if (!isM3u8 && !isMp4) continue;
      episodes.push({ name: epName, url: epUrl });
    }

    if (episodes.length > 0) {
      sources.push({ name: sourceName, episodes });
    }
  }

  return sources;
}

// ── 分组数据缓存 ──────────────────────────────────────────────────────────

const GROUP_CACHE_PREFIX = 'meowtv_group_';

/** 缓存分组数据到 localStorage */
export function cacheGroupData(groupKey: string, items: SearchResultItem[]): void {
  try {
    localStorage.setItem(GROUP_CACHE_PREFIX + groupKey, JSON.stringify(items));
  } catch {
    // localStorage 满或不可用，静默忽略
  }
}

/** 从 localStorage 读取分组数据 */
export function getCachedGroupData(groupKey: string): SearchResultItem[] | null {
  try {
    const raw = localStorage.getItem(GROUP_CACHE_PREFIX + groupKey);
    if (!raw) return null;
    return JSON.parse(raw) as SearchResultItem[];
  } catch {
    return null;
  }
}
