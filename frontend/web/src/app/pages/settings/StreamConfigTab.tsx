import { useEffect, useState } from "react";
import { RefreshCw, ToggleLeft, ToggleRight } from "lucide-react";
import * as configApi from "@/api/config";
import { ApiError } from "@/api/client";
import type { SettingsTheme } from "./settings-styles";
import { cardStyle, sectionTitleStyle, labelStyle, inputStyle, primaryBtnStyle } from "./settings-styles";

export function StreamConfigTab({ theme }: { theme: SettingsTheme }) {
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState<{ type: "success" | "error"; text: string } | null>(null);

  // 流代理配置
  const [configId, setConfigId] = useState<number | null>(null);
  const [enabled, setEnabled] = useState(false);
  const [bufferSize, setBufferSize] = useState(20);
  const [generalWorkers, setGeneralWorkers] = useState(5);
  const [maxWorkers, setMaxWorkers] = useState(8);
  const [autoSave, setAutoSave] = useState(false);
  const [maxDiskCacheMB, setMaxDiskCacheMB] = useState(10240);

  const fetchConfig = async () => {
    setLoading(true);
    try {
      const list = await configApi.getConfigList({ group: "stream" });
      if (list && list.length > 0) {
        const cfg = list.find((item) => item.config_key === "stream_config");
        if (cfg) {
          setConfigId(cfg.id);
          setEnabled(cfg.value5 === "1" || cfg.value5 === "true");
          setBufferSize(parseInt(cfg.value1 || "20", 10) || 20);
          setGeneralWorkers(parseInt(cfg.value2 || "5", 10) || 5);
          setMaxWorkers(parseInt(cfg.value3 || "8", 10) || 8);
          setAutoSave(cfg.value4 === "1" || cfg.value4 === "true");
          setMaxDiskCacheMB(parseInt(cfg.value6 || "10240", 10) || 10240);
        }
      }
    } catch {
      setMessage({ type: "error", text: "获取流代理配置失败" });
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { fetchConfig(); }, []);

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    if (configId === null) {
      setMessage({ type: "error", text: "配置不存在，请先在数据库中初始化 stream_config" });
      return;
    }
    setSaving(true);
    setMessage(null);
    try {
      await configApi.updateConfig({
        config_key: "stream_config",
        value1: bufferSize.toString(),
        value2: generalWorkers.toString(),
        value3: maxWorkers.toString(),
        value4: autoSave ? "true" : "false",
        value5: enabled ? "true" : "false",
        value6: maxDiskCacheMB.toString(),
      });
      setMessage({ type: "success", text: "流代理配置已保存" });
      await fetchConfig();
    } catch {
      setMessage({ type: "error", text: "保存失败" });
    } finally {
      setSaving(false);
    }
  };

  // 通用输入行
  const inputRow = (label: string, value: number, onChange: (v: number) => void) => (
    <div className="flex items-center gap-3 py-2">
      <label className="w-40 shrink-0 text-xs" style={labelStyle}>{label}</label>
      <input
        type="number"
        value={value}
        onChange={e => onChange(parseInt(e.target.value, 10) || 0)}
        className="flex-1 px-3 py-2 rounded-xl text-sm outline-none"
        style={inputStyle}
        min={1}
      />
    </div>
  );

  // 通用开关行
  const switchRow = (label: string, checked: boolean, onChange: (v: boolean) => void) => (
    <div className="flex items-center gap-3 py-2">
      <label className="w-40 shrink-0 text-xs" style={labelStyle}>{label}</label>
      {checked ? (
        <ToggleRight size={28} style={{ color: theme.from, cursor: "pointer" }} onClick={() => onChange(false)} />
      ) : (
        <ToggleLeft size={28} style={{ color: "var(--text-tertiary)", cursor: "pointer" }} onClick={() => onChange(true)} />
      )}
    </div>
  );

  return (
    <div className="space-y-6">
      {loading ? (
        <div className="flex items-center justify-center py-12">
          <RefreshCw size={24} className="animate-spin" style={{ color: theme.from }} />
        </div>
      ) : (
        <form onSubmit={handleSave}>
          <div className="rounded-2xl p-6 space-y-1" style={cardStyle}>
            <h3 className="mb-4" style={sectionTitleStyle}>远程流代理配置</h3>

            {/* 说明 */}
            <div className="mb-4 p-3 rounded-xl text-xs" style={{ background: "var(--bg-elevated)", color: "var(--text-secondary)" }}>
              启用后，播放 m3u8 视频时将通过后端流代理服务器进行转发，支持并行下载和缓冲控制。
            </div>

            {/* 启用开关 */}
            {switchRow("启用远程代理", enabled, setEnabled)}

            {/* 分隔线 */}
            <div className="border-t border-solid my-3" style={{ borderColor: "var(--border-strong)" }} />

            {/* 前瞻窗口大小 */}
            {inputRow("前瞻窗口大小", bufferSize, setBufferSize)}

            {/* 通用协程数 */}
            {inputRow("通用协程数", generalWorkers, setGeneralWorkers)}

            {/* 总协程上限 */}
            {inputRow("总协程上限", maxWorkers, setMaxWorkers)}

            {/* 自动保存 */}
            {switchRow("自动保存进度", autoSave, setAutoSave)}

            {/* 磁盘缓存上限 */}
            {inputRow("磁盘缓存上限(MB)", maxDiskCacheMB, setMaxDiskCacheMB)}
            <div className="px-1 pb-1 text-xs" style={{ color: "var(--text-tertiary)" }}>
              0 表示不限制，默认 10240（10GB）
            </div>
          </div>

          {/* 消息提示 */}
          {message && (
            <div
              className="mt-4 px-4 py-3 rounded-xl text-sm"
              style={{
                background: message.type === "success" ? "rgba(74,222,128,0.1)" : "rgba(255,85,85,0.1)",
                color: message.type === "success" ? "#4ade80" : "#ff5555",
              }}
            >
              {message.text}
            </div>
          )}

          {/* 保存按钮 */}
          <div className="flex justify-end pt-4">
            <button
              type="submit"
              disabled={saving}
              className="px-6 py-2.5 rounded-xl text-sm"
              style={primaryBtnStyle(theme, saving)}
            >
              {saving ? "保存中…" : "保存配置"}
            </button>
          </div>
        </form>
      )}
    </div>
  );
}
