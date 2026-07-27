import { useState, useCallback, useRef } from 'react';
import { checkM3u8Urls, type M3u8CheckResult } from '@/api/stream';

/** URL 检测状态 */
export type UrlCheckStatus = 'unchecked' | 'checking' | 'available' | 'unavailable';

/** localStorage 缓存 key 前缀 */
const CACHE_PREFIX = 'meowtv_m3u8_check:';
/** 缓存 TTL: 30 分钟 */
const CACHE_TTL_MS = 30 * 60 * 1000;

/**
 * 计算 URL 的缓存 key（简单 hash）
 */
function urlCacheKey(url: string): string {
  let hash = 0;
  for (let i = 0; i < url.length; i++) {
    const char = url.charCodeAt(i);
    hash = (hash << 5) - hash + char;
    hash = hash & hash; // Convert to 32bit integer
  }
  return `${CACHE_PREFIX}${Math.abs(hash)}`;
}

/**
 * 从 localStorage 读取缓存
 */
function readCache(url: string): { status: UrlCheckStatus; error?: string } | null {
  try {
    const raw = localStorage.getItem(urlCacheKey(url));
    if (!raw) return null;
    const data = JSON.parse(raw) as { status: UrlCheckStatus; error?: string; cachedAt: number };
    if (Date.now() - data.cachedAt > CACHE_TTL_MS) {
      localStorage.removeItem(urlCacheKey(url));
      return null;
    }
    return { status: data.status, error: data.error };
  } catch {
    return null;
  }
}

/**
 * 写入 localStorage 缓存
 */
function writeCache(url: string, status: UrlCheckStatus, error?: string): void {
  try {
    localStorage.setItem(urlCacheKey(url), JSON.stringify({
      status,
      error,
      cachedAt: Date.now(),
    }));
  } catch {
    // localStorage 满或不可用，静默忽略
  }
}

interface UseM3u8CheckReturn {
  /** URL -> 检测状态映射 */
  statusMap: Map<string, UrlCheckStatus>;
  /** URL -> 错误信息映射（仅不可用时） */
  errorMap: Map<string, string>;
  /** 是否正在检测中 */
  checking: boolean;
  /** 触发批量检测（异步，不阻塞） */
  checkUrls: (urls: string[]) => void;
  /** 检测单个 URL（返回 Promise，供播放失败时使用） */
  checkSingle: (url: string) => Promise<M3u8CheckResult>;
}

/**
 * 管理 m3u8 链接检测状态的 hook
 * - 检测结果缓存到 localStorage（TTL: 30分钟）
 * - 批量检测限制并发，每次最多 20 个 URL
 */
export function useM3u8Check(): UseM3u8CheckReturn {
  const [statusMap, setStatusMap] = useState<Map<string, UrlCheckStatus>>(() => new Map());
  const [errorMap, setErrorMap] = useState<Map<string, string>>(() => new Map());
  const [checking, setChecking] = useState(false);
  const seqRef = useRef(0); // 用于取消过期的请求

  /** 批量检测 */
  const checkUrls = useCallback((urls: string[]) => {
    if (urls.length === 0) return;

    const seq = ++seqRef.current;

    // 先从缓存中过滤出未检测的 URL
    const toCheck: string[] = [];
    const cachedResults: Map<string, { status: UrlCheckStatus; error?: string }> = new Map();

    for (const url of urls) {
      const cached = readCache(url);
      if (cached) {
        cachedResults.set(url, cached);
      } else {
        toCheck.push(url);
      }
    }

    // 立即更新已缓存的状态
    if (cachedResults.size > 0) {
      setStatusMap(prev => {
        const next = new Map(prev);
        for (const [url, result] of cachedResults) {
          next.set(url, result.status);
        }
        return next;
      });
      setErrorMap(prev => {
        const next = new Map(prev);
        for (const [url, result] of cachedResults) {
          if (result.status === 'unavailable' && result.error) {
            next.set(url, result.error);
          }
        }
        return next;
      });
    }

    if (toCheck.length === 0) return;

    // 分批检测，每批最多 20 个
    const batchSize = 20;
    const batches: string[][] = [];
    for (let i = 0; i < toCheck.length; i += batchSize) {
      batches.push(toCheck.slice(i, i + batchSize));
    }

    setChecking(true);

    // 标记为检测中
    setStatusMap(prev => {
      const next = new Map(prev);
      for (const url of toCheck) {
        next.set(url, 'checking');
      }
      return next;
    });

    // 并发执行所有批次
    Promise.all(batches.map(batch => checkM3u8Urls(batch)))
      .then(allResults => {
        if (seq !== seqRef.current) return; // 序列号已过期，跳过

        const newStatusMap = new Map<string, UrlCheckStatus>();
        const newErrorMap = new Map<string, string>();

        for (const results of allResults) {
          for (const result of results) {
            const status: UrlCheckStatus = result.available ? 'available' : 'unavailable';
            newStatusMap.set(result.url, status);
            if (!result.available && result.error) {
              newErrorMap.set(result.url, result.error);
            }
            // 写入缓存
            writeCache(result.url, status, result.error || undefined);
          }
        }

        setStatusMap(prev => {
          const next = new Map(prev);
          for (const [url, status] of newStatusMap) {
            next.set(url, status);
          }
          return next;
        });
        setErrorMap(prev => {
          const next = new Map(prev);
          for (const [url, error] of newErrorMap) {
            next.set(url, error);
          }
          return next;
        });
      })
      .catch(err => {
        console.error('[useM3u8Check] check failed:', err);
        // 检测失败的 URL 标记为 unchecked（下次会重新检测）
        if (seq !== seqRef.current) return;
        setStatusMap(prev => {
          const next = new Map(prev);
          for (const url of toCheck) {
            if (next.get(url) === 'checking') {
              next.set(url, 'unchecked');
            }
          }
          return next;
        });
      })
      .finally(() => {
        if (seq !== seqRef.current) return;
        setChecking(false);
      });
  }, []);

  /** 检测单个 URL（返回 Promise） */
  const checkSingle = useCallback(async (url: string): Promise<M3u8CheckResult> => {
    // 先检查缓存
    const cached = readCache(url);
    if (cached) {
      const result: M3u8CheckResult = {
        url,
        available: cached.status === 'available',
        status_code: cached.status === 'available' ? 200 : 0,
        error: cached.error || '',
      };
      setStatusMap(prev => new Map(prev).set(url, cached.status));
      if (cached.status === 'unavailable' && cached.error) {
        setErrorMap(prev => new Map(prev).set(url, cached.error!));
      }
      return result;
    }

    const results = await checkM3u8Urls([url]);
    const result = results[0];

    const status: UrlCheckStatus = result.available ? 'available' : 'unavailable';
    setStatusMap(prev => new Map(prev).set(url, status));
    if (!result.available && result.error) {
      setErrorMap(prev => new Map(prev).set(url, result.error));
    }
    writeCache(url, status, result.error || undefined);

    return result;
  }, []);

  return {
    statusMap,
    errorMap,
    checking,
    checkUrls,
    checkSingle,
  };
}
