import { API } from '@/constants/api';
import { getConfigList } from './config';
import { post } from './client';
import { getTempToken } from './tempToken';
import type { StreamConfig } from '@/types/api';

/**
 * 将原始 m3u8 URL 转换为代理 URL（不含 token）
 * 格式: /api/stream/proxy/m3u8?url=<encoded_url>
 * 注意：token 需要另外通过 getTempToken() 获取并拼接到 URL
 */
export function buildProxyM3u8Url(originalUrl: string): string {
  const encoded = encodeURIComponent(originalUrl);
  return `${API.STREAM_PROXY_M3U8}?url=${encoded}`;
}

/**
 * 将原始 m3u8 URL 转换为带临时 token 的代理 URL（异步）
 * 格式: /api/stream/proxy/m3u8?url=<encoded_url>&token=<temp_token>
 * 临时 token 由 /api/token/temp 接口生成，用于替代 JWT 在 URL 中暴露
 * 适用于 Apple TV 等无法设置自定义 HTTP 头的客户端
 */
export async function buildProxyM3u8UrlWithToken(originalUrl: string): Promise<string> {
  const encoded = encodeURIComponent(originalUrl);
  const token = await getTempToken();
  return `${API.STREAM_PROXY_M3U8}?url=${encoded}&token=${encodeURIComponent(token)}`;
}

/**
 * 从代理 m3u8 内容中提取 session key
 * 后端重写后的 m3u8 中 TS URL 格式为：
 *   /api/stream/proxy/ts?session=<key>&index=<N>
 * 因此可以从任意一个 TS URL 的 query string 中提取 session 参数
 */
export function extractSessionFromM3u8(m3u8Content: string): string | null {
  // 匹配 /api/stream/proxy/ts?session=<key>&index=...
  const match = m3u8Content.match(/[?&]session=([^&]+)/);
  return match ? match[1] : null;
}

/**
 * 判断 URL 是否为 m3u8 地址
 */
export function isM3u8Url(url: string): boolean {
  if (!url) return false;
  const lower = url.toLowerCase();
  return (
    lower.includes('.m3u8') ||
    lower.includes('.m3u8?') ||
    lower.endsWith('.m3u8')
  );
}

/**
 * 获取流代理配置（通过 sys_config 统一接口）
 * 读取 config_group = "stream" 的 stream_config 配置项
 */
export async function getStreamConfig(): Promise<StreamConfig> {
  try {
    const list = await getConfigList({ group: 'stream' });
    const streamConfigItem = list?.find((item) => item.config_key === 'stream_config');
    if (!streamConfigItem) {
      // 配置不存在，返回默认值
      return {
        enabled: false,
        bufferSize: 20,
        generalWorkers: 5,
        maxWorkers: 8,
        autoSave: false,
        maxDiskCacheMB: 10240,
      };
    }

    const cfg = streamConfigItem;
    return {
      // enabled 字段对应 value5（"1"/"true" 为启用）
      enabled: cfg.value5 === '1' || cfg.value5 === 'true',
      // value1: buffer_size
      bufferSize: parseInt(cfg.value1 || '0', 10) || 20,
      // value2: general_workers
      generalWorkers: parseInt(cfg.value2 || '0', 10) || 5,
      // value3: max_workers
      maxWorkers: parseInt(cfg.value3 || '0', 10) || 8,
      // value4: auto_save
      autoSave: cfg.value4 === '1' || cfg.value4 === 'true',
      // value6: max_disk_cache_mb
      maxDiskCacheMB: parseInt(cfg.value6 || '0', 10) || 10240,
    };
  } catch {
    // 获取失败时返回默认值，不使用代理
    return {
      enabled: false,
      bufferSize: 20,
      generalWorkers: 5,
      maxWorkers: 8,
      autoSave: false,
      maxDiskCacheMB: 10240,
    };
  }
}

/**
 * M3U8 链接检测结果
 */
export interface M3u8CheckResult {
  url: string;
  available: boolean;
  status_code: number;
  error: string;
}

/**
 * 批量检测 m3u8 链接可用性
 * 使用 POST 请求，后端通过 HEAD 并发检测
 */
export async function checkM3u8Urls(urls: string[]): Promise<M3u8CheckResult[]> {
  const resp = await post<{ results: M3u8CheckResult[] }>(API.STREAM_CHECK, { urls });
  return resp.results;
}
