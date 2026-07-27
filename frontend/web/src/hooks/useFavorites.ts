import { useCallback } from 'react';
import { useFavoritesStore, type FavoriteRecord } from '@/stores/favorites';

interface UseFavoritesReturn {
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
  /** 获取所有收藏列表 */
  getAllFavorites: () => FavoriteRecord[];
  /** 清空所有收藏 */
  clearAll: () => void;
}

export function useFavorites(): UseFavoritesReturn {
  const fetchFromServer = useFavoritesStore((s) => s.fetchFromServer);
  const add = useFavoritesStore((s) => s.addFavorite);
  const remove = useFavoritesStore((s) => s.removeFavorite);
  const toggle = useFavoritesStore((s) => s.toggleFavorite);
  const isFav = useFavoritesStore((s) => s.isFavorite);
  const getAll = useFavoritesStore((s) => s.getAllFavorites);
  const clearAllStore = useFavoritesStore((s) => s.clearAll);

  const fetchFromServerCb = useCallback(() => {
    return fetchFromServer();
  }, [fetchFromServer]);

  const addFavorite = useCallback(
    (record: FavoriteRecord) => {
      add({ ...record, createdAt: Date.now() });
    },
    [add]
  );

  const removeFavorite = useCallback(
    (vodId: number, resourceDomain: string, doubanId?: string) => {
      remove(vodId, resourceDomain, doubanId);
    },
    [remove]
  );

  const toggleFavorite = useCallback(
    (record: FavoriteRecord) => {
      toggle(record);
    },
    [toggle]
  );

  const isFavorite = useCallback(
    (vodId: number, resourceDomain: string, doubanId?: string) => {
      return isFav(vodId, resourceDomain, doubanId);
    },
    [isFav]
  );

  const getAllFavorites = useCallback(() => {
    return getAll();
  }, [getAll]);

  const clearAll = useCallback(() => {
    clearAllStore();
  }, [clearAllStore]);

  return { fetchFromServer: fetchFromServerCb, addFavorite, removeFavorite, toggleFavorite, isFavorite, getAllFavorites, clearAll };
}
