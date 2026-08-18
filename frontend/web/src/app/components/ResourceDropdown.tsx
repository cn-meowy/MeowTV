import { useState } from "react";
import { ChevronDown, Check, Layers } from "lucide-react";
import type { ResourceSiteItem } from "@/types/api";

interface ResourceDropdownProps {
  sites: ResourceSiteItem[];
  selected: string[];  // domain 列表
  onChange: (domains: string[]) => void;
  themeFrom: string;
  themeTo: string;
  themeGlow: string;
  themeSubtle: string;
}

export function ResourceDropdown({ sites, selected, onChange, themeFrom, themeTo, themeGlow, themeSubtle }: ResourceDropdownProps) {
  const [expanded, setExpanded] = useState(false);

  // 过滤掉不允许搜索的资源
  const visibleSites = sites.filter(s => s.searchable !== false);

  // 是否存在18禁资源
  const hasAdultSites = visibleSites.some(s => s.is_adult);
  const adultSites = hasAdultSites ? visibleSites.filter(s => s.is_adult) : [];
  const adultDomains = new Set(adultSites.map(s => s.domain));

  // 全选状态（基于可见资源）
  const allSelected = visibleSites.length > 0 && selected.length === visibleSites.length;

  // 18禁复选框状态
  const adultChecked = adultSites.length > 0 && adultSites.every(s => selected.includes(s.domain));

  // 选中数量标签
  const selectedLabel = allSelected
    ? "全部资源"
    : selected.length === 0
      ? "未选择"
      : `${selected.length}个资源`;

  // 切换全部
  function toggleAll() {
    if (allSelected) {
      onChange([]);
    } else {
      onChange(visibleSites.map(s => s.domain));
    }
  }

  // 切换单个资源
  function toggleSite(domain: string) {
    if (selected.includes(domain)) {
      onChange(selected.filter(d => d !== domain));
    } else {
      onChange([...selected, domain]);
    }
  }

  // 切换18禁
  function toggleAdult() {
    if (adultChecked) {
      // 取消所有18禁资源
      onChange(selected.filter(d => !adultDomains.has(d)));
    } else {
      // 勾选所有18禁资源（保留已有选择）
      const newSelected = new Set(selected);
      for (const d of adultDomains) {
        newSelected.add(d);
      }
      onChange(Array.from(newSelected));
    }
  }

  return (
    <div>
      {/* 第一行：全部资源按钮 + 18禁复选框 */}
      <div className="flex items-center gap-2 flex-wrap">
        {/* 全部资源按钮（点击展开/折叠） */}
        <button
          onClick={() => setExpanded(e => !e)}
          className="flex items-center gap-2 px-4 py-3 rounded-2xl text-sm transition-all duration-200"
          style={{
            background: expanded ? themeSubtle : "var(--bg-hover)",
            border: `1px solid ${expanded ? themeGlow : "var(--border-strong)"}`,
            color: expanded ? themeFrom : "var(--text-secondary)",
            boxShadow: expanded ? `0 0 12px ${themeGlow}` : "none",
            fontFamily: "var(--font-display)",
          }}
        >
          <Layers size={14} />
          {selectedLabel}
          <ChevronDown
            size={12}
            style={{
              transition: "transform 0.2s",
              transform: expanded ? "rotate(180deg)" : "rotate(0)",
            }}
          />
        </button>

      </div>

      {/* 展开的资源列表 */}
      {expanded && (
        <div
          className="mt-2 p-3 rounded-2xl"
          style={{
            background: "var(--bg-elevated)",
            border: "1px solid var(--border-strong)",
            boxShadow: "var(--shadow-dropdown)",
          }}
        >
          {/* 全选 + 18禁 并排 */}
          <div className="flex flex-wrap items-center gap-2 mb-2">
            <button
              onClick={toggleAll}
              className="flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg text-xs transition-all duration-200"
              style={{
                background: allSelected ? themeSubtle : "var(--bg-elevated)",
                border: `1px solid ${allSelected ? themeGlow : "var(--border-strong)"}`,
                color: allSelected ? themeFrom : "var(--text-secondary)",
                fontFamily: "var(--font-display)",
              }}
            >
              <span
                className="w-3.5 h-3.5 rounded flex items-center justify-center shrink-0"
                style={{
                  border: allSelected ? "none" : "1px solid var(--border-strong)",
                  background: allSelected ? `linear-gradient(135deg,${themeFrom},${themeTo})` : "transparent",
                }}
              >
                {allSelected && <Check size={8} color="#fff" strokeWidth={3} />}
              </span>
              全选
            </button>

            {/* 18禁复选框 —— 仅在有18禁资源时显示 */}
            {hasAdultSites && (
              <button
                onClick={toggleAdult}
                className="flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg text-xs transition-all duration-200"
                style={{
                  background: adultChecked ? "rgba(220,38,38,0.12)" : "var(--bg-elevated)",
                  border: `1px solid ${adultChecked ? "rgba(220,38,38,0.3)" : "var(--border-strong)"}`,
                  color: adultChecked ? "#fb7185" : "var(--text-secondary)",
                  fontFamily: "var(--font-display)",
                }}
              >
                <span
                  className="w-3.5 h-3.5 rounded flex items-center justify-center shrink-0"
                  style={{
                    border: adultChecked ? "none" : "1px solid var(--border-strong)",
                    background: adultChecked ? "linear-gradient(135deg,#dc2626,#fb7185)" : "transparent",
                  }}
                >
                  {adultChecked && <Check size={8} color="#fff" strokeWidth={3} />}
                </span>
                18禁
              </button>
            )}
          </div>

          <div style={{ borderTop: "1px solid var(--border-default)", marginBottom: 8 }} />

          {/* 各资源站 pill */}
          <div className="flex flex-wrap gap-2">
            {visibleSites.map(site => {
              const isSelected = selected.includes(site.domain);
              const isAdult = site.is_adult;
              return (
                <button
                  key={site.domain}
                  onClick={() => toggleSite(site.domain)}
                  className="flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg text-xs transition-all duration-200"
                  style={{
                    background: isSelected
                      ? isAdult ? "rgba(220,38,38,0.10)" : themeSubtle
                      : "var(--bg-elevated)",
                    border: `1px solid ${isSelected
                      ? isAdult ? "rgba(220,38,38,0.25)" : themeGlow
                      : "var(--border-strong)"}`,
                    color: isSelected
                      ? isAdult ? "#fb7185" : themeFrom
                      : "var(--text-secondary)",
                    fontFamily: "var(--font-display)",
                  }}
                >
                  <span
                    className="w-3.5 h-3.5 rounded flex items-center justify-center shrink-0"
                    style={{
                      border: isSelected ? "none" : "1px solid var(--border-strong)",
                      background: isSelected
                        ? isAdult ? "linear-gradient(135deg,#dc2626,#fb7185)" : `linear-gradient(135deg,${themeFrom},${themeTo})`
                        : "transparent",
                    }}
                  >
                    {isSelected && <Check size={8} color="#fff" strokeWidth={3} />}
                  </span>
                  {site.name}
                </button>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
}
