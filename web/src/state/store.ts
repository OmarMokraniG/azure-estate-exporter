import { create } from 'zustand';
import { persist } from 'zustand/middleware';

export interface SelectedScope {
  tenantId?: string;
  subscriptionId?: string;
  subscriptionName?: string;
  resourceGroup?: string;
}

export type Theme = 'light' | 'dark';
export type EstateSection = 'diagram' | 'resources' | 'terraform';

interface UiState {
  scope: SelectedScope;
  selectedResourceId: string | null;
  activeTab: EstateSection;
  theme: Theme;
  setScope: (s: Partial<SelectedScope>) => void;
  clearScope: () => void;
  selectResource: (id: string | null) => void;
  setTab: (t: EstateSection) => void;
  toggleTheme: () => void;
  setTheme: (t: Theme) => void;
}

export const useUi = create<UiState>()(
  persist(
    (set) => ({
      scope: {},
      selectedResourceId: null,
      activeTab: 'diagram',
      // Default to system preference at first load; persisted afterwards.
      theme:
        typeof window !== 'undefined' &&
        window.matchMedia?.('(prefers-color-scheme: dark)').matches
          ? 'dark'
          : 'light',
      setScope: (s) => set((prev) => ({ scope: { ...prev.scope, ...s } })),
      clearScope: () => set({ scope: {}, selectedResourceId: null }),
      selectResource: (id) => set({ selectedResourceId: id }),
      setTab: (t) => set({ activeTab: t }),
      toggleTheme: () =>
        set((s) => ({ theme: s.theme === 'dark' ? 'light' : 'dark' })),
      setTheme: (t) => set({ theme: t }),
    }),
    {
      name: 'aee-ui',
      // Persist only the user-pickable bits — don`t serialise the resource
      // selection or the current scope (those are fetched fresh on reload).
      partialize: (s) => ({ theme: s.theme, activeTab: s.activeTab }),
    },
  ),
);
