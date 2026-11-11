import type { Command, DispatchPolicy, FinancingPreview, PlantDispatchView, GameState, SimEvent, ViabilityResult } from '@voltaje/sim';
import type { BusinessPanel, FromWorker, QuoteReply, QuoteRequest, SiteEstimate, ToWorker, Views } from './protocol';

type Listener<T> = (v: T) => void;
type Reply = Extract<FromWorker, { reqId: number }>;

/** Puente entre la UI y el hilo de simulación. */
export class SimClient {
  private worker = new Worker(new URL('./sim.worker.ts', import.meta.url), { type: 'module' });
  private reqId = 0;
  private waiting = new Map<number, (m: Reply) => void>();
  private stateListeners = new Set<Listener<{ state: GameState; views: Views }>>();
  private eventListeners = new Set<Listener<SimEvent[]>>();
  state: GameState | null = null;
  views: Views | null = null;
  /** La grilla de recursos está cargada en el worker (hasta entonces los comandos esperan). */
  ready: Promise<void>;

  constructor() {
    let resolveReady!: () => void;
    this.ready = new Promise((r) => (resolveReady = r));
    this.worker.onmessage = (e: MessageEvent<FromWorker>) => {
      const m = e.data;
      if (m.t === 'snapshot') {
        this.state = m.state; this.views = m.views;
        this.stateListeners.forEach((l) => l(m));
      } else if (m.t === 'events') this.eventListeners.forEach((l) => l(m.events));
      else if (m.t === 'ready') { if (m.error) console.warn('Grilla no cargada en el worker:', m.error); resolveReady(); }
      else { this.waiting.get(m.reqId)?.(m); this.waiting.delete(m.reqId); }
    };
    const base = typeof document !== 'undefined' ? document.baseURI : location.href;
    this.send({ t: 'init', gridUrl: new URL('grid.json', base).href, binUrl: new URL('grid.bin', base).href });
  }

  private send(m: ToWorker) { this.worker.postMessage(m); }

  private request<T extends Reply['t']>(make: (reqId: number) => ToWorker): Promise<Extract<Reply, { t: T }>> {
    const id = ++this.reqId;
    return new Promise((resolve) => { this.waiting.set(id, resolve as (m: Reply) => void); this.send(make(id)); });
  }

  newGame(seed: number, companyName: string) { this.send({ t: 'new', seed, companyName }); }
  setSpeed(daysPerSecond: number) { this.send({ t: 'speed', daysPerSecond }); }
  command(cmd: Command) { this.send({ t: 'cmd', cmd }); }
  focus(projectId: string | null, tab?: string) { this.send({ t: 'focus', projectId, tab }); }
  /** País de la ventana Mercado eléctrico. */
  powerCountry(iso3: string) { this.send({ t: 'powerCountry', iso3 }); }
  /** Vista previa de una política de despacho (no cambia la partida). */
  async dispatchPreview(projectId: string, policy: DispatchPolicy): Promise<PlantDispatchView | null> {
    return (await this.request<'dispatchPreview'>((reqId) => ({ t: 'dispatchPreview', reqId, projectId, policy }))).view;
  }
  /** Solo para la prueba de humo: fuerza un evento del mundo. */
  debugWorldEvent(eventId: string, countries: string[] | null) { this.send({ t: 'debug', op: 'worldEvent', eventId, countries }); }
  quit() { this.state = null; this.views = null; this.send({ t: 'quit' }); }

  async save(): Promise<string> {
    const m = await this.request<'saved'>((reqId) => ({ t: 'save', reqId }));
    return m.text;
  }

  async load(text: string): Promise<void> {
    const m = await this.request<'loaded'>((reqId) => ({ t: 'load', text, reqId }));
    if (m.error) throw new Error(m.error);
  }

  async preview(techId: string, mw: number, lat: number, lon: number, to?: { lat: number; lon: number }): Promise<SiteEstimate> {
    await this.ready;
    return (await this.request<'preview'>((reqId) => ({ t: 'preview', reqId, techId, mw, lat, lon, to }))).estimate;
  }

  async viability(projectId: string, runs = 500): Promise<{ result?: ViabilityResult; error?: string; ms: number }> {
    return this.request<'viability'>((reqId) => ({ t: 'viability', reqId, projectId, runs }));
  }

  /** Vista previa del financiamiento (`previewFinancing` del motor). */
  async financePreview(projectId: string, lenderId: string, debtFraction: number, partnerShare: number): Promise<FinancingPreview | null> {
    return (await this.request<'finPreview'>((reqId) => ({ t: 'finPreview', reqId, projectId, lenderId, debtFraction, partnerShare }))).preview;
  }

  /** Cotización de una oferta (`selectBidQuote`) y proveedores de la tecnología. */
  async quote(req: QuoteRequest): Promise<QuoteReply> {
    return (await this.request<'quote'>((reqId) => ({ t: 'quote', reqId, req }))).reply;
  }

  /** Panel de negocio abierto (el worker solo calcula sus vistas mientras esté abierto). */
  panel(panel: BusinessPanel | null) { this.send({ t: 'panel', panel }); }
  /** País de la ficha (ventana Países). */
  country(iso3: string | null) { this.send({ t: 'country', iso3 }); }

  onState(l: Listener<{ state: GameState; views: Views }>) { this.stateListeners.add(l); return () => void this.stateListeners.delete(l); }
  onEvents(l: Listener<SimEvent[]>) { this.eventListeners.add(l); return () => void this.eventListeners.delete(l); }
}

export const sim = new SimClient();
