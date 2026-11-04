import { useSyncExternalStore } from 'react';
import type { GameState } from '@voltaje/sim';
import { gameData } from '@voltaje/data';
import { sim } from '../worker/client';

/** Estado de la UI (no es estado del juego: eso vive en el worker). */
export interface UiState {
  screen: 'menu' | 'game';
  game: GameState | null;
  speedId: string | null; // null = pausa
  layerId: string | null;
  layerOpacity: number;
  selected: { lat: number; lon: number } | null;
  dialog: null | 'save' | 'load' | 'menu';
  toasts: { id: number; text: string; kind: 'info' | 'good' | 'warn' | 'bad' }[];
}

let state: UiState = {
  screen: 'menu',
  game: null,
  speedId: null,
  layerId: null,
  layerOpacity: 0.82,
  selected: null,
  dialog: null,
  toasts: [],
};
const listeners = new Set<() => void>();

export const ui = {
  get: () => state,
  set(patch: Partial<UiState> | ((s: UiState) => Partial<UiState>)) {
    state = { ...state, ...(typeof patch === 'function' ? patch(state) : patch) };
    listeners.forEach((l) => l());
  },
  subscribe(l: () => void) { listeners.add(l); return () => void listeners.delete(l); },
  setSpeed(id: string | null) {
    const sp = gameData.game.velocidades.find((v) => v.id === id);
    sim.setSpeed(sp ? sp.dias_por_segundo : 0);
    ui.set({ speedId: sp ? sp.id : null });
  },
  toast(text: string, kind: UiState['toasts'][number]['kind'] = 'info') {
    const id = Math.random();
    ui.set((s) => ({ toasts: [...s.toasts.slice(-3), { id, text, kind }] }));
    setTimeout(() => ui.set((s) => ({ toasts: s.toasts.filter((t) => t.id !== id) })), 4500);
  },
};

sim.onState((g) => ui.set({ game: g }));

export function useUi<T>(sel: (s: UiState) => T): T {
  return useSyncExternalStore(ui.subscribe, () => sel(state));
}
