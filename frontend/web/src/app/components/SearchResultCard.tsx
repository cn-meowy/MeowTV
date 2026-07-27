import { useState } from "react";
import { Star, Play, Globe } from "lucide-react";
import type { SearchResultItem } from "@/types/api";
import { buildResourceImageUrl } from "@/api/search";
import { FavoriteButton } from "./FavoriteButton";

interface SearchResultCardProps {
  item: SearchResultItem;
  themeFrom: string;
  themeTo: string;
  themeGlow: string;
  themeSubtle: string;
  onClick?: (item: SearchResultItem) => void;
}

export function SearchResultCard({ item, themeFrom, themeTo, themeGlow, themeSubtle, onClick }: SearchResultCardProps) {
  const [hovered, setHovered] = useState(false);
  const [imgError, setImgError] = useState(false);
  const coverUrl = item.cover ? buildResourceImageUrl(item.cover) : "";
  const displayScore = item.douban_score || item.score || "";
  const hasPlayUrl = !!item.play_url;

  return (
    <div
      className="relative rounded-2xl overflow-hidden cursor-pointer transition-all duration-300 group"
      onClick={() => onClick?.(item)}
      style={{
        transform: hovered ? "translateY(-6px) scale(1.02)" : "translateY(0) scale(1)",
        boxShadow: hovered
          ? `0 20px 60px rgba(0,0,0,0.7), 0 0 0 1px var(--border-strong), 0 0 40px ${themeGlow}`
          : "var(--shadow-card), 0 0 0 1px var(--border-default)",
      }}
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
    >
      {/* Poster */}
      <div className="relative aspect-[2/3] overflow-hidden" style={{ background: "var(--bg-elevated)" }}>
        {coverUrl && !imgError ? (
          <img
            src={coverUrl}
            alt={item.title}
            className="w-full h-full object-cover transition-transform duration-500"
            style={{ transform: hovered ? "scale(1.08)" : "scale(1)" }}
            onError={() => setImgError(true)}
            loading="lazy"
          />
        ) : (
          <div className="w-full h-full flex items-center justify-center">
            <Play size={20} style={{ color: "var(--text-tertiary)" }} />
          </div>
        )}

        {/* Gradient overlay */}
        <div
          className="absolute inset-0"
          style={{
            background: hovered
              ? "linear-gradient(to top, rgba(0,0,0,0.95) 0%, rgba(0,0,0,0.4) 50%, transparent 100%)"
              : "linear-gradient(to top, rgba(0,0,0,0.8) 0%, transparent 60%)",
            transition: "background 0.3s",
          }}
        />

        {/* Badge - 可播放 */}
        {hasPlayUrl && (
          <div
            className="absolute top-2 left-2 px-2 py-0.5 rounded-lg text-xs"
            style={{
              background: `linear-gradient(135deg,${themeFrom},${themeTo})`,
              color: "#fff",
              fontFamily: "var(--font-display)",
              fontWeight: 600,
              letterSpacing: "0.06em",
            }}
          >
            可播放
          </div>
        )}

        {/* Remarks badge */}
        {!hasPlayUrl && item.remarks && (
          <div
            className="absolute top-2 left-2 px-2 py-0.5 rounded-lg text-xs"
            style={{
              background: themeSubtle,
              color: themeFrom,
              fontFamily: "var(--font-display)",
              fontWeight: 600,
            }}
          >
            {item.remarks}
          </div>
        )}

        {/* Rating */}
        {displayScore && (
          <div
            className="absolute top-2 left-2 flex items-center gap-1 px-2 py-0.5 rounded-lg"
            style={{ background: "rgba(0,0,0,0.7)", backdropFilter: "blur(8px)" }}
          >
            <Star size={10} style={{ color: "#fbbf24", fill: "#fbbf24" }} />
            <span className="text-xs" style={{ color: "#fbbf24", fontFamily: "var(--font-display)", fontWeight: 600 }}>
              {parseFloat(displayScore).toFixed(1)}
            </span>
          </div>
        )}

        {/* 收藏星标 */}
        <FavoriteButton
          vodId={item.vod_id}
          vodName={item.title}
          vodPic={item.cover}
          doubanId={item.douban_id}
          groupKey=""
          site={item.resource_domain}
          resourceDomain={item.resource_domain}
          resourceName={item.resource_name}
          mode="card"
        />

        {/* Hover play button */}
        <div
          className="absolute inset-0 flex items-center justify-center transition-opacity duration-300"
          style={{ opacity: hovered ? 1 : 0 }}
        >
          <button
            className="w-12 h-12 rounded-2xl flex items-center justify-center transition-transform duration-200 hover:scale-110"
            style={{ background: `linear-gradient(135deg,${themeFrom},${themeTo})`, boxShadow: `0 0 24px ${themeGlow}` }}
          >
            <Play size={18} color="#fff" fill="#fff" style={{ marginLeft: 2 }} />
          </button>
        </div>

        {/* Bottom info overlay */}
        <div className="absolute bottom-0 left-0 right-0 p-3">
          {/* Title */}
          <p
            className="text-sm mb-0.5 truncate"
            title={item.title}
            style={{ color: "#fff", fontFamily: "var(--font-display)", fontWeight: 600 }}
          >
            {item.title}
          </p>

          {/* Meta line: year / type / area */}
          <div className="flex items-center gap-2 mb-1">
            {item.year && <span className="text-xs" style={{ color: "rgba(255,255,255,0.6)" }}>{item.year}</span>}
            {item.type && <span className="text-xs" style={{ color: themeFrom }}>{item.type}</span>}
            {item.area && <span className="text-xs" style={{ color: "rgba(255,255,255,0.5)" }}>{item.area}</span>}
          </div>

          {/* Description - 2 line clamp */}
          {item.description && (
            <p
              className="mb-1"
              style={{
                color: "rgba(255,255,255,0.5)",
                fontSize: "11px",
                lineHeight: "1.4",
                display: "-webkit-box",
                WebkitLineClamp: 2,
                WebkitBoxOrient: "vertical",
                overflow: "hidden",
              }}
            >
              {item.description}
            </p>
          )}

          {/* Resource source */}
          <div className="flex items-center gap-1">
            <Globe size={9} style={{ color: themeFrom }} />
            <span className="text-[10px]" style={{ color: themeFrom, fontFamily: "var(--font-display)" }}>
              {item.resource_name}
            </span>
          </div>
        </div>
      </div>
    </div>
  );
}
