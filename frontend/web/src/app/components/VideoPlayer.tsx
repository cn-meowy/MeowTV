import { useState, useEffect, useRef, useCallback } from "react";
import { AlertCircle, Maximize, Minimize, Volume2, VolumeX } from "lucide-react";
import { useThemeStore } from "@/stores/theme";
import { THEMES } from "./Navbar";

interface VideoPlayerProps {
  url: string;
  episodeName?: string;
}

function isDirectPlayUrl(url: string): boolean {
  const lower = url.toLowerCase();
  return (
    lower.includes(".m3u8") ||
    lower.endsWith(".mp4") ||
    lower.endsWith(".webm") ||
    lower.endsWith(".ogg") ||
    lower.includes("m3u8?") ||
    lower.includes(".mp4?")
  );
}

export function VideoPlayer({ url, episodeName }: VideoPlayerProps) {
  const activeTheme = useThemeStore((s) => s.activeTheme);
  const theme = THEMES[activeTheme];
  const containerRef = useRef<HTMLDivElement>(null);
  const videoRef = useRef<HTMLVideoElement>(null);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const hlsRef = useRef<any>(null);

  const [isFullscreen, setIsFullscreen] = useState(false);
  const [isMuted, setIsMuted] = useState(false);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);

  const destroyHls = useCallback(() => {
    if (hlsRef.current) {
      hlsRef.current.destroy();
      hlsRef.current = null;
    }
  }, []);

  useEffect(() => {
    if (!url || !isDirectPlayUrl(url)) return;
    const video = videoRef.current;
    if (!video) return;

    setLoading(true);
    setError("");

    const isNativeHls = video.canPlayType("application/vnd.apple.mpegurl") !== "";

    if (isNativeHls) {
      video.src = url;
      video.play().catch(() => {});
    } else {
      import("hls.js")
        .then(({ default: Hls }) => {
          if (!video) return;
          if (Hls.isSupported()) {
            destroyHls();
            const hls = new Hls({ enableWorker: true, lowLatencyMode: true });
            hlsRef.current = hls;
            hls.loadSource(url);
            hls.attachMedia(video);
            hls.on(Hls.Events.MANIFEST_PARSED, () => {
              video.play().catch(() => {});
            });
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            hls.on(Hls.Events.ERROR, (_event: string, data: any) => {
              if (data.fatal) {
                switch (data.type) {
                  case Hls.ErrorTypes.NETWORK_ERROR:
                    setError("网络错误，无法加载视频流");
                    break;
                  case Hls.ErrorTypes.MEDIA_ERROR:
                    setError("媒体解码错误");
                    break;
                  default:
                    setError("播放出错");
                    hls.destroy();
                    break;
                }
              }
            });
          } else {
            setError("当前浏览器不支持 HLS 播放");
          }
        })
        .catch(() => {
          setError("HLS.js 加载失败");
        });
    }

    return () => {
      destroyHls();
      // 清空 video 源，防止 HLS 销毁后原生 video 元素仍尝试加载
      if (videoRef.current) {
        videoRef.current.pause();
        videoRef.current.removeAttribute('src');
        videoRef.current.load();
      }
    };
  }, [url, destroyHls]);

  const handleCanPlay = () => setLoading(false);
  const handleWaiting = () => setLoading(true);
  const handlePlaying = () => setLoading(false);
  const handleError = () => {
    if (isDirectPlayUrl(url)) {
      setError("视频加载失败，请尝试切换线路");
    }
    setLoading(false);
  };

  const toggleFullscreen = async () => {
    if (!containerRef.current) return;
    try {
      if (!document.fullscreenElement) {
        await containerRef.current.requestFullscreen();
      } else {
        await document.exitFullscreen();
      }
    } catch {
      // 全屏 API 不可用
    }
  };

  const toggleMute = () => {
    if (videoRef.current) {
      videoRef.current.muted = !videoRef.current.muted;
      setIsMuted(!isMuted);
    }
  };

  useEffect(() => {
    const onFsChange = () => setIsFullscreen(!!document.fullscreenElement);
    document.addEventListener("fullscreenchange", onFsChange);
    return () => document.removeEventListener("fullscreenchange", onFsChange);
  }, []);

  if (!url) {
    return (
      <div
        className="relative w-full aspect-video rounded-xl overflow-hidden flex items-center justify-center"
        style={{ background: "var(--bg-surface-strong)", border: "1px solid var(--border-default)" }}
      >
        <div className="text-center">
          <AlertCircle size={48} style={{ color: "var(--text-tertiary)", margin: "0 auto" }} />
          <p className="mt-3 text-sm" style={{ color: "var(--text-secondary)" }}>请选择剧集开始播放</p>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div
        className="relative w-full aspect-video rounded-xl overflow-hidden flex items-center justify-center"
        style={{ background: "var(--bg-surface-strong)", border: "1px solid var(--border-default)" }}
      >
        <div className="text-center">
          <AlertCircle size={48} style={{ color: "#fb7185", margin: "0 auto" }} />
          <p className="mt-3 text-sm" style={{ color: "#fb7185" }}>{error}</p>
          <p className="mt-1 text-xs" style={{ color: "var(--text-secondary)" }}>请尝试切换其他线路或剧集</p>
        </div>
      </div>
    );
  }

  const directPlay = isDirectPlayUrl(url);

  return (
    <div
      ref={containerRef}
      className="relative w-full aspect-video rounded-xl overflow-hidden group"
      style={{ background: "#000", border: "1px solid var(--border-default)" }}
    >
      {/* 剧集名称标签 */}
      {episodeName && (
        <div
          className="absolute top-3 left-3 z-20 px-2.5 py-1 rounded-lg text-xs pointer-events-none"
          style={{
            background: "rgba(0,0,0,0.7)",
            backdropFilter: "blur(8px)",
            color: "rgba(255,255,255,0.8)",
            fontFamily: "var(--font-display)",
          }}
        >
          {episodeName}
        </div>
      )}

      {/* 加载指示器 */}
      {loading && directPlay && (
        <div
          className="absolute inset-0 z-10 flex items-center justify-center"
          style={{ background: "rgba(0,0,0,0.3)" }}
        >
          <div
            className="w-10 h-10 rounded-full border-2 border-t-transparent animate-spin"
            style={{ borderColor: `${theme.from}40`, borderTopColor: "transparent" }}
          />
        </div>
      )}

      {/* 直链播放 */}
      {directPlay && (
        <video
          ref={videoRef}
          className="w-full h-full object-contain"
          controls
          playsInline
          autoPlay
          onCanPlay={handleCanPlay}
          onWaiting={handleWaiting}
          onPlaying={handlePlaying}
          onError={handleError}
          style={{ background: "#000" }}
        />
      )}

      {/* iframe 嵌入播放 */}
      {!directPlay && (
        <iframe
          src={url}
          className="w-full h-full border-0"
          allowFullScreen
          allow="autoplay; encrypted-media; fullscreen; picture-in-picture"
          sandbox="allow-same-origin allow-scripts allow-popups allow-forms allow-presentation"
          onLoad={() => setLoading(false)}
          style={{ background: "#000" }}
        />
      )}

      {/* iframe 模式下的浮动控制栏 */}
      {!directPlay && (
        <div
          className="absolute bottom-0 left-0 right-0 z-20 flex items-center justify-end px-4 py-2 opacity-0 group-hover:opacity-100 transition-opacity duration-300"
          style={{ background: "linear-gradient(transparent, rgba(0,0,0,0.8))" }}
        >
          <div className="flex items-center gap-3">
            <button
              onClick={toggleMute}
              className="p-1.5 rounded-lg transition-colors"
              style={{ color: "rgba(255,255,255,0.6)" }}
            >
              {isMuted ? <VolumeX size={16} /> : <Volume2 size={16} />}
            </button>
            <button
              onClick={toggleFullscreen}
              className="p-1.5 rounded-lg transition-colors"
              style={{ color: "rgba(255,255,255,0.6)" }}
            >
              {isFullscreen ? <Minimize size={16} /> : <Maximize size={16} />}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
