import { useMemo, useState } from 'react';
import { gameData } from '@voltaje/data';
import type { CountrySheet, CountrySummary } from '@voltaje/sim';
import { sim } from '../../worker/client';
import { FUELS_PICK, ui, useUi } from '../store';
import { ConfirmButton, Empty, Pill, Section, Stat, Tabs, Window } from '../common';
import { Chart, CHART, baseOption } from '../Chart';
import { fmtDate, fmtMoney, fmtNum, fmtPct, monthLabel, dateOfTick } from '../format';
import type { FuelMarket } from '../../worker/protocol';
import { COUNTRY_MARK_COLORS } from '../../globe/countries';
import { countryCenter, getGlobe } from '../../globe/GlobeView';
import { MODE_ORDER, TECH_ICON, allTechs, fuelName, modeOf } from '../tech';
import { techName } from '../business/labels';
import { PermitGraphView } from './PermitGraphView';

type Tab = 'lista' | 'ficha' | 'combustibles';

const PRESENCE: Record<CountrySummary['presence'], { label: string; tone: 'good' | 'warn' | 'info' | 'dim' }> = {
  origen: { label: 'País de origen', tone: 'good' }, activa: { label: 'Presencia', tone: 'good' }, en_tramite: { label: 'En trámite', tone: 'warn' }, ninguna: { label: 'Sin presencia', tone: 'dim' },
};
const statusOf = (c: CountrySummary) => (c.presence !== 'ninguna' ? PRESENCE[c.presence] : c.unlocked ? { label: 'Desbloqueado', tone: 'info' as const } : { label: 'Cerrado (I+D)', tone: 'dim' as const });

/** Centro del país para volar la cámara (la zona habilitada si la hay, p. ej. Texas). */
function centerOf(iso3: string): { lat: number; lon: number } | null {
  const z = gameData.simData.countries[iso3]?.zona;
  if (z) return { lat: (z.lat_min + z.lat_max) / 2, lon: (z.lon_min + z.lon_max) / 2 };
  return countryCenter(iso3);
}

export function CountriesPanel() {
  const countries = useUi((s) => s.views?.business?.countries ?? []);
  const pick = useUi((s) => s.pick.countries);
  const sheet = useUi((s) => s.views?.business?.countrySheet);
  const fuels = useUi((s) => s.views?.business?.fuels);
  const game = useUi((s) => s.game);
  const [tabState, setTab] = useState<Tab>('lista');
  // abrir con un país elegido (clic en el globo, evento) lleva directo a su ficha
  const [lastPick, setLastPick] = useState<string | undefined>(undefined);
  let tab = tabState;
  if (pick !== lastPick) { setLastPick(pick); tab = pick === FUELS_PICK ? 'combustibles' : pick ? 'ficha' : tabState; if (tab !== tabState) setTab(tab); }
  const iso = pick && pick !== FUELS_PICK ? pick : undefined;
  const choose = (id: string) => { ui.set((s) => ({ pick: { ...s.pick, countries: id } })); sim.country(id); };
  const pres = Object.values(game?.business?.presence ?? {});
  const monthly = pres.filter((p) => p.status === 'activa').reduce((a, p) => a + p.monthlyCostUsd, 0);
  const sel = countries.find((c) => c.iso3 === iso);

  return (
    <Window title="Países y expansión" subtitle="Mercados con datos: acceso por I+D, presencia local, moneda, permisos y combustibles" width={1440} onClose={() => ui.openWindow(null)} testId="countries-panel"
      actions={sel && tab === 'ficha' ? <button onClick={() => { const c = centerOf(sel.iso3); if (c) { ui.openWindow(null); getGlobe()?.flyTo(c.lat, c.lon, 1.9); } }} title="Volar al país en el globo">⌖ Ver en el globo</button> : undefined}>
      <div className="stats-row">
        <Stat label="Países con presencia" value={countries.filter((c) => c.presence === 'activa' || c.presence === 'origen').length} hint={`${countries.filter((c) => c.presence === 'en_tramite').length} en trámite`} tone="good" />
        <Stat label="Desbloqueados (I+D)" value={`${countries.filter((c) => c.unlocked).length} / ${countries.length}`} hint="mercados investigados" />
        <Stat label="Costo de presencia" value={`${fmtMoney(monthly)}/mes`} hint="representantes legales" />
        <Stat label="Mis proyectos fuera" value={countries.filter((c) => c.presence !== 'origen').reduce((a, c) => a + c.myProjects, 0)} hint="fuera del país de origen" />
        <Stat label="Oportunidades abiertas" value={countries.reduce((a, c) => a + c.openOpportunities, 0)} hint="en todos los países" />
      </div>
      <Tabs<Tab> value={tab} onChange={(t) => { setTab(t); if (t === 'combustibles') ui.set((s) => ({ pick: { ...s.pick, countries: FUELS_PICK } })); else if (t === 'ficha' && !iso && countries[0]) choose(game?.company.homeCountry ?? countries[0].iso3); }} tabs={[
        { id: 'lista', label: `Países (${countries.length})` },
        { id: 'ficha', label: sel ? `Ficha: ${sel.nombre}` : 'Ficha de país' },
        { id: 'combustibles', label: 'Combustibles' },
      ]} />
      <div className="window-body scroll" style={{ minHeight: 0 }}>
        {tab === 'lista' && <CountryList list={countries} onPick={choose} sel={iso} />}
        {tab === 'ficha' && (iso ? (sheet && sheet.iso3 === iso ? <Sheet s={sheet} summary={sel} /> : <Empty>Cargando ficha…</Empty>) : <Empty>Elige un país de la lista.</Empty>)}
        {tab === 'combustibles' && <Fuels fuels={fuels} />}
      </div>
    </Window>
  );
}

function CountryList({ list, onPick, sel }: { list: CountrySummary[]; onPick: (id: string) => void; sel?: string }) {
  return (
    <table className="grid-table">
      <thead><tr><th>País</th><th>Estado</th><th>Acceso</th><th className="num">Spot hoy</th><th className="num">Moneda</th><th className="num">Tipo de cambio real</th><th className="num">Riesgo país</th><th className="num">Inflación</th><th className="num">Mis proyectos</th><th className="num">Oportunidades</th></tr></thead>
      <tbody>
        {list.map((c) => {
          const st = statusOf(c);
          const mark = c.presence === 'origen' || c.presence === 'activa' ? 'presencia' : c.presence === 'en_tramite' ? 'tramite' : c.unlocked ? 'desbloqueado' : 'cerrado';
          return (
            <tr key={c.iso3} className={`clickable ${sel === c.iso3 ? 'selected' : ''}`} data-country={c.iso3} onClick={() => onPick(c.iso3)}>
              <td><span className="swatch" style={{ background: COUNTRY_MARK_COLORS[mark] }} /><b>{c.nombre}</b> <span className="dim mono" style={{ fontSize: 11 }}>{c.iso3}</span></td>
              <td><Pill tone={st.tone}>{st.label}</Pill></td>
              <td className="dim" style={{ fontSize: 11.5 }}>{c.presence === 'origen' ? '—' : c.unlocked ? (c.presence === 'ninguna' ? 'falta abrir presencia' : 'abierto') : `I+D: ${c.unlockNode ?? '—'}`}</td>
              <td className="num mono">{fmtNum(c.spotUsdMwh, 0)} US$/MWh</td>
              <td className="num mono">{c.currency}<div className="dim" style={{ fontSize: 10.5 }}>{fmtFx(c.usdPerUnitNow)} por US$</div></td>
              <td className="num mono" style={{ color: c.realIndex < 0.95 ? 'var(--bad)' : c.realIndex > 1.05 ? 'var(--good)' : undefined }}>{fmtNum(c.realIndex, 3)}</td>
              <td className="num mono">{fmtPct(c.countryRiskPremium, 1)}</td>
              <td className="num mono">{fmtPct(c.inflation, 1)}</td>
              <td className="num mono">{c.myProjects || <span className="dim">–</span>}</td>
              <td className="num mono">{c.openOpportunities || <span className="dim">–</span>}</td>
            </tr>
          );
        })}
      </tbody>
    </table>
  );
}

/** Unidades de moneda local por US$ (más legible que US$ por unidad). */
const fmtFx = (usdPerUnit: number) => { const v = 1 / usdPerUnit; return fmtNum(v, v >= 100 ? 0 : v >= 10 ? 1 : 3); };

function Sheet({ s, summary }: { s: CountrySheet; summary?: CountrySummary }) {
  const techs = allTechs().filter((t) => !s.restrictions?.banned.includes(t.id));
  const [techId, setTechId] = useState<string>('solar_fv');
  const tech = gameData.simData.technologies[techId];
  const path = s.permitPaths.find((p) => p.techId === techId);
  const months = s.market.monthlySpot;
  const spotOpt = useMemo(() => {
    const o = baseOption(['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'], { unit: '' });
    return { ...o, grid: { left: 40, right: 10, top: 26, bottom: 22 }, series: [{ name: 'Spot medio (US$/MWh)', type: 'bar', data: months.map((v) => Math.round(v)), itemStyle: { color: CHART.info } }] };
  }, [s.iso3]);
  const fxOpt = useMemo(() => {
    const h = s.currency.history;
    const o = baseOption(h.map((x) => monthLabel(x.year, x.month)), { unit: '' });
    return {
      ...o, grid: { left: 52, right: 10, top: 26, bottom: 22 }, yAxis: { ...(o.yAxis as object), scale: true },
      series: [{ name: `${s.currency.code} por US$`, type: 'line', data: h.map((x) => +(1 / x.usdPerUnit).toPrecision(5)), symbol: 'none', lineStyle: { color: CHART.accent, width: 2 }, itemStyle: { color: CHART.accent } }],
    };
  }, [s.iso3, s.currency.history.length]);
  const change = s.currency.usdPerUnitNow / s.currency.usdPerUnitStart - 1;
  const mix = Object.entries(s.market.mix ?? {}).filter(([, v]) => typeof v === 'number').sort((a, b) => (b[1] as number) - (a[1] as number));
  return (
    <div className="sheet" data-testid="country-sheet">
      <div className="sheet-grid">
        <PresenceCard s={s} summary={summary} />
        <Section title="Mercado eléctrico">
          <div className="mini-stats">
            <div><span className="dim">Spot hoy</span><b className="mono">{fmtNum(s.market.spotNowUsdMwh, 0)}</b><span className="dim">US$/MWh</span></div>
            <div><span className="dim">Demanda</span><b className="mono">{fmtNum(s.market.demandTwh ?? 0, 0)}</b><span className="dim">TWh/año</span></div>
            <div><span className="dim">Pico</span><b className="mono">{fmtNum(s.market.peakMw ?? 0, 0)}</b><span className="dim">MW</span></div>
            <div><span className="dim">Punta / valle</span><b className="mono">×{fmtNum(s.market.peakFactor, 2)} / ×{fmtNum(s.market.valleyFactor, 2)}</b></div>
          </div>
          <Chart option={spotOpt} height={130} />
          {mix.length > 0 && <div className="mix-bar" title="Matriz de generación">{mix.map(([k, v], i) => <div key={k} style={{ flex: v as number, background: MIX_COLORS[i % MIX_COLORS.length] }} title={`${k}: ${fmtPct(v as number, 0)}`} />)}</div>}
          {mix.length > 0 && <div className="weights-legend">{mix.slice(0, 6).map(([k, v], i) => <span key={k}><i className="wl" style={{ background: MIX_COLORS[i % MIX_COLORS.length] }} />{k.replace(/_/g, ' ')} <b className="mono">{fmtPct(v as number, 0)}</b></span>)}</div>}
        </Section>
        <Section title={`Moneda: ${s.currency.name ?? s.currency.code}`} right={<Pill tone={s.currency.pegged ? 'good' : Math.abs(change) > 0.05 ? 'warn' : 'dim'}>{s.currency.pegged ? 'fija al US$' : `${change >= 0 ? '+' : ''}${fmtPct(change, 1)} vs inicio`}</Pill>}>
          <table className="kv"><tbody>
            <tr><td>Hoy</td><td>{fmtFx(s.currency.usdPerUnitNow)} {s.currency.code}/US$ <span className="dim">(inicio {fmtFx(s.currency.usdPerUnitStart)})</span></td></tr>
            <tr><td>Índice real</td><td>{fmtNum(s.currency.realIndex, 3)} · volatilidad {fmtPct(s.currency.volatility, 0)}/año</td></tr>
            <tr><td>Shocks</td><td>{fmtPct(s.currency.shockProbYear, 0)}/año · deriva {fmtPct(s.currency.drift, 1)}</td></tr>
            <tr><td>Contratos en</td><td>{s.currency.contractsIn === 'local' ? <span style={{ color: 'var(--warn)' }}>moneda local (riesgo cambiario)</span> : 'US$'}</td></tr>
          </tbody></table>
          {s.currency.history.length > 1 ? <Chart option={fxOpt} height={120} /> : <div className="hint">El historial del tipo de cambio se llena mes a mes.</div>}
        </Section>
      </div>

      <Section title="Permisos" right={
        <label className="row" style={{ gap: 6, fontSize: 12 }}>Ruta crítica para
          <select value={techId} onChange={(e) => setTechId(e.target.value)} data-testid="permit-tech">
            {MODE_ORDER.map((m) => <optgroup key={m} label={m}>{techs.filter((t) => modeOf(t.id) === m).map((t) => <option key={t.id} value={t.id}>{TECH_ICON[t.id]} {t.nombre}</option>)}</optgroup>)}
          </select>
        </label>}>
        {path && (
          <div className="row path-summary">
            <span><b>{path.permits}</b> permisos para {tech?.nombre} ({fmtNum(tech?.escala_mw.tipico ?? 0, 0)} MW)</span>
            <span>Ruta crítica esperada <b className="mono">{fmtNum(path.days / 30.44, 1)} meses</b> <span className="dim">({fmtNum(path.days, 0)} d, con pedidos de información)</span></span>
            <span>Aprobar todos al primer intento <b className="mono" style={{ color: path.approvalAll < 0.4 ? 'var(--bad)' : path.approvalAll < 0.7 ? 'var(--warn)' : 'var(--good)' }}>{fmtPct(path.approvalAll, 0)}</b></span>
            <span>Costo <b className="mono">{fmtMoney(path.costUsd)}</b></span>
            <span className="dim" style={{ fontSize: 11 }}><i className="lg-crit" /> ruta crítica · atenuados: no aplican</span>
          </div>
        )}
        <PermitGraphView graph={s.permits} techId={techId} mw={tech?.escala_mw.tipico ?? 50} />
      </Section>

      <div className="sheet-grid">
        <Section title="Macro e impuestos">
          <table className="kv"><tbody>
            <tr><td>Regulador / operador</td><td style={{ fontSize: 11 }}>{s.regulator?.split(' (')[0] ?? '—'} / {s.systemOperator?.split(' (')[0] ?? '—'}</td></tr>
            <tr><td>Inflación local</td><td>{fmtPct(s.macro.inflation, 1)} <span className="dim">(precios en US$: {fmtPct(s.macro.usdPriceInflation, 1)})</span></td></tr>
            <tr><td>Riesgo país</td><td>{fmtPct(s.macro.countryRiskPremium, 2)} <span className="dim">· libre de riesgo {fmtPct(s.macro.riskFree, 1)}</span></td></tr>
            <tr><td>Impuesto a la renta</td><td>{fmtPct(s.taxes.income, 0)} · depreciación {s.taxes.depreciationYears} años</td></tr>
            <tr><td>IVA / arancel de equipos</td><td>{fmtPct(s.taxes.vat, 0)} / {fmtPct(s.taxes.tariff, 0)}</td></tr>
            <tr><td>Construcción local</td><td>×{fmtNum(s.costs.localConstruction, 2)} · {fmtPct(s.costs.localCostShare, 0)} costos locales</td></tr>
            <tr><td>Prospección</td><td>{fmtMoney(s.costs.prospectingUsd)} · terreno {fmtNum(s.costs.landLeaseUsdHaYear, 0)} US$/ha-año</td></tr>
            <tr><td>Lluvias / huelgas</td><td>{s.risks.construction.rainyMonths.length} meses lluviosos · huelga {fmtPct(s.risks.construction.strikeProbMonth, 1)}/mes</td></tr>
          </tbody></table>
        </Section>
        <Section title="Incentivos, carbono, combustibles y restricciones">
          {s.incentives.length ? <ul className="obligations">{s.incentives.map((i) => (
            <li key={i.techId}><b>{techName(i.techId)}:</b> {i.descripcion}{i.taxCredit ? ` (crédito ${fmtPct(i.taxCredit, 0)})` : ''}</li>
          ))}</ul> : <div className="dim" style={{ fontSize: 12 }}>Sin incentivos específicos.</div>}
          <table className="kv" style={{ marginTop: 6 }}><tbody>
            <tr><td>Precio del carbono</td><td>{s.carbon ? `${fmtNum(s.carbon.priceUsdT, 0)} US$/t CO₂ (+${fmtPct(s.carbon.growth, 0)}/año)` : <span className="dim">no hay</span>}</td></tr>
            {s.fuels.map((f) => <tr key={f.type}><td>{fuelName(f.type)}</td><td>{fmtNum(f.priceUsdMmbtu, 2)} US$/MMBtu</td></tr>)}
            {s.zone && <tr><td>Zona habilitada</td><td>{s.zone.nombre}</td></tr>}
          </tbody></table>
          {s.restrictions && s.restrictions.banned.length > 0 && <div className="notice bad" style={{ marginTop: 6, fontSize: 12 }}><b>Prohibidas:</b> {s.restrictions.banned.map(techName).join(', ')}{s.restrictions.reason ? ` — ${s.restrictions.reason}` : ''}</div>}
        </Section>
        <Section title="Bancos y canales de venta">
          <table className="grid-table ranking"><thead><tr><th>Banco</th><th className="num">Tasa</th><th className="num">Plazo</th><th className="num">Deuda máx.</th></tr></thead>
            <tbody>{s.lenders.map((l) => (
              <tr key={l.id}><td><span className="ellipsis" style={{ display: 'block', maxWidth: 170 }} title={l.nombre}>{l.nombre}</span><span className="dim" style={{ fontSize: 10.5 }}>{l.tipo}{l.requiresPpa ? ' · exige PPA' : ''}</span></td>
                <td className="num mono">{fmtNum(l.ratePct, 1)} %</td><td className="num mono">{l.tenorYears} a</td><td className="num mono">{fmtPct(l.maxLeverage, 0)}</td></tr>
            ))}</tbody>
          </table>
          <table className="grid-table ranking" style={{ marginTop: 8 }}><thead><tr><th>Canal PPA</th><th className="num">Precio</th><th className="num">Plazo</th><th className="num">Prob.</th></tr></thead>
            <tbody>{s.ppaChannels.map((c) => (
              <tr key={c.id} title={c.descripcion}><td><span className="ellipsis" style={{ display: 'block', maxWidth: 170 }}>{c.nombre}</span><span className="dim" style={{ fontSize: 10.5 }}>{c.currency === 'local' ? 'moneda local' : 'US$'}{c.techs ? ` · ${c.techs.length} tec.` : ''}</span></td>
                <td className="num mono">{fmtNum(c.priceUsdMwh, 0)}</td><td className="num mono">{c.years} a</td><td className="num mono">{fmtPct(c.probability, 0)}</td></tr>
            ))}</tbody>
          </table>
        </Section>
      </div>
    </div>
  );
}

const MIX_COLORS = ['#60a5fa', '#4ade80', '#ffcb3d', '#f87171', '#a78bfa', '#22d3ee', '#fb923c', '#94a3b8'];

function PresenceCard({ s, summary }: { s: CountrySheet; summary?: CountrySummary }) {
  const game = useUi((st) => st.game);
  const cash = game?.company.cashUsd ?? 0;
  const pr = s.presence;
  const active = game ? game.projects.filter((p) => p.countryCode === s.iso3 && !['vendido', 'abandonado', 'desmantelado'].includes(p.stage)).length : 0;
  const ready = pr.readyTick !== undefined && game ? fmtDate(dateOfTick(game, pr.readyTick)) : '—';
  return (
    <Section title="Presencia y acceso" right={summary && <Pill tone={statusOf(summary).tone}>{statusOf(summary).label}</Pill>}>
      <div data-testid="presence-card">
        <table className="kv"><tbody>
          <tr><td>Mercado (I+D)</td><td>{s.unlocked ? <span style={{ color: 'var(--good)' }}>✓ investigado</span> : <span style={{ color: 'var(--warn)' }}>✕ {s.unlockNode?.nombre ?? 'requiere I+D'}</span>}</td></tr>
          {!pr.home && <tr><td>Constitución</td><td>{fmtMoney(pr.setupCostUsd)} · {pr.days ? `${pr.days.min}–${pr.days.max} días` : '—'}</td></tr>}
          {!pr.home && <tr><td>Representante legal</td><td>{fmtMoney(pr.monthlyCostUsd)}/mes</td></tr>}
          {pr.status === 'en_tramite' && <tr><td>Lista</td><td>{ready}</td></tr>}
          <tr><td>Proyectos propios</td><td>{active}</td></tr>
          <tr><td>Oportunidades abiertas</td><td>{summary?.openOpportunities ?? 0}</td></tr>
        </tbody></table>
        {pr.home ? <div className="hint">País de origen: siempre abierto.</div>
          : pr.active ? (
            <div style={{ marginTop: 8 }}>
              <ConfirmButton disabled={active > 0} title={active > 0 ? 'Solo sin proyectos ni contratos activos' : undefined}
                confirm="Se deja de pagar el representante; la constitución no se recupera." onConfirm={() => sim.command({ type: 'closePresence', countryCode: s.iso3 })}>Cerrar presencia</ConfirmButton>
              {active > 0 && <div className="hint">Para cerrar no puede haber proyectos ni contratos activos.</div>}
            </div>
          ) : pr.status === 'en_tramite' ? <div className="notice warn" style={{ marginTop: 8 }}>Constitución en trámite: lista hacia el {ready}.</div>
          : (
            <div style={{ marginTop: 8 }}>
              {!!pr.blockers.length && <div className="notice warn" style={{ marginBottom: 6, fontSize: 12 }}>{pr.blockers.join(' ')}</div>}
              <ConfirmButton className="primary" disabled={pr.blockers.length > 0 || cash < (pr.setupCostUsd ?? 0)}
                confirm={`${fmtMoney(pr.setupCostUsd)} ahora y ${fmtMoney(pr.monthlyCostUsd)}/mes.`} onConfirm={() => sim.command({ type: 'openPresence', countryCode: s.iso3 })}>
                <span data-testid="open-presence">Abrir presencia ({fmtMoney(pr.setupCostUsd)}, ~{pr.days?.base ?? '?'} días)</span>
              </ConfirmButton>
              {!s.unlocked && s.unlockNode && <button style={{ marginLeft: 6 }} onClick={() => ui.openPanel('research', s.unlockNode!.id)}>Ir a I+D</button>}
            </div>
          )}
      </div>
    </Section>
  );
}

const FUEL_COLORS = ['#ffcb3d', '#60a5fa', '#f87171', '#a78bfa', '#4ade80', '#22d3ee', '#fb923c'];

function Fuels({ fuels }: { fuels?: FuelMarket[] }) {
  const [rel, setRel] = useState(false);
  const opt = useMemo(() => {
    const h = fuels?.[0]?.history ?? [];
    const o = baseOption(h.map((x) => monthLabel(x.year, x.month)), { unit: '' });
    return {
      ...o, grid: { left: 52, right: 16, top: 50, bottom: 28 },
      series: (fuels ?? []).map((f, i) => ({
        name: f.nombre, type: 'line', symbol: 'none', lineStyle: { color: FUEL_COLORS[i % FUEL_COLORS.length], width: 2 }, itemStyle: { color: FUEL_COLORS[i % FUEL_COLORS.length] },
        data: f.history.map((x) => +(rel ? x.index : x.index * f.referenceUsdMmbtu).toFixed(3)),
      })),
    };
  }, [fuels?.[0]?.history.length, rel, fuels?.map((f) => f.index).join()]);
  if (!fuels) return <Empty>Cargando…</Empty>;
  return (
    <div data-testid="fuels">
      <Section title={rel ? 'Índice de precio (1 = referencia)' : 'Precio de referencia × índice (US$/MMBtu)'} right={<label className="row" style={{ gap: 4, fontSize: 12 }}><input type="checkbox" checked={rel} onChange={(e) => setRel(e.target.checked)} /> Ver como índice</label>}>
        {(fuels[0]?.history.length ?? 0) > 1 ? <Chart option={opt} height={300} /> : <Empty>El historial se llena mes a mes: deja correr el tiempo.</Empty>}
      </Section>
      <Section title="Combustibles">
        <table className="grid-table">
          <thead><tr><th>Combustible</th><th className="num">Referencia</th><th className="num">Hoy</th><th className="num">Índice</th><th className="num">Mín. / máx. del historial</th><th className="num">Emisiones</th><th>Lo usan</th></tr></thead>
          <tbody>{fuels.map((f, i) => {
            const idx = f.history.map((x) => x.index);
            const users = allTechs().filter((t) => t.combustible?.tipo === f.id || (f.id.startsWith('gas') || f.id === 'gnl' ? t.combustible?.tipo === 'gas_natural' : false));
            return (
              <tr key={f.id}>
                <td><span className="swatch" style={{ background: FUEL_COLORS[i % FUEL_COLORS.length] }} />{f.nombre}</td>
                <td className="num mono">{fmtNum(f.referenceUsdMmbtu, 2)} US$/MMBtu</td>
                <td className="num mono"><b>{fmtNum(f.priceUsdMmbtu, 2)}</b></td>
                <td className="num mono" style={{ color: f.index > 1.15 ? 'var(--bad)' : f.index < 0.87 ? 'var(--good)' : undefined }}>{fmtNum(f.index, 2)}</td>
                <td className="num mono">{idx.length ? `${fmtNum(Math.min(...idx), 2)} / ${fmtNum(Math.max(...idx), 2)}` : '—'}</td>
                <td className="num mono">{fmtNum(f.emissionsKgMmbtu, 1)} kg/MMBtu</td>
                <td className="dim" style={{ fontSize: 11.5 }}>{[...new Set(users.map((t) => t.nombre))].join(', ') || '—'}</td>
              </tr>
            );
          })}</tbody>
        </table>
        <div className="hint">Cada país aplica su factor (transporte, regasificación, subsidios): ver la ficha. El costo variable de las térmicas = heat rate × combustible + CO₂ × precio del carbono.</div>
      </Section>
    </div>
  );
}
