import { createBrowserRouter } from 'react-router';
import { lazy, Suspense } from 'react';
import { AuthGuard, AdminGuard, GuestGuard } from './guards';
import AppLayout from '@/app/layouts/AppLayout';

// 路由级懒加载：每个页面独立 chunk，首屏只加载当前路由所需代码
const HomePage = lazy(() => import('@/app/pages/HomePage'));
const LoginPage = lazy(() => import('@/app/pages/LoginPage'));
const ProfilePage = lazy(() => import('@/app/pages/ProfilePage'));
const SettingsPage = lazy(() => import('@/app/pages/SettingsPage'));
const SearchPage = lazy(() => import('@/app/pages/SearchPage'));
const ResourcePage = lazy(() => import('@/app/pages/ResourcePage'));
const DetailPage = lazy(() => import('@/app/pages/DetailPage'));
const PlayPage = lazy(() => import('@/app/pages/PlayPage'));
const HistoryPage = lazy(() => import('@/app/pages/HistoryPage'));
const FavoritePage = lazy(() => import('@/app/pages/FavoritePage'));
const DownloadPage = lazy(() => import('@/app/pages/DownloadPage'));
const NotFoundPage = lazy(() => import('@/app/pages/NotFoundPage'));

/** 页面级 Suspense 加载占位 */
function PageLoading() {
  return (
    <div className="flex items-center justify-center min-h-[60vh]">
      <div className="flex flex-col items-center gap-3">
        <div
          className="w-8 h-8 rounded-full border-2 border-t-transparent animate-spin"
          style={{ borderColor: 'var(--theme-from)', borderTopColor: 'transparent' }}
        />
        <span className="text-sm" style={{ color: 'var(--text-secondary)' }}>加载中...</span>
      </div>
    </div>
  );
}

/** 包裹懒加载页面的 Suspense 容器 */
function LazyPage({ children }: { children: React.ReactNode }) {
  return <Suspense fallback={<PageLoading />}>{children}</Suspense>;
}

export const router = createBrowserRouter([
  // 访客路由（未登录才可访问）
  {
    path: '/login',
    element: (
      <GuestGuard>
        <LazyPage><LoginPage /></LazyPage>
      </GuestGuard>
    ),
  },

  // 认证路由（需要登录）
  {
    path: '/',
    element: (
      <AuthGuard>
        <AppLayout />
      </AuthGuard>
    ),
    children: [
      { index: true, element: <LazyPage><HomePage /></LazyPage> },
      { path: 'profile', element: <LazyPage><ProfilePage /></LazyPage> },
      { path: 'search', element: <LazyPage><SearchPage /></LazyPage> },
      { path: 'resource', element: <LazyPage><ResourcePage /></LazyPage> },
      { path: 'detail', element: <LazyPage><DetailPage /></LazyPage> },
      { path: 'play', element: <LazyPage><PlayPage /></LazyPage> },
      { path: 'history', element: <LazyPage><HistoryPage /></LazyPage> },
      { path: 'favorites', element: <LazyPage><FavoritePage /></LazyPage> },
      { path: 'downloads', element: <LazyPage><DownloadPage /></LazyPage> },
      {
        path: 'settings',
        element: (
          <AdminGuard>
            <LazyPage><SettingsPage /></LazyPage>
          </AdminGuard>
        ),
      },
    ],
  },

  // 404 兜底
  {
    path: '*',
    element: <LazyPage><NotFoundPage /></LazyPage>,
  },
]);
