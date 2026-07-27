import { useNavigate } from "react-router";
import { Play, ChevronRight, Clock } from "lucide-react";
import { usePlayHistoryStore } from "@/stores/play-history";
import { useThemeStore } from "@/stores/theme";
import { THEMES } from "./Navbar";
import { GradientText } from "./GradientText";
import { buildResourceImageUrl } from "@/api/search";

/**
 * 首页"继续观看"板块 — 横向滚动展示最近播放记录，
 * 带进度条，点击可跳转继续播放。
 */
export function ContinueWatchingSection() {
  const navigate = useNavigate();
  const activeTheme = useThemeStore((s) => s.activeTheme);
  const theme = THEMES[activeTheme];
  const records = usePlayHistoryStore((s) => s.records);

  // 取最近 10 条记录（已看完的也显示，用进度条样式区分）
  const continueItems = records.slice(0, 10);

  if (continueItems.length === 0) return null;

  const handleClick = (record: typeof continueItems[0]) => {
    const params = new URLSearchParams({
      group_key: record.groupKey,
      name: record.vodName,
      site: record.resourceDomain,
      vod_id: String(record.vodId),
      source: String(record.sourceIndex),
      ep: String(record.epIndex),
    });
    navigate(`/play?${params.toString()}`);
  };

  const formatTime = (seconds: number) => {
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    const s = Math.floor(seconds % 60);
    if (h > 0) return `${h}:${m.toString().padStart(2, "0")}:${s.toString().padStart(2, "0")}`;
    return `${m}:${s.toString().padStart(2, "0")}`;
  };

  const formatRelativeTime = (ms: number) => {
    const diff = Date.now() - ms;
    const min = Math.floor(diff / 60000);
    if (min < 1) return "刚刚";
    if (min < 60) return `${min}分钟前`;
    const hour = Math.floor(min / 60);
    if (hour < 24) return `${hour}小时前`;
    const day = Math.floor(hour / 24);
    if (day < 7) return `${day}天前`;
    return `${new Date(ms).getMonth() + 1}/${new Date(ms).getDate()}`;
  };

  return (
    <section>
      {/* 标题栏 */}
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-3">
          <div
            className="w-8 h-8 rounded-xl flex items-center justify-center"
            style={{
              background: `linear-gradient(135deg,${theme.from},${theme.to})`,
              boxShadow: `0 0 16px ${theme.glow}`,
            }}
          >
            <Clock size={15} color="#fff" />
          </div>
          <h2
            className="tracking-wide"
            style={{ fontFamily: "var(--font-display)", fontWeight: 700, fontSize: "1.1rem" }}
          >
            <GradientText from="#ffffff" to={theme.from}>继续观看</GradientText>
          </h2>
        </div>
        <button
          onClick={() => navigate("/history")}
          className="flex items-center gap-1 text-xs px-3 py-1.5 rounded-xl transition-all duration-200"
          style={{ color: theme.from, fontFamily: "var(--font-display)" }}
          onMouseEnter={(e) => {
            e.currentTarget.style.background = `rgba(${hexToRgb(theme.from)},0.1)`;
          }}
          onMouseLeave={(e) => {
            e.currentTarget.style.background = "transparent";
          }}
        >
          查看全部 <ChevronRight size={12} />
        </button>
      </div>

      {/* 横向滚动卡片 */}
      <div
        className="flex gap-4 overflow-x-auto pb-2"
        style={{ scrollbarWidth: "none" }}
      >
        {continueItems.map((record) => {
          const picUrl = record.vodPic ? buildResourceImageUrl(record.vodPic) : "";
          const progressPercent = record.duration > 0 ? Math.min(record.progress, 100) : 0;
          const isWatched = progressPercent >= 95;

          return (
            <div
              key={`${record.vodId}-${record.resourceDomain}-ep${record.epIndex}`}
              className="shrink-0 w-[180px] cursor-pointer group"
              onClick={() => handleClick(record)}
            >
              {/* 封面 */}
              <div
                className="relative aspect-video rounded-xl overflow-hidden mb-2"
                style={{ background: "var(--bg-elevated)" }}
              >
                {picUrl ? (
                  <img
                    src={picUrl}
                    alt={record.vodName}
                    className="w-full h-full object-cover transition-transform duration-300 group-hover:scale-105"
                    onError={(e) => {
                      (e.target as HTMLImageElement).style.display = "none";
                    }}
                  />
                ) : (
                  <div className="w-full h-full flex items-center justify-center">
                    <Play size={20} style={{ color: "var(--text-tertiary)" }} />
                  </div>
                )}

                {/* 渐变遮罩 */}
                <div
                  className="absolute inset-0"
                  style={{
                    background:
                      "linear-gradient(to top, rgba(0,0,0,0.7) 0%, transparent 60%)",
                  }}
                />

                {/* 播放按钮 */}
                <div
                  className="absolute inset-0 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity duration-200"
                >
                  <div
                    className="w-10 h-10 rounded-full flex items-center justify-center"
                    style={{
                      background: `linear-gradient(135deg,${theme.from},${theme.to})`,
                      boxShadow: `0 0 20px ${theme.glow}`,
                    }}
                  >
                    <Play size={16} color="#fff" fill="#fff" />
                  </div>
                </div>

                {/* 进度条 */}
                {progressPercent > 0 && (
                  <div
                    className="absolute bottom-0 left-0 right-0 h-1"
                    style={{ background: "rgba(255,255,255,0.15)" }}
                  >
                    <div
                      className="h-full transition-all duration-300"
                      style={{
                        width: `${progressPercent}%`,
                        background: isWatched ? "rgba(255,255,255,0.5)" : theme.from,
                      }}
                    />
                  </div>
                )}

                {/* 已看完标签 */}
                {isWatched && (
                  <div
                    className="absolute top-1.5 right-1.5 text-[9px] px-1.5 py-0.5 rounded-md"
                    style={{
                      background: "rgba(0,0,0,0.7)",
                      color: "rgba(255,255,255,0.8)",
                      fontFamily: "var(--font-display)",
                    }}
                  >
                    已看完
                  </div>
                )}

                {/* 时长标签 */}
                {record.duration > 0 && (
                  <div
                    className="absolute bottom-1.5 right-1.5 text-[10px] px-1.5 py-0.5 rounded-md"
                    style={{
                      background: "rgba(0,0,0,0.75)",
                      color: "rgba(255,255,255,0.9)",
                      fontFamily: "var(--font-display)",
                    }}
                  >
                    {formatTime(record.currentTime)} / {formatTime(record.duration)}
                  </div>
                )}
              </div>

              {/* 信息 */}
              <p
                className="text-xs truncate mb-0.5"
                style={{ color: "var(--text-primary)", fontWeight: 500 }}
              >
                {record.vodName}
              </p>
              <p
                className="text-[10px] truncate"
                style={{ color: "var(--text-muted)" }}
              >
                {record.epName} · {record.resourceName}
              </p>
              <p
                className="text-[9px] mt-0.5"
                style={{ color: "var(--text-tertiary)" }}
              >
                {formatRelativeTime(record.updatedAt)}
              </p>
            </div>
          );
        })}
      </div>
    </section>
  );
}

/** 将 hex 颜色转为 r,g,b 字符串 */
function hexToRgb(hex: string): string {
  const m = hex.replace("#", "").match(/.{2}/g);
  if (!m) return "255,255,255";
  return m.map((c) => parseInt(c, 16)).join(",");
}
