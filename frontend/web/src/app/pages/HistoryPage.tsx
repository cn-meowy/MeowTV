import { useEffect, useState } from "react";
import { useNavigate } from "react-router";
import { Clock, Play, Trash2, ArrowLeft, Search } from "lucide-react";
import { usePlayHistoryStore, type PlayHistoryRecord } from "@/stores/play-history";
import { useThemeStore } from "@/stores/theme";
import { THEMES, type ThemeKey } from "@/app/components/Navbar";
import { GradientText } from "@/app/components/GradientText";
import { buildResourceImageUrl } from "@/api/search";

interface DateGroup { label: string; items: PlayHistoryRecord[] }

function groupByDate(records: PlayHistoryRecord[]): DateGroup[] {
  const groups = new Map<string, PlayHistoryRecord[]>();
  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
  const yesterday = today - 86400000;
  const weekAgo = today - 7 * 86400000;
  for (const r of records) {
    const t = r.updatedAt;
    let label: string;
    if (t >= today) label = "今天";
    else if (t >= yesterday) label = "昨天";
    else if (t >= weekAgo) label = "本周";
    else { const d = new Date(t); label = d.getFullYear() + "年" + (d.getMonth() + 1) + "月"; }
    if (!groups.has(label)) groups.set(label, []);
    groups.get(label)!.push(r);
  }
  return Array.from(groups.entries()).map(([label, items]) => ({ label, items }));
}

function fmtTime(sec: number) {
  const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = Math.floor(sec % 60);
  return h > 0 ? h + ":" + String(m).padStart(2, "0") + ":" + String(s).padStart(2, "0") : m + ":" + String(s).padStart(2, "0");
}

function fmtRelative(ms: number) {
  const diff = Date.now() - ms, min = Math.floor(diff / 60000);
  if (min < 1) return "刚刚";
  if (min < 60) return min + "分钟前";
  const hour = Math.floor(min / 60);
  if (hour < 24) return hour + "小时前";
  const day = Math.floor(hour / 24);
  if (day < 7) return day + "天前";
  const d = new Date(ms);
  return d.getFullYear() + "/" + (d.getMonth() + 1) + "/" + d.getDate();
}

function HistoryCard({ record, theme, onClick, onDelete }: {
  record: PlayHistoryRecord;
  theme: (typeof THEMES)[ThemeKey];
  onClick: () => void;
  onDelete: () => void;
}) {
  const pic = record.vodPic ? buildResourceImageUrl(record.vodPic) : "";
  const pct = record.duration > 0 ? Math.min(record.progress, 100) : 0;
  return (
    <div className="flex gap-3 p-3 rounded-xl cursor-pointer transition-all duration-200 group"
      style={{ background: "var(--bg-surface)", border: "1px solid var(--border-default)" }}
      onClick={onClick}
      onMouseEnter={(e) => { e.currentTarget.style.background = "var(--bg-hover)"; e.currentTarget.style.borderColor = "var(--border-strong)"; }}
      onMouseLeave={(e) => { e.currentTarget.style.background = "var(--bg-surface)"; e.currentTarget.style.borderColor = "var(--border-default)"; }}>
      <div className="relative w-28 h-16 shrink-0 rounded-lg overflow-hidden" style={{ background: "var(--bg-elevated)" }}>
        {pic ? <img src={pic} alt={record.vodName} loading="lazy" className="w-full h-full object-cover"
          onError={(e) => { (e.target as HTMLImageElement).style.display = "none"; }} />
        : <div className="w-full h-full flex items-center justify-center"><Play size={14} style={{ color: "var(--text-tertiary)" }} /></div>}
        <div className="absolute inset-0" style={{ background: "linear-gradient(to top, rgba(0,0,0,0.5) 0%, transparent 50%)" }} />
        {pct > 0 && <div className="absolute bottom-0 left-0 right-0 h-0.5" style={{ background: "rgba(255,255,255,0.15)" }}>
          <div className="h-full" style={{ width: pct + "%", background: theme.from }} /></div>}
        {record.duration > 0 && (
          <div className="absolute bottom-1 right-1 text-[9px] px-1 rounded"
            style={{ background: "rgba(0,0,0,0.7)", color: "rgba(255,255,255,0.85)", fontFamily: "var(--font-display)" }}>
            {fmtTime(record.currentTime)}/{fmtTime(record.duration)}</div>)}
      </div>
      <div className="flex-1 min-w-0 py-0.5">
        <p className="text-xs truncate" style={{ color: "var(--text-primary)", fontWeight: 600 }}>{record.vodName}</p>
        <p className="text-[10px] truncate mt-0.5" style={{ color: "var(--text-muted)" }}>{record.epName} · {record.resourceName}</p>
        <p className="text-[9px] mt-1" style={{ color: "var(--text-tertiary)" }}>{fmtRelative(record.updatedAt)}</p>
      </div>
      <button onClick={(e) => { e.stopPropagation(); onDelete(); }}
        className="shrink-0 self-center opacity-0 group-hover:opacity-100 w-7 h-7 flex items-center justify-center rounded-lg transition-all duration-200"
        style={{ color: "var(--text-tertiary)" }}
        onMouseEnter={(e) => { e.currentTarget.style.color = "#fb7185"; e.currentTarget.style.background = "rgba(220,38,38,0.08)"; }}
        onMouseLeave={(e) => { e.currentTarget.style.color = "var(--text-tertiary)"; e.currentTarget.style.background = "transparent"; }}>
        <Trash2 size={12} />
      </button>
    </div>
  );
}

export default function HistoryPage() {
  const navigate = useNavigate();
  const activeTheme = useThemeStore((s) => s.activeTheme);
  const theme = THEMES[activeTheme];
  const records = usePlayHistoryStore((s) => s.records);
  const removeRecord = usePlayHistoryStore((s) => s.removeRecord);
  const clearAll = usePlayHistoryStore((s) => s.clearAll);
  const [q, setQ] = useState("");
  const [confirmClear, setConfirmClear] = useState(false);

  const filtered = q.trim()
    ? records.filter((r) =>
        r.vodName.toLowerCase().includes(q.toLowerCase()) ||
        r.epName.toLowerCase().includes(q.toLowerCase()) ||
        r.resourceName.toLowerCase().includes(q.toLowerCase()))
    : records;

  const grouped = groupByDate(filtered);

  const go = (r: PlayHistoryRecord) => {
    navigate("/play?" + new URLSearchParams({
      group_key: r.groupKey, name: r.vodName, site: r.resourceDomain,
      vod_id: String(r.vodId),
      source: String(r.sourceIndex), ep: String(r.epIndex),
    }).toString());
  };

  const doClear = () => {
    if (!confirmClear) { setConfirmClear(true); setTimeout(() => setConfirmClear(false), 3000); return; }
    clearAll(); setConfirmClear(false);
  };

  return (
    <div className="px-10 md:px-16 py-8 min-h-screen">
      <div className="flex items-center justify-between mb-8">
        <div className="flex items-center gap-4">
          <button onClick={() => navigate(-1)}
            className="w-9 h-9 rounded-xl flex items-center justify-center transition-all duration-200"
            style={{ background: "var(--bg-elevated)", border: "1px solid var(--border-default)" }}
            onMouseEnter={(e) => { e.currentTarget.style.background = theme.subtle; e.currentTarget.style.borderColor = theme.glow; }}
            onMouseLeave={(e) => { e.currentTarget.style.background = "var(--bg-elevated)"; e.currentTarget.style.borderColor = "var(--border-default)"; }}>
            <ArrowLeft size={16} style={{ color: "var(--text-secondary)" }} />
          </button>
          <div className="flex items-center gap-3">
            <div className="w-9 h-9 rounded-xl flex items-center justify-center"
              style={{ background: "linear-gradient(135deg," + theme.from + "," + theme.to + ")", boxShadow: "0 0 16px " + theme.glow }}>
              <Clock size={16} color="#fff" />
            </div>
            <h1 className="text-xl" style={{ fontFamily: "var(--font-display)", fontWeight: 700 }}>
              <GradientText from="#ffffff" to={theme.from}>播放历史</GradientText>
            </h1>
            <span className="text-xs px-2 py-0.5 rounded-full"
              style={{ background: theme.subtle, color: theme.from, fontFamily: "var(--font-display)", fontWeight: 600 }}>
              {records.length}
            </span>
          </div>
        </div>
        <div className="flex items-center gap-3">
          <div className="flex items-center gap-2 rounded-xl px-3 py-2"
            style={{ background: "var(--bg-elevated)", border: "1px solid var(--border-default)", minWidth: "200px" }}>
            <Search size={14} style={{ color: "var(--text-tertiary)", flexShrink: 0 }} />
            <input value={q} onChange={(e) => setQ(e.target.value)}
              placeholder="搜索历史记录..." className="flex-1 bg-transparent outline-none text-xs"
              style={{ color: "var(--text-primary)" }} />
          </div>
          <button onClick={doClear}
            className="flex items-center gap-1.5 text-xs px-4 py-2 rounded-xl transition-all duration-200"
            style={{
              color: confirmClear ? "#fff" : "var(--text-secondary)",
              background: confirmClear ? "linear-gradient(135deg,#dc2626,#fb7185)" : "var(--bg-elevated)",
              border: "1px solid var(--border-default)", fontFamily: "var(--font-display)",
            }}
            onMouseEnter={(e) => { if (!confirmClear) { e.currentTarget.style.color = "#fb7185"; e.currentTarget.style.borderColor = "rgba(220,38,38,0.3)"; }}}
            onMouseLeave={(e) => { if (!confirmClear) { e.currentTarget.style.color = "var(--text-secondary)"; e.currentTarget.style.borderColor = "var(--border-default)"; }}}>
            <Trash2 size={12} />{confirmClear ? "确认清空？" : "清空全部"}
          </button>
        </div>
      </div>

      {filtered.length === 0 && (
        <div className="flex flex-col items-center justify-center py-32">
          <div className="w-20 h-20 rounded-3xl flex items-center justify-center mb-4" style={{ background: theme.subtle }}>
            <Clock size={32} style={{ color: theme.from }} />
          </div>
          <p className="text-sm mb-1" style={{ color: "var(--text-secondary)", fontFamily: "var(--font-display)" }}>
            {q ? "没有找到匹配的记录" : "还没有播放历史"}</p>
          <p className="text-xs" style={{ color: "var(--text-tertiary)" }}>
            {q ? "试试其他关键词" : "开始观看视频，历史记录会出现在这里"}</p>
        </div>
      )}

      <div className="space-y-8">
        {grouped.map(({ label, items }) => (
          <div key={label}>
            <div className="flex items-center gap-2 mb-4">
              <p className="text-xs tracking-wider shrink-0" style={{ color: "var(--text-muted)", fontFamily: "var(--font-display)", fontWeight: 600 }}>{label}</p>
              <div className="flex-1 h-px" style={{ background: "var(--border-default)" }} />
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-3">
              {items.map((record) => (
                <HistoryCard key={record.vodId + "-" + record.resourceDomain + "-ep" + record.epIndex}
                  record={record} theme={theme}
                  onClick={() => go(record)}
                  onDelete={() => removeRecord(record.vodId, record.resourceDomain, record.epIndex)} />
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
