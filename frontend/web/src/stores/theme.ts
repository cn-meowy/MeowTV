import { create } from 'zustand';
import type { ThemeKey } from '@/app/components/Navbar';

const THEME_KEY = 'meowtv_theme';
const MODE_KEY = 'meowtv_mode';

export type ThemeMode = 'dark' | 'light';

interface ThemeState {
  activeTheme: ThemeKey;
  mode: ThemeMode;
  setActiveTheme: (theme: ThemeKey) => void;
  setMode: (mode: ThemeMode) => void;
  toggleMode: () => void;
}

export const useThemeStore = create<ThemeState>((set, get) => ({
  activeTheme: (localStorage.getItem(THEME_KEY) as ThemeKey) || 'violet',
  mode: (localStorage.getItem(MODE_KEY) as ThemeMode) || 'dark',
  setActiveTheme: (theme: ThemeKey) => {
    localStorage.setItem(THEME_KEY, theme);
    set({ activeTheme: theme });
  },
  setMode: (mode: ThemeMode) => {
    localStorage.setItem(MODE_KEY, mode);
    set({ mode });
  },
  toggleMode: () => {
    const next = get().mode === 'dark' ? 'light' : 'dark';
    localStorage.setItem(MODE_KEY, next);
    set({ mode: next });
  },
}));
