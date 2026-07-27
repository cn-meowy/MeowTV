import { useMemo } from "react";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { useThemeStore } from "@/stores/theme";
import { THEMES } from "./Navbar";

interface EpisodeGroupNavProps {
  /** 总集数 */
  totalEpisodes: number;
  /** 当前激活的集索引 (0-based) */
  activeIndex: number;
  /** 每组集数，默认 20 */
  groupSize?: number;
  /** 点击集索引回调 */
  onSelect: (index: number) => void;
}

/**
 * 剧集分组导航 — 当总集数 > groupSize 时显示分组标签栏，
 * 点击分组自动滚动到对应区间，当前集所在分组高亮。
 */
export function EpisodeGroupNav({
  totalEpisodes,
  activeIndex,
  groupSize = 20,
  onSelect,
}: EpisodeGroupNavProps) {
  const activeTheme = useThemeStore((s) => s.activeTheme);
  const theme = THEMES[activeTheme];

  const groups = useMemo(() => {
    const result: { label: string; start: number; end: number }[] = [];
    for (let i = 0; i < totalEpisodes; i += groupSize) {
      const start = i;
      const end = Math.min(i + groupSize - 1, totalEpisodes - 1);
      result.push({
        label: `${start + 1}-${end + 1}`,
        start,
        end,
      });
    }
    return result;
  }, [totalEpisodes, groupSize]);

  // 不需要分组时不渲染
  if (groups.length <= 1) return null;

  const activeGroupIdx = groups.findIndex(
    (g) => activeIndex >= g.start && activeIndex <= g.end
  );

  const handleGroupClick = (groupIdx: number) => {
    // 点击分组时跳到该组第一集
    onSelect(groups[groupIdx].start);
  };

  const handlePrevGroup = () => {
    if (activeGroupIdx > 0) handleGroupClick(activeGroupIdx - 1);
  };

  const handleNextGroup = () => {
    if (activeGroupIdx < groups.length - 1) handleGroupClick(activeGroupIdx + 1);
  };

  return (
    <div
      className="flex items-center gap-1.5 px-1 py-1.5 rounded-lg overflow-x-auto"
      style={{ background: "var(--bg-elevated)" }}
    >
      {/* 上一组 */}
      <button
        onClick={handlePrevGroup}
        disabled={activeGroupIdx <= 0}
        className="shrink-0 flex items-center justify-center w-6 h-6 rounded-md transition-all duration-200"
        style={{
          color: activeGroupIdx > 0 ? "var(--text-muted)" : "var(--text-tertiary)",
          background: "transparent",
          opacity: activeGroupIdx > 0 ? 1 : 0.4,
          cursor: activeGroupIdx > 0 ? "pointer" : "not-allowed",
        }}
        onMouseEnter={(e) => {
          if (activeGroupIdx > 0) {
            e.currentTarget.style.background = "var(--bg-hover)";
            e.currentTarget.style.color = "var(--text-secondary)";
          }
        }}
        onMouseLeave={(e) => {
          if (activeGroupIdx > 0) {
            e.currentTarget.style.background = "transparent";
            e.currentTarget.style.color = "var(--text-muted)";
          }
        }}
      >
        <ChevronLeft size={13} />
      </button>

      {/* 分组标签 */}
      <div className="flex items-center gap-1 overflow-x-auto scrollbar-none">
        {groups.map((group, idx) => {
          const isActive = idx === activeGroupIdx;
          return (
            <button
              key={group.label}
              onClick={() => handleGroupClick(idx)}
              className="shrink-0 px-2.5 py-1 rounded-md text-[11px] transition-all duration-200 whitespace-nowrap"
              style={{
                background: isActive ? theme.subtle : "transparent",
                color: isActive ? theme.from : "var(--text-muted)",
                fontWeight: isActive ? 600 : 400,
                fontFamily: "var(--font-display)",
                border: isActive ? `1px solid ${theme.from}30` : "1px solid transparent",
              }}
              onMouseEnter={(e) => {
                if (!isActive) {
                  e.currentTarget.style.background = "var(--bg-hover)";
                  e.currentTarget.style.color = "var(--text-secondary)";
                }
              }}
              onMouseLeave={(e) => {
                if (!isActive) {
                  e.currentTarget.style.background = "transparent";
                  e.currentTarget.style.color = "var(--text-muted)";
                }
              }}
            >
              {group.label}
            </button>
          );
        })}
      </div>

      {/* 下一组 */}
      <button
        onClick={handleNextGroup}
        disabled={activeGroupIdx >= groups.length - 1}
        className="shrink-0 flex items-center justify-center w-6 h-6 rounded-md transition-all duration-200"
        style={{
          color: activeGroupIdx < groups.length - 1 ? "var(--text-muted)" : "var(--text-tertiary)",
          background: "transparent",
          opacity: activeGroupIdx < groups.length - 1 ? 1 : 0.4,
          cursor: activeGroupIdx < groups.length - 1 ? "pointer" : "not-allowed",
        }}
        onMouseEnter={(e) => {
          if (activeGroupIdx < groups.length - 1) {
            e.currentTarget.style.background = "var(--bg-hover)";
            e.currentTarget.style.color = "var(--text-secondary)";
          }
        }}
        onMouseLeave={(e) => {
          if (activeGroupIdx < groups.length - 1) {
            e.currentTarget.style.background = "transparent";
            e.currentTarget.style.color = "var(--text-muted)";
          }
        }}
      >
        <ChevronRight size={13} />
      </button>
    </div>
  );
}
