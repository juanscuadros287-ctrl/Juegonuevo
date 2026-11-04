/**
 * Matemática financiera pura. Flujos anuales con flows[0] en t = 0 (o el período que se use).
 */

/** Valor actual neto. */
export function npv(rate: number, flows: readonly number[]): number {
  let v = 0;
  let df = 1;
  for (let t = 0; t < flows.length; t++) {
    v += flows[t] * df;
    df /= 1 + rate;
  }
  return v;
}

function dnpv(rate: number, flows: readonly number[]): number {
  let d = 0;
  for (let t = 1; t < flows.length; t++) d -= (t * flows[t]) / Math.pow(1 + rate, t + 1);
  return d;
}

/**
 * Tasa interna de retorno robusta: busca un intervalo con cambio de signo, bisección para acercarse
 * y Newton para pulir. Devuelve null si no hay solución en (-99 %, 1000 %).
 */
export function irr(flows: readonly number[], guess = 0.08): number | null {
  if (flows.length < 2) return null;
  const hasPos = flows.some((f) => f > 0);
  const hasNeg = flows.some((f) => f < 0);
  if (!hasPos || !hasNeg) return null;
  // rejilla de búsqueda de cambio de signo, empezando cerca del valor esperado
  const grid = [-0.99, -0.9, -0.7, -0.5, -0.3, -0.2, -0.1, -0.05, 0, 0.02, 0.04, 0.06, 0.08, 0.1, 0.12, 0.15, 0.2, 0.3, 0.5, 0.75, 1, 2, 5, 10];
  let lo = NaN, hi = NaN;
  let best = Infinity;
  // preferimos el intervalo más cercano al valor guía
  for (let i = 0; i < grid.length - 1; i++) {
    const a = npv(grid[i], flows), b = npv(grid[i + 1], flows);
    if (a === 0) return grid[i];
    if (a * b < 0) {
      const d = Math.abs((grid[i] + grid[i + 1]) / 2 - guess);
      if (d < best) { best = d; lo = grid[i]; hi = grid[i + 1]; }
    }
  }
  if (Number.isNaN(lo)) return null;
  let flo = npv(lo, flows);
  for (let i = 0; i < 60 && hi - lo > 1e-7; i++) {
    const mid = (lo + hi) / 2;
    const fm = npv(mid, flows);
    if (fm === 0) return mid;
    if (fm * flo < 0) hi = mid; else { lo = mid; flo = fm; }
  }
  let r = (lo + hi) / 2;
  for (let i = 0; i < 8; i++) {
    const f = npv(r, flows), d = dnpv(r, flows);
    if (!Number.isFinite(d) || d === 0) break;
    const next = r - f / d;
    if (!Number.isFinite(next) || next <= -0.999) break;
    if (Math.abs(next - r) < 1e-12) { r = next; break; }
    r = next;
  }
  return Math.abs(npv(r, flows)) <= 1e-6 * Math.max(1, Math.abs(flows[0])) ? r : (lo + hi) / 2;
}

/** Cuota constante (sistema francés). */
export function annuityPayment(principal: number, rate: number, periods: number): number {
  if (periods <= 0) return principal;
  if (rate === 0) return principal / periods;
  return (principal * rate) / (1 - Math.pow(1 + rate, -periods));
}

export interface AmortRow { period: number; payment: number; interest: number; principal: number; balance: number }

/** Tabla de amortización francesa. */
export function amortizationSchedule(principal: number, rate: number, periods: number): AmortRow[] {
  const pay = annuityPayment(principal, rate, periods);
  const rows: AmortRow[] = [];
  let bal = principal;
  for (let p = 1; p <= periods; p++) {
    const interest = bal * rate;
    const princ = p === periods ? bal : pay - interest;
    bal = Math.max(0, bal - princ);
    rows.push({ period: p, payment: interest + princ, interest, principal: princ, balance: bal });
  }
  return rows;
}

/** Factor de recuperación de capital. */
export function crf(rate: number, years: number): number {
  return annuityPayment(1, rate, years);
}

export interface LcoeInput {
  capexUsd: number;
  /** Costos fijos anuales (O&M fijo, seguro, terreno). */
  fixedCostUsdYear: number;
  varCostUsdMwh: number;
  energyMwhYear1: number;
  degradation: number;
  years: number;
  rate: number;
  /** Años de construcción: el CAPEX se reparte uniforme antes del año 1. */
  constructionYears?: number;
}

/** LCOE (USD/MWh) = VP(costos) / VP(energía), real, sin impuestos. */
export function lcoe(i: LcoeInput): number {
  let pvCost = i.capexUsd, pvEnergy = 0;
  for (let t = 1; t <= i.years; t++) {
    const e = i.energyMwhYear1 * Math.pow(1 - i.degradation, t - 1);
    const df = Math.pow(1 + i.rate, -t);
    pvCost += (i.fixedCostUsdYear + i.varCostUsdMwh * e) * df;
    pvEnergy += e * df;
  }
  return pvCost / pvEnergy;
}

export interface WaccInput {
  riskFree: number;
  countryPremium: number;
  equityPremium: number;
  beta: number;
  stagePremium: number;
  techPremium: number;
  costOfDebt: number;
  taxRate: number;
  debtFraction: number;
}

/** Costo del equity (CAPM + primas) y WACC. */
export function costOfEquity(i: Omit<WaccInput, 'costOfDebt' | 'taxRate' | 'debtFraction'>): number {
  return i.riskFree + i.beta * i.equityPremium + i.countryPremium + i.stagePremium + i.techPremium;
}

export function wacc(i: WaccInput): number {
  const ke = costOfEquity(i);
  return (1 - i.debtFraction) * ke + i.debtFraction * i.costOfDebt * (1 - i.taxRate);
}

/**
 * Deuda máxima que soporta un flujo (CFADS) con cobertura `dscr`: VP(CFADS/DSCR) durante el plazo.
 */
export function debtCapacityByDscr(cfads: readonly number[], dscr: number, rate: number, tenor: number): number {
  let pv = 0;
  for (let t = 0; t < Math.min(tenor, cfads.length); t++) pv += Math.max(0, cfads[t]) / dscr / Math.pow(1 + rate, t + 1);
  return pv;
}

/**
 * Deuda máxima con cuota constante (francés): la cuota no puede superar el menor CFADS/DSCR del plazo.
 */
export function debtCapacityFrench(cfads: readonly number[], dscr: number, rate: number, tenor: number): number {
  const n = Math.min(tenor, cfads.length);
  if (n <= 0) return 0;
  let minCf = Infinity;
  for (let t = 0; t < n; t++) minCf = Math.min(minCf, cfads[t]);
  if (minCf <= 0) return 0;
  const pay = minCf / dscr;
  return rate === 0 ? pay * n : (pay * (1 - Math.pow(1 + rate, -n))) / rate;
}

/** Percentil de una muestra (interpolación lineal). */
export function percentile(values: readonly number[], p: number): number {
  if (!values.length) return NaN;
  const s = [...values].sort((a, b) => a - b);
  const idx = (s.length - 1) * p;
  const lo = Math.floor(idx), hi = Math.ceil(idx);
  return s[lo] + (s[hi] - s[lo]) * (idx - lo);
}
