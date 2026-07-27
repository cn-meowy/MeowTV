import { useState, useCallback, useRef, useEffect } from "react";
import { useNavigate } from "react-router";
import { Search, Loader2, ChevronLeft, ChevronRight, AlertTriangle } from "lucide-react";
import { useThemeStore } from "@/stores/theme";
import { THEMES } from "@/app/components/Navbar";
import { SearchResultCard } from "@/app/components/SearchResultCard";
import { SearchHistoryBubbles } from "@/app/components/SearchHistoryBubbles";
import { getResourceSites, resourcePaginate } from "@/api/search";
import { useSearchHistoryStore } from "@/stores/search-history";
import { ApiError } from "@/api/client";
import type { ResourceSiteItem, SearchResultItem } from "@/types/api";

const PAGE_SIZE = 20;

export default function ResourcePage() {
  const navigate = useNavigate();
  const activeTheme = useThemeStore((s) => s.activeTheme);
  const theme = THEMES[activeTheme];

  const [sites, setSites] = useState<ResourceSiteItem[]>([]);
  const [selectedResource, setSelectedResource] = useState<string>("");
  const [keyword, setKeyword] = useState("");
  const [page, setPage] = useState(1);
  const [results, setResults] = useState<SearchResultItem[]>([]);
  const [total, setTotal] = useState(0);
  const [totalPages, setTotalPages] = useState(0);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const abortRef = useRef<AbortController | null>(null);

  // 查询数据
  const fetchData = useCallback(
    async (resourceDomain: string, currentPage: number, searchKeyword?: string) => {
      if (!resourceDomain) return;
      // 取消上一次未完成的请求
      abortRef.current?.abort();
      const ac = new AbortController();
      abortRef.current = ac;

      setLoading(true);
      setError(null);
      try {
        const resp = await resourcePaginate({
          page: currentPage,
          page_size: PAGE_SIZE,
          resource: resourceDomain,
          keyword: searchKeyword || undefined,
        });
        // 仅在请求未被取消时更新状态
        if (!ac.signal.aborted) {
          setResults(resp.items || []);
          setTotal(resp.total);
          setTotalPages(resp.total_pages);
        }
      } catch (err) {
        if (!ac.signal.aborted) {
          setResults([]);
          setTotal(0);
          setTotalPages(0);
          const errMsg = err instanceof ApiError ? err.message : "请求资源站失败";
          setError(errMsg);
        }
      } finally {
        if (!ac.signal.aborted) {
          setLoading(false);
        }
      }
    },
    []
  );

  // 加载资源站点列表 + 首次查询
  useEffect(() => {
    getResourceSites()
      .then((list) => {
        setSites(list);
        if (list.length > 0) {
          setSelectedResource(list[0].domain);
          fetchData(list[0].domain, 1);
        }
      })
      .catch(() => {});
  }, [fetchData]);

  // 搜索历史 store
  const addSearchKeyword = useSearchHistoryStore((s) => s.addKeyword);

  // 从搜索历史选择关键词
  const handleHistorySelect = (keyword: string) => {
    setKeyword(keyword);
    setPage(1);
    fetchData(selectedResource, 1, keyword);
    addSearchKeyword(keyword);
  };

  // 搜索框输入：仅更新显示值，不触发查询
  const handleKeywordChange = (value: string) => {
    setKeyword(value);
  };

  // 回车搜索：仅当关键词非空时触发查询
  const handleSearch = () => {
    if (!keyword.trim()) return;
    setPage(1);
    fetchData(selectedResource, 1, keyword);
  };

  // 清空搜索框：仅清空显示值，不触发查询
  const handleClearKeyword = () => {
    setKeyword("");
  };

  // 切换资源
  const handleResourceChange = (domain: string) => {
    if (domain === selectedResource) return;
    setSelectedResource(domain);
    setPage(1);
    setKeyword("");
    fetchData(domain, 1);
  };

  // 翻页
  const handlePageChange = (newPage: number) => {
    if (newPage < 1 || newPage > totalPages) return;
    setPage(newPage);
    fetchData(selectedResource, newPage, keyword || undefined);
    window.scrollTo({ top: 0, behavior: "smooth" });
  };

  // 卡片点击 — 直接跳转播放页
  const handleCardClick = (item: SearchResultItem) => {
    const params = new URLSearchParams({
      vod_id: String(item.vod_id),
      site: item.resource_domain,
      name: item.title,
    });
    navigate(`/play?${params.toString()}`);
  };

  // 分页按钮生成
  const getPageButtons = () => {
    const buttons: (number | "...")[] = [];
    if (totalPages <= 7) {
      for (let i = 1; i <= totalPages; i++) buttons.push(i);
    } else {
      buttons.push(1);
      if (page > 3) buttons.push("...");
      const start = Math.max(2, page - 1);
      const end = Math.min(totalPages - 1, page + 1);
      for (let i = start; i <= end; i++) buttons.push(i);
      if (page < totalPages - 2) buttons.push("...");
      buttons.push(totalPages);
    }
    return buttons;
  };

  return (
    <div className="min-h-screen px-4 py-6 max-w-7xl mx-auto">
      {/* 搜索栏 */}
      <div
        className="flex items-center gap-3 rounded-2xl px-4 py-3 mb-6"
        style={{
          background: "var(--bg-surface-strong)",
          border: `1px solid var(--border-default)`,
          boxShadow: "var(--shadow-elevated)",
        }}
      >
        <Search size={18} style={{ color: theme.from, flexShrink: 0 }} />
        <input
          value={keyword}
          onChange={(e) => handleKeywordChange(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter") handleSearch();
          }}
          placeholder="搜索资源..."
          className="flex-1 bg-transparent outline-none text-sm"
          style={{ color: "var(--text-primary)" }}
        />
        {keyword && (
          <button
            onClick={handleClearKeyword}
            className="shrink-0 p-1 rounded-lg transition-colors"
            style={{ color: "var(--text-tertiary)" }}
          >
            ✕
          </button>
        )}
      </div>

      {/* 搜索历史气泡 */}
      <div className="mb-6">
        <SearchHistoryBubbles
          onSelect={handleHistorySelect}
          themeFrom={theme.from}
          themeGlow={theme.glow}
        />
      </div>

      {/* 资源标签列表 */}
      <div className="flex flex-wrap gap-2 mb-6">
        {sites.map((site) => {
          const active = selectedResource === site.domain;
          return (
            <button
              key={site.domain}
              onClick={() => handleResourceChange(site.domain)}
              className="px-4 py-2 rounded-xl text-sm whitespace-nowrap transition-all duration-200"
              style={{
                background: active ? theme.subtle : "var(--bg-elevated)",
                color: active ? theme.from : "var(--text-secondary)",
                border: active
                  ? `1px solid ${theme.glow}`
                  : "1px solid var(--border-default)",
                boxShadow: active ? `0 0 12px ${theme.glow}` : "none",
                fontFamily: "var(--font-display)",
              }}
            >
              {site.name}
            </button>
          );
        })}
      </div>

      {/* 加载状态 */}
      {loading && (
        <div className="flex items-center justify-center py-20">
          <Loader2
            size={32}
            className="animate-spin"
            style={{ color: theme.from }}
          />
        </div>
      )}

      {/* 结果列表 */}
      {!loading && results.length > 0 && (
        <>
          <div className="text-xs mb-4" style={{ color: "var(--text-tertiary)" }}>
            共 {total} 条结果
          </div>
          <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-4">
            {results.map((item, idx) => (
              <SearchResultCard
                key={`${item.resource_domain}-${item.vod_id}-${idx}`}
                item={item}
                themeFrom={theme.from}
                themeTo={theme.to}
                themeGlow={theme.glow}
                themeSubtle={theme.subtle}
                onClick={handleCardClick}
              />
            ))}
          </div>
        </>
      )}

      {/* 错误状态 */}
      {!loading && error && (
        <div className="flex flex-col items-center justify-center py-20">
          <AlertTriangle size={48} style={{ color: "#ff5555", opacity: 0.7 }} />
          <p className="mt-4 text-sm text-center max-w-md" style={{ color: "#ff5555" }}>
            {error}
          </p>
          <button
            onClick={() => fetchData(selectedResource, page, keyword || undefined)}
            className="mt-4 px-4 py-2 rounded-xl text-xs transition-all duration-200"
            style={{
              background: "rgba(255,85,85,0.08)",
              border: "1px solid rgba(255,85,85,0.3)",
              color: "#ff5555",
            }}
          >
            重试
          </button>
        </div>
      )}

      {/* 空状态（无错误时才显示） */}
      {!loading && !error && results.length === 0 && selectedResource && (
        <div className="flex flex-col items-center justify-center py-20">
          <Search size={48} style={{ color: "var(--text-tertiary)", opacity: 0.5 }} />
          <p className="mt-4 text-sm" style={{ color: "var(--text-tertiary)" }}>
            暂无数据
          </p>
        </div>
      )}

      {/* 分页控件 */}
      {!loading && totalPages > 1 && (
        <div
          className="flex items-center justify-center gap-2 mt-8 mb-4"
          style={{ fontFamily: "var(--font-display)" }}
        >
          <button
            onClick={() => handlePageChange(page - 1)}
            disabled={page <= 1}
            className="flex items-center gap-1 px-3 py-2 rounded-xl text-sm transition-all duration-200"
            style={{
              background: page <= 1 ? "var(--bg-elevated)" : theme.subtle,
              color: page <= 1 ? "var(--text-tertiary)" : theme.from,
              border:
                page <= 1
                  ? "1px solid var(--border-default)"
                  : `1px solid ${theme.glow}`,
              opacity: page <= 1 ? 0.5 : 1,
              cursor: page <= 1 ? "not-allowed" : "pointer",
            }}
          >
            <ChevronLeft size={14} />
            上一页
          </button>

          {getPageButtons().map((btn, idx) =>
            btn === "..." ? (
              <span
                key={`ellipsis-${idx}`}
                className="px-2 text-sm"
                style={{ color: "var(--text-tertiary)" }}
              >
                ...
              </span>
            ) : (
              <button
                key={btn}
                onClick={() => handlePageChange(btn)}
                className="w-9 h-9 rounded-xl text-sm transition-all duration-200"
                style={{
                  background: page === btn ? theme.subtle : "transparent",
                  color: page === btn ? theme.from : "var(--text-secondary)",
                  border: page === btn ? `1px solid ${theme.glow}` : "1px solid transparent",
                  boxShadow: page === btn ? `0 0 8px ${theme.glow}` : "none",
                }}
              >
                {btn}
              </button>
            )
          )}

          <button
            onClick={() => handlePageChange(page + 1)}
            disabled={page >= totalPages}
            className="flex items-center gap-1 px-3 py-2 rounded-xl text-sm transition-all duration-200"
            style={{
              background: page >= totalPages ? "var(--bg-elevated)" : theme.subtle,
              color: page >= totalPages ? "var(--text-tertiary)" : theme.from,
              border:
                page >= totalPages
                  ? "1px solid var(--border-default)"
                  : `1px solid ${theme.glow}`,
              opacity: page >= totalPages ? 0.5 : 1,
              cursor: page >= totalPages ? "not-allowed" : "pointer",
            }}
          >
            下一页
            <ChevronRight size={14} />
          </button>
        </div>
      )}
    </div>
  );
}
