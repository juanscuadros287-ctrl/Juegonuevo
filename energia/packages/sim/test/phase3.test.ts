import { describe, expect, it } from 'vitest';
import {
  actorView, applyCommand, createNewGame, currentCapex, decideCompetitor, deserialize, opportunitiesDaily, projectEconomics, researchEffects,
  selectBidQuote, selectCompetitors, selectContracts, selectMyBids, selectOpportunities, selectResearchTree, selectSupplierCatalog,
  serialize, stateHash, step, SAVE_VERSION, supplierLeadFactor, supplierPriceFactor, withActor, balanceSheet,
  type Command, type GameState, type Opportunity, type SimEvent,
} from '../src';
import { gameData } from '@voltaje/data';
import { ctx, data, grid, newGame, SITES } from './helpers';

/** Partida con el mundo de la Fase 3 inicializado (un `step` en pausa) y sin oportunidades aleatorias. */
function world(seed = 1, cash = 50_000_000, competitors = true): GameState {
  const s = createNewGame(gameData.sim, { seed, companyName: 'Prueba S.A.', competitors });
  s.company.cashUsd = cash;
  step(s, [], ctx);
  s.market.opportunities = [];
  return s;
}

function inject(s: GameState, o: Partial<Opportunity> = {}): Opportunity {
  const opp: Opportunity = {
    id: `T${s.market.nextOpportunityId++}`, clientTypeId: 'prueba', clientName: 'Cliente de prueba', countryCode: 'PAN', kind: 'licitacion_publica',
    contract: 'ppa', contractType: 'ppa_simple', mw: 20, years: 15, techs: ['solar_fv', 'eolica_tierra'], ceilingPrice: 90, reservePrice: 90, referencePrice: 70,
    openedTick: s.tick, deadlineTick: s.tick + 30, awardTick: s.tick + 40, codMonths: 30, bidBondUsd: 200_000, performanceBondUsd: 1_000_000,
    weights: { precio: 0.6, tecnica: 0.15, experiencia: 0.15, plazo: 0.1 }, minExperienceMw: 0, minEquityUsd: 0, penaltyUsdMwMonth: 1500, maxDelayMonths: 12,
    prepCostUsd: 30_000, indexation: 0.01, status: 'abierta', bids: [], ...o,
  };
  s.market.opportunities.push(opp);
  return opp;
}

const bid = (opportunityId: string, price: number, extra: Partial<Extract<Command, { type: 'submitBid' }>> = {}): Command =>
  ({ type: 'submitBid', opportunityId, techId: 'solar_fv', price, deliveryMonths: 30, ...extra });

function awardNow(s: GameState, o: Opportunity): SimEvent[] {
  const ev: SimEvent[] = [];
  s.tick = o.awardTick;
  opportunitiesDaily(s, ctx, ev);
  return ev;
}

describe('Licitaciones: adjudicación por puntaje', () => {
  it('la oferta más barata (con los requisitos cumplidos) gana casi siempre; nunca sobre el tope', () => {
    let cheapWins = 0;
    const n = 60;
    for (let seed = 1; seed <= n; seed++) {
      const s = world(seed);
      s.business.reputation = 60; s.business.experienceMwBase = 150; // misma trayectoria que C2
      const o = inject(s);
      // Competidor «Istmo Generación» (C2) ofrece más caro; misma tecnología, plazo y trayectoria.
      expect(applyCommand(s, bid(o.id, 60), ctx).ok).toBe(true);
      expect(withActor(s, 'C2', (v) => applyCommand(v, bid(o.id, 68), ctx))!.ok).toBe(true);
      awardNow(s, o);
      if (o.result!.winnerId === 'jugador') cheapWins++;
      expect(o.result!.ranking.map((r) => r.price)).toEqual(expect.arrayContaining([60, 68])); // precios rivales revelados
    }
    expect(cheapWins / n).toBeGreaterThan(0.8);
    const s = world(3);
    const o = inject(s);
    applyCommand(s, bid(o.id, 95), ctx); // sobre el tope
    awardNow(s, o);
    expect(o.status).toBe('desierta');
    expect(o.result!.ranking[0].disqualified).toMatch(/tope/);
  });

  it('a igual precio pesan la experiencia y la reputación (EGESA, estatal, gana a una empresa nueva)', () => {
    let egesa = 0;
    const n = 40;
    for (let seed = 1; seed <= n; seed++) {
      const s = world(seed);
      const o = inject(s);
      applyCommand(s, bid(o.id, 65), ctx);
      withActor(s, 'C3', (v) => applyCommand(v, bid(o.id, 65), ctx));
      awardNow(s, o);
      if (o.result!.winnerId === 'C3') egesa++;
    }
    expect(egesa / n).toBeGreaterThan(0.85);
    // Con reputación máxima y experiencia, el jugador pasa a ganar
    const s = world(1);
    s.business.reputation = 100; s.business.experienceMwBase = 500;
    if (s.business.rep) s.business.rep.gobierno.PAN = 100; // Fase 6: la reputación con el gobierno también cuenta en licitaciones públicas
    const o = inject(s);
    applyCommand(s, bid(o.id, 65, { effort: 'reforzada' }), ctx);
    withActor(s, 'C3', (v) => applyCommand(v, bid(o.id, 65), ctx));
    awardNow(s, o);
    expect(o.result!.winnerId).toBe('jugador');
  });

  it('ofertar cuesta: preparación + garantía de seriedad (devuelta al perder)', () => {
    const s = world(2, 5_000_000);
    const o = inject(s);
    const cash0 = s.company.cashUsd;
    applyCommand(s, bid(o.id, 80), ctx);
    expect(s.business.restrictedCashUsd).toBeCloseTo(200_000 * 0.5, 6);
    expect(s.company.cashUsd).toBeCloseTo(cash0 - 30_000 - 100_000, 6);
    withActor(s, 'C3', (v) => applyCommand(v, bid(o.id, 55), ctx));
    const ev = awardNow(s, o);
    expect(ev.find((e) => e.type === 'bidResult')).toMatchObject({ won: false });
    expect(s.business.restrictedCashUsd).toBe(0);
    expect(s.company.cashUsd).toBeCloseTo(cash0 - 30_000, 6);
    const mine = selectMyBids(s, ctx)[0];
    expect(mine.status).toBe('perdida');
    expect(mine.ranking!.find((r) => r.actorId === 'C3')!.price).toBe(55);
  });

  it('valida requisitos: tipo de contrato sin investigar, experiencia y caja', () => {
    const s = world(1, 5_000_000);
    const a = inject(s, { contractType: 'ppa_corporativo', kind: 'solicitud_privada', ceilingPrice: undefined });
    const b = inject(s, { minExperienceMw: 50 });
    const r1 = applyCommand(s, bid(a.id, 70), ctx);
    expect(r1.ok).toBe(false);
    expect((r1 as { error: string }).error).toMatch(/investigación/);
    expect((applyCommand(s, bid(b.id, 70), ctx) as { error: string }).error).toMatch(/experiencia/);
    s.company.cashUsd = 10_000;
    const c = inject(s);
    expect((applyCommand(s, bid(c.id, 70), ctx) as { error: string }).error).toMatch(/Caja insuficiente/);
  });
});

describe('Contratos: obligaciones, penalidades y garantías', () => {
  function winContract(s: GameState, extra: Partial<Opportunity> = {}, bidExtra = {}) {
    const o = inject(s, extra);
    expect(applyCommand(s, bid(o.id, 60, bidExtra), ctx).ok).toBe(true);
    awardNow(s, o);
    expect(o.result!.winnerId).toBe('jugador');
    return s.business.contracts.at(-1)!;
  }

  it('ganar convierte la garantía de seriedad en una de cumplimiento', () => {
    const s = world(4, 5_000_000);
    const k = winContract(s);
    expect(k.status).toBe('sin_proyecto');
    expect(s.business.restrictedCashUsd).toBeCloseTo(1_000_000 * 0.5, 6);
    expect(selectContracts(s, ctx)[0].obligations.join(' ')).toMatch(/Asignar un proyecto/);
  });

  it('sin proyecto asignado a tiempo se ejecuta la garantía y baja la reputación', () => {
    const s = world(5, 5_000_000);
    const k = winContract(s);
    const rep = s.business.reputation;
    const ev: SimEvent[] = [];
    while (s.tick <= k.assignDeadlineTick! + 40) ev.push(...step(s, [], ctx));
    expect(k.status).toBe('incumplido');
    expect(ev.some((e) => e.type === 'guaranteeExecuted')).toBe(true);
    expect(s.business.reputation).toBeLessThan(rep - 10);
    expect(s.business.restrictedCashUsd).toBe(0);
    const lines = s.finance.statements.flatMap((x) => Object.entries(x.lines));
    expect(lines.filter(([kk]) => kk === 'garantias_ejecutadas').reduce((a, [, v]) => a + v, 0)).toBeCloseTo(-1_000_000, 0);
  });

  it('un proyecto vinculado recibe el PPA del contrato y paga multa si se atrasa', () => {
    const s = world(6, 20_000_000);
    step(s, [{ type: 'createProject', techId: 'solar_fv', mw: 20, lat: SITES.solar.lat, lon: SITES.solar.lon }], ctx);
    const p = s.projects[0];
    const k = winContract(s, { codMonths: 6 }, { projectId: p.id, deliveryMonths: 6 });
    expect(p.contractId).toBe(k.id);
    expect(p.ppa).toMatchObject({ status: 'firmado', priceUsdMwh: 60 });
    const ev: SimEvent[] = [];
    while (s.tick < k.codDeadlineTick + 70) ev.push(...step(s, [], ctx));
    expect(ev.some((e) => e.type === 'ppaPenalty')).toBe(true);
    // Pasado el plazo máximo se rescinde
    while (s.tick < k.terminationTick + 40) ev.push(...step(s, [], ctx));
    expect(k.status).toBe('incumplido');
    expect(p.ppa!.status).toBe('fallido');
  });

  it('EPC para terceros: exige I+D, se construye, cobra por avance y entrega con margen', () => {
    const s = world(7, 10_000_000);
    const o = inject(s, { contract: 'epc', contractType: 'epc_llave_en_mano', kind: 'solicitud_privada', mw: 3, years: 1, ceilingPrice: undefined, reservePrice: 1500, referencePrice: 1150, codMonths: 10, bidBondUsd: 15_000, performanceBondUsd: 330_000, techs: ['solar_fv'] });
    expect(applyCommand(s, bid(o.id, 1200, { deliveryMonths: 10 }), ctx).ok).toBe(false);
    s.business.research.completed.push('contrato_epc');
    const q = selectBidQuote(s, ctx, o.id, { techId: 'solar_fv', marginPct: 0.15 })!;
    expect(q.ok).toBe(true);
    expect(q.breakEvenPrice).toBeGreaterThan(500);
    expect(q.breakEvenPrice).toBeLessThan(1200);
    expect(applyCommand(s, bid(o.id, q.suggestedPrice, { deliveryMonths: 10 }), ctx).ok).toBe(true);
    awardNow(s, o);
    const k = s.business.contracts[0];
    expect(k.kind).toBe('epc');
    const ev: SimEvent[] = [];
    for (let d = 0; d < 500 && k.status === 'en_desarrollo'; d++) ev.push(...step(s, [], ctx));
    expect(k.status).toBe('cumplido');
    expect(ev.some((e) => e.type === 'epcDelivered')).toBe(true);
    expect(k.revenueUsd).toBeCloseTo(q.suggestedPrice * 3000, -2);
    expect(k.epc!.collectedUsd - k.epc!.spentUsd).toBeGreaterThan(0);
    expect(s.business.epcDeliveredMw).toBe(3);
  });
});

describe('Investigación (I+D)', () => {
  it('empieza solo con solar, eólica, estudios básicos, Panamá y PPA simple', () => {
    const s = world(1);
    const fx = researchEffects(s, ctx);
    expect([...fx.techs!].sort()).toEqual(['eolica_tierra', 'solar_fv']);
    expect([...fx.countries!]).toEqual(['PAN']);
    expect([...fx.contracts!]).toEqual(['ppa_simple']);
    const t = selectResearchTree(s, ctx);
    expect(t.nodes.filter((n) => n.status === 'completado').map((n) => n.id).sort()).toEqual(['contrato_ppa_simple', 'est_basicos', 'mercado_panama', 'tec_eolica_tierra', 'tec_solar_fv']);
    expect(t.nodes.find((n) => n.id === 'tec_geotermica')!.modelPhase).toBeUndefined(); // Fase 4: ya tiene modelo
  });

  it('respeta prerrequisitos y exige presupuesto', () => {
    const s = world(1);
    expect(applyCommand(s, { type: 'startResearch', nodeId: 'contrato_ppa_corporativo' }, ctx).ok).toBe(false); // sin presupuesto
    applyCommand(s, { type: 'setResearchBudget', usdPerMonth: 50_000 }, ctx);
    const r = applyCommand(s, { type: 'startResearch', nodeId: 'contrato_potencia' }, ctx);
    expect((r as { error: string }).error).toMatch(/Requiere antes: PPA corporativo/);
    expect(applyCommand(s, { type: 'startResearch', nodeId: 'contrato_ppa_corporativo' }, ctx).ok).toBe(true);
    expect(applyCommand(s, { type: 'queueResearch', nodeId: 'contrato_potencia' }, ctx).ok).toBe(true); // en cola tras su prerrequisito
    const ev: SimEvent[] = [];
    for (let d = 0; d < 365 * 2; d++) ev.push(...step(s, [], ctx));
    expect(s.business.research.completed).toEqual(expect.arrayContaining(['contrato_ppa_corporativo', 'contrato_potencia']));
    expect(ev.filter((e) => e.type === 'researchCompleted')).toHaveLength(2);
    // Con 50 kUSD/mes el corporativo (90 k, 4 meses) toma ≥ 4 meses; el pago total ≈ costo (+ contratiempos)
    expect(s.business.research.totalSpentUsd).toBeGreaterThanOrEqual(240_000 - 1);
    expect(s.business.research.totalSpentUsd).toBeLessThan(240_000 * 1.35);
    const lines = s.finance.statements.flatMap((x) => Object.entries(x.lines)).filter(([k]) => k === 'investigacion');
    expect(lines.reduce((a, [, v]) => a + v, 0)).toBeCloseTo(-s.business.research.totalSpentUsd, 0);
  });

  it('cancelar conserva la mitad del avance', () => {
    const s = world(1);
    applyCommand(s, { type: 'setResearchBudget', usdPerMonth: 20_000 }, ctx);
    applyCommand(s, { type: 'startResearch', nodeId: 'ef_compras_globales' }, ctx);
    for (let d = 0; d < 120; d++) step(s, [], ctx);
    const prog = s.business.research.active!.progress;
    applyCommand(s, { type: 'cancelResearch', nodeId: 'ef_compras_globales' }, ctx);
    expect(s.business.research.active).toBeNull();
    expect(s.business.research.partial.ef_compras_globales).toBeCloseTo(prog / 2, 9);
  });

  it('los efectos se aplican de verdad: CAPEX −4 %, O&M −10 %, FC +4 %, permisos −15 %, estudios desbloqueados', () => {
    const s = world(1, 30_000_000, false);
    step(s, [{ type: 'createProject', techId: 'solar_fv', mw: 20, lat: SITES.solar.lat, lon: SITES.solar.lon },
      { type: 'createProject', techId: 'eolica_tierra', mw: 30, lat: SITES.eolica.lat, lon: SITES.eolica.lon }], ctx);
    const [sol, eol] = s.projects;
    const input = { techId: 'solar_fv', mw: 20, countryCode: 'PAN', equipmentId: 'modulos_asia_tier1', epcId: 'epc_regional' };
    const capex0 = currentCapex(s, ctx, input).totalUsd;
    const eco0 = projectEconomics(s, ctx, sol);
    const lidar = applyCommand(s, { type: 'commissionStudy', projectId: eol.id, studyId: 'medicion_eolica_lidar' }, ctx);
    expect((lidar as { error: string }).error).toMatch(/investigación/);
    s.business.research.completed.push('ef_compras_globales', 'ef_om_predictivo', 'ef_seguidores_bifaciales', 'ef_permisos', 'est_lidar');
    expect(currentCapex(s, ctx, input).totalUsd / capex0).toBeCloseTo(0.96, 9);
    const eco1 = projectEconomics(s, ctx, sol);
    expect(eco1.fcP50 / eco0.fcP50).toBeCloseTo(1.04, 9);
    expect(eco1.capexUsd / eco0.capexUsd).toBeCloseTo(0.96, 9);
    expect(researchEffects(s, ctx).omMult('solar_fv')).toBeCloseTo(0.9, 9);
    expect(researchEffects(s, ctx).permitTimeMult).toBeCloseTo(0.85, 9);
    expect(applyCommand(s, { type: 'commissionStudy', projectId: eol.id, studyId: 'medicion_eolica_lidar' }, ctx).ok).toBe(true);
    // Permisos: misma semilla con y sin la mejora ⇒ plazo × 0,85
    const durations = (withResearch: boolean) => {
      const t = world(9, 30_000_000, false);
      if (withResearch) t.business.research.completed.push('ef_permisos');
      step(t, [{ type: 'createProject', techId: 'solar_fv', mw: 5, lat: SITES.solar.lat, lon: SITES.solar.lon }], ctx);
      const p = t.projects[0];
      p.studies.prefactibilidad = { studyId: 'prefactibilidad', status: 'completado', startTick: 0, endTick: 0, costUsd: 0, outcome: 'normal' };
      step(t, [{ type: 'applyPermit', projectId: p.id, permitId: 'uso_suelo' }], ctx);
      const r = Object.values(p.permits)[0];
      return r ? r.endTick - r.startTick : NaN;
    };
    const d0 = durations(false), d1 = durations(true);
    expect(Number.isFinite(d0)).toBe(true);
    expect(d1).toBe(Math.max(1, Math.round(d0 * 0.85)));
  });
});

describe('Proveedores y cadena de suministro', () => {
  it('precios de equipos dentro de rangos realistas durante 10 años (varias semillas)', () => {
    for (let seed = 1; seed <= 4; seed++) {
      const s = world(seed, 1e9, false);
      let minS = Infinity, maxS = 0, minW = Infinity, maxW = 0;
      for (let m = 0; m < 120; m++) {
        for (let d = 0; d < 30; d++) step(s, [], ctx);
        const c = selectSupplierCatalog(s, ctx);
        const sol = c.techIndices.find((x) => x.techId === 'solar_fv')!.capexUsdKwNow, win = c.techIndices.find((x) => x.techId === 'eolica_tierra')!.capexUsdKwNow;
        minS = Math.min(minS, sol); maxS = Math.max(maxS, sol); minW = Math.min(minW, win); maxW = Math.max(maxW, win);
      }
      // IRENA/NREL: FV utility 2024–2035 ≈ 450–1.400 USD/kW; eólica en tierra ≈ 900–2.400 USD/kW
      expect(minS).toBeGreaterThan(450); expect(maxS).toBeLessThan(1400);
      expect(minW).toBeGreaterThan(900); expect(maxW).toBeLessThan(2400);
      // La curva de aprendizaje baja la FV a 10 años
      const c = selectSupplierCatalog(s, ctx);
      expect(c.techIndices.find((x) => x.techId === 'solar_fv')!.capexUsdKwNow).toBeLessThan(data.technologies.solar_fv.capex_usd_kw.base * 1.05);
    }
  });

  it('la cola de pedidos alarga plazos y sube precios; la relación da descuento', () => {
    const s = world(1, 1e9, false);
    const lf0 = supplierLeadFactor(s, ctx, 'turbinas_europa');
    const pf0 = supplierPriceFactor(s, ctx, 'turbinas_europa');
    s.market.supply.backlogMw.turbinas_europa = 700; // 2 años de capacidad
    expect(supplierLeadFactor(s, ctx, 'turbinas_europa')).toBeGreaterThan(lf0 * 1.8);
    expect(supplierPriceFactor(s, ctx, 'turbinas_europa')).toBeGreaterThan(pf0 * 1.1);
    s.business.relations.modulos_asia_tier1 = { orders: 3, mw: 60, lateDeliveries: 0 };
    expect(supplierPriceFactor(s, ctx, 'modulos_asia_tier1')).toBeCloseTo(data.suppliers.modulos_asia_tier1.factor_precio * (1 - 0.045), 9);
    const cat = selectSupplierCatalog(s, ctx);
    expect(cat.suppliers.some((x) => x.tipo === 'inversores')).toBe(true);
    expect(cat.suppliers.some((x) => x.tipo === 'logistica')).toBe(true);
  });

  it('inversores y logística aparte cambian el presupuesto', () => {
    const s = world(1, 1e9, false);
    const base = { techId: 'solar_fv', mw: 20, countryCode: 'PAN', equipmentId: 'modulos_occidente', epcId: 'epc_regional' };
    const a = currentCapex(s, ctx, base), b = currentCapex(s, ctx, { ...base, inverterId: 'inversores_asia', logisticsId: 'logistica_premium' });
    expect(b.equipmentUsd).toBeLessThan(a.equipmentUsd);
    expect(b.freightUsd / b.equipmentUsd).toBeCloseTo(0.07, 9);
  });
});

describe('Competidores IA', () => {
  it('los sitios candidatos están en tierra, en Panamá y con recurso', () => {
    for (const site of data.competitors!.sitios_candidatos) {
      const c = grid.cell(site.lat, site.lon);
      expect(c.land, site.nombre).toBe(true);
      expect(c.country?.code, site.nombre).toBe(site.pais);
      expect(c.values[data.technologies[site.tecnologia].recurso!] ?? 0, site.nombre).toBeGreaterThan(0);
    }
  });

  const run = (seed: number, days: number) => {
    const s = newGame(seed, 1e9);
    for (let d = 0; d < days; d++) step(s, [], ctx);
    return s;
  };

  it('son deterministas y guardar → cargar → seguir da el mismo resultado', () => {
    const a = run(11, 365 * 2), b = run(11, 365 * 2);
    expect(stateHash(a)).toBe(stateHash(b));
    expect(a.competitors.some((c) => c.projects.length > 0)).toBe(true);
    const c = deserialize(serialize(a));
    for (let d = 0; d < 365 * 2; d++) { step(a, [], ctx); step(c, [], ctx); }
    expect(stateHash(c)).toBe(stateHash(a));
  });

  it('no usan información oculta: cambiar recurso real, precios de reserva y ofertas ajenas no cambia sus decisiones', () => {
    const s = run(12, 500);
    const t = deserialize(serialize(s));
    for (const c of t.competitors) for (const p of c.projects) { p.site.realFactor *= 1.7; if (p.operation) p.operation.fcReal *= 0.5; }
    for (const p of t.projects) p.site.realFactor *= 0.4;
    for (const o of t.market.opportunities) {
      o.reservePrice = o.ceilingPrice ?? o.reservePrice * 3;
      for (const b of o.bids) b.price *= 0.5;
    }
    const hash = stateHash(s);
    let total = 0;
    for (let i = 0; i < s.competitors.length; i++) {
      const def = data.competitors!.empresas.find((d) => d.id === s.competitors[i].defId)!;
      const a = decideCompetitor(actorView(s, s.competitors[i]), ctx, { def, occupiedSites: new Set() });
      const b = decideCompetitor(actorView(t, t.competitors[i]), ctx, { def, occupiedSites: new Set() });
      expect(b).toEqual(a);
      total += a.length;
    }
    expect(total).toBeGreaterThan(0);
    expect(stateHash(s)).toBe(hash); // decidir no modifica el estado
  });

  it('balance a 10 años: ninguna se vuelve millonaria sin límite y no quiebran todas; 10 años con 5 IA en < 5 s', () => {
    let bankrupt = 0, total = 0, plants = 0;
    const ratios: number[] = [];
    for (const seed of [21, 22, 23]) {
      const t0 = performance.now();
      const s = run(seed, 3650);
      const ms = performance.now() - t0;
      expect(ms).toBeLessThan(5000);
      for (const c of s.competitors) {
        const def = data.competitors!.empresas.find((d) => d.id === c.defId)!;
        total++;
        if (c.status === 'quebrada') { bankrupt++; continue; }
        const eq = balanceSheet(actorView(s, c)).equityUsd;
        // Fase 5: con el spot endógeno y la valoración merchant del comprador se vuelve al límite original (< 6×).
        expect(eq).toBeLessThan(def.caja_inicial_usd * 6);
        ratios.push(eq / def.caja_inicial_usd);
        plants += c.projects.filter((p) => p.stage === 'operacion').length;
      }
    }
    expect(bankrupt).toBeLessThan(total / 2);
    ratios.sort((a, b) => a - b);
    expect(ratios[Math.floor(ratios.length / 2)]).toBeLessThan(4);
    expect(plants).toBeGreaterThan(3);
  }, 30_000);

  it('compiten en licitaciones y los selectores públicos no revelan lo oculto', () => {
    const s = run(13, 365 * 3);
    const comp = selectCompetitors(s, ctx);
    expect(comp.competitors).toHaveLength(5);
    expect(comp.competitors.reduce((a, c) => a + c.bidsWon + c.bidsLost, 0)).toBeGreaterThan(0);
    const json = JSON.stringify(comp) + JSON.stringify(selectOpportunities(s, ctx, { includeClosed: true }));
    expect(json).not.toMatch(/realFactor|fcReal|reservePrice|cashUsd/);
    for (const o of selectOpportunities(s, ctx)) expect(o.result).toBeUndefined();
  });
});

describe('Guardado (versión 3)', () => {
  it('migra partidas de la versión 2 y el mundo se inicializa en el siguiente paso', () => {
    const s = newGame(3, 1e7);
    for (let d = 0; d < 40; d++) step(s, [], ctx);
    const v2 = JSON.parse(serialize(s));
    v2.saveVersion = 2; v2.state.saveVersion = 2;
    delete v2.state.business; delete v2.state.market; delete v2.state.competitors;
    for (const k of Object.keys(v2.state.rng)) if (!['world', 'market', 'projects', 'events', 'ai'].includes(k)) delete v2.state.rng[k];
    const m = deserialize(JSON.stringify(v2));
    expect(m.saveVersion).toBe(SAVE_VERSION);
    expect(m.competitors).toEqual([]);
    step(m, [], ctx);
    expect(m.competitors).toHaveLength(5);
    expect(m.market.initialized).toBe(true);
  });

  it('no se puede guardar una vista de actor', () => {
    const s = world(1);
    expect(() => serialize(actorView(s, s.competitors[0]))).toThrow(/vista/);
  });
});
