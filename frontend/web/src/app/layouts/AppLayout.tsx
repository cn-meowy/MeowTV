import { Outlet } from 'react-router';
import { Navbar, THEMES, type ThemeKey } from '@/app/components/Navbar';
import { useThemeStore } from '@/stores/theme';
import { useFavoritesStore } from '@/stores/favorites';
import { usePlayHistoryStore } from '@/stores/play-history';
import { useEffect } from 'react';
import { useLocation, useNavigate } from 'react-router';

/**
 * 应用主布局：包含顶部导航栏 + 主题系统 + 页面内容出口
 */
export default function AppLayout() {
  const activeTheme = useThemeStore((s) => s.activeTheme);
  const setActiveTheme = useThemeStore((s) => s.setActiveTheme);
  const mode = useThemeStore((s) => s.mode);
  const theme = THEMES[activeTheme];
  const location = useLocation();
  const navigate = useNavigate();

  // 将当前路径映射为 activePage（供 Navbar 高亮）
  const activePage = location.pathname === '/' ? 'home'
    : location.pathname.startsWith('/resource') ? 'resource'
    : location.pathname.startsWith('/favorites') ? 'favorites'
    : location.pathname.startsWith('/search') ? 'search'
    : location.pathname.startsWith('/detail') ? 'search'
    : location.pathname.startsWith('/play') ? 'search'
    : location.pathname.startsWith('/downloads') ? 'downloads'
    : location.pathname.startsWith('/history') ? 'history'
    : location.pathname.startsWith('/profile') ? 'profile'
    : location.pathname.startsWith('/settings') ? 'settings'
    : 'home';

  // 页面导航处理
  const handlePageChange = (page: string) => {
    const routeMap: Record<string, string> = {
      home: '/',
      resource: '/resource',
      favorites: '/favorites',
      search: '/search',
      downloads: '/downloads',
      history: '/history',
      profile: '/profile',
      settings: '/settings',
    };
    navigate(routeMap[page] || '/');
  };

  // 应用 CSS 变量
  useEffect(() => {
    const root = document.documentElement;
    root.style.setProperty('--theme-from', theme.from);
    root.style.setProperty('--theme-to', theme.to);
    root.style.setProperty('--theme-mid', theme.mid);
    root.style.setProperty('--theme-glow', theme.glow);
    root.style.setProperty('--theme-subtle', theme.subtle);
    root.style.setProperty('--primary', theme.from);
    root.style.setProperty('--ring', theme.glow);
    root.style.setProperty('--accent', theme.subtle);
    root.style.setProperty('--accent-foreground', theme.to);
  }, [activeTheme, theme]);

  // 应用暗黑/明亮模式
  useEffect(() => {
    const root = document.documentElement;
    root.classList.remove('dark', 'light');
    root.classList.add(mode);
  }, [mode]);

  // 应用级初始化：预加载收藏和播放历史数据
  const fetchFavorites = useFavoritesStore((s) => s.fetchFromServer);
  const fetchPlayHistory = usePlayHistoryStore((s) => s.fetchFromServer);
  useEffect(() => {
    fetchFavorites();
    fetchPlayHistory();
  }, [fetchFavorites, fetchPlayHistory]);

  return (
    <div
      className="min-h-screen"
      style={{
        background: `radial-gradient(ellipse at 20% 0%, ${theme.glow} 0%, transparent 40%), radial-gradient(ellipse at 80% 100%, ${theme.subtle} 0%, transparent 40%), var(--bg-base)`,
        fontFamily: 'var(--font-body)',
      }}
    >
      <Navbar
        activeTheme={activeTheme}
        onThemeChange={setActiveTheme}
        activePage={activePage}
        onPageChange={handlePageChange}
      />
      <main className="pt-16">
        <Outlet />
      </main>
    </div>
  );
}
