import { useMemo } from 'react';
import type { PermitGraph, PermitGraphNode } from '@voltaje/sim';
import { fmtNum, fmtPct } from '../format';

const W = 214, H = 92, GX = 40, GY = 10;

/** ¿El permiso aplica a la tecnología y tamaño? (mismo criterio que `applies` del motor). */
export function permitApplies(n: PermitGraphNode, techId: string | null, mw: number): boolean {
  if (!techId) return true;
  if (n.techs && !n.techs.includes(techId)) return false;
  if (n.mwMin !== undefined && mw < n.mwMin) return false;
  if (n.mwMax !== undefined && mw >= n.mwMax) return false;
  return true;
}

/**
 * Grafo de permisos de un país: columnas por profundidad (requisitos a la izquierda), autoridad, duración y
 * probabilidad. Con una tecnología elegida se atenúan los que no aplican y se resalta la ruta crítica (base).
 */
export function PermitGraphView({ graph, techId, mw }: { graph: PermitGraph; techId: string | null; mw: number }) {
  const lay = useMemo(() => {
    const byId = new Map(graph.nodes.map((n) => [n.id, n]));
    const preds = new Map<string, string[]>();
    for (const e of graph.edges) preds.set(e.to, [...(preds.get(e.to) ?? []), e.from]);
    const depth = new Map<string, number>();
    const d = (id: string, guard = 0): number => {
      if (depth.has(id)) return depth.get(id)!;
      const ps = preds.get(id) ?? [];
      const v = ps.length && guard < 30 ? 1 + Math.max(...ps.map((p) => d(p, guard + 1))) : 0;
      depth.set(id, v);
      return v;
    };
    graph.nodes.forEach((n) => d(n.id));
    const cols: PermitGraphNode[][] = [];
    for (const n of graph.nodes) (cols[depth.get(n.id)!] ??= []).push(n);
    const pos = new Map<string, { x: number; y: number }>();
    cols.forEach((col, c) => col.forEach((n, r) => pos.set(n.id, { x: c * (W + GX), y: r * (H + GY) })));
    // ruta crítica con la duración base, solo entre los permisos que aplican
    const app = (id: string) => permitApplies(byId.get(id)!, techId, mw);
    const end = new Map<string, { t: number; prev: string | null }>();
    const fin = (id: string, guard = 0): { t: number; prev: string | null } => {
      if (end.has(id)) return end.get(id)!;
      let best: { t: number; prev: string | null } = { t: 0, prev: null };
      for (const p of preds.get(id) ?? []) if (app(p) && guard < 30) { const f = fin(p, guard + 1); if (f.t > best.t) best = { t: f.t, prev: p }; }
      const v = { t: best.t + byId.get(id)!.durationDays.base, prev: best.prev };
      end.set(id, v);
      return v;
    };
    const critical = new Set<string>();
    if (techId) {
      let last: string | null = null, lt = -1;
      for (const n of graph.nodes) if (app(n.id)) { const f = fin(n.id); if (f.t > lt) { lt = f.t; last = n.id; } }
      for (let id = last; id; id = end.get(id)?.prev ?? null) critical.add(id);
    }
    const width = cols.length * (W + GX) - GX;
    const height = Math.max(...cols.map((c) => c.length)) * (H + GY) - GY;
    return { pos, critical, width, height, cols: cols.length, app };
  }, [graph, techId, mw]);

  return (
    <div className="pgraph-wrap scroll-x" data-testid="permit-graph">
      <div className="pgraph" style={{ width: lay.width, height: lay.height + 18 }}>
        {Array.from({ length: lay.cols }, (_, c) => <div key={c} className="pgraph-col dim" style={{ left: c * (W + GX) }}>{c === 0 ? 'Sin requisitos previos' : `Paso ${c + 1}`}</div>)}
        <svg className="pgraph-links" width={lay.width} height={lay.height + 18}>
          <defs>
            <marker id="pg-arrow" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="6" markerHeight="6" orient="auto"><path d="M0,0 L8,4 L0,8 z" fill="rgba(140,180,220,.5)" /></marker>
            <marker id="pg-arrow-c" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="6" markerHeight="6" orient="auto"><path d="M0,0 L8,4 L0,8 z" fill="#ffcb3d" /></marker>
          </defs>
          {graph.edges.map((e, i) => {
            const a = lay.pos.get(e.from), b = lay.pos.get(e.to);
            if (!a || !b) return null;
            const crit = lay.critical.has(e.from) && lay.critical.has(e.to);
            const off = !lay.app(e.from) || !lay.app(e.to);
            const x1 = a.x + W, y1 = a.y + H / 2 + 18, x2 = b.x - 2, y2 = b.y + H / 2 + 18, mx = (x1 + x2) / 2;
            return <path key={i} d={`M${x1},${y1} C${mx},${y1} ${mx},${y2} ${x2},${y2}`} fill="none" stroke={crit ? '#ffcb3d' : 'rgba(140,180,220,.35)'} strokeWidth={crit ? 2.4 : 1.2} opacity={off ? 0.25 : 1} markerEnd={`url(#${crit ? 'pg-arrow-c' : 'pg-arrow'})`} />;
          })}
        </svg>
        {graph.nodes.map((n) => {
          const p = lay.pos.get(n.id)!;
          const crit = lay.critical.has(n.id);
          const off = !lay.app(n.id);
          const pr = n.approvalProbability;
          return (
            <div key={n.id} data-permit={n.id} className={`pnode ${crit ? 'crit' : ''} ${off ? 'off' : ''}`} style={{ left: p.x, top: p.y + 18, width: W, height: H }}
              title={`${n.nombre}\n${n.autoridad}\n${n.descripcion}${n.techs ? `\nSolo: ${n.techs.join(', ')}` : ''}${n.mwMin !== undefined || n.mwMax !== undefined ? `\nTamaño: ${n.mwMin ?? 0}–${n.mwMax ?? '∞'} MW` : ''}\nAprobado ${fmtPct(n.probs.aprobado, 0)} · info adicional ${fmtPct(n.probs.info_adicional, 0)} · rechazo ${fmtPct(n.probs.rechazado, 0)}${n.retryable ? ' (reintentable)' : ''}`}>
              <div className="pnode-name">{n.nombre}</div>
              <div className="pnode-auth ellipsis">{n.autoridad}</div>
              <div className="pnode-meta">
                <span className="mono">{n.durationDays.min === n.durationDays.max ? `${n.durationDays.base} d` : `${n.durationDays.min}–${n.durationDays.max} d`}</span>
                <span className="spacer" />
                <span className="mono" style={{ color: pr < 0.6 ? 'var(--bad)' : pr < 0.85 ? 'var(--warn)' : 'var(--good)' }}>{fmtPct(pr, 0)}</span>
              </div>
              <div className="probbar" title="aprobado / información adicional / rechazo">
                <div style={{ width: `${n.probs.aprobado * 100}%`, background: 'var(--good)' }} />
                <div style={{ width: `${n.probs.info_adicional * 100}%`, background: 'var(--warn)' }} />
                <div style={{ width: `${n.probs.rechazado * 100}%`, background: 'var(--bad)' }} />
              </div>
              {(n.techs || n.mwMin !== undefined || n.mwMax !== undefined) && <div className="pnode-tag">{n.techs ? `${n.techs.length} tec.` : ''}{n.mwMin !== undefined ? ` ≥${fmtNum(n.mwMin, 0)} MW` : ''}{n.mwMax !== undefined ? ` <${fmtNum(n.mwMax, 0)} MW` : ''}</div>}
            </div>
          );
        })}
      </div>
    </div>
  );
}
