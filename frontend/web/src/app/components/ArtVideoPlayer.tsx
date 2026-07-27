import { useRef, useState, useCallback, useMemo, forwardRef, useImperativeHandle, useEffect } from 'react';
import { AutoPlayCountdown } from '@/app/components/AutoPlayCountdown';
import '@/styles/artplayer-theme.css';

/** 判断 URL 是否为直链播放地址（非 iframe 嵌入） */
function isDirectPlayUrl(url: string): boolean {
  if (!url) return false;
  // m3u8 / mp4 / mkv / flv / ts 等常见直链格式
  const directPatterns = /\.(m3u8|mp4|mkv|flv|ts|f4v|mpd)(\?.*)?$/i;
  if (directPatterns.test(url)) return true;
  // 包含 m3u8 但不以 .html 结尾
  if (url.includes('.m3u8') && !url.includes('.html')) return true;
  // 纯数字 URL (某些源站用纯数字 episode URL)
  if (/^\d+$/.test(url)) return false;
  // iframe 特征：包含 /share/、/player.php、iframe 等
  const iframePatterns = /\/share\/|\/player\.php|\/iframe|embed|\.html/i;
  if (iframePatterns.test(url)) return false;
  // 默认为直链
  return true;
}

export interface ArtVideoPlayerHandle {
  /** 播放器容器 DOM，供父组件挂载 Artplayer 实例 */
  containerRef: React.RefObject<HTMLDivElement | null>;
}

interface ArtVideoPlayerProps {
  url: string;
  /** 是否为本地下载文件（不走 HLS 解析，需要 JWT 认证） */
  isLocalFile?: boolean;
  /** 连播倒计时相关 */
  showCountdown?: boolean;
  countdownSeconds?: number;
  onCancelCountdown?: () => void;
}

/**
 * 纯容器组件：只负责渲染播放器容器 DOM 和 iframe 降级模式。
 * Artplayer 实例的创建/销毁由父组件（PlayPage）主动控制。
 */
export const ArtVideoPlayer = forwardRef<ArtVideoPlayerHandle, ArtVideoPlayerProps>(
  function ArtVideoPlayer({
    url,
    isLocalFile = false,
    showCountdown = false,
    countdownSeconds = 5,
    onCancelCountdown,
  }, ref) {
    const containerRef = useRef<HTMLDivElement>(null);
    // 本地文件直接播放，否则判断是否为直链
    const directPlay = useMemo(() => isLocalFile || isDirectPlayUrl(url), [url, isLocalFile]);

    // iframe 模式的状态
    const [iframeLoaded, setIframeLoaded] = useState(false);

    // 暴露 containerRef 给父组件
    useImperativeHandle(ref, () => ({ containerRef }), []);

    // ====== 组件卸载时清理容器内残留的 video/iframe，防止后台继续播放 ======
    useEffect(() => {
        return () => {
            const container = containerRef.current;
            if (container) {
                container.querySelectorAll('video').forEach(v => {
                    try {
                        v.pause();
                        v.removeAttribute('src');
                        v.load();
                    } catch { /* ignore */ }
                });
                container.querySelectorAll('iframe').forEach(iframe => {
                    iframe.src = 'about:blank';
                });
                container.innerHTML = '';
            }
        };
    }, []);

    // ====== iframe 降级模式 ======
    const toggleFullscreen = useCallback(async () => {
      const container = containerRef.current;
      if (!container) return;
      try {
        if (document.fullscreenElement) {
          await document.exitFullscreen();
        } else {
          await container.requestFullscreen();
        }
      } catch { /* fullscreen may fail */ }
    }, []);

    // ====== 渲染 ======
    if (!url) {
      return (
        <div
          className="w-full aspect-video rounded-xl flex items-center justify-center"
          style={{ background: '#000' }}
        >
          <span className="text-sm" style={{ color: 'var(--text-muted)' }}>
            无播放地址
          </span>
        </div>
      );
    }

    return (
      <div className="relative w-full" style={{ background: '#000' }}>
        {/* 播放器容器 */}
        <div
          ref={containerRef}
          className="w-full aspect-video rounded-xl overflow-hidden"
        >
          {directPlay ? (
            /* Artplayer 会自动挂载到 containerRef */
            <div className="w-full h-full" />
          ) : (
            /* iframe 降级模式 */
            <div className="relative w-full h-full">
              {/* 加载状态指示 */}
              {!iframeLoaded && (
                <div className="absolute inset-0 flex items-center justify-center" style={{ background: '#000' }}>
                  <div className="flex items-center gap-2">
                    <div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                    <span className="text-xs text-white/50">加载播放器...</span>
                  </div>
                </div>
              )}
              <iframe
                src={url}
                className="w-full h-full border-0"
                allowFullScreen
                allow="autoplay; encrypted-media; fullscreen; picture-in-picture"
                sandbox="allow-same-origin allow-scripts allow-popups allow-forms allow-presentation allow-popups-to-escape-sandbox"
                onLoad={() => setIframeLoaded(true)}
              />
              {/* 仅保留右上角浮动全屏按钮，不遮挡第三方播放器控制栏 */}
              <button
                onClick={toggleFullscreen}
                className="absolute top-2 right-2 p-1.5 rounded-lg opacity-0 hover:opacity-100 focus:opacity-100 transition-opacity duration-200"
                style={{ background: 'rgba(0,0,0,0.5)' }}
                title="全屏"
              >
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2">
                  <path d="M8 3H5a2 2 0 0 0-2 2v3m18 0V5a2 2 0 0 0-2-2h-3m0 18h3a2 2 0 0 0 2-2v-3M3 16v3a2 2 0 0 0 2 2h3" />
                </svg>
              </button>
            </div>
          )}
        </div>

        {/* 连播倒计时覆盖层 */}
        {directPlay && (
          <AutoPlayCountdown
            visible={showCountdown}
            seconds={countdownSeconds}
            onCancel={onCancelCountdown ?? (() => {})}
          />
        )}
      </div>
    );
  }
);
