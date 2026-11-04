import { z } from 'zod';
import type { SimConfig } from '@voltaje/sim';
import { countrySchema, gameSchema, layerSchema, type CountryDef, type GameYaml, type LayerDef } from './schemas';

export interface GameData {
  game: GameYaml;
  layers: LayerDef[];
  countries: Record<string, CountryDef>;
  sim: SimConfig;
}

export class DataError extends Error {}

function check<T>(schema: z.ZodType<T>, value: unknown, file: string): T {
  const r = schema.safeParse(value);
  if (!r.success) {
    const issues = r.error.issues.map((i) => `  · ${i.path.join('.') || '(raíz)'}: ${i.message}`).join('\n');
    throw new DataError(`Error en ${file}:\n${issues}`);
  }
  return r.data;
}

/** Valida los datos crudos (ya parseados de YAML) y arma la configuración del motor. */
export function buildGameData(raw: { game: unknown; layers: unknown; countries: Record<string, unknown> }): GameData {
  const game = check(gameSchema, raw.game, 'game.yaml');
  const layers = check(z.array(layerSchema), raw.layers, 'layers.yaml');
  const countries: Record<string, CountryDef> = {};
  for (const [file, value] of Object.entries(raw.countries)) {
    const c = check(countrySchema, value, file);
    countries[c.iso3] = c;
  }
  if (!countries[game.pais_inicial]) throw new DataError(`game.yaml: el país inicial ${game.pais_inicial} no tiene archivo en countries/`);
  return {
    game,
    layers,
    countries,
    sim: {
      dataVersion: game.version_datos,
      startDate: game.fecha_inicio,
      startCountry: game.pais_inicial,
      company: { cashUsd: game.empresa_inicial.caja_usd, monthlyFixedCostUsd: game.empresa_inicial.gastos_fijos_mensuales_usd },
    },
  };
}
