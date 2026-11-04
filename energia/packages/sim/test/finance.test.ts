import { describe, expect, it } from 'vitest';
import {
  amortizationSchedule, annuityPayment, costOfEquity, crf, debtCapacityFrench, irr, lcoe, npv, percentile, runProjectModel, sizeDebt, wacc,
} from '../src';

describe('VAN y TIR (valores calculados a mano)', () => {
  it('VAN', () => {
    // −1000 + 300/1,08 + 400/1,08² + 500/1,08³ = 17,63
    expect(npv(0.08, [-1000, 300, 400, 500])).toBeCloseTo(17.6294, 3);
    expect(npv(0, [-10, 4, 6])).toBe(0);
  });
  it('TIR', () => {
    expect(irr([-100, 110])).toBeCloseTo(0.1, 10);
    expect(irr([-1000, 300, 400, 500])!).toBeCloseTo(0.088963394, 7);
    expect(irr([-100, 30, 35, 40, 45])!).toBeCloseTo(0.170936863, 7);
    expect(irr([-5000, 1200, 1200, 1200, 1200, 1200, 1200])!).toBeCloseTo(0.115304732, 7);
  });
  it('TIR negativa y casos sin solución', () => {
    expect(irr([-100, 50, 40])!).toBeLessThan(0);
    expect(npv(irr([-100, 50, 40])!, [-100, 50, 40])).toBeCloseTo(0, 6);
    expect(irr([100, 50])).toBeNull(); // todo positivo
    expect(irr([-100, -50])).toBeNull(); // todo negativo
    expect(irr([-100])).toBeNull();
  });
});

describe('Deuda', () => {
  it('cuota francesa', () => {
    expect(annuityPayment(100_000, 0.01, 12)).toBeCloseTo(8884.8789, 3);
    expect(annuityPayment(1200, 0, 12)).toBe(100);
    expect(crf(0.07, 30)).toBeCloseTo(0.080586, 5);
  });
  it('tabla de amortización: suma de capital = préstamo y saldo final 0', () => {
    const rows = amortizationSchedule(1_000_000, 0.075 / 12, 14 * 12);
    expect(rows).toHaveLength(168);
    expect(rows.reduce((a, r) => a + r.principal, 0)).toBeCloseTo(1_000_000, 4);
    expect(rows.at(-1)!.balance).toBe(0);
    expect(rows[0].interest).toBeCloseTo(6250, 6);
    // cuota constante
    expect(rows[10].payment).toBeCloseTo(rows[100].payment, 6);
  });
  it('capacidad de deuda por DSCR', () => {
    // CFADS 130/año, DSCR 1,3 ⇒ cuota 100; 10 años al 0 % ⇒ 1000
    expect(debtCapacityFrench(new Array(20).fill(130), 1.3, 0, 10)).toBeCloseTo(1000, 6);
    // al 10 %: 100 · (1 − 1,1⁻¹⁰)/0,1 = 614,457
    expect(debtCapacityFrench(new Array(20).fill(130), 1.3, 0.1, 10)).toBeCloseTo(614.4567, 3);
    const s = sizeDebt({ cfads: new Array(20).fill(130), dscr: 1.3, rate: 0.1, tenorYears: 10, maxLeverage: 0.7, requestedFraction: 0.8, budgetUsd: 1000 });
    expect(s.debtUsd).toBeCloseTo(614.4567, 3);
    expect(s.limitedBy).toBe('dscr');
    expect(sizeDebt({ cfads: new Array(20).fill(1000), dscr: 1.3, rate: 0.1, tenorYears: 10, maxLeverage: 0.7, requestedFraction: 0.8, budgetUsd: 1000 }).limitedBy).toBe('apalancamiento');
  });
});

describe('LCOE y WACC', () => {
  it('LCOE a mano', () => {
    // 1000 de inversión, 100 MWh/año, tasa 0, 10 años, sin O&M ⇒ 1 USD/MWh
    expect(lcoe({ capexUsd: 1000, fixedCostUsdYear: 0, varCostUsdMwh: 0, energyMwhYear1: 100, degradation: 0, years: 10, rate: 0 })).toBeCloseTo(1, 10);
    // 1 año al 10 %: 1000 / (100/1,1) = 11
    expect(lcoe({ capexUsd: 1000, fixedCostUsdYear: 0, varCostUsdMwh: 0, energyMwhYear1: 100, degradation: 0, years: 1, rate: 0.1 })).toBeCloseTo(11, 10);
    // con O&M variable se suma tal cual
    expect(lcoe({ capexUsd: 0, fixedCostUsdYear: 0, varCostUsdMwh: 7, energyMwhYear1: 100, degradation: 0, years: 5, rate: 0.08 })).toBeCloseTo(7, 10);
    // forma cerrada sin degradación: (capex·CRF + fijo)/energía
    const v = lcoe({ capexUsd: 1_000_000, fixedCostUsdYear: 20_000, varCostUsdMwh: 0, energyMwhYear1: 2000, degradation: 0, years: 25, rate: 0.07 });
    expect(v).toBeCloseTo((1_000_000 * crf(0.07, 25) + 20_000) / 2000, 6);
  });
  it('WACC y costo del equity', () => {
    const base = { riskFree: 0.04, countryPremium: 0.03, equityPremium: 0.05, beta: 1, stagePremium: 0.02, techPremium: 0.01 };
    expect(costOfEquity(base)).toBeCloseTo(0.15, 12);
    expect(wacc({ ...base, costOfDebt: 0.08, taxRate: 0.25, debtFraction: 0.6 })).toBeCloseTo(0.4 * 0.15 + 0.6 * 0.08 * 0.75, 12);
  });
  it('percentiles', () => {
    expect(percentile([1, 2, 3, 4, 5], 0.5)).toBe(3);
    expect(percentile([1, 2, 3, 4, 5], 0.9)).toBeCloseTo(4.6, 10);
  });
});

describe('Modelo de proyecto', () => {
  const base = {
    energyMwhYear1: 10_000, degradation: 0, lifeYears: 20, capexUsd: 5_000_000, fixedCostUsdYear: 100_000, varCostUsdMwh: 0, inflation: 0,
    spotPriceUsdMwh: 80, taxRate: 0.25, depreciationYears: 20, taxCreditUsd: 0, taxCreditMaxFrac: 0, decommissionUsd: 0,
  };
  it('impuestos con depreciación lineal', () => {
    const m = runProjectModel(base);
    // EBITDA 700k, depreciación 250k ⇒ impuesto 112,5k ⇒ flujo 587,5k
    expect(m.rows[0].ebitdaUsd).toBeCloseTo(700_000, 6);
    expect(m.rows[0].taxUnleveredUsd).toBeCloseTo(112_500, 6);
    expect(m.projectFlows[1]).toBeCloseTo(587_500, 6);
    expect(m.irrProject!).toBeCloseTo(irr([-5_000_000, ...new Array(20).fill(587_500)])!, 10);
  });
  it('la deuda apalanca la TIR del equity y el DSCR es coherente', () => {
    const m = runProjectModel({ ...base, debt: { amountUsd: 3_000_000, rate: 0.07, tenorYears: 12 } });
    expect(m.irrEquity!).toBeGreaterThan(m.irrProject!);
    const pay = annuityPayment(3_000_000, 0.07, 12);
    expect(m.rows[0].interestUsd + m.rows[0].principalUsd).toBeCloseTo(pay, 4);
    expect(m.rows.slice(0, 12).reduce((a, r) => a + r.principalUsd, 0)).toBeCloseTo(3_000_000, 3);
    expect(m.minDscr!).toBeGreaterThan(1);
  });
  it('el PPA fija el precio durante su plazo y luego rige el spot', () => {
    const m = runProjectModel({ ...base, ppa: { priceUsdMwh: 60, years: 10, indexation: 0.02 } });
    expect(m.rows[0].priceUsdMwh).toBe(60);
    expect(m.rows[9].priceUsdMwh).toBeCloseTo(60 * 1.02 ** 9, 8);
    expect(m.rows[10].priceUsdMwh).toBe(80);
  });
});
