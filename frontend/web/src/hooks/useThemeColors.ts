/**
 * 语义化色值 Hook —— 替代组件中的硬编码色值
 *
 * 使用方式：
 *   const c = useThemeColors();
 *   <div style={{ background: c.bgSurface, color: c.textPrimary, border: `1px solid ${c.borderDefault}` }}>
 */

export function useThemeColors() {
  return {
    // 背景
    bgBase: 'var(--bg-base)',
    bgSurface: 'var(--bg-surface)',
    bgSurfaceStrong: 'var(--bg-surface-strong)',
    bgElevated: 'var(--bg-elevated)',
    bgHover: 'var(--bg-hover)',
    bgActive: 'var(--bg-active)',

    // 文字
    textPrimary: 'var(--text-primary)',
    textSecondary: 'var(--text-secondary)',
    textTertiary: 'var(--text-tertiary)',
    textMuted: 'var(--text-muted)',

    // 边框
    borderDefault: 'var(--border-default)',
    borderSubtle: 'var(--border-subtle)',
    borderStrong: 'var(--border-strong)',

    // 阴影
    shadowCard: 'var(--shadow-card)',
    shadowElevated: 'var(--shadow-elevated)',
    shadowDropdown: 'var(--shadow-dropdown)',
  };
}
