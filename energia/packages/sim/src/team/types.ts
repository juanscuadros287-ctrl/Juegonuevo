import type { OfficeLevelId, TeamArea } from '../data/types';

/** Fase 6: persona (candidato o empleado). Los ids son únicos en toda la partida (`LaborMarket.nextPersonId`). */
export interface Person {
  id: string;
  name: string;
  /** Rol (team.yaml → roles). */
  role: string;
  /** País de origen/base (mercado laboral donde se contrató; cuenta para la capacidad de la oficina de ese país). */
  countryCode: string;
  /** Habilidad 0–100. */
  skill: number;
  experienceYears: number;
  languages: string[];
}

export interface Candidate extends Person {
  /** Salario bruto mensual pedido (USD). */
  askUsdMonth: number;
  postedTick: number;
  expiresTick: number;
}

export interface Employee extends Person {
  /** Salario bruto mensual (USD); el costo para la empresa suma las cargas sociales del país. */
  salaryUsdMonth: number;
  /** Moral 0–100. */
  morale: number;
  hiredTick: number;
  /** Proyectos asignados. Vacío = en la oficina (atiende todos los proyectos de la empresa, con su carga). */
  assignment: string[];
  /** En capacitación hasta este tick (sin efecto mientras tanto). */
  trainingUntilTick?: number;
  trainings: number;
}

export interface TeamState {
  employees: Employee[];
  hires: number;
  quits: number;
  fired: number;
  /** Historial mensual (últimos 120 meses): personas y costo del mes. */
  history: { year: number; month: number; headcount: number; costUsd: number; avgMorale: number }[];
}

export type RepAxis = 'gobierno' | 'comunidad' | 'clientes';

export interface ReputationLogEntry { tick: number; axis: RepAxis; countryCode?: string; delta: number; cause: string; text: string }

export interface ReputationState {
  gobierno: Record<string, number>;
  comunidad: Record<string, number>;
  /** Últimos 80 cambios con su causa. */
  log: ReputationLogEntry[];
  /** Historial mensual (últimos 120 meses). */
  history: { year: number; month: number; clientes: number; gobierno: Record<string, number>; comunidad: Record<string, number> }[];
  /** Puntos de comunidad comprados con inversión social en el año en curso, por país (tope anual). */
  socialYear: { year: number; points: Record<string, number> };
}

export interface OfficeState {
  level: OfficeLevelId;
  /** Mejora en curso. */
  upgradeTo?: OfficeLevelId;
  readyTick?: number;
  sinceTick: number;
}

export interface LaborMarket {
  candidates: Record<string, Candidate[]>;
  nextPersonId: number;
  /** Avisos para otros actores (p. ej. «tu ingeniera aceptó una oferta de X»); el jugador los recibe en el siguiente paso. */
  notices?: { actorId: string; event: import('../core/events').SimEvent }[];
}

export type { TeamArea, OfficeLevelId };
