import type { ContractKind } from '../data/types';
import type { Company, FinanceState } from '../core/state';
import type { Project } from '../project/types';

/** Id del jugador como actor en licitaciones y contratos. */
export const PLAYER_ID = 'jugador';

// ───────────────────────── I+D ─────────────────────────

export interface ActiveResearch {
  nodeId: string;
  startTick: number;
  /** 0–1 */
  progress: number;
  spentUsd: number;
  /** Ya tuvo su contratiempo (solo uno por nodo). */
  setback: boolean;
}

export interface ResearchState {
  completed: string[];
  active: ActiveResearch | null;
  queue: string[];
  budgetUsdMonth: number;
  /** Avance conservado de investigaciones canceladas (la mitad de lo logrado). */
  partial: Record<string, number>;
  /** Gasto devengado en el mes en curso (se paga al cerrar el mes). */
  monthSpendUsd: number;
  totalSpentUsd: number;
}

// ───────────────────── Proveedores ─────────────────────

export interface SupplierRelation { orders: number; mw: number; lateDeliveries: number }

// ───────────────────── Licitaciones ─────────────────────

export type BidStatus = 'presentada' | 'ganada' | 'perdida' | 'descalificada' | 'retirada';

export interface Bid {
  id: string;
  opportunityId: string;
  actorId: string;
  actorName: string;
  techId: string;
  /** USD/MWh (ppa, bot), USD/kW-mes (potencia) o USD/kW (epc). */
  price: number;
  deliveryMonths: number;
  projectId?: string;
  effort: 'estandar' | 'reforzada';
  equipmentId?: string;
  epcId?: string;
  submittedTick: number;
  bondUsd: number;
  prepCostUsd: number;
  status: BidStatus;
  /** Puntajes al evaluar (0–100). */
  score?: { price: number; technical: number; experience: number; delivery: number; total: number };
  rank?: number;
}

export type OpportunityStatus = 'abierta' | 'evaluacion' | 'adjudicada' | 'desierta';

export interface RankingEntry {
  actorId: string;
  name: string;
  price: number;
  deliveryMonths: number;
  score: number;
  /** Ofertante externo (no simulado como empresa). */
  external: boolean;
  disqualified?: string;
}

export interface Opportunity {
  id: string;
  clientTypeId: string;
  clientName: string;
  countryCode: string;
  kind: 'licitacion_publica' | 'solicitud_privada';
  contract: ContractKind;
  /** Nodo de I+D de tipo de contrato exigido. */
  contractType: string;
  mw: number;
  years: number;
  techs: string[];
  /** Precio tope publicado (solo si la licitación lo publica). */
  ceilingPrice?: number;
  /** OCULTO: precio máximo que el cliente acepta (igual al tope si es público). */
  reservePrice: number;
  /** Precio de referencia de mercado (público, orientativo). */
  referencePrice: number;
  openedTick: number;
  deadlineTick: number;
  awardTick: number;
  codMonths: number;
  bidBondUsd: number;
  performanceBondUsd: number;
  weights: { precio: number; tecnica: number; experiencia: number; plazo: number };
  minExperienceMw: number;
  minEquityUsd: number;
  penaltyUsdMwMonth: number;
  maxDelayMonths: number;
  prepCostUsd: number;
  indexation: number;
  status: OpportunityStatus;
  /** Fase 4: moneda del contrato ('local' = el precio en USD sigue al tipo de cambio desde la firma). Ausente = USD. */
  currency?: 'USD' | 'local';
  /** Fase 6: solicitud privada directa (solo el invitado puede ofertar; casi sin ofertantes externos). */
  invitedActorId?: string;
  /** Ofertas selladas (la UI solo ve la propia hasta la adjudicación). */
  bids: Bid[];
  result?: { ranking: RankingEntry[]; winnerId?: string; winnerName?: string; winnerPrice?: number; tick: number; reason?: string };
}

// ───────────────────── Contratos ─────────────────────

export type ContractStatus = 'sin_proyecto' | 'en_desarrollo' | 'operando' | 'cumplido' | 'incumplido' | 'cedido';

export interface EpcExecution {
  budgetUsd: number;
  spentUsd: number;
  progress: number;
  plannedDays: number;
  startTick: number;
  stoppedDays: number;
  delayDays: number;
  overrunUsd: number;
  collectedUsd: number;
  ldUsd: number;
  equipmentId: string;
  epcId: string;
  monthSpendUsd: number;
  monthProgress: number;
  deliveredTick?: number;
}

export interface Contract {
  id: string;
  opportunityId: string;
  actorId: string;
  kind: ContractKind;
  clientName: string;
  countryCode: string;
  /** MW contratados (firmes en potencia). */
  mw: number;
  techId: string;
  price: number;
  years: number;
  indexation: number;
  signedTick: number;
  codDeadlineTick: number;
  /** Después de esta fecha sin COD/entrega se ejecuta la garantía y se rescinde. */
  terminationTick: number;
  /** Fecha límite para asignar un proyecto (contratos «con proyecto nuevo»). */
  assignDeadlineTick?: number;
  projectId?: string;
  bondUsd: number;
  penaltyUsdMwMonth: number;
  penaltiesUsd: number;
  revenueUsd: number;
  status: ContractStatus;
  /** Fase 4: moneda y tipo de cambio nominal a la firma. */
  currency?: 'USD' | 'local';
  fxAtSigning?: number;
  codTick?: number;
  endTick?: number;
  epc?: EpcExecution;
}

// ───────────────────── Actor (empresa) ─────────────────────

export interface BusinessState {
  reputation: number;
  /** Experiencia previa (MW) al empezar la partida. */
  experienceMwBase: number;
  /** MW entregados en EPC para terceros. */
  epcDeliveredMw: number;
  research: ResearchState;
  contracts: Contract[];
  nextContractId: number;
  relations: Record<string, SupplierRelation>;
  /** Caja inmovilizada en garantías bancarias. */
  restrictedCashUsd: number;
  bidsWon: number;
  bidsLost: number;
  /**
   * Fase 4: presencia legal por país (constitución + representante legal). El país de origen no figura: siempre
   * está abierto. `level: 'oficina'` queda reservado para la Fase 6 (oficinas completas).
   */
  presence?: Record<string, Presence>;
  /** Fase 6: equipo propio (personas, cargas, capacitación). */
  team?: import('../team/types').TeamState;
  /** Fase 6: reputación con gobiernos y comunidades por país (la de clientes es `reputation`, que se mantiene como alias). */
  rep?: import('../team/types').ReputationState;
  /** Fase 6: oficinas por país (el de origen arranca con oficina local; sin entrada = nivel de la presencia). */
  offices?: Record<string, import('../team/types').OfficeState>;
}

export interface Presence {
  status: 'en_tramite' | 'activa' | 'cerrada';
  /** Fase 6: 'sede' (sede regional). Alias del nivel de `business.offices[iso]`. */
  level: 'representante' | 'oficina' | 'sede';
  requestedTick: number;
  readyTick: number;
  setupCostUsd: number;
  monthlyCostUsd: number;
  closedTick?: number;
}

export interface CompetitorState {
  id: string;
  defId: string;
  name: string;
  company: Company;
  finance: FinanceState;
  projects: Project[];
  nextProjectId: number;
  business: BusinessState;
  status: 'activa' | 'quebrada';
  /** Próximo tick de decisión. */
  nextDecisionTick: number;
  rejectedCommands: number;
}

// ───────────────────── Mundo compartido ─────────────────────

export interface SupplyState {
  materials: Record<string, number>;
  demandIndex: number;
  /** Cola de pedidos (MW) por proveedor. */
  backlogMw: Record<string, number>;
  /** Historial mensual (últimos 120 meses). */
  history: { year: number; month: number; materials: Record<string, number>; demandIndex: number; equipment: Record<string, number>; epc: Record<string, number> }[];
}

export interface MarketState {
  initialized: boolean;
  /** Competidores IA activados en esta partida. */
  competitorsEnabled: boolean;
  opportunities: Opportunity[];
  nextOpportunityId: number;
  supply: SupplyState;
  /** Fase 4: tipo de cambio real por país (1 = el del inicio; la deriva nominal por inflación se agrega aparte). */
  fx?: Record<string, number>;
  /** Fase 4: índice de precio de cada combustible (1 = precio de referencia de markets.yaml). */
  fuels?: Record<string, number>;
  /** Fase 4: historial mensual (últimos 120 meses) de tipos de cambio nominales (USD por unidad) e índices de combustibles. */
  macroHistory?: { year: number; month: number; fxUsdPerUnit: Record<string, number>; fuels: Record<string, number> }[];
  /** Fase 5: mercado eléctrico (clima, parque de los actores, precios horarios del mes, historial). */
  power?: import('../market/power').PowerState;
  /** Fase 5: eventos del mundo, regulación vigente por país y elecciones. */
  world?: import('../world/events').WorldState;
  /** Fase 3 (pedido de la UI): cuota de mercado mensual por actor (MW en operación). */
  shareHistory?: { year: number; month: number; mw: Record<string, number> }[];
  /** Fase 6: mercado laboral compartido (candidatos por país). */
  labor?: import('../team/types').LaborMarket;
}

export function newResearchState(): ResearchState {
  return { completed: [], active: null, queue: [], budgetUsdMonth: 0, partial: {}, monthSpendUsd: 0, totalSpentUsd: 0 };
}

export function newBusinessState(reputation = 25, experienceMwBase = 0): BusinessState {
  return {
    reputation, experienceMwBase, epcDeliveredMw: 0, research: newResearchState(), contracts: [], nextContractId: 1, relations: {},
    restrictedCashUsd: 0, bidsWon: 0, bidsLost: 0, presence: {},
  };
}

export function newMarketState(competitorsEnabled = true): MarketState {
  return { initialized: false, competitorsEnabled, opportunities: [], nextOpportunityId: 1, supply: { materials: {}, demandIndex: 1, backlogMw: {}, history: [] } };
}
