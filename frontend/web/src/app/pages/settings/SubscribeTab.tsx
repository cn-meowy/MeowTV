import { useEffect, useState } from "react";
import { RefreshCw, Download, Globe, ToggleLeft, ToggleRight, Zap } from "lucide-react";
import * as configApi from "@/api/config";
import { ApiError } from "@/api/client";
import type { SettingsTheme } from "./settings-styles";
import { cardStyle, sectionTitleStyle, labelStyle, inputStyle, primaryBtnStyle } from "./settings-styles";

export function SubscribeTab({ theme }: { theme: SettingsTheme }) {
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [savingProxy, setSavingProxy] = useState(false);
  const [fetching, setFetching] = useState(false);
  const [message, setMessage] = useState<{ type: "success" | "error"; text: string } | null>(null);

  // 订阅配置数据
  const [configId, setConfigId] = useState<number | null>(null);
  const [subscribeUrl, setSubscribeUrl] = useState("");
  const [autoSubscribe, setAutoSubscribe] = useState(false);
  const [cronExpr, setCronExpr] = useState("0 */6 * * * ?");
  const [isEnabled, setIsEnabled] = useState(true);

  // 代理配置数据
  const [proxyProtocol, setProxyProtocol] = useState("socks5");
  const [proxyHost, setProxyHost] = useState("127.0.0.1");
  const [proxyPort, setProxyPort] = useState("1080");
  const [proxyUsername, setProxyUsername] = useState("");
  const [proxyPassword, setProxyPassword] = useState("");
  const [proxyEnabled, setProxyEnabled] = useState(false);
  const [proxyPasswordMasked, setProxyPasswordMasked] = useState(false);

  // 代理测试
  const [proxyTestUrl, setProxyTestUrl] = useState("http://www.gstatic.com/generate_204");
  const [testingProxy, setTestingProxy] = useState(false);
  const [proxyTestResult, setProxyTestResult] = useState<{ type: "success" | "error"; text: string } | null>(null);

  const fetchConfig = async () => {
    setLoading(true);
    try {
      const list = await configApi.getConfigList({ group: "resource_subscribe" });
      if (list && list.length > 0) {
        for (const cfg of list) {
          if (cfg.config_key === "resource_subscribe") {
            setConfigId(cfg.id);
            setSubscribeUrl(cfg.value1 || "");
            setAutoSubscribe(cfg.value2 === "true");
            setCronExpr(cfg.value3 || "0 */6 * * * ?");
            setIsEnabled(cfg.is_enabled);
          } else if (cfg.config_key === "resource_proxy") {
            setProxyProtocol(cfg.value1 || "socks5");
            setProxyHost(cfg.value2 || "127.0.0.1");
            setProxyPort(cfg.value3 || "1080");
            setProxyUsername(cfg.value4 || "");
            if (cfg.value5) {
              setProxyPassword("••••••");
              setProxyPasswordMasked(true);
            } else {
              setProxyPassword("");
              setProxyPasswordMasked(false);
            }
            setProxyEnabled(cfg.value6 === "true");
          } else if (cfg.config_key === "resource_proxy_test_url") {
            setProxyTestUrl(cfg.value1 || "http://www.gstatic.com/generate_204");
          }
        }
      }
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
      await configApi.updateConfig({
        config_key: "resource_subscribe",
        value1: subscribeUrl,
        value2: String(autoSubscribe),
        value3: cronExpr,
        is_enabled: isEnabled,
      });
      setMessage({ type: "success", text: "订阅配置已保存" });
      await fetchConfig();
    } catch (err) {
      setMessage({ type: "error", text: err instanceof ApiError ? err.message : "保存失败" });
    } finally {
      setSaving(false);
    }
  };

  const handleSaveProxy = async (e: React.FormEvent) => {
    e.preventDefault();
    setSavingProxy(true);
    setMessage(null);
    try {
      const updateReq: Record<string, unknown> = {
        config_key: "resource_proxy",
        value1: proxyProtocol,
        value2: proxyHost,
        value3: proxyPort,
        value4: proxyUsername,
        value6: String(proxyEnabled),
      };
      // 只有用户实际修改了密码才提交，掩码值不提交
      if (!proxyPasswordMasked && proxyPassword) {
        updateReq.value5 = proxyPassword;
      } else if (!proxyPasswordMasked) {
        updateReq.value5 = "";
      }
      await configApi.updateConfig(updateReq as any);
      setMessage({ type: "success", text: "代理配置已保存" });
      await fetchConfig();
    } catch (err) {
      setMessage({ type: "error", text: err instanceof ApiError ? err.message : "保存失败" });
    } finally {
      setSavingProxy(false);
    }
  };

  // 测试代理连通性
  const handleTestProxy = async () => {
    setTestingProxy(true);
    setProxyTestResult(null);
    try {
      // 先保存测试URL
      await configApi.updateConfig({
        config_key: "resource_proxy_test_url",
        value1: proxyTestUrl,
        is_enabled: true,
      } as any);
      const msg = await configApi.testProxyConnectivity();
      setProxyTestResult({ type: "success", text: msg || "代理连接成功" });
    } catch (err) {
      setProxyTestResult({ type: "error", text: err instanceof ApiError ? err.message : "测试失败" });
    } finally {
      setTestingProxy(false);
    }
  };

  const handleFetch = async () => {
    setFetching(true);
    setMessage(null);
    try {
      const result = await configApi.fetchSubscribe();
      setMessage({ type: "success", text: `拉取成功：共 ${result.total} 个站点，新增 ${result.added}，更新 ${result.updated}` });
    } catch (err) {
      setMessage({ type: "error", text: err instanceof ApiError ? err.message : "拉取失败" });
    } finally {
      setFetching(false);
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
            <h2 style={sectionTitleStyle}>资源订阅配置</h2>
            <div className="flex items-center gap-3">
              <button onClick={fetchConfig} className="flex items-center gap-1 text-xs px-3 py-2 rounded-xl" style={{ color: theme.from, fontFamily: "var(--font-display)", background: "var(--bg-elevated)", border: "1px solid var(--border-strong)" }}>
                <RefreshCw size={12} /> 刷新
              </button>
              <button onClick={handleFetch} disabled={fetching} className="flex items-center gap-1 text-xs px-4 py-2 rounded-xl hover:scale-105 transition-all duration-200" style={primaryBtnStyle(theme, fetching)}>
                <Download size={12} /> {fetching ? "拉取中…" : "手动拉取"}
              </button>
            </div>
          </div>

          <form onSubmit={handleSave} className="space-y-5">
            {/* 订阅地址 */}
            <div className="flex flex-col gap-1.5">
              <label style={labelStyle}>订阅地址</label>
              <input
                value={subscribeUrl}
                onChange={e => setSubscribeUrl(e.target.value)}
                className="px-4 py-2.5 rounded-xl text-sm outline-none"
                style={inputStyle}
                placeholder="https://..."
              />
            </div>

            {/* 自动订阅 + Cron */}
            <div className="grid grid-cols-2 gap-4">
              <div className="flex flex-col gap-1.5">
                <label style={labelStyle}>自动订阅</label>
                <button
                  type="button"
                  onClick={() => setAutoSubscribe(!autoSubscribe)}
                  className="flex items-center gap-2 px-4 py-2.5 rounded-xl text-sm"
                  style={{
                    background: autoSubscribe ? "rgba(52,211,153,0.08)" : "var(--bg-elevated)",
                    border: `1px solid ${autoSubscribe ? "rgba(52,211,153,0.3)" : "var(--border-strong)"}`,
                    color: autoSubscribe ? "#34d399" : "var(--text-secondary)",
                  }}
                >
                  {autoSubscribe ? <ToggleRight size={18} /> : <ToggleLeft size={18} />}
                  {autoSubscribe ? "已开启" : "已关闭"}
                </button>
              </div>
              <div className="flex flex-col gap-1.5">
                <label style={labelStyle}>Cron 表达式</label>
                <input
                  value={cronExpr}
                  onChange={e => setCronExpr(e.target.value)}
                  className="px-4 py-2.5 rounded-xl text-sm outline-none font-mono"
                  style={inputStyle}
                  placeholder="0 */6 * * * ?"
                  disabled={!autoSubscribe}
                />
              </div>
            </div>

            {/* 启用/禁用 */}
            <div className="flex flex-col gap-1.5">
              <label style={labelStyle}>状态</label>
              <button
                type="button"
                onClick={() => setIsEnabled(!isEnabled)}
                className="flex items-center gap-2 px-4 py-2.5 rounded-xl text-sm w-fit"
                style={{
                  background: isEnabled ? "rgba(52,211,153,0.08)" : "rgba(255,85,85,0.08)",
                  border: `1px solid ${isEnabled ? "rgba(52,211,153,0.3)" : "rgba(255,85,85,0.3)"}`,
                  color: isEnabled ? "#34d399" : "#ff5555",
                }}
              >
                {isEnabled ? <ToggleRight size={18} /> : <ToggleLeft size={18} />}
                {isEnabled ? "已启用" : "已禁用"}
              </button>
            </div>

            {/* 保存按钮 */}
            <div className="flex justify-end pt-2">
              <button type="submit" disabled={saving} className="px-6 py-2.5 rounded-xl text-sm hover:scale-105 transition-all duration-200" style={primaryBtnStyle(theme, saving)}>
                {saving ? "保存中…" : "保存配置"}
              </button>
            </div>
          </form>

          {configId !== null && (
            <div className="mt-4 pt-4" style={{ borderTop: "1px solid var(--border-default)" }}>
              <span className="text-xs" style={{ color: "var(--text-tertiary)", fontFamily: "var(--font-display)" }}>配置 ID: #{configId}</span>
            </div>
          )}
        </div>
      )}

      {/* ── 代理配置 ── */}
      <div className="rounded-2xl p-6 mt-6" style={{ ...cardStyle, border: `1px solid ${theme.glow}` }}>
        <div className="flex items-center gap-2 mb-6">
          <Globe size={16} style={{ color: theme.from }} />
          <h2 style={sectionTitleStyle}>资源代理配置</h2>
        </div>

        <form onSubmit={handleSaveProxy} className="space-y-5">
          {/* 代理协议 */}
          <div className="flex flex-col gap-1.5">
            <label style={labelStyle}>代理协议</label>
            <select
              value={proxyProtocol}
              onChange={e => setProxyProtocol(e.target.value)}
              className="px-4 py-2.5 rounded-xl text-sm outline-none cursor-pointer"
              style={{
                ...inputStyle,
                appearance: "none",
                backgroundImage: `url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='12' viewBox='0 0 24 24' fill='none' stroke='%23888' stroke-width='2'%3E%3Cpath d='M6 9l6 6 6-6'/%3E%3C/svg%3E")`,
                backgroundRepeat: "no-repeat",
                backgroundPosition: "right 12px center",
              }}
            >
              <option value="socks5">SOCKS5</option>
              <option value="http">HTTP</option>
            </select>
          </div>

          {/* 代理地址 + 端口 */}
          <div className="grid grid-cols-4 gap-4">
            <div className="col-span-3 flex flex-col gap-1.5">
              <label style={labelStyle}>代理地址</label>
              <input
                value={proxyHost}
                onChange={e => setProxyHost(e.target.value)}
                className="px-4 py-2.5 rounded-xl text-sm outline-none"
                style={inputStyle}
                placeholder="127.0.0.1"
              />
            </div>
            <div className="flex flex-col gap-1.5">
              <label style={labelStyle}>端口</label>
              <input
                value={proxyPort}
                onChange={e => setProxyPort(e.target.value)}
                className="px-4 py-2.5 rounded-xl text-sm outline-none"
                style={inputStyle}
                placeholder="1080"
              />
            </div>
          </div>

          {/* 认证用户名 */}
          <div className="flex flex-col gap-1.5">
            <label style={labelStyle}>认证用户名 <span style={{ color: "var(--text-tertiary)", fontSize: "0.7rem" }}>(可选)</span></label>
            <input
              value={proxyUsername}
              onChange={e => setProxyUsername(e.target.value)}
              className="px-4 py-2.5 rounded-xl text-sm outline-none"
              style={inputStyle}
              placeholder="无需认证可留空"
            />
          </div>

          {/* 认证密码 */}
          <div className="flex flex-col gap-1.5">
            <label style={labelStyle}>认证密码 <span style={{ color: "var(--text-tertiary)", fontSize: "0.7rem" }}>(可选)</span></label>
            <input
              type="password"
              value={proxyPassword}
              onChange={e => { setProxyPassword(e.target.value); setProxyPasswordMasked(false); }}
              onFocus={() => { if (proxyPasswordMasked) { setProxyPassword(""); setProxyPasswordMasked(false); } }}
              className="px-4 py-2.5 rounded-xl text-sm outline-none"
              style={inputStyle}
              placeholder="无需认证可留空"
            />
          </div>

          {/* 启用代理 */}
          <div className="flex flex-col gap-1.5">
            <label style={labelStyle}>启用代理</label>
            <button
              type="button"
              onClick={() => setProxyEnabled(!proxyEnabled)}
              className="flex items-center gap-2 px-4 py-2.5 rounded-xl text-sm w-fit"
              style={{
                background: proxyEnabled ? "rgba(52,211,153,0.08)" : "var(--bg-elevated)",
                border: `1px solid ${proxyEnabled ? "rgba(52,211,153,0.3)" : "var(--border-strong)"}`,
                color: proxyEnabled ? "#34d399" : "var(--text-secondary)",
              }}
            >
              {proxyEnabled ? <ToggleRight size={18} /> : <ToggleLeft size={18} />}
              {proxyEnabled ? "已开启" : "已关闭"}
            </button>
          </div>

          {/* 代理测试URL */}
          <div className="flex flex-col gap-1.5">
            <label style={labelStyle}>测试URL <span style={{ color: "var(--text-tertiary)", fontSize: "0.7rem" }}>(用于验证代理连通性)</span></label>
            <input
              value={proxyTestUrl}
              onChange={e => setProxyTestUrl(e.target.value)}
              className="px-4 py-2.5 rounded-xl text-sm outline-none"
              style={inputStyle}
              placeholder="http://www.gstatic.com/generate_204"
            />
          </div>

          {/* 测试结果提示 */}
          {proxyTestResult && (
            <p className="text-xs" style={{ color: proxyTestResult.type === "success" ? "#34d399" : "#ff5555" }}>
              {proxyTestResult.text}
            </p>
          )}

          {/* 保存 + 测试按钮 */}
          <div className="flex items-center justify-end gap-3 pt-2">
            <button
              type="button"
              onClick={handleTestProxy}
              disabled={testingProxy || !proxyEnabled}
              className="flex items-center gap-1.5 px-4 py-2.5 rounded-xl text-sm transition-all duration-200"
              style={{
                background: testingProxy ? "var(--bg-elevated)" : "rgba(250,204,21,0.08)",
                border: `1px solid ${testingProxy ? "var(--border-strong)" : "rgba(250,204,21,0.3)"}`,
                color: testingProxy ? "var(--text-tertiary)" : "#facc15",
                cursor: testingProxy || !proxyEnabled ? "not-allowed" : "pointer",
                opacity: !proxyEnabled ? 0.5 : 1,
              }}
            >
              <Zap size={14} />
              {testingProxy ? "测试中…" : "测试连接"}
            </button>
            <button type="submit" disabled={savingProxy} className="px-6 py-2.5 rounded-xl text-sm hover:scale-105 transition-all duration-200" style={primaryBtnStyle(theme, savingProxy)}>
              {savingProxy ? "保存中…" : "保存代理配置"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
