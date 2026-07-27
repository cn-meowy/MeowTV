import { useState, useEffect, useCallback } from "react";
import { useNavigate } from "react-router";
import { Star, Search, Trash2, Globe, Play, X } from "lucide-react";
import { useThemeStore } from "@/stores/theme";
import { useFavoritesStore, type FavoriteRecord } from "@/stores/favorites";
import { THEMES } from "@/app/components/Navbar";
import { GradientText } from "@/app/components/GradientText";
import { getFavoritesList } from "@/api/user-data";

export default function FavoritePage() {
  const navigate = useNavigate();
  const activeTheme = useThemeStore((s) => s.activeTheme);
  const theme = THEMES[activeTheme];
  const localFavorites = useFavoritesStore((s) => s.favorites);
  const removeFavorite = useFavoritesStore((s) => s.removeFavorite);
  const clearAll = useFavoritesStore((s) => s.clearAll);

  const [keyword, setKeyword] = useState("");
  const [serverTotal, setServerTotal] = useState(0);
  const [showClearConfirm, setShowClearConfirm] = useState(false);

  useEffect(() => {
    getFavoritesList(1, 0).then(resp => setServerTotal(resp.total)).catch(() => {});
  }, [localFavorites]);

  const filteredFavorites = keyword.trim()
    ? localFavorites.filter(f => f.vodName.toLowerCase().includes(keyword.toLowerCase()))
    : localFavorites;

  const handleFavoriteClick = useCallback((record: FavoriteRecord) => {
    if (record.resourceDomain && record.vodId > 0) {
      const params = new URLSearchParams({
        group_key: record.groupKey || `fav_${record.vodId}`,
        name: record.vodName,
        site: record.resourceDomain,
        ep: "0",
      });
      navigate(`/play?${params.toString()}`);
    } else if (record.doubanId) {
      const params = new URLSearchParams({ q: record.vodName });
      params.set("douban_id", record.doubanId);
      navigate(`/search?${params.toString()}`);
    } else {
      navigate(`/search?q=${encodeURIComponent(record.vodName)}`);
    }
  }, [navigate]);

  const handleClearAll = useCallback(() => {
    clearAll();
    setShowClearConfirm(false);
  }, [clearAll]);

  return (
    <div className="px-6 md:px-12 lg:px-16 py-8">
      {/* 标题区 */}
      <div className="mb-6">
        <div className="flex items-center justify-between mb-4">
          <h1 style={{ fontFamily: "var(--font-display)", fontWeight: 800, fontSize: "1.5rem" }}>
            <GradientText from={theme.from} to={theme.to}>我的收藏</GradientText>
          </h1>
          <div className="flex items-center gap-2">
            <span className="text-xs" style={{ color: "var(--text-muted)", fontFamily: "var(--font-display)" }}>
              共 {serverTotal} 项
            </span>
            {localFavorites.length > 0 && !showClearConfirm && (
              <button
                onClick={() => setShowClearConfirm(true)}
                className="flex items-center gap-1 px-2 py-1 rounded-lg text-xs transition-all duration-200"
                style={{ color: "var(--text-muted)", background: "var(--bg-elevated)", border: "1px solid var(--border-subtle)" }}
                onMouseEnter={(e) => {
                  e.currentTarget.style.color = "#fb7185";
                  e.currentTarget.style.borderColor = "rgba(220,38,38,0.3)";
                }}
                onMouseLeave={(e) => {
                  e.currentTarget.style.color = "var(--text-muted)";
                  e.currentTarget.style.borderColor = "var(--border-subtle)";
                }}
              >
                <Trash2 size={12} />
                <span>清空</span>
              </button>
            )}
            {showClearConfirm && (
              <div className="flex items-center gap-2">
                <span className="text-xs" style={{ color: "#fb7185" }}>确认清空？</span>
                <button
                  onClick={handleClearAll}
                  className="px-2 py-1 rounded-lg text-xs"
                  style={{ background: "rgba(220,38,38,0.15)", color: "#fb7185", border: "1px solid rgba(220,38,38,0.3)" }}
                >
                  确认
                </button>
                <button
                  onClick={() => setShowClearConfirm(false)}
                  className="px-2 py-1 rounded-lg text-xs"
                  style={{ background: "var(--bg-elevated)", color: "var(--text-muted)", border: "1px solid var(--border-subtle)" }}
                >
                  取消
                </button>
              </div>
            )}
          </div>
        </div>

        {/* 搜索栏 */}
        <div className="relative max-w-md">
          <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2" style={{ color: "var(--text-muted)" }} />
          <input
            type="text"
            value={keyword}
            onChange={(e) => setKeyword(e.target.value)}
            placeholder="搜索收藏..."
            className="w-full pl-10 pr-10 py-2.5 rounded-xl text-sm outline-none transition-all duration-200"
            style={{
              background: "var(--bg-surface)",
              border: "1px solid var(--border-default)",
              color: "var(--text-primary)",
              fontFamily: "var(--font-body)",
            }}
            onFocus={(e) => {
              e.currentTarget.style.borderColor = theme.from;
              e.currentTarget.style.boxShadow = `0 0 0 3px ${theme.glow}`;
            }}
            onBlur={(e) => {
              e.currentTarget.style.borderColor = "var(--border-default)";
              e.currentTarget.style.boxShadow = "none";
            }}
          />
          {keyword && (
            <button onClick={() => setKeyword("")} className="absolute right-3 top-1/2 -translate-y-1/2" style={{ color: "var(--text-muted)" }}>
              <X size={14} />
            </button>
          )}
        </div>
      </div>

      {/* 空状态 */}
      {filteredFavorites.length === 0 && (
        <div className="flex flex-col items-center justify-center py-20">
          <Star size={48} style={{ color: "var(--text-tertiary)" }} />
          <p className="mt-4 text-sm" style={{ color: "var(--text-secondary)" }}>
            {keyword ? "未找到匹配的收藏" : "还没有收藏任何作品"}
          </p>
          {!keyword && (
            <button
              onClick={() => navigate("/search")}
              className="mt-4 px-4 py-2 rounded-xl text-sm transition-all duration-200"
              style={{
                background: `linear-gradient(135deg, ${theme.from}, ${theme.to})`,
                color: "#fff",
                fontFamily: "var(--font-display)",
                fontWeight: 600,
                boxShadow: `0 0 20px ${theme.glow}`,
              }}
            >
              去搜索收藏
            </button>
          )}
        </div>
      )}

      {/* 卡片网格 */}
      {filteredFavorites.length > 0 && (
        <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-4">
          {filteredFavorites.map((record) => (
            <FavoriteCard
              key={`${record.vodId}-${record.resourceDomain}-${record.doubanId}`}
              record={record}
              themeFrom={theme.from}
              themeTo={theme.to}
              themeGlow={theme.glow}
              themeSubtle={theme.subtle}
              onClick={() => handleFavoriteClick(record)}
              onRemove={() => removeFavorite(record.vodId, record.resourceDomain, record.doubanId)}
            />
          ))}
        </div>
      )}
    </div>
  );
}

function FavoriteCard({
  record,
  themeFrom,
  themeTo,
  themeGlow,
  themeSubtle,
  onClick,
  onRemove,
}: {
  record: FavoriteRecord;
  themeFrom: string;
  themeTo: string;
  themeGlow: string;
  themeSubtle: string;
  onClick: () => void;
  onRemove: () => void;
}) {
  const [hovered, setHovered] = useState(false);
  const [imgError, setImgError] = useState(false);
  const hasResource = !!(record.resourceDomain && record.vodId > 0);

  return (
    <div
      className="relative rounded-2xl overflow-hidden cursor-pointer transition-all duration-300 group"
      onClick={onClick}
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
        {record.vodPic && !imgError ? (
          <img
            src={record.vodPic}
            alt={record.vodName}
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

        {/* Badge - 有资源来源 */}
        {hasResource && (
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

        {/* 无资源来源标记 */}
        {!hasResource && (
          <div
            className="absolute top-2 left-2 px-2 py-0.5 rounded-lg text-xs"
            style={{
              background: themeSubtle,
              color: themeFrom,
              fontFamily: "var(--font-display)",
              fontWeight: 600,
            }}
          >
            豆瓣
          </div>
        )}

        {/* 取消收藏按钮 */}
        <button
          onClick={(e) => {
            e.stopPropagation();
            onRemove();
          }}
          className="absolute top-2 right-2 z-10 w-7 h-7 rounded-full flex items-center justify-center transition-all duration-200"
          style={{
            background: hovered ? "rgba(220,38,38,0.8)" : "rgba(0,0,0,0.5)",
            backdropFilter: "blur(8px)",
          }}
          onMouseEnter={(e) => {
            e.currentTarget.style.background = "rgba(220,38,38,0.9)";
            e.currentTarget.style.transform = "scale(1.15)";
          }}
          onMouseLeave={(e) => {
            e.currentTarget.style.background = hovered ? "rgba(220,38,38,0.8)" : "rgba(0,0,0,0.5)";
            e.currentTarget.style.transform = "scale(1)";
          }}
        >
          <Star size={14} style={{ fill: "#fff", color: "#fff" }} />
        </button>

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
          <p
            className="text-sm mb-0.5 truncate"
            title={record.vodName}
            style={{ color: "#fff", fontFamily: "var(--font-display)", fontWeight: 600 }}
          >
            {record.vodName}
          </p>
          <div className="flex items-center gap-2">
            {hasResource ? (
              <>
                <Globe size={9} style={{ color: themeFrom }} />
                <span className="text-[10px]" style={{ color: themeFrom, fontFamily: "var(--font-display)" }}>
                  {record.resourceName || record.resourceDomain}
                </span>
              </>
            ) : (
              <span className="text-[10px]" style={{ color: "rgba(255,255,255,0.5)" }}>
                点击搜索资源
              </span>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
