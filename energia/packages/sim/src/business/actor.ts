import type { GameState } from '../core/state';
import { seedStream } from '../core/rng';
import { PLAYER_ID, type CompetitorState } from './types';

/**
 * Vista de actor: un `GameState` cuyo `company`, `finance`, `projects`, `business` y flujos de RNG
 * de proyecto/negocio son los del competidor. Todo lo demás (tick, mercado, oportunidades, índices)
 * es compartido. Así la IA corre EXACTAMENTE el mismo código que el jugador (comandos, avance diario,
 * cierre de mes, quiebra) sin duplicar reglas. Los objetos son referencias: las mutaciones caen en el
 * competidor. El único escalar que se copia de vuelta es `nextProjectId` (ver `syncActorView`).
 */
export function actorView(state: GameState, comp: CompetitorState): GameState {
  const key = rngKey(comp.id);
  if (!state.rng[key]) state.rng[key] = seedStream(state.seed, key);
  return {
    ...state,
    actorId: comp.id,
    root: state.root ?? state,
    company: comp.company,
    finance: comp.finance,
    projects: comp.projects,
    nextProjectId: comp.nextProjectId,
    business: comp.business,
    rng: { ...state.rng, projects: state.rng[key], business: state.rng[key] },
  };
}

export function syncActorView(view: GameState, comp: CompetitorState) {
  comp.nextProjectId = view.nextProjectId;
}

export const rngKey = (competitorId: string) => `ai_${competitorId}`;

export function actorIdOf(state: GameState): string {
  return state.actorId ?? PLAYER_ID;
}

/** Ejecuta `fn` con la vista del actor indicado (jugador = el propio estado). */
export function withActor<T>(state: GameState, actorId: string, fn: (view: GameState) => T): T | undefined {
  if (actorId === PLAYER_ID) return fn(state);
  const comp = state.competitors.find((c) => c.id === actorId);
  if (!comp) return undefined;
  const v = actorView(state, comp);
  const r = fn(v);
  syncActorView(v, comp);
  return r;
}

export function actorName(state: GameState, actorId: string): string {
  if (actorId === PLAYER_ID) return state.company.name;
  return state.competitors.find((c) => c.id === actorId)?.name ?? actorId;
}

/** Experiencia pública (MW): plantas propias que llegaron a operar + EPC entregados + historial previo. */
export function experienceMw(state: GameState): number {
  let mw = state.business?.experienceMwBase ?? 0;
  for (const p of state.projects) if (p.operation) mw += p.mw;
  return mw + (state.business?.epcDeliveredMw ?? 0);
}

export function clampReputation(v: number): number {
  return Math.max(0, Math.min(100, v));
}

export function changeReputation(state: GameState, delta: number) {
  if (state.business) state.business.reputation = clampReputation(state.business.reputation + delta);
}
