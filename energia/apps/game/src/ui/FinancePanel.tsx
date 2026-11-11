import { useMemo, useState } from 'react';
import { gameData } from '@voltaje/data';
import { CATEGORIES, type CompanyFinancials, type MonthlyStatement } from '@voltaje/sim';
import { ui, useUi } from './store';
import { Empty, Section, Stat, Tabs, Window } from './common';
import { Chart, CHART, baseOption } from './Chart';
import { fmtMoney, fmtNum, monthLabel } from './format';

type Tab = 'resumen' | 'pyg' | 'caja' | 'balance' | 'deuda';
type Cat = keyof typeof CATEGORIES;
const CATS = Object.keys(CATEGORIES) as Cat[];

export function riskLevel(f: CompanyFinancials): { label: string; tone: 'good' | 'warn' | 'bad'; text: string } {
  const b = f.bankruptcy;
  if (b.bankrupt) return { label: 'Quiebra', tone: 'bad', text: 'La empresa quebró.' };
  if (b.negativeCashMonths > 0) return { label: 'Crítico', tone: 'bad', text: `${b.negativeCashMonths} de ${b.monthsLimit} meses con caja negativa: al llegar a ${b.monthsLimit} la empresa quiebra.` };
  if (f.cashUsd < 0) return { label: 'Alto', tone: 'bad', text: 'La caja es negativa: si cierra el mes así, empieza la cuenta de quiebra.' };
  if (b.runwayMonths !== null && b.runwayMonths < 6) return { label: 'Medio', tone: 'warn', text: `Al ritmo actual la caja alcanza ~${fmtNum(b.runwayMonths, 0)} meses.` };
  return { label: 'Bajo', tone: 'good', text: b.runwayMonths === null ? 'La empresa genera caja.' : `La caja alcanza ~${fmtNum(b.runwayMonths, 0)} meses al ritmo actual.` };
}

function StatementTable({ f, filter, totals }: { f: CompanyFinancials; filter: (c: Cat) => boolean; totals: { label: string; get: (s: MonthlyStatement | null, cur: Record<string, number>) => number }[] }) {
  const months = f.statements.slice(-12);
  const cats = CATS.filter(filter).filter((c) => months.some((s) => s.lines[c]) || f.currentMonth[c]);
  if (!months.length && !Object.keys(f.currentMonth).length) return <Empty>Aún no hay meses cerrados.</Empty>;
  const cell = (v: number) => <td className="num mono" style={{ color: v < 0 ? 'var(--bad)' : v > 0 ? undefined : 'var(--text-dim)' }}>{v ? fmtMoney(v).replace('US$ ', '') : '–'}</td>;
  return (
    <div className="scroll-x">
      <table className="grid-table statement">
        <thead>
          <tr><th>Concepto (US$)</th>{months.map((s) => <th key={`${s.year}-${s.month}`} className="num">{monthLabel(s.year, s.month)}</th>)}<th className="num">En curso</th></tr>
        </thead>
        <tbody>
          {cats.map((c) => (
            <tr key={c}><td>{CATEGORIES[c].label}</td>{months.map((s) => <td key={`${s.year}-${s.month}`} className="num mono" style={{ color: (s.lines[c] ?? 0) < 0 ? 'var(--bad)' : undefined }}>{s.lines[c] ? fmtMoney(s.lines[c]).replace('US$ ', '') : <span className="dim">–</span>}</td>)}{cell(f.currentMonth[c] ?? 0)}</tr>
          ))}
          {totals.map((t) => (
            <tr key={t.label} className="total"><td>{t.label}</td>{months.map((s) => <td key={`${s.year}-${s.month}`} className="num mono" style={{ color: t.get(s, {}) < 0 ? 'var(--bad)' : 'var(--good)' }}>{fmtMoney(t.get(s, {})).replace('US$ ', '')}</td>)}{cell(t.get(null, f.currentMonth))}</tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

const sumCur = (cur: Record<string, number>, test: (c: Cat) => boolean) => CATS.filter(test).reduce((a, c) => a + (cur[c] ?? 0), 0);

export function FinancePanel() {
  const f = useUi((s) => s.views?.finance);
  const game = useUi((s) => s.game);
  const [tab, setTab] = useState<Tab>('resumen');
  const key = f ? `${f.statements.length}` : '';
  const months = f?.statements.slice(-36) ?? [];
  const cashOpt = useMemo(() => {
    const o = baseOption(months.map((s) => monthLabel(s.year, s.month)), { money: true });
    return {
      ...o,
      series: [
        { name: 'Caja al cierre', type: 'line', data: months.map((s) => s.cashEndUsd), lineStyle: { color: CHART.accent, width: 2 }, itemStyle: { color: CHART.accent }, areaStyle: { color: 'rgba(255,203,61,0.10)' }, symbol: 'none' },
        { name: 'Deuda', type: 'line', data: months.map((s) => s.debtEndUsd), lineStyle: { color: CHART.bad }, itemStyle: { color: CHART.bad }, symbol: 'none' },
      ],
    };
  }, [key]);
  const flowOpt = useMemo(() => {
    const o = baseOption(months.map((s) => monthLabel(s.year, s.month)), { money: true });
    return {
      ...o,
      series: [
        { name: 'Operativo', type: 'bar', stack: 'f', data: months.map((s) => s.cashFlow.operating), itemStyle: { color: CHART.info } },
        { name: 'Inversión', type: 'bar', stack: 'f', data: months.map((s) => s.cashFlow.investing), itemStyle: { color: CHART.violet } },
        { name: 'Financiamiento', type: 'bar', stack: 'f', data: months.map((s) => s.cashFlow.financing), itemStyle: { color: CHART.dim } },
        { name: 'Resultado neto', type: 'line', data: months.map((s) => s.netIncomeUsd), lineStyle: { color: CHART.good }, itemStyle: { color: CHART.good }, symbol: 'circle', symbolSize: 4 },
      ],
    };
  }, [key]);
  const rev = useUi((s) => s.views?.power?.revenue);
  const revKey = rev ? rev.byMonth.map((m) => `${m.energyUsd.toFixed(0)}`).join('|') : '';
  const revOpt = useMemo(() => {
    if (!rev) return null;
    const o = baseOption(rev.byMonth.map((m) => monthLabel(m.year, m.month)), { money: true });
    return {
      ...o,
      series: [
        { name: 'Energía (PPA y spot)', type: 'bar', stack: 'r', data: rev.byMonth.map((m) => m.energyUsd), itemStyle: { color: CHART.info } },
        { name: 'Capacidad', type: 'bar', stack: 'r', data: rev.byMonth.map((m) => m.capacityUsd), itemStyle: { color: CHART.violet } },
        { name: 'Servicios', type: 'bar', stack: 'r', data: rev.byMonth.map((m) => m.servicesUsd), itemStyle: { color: '#22d3ee' } },
        { name: 'Compras al spot', type: 'bar', stack: 'r', data: rev.byMonth.map((m) => -Math.abs(m.purchasesUsd)), itemStyle: { color: CHART.bad } },
      ],
    };
  }, [revKey]);
  if (!f || !game) return null;
  const b = f.balance;
  const risk = riskLevel(f);
  const debts = game.projects.filter((p) => (p.debt?.outstandingUsd ?? 0) > 0);

  return (
    <Window title="Finanzas de la empresa" subtitle={game.company.name} width={1180} onClose={() => ui.openWindow(null)} testId="finance-panel">
      <div className="stats-row">
        <Stat label="Caja" value={fmtMoney(f.cashUsd)} tone={f.cashUsd < 0 ? 'bad' : undefined} />
        <Stat label="Patrimonio" value={fmtMoney(b.equityUsd)} />
        <Stat label="Deuda total" value={fmtMoney(b.debtUsd)} />
        <Stat label="Ingresos (12 meses)" value={fmtMoney(f.last12m.revenueUsd)} />
        <Stat label="EBITDA (12 meses)" value={fmtMoney(f.last12m.ebitdaUsd)} tone={f.last12m.ebitdaUsd < 0 ? 'bad' : 'good'} />
        <Stat label="Meses de caja" value={f.bankruptcy.runwayMonths === null ? '∞' : fmtNum(f.bankruptcy.runwayMonths, 0)} tone={f.bankruptcy.runwayMonths !== null && f.bankruptcy.runwayMonths < 6 ? 'warn' : undefined} />
        <Stat label="Riesgo de quiebra" value={risk.label} tone={risk.tone} />
      </div>
      <Tabs<Tab> value={tab} onChange={setTab} tabs={[{ id: 'resumen', label: 'Resumen' }, { id: 'pyg', label: 'Pérdidas y ganancias' }, { id: 'caja', label: 'Flujo de caja' }, { id: 'balance', label: 'Balance' }, { id: 'deuda', label: 'Deuda y riesgo' }]} />
      <div className="window-body scroll">
        {tab === 'resumen' && (
          <>
            <div className={`notice ${risk.tone}`}>{risk.text}</div>
            {months.length === 0 ? <Empty>Los gráficos aparecen al cerrar el primer mes.</Empty> : (
              <div className="grid2">
                <Section title="Caja y deuda"><Chart option={cashOpt} height={250} /></Section>
                <Section title="Flujo de caja mensual y resultado"><Chart option={flowOpt} height={250} /></Section>
              </div>
            )}
            {rev && (
              <div className="grid2">
                <Section title="Ingresos por fuente (12 meses)">
                  <table className="kv" data-testid="revenue-sources"><tbody>
                    <tr><td>Energía (PPA y spot)</td><td>{fmtMoney(rev.energyUsd)}</td></tr>
                    <tr><td>Pagos por capacidad</td><td>{fmtMoney(rev.capacityUsd)}</td></tr>
                    <tr><td>Servicios complementarios</td><td>{fmtMoney(rev.servicesUsd)}</td></tr>
                    <tr><td>Compras de energía al spot</td><td style={{ color: rev.purchasesUsd ? 'var(--bad)' : undefined }}>{fmtMoney(-Math.abs(rev.purchasesUsd))}</td></tr>
                    <tr><td>Indemnizaciones de seguros</td><td style={{ color: rev.insuranceUsd ? 'var(--good)' : undefined }}>{fmtMoney(rev.insuranceUsd)}</td></tr>
                    <tr className="kv-head"><td>Neto de energía y servicios</td><td>{fmtMoney(rev.energyUsd + rev.capacityUsd + rev.servicesUsd - Math.abs(rev.purchasesUsd))}</td></tr>
                  </tbody></table>
                  <div className="dim" style={{ fontSize: 11.5, marginTop: 6 }}>El desglose por planta (PPA, spot, capacidad, servicios) está en la pestaña «Despacho y venta» de cada proyecto en operación.</div>
                </Section>
                <Section title="Ingresos por fuente, mensual">{rev.byMonth.length && revOpt ? <Chart option={revOpt} height={220} /> : <Empty>Sin meses cerrados.</Empty>}</Section>
              </div>
            )}
          </>
        )}
        {tab === 'pyg' && (
          <StatementTable f={f} filter={(c) => CATEGORIES[c].pnl} totals={[
            { label: 'EBITDA', get: (s, cur) => (s ? s.ebitdaUsd : sumCur(cur, (c) => CATEGORIES[c].pnl && !['intereses', 'impuestos', 'depreciacion', 'castigos', 'resultado_venta'].includes(c))) },
            { label: 'Resultado neto', get: (s, cur) => (s ? s.netIncomeUsd : sumCur(cur, (c) => CATEGORIES[c].pnl)) },
          ]} />
        )}
        {tab === 'caja' && (
          <StatementTable f={f} filter={(c) => CATEGORIES[c].cash !== null} totals={[
            { label: 'Flujo operativo', get: (s, cur) => (s ? s.cashFlow.operating : sumCur(cur, (c) => CATEGORIES[c].cash === 'operating')) },
            { label: 'Flujo de inversión', get: (s, cur) => (s ? s.cashFlow.investing : sumCur(cur, (c) => CATEGORIES[c].cash === 'investing')) },
            { label: 'Flujo de financiamiento', get: (s, cur) => (s ? s.cashFlow.financing : sumCur(cur, (c) => CATEGORIES[c].cash === 'financing')) },
            { label: 'Variación de caja', get: (s, cur) => (s ? s.cashFlow.net : sumCur(cur, (c) => CATEGORIES[c].cash !== null)) },
          ]} />
        )}
        {tab === 'balance' && (
          <div className="grid2">
            <Section title="Activos">
              <table className="kv"><tbody>
                <tr><td>Caja</td><td>{fmtMoney(b.cashUsd)}</td></tr>
                <tr><td>Proyectos en desarrollo</td><td>{fmtMoney(b.developmentAssetsUsd)}</td></tr>
                <tr><td>Obras en curso</td><td>{fmtMoney(b.constructionAssetsUsd)}</td></tr>
                <tr><td>Plantas en operación (neto)</td><td>{fmtMoney(b.operatingAssetsUsd)}</td></tr>
                <tr className="kv-head"><td>Total activos</td><td>{fmtMoney(b.totalAssetsUsd)}</td></tr>
              </tbody></table>
            </Section>
            <Section title="Pasivos y patrimonio">
              <table className="kv"><tbody>
                <tr><td>Deuda</td><td>{fmtMoney(b.debtUsd)}</td></tr>
                <tr><td>Participación de socios</td><td>{fmtMoney(b.partnerInterestUsd)}</td></tr>
                <tr className="kv-head"><td>Patrimonio de la empresa</td><td style={{ color: b.equityUsd < 0 ? 'var(--bad)' : undefined }}>{fmtMoney(b.equityUsd)}</td></tr>
                <tr><td>Pérdidas fiscales por compensar</td><td>{fmtMoney(f.taxLossCarryforwardUsd)}</td></tr>
                <tr><td>Crédito fiscal disponible</td><td>{fmtMoney(f.taxCreditUsd)}</td></tr>
              </tbody></table>
            </Section>
          </div>
        )}
        {tab === 'deuda' && (
          <>
            <div className={`notice ${risk.tone}`}><b>Riesgo de quiebra: {risk.label}.</b> {risk.text} Si la caja cierra un mes en negativo se intenta un crédito de emergencia (hasta el 50 % del valor neto de las plantas).</div>
            <Section title="Deuda por proyecto">
              {debts.length === 0 && f.emergencyDebtUsd === 0 ? <Empty>Sin deuda.</Empty> : (
                <table className="grid-table">
                  <thead><tr><th>Deuda</th><th className="num">Saldo</th><th className="num">Tasa</th><th className="num">Cuota mensual</th><th className="num">Cuotas</th></tr></thead>
                  <tbody>
                    {debts.map((p) => (
                      <tr key={p.id} className="clickable" onClick={() => ui.openProject(p.id, 'financiacion')}>
                        <td>{p.name}</td><td className="num mono">{fmtMoney(p.debt!.outstandingUsd)}</td><td className="num mono">{fmtNum(p.debt!.rate * 100, 2)} %</td>
                        <td className="num mono">{fmtMoney(p.debt!.monthlyPayment)}</td><td className="num mono">{p.debt!.monthsPaid} / {p.debt!.tenorMonths}</td>
                      </tr>
                    ))}
                    {f.emergencyDebtUsd > 0 && <tr><td>Crédito de emergencia</td><td className="num mono">{fmtMoney(f.emergencyDebtUsd)}</td><td className="num mono">{fmtNum(gameData.simData.countries[game.company.homeCountry].finanzas.credito_emergencia.tasa * 100, 1)} %</td><td /><td /></tr>}
                  </tbody>
                </table>
              )}
            </Section>
          </>
        )}
      </div>
    </Window>
  );
}
