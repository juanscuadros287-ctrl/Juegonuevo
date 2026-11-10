import type {
  BidQuoteView, BusinessSummary, Command, CompanyFinancials, CompetitorsOverview, ContractView, FinancingPreview, GameState, MyBidView, OpportunityView,
  ProjectDetail, ProjectSummary, ResearchTreeView, SimEvent, SitePreview, SupplierCatalog, SupplierCatalogItem, ViabilityResult,
} from '@voltaje/sim';

/** Paneles de la Fase 3 cuyas vistas (más pesadas) solo se calculan mientras están abiertos. */
export type BusinessPanel = 'market' | 'contracts' | 'research' | 'competitors' | 'suppliers';

/** Vistas de negocio (Fase 3). `summary` y `competitors` siempre (barra superior y globo); el resto según el panel abierto. */
export interface BusinessViews {
  summary: BusinessSummary;
  competitors: CompetitorsOverview;
  /** Oportunidades abiertas en las que puedo ofertar (para el contador de la barra). */
  biddableCount: number;
  opportunities?: OpportunityView[];
  myBids?: MyBidView[];
  contracts?: ContractView[];
  research?: ResearchTreeView;
  suppliers?: SupplierCatalog;
}

/** Opciones de una cotización (las mismas del comando `submitBid`). */
export interface QuoteRequest {
  opportunityId: string; techId: string; projectId?: string; marginPct?: number; price?: number; deliveryMonths?: number;
  effort?: 'estandar' | 'reforzada'; equipmentId?: string; epcId?: string;
}
export interface QuoteReply { quote: BidQuoteView | null; suppliers: SupplierCatalogItem[] }

/** Vistas calculadas en el worker con los selectores del motor (necesitan datos + grilla). */
export interface Views {
  projects: ProjectSummary[];
  finance: CompanyFinancials;
  /** Detalle del proyecto enfocado en la UI (null si no hay ventana abierta). */
  detail: ProjectDetail | null;
  business: BusinessViews | null;
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
  | { t: 'finPreview'; reqId: number; projectId: string; lenderId: string; debtFraction: number; partnerShare: number }
  | { t: 'panel'; panel: BusinessPanel | null }
  | { t: 'quote'; reqId: number; req: QuoteRequest }
  | { t: 'quit' };

export type FromWorker =
  | { t: 'ready'; error?: string }
  | { t: 'snapshot'; state: GameState; views: Views }
  | { t: 'events'; events: SimEvent[] }
  | { t: 'saved'; reqId: number; text: string }
  | { t: 'loaded'; reqId: number; error?: string }
  | { t: 'preview'; reqId: number; estimate: SiteEstimate }
  | { t: 'viability'; reqId: number; result?: ViabilityResult; error?: string; ms: number }
  | { t: 'finPreview'; reqId: number; preview: FinancingPreview | null; error?: string }
  | { t: 'quote'; reqId: number; reply: QuoteReply };
