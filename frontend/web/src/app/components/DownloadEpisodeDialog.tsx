import { useState, useCallback } from "react";
import { Download, Check, Loader2, X } from "lucide-react";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/app/components/ui/dialog";
import { Button } from "@/app/components/ui/button";
import { createDownload } from "@/api/download";
import { useThemeStore } from "@/stores/theme";
import { THEMES } from "./Navbar";
import type { PlaySource, PlayEpisode, DownloadItem } from "@/types/api";

interface DownloadEpisodeDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  /** 多源剧集列表 */
  sources: PlaySource[];
  /** 当前选中的源索引 */
  defaultSourceIndex?: number;
  /** 视频基本信息（用于创建下载任务） */
  vodId: number;
  vodName: string;
  vodPic: string;
  resourceDomain: string;
  resourceName: string;
  groupKey: string;
}

export function DownloadEpisodeDialog({
  open,
  onOpenChange,
  sources,
  defaultSourceIndex = 0,
  vodId,
  vodName,
  vodPic,
  resourceDomain,
  resourceName,
  groupKey,
}: DownloadEpisodeDialogProps) {
  const activeTheme = useThemeStore((s) => s.activeTheme);
  const theme = THEMES[activeTheme];

  const [sourceIndex, setSourceIndex] = useState(defaultSourceIndex);
  const [selectedEps, setSelectedEps] = useState<Set<number>>(new Set());
  const [submitting, setSubmitting] = useState(false);
  const [result, setResult] = useState<string | null>(null);

  const currentSource = sources[sourceIndex];
  const episodes = currentSource?.episodes ?? [];

  // 切换源时重置选中
  const handleSourceChange = useCallback(
    (idx: number) => {
      setSourceIndex(idx);
      setSelectedEps(new Set());
      setResult(null);
    },
    []
  );

  // 切换单个剧集选中
  const toggleEp = useCallback((epIdx: number) => {
    setSelectedEps((prev) => {
      const next = new Set(prev);
      if (next.has(epIdx)) next.delete(epIdx);
      else next.add(epIdx);
      return next;
    });
  }, []);

  // 全选/取消全选
  const toggleAll = useCallback(() => {
    if (selectedEps.size === episodes.length) {
      setSelectedEps(new Set());
    } else {
      setSelectedEps(new Set(episodes.map((_, i) => i)));
    }
  }, [selectedEps.size, episodes.length]);

  // 提交下载
  const handleSubmit = useCallback(async () => {
    if (selectedEps.size === 0) return;
    setSubmitting(true);
    setResult(null);

    const items: DownloadItem[] = Array.from(selectedEps).map((epIdx) => ({
      source_index: sourceIndex,
      ep_index: epIdx,
      ep_name: episodes[epIdx].name,
      m3u8_url: episodes[epIdx].url,
    }));

    try {
      const resp = await createDownload({
        vod_id: vodId,
        vod_name: vodName,
        vod_pic: vodPic,
        resource_domain: resourceDomain,
        resource_name: resourceName,
        group_key: groupKey,
        items,
      });
      setResult(`已添加 ${resp.queued} 个任务${resp.skipped > 0 ? `，跳过 ${resp.skipped} 个（已存在）` : ""}`);
      setSelectedEps(new Set());
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : "创建下载任务失败";
      setResult(`失败: ${msg}`);
    } finally {
      setSubmitting(false);
    }
  }, [selectedEps, sourceIndex, episodes, vodId, vodName, vodPic, resourceDomain, resourceName, groupKey]);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg max-h-[80vh] flex flex-col">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Download size={18} />
            下载剧集
          </DialogTitle>
        </DialogHeader>

        {/* 源选择 */}
        {sources.length > 1 && (
          <div className="flex gap-2 flex-wrap mb-2">
            {sources.map((src, idx) => (
              <button
                key={idx}
                onClick={() => handleSourceChange(idx)}
                className="px-3 py-1 rounded-lg text-xs transition-all duration-200"
                style={{
                  background: idx === sourceIndex ? theme.subtle : "var(--bg-elevated)",
                  color: idx === sourceIndex ? theme.from : "var(--text-muted)",
                  border: idx === sourceIndex ? `1px solid ${theme.from}40` : "1px solid var(--border-default)",
                  fontFamily: "var(--font-display)",
                }}
              >
                {src.name || `线路${idx + 1}`}
              </button>
            ))}
          </div>
        )}

        {/* 全选按钮 */}
        <div className="flex items-center justify-between mb-2">
          <span className="text-xs" style={{ color: "var(--text-muted)" }}>
            已选 {selectedEps.size}/{episodes.length} 集
          </span>
          <Button variant="ghost" size="sm" className="text-xs h-7" onClick={toggleAll}>
            {selectedEps.size === episodes.length ? "取消全选" : "全选"}
          </Button>
        </div>

        {/* 剧集列表 */}
        <div className="flex-1 overflow-y-auto">
          <div className="grid grid-cols-4 sm:grid-cols-5 gap-2">
            {episodes.map((ep, idx) => {
              const selected = selectedEps.has(idx);
              return (
                <button
                  key={idx}
                  onClick={() => toggleEp(idx)}
                  className="relative flex items-center justify-center gap-1 px-2 py-2 rounded-lg text-xs transition-all duration-200 cursor-pointer"
                  style={{
                    background: selected ? theme.subtle : "var(--bg-elevated)",
                    color: selected ? theme.from : "var(--text-muted)",
                    border: selected ? `1px solid ${theme.from}40` : "1px solid var(--border-default)",
                    fontFamily: "var(--font-display)",
                  }}
                  title={ep.name}
                >
                  {selected && <Check size={10} style={{ flexShrink: 0 }} />}
                  <span className="truncate">{ep.name}</span>
                </button>
              );
            })}
          </div>
        </div>

        {/* 结果提示 */}
        {result && (
          <div
            className="flex items-center gap-2 px-3 py-2 rounded-lg text-xs"
            style={{
              background: result.startsWith("失败") ? "rgba(220,38,38,0.08)" : "rgba(34,197,94,0.08)",
              color: result.startsWith("失败") ? "#fb7185" : "#4ade80",
            }}
          >
            {result.startsWith("失败") ? <X size={14} /> : <Check size={14} />}
            {result}
          </div>
        )}

        {/* 提交按钮 */}
        <Button
          onClick={handleSubmit}
          disabled={selectedEps.size === 0 || submitting}
          className="w-full mt-2"
          style={{
            background: theme.from,
            color: "#fff",
          }}
        >
          {submitting ? (
            <>
              <Loader2 size={14} className="animate-spin mr-2" />
              提交中...
            </>
          ) : (
            <>
              <Download size={14} className="mr-2" />
              下载选中 ({selectedEps.size})
            </>
          )}
        </Button>
      </DialogContent>
    </Dialog>
  );
}
