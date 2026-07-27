import { useEffect, useRef, useState } from 'react';
import { Clock, X, Trash2 } from 'lucide-react';
import { useSearchHistoryStore } from '@/stores/search-history';

interface SearchHistoryDropdownProps {
  /** 输入框当前值，为空时显示历史 */
  inputValue: string;
  /** 选中某条历史时的回调 */
  onSelect: (keyword: string) => void;
  /** 主题色 */
  themeFrom: string;
  themeGlow: string;
}

export function SearchHistoryDropdown({
  inputValue,
  onSelect,
  themeFrom,
  themeGlow,
}: SearchHistoryDropdownProps) {
  const keywords = useSearchHistoryStore((s) => s.keywords);
  const fetchFromServer = useSearchHistoryStore((s) => s.fetchFromServer);
  const removeKeyword = useSearchHistoryStore((s) => s.removeKeyword);
  const clearAll = useSearchHistoryStore((s) => s.clearAll);
  const loaded = useSearchHistoryStore((s) => s.loaded);

  const [visible, setVisible] = useState(false);
  const [hoveredIndex, setHoveredIndex] = useState(-1);
  const containerRef = useRef<HTMLDivElement>(null);

  // 首次加载从后端拉取
  useEffect(() => {
    if (!loaded) fetchFromServer();
  }, [loaded, fetchFromServer]);

  // 点击外部关闭
  useEffect(() => {
    function handleClickOutside(e: MouseEvent) {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
        setVisible(false);
      }
    }
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  // 输入框有内容时隐藏
  const shouldShow = visible && !inputValue.trim() && keywords.length > 0;

  return (
    <div ref={containerRef} className="relative">
      {/* 透明覆盖层用于捕获 focus 来显示下拉 */}
      <div
        className="absolute inset-0 z-10 cursor-text"
        onFocus={() => setVisible(true)}
        onClick={() => setVisible(true)}
      />
      {shouldShow && (
        <div
          className="absolute top-full left-0 right-0 z-50 mt-1 rounded-xl overflow-hidden"
          style={{
            background: 'var(--bg-elevated)',
            border: '1px solid var(--border-strong)',
            boxShadow: `0 8px 32px rgba(0,0,0,0.4), 0 0 1px ${themeGlow}`,
            maxHeight: '320px',
          }}
        >
          {/* 头部 */}
          <div className="flex items-center justify-between px-3 py-2" style={{ borderBottom: '1px solid var(--border-default)' }}>
            <div className="flex items-center gap-1.5">
              <Clock size={12} style={{ color: themeFrom }} />
              <span className="text-xs font-medium" style={{ color: 'var(--text-secondary)' }}>搜索历史</span>
            </div>
            <button
              onClick={(e) => { e.stopPropagation(); clearAll(); }}
              className="flex items-center gap-1 px-2 py-0.5 rounded-md text-xs transition-colors duration-150"
              style={{ color: 'var(--text-tertiary)' }}
              onMouseEnter={(e) => { e.currentTarget.style.color = themeFrom; }}
              onMouseLeave={(e) => { e.currentTarget.style.color = 'var(--text-tertiary)'; }}
            >
              <Trash2 size={10} />
              <span>清空</span>
            </button>
          </div>

          {/* 历史列表 */}
          <div className="overflow-y-auto" style={{ maxHeight: '270px' }}>
            {keywords.map((keyword, idx) => (
              <div
                key={`${keyword}-${idx}`}
                className="flex items-center group cursor-pointer transition-colors duration-100"
                style={{
                  background: hoveredIndex === idx ? 'var(--bg-hover)' : 'transparent',
                  padding: '8px 12px',
                }}
                onMouseEnter={() => setHoveredIndex(idx)}
                onMouseLeave={() => setHoveredIndex(-1)}
                onClick={() => {
                  onSelect(keyword);
                  setVisible(false);
                }}
              >
                <Clock size={12} className="shrink-0" style={{ color: 'var(--text-tertiary)', marginRight: '8px' }} />
                <span
                  className="flex-1 text-sm truncate"
                  style={{ color: hoveredIndex === idx ? themeFrom : 'var(--text-primary)' }}
                >
                  {keyword}
                </span>
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    removeKeyword(keyword);
                  }}
                  className="shrink-0 opacity-0 group-hover:opacity-100 transition-opacity duration-150 p-1 rounded"
                  style={{ color: 'var(--text-tertiary)' }}
                  onMouseEnter={(e) => { e.currentTarget.style.color = themeFrom; }}
                  onMouseLeave={(e) => { e.currentTarget.style.color = 'var(--text-tertiary)'; }}
                >
                  <X size={12} />
                </button>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
