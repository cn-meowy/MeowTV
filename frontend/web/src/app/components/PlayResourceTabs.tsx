import { Globe, Check, Server } from "lucide-react";
import type { PlaySource } from "@/types/api";
import { useThemeStore } from "@/stores/theme";
import { THEMES } from "./Navbar";

interface PlayResourceTabsProps {
  sources: PlaySource[];
  activeSourceIndex: number;
  onSelect: (index: number) => void;
}

export function PlayResourceTabs({ sources, activeSourceIndex, onSelect }: PlayResourceTabsProps) {
  const activeTheme = useThemeStore((s) => s.activeTheme);
  const theme = THEMES[activeTheme];

  if (sources.length <= 1) return null;

  return (
    <div
      className="rounded-xl p-3"
      style={{ background: "var(--bg-surface)", border: "1px solid var(--border-default)" }}
    >
      <h3
        className="text-xs mb-2.5"
        style={{ color: "var(--text-muted)", fontFamily: "var(--font-display)", fontWeight: 600 }}
      >
        播放线路
      </h3>
      <div className="flex gap-2 flex-wrap">
        {sources.map((source, idx) => {
          const isActive = idx === activeSourceIndex;
          return (
            <button
              key={source.name}
              onClick={() => onSelect(idx)}
              className="inline-flex items-center gap-1.5 text-xs px-3 py-1.5 rounded-lg transition-all duration-200"
              style={{
                background: isActive ? theme.subtle : "var(--bg-elevated)",
                color: isActive ? theme.from : "var(--text-muted)",
                border: isActive ? `1px solid ${theme.from}40` : "1px solid var(--border-subtle)",
                fontFamily: "var(--font-display)",
                fontWeight: isActive ? 600 : 400,
              }}
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
            >
              <Server size={10} />
              <span>{source.name}</span>
              <span className="text-[10px]" style={{ opacity: 0.5 }}>({source.episodes.length})</span>
              {isActive && <Check size={10} style={{ color: theme.from }} />}
            </button>
          );
        })}
      </div>
    </div>
  );
}
