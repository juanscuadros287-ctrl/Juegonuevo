import type {
  BidQuoteView, BusinessSummary, Command, CompanyFinancials, CompetitorsOverview, ContractView, CountrySheet, CountrySummary, FinancingPreview, GameState,
  MyBidView, OpportunityView, ProjectDetail, ProjectSummary, ResearchTreeView, SimEvent, SitePreview, SupplierCatalog, SupplierCatalogItem, TechCatalogEntry,
  ViabilityResult, selectFuelMarkets, ClimateView, DispatchPolicy, PlantDispatchView, PowerMarketView, WorldEventView, WorldEventsOverview,
  selectMarketShareHistory, selectPowerMarkets, selectRevenueBySource,
} from '@voltaje/sim';

/** Paneles de las Fases 3 y 4 cuyas vistas (más pesadas) solo se calculan mientras están abiertos. */
export type BusinessPanel = 'market' | 'contracts' | 'research' | 'competitors' | 'suppliers' | 'countries' | 'catalog' | 'power' | 'world';

export type FuelMarket = ReturnType<typeof selectFuelMarkets>[number];

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
  // ───────── Fase 4 ─────────
  /** Lista de países (siempre: el globo resalta presencia y desbloqueo). */
  countries: CountrySummary[];
  /** Ficha del país elegido (solo con la ventana Países abierta y un país elegido). */
  countrySheet?: CountrySheet | null;
  /** Mercados de combustibles (ventana Países). */
  fuels?: FuelMarket[];
  /** Catálogo de tecnologías con LCOE típico por país (ventana Tecnologías; se recalcula una vez por mes). */
  catalog?: TechCatalogEntry[];
}

/** Opciones de una cotización (las mismas del comando `submitBid`). */
export interface QuoteRequest {
  opportunityId: string; techId: string; projectId?: string; marginPct?: number; price?: number; deliveryMonths?: number;
  effort?: 'estandar' | 'reforzada'; equipmentId?: string; epcId?: string;
}
export interface QuoteReply { quote: BidQuoteView | null; suppliers: SupplierCatalogItem[] }

// ───────── Fase 5 ─────────
export type PowerMarketRow = ReturnType<typeof selectPowerMarkets>[number];
export type RevenueBySource = ReturnType<typeof selectRevenueBySource>;
export type ShareHistory = ReturnType<typeof selectMarketShareHistory>;

/** Marcador de una oportunidad abierta en el globo (`OpportunityView.location`, aproximada). */
export interface OpportunityMark { id: string; lat: number; lon: number; clientName: string; countryCode: string; mw: number; techs: string[]; kind: string; daysLeft: number; myBid: boolean }

/** Vistas de la Fase 5 (mercado eléctrico, mundo). Lo liviano siempre; el resto según la ventana abierta. */
export interface PowerViews {
  /** Eventos del mundo activos (barra, avisos y globo). */
  worldActive: WorldEventView[];
  /** Clima (El Niño/La Niña) e hidrología del país de origen. */
  climate: ClimateView;
  /** Ingresos de la empresa por fuente (finanzas). */
  revenue: RevenueBySource;
  /** Oportunidades abiertas con ubicación (globo). */
  oppMarks: OpportunityMark[];
  /** Ventana Mercado eléctrico: resumen por país y el país elegido. */
  markets?: PowerMarketRow[];
  market?: PowerMarketView | null;
  /** Ventana Mundo. */
  world?: WorldEventsOverview;
  /** Ventana Competidores: cuota de mercado mensual. */
  shareHistory?: ShareHistory;
}

/** Vistas calculadas en el worker con los selectores del motor (necesitan datos + grilla). */
export interface Views {
  projects: ProjectSummary[];
  finance: CompanyFinancials;
  /** Detalle del proyecto enfocado en la UI (null si no hay ventana abierta). */
  detail: ProjectDetail | null;
  business: BusinessViews | null;
  /** Fase 5. */
  power: PowerViews | null;
  /** Despacho, ventas y seguro del proyecto enfocado (solo si opera o está en obra). */
  dispatch: PlantDispatchView | null;
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
  | { t: 'focus'; projectId: string | null; tab?: string }
  | { t: 'powerCountry'; iso3: string }
  | { t: 'dispatchPreview'; reqId: number; projectId: string; policy: DispatchPolicy }
  | { t: 'debug'; op: 'worldEvent'; eventId: string; countries: string[] | null }
  | { t: 'debug'; op: 'autopilot'; maxDays?: number; extraDays?: number }
  | { t: 'preview'; reqId: number; techId: string; mw: number; lat: number; lon: number; to?: { lat: number; lon: number } }
  | { t: 'country'; iso3: string | null }
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
  | { t: 'quote'; reqId: number; reply: QuoteReply }
  | { t: 'dispatchPreview'; reqId: number; view: PlantDispatchView | null; error?: string };
