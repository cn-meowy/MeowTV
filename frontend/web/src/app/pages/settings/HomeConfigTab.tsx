import { useEffect, useState } from "react";
import { RefreshCw } from "lucide-react";
import * as configApi from "@/api/config";
import type { SettingsTheme } from "./settings-styles";
import { cardStyle, sectionTitleStyle, labelStyle, inputStyle, primaryBtnStyle } from "./settings-styles";

export function HomeConfigTab({ theme }: { theme: SettingsTheme }) {
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState<{ type: "success" | "error"; text: string } | null>(null);

  // 首页区块标题配置
  const [configId, setConfigId] = useState<number | null>(null);
  const [sectionTitle1, setSectionTitle1] = useState("最近添加");
  const [sectionTitle2, setSectionTitle2] = useState("可能喜欢");

  const fetchConfig = async () => {
    setLoading(true);
    try {
      const list = await configApi.getConfigList({ group: "home" });
      if (list && list.length > 0) {
        const cfg = list.find((item) => item.config_key === "home_section_titles");
        if (cfg) {
          setConfigId(cfg.id);
          setSectionTitle1(cfg.value1?.trim() || "最近添加");
          setSectionTitle2(cfg.value2?.trim() || "可能喜欢");
        }
      }
    } catch {
      setMessage({ type: "error", text: "获取首页区块标题配置失败" });
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { fetchConfig(); }, []);

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    if (configId === null) {
      setMessage({ type: "error", text: "配置不存在，请先在数据库中初始化 home_section_titles" });
      return;
    }
    setSaving(true);
    setMessage(null);
    try {
      await configApi.updateConfig({
        config_key: "home_section_titles",
        value1: sectionTitle1.trim() || "最近添加",
        value2: sectionTitle2.trim() || "可能喜欢",
      });
      setMessage({ type: "success", text: "首页区块标题已保存" });
      await fetchConfig();
    } catch {
      setMessage({ type: "error", text: "保存失败" });
    } finally {
      setSaving(false);
    }
  };

  // 文本输入行
  const textInputRow = (label: string, value: string, onChange: (v: string) => void) => (
    <div className="flex items-center gap-3 py-2">
      <label className="w-40 shrink-0 text-xs" style={labelStyle}>{label}</label>
      <input
        type="text"
        value={value}
        onChange={e => onChange(e.target.value)}
        className="flex-1 px-3 py-2 rounded-xl text-sm outline-none"
        style={inputStyle}
        placeholder={label}
      />
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
            <h3 className="mb-4" style={sectionTitleStyle}>首页区块标题配置</h3>

            {/* 说明 */}
            <div className="mb-4 p-3 rounded-xl text-xs" style={{ background: "var(--bg-elevated)", color: "var(--text-secondary)" }}>
              配置首页两个内容区块的标题文字。区块一对应电影列表，区块二对应剧集列表。留空将使用默认值"最近添加"/"可能喜欢"。
            </div>

            {/* 分隔线 */}
            <div className="border-t border-solid my-3" style={{ borderColor: "var(--border-strong)" }} />

            {/* 区块一标题 */}
            {textInputRow("区块一标题", sectionTitle1, setSectionTitle1)}

            {/* 区块二标题 */}
            {textInputRow("区块二标题", sectionTitle2, setSectionTitle2)}
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
