import { useState, useCallback, useRef, useEffect } from 'react';

interface UseAutoPlayNextOptions {
  /** 是否为最后一集 */
  isLastEpisode: boolean;
  /** 是否启用自动连播 */
  enabled: boolean;
  /** 切换到下一集的回调 */
  onNext: () => void;
  /** 获取当前播放时间（秒） */
  getCurrentTime: () => number;
  /** 获取视频总时长（秒） */
  getDuration: () => number;
}

interface UseAutoPlayNextReturn {
  /** 是否显示倒计时 */
  showCountdown: boolean;
  /** 倒计时剩余秒数 */
  countdownSeconds: number;
  /** 取消自动播放下一集 */
  cancelAutoPlay: () => void;
  /** 重置倒计时状态（切集后调用） */
  resetCountdown: () => void;
  /** 在 timeupdate 中调用，检测是否应触发连播 */
  checkAutoPlay: () => void;
}

const TRIGGER_BEFORE_END = 10; // 距结束 10 秒触发
const COUNTDOWN_SECONDS = 10;   // 倒计时 10 秒

export function useAutoPlayNext({
  isLastEpisode,
  enabled,
  onNext,
  getCurrentTime,
  getDuration,
}: UseAutoPlayNextOptions): UseAutoPlayNextReturn {
  const [showCountdown, setShowCountdown] = useState(false);
  const [countdownSeconds, setCountdownSeconds] = useState(COUNTDOWN_SECONDS);
  const cancelledRef = useRef(false);
  const triggeredRef = useRef(false);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const clearTimer = useCallback(() => {
    if (timerRef.current) {
      clearInterval(timerRef.current);
      timerRef.current = null;
    }
  }, []);

  const cancelAutoPlay = useCallback(() => {
    cancelledRef.current = true;
    setShowCountdown(false);
    setCountdownSeconds(COUNTDOWN_SECONDS);
    clearTimer();
  }, [clearTimer]);

  const resetCountdown = useCallback(() => {
    cancelledRef.current = false;
    triggeredRef.current = false;
    setShowCountdown(false);
    setCountdownSeconds(COUNTDOWN_SECONDS);
    clearTimer();
  }, [clearTimer]);

  // 当 enabled 或 isLastEpisode 变化时重置
  useEffect(() => {
    resetCountdown();
  }, [enabled, isLastEpisode, resetCountdown]);

  // 在 timeupdate 中调用的检测方法
  const checkAutoPlay = useCallback(() => {
    if (!enabled || isLastEpisode || cancelledRef.current || triggeredRef.current) return;

    const currentTime = getCurrentTime();
    const duration = getDuration();

    if (!duration || duration <= 0) return;

    const remaining = duration - currentTime;

    if (remaining <= TRIGGER_BEFORE_END && remaining > 0) {
      triggeredRef.current = true;
      setShowCountdown(true);
      setCountdownSeconds(COUNTDOWN_SECONDS);

      // 启动倒计时
      clearTimer();
      let countdown = COUNTDOWN_SECONDS;
      timerRef.current = setInterval(() => {
        countdown -= 1;
        if (countdown <= 0) {
          clearTimer();
          setShowCountdown(false);
          onNext();
        } else {
          setCountdownSeconds(countdown);
        }
      }, 1000);
    }
  }, [enabled, isLastEpisode, getCurrentTime, getDuration, onNext, clearTimer]);

  // 清理定时器
  useEffect(() => {
    return () => {
      clearTimer();
    };
  }, [clearTimer]);

  return {
    showCountdown,
    countdownSeconds,
    cancelAutoPlay,
    resetCountdown,
    checkAutoPlay,
  };
}
