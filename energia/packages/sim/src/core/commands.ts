import type { GameState } from './state';

/**
 * Toda acción del jugador (y de la IA) es un comando. La UI nunca modifica el estado directamente.
 * Los comandos se aplican al inicio del siguiente tick, en el orden recibido.
 */
export type Command =
  | { type: 'renameCompany'; name: string }
  | { type: 'setFocusCountry'; countryCode: string };

export type CommandResult = { ok: true } | { ok: false; error: string };

export function applyCommand(state: GameState, cmd: Command): CommandResult {
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
    default: {
      const never: never = cmd;
      return { ok: false, error: `Comando desconocido: ${JSON.stringify(never)}` };
    }
  }
}
