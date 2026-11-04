import type { Command, GameState, SimEvent } from '@voltaje/sim';
import type { FromWorker, ToWorker } from './protocol';

type Listener<T> = (v: T) => void;

/** Puente entre la UI y el hilo de simulación. */
export class SimClient {
  private worker = new Worker(new URL('./sim.worker.ts', import.meta.url), { type: 'module' });
  private reqId = 0;
  private waiting = new Map<number, (m: FromWorker) => void>();
  private stateListeners = new Set<Listener<GameState>>();
  private eventListeners = new Set<Listener<SimEvent[]>>();
  state: GameState | null = null;

  constructor() {
    this.worker.onmessage = (e: MessageEvent<FromWorker>) => {
      const m = e.data;
      if (m.t === 'snapshot') { this.state = m.state; this.stateListeners.forEach((l) => l(m.state)); }
      else if (m.t === 'events') this.eventListeners.forEach((l) => l(m.events));
      else if (m.t === 'saved' || m.t === 'loaded') { this.waiting.get(m.reqId)?.(m); this.waiting.delete(m.reqId); }
    };
  }

  private send(m: ToWorker) { this.worker.postMessage(m); }

  private request(make: (reqId: number) => ToWorker): Promise<FromWorker> {
    const id = ++this.reqId;
    return new Promise((resolve) => { this.waiting.set(id, resolve); this.send(make(id)); });
  }

  newGame(seed: number, companyName: string) { this.send({ t: 'new', seed, companyName }); }
  setSpeed(daysPerSecond: number) { this.send({ t: 'speed', daysPerSecond }); }
  command(cmd: Command) { this.send({ t: 'cmd', cmd }); }
  quit() { this.state = null; this.send({ t: 'quit' }); }

  async save(): Promise<string> {
    const m = await this.request((reqId) => ({ t: 'save', reqId }));
    if (m.t !== 'saved') throw new Error('Respuesta inesperada');
    return m.text;
  }

  async load(text: string): Promise<void> {
    const m = await this.request((reqId) => ({ t: 'load', text, reqId }));
    if (m.t === 'loaded' && m.error) throw new Error(m.error);
  }

  onState(l: Listener<GameState>) { this.stateListeners.add(l); return () => void this.stateListeners.delete(l); }
  onEvents(l: Listener<SimEvent[]>) { this.eventListeners.add(l); return () => void this.eventListeners.delete(l); }
}

export const sim = new SimClient();
