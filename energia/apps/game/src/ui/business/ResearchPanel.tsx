import { useEffect, useMemo, useState } from 'react';
import type { ResearchNodeView, ResearchTreeView } from '@voltaje/sim';
import { sim } from '../../worker/client';
import { ui, useUi } from '../store';
import { Bar, ConfirmButton, Empty, Pill, Stat, Window } from '../common';
import { fmtMoney, fmtNum, fmtPct } from '../format';

const NODE_W = 182, NODE_H = 58, GAP_X = 46, GAP_Y = 10, LANE_HEAD = 24, LANE_GAP = 14, LEFT = 8;

const STATUS: Record<ResearchNodeView['status'], { label: string; tone: 'good' | 'bad' | 'warn' | 'info' | 'dim'; color: string }> = {
  completado: { label: 'Completado', tone: 'good', color: '#4ade80' },
  en_curso: { label: 'En curso', tone: 'warn', color: '#ffcb3d' },
  en_cola: { label: 'En cola', tone: 'info', color: '#60a5fa' },
  disponible: { label: 'Disponible', tone: 'info', color: '#e6eef7' },
  bloqueado: { label: 'Bloqueado', tone: 'dim', color: '#64748b' },
};

const BRANCH_ICON: Record<string, string> = { tecnologias: '⚡', estudios: '⌖', mercados: '◍', contratos: '✎', eficiencia: '⚙' };

interface Placed { n: ResearchNodeView; x: number; y: number }

/**
 * Disposición del árbol: carriles por rama (filas) y columnas por profundidad (prerrequisitos a la izquierda).
 * Las hojas de columnas llenas se corren a columnas posteriores con espacio para que los carriles queden bajos.
 */
function layout(t: ResearchTreeView) {
  const byId = new Map(t.nodes.map((n) => [n.id, n]));
  const depth = new Map<string, number>();
  const d = (id: string, seen = new Set<string>()): number => {
    if (depth.has(id)) return depth.get(id)!;
    if (seen.has(id)) return 0;
    seen.add(id);
    const n = byId.get(id);
    const v = n && n.requires.length ? 1 + Math.max(...n.requires.map((r) => d(r.id, seen))) : 0;
    depth.set(id, v);
    return v;
  };
  t.nodes.forEach((n) => d(n.id));
  const cols = 1 + Math.max(0, ...depth.values());
  const hasChildren = new Set(t.nodes.flatMap((n) => n.requires.map((r) => r.id)));
  const placed = new Map<string, Placed>();
  let y = 0;
  const lanes: { id: string; label: string; y: number; h: number }[] = [];
  for (const b of t.branches) {
    const nodes = t.nodes.filter((n) => n.rama === b.id);
    if (!nodes.length) continue;
    const col: ResearchNodeView[][] = Array.from({ length: cols }, () => []);
    for (const n of nodes) col[depth.get(n.id)!].push(n);
    const target = Math.max(2, Math.ceil(nodes.length / cols));
    for (let c = 0; c < cols; c++) {
      while (col[c].length > target) {
        const leaf = col[c].findIndex((n) => !hasChildren.has(n.id));
        let dest = -1;
        for (let k = c + 1; k < cols; k++) if (col[k].length < target && (dest < 0 || col[k].length < col[dest].length)) dest = k;
        if (leaf < 0 || dest < 0) break;
        col[dest].push(...col[c].splice(leaf, 1));
      }
    }
    const rows = Math.max(...col.map((x) => x.length));
    const top = y + LANE_HEAD;
    col.forEach((list, c) => list.forEach((n, i) => placed.set(n.id, { n, x: LEFT + c * (NODE_W + GAP_X), y: top + i * (NODE_H + GAP_Y) })));
    const h = LANE_HEAD + rows * (NODE_H + GAP_Y);
    lanes.push({ id: b.id, label: b.label, y, h });
    y += h + LANE_GAP;
  }
  return { placed, lanes, width: LEFT + cols * (NODE_W + GAP_X) - GAP_X + 8, height: y };
}

export function ResearchPanel() {
  const t = useUi((s) => s.views?.business?.research);
  const pick = useUi((s) => s.pick.research);
  const cash = useUi((s) => s.game?.company.cashUsd ?? 0);
  const L = useMemo(() => (t ? layout(t) : null), [t?.nodes.length]);
  if (!t || !L) return <Window title="Investigación y desarrollo" onClose={() => ui.openWindow(null)} testId="research-panel"><Empty>Cargando…</Empty></Window>;
  const sel = t.nodes.find((n) => n.id === pick) ?? t.nodes.find((n) => n.id === t.active?.nodeId) ?? t.nodes.find((n) => n.status === 'disponible');
  const done = t.nodes.filter((n) => n.status === 'completado' && !n.initial).length;
  const choose = (id: string) => ui.set((s) => ({ pick: { ...s.pick, research: id } }));

  return (
    <Window title="Investigación y desarrollo" subtitle="Tecnologías, estudios, mercados, contratos y mejoras de eficiencia" width={1320} onClose={() => ui.openWindow(null)} testId="research-panel">
      <div className="stats-row">
        <Stat label="Investigando" value={t.active ? t.active.nombre : 'Nada'} hint={t.active ? `${fmtPct(t.active.progress, 0)} · ${t.active.etaMonths !== null ? `~${fmtNum(t.active.etaMonths, 1)} meses` : 'detenida: sin presupuesto'}` : 'elige un nodo disponible'} tone={t.active ? undefined : 'warn'} />
        <Stat label="En cola" value={t.queue.length} />
        <Stat label="Presupuesto mensual" value={fmtMoney(t.budgetUsdMonth)} hint="se paga al cierre del mes" />
        <Stat label="Completados" value={`${done} / ${t.nodes.filter((n) => !n.initial).length}`} />
        <Stat label="Gastado en I+D" value={fmtMoney(t.totalSpentUsd)} />
      </div>
      <div className="window-body" style={{ display: 'flex', gap: 14, minHeight: 0, overflow: 'hidden' }}>
        <div className="scroll research-scroll" style={{ flex: 1, minWidth: 0 }}>
          <div className="research-tree" style={{ width: L.width, height: L.height }} data-testid="research-tree">
            {L.lanes.map((l) => (
              <div key={l.id} className="lane" style={{ top: l.y, height: l.h }}>
                <div className="lane-head">{BRANCH_ICON[l.id]} {l.label}</div>
              </div>
            ))}
            <svg className="research-links" width={L.width} height={L.height}>
              {[...L.placed.values()].flatMap((p) => p.n.requires.map((r) => {
                const a = L.placed.get(r.id);
                if (!a) return null;
                const x1 = a.x + NODE_W, y1 = a.y + NODE_H / 2, x2 = p.x, y2 = p.y + NODE_H / 2;
                const mx = (x1 + x2) / 2;
                const hot = sel && (sel.id === p.n.id || sel.id === r.id);
                const c = r.done ? 'rgba(74,222,128,.22)' : 'rgba(140,180,220,.35)';
                return <path key={`${r.id}-${p.n.id}`} d={`M${x1},${y1} C${mx},${y1} ${mx},${y2} ${x2},${y2}`} stroke={hot ? '#ffcb3d' : c} strokeWidth={hot ? 2.2 : 1.2} fill="none" strokeDasharray={r.done ? undefined : '4 3'} />;
              }))}
            </svg>
            {[...L.placed.values()].map(({ n, x, y }) => (
              <button key={n.id} className={`rnode ${n.status} ${sel?.id === n.id ? 'sel' : ''}`} style={{ left: x, top: y, width: NODE_W, height: NODE_H }} onClick={() => choose(n.id)} data-node={n.id}
                title={`${n.nombre} — ${STATUS[n.status].label}`}>
                <div className="row" style={{ gap: 5 }}>
                  <span className="rnode-dot" style={{ background: STATUS[n.status].color }} />
                  <span className="rnode-name">{n.nombre}</span>
                </div>
                <div className="rnode-meta mono">
                  {n.initial ? 'inicial' : `${fmtMoney(n.costUsd)} · ${n.months} m`}
                  {n.modelPhase ? <span className="rnode-phase">F{n.modelPhase}</span> : null}
                  {n.status === 'en_cola' && <span className="rnode-phase" style={{ color: 'var(--info)' }}>#{t.queue.indexOf(n.id) + 1}</span>}
                </div>
                {(n.status === 'en_curso' || (n.progress > 0 && n.status !== 'completado')) && <div className="rnode-bar"><div style={{ width: `${n.progress * 100}%` }} /></div>}
              </button>
            ))}
          </div>
        </div>
        <div className="side-card scroll" style={{ width: 340 }}>
          <Budget t={t} cash={cash} />
          {sel && <NodeDetail n={sel} t={t} />}
          {t.queue.length > 0 && (
            <>
              <div className="stat-label" style={{ margin: '14px 0 4px' }}>Cola</div>
              {t.queue.map((id, i) => {
                const n = t.nodes.find((x) => x.id === id);
                return <div key={id} className="row queue-row" onClick={() => choose(id)}><span className="mono dim">{i + 1}.</span><span className="ellipsis" style={{ flex: 1 }}>{n?.nombre ?? id}</span><span className="mono dim">{n ? fmtMoney(n.costUsd) : ''}</span></div>;
              })}
            </>
          )}
        </div>
      </div>
    </Window>
  );
}

const BUDGETS = [0, 25_000, 50_000, 100_000, 150_000, 250_000];

function Budget({ t, cash }: { t: ResearchTreeView; cash: number }) {
  const [v, setV] = useState(t.budgetUsdMonth);
  useEffect(() => setV(t.budgetUsdMonth), [t.budgetUsdMonth]);
  return (
    <div>
      <div className="stat-label">Presupuesto mensual de I+D</div>
      <div className="row" style={{ gap: 4, flexWrap: 'wrap', margin: '6px 0' }}>
        {BUDGETS.map((b) => (
          <button key={b} className={v === b ? 'active' : ''} style={{ padding: '4px 8px' }} data-budget={b}
            onClick={() => { setV(b); sim.command({ type: 'setResearchBudget', usdPerMonth: b }); }}>{b ? fmtMoney(b).replace('US$ ', '') : '0'}</button>
        ))}
      </div>
      <div className="hint">El avance mensual es el menor entre el ritmo máximo del nodo y presupuesto ÷ costo. Sin presupuesto o sin caja, la investigación se detiene.{cash < t.budgetUsdMonth * 3 && t.budgetUsdMonth > 0 ? <span style={{ color: 'var(--warn)' }}> Tu caja cubre menos de 3 meses de este gasto.</span> : null}</div>
    </div>
  );
}

function NodeDetail({ n, t }: { n: ResearchNodeView; t: ResearchTreeView }) {
  const st = STATUS[n.status];
  const busy = !!t.active;
  return (
    <div style={{ marginTop: 14 }} data-testid="research-node">
      <div className="row" style={{ alignItems: 'flex-start' }}>
        <div style={{ fontSize: 15, fontWeight: 700, flex: 1 }}>{n.nombre}</div>
        <Pill tone={st.tone}>{st.label}</Pill>
      </div>
      <div className="dim" style={{ fontSize: 11.5, margin: '2px 0 8px' }}>{n.ramaLabel}</div>
      <div style={{ fontSize: 12.5 }}>{n.descripcion}</div>
      <div className="effects">{n.effectsText || 'Sin efectos directos (abre otras ramas).'}</div>
      {n.modelPhase && <div className="notice warn" style={{ fontSize: 12 }}>Se puede investigar, pero lo que desbloquea se podrá construir o usar desde la Fase {n.modelPhase}.</div>}
      <table className="kv"><tbody>
        <tr><td>Costo</td><td>{fmtMoney(n.costUsd)}</td></tr>
        <tr><td>Duración mínima</td><td>{n.months} meses</td></tr>
        {n.status !== 'completado' && <tr><td>Con tu presupuesto</td><td>{n.monthsAtBudget === null ? <span style={{ color: 'var(--warn)' }}>sin presupuesto</span> : `${fmtNum(n.monthsAtBudget, 1)} meses`}</td></tr>}
        <tr><td>Prob. de contratiempo</td><td>{fmtPct(n.setbackProbability, 0)}</td></tr>
        {n.progress > 0 && n.status !== 'completado' && <tr><td>Avance</td><td>{fmtPct(n.progress, 0)}</td></tr>}
      </tbody></table>
      {n.status === 'en_curso' && <div style={{ margin: '6px 0' }}><Bar value={n.progress} color="var(--accent)" height={8} /></div>}
      {n.requires.length > 0 && (
        <>
          <div className="stat-label" style={{ margin: '10px 0 4px' }}>Requiere</div>
          {n.requires.map((r) => <div key={r.id} style={{ fontSize: 12 }}><span style={{ color: r.done ? 'var(--good)' : 'var(--bad)' }}>{r.done ? '✓' : '✕'}</span> {r.nombre}</div>)}
        </>
      )}
      {n.blockers.length > 0 && <div className="dim" style={{ fontSize: 11.5, marginTop: 6 }}>{n.blockers.join(' ')}</div>}
      <div className="row" style={{ gap: 6, marginTop: 12, flexWrap: 'wrap' }}>
        {n.status === 'disponible' && (
          <button className="primary" data-testid="research-start" onClick={() => sim.command({ type: 'startResearch', nodeId: n.id })}>{busy ? 'Poner en cola' : 'Investigar'}</button>
        )}
        {(n.status === 'bloqueado') && n.requires.every((r) => r.done || t.queue.includes(r.id) || t.active?.nodeId === r.id) && (
          <button onClick={() => sim.command({ type: 'queueResearch', nodeId: n.id })}>Encolar tras sus requisitos</button>
        )}
        {(n.status === 'en_curso' || n.status === 'en_cola') && (
          <ConfirmButton className="danger" confirm={n.status === 'en_curso' ? 'Se pierde lo gastado y la mitad del avance.' : '¿Quitar de la cola?'} onConfirm={() => sim.command({ type: 'cancelResearch', nodeId: n.id })}>
            {n.status === 'en_curso' ? 'Cancelar investigación' : 'Quitar de la cola'}
          </ConfirmButton>
        )}
      </div>
    </div>
  );
}
