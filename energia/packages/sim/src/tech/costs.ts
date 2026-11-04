import type { SimContext } from '../core/context';
import type { CountrySimDef, SupplierDef, TechnologyDef } from '../data/types';
import type { GameState } from '../core/state';
import { equipmentIndex, epcIndex, supplierPriceFactor } from '../supply/supply';
import { researchEffects } from '../business/research';

export interface CapexInput {
  techId: string;
  mw: number;
  countryCode: string;
  /** Multiplicador por resultados «peor» de estudios. */
  capexFactor?: number;
  equipmentId?: string;
  epcId?: string;
  /** Fase 3: proveedor de inversores (solo la fracción `fraccion_inversores` de los equipos). */
  inverterId?: string;
  /** Fase 3: operador logístico (reemplaza el flete del proveedor de equipos). */
  logisticsId?: string;
  /** Fase 3: índices de precio (curva de aprendizaje, materiales, demanda). 1 = precio de los YAML. */
  equipmentIndex?: number;
  epcIndex?: number;
  /** Fase 3: factores de precio actuales de cada proveedor (cola, relación); por defecto `factor_precio`. */
  priceFactors?: { equipment?: number; inverter?: number; epc?: number };
  /** Fase 3: multiplicador de I+D sobre todo el CAPEX (p. ej. 0,95 = −5 %). */
  costMultiplier?: number;
}

export interface CapexBreakdown {
  equipmentUsd: number;
  epcUsd: number;
  otherUsd: number;
  freightUsd: number;
  tariffsUsd: number;
  totalUsd: number;
  perKwUsd: number;
}

/**
 * CAPEX de construcción (sin desarrollo ni intereses):
 *   equipos = base·%equipos·precio_proveedor; flete = equipos·flete; aranceles e ITBMS salvo exención
 *   EPC = base·%epc·precio_EPC·costo_local; otros = base·%otros; todo × factor de estudios.
 * Sin proveedores elegidos se usan factores neutros (1,0) y flete del 5 %.
 */
export function capexBreakdown(ctx: SimContext, i: CapexInput): CapexBreakdown {
  const tech = ctx.data.technologies[i.techId];
  const country = ctx.data.countries[i.countryCode];
  const base = tech.capex_usd_kw.base * i.mw * 1000 * (i.capexFactor ?? 1) * (i.costMultiplier ?? 1);
  const eq: SupplierDef | undefined = i.equipmentId ? ctx.data.suppliers[i.equipmentId] : undefined;
  const epc: SupplierDef | undefined = i.epcId ? ctx.data.suppliers[i.epcId] : undefined;
  const inv: SupplierDef | undefined = i.inverterId ? ctx.data.suppliers[i.inverterId] : undefined;
  const log: SupplierDef | undefined = i.logisticsId ? ctx.data.suppliers[i.logisticsId] : undefined;
  const fInv = inv ? (tech.fraccion_inversores ?? 0) : 0;
  const eqFactor = i.priceFactors?.equipment ?? eq?.factor_precio ?? 1;
  const invFactor = i.priceFactors?.inverter ?? inv?.factor_precio ?? 1;
  const equipmentUsd = base * tech.desglose_capex.equipos * ((1 - fInv) * eqFactor + fInv * invFactor) * (i.equipmentIndex ?? 1);
  const freightUsd = equipmentUsd * (log?.flete_frac ?? eq?.flete_frac ?? 0.05);
  const inc = country?.incentivos[i.techId];
  const importedFromAbroad = !eq || eq.origen !== i.countryCode;
  let tariffRate = 0;
  if (importedFromAbroad) {
    if (!inc?.arancel_exento) tariffRate += country?.impuestos.arancel_general_equipos.base ?? 0;
    if (!inc?.itbms_exento) tariffRate += country?.impuestos.itbms.base ?? 0;
  }
  const tariffsUsd = (equipmentUsd + freightUsd) * tariffRate;
  const epcUsd = base * tech.desglose_capex.epc * (i.priceFactors?.epc ?? epc?.factor_precio ?? 1) * (country?.costos.factor_construccion_local.base ?? 1) * (i.epcIndex ?? 1);
  const otherUsd = base * tech.desglose_capex.otros;
  const totalUsd = equipmentUsd + freightUsd + tariffsUsd + epcUsd + otherUsd;
  return { equipmentUsd, epcUsd, otherUsd, freightUsd, tariffsUsd, totalUsd, perKwUsd: totalUsd / (i.mw * 1000) };
}

/**
 * Completa un `CapexInput` con el estado actual del mundo y del actor: índices de precio, prima por cola,
 * descuento por relación con el proveedor y reducción de costos por I+D. Es lo que se usa en el juego.
 */
export function dynamicCapexInput(state: GameState, ctx: SimContext, i: CapexInput): CapexInput {
  const pf = (id?: string) => (id ? supplierPriceFactor(state, ctx, id) : undefined);
  return {
    ...i,
    equipmentIndex: i.equipmentIndex ?? equipmentIndex(state, ctx, i.techId),
    epcIndex: i.epcIndex ?? epcIndex(state, ctx, i.techId),
    priceFactors: i.priceFactors ?? { equipment: pf(i.equipmentId), inverter: pf(i.inverterId), epc: pf(i.epcId) },
    costMultiplier: i.costMultiplier ?? researchEffects(state, ctx).capexMult(i.techId),
  };
}

/** CAPEX con precios actuales (índices, proveedores, I+D del actor de `state`). */
export function currentCapex(state: GameState, ctx: SimContext, i: CapexInput): CapexBreakdown {
  return capexBreakdown(ctx, dynamicCapexInput(state, ctx, i));
}

export function landHa(tech: TechnologyDef, mw: number): number {
  return tech.uso_suelo_ha_mw.base * mw;
}

export interface AnnualFixedCosts { omUsd: number; insuranceUsd: number; landUsd: number; totalUsd: number }

/** Costos fijos anuales de operación (año 1, sin inflación). */
export function annualFixedCosts(tech: TechnologyDef, country: CountrySimDef, mw: number, capexUsd: number, policy: 'preventivo' | 'correctivo' = 'preventivo', omMultiplier = 1): AnnualFixedCosts {
  const f = policy === 'preventivo' ? tech.mantenimiento.preventivo_om_factor : tech.mantenimiento.correctivo_om_factor;
  const omUsd = tech.om_fijo_usd_kw_ano.base * mw * 1000 * f * omMultiplier;
  const insuranceUsd = capexUsd * country.costos.seguro_frac_capex_ano.base;
  const landUsd = landHa(tech, mw) * country.costos.arriendo_terreno_usd_ha_ano.base;
  return { omUsd, insuranceUsd, landUsd, totalUsd: omUsd + insuranceUsd + landUsd };
}

/**
 * Disponibilidad esperada: 1 − mantenimiento programado − pérdida media por fallas
 * (eventos/año · fracción · días / 365), con el factor de la política de mantenimiento.
 */
export function expectedAvailability(tech: TechnologyDef, mw: number, policy: 'preventivo' | 'correctivo' = 'preventivo', failureMultiplier = 1): number {
  const pf = policy === 'preventivo' ? tech.mantenimiento.preventivo_fallas_factor : 1;
  const events = tech.fallas.eventos_ano_por_mw.base * mw * pf * failureMultiplier;
  const lossPerEvent = tech.fallas.fraccion_afectada.base * tech.fallas.duracion_dias.base / 365;
  const forced = Math.min(0.5, events * lossPerEvent); // fracción del año perdida
  return Math.max(0, (1 - tech.mantenimiento.programado_perdida) * (1 - forced));
}

/** Costo anual esperado de reparaciones (el costo por evento es por kW afectado). */
export function expectedRepairCostUsd(tech: TechnologyDef, mw: number, policy: 'preventivo' | 'correctivo' = 'preventivo', failureMultiplier = 1): number {
  const pf = policy === 'preventivo' ? tech.mantenimiento.preventivo_fallas_factor : 1;
  const events = tech.fallas.eventos_ano_por_mw.base * mw * pf * failureMultiplier;
  return events * tech.fallas.fraccion_afectada.base * mw * 1000 * tech.fallas.costo_reparacion_usd_kw.base;
}
