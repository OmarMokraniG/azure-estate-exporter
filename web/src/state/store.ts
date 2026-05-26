import { create } from 'zustand';

export interface SelectedScope {
  tenantId?: string;
  subscriptionId?: string;
  subscriptionName?: string;
  resourceGroup?: string;
}

interface UiState {
  scope: SelectedScope;
  selectedResourceId: string | null;
  activeTab: 'diagram' | 'resources' | 'terraform';
  setScope: (s: Partial<SelectedScope>) => void;
  clearScope: () => void;
  selectResource: (id: string | null) => void;
  setTab: (t: UiState['activeTab']) => void;
}

export const useUi = create<UiState>((set) => ({
  scope: {},
  selectedResourceId: null,
  activeTab: 'diagram',
  setScope: (s) => set((prev) => ({ scope: { ...prev.scope, ...s } })),
  clearScope: () => set({ scope: {}, selectedResourceId: null }),
  selectResource: (id) => set({ selectedResourceId: id }),
  setTab: (t) => set({ activeTab: t }),
}));
