import type { Rng } from '../core/rng';
import type { Dist, FindingDef, PermitDef, StudyDef, StudyOutcome } from '../data/types';

/**
 * Sorteos compartidos por la simulación (step) y el verificador de viabilidad (Monte Carlo),
 * para que ambos usen exactamente las mismas probabilidades.
 */

/** Triangular(min, base, max). Si faltan min/max se usa ±0 (valor fijo). */
export function drawDist(rng: Rng, d: Dist): number {
  const lo = d.min ?? d.base, hi = d.max ?? d.base;
  if (hi <= lo) return d.base;
  return rng.triangular(lo, Math.min(Math.max(d.base, lo), hi), hi);
}

export function drawDays(rng: Rng, d: Dist): number {
  return Math.max(1, Math.round(drawDist(rng, d)));
}

export function studyCostUsd(s: StudyDef, mw: number): number {
  return s.costo_fijo_usd.base + s.costo_usd_mw.base * mw;
}

export function permitCostUsd(p: PermitDef, mw: number): number {
  return p.costo_fijo_usd.base + p.costo_usd_mw.base * mw;
}

export function findingCostUsd(f: FindingDef, mw: number): number {
  return (f.costo_mitigacion_fijo_usd ?? 0) + (f.costo_mitigacion_usd_mw ?? 0) * mw;
}

export interface StudyDraw { outcome: StudyOutcome; capexFactor?: number; findingId?: string }

/** Resultado de un estudio que no es de medición de recurso. */
export function drawStudyOutcome(rng: Rng, s: StudyDef, findings: Record<string, FindingDef>, mod?: { block: number; worse: number }): StudyDraw {
  const u = rng.next();
  // Fase 6: el equipo de recurso (geólogos, ingenieros de recurso) reduce bloqueos y sorpresas (mod ≤ 1).
  const r = mod ? { ...s.resultados, bloqueo: s.resultados.bloqueo * mod.block, peor: s.resultados.peor * mod.worse } : s.resultados;
  if (u < r.bloqueo && s.hallazgos?.length) {
    const opts = s.hallazgos.map((id) => findings[id]).filter(Boolean);
    const total = opts.reduce((a, f) => a + f.peso, 0);
    let x = rng.next() * total;
    let pick = opts[opts.length - 1];
    for (const f of opts) { x -= f.peso; if (x < 0) { pick = f; break; } }
    return { outcome: 'bloqueo', findingId: pick.id };
  }
  if (u < r.bloqueo + r.peor) return { outcome: 'peor', capexFactor: s.peor_capex_factor ? drawDist(rng, s.peor_capex_factor) : 1 };
  return { outcome: 'normal' };
}

/** Fase 6: multiplicadores del equipo y la reputación sobre las probabilidades de una autoridad (renormalizadas). */
export interface PermitProbMod { approve: number; reject: number; info: number }

export function permitProbs(p: PermitDef, mod?: PermitProbMod): { aprobado: number; rechazado: number; info_adicional: number } {
  if (!mod) return p.prob;
  let a = p.prob.aprobado * mod.approve, r = p.prob.rechazado * Math.max(0, mod.reject), i = p.prob.info_adicional * Math.max(0, mod.info);
  // La aprobación no pasa del 98 %: siempre queda riesgo regulatorio.
  const tot = a + r + i;
  a /= tot; r /= tot; i /= tot;
  if (a > 0.98) { const rest = r + i; const f = rest > 0 ? 0.02 / rest : 0; a = 0.98; r *= f; i *= f; if (!rest) r = 0.02; }
  return { aprobado: a, rechazado: r, info_adicional: i };
}

export type PermitDecision = 'aprobado' | 'rechazado' | 'info_adicional';

/**
 * Decisión de la autoridad. Si ya se agotaron los pedidos de información, se renormaliza entre
 * aprobado y rechazado.
 */
export function drawPermitDecision(rng: Rng, p: PermitDef, infoRequests: number, mod?: PermitProbMod): PermitDecision {
  const { aprobado, rechazado, info_adicional } = permitProbs(p, mod);
  const allowInfo = infoRequests < p.max_intentos_info;
  const total = aprobado + rechazado + (allowInfo ? info_adicional : 0);
  const u = rng.next() * total;
  if (u < aprobado) return 'aprobado';
  if (u < aprobado + rechazado) return 'rechazado';
  return 'info_adicional';
}

/** Probabilidad final de aprobación de una solicitud (con los pedidos de información incluidos). */
export function permitApprovalProbability(p: PermitDef, mod?: PermitProbMod): number {
  // Cada pedido de info vuelve a sortear; tras max_intentos_info se renormaliza.
  const { aprobado: a, rechazado: r, info_adicional: i } = permitProbs(p, mod);
  let pInfoChain = 1, pa = 0;
  for (let k = 0; k < p.max_intentos_info; k++) { pa += pInfoChain * a; pInfoChain *= i; }
  pa += pInfoChain * (a / (a + r));
  return pa;
}

/** Fase 4 (geotermia): resultado de una campaña de pozos exploratorios. */
export interface WellCampaign { dry: number; low: number; productive: number }

/** Sorteo de `n` pozos con probabilidades (seco, baja entalpía); compartido por la simulación y el Monte Carlo. */
export function drawWells(rng: Rng, n: number, pDry: number, pLow: number): WellCampaign {
  const out = { dry: 0, low: 0, productive: 0 };
  for (let i = 0; i < n; i++) {
    const u = rng.next();
    if (u < pDry) out.dry++;
    else if (u < pDry + pLow) out.low++;
    else out.productive++;
  }
  return out;
}
