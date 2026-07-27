import { useState } from "react";
import { Globe, Check, ChevronDown, ChevronUp } from "lucide-react";
import type { SearchResultItem } from "@/types/api";
import { useThemeStore } from "@/stores/theme";
import { THEMES } from "./Navbar";
import { Collapsible, CollapsibleTrigger, CollapsibleContent } from "./ui/collapsible";

interface ResourceSwitcherProps {
  items: SearchResultItem[];
  activeDomain: string;
  onChange: (item: SearchResultItem) => void;
}

export function ResourceSwitcher({ items, activeDomain, onChange }: ResourceSwitcherProps) {
  const activeTheme = useThemeStore((s) => s.activeTheme);
  const theme = THEMES[activeTheme];
  const [open, setOpen] = useState(false);

  if (items.length <= 1) return null;

  return (
    <Collapsible open={open} onOpenChange={setOpen}>
      <div className="rounded-xl p-4" style={{ background: "var(--bg-surface)", border: "1px solid var(--border-default)" }}>
        <CollapsibleTrigger asChild>
          <button className="w-full flex items-center justify-between cursor-pointer">
            <h3
              className="text-xs"
              style={{ color: "var(--text-muted)", fontFamily: "var(--font-display)", fontWeight: 600 }}
            >
              同组资源
            </h3>
            <span
              className="flex items-center gap-0.5 text-[10px] transition-transform duration-200"
              style={{ color: "var(--text-tertiary)" }}
            >
              {open ? <ChevronUp size={12} /> : <ChevronDown size={12} />}
            </span>
          </button>
        </CollapsibleTrigger>
        <CollapsibleContent>
          <div className="flex gap-2 flex-wrap mt-3">
            {items.map((item) => {
              const isActive = item.resource_domain === activeDomain;
              return (
                <button
                  key={item.resource_domain}
                  onClick={() => onChange(item)}
                  className="inline-flex items-center gap-1.5 text-xs px-3 py-1.5 rounded-lg transition-all duration-200"
                  style={{
                    background: isActive ? theme.subtle : "var(--bg-elevated)",
                    color: isActive ? theme.from : "var(--text-muted)",
                    border: isActive ? `1px solid ${theme.from}40` : "1px solid var(--border-default)",
                    fontFamily: "var(--font-display)",
                    fontWeight: isActive ? 600 : 400,
                  }}
                >
                  <Globe size={10} />
                  {item.resource_name}
                  {isActive && <Check size={10} style={{ color: theme.from }} />}
                </button>
              );
            })}
          </div>
        </CollapsibleContent>
      </div>
    </Collapsible>
  );
}
