import type { SimContext } from '../core/context';
import type { CountrySimDef } from '../data/types';

/**
 * Precio spot simple (Fase 2): media del país × perfil mensual (hidrología) × inflación acumulada.
 * Interfaz estable para la Fase 5, que lo reemplazará por despacho horario (merit order).
 */
export interface SpotMarket {
  priceUsdMwh(countryCode: string, year: number, month: number): number;
}

export function normalizedProfile(profile: readonly number[] | undefined): number[] {
  if (!profile || profile.length !== 12) return new Array(12).fill(1);
  const mean = profile.reduce((a, b) => a + b, 0) / 12;
  return profile.map((x) => x / mean);
}

export function simpleSpotMarket(ctx: SimContext, startYear: number): SpotMarket {
  return {
    priceUsdMwh(countryCode, year, month) {
      const c = ctx.data.countries[countryCode];
      if (!c) return 0;
      return spotPrice(c, startYear, year, month);
    },
  };
}

export function spotPrice(c: CountrySimDef, startYear: number, year: number, month: number): number {
  const prof = normalizedProfile(c.mercado.perfil_spot_mensual);
  const infl = Math.pow(1 + c.inflacion_anual.base, Math.max(0, year - startYear));
  return c.mercado.precio_spot_medio_usd_mwh.base * prof[month - 1] * infl;
}

/**
 * Factor de captura: precio medio ponderado por la producción / precio medio simple.
 * >1 si la planta produce más en los meses caros (solar y viento en la estación seca de Panamá).
 */
export function captureFactor(c: CountrySimDef, layer: string | undefined): number {
  const price = normalizedProfile(c.mercado.perfil_spot_mensual);
  const res = normalizedProfile(layer ? c.perfil_recurso_mensual[layer] : undefined);
  let s = 0;
  for (let m = 0; m < 12; m++) s += price[m] * res[m];
  return s / 12;
}
