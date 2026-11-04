import type { GameState } from '../core/state';
import { newFinanceState } from '../core/state';
import type { SimContext } from '../core/context';
import type { SimEvent } from '../core/events';
import type { GameDate } from '../core/calendar';
import { seedStream } from '../core/rng';
import { applyCommand } from '../core/commands';
import { siteKey } from '../world/site';
import { isTerminal } from '../project/helpers';
import { actorView, rngKey, syncActorView } from '../business/actor';
import { actorDaily, actorMonthly } from '../business/tick';
import { executeBond } from '../business/bonds';
import { newBusinessState, type CompetitorState } from '../business/types';
import { decideCompetitor, type AiContext } from './brain';

/**
 * Competidores IA (Fase 3). Cada uno es un actor completo (empresa, contabilidad, proyectos, negocio)
 * que corre EXACTAMENTE el mismo código que el jugador a través de una vista de actor. Decide cada
 * `dias_decision` días (escalonados) con `decideCompetitor` y sus comandos pasan por `applyCommand`.
 * De sus eventos solo salen a la UI los públicos: planta en operación, licitación ganada, quiebra.
 */

export function initCompetitors(state: GameState, ctx: SimContext) {
  const defs = ctx.data.competitors?.empresas ?? [];
  state.competitors = defs.map((d, i) => {
    const id = `C${i + 1}`;
    state.rng[rngKey(id)] = seedStream(state.seed, rngKey(id));
    const b = newBusinessState(d.reputacion_inicial, d.experiencia_mw_inicial);
    const comp: CompetitorState = {
      id, defId: d.id, name: d.nombre,
      company: { name: d.nombre, homeCountry: state.company.homeCountry, cashUsd: d.caja_inicial_usd, monthlyFixedCostUsd: d.gastos_fijos_mensuales_usd, ledger: [{ day: state.tick, concept: 'Capital inicial', amountUsd: d.caja_inicial_usd }] },
      finance: newFinanceState(), projects: [], nextProjectId: 1, business: b, status: 'activa',
      nextDecisionTick: state.tick + 1 + (i * 3) % Math.max(1, d.dias_decision), rejectedCommands: 0,
    };
    return comp;
  });
}

function occupiedSites(state: GameState): Set<string> {
  const s = new Set<string>();
  const add = (ps: GameState['projects']) => { for (const p of ps) if (!isTerminal(p)) s.add(siteKey(p.site.lat, p.site.lon)); };
  add(state.projects);
  for (const c of state.competitors) add(c.projects);
  return s;
}

/** Turno de decisión de los competidores (antes de avanzar el día, como los comandos del jugador). */
export function competitorsDecide(state: GameState, ctx: SimContext) {
  if (!ctx.data.competitors) return;
  let occ: Set<string> | undefined;
  for (const comp of state.competitors) {
    if (comp.status !== 'activa' || state.tick < comp.nextDecisionTick) continue;
    const def = ctx.data.competitors.empresas.find((d) => d.id === comp.defId);
    if (!def) continue;
    comp.nextDecisionTick = state.tick + def.dias_decision;
    occ ??= occupiedSites(state);
    const view = actorView(state, comp);
    const ai: AiContext = { def, occupiedSites: occ };
    const cmds = decideCompetitor(view, ctx, ai);
    const sink: SimEvent[] = [];
    for (const c of cmds) if (!applyCommand(view, c, ctx, sink).ok) comp.rejectedCommands++;
    syncActorView(view, comp);
  }
}

/** Avance diario de los competidores; empuja a `events` solo lo público. */
export function competitorsDaily(state: GameState, ctx: SimContext, prev: GameDate, now: GameDate, events: SimEvent[]) {
  for (const comp of state.competitors) {
    if (comp.status !== 'activa') continue;
    const view = actorView(state, comp);
    const sink: SimEvent[] = [];
    actorDaily(view, ctx, prev, now, sink);
    syncActorView(view, comp);
    publish(state, comp, sink, events);
  }
}

export function competitorsMonthly(state: GameState, ctx: SimContext, prev: GameDate, events: SimEvent[]) {
  for (const comp of state.competitors) {
    if (comp.status !== 'activa') continue;
    const view = actorView(state, comp);
    const sink: SimEvent[] = [];
    actorMonthly(view, ctx, prev, sink);
    syncActorView(view, comp);
    publish(state, comp, sink, events);
    if (comp.finance.bankrupt) bankrupt(state, ctx, comp, events);
  }
}

function publish(state: GameState, comp: CompetitorState, sink: SimEvent[], events: SimEvent[]) {
  for (const e of sink) {
    if (e.type === 'projectOperational') {
      const p = comp.projects.find((x) => x.id === e.projectId);
      if (p) events.push({ type: 'competitorPlantOperational', competitorId: comp.id, techId: p.techId, mw: p.mw, severity: 'info', text: `${comp.name} puso en operación una planta de ${p.mw} MW (${p.techId.replace(/_/g, ' ')}).` });
    }
  }
  void state;
}

function bankrupt(state: GameState, ctx: SimContext, comp: CompetitorState, events: SimEvent[]) {
  comp.status = 'quebrada';
  const view = actorView(state, comp);
  // Ofertas vigentes: se retiran y se pierde la garantía; contratos: se ejecutan las garantías.
  for (const o of state.market.opportunities) for (const b of o.bids) if (b.actorId === comp.id && b.status === 'presentada') { b.status = 'retirada'; executeBond(view, ctx, b.bondUsd, 'Garantía ejecutada por quiebra'); }
  for (const k of comp.business.contracts) if (k.status === 'sin_proyecto' || k.status === 'en_desarrollo') { k.status = 'incumplido'; k.endTick = state.tick; }
  syncActorView(view, comp);
  events.push({ type: 'competitorBankrupt', competitorId: comp.id, severity: 'info', text: `${comp.name} quebró: sus proyectos quedan detenidos y sus contratos, rescindidos.` });
}
