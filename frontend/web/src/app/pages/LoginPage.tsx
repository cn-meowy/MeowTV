import { useState, useEffect } from "react";
import { Lock, Eye, EyeOff, ArrowRight, QrCode, RefreshCw, CheckCircle2, Clock, AlertCircle } from "lucide-react";
import { GradientText } from "@/app/components/GradientText";
import { LogoImage } from "@/app/components/LogoImage";
import { THEMES } from "@/app/components/Navbar";
import { useThemeStore } from "@/stores/theme";
import { useAuthStore } from "@/stores/auth";
import type { QRCodeLoginState } from "@/stores/auth";
import { useNavigate } from "react-router";
import { ApiError } from "@/api/client";

type LoginMode = "password" | "qrcode";

/**
 * 登录页面 — 密码登录 + 扫码登录
 */
export default function LoginPage() {
  const activeTheme = useThemeStore((s) => s.activeTheme);
  const theme = THEMES[activeTheme];
  const login = useAuthStore((s) => s.login);
  const navigate = useNavigate();

  // 扫码登录相关状态
  const qrcodeState = useAuthStore((s) => s.qrcodeState);
  const qrcodeUrl = useAuthStore((s) => s.qrcodeUrl);
  const qrcodeCode = useAuthStore((s) => s.qrcodeCode);
  const qrcodeExpiresIn = useAuthStore((s) => s.qrcodeExpiresIn);
  const startQRCodeLogin = useAuthStore((s) => s.startQRCodeLogin);
  const stopQRCodeLogin = useAuthStore((s) => s.stopQRCodeLogin);
  const refreshQRCode = useAuthStore((s) => s.refreshQRCode);
  const isAuthenticated = useAuthStore((s) => s.isAuthenticated);

  const [mode, setMode] = useState<LoginMode>("password");
  const [showPassword, setShowPassword] = useState(false);
  const [password, setPassword] = useState("");
  const [username, setUsername] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  // 登录成功后跳转
  useEffect(() => {
    if (isAuthenticated) {
      navigate("/", { replace: true });
    }
  }, [isAuthenticated, navigate]);

  // 扫码登录：切换到扫码 Tab 时自动启动，离开时停止
  useEffect(() => {
    if (mode === "qrcode" && (qrcodeState === "idle" || qrcodeState === "error")) {
      startQRCodeLogin();
    }
    return () => {
      // 组件卸载时停止轮询
      stopQRCodeLogin();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [mode]);

  // 页面可见性变化时暂停/恢复轮询
  useEffect(() => {
    const handleVisibility = () => {
      if (document.hidden) {
        stopQRCodeLogin();
      } else if (mode === "qrcode" && (qrcodeState === "showing")) {
        // 页面恢复可见且正在展示二维码时，重新启动轮询
        startQRCodeLogin();
      }
    };
    document.addEventListener("visibilitychange", handleVisibility);
    return () => document.removeEventListener("visibilitychange", handleVisibility);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [mode, qrcodeState]);

  const handleModeSwitch = (m: LoginMode) => {
    if (m === mode) return;
    setError("");
    if (mode === "qrcode") {
      stopQRCodeLogin();
    }
    setMode(m);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");

    if (!username.trim() || !password.trim()) {
      setError("请输入用户名和密码");
      return;
    }

    setLoading(true);
    try {
      await login(username.trim(), password);
      navigate("/", { replace: true });
    } catch (err) {
      if (err instanceof ApiError) {
        setError(err.message || "登录失败，请检查用户名和密码");
      } else {
        setError("网络错误，请稍后重试");
      }
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex overflow-hidden relative" style={{ background: "var(--bg-base)" }}>

      {/* ── Left panel — cinematic visual ──────────────────────────────────── */}
      <div className="hidden lg:flex flex-1 relative overflow-hidden">
        <img
          src="https://images.unsplash.com/photo-1516583562173-e1c2721ee57b?w=1200&h=900&fit=crop&auto=format"
          alt="影视灯光"
          className="absolute inset-0 w-full h-full object-cover"
        />
        <div className="absolute inset-0" style={{ background: "linear-gradient(135deg, rgba(8,8,16,0.85) 0%, rgba(8,8,16,0.4) 100%)" }} />
        <div className="absolute inset-0" style={{ background: `radial-gradient(ellipse at 30% 60%, ${theme.glow} 0%, transparent 55%)` }} />
        <div className="absolute inset-y-0 right-0 w-32" style={{ background: "linear-gradient(to right, transparent, var(--bg-base))" }} />

        <div className="relative z-10 flex flex-col justify-between p-12 h-full">
          <div className="flex items-center gap-3">
            <div
              className="w-10 h-10 rounded-2xl flex items-center justify-center overflow-hidden"
              style={{ background: `linear-gradient(135deg, ${theme.from}, ${theme.to})`, boxShadow: `0 0 24px ${theme.glow}` }}
            >
              <LogoImage className="w-full h-full" style={{ objectFit: "contain" }} />
            </div>
            <GradientText from="#ffffff" to={theme.from} extraStyle={{ fontFamily: "var(--font-display)", fontWeight: 800, fontSize: "1.25rem", letterSpacing: "0.06em" }}>
              MeowTV
            </GradientText>
          </div>

          <div>
            <p className="text-xs mb-4 tracking-widest" style={{ color: theme.from, fontFamily: "var(--font-display)", fontWeight: 700 }}>
              你的影视宇宙等你开启
            </p>
            <h1
              className="mb-4 leading-tight"
              style={{ fontFamily: "var(--font-display)", fontWeight: 800, fontSize: "clamp(2rem, 3.5vw, 3rem)", color: "#ffffff" }}
            >
              每个故事<br />
              <GradientText from={theme.from} to={theme.to}>都值得被看见。</GradientText>
            </h1>
            <p className="text-sm leading-relaxed" style={{ color: "var(--text-muted)", maxWidth: 380 }}>
              畅享电影、剧集和动漫，4K HDR 高画质流媒体。你的影视之旅从这里开始。
            </p>

            <div className="flex items-center gap-6 mt-8">
              {[["12K+", "片源"], ["4K", "HDR"], ["150+", "国家"]].map(([val, label]) => (
                <div key={label}>
                  <p style={{ fontFamily: "var(--font-display)", fontWeight: 700, fontSize: "1.1rem" }}>
                    <GradientText from="#ffffff" to={theme.from}>{val}</GradientText>
                  </p>
                  <p className="text-xs" style={{ color: "var(--text-muted)", fontFamily: "var(--font-display)" }}>{label}</p>
                </div>
              ))}
            </div>

            <div className="flex items-center gap-3 mt-8">
              <div className="flex -space-x-2">
                {[
                  "https://images.unsplash.com/photo-1560665744-11d8334e0bc0?w=40&h=40&fit=crop",
                  "https://images.unsplash.com/photo-1462715412043-8d09205be605?w=40&h=40&fit=crop",
                  "https://images.unsplash.com/photo-1629278357549-b413116d211c?w=40&h=40&fit=crop",
                ].map((src, i) => (
                  <img
                    key={i}
                    src={src}
                    alt=""
                    className="w-8 h-8 rounded-full object-cover"
                    style={{ border: "2px solid var(--bg-base)", boxShadow: `0 0 0 1px ${theme.glow}` }}
                  />
                ))}
                <div
                  className="w-8 h-8 rounded-full flex items-center justify-center"
                  style={{ border: "2px solid var(--bg-base)", background: `linear-gradient(135deg,${theme.from},${theme.to})` }}
                >
                  <span className="text-xs text-white" style={{ fontFamily: "var(--font-display)", fontWeight: 700 }}>+</span>
                </div>
              </div>
              <p className="text-xs" style={{ color: "var(--text-muted)" }}>
                加入 <span style={{ color: theme.from, fontWeight: 600 }}>2.4M+</span> 全球影迷
              </p>
            </div>
          </div>
        </div>
      </div>

      {/* ── Right panel — auth form ─────────────────────────────────────────── */}
      <div
        className="w-full lg:w-[480px] flex flex-col justify-center px-8 md:px-12 py-12 relative shrink-0"
        style={{ background: "var(--bg-surface-strong)" }}
      >
        <div
          className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-96 h-96 rounded-full blur-3xl pointer-events-none"
          style={{ background: `radial-gradient(circle, ${theme.glow} 0%, transparent 70%)`, opacity: 0.4 }}
        />

        <div className="flex items-center gap-2 mb-10 lg:hidden">
          <div
            className="w-8 h-8 rounded-xl flex items-center justify-center overflow-hidden"
            style={{ background: `linear-gradient(135deg,${theme.from},${theme.to})`, boxShadow: `0 0 16px ${theme.glow}` }}
          >
            <LogoImage className="w-full h-full" style={{ objectFit: "contain" }} />
          </div>
          <GradientText from="#ffffff" to={theme.from} extraStyle={{ fontFamily: "var(--font-display)", fontWeight: 800, letterSpacing: "0.06em" }}>
            MeowTV
          </GradientText>
        </div>

        <div className="relative z-10 max-w-sm w-full mx-auto">

          {/* Mode toggle tabs */}
          <div
            className="flex rounded-2xl p-1 mb-8"
            style={{ background: "var(--bg-hover)", border: "1px solid var(--border-strong)" }}
          >
            {(["password", "qrcode"] as const).map(m => (
              <button
                key={m}
                onClick={() => handleModeSwitch(m)}
                className="flex-1 py-2.5 rounded-xl text-sm transition-all duration-200 flex items-center justify-center gap-2"
                style={{
                  background: mode === m ? `linear-gradient(135deg,${theme.from},${theme.to})` : "transparent",
                  color: mode === m ? "#fff" : "var(--text-secondary)",
                  fontFamily: "var(--font-display)",
                  fontWeight: mode === m ? 600 : 400,
                  boxShadow: mode === m ? `0 0 20px ${theme.glow}` : "none",
                }}
              >
                {m === "password" ? (
                  <><Lock size={14} />密码登录</>
                ) : (
                  <><QrCode size={14} />扫码登录</>
                )}
              </button>
            ))}
          </div>

          {/* Heading */}
          <div className="mb-8">
            <h2 style={{ fontFamily: "var(--font-display)", fontWeight: 800, fontSize: "1.75rem", color: "#ffffff" }}>
              {mode === "password" ? (
                <>欢迎<GradientText from={theme.from} to={theme.to}>回来</GradientText></>
              ) : (
                <>扫码<GradientText from={theme.from} to={theme.to}>登录</GradientText></>
              )}
            </h2>
            <p className="text-sm mt-1" style={{ color: "var(--text-secondary)" }}>
              {mode === "password"
                ? "登录以继续你的影视之旅"
                : "使用 MeowTV App 扫码快速登录"}
            </p>
          </div>

          {/* ── 密码登录表单 ─────────────────────────────────────────────────── */}
          {mode === "password" && (
            <form onSubmit={handleSubmit} className="flex flex-col gap-4">
              {/* Username */}
              <div className="flex flex-col gap-1.5">
                <label className="text-xs" style={{ color: "var(--text-secondary)", fontFamily: "var(--font-display)", fontWeight: 500, letterSpacing: "0.06em" }}>用户名</label>
                <div
                  className="flex items-center gap-3 px-4 py-3 rounded-xl transition-all duration-200"
                  style={{
                    background: "var(--bg-elevated)",
                    border: `1px solid ${username ? theme.glow : "var(--border-strong)"}`,
                    boxShadow: username ? `0 0 12px ${theme.glow}` : "none",
                  }}
                >
                  <span className="text-xs" style={{ color: username ? theme.from : "var(--text-secondary)", fontFamily: "var(--font-display)", fontWeight: 600 }}>@</span>
                  <input
                    value={username}
                    onChange={e => setUsername(e.target.value)}
                    placeholder="请输入用户名"
                    className="flex-1 bg-transparent outline-none text-sm"
                    style={{ color: "var(--text-primary)" }}
                    autoComplete="username"
                  />
                </div>
              </div>

              {/* Password */}
              <div className="flex flex-col gap-1.5">
                <label className="text-xs" style={{ color: "var(--text-secondary)", fontFamily: "var(--font-display)", fontWeight: 500, letterSpacing: "0.06em" }}>密码</label>
                <div
                  className="flex items-center gap-3 px-4 py-3 rounded-xl transition-all duration-200"
                  style={{
                    background: "var(--bg-elevated)",
                    border: `1px solid ${password ? theme.glow : "var(--border-strong)"}`,
                    boxShadow: password ? `0 0 12px ${theme.glow}` : "none",
                  }}
                >
                  <Lock size={15} style={{ color: password ? theme.from : "var(--text-secondary)", flexShrink: 0 }} />
                  <input
                    type={showPassword ? "text" : "password"}
                    value={password}
                    onChange={e => setPassword(e.target.value)}
                    placeholder="••••••••••••"
                    className="flex-1 bg-transparent outline-none text-sm"
                    style={{ color: "var(--text-primary)" }}
                    autoComplete="current-password"
                  />
                  <button type="button" onClick={() => setShowPassword(p => !p)}>
                    {showPassword
                      ? <EyeOff size={15} style={{ color: "var(--text-secondary)" }} />
                      : <Eye size={15} style={{ color: "var(--text-secondary)" }} />}
                  </button>
                </div>
              </div>

              {/* Error message */}
              {error && (
                <p className="text-xs" style={{ color: "#ff5555" }}>{error}</p>
              )}

              {/* Submit */}
              <button
                type="submit"
                disabled={loading}
                className="w-full flex items-center justify-center gap-2 py-3.5 rounded-xl text-sm transition-all duration-200 mt-2 hover:scale-[1.02] active:scale-[0.98] disabled:opacity-70 disabled:cursor-not-allowed"
                style={{
                  background: `linear-gradient(135deg,${theme.from},${theme.to})`,
                  color: "#fff",
                  fontFamily: "var(--font-display)",
                  fontWeight: 700,
                  boxShadow: `0 0 32px ${theme.glow}, 0 4px 16px rgba(0,0,0,0.4)`,
                  letterSpacing: "0.04em",
                }}
              >
                {loading ? (
                  <span className="flex items-center gap-2">
                    <svg className="animate-spin" width="16" height="16" viewBox="0 0 24 24" fill="none">
                      <circle cx="12" cy="12" r="10" stroke="rgba(255,255,255,0.3)" strokeWidth="3" />
                      <path d="M12 2a10 10 0 0 1 10 10" stroke="#fff" strokeWidth="3" strokeLinecap="round" />
                    </svg>
                    登录中…
                  </span>
                ) : (
                  <>
                    登录
                    <ArrowRight size={16} />
                  </>
                )}
              </button>
            </form>
          )}

          {/* ── 扫码登录面板 ─────────────────────────────────────────────────── */}
          {mode === "qrcode" && (
            <QRCodeLoginPanel
              qrcodeState={qrcodeState}
              qrcodeUrl={qrcodeUrl}
              qrcodeCode={qrcodeCode}
              qrcodeExpiresIn={qrcodeExpiresIn}
              onRefresh={refreshQRCode}
              theme={theme}
            />
          )}

          {/* Bottom hint */}
          <p className="text-sm text-center mt-8" style={{ color: "var(--text-secondary)" }}>
            还没有账号？
            <span
              style={{ color: theme.from, fontFamily: "var(--font-display)", fontWeight: 600 }}
            >
              联系管理员创建
            </span>
          </p>
        </div>
      </div>
    </div>
  );
}

// ── 扫码登录面板组件 ──────────────────────────────────────────────────────

interface QRCodeLoginPanelProps {
  qrcodeState: QRCodeLoginState;
  qrcodeUrl: string | null;
  qrcodeCode: string | null;
  qrcodeExpiresIn: number;
  onRefresh: () => void;
  theme: (typeof THEMES)[keyof typeof THEMES];
}

function QRCodeLoginPanel({
  qrcodeState,
  qrcodeUrl,
  qrcodeCode,
  qrcodeExpiresIn,
  onRefresh,
  theme,
}: QRCodeLoginPanelProps) {
  return (
    <div className="flex flex-col items-center gap-5">
      {/* 二维码区域 */}
      <div className="relative">
        {/* 二维码图片 */}
        <div
          className="w-[240px] h-[240px] rounded-2xl flex items-center justify-center overflow-hidden"
          style={{
            background: "#ffffff",
            border: `2px solid ${qrcodeState === "showing" ? theme.glow : "var(--border-strong)"}`,
            boxShadow: qrcodeState === "showing" ? `0 0 24px ${theme.glow}` : "none",
          }}
        >
          {qrcodeState === "loading" ? (
            <div className="flex flex-col items-center gap-3">
              <svg className="animate-spin" width="40" height="40" viewBox="0 0 24 24" fill="none">
                <circle cx="12" cy="12" r="10" stroke={theme.from} strokeWidth="2" opacity="0.3" />
                <path d="M12 2a10 10 0 0 1 10 10" stroke={theme.from} strokeWidth="2" strokeLinecap="round" />
              </svg>
              <span className="text-xs" style={{ color: "#666" }}>生成二维码中…</span>
            </div>
          ) : qrcodeUrl ? (
            <img src={qrcodeUrl} alt="扫码登录" className="w-full h-full object-contain" />
          ) : null}
        </div>

        {/* 状态遮罩 */}
        {(qrcodeState === "expired" || qrcodeState === "scanned" || qrcodeState === "error") && (
          <div
            className="absolute inset-0 rounded-2xl flex flex-col items-center justify-center gap-3"
            style={{ background: "rgba(255,255,255,0.88)", backdropFilter: "blur(4px)" }}
          >
            {qrcodeState === "expired" && (
              <>
                <Clock size={36} style={{ color: "#999" }} />
                <span className="text-sm" style={{ color: "#666" }}>二维码已过期</span>
                <button
                  onClick={onRefresh}
                  className="flex items-center gap-1.5 px-4 py-2 rounded-xl text-sm transition-all duration-200 hover:scale-105 active:scale-95"
                  style={{
                    background: `linear-gradient(135deg,${theme.from},${theme.to})`,
                    color: "#fff",
                    fontFamily: "var(--font-display)",
                    fontWeight: 600,
                    boxShadow: `0 0 16px ${theme.glow}`,
                  }}
                >
                  <RefreshCw size={14} />
                  刷新二维码
                </button>
              </>
            )}
            {qrcodeState === "scanned" && (
              <>
                <CheckCircle2 size={36} style={{ color: theme.from }} />
                <span className="text-sm font-medium" style={{ color: theme.from }}>扫码成功</span>
                <span className="text-xs" style={{ color: "#999" }}>正在登录…</span>
              </>
            )}
            {qrcodeState === "error" && (
              <>
                <AlertCircle size={36} style={{ color: "#ff5555" }} />
                <span className="text-sm" style={{ color: "#666" }}>网络错误</span>
                <button
                  onClick={onRefresh}
                  className="flex items-center gap-1.5 px-4 py-2 rounded-xl text-sm transition-all duration-200 hover:scale-105 active:scale-95"
                  style={{
                    background: `linear-gradient(135deg,${theme.from},${theme.to})`,
                    color: "#fff",
                    fontFamily: "var(--font-display)",
                    fontWeight: 600,
                    boxShadow: `0 0 16px ${theme.glow}`,
                  }}
                >
                  <RefreshCw size={14} />
                  重新获取
                </button>
              </>
            )}
          </div>
        )}
      </div>

      {/* 登录码展示 */}
      {qrcodeCode && (qrcodeState === "showing" || qrcodeState === "expired") && (
        <div
          className="flex items-center gap-2 px-4 py-2 rounded-xl"
          style={{ background: "var(--bg-elevated)", border: "1px solid var(--border-strong)" }}
        >
          <span className="text-xs" style={{ color: "var(--text-secondary)" }}>登录码：</span>
          <span
            className="text-lg tracking-[0.15em]"
            style={{ color: theme.from, fontFamily: "var(--font-display)", fontWeight: 700, letterSpacing: "0.15em" }}
          >
            {qrcodeCode}
          </span>
        </div>
      )}

      {/* 提示文字 */}
      <div className="text-center">
        {qrcodeState === "showing" && (
          <>
            <p className="text-sm" style={{ color: "var(--text-secondary)" }}>
              请使用 <span style={{ color: theme.from, fontWeight: 600 }}>MeowTV App</span> 扫描二维码
            </p>
            {qrcodeExpiresIn > 0 && (
              <p className="text-xs mt-1.5" style={{ color: "var(--text-muted)" }}>
                二维码将在 <span style={{ color: qrcodeExpiresIn <= 30 ? "#ff5555" : theme.from, fontWeight: 600 }}>{qrcodeExpiresIn}s</span> 后过期
              </p>
            )}
          </>
        )}
        {qrcodeState === "loading" && (
          <p className="text-sm" style={{ color: "var(--text-secondary)" }}>正在获取登录码…</p>
        )}
      </div>
    </div>
  );
}
