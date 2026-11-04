import type { GameState } from '../core/state';
import type { SimContext } from '../core/context';
import type { SimEvent } from '../core/events';
import { Rng } from '../core/rng';
import type { ResearchNodeDef } from '../data/types';
import { postCash } from '../finance/company';
import type { ResearchState } from './types';

/**
 * Árbol de I+D. Un nodo cuesta `costo_usd` y dura al menos `meses`; avanza cada día a
 * min(1/duración, presupuesto mensual/costo) y se paga lo devengado al cerrar el mes.
 * Al terminar puede haber un contratiempo (vuelve 10–30 % atrás, una vez).
 * Sin datos de I+D (`ctx.data.research` ausente) todo está desbloqueado (compatibilidad con la Fase 2).
 */

const DAYS_PER_MONTH = 30.44;

export interface ResearchEffectsSummary {
  /** `null` = sin restricción (no hay árbol de I+D en los datos). */
  techs: Set<string> | null;
  studies: Set<string> | null;
  /** Estudios que algún nodo desbloquea (los demás están siempre disponibles). */
  gatedStudies: Set<string>;
  countries: Set<string> | null;
  contracts: Set<string> | null;
  capexMult(techId: string): number;
  omMult(techId: string): number;
  fcMult(techId: string): number;
  permitTimeMult: number;
  technicalScoreBonus: number;
}

const cache = new WeakMap<ResearchState, { key: string; data: object; fx: ResearchEffectsSummary }>();

const UNRESTRICTED: ResearchEffectsSummary = {
  techs: null, studies: null, gatedStudies: new Set(), countries: null, contracts: null,
  capexMult: () => 1, omMult: () => 1, fcMult: () => 1, permitTimeMult: 1, technicalScoreBonus: 0,
};

export function researchNodes(ctx: SimContext): Record<string, ResearchNodeDef> {
  const out: Record<string, ResearchNodeDef> = {};
  for (const n of ctx.data.research?.nodos ?? []) out[n.id] = n;
  return out;
}

export function isResearched(ctx: SimContext, r: ResearchState, nodeId: string): boolean {
  if (r.completed.includes(nodeId)) return true;
  return !!ctx.data.research?.nodos.find((n) => n.id === nodeId)?.inicial;
}

/** Efectos acumulados de lo investigado por el actor de `state` (jugador o vista de un competidor). */
export function researchEffects(state: Pick<GameState, 'business'>, ctx: SimContext): ResearchEffectsSummary {
  const def = ctx.data.research;
  const r = state.business?.research;
  if (!def || !r) return UNRESTRICTED;
  const key = r.completed.join(',');
  const hit = cache.get(r);
  if (hit && hit.key === key && hit.data === def) return hit.fx;
  const techs = new Set<string>(), studies = new Set<string>(), countries = new Set<string>(), contracts = new Set<string>();
  const capex: Record<string, number> = {}, om: Record<string, number> = {}, fc: Record<string, number> = {};
  let permit = 1, score = 0;
  // Estudios desbloqueables: los que algún nodo menciona; el resto está disponible siempre.
  const gatedStudies = new Set<string>();
  for (const n of def.nodos) for (const s of n.efectos.estudios ?? []) gatedStudies.add(s);
  const mult = (acc: Record<string, number>, fx?: Record<string, number>) => { for (const [k, v] of Object.entries(fx ?? {})) acc[k] = (acc[k] ?? 1) * (1 + v); };
  for (const n of def.nodos) {
    if (!(n.inicial || r.completed.includes(n.id))) continue;
    const e = n.efectos;
    for (const x of e.tecnologias ?? []) techs.add(x);
    for (const x of e.estudios ?? []) studies.add(x);
    for (const x of e.paises ?? []) countries.add(x);
    for (const x of e.contratos ?? []) contracts.add(x);
    mult(capex, e.capex_frac); mult(om, e.om_frac); mult(fc, e.fc_frac);
    if (e.permisos_tiempo_frac) permit *= 1 + e.permisos_tiempo_frac;
    score += e.puntaje_tecnico ?? 0;
  }
  const get = (acc: Record<string, number>) => (techId: string) => (acc['*'] ?? 1) * (acc[techId] ?? 1);
  const fx: ResearchEffectsSummary = {
    techs, countries, contracts, studies, gatedStudies,
    capexMult: get(capex), omMult: get(om), fcMult: get(fc), permitTimeMult: permit, technicalScoreBonus: score,
  };
  cache.set(r, { key, data: def, fx });
  return fx;
}

/** ¿El estudio está disponible para el actor? (los que ningún nodo menciona lo están siempre). */
export function studyUnlocked(state: Pick<GameState, 'business'>, ctx: SimContext, studyId: string): boolean {
  const fx = researchEffects(state, ctx);
  if (!fx.studies || !fx.gatedStudies.has(studyId)) return true;
  return fx.studies.has(studyId);
}

export function techUnlocked(state: Pick<GameState, 'business'>, ctx: SimContext, techId: string): boolean {
  const t = researchEffects(state, ctx).techs;
  return !t || t.has(techId);
}

export function countryUnlocked(state: Pick<GameState, 'business'>, ctx: SimContext, iso3: string): boolean {
  const c = researchEffects(state, ctx).countries;
  return !c || c.has(iso3);
}

export function contractUnlocked(state: Pick<GameState, 'business'>, ctx: SimContext, contractType: string): boolean {
  const c = researchEffects(state, ctx).contracts;
  return !c || c.has(contractType);
}

/** Nodo de I+D que desbloquea un estudio, tecnología, país o contrato (para mensajes). */
export function unlockingNode(ctx: SimContext, kind: 'estudios' | 'tecnologias' | 'paises' | 'contratos', id: string): ResearchNodeDef | undefined {
  return ctx.data.research?.nodos.find((n) => n.efectos[kind]?.includes(id));
}

/** Faltantes para iniciar (o encolar) un nodo. */
export function researchBlockers(state: GameState, ctx: SimContext, nodeId: string, forQueue = false): string[] {
  const n = researchNodes(ctx)[nodeId];
  if (!n) return ['Investigación desconocida.'];
  const r = state.business.research;
  const out: string[] = [];
  if (isResearched(ctx, r, nodeId)) out.push('Ya está investigado.');
  if (r.active?.nodeId === nodeId) out.push('Ya está en curso.');
  if (r.queue.includes(nodeId)) out.push('Ya está en la cola.');
  for (const q of n.requiere) {
    const ok = isResearched(ctx, r, q) || (forQueue && (r.active?.nodeId === q || r.queue.includes(q)));
    if (!ok) out.push(`Requiere antes: ${researchNodes(ctx)[q]?.nombre ?? q}.`);
  }
  return out;
}

export type ResearchCommand =
  | { type: 'startResearch'; nodeId: string }
  | { type: 'queueResearch'; nodeId: string }
  | { type: 'cancelResearch'; nodeId: string }
  | { type: 'setResearchBudget'; usdPerMonth: number };

type Result = { ok: true } | { ok: false; error: string };

const ev = (type: 'researchStarted' | 'researchCompleted' | 'researchSetback' | 'researchCancelled', nodeId: string, text: string, severity: 'info' | 'bueno' | 'malo'): SimEvent =>
  ({ type, nodeId, text, severity });

function begin(state: GameState, ctx: SimContext, nodeId: string, events: SimEvent[]) {
  const r = state.business.research;
  const n = researchNodes(ctx)[nodeId];
  const progress = r.partial[nodeId] ?? 0;
  delete r.partial[nodeId];
  r.active = { nodeId, startTick: state.tick, progress, spentUsd: 0, setback: false };
  const months = Math.max(n.meses, r.budgetUsdMonth > 0 ? n.costo_usd / r.budgetUsdMonth : Infinity);
  events.push(ev('researchStarted', nodeId, `I+D iniciada: ${n.nombre} (${fmt(n.costo_usd)}; ~${Number.isFinite(months) ? Math.ceil(months * (1 - progress)) : '∞'} meses con el presupuesto actual).`, 'info'));
}

const fmt = (v: number) => `${Math.round(v).toLocaleString('es-PA')} USD`;

export function applyResearchCommand(state: GameState, ctx: SimContext | undefined, cmd: ResearchCommand, events: SimEvent[]): Result {
  if (!ctx?.data.research) return { ok: false, error: 'No hay árbol de investigación en los datos.' };
  const r = state.business.research;
  switch (cmd.type) {
    case 'setResearchBudget': {
      if (!(cmd.usdPerMonth >= 0 && cmd.usdPerMonth <= 5_000_000)) return { ok: false, error: 'Presupuesto de I+D inválido (0 a 5 000 000 USD/mes).' };
      r.budgetUsdMonth = Math.round(cmd.usdPerMonth);
      return { ok: true };
    }
    case 'startResearch': {
      const b = researchBlockers(state, ctx, cmd.nodeId);
      if (b.length) return { ok: false, error: b.join(' ') };
      if (r.budgetUsdMonth <= 0) return { ok: false, error: 'Define primero un presupuesto mensual de I+D.' };
      if (r.active) {
        r.queue.push(cmd.nodeId);
        return { ok: true };
      }
      begin(state, ctx, cmd.nodeId, events);
      return { ok: true };
    }
    case 'queueResearch': {
      const b = researchBlockers(state, ctx, cmd.nodeId, true);
      if (b.length) return { ok: false, error: b.join(' ') };
      r.queue.push(cmd.nodeId);
      return { ok: true };
    }
    case 'cancelResearch': {
      const n = researchNodes(ctx)[cmd.nodeId];
      if (r.queue.includes(cmd.nodeId)) {
        r.queue = r.queue.filter((x) => x !== cmd.nodeId);
        return { ok: true };
      }
      if (r.active?.nodeId !== cmd.nodeId) return { ok: false, error: 'Esa investigación no está en curso ni en la cola.' };
      // Lo gastado no se recupera y se pierde la mitad del avance (equipo disperso, conocimiento sin documentar).
      r.partial[cmd.nodeId] = r.active.progress * 0.5;
      r.active = null;
      events.push(ev('researchCancelled', cmd.nodeId, `I+D cancelada: ${n?.nombre ?? cmd.nodeId}. Se conserva la mitad del avance.`, 'malo'));
      startNextQueued(state, ctx, events);
      return { ok: true };
    }
  }
}

function startNextQueued(state: GameState, ctx: SimContext, events: SimEvent[]) {
  const r = state.business.research;
  while (!r.active && r.queue.length) {
    const next = r.queue.shift()!;
    if (researchBlockers(state, ctx, next).length === 0) begin(state, ctx, next, events);
  }
}

/** Avance diario (solo devenga; el pago se hace al cerrar el mes). */
export function researchDaily(state: GameState, ctx: SimContext, rng: Rng, events: SimEvent[]) {
  const r = state.business.research;
  if (!r.active || !ctx.data.research) { if (!r.active && r.queue.length && ctx.data.research) startNextQueued(state, ctx, events); return; }
  if (state.company.cashUsd <= 0 || r.budgetUsdMonth <= 0) return; // sin caja o sin presupuesto la I+D se detiene
  const n = researchNodes(ctx)[r.active.nodeId];
  const rate = Math.min(1 / (n.meses * DAYS_PER_MONTH), r.budgetUsdMonth / DAYS_PER_MONTH / n.costo_usd);
  const step = Math.min(rate, 1 - r.active.progress);
  r.active.progress += step;
  const spend = step * n.costo_usd;
  r.active.spentUsd += spend;
  r.monthSpendUsd += spend;
  if (r.active.progress < 1 - 1e-9) return;
  if (!r.active.setback && rng.chance(n.prob_contratiempo)) {
    r.active.setback = true;
    const back = rng.triangular(0.1, 0.15, 0.3);
    r.active.progress = 1 - back;
    events.push(ev('researchSetback', n.id, `Contratiempo en «${n.nombre}»: los ensayos no dieron el resultado esperado (+${Math.round(back * 100)} % de tiempo y costo).`, 'malo'));
    return;
  }
  r.completed.push(n.id);
  r.active = null;
  events.push(ev('researchCompleted', n.id, `I+D terminada: ${n.nombre}. ${describeEffects(n)}`, 'bueno'));
  startNextQueued(state, ctx, events);
}

/** Cierre de mes: paga lo devengado en I+D. */
export function researchMonthly(state: GameState) {
  const r = state.business.research;
  if (r.monthSpendUsd > 0) {
    postCash(state, 'investigacion', -r.monthSpendUsd, 'Investigación y desarrollo');
    r.totalSpentUsd += r.monthSpendUsd;
    r.monthSpendUsd = 0;
  }
}

export function describeEffects(n: ResearchNodeDef): string {
  const e = n.efectos;
  const parts: string[] = [];
  const pct = (v: number) => `${v > 0 ? '+' : '−'}${Math.abs(Math.round(v * 1000) / 10)} %`;
  const keyName = (k: string) => (k === '*' ? 'todas' : k.replace(/_/g, ' '));
  if (e.tecnologias?.length) parts.push(`Desbloquea tecnología: ${e.tecnologias.join(', ').replace(/_/g, ' ')}${n.fase_modelo ? ` (modelo completo en la Fase ${n.fase_modelo})` : ''}.`);
  if (e.estudios?.length) parts.push(`Desbloquea estudio: ${e.estudios.join(', ').replace(/_/g, ' ')}.`);
  if (e.paises?.length) parts.push(`Abre mercado: ${e.paises.join(', ')}${n.fase_modelo ? ` (Fase ${n.fase_modelo})` : ''}.`);
  if (e.contratos?.length) parts.push(`Habilita contrato: ${e.contratos.join(', ').replace(/_/g, ' ')}.`);
  for (const [k, v] of Object.entries(e.capex_frac ?? {})) parts.push(`CAPEX ${pct(v)} (${keyName(k)}).`);
  for (const [k, v] of Object.entries(e.om_frac ?? {})) parts.push(`O&M ${pct(v)} (${keyName(k)}).`);
  for (const [k, v] of Object.entries(e.fc_frac ?? {})) parts.push(`Factor de capacidad ${pct(v)} (${keyName(k)}).`);
  if (e.permisos_tiempo_frac) parts.push(`Tiempo de permisos ${pct(e.permisos_tiempo_frac)}.`);
  if (e.puntaje_tecnico) parts.push(`+${e.puntaje_tecnico} puntos técnicos en ofertas.`);
  return parts.join(' ');
}
