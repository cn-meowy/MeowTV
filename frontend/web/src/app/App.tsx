import { RouterProvider } from 'react-router';
import { useEffect } from 'react';
import { router } from '@/router';
import { useAuthStore } from '@/stores/auth';

/**
 * 应用根组件 — 渲染路由 + 启动时恢复认证状态
 */
export default function App() {
  const initializeAuth = useAuthStore((s) => s.initializeAuth);

  useEffect(() => {
    initializeAuth();
  }, [initializeAuth]);

  return <RouterProvider router={router} />;
}
