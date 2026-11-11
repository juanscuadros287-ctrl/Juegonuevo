import { useEffect, useMemo, useState, type ReactNode } from 'react';
import { gameData } from '@voltaje/data';
import { countryAccessBlockers, evaluateSite, techUnlocked, unlockingNode, type SimContext, type TechMode, type TechnologyDef } from '@voltaje/sim';
import type { World } from '../world/loadWorld';
import { sim } from '../worker/client';
import type { SiteEstimate } from '../worker/protocol';
import { ui, useUi } from './store';
import { fmtLat, fmtLon, fmtMoney, fmtNum, fmtPct } from './format';
import { Pill } from './common';
import { MODE_LABEL, MODE_ORDER, MODE_PRODUCT, TECH_ICON, allTechs, countryName, fuelName, modeOf, mwStep } from './tech';

/** Disponibilidad de una tecnología en el sitio elegido: I+D, país (acceso o prohibición) y sitio. */
interface Availability { ok: boolean; kind: 'ok' | 'id' | 'pais' | 'sitio'; reason?: string }

const LINE_ONLY = 'Una línea necesita el punto final.';

function availability(ctx: SimContext, game: Parameters<typeof techUnlocked>[0] & Parameters<typeof countryAccessBlockers>[0], t: TechnologyDef, at: { lat: number; lon: number; to?: { lat: number; lon: number } }): Availability {
  const ev = evaluateSite(ctx, t.id, at.lat, at.lon, at.to);
  const site = ev.errors.filter((e) => e !== LINE_ONLY);
  // prohibiciones del país: cuentan como «país», no como sitio
  const banned = site.filter((e) => / no permite |solo se puede desarrollar en/.test(e));
  const pure = site.filter((e) => !banned.includes(e));
  if (pure.length) return { ok: false, kind: 'sitio', reason: pure[0] };
  if (banned.length) return { ok: false, kind: 'pais', reason: banned[0] };
  if (!techUnlocked(game, ctx, t.id)) return { ok: false, kind: 'id', reason: `Requiere I+D: ${unlockingNode(ctx, 'tecnologias', t.id)?.nombre ?? 'investigación'}.` };
  const access = ev.countryCode ? countryAccessBlockers(game as never, ctx, ev.countryCode) : [];
  if (access.length) return { ok: false, kind: 'pais', reason: access[0] };
  return { ok: true, kind: 'ok' };
}

const AV_PILL: Record<Availability['kind'], { label: string; tone: 'good' | 'warn' | 'bad' | 'info' }> = {
  ok: { label: 'Disponible', tone: 'good' }, id: { label: 'I+D', tone: 'info' }, pais: { label: 'País', tone: 'warn' }, sitio: { label: 'Sitio', tone: 'bad' },
};

export function DevelopDialog({ world }: { world: World }) {
  const at = useUi((s) => s.developAt);
  const picking = useUi((s) => s.pickingRoute);
  const game = useUi((s) => s.game);
  const cash = game?.company.cashUsd ?? 0;
  const [techId, setTechId] = useState<string>('solar_fv');
  const [mw, setMw] = useState(10);
  const [name, setName] = useState('');
  const [est, setEst] = useState<SiteEstimate | null>(null);
  const [busy, setBusy] = useState(false);
  const ctx = useMemo<SimContext>(() => ({ data: gameData.simData, grid: world.grid }), [world]);
  const tech = gameData.simData.technologies[techId];
  const mode = modeOf(techId);
  const isLine = !!tech.transmision;
  const to = at?.to;

  // disponibilidad de todas las tecnologías en este sitio (sin pedir nada al worker: evaluateSite con la grilla de la UI)
  const avail = useMemo(() => {
    const out: Record<string, Availability> = {};
    if (!at || !game) return out;
    for (const t of allTechs()) out[t.id] = availability(ctx, game, t, at);
    return out;
  }, [at, game?.business?.research.completed.length, game?.business?.presence, ctx]);

  // al abrir en un sitio: elegir la primera tecnología disponible si la actual no lo está
  useEffect(() => {
    if (!at || picking) return;
    if (avail[techId] && avail[techId].kind === 'sitio') {
      const first = allTechs().find((t) => avail[t.id]?.ok) ?? allTechs().find((t) => avail[t.id]?.kind !== 'sitio');
      if (first) pickTech(first.id);
    }
  }, [at?.lat, at?.lon]);

  useEffect(() => {
    if (!at || picking) return;
    if (isLine && !to) { setEst(null); return; }
    setBusy(true);
    let live = true;
    const t = setTimeout(() => {
      sim.preview(techId, mw, at.lat, at.lon, isLine ? to : undefined).then((e) => { if (live) { setEst(e); setBusy(false); } });
    }, 140);
    return () => { live = false; clearTimeout(t); };
  }, [at, techId, mw, to, picking]);

  if (!at) return null;
  if (picking) {
    return (
      <div className="panel route-banner" data-testid="route-banner">
        <b>{TECH_ICON[techId]} {tech.nombre}:</b> haz clic en el globo en el <b>punto final</b> de la línea
        <span className="dim"> ({tech.transmision?.longitud_min_km}–{tech.transmision?.longitud_max_km} km{tech.transmision?.interconexion ? ', en otro país' : ', en el mismo país'})</span>
        <button style={{ marginLeft: 10 }} onClick={() => ui.set({ pickingRoute: false })}>Cancelar</button>
      </div>
    );
  }
  const close = () => ui.set({ developAt: null, pickingRoute: false });
  const p = est?.preview;
  const cost = p?.prospectingUsd ?? 0;
  const canPay = cash >= cost;
  const ok = !!p?.ok && !busy;
  const lo = tech.escala_mw.min, hi = tech.escala_mw.max;
  function pickTech(id: string) {
    const t = gameData.simData.technologies[id];
    setTechId(id);
    setMw(Math.min(t.escala_mw.max, Math.max(t.escala_mw.min, t.escala_mw.tipico)));
  }
  const create = () => {
    sim.command({ type: 'createProject', techId, mw, lat: at.lat, lon: at.lon, name: name.trim() || undefined, ...(isLine && to ? { toLat: to.lat, toLon: to.lon } : {}) });
    ui.set({ developAt: null });
  };
  const av = avail[techId];
  const access = p?.accessBlockers ?? [];
  const siteErrors = (p?.errors ?? []).filter((e) => !access.includes(e) && !/requiere investigación/.test(e) && e !== LINE_ONLY);
  const researchErr = (p?.errors ?? []).find((e) => /requiere investigación/.test(e));
  const country = p?.countryCode ?? world.grid.cell(at.lat, at.lon).country?.code;

  return (
    <div className="modal-back" onClick={close}>
      <div className="panel modal develop" onClick={(e) => e.stopPropagation()} data-testid="develop-dialog">
        <div className="row" style={{ marginBottom: 4 }}>
          <div className="window-title">Desarrollar proyecto</div>
          <span className="spacer" />
          <button onClick={close} title="Cerrar (Esc)">✕</button>
        </div>
        <div className="dim" style={{ marginBottom: 12 }}>
          {fmtLat(at.lat)} · {fmtLon(at.lon)}{p?.countryName ? ` · ${p.countryName}` : ''} — prospección y opción de terreno sobre esta celda.
        </div>
        <div className="develop-grid">
          <div className="tech-list scroll" data-testid="tech-list">
            {MODE_ORDER.map((m) => {
              const list = allTechs().filter((t) => modeOf(t.id) === m);
              if (!list.length) return null;
              return (
                <div key={m}>
                  <div className="field-label" style={{ margin: '6px 0 4px' }}>{MODE_LABEL[m]}</div>
                  {list.map((t) => {
                    const a = avail[t.id];
                    return (
                      <button key={t.id} data-tech={t.id} className={`tech-item ${techId === t.id ? 'selected' : ''} ${a && !a.ok ? 'off' : ''}`} onClick={() => pickTech(t.id)} title={a?.reason}>
                        <span className="tech-icon">{TECH_ICON[t.id] ?? '•'}</span>
                        <span className="ellipsis" style={{ flex: 1, minWidth: 0 }}>{t.nombre}</span>
                        {a && <Pill tone={AV_PILL[a.kind].tone}>{a.ok ? '✓' : AV_PILL[a.kind].label}</Pill>}
                      </button>
                    );
                  })}
                </div>
              );
            })}
          </div>

          <div style={{ minWidth: 0 }}>
            <div className="row" style={{ gap: 10, marginBottom: 6, alignItems: 'baseline' }}>
              <span style={{ fontSize: 17, fontWeight: 700 }}>{TECH_ICON[techId]} {tech.nombre}</span>
              <span className="dim">{MODE_LABEL[mode]}</span>
            </div>
            <div className="param-chips">
              <span>CAPEX <b>{fmtNum(tech.capex_usd_kw.base, 0)}</b> US$/kW</span>
              <span>O&M <b>{fmtNum(tech.om_fijo_usd_kw_ano.base, 0)}</b> US$/kW-año</span>
              {mode !== 'transmision' && mode !== 'eficiencia' && <span>FC ref. <b>{fmtPct(tech.factor_capacidad_ref.base, 0)}</b></span>}
              <span>Vida <b>{tech.vida_util_anos.base}</b> años</span>
              <span>Obra <b>{tech.construccion_meses.base}</b> meses</span>
              <span>Emisiones <b>{fmtNum(tech.emisiones_gco2_kwh.base, 0)}</b> gCO₂/kWh</span>
              <span>Escala <b>{lo}–{fmtNum(hi, 0)}</b> MW</span>
            </div>
            {av && !av.ok && (
              <div className={`notice ${av.kind === 'sitio' ? 'bad' : 'warn'}`} style={{ marginTop: 8 }} data-testid="avail-notice">
                <b>{av.kind === 'sitio' ? 'Este sitio no sirve: ' : av.kind === 'id' ? 'Bloqueada por I+D: ' : 'Acceso al país: '}</b>{av.reason}
                {av.kind === 'id' && <button style={{ marginLeft: 8 }} onClick={() => { const n = unlockingNode(ctx, 'tecnologias', techId); ui.set({ developAt: null }); ui.openPanel('research', n?.id); }}>Ir a I+D</button>}
                {av.kind === 'pais' && country && gameData.simData.countries[country] && <button style={{ marginLeft: 8 }} onClick={() => { ui.set({ developAt: null }); ui.openCountry(country); }}>Ficha del país</button>}
              </div>
            )}

            <div className="row" style={{ gap: 12, margin: '10px 0 6px' }}>
              <label style={{ flex: 1 }}>Capacidad{mode === 'eficiencia' ? ' (carga atendida)' : mode === 'hidrogeno' ? ' (electrolizador)' : ''}
                <input type="range" min={lo} max={hi} step={mwStep(lo, hi)} value={mw} onChange={(e) => setMw(+e.target.value)} />
              </label>
              <div className="row" style={{ gap: 4, width: 120 }}>
                <input type="number" data-testid="mw" min={lo} max={hi} value={mw} onChange={(e) => setMw(Math.max(lo, Math.min(hi, Math.round(+e.target.value || lo))))} />
                <span className="dim">MW</span>
              </div>
            </div>
            {isLine && (
              <div className="row route-row">
                <span>Punto final: {to ? <b className="mono">{fmtLat(to.lat)} · {fmtLon(to.lon)}{p?.site?.to ? ` · ${countryName(p.site.to.countryCode)} · ${fmtNum(p.site.to.km, 0)} km` : ''}</b> : <span className="dim">sin elegir</span>}</span>
                <span className="spacer" />
                <button className={to ? '' : 'primary'} data-testid="pick-route" onClick={() => ui.set({ pickingRoute: true })}>{to ? 'Cambiar punto final' : 'Elegir punto final en el globo'}</button>
              </div>
            )}
            <label style={{ display: 'block', marginBottom: 10 }}>Nombre (opcional)
              <input type="text" value={name} maxLength={60} placeholder={`${tech.nombre} ${mw} MW`} onChange={(e) => setName(e.target.value)} />
            </label>

            {isLine && !to && <div className="notice">Elige el punto final de la línea en el globo para ver el trazado, la longitud, las pérdidas y la economía.</div>}
            {siteErrors.length > 0 && <div className="notice bad"><b>Sitio:</b> {siteErrors.join(' ')}</div>}
            {p && (siteErrors.length === 0) && (access.length > 0 || researchErr) && (
              <div className="notice warn" style={{ marginBottom: 8 }}>
                {researchErr && <div><b>I+D:</b> {researchErr}</div>}
                {access.map((a) => <div key={a}><b>País:</b> {a}</div>)}
                <div className="dim" style={{ fontSize: 11 }}>El sitio sirve: la estimación supone que ya investigaste la tecnología y abriste el mercado.</div>
              </div>
            )}
            {p && siteErrors.length === 0 && <Preview est={est!} mode={mode} tech={tech} mw={mw} busy={busy} />}
          </div>
        </div>

        <div className="row" style={{ marginTop: 14 }}>
          <span className="dim">Costo ahora: <b className="mono" style={{ color: 'var(--text)' }}>{fmtMoney(cost)}</b> · caja {fmtMoney(cash)}</span>
          <span className="spacer" />
          <button onClick={close}>Cancelar</button>
          <button className="primary" data-testid="create-project" disabled={!ok || !canPay} onClick={create} title={p?.error}>
            {!p?.ok && p ? 'No disponible' : canPay ? `Crear proyecto (${fmtMoney(cost)})` : 'Caja insuficiente'}
          </button>
        </div>
      </div>
    </div>
  );
}

function Kv({ rows }: { rows: [ReactNode, ReactNode, boolean?][] }) {
  return <table className="kv"><tbody>{rows.filter((r) => r[2] !== false).map(([k, v], i) => <tr key={i}><td>{k}</td><td>{v}</td></tr>)}</tbody></table>;
}

/** Vista previa adaptada al modo económico de la tecnología. */
function Preview({ est, mode, tech, mw, busy }: { est: SiteEstimate; mode: TechMode; tech: TechnologyDef; mw: number; busy: boolean }) {
  const p = est.preview;
  const layer = gameData.layers.find((l) => l.id === p.layer);
  const site = p.site;
  const gwh = (v: number) => <>{fmtNum(v / 1000, 1)} <span className="dim">GWh/año</span></>;
  const usdMwh = (v: number | null | undefined) => (v === null || v === undefined || !Number.isFinite(v) ? '—' : <>{fmtNum(v, 1)} <span className="dim">US$/MWh</span></>);
  const prod = MODE_PRODUCT[mode];
  let left: [ReactNode, ReactNode, boolean?][] = [];
  let title = 'Recurso estimado (celda)';
  if (mode === 'generacion') {
    left = [
      ['Recurso P50 / P90', <>{fmtNum(p.cellValue, 2)} / {fmtNum(p.resourceP90, 2)} <span className="dim">{layer?.unidad}</span></>],
      ['Incertidumbre (σ)', `± ${fmtPct(p.sigma)}`],
      ['Factor de capacidad P50 / P90', `${fmtPct(p.fcP50)} / ${fmtPct(p.fcP90)}`],
      [prod.energy, gwh(p.energyP50MwhYear)],
      ['Terreno', <>{fmtNum(p.landHa, 0)} <span className="dim">ha</span></>],
    ];
    if (tech.id === 'geotermica') left.push(['Flujo de calor', <>{fmtNum(p.cellValue, 0)} <span className="dim">mW/m²</span></>], ['Pozos exploratorios', <span className="dim">pueden salir secos (estudio de perforación)</span>]);
    if (site?.offshore) left.push(['Distancia a la costa', `${fmtNum(site.distCoastKm, 0)} km`], ['Profundidad aprox.', `${fmtNum(site.depthM, 0)} m`]);
    if (tech.recurso === 'hidro') left.push(['Lluvia anual', `${fmtNum(site?.rainMm ?? 0, 0)} mm`], ['Relieve', fmtNum(site?.relief ?? 0, 2)]);
  } else if (mode === 'termica') {
    title = 'Combustible y despacho';
    left = [
      ['Combustible', fuelName(tech.combustible?.tipo)],
      ['Heat rate', <>{fmtNum(tech.combustible?.heat_rate_btu_kwh.base ?? 0, 0)} <span className="dim">Btu/kWh</span></>],
      ['Costo variable (combustible + CO₂)', usdMwh(p.fuelCostUsdMwh)],
      ['Despacho supuesto', fmtPct(p.dispatch, 0)],
      ['Factor de capacidad', fmtPct(p.fcP50)],
      [prod.energy, gwh(p.energyP50MwhYear)],
      ['Agua (refrigeración)', site ? `índice hidro ${fmtNum(site.hydroIndex, 0)} · costa a ${fmtNum(site.distCoastKm, 0)} km` : '—'],
    ];
    if (p.layer === 'biomasa') left.push(['Biomasa disponible', `${fmtNum(p.cellValue, 0)} ${layer?.unidad ?? ''}`]);
  } else if (mode === 'almacenamiento') {
    title = 'Almacenamiento';
    const h = tech.almacenamiento?.horas.base ?? 0;
    left = [
      ['Duración', `${fmtNum(h, 1)} h · ${fmtNum(mw * h, 0)} MWh`],
      ['Eficiencia ida y vuelta', fmtPct(tech.almacenamiento?.eficiencia_ida_vuelta.base, 0)],
      ['Ciclos/año (si el arbitraje paga)', fmtNum(tech.almacenamiento?.ciclos_ano_max ?? 0, 0)],
      ['Degradación por ciclo', fmtPct(tech.almacenamiento?.degradacion_por_ciclo ?? 0, 3)],
      [prod.energy, gwh(p.energyP50MwhYear)],
      ['Costo de la carga (valle)', usdMwh(p.fuelCostUsdMwh)],
    ];
    if (tech.id === 'hidro_bombeo') left.push(['Relieve', fmtNum(site?.relief ?? 0, 2)]);
  } else if (mode === 'hidrogeno') {
    title = 'Electrólisis';
    const kwh = tech.hidrogeno?.kwh_por_kg.base ?? 55;
    left = [
      ['Consumo', <>{fmtNum(kwh, 1)} <span className="dim">kWh/kg</span></>],
      ['Utilización', fmtPct(tech.hidrogeno?.utilizacion, 0)],
      [prod.energy, gwh(p.energyP50MwhYear)],
      ['Producción de H₂', <>{fmtNum((p.energyP50MwhYear * 1000) / kwh / 1000, 0)} <span className="dim">t/año</span></>],
      ['Costo de la electricidad', usdMwh(p.fuelCostUsdMwh)],
      ['Precio de venta del H₂', <>{fmtNum(tech.hidrogeno?.precio_venta_usd_kg.base ?? 0, 2)} <span className="dim">US$/kg</span></>],
    ];
  } else if (mode === 'transmision') {
    title = 'Trazado';
    const km = site?.to?.km ?? 0;
    const tr = tech.transmision!;
    left = [
      ['Destino', site?.to ? `${countryName(site.to.countryCode)} (${fmtLat(site.to.lat)} · ${fmtLon(site.to.lon)})` : '—'],
      ['Longitud de trazado', <>{fmtNum(km, 0)} <span className="dim">km (gran círculo × 1,15)</span></>],
      ['Pérdidas', fmtPct((tr.perdidas_frac_100km * km) / 100, 1)],
      ['Costo por MW-km', <>{fmtNum(tr.costo_usd_mw_km.base, 0)} <span className="dim">US$</span></>],
      ['Peaje', usdMwh(tr.peaje_usd_mwh.base)],
      ['Utilización', fmtPct(tr.utilizacion, 0)],
      [prod.energy, gwh(p.energyP50MwhYear)],
      ['Costo de las pérdidas', usdMwh(p.fuelCostUsdMwh)],
    ];
  } else {
    title = 'Ahorro (auditoría)';
    const ef = tech.eficiencia!;
    left = [
      [prod.energy, gwh(p.energyP50MwhYear)],
      ['Ahorro garantizado', `${fmtPct(ef.ahorro_garantizado_frac, 0)} de la estimación (${fmtNum((p.energyP50MwhYear * ef.ahorro_garantizado_frac) / 1000, 1)} GWh/año)`],
      ['Precio del ahorro', usdMwh(ef.precio_ahorro_usd_mwh.base)],
      ['Si no se llega', <span className="dim">se paga la diferencia al precio del contrato</span>],
    ];
  }
  const lcoeLabel = mode === 'hidrogeno' ? 'LCOH' : prod.lcoe;
  const lcoe = mode === 'hidrogeno'
    ? (p.lcohUsdKg ? <>{fmtNum(p.lcohUsdKg, 2)} <span className="dim">US$/kg</span></> : '—')
    : usdMwh(est.lcoeUsdMwh ?? p.lcoeUsdMwh);
  const irr = est.irrEquity ?? p.irrEquity ?? null;
  return (
    <div className="grid2" style={{ opacity: busy ? 0.6 : 1 }} data-testid="site-preview">
      <div>
        <h3>{title}</h3>
        <Kv rows={left} />
      </div>
      <div>
        <h3>Economía estimada</h3>
        <Kv rows={[
          ['CAPEX de obra', fmtMoney(p.capexUsd)],
          ['Por kW', <>{fmtNum(p.capexUsdKw ?? p.capexUsd / (mw * 1000), 0)} <span className="dim">US$/kW</span>{p.siteCapexFactor && Math.abs(p.siteCapexFactor - 1) > 0.005 ? <span className="dim"> · sitio ×{fmtNum(p.siteCapexFactor, 2)}</span> : null}</>],
          [lcoeLabel, lcoe],
          ['TIR del capital', <span style={{ color: irr !== null && irr < 0.08 ? 'var(--warn)' : undefined }}>{fmtPct(irr)}</span>],
          ['VAN del capital', <span style={{ color: (est.npvEquityUsd ?? 0) < 0 ? 'var(--bad)' : undefined }}>{fmtMoney(est.npvEquityUsd)}</span>],
          ['Desarrollo por venir', fmtMoney(est.devCostUpcomingUsd)],
          ['Prob. de llegar a obra', fmtPct(est.successProbability, 0)],
          ['Precio supuesto', est.priceUsdMwh ? usdMwh(est.priceUsdMwh) : '—', mode !== 'hidrogeno'],
        ]} />
        {!!p.restrictions?.length && <div className="hint">{p.restrictions.join(' ')}</div>}
      </div>
      <div className="dim" style={{ fontSize: 11, gridColumn: '1 / -1' }}>
        Estimación con la información pública de la celda: el recurso real puede ser distinto (± σ) y solo se conoce con estudios. Sin PPA: precio de mercado capturado.
      </div>
    </div>
  );
}
