import { useRef, useEffect } from "react";
import { Download, X, Play, RotateCw, Trash2, Loader2, CheckCircle2, XCircle, Ban } from "lucide-react";
import { useNavigate } from "react-router";
import { toast } from "sonner";
import { useThemeStore } from "@/stores/theme";
import { THEMES } from "./Navbar";
import { useDownloadTasks, getStatusLabel, formatFileSize } from "@/hooks/useDownload";
import { cancelDownload, deleteDownload, retryDownload } from "@/api/download";
import { ApiError } from "@/api/client";
import type { DownloadTaskItem, DownloadStatus } from "@/types/api";

interface DownloadDropdownProps {
  open: boolean;
  onClose: () => void;
}

function StatusIcon({ status }: { status: DownloadStatus }) {
  if (status <= 3) return <Loader2 size={14} className="animate-spin" style={{ color: "var(--text-muted)" }} />;
  if (status === 4) return <CheckCircle2 size={14} style={{ color: "#4ade80" }} />;
  if (status === 5) return <XCircle size={14} style={{ color: "#fb7185" }} />;
  return <Ban size={14} style={{ color: "var(--text-muted)" }} />;
}

export function DownloadDropdown({ open, onClose }: DownloadDropdownProps) {
  const activeTheme = useThemeStore((s) => s.activeTheme);
  const theme = THEMES[activeTheme];
  const navigate = useNavigate();
  const ref = useRef<HTMLDivElement>(null);
  const { tasks, refresh, silentRefresh, hasActiveTasks } = useDownloadTasks({ interval: open ? 3000 : 0, limit: 10 });

  useEffect(() => {
    if (!open) return;
    const handleClick = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) onClose();
    };
    document.addEventListener("mousedown", handleClick);
    return () => document.removeEventListener("mousedown", handleClick);
  }, [open, onClose]);

  if (!open) return null;

  const handleCancel = async (id: number) => { try { await cancelDownload(id); silentRefresh(); } catch (e) { toast.error(e instanceof ApiError ? e.message : "操作失败"); } };
  const handleDelete = async (id: number) => { try { await deleteDownload(id); silentRefresh(); } catch (e) { toast.error(e instanceof ApiError ? e.message : "操作失败"); } };
  const handleRetry = async (id: number) => { try { await retryDownload(id); silentRefresh(); } catch (e) { toast.error(e instanceof ApiError ? e.message : "操作失败"); } };
  const handlePlay = (t: DownloadTaskItem) => {
    const p = new URLSearchParams({
      group_key: t.group_key || "", name: t.vod_name, site: t.resource_domain,
      vod_id: String(t.vod_id), source: String(t.source_index), ep: String(t.ep_index),
    });
    navigate(`/play?${p.toString()}`);
    onClose();
  };

  return (
    <div ref={ref} className="absolute top-12 right-0 rounded-2xl overflow-hidden w-[380px] max-h-[480px] flex flex-col"
      style={{ background: "var(--bg-surface-strong)", backdropFilter: "blur(24px)", WebkitBackdropFilter: "blur(24px)", border: "1px solid var(--border-strong)", boxShadow: "var(--shadow-dropdown)" }}>
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-3" style={{ borderBottom: "1px solid var(--border-default)" }}>
        <div className="flex items-center gap-2">
          <Download size={16} style={{ color: theme.from }} />
          <span className="text-sm font-semibold" style={{ color: "var(--text-primary)", fontFamily: "var(--font-display)" }}>下载管理</span>
          {hasActiveTasks && <span className="w-2 h-2 rounded-full animate-pulse" style={{ background: theme.from }} />}
        </div>
        <div className="flex items-center gap-2">
          <button onClick={() => { navigate("/downloads"); onClose(); }}
            className="text-xs px-2 py-1 rounded-lg transition-colors"
            style={{ color: theme.from, fontFamily: "var(--font-display)" }}
            onMouseEnter={(e) => { e.currentTarget.style.background = theme.subtle; }}
            onMouseLeave={(e) => { e.currentTarget.style.background = "transparent"; }}>
            查看全部
          </button>
          <button onClick={onClose} className="p-1 rounded-lg" style={{ color: "var(--text-muted)" }}><X size={14} /></button>
        </div>
      </div>
      {/* List */}
      <div className="flex-1 overflow-y-auto">
        {tasks.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-8">
            <Download size={32} style={{ color: "var(--text-tertiary)" }} />
            <p className="mt-2 text-xs" style={{ color: "var(--text-muted)" }}>暂无下载任务</p>
          </div>
        ) : tasks.map((task) => (
          <div key={task.id} className="flex items-center gap-3 px-4 py-3 transition-colors"
            style={{ borderBottom: "1px solid var(--border-default)" }}
            onMouseEnter={(e) => { e.currentTarget.style.background = theme.subtle; }}
            onMouseLeave={(e) => { e.currentTarget.style.background = "transparent"; }}>
            <StatusIcon status={task.status} />
            <div className="flex-1 min-w-0">
              <p className="text-xs truncate" style={{ color: "var(--text-primary)" }}>{task.vod_name} - {task.ep_name}</p>
              <div className="flex items-center gap-2 mt-0.5">
                <span className="text-[10px]" style={{ color: "var(--text-muted)" }}>{getStatusLabel(task.status)}</span>
                {task.status === 2 && task.progress > 0 && (
                  <>
                    <span className="text-[10px]" style={{ color: theme.from }}>{task.progress.toFixed(1)}%</span>
                    <div className="flex-1 h-1 rounded-full overflow-hidden" style={{ background: "var(--bg-elevated)", maxWidth: 60 }}>
                      <div className="h-full rounded-full transition-all duration-300" style={{ width: `${Math.min(task.progress, 100)}%`, background: theme.from }} />
                    </div>
                  </>
                )}
                {task.status === 4 && task.file_size > 0 && (
                  <span className="text-[10px]" style={{ color: "var(--text-muted)" }}>{formatFileSize(task.file_size)}</span>
                )}
                {task.status === 5 && task.error_msg && (
                  <span className="text-[10px] truncate" style={{ color: "#fb7185" }} title={task.error_msg}>{task.error_msg}</span>
                )}
              </div>
            </div>
            <div className="flex items-center gap-1 shrink-0">
              {task.status === 4 && (
                <button onClick={() => handlePlay(task)} className="p-1.5 rounded-lg transition-colors" style={{ color: "#4ade80" }}
                  onMouseEnter={(e) => { e.currentTarget.style.background = "rgba(34,197,94,0.1)"; }}
                  onMouseLeave={(e) => { e.currentTarget.style.background = "transparent"; }} title="播放"><Play size={12} /></button>
              )}
              {(task.status >= 0 && task.status <= 3) && (
                <button onClick={() => handleCancel(task.id)} className="p-1.5 rounded-lg transition-colors" style={{ color: "var(--text-muted)" }}
                  onMouseEnter={(e) => { e.currentTarget.style.background = "var(--bg-elevated)"; }}
                  onMouseLeave={(e) => { e.currentTarget.style.background = "transparent"; }} title="取消"><Ban size={12} /></button>
              )}
              {task.status === 5 && (
                <button onClick={() => handleRetry(task.id)} className="p-1.5 rounded-lg transition-colors" style={{ color: theme.from }}
                  onMouseEnter={(e) => { e.currentTarget.style.background = theme.subtle; }}
                  onMouseLeave={(e) => { e.currentTarget.style.background = "transparent"; }} title="重试"><RotateCw size={12} /></button>
              )}
              {(task.status === 4 || task.status === 5 || task.status === 6) && (
                <button onClick={() => handleDelete(task.id)} className="p-1.5 rounded-lg transition-colors" style={{ color: "#fb7185" }}
                  onMouseEnter={(e) => { e.currentTarget.style.background = "rgba(220,38,38,0.08)"; }}
                  onMouseLeave={(e) => { e.currentTarget.style.background = "transparent"; }} title="删除"><Trash2 size={12} /></button>
              )}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
