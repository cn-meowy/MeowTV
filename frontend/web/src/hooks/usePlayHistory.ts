import { useCallback } from 'react';
import { usePlayHistoryStore, type PlayHistoryRecord } from '@/stores/play-history';

interface UsePlayHistoryReturn {
  /** 从后端加载播放历史（首次进入时调用） */
  fetchFromServer: () => Promise<void>;
  /** 新增或更新一条播放历史记录 */
  recordPlay: (record: PlayHistoryRecord) => void;
  /** 仅更新播放进度（只写本地，不触发后端 API） */
  updateProgress: (vodId: number, resourceDomain: string, progress: number, currentTime: number, duration: number, sourceIndex: number, epIndex: number, epName: string) => void;
  /** 删除一条播放历史记录 */
  removeRecord: (vodId: number, resourceDomain: string, epIndex: number) => void;
  /** 获取指定视频的播放历史 */
  getRecord: (vodId: number, resourceDomain: string, epIndex: number) => PlayHistoryRecord | undefined;
  /** 获取最近播放的记录列表 */
  getRecentRecords: (limit?: number) => PlayHistoryRecord[];
  /** 清空所有播放历史 */
  clearAll: () => void;
}

export function usePlayHistory(): UsePlayHistoryReturn {
  const fetchFromServer = usePlayHistoryStore((s) => s.fetchFromServer);
  const upsertRecord = usePlayHistoryStore((s) => s.upsertRecord);
  const updateProgressFromStore = usePlayHistoryStore((s) => s.updateProgressLocal);
  const removeRecord = usePlayHistoryStore((s) => s.removeRecord);
  const getRecordFromStore = usePlayHistoryStore((s) => s.getRecord);
  const getRecentRecordsFromStore = usePlayHistoryStore((s) => s.getRecentRecords);
  const clearAllStore = usePlayHistoryStore((s) => s.clearAll);

  const recordPlay = useCallback(
    (record: PlayHistoryRecord) => {
      upsertRecord({ ...record, updatedAt: Date.now() });
    },
    [upsertRecord]
  );

  const updateProgress = useCallback(
    (vodId: number, resourceDomain: string, progress: number, currentTime: number, duration: number, sourceIndex: number, epIndex: number, epName: string) => {
      updateProgressFromStore(vodId, resourceDomain, progress, currentTime, duration, sourceIndex, epIndex, epName);
    },
    [updateProgressFromStore]
  );

  const removeRecordCb = useCallback(
    (vodId: number, resourceDomain: string, epIndex: number) => {
      removeRecord(vodId, resourceDomain, epIndex);
    },
    [removeRecord]
  );

  const getRecord = useCallback(
    (vodId: number, resourceDomain: string, epIndex: number) => {
      return getRecordFromStore(vodId, resourceDomain, epIndex);
    },
    [getRecordFromStore]
  );

  const getRecentRecords = useCallback(
    (limit?: number) => {
      return getRecentRecordsFromStore(limit);
    },
    [getRecentRecordsFromStore]
  );

  const clearAll = useCallback(() => {
    clearAllStore();
  }, [clearAllStore]);

  return { fetchFromServer, recordPlay, updateProgress, removeRecord: removeRecordCb, getRecord, getRecentRecords, clearAll };
}
