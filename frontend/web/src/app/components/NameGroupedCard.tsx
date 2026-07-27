import { useState, useRef, useEffect, useCallback } from "react";
import { Star, Play, Globe } from "lucide-react";
import type { SearchResultItem } from "@/types/api";
import { buildResourceImageUrl } from "@/api/search";
import { FavoriteButton } from "./FavoriteButton";

interface NameGroupedCardProps {
  items: SearchResultItem[];
  label: string;
  themeFrom: string;
  themeTo: string;
  themeGlow: string;
  themeSubtle: string;
  onClick?: (item: SearchResultItem) => void;
}

function firstOf<K extends keyof SearchResultItem>(items: SearchResultItem[], key: K): SearchResultItem[K] | undefined {
  return items.find(item => item[key] != null && item[key] !== "")?.[key];
}

function pickScore(items: SearchResultItem[]): string {
  const db = items.find(item => item.douban_score && item.douban_score !== "");
  if (db) return db.douban_score!;
  const sc = items.find(item => item.score && item.score !== "");
  return sc?.score || "";
}

export function NameGroupedCard({ items, label, themeFrom, themeTo, themeGlow, themeSubtle, onClick }: NameGroupedCardProps) {
  const [hovered, setHovered] = useState(false);
  const [imgError, setImgError] = useState(false);

  const cover = firstOf(items, "cover");
  const coverUrl = cover ? buildResourceImageUrl(cover) : "";
  const displayScore = pickScore(items);
  const year = firstOf(items, "year");
  const type = firstOf(items, "type");
  const area = firstOf(items, "area");
  const description = firstOf(items, "description");
  const hasPlayUrl = items.some(item => !!item.play_url);

  const tagContainerRef = useRef<HTMLDivElement>(null);
  const [overflowCount, setOverflowCount] = useState(0);

  const measureOverflow = useCallback(() => {
    const container = tagContainerRef.current;
    if (!container) return;
    const tags = container.children;
    if (tags.length === 0) return;

    const firstTag = tags[0] as HTMLElement;
    const lineHeight = firstTag.offsetHeight;
    const maxVisibleHeight = lineHeight * 2 + 6;

    let visibleCount = 0;
    for (let i = 0; i < tags.length; i++) {
      const tag = tags[i] as HTMLElement;
      if (tag.offsetTop + tag.offsetHeight <= maxVisibleHeight) {
        visibleCount = i + 1;
      } else {
        break;
      }
    }
    setOverflowCount(items.length - visibleCount);
  }, [items.length]);

  useEffect(() => {
    measureOverflow();
    window.addEventListener("resize", measureOverflow);
    return () => window.removeEventListener("resize", measureOverflow);
  }, [measureOverflow]);

  return (
    <div
      className="relative rounded-2xl overflow-hidden cursor-pointer transition-all duration-300 group"
      onClick={() => onClick?.(items[0])}
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
            alt={label}
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

        {/* Resource count badge */}
        <div
          className="absolute top-2 left-2 px-2 py-0.5 rounded-lg text-xs"
          style={{
            background: hasPlayUrl ? `linear-gradient(135deg,${themeFrom},${themeTo})` : themeSubtle,
            color: hasPlayUrl ? "#fff" : themeFrom,
            fontFamily: "var(--font-display)",
            fontWeight: 600,
            letterSpacing: "0.06em",
            display: hasPlayUrl ? "none" : "block",
          }}
        >
          {items.length}个资源
        </div>

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

        {/* 收藏星标 — 使用分组中第一个有 vod_id 的 item */}
        <FavoriteButton
          vodId={items.find(i => i.vod_id)?.vod_id ?? 0}
          vodName={label}
          vodPic={cover ?? ""}
          doubanId={items.find(i => i.douban_id)?.douban_id ?? ""}
          groupKey=""
          site={items[0]?.resource_domain ?? ""}
          resourceDomain={items[0]?.resource_domain ?? ""}
          resourceName={items[0]?.resource_name ?? ""}
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
            title={label}
            style={{ color: "#fff", fontFamily: "var(--font-display)", fontWeight: 600 }}
          >
            {label}
          </p>

          {/* Meta line: year / type / area + resource count */}
          <div className="flex items-center gap-2 mb-1">
            {year && <span className="text-xs" style={{ color: "rgba(255,255,255,0.6)" }}>{year}</span>}
            {type && <span className="text-xs" style={{ color: themeFrom }}>{type}</span>}
            {area && <span className="text-xs" style={{ color: "rgba(255,255,255,0.5)" }}>{area}</span>}
            {hasPlayUrl && (
              <span
                className="text-[10px] px-1.5 py-0.5 rounded-md"
                style={{ background: themeSubtle, color: themeFrom }}
              >
                共{items.length}个资源
              </span>
            )}
          </div>

          {/* Description - 2 line clamp */}
          {description && (
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
              {description}
            </p>
          )}

          {/* Resource source tags */}
          <div
            ref={tagContainerRef}
            className="flex flex-wrap gap-1"
            style={{ maxHeight: "calc(18px * 2 + 4px)", overflow: "hidden" }}
          >
            {items.map((item) => (
              <span
                key={item.resource_domain}
                className="inline-flex items-center gap-0.5 text-[10px] px-1.5 py-0.5 rounded-md"
                style={{ background: "rgba(0,0,0,0.5)", color: "rgba(255,255,255,0.7)" }}
              >
                <Globe size={8} />
                {item.resource_name}
              </span>
            ))}
          </div>
          {overflowCount > 0 && (
            <span className="text-[10px] mt-0.5 inline-block" style={{ color: themeFrom }}>
              +{overflowCount}个资源
            </span>
          )}
        </div>
      </div>
    </div>
  );
}
