import { useNavigate } from "react-router";
import { Clock, Play, Trash2 } from "lucide-react";
import { usePlayHistoryStore } from "@/stores/play-history";
import { useThemeStore } from "@/stores/theme";
import { THEMES } from "./Navbar";
import { buildResourceImageUrl } from "@/api/search";

/**
 * 最近播放历史面板 — 显示在播放页右栏底部，
 * 展示最近观看记录，点击可跳转继续观看。
 */
export function PlayHistoryPanel() {
  const navigate = useNavigate();
  const activeTheme = useThemeStore((s) => s.activeTheme);
  const theme = THEMES[activeTheme];
  const records = usePlayHistoryStore((s) => s.records);
  const removeRecord = usePlayHistoryStore((s) => s.removeRecord);
  const clearAll = usePlayHistoryStore((s) => s.clearAll);

  // 只取最近 8 条
  const recentRecords = records.slice(0, 8);

  if (recentRecords.length === 0) return null;

  const formatTime = (ms: number) => {
    const d = new Date(ms);
    const now = new Date();
    const diffMs = now.getTime() - d.getTime();
    const diffMin = Math.floor(diffMs / 60000);
    if (diffMin < 1) return "刚刚";
    if (diffMin < 60) return `${diffMin}分钟前`;
    const diffHour = Math.floor(diffMin / 60);
    if (diffHour < 24) return `${diffHour}小时前`;
    const diffDay = Math.floor(diffHour / 24);
    if (diffDay < 7) return `${diffDay}天前`;
    return `${d.getMonth() + 1}/${d.getDate()}`;
  };

  const formatProgress = (currentTime: number, duration: number) => {
    if (duration <= 0) return "";
    const min = Math.floor(currentTime / 60);
    const sec = Math.floor(currentTime % 60);
    return `${min}:${sec.toString().padStart(2, "0")}`;
  };

  const handleClick = (record: typeof recentRecords[0]) => {
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

  return (
    <div
      className="rounded-xl p-4"
      style={{ background: "var(--bg-surface)", border: "1px solid var(--border-default)" }}
    >
      {/* 标题栏 */}
      <div className="flex items-center justify-between mb-3">
        <h3
          className="flex items-center gap-1.5 text-xs"
          style={{ color: "var(--text-muted)", fontFamily: "var(--font-display)", fontWeight: 600 }}
        >
          <Clock size={12} />
          最近观看
        </h3>
        <button
          onClick={clearAll}
          className="flex items-center gap-0.5 text-[10px] px-1.5 py-0.5 rounded-md transition-all duration-200"
          style={{ color: "var(--text-tertiary)" }}
          onMouseEnter={(e) => {
            e.currentTarget.style.color = "#fb7185";
            e.currentTarget.style.background = "rgba(220,38,38,0.08)";
          }}
          onMouseLeave={(e) => {
            e.currentTarget.style.color = "var(--text-tertiary)";
            e.currentTarget.style.background = "transparent";
          }}
        >
          <Trash2 size={9} />
          清空
        </button>
      </div>

      {/* 历史列表 */}
      <div className="space-y-2">
        {recentRecords.map((record) => {
          const picUrl = record.vodPic ? buildResourceImageUrl(record.vodPic) : "";
          const progressPercent = record.duration > 0 ? Math.min(record.progress, 100) : 0;

          return (
            <div
              key={`${record.vodId}-${record.resourceDomain}-ep${record.epIndex}`}
              className="flex gap-2.5 p-2 rounded-lg cursor-pointer transition-all duration-200 group"
              style={{ background: "transparent" }}
              onClick={() => handleClick(record)}
              onMouseEnter={(e) => {
                e.currentTarget.style.background = "var(--bg-hover)";
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.background = "transparent";
              }}
            >
              {/* 缩略图 */}
              <div
                className="relative w-16 h-10 shrink-0 rounded-md overflow-hidden"
                style={{ background: "var(--bg-elevated)" }}
              >
                {picUrl ? (
                  <img
                    src={picUrl}
                    alt={record.vodName}
                    className="w-full h-full object-cover"
                    onError={(e) => { (e.target as HTMLImageElement).style.display = "none"; }}
                  />
                ) : (
                  <div className="w-full h-full flex items-center justify-center">
                    <Play size={10} style={{ color: "var(--text-tertiary)" }} />
                  </div>
                )}
                {/* 进度条 */}
                {progressPercent > 0 && (
                  <div
                    className="absolute bottom-0 left-0 right-0 h-0.5"
                    style={{ background: "rgba(255,255,255,0.15)" }}
                  >
                    <div
                      className="h-full"
                      style={{ width: `${progressPercent}%`, background: theme.from }}
                    />
                  </div>
                )}
                {/* 时长标签 */}
                {record.duration > 0 && (
                  <div
                    className="absolute bottom-0.5 right-0.5 text-[8px] px-0.5 rounded"
                    style={{
                      background: "rgba(0,0,0,0.7)",
                      color: "rgba(255,255,255,0.8)",
                      fontFamily: "var(--font-display)",
                    }}
                  >
                    {formatProgress(record.currentTime, record.duration)}
                  </div>
                )}
              </div>

              {/* 信息 */}
              <div className="flex-1 min-w-0">
                <p
                  className="text-[11px] leading-tight truncate"
                  style={{ color: "var(--text-primary)", fontWeight: 500 }}
                >
                  {record.vodName}
                </p>
                <p
                  className="text-[10px] truncate mt-0.5"
                  style={{ color: "var(--text-muted)" }}
                >
                  {record.epName} · {record.resourceName}
                </p>
                <p
                  className="text-[9px] mt-0.5"
                  style={{ color: "var(--text-tertiary)" }}
                >
                  {formatTime(record.updatedAt)}
                </p>
              </div>

              {/* 删除按钮 */}
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  removeRecord(record.vodId, record.resourceDomain, record.epIndex);
                }}
                className="shrink-0 self-center opacity-0 group-hover:opacity-100 w-5 h-5 flex items-center justify-center rounded transition-all duration-200"
                style={{ color: "var(--text-tertiary)" }}
                onMouseEnter={(e) => { e.currentTarget.style.color = "#fb7185"; }}
                onMouseLeave={(e) => { e.currentTarget.style.color = "var(--text-tertiary)"; }}
              >
                <Trash2 size={10} />
              </button>
            </div>
          );
        })}
      </div>
    </div>
  );
}
