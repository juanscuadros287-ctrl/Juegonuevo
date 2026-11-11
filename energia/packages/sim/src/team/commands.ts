import type { GameState } from '../core/state';
import type { SimContext } from '../core/context';
import type { SimEvent } from '../core/events';
import { Rng, seedStream } from '../core/rng';
import { postCash } from '../finance/company';
import { drawDays, drawDist } from '../project/outcomes';
import { isTerminal } from '../project/helpers';
import { actorIdOf, actorName } from '../business/actor';
import { PLAYER_ID } from '../business/types';
import type { OfficeLevelId } from '../data/types';
import {
  OFFICE_ORDER, changeRep, employerCostUsd, findEmployeeOwner, laborCountry, marketSalaryUsd, newReputationState, newTeamState, officeCapacity, officeLevel,
  officeLevelDef, officeSetupUsd, recruitmentFeeUsd, repOf, roleDef, rootState, severanceUsd, staffBasedIn,
} from './team';
import type { Employee } from './types';

/** Fase 6: comandos del equipo, las oficinas y la inversión social (los mismos para el jugador y la IA). */
export type TeamCommand =
  | { type: 'hireCandidate'; candidateId: string; salaryUsdMonth?: number }
  | { type: 'fireEmployee'; employeeId: string }
  /** `projectIds` vacío = a la oficina (atiende todos los proyectos con su carga). */
  | { type: 'assignEmployee'; employeeId: string; projectIds: string[] }
  | { type: 'setSalary'; employeeId: string; salaryUsdMonth: number }
  | { type: 'trainEmployee'; employeeId: string }
  /** Oferta a una persona de OTRA empresa (la IA a ti y tú a la IA): honorario de reclutamiento aunque no acepte. */
  | { type: 'poachEmployee'; employeeId: string; salaryUsdMonth: number }
  | { type: 'upgradeOffice'; countryCode: string }
  | { type: 'downgradeOffice'; countryCode: string }
  | { type: 'investInCommunity'; countryCode: string; amountUsd: number };

export const TEAM_COMMANDS = ['hireCandidate', 'fireEmployee', 'assignEmployee', 'setSalary', 'trainEmployee', 'poachEmployee', 'upgradeOffice', 'downgradeOffice', 'investInCommunity'] as const;

type Result = { ok: true } | { ok: false; error: string };
const fail = (error: string): Result => ({ ok: false, error });
const OK: Result = { ok: true };
const fmt = (v: number) => `${Math.round(v).toLocaleString('es-PA')} USD`;

function teamRng(state: GameState): Rng {
  if (!state.rng.team) state.rng.team = seedStream(state.seed, 'team');
  return new Rng(state.rng.team);
}

function findEmployee(state: GameState, id: string): Employee | undefined {
  return state.business.team?.employees.find((e) => e.id === id);
}

/** Faltantes para contratar en un país (presencia y capacidad de la oficina). */
export function hireBlockers(state: GameState, ctx: SimContext, iso: string, salary: number): string[] {
  const out: string[] = [];
  const lvl = officeLevel(state, iso);
  const name = ctx.data.countries[iso]?.nombre ?? iso;
  if (!lvl) out.push(`Sin presencia en ${name}: no puedes contratar allí.`);
  else if (staffBasedIn(state, iso) >= officeCapacity(ctx, lvl)) out.push(`La ${officeLevelDef(ctx, lvl)?.nombre.toLowerCase() ?? 'oficina'} de ${name} está llena (${officeCapacity(ctx, lvl)} personas): mejora la oficina.`);
  const fee = recruitmentFeeUsd(ctx, salary);
  if (state.company.cashUsd < fee + salary) out.push(`Caja insuficiente: reclutamiento ${fmt(fee)} + primer mes.`);
  return out;
}

export function upgradeBlockers(state: GameState, ctx: SimContext, iso: string): string[] {
  const t = ctx.data.team;
  if (!t) return ['Sin datos de oficinas.'];
  const out: string[] = [];
  const lvl = officeLevel(state, iso);
  const name = ctx.data.countries[iso]?.nombre ?? iso;
  if (!lvl) return [`Sin presencia en ${name}: primero abre la sociedad local (representante).`];
  const o = state.business.offices?.[iso];
  if (o?.upgradeTo) out.push('Ya hay una mejora en curso.');
  const next = OFFICE_ORDER[OFFICE_ORDER.indexOf(lvl) + 1];
  if (!next) { out.push('Ya es sede regional (nivel máximo).'); return out; }
  if (next === 'sede' && staffBasedIn(state, iso) < t.oficinas.requisitos_sede.personal_min) out.push(`Una sede regional exige al menos ${t.oficinas.requisitos_sede.personal_min} personas en el país.`);
  const cost = officeSetupUsd(ctx, iso, next);
  if (state.company.cashUsd < cost) out.push(`Caja insuficiente: la ${officeLevelDef(ctx, next)?.nombre.toLowerCase()} cuesta ${fmt(cost)}.`);
  return out;
}

export function applyTeamCommand(state: GameState, ctx: SimContext | undefined, cmd: TeamCommand, events: SimEvent[]): Result {
  const t = ctx?.data.team;
  if (!ctx || !t) return fail('Datos del equipo no disponibles.');
  const b = state.business;
  b.team ??= newTeamState();
  b.rep ??= newReputationState();
  const lab = (state.market.labor ??= { candidates: {}, nextPersonId: 1 });
  switch (cmd.type) {
    case 'hireCandidate': {
      let iso: string | undefined, idx = -1;
      for (const [k, list] of Object.entries(lab.candidates)) { const i = list.findIndex((c) => c.id === cmd.candidateId); if (i >= 0) { iso = k; idx = i; break; } }
      if (!iso || idx < 0) return fail('El candidato ya no está disponible.');
      const c = lab.candidates[iso][idx];
      if (c.expiresTick <= state.tick) return fail('El candidato ya aceptó otra oferta.');
      const salary = Math.round(cmd.salaryUsdMonth ?? c.askUsdMonth);
      const min = t.mercado_laboral.oferta_minima_frac.base;
      if (!(salary >= min * c.askUsdMonth)) return fail(`Oferta demasiado baja: pide ${fmt(c.askUsdMonth)}/mes (mínimo aceptable ${fmt(min * c.askUsdMonth)}).`);
      const bl = hireBlockers(state, ctx, iso, salary);
      if (bl.length) return fail(bl.join(' '));
      if (salary < c.askUsdMonth && !teamRng(state).chance((salary / c.askUsdMonth - min) / (1 - min))) {
        events.push({ type: 'hireRejected', candidateId: c.id, severity: 'malo', text: `${c.name} rechazó la oferta de ${fmt(salary)}/mes (pedía ${fmt(c.askUsdMonth)}).` });
        return OK;
      }
      const fee = recruitmentFeeUsd(ctx, salary);
      postCash(state, 'personal', -fee, `Reclutamiento: ${c.name}`);
      lab.candidates[iso].splice(idx, 1);
      const { askUsdMonth: _a, postedTick: _p, expiresTick: _x, ...person } = c;
      void _a; void _p; void _x;
      // La moral inicial refleja la oferta frente al salario de mercado.
      const ratio = salary / Math.max(1, marketSalaryUsd(state, ctx, c));
      b.team.employees.push({ ...person, salaryUsdMonth: salary, morale: Math.max(40, Math.min(90, 60 + 60 * (ratio - 1))), hiredTick: state.tick, assignment: [], trainings: 0 });
      b.team.hires++;
      events.push({ type: 'employeeHired', employeeId: c.id, countryCode: iso, severity: 'bueno', text: `Contrataste a ${c.name} (${roleDef(ctx, c.role)?.nombre ?? c.role}, habilidad ${c.skill}) por ${fmt(salary)}/mes; reclutamiento ${fmt(fee)}.` });
      return OK;
    }
    case 'fireEmployee': {
      const e = findEmployee(state, cmd.employeeId);
      if (!e) return fail('Empleado inexistente.');
      const sev = severanceUsd(state, ctx, e);
      postCash(state, 'personal', -sev, `Indemnización: ${e.name}`);
      b.team.employees = b.team.employees.filter((x) => x !== e);
      b.team.fired++;
      // Despedir en serio afecta la relación con el gobierno local (si es parte de un recorte grande).
      const recent = b.team.fired;
      if (recent > 0 && recent % 4 === 0) changeRep(state, ctx, 'gobierno', e.countryCode, ctx.data.team!.reputacion.causas.despido_masivo?.gobierno ?? -1, 'despido_masivo', 'despidos', events);
      for (const o of b.team.employees) o.morale = Math.max(0, o.morale - 3);
      events.push({ type: 'employeeFired', employeeId: e.id, severanceUsd: sev, severity: 'info', text: `Despediste a ${e.name}: indemnización ${fmt(sev)}. La moral del equipo baja un poco.` });
      return OK;
    }
    case 'assignEmployee': {
      const e = findEmployee(state, cmd.employeeId);
      if (!e) return fail('Empleado inexistente.');
      const ids = [...new Set(cmd.projectIds)];
      const r = roleDef(ctx, e.role)!;
      if (ids.length > 2 * r.capacidad) return fail(`Demasiados proyectos: ${r.nombre} lleva bien ${r.capacidad} (máximo asignable ${2 * r.capacidad}).`);
      for (const id of ids) { const p = state.projects.find((x) => x.id === id); if (!p || isTerminal(p)) return fail(`Proyecto ${id} inexistente o cerrado.`); }
      e.assignment = ids;
      events.push({ type: 'employeeAssigned', employeeId: e.id, severity: 'info', text: ids.length ? `${e.name} asignado a ${ids.map((id) => state.projects.find((x) => x.id === id)!.name).join(', ')}.` : `${e.name} vuelve a la oficina (atiende todos los proyectos).` });
      return OK;
    }
    case 'setSalary': {
      const e = findEmployee(state, cmd.employeeId);
      if (!e) return fail('Empleado inexistente.');
      const m = marketSalaryUsd(state, ctx, e);
      if (!(cmd.salaryUsdMonth >= 0.5 * m && cmd.salaryUsdMonth <= 3 * m)) return fail(`El salario debe estar entre ${fmt(0.5 * m)} y ${fmt(3 * m)} (mercado ${fmt(m)}).`);
      const up = cmd.salaryUsdMonth > e.salaryUsdMonth;
      // Un aumento sube la moral de inmediato (reconocimiento); un recorte la baja más fuerte.
      e.morale = Math.max(0, Math.min(100, e.morale + (up ? 1 : 2) * 50 * (cmd.salaryUsdMonth - e.salaryUsdMonth) / Math.max(1, e.salaryUsdMonth)));
      e.salaryUsdMonth = Math.round(cmd.salaryUsdMonth);
      events.push({ type: 'salaryChanged', employeeId: e.id, salaryUsdMonth: e.salaryUsdMonth, severity: 'info', text: `Nuevo salario de ${e.name}: ${fmt(e.salaryUsdMonth)}/mes.` });
      return OK;
    }
    case 'trainEmployee': {
      const e = findEmployee(state, cmd.employeeId);
      if (!e) return fail('Empleado inexistente.');
      if (e.trainingUntilTick !== undefined && state.tick < e.trainingUntilTick) return fail('Ya está en capacitación.');
      if (e.skill >= 95) return fail('Ya está en el máximo de su campo.');
      const rng = teamRng(state);
      const cost = drawDist(rng, t.mercado_laboral.capacitacion_costo_usd);
      if (state.company.cashUsd < cost) return fail(`Caja insuficiente: la capacitación cuesta ${fmt(cost)}.`);
      const days = drawDays(rng, t.mercado_laboral.capacitacion_dias);
      postCash(state, 'personal', -cost, `Capacitación: ${e.name}`);
      e.trainingUntilTick = state.tick + days;
      events.push({ type: 'trainingStarted', employeeId: e.id, severity: 'info', text: `${e.name} empieza una capacitación (${fmt(cost)}, ${days} días sin trabajar en proyectos).` });
      return OK;
    }
    case 'poachEmployee': {
      const owner = findEmployeeOwner(state, cmd.employeeId);
      const me = actorIdOf(state);
      if (!owner) return fail('Esa persona no trabaja en otra empresa activa.');
      if (owner.actorId === me) return fail('Ya trabaja para ti.');
      const e = owner.business.team!.employees.find((x) => x.id === cmd.employeeId)!;
      const bl = hireBlockers(state, ctx, officeLevel(state, e.countryCode) ? e.countryCode : state.company.homeCountry, cmd.salaryUsdMonth);
      if (bl.length) return fail(bl.join(' '));
      const fee = recruitmentFeeUsd(ctx, cmd.salaryUsdMonth);
      postCash(state, 'personal', -fee, `Búsqueda de ${e.name} (${actorName(rootState(state), owner.actorId)})`);
      // Acepta según la mejora salarial y su moral actual: p = 3·(oferta/salario − 1,05) − (moral − 50)/100, en [0, 0,85].
      const pAccept = Math.max(0, Math.min(0.85, 3 * (cmd.salaryUsdMonth / Math.max(1, e.salaryUsdMonth) - 1.05) - (e.morale - 50) / 100));
      const notify = (ev: SimEvent) => { (rootState(state).market.labor!.notices ??= []).push({ actorId: owner.actorId, event: ev }); };
      if (!teamRng(state).chance(pAccept)) {
        events.push({ type: 'poachRejected', employeeId: e.id, severity: 'malo', text: `${e.name} rechazó tu oferta de ${fmt(cmd.salaryUsdMonth)}/mes.` });
        e.morale = Math.min(100, e.morale + 2);
        return OK;
      }
      owner.business.team!.employees = owner.business.team!.employees.filter((x) => x !== e);
      owner.business.team!.quits++;
      const base = officeLevel(state, e.countryCode) ? e.countryCode : state.company.homeCountry;
      b.team.employees.push({ ...e, countryCode: base, salaryUsdMonth: Math.round(cmd.salaryUsdMonth), morale: 70, hiredTick: state.tick, assignment: [], trainingUntilTick: undefined });
      b.team.hires++;
      const myName = actorName(rootState(state), me);
      events.push({ type: 'employeePoached', employeeId: e.id, fromActorId: owner.actorId, toActorId: me, severity: 'bueno', text: `${e.name} dejó ${actorName(rootState(state), owner.actorId)} y se une a tu equipo por ${fmt(cmd.salaryUsdMonth)}/mes.` });
      notify({ type: 'employeeQuit', employeeId: e.id, reason: 'oferta', severity: 'malo', text: `${e.name} (${roleDef(ctx, e.role)?.nombre ?? e.role}) renunció: aceptó una oferta de ${myName}.` });
      return OK;
    }
    case 'upgradeOffice': {
      const bl = upgradeBlockers(state, ctx, cmd.countryCode);
      if (bl.length) return fail(bl.join(' '));
      const lvl = officeLevel(state, cmd.countryCode)!;
      const next = OFFICE_ORDER[OFFICE_ORDER.indexOf(lvl) + 1] as OfficeLevelId;
      const d = officeLevelDef(ctx, next)!;
      const cost = officeSetupUsd(ctx, cmd.countryCode, next);
      postCash(state, 'oficinas', -cost, `${d.nombre} en ${ctx.data.countries[cmd.countryCode]?.nombre ?? cmd.countryCode}`);
      b.offices ??= {};
      const o = (b.offices[cmd.countryCode] ??= { level: lvl, sinceTick: state.tick });
      o.upgradeTo = next;
      o.readyTick = state.tick + d.dias;
      events.push({ type: 'officeUpgradeStarted', countryCode: cmd.countryCode, level: next, severity: 'info', text: `Abriendo ${d.nombre.toLowerCase()} en ${ctx.data.countries[cmd.countryCode]?.nombre ?? cmd.countryCode} (${fmt(cost)}, ~${d.dias} días).` });
      return OK;
    }
    case 'downgradeOffice': {
      const lvl = officeLevel(state, cmd.countryCode);
      if (!lvl) return fail('Sin presencia en ese país.');
      const i = OFFICE_ORDER.indexOf(lvl);
      if (i <= 0) return fail('Ya es el nivel mínimo (para salir del país usa cerrar la presencia).');
      const prev = OFFICE_ORDER[i - 1];
      if (cmd.countryCode === state.company.homeCountry && prev === 'representante') return fail('El país de origen conserva al menos la oficina local.');
      if (staffBasedIn(state, cmd.countryCode) > officeCapacity(ctx, prev)) return fail(`Hay ${staffBasedIn(state, cmd.countryCode)} personas en el país; el nivel inferior admite ${officeCapacity(ctx, prev)}.`);
      b.offices ??= {};
      b.offices[cmd.countryCode] = { level: prev, sinceTick: state.tick };
      const pr = b.presence?.[cmd.countryCode];
      if (pr) pr.level = prev;
      events.push({ type: 'officeChanged', countryCode: cmd.countryCode, level: prev, severity: 'info', text: `Oficina en ${ctx.data.countries[cmd.countryCode]?.nombre ?? cmd.countryCode} reducida a ${officeLevelDef(ctx, prev)?.nombre.toLowerCase()}.` });
      return OK;
    }
    case 'investInCommunity': {
      const iso = cmd.countryCode;
      if (!officeLevel(state, iso)) return fail('Sin presencia en ese país.');
      if (!(cmd.amountUsd > 0)) return fail('Monto inválido.');
      if (state.company.cashUsd < cmd.amountUsd) return fail('Caja insuficiente.');
      const is = t.reputacion.inversion_social;
      const year = Math.floor(state.tick / 365.25);
      const sy = b.rep!.socialYear.year === year ? b.rep!.socialYear : (b.rep!.socialYear = { year, points: {} });
      const left = is.tope_anual_puntos.base - (sy.points[iso] ?? 0);
      if (left <= 0.01) return fail('Ya alcanzaste el tope anual de inversión social en ese país (la confianza no se compra).');
      // Rendimiento decreciente: más difícil subir cuanto mejor es la relación.
      const cur = repOf(state, ctx, 'comunidad', iso);
      const pts = Math.min(left, cmd.amountUsd / is.usd_por_punto.base * (1 - cur / 120));
      postCash(state, 'inversion_social', -cmd.amountUsd, `Inversión social en ${ctx.data.countries[iso]?.nombre ?? iso}`);
      sy.points[iso] = (sy.points[iso] ?? 0) + pts;
      changeRep(state, ctx, 'comunidad', iso, pts, 'inversion_social', 'inversión social');
      events.push({ type: 'communityInvestment', countryCode: iso, amountUsd: cmd.amountUsd, points: pts, severity: 'bueno', text: `Inversión social de ${fmt(cmd.amountUsd)} en ${ctx.data.countries[iso]?.nombre ?? iso}: reputación comunitaria +${pts.toFixed(1)}.` });
      return OK;
    }
  }
}

export { PLAYER_ID, laborCountry, employerCostUsd };
