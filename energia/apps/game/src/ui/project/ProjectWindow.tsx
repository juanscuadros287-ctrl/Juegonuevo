import { useState } from 'react';
import type { ProjectDetail, ViabilityResult } from '@voltaje/sim';
import { sim } from '../../worker/client';
import { getGlobe } from '../../globe/GlobeView';
import { ui, useUi } from '../store';
import { ConfirmButton, Empty, Pill, StageBadge, Tabs, Window } from '../common';
import { fmtLat, fmtLon, fmtMoney, fmtNum, fmtPct } from '../format';
import { SummaryTab } from './SummaryTab';
import { StudiesTab } from './StudiesTab';
import { PermitsTab } from './PermitsTab';
import { CommercialTab } from './CommercialTab';
import { FinancingTab } from './FinancingTab';
import { ConstructionTab } from './ConstructionTab';
import { OperationTab } from './OperationTab';
import { DispatchTab } from './DispatchTab';
import { InsuranceTab } from './InsuranceTab';

type TabId = 'resumen' | 'estudios' | 'permisos' | 'comercial' | 'financiacion' | 'construccion' | 'operacion' | 'despacho' | 'seguro';

export function cmd(c: Parameters<typeof sim.command>[0]) { sim.command(c); }

export function ProjectWindow() {
  const id = useUi((s) => s.projectId);
  const tab = useUi((s) => s.projectTab) as TabId;
  const d = useUi((s) => (s.views?.detail?.summary.id === s.projectId ? s.views?.detail : null));
  const [viab, setViab] = useState<{ id: string; tick: number; result?: ViabilityResult; error?: string; busy: boolean } | null>(null);
  const tick = useUi((s) => s.game?.tick ?? 0);
  const close = () => ui.openWindow(null);
  if (!id) return null;
  if (!d) return <Window title="Proyecto" onClose={close}><Empty>Cargando…</Empty></Window>;
  const s = d.summary;
  const pid = s.id;
  const openFindings = d.findings.filter((f) => f.status === 'abierto').length;
  const pendingStudies = d.studies.filter((x) => x.required && x.status === 'disponible').length;
  const pendingPermits = d.permits.filter((x) => x.status === 'disponible' || x.status === 'rechazado').length;
  const dot = (n: number, tone = 'var(--accent)') => (n > 0 ? <span className="tab-dot" style={{ background: tone }}>{n}</span> : null);
  const tabs: { id: TabId; label: string; badge?: React.ReactNode }[] = [
    { id: 'resumen', label: 'Resumen' },
    { id: 'estudios', label: 'Estudios', badge: openFindings ? dot(openFindings, 'var(--bad)') : dot(pendingStudies) },
    { id: 'permisos', label: 'Permisos', badge: dot(pendingPermits) },
    { id: 'comercial', label: 'Comercial' },
    { id: 'financiacion', label: 'Financiación' },
    { id: 'construccion', label: 'Construcción' },
    { id: 'operacion', label: 'Operación' },
  ];
  // Fase 5: despacho y mercado solo en operación; seguro desde la obra
  const raw = ui.get().game?.projects.find((p) => p.id === pid);
  if (d.operation) tabs.push({ id: 'despacho', label: 'Despacho y venta', badge: raw?.codBlocked ? dot(1, 'var(--bad)') : undefined });
  if (d.operation || d.construction) tabs.push({ id: 'seguro', label: 'Seguro', badge: raw && !raw.insurance ? <span className="tab-dot" style={{ background: 'var(--text-dim)' }}>!</span> : undefined });
  const runViability = async () => {
    setViab({ id: pid, tick, busy: true });
    const r = await sim.viability(pid, 500);
    setViab({ id: pid, tick, busy: false, result: r.result, error: r.error });
  };
  const inSale = d.summary.nextStep === 'En venta';

  return (
    <Window
      width={1180}
      testId="project-window"
      onClose={close}
      title={<span className="row" style={{ gap: 10 }}><button onClick={() => ui.openWindow('projects')} title="Volver a la lista">←</button>{s.name} <StageBadge stage={s.stage} label={s.stageLabel} /></span>}
      subtitle={<>{d.techName} · {fmtNum(s.mw, 0)} MW · {d.countryName} · <button className="link" onClick={() => getGlobe()?.flyTo(s.lat, s.lon, 1.25)}>{fmtLat(s.lat)} {fmtLon(s.lon)}</button> · {s.nextStep}</>}
      actions={s.active && (
        <div className="row" style={{ gap: 6 }}>
          <button className="primary" data-testid="viability" onClick={runViability} disabled={viab?.busy}>Comprobar viabilidad</button>
          {!inSale && <ConfirmButton confirm={`¿Vender por ~${fmtMoney(d.saleValueUsd)}?`} onConfirm={() => cmd({ type: 'sellProject', projectId: pid })}>Vender</ConfirmButton>}
          {d.operation
            ? <ConfirmButton className="danger" confirm="¿Desmantelar la planta?" onConfirm={() => cmd({ type: 'decommissionProject', projectId: pid })}>Desmantelar</ConfirmButton>
            : <ConfirmButton className="danger" confirm={`Se castigan ${fmtMoney(d.costs.incurredUsd.total)}`} onConfirm={() => cmd({ type: 'abandonProject', projectId: pid })}>Abandonar</ConfirmButton>}
        </div>
      )}
    >
      <Tabs tabs={tabs} value={tab} onChange={(t) => ui.setProjectTab(t)} />
      <div className="window-body scroll">
        {viab && viab.id === pid && <ViabilityCard v={viab} d={d} onClose={() => setViab(null)} stale={viab.tick !== tick} />}
        {tab === 'resumen' && <SummaryTab d={d} />}
        {tab === 'estudios' && <StudiesTab d={d} />}
        {tab === 'permisos' && <PermitsTab d={d} />}
        {tab === 'comercial' && <CommercialTab d={d} />}
        {tab === 'financiacion' && <FinancingTab d={d} />}
        {tab === 'construccion' && <ConstructionTab d={d} />}
        {tab === 'operacion' && <OperationTab d={d} />}
        {tab === 'despacho' && <DispatchTab d={d} />}
        {tab === 'seguro' && <InsuranceTab d={d} />}
      </div>
    </Window>
  );
}

const FAILURE_LABELS: Record<string, string> = {
  hallazgo: 'Hallazgo de un estudio sin solución',
  permiso: 'Permiso rechazado',
  financiamiento: 'Sin cierre financiero',
};

function ViabilityCard({ v, d, onClose, stale }: { v: { busy: boolean; result?: ViabilityResult; error?: string }; d: ProjectDetail; onClose: () => void; stale: boolean }) {
  const r = v.result;
  const fails = r ? Object.entries(r.failures).sort((a, b) => b[1] - a[1]) : [];
  return (
    <div className="viability panel" data-testid="viability-card">
      <div className="row" style={{ marginBottom: 8 }}>
        <h3 style={{ margin: 0 }}>Comprobación de viabilidad (Monte Carlo{r ? `, ${r.runs} corridas` : ''})</h3>
        {stale && <Pill tone="dim">calculada en otra fecha</Pill>}
        <span className="spacer" />
        <button onClick={onClose} title="Cerrar">✕</button>
      </div>
      {v.busy && <div className="dim">Simulando el resto del ciclo del proyecto…</div>}
      {v.error && <div className="notice bad">{v.error}</div>}
      {r && (
        <div className="viab-grid">
          <div className="viab-big">
            <div className="stat-label">Prob. de llegar a operación</div>
            <div className="mono" style={{ fontSize: 34, fontWeight: 800, color: r.probCod >= 0.6 ? 'var(--good)' : r.probCod >= 0.35 ? 'var(--warn)' : 'var(--bad)' }}>{fmtPct(r.probCod, 0)}</div>
            <div className="dim" style={{ fontSize: 11 }}>Estimación del motor sin simular: {fmtPct(d.successProbability, 0)}</div>
            <div className="dim" style={{ fontSize: 11 }}>Precio supuesto: {r.ppaChannelId ? `PPA (${d.ppa?.channelName ?? r.ppaChannelId})` : 'spot'}</div>
          </div>
          <table className="kv"><tbody>
            <tr><td>Meses hasta operar (P50 / P90)</td><td>{r.monthsToCodP50 !== null ? `${fmtNum(r.monthsToCodP50, 0)} / ${fmtNum(r.monthsToCodP90 ?? 0, 0)}` : '—'}</td></tr>
            <tr><td>Costo por gastar (P50 / P90)</td><td>{fmtMoney(r.costP50Usd)} / {fmtMoney(r.costP90Usd)}</td></tr>
            <tr><td>TIR del capital (P50 / P10)</td><td>{fmtPct(r.irrEquityP50)} / {fmtPct(r.irrEquityP10)}</td></tr>
            <tr><td>VAN esperado del capital (con riesgo)</td><td style={{ color: r.npvExpectedUsd < 0 ? 'var(--bad)' : 'var(--good)' }}>{fmtMoney(r.npvExpectedUsd)}</td></tr>
            <tr><td>VAN si todo sale bien (misma base)</td><td>{fmtMoney(r.npvDeterministicUsd)}</td></tr>
            <tr><td>Costo del riesgo</td><td style={{ color: r.npvDeterministicUsd - r.npvExpectedUsd > 0 ? 'var(--warn)' : undefined }}>{fmtMoney(r.npvDeterministicUsd - r.npvExpectedUsd)}</td></tr>
          </tbody></table>
          <div>
            <div className="stat-label" style={{ marginBottom: 4 }}>Principales causas de fracaso</div>
            {fails.length === 0 ? <div className="dim">Ninguna corrida fracasó.</div> : fails.slice(0, 5).map(([k, n]) => (
              <div key={k} className="row" style={{ gap: 6, fontSize: 12 }}>
                <span style={{ flex: 1 }}>{FAILURE_LABELS[k] ?? k}</span>
                <span className="mono dim">{fmtPct(n / r.runs, 0)}</span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
