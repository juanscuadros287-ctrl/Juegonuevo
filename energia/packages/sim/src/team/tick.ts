import type { GameState } from '../core/state';
import type { SimContext } from '../core/context';
import type { SimEvent } from '../core/events';
import { Rng, seedStream } from '../core/rng';
import { postCash } from '../finance/company';
import { drawDays, drawDist } from '../project/outcomes';
import { fmtUsd, isTerminal, note } from '../project/helpers';
import { contractUnlocked } from '../business/research';
import { openOpportunity } from '../business/opportunities';
import { withActor } from '../business/actor';
import { PLAYER_ID } from '../business/types';
import {
  accidentProbMonthly, changeRep, conflictProbMonthly, employeeLoad, employerCostUsd, laborMonthly, marketSalaryUsd, newReputationState, officeLevel,
  officeLevelDef, officeMonthlyUsd, repCause, repOf, roleDef,
} from './team';

/**
 * Fase 6: avance del equipo, las oficinas y la reputación de UN actor (jugador o vista de un competidor), y el cierre
 * de mes del mercado laboral y las invitaciones directas (mundo compartido). Flujos RNG: `team` (actores) y `labor` (mercado).
 */

function rngTeam(state: GameState) {
  if (!state.rng.team) state.rng.team = seedStream(state.seed, 'team');
  return new Rng(state.rng.team);
}

/** Avance diario: fin de capacitaciones y de mejoras de oficina. */
export function teamDaily(state: GameState, ctx: SimContext, events: SimEvent[]) {
  const t = ctx.data.team;
  const b = state.business;
  if (!t || !b) return;
  for (const e of b.team?.employees ?? []) {
    if (e.trainingUntilTick !== undefined && state.tick >= e.trainingUntilTick) {
      e.trainingUntilTick = undefined;
      const gain = t.mercado_laboral.capacitacion_ganancia.base * (1 - e.skill / 100);
      e.skill = Math.min(100, Math.round((e.skill + gain) * 10) / 10);
      e.trainings++;
      e.morale = Math.min(100, e.morale + 5);
      events.push({ type: 'trainingCompleted', employeeId: e.id, skill: e.skill, severity: 'bueno', text: `${e.name} terminó la capacitación: habilidad ${e.skill.toFixed(0)}.` });
    }
  }
  for (const [iso, o] of Object.entries(b.offices ?? {})) {
    if (o.upgradeTo && o.readyTick !== undefined && state.tick >= o.readyTick) {
      o.level = o.upgradeTo;
      o.upgradeTo = undefined;
      o.readyTick = undefined;
      o.sinceTick = state.tick;
      const pr = b.presence?.[iso];
      if (pr) pr.level = o.level;
      events.push({ type: 'officeChanged', countryCode: iso, level: o.level, severity: 'bueno', text: `${officeLevelDef(ctx, o.level)?.nombre ?? o.level} abierta en ${ctx.data.countries[iso]?.nombre ?? iso}.` });
    }
  }
}

/** Probabilidad mensual de renuncia: base + extra × ((45 − moral)/45)² si la moral es baja. */
export function quitProbability(ctx: SimContext, morale: number): number {
  const lm = ctx.data.team!.mercado_laboral;
  return lm.rotacion_base_mensual.base + lm.rotacion_moral_baja.base * Math.pow(Math.max(0, (45 - morale) / 45), 2);
}

/** Objetivo de moral: 55 + kS·(salario/mercado − 1) − kC·máx(0, carga/capacidad − 1) + 5 con oficina local o sede en su país. */
export function moraleTarget(state: GameState, ctx: SimContext, e: { salaryUsdMonth: number; countryCode: string; role: string; skill: number; experienceYears: number; id: string }): number {
  const lm = ctx.data.team!.mercado_laboral;
  const m = marketSalaryUsd(state, ctx, e);
  const r = roleDef(ctx, e.role);
  const emp = state.business.team?.employees.find((x) => x.id === e.id);
  const load = emp && r ? employeeLoad(state, ctx, emp) / r.capacidad : 0;
  const lvl = officeLevel(state, e.countryCode);
  return Math.max(0, Math.min(100, 55 + lm.moral_salario.base * (e.salaryUsdMonth / Math.max(1, m) - 1) - lm.moral_sobrecarga.base * Math.max(0, load - 1) + (lvl === 'oficina' || lvl === 'sede' ? 5 : 0)));
}

/** Cierre de mes del actor: salarios, oficinas, moral y renuncias, experiencia, riesgos sociales de obra y reputación. */
export function teamMonthly(state: GameState, ctx: SimContext, year: number, month: number, events: SimEvent[]) {
  const t = ctx.data.team;
  const b = state.business;
  if (!t || !b?.team) return;
  b.rep ??= newReputationState();
  const rng = rngTeam(state);
  const lm = t.mercado_laboral;
  let cost = 0, moraleSum = 0;
  // Salarios + cargas sociales
  for (const e of b.team.employees) { const c = employerCostUsd(ctx, e); cost += c; }
  if (cost > 0) postCash(state, 'personal', -cost, `Salarios y cargas (${b.team.employees.length} personas)`);
  // Oficinas
  for (const [iso, o] of Object.entries(b.offices ?? {})) {
    const m = officeMonthlyUsd(state, ctx, iso, o.level);
    if (m > 0) postCash(state, 'oficinas', -m, `${officeLevelDef(ctx, o.level)?.nombre ?? 'Oficina'} en ${ctx.data.countries[iso]?.nombre ?? iso}`);
  }
  // Moral, renuncias y experiencia
  const quitters: string[] = [];
  for (const e of b.team.employees) {
    e.morale += lm.moral_inercia.base * (moraleTarget(state, ctx, e) - e.morale);
    e.morale = Math.max(0, Math.min(100, e.morale));
    moraleSum += e.morale;
    e.experienceYears += lm.aumento_anual_experiencia.base / 12;
    if (rng.chance(quitProbability(ctx, e.morale))) quitters.push(e.id);
  }
  for (const id of quitters) {
    const e = b.team.employees.find((x) => x.id === id)!;
    b.team.employees = b.team.employees.filter((x) => x.id !== id);
    b.team.quits++;
    const low = e.morale < 45;
    events.push({ type: 'employeeQuit', employeeId: e.id, reason: 'moral', severity: 'malo',
      text: `${e.name} (${roleDef(ctx, e.role)?.nombre ?? e.role}) renunció${low ? `: moral ${e.morale.toFixed(0)} (salario ${fmtUsd(e.salaryUsdMonth)} frente a ${fmtUsd(marketSalaryUsd(state, ctx, e))} de mercado o sobrecarga)` : ' por motivos personales'}.` });
  }
  b.team.history.push({ year, month, headcount: b.team.employees.length, costUsd: cost, avgMorale: b.team.employees.length ? moraleSum / b.team.employees.length : 0 });
  if (b.team.history.length > 120) b.team.history.splice(0, b.team.history.length - 120);

  // Riesgos sociales y de seguridad de las obras (dependen del equipo social, la supervisión y la reputación comunitaria).
  const ro = t.riesgos_obra;
  for (const p of state.projects) {
    if (isTerminal(p) || !p.construction || p.operation || p.construction.commissioningStartTick !== undefined) continue;
    const k = p.construction;
    if (rng.chance(conflictProbMonthly(state, ctx, p))) {
      const d = drawDays(rng, ro.conflicto_dias);
      const c = drawDist(rng, ro.conflicto_costo_frac) * k.budgetUsd;
      k.stoppedDays += d;
      k.overrunUsd += c; k.monthOverrunUsd += c; k.spentUsd += c;
      events.push(note(state, p, 'communityConflict', `Conflicto con la comunidad: bloqueo de ${d} días y ${fmtUsd(c)} en negociación y compensaciones.`, 'malo', { days: d, costUsd: c }));
      repCause(state, ctx, 'conflicto', p.countryCode, `conflicto en ${p.name}`, events);
    }
    if (rng.chance(accidentProbMonthly(state, ctx, p))) {
      const d = drawDays(rng, ro.accidente_dias);
      const c = drawDist(rng, ro.accidente_costo_frac) * k.budgetUsd;
      k.stoppedDays += d;
      k.overrunUsd += c; k.monthOverrunUsd += c; k.spentUsd += c;
      events.push(note(state, p, 'constructionAccident', `Accidente grave en la obra: paro de ${d} días e investigación; costo ${fmtUsd(c)}.`, 'malo', { days: d, costUsd: c }));
      repCause(state, ctx, 'accidente', p.countryCode, `accidente en ${p.name}`, events);
    }
  }

  // Reputación: reversión hacia el neutro + relación con el gobierno por tener oficina en el país.
  const rev = t.reputacion.reversion_mensual.base, neutral = t.reputacion.neutro.base;
  for (const axis of ['gobierno', 'comunidad'] as const) {
    for (const iso of Object.keys(b.rep[axis])) b.rep[axis][iso] += rev * (neutral - b.rep[axis][iso]);
  }
  b.reputation += rev * (neutral - b.reputation);
  const countries = new Set([state.company.homeCountry, ...Object.keys(b.presence ?? {}), ...Object.keys(b.offices ?? {})]);
  for (const iso of countries) {
    const lvl = officeLevel(state, iso);
    const drift = lvl ? officeLevelDef(ctx, lvl)?.reputacion_gobierno_mes ?? 0 : 0;
    if (drift) changeRep(state, ctx, 'gobierno', iso, drift, 'oficina', 'presencia de la oficina');
  }
  // Plantas operando sin problemas: un pequeño aporte anual (en enero).
  if (month === 12) {
    const byCountry = new Map<string, number>();
    for (const p of state.projects) if (p.operation && !isTerminal(p)) byCountry.set(p.countryCode, (byCountry.get(p.countryCode) ?? 0) + 1);
    for (const [iso, n] of byCountry) repCause(state, ctx, 'planta_operando_anual', iso, `${n} planta(s) operando`, undefined, Math.min(3, n));
  }
  b.rep.history.push({ year, month, clientes: b.reputation, gobierno: { ...b.rep.gobierno }, comunidad: { ...b.rep.comunidad } });
  if (b.rep.history.length > 120) b.rep.history.splice(0, b.rep.history.length - 120);
}

/**
 * Mundo compartido al cerrar el mes: mercado laboral (candidatos en países abiertos) e invitaciones directas de
 * privados: cada actor con oficina local o sede en un país y reputación con clientes > 50 recibe con probabilidad
 * k·(rep − 50)/50 por mes una solicitud privada directa de un tipo de cliente privado del país.
 */
export function teamWorldMonthly(state: GameState, ctx: SimContext, open: Set<string>, events: SimEvent[]) {
  const t = ctx.data.team;
  if (!t || !state.market.labor) return;
  laborMonthly(state, ctx, open);
  if (!ctx.data.clients) return;
  const rng = new Rng(state.rng.labor ?? (state.rng.labor = seedStream(state.seed, 'labor')));
  const actors = [PLAYER_ID, ...state.competitors.filter((c) => c.status === 'activa').map((c) => c.id)];
  const kInv = t.reputacion.efectos.invitacion_prob_mes.base;
  for (const id of actors) {
    withActor(state, id, (v) => {
      const isos = new Set([v.company.homeCountry, ...Object.keys(v.business.presence ?? {}), ...Object.keys(v.business.offices ?? {})]);
      for (const iso of [...isos].sort()) {
        const lvl = officeLevel(v, iso);
        if (!lvl || !officeLevelDef(ctx, lvl)?.invitaciones_privadas) continue;
        const rep = 0.7 * v.business.reputation + 0.3 * repOf(v, ctx, 'gobierno', iso);
        if (rep <= 50) continue;
        if (!rng.chance(kInv * (rep - 50) / 50)) continue;
        const types = ctx.data.clients!.tipos.filter((ct) => ct.pais === iso && ct.tipo === 'solicitud_privada' && contractUnlocked(v, ctx, ct.tipo_contrato));
        if (!types.length) continue;
        const ct = rng.pick(types);
        const sink: SimEvent[] = [];
        const o = openOpportunity(state, ctx, ct, rng, sink, id);
        if (id === PLAYER_ID) {
          events.push(...sink);
          events.push({ type: 'directInvitation', opportunityId: o.id, countryCode: iso, severity: 'bueno', text: `${o.clientName} te invita directamente a ofertar ${o.mw} MW en ${ctx.data.countries[iso]?.nombre ?? iso} (por tu reputación y tu oficina local).` });
        }
      }
    });
  }
}

/** Avisos al jugador generados desde las vistas de la IA (p. ej. una renuncia por una oferta de un competidor). */
export function flushTeamNotices(state: GameState, events: SimEvent[]) {
  const n = state.market.labor?.notices;
  if (!n?.length) return;
  for (const x of n) if (x.actorId === PLAYER_ID) events.push(x.event);
  state.market.labor!.notices = [];
}
