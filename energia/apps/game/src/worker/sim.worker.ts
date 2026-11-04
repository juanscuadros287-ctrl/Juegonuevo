/// <reference lib="webworker" />
/**
 * Hilo de simulación: dueño único del GameState. Avanza días según la velocidad y
 * envía instantáneas de solo lectura a la UI.
 */
import { applyCommands, createNewGame, deserialize, serialize, step, type Command, type GameState, type SimContext, type SimEvent } from '@voltaje/sim';
import { gameData } from '@voltaje/data';
import type { FromWorker, ToWorker } from './protocol';

const post = (m: FromWorker) => (self as unknown as Worker).postMessage(m);

let state: GameState | null = null;
// Fase 2: datos del motor. La grilla (necesaria para crear proyectos) la agregará la UI.
const ctx: SimContext = { data: gameData.simData };
let daysPerSecond = 0;
let pending: Command[] = [];
let carry = 0;
let last = performance.now();
const MAX_DAYS_PER_TICK = 60;

function snapshot() {
  if (state) post({ t: 'snapshot', state });
}

function advance(days: number) {
  if (!state) return;
  const events: SimEvent[] = [];
  for (let d = 0; d < days; d++) {
    events.push(...step(state, d === 0 ? pending : [], ctx));
    if (d === 0) pending = [];
  }
  if (events.length) post({ t: 'events', events });
  snapshot();
}

setInterval(() => {
  const now = performance.now();
  const dt = (now - last) / 1000;
  last = now;
  if (!state) return;
  if (daysPerSecond <= 0) {
    // en pausa los comandos se aplican sin avanzar el tiempo
    if (pending.length) {
      const events = applyCommands(state, pending, ctx);
      pending = [];
      if (events.length) post({ t: 'events', events });
      snapshot();
    }
    return;
  }
  carry += dt * daysPerSecond;
  const days = Math.min(MAX_DAYS_PER_TICK, Math.floor(carry));
  if (days > 0) {
    carry -= days;
    advance(days);
  }
}, 50);

self.onmessage = (e: MessageEvent<ToWorker>) => {
  const m = e.data;
  switch (m.t) {
    case 'new':
      state = createNewGame(gameData.sim, { seed: m.seed, companyName: m.companyName });
      pending = []; carry = 0; daysPerSecond = 0;
      snapshot();
      break;
    case 'load':
      try {
        state = deserialize(m.text);
        pending = []; carry = 0; daysPerSecond = 0;
        post({ t: 'loaded', reqId: m.reqId });
        snapshot();
      } catch (err) {
        post({ t: 'loaded', reqId: m.reqId, error: (err as Error).message });
      }
      break;
    case 'speed':
      daysPerSecond = m.daysPerSecond;
      last = performance.now();
      carry = 0;
      break;
    case 'cmd':
      pending.push(m.cmd);
      break;
    case 'save':
      if (state) post({ t: 'saved', reqId: m.reqId, text: serialize(state) });
      break;
    case 'quit':
      state = null; daysPerSecond = 0; pending = [];
      break;
  }
};
