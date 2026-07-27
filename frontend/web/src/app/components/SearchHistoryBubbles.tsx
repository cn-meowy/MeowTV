import { useEffect, useState } from 'react';
import { Clock, Trash2 } from 'lucide-react';
import { useSearchHistoryStore } from '@/stores/search-history';

interface SearchHistoryBubblesProps {
  /** 选中某条历史时的回调 */
  onSelect: (keyword: string) => void;
  /** 主题色 */
  themeFrom: string;
  themeGlow: string;
}

export function SearchHistoryBubbles({
  onSelect,
  themeFrom,
  themeGlow,
}: SearchHistoryBubblesProps) {
  const keywords = useSearchHistoryStore((s) => s.keywords);
  const fetchFromServer = useSearchHistoryStore((s) => s.fetchFromServer);
  const clearAll = useSearchHistoryStore((s) => s.clearAll);
  const loaded = useSearchHistoryStore((s) => s.loaded);

  const [hovered, setHovered] = useState(false);

  // 首次加载从后端拉取
  useEffect(() => {
    if (!loaded) fetchFromServer();
  }, [loaded, fetchFromServer]);

  // 无历史记录时不显示
  if (keywords.length === 0) return null;

  return (
    <div
      className="relative"
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
    >
      <div className="flex items-start gap-3 flex-wrap">
        {/* 搜索历史标签列表 */}
        <div className="flex items-center gap-2 flex-wrap flex-1">
          <Clock size={12} style={{ color: themeFrom, marginTop: 8, flexShrink: 0 }} />
          {keywords.map((keyword, idx) => (
            <button
              key={`${keyword}-${idx}`}
              onClick={() => onSelect(keyword)}
              className="rounded-full text-[13px] transition-all duration-200 whitespace-nowrap"
              style={{
                padding: '8px 16px',
                background: 'var(--bg-elevated)',
                border: `1px solid var(--border-strong)`,
                color: 'var(--text-secondary)',
              }}
              onMouseEnter={(e) => {
                e.currentTarget.style.background = 'var(--bg-hover)';
                e.currentTarget.style.borderColor = themeGlow;
                e.currentTarget.style.color = themeFrom;
                e.currentTarget.style.boxShadow = `0 0 8px ${themeGlow}`;
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.background = 'var(--bg-elevated)';
                e.currentTarget.style.borderColor = 'var(--border-strong)';
                e.currentTarget.style.color = 'var(--text-secondary)';
                e.currentTarget.style.boxShadow = 'none';
              }}
            >
              {keyword}
            </button>
          ))}
        </div>

        {/* 清空按钮 - hover 时显示 */}
        {hovered && keywords.length > 0 && (
          <button
            onClick={(e) => {
              e.stopPropagation();
              clearAll();
            }}
            className="flex items-center gap-1 px-3 py-2 rounded-xl text-xs transition-all duration-200 mt-1"
            style={{
              background: 'rgba(220,38,38,0.08)',
              border: '1px solid rgba(220,38,38,0.2)',
              color: '#fb7185',
            }}
            onMouseEnter={(e) => {
              e.currentTarget.style.background = 'rgba(220,38,38,0.15)';
              e.currentTarget.style.borderColor = 'rgba(220,38,38,0.4)';
            }}
            onMouseLeave={(e) => {
              e.currentTarget.style.background = 'rgba(220,38,38,0.08)';
              e.currentTarget.style.borderColor = 'rgba(220,38,38,0.2)';
            }}
          >
            <Trash2 size={12} />
            <span>清空历史</span>
          </button>
        )}
      </div>
    </div>
  );
}
