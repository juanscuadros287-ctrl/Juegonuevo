import { describe, it } from 'vitest';
import { STRATEGIES, runStrategy, typicalIrrTable, type RunResult } from './balance';

/**
 * `npm run balance`: reporte de balance (no corre en `npm test`). Variables: BALANCE_SEEDS (por defecto 1–6),
 * BALANCE_YEARS (15). Ver docs/BALANCE.md.
 */
const on = process.env.BALANCE_REPORT === '1';

describe.runIf(on)('Reporte de balance', () => {
  it('imprime el reporte', () => {
    const seeds = (process.env.BALANCE_SEEDS ?? '1,2,3,4,5,6').split(',').map(Number);
    const years = Number(process.env.BALANCE_YEARS ?? 15);
    const lines: string[] = [`# Reporte de balance — ${years} años, semillas ${seeds.join(', ')}`, ''];
    const all: RunResult[] = [];
    lines.push('| Estrategia | Semilla | Quiebra (año) | Patrimonio final (M USD) | × capital | MW operando | Países | Equipo | Patrimonio por año (M) |', '|---|---|---|---|---|---|---|---|---|');
    for (const st of STRATEGIES) {
      for (const seed of seeds) {
        const r = runStrategy(st, seed, years);
        all.push(r);
        lines.push(`| ${st} | ${seed} | ${r.bankrupt ? r.bankruptYear!.toFixed(1) : '—'} | ${(r.finalEquityUsd / 1e6).toFixed(2)} | ${(r.finalEquityUsd / r.initialCashUsd).toFixed(1)} | ${r.operatingMw} | ${r.countries} | ${r.headcount} | ${r.equityByYear.map((x) => (x / 1e6).toFixed(1)).join(' ')} |`);
      }
    }
    lines.push('', '## Resumen por estrategia', '', '| Estrategia | Quiebras | Mediana × capital | Mín | Máx |', '|---|---|---|---|---|');
    for (const st of STRATEGIES) {
      const rs = all.filter((r) => r.strategy === st);
      const m = rs.map((r) => (r.bankrupt ? 0 : r.finalEquityUsd / r.initialCashUsd)).sort((a, b) => a - b);
      lines.push(`| ${st} | ${rs.filter((r) => r.bankrupt).length}/${rs.length} | ${m[Math.floor(m.length / 2)].toFixed(1)} | ${m[0].toFixed(1)} | ${m[m.length - 1].toFixed(1)} |`);
    }
    lines.push('', '## IA (patrimonio final / capital inicial; Q = quebrada)', '');
    const names = all[0].ai.map((a) => a.name);
    lines.push(`| Partida | ${names.join(' | ')} |`, `|---|${names.map(() => '---').join('|')}|`);
    const wins: Record<string, number> = {};
    for (const r of all.filter((x) => x.strategy !== 'pasivo')) {
      lines.push(`| ${r.strategy} ${r.seed} | ${r.ai.map((a) => `${a.equityMultiple.toFixed(2)}${a.bankrupt ? ' Q' : ''}`).join(' | ')} |`);
      const w = [...r.ai].sort((a, b) => b.equityMultiple - a.equityMultiple)[0].name;
      wins[w] = (wins[w] ?? 0) + 1;
    }
    lines.push('', `Primer lugar entre las IA: ${Object.entries(wins).map(([k, v]) => `${k} ${v}`).join(', ')}`);
    lines.push('', '## TIR del capital de proyectos típicos (catálogo, sitio típico)', '');
    const rows = typicalIrrTable(['solar_fv', 'eolica_tierra', 'geotermica', 'hidro_pasada', 'gas_natural'], ['PAN', 'CRI', 'COL', 'DOM', 'CHL', 'MEX', 'BRA', 'KEN', 'ESP', 'USA', 'IDN', 'PHL']);
    const countries = [...new Set(rows.map((r) => r.countryCode))];
    lines.push(`| Tecnología | ${countries.join(' | ')} |`, `|---|${countries.map(() => '---').join('|')}|`);
    for (const t of [...new Set(rows.map((r) => r.techId))]) lines.push(`| ${t} | ${countries.map((c) => { const r = rows.find((x) => x.techId === t && x.countryCode === c); return r?.irr == null ? '—' : `${(r.irr * 100).toFixed(1)} %`; }).join(' | ')} |`);
    console.log(lines.join('\n'));
  }, 3_600_000);
});
