import type { GameState } from '../core/state';
import { PLAYER_ID } from './types';

/** Pedido de la UI (Fase 3): historial mensual de cuota de mercado (MW en operación por actor, últimos 120 meses). */
export function recordMarketShare(state: GameState, year: number, month: number) {
  if (!state.market) return;
  const mw: Record<string, number> = { [PLAYER_ID]: 0 };
  for (const p of state.projects) if (p.operation && p.stage === 'operacion') mw[PLAYER_ID] += p.mw;
  for (const c of state.competitors ?? []) {
    mw[c.id] = 0;
    for (const p of c.projects) if (p.operation && p.stage === 'operacion') mw[c.id] += p.mw;
  }
  const h = (state.market.shareHistory ??= []);
  h.push({ year, month, mw });
  if (h.length > 120) h.splice(0, h.length - 120);
}
