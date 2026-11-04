import type { RngState } from './rng';
import { seedStream } from './rng';
import { parseIsoDate, toEpochDay } from './calendar';
import type { SimConfig } from './config';
import type { Project } from '../project/types';
import { newBusinessState, newMarketState, type BusinessState, type CompetitorState, type MarketState } from '../business/types';

/**
 * v2 (Fase 2): proyectos y finanzas de la empresa.
 * v3 (Fase 3): licitaciones, contratos, I+D, cadena de suministro y competidores IA.
 * v4 (Fase 4): presencia por país, tipos de cambio, combustibles y datos extra de sitio.
 * Las partidas anteriores se migran (ver save.ts).
 */
export const SAVE_VERSION = 4;

/** Movimiento contable de caja de la empresa. */
export interface LedgerEntry { day: number; concept: string; amountUsd: number }

export interface Company {
  name: string;
  homeCountry: string;
  cashUsd: number;
  monthlyFixedCostUsd: number;
  ledger: LedgerEntry[]; // últimos 24 meses
}

/** Estado de resultados + flujo de caja de un mes (USD). Signo: ingresos +, gastos −. */
export interface MonthlyStatement {
  year: number;
  month: number;
  /** Por concepto (ver finance/company.ts: CATEGORIES). */
  lines: Record<string, number>;
  revenueUsd: number;
  ebitdaUsd: number;
  netIncomeUsd: number;
  cashFlow: { operating: number; investing: number; financing: number; net: number };
  cashEndUsd: number;
  debtEndUsd: number;
}

export interface FinanceState {
  /** Acumulado del mes en curso por concepto. */
  month: Record<string, number>;
  /** Últimos 120 meses. */
  statements: MonthlyStatement[];
  taxLossCarryforwardUsd: number;
  taxCreditUsd: number;
  emergencyDebtUsd: number;
  negativeCashMonths: number;
  bankrupt: boolean;
  bankruptTick?: number;
}

/** Estado completo de la partida: objeto plano y serializable. */
export interface GameState {
  saveVersion: number;
  dataVersion: number;
  seed: number;
  /** Días transcurridos desde el inicio (tick actual). */
  tick: number;
  /** Día de época (1970) correspondiente a tick = 0. */
  startEpochDay: number;
  company: Company;
  /** Un flujo de RNG por subsistema, para que añadir sistemas no cambie los demás. */
  rng: Record<string, RngState>;
  /** País y celda enfocados en la UI (parte de la partida para que el guardado la restaure). */
  focus: { countryCode: string };
  projects: Project[];
  nextProjectId: number;
  finance: FinanceState;
  /** Fase 3: licitaciones, contratos, I+D, reputación y relación con proveedores del jugador. */
  business: BusinessState;
  /** Fase 3: mundo compartido (oportunidades, índices de precios y colas de proveedores). */
  market: MarketState;
  /** Fase 3: competidores IA (cada uno con su empresa, proyectos y negocio). */
  competitors: CompetitorState[];
  /**
   * Solo en vistas de actor (ver business/actor.ts): id del competidor IA cuyo estado se está procesando.
   * Nunca se guarda: en la partida es siempre `undefined` (= jugador).
   */
  actorId?: string;
}

/** `supply`, `tenders` y `business` se agregaron en la Fase 3 (la migración 2→3 los siembra). */
export const RNG_STREAMS = ['world', 'market', 'projects', 'events', 'ai', 'supply', 'tenders', 'business', 'fx', 'fuels'] as const;

export function newFinanceState(): FinanceState {
  return { month: {}, statements: [], taxLossCarryforwardUsd: 0, taxCreditUsd: 0, emergencyDebtUsd: 0, negativeCashMonths: 0, bankrupt: false };
}

/**
 * Partida nueva. Los competidores IA, los índices de precios y las oportunidades se inicializan en el
 * primer `step` con datos (`ctx`), porque dependen de los YAML. `competitors: false` los desactiva.
 */
export function createNewGame(config: SimConfig, opts: { seed: number; companyName: string; competitors?: boolean }): GameState {
  const rng: Record<string, RngState> = {};
  for (const s of RNG_STREAMS) rng[s] = seedStream(opts.seed, s);
  return {
    saveVersion: SAVE_VERSION,
    dataVersion: config.dataVersion,
    seed: opts.seed >>> 0,
    tick: 0,
    startEpochDay: toEpochDay(parseIsoDate(config.startDate)),
    company: {
      name: opts.companyName.trim() || 'Mi empresa',
      homeCountry: config.startCountry,
      cashUsd: config.company.cashUsd,
      monthlyFixedCostUsd: config.company.monthlyFixedCostUsd,
      ledger: [{ day: 0, concept: 'Capital inicial', amountUsd: config.company.cashUsd }],
    },
    rng,
    focus: { countryCode: config.startCountry },
    projects: [],
    nextProjectId: 1,
    finance: newFinanceState(),
    business: newBusinessState(),
    market: newMarketState(opts.competitors ?? true),
    competitors: [],
  };
}
