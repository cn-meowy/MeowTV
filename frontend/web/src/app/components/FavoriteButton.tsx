import { Star } from "lucide-react";
import { useFavoritesStore } from "@/stores/favorites";
import { useThemeStore } from "@/stores/theme";
import { THEMES } from "./Navbar";

interface FavoriteButtonProps {
  vodId?: number;
  vodName: string;
  vodPic?: string;
  doubanId?: string;
  groupKey?: string;
  site?: string;
  resourceDomain?: string;
  resourceName?: string;
  /**
   * 显示模式：
   * - "button"：带文字的按钮样式（详情页/播放页使用）
   * - "card"：纯图标的小星标（卡片右上角使用）
   */
  mode?: "button" | "card";
}

/**
 * 收藏按钮 — 支持切换收藏状态，
 * 收藏时星形填充+主题色，未收藏时空心。
 * 支持两种模式：button（带文字）和 card（纯图标小星标）。
 * 支持两种标识方式：vodId+resourceDomain 或 doubanId。
 */
export function FavoriteButton({
  vodId = 0,
  vodName,
  vodPic,
  doubanId = "",
  groupKey = "",
  site = "",
  resourceDomain = "",
  resourceName = "",
  mode = "button",
}: FavoriteButtonProps) {
  const activeTheme = useThemeStore((s) => s.activeTheme);
  const theme = THEMES[activeTheme];
  const toggleFavorite = useFavoritesStore((s) => s.toggleFavorite);
  const isFavorite = useFavoritesStore((s) => s.isFavorite);

  const favorited = isFavorite(vodId, resourceDomain, doubanId);

  const handleToggle = (e: React.MouseEvent) => {
    e.stopPropagation(); // 防止卡片点击事件冒泡
    toggleFavorite({
      vodId,
      vodName,
      vodPic,
      doubanId,
      groupKey,
      site,
      resourceDomain,
      resourceName,
      createdAt: Date.now(),
    });
  };

  // 卡片模式：右上角小星标
  if (mode === "card") {
    return (
      <button
        onClick={handleToggle}
        className="absolute top-2 right-2 z-10 w-7 h-7 rounded-full flex items-center justify-center transition-all duration-200"
        style={{
          background: favorited
            ? `linear-gradient(135deg, ${theme.from}, ${theme.to})`
            : "rgba(0,0,0,0.5)",
          backdropFilter: "blur(8px)",
          boxShadow: favorited ? `0 0 12px ${theme.glow}` : "none",
        }}
        onMouseEnter={(e) => {
          if (!favorited) {
            e.currentTarget.style.background = "rgba(0,0,0,0.7)";
            e.currentTarget.style.transform = "scale(1.15)";
          }
        }}
        onMouseLeave={(e) => {
          if (!favorited) {
            e.currentTarget.style.background = "rgba(0,0,0,0.5)";
            e.currentTarget.style.transform = "scale(1)";
          }
        }}
      >
        <Star
          size={14}
          style={{
            fill: favorited ? "#fff" : "none",
            color: favorited ? "#fff" : "rgba(255,255,255,0.7)",
            transition: "all 0.2s",
          }}
        />
      </button>
    );
  }

  // 按钮模式：带文字
  return (
    <button
      onClick={handleToggle}
      className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs transition-all duration-200"
      style={{
        background: favorited ? theme.subtle : "var(--bg-elevated)",
        color: favorited ? theme.from : "var(--text-muted)",
        border: favorited ? `1px solid ${theme.from}30` : "1px solid var(--border-subtle)",
        fontFamily: "var(--font-display)",
        fontWeight: favorited ? 600 : 400,
      }}
      onMouseEnter={(e) => {
        if (!favorited) {
          e.currentTarget.style.background = "var(--bg-hover)";
          e.currentTarget.style.color = theme.from;
        }
      }}
      onMouseLeave={(e) => {
        if (!favorited) {
          e.currentTarget.style.background = "var(--bg-elevated)";
          e.currentTarget.style.color = "var(--text-muted)";
        }
      }}
    >
      <Star
        size={13}
        style={{
          fill: favorited ? theme.from : "none",
          transition: "all 0.2s",
        }}
      />
      <span>{favorited ? "已收藏" : "收藏"}</span>
    </button>
  );
}
