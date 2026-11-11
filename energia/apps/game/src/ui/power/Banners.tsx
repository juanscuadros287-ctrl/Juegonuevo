import { ui, useUi } from '../store';

/** Avisos grandes de eventos graves del mundo (huracán, conflicto, pandemia…). Clic → ventana Mundo. */
export function Banners() {
  const list = useUi((s) => s.banners);
  if (!list.length) return null;
  return (
    <div className="banners">
      {list.map((b) => (
        <div key={b.id} className="panel banner" data-testid="world-banner" onClick={() => { ui.set((s) => ({ banners: s.banners.filter((x) => x.id !== b.id) })); ui.openPanel('world'); }}>
          <span className="banner-icon" style={{ color: 'var(--bad)' }}>⚠</span>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div className="banner-title">{b.title}{b.scope ? <span className="dim" style={{ fontWeight: 400, fontSize: 12 }}> · {b.scope}</span> : null}</div>
            <div style={{ fontSize: 12.5, marginTop: 2 }}>{b.text}</div>
            <div className="dim" style={{ fontSize: 11, marginTop: 3 }}>Clic para ver los efectos en Mundo (W)</div>
          </div>
          <button onClick={(e) => { e.stopPropagation(); ui.set((s) => ({ banners: s.banners.filter((x) => x.id !== b.id) })); }} title="Cerrar">✕</button>
        </div>
      ))}
    </div>
  );
}
