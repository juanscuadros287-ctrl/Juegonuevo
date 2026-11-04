/**
 * Selectores de solo lectura para la UI. No modifican el estado ni consumen RNG.
 * Nunca exponen el recurso real oculto (Site.realFactor / Operation.fcReal).
 */
import type { GameState, MonthlyStatement } from './core/state';
import type { SimContext } from './core/context';
import { daysInMonth, fromEpochDay, type GameDate } from './core/calendar';
import { normalizedProfile } from './market/spot';
import { maturity } from './business/bids';
import { CATEGORIES, balanceSheet, type BalanceSheet } from './finance/company';
import { currentCapex, type CapexBreakdown } from './tech/costs';
import { supplierLeadFactor, supplierPriceFactor, supplierReliability } from './supply/supply';
import { studyUnlocked, unlockingNode } from './business/research';
import { capacityFactor } from './tech/capacityFactor';
import { hiddenResourceFactor, p90 } from './world/site';
import { DAYS_PER_MONTH } from './project/helpers';
import { findingCostUsd, permitApprovalProbability, permitCostUsd, studyCostUsd } from './project/outcomes';
import {
  applicablePermits, applicableStudies, financingBlockers, openFindings, permitBlockers, requiredStudyGroups, studyBlockers, studyGroupDone,
} from './project/requirements';
import { projectCapex, projectEconomics, type Economics } from './project/economics';
import { bankDebtSizing } from './project/tick';
import { remainingDevCostUsd, saleValueUsd, successProbability } from './project/valuation';
import { TERMINAL_STAGES, type Project, type ProjectStage } from './project/types';

export const STAGE_LABELS: Record<ProjectStage, string> = {
  identificado: 'Identificado',
  estudios: 'Estudios',
  permisos: 'Permisos',
  cierre_financiero: 'Cierre financiero',
  construccion: 'Construcción',
  puesta_en_marcha: 'Puesta en marcha',
  operacion: 'Operación',
  vendido: 'Vendido',
  abandonado: 'Abandonado',
  desmantelado: 'Desmantelado',
};

const dateOf = (s: GameState, tick: number): GameDate => fromEpochDay(s.startEpochDay + tick);

export interface ProjectSummary {
  id: string;
  name: string;
  techId: string;
  techName: string;
  mw: number;
  stage: ProjectStage;
  stageLabel: string;
  lat: number;
  lon: number;
  /** Avance de obra 0–1 (para el modelo 3D); 1 en operación. */
  buildProgress: number;
  /**
   * Avance de la etapa actual 0–1: en desarrollo (identificado → cierre financiero) = estudios requeridos hechos +
   * permisos aprobados sobre el total; en obra = avance de obra; puesta en marcha = días transcurridos; operación = 1.
   */
  stageProgress: number;
  /** Texto corto con lo siguiente que hay que hacer o lo que está en curso. */
  nextStep: string;
  devCostUsd: number;
  resourceP50: number;
  resourceSigma: number;
  fcP50: number;
  irrEquity: number | null;
  npvEquityUsd: number;
  warnings: string[];
  active: boolean;
}

function safeEconomics(state: GameState, ctx: SimContext, p: Project): Economics | null {
  try { return projectEconomics(state, ctx, p); } catch { return null; }
}

function nextStep(ctx: SimContext, p: Project): string {
  if (TERMINAL_STAGES.includes(p.stage)) return STAGE_LABELS[p.stage];
  if (p.sale?.status === 'en_proceso') return 'En venta';
  if (p.operation) return 'Operando';
  if (p.construction) {
    if (p.construction.commissioningStartTick !== undefined) return 'Puesta en marcha';
    const m = p.construction.milestones.find((x) => !x.done);
    return m ? `Obra: ${m.nombre}` : 'Obra';
  }
  const busy: string[] = [];
  for (const r of Object.values(p.studies)) if (r.status === 'en_curso') busy.push(ctx.data.studies[r.studyId].nombre);
  for (const r of Object.values(p.permits)) if (r.status === 'en_tramite') busy.push(ctx.data.countries[p.countryCode].permisos.find((x) => x.id === r.permitId)?.nombre ?? r.permitId);
  if (p.ppa?.status === 'en_proceso') busy.push('PPA');
  if (p.financing?.status === 'en_proceso') busy.push('Due diligence del banco');
  if (busy.length) return `En curso: ${busy.join(', ')}`;
  if (openFindings(p).length) return 'Resolver hallazgo';
  const fb = financingBlockers(ctx, p);
  if (!fb.length) {
    if (!p.suppliers) return 'Elegir proveedores';
    if (p.financing?.status !== 'cerrado') return 'Armar financiamiento';
    return 'Iniciar construcción';
  }
  return fb[0];
}

function stageProgress(state: GameState, ctx: SimContext, p: Project): number {
  if (p.operation || TERMINAL_STAGES.includes(p.stage)) return 1;
  const k = p.construction;
  if (k?.commissioningStartTick !== undefined) return Math.min(1, (state.tick - k.commissioningStartTick) / Math.max(1, k.commissioningDays ?? 1));
  if (k) return k.progress;
  return maturity(ctx, p);
}

export function selectProjects(state: GameState, ctx: SimContext): ProjectSummary[] {
  return state.projects.map((p) => {
    const tech = ctx.data.technologies[p.techId];
    const eco = TERMINAL_STAGES.includes(p.stage) ? null : safeEconomics(state, ctx, p);
    const warnings: string[] = [];
    if (p.findings.some((f) => f.status === 'abierto')) warnings.push('Hallazgo sin resolver');
    if (p.findings.some((f) => f.status === 'fatal')) warnings.push('Hallazgo fatal');
    if (Object.values(p.permits).some((r) => r.status === 'rechazado')) warnings.push('Permiso rechazado');
    if (p.ppa?.status === 'firmado' && !p.operation && state.tick > p.ppa.codDeadlineTick) warnings.push('Multa por atraso del PPA');
    if (p.construction && p.construction.delayDays > 30 && !p.operation) warnings.push(`Obra atrasada ${p.construction.delayDays} días`);
    return {
      id: p.id, name: p.name, techId: p.techId, techName: tech?.nombre ?? p.techId, mw: p.mw, stage: p.stage, stageLabel: STAGE_LABELS[p.stage],
      lat: p.site.lat, lon: p.site.lon,
      buildProgress: p.operation ? 1 : p.construction?.progress ?? 0,
      stageProgress: stageProgress(state, ctx, p),
      nextStep: nextStep(ctx, p),
      devCostUsd: p.devCostUsd,
      resourceP50: p.estimate.value, resourceSigma: p.estimate.sigma,
      fcP50: eco?.fcP50 ?? 0, irrEquity: eco?.model.irrEquity ?? null, npvEquityUsd: eco?.npvEquityUsd ?? 0,
      warnings, active: !TERMINAL_STAGES.includes(p.stage),
    };
  });
}

export interface TimelineItem { date: GameDate; text: string; kind: 'info' | 'bueno' | 'malo' | 'plan' }

export interface StudyOption {
  id: string; nombre: string; grupo: string; descripcion: string; costUsd: number; durationDays: { min: number; base: number; max: number };
  sigmaAfter?: number; probs: { normal: number; peor: number; bloqueo: number }; required: boolean;
  status: 'disponible' | 'bloqueado' | 'en_curso' | 'completado'; blockers: string[]; outcome?: string; startDate?: GameDate; endDate?: GameDate;
}
export interface PermitOption {
  id: string; nombre: string; autoridad: string; descripcion: string; costUsd: number; durationDays: { min: number; base: number; max: number };
  probs: { aprobado: number; rechazado: number; info_adicional: number }; approvalProbability: number;
  status: 'disponible' | 'bloqueado' | 'en_tramite' | 'aprobado' | 'rechazado'; blockers: string[]; startDate?: GameDate; endDate?: GameDate; infoRequests: number;
}

export interface MonthlyProduction { month: number; p50Mwh: number; p90Mwh: number }

/** Producción esperada por mes (1–12): energía anual repartida según perfil mensual del recurso × días del mes (suma = energía anual). */
export function expectedMonthlyProduction(ctx: SimContext, p: Project, energyP50Year: number, energyP90Year: number, year: number): MonthlyProduction[] {
  const prof = normalizedProfile(ctx.data.countries[p.countryCode]?.perfil_recurso_mensual[p.site.layer]);
  const w = prof.map((f, i) => f * daysInMonth(year, i + 1));
  const tot = w.reduce((a, b) => a + b, 0);
  return w.map((x, i) => ({ month: i + 1, p50Mwh: energyP50Year * x / tot, p90Mwh: energyP90Year * x / tot }));
}

export interface ProjectDetail {
  summary: ProjectSummary;
  techName: string;
  countryName: string;
  countryCode: string;
  site: { lat: number; lon: number; layer: string; cellValue: number; temperatureC: number };
  resource: {
    p50: number; p90: number; sigma: number; source: string; fcP50: number; fcP90: number; energyP50MwhYear: number; energyP90MwhYear: number;
    /** Producción esperada por mes calendario (perfil estacional del país, disponibilidad y degradación de este año). */
    monthlyMwh: MonthlyProduction[];
  };
  timeline: TimelineItem[];
  studies: StudyOption[];
  permits: PermitOption[];
  findings: { id: string; nombre: string; descripcion: string; status: string; mitigable: boolean; costUsd: number; successProbability: number; endDate?: GameDate }[];
  ppa: Project['ppa'] & { channelName?: string } | null;
  ppaChannels: { id: string; nombre: string; descripcion: string; priceUsdMwh: { min: number; base: number; max: number }; years: number; probability: number; costUsd: number; available: boolean; reason?: string }[];
  lenders: { id: string; nombre: string; descripcion: string; ratePct: number; tenorYears: number; maxLeverage: number; dscr: number; requiresPpa: boolean; maxSigma: number; available: boolean; reason?: string }[];
  suppliers: { equipment: SupplierOption[]; epc: SupplierOption[]; inverters: SupplierOption[]; logistics: SupplierOption[]; selected?: { equipmentId: string; epcId: string; inverterId?: string; logisticsId?: string } };
  /** Fase 3: contrato vinculado (licitación o cliente privado). */
  contractId?: string;
  financing: Project['financing'] | null;
  construction: (NonNullable<Project['construction']> & { startDate: GameDate; expectedEndDate: GameDate }) | null;
  operation: (Omit<NonNullable<Project['operation']>, 'fcReal'> & {
    codDate: GameDate; actualFcLast12m: number | null;
    /** Producción esperada por mes calendario P50/P90 (igual que `resource.monthlyMwh`). */
    expectedMonthlyMwh: MonthlyProduction[];
    /** Fallas pasadas con fecha (las más recientes al final). */
    failureLog: { date: GameDate; fractionLost: number; days: number; costUsd: number }[];
  }) | null;
  debt: Project['debt'] | null;
  costs: {
    incurredUsd: { development: number; landOptions: number; construction: number; idc: number; total: number };
    upcomingUsd: { studies: number; permits: number; financing: number; construction: number; total: number };
    capex: CapexBreakdown;
  };
  economics: Economics | null;
  successProbability: number;
  saleValueUsd: number;
  risks: { id: string; nombre: string; descripcion: string }[];
  canFinance: { ok: boolean; blockers: string[] };
  canStartConstruction: { ok: boolean; blockers: string[] };
}

export interface SupplierOption {
  id: string; nombre: string; origen: string; descripcion: string;
  /** Factor de precio ACTUAL para este jugador (cola del proveedor y relación); `basePriceFactor` = el del YAML. */
  priceFactor: number; basePriceFactor: number; quality: number; reliability: number;
  /** Plazo de entrega típico actual (días, con cola y demanda mundial). */
  leadDays?: number; scheduleFactor?: number; overrunProb?: number;
}

export function selectProjectDetail(state: GameState, ctx: SimContext, projectId: string): ProjectDetail | null {
  const p = state.projects.find((x) => x.id === projectId);
  if (!p) return null;
  const tech = ctx.data.technologies[p.techId];
  const c = ctx.data.countries[p.countryCode];
  const summary = selectProjects(state, ctx).find((x) => x.id === projectId)!;
  const active = !TERMINAL_STAGES.includes(p.stage);
  const eco = active ? safeEconomics(state, ctx, p) : null;

  // Línea de tiempo: pasado + lo planificado
  const timeline: TimelineItem[] = p.timeline.map((e) => ({ date: dateOf(state, e.tick), text: e.text, kind: e.kind }));
  for (const r of Object.values(p.studies)) if (r.status === 'en_curso') timeline.push({ date: dateOf(state, r.endTick), text: `Fin previsto: ${ctx.data.studies[r.studyId].nombre}`, kind: 'plan' });
  for (const r of Object.values(p.permits)) if (r.status === 'en_tramite') timeline.push({ date: dateOf(state, r.endTick), text: `Respuesta prevista: ${c.permisos.find((x) => x.id === r.permitId)?.nombre}`, kind: 'plan' });
  if (p.ppa?.status === 'en_proceso') timeline.push({ date: dateOf(state, p.ppa.endTick), text: 'Resultado previsto del PPA', kind: 'plan' });
  if (p.financing?.status === 'en_proceso') timeline.push({ date: dateOf(state, p.financing.endTick), text: 'Decisión prevista del banco', kind: 'plan' });
  if (p.construction && !p.operation) {
    const k = p.construction;
    const remaining = k.commissioningStartTick !== undefined ? k.commissioningStartTick + (k.commissioningDays ?? 0) - state.tick : (1 - k.progress) * k.plannedDays + k.stoppedDays + 30;
    timeline.push({ date: dateOf(state, state.tick + Math.round(remaining)), text: 'Operación comercial prevista', kind: 'plan' });
  }
  timeline.sort((a, b) => (a.date.year - b.date.year) || (a.date.month - b.date.month) || (a.date.day - b.date.day));

  const reqGroups = new Set(requiredStudyGroups(ctx, p));
  const studies: StudyOption[] = applicableStudies(ctx, p).map((s) => {
    const rec = p.studies[s.id];
    const blockers = studyBlockers(ctx, p, s.id);
    if (!studyUnlocked(state, ctx, s.id)) blockers.push(`Requiere investigación: ${unlockingNode(ctx, 'estudios', s.id)?.nombre ?? 'I+D'}.`);
    const status: StudyOption['status'] = rec ? (rec.status === 'en_curso' ? 'en_curso' : 'completado') : blockers.length ? 'bloqueado' : 'disponible';
    return {
      id: s.id, nombre: s.nombre, grupo: s.grupo, descripcion: s.descripcion, costUsd: studyCostUsd(s, p.mw),
      durationDays: { min: s.duracion_dias.min ?? s.duracion_dias.base, base: s.duracion_dias.base, max: s.duracion_dias.max ?? s.duracion_dias.base },
      sigmaAfter: s.sigma_recurso, probs: { normal: s.resultados.normal, peor: s.resultados.peor, bloqueo: s.resultados.bloqueo },
      required: reqGroups.has(s.grupo) && !studyGroupDone(ctx, p, s.grupo), status, blockers: status === 'bloqueado' ? blockers : [],
      outcome: rec?.outcome, startDate: rec ? dateOf(state, rec.startTick) : undefined, endDate: rec ? dateOf(state, rec.endTick) : undefined,
    };
  });
  const permits: PermitOption[] = applicablePermits(ctx, p).map((d) => {
    const rec = p.permits[d.id];
    const blockers = permitBlockers(ctx, p, d.id);
    const status: PermitOption['status'] = rec && rec.status !== 'info_adicional' ? (rec.status === 'rechazado' && blockers.length === 0 ? 'rechazado' : rec.status) : blockers.length ? 'bloqueado' : 'disponible';
    return {
      id: d.id, nombre: d.nombre, autoridad: d.autoridad, descripcion: d.descripcion, costUsd: permitCostUsd(d, p.mw),
      durationDays: { min: d.duracion_dias.min ?? d.duracion_dias.base, base: d.duracion_dias.base, max: d.duracion_dias.max ?? d.duracion_dias.base },
      probs: { aprobado: d.prob.aprobado, rechazado: d.prob.rechazado, info_adicional: d.prob.info_adicional }, approvalProbability: permitApprovalProbability(d),
      status, blockers: status === 'bloqueado' || status === 'rechazado' ? blockers : [], startDate: rec ? dateOf(state, rec.startTick) : undefined, endDate: rec ? dateOf(state, rec.endTick) : undefined, infoRequests: rec?.infoRequests ?? 0,
    };
  });
  const findings = p.findings.map((f) => {
    const d = ctx.data.findings[f.id];
    return { id: f.id, nombre: d.nombre, descripcion: d.descripcion, status: f.status, mitigable: d.mitigable, costUsd: findingCostUsd(d, p.mw), successProbability: d.prob_exito_mitigacion ?? 0.5, endDate: f.endTick ? dateOf(state, f.endTick) : undefined };
  });

  const ppaChannels = c.ppa.canales.map((ch) => {
    let reason: string | undefined;
    if (p.mw < ch.mw_min || p.mw > ch.mw_max) reason = `Solo entre ${ch.mw_min} y ${ch.mw_max} MW.`;
    else if (p.ppa && (p.ppa.status === 'firmado' || p.ppa.status === 'en_proceso')) reason = 'Ya hay un PPA firmado o en proceso.';
    else for (const g of ch.requiere_permisos) if (applicablePermits(ctx, p).some((x) => x.grupo === g) && !Object.values(p.permits).some((r) => r.status === 'aprobado' && c.permisos.find((x) => x.id === r.permitId)?.grupo === g)) reason = 'Faltan permisos previos.';
    return {
      id: ch.id, nombre: ch.nombre, descripcion: ch.descripcion,
      priceUsdMwh: { min: ch.precio_usd_mwh.min ?? ch.precio_usd_mwh.base, base: ch.precio_usd_mwh.base, max: ch.precio_usd_mwh.max ?? ch.precio_usd_mwh.base },
      years: ch.plazo_anos, probability: ch.prob_exito, costUsd: ch.costo_usd.base, available: !reason, reason,
    };
  });
  const fb = financingBlockers(ctx, p);
  const lenders = c.finanzas.prestamistas.map((l) => {
    let reason: string | undefined;
    if (l.requiere_ppa && p.ppa?.status !== 'firmado') reason = 'Exige PPA firmado.';
    else if (p.estimate.sigma > l.sigma_recurso_max + 1e-9) reason = `Exige medición de recurso con incertidumbre ≤ ${(l.sigma_recurso_max * 100).toFixed(1)} %.`;
    else if (fb.length) reason = fb[0];
    return {
      id: l.id, nombre: l.nombre, descripcion: l.descripcion, ratePct: (c.finanzas.tasa_libre_riesgo.base + l.spread.base) * 100,
      tenorYears: l.plazo_anos, maxLeverage: l.apalancamiento_max, dscr: p.ppa?.status === 'firmado' ? l.dscr_ppa : l.dscr_merchant,
      requiresPpa: l.requiere_ppa, maxSigma: l.sigma_recurso_max, available: !reason, reason,
    };
  });
  const supp = Object.values(ctx.data.suppliers).filter((s) => s.tecnologias.includes(p.techId)).map<SupplierOption & { tipo: string }>((s) => ({
    id: s.id, nombre: s.nombre, origen: s.origen, descripcion: s.descripcion, priceFactor: supplierPriceFactor(state, ctx, s.id), basePriceFactor: s.factor_precio,
    quality: s.calidad, reliability: supplierReliability(state, ctx, s.id),
    leadDays: s.plazo_entrega_dias ? Math.round(s.plazo_entrega_dias.base * supplierLeadFactor(state, ctx, s.id)) : undefined, scheduleFactor: s.factor_plazo, overrunProb: s.prob_sobrecosto_hito, tipo: s.tipo,
  }));

  const k = p.construction;
  const capex = projectCapex(ctx, p, state);
  const rem = remainingDevCostUsd(ctx, p);
  const consRemaining = p.operation || !active ? 0 : k ? Math.max(0, k.budgetUsd + k.overrunUsd - k.spentUsd) : (p.financing?.status === 'cerrado' ? p.financing.budgetUsd : capex.totalUsd);
  const incurredCons = k?.spentUsd ?? 0;
  const op = p.operation;
  let actualFc: number | null = null;
  if (op && op.history.length) {
    const last = op.history.slice(-12);
    const hours = last.length * 730;
    actualFc = last.reduce((a, h) => a + h.energyMwh, 0) / (p.mw * hours);
  }
  // Energía de este año: P50/P90 de la estimación, con degradación si ya opera.
  const yearNow = dateOf(state, state.tick).year;
  const degr = p.operation ? Math.pow(1 - tech.degradacion_anual.base, (state.tick - p.operation.codTick) / 365.25) : 1;
  const monthly = expectedMonthlyProduction(ctx, p, (eco?.energyP50MwhYear ?? 0) * degr, (eco?.energyP90MwhYear ?? 0) * degr, yearNow);
  const fcBlockers = [...fb, ...(p.suppliers ? [] : ['Elegir proveedores.'])];
  const csBlockers: string[] = [];
  if (p.financing?.status !== 'cerrado') csBlockers.push('Falta el cierre financiero.');
  if (openFindings(p).length) csBlockers.push('Hay hallazgos sin resolver.');
  if (k) csBlockers.push('La obra ya empezó.');

  return {
    summary, techName: tech.nombre, countryName: c.nombre, countryCode: p.countryCode,
    site: { lat: p.site.lat, lon: p.site.lon, layer: p.site.layer, cellValue: p.site.cellValue, temperatureC: p.site.temperatureC },
    resource: {
      p50: p.estimate.value, p90: p90(p.estimate.value, p.estimate.sigma), sigma: p.estimate.sigma, source: p.estimate.source,
      fcP50: eco?.fcP50 ?? 0, fcP90: eco?.fcP90 ?? 0, energyP50MwhYear: eco?.energyP50MwhYear ?? 0, energyP90MwhYear: eco?.energyP90MwhYear ?? 0,
      monthlyMwh: monthly,
    },
    timeline, studies, permits, findings,
    ppa: p.ppa ? { ...p.ppa, channelName: c.ppa.canales.find((x) => x.id === p.ppa!.channelId)?.nombre
      ?? (() => { const k = state.business?.contracts.find((x) => x.id === p.contractId); return k ? `Contrato ${k.id}: ${k.clientName}` : undefined; })() } : null,
    ppaChannels, lenders,
    suppliers: {
      equipment: supp.filter((s) => s.tipo === 'equipos'), epc: supp.filter((s) => s.tipo === 'epc'),
      inverters: supp.filter((s) => s.tipo === 'inversores'), logistics: supp.filter((s) => s.tipo === 'logistica'), selected: p.suppliers,
    },
    contractId: p.contractId,
    financing: p.financing ?? null,
    construction: k ? { ...k, startDate: dateOf(state, k.startTick), expectedEndDate: dateOf(state, k.startTick + Math.round(k.plannedDays + k.delayDays)) } : null,
    operation: op ? (() => { const { fcReal: _hidden, ...rest } = op; void _hidden; return {
      ...rest, codDate: dateOf(state, op.codTick), actualFcLast12m: actualFc, expectedMonthlyMwh: monthly,
      failureLog: (op.failures ?? []).map((f) => ({ date: dateOf(state, f.tick), fractionLost: f.fraction, days: f.days, costUsd: f.costUsd })),
    }; })() : null,
    debt: p.debt ?? null,
    costs: {
      incurredUsd: { development: p.devCostUsd, landOptions: p.devExpenseUsd, construction: incurredCons, idc: k?.idcUsd ?? 0, total: p.devCostUsd + p.devExpenseUsd + incurredCons + (k?.idcUsd ?? 0) },
      upcomingUsd: { studies: rem.studiesUsd, permits: rem.permitsUsd, financing: rem.financingUsd, construction: consRemaining, total: rem.totalUsd + consRemaining },
      capex,
    },
    economics: eco,
    successProbability: active ? successProbability(ctx, p) : 0,
    saleValueUsd: active ? saleValueUsd(state, ctx, p) * (1 - p.partnerShare) : 0,
    risks: tech.riesgos,
    canFinance: { ok: fcBlockers.length === 0 && !(p.financing && p.financing.status !== 'fallido'), blockers: fcBlockers },
    canStartConstruction: { ok: csBlockers.length === 0, blockers: csBlockers },
  };
}

export interface CompanyFinancials {
  cashUsd: number;
  balance: BalanceSheet;
  /** Estados mensuales (los más recientes al final). */
  statements: MonthlyStatement[];
  /** Mes en curso (parcial). */
  currentMonth: Record<string, number>;
  categoryLabels: Record<string, string>;
  last12m: { revenueUsd: number; ebitdaUsd: number; netIncomeUsd: number; operatingCashFlowUsd: number };
  taxLossCarryforwardUsd: number;
  taxCreditUsd: number;
  emergencyDebtUsd: number;
  bankruptcy: { bankrupt: boolean; negativeCashMonths: number; monthsLimit: number; runwayMonths: number | null };
}

export function selectCompanyFinancials(state: GameState, ctx: SimContext): CompanyFinancials {
  const f = state.finance;
  const last = f.statements.slice(-12);
  const sum = (fn: (s: MonthlyStatement) => number) => last.reduce((a, s) => a + fn(s), 0);
  const burn = last.length ? -sum((s) => s.cashFlow.net) / last.length : state.company.monthlyFixedCostUsd;
  const labels: Record<string, string> = {};
  for (const [k, v] of Object.entries(CATEGORIES)) labels[k] = v.label;
  return {
    cashUsd: state.company.cashUsd,
    balance: balanceSheet(state),
    statements: f.statements,
    currentMonth: { ...f.month },
    categoryLabels: labels,
    last12m: { revenueUsd: sum((s) => s.revenueUsd), ebitdaUsd: sum((s) => s.ebitdaUsd), netIncomeUsd: sum((s) => s.netIncomeUsd), operatingCashFlowUsd: sum((s) => s.cashFlow.operating) },
    taxLossCarryforwardUsd: f.taxLossCarryforwardUsd,
    taxCreditUsd: f.taxCreditUsd,
    emergencyDebtUsd: f.emergencyDebtUsd,
    bankruptcy: {
      bankrupt: f.bankrupt, negativeCashMonths: f.negativeCashMonths,
      monthsLimit: ctx.data.countries[state.company.homeCountry]?.quiebra.meses_caja_negativa ?? 3,
      runwayMonths: burn > 0 ? Math.max(0, state.company.cashUsd / burn) : null,
    },
  };
}

export interface SitePreview {
  ok: boolean;
  error?: string;
  techId: string;
  mw: number;
  countryCode?: string;
  cellValue: number;
  sigma: number;
  resourceP90: number;
  fcP50: number;
  fcP90: number;
  energyP50MwhYear: number;
  capexUsd: number;
  prospectingUsd: number;
  landHa: number;
}

/**
 * Vista previa de un sitio antes de crear el proyecto (lo que el jugador sabe: la celda ± σ).
 */
export function previewSite(_state: GameState, ctx: SimContext, techId: string, mw: number, lat: number, lon: number): SitePreview {
  const tech = ctx.data.technologies[techId];
  const blank = { techId, mw, cellValue: 0, sigma: 0, resourceP90: 0, fcP50: 0, fcP90: 0, energyP50MwhYear: 0, capexUsd: 0, prospectingUsd: 0, landHa: 0 };
  if (!tech?.recurso) return { ok: false, error: 'Tecnología desconocida.', ...blank };
  if (!ctx.grid) return { ok: false, error: 'La grilla de recursos no está cargada.', ...blank };
  const cell = ctx.grid.cell(lat, lon);
  const c = cell.country ? ctx.data.countries[cell.country.code] : undefined;
  if (!cell.land || !c) return { ok: false, error: !cell.land ? 'El sitio no está en tierra firme.' : `Todavía no se puede desarrollar en ${cell.country?.nombre}.`, ...blank };
  const v = cell.values[tech.recurso] ?? 0;
  const t = cell.values.temperatura ?? 25;
  const fc50 = capacityFactor(tech, v, t), fc90 = capacityFactor(tech, p90(v, tech.sigma_recurso_sitio), t);
  return {
    ok: true, techId, mw, countryCode: c.iso3, cellValue: v, sigma: tech.sigma_recurso_sitio, resourceP90: p90(v, tech.sigma_recurso_sitio),
    fcP50: fc50, fcP90: fc90, energyP50MwhYear: fc50 * mw * 8760,
    capexUsd: currentCapex(_state, ctx, { techId, mw, countryCode: c.iso3 }).totalUsd, prospectingUsd: c.costos.prospeccion_usd.base,
    landHa: tech.uso_suelo_ha_mw.base * mw,
  };
}

/** Meses transcurridos entre dos ticks (ayuda para la UI). */
export const ticksToMonths = (days: number) => days / DAYS_PER_MONTH;

/** Solo para pruebas y depuración: recurso real de un sitio. La UI NO debe usarlo. */
export function debugRealResource(state: GameState, ctx: SimContext, p: Project): number {
  const tech = ctx.data.technologies[p.techId];
  return p.site.cellValue * hiddenResourceFactor(state.seed, p.site.layer, p.site.lat, p.site.lon, tech.sigma_recurso_sitio);
}

export interface FinancingPreview {
  ok: boolean;
  /** Por qué no se puede pedir hoy (igual que las validaciones de `arrangeFinancing`). */
  blockers: string[];
  lenderId: string;
  lenderName: string;
  budgetUsd: number;
  /** Deuda que el banco elegido dimensionaría hoy (caso del banco: P90, spot con recorte si no hay PPA). */
  debtUsd: number;
  limitedBy: 'apalancamiento' | 'pedido' | 'dscr' | 'sin_deuda';
  requestedDebtUsd: number;
  ratePct: number;
  tenorYears: number;
  dscrTarget: number;
  /** Comisión de estructuración (sobre la deuda) y asesores (se pagan al pedir). */
  structuringFeeUsd: number;
  advisorsUsd: number;
  equityUsd: number;
  partnerShare: number;
  partnerEquityUsd: number;
  ownEquityUsd: number;
  /** Prima de desarrollo que paga el socio al cierre. */
  partnerPremiumUsd: number;
  /** Lo que la empresa debe poner de su caja: aporte propio + asesores + comisión − prima del socio. */
  netOwnCashUsd: number;
  approvalProbability: number;
  dueDiligenceDays: { min: number; base: number; max: number };
  /** Mínimo que presta el banco: si la deuda dimensionada queda debajo, el cierre fracasa. */
  belowLenderMinimum: boolean;
  irrEquity: number | null;
  npvEquityUsd: number;
}

/**
 * Vista previa del financiamiento con un prestamista, fracción de deuda y socio: el mismo dimensionamiento que hará
 * el banco al cerrar (con la información del jugador). `debtFraction = 0` = solo capital propio y del socio.
 */
export function previewFinancing(state: GameState, ctx: SimContext, projectId: string, o: { lenderId: string; debtFraction: number; partnerShare: number }): FinancingPreview | null {
  const p = state.projects.find((x) => x.id === projectId);
  if (!p) return null;
  const c = ctx.data.countries[p.countryCode];
  const l = c.finanzas.prestamistas.find((x) => x.id === o.lenderId);
  const blockers: string[] = [...financingBlockers(ctx, p)];
  if (!p.suppliers) blockers.push('Elige proveedor de equipos y EPC antes de financiar.');
  if (p.financing && p.financing.status !== 'fallido') blockers.push('Ya hay un financiamiento cerrado o en proceso.');
  const se = c.finanzas.socio_equity;
  if (!(o.partnerShare >= 0 && o.partnerShare <= se.participacion_max)) blockers.push(`La participación del socio debe estar entre 0 y ${se.participacion_max * 100} %.`);
  const budget = p.financing?.status === 'cerrado' ? p.financing.budgetUsd : projectCapex(ctx, p, state).totalUsd;
  const noDebt = o.debtFraction === 0 || !l;
  if (!noDebt && l) {
    if (o.debtFraction > l.apalancamiento_max) blockers.push(`${l.nombre} presta como máximo el ${Math.round(l.apalancamiento_max * 100)} % del costo.`);
    if (l.requiere_ppa && p.ppa?.status !== 'firmado') blockers.push(`${l.nombre} exige un PPA firmado.`);
    if (p.estimate.sigma > l.sigma_recurso_max + 1e-9) blockers.push(`${l.nombre} exige una medición de recurso bancable (incertidumbre ≤ ${(l.sigma_recurso_max * 100).toFixed(1)} %).`);
  }
  if (!l && o.debtFraction > 0) blockers.push('Prestamista desconocido.');
  const rate = l ? c.finanzas.tasa_libre_riesgo.base + l.spread.base : 0;
  const dscr = l ? (p.ppa?.status === 'firmado' ? l.dscr_ppa : l.dscr_merchant) : 0;
  let debt = 0;
  let limitedBy: FinancingPreview['limitedBy'] = 'sin_deuda';
  if (!noDebt && l) {
    try {
      const sized = bankDebtSizing(state, ctx, p, { lenderId: l.id, budgetUsd: budget, rate, tenorYears: l.plazo_anos, dscr, requestedFraction: o.debtFraction });
      debt = sized.debtUsd;
      limitedBy = sized.limitedBy;
    } catch { debt = 0; }
  }
  const equity = budget - debt;
  const partnerEquity = equity * o.partnerShare;
  const premium = partnerEquity * se.prima_desarrollo_frac;
  const fee = l && !noDebt ? debt * l.comision_estructuracion : 0;
  const advisors = l && !noDebt ? l.costo_asesores_usd.base : 0;
  const below = !noDebt && !!l && debt < l.monto_min_usd;
  let eco: Economics | null = null;
  try { eco = projectEconomics(state, ctx, p, { capexUsd: budget, lenderId: l?.id, debtFraction: noDebt ? 0 : Math.min(o.debtFraction, debt / Math.max(1, budget)) }); } catch { eco = null; }
  return {
    ok: blockers.length === 0 && !below, blockers, lenderId: l?.id ?? 'ninguno', lenderName: l?.nombre ?? 'Sin deuda', budgetUsd: budget, debtUsd: debt, limitedBy,
    requestedDebtUsd: budget * o.debtFraction, ratePct: rate * 100, tenorYears: l?.plazo_anos ?? 0, dscrTarget: dscr, structuringFeeUsd: fee, advisorsUsd: advisors,
    equityUsd: equity, partnerShare: o.partnerShare, partnerEquityUsd: partnerEquity, ownEquityUsd: equity - partnerEquity, partnerPremiumUsd: premium,
    netOwnCashUsd: equity - partnerEquity + fee + advisors - premium, approvalProbability: noDebt ? 1 : l?.prob_aprobacion ?? 0,
    dueDiligenceDays: l && !noDebt ? { min: l.diligencia_dias.min ?? l.diligencia_dias.base, base: l.diligencia_dias.base, max: l.diligencia_dias.max ?? l.diligencia_dias.base } : { min: 0, base: 0, max: 0 },
    belowLenderMinimum: below, irrEquity: eco?.model.irrEquity ?? null, npvEquityUsd: eco?.npvEquityUsd ?? 0,
  };
}
