/**
 * Selectores de la Fase 3 para la UI (solo lectura, no consumen RNG ni exponen información oculta:
 * ni el precio de reserva privado de los clientes, ni las ofertas ajenas antes de la adjudicación,
 * ni la caja o el recurso real de los competidores).
 */
import type { GameState } from './core/state';
import type { SimContext } from './core/context';
import { fromEpochDay, type GameDate } from './core/calendar';
import { balanceSheet } from './finance/company';
import { isTerminal } from './project/helpers';
import { STAGE_LABELS } from './selectors';
import { actorView, experienceMw } from './business/actor';
import { bidBlockers, nameplateMw, PRICE_UNITS, quoteBid, type BidQuote } from './business/bids';
import { publicOpportunity } from './business/opportunities';
import { describeEffects, isResearched, researchBlockers, researchEffects, researchNodes } from './business/research';
import { equipmentIndex, epcIndex, supplierLeadFactor, supplierPriceFactor, supplierReliability, relationDiscount } from './supply/supply';
import { contractValue } from './business/contracts';
import { PLAYER_ID, type Bid, type ContractStatus, type Opportunity, type RankingEntry } from './business/types';
import type { ContractKind, ResearchBranch } from './data/types';
import type { ProjectStage } from './project/types';
import { hashString } from './core/rng';

const dateOf = (s: GameState, tick: number): GameDate => fromEpochDay(s.startEpochDay + tick);

export const CONTRACT_LABELS: Record<ContractKind, string> = { ppa: 'PPA (energía)', potencia: 'Potencia firme', epc: 'EPC llave en mano', bot: 'BOT (construir, operar, transferir)' };
export const CONTRACT_STATUS_LABELS: Record<ContractStatus, string> = {
  sin_proyecto: 'Sin proyecto asignado', en_desarrollo: 'En desarrollo / obra', operando: 'En operación', cumplido: 'Cumplido', incumplido: 'Incumplido (garantía ejecutada)', cedido: 'Cedido con la venta',
};
export const RESEARCH_BRANCH_LABELS: Record<ResearchBranch, string> = {
  tecnologias: 'Tecnologías de energía', estudios: 'Tipos de estudio', mercados: 'Mercados y países', contratos: 'Tipos de contrato', eficiencia: 'Eficiencia y costos',
};

// ───────────────────────── Oportunidades ─────────────────────────

export interface OpportunityView {
  id: string;
  clientName: string;
  clientTypeName: string;
  countryCode: string;
  kind: Opportunity['kind'];
  kindLabel: string;
  contract: ContractKind;
  contractLabel: string;
  contractType: string;
  mw: number;
  years: number;
  unit: string;
  /** Tecnologías admitidas; `modeled` = tiene modelo en el juego; `unlocked` = la investigaste. */
  techs: { id: string; modeled: boolean; unlocked: boolean }[];
  ceilingPrice?: number;
  referencePrice: number;
  status: Opportunity['status'];
  openedDate: GameDate;
  deadlineDate: GameDate;
  awardDate: GameDate;
  daysToDeadline: number;
  codMonths: number;
  bidBondUsd: number;
  performanceBondUsd: number;
  prepCostUsd: number;
  weights: Opportunity['weights'];
  requirements: { minExperienceMw: number; minEquityUsd: number; penaltyUsdMwMonth: number; maxDelayMonths: number };
  /** ¿Puedo ofertar? (con la primera tecnología admitida que tengas). */
  canBid: { ok: boolean; techId?: string; blockers: string[] };
  myBid?: Bid;
  result?: { ranking: RankingEntry[]; winnerName?: string; winnerPrice?: number; date: GameDate; reason?: string };
  /**
   * Pedido de la UI: ubicación aproximada para marcarla en el globo (sitio candidato público del país y la tecnología,
   * con un desplazamiento determinista por oportunidad; si no hay, el centro de la zona habilitada del país).
   */
  location?: { lat: number; lon: number; approximate: true };
}

/** Ubicación aproximada de una oportunidad (pública y determinista). */
export function opportunityLocation(ctx: SimContext, o: Pick<Opportunity, 'id' | 'countryCode' | 'techs'>): { lat: number; lon: number; approximate: true } | undefined {
  const sites = ctx.data.competitors?.sitios_candidatos ?? [];
  const inCountry = sites.filter((s) => s.pais === o.countryCode);
  const pool = inCountry.filter((s) => o.techs.includes(s.tecnologia));
  const list = pool.length ? pool : inCountry;
  const h = hashString(o.id);
  if (list.length) {
    const s = list[h % list.length];
    return { lat: s.lat + ((h >>> 8) % 21 - 10) * 0.01, lon: s.lon + ((h >>> 16) % 21 - 10) * 0.01, approximate: true };
  }
  const z = ctx.data.countries[o.countryCode]?.zona;
  if (z) return { lat: (z.lat_min + z.lat_max) / 2, lon: (z.lon_min + z.lon_max) / 2, approximate: true };
  return undefined;
}

function oppView(state: GameState, ctx: SimContext, o: Opportunity): OpportunityView {
  const pub = publicOpportunity(o, PLAYER_ID);
  const fx = researchEffects(state, ctx);
  const techs = o.techs.map((t) => ({ id: t, modeled: !!ctx.data.technologies[t], unlocked: !fx.techs || fx.techs.has(t) }));
  const sanitized: Opportunity = { ...pub, reservePrice: pub.ceilingPrice ?? Infinity, bids: pub.myBid ? [pub.myBid] : [] };
  const firstTech = techs.find((t) => t.modeled && t.unlocked)?.id ?? techs.find((t) => t.modeled)?.id ?? o.techs[0];
  const blockers = o.status === 'abierta' ? bidBlockers(state, ctx, sanitized, { techId: firstTech }) : ['La recepción de ofertas está cerrada.'];
  const ct = ctx.data.clients?.tipos.find((x) => x.id === o.clientTypeId);
  const closed = o.status === 'adjudicada' || o.status === 'desierta';
  return {
    id: o.id, clientName: o.clientName, clientTypeName: ct?.nombre ?? o.clientTypeId, countryCode: o.countryCode, kind: o.kind,
    kindLabel: o.kind === 'licitacion_publica' ? 'Licitación pública' : 'Solicitud privada', contract: o.contract, contractLabel: CONTRACT_LABELS[o.contract],
    contractType: o.contractType, mw: o.mw, years: o.years, unit: PRICE_UNITS[o.contract], techs, ceilingPrice: o.ceilingPrice, referencePrice: o.referencePrice,
    status: o.status, openedDate: dateOf(state, o.openedTick), deadlineDate: dateOf(state, o.deadlineTick), awardDate: dateOf(state, o.awardTick),
    daysToDeadline: Math.max(0, o.deadlineTick - state.tick), codMonths: o.codMonths, bidBondUsd: o.bidBondUsd, performanceBondUsd: o.performanceBondUsd,
    prepCostUsd: o.prepCostUsd, weights: o.weights,
    requirements: { minExperienceMw: o.minExperienceMw, minEquityUsd: o.minEquityUsd, penaltyUsdMwMonth: o.penaltyUsdMwMonth, maxDelayMonths: o.maxDelayMonths },
    canBid: { ok: blockers.length === 0, techId: firstTech, blockers }, myBid: pub.myBid,
    result: closed && o.result ? { ranking: o.result.ranking, winnerName: o.result.winnerName, winnerPrice: o.result.winnerPrice, date: dateOf(state, o.result.tick), reason: o.result.reason } : undefined,
    location: opportunityLocation(ctx, o),
  };
}

/** Oportunidades abiertas o en evaluación (y, con `includeClosed`, las adjudicadas/desiertas recientes). */
export function selectOpportunities(state: GameState, ctx: SimContext, opts: { includeClosed?: boolean } = {}): OpportunityView[] {
  return state.market.opportunities
    .filter((o) => opts.includeClosed || o.status === 'abierta' || o.status === 'evaluacion')
    .map((o) => oppView(state, ctx, o))
    .sort((a, b) => a.daysToDeadline - b.daysToDeadline);
}

export interface BidQuoteView extends BidQuote {
  blockers: string[];
  /** Proyectos propios que se pueden vincular a esta oportunidad. */
  eligibleProjects: { id: string; name: string; mw: number; stage: string }[];
  /** Puntaje de precio y total estimado si los rivales ofertan a la referencia (orientativo). */
  estimatedScoreAtReference: number;
}

/** Cotización de una oferta (lo que costaría y cuánto pedir). Las opciones son las del comando `submitBid`. */
export function selectBidQuote(state: GameState, ctx: SimContext, opportunityId: string,
  o: { techId: string; projectId?: string; marginPct?: number; price?: number; deliveryMonths?: number; effort?: 'estandar' | 'reforzada'; equipmentId?: string; epcId?: string }): BidQuoteView | null {
  const real = state.market.opportunities.find((x) => x.id === opportunityId);
  if (!real) return null;
  const pub = publicOpportunity(real, PLAYER_ID);
  const opp: Opportunity = { ...pub, reservePrice: pub.ceilingPrice ?? Infinity, bids: pub.myBid ? [pub.myBid] : [] };
  const q = quoteBid(state, ctx, opp, o);
  const blockers = bidBlockers(state, ctx, opp, { ...o, price: o.price ?? q.suggestedPrice, deliveryMonths: o.deliveryMonths ?? Math.min(opp.codMonths, Math.ceil(q.realisticDeliveryMonths)) });
  const need = nameplateMw(ctx, opp, o.techId);
  const eligibleProjects = opp.contract === 'epc' ? [] : state.projects
    .filter((p) => !isTerminal(p) && p.techId === o.techId && p.countryCode === opp.countryCode && !p.contractId && p.ppa?.status !== 'firmado' && p.ppa?.status !== 'en_proceso' && p.mw >= 0.9 * need && p.mw <= 1.5 * need)
    .map((p) => ({ id: p.id, name: p.name, mw: p.mw, stage: STAGE_LABELS[p.stage] }));
  const price = o.price ?? q.suggestedPrice;
  const ps = 100 * Math.min(1, opp.referencePrice / price);
  const w = opp.weights;
  const est = w.precio * ps + w.tecnica * q.technicalScore + w.experiencia * q.experienceScore + w.plazo * 100 * Math.min(1, opp.codMonths / Math.max(1, o.deliveryMonths ?? opp.codMonths));
  return { ...q, blockers, eligibleProjects, estimatedScoreAtReference: est };
}

export interface MyBidView {
  opportunityId: string;
  clientName: string;
  contractLabel: string;
  mw: number;
  unit: string;
  bid: Bid;
  status: Bid['status'];
  opportunityStatus: Opportunity['status'];
  awardDate: GameDate;
  /** Tras la adjudicación: ranking con precios rivales revelados. */
  ranking?: RankingEntry[];
  winnerName?: string;
  winnerPrice?: number;
}

export function selectMyBids(state: GameState, _ctx: SimContext): MyBidView[] {
  const out: MyBidView[] = [];
  for (const o of state.market.opportunities) {
    const b = o.bids.find((x) => x.actorId === PLAYER_ID);
    if (!b) continue;
    const closed = o.status === 'adjudicada' || o.status === 'desierta';
    out.push({
      opportunityId: o.id, clientName: o.clientName, contractLabel: CONTRACT_LABELS[o.contract], mw: o.mw, unit: PRICE_UNITS[o.contract], bid: b, status: b.status,
      opportunityStatus: o.status, awardDate: dateOf(state, o.awardTick), ranking: closed ? o.result?.ranking : undefined, winnerName: closed ? o.result?.winnerName : undefined,
      winnerPrice: closed ? o.result?.winnerPrice : undefined,
    });
  }
  return out.sort((a, b) => b.bid.submittedTick - a.bid.submittedTick);
}

// ───────────────────────── Contratos ─────────────────────────

export interface ContractView {
  id: string;
  clientName: string;
  kind: ContractKind;
  kindLabel: string;
  status: ContractStatus;
  statusLabel: string;
  mw: number;
  techId: string;
  price: number;
  unit: string;
  years: number;
  signedDate: GameDate;
  codDeadlineDate: GameDate;
  terminationDate: GameDate;
  assignDeadlineDate?: GameDate;
  daysToCod: number;
  late: boolean;
  bondUsd: number;
  penaltiesUsd: number;
  revenueUsd: number;
  project?: { id: string; name: string; stage: string; stageId: ProjectStage; buildProgress: number };
  /** Pedido de la UI: país del contrato. */
  countryCode: string;
  /** Pedido de la UI: proyectos propios que se pueden asignar (contratos «sin proyecto»: misma tecnología y país, 0,9–1,5× MW). */
  eligibleProjects: { id: string; name: string; mw: number; stage: string; stageId: ProjectStage }[];
  epc?: { progress: number; budgetUsd: number; spentUsd: number; collectedUsd: number; overrunUsd: number; ldUsd: number; contractValueUsd: number; expectedMarginUsd: number };
  /** Obligaciones y lo que hay que hacer, en texto. */
  obligations: string[];
  active: boolean;
}

export function selectContracts(state: GameState, ctx: SimContext): ContractView[] {
  const fmt = (v: number) => `${Math.round(v).toLocaleString('es-PA')} USD`;
  return state.business.contracts.map((k) => {
    const p = k.projectId ? state.projects.find((x) => x.id === k.projectId) : undefined;
    const active = k.status === 'sin_proyecto' || k.status === 'en_desarrollo' || k.status === 'operando';
    const ob: string[] = [];
    if (k.status === 'sin_proyecto') ob.push(`Asignar un proyecto de ${k.techId.replace(/_/g, ' ')} de ${Math.ceil(k.kind === 'potencia' ? nameplateMw(ctx, { contract: 'potencia', mw: k.mw }, k.techId) : k.mw)} MW antes del ${fmtDate(dateOf(state, k.assignDeadlineTick ?? k.codDeadlineTick))} o se ejecuta la garantía (${fmt(k.bondUsd)}).`);
    if (k.status === 'en_desarrollo' || k.status === 'sin_proyecto') {
      ob.push(`${k.kind === 'epc' ? 'Entregar la obra' : 'Operación comercial'} antes del ${fmtDate(dateOf(state, k.codDeadlineTick))}; después, ${k.kind === 'epc' ? 'daños por atraso de 0,5 %/semana' : `multa de ${fmt(k.penaltyUsdMwMonth * k.mw)} por mes`}.`);
      ob.push(`Plazo máximo: ${fmtDate(dateOf(state, k.terminationTick))}; si no se cumple, se ejecuta la garantía y se rescinde.`);
    }
    if (k.status === 'operando' && k.kind === 'potencia') ob.push('Mantener disponibilidad mensual ≥ 85 % (si no, 10 % de descuento en el pago).');
    if (k.status === 'operando' && k.kind === 'bot') ob.push(`Al terminar (${k.years} años) la planta se transfiere al Estado sin pago.`);
    const e = k.epc;
    const value = contractValue(k);
    return {
      id: k.id, clientName: k.clientName, kind: k.kind, kindLabel: CONTRACT_LABELS[k.kind], status: k.status, statusLabel: CONTRACT_STATUS_LABELS[k.status], mw: k.mw, techId: k.techId,
      price: k.price, unit: PRICE_UNITS[k.kind], years: k.years, signedDate: dateOf(state, k.signedTick), codDeadlineDate: dateOf(state, k.codDeadlineTick),
      terminationDate: dateOf(state, k.terminationTick), assignDeadlineDate: k.assignDeadlineTick !== undefined ? dateOf(state, k.assignDeadlineTick) : undefined,
      daysToCod: k.codDeadlineTick - state.tick, late: active && k.status !== 'operando' && state.tick > k.codDeadlineTick,
      bondUsd: k.bondUsd, penaltiesUsd: k.penaltiesUsd, revenueUsd: k.revenueUsd,
      project: p ? { id: p.id, name: p.name, stage: STAGE_LABELS[p.stage], stageId: p.stage, buildProgress: p.operation ? 1 : p.construction?.progress ?? 0 } : undefined,
      countryCode: k.countryCode,
      eligibleProjects: k.status !== 'sin_proyecto' || k.kind === 'epc' ? [] : (() => {
        const need = k.kind === 'potencia' ? nameplateMw(ctx, { contract: 'potencia', mw: k.mw }, k.techId) : k.mw;
        return state.projects.filter((x) => !isTerminal(x) && x.techId === k.techId && x.countryCode === k.countryCode && !x.contractId && (!x.ppa || x.ppa.status === 'fallido') && !x.construction && !x.operation && x.mw >= 0.9 * need && x.mw <= 1.5 * need)
          .map((x) => ({ id: x.id, name: x.name, mw: x.mw, stage: STAGE_LABELS[x.stage], stageId: x.stage }));
      })(),
      epc: e ? { progress: e.progress, budgetUsd: e.budgetUsd, spentUsd: e.spentUsd, collectedUsd: e.collectedUsd, overrunUsd: e.overrunUsd, ldUsd: e.ldUsd, contractValueUsd: value, expectedMarginUsd: value - e.budgetUsd - e.ldUsd } : undefined,
      obligations: ob, active,
    };
  });
}

const fmtDate = (d: GameDate) => `${d.day}/${d.month}/${d.year}`;

// ───────────────────────── Competidores ─────────────────────────

export interface CompetitorView {
  id: string;
  name: string;
  /** Estrategia aparente (lo que el mercado percibe). */
  apparentStrategy: string;
  description: string;
  status: 'activa' | 'quebrada';
  reputation: number;
  experienceMw: number;
  operatingMw: number;
  /** Proyectos visibles (desde permisos en trámite: registros públicos) con ubicación. */
  visibleProjects: { id: string; name: string; techId: string; mw: number; stage: string; stageId: ProjectStage; lat: number; lon: number; buildProgress: number }[];
  bidsWon: number;
  bidsLost: number;
  /** Cuota del mercado (MW renovables en operación de las empresas del juego en el país de origen). */
  marketShare: number;
}

export interface CompetitorsOverview {
  competitors: CompetitorView[];
  player: { name: string; operatingMw: number; marketShare: number; reputation: number; experienceMw: number };
  totalOperatingMw: number;
}

export function selectCompetitors(state: GameState, ctx: SimContext): CompetitorsOverview {
  const opMw = (ps: GameState['projects']) => ps.filter((p) => p.stage === 'operacion').reduce((a, p) => a + p.mw, 0);
  const playerMw = opMw(state.projects);
  const total = playerMw + state.competitors.reduce((a, c) => a + opMw(c.projects), 0);
  const visibleStages = new Set(['permisos', 'cierre_financiero', 'construccion', 'puesta_en_marcha', 'operacion']);
  const defs = ctx.data.competitors?.empresas ?? [];
  return {
    totalOperatingMw: total,
    player: { name: state.company.name, operatingMw: playerMw, marketShare: total > 0 ? playerMw / total : 0, reputation: state.business.reputation, experienceMw: experienceMw(state) },
    competitors: state.competitors.map((c) => {
      const def = defs.find((d) => d.id === c.defId);
      const v = actorView(state, c);
      const mw = opMw(c.projects);
      return {
        id: c.id, name: c.name, apparentStrategy: def?.estrategia_aparente ?? '', description: def?.descripcion ?? '', status: c.status,
        reputation: c.business.reputation, experienceMw: experienceMw(v), operatingMw: mw,
        visibleProjects: c.projects.filter((p) => visibleStages.has(p.stage)).map((p) => ({
          id: p.id, name: p.name, techId: p.techId, mw: p.mw, stage: STAGE_LABELS[p.stage], stageId: p.stage, lat: p.site.lat, lon: p.site.lon, buildProgress: p.operation ? 1 : p.construction?.progress ?? 0,
        })),
        bidsWon: c.business.bidsWon, bidsLost: c.business.bidsLost, marketShare: total > 0 ? mw / total : 0,
      };
    }),
  };
}

// ───────────────────────── I+D ─────────────────────────

export type ResearchNodeStatus = 'completado' | 'en_curso' | 'en_cola' | 'disponible' | 'bloqueado';

export interface ResearchNodeView {
  id: string;
  nombre: string;
  rama: ResearchBranch;
  ramaLabel: string;
  descripcion: string;
  costUsd: number;
  months: number;
  /** Meses estimados con el presupuesto actual (null si el presupuesto es 0). */
  monthsAtBudget: number | null;
  requires: { id: string; nombre: string; done: boolean }[];
  status: ResearchNodeStatus;
  progress: number;
  blockers: string[];
  effectsText: string;
  /** Lo que desbloquea aún no tiene modelo completo (llega en esa fase). */
  modelPhase?: number;
  setbackProbability: number;
  initial: boolean;
}

export interface ResearchTreeView {
  budgetUsdMonth: number;
  active: { nodeId: string; nombre: string; progress: number; spentUsd: number; etaMonths: number | null } | null;
  queue: string[];
  totalSpentUsd: number;
  nodes: ResearchNodeView[];
  branches: { id: ResearchBranch; label: string }[];
}

export function selectResearchTree(state: GameState, ctx: SimContext): ResearchTreeView {
  const r = state.business.research;
  const nodes = researchNodes(ctx);
  const months = (cost: number, min: number, left = 1) => (r.budgetUsdMonth > 0 ? Math.max(min, cost / r.budgetUsdMonth) * left : null);
  const list: ResearchNodeView[] = Object.values(nodes).map((n) => {
    const done = isResearched(ctx, r, n.id);
    const status: ResearchNodeStatus = done ? 'completado' : r.active?.nodeId === n.id ? 'en_curso' : r.queue.includes(n.id) ? 'en_cola' : researchBlockers(state, ctx, n.id).length ? 'bloqueado' : 'disponible';
    const progress = done ? 1 : r.active?.nodeId === n.id ? r.active.progress : r.partial[n.id] ?? 0;
    return {
      id: n.id, nombre: n.nombre, rama: n.rama, ramaLabel: RESEARCH_BRANCH_LABELS[n.rama], descripcion: n.descripcion, costUsd: n.costo_usd, months: n.meses,
      monthsAtBudget: n.costo_usd > 0 ? months(n.costo_usd, n.meses, 1 - progress) : 0,
      requires: n.requiere.map((q) => ({ id: q, nombre: nodes[q]?.nombre ?? q, done: isResearched(ctx, r, q) })),
      status, progress, blockers: status === 'bloqueado' ? researchBlockers(state, ctx, n.id) : [], effectsText: describeEffects(n),
      modelPhase: n.fase_modelo, setbackProbability: n.prob_contratiempo, initial: !!n.inicial,
    };
  });
  const a = r.active;
  return {
    budgetUsdMonth: r.budgetUsdMonth, queue: [...r.queue], totalSpentUsd: r.totalSpentUsd, nodes: list,
    active: a ? { nodeId: a.nodeId, nombre: nodes[a.nodeId]?.nombre ?? a.nodeId, progress: a.progress, spentUsd: a.spentUsd, etaMonths: months(nodes[a.nodeId].costo_usd, nodes[a.nodeId].meses, 1 - a.progress) } : null,
    branches: (Object.keys(RESEARCH_BRANCH_LABELS) as ResearchBranch[]).map((id) => ({ id, label: RESEARCH_BRANCH_LABELS[id] })),
  };
}

// ───────────────────────── Proveedores y mercado de equipos ─────────────────────────

export interface SupplierCatalogItem {
  id: string;
  nombre: string;
  tipo: string;
  tecnologias: string[];
  origen: string;
  descripcion: string;
  basePriceFactor: number;
  /** Factor actual para el jugador (cola del proveedor y descuento por relación). */
  priceFactor: number;
  quality: number;
  reliability: number;
  leadDays?: number;
  backlogMw: number;
  capacityMwYear?: number;
  relation: { orders: number; mw: number; lateDeliveries: number; discount: number };
}

export interface SupplierCatalog {
  suppliers: SupplierCatalogItem[];
  /** Índices actuales y variación a 12 meses por tecnología (1 = precios de los YAML al inicio). */
  techIndices: { techId: string; equipment: number; epc: number; equipmentChange12m: number | null; capexUsdKwNow: number }[];
  materials: { id: string; nombre: string; index: number; change12m: number | null }[];
  demandIndex: number;
  history: GameState['market']['supply']['history'];
}

export function selectSupplierCatalog(state: GameState, ctx: SimContext): SupplierCatalog {
  const s = state.market.supply;
  const h12 = s.history.length >= 13 ? s.history[s.history.length - 13] : undefined;
  const suppliers = Object.values(ctx.data.suppliers).map((d) => {
    const rel = state.business.relations[d.id];
    return {
      id: d.id, nombre: d.nombre, tipo: d.tipo, tecnologias: d.tecnologias, origen: d.origen, descripcion: d.descripcion, basePriceFactor: d.factor_precio,
      priceFactor: supplierPriceFactor(state, ctx, d.id), quality: d.calidad, reliability: supplierReliability(state, ctx, d.id),
      leadDays: d.plazo_entrega_dias ? Math.round(d.plazo_entrega_dias.base * supplierLeadFactor(state, ctx, d.id) * (d.factor_plazo_entrega ?? 1)) : undefined,
      backlogMw: s.backlogMw[d.id] ?? 0, capacityMwYear: d.capacidad_mw_ano,
      relation: { orders: rel?.orders ?? 0, mw: rel?.mw ?? 0, lateDeliveries: rel?.lateDeliveries ?? 0, discount: relationDiscount(state, ctx, d.id) },
    };
  });
  const techIndices = Object.values(ctx.data.technologies).map((t) => {
    const eq = equipmentIndex(state, ctx, t.id), ep = epcIndex(state, ctx, t.id);
    const fx = researchEffects(state, ctx).capexMult(t.id);
    const capexKw = t.capex_usd_kw.base * fx * (t.desglose_capex.equipos * eq + t.desglose_capex.epc * ep * (ctx.data.countries[state.company.homeCountry]?.costos.factor_construccion_local.base ?? 1) + t.desglose_capex.otros);
    return { techId: t.id, equipment: eq, epc: ep, equipmentChange12m: h12 ? eq / (h12.equipment[t.id] ?? eq) - 1 : null, capexUsdKwNow: capexKw };
  });
  const materials = (ctx.data.supply?.materiales ?? []).map((m) => ({ id: m.id, nombre: m.nombre, index: s.materials[m.id] ?? 1, change12m: h12 ? (s.materials[m.id] ?? 1) / (h12.materials[m.id] ?? 1) - 1 : null }));
  return { suppliers, techIndices, materials, demandIndex: s.demandIndex, history: s.history };
}

// ───────────────────────── Resumen comercial ─────────────────────────

export interface BusinessSummary {
  reputation: number;
  experienceMw: number;
  restrictedCashUsd: number;
  bidsWon: number;
  bidsLost: number;
  openBids: number;
  activeContracts: number;
  researchBudgetUsdMonth: number;
  equityUsd: number;
}

export function selectBusinessSummary(state: GameState, _ctx: SimContext): BusinessSummary {
  const b = state.business;
  return {
    reputation: b.reputation, experienceMw: experienceMw(state), restrictedCashUsd: b.restrictedCashUsd, bidsWon: b.bidsWon, bidsLost: b.bidsLost,
    openBids: state.market.opportunities.filter((o) => o.bids.some((x) => x.actorId === PLAYER_ID && x.status === 'presentada')).length,
    activeContracts: b.contracts.filter((k) => k.status === 'sin_proyecto' || k.status === 'en_desarrollo' || k.status === 'operando').length,
    researchBudgetUsdMonth: b.research.budgetUsdMonth, equityUsd: balanceSheet(state).equityUsd,
  };
}

/** Pedido de la UI: historial mensual de cuota de mercado (MW en operación de cada empresa del juego y su fracción). */
export function selectMarketShareHistory(state: GameState): { year: number; month: number; totalMw: number; actors: { id: string; name: string; mw: number; share: number }[] }[] {
  return (state.market.shareHistory ?? []).map((h) => {
    const total = Object.values(h.mw).reduce((a, b) => a + b, 0);
    return {
      year: h.year, month: h.month, totalMw: total,
      actors: Object.entries(h.mw).map(([id, mw]) => ({ id, name: id === PLAYER_ID ? state.company.name : state.competitors.find((c) => c.id === id)?.name ?? id, mw, share: total > 0 ? mw / total : 0 })),
    };
  });
}
