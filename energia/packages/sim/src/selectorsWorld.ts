/**
 * Fase 4: selectores del mundo para la UI (catálogo de tecnologías, fichas de país, mercados). Solo lectura, sin RNG.
 * Nunca exponen información oculta (recurso real, precios de reserva).
 */
import type { GameState } from './core/state';
import type { SimContext } from './core/context';
import type { CountrySimDef, TechnologyDef } from './data/types';
import type { SiteExtras } from './project/types';
import type { ResourceGrid } from './world/grid';
import { applies } from './project/requirements';
import { permitApprovalProbability, permitCostUsd } from './project/outcomes';
import { projectEconomics, type Economics } from './project/economics';
import { currentCapex } from './tech/costs';
import { capacityFactor } from './tech/capacityFactor';
import { siteCapexFactor, techMode, type TechMode } from './tech/models';
import { siteRestrictionText } from './tech/siting';
import { countryUnlocked, techUnlocked, unlockingNode } from './business/research';
import { hasPresence, presenceBlockers, presenceOf } from './business/presence';
import { carbonPriceUsdT, fuelPriceUsdMmbtu, fxNominal, fxReal, isPegged, usdInflation } from './market/macro';
import { visualKindOf, virtualProject } from './selectors';

// ───────────────────────── Recurso típico por país ─────────────────────────

const countryCellsCache = new WeakMap<ResourceGrid, Map<string, number[]>>();

function countryCells(grid: ResourceGrid, iso3: string): number[] {
  let m = countryCellsCache.get(grid);
  if (!m) { m = new Map(); countryCellsCache.set(grid, m); }
  let cells = m.get(iso3);
  if (!cells) { cells = grid.cellsOfCountry(iso3); m.set(iso3, cells); }
  return cells;
}

/**
 * Recurso de un «sitio típico bueno» de la tecnología en el país: percentil 75 de la capa en las celdas del país que
 * superan el recurso mínimo (o `recurso_tipico` del YAML si no hay grilla o es mar adentro). 1 si no usa la grilla.
 */
export function typicalResource(ctx: SimContext, t: TechnologyDef, iso3: string): number {
  if (!t.recurso) return 1;
  const fallback = t.recurso_tipico ?? t.sitio?.recurso_min ?? 1;
  if (!ctx.grid || t.sitio?.superficie === 'mar') return fallback;
  const grid = ctx.grid;
  const vals = countryCells(grid, iso3).map((i) => grid.valueAt(t.recurso!, i)).filter((v) => v > 0 && v >= (t.sitio?.recurso_min ?? 0)).sort((a, b) => a - b);
  if (!vals.length) return fallback;
  return vals[Math.floor(0.75 * (vals.length - 1))];
}

function typicalExtras(t: TechnologyDef, resource: number, iso3: string): SiteExtras {
  const sea = t.sitio?.superficie === 'mar';
  const dist = sea ? Math.max(t.sitio?.dist_costa_km_min ?? 10, 30) : 50;
  return {
    rainMm: t.hidro?.lluvia_ref_mm ?? 1500, relief: Math.max(0.5, t.sitio?.relieve_min ?? 0), distCoastKm: dist, depthM: sea ? dist * (t.sitio?.profundidad_m_por_km ?? 1.5) : 0,
    offshore: sea, hydroIndex: t.recurso === 'hidro' ? resource : 50, biomass: t.recurso === 'biomasa' ? resource : 1200,
    ...(t.transmision ? { to: { lat: 0, lon: 0, countryCode: iso3, km: t.transmision.interconexion ? 250 : 120 } } : {}),
  };
}

export interface TypicalEconomics {
  countryCode: string;
  resource: number;
  fc: number;
  capexUsdKw: number;
  lcoeUsdMwh: number;
  lcohUsdKg?: number;
  irrEquity: number | null;
  fuelCostUsdMwh: number;
  dispatch: number;
  priceUsdMwh: number;
}

/**
 * Economía de un proyecto típico (tamaño típico, sitio típico del país, sin PPA, banco comercial) con las MISMAS
 * funciones que un proyecto real (`projectEconomics`). Sirve para el catálogo y para las pruebas de LCOE.
 */
export function typicalEconomics(state: GameState, ctx: SimContext, techId: string, iso3: string, o: { resource?: number; mw?: number } = {}): TypicalEconomics | null {
  const t = ctx.data.technologies[techId];
  const c = ctx.data.countries[iso3];
  if (!t || !c) return null;
  const resource = o.resource ?? typicalResource(ctx, t, iso3);
  const mw = o.mw ?? t.escala_mw.tipico;
  const extras = typicalExtras(t, resource, iso3);
  const p = virtualProject(ctx, techId, mw, { countryCode: iso3, cellIndex: -1, layer: t.recurso ?? 'sin_recurso', value: resource, temperatureC: 22, extras });
  const sf = siteCapexFactor(t, extras, resource);
  const capex = currentCapex(state, ctx, { techId, mw, countryCode: iso3, ...(sf !== 1 ? { siteFactor: sf } : {}) }).totalUsd;
  let eco: Economics;
  try { eco = projectEconomics(state, ctx, p, { capexUsd: capex, stage: 'operacion', staticMarket: true }); } catch { return null; }
  return {
    countryCode: iso3, resource, fc: capacityFactor(t, resource, 22, extras), capexUsdKw: capex / (mw * 1000), lcoeUsdMwh: eco.lcoeUsdMwh, lcohUsdKg: eco.lcohUsdKg,
    irrEquity: eco.model.irrEquity, fuelCostUsdMwh: eco.fuelCostUsdMwh, dispatch: eco.dispatch, priceUsdMwh: eco.priceUsdMwh,
  };
}

// ───────────────────────── Catálogo de tecnologías ─────────────────────────

const MODE_LABELS: Record<TechMode, string> = {
  generacion: 'Generación', termica: 'Térmica (combustible)', almacenamiento: 'Almacenamiento', hidrogeno: 'Hidrógeno',
  transmision: 'Transmisión', eficiencia: 'Eficiencia (ESCO)',
};

export interface TechCatalogEntry {
  id: string;
  nombre: string;
  categoria: string;
  mode: TechMode;
  modeLabel: string;
  /** Tipo de modelo 3D (PlantKind). */
  visualKind: string;
  resourceLayer: string | null;
  unlocked: boolean;
  unlockNode?: { id: string; nombre: string };
  params: {
    capexUsdKw: { min: number; base: number; max: number };
    omFixedUsdKwYear: number; omVarUsdMwh: number; fcRef: number; lifeYears: number; constructionMonths: number;
    emissionsGco2Kwh: number; landHaMw: number; scaleMw: { min: number; max: number; tipico: number }; degradation: number;
    heatRateBtuKwh?: number; fuel?: string; storageHours?: number; roundTrip?: number; h2KwhPerKg?: number; h2PriceUsdKg?: number;
    lineCostUsdMwKm?: number; lineLossesPer100km?: number; tollUsdMwh?: number; savingsPriceUsdMwh?: number; guaranteedSavings?: number;
  };
  restrictions: string[];
  risks: { id: string; nombre: string; descripcion: string }[];
  /** Por país con datos: si se permite y LCOE típico. */
  byCountry: { countryCode: string; countryName: string; allowed: boolean; reason?: string; typical: TypicalEconomics | null }[];
}

const rng3 = (d: { base: number; min?: number; max?: number }) => ({ min: d.min ?? d.base, base: d.base, max: d.max ?? d.base });

/** Catálogo: todas las tecnologías con disponibilidad (I+D), parámetros y LCOE típico por país (o solo `countryCode`). */
export function selectTechCatalog(state: GameState, ctx: SimContext, o: { countryCode?: string } = {}): TechCatalogEntry[] {
  const countries = Object.values(ctx.data.countries).filter((c) => !o.countryCode || c.iso3 === o.countryCode).sort((a, b) => a.nombre.localeCompare(b.nombre));
  return Object.values(ctx.data.technologies).map((t) => {
    const node = unlockingNode(ctx, 'tecnologias', t.id);
    const mode = techMode(t);
    return {
      id: t.id, nombre: t.nombre, categoria: t.categoria, mode, modeLabel: MODE_LABELS[mode], visualKind: visualKindOf(t), resourceLayer: t.recurso ?? null,
      unlocked: techUnlocked(state, ctx, t.id), unlockNode: node ? { id: node.id, nombre: node.nombre } : undefined,
      params: {
        capexUsdKw: rng3(t.capex_usd_kw), omFixedUsdKwYear: t.om_fijo_usd_kw_ano.base, omVarUsdMwh: t.om_variable_usd_mwh.base, fcRef: t.factor_capacidad_ref.base,
        lifeYears: t.vida_util_anos.base, constructionMonths: t.construccion_meses.base, emissionsGco2Kwh: t.emisiones_gco2_kwh.base, landHaMw: t.uso_suelo_ha_mw.base,
        scaleMw: t.escala_mw, degradation: t.degradacion_anual.base,
        heatRateBtuKwh: t.combustible?.heat_rate_btu_kwh.base, fuel: t.combustible?.tipo, storageHours: t.almacenamiento?.horas.base,
        roundTrip: t.almacenamiento?.eficiencia_ida_vuelta.base, h2KwhPerKg: t.hidrogeno?.kwh_por_kg.base, h2PriceUsdKg: t.hidrogeno?.precio_venta_usd_kg.base,
        lineCostUsdMwKm: t.transmision?.costo_usd_mw_km.base, lineLossesPer100km: t.transmision?.perdidas_frac_100km, tollUsdMwh: t.transmision?.peaje_usd_mwh.base,
        savingsPriceUsdMwh: t.eficiencia?.precio_ahorro_usd_mwh.base, guaranteedSavings: t.eficiencia?.ahorro_garantizado_frac,
      },
      restrictions: siteRestrictionText(t),
      risks: t.riesgos,
      byCountry: countries.map((c) => {
        const banned = c.restricciones?.tecnologias_prohibidas.includes(t.id);
        return { countryCode: c.iso3, countryName: c.nombre, allowed: !banned, reason: banned ? c.restricciones!.motivo : undefined, typical: banned ? null : typicalEconomics(state, ctx, t.id, c.iso3) };
      }),
    };
  });
}

// ───────────────────────── Permisos como grafo ─────────────────────────

export interface PermitGraphNode {
  id: string; nombre: string; grupo: string; autoridad: string; descripcion: string;
  techs: string[] | null; mwMin?: number; mwMax?: number;
  durationDays: { min: number; base: number; max: number };
  probs: { aprobado: number; rechazado: number; info_adicional: number };
  approvalProbability: number;
  costFixedUsd: number; costUsdMw: number;
  requiresStudies: string[]; requiresPermits: string[];
  retryable: boolean;
}

export interface PermitGraph {
  nodes: PermitGraphNode[];
  /** Aristas grupo de permiso requerido → permiso (por id del permiso que satisface el grupo). */
  edges: { from: string; to: string }[];
}

export function permitGraph(c: CountrySimDef, filter?: { techId: string; mw: number }): PermitGraph {
  const permits = filter ? c.permisos.filter((d) => applies(d.aplica, filter.techId, filter.mw)) : c.permisos;
  const nodes = permits.map<PermitGraphNode>((d) => ({
    id: d.id, nombre: d.nombre, grupo: d.grupo, autoridad: d.autoridad, descripcion: d.descripcion,
    techs: d.aplica.tecnologias ?? null, mwMin: d.aplica.mw_min, mwMax: d.aplica.mw_max,
    durationDays: rng3(d.duracion_dias), probs: { aprobado: d.prob.aprobado, rechazado: d.prob.rechazado, info_adicional: d.prob.info_adicional },
    approvalProbability: permitApprovalProbability(d), costFixedUsd: d.costo_fijo_usd.base, costUsdMw: d.costo_usd_mw.base,
    requiresStudies: d.requiere.estudios, requiresPermits: d.requiere.permisos, retryable: d.reintentable,
  }));
  const edges: { from: string; to: string }[] = [];
  for (const n of nodes) for (const g of n.requiresPermits) for (const m of nodes) if (m.grupo === g) edges.push({ from: m.id, to: n.id });
  return { nodes, edges };
}

/**
 * Ruta crítica esperada de los permisos de un proyecto (días, con los pedidos de información esperados) y probabilidad
 * de aprobar todos al primer intento. Supone los estudios ya hechos.
 */
export function expectedPermitPath(c: CountrySimDef, techId: string, mw: number): { days: number; approvalAll: number; permits: number; costUsd: number } {
  const ps = c.permisos.filter((d) => applies(d.aplica, techId, mw));
  const memo = new Map<string, number>();
  const groupEnd = (g: string, depth = 0): number => {
    if (memo.has(g)) return memo.get(g)!;
    const d = ps.find((x) => x.grupo === g);
    if (!d || depth > 30) return 0;
    let start = 0;
    for (const r of d.requiere.permisos) start = Math.max(start, groupEnd(r, depth + 1));
    // Pedidos de información esperados: Σ_k (info)^k hasta el máximo × retraso medio.
    let infoExp = 0, pk = 1;
    for (let k = 0; k < d.max_intentos_info; k++) { pk *= d.prob.info_adicional; infoExp += pk; }
    const end = start + d.duracion_dias.base + infoExp * d.info_adicional.retraso_dias.base;
    memo.set(g, end);
    return end;
  };
  let days = 0, prob = 1, cost = 0;
  for (const d of ps) { days = Math.max(days, groupEnd(d.grupo)); prob *= permitApprovalProbability(d); cost += permitCostUsd(d, mw); }
  return { days, approvalAll: prob, permits: ps.length, costUsd: cost };
}

// ───────────────────────── Ficha de país ─────────────────────────

export interface CountrySheet {
  iso3: string; nombre: string;
  unlocked: boolean; unlockNode?: { id: string; nombre: string };
  presence: { home: boolean; active: boolean; status?: string; readyTick?: number; setupCostUsd?: number; monthlyCostUsd?: number; days?: { min: number; base: number; max: number }; blockers: string[] };
  regulator?: string; systemOperator?: string;
  currency: { code: string; name?: string; pegged: boolean; usdPerUnitStart: number; usdPerUnitNow: number; realIndex: number; volatility: number; drift: number; shockProbYear: number; contractsIn: 'USD' | 'local'; history: { year: number; month: number; usdPerUnit: number }[] };
  macro: { inflation: number; usdPriceInflation: number; countryRiskPremium: number; riskFree: number; equityPremium: number };
  market: { demandTwh?: number; peakMw?: number; spotUsdMwh: number; spotNowUsdMwh: number; monthlySpot: number[]; peakFactor: number; valleyFactor: number; mix?: Record<string, number | string> };
  resourceSeasonality: Record<string, number[]>;
  taxes: { income: number; depreciationYears: number; vat: number; tariff: number };
  incentives: { techId: string; descripcion: string; tariffExempt: boolean; vatExempt: boolean; taxCredit: number }[];
  costs: { localConstruction: number; prospectingUsd: number; landOptionUsdHaYear: number; landLeaseUsdHaYear: number; insurance: number; localCostShare: number };
  carbon: { priceUsdT: number; growth: number } | null;
  fuels: { type: string; priceUsdMmbtu: number }[];
  restrictions: { banned: string[]; reason?: string } | null;
  zone: { nombre: string; lat_min: number; lat_max: number; lon_min: number; lon_max: number } | null;
  risks: { construction: { rainyMonths: number[]; strikeProbMonth: number; extremeWeatherProbMonth: number } };
  lenders: { id: string; nombre: string; tipo: string; ratePct: number; tenorYears: number; maxLeverage: number; requiresPpa: boolean }[];
  ppaChannels: { id: string; nombre: string; descripcion: string; priceUsdMwh: number; years: number; probability: number; currency: 'USD' | 'local'; techs: string[] | null }[];
  permits: PermitGraph;
  /** Ruta crítica esperada de permisos por tecnología (tamaño típico). */
  permitPaths: { techId: string; days: number; approvalAll: number; permits: number; costUsd: number }[];
}

export function selectCountrySheet(state: GameState, ctx: SimContext, iso3: string): CountrySheet | null {
  const c = ctx.data.countries[iso3];
  if (!c) return null;
  const node = unlockingNode(ctx, 'paises', iso3);
  const home = iso3 === state.company.homeCountry;
  const pr = presenceOf(state, iso3);
  const e = c.expansion;
  const spot = c.mercado.precio_spot_medio_usd_mwh.base;
  const hist = (state.market?.macroHistory ?? []).map((h) => ({ year: h.year, month: h.month, usdPerUnit: h.fxUsdPerUnit[iso3] ?? c.moneda.usd_por_unidad }));
  const fuelTypes = new Set(Object.values(ctx.data.technologies).map((t) => t.combustible?.tipo).filter((x): x is string => !!x));
  const prof = c.mercado.perfil_spot_mensual;
  const mean = prof.reduce((a, b) => a + b, 0) / 12;
  return {
    iso3, nombre: c.nombre, unlocked: countryUnlocked(state, ctx, iso3), unlockNode: node ? { id: node.id, nombre: node.nombre } : undefined,
    presence: {
      home, active: hasPresence(state, iso3), status: home ? 'origen' : pr?.status, readyTick: pr?.readyTick, setupCostUsd: e?.constitucion_usd.base, monthlyCostUsd: e?.representante_mensual_usd.base,
      days: e ? rng3(e.dias) : undefined, blockers: home ? [] : presenceBlockers(state, ctx, iso3),
    },
    regulator: c.regulador, systemOperator: c.operador_sistema,
    currency: {
      code: c.moneda.codigo, name: c.moneda.nombre, pegged: isPegged(c), usdPerUnitStart: c.moneda.usd_por_unidad, usdPerUnitNow: fxNominal(state, ctx, iso3), realIndex: fxReal(state, iso3),
      volatility: c.tipo_cambio.volatilidad_anual, drift: c.tipo_cambio.deriva_anual, shockProbYear: c.tipo_cambio.shock_prob_anual ?? 0, contractsIn: c.mercado.moneda_contratos ?? 'USD', history: hist,
    },
    macro: { inflation: c.inflacion_anual.base, usdPriceInflation: usdInflation(c), countryRiskPremium: c.prima_riesgo_pais.base, riskFree: c.finanzas.tasa_libre_riesgo.base, equityPremium: c.finanzas.prima_mercado_acciones.base },
    market: {
      demandTwh: c.mercado.demanda_anual_twh?.base, peakMw: c.mercado.pico_mw?.base, spotUsdMwh: spot, spotNowUsdMwh: spot * fxReal(state, iso3),
      monthlySpot: prof.map((x) => spot * x / mean), peakFactor: c.mercado.factor_punta ?? 1.3, valleyFactor: c.mercado.factor_valle ?? 0.75, mix: c.mercado.matriz,
    },
    resourceSeasonality: c.perfil_recurso_mensual,
    taxes: { income: c.impuestos.renta.base, depreciationYears: c.impuestos.depreciacion_anos.base, vat: c.impuestos.itbms.base, tariff: c.impuestos.arancel_general_equipos.base },
    incentives: Object.entries(c.incentivos).map(([techId, i]) => ({ techId, descripcion: i.descripcion, tariffExempt: i.arancel_exento, vatExempt: i.itbms_exento, taxCredit: i.credito_fiscal_frac_inversion.base })),
    costs: {
      localConstruction: c.costos.factor_construccion_local.base, prospectingUsd: c.costos.prospeccion_usd.base, landOptionUsdHaYear: c.costos.opcion_terreno_usd_ha_ano.base,
      landLeaseUsdHaYear: c.costos.arriendo_terreno_usd_ha_ano.base, insurance: c.costos.seguro_frac_capex_ano.base, localCostShare: c.costos.fraccion_costos_locales ?? 0.5,
    },
    carbon: c.carbono ? { priceUsdT: carbonPriceUsdT(c, state.tick / 365.25), growth: c.carbono.crecimiento_anual } : null,
    fuels: [...fuelTypes].sort().map((f) => ({ type: f, priceUsdMmbtu: fuelPriceUsdMmbtu(state, ctx, c, f) })),
    restrictions: c.restricciones ? { banned: c.restricciones.tecnologias_prohibidas, reason: c.restricciones.motivo } : null,
    zone: c.zona ?? null,
    risks: { construction: { rainyMonths: c.construccion.meses_lluviosos, strikeProbMonth: c.construccion.huelga_prob_mensual, extremeWeatherProbMonth: c.construccion.clima_extremo_prob_mensual } },
    lenders: c.finanzas.prestamistas.map((l) => ({ id: l.id, nombre: l.nombre, tipo: l.tipo, ratePct: (c.finanzas.tasa_libre_riesgo.base + l.spread.base) * 100, tenorYears: l.plazo_anos, maxLeverage: l.apalancamiento_max, requiresPpa: l.requiere_ppa })),
    ppaChannels: c.ppa.canales.map((ch) => ({ id: ch.id, nombre: ch.nombre, descripcion: ch.descripcion, priceUsdMwh: ch.precio_usd_mwh.base, years: ch.plazo_anos, probability: ch.prob_exito, currency: ch.moneda ?? c.mercado.moneda_contratos ?? 'USD', techs: ch.tecnologias ?? null })),
    permits: permitGraph(c),
    permitPaths: Object.values(ctx.data.technologies).filter((t) => !c.restricciones?.tecnologias_prohibidas.includes(t.id)).map((t) => ({ techId: t.id, ...expectedPermitPath(c, t.id, t.escala_mw.tipico) })),
  };
}

export interface CountrySummary {
  iso3: string; nombre: string; unlocked: boolean; presence: 'origen' | 'activa' | 'en_tramite' | 'ninguna'; unlockNode?: string;
  spotUsdMwh: number; currency: string; usdPerUnitNow: number; realIndex: number; countryRiskPremium: number; inflation: number;
  myProjects: number; openOpportunities: number;
}

/** Lista de países con datos: desbloqueo, presencia y resumen de mercado. */
export function selectCountries(state: GameState, ctx: SimContext): CountrySummary[] {
  return Object.values(ctx.data.countries).sort((a, b) => a.nombre.localeCompare(b.nombre)).map((c) => {
    const home = c.iso3 === state.company.homeCountry;
    const pr = presenceOf(state, c.iso3);
    return {
      iso3: c.iso3, nombre: c.nombre, unlocked: countryUnlocked(state, ctx, c.iso3),
      presence: home ? 'origen' : pr?.status === 'activa' ? 'activa' : pr?.status === 'en_tramite' ? 'en_tramite' : 'ninguna',
      unlockNode: unlockingNode(ctx, 'paises', c.iso3)?.nombre,
      spotUsdMwh: c.mercado.precio_spot_medio_usd_mwh.base * fxReal(state, c.iso3), currency: c.moneda.codigo, usdPerUnitNow: fxNominal(state, ctx, c.iso3), realIndex: fxReal(state, c.iso3),
      countryRiskPremium: c.prima_riesgo_pais.base, inflation: c.inflacion_anual.base,
      myProjects: state.projects.filter((p) => p.countryCode === c.iso3).length,
      openOpportunities: (state.market?.opportunities ?? []).filter((o) => o.countryCode === c.iso3 && o.status === 'abierta').length,
    };
  });
}

/** Combustibles: precio de referencia, índice actual e historial. */
export function selectFuelMarkets(state: GameState, ctx: SimContext) {
  return (ctx.data.markets?.combustibles ?? []).map((f) => ({
    id: f.id, nombre: f.nombre, referenceUsdMmbtu: f.precio_usd_mmbtu.base, index: state.market?.fuels?.[f.id] ?? 1,
    priceUsdMmbtu: f.precio_usd_mmbtu.base * (state.market?.fuels?.[f.id] ?? 1), emissionsKgMmbtu: f.emisiones_kgco2_mmbtu,
    history: (state.market?.macroHistory ?? []).map((h) => ({ year: h.year, month: h.month, index: h.fuels[f.id] ?? 1 })),
  }));
}
