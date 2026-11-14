import type { Command } from './commands';
import type { StudyOutcome } from '../data/types';

/**
 * Eventos que la UI debe notificar. Los de proyecto llevan `projectId` y un `text` listo en español.
 * `severity`: 'info' | 'bueno' | 'malo' para colorear el aviso.
 */
type P<T extends string, X = object> = { type: T; projectId: string; text: string; severity: Severity } & X;
export type Severity = 'info' | 'bueno' | 'malo';

/**
 * `tick`: día de la partida en que ocurrió. Lo pone `step`/`applyCommands` en TODOS los eventos que devuelven
 * (los de comandos llevan el día en que se aplicaron; los del avance, el día nuevo).
 */
export type SimEvent = SimEventBase & { tick?: number };

export type SimEventBase =
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
  | P<'projectDecommissioned', { costUsd: number }>
  // Fase 4
  | P<'wellsDrilled', { producers: number; injectors: number; dry: number; extraCostUsd: number }>
  | P<'savingsShortfall', { shortfallMwh: number; penaltyUsd: number }>
  // Fase 5
  | P<'plantDamaged', { eventId: string; costUsd: number; insuredUsd: number; days: number }>
  | P<'insuranceChanged', { coverage: string | null; premiumUsdYear: number }>
  | P<'dispatchPolicyChanged'>
  | P<'ppaTerminated', { penaltyUsd: number }>
  | P<'operationBlocked', { missing: string[] }>
  | P<'curtailment', { curtailedMwh: number; reason: 'precio' | 'red' }>
  | BusinessEvent;

/** Eventos de negocio (Fase 3): texto en español y severidad. */
type B<T extends string, X = object> = { type: T; text: string; severity: Severity } & X;

export type BusinessEvent =
  | B<'opportunityOpened', { opportunityId: string }>
  | B<'bidSubmitted', { opportunityId: string }>
  | B<'bidWithdrawn', { opportunityId: string }>
  | B<'bidResult', { opportunityId: string; won: boolean; rank: number; winnerName: string; winnerPrice: number }>
  | B<'opportunityDeserted', { opportunityId: string }>
  | B<'contractSigned', { contractId: string }>
  | B<'contractProjectAssigned', { contractId: string }>
  | B<'contractFulfilled', { contractId: string; amountUsd?: number }>
  | B<'contractTerminated', { contractId: string }>
  | B<'contractPenalty', { contractId: string; amountUsd: number }>
  | B<'guaranteeExecuted', { contractId: string; amountUsd: number }>
  | B<'guaranteeReleased', { contractId: string; amountUsd: number }>
  | B<'epcDelivered', { contractId: string }>
  | B<'epcUpdate', { contractId: string; amountUsd?: number }>
  | B<'researchStarted', { nodeId: string }>
  | B<'researchCompleted', { nodeId: string }>
  | B<'researchSetback', { nodeId: string }>
  | B<'researchCancelled', { nodeId: string }>
  | B<'supplyPriceChange', { techId: string; changePct: number }>
  | B<'competitorWonTender', { competitorId: string; opportunityId: string }>
  | B<'competitorPlantOperational', { competitorId: string; techId: string; mw: number }>
  | B<'competitorBankrupt', { competitorId: string }>
  // Fase 4
  | B<'presenceRequested', { countryCode: string }>
  | B<'presenceOpened', { countryCode: string }>
  | B<'presenceClosed', { countryCode: string }>
  | B<'competitorExpanded', { competitorId: string; countryCode: string }>
  | B<'currencyShock', { countryCode: string; changePct: number }>
  | B<'fuelPriceChange', { fuelId: string; changePct: number }>
  // Fase 5
  | B<'climateOutlook', { enso: 'nino' | 'nina' | 'neutral' }>
  | B<'worldEvent', { eventId: string; uid: number; countryCode?: string }>
  | B<'worldEventEnded', { eventId: string; uid: number; countryCode?: string }>
  // Fase 6
  | B<'employeeHired', { employeeId: string; countryCode: string }>
  | B<'hireRejected', { candidateId: string }>
  | B<'employeeFired', { employeeId: string; severanceUsd: number }>
  | B<'employeeQuit', { employeeId: string; reason: 'moral' | 'oferta' }>
  | B<'employeePoached', { employeeId: string; fromActorId: string; toActorId: string }>
  | B<'poachRejected', { employeeId: string }>
  | B<'employeeAssigned', { employeeId: string }>
  | B<'salaryChanged', { employeeId: string; salaryUsdMonth: number }>
  | B<'trainingStarted', { employeeId: string }>
  | B<'trainingCompleted', { employeeId: string; skill: number }>
  | B<'officeUpgradeStarted', { countryCode: string; level: string }>
  | B<'officeChanged', { countryCode: string; level: string }>
  | B<'reputationChanged', { axis: 'gobierno' | 'comunidad' | 'clientes'; countryCode?: string; delta: number; cause: string }>
  | B<'communityInvestment', { countryCode: string; amountUsd: number; points: number }>
  | B<'directInvitation', { opportunityId: string; countryCode: string }>
  | P<'communityConflict', { days: number; costUsd: number }>
  | P<'constructionAccident', { days: number; costUsd: number }>;

export type ProjectEvent = Extract<SimEvent, { projectId: string }>;
