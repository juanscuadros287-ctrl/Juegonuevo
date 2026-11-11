import type { GameState } from '../core/state';
import type { SimContext } from '../core/context';
import type { SimEvent } from '../core/events';
import { Rng, seedStream } from '../core/rng';
import type { WorldEventDef, WorldEventEffects } from '../data/types';
import { drawDays, drawDist } from '../project/outcomes';
import { postCash } from '../finance/company';
import { actorView, syncActorView } from '../business/actor';
import { fmtUsd, isTerminal, note } from '../project/helpers';
import type { Project } from '../project/types';

/**
 * Fase 5: eventos del mundo (events.yaml). Cada mes, con el flujo RNG `events`, pueden empezar eventos globales o por
 * país (crisis petrolera, conflictos, pandemias, avances tecnológicos, sobreoferta de equipos, desastres naturales,
 * huelgas, devaluaciones, cambios regulatorios) y hay elecciones periódicas por país. Afectan por igual a todos los
 * actores: los efectos se consultan con las funciones `world*` desde el mercado, el CAPEX, los permisos y el suministro,
 * y los daños de los desastres se aplican a las plantas y obras de todos (jugador e IA) del país afectado.
 */

export interface ActiveWorldEvent {
  uid: number;
  defId: string;
  name: string;
  kind: WorldEventDef['tipo'];
  /** Países afectados; null = global. */
  countries: string[] | null;
  startTick: number;
  endTick: number;
  text: string;
  effects: WorldEventEffects;
  /** Resumen de daños (desastres): plantas afectadas y costo total (todas las empresas). */
  damage?: { plants: number; costUsd: number };
}

export interface RegulationState {
  carbonAddUsdT: number;
  permitFactor: number;
  creditFactor: number;
  government?: string;
  governmentSince?: number;
}

export interface WorldState {
  nextUid: number;
  active: ActiveWorldEvent[];
  past: ActiveWorldEvent[];
  regulation: Record<string, RegulationState>;
  /** Cambio permanente del costo por tecnología (avances tecnológicos). */
  techCost: Record<string, number>;
  /** Año de la próxima elección por país. */
  nextElection: Record<string, number>;
}

type MarketHolder = Pick<GameState, 'market'> | null | undefined;

function ws(state: MarketHolder): WorldState | undefined {
  return state?.market?.world;
}

function applies(e: ActiveWorldEvent, iso: string | undefined, tick: number | undefined): boolean {
  if (tick !== undefined && tick >= e.endTick) return false;
  return e.countries === null || (iso !== undefined && e.countries.includes(iso));
}

function product(state: MarketHolder, iso: string | undefined, tick: number | undefined, f: (x: WorldEventEffects) => number | undefined): number {
  const w = ws(state);
  if (!w) return 1;
  let m = 1;
  for (const e of w.active) if (applies(e, iso, tick)) m *= f(e.effects) ?? 1;
  return m;
}

/** Multiplicador del precio de un índice de combustible por eventos (crisis petrolera, conflictos, pandemia). */
export function worldFuelFactor(state: MarketHolder, fuelId: string, iso?: string, tick?: number): number {
  return product(state, iso, tick, (x) => x.combustibles?.[fuelId]);
}
export function worldDemandFactor(state: MarketHolder, iso: string, tick?: number): number {
  return product(state, iso, tick, (x) => x.demanda);
}
export function worldHydrologyFactor(state: MarketHolder, iso: string, tick?: number): number {
  return product(state, iso, tick, (x) => x.hidrologia);
}
/** Multiplicador del CAPEX: eventos temporales, aranceles (sobre ≈ 60 % de equipos) y avances tecnológicos permanentes. */
export function worldCapexFactor(state: MarketHolder, techId: string, iso?: string): number {
  const w = ws(state);
  if (!w) return 1;
  let m = w.techCost[techId] ?? 1;
  for (const e of w.active) {
    if (!applies(e, iso, undefined)) continue;
    m *= e.effects.capex?.[techId] ?? e.effects.capex?.todas ?? 1;
    if (e.effects.arancel) m *= 1 + 0.6 * e.effects.arancel;
  }
  return m;
}
export function worldLeadTimeFactor(state: MarketHolder): number {
  return product(state, undefined, undefined, (x) => x.plazo_entrega);
}
/** Plazo de los permisos: eventos temporales × regulación vigente del país. */
export function worldPermitFactor(state: MarketHolder, iso: string): number {
  return product(state, iso, undefined, (x) => x.plazo_permisos) * (ws(state)?.regulation[iso]?.permitFactor ?? 1);
}
export function worldCarbonAddUsdT(state: MarketHolder, iso: string): number {
  return ws(state)?.regulation[iso]?.carbonAddUsdT ?? 0;
}
/** Multiplicador del crédito fiscal a la inversión (incentivos que aparecen o desaparecen). */
export function worldCreditFactor(state: MarketHolder, iso: string): number {
  return ws(state)?.regulation[iso]?.creditFactor ?? 1;
}

/** Inicialización perezosa. */
export function ensureWorldEvents(state: GameState, ctx: SimContext) {
  if (!ctx.data.world || !state.market || state.market.world) return;
  if (!state.rng.events) state.rng.events = seedStream(state.seed, 'events');
  const nextElection: Record<string, number> = {};
  for (const [iso, pc] of Object.entries(ctx.data.power?.paises ?? {})) if (pc.elecciones) nextElection[iso] = pc.elecciones.proxima;
  state.market.world = { nextUid: 1, active: [], past: [], regulation: {}, techCost: {}, nextElection };
}

function reg(w: WorldState, iso: string): RegulationState {
  return (w.regulation[iso] ??= { carbonAddUsdT: 0, permitFactor: 1, creditFactor: 1 });
}

function applyRegulation(w: WorldState, ctx: SimContext, iso: string, r: { carbono_usd_t?: number; plazo_permisos?: number; credito_fiscal?: number }) {
  const g = reg(w, iso);
  const base = ctx.data.countries[iso]?.carbono?.precio_usd_tco2.base ?? 0;
  if (r.carbono_usd_t) g.carbonAddUsdT = Math.max(-base, Math.min(200, g.carbonAddUsdT + r.carbono_usd_t));
  if (r.plazo_permisos) g.permitFactor = Math.max(0.5, Math.min(2.5, g.permitFactor * r.plazo_permisos));
  if (r.credito_fiscal !== undefined) g.creditFactor = Math.max(0, Math.min(3, g.creditFactor * r.credito_fiscal));
}

/** Países relevantes para los avisos del jugador (origen, presencia o proyectos). */
function playerCountries(state: GameState): Set<string> {
  const s = new Set<string>([state.company.homeCountry]);
  for (const [iso, p] of Object.entries(state.business?.presence ?? {})) if (p.status === 'activa') s.add(iso);
  for (const p of state.projects) if (!isTerminal(p)) s.add(p.countryCode);
  return s;
}

/** Cierre de mes: vencimientos, nuevos eventos y elecciones. */
export function worldMonthly(state: GameState, ctx: SimContext, year: number, month: number, events: SimEvent[]) {
  const w = state.market?.world;
  const W = ctx.data.world;
  if (!w || !W) return;
  const rng = new Rng(state.rng.events);
  const mine = playerCountries(state);
  // Vencimientos
  const still: ActiveWorldEvent[] = [];
  for (const e of w.active) {
    if (state.tick >= e.endTick) {
      w.past.push(e);
      if (e.countries === null || e.countries.some((c) => mine.has(c))) {
        events.push({ type: 'worldEventEnded', eventId: e.defId, uid: e.uid, countryCode: e.countries?.[0], severity: 'info', text: `Termina: ${e.name}${e.countries ? ` (${e.countries.map((c) => ctx.data.countries[c]?.nombre ?? c).join(', ')})` : ''}.` });
      }
    } else still.push(e);
  }
  w.active = still;
  if (w.past.length > 80) w.past.splice(0, w.past.length - 80);

  const countries = Object.keys(ctx.data.countries).sort();
  for (const def of W.eventos) {
    if (def.alcance === 'global') {
      if (w.active.some((e) => e.defId === def.id)) continue;
      if (rng.chance(def.prob_anual / 12)) startEvent(state, ctx, def, null, rng, events, mine);
      continue;
    }
    for (const iso of def.paises ?? countries) {
      const p = def.amenaza ? ctx.data.power?.paises[iso]?.riesgos?.[def.amenaza] ?? 0 : def.prob_anual;
      if (p <= 0) continue;
      if (w.active.some((e) => e.defId === def.id && e.countries?.includes(iso))) continue;
      if (rng.chance(p / 12)) startEvent(state, ctx, def, [iso], rng, events, mine);
    }
  }

  // Elecciones
  for (const iso of countries) {
    const el = ctx.data.power?.paises[iso]?.elecciones;
    if (!el || w.nextElection[iso] !== year || el.mes !== month) continue;
    w.nextElection[iso] = year + el.cada_anos;
    const u = rng.next();
    let acc = 0, gov = W.gobiernos[W.gobiernos.length - 1];
    for (const g of W.gobiernos) { acc += g.prob; if (u < acc) { gov = g; break; } }
    applyRegulation(w, ctx, iso, gov.efectos);
    const r = reg(w, iso);
    r.government = gov.id;
    r.governmentSince = state.tick;
    const uid = w.nextUid++;
    const name = `Elecciones en ${ctx.data.countries[iso].nombre}`;
    const text = `${name}: gana un ${gov.nombre.toLowerCase()}, que ${gov.texto}`;
    w.past.push({ uid, defId: 'elecciones', name, kind: 'politico', countries: [iso], startTick: state.tick, endTick: state.tick, text, effects: { regulacion: gov.efectos } });
    if (mine.has(iso)) events.push({ type: 'worldEvent', eventId: 'elecciones', uid, countryCode: iso, severity: 'info', text });
  }
}

function startEvent(state: GameState, ctx: SimContext, def: WorldEventDef, countries: string[] | null, rng: Rng, events: SimEvent[], mine: Set<string>) {
  const w = state.market.world!;
  const months = Math.max(1, Math.round(drawDist(rng, def.duracion_meses)));
  const e: ActiveWorldEvent = {
    uid: w.nextUid++, defId: def.id, name: def.nombre, kind: def.tipo, countries, startTick: state.tick,
    endTick: state.tick + Math.round(months * 30.44), text: def.texto, effects: def.efectos,
  };
  const where = countries ? countries.map((c) => ctx.data.countries[c]?.nombre ?? c).join(', ') : '';
  const fx = def.efectos;
  // Efectos permanentes e inmediatos
  if (fx.regulacion) for (const iso of countries ?? Object.keys(ctx.data.countries)) applyRegulation(w, ctx, iso, fx.regulacion);
  if (fx.costo_tecnologia) for (const [t, f] of Object.entries(fx.costo_tecnologia)) w.techCost[t] = (w.techCost[t] ?? 1) * f;
  if (fx.tipo_cambio && countries && state.market.fx) for (const iso of countries) state.market.fx[iso] = Math.max(0.25, (state.market.fx[iso] ?? 1) * (1 - fx.tipo_cambio));
  if (fx.obras_paradas_dias || fx.danos) e.damage = damageAll(state, ctx, e, rng, events);
  w.active.push(e);
  if (countries === null || countries.some((c) => mine.has(c))) {
    const dmg = e.damage && e.damage.plants > 0 ? ` ${e.damage.plants} planta(s) u obra(s) dañada(s) en el país (todas las empresas).` : '';
    events.push({ type: 'worldEvent', eventId: def.id, uid: e.uid, countryCode: countries?.[0], severity: def.tipo === 'tecnologia' ? 'bueno' : def.tipo === 'regulatorio' ? 'info' : 'malo',
      text: `${where ? `${where}: ` : ''}${def.texto}${months > 1 ? ` Duración estimada: ${months} meses.` : ''}${dmg}` });
  }
}

/** Daños y paros de obra del evento sobre todos los actores (jugador e IA). */
function damageAll(state: GameState, ctx: SimContext, e: ActiveWorldEvent, rng: Rng, events: SimEvent[]) {
  const total = { plants: 0, costUsd: 0 };
  const apply = (view: GameState, isPlayer: boolean) => {
    for (const p of view.projects) {
      if (isTerminal(p) || !e.countries?.includes(p.countryCode)) continue;
      const r = damageProject(view, ctx, p, e, rng);
      if (!r) continue;
      total.plants += r.damaged ? 1 : 0;
      total.costUsd += r.costUsd;
      if (isPlayer && r.text) events.push(note(view, p, 'plantDamaged', r.text, 'malo', { eventId: e.defId, costUsd: r.costUsd, insuredUsd: r.paidUsd, days: r.days }));
    }
  };
  apply(state, true);
  for (const comp of state.competitors ?? []) {
    if (comp.status !== 'activa') continue;
    const v = actorView(state, comp);
    apply(v, false);
    syncActorView(v, comp);
  }
  return total;
}

function damageProject(state: GameState, ctx: SimContext, p: Project, e: ActiveWorldEvent, rng: Rng) {
  const fx = e.effects;
  let text = '', costUsd = 0, paidUsd = 0, days = 0, damaged = false;
  if (p.construction && !p.operation && fx.obras_paradas_dias) {
    const d = drawDays(rng, fx.obras_paradas_dias);
    p.construction.stoppedDays += d;
    days += d;
    text = `${e.name}: la obra se detiene ${d} días.`;
  }
  const dm = fx.danos;
  if (dm) {
    const v = dm.vulnerabilidad[p.techId] ?? dm.vulnerabilidad.otras ?? 0.1;
    if ((p.operation || p.construction) && rng.chance(v)) {
      damaged = true;
      const frac = Math.min(1, drawDist(rng, dm.fraccion));
      const d = drawDays(rng, dm.dias);
      const value = insuredValueUsd(p);
      costUsd = value * frac * drawDist(rng, dm.costo_frac_capex);
      days = Math.max(days, d);
      if (p.operation) {
        p.operation.outages.push({ fraction: frac, daysLeft: d });
        p.operation.month.repairUsd += costUsd;
        (p.operation.failures ??= []).push({ tick: state.tick, fraction: frac, days: d, costUsd });
      } else if (p.construction) {
        const k = p.construction;
        k.stoppedDays += Math.round(d / 3);
        k.overrunUsd += costUsd; k.monthOverrunUsd += costUsd; k.spentUsd += costUsd;
      }
      paidUsd = insuranceClaim(state, ctx, p, costUsd, frac, d);
      text = `${e.name}: daños en ${(frac * 100).toFixed(0)} % de la planta${p.operation ? ` (${d} días fuera de servicio)` : ''}, reparación ${fmtUsd(costUsd)}.${paidUsd > 0 ? ` El seguro paga ${fmtUsd(paidUsd)}.` : p.insurance ? ' El seguro aún no cubre (carencia).' : ' Sin seguro de catástrofe: lo paga la empresa.'}`;
    }
  }
  if (!text) return undefined;
  return { text, costUsd, paidUsd, days, damaged };
}

// ───────────────────────── Seguros ─────────────────────────

export type InsuranceCoverage = 'danos' | 'danos_lucro';

export interface Insurance {
  coverage: InsuranceCoverage;
  startTick: number;
  premiumUsdYear: number;
  claims: { tick: number; paidUsd: number }[];
}

/** Valor asegurado: activo bruto en operación o presupuesto de la obra. */
export function insuredValueUsd(p: Project): number {
  if (p.operation) return p.operation.grossAssetUsd;
  if (p.construction) return p.construction.budgetUsd + p.construction.overrunUsd;
  return 0;
}

/**
 * Prima anual: pérdida esperada (Σ amenazas del país × vulnerabilidad de la tecnología × daño medio) × recargo, con
 * piso `tasa_minima`; × factor de lucro cesante si lo cubre.
 */
export function insurancePremium(ctx: SimContext, p: Project, coverage: InsuranceCoverage): { premiumUsdYear: number; expectedLossFrac: number; rate: number } {
  const W = ctx.data.world;
  const risks = ctx.data.power?.paises[p.countryCode]?.riesgos ?? {};
  let loss = 0;
  for (const e of W?.eventos ?? []) {
    if (!e.amenaza || !e.efectos.danos) continue;
    const prob = risks[e.amenaza] ?? 0;
    const d = e.efectos.danos;
    loss += prob * (d.vulnerabilidad[p.techId] ?? d.vulnerabilidad.otras ?? 0.1) * d.fraccion.base * d.costo_frac_capex.base;
  }
  const s = W?.seguros;
  const rate = Math.max(s?.tasa_minima ?? 0.001, loss * (s?.recargo ?? 1.6)) * (coverage === 'danos_lucro' ? s?.lucro_factor_prima ?? 1.35 : 1);
  return { premiumUsdYear: insuredValueUsd(p) * rate, expectedLossFrac: loss, rate };
}

/** Indemnización de un siniestro (si la póliza ya cubre): daño − deducible y, con lucro cesante, ingresos perdidos. */
function insuranceClaim(state: GameState, ctx: SimContext, p: Project, costUsd: number, frac: number, days: number): number {
  const ins = p.insurance;
  const s = ctx.data.world?.seguros;
  if (!ins || !s || state.tick < ins.startTick + s.espera_dias) return 0;
  let paid = Math.max(0, costUsd * (1 - s.deducible_frac));
  if (ins.coverage === 'danos_lucro' && p.operation) {
    const h = p.operation.history.slice(-12);
    const perDay = h.length ? h.reduce((a, x) => a + x.revenueUsd, 0) / (h.length * 30.44) : 0;
    paid += perDay * frac * Math.min(days, s.lucro_dias_max);
  }
  if (paid <= 0) return 0;
  postCash(state, 'indemnizaciones', paid, `${p.name}: indemnización del seguro`);
  ins.claims.push({ tick: state.tick, paidUsd: paid });
  if (ins.claims.length > 50) ins.claims.splice(0, ins.claims.length - 50);
  return paid;
}

/** Cobro mensual de las primas (lo llama el cierre de mes del proyecto). */
export function insuranceMonthly(state: GameState, ctx: SimContext, p: Project) {
  const ins = p.insurance;
  if (!ins || isTerminal(p)) return;
  if (!p.operation && !p.construction) return;
  // La prima se ajusta al valor asegurado vigente.
  ins.premiumUsdYear = insurancePremium(ctx, p, ins.coverage).premiumUsdYear;
  postCash(state, 'seguro', -ins.premiumUsdYear / 12, `${p.name}: seguro de catástrofe`);
}

/** Fuerza un evento (pruebas y escenarios): mismo efecto que si saliera en el sorteo. */
export function triggerWorldEvent(state: GameState, ctx: SimContext, eventId: string, countries: string[] | null, events: SimEvent[] = []): ActiveWorldEvent | undefined {
  ensureWorldEvents(state, ctx);
  const def = ctx.data.world?.eventos.find((e) => e.id === eventId);
  if (!def || !state.market.world) return undefined;
  const rng = new Rng(state.rng.events);
  startEvent(state, ctx, def, def.alcance === 'global' ? null : countries, rng, events, playerCountries(state));
  return state.market.world.active[state.market.world.active.length - 1];
}
