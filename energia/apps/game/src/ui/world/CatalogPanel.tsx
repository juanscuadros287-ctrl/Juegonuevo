import { useMemo, useState } from 'react';
import { gameData } from '@voltaje/data';
import type { TechCatalogEntry, TechMode } from '@voltaje/sim';
import { ui, useUi } from '../store';
import { Empty, Pill, Section, Stat, Tabs, Window } from '../common';
import { Chart, CHART } from '../Chart';
import { fmtNum, fmtPct } from '../format';
import { MODE_LABEL, MODE_ORDER, MODE_SHORT, TECH_ICON, fuelName } from '../tech';

type Tab = 'tabla' | 'lcoe';
type Sort = 'nombre' | 'lcoe' | 'capex' | 'emisiones';

/** LCOE típico (o LCOH) de una tecnología en un país. */
const typicalIn = (e: TechCatalogEntry, iso3: string) => e.byCountry.find((c) => c.countryCode === iso3);
const lcoeOf = (e: TechCatalogEntry, iso3: string) => typicalIn(e, iso3)?.typical?.lcoeUsdMwh ?? null;

/** Rango de LCOE entre los países donde está permitida. */
function lcoeRange(e: TechCatalogEntry): [number, number] | null {
  const v = e.byCountry.map((c) => c.typical?.lcoeUsdMwh).filter((x): x is number => x !== undefined && Number.isFinite(x) && x > 0);
  return v.length ? [Math.min(...v), Math.max(...v)] : null;
}

export function CatalogPanel() {
  const catalog = useUi((s) => s.views?.business?.catalog);
  const home = useUi((s) => s.game?.company.homeCountry ?? 'PAN');
  const pick = useUi((s) => s.pick.catalog);
  const [tab, setTab] = useState<Tab>('tabla');
  const [mode, setMode] = useState<TechMode | 'todas'>('todas');
  const [country, setCountry] = useState<string>(home);
  const [onlyOpen, setOnlyOpen] = useState(false);
  const [sort, setSort] = useState<Sort>('nombre');
  const countries = useMemo(() => Object.values(gameData.simData.countries).sort((a, b) => a.nombre.localeCompare(b.nombre)), []);

  const list = useMemo(() => {
    const l = (catalog ?? []).filter((e) => (mode === 'todas' || e.mode === mode) && (!onlyOpen || e.unlocked));
    const key = (e: TechCatalogEntry) => (sort === 'lcoe' ? lcoeOf(e, country) ?? 1e9 : sort === 'capex' ? e.params.capexUsdKw.base : sort === 'emisiones' ? e.params.emissionsGco2Kwh : 0);
    return sort === 'nombre'
      ? l.sort((a, b) => MODE_ORDER.indexOf(a.mode) - MODE_ORDER.indexOf(b.mode) || a.nombre.localeCompare(b.nombre))
      : l.sort((a, b) => key(a) - key(b));
  }, [catalog, mode, onlyOpen, sort, country]);
  const sel = (catalog ?? []).find((e) => e.id === pick) ?? list[0];
  const choose = (id: string) => ui.set((s) => ({ pick: { ...s.pick, catalog: id } }));
  const cname = gameData.simData.countries[country]?.nombre ?? country;

  const unlocked = (catalog ?? []).filter((e) => e.unlocked).length;
  const cheapest = (catalog ?? []).filter((e) => e.mode === 'generacion' || e.mode === 'termica')
    .map((e) => ({ e, v: lcoeOf(e, country) })).filter((x): x is { e: TechCatalogEntry; v: number } => x.v !== null && x.v > 0).sort((a, b) => a.v - b.v)[0];
  const banned = (catalog ?? []).filter((e) => typicalIn(e, country) && !typicalIn(e, country)!.allowed).length;

  return (
    <Window title="Tecnologías" subtitle="Catálogo comparativo: costos, desempeño, emisiones y LCOE típico por país (sitio típico bueno, sin PPA, 7 % real)" width={1400} onClose={() => ui.openWindow(null)} testId="catalog-panel">
      <div className="stats-row">
        <Stat label="Tecnologías" value={`${unlocked} / ${catalog?.length ?? 0}`} hint="investigadas / en el catálogo" />
        <Stat label={`Más barata en ${cname}`} value={cheapest ? `${fmtNum(cheapest.v, 0)} US$/MWh` : '—'} hint={cheapest?.e.nombre} tone="good" />
        <Stat label={`Prohibidas en ${cname}`} value={banned} hint={banned ? 'por ley o sin regulador' : 'ninguna'} />
        <Stat label="Spot medio" value={`${fmtNum(gameData.simData.countries[country]?.mercado.precio_spot_medio_usd_mwh.base ?? 0, 0)} US$/MWh`} hint={`${cname} (referencia)`} />
      </div>
      <div className="row filters">
        <Tabs<Tab> value={tab} onChange={setTab} tabs={[{ id: 'tabla', label: 'Tabla comparativa' }, { id: 'lcoe', label: 'Gráfica de LCOE' }]} />
        <span className="spacer" />
        <div className="row seg">
          {(['todas', ...MODE_ORDER] as const).map((m) => (
            <button key={m} className={mode === m ? 'active' : ''} data-mode={m} onClick={() => setMode(m)}>{m === 'todas' ? 'Todas' : MODE_SHORT[m]}</button>
          ))}
        </div>
        <label className="row" style={{ gap: 6 }}>País
          <select value={country} onChange={(e) => setCountry(e.target.value)} data-testid="catalog-country">
            {countries.map((c) => <option key={c.iso3} value={c.iso3}>{c.nombre}</option>)}
          </select>
        </label>
        <label className="row" style={{ gap: 4 }}><input type="checkbox" checked={onlyOpen} onChange={(e) => setOnlyOpen(e.target.checked)} /> Solo investigadas</label>
      </div>
      <div className="window-body" style={{ display: 'flex', gap: 14, minHeight: 0, overflow: 'hidden' }}>
        {!catalog ? <div style={{ flex: 1 }}><Empty>Calculando el catálogo…</Empty></div> : (
          <>
            <div className="scroll" style={{ flex: 1, minWidth: 0 }}>
              {tab === 'tabla' ? <CatalogTable list={list} country={country} sel={sel?.id} onPick={choose} sort={sort} setSort={setSort} />
                : <LcoeChart list={list} country={country} cname={cname} />}
            </div>
            {sel && <TechCard e={sel} country={country} />}
          </>
        )}
      </div>
    </Window>
  );
}

function CatalogTable({ list, country, sel, onPick, sort, setSort }: { list: TechCatalogEntry[]; country: string; sel?: string; onPick: (id: string) => void; sort: Sort; setSort: (s: Sort) => void }) {
  const th = (s: Sort, label: string, cls = 'num') => <th className={`${cls} sortable ${sort === s ? 'sorted' : ''}`} onClick={() => setSort(s)}>{label}{sort === s ? ' ▴' : ''}</th>;
  return (
    <table className="grid-table catalog-table">
      <thead>
        <tr>
          {th('nombre', 'Tecnología', '')}<th className="col-estado">Estado</th>{th('capex', 'CAPEX US$/kW')}<th className="num">O&M fijo</th><th className="num">FC ref.</th>
          <th className="num">Vida · obra</th>{th('emisiones', 'gCO₂/kWh')}{th('lcoe', 'LCOE típico')}<th className="num">TIR</th>
        </tr>
      </thead>
      <tbody>
        {list.map((e) => {
          const t = typicalIn(e, country);
          const ty = t?.typical;
          const h2 = e.mode === 'hidrogeno';
          return (
            <tr key={e.id} className={`clickable ${sel === e.id ? 'selected' : ''}`} data-tech={e.id} onClick={() => onPick(e.id)}>
              <td style={{ maxWidth: 210 }}>
                <div className="row" style={{ gap: 7 }}><span className="tech-icon">{TECH_ICON[e.id]}</span><b className="ellipsis">{e.nombre}</b></div>
                <div className="dim" style={{ fontSize: 11, marginLeft: 29 }}>{MODE_LABEL[e.mode]}<span className="lock-hint">{e.unlocked ? '' : ' · requiere I+D'}</span></div>
              </td>
              <td className="col-estado">{e.unlocked ? <Pill tone="good">Investigada</Pill> : <span className="dim ellipsis" style={{ fontSize: 11, display: 'block', maxWidth: 120 }} title={`Requiere I+D: ${e.unlockNode?.nombre ?? '—'}`}>I+D: {e.unlockNode?.nombre ?? '—'}</span>}</td>
              <td className="num mono">{fmtNum(e.params.capexUsdKw.base, 0)}<div className="dim" style={{ fontSize: 10.5 }}>{fmtNum(e.params.capexUsdKw.min, 0)}–{fmtNum(e.params.capexUsdKw.max, 0)}</div></td>
              <td className="num mono">{fmtNum(e.params.omFixedUsdKwYear, 0)}<div className="dim" style={{ fontSize: 10.5 }}>+{fmtNum(e.params.omVarUsdMwh, 1)}/MWh</div></td>
              <td className="num mono">{e.mode === 'transmision' || e.mode === 'eficiencia' ? <span className="dim">—</span> : fmtPct(e.params.fcRef, 0)}</td>
              <td className="num mono">{e.params.lifeYears} a<div className="dim" style={{ fontSize: 10.5 }}>obra {e.params.constructionMonths} m</div></td>
              <td className="num mono" style={{ color: e.params.emissionsGco2Kwh > 300 ? 'var(--bad)' : e.params.emissionsGco2Kwh > 50 ? 'var(--warn)' : undefined }}>{fmtNum(e.params.emissionsGco2Kwh, 0)}</td>
              <td className="num mono">
                {!t ? '—' : !t.allowed ? <span style={{ color: 'var(--bad)', fontFamily: 'inherit' }} title={t.reason}>prohibida</span>
                  : h2 ? (ty?.lcohUsdKg ? `${fmtNum(ty.lcohUsdKg, 2)} US$/kg` : '—') : ty ? `${fmtNum(ty.lcoeUsdMwh, 0)}` : '—'}
                {t?.allowed && ty && !h2 && <div className="dim" style={{ fontSize: 10.5 }}>FC {fmtPct(ty.fc, 0)}{e.mode === 'termica' ? ` · desp. ${fmtPct(ty.dispatch, 0)}` : ''}</div>}
              </td>
              <td className="num mono" style={{ color: (ty?.irrEquity ?? 0) < 0.08 ? 'var(--text-dim)' : 'var(--good)' }}>{t?.allowed ? fmtPct(ty?.irrEquity ?? null, 0) : ''}</td>
            </tr>
          );
        })}
      </tbody>
    </table>
  );
}

function LcoeChart({ list, country, cname }: { list: TechCatalogEntry[]; country: string; cname: string }) {
  const rows = list.filter((e) => e.mode !== 'hidrogeno' && e.mode !== 'transmision' && e.mode !== 'eficiencia')
    .map((e) => ({ e, v: lcoeOf(e, country), r: lcoeRange(e) })).sort((a, b) => (a.v ?? 1e9) - (b.v ?? 1e9));
  const option = useMemo(() => ({
    backgroundColor: 'transparent', animation: false, textStyle: { color: CHART.text, fontFamily: 'inherit' },
    grid: { left: 190, right: 24, top: 30, bottom: 28 },
    legend: { top: 0, textStyle: { color: CHART.text }, itemWidth: 12, itemHeight: 8 },
    tooltip: { trigger: 'axis', axisPointer: { type: 'shadow' }, backgroundColor: '#0f1d2e', borderColor: 'rgba(140,180,220,0.3)', textStyle: { color: '#e6eef7' }, valueFormatter: (v: unknown) => (typeof v === 'number' ? `${v.toFixed(0)} US$/MWh` : '—') },
    xAxis: { type: 'value', name: 'US$/MWh', nameTextStyle: { color: CHART.text }, splitLine: { lineStyle: { color: CHART.grid } }, axisLabel: { color: CHART.text } },
    yAxis: { type: 'category', inverse: true, data: rows.map((x) => x.e.nombre), axisLabel: { color: CHART.text }, axisLine: { lineStyle: { color: CHART.grid } } },
    series: [
      { name: `En ${cname}`, type: 'bar', data: rows.map((x) => (x.v ? Math.round(x.v) : null)), itemStyle: { color: CHART.accent }, barGap: '10%', barMaxWidth: 12 },
      { name: 'Mínimo entre países', type: 'bar', data: rows.map((x) => (x.r ? Math.round(x.r[0]) : null)), itemStyle: { color: CHART.info }, barMaxWidth: 12 },
      { name: 'Máximo entre países', type: 'bar', data: rows.map((x) => (x.r ? Math.round(x.r[1]) : null)), itemStyle: { color: 'rgba(140,163,184,0.45)' }, barMaxWidth: 12 },
    ],
  }), [rows.map((x) => `${x.e.id}${x.v}`).join(), cname]);
  if (!rows.length) return <Empty>No hay tecnologías de generación con este filtro.</Empty>;
  return (
    <div data-testid="lcoe-chart">
      <Chart option={option} height={Math.max(260, rows.length * 30 + 70)} />
      <div className="hint">Almacenamiento = LCOS con el costo de la carga. Hidrógeno (LCOH), líneas (costo por MWh transportado) y ESCO (por MWh ahorrado) se comparan en la tabla. Las barras vacías son tecnologías prohibidas en el país.</div>
    </div>
  );
}

function TechCard({ e, country }: { e: TechCatalogEntry; country: string }) {
  const p = e.params;
  const rows: [string, string][] = [
    ['CAPEX', `${fmtNum(p.capexUsdKw.base, 0)} US$/kW (${fmtNum(p.capexUsdKw.min, 0)}–${fmtNum(p.capexUsdKw.max, 0)})`],
    ['O&M', `${fmtNum(p.omFixedUsdKwYear, 0)} US$/kW-año + ${fmtNum(p.omVarUsdMwh, 1)} US$/MWh`],
    ['Escala', `${p.scaleMw.min}–${fmtNum(p.scaleMw.max, 0)} MW (típico ${fmtNum(p.scaleMw.tipico, 0)})`],
    ['Vida / obra', `${p.lifeYears} años / ${p.constructionMonths} meses`],
    ['Degradación', `${fmtPct(p.degradation, 2)}/año`],
    ['Terreno', `${fmtNum(p.landHaMw, 2)} ha/MW`],
  ];
  if (p.fuel) rows.push(['Combustible', `${fuelName(p.fuel)} · ${fmtNum(p.heatRateBtuKwh ?? 0, 0)} Btu/kWh`]);
  if (p.storageHours) rows.push(['Almacenamiento', `${fmtNum(p.storageHours, 1)} h · ida y vuelta ${fmtPct(p.roundTrip, 0)}`]);
  if (p.h2KwhPerKg) rows.push(['Hidrógeno', `${fmtNum(p.h2KwhPerKg, 1)} kWh/kg · venta ${fmtNum(p.h2PriceUsdKg ?? 0, 2)} US$/kg`]);
  if (p.lineCostUsdMwKm) rows.push(['Línea', `${fmtNum(p.lineCostUsdMwKm, 0)} US$/MW-km · pérdidas ${fmtPct(p.lineLossesPer100km, 1)}/100 km · peaje ${fmtNum(p.tollUsdMwh ?? 0, 1)} US$/MWh`]);
  if (p.savingsPriceUsdMwh) rows.push(['Ahorro', `${fmtNum(p.savingsPriceUsdMwh, 0)} US$/MWh · garantizado ${fmtPct(p.guaranteedSavings, 0)}`]);
  const h2 = e.mode === 'hidrogeno';
  return (
    <div className="side-card scroll catalog-side" data-testid="tech-card">
      <div className="row" style={{ gap: 8 }}>
        <span className="tech-icon" style={{ fontSize: 20 }}>{TECH_ICON[e.id]}</span>
        <div style={{ minWidth: 0 }}>
          <div style={{ fontSize: 15, fontWeight: 700 }}>{e.nombre}</div>
          <div className="dim" style={{ fontSize: 11.5 }}>{e.modeLabel} · {e.unlocked ? 'investigada' : `requiere ${e.unlockNode?.nombre ?? 'I+D'}`}</div>
        </div>
      </div>
      {!e.unlocked && e.unlockNode && <button style={{ width: '100%', marginTop: 8 }} onClick={() => ui.openPanel('research', e.unlockNode!.id)}>Ver en I+D: {e.unlockNode.nombre}</button>}
      <table className="kv" style={{ marginTop: 8 }}><tbody>{rows.map(([k, v]) => <tr key={k}><td>{k}</td><td style={{ fontSize: 11.5 }}>{v}</td></tr>)}</tbody></table>
      {!!e.restrictions.length && (
        <Section title="Restricciones de sitio">
          <ul className="obligations">{e.restrictions.map((r) => <li key={r}>{r}</li>)}</ul>
        </Section>
      )}
      {!!e.risks.length && (
        <Section title="Riesgos propios">
          <ul className="obligations">{e.risks.map((r) => <li key={r.id}><b>{r.nombre}:</b> <span className="dim">{r.descripcion}</span></li>)}</ul>
        </Section>
      )}
      <Section title={h2 ? 'LCOH típico por país' : 'LCOE típico por país'}>
        <table className="grid-table ranking">
          <thead><tr><th>País</th><th className="num">{h2 ? 'US$/kg' : 'US$/MWh'}</th><th className="num">FC</th><th className="num">US$/kW</th><th className="num">TIR</th></tr></thead>
          <tbody>
            {e.byCountry.map((c) => (
              <tr key={c.countryCode} className={c.countryCode === country ? 'me' : ''}>
                <td><span className="ellipsis" style={{ display: 'block', maxWidth: 130 }}>{c.countryName}</span></td>
                {!c.allowed ? <td colSpan={4} style={{ color: 'var(--bad)', fontSize: 11 }} title={c.reason}>prohibida{c.reason ? `: ${c.reason}` : ''}</td> : !c.typical ? <td colSpan={4} className="dim">sin datos</td> : (
                  <>
                    <td className="num mono">{h2 ? fmtNum(c.typical.lcohUsdKg ?? 0, 2) : fmtNum(c.typical.lcoeUsdMwh, 0)}</td>
                    <td className="num mono">{fmtPct(c.typical.fc, 0)}</td>
                    <td className="num mono">{fmtNum(c.typical.capexUsdKw, 0)}</td>
                    <td className="num mono">{fmtPct(c.typical.irrEquity, 0)}</td>
                  </>
                )}
              </tr>
            ))}
          </tbody>
        </table>
      </Section>
    </div>
  );
}
