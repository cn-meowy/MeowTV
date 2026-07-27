import { create } from 'zustand';
import {
  getSearchHistoryList,
  addSearchHistory as apiAdd,
  deleteSearchHistory as apiDelete,
  clearSearchHistory as apiClear,
} from '@/api/user-data';
import type { SearchHistoryItem } from '@/types/api';

const STORAGE_KEY = 'meowtv_search_history';
const MAX_LOCAL = 50;

interface SearchHistoryState {
  keywords: string[];
  loaded: boolean;
  /** 从后端加载搜索历史 */
  fetchFromServer: () => Promise<void>;
  /** 新增搜索记录 */
  addKeyword: (keyword: string) => void;
  /** 按 keyword 删除单条 */
  removeKeyword: (keyword: string) => void;
  /** 清空搜索历史 */
  clearAll: () => void;
}

function loadLocal(): string[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function saveLocal(keywords: string[]): void {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(keywords.slice(0, MAX_LOCAL)));
  } catch { /* ignore */ }
}

export const useSearchHistoryStore = create<SearchHistoryState>((set, get) => ({
  keywords: loadLocal(),
  loaded: false,

  fetchFromServer: async () => {
    if (get().loaded) return;
    try {
      const items = await getSearchHistoryList(MAX_LOCAL);
      const keywords = items.map((item: SearchHistoryItem) => item.keyword);

      // 数据迁移：后端为空但本地有数据 → 批量同步到后端
      const localKeywords = get().keywords;
      if (keywords.length === 0 && localKeywords.length > 0) {
        for (const kw of localKeywords) {
          apiAdd(kw).catch(() => {});
        }
        set({ loaded: true });
        return; // 保留本地数据，后端已异步同步
      }

      saveLocal(keywords);
      set({ keywords, loaded: true });
    } catch {
      set({ loaded: true });
    }
  },

  addKeyword: (keyword: string) => {
    const trimmed = keyword.trim();
    if (!trimmed) return;

    // 乐观更新本地
    set((state) => {
      const filtered = state.keywords.filter((k) => k !== trimmed);
      const updated = [trimmed, ...filtered].slice(0, MAX_LOCAL);
      saveLocal(updated);
      return { keywords: updated };
    });

    // 异步写后端
    apiAdd(trimmed).catch(() => {});
  },

  removeKeyword: (keyword: string) => {
    // 乐观删除本地
    set((state) => {
      const updated = state.keywords.filter((k) => k !== keyword);
      saveLocal(updated);
      return { keywords: updated };
    });

    // 后端需要 id，先查询再删除
    getSearchHistoryList(MAX_LOCAL).then((items) => {
      const item = items.find((i: SearchHistoryItem) => i.keyword === keyword);
      if (item) {
        apiDelete(item.id).catch(() => {});
      }
    }).catch(() => {});
  },

  clearAll: () => {
    saveLocal([]);
    set({ keywords: [] });
    apiClear().catch(() => {});
  },
}));
