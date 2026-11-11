import type { GameState } from '../core/state';
import type { SimContext } from '../core/context';
import type { CountrySimDef, GeothermalDef, TechnologyDef } from '../data/types';
import type { SiteExtras } from '../project/types';
import { normalizedProfile, spotPrice } from '../market/spot';
import { worldCarbonAddUsdT } from '../world/events';
import { carbonPriceUsdT, fuelEmissionsKgMmbtu, fuelPriceUsdMmbtu, fxReal, usdInflation, usdInflationGlobal } from '../market/macro';

/**
 * Fase 4: modelo físico/económico por tecnología, compartido por la simulación, la economía estimada, las cotizaciones,
 * la viabilidad y los selectores (misma fórmula en todos lados).
 *
 * Cada tecnología produce un «producto» medido en MWh por año y vendido a un precio:
 *  - generación (solar, eólica, geotermia, hidro, CSP) y térmicas: MWh vendidos al spot capturado o por PPA;
 *    las térmicas pagan combustible (heat rate × precio indexado) e impuesto al carbono y despachan según el margen;
 *  - almacenamiento: MWh descargados vendidos en punta; la carga se compra en valle (÷ eficiencia ida y vuelta);
 *  - hidrógeno: MWh de electricidad consumidos; el precio por MWh = kg/MWh × precio del H2; la electricidad es un costo;
 *  - transmisión: MWh transportados × peaje (+ parte del diferencial de precios en interconexiones); pérdidas al spot;
 *  - eficiencia (ESCO): MWh ahorrados × precio del ahorro (contrato con el cliente), con ahorro garantizado.
 */

export type TechMode = 'generacion' | 'termica' | 'almacenamiento' | 'hidrogeno' | 'transmision' | 'eficiencia';

export function techMode(t: TechnologyDef): TechMode {
  switch (t.modelo_fc) {
    case 'termica': return 'termica';
    case 'almacenamiento': return 'almacenamiento';
    case 'hidrogeno': return 'hidrogeno';
    case 'transmision': return 'transmision';
    case 'eficiencia': return 'eficiencia';
    default: return 'generacion';
  }
}

/** ¿Vende energía por PPA? (generación y térmicas; el resto tiene su propio ingreso). */
export function sellsEnergy(t: TechnologyDef): boolean {
  const m = techMode(t);
  return m === 'generacion' || m === 'termica';
}

/** Capa de la grilla usada como clave del recurso oculto (las tecnologías sin capa usan su id). */
export function resourceKey(t: TechnologyDef): string {
  return t.recurso ?? t.id;
}

// ───────────────────────── Geotermia ─────────────────────────

/** Calidad del reservorio 0–1 a partir del flujo de calor (mW/m²). */
export function geoQuality(g: GeothermalDef, heatFlow: number): number {
  return Math.max(0, Math.min(1, (heatFlow - g.calidad_min_mw_m2) / (g.calidad_max_mw_m2 - g.calidad_min_mw_m2)));
}

export interface WellProbabilities { dry: number; low: number; productive: number; mwPerWell: number }

/**
 * Probabilidades de un pozo de EXPLORACIÓN (seco, baja entalpía, productivo) y MW por pozo productor según el flujo
 * de calor. Con `development` = pozo de desarrollo en un campo ya probado (tasa de secos × factor_seco_desarrollo).
 */
export function geoWellProbabilities(t: TechnologyDef, heatFlow: number, development = false): WellProbabilities {
  const g = t.geotermia!;
  const q = geoQuality(g, heatFlow);
  let dry = g.prob_seco_calidad0 + (g.prob_seco_calidad1 - g.prob_seco_calidad0) * q;
  const low = g.prob_baja_calidad0 + (g.prob_baja_calidad1 - g.prob_baja_calidad0) * q;
  if (development) dry *= g.factor_seco_desarrollo;
  const mw = g.mw_pozo_calidad0 + (g.mw_pozo_calidad1 - g.mw_pozo_calidad0) * q;
  return { dry, low, productive: Math.max(0, 1 - dry - low), mwPerWell: mw };
}

/** MW por pozo de referencia del CAPEX base (calidad media). */
export function geoReferenceMwPerWell(g: GeothermalDef): number {
  return (g.mw_pozo_calidad0 + g.mw_pozo_calidad1) / 2;
}

/** Pozos productores y reinyectores para `mw` con `mwPerWell` (sin contar secos). */
export function geoWellCount(g: GeothermalDef, mw: number, mwPerWell: number) {
  const producers = Math.max(1, Math.ceil(mw / Math.max(0.5, mwPerWell)));
  return { producers, injectors: Math.max(1, Math.ceil(producers * g.reinyectores_por_productor)) };
}

// ───────────────────────── Sitio ─────────────────────────

/** Factor del CAPEX por el sitio (mar adentro, profundidad, longitud de línea, productividad de pozos). */
export function siteCapexFactor(t: TechnologyDef, extras: SiteExtras | undefined, resourceEstimate: number): number {
  let f = 1;
  const s = t.sitio;
  if (s?.superficie === 'mar' && extras) {
    if (s.capex_extra_por_km) f *= 1 + s.capex_extra_por_km * Math.max(0, extras.distCoastKm - (s.km_ref ?? 0));
    if (s.flotante_desde_m !== undefined && extras.depthM >= s.flotante_desde_m) f *= 1 + (s.flotante_capex_extra ?? 0);
  }
  if (t.transmision && extras?.to) {
    f *= 1 + t.transmision.costo_usd_mw_km.base * extras.to.km / (t.capex_usd_kw.base * 1000);
  }
  if (t.geotermia) {
    const g = t.geotermia;
    const mw = geoWellProbabilities(t, resourceEstimate).mwPerWell;
    f *= 1 - g.frac_capex_perforacion + g.frac_capex_perforacion * geoReferenceMwPerWell(g) / Math.max(0.5, mw);
  }
  return f;
}

// ───────────────────────── Perfiles y precios ─────────────────────────

/** Perfil mensual de producción (12 valores, media 1). Hidro con embalse traslada energía a los meses caros. */
export function productionProfile(c: CountrySimDef | undefined, t: TechnologyDef, layer: string): number[] {
  const mode = techMode(t);
  if (mode !== 'generacion' && mode !== 'eficiencia') return new Array(12).fill(1);
  const prof = normalizedProfile(c?.perfil_recurso_mensual[layer]);
  const r = t.hidro?.regulacion ?? 0;
  if (r <= 0 || !c) return prof;
  const price = normalizedProfile(c.mercado.perfil_spot_mensual);
  return normalizedProfile(prof.map((x, i) => (1 - r) * x + r * price[i]));
}

/** Factor de captura (precio ponderado por la producción / precio medio). */
export function techCaptureFactor(c: CountrySimDef, t: TechnologyDef, layer: string): number {
  const price = normalizedProfile(c.mercado.perfil_spot_mensual);
  const prof = productionProfile(c, t, layer);
  let s = 0;
  for (let m = 0; m < 12; m++) s += price[m] * prof[m];
  return (s / 12) * (t.termica?.prima_captura ?? 1);
}

export function peakValley(c: CountrySimDef) {
  return { peak: c.mercado.factor_punta ?? 1.3, valley: c.mercado.factor_valle ?? 0.75 };
}

/** Eficiencia ida y vuelta. */
export function roundTrip(t: TechnologyDef): number {
  return t.almacenamiento?.eficiencia_ida_vuelta.base ?? 1;
}

/** El arbitraje es rentable si el precio de punta × eficiencia supera al de valle. */
export function storageProfitable(t: TechnologyDef, c: CountrySimDef): boolean {
  const { peak, valley } = peakValley(c);
  return peak * roundTrip(t) > valley;
}

/** Ciclos completos por año que haría el almacenamiento con el diferencial del país. */
export function storageCycles(t: TechnologyDef, c: CountrySimDef): number {
  return storageProfitable(t, c) ? t.almacenamiento?.ciclos_ano_max ?? 300 : 0;
}

/** Degradación anual efectiva: calendario + ciclos × degradación por ciclo. */
export function effectiveDegradation(t: TechnologyDef, c: CountrySimDef | undefined): number {
  const base = t.degradacion_anual.base;
  if (!t.almacenamiento?.degradacion_por_ciclo || !c) return base;
  return base + storageCycles(t, c) * t.almacenamiento.degradacion_por_ciclo;
}

/** kg de H2 por MWh consumido. */
export function h2KgPerMwh(t: TechnologyDef): number {
  return 1000 / (t.hidrogeno?.kwh_por_kg.base ?? 55);
}

/** Pérdidas de una línea (fracción de la energía transportada). */
export function lineLosses(t: TechnologyDef, extras: SiteExtras | undefined): number {
  return (t.transmision?.perdidas_frac_100km ?? 0) * (extras?.to?.km ?? 0) / 100;
}

// ───────────────────────── Costos variables y despacho ─────────────────────────

export interface FuelTerms {
  /** USD/MWh del producto: combustible + carbono (térmicas), carga (almacenamiento), electricidad (H2), pérdidas (líneas). */
  varUsdMwh: number;
  fuelUsdMwh: number;
  carbonUsdMwh: number;
  co2TPerMwh: number;
}

/** Factor logístico del costo de biomasa: menos productividad de biomasa ⇒ más lejos hay que ir a buscarla. */
export function biomassLogisticsFactor(npp: number): number {
  return Math.max(0.7, Math.min(2.5, Math.sqrt(1000 / Math.max(50, npp))));
}

/**
 * Costos variables (sin O&M variable) por MWh del producto. `spotUsd` = spot medio del período (USD/MWh) y
 * `yearsFromStart` para el carbono y el H2. `resourceValue` = biomasa (NPP) del sitio para la logística.
 */
export function variableTerms(state: Pick<GameState, 'market'> | null, ctx: SimContext, t: TechnologyDef, c: CountrySimDef, spotUsd: number, yearsFromStart: number, resourceValue?: number, extras?: SiteExtras): FuelTerms {
  const zero = { varUsdMwh: 0, fuelUsdMwh: 0, carbonUsdMwh: 0, co2TPerMwh: 0 };
  switch (techMode(t)) {
    case 'termica': {
      if (!t.combustible) return zero;
      const mmbtuPerMwh = t.combustible.heat_rate_btu_kwh.base / 1000;
      let price = fuelPriceUsdMmbtu(state, ctx, c, t.combustible.tipo);
      if (t.recurso === 'biomasa' && resourceValue !== undefined) price *= biomassLogisticsFactor(resourceValue);
      const fuel = mmbtuPerMwh * price;
      const co2 = mmbtuPerMwh * fuelEmissionsKgMmbtu(ctx, c, t.combustible.tipo) / 1000;
      const carbon = co2 * Math.max(0, carbonPriceUsdT(c, yearsFromStart) + worldCarbonAddUsdT(state, c.iso3));
      return { varUsdMwh: fuel + carbon, fuelUsdMwh: fuel, carbonUsdMwh: carbon, co2TPerMwh: co2 };
    }
    case 'almacenamiento': {
      const charge = spotUsd * peakValley(c).valley / Math.max(0.05, roundTrip(t));
      return { ...zero, varUsdMwh: charge, fuelUsdMwh: charge };
    }
    case 'hidrogeno': {
      const h = t.hidrogeno!;
      const elec = spotUsd * h.factor_precio_electricidad + h.agua_usd_kg * h2KgPerMwh(t);
      return { ...zero, varUsdMwh: elec, fuelUsdMwh: elec };
    }
    case 'transmision': {
      const loss = lineLosses(t, extras) * spotUsd;
      return { ...zero, varUsdMwh: loss, fuelUsdMwh: loss };
    }
    default: return zero;
  }
}

/** Fracción de despacho de una térmica según el margen sobre el costo marginal (1 = a plena disponibilidad). */
export function thermalDispatch(t: TechnologyDef, marginalUsdMwh: number, priceUsdMwh: number): number {
  if (techMode(t) !== 'termica') return 1;
  if (marginalUsdMwh <= 0) return 1;
  const ratio = priceUsdMwh / marginalUsdMwh;
  const lo = t.termica?.despacho === 'base' ? 0.4 : 0.6;
  return Math.max(0.05, Math.min(1, (ratio - lo) / 0.8));
}

export interface ProductTerms {
  mode: TechMode;
  /** Multiplicador de la energía por despacho (térmicas: margen; almacenamiento: 1 si hay arbitraje, 0 si no). */
  dispatch: number;
  /** Precio del producto si no hay PPA (USD/MWh). */
  priceUsdMwh: number;
  fuel: FuelTerms;
  degradation: number;
}

/**
 * Términos del producto para un período: `spotUsdMwh` = spot medio del país en ese período (USD, ya con tipo de cambio),
 * `capture` = factor de captura de la tecnología. Mismas fórmulas en la operación (mes a mes) y en la economía (anual).
 */
export function productTerms(state: Pick<GameState, 'market'> | null, ctx: SimContext, t: TechnologyDef, c: CountrySimDef, o: {
  spotUsdMwh: number; capture: number; yearsFromStart: number; resourceValue?: number; extras?: SiteExtras; otherSpotUsdMwh?: number;
}): ProductTerms {
  const mode = techMode(t);
  const fuel = variableTerms(state, ctx, t, c, o.spotUsdMwh, o.yearsFromStart, o.resourceValue, o.extras);
  const usdGrowth = Math.pow(1 + usdInflationGlobal(ctx), Math.max(0, o.yearsFromStart));
  let price = o.spotUsdMwh * o.capture, dispatch = 1;
  switch (mode) {
    case 'termica': {
      const mc = fuel.varUsdMwh + t.om_variable_usd_mwh.base;
      dispatch = thermalDispatch(t, mc, price);
      break;
    }
    case 'almacenamiento':
      price = o.spotUsdMwh * peakValley(c).peak;
      dispatch = storageProfitable(t, c) ? 1 : 0;
      break;
    case 'hidrogeno':
      price = (t.hidrogeno!.precio_venta_usd_kg.base * usdGrowth) * h2KgPerMwh(t);
      break;
    case 'transmision': {
      const tr = t.transmision!;
      price = tr.peaje_usd_mwh.base * usdGrowth;
      if (tr.interconexion && o.otherSpotUsdMwh !== undefined) price += tr.captura_diferencial * Math.abs(o.spotUsdMwh - o.otherSpotUsdMwh);
      break;
    }
    case 'eficiencia':
      price = t.eficiencia!.precio_ahorro_usd_mwh.base * Math.pow(1 + usdInflation(c), Math.max(0, o.yearsFromStart));
      break;
  }
  return { mode, dispatch, priceUsdMwh: price, fuel, degradation: effectiveDegradation(t, c) };
}

/** Spot medio anual del país en USD (con tipo de cambio real actual) para el año calendario dado. */
export function annualSpotUsd(state: Pick<GameState, 'market'>, c: CountrySimDef, startY: number, year: number): number {
  let s = 0;
  for (let m = 1; m <= 12; m++) s += spotPrice(c, startY, year, m);
  return (s / 12) * fxReal(state, c.iso3);
}
