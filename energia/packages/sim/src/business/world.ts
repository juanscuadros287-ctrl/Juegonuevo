import type { GameState } from '../core/state';
import type { SimContext } from '../core/context';
import type { SimEvent } from '../core/events';
import { seedStream } from '../core/rng';
import { initSupply } from '../supply/supply';
import { initCompetitors } from '../ai/competitors';
import { generateOpportunities } from './opportunities';

/**
 * Inicialización perezosa del mundo de la Fase 3 (en el primer `step`/`applyCommands` con datos): índices de
 * precios, reputación inicial del jugador, competidores IA y primeras oportunidades. Determinista.
 * También corre en partidas migradas desde la versión 2.
 */
export function ensureWorld(state: GameState, ctx: SimContext, events: SimEvent[]) {
  const m = state.market;
  if (!m || m.initialized) return;
  m.initialized = true;
  for (const k of ['supply', 'tenders', 'business']) if (!state.rng[k]) state.rng[k] = seedStream(state.seed, k);
  initSupply(state, ctx);
  const j = ctx.data.clients?.jugador;
  if (j) { state.business.reputation = j.reputacion_inicial; state.business.experienceMwBase = j.experiencia_mw_inicial; }
  if (m.competitorsEnabled && ctx.data.competitors) initCompetitors(state, ctx);
  generateOpportunities(state, ctx, events);
}
