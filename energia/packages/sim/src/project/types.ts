import type { StudyOutcome } from '../data/types';

export type ProjectStage =
  | 'identificado'
  | 'estudios'
  | 'permisos'
  | 'cierre_financiero'
  | 'construccion'
  | 'puesta_en_marcha'
  | 'operacion'
  | 'vendido'
  | 'abandonado'
  | 'desmantelado';

export const TERMINAL_STAGES: readonly ProjectStage[] = ['vendido', 'abandonado', 'desmantelado'];

export interface Site {
  lat: number;
  lon: number;
  cellIndex: number;
  /** Capa de recurso (ghi, viento_tierra). */
  layer: string;
  /** Valor de la celda (público). */
  cellValue: number;
  temperatureC: number;
  /**
   * OCULTO: recurso real = cellValue × realFactor. La UI no debe mostrarlo (solo lo usa la producción).
   */
  realFactor: number;
}

export interface ResourceEstimate {
  /** Estimación P50 del recurso (misma unidad que la capa). */
  value: number;
  /** Incertidumbre relativa (σ) de la estimación. */
  sigma: number;
  /** Estudio que dio la estimación (o 'celda'). */
  source: string;
}

export interface StudyRecord {
  studyId: string;
  status: 'en_curso' | 'completado';
  startTick: number;
  endTick: number;
  costUsd: number;
  outcome?: StudyOutcome;
  findingId?: string;
  /** Efecto sobre el CAPEX (multiplicador) si salió peor. */
  capexFactor?: number;
  /** Para medición de recurso: estimación resultante. */
  measured?: number;
}

export type PermitStatus = 'en_tramite' | 'info_adicional' | 'aprobado' | 'rechazado';

export interface PermitRecord {
  permitId: string;
  status: PermitStatus;
  startTick: number;
  endTick: number;
  costUsd: number;
  /** Veces que la autoridad pidió información adicional en esta solicitud. */
  infoRequests: number;
  applications: number;
}

export interface Finding {
  id: string; // id de FindingDef
  studyId: string;
  status: 'abierto' | 'en_mitigacion' | 'mitigado' | 'fatal';
  endTick?: number;
  costUsd: number;
  attempts: number;
}

export interface PpaContract {
  channelId: string;
  status: 'en_proceso' | 'firmado' | 'fallido';
  startTick: number;
  endTick: number;
  priceUsdMwh: number;
  years: number;
  indexation: number;
  /** Fecha límite de COD (tick). Después, multa mensual. */
  codDeadlineTick: number;
  penaltyUsdMwMonth: number;
  costUsd: number;
}

export interface Financing {
  status: 'en_proceso' | 'cerrado' | 'fallido';
  lenderId: string;
  startTick: number;
  endTick: number;
  requestedDebtFraction: number;
  partnerShare: number;
  rate: number;
  tenorYears: number;
  dscrTarget: number;
  budgetUsd: number;
  debtUsd: number;
  equityUsd: number;
  feesUsd: number;
  partnerPremiumUsd: number;
  failReason?: string;
}

export interface MilestoneState { id: string; nombre: string; fraction: number; start: number; end: number; done: boolean }

export interface Construction {
  startTick: number;
  plannedDays: number;
  progress: number; // 0–1
  milestones: MilestoneState[];
  equipmentArrivalTick: number;
  equipmentArrived: boolean;
  /** Días de paralización restantes (huelga, clima). */
  stoppedDays: number;
  stopReason?: string;
  delayDays: number;
  budgetUsd: number;
  overrunUsd: number;
  spentUsd: number;
  /** Intereses durante construcción capitalizados. */
  idcUsd: number;
  /** Gasto del mes en curso (se liquida al cerrar el mes). */
  monthSpendUsd: number;
  monthOverrunUsd: number;
  /** Retraso de entrega de equipos (días). */
  equipmentLateDays: number;
  commissioningStartTick?: number;
  commissioningDays?: number;
}

export interface Outage { fraction: number; daysLeft: number }

export interface Operation {
  codTick: number;
  endOfLifeTick: number;
  maintenance: 'preventivo' | 'correctivo';
  outages: Outage[];
  /** OCULTO: factor de capacidad real (del recurso real), calculado al entrar en operación. */
  fcReal: number;
  /** Factor interanual del año en curso (clima). */
  yearFactor: number;
  /** Fase 3: multiplicador de FC por I+D vigente al entrar en operación (ya incluido en fcReal). */
  fcBonus?: number;
  /** Multiplicador de fallas por calidad/confiabilidad del equipo. */
  failureMultiplier: number;
  /** Acumulado del mes en curso. */
  month: { energyMwh: number; availSum: number; days: number; repairUsd: number };
  /** Fallas (últimas 100): día, fracción de la planta fuera, días y costo de reparación. Opcional (partidas viejas no la traen). */
  failures?: { tick: number; fraction: number; days: number; costUsd: number }[];
  /** Historial mensual (últimos 120 meses). */
  history: { year: number; month: number; energyMwh: number; revenueUsd: number; opexUsd: number; availability: number }[];
  totalEnergyMwh: number;
  totalRevenueUsd: number;
  grossAssetUsd: number;
  accumulatedDepreciationUsd: number;
}

export interface Debt {
  principalUsd: number;
  outstandingUsd: number;
  rate: number;
  tenorMonths: number;
  monthsPaid: number;
  monthlyPayment: number;
}

export interface TimelineEntry { tick: number; text: string; kind: 'info' | 'bueno' | 'malo' }

export interface Project {
  id: string;
  name: string;
  techId: string;
  countryCode: string;
  mw: number;
  createdTick: number;
  stage: ProjectStage;
  site: Site;
  estimate: ResourceEstimate;
  studies: Record<string, StudyRecord>;
  permits: Record<string, PermitRecord>;
  findings: Finding[];
  /** Multiplicador acumulado del CAPEX por resultados «peor». */
  capexFactor: number;
  suppliers?: { equipmentId: string; epcId: string; inverterId?: string; logisticsId?: string };
  /** Fase 3: contrato (licitación o cliente privado) al que está vinculado el proyecto. */
  contractId?: string;
  ppa?: PpaContract;
  financing?: Financing;
  construction?: Construction;
  operation?: Operation;
  debt?: Debt;
  /** Costo de desarrollo capitalizado (estudios, permisos, comisiones). */
  devCostUsd: number;
  /** Gastos de desarrollo llevados a resultados (opción de terreno). */
  devExpenseUsd: number;
  sale?: { status: 'en_proceso' | 'vendido' | 'fallido'; startTick: number; endTick: number; priceUsd: number };
  partnerShare: number;
  timeline: TimelineEntry[];
  endTick?: number;
}
