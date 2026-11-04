import { describe, expect, it } from 'vitest';
import { createNewGame, currentDate, deserialize, serialize, stateHash, step, SAVE_VERSION, type Command, type SimConfig, formatDate } from '../src';
import { ctx, newGame, runWithPilot, SITES } from './helpers';

const config: SimConfig = {
  dataVersion: 1,
  startDate: '2026-01-01',
  startCountry: 'PAN',
  company: { cashUsd: 750_000, monthlyFixedCostUsd: 18_500 },
};

function run(days: number, seed = 123, commandsAt: Record<number, Command[]> = {}) {
  const s = createNewGame(config, { seed, companyName: 'Prueba S.A.' });
  for (let d = 0; d < days; d++) step(s, commandsAt[d] ?? []);
  return s;
}

describe('Calendario', () => {
  it('avanza días y cruza años bisiestos', () => {
    const s = run(365 + 365 + 31 + 29); // 2026, 2027, ene-2028, feb-2028 (bisiesto)
    expect(currentDate(s)).toEqual({ year: 2028, month: 3, day: 1 });
  });
  it('formatea fechas en español', () => {
    expect(formatDate({ year: 2026, month: 3, day: 5 })).toBe('5 de marzo de 2026');
    expect(formatDate({ year: 2026, month: 3, day: 5 }, true)).toBe('5 mar 2026');
  });
});

describe('Economía base', () => {
  it('cobra los gastos fijos cada mes (nada es gratis)', () => {
    const s = run(365);
    expect(s.company.cashUsd).toBe(750_000 - 12 * 18_500);
  });
  it('avisa cuando la caja queda negativa', () => {
    const s = createNewGame(config, { seed: 1, companyName: 'X Corp' });
    s.company.cashUsd = 10_000;
    const events = [];
    for (let d = 0; d < 31; d++) events.push(...step(s));
    expect(events.some((e) => e.type === 'cashNegative')).toBe(true);
  });
  it('emite eventos de mes y año', () => {
    const s = createNewGame(config, { seed: 1, companyName: 'X Corp' });
    const ev = [];
    for (let d = 0; d < 366; d++) ev.push(...step(s));
    expect(ev.filter((e) => e.type === 'newMonth')).toHaveLength(12);
    expect(ev.filter((e) => e.type === 'newYear')).toHaveLength(1);
  });
});

describe('Comandos', () => {
  it('renombrar la empresa valida el nombre', () => {
    const s = createNewGame(config, { seed: 1, companyName: 'X Corp' });
    const ev = step(s, [{ type: 'renameCompany', name: 'A' }]);
    expect(ev[0].type).toBe('commandRejected');
    step(s, [{ type: 'renameCompany', name: 'Energía del Istmo' }]);
    expect(s.company.name).toBe('Energía del Istmo');
  });
});

describe('Determinismo', () => {
  it('misma semilla + mismos comandos ⇒ mismo estado tras 10 años', () => {
    const cmds = { 100: [{ type: 'renameCompany', name: 'Istmo Power' } as Command] };
    expect(stateHash(run(3650, 77, cmds))).toBe(stateHash(run(3650, 77, cmds)));
  });
  it('semillas distintas ⇒ estado distinto', () => {
    expect(stateHash(run(10, 1))).not.toBe(stateHash(run(10, 2)));
  });
});

describe('Guardado y carga', () => {
  it('guardar → cargar → seguir = no guardar', () => {
    const a = run(400, 5);
    const b = deserialize(serialize(a));
    for (let d = 0; d < 800; d++) { step(a); step(b); }
    expect(stateHash(b)).toBe(stateHash(a));
  });
  it('rechaza archivos dañados, ajenos o de versiones futuras', () => {
    expect(() => deserialize('{no json')).toThrow(/dañado/);
    expect(() => deserialize('{"format":"otro"}')).toThrow(/no es una partida/);
    const s = JSON.parse(serialize(run(1)));
    s.saveVersion = 999;
    expect(() => deserialize(JSON.stringify(s))).toThrow(/más nueva/);
    const t = JSON.parse(serialize(run(1)));
    t.state.rng.world = [1, 2];
    expect(() => deserialize(JSON.stringify(t))).toThrow(/RNG/);
  });
});

describe('Determinismo y guardado con proyectos (Fase 2)', () => {
  const play = (seed: number, days: number) => {
    const s = newGame(seed, 40_000_000);
    step(s, [
      { type: 'createProject', techId: 'solar_fv', mw: 10, lat: SITES.solar.lat, lon: SITES.solar.lon },
      { type: 'createProject', techId: 'eolica_tierra', mw: 30, lat: SITES.eolica.lat, lon: SITES.eolica.lon },
    ], ctx);
    runWithPilot(s, days, { partnerShare: 0.5 });
    return s;
  };

  it('misma semilla + mismos comandos ⇒ mismo estado tras 10 años con proyectos', () => {
    const a = play(77, 3650), b = play(77, 3650);
    expect(a.projects.some((p) => p.stage === 'operacion')).toBe(true);
    expect(stateHash(a)).toBe(stateHash(b));
    expect(stateHash(play(78, 400))).not.toBe(stateHash(play(77, 400)));
  });

  it('guardar → cargar → seguir = no guardar (con obras y plantas en curso)', () => {
    const a = play(5, 365 * 4);
    const b = deserialize(serialize(a));
    runWithPilot(a, 365 * 3, { partnerShare: 0.5 });
    runWithPilot(b, 365 * 3, { partnerShare: 0.5 });
    expect(stateHash(b)).toBe(stateHash(a));
  });

  it('migra partidas de la Fase 1 (versión 1)', () => {
    const v1 = JSON.parse(serialize(run(40)));
    v1.saveVersion = 1;
    delete v1.state.projects; delete v1.state.nextProjectId; delete v1.state.finance;
    v1.state.saveVersion = 1;
    const s = deserialize(JSON.stringify(v1));
    expect(s.saveVersion).toBe(SAVE_VERSION);
    expect(s.projects).toEqual([]);
    expect(s.finance.bankrupt).toBe(false);
    step(s, [], ctx);
  });
});
