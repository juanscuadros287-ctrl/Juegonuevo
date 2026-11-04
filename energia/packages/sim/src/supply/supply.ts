import type { GameState } from '../core/state';
import type { SimContext } from '../core/context';
import type { SimEvent } from '../core/events';
import { Rng } from '../core/rng';
import type { SupplierDef } from '../data/types';

/**
 * Cadena de suministro (Fase 3).
 *  - Índices de materiales (polisilicio, acero, cobre): log-normal con reversión a 1, actualizados cada mes.
 *  - Demanda mundial de equipos: otro índice con reversión; sube precios y alarga plazos cuando está alta.
 *  - Curvas de aprendizaje: precio de equipos y obra × (1 + tasa_anual)^años desde el inicio.
 *  - Cola de cada proveedor (MW pedidos que aún no fabrica): alarga plazos y, sobre un umbral, sube precios.
 *  - Relación con el proveedor (pedidos previos del actor): descuento y más confiabilidad; los retrasos la dañan.
 * Sin `ctx.data.supply` todo vale 1 (comportamiento de la Fase 2).
 */

export const YEAR_DAYS = 365.25;

export function initSupply(state: GameState, ctx: SimContext) {
  const s = state.market.supply;
  for (const m of ctx.data.supply?.materiales ?? []) if (s.materials[m.id] === undefined) s.materials[m.id] = 1;
  if (!s.demandIndex) s.demandIndex = 1;
}

function ou(rng: Rng, x: number, volAnnual: number, revAnnual: number, min: number, max: number): number {
  const dt = 1 / 12;
  const lx = Math.log(x) * (1 - revAnnual * dt) + volAnnual * Math.sqrt(dt) * rng.normal();
  return Math.min(max, Math.max(min, Math.exp(lx)));
}

/** Cierre de mes del mercado de equipos. */
export function supplyMonthly(state: GameState, ctx: SimContext, year: number, month: number, events: SimEvent[]) {
  const def = ctx.data.supply;
  if (!def) return;
  const s = state.market.supply;
  const rng = new Rng(state.rng.supply);
  const before: Record<string, number> = {};
  for (const t of Object.keys(ctx.data.technologies)) before[t] = equipmentIndex(state, ctx, t);
  for (const m of def.materiales) s.materials[m.id] = ou(rng, s.materials[m.id] ?? 1, m.volatilidad_anual, m.reversion_anual, m.min, m.max);
  const d = def.demanda_global;
  s.demandIndex = ou(rng, s.demandIndex || 1, d.volatilidad_anual, d.reversion_anual, d.min, d.max);
  for (const [id, mw] of Object.entries(s.backlogMw)) {
    const cap = ctx.data.suppliers[id]?.capacidad_mw_ano ?? 500;
    const left = Math.max(0, mw - cap / 12);
    if (left > 0.01) s.backlogMw[id] = left; else delete s.backlogMw[id];
  }
  const equipment: Record<string, number> = {}, epc: Record<string, number> = {};
  for (const t of Object.keys(ctx.data.technologies)) { equipment[t] = equipmentIndex(state, ctx, t); epc[t] = epcIndex(state, ctx, t); }
  s.history.push({ year, month, materials: { ...s.materials }, demandIndex: s.demandIndex, equipment, epc });
  if (s.history.length > 120) s.history.splice(0, s.history.length - 120);
  for (const t of Object.keys(equipment)) {
    const ch = equipment[t] / before[t] - 1;
    if (Math.abs(ch) >= 0.06) {
      const name = ctx.data.technologies[t].nombre;
      events.push({ type: 'supplyPriceChange', techId: t, changePct: ch * 100, text: `Precio de equipos de ${name} ${ch > 0 ? 'sube' : 'baja'} ${Math.abs(ch * 100).toFixed(1)} % en el mes (materiales y demanda mundial).`, severity: ch > 0 ? 'malo' : 'bueno' });
    }
  }
}

export function yearsElapsed(state: GameState): number {
  return state.tick / YEAR_DAYS;
}

/** Índice del precio de los equipos de una tecnología (1 = precio de los YAML al inicio de la partida). */
export function equipmentIndex(state: GameState, ctx: SimContext, techId: string): number {
  const def = ctx.data.supply;
  if (!def || !state.market) return 1;
  const c = def.curvas_aprendizaje.find((x) => x.tecnologia === techId);
  const learning = c ? Math.pow(1 + c.equipos_anual, yearsElapsed(state)) : 1;
  let w = 0, mat = 0;
  for (const [id, wt] of Object.entries(c?.exposicion ?? {})) { w += wt; mat += wt * (state.market.supply.materials[id] ?? 1); }
  const demand = Math.pow(state.market.supply.demandIndex || 1, def.demanda_global.elasticidad_precio);
  return learning * (1 - w + mat) * demand;
}

/** Índice del costo de obra (EPC) de una tecnología. */
export function epcIndex(state: GameState, ctx: SimContext, techId: string): number {
  const c = ctx.data.supply?.curvas_aprendizaje.find((x) => x.tecnologia === techId);
  return c && state.market ? Math.pow(1 + c.epc_anual, yearsElapsed(state)) : 1;
}

function relation(state: GameState, id: string) {
  return state.business?.relations[id];
}

/** Descuento por relación (historial de pedidos del actor con el proveedor). */
export function relationDiscount(state: GameState, ctx: SimContext, supplierId: string): number {
  const def = ctx.data.supply?.relacion;
  const r = relation(state, supplierId);
  if (!def || !r) return 0;
  return Math.min(def.descuento_max, def.descuento_por_pedido * r.orders);
}

/** Prima de precio por la cola de pedidos del proveedor. */
export function queuePremium(state: GameState, ctx: SimContext, s: SupplierDef): number {
  const def = ctx.data.supply?.cola;
  if (!def || !s.capacidad_mw_ano || !state.market) return 1;
  const q = (state.market.supply.backlogMw[s.id] ?? 0) / s.capacidad_mw_ano;
  return 1 + def.prima_precio * Math.max(0, q - def.umbral);
}

/** Factor de precio actual de un proveedor para el actor (sin el índice de la tecnología). */
export function supplierPriceFactor(state: GameState, ctx: SimContext, supplierId: string): number {
  const s = ctx.data.suppliers[supplierId];
  if (!s) return 1;
  return s.factor_precio * queuePremium(state, ctx, s) * (1 - relationDiscount(state, ctx, supplierId));
}

/** Multiplicador del plazo de entrega: cola propia del proveedor y demanda mundial. */
export function supplierLeadFactor(state: GameState, ctx: SimContext, supplierId: string): number {
  const def = ctx.data.supply;
  const s = ctx.data.suppliers[supplierId];
  if (!def || !s || !state.market) return 1;
  const q = s.capacidad_mw_ano ? (state.market.supply.backlogMw[s.id] ?? 0) / s.capacidad_mw_ano : 0;
  return (1 + def.cola.plazo_por_cola * q) * Math.pow(state.market.supply.demandIndex || 1, def.demanda_global.elasticidad_plazo);
}

/** Confiabilidad efectiva (la relación la mejora; los retrasos previos la empeoran). */
export function supplierReliability(state: GameState, ctx: SimContext, supplierId: string): number {
  const s = ctx.data.suppliers[supplierId];
  if (!s) return 0.8;
  const def = ctx.data.supply?.relacion;
  const r = relation(state, supplierId);
  if (!def || !r) return s.confiabilidad;
  const bonus = Math.min(def.confiabilidad_max, def.confiabilidad_por_pedido * r.orders) - def.penalidad_retraso * r.lateDeliveries;
  return Math.min(0.99, Math.max(0.3, s.confiabilidad + bonus));
}

/** Registra un pedido: cola del proveedor (mercado compartido) y relación del actor. */
export function recordOrder(state: GameState, supplierId: string, mw: number, late = false) {
  if (!state.market || !state.business) return;
  const b = state.market.supply.backlogMw;
  b[supplierId] = (b[supplierId] ?? 0) + mw;
  const r = state.business.relations[supplierId] ?? (state.business.relations[supplierId] = { orders: 0, mw: 0, lateDeliveries: 0 });
  r.orders += 1;
  r.mw += mw;
  if (late) r.lateDeliveries += 1;
}

export function recordLateDelivery(state: GameState, supplierId: string) {
  const r = state.business?.relations[supplierId];
  if (r) r.lateDeliveries += 1;
}
