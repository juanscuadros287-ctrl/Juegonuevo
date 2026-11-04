import { describe, expect, it } from 'vitest';
import {
  capacityFactor, capexBreakdown, captureFactor, crf, gamma, hiddenResourceFactor, lcoe, p90, previewSite, projectEconomics,
  annualFixedCosts, expectedAvailability, type Project,
} from '../src';
import { ctx, data, grid, newGame, SITES } from './helpers';

const solar = data.technologies.solar_fv;
const wind = data.technologies.eolica_tierra;
const PAN = data.countries.PAN;

describe('Factor de capacidad desde el recurso', () => {
  it('función gamma', () => {
    expect(gamma(1.5)).toBeCloseTo(Math.sqrt(Math.PI) / 2, 10);
    expect(gamma(5)).toBeCloseTo(24, 8);
  });

  it('solar FV en Panamá: 17–20 % en el arco seco del Pacífico y 15–21 % en todo el país', () => {
    for (const i of grid.cellsOfCountry('PAN')) {
      const ghi = grid.valueAt('ghi', i), t = grid.valueAt('temperatura', i);
      const fc = capacityFactor(solar, ghi, t);
      expect(fc).toBeGreaterThan(0.15);
      expect(fc).toBeLessThan(0.21);
      if (ghi >= 5.0) { expect(fc).toBeGreaterThan(0.17); expect(fc).toBeLessThan(0.20); }
    }
  });

  it('solar: más calor ⇒ menos FC; desierto de Atacama ⇒ FC alto', () => {
    expect(capacityFactor(solar, 5, 35)).toBeLessThan(capacityFactor(solar, 5, 20));
    const atacama = grid.cell(-23.5, -69);
    const fc = capacityFactor(solar, atacama.values.ghi, atacama.values.temperatura);
    expect(fc).toBeGreaterThan(0.24);
    expect(fc).toBeLessThan(0.34);
  });

  it('eólica en Penonomé: 30–38 %', () => {
    const c = grid.cell(SITES.eolica.lat, SITES.eolica.lon);
    expect(c.country?.code).toBe('PAN');
    const fc = capacityFactor(wind, c.values.viento_tierra, c.values.temperatura);
    expect(fc).toBeGreaterThan(0.30);
    expect(fc).toBeLessThan(0.38);
  });

  it('eólica: curva creciente y valores típicos (IRENA: media mundial ≈ 36 %)', () => {
    let prev = 0;
    for (const v of [4, 5, 6, 7, 8, 9, 10]) {
      const fc = capacityFactor(wind, v, 15);
      expect(fc).toBeGreaterThan(prev);
      prev = fc;
    }
    expect(capacityFactor(wind, 7.5, 15)).toBeGreaterThan(0.38);
    expect(capacityFactor(wind, 7.5, 15)).toBeLessThan(0.5);
    expect(capacityFactor(wind, 4, 15)).toBeLessThan(0.15);
  });
});

describe('Recurso oculto', () => {
  it('es determinista por sitio y distinto entre sitios', () => {
    const a = hiddenResourceFactor(42, 'ghi', 8.2, -80.7, 0.07);
    expect(hiddenResourceFactor(42, 'ghi', 8.2, -80.7, 0.07)).toBe(a);
    expect(hiddenResourceFactor(42, 'ghi', 8.21, -80.7, 0.07)).not.toBe(a);
    expect(hiddenResourceFactor(43, 'ghi', 8.2, -80.7, 0.07)).not.toBe(a);
  });

  it('tiene media ≈ 1 y desviación ≈ σ (7 % solar, 12 % viento)', () => {
    for (const [layer, sigma] of [['ghi', 0.07], ['viento_tierra', 0.12]] as const) {
      const xs: number[] = [];
      for (let i = 0; i < 4000; i++) xs.push(hiddenResourceFactor(7, layer, 8 + (i % 80) * 0.01, -81 + Math.floor(i / 80) * 0.01, sigma));
      const mean = xs.reduce((a, b) => a + b, 0) / xs.length;
      const sd = Math.sqrt(xs.reduce((a, b) => a + (b - mean) ** 2, 0) / xs.length);
      expect(mean).toBeCloseTo(1, 1);
      expect(Math.abs(mean - 1)).toBeLessThan(0.01);
      expect(sd).toBeGreaterThan(sigma * 0.9);
      expect(sd).toBeLessThan(sigma * 1.1);
    }
  });

  it('P90 = P50·(1 − 1,2816σ)', () => {
    expect(p90(100, 0.1)).toBeCloseTo(87.184, 6);
  });
});

describe('Costos y LCOE dentro de rangos de referencia', () => {
  it('CAPEX con incentivos de Panamá: sin aranceles; costo local sube la parte EPC', () => {
    const b = capexBreakdown(ctx, { techId: 'solar_fv', mw: 10, countryCode: 'PAN' });
    expect(b.tariffsUsd).toBe(0);
    expect(b.perKwUsd).toBeGreaterThan(900);
    expect(b.perKwUsd).toBeLessThan(1100);
    const eq = capexBreakdown(ctx, { techId: 'solar_fv', mw: 10, countryCode: 'PAN', equipmentId: 'modulos_asia_economico', epcId: 'epc_local' });
    expect(eq.totalUsd).toBeLessThan(b.totalUsd);
  });

  it('LCOE solar utility en buen sitio (GHI 6,5, WACC 6 %): 35–70 USD/MWh', () => {
    const fc = capacityFactor(solar, 6.5, 22);
    const mw = 50;
    const capex = solar.capex_usd_kw.base * mw * 1000;
    const fixed = solar.om_fijo_usd_kw_ano.base * mw * 1000 + 0.003 * capex;
    const v = lcoe({ capexUsd: capex, fixedCostUsdYear: fixed, varCostUsdMwh: 0, energyMwhYear1: mw * 8760 * fc * 0.99, degradation: solar.degradacion_anual.base, years: 30, rate: 0.06 });
    expect(v).toBeGreaterThan(35);
    expect(v).toBeLessThan(70);
  });

  it('LCOE en Panamá: solar 50–85 y eólica 45–90 USD/MWh (más alto que en los mejores sitios del mundo)', () => {
    const s = newGame(1);
    for (const [techId, mw, site, lo, hi] of [['solar_fv', 20, SITES.solar, 50, 85], ['eolica_tierra', 45, SITES.eolica, 45, 90]] as const) {
      const cell = grid.cell(site.lat, site.lon);
      const tech = data.technologies[techId];
      const p = {
        id: 'X', name: 'X', techId, countryCode: 'PAN', mw, createdTick: 0, stage: 'identificado',
        site: { lat: site.lat, lon: site.lon, cellIndex: cell.index, layer: tech.recurso!, cellValue: cell.values[tech.recurso!], temperatureC: cell.values.temperatura, realFactor: 1 },
        estimate: { value: cell.values[tech.recurso!], sigma: tech.sigma_recurso_sitio, source: 'celda' },
        studies: {}, permits: {}, findings: [], capexFactor: 1, devCostUsd: 0, devExpenseUsd: 0, partnerShare: 0, timeline: [],
      } as Project;
      const eco = projectEconomics(s, ctx, p);
      expect(eco.lcoeUsdMwh).toBeGreaterThan(lo);
      expect(eco.lcoeUsdMwh).toBeLessThan(hi);
    }
  });

  it('disponibilidad esperada 97–100 % con mantenimiento preventivo', () => {
    for (const t of [solar, wind]) {
      const a = expectedAvailability(t, 20, 'preventivo');
      expect(a).toBeGreaterThan(0.97);
      expect(a).toBeLessThanOrEqual(1);
      expect(expectedAvailability(t, 20, 'correctivo')).toBeLessThan(a);
    }
    expect(annualFixedCosts(solar, PAN, 10, 9_000_000).totalUsd).toBeGreaterThan(150_000);
  });

  it('solar y viento capturan más que el precio medio en Panamá (producen en la estación seca, cuando el spot es caro)', () => {
    expect(captureFactor(PAN, 'ghi')).toBeGreaterThan(1);
    expect(captureFactor(PAN, 'viento_tierra')).toBeGreaterThan(captureFactor(PAN, 'ghi'));
  });

  it('vista previa de un sitio sin revelar el recurso real', () => {
    const s = newGame(1);
    const v = previewSite(s, ctx, 'solar_fv', 10, SITES.solar.lat, SITES.solar.lon);
    expect(v.ok).toBe(true);
    expect(v.fcP90).toBeLessThan(v.fcP50);
    expect(previewSite(s, ctx, 'solar_fv', 10, 0, -30).ok).toBe(false);
    expect(previewSite(s, ctx, 'solar_fv', 10, 4.6, -74.1).error).toMatch(/Colombia|todavía/i);
  });

  it('CRF de control', () => {
    expect(crf(0.06, 30)).toBeCloseTo(0.07265, 4);
  });
});

describe('TIR realista de un proyecto típico', () => {
  it('solar 20 MW en el arco seco con PPA de ~70 USD/MWh: TIR de equity 8–15 %', () => {
    const s = newGame(1);
    const cell = grid.cell(SITES.solar.lat, SITES.solar.lon);
    const p = {
      id: 'X', name: 'X', techId: 'solar_fv', countryCode: 'PAN', mw: 20, createdTick: 0, stage: 'cierre_financiero',
      site: { lat: SITES.solar.lat, lon: SITES.solar.lon, cellIndex: cell.index, layer: 'ghi', cellValue: cell.values.ghi, temperatureC: cell.values.temperatura, realFactor: 1 },
      estimate: { value: cell.values.ghi, sigma: 0.025, source: 'medicion_solar_estacion' },
      studies: {}, permits: {}, findings: [], capexFactor: 1, devCostUsd: 0, devExpenseUsd: 0, partnerShare: 0, timeline: [],
      suppliers: { equipmentId: 'modulos_asia_tier1', epcId: 'epc_regional' },
    } as Project;
    const eco = projectEconomics(s, ctx, p, { ppaPriceUsdMwh: 70 });
    expect(eco.priceAssumption).toBe('ppa');
    expect(eco.debtUsd / eco.investmentUsd).toBeGreaterThan(0.4);
    expect(eco.model.irrProject!).toBeGreaterThan(0.06);
    expect(eco.model.irrEquity!).toBeGreaterThan(0.08);
    expect(eco.model.irrEquity!).toBeLessThan(0.15);
    expect(eco.model.minDscr!).toBeGreaterThan(1.2);
    // un PPA malo destruye valor
    expect(projectEconomics(s, ctx, p, { ppaPriceUsdMwh: 45 }).model.irrEquity ?? -1).toBeLessThan(Math.min(0.08, eco.model.irrEquity! - 0.03));
  });
});
