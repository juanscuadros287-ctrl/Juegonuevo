import type { GameState } from './state';
import type { SimContext } from './context';
import type { SimEvent } from './events';
import { applyProjectCommand, type ProjectCommand } from '../project/commands';
import { applyBidCommand, type BidCommand } from '../business/bids';
import { applyContractCommand, type ContractCommand } from '../business/contracts';
import { applyResearchCommand, type ResearchCommand } from '../business/research';
import { applyPresenceCommand, type PresenceCommand } from '../business/presence';

/**
 * Toda acción del jugador (y de la IA) es un comando. La UI nunca modifica el estado directamente.
 * Los comandos se aplican al inicio del siguiente tick, en el orden recibido.
 */
export type Command =
  | { type: 'renameCompany'; name: string }
  | { type: 'setFocusCountry'; countryCode: string }
  | ProjectCommand
  | BidCommand
  | ContractCommand
  | ResearchCommand
  | PresenceCommand;

export type CommandResult = { ok: true } | { ok: false; error: string };

/**
 * Aplica un comando. `events` recibe los eventos que produzca (p. ej. proyecto creado).
 * Los comandos de proyecto necesitan `ctx` (datos y, para crear proyectos, la grilla).
 */
export function applyCommand(state: GameState, cmd: Command, ctx?: SimContext, events: SimEvent[] = []): CommandResult {
  if (state.finance?.bankrupt) return { ok: false, error: 'La empresa quebró: la partida terminó.' };
  switch (cmd.type) {
    case 'renameCompany': {
      const name = cmd.name.trim();
      if (name.length < 2 || name.length > 40) return { ok: false, error: 'El nombre debe tener entre 2 y 40 caracteres.' };
      state.company.name = name;
      return { ok: true };
    }
    case 'setFocusCountry': {
      if (!/^[A-Z0-9]{3}$/.test(cmd.countryCode)) return { ok: false, error: 'Código de país inválido.' };
      state.focus.countryCode = cmd.countryCode;
      return { ok: true };
    }
    case 'submitBid':
    case 'withdrawBid':
      return applyBidCommand(state, ctx, cmd, events);
    case 'assignContractProject':
      return applyContractCommand(state, ctx, cmd, events);
    case 'startResearch':
    case 'queueResearch':
    case 'cancelResearch':
    case 'setResearchBudget':
      return applyResearchCommand(state, ctx, cmd, events);
    case 'openPresence':
    case 'closePresence':
      return applyPresenceCommand(state, ctx, cmd, events);
    default:
      return applyProjectCommand(state, ctx, cmd, events);
  }
}
