import { useMemo } from 'react';
import type { ProjectDetail } from '@voltaje/sim';
import { useUi } from '../store';
import { Empty, Section, Stat } from '../common';
import { Chart, CHART, baseOption } from '../Chart';
import { fmtDate, fmtMoney, fmtNum, fmtPct, MONTHS_SHORT, monthLabel } from '../format';
import { cmd } from './ProjectWindow';

export function OperationTab({ d }: { d: ProjectDetail }) {
  const op = d.operation;
  const raw = useUi((s) => s.game?.projects.find((p) => p.id === d.summary.id));
  const hist = op?.history ?? [];
  const expected = op?.expectedMonthlyMwh ?? d.resource.monthlyMwh;
  const histKey = hist.length ? `${hist.length}-${hist[hist.length - 1].energyMwh}` : '0';
  const energyOpt = useMemo(() => {
    const last = hist.slice(-36);
    const o = baseOption(last.map((h) => monthLabel(h.year, h.month)), { unit: ' MWh' });
    return {
      ...o,
      series: [
        { name: 'Producción real', type: 'bar', data: last.map((h) => Math.round(h.energyMwh)), itemStyle: { color: CHART.good, borderRadius: [3, 3, 0, 0] } },
        // perfil estacional del país (P50 y P90 por mes calendario, con degradación)
        { name: 'Esperada P50', type: 'line', data: last.map((h) => Math.round(expected[h.month - 1]?.p50Mwh ?? 0)), lineStyle: { color: CHART.accent, type: 'dashed' }, itemStyle: { color: CHART.accent }, symbol: 'none' },
        { name: 'P90', type: 'line', data: last.map((h) => Math.round(expected[h.month - 1]?.p90Mwh ?? 0)), lineStyle: { color: CHART.bad, type: 'dotted' }, itemStyle: { color: CHART.bad }, symbol: 'none' },
      ],
    };
  }, [histKey, expected]);
  // sin operación: perfil esperado del año tipo
  const profileOpt = useMemo(() => {
    const m = d.resource.monthlyMwh;
    const o = baseOption(m.map((x) => MONTHS_SHORT[x.month - 1]), { unit: ' MWh' });
    return {
      ...o,
      series: [
        { name: 'Esperada P50', type: 'bar', data: m.map((x) => Math.round(x.p50Mwh)), itemStyle: { color: CHART.accent, borderRadius: [3, 3, 0, 0] } },
        { name: 'P90', type: 'line', data: m.map((x) => Math.round(x.p90Mwh)), lineStyle: { color: CHART.bad, type: 'dotted' }, itemStyle: { color: CHART.bad }, symbol: 'circle', symbolSize: 4 },
      ],
    };
  }, [d.resource.monthlyMwh]);
  const moneyOpt = useMemo(() => {
    const last = hist.slice(-36);
    const o = baseOption(last.map((h) => monthLabel(h.year, h.month)), { money: true });
    return {
      ...o,
      series: [
        { name: 'Ingresos', type: 'bar', data: last.map((h) => h.revenueUsd), itemStyle: { color: CHART.info } },
        { name: 'Costos de operación', type: 'bar', data: last.map((h) => -Math.abs(h.opexUsd)), itemStyle: { color: CHART.bad } },
        { name: 'Disponibilidad', type: 'line', yAxisIndex: 1, data: last.map((h) => h.availability), lineStyle: { color: CHART.violet }, itemStyle: { color: CHART.violet }, symbol: 'none' },
      ],
      yAxis: [(o as { yAxis: object }).yAxis, { type: 'value', min: 0.8, max: 1, splitLine: { show: false }, axisLabel: { color: CHART.text, formatter: (v: number) => `${Math.round(v * 100)} %` } }],
    };
  }, [histKey]);

  if (!op) return (
    <>
      <Empty>La planta aún no está en operación. Aquí verás su producción mensual, factor de capacidad real, fallas y mantenimiento.</Empty>
      <Section title="Producción esperada por mes (perfil estacional del país)"><Chart option={profileOpt} height={240} /></Section>
    </>
  );
  const failures = op.failureLog;
  const outages = raw?.operation?.outages ?? [];
  const lost = outages.reduce((a, o) => a + o.fraction, 0);

  return (
    <>
      <div className="stats-row">
        <Stat label="FC real (12 meses)" value={fmtPct(op.actualFcLast12m)} hint={`esperado P50 ${fmtPct(d.resource.fcP50)}`} tone={op.actualFcLast12m !== null && op.actualFcLast12m < d.resource.fcP90 ? 'bad' : undefined} />
        <Stat label="En operación desde" value={fmtDate(op.codDate)} />
        <Stat label="Energía total" value={`${fmtNum(op.totalEnergyMwh / 1000, 1)} GWh`} />
        <Stat label="Ingresos totales" value={fmtMoney(op.totalRevenueUsd)} />
        <Stat label="Capacidad fuera de servicio" value={fmtPct(lost, 0)} tone={lost > 0 ? 'bad' : 'good'} hint={outages.length ? `${outages.length} falla(s) en curso` : 'sin fallas'} />
        <Stat label="Activo neto" value={fmtMoney(op.grossAssetUsd - op.accumulatedDepreciationUsd)} />
      </div>
      <div className="grid2">
        <Section title="Producción mensual vs esperada"><Chart option={energyOpt} height={240} /></Section>
        <Section title="Ingresos, costos y disponibilidad"><Chart option={moneyOpt} height={240} /></Section>
      </div>
      <div className="grid2">
        <Section title="Política de mantenimiento">
          <div className="grid2">
            {(['preventivo', 'correctivo'] as const).map((m) => (
              <button key={m} className={`choice ${op.maintenance === m ? 'selected' : ''}`} style={{ display: 'block', textAlign: 'left' }}
                onClick={() => op.maintenance !== m && cmd({ type: 'setMaintenancePolicy', projectId: d.summary.id, policy: m })}>
                <b>{m === 'preventivo' ? 'Preventivo' : 'Correctivo'}</b>
                <div className="dim" style={{ fontSize: 11.5 }}>{m === 'preventivo' ? 'Más O&M fijo; fallas a cerca de la mitad.' : 'O&M más barato; más fallas y reparaciones.'}</div>
              </button>
            ))}
          </div>
        </Section>
        <Section title={`Fallas (${failures.length})`}>
          {failures.length === 0 ? <div className="dim">Sin fallas registradas.</div> : (
            <div className="scroll" style={{ maxHeight: 180 }}>
              <table className="grid-table">
                <thead><tr><th>Fecha</th><th className="num">Capacidad perdida</th><th className="num">Días</th><th className="num">Reparación</th></tr></thead>
                <tbody>
                  {[...failures].reverse().map((f, i) => (
                    <tr key={i}><td className="mono">{fmtDate(f.date)}</td><td className="num mono">{fmtPct(f.fractionLost, 0)}</td><td className="num mono">{f.days}</td><td className="num mono">{fmtMoney(f.costUsd)}</td></tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Section>
      </div>
    </>
  );
}
