import { Navigate } from 'react-router';
import { useAuthStore } from '@/stores/auth';

/**
 * 认证守卫：未登录则重定向到 /login
 * 初始化期间显示 loading，避免刷新页面时误跳登录页
 */
export function AuthGuard({ children }: { children: React.ReactNode }) {
  const isAuthenticated = useAuthStore((s) => s.isAuthenticated);
  const isInitializing = useAuthStore((s) => s.isInitializing);

  if (isInitializing) {
    return <div className="flex h-screen items-center justify-center">加载中...</div>;
  }
  if (!isAuthenticated) {
    return <Navigate to="/login" replace />;
  }
  return <>{children}</>;
}

/**
 * 管理员守卫：非管理员重定向到首页
 */
export function AdminGuard({ children }: { children: React.ReactNode }) {
  const user = useAuthStore((s) => s.user);
  if (!user || user.role !== 1) {
    return <Navigate to="/" replace />;
  }
  return <>{children}</>;
}

/**
 * 访客守卫：已登录则重定向到首页（用于 login 页）
 * 初始化期间显示 loading，避免刷新页面时闪烁
 */
export function GuestGuard({ children }: { children: React.ReactNode }) {
  const isAuthenticated = useAuthStore((s) => s.isAuthenticated);
  const isInitializing = useAuthStore((s) => s.isInitializing);

  if (isInitializing) {
    return <div className="flex h-screen items-center justify-center">加载中...</div>;
  }
  if (isAuthenticated) {
    return <Navigate to="/" replace />;
  }
  return <>{children}</>;
}
