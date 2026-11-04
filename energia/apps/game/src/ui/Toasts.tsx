import { useUi } from './store';

const COLORS = { info: 'var(--info)', good: 'var(--good)', warn: 'var(--warn)', bad: 'var(--bad)' };

export function Toasts() {
  const toasts = useUi((s) => s.toasts);
  return (
    <div style={{ position: 'absolute', bottom: 16, left: '50%', transform: 'translateX(-50%)', display: 'grid', gap: 6, pointerEvents: 'none' }}>
      {toasts.map((t) => (
        <div key={t.id} className="panel" style={{ padding: '8px 14px', borderLeft: `3px solid ${COLORS[t.kind]}` }}>{t.text}</div>
      ))}
    </div>
  );
}
