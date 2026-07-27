import { useState, useEffect, useCallback, useRef } from "react";
import { useNavigate } from "react-router";
import { HeroSection } from "@/app/components/HeroSection";
import { MovieCard } from "@/app/components/MovieCard";
import { GradientText } from "@/app/components/GradientText";
import { Skeleton } from "@/app/components/ui/skeleton";
import { THEMES } from "@/app/components/Navbar";
import { useThemeStore } from "@/stores/theme";
import { useAuthStore } from "@/stores/auth";
import { getSubjects, getTags } from "@/api/douban";
import { getTempToken } from "@/api/tempToken";
import { subjectToMovieCard, subjectToHeroItem } from "@/utils/douban";
import type { MovieCardData, HeroItemData } from "@/utils/douban";
import { TrendingUp, Flame, Clock, ChevronRight } from "lucide-react";
import { ContinueWatchingSection } from "@/app/components/ContinueWatchingSection";

// ── Section Header ───────────────────────────────────────────────────────────
function SectionHeader({ icon: Icon, title, themeFrom, themeTo, themeGlow }: { icon: React.ElementType; title: string; themeFrom: string; themeTo: string; themeGlow: string }) {
  return (
    <div className="flex items-center justify-between mb-6">
      <div className="flex items-center gap-3">
        <div
          className="w-8 h-8 rounded-xl flex items-center justify-center"
          style={{ background: `linear-gradient(135deg,${themeFrom},${themeTo})`, boxShadow: `0 0 16px ${themeGlow}` }}
        >
          <Icon size={15} color="#fff" />
        </div>
        <h2 className="tracking-wide" style={{ fontFamily: "var(--font-display)", fontWeight: 700, fontSize: "1.1rem" }}>
          <GradientText from="#ffffff" to={themeFrom}>{title}</GradientText>
        </h2>
      </div>
      <button
        className="flex items-center gap-1 text-xs px-3 py-1.5 rounded-xl transition-all duration-200"
        style={{ color: themeFrom, fontFamily: "var(--font-display)" }}
        onMouseEnter={e => { e.currentTarget.style.background = `rgba(${themeFrom},0.1)`; }}
        onMouseLeave={e => { e.currentTarget.style.background = "transparent"; }}
      >
        查看全部 <ChevronRight size={12} />
      </button>
    </div>
  );
}

// ── Genre Pills ──────────────────────────────────────────────────────────────
const DEFAULT_TAGS = ["热门", "最新", "经典", "豆瓣高分", "冷门佳片"];

interface GenrePillsProps {
  themeFrom: string;
  themeTo: string;
  themeGlow: string;
  themeSubtle: string;
  activeTag: string;
  onTagChange: (tag: string) => void;
}

function GenrePills({ themeFrom, themeTo, themeGlow, themeSubtle, activeTag, onTagChange }: GenrePillsProps) {
  const [tags, setTags] = useState<string[]>(DEFAULT_TAGS);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const resp = await getTags({ type: 'movie' });
        if (cancelled) return;
        const tagNames = (resp.tags ?? []).filter(Boolean);
        if (tagNames.length > 0) {
          setTags(tagNames);
        }
      } catch {
        // 失败时使用默认 tags
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => { cancelled = true; };
  }, []);

  return (
    <div className="flex gap-2 overflow-x-auto pb-2" style={{ scrollbarWidth: "none" }}>
      {tags.map(g => (
        <button
          key={g}
          onClick={() => onTagChange(g)}
          disabled={loading}
          className="shrink-0 px-4 py-1.5 rounded-full text-xs transition-all duration-200 whitespace-nowrap"
          style={{
            background: activeTag === g ? `linear-gradient(135deg,${themeFrom},${themeTo})` : "var(--bg-hover)",
            color: activeTag === g ? "#fff" : "var(--text-secondary)",
            border: activeTag === g ? "none" : "1px solid var(--border-strong)",
            boxShadow: activeTag === g ? `0 0 16px ${themeGlow}` : "none",
            fontFamily: "var(--font-display)",
            fontWeight: activeTag === g ? 600 : 400,
            opacity: loading ? 0.5 : 1,
          }}
        >
          {g}
        </button>
      ))}
    </div>
  );
}

// ── Frosted glass stats bar ──────────────────────────────────────────────────
function StatsBar({ themeFrom, themeGlow }: { themeFrom: string; themeGlow: string }) {
  const stats = [
    { label: "电影", value: "12,400+" },
    { label: "剧集", value: "3,800+" },
    { label: "动漫", value: "5,200+" },
    { label: "4K 片源", value: "2,100+" },
  ];
  return (
    <div
      className="flex items-center justify-center gap-8 py-4 rounded-2xl mx-10 md:mx-16 -mt-6 relative z-10 mb-12"
      style={{
        background: "var(--bg-surface-strong)",
        backdropFilter: "blur(20px)",
        WebkitBackdropFilter: "blur(20px)",
        border: "1px solid var(--border-strong)",
        boxShadow: `0 8px 32px rgba(0,0,0,0.5), 0 0 0 1px var(--border-subtle), inset 0 1px 0 var(--border-default)`,
      }}
    >
      {stats.map((s, i) => (
        <div key={s.label} className="flex items-center gap-6">
          <div className="text-center">
            <p className="text-lg" style={{ fontFamily: "var(--font-display)", fontWeight: 700 }}>
              <GradientText from="#ffffff" to={themeFrom}>{s.value}</GradientText>
            </p>
            <p className="text-xs" style={{ color: "var(--text-secondary)", fontFamily: "var(--font-display)" }}>{s.label}</p>
          </div>
          {i < stats.length - 1 && <div className="w-px h-8" style={{ background: "var(--border-strong)" }} />}
        </div>
      ))}
    </div>
  );
}

// ── Skeleton placeholders ────────────────────────────────────────────────────
function HeroSkeleton() {
  return (
    <div className="relative w-full h-[520px] md:h-[600px] rounded-b-3xl overflow-hidden">
      <Skeleton className="absolute inset-0 w-full h-full rounded-b-3xl" />
      <div className="absolute bottom-0 left-0 right-0 p-10 md:p-16 space-y-3">
        <Skeleton className="h-8 w-48" />
        <Skeleton className="h-5 w-32" />
        <Skeleton className="h-4 w-80" />
      </div>
    </div>
  );
}

function CardGridSkeleton({ count = 6 }: { count?: number }) {
  return (
    <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-4">
      {Array.from({ length: count }).map((_, i) => (
        <div key={i} className="space-y-2">
          <Skeleton className="aspect-[2/3] w-full rounded-xl" />
          <Skeleton className="h-4 w-3/4" />
          <Skeleton className="h-3 w-1/2" />
        </div>
      ))}
    </div>
  );
}

// ── Home Page ────────────────────────────────────────────────────────────────
export default function HomePage() {
  const activeTheme = useThemeStore((s) => s.activeTheme);
  const theme = THEMES[activeTheme];
  const isAuthenticated = useAuthStore((s) => s.isAuthenticated);
  const navigate = useNavigate();

  // 数据状态
  const [heroItems, setHeroItems] = useState<HeroItemData[]>([]);
  const [movieCards, setMovieCards] = useState<MovieCardData[]>([]);
  const [tvCards, setTvCards] = useState<MovieCardData[]>([]);

  // 当前选中的电影标签
  const [activeTag, setActiveTag] = useState("热门");
  const initialLoadDone = useRef(false);

  // loading 状态
  const [heroLoading, setHeroLoading] = useState(true);
  const [movieLoading, setMovieLoading] = useState(true);
  const [tvLoading, setTvLoading] = useState(true);

  // 错误状态
  const [heroError, setHeroError] = useState<string | null>(null);
  const [movieError, setMovieError] = useState<string | null>(null);
  const [tvError, setTvError] = useState<string | null>(null);

  const handleCardClick = useCallback((card: MovieCardData) => {
    const params = new URLSearchParams({ q: card.title });
    if (card.doubanId) params.set("douban_id", card.doubanId);
    navigate(`/search?${params.toString()}`);
  }, [navigate]);

  const cardProps = {
    themeFrom: theme.from,
    themeTo: theme.to,
    themeGlow: theme.glow,
    themeSubtle: theme.subtle,
  };

  /** 加载单个板块数据 */
  const fetchSection = useCallback(async (
    params: { type?: 'movie' | 'tv'; tag: string; page_limit?: number },
    section: 'hero' | 'movie' | 'tv',
  ) => {
    const setLoading = section === 'hero' ? setHeroLoading : section === 'movie' ? setMovieLoading : setTvLoading;
    const setError = section === 'hero' ? setHeroError : section === 'movie' ? setMovieError : setTvError;
    const transformer = section === 'hero' ? subjectToHeroItem : subjectToMovieCard;

    setLoading(true);
    setError(null);``

    try {
      // 获取图片代理 token（带缓存，未过期不重复请求）
      const token = await getTempToken();

      // 获取影视列表
      const resp = await getSubjects({
        type: params.type,
        tag: params.tag,
        page_limit: params.page_limit ?? 8,
        page_start: 0,
      });

      // 转换数据格式
      const items = (resp.subjects ?? []).map(s => transformer(s, token));
      if (section === 'hero') {
        setHeroItems(items as HeroItemData[]);
      } else if (section === 'movie') {
        setMovieCards(items as MovieCardData[]);
      } else {
        setTvCards(items as MovieCardData[]);
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : '加载失败';
      setError(msg);
    } finally {
      setLoading(false);
    }
  }, []);

  /** 加载所有板块数据（仅初始加载） */
  const fetchAllSections = useCallback(async () => {
    if (!isAuthenticated) {
      setHeroLoading(false);
      setMovieLoading(false);
      setTvLoading(false);
      return;
    }

    await Promise.allSettled([
      fetchSection({ type: 'movie', tag: '最新', page_limit: 5 }, 'hero'),
      fetchSection({ type: 'movie', tag: '热门', page_limit: 6 }, 'movie'),
      fetchSection({ type: 'tv', tag: '热门', page_limit: 6 }, 'tv'),
    ]);
  }, [isAuthenticated, fetchSection]);

  useEffect(() => {
    fetchAllSections();
  }, [fetchAllSections]);

  /** 标签切换时刷新热门推荐 */
  const handleTagChange = useCallback((tag: string) => {
    setActiveTag(tag);
  }, []);

  /** activeTag 变化时重新加载热门推荐（跳过初始加载，避免与 fetchAllSections 重复） */
  useEffect(() => {
    if (!isAuthenticated) return;
    if (!initialLoadDone.current) {
      initialLoadDone.current = true;
      return;
    }
    fetchSection({ type: 'movie', tag: activeTag, page_limit: 6 }, 'movie');
  }, [activeTag, isAuthenticated, fetchSection]);

  return (
    <>
      {/* Hero 轮播 */}
      {heroLoading ? (
        <HeroSkeleton />
      ) : heroError ? (
        <div className="w-full h-[520px] md:h-[600px] flex items-center justify-center text-sm" style={{ color: 'var(--text-secondary)' }}>
          {heroError}
        </div>
      ) : heroItems.length > 0 ? (
        <HeroSection
          items={heroItems}
          themeFrom={theme.from}
          themeTo={theme.to}
          themeMid={theme.mid}
          themeGlow={theme.glow}
          onPlay={(item) => {
            const params = new URLSearchParams({ q: item.title });
            if (item.doubanId) params.set("douban_id", item.doubanId);
            navigate(`/search?${params.toString()}`);
          }}
        />
      ) : null}

      {/*<StatsBar themeFrom={theme.from} themeGlow={theme.glow} />*/}

      <div className="px-10 md:px-16 pb-16 space-y-14">

        {/* 继续观看 */}
        <ContinueWatchingSection />

        {/* Genre filter */}
        <div>
          <GenrePills themeFrom={theme.from} themeTo={theme.to} themeGlow={theme.glow} themeSubtle={theme.subtle} activeTag={activeTag} onTagChange={handleTagChange} />
        </div>
        {/* 热门推荐 */}
        <section>
          <SectionHeader icon={TrendingUp} title="热门推荐" themeFrom={theme.from} themeTo={theme.to} themeGlow={theme.glow} />
          {movieLoading ? (
            <CardGridSkeleton count={6} />
          ) : movieError ? (
            <p className="text-sm" style={{ color: 'var(--text-secondary)' }}>{movieError}</p>
          ) : (
            <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-4">
              {movieCards.map(m => (
                <MovieCard key={m.title} {...m} {...cardProps} onClick={() => handleCardClick(m)} />
              ))}
            </div>
          )}
        </section>

        {/* 热播剧集 */}
        <section>
          <SectionHeader icon={Flame} title="热播剧集" themeFrom={theme.from} themeTo={theme.to} themeGlow={theme.glow} />
          {tvLoading ? (
            <CardGridSkeleton count={6} />
          ) : tvError ? (
            <p className="text-sm" style={{ color: 'var(--text-secondary)' }}>{tvError}</p>
          ) : (
            <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-4">
              {tvCards.map(m => (
                <MovieCard key={m.title} {...m} {...cardProps} onClick={() => handleCardClick(m)} />
              ))}
            </div>
          )}
        </section>

        {/* Bottom frosted promo banner */}
        <section>
          <div
            className="rounded-3xl p-8 md:p-12 flex flex-col md:flex-row items-center gap-8 overflow-hidden relative"
            style={{
              background: "var(--bg-surface-strong)",
              backdropFilter: "blur(24px)",
              WebkitBackdropFilter: "blur(24px)",
              border: "1px solid var(--border-strong)",
              boxShadow: `0 8px 48px rgba(0,0,0,0.5), inset 0 1px 0 var(--border-default)`,
            }}
          >
            {/* Glow orb */}
            <div
              className="absolute -right-20 -top-20 w-80 h-80 rounded-full blur-3xl pointer-events-none"
              style={{ background: `radial-gradient(circle, ${theme.glow} 0%, transparent 70%)` }}
            />
            <div className="relative z-10 flex-1">
              {/*<p className="text-xs mb-2 tracking-widest" style={{ color: theme.from, fontFamily: "var(--font-display)", fontWeight: 700 }}>高级会员</p>*/}
              {/*<h2 className="mb-3" style={{ fontFamily: "var(--font-display)", fontWeight: 800, fontSize: "clamp(1.5rem, 3vw, 2.25rem)" }}>*/}
              {/*  <GradientText from="#ffffff" to={theme.from}>解锁完整影视宇宙</GradientText>*/}
              {/*</h2>*/}
              {/*<p className="text-sm" style={{ color: "var(--text-muted)", maxWidth: 480 }}>*/}
              {/*  畅享 12,400+ 电影，4K HDR 流媒体播放，离线下载及 IMAX 增强内容。无广告打扰。*/}
              {/*</p>*/}
            </div>
            <div className="relative z-10 shrink-0">
              {/*<button*/}
              {/*  className="px-8 py-3.5 rounded-2xl text-sm transition-all duration-200 hover:scale-105 active:scale-95"*/}
              {/*  style={{*/}
              {/*    background: `linear-gradient(135deg,${theme.from},${theme.to})`,*/}
              {/*    color: "#fff",*/}
              {/*    fontFamily: "var(--font-display)",*/}
              {/*    fontWeight: 700,*/}
              {/*    boxShadow: `0 0 32px ${theme.glow}, 0 4px 16px rgba(0,0,0,0.4)`,*/}
              {/*    letterSpacing: "0.04em",*/}
              {/*  }}*/}
              {/*>*/}
              {/*  免费试用*/}
              {/*</button>*/}
            </div>
          </div>
        </section>
      </div>
    </>
  );
}
