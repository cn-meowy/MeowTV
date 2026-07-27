import { useState, useEffect, useCallback, useRef } from 'react';
import { getDownloadList } from '@/api/download';
import type { DownloadTaskItem, DownloadStatus } from '@/types/api';

/** 下载状态是否为终态（不再变化） */
export function isTerminalStatus(status: DownloadStatus): boolean {
  return status === 4 || status === 5 || status === 6; // Completed, Failed, Cancelled
}

/** 获取状态显示文本 */
export function getStatusLabel(status: DownloadStatus): string {
  switch (status) {
    case 0: return '排队中';
    case 1: return '解析中';
    case 2: return '下载中';
    case 3: return '合并中';
    case 4: return '已完成';
    case 5: return '失败';
    case 6: return '已取消';
    default: return '未知';
  }
}

/** 格式化文件大小 */
export function formatFileSize(bytes: number): string {
  if (bytes === 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(1024));
  return (bytes / Math.pow(1024, i)).toFixed(1) + ' ' + units[i];
}

interface UseDownloadTasksOptions {
  /** 轮询间隔 ms，默认 3000，设为 0 则不轮询 */
  interval?: number;
  /** 按状态过滤 */
  status?: number;
  /** 每页数量 */
  limit?: number;
}

interface UseDownloadTasksReturn {
  tasks: DownloadTaskItem[];
  total: number;
  loading: boolean;
  refresh: () => Promise<void>;
  /** 静默刷新，不改变 loading 状态 */
  silentRefresh: () => Promise<void>;
  /** 是否有活跃任务（非终态） */
  hasActiveTasks: boolean;
}

export function useDownloadTasks(options?: UseDownloadTasksOptions): UseDownloadTasksReturn {
  const interval = options?.interval ?? 3000;
  const [tasks, setTasks] = useState<DownloadTaskItem[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(false);
  const timerRef = useRef<ReturnType<typeof setInterval>>();

  const refresh = useCallback(async () => {
    try {
      setLoading(true);
      const resp = await getDownloadList(options?.status, options?.limit ?? 50, 0);
      setTasks(resp.items);
      setTotal(resp.total);
    } catch {
      // 静默处理
    } finally {
      setLoading(false);
    }
  }, [options?.status, options?.limit]);

  /** 静默刷新，不改变 loading 状态（用于轮询和操作后刷新） */
  const silentRefresh = useCallback(async () => {
    try {
      const resp = await getDownloadList(options?.status, options?.limit ?? 50, 0);
      setTasks(resp.items);
      setTotal(resp.total);
    } catch {
      // 静默处理
    }
  }, [options?.status, options?.limit]);

  // 初次加载 + 轮询
  useEffect(() => {
    refresh();
    if (interval > 0) {
      timerRef.current = setInterval(silentRefresh, interval);
    }
    return () => {
      if (timerRef.current) clearInterval(timerRef.current);
    };
  }, [refresh, silentRefresh, interval]);

  const hasActiveTasks = tasks.some((t) => !isTerminalStatus(t.status));

  return { tasks, total, loading, refresh, silentRefresh, hasActiveTasks };
}
