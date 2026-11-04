import { fromEpochDay } from './calendar';
import { applyCommand, type Command } from './commands';
import type { SimContext } from './context';
import type { SimEvent } from './events';
import type { GameState } from './state';
import { actorDaily, actorMonthly } from '../business/tick';
import { ensureWorld } from '../business/world';
import { opportunitiesDaily, generateOpportunities } from '../business/opportunities';
import { supplyMonthly } from '../supply/supply';
import { competitorsDaily, competitorsDecide, competitorsMonthly } from '../ai/competitors';

export type { SimEvent } from './events';

/**
 * Avanza la simulación un día. Muta `state` y devuelve los eventos producidos.
 * Determinista: depende solo de `state`, `commands` y `ctx` (datos estáticos).
 * Sin `ctx` solo corren el calendario y los gastos fijos (útil en pruebas mínimas).
 * Con la empresa en quiebra no avanza (fin de la partida).
 *
 * Orden de un día: (1) comandos del jugador, (2) decisiones de la IA (mismos comandos), (3) avance del
 * jugador y de cada competidor (proyectos, I+D, contratos), (4) licitaciones (cierres y adjudicaciones),
 * (5) al cambiar de mes: cierre contable de cada actor, mercado de equipos y nuevas oportunidades.
 */
export function step(state: GameState, commands: readonly Command[] = [], ctx?: SimContext): SimEvent[] {
  if (state.finance.bankrupt) return [];
  const events = applyCommands(state, commands, ctx);
  if (ctx) competitorsDecide(state, ctx);

  const prev = fromEpochDay(state.startEpochDay + state.tick);
  state.tick += 1;
  const now = fromEpochDay(state.startEpochDay + state.tick);

  if (ctx) {
    actorDaily(state, ctx, prev, now, events);
    competitorsDaily(state, ctx, prev, now, events);
    opportunitiesDaily(state, ctx, events);
  }

  if (now.month !== prev.month) {
    actorMonthly(state, ctx, prev, events);
    if (ctx) {
      competitorsMonthly(state, ctx, prev, events);
      supplyMonthly(state, ctx, prev.year, prev.month, events);
      generateOpportunities(state, ctx, events);
    }
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
  if (ctx) ensureWorld(state, ctx, events);
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
