import { useSyncExternalStore } from 'react';
import type { GameState, Severity } from '@voltaje/sim';
import { gameData } from '@voltaje/data';
import { sim } from '../worker/client';
import type { Views } from '../worker/protocol';

export type ToastKind = 'info' | 'good' | 'warn' | 'bad';
export type WindowId = 'projects' | 'finance' | 'events' | 'project';

/** Entrada del registro de eventos (vive en la UI; al cargar se reconstruye con las líneas de tiempo). */
export interface LogEntry { id: number; tick: number; date: string; text: string; severity: Severity; projectId?: string }

/** Estado de la UI (no es estado del juego: eso vive en el worker). */
export interface UiState {
  screen: 'menu' | 'game';
  game: GameState | null;
  views: Views | null;
  speedId: string | null; // null = pausa
  layerId: string | null;
  layerOpacity: number;
  selected: { lat: number; lon: number } | null;
  dialog: null | 'save' | 'load' | 'menu';
  /** Ventana grande abierta (proyectos, finanzas, eventos o detalle de un proyecto). */
  window: WindowId | null;
  projectId: string | null;
  projectTab: string;
  /** Diálogo «Desarrollar proyecto aquí». */
  developAt: { lat: number; lon: number } | null;
  log: LogEntry[];
  unread: number;
  toasts: { id: number; text: string; kind: ToastKind; projectId?: string }[];
}

let state: UiState = {
  screen: 'menu',
  game: null,
  views: null,
  speedId: null,
  layerId: null,
  layerOpacity: 0.82,
  selected: null,
  dialog: null,
  window: null,
  projectId: null,
  projectTab: 'resumen',
  developAt: null,
  log: [],
  unread: 0,
  toasts: [],
};
const listeners = new Set<() => void>();
let toastSeq = 0;
let logSeq = 0;
export const LOG_MAX = 400;

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
  toast(text: string, kind: ToastKind = 'info', projectId?: string) {
    const id = ++toastSeq;
    ui.set((s) => ({ toasts: [...s.toasts.slice(-3), { id, text, kind, projectId }] }));
    setTimeout(() => ui.set((s) => ({ toasts: s.toasts.filter((t) => t.id !== id) })), kind === 'bad' ? 7000 : 4500);
  },
  log(entries: Omit<LogEntry, 'id'>[]) {
    if (!entries.length) return;
    const add = entries.map((e) => ({ ...e, id: ++logSeq }));
    ui.set((s) => ({ log: [...s.log, ...add].slice(-LOG_MAX), unread: s.window === 'events' ? 0 : s.unread + add.length }));
  },
  openWindow(w: WindowId | null) {
    ui.set((s) => ({ window: s.window === w ? null : w, unread: w === 'events' ? 0 : s.unread }));
    if (w !== 'project') sim.focus(null);
  },
  openProject(id: string, tab = 'resumen') {
    sim.focus(id);
    ui.set({ window: 'project', projectId: id, projectTab: tab });
  },
};

sim.onState(({ state: g, views }) => ui.set({ game: g, views }));

export function useUi<T>(sel: (s: UiState) => T): T {
  return useSyncExternalStore(ui.subscribe, () => sel(state));
}
