import { useState } from 'react';
import { gameData } from '@voltaje/data';
import { currentDate, type WorldEventView } from '@voltaje/sim';
import { ui, useUi } from '../store';
import { Empty, Pill, Section, Stat, Tabs, Window } from '../common';
import { fmtDate, fmtMoney, fmtNum, MONTHS_SHORT } from '../format';
import { countryCenter, getGlobe } from '../../globe/GlobeView';
import { techName } from '../business/labels';
import { isGrave, kindOf } from './worldLabels';

type Tab = 'eventos' | 'gobiernos' | 'avances';

const daysText = (d: number) => (d < 60 ? `${d} d` : `${fmtNum(d / 30.44, 0)} meses`);

export function EventCard({ e, mine }: { e: WorldEventView; mine?: boolean }) {
  const k = kindOf(e.kind);
  const fly = () => {
    const c = e.countries?.[0] ? countryCenter(e.countries[0]) : null;
    ui.openWindow(null);
    if (c) getGlobe()?.flyTo(c.lat, c.lon, 1.7); else getGlobe()?.flyTo(10, -40, 3.2);
  };
  return (
    <div className="event-card" style={{ borderLeftColor: k.color, opacity: e.active ? 1 : 0.78 }} data-world-event={e.id}>
      <div className="row" style={{ gap: 8 }}>
        <span className="badge" style={{ color: k.color, border: `1px solid ${k.color}` }}>{k.label}</span>
        <b style={{ fontSize: 13.5 }}>{e.name}</b>
        {isGrave(e) && e.active && <Pill tone="bad">grave</Pill>}
        {mine && <Pill tone="warn">te afecta</Pill>}
        <span className="spacer" />
        <span className="dim" style={{ fontSize: 11.5 }}>{e.scopeLabel}</span>
        <button className="link" onClick={fly} title="Ver en el globo">⌖ globo</button>
      </div>
      <div className="dim" style={{ fontSize: 11.5, marginTop: 3 }}>
        {fmtDate(e.start)}{e.end.year !== e.start.year || e.end.month !== e.start.month || e.end.day !== e.start.day ? ` → ${fmtDate(e.end)}` : ''}
        {e.active ? (e.daysLeft > 3000 ? ' · permanente' : ` · quedan ${daysText(e.daysLeft)}`) : ' · terminado'}
      </div>
      {e.text && <div style={{ fontSize: 12.5, marginTop: 4 }}>{e.text}</div>}
      {e.effects.length > 0 && <ul>{e.effects.map((t, i) => <li key={i}>{t}</li>)}</ul>}
      {e.damage && <div style={{ fontSize: 12, marginTop: 4, color: 'var(--bad)' }}>Daños: {e.damage.plants} planta(s) u obra(s), {fmtMoney(e.damage.costUsd)}</div>}
    </div>
  );
}

export function WorldPanel() {
  const w = useUi((s) => s.views?.power?.world);
  const countries = useUi((s) => s.views?.business?.countries ?? []);
  const year = useUi((s) => (s.game ? currentDate(s.game).year : 2026));
  const myCountries = useUi((s) => s.game?.projects.filter((p) => p.stage !== 'vendido' && p.stage !== 'desmantelado' && p.stage !== 'abandonado').map((p) => p.countryCode).join(',') ?? '');
  const [tab, setTab] = useState<Tab>('eventos');
  const [iso, setIso] = useState('');
  const close = () => ui.openWindow(null);
  if (!w) return <Window title="Mundo" onClose={close} testId="world-panel"><Empty>Cargando…</Empty></Window>;
  const mine = new Set(myCountries.split(',').filter(Boolean));
  const affects = (e: WorldEventView) => !e.countries || e.countries.some((c) => mine.has(c));
  const filt = (e: WorldEventView) => !iso || !e.countries || e.countries.includes(iso);
  const active = w.active.filter(filt);
  const past = w.past.filter(filt).slice(0, 40);
  const grave = w.active.filter(isGrave);
  const elections = w.regulation.filter((r) => r.nextElection).sort((a, b) => (a.nextElection! - b.nextElection!) || (elMonth(a.countryCode) - elMonth(b.countryCode)));
  const next = elections[0];
  const changed = w.regulation.filter((r) => r.carbonAddUsdT || r.permitTimeFactor !== 1 || r.taxCreditFactor !== 1);
  const withData = countries.filter((c) => gameData.simData.countries[c.iso3]);

  return (
    <Window title="Mundo" subtitle="Eventos globales y por país, gobiernos, regulación y clima: afectan a todas las empresas por igual" width={1240} onClose={close} testId="world-panel">
      <div className="stats-row">
        <Stat label="Eventos activos" value={w.active.length} hint={`${w.past.length} terminados`} />
        <Stat label="Graves" value={grave.length} tone={grave.length ? 'bad' : 'good'} hint={grave.map((e) => e.name).slice(0, 2).join(', ') || 'ninguno'} />
        <Stat label="Clima (ENSO)" value={w.climate.ensoLabel} tone={w.climate.enso === 'nino' ? 'warn' : undefined} hint="hidrología del año" />
        <Stat label="Próxima elección" value={next ? next.countryName : '—'} hint={next ? `${MONTHS_SHORT[elMonth(next.countryCode) - 1]} ${next.nextElection}` : ''} />
        <Stat label="Regulación modificada" value={changed.length} hint="países con cambios vigentes" />
        <Stat label="Avances tecnológicos" value={w.techCost.length} hint="costos permanentes" tone={w.techCost.length ? 'good' : undefined} />
      </div>
      <Tabs<Tab> tabs={[{ id: 'eventos', label: `Eventos (${w.active.length})` }, { id: 'gobiernos', label: 'Gobiernos y regulación' }, { id: 'avances', label: 'Avances y costos' }]} value={tab} onChange={setTab} />
      <div className="window-body scroll">
        {tab === 'eventos' && (
          <>
            <div className="row" style={{ marginBottom: 8 }}>
              <span className="dim">País:</span>
              <select value={iso} onChange={(e) => setIso(e.target.value)} data-testid="world-country">
                <option value="">Todos</option>
                {withData.map((c) => <option key={c.iso3} value={c.iso3}>{c.nombre}</option>)}
              </select>
              <span className="spacer" />
              <span className="dim" style={{ fontSize: 11.5 }}>Los eventos regionales se resaltan en el globo mientras duran.</span>
            </div>
            <div className="grid2">
              <Section title={`Activos (${active.length})`}>
                {active.length === 0 ? <Empty>Sin eventos activos{iso ? ' en este país' : ''}.</Empty> : active.map((e) => <EventCard key={e.uid} e={e} mine={affects(e)} />)}
              </Section>
              <Section title={`Pasados (${w.past.length})`}>
                {past.length === 0 ? <Empty>Aún no terminó ningún evento.</Empty> : past.map((e) => <EventCard key={`p${e.uid}`} e={e} />)}
              </Section>
            </div>
          </>
        )}
        {tab === 'gobiernos' && (
          <table className="grid-table" data-testid="world-regulation">
            <thead><tr><th>País</th><th>Gobierno</th><th className="num">Próxima elección</th><th className="num">Carbono adicional</th><th className="num">Plazo de permisos</th><th className="num">Crédito fiscal</th><th /></tr></thead>
            <tbody>
              {w.regulation.map((r) => (
                <tr key={r.countryCode} className={mine.has(r.countryCode) ? 'me' : ''}>
                  <td><b>{r.countryName}</b>{mine.has(r.countryCode) && <span className="dim"> · tus proyectos</span>}</td>
                  <td>{r.governmentName ?? <span className="dim">Sin cambios</span>}</td>
                  <td className="num mono">{r.nextElection ? `${MONTHS_SHORT[elMonth(r.countryCode) - 1]} ${r.nextElection}` : '—'}{r.nextElection && r.nextElection <= year + 1 ? <> <Pill tone="warn">pronto</Pill></> : null}</td>
                  <td className="num mono" style={{ color: r.carbonAddUsdT > 0 ? 'var(--warn)' : r.carbonAddUsdT < 0 ? 'var(--good)' : undefined }}>{r.carbonAddUsdT ? `${r.carbonAddUsdT > 0 ? '+' : ''}${fmtNum(r.carbonAddUsdT, 0)} US$/t` : '—'}</td>
                  <td className="num mono" style={{ color: r.permitTimeFactor > 1 ? 'var(--bad)' : r.permitTimeFactor < 1 ? 'var(--good)' : undefined }}>{r.permitTimeFactor !== 1 ? `×${fmtNum(r.permitTimeFactor, 2)}` : '—'}</td>
                  <td className="num mono" style={{ color: r.taxCreditFactor < 1 ? 'var(--bad)' : r.taxCreditFactor > 1 ? 'var(--good)' : undefined }}>{r.taxCreditFactor !== 1 ? `×${fmtNum(r.taxCreditFactor, 2)}` : '—'}</td>
                  <td className="num"><button className="link" onClick={() => ui.openCountry(r.countryCode)}>Ficha →</button></td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
        {tab === 'avances' && (
          w.techCost.length === 0 ? <Empty>Sin avances tecnológicos todavía. Cuando ocurren bajan de forma permanente el CAPEX de una tecnología para todas las empresas.</Empty> : (
            <table className="grid-table" style={{ maxWidth: 620 }}>
              <thead><tr><th>Tecnología</th><th className="num">Factor de costo</th><th className="num">Cambio</th></tr></thead>
              <tbody>{w.techCost.map((t) => <tr key={t.techId}><td>{techName(t.techId)}</td><td className="num mono">×{fmtNum(t.factor, 3)}</td><td className="num mono" style={{ color: t.factor < 1 ? 'var(--good)' : 'var(--bad)' }}>{t.factor < 1 ? '−' : '+'}{fmtNum(Math.abs(t.factor - 1) * 100, 0)} %</td></tr>)}</tbody>
            </table>
          )
        )}
      </div>
    </Window>
  );
}

const elMonth = (iso: string) => gameData.simData.power?.paises[iso]?.elecciones?.mes ?? 1;
