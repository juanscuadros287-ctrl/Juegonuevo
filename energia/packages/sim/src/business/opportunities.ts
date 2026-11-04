import type { GameState } from '../core/state';
import type { SimContext } from '../core/context';
import type { SimEvent } from '../core/events';
import { Rng } from '../core/rng';
import type { ClientTypeDef } from '../data/types';
import { drawDays, drawDist } from '../project/outcomes';
import { isTerminal } from '../project/helpers';
import { equipmentIndex, epcIndex, yearsElapsed } from '../supply/supply';
import { actorName, changeReputation, withActor } from './actor';
import { executeBond, releaseBond } from './bonds';
import { experienceScore, technicalScore, PRICE_UNITS } from './bids';
import { signContract } from './contracts';
import { PLAYER_ID, type Opportunity, type RankingEntry } from './types';

/**
 * Oportunidades (Fase 3): licitaciones públicas (ETESA/ASEP) y solicitudes de privados, generadas cada mes
 * por tipo de cliente (Poisson con la frecuencia anual del YAML) con el flujo RNG `tenders`.
 * El precio de referencia sigue al mercado: costo de equipos (aprendizaje + materiales) e inflación.
 */

const KEEP_CLOSED_DAYS = 730;

function poisson(rng: Rng, mean: number): number {
  const L = Math.exp(-mean);
  let k = 0, p = 1;
  for (;;) { p *= rng.next(); if (p <= L) return k; k++; }
}

/** Índice de costo de capital de una tecnología (equipos y obra ponderados por el desglose). */
export function capexIndex(state: GameState, ctx: SimContext, techId: string): number {
  const t = ctx.data.technologies[techId];
  if (!t) return 1;
  const d = t.desglose_capex;
  return d.equipos * equipmentIndex(state, ctx, techId) + d.epc * epcIndex(state, ctx, techId) + d.otros;
}

/** Multiplicador del precio de referencia de mercado para un tipo de cliente. */
export function marketPriceIndex(state: GameState, ctx: SimContext, ct: ClientTypeDef): number {
  const infl = Math.pow(1 + (ctx.data.countries[ct.pais]?.inflacion_anual.base ?? 0.02), yearsElapsed(state));
  const tech = ct.tecnologias.find((t) => ctx.data.technologies[t]);
  const cap = tech ? capexIndex(state, ctx, tech) : 1;
  if (ct.contrato === 'epc') return cap;
  if (ct.contrato === 'potencia') return infl;
  return 0.75 * cap + 0.25 * infl;
}

export function generateOpportunities(state: GameState, ctx: SimContext, events: SimEvent[]) {
  const def = ctx.data.clients;
  if (!def) return;
  const rng = new Rng(state.rng.tenders);
  const m = state.market;
  for (const ct of def.tipos) {
    if (!ctx.data.countries[ct.pais]) continue;
    const n = poisson(rng, ct.frecuencia_anual / 12);
    for (let i = 0; i < n; i++) {
      const mw = Math.max(1, Math.round(drawDist(rng, ct.mw)));
      const ref = drawDist(rng, ct.precio_referencia) * marketPriceIndex(state, ctx, ct);
      const reserve = ref * drawDist(rng, ct.precio_reserva_factor);
      const deadline = state.tick + drawDays(rng, ct.plazo_oferta_dias);
      const o: Opportunity = {
        id: `L${m.nextOpportunityId++}`, clientTypeId: ct.id, clientName: rng.pick(ct.nombres_cliente), countryCode: ct.pais, kind: ct.tipo,
        contract: ct.contrato, contractType: ct.tipo_contrato, mw, years: Math.round(drawDist(rng, ct.plazo_anos)), techs: [...ct.tecnologias],
        ceilingPrice: ct.publica_precio_tope ? reserve : undefined, reservePrice: reserve, referencePrice: ref,
        openedTick: state.tick, deadlineTick: deadline, awardTick: deadline + drawDays(rng, ct.evaluacion_dias),
        codMonths: Math.round(drawDist(rng, ct.plazo_cod_meses)), bidBondUsd: ct.garantia_seriedad_usd_mw * mw, performanceBondUsd: ct.garantia_cumplimiento_usd_mw * mw,
        weights: { ...ct.pesos }, minExperienceMw: ct.experiencia_mw_min, minEquityUsd: ct.capital_min_usd, penaltyUsdMwMonth: ct.multa_usd_mw_mes,
        maxDelayMonths: ct.meses_max_atraso, prepCostUsd: drawDist(rng, ct.costo_preparacion_usd), indexation: ct.indexacion_anual, status: 'abierta', bids: [],
      };
      m.opportunities.push(o);
      const unit = PRICE_UNITS[o.contract];
      events.push({
        type: 'opportunityOpened', opportunityId: o.id, severity: 'info',
        text: `${o.kind === 'licitacion_publica' ? 'Licitación' : 'Solicitud'}: ${o.clientName} busca ${o.mw} MW (${ct.nombre}). Ofertas hasta dentro de ${deadline - state.tick} días${o.ceilingPrice ? `, tope ${o.ceilingPrice.toFixed(o.contract === 'epc' ? 0 : 1)} ${unit}` : ''}.`,
      });
    }
  }
  // Limpieza: se guardan las cerradas de los últimos 2 años
  m.opportunities = m.opportunities.filter((o) => o.status === 'abierta' || o.status === 'evaluacion' || state.tick - (o.result?.tick ?? o.awardTick) < KEEP_CLOSED_DAYS);
}

/** Avance diario: cierre de recepción de ofertas y adjudicación. */
export function opportunitiesDaily(state: GameState, ctx: SimContext, events: SimEvent[]) {
  for (const o of state.market.opportunities) {
    if (o.status === 'abierta' && state.tick >= o.deadlineTick) o.status = 'evaluacion';
    if (o.status === 'evaluacion' && state.tick >= o.awardTick) award(state, ctx, o, events);
  }
}

interface Entry { actorId: string; name: string; price: number; delivery: number; technical: number; experience: number; external: boolean; bidId?: string; disq?: string; total: number }

function award(state: GameState, ctx: SimContext, o: Opportunity, events: SimEvent[]) {
  const def = ctx.data.clients!;
  const ct = def.tipos.find((x) => x.id === o.clientTypeId);
  const rng = new Rng(state.rng.tenders);
  const entries: Entry[] = [];
  for (const b of o.bids) {
    if (b.status !== 'presentada') continue;
    const comp = b.actorId === PLAYER_ID ? undefined : state.competitors.find((c) => c.id === b.actorId);
    const res = withActor(state, b.actorId, (v) => {
      let disq: string | undefined;
      if (v.finance.bankrupt || comp?.status === 'quebrada') disq = 'empresa en quiebra';
      const p = b.projectId ? v.projects.find((x) => x.id === b.projectId) : undefined;
      if (b.projectId && (!p || isTerminal(p) || p.contractId || p.ppa?.status === 'firmado')) disq = 'el proyecto ofertado ya no está disponible';
      return { disq, technical: technicalScore(v, ctx, o, b), experience: experienceScore(v, o) };
    });
    if (!res) continue;
    let disq = res.disq;
    if (!disq && b.price > o.reservePrice * (1 + 1e-9)) disq = o.ceilingPrice ? 'precio sobre el tope' : 'precio sobre lo que el cliente acepta';
    entries.push({ actorId: b.actorId, name: b.actorName, price: b.price, delivery: b.deliveryMonths, technical: res.technical, experience: res.experience, external: false, bidId: b.id, disq, total: 0 });
  }
  // Ofertantes externos (empresas internacionales no simuladas en detalle): mantienen la competencia real.
  if (ct) {
    const n = poisson(rng, ct.ofertantes_externos.media);
    for (let i = 0; i < n; i++) {
      const price = o.referencePrice * drawDist(rng, ct.ofertantes_externos.precio_factor);
      entries.push({
        actorId: `externo_${i + 1}`, name: EXTERNAL_NAMES[(hashIdx(o.id) + i) % EXTERNAL_NAMES.length], price, delivery: Math.round(o.codMonths * rng.range(0.8, 1)),
        technical: rng.triangular(55, 72, 90), experience: rng.triangular(55, 75, 95), external: true,
        disq: price > o.reservePrice ? (o.ceilingPrice ? 'precio sobre el tope' : 'precio sobre lo que el cliente acepta') : undefined, total: 0,
      });
    }
  }
  const valid = entries.filter((e) => !e.disq);
  const minP = Math.min(...valid.map((e) => e.price)), minD = Math.min(...valid.map((e) => e.delivery));
  const w = o.weights, ws = w.precio + w.tecnica + w.experiencia + w.plazo;
  for (const e of valid) {
    const ps = 100 * minP / e.price, ds = 100 * minD / e.delivery;
    // Pequeño ruido del comité evaluador (±1,5 puntos): la oferta mejor puntuada gana casi siempre, no siempre.
    e.total = (w.precio * ps + w.tecnica * e.technical + w.experiencia * e.experience + w.plazo * ds) / ws + rng.normal(0, 1.5);
    const b = o.bids.find((x) => x.id === e.bidId);
    if (b) b.score = { price: ps, technical: e.technical, experience: e.experience, delivery: ds, total: e.total };
  }
  valid.sort((a, b) => b.total - a.total || a.price - b.price);
  let winner: Entry | undefined;
  for (const e of valid) {
    if (e.external) { winner = e; break; }
    const b = o.bids.find((x) => x.id === e.bidId)!;
    const signed = withActor(state, e.actorId, (v) => signContract(v, ctx, o, b, events));
    if (signed) { winner = e; break; }
    // No pudo constituir la garantía de cumplimiento: pierde la de seriedad y se pasa al siguiente.
    e.disq = 'no constituyó la garantía de cumplimiento';
    b.status = 'descalificada';
    withActor(state, e.actorId, (v) => { executeBond(v, ctx, b.bondUsd, `Garantía de seriedad ejecutada (${o.clientName})`); changeReputation(v, -5); });
  }
  const ranking: RankingEntry[] = [
    ...valid.filter((e) => !e.disq).map((e) => ({ actorId: e.actorId, name: e.name, price: e.price, deliveryMonths: e.delivery, score: e.total, external: e.external })),
    ...entries.filter((e) => e.disq).map((e) => ({ actorId: e.actorId, name: e.name, price: e.price, deliveryMonths: e.delivery, score: 0, external: e.external, disqualified: e.disq })),
  ];
  o.status = winner ? 'adjudicada' : 'desierta';
  o.result = { ranking, winnerId: winner?.actorId, winnerName: winner?.name, winnerPrice: winner?.price, tick: state.tick, reason: winner ? undefined : 'Ninguna oferta válida dentro del precio aceptable.' };
  ranking.forEach((r, i) => { const b = o.bids.find((x) => x.actorId === r.actorId && x.status !== 'retirada'); if (b) b.rank = r.disqualified ? undefined : i + 1; });

  const unit = PRICE_UNITS[o.contract];
  const dec = o.contract === 'epc' ? 0 : 1;
  for (const b of o.bids) {
    if (b.status === 'retirada') continue;
    const won = winner?.bidId === b.id;
    if (!won && b.status === 'presentada') {
      const e = entries.find((x) => x.bidId === b.id);
      b.status = e?.disq ? 'descalificada' : 'perdida';
      withActor(state, b.actorId, (v) => { releaseBond(v, ctx, b.bondUsd, `Garantía de seriedad devuelta (${o.clientName})`); v.business.bidsLost += 1; });
    }
    if (b.actorId === PLAYER_ID) {
      const rank = ranking.findIndex((r) => r.actorId === PLAYER_ID) + 1;
      const disq = entries.find((x) => x.bidId === b.id)?.disq;
      events.push({
        type: 'bidResult', opportunityId: o.id, won, rank, winnerName: winner?.name ?? '—', winnerPrice: winner?.price ?? 0, severity: won ? 'bueno' : 'malo',
        text: won ? `¡Ganaste ${o.clientName}! ${o.mw} MW a ${b.price.toFixed(dec)} ${unit}.`
          : disq ? `Oferta descalificada en ${o.clientName}: ${disq}.`
            : `Perdiste ${o.clientName} (puesto ${rank} de ${ranking.filter((r) => !r.disqualified).length}). ${winner ? `Ganó ${winner.name} con ${winner.price.toFixed(dec)} ${unit}.` : 'Quedó desierta.'}`,
      });
    }
  }
  if (winner && !winner.external && winner.actorId !== PLAYER_ID) {
    events.push({ type: 'competitorWonTender', competitorId: winner.actorId, opportunityId: o.id, severity: 'info', text: `${actorName(state, winner.actorId)} ganó ${o.clientName}: ${o.mw} MW a ${winner.price.toFixed(dec)} ${unit}.` });
  }
  if (!winner && o.bids.some((b) => b.actorId === PLAYER_ID)) {
    events.push({ type: 'opportunityDeserted', opportunityId: o.id, severity: 'info', text: `${o.clientName}: la convocatoria quedó desierta.` });
  }
}

const EXTERNAL_NAMES = ['Consorcio Iberoamericano', 'Pacific Renewables', 'Grupo Energético del Caribe', 'Andes Power Partners', 'Atlas Infra Fund', 'Solaria Latam', 'Vientos del Sur'];
function hashIdx(id: string) { let h = 0; for (const ch of id) h = (h * 31 + ch.charCodeAt(0)) >>> 0; return h; }

/** Para la UI y la IA: oportunidad sin la información oculta (precio de reserva privado, ofertas ajenas). */
export function publicOpportunity(o: Opportunity, viewerId: string): Omit<Opportunity, 'reservePrice' | 'bids'> & { myBid?: Opportunity['bids'][number]; bidders: number } {
  const { reservePrice: _r, bids, ...rest } = o;
  void _r;
  const closed = o.status === 'adjudicada' || o.status === 'desierta';
  return { ...rest, myBid: bids.find((b) => b.actorId === viewerId && b.status !== 'retirada'), bidders: closed ? bids.filter((b) => b.status !== 'retirada').length : 0 };
}
