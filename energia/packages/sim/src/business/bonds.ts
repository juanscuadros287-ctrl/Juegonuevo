import type { GameState } from '../core/state';
import type { SimContext } from '../core/context';
import { postCash } from '../finance/company';

/**
 * Garantías bancarias (de seriedad de oferta y de cumplimiento). El banco exige caja en garantía
 * (`colateral_frac` del valor) y cobra una comisión anual sobre el valor. Si se ejecuta, se pierde el
 * valor completo: el colateral y, si no alcanza, el resto en efectivo.
 */
export function collateralFrac(ctx: SimContext): number {
  return ctx.data.clients?.garantias.colateral_frac ?? 1;
}

export function bondCollateral(ctx: SimContext, faceUsd: number): number {
  return faceUsd * collateralFrac(ctx);
}

export function postBond(state: GameState, ctx: SimContext, faceUsd: number, concept: string) {
  const c = bondCollateral(ctx, faceUsd);
  if (c <= 0) return;
  postCash(state, 'garantias', -c, concept);
  state.business.restrictedCashUsd += c;
}

export function releaseBond(state: GameState, ctx: SimContext, faceUsd: number, concept: string) {
  const c = Math.min(bondCollateral(ctx, faceUsd), state.business.restrictedCashUsd);
  if (c <= 0) return;
  state.business.restrictedCashUsd -= c;
  postCash(state, 'garantias', c, concept);
}

export function executeBond(state: GameState, ctx: SimContext, faceUsd: number, concept: string) {
  releaseBond(state, ctx, faceUsd, `${concept} (liberación del colateral)`);
  postCash(state, 'garantias_ejecutadas', -faceUsd, concept);
}

/** Comisión mensual del banco sobre las garantías vigentes. */
export function bondFeesMonthly(state: GameState, ctx: SimContext) {
  const r = ctx.data.clients?.garantias.comision_anual ?? 0;
  const face = state.business.restrictedCashUsd / Math.max(1e-9, collateralFrac(ctx));
  if (face > 0 && r > 0) postCash(state, 'garantias_comision', -face * r / 12, 'Comisión de garantías bancarias');
}
