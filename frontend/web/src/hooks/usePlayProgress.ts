import { useCallback, useRef } from 'react';
import { usePlayHistoryStore } from '@/stores/play-history';

// const STORAGE_PREFIX = 'meowtv_pp'; // 已注释：不再使用本地缓存
// const THROTTLE_MS = 5000;        // 已注释：不再节流 localStorage
const SKIP_RESTORE_THRESHOLD = 95;  // 进度>95%视为已看完，不恢复
const SEEK_DELTA_THRESHOLD = 5;     // currentTime 跳变超过 5 秒视为 seek

interface UsePlayProgressOptions {
  vodId: number;
  sourceIndex: number;
  epIndex: number;
  resourceDomain: string;
  epName: string;
  /** 流代理数据（代理开启时由 PlayPage 传入） */
  streamData?: { session?: string; current_index?: number; buffered_ahead?: number };
  /** 提供完整 VOD 元信息（退出上送时填充，避免空字符串覆盖后端数据） */
  getMeta?: () => { vodName?: string; vodPic?: string; resourceName?: string; groupKey?: string };
}

interface UsePlayProgressReturn {
  /** 在 video loadedmetadata 事件中调用，恢复上次播放位置 */
  onLoadedMetadata: (videoEl: HTMLVideoElement) => void;
  /** 在 video timeupdate 事件中调用，同步进度到后端 */
  onTimeUpdate: (videoEl: HTMLVideoElement) => void;
  /** 手动保存当前进度（页面卸载前调用） */
  saveProgress: (videoEl: HTMLVideoElement) => void;
  /** 已保存的进度百分比 0-100 */
  getSavedProgress: () => number;
}

// function buildKey(vodId: number, sourceIndex: number, epIndex: number): string { // 已注释：不再使用 localStorage
//   return `${STORAGE_PREFIX}:${vodId}:${sourceIndex}:${epIndex}`;
// }

// interface ProgressData { // 已注释：不再使用 localStorage
//   currentTime: number;
//   duration: number;
//   percent: number;
//   updatedAt: number;
// }

// function loadProgress(key: string): ProgressData | null { // 已注释：不再从 localStorage 读取
//   try {
//     const raw = localStorage.getItem(key);
//     if (!raw) return null;
//     return JSON.parse(raw) as ProgressData;
//   } catch {
//     return null;
//   }
// }

// function storeProgress(key: string, data: ProgressData): void { // 已注释：不再写入 localStorage
//   try {
//     localStorage.setItem(key, JSON.stringify(data));
//   } catch { /* ignore */ }
// }

export function usePlayProgress({
  vodId,
  sourceIndex,
  epIndex,
  resourceDomain,
  epName,
  streamData,
  getMeta,
}: UsePlayProgressOptions): UsePlayProgressReturn {
  // const lastSaveRef = useRef(0); // 已注释：不再使用 localStorage
  // const key = buildKey(vodId, sourceIndex, epIndex); // 已注释：不再使用 localStorage

  // seek 检测：记录上次 currentTime，跳变超过阈值视为 seek
  const lastCurrentTimeRef = useRef(0);

  const onLoadedMetadata = useCallback(
    (videoEl: HTMLVideoElement) => {
      // 从 store（后端数据）中恢复播放位置，不再从 localStorage 读取
      console.log('[usePlayProgress] onLoadedMetadata called', { vodId, resourceDomain, epIndex, duration: videoEl.duration });
      const record = usePlayHistoryStore.getState().getRecord(vodId, resourceDomain, epIndex);
      console.log('[usePlayProgress] getRecord result', record ? { currentTime: record.currentTime, progress: record.progress } : null);
      console.log('[usePlayProgress] store records count', usePlayHistoryStore.getState().records.length);
      if (!record) {
        // store 中暂无数据，可能 getPlayHistory 异步请求还未返回
        // 延迟重试一次，给异步请求完成的时间窗口
        setTimeout(() => {
          const retryRecord = usePlayHistoryStore.getState().getRecord(vodId, resourceDomain, epIndex);
          console.log('[usePlayProgress] retry getRecord result', retryRecord ? { currentTime: retryRecord.currentTime, progress: retryRecord.progress } : null);
          if (retryRecord && retryRecord.progress <= SKIP_RESTORE_THRESHOLD) {
            if (videoEl.duration && retryRecord.currentTime < videoEl.duration) {
              console.log('[usePlayProgress] retry seek to', retryRecord.currentTime);
              videoEl.currentTime = retryRecord.currentTime;
            }
          }
        }, 500);
        return;
      }
      if (record.progress > SKIP_RESTORE_THRESHOLD) return;
      if (videoEl.duration && record.currentTime < videoEl.duration) {
        console.log('[usePlayProgress] seek to', record.currentTime);
        videoEl.currentTime = record.currentTime;
      }
    },
    [vodId, resourceDomain, epIndex]
  );

  const onTimeUpdate = useCallback(
    (videoEl: HTMLVideoElement) => {
      const { currentTime, duration } = videoEl;
      if (!duration || duration <= 0) return;

      // seek 检测：currentTime 跳变超过阈值视为 seek，立即强制同步到后端
      const delta = Math.abs(currentTime - lastCurrentTimeRef.current);
      lastCurrentTimeRef.current = currentTime;
      const isSeek = delta > SEEK_DELTA_THRESHOLD;

      const percent = Math.round((currentTime / duration) * 10000) / 100;

      // 同步更新 store（后端同步，节流由 store 内部控制）
      // seek 时 forceSync=true 绕过 60 秒节流，让后端调度器立即感知新位置
      usePlayHistoryStore.getState().updateProgressLocal(
        vodId, resourceDomain, percent, currentTime, duration,
        sourceIndex, epIndex, epName, isSeek, streamData, getMeta?.(),
      );
    },
    [vodId, resourceDomain, sourceIndex, epIndex, epName, streamData, getMeta]
  );

  const saveProgress = useCallback(
    (videoEl: HTMLVideoElement) => {
      const { currentTime, duration } = videoEl;
      if (!duration || duration <= 0) return;

      const percent = Math.round((currentTime / duration) * 10000) / 100;
      // storeProgress(key, { currentTime, duration, percent, updatedAt: now }); // 已注释：不再写入 localStorage

      // 页面卸载时立即同步到后端（forceSync = true）
      usePlayHistoryStore.getState().updateProgressLocal(
        vodId, resourceDomain, percent, currentTime, duration,
        sourceIndex, epIndex, epName, true, streamData, getMeta?.(),
      );
    },
    [vodId, resourceDomain, sourceIndex, epIndex, epName, streamData, getMeta]
  );

  const getSavedProgress = useCallback((): number => {
    // 从 store（后端数据）获取进度，不再从 localStorage 读取
    const record = usePlayHistoryStore.getState().getRecord(vodId, resourceDomain, epIndex);
    return record?.progress ?? 0;
  }, [vodId, resourceDomain, epIndex]);

  return { onLoadedMetadata, onTimeUpdate, saveProgress, getSavedProgress };
}
