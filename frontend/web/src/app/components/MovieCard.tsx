import { useState } from "react";
import { Play, Star, Plus, Clock } from "lucide-react";
import { FavoriteButton } from "./FavoriteButton";

interface MovieCardProps {
  title: string;
  year: number | string;
  rating: number;
  genre: string;
  duration: string;
  image: string;
  badge?: string;
  doubanId?: string;
  themeFrom: string;
  themeTo: string;
  themeGlow: string;
  themeSubtle: string;
  onClick?: () => void;
}

export function MovieCard({ title, year, rating, genre, duration, image, badge, doubanId, themeFrom, themeTo, themeGlow, themeSubtle, onClick }: MovieCardProps) {
  const [hovered, setHovered] = useState(false);

  return (
    <div
      className="relative rounded-2xl overflow-hidden cursor-pointer transition-all duration-300 group"
      onClick={onClick}
      style={{
        transform: hovered ? "translateY(-6px) scale(1.02)" : "translateY(0) scale(1)",
        boxShadow: hovered ? `0 20px 60px rgba(0,0,0,0.7), 0 0 0 1px var(--border-strong), 0 0 40px ${themeGlow}` : "var(--shadow-card), 0 0 0 1px var(--border-default)",
      }}
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
    >
      {/* Poster */}
      <div className="relative aspect-[2/3] overflow-hidden">
        <img
          src={image}
          alt={title}
          loading="lazy"
          className="w-full h-full object-cover transition-transform duration-500"
          style={{ transform: hovered ? "scale(1.08)" : "scale(1)" }}
        />
        {/* Gradient overlay */}
        <div
          className="absolute inset-0"
          style={{
            background: hovered
              ? `linear-gradient(to top, rgba(0,0,0,0.95) 0%, rgba(0,0,0,0.4) 50%, transparent 100%)`
              : `linear-gradient(to top, rgba(0,0,0,0.8) 0%, transparent 60%)`,
            transition: "background 0.3s",
          }}
        />

        {/* Badge */}
        {badge && (
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
            {badge}
          </div>
        )}

        {/* Rating */}
        <div
          className="absolute top-2 left-2 flex items-center gap-1 px-2 py-0.5 rounded-lg"
          style={{ background: "rgba(0,0,0,0.7)", backdropFilter: "blur(8px)" }}
        >
          <Star size={10} style={{ color: "#fbbf24", fill: "#fbbf24" }} />
          <span className="text-xs" style={{ color: "#fbbf24", fontFamily: "var(--font-display)", fontWeight: 600 }}>{rating.toFixed(1)}</span>
        </div>

        {/* 收藏星标 */}
        <FavoriteButton
          vodName={title}
          vodPic={image}
          doubanId={doubanId}
          mode="card"
        />

        {/* Hover actions */}
        <div
          className="absolute inset-0 flex items-center justify-center gap-3 transition-opacity duration-300"
          style={{ opacity: hovered ? 1 : 0 }}
        >
          <button
            className="w-12 h-12 rounded-2xl flex items-center justify-center transition-transform duration-200 hover:scale-110"
            style={{ background: `linear-gradient(135deg,${themeFrom},${themeTo})`, boxShadow: `0 0 24px ${themeGlow}` }}
          >
            <Play size={18} color="#fff" fill="#fff" style={{ marginLeft: 2 }} />
          </button>
          <button
            className="w-9 h-9 rounded-xl flex items-center justify-center transition-all duration-200 hover:scale-110"
            style={{ background: "rgba(255,255,255,0.15)", backdropFilter: "blur(8px)" }}
          >
            <Plus size={16} color="#fff" />
          </button>
        </div>

        {/* Bottom info */}
        <div className="absolute bottom-0 left-0 right-0 p-3">
          <p
            className="text-sm mb-0.5 truncate"
            style={{ color: "#fff", fontFamily: "var(--font-display)", fontWeight: 600 }}
          >
            {title}
          </p>
          <div className="flex items-center gap-2">
            <span className="text-xs" style={{ color: "rgba(255,255,255,0.6)" }}>{year}</span>
            <span className="text-xs" style={{ color: themeFrom }}>{genre}</span>
            <span className="flex items-center gap-1 text-xs" style={{ color: "rgba(255,255,255,0.5)", marginLeft: "auto" }}>
              <Clock size={10} />{duration}
            </span>
          </div>
        </div>
      </div>
    </div>
  );
}
