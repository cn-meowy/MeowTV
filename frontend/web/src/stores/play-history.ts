import { create } from 'zustand';
import {
  getPlayHistoryList,
  upsertPlayHistory as apiUpsert,
  updatePlayProgress as apiUpdateProgress,
  deletePlayHistory as apiDelete,
  clearPlayHistory as apiClear,
} from '@/api/user-data';
import type { PlayHistoryItem } from '@/types/api';

// const STORAGE_KEY = 'meowtv_play_history'; // 已注释：不再使用本地缓存
const MAX_RECORDS = 100;
const PROGRESS_BACKEND_THROTTLE_MS = 60000; // 后端进度同步节流 60 秒

/** 进度后端同步节流 Map：key = "vodId:resourceDomain:epIndex", value = lastSyncTimestamp */
const progressThrottleMap = new Map<string, number>();

export interface PlayHistoryRecord {
  vodId: number;
  vodName: string;
  vodPic?: string;
  resourceDomain: string;
  resourceName: string;
  groupKey: string;
  sourceIndex: number;
  epIndex: number;
  epName: string;
  progress: number;      // 0-100 浮点百分比
  currentTime: number;   // 秒，浮点精度
  duration: number;      // 秒，浮点精度
  updatedAt: number;     // timestamp ms
}

interface PlayHistoryState {
  records: PlayHistoryRecord[];
  loaded: boolean;
  loading: boolean;
  /** 从后端加载播放历史 */
  fetchFromServer: () => Promise<void>;
  /** 新增/更新记录（乐观更新内存 + 异步写后端 upsert） */
  upsertRecord: (record: PlayHistoryRecord) => void;
  /** 仅更新内存记录（不写后端，用于 get 恢复进度） */
  hydrateRecord: (record: PlayHistoryRecord) => void;
  /** 仅更新进度（内存状态 + 节流后端同步） */
  updateProgressLocal: (vodId: number, resourceDomain: string, progress: number, currentTime: number, duration: number, sourceIndex: number, epIndex: number, epName: string, forceSync?: boolean, streamData?: { session?: string; current_index?: number; buffered_ahead?: number }, meta?: { vodName?: string; vodPic?: string; resourceName?: string; groupKey?: string }) => void;
  /** 删除单条记录 */
  removeRecord: (vodId: number, resourceDomain: string, epIndex: number) => void;
  /** 清空所有 */
  clearAll: () => void;
  /** 获取指定记录 */
  getRecord: (vodId: number, resourceDomain: string, epIndex: number) => PlayHistoryRecord | undefined;
  /** 获取最近记录 */
  getRecentRecords: (limit?: number) => PlayHistoryRecord[];
}

// function loadRecords(): PlayHistoryRecord[] { // 已注释：不再从 localStorage 读取
//   try {
//     const raw = localStorage.getItem(STORAGE_KEY);
//     if (!raw) return [];
//     const parsed = JSON.parse(raw);
//     return Array.isArray(parsed) ? parsed : [];
//   } catch {
//     return [];
//   }
// }
function loadRecords(): PlayHistoryRecord[] {
  return []; // 不再从 localStorage 读取，完全由后端提供
}

// function saveRecords(records: PlayHistoryRecord[]): void { // 已注释：不再写入 localStorage
//   try {
//     localStorage.setItem(STORAGE_KEY, JSON.stringify(records));
//   } catch { /* ignore */ }
// }
function saveRecords(_records: PlayHistoryRecord[]): void {
  // 不再写入 localStorage，完全由后端管理
}

/** 将后端 PlayHistoryItem 转为本地 PlayHistoryRecord */
function toItem(r: PlayHistoryItem): PlayHistoryRecord {
  return {
    vodId: r.vod_id,
    vodName: r.vod_name,
    vodPic: r.vod_pic,
    resourceDomain: r.resource_domain,
    resourceName: r.resource_name,
    groupKey: r.group_key,
    sourceIndex: r.source_index,
    epIndex: r.ep_index,
    epName: r.ep_name,
    progress: r.progress,
    currentTime: r.current_time,
    duration: r.duration,
    updatedAt: r.updated_at,
  };
}

export const usePlayHistoryStore = create<PlayHistoryState>((set, get) => ({
  records: loadRecords(),
  loaded: false,
  loading: false,

  fetchFromServer: async () => {
    if (get().loaded || get().loading) return;
    set({ loading: true });
    try {
      const resp = await getPlayHistoryList(MAX_RECORDS, 0);
      const records = resp.items.map(toItem);
      // 不再写入 localStorage
      set({ records, loaded: true, loading: false });
    } catch {
      // 后端不可用时清空本地数据
      set({ records: [], loaded: true, loading: false });
    }
  },

  upsertRecord: (record) => {
    // 乐观更新内存状态（不再写入 localStorage）
    set((state) => {
      const filtered = state.records.filter(
        (r) => !(r.vodId === record.vodId && r.resourceDomain === record.resourceDomain && r.epIndex === record.epIndex)
      );
      const updated = [record, ...filtered].slice(0, MAX_RECORDS);
      // saveRecords(updated); // 已注释：不再写入 localStorage
      return { records: updated };
    });

    // 异步写后端
    apiUpsert({
      vod_id: record.vodId,
      vod_name: record.vodName,
      vod_pic: record.vodPic ?? '',
      resource_domain: record.resourceDomain,
      resource_name: record.resourceName,
      group_key: record.groupKey,
      source_index: record.sourceIndex,
      ep_index: record.epIndex,
      ep_name: record.epName,
      progress: record.progress,
      current_time: record.currentTime,
      duration: record.duration,
    }).catch(() => {});
  },

  hydrateRecord: (record) => {
    // 仅更新内存状态（不写后端，用于 get 恢复进度）
    set((state) => {
      const filtered = state.records.filter(
        (r) => !(r.vodId === record.vodId && r.resourceDomain === record.resourceDomain && r.epIndex === record.epIndex)
      );
      const updated = [record, ...filtered].slice(0, MAX_RECORDS);
      return { records: updated };
    });
  },

  updateProgressLocal: (vodId, resourceDomain, progress, currentTime, duration, sourceIndex, epIndex, epName, forceSync = false, streamData, meta) => {
    const now = Date.now();

    // 乐观更新内存状态（不再写入 localStorage）
    set((state) => {
      const updated = state.records.map((r) => {
        if (r.vodId === vodId && r.resourceDomain === resourceDomain && r.epIndex === epIndex) {
          return { ...r, progress, currentTime, duration, sourceIndex, epIndex, epName, updatedAt: now };
        }
        return r;
      });
      // saveRecords(updated); // 已注释：不再写入 localStorage
      return { records: updated };
    });

    // 后端同步：forceSync 时立即调用，否则节流 60 秒
    const lastSync = progressThrottleMap.get(`${vodId}:${resourceDomain}:${epIndex}`) ?? 0;
    if (forceSync || now - lastSync >= PROGRESS_BACKEND_THROTTLE_MS) {
      progressThrottleMap.set(`${vodId}:${resourceDomain}:${epIndex}`, now);
      // 从当前 records 中查找完整字段，以支持 upsert（记录不存在时自动创建）
      const record = get().records.find((r) => r.vodId === vodId && r.resourceDomain === resourceDomain && r.epIndex === epIndex);
      // 元信息优先用传入 meta（来自 PlayPage detail），fallback 到 store 记录，避免空字符串覆盖后端数据
      apiUpdateProgress({
        vod_id: vodId,
        vod_name: meta?.vodName || record?.vodName || '',
        vod_pic: meta?.vodPic || record?.vodPic || '',
        resource_domain: resourceDomain,
        resource_name: meta?.resourceName || record?.resourceName || '',
        group_key: meta?.groupKey || record?.groupKey || '',
        source_index: sourceIndex,
        ep_index: epIndex,
        ep_name: epName,
        progress,
        current_time: currentTime,
        duration,
        ...streamData,
      }).catch(() => {});
    }
  },

  removeRecord: (vodId, resourceDomain, epIndex) => {
    set((state) => {
      const updated = state.records.filter(
        (r) => !(r.vodId === vodId && r.resourceDomain === resourceDomain && r.epIndex === epIndex)
      );
      // saveRecords(updated); // 已注释：不再写入 localStorage
      return { records: updated };
    });
    // 找到对应的 id 再删除 - 先从本地删，后端无法用 vodId+domain+epIndex 直接删
    // 所以使用 fetchFromServer 后重新获取以获得 id
    // 简化方案：先 fetch，再删除
    // 但这样会有竞态问题，所以改为：如果已 loaded，直接用后端删除
    // 后端 DELETE 接口需要 id，本地缓存没有 id。改用 fetch + delete
    getPlayHistoryList(MAX_RECORDS, 0).then((resp) => {
      const item = resp.items.find((i) => i.vod_id === vodId && i.resource_domain === resourceDomain && i.ep_index === epIndex);
      if (item) {
        apiDelete(item.id).catch(() => {});
      }
    }).catch(() => {});
  },

  clearAll: () => {
    // saveRecords([]); // 已注释：不再写入 localStorage
    set({ records: [] });
    apiClear().catch(() => {});
  },

  getRecord: (vodId, resourceDomain, epIndex) => {
    return get().records.find(
      (r) => r.vodId === vodId && r.resourceDomain === resourceDomain && r.epIndex === epIndex
    );
  },

  getRecentRecords: (limit = 20) => {
    return get().records.slice(0, limit);
  },
}));
