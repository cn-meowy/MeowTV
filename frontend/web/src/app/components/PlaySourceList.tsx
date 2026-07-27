import type { PlayEpisode } from "@/types/api";
import { Play } from "lucide-react";
import { useThemeStore } from "@/stores/theme";
import { THEMES } from "./Navbar";
import { Tooltip, TooltipContent, TooltipTrigger } from "./ui/tooltip";
import type { UrlCheckStatus } from "@/hooks/useM3u8Check";

interface PlaySourceListProps {
  episodes: PlayEpisode[];
  /** 点击剧集回调，传入剧集索引 */
  onEpisodeClick?: (index: number) => void;
  /** URL 检测状态映射 */
  urlCheckStatuses?: Map<string, UrlCheckStatus>;
  /** URL 检测错误信息映射 */
  urlCheckErrors?: Map<string, string>;
}

export function PlaySourceList({
  episodes,
  onEpisodeClick,
  urlCheckStatuses,
  urlCheckErrors,
}: PlaySourceListProps) {
  const activeTheme = useThemeStore((s) => s.activeTheme);
  const theme = THEMES[activeTheme];

  if (episodes.length === 0) return null;

  return (
    <div
      className="rounded-xl p-4"
      style={{ background: "var(--bg-surface)", border: "1px solid var(--border-default)" }}
    >
      <h3
        className="text-xs mb-3"
        style={{ color: "var(--text-muted)", fontFamily: "var(--font-display)", fontWeight: 600 }}
      >
        剧集列表 · 共{episodes.length}集
      </h3>
      <div className="grid grid-cols-4 sm:grid-cols-6 md:grid-cols-8 lg:grid-cols-10 gap-2">
        {episodes.map((ep, idx) => {
          // 获取链接检测状态
          const checkStatus = urlCheckStatuses?.get(ep.url);
          const checkError = urlCheckErrors?.get(ep.url);
          const isUnavailable = checkStatus === "unavailable";

          // 构建按钮样式（考虑链接不可用时的红色虚线边框）
          const buttonStyle: React.CSSProperties = {
            background: "var(--bg-elevated)",
            color: "var(--text-muted)",
            border: isUnavailable ? "1px dashed #ef4444" : "1px solid var(--border-default)",
            fontFamily: "var(--font-display)",
          };

          // 构建 tooltip 内容
          const tooltipContent =
            checkStatus === "unavailable" && checkError
              ? `链接不可用: ${checkError}`
              : checkStatus === "available"
                ? "链接可用"
                : checkStatus === "checking"
                  ? "检测中..."
                  : ep.name;

          const button = (
            <button
              key={idx}
              onClick={() => onEpisodeClick?.(idx)}
              className="relative flex items-center justify-center gap-1 px-2 py-2 rounded-lg text-xs transition-all duration-200 cursor-pointer"
              style={buttonStyle}
              onMouseEnter={(e) => {
                e.currentTarget.style.background = theme.subtle;
                e.currentTarget.style.color = theme.from;
                e.currentTarget.style.borderColor = isUnavailable ? "#ef4444" : `${theme.from}40`;
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.background = "var(--bg-elevated)";
                e.currentTarget.style.color = "var(--text-muted)";
                e.currentTarget.style.borderColor = isUnavailable ? "#ef4444" : "var(--border-default)";
              }}
              title={tooltipContent}
            >
              <Play size={9} style={{ flexShrink: 0 }} />
              <span className="truncate">{ep.name}</span>

              {/* 链接状态指示点 */}
              {checkStatus && checkStatus !== "unchecked" && (
                <span
                  className={`absolute top-0.5 right-0.5 w-1.5 h-1.5 rounded-full ${
                    checkStatus === "available"
                      ? "bg-green-500"
                      : checkStatus === "unavailable"
                        ? "bg-red-500"
                        : "bg-gray-400 animate-pulse"
                  }`}
                />
              )}
            </button>
          );

          // 如果有错误信息，用 Tooltip 包裹
          if (checkStatus === "unavailable" && checkError) {
            return (
              <Tooltip key={idx}>
                <TooltipTrigger asChild>{button}</TooltipTrigger>
                <TooltipContent side="top" className="max-w-xs">
                  <p className="text-xs text-red-400">链接不可用</p>
                  <p className="text-xs text-red-300">{checkError}</p>
                </TooltipContent>
              </Tooltip>
            );
          }

          return button;
        })}
      </div>
    </div>
  );
}
