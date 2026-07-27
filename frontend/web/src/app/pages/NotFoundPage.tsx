import { useNavigate } from "react-router";
import { Home } from "lucide-react";
import { GradientText } from "@/app/components/GradientText";
import { THEMES } from "@/app/components/Navbar";
import { useThemeStore } from "@/stores/theme";

export default function NotFoundPage() {
  const activeTheme = useThemeStore((s) => s.activeTheme);
  const theme = THEMES[activeTheme];
  const navigate = useNavigate();

  return (
    <div
      className="min-h-screen flex items-center justify-center"
      style={{ background: "var(--bg-base)" }}
    >
      <div className="text-center">
        <p
          className="mb-4"
          style={{ fontFamily: "var(--font-display)", fontWeight: 800, fontSize: "6rem", lineHeight: 1 }}
        >
          <GradientText from={theme.from} to={theme.to}>404</GradientText>
        </p>
        <h2
          className="mb-2"
          style={{ fontFamily: "var(--font-display)", fontWeight: 700, fontSize: "1.5rem", color: "#ffffff" }}
        >
          页面未找到
        </h2>
        <p className="mb-8 text-sm" style={{ color: "var(--text-secondary)" }}>
          你访问的页面不存在或已被移动。
        </p>
        <button
          onClick={() => navigate("/")}
          className="inline-flex items-center gap-2 px-6 py-3 rounded-xl text-sm transition-all duration-200 hover:scale-105"
          style={{
            background: `linear-gradient(135deg,${theme.from},${theme.to})`,
            color: "#fff",
            fontFamily: "var(--font-display)",
            fontWeight: 700,
            boxShadow: `0 0 24px ${theme.glow}`,
          }}
        >
          <Home size={16} />
          返回首页
        </button>
      </div>
    </div>
  );
}
