import type { GameState } from '../core/state';
import type { SimContext } from '../core/context';
import type { ProjectEvent, Severity } from '../core/events';
import { postCash, type Category } from '../finance/company';
import { financingBlockers } from './requirements';
import { TERMINAL_STAGES, type Project, type TimelineEntry } from './types';

const TIMELINE_KEEP = 300;

/** Agrega una línea a la línea de tiempo del proyecto y devuelve el evento listo para la UI. */
export function note<T extends ProjectEvent['type']>(
  state: GameState, p: Project, type: T, text: string, severity: Severity,
  extra?: Omit<Extract<ProjectEvent, { type: T }>, 'type' | 'projectId' | 'text' | 'severity'>,
): ProjectEvent {
  const kind: TimelineEntry['kind'] = severity;
  p.timeline.push({ tick: state.tick, text, kind });
  if (p.timeline.length > TIMELINE_KEEP) p.timeline.splice(0, p.timeline.length - TIMELINE_KEEP);
  return { type, projectId: p.id, text, severity, ...(extra ?? {}) } as ProjectEvent;
}

export const fmtUsd = (v: number) => `${Math.round(v).toLocaleString('es-PA')} USD`;

/** Paga un costo de desarrollo (capitalizado en el proyecto). */
export function payDev(state: GameState, p: Project, amount: number, concept: string) {
  p.devCostUsd += amount;
  postCash(state, 'inversion_desarrollo', -amount, `${p.name}: ${concept}`);
}

export function payExpense(state: GameState, p: Project, cat: Category, amount: number, concept: string) {
  postCash(state, cat, -amount, `${p.name}: ${concept}`);
}

export function isTerminal(p: Project) {
  return TERMINAL_STAGES.includes(p.stage);
}

/** Recalcula la etapa a partir del avance real del proyecto. */
export function updateStage(ctx: SimContext, p: Project) {
  if (isTerminal(p)) return;
  if (p.operation) p.stage = 'operacion';
  else if (p.construction) p.stage = p.construction.commissioningStartTick !== undefined ? 'puesta_en_marcha' : 'construccion';
  else if (financingBlockers(ctx, p).length === 0) p.stage = 'cierre_financiero';
  else if (Object.keys(p.permits).length) p.stage = 'permisos';
  else if (Object.keys(p.studies).length) p.stage = 'estudios';
  else p.stage = 'identificado';
}

export const DAYS_PER_MONTH = 30.44;
