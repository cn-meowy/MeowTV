import { useEffect, useState } from "react";
import { User, Mail, Shield, Calendar, Save, Monitor, Smartphone, Trash2, RefreshCw } from "lucide-react";
import { GradientText } from "@/app/components/GradientText";
import { THEMES } from "@/app/components/Navbar";
import { useThemeStore } from "@/stores/theme";
import { useAuthStore } from "@/stores/auth";
import * as userApi from "@/api/user";
import type { DeviceInfo } from "@/types/api";
import { ApiError } from "@/api/client";

const DEVICE_TYPE_LABELS: Record<number, { label: string; icon: React.ElementType }> = {
  0: { label: "Web", icon: Monitor },
  1: { label: "Android", icon: Smartphone },
  2: { label: "iOS", icon: Smartphone },
  3: { label: "Apple TV", icon: Monitor },
};

/**
 * 个人信息页面 — 查看和编辑个人资料、修改密码、在线设备
 */
export default function ProfilePage() {
  const activeTheme = useThemeStore((s) => s.activeTheme);
  const theme = THEMES[activeTheme];
  const user = useAuthStore((s) => s.user);
  const fetchProfile = useAuthStore((s) => s.fetchProfile);

  const [nickname, setNickname] = useState(user?.nickname || "");
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState<{ type: "success" | "error"; text: string } | null>(null);

  // 修改密码表单
  const [oldPassword, setOldPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [changingPwd, setChangingPwd] = useState(false);
  const [pwdMessage, setPwdMessage] = useState<{ type: "success" | "error"; text: string } | null>(null);

  // 在线设备
  const [devices, setDevices] = useState<DeviceInfo[]>([]);
  const [deviceLoading, setDeviceLoading] = useState(true);
  const [deviceMessage, setDeviceMessage] = useState<{ type: "success" | "error"; text: string } | null>(null);

  const fetchDevices = async () => {
    setDeviceLoading(true);
    try {
      const data = await userApi.getDevices();
      setDevices(data.devices || []);
    } catch {
      // 静默处理
    } finally {
      setDeviceLoading(false);
    }
  };

  useEffect(() => {
    if (user) {
      setNickname(user.nickname || "");
    }
  }, [user]);

  useEffect(() => {
    fetchDevices();
  }, []);

  const handleSaveProfile = async () => {
    setSaving(true);
    setMessage(null);
    try {
      await userApi.updateProfile({ nickname });
      await fetchProfile();
      setMessage({ type: "success", text: "个人资料已更新" });
    } catch (err) {
      setMessage({ type: "error", text: err instanceof ApiError ? err.message : "更新失败" });
    } finally {
      setSaving(false);
    }
  };

  const handleChangePassword = async (e: React.FormEvent) => {
    e.preventDefault();
    setPwdMessage(null);
    if (newPassword !== confirmPassword) {
      setPwdMessage({ type: "error", text: "两次输入的密码不一致" });
      return;
    }
    if (newPassword.length < 6) {
      setPwdMessage({ type: "error", text: "密码至少 6 个字符" });
      return;
    }
    setChangingPwd(true);
    try {
      await userApi.changePassword({ old_password: oldPassword, new_password: newPassword });
      setPwdMessage({ type: "success", text: "密码已修改" });
      setOldPassword("");
      setNewPassword("");
      setConfirmPassword("");
    } catch (err) {
      setPwdMessage({ type: "error", text: err instanceof ApiError ? err.message : "修改密码失败" });
    } finally {
      setChangingPwd(false);
    }
  };

  const handleKick = async (deviceType: number) => {
    try {
      await userApi.kickDevice({ device_type: deviceType });
      setDeviceMessage({ type: "success", text: "设备已下线" });
      await fetchDevices();
    } catch (err) {
      setDeviceMessage({ type: "error", text: err instanceof ApiError ? err.message : "操作失败" });
    }
  };

  const roleLabel = user?.role === 1 ? "管理员" : "普通用户";
  const statusLabel = user?.status === 1 ? "正常" : "已禁用";

  return (
    <div className="px-10 md:px-16 py-10 max-w-3xl mx-auto">
      <h1 className="mb-8" style={{ fontFamily: "var(--font-display)", fontWeight: 800, fontSize: "1.75rem" }}>
        <GradientText from={theme.from} to={theme.to}>个人资料</GradientText>
      </h1>

      {/* 用户信息卡片 */}
      <div
        className="rounded-2xl p-6 mb-8"
        style={{
          background: "var(--bg-surface-strong)",
          backdropFilter: "blur(20px)",
          border: "1px solid var(--border-strong)",
        }}
      >
        <div className="flex items-center gap-4 mb-6">
          <div
            className="w-14 h-14 rounded-2xl flex items-center justify-center"
            style={{ background: `linear-gradient(135deg,${theme.from},${theme.to})`, boxShadow: `0 0 24px ${theme.glow}` }}
          >
            <User size={24} color="#fff" />
          </div>
          <div>
            <p style={{ fontFamily: "var(--font-display)", fontWeight: 700, fontSize: "1.25rem", color: "#fff" }}>
              {user?.nickname || user?.username || "—"}
            </p>
            <p className="text-sm" style={{ color: "var(--text-secondary)" }}>@{user?.username}</p>
          </div>
        </div>

        <div className="grid grid-cols-2 gap-4 text-sm">
          <div className="flex items-center gap-2" style={{ color: "var(--text-secondary)" }}>
            <Mail size={14} style={{ color: theme.from }} />
            <span>{user?.username}</span>
          </div>
          <div className="flex items-center gap-2" style={{ color: "var(--text-secondary)" }}>
            <Shield size={14} style={{ color: theme.from }} />
            <span>{roleLabel}</span>
          </div>
          <div className="flex items-center gap-2" style={{ color: "var(--text-secondary)" }}>
            <Calendar size={14} style={{ color: theme.from }} />
            <span>{statusLabel}</span>
          </div>
        </div>
      </div>

      {/* 编辑昵称 */}
      <div
        className="rounded-2xl p-6 mb-8"
        style={{
          background: "var(--bg-surface-strong)",
          backdropFilter: "blur(20px)",
          border: "1px solid var(--border-strong)",
        }}
      >
        <h2 className="mb-4" style={{ fontFamily: "var(--font-display)", fontWeight: 700, fontSize: "1.1rem", color: "#fff" }}>
          编辑资料
        </h2>
        <div className="flex flex-col gap-1.5 mb-4">
          <label className="text-xs" style={{ color: "var(--text-secondary)", fontFamily: "var(--font-display)", fontWeight: 500, letterSpacing: "0.06em" }}>昵称</label>
          <input
            value={nickname}
            onChange={e => setNickname(e.target.value)}
            className="px-4 py-3 rounded-xl text-sm outline-none transition-all duration-200"
            style={{
              background: "var(--bg-elevated)",
              border: `1px solid ${nickname ? theme.glow : "var(--border-strong)"}`,
              color: "var(--text-primary)",
            }}
          />
        </div>
        {message && (
          <p className="text-xs mb-3" style={{ color: message.type === "success" ? "#34d399" : "#ff5555" }}>{message.text}</p>
        )}
        <button
          onClick={handleSaveProfile}
          disabled={saving}
          className="flex items-center gap-2 px-5 py-2.5 rounded-xl text-sm transition-all duration-200 hover:scale-105 disabled:opacity-70"
          style={{
            background: `linear-gradient(135deg,${theme.from},${theme.to})`,
            color: "#fff",
            fontFamily: "var(--font-display)",
            fontWeight: 700,
            boxShadow: `0 0 20px ${theme.glow}`,
          }}
        >
          <Save size={14} />
          {saving ? "保存中…" : "保存"}
        </button>
      </div>

      {/* 修改密码 */}
      <div
        className="rounded-2xl p-6 mb-8"
        style={{
          background: "var(--bg-surface-strong)",
          backdropFilter: "blur(20px)",
          border: "1px solid var(--border-strong)",
        }}
      >
        <h2 className="mb-4" style={{ fontFamily: "var(--font-display)", fontWeight: 700, fontSize: "1.1rem", color: "#fff" }}>
          修改密码
        </h2>
        <form onSubmit={handleChangePassword} className="flex flex-col gap-4">
          <div className="flex flex-col gap-1.5">
            <label className="text-xs" style={{ color: "var(--text-secondary)", fontFamily: "var(--font-display)", fontWeight: 500, letterSpacing: "0.06em" }}>当前密码</label>
            <input
              type="password"
              value={oldPassword}
              onChange={e => setOldPassword(e.target.value)}
              className="px-4 py-3 rounded-xl text-sm outline-none transition-all duration-200"
              style={{
                background: "var(--bg-elevated)",
                border: "1px solid var(--border-strong)",
                color: "var(--text-primary)",
              }}
              autoComplete="current-password"
            />
          </div>
          <div className="flex flex-col gap-1.5">
            <label className="text-xs" style={{ color: "var(--text-secondary)", fontFamily: "var(--font-display)", fontWeight: 500, letterSpacing: "0.06em" }}>新密码</label>
            <input
              type="password"
              value={newPassword}
              onChange={e => setNewPassword(e.target.value)}
              className="px-4 py-3 rounded-xl text-sm outline-none transition-all duration-200"
              style={{
                background: "var(--bg-elevated)",
                border: "1px solid var(--border-strong)",
                color: "var(--text-primary)",
              }}
              autoComplete="new-password"
            />
          </div>
          <div className="flex flex-col gap-1.5">
            <label className="text-xs" style={{ color: "var(--text-secondary)", fontFamily: "var(--font-display)", fontWeight: 500, letterSpacing: "0.06em" }}>确认新密码</label>
            <input
              type="password"
              value={confirmPassword}
              onChange={e => setConfirmPassword(e.target.value)}
              className="px-4 py-3 rounded-xl text-sm outline-none transition-all duration-200"
              style={{
                background: "var(--bg-elevated)",
                border: "1px solid var(--border-strong)",
                color: "var(--text-primary)",
              }}
              autoComplete="new-password"
            />
          </div>
          {pwdMessage && (
            <p className="text-xs" style={{ color: pwdMessage.type === "success" ? "#34d399" : "#ff5555" }}>{pwdMessage.text}</p>
          )}
          <button
            type="submit"
            disabled={changingPwd}
            className="flex items-center justify-center gap-2 px-5 py-2.5 rounded-xl text-sm transition-all duration-200 hover:scale-105 disabled:opacity-70"
            style={{
              background: `linear-gradient(135deg,${theme.from},${theme.to})`,
              color: "#fff",
              fontFamily: "var(--font-display)",
              fontWeight: 700,
              boxShadow: `0 0 20px ${theme.glow}`,
            }}
          >
            {changingPwd ? "修改中…" : "修改密码"}
          </button>
        </form>
      </div>

      {/* 在线设备 */}
      <div
        className="rounded-2xl p-6"
        style={{
          background: "var(--bg-surface-strong)",
          backdropFilter: "blur(20px)",
          border: "1px solid var(--border-strong)",
        }}
      >
        <div className="flex items-center justify-between mb-4">
          <h2 style={{ fontFamily: "var(--font-display)", fontWeight: 700, fontSize: "1.1rem", color: "#fff" }}>
            在线设备
          </h2>
          <button
            onClick={fetchDevices}
            className="flex items-center gap-1 text-xs px-3 py-1.5 rounded-xl transition-all duration-200"
            style={{ color: theme.from, fontFamily: "var(--font-display)" }}
          >
            <RefreshCw size={12} />
            刷新
          </button>
        </div>

        {deviceMessage && (
          <p className="text-xs mb-3" style={{ color: deviceMessage.type === "success" ? "#34d399" : "#ff5555" }}>{deviceMessage.text}</p>
        )}

        {deviceLoading ? (
          <p className="text-sm" style={{ color: "var(--text-secondary)" }}>加载中…</p>
        ) : devices.length === 0 ? (
          <p className="text-sm" style={{ color: "var(--text-secondary)" }}>暂无在线设备</p>
        ) : (
          <div className="flex flex-col gap-3">
            {devices.map(device => {
              const info = DEVICE_TYPE_LABELS[device.device_type] || DEVICE_TYPE_LABELS[0];
              const Icon = info.icon;
              return (
                <div
                  key={device.device_id}
                  className="flex items-center justify-between p-4 rounded-xl"
                  style={{
                    background: "var(--bg-elevated)",
                    border: "1px solid var(--border-default)",
                  }}
                >
                  <div className="flex items-center gap-3">
                    <Icon size={18} style={{ color: theme.from }} />
                    <div>
                      <p className="text-sm" style={{ color: "var(--text-primary)" }}>{info.label}</p>
                      <p className="text-xs" style={{ color: "var(--text-secondary)" }}>{device.device_name}</p>
                    </div>
                  </div>
                  <button
                    onClick={() => handleKick(device.device_type)}
                    className="flex items-center gap-1 text-xs px-3 py-1.5 rounded-xl transition-all duration-200"
                    style={{ color: "#ff5555", fontFamily: "var(--font-display)" }}
                  >
                    <Trash2 size={12} />
                    下线
                  </button>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
