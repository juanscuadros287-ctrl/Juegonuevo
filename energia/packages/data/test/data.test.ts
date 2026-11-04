import { describe, expect, it } from 'vitest';
import { gameData, buildGameData, anchorsSchema, DataError } from '../src';
import anclas from '../resources/anclas.yaml';
import game from '../game.yaml';
import layers from '../layers.yaml';

describe('Datos del juego', () => {
  it('todos los YAML cumplen su esquema', () => {
    expect(gameData.game.pais_inicial).toBe('PAN');
    expect(gameData.countries.PAN.nombre).toBe('Panamá');
    expect(gameData.layers.length).toBeGreaterThanOrEqual(7);
    expect(anchorsSchema.safeParse(anclas).success).toBe(true);
  });

  it('un valor sin fuente ni supuesto es rechazado', () => {
    const bad = structuredClone(gameData.countries.PAN) as any;
    delete bad.inflacion_anual.fuente;
    expect(() => buildGameData({ game, layers, countries: { 'PAN.yaml': bad } })).toThrow(DataError);
  });

  it('el país inicial debe existir', () => {
    expect(() => buildGameData({ game: { ...(game as object), pais_inicial: 'XXX' }, layers, countries: {} })).toThrow(/país inicial/);
  });
});
