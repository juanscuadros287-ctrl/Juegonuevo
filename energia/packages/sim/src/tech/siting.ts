import type { SimContext } from '../core/context';
import type { CountrySimDef, TechnologyDef } from '../data/types';
import type { SiteExtras } from '../project/types';

/**
 * Fase 4: evaluación de un sitio para una tecnología con la información pública de la grilla.
 * La comparten `createProject`, `previewSite`, la IA y los selectores (mismas restricciones en todos).
 */
export interface SiteEvaluation {
  ok: boolean;
  /** Motivos por los que no se puede (vacío si ok). */
  errors: string[];
  countryCode?: string;
  countryName?: string;
  cellIndex: number;
  /** Valor del recurso de la celda (capa de la tecnología; 1 si no tiene capa). */
  value: number;
  layer: string;
  temperatureC: number;
  extras: SiteExtras;
  /** Restricciones de la tecnología en texto (para la UI). */
  restrictions: string[];
}

export const KM_PER_DEG = 111.2;

/** Distancia de trazado (km) entre dos puntos: gran círculo × 1,15 (rodeos, servidumbres). */
export function routeKm(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const r = Math.PI / 180;
  const a = Math.sin((lat2 - lat1) * r / 2) ** 2 + Math.cos(lat1 * r) * Math.cos(lat2 * r) * Math.sin((lon2 - lon1) * r / 2) ** 2;
  return 2 * 6371 * Math.asin(Math.min(1, Math.sqrt(a))) * 1.15;
}

export function siteRestrictionText(t: TechnologyDef): string[] {
  const s = t.sitio;
  const out: string[] = [];
  if (!s) return out;
  if (s.superficie === 'mar') out.push('En el mar, cerca de la costa de un país habilitado.');
  if (s.recurso_min !== undefined && t.recurso) out.push(`Recurso mínimo: ${s.recurso_min} (${t.recurso.replace(/_/g, ' ')}).`);
  if (s.dist_costa_km_min !== undefined) out.push(`A más de ${s.dist_costa_km_min} km de la costa.`);
  if (s.dist_costa_km_max !== undefined) out.push(`A menos de ${s.dist_costa_km_max} km de la costa.`);
  if (s.profundidad_max_m !== undefined) out.push(`Profundidad máxima ≈ ${s.profundidad_max_m} m${s.flotante_desde_m !== undefined ? ` (flotante desde ${s.flotante_desde_m} m, +${Math.round((s.flotante_capex_extra ?? 0) * 100)} % de CAPEX)` : ''}.`);
  if (s.relieve_min !== undefined) out.push(`Relieve mínimo ${s.relieve_min} (desnivel para los embalses).`);
  if (s.agua_indice_min !== undefined) out.push(`Necesita agua: índice hidro ≥ ${s.agua_indice_min}${s.agua_dist_costa_km !== undefined ? ` o a menos de ${s.agua_dist_costa_km} km de la costa` : ''}.`);
  if (t.transmision) out.push(`Línea de ${t.transmision.longitud_min_km} a ${t.transmision.longitud_max_km} km${t.transmision.interconexion ? ' entre dos países' : ' dentro de un país'}.`);
  return out;
}

function countryAllows(c: CountrySimDef, t: TechnologyDef, lat: number, lon: number): string[] {
  const out: string[] = [];
  if (c.restricciones?.tecnologias_prohibidas.includes(t.id)) out.push(`${c.nombre} no permite ${t.nombre}: ${c.restricciones.motivo}`);
  const z = c.zona;
  if (z && (lat < z.lat_min || lat > z.lat_max || lon < z.lon_min || lon > z.lon_max)) out.push(`En ${c.nombre} solo se puede desarrollar en ${z.nombre}.`);
  return out;
}

export function evaluateSite(ctx: SimContext, techId: string, lat: number, lon: number, to?: { lat: number; lon: number }): SiteEvaluation {
  const t = ctx.data.technologies[techId];
  const blank: SiteEvaluation = {
    ok: false, errors: [], cellIndex: -1, value: 0, layer: '', temperatureC: 25,
    extras: { rainMm: 0, relief: 0, distCoastKm: 0, depthM: 0, offshore: false, hydroIndex: 0, biomass: 0 }, restrictions: [],
  };
  if (!t) return { ...blank, errors: ['Tecnología desconocida.'] };
  blank.restrictions = siteRestrictionText(t);
  blank.layer = t.recurso ?? 'sin_recurso';
  const grid = ctx.grid;
  if (!grid) return { ...blank, errors: ['La grilla de recursos no está cargada.'] };
  if (!(Math.abs(lat) <= 90 && Math.abs(lon) <= 180)) return { ...blank, errors: ['Ubicación inválida.'] };
  const cell = grid.cell(lat, lon);
  const v = cell.values;
  const sea = t.sitio?.superficie === 'mar';
  const errors: string[] = [];
  let country = cell.country;
  let distCoast = v.dist_costa_km ?? 0;
  if (sea) {
    if (cell.land) errors.push('Esta tecnología se construye en el mar.');
    const near = grid.nearestCountry(lat, lon, 6);
    country = near?.country ?? null;
    if (near) distCoast = Math.max(distCoast, (near.cells - 0.5) * grid.res * KM_PER_DEG * 0.9);
  } else if (!cell.land || !country) errors.push('El sitio no está en tierra firme.');
  const c = country ? ctx.data.countries[country.code] : undefined;
  if (country && !c) errors.push(`Todavía no se puede desarrollar en ${country.nombre}.`);
  else if (!country && sea) errors.push('No hay ningún país cerca de este punto del mar.');
  const s = t.sitio;
  const depth = sea ? distCoast * (s?.profundidad_m_por_km ?? 1.5) : 0;
  const extras: SiteExtras = {
    rainMm: v.lluvia ?? 0, relief: v.relieve ?? 0, distCoastKm: distCoast, depthM: depth, offshore: sea,
    hydroIndex: v.hidro ?? 0, biomass: v.biomasa ?? 0,
  };
  const value = t.recurso ? v[t.recurso] ?? 0 : 1;
  if (t.recurso && !(value > 0)) errors.push('El sitio no tiene recurso para esta tecnología.');
  if (s) {
    if (t.recurso && s.recurso_min !== undefined && value < s.recurso_min) errors.push(`Recurso insuficiente: ${value.toFixed(1)} < ${s.recurso_min}.`);
    if (s.dist_costa_km_min !== undefined && distCoast < s.dist_costa_km_min) errors.push(`Demasiado cerca de la costa (${Math.round(distCoast)} km < ${s.dist_costa_km_min}).`);
    if (s.dist_costa_km_max !== undefined && distCoast > s.dist_costa_km_max) errors.push(`Demasiado lejos de la costa (${Math.round(distCoast)} km > ${s.dist_costa_km_max}).`);
    if (s.profundidad_max_m !== undefined && depth > s.profundidad_max_m) errors.push(`Demasiado profundo (≈${Math.round(depth)} m).`);
    if (s.relieve_min !== undefined && extras.relief < s.relieve_min) errors.push(`Terreno demasiado plano para embalses (relieve ${extras.relief.toFixed(2)} < ${s.relieve_min}).`);
    if (s.agua_indice_min !== undefined && extras.hydroIndex < s.agua_indice_min && !(s.agua_dist_costa_km !== undefined && distCoast <= s.agua_dist_costa_km)) errors.push('Sin agua suficiente para refrigeración/proceso (río o costa).');
  }
  if (c) errors.push(...countryAllows(c, t, lat, lon));
  if (t.transmision) {
    if (!to) errors.push('Una línea necesita el punto final.');
    else {
      const end = grid.cell(to.lat, to.lon);
      const ec = end.country ? ctx.data.countries[end.country.code] : undefined;
      if (!end.land || !end.country) errors.push('El extremo final no está en tierra firme.');
      else if (!ec) errors.push(`Todavía no se puede llegar a ${end.country.nombre}.`);
      else {
        const km = routeKm(lat, lon, to.lat, to.lon);
        extras.to = { lat: to.lat, lon: to.lon, countryCode: ec.iso3, km };
        const tr = t.transmision;
        if (km < tr.longitud_min_km || km > tr.longitud_max_km) errors.push(`Longitud ${Math.round(km)} km fuera de rango (${tr.longitud_min_km}–${tr.longitud_max_km} km).`);
        if (tr.interconexion && ec.iso3 === c?.iso3) errors.push('Una interconexión debe unir dos países.');
        if (!tr.interconexion && c && ec.iso3 !== c.iso3) errors.push('Una línea nacional no puede cruzar la frontera (usa una interconexión).');
        errors.push(...countryAllows(ec, t, to.lat, to.lon));
      }
    }
  }
  return {
    ok: errors.length === 0, errors, countryCode: c?.iso3, countryName: c?.nombre ?? country?.nombre, cellIndex: cell.index, value, layer: t.recurso ?? 'sin_recurso',
    temperatureC: v.temperatura ?? 25, extras, restrictions: blank.restrictions,
  };
}
