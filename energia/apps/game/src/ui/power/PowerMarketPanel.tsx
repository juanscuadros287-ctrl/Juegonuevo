import { useMemo, useState } from 'react';
import type { PowerMarketView } from '@voltaje/sim';
import { ui, useUi } from '../store';
import { Empty, Pill, Section, Stat, Tabs, Window } from '../common';
import { Chart, CHART, baseOption } from '../Chart';
import { fmtNum, fmtPct, monthLabel } from '../format';
import { getGlobe, countryCenter } from '../../globe/GlobeView';

type Tab = 'mes' | 'prevision' | 'parque' | 'comparar';

/** Color por tecnología de la curva de oferta (por el nombre de la clase). */
export function fleetColor(label: string): string {
  const l = label.toLowerCase();
  if (l.includes('solar')) return '#fcd34d';
  if (l.includes('eól') || l.includes('eol') || l.includes('viento')) return '#67e8f9';
  if (l.includes('geot')) return '#fb923c';
  if (l.includes('nuclear')) return '#c084fc';
  if (l.includes('hidr') || l.includes('agua')) return '#60a5fa';
  if (l.includes('almac') || l.includes('bater')) return '#34d399';
  if (l.includes('bio')) return '#86efac';
  if (l.includes('carb')) return '#78716c';
  if (l.includes('gas') && (l.includes('ciclo') || l.includes('combinado'))) return '#f59e0b';
  if (l.includes('gas')) return '#fbbf24';
  if (l.includes('fuel') || l.includes('búnker') || l.includes('petr') || l.includes('diés') || l.includes('dies')) return '#f87171';
  if (l.includes('punta')) return '#ef4444';
  return '#94a3b8';
}

const ENSO_TONE = { nino: 'warn', nina: 'info', neutral: 'dim' } as const;

export function PowerMarketPanel() {
  const m = useUi((s) => s.views?.power?.market ?? null);
  const rows = useUi((s) => s.views?.power?.markets);
  const home = useUi((s) => s.game?.company.homeCountry ?? 'PAN');
  const [tab, setTab] = useState<Tab>('mes');
  const close = () => ui.openWindow(null);
  const choose = (iso: string) => ui.openPowerMarket(iso);
  const sel = m?.countryCode ?? home;
  const row = rows?.find((r) => r.countryCode === sel);

  return (
    <Window title="Mercado eléctrico" testId="power-panel" width={1320} onClose={close}
      subtitle={<>Spot horario por país: orden de mérito con días tipo, clima e hidrología, previsión y servicios · {m?.monthLabel ?? ''}</>}
      actions={
        <span className="row" style={{ gap: 6 }}>
          <select value={sel} onChange={(e) => choose(e.target.value)} data-testid="power-country">
            {(rows ?? []).map((r) => <option key={r.countryCode} value={r.countryCode}>{r.countryName}</option>)}
          </select>
          <button onClick={() => { const c = countryCenter(sel); if (c) { ui.openWindow(null); getGlobe()?.flyTo(c.lat, c.lon, 1.6); } }} title="Ver en el globo">⌖</button>
        </span>
      }>
      {!m ? <Empty>Cargando el mercado…</Empty> : !m.available ? <Empty>{m.countryName} no tiene mercado eléctrico modelado.</Empty> : (
        <>
          <div className="stats-row">
            <Stat label="Spot medio del mes" value={`${fmtNum(m.avgUsdMwh, 1)}`} hint={`US$/MWh · histórico ${fmtNum(m.historicalMeanUsdMwh, 0)}`} tone={m.avgUsdMwh > m.historicalMeanUsdMwh * 1.15 ? 'warn' : undefined} />
            <Stat label="Punta / valle" value={`${fmtNum(m.peakUsdMwh, 0)} / ${fmtNum(m.offpeakUsdMwh, 0)}`} hint="US$/MWh" />
            <Stat label="Mín. / máx. horario" value={`${fmtNum(m.minUsdMwh, 0)} / ${fmtNum(m.maxUsdMwh, 0)}`} hint={`piso ${fmtNum(m.priceFloorUsdMwh, 0)} · techo ${fmtNum(m.priceCapUsdMwh, 0)}`} tone={m.maxUsdMwh >= m.priceCapUsdMwh * 0.9 ? 'bad' : undefined} />
            <Stat label="Valor del agua" value={fmtNum(m.waterValueUsdMwh, 0)} hint="US$/MWh (hidro de embalse)" />
            <Stat label="Clima del año" value={m.climate.ensoLabel} hint={`${m.climate.hydrologyLabel} · caudales ${fmtPct(m.climate.hydrology, 0)}`} tone={m.climate.hydrology < 0.85 ? 'bad' : m.climate.hydrology > 1.1 ? 'good' : undefined} />
            <Stat label="Cambio a 12 meses" value={row?.change12mPct === null || row?.change12mPct === undefined ? '—' : `${row.change12mPct >= 0 ? '+' : '−'}${fmtNum(Math.abs(row.change12mPct), 0)} %`} hint="spot medio" />
          </div>
          <Tabs<Tab> tabs={[{ id: 'mes', label: 'Mes en curso' }, { id: 'prevision', label: 'Previsión e historial' }, { id: 'parque', label: 'Parque, capacidad y servicios' }, { id: 'comparar', label: 'Comparar países' }]} value={tab} onChange={setTab} />
          <div className="window-body scroll">
            {tab === 'mes' && <MonthTab m={m} />}
            {tab === 'prevision' && <ForecastTab m={m} />}
            {tab === 'parque' && <FleetTab m={m} />}
            {tab === 'comparar' && <CompareTab sel={sel} onPick={(iso) => { choose(iso); setTab('mes'); }} />}
          </div>
        </>
      )}
    </Window>
  );
}

function MonthTab({ m }: { m: PowerMarketView }) {
  const key = `${m.countryCode}|${m.year}|${m.month}|${m.avgUsdMwh.toFixed(2)}`;
  const curveOpt = useMemo(() => {
    // bloques como rectángulos: una serie de área por tecnología con huecos entre bloques
    const byLabel = new Map<string, (number | null)[][]>();
    for (const b of m.supplyCurve) {
      const arr = byLabel.get(b.label) ?? [];
      const x0 = b.cumulativeMw - b.mw;
      arr.push([x0, b.costUsdMwh], [b.cumulativeMw, b.costUsdMwh], [b.cumulativeMw, null]);
      byLabel.set(b.label, arr);
    }
    const lab = m.hours.filter((h) => h.dayType === 'laborable');
    const dMax = Math.max(...lab.map((h) => h.demandMw)), dMin = Math.min(...lab.map((h) => h.demandMw));
    const total = m.supplyCurve[m.supplyCurve.length - 1]?.cumulativeMw ?? 1;
    const yMax = Math.min(m.priceCapUsdMwh, Math.max(...m.supplyCurve.map((b) => b.costUsdMwh), m.maxUsdMwh) * 1.1);
    const series: unknown[] = [...byLabel.entries()].map(([label, data]) => ({
      name: label, type: 'line', data, step: false, symbol: 'none', connectNulls: false,
      lineStyle: { color: fleetColor(label), width: 1.5 }, itemStyle: { color: fleetColor(label) }, areaStyle: { color: fleetColor(label), opacity: 0.55 },
    }));
    series.push({
      name: 'Demanda', type: 'line', data: [], markLine: {
        symbol: 'none', silent: true,
        data: [
          { xAxis: Math.round(dMax), label: { formatter: `Punta ${fmtNum(dMax, 0)} MW`, color: '#e6eef7' }, lineStyle: { color: '#e6eef7', type: 'solid', width: 2 } },
          { xAxis: Math.round(dMin), label: { formatter: `Valle ${fmtNum(dMin, 0)} MW`, color: CHART.text }, lineStyle: { color: CHART.text, type: 'dashed' } },
          { yAxis: +m.avgUsdMwh.toFixed(1), label: { formatter: `Precio medio ${fmtNum(m.avgUsdMwh, 0)}`, color: CHART.accent, position: 'insideStartTop' }, lineStyle: { color: CHART.accent, type: 'dashed', width: 2 } },
        ],
      },
    });
    return {
      backgroundColor: 'transparent', animation: false, textStyle: { color: CHART.text },
      grid: { left: 56, right: 24, top: 50, bottom: 36 },
      legend: { top: 0, textStyle: { color: CHART.text, fontSize: 11 }, itemWidth: 12, itemHeight: 8, data: [...byLabel.keys()] },
      tooltip: { trigger: 'item', backgroundColor: '#0f1d2e', borderColor: 'rgba(140,180,220,0.3)', textStyle: { color: '#e6eef7' },
        formatter: (p: { seriesName: string; value: [number, number] }) => `${p.seriesName}<br/>${fmtNum(p.value[1], 1)} US$/MWh · hasta ${fmtNum(p.value[0], 0)} MW` },
      xAxis: { type: 'value', min: 0, max: Math.ceil(total * 1.02), name: 'MW acumulados', nameLocation: 'middle', nameGap: 24, nameTextStyle: { color: CHART.text }, splitLine: { lineStyle: { color: CHART.grid } }, axisLabel: { color: CHART.text } },
      yAxis: { type: 'value', min: Math.min(0, m.priceFloorUsdMwh), max: Math.ceil(yMax / 10) * 10, name: 'US$/MWh', nameTextStyle: { color: CHART.text }, splitLine: { lineStyle: { color: CHART.grid } }, axisLabel: { color: CHART.text } },
      series,
    };
  }, [key]);
  const dayOpt = useMemo(() => {
    const lab = m.hours.filter((h) => h.dayType === 'laborable'), fin = m.hours.filter((h) => h.dayType === 'finde');
    const o = baseOption(lab.map((h) => `${h.hour} h`), { unit: ' US$/MWh' }) as Record<string, unknown>;
    return {
      ...o, grid: { left: 56, right: 64, top: 34, bottom: 28 },
      tooltip: { ...(o.tooltip as object), valueFormatter: (v: unknown) => (typeof v === 'number' ? fmtNum(v, 1) : String(v)) },
      yAxis: [{ ...(o.yAxis as object), name: 'US$/MWh', nameTextStyle: { color: CHART.text } }, { type: 'value', name: 'MW', nameTextStyle: { color: CHART.text }, splitLine: { show: false }, axisLabel: { color: CHART.text } }],
      series: [
        { name: 'Demanda laborable', type: 'line', yAxisIndex: 1, data: lab.map((h) => Math.round(h.demandMw)), lineStyle: { color: 'rgba(230,238,247,.45)' }, itemStyle: { color: 'rgba(230,238,247,.45)' }, areaStyle: { color: 'rgba(230,238,247,.06)' }, symbol: 'none' },
        { name: 'Demanda fin de semana', type: 'line', yAxisIndex: 1, data: fin.map((h) => Math.round(h.demandMw)), lineStyle: { color: 'rgba(230,238,247,.35)', type: 'dotted' }, itemStyle: { color: 'rgba(230,238,247,.35)' }, symbol: 'none' },
        { name: 'Precio laborable', type: 'line', data: lab.map((h) => +h.priceUsdMwh.toFixed(1)), lineStyle: { color: CHART.accent, width: 2.5 }, itemStyle: { color: CHART.accent }, symbol: 'circle', symbolSize: 4 },
        { name: 'Precio fin de semana', type: 'line', data: fin.map((h) => +h.priceUsdMwh.toFixed(1)), lineStyle: { color: CHART.violet, width: 2, type: 'dashed' }, itemStyle: { color: CHART.violet }, symbol: 'none' },
        { name: 'Vertimiento', type: 'bar', yAxisIndex: 1, data: lab.map((h) => Math.round(h.curtailFrac * h.demandMw)), itemStyle: { color: 'rgba(248,113,113,.55)' }, barWidth: 8 },
      ],
    };
  }, [key]);
  const curt = m.hours.some((h) => h.curtailFrac > 0.001);
  return (
    <div className="market-grid">
      <Section title="Curva de oferta (orden de mérito) y demanda" right={<span className="dim" style={{ fontSize: 11 }}>costo marginal por bloque · la unidad marginal fija el precio</span>}>
        <Chart option={curveOpt} height={340} />
      </Section>
      <Section title="Precios por hora del día tipo" right={<span className="dim" style={{ fontSize: 11 }}>{curt ? 'hay vertimiento de renovables' : 'sin vertimiento'}</span>}>
        <Chart option={dayOpt} height={340} />
      </Section>
    </div>
  );
}

function ForecastTab({ m }: { m: PowerMarketView }) {
  const key = `${m.countryCode}|${m.year}|${m.month}|${m.history.length}`;
  const fOpt = useMemo(() => {
    const f = m.forecast;
    const o = baseOption(f.map((x) => monthLabel(x.year, x.month)), { unit: ' US$/MWh' }) as Record<string, unknown>;
    return {
      ...o,
      tooltip: { ...(o.tooltip as object), valueFormatter: (v: unknown) => (typeof v === 'number' ? fmtNum(v, 1) : String(v)) },
      series: [
        { name: 'P10', type: 'line', stack: 'band', data: f.map((x) => +x.p10UsdMwh.toFixed(1)), lineStyle: { opacity: 0 }, symbol: 'none', itemStyle: { color: CHART.info } },
        { name: 'Banda P10–P90', type: 'line', stack: 'band', data: f.map((x) => +(x.p90UsdMwh - x.p10UsdMwh).toFixed(1)), lineStyle: { opacity: 0 }, symbol: 'none', areaStyle: { color: 'rgba(96,165,250,.22)' }, itemStyle: { color: 'rgba(96,165,250,.5)' } },
        { name: 'Media prevista', type: 'line', data: f.map((x) => +x.avgUsdMwh.toFixed(1)), lineStyle: { color: CHART.accent, width: 2.5 }, itemStyle: { color: CHART.accent }, symbol: 'circle', symbolSize: 5,
          markLine: { symbol: 'none', silent: true, data: [{ yAxis: +m.historicalMeanUsdMwh.toFixed(0), label: { formatter: 'histórico', color: CHART.text }, lineStyle: { color: CHART.dim, type: 'dotted' } }] } },
        { name: 'Punta', type: 'line', data: f.map((x) => +x.peakUsdMwh.toFixed(1)), lineStyle: { color: CHART.bad, type: 'dashed' }, itemStyle: { color: CHART.bad }, symbol: 'none' },
        { name: 'Valle', type: 'line', data: f.map((x) => +x.offpeakUsdMwh.toFixed(1)), lineStyle: { color: CHART.good, type: 'dashed' }, itemStyle: { color: CHART.good }, symbol: 'none' },
      ],
    };
  }, [key]);
  const hOpt = useMemo(() => {
    const h = m.history;
    const o = baseOption(h.map((x) => monthLabel(x.year, x.month)), { unit: ' US$/MWh' }) as Record<string, unknown>;
    return {
      ...o, grid: { left: 56, right: 56, top: 34, bottom: 28 },
      tooltip: { ...(o.tooltip as object), valueFormatter: (v: unknown) => (typeof v === 'number' ? fmtNum(v, v < 3 ? 2 : 1) : String(v)) },
      yAxis: [o.yAxis, { type: 'value', min: 0, max: 2, splitLine: { show: false }, axisLabel: { color: CHART.text, formatter: (v: number) => `${Math.round(v * 100)} %` } }],
      series: [
        { name: 'Mín.', type: 'line', stack: 'mm', data: h.map((x) => +x.minUsdMwh.toFixed(1)), lineStyle: { opacity: 0 }, symbol: 'none', itemStyle: { color: CHART.dim } },
        { name: 'Rango horario', type: 'line', stack: 'mm', data: h.map((x) => +(x.maxUsdMwh - x.minUsdMwh).toFixed(1)), lineStyle: { opacity: 0 }, symbol: 'none', areaStyle: { color: 'rgba(167,139,250,.16)' }, itemStyle: { color: 'rgba(167,139,250,.5)' } },
        { name: 'Spot medio', type: 'line', data: h.map((x) => +x.avgUsdMwh.toFixed(1)), lineStyle: { color: CHART.accent, width: 2 }, itemStyle: { color: CHART.accent }, symbol: 'none' },
        { name: 'Hidrología', type: 'bar', yAxisIndex: 1, data: h.map((x) => +x.hydrology.toFixed(2)), itemStyle: { color: 'rgba(96,165,250,.35)' } },
      ],
    };
  }, [key]);
  return (
    <div className="market-grid">
      <Section title="Previsión de 12 meses (banda P10–P90)" right={<span className="dim" style={{ fontSize: 11 }}>con la hidrología, combustibles y eventos conocidos hoy</span>}>
        <Chart option={fOpt} height={320} />
      </Section>
      <Section title={`Historial de precios (${m.history.length} meses)`}>
        {m.history.length === 0 ? <Empty>Aún no hay meses cerrados.</Empty> : <Chart option={hOpt} height={320} />}
      </Section>
    </div>
  );
}

function FleetTab({ m }: { m: PowerMarketView }) {
  const key = `${m.countryCode}|${m.fleet.map((f) => Math.round(f.existingMw + f.actorsMw)).join(',')}`;
  const opt = useMemo(() => {
    const f = m.fleet;
    return {
      backgroundColor: 'transparent', animation: false, textStyle: { color: CHART.text },
      grid: { left: 150, right: 24, top: 30, bottom: 24 },
      legend: { top: 0, textStyle: { color: CHART.text }, itemWidth: 12, itemHeight: 8 },
      tooltip: { trigger: 'axis', axisPointer: { type: 'shadow' }, backgroundColor: '#0f1d2e', borderColor: 'rgba(140,180,220,0.3)', textStyle: { color: '#e6eef7' }, valueFormatter: (v: number) => `${fmtNum(v, 0)} MW` },
      xAxis: { type: 'value', splitLine: { lineStyle: { color: CHART.grid } }, axisLabel: { color: CHART.text, formatter: (v: number) => `${v} MW` } },
      yAxis: { type: 'category', inverse: true, data: f.map((x) => x.label), axisLabel: { color: CHART.text, width: 140, overflow: 'truncate' }, axisLine: { lineStyle: { color: CHART.grid } } },
      series: [
        { name: 'Existente', type: 'bar', stack: 'mw', data: f.map((x) => ({ value: Math.round(x.existingMw), itemStyle: { color: fleetColor(x.label) } })), barWidth: 14 },
        { name: 'Empresas del juego', type: 'bar', stack: 'mw', data: f.map((x) => ({ value: Math.round(x.actorsMw), itemStyle: { color: '#e6eef7' } })) },
      ],
    };
  }, [key]);
  const total = m.fleet.reduce((a, f) => a + f.existingMw + f.actorsMw, 0);
  const actors = m.fleet.reduce((a, f) => a + f.actorsMw, 0);
  return (
    <div className="market-grid">
      <Section title={`Parque instalado por tecnología · ${fmtNum(total, 0)} MW`} right={<span className="dim" style={{ fontSize: 11 }}>empresas del juego: {fmtNum(actors, 0)} MW ({fmtPct(total ? actors / total : 0, 1)})</span>}>
        <Chart option={opt} height={Math.max(220, 34 * m.fleet.length + 50)} />
      </Section>
      <div>
        <Section title="Mercado de capacidad">
          {m.capacityMarket ? (
            <table className="kv"><tbody>
              <tr><td>Mecanismo</td><td style={{ whiteSpace: 'normal', fontFamily: 'inherit' }}>{m.capacityMarket.name}</td></tr>
              <tr><td>Precio de la potencia</td><td>{fmtNum(m.capacityMarket.priceUsdKwMonth, 1)} US$/kW-mes</td></tr>
              <tr><td>Por MW firme al año</td><td>{fmtNum(m.capacityMarket.priceUsdKwMonth * 12, 0)} k US$</td></tr>
            </tbody></table>
          ) : <div className="dim">Sin mercado de capacidad: solo se paga la energía (mercado de solo energía).</div>}
          <div className="dim" style={{ fontSize: 11.5, marginTop: 6 }}>Se paga por el crédito firme de cada tecnología × MW × disponibilidad: baterías, hidro y térmicas cobran mucho más que solar o eólica.</div>
        </Section>
        <Section title="Servicios complementarios">
          {m.ancillary ? (
            <>
              <table className="kv"><tbody>
                <tr><td>Servicio</td><td style={{ whiteSpace: 'normal', fontFamily: 'inherit' }}>{m.ancillary.name}</td></tr>
                <tr><td>Precio</td><td>{fmtNum(m.ancillary.priceUsdMwH, 1)} US$/MW-h</td></tr>
                <tr><td>Requerimiento del sistema</td><td>{fmtNum(m.ancillary.requirementMw, 0)} MW</td></tr>
                <tr><td>Ofrecido por las empresas</td><td>{fmtNum(m.ancillary.offeredMw, 0)} MW</td></tr>
              </tbody></table>
              {m.ancillary.offeredMw > m.ancillary.requirementMw && <div className="notice warn">La oferta supera el requerimiento: el pago por MW se diluye.</div>}
            </>
          ) : <div className="dim">Este país no paga servicios complementarios a privados.</div>}
        </Section>
        <Section title="Clima e hidrología">
          <div className="row" style={{ gap: 8 }}><Pill tone={ENSO_TONE[m.climate.enso]}>{m.climate.ensoLabel}</Pill><span>{m.climate.hydrologyLabel}: caudales al {fmtPct(m.climate.hydrology, 0)} de lo normal.</span></div>
          <div className="dim" style={{ fontSize: 11.5, marginTop: 6 }}>Un año seco encarece el valor del agua y el spot donde hay mucha hidro (Panamá, Colombia, Costa Rica, Brasil); El Niño suele secar el istmo y Colombia y mojar el sur de Chile.</div>
        </Section>
      </div>
    </div>
  );
}

function CompareTab({ sel, onPick }: { sel: string; onPick: (iso: string) => void }) {
  const rows = useUi((s) => s.views?.power?.markets) ?? [];
  const key = rows.map((r) => `${r.countryCode}${r.avgUsdMwh.toFixed(1)}`).join('|');
  const opt = useMemo(() => {
    const r = [...rows].sort((a, b) => b.avgUsdMwh - a.avgUsdMwh);
    const o = baseOption(r.map((x) => x.countryName), { unit: ' US$/MWh' }) as Record<string, unknown>;
    return {
      ...o, grid: { left: 56, right: 16, top: 34, bottom: 46 },
      xAxis: { ...(o.xAxis as object), axisLabel: { color: CHART.text, rotate: 30, interval: 0, fontSize: 11 } },
      tooltip: { ...(o.tooltip as object), valueFormatter: (v: unknown) => (typeof v === 'number' ? `${fmtNum(v, 1)} US$/MWh` : String(v)) },
      series: [
        { name: 'Spot medio', type: 'bar', data: r.map((x) => ({ value: +x.avgUsdMwh.toFixed(1), itemStyle: { color: x.countryCode === sel ? CHART.accent : 'rgba(96,165,250,.7)' } })) },
        { name: 'Punta', type: 'line', data: r.map((x) => +x.peakUsdMwh.toFixed(1)), lineStyle: { opacity: 0 }, symbol: 'triangle', symbolSize: 8, itemStyle: { color: CHART.bad } },
        { name: 'Valle', type: 'line', data: r.map((x) => +x.offpeakUsdMwh.toFixed(1)), lineStyle: { opacity: 0 }, symbol: 'diamond', symbolSize: 8, itemStyle: { color: CHART.good } },
      ],
    };
  }, [key, sel]);
  return (
    <div className="market-grid">
      <Section title="Spot del mes por país"><Chart option={opt} height={320} /></Section>
      <Section title="Tabla comparativa" right={<span className="dim" style={{ fontSize: 11 }}>clic para ver el país</span>}>
        <table className="grid-table" data-testid="power-compare">
          <thead><tr><th>País</th><th className="num">Spot medio</th><th className="num">Punta</th><th className="num">Valle</th><th className="num">Hidrología</th><th className="num">12 meses</th></tr></thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.countryCode} className={`clickable ${r.countryCode === sel ? 'selected' : ''}`} onClick={() => onPick(r.countryCode)}>
                <td><b>{r.countryName}</b></td>
                <td className="num mono">{fmtNum(r.avgUsdMwh, 1)}</td>
                <td className="num mono">{fmtNum(r.peakUsdMwh, 0)}</td>
                <td className="num mono">{fmtNum(r.offpeakUsdMwh, 0)}</td>
                <td className="num mono" style={{ color: r.hydrology < 0.85 ? 'var(--bad)' : r.hydrology > 1.1 ? 'var(--good)' : undefined }}>{fmtPct(r.hydrology, 0)}</td>
                <td className="num mono" style={{ color: (r.change12mPct ?? 0) > 10 ? 'var(--bad)' : (r.change12mPct ?? 0) < -10 ? 'var(--good)' : undefined }}>{r.change12mPct === null ? '—' : `${r.change12mPct >= 0 ? '+' : '−'}${fmtNum(Math.abs(r.change12mPct), 0)} %`}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </Section>
    </div>
  );
}
