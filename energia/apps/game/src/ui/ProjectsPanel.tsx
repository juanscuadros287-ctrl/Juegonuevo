import { useState } from 'react';
import type { ProjectStage, ProjectSummary } from '@voltaje/sim';
import { STAGE_COLORS } from '../globe/siteVisual';
import { getGlobe } from '../globe/GlobeView';
import { ui, useUi } from './store';
import { Bar, Empty, Pill, StageBadge, Stat, Window } from './common';
import { fmtMoney, fmtNum, fmtPct } from './format';

const ORDER: ProjectStage[] = ['identificado', 'estudios', 'permisos', 'cierre_financiero', 'construccion', 'puesta_en_marcha', 'operacion'];

/** Avance global del ciclo 0–1: etapa + avance de obra. */
export function lifecycleProgress(p: ProjectSummary): number {
  const i = ORDER.indexOf(p.stage);
  if (i < 0) return 0;
  if (p.stage === 'operacion') return 1;
  const within = p.stage === 'construccion' ? p.buildProgress : 0;
  return (i + within) / (ORDER.length - 1);
}

type Filter = 'activos' | 'desarrollo' | 'obra' | 'operacion' | 'cerrados' | 'todos';
const FILTERS: { id: Filter; label: string; test: (p: ProjectSummary) => boolean }[] = [
  { id: 'activos', label: 'Activos', test: (p) => p.active },
  { id: 'desarrollo', label: 'En desarrollo', test: (p) => ['identificado', 'estudios', 'permisos', 'cierre_financiero'].includes(p.stage) },
  { id: 'obra', label: 'En obra', test: (p) => p.stage === 'construccion' || p.stage === 'puesta_en_marcha' },
  { id: 'operacion', label: 'En operación', test: (p) => p.stage === 'operacion' },
  { id: 'cerrados', label: 'Cerrados', test: (p) => !p.active },
  { id: 'todos', label: 'Todos', test: () => true },
];

export function ProjectsPanel() {
  const projects = useUi((s) => s.views?.projects ?? []);
  const [filter, setFilter] = useState<Filter>('activos');
  const f = FILTERS.find((x) => x.id === filter)!;
  const list = projects.filter(f.test);
  const active = projects.filter((p) => p.active);
  const mwOp = active.filter((p) => p.stage === 'operacion').reduce((a, p) => a + p.mw, 0);
  const mwDev = active.filter((p) => p.stage !== 'operacion').reduce((a, p) => a + p.mw, 0);
  const devCost = active.reduce((a, p) => a + p.devCostUsd, 0);
  const alerts = active.reduce((a, p) => a + p.warnings.length, 0);

  return (
    <Window title="Proyectos" subtitle="Cartera de la empresa" onClose={() => ui.openWindow(null)} testId="projects-panel">
      <div className="stats-row">
        <Stat label="Proyectos activos" value={active.length} />
        <Stat label="En operación" value={`${fmtNum(mwOp, 0)} MW`} tone={mwOp > 0 ? 'good' : undefined} />
        <Stat label="En desarrollo y obra" value={`${fmtNum(mwDev, 0)} MW`} />
        <Stat label="Invertido en desarrollo" value={fmtMoney(devCost)} />
        <Stat label="Alertas" value={alerts} tone={alerts ? 'warn' : undefined} />
      </div>
      <div className="row" style={{ gap: 4, margin: '12px 0 8px', flexWrap: 'wrap' }}>
        {FILTERS.map((x) => (
          <button key={x.id} className={filter === x.id ? 'active' : ''} onClick={() => setFilter(x.id)}>
            {x.label} <span className="dim" style={{ color: filter === x.id ? 'inherit' : undefined }}>{projects.filter(x.test).length}</span>
          </button>
        ))}
      </div>
      {list.length === 0 ? (
        <Empty>{projects.length ? 'Ningún proyecto con este filtro.' : 'Aún no tienes proyectos. Elige una celda en tierra en Panamá y pulsa «Desarrollar proyecto aquí».'}</Empty>
      ) : (
        <div className="scroll table-wrap">
          <table className="grid-table">
            <thead>
              <tr>
                <th>Proyecto</th><th>Etapa</th><th style={{ width: 120 }}>Avance</th><th>Próximo paso</th>
                <th className="num">FC P50</th><th className="num">TIR capital</th><th className="num">VAN capital</th><th>Alertas</th>
              </tr>
            </thead>
            <tbody>
              {list.map((p) => (
                <tr key={p.id} className="clickable" data-project={p.id} onClick={() => { ui.openProject(p.id); getGlobe()?.flyTo(p.lat, p.lon, 1.3); }}>
                  <td>
                    <div style={{ fontWeight: 600 }}>{p.name}</div>
                    <div className="dim" style={{ fontSize: 11 }}>{p.techName} · {fmtNum(p.mw, 0)} MW</div>
                  </td>
                  <td><StageBadge stage={p.stage} label={p.stageLabel} /></td>
                  <td><Bar value={lifecycleProgress(p)} color={STAGE_COLORS[p.stage]} /></td>
                  <td className="ellipsis" style={{ maxWidth: 260 }} title={p.nextStep}>{p.nextStep}</td>
                  <td className="num mono">{p.active ? fmtPct(p.fcP50) : '—'}</td>
                  <td className="num mono" style={{ color: p.irrEquity !== null && p.irrEquity < 0.1 ? 'var(--warn)' : undefined }}>{p.active ? fmtPct(p.irrEquity) : '—'}</td>
                  <td className="num mono" style={{ color: p.npvEquityUsd < 0 ? 'var(--bad)' : undefined }}>{p.active ? fmtMoney(p.npvEquityUsd) : '—'}</td>
                  <td>{p.warnings.length ? p.warnings.map((w) => <Pill key={w} tone="warn">{w}</Pill>) : <span className="dim">—</span>}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </Window>
  );
}
