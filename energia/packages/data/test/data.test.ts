import { describe, expect, it } from 'vitest';
import { gameData, buildGameData, anchorsSchema, DataError } from '../src';
import anclas from '../resources/anclas.yaml';
import game from '../game.yaml';
import layers from '../layers.yaml';
import studies from '../studies.yaml';
import suppliers from '../suppliers.yaml';
import solar from '../technologies/solar_fv.yaml';
import eolica from '../technologies/eolica_tierra.yaml';
import pan from '../countries/PAN.yaml';

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

describe('Datos de la Fase 2', () => {
  const raw = () => structuredClone({ game, layers, countries: { 'PAN.yaml': pan }, technologies: { 'solar_fv.yaml': solar, 'eolica_tierra.yaml': eolica }, studies, suppliers }) as any;

  it('tecnologías, estudios, proveedores y Panamá cargan y se cruzan bien', () => {
    const d = gameData.simData;
    expect(Object.keys(d.technologies).sort()).toEqual(['eolica_tierra', 'solar_fv']);
    expect(Object.keys(d.studies).length).toBeGreaterThanOrEqual(9);
    expect(Object.values(d.suppliers).filter((s) => s.tipo === 'epc').length).toBeGreaterThanOrEqual(2);
    for (const t of ['solar_fv', 'eolica_tierra']) {
      expect(Object.values(d.suppliers).filter((s) => s.tipo === 'equipos' && s.tecnologias.includes(t)).length).toBeGreaterThanOrEqual(2);
    }
    const p = d.countries.PAN;
    expect(p.impuestos.renta.base).toBe(0.25);
    expect(p.permisos.map((x) => x.autoridad).join(' ')).toMatch(/MiAmbiente.*ETESA|ETESA.*MiAmbiente/);
    expect(p.permisos.some((x) => x.autoridad === 'ASEP')).toBe(true);
    expect(p.ppa.canales.map((c) => c.id)).toEqual(['licitacion_etesa', 'gran_cliente']);
    expect(p.finanzas.prestamistas.map((l) => l.tipo).sort()).toEqual(['comercial', 'desarrollo']);
    expect(buildGameData(raw()).simData.technologies.solar_fv.capex_usd_kw.base).toBe(d.technologies.solar_fv.capex_usd_kw.base);
  });

  it('rangos realistas de CAPEX (IRENA/NREL)', () => {
    const d = gameData.simData.technologies;
    expect(d.solar_fv.capex_usd_kw.base).toBeGreaterThan(600);
    expect(d.solar_fv.capex_usd_kw.base).toBeLessThan(1500);
    expect(d.eolica_tierra.capex_usd_kw.base).toBeGreaterThan(1000);
    expect(d.eolica_tierra.capex_usd_kw.base).toBeLessThan(2200);
  });

  it('rechaza un CAPEX sin fuente', () => {
    const r = raw(); delete r.technologies['solar_fv.yaml'].capex_usd_kw.fuente;
    expect(() => buildGameData(r)).toThrow(/solar_fv.yaml[\s\S]*capex_usd_kw/);
  });

  it('rechaza probabilidades que no suman 1', () => {
    const r = raw(); r.countries['PAN.yaml'].permisos[0].prob.aprobado = 0.5;
    expect(() => buildGameData(r)).toThrow(/sumar 1/);
    const r2 = raw(); r2.studies.estudios[4].resultados.peor = 0.5;
    expect(() => buildGameData(r2)).toThrow(/sumar 1/);
  });

  it('rechaza hitos que no suman 1 y min > base', () => {
    const r = raw(); r.technologies['eolica_tierra.yaml'].hitos_construccion[0].fraccion = 0.5;
    expect(() => buildGameData(r)).toThrow(/hitos/);
    const r2 = raw(); r2.technologies['solar_fv.yaml'].vida_util_anos.min = 50;
    expect(() => buildGameData(r2)).toThrow(/min ≤ base/);
  });

  it('rechaza referencias rotas entre archivos', () => {
    const r = raw(); r.countries['PAN.yaml'].permisos[0].requiere.permisos = ['no_existe'];
    expect(() => buildGameData(r)).toThrow(/no_existe/);
    const r2 = raw(); r2.studies.estudios[4].hallazgos = ['ovni'];
    expect(() => buildGameData(r2)).toThrow(/ovni/);
    const r3 = raw(); r3.technologies['solar_fv.yaml'].estudios_requeridos.push('astrologia');
    expect(() => buildGameData(r3)).toThrow(/astrologia/);
  });
});
