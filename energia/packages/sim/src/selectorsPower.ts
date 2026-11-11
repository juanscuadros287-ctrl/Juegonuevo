import type { GameState } from './core/state';
import type { SimContext } from './core/context';
import { fromEpochDay, type GameDate } from './core/calendar';
import { DAY_TYPES, countryFleetMw, currentYm, forecastBand, monthPrices, powerCountry, yearMonthFromIndex, type MonthPrices } from './market/power';
import { describePolicy } from './project/commands';
import { ppaTerminationPenalty, projectEconomics } from './project/economics';
import { currentPlan } from './project/tick';
import { projectPlan } from './market/dispatch';
import { insurancePremium, insuredValueUsd, type ActiveWorldEvent } from './world/events';
import { techMode } from './tech/models';
import { isTerminal } from './project/helpers';
import { saleValuation } from './project/valuation';
import type { WorldEventEffects } from './data/types';

/**
 * Fase 5: selectores para la UI (solo lectura, sin RNG): mercado eléctrico por país (curva de oferta, precios por hora
 * y mes, previsión de 12 meses con banda, historial, clima), despacho de cada planta (perfil horario típico del mes e
 * ingresos por fuente), eventos del mundo (activos y pasados) y seguros.
 */

const MONTHS = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

export interface HourPoint { dayType: 'laborable' | 'finde'; hour: number; priceUsdMwh: number; demandMw: number; curtailFrac: number }

export interface PowerMarketView {
  countryCode: string;
  countryName: string;
  available: boolean;
  year: number;
  month: number;
  monthLabel: string;
  /** Precios horarios del mes en curso (días tipo). */
  hours: HourPoint[];
  avgUsdMwh: number;
  peakUsdMwh: number;
  offpeakUsdMwh: number;
  minUsdMwh: number;
  maxUsdMwh: number;
  priceCapUsdMwh: number;
  priceFloorUsdMwh: number;
  /** Curva de oferta (orden de mérito) del mes: bloques de MW con su costo marginal, de menor a mayor. */
  supplyCurve: { label: string; mw: number; cumulativeMw: number; costUsdMwh: number }[];
  waterValueUsdMwh: number;
  /** Previsión de 12 meses (desde el mes en curso) con banda P10–P90. */
  forecast: { year: number; month: number; label: string; avgUsdMwh: number; peakUsdMwh: number; offpeakUsdMwh: number; p10UsdMwh: number; p90UsdMwh: number }[];
  /** Historial mensual (hasta 120 meses). */
  history: { year: number; month: number; avgUsdMwh: number; peakUsdMwh: number; offpeakUsdMwh: number; minUsdMwh: number; maxUsdMwh: number; hydrology: number }[];
  /** Referencia histórica del YAML (spot medio de la Fase 2–4). */
  historicalMeanUsdMwh: number;
  climate: ClimateView;
  /** Parque por clase: existente (crece con la demanda) y de los actores del juego. */
  fleet: { cls: string; label: string; existingMw: number; actorsMw: number }[];
  capacityMarket?: { name: string; priceUsdKwMonth: number };
  ancillary?: { name: string; priceUsdMwH: number; requirementMw: number; offeredMw: number };
}

export interface ClimateView {
  enso: 'nino' | 'nina' | 'neutral';
  ensoLabel: string;
  /** Hidrología del año (1 = normal) y texto. */
  hydrology: number;
  hydrologyLabel: string;
}

const CLASS_LABEL = (ctx: SimContext, cls: string) => ctx.data.power?.clases[cls]?.nombre ?? ctx.data.technologies[cls]?.nombre ?? (cls === 'almacenamiento' ? 'Almacenamiento' : cls);

export function selectClimate(state: GameState, ctx: SimContext, iso: string): ClimateView {
  const ps = state.market?.power;
  const enso = ps?.enso ?? 'neutral';
  const h = ps?.hydrology[iso] ?? 1;
  return {
    enso, ensoLabel: enso === 'nino' ? 'El Niño' : enso === 'nina' ? 'La Niña' : 'Neutral',
    hydrology: h, hydrologyLabel: h < 0.8 ? 'Año seco' : h < 0.93 ? 'Algo seco' : h > 1.2 ? 'Año muy húmedo' : h > 1.07 ? 'Húmedo' : 'Normal',
  };
}

function hoursOf(mp: MonthPrices): HourPoint[] {
  const out: HourPoint[] = [];
  for (let d = 0; d < 2; d++) for (let h = 0; h < 24; h++) out.push({ dayType: DAY_TYPES[d], hour: h, priceUsdMwh: mp.prices[d][h], demandMw: mp.demand[d][h], curtailFrac: mp.curtail[d][h] });
  return out;
}

/** Mercado eléctrico de un país. */
export function selectPowerMarket(state: GameState, ctx: SimContext, iso: string): PowerMarketView {
  const c = ctx.data.countries[iso];
  const pc = powerCountry(ctx, iso);
  const { year, month } = yearMonthFromIndex(currentYm(state));
  const mp = monthPrices(state, ctx, iso, year, month);
  const empty: PowerMarketView = {
    countryCode: iso, countryName: c?.nombre ?? iso, available: false, year, month, monthLabel: `${MONTHS[month - 1]} ${year}`, hours: [], avgUsdMwh: 0, peakUsdMwh: 0, offpeakUsdMwh: 0,
    minUsdMwh: 0, maxUsdMwh: 0, priceCapUsdMwh: 0, priceFloorUsdMwh: 0, supplyCurve: [], waterValueUsdMwh: 0, forecast: [], history: [],
    historicalMeanUsdMwh: c?.mercado.precio_spot_medio_usd_mwh.base ?? 0, climate: selectClimate(state, ctx, iso), fleet: [],
  };
  if (!c || !pc || !mp) return empty;
  const fleet = countryFleetMw(state, ctx, iso);
  // Curva de oferta: lo que entra a costo ~0 (renovables, base, hidro de pasada), la hidro de embalse al valor del agua y los térmicos.
  const curve: PowerMarketView['supplyCurve'] = [];
  let cum = 0;
  const add = (label: string, mw: number, cost: number) => { if (mw <= 0.5) return; cum += mw; curve.push({ label, mw, cumulativeMw: cum, costUsdMwh: cost }); };
  for (const cls of ['solar', 'eolica', 'geotermia', 'nuclear']) {
    const f = fleet[cls];
    if (f) add(CLASS_LABEL(ctx, cls), f.existingMw + f.actorsMw, ctx.data.power!.clases[cls]?.om_variable_usd_mwh ?? 0);
  }
  if (fleet.hidro) add(CLASS_LABEL(ctx, 'hidro'), fleet.hidro.existingMw + fleet.hidro.actorsMw, mp.waterValue);
  const thermal = [...mp.thermalMc].sort((a, b) => a.mc - b.mc);
  for (const b of thermal) add(CLASS_LABEL(ctx, b.cls), b.mw, b.mc);
  const forecast: PowerMarketView['forecast'] = [];
  for (let i = 0; i < 12; i++) {
    const t = yearMonthFromIndex(currentYm(state) + i);
    const f = monthPrices(state, ctx, iso, t.year, t.month)!;
    const band = forecastBand(state, ctx, iso, t.year, t.month) ?? { p10: f.avg, p90: f.avg };
    forecast.push({ year: t.year, month: t.month, label: `${MONTHS[t.month - 1]} ${t.year}`, avgUsdMwh: f.avg, peakUsdMwh: f.peak, offpeakUsdMwh: f.offpeak, p10UsdMwh: Math.min(band.p10, f.avg), p90UsdMwh: Math.max(band.p90, f.avg) });
  }
  const hist = (state.market?.power?.history[iso] ?? []).map((h) => ({ year: h.year, month: h.month, avgUsdMwh: h.avg, peakUsdMwh: h.peak, offpeakUsdMwh: h.offpeak, minUsdMwh: h.min, maxUsdMwh: h.max, hydrology: h.hydrology }));
  const svc = pc.servicios;
  const req = svc ? svc.requerimiento_frac_demanda * mp.demand[0].reduce((a, b) => a + b, 0) / 24 : 0;
  return {
    ...empty, available: true, hours: hoursOf(mp), avgUsdMwh: mp.avg, peakUsdMwh: mp.peak, offpeakUsdMwh: mp.offpeak, minUsdMwh: mp.min, maxUsdMwh: mp.max,
    priceCapUsdMwh: pc.precio_techo_usd_mwh, priceFloorUsdMwh: pc.precio_piso_usd_mwh, supplyCurve: curve, waterValueUsdMwh: mp.waterValue, forecast, history: hist,
    fleet: Object.entries(fleet).map(([cls, v]) => ({ cls, label: CLASS_LABEL(ctx, cls), existingMw: v.existingMw, actorsMw: v.actorsMw })).sort((a, b) => b.existingMw + b.actorsMw - a.existingMw - a.actorsMw),
    capacityMarket: pc.capacidad ? { name: pc.capacidad.nombre, priceUsdKwMonth: pc.capacidad.precio_usd_kw_mes.base } : undefined,
    ancillary: svc ? { name: svc.nombre, priceUsdMwH: svc.precio_usd_mw_h.base, requirementMw: req, offeredMw: state.market?.power?.fleet[iso]?.servicesMw ?? 0 } : undefined,
  };
}

/** Resumen de precios de todos los países con mercado (para un mapa o una tabla). */
export function selectPowerMarkets(state: GameState, ctx: SimContext): { countryCode: string; countryName: string; avgUsdMwh: number; peakUsdMwh: number; offpeakUsdMwh: number; hydrology: number; change12mPct: number | null }[] {
  const { year, month } = yearMonthFromIndex(currentYm(state));
  return Object.keys(ctx.data.countries).sort().filter((iso) => powerCountry(ctx, iso)).map((iso) => {
    const mp = monthPrices(state, ctx, iso, year, month)!;
    const h = state.market?.power?.history[iso] ?? [];
    const ago = h.length >= 12 ? h[h.length - 12] : undefined;
    return { countryCode: iso, countryName: ctx.data.countries[iso].nombre, avgUsdMwh: mp.avg, peakUsdMwh: mp.peak, offpeakUsdMwh: mp.offpeak, hydrology: mp.hydrology, change12mPct: ago ? (mp.avg / ago.avg - 1) * 100 : null };
  });
}

// ───────────────────────── Despacho de una planta ─────────────────────────

export interface PlantDispatchView {
  projectId: string;
  name: string;
  techId: string;
  mode: string;
  countryCode: string;
  operating: boolean;
  policy: import('./market/dispatch').DispatchPolicy;
  policyText: string;
  /** Qué reglas acepta esta tecnología (para el formulario). */
  policyOptions: { storageThresholds: boolean; minPrice: boolean; priority: boolean; ancillary: boolean; h2MaxPrice: boolean };
  month: { year: number; month: number; label: string };
  /** Resumen del plan del mes. */
  plan?: { genFrac: number; captureUsdMwh: number; avgSpotUsdMwh: number; chargeUsdMwh: number; curtailedFrac: number; servicesFrac: number; servicesUsdMwH: number };
  /** Perfil horario típico del mes (MW): generación o descarga, carga y precio. */
  hourly: { dayType: 'laborable' | 'finde'; hour: number; priceUsdMwh: number; generationMw: number; chargeMw: number }[];
  /** Ingresos por fuente (últimos 24 meses). */
  revenue: { year: number; month: number; energyMwh: number; ppaUsd: number; spotUsd: number; capacityUsd: number; servicesUsd: number; purchasesUsd: number; curtailedMwh: number; captureUsdMwh: number | null }[];
  /** Totales de los últimos 12 meses. */
  revenue12m: { ppaUsd: number; spotUsd: number; capacityUsd: number; servicesUsd: number; purchasesUsd: number };
  sales: {
    mode: 'ppa' | 'merchant';
    ppa?: { channelId: string; status: string; priceUsdMwh: number; settlement: 'produccion' | 'bloque' | 'financiero'; committedMwhYear?: number; yearsLeft?: number; canTerminate: boolean; terminationPenaltyUsd?: number };
    /** Valoración de venta (con el descuento merchant del comprador). */
    saleValueUsd: number;
    merchantDiscount: boolean;
  };
  insurance: InsuranceView;
  codBlocked: boolean;
}

export interface InsuranceView {
  insurable: boolean;
  insuredValueUsd: number;
  current?: { coverage: 'danos' | 'danos_lucro'; premiumUsdYear: number; coveredFrom: GameDate; active: boolean; claims: { date: GameDate; paidUsd: number }[] };
  quotes: { coverage: 'danos' | 'danos_lucro'; premiumUsdYear: number; ratePct: number }[];
  /** Pérdida esperada anual por catástrofes (fracción del valor) en este sitio y tecnología. */
  expectedLossPct: number;
}

const dateOf = (state: GameState, tick: number) => fromEpochDay(state.startEpochDay + tick);

export function selectPlantDispatch(state: GameState, ctx: SimContext, projectId: string): PlantDispatchView | null {
  const p = state.projects.find((x) => x.id === projectId);
  if (!p) return null;
  const tech = ctx.data.technologies[p.techId];
  const mode = techMode(tech);
  const { year, month } = yearMonthFromIndex(currentYm(state));
  const pc = powerCountry(ctx, p.countryCode);
  let plan: PlantDispatchView['plan'];
  const hourly: PlantDispatchView['hourly'] = [];
  if (pc) {
    const base = p.operation ? currentPlanReadOnly(state, ctx, p, year, month) : undefined;
    const fcRef = p.operation?.fcReal ?? projectEconomics(state, ctx, p).fcP50;
    const terms = mode === 'termica' ? projectEconomics(state, ctx, p) : undefined;
    const d = projectPlan(state, ctx, p, year, month, { fcRef: p.operation ? fcRef : projectEconomics(state, ctx, p).fcP50, thermalMcUsdMwh: terms ? terms.fuelCostUsdMwh + tech.om_variable_usd_mwh.base : undefined }, true);
    if (d) {
      const pl = base ?? d;
      plan = { genFrac: pl.genFrac, captureUsdMwh: pl.captureUsdMwh, avgSpotUsdMwh: pl.avgSpotUsdMwh, chargeUsdMwh: pl.chargeUsdMwh, curtailedFrac: pl.curtailedFrac, servicesFrac: pl.servicesFrac, servicesUsdMwH: pl.servicesUsdMwH };
      // MW = por MW de potencia × MW; para generación se escala por el FC (la forma tiene media 1).
      const scale = mode === 'almacenamiento' || mode === 'hidrogeno' || mode === 'termica' ? p.mw : p.mw * fcRef;
      for (let dt = 0; dt < 2; dt++) for (let h = 0; h < 24; h++) hourly.push({ dayType: DAY_TYPES[dt], hour: h, priceUsdMwh: d.price[dt][h], generationMw: d.gen[dt][h] * scale, chargeMw: d.charge[dt][h] * scale });
    }
  }
  const hist = (p.operation?.history ?? []).slice(-24);
  const revenue = hist.map((h) => ({ year: h.year, month: h.month, energyMwh: h.energyMwh, ppaUsd: h.ppaUsd ?? (h.spotUsd === undefined ? h.revenueUsd : 0), spotUsd: h.spotUsd ?? 0, capacityUsd: h.capacityUsd ?? 0, servicesUsd: h.servicesUsd ?? 0, purchasesUsd: h.purchasesUsd ?? 0, curtailedMwh: h.curtailedMwh ?? 0, captureUsdMwh: h.captureUsdMwh ?? null }));
  const r12 = revenue.slice(-12).reduce((a, r) => ({ ppaUsd: a.ppaUsd + r.ppaUsd, spotUsd: a.spotUsd + r.spotUsd, capacityUsd: a.capacityUsd + r.capacityUsd, servicesUsd: a.servicesUsd + r.servicesUsd, purchasesUsd: a.purchasesUsd + r.purchasesUsd }), { ppaUsd: 0, spotUsd: 0, capacityUsd: 0, servicesUsd: 0, purchasesUsd: 0 });
  const ppa = p.ppa;
  const yearsOp = p.operation ? (state.tick - p.operation.codTick) / 365.25 : 0;
  const sv = !isTerminal(p) ? saleValuation(state, ctx, p) : { valueUsd: 0, merchant: false };
  const ins = p.insurance;
  const s = ctx.data.world?.seguros;
  const insurable = !!ctx.data.world && (!!p.operation || !!p.construction) && !isTerminal(p);
  const quote = (cov: 'danos' | 'danos_lucro') => { const q = insurancePremium(ctx, p, cov); return { coverage: cov, premiumUsdYear: q.premiumUsdYear, ratePct: q.rate * 100 }; };
  return {
    projectId: p.id, name: p.name, techId: p.techId, mode, countryCode: p.countryCode, operating: !!p.operation,
    policy: p.dispatch ?? {}, policyText: describePolicy(p.dispatch ?? {}),
    policyOptions: {
      storageThresholds: mode === 'almacenamiento', minPrice: mode === 'generacion' || mode === 'termica', priority: mode === 'termica' && !!ppa,
      ancillary: !!pc?.servicios && (mode === 'almacenamiento' || mode === 'termica' || !!tech.hidro?.regulacion), h2MaxPrice: mode === 'hidrogeno',
    },
    month: { year, month, label: `${MONTHS[month - 1]} ${year}` }, plan, hourly, revenue, revenue12m: r12,
    sales: {
      mode: ppa?.status === 'firmado' ? 'ppa' : 'merchant',
      ppa: ppa ? {
        channelId: ppa.channelId, status: ppa.status, priceUsdMwh: ppa.priceUsdMwh, settlement: ppa.settlement ?? 'produccion', committedMwhYear: ppa.committedMwhYear,
        yearsLeft: ppa.status === 'firmado' ? Math.max(0, ppa.years - yearsOp) : undefined,
        canTerminate: ppa.status === 'firmado' && !p.contractId,
        terminationPenaltyUsd: ppa.status === 'firmado' && !p.contractId ? ppaTerminationPenalty(state, ctx, p) : undefined,
      } : undefined,
      saleValueUsd: sv.valueUsd, merchantDiscount: sv.merchant,
    },
    insurance: {
      insurable, insuredValueUsd: insuredValueUsd(p),
      current: ins ? { coverage: ins.coverage, premiumUsdYear: ins.premiumUsdYear, coveredFrom: dateOf(state, ins.startTick + (s?.espera_dias ?? 0)), active: state.tick >= ins.startTick + (s?.espera_dias ?? 0), claims: ins.claims.map((c) => ({ date: dateOf(state, c.tick), paidUsd: c.paidUsd })) } : undefined,
      quotes: insurable ? [quote('danos'), quote('danos_lucro')] : [],
      expectedLossPct: insurancePremium(ctx, p, 'danos').expectedLossFrac * 100,
    },
    codBlocked: !!p.codBlocked,
  };
}

/** El plan guardado del mes (sin recalcular ni escribir en el estado). */
function currentPlanReadOnly(state: GameState, ctx: SimContext, p: GameState['projects'][number], year: number, month: number) {
  const op = p.operation;
  if (!op) return undefined;
  if (op.plan && yearMonthFromIndex(op.plan.ym).year === year && yearMonthFromIndex(op.plan.ym).month === month) return op.plan;
  // Copia: currentPlan escribe el caché en la operación; el selector no debe tocar la partida.
  const copy = { ...p, operation: { ...op, plan: undefined } };
  return currentPlan(state, ctx, copy, year, month);
}

/** Ingresos de la empresa por fuente (últimos 12 meses cerrados). */
export function selectRevenueBySource(state: GameState): { energyUsd: number; capacityUsd: number; servicesUsd: number; purchasesUsd: number; insuranceUsd: number; byMonth: { year: number; month: number; energyUsd: number; capacityUsd: number; servicesUsd: number; purchasesUsd: number }[] } {
  const st = state.finance.statements.slice(-12);
  const g = (s: typeof st[number], k: string) => s.lines[k] ?? 0;
  const byMonth = st.map((s) => ({ year: s.year, month: s.month, energyUsd: g(s, 'ingresos'), capacityUsd: g(s, 'ingresos_capacidad'), servicesUsd: g(s, 'ingresos_servicios'), purchasesUsd: -g(s, 'compras_energia') }));
  const sum = (k: string) => st.reduce((a, s) => a + g(s, k), 0);
  return { energyUsd: sum('ingresos'), capacityUsd: sum('ingresos_capacidad'), servicesUsd: sum('ingresos_servicios'), purchasesUsd: -sum('compras_energia'), insuranceUsd: sum('indemnizaciones'), byMonth };
}

// ───────────────────────── Eventos del mundo ─────────────────────────

export interface WorldEventView {
  uid: number;
  id: string;
  name: string;
  kind: string;
  countries: string[] | null;
  scopeLabel: string;
  start: GameDate;
  end: GameDate;
  active: boolean;
  daysLeft: number;
  text: string;
  /** Efectos en texto (para tarjetas y avisos). */
  effects: string[];
  damage?: { plants: number; costUsd: number };
}

export function effectTexts(e: WorldEventEffects): string[] {
  const out: string[] = [];
  const pct = (x: number) => `${x >= 1 ? '+' : '−'}${Math.abs((x - 1) * 100).toFixed(0)} %`;
  for (const [f, m] of Object.entries(e.combustibles ?? {})) out.push(`Combustible ${f.replace(/_/g, ' ')} ${pct(m)}`);
  if (e.demanda) out.push(`Demanda eléctrica ${pct(e.demanda)}`);
  for (const [t, m] of Object.entries(e.capex ?? {})) out.push(`CAPEX ${t === 'todas' ? 'de todas las tecnologías' : t.replace(/_/g, ' ')} ${pct(m)}`);
  if (e.plazo_entrega) out.push(`Plazos de entrega de equipos ${pct(e.plazo_entrega)}`);
  if (e.plazo_permisos) out.push(`Plazos de permisos ${pct(e.plazo_permisos)}`);
  if (e.arancel) out.push(`Aranceles +${(e.arancel * 100).toFixed(0)} pp sobre equipos importados`);
  if (e.tipo_cambio) out.push(`Devaluación de ${(e.tipo_cambio * 100).toFixed(0)} %`);
  if (e.hidrologia) out.push(`Caudales ${pct(e.hidrologia)}`);
  if (e.obras_paradas_dias) out.push(`Obras paradas ≈ ${e.obras_paradas_dias.base} días`);
  if (e.danos) out.push(`Daños a plantas (más vulnerables: ${Object.entries(e.danos.vulnerabilidad).filter(([k]) => k !== 'otras').sort((a, b) => b[1] - a[1]).slice(0, 3).map(([k]) => k.replace(/_/g, ' ')).join(', ')})`);
  const r = e.regulacion;
  if (r?.carbono_usd_t) out.push(`Impuesto al carbono ${r.carbono_usd_t > 0 ? '+' : ''}${r.carbono_usd_t} USD/tCO2 (permanente)`);
  if (r?.plazo_permisos) out.push(`Plazos de permisos ${pct(r.plazo_permisos)} (permanente)`);
  if (r?.credito_fiscal !== undefined) out.push(`Crédito fiscal a la inversión ×${r.credito_fiscal} (permanente)`);
  for (const [t, m] of Object.entries(e.costo_tecnologia ?? {})) out.push(`Costo de ${t.replace(/_/g, ' ')} ${pct(m)} (permanente)`);
  return out;
}

function eventView(state: GameState, ctx: SimContext, e: ActiveWorldEvent, active: boolean): WorldEventView {
  return {
    uid: e.uid, id: e.defId, name: e.name, kind: e.kind, countries: e.countries,
    scopeLabel: e.countries ? e.countries.map((c) => ctx.data.countries[c]?.nombre ?? c).join(', ') : 'Mundial',
    start: dateOf(state, e.startTick), end: dateOf(state, e.endTick), active, daysLeft: active ? Math.max(0, e.endTick - state.tick) : 0,
    text: e.text, effects: effectTexts(e.effects), damage: e.damage,
  };
}

export interface WorldEventsOverview {
  active: WorldEventView[];
  past: WorldEventView[];
  /** Regulación vigente por país (resultado de elecciones y reformas). */
  regulation: { countryCode: string; countryName: string; government?: string; governmentName?: string; carbonAddUsdT: number; permitTimeFactor: number; taxCreditFactor: number; nextElection?: number }[];
  /** Cambios permanentes de costo por tecnología (avances). */
  techCost: { techId: string; factor: number }[];
  climate: { enso: string; ensoLabel: string };
}

export function selectWorldEvents(state: GameState, ctx: SimContext, opts: { countryCode?: string } = {}): WorldEventsOverview {
  const w = state.market?.world;
  const f = (e: ActiveWorldEvent) => !opts.countryCode || e.countries === null || e.countries.includes(opts.countryCode);
  const govs = ctx.data.world?.gobiernos ?? [];
  const isos = Object.keys(ctx.data.countries).sort().filter((iso) => !opts.countryCode || iso === opts.countryCode);
  const cl = selectClimate(state, ctx, opts.countryCode ?? state.company.homeCountry);
  return {
    active: (w?.active ?? []).filter(f).map((e) => eventView(state, ctx, e, true)),
    past: (w?.past ?? []).filter(f).slice().reverse().map((e) => eventView(state, ctx, e, false)),
    regulation: isos.map((iso) => {
      const r = w?.regulation[iso];
      return { countryCode: iso, countryName: ctx.data.countries[iso].nombre, government: r?.government, governmentName: govs.find((g) => g.id === r?.government)?.nombre,
        carbonAddUsdT: r?.carbonAddUsdT ?? 0, permitTimeFactor: r?.permitFactor ?? 1, taxCreditFactor: r?.creditFactor ?? 1, nextElection: w?.nextElection[iso] };
    }),
    techCost: Object.entries(w?.techCost ?? {}).map(([techId, factor]) => ({ techId, factor })),
    climate: { enso: cl.enso, ensoLabel: cl.ensoLabel },
  };
}
