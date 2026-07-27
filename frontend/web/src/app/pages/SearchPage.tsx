import { useState, useEffect, useCallback, useRef } from "react";
import { useSearchParams, useNavigate } from "react-router";
import { Search, Loader2, AlertCircle, LayoutGrid, List, X } from "lucide-react";
import { useThemeStore } from "@/stores/theme";
import { THEMES } from "@/app/components/Navbar";
import { GradientText } from "@/app/components/GradientText";
import { ResourceDropdown } from "@/app/components/ResourceDropdown";
import { SearchResultCard } from "@/app/components/SearchResultCard";
import { NameGroupedCard } from "@/app/components/NameGroupedCard";
import { SearchHistoryBubbles } from "@/app/components/SearchHistoryBubbles";
import { getResourceSites, searchSSE, cacheGroupData } from "@/api/search";
import { useSearchHistoryStore } from "@/stores/search-history";
import type { ResourceSiteItem, SearchResultItem, SearchDoneData, SearchErrorData } from "@/types/api";

type GroupMode = "resource" | "name";

interface GroupedResults {
  [key: string]: {
    label: string;
    items: SearchResultItem[];
  };
}

export default function SearchPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const navigate = useNavigate();
  const activeTheme = useThemeStore((s) => s.activeTheme);
  const theme = THEMES[activeTheme];

  const queryFromUrl = searchParams.get("q") || "";
  const doubanIdFromUrl = searchParams.get("douban_id") || "";

  const [inputValue, setInputValue] = useState(queryFromUrl);
  const [sites, setSites] = useState<ResourceSiteItem[]>([]);
  const [selectedResources, setSelectedResources] = useState<string[]>([]);
  const [groupMode, setGroupMode] = useState<GroupMode>("resource");
  const [results, setResults] = useState<SearchResultItem[]>([]);
  const [errors, setErrors] = useState<SearchErrorData[]>([]);
  const [doneSites, setDoneSites] = useState<Set<string>>(new Set());
  const [totalResults, setTotalResults] = useState(0);
  const [searching, setSearching] = useState(false);
  const [searchComplete, setSearchComplete] = useState(false);
  const [searchInitiated, setSearchInitiated] = useState(false);

  const inputRef = useRef<HTMLInputElement>(null);
  const lastSearchKey = useRef<string>("");
  const initialQueryRef = useRef<string>(queryFromUrl);
  const abortControllerRef = useRef<AbortController | null>(null);

  // 同步 URL 参数到输入框
  useEffect(() => {
    setInputValue(queryFromUrl);
  }, [queryFromUrl]);

  // 加载资源站点列表
  useEffect(() => {
    getResourceSites()
      .then(list => {
        // 过滤掉不允许搜索的资源
        const searchable = list.filter(s => s.searchable !== false);
        setSites(searchable);
        // 默认不选中18禁资源
        const defaultSelected = searchable.filter(s => !s.is_adult).map(s => s.domain);
        setSelectedResources(defaultSelected);
        // 如果 URL 已有搜索词，站点加载完成后立即触发搜索
        if (queryFromUrl && defaultSelected.length > 0) {
          doSearch(queryFromUrl, doubanIdFromUrl, defaultSelected);
        }
      })
      .catch(() => {});
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // 执行搜索
  const doSearch = useCallback(async (q: string, doubanId: string, resources: string[]) => {
    if (!q.trim() || resources.length === 0) return;
    // 防止重复搜索相同内容
    const key = `${q.trim()}|${doubanId}|${resources.sort().join(",")}`;
    if (key === lastSearchKey.current) return;
    lastSearchKey.current = key;

    // 中断之前的搜索请求
    if (abortControllerRef.current) {
      abortControllerRef.current.abort();
    }
    const controller = new AbortController();
    abortControllerRef.current = controller;

    setResults([]);
    setErrors([]);
    setDoneSites(new Set());
    setTotalResults(0);
    setSearching(true);
    setSearchComplete(false);
    setSearchInitiated(true);

    try {
      await searchSSE(
        { q: q.trim(), douban_id: doubanId || undefined, resources },
        {
          onResult: (item) => { if (!controller.signal.aborted) setResults(prev => [...prev, item]); },
          onDone: (data: SearchDoneData) => { if (!controller.signal.aborted) setDoneSites(prev => new Set(prev).add(data.resource_domain)); },
          onComplete: (data) => { if (!controller.signal.aborted) { setTotalResults(data.total); setSearching(false); setSearchComplete(true); } },
          onError: (data: SearchErrorData) => { if (!controller.signal.aborted) setErrors(prev => [...prev, data]); },
        },
        controller.signal,
      );
    } catch {
      if (!controller.signal.aborted) {
        setSearching(false);
        setSearchComplete(true);
      }
    }
  }, []);

  // URL 参数变化时自动搜索（站点已加载后才生效）
  useEffect(() => {
    if (queryFromUrl && selectedResources.length > 0 && sites.length > 0) {
      doSearch(queryFromUrl, doubanIdFromUrl, selectedResources);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [queryFromUrl, doubanIdFromUrl]);

  // 资源选择变化时仅更新状态，不自动触发搜索
  function handleResourceChange(domains: string[]) {
    setSelectedResources(domains);
  }

  // 搜索历史 store
  const addSearchKeyword = useSearchHistoryStore((s) => s.addKeyword);

  // 触发搜索：直接调用 doSearch 并同步 URL
  function triggerSearch() {
    const q = inputValue.trim();
    if (!q || selectedResources.length === 0) return;
    // 如果搜索词与初始词不同，说明用户修改了搜索内容，此时豆瓣 ID 已不匹配，应移除
    const effectiveDoubanId = q === initialQueryRef.current ? doubanIdFromUrl : "";
    // 同步 URL 参数（不依赖 URL 变化触发搜索）
    const params = new URLSearchParams();
    params.set("q", q);
    if (effectiveDoubanId) params.set("douban_id", effectiveDoubanId);
    setSearchParams(params);
    // 直接执行搜索
    doSearch(q, effectiveDoubanId, selectedResources);
    // 记录搜索历史
    addSearchKeyword(q);
  }

  // 从搜索历史选择关键词
  function handleHistorySelect(keyword: string) {
    setInputValue(keyword);
    // 自动触发搜索
    if (selectedResources.length > 0) {
      doSearch(keyword, "", selectedResources);
      addSearchKeyword(keyword);
      const params = new URLSearchParams();
      params.set("q", keyword);
      setSearchParams(params);
    }
  }

  // 清除搜索输入
  function clearInput() {
    setInputValue("");
    inputRef.current?.focus();
  }

  // 点击搜索结果跳转详情页
  function handleResultClick(item: SearchResultItem, groupKey: string) {
    // 缓存当前分组数据（按 resource_domain 去重，同一资源站只保留第一条）
    const group = groupedResults[groupKey];
    if (group) {
      const seen = new Set<string>();
      const deduped = group.items.filter(i => {
        if (seen.has(i.resource_domain)) return false;
        seen.add(i.resource_domain);
        return true;
      });
      cacheGroupData(groupKey, deduped);
    }
    // 跳转详情页
    const params = new URLSearchParams();
    params.set("group_key", groupKey);
    params.set("name", item.title);
    params.set("site", item.resource_domain);
    navigate(`/detail?${params.toString()}`);
  }

  // 分组结果
  const groupedResults: GroupedResults = (() => {
    if (groupMode === "resource") {
      const groups: GroupedResults = {};
      for (const item of results) {
        const key = item.resource_domain;
        if (!groups[key]) groups[key] = { label: item.resource_name, items: [] };
        groups[key].items.push(item);
      }
      return groups;
    } else {
      const groups: GroupedResults = {};
      for (const item of results) {
        const key = item.douban_id ? `db_${item.douban_id}` : `name_${item.title}`;
        if (!groups[key]) groups[key] = { label: item.title, items: [] };
        groups[key].items.push(item);
      }
      return groups;
    }
  })();

  const groupKeys = Object.keys(groupedResults);

  return (
    <div className="px-6 md:px-12 lg:px-16 py-8">
      {/* 标题区 */}
      <div className="mb-6">
        <div className="flex items-center gap-3 mb-2">
          <Search size={24} style={{ color: theme.from }} />
          <h1 style={{ fontFamily: "var(--font-display)", fontWeight: 800, fontSize: "1.75rem" }}>
            <GradientText from={theme.from} to={theme.to}>
              {queryFromUrl ? `搜索: ${queryFromUrl}` : "聚合搜索"}
            </GradientText>
          </h1>
        </div>
        {doubanIdFromUrl && (
          <p className="text-xs" style={{ color: "var(--text-secondary)" }}>豆瓣 ID: {doubanIdFromUrl}</p>
        )}
      </div>

      {/* 搜索输入框 + 资源选择 */}
      <div className="mb-4">
        <div className="flex items-center gap-3 flex-wrap">
          {/* 资源选择 - 与搜索框高度对齐 */}
          <div
            className="flex items-center transition-all duration-200"
            style={{
              height: "50px",
            }}
          >
            <ResourceDropdown
              sites={sites}
              selected={selectedResources}
              onChange={handleResourceChange}
              themeFrom={theme.from}
              themeTo={theme.to}
              themeGlow={theme.glow}
              themeSubtle={theme.subtle}
            />
          </div>

          {/* 搜索框 */}
          <div className="relative flex-1 min-w-[200px]">
            <div
              className="flex items-center gap-2 rounded-2xl px-4 py-3 transition-all duration-300"
              style={{
                background: "var(--bg-hover)",
                border: `1px solid ${inputValue ? theme.glow : "var(--border-strong)"}`,
                boxShadow: inputValue ? `0 0 20px ${theme.glow}` : "none",
              }}
            >
              <Search size={16} style={{ color: inputValue ? theme.from : "var(--text-secondary)", flexShrink: 0 }} />
              <input
                ref={inputRef}
                value={inputValue}
                onChange={e => setInputValue(e.target.value)}
                placeholder="搜索电影、剧集、动漫..."
                className="flex-1 bg-transparent outline-none text-sm"
                style={{ color: "var(--text-primary)" }}
                onKeyDown={e => {
                  if (e.key === "Enter") {
                    triggerSearch();
                  }
                }}
              />
              {inputValue && (
                <button
                  onClick={clearInput}
                  className="shrink-0 transition-colors duration-150"
                  style={{ color: "var(--text-secondary)" }}
                  onMouseEnter={e => (e.currentTarget.style.color = theme.from)}
                  onMouseLeave={e => (e.currentTarget.style.color = "var(--text-secondary)")}
                >
                  <X size={14} />
                </button>
              )}
            </div>
          </div>
        </div>
      </div>

      {/* 搜索历史气泡 */}
      <div className="mb-6">
        <SearchHistoryBubbles
          onSelect={handleHistorySelect}
          themeFrom={theme.from}
          themeGlow={theme.glow}
        />
      </div>

      {/* 工具栏：分组切换 + 搜索状态 */}
      <div className="mb-6 space-y-3">
        {/* 第二行：分组模式切换 + 搜索状态 */}
        <div className="flex items-center gap-4 flex-wrap">
          {/* 分组模式切换 */}
          <div
            className="flex items-center rounded-xl overflow-hidden"
            style={{ background: "var(--bg-hover)", border: "1px solid var(--border-strong)" }}
          >
            <button
              onClick={() => setGroupMode("resource")}
              className="flex items-center gap-1.5 px-3 py-2 text-xs transition-all duration-200"
              style={{
                background: groupMode === "resource" ? theme.subtle : "transparent",
                color: groupMode === "resource" ? theme.from : "var(--text-secondary)",
                fontFamily: "var(--font-display)",
              }}
            >
              <LayoutGrid size={12} />
              按资源
            </button>
            <button
              onClick={() => setGroupMode("name")}
              className="flex items-center gap-1.5 px-3 py-2 text-xs transition-all duration-200"
              style={{
                background: groupMode === "name" ? theme.subtle : "transparent",
                color: groupMode === "name" ? theme.from : "var(--text-secondary)",
                fontFamily: "var(--font-display)",
              }}
            >
              <List size={12} />
              按名称
            </button>
          </div>

          {/* 搜索状态 */}
          {searching && (
            <div className="flex items-center gap-2">
              <Loader2 size={14} className="animate-spin" style={{ color: theme.from }} />
              <span className="text-xs" style={{ color: "var(--text-secondary)" }}>搜索中... 已找到 {results.length} 条结果</span>
            </div>
          )}
          {searchComplete && !searching && (
            <span className="text-xs" style={{ color: "var(--text-secondary)" }}>搜索完成，共 {totalResults} 条结果</span>
          )}
        </div>
      </div>

      {/* 错误提示 */}
      {errors.length > 0 && (
        <div className="mb-6 space-y-2">
          {errors.map((err, i) => (
            <div
              key={i}
              className="flex items-center gap-2 px-4 py-2 rounded-xl"
              style={{ background: "rgba(220,38,38,0.08)", border: "1px solid rgba(220,38,38,0.15)" }}
            >
              <AlertCircle size={14} style={{ color: "#fb7185" }} />
              <span className="text-xs" style={{ color: "#fb7185" }}>
                {err.resource_domain ? `[${err.resource_domain}] ` : ""}{err.message}
              </span>
            </div>
          ))}
        </div>
      )}

      {/* 搜索结果 */}
      {groupKeys.length > 0 && (
        <div className="space-y-8">
          {groupKeys.map(key => {
            const group = groupedResults[key];
            const isNameGroup = groupMode === "name";
            return (
              <section key={key}>
                {/* 分组标题 */}
                <div className="flex items-center gap-3 mb-4">
                  <div
                    className="w-1 h-5 rounded-full"
                    style={{ background: `linear-gradient(to bottom, ${theme.from}, ${theme.to})` }}
                  />
                  <h2
                    className="text-sm"
                    style={{ color: "var(--text-primary)", fontFamily: "var(--font-display)", fontWeight: 600 }}
                  >
                    {group.label}
                    {isNameGroup && (
                      <span className="ml-2 text-xs" style={{ color: theme.from, fontWeight: 400 }}>
                        共{group.items.length}个资源
                      </span>
                    )}
                  </h2>
                  {groupMode === "resource" && doneSites.has(key) && (
                    <span className="text-[10px] px-1.5 py-0.5 rounded-md" style={{ background: theme.subtle, color: theme.from }}>
                      {group.items.length}条
                    </span>
                  )}
                </div>

                {/* 结果列表 */}
                {groupMode === "name" ? (
                  <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-4">
                    <NameGroupedCard
                      items={group.items}
                      label={group.label}
                      themeFrom={theme.from}
                      themeTo={theme.to}
                      themeGlow={theme.glow}
                      themeSubtle={theme.subtle}
                      onClick={(item) => handleResultClick(item, key)}
                    />
                  </div>
                ) : (
                  <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-4">
                    {group.items.map((item, idx) => (
                      <SearchResultCard
                        key={`${item.resource_domain}-${idx}`}
                        item={item}
                        themeFrom={theme.from}
                        themeTo={theme.to}
                        themeGlow={theme.glow}
                        themeSubtle={theme.subtle}
                        onClick={() => handleResultClick(item, key)}
                      />
                    ))}
                  </div>
                )}
              </section>
            );
          })}
        </div>
      )}

      {/* 空状态 */}
      {searchInitiated && !searching && results.length === 0 && errors.length > 0 && (
        <div className="flex flex-col items-center justify-center py-20">
          <AlertCircle size={48} style={{ color: "var(--text-tertiary)" }} />
          <p className="mt-4 text-sm" style={{ color: "var(--text-secondary)" }}>未找到相关结果</p>
        </div>
      )}

      {/* 未搜索状态 */}
      {!searchInitiated && !queryFromUrl && (
        <div className="flex flex-col items-center justify-center py-20">
          <Search size={48} style={{ color: "var(--text-tertiary)" }} />
          <p className="mt-4 text-sm" style={{ color: "var(--text-secondary)" }}>输入关键词开始搜索</p>
        </div>
      )}
    </div>
  );
}
