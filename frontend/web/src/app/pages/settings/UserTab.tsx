import { useEffect, useState, useCallback, useRef } from "react";
import { RefreshCw, Plus, Trash2, Edit2, Check, X, KeyRound, Shield, Settings2, Users } from "lucide-react";
import * as adminApi from "@/api/admin";
import * as configApi from "@/api/config";
import * as userGroupApi from "@/api/user-group";
import { ApiError } from "@/api/client";
import type { UserListItem, SysConfigItem, UserGroupItem } from "@/types/api";
import type { SettingsTheme } from "./settings-styles";
import { cardStyle, sectionTitleStyle, labelStyle, inputStyle, primaryBtnStyle, ghostBtnStyle, dangerBtnStyle } from "./settings-styles";

export function UserTab({ theme }: { theme: SettingsTheme }) {
  const [subTab, setSubTab] = useState<"groups" | "users">("users");

  return (
    <div>
      {/* 子 Tab 切换 */}
      <div className="flex gap-2 mb-6">
        <button
          onClick={() => setSubTab("users")}
          className="flex items-center gap-2 px-4 py-2 rounded-xl text-sm transition-all duration-200"
          style={{
            background: subTab === "users" ? theme.subtle : "var(--bg-elevated)",
            color: subTab === "users" ? theme.from : "var(--text-secondary)",
            fontFamily: "var(--font-display)",
            fontWeight: subTab === "users" ? 600 : 400,
            border: `1px solid ${subTab === "users" ? theme.glow : "var(--border-strong)"}`,
          }}
        >
          <Users size={14} /> 用户管理
        </button>
        <button
          onClick={() => setSubTab("groups")}
          className="flex items-center gap-2 px-4 py-2 rounded-xl text-sm transition-all duration-200"
          style={{
            background: subTab === "groups" ? theme.subtle : "var(--bg-elevated)",
            color: subTab === "groups" ? theme.from : "var(--text-secondary)",
            fontFamily: "var(--font-display)",
            fontWeight: subTab === "groups" ? 600 : 400,
            border: `1px solid ${subTab === "groups" ? theme.glow : "var(--border-strong)"}`,
          }}
        >
          <Shield size={14} /> 用户组管理
        </button>
      </div>

      {subTab === "users" && <UserListSubTab theme={theme} />}
      {subTab === "groups" && <UserGroupSubTab theme={theme} />}
    </div>
  );
}

// ── 用户列表子 Tab ────────────────────────────────────────────────────
function UserListSubTab({ theme }: { theme: SettingsTheme }) {
  const [users, setUsers] = useState<UserListItem[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [loading, setLoading] = useState(true);
  const [message, setMessage] = useState<{ type: "success" | "error"; text: string } | null>(null);

  // 用户组下拉数据源
  const [groups, setGroups] = useState<UserGroupItem[]>([]);

  const [showCreate, setShowCreate] = useState(false);
  const [newUsername, setNewUsername] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [newNickname, setNewNickname] = useState("");
  const [newRole, setNewRole] = useState(0);
  const [newGroupId, setNewGroupId] = useState<number | null>(null);
  const [creating, setCreating] = useState(false);

  // 编辑用户
  const [editingUser, setEditingUser] = useState<UserListItem | null>(null);
  const [editNickname, setEditNickname] = useState("");
  const [editRole, setEditRole] = useState(0);
  const [editStatus, setEditStatus] = useState(1);
  const [editGroupId, setEditGroupId] = useState<number | null>(null);
  const [originalGroupId, setOriginalGroupId] = useState<number | null>(null);
  const [saving, setSaving] = useState(false);

  const pageSize = 10;

  const fetchUsers = async () => {
    setLoading(true);
    try {
      const data = await adminApi.getUserList({ page, size: pageSize });
      setUsers(data.items || []);
      setTotal(data.total || 0);
    } catch {
      // 静默
    } finally {
      setLoading(false);
    }
  };

  // 一次性加载用户组列表（size 取较大值）
  useEffect(() => {
    (async () => {
      try {
        const data = await userGroupApi.getUserGroupList({ page: 1, size: 100 });
        setGroups(data.items || []);
      } catch {
        // 静默
      }
    })();
  }, []);

  useEffect(() => { fetchUsers(); }, [page]);

  const handleCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    setCreating(true);
    setMessage(null);
    try {
      const resp = await adminApi.createUser({ username: newUsername, password: newPassword, nickname: newNickname || undefined, role: newRole });
      if (newGroupId != null) {
        try {
          await userGroupApi.setUserGroup({ user_id: resp.id, group_id: newGroupId });
        } catch (err) {
          setMessage({ type: "error", text: `用户已创建，但用户组设置失败：${err instanceof ApiError ? err.message : "未知错误"}` });
          setNewUsername(""); setNewPassword(""); setNewNickname(""); setNewRole(0); setNewGroupId(null);
          setShowCreate(false);
          await fetchUsers();
          return;
        }
      }
      setMessage({ type: "success", text: "用户创建成功" });
      setNewUsername(""); setNewPassword(""); setNewNickname(""); setNewRole(0); setNewGroupId(null);
      setShowCreate(false);
      await fetchUsers();
    } catch (err) {
      setMessage({ type: "error", text: err instanceof ApiError ? err.message : "创建失败" });
    } finally {
      setCreating(false);
    }
  };

  const handleEdit = (u: UserListItem) => {
    setEditingUser(u);
    setEditNickname(u.nickname || "");
    setEditRole(u.role);
    setEditStatus(u.status);
    const gid = u.group_id ?? null;
    setEditGroupId(gid);
    setOriginalGroupId(gid);
  };

  const handleCancelEdit = () => {
    setEditingUser(null);
  };

  const handleSaveEdit = async () => {
    if (!editingUser) return;
    setSaving(true);
    setMessage(null);
    try {
      await adminApi.updateUser({ id: editingUser.id, nickname: editNickname, role: editRole, status: editStatus });
      if (editGroupId !== originalGroupId) {
        try {
          await userGroupApi.setUserGroup({ user_id: editingUser.id, group_id: editGroupId });
        } catch (err) {
          setMessage({ type: "error", text: `用户信息已更新，但用户组设置失败：${err instanceof ApiError ? err.message : "未知错误"}` });
          setEditingUser(null);
          await fetchUsers();
          return;
        }
      }
      setMessage({ type: "success", text: "用户已更新" });
      setEditingUser(null);
      await fetchUsers();
    } catch (err) {
      setMessage({ type: "error", text: err instanceof ApiError ? err.message : "更新失败" });
    } finally {
      setSaving(false);
    }
  };

  const handleResetPassword = async (id: number) => {
    try {
      await adminApi.resetPassword({ id, new_password: "123456" });
      setMessage({ type: "success", text: "密码已重置为 123456" });
    } catch (err) {
      setMessage({ type: "error", text: err instanceof ApiError ? err.message : "重置失败" });
    }
  };

  const handleDelete = async (id: number) => {
    try {
      await adminApi.deleteUser({ id });
      setMessage({ type: "success", text: "用户已删除" });
      await fetchUsers();
    } catch (err) {
      setMessage({ type: "error", text: err instanceof ApiError ? err.message : "删除失败" });
    }
  };

  const totalPages = Math.ceil(total / pageSize);

  // 用户组下拉选项（创建/编辑共用）
  const groupOptions = (
    <>
      <option value="">未分组</option>
      {groups.map(g => <option key={g.id} value={g.id}>{g.name}</option>)}
    </>
  );

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <div />
        <div className="flex items-center gap-3">
          <button onClick={fetchUsers} className="flex items-center gap-1 text-xs px-3 py-2 rounded-xl" style={{ color: theme.from, fontFamily: "var(--font-display)", background: "var(--bg-elevated)", border: "1px solid var(--border-strong)" }}>
            <RefreshCw size={12} /> 刷新
          </button>
          <button onClick={() => setShowCreate(!showCreate)} className="flex items-center gap-1 text-xs px-4 py-2 rounded-xl hover:scale-105 transition-all duration-200" style={primaryBtnStyle(theme)}>
            <Plus size={12} /> 创建用户
          </button>
        </div>
      </div>

      {message && <p className="text-xs mb-4" style={{ color: message.type === "success" ? "#34d399" : "#ff5555" }}>{message.text}</p>}

      {showCreate && (
        <div className="rounded-2xl p-6 mb-6" style={{ ...cardStyle, border: `1px solid ${theme.glow}` }}>
          <h2 className="mb-4" style={sectionTitleStyle}>创建新用户</h2>
          <form onSubmit={handleCreate} className="grid grid-cols-2 gap-4">
            <div className="flex flex-col gap-1.5">
              <label style={labelStyle}>用户名</label>
              <input value={newUsername} onChange={e => setNewUsername(e.target.value)} className="px-4 py-2.5 rounded-xl text-sm outline-none" style={inputStyle} required />
            </div>
            <div className="flex flex-col gap-1.5">
              <label style={labelStyle}>密码</label>
              <input type="password" value={newPassword} onChange={e => setNewPassword(e.target.value)} className="px-4 py-2.5 rounded-xl text-sm outline-none" style={inputStyle} required />
            </div>
            <div className="flex flex-col gap-1.5">
              <label style={labelStyle}>昵称</label>
              <input value={newNickname} onChange={e => setNewNickname(e.target.value)} className="px-4 py-2.5 rounded-xl text-sm outline-none" style={inputStyle} />
            </div>
            <div className="flex flex-col gap-1.5">
              <label style={labelStyle}>角色</label>
              <select value={newRole} onChange={e => setNewRole(Number(e.target.value))} className="px-4 py-2.5 rounded-xl text-sm outline-none" style={inputStyle}>
                <option value={0}>普通用户</option>
                <option value={1}>管理员</option>
              </select>
            </div>
            <div className="flex flex-col gap-1.5">
              <label style={labelStyle}>用户组</label>
              <select value={newGroupId ?? ""} onChange={e => setNewGroupId(e.target.value === "" ? null : Number(e.target.value))} className="px-4 py-2.5 rounded-xl text-sm outline-none" style={inputStyle}>
                {groupOptions}
              </select>
            </div>
            <div className="col-span-2 flex justify-end gap-3">
              <button type="button" onClick={() => setShowCreate(false)} className="px-4 py-2 rounded-xl text-sm" style={ghostBtnStyle}>取消</button>
              <button type="submit" disabled={creating} className="px-5 py-2 rounded-xl text-sm hover:scale-105 transition-all duration-200" style={primaryBtnStyle(theme, creating)}>
                {creating ? "创建中…" : "创建"}
              </button>
            </div>
          </form>
        </div>
      )}

      {editingUser && (
        <div className="rounded-2xl p-6 mb-6" style={{ ...cardStyle, border: `1px solid ${theme.glow}` }}>
          <h2 className="mb-4" style={sectionTitleStyle}>编辑用户 — #{editingUser.id} {editingUser.username}</h2>
          <div className="grid grid-cols-2 gap-4">
            <div className="flex flex-col gap-1.5">
              <label style={labelStyle}>昵称</label>
              <input value={editNickname} onChange={e => setEditNickname(e.target.value)} className="px-4 py-2.5 rounded-xl text-sm outline-none" style={inputStyle} />
            </div>
            <div className="flex flex-col gap-1.5">
              <label style={labelStyle}>角色</label>
              <select value={editRole} onChange={e => setEditRole(Number(e.target.value))} className="px-4 py-2.5 rounded-xl text-sm outline-none" style={inputStyle}>
                <option value={0}>普通用户</option>
                <option value={1}>管理员</option>
              </select>
            </div>
            <div className="flex flex-col gap-1.5">
              <label style={labelStyle}>状态</label>
              <select value={editStatus} onChange={e => setEditStatus(Number(e.target.value))} className="px-4 py-2.5 rounded-xl text-sm outline-none" style={inputStyle}>
                <option value={1}>正常</option>
                <option value={0}>禁用</option>
              </select>
            </div>
            <div className="flex flex-col gap-1.5">
              <label style={labelStyle}>用户组</label>
              <select value={editGroupId ?? ""} onChange={e => setEditGroupId(e.target.value === "" ? null : Number(e.target.value))} className="px-4 py-2.5 rounded-xl text-sm outline-none" style={inputStyle}>
                {groupOptions}
              </select>
            </div>
            <div className="col-span-2 flex justify-end gap-3">
              <button type="button" onClick={handleCancelEdit} className="px-4 py-2 rounded-xl text-sm" style={ghostBtnStyle}>取消</button>
              <button type="button" onClick={handleSaveEdit} disabled={saving} className="px-5 py-2 rounded-xl text-sm hover:scale-105 transition-all duration-200" style={primaryBtnStyle(theme, saving)}>
                {saving ? "保存中…" : "保存"}
              </button>
            </div>
          </div>
        </div>
      )}

      <div className="rounded-2xl overflow-hidden" style={cardStyle}>
        <div className="grid grid-cols-6 gap-4 px-6 py-3 text-xs" style={{ color: "var(--text-secondary)", fontFamily: "var(--font-display)", fontWeight: 600, letterSpacing: "0.06em", borderBottom: "1px solid var(--border-default)" }}>
          <span>UID</span><span>用户名</span><span>昵称</span><span>用户组</span><span>角色</span><span className="text-right">操作</span>
        </div>
        {loading ? (
          <div className="px-6 py-8 text-center text-sm" style={{ color: "var(--text-secondary)" }}>加载中…</div>
        ) : users.length === 0 ? (
          <div className="px-6 py-8 text-center text-sm" style={{ color: "var(--text-secondary)" }}>暂无用户</div>
        ) : users.map(u => (
          <div key={u.id} className="grid grid-cols-6 gap-4 px-6 py-4 items-center text-sm" style={{ borderBottom: "1px solid var(--border-subtle)" }}>
            <span style={{ color: theme.from, fontFamily: "var(--font-display)", fontWeight: 600 }}>#{u.id}</span>
            <span style={{ color: "var(--text-primary)" }}>{u.username}</span>
            <span style={{ color: "var(--text-secondary)" }}>{u.nickname || "—"}</span>
            <span style={{ color: "var(--text-secondary)" }}>{u.group_name || "—"}</span>
            <span className="flex items-center gap-1">
              <Shield size={12} style={{ color: u.role === 1 ? theme.from : "var(--text-secondary)" }} />
              <span style={{ color: u.role === 1 ? theme.from : "var(--text-secondary)" }}>{u.role === 1 ? "管理员" : "用户"}</span>
            </span>
            <div className="flex items-center justify-end gap-2">
              <button onClick={() => handleEdit(u)} className="flex items-center gap-1 text-xs px-2 py-1 rounded-lg" style={{ color: theme.from, background: "var(--bg-elevated)" }} title="编辑用户">
                <Edit2 size={11} /> 编辑
              </button>
              <button onClick={() => handleResetPassword(u.id)} className="flex items-center gap-1 text-xs px-2 py-1 rounded-lg" style={{ color: "var(--text-secondary)", background: "var(--bg-elevated)" }} title="重置密码为 123456">
                <KeyRound size={11} /> 重置
              </button>
              <button onClick={() => handleDelete(u.id)} className="flex items-center gap-1 text-xs px-2 py-1 rounded-lg" style={dangerBtnStyle}>
                <Trash2 size={11} /> 删除
              </button>
            </div>
          </div>
        ))}
        {totalPages > 1 && (
          <div className="flex items-center justify-center gap-2 px-6 py-4" style={{ borderTop: "1px solid var(--border-subtle)" }}>
            <button onClick={() => setPage(p => Math.max(1, p - 1))} disabled={page <= 1} className="px-3 py-1.5 rounded-lg text-xs disabled:opacity-40" style={{ color: theme.from, background: "var(--bg-elevated)", fontFamily: "var(--font-display)" }}>上一页</button>
            <span className="text-xs" style={{ color: "var(--text-secondary)", fontFamily: "var(--font-display)" }}>{page} / {totalPages}</span>
            <button onClick={() => setPage(p => Math.min(totalPages, p + 1))} disabled={page >= totalPages} className="px-3 py-1.5 rounded-lg text-xs disabled:opacity-40" style={{ color: theme.from, background: "var(--bg-elevated)", fontFamily: "var(--font-display)" }}>下一页</button>
          </div>
        )}
      </div>
    </div>
  );
}

// ── 用户组管理子 Tab ──────────────────────────────────────────────────
function UserGroupSubTab({ theme }: { theme: SettingsTheme }) {
  const [items, setItems] = useState<UserGroupItem[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [loading, setLoading] = useState(true);
  const [message, setMessage] = useState<{ type: "success" | "error"; text: string } | null>(null);

  const [showCreate, setShowCreate] = useState(false);
  const [newName, setNewName] = useState("");
  const [newDesc, setNewDesc] = useState("");
  const [creating, setCreating] = useState(false);

  // 编辑
  const [editingId, setEditingId] = useState<number | null>(null);
  const [editName, setEditName] = useState("");
  const [editDesc, setEditDesc] = useState("");
  const [saving, setSaving] = useState(false);

  // 资源配置
  const [configuringId, setConfiguringId] = useState<number | null>(null);

  const pageSize = 10;

  const fetchList = async () => {
    setLoading(true);
    try {
      const data = await userGroupApi.getUserGroupList({ page, size: pageSize });
      setItems(data.items || []);
      setTotal(data.total || 0);
    } catch {
      // 静默
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { fetchList(); }, [page]);

  const handleCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    setCreating(true);
    setMessage(null);
    try {
      await userGroupApi.createUserGroup({ name: newName, remark: newDesc || undefined });
      setMessage({ type: "success", text: "用户组创建成功" });
      setNewName(""); setNewDesc("");
      setShowCreate(false);
      await fetchList();
    } catch (err) {
      setMessage({ type: "error", text: err instanceof ApiError ? err.message : "创建失败" });
    } finally {
      setCreating(false);
    }
  };

  const handleEdit = (item: UserGroupItem) => {
    setEditingId(item.id);
    setEditName(item.name);
    setEditDesc(item.remark);
  };

  const handleSaveEdit = async () => {
    if (editingId === null) return;
    setSaving(true);
    setMessage(null);
    try {
      await userGroupApi.updateUserGroup({ id: editingId, name: editName || undefined, remark: editDesc || undefined });
      setMessage({ type: "success", text: "用户组已更新" });
      setEditingId(null);
      await fetchList();
    } catch (err) {
      setMessage({ type: "error", text: err instanceof ApiError ? err.message : "更新失败" });
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = async (id: number) => {
    try {
      await userGroupApi.deleteUserGroup({ id });
      setMessage({ type: "success", text: "用户组已删除" });
      await fetchList();
    } catch (err) {
      setMessage({ type: "error", text: err instanceof ApiError ? err.message : "删除失败" });
    }
  };

  const totalPages = Math.ceil(total / pageSize);

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <div />
        <div className="flex items-center gap-3">
          <button onClick={fetchList} className="flex items-center gap-1 text-xs px-3 py-2 rounded-xl" style={{ color: theme.from, fontFamily: "var(--font-display)", background: "var(--bg-elevated)", border: "1px solid var(--border-strong)" }}>
            <RefreshCw size={12} /> 刷新
          </button>
          <button onClick={() => setShowCreate(!showCreate)} className="flex items-center gap-1 text-xs px-4 py-2 rounded-xl hover:scale-105 transition-all duration-200" style={primaryBtnStyle(theme)}>
            <Plus size={12} /> 创建用户组
          </button>
        </div>
      </div>

      {message && <p className="text-xs mb-4" style={{ color: message.type === "success" ? "#34d399" : "#ff5555" }}>{message.text}</p>}

      {showCreate && (
        <div className="rounded-2xl p-6 mb-6" style={{ ...cardStyle, border: `1px solid ${theme.glow}` }}>
          <h2 className="mb-4" style={sectionTitleStyle}>创建用户组</h2>
          <form onSubmit={handleCreate} className="grid grid-cols-2 gap-4">
            <div className="flex flex-col gap-1.5">
              <label style={labelStyle}>名称</label>
              <input value={newName} onChange={e => setNewName(e.target.value)} className="px-4 py-2.5 rounded-xl text-sm outline-none" style={inputStyle} required />
            </div>
            <div className="flex flex-col gap-1.5">
              <label style={labelStyle}>描述</label>
              <input value={newDesc} onChange={e => setNewDesc(e.target.value)} className="px-4 py-2.5 rounded-xl text-sm outline-none" style={inputStyle} />
            </div>
            <div className="col-span-2 flex justify-end gap-3">
              <button type="button" onClick={() => setShowCreate(false)} className="px-4 py-2 rounded-xl text-sm" style={ghostBtnStyle}>取消</button>
              <button type="submit" disabled={creating} className="px-5 py-2 rounded-xl text-sm hover:scale-105 transition-all duration-200" style={primaryBtnStyle(theme, creating)}>
                {creating ? "创建中…" : "创建"}
              </button>
            </div>
          </form>
        </div>
      )}

      {/* 资源配置面板 */}
      {configuringId !== null && (
        <ResourceConfigPanel
          theme={theme}
          groupId={configuringId}
          onClose={() => { setConfiguringId(null); fetchList(); }}
        />
      )}

      <div className="rounded-2xl overflow-hidden" style={cardStyle}>
        <div className="grid grid-cols-6 gap-4 px-6 py-3 text-xs" style={{ color: "var(--text-secondary)", fontFamily: "var(--font-display)", fontWeight: 600, letterSpacing: "0.06em", borderBottom: "1px solid var(--border-default)" }}>
          <span>ID</span><span>名称</span><span>描述</span><span>用户数</span><span>资源数</span><span className="text-right">操作</span>
        </div>
        {loading ? (
          <div className="px-6 py-8 text-center text-sm" style={{ color: "var(--text-secondary)" }}>加载中…</div>
        ) : items.length === 0 ? (
          <div className="px-6 py-8 text-center text-sm" style={{ color: "var(--text-secondary)" }}>暂无用户组</div>
        ) : items.map(item => (
          <div key={item.id} className="grid grid-cols-6 gap-4 px-6 py-4 items-center text-sm" style={{ borderBottom: "1px solid var(--border-subtle)" }}>
            <span style={{ color: theme.from, fontFamily: "var(--font-display)", fontWeight: 600 }}>#{item.id}</span>
            {editingId === item.id ? (
              <>
                <input value={editName} onChange={e => setEditName(e.target.value)} className="px-2 py-1 rounded-lg text-sm outline-none" style={inputStyle} />
                <input value={editDesc} onChange={e => setEditDesc(e.target.value)} className="px-2 py-1 rounded-lg text-sm outline-none" style={inputStyle} />
                <span style={{ color: "var(--text-secondary)" }}>{item.user_count}</span>
                <span style={{ color: "var(--text-secondary)" }}>{item.resource_count}</span>
              </>
            ) : (
              <>
                <span style={{ color: "var(--text-primary)" }}>{item.name}</span>
                <span style={{ color: "var(--text-secondary)" }}>{item.remark || "—"}</span>
                <span style={{ color: "var(--text-secondary)" }}>{item.user_count}</span>
                <span style={{ color: "var(--text-secondary)" }}>{item.resource_count}</span>
              </>
            )}
            <div className="flex items-center justify-end gap-2">
              {editingId === item.id ? (
                <>
                  <button onClick={handleSaveEdit} disabled={saving} className="flex items-center gap-1 text-xs px-2 py-1 rounded-lg" style={{ color: "#34d399", background: "rgba(52,211,153,0.08)" }}>
                    <Check size={11} /> 保存
                  </button>
                  <button onClick={() => setEditingId(null)} className="flex items-center gap-1 text-xs px-2 py-1 rounded-lg" style={ghostBtnStyle}>
                    <X size={11} /> 取消
                  </button>
                </>
              ) : (
                <>
                  <button onClick={() => setConfiguringId(item.id)} className="flex items-center gap-1 text-xs px-2 py-1 rounded-lg" style={{ color: "#34d399", background: "rgba(52,211,153,0.08)" }}>
                    <Settings2 size={11} /> 配置资源
                  </button>
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
        {totalPages > 1 && (
          <div className="flex items-center justify-center gap-2 px-6 py-4" style={{ borderTop: "1px solid var(--border-subtle)" }}>
            <button onClick={() => setPage(p => Math.max(1, p - 1))} disabled={page <= 1} className="px-3 py-1.5 rounded-lg text-xs disabled:opacity-40" style={{ color: theme.from, background: "var(--bg-elevated)", fontFamily: "var(--font-display)" }}>上一页</button>
            <span className="text-xs" style={{ color: "var(--text-secondary)", fontFamily: "var(--font-display)" }}>{page} / {totalPages}</span>
            <button onClick={() => setPage(p => Math.min(totalPages, p + 1))} disabled={page >= totalPages} className="px-3 py-1.5 rounded-lg text-xs disabled:opacity-40" style={{ color: theme.from, background: "var(--bg-elevated)", fontFamily: "var(--font-display)" }}>下一页</button>
          </div>
        )}
      </div>
    </div>
  );
}

// ── 资源配置面板 ──────────────────────────────────────────────────────
function ResourceConfigPanel({
  theme,
  groupId,
  onClose,
}: {
  theme: SettingsTheme;
  groupId: number;
  onClose: () => void;
}) {
  const [allResources, setAllResources] = useState<SysConfigItem[]>([]);
  const [selectedKeys, setSelectedKeys] = useState<Set<string>>(new Set());
  const [loadingResources, setLoadingResources] = useState(true);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState<{ type: "success" | "error"; text: string } | null>(null);

  // 桌面文件管理器多选锚点：记录上次单击 pill 的下标（基于 visibleResources）
  const lastClickedIndex = useRef<number | null>(null);

  const fetchResources = useCallback(async () => {
    setLoadingResources(true);
    try {
      const [resources, detail] = await Promise.all([
        configApi.getConfigList({ group: "resource_site" }),
        userGroupApi.getGroupDetail({ id: groupId }),
      ]);
      setAllResources(resources || []);
      setSelectedKeys(new Set(detail.config_keys || []));
      lastClickedIndex.current = null;
    } catch {
      // 静默
    } finally {
      setLoadingResources(false);
    }
  }, [groupId]);

  useEffect(() => { fetchResources(); }, [fetchResources]);

  // 派生：18禁资源与全选状态
  const adultResources = allResources.filter(r => r.value5 === "1");
  const hasAdult = adultResources.length > 0;
  const adultKeys = new Set(adultResources.map(r => r.config_key));
  const allSelected = allResources.length > 0 && selectedKeys.size === allResources.length;
  const adultSelected = hasAdult && adultResources.every(r => selectedKeys.has(r.config_key));

  // pill 点击：桌面文件管理器语义
  // - 单击：清空当前，仅选中该项（更新锚点）
  // - Ctrl/Cmd + 单击：在该项上切换，不影响其他项（更新锚点）
  // - Shift + 单击：选中锚点到当前项区间内所有 pill（不清空区间外，不改锚点）
  const handlePillClick = (index: number, e: React.MouseEvent) => {
    const key = allResources[index].config_key;
    if (e.shiftKey && lastClickedIndex.current !== null) {
      const [a, b] = [lastClickedIndex.current, index].sort((x, y) => x - y);
      setSelectedKeys(prev => {
        const next = new Set(prev);
        for (let i = a; i <= b; i++) next.add(allResources[i].config_key);
        return next;
      });
      return;
    }
    if (e.ctrlKey || e.metaKey) {
      setSelectedKeys(prev => {
        const next = new Set(prev);
        if (next.has(key)) next.delete(key); else next.add(key);
        return next;
      });
      lastClickedIndex.current = index;
      return;
    }
    setSelectedKeys(new Set([key]));
    lastClickedIndex.current = index;
  };

  const toggleAll = () => {
    if (allSelected) {
      setSelectedKeys(new Set());
      lastClickedIndex.current = null;
    } else {
      setSelectedKeys(new Set(allResources.map(r => r.config_key)));
      lastClickedIndex.current = allResources.length > 0 ? 0 : null;
    }
  };

  // 18禁一键：在当前选择基础上增删全部 18禁，不动其余项
  const toggleAdult = () => {
    if (adultSelected) {
      setSelectedKeys(prev => {
        const next = new Set(prev);
        for (const k of adultKeys) next.delete(k);
        return next;
      });
    } else {
      setSelectedKeys(prev => {
        const next = new Set(prev);
        for (const k of adultKeys) next.add(k);
        return next;
      });
    }
  };

  const handleSave = async () => {
    setSaving(true);
    setMessage(null);
    try {
      await userGroupApi.setGroupResources({
        group_id: groupId,
        config_keys: Array.from(selectedKeys),
      });
      setMessage({ type: "success", text: "资源配置已保存" });
    } catch (err) {
      setMessage({ type: "error", text: err instanceof ApiError ? err.message : "保存失败" });
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="rounded-2xl p-6 mb-6" style={{ ...cardStyle, border: `1px solid ${theme.glow}` }}>
      <div className="flex items-center justify-between mb-4">
        <h2 style={sectionTitleStyle}>配置资源 — 用户组 #{groupId}</h2>
        <button onClick={onClose} className="flex items-center gap-1 text-xs px-3 py-2 rounded-xl" style={ghostBtnStyle}>
          <X size={12} /> 关闭
        </button>
      </div>

      {message && <p className="text-xs mb-4" style={{ color: message.type === "success" ? "#34d399" : "#ff5555" }}>{message.text}</p>}

      {loadingResources ? (
        <div className="py-8 text-center text-sm" style={{ color: "var(--text-secondary)" }}>加载资源列表…</div>
      ) : allResources.length === 0 ? (
        <div className="py-8 text-center text-sm" style={{ color: "var(--text-secondary)" }}>暂无资源站点，请先在"资源组管理"中添加</div>
      ) : (
        <div>
          {/* 工具行：全选 + 18禁 + 计数 */}
          <div className="flex flex-wrap items-center gap-2 mb-3">
            <button
              onClick={toggleAll}
              className="flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg text-xs transition-all duration-200"
              style={{
                background: allSelected ? theme.subtle : "var(--bg-elevated)",
                border: `1px solid ${allSelected ? theme.glow : "var(--border-strong)"}`,
                color: allSelected ? theme.from : "var(--text-secondary)",
                fontFamily: "var(--font-display)",
              }}
            >
              <span
                className="w-3.5 h-3.5 rounded flex items-center justify-center shrink-0"
                style={{
                  border: allSelected ? "none" : "1px solid var(--border-strong)",
                  background: allSelected ? `linear-gradient(135deg,${theme.from},${theme.to})` : "transparent",
                }}
              >
                {allSelected && <Check size={8} color="#fff" strokeWidth={3} />}
              </span>
              全选
            </button>

            {hasAdult && (
              <button
                onClick={toggleAdult}
                className="flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg text-xs transition-all duration-200"
                style={{
                  background: adultSelected ? "rgba(220,38,38,0.12)" : "var(--bg-elevated)",
                  border: `1px solid ${adultSelected ? "rgba(220,38,38,0.3)" : "var(--border-strong)"}`,
                  color: adultSelected ? "#fb7185" : "var(--text-secondary)",
                  fontFamily: "var(--font-display)",
                }}
              >
                <span
                  className="w-3.5 h-3.5 rounded flex items-center justify-center shrink-0"
                  style={{
                    border: adultSelected ? "none" : "1px solid var(--border-strong)",
                    background: adultSelected ? "linear-gradient(135deg,#dc2626,#fb7185)" : "transparent",
                  }}
                >
                  {adultSelected && <Check size={8} color="#fff" strokeWidth={3} />}
                </span>
                18禁
              </button>
            )}

            <span className="ml-auto text-xs" style={{ color: "var(--text-secondary)", fontFamily: "var(--font-display)" }}>
              已选 {selectedKeys.size} / {allResources.length}
            </span>
          </div>

          <div style={{ borderTop: "1px solid var(--border-default)", marginBottom: 8 }} />

          {/* 平铺 pill 网格 */}
          <div className="flex flex-wrap gap-2 max-h-80 overflow-y-auto pr-1">
            {allResources.map((res, idx) => {
              const isSelected = selectedKeys.has(res.config_key);
              const isAdult = res.value5 === "1";
              const notSearchable = res.value6 === "0";
              const label = res.title || res.config_key;
              const tip = `${res.config_key}${res.value1 ? `\n${res.value1}` : ""}${notSearchable ? "\n(不允许搜索)" : ""}`;
              return (
                <button
                  key={res.id}
                  onClick={(e) => handlePillClick(idx, e)}
                  title={tip}
                  className="relative flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg text-xs transition-all duration-200"
                  style={{
                    background: isSelected
                      ? isAdult ? "rgba(220,38,38,0.10)" : theme.subtle
                      : notSearchable ? "var(--bg-surface)" : "var(--bg-elevated)",
                    border: `1px solid ${isSelected
                      ? isAdult ? "rgba(220,38,38,0.25)" : theme.glow
                      : "var(--border-strong)"}`,
                    color: isSelected
                      ? isAdult ? "#fb7185" : theme.from
                      : notSearchable ? "var(--text-tertiary)" : "var(--text-secondary)",
                    fontFamily: "var(--font-display)",
                    opacity: notSearchable && !isSelected ? 0.7 : 1,
                  }}
                >
                  <span
                    className="w-3.5 h-3.5 rounded flex items-center justify-center shrink-0"
                    style={{
                      border: isSelected ? "none" : "1px solid var(--border-strong)",
                      background: isSelected
                        ? isAdult ? "linear-gradient(135deg,#dc2626,#fb7185)" : `linear-gradient(135deg,${theme.from},${theme.to})`
                        : "transparent",
                    }}
                  >
                    {isSelected && <Check size={8} color="#fff" strokeWidth={3} />}
                  </span>
                  <span className="truncate max-w-[12rem]">{label}</span>
                  {notSearchable && (
                    <span
                      className="text-[9px] px-1 rounded shrink-0"
                      style={{ background: "var(--bg-hover)", color: "var(--text-tertiary)" }}
                    >
                      禁搜
                    </span>
                  )}
                </button>
              );
            })}
          </div>

          <p className="text-[10px] mt-2" style={{ color: "var(--text-tertiary)" }}>
            单击选中该项 · Ctrl/Cmd+点击 切换追加 · Shift+点击 区间多选
          </p>
        </div>
      )}

      <div className="flex items-center justify-between mt-5 pt-4" style={{ borderTop: "1px solid var(--border-default)" }}>
        <span className="text-xs" style={{ color: "var(--text-secondary)", fontFamily: "var(--font-display)" }}>
          已选择 {selectedKeys.size} / {allResources.length} 个资源站点
        </span>
        <div className="flex gap-3">
          <button onClick={onClose} className="px-4 py-2 rounded-xl text-sm" style={ghostBtnStyle}>取消</button>
          <button onClick={handleSave} disabled={saving} className="px-5 py-2 rounded-xl text-sm hover:scale-105 transition-all duration-200" style={primaryBtnStyle(theme, saving)}>
            {saving ? "保存中…" : "保存配置"}
          </button>
        </div>
      </div>
    </div>
  );
}
