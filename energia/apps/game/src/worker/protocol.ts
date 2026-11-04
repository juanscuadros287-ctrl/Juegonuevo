import type { Command, GameState, SimEvent } from '@voltaje/sim';

export type ToWorker =
  | { t: 'new'; seed: number; companyName: string }
  | { t: 'load'; text: string; reqId: number }
  | { t: 'speed'; daysPerSecond: number } // 0 = pausa
  | { t: 'cmd'; cmd: Command }
  | { t: 'save'; reqId: number }
  | { t: 'quit' };

export type FromWorker =
  | { t: 'snapshot'; state: GameState }
  | { t: 'events'; events: SimEvent[] }
  | { t: 'saved'; reqId: number; text: string }
  | { t: 'loaded'; reqId: number; error?: string };
