import type { GameState } from '../core/state';
import type { SimContext } from '../core/context';
import type { SimEvent } from '../core/events';
import { Rng, seedStream } from '../core/rng';
import type { Dist, OfficeLevelDef, OfficeLevelId, PermitDef, TeamArea, TeamDef, TeamMemberSeed, TeamRoleDef } from '../data/types';
import { TEAM_AREAS } from '../data/types';
import { drawDist } from '../project/outcomes';
import { isTerminal } from '../project/helpers';
import type { Project } from '../project/types';
import { actorIdOf } from '../business/actor';
import { PLAYER_ID } from '../business/types';
import type { Candidate, Employee, OfficeState, Person, RepAxis, ReputationState, TeamState } from './types';

/**
 * Fase 6: equipo, reputación por eje y oficinas. Funciones puras sobre el estado del actor (jugador o vista de un
 * competidor): la IA usa exactamente las mismas. Fórmulas documentadas en docs/MOTOR_FASE6.md.
 */

export const OFFICE_ORDER: OfficeLevelId[] = ['representante', 'oficina', 'sede'];
const YEAR_DAYS = 365.25;

// ───────────────────────── Datos ─────────────────────────

export function roleDef(ctx: SimContext, role: string): TeamRoleDef | undefined {
  return ctx.data.team?.roles.find((r) => r.id === role);
}

export function laborCountry(ctx: SimContext, iso: string) {
  return ctx.data.team?.paises[iso];
}

export function officeLevelDef(ctx: SimContext, level: OfficeLevelId): OfficeLevelDef | undefined {
  return ctx.data.team?.oficinas.niveles.find((l) => l.id === level);
}

const k = (t: TeamDef, id: string) => t.efectos[id]?.base ?? 0;

// ───────────────────────── Salarios ─────────────────────────

/** Factor de nivel: 1 con habilidad 50 y 8 años de experiencia. */
export function levelFactor(skill: number, years: number): number {
  const lf = (0.45 + 1.1 * Math.pow(Math.max(0, Math.min(100, skill)) / 100, 1.5)) / (0.45 + 1.1 * Math.pow(0.5, 1.5));
  const ef = (0.8 + 0.4 * Math.min(1, years / 20)) / (0.8 + 0.4 * 0.4);
  return lf * ef;
}

/** Salario bruto mensual de mercado (USD de hoy) de una persona: país × rol × nivel × inflación del USD del país. */
export function marketSalaryUsd(state: Pick<GameState, 'tick'>, ctx: SimContext, p: Pick<Person, 'countryCode' | 'role' | 'skill' | 'experienceYears'>): number {
  const lc = laborCountry(ctx, p.countryCode);
  const r = roleDef(ctx, p.role);
  if (!lc || !r) return 0;
  const infl = Math.pow(1 + (ctx.data.countries[p.countryCode]?.inflacion_usd_anual ?? 0.025), state.tick / YEAR_DAYS);
  return lc.salario_usd * r.factor_salario * levelFactor(p.skill, p.experienceYears) * infl;
}

/** Costo mensual para la empresa (salario + cargas sociales del país). */
export function employerCostUsd(ctx: SimContext, e: Pick<Employee, 'countryCode' | 'salaryUsdMonth'>): number {
  return e.salaryUsdMonth * (1 + (laborCountry(ctx, e.countryCode)?.cargas ?? 0.25));
}

export function recruitmentFeeUsd(ctx: SimContext, salaryUsdMonth: number): number {
  return 12 * salaryUsdMonth * (ctx.data.team?.mercado_laboral.reclutamiento_frac_anual.base ?? 0.2);
}

/** Indemnización por despido sin causa según el país (meses de salario por año en la empresa, con mínimo y tope). */
export function severanceUsd(state: Pick<GameState, 'tick'>, ctx: SimContext, e: Employee): number {
  const lc = laborCountry(ctx, e.countryCode);
  if (!lc) return e.salaryUsdMonth;
  const years = Math.max(0, (state.tick - e.hiredTick) / YEAR_DAYS);
  const months = Math.min(lc.indemnizacion_max_meses, Math.max(lc.indemnizacion_min_meses, lc.indemnizacion_meses_ano * years));
  return months * e.salaryUsdMonth;
}

// ───────────────────────── Oficinas ─────────────────────────

/** Nivel de oficina del actor en un país (undefined = sin presencia). El país de origen arranca con oficina local. */
export function officeLevel(state: Pick<GameState, 'business' | 'company'>, iso: string): OfficeLevelId | undefined {
  const o = state.business?.offices?.[iso];
  if (o) return o.level;
  if (iso === state.company.homeCountry) return 'oficina';
  const p = state.business?.presence?.[iso];
  return p?.status === 'activa' ? (p.level ?? 'representante') : undefined;
}

export function staffBasedIn(state: Pick<GameState, 'business'>, iso: string): number {
  return (state.business?.team?.employees ?? []).filter((e) => e.countryCode === iso).length;
}

export function officeCapacity(ctx: SimContext, level: OfficeLevelId | undefined): number {
  if (!level) return 0;
  return officeLevelDef(ctx, level)?.capacidad_personal ?? (level === 'representante' ? 2 : 15);
}

/** Regiones (team.yaml) a las que pertenece un país. */
export function regionsOf(ctx: SimContext, iso: string): string[] {
  return Object.entries(ctx.data.team?.oficinas.regiones ?? {}).filter(([, l]) => l.includes(iso)).map(([id]) => id);
}

/** ¿El actor tiene sede regional en un país de la misma región que `iso` (sin contar `iso`)? */
export function regionalHqFor(state: Pick<GameState, 'business' | 'company'>, ctx: SimContext, iso: string): string | undefined {
  const regs = ctx.data.team?.oficinas.regiones ?? {};
  for (const r of regionsOf(ctx, iso)) for (const other of regs[r]) if (other !== iso && officeLevel(state, other) === 'sede') return other;
  return undefined;
}

/**
 * Multiplicador del costo de estudios y permisos en un país. Los datos suponen un desarrollador CON oficina local
 * (como en el país de origen): sin oficina (solo representante) cuesta (1 + 0)/(1 − 0,05) ≈ +5 %; con sede, −3 %;
 * una sede regional vecina resta además un 3 %.
 */
export function devCostMult(state: Pick<GameState, 'business' | 'company'>, ctx: SimContext, iso: string): number {
  if (!ctx.data.team) return 1;
  const ref = officeLevelDef(ctx, 'oficina')?.costo_desarrollo_frac ?? 0;
  const lvl = officeLevel(state, iso) ?? 'representante';
  let m = (1 + (officeLevelDef(ctx, lvl)?.costo_desarrollo_frac ?? 0)) / (1 + ref);
  if (regionalHqFor(state, ctx, iso)) m *= 1 + (officeLevelDef(ctx, 'sede')?.costo_desarrollo_vecinos_frac ?? 0);
  return m;
}

/** Costo mensual de las oficinas (sobre el representante de la Fase 4); la oficina del país de origen está en los gastos fijos. */
export function officeMonthlyUsd(state: Pick<GameState, 'company' | 'tick'>, ctx: SimContext, iso: string, level: OfficeLevelId): number {
  const d = officeLevelDef(ctx, level);
  if (!d) return 0;
  const idx = laborCountry(ctx, iso)?.oficina_indice ?? 1;
  const home = iso === state.company.homeCountry ? (officeLevelDef(ctx, 'oficina')?.costo_mensual_usd ?? 0) : 0;
  const infl = Math.pow(1 + (ctx.data.countries[iso]?.inflacion_usd_anual ?? 0.025), state.tick / YEAR_DAYS);
  return Math.max(0, d.costo_mensual_usd - home) * idx * infl;
}

export function officeSetupUsd(ctx: SimContext, iso: string, level: OfficeLevelId): number {
  return (officeLevelDef(ctx, level)?.costo_inicial_usd ?? 0) * (laborCountry(ctx, iso)?.oficina_indice ?? 1);
}

// ───────────────────────── Reputación ─────────────────────────

export function newReputationState(): ReputationState {
  return { gobierno: {}, comunidad: {}, log: [], history: [], socialYear: { year: 0, points: {} } };
}

/** Reputación del actor en un eje (0–100). `clientes` es global (= `business.reputation`); gobierno y comunidad, por país. */
export function repOf(state: Pick<GameState, 'business'>, ctx: SimContext, axis: RepAxis, iso?: string): number {
  const b = state.business;
  if (!b) return 0;
  if (axis === 'clientes' || !iso) return b.reputation;
  const v = b.rep?.[axis]?.[iso];
  return v ?? ctx.data.team?.reputacion.inicial_pais_nuevo.base ?? b.reputation;
}

const clamp100 = (v: number) => Math.max(0, Math.min(100, v));
const AXIS_NAME: Record<RepAxis, string> = { gobierno: 'gobierno', comunidad: 'comunidades', clientes: 'clientes' };

/** Cambia la reputación de un eje por una causa (registra la causa; evento solo si el cambio es visible). */
export function changeRep(state: GameState, ctx: SimContext, axis: RepAxis, iso: string | undefined, delta: number, cause: string, text: string, events?: SimEvent[]) {
  const b = state.business;
  if (!b || !delta || !Number.isFinite(delta)) return;
  let before: number, after: number;
  if (axis === 'clientes') { before = b.reputation; b.reputation = clamp100(b.reputation + delta); after = b.reputation; }
  else {
    if (!iso || !ctx.data.team) return;
    b.rep ??= newReputationState();
    before = repOf(state, ctx, axis, iso);
    after = clamp100(before + delta);
    b.rep[axis][iso] = after;
  }
  const d = after - before;
  if (Math.abs(d) < 1e-9) return;
  if (b.rep) {
    b.rep.log.push({ tick: state.tick, axis, countryCode: axis === 'clientes' ? undefined : iso, delta: d, cause, text });
    if (b.rep.log.length > 80) b.rep.log.splice(0, b.rep.log.length - 80);
  }
  if (events && Math.abs(d) >= 1) {
    const where = axis !== 'clientes' && iso ? ` en ${ctx.data.countries[iso]?.nombre ?? iso}` : '';
    events.push({ type: 'reputationChanged', axis, countryCode: axis === 'clientes' ? undefined : iso, delta: d, cause, severity: d > 0 ? 'bueno' : 'malo',
      text: `Reputación con ${AXIS_NAME[axis]}${where} ${d > 0 ? '+' : ''}${d.toFixed(1)} (${text}).` });
  }
}

/** Aplica una causa de team.yaml → reputacion.causas (varios ejes a la vez). */
export function repCause(state: GameState, ctx: SimContext, cause: string, iso: string | undefined, text: string, events?: SimEvent[], scale = 1) {
  const c = ctx.data.team?.reputacion.causas[cause];
  if (!c) return;
  for (const axis of ['gobierno', 'comunidad', 'clientes'] as RepAxis[]) {
    const d = c[axis];
    if (d) changeRep(state, ctx, axis, iso, d * scale, cause, text, events);
  }
}

/** Multiplicador acotado 1 + k·(rep − 50)/50 (rep 50 = neutro). */
export function repFactor(rep: number, kk: number): number {
  return Math.max(1 - kk, Math.min(1 + kk, 1 + kk * (rep - 50) / 50));
}

// ───────────────────────── Equipo: carga y puntaje por área ─────────────────────────

export function employeesOf(state: Pick<GameState, 'business'>): Employee[] {
  return state.business?.team?.employees ?? [];
}

/** ¿El proyecto necesita un área hoy? Desarrollo: permisos/social/recurso/finanzas/mercado; obra; operación. */
export function projectNeedsArea(p: Project, area: TeamArea): boolean {
  if (isTerminal(p)) return false;
  if (area === 'operacion') return !!p.operation;
  if (area === 'obra') return !!p.construction && !p.operation;
  if (area === 'ofertas') return false;
  if (area === 'social') return !p.operation; // también en obra (conflictos)
  return !p.construction && !p.operation;
}

export function mainArea(r: TeamRoleDef): TeamArea {
  let best: TeamArea = 'permisos', w = -1;
  for (const a of TEAM_AREAS) { const v = r.areas[a] ?? 0; if (v > w) { w = v; best = a; } }
  return best;
}

/** Carga de una persona: proyectos asignados activos, o (en la oficina) proyectos de la empresa que necesitan su área principal + ofertas abiertas (comercial). */
export function employeeLoad(state: GameState, ctx: SimContext, e: Employee): number {
  const r = roleDef(ctx, e.role);
  if (!r) return 0;
  const area = mainArea(r);
  if (e.assignment.length) return e.assignment.filter((id) => { const p = state.projects.find((x) => x.id === id); return p && !isTerminal(p); }).length;
  let n = state.projects.filter((p) => projectNeedsArea(p, area)).length;
  if (area === 'ofertas' || (r.areas.ofertas ?? 0) > 0) {
    const me = actorIdOf(state);
    for (const o of state.market?.opportunities ?? []) if (o.status === 'abierta' && o.bids.some((b) => b.actorId === me && b.status === 'presentada')) n += area === 'ofertas' ? 1 : 0;
  }
  return n;
}

export function expFactor(ctx: SimContext, years: number): number {
  return 0.85 + 0.15 * Math.min(1, years / (ctx.data.team?.experiencia_anos_plena ?? 15));
}

/** Factor por ubicación e idioma de una persona frente al país del proyecto. */
export function locationFactor(state: Pick<GameState, 'business' | 'company'>, ctx: SimContext, e: Person, iso: string | undefined): number {
  const t = ctx.data.team;
  if (!t || !iso) return 1;
  const local = t.roles_locales.includes(e.role);
  let f = 1;
  if (iso !== e.countryCode && local) f *= regionalHqFor(state, ctx, iso) || officeLevel(state, iso) === 'sede' ? t.factor_fuera_pais_region.base : t.factor_fuera_pais.base;
  const lang = laborCountry(ctx, iso)?.idioma;
  if (lang && !e.languages.includes(lang)) f *= local ? t.factor_sin_idioma_local.base : t.factor_sin_idioma.base;
  return f;
}

export interface AreaContribution { employeeId: string; name: string; role: string; contribution: number; dilution: number; load: number; capacity: number }
export interface AreaScore { area: TeamArea; score: number; gain: number; external: number; contributors: AreaContribution[] }

/**
 * Puntaje de un área para un proyecto (o para la empresa en un país si no hay proyecto). Cada persona aporta
 * habilidad × experiencia × peso del rol en el área × ubicación/idioma, diluida hacia el consultor externo si su
 * carga supera su capacidad: c = externo + máx(0, aporte − externo) × mín(1, capacidad/carga). Puntaje = externo +
 * Σ pesos_equipo[i] × (c_i − externo) (las mejores primero), tope 100. Ganancia g = (puntaje − externo)/(100 − externo).
 */
export function areaScore(state: GameState, ctx: SimContext, area: TeamArea, target?: { projectId?: string; countryCode?: string }): AreaScore {
  const t = ctx.data.team;
  const ext = t?.puntaje_externo.base ?? 35;
  const out: AreaScore = { area, score: ext, gain: 0, external: ext, contributors: [] };
  if (!t) return out;
  const emps = employeesOf(state);
  if (!emps.length) return out;
  const iso = target?.countryCode ?? (target?.projectId ? state.projects.find((p) => p.id === target.projectId)?.countryCode : undefined);
  const list: AreaContribution[] = [];
  for (const e of emps) {
    if (e.trainingUntilTick !== undefined && state.tick < e.trainingUntilTick) continue;
    const r = roleDef(ctx, e.role);
    const w = r?.areas[area] ?? 0;
    if (!r || w <= 0) continue;
    if (e.assignment.length && (!target?.projectId || !e.assignment.includes(target.projectId))) continue;
    const eff = e.skill * expFactor(ctx, e.experienceYears) * w * locationFactor(state, ctx, e, iso);
    const load = employeeLoad(state, ctx, e);
    const dil = Math.min(1, r.capacidad / Math.max(1, load));
    list.push({ employeeId: e.id, name: e.name, role: e.role, contribution: ext + Math.max(0, eff - ext) * dil, dilution: dil, load, capacity: r.capacidad });
  }
  list.sort((a, b) => b.contribution - a.contribution || a.employeeId.localeCompare(b.employeeId));
  let s = ext;
  list.forEach((c, i) => { s += (t.pesos_equipo[i] ?? 0) * (c.contribution - ext); });
  out.score = Math.min(100, s);
  out.gain = Math.max(0, Math.min(1, (out.score - ext) / (100 - ext)));
  out.contributors = list.filter((c) => c.contribution > ext + 1e-9);
  return out;
}

export const teamGain = (state: GameState, ctx: SimContext, area: TeamArea, target?: { projectId?: string; countryCode?: string }) =>
  ctx.data.team ? areaScore(state, ctx, area, target).gain : 0;

// ───────────────────────── Modificadores (los usan la simulación, la IA y el Monte Carlo) ─────────────────────────

export interface PermitMod { approve: number; reject: number; info: number; time: number }
export const NEUTRAL_PERMIT: PermitMod = { approve: 1, reject: 1, info: 1, time: 1 };

export function isSocialPermit(ctx: SimContext, d: Pick<PermitDef, 'grupo'>): boolean {
  return !!ctx.data.team?.permisos_sociales.includes(d.grupo);
}

/**
 * Permisos: con g = ganancia de permisos (o 0,4·permisos + 0,6·social en permisos sociales): aprobación × (1 + kA·g),
 * rechazo × (1 − kR·g), información × (1 − kI·g), plazo × (1 − kT·g). En permisos sociales además la reputación con la
 * comunidad del país: aprobación × f, rechazo ÷ f, con f = 1 + k·(rep − 50)/50 (acotado a ±k).
 */
export function permitModifiers(state: GameState, ctx: SimContext, p: Project, d: Pick<PermitDef, 'grupo'>): PermitMod {
  const t = ctx.data.team;
  if (!t) return NEUTRAL_PERMIT;
  const social = isSocialPermit(ctx, d);
  const gl = teamGain(state, ctx, 'permisos', { projectId: p.id });
  const g = social ? 0.4 * gl + 0.6 * teamGain(state, ctx, 'social', { projectId: p.id }) : gl;
  const f = social ? repFactor(repOf(state, ctx, 'comunidad', p.countryCode), t.reputacion.efectos.social_aprobacion.base) : 1;
  return {
    approve: (1 + (social ? k(t, 'social_aprobacion') : k(t, 'permisos_aprobacion')) * g) * f,
    reject: (1 - k(t, 'permisos_rechazo') * g) / f,
    info: 1 - k(t, 'permisos_info') * g,
    time: 1 - k(t, 'permisos_tiempo') * g,
  };
}

export interface StudyMod { block: number; worse: number; sigma: number; dry: number }
export const NEUTRAL_STUDY: StudyMod = { block: 1, worse: 1, sigma: 1, dry: 1 };

export function studyModifiers(state: GameState, ctx: SimContext, p: Project): StudyMod {
  const t = ctx.data.team;
  if (!t) return NEUTRAL_STUDY;
  const g = teamGain(state, ctx, 'recurso', { projectId: p.id });
  return { block: 1 - k(t, 'recurso_bloqueo') * g, worse: 1 - k(t, 'recurso_peor') * g, sigma: 1 - k(t, 'recurso_sigma') * g, dry: 1 - k(t, 'recurso_pozo_seco') * g };
}

export interface BuildMod { overrunProb: number; overrunSize: number; stoppage: number; accident: number }
export const NEUTRAL_BUILD: BuildMod = { overrunProb: 1, overrunSize: 1, stoppage: 1, accident: 1 };

export function buildModifiers(state: GameState, ctx: SimContext, p: Project): BuildMod {
  const t = ctx.data.team;
  if (!t) return NEUTRAL_BUILD;
  const g = teamGain(state, ctx, 'obra', { projectId: p.id });
  return { overrunProb: 1 - k(t, 'obra_sobrecosto_prob') * g, overrunSize: 1 - k(t, 'obra_sobrecosto_magnitud') * g, stoppage: 1 - k(t, 'obra_paros') * g, accident: 1 - k(t, 'obra_accidentes') * g };
}

export interface FinanceMod { spread: number; fees: number; days: number }
export const NEUTRAL_FINANCE: FinanceMod = { spread: 1, fees: 1, days: 1 };

/** Financiamiento: spread × (1 − k·g) y, en bancos de desarrollo, × 1/f(gobierno) (buena relación ⇒ menor spread). */
export function financeModifiers(state: GameState, ctx: SimContext, p: Project, lenderTipo?: string): FinanceMod {
  const t = ctx.data.team;
  if (!t) return NEUTRAL_FINANCE;
  const g = teamGain(state, ctx, 'finanzas', { projectId: p.id });
  const dev = lenderTipo === 'desarrollo' ? 2 - repFactor(repOf(state, ctx, 'gobierno', p.countryCode), t.reputacion.efectos.banca_desarrollo_spread.base) : 1;
  return { spread: (1 - k(t, 'finanzas_spread') * g) * dev, fees: 1 - k(t, 'finanzas_costos') * g, days: 1 - k(t, 'finanzas_plazo') * g };
}

export interface BidMod { technicalBonus: number; prepCost: number }
export function bidModifiers(state: GameState, ctx: SimContext, countryCode: string): BidMod {
  const t = ctx.data.team;
  if (!t) return { technicalBonus: 0, prepCost: 1 };
  const g = teamGain(state, ctx, 'ofertas', { countryCode });
  return { technicalBonus: k(t, 'ofertas_puntaje') * g, prepCost: 1 - k(t, 'ofertas_preparacion') * g };
}

export interface PpaMod { success: number; price: number }
export function ppaModifiers(state: GameState, ctx: SimContext, p: Project): PpaMod {
  const t = ctx.data.team;
  if (!t) return { success: 1, price: 1 };
  return {
    success: 1 + k(t, 'mercado_ppa_exito') * teamGain(state, ctx, 'ofertas', { projectId: p.id, countryCode: p.countryCode }),
    price: 1 + k(t, 'mercado_ppa_precio') * teamGain(state, ctx, 'mercado', { projectId: p.id, countryCode: p.countryCode }),
  };
}

export interface OmMod { failures: number; repair: number }
export function omModifiers(state: GameState, ctx: SimContext, p: Project): OmMod {
  const t = ctx.data.team;
  if (!t) return { failures: 1, repair: 1 };
  const g = teamGain(state, ctx, 'operacion', { projectId: p.id });
  return { failures: 1 - k(t, 'operacion_fallas') * g, repair: 1 - k(t, 'operacion_reparacion') * g };
}

/** Probabilidad mensual de conflicto comunitario en obra: base × (1 − k·g_social) ÷ f(comunidad)^(k_conflicto). */
export function conflictProbMonthly(state: GameState, ctx: SimContext, p: Project): number {
  const t = ctx.data.team;
  if (!t) return 0;
  const g = teamGain(state, ctx, 'social', { projectId: p.id });
  const f = repFactor(repOf(state, ctx, 'comunidad', p.countryCode), t.reputacion.efectos.conflicto.base);
  return t.riesgos_obra.conflicto_mensual.base * (1 - k(t, 'social_conflicto') * g) * (2 - f);
}

export function accidentProbMonthly(state: GameState, ctx: SimContext, p: Project): number {
  const t = ctx.data.team;
  if (!t) return 0;
  return t.riesgos_obra.accidente_mensual.base * buildModifiers(state, ctx, p).accident;
}

// ───────────────────────── Mercado laboral ─────────────────────────

export function generateCandidate(state: GameState, ctx: SimContext, rng: Rng, iso: string): Candidate | undefined {
  const t = ctx.data.team;
  const lc = laborCountry(ctx, iso);
  if (!t || !lc) return undefined;
  const lm = t.mercado_laboral;
  const role = rng.pick(t.roles).id;
  const skill = Math.round(drawDist(rng, lm.habilidad));
  const exp = Math.max(1, Math.min(35, Math.round(drawDist(rng, lm.experiencia_anos) * (0.6 + 0.8 * skill / 100))));
  const native = lc.idioma;
  const languages = [native];
  if (native !== 'en' && rng.chance(lc.ingles)) languages.push('en');
  for (const [l, pr] of Object.entries(t.otras_lenguas?.[iso] ?? {})) if (!languages.includes(l) && rng.chance(pr)) languages.push(l);
  const names = t.nombres[native] ?? t.nombres.es ?? Object.values(t.nombres)[0];
  const name = `${rng.pick(names.nombres)} ${rng.pick(names.apellidos)}`;
  const lab = (state.market.labor ??= { candidates: {}, nextPersonId: 1 });
  const id = `E${lab.nextPersonId++}`;
  const base = { countryCode: iso, role, skill, experienceYears: exp };
  const ask = Math.round(marketSalaryUsd(state, ctx, base) * rng.range(0.92, 1.12) / 10) * 10;
  return { id, name, ...base, languages, askUsdMonth: ask, postedTick: state.tick, expiresTick: state.tick + Math.round(drawDist(rng, lm.vigencia_dias)) };
}

/** Cierre de mes del mercado laboral: vencen candidatos y llegan nuevos en los países donde algún actor está presente. */
export function laborMonthly(state: GameState, ctx: SimContext, open: Set<string>) {
  const t = ctx.data.team;
  if (!t) return;
  const lab = (state.market.labor ??= { candidates: {}, nextPersonId: 1 });
  const rng = new Rng(state.rng.labor ?? (state.rng.labor = seedStream(state.seed, 'labor')));
  const target = Math.round(t.mercado_laboral.candidatos_por_pais.base);
  for (const iso of [...open].sort()) {
    if (!laborCountry(ctx, iso)) continue;
    const list = (lab.candidates[iso] ?? []).filter((c) => c.expiresTick > state.tick);
    let add = Math.max(2, target - list.length);
    if (list.length + add > target + 2) add = Math.max(0, target + 2 - list.length);
    for (let i = 0; i < add; i++) { const c = generateCandidate(state, ctx, rng, iso); if (c) list.push(c); }
    lab.candidates[iso] = list;
  }
  for (const iso of Object.keys(lab.candidates)) if (!open.has(iso)) lab.candidates[iso] = lab.candidates[iso].filter((c) => c.expiresTick > state.tick);
}

// ───────────────────────── Inicialización ─────────────────────────

export function newTeamState(): TeamState {
  return { employees: [], hires: 0, quits: 0, fired: 0, history: [] };
}

function seedEmployee(state: GameState, ctx: SimContext, rng: Rng, iso: string, s: TeamMemberSeed): Employee | undefined {
  const c = generateCandidate(state, ctx, rng, iso);
  if (!c) return undefined;
  const base = { ...c, role: s.rol, skill: s.habilidad, experienceYears: s.experiencia };
  const salary = Math.round(marketSalaryUsd(state, ctx, base) / 10) * 10;
  const { askUsdMonth: _a, postedTick: _p, expiresTick: _e, ...person } = base;
  void _a; void _p; void _e;
  return { ...person, salaryUsdMonth: salary, morale: 65, hiredTick: state.tick, assignment: [], trainings: 0 };
}

/**
 * Inicialización perezosa de la Fase 6 (partidas nuevas y migradas): mercado laboral, equipo inicial explícito del
 * jugador y de cada IA (su costo se DESCUENTA de los gastos fijos, que ya lo incluían: el gasto total no cambia),
 * reputación con gobierno y comunidad del país de origen igual a la reputación previa.
 */
export function ensureTeam(state: GameState, ctx: SimContext) {
  const t = ctx.data.team;
  if (!t || !state.market?.initialized) return;
  if (state.market.labor) return;
  state.market.labor = { candidates: {}, nextPersonId: 1 };
  for (const k2 of ['labor', 'team']) if (!state.rng[k2]) state.rng[k2] = seedStream(state.seed, k2);
  const rng = new Rng(state.rng.labor);
  const setup = (b: GameState['business'], company: GameState['company'], seeds: TeamMemberSeed[], view: GameState) => {
    b.team ??= newTeamState();
    b.rep ??= newReputationState();
    const home = company.homeCountry;
    b.rep.gobierno[home] ??= b.reputation;
    b.rep.comunidad[home] ??= b.reputation;
    for (const iso of Object.keys(b.presence ?? {})) { b.rep.gobierno[iso] ??= t.reputacion.inicial_pais_nuevo.base; b.rep.comunidad[iso] ??= t.reputacion.inicial_pais_nuevo.base; }
    if (b.team.employees.length) return;
    let cost = 0;
    for (const s of seeds) {
      const e = seedEmployee(view, ctx, rng, home, s);
      if (!e) continue;
      b.team.employees.push(e);
      cost += employerCostUsd(ctx, e);
    }
    company.monthlyFixedCostUsd = Math.max(0, company.monthlyFixedCostUsd - cost);
  };
  setup(state.business, state.company, t.equipo_inicial_jugador, state);
  for (const c of state.competitors) {
    const def = ctx.data.competitors?.empresas.find((d) => d.id === c.defId);
    setup(c.business, c.company, def ? t.ia.equipo_inicial[def.estrategia] ?? [] : [], state);
  }
  laborMonthly(state, ctx, new Set([state.company.homeCountry, ...state.competitors.map((c) => c.company.homeCountry)]));
}

/** Estado raíz de la partida (desde una vista de actor, la partida completa). */
export function rootState(state: GameState): GameState {
  return state.root ?? state;
}

/** Dueño de un empleado (cualquier actor): para las ofertas a personal ajeno. */
export function findEmployeeOwner(state: GameState, employeeId: string): { actorId: string; business: GameState['business']; company: GameState['company'] } | undefined {
  const root = rootState(state);
  if (root.business.team?.employees.some((e) => e.id === employeeId)) return { actorId: PLAYER_ID, business: root.business, company: root.company };
  for (const c of root.competitors) if (c.status === 'activa' && c.business.team?.employees.some((e) => e.id === employeeId)) return { actorId: c.id, business: c.business, company: c.company };
  return undefined;
}

export type { Dist, OfficeState };
