import type { SimContext } from '../core/context';
import type { GameState } from '../core/state';
import { fromEpochDay } from '../core/calendar';
import type { CountrySimDef, LenderDef, TechnologyDef } from '../data/types';
import { capacityFactor } from '../tech/capacityFactor';
import { annualFixedCosts, currentCapex, capexBreakdown, expectedAvailability, expectedRepairCostUsd, type CapexBreakdown } from '../tech/costs';
import { researchEffects } from '../business/research';
import { captureFactor, spotPrice } from '../market/spot';
import { costOfEquity, npv, wacc } from '../finance/math';
import { runProjectModel, sizeDebt, type ProjectModelInput, type ProjectModelResult } from '../finance/projectModel';
import { p90 } from '../world/site';
import type { Project, ProjectStage } from './types';

export function currentYear(state: GameState): number {
  return fromEpochDay(state.startEpochDay + state.tick).year;
}
export function startYear(state: GameState): number {
  return fromEpochDay(state.startEpochDay).year;
}

export function stagePremium(c: CountrySimDef, stage: ProjectStage): number {
  return c.finanzas.prima_etapa[stage] ?? 0;
}

/** Costo del equity y WACC del proyecto en su etapa actual. */
export function discountRates(c: CountrySimDef, techId: string, stage: ProjectStage, debtFraction: number, costOfDebt: number) {
  const base = {
    riskFree: c.finanzas.tasa_libre_riesgo.base, countryPremium: c.prima_riesgo_pais.base,
    equityPremium: c.finanzas.prima_mercado_acciones.base, beta: c.finanzas.beta_renovables,
    stagePremium: stagePremium(c, stage), techPremium: c.finanzas.prima_tecnologia[techId] ?? 0,
  };
  const ke = costOfEquity(base);
  const w = wacc({ ...base, costOfDebt, taxRate: c.impuestos.renta.base, debtFraction });
  return { costOfEquity: ke, wacc: w };
}

export function lenderRate(c: CountrySimDef, l: LenderDef): number {
  return c.finanzas.tasa_libre_riesgo.base + l.spread.base;
}

/** Precio spot medio capturado por la tecnología en el año dado. */
export function capturedSpot(c: CountrySimDef, tech: TechnologyDef, startY: number, year: number): number {
  let s = 0;
  for (let m = 1; m <= 12; m++) s += spotPrice(c, startY, year, m);
  return (s / 12) * captureFactor(c, tech.recurso);
}

export interface EconomicsOptions {
  /** Recurso a usar (por defecto la estimación P50 del jugador). */
  resource?: number;
  /** CAPEX de construcción a usar (por defecto el presupuesto actual). */
  capexUsd?: number;
  /** Precio de PPA a suponer si no hay uno firmado. */
  ppaPriceUsdMwh?: number;
  /** Supone venta al spot aunque haya PPA (análisis de sensibilidad). */
  merchant?: boolean;
  lenderId?: string;
  debtFraction?: number;
  /** Etapa para la prima de riesgo de la tasa (por defecto la actual). El Monte Carlo usa 'operacion': el riesgo ya lo simula. */
  stage?: ProjectStage;
}

export interface Economics {
  fc: number;
  fcP50: number;
  fcP90: number;
  energyP50MwhYear: number;
  energyP90MwhYear: number;
  availability: number;
  capexUsd: number;
  investmentUsd: number;
  debtUsd: number;
  debtRate: number;
  costOfEquity: number;
  wacc: number;
  model: ProjectModelResult;
  npvEquityUsd: number;
  npvProjectUsd: number;
  lcoeUsdMwh: number;
  priceAssumption: 'ppa' | 'spot';
  priceUsdMwh: number;
}

/** CAPEX del proyecto a precios actuales (con `state`: índices, proveedores, relación e I+D del actor). */
export function projectCapex(ctx: SimContext, p: Project, state?: GameState): CapexBreakdown {
  const i = { techId: p.techId, mw: p.mw, countryCode: p.countryCode, capexFactor: p.capexFactor, ...p.suppliers };
  return state ? currentCapex(state, ctx, i) : capexBreakdown(ctx, i);
}

/** CAPEX de construcción actual del proyecto (presupuesto + sobrecostos si ya se construye). */
export function constructionBudget(ctx: SimContext, p: Project, state?: GameState): number {
  if (p.construction) return p.construction.budgetUsd + p.construction.overrunUsd;
  if (p.financing?.status === 'cerrado') return p.financing.budgetUsd;
  return projectCapex(ctx, p, state).totalUsd;
}

export function fcFromResource(ctx: SimContext, p: Pick<Project, 'techId' | 'site'>, resource: number): number {
  return capacityFactor(ctx.data.technologies[p.techId], resource, p.site.temperatureC);
}

/**
 * Economía estimada del proyecto con la información del jugador (P50 de su estimación).
 * Nunca usa el recurso real oculto salvo que se pase explícitamente en `opts.resource`.
 */
export function projectEconomics(state: GameState, ctx: SimContext, p: Project, opts: EconomicsOptions = {}): Economics {
  const tech = ctx.data.technologies[p.techId];
  const c = ctx.data.countries[p.countryCode];
  const resP50 = opts.resource ?? p.estimate.value;
  const resP90 = opts.resource ?? p90(p.estimate.value, p.estimate.sigma);
  // I+D: el FC de una planta operando ya trae su bono; uno nuevo usa lo investigado hoy.
  const fx = researchEffects(state, ctx);
  const fcBonus = p.operation ? p.operation.fcBonus ?? 1 : fx.fcMult(p.techId);
  const fcP50 = fcFromResource(ctx, p, resP50) * fcBonus;
  const fcP90 = fcFromResource(ctx, p, resP90) * fcBonus;
  const policy = p.operation?.maintenance ?? 'preventivo';
  const avail = expectedAvailability(tech, p.mw, policy, p.operation?.failureMultiplier ?? 1);
  const energyP50 = p.mw * 8760 * fcP50 * avail;
  const energyP90 = p.mw * 8760 * fcP90 * avail;
  const capex = opts.capexUsd ?? constructionBudget(ctx, p, state);
  const fixed = annualFixedCosts(tech, c, p.mw, capex, policy, fx.omMult(p.techId));
  const repairs = expectedRepairCostUsd(tech, p.mw, policy, p.operation?.failureMultiplier ?? 1);
  const yearNow = currentYear(state), y0 = startYear(state);
  const spot = capturedSpot(c, tech, y0, yearNow);

  let ppa: ProjectModelInput['ppa'];
  if (!opts.merchant) {
    if (p.ppa?.status === 'firmado') ppa = { priceUsdMwh: p.ppa.priceUsdMwh, years: p.ppa.years, indexation: p.ppa.indexation };
    else if (opts.ppaPriceUsdMwh) ppa = { priceUsdMwh: opts.ppaPriceUsdMwh, years: 15, indexation: 0.01 };
    else if (p.ppa?.status === 'en_proceso') {
      const ch = c.ppa.canales.find((x) => x.id === p.ppa!.channelId);
      if (ch) ppa = { priceUsdMwh: ch.precio_usd_mwh.base, years: ch.plazo_anos, indexation: ch.indexacion_anual };
    }
  }

  const lender = c.finanzas.prestamistas.find((l) => l.id === (opts.lenderId ?? p.financing?.lenderId)) ?? c.finanzas.prestamistas.find((l) => l.tipo === 'comercial') ?? c.finanzas.prestamistas[0];
  const rate = p.financing?.status === 'cerrado' ? p.financing.rate : lenderRate(c, lender);
  const tenor = p.financing?.status === 'cerrado' ? p.financing.tenorYears : lender.plazo_anos;
  const constructionYears = tech.construccion_meses.base / 12;

  const inc = c.incentivos[p.techId];
  const base: ProjectModelInput = {
    energyMwhYear1: energyP50,
    degradation: tech.degradacion_anual.base,
    lifeYears: tech.vida_util_anos.base,
    capexUsd: capex,
    fixedCostUsdYear: fixed.totalUsd + repairs,
    varCostUsdMwh: tech.om_variable_usd_mwh.base,
    inflation: c.inflacion_anual.base,
    ppa,
    spotPriceUsdMwh: spot,
    taxRate: c.impuestos.renta.base,
    depreciationYears: c.impuestos.depreciacion_anos.base,
    taxCreditUsd: (inc?.credito_fiscal_frac_inversion.base ?? 0) * capex,
    taxCreditMaxFrac: inc?.credito_max_frac_impuesto ?? 0,
    decommissionUsd: tech.costo_desmantelamiento_frac_capex.base * capex,
  };

  // Deuda: la real si hay cierre; si no, dimensionada por el banco con P90 (y precio con recorte si es merchant)
  let debt = 0;
  if (p.financing?.status === 'cerrado') debt = p.debt?.principalUsd ?? p.financing.debtUsd;
  else {
    const bankCase = runProjectModel({ ...base, energyMwhYear1: energyP90, spotPriceUsdMwh: spot * (ppa ? 1 : 0.8) });
    const cfads = bankCase.rows.map((r) => r.ebitdaUsd - r.taxUnleveredUsd);
    debt = sizeDebt({ cfads, dscr: ppa ? lender.dscr_ppa : lender.dscr_merchant, rate, tenorYears: tenor, maxLeverage: lender.apalancamiento_max,
      requestedFraction: opts.debtFraction ?? lender.apalancamiento_max, budgetUsd: capex }).debtUsd;
  }
  const fees = p.financing?.status === 'cerrado' ? 0 : debt * lender.comision_estructuracion + lender.costo_asesores_usd.base;
  const idc = p.construction ? p.construction.idcUsd : rate * debt * constructionYears * 0.5;
  const investment = capex + fees + idc;
  const model = runProjectModel({ ...base, capexUsd: investment, debt: debt > 0 ? { amountUsd: debt, rate, tenorYears: tenor } : undefined });
  const dr = discountRates(c, p.techId, opts.stage ?? p.stage, debt / Math.max(1, investment), rate);
  return {
    fc: fcP50, fcP50, fcP90, energyP50MwhYear: energyP50, energyP90MwhYear: energyP90, availability: avail,
    capexUsd: capex, investmentUsd: investment, debtUsd: debt, debtRate: rate,
    costOfEquity: dr.costOfEquity, wacc: dr.wacc, model,
    npvEquityUsd: npv(dr.costOfEquity, model.equityFlows),
    npvProjectUsd: npv(dr.wacc, model.projectFlows),
    lcoeUsdMwh: model.lcoeUsdMwh,
    priceAssumption: ppa ? 'ppa' : 'spot',
    priceUsdMwh: ppa ? ppa.priceUsdMwh : spot,
  };
}
