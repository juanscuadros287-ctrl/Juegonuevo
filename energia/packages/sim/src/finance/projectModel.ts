import { annuityPayment, debtCapacityFrench, irr, lcoe, npv } from './math';

/**
 * Modelo anual de flujo de caja de un proyecto (t = 0 inversión, t = 1…vida operación).
 * Impuestos con depreciación lineal y arrastre de pérdidas; deuda con cuota francesa anual.
 */
export interface ProjectModelInput {
  energyMwhYear1: number;
  degradation: number;
  lifeYears: number;
  capexUsd: number;
  /** Costos fijos del año 1 (O&M, seguro, terreno, reparaciones esperadas); crecen con la inflación. */
  fixedCostUsdYear: number;
  varCostUsdMwh: number;
  inflation: number;
  ppa?: { priceUsdMwh: number; years: number; indexation: number };
  /** Precio spot capturado del año 1; crece con la inflación. */
  spotPriceUsdMwh: number;
  taxRate: number;
  depreciationYears: number;
  taxCreditUsd: number;
  taxCreditMaxFrac: number;
  debt?: { amountUsd: number; rate: number; tenorYears: number };
  decommissionUsd: number;
  /** Tasa para el LCOE (por defecto 7 %). */
  lcoeRate?: number;
}

export interface YearRow {
  year: number;
  energyMwh: number;
  priceUsdMwh: number;
  revenueUsd: number;
  opexUsd: number;
  ebitdaUsd: number;
  depreciationUsd: number;
  interestUsd: number;
  principalUsd: number;
  taxUnleveredUsd: number;
  taxLeveredUsd: number;
  cfadsUsd: number;
  dscr: number | null;
}

export interface ProjectModelResult {
  rows: YearRow[];
  projectFlows: number[];
  equityFlows: number[];
  irrProject: number | null;
  irrEquity: number | null;
  minDscr: number | null;
  avgDscr: number | null;
  lcoeUsdMwh: number;
}

function taxes(ebt: number[], rate: number, credit: number, maxFrac: number): number[] {
  let carry = 0, cr = credit;
  return ebt.map((e) => {
    if (e <= 0) { carry += -e; return 0; }
    const used = Math.min(carry, e);
    carry -= used;
    let tax = (e - used) * rate;
    const c = Math.min(cr, tax * maxFrac);
    cr -= c;
    tax -= c;
    return tax;
  });
}

export function priceForYear(i: ProjectModelInput, t: number): number {
  if (i.ppa && t <= i.ppa.years) return i.ppa.priceUsdMwh * Math.pow(1 + i.ppa.indexation, t - 1);
  return i.spotPriceUsdMwh * Math.pow(1 + i.inflation, t - 1);
}

export function runProjectModel(i: ProjectModelInput): ProjectModelResult {
  const n = Math.max(1, Math.round(i.lifeYears));
  const rows: YearRow[] = [];
  const debtAmt = i.debt?.amountUsd ?? 0;
  const pay = i.debt && debtAmt > 0 ? annuityPayment(debtAmt, i.debt.rate, i.debt.tenorYears) : 0;
  let bal = debtAmt;
  const ebtU: number[] = [], ebtL: number[] = [];
  for (let t = 1; t <= n; t++) {
    const energy = i.energyMwhYear1 * Math.pow(1 - i.degradation, t - 1);
    const price = priceForYear(i, t);
    const revenue = energy * price;
    const opex = i.fixedCostUsdYear * Math.pow(1 + i.inflation, t - 1) + i.varCostUsdMwh * energy + (t === n ? i.decommissionUsd : 0);
    const ebitda = revenue - opex;
    const dep = t <= i.depreciationYears ? i.capexUsd / i.depreciationYears : 0;
    let interest = 0, principal = 0;
    if (bal > 0 && i.debt && t <= i.debt.tenorYears) {
      interest = bal * i.debt.rate;
      principal = t === i.debt.tenorYears ? bal : Math.min(bal, pay - interest);
      bal -= principal;
    }
    ebtU.push(ebitda - dep);
    ebtL.push(ebitda - dep - interest);
    rows.push({ year: t, energyMwh: energy, priceUsdMwh: price, revenueUsd: revenue, opexUsd: opex, ebitdaUsd: ebitda, depreciationUsd: dep,
      interestUsd: interest, principalUsd: principal, taxUnleveredUsd: 0, taxLeveredUsd: 0, cfadsUsd: 0, dscr: null });
  }
  const tu = taxes(ebtU, i.taxRate, i.taxCreditUsd, i.taxCreditMaxFrac);
  const tl = taxes(ebtL, i.taxRate, i.taxCreditUsd, i.taxCreditMaxFrac);
  const projectFlows = [-i.capexUsd];
  const equityFlows = [-(i.capexUsd - debtAmt)];
  const dscrs: number[] = [];
  rows.forEach((r, k) => {
    r.taxUnleveredUsd = tu[k];
    r.taxLeveredUsd = tl[k];
    r.cfadsUsd = r.ebitdaUsd - tl[k];
    const ds = r.interestUsd + r.principalUsd;
    r.dscr = ds > 0 ? r.cfadsUsd / ds : null;
    if (r.dscr !== null) dscrs.push(r.dscr);
    projectFlows.push(r.ebitdaUsd - tu[k]);
    equityFlows.push(r.cfadsUsd - ds);
  });
  const lc = lcoe({
    capexUsd: i.capexUsd, fixedCostUsdYear: i.fixedCostUsdYear, varCostUsdMwh: i.varCostUsdMwh,
    energyMwhYear1: i.energyMwhYear1, degradation: i.degradation, years: n, rate: i.lcoeRate ?? 0.07,
  });
  return {
    rows, projectFlows, equityFlows,
    irrProject: irr(projectFlows),
    irrEquity: debtAmt >= i.capexUsd ? null : irr(equityFlows, 0.12),
    minDscr: dscrs.length ? Math.min(...dscrs) : null,
    avgDscr: dscrs.length ? dscrs.reduce((a, b) => a + b, 0) / dscrs.length : null,
    lcoeUsdMwh: lc,
  };
}

export function modelNpv(flows: number[], rate: number): number {
  return npv(rate, flows);
}

export interface DebtSizingInput {
  /** CFADS anuales (antes de servicio de deuda, después de impuestos) en el caso del banco (P90). */
  cfads: number[];
  dscr: number;
  rate: number;
  tenorYears: number;
  maxLeverage: number;
  requestedFraction: number;
  budgetUsd: number;
}

/** Deuda = mín(apalancamiento máximo, fracción pedida, capacidad por DSCR con cuota francesa). */
export function sizeDebt(i: DebtSizingInput): { debtUsd: number; limitedBy: 'apalancamiento' | 'pedido' | 'dscr' } {
  const byLev = i.maxLeverage * i.budgetUsd;
  const byReq = i.requestedFraction * i.budgetUsd;
  const byDscr = debtCapacityFrench(i.cfads, i.dscr, i.rate, i.tenorYears);
  const debt = Math.max(0, Math.min(byLev, byReq, byDscr));
  const limitedBy = debt === byDscr ? 'dscr' : debt === byReq ? 'pedido' : 'apalancamiento';
  return { debtUsd: debt, limitedBy };
}
