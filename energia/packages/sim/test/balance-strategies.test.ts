import { beforeAll, describe, expect, it } from 'vitest';
import { runStrategy, typicalIrrTable, type RunResult } from './balance';

/**
 * Fase 6: balance global (ver docs/BALANCE.md). 15 años con el jugador en piloto automático contra las 5 IA.
 * Condiciones (en ≥ 3 semillas cada una): pasivo quiebra en pocos años; solar conservador sobrevive y crece de forma
 * moderada; agresivo puede crecer mucho o quebrar; diversificado internacional es viable y se expande; las IA terminan
 * con resultados variados y ninguna domina siempre; TIR de proyectos típicos en rangos reales.
 */
const YEARS = 15;
const runs: Record<string, RunResult[]> = {};

beforeAll(() => {
  runs.pasivo = [1, 2, 3].map((s) => runStrategy('pasivo', s, YEARS));
  runs.solar_conservador = [1, 3, 5].map((s) => runStrategy('solar_conservador', s, YEARS));
  runs.agresivo = [1, 2, 3, 4, 5, 6].map((s) => runStrategy('agresivo', s, YEARS));
  runs.diversificado = [1, 3, 5].map((s) => runStrategy('diversificado', s, YEARS));
}, 300_000);

describe('Balance global (15 años, varias semillas)', () => {
  it('pasivo: pierde dinero cada año y quiebra en pocos años', () => {
    for (const r of runs.pasivo) {
      expect(r.bankrupt).toBe(true);
      expect(r.bankruptYear!).toBeLessThan(8);
      expect(r.bankruptYear!).toBeGreaterThan(3);
      for (let i = 1; i < r.equityByYear.length; i++) expect(r.equityByYear[i]).toBeLessThan(r.equityByYear[i - 1]);
    }
  });

  it('solar conservador: sobrevive 15 años y crece de forma moderada (sin multiplicar por más de 15)', () => {
    for (const r of runs.solar_conservador) {
      expect(r.bankrupt).toBe(false);
      const m = r.finalEquityUsd / r.initialCashUsd;
      expect(m).toBeGreaterThan(1.5);
      expect(m).toBeLessThan(15);
    }
  });

  it('agresivo apalancado: alta dispersión (alguna partida quiebra y alguna crece mucho)', () => {
    const mult = runs.agresivo.map((r) => (r.bankrupt ? 0 : r.finalEquityUsd / r.initialCashUsd));
    expect(runs.agresivo.filter((r) => r.bankrupt).length).toBeGreaterThanOrEqual(2);
    expect(Math.max(...mult)).toBeGreaterThan(5);
  });

  it('diversificado internacional: viable con equipo, abre otros países y termina con más patrimonio', () => {
    for (const r of runs.diversificado) {
      expect(r.bankrupt).toBe(false);
      expect(r.countries).toBeGreaterThanOrEqual(2);
      expect(r.headcount).toBeGreaterThanOrEqual(1);
      expect(r.finalEquityUsd / r.initialCashUsd).toBeGreaterThan(3);
    }
  });

  it('las IA terminan con resultados variados y ninguna domina siempre', () => {
    const all = [...runs.solar_conservador, ...runs.diversificado, ...runs.agresivo.filter((r) => !r.bankrupt)];
    const winners = new Set(all.map((r) => [...r.ai].sort((a, b) => b.equityMultiple - a.equityMultiple)[0].name));
    expect(winners.size).toBeGreaterThanOrEqual(2);
    for (const r of all) {
      const m = r.ai.map((a) => a.equityMultiple);
      expect(Math.max(...m) - Math.min(...m)).toBeGreaterThan(0.3);
      for (const x of m) expect(x).toBeLessThan(12);
    }
    expect(all.some((r) => r.ai.some((a) => a.bankrupt))).toBe(true);
  });

  it('TIR del capital de proyectos típicos en rangos reales por tecnología y país', () => {
    // Combinaciones que el mercado real desarrolla (sitio típico del país, mercado de referencia de la Fase 4).
    // Rango 3–22 %: IEA Cost of Capital Observatory 2024 (TIR del capital de renovables ≈ 8–16 % en emergentes, 5–9 % en
    // mercados maduros con PPA); los mercados caros y con buen recurso (Panamá, Rep. Dominicana) quedan arriba.
    const cases: [string, string[]][] = [
      ['solar_fv', ['PAN', 'CHL', 'MEX', 'DOM', 'KEN', 'ESP', 'USA', 'BRA']],
      ['eolica_tierra', ['CHL', 'MEX', 'USA', 'PAN', 'CRI', 'ESP']],
      ['geotermica', ['KEN', 'IDN', 'PHL', 'CRI']],
      ['hidro_pasada', ['COL', 'PAN', 'CRI', 'MEX']],
      ['gas_natural', ['USA', 'MEX']],
    ];
    for (const [t, cs] of cases) for (const r of typicalIrrTable([t], cs)) {
      expect(r.irr, `${t} ${r.countryCode}`).not.toBeNull();
      expect(r.irr!, `${t} ${r.countryCode}`).toBeGreaterThan(0.03);
      expect(r.irr!, `${t} ${r.countryCode}`).toBeLessThan(0.22);
    }
    // La eólica en un país sin buen viento (Colombia fuera de La Guajira: sitio típico) no es negocio: así debe ser.
    expect(typicalIrrTable(['eolica_tierra'], ['COL'])[0].irr ?? -1).toBeLessThan(0.03);
  });
});
