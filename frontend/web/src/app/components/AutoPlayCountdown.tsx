import { useThemeStore } from '@/stores/theme';
import { THEMES } from '@/app/components/Navbar';

interface AutoPlayCountdownProps {
  /** 是否显示倒计时 */
  visible: boolean;
  /** 倒计时剩余秒数 */
  seconds: number;
  /** 取消自动播放 */
  onCancel: () => void;
}

export function AutoPlayCountdown({ visible, seconds, onCancel }: AutoPlayCountdownProps) {
  const activeTheme = useThemeStore((s) => s.activeTheme);
  const theme = THEMES[activeTheme];

  if (!visible) return null;

  return (
    <div
      className="absolute inset-0 z-50 flex items-center justify-center pointer-events-none"
      style={{ background: 'rgba(0, 0, 0, 0.6)' }}
    >
      <div
        className="flex items-center gap-4 px-6 py-4 rounded-2xl pointer-events-auto"
        style={{
          background: 'rgba(0, 0, 0, 0.85)',
          backdropFilter: 'blur(12px)',
          border: `1px solid ${theme.from}33`,
        }}
      >
        {/* 倒计时圆环 */}
        <div className="relative w-14 h-14 flex items-center justify-center">
          <svg className="w-14 h-14 -rotate-90" viewBox="0 0 56 56">
            <circle
              cx="28" cy="28" r="24"
              fill="none"
              stroke="rgba(255,255,255,0.15)"
              strokeWidth="3"
            />
            <circle
              cx="28" cy="28" r="24"
              fill="none"
              stroke={theme.from}
              strokeWidth="3"
              strokeLinecap="round"
              strokeDasharray={`${2 * Math.PI * 24}`}
              strokeDashoffset={`${2 * Math.PI * 24 * (1 - seconds / 10)}`}
              style={{ transition: 'stroke-dashoffset 1s linear' }}
            />
          </svg>
          <span
            className="absolute text-lg font-bold"
            style={{ color: theme.from, fontFamily: 'var(--font-display)' }}
          >
            {seconds}
          </span>
        </div>

        {/* 提示文字 */}
        <div className="flex flex-col gap-1">
          <span
            className="text-sm font-semibold text-white"
            style={{ fontFamily: 'var(--font-display)' }}
          >
            即将播放下一集
          </span>
          <span className="text-xs" style={{ color: 'var(--text-secondary)' }}>
            {seconds} 秒后自动播放
          </span>
        </div>

        {/* 取消按钮 */}
        <button
          onClick={onCancel}
          className="px-4 py-2 rounded-lg text-xs font-semibold transition-all duration-200"
          style={{
            background: 'rgba(255, 255, 255, 0.1)',
            color: 'var(--text-secondary)',
            border: '1px solid rgba(255, 255, 255, 0.1)',
          }}
          onMouseEnter={(e) => {
            e.currentTarget.style.background = theme.subtle;
            e.currentTarget.style.color = theme.from;
            e.currentTarget.style.borderColor = theme.from + '44';
          }}
          onMouseLeave={(e) => {
            e.currentTarget.style.background = 'rgba(255, 255, 255, 0.1)';
            e.currentTarget.style.color = 'var(--text-secondary)';
            e.currentTarget.style.borderColor = 'rgba(255, 255, 255, 0.1)';
          }}
        >
          取消
        </button>
      </div>
    </div>
  );
}
