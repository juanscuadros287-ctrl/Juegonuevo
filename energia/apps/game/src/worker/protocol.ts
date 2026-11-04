import type { Command, CompanyFinancials, GameState, ProjectDetail, ProjectSummary, SimEvent, SitePreview, ViabilityResult } from '@voltaje/sim';

/** Vistas calculadas en el worker con los selectores del motor (necesitan datos + grilla). */
export interface Views {
  projects: ProjectSummary[];
  finance: CompanyFinancials;
  /** Detalle del proyecto enfocado en la UI (null si no hay ventana abierta). */
  detail: ProjectDetail | null;
}

/** Estimación económica de un sitio antes de crear el proyecto (proyecto simulado sobre una copia del estado). */
export interface SiteEstimate {
  preview: SitePreview;
  irrEquity: number | null;
  npvEquityUsd: number | null;
  lcoeUsdMwh: number | null;
  devCostUpcomingUsd: number | null;
  successProbability: number | null;
  priceUsdMwh: number | null;
}

/** Efecto estimado de una estructura de financiamiento. */
export interface FinancePreview {
  debtUsd: number;
  equityUsd: number;
  irrEquity: number | null;
  npvEquityUsd: number;
  minDscr: number | null;
  ratePct: number;
  error?: string;
}

export type ToWorker =
  | { t: 'init'; gridUrl: string; binUrl: string }
  | { t: 'new'; seed: number; companyName: string }
  | { t: 'load'; text: string; reqId: number }
  | { t: 'speed'; daysPerSecond: number } // 0 = pausa
  | { t: 'cmd'; cmd: Command }
  | { t: 'save'; reqId: number }
  | { t: 'focus'; projectId: string | null }
  | { t: 'preview'; reqId: number; techId: string; mw: number; lat: number; lon: number }
  | { t: 'viability'; reqId: number; projectId: string; runs: number }
  | { t: 'finPreview'; reqId: number; projectId: string; lenderId: string; debtFraction: number }
  | { t: 'quit' };

export type FromWorker =
  | { t: 'ready'; error?: string }
  | { t: 'snapshot'; state: GameState; views: Views }
  | { t: 'events'; events: SimEvent[] }
  | { t: 'saved'; reqId: number; text: string }
  | { t: 'loaded'; reqId: number; error?: string }
  | { t: 'preview'; reqId: number; estimate: SiteEstimate }
  | { t: 'viability'; reqId: number; result?: ViabilityResult; error?: string; ms: number }
  | { t: 'finPreview'; reqId: number; preview: FinancePreview };
