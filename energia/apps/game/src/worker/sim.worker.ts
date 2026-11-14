/// <reference lib="webworker" />
/**
 * Hilo de simulación: dueño único del GameState. Avanza días según la velocidad y
 * envía instantáneas de solo lectura a la UI junto con las vistas de los selectores
 * (que necesitan datos + grilla, por eso se calculan aquí).
 */
import {
  applyCommands, checkViability, createNewGame, deserialize, previewFinancing, previewSite, ResourceGrid, selectBidQuote, selectBusinessSummary,
  selectCompanyFinancials, selectCompetitors, selectContracts, selectMyBids, selectOpportunities, selectProjectDetail, selectProjects, selectResearchTree,
  selectSupplierCatalog, serialize, step, PLAYER_ID, selectCountries, selectCountrySheet, selectFuelMarkets, selectTechCatalog, type TechCatalogEntry,
  opportunityLocation, selectClimate, selectMarketShareHistory, selectPlantDispatch, selectPowerMarket, selectPowerMarkets, selectRevenueBySource, selectWorldEvents,
  triggerWorldEvent, type PlantDispatchView, type Command, type GameState, type GridMeta, type SimContext, type SimEvent,
} from '@voltaje/sim';
import { gameData } from '@voltaje/data';
import { runAutopilot } from './devPilot';
import type { BusinessPanel, BusinessViews, FromWorker, OpportunityMark, PowerViews, QuoteReply, QuoteRequest, SiteEstimate, ToWorker, Views } from './protocol';

const post = (m: FromWorker) => (self as unknown as Worker).postMessage(m);

let state: GameState | null = null;
const ctx: SimContext = { data: gameData.simData };
let gridReady = false;
let daysPerSecond = 0;
let pending: Command[] = [];
let carry = 0;
let last = performance.now();
let focus: string | null = null;
let panel: BusinessPanel | null = null;
let country: string | null = null;
/** Fase 5: país de la ventana Mercado eléctrico (por defecto el de origen). */
let powerIso: string | null = null;
/** Pestaña del proyecto enfocado: el despacho (más costoso) solo se calcula en las pestañas que lo usan. */
let focusTab: string | null = null;
const DISPATCH_TABS = new Set(['despacho', 'seguro', 'operacion']);
/** Ubicación aproximada de cada oportunidad (determinista: se calcula una vez). */
const oppLoc = new Map<string, { lat: number; lon: number } | null>();
/** El catálogo (LCOE típico de 20 tecnologías × 13 países) cuesta: se recalcula al cambiar de mes o de I+D. */
let catalogCache: { key: string; entries: TechCatalogEntry[] } | null = null;
function catalog(s: GameState): TechCatalogEntry[] {
  const key = `${s.seed}|${Math.floor(s.tick / 30)}|${s.business?.research.completed.length ?? 0}`;
  if (catalogCache?.key !== key) catalogCache = { key, entries: selectTechCatalog(s, ctx) };
  return catalogCache.entries;
}
const MAX_DAYS_PER_TICK = 60;
/** Intervalo mínimo entre instantáneas mientras corre el tiempo (las vistas cuestan algo de CPU). */
const SNAPSHOT_MS = 100;
let lastSnapshot = 0;
let dirty = false;

async function loadGrid(gridUrl: string, binUrl: string) {
  try {
    const [meta, bin] = await Promise.all([
      fetch(gridUrl).then((r) => r.json() as Promise<GridMeta>),
      fetch(binUrl).then((r) => r.arrayBuffer()),
    ]);
    ctx.grid = new ResourceGrid(meta, bin);
    gridReady = true;
    post({ t: 'ready' });
  } catch (e) {
    post({ t: 'ready', error: (e as Error).message });
  }
}

/** Vistas de negocio: lo liviano siempre; lo de cada panel solo mientras está abierto. */
function businessViews(s: GameState): BusinessViews | null {
  if (!s.market?.initialized) return null;
  const open = s.market.opportunities.filter((o) => o.status === 'abierta' && !o.bids.some((b) => b.actorId === PLAYER_ID && b.status === 'presentada'));
  const b: BusinessViews = {
    summary: selectBusinessSummary(s, ctx),
    competitors: selectCompetitors(s, ctx),
    biddableCount: open.length,
    countries: selectCountries(s, ctx),
  };
  try {
    if (panel === 'market') { b.opportunities = selectOpportunities(s, ctx, { includeClosed: true }); b.myBids = selectMyBids(s, ctx); }
    if (panel === 'contracts') { b.contracts = selectContracts(s, ctx); b.myBids = selectMyBids(s, ctx); }
    if (panel === 'research') b.research = selectResearchTree(s, ctx);
    if (panel === 'suppliers') b.suppliers = selectSupplierCatalog(s, ctx);
    if (panel === 'countries') { b.fuels = selectFuelMarkets(s, ctx); if (country) b.countrySheet = selectCountrySheet(s, ctx, country); }
    if (panel === 'catalog') b.catalog = catalog(s);
  } catch (e) { console.error('Vista de negocio:', e); }
  return b;
}

/** Vistas de la Fase 5: eventos activos, clima, ingresos por fuente y marcadores siempre; mercado y mundo con su ventana. */
function powerViews(s: GameState): PowerViews | null {
  if (!s.market?.initialized) return null;
  try {
    const marks: OpportunityMark[] = [];
    for (const o of s.market.opportunities) {
      if (o.status !== 'abierta') continue;
      let loc = oppLoc.get(o.id);
      if (loc === undefined) { loc = opportunityLocation(ctx, o) ?? null; oppLoc.set(o.id, loc); }
      if (!loc) continue;
      marks.push({ id: o.id, lat: loc.lat, lon: loc.lon, clientName: o.clientName, countryCode: o.countryCode, mw: o.mw, techs: o.techs, kind: o.kind, daysLeft: o.deadlineTick - s.tick,
        myBid: o.bids.some((b) => b.actorId === PLAYER_ID && b.status === 'presentada') });
    }
    const all = selectWorldEvents(s, ctx);
    const v: PowerViews = { worldActive: all.active, climate: selectClimate(s, ctx, s.company.homeCountry), revenue: selectRevenueBySource(s), oppMarks: marks };
    if (panel === 'power') { v.markets = selectPowerMarkets(s, ctx); v.market = selectPowerMarket(s, ctx, powerIso ?? s.company.homeCountry); }
    if (panel === 'world') v.world = all;
    if (panel === 'competitors') v.shareHistory = selectMarketShareHistory(s);
    return v;
  } catch (e) { console.error('Vista de la Fase 5:', e); return null; }
}

function dispatchView(s: GameState): PlantDispatchView | null {
  if (!focus || !focusTab || !DISPATCH_TABS.has(focusTab)) return null;
  const p = s.projects.find((x) => x.id === focus);
  if (!p || (!p.operation && !p.construction)) return null;
  try { return selectPlantDispatch(s, ctx, focus); } catch (e) { console.error('Despacho:', e); return null; }
}

function views(s: GameState): Views {
  let detail = null;
  if (focus) { try { detail = selectProjectDetail(s, ctx, focus); } catch { detail = null; } }
  return { projects: selectProjects(s, ctx), finance: selectCompanyFinancials(s, ctx), detail, business: businessViews(s), power: powerViews(s), dispatch: dispatchView(s) };
}

/** Vista previa de una política de despacho: la misma vista sobre una copia superficial del estado con la política nueva. */
function dispatchPreview(projectId: string, policy: import('@voltaje/sim').DispatchPolicy): PlantDispatchView | null {
  if (!state) return null;
  const copy: GameState = { ...state, projects: state.projects.map((p) => (p.id === projectId ? { ...p, dispatch: policy, operation: p.operation && { ...p.operation, plan: undefined } } : p)) };
  return selectPlantDispatch(copy, ctx, projectId);
}

function snapshot(force = true) {
  if (!state) return;
  const now = performance.now();
  if (!force && now - lastSnapshot < SNAPSHOT_MS) { dirty = true; return; }
  lastSnapshot = now;
  dirty = false;
  post({ t: 'snapshot', state, views: views(state) });
}

function advance(days: number) {
  if (!state) return;
  const events: SimEvent[] = [];
  for (let d = 0; d < days; d++) {
    // los comandos esperan a que la grilla esté cargada (createProject la necesita)
    const cmds = d === 0 && gridReady ? pending : [];
    events.push(...step(state, cmds, ctx));
    if (cmds.length) pending = [];
    if (state.finance.bankrupt) break;
  }
  if (events.length) post({ t: 'events', events });
  snapshot(events.some((e) => e.type !== 'newMonth'));
}

setInterval(() => {
  const now = performance.now();
  const dt = (now - last) / 1000;
  last = now;
  if (!state) return;
  if (daysPerSecond <= 0 || state.finance.bankrupt) {
    // en pausa los comandos se aplican sin avanzar el tiempo
    if (pending.length && gridReady) {
      const events = applyCommands(state, pending, ctx);
      pending = [];
      if (events.length) post({ t: 'events', events });
      snapshot();
    } else if (dirty) snapshot();
    return;
  }
  carry += dt * daysPerSecond;
  const days = Math.min(MAX_DAYS_PER_TICK, Math.floor(carry));
  if (days > 0) {
    carry -= days;
    advance(days);
  } else if (dirty) snapshot(false);
}, 50);

/** Simula la creación del proyecto en una copia del estado para estimar su economía (no toca la partida). */
function estimateSite(techId: string, mw: number, lat: number, lon: number, to?: { lat: number; lon: number }): SiteEstimate {
  const empty = { irrEquity: null, npvEquityUsd: null, lcoeUsdMwh: null, devCostUpcomingUsd: null, successProbability: null, priceUsdMwh: null };
  if (!state) return { preview: previewSite(createNewGame(gameData.sim, { seed: 1, companyName: 'x' }), ctx, techId, mw, lat, lon, to), ...empty };
  const preview = previewSite(state, ctx, techId, mw, lat, lon, to);
  // con el sitio bien pero el país cerrado (I+D, presencia) o la tecnología sin investigar, se estima igual sobre la copia:
  // así se ve si vale la pena abrir el mercado o investigar
  const siteOk = !!preview.countryCode && (preview.errors ?? []).every((e) => (preview.accessBlockers ?? []).includes(e) || /requiere investigación/.test(e));
  if (!preview.ok && !siteOk) return { preview, ...empty };
  const copy = structuredClone(state);
  copy.company.cashUsd = Math.max(copy.company.cashUsd, 1e9);
  copy.finance.bankrupt = false;
  if (!preview.ok) unlockForEstimate(copy, techId, preview.countryCode!, preview.site?.to?.countryCode);
  const id = `P${copy.nextProjectId}`;
  applyCommands(copy, [{ type: 'createProject', techId, mw, lat, lon, ...(to ? { toLat: to.lat, toLon: to.lon } : {}) }], ctx);
  const d = selectProjectDetail(copy, ctx, id);
  if (!d) return { preview, ...empty };
  return {
    preview,
    irrEquity: d.economics?.model.irrEquity ?? null,
    npvEquityUsd: d.economics?.npvEquityUsd ?? null,
    lcoeUsdMwh: d.economics?.lcoeUsdMwh ?? null,
    devCostUpcomingUsd: d.costs.upcomingUsd.studies + d.costs.upcomingUsd.permits + d.costs.upcomingUsd.financing,
    successProbability: d.successProbability,
    priceUsdMwh: d.economics?.priceUsdMwh ?? null,
  };
}

/** Solo en la copia de la vista previa: I+D y presencia necesarias para poder crear el proyecto y estimarlo. */
function unlockForEstimate(copy: GameState, techId: string, ...countries: (string | undefined)[]) {
  const r = copy.business.research;
  const add = (id: string | undefined) => { if (id && !r.completed.includes(id)) r.completed.push(id); };
  const nodes = ctx.data.research?.nodos ?? [];
  const need = (pred: (n: (typeof nodes)[number]) => boolean) => {
    // el nodo y todos sus prerrequisitos
    const stack = nodes.filter(pred).map((n) => n.id);
    while (stack.length) { const id = stack.pop()!; if (r.completed.includes(id)) continue; add(id); stack.push(...(nodes.find((n) => n.id === id)?.requiere ?? [])); }
  };
  need((n) => !!n.efectos.tecnologias?.includes(techId));
  for (const c of countries) {
    if (!c || c === copy.company.homeCountry) continue;
    need((n) => !!n.efectos.paises?.includes(c));
    copy.business.presence ??= {};
    copy.business.presence[c] = { status: 'activa', level: 'representante', requestedTick: copy.tick, readyTick: copy.tick, setupCostUsd: 0, monthlyCostUsd: 0 };
  }
}

/** Cotización de una oferta + proveedores de esa tecnología (para elegir equipos y EPC en el diálogo). */
function quote(req: QuoteRequest): QuoteReply {
  if (!state) return { quote: null, suppliers: [] };
  const { opportunityId, ...o } = req;
  const all = selectSupplierCatalog(state, ctx).suppliers.filter((x) => x.tecnologias.includes(req.techId) && (x.tipo === 'equipos' || x.tipo === 'epc'));
  try {
    return { quote: selectBidQuote(state, ctx, opportunityId, o), suppliers: all };
  } catch (e) {
    console.error('Cotización:', e);
    return { quote: null, suppliers: all };
  }
}

self.onmessage = (e: MessageEvent<ToWorker>) => {
  const m = e.data;
  switch (m.t) {
    case 'init':
      void loadGrid(m.gridUrl, m.binUrl);
      break;
    case 'new':
      state = createNewGame(gameData.sim, { seed: m.seed, companyName: m.companyName });
      // el mundo de la Fase 3 (mercado, competidores, I+D) se arma en el primer applyCommands/step: así el mercado se ve en pausa
      { const ev = applyCommands(state, [], ctx); if (ev.length) post({ t: 'events', events: ev }); }
      pending = []; carry = 0; daysPerSecond = 0; focus = null;
      snapshot();
      break;
    case 'load':
      try {
        state = deserialize(m.text);
        applyCommands(state, [], ctx);
        pending = []; carry = 0; daysPerSecond = 0; focus = null;
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
    case 'focus':
      focus = m.projectId;
      focusTab = m.tab ?? null;
      snapshot();
      break;
    case 'powerCountry':
      powerIso = m.iso3;
      if (panel === 'power') snapshot();
      break;
    case 'dispatchPreview':
      try { post({ t: 'dispatchPreview', reqId: m.reqId, view: dispatchPreview(m.projectId, m.policy) }); }
      catch (err) { post({ t: 'dispatchPreview', reqId: m.reqId, view: null, error: (err as Error).message }); }
      break;
    case 'debug':
      // solo para la prueba de humo: forzar un evento del mundo (triggerWorldEvent del motor, no es un comando de juego)
      if (state && m.op === 'worldEvent') {
        const ev: SimEvent[] = [];
        triggerWorldEvent(state, ctx, m.eventId, m.countries, ev);
        if (ev.length) post({ t: 'events', events: ev });
        snapshot();
      }
      if (state && m.op === 'autopilot') {
        runAutopilot(state, ctx, m.maxDays ?? 2400, m.extraDays ?? 120);
        snapshot();
      }
      break;
    case 'preview':
      post({ t: 'preview', reqId: m.reqId, estimate: estimateSite(m.techId, m.mw, m.lat, m.lon, m.to) });
      break;
    case 'viability': {
      const t0 = performance.now();
      try {
        if (!state) throw new Error('Sin partida.');
        const result = checkViability(state, ctx, m.projectId, { runs: m.runs });
        post({ t: 'viability', reqId: m.reqId, result, ms: performance.now() - t0 });
      } catch (err) {
        post({ t: 'viability', reqId: m.reqId, error: (err as Error).message, ms: performance.now() - t0 });
      }
      break;
    }
    case 'finPreview':
      try {
        post({ t: 'finPreview', reqId: m.reqId, preview: state ? previewFinancing(state, ctx, m.projectId, { lenderId: m.lenderId, debtFraction: m.debtFraction, partnerShare: m.partnerShare }) : null });
      } catch (err) {
        post({ t: 'finPreview', reqId: m.reqId, preview: null, error: (err as Error).message });
      }
      break;
    case 'quote':
      post({ t: 'quote', reqId: m.reqId, reply: quote(m.req) });
      break;
    case 'panel':
      panel = m.panel;
      snapshot();
      break;
    case 'country':
      country = m.iso3;
      if (panel === 'countries') snapshot();
      break;
    case 'save':
      if (state) post({ t: 'saved', reqId: m.reqId, text: serialize(state) });
      break;
    case 'quit':
      state = null; daysPerSecond = 0; pending = []; focus = null; powerIso = null; oppLoc.clear();
      break;
  }
};
