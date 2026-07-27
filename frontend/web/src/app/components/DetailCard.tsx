import { useState } from "react";
import { Star, Play, Calendar, Globe, Film, MapPin, Languages } from "lucide-react";
import type { ResourceDetailResp } from "@/types/api";
import { buildResourceImageUrl } from "@/api/search";
import { useThemeStore } from "@/stores/theme";
import { THEMES } from "./Navbar";

interface DetailCardProps {
  detail: ResourceDetailResp;
}

export function DetailCard({ detail }: DetailCardProps) {
  const [imgError, setImgError] = useState(false);
  const activeTheme = useThemeStore((s) => s.activeTheme);
  const theme = THEMES[activeTheme];

  const coverUrl = detail.vod_pic ? buildResourceImageUrl(detail.vod_pic) : "";

  // 解析 HTML 内容（vod_content 可能包含 HTML 标签）
  const stripHtml = (html: string) => html.replace(/<[^>]*>/g, "").trim();
  const blurb = detail.vod_blurb || (detail.vod_content ? stripHtml(detail.vod_content) : "");
  const displayContent = blurb.length > 200 ? blurb.slice(0, 200) + "…" : blurb;

  return (
    <div className="relative rounded-2xl overflow-hidden" style={{ background: "var(--bg-surface)", border: "1px solid var(--border-default)" }}>
      {/* 背景模糊大图 */}
      {coverUrl && !imgError && (
        <div className="absolute inset-0 z-0">
          <img
            src={coverUrl}
            alt=""
            className="w-full h-full object-cover"
            style={{ filter: "blur(40px) brightness(0.3)", transform: "scale(1.2)" }}
            onError={() => setImgError(true)}
          />
          <div className="absolute inset-0" style={{ background: "linear-gradient(to bottom, var(--bg-surface), var(--bg-surface-strong))" }} />
        </div>
      )}

      {/* 内容区 */}
      <div className="relative z-10 flex gap-6 p-6">
        {/* 封面海报 */}
        <div
          className="relative w-40 h-60 shrink-0 rounded-xl overflow-hidden shadow-2xl"
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
              <Play size={32} style={{ color: "var(--text-tertiary)" }} />
            </div>
          )}
          {/* 评分角标 */}
          {(detail.vod_douban_score || detail.vod_score) && (
            <div
              className="absolute top-2 right-2 flex items-center gap-1 px-2 py-1 rounded-lg"
              style={{ background: "rgba(0,0,0,0.8)", backdropFilter: "blur(8px)" }}
            >
              <Star size={10} style={{ color: "#fbbf24", fill: "#fbbf24" }} />
              <span className="text-xs" style={{ color: "#fbbf24", fontFamily: "var(--font-display)", fontWeight: 700 }}>
                {parseFloat(detail.vod_douban_score || detail.vod_score || "0").toFixed(1)}
              </span>
            </div>
          )}
          {/* 备注角标 */}
          {detail.vod_remarks && (
            <div
              className="absolute bottom-2 left-2 px-2 py-0.5 rounded-md text-[10px]"
              style={{ background: theme.subtle, color: theme.from, fontFamily: "var(--font-display)" }}
            >
              {detail.vod_remarks}
            </div>
          )}
        </div>

        {/* 信息区 */}
        <div className="flex-1 min-w-0 flex flex-col gap-2">
          {/* 标题 */}
          <div>
            <h1
              className="text-2xl leading-tight"
              style={{ color: "var(--text-primary)", fontFamily: "var(--font-display)", fontWeight: 800 }}
            >
              {detail.vod_name}
            </h1>
            {detail.vod_sub && (
              <p className="text-sm mt-0.5" style={{ color: "var(--text-secondary)" }}>{detail.vod_sub}</p>
            )}
          </div>

          {/* 元信息行 */}
          <div className="flex items-center gap-3 flex-wrap">
            {detail.vod_year && (
              <span className="flex items-center gap-1 text-xs" style={{ color: "var(--text-muted)" }}>
                <Calendar size={11} />{detail.vod_year}
              </span>
            )}
            {detail.type_name && (
              <span className="flex items-center gap-1 text-xs" style={{ color: theme.from }}>
                <Film size={11} />{detail.type_name}
              </span>
            )}
            {detail.vod_area && (
              <span className="flex items-center gap-1 text-xs" style={{ color: "var(--text-muted)" }}>
                <MapPin size={11} />{detail.vod_area}
              </span>
            )}
            {detail.vod_lang && (
              <span className="flex items-center gap-1 text-xs" style={{ color: "var(--text-muted)" }}>
                <Languages size={11} />{detail.vod_lang}
              </span>
            )}
            <span className="flex items-center gap-1 text-xs" style={{ color: theme.from }}>
              <Globe size={11} />{detail.resource_name}
            </span>
          </div>

          {/* 评分行 */}
          {(detail.vod_douban_score || detail.vod_score) && (
            <div className="flex items-center gap-4">
              {detail.vod_douban_score && (
                <div className="flex items-center gap-1.5">
                  <Star size={14} style={{ color: "#fbbf24", fill: "#fbbf24" }} />
                  <span className="text-xs" style={{ color: "var(--text-muted)" }}>豆瓣</span>
                  <span className="text-sm" style={{ color: "#fbbf24", fontFamily: "var(--font-display)", fontWeight: 700 }}>
                    {parseFloat(detail.vod_douban_score).toFixed(1)}
                  </span>
                </div>
              )}
              {detail.vod_score && detail.vod_douban_score !== detail.vod_score && (
                <div className="flex items-center gap-1.5">
                  <Star size={14} style={{ color: theme.from, fill: theme.from }} />
                  <span className="text-xs" style={{ color: "var(--text-muted)" }}>资源站</span>
                  <span className="text-sm" style={{ color: theme.from, fontFamily: "var(--font-display)", fontWeight: 700 }}>
                    {parseFloat(detail.vod_score).toFixed(1)}
                  </span>
                </div>
              )}
            </div>
          )}

          {/* 类型标签 */}
          {detail.vod_class && (
            <div className="flex gap-1.5 flex-wrap">
              {detail.vod_class.split(",").map((g, i) => (
                <span
                  key={i}
                  className="text-[11px] px-2 py-0.5 rounded-md"
                  style={{ background: "var(--bg-hover)", color: "var(--text-tertiary)" }}
                >
                  {g.trim()}
                </span>
              ))}
            </div>
          )}

          {/* 导演 */}
          {detail.vod_director && (
            <p className="text-xs" style={{ color: "var(--text-muted)" }}>
              <span style={{ color: "var(--text-muted)" }}>导演: </span>{detail.vod_director}
            </p>
          )}

          {/* 演员 */}
          {detail.vod_actor && (
            <p className="text-xs leading-relaxed" style={{ color: "var(--text-muted)" }}>
              <span style={{ color: "var(--text-muted)" }}>演员: </span>{detail.vod_actor}
            </p>
          )}

          {/* 简介 */}
          {displayContent && (
            <p className="text-xs leading-relaxed mt-1" style={{ color: "var(--text-muted)" }}>
              {displayContent}
            </p>
          )}
        </div>
      </div>
    </div>
  );
}
