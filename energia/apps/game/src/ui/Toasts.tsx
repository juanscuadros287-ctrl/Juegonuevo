import { ui, useUi } from './store';

const COLORS = { info: 'var(--info)', good: 'var(--good)', warn: 'var(--warn)', bad: 'var(--bad)' };

export function Toasts() {
  const toasts = useUi((s) => s.toasts);
  return (
    <div className="toasts">
      {toasts.map((t) => (
        <div key={t.id} className={`panel toast ${t.projectId ? 'clickable' : ''}`} style={{ borderLeft: `3px solid ${COLORS[t.kind]}` }}
          onClick={() => t.projectId && ui.openProject(t.projectId)} title={t.projectId ? 'Abrir el proyecto' : undefined}>
          {t.text}
        </div>
      ))}
    </div>
  );
}
