import { useSyncExternalStore } from 'react';
import type { GameState, Severity } from '@voltaje/sim';
import { gameData } from '@voltaje/data';
import { sim } from '../worker/client';
import type { BusinessPanel, Views } from '../worker/protocol';

export type ToastKind = 'info' | 'good' | 'warn' | 'bad';
export type WindowId = 'projects' | 'finance' | 'events' | 'project' | BusinessPanel;
const BUSINESS_PANELS = new Set<string>(['market', 'contracts', 'research', 'competitors', 'suppliers', 'countries', 'catalog', 'power', 'world']);
/** Elegido especial de la ventana Países: la pestaña de combustibles. */
export const FUELS_PICK = '@combustibles';

/** Enlace de una entrada del registro o aviso (proyecto u otra ventana con un elemento elegido). */
export type UiLink = { projectId: string } | { window: BusinessPanel; id?: string };

/** Entrada del registro de eventos (vive en la UI; al cargar se reconstruye con las líneas de tiempo). */
export interface LogEntry { id: number; tick: number; date: string; text: string; severity: Severity; projectId?: string; link?: UiLink }

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
  /** Diálogo «Desarrollar proyecto aquí» (`to`: extremo final de una línea o interconexión). */
  developAt: { lat: number; lon: number; to?: { lat: number; lon: number } } | null;
  /** Eligiendo en el globo el extremo final de una línea (el diálogo se oculta mientras tanto). */
  pickingRoute: boolean;
  /** Elemento elegido en cada ventana de negocio (oportunidad, contrato, nodo de I+D, competidor). */
  pick: Partial<Record<BusinessPanel, string>>;
  /** Diálogo «Armar oferta» para esta oportunidad. */
  bidFor: string | null;
  log: LogEntry[];
  unread: number;
  toasts: { id: number; text: string; kind: ToastKind; projectId?: string; link?: UiLink }[];
  /** Fase 5: avisos grandes de eventos graves del mundo (se cierran a mano o solos tras unos segundos). */
  banners: { id: number; uid: number; title: string; text: string; scope: string }[];
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
  pickingRoute: false,
  pick: {},
  bidFor: null,
  log: [],
  unread: 0,
  toasts: [],
  banners: [],
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
  toast(text: string, kind: ToastKind = 'info', projectId?: string, link?: UiLink) {
    const id = ++toastSeq;
    ui.set((s) => ({ toasts: [...s.toasts.slice(-3), { id, text, kind, projectId, link }] }));
    setTimeout(() => ui.set((s) => ({ toasts: s.toasts.filter((t) => t.id !== id) })), kind === 'bad' ? 7000 : 4500);
  },
  log(entries: Omit<LogEntry, 'id'>[]) {
    if (!entries.length) return;
    const add = entries.map((e) => ({ ...e, id: ++logSeq }));
    ui.set((s) => ({ log: [...s.log, ...add].slice(-LOG_MAX), unread: s.window === 'events' ? 0 : s.unread + add.length }));
  },
  openWindow(w: WindowId | null) {
    ui.set((s) => ({ window: s.window === w ? null : w, unread: w === 'events' ? 0 : s.unread, bidFor: null }));
    if (w !== 'project') sim.focus(null);
    const now = ui.get().window;
    sim.panel(now && BUSINESS_PANELS.has(now) ? (now as BusinessPanel) : null);
  },
  /** Abre una ventana de negocio con un elemento elegido (no la cierra si ya estaba abierta). */
  openPanel(w: BusinessPanel, id?: string) {
    sim.focus(null);
    sim.panel(w);
    if (w === 'countries' && id && id !== FUELS_PICK) sim.country(id);
    ui.set((s) => ({ window: w, bidFor: null, pick: id ? { ...s.pick, [w]: id } : s.pick }));
  },
  /** Ficha de un país (ventana Países). */
  openCountry(iso3: string) { ui.openPanel('countries', iso3); },
  follow(link: UiLink) {
    if ('projectId' in link) ui.openProject(link.projectId);
    else ui.openPanel(link.window, link.id);
  },
  openProject(id: string, tab = 'resumen') {
    sim.focus(id, tab);
    sim.panel(null);
    ui.set({ window: 'project', projectId: id, projectTab: tab });
  },
  /** Cambia la pestaña del detalle (el worker calcula el despacho solo en las pestañas que lo usan). */
  setProjectTab(tab: string) {
    const id = ui.get().projectId;
    if (id) sim.focus(id, tab);
    ui.set({ projectTab: tab });
  },
  /** Mercado eléctrico de un país. */
  openPowerMarket(iso3: string) {
    sim.powerCountry(iso3);
    ui.openPanel('power', iso3);
  },
  banner(b: { uid: number; title: string; text: string; scope: string }) {
    const id = ++toastSeq;
    ui.set((s) => ({ banners: [...s.banners.filter((x) => x.uid !== b.uid).slice(-1), { ...b, id }] }));
    setTimeout(() => ui.set((s) => ({ banners: s.banners.filter((x) => x.id !== id) })), 14000);
  },
};

sim.onState(({ state: g, views }) => ui.set({ game: g, views }));

export function useUi<T>(sel: (s: UiState) => T): T {
  return useSyncExternalStore(ui.subscribe, () => sel(state));
}
