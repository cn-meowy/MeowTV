import { useState, lazy, Suspense } from "react";
import { Link, FolderOpen, Users, HardDrive, Globe, Zap } from "lucide-react";
import { GradientText } from "@/app/components/GradientText";
import { THEMES } from "@/app/components/Navbar";
import { useThemeStore } from "@/stores/theme";

// ── Tab 组件懒加载 ────────────────────────────────────────────────────
const SubscribeTab = lazy(() => import("./settings/SubscribeTab").then(m => ({ default: m.SubscribeTab })));
const ResourceGroupTab = lazy(() => import("./settings/ResourceGroupTab").then(m => ({ default: m.ResourceGroupTab })));
const UserTab = lazy(() => import("./settings/UserTab").then(m => ({ default: m.UserTab })));
const DownloadConfigTab = lazy(() => import("./settings/DownloadConfigTab").then(m => ({ default: m.DownloadConfigTab })));
const DoubanConfigTab = lazy(() => import("./settings/DoubanConfigTab").then(m => ({ default: m.DoubanConfigTab })));
const StreamConfigTab = lazy(() => import("./settings/StreamConfigTab").then(m => ({ default: m.StreamConfigTab })));

// ── Tab 定义 ──────────────────────────────────────────────────────────
type TabKey = "subscribe" | "resource-group" | "user" | "download" | "douban" | "stream";

const TABS: { key: TabKey; label: string; icon: React.ElementType }[] = [
  { key: "subscribe",      label: "订阅管理",   icon: Link },
  { key: "resource-group", label: "资源组管理", icon: FolderOpen },
  { key: "user",           label: "用户管理",   icon: Users },
  { key: "download",       label: "下载配置",   icon: HardDrive },
  { key: "douban",         label: "豆瓣配置",   icon: Globe },
  { key: "stream",         label: "流代理配置",  icon: Zap },
];

// ── Tab 加载占位 ──────────────────────────────────────────────────────
function TabLoading() {
  return (
    <div className="rounded-2xl p-8 text-center text-sm" style={{
      background: "var(--bg-surface-strong)",
      backdropFilter: "blur(20px)",
      border: "1px solid var(--border-strong)",
    }}>
      <span style={{ color: "var(--text-secondary)" }}>加载中…</span>
    </div>
  );
}

// ── 主组件 ────────────────────────────────────────────────────────────
/**
 * 系统设置页面（仅管理员） — 订阅管理、资源组管理、用户管理
 */
export default function SettingsPage() {
  const activeTheme = useThemeStore((s) => s.activeTheme);
  const theme = THEMES[activeTheme];
  const [activeTab, setActiveTab] = useState<TabKey>("subscribe");

  return (
    <div className="px-10 md:px-16 py-10 max-w-5xl mx-auto">
      <h1 className="mb-8" style={{ fontFamily: "var(--font-display)", fontWeight: 800, fontSize: "1.75rem" }}>
        <GradientText from={theme.from} to={theme.to}>系统设置</GradientText>
      </h1>

      {/* Tab 栏 */}
      <div className="flex gap-2 mb-8">
        {TABS.map(({ key, label, icon: Icon }) => {
          const active = activeTab === key;
          return (
            <button
              key={key}
              onClick={() => setActiveTab(key)}
              className="flex items-center gap-2 px-4 py-2.5 rounded-xl text-sm transition-all duration-200"
              style={{
                background: active ? theme.subtle : "var(--bg-elevated)",
                color: active ? theme.from : "var(--text-secondary)",
                fontFamily: "var(--font-display)",
                fontWeight: active ? 600 : 400,
                border: `1px solid ${active ? theme.glow : "var(--border-strong)"}`,
                boxShadow: active ? `0 0 12px ${theme.glow}` : "none",
              }}
            >
              <Icon size={15} />
              {label}
            </button>
          );
        })}
      </div>

      {/* Tab 内容 — 懒加载 */}
      <Suspense fallback={<TabLoading />}>
        {activeTab === "subscribe" && <SubscribeTab theme={theme} />}
        {activeTab === "resource-group" && <ResourceGroupTab theme={theme} />}
        {activeTab === "user" && <UserTab theme={theme} />}
        {activeTab === "download" && <DownloadConfigTab theme={theme} />}
        {activeTab === "douban" && <DoubanConfigTab theme={theme} />}
        {activeTab === "stream" && <StreamConfigTab theme={theme} />}
      </Suspense>
    </div>
  );
}
