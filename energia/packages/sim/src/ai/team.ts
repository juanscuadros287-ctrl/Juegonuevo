import type { GameState } from '../core/state';
import type { SimContext } from '../core/context';
import type { Command } from '../core/commands';
import type { Rng } from '../core/rng';
import type { CompetitorDef } from '../data/types';
import { isTerminal } from '../project/helpers';
import { actorIdOf } from '../business/actor';
import { PLAYER_ID } from '../business/types';
import {
  OFFICE_ORDER, employerCostUsd, marketSalaryUsd, officeCapacity, officeLevel, officeSetupUsd, recruitmentFeeUsd, rootState, roleDef, staffBasedIn,
} from '../team/team';
import { hireBlockers, upgradeBlockers } from '../team/commands';

/**
 * Fase 6: decisiones de equipo y oficinas de un actor automático (IA y jugadores automáticos del arnés de balance).
 * Mismos comandos que el jugador. Información: su propio equipo, los candidatos publicados y el perfil PÚBLICO de las
 * personas de otras empresas (rol, habilidad, experiencia y país; nunca su salario ni su moral).
 */
export function decideTeam(view: GameState, ctx: SimContext, def: CompetitorDef, rng: Rng, budget: { cash: number }, crisis: boolean): Command[] {
  const t = ctx.data.team;
  if (!t || !view.business.team) return [];
  const out: Command[] = [];
  const team = view.business.team.employees;
  const goal = t.ia.objetivos[def.estrategia];
  const active = view.projects.filter((p) => !isTerminal(p));
  const monthlyCost = team.reduce((a, e) => a + employerCostUsd(ctx, e), 0);

  // Crisis: recorta al menos valioso (indemnización incluida) si queda más de una persona.
  if (crisis) {
    if (team.length > 1 && view.company.cashUsd < 3 * (def.gastos_fijos_mensuales_usd + monthlyCost)) {
      const worst = [...team].sort((a, b) => a.skill / a.salaryUsdMonth - b.skill / b.salaryUsdMonth || a.id.localeCompare(b.id))[0];
      out.push({ type: 'fireEmployee', employeeId: worst.id });
    }
    return out;
  }

  // Retención: quien tiene moral baja y cobra bajo mercado recibe un aumento hasta el mercado + 5 %.
  for (const e of team) {
    const m = marketSalaryUsd(view, ctx, e);
    if (e.morale < 48 && e.salaryUsdMonth < m) out.push({ type: 'setSalary', employeeId: e.id, salaryUsdMonth: Math.round(m * 1.05) });
  }

  // Contratación hacia el objetivo de la estrategia.
  if (goal) {
    const want = Math.min(goal.max, Math.max(1, Math.ceil(active.length / goal.por_proyectos) + 1));
    const desired: string[] = [];
    for (let i = 0; desired.length < want; i++) desired.push(goal.roles[i % goal.roles.length]);
    const have = new Map<string, number>();
    for (const e of team) have.set(e.role, (have.get(e.role) ?? 0) + 1);
    const missing: string[] = [];
    for (const r of desired) { const n = have.get(r) ?? 0; if (n > 0) have.set(r, n - 1); else missing.push(r); }
    // Una contratación por turno (como un equipo real de RR. HH.), si la caja cubre un año de su costo con holgura.
    const role = missing[0];
    if (role && team.length < want) {
      const markets = [view.company.homeCountry, ...Object.keys(view.business.presence ?? {}).filter((iso) => officeLevel(view, iso)).sort()];
      let best: { id: string; v: number; ask: number; iso: string } | undefined;
      for (const iso of markets) {
        for (const c of view.market.labor?.candidates[iso] ?? []) {
          if (c.role !== role || c.expiresTick <= view.tick) continue;
          if (staffBasedIn(view, iso) >= officeCapacity(ctx, officeLevel(view, iso))) continue;
          const v = c.skill / Math.max(1, c.askUsdMonth) * (iso === view.company.homeCountry ? 1.05 : 1);
          if (!best || v > best.v) best = { id: c.id, v, ask: c.askUsdMonth, iso };
        }
      }
      const yearCost = best ? 12 * best.ask * 1.3 + recruitmentFeeUsd(ctx, best.ask) : 0;
      if (best && budget.cash > yearCost * 1.5 && hireBlockers(view, ctx, best.iso, best.ask).length === 0) {
        budget.cash -= yearCost / 4;
        out.push({ type: 'hireCandidate', candidateId: best.id });
      } else if (!best && (def.estrategia === 'agresiva' || def.estrategia === 'fondo') && budget.cash > 3_000_000 && rng.chance(0.25)) {
        // Sin candidatos del rol: buscar en otras empresas (oferta 25–35 % sobre el mercado de esa persona).
        const me = actorIdOf(view);
        const root = rootState(view);
        const pool = [
          ...(me !== PLAYER_ID ? (root.business.team?.employees ?? []) : []),
          ...root.competitors.filter((c) => c.id !== me && c.status === 'activa').flatMap((c) => c.business.team?.employees ?? []),
        ].filter((e) => e.role === role && e.skill >= 55).sort((a, b) => b.skill - a.skill || a.id.localeCompare(b.id));
        const target = pool[0];
        if (target) {
          const offer = Math.round(marketSalaryUsd(view, ctx, target) * rng.range(1.25, 1.35));
          if (hireBlockers(view, ctx, view.company.homeCountry, offer).length === 0) { budget.cash -= recruitmentFeeUsd(ctx, offer); out.push({ type: 'poachEmployee', employeeId: target.id, salaryUsdMonth: offer }); }
        }
      }
    }
  }

  // Oficinas: oficina local donde hay ≥ 2 proyectos activos o la oficina está llena; sede regional en el país con más
  // proyectos si la estrategia es grande (estatal, fondo) o tiene ≥ 6 proyectos.
  const byCountry = new Map<string, number>();
  for (const p of active) byCountry.set(p.countryCode, (byCountry.get(p.countryCode) ?? 0) + 1);
  for (const iso of [view.company.homeCountry, ...Object.keys(view.business.presence ?? {}).sort()]) {
    const lvl = officeLevel(view, iso);
    if (!lvl || view.business.offices?.[iso]?.upgradeTo) continue;
    const next = OFFICE_ORDER[OFFICE_ORDER.indexOf(lvl) + 1];
    if (!next) continue;
    const n = byCountry.get(iso) ?? 0;
    const full = staffBasedIn(view, iso) >= officeCapacity(ctx, lvl);
    const wants = next === 'oficina' ? n >= 2 || full : (n >= 6 || ((def.estrategia === 'estatal' || def.estrategia === 'fondo') && n >= 4)) && full;
    if (!wants) continue;
    const cost = officeSetupUsd(ctx, iso, next);
    if (budget.cash < cost * 4 || upgradeBlockers(view, ctx, iso).length) continue;
    budget.cash -= cost;
    out.push({ type: 'upgradeOffice', countryCode: iso });
    break;
  }
  // Licencia social: con obra en un país donde la comunidad desconfía (< 35), inversión social (las prudentes).
  if (def.estrategia === 'estatal' || def.estrategia === 'conservadora' || def.estrategia === 'fondo') {
    const iso = active.find((p) => p.construction && !p.operation && (view.business.rep?.comunidad[p.countryCode] ?? 50) < 35)?.countryCode;
    if (iso && budget.cash > 2_000_000) { budget.cash -= 120_000; out.push({ type: 'investInCommunity', countryCode: iso, amountUsd: 120_000 }); }
  }
  void roleDef;
  return out;
}
