import type { THEMES } from "@/app/components/Navbar";

/** 设置页 Tab 组件的 theme prop 类型 */
export type SettingsTheme = typeof THEMES.violet;

// ── 通用卡片样式 ──────────────────────────────────────────────────────
export const cardStyle: React.CSSProperties = {
  background: "var(--bg-surface-strong)",
  backdropFilter: "blur(20px)",
  border: "1px solid var(--border-strong)",
};

export const sectionTitleStyle: React.CSSProperties = {
  fontFamily: "var(--font-display)",
  fontWeight: 700,
  fontSize: "1.1rem",
  color: "var(--text-primary)",
};

export const labelStyle: React.CSSProperties = {
  color: "var(--text-secondary)",
  fontFamily: "var(--font-display)",
  fontWeight: 500,
  fontSize: "0.75rem",
  letterSpacing: "0.06em",
};

export const inputStyle: React.CSSProperties = {
  background: "var(--bg-elevated)",
  border: "1px solid var(--border-strong)",
  color: "var(--text-primary)",
};

export const primaryBtnStyle = (theme: SettingsTheme, disabled = false): React.CSSProperties => ({
  background: `linear-gradient(135deg,${theme.from},${theme.to})`,
  color: "#fff",
  fontFamily: "var(--font-display)",
  fontWeight: 700,
  boxShadow: `0 0 16px ${theme.glow}`,
  opacity: disabled ? 0.7 : 1,
});

export const ghostBtnStyle: React.CSSProperties = {
  color: "var(--text-secondary)",
  fontFamily: "var(--font-display)",
};

export const dangerBtnStyle: React.CSSProperties = {
  color: "#ff5555",
  background: "rgba(255,85,85,0.08)",
};
