import type { RngState } from './rng';
import { seedStream } from './rng';
import { parseIsoDate, toEpochDay } from './calendar';
import type { SimConfig } from './config';
import type { Project } from '../project/types';

/** v2 (Fase 2): proyectos y finanzas de la empresa. Las partidas v1 se migran (ver save.ts). */
export const SAVE_VERSION = 2;

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
}

export const RNG_STREAMS = ['world', 'market', 'projects', 'events', 'ai'] as const;

export function newFinanceState(): FinanceState {
  return { month: {}, statements: [], taxLossCarryforwardUsd: 0, taxCreditUsd: 0, emergencyDebtUsd: 0, negativeCashMonths: 0, bankrupt: false };
}

export function createNewGame(config: SimConfig, opts: { seed: number; companyName: string }): GameState {
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
  };
}
