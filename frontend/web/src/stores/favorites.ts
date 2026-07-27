import { create } from 'zustand';
import {
  getFavoritesList,
  addFavorite as apiAdd,
  removeFavorite as apiRemove,
  toggleFavorite as apiToggle,
  checkFavorite as apiCheck,
  clearFavorites as apiClear,
} from '@/api/user-data';
import type { FavoriteItem } from '@/types/api';

const STORAGE_KEY = 'meowtv_favorites';

export interface FavoriteRecord {
  vodId: number;
  vodName: string;
  vodPic?: string;
  doubanId: string;
  groupKey: string;
  site: string;
  resourceDomain: string;
  resourceName: string;
  createdAt: number; // timestamp ms
}

interface FavoritesState {
  favorites: FavoriteRecord[];
  loaded: boolean;
  loading: boolean;
  /** 从后端加载收藏列表 */
  fetchFromServer: () => Promise<void>;
  /** 添加收藏 */
  addFavorite: (record: FavoriteRecord) => void;
  /** 取消收藏（支持 vodId+resourceDomain 或 doubanId） */
  removeFavorite: (vodId: number, resourceDomain: string, doubanId?: string) => void;
  /** 切换收藏状态 */
  toggleFavorite: (record: FavoriteRecord) => void;
  /** 判断是否已收藏（支持 vodId+resourceDomain 或 doubanId） */
  isFavorite: (vodId: number, resourceDomain: string, doubanId?: string) => boolean;
  /** 清空所有收藏 */
  clearAll: () => void;
  /** 获取所有收藏列表 */
  getAllFavorites: () => FavoriteRecord[];
}

function loadFavorites(): FavoriteRecord[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function saveFavorites(favorites: FavoriteRecord[]): void {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(favorites));
  } catch { /* ignore */ }
}

/** 将后端 FavoriteItem 转为本地 FavoriteRecord */
function toItem(r: FavoriteItem): FavoriteRecord {
  return {
    vodId: r.vod_id,
    vodName: r.vod_name,
    vodPic: r.vod_pic,
    doubanId: r.douban_id || "",
    groupKey: r.group_key,
    site: r.site,
    resourceDomain: r.resource_domain,
    resourceName: r.resource_name,
    createdAt: r.created_at,
  };
}

/** 判断两条记录是否为同一收藏（与后端优先逻辑一致：有 doubanId 就只用 doubanId，否则用 vodId+resourceDomain） */
function isSameFavorite(f: FavoriteRecord, vodId: number, resourceDomain: string, doubanId?: string): boolean {
  // 与后端 IsFavorite/Remove 一致：有 doubanId 就只用 doubanId 匹配
  if (doubanId) {
    return f.doubanId === doubanId;
  }
  // 否则用 vodId + resourceDomain 匹配
  return vodId > 0 && resourceDomain !== "" && f.vodId === vodId && f.resourceDomain === resourceDomain;
}

export const useFavoritesStore = create<FavoritesState>((set, get) => ({
  favorites: loadFavorites(),
  loaded: false,
  loading: false,

  fetchFromServer: async () => {
    if (get().loaded || get().loading) return;
    set({ loading: true });
    try {
      const resp = await getFavoritesList(200, 0);
      const favorites = resp.items.map(toItem);

      // 数据迁移：后端为空但本地有数据 → 批量同步到后端
      const localFavorites = get().favorites;
      if (favorites.length === 0 && localFavorites.length > 0) {
        for (const f of localFavorites) {
          apiAdd({
            vod_id: f.vodId, vod_name: f.vodName, vod_pic: f.vodPic ?? '',
            douban_id: f.doubanId ?? '',
            group_key: f.groupKey, site: f.site,
            resource_domain: f.resourceDomain, resource_name: f.resourceName,
          }).catch(() => {});
        }
        set({ loaded: true, loading: false });
        return;
      }

      saveFavorites(favorites);
      set({ favorites, loaded: true, loading: false });
    } catch {
      set({ loaded: true, loading: false });
    }
  },

  addFavorite: (record) => {
    set((state) => {
      if (state.favorites.some(
        (f) => isSameFavorite(f, record.vodId, record.resourceDomain, record.doubanId)
      )) {
        return state;
      }
      const updated = [record, ...state.favorites];
      saveFavorites(updated);
      return { favorites: updated };
    });

    apiAdd({
      vod_id: record.vodId,
      vod_name: record.vodName,
      vod_pic: record.vodPic ?? '',
      douban_id: record.doubanId ?? '',
      group_key: record.groupKey,
      site: record.site,
      resource_domain: record.resourceDomain,
      resource_name: record.resourceName,
    }).catch(() => {});
  },

  removeFavorite: (vodId, resourceDomain, doubanId) => {
    set((state) => {
      const updated = state.favorites.filter(
        (f) => !isSameFavorite(f, vodId, resourceDomain, doubanId)
      );
      saveFavorites(updated);
      return { favorites: updated };
    });

    apiRemove({ vod_id: vodId, resource_domain: resourceDomain, douban_id: doubanId ?? '' }).catch(() => {});
  },

  toggleFavorite: (record) => {
    const isFav = get().isFavorite(record.vodId, record.resourceDomain, record.doubanId);

    // 乐观更新本地
    if (isFav) {
      get().removeFavorite(record.vodId, record.resourceDomain, record.doubanId);
    } else {
      get().addFavorite(record);
    }

    // 后端 toggle
    apiToggle({
      vod_id: record.vodId,
      vod_name: record.vodName,
      vod_pic: record.vodPic ?? '',
      douban_id: record.doubanId ?? '',
      group_key: record.groupKey,
      site: record.site,
      resource_domain: record.resourceDomain,
      resource_name: record.resourceName,
    }).catch(() => {});
  },

  isFavorite: (vodId, resourceDomain, doubanId) => {
    return get().favorites.some(
      (f) => isSameFavorite(f, vodId, resourceDomain, doubanId)
    );
  },

  clearAll: () => {
    saveFavorites([]);
    set({ favorites: [] });
    apiClear().catch(() => {});
  },

  getAllFavorites: () => {
    return get().favorites;
  },
}));
