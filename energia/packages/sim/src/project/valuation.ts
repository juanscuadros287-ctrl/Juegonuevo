import type { GameState } from '../core/state';
import type { SimContext } from '../core/context';
import { npv } from '../finance/math';
import { findingCostUsd, permitApprovalProbability, permitCostUsd, studyCostUsd } from './outcomes';
import { applicablePermits, applicableStudies, permitGroupApproved, requiredStudyGroups, studyGroupDone } from './requirements';
import { projectEconomics } from './economics';
import { sellsEnergy } from '../tech/models';
import type { Project } from './types';

/** Valor contable del proyecto (activos, sin restar deuda). */
export function bookValue(p: Project): number {
  if (p.operation) return p.operation.grossAssetUsd - p.operation.accumulatedDepreciationUsd;
  if (p.construction) return p.devCostUsd + p.construction.spentUsd + p.construction.idcUsd;
  return p.devCostUsd;
}

/** Estudio representativo (el más barato) de un grupo aplicable. */
export function cheapestStudy(ctx: SimContext, p: Project, group: string) {
  const opts = applicableStudies(ctx, p).filter((s) => s.grupo === group);
  opts.sort((a, b) => studyCostUsd(a, p.mw) - studyCostUsd(b, p.mw));
  return opts[0];
}

/** Estudio que satisface el grupo y que el banco aceptaría (el de menor σ para medición de recurso). */
export function bankableStudy(ctx: SimContext, p: Project, group: string) {
  const opts = applicableStudies(ctx, p).filter((s) => s.grupo === group);
  if (opts.some((s) => s.sigma_recurso !== undefined)) {
    opts.sort((a, b) => (a.sigma_recurso ?? 1) - (b.sigma_recurso ?? 1));
    return opts[0];
  }
  return cheapestStudy(ctx, p, group);
}

/** Costos de desarrollo que faltan (estudios, permisos, asesores del banco), estimados. */
export function remainingDevCostUsd(ctx: SimContext, p: Project): { studiesUsd: number; permitsUsd: number; financingUsd: number; totalUsd: number } {
  let studiesUsd = 0, permitsUsd = 0, financingUsd = 0;
  if (!p.construction && !p.operation) {
    for (const g of requiredStudyGroups(ctx, p)) {
      if (studyGroupDone(ctx, p, g) || Object.values(p.studies).some((r) => r.status === 'en_curso' && ctx.data.studies[r.studyId]?.grupo === g)) continue;
      const s = bankableStudy(ctx, p, g);
      if (s) studiesUsd += studyCostUsd(s, p.mw);
    }
    for (const d of applicablePermits(ctx, p)) {
      const r = p.permits[d.id];
      if (r && r.status !== 'rechazado') continue;
      permitsUsd += permitCostUsd(d, p.mw);
    }
    for (const f of p.findings) if (f.status === 'abierto') studiesUsd += findingCostUsd(ctx.data.findings[f.id], p.mw);
    if (!p.financing || p.financing.status === 'fallido') {
      const l = ctx.data.countries[p.countryCode].finanzas.prestamistas[0];
      financingUsd += l.costo_asesores_usd.base;
    }
  }
  return { studiesUsd, permitsUsd, financingUsd, totalUsd: studiesUsd + permitsUsd + financingUsd };
}

/**
 * Probabilidad aproximada (analítica) de llegar a operación desde el estado actual.
 * Estudios: 1 − P(bloqueo)·(1 − P(éxito de mitigación)); permisos: aprobación con un reintento;
 * financiamiento ≈ 1 − (1 − p)²; construcción 0,98.
 */
export function successProbability(ctx: SimContext, p: Project): number {
  if (p.operation) return 1;
  if (p.construction) return 0.98;
  let prob = 1;
  for (const f of p.findings) {
    if (f.status === 'fatal') return 0;
    if (f.status === 'abierto' || f.status === 'en_mitigacion') prob *= ctx.data.findings[f.id].prob_exito_mitigacion ?? 0.5;
  }
  for (const g of requiredStudyGroups(ctx, p)) {
    if (studyGroupDone(ctx, p, g)) continue;
    const s = bankableStudy(ctx, p, g);
    if (!s) continue;
    const mit = (s.hallazgos ?? []).map((h) => ctx.data.findings[h]?.prob_exito_mitigacion ?? 0.5);
    const avgMit = mit.length ? mit.reduce((a, b) => a + b, 0) / mit.length : 1;
    prob *= 1 - s.resultados.bloqueo * (1 - avgMit);
  }
  for (const d of applicablePermits(ctx, p)) {
    if (permitGroupApproved(ctx, p, d.grupo)) continue;
    const pa = permitApprovalProbability(d);
    prob *= d.reintentable ? 1 - (1 - pa) * (1 - pa) : pa;
  }
  if (p.financing?.status !== 'cerrado') prob *= 0.97;
  return prob * 0.98;
}

/**
 * Valor de venta del proyecto (100 %): P(éxito)·(VP de la operación − CAPEX por gastar − desarrollo por gastar)
 * − deuda, descontado a la tasa de la etapa; piso = 30 % del costo de desarrollo; recorte del comprador 8 %.
 */
export function saleValueUsd(state: GameState, ctx: SimContext, p: Project): number {
  return saleValuation(state, ctx, p).valueUsd;
}

/**
 * Fase 5: valoración de venta como la haría un comprador real. Si el proyecto vende al spot (sin PPA firmado), el
 * comprador recorta la curva de precios (`comprador.recorte_precio_merchant`) y exige una prima de retorno
 * (`comprador.prima_merchant`) por el riesgo de precio y de canibalización.
 */
export function saleValuation(state: GameState, ctx: SimContext, p: Project): { valueUsd: number; merchant: boolean; discountRate: number; pvOpsUsd: number } {
  const tech0 = ctx.data.technologies[p.techId];
  const buyer = ctx.data.power?.comprador;
  const merchant = !!buyer && sellsEnergy(tech0) && p.ppa?.status !== 'firmado' && !p.contractId;
  const eco = projectEconomics(state, ctx, p, merchant ? { spotHaircut: buyer!.recorte_precio_merchant } : {});
  const tech = ctx.data.technologies[p.techId];
  const life = Math.round(tech.vida_util_anos.base);
  let age = 0;
  if (p.operation) age = Math.floor((state.tick - p.operation.codTick) / 365);
  const opsFlows = [0, ...eco.model.projectFlows.slice(1 + age, 1 + life)];
  const rate = eco.wacc + (merchant ? buyer!.prima_merchant : 0);
  const pvOps = npv(rate, opsFlows);
  const remainingCapex = p.operation ? 0 : p.construction ? Math.max(0, p.construction.budgetUsd + p.construction.overrunUsd - p.construction.spentUsd) : eco.investmentUsd;
  const remainingDev = remainingDevCostUsd(ctx, p).totalUsd;
  const debt = p.debt?.outstandingUsd ?? 0;
  const value = successProbability(ctx, p) * (pvOps - remainingCapex - remainingDev) - debt;
  const floor = p.operation || p.construction ? 0 : 0.3 * p.devCostUsd;
  return { valueUsd: Math.max(floor, value) * 0.92, merchant, discountRate: rate, pvOpsUsd: pvOps };
}
