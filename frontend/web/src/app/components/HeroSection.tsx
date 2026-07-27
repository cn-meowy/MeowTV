import { useState, useEffect } from "react";
import { Play, ChevronLeft, ChevronRight, Star } from "lucide-react";
import { GradientText } from "./GradientText";

interface HeroItem {
  title: string;
  tagline?: string;
  description?: string;
  year: number;
  rating: number;
  genre: string;
  duration: string;
  image: string;
  doubanId?: string;
}

interface HeroSectionProps {
  items: HeroItem[];
  themeFrom: string;
  themeTo: string;
  themeMid: string;
  themeGlow: string;
  onPlay?: (item: HeroItem) => void;
}

export function HeroSection({ items, themeFrom, themeTo, themeMid, themeGlow, onPlay }: HeroSectionProps) {
  const [current, setCurrent] = useState(0);
  const [animating, setAnimating] = useState(false);

  useEffect(() => {
    const timer = setInterval(() => slide(1), 6000);
    return () => clearInterval(timer);
  }, [current]);

  const slide = (dir: number) => {
    if (animating) return;
    setAnimating(true);
    setTimeout(() => {
      setCurrent(c => (c + dir + items.length) % items.length);
      setAnimating(false);
    }, 300);
  };

  const item = items[current];

  return (
    <div
      className="relative w-full overflow-hidden"
      style={{ height: "70vh", minHeight: 460 }}
    >
      {/* Background image */}
      <div
        className="absolute inset-0 transition-opacity duration-700"
        style={{ opacity: animating ? 0 : 1 }}
      >
        <img src={item.image} alt={item.title} className="w-full h-full object-cover" />
        {/* Multi-layer overlay — kept as-is since it's on top of an image and always dark */}
        <div className="absolute inset-0" style={{ background: "linear-gradient(to right, rgba(6,6,16,0.95) 35%, rgba(6,6,16,0.5) 65%, rgba(6,6,16,0.2) 100%)" }} />
        <div className="absolute inset-0" style={{ background: "linear-gradient(to top, rgba(6,6,16,1) 0%, transparent 40%)" }} />
        <div className="absolute inset-0" style={{ background: `radial-gradient(ellipse at 20% 60%, ${themeGlow} 0%, transparent 50%)` }} />
      </div>

      {/* Content */}
      <div
        className="relative h-full flex flex-col justify-end pb-20 px-10 md:px-16 transition-opacity duration-300 max-w-2xl"
        style={{ opacity: animating ? 0 : 1 }}
      >
        {/* Genre badge */}
        <div className="flex items-center gap-2 mb-4">
          <span
            className="px-3 py-1 rounded-full text-xs tracking-widest"
            style={{
              background: `linear-gradient(135deg,${themeFrom},${themeTo})`,
              color: "#fff",
              fontFamily: "var(--font-display)",
              fontWeight: 700,
            }}
          >
            {item.genre.toUpperCase()}
          </span>
          <div className="flex items-center gap-1.5 px-3 py-1 rounded-full" style={{ background: "rgba(255,255,255,0.08)", backdropFilter: "blur(8px)" }}>
            <Star size={12} style={{ color: "#fbbf24", fill: "#fbbf24" }} />
            <span className="text-xs" style={{ color: "#fbbf24", fontFamily: "var(--font-display)", fontWeight: 600 }}>{item.rating.toFixed(1)}</span>
          </div>
          <span className="text-xs" style={{ color: "rgba(255,255,255,0.5)" }}>{item.year} · {item.duration}</span>
        </div>

        {/* Title */}
        <h1 className="mb-2 leading-tight" style={{ fontFamily: "var(--font-display)", fontWeight: 800, fontSize: "clamp(2rem, 4vw, 3.5rem)" }}>
          <GradientText from="#ffffff" to={themeFrom}>
            {item.title}
          </GradientText>
        </h1>
        <p className="text-sm mb-2" style={{ color: themeFrom, fontFamily: "var(--font-display)", fontWeight: 500 }}>{item.tagline}</p>
        <p
          className="text-sm mb-6 leading-relaxed"
          style={{ color: "rgba(255,255,255,0.65)", maxWidth: 480 }}
        >
          {item.description}
        </p>

        {/* CTA buttons */}
        <div className="flex items-center gap-3">
          <button
            onClick={() => onPlay?.(item)}
            className="flex items-center gap-2.5 px-6 py-3 rounded-2xl text-sm transition-all duration-200 hover:scale-105 active:scale-95"
            style={{
              background: `linear-gradient(135deg,${themeFrom},${themeTo})`,
              color: "#fff",
              fontFamily: "var(--font-display)",
              fontWeight: 600,
              boxShadow: `0 0 24px ${themeGlow}, 0 4px 12px rgba(0,0,0,0.4)`,
            }}
          >
            <Play size={16} fill="#fff" />
            立即播放
          </button>
        </div>
      </div>

      {/* Dots */}
      <div className="absolute bottom-6 left-1/2 -translate-x-1/2 flex gap-2">
        {items.map((_, i) => (
          <button
            key={i}
            onClick={() => setCurrent(i)}
            className="rounded-full transition-all duration-300"
            style={{
              width: i === current ? 24 : 6,
              height: 6,
              background: i === current ? `linear-gradient(135deg,${themeFrom},${themeTo})` : "rgba(255,255,255,0.25)",
              boxShadow: i === current ? `0 0 8px ${themeGlow}` : "none",
            }}
          />
        ))}
      </div>
    </div>
  );
}
