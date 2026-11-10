import { describe, expect, it } from 'vitest';
import {
  Rng, SAVE_VERSION, actorView, balanceSheet, createNewGame, cspCapacityFactor, deserialize, drawPermitDecision, drawWells, evaluateSite,
  expectedMonthlyProduction, expectedPermitPath, geoWellProbabilities, permitApprovalProbability, previewSite, productTerms, projectMonthly,
  selectCountries, selectCountrySheet, selectProjectDetail, selectProjects, selectTechCatalog, serialize, stateHash, step, storageCycles,
  storageProfitable, typicalEconomics, seedStream, techCaptureFactor, type Command, type GameState, type Project, type SimEvent, type TechnologyDef,
} from '../src';
import { gameData } from '@voltaje/data';
import { ctx, data, newGame } from './helpers';

const MARKET_NODES: Record<string, string[]> = {
  COL: ['mercado_regional', 'mercado_colombia'], CRI: ['mercado_regional', 'mercado_costa_rica'], CHL: ['mercado_regional', 'mercado_colombia', 'mercado_chile'],
  KEN: ['mercado_regional', 'mercado_internacional', 'mercado_kenia'], USA: ['mercado_regional', 'mercado_internacional', 'mercado_eeuu'],
};
const ALL_TECH_NODES = ['tec_baterias', 'tec_hidro_pasada', 'tec_hidro_embalse', 'tec_hidro_bombeo', 'est_geofisica', 'tec_geotermica', 'tec_csp', 'est_lidar', 'est_batimetria',
  'tec_eolica_marina', 'tec_biomasa', 'contrato_ppa_corporativo', 'contrato_potencia', 'tec_gas', 'ef_compras_globales', 'tec_hidrogeno', 'tec_fosiles', 'ef_permisos',
  'tec_nuclear', 'tec_smr', 'tec_transmision', 'tec_interconexion', 'tec_eficiencia'];

/** Partida con el mundo inicializado, I+D de tecnologías hecha y presencia activa en los países pedidos (atajo de prueba). */
function world(seed = 1, cash = 2e9, countries: string[] = [], competitors = false): GameState {
  const s = createNewGame(gameData.sim, { seed, companyName: 'Prueba S.A.', competitors });
  s.company.cashUsd = cash;
  step(s, [], ctx);
  s.business.research.completed.push(...ALL_TECH_NODES);
  for (const iso of countries) {
    for (const n of MARKET_NODES[iso] ?? []) if (!s.business.research.completed.includes(n)) s.business.research.completed.push(n);
    s.business.presence![iso] = { status: 'activa', level: 'representante', requestedTick: 0, readyTick: 0, setupCostUsd: 0, monthlyCostUsd: 3000 };
  }
  return s;
}

/** Piloto genérico (como el de helpers.ts) que elige el primer proveedor disponible de cada tipo. */
function pilot(s: GameState, projectId: string, ppaChannel?: string | null, debtFraction = 0.6): Command[] {
  const d = selectProjectDetail(s, ctx, projectId);
  if (!d || !d.summary.active) return [];
  const cmds: Command[] = [];
  for (const f of d.findings) if (f.status === 'abierto' && f.mitigable) cmds.push({ type: 'mitigateFinding', projectId, findingId: f.id });
  if (d.findings.some((f) => f.status !== 'mitigado')) return cmds;
  const groups = new Map<string, typeof d.studies>();
  for (const st of d.studies) groups.set(st.grupo, [...(groups.get(st.grupo) ?? []), st]);
  for (const [, list] of groups) {
    if (!list.some((x) => x.required) || list.some((x) => x.status === 'en_curso' || x.status === 'completado')) continue;
    const avail = list.filter((x) => x.status === 'disponible').sort((a, b) => (a.sigmaAfter ?? 1) - (b.sigmaAfter ?? 1));
    if (avail.length) cmds.push({ type: 'commissionStudy', projectId, studyId: avail[0].id });
  }
  for (const p of d.permits) if (p.status === 'disponible' || (p.status === 'rechazado' && p.blockers.length === 0)) cmds.push({ type: 'applyPermit', projectId, permitId: p.id });
  if (ppaChannel && (!d.ppa || d.ppa.status === 'fallido')) {
    const ch = d.ppaChannels.find((c) => c.id === ppaChannel && c.available);
    if (ch) cmds.push({ type: 'seekPpa', projectId, channelId: ch.id });
  }
  if (d.canFinance.blockers.length === 1 && d.canFinance.blockers[0] === 'Elegir proveedores.') {
    cmds.push({ type: 'selectSuppliers', projectId, equipmentId: d.suppliers.equipment[0].id, epcId: d.suppliers.epc[0].id });
  } else if (d.canFinance.ok && d.ppa?.status !== 'en_proceso') {
    cmds.push({ type: 'arrangeFinancing', projectId, lenderId: 'banco_comercial', debtFraction, partnerShare: 0 });
  }
  if (d.canStartConstruction.ok) cmds.push({ type: 'startConstruction', projectId });
  return cmds;
}

function run(s: GameState, days: number, ppa?: string | null, debtFraction = 0.6): SimEvent[] {
  const ev: SimEvent[] = [];
  for (let i = 0; i < days; i++) {
    let cmds: Command[] = [];
    if (s.tick % 7 === 0) for (const p of s.projects) cmds = cmds.concat(pilot(s, p.id, ppa, debtFraction));
    ev.push(...step(s, cmds, ctx));
  }
  return ev;
}

// ───────────────────────────────────────────────────────────────────────────

describe('LCOE de cada tecnología en un sitio típico (rangos publicados)', () => {
  // Rangos: Lazard LCOE+ 2024 (sin subsidios), IRENA 2023, NREL ATB 2024, IEA; algo más anchos por el costo de capital del juego.
  const cases: [string, string, number, number][] = [
    ['solar_fv', 'CHL', 30, 90], ['eolica_tierra', 'USA', 30, 80], ['geotermica', 'KEN', 60, 110], ['hidro_pasada', 'COL', 40, 110],
    ['hidro_embalse', 'COL', 50, 140], ['csp', 'CHL', 100, 230], ['eolica_marina', 'USA', 70, 145], ['biomasa', 'BRA', 60, 150],
    ['biogas', 'PAN', 60, 160], ['gas_natural', 'USA', 40, 110], ['carbon', 'USA', 65, 170], ['petroleo', 'PAN', 120, 300],
    ['nuclear', 'USA', 110, 230], ['smr', 'USA', 120, 260], ['baterias', 'USA', 120, 300], ['hidro_bombeo', 'USA', 100, 260],
    ['linea_transmision', 'PAN', 3, 25], ['interconexion', 'PAN', 4, 30], ['eficiencia_energetica', 'MEX', 10, 60],
  ];
  const s = createNewGame(gameData.sim, { seed: 1, companyName: 'x' });
  for (const [tech, iso, lo, hi] of cases) {
    it(`${tech} (${iso}): ${lo}–${hi} USD/MWh`, () => {
      const e = typicalEconomics(s, ctx, tech, iso)!;
      expect(e).not.toBeNull();
      expect(e.lcoeUsdMwh).toBeGreaterThan(lo);
      expect(e.lcoeUsdMwh).toBeLessThan(hi);
    });
  }
  it('hidrógeno verde: LCOH 3–8 USD/kg (IEA GHR 2024)', () => {
    for (const iso of ['CHL', 'ESP', 'PAN']) {
      const e = typicalEconomics(s, ctx, 'hidrogeno_verde', iso)!;
      expect(e.lcohUsdKg!).toBeGreaterThan(3);
      expect(e.lcohUsdKg!).toBeLessThan(8);
    }
  });
  it('las térmicas pagan combustible y carbono; el carbono de España (EU ETS) les quita despacho', () => {
    const us = typicalEconomics(s, ctx, 'carbon', 'USA')!, mx = typicalEconomics(s, ctx, 'gas_natural', 'MEX')!, pa = typicalEconomics(s, ctx, 'gas_natural', 'PAN')!;
    expect(us.fuelCostUsdMwh).toBeGreaterThan(10);
    expect(pa.fuelCostUsdMwh).toBeGreaterThan(mx.fuelCostUsdMwh); // GNL importado más caro que el gas de Texas
    const t = data.technologies.gas_natural, esp = data.countries.ESP;
    const terms = productTerms(null, ctx, t, esp, { spotUsdMwh: 68, capture: 1, yearsFromStart: 0 });
    expect(terms.fuel.carbonUsdMwh).toBeGreaterThan(20);
    expect(terms.dispatch).toBeLessThan(0.5);
  });
});

describe('Geotermia: pozos secos', () => {
  const t = data.technologies.geotermica;
  it('20–30 % de pozos exploratorios secos en zonas buenas, mucho más fuera (10 000 pozos)', () => {
    const rng = new Rng(seedStream(7, 'pozos'));
    const rate = (hf: number) => { const p = geoWellProbabilities(t, hf); return drawWells(rng, 10_000, p.dry, p.low).dry / 10_000; };
    const good = rate(190), mid = rate(130), bad = rate(90);
    expect(good).toBeGreaterThan(0.2);
    expect(good).toBeLessThan(0.3);
    expect(mid).toBeGreaterThan(good);
    expect(bad).toBeGreaterThan(0.45);
    expect(geoWellProbabilities(t, 190, true).dry).toBeLessThan(geoWellProbabilities(t, 190).dry); // los de desarrollo fallan menos
    expect(geoWellProbabilities(t, 190).mwPerWell).toBeGreaterThan(geoWellProbabilities(t, 100).mwPerWell);
  });
  it('fuera de zonas volcánicas no se puede (recurso mínimo) y en el Rift sí', () => {
    expect(evaluateSite(ctx, 'geotermica', 40.4, -3.7).ok).toBe(false); // Madrid
    expect(evaluateSite(ctx, 'geotermica', -0.9, 36.3).ok).toBe(true); // Olkaria
  });
  it('la perforación exploratoria abre un hallazgo si todos los pozos salen secos; si no, mide el reservorio', () => {
    let dry = 0, measured = 0;
    for (let seed = 1; seed <= 30; seed++) {
      const s = world(seed, 2e9, ['KEN']);
      step(s, [{ type: 'createProject', techId: 'geotermica', mw: 50, lat: -0.9, lon: 36.3 }], ctx);
      const p = s.projects[0];
      p.studies.prospeccion_geofisica = { studyId: 'prospeccion_geofisica', status: 'completado', startTick: 0, endTick: 0, costUsd: 0, outcome: 'normal' };
      p.studies.prefactibilidad = { studyId: 'prefactibilidad', status: 'completado', startTick: 0, endTick: 0, costUsd: 0, outcome: 'normal' };
      const ev = step(s, [{ type: 'commissionStudy', projectId: p.id, studyId: 'perforacion_exploratoria' }], ctx);
      expect(ev.some((e) => e.type === 'commandRejected')).toBe(false);
      const end = p.studies.perforacion_exploratoria.endTick;
      while (s.tick <= end) step(s, [], ctx);
      if (p.findings.some((f) => f.id === 'reservorio_no_comercial')) dry++;
      else { measured++; expect(p.estimate.source).toBe('perforacion_exploratoria'); expect(p.estimate.sigma).toBeLessThanOrEqual(0.05); }
    }
    expect(measured).toBeGreaterThan(20); // P(3 secos) ≈ 1,6 % en Olkaria
    expect(dry + measured).toBe(30);
  });
});

describe('Hidro, almacenamiento y CSP', () => {
  it('hidro de pasada muy estacional; el embalse regula y traslada energía a los meses caros', () => {
    const s = world(1, 1e9, ['COL']);
    step(s, [{ type: 'createProject', techId: 'hidro_pasada', mw: 20, lat: 6.9, lon: -75.4 }, { type: 'createProject', techId: 'hidro_embalse', mw: 200, lat: 6.95, lon: -75.45 }], ctx);
    expect(s.projects).toHaveLength(2);
    const [ror, res] = s.projects;
    const prof = (p: Project) => { const m = expectedMonthlyProduction(ctx, p, 1200, 1000, 2026).map((x) => x.p50Mwh / 100); return Math.max(...m) / Math.min(...m); };
    expect(prof(ror)).toBeGreaterThan(2);
    expect(prof(res)).toBeLessThan(prof(ror));
    const pan = data.countries.PAN, emb = data.technologies.hidro_embalse, pas = data.technologies.hidro_pasada;
    expect(productTerms(null, ctx, emb, pan, { spotUsdMwh: 95, capture: 1, yearsFromStart: 0 }).priceUsdMwh).toBeGreaterThan(0);
    expect(techCaptureFactor(pan, emb, 'hidro')).toBeGreaterThan(techCaptureFactor(pan, pas, 'hidro'));
    // Lluvia: un año seco baja la producción (variabilidad interanual alta)
    expect(pas.variabilidad.interanual).toBeGreaterThan(0.1);
  });

  it('baterías: el arbitraje se hace solo si punta × eficiencia > valle; ganan con el diferencial y degradan por ciclos', () => {
    const b = data.technologies.baterias, pan = data.countries.PAN;
    expect(storageProfitable(b, pan)).toBe(true);
    const t = productTerms(null, ctx, b, pan, { spotUsdMwh: 95, capture: 1, yearsFromStart: 0 });
    expect(t.priceUsdMwh).toBeCloseTo(95 * 1.3, 6);
    expect(t.fuel.varUsdMwh).toBeCloseTo(95 * 0.75 / 0.86, 6);
    expect(t.priceUsdMwh - t.fuel.varUsdMwh).toBeGreaterThan(0); // margen positivo por MWh descargado
    const flat = { ...pan, mercado: { ...pan.mercado, factor_punta: 1.05, factor_valle: 0.95 } };
    expect(storageProfitable(b, flat)).toBe(false);
    expect(storageCycles(b, flat)).toBe(0);
    expect(productTerms(null, ctx, b, flat, { spotUsdMwh: 95, capture: 1, yearsFromStart: 0 }).dispatch).toBe(0);
    expect(typicalEconomics(createNewGame(gameData.sim, { seed: 1, companyName: 'x' }), ctx, 'baterias', 'PAN')!.fc).toBeGreaterThan(0.1);
  });

  it('una batería en operación cobra en punta y paga la carga en valle (contabilidad)', () => {
    const s = world(3, 1e9);
    step(s, [{ type: 'createProject', techId: 'baterias', mw: 20, lat: 8.2, lon: -80.7 }], ctx);
    run(s, 365 * 5, null, 0); // sin contrato de potencia ningún banco presta a un arbitraje puro: capital propio
    const p = s.projects[0];
    expect(p.stage).toBe('operacion');
    const lines = s.finance.statements.slice(-12).reduce((a, st) => { for (const [k, v] of Object.entries(st.lines)) a[k] = (a[k] ?? 0) + v; return a; }, {} as Record<string, number>);
    expect(lines.combustible).toBeLessThan(0);
    expect(lines.ingresos).toBeGreaterThan(-lines.combustible);
    const hist = p.operation!.history.slice(-12);
    const fc = hist.reduce((a, h) => a + h.energyMwh, 0) / (20 * 730 * hist.length);
    expect(fc).toBeGreaterThan(0.1);
    expect(fc).toBeLessThan(0.17);
  }, 30_000);

  it('CSP: más horas de almacenamiento ⇒ más FC', () => {
    const t = data.technologies.csp;
    const with0: TechnologyDef = { ...t, csp: { ...t.csp!, horas_almacenamiento: 0 } };
    expect(cspCapacityFactor(t, 7.5)).toBeGreaterThan(cspCapacityFactor(with0, 7.5) * 1.5);
    expect(cspCapacityFactor(with0, 7.5)).toBeGreaterThan(0.2);
    expect(cspCapacityFactor(t, 10)).toBeLessThanOrEqual(t.csp!.fc_max);
  });

  it('eólica marina: solo en el mar, cerca de un país, y el CAPEX sube con la distancia y la profundidad', () => {
    expect(evaluateSite(ctx, 'eolica_marina', 8.6, -80.3).ok).toBe(false); // tierra
    const near = evaluateSite(ctx, 'eolica_marina', 12.6, -72.5);
    expect(near.countryCode).toBe('COL');
    expect(near.extras.offshore).toBe(true);
    expect(near.extras.depthM).toBeGreaterThan(0);
    const s = world(1, 1e9, ['COL']);
    const pv = previewSite(s, ctx, 'eolica_marina', 300, 12.6, -72.5);
    expect(pv.countryCode).toBe('COL');
    expect(pv.siteCapexFactor).toBeGreaterThanOrEqual(1);
    expect(pv.visualKind).toBe('eolica_mar');
  });
});

describe('Países y permisos', () => {
  it('12 países además de Panamá, cada uno con su sistema de permisos y autoridades reales', () => {
    const isos = Object.keys(data.countries);
    expect(isos.length).toBeGreaterThanOrEqual(12);
    for (const iso of ['CRI', 'COL', 'DOM', 'CHL', 'MEX', 'BRA', 'KEN', 'ISL', 'ESP', 'IDN', 'PHL', 'USA']) expect(isos).toContain(iso);
    const auth = (iso: string) => data.countries[iso].permisos.map((p) => p.autoridad).join(' ');
    expect(auth('COL')).toMatch(/Consulta Previa/);
    expect(auth('CHL')).toMatch(/Servicio de Evaluación Ambiental/);
    expect(auth('MEX')).toMatch(/SEMARNAT/);
    expect(auth('BRA')).toMatch(/IBAMA/);
    expect(auth('PHL')).toMatch(/NCIP/);
    expect(auth('ISL')).toMatch(/Althingi/);
    expect(auth('USA')).toMatch(/ERCOT/);
    expect(auth('KEN')).toMatch(/NEMA/);
  });

  it('duraciones y probabilidades distintas por país (ruta crítica esperada de una solar de 50 MW)', () => {
    const paths = Object.fromEntries(['PAN', 'COL', 'CHL', 'USA', 'ESP', 'BRA'].map((iso) => [iso, expectedPermitPath(data.countries[iso], 'solar_fv', 50)]));
    expect(paths.COL.days).toBeGreaterThan(paths.PAN.days); // consulta previa + UPME
    expect(paths.COL.approvalAll).toBeLessThan(paths.PAN.approvalAll);
    expect(paths.USA.days).toBeGreaterThan(paths.CHL.days * 0.8); // cola de ERCOT
    const days = Object.values(paths).map((x) => Math.round(x.days));
    expect(new Set(days).size).toBe(days.length);
  });

  it('la consulta previa de Colombia converge a su probabilidad (10 000 sorteos) y es la más incierta', () => {
    const d = data.countries.COL.permisos.find((p) => p.id === 'consulta_previa')!;
    const rng = new Rng(seedStream(11, 'cp'));
    let ok = 0;
    const n = 10_000;
    for (let i = 0; i < n; i++) {
      let info = 0;
      for (;;) { const dec = drawPermitDecision(rng, d, info); if (dec === 'info_adicional') { info++; continue; } if (dec === 'aprobado') ok++; break; }
    }
    expect(ok / n).toBeCloseTo(permitApprovalProbability(d), 1.5);
    const pan = data.countries.PAN.permisos.find((p) => p.id === 'participacion_ciudadana')!;
    expect(permitApprovalProbability(d)).toBeLessThan(permitApprovalProbability(pan));
    expect((d.duracion_dias.max ?? 0) - (d.duracion_dias.min ?? 0)).toBeGreaterThan(700);
  });

  it('para operar hace falta I+D del mercado y presencia (constitución con costo, días y costo mensual)', () => {
    const s = createNewGame(gameData.sim, { seed: 2, companyName: 'x', competitors: false });
    s.company.cashUsd = 1e8;
    step(s, [], ctx);
    const create: Command = { type: 'createProject', techId: 'solar_fv', mw: 20, lat: 10.0, lon: -73.6 };
    let ev = step(s, [create, { type: 'openPresence', countryCode: 'COL' }], ctx);
    expect(ev.filter((e) => e.type === 'commandRejected').map((e) => (e as { error: string }).error).join(' ')).toMatch(/investigación/);
    s.business.research.completed.push('mercado_regional', 'mercado_colombia');
    ev = step(s, [create], ctx);
    expect(ev.find((e) => e.type === 'commandRejected')).toBeDefined(); // sin presencia
    const cash0 = s.company.cashUsd;
    ev = step(s, [{ type: 'openPresence', countryCode: 'COL' }], ctx);
    expect(ev.some((e) => e.type === 'presenceRequested')).toBe(true);
    expect(s.company.cashUsd).toBeLessThan(cash0 - 10_000);
    const ready = s.business.presence!.COL.readyTick;
    while (s.tick <= ready) ev = step(s, [], ctx);
    expect(s.business.presence!.COL.status).toBe('activa');
    ev = step(s, [create], ctx);
    expect(s.projects.some((p) => p.countryCode === 'COL')).toBe(true);
    const sheet = selectCountrySheet(s, ctx, 'COL')!;
    expect(sheet.presence.active).toBe(true);
    expect(sheet.permits.nodes.length).toBeGreaterThan(5);
    expect(sheet.permits.edges.length).toBeGreaterThan(3);
    expect(sheet.currency.code).toBe('COP');
    expect(selectCountries(s, ctx).find((c) => c.iso3 === 'COL')!.presence).toBe('activa');
    // costo mensual del representante
    for (let i = 0; i < 40; i++) step(s, [], ctx);
    expect(s.finance.statements.some((st) => (st.lines.presencia ?? 0) < 0)).toBe(true);
  });

  it('restricciones por país: nuclear prohibida en Panamá, Texas como única zona de EE. UU.', () => {
    expect(evaluateSite(ctx, 'nuclear', 8.2, -80.7).errors.join(' ')).toMatch(/nuclear/i);
    expect(evaluateSite(ctx, 'solar_fv', 34.0, -117.0).errors.join(' ')).toMatch(/Texas/); // California
    expect(evaluateSite(ctx, 'solar_fv', 31.5, -100.0).ok).toBe(true); // Texas
  });
});

describe('Riesgo cambiario e inflación', () => {
  it('una devaluación baja los ingresos en USD de un PPA en moneda local; la deuda en USD no cambia', () => {
    const s = world(5, 1e9, ['COL']);
    step(s, [{ type: 'createProject', techId: 'solar_fv', mw: 20, lat: 10.0, lon: -73.6 }], ctx);
    const p = s.projects[0];
    // Planta en operación con PPA en pesos (atajo de prueba) y deuda en USD.
    p.ppa = { channelId: 'subasta_largo_plazo', status: 'firmado', startTick: s.tick, endTick: s.tick, priceUsdMwh: 50, years: 15, indexation: 0, codDeadlineTick: s.tick + 9999, penaltyUsdMwMonth: 0, costUsd: 0, currency: 'local', fxAtSigning: data.countries.COL.moneda.usd_por_unidad };
    p.operation = { codTick: s.tick, endOfLifeTick: s.tick + 10_000, maintenance: 'preventivo', outages: [], fcReal: 0.2, yearFactor: 1, failureMultiplier: 1,
      month: { energyMwh: 3000, availSum: 30, days: 30, repairUsd: 0 }, history: [], totalEnergyMwh: 0, totalRevenueUsd: 0, grossAssetUsd: 2e7, accumulatedDepreciationUsd: 0 };
    p.debt = { principalUsd: 1e7, outstandingUsd: 1e7, rate: 0.08, tenorMonths: 168, monthsPaid: 0, monthlyPayment: 100_000 };
    p.stage = 'operacion';
    const month = (fx: number) => {
      const t = deserialize(serialize(s));
      t.market.fx!.COL = fx;
      t.finance.month = {};
      const q = t.projects[0];
      projectMonthly(t, ctx, q, new Rng(seedStream(1, 'x')), 2026, 3, []);
      return { rev: t.finance.month.ingresos ?? 0, debt: (t.finance.month.intereses ?? 0) + (t.finance.month.deuda_amortizacion ?? 0) };
    };
    const base = month(1), dev = month(0.7);
    expect(dev.rev / base.rev).toBeCloseTo(0.7, 2);
    expect(dev.debt).toBeCloseTo(base.debt, 6);
  });

  it('los tipos de cambio se mueven (con shocks) y Panamá (dolarizado) no', () => {
    const s = world(8, 1e9);
    for (let i = 0; i < 365 * 5; i++) step(s, [], ctx);
    expect(s.market.fx!.PAN).toBe(1);
    expect(s.market.fx!.COL).not.toBe(1);
    expect(s.market.macroHistory!.length).toBeGreaterThan(50);
    const sheet = selectCountrySheet(s, ctx, 'BRA')!;
    expect(sheet.currency.usdPerUnitNow).not.toBeCloseTo(sheet.currency.usdPerUnitStart, 6);
    expect(s.market.fuels!.gnl).not.toBe(1);
  });
});

describe('Ciclo completo de tecnologías nuevas', () => {
  it('geotérmica en Kenia: exploración, permisos, pozos de producción y operación', () => {
    let ok = false;
    for (const seed of [1, 2, 3]) {
      const s = world(seed, 2e9, ['KEN']);
      step(s, [{ type: 'createProject', techId: 'geotermica', mw: 30, lat: -0.9, lon: 36.3 }], ctx);
      const ev = run(s, 365 * 10, 'ppa_kplc');
      const p = s.projects[0];
      if (p.stage !== 'operacion') continue;
      expect(ev.some((e) => e.type === 'wellsDrilled')).toBe(true);
      expect(p.construction!.wells!.drilled).toBeGreaterThanOrEqual(p.construction!.wells!.plannedProducers);
      const h = p.operation!.history.slice(-12);
      const fc = h.reduce((a, x) => a + x.energyMwh, 0) / (30 * 730 * h.length);
      expect(fc).toBeGreaterThan(0.7);
      ok = true;
      break;
    }
    expect(ok).toBe(true);
  }, 60_000);

  it('ESCO: el ahorro garantizado se fija con la auditoría y el faltante se paga al cliente', () => {
    const s = world(4, 1e9);
    step(s, [{ type: 'createProject', techId: 'eficiencia_energetica', mw: 5, lat: 8.3, lon: -80.6 }], ctx);
    const p = s.projects[0];
    for (let i = 0; i < 365 * 4 && !p.operation; i++) run(s, 1, null, 0);
    expect(p.stage).toBe('operacion');
    expect(p.operation!.guaranteedMwhYear).toBeGreaterThan(0);
    const before = run(s, 120, null, 0);
    p.operation!.fcReal *= 0.6; // la producción del cliente cae: el ahorro real queda bajo el garantizado (atajo de prueba)
    const after = run(s, 120, null, 0);
    expect(after.filter((e) => e.type === 'savingsShortfall').length).toBeGreaterThan(before.filter((e) => e.type === 'savingsShortfall').length);
  }, 30_000);
});

describe('Selectores para la UI', () => {
  const s = createNewGame(gameData.sim, { seed: 1, companyName: 'x' });
  it('catálogo: todas las tecnologías con disponibilidad, parámetros, LCOE típico por país y tipo visual', () => {
    const cat = selectTechCatalog(s, ctx);
    expect(cat.length).toBe(Object.keys(data.technologies).length);
    const kinds = new Set(cat.map((t) => t.visualKind));
    for (const k of ['geotermica', 'hidro_embalse', 'csp', 'eolica_mar', 'nuclear', 'baterias', 'hidrogeno', 'linea_transmision', 'eficiencia_industrial', 'gas']) expect(kinds).toContain(k);
    const geo = cat.find((t) => t.id === 'geotermica')!;
    expect(geo.unlocked).toBe(false);
    expect(geo.unlockNode?.id).toBe('tec_geotermica');
    expect(geo.byCountry.find((c) => c.countryCode === 'KEN')!.typical!.lcoeUsdMwh).toBeGreaterThan(0);
    expect(cat.find((t) => t.id === 'nuclear')!.byCountry.find((c) => c.countryCode === 'PAN')!.allowed).toBe(false);
  });
  it('previewSite para todas las tecnologías (recurso, restricciones, kind visual) y selectProjects con kind visual', () => {
    const t = world(1, 1e9, ['USA']);
    const sites: Record<string, [number, number]> = {
      solar_fv: [31.5, -100], eolica_tierra: [32.4, -99.7], csp: [31.5, -103.5], gas_natural: [29.8, -95.4], baterias: [31.5, -100], hidrogeno_verde: [29.8, -95.4],
      nuclear: [28.8, -96.0], eficiencia_energetica: [29.8, -95.4], biomasa: [31.0, -94.5],
    };
    for (const [tech, [lat, lon]] of Object.entries(sites)) {
      const pv = previewSite(t, ctx, tech, data.technologies[tech].escala_mw.tipico, lat, lon);
      expect(pv.visualKind, tech).toBeTruthy();
      expect(pv.restrictions, tech).toBeDefined();
      expect(pv.ok, `${tech}: ${pv.errors?.join(' ')}`).toBe(true);
      expect(pv.lcoeUsdMwh!, tech).toBeGreaterThan(0);
    }
    const line = previewSite(t, ctx, 'linea_transmision', 300, 31.5, -100, { lat: 30.3, lon: -97.7 });
    expect(line.ok, line.errors?.join(' ')).toBe(true);
    expect(line.site!.to!.km).toBeGreaterThan(200);
    step(t, [{ type: 'createProject', techId: 'gas_natural', mw: 400, lat: 29.8, lon: -95.4 }], ctx);
    expect(selectProjects(t, ctx)[0].visualKind).toBe('gas');
    expect(JSON.stringify(previewSite(t, ctx, 'solar_fv', 50, 31.5, -100))).not.toMatch(/realFactor/);
  });
});

describe('IA en varios países, determinismo, guardado y rendimiento', () => {
  const runAi = (seed: number, days: number) => {
    const s = newGame(seed, 1e9);
    for (let d = 0; d < days; d++) step(s, [], ctx);
    return s;
  };

  it('la IA se expande a otros países con los mismos comandos y sin romper el balance; 10 años con 5 IA < 5 s', () => {
    let abroad = 0, presence = 0;
    for (const seed of [31, 32]) {
      const t0 = performance.now();
      const s = runAi(seed, 3650);
      expect(performance.now() - t0).toBeLessThan(5000);
      for (const c of s.competitors) {
        presence += Object.values(c.business.presence ?? {}).filter((p) => p.status === 'activa').length;
        abroad += c.projects.filter((p) => p.countryCode !== 'PAN').length;
        expect(Number.isFinite(c.company.cashUsd)).toBe(true);
        const def = data.competitors!.empresas.find((d) => d.id === c.defId)!;
        if (c.status === 'activa') expect(balanceSheet(actorView(s, c)).equityUsd).toBeLessThan(def.caja_inicial_usd * 12); // mismo límite que la prueba de la Fase 3
      }
      expect(s.market.opportunities.some((o) => o.countryCode !== 'PAN')).toBe(true);
    }
    expect(presence).toBeGreaterThan(0);
    expect(abroad).toBeGreaterThan(0);
  }, 30_000);

  it('determinismo y guardar → cargar → seguir con todo activo (países, tecnologías nuevas, IA, tipos de cambio)', () => {
    const make = () => {
      const s = world(9, 3e9, ['COL', 'USA', 'KEN'], true);
      step(s, [
        { type: 'createProject', techId: 'solar_fv', mw: 20, lat: 10.0, lon: -73.6 },
        { type: 'createProject', techId: 'gas_natural', mw: 400, lat: 29.8, lon: -95.4 },
        { type: 'createProject', techId: 'geotermica', mw: 30, lat: -0.9, lon: 36.3 },
        { type: 'createProject', techId: 'baterias', mw: 20, lat: 8.2, lon: -80.7 },
      ], ctx);
      return s;
    };
    const a = make(), b = make();
    run(a, 365 * 2, null); run(b, 365 * 2, null);
    expect(stateHash(a)).toBe(stateHash(b));
    const c = deserialize(serialize(a));
    expect(c.saveVersion).toBe(SAVE_VERSION);
    run(a, 365 * 2, null); run(c, 365 * 2, null);
    expect(stateHash(c)).toBe(stateHash(a));
    expect(a.projects.length).toBe(4);
  }, 60_000);

  it('migra partidas de la versión 3 (sin presencia ni tipos de cambio)', () => {
    const s = newGame(3, 1e7);
    for (let d = 0; d < 40; d++) step(s, [], ctx);
    const v3 = JSON.parse(serialize(s));
    v3.saveVersion = 3; v3.state.saveVersion = 3;
    delete v3.state.business.presence; delete v3.state.market.fx; delete v3.state.market.fuels; delete v3.state.market.macroHistory;
    delete v3.state.rng.fx; delete v3.state.rng.fuels;
    for (const c of v3.state.competitors) delete c.business.presence;
    const m = deserialize(JSON.stringify(v3));
    expect(m.saveVersion).toBe(4);
    expect(m.business.presence).toEqual({});
    step(m, [], ctx);
    expect(m.market.fx!.COL).toBe(1);
    for (let d = 0; d < 60; d++) step(m, [], ctx);
    expect(m.market.macroHistory!.length).toBeGreaterThan(0);
  });
});

describe('Datos de la Fase 4', () => {
  it('cada tecnología tiene modelo 3D, proveedor de equipos y EPC, y ningún nodo de I+D queda marcado para otra fase', () => {
    for (const t of Object.values(data.technologies)) {
      expect(Object.values(data.suppliers).some((s) => s.tipo === 'equipos' && s.tecnologias.includes(t.id)), t.id).toBe(true);
      expect(Object.values(data.suppliers).some((s) => s.tipo === 'epc' && s.tecnologias.includes(t.id)), t.id).toBe(true);
      if (!['solar_fv', 'eolica_tierra'].includes(t.id)) expect(t.visual, t.id).toBeTruthy();
    }
    expect(data.research!.nodos.filter((n) => n.fase_modelo !== undefined)).toEqual([]);
    for (const c of Object.values(data.countries)) {
      expect(c.expansion, c.iso3).toBeDefined();
      expect(c.ppa.canales.length, c.iso3).toBeGreaterThan(0);
    }
  });
});
