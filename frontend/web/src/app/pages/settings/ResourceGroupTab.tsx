import { useEffect, useState } from "react";
import { RefreshCw, Plus, Trash2, Edit2, Check, X, ToggleLeft, ToggleRight } from "lucide-react";
import * as configApi from "@/api/config";
import { ApiError } from "@/api/client";
import type { SysConfigItem } from "@/types/api";
import type { SettingsTheme } from "./settings-styles";
import { cardStyle, sectionTitleStyle, labelStyle, inputStyle, primaryBtnStyle, ghostBtnStyle, dangerBtnStyle } from "./settings-styles";

export function ResourceGroupTab({ theme }: { theme: SettingsTheme }) {
  const [items, setItems] = useState<SysConfigItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [message, setMessage] = useState<{ type: "success" | "error"; text: string } | null>(null);

  // 创建表单
  const [showCreate, setShowCreate] = useState(false);
  const [newDomain, setNewDomain] = useState("");
  const [newName, setNewName] = useState("");
  const [newApi, setNewApi] = useState("");
  const [newDetail, setNewDetail] = useState("");
  const [newComment, setNewComment] = useState("");
  const [creating, setCreating] = useState(false);

  // 编辑
  const [editingKey, setEditingKey] = useState<string | null>(null);
  const [editName, setEditName] = useState("");
  const [editApi, setEditApi] = useState("");
  const [editDetail, setEditDetail] = useState("");
  const [editComment, setEditComment] = useState("");
  const [saving, setSaving] = useState(false);

  const fetchList = async () => {
    setLoading(true);
    try {
      const data = await configApi.getConfigList({ group: "resource_site" });
      setItems(data || []);
    } catch {
      // 静默
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { fetchList(); }, []);

  const handleCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    setCreating(true);
    setMessage(null);
    try {
      await configApi.createConfig({
        config_key: newDomain,
        config_group: "resource_site",
        title: newName,
        title1: "API地址",
        value1: newApi,
        title2: "详情地址",
        value2: newDetail,
        title3: "备注",
        value3: newComment,
        is_enabled: true,
      });
      setMessage({ type: "success", text: "资源站点创建成功" });
      setNewDomain(""); setNewName(""); setNewApi(""); setNewDetail(""); setNewComment("");
      setShowCreate(false);
      await fetchList();
    } catch (err) {
      setMessage({ type: "error", text: err instanceof ApiError ? err.message : "创建失败" });
    } finally {
      setCreating(false);
    }
  };

  const handleEdit = (item: SysConfigItem) => {
    setEditingKey(item.config_key);
    setEditName(item.title);
    setEditApi(item.value1);
    setEditDetail(item.value2);
    setEditComment(item.value3);
  };

  const handleSaveEdit = async () => {
    if (editingKey === null) return;
    setSaving(true);
    setMessage(null);
    try {
      await configApi.updateConfig({
        config_key: editingKey,
        title: editName || undefined,
        value1: editApi || undefined,
        value2: editDetail || undefined,
        value3: editComment || undefined,
      });
      setMessage({ type: "success", text: "资源站点已更新" });
      setEditingKey(null);
      await fetchList();
    } catch (err) {
      setMessage({ type: "error", text: err instanceof ApiError ? err.message : "更新失败" });
    } finally {
      setSaving(false);
    }
  };

  const handleToggleEnabled = async (item: SysConfigItem) => {
    setMessage(null);
    try {
      await configApi.updateConfig({
        config_key: item.config_key,
        is_enabled: !item.is_enabled,
      });
      setMessage({ type: "success", text: item.is_enabled ? "已禁用" : "已启用" });
      await fetchList();
    } catch (err) {
      setMessage({ type: "error", text: err instanceof ApiError ? err.message : "操作失败" });
    }
  };

  const handleDelete = async (id: number) => {
    try {
      await configApi.deleteConfig({ id });
      setMessage({ type: "success", text: "资源站点已删除" });
      await fetchList();
    } catch (err) {
      setMessage({ type: "error", text: err instanceof ApiError ? err.message : "删除失败" });
    }
  };

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <div />
        <div className="flex items-center gap-3">
          <button onClick={fetchList} className="flex items-center gap-1 text-xs px-3 py-2 rounded-xl" style={{ color: theme.from, fontFamily: "var(--font-display)", background: "var(--bg-elevated)", border: "1px solid var(--border-strong)" }}>
            <RefreshCw size={12} /> 刷新
          </button>
          <button onClick={() => setShowCreate(!showCreate)} className="flex items-center gap-1 text-xs px-4 py-2 rounded-xl hover:scale-105 transition-all duration-200" style={primaryBtnStyle(theme)}>
            <Plus size={12} /> 添加站点
          </button>
        </div>
      </div>

      {message && <p className="text-xs mb-4" style={{ color: message.type === "success" ? "#34d399" : "#ff5555" }}>{message.text}</p>}

      {/* 创建表单 */}
      {showCreate && (
        <div className="rounded-2xl p-6 mb-6" style={{ ...cardStyle, border: `1px solid ${theme.glow}` }}>
          <h2 className="mb-4" style={sectionTitleStyle}>添加资源站点</h2>
          <form onSubmit={handleCreate} className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div className="flex flex-col gap-1.5">
                <label style={labelStyle}>域名（唯一标识）</label>
                <input value={newDomain} onChange={e => setNewDomain(e.target.value)} className="px-4 py-2.5 rounded-xl text-sm outline-none" style={inputStyle} required placeholder="example.com" />
              </div>
              <div className="flex flex-col gap-1.5">
                <label style={labelStyle}>名称</label>
                <input value={newName} onChange={e => setNewName(e.target.value)} className="px-4 py-2.5 rounded-xl text-sm outline-none" style={inputStyle} required />
              </div>
              <div className="flex flex-col gap-1.5">
                <label style={labelStyle}>API 地址</label>
                <input value={newApi} onChange={e => setNewApi(e.target.value)} className="px-4 py-2.5 rounded-xl text-sm outline-none" style={inputStyle} required placeholder="https://..." />
              </div>
              <div className="flex flex-col gap-1.5">
                <label style={labelStyle}>详情地址</label>
                <input value={newDetail} onChange={e => setNewDetail(e.target.value)} className="px-4 py-2.5 rounded-xl text-sm outline-none" style={inputStyle} placeholder="https://..." />
              </div>
              <div className="col-span-2 flex flex-col gap-1.5">
                <label style={labelStyle}>备注</label>
                <input value={newComment} onChange={e => setNewComment(e.target.value)} className="px-4 py-2.5 rounded-xl text-sm outline-none" style={inputStyle} />
              </div>
            </div>
            <div className="flex justify-end gap-3">
              <button type="button" onClick={() => setShowCreate(false)} className="px-4 py-2 rounded-xl text-sm" style={ghostBtnStyle}>取消</button>
              <button type="submit" disabled={creating} className="px-5 py-2 rounded-xl text-sm hover:scale-105 transition-all duration-200" style={primaryBtnStyle(theme, creating)}>
                {creating ? "创建中…" : "创建"}
              </button>
            </div>
          </form>
        </div>
      )}

      {/* 列表 */}
      <div className="rounded-2xl overflow-hidden" style={cardStyle}>
        <div className="grid grid-cols-6 gap-4 px-6 py-3 text-xs" style={{ color: "var(--text-secondary)", fontFamily: "var(--font-display)", fontWeight: 600, letterSpacing: "0.06em", borderBottom: "1px solid var(--border-default)" }}>
          <span>域名</span><span>名称</span><span>API</span><span>状态</span><span>备注</span><span className="text-right">操作</span>
        </div>
        {loading ? (
          <div className="px-6 py-8 text-center text-sm" style={{ color: "var(--text-secondary)" }}>加载中…</div>
        ) : items.length === 0 ? (
          <div className="px-6 py-8 text-center text-sm" style={{ color: "var(--text-secondary)" }}>暂无资源站点</div>
        ) : items.map(item => (
          <div key={item.id} className="grid grid-cols-6 gap-4 px-6 py-4 items-center text-sm" style={{ borderBottom: "1px solid var(--border-subtle)" }}>
            {editingKey === item.config_key ? (
              <>
                <span style={{ color: theme.from, fontFamily: "var(--font-display)", fontWeight: 600, fontSize: "0.75rem" }} title={item.config_key}>{item.config_key}</span>
                <input value={editName} onChange={e => setEditName(e.target.value)} className="px-2 py-1 rounded-lg text-sm outline-none" style={inputStyle} />
                <input value={editApi} onChange={e => setEditApi(e.target.value)} className="px-2 py-1 rounded-lg text-sm outline-none" style={inputStyle} />
                <span style={{ color: item.is_enabled ? "#34d399" : "var(--text-secondary)" }}>{item.is_enabled ? "启用" : "禁用"}</span>
                <input value={editComment} onChange={e => setEditComment(e.target.value)} className="px-2 py-1 rounded-lg text-sm outline-none" style={inputStyle} />
              </>
            ) : (
              <>
                <span style={{ color: theme.from, fontFamily: "var(--font-display)", fontWeight: 600, fontSize: "0.75rem" }} title={item.config_key}>{item.config_key}</span>
                <span style={{ color: "var(--text-primary)" }}>{item.title || "—"}</span>
                <span className="truncate" style={{ color: "var(--text-secondary)" }} title={item.value1}>{item.value1 || "—"}</span>
                <button onClick={() => handleToggleEnabled(item)} className="flex items-center gap-1 text-xs" style={{ color: item.is_enabled ? "#34d399" : "var(--text-secondary)" }}>
                  {item.is_enabled ? <ToggleRight size={14} /> : <ToggleLeft size={14} />}
                  {item.is_enabled ? "启用" : "禁用"}
                </button>
                <span className="truncate" style={{ color: "var(--text-secondary)" }} title={item.value3}>{item.value3 || "—"}</span>
              </>
            )}
            <div className="flex items-center justify-end gap-2">
              {editingKey === item.config_key ? (
                <>
                  <button onClick={handleSaveEdit} disabled={saving} className="flex items-center gap-1 text-xs px-2 py-1 rounded-lg" style={{ color: "#34d399", background: "rgba(52,211,153,0.08)" }}>
                    <Check size={11} /> 保存
                  </button>
                  <button onClick={() => setEditingKey(null)} className="flex items-center gap-1 text-xs px-2 py-1 rounded-lg" style={ghostBtnStyle}>
                    <X size={11} /> 取消
                  </button>
                </>
              ) : (
                <>
                  <button onClick={() => handleEdit(item)} className="flex items-center gap-1 text-xs px-2 py-1 rounded-lg" style={{ color: theme.from, background: "var(--bg-elevated)" }}>
                    <Edit2 size={11} /> 编辑
                  </button>
                  <button onClick={() => handleDelete(item.id)} className="flex items-center gap-1 text-xs px-2 py-1 rounded-lg" style={dangerBtnStyle}>
                    <Trash2 size={11} /> 删除
                  </button>
                </>
              )}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
