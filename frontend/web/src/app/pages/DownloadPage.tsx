import { useState, useCallback } from "react";
import { ArrowLeft, Download, Play, RotateCw, Trash2, Ban, CheckCircle2, XCircle, Loader2, Filter } from "lucide-react";
import { useNavigate } from "react-router";
import { toast } from "sonner";
import { useThemeStore } from "@/stores/theme";
import { THEMES } from "@/app/components/Navbar";
import { GradientText } from "@/app/components/GradientText";
import { useDownloadTasks, getStatusLabel, isTerminalStatus, formatFileSize } from "@/hooks/useDownload";
import { cancelDownload, deleteDownload, retryDownload, getDownloadFileUrl } from "@/api/download";
import { ApiError } from "@/api/client";
import type { DownloadTaskItem, DownloadStatus } from "@/types/api";

const STATUS_FILTERS: { label: string; value: number | undefined }[] = [
  { label: "全部", value: undefined },
  { label: "下载中", value: 2 },
  { label: "已完成", value: 4 },
  { label: "失败", value: 5 },
  { label: "已取消", value: 6 },
];

function StatusBadge({ status }: { status: DownloadStatus }) {
  const activeTheme = useThemeStore((s) => s.activeTheme);
  const theme = THEMES[activeTheme];
  const label = getStatusLabel(status);
  let color = "var(--text-muted)";
  let bg = "var(--bg-elevated)";
  if (status === 2 || status === 1 || status === 3) { color = theme.from; bg = theme.subtle; }
  else if (status === 4) { color = "#4ade80"; bg = "rgba(34,197,94,0.08)"; }
  else if (status === 5) { color = "#fb7185"; bg = "rgba(220,38,38,0.08)"; }
  return (
    <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md text-[10px]" style={{ color, background: bg, fontFamily: "var(--font-display)" }}>
      {(status <= 3) && <Loader2 size={10} className="animate-spin" />}
      {status === 4 && <CheckCircle2 size={10} />}
      {status === 5 && <XCircle size={10} />}
      {status === 6 && <Ban size={10} />}
      {label}
    </span>
  );
}

export default function DownloadPage() {
  const activeTheme = useThemeStore((s) => s.activeTheme);
  const theme = THEMES[activeTheme];
  const navigate = useNavigate();
  const [statusFilter, setStatusFilter] = useState<number | undefined>(undefined);
  const { tasks, total, loading, refresh, silentRefresh } = useDownloadTasks({ interval: 3000, status: statusFilter, limit: 100 });

  const handleCancel = async (id: number) => { try { await cancelDownload(id); silentRefresh(); } catch (e) { toast.error(e instanceof ApiError ? e.message : "操作失败"); } };
  const handleDelete = async (id: number) => { try { await deleteDownload(id); silentRefresh(); } catch (e) { toast.error(e instanceof ApiError ? e.message : "操作失败"); } };
  const handleRetry = async (id: number) => { try { await retryDownload(id); silentRefresh(); } catch (e) { toast.error(e instanceof ApiError ? e.message : "操作失败"); } };
  const handlePlay = (t: DownloadTaskItem) => {
    const p = new URLSearchParams({
      group_key: t.group_key || "", name: t.vod_name, site: t.resource_domain,
      vod_id: String(t.vod_id), source: String(t.source_index), ep: String(t.ep_index),
    });
    navigate(`/play?${p.toString()}`);
  };

  const formatDate = (ts: number) => {
    if (!ts) return "";
    const d = new Date(ts);
    return `${d.getMonth() + 1}/${d.getDate()} ${d.getHours().toString().padStart(2, "0")}:${d.getMinutes().toString().padStart(2, "0")}`;
  };

  return (
    <div className="px-4 md:px-8 lg:px-12 py-4">
      {/* Header */}
      <div className="flex items-center gap-3 mb-6">
        <button onClick={() => navigate(-1)}
          className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg transition-all duration-200"
          style={{ background: "var(--bg-elevated)", color: "var(--text-muted)" }}
          onMouseEnter={(e) => { e.currentTarget.style.background = theme.subtle; e.currentTarget.style.color = theme.from; }}
          onMouseLeave={(e) => { e.currentTarget.style.background = "var(--bg-elevated)"; e.currentTarget.style.color = "var(--text-muted)"; }}>
          <ArrowLeft size={14} />
          <span className="text-xs" style={{ fontFamily: "var(--font-display)" }}>返回</span>
        </button>
        <h1 style={{ fontFamily: "var(--font-display)", fontWeight: 800, fontSize: "1.1rem" }}>
          <GradientText from={theme.from} to={theme.to}>下载管理</GradientText>
        </h1>
        <span className="text-xs" style={{ color: "var(--text-muted)" }}>({total})</span>
      </div>

      {/* Filters */}
      <div className="flex items-center gap-2 mb-4">
        <Filter size={14} style={{ color: "var(--text-muted)" }} />
        {STATUS_FILTERS.map((f) => (
          <button key={String(f.value)} onClick={() => setStatusFilter(f.value)}
            className="px-3 py-1.5 rounded-lg text-xs transition-all duration-200"
            style={{
              background: statusFilter === f.value ? theme.subtle : "var(--bg-elevated)",
              color: statusFilter === f.value ? theme.from : "var(--text-muted)",
              border: statusFilter === f.value ? `1px solid ${theme.from}40` : "1px solid var(--border-default)",
              fontFamily: "var(--font-display)",
            }}>
            {f.label}
          </button>
        ))}
      </div>

      {/* Task list */}
      {loading && tasks.length === 0 ? (
        <div className="flex items-center justify-center py-20">
          <Loader2 size={32} className="animate-spin" style={{ color: theme.from }} />
        </div>
      ) : tasks.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-20">
          <Download size={48} style={{ color: "var(--text-tertiary)" }} />
          <p className="mt-4 text-sm" style={{ color: "var(--text-secondary)" }}>暂无下载任务</p>
        </div>
      ) : (
        <div className="space-y-2">
          {tasks.map((task) => (
            <div key={task.id}
              className="flex items-center gap-4 px-4 py-3 rounded-xl transition-colors"
              style={{ background: "var(--bg-surface)", border: "1px solid var(--border-default)" }}>
              {/* 封面 */}
              {task.vod_pic ? (
                <img src={task.vod_pic} alt="" loading="lazy" className="w-10 h-14 rounded-lg object-cover shrink-0"
                  style={{ background: "var(--bg-elevated)" }} onError={(e) => { (e.target as HTMLImageElement).style.display = "none"; }} />
              ) : (
                <div className="w-10 h-14 rounded-lg flex items-center justify-center shrink-0" style={{ background: "var(--bg-elevated)" }}>
                  <Download size={16} style={{ color: "var(--text-muted)" }} />
                </div>
              )}

              {/* 信息 */}
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  <p className="text-sm truncate" style={{ color: "var(--text-primary)" }}>{task.vod_name}</p>
                  <span className="text-xs shrink-0" style={{ color: "var(--text-muted)" }}>- {task.ep_name}</span>
                </div>
                <div className="flex items-center gap-3 mt-1">
                  <StatusBadge status={task.status} />
                  <span className="text-[10px]" style={{ color: "var(--text-muted)" }}>{task.resource_name}</span>
                  <span className="text-[10px]" style={{ color: "var(--text-muted)" }}>{formatDate(task.created_at)}</span>
                </div>
                {/* Progress bar */}
                {(task.status === 2 || task.status === 3) && (
                  <div className="flex items-center gap-2 mt-1.5">
                    <div className="flex-1 h-1.5 rounded-full overflow-hidden" style={{ background: "var(--bg-elevated)" }}>
                      <div className="h-full rounded-full transition-all duration-300"
                        style={{ width: `${Math.min(task.progress, 100)}%`, background: theme.from }} />
                    </div>
                    <span className="text-[10px] shrink-0" style={{ color: theme.from }}>
                      {task.progress.toFixed(1)}%
                    </span>
                    {task.downloaded_segments > 0 && task.total_segments > 0 && (
                      <span className="text-[10px]" style={{ color: "var(--text-muted)" }}>
                        {task.downloaded_segments}/{task.total_segments} 分片
                      </span>
                    )}
                  </div>
                )}
                {/* Completed info */}
                {task.status === 4 && task.file_size > 0 && (
                  <span className="text-[10px] mt-1 inline-block" style={{ color: "var(--text-muted)" }}>
                    {formatFileSize(task.file_size)}
                  </span>
                )}
                {/* Error info */}
                {task.status === 5 && task.error_msg && (
                  <p className="text-[10px] mt-1 truncate" style={{ color: "#fb7185" }}>{task.error_msg}</p>
                )}
              </div>

              {/* Actions */}
              <div className="flex items-center gap-1.5 shrink-0">
                {task.status === 4 && (
                  <button onClick={() => handlePlay(task)}
                    className="flex items-center gap-1 px-2.5 py-1.5 rounded-lg text-xs transition-colors"
                    style={{ color: "#4ade80", background: "rgba(34,197,94,0.08)" }}
                    onMouseEnter={(e) => { e.currentTarget.style.background = "rgba(34,197,94,0.15)"; }}
                    onMouseLeave={(e) => { e.currentTarget.style.background = "rgba(34,197,94,0.08)"; }}>
                    <Play size={12} />播放
                  </button>
                )}
                {(task.status >= 0 && task.status <= 3) && (
                  <button onClick={() => handleCancel(task.id)}
                    className="p-1.5 rounded-lg transition-colors" style={{ color: "var(--text-muted)" }}
                    onMouseEnter={(e) => { e.currentTarget.style.background = "var(--bg-elevated)"; }}
                    onMouseLeave={(e) => { e.currentTarget.style.background = "transparent"; }} title="取消">
                    <Ban size={14} />
                  </button>
                )}
                {task.status === 5 && (
                  <button onClick={() => handleRetry(task.id)}
                    className="flex items-center gap-1 px-2.5 py-1.5 rounded-lg text-xs transition-colors"
                    style={{ color: theme.from, background: theme.subtle }}
                    onMouseEnter={(e) => { e.currentTarget.style.background = theme.from; e.currentTarget.style.color = "#fff"; }}
                    onMouseLeave={(e) => { e.currentTarget.style.background = theme.subtle; e.currentTarget.style.color = theme.from; }}>
                    <RotateCw size={12} />重试
                  </button>
                )}
                {(task.status === 4 || task.status === 5 || task.status === 6) && (
                  <button onClick={() => handleDelete(task.id)}
                    className="p-1.5 rounded-lg transition-colors" style={{ color: "#fb7185" }}
                    onMouseEnter={(e) => { e.currentTarget.style.background = "rgba(220,38,38,0.08)"; }}
                    onMouseLeave={(e) => { e.currentTarget.style.background = "transparent"; }} title="删除">
                    <Trash2 size={14} />
                  </button>
                )}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}