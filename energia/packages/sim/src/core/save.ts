import { SAVE_VERSION, newFinanceState, type GameState } from './state';
import { seedStream } from './rng';
import { newBusinessState, newMarketState } from '../business/types';

export interface SaveFile {
  format: 'voltaje-save';
  saveVersion: number;
  state: GameState;
}

/** Migraciones de partidas: clave = versión de origen. */
const MIGRATIONS: Record<number, (s: any) => any> = {
  // v1 (Fase 1) → v2 (Fase 2): la empresa empieza sin proyectos y con la contabilidad vacía.
  1: (s) => ({ ...s, saveVersion: 2, projects: [], nextProjectId: 1, finance: newFinanceState() }),
  // v2 (Fase 2) → v3 (Fase 3): negocio vacío del jugador, mundo sin inicializar (se arma en el próximo step
  // con datos: competidores, índices y oportunidades) y flujos de RNG nuevos sembrados desde la semilla.
  2: (s) => ({
    ...s, saveVersion: 3, business: newBusinessState(), market: newMarketState(true), competitors: [],
    rng: { ...s.rng, supply: seedStream(s.seed, 'supply'), tenders: seedStream(s.seed, 'tenders'), business: seedStream(s.seed, 'business') },
  }),
  // v3 (Fase 3) → v4 (Fase 4): presencia por país vacía (jugador y competidores), flujos `fx` y `fuels`; los tipos de
  // cambio y los índices de combustibles se inicializan en el próximo step con datos (todos en 1 = precios del YAML).
  3: (s) => ({
    ...s, saveVersion: 4,
    business: { ...s.business, presence: s.business?.presence ?? {} },
    competitors: (s.competitors ?? []).map((c: any) => ({ ...c, business: { ...c.business, presence: c.business?.presence ?? {} } })),
    rng: { ...s.rng, fx: s.rng.fx ?? seedStream(s.seed, 'fx'), fuels: s.rng.fuels ?? seedStream(s.seed, 'fuels') },
  }),
};

export function serialize(state: GameState): string {
  if (state.actorId !== undefined) throw new Error('No se puede guardar una vista de actor.');
  const file: SaveFile = { format: 'voltaje-save', saveVersion: SAVE_VERSION, state };
  return JSON.stringify(file);
}

export function deserialize(text: string): GameState {
  let file: any;
  try {
    file = JSON.parse(text);
  } catch {
    throw new Error('El archivo de partida está dañado (no es JSON válido).');
  }
  if (file?.format !== 'voltaje-save') throw new Error('El archivo no es una partida de Voltaje.');
  let v = file.saveVersion;
  if (typeof v !== 'number') throw new Error('Partida sin versión.');
  if (v > SAVE_VERSION) throw new Error(`La partida es de una versión más nueva del juego (${v}).`);
  let state = file.state;
  while (v < SAVE_VERSION) {
    const m = MIGRATIONS[v];
    if (!m) throw new Error(`No hay migración desde la versión ${v}.`);
    state = m(state);
    v++;
  }
  validate(state);
  return state as GameState;
}

function validate(s: any) {
  const ok =
    s && typeof s.tick === 'number' && typeof s.seed === 'number' && typeof s.startEpochDay === 'number' &&
    s.company && typeof s.company.cashUsd === 'number' && s.rng && typeof s.rng === 'object' &&
    Array.isArray(s.projects) && typeof s.nextProjectId === 'number' && s.finance && typeof s.finance === 'object' &&
    s.business && typeof s.business === 'object' && s.market && Array.isArray(s.market.opportunities) && Array.isArray(s.competitors);
  if (!ok) throw new Error('La partida tiene un formato inválido.');
  for (const k of Object.keys(s.rng)) {
    const r = s.rng[k];
    if (!Array.isArray(r) || r.length !== 4 || r.some((x: unknown) => typeof x !== 'number')) throw new Error(`Estado RNG inválido: ${k}`);
  }
}

/** Hash estable del estado (para pruebas de determinismo). */
export function stateHash(state: GameState): string {
  const text = canonical(state);
  let h1 = 0x811c9dc5, h2 = 0x01000193;
  for (let i = 0; i < text.length; i++) {
    const c = text.charCodeAt(i);
    h1 = Math.imul(h1 ^ c, 0x01000193);
    h2 = Math.imul(h2 ^ c, 0x5bd1e995);
  }
  return (h1 >>> 0).toString(16).padStart(8, '0') + (h2 >>> 0).toString(16).padStart(8, '0');
}

function canonical(v: unknown): string {
  if (Array.isArray(v)) return '[' + v.map(canonical).join(',') + ']';
  if (v && typeof v === 'object') {
    // Las claves con valor `undefined` no se guardan en JSON: se ignoran para que guardar/cargar no cambie el hash.
    return '{' + Object.keys(v as object).filter((k) => (v as any)[k] !== undefined).sort().map((k) => JSON.stringify(k) + ':' + canonical((v as any)[k])).join(',') + '}';
  }
  return JSON.stringify(v);
}
