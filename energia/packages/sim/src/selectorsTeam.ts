import type { GameState } from './core/state';
import type { SimContext } from './core/context';
import { fromEpochDay } from './core/calendar';
import type { OfficeLevelId, TeamArea } from './data/types';
import { TEAM_AREAS } from './data/types';
import { balanceSheet } from './finance/company';
import { isTerminal } from './project/helpers';
import { actorView, experienceMw } from './business/actor';
import { hasPresence } from './business/presence';
import { blendedReputation } from './business/bids';
import {
  OFFICE_ORDER, areaScore, buildModifiers, conflictProbMonthly, devCostMult, employeeLoad, employerCostUsd, expFactor, financeModifiers, laborCountry,
  locationFactor, mainArea, marketSalaryUsd, officeCapacity, officeLevel, officeLevelDef, officeMonthlyUsd, officeSetupUsd, omModifiers, permitModifiers,
  ppaModifiers, recruitmentFeeUsd, regionalHqFor, repFactor, repOf, roleDef, severanceUsd, staffBasedIn, studyModifiers,
} from './team/team';
import { hireBlockers, upgradeBlockers } from './team/commands';
import { moraleTarget, quitProbability } from './team/tick';
import type { Employee, RepAxis } from './team/types';

/**
 * Fase 6: vistas del equipo, el mercado laboral, la reputación, las oficinas y el resumen global de la empresa.
 * Todos los efectos se muestran cuantificados (multiplicadores y puntos) con las mismas funciones que usa la simulación.
 */

const AREA_LABELS: Record<TeamArea, string> = {
  permisos: 'Permisos', social: 'Comunidades', recurso: 'Recurso y estudios', obra: 'Obra', finanzas: 'Financiamiento', ofertas: 'Ofertas', mercado: 'Mercado', operacion: 'Operación',
};
export const TEAM_AREA_LABELS = AREA_LABELS;

const pct = (m: number) => `${m >= 1 ? '+' : '−'}${Math.abs((m - 1) * 100).toFixed(1)} %`;

export interface EffectLine { id: string; label: string; multiplier: number; text: string }

/** Efectos cuantificados de una ganancia `g` (0–1) en un área (mismas k de team.yaml que la simulación). */
export function areaEffectLines(ctx: SimContext, area: TeamArea, g: number): EffectLine[] {
  const t = ctx.data.team;
  if (!t) return [];
  const k = (id: string) => t.efectos[id]?.base ?? 0;
  const line = (id: string, label: string, sign: 1 | -1): EffectLine => { const m = 1 + sign * k(id) * g; return { id, label, multiplier: m, text: `${label} ${pct(m)}` }; };
  switch (area) {
    case 'permisos': return [line('permisos_aprobacion', 'Aprobación', 1), line('permisos_rechazo', 'Rechazos', -1), line('permisos_info', 'Pedidos de información', -1), line('permisos_tiempo', 'Plazo', -1)];
    case 'social': return [line('social_aprobacion', 'Aprobación de consultas', 1), line('social_conflicto', 'Conflictos en obra', -1)];
    case 'recurso': return [line('recurso_bloqueo', 'Hallazgos bloqueantes', -1), line('recurso_peor', 'Sorpresas de CAPEX', -1), line('recurso_sigma', 'Incertidumbre de la medición', -1), line('recurso_pozo_seco', 'Pozos secos', -1)];
    case 'obra': return [line('obra_sobrecosto_prob', 'Probabilidad de sobrecosto', -1), line('obra_sobrecosto_magnitud', 'Tamaño del sobrecosto', -1), line('obra_paros', 'Paros técnicos', -1), line('obra_accidentes', 'Accidentes', -1)];
    case 'finanzas': return [line('finanzas_spread', 'Spread de la deuda', -1), line('finanzas_costos', 'Asesores', -1), line('finanzas_plazo', 'Due diligence', -1)];
    case 'ofertas': {
      const pts = k('ofertas_puntaje') * g;
      return [{ id: 'ofertas_puntaje', label: 'Puntaje técnico', multiplier: 1, text: `Puntaje técnico +${pts.toFixed(1)} pts` }, line('ofertas_preparacion', 'Costo de preparación', -1), line('mercado_ppa_exito', 'Éxito al buscar PPA', 1)];
    }
    case 'mercado': return [line('mercado_ppa_precio', 'Precio del PPA', 1)];
    case 'operacion': return [line('operacion_fallas', 'Fallas', -1), line('operacion_reparacion', 'Costo de reparación', -1)];
  }
}

// ───────────────────────── Mercado laboral ─────────────────────────

export interface CandidateView {
  id: string; name: string; role: string; roleName: string; countryCode: string; countryName: string; skill: number; experienceYears: number; languages: string[];
  askUsdMonth: number; employerCostUsdMonth: number; marketUsdMonth: number; recruitmentFeeUsd: number; expiresInDays: number;
  /** Áreas en las que aporta (peso del rol) y la habilidad efectiva (con experiencia). */
  areas: { area: TeamArea; label: string; weight: number; effectiveSkill: number }[];
  /** Mejora del puntaje de la empresa en su área principal si se contrata hoy (sin asignación, en la oficina). */
  impact: { area: TeamArea; scoreNow: number; scoreWith: number; effects: EffectLine[] };
  canHire: boolean; blockers: string[];
}

export function selectLaborMarket(state: GameState, ctx: SimContext, o: { countryCode?: string } = {}): { countries: { code: string; name: string; officeLevel?: OfficeLevelId; capacity: number; staff: number; candidates: number }[]; candidates: CandidateView[] } {
  const t = ctx.data.team;
  const lab = state.market.labor;
  if (!t || !lab) return { countries: [], candidates: [] };
  const countries = Object.keys(lab.candidates).sort().map((iso) => ({ code: iso, name: ctx.data.countries[iso]?.nombre ?? iso, officeLevel: officeLevel(state, iso), capacity: officeCapacity(ctx, officeLevel(state, iso)), staff: staffBasedIn(state, iso), candidates: lab.candidates[iso].filter((c) => c.expiresTick > state.tick).length }));
  const out: CandidateView[] = [];
  for (const [iso, list] of Object.entries(lab.candidates)) {
    if (o.countryCode && iso !== o.countryCode) continue;
    for (const c of list) {
      if (c.expiresTick <= state.tick) continue;
      const r = roleDef(ctx, c.role);
      if (!r) continue;
      const area = mainArea(r);
      const now = areaScore(state, ctx, area, { countryCode: state.company.homeCountry });
      // Simulación sobre una copia superficial: el candidato en la oficina.
      const tmp: Employee = { ...c, salaryUsdMonth: c.askUsdMonth, morale: 60, hiredTick: state.tick, assignment: [], trainings: 0 };
      const view = { ...state, business: { ...state.business, team: { ...(state.business.team ?? { hires: 0, quits: 0, fired: 0, history: [] }), employees: [...(state.business.team?.employees ?? []), tmp] } } } as GameState;
      const withC = areaScore(view, ctx, area, { countryCode: state.company.homeCountry });
      const blockers = hireBlockers(state, ctx, iso, c.askUsdMonth);
      out.push({
        id: c.id, name: c.name, role: c.role, roleName: r.nombre, countryCode: iso, countryName: ctx.data.countries[iso]?.nombre ?? iso, skill: c.skill, experienceYears: Math.round(c.experienceYears), languages: c.languages,
        askUsdMonth: c.askUsdMonth, employerCostUsdMonth: employerCostUsd(ctx, { countryCode: iso, salaryUsdMonth: c.askUsdMonth }), marketUsdMonth: marketSalaryUsd(state, ctx, c),
        recruitmentFeeUsd: recruitmentFeeUsd(ctx, c.askUsdMonth), expiresInDays: c.expiresTick - state.tick,
        areas: TEAM_AREAS.filter((a) => (r.areas[a] ?? 0) > 0).map((a) => ({ area: a, label: AREA_LABELS[a], weight: r.areas[a]!, effectiveSkill: c.skill * expFactor(ctx, c.experienceYears) * r.areas[a]! })),
        impact: { area, scoreNow: now.score, scoreWith: withC.score, effects: areaEffectLines(ctx, area, withC.gain) },
        canHire: blockers.length === 0, blockers,
      });
    }
  }
  out.sort((a, b) => a.countryCode.localeCompare(b.countryCode) || a.role.localeCompare(b.role) || b.skill - a.skill);
  return { countries, candidates: out };
}

// ───────────────────────── Equipo ─────────────────────────

export interface EmployeeView {
  id: string; name: string; role: string; roleName: string; countryCode: string; skill: number; effectiveSkill: number; experienceYears: number; languages: string[];
  salaryUsdMonth: number; employerCostUsdMonth: number; marketUsdMonth: number; payRatio: number; morale: number; moraleTarget: number; quitRiskMonthly: number;
  load: number; capacity: number; dilution: number; overloaded: boolean;
  assignment: { kind: 'oficina' } | { kind: 'proyectos'; projects: { id: string; name: string }[] };
  training: { active: boolean; daysLeft: number }; trainings: number; hiredDate: string; severanceUsd: number;
  /** Aporte por área: puntaje con el que contribuye y los efectos sobre los proyectos que atiende. */
  areas: { area: TeamArea; label: string; weight: number; contribution: number }[];
  /** Por proyecto atendido: puntaje del área principal con y sin esta persona. */
  perProject: { projectId: string; name: string; area: TeamArea; scoreWith: number; scoreWithout: number }[];
}

export interface TeamOverview {
  headcount: number; monthlyCostUsd: number; avgMorale: number; hires: number; quits: number; fired: number;
  employees: EmployeeView[];
  /** Puntaje de la empresa por área (en la oficina del país de origen) con sus efectos. */
  areas: { area: TeamArea; label: string; score: number; gain: number; external: number; effects: EffectLine[]; people: number }[];
  history: { year: number; month: number; headcount: number; costUsd: number; avgMorale: number }[];
  externalScore: number;
}

export function selectTeam(state: GameState, ctx: SimContext): TeamOverview {
  const t = ctx.data.team;
  const team = state.business.team;
  const ext = t?.puntaje_externo.base ?? 35;
  if (!t || !team) return { headcount: 0, monthlyCostUsd: 0, avgMorale: 0, hires: 0, quits: 0, fired: 0, employees: [], areas: [], history: [], externalScore: ext };
  const home = state.company.homeCountry;
  const without = (id: string) => ({ ...state, business: { ...state.business, team: { ...team, employees: team.employees.filter((e) => e.id !== id) } } } as GameState);
  const employees = team.employees.map((e): EmployeeView => {
    const r = roleDef(ctx, e.role)!;
    const area = mainArea(r);
    const load = employeeLoad(state, ctx, e);
    const m = marketSalaryUsd(state, ctx, e);
    const served = (e.assignment.length ? e.assignment : state.projects.filter((p) => !isTerminal(p)).map((p) => p.id)).map((id) => state.projects.find((p) => p.id === id)).filter((p): p is NonNullable<typeof p> => !!p && !isTerminal(p));
    const wo = without(e.id);
    return {
      id: e.id, name: e.name, role: e.role, roleName: r.nombre, countryCode: e.countryCode, skill: e.skill, effectiveSkill: e.skill * expFactor(ctx, e.experienceYears),
      experienceYears: Math.round(e.experienceYears * 10) / 10, languages: e.languages, salaryUsdMonth: e.salaryUsdMonth, employerCostUsdMonth: employerCostUsd(ctx, e),
      marketUsdMonth: m, payRatio: e.salaryUsdMonth / Math.max(1, m), morale: e.morale, moraleTarget: moraleTarget(state, ctx, e), quitRiskMonthly: quitProbability(ctx, e.morale),
      load, capacity: r.capacidad, dilution: Math.min(1, r.capacidad / Math.max(1, load)), overloaded: load > r.capacidad,
      assignment: e.assignment.length ? { kind: 'proyectos', projects: e.assignment.map((id) => ({ id, name: state.projects.find((p) => p.id === id)?.name ?? id })) } : { kind: 'oficina' },
      training: { active: e.trainingUntilTick !== undefined && state.tick < e.trainingUntilTick, daysLeft: Math.max(0, (e.trainingUntilTick ?? 0) - state.tick) }, trainings: e.trainings,
      hiredDate: dateStr(state, e.hiredTick), severanceUsd: severanceUsd(state, ctx, e),
      areas: TEAM_AREAS.filter((a) => (r.areas[a] ?? 0) > 0).map((a) => ({ area: a, label: AREA_LABELS[a], weight: r.areas[a]!, contribution: e.skill * expFactor(ctx, e.experienceYears) * r.areas[a]! * locationFactor(state, ctx, e, home) })),
      perProject: served.slice(0, 12).map((p) => ({ projectId: p.id, name: p.name, area, scoreWith: areaScore(state, ctx, area, { projectId: p.id }).score, scoreWithout: areaScore(wo, ctx, area, { projectId: p.id }).score })),
    };
  });
  const areas = TEAM_AREAS.map((a) => {
    const sc = areaScore(state, ctx, a, { countryCode: home });
    return { area: a, label: AREA_LABELS[a], score: sc.score, gain: sc.gain, external: sc.external, effects: areaEffectLines(ctx, a, sc.gain), people: sc.contributors.length };
  });
  const cost = team.employees.reduce((s, e) => s + employerCostUsd(ctx, e), 0);
  return {
    headcount: team.employees.length, monthlyCostUsd: cost, avgMorale: team.employees.length ? team.employees.reduce((s, e) => s + e.morale, 0) / team.employees.length : 0,
    hires: team.hires, quits: team.quits, fired: team.fired, employees, areas, history: team.history, externalScore: ext,
  };
}

/** Equipo de un proyecto: puntaje por área, quién aporta (con carga y dilución) y los multiplicadores que se aplican hoy. */
export function selectProjectTeam(state: GameState, ctx: SimContext, projectId: string) {
  const p = state.projects.find((x) => x.id === projectId);
  if (!p || !ctx.data.team) return undefined;
  const areas = TEAM_AREAS.filter((a) => a !== 'ofertas').map((a) => {
    const sc = areaScore(state, ctx, a, { projectId });
    return { area: a, label: AREA_LABELS[a], score: sc.score, gain: sc.gain, contributors: sc.contributors.map((c) => ({ ...c, roleName: roleDef(ctx, c.role)?.nombre ?? c.role })), effects: areaEffectLines(ctx, a, sc.gain) };
  });
  const c = ctx.data.countries[p.countryCode];
  const permits = (c?.permisos ?? []).map((d) => ({ id: d.id, nombre: d.nombre, ...permitModifiers(state, ctx, p, d) }));
  const lender = c?.finanzas.prestamistas.map((l) => ({ id: l.id, nombre: l.nombre, ...financeModifiers(state, ctx, p, l.tipo) })) ?? [];
  return {
    projectId, name: p.name, countryCode: p.countryCode, areas,
    applied: {
      permits, study: studyModifiers(state, ctx, p), build: buildModifiers(state, ctx, p), finance: lender, ppa: ppaModifiers(state, ctx, p), om: omModifiers(state, ctx, p),
      devCostMult: devCostMult(state, ctx, p.countryCode), conflictProbMonthly: p.construction && !p.operation ? conflictProbMonthly(state, ctx, p) : 0,
    },
    assigned: (state.business.team?.employees ?? []).filter((e) => e.assignment.includes(projectId)).map((e) => ({ id: e.id, name: e.name, role: e.role })),
  };
}

/** Carga de trabajo: por persona (carga/capacidad) y por proyecto (quién lo atiende). */
export function selectWorkload(state: GameState, ctx: SimContext) {
  const emps = state.business.team?.employees ?? [];
  const people = emps.map((e) => { const r = roleDef(ctx, e.role); const load = employeeLoad(state, ctx, e); return { id: e.id, name: e.name, role: e.role, load, capacity: r?.capacidad ?? 1, overloaded: load > (r?.capacidad ?? 1), office: e.assignment.length === 0 }; });
  const projects = state.projects.filter((p) => !isTerminal(p)).map((p) => ({
    projectId: p.id, name: p.name, stage: p.stage,
    dedicated: emps.filter((e) => e.assignment.includes(p.id)).map((e) => e.id),
    office: emps.filter((e) => !e.assignment.length).map((e) => e.id),
    scores: Object.fromEntries(TEAM_AREAS.map((a) => [a, areaScore(state, ctx, a, { projectId: p.id }).score])) as Record<TeamArea, number>,
  }));
  return { people, projects, overloadedCount: people.filter((x) => x.overloaded).length };
}

// ───────────────────────── Reputación ─────────────────────────

export function selectReputation(state: GameState, ctx: SimContext) {
  const t = ctx.data.team;
  const b = state.business;
  const isos = [...new Set([state.company.homeCountry, ...Object.keys(b.rep?.gobierno ?? {}), ...Object.keys(b.rep?.comunidad ?? {})])].sort();
  const countries = isos.map((iso) => {
    const gov = repOf(state, ctx, 'gobierno', iso), com = repOf(state, ctx, 'comunidad', iso);
    return {
      code: iso, name: ctx.data.countries[iso]?.nombre ?? iso, gobierno: gov, comunidad: com,
      effects: t ? {
        socialPermitApproval: repFactor(com, t.reputacion.efectos.social_aprobacion.base),
        conflictFactor: 2 - repFactor(com, t.reputacion.efectos.conflicto.base),
        developmentBankSpread: 2 - repFactor(gov, t.reputacion.efectos.banca_desarrollo_spread.base),
        publicTenderReputation: blendedReputation(state, { countryCode: iso, kind: 'licitacion_publica' }, ctx),
        privateTenderReputation: blendedReputation(state, { countryCode: iso, kind: 'solicitud_privada' }, ctx),
        invitationProbMonthly: invitationProb(state, ctx, iso),
      } : undefined,
    };
  });
  const recent = [...(b.rep?.log ?? [])].reverse().slice(0, 30).map((e) => ({ ...e, date: dateStr(state, e.tick), countryName: e.countryCode ? ctx.data.countries[e.countryCode]?.nombre ?? e.countryCode : undefined }));
  return { clientes: b.reputation, countries, recent, history: b.rep?.history ?? [] };
}

export function invitationProb(state: GameState, ctx: SimContext, iso: string): number {
  const t = ctx.data.team;
  const lvl = officeLevel(state, iso);
  if (!t || !lvl || !officeLevelDef(ctx, lvl)?.invitaciones_privadas) return 0;
  const rep = 0.7 * state.business.reputation + 0.3 * repOf(state, ctx, 'gobierno', iso);
  return rep > 50 ? t.reputacion.efectos.invitacion_prob_mes.base * (rep - 50) / 50 : 0;
}

// ───────────────────────── Oficinas ─────────────────────────

export function selectOffices(state: GameState, ctx: SimContext) {
  const t = ctx.data.team;
  if (!t) return [];
  const isos = [...new Set([state.company.homeCountry, ...Object.keys(state.business.presence ?? {}).filter((i) => state.business.presence![i].status !== 'cerrada')])].sort();
  return isos.map((iso) => {
    const lvl = officeLevel(state, iso);
    const d = lvl ? officeLevelDef(ctx, lvl) : undefined;
    const o = state.business.offices?.[iso];
    const next = lvl ? OFFICE_ORDER[OFFICE_ORDER.indexOf(lvl) + 1] : undefined;
    const nd = next ? officeLevelDef(ctx, next) : undefined;
    const prev = lvl ? OFFICE_ORDER[OFFICE_ORDER.indexOf(lvl) - 1] : undefined;
    return {
      code: iso, name: ctx.data.countries[iso]?.nombre ?? iso, home: iso === state.company.homeCountry, presence: hasPresence(state, iso), level: lvl, levelName: d?.nombre,
      staff: staffBasedIn(state, iso), capacity: officeCapacity(ctx, lvl), monthlyCostUsd: lvl ? officeMonthlyUsd(state, ctx, iso, lvl) + (iso !== state.company.homeCountry ? state.business.presence?.[iso]?.monthlyCostUsd ?? 0 : 0) : 0,
      effects: { devCostMult: devCostMult(state, ctx, iso), governmentRepPerMonth: d?.reputacion_gobierno_mes ?? 0, privateInvitations: !!d?.invitaciones_privadas, regionalHq: regionalHqFor(state, ctx, iso) ?? null, invitationProbMonthly: invitationProb(state, ctx, iso) },
      upgrading: o?.upgradeTo ? { to: o.upgradeTo, daysLeft: Math.max(0, (o.readyTick ?? 0) - state.tick) } : null,
      upgrade: next && nd ? { to: next, name: nd.nombre, setupUsd: officeSetupUsd(ctx, iso, next), monthlyUsd: officeMonthlyUsd(state, ctx, iso, next), days: nd.dias, capacity: nd.capacidad_personal,
        devCostMult: devCostMult({ ...state, business: { ...state.business, offices: { ...state.business.offices, [iso]: { level: next, sinceTick: state.tick } } } } as GameState, ctx, iso),
        blockers: upgradeBlockers(state, ctx, iso) } : null,
      downgrade: prev && !(iso === state.company.homeCountry && prev === 'representante') ? { to: prev, capacity: officeCapacity(ctx, prev), ok: staffBasedIn(state, iso) <= officeCapacity(ctx, prev) } : null,
      labor: laborCountry(ctx, iso) ? { language: laborCountry(ctx, iso)!.idioma, salaryUsd: laborCountry(ctx, iso)!.salario_usd, socialCharges: laborCountry(ctx, iso)!.cargas } : null,
    };
  });
}

// ───────────────────────── Resumen global de la empresa ─────────────────────────

export function selectCompanyOverview(state: GameState, ctx: SimContext) {
  const mwBy = (ps: GameState['projects'], pred: (p: GameState['projects'][number]) => boolean) => {
    const m: Record<string, number> = {};
    for (const p of ps) if (!isTerminal(p) && pred(p)) m[p.techId] = (m[p.techId] ?? 0) + p.mw;
    return m;
  };
  const bs = balanceSheet(state);
  const countries = [...new Set([state.company.homeCountry, ...Object.keys(state.business.presence ?? {}).filter((i) => hasPresence(state, i)), ...state.projects.filter((p) => !isTerminal(p)).map((p) => p.countryCode)])].sort();
  const me = {
    id: 'jugador', name: state.company.name, equityUsd: bs.equityUsd, cashUsd: bs.cashUsd, debtUsd: bs.debtUsd,
    operatingMw: state.projects.filter((p) => p.operation && !isTerminal(p)).reduce((a, p) => a + p.mw, 0), countries: countries.length, reputation: state.business.reputation, bankrupt: state.finance.bankrupt,
  };
  const rivals = state.competitors.map((c) => {
    const v = actorView(state, c);
    const b = balanceSheet(v);
    return { id: c.id, name: c.name, equityUsd: b.equityUsd, cashUsd: b.cashUsd, debtUsd: b.debtUsd, operatingMw: c.projects.filter((p) => p.operation && !isTerminal(p)).reduce((a, p) => a + p.mw, 0),
      countries: new Set([c.company.homeCountry, ...Object.keys(c.business.presence ?? {}).filter((i) => c.business.presence![i].status === 'activa')]).size, reputation: c.business.reputation, bankrupt: c.status === 'quebrada' };
  });
  const all = [me, ...rivals];
  const rank = (key: 'equityUsd' | 'operatingMw') => [...all].sort((a, b) => b[key] - a[key]).findIndex((x) => x.id === 'jugador') + 1;
  return {
    countries: countries.map((iso) => ({ code: iso, name: ctx.data.countries[iso]?.nombre ?? iso, office: officeLevel(state, iso) ?? null, projects: state.projects.filter((p) => !isTerminal(p) && p.countryCode === iso).length,
      operatingMw: state.projects.filter((p) => p.operation && !isTerminal(p) && p.countryCode === iso).reduce((a, p) => a + p.mw, 0) })),
    mwByTech: { operating: mwBy(state.projects, (p) => !!p.operation), construction: mwBy(state.projects, (p) => !!p.construction && !p.operation), development: mwBy(state.projects, (p) => !p.construction && !p.operation) },
    balance: bs, experienceMw: experienceMw(state), headcount: state.business.team?.employees.length ?? 0,
    ranking: { byEquity: rank('equityUsd'), byOperatingMw: rank('operatingMw'), of: all.length, table: all.sort((a, b) => b.equityUsd - a.equityUsd) },
  };
}

function dateStr(state: GameState, tick: number): string {
  const d = fromEpochDay(state.startEpochDay + tick);
  return `${d.year}-${String(d.month).padStart(2, '0')}-${String(d.day).padStart(2, '0')}`;
}

export type { RepAxis };

