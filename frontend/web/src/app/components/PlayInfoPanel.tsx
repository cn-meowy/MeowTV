import { useState } from "react";
import {
  Star, Calendar, Film, MapPin, Languages, Globe,
  ChevronDown, ChevronUp, Play
} from "lucide-react";
import * as Collapsible from "@radix-ui/react-collapsible";
import type { ResourceDetailResp } from "@/types/api";
import { buildResourceImageUrl } from "@/api/search";
import { useThemeStore } from "@/stores/theme";
import { THEMES } from "./Navbar";
import { FavoriteButton } from "./FavoriteButton";

interface PlayInfoPanelProps {
  detail: ResourceDetailResp;
  /** 收藏按钮所需参数 */
  groupKey: string;
  site: string;
}

export function PlayInfoPanel({ detail, groupKey, site }: PlayInfoPanelProps) {
  const [imgError, setImgError] = useState(false);
  const [descExpanded, setDescExpanded] = useState(false);
  const [infoExpanded, setInfoExpanded] = useState(false);
  const activeTheme = useThemeStore((s) => s.activeTheme);
  const theme = THEMES[activeTheme];

  const coverUrl = detail.vod_pic ? buildResourceImageUrl(detail.vod_pic) : "";

  const stripHtml = (html: string) => html.replace(/<[^>]*>/g, "").trim();
  const blurb = detail.vod_blurb || (detail.vod_content ? stripHtml(detail.vod_content) : "");
  const isLongDesc = blurb.length > 120;
  const displayDesc = descExpanded ? blurb : (isLongDesc ? blurb.slice(0, 120) + "…" : blurb);

  return (
    <Collapsible.Root open={infoExpanded} onOpenChange={setInfoExpanded}>
      <div
        className="rounded-xl overflow-hidden"
        style={{ background: "var(--bg-surface)", border: "1px solid var(--border-default)" }}
      >
        {/* 头部：封面 + 基本信息 — 始终可见 */}
        <div className="flex gap-4 p-4">
          {/* 封面 */}
          <div
            className="relative w-24 h-36 shrink-0 rounded-lg overflow-hidden"
            style={{ background: "var(--bg-elevated)" }}
          >
            {coverUrl && !imgError ? (
              <img
                src={coverUrl}
                alt={detail.vod_name}
                className="w-full h-full object-cover"
                onError={() => setImgError(true)}
              />
            ) : (
              <div className="w-full h-full flex items-center justify-center">
                <Play size={24} style={{ color: "var(--text-tertiary)" }} />
              </div>
            )}
            {/* 评分角标 */}
            {(detail.vod_douban_score || detail.vod_score) && (
              <div
                className="absolute top-1.5 right-1.5 flex items-center gap-0.5 px-1.5 py-0.5 rounded-md"
                style={{ background: "rgba(0,0,0,0.8)", backdropFilter: "blur(8px)" }}
              >
                <Star size={9} style={{ color: "#fbbf24", fill: "#fbbf24" }} />
                <span className="text-[10px]" style={{ color: "#fbbf24", fontFamily: "var(--font-display)", fontWeight: 700 }}>
                  {parseFloat(detail.vod_douban_score || detail.vod_score || "0").toFixed(1)}
                </span>
              </div>
            )}
          </div>

          {/* 信息 */}
          <div className="flex-1 min-w-0 flex flex-col gap-1.5">
            {/* 标题行 + 收藏按钮 */}
            <div className="flex items-start justify-between gap-2">
              <h1
                className="text-lg leading-tight truncate"
                style={{ color: "var(--text-primary)", fontFamily: "var(--font-display)", fontWeight: 800 }}
              >
                {detail.vod_name}
              </h1>
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
            </div>
            {detail.vod_sub && (
              <p className="text-xs truncate" style={{ color: "var(--text-secondary)" }}>{detail.vod_sub}</p>
            )}

            {/* 元信息行 */}
            <div className="flex items-center gap-2 flex-wrap">
              {detail.vod_year && (
                <span className="flex items-center gap-0.5 text-[11px]" style={{ color: "var(--text-muted)" }}>
                  <Calendar size={10} />{detail.vod_year}
                </span>
              )}
              {detail.type_name && (
                <span className="flex items-center gap-0.5 text-[11px]" style={{ color: theme.from }}>
                  <Film size={10} />{detail.type_name}
                </span>
              )}
              {detail.vod_area && (
                <span className="flex items-center gap-0.5 text-[11px]" style={{ color: "var(--text-muted)" }}>
                  <MapPin size={10} />{detail.vod_area}
                </span>
              )}
              {detail.vod_lang && (
                <span className="flex items-center gap-0.5 text-[11px]" style={{ color: "var(--text-muted)" }}>
                  <Languages size={10} />{detail.vod_lang}
                </span>
              )}
              <span className="flex items-center gap-0.5 text-[11px]" style={{ color: theme.from }}>
                <Globe size={10} />{detail.resource_name}
              </span>
            </div>

            {/* 评分行 */}
            {(detail.vod_douban_score || detail.vod_score) && (
              <div className="flex items-center gap-3">
                {detail.vod_douban_score && (
                  <div className="flex items-center gap-1">
                    <Star size={12} style={{ color: "#fbbf24", fill: "#fbbf24" }} />
                    <span className="text-[10px]" style={{ color: "var(--text-muted)" }}>豆瓣</span>
                    <span className="text-xs" style={{ color: "#fbbf24", fontFamily: "var(--font-display)", fontWeight: 700 }}>
                      {parseFloat(detail.vod_douban_score).toFixed(1)}
                    </span>
                  </div>
                )}
                {detail.vod_score && detail.vod_douban_score !== detail.vod_score && (
                  <div className="flex items-center gap-1">
                    <Star size={12} style={{ color: theme.from, fill: theme.from }} />
                    <span className="text-[10px]" style={{ color: "var(--text-muted)" }}>资源站</span>
                    <span className="text-xs" style={{ color: theme.from, fontFamily: "var(--font-display)", fontWeight: 700 }}>
                      {parseFloat(detail.vod_score).toFixed(1)}
                    </span>
                  </div>
                )}
              </div>
            )}

            {/* 类型标签 */}
            {detail.vod_class && (
              <div className="flex gap-1 flex-wrap">
                {detail.vod_class.split(",").map((g, i) => (
                  <span
                    key={i}
                    className="text-[10px] px-1.5 py-0.5 rounded-md"
                    style={{ background: "var(--bg-elevated)", color: "var(--text-tertiary)" }}
                  >
                    {g.trim()}
                  </span>
                ))}
              </div>
            )}

            {/* 备注 */}
            {detail.vod_remarks && (
              <span
                className="text-[10px] px-1.5 py-0.5 rounded-md self-start"
                style={{ background: theme.subtle, color: theme.from, fontFamily: "var(--font-display)" }}
              >
                {detail.vod_remarks}
              </span>
            )}
          </div>
        </div>

        {/* 折叠触发器 */}
        <Collapsible.Trigger asChild>
          <button
            className="w-full flex items-center justify-center gap-1 py-1.5 text-[10px] transition-all duration-200"
            style={{
              color: "var(--text-tertiary)",
              background: "transparent",
              borderTop: "1px solid var(--border-subtle)",
              fontFamily: "var(--font-display)",
            }}
            onMouseEnter={(e) => {
              e.currentTarget.style.background = "var(--bg-hover)";
              e.currentTarget.style.color = "var(--text-secondary)";
            }}
            onMouseLeave={(e) => {
              e.currentTarget.style.background = "transparent";
              e.currentTarget.style.color = "var(--text-tertiary)";
            }}
          >
            {infoExpanded ? (
              <><ChevronUp size={10} />收起详情</>
            ) : (
              <><ChevronDown size={10} />展开详情</>
            )}
          </button>
        </Collapsible.Trigger>

        {/* 可折叠内容：导演 + 演员 + 简介 */}
        <Collapsible.Content>
          <div className="px-4 pb-3 space-y-2" style={{ animation: "slideDown 200ms ease-out" }}>
            {/* 导演 & 演员 */}
            {detail.vod_director && (
              <p className="text-[11px]" style={{ color: "var(--text-muted)" }}>
                <span style={{ color: "var(--text-secondary)", fontWeight: 500 }}>导演: </span>{detail.vod_director}
              </p>
            )}
            {detail.vod_actor && (
              <p className="text-[11px] leading-relaxed" style={{ color: "var(--text-muted)" }}>
                <span style={{ color: "var(--text-secondary)", fontWeight: 500 }}>演员: </span>{detail.vod_actor}
              </p>
            )}

            {/* 简介 */}
            {blurb && (
              <div>
                <p className="text-[11px] leading-relaxed" style={{ color: "var(--text-muted)" }}>
                  {displayDesc}
                </p>
                {isLongDesc && (
                  <button
                    onClick={() => setDescExpanded(!descExpanded)}
                    className="flex items-center gap-0.5 mt-1 text-[10px] transition-colors"
                    style={{ color: theme.from, fontFamily: "var(--font-display)" }}
                  >
                    {descExpanded ? <><ChevronUp size={10} />收起简介</> : <><ChevronDown size={10} />展开简介</>}
                  </button>
                )}
              </div>
            )}
          </div>
        </Collapsible.Content>
      </div>
    </Collapsible.Root>
  );
}
