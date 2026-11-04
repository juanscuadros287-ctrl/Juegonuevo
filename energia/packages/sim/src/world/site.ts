import { Rng, hashString, seedStream } from '../core/rng';
import type { TechnologyDef } from '../data/types';

/** Ubicación de un sitio redondeada a 0,01° (≈1 km): dos proyectos en el mismo sitio comparten recurso. */
export function siteKey(lat: number, lon: number): string {
  return `${Math.round(lat * 100)}:${Math.round(lon * 100)}`;
}

/**
 * Factor oculto recurso_real / recurso_celda, determinista por (semilla de partida, capa, sitio).
 * Normal(1, σ) truncada a ±3σ. No usa los flujos RNG del estado: no depende del orden de creación.
 */
export function hiddenResourceFactor(seed: number, layer: string, lat: number, lon: number, sigma: number): number {
  const rng = new Rng(seedStream((seed ^ hashString(`${layer}@${siteKey(lat, lon)}`)) >>> 0, 'site'));
  const z = Math.max(-3, Math.min(3, rng.normal()));
  return Math.max(0.3, 1 + sigma * z);
}

/** z de la normal estándar para P90 (excedido el 90 % del tiempo). */
export const Z_P90 = 1.2816;

/** Recurso P90 a partir de P50 y σ relativa. */
export function p90(value: number, sigma: number): number {
  return value * Math.max(0, 1 - Z_P90 * sigma);
}

export function siteSigma(tech: TechnologyDef): number {
  return tech.sigma_recurso_sitio;
}
