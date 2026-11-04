import { gameData } from '@voltaje/data';
import { rampCss } from '../globe/textures';
import { ui, useUi } from './store';
import { fmtNum } from './format';

export function LayerPanel() {
  const layerId = useUi((s) => s.layerId);
  const opacity = useUi((s) => s.layerOpacity);
  const active = gameData.layers.find((l) => l.id === layerId);

  return (
    <div className="panel" style={{ position: 'absolute', top: 72, left: 12, width: 250, padding: 12 }}>
      <h3>Capas de recursos</h3>
      <div style={{ display: 'grid', gap: 3 }}>
        <button className={!layerId ? 'active' : ''} style={{ textAlign: 'left' }} onClick={() => ui.set({ layerId: null })}>Mapa base</button>
        {gameData.layers.map((l) => (
          <button key={l.id} data-layer={l.id} className={layerId === l.id ? 'active' : ''} style={{ textAlign: 'left' }} onClick={() => ui.set({ layerId: l.id })}>
            {l.nombre}
          </button>
        ))}
      </div>
      {active && (
        <div style={{ marginTop: 12 }}>
          <div style={{ height: 10, borderRadius: 5, background: rampCss(active) }} />
          <div className="row dim mono" style={{ fontSize: 11, marginTop: 3 }}>
            <span>{fmtNum(active.rango[0])}</span><span className="spacer" /><span>{active.unidad}</span><span className="spacer" /><span>{fmtNum(active.rango[1])}</span>
          </div>
          {active.tecnologias.length > 0 && <div className="dim" style={{ fontSize: 11, marginTop: 6 }}>Para: {active.tecnologias.join(', ')}</div>}
          <div className="row" style={{ marginTop: 8 }}>
            <span className="dim" style={{ fontSize: 11 }}>Opacidad</span>
            <input type="range" min={0.2} max={1} step={0.05} value={opacity} onChange={(e) => ui.set({ layerOpacity: +e.target.value })} />
          </div>
        </div>
      )}
      <div className="dim" style={{ fontSize: 11, marginTop: 10 }}>Clic en el mapa para ver una zona. Rueda o pellizco para acercar.</div>
    </div>
  );
}
