import { useEffect, useState } from "react";
import { RefreshCw, ToggleLeft, ToggleRight, Zap } from "lucide-react";
import * as configApi from "@/api/config";
import { ApiError } from "@/api/client";
import type { SysConfigItem } from "@/types/api";
import type { SettingsTheme } from "./settings-styles";
import { cardStyle, sectionTitleStyle, labelStyle, inputStyle, primaryBtnStyle } from "./settings-styles";

export function DoubanConfigTab({ theme }: { theme: SettingsTheme }) {
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState<string | null>(null);
  const [message, setMessage] = useState<{ type: "success" | "error"; text: string } | null>(null);

  // 存储 9 条配置，按 config_key 索引
  const [configs, setConfigs] = useState<Record<string, SysConfigItem>>({});

  const fetchConfig = async () => {
    setLoading(true);
    try {
      const list = await configApi.getConfigList({ group: "douban" });
      const map: Record<string, SysConfigItem> = {};
      for (const cfg of list || []) {
        map[cfg.config_key] = cfg;
      }
      setConfigs(map);
    } catch {
      setMessage({ type: "error", text: "获取豆瓣配置失败" });
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { fetchConfig(); }, []);

  const updateValue = (key: string, field: keyof SysConfigItem, value: string | boolean) => {
    setConfigs(prev => ({
      ...prev,
      [key]: { ...prev[key], [field]: value },
    }));
  };

  const saveConfig = async (key: string) => {
    setSaving(key);
    setMessage(null);
    try {
      const cfg = configs[key];
      await configApi.updateConfig({
        config_key: key,
        value1: cfg.value1,
        value2: cfg.value2,
        value3: cfg.value3,
        value4: cfg.value4,
        value5: cfg.value5,
        is_enabled: cfg.is_enabled,
      });
      setMessage({ type: "success", text: `${cfg.title} 已保存` });
      await fetchConfig();
    } catch {
      setMessage({ type: "error", text: "保存失败" });
    } finally {
      setSaving(null);
    }
  };

  const saveAll = async () => {
    for (const key of Object.keys(configs)) {
      await saveConfig(key);
    }
  };

  // 通用输入行
  const inputRow = (label: string, value: string, onChange: (v: string) => void, type: "text" | "number" = "text") => (
    <div className="flex items-center gap-3 py-2">
      <label className="w-40 shrink-0 text-xs" style={labelStyle}>{label}</label>
      <input
        type={type}
        value={value}
        onChange={e => onChange(e.target.value)}
        className="flex-1 px-3 py-2 rounded-xl text-sm outline-none"
        style={inputStyle}
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

  // 选择行
  const selectRow = (label: string, value: string, options: { value: string; label: string }[], onChange: (v: string) => void) => (
    <div className="flex items-center gap-3 py-2">
      <label className="w-40 shrink-0 text-xs" style={labelStyle}>{label}</label>
      <select
        value={value}
        onChange={e => onChange(e.target.value)}
        className="flex-1 px-3 py-2 rounded-xl text-sm outline-none"
        style={inputStyle}
      >
        {options.map(opt => <option key={opt.value} value={opt.value}>{opt.label}</option>)}
      </select>
    </div>
  );

  // 文本域行
  const textareaRow = (label: string, value: string, onChange: (v: string) => void) => (
    <div className="flex items-start gap-3 py-2">
      <label className="w-40 shrink-0 text-xs pt-2" style={labelStyle}>{label}</label>
      <textarea
        value={value}
        onChange={e => onChange(e.target.value)}
        rows={3}
        className="flex-1 px-3 py-2 rounded-xl text-sm outline-none resize-y"
        style={inputStyle}
      />
    </div>
  );

  if (loading) {
    return <div className="text-center py-12" style={{ color: "var(--text-secondary)" }}>加载中…</div>;
  }

  return (
    <div className="space-y-6">
      {/* 消息提示 */}
      {message && (
        <div className="px-4 py-2 rounded-xl text-sm" style={{
          background: message.type === "success" ? "rgba(52,211,153,0.1)" : "rgba(255,85,85,0.1)",
          color: message.type === "success" ? "#34d399" : "#ff5555",
        }}>
          {message.text}
        </div>
      )}

      {/* 操作栏 */}
      <div className="flex items-center gap-3">
        <button onClick={fetchConfig} className="flex items-center gap-1 text-xs px-3 py-2 rounded-xl" style={{ color: theme.from, fontFamily: "var(--font-display)", background: "var(--bg-elevated)", border: "1px solid var(--border-strong)" }}>
          <RefreshCw size={12} /> 刷新
        </button>
        <button onClick={saveAll} className="flex items-center gap-1 text-xs px-3 py-2 rounded-xl" style={primaryBtnStyle(theme)}>
          <Zap size={12} /> 全部保存
        </button>
      </div>

      {/* JSON数据通道 */}
      {configs["douban_json_channel"] && (() => {
        const cfg = configs["douban_json_channel"];
        return (
          <div className="rounded-2xl p-6" style={cardStyle}>
            <h2 style={sectionTitleStyle}>{cfg.title}</h2>
            <div className="space-y-1">
              {inputRow(cfg.title1, cfg.value1, v => updateValue("douban_json_channel", "value1", v))}
              {inputRow(cfg.title2, cfg.value2, v => updateValue("douban_json_channel", "value2", v))}
              {selectRow(cfg.title3, cfg.value3, [
                { value: "1", label: "直连" },
                { value: "2", label: "CORS代理" },
              ], v => updateValue("douban_json_channel", "value3", v))}
              {inputRow(cfg.title4, cfg.value4, v => updateValue("douban_json_channel", "value4", v), "number")}
              {inputRow(cfg.title5, cfg.value5, v => updateValue("douban_json_channel", "value5", v), "number")}
            </div>
            <div className="flex justify-end pt-3">
              <button onClick={() => saveConfig("douban_json_channel")} disabled={saving === "douban_json_channel"} className="px-5 py-2 rounded-xl text-sm" style={primaryBtnStyle(theme, saving === "douban_json_channel")}>
                {saving === "douban_json_channel" ? "保存中…" : "保存"}
              </button>
            </div>
          </div>
        );
      })()}

      {/* 图片分流节点 */}
      {["douban_image_node_img1", "douban_image_node_img2", "douban_image_node_img3", "douban_image_node_img9"].map(key =>
        configs[key] ? (() => {
          const cfg = configs[key];
          const nodeKey = key.replace("douban_image_node_", "");
          return (
            <div key={key} className="rounded-2xl p-6" style={cardStyle}>
              <div className="flex items-center justify-between mb-3">
                <h2 style={sectionTitleStyle}>{cfg.title}</h2>
                <span className="text-xs px-2 py-1 rounded-lg" style={{ background: theme.subtle, color: theme.from, fontFamily: "var(--font-display)" }}>
                  {nodeKey}
                </span>
              </div>
              <div className="space-y-1">
                {inputRow(cfg.title1 || "节点前缀", cfg.value1, v => updateValue(key, "value1", v))}
                {inputRow(cfg.title2 || "优先级", cfg.value2, v => updateValue(key, "value2", v), "number")}
                <div className="flex items-center gap-3 py-2">
                  <label className="w-40 shrink-0 text-xs" style={labelStyle}>{cfg.title3 || "用途说明"}</label>
                  <span className="text-sm" style={{ color: "var(--text-tertiary)" }}>{cfg.value3}</span>
                </div>
                {switchRow(cfg.title4 || "启用", cfg.value4 === "true", v => updateValue(key, "value4", v.toString()))}
              </div>
              <div className="flex justify-end pt-3">
                <button onClick={() => saveConfig(key)} disabled={saving === key} className="px-5 py-2 rounded-xl text-sm" style={primaryBtnStyle(theme, saving === key)}>
                  {saving === key ? "保存中…" : "保存"}
                </button>
              </div>
            </div>
          );
        })() : null
      )}

      {/* 图片代理配置 */}
      {configs["douban_image_proxy"] && (() => {
        const cfg = configs["douban_image_proxy"];
        return (
          <div className="rounded-2xl p-6" style={cardStyle}>
            <h2 style={sectionTitleStyle}>{cfg.title}</h2>
            <div className="space-y-1">
              {switchRow(cfg.title1, cfg.value1 === "true", v => updateValue("douban_image_proxy", "value1", v.toString()))}
              {inputRow(cfg.title2, cfg.value2, v => updateValue("douban_image_proxy", "value2", v))}
              {inputRow(cfg.title3, cfg.value3, v => updateValue("douban_image_proxy", "value3", v), "number")}
              {inputRow(cfg.title4, cfg.value4, v => updateValue("douban_image_proxy", "value4", v), "number")}
              {textareaRow(cfg.title5, cfg.value5, v => updateValue("douban_image_proxy", "value5", v))}
            </div>
            <div className="flex justify-end pt-3">
              <button onClick={() => saveConfig("douban_image_proxy")} disabled={saving === "douban_image_proxy"} className="px-5 py-2 rounded-xl text-sm" style={primaryBtnStyle(theme, saving === "douban_image_proxy")}>
                {saving === "douban_image_proxy" ? "保存中…" : "保存"}
              </button>
            </div>
          </div>
        );
      })()}

      {/* 请求限流 */}
      {configs["douban_rate_limit"] && (() => {
        const cfg = configs["douban_rate_limit"];
        return (
          <div className="rounded-2xl p-6" style={cardStyle}>
            <h2 style={sectionTitleStyle}>{cfg.title}</h2>
            <div className="space-y-1">
              {inputRow(cfg.title1, cfg.value1, v => updateValue("douban_rate_limit", "value1", v), "number")}
              {inputRow(cfg.title2, cfg.value2, v => updateValue("douban_rate_limit", "value2", v), "number")}
            </div>
            <div className="flex justify-end pt-3">
              <button onClick={() => saveConfig("douban_rate_limit")} disabled={saving === "douban_rate_limit"} className="px-5 py-2 rounded-xl text-sm" style={primaryBtnStyle(theme, saving === "douban_rate_limit")}>
                {saving === "douban_rate_limit" ? "保存中…" : "保存"}
              </button>
            </div>
          </div>
        );
      })()}

      {/* 数据缓存 */}
      {configs["douban_cache"] && (() => {
        const cfg = configs["douban_cache"];
        return (
          <div className="rounded-2xl p-6" style={cardStyle}>
            <h2 style={sectionTitleStyle}>{cfg.title}</h2>
            <div className="space-y-1">
              {inputRow(cfg.title1, cfg.value1, v => updateValue("douban_cache", "value1", v), "number")}
              {switchRow(cfg.title2, cfg.value2 === "true", v => updateValue("douban_cache", "value2", v.toString()))}
            </div>
            <div className="flex justify-end pt-3">
              <button onClick={() => saveConfig("douban_cache")} disabled={saving === "douban_cache"} className="px-5 py-2 rounded-xl text-sm" style={primaryBtnStyle(theme, saving === "douban_cache")}>
                {saving === "douban_cache" ? "保存中…" : "保存"}
              </button>
            </div>
          </div>
        );
      })()}

      {/* 榜单同步配置 */}
      {configs["douban_rank_sync"] && (() => {
        const cfg = configs["douban_rank_sync"];
        return (
          <div className="rounded-2xl p-6" style={cardStyle}>
            <h2 style={sectionTitleStyle}>{cfg.title}</h2>
            <div className="space-y-1">
              {switchRow(cfg.title1, cfg.value1 === "true", v => updateValue("douban_rank_sync", "value1", v.toString()))}
              {inputRow(cfg.title2, cfg.value2, v => updateValue("douban_rank_sync", "value2", v))}
              {inputRow(cfg.title3, cfg.value3, v => updateValue("douban_rank_sync", "value3", v), "number")}
              {inputRow(cfg.title4, cfg.value4, v => updateValue("douban_rank_sync", "value4", v), "number")}
              {inputRow(cfg.title5, cfg.value5, v => updateValue("douban_rank_sync", "value5", v), "number")}
            </div>
            <div className="flex justify-end pt-3">
              <button onClick={() => saveConfig("douban_rank_sync")} disabled={saving === "douban_rank_sync"} className="px-5 py-2 rounded-xl text-sm" style={primaryBtnStyle(theme, saving === "douban_rank_sync")}>
                {saving === "douban_rank_sync" ? "保存中…" : "保存"}
              </button>
            </div>
          </div>
        );
      })()}
    </div>
  );
}
