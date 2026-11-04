import { describe, expect, it } from 'vitest';
import {
  Rng, checkViability, debugRealResource, deserialize, drawPermitDecision, drawStudyOutcome, permitApprovalProbability, selectCompanyFinancials,
  selectProjectDetail, selectProjects, serialize, seedStream, stateHash, step, type Command, type SimEvent,
} from '../src';
import { ctx, data, newGame, runWithPilot, SITES } from './helpers';

const create = (techId: string, mw: number, site: { lat: number; lon: number }): Command => ({ type: 'createProject', techId, mw, lat: site.lat, lon: site.lon });

describe('Probabilidades de estudios y permisos (10 000 corridas)', () => {
  it('cada decisión de permiso converge a su probabilidad configurada', () => {
    for (const d of data.countries.PAN.permisos) {
      const rng = new Rng(seedStream(11, d.id));
      const n = 10_000;
      const c = { aprobado: 0, rechazado: 0, info_adicional: 0 };
      for (let i = 0; i < n; i++) c[drawPermitDecision(rng, d, 0)]++;
      expect(Math.abs(c.aprobado / n - d.prob.aprobado)).toBeLessThan(0.015);
      expect(Math.abs(c.rechazado / n - d.prob.rechazado)).toBeLessThan(0.015);
      expect(Math.abs(c.info_adicional / n - d.prob.info_adicional)).toBeLessThan(0.015);
    }
  });

  it('la aprobación final (con pedidos de información) converge a la fórmula analítica', () => {
    const d = data.countries.PAN.permisos.find((x) => x.id === 'licencia_ambiental_cat_III')!;
    const rng = new Rng(seedStream(5, 'x'));
    let ok = 0;
    const n = 10_000;
    for (let i = 0; i < n; i++) {
      let info = 0;
      for (;;) {
        const r = drawPermitDecision(rng, d, info);
        if (r === 'info_adicional') { info++; continue; }
        if (r === 'aprobado') ok++;
        break;
      }
    }
    expect(Math.abs(ok / n - permitApprovalProbability(d))).toBeLessThan(0.012);
  });

  it('los resultados de estudios convergen a normal/peor/bloqueo', () => {
    for (const s of Object.values(data.studies)) {
      if (s.sigma_recurso !== undefined) continue;
      const rng = new Rng(seedStream(3, s.id));
      const n = 10_000;
      const c = { normal: 0, peor: 0, bloqueo: 0 };
      for (let i = 0; i < n; i++) {
        const r = drawStudyOutcome(rng, s, data.findings);
        c[r.outcome]++;
        if (r.outcome === 'peor') expect(r.capexFactor!).toBeGreaterThanOrEqual(1);
        if (r.outcome === 'bloqueo') expect(s.hallazgos).toContain(r.findingId);
      }
      expect(Math.abs(c.normal / n - s.resultados.normal)).toBeLessThan(0.015);
      expect(Math.abs(c.peor / n - s.resultados.peor)).toBeLessThan(0.015);
      expect(Math.abs(c.bloqueo / n - s.resultados.bloqueo)).toBeLessThan(0.01);
    }
  });
});

describe('Comandos de proyecto', () => {
  it('crear proyecto cobra la prospección y valida sitio, escala y grilla', () => {
    const s = newGame(1);
    const cash = s.company.cashUsd;
    const ev = step(s, [create('solar_fv', 10, SITES.solar)], ctx);
    expect(ev.some((e) => e.type === 'projectCreated')).toBe(true);
    expect(s.projects).toHaveLength(1);
    expect(s.company.cashUsd).toBeLessThan(cash);
    expect(s.projects[0].stage).toBe('identificado');
    const bad = step(s, [create('solar_fv', 10, { lat: 0, lon: -30 }), create('solar_fv', 5000, SITES.solar), create('solar_fv', 10, { lat: 4.6, lon: -74.1 })], ctx);
    expect(bad.filter((e) => e.type === 'commandRejected')).toHaveLength(3);
    // sin grilla no se puede crear, pero el tiempo avanza
    const r = step(s, [create('solar_fv', 10, SITES.solar)], { data: ctx.data });
    expect(r.some((e) => e.type === 'commandRejected' && /grilla/.test(e.error))).toBe(true);
  });

  it('respeta el grafo: no se puede pedir la licencia ambiental sin EIA ni la factibilidad sin medición', () => {
    const s = newGame(1);
    step(s, [create('solar_fv', 20, SITES.solar)], ctx);
    const id = s.projects[0].id;
    const ev = step(s, [
      { type: 'applyPermit', projectId: id, permitId: 'licencia_ambiental_cat_II' },
      { type: 'commissionStudy', projectId: id, studyId: 'factibilidad' },
      { type: 'commissionStudy', projectId: id, studyId: 'eia_cat_I' }, // no aplica a 20 MW
      { type: 'arrangeFinancing', projectId: id, lenderId: 'banco_comercial', debtFraction: 0.7, partnerShare: 0 },
      { type: 'startConstruction', projectId: id },
    ], ctx);
    const rej = ev.filter((e): e is Extract<SimEvent, { type: 'commandRejected' }> => e.type === 'commandRejected');
    expect(rej).toHaveLength(5);
    expect(rej[0].error).toMatch(/estudio|Requiere/);
  });

  it('nada es gratis: sin caja no se encargan estudios', () => {
    const s = newGame(1, 20_000);
    step(s, [create('eolica_tierra', 45, SITES.eolica)], ctx);
    const ev = step(s, [{ type: 'commissionStudy', projectId: s.projects[0].id, studyId: 'medicion_eolica_torre' }], ctx);
    expect(ev.some((e) => e.type === 'commandRejected' && /Caja insuficiente/.test(e.error))).toBe(true);
  });

  it('la medición en sitio acerca la estimación al recurso real y reduce la incertidumbre', () => {
    let errBefore = 0, errAfter = 0;
    for (let seed = 1; seed <= 30; seed++) {
      const s = newGame(seed, undefined, false);
      step(s, [create('solar_fv', 10, { lat: 8.2 + seed * 0.003, lon: -80.7 })], ctx);
      const p = s.projects[0];
      const real = debugRealResource(s, ctx, p);
      errBefore += Math.abs(p.estimate.value / real - 1);
      step(s, [{ type: 'commissionStudy', projectId: p.id, studyId: 'medicion_solar_estacion' }], ctx);
      for (let d = 0; d < 430; d++) step(s, [], ctx);
      expect(p.estimate.sigma).toBe(0.025);
      expect(p.estimate.source).toBe('medicion_solar_estacion');
      errAfter += Math.abs(p.estimate.value / real - 1);
    }
    expect(errAfter).toBeLessThan(errBefore * 0.6);
  });

  it('los selectores no exponen el recurso real oculto', () => {
    const s = newGame(3, 30_000_000);
    step(s, [create('solar_fv', 10, SITES.solar)], ctx);
    runWithPilot(s, 365 * 6);
    const d = selectProjectDetail(s, ctx, s.projects[0].id)!;
    expect(d.summary.stage).toBe('operacion');
    expect(JSON.stringify(d)).not.toMatch(/realFactor|fcReal/);
  });
});

describe('Ciclo completo de un proyecto solar', () => {
  const s = newGame(7, 30_000_000);
  step(s, [create('solar_fv', 10, SITES.solar)], ctx);
  const id = s.projects[0].id;
  const stages = new Set<string>();
  const events: SimEvent[] = [];
  for (let d = 0; d < 365 * 8; d++) {
    events.push(...runWithPilot(s, 1));
    stages.add(s.projects[0].stage);
  }
  const p = s.projects[0];

  it('recorre todas las etapas hasta operación', () => {
    for (const st of ['estudios', 'permisos', 'cierre_financiero', 'construccion', 'puesta_en_marcha', 'operacion']) expect(stages).toContain(st);
    expect(p.stage).toBe('operacion');
  });

  it('emite eventos de cada paso', () => {
    const types = new Set(events.map((e) => e.type));
    for (const t of ['studyCompleted', 'permitDecided', 'ppaResult', 'financingResult', 'constructionStarted', 'milestoneCompleted', 'commissioningStarted', 'projectOperational']) {
      expect(types).toContain(t);
    }
  });

  it('la construcción avanza por hitos de 0 a 1 y la deuda se amortiza', () => {
    expect(p.construction!.progress).toBe(1);
    expect(p.construction!.milestones.every((m) => m.done)).toBe(true);
    expect(p.debt!.monthsPaid).toBeGreaterThan(12);
    expect(p.debt!.outstandingUsd).toBeLessThan(p.debt!.principalUsd);
  });

  it('produce según el recurso real (FC anual del orden esperado) y gana dinero operando', () => {
    const d = selectProjectDetail(s, ctx, id)!;
    expect(d.operation!.actualFcLast12m!).toBeGreaterThan(0.15);
    expect(d.operation!.actualFcLast12m!).toBeLessThan(0.23);
    const f = selectCompanyFinancials(s, ctx);
    expect(f.last12m.revenueUsd).toBeGreaterThan(1_000_000);
    expect(f.last12m.ebitdaUsd).toBeGreaterThan(0);
    expect(f.balance.operatingAssetsUsd).toBeGreaterThan(0);
    expect(f.balance.totalAssetsUsd).toBeCloseTo(f.balance.cashUsd + f.balance.developmentAssetsUsd + f.balance.constructionAssetsUsd + f.balance.operatingAssetsUsd, 4);
    expect(selectProjects(s, ctx)[0].buildProgress).toBe(1);
  });

  it('el detalle trae línea de tiempo, costos y economía', () => {
    const d = selectProjectDetail(s, ctx, id)!;
    expect(d.timeline.length).toBeGreaterThan(20);
    expect(d.costs.incurredUsd.total).toBeGreaterThan(d.costs.capex.totalUsd * 0.8);
    expect(d.economics!.lcoeUsdMwh).toBeGreaterThan(0);
    expect(d.saleValueUsd).toBeGreaterThan(0);
  });

  it('se puede vender una planta en operación', () => {
    const t = deserialize(serialize(s));
    const cash = t.company.cashUsd;
    let sold = false;
    for (let d = 0; d < 400 && !sold; d++) {
      const ev = step(t, d === 0 ? [{ type: 'sellProject', projectId: id }] : [], ctx);
      sold = ev.some((e) => e.type === 'projectSold');
      if (ev.some((e) => e.type === 'saleFailed')) step(t, [{ type: 'sellProject', projectId: id }], ctx);
    }
    expect(sold).toBe(true);
    expect(t.projects[0].stage).toBe('vendido');
    expect(t.company.cashUsd).toBeGreaterThan(cash);
  });
});

describe('Eólica, abandono y venta en desarrollo', () => {
  it('un proyecto abandonado castiga lo invertido', () => {
    const s = newGame(2);
    step(s, [create('eolica_tierra', 45, SITES.eolica)], ctx);
    const id = s.projects[0].id;
    step(s, [{ type: 'commissionStudy', projectId: id, studyId: 'prefactibilidad' }], ctx);
    const ev = step(s, [{ type: 'abandonProject', projectId: id }], ctx);
    expect(ev.some((e) => e.type === 'projectAbandoned')).toBe(true);
    expect(s.projects[0].stage).toBe('abandonado');
    for (let d = 0; d < 40; d++) step(s, [], ctx);
    const st = s.finance.statements.at(-1)!;
    expect(st.lines.castigos ?? 0).toBeLessThan(0);
    expect(step(s, [{ type: 'commissionStudy', projectId: id, studyId: 'factibilidad' }], ctx)[0].type).toBe('commandRejected');
  });

  it('un proyecto con permisos vale más que uno recién identificado', () => {
    const s = newGame(9, 30_000_000);
    step(s, [create('solar_fv', 20, SITES.solar)], ctx);
    const v0 = selectProjectDetail(s, ctx, s.projects[0].id)!;
    runWithPilot(s, 365 * 2, { ppaChannel: null });
    const v1 = selectProjectDetail(s, ctx, s.projects[0].id)!;
    expect(v1.successProbability).toBeGreaterThan(v0.successProbability);
    expect(v1.saleValueUsd).toBeGreaterThan(v0.saleValueUsd);
  });
});

describe('Verificador de viabilidad (Monte Carlo)', () => {
  const s = newGame(4, 30_000_000);
  step(s, [create('solar_fv', 20, SITES.solar)], ctx);
  const id = s.projects[0].id;

  it('no modifica el estado y es reproducible', () => {
    const h = stateHash(s);
    const a = checkViability(s, ctx, id, { runs: 300, seed: 1 });
    const b = checkViability(s, ctx, id, { runs: 300, seed: 1 });
    expect(stateHash(s)).toBe(h);
    expect(a).toEqual(b);
  });

  it('da probabilidades, plazos, costos y TIR con sentido', () => {
    const v = checkViability(s, ctx, id, { runs: 500 });
    expect(v.probCod).toBeGreaterThan(0.5);
    expect(v.probCod).toBeLessThan(1);
    expect(v.monthsToCodP90!).toBeGreaterThanOrEqual(v.monthsToCodP50!);
    expect(v.monthsToCodP50!).toBeGreaterThan(24);
    expect(v.monthsToCodP50!).toBeLessThan(72);
    expect(v.costP90Usd!).toBeGreaterThanOrEqual(v.costP50Usd!);
    expect(v.irrEquityP50!).toBeGreaterThan(v.irrEquityP10!);
    expect(Object.values(v.failures).reduce((a, b) => a + b, 0)).toBe(Math.round((1 - v.probCod) * v.runs));
  });

  it('un hallazgo fatal deja la probabilidad en 0', () => {
    const t = deserialize(serialize(s));
    t.projects[0].findings.push({ id: 'arqueologia', studyId: 'eia_cat_II', status: 'fatal', costUsd: 0, attempts: 0 });
    expect(checkViability(t, ctx, id, { runs: 50 }).probCod).toBe(0);
  });
});

describe('Economía de la empresa', () => {
  it('una empresa que no hace nada pierde dinero', () => {
    const s = newGame(1);
    const cash = s.company.cashUsd;
    for (let d = 0; d < 365 * 2; d++) step(s, [], ctx);
    expect(s.company.cashUsd).toBeLessThan(cash - 400_000);
    const f = selectCompanyFinancials(s, ctx);
    expect(f.last12m.netIncomeUsd).toBeLessThan(0);
    expect(f.taxLossCarryforwardUsd).toBeGreaterThan(0);
    expect(f.statements).toHaveLength(24);
  });

  it('sobreapalancarse puede quebrar: obra grande con poca caja ⇒ quiebra y fin de la partida', () => {
    const s = newGame(7, 20_000_000);
    step(s, [create('eolica_tierra', 45, SITES.eolica)], ctx);
    const ev = runWithPilot(s, 365 * 8);
    const b = ev.find((e) => e.type === 'bankruptcy');
    expect(b).toBeDefined();
    expect(s.finance.bankrupt).toBe(true);
    const tick = s.tick;
    expect(step(s, [{ type: 'renameCompany', name: 'Otra' }], ctx)).toEqual([]);
    expect(s.tick).toBe(tick);
  });

  it('un socio de capital reduce el aporte propio y cobra dividendos', () => {
    const s = newGame(7, 20_000_000);
    step(s, [create('eolica_tierra', 45, SITES.eolica)], ctx);
    const ev = runWithPilot(s, 365 * 8, { partnerShare: 0.8 });
    expect(ev.some((e) => e.type === 'bankruptcy')).toBe(false);
    expect(s.projects[0].stage).toBe('operacion');
    const lines = s.finance.statements.flatMap((x) => Object.entries(x.lines));
    expect(lines.some(([k, v]) => k === 'socio_aporte' && v > 0)).toBe(true);
    expect(lines.some(([k, v]) => k === 'socio_distribucion' && v < 0)).toBe(true);
    expect(lines.some(([k, v]) => k === 'prima_desarrollo' && v > 0)).toBe(true);
  });
});
