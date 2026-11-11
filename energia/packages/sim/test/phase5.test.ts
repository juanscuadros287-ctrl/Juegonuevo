import { describe, expect, it } from 'vitest';
import {
  SAVE_VERSION, actorView, applyCommands, balanceSheet, calibrationFactor, computeMonthPrices, deserialize, planOnPrices, selectPlantDispatch,
  selectPowerMarket, selectWorldEvents, serialize, stateHash, step, storageDay, triggerWorldEvent, worldCapexFactor, currentCapex,
  type GameState, type MarketInputs, type MonthPrices, type Project, type SimContext, type SimEvent,
} from '../src';
import { buildGameData, rawGameData } from '@voltaje/data';
import { ctx, data, newGame, runWithPilot, SITES } from './helpers';

/** Entradas «normales» del mercado (año base, hidrología normal, combustibles de referencia, sin actores). */
function inputs(iso: string, month: number, o: Partial<MarketInputs> = {}): MarketInputs {
  const c = data.countries[iso];
  return {
    year: 2026, month, yearsFromStart: 0, hydrology: 1, demandFactor: 1, carbonUsdT: c.carbono?.precio_usd_tco2.base ?? 0, priceMult: 1,
    fuelPrice: (f) => {
      const map = c.combustibles?.[f];
      const fd = data.markets!.combustibles.find((x) => x.id === (map?.indice ?? f));
      return fd ? fd.precio_usd_mmbtu.base * (map?.factor ?? 1) : 0;
    },
    ...o,
  };
}
const annualMean = (iso: string, o: Partial<MarketInputs> = {}) => {
  const k = calibrationFactor(ctx, iso);
  let s = 0;
  for (let m = 1; m <= 12; m++) s += computeMonthPrices(ctx, iso, inputs(iso, m, o), k).avg;
  return s / 12;
};
const emptyFleet = () => ({ mw: {}, thermal: [], storage: { mw: 0, hours: 0, eff: 0 }, servicesMw: 0, construction: [] });
/** Mes sintético con el mismo precio por hora para los dos tipos de día. */
function synthMonth(day: number[]): MonthPrices {
  const avg = day.reduce((a, b) => a + b, 0) / 24;
  return { year: 2026, month: 1, prices: [day, day], demand: [new Array(24).fill(1000), new Array(24).fill(1000)], curtail: [new Array(24).fill(0), new Array(24).fill(0)],
    avg, peak: avg, offpeak: avg, min: Math.min(...day), max: Math.max(...day), hydrology: 1, thermalMc: [], waterValue: 0 };
}

/** Lleva un proyecto del jugador hasta la operación con el piloto automático. */
function operatingPlant(seed: number, techId = 'solar_fv', mw = 10, site = SITES.solar, competitors = false): GameState {
  const s = newGame(seed, 1e8, competitors);
  step(s, [{ type: 'createProject', techId, mw, lat: site.lat, lon: site.lon }], ctx);
  for (let i = 0; i < 12 && s.projects[0].stage !== 'operacion'; i++) runWithPilot(s, 180, { ppaChannel: null, debtFraction: 0 });
  expect(s.projects[0].stage).toBe('operacion');
  return s;
}

/** Copia de los datos con la vulnerabilidad de un desastre al 100 % (para probar daños de forma determinista). */
function certainDisaster(eventId: string): SimContext {
  const raw = structuredClone(rawGameData) as typeof rawGameData;
  const ev = (raw.events as { eventos: { id: string; efectos: { danos?: { vulnerabilidad: Record<string, number> } } }[] }).eventos.find((e) => e.id === eventId)!;
  for (const k of Object.keys(ev.efectos.danos!.vulnerabilidad)) ev.efectos.danos!.vulnerabilidad[k] = 1;
  return { data: buildGameData(raw).simData, grid: ctx.grid };
}

describe('Mercado eléctrico por país (merit order horario)', () => {
  it('calibrado: el spot medio del año base sin actores es el histórico del país (Panamá ≈ 95)', () => {
    for (const iso of ['PAN', 'COL', 'CHL', 'MEX', 'ESP', 'USA']) {
      const target = data.countries[iso].mercado.precio_spot_medio_usd_mwh.base;
      expect(Math.abs(annualMean(iso) / target - 1), iso).toBeLessThan(0.03);
    }
  });

  it('en Panamá la estación seca es más cara que la lluviosa (endógeno: hidrología mensual)', () => {
    const k = calibrationFactor(ctx, 'PAN');
    const mar = computeMonthPrices(ctx, 'PAN', inputs('PAN', 3), k).avg;
    const oct = computeMonthPrices(ctx, 'PAN', inputs('PAN', 10), k).avg;
    expect(mar).toBeGreaterThan(oct * 1.5);
  });

  it('el spot sube en sequía en los países con mucha hidro (Panamá, Colombia, Brasil)', () => {
    for (const iso of ['PAN', 'COL', 'BRA']) {
      expect(annualMean(iso, { hydrology: 0.6 }), iso).toBeGreaterThan(annualMean(iso) * 1.15);
      expect(annualMean(iso, { hydrology: 1.3 }), iso).toBeLessThan(annualMean(iso));
    }
  });

  it('mucha solar baja el precio del mediodía (canibalización) y deja la noche igual', () => {
    const k = calibrationFactor(ctx, 'DOM');
    const base = computeMonthPrices(ctx, 'DOM', inputs('DOM', 1), k);
    const lots = computeMonthPrices(ctx, 'DOM', inputs('DOM', 1, { fleet: { ...emptyFleet(), mw: { solar: 4000 } } }), k);
    expect(lots.prices[0][12]).toBeLessThan(base.prices[0][12]);
    expect(lots.prices[0][12]).toBeLessThan(lots.prices[0][21] * 0.8);
    expect(lots.prices[0][2]).toBeCloseTo(base.prices[0][2], 0);
    // Panamá también: 2 GW de solar nueva.
    const kp = calibrationFactor(ctx, 'PAN');
    const pan = computeMonthPrices(ctx, 'PAN', inputs('PAN', 3, { fleet: { ...emptyFleet(), mw: { solar: 2500 } } }), kp);
    expect(pan.prices[0][12]).toBeLessThan(computeMonthPrices(ctx, 'PAN', inputs('PAN', 3), kp).prices[0][12]);
  });

  it('escasez: si la demanda supera la oferta disponible, el precio llega al techo', () => {
    const k = calibrationFactor(ctx, 'PAN');
    const mp = computeMonthPrices(ctx, 'PAN', inputs('PAN', 3, { demandFactor: 1.8, hydrology: 0.5 }), k);
    expect(mp.max).toBeCloseTo(data.power!.paises.PAN.precio_techo_usd_mwh, 6);
  });

  it('una crisis de combustibles encarece el spot donde la térmica marca precio', () => {
    expect(annualMean('DOM', { fuelPrice: (f) => inputs('DOM', 1).fuelPrice(f) * 1.6 })).toBeGreaterThan(annualMean('DOM') * 1.3);
  });

  it('el selector del mercado trae curva de oferta, horas, previsión de 12 meses con banda e historial', () => {
    const s = newGame(1, 1e7, false);
    for (let d = 0; d < 70; d++) step(s, [], ctx);
    const v = selectPowerMarket(s, ctx, 'PAN');
    expect(v.available).toBe(true);
    expect(v.hours).toHaveLength(48);
    expect(v.forecast).toHaveLength(12);
    for (const f of v.forecast) { expect(f.p10UsdMwh).toBeLessThanOrEqual(f.avgUsdMwh + 1e-9); expect(f.p90UsdMwh).toBeGreaterThanOrEqual(f.avgUsdMwh - 1e-9); }
    expect(v.history.length).toBeGreaterThanOrEqual(2);
    expect(v.supplyCurve.length).toBeGreaterThan(3);
    for (let i = 1; i < v.supplyCurve.length; i++) expect(v.supplyCurve[i].cumulativeMw).toBeGreaterThan(v.supplyCurve[i - 1].cumulativeMw);
    expect(v.capacityMarket).toBeDefined();
    expect(['nino', 'nina', 'neutral']).toContain(v.climate.enso);
  });
});

describe('Despacho de plantas', () => {
  it('baterías: arbitraje rentable cuando el diferencial supera las pérdidas, y no cuando no', () => {
    const spread = [...new Array(8).fill(20), ...new Array(10).fill(60), ...new Array(6).fill(140)];
    const yes = storageDay(spread, { hours: 4, eff: 0.86, cyclesCap: 1 });
    expect(yes.discharge.reduce((a, b) => a + b, 0)).toBeCloseTo(4, 6);
    expect(yes.profitPerMw).toBeGreaterThan(0);
    // 100 × 0,86 = 86 < 90: no compensa las pérdidas de ida y vuelta.
    const flat = [...new Array(12).fill(90), ...new Array(12).fill(100)];
    const no = storageDay(flat, { hours: 4, eff: 0.86, cyclesCap: 1 });
    expect(no.discharge.reduce((a, b) => a + b, 0)).toBe(0);
    // Con un plan de mes: la carga es barata y la descarga cara.
    const plan = planOnPrices(newGame(1, 1e6, false), ctx, synthMonth(spread), { tech: data.technologies.baterias, countryCode: 'PAN', policy: {}, fcRef: 0.15 });
    expect(plan.genFrac).toBeGreaterThan(0.5);
    expect(plan.captureUsdMwh).toBeGreaterThan(plan.chargeUsdMwh);
    // Reglas: descargar solo sobre 150 ⇒ no descarga.
    const strict = planOnPrices(newGame(1, 1e6, false), ctx, synthMonth(spread), { tech: data.technologies.baterias, countryCode: 'PAN', policy: { descargarSobre: 150 }, fcRef: 0.15 });
    expect(strict.genFrac).toBe(0);
  });

  it('una térmica no genera si el precio está bajo su costo marginal', () => {
    const s = newGame(1, 1e6, false);
    const gas = data.technologies.gas_natural;
    const cheap = planOnPrices(s, ctx, synthMonth(new Array(24).fill(60)), { tech: gas, countryCode: 'PAN', policy: {}, fcRef: 0.85, thermalMcUsdMwh: 80 });
    expect(cheap.genFrac).toBe(0);
    const dear = planOnPrices(s, ctx, synthMonth(new Array(24).fill(100)), { tech: gas, countryCode: 'PAN', policy: {}, fcRef: 0.85, thermalMcUsdMwh: 80 });
    expect(dear.genFrac).toBeCloseTo(1, 9);
    // Con PPA según producción sobre su costo y prioridad PPA, genera aunque el spot esté bajo.
    const ppa = planOnPrices(s, ctx, synthMonth(new Array(24).fill(60)), { tech: gas, countryCode: 'PAN', policy: { prioridad: 'ppa' }, fcRef: 0.85, thermalMcUsdMwh: 80, ppaPriceUsdMwh: 95 });
    expect(ppa.genFrac).toBeCloseTo(1, 9);
  });

  it('la solar se vierte con precio negativo y por congestión de la red', () => {
    const s = newGame(1, 1e6, false);
    const day = new Array(24).fill(40);
    for (let h = 10; h < 15; h++) day[h] = -15;
    const p = planOnPrices(s, ctx, synthMonth(day), { tech: data.technologies.solar_fv, countryCode: 'ESP', policy: {}, fcRef: 0.2 });
    expect(p.curtailedFrac).toBeGreaterThan(0.2);
    expect(p.genFrac).toBeLessThan(0.8);
    expect(p.captureUsdMwh).toBeGreaterThan(0);
  });

  it('planta propia en operación: ingresos separados por fuente, capacidad, y cambio a PPA en bloque con compras al spot', () => {
    const s = operatingPlant(5);
    const p = s.projects[0];
    for (let d = 0; d < 90; d++) step(s, [], ctx);
    const h = p.operation!.history.at(-1)!;
    expect(h.spotUsd).toBeGreaterThan(0);
    expect(h.capacityUsd).toBeGreaterThan(0); // Panamá tiene mercado de potencia
    const view = selectPlantDispatch(s, ctx, p.id)!;
    expect(view.hourly).toHaveLength(48);
    expect(view.hourly.find((x) => x.hour === 12)!.generationMw).toBeGreaterThan(view.hourly.find((x) => x.hour === 2)!.generationMw);
    expect(view.sales.mode).toBe('merchant');
    expect(view.sales.merchantDiscount).toBe(true);
    // Contrato en bloque con un volumen comprometido mayor que la producción ⇒ compra la diferencia al spot.
    p.ppa = { channelId: 'licitacion_etesa', status: 'firmado', startTick: s.tick, endTick: s.tick, priceUsdMwh: 70, years: 15, indexation: 0, codDeadlineTick: 0, penaltyUsdMwMonth: 0, costUsd: 0, settlement: 'bloque', committedMwhYear: 60000 };
    for (let d = 0; d < 62; d++) step(s, [], ctx);
    const h2 = p.operation!.history.at(-1)!;
    expect(h2.purchasesUsd).toBeGreaterThan(0);
    expect(h2.ppaUsd).toBeCloseTo(60000 * 70 * (h2.year && 1) * (new Date(Date.UTC(h2.year, h2.month, 0)).getUTCDate() / 365.25), -3);
    // Terminar el PPA cuesta (nada gratis) y pasa al spot.
    const cash = s.company.cashUsd;
    applyCommands(s, [{ type: 'terminatePpa', projectId: p.id }], ctx);
    expect(p.ppa!.status).toBe('fallido');
    expect(s.company.cashUsd).toBeLessThan(cash);
  }, 60_000);

  it('setDispatchPolicy valida las reglas y la IA no recibe reglas propias', () => {
    const s = operatingPlant(6);
    const p = s.projects[0];
    const ev = applyCommands(s, [{ type: 'setDispatchPolicy', projectId: p.id, policy: { cargarBajo: 10 } }], ctx);
    expect(ev.some((e) => e.type === 'commandRejected')).toBe(true); // umbrales de carga solo para almacenamiento
    const ok = applyCommands(s, [{ type: 'setDispatchPolicy', projectId: p.id, policy: { precioMinimo: 500 } }], ctx);
    expect(ok.some((e) => e.type === 'commandRejected')).toBe(false);
    for (let d = 0; d < 70; d++) step(s, [], ctx);
    expect(p.operation!.history.at(-1)!.energyMwh).toBeLessThan(1); // no produce bajo 500 USD/MWh
  }, 60_000);

  it('sin licencia de generación o contrato de conexión la planta no entra en operación', () => {
    const s = newGame(7, 1e8, false);
    step(s, [{ type: 'createProject', techId: 'solar_fv', mw: 10, lat: SITES.solar.lat, lon: SITES.solar.lon }], ctx);
    let i = 0;
    while (!s.projects[0].construction && i++ < 40) runWithPilot(s, 30, { ppaChannel: null, debtFraction: 0 });
    const p = s.projects[0];
    expect(p.construction).toBeDefined();
    for (const [k, r] of Object.entries(p.permits)) if (data.countries.PAN.permisos.find((x) => x.id === r.permitId)?.grupo === 'contrato_acceso_red') delete p.permits[k];
    const events: SimEvent[] = [];
    for (let d = 0; d < 900 && !p.codBlocked; d++) events.push(...step(s, [], ctx));
    expect(p.codBlocked).toBe(true);
    expect(p.operation).toBeUndefined();
    expect(events.some((e) => e.type === 'operationBlocked')).toBe(true);
  }, 60_000);
});

describe('Eventos del mundo y seguros', () => {
  it('un evento afecta igual al jugador y a la IA (CAPEX, combustibles, daños)', () => {
    const s = newGame(8, 1e8, true);
    step(s, [], ctx);
    const comp = s.competitors[0];
    const before = currentCapex(s, ctx, { techId: 'solar_fv', mw: 10, countryCode: 'PAN' }).totalUsd;
    triggerWorldEvent(s, ctx, 'sobreoferta_equipos', null);
    const after = currentCapex(s, ctx, { techId: 'solar_fv', mw: 10, countryCode: 'PAN' }).totalUsd;
    expect(after).toBeLessThan(before);
    expect(worldCapexFactor(actorView(s, comp), 'solar_fv', 'PAN')).toBe(worldCapexFactor(s, 'solar_fv', 'PAN'));
    // Daños: una planta del jugador y una copia en manos de la IA, huracán seguro.
    const c2 = certainDisaster('huracan');
    const t = operatingPlant(9, 'solar_fv', 10, SITES.solar, true);
    const mine = t.projects[0];
    const ai = t.competitors[0];
    const copy: Project = structuredClone(mine);
    copy.id = `${ai.id}-P99`;
    ai.projects.push(copy);
    const ev: SimEvent[] = [];
    triggerWorldEvent(t, c2, 'huracan', ['PAN'], ev);
    expect(mine.operation!.outages.length).toBeGreaterThan(0);
    expect(copy.operation!.outages.length).toBeGreaterThan(0);
    expect(ev.some((e) => e.type === 'plantDamaged' && e.projectId === mine.id)).toBe(true);
    expect(ev.some((e) => e.type === 'plantDamaged' && e.projectId === copy.id)).toBe(false); // lo de la IA no llega al registro del jugador
    expect(selectWorldEvents(t, ctx).active.some((e) => e.id === 'huracan')).toBe(true);
  }, 60_000);

  it('el seguro de catástrofe cobra prima y paga el siniestro (tras la carencia)', () => {
    const c2 = certainDisaster('terremoto');
    const s = operatingPlant(10);
    const p = s.projects[0];
    applyCommands(s, [{ type: 'buyInsurance', projectId: p.id, coverage: 'danos_lucro' }], c2);
    expect(p.insurance?.premiumUsdYear).toBeGreaterThan(0);
    for (let d = 0; d < 40; d++) step(s, [], c2);
    const premiums = s.finance.statements.at(-1)!.lines.seguro;
    expect(premiums).toBeLessThan(0);
    const cash = s.company.cashUsd;
    triggerWorldEvent(s, c2, 'terremoto', ['PAN']);
    expect(p.insurance!.claims.length).toBe(1);
    expect(s.company.cashUsd).toBeGreaterThan(cash);
    expect(s.finance.month.indemnizaciones).toBeGreaterThan(0);
    const v = selectPlantDispatch(s, c2, p.id)!;
    expect(v.insurance.current?.claims.length).toBe(1);
    // Sin seguro no hay indemnización.
    const u = operatingPlant(10);
    const cash2 = u.company.cashUsd;
    triggerWorldEvent(u, c2, 'terremoto', ['PAN']);
    expect(u.company.cashUsd).toBe(cash2);
    expect(u.finance.month.indemnizaciones ?? 0).toBe(0);
  }, 60_000);

  it('una pandemia baja la demanda y el spot; un impuesto al carbono es permanente', () => {
    const s = newGame(11, 1e7, false);
    step(s, [], ctx);
    const { selectPowerMarket: sel } = { selectPowerMarket };
    const before = sel(s, ctx, 'DOM').forecast[1].avgUsdMwh;
    triggerWorldEvent(s, ctx, 'pandemia', null);
    triggerWorldEvent(s, ctx, 'impuesto_carbono', ['DOM']);
    for (let d = 0; d < 35; d++) step(s, [], ctx);
    expect(s.market.world!.regulation.DOM.carbonAddUsdT).toBe(10);
    expect(selectWorldEvents(s, ctx).active.some((e) => e.id === 'pandemia' && e.effects.length > 0)).toBe(true);
    void before;
  });
});

describe('IA, determinismo y guardado (Fase 5)', () => {
  it('balance de la IA restaurado: patrimonio máximo < 6× del capital inicial en 10 años (3 semillas); 10 años con 5 IA y todos los países < 8 s', () => {
    let bankrupt = 0, total = 0;
    for (const seed of [21, 22, 23]) {
      const s = newGame(seed, 1e9);
      const t0 = performance.now();
      for (let d = 0; d < 3650; d++) step(s, [], ctx);
      expect(performance.now() - t0).toBeLessThan(8000);
      expect(Object.keys(s.market.power!.current).length).toBe(Object.keys(data.countries).length);
      for (const c of s.competitors) {
        total++;
        if (c.status === 'quebrada') { bankrupt++; continue; }
        const def = data.competitors!.empresas.find((d) => d.id === c.defId)!;
        expect(balanceSheet(actorView(s, c)).equityUsd, `${seed} ${c.name}`).toBeLessThan(def.caja_inicial_usd * 6);
      }
    }
    expect(bankrupt).toBeLessThan(total / 2);
  }, 60_000);

  it('los contratos que firma la IA no aparecen en los eventos del jugador', () => {
    const s = newGame(13, 1e9);
    const events: SimEvent[] = [];
    for (let d = 0; d < 365 * 3; d++) events.push(...step(s, [], ctx));
    expect(s.competitors.some((c) => c.business.contracts.length > 0)).toBe(true);
    for (const e of events) if (e.type === 'contractSigned' || e.type === 'guaranteeReleased' || e.type === 'contractFulfilled') expect(e.contractId.startsWith('C')).toBe(false);
  }, 60_000);

  it('determinismo y guardar → cargar → seguir con todo activo (mercado, despacho, eventos, seguros, IA)', () => {
    const make = () => {
      const s = operatingPlant(14, 'solar_fv', 10, SITES.solar, true);
      applyCommands(s, [{ type: 'buyInsurance', projectId: s.projects[0].id, coverage: 'danos' }, { type: 'setDispatchPolicy', projectId: s.projects[0].id, policy: { precioMinimo: 5 } }], ctx);
      triggerWorldEvent(s, ctx, 'crisis_petrolera', null);
      return s;
    };
    const a = make(), b = make();
    for (let d = 0; d < 400; d++) { step(a, [], ctx); step(b, [], ctx); }
    expect(stateHash(a)).toBe(stateHash(b));
    const c = deserialize(serialize(a));
    expect(c.saveVersion).toBe(SAVE_VERSION);
    for (let d = 0; d < 400; d++) { step(a, [], ctx); step(c, [], ctx); }
    expect(stateHash(c)).toBe(stateHash(a));
    expect(a.market.power!.history.PAN.length).toBeGreaterThan(20);
  }, 120_000);

  it('migra partidas de la versión 4 (sin mercado eléctrico ni eventos del mundo)', () => {
    const s = newGame(3, 1e7);
    for (let d = 0; d < 40; d++) step(s, [], ctx);
    const v4 = JSON.parse(serialize(s));
    v4.saveVersion = 4; v4.state.saveVersion = 4;
    delete v4.state.market.power; delete v4.state.market.world; delete v4.state.market.shareHistory;
    const m = deserialize(JSON.stringify(v4));
    expect(m.saveVersion).toBe(SAVE_VERSION);
    expect(m.market.power).toBeUndefined();
    step(m, [], ctx);
    expect(m.market.power).toBeDefined();
    expect(m.market.world).toBeDefined();
    for (let d = 0; d < 60; d++) step(m, [], ctx);
    expect(m.market.power!.history.PAN.length).toBeGreaterThan(0);
  });
});

describe('Datos de la Fase 5 (YAML)', () => {
  it('cada país tiene mercado eléctrico; los esquemas rechazan datos inválidos', () => {
    for (const iso of Object.keys(data.countries)) expect(data.power!.paises[iso], iso).toBeDefined();
    expect(data.world!.eventos.length).toBeGreaterThan(10);
    const bad1 = structuredClone(rawGameData) as any;
    delete bad1.power.paises.PAN;
    expect(() => buildGameData(bad1)).toThrow(/PAN/);
    const bad2 = structuredClone(rawGameData) as any;
    bad2.events.eventos[0].prob_anual = 1.5;
    expect(() => buildGameData(bad2)).toThrow(/events.yaml/);
    const bad3 = structuredClone(rawGameData) as any;
    delete bad3.power.paises.COL.supuesto;
    expect(() => buildGameData(bad3)).toThrow(/fuente|supuesto/);
    const bad4 = structuredClone(rawGameData) as any;
    bad4.events.gobiernos[0].prob = 0.9;
    expect(() => buildGameData(bad4)).toThrow(/gobiernos/);
  });
});
