import { useState } from 'react';
import type { Severity } from '@voltaje/sim';
import { ui, useUi } from './store';
import { Empty, Window } from './common';

const SEV: Record<Severity, { color: string; label: string }> = {
  info: { color: 'var(--info)', label: 'Información' },
  bueno: { color: 'var(--good)', label: 'Buenas noticias' },
  malo: { color: 'var(--bad)', label: 'Problemas' },
};

export function EventLog() {
  const log = useUi((s) => s.log);
  const projects = useUi((s) => s.views?.projects ?? []);
  const [sev, setSev] = useState<Severity | 'todos'>('todos');
  const [pid, setPid] = useState<string>('');
  const list = log.filter((e) => (sev === 'todos' || e.severity === sev) && (!pid || e.projectId === pid)).slice().reverse();
  const name = (id?: string) => projects.find((p) => p.id === id)?.name;

  return (
    <Window title="Registro de eventos" subtitle={`${log.length} eventos`} width={900} onClose={() => ui.openWindow(null)} testId="event-log">
      <div className="row" style={{ gap: 4, marginBottom: 10, flexWrap: 'wrap' }}>
        <button className={sev === 'todos' ? 'active' : ''} onClick={() => setSev('todos')}>Todos</button>
        {(Object.keys(SEV) as Severity[]).map((k) => (
          <button key={k} className={sev === k ? 'active' : ''} onClick={() => setSev(k)}><span style={{ color: sev === k ? 'inherit' : SEV[k].color }}>●</span> {SEV[k].label}</button>
        ))}
        <span className="spacer" />
        <select value={pid} onChange={(e) => setPid(e.target.value)}>
          <option value="">Todos los proyectos</option>
          {projects.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
        </select>
      </div>
      <div className="window-body scroll" style={{ paddingTop: 0 }}>
        {list.length === 0 ? <Empty>Sin eventos todavía.</Empty> : list.map((e) => (
          <div key={e.id} className={`log-row ${e.projectId ? 'clickable' : ''}`} onClick={() => e.projectId && ui.openProject(e.projectId)}>
            <span className="log-dot" style={{ background: SEV[e.severity].color }} />
            <span className="mono dim log-date">{e.date}</span>
            <span style={{ flex: 1 }}>{e.text}</span>
            {e.projectId && <span className="dim log-project ellipsis">{name(e.projectId) ?? e.projectId}</span>}
          </div>
        ))}
      </div>
    </Window>
  );
}
