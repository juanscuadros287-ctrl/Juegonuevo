import type { GameState } from '../core/state';
import type { SimContext } from '../core/context';
import type { TechnologyDef } from '../data/types';
import type { Project } from '../project/types';
import { DAY_WEIGHTS, monthPrices, storageDay, yearMonthIndex, type MonthPrices } from './power';
import { fxReal, usdInflation } from './macro';
import { techMode } from '../tech/models';
import { fromEpochDay } from '../core/calendar';

/**
 * Fase 5: despacho de una planta contra los precios horarios del mes (días tipo × 24 h).
 * Reglas automáticas configurables por planta (`setDispatchPolicy`): umbrales de carga/descarga, reserva mínima,
 * precio mínimo para producir (vertimiento voluntario), prioridad PPA o spot y participación en servicios complementarios.
 */
export interface DispatchPolicy {
  /** Almacenamiento: cargar solo si el precio ≤ este valor (USD/MWh). */
  cargarBajo?: number;
  /** Almacenamiento: descargar solo si el precio ≥ este valor (USD/MWh). */
  descargarSobre?: number;
  /** Almacenamiento: fracción de la energía que se reserva sin usar (0–0,9). */
  reservaMin?: number;
  /** Generación y térmicas: no producir si el spot < este valor (USD/MWh). Por defecto: 0 sin PPA (no vende a pérdida). */
  precioMinimo?: number;
  /** Con PPA: 'ppa' = cumplir con generación propia; 'spot' = comprar al spot cuando sale más barato que generar. */
  prioridad?: 'ppa' | 'spot';
  /** Ofrecer una fracción de la potencia en servicios complementarios (regulación/reserva). */
  servicios?: boolean;
  fraccionServicios?: number;
  /** Hidrógeno: comprar electricidad solo si el precio ≤ este valor (USD/MWh). */
  compraMaxima?: number;
}

export interface MonthPlan {
  ym: number;
  key: string;
  /** Fracción de la energía disponible que se produce (o se descarga). */
  genFrac: number;
  /** Precio spot medio que recibe lo producido (USD/MWh). */
  captureUsdMwh: number;
  /** Spot medio del mes (USD/MWh). */
  avgSpotUsdMwh: number;
  /** Almacenamiento: costo de la carga por MWh descargado; hidrógeno: precio medio de la electricidad comprada. */
  chargeUsdMwh: number;
  /** Fracción vertida (precio bajo o red saturada). */
  curtailedFrac: number;
  /** Fracción de la potencia ofrecida en servicios y pago por MW-h. */
  servicesFrac: number;
  servicesUsdMwH: number;
}

export interface PlanDetail extends MonthPlan {
  /** Por MW instalado, [tipo de día][hora]: generación/descarga, carga y precio. */
  gen: number[][];
  charge: number[][];
  price: number[][];
}

const SOLAR_TECHS = new Set(['solar_fv']);
const WIND_TECHS = new Set(['eolica_tierra', 'eolica_marina']);

function norm24(v: number[]): number[] {
  const m = v.reduce((a, b) => a + Math.max(0, b), 0) / 24 || 1;
  return v.map((x) => Math.max(0, x) / m);
}

/** Forma horaria de la producción disponible (media 1). */
export function availabilityShape(ctx: SimContext, tech: TechnologyDef): number[] {
  const P = ctx.data.power;
  if (P && SOLAR_TECHS.has(tech.id)) return norm24(P.formas_recurso.solar);
  if (P && WIND_TECHS.has(tech.id)) return norm24(P.formas_recurso.eolica);
  return new Array(24).fill(1);
}

export function policyKey(p: Pick<Project, 'dispatch' | 'ppa'>): string {
  const d = p.dispatch ?? {};
  return JSON.stringify([d.cargarBajo, d.descargarSobre, d.reservaMin, d.precioMinimo, d.prioridad, d.servicios, d.fraccionServicios, d.compraMaxima, p.ppa?.status, p.ppa?.settlement]);
}

export interface PlanInputs {
  tech: TechnologyDef;
  countryCode: string;
  policy: DispatchPolicy;
  /** Costo marginal de una térmica (USD/MWh: combustible + carbono + O&M variable). */
  thermalMcUsdMwh?: number;
  /** Precio del PPA vigente (USD/MWh) si vende por PPA «según producción». */
  ppaPriceUsdMwh?: number;
  /** H2: valor de la electricidad (USD/MWh) = kg/MWh × precio del H2 − agua. */
  h2ValueUsdMwh?: number;
  /** Utilización de referencia del producto (FC típico) para pasar de MWh/MW-día a fracción. */
  fcRef: number;
}

/** Pago de servicios complementarios por MW-h en el país (se diluye si la oferta supera el requerimiento). */
export function servicesPrice(state: GameState, ctx: SimContext, iso: string, mp: MonthPrices): number {
  const sv = ctx.data.power?.paises[iso]?.servicios;
  if (!sv) return 0;
  const c = ctx.data.countries[iso];
  const y0 = fromEpochDay(state.startEpochDay).year;
  const req = sv.requerimiento_frac_demanda * (mp.demand[0].reduce((a, b) => a + b, 0) / 24);
  const offered = state.market?.power?.fleet[iso]?.servicesMw ?? 0;
  const dil = offered > req ? req / offered : 1;
  return sv.precio_usd_mw_h.base * Math.pow(1 + usdInflation(c), Math.max(0, mp.year - y0)) * fxReal(state, iso) * dil;
}

/** Despacho de un mes (puro): genera el plan a partir de los precios horarios. */
export function planOnPrices(state: GameState, ctx: SimContext, mp: MonthPrices, o: PlanInputs, detail = false): PlanDetail {
  const t = o.tech;
  const mode = techMode(t);
  const pol = o.policy;
  const sh = availabilityShape(ctx, t);
  const vre = SOLAR_TECHS.has(t.id) || WIND_TECHS.has(t.id);
  const svcPrice = servicesPrice(state, ctx, o.countryCode, mp);
  const svcFrac = pol.servicios && svcPrice > 0 && (mode === 'almacenamiento' || mode === 'termica' || t.hidro?.regulacion) ? Math.max(0, Math.min(0.8, pol.fraccionServicios ?? 0.3)) : 0;
  const gen: number[][] = [], charge: number[][] = [];
  let sumAvail = 0, sumGen = 0, sumRev = 0, sumCharge = 0, sumChargeCost = 0, sumCurt = 0;
  for (let d = 0; d < 2; d++) {
    const pr = mp.prices[d], w = DAY_WEIGHTS[d];
    const g = new Array(24).fill(0), ch = new Array(24).fill(0);
    if (mode === 'almacenamiento') {
      const a = t.almacenamiento!;
      const usable = a.horas.base * (1 - Math.max(0, Math.min(0.9, pol.reservaMin ?? 0)));
      const cyclesCap = usable > 0 ? Math.min(1, 24 * o.fcRef / usable) : 0;
      const plan = storageDay(pr, { hours: usable, eff: a.eficiencia_ida_vuelta.base, cyclesCap, minSpread: t.om_variable_usd_mwh.base, chargeBelow: pol.cargarBajo, dischargeAbove: pol.descargarSobre });
      for (let h = 0; h < 24; h++) { g[h] = plan.discharge[h] * (1 - svcFrac); ch[h] = plan.charge[h] * (1 - svcFrac); }
      sumAvail += w * 24 * o.fcRef;
    } else if (mode === 'hidrogeno') {
      const util = Math.max(0.05, Math.min(1, o.fcRef));
      const thr = pol.compraMaxima ?? o.h2ValueUsdMwh ?? Infinity;
      const hours = [...pr.keys()].sort((x, y) => pr[x] - pr[y] || x - y);
      let left = util * 24;
      for (const h of hours) { if (left <= 0 || pr[h] > thr) break; const x = Math.min(1, left); g[h] = x; left -= x; }
      sumAvail += w * util * 24;
    } else if (mode === 'termica') {
      const mc = o.thermalMcUsdMwh ?? 0;
      const minP = Math.max(mc, pol.precioMinimo ?? -Infinity);
      const ppaRun = o.ppaPriceUsdMwh !== undefined && pol.prioridad !== 'spot' && o.ppaPriceUsdMwh >= mc;
      const base = t.termica?.despacho === 'base';
      const dayMargin = pr.reduce((a, x) => a + (x - mc), 0);
      for (let h = 0; h < 24; h++) {
        const on = ppaRun || (base ? dayMargin >= 0 || pr[h] >= minP : pr[h] >= minP);
        g[h] = on ? 1 - svcFrac : 0;
      }
      sumAvail += w * 24;
    } else if (mode === 'generacion' && t.hidro && t.hidro.regulacion > 0) {
      // Embalse: una parte de la energía se mueve a las horas más caras.
      const r = t.hidro.regulacion;
      const n = Math.max(1, Math.min(24, Math.round(24 * Math.max(0.2, o.fcRef))));
      const top = [...pr.keys()].sort((x, y) => pr[y] - pr[x] || x - y).slice(0, n);
      for (let h = 0; h < 24; h++) g[h] = (1 - r) + (top.includes(h) ? r * 24 / n : 0);
      for (let h = 0; h < 24; h++) g[h] *= 1 - svcFrac;
      sumAvail += w * 24;
    } else if (mode === 'generacion' && t.id === 'csp') {
      const n = Math.max(1, Math.min(24, Math.round(24 * Math.max(0.2, o.fcRef))));
      const top = [...pr.keys()].sort((x, y) => pr[y] - pr[x] || x - y).slice(0, n);
      for (let h = 0; h < 24; h++) g[h] = 0.4 * sh[h] + (top.includes(h) ? 0.6 * 24 / n : 0);
      sumAvail += w * 24;
    } else if (mode === 'generacion') {
      const minP = pol.precioMinimo ?? (o.ppaPriceUsdMwh !== undefined ? -Infinity : 0);
      for (let h = 0; h < 24; h++) {
        const cur = vre ? mp.curtail[d][h] : 0;
        const on = pr[h] >= minP ? 1 : 0;
        g[h] = sh[h] * on * (1 - cur);
        sumCurt += w * sh[h] * (1 - on * (1 - cur));
      }
      sumAvail += w * 24;
    } else {
      for (let h = 0; h < 24; h++) g[h] = 1;
      sumAvail += w * 24;
    }
    for (let h = 0; h < 24; h++) {
      const x = mode === 'hidrogeno' ? g[h] : g[h];
      sumGen += w * x;
      sumRev += w * x * pr[h];
      if (mode === 'almacenamiento') { sumCharge += w * ch[h]; sumChargeCost += w * ch[h] * pr[h]; }
      if (mode === 'hidrogeno') { sumChargeCost += w * g[h] * pr[h]; sumCharge += w * g[h]; }
    }
    gen.push(g); charge.push(ch);
  }
  const genFrac = sumAvail > 0 ? sumGen / sumAvail : 0;
  const capture = sumGen > 0 ? sumRev / sumGen : mp.avg;
  let chargeUsd = 0;
  if (mode === 'almacenamiento') chargeUsd = sumGen > 0 ? sumChargeCost / sumGen : 0;
  if (mode === 'hidrogeno') chargeUsd = sumCharge > 0 ? sumChargeCost / sumCharge : mp.avg;
  const out: PlanDetail = {
    ym: yearMonthIndex(mp.year, mp.month), key: '', genFrac: Math.max(0, Math.min(mode === 'generacion' ? 1.6 : 1, genFrac)),
    captureUsdMwh: capture, avgSpotUsdMwh: mp.avg, chargeUsdMwh: chargeUsd, curtailedFrac: sumAvail > 0 ? sumCurt / sumAvail : 0,
    servicesFrac: svcFrac, servicesUsdMwH: svcFrac > 0 ? svcPrice : 0,
    gen: detail ? gen : [], charge: detail ? charge : [], price: detail ? mp.prices : [],
  };
  return out;
}

/** Plan del mes de un proyecto con la información de hoy (precios del mes en curso o previsión). */
export function projectPlan(state: GameState, ctx: SimContext, p: Project, year: number, month: number, o: Omit<PlanInputs, 'tech' | 'countryCode' | 'policy'>, detail = false): PlanDetail | undefined {
  const mp = monthPrices(state, ctx, p.countryCode, year, month);
  if (!mp) return undefined;
  return planOnPrices(state, ctx, mp, { ...o, tech: ctx.data.technologies[p.techId], countryCode: p.countryCode, policy: p.dispatch ?? {} }, detail);
}
