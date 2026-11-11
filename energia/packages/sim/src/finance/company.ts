import type { GameState, MonthlyStatement } from '../core/state';
import type { SimContext } from '../core/context';
import type { SimEvent } from '../core/events';
import { TERMINAL_STAGES, type Project } from '../project/types';

/**
 * Contabilidad de la empresa (consolidada con sus proyectos).
 *
 * Conceptos (signo: + ingreso/entrada, − gasto/salida):
 *  - Resultado y caja operativa: ingresos, om, terreno, seguro, gastos_fijos, desarrollo_gasto,
 *    reparaciones, multas, intereses, impuestos, prima_desarrollo
 *  - Solo resultado (no caja): depreciacion, castigos, resultado_venta
 *  - Caja de inversión: inversion_desarrollo, inversion_construccion, venta_activos
 *  - Caja de financiamiento: deuda_desembolso, deuda_amortizacion, socio_aporte, socio_distribucion,
 *    credito_emergencia
 */
export const CATEGORIES = {
  ingresos: { pnl: true, cash: 'operating', label: 'Venta de energía' },
  prima_desarrollo: { pnl: true, cash: 'operating', label: 'Prima de desarrollo (socio)' },
  om: { pnl: true, cash: 'operating', label: 'Operación y mantenimiento' },
  terreno: { pnl: true, cash: 'operating', label: 'Arriendo de terrenos' },
  seguro: { pnl: true, cash: 'operating', label: 'Seguros' },
  gastos_fijos: { pnl: true, cash: 'operating', label: 'Gastos fijos (personal y oficina)' },
  desarrollo_gasto: { pnl: true, cash: 'operating', label: 'Gastos de desarrollo' },
  reparaciones: { pnl: true, cash: 'operating', label: 'Reparaciones' },
  multas: { pnl: true, cash: 'operating', label: 'Multas contractuales' },
  intereses: { pnl: true, cash: 'operating', label: 'Intereses' },
  impuestos: { pnl: true, cash: 'operating', label: 'Impuesto sobre la renta' },
  depreciacion: { pnl: true, cash: null, label: 'Depreciación' },
  castigos: { pnl: true, cash: null, label: 'Castigo de proyectos' },
  resultado_venta: { pnl: true, cash: null, label: 'Resultado por venta de proyectos' },
  inversion_desarrollo: { pnl: false, cash: 'investing', label: 'Estudios y permisos (capitalizados)' },
  inversion_construccion: { pnl: false, cash: 'investing', label: 'Construcción' },
  venta_activos: { pnl: false, cash: 'investing', label: 'Venta de proyectos' },
  deuda_desembolso: { pnl: false, cash: 'financing', label: 'Desembolsos de deuda' },
  deuda_amortizacion: { pnl: false, cash: 'financing', label: 'Amortización de deuda' },
  socio_aporte: { pnl: false, cash: 'financing', label: 'Aportes de socios' },
  socio_distribucion: { pnl: false, cash: 'financing', label: 'Dividendos a socios' },
  credito_emergencia: { pnl: false, cash: 'financing', label: 'Crédito de emergencia' },
  // Fase 3
  ingresos_potencia: { pnl: true, cash: 'operating', label: 'Pagos por potencia firme' },
  ingresos_epc: { pnl: true, cash: 'operating', label: 'Ingresos EPC (obras para terceros)' },
  costos_epc: { pnl: true, cash: 'operating', label: 'Costos EPC (obras para terceros)' },
  licitaciones: { pnl: true, cash: 'operating', label: 'Preparación de ofertas' },
  garantias_comision: { pnl: true, cash: 'operating', label: 'Comisiones de garantías bancarias' },
  garantias_ejecutadas: { pnl: true, cash: 'operating', label: 'Garantías ejecutadas' },
  investigacion: { pnl: true, cash: 'operating', label: 'Investigación y desarrollo' },
  garantias: { pnl: false, cash: 'investing', label: 'Caja inmovilizada en garantías (neto)' },
  // Fase 4
  combustible: { pnl: true, cash: 'operating', label: 'Combustibles y energía comprada' },
  carbono: { pnl: true, cash: 'operating', label: 'Impuesto al carbono' },
  presencia: { pnl: true, cash: 'operating', label: 'Presencia en otros países (constitución y representantes)' },
  // Fase 5
  ingresos_capacidad: { pnl: true, cash: 'operating', label: 'Pagos por capacidad (mercado de potencia)' },
  ingresos_servicios: { pnl: true, cash: 'operating', label: 'Servicios complementarios' },
  compras_energia: { pnl: true, cash: 'operating', label: 'Compras de energía al spot (contratos)' },
  indemnizaciones: { pnl: true, cash: 'operating', label: 'Indemnizaciones de seguros' },
} as const;
export type Category = keyof typeof CATEGORIES;

const EBITDA_EXCLUDE: Category[] = ['intereses', 'impuestos', 'depreciacion', 'castigos', 'resultado_venta', 'garantias_ejecutadas'];
const LEDGER_KEEP_DAYS = 730;
const STATEMENTS_KEEP = 120;

/** Movimiento de caja (con su concepto contable). */
export function postCash(state: GameState, cat: Category, amountUsd: number, concept: string) {
  if (amountUsd === 0 || !Number.isFinite(amountUsd)) return;
  state.company.cashUsd += amountUsd;
  state.finance.month[cat] = (state.finance.month[cat] ?? 0) + amountUsd;
  state.company.ledger.push({ day: state.tick, concept, amountUsd });
}

/** Movimiento solo de resultados (sin caja): depreciación, castigos, resultado de ventas. */
export function accrue(state: GameState, cat: Category, amountUsd: number) {
  if (amountUsd === 0 || !Number.isFinite(amountUsd)) return;
  state.finance.month[cat] = (state.finance.month[cat] ?? 0) + amountUsd;
}

export function totalDebt(state: GameState): number {
  let d = state.finance.emergencyDebtUsd;
  for (const p of state.projects) if (!TERMINAL_STAGES.includes(p.stage)) d += p.debt?.outstandingUsd ?? 0;
  return d;
}

/** Valor contable neto de los activos en operación (para crédito de emergencia y balance). */
export function operatingAssetsNet(state: GameState): number {
  let v = 0;
  for (const p of state.projects) if (p.stage === 'operacion' && p.operation) v += p.operation.grossAssetUsd - p.operation.accumulatedDepreciationUsd;
  return v;
}

export interface BalanceSheet {
  cashUsd: number;
  /** Fase 3: caja inmovilizada en garantías bancarias (incluida en el activo total). */
  restrictedCashUsd: number;
  developmentAssetsUsd: number;
  constructionAssetsUsd: number;
  operatingAssetsUsd: number;
  totalAssetsUsd: number;
  debtUsd: number;
  partnerInterestUsd: number;
  equityUsd: number;
}

export function balanceSheet(state: GameState): BalanceSheet {
  let dev = 0, cons = 0, op = 0, partner = 0;
  for (const p of state.projects) {
    if (TERMINAL_STAGES.includes(p.stage)) continue;
    if (p.operation) op += p.operation.grossAssetUsd - p.operation.accumulatedDepreciationUsd;
    else if (p.construction) cons += p.devCostUsd + p.construction.spentUsd + p.construction.idcUsd;
    else dev += p.devCostUsd;
    if (p.financing?.status === 'cerrado') partner += p.financing.partnerShare * p.financing.equityUsd;
  }
  const debt = totalDebt(state);
  const restricted = state.business?.restrictedCashUsd ?? 0;
  const total = state.company.cashUsd + restricted + dev + cons + op;
  return {
    cashUsd: state.company.cashUsd, restrictedCashUsd: restricted, developmentAssetsUsd: dev, constructionAssetsUsd: cons, operatingAssetsUsd: op,
    totalAssetsUsd: total, debtUsd: debt, partnerInterestUsd: partner, equityUsd: total - debt - partner,
  };
}

/**
 * Cierre de mes: impuestos, crédito de emergencia, estado del mes y control de quiebra.
 * Se llama después de liquidar proyectos y gastos fijos del mes.
 */
export function closeMonth(state: GameState, ctx: SimContext, year: number, month: number, events: SimEvent[]) {
  const f = state.finance;
  const country = ctx.data.countries[state.company.homeCountry];
  const taxRate = country?.impuestos.renta.base ?? 0.25;

  // Intereses del crédito de emergencia
  if (f.emergencyDebtUsd > 0) {
    const rate = country?.finanzas.credito_emergencia.tasa ?? 0.14;
    postCash(state, 'intereses', -f.emergencyDebtUsd * rate / 12, 'Intereses crédito de emergencia');
  }

  // Impuesto sobre la renta (mensual, con arrastre de pérdidas y crédito fiscal)
  let pretax = 0;
  for (const [k, v] of Object.entries(f.month)) if (CATEGORIES[k as Category]?.pnl && k !== 'impuestos') pretax += v;
  if (pretax < 0) f.taxLossCarryforwardUsd += -pretax;
  else if (pretax > 0) {
    const used = Math.min(f.taxLossCarryforwardUsd, pretax);
    f.taxLossCarryforwardUsd -= used;
    let tax = (pretax - used) * taxRate;
    const maxCreditFrac = 0.5;
    const credit = Math.min(f.taxCreditUsd, tax * maxCreditFrac);
    f.taxCreditUsd -= credit;
    tax -= credit;
    if (tax > 0) postCash(state, 'impuestos', -tax, 'Impuesto sobre la renta');
  }

  // Barrido: si sobra caja, se paga el crédito de emergencia
  if (f.emergencyDebtUsd > 0) {
    const spare = state.company.cashUsd - 3 * state.company.monthlyFixedCostUsd;
    if (spare > 0) {
      const pay = Math.min(spare, f.emergencyDebtUsd);
      f.emergencyDebtUsd -= pay;
      postCash(state, 'credito_emergencia', -pay, 'Pago de crédito de emergencia');
    }
  }

  // Caja negativa: intento de crédito de emergencia; si no alcanza, cuenta para la quiebra
  if (state.company.cashUsd < 0) {
    const frac = country?.finanzas.credito_emergencia.frac_valor_activos ?? 0.5;
    const capacity = frac * operatingAssetsNet(state) - totalDebt(state);
    const need = -state.company.cashUsd + state.company.monthlyFixedCostUsd;
    if (capacity >= need) {
      f.emergencyDebtUsd += need;
      postCash(state, 'credito_emergencia', need, 'Crédito de emergencia');
      events.push({ type: 'emergencyCredit', amountUsd: need, text: `Se tomó un crédito de emergencia de ${Math.round(need).toLocaleString('es')} USD garantizado con las plantas.` });
      f.negativeCashMonths = 0;
    } else {
      f.negativeCashMonths += 1;
    }
  } else f.negativeCashMonths = 0;

  // Estado del mes
  const lines = { ...f.month };
  let revenue = 0, ebitda = 0, net = 0;
  const cf = { operating: 0, investing: 0, financing: 0, net: 0 };
  for (const [k, v] of Object.entries(lines)) {
    const c = CATEGORIES[k as Category];
    if (!c) continue;
    if (c.pnl) {
      net += v;
      if (!EBITDA_EXCLUDE.includes(k as Category)) ebitda += v;
      if (k === 'ingresos' || k === 'ingresos_capacidad' || k === 'ingresos_servicios') revenue += v;
    }
    if (c.cash) { cf[c.cash] += v; cf.net += v; }
  }
  const st: MonthlyStatement = {
    year, month, lines, revenueUsd: revenue, ebitdaUsd: ebitda, netIncomeUsd: net, cashFlow: cf,
    cashEndUsd: state.company.cashUsd, debtEndUsd: totalDebt(state),
  };
  f.statements.push(st);
  if (f.statements.length > STATEMENTS_KEEP) f.statements.splice(0, f.statements.length - STATEMENTS_KEEP);
  f.month = {};

  const c = state.company;
  const cutoff = state.tick - LEDGER_KEEP_DAYS;
  if (c.ledger.length && c.ledger[0].day < cutoff) c.ledger = c.ledger.filter((e) => e.day >= cutoff);

  if (c.cashUsd < 0) {
    events.push({ type: 'cashNegative', cashUsd: c.cashUsd, monthsNegative: f.negativeCashMonths });
    const limit = country?.quiebra.meses_caja_negativa ?? 3;
    if (f.negativeCashMonths >= limit) {
      f.bankrupt = true;
      f.bankruptTick = state.tick;
      events.push({ type: 'bankruptcy', cashUsd: c.cashUsd, text: `Quiebra: ${limit} meses con caja negativa y sin crédito disponible. Fin de la partida.` });
    }
  }
}

/** Proyectos activos (no terminales). */
export function activeProjects(state: GameState): Project[] {
  return state.projects.filter((p) => !TERMINAL_STAGES.includes(p.stage));
}
