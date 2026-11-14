import { describe, expect, it } from 'vitest';
import { buildGameData, rawGameData } from '@voltaje/data';
import {
  Rng, SAVE_VERSION, applyCommand, applyCommands, areaScore, blendedReputation, buildModifiers, deserialize, devCostMult, drawPermitDecision, employerCostUsd,
  experienceScore, financeModifiers, marketSalaryUsd, officeLevel, omModifiers, permitApprovalProbability, permitModifiers, repOf, selectCompanyOverview,
  selectLaborMarket, selectOffices, selectProjectTeam, selectReputation, selectTeam, selectWorkload, serialize, severanceUsd, stateHash, step, studyModifiers,
  technicalScore, seedStream, type Employee, type GameState, type Opportunity,
} from '../src';
import { ctx, data, newGame, SITES } from './helpers';

const team = data.team!;

/** Partida con el mundo inicializado y un proyecto solar en Panamá. */
function game(seed = 1, cash = 50e6, competitors = false): GameState {
  const s = newGame(seed, cash, competitors);
  step(s, [{ type: 'createProject', techId: 'solar_fv', mw: 20, lat: SITES.solar.lat, lon: SITES.solar.lon }], ctx);
  return s;
}

/** Empleado sintético (para medir efectos sin pasar por el mercado laboral). */
function emp(s: GameState, role: string, skill: number, o: Partial<Employee> = {}): Employee {
  const id = `T${role}${skill}${s.business.team!.employees.length}`;
  const e: Employee = { id, name: id, role, countryCode: 'PAN', skill, experienceYears: 15, languages: ['es', 'en'], salaryUsdMonth: 0, morale: 60, hiredTick: s.tick, assignment: [], trainings: 0, ...o };
  e.salaryUsdMonth = o.salaryUsdMonth ?? Math.round(marketSalaryUsd(s, ctx, e));
  s.business.team!.employees.push(e);
  return e;
}
const noTeam = (s: GameState) => { s.business.team!.employees = []; };

describe('Fase 6: datos (team.yaml)', () => {
  it('carga y se valida; referencias cruzadas', () => {
    expect(team.roles.length).toBeGreaterThanOrEqual(10);
    for (const iso of Object.keys(data.countries)) expect(team.paises[iso]).toBeDefined();
    expect(team.oficinas.niveles.map((l) => l.id)).toEqual(['representante', 'oficina', 'sede']);
  });

  it('rechaza un rol inexistente, un efecto > 1 y un valor sin fuente', () => {
    const raw = () => structuredClone({ ...rawGameData, countries: Object.fromEntries(Object.entries(rawGameData.countries).map(([k, v]) => [k.split('/').pop()!, v])), technologies: Object.fromEntries(Object.entries(rawGameData.technologies).map(([k, v]) => [k.split('/').pop()!, v])) }) as any;
    const a = raw(); a.team.equipo_inicial_jugador[0].rol = 'astronauta';
    expect(() => buildGameData(a)).toThrow(/rol inexistente/);
    const b = raw(); b.team.efectos.permisos_rechazo.base = 1.5;
    expect(() => buildGameData(b)).toThrow(/≤ 1/);
    const c = raw(); delete c.team.puntaje_externo.supuesto;
    expect(() => buildGameData(c)).toThrow(/fuente/);
  });
});

describe('Fase 6: efectos del equipo (acotados y en la dirección correcta)', () => {
  it('sin equipo los efectos son neutros (consultor externo); con un experto mejoran sin pasar de 1 ± k', () => {
    const s = game();
    const p = s.projects[0];
    noTeam(s);
    const d = data.countries.PAN.permisos.find((x) => x.id === 'licencia_ambiental_cat_II')!;
    const m0 = permitModifiers(s, ctx, p, d);
    expect(m0.reject).toBeCloseTo(1, 9); expect(m0.time).toBeCloseTo(1, 9);
    expect(buildModifiers(s, ctx, p).overrunProb).toBe(1);
    emp(s, 'abogado', 95); emp(s, 'gerente_proyecto', 95); emp(s, 'ing_recurso', 95); emp(s, 'financiero', 95); emp(s, 'ing_electrico', 95);
    const m = permitModifiers(s, ctx, p, d);
    const k = (id: string) => team.efectos[id].base;
    expect(m.approve).toBeGreaterThan(1); expect(m.approve).toBeLessThanOrEqual(1 + k('permisos_aprobacion') + 1e-9);
    expect(m.reject).toBeLessThan(1); expect(m.reject).toBeGreaterThanOrEqual(1 - k('permisos_rechazo') - 1e-9);
    expect(m.time).toBeLessThan(1); expect(m.time).toBeGreaterThanOrEqual(1 - k('permisos_tiempo'));
    const b = buildModifiers(s, ctx, p);
    expect(b.overrunProb).toBeLessThan(1); expect(b.overrunProb).toBeGreaterThanOrEqual(1 - k('obra_sobrecosto_prob'));
    expect(studyModifiers(s, ctx, p).sigma).toBeGreaterThanOrEqual(1 - k('recurso_sigma'));
    expect(financeModifiers(s, ctx, p, 'comercial').spread).toBeLessThan(1);
    expect(omModifiers(s, ctx, p).failures).toBeLessThan(1);
    // Con equipo, la probabilidad de aprobar sube (analítica) y nunca pasa del 98 %.
    expect(permitApprovalProbability(d, m)).toBeGreaterThan(permitApprovalProbability(d, m0));
    expect(permitApprovalProbability(d, { approve: 50, reject: 0.01, info: 0.01 })).toBeLessThanOrEqual(0.98 + 1e-9);
  });

  it('convergencia estadística: la frecuencia de aprobaciones sorteadas sigue la probabilidad modificada', () => {
    const s = game();
    const p = s.projects[0];
    const d = data.countries.PAN.permisos.find((x) => x.id === 'licencia_ambiental_cat_II')!;
    noTeam(s);
    const m0 = permitModifiers(s, ctx, p, d);
    emp(s, 'abogado', 90);
    const m1 = permitModifiers(s, ctx, p, d);
    const rate = (m: typeof m0) => {
      const rng = new Rng(seedStream(7, 'x'));
      let ok = 0;
      const n = 20000;
      for (let i = 0; i < n; i++) if (drawPermitDecision(rng, d, d.max_intentos_info, m) === 'aprobado') ok++;
      return ok / n;
    };
    const r0 = rate(m0), r1 = rate(m1);
    expect(r1).toBeGreaterThan(r0 + 0.01);
    const expected = (m: typeof m0) => { const a = d.prob.aprobado * m.approve, r = d.prob.rechazado * m.reject; return a / (a + r); };
    expect(Math.abs(r1 - expected(m1))).toBeLessThan(0.015);
    expect(Math.abs(r0 - expected(m0))).toBeLessThan(0.015);
  });

  it('la carga diluye el efecto: un gerente con 6 obras rinde menos que con 1; asignarlo a un proyecto lo concentra', () => {
    const s = game();
    noTeam(s);
    const e = emp(s, 'gerente_proyecto', 90);
    const p = s.projects[0];
    p.construction = { progress: 0 } as any; // basta para contar la carga (necesita obra)
    const one = areaScore(s, ctx, 'obra', { projectId: p.id }).gain;
    for (let i = 0; i < 5; i++) s.projects.push({ ...structuredClone(p), id: `X${i}` });
    const six = areaScore(s, ctx, 'obra', { projectId: p.id }).gain;
    expect(six).toBeLessThan(one * 0.5);
    e.assignment = [p.id];
    expect(areaScore(s, ctx, 'obra', { projectId: p.id }).gain).toBeCloseTo(one, 6);
    expect(areaScore(s, ctx, 'obra', { projectId: 'X0' }).gain).toBe(0);
  });

  it('un abogado de otro país y sin el idioma rinde menos (conocimiento local)', () => {
    const s = game();
    noTeam(s);
    emp(s, 'abogado', 80, { countryCode: 'BRA', languages: ['pt'] });
    const foreign = areaScore(s, ctx, 'permisos', { projectId: s.projects[0].id }).score;
    noTeam(s);
    emp(s, 'abogado', 80);
    expect(areaScore(s, ctx, 'permisos', { projectId: s.projects[0].id }).score).toBeGreaterThan(foreign + 10);
  });

  it('el comercial sube el puntaje técnico de las ofertas (hasta +10)', () => {
    const s = game();
    noTeam(s);
    const opp = { countryCode: 'PAN', contract: 'ppa', mw: 20, codMonths: 30 } as Opportunity;
    const t0 = technicalScore(s, ctx, opp, { techId: 'solar_fv' });
    emp(s, 'comercial', 90);
    const t1 = technicalScore(s, ctx, opp, { techId: 'solar_fv' });
    expect(t1 - t0).toBeGreaterThan(4);
    expect(t1 - t0).toBeLessThanOrEqual(team.efectos.ofertas_puntaje.base + 1e-9);
  });

  it('en la simulación un equipo de obra fuerte reduce los sobrecostos (muchas semillas)', () => {
    // Se compara el sobrecosto medio de 40 obras con y sin gerencia (mismo sorteo base).
    const overrun = (withTeam: boolean) => {
      let sum = 0;
      for (let seed = 1; seed <= 40; seed++) {
        const s = game(seed);
        noTeam(s);
        if (withTeam) { emp(s, 'gerente_proyecto', 95); emp(s, 'ing_civil', 95); }
        const p = s.projects[0];
        const m = buildModifiers(s, ctx, p);
        const rng = new Rng(seedStream(seed, 'obra'));
        for (const h of data.technologies.solar_fv.hitos_construccion) if (rng.chance(0.15 * m.overrunProb)) sum += rng.triangular(0.02, 0.06, 0.2) * m.overrunSize * h.fraccion;
      }
      return sum / 40;
    };
    expect(overrun(true)).toBeLessThan(overrun(false) * 0.85);
  });
});

describe('Fase 6: contratar, despedir, capacitar, rotación', () => {
  it('contratar cuesta reclutamiento; despedir, la indemnización del país; capacitar sube la habilidad', () => {
    const s = game();
    const c = selectLaborMarket(s, ctx, { countryCode: 'PAN' }).candidates[0];
    expect(c).toBeDefined();
    const cash0 = s.company.cashUsd;
    expect(applyCommand(s, { type: 'hireCandidate', candidateId: c.id }, ctx).ok).toBe(true);
    expect(cash0 - s.company.cashUsd).toBeCloseTo(c.recruitmentFeeUsd, 0);
    const e = s.business.team!.employees.find((x) => x.id === c.id)!;
    expect(e).toBeDefined();
    // México: mínimo 3 meses de indemnización (LFT art. 50)
    const mx = { ...e, countryCode: 'MEX', hiredTick: s.tick };
    expect(severanceUsd(s, ctx, mx)).toBeCloseTo(3 * e.salaryUsdMonth, 0);
    const skill0 = e.skill;
    expect(applyCommand(s, { type: 'trainEmployee', employeeId: e.id }, ctx).ok).toBe(true);
    for (let d = 0; d < 70; d++) step(s, [], ctx);
    expect(e.skill).toBeGreaterThan(skill0);
    const cash1 = s.company.cashUsd;
    const sev = severanceUsd(s, ctx, e);
    expect(applyCommand(s, { type: 'fireEmployee', employeeId: e.id }, ctx).ok).toBe(true);
    expect(cash1 - s.company.cashUsd).toBeCloseTo(sev, 0);
    expect(s.business.team!.employees.some((x) => x.id === e.id)).toBe(false);
  });

  it('el salario se cobra cada mes con las cargas sociales del país', () => {
    const s = game();
    const cost = s.business.team!.employees.reduce((a, e) => a + employerCostUsd(ctx, e), 0);
    expect(cost).toBeGreaterThan(0);
    for (let d = 0; d < 40; d++) step(s, [], ctx);
    expect(s.finance.statements[0].lines.personal).toBeCloseTo(-cost, -1);
  });

  it('rotación: mal pagados renuncian mucho más que bien pagados', () => {
    const quits = (ratio: number) => {
      let q = 0;
      for (let seed = 1; seed <= 6; seed++) {
        const s = game(seed);
        noTeam(s);
        for (let i = 0; i < 10; i++) { const e = emp(s, 'ing_electrico', 50); e.salaryUsdMonth = Math.round(e.salaryUsdMonth * ratio); }
        for (let d = 0; d < 730; d++) step(s, [], ctx);
        q += s.business.team!.quits;
      }
      return q;
    };
    const low = quits(0.6), fair = quits(1.1);
    expect(low).toBeGreaterThan(fair * 2.5);
    expect(low).toBeGreaterThan(20);
  }, 60_000);

  it('una oferta de otra empresa puede llevarse a una persona (la IA usa el mismo comando) y el jugador recibe el aviso', () => {
    const s = game(3, 50e6, true);
    const e = emp(s, 'financiero', 80);
    e.morale = 20;
    const comp = s.competitors[0];
    comp.company.cashUsd = 50e6;
    const view = { ...s, actorId: comp.id, root: s, company: comp.company, finance: comp.finance, projects: comp.projects, business: comp.business } as GameState;
    let moved = false;
    for (let i = 0; i < 20 && !moved; i++) {
      applyCommand(view, { type: 'poachEmployee', employeeId: e.id, salaryUsdMonth: e.salaryUsdMonth * 1.6 }, ctx);
      moved = comp.business.team!.employees.some((x) => x.id === e.id);
    }
    expect(moved).toBe(true);
    expect(s.business.team!.employees.some((x) => x.id === e.id)).toBe(false);
    const ev = step(s, [], ctx);
    expect(ev.some((x) => x.type === 'employeeQuit' && x.reason === 'oferta')).toBe(true);
  });
});

describe('Fase 6: reputación por eje', () => {
  it('abandonar baja la reputación con el gobierno; un conflicto, la comunitaria; los cambios quedan con su causa', () => {
    const s = game();
    s.projects[0].permits.x = { permitId: 'x', status: 'aprobado', startTick: 0, endTick: 0, costUsd: 0, infoRequests: 0, applications: 1 } as any;
    const g0 = repOf(s, ctx, 'gobierno', 'PAN');
    applyCommand(s, { type: 'abandonProject', projectId: s.projects[0].id }, ctx);
    expect(repOf(s, ctx, 'gobierno', 'PAN')).toBeLessThan(g0);
    const r = selectReputation(s, ctx);
    expect(r.recent[0].cause).toBe('abandono');
  });

  it('la reputación cambia el puntaje de experiencia y las probabilidades de consulta y de conflicto', () => {
    const s = game();
    const opp = { mw: 20, countryCode: 'PAN', kind: 'licitacion_publica' } as const;
    const e0 = experienceScore(s, opp, ctx);
    s.business.rep!.gobierno.PAN = 90;
    expect(experienceScore(s, opp, ctx)).toBeGreaterThan(e0 + 5);
    expect(blendedReputation(s, opp, ctx)).toBeGreaterThan(s.business.reputation);
    const d = data.countries.PAN.permisos.find((x) => x.grupo === 'participacion_ciudadana')!;
    s.business.rep!.comunidad.PAN = 10;
    const low = permitModifiers(s, ctx, s.projects[0], d).approve;
    s.business.rep!.comunidad.PAN = 90;
    expect(permitModifiers(s, ctx, s.projects[0], d).approve).toBeGreaterThan(low * 1.2);
    // Bancos de desarrollo: mejor relación con el gobierno ⇒ menor spread
    s.business.rep!.gobierno.PAN = 10;
    const hi = financeModifiers(s, ctx, s.projects[0], 'desarrollo').spread;
    s.business.rep!.gobierno.PAN = 90;
    expect(financeModifiers(s, ctx, s.projects[0], 'desarrollo').spread).toBeLessThan(hi);
  });

  it('con oficina y buena reputación con clientes llegan invitaciones directas (solo el invitado puede ofertar)', () => {
    const s = game(5, 50e6);
    s.business.research.completed.push('contrato_ppa_corporativo', 'contrato_epc');
    let invites = 0, kind = '', invited = '';
    for (let d = 0; d < 365 * 4; d++) {
      s.business.reputation = 95;
      const ev = step(s, [], ctx);
      for (const e of ev) if (e.type === 'directInvitation') {
        invites++;
        const o = s.market.opportunities.find((x) => x.id === e.opportunityId)!;
        kind = o.kind; invited = o.invitedActorId!;
      }
    }
    expect(invites).toBeGreaterThan(0);
    expect(kind).toBe('solicitud_privada');
    expect(invited).toBe('jugador');
  });

  it('la inversión social sube la reputación comunitaria con tope anual', () => {
    const s = game();
    const c0 = repOf(s, ctx, 'comunidad', 'PAN');
    expect(applyCommand(s, { type: 'investInCommunity', countryCode: 'PAN', amountUsd: 200_000 }, ctx).ok).toBe(true);
    expect(repOf(s, ctx, 'comunidad', 'PAN')).toBeGreaterThan(c0 + 2);
    applyCommand(s, { type: 'investInCommunity', countryCode: 'PAN', amountUsd: 5_000_000 }, ctx);
    expect(repOf(s, ctx, 'comunidad', 'PAN') - c0).toBeLessThanOrEqual(team.reputacion.inversion_social.tope_anual_puntos.base + 1e-6);
    expect(applyCommand(s, { type: 'investInCommunity', countryCode: 'PAN', amountUsd: 10_000 }, ctx).ok).toBe(false);
  });
});

describe('Fase 6: oficinas', () => {
  it('mejorar a oficina cuesta, tarda, cobra cada mes y abarata el desarrollo; la sede exige personal', () => {
    const s = game(2, 50e6);
    s.business.research.completed.push('mercado_regional', 'mercado_colombia');
    s.business.presence!.COL = { status: 'activa', level: 'representante', requestedTick: 0, readyTick: 0, setupCostUsd: 0, monthlyCostUsd: 4000 };
    expect(officeLevel(s, 'COL')).toBe('representante');
    const dc0 = devCostMult(s, ctx, 'COL');
    expect(dc0).toBeGreaterThan(1);
    expect(devCostMult(s, ctx, 'PAN')).toBeCloseTo(1, 9);
    const cash0 = s.company.cashUsd;
    expect(applyCommand(s, { type: 'upgradeOffice', countryCode: 'COL' }, ctx).ok).toBe(true);
    expect(s.company.cashUsd).toBeLessThan(cash0);
    for (let d = 0; d < 70; d++) step(s, [], ctx);
    expect(officeLevel(s, 'COL')).toBe('oficina');
    expect(s.business.presence!.COL.level).toBe('oficina');
    expect(devCostMult(s, ctx, 'COL')).toBeLessThan(dc0);
    for (let d = 0; d < 35; d++) step(s, [], ctx);
    expect(s.finance.statements.at(-1)!.lines.oficinas).toBeLessThan(0);
    // Sede: exige personal en el país
    const r = applyCommand(s, { type: 'upgradeOffice', countryCode: 'COL' }, ctx);
    expect(r.ok).toBe(false);
    const o = selectOffices(s, ctx).find((x) => x.code === 'COL')!;
    expect(o.upgrade?.blockers.join(' ')).toMatch(/personas/);
  });

  it('la capacidad de la oficina limita las contrataciones (representante: 2 personas)', () => {
    const s = game(2, 50e6);
    s.business.presence!.COL = { status: 'activa', level: 'representante', requestedTick: 0, readyTick: 0, setupCostUsd: 0, monthlyCostUsd: 4000 };
    emp(s, 'abogado', 50, { countryCode: 'COL' }); emp(s, 'social', 50, { countryCode: 'COL' });
    const list = s.market.labor!.candidates.COL ?? [];
    s.market.labor!.candidates.COL = list.length ? list : [{ id: 'EZ', name: 'Z', role: 'abogado', countryCode: 'COL', skill: 50, experienceYears: 5, languages: ['es'], askUsdMonth: 2000, postedTick: 0, expiresTick: 1e9 }];
    const r = applyCommand(s, { type: 'hireCandidate', candidateId: s.market.labor!.candidates.COL[0].id }, ctx);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error).toMatch(/llena/);
  });
});

describe('Fase 6: IA, selectores, guardado y rendimiento', () => {
  it('la IA arma su equipo con los mismos comandos (contrata, sube salarios u oficinas)', () => {
    const s = newGame(4, undefined, true);
    for (let d = 0; d < 365 * 4; d++) step(s, [], ctx);
    const hires = s.competitors.reduce((a, c) => a + (c.business.team?.hires ?? 0), 0);
    expect(hires).toBeGreaterThan(0);
    for (const c of s.competitors) expect(c.business.team).toBeDefined();
  }, 60_000);

  it('el equipo inicial es explícito y su costo se descontó de los gastos fijos (gasto total igual)', () => {
    const s = newGame(1);
    step(s, [], ctx);
    const cost = s.business.team!.employees.reduce((a, e) => a + employerCostUsd(ctx, e), 0);
    expect(s.business.team!.employees.length).toBe(team.equipo_inicial_jugador.length);
    expect(s.company.monthlyFixedCostUsd + cost).toBeCloseTo(data.countries.PAN ? 18_500 : 0, -1);
  });

  it('selectores: equipo, carga, proyecto, reputación, oficinas y resumen global', () => {
    const s = game(6, 50e6, true);
    for (let d = 0; d < 60; d++) step(s, [], ctx);
    const t = selectTeam(s, ctx);
    expect(t.headcount).toBeGreaterThan(0);
    expect(t.areas.length).toBe(8);
    expect(t.employees[0].perProject.length).toBeGreaterThan(0);
    expect(selectWorkload(s, ctx).projects.length).toBe(1);
    const pt = selectProjectTeam(s, ctx, s.projects[0].id)!;
    expect(pt.applied.permits.length).toBeGreaterThan(0);
    expect(selectLaborMarket(s, ctx).candidates.length).toBeGreaterThan(0);
    expect(selectReputation(s, ctx).countries[0].effects).toBeDefined();
    expect(selectOffices(s, ctx)[0].home).toBe(true);
    const ov = selectCompanyOverview(s, ctx);
    expect(ov.ranking.of).toBe(6);
    expect(ov.mwByTech.development.solar_fv).toBe(20);
  });

  it('determinismo y guardar → cargar → seguir con equipo, oficinas y reputación', () => {
    const make = () => {
      const s = game(8, 50e6, true);
      const c = selectLaborMarket(s, ctx).candidates[0];
      applyCommands(s, [{ type: 'hireCandidate', candidateId: c.id }, { type: 'investInCommunity', countryCode: 'PAN', amountUsd: 50_000 }], ctx);
      return s;
    };
    const a = make(), b = make();
    for (let d = 0; d < 400; d++) { step(a, [], ctx); step(b, [], ctx); }
    expect(stateHash(a)).toBe(stateHash(b));
    const c = deserialize(serialize(a));
    expect(c.saveVersion).toBe(SAVE_VERSION);
    for (let d = 0; d < 400; d++) { step(a, [], ctx); step(c, [], ctx); }
    expect(stateHash(c)).toBe(stateHash(a));
  }, 60_000);

  it('migra partidas de la versión 5 (sin equipo): se crea el equipo y se descuenta de los gastos fijos', () => {
    const s = newGame(2);
    step(s, [], ctx);
    const v5: any = structuredClone(s);
    v5.saveVersion = 5;
    delete v5.market.labor; delete v5.rng.labor; delete v5.rng.team;
    v5.business.team = undefined; v5.business.rep = undefined;
    v5.company.monthlyFixedCostUsd = 18_500;
    for (const c of v5.competitors) { c.business.team = undefined; c.business.rep = undefined; }
    const m = deserialize(JSON.stringify({ format: 'voltaje-save', saveVersion: 5, state: v5 }));
    expect(m.saveVersion).toBe(SAVE_VERSION);
    step(m, [], ctx);
    expect(m.business.team!.employees.length).toBeGreaterThan(0);
    expect(m.company.monthlyFixedCostUsd).toBeLessThan(18_500);
    expect(m.business.rep!.gobierno.PAN).toBe(m.business.reputation);
  });

  it('rendimiento: 10 años con 5 IA y todos los países abiertos < 8 s', () => {
    const s = newGame(11, 1e9, true);
    step(s, [], ctx);
    for (const iso of Object.keys(data.countries)) if (iso !== 'PAN') s.business.presence![iso] = { status: 'activa', level: 'representante', requestedTick: 0, readyTick: 0, setupCostUsd: 0, monthlyCostUsd: 1000 };
    const t0 = performance.now();
    for (let d = 0; d < 3650; d++) step(s, [], ctx);
    expect(performance.now() - t0).toBeLessThan(8000);
    expect(Object.keys(s.market.labor!.candidates).length).toBe(Object.keys(data.countries).length);
  }, 30_000);
});
