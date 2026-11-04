import type { Command } from './commands';
import type { StudyOutcome } from '../data/types';

/**
 * Eventos que la UI debe notificar. Los de proyecto llevan `projectId` y un `text` listo en español.
 * `severity`: 'info' | 'bueno' | 'malo' para colorear el aviso.
 */
type P<T extends string, X = object> = { type: T; projectId: string; text: string; severity: Severity } & X;
export type Severity = 'info' | 'bueno' | 'malo';

export type SimEvent =
  | { type: 'newMonth'; year: number; month: number }
  | { type: 'newYear'; year: number }
  | { type: 'commandRejected'; command: Command; error: string }
  | { type: 'cashNegative'; cashUsd: number; monthsNegative: number }
  | { type: 'emergencyCredit'; amountUsd: number; text: string }
  | { type: 'bankruptcy'; cashUsd: number; text: string }
  | P<'projectCreated'>
  | P<'studyStarted', { studyId: string }>
  | P<'processStarted', { process: 'ppa' | 'mitigacion' | 'financiamiento' }>
  | P<'studyCompleted', { studyId: string; outcome: StudyOutcome }>
  | P<'findingDiscovered', { findingId: string; mitigable: boolean }>
  | P<'findingResolved', { findingId: string; success: boolean }>
  | P<'permitRequested', { permitId: string }>
  | P<'permitInfoRequested', { permitId: string; delayDays: number; costUsd: number }>
  | P<'permitDecided', { permitId: string; approved: boolean }>
  | P<'ppaResult', { channelId: string; success: boolean; priceUsdMwh?: number }>
  | P<'financingResult', { success: boolean; debtUsd?: number; equityUsd?: number }>
  | P<'constructionStarted'>
  | P<'equipmentArrived', { lateDays: number }>
  | P<'milestoneCompleted', { milestoneId: string }>
  | P<'constructionDelay', { reason: string; days: number }>
  | P<'costOverrun', { amountUsd: number; milestoneId: string }>
  | P<'qualityDefect', { days: number }>
  | P<'commissioningStarted'>
  | P<'projectOperational'>
  | P<'plantFailure', { fractionLost: number; days: number; costUsd: number }>
  | P<'ppaPenalty', { amountUsd: number }>
  | P<'saleStarted'>
  | P<'projectSold', { priceUsd: number }>
  | P<'saleFailed'>
  | P<'projectAbandoned', { writeOffUsd: number }>
  | P<'projectDecommissioned', { costUsd: number }>;

export type ProjectEvent = Extract<SimEvent, { projectId: string }>;
