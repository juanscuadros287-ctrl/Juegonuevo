import type { GameState } from '../core/state';
import type { SimContext } from '../core/context';
import type { SimEvent } from '../core/events';
import type { GameDate } from '../core/calendar';
import { Rng } from '../core/rng';
import { closeMonth, postCash } from '../finance/company';
import { projectDaily, projectMonthly, projectNewYear } from '../project/tick';
import { researchDaily, researchMonthly } from './research';
import { contractsDaily, contractsMonthly } from './contracts';
import { bondFeesMonthly } from './bonds';

/**
 * Avance de UN actor (jugador o vista de un competidor): proyectos, I+D y contratos.
 * Es el mismo código para todos: la IA no tiene reglas propias.
 */
export function actorDaily(state: GameState, ctx: SimContext, prev: GameDate, now: GameDate, events: SimEvent[]) {
  const rng = new Rng(state.rng.projects);
  for (const p of state.projects) projectDaily(state, ctx, p, rng, prev, events);
  if (now.year !== prev.year) for (const p of state.projects) projectNewYear(ctx, p, rng);
  if (ctx.data.research) researchDaily(state, ctx, new Rng(state.rng.business ?? state.rng.projects), events);
  if (ctx.data.clients) contractsDaily(state, ctx, prev.month, events);
}

/** Cierre del mes que terminó (`prev`): proyectos, contratos, I+D, garantías, gastos fijos, impuestos y caja. */
export function actorMonthly(state: GameState, ctx: SimContext | undefined, prev: GameDate, events: SimEvent[]) {
  if (ctx) {
    const rng = new Rng(state.rng.projects);
    for (const p of state.projects) projectMonthly(state, ctx, p, rng, prev.year, prev.month, events);
    if (ctx.data.clients && state.business) { contractsMonthly(state, ctx, prev.month, events); bondFeesMonthly(state, ctx); }
    if (ctx.data.research && state.business) researchMonthly(state);
  }
  const c = state.company;
  postCash(state, 'gastos_fijos', -c.monthlyFixedCostUsd, 'Gastos fijos (personal y oficina)');
  closeMonth(state, ctx ?? { data: { technologies: {}, studies: {}, findings: {}, suppliers: {}, countries: {} } }, prev.year, prev.month, events);
}
