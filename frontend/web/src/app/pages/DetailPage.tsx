import { useState, useEffect, useCallback } from "react";
import { useSearchParams, useNavigate } from "react-router";
import { ArrowLeft, Loader2, AlertCircle, Download } from "lucide-react";
import { useThemeStore } from "@/stores/theme";
import { THEMES } from "@/app/components/Navbar";
import { GradientText } from "@/app/components/GradientText";
import { DetailCard } from "@/app/components/DetailCard";
import { ResourceSwitcher } from "@/app/components/ResourceSwitcher";
import { PlaySourceList } from "@/app/components/PlaySourceList";
import { DownloadEpisodeDialog } from "@/app/components/DownloadEpisodeDialog";
import { FavoriteButton } from "@/app/components/FavoriteButton";
import { getResourceDetail, parsePlayUrl, parsePlaySources, getCachedGroupData } from "@/api/search";
import { useM3u8Check } from "@/hooks/useM3u8Check";
import type { SearchResultItem, ResourceDetailResp, PlayEpisode, PlaySource } from "@/types/api";

export default function DetailPage() {
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();
  const activeTheme = useThemeStore((s) => s.activeTheme);
  const theme = THEMES[activeTheme];

  const groupKey = searchParams.get("group_key") || "";
  const name = searchParams.get("name") || "";
  const site = searchParams.get("site") || "";

  const [groupItems, setGroupItems] = useState<SearchResultItem[]>([]);
  const [activeDomain, setActiveDomain] = useState(site);
  const [detail, setDetail] = useState<ResourceDetailResp | null>(null);
  const [episodes, setEpisodes] = useState<PlayEpisode[]>([]);
  const [sources, setSources] = useState<PlaySource[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [downloadOpen, setDownloadOpen] = useState(false);

  // ====== m3u8 链接检测 ======
  const m3u8Check = useM3u8Check();

  // 当播放源变化时，批量检测所有剧集链接
  useEffect(() => {
    if (sources.length === 0) return;
    // 收集所有 source 的所有剧集 URL
    const urls: string[] = [];
    for (const source of sources) {
      for (const ep of source.episodes) {
        if (ep.url && (ep.url.includes('.m3u8') || ep.url.includes('.mp4'))) {
          urls.push(ep.url);
        }
      }
    }
    if (urls.length > 0) {
      m3u8Check.checkUrls(urls);
    }
  }, [sources]);

  // 加载分组数据
  useEffect(() => {
    if (!groupKey) return;
    const cached = getCachedGroupData(groupKey);
    if (cached) {
      setGroupItems(cached);
    }
  }, [groupKey]);

  // 查询详情
  const fetchDetail = useCallback(async (resourceDomain: string, vodId: number | undefined) => {
    if (!resourceDomain || !vodId) {
      setError("缺少资源站点或视频ID信息");
      return;
    }
    setLoading(true);
    setError("");
    try {
      const resp = await getResourceDetail({ site: resourceDomain, vod_id: vodId });
      setDetail(resp);
      setEpisodes(parsePlayUrl(resp.vod_play_url || ""));
      setSources(parsePlaySources(resp.vod_play_url || "", resp.vod_play_from));
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : "获取详情失败";
      setError(msg);
      setDetail(null);
      setEpisodes([]);
    } finally {
      setLoading(false);
    }
  }, []);

  // 初始加载：根据 URL 的 site 参数找到对应的 item，获取 vod_id
  useEffect(() => {
    const targetItem = groupItems.find((item) => item.resource_domain === site);
    if (targetItem && targetItem.vod_id) {
      fetchDetail(targetItem.resource_domain, targetItem.vod_id);
    } else if (groupItems.length > 0 && site) {
      // groupItems 加载完成但找不到匹配 site，取第一个
      const first = groupItems[0];
      if (first?.vod_id) {
        setActiveDomain(first.resource_domain);
        fetchDetail(first.resource_domain, first.vod_id);
      }
    }
  }, [groupItems, site, fetchDetail]);

  // 切换资源
  function handleResourceChange(item: SearchResultItem) {
    if (item.resource_domain === activeDomain) return;
    setActiveDomain(item.resource_domain);
    fetchDetail(item.resource_domain, item.vod_id);
  }

  return (
    <div className="px-6 md:px-12 lg:px-16 py-8">
      {/* 顶部导航 */}
      <div className="flex items-center gap-3 mb-6">
        <button
          onClick={() => navigate(-1)}
          className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg transition-all duration-200"
          style={{ background: "var(--bg-hover)", color: "var(--text-muted)" }}
          onMouseEnter={(e) => {
            e.currentTarget.style.background = theme.subtle;
            e.currentTarget.style.color = theme.from;
          }}
          onMouseLeave={(e) => {
            e.currentTarget.style.background = "var(--bg-hover)";
            e.currentTarget.style.color = "var(--text-muted)";
          }}
        >
          <ArrowLeft size={14} />
          <span className="text-xs" style={{ fontFamily: "var(--font-display)" }}>返回</span>
        </button>
        <h1 style={{ fontFamily: "var(--font-display)", fontWeight: 800, fontSize: "1.25rem" }}>
          <GradientText from={theme.from} to={theme.to}>
            {name || "详情"}
          </GradientText>
        </h1>
        {/* 收藏按钮 */}
        {detail && (
          <FavoriteButton
            vodId={detail.vod_id}
            vodName={detail.vod_name}
            vodPic={detail.vod_pic}
            groupKey={groupKey}
            site={site}
            resourceDomain={detail.resource_domain}
            resourceName={detail.resource_name}
            mode="button"
          />
        )}

        {/* 下载按钮 */}
        {detail && sources.length > 0 && (
          <button
            onClick={() => setDownloadOpen(true)}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg transition-all duration-200"
            style={{ background: theme.subtle, color: theme.from, border: `1px solid ${theme.from}30` }}
            onMouseEnter={(e) => {
              e.currentTarget.style.background = theme.from;
              e.currentTarget.style.color = "#fff";
            }}
            onMouseLeave={(e) => {
              e.currentTarget.style.background = theme.subtle;
              e.currentTarget.style.color = theme.from;
            }}
          >
            <Download size={14} />
            <span className="text-xs" style={{ fontFamily: "var(--font-display)" }}>下载</span>
          </button>
        )}
      </div>

      {/* 加载状态 */}
      {loading && !detail && (
        <div className="flex items-center justify-center py-20">
          <Loader2 size={32} className="animate-spin" style={{ color: theme.from }} />
          <span className="ml-3 text-sm" style={{ color: "var(--text-secondary)" }}>加载中...</span>
        </div>
      )}

      {/* 错误提示 */}
      {error && !loading && (
        <div
          className="flex items-center gap-2 px-4 py-3 rounded-xl mb-6"
          style={{ background: "rgba(220,38,38,0.08)", border: "1px solid rgba(220,38,38,0.15)" }}
        >
          <AlertCircle size={16} style={{ color: "#fb7185" }} />
          <span className="text-sm" style={{ color: "#fb7185" }}>{error}</span>
        </div>
      )}

      {/* 详情卡片 */}
      {detail && <DetailCard detail={detail} />}

      {/* 切换加载指示 */}
      {loading && detail && (
        <div className="flex items-center gap-2 my-4">
          <Loader2 size={14} className="animate-spin" style={{ color: theme.from }} />
          <span className="text-xs" style={{ color: "var(--text-secondary)" }}>切换资源中...</span>
        </div>
      )}

      {/* 同组资源切换 */}
      <div className="mt-6">
        <ResourceSwitcher
          items={groupItems}
          activeDomain={activeDomain}
          onChange={handleResourceChange}
        />
      </div>

      {/* 剧集列表 */}
      <div className="mt-4">
        <PlaySourceList
          episodes={episodes}
          onEpisodeClick={(idx) => {
            const params = new URLSearchParams({
              group_key: groupKey,
              name: name,
              site: activeDomain,
              ep: String(idx),
            });
            navigate(`/play?${params.toString()}`);
          }}
          urlCheckStatuses={m3u8Check.statusMap}
          urlCheckErrors={m3u8Check.errorMap}
        />
      </div>

      {/* 无数据状态 */}
      {!loading && !detail && !error && groupItems.length === 0 && (
        <div className="flex flex-col items-center justify-center py-20">
          <AlertCircle size={48} style={{ color: "var(--text-tertiary)" }} />
          <p className="mt-4 text-sm" style={{ color: "var(--text-secondary)" }}>未找到分组数据，请从搜索页进入</p>
        </div>
      )}

      {/* 下载弹窗 */}
      {detail && sources.length > 0 && (
        <DownloadEpisodeDialog
          open={downloadOpen}
          onOpenChange={setDownloadOpen}
          sources={sources}
          vodId={detail.vod_id}
          vodName={detail.vod_name}
          vodPic={detail.vod_pic ?? ""}
          resourceDomain={detail.resource_domain}
          resourceName={detail.resource_name}
          groupKey={groupKey}
        />
      )}
    </div>
  );
}
