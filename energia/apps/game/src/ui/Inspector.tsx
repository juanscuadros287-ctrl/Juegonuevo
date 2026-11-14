import { gameData, type LayerDef } from '@voltaje/data';
import type { World } from '../world/loadWorld';
import { getGlobe } from '../globe/GlobeView';
import { ui, useUi } from './store';
import { fmtCompact, fmtLat, fmtLon, fmtNum } from './format';
import { StageBadge } from './common';

const RATED = new Set(['ghi', 'dni', 'viento_tierra', 'viento_mar', 'geotermia', 'hidro', 'biomasa']);

function rating(layer: LayerDef, v: number): { text: string; color: string; score: number } {
  const t = (v - layer.rango[0]) / (layer.rango[1] - layer.rango[0]);
  if (t >= 0.72) return { text: 'Excelente', color: 'var(--good)', score: t };
  if (t >= 0.5) return { text: 'Bueno', color: '#a3e635', score: t };
  if (t >= 0.28) return { text: 'Medio', color: 'var(--warn)', score: t };
  return { text: 'Bajo', color: 'var(--text-dim)', score: t };
}

export function Inspector({ world }: { world: World }) {
  const sel = useUi((s) => s.selected);
  const layerId = useUi((s) => s.layerId);
  const countries = useUi((s) => s.views?.business?.countries);
  const projects = useUi((s) => s.views?.projects);
  if (!sel) return null;
  const cell = world.grid.cell(sel.lat, sel.lon);
  const where = cell.land ? 'tierra' : 'mar';
  const layers = gameData.layers.filter((l) => l.aplica === where && !(cell.land && cell.values.temperatura <= -29 && l.id !== 'temperatura'));
  const rated = layers.filter((l) => RATED.has(l.id)).map((l) => ({ l, r: rating(l, cell.values[l.id]) })).sort((a, b) => b.r.score - a.r.score);
  const best = rated.filter((x) => x.r.score >= 0.5);
  const country = cell.country;
  const cdata = country ? gameData.countries[country.code] : undefined;
  // en el mar: eólica marina frente a la costa de un país con datos
  const seaCountry = !cell.land ? world.grid.nearestCountry(cell.lat, cell.lon, 6)?.country : undefined;
  const devCountry = cell.land ? country : seaCountry;
  const canDevelop = !!devCountry && !!gameData.simData.countries[devCountry.code];
  const sheetCode = devCountry && gameData.simData.countries[devCountry.code] ? devCountry.code : null;
  const cmark = countries?.find((c) => c.iso3 === sheetCode);
  const half = world.grid.res / 2;
  const here = (projects ?? []).filter((p) => p.active && Math.abs(p.lat - cell.lat) <= half && Math.abs(p.lon - cell.lon) <= half);

  return (
    <div className="panel scroll" style={{ position: 'absolute', top: 72, right: 12, width: 320, maxHeight: 'calc(100% - 96px)', padding: 14 }} data-testid="inspector">
      <div className="row">
        <div style={{ fontSize: 16, fontWeight: 700 }}>{country ? country.nombre : 'Océano'}</div>
        <span className="spacer" />
        <button onClick={() => getGlobe()?.flyTo(cell.lat, cell.lon, 1.35)} title="Acercar">⌖</button>
        <button onClick={() => ui.set({ selected: null })} title="Cerrar (Esc)">✕</button>
      </div>
      <div className="dim mono" style={{ fontSize: 11, marginBottom: 10 }}>
        {fmtLat(cell.lat)} · {fmtLon(cell.lon)} · celda {world.grid.res}° (≈{Math.round(world.grid.res * 111 * Math.cos((cell.lat * Math.PI) / 180))}×{Math.round(world.grid.res * 111)} km)
      </div>

      <div style={{ marginBottom: 12 }}>
        <button className="primary" style={{ width: '100%' }} data-testid="develop" disabled={!canDevelop}
          onClick={() => ui.set({ developAt: { lat: cell.lat, lon: cell.lon } })}>Desarrollar proyecto aquí</button>
        {sheetCode && (
          <button style={{ width: '100%', marginTop: 6 }} data-testid="country-sheet" onClick={() => ui.openCountry(sheetCode)} title="También: doble clic sobre el país">
            Ficha de {devCountry!.nombre}{cmark ? ` · ${cmark.presence === 'origen' ? 'origen' : cmark.presence === 'activa' ? 'con presencia' : cmark.presence === 'en_tramite' ? 'en trámite' : cmark.unlocked ? 'desbloqueado' : 'cerrado'}` : ''} →
          </button>
        )}
        {!canDevelop && (
          <div className="dim" style={{ fontSize: 11, marginTop: 4 }}>
            {!cell.land ? 'Mar abierto: la eólica marina se desarrolla cerca de la costa de un país con mercado.' : `Mercado de ${country?.nombre ?? 'esta zona'} aún no disponible.`}
          </div>
        )}
        {here.map((p) => (
          <button key={p.id} className="row" style={{ width: '100%', marginTop: 6, textAlign: 'left' }} onClick={() => ui.openProject(p.id)}>
            <span style={{ flex: 1, minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{p.name}</span>
            <StageBadge stage={p.stage} label={p.stageLabel} />
          </button>
        ))}
      </div>

      <h3>Recursos</h3>
      <table className="kv">
        <tbody>
          {layers.map((l) => {
            const v = cell.values[l.id];
            const r = RATED.has(l.id) ? rating(l, v) : null;
            return (
              <tr key={l.id} onClick={() => ui.set({ layerId: l.id })} style={{ cursor: 'pointer', background: l.id === layerId ? 'rgba(255,203,61,.08)' : undefined }}>
                <td>{l.nombre}{r && <> <span className="badge" style={{ color: r.color, border: `1px solid ${r.color}` }}>{r.text}</span></>}</td>
                <td>{fmtNum(v, l.id === 'ghi' || l.id === 'dni' || l.id.startsWith('viento') ? 1 : 0)} <span className="dim">{l.unidad}</span></td>
              </tr>
            );
          })}
          {!cell.land && <tr><td>Distancia a la costa</td><td>{fmtNum(cell.values.dist_costa_km, 0)} <span className="dim">km</span></td></tr>}
        </tbody>
      </table>

      <h3 style={{ marginTop: 14 }}>Potencial</h3>
      {best.length ? (
        <div style={{ display: 'grid', gap: 4 }}>
          {best.map(({ l, r }) => <div key={l.id}><span style={{ color: r.color }}>●</span> {l.tecnologias.join(' / ')} <span className="dim">({r.text.toLowerCase()})</span></div>)}
        </div>
      ) : <div className="dim">Ningún recurso destacado en esta zona.</div>}

      {country && (
        <>
          <h3 style={{ marginTop: 14 }}>País</h3>
          <table className="kv">
            <tbody>
              <tr><td>Población</td><td>{fmtCompact(country.poblacion)}</td></tr>
              <tr><td>PIB</td><td>US$ {fmtCompact(country.pib_musd * 1e6)}</td></tr>
              {cdata && (
                <>
                  <tr><td>Regulador</td><td style={{ fontFamily: 'inherit', fontSize: 11 }}>{cdata.regulador.split(' (')[0]}</td></tr>
                  <tr><td>Demanda eléctrica</td><td>{fmtNum(cdata.mercado.demanda_anual_twh.base)} TWh/año</td></tr>
                  <tr><td>Pico de demanda</td><td>{fmtNum(cdata.mercado.pico_mw.base, 0)} MW</td></tr>
                  <tr><td>Precio spot medio</td><td>{fmtNum(cdata.mercado.precio_spot_medio_usd_mwh.base, 0)} USD/MWh</td></tr>
                  <tr><td>Prima riesgo país</td><td>{fmtNum(cdata.prima_riesgo_pais.base * 100)} %</td></tr>
                </>
              )}
            </tbody>
          </table>
          {!cdata && <div className="dim" style={{ fontSize: 11, marginTop: 6 }}>Mercado aún no disponible (se abre con la expansión).</div>}
        </>
      )}
      <div className="dim" style={{ fontSize: 10.5, marginTop: 12 }}>Valores aproximados por celda; el recurso real de un sitio se conoce con estudios. Ver docs/RECURSOS.md.</div>
    </div>
  );
}
