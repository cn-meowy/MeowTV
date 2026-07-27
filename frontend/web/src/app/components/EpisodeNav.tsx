import { useThemeStore } from "@/stores/theme";
import { THEMES } from "./Navbar";

interface EpisodeNavProps {
  activeEpIndex: number;
  maxEpIndex: number;
  onPrev: () => void;
  onNext: () => void;
}

export function EpisodeNav({ activeEpIndex, maxEpIndex, onPrev, onNext }: EpisodeNavProps) {
  const activeTheme = useThemeStore((s) => s.activeTheme);
  const theme = THEMES[activeTheme];
  const canPrev = activeEpIndex > 0;
  const canNext = activeEpIndex < maxEpIndex;

  return (
    <div className="flex items-center gap-2">
      <button
        onClick={onPrev}
        disabled={!canPrev}
        className="text-xs px-3 py-1.5 rounded-lg transition-all duration-200"
        style={{
          background: canPrev ? "var(--bg-hover)" : "var(--bg-elevated)",
          color: canPrev ? "var(--text-muted)" : "var(--text-muted)",
          opacity: canPrev ? 1 : 0.4,
          cursor: canPrev ? "pointer" : "not-allowed",
          fontFamily: "var(--font-display)",
        }}
      >
        上一集
      </button>
      <span className="text-xs" style={{ color: "var(--text-muted)", fontFamily: "var(--font-display)" }}>
        {activeEpIndex + 1} / {maxEpIndex + 1}
      </span>
      <button
        onClick={onNext}
        disabled={!canNext}
        className="text-xs px-3 py-1.5 rounded-lg transition-all duration-200"
        style={{
          background: canNext ? "var(--bg-hover)" : "var(--bg-elevated)",
          color: canNext ? "var(--text-muted)" : "var(--text-muted)",
          opacity: canNext ? 1 : 0.4,
          cursor: canNext ? "pointer" : "not-allowed",
          fontFamily: "var(--font-display)",
        }}
      >
        下一集
      </button>
    </div>
  );
}
