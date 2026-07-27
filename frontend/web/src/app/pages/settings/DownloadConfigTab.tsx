import { useEffect, useState } from "react";
import { RefreshCw } from "lucide-react";
import * as downloadApi from "@/api/download";
import { ApiError } from "@/api/client";
import type { SettingsTheme } from "./settings-styles";
import { cardStyle, sectionTitleStyle, labelStyle, inputStyle, primaryBtnStyle } from "./settings-styles";

export function DownloadConfigTab({ theme }: { theme: SettingsTheme }) {
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState<{ type: "success" | "error"; text: string } | null>(null);

  // 配置数据
  const [downloadDir, setDownloadDir] = useState("data/downloads");
  const [maxConcurrent, setMaxConcurrent] = useState(2);
  const [segmentConcurrency, setSegmentConcurrency] = useState(10);

  const fetchConfig = async () => {
    setLoading(true);
    try {
      const cfg = await downloadApi.adminGetDownloadConfig();
      setDownloadDir(cfg.download_dir || "data/downloads");
      setMaxConcurrent(cfg.max_concurrent || 2);
      setSegmentConcurrency(cfg.segment_concurrency || 10);
    } catch {
      // 静默
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { fetchConfig(); }, []);

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    setMessage(null);
    try {
      await downloadApi.adminUpdateDownloadConfig({
        download_dir: downloadDir,
        max_concurrent: maxConcurrent,
        segment_concurrency: segmentConcurrency,
      });
      setMessage({ type: "success", text: "下载配置已保存" });
      await fetchConfig();
    } catch (err) {
      setMessage({ type: "error", text: err instanceof ApiError ? err.message : "保存失败" });
    } finally {
      setSaving(false);
    }
  };

  return (
    <div>
      {message && <p className="text-xs mb-4" style={{ color: message.type === "success" ? "#34d399" : "#ff5555" }}>{message.text}</p>}

      {loading ? (
        <div className="rounded-2xl p-8 text-center text-sm" style={cardStyle}>
          <span style={{ color: "var(--text-secondary)" }}>加载中…</span>
        </div>
      ) : (
        <div className="rounded-2xl p-6" style={{ ...cardStyle, border: `1px solid ${theme.glow}` }}>
          <div className="flex items-center justify-between mb-6">
            <h2 style={sectionTitleStyle}>下载配置</h2>
            <button onClick={fetchConfig} className="flex items-center gap-1 text-xs px-3 py-2 rounded-xl" style={{ color: theme.from, fontFamily: "var(--font-display)", background: "var(--bg-elevated)", border: "1px solid var(--border-strong)" }}>
              <RefreshCw size={12} /> 刷新
            </button>
          </div>

          <form onSubmit={handleSave} className="space-y-5">
            {/* 下载目录 */}
            <div className="flex flex-col gap-1.5">
              <label style={labelStyle}>下载目录</label>
              <input
                value={downloadDir}
                onChange={e => setDownloadDir(e.target.value)}
                className="px-4 py-2.5 rounded-xl text-sm outline-none"
                style={inputStyle}
                placeholder="data/downloads"
              />
            </div>

            {/* 最大并发下载数 + 分片并发数 */}
            <div className="grid grid-cols-2 gap-4">
              <div className="flex flex-col gap-1.5">
                <label style={labelStyle}>最大并发下载数</label>
                <input
                  type="number"
                  min={1}
                  max={10}
                  value={maxConcurrent}
                  onChange={e => setMaxConcurrent(Math.min(10, Math.max(1, Number(e.target.value) || 1)))}
                  className="px-4 py-2.5 rounded-xl text-sm outline-none"
                  style={inputStyle}
                />
              </div>
              <div className="flex flex-col gap-1.5">
                <label style={labelStyle}>分片并发数</label>
                <input
                  type="number"
                  min={1}
                  max={50}
                  value={segmentConcurrency}
                  onChange={e => setSegmentConcurrency(Math.min(50, Math.max(1, Number(e.target.value) || 1)))}
                  className="px-4 py-2.5 rounded-xl text-sm outline-none"
                  style={inputStyle}
                />
              </div>
            </div>

            {/* 保存按钮 */}
            <div className="flex justify-end pt-2">
              <button type="submit" disabled={saving} className="px-6 py-2.5 rounded-xl text-sm hover:scale-105 transition-all duration-200" style={primaryBtnStyle(theme, saving)}>
                {saving ? "保存中…" : "保存配置"}
              </button>
            </div>
          </form>
        </div>
      )}
    </div>
  );
}
