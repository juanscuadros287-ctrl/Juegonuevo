import { useEffect, useState } from 'react';
import { gameData } from '@voltaje/data';
import { sim } from '../worker/client';
import type { SiteEstimate } from '../worker/protocol';
import { ui, useUi } from './store';
import { fmtLat, fmtLon, fmtMoney, fmtNum, fmtPct } from './format';

/** Tecnologías que el jugador puede desarrollar hoy (las que tienen recurso de grilla). */
export const BUILDABLE = ['solar_fv', 'eolica_tierra'] as const;
const ICON: Record<string, string> = { solar_fv: '☀', eolica_tierra: '✇' };

export function DevelopDialog() {
  const at = useUi((s) => s.developAt);
  const cash = useUi((s) => s.game?.company.cashUsd ?? 0);
  const [techId, setTechId] = useState<string>('solar_fv');
  const [mw, setMw] = useState(10);
  const [name, setName] = useState('');
  const [est, setEst] = useState<SiteEstimate | null>(null);
  const [busy, setBusy] = useState(false);
  const tech = gameData.simData.technologies[techId];
  const layer = gameData.layers.find((l) => l.id === tech.recurso);

  useEffect(() => {
    if (!at) return;
    setBusy(true);
    let live = true;
    const t = setTimeout(() => {
      sim.preview(techId, mw, at.lat, at.lon).then((e) => { if (live) { setEst(e); setBusy(false); } });
    }, 120);
    return () => { live = false; clearTimeout(t); };
  }, [at, techId, mw]);

  if (!at) return null;
  const close = () => ui.set({ developAt: null });
  const p = est?.preview;
  const cost = p?.prospectingUsd ?? 0;
  const canPay = cash >= cost;
  const ok = !!p?.ok && !busy;
  const lo = tech.escala_mw.min, hi = tech.escala_mw.max;
  const pickTech = (id: string) => {
    const t = gameData.simData.technologies[id];
    setTechId(id);
    setMw((m) => Math.min(t.escala_mw.max, Math.max(t.escala_mw.min, id === 'eolica_tierra' ? Math.max(m, 20) : m)));
  };
  const create = () => {
    sim.command({ type: 'createProject', techId, mw, lat: at.lat, lon: at.lon, name: name.trim() || undefined });
    ui.set({ developAt: null });
  };

  return (
    <div className="modal-back" onClick={close}>
      <div className="panel modal" style={{ width: 620 }} onClick={(e) => e.stopPropagation()} data-testid="develop-dialog">
        <div className="row" style={{ marginBottom: 4 }}>
          <div className="window-title">Desarrollar proyecto</div>
          <span className="spacer" />
          <button onClick={close} title="Cerrar (Esc)">✕</button>
        </div>
        <div className="dim" style={{ marginBottom: 14 }}>{fmtLat(at.lat)} · {fmtLon(at.lon)} — prospección y opción de terreno sobre esta celda.</div>

        <div className="grid2" style={{ marginBottom: 12 }}>
          {BUILDABLE.map((id) => {
            const t = gameData.simData.technologies[id];
            return (
              <button key={id} data-tech={id} className={`choice ${techId === id ? 'selected' : ''}`} onClick={() => pickTech(id)}>
                <span className="choice-icon">{ICON[id]}</span>
                <span style={{ textAlign: 'left' }}>
                  <b>{t.nombre}</b>
                  <span className="dim" style={{ display: 'block', fontSize: 11.5 }}>{t.escala_mw.min}–{t.escala_mw.max} MW · obra {t.construccion_meses.base} meses · vida {t.vida_util_anos.base} años</span>
                </span>
              </button>
            );
          })}
        </div>

        <div className="row" style={{ gap: 12, marginBottom: 6 }}>
          <label style={{ flex: 1 }}>Capacidad
            <input type="range" min={lo} max={hi} step={lo < 5 ? 1 : 5} value={mw} onChange={(e) => setMw(+e.target.value)} />
          </label>
          <div className="row" style={{ gap: 4, width: 120 }}>
            <input type="number" data-testid="mw" min={lo} max={hi} value={mw} onChange={(e) => setMw(Math.max(lo, Math.min(hi, Math.round(+e.target.value || lo))))} />
            <span className="dim">MW</span>
          </div>
        </div>
        <label style={{ display: 'block', marginBottom: 12 }}>Nombre (opcional)
          <input type="text" value={name} maxLength={60} placeholder={`${tech.nombre} ${mw} MW`} onChange={(e) => setName(e.target.value)} />
        </label>

        {p && !p.ok && <div className="notice bad">{p.error}</div>}
        {p?.ok && (
          <div className="grid2" style={{ opacity: busy ? 0.6 : 1 }}>
            <div>
              <h3>Recurso estimado (celda)</h3>
              <table className="kv"><tbody>
                <tr><td>P50</td><td>{fmtNum(p.cellValue, 2)} <span className="dim">{layer?.unidad}</span></td></tr>
                <tr><td>P90</td><td>{fmtNum(p.resourceP90, 2)} <span className="dim">{layer?.unidad}</span></td></tr>
                <tr><td>Incertidumbre (σ)</td><td>± {fmtPct(p.sigma)}</td></tr>
                <tr><td>Factor de capacidad P50 / P90</td><td>{fmtPct(p.fcP50)} / {fmtPct(p.fcP90)}</td></tr>
                <tr><td>Energía P50</td><td>{fmtNum(p.energyP50MwhYear / 1000, 1)} <span className="dim">GWh/año</span></td></tr>
                <tr><td>Terreno</td><td>{fmtNum(p.landHa, 0)} <span className="dim">ha</span></td></tr>
              </tbody></table>
            </div>
            <div>
              <h3>Economía estimada</h3>
              <table className="kv"><tbody>
                <tr><td>CAPEX de obra</td><td>{fmtMoney(p.capexUsd)}</td></tr>
                <tr><td>Por kW</td><td>{fmtNum(p.capexUsd / (mw * 1000), 0)} <span className="dim">US$/kW</span></td></tr>
                <tr><td>LCOE</td><td>{est?.lcoeUsdMwh ? `${fmtNum(est.lcoeUsdMwh, 1)} US$/MWh` : '—'}</td></tr>
                <tr><td>TIR del capital</td><td>{fmtPct(est?.irrEquity)}</td></tr>
                <tr><td>VAN del capital</td><td style={{ color: (est?.npvEquityUsd ?? 0) < 0 ? 'var(--bad)' : undefined }}>{fmtMoney(est?.npvEquityUsd)}</td></tr>
                <tr><td>Desarrollo por venir</td><td>{fmtMoney(est?.devCostUpcomingUsd)}</td></tr>
                <tr><td>Prob. de llegar a obra</td><td>{fmtPct(est?.successProbability, 0)}</td></tr>
              </tbody></table>
            </div>
          </div>
        )}
        <div className="dim" style={{ fontSize: 11, marginTop: 10 }}>
          Estimación con el valor de la celda: el recurso real del sitio puede ser distinto (± σ) y solo se conoce con un estudio de medición.
          {est?.priceUsdMwh ? ` Precio supuesto: ${fmtNum(est.priceUsdMwh, 0)} US$/MWh (spot capturado, sin PPA).` : ''}
        </div>

        <div className="row" style={{ marginTop: 16 }}>
          <span className="dim">Costo ahora: <b className="mono" style={{ color: 'var(--text)' }}>{fmtMoney(cost)}</b> · caja {fmtMoney(cash)}</span>
          <span className="spacer" />
          <button onClick={close}>Cancelar</button>
          <button className="primary" data-testid="create-project" disabled={!ok || !canPay} onClick={create}>
            {canPay ? `Crear proyecto (${fmtMoney(cost)})` : 'Caja insuficiente'}
          </button>
        </div>
      </div>
    </div>
  );
}
