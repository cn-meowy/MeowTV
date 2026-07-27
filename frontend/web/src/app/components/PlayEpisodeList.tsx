import { useState, useMemo, useCallback } from "react";
import { ArrowUpDown, ChevronDown, ChevronUp } from "lucide-react";
import type { PlayEpisode } from "@/types/api";
import { useThemeStore } from "@/stores/theme";
import { THEMES } from "./Navbar";
import { EpisodeGroupNav } from "./EpisodeGroupNav";
import { Tooltip, TooltipContent, TooltipTrigger } from "./ui/tooltip";
import type { UrlCheckStatus } from "@/hooks/useM3u8Check";

interface PlayEpisodeListProps {
  episodes: PlayEpisode[];
  activeIndex: number;
  onSelect: (index: number) => void;
  /** 当前 vodId，用于查询每集播放进度 */
  vodId?: number;
  /** 当前 sourceIndex，用于查询每集播放进度 */
  sourceIndex?: number;
  /** URL 检测状态映射 */
  urlCheckStatuses?: Map<string, UrlCheckStatus>;
  /** URL 检测错误信息映射 */
  urlCheckErrors?: Map<string, string>;
}

/** 剧集列表折叠阈值，超过此数量自动折叠 */
const COLLAPSE_THRESHOLD = 24;
/** 分组大小，与 EpisodeGroupNav 保持一致 */
const GROUP_SIZE = 20;

/**
 * 从 localStorage 读取某集的播放进度百分比
 */
function getEpProgress(vodId: number, sourceIndex: number, epIndex: number): number {
  try {
    const key = `meowtv_pp:${vodId}:${sourceIndex}:${epIndex}`;
    const raw = localStorage.getItem(key);
    if (!raw) return 0;
    const data = JSON.parse(raw);
    return typeof data.percent === "number" ? data.percent : 0;
  } catch {
    return 0;
  }
}

export function PlayEpisodeList({
  episodes,
  activeIndex,
  onSelect,
  vodId,
  sourceIndex,
  urlCheckStatuses,
  urlCheckErrors,
}: PlayEpisodeListProps) {
  const activeTheme = useThemeStore((s) => s.activeTheme);
  const theme = THEMES[activeTheme];

  const [reversed, setReversed] = useState(false);
  const [expanded, setExpanded] = useState(false);
  const [activeGroupStart, setActiveGroupStart] = useState(() => {
    // 初始化时定位到当前集所在分组
    const groupIdx = Math.floor(activeIndex / GROUP_SIZE);
    return groupIdx * GROUP_SIZE;
  });

  // 当 activeIndex 变化时，自动定位到对应分组
  useMemo(() => {
    const groupIdx = Math.floor(activeIndex / GROUP_SIZE);
    const newStart = groupIdx * GROUP_SIZE;
    if (newStart !== activeGroupStart) {
      setActiveGroupStart(newStart);
    }
  }, [activeIndex]);

  const displayEpisodes = useMemo(() => {
    const list = reversed ? [...episodes].reverse() : episodes;
    if (!expanded && list.length > COLLAPSE_THRESHOLD) {
      return list.slice(0, COLLAPSE_THRESHOLD);
    }
    return list;
  }, [episodes, reversed, expanded]);

  const hasMore = episodes.length > COLLAPSE_THRESHOLD && !expanded;

  // 分组导航回调：跳到对应分组的第一集
  const handleGroupSelect = useCallback(
    (index: number) => {
      setActiveGroupStart(index);
      // 如果折叠状态，展开以显示目标分组
      if (!expanded && episodes.length > COLLAPSE_THRESHOLD) {
        setExpanded(true);
      }
    },
    [expanded, episodes.length]
  );

  if (episodes.length === 0) {
    return (
      <div
        className="rounded-xl p-4 text-center"
        style={{ background: "var(--bg-surface)", border: "1px solid var(--border-default)" }}
      >
        <p className="text-xs" style={{ color: "var(--text-secondary)" }}>暂无剧集</p>
      </div>
    );
  }

  return (
    <div
      className="rounded-xl p-4"
      style={{ background: "var(--bg-surface)", border: "1px solid var(--border-default)" }}
    >
      {/* 标题栏 */}
      <div className="flex items-center justify-between mb-3">
        <h3
          className="text-xs"
          style={{ color: "var(--text-muted)", fontFamily: "var(--font-display)", fontWeight: 600 }}
        >
          剧集列表 · 共 {episodes.length} 集
        </h3>
        <button
          onClick={() => setReversed(!reversed)}
          className="flex items-center gap-1 text-xs px-2 py-1 rounded-lg transition-all duration-200"
          style={{
            color: reversed ? theme.from : "var(--text-muted)",
            background: reversed ? theme.subtle : "transparent",
          }}
        >
          <ArrowUpDown size={11} />
          <span style={{ fontFamily: "var(--font-display)" }}>{reversed ? "倒序" : "正序"}</span>
        </button>
      </div>

      {/* 分组导航（>20集时显示） */}
      <div className="mb-3">
        <EpisodeGroupNav
          totalEpisodes={episodes.length}
          activeIndex={activeIndex}
          groupSize={GROUP_SIZE}
          onSelect={handleGroupSelect}
        />
      </div>

      {/* 剧集网格 */}
      <div className="grid grid-cols-4 sm:grid-cols-6 md:grid-cols-8 lg:grid-cols-8 xl:grid-cols-10 gap-1.5">
        {displayEpisodes.map((ep, idx) => {
          // 计算原始索引（用于 onSelect）
          const originalIdx = reversed ? episodes.length - 1 - idx : idx;
          const isActive = originalIdx === activeIndex;

          // 读取该集播放进度
          const epProgress =
            vodId !== undefined && sourceIndex !== undefined
              ? getEpProgress(vodId, sourceIndex, originalIdx)
              : 0;

          // 获取链接检测状态
          const checkStatus = urlCheckStatuses?.get(ep.url);
          const checkError = urlCheckErrors?.get(ep.url);
          const isUnavailable = checkStatus === 'unavailable';

          // 构建按钮样式（考虑链接不可用时的红色虚线边框）
          const buttonStyle: React.CSSProperties = {
            background: isActive ? theme.subtle : "var(--bg-elevated)",
            color: isActive ? theme.from : "var(--text-muted)",
            border: isActive
              ? `1px solid ${theme.from}40`
              : isUnavailable
                ? "1px dashed #ef4444"
                : "1px solid var(--border-subtle)",
            fontFamily: "var(--font-display)",
            fontWeight: isActive ? 600 : 400,
          };

          // 构建 tooltip 内容
          const tooltipContent = checkStatus === 'unavailable' && checkError
            ? `链接不可用: ${checkError}`
            : checkStatus === 'available'
              ? '链接可用'
              : checkStatus === 'checking'
                ? '检测中...'
                : ep.name;

          const button = (
            <button
              key={`${ep.name}-${originalIdx}`}
              onClick={() => onSelect(originalIdx)}
              className="relative flex items-center justify-center px-2 py-1.5 rounded-lg text-sm transition-all duration-200 truncate"
              style={buttonStyle}
              onMouseEnter={(e) => {
                if (!isActive) {
                  e.currentTarget.style.background = "var(--bg-hover)";
                  e.currentTarget.style.color = "var(--text-secondary)";
                }
              }}
              onMouseLeave={(e) => {
                if (!isActive) {
                  e.currentTarget.style.background = "var(--bg-elevated)";
                  e.currentTarget.style.color = "var(--text-muted)";
                }
              }}
              title={tooltipContent}
            >
              <span className="truncate">{ep.name}</span>

              {/* 链接状态指示点 */}
              {checkStatus && checkStatus !== 'unchecked' && (
                <span
                  className={`absolute top-0.5 right-0.5 w-1.5 h-1.5 rounded-full ${
                    checkStatus === 'available' ? 'bg-green-500' :
                    checkStatus === 'unavailable' ? 'bg-red-500' :
                    'bg-gray-400 animate-pulse'
                  }`}
                />
              )}

              {/* 微型进度条 — 底部细线 */}
              {epProgress > 0 && epProgress < 95 && (
                <div
                  className="absolute bottom-0 left-1 right-1 h-[2px] rounded-full"
                  style={{ background: "var(--border-subtle)" }}
                >
                  <div
                    className="h-full rounded-full"
                    style={{ width: `${epProgress}%`, background: theme.from, opacity: isActive ? 1 : 0.6 }}
                  />
                </div>
              )}
              {/* 已看完标记 — 底部满进度线 */}
              {epProgress >= 95 && (
                <div
                  className="absolute bottom-0 left-1 right-1 h-[2px] rounded-full"
                  style={{ background: theme.from, opacity: isActive ? 1 : 0.4 }}
                />
              )}
            </button>
          );

          // 如果有错误信息，用 Tooltip 包裹
          if (checkStatus === 'unavailable' && checkError) {
            return (
              <Tooltip key={`${ep.name}-${originalIdx}`}>
                <TooltipTrigger asChild>
                  {button}
                </TooltipTrigger>
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

      {/* 展开/折叠更多 */}
      {episodes.length > COLLAPSE_THRESHOLD && (
        <button
          onClick={() => setExpanded(!expanded)}
          className="w-full mt-3 flex items-center justify-center gap-1 text-xs py-2 rounded-lg transition-all duration-200"
          style={{
            color: theme.from,
            background: theme.subtle,
            fontFamily: "var(--font-display)",
          }}
        >
          {expanded ? (
            <>
              <ChevronUp size={12} />
              收起
            </>
          ) : (
            <>
              <ChevronDown size={12} />
              展开全部 {episodes.length} 集
            </>
          )}
        </button>
      )}
    </div>
  );
}
