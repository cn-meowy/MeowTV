import { useState, useRef, useEffect } from "react";
import {
  Home, Film, Database, Search, Code2,
  Palette, User, Settings, LogOut, ChevronRight, X,
  Moon, Sun, Download, Bookmark
} from "lucide-react";
import { GradientText } from "./GradientText";
import { DownloadDropdown } from "./DownloadDropdown";
import { LogoImage } from "./LogoImage";
import { useAuthStore } from "@/stores/auth";
import { useThemeStore } from "@/stores/theme";
import { useNavigate } from "react-router";

export type ThemeKey = "violet" | "sapphire" | "emerald" | "crimson" | "amber";

export const THEMES: Record<ThemeKey, { label: string; from: string; to: string; mid: string; glow: string; subtle: string; swatch: string }> = {
  violet:   { label: "紫罗兰",  from: "#7c4dff", to: "#b57bff", mid: "#9c6dff", glow: "rgba(124,77,255,0.30)", subtle: "rgba(124,77,255,0.08)", swatch: "linear-gradient(135deg,#7c4dff,#b57bff)" },
  sapphire: { label: "蓝宝石",  from: "#2563eb", to: "#60a5fa", mid: "#3b82f6", glow: "rgba(37,99,235,0.30)",  subtle: "rgba(37,99,235,0.08)",  swatch: "linear-gradient(135deg,#2563eb,#60a5fa)" },
  emerald:  { label: "翡翠绿",  from: "#059669", to: "#34d399", mid: "#10b981", glow: "rgba(5,150,105,0.30)",  subtle: "rgba(5,150,105,0.08)",  swatch: "linear-gradient(135deg,#059669,#34d399)" },
  crimson:  { label: "绯红",    from: "#dc2626", to: "#fb7185", mid: "#ef4444", glow: "rgba(220,38,38,0.30)",  subtle: "rgba(220,38,38,0.08)",  swatch: "linear-gradient(135deg,#dc2626,#fb7185)" },
  amber:    { label: "琥珀",    from: "#d97706", to: "#fbbf24", mid: "#f59e0b", glow: "rgba(217,119,6,0.30)",  subtle: "rgba(217,119,6,0.08)",  swatch: "linear-gradient(135deg,#d97706,#fbbf24)" },
};

interface NavbarProps {
  activeTheme: ThemeKey;
  onThemeChange: (t: ThemeKey) => void;
  activePage: string;
  onPageChange: (p: string) => void;
}

const NAV_ITEMS = [
  { id: "home",     label: "首页",  icon: Home },
  { id: "resource", label: "资源",  icon: Database },
  { id: "favorites", label: "收藏", icon: Bookmark },
  { id: "search",   label: "搜索",  icon: Search },
];

export function Navbar({ activeTheme, onThemeChange, activePage, onPageChange }: NavbarProps) {
  const theme = THEMES[activeTheme];
  const mode = useThemeStore((s) => s.mode);
  const toggleMode = useThemeStore((s) => s.toggleMode);
  const user = useAuthStore((s) => s.user);
  const logout = useAuthStore((s) => s.logout);
  const navigate = useNavigate();
  const [searchOpen, setSearchOpen] = useState(false);
  const [searchVal, setSearchVal] = useState("");
  const [paletteOpen, setPaletteOpen] = useState(false);
  const [userOpen, setUserOpen] = useState(false);
  const [downloadOpen, setDownloadOpen] = useState(false);
  const searchRef = useRef<HTMLInputElement>(null);
  const paletteRef = useRef<HTMLDivElement>(null);
  const userMenuRef = useRef<HTMLDivElement>(null);
  const downloadRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (searchOpen) searchRef.current?.focus();
  }, [searchOpen]);

  // 点击外部关闭面板
  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (paletteOpen && paletteRef.current && !paletteRef.current.contains(e.target as Node)) {
        setPaletteOpen(false);
      }
      if (userOpen && userMenuRef.current && !userMenuRef.current.contains(e.target as Node)) {
        setUserOpen(false);
      }
      if (downloadOpen && downloadRef.current && !downloadRef.current.contains(e.target as Node)) {
        setDownloadOpen(false);
      }
    };
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, [paletteOpen, userOpen, downloadOpen]);

  const closeAll = () => { setPaletteOpen(false); setUserOpen(false); setDownloadOpen(false); };

  const displayName = user?.nickname || user?.username || "用户";
  const roleLabel = user?.role === 1 ? "管理员" : "普通用户";

  return (
    <header
      className="fixed top-0 left-0 right-0 z-50 h-16"
      style={{
        background: "var(--bg-surface-strong)",
        backdropFilter: "blur(20px) saturate(1.6)",
        WebkitBackdropFilter: "blur(20px) saturate(1.6)",
        borderBottom: "1px solid var(--border-strong)",
        boxShadow: "var(--shadow-elevated)",
      }}
    >
      <div className="h-full flex items-center px-4 gap-2 relative">

        {/* LEFT — palette + user */}
        <div className="flex items-center gap-1 shrink-0">
          {/* Palette button */}
          <div className="relative" ref={paletteRef}>
            <button
              onClick={() => { setPaletteOpen(p => !p); setUserOpen(false); }}
              className="w-9 h-9 rounded-xl flex items-center justify-center transition-all duration-200 group"
              style={{
                background: paletteOpen ? theme.subtle : "transparent",
                boxShadow: paletteOpen ? `0 0 12px ${theme.glow}` : "none",
              }}
              title="颜色主题"
            >
              <Palette
                size={18}
                style={{ color: paletteOpen ? theme.from : "var(--text-secondary)", transition: "color 0.2s" }}
              />
            </button>

            {paletteOpen && (
              <div
                className="absolute top-12 left-0 rounded-2xl p-3 min-w-[200px]"
                style={{
                  background: "var(--bg-surface-strong)",
                  backdropFilter: "blur(24px)",
                  WebkitBackdropFilter: "blur(24px)",
                  border: "1px solid var(--border-strong)",
                  boxShadow: "var(--shadow-dropdown)",
                }}
              >
                {/* Mode toggle */}
                <p className="text-xs mb-2 px-1" style={{ color: "var(--text-secondary)", fontFamily: "var(--font-display)", letterSpacing: "0.08em" }}>外观模式</p>
                <div className="flex items-center gap-1 mb-3">
                  <button
                    onClick={() => { if (mode !== 'dark') toggleMode(); }}
                    className="flex items-center gap-2 px-3 py-2 rounded-xl text-sm transition-all duration-150 flex-1"
                    style={{
                      background: mode === 'dark' ? theme.subtle : "var(--bg-elevated)",
                      color: mode === 'dark' ? theme.from : "var(--text-secondary)",
                      border: mode === 'dark' ? `1px solid ${theme.glow}` : "1px solid var(--border-default)",
                      fontFamily: "var(--font-display)",
                    }}
                  >
                    <Moon size={14} />
                    <span>暗黑</span>
                  </button>
                  <button
                    onClick={() => { if (mode !== 'light') toggleMode(); }}
                    className="flex items-center gap-2 px-3 py-2 rounded-xl text-sm transition-all duration-150 flex-1"
                    style={{
                      background: mode === 'light' ? theme.subtle : "var(--bg-elevated)",
                      color: mode === 'light' ? theme.from : "var(--text-secondary)",
                      border: mode === 'light' ? `1px solid ${theme.glow}` : "1px solid var(--border-default)",
                      fontFamily: "var(--font-display)",
                    }}
                  >
                    <Sun size={14} />
                    <span>明亮</span>
                  </button>
                </div>

                <p className="text-xs mb-2 px-1" style={{ color: "var(--text-secondary)", fontFamily: "var(--font-display)", letterSpacing: "0.08em" }}>颜色主题</p>
                <div className="flex flex-col gap-1">
                  {(Object.keys(THEMES) as ThemeKey[]).map(key => (
                    <button
                      key={key}
                      onClick={() => { onThemeChange(key); setPaletteOpen(false); }}
                      className="flex items-center gap-3 px-2 py-2 rounded-xl transition-all duration-150 group/item"
                      style={{
                        background: activeTheme === key ? `${THEMES[key].subtle}` : "transparent",
                      }}
                    >
                      <span
                        className="w-5 h-5 rounded-full shrink-0"
                        style={{ background: THEMES[key].swatch, boxShadow: activeTheme === key ? `0 0 8px ${THEMES[key].glow}` : "none" }}
                      />
                      <span className="text-sm" style={{ color: activeTheme === key ? THEMES[key].from : "var(--text-secondary)" }}>
                        {THEMES[key].label}
                      </span>
                      {activeTheme === key && <ChevronRight size={12} style={{ color: THEMES[key].from, marginLeft: "auto" }} />}
                    </button>
                  ))}
                </div>
              </div>
            )}
          </div>

          {/* User button */}
          <div className="relative" ref={userMenuRef}>
            <button
              onClick={() => { setUserOpen(u => !u); setPaletteOpen(false); }}
              className="w-9 h-9 rounded-xl flex items-center justify-center transition-all duration-200"
              style={{
                background: userOpen ? theme.subtle : "transparent",
                boxShadow: userOpen ? `0 0 12px ${theme.glow}` : "none",
              }}
              title="用户菜单"
            >
              <div
                className="w-7 h-7 rounded-lg flex items-center justify-center"
                style={{ background: userOpen ? `linear-gradient(135deg,${theme.from},${theme.to})` : "var(--bg-active)" }}
              >
                <User size={14} style={{ color: userOpen ? "#fff" : "var(--text-secondary)" }} />
              </div>
            </button>

            {userOpen && (
              <div
                className="absolute top-12 left-0 rounded-2xl overflow-hidden min-w-[220px]"
                style={{
                  background: "var(--bg-surface-strong)",
                  backdropFilter: "blur(24px)",
                  WebkitBackdropFilter: "blur(24px)",
                  border: "1px solid var(--border-strong)",
                  boxShadow: "var(--shadow-dropdown)",
                }}
              >
                {/* User header */}
                <div className="px-4 py-3" style={{ borderBottom: "1px solid var(--border-default)" }}>
                  <div className="flex items-center gap-3">
                    <div
                      className="w-9 h-9 rounded-xl flex items-center justify-center shrink-0"
                      style={{ background: `linear-gradient(135deg,${theme.from},${theme.to})` }}
                    >
                      <User size={16} color="#fff" />
                    </div>
                    <div>
                      <p className="text-sm" style={{ color: "var(--text-primary)", fontWeight: 600 }}>{displayName}</p>
                      <p className="text-xs" style={{ color: "var(--text-secondary)" }}>{roleLabel}</p>
                    </div>
                  </div>
                </div>
                {/* Menu items */}
                {[
                  { icon: User,     label: "个人信息", page: "profile" },
                  ...(user?.role === 1 ? [{ icon: Settings, label: "系统设置", page: "settings" as string }] : []),
                ].map(({ icon: Icon, label, page }) => (
                  <button
                    key={page}
                    onClick={() => { onPageChange(page); closeAll(); }}
                    className="w-full flex items-center gap-3 px-4 py-3 transition-colors duration-150"
                    style={{ color: "var(--text-secondary)" }}
                    onMouseEnter={e => (e.currentTarget.style.background = theme.subtle)}
                    onMouseLeave={e => (e.currentTarget.style.background = "transparent")}
                  >
                    <Icon size={15} />
                    <span className="text-sm">{label}</span>
                  </button>
                ))}
                <div style={{ borderTop: "1px solid var(--border-default)" }}>
                  <button
                    onClick={async () => { closeAll(); await logout(); }}
                    className="w-full flex items-center gap-3 px-4 py-3 transition-colors duration-150"
                    style={{ color: "#fb7185" }}
                    onMouseEnter={e => (e.currentTarget.style.background = "rgba(220,38,38,0.08)")}
                    onMouseLeave={e => (e.currentTarget.style.background = "transparent")}
                  >
                    <LogOut size={15} />
                    <span className="text-sm">退出登录</span>
                  </button>
                </div>
              </div>
            )}
          </div>
        </div>

        {/* LOGO */}
        <div
          className="flex items-center gap-2 ml-2 mr-4 shrink-0 cursor-pointer"
          onClick={() => { onPageChange("home"); closeAll(); }}
        >
          <div
            className="w-8 h-8 rounded-xl flex items-center justify-center overflow-hidden"
            style={{ background: `linear-gradient(135deg,${theme.from},${theme.to})`, boxShadow: `0 0 16px ${theme.glow}` }}
          >
            <LogoImage className="w-full h-full" style={{ objectFit: "contain" }} />
          </div>
          <GradientText
            from={theme.from}
            to={theme.to}
            className="text-base tracking-wide"
            extraStyle={{ fontFamily: "var(--font-display)", fontWeight: 700 }}
          >
            MeowTV
          </GradientText>
        </div>

        {/* CENTER — nav items */}
        <nav className="flex items-center gap-1 flex-1 justify-center">
          {NAV_ITEMS.map(({ id, label, icon: Icon }) => {
            const active = activePage === id;
            return (
              <button
                key={id}
                onClick={() => { onPageChange(id); closeAll(); }}
                className="flex items-center gap-2 px-3 py-2 rounded-xl text-sm transition-all duration-200 whitespace-nowrap"
                style={{
                  background: active ? theme.subtle : "transparent",
                  color: active ? theme.from : "var(--text-secondary)",
                  fontFamily: "var(--font-display)",
                  boxShadow: active ? `0 0 12px ${theme.glow}` : "none",
                  border: active ? `1px solid ${theme.glow}` : "1px solid transparent",
                }}
                onMouseEnter={e => { if (!active) { e.currentTarget.style.color = "var(--text-primary)"; e.currentTarget.style.background = "var(--bg-elevated)"; }}}
                onMouseLeave={e => { if (!active) { e.currentTarget.style.color = "var(--text-secondary)"; e.currentTarget.style.background = "transparent"; }}}
              >
                <Icon size={15} />
                <span className="hidden sm:inline">{label}</span>
              </button>
            );
          })}
        </nav>

        {/* RIGHT — download + search */}
        <div className="flex items-center gap-2 shrink-0">
          {/* Download button */}
          <div className="relative" ref={downloadRef}>
            <button
              onClick={() => { setDownloadOpen(d => !d); closeAll(); setDownloadOpen(true); }}
              className="w-9 h-9 rounded-xl flex items-center justify-center transition-all duration-200"
              style={{
                background: downloadOpen ? theme.subtle : "transparent",
                boxShadow: downloadOpen ? `0 0 12px ${theme.glow}` : "none",
              }}
              title="下载管理"
            >
              <Download
                size={18}
                style={{ color: downloadOpen ? theme.from : "var(--text-secondary)", transition: "color 0.2s" }}
              />
            </button>
            <DownloadDropdown open={downloadOpen} onClose={() => setDownloadOpen(false)} />
          </div>
          {searchOpen ? (
            <div
              className="flex items-center gap-2 rounded-2xl px-3 py-2 transition-all duration-300"
              style={{
                background: "var(--bg-hover)",
                border: `1px solid ${theme.glow}`,
                boxShadow: `0 0 20px ${theme.glow}`,
                minWidth: "280px",
              }}
            >
              <Search size={15} style={{ color: theme.from, flexShrink: 0 }} />
              <input
                ref={searchRef}
                value={searchVal}
                onChange={e => setSearchVal(e.target.value)}
                placeholder="搜索电影、剧集、动漫..."
                className="flex-1 bg-transparent outline-none text-sm"
                style={{ color: "var(--text-primary)" }}
                onBlur={() => {
                  setTimeout(() => setSearchOpen(false), 150);
                }}
                onKeyDown={e => {
                  if (e.key === "Escape") {
                    setSearchOpen(false);
                  } else if (e.key === "Enter" && searchVal.trim()) {
                    navigate(`/search?q=${encodeURIComponent(searchVal.trim())}`);
                    setSearchOpen(false);
                    setSearchVal("");
                  }
                }}
              />
              <button onClick={() => { setSearchOpen(false); setSearchVal(""); }}>
                <X size={14} style={{ color: "var(--text-secondary)" }} />
              </button>
            </div>
          ) : (
            <button
              onClick={() => { setSearchOpen(true); closeAll(); }}
              className="flex items-center gap-2 px-3 py-2 rounded-2xl text-sm transition-all duration-200"
              style={{
                background: "var(--bg-elevated)",
                border: "1px solid var(--border-default)",
                color: "var(--text-secondary)",
              }}
              onMouseEnter={e => {
                e.currentTarget.style.background = theme.subtle;
                e.currentTarget.style.borderColor = theme.glow;
                e.currentTarget.style.color = theme.from;
              }}
              onMouseLeave={e => {
                e.currentTarget.style.background = "var(--bg-elevated)";
                e.currentTarget.style.borderColor = "var(--border-default)";
                e.currentTarget.style.color = "var(--text-secondary)";
              }}
            >
              <Search size={15} />
              <span className="hidden md:inline" style={{ fontFamily: "var(--font-display)" }}>搜索</span>
            </button>
          )}
        </div>

      </div>

      {/* Dismiss overlay for dropdowns */}
      {(paletteOpen || userOpen || downloadOpen) && (
        <div className="fixed inset-0 z-[-1]" onClick={closeAll} />
      )}
    </header>
  );
}
