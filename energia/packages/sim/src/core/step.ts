import { fromEpochDay } from './calendar';
import { applyCommand, type Command } from './commands';
import type { GameState } from './state';

export type SimEvent =
  | { type: 'newMonth'; year: number; month: number }
  | { type: 'newYear'; year: number }
  | { type: 'commandRejected'; command: Command; error: string }
  | { type: 'cashNegative'; cashUsd: number };

const LEDGER_KEEP_DAYS = 730;

/**
 * Avanza la simulación un día. Muta `state` y devuelve los eventos producidos.
 * Determinista: depende solo de `state` y `commands`.
 */
export function step(state: GameState, commands: readonly Command[] = []): SimEvent[] {
  const events = applyCommands(state, commands);

  const prev = fromEpochDay(state.startEpochDay + state.tick);
  state.tick += 1;
  const now = fromEpochDay(state.startEpochDay + state.tick);

  if (now.month !== prev.month) {
    // Gastos fijos del mes que terminó: nada es gratis.
    const c = state.company;
    c.cashUsd -= c.monthlyFixedCostUsd;
    c.ledger.push({ day: state.tick, concept: 'Gastos fijos (personal y oficina)', amountUsd: -c.monthlyFixedCostUsd });
    const cutoff = state.tick - LEDGER_KEEP_DAYS;
    if (c.ledger.length && c.ledger[0].day < cutoff) c.ledger = c.ledger.filter((e) => e.day >= cutoff);
    events.push({ type: 'newMonth', year: now.year, month: now.month });
    if (now.year !== prev.year) events.push({ type: 'newYear', year: now.year });
    if (c.cashUsd < 0) events.push({ type: 'cashNegative', cashUsd: c.cashUsd });
  }
  return events;
}

/**
 * Aplica comandos en el tick actual sin avanzar el tiempo (p. ej. con el juego en pausa).
 * Equivale a pasarlos al inicio del siguiente step().
 */
export function applyCommands(state: GameState, commands: readonly Command[]): SimEvent[] {
  const events: SimEvent[] = [];
  for (const cmd of commands) {
    const r = applyCommand(state, cmd);
    if (!r.ok) events.push({ type: 'commandRejected', command: cmd, error: r.error });
  }
  return events;
}

/** Fecha actual de la partida. */
export function currentDate(state: GameState) {
  return fromEpochDay(state.startEpochDay + state.tick);
}
