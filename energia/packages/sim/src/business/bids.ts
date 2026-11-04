import type { GameState } from '../core/state';
import type { SimContext } from '../core/context';
import type { SimEvent } from '../core/events';
import type { SupplierDef } from '../data/types';
import { balanceSheet, postCash } from '../finance/company';
import { currentCapex, expectedAvailability, expectedRepairCostUsd, annualFixedCosts } from '../tech/costs';
import { currentYear, discountRates, lenderRate, projectEconomics, startYear } from '../project/economics';
import { applicablePermits, permitGroupApproved, requiredStudyGroups, studyGroupDone } from '../project/requirements';
import { isTerminal } from '../project/helpers';
import { actorIdOf, experienceMw } from './actor';
import { contractUnlocked, countryUnlocked, researchEffects, techUnlocked, unlockingNode } from './research';
import { postBond, releaseBond } from './bonds';
import { hasPresence } from './presence';
import { annualSpotUsd, effectiveDegradation, productTerms, techCaptureFactor } from '../tech/models';
import type { Bid, Opportunity } from './types';

/**
 * Ofertas (Fase 3). La misma lógica para el jugador y para la IA (que llega aquí con su vista de actor).
 * Precio: USD/MWh (ppa, bot), USD/kW-mes de potencia firme (potencia) o USD/kW instalado (epc).
 */

export type BidCommand =
  | {
    type: 'submitBid'; opportunityId: string; techId: string; price: number; deliveryMonths: number;
    /** Proyecto propio en desarrollo al que se vincula la oferta; sin él, te comprometes a uno nuevo. */
    projectId?: string;
    /** 'reforzada': ingeniería y visitas de sitio adicionales (2,5× el costo de preparación, +12 puntos técnicos). */
    effort?: 'estandar' | 'reforzada';
    /** EPC para terceros: proveedores con los que construirás (definen costo y riesgo). */
    equipmentId?: string; epcId?: string;
  }
  | { type: 'withdrawBid'; opportunityId: string };

type Result = { ok: true } | { ok: false; error: string };

export const PRICE_UNITS: Record<string, string> = { ppa: 'USD/MWh', bot: 'USD/MWh', potencia: 'USD/kW-mes', epc: 'USD/kW' };

export const EFFORT_COST_MULT = { estandar: 1, reforzada: 2.5 } as const;
export const EFFORT_SCORE = { estandar: 0, reforzada: 12 } as const;

/** Proveedores por defecto según preferencia (para cotizar sin proveedores elegidos). */
export function defaultSuppliers(ctx: SimContext, techId: string, pref: 'baratos' | 'equilibrados' | 'calidad' = 'equilibrados'): { equipmentId?: string; epcId?: string } {
  const pick = (tipo: SupplierDef['tipo']) => {
    const list = Object.values(ctx.data.suppliers).filter((s) => s.tipo === tipo && s.tecnologias.includes(techId));
    if (!list.length) return undefined;
    const score = (s: SupplierDef) => pref === 'baratos' ? s.factor_precio : pref === 'calidad' ? -s.calidad : Math.abs(s.factor_precio - 1) - 0.01 * s.calidad;
    return [...list].sort((a, b) => score(a) - score(b) || a.id.localeCompare(b.id))[0].id;
  };
  return { equipmentId: pick('equipos'), epcId: pick('epc') };
}

/** Potencia instalada necesaria para cumplir el contrato (en potencia: MW firmes / fracción firme). */
export function nameplateMw(ctx: SimContext, opp: Pick<Opportunity, 'contract' | 'mw'>, techId: string): number {
  if (opp.contract !== 'potencia') return opp.mw;
  const f = ctx.data.clients?.potencia_firme_frac[techId] ?? 0;
  return f > 0 ? opp.mw / f : Infinity;
}

export interface BidQuote {
  ok: boolean;
  error?: string;
  unit: string;
  /** Precio que deja VAN = 0 con la tasa usada (USD por la unidad del contrato). */
  breakEvenPrice: number;
  /** Precio sugerido = equilibrio × (1 + margen). */
  suggestedPrice: number;
  marginPct: number;
  capexUsd: number;
  capexUsdKw: number;
  fcP50: number;
  energyMwhYear: number;
  nameplateMw: number;
  discountRate: number;
  bidBondUsd: number;
  performanceBondUsd: number;
  prepCostUsd: number;
  prepCostReforzadaUsd: number;
  /** Puntaje técnico que tendría la oferta (0–100). */
  technicalScore: number;
  experienceScore: number;
  /** Plazo de entrega realista estimado (meses). */
  realisticDeliveryMonths: number;
}

export interface QuoteOptions {
  techId: string;
  projectId?: string;
  marginPct?: number;
  discountRate?: number;
  equipmentId?: string;
  epcId?: string;
  effort?: 'estandar' | 'reforzada';
}

/** Meses de obra según tamaño: las plantas pequeñas se construyen más rápido (× (MW/típico)^0,3, entre 0,4 y 1,3). */
export function buildMonths(tech: { construccion_meses: { base: number }; escala_mw: { tipico: number } }, mw: number): number {
  return tech.construccion_meses.base * Math.min(1.3, Math.max(0.4, Math.pow(mw / tech.escala_mw.tipico, 0.3)));
}

/** Plazo realista (meses): desarrollo pendiente + obra + puesta en marcha. */
export function realisticDeliveryMonths(state: GameState, ctx: SimContext, opp: Opportunity, techId: string, projectId?: string): number {
  const tech = ctx.data.technologies[techId];
  if (!tech) return opp.codMonths;
  const build = tech.construccion_meses.base + tech.puesta_en_marcha_dias.base / 30.44;
  if (opp.contract === 'epc') return buildMonths(tech, opp.mw) + 1.5;
  const p = projectId ? state.projects.find((x) => x.id === projectId) : undefined;
  if (p?.operation) return 1;
  if (p?.construction) return Math.max(1, (1 - p.construction.progress) * p.construction.plannedDays / 30.44 + 1);
  const m = p ? maturity(ctx, p) : 0;
  return build + 22 * (1 - m) + 3;
}

/** Madurez del desarrollo (0–1): estudios requeridos hechos + permisos aprobados. */
export function maturity(ctx: SimContext, p: GameState['projects'][number]): number {
  if (p.construction || p.operation) return 1;
  const groups = requiredStudyGroups(ctx, p);
  const permits = applicablePermits(ctx, p);
  const total = groups.length + permits.length;
  if (!total) return 1;
  const done = groups.filter((g) => studyGroupDone(ctx, p, g)).length + permits.filter((d) => permitGroupApproved(ctx, p, d.grupo)).length;
  return done / total;
}

/** Puntaje técnico (0–100): base 50 + madurez del proyecto, medición bancable, proveedores, esfuerzo e I+D. */
export function technicalScore(state: GameState, ctx: SimContext, opp: Opportunity, b: { techId: string; projectId?: string; effort?: 'estandar' | 'reforzada'; deliveryMonths?: number; equipmentId?: string; epcId?: string }): number {
  let t = 50 + researchEffects(state, ctx).technicalScoreBonus + EFFORT_SCORE[b.effort ?? 'estandar'];
  const p = b.projectId ? state.projects.find((x) => x.id === b.projectId) : undefined;
  if (p) {
    t += 25 * maturity(ctx, p);
    if (p.estimate.sigma <= 0.035 + 1e-9) t += 8;
  }
  if (opp.contract === 'epc') {
    const sup = defaultSuppliers(ctx, b.techId);
    const eq = ctx.data.suppliers[b.equipmentId ?? sup.equipmentId ?? ''], epc = ctx.data.suppliers[b.epcId ?? sup.epcId ?? ''];
    if (eq && epc) t += 60 * ((eq.calidad + epc.calidad) / 2 - 0.8);
  }
  if (b.deliveryMonths !== undefined && b.deliveryMonths < 0.8 * realisticDeliveryMonths(state, ctx, opp, b.techId, b.projectId)) t -= 15; // plazo poco creíble
  return Math.max(0, Math.min(100, t));
}

/** Experiencia y reputación (0–100): base 30 + 35 por MW de experiencia frente al tamaño pedido + 0,35 × reputación. */
export function experienceScore(state: GameState, opp: Pick<Opportunity, 'mw'>): number {
  const exp = experienceMw(state);
  return 30 + 35 * Math.min(1, exp / Math.max(2 * opp.mw, 20)) + 0.35 * (state.business?.reputation ?? 0);
}

/** Cotización: costo de equilibrio y precio sugerido (misma función para jugador e IA). No usa información oculta. */
export function quoteBid(state: GameState, ctx: SimContext, opp: Opportunity, o: QuoteOptions): BidQuote {
  const tech = ctx.data.technologies[o.techId];
  const c = ctx.data.countries[opp.countryCode];
  const unit = PRICE_UNITS[opp.contract];
  const margin = o.marginPct ?? 0.1;
  const blank: BidQuote = {
    ok: false, unit, breakEvenPrice: 0, suggestedPrice: 0, marginPct: margin, capexUsd: 0, capexUsdKw: 0, fcP50: 0, energyMwhYear: 0, nameplateMw: 0, discountRate: 0,
    bidBondUsd: opp.bidBondUsd, performanceBondUsd: opp.performanceBondUsd, prepCostUsd: opp.prepCostUsd, prepCostReforzadaUsd: opp.prepCostUsd * EFFORT_COST_MULT.reforzada,
    technicalScore: 0, experienceScore: experienceScore(state, opp), realisticDeliveryMonths: opp.codMonths,
  };
  if (!tech) return { ...blank, error: 'Tecnología sin modelo todavía.' };
  if (!c) return { ...blank, error: 'País sin datos.' };
  const p = o.projectId ? state.projects.find((x) => x.id === o.projectId) : undefined;
  const mw = p ? p.mw : nameplateMw(ctx, opp, o.techId);
  if (!Number.isFinite(mw)) return { ...blank, error: `${tech.nombre} no aporta potencia firme reconocida.` };
  const fx = researchEffects(state, ctx);
  const sup = { ...defaultSuppliers(ctx, o.techId), ...(p?.suppliers ?? {}), ...(o.equipmentId ? { equipmentId: o.equipmentId } : {}), ...(o.epcId ? { epcId: o.epcId } : {}) };
  const cap = currentCapex(state, ctx, { techId: o.techId, mw, countryCode: opp.countryCode, capexFactor: p?.capexFactor ?? 1, ...sup });
  const capex = p?.financing?.status === 'cerrado' ? p.financing.budgetUsd : cap.totalUsd;
  const lender = c.finanzas.prestamistas.find((l) => l.tipo === 'comercial') ?? c.finanzas.prestamistas[0];
  const r = o.discountRate ?? discountRates(c, o.techId, 'cierre_financiero', 0.7, lenderRate(c, lender)).wacc + 0.01;
  const tech0 = { technicalScore: technicalScore(state, ctx, opp, { ...o, ...sup }), realisticDeliveryMonths: realisticDeliveryMonths(state, ctx, opp, o.techId, o.projectId) };

  if (opp.contract === 'epc') {
    const k = ctx.data.clients?.epc.contingencia_frac ?? 0.05;
    const cost = (cap.equipmentUsd + cap.freightUsd + cap.tariffsUsd + cap.epcUsd + 0.5 * cap.otherUsd) * (1 + k);
    const perKw = cost / (mw * 1000);
    return { ...blank, ...tech0, ok: true, breakEvenPrice: perKw, suggestedPrice: perKw * (1 + margin), capexUsd: cost, capexUsdKw: perKw, nameplateMw: mw, discountRate: r };
  }

  const fc = p ? projectEconomics(state, ctx, p).fcP50 : tech.factor_capacidad_ref.base * fx.fcMult(o.techId);
  const avail = expectedAvailability(tech, mw);
  const energy = mw * 8760 * fc * avail;
  const fixed = annualFixedCosts(tech, c, mw, capex, 'preventivo', fx.omMult(o.techId)).totalUsd + expectedRepairCostUsd(tech, mw);
  const life = Math.round(tech.vida_util_anos.base);
  const years = Math.min(opp.years, life);
  const devAllowance = p ? 0 : 0.04 * capex;
  let pvCost = capex + devAllowance, pvE = 0, pvTail = 0, ann = 0;
  const y0 = startYear(state), yNow = currentYear(state);
  // Fase 4: costo variable (combustible, carbono, carga) y precio sin contrato con las mismas fórmulas que la operación.
  const terms = productTerms(state, ctx, tech, c, { spotUsdMwh: annualSpotUsd(state, c, y0, yNow), capture: techCaptureFactor(c, tech, tech.recurso ?? 'sin_recurso'), yearsFromStart: yNow - y0, resourceValue: p?.estimate.value });
  const fuel = terms.fuel.varUsdMwh;
  const deg = effectiveDegradation(tech, c);
  const spot = terms.priceUsdMwh * 0.85;
  for (let t = 1; t <= life; t++) {
    const e = energy * Math.pow(1 - deg, t - 1);
    const df = Math.pow(1 + r, -t);
    pvCost += (fixed + (tech.om_variable_usd_mwh.base + fuel) * e) * df;
    if (t <= years) { pvE += e * df; ann += df; }
    else if (opp.contract !== 'bot') pvTail += e * spot * df; // tras el contrato vende al spot (en BOT la planta se transfiere)
  }
  let be: number;
  if (opp.contract === 'potencia') {
    // Potencia firme: la energía se vende al spot durante toda la vida; el pago por potencia cubre el resto.
    let pvSpot = 0;
    for (let t = 1; t <= life; t++) pvSpot += energy * Math.pow(1 - tech.degradacion_anual.base, t - 1) * spot * Math.pow(1 + r, -t);
    be = Math.max(0.5, (pvCost - pvSpot) / (ann * opp.mw * 1000 * 12));
  } else be = Math.max(1, (pvCost - pvTail) / Math.max(1, pvE));
  return {
    ...blank, ...tech0, ok: true, breakEvenPrice: be, suggestedPrice: be * (1 + margin), capexUsd: capex, capexUsdKw: capex / (mw * 1000),
    fcP50: fc, energyMwhYear: energy, nameplateMw: mw, discountRate: r,
  };
}

/** Faltantes para ofertar (vacío = se puede). Misma validación para jugador e IA. */
export function bidBlockers(state: GameState, ctx: SimContext, opp: Opportunity | undefined, b: { techId: string; price?: number; deliveryMonths?: number; projectId?: string; effort?: 'estandar' | 'reforzada'; equipmentId?: string; epcId?: string }): string[] {
  if (!opp) return ['Oportunidad inexistente.'];
  const out: string[] = [];
  const me = actorIdOf(state);
  if (opp.status !== 'abierta' || state.tick >= opp.deadlineTick) out.push('El plazo para ofertar ya cerró.');
  if (opp.bids.some((x) => x.actorId === me && x.status === 'presentada')) out.push('Ya presentaste una oferta.');
  if (!contractUnlocked(state, ctx, opp.contractType)) out.push(`Requiere investigación: ${unlockingNode(ctx, 'contratos', opp.contractType)?.nombre ?? opp.contractType}.`);
  if (!countryUnlocked(state, ctx, opp.countryCode)) out.push(`Mercado cerrado: ${opp.countryCode}.`);
  else if (!hasPresence(state, opp.countryCode)) out.push(`Sin presencia en ${ctx.data.countries[opp.countryCode]?.nombre ?? opp.countryCode}: abre antes una sociedad local.`);
  const tech = ctx.data.technologies[b.techId];
  if (!opp.techs.includes(b.techId)) out.push('La tecnología no está admitida en esta oportunidad.');
  else if (!tech) out.push('Esa tecnología aún no tiene modelo en el juego.');
  else if (!techUnlocked(state, ctx, b.techId)) out.push(`Requiere investigación: ${unlockingNode(ctx, 'tecnologias', b.techId)?.nombre ?? b.techId}.`);
  if (opp.contract === 'potencia' && tech && !Number.isFinite(nameplateMw(ctx, opp, b.techId))) out.push('Esa tecnología no aporta potencia firme.');
  if (experienceMw(state) < opp.minExperienceMw) out.push(`Exige ${opp.minExperienceMw} MW de experiencia (tienes ${Math.round(experienceMw(state))}).`);
  if (opp.minEquityUsd > 0 && balanceSheet(state).equityUsd < opp.minEquityUsd) out.push(`Exige un patrimonio de ${fmt(opp.minEquityUsd)}.`);
  if (b.price !== undefined && !(b.price > 0)) out.push('Precio inválido.');
  if (b.deliveryMonths !== undefined && !(b.deliveryMonths >= 3 && b.deliveryMonths <= opp.codMonths)) out.push(`El plazo de entrega debe estar entre 3 y ${opp.codMonths} meses.`);
  if (b.projectId) {
    if (opp.contract === 'epc') out.push('En un EPC para terceros no se vincula un proyecto propio.');
    const p = state.projects.find((x) => x.id === b.projectId);
    if (!p) out.push('Proyecto inexistente.');
    else {
      const need = nameplateMw(ctx, opp, b.techId);
      if (isTerminal(p)) out.push('El proyecto está cerrado.');
      if (p.techId !== b.techId) out.push('El proyecto es de otra tecnología.');
      if (p.countryCode !== opp.countryCode) out.push('El proyecto está en otro país.');
      if (p.mw < 0.9 * need || p.mw > 1.5 * need) out.push(`El proyecto debe tener entre ${Math.ceil(0.9 * need)} y ${Math.floor(1.5 * need)} MW.`);
      if (p.contractId || p.ppa?.status === 'firmado' || p.ppa?.status === 'en_proceso') out.push('El proyecto ya tiene un contrato de venta.');
      if (opp.bids.some((x) => x.projectId === p.id && x.status === 'presentada')) out.push('El proyecto ya está en otra oferta.');
      if (p.sale?.status === 'en_proceso') out.push('El proyecto está en venta.');
    }
  }
  for (const id of [b.equipmentId, b.epcId]) if (id && (!ctx.data.suppliers[id] || !ctx.data.suppliers[id].tecnologias.includes(b.techId))) out.push('Proveedor inválido para esa tecnología.');
  const cost = opp.prepCostUsd * EFFORT_COST_MULT[b.effort ?? 'estandar'] + opp.bidBondUsd * (ctx.data.clients?.garantias.colateral_frac ?? 1);
  if (state.company.cashUsd < cost) out.push(`Caja insuficiente: preparar la oferta y su garantía cuesta ${fmt(cost)}.`);
  return out;
}

const fmt = (v: number) => `${Math.round(v).toLocaleString('es-PA')} USD`;

export function applyBidCommand(state: GameState, ctx: SimContext | undefined, cmd: BidCommand, events: SimEvent[]): Result {
  if (!ctx?.data.clients) return { ok: false, error: 'No hay licitaciones en los datos.' };
  const opp = state.market.opportunities.find((o) => o.id === cmd.opportunityId);
  const me = actorIdOf(state);
  if (cmd.type === 'withdrawBid') {
    const b = opp?.bids.find((x) => x.actorId === me && x.status === 'presentada');
    if (!opp || !b) return { ok: false, error: 'No tienes una oferta vigente en esa oportunidad.' };
    if (opp.status !== 'abierta') return { ok: false, error: 'La oferta ya está en evaluación: retirarla ejecutaría la garantía.' };
    b.status = 'retirada';
    releaseBond(state, ctx, b.bondUsd, `Garantía de seriedad devuelta (${opp.clientName})`);
    events.push({ type: 'bidWithdrawn', opportunityId: opp.id, text: `Oferta retirada: ${opp.clientName}. El costo de preparación no se recupera.`, severity: 'info' });
    return { ok: true };
  }
  const blockers = bidBlockers(state, ctx, opp, cmd);
  if (blockers.length) return { ok: false, error: blockers.join(' ') };
  const o = opp!;
  const effort = cmd.effort ?? 'estandar';
  const prep = o.prepCostUsd * EFFORT_COST_MULT[effort];
  postCash(state, 'licitaciones', -prep, `Oferta para ${o.clientName}`);
  postBond(state, ctx, o.bidBondUsd, `Garantía de seriedad (${o.clientName})`);
  const bid: Bid = {
    id: `${o.id}-${me}`, opportunityId: o.id, actorId: me, actorName: state.company.name, techId: cmd.techId, price: cmd.price,
    deliveryMonths: Math.round(cmd.deliveryMonths), projectId: cmd.projectId, effort, equipmentId: cmd.equipmentId, epcId: cmd.epcId,
    submittedTick: state.tick, bondUsd: o.bidBondUsd, prepCostUsd: prep, status: 'presentada',
  };
  o.bids = o.bids.filter((x) => x.id !== bid.id);
  o.bids.push(bid);
  events.push({ type: 'bidSubmitted', opportunityId: o.id, text: `Oferta presentada a ${o.clientName}: ${cmd.price.toFixed(o.contract === 'epc' ? 0 : 1)} ${PRICE_UNITS[o.contract]}, entrega en ${bid.deliveryMonths} meses (preparación ${fmt(prep)}, garantía ${fmt(o.bidBondUsd)}).`, severity: 'info' });
  return { ok: true };
}
