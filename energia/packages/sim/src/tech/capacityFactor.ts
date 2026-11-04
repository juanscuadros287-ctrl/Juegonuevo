import type { TechnologyDef } from '../data/types';

/**
 * Factor de capacidad (fracción del año a potencia nominal, base AC) a partir del recurso del sitio.
 *
 * Solar FV:  FC = GHI·PR·f_T·g_seg / 24
 *   GHI en kWh/m²/día (equivale a horas solares pico), PR sin temperatura,
 *   f_T = 1 + γ·(T_amb + ΔT_celda − T_ref) (γ < 0), g_seg = ganancia del seguidor de un eje.
 * Eólica:   FC = (1 − pérdidas)·∫ P(v)·f_Weibull(v; k, c) dv / P_nom
 *   v media a 100 m llevada a la altura de buje con ley potencial (α), c = v̄ / Γ(1 + 1/k),
 *   curva de potencia genérica de una turbina de referencia: P = ½ρA·Cp·v³ limitada a P_nom
 *   entre v_arranque y v_corte; ρ corregida por temperatura.
 */
export function capacityFactor(tech: TechnologyDef, resource: number, temperatureC = 25): number {
  switch (tech.modelo_fc) {
    case 'solar_fv': return solarCapacityFactor(tech, resource, temperatureC);
    case 'eolica': return windCapacityFactor(tech, resource, temperatureC);
    case 'fijo': return tech.factor_capacidad_ref.base;
  }
}

export function solarCapacityFactor(tech: TechnologyDef, ghi: number, temperatureC: number): number {
  const s = tech.solar;
  if (!s) throw new Error(`${tech.id}: falta el bloque "solar"`);
  const fT = 1 + s.coef_temp_por_c * (temperatureC + s.delta_celda_c - s.t_ref_c);
  return Math.max(0, (ghi * s.pr * fT * s.ganancia_seguidor) / 24);
}

/** Γ(x) por aproximación de Lanczos. */
export function gamma(x: number): number {
  const g = 7;
  const c = [0.99999999999980993, 676.5203681218851, -1259.1392167224028, 771.32342877765313, -176.61502916214059,
    12.507343278686905, -0.13857109526572012, 9.9843695780195716e-6, 1.5056327351493116e-7];
  if (x < 0.5) return Math.PI / (Math.sin(Math.PI * x) * gamma(1 - x));
  x -= 1;
  let a = c[0];
  const t = x + g + 0.5;
  for (let i = 1; i < g + 2; i++) a += c[i] / (x + i);
  return Math.sqrt(2 * Math.PI) * Math.pow(t, x + 0.5) * Math.exp(-t) * a;
}

/** Potencia (fracción de la nominal) de la turbina de referencia a velocidad v. */
export function turbinePowerFraction(tech: TechnologyDef, v: number, rho = 1.225): number {
  const w = tech.eolica!;
  if (v < w.v_arranque || v > w.v_corte) return 0;
  const area = Math.PI * (w.diametro_rotor_m / 2) ** 2;
  const p = 0.5 * rho * area * w.cp * v ** 3; // W
  return Math.min(1, p / (w.turbina_mw * 1e6));
}

export function windCapacityFactor(tech: TechnologyDef, meanSpeed100m: number, temperatureC: number): number {
  const w = tech.eolica;
  if (!w) throw new Error(`${tech.id}: falta el bloque "eolica"`);
  if (meanSpeed100m <= 0) return 0;
  const vHub = meanSpeed100m * Math.pow(w.altura_buje_m / 100, w.cizalle_alfa);
  const rho = 1.225 * (288.15 / (temperatureC + 273.15));
  const k = w.weibull_k;
  const c = vHub / gamma(1 + 1 / k);
  let acc = 0;
  const dv = 0.05;
  for (let v = dv / 2; v < 35; v += dv) {
    const pdf = (k / c) * Math.pow(v / c, k - 1) * Math.exp(-Math.pow(v / c, k));
    acc += turbinePowerFraction(tech, v, rho) * pdf * dv;
  }
  return acc * (1 - w.perdidas);
}
