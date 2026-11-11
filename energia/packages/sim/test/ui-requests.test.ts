import { describe, expect, it } from 'vitest';
import { checkViability, previewFinancing, projectEconomics, selectProjectDetail, selectProjects, step, type SimEvent } from '../src';
import { ctx, newGame, runWithPilot, SITES } from './helpers';

/** Pedidos de la UI de la Fase 2 (agregados en la Fase 3 sin romper la API). */
describe('Pedidos de la UI al motor', () => {
  it('todo evento lleva el tick en que ocurrió', () => {
    const s = newGame(1, 5_000_000, false);
    const ev: SimEvent[] = [];
    ev.push(...step(s, [{ type: 'createProject', techId: 'solar_fv', mw: 10, lat: SITES.solar.lat, lon: SITES.solar.lon }, { type: 'renameCompany', name: 'X' }], ctx));
    expect(ev.find((e) => e.type === 'projectCreated')!.tick).toBe(0);
    expect(ev.find((e) => e.type === 'commandRejected')!.tick).toBe(0);
    for (let d = 0; d < 40; d++) ev.push(...step(s, [], ctx));
    expect(ev.every((e) => typeof e.tick === 'number')).toBe(true);
    expect(ev.find((e) => e.type === 'newMonth')!.tick).toBe(31);
  });

  it('detalle: país, fechas de inicio, avance de etapa, producción mensual P50/P90 y fallas', () => {
    const s = newGame(3, 30_000_000, false);
    step(s, [{ type: 'createProject', techId: 'solar_fv', mw: 10, lat: SITES.solar.lat, lon: SITES.solar.lon }], ctx);
    const id = s.projects[0].id;
    step(s, [{ type: 'commissionStudy', projectId: id, studyId: 'prefactibilidad' }], ctx);
    let d = selectProjectDetail(s, ctx, id)!;
    expect(d.countryCode).toBe('PAN');
    expect(d.studies.find((x) => x.id === 'prefactibilidad')!.startDate).toEqual({ year: 2026, month: 1, day: 2 });
    expect(d.summary.stageProgress).toBe(0);
    const months = d.resource.monthlyMwh;
    expect(months).toHaveLength(12);
    expect(months.reduce((a, m) => a + m.p50Mwh, 0)).toBeCloseTo(d.resource.energyP50MwhYear, -1);
    expect(months.every((m) => m.p90Mwh <= m.p50Mwh)).toBe(true);
    // Estación seca (ene–abr) produce más que la lluviosa (oct)
    expect(months[2].p50Mwh / 31).toBeGreaterThan(months[9].p50Mwh / 31);
    runWithPilot(s, 365 * 2);
    d = selectProjectDetail(s, ctx, id)!;
    if (!d.construction && !d.operation) expect(d.summary.stageProgress).toBeGreaterThan(0.5);
    runWithPilot(s, 365 * 4);
    d = selectProjectDetail(s, ctx, id)!;
    expect(d.operation).not.toBeNull();
    expect(d.summary.stageProgress).toBe(1);
    expect(d.operation!.expectedMonthlyMwh).toHaveLength(12);
    expect(Array.isArray(d.operation!.failureLog)).toBe(true);
    for (const f of d.operation!.failureLog) expect(f.date.year).toBeGreaterThanOrEqual(2026);
    expect(JSON.stringify(d)).not.toMatch(/realFactor|fcReal/);
    expect(selectProjects(s, ctx)[0].stageProgress).toBe(1);
  });

  it('vista previa de financiamiento: banco, socio, prima y dimensionamiento igual al cierre', () => {
    const s = newGame(7, 30_000_000, false);
    step(s, [{ type: 'createProject', techId: 'solar_fv', mw: 20, lat: SITES.solar.lat, lon: SITES.solar.lon }], ctx);
    const id = s.projects[0].id;
    let pv = previewFinancing(s, ctx, id, { lenderId: 'banco_comercial', debtFraction: 0.7, partnerShare: 0.5 })!;
    expect(pv.ok).toBe(false);
    expect(pv.blockers.length).toBeGreaterThan(0);
    // Avanza hasta que se pueda financiar
    for (let i = 0; i < 365 * 4 && !previewFinancing(s, ctx, id, { lenderId: 'banco_comercial', debtFraction: 0.7, partnerShare: 0.5 })!.ok; i++) runWithPilot(s, 1, { ppaChannel: null, debtFraction: 0 });
    pv = previewFinancing(s, ctx, id, { lenderId: 'banco_comercial', debtFraction: 0.7, partnerShare: 0.5 })!;
    expect(pv.ok).toBe(true);
    expect(pv.debtUsd).toBeGreaterThan(0);
    expect(pv.debtUsd).toBeLessThanOrEqual(pv.budgetUsd * 0.7 + 1);
    expect(pv.partnerEquityUsd).toBeCloseTo((pv.budgetUsd - pv.debtUsd) * 0.5, 6);
    expect(pv.partnerPremiumUsd).toBeCloseTo(pv.partnerEquityUsd * 0.1, 6);
    expect(pv.netOwnCashUsd).toBeCloseTo(pv.ownEquityUsd + pv.structuringFeeUsd + pv.advisorsUsd - pv.partnerPremiumUsd, 6);
    const noDebt = previewFinancing(s, ctx, id, { lenderId: 'banco_comercial', debtFraction: 0, partnerShare: 0 })!;
    expect(noDebt.debtUsd).toBe(0);
    expect(noDebt.ownEquityUsd).toBeCloseTo(noDebt.budgetUsd, 6);
    // El cierre real da la misma deuda que la vista previa (si el comité aprueba)
    const ev: SimEvent[] = [];
    ev.push(...step(s, [{ type: 'arrangeFinancing', projectId: id, lenderId: 'banco_comercial', debtFraction: 0.7, partnerShare: 0.5 }], ctx));
    for (let i = 0; i < 200 && s.projects[0].financing?.status === 'en_proceso'; i++) ev.push(...step(s, [], ctx));
    const f = s.projects[0].financing!;
    // Fase 5: entre la vista previa y el cierre cambia la previsión de precios del mes (mercado endógeno).
    if (f.status === 'cerrado') expect(f.debtUsd / pv.debtUsd).toBeGreaterThan(0.85);
  }, 20_000);

  it('BUG viabilidad: el VAN esperado del Monte Carlo es coherente con el determinista en la misma base', () => {
    // Caso reportado: solar 10 MW en Coclé recién creado con estudio satelital y prefactibilidad.
    const s = newGame(4, 30_000_000, false);
    step(s, [{ type: 'createProject', techId: 'solar_fv', mw: 10, lat: SITES.solar.lat, lon: SITES.solar.lon }], ctx);
    const id = s.projects[0].id;
    step(s, [{ type: 'commissionStudy', projectId: id, studyId: 'medicion_solar_satelital' }, { type: 'commissionStudy', projectId: id, studyId: 'prefactibilidad' }], ctx);
    const v = checkViability(s, ctx, id, { runs: 500, seed: 1 });
    const eco = projectEconomics(s, ctx, s.projects[0]);
    expect(v.probCod).toBeGreaterThan(0.85);
    expect(v.ppaChannelId).toBeNull(); // mismo supuesto de precio que la economía (spot) si no hay PPA
    // Misma TIR de equity (mediana) que el cálculo determinista, ±2,5 puntos
    expect(Math.abs(v.irrEquityP50! - eco.model.irrEquity!)).toBeLessThan(0.025);
    // Antes: VAN esperado −1,5 M con 95 % de éxito y TIR 15 %. Ahora: mismo signo y orden de magnitud que el determinista.
    expect(Math.sign(v.npvExpectedUsd)).toBe(Math.sign(v.npvDeterministicUsd));
    expect(v.npvExpectedUsd).toBeGreaterThan(v.npvDeterministicUsd * v.probCod - 0.3 * Math.abs(v.npvDeterministicUsd));
    expect(v.npvExpectedUsd).toBeLessThan(v.npvDeterministicUsd + 0.2 * Math.abs(v.npvDeterministicUsd) + 1);
    // Con un canal de PPA explícito se simula ese canal
    const w = checkViability(s, ctx, id, { runs: 300, seed: 1, ppaChannelId: 'licitacion_etesa' });
    expect(w.ppaChannelId).toBe('licitacion_etesa');
  });
});
