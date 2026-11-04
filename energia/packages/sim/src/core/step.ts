import { fromEpochDay } from './calendar';
import { applyCommand, type Command } from './commands';
import type { SimContext } from './context';
import type { SimEvent } from './events';
import { Rng } from './rng';
import type { GameState } from './state';
import { closeMonth, postCash } from '../finance/company';
import { projectDaily, projectMonthly, projectNewYear } from '../project/tick';

export type { SimEvent } from './events';

/**
 * Avanza la simulación un día. Muta `state` y devuelve los eventos producidos.
 * Determinista: depende solo de `state`, `commands` y `ctx` (datos estáticos).
 * Sin `ctx` solo corren el calendario y los gastos fijos (útil en pruebas mínimas).
 * Con la empresa en quiebra no avanza (fin de la partida).
 */
export function step(state: GameState, commands: readonly Command[] = [], ctx?: SimContext): SimEvent[] {
  if (state.finance.bankrupt) return [];
  const events = applyCommands(state, commands, ctx);

  const prev = fromEpochDay(state.startEpochDay + state.tick);
  state.tick += 1;
  const now = fromEpochDay(state.startEpochDay + state.tick);

  if (ctx) {
    const rng = new Rng(state.rng.projects);
    for (const p of state.projects) projectDaily(state, ctx, p, rng, prev, events);
    if (now.year !== prev.year) for (const p of state.projects) projectNewYear(ctx, p, rng);
  }

  if (now.month !== prev.month) {
    // Cierre del mes que terminó: proyectos, gastos fijos (nada es gratis), impuestos y caja.
    if (ctx) {
      const rng = new Rng(state.rng.projects);
      for (const p of state.projects) projectMonthly(state, ctx, p, rng, prev.year, prev.month, events);
    }
    const c = state.company;
    postCash(state, 'gastos_fijos', -c.monthlyFixedCostUsd, 'Gastos fijos (personal y oficina)');
    if (ctx) closeMonth(state, ctx, prev.year, prev.month, events);
    else closeMonth(state, { data: { technologies: {}, studies: {}, findings: {}, suppliers: {}, countries: {} } }, prev.year, prev.month, events);
    events.push({ type: 'newMonth', year: now.year, month: now.month });
    if (now.year !== prev.year) events.push({ type: 'newYear', year: now.year });
  }
  return events;
}

/**
 * Aplica comandos en el tick actual sin avanzar el tiempo (p. ej. con el juego en pausa).
 * Equivale a pasarlos al inicio del siguiente step().
 */
export function applyCommands(state: GameState, commands: readonly Command[], ctx?: SimContext): SimEvent[] {
  const events: SimEvent[] = [];
  for (const cmd of commands) {
    const r = applyCommand(state, cmd, ctx, events);
    if (!r.ok) events.push({ type: 'commandRejected', command: cmd, error: r.error });
  }
  return events;
}

/** Fecha actual de la partida. */
export function currentDate(state: GameState) {
  return fromEpochDay(state.startEpochDay + state.tick);
}
