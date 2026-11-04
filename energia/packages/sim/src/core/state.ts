import type { RngState } from './rng';
import { seedStream } from './rng';
import { parseIsoDate, toEpochDay } from './calendar';
import type { SimConfig } from './config';

export const SAVE_VERSION = 1;

/** Movimiento contable de la empresa. */
export interface LedgerEntry { day: number; concept: string; amountUsd: number }

export interface Company {
  name: string;
  homeCountry: string;
  cashUsd: number;
  monthlyFixedCostUsd: number;
  ledger: LedgerEntry[]; // últimos 24 meses
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
}

export const RNG_STREAMS = ['world', 'market', 'projects', 'events', 'ai'] as const;

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
  };
}
