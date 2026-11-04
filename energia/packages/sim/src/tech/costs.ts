import type { SimContext } from '../core/context';
import type { CountrySimDef, SupplierDef, TechnologyDef } from '../data/types';

export interface CapexInput {
  techId: string;
  mw: number;
  countryCode: string;
  /** Multiplicador por resultados «peor» de estudios. */
  capexFactor?: number;
  equipmentId?: string;
  epcId?: string;
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
  const base = tech.capex_usd_kw.base * i.mw * 1000 * (i.capexFactor ?? 1);
  const eq: SupplierDef | undefined = i.equipmentId ? ctx.data.suppliers[i.equipmentId] : undefined;
  const epc: SupplierDef | undefined = i.epcId ? ctx.data.suppliers[i.epcId] : undefined;
  const equipmentUsd = base * tech.desglose_capex.equipos * (eq?.factor_precio ?? 1);
  const freightUsd = equipmentUsd * (eq?.flete_frac ?? 0.05);
  const inc = country?.incentivos[i.techId];
  const importedFromAbroad = !eq || eq.origen !== i.countryCode;
  let tariffRate = 0;
  if (importedFromAbroad) {
    if (!inc?.arancel_exento) tariffRate += country?.impuestos.arancel_general_equipos.base ?? 0;
    if (!inc?.itbms_exento) tariffRate += country?.impuestos.itbms.base ?? 0;
  }
  const tariffsUsd = (equipmentUsd + freightUsd) * tariffRate;
  const epcUsd = base * tech.desglose_capex.epc * (epc?.factor_precio ?? 1) * (country?.costos.factor_construccion_local.base ?? 1);
  const otherUsd = base * tech.desglose_capex.otros;
  const totalUsd = equipmentUsd + freightUsd + tariffsUsd + epcUsd + otherUsd;
  return { equipmentUsd, epcUsd, otherUsd, freightUsd, tariffsUsd, totalUsd, perKwUsd: totalUsd / (i.mw * 1000) };
}

export function landHa(tech: TechnologyDef, mw: number): number {
  return tech.uso_suelo_ha_mw.base * mw;
}

export interface AnnualFixedCosts { omUsd: number; insuranceUsd: number; landUsd: number; totalUsd: number }

/** Costos fijos anuales de operación (año 1, sin inflación). */
export function annualFixedCosts(tech: TechnologyDef, country: CountrySimDef, mw: number, capexUsd: number, policy: 'preventivo' | 'correctivo' = 'preventivo'): AnnualFixedCosts {
  const f = policy === 'preventivo' ? tech.mantenimiento.preventivo_om_factor : tech.mantenimiento.correctivo_om_factor;
  const omUsd = tech.om_fijo_usd_kw_ano.base * mw * 1000 * f;
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
