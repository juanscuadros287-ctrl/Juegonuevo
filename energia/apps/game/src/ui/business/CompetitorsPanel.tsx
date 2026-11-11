import { useMemo } from 'react';
import { PLAYER_ID, type CompetitorView } from '@voltaje/sim';
import { getGlobe } from '../../globe/GlobeView';
import { STAGE_COLORS } from '../../globe/siteVisual';
import { ui, useUi } from '../store';
import { Bar, Empty, Pill, Section, Stat, StageBadge, Window } from '../common';
import { Chart, CHART, baseOption } from '../Chart';
import { fmtNum, fmtPct } from '../format';
import { PLAYER_COLOR, rivalColor, techShort } from './labels';
import { monthLabel } from '../format';

export function CompetitorsPanel() {
  const ov = useUi((s) => s.views?.business?.competitors);
  const pick = useUi((s) => s.pick.competitors);
  const list = ov?.competitors ?? [];
  const sel = list.find((c) => c.id === pick) ?? list[0];
  const choose = (id: string) => ui.set((s) => ({ pick: { ...s.pick, competitors: id } }));
  const key = ov ? list.map((c) => `${c.operatingMw}-${c.visibleProjects.length}-${c.experienceMw}`).join('|') + ov.player.operatingMw : '';
  const chartOpt = useMemo(() => {
    if (!ov) return null;
    const rows = [{ name: ov.player.name, op: ov.player.operatingMw, dev: 0, exp: ov.player.experienceMw, color: PLAYER_COLOR },
      ...list.map((c, i) => ({ name: c.name, op: c.operatingMw, dev: c.visibleProjects.filter((p) => p.stageId !== 'operacion').reduce((a, p) => a + p.mw, 0), exp: c.experienceMw, color: rivalColor(i) }))];
    const o = baseOption(rows.map((r) => r.name), { unit: ' MW' }) as Record<string, unknown>;
    return {
      ...o,
      grid: { left: 150, right: 18, top: 8, bottom: 22 },
      legend: { show: false },
      xAxis: { type: 'value', splitLine: { lineStyle: { color: CHART.grid } }, axisLabel: { color: CHART.text, formatter: (v: number) => `${v} MW` } },
      yAxis: { type: 'category', inverse: true, data: rows.map((r) => r.name), axisLabel: { color: CHART.text, width: 135, overflow: 'truncate' }, axisLine: { lineStyle: { color: CHART.grid } } },
      series: [
        { name: 'En operación', type: 'bar', stack: 'mw', data: rows.map((r) => ({ value: Math.round(r.op), itemStyle: { color: r.color } })), barWidth: 14 },
        { name: 'En desarrollo (visible)', type: 'bar', stack: 'mw', data: rows.map((r) => ({ value: Math.round(r.dev), itemStyle: { color: r.color, opacity: 0.4 } })) },
        { name: 'Experiencia acreditada', type: 'line', data: rows.map((r) => Math.round(r.exp)), symbol: 'diamond', symbolSize: 9, lineStyle: { opacity: 0 }, itemStyle: { color: '#e6eef7' } },
      ],
    };
  }, [key]);

  const hist = useUi((s) => s.views?.power?.shareHistory);
  const histKey = hist ? `${hist.length}-${hist[hist.length - 1]?.totalMw ?? 0}` : '';
  const shareOpt = useMemo(() => {
    if (!hist?.length || !ov) return null;
    const ids = [PLAYER_ID, ...list.map((c) => c.id)];
    const color = (id: string) => (id === PLAYER_ID ? PLAYER_COLOR : rivalColor(list.findIndex((c) => c.id === id)));
    const name = (id: string) => (id === PLAYER_ID ? ov.player.name : list.find((c) => c.id === id)?.name ?? id);
    const o = baseOption(hist.map((h) => monthLabel(h.year, h.month)), { percent: true }) as Record<string, unknown>;
    return {
      ...o,
      grid: { left: 56, right: 64, top: 34, bottom: 28 },
      yAxis: [{ ...(o.yAxis as object), max: 1 }, { type: 'value', splitLine: { show: false }, axisLabel: { color: CHART.text, formatter: (v: number) => `${v} MW` } }],
      tooltip: { ...(o.tooltip as object), valueFormatter: (v: unknown) => (typeof v === 'number' ? (v <= 1 ? `${(v * 100).toFixed(1)} %` : `${fmtNum(v, 0)} MW`) : String(v)) },
      series: [
        ...ids.map((id) => ({ name: name(id), type: 'line', stack: 'share', areaStyle: { opacity: id === PLAYER_ID ? 0.75 : 0.45 }, symbol: 'none', lineStyle: { width: 1, color: color(id) }, itemStyle: { color: color(id) },
          data: hist.map((h) => h.actors.find((a) => a.id === id)?.share ?? 0) })),
        { name: 'MW en operación', type: 'line', yAxisIndex: 1, data: hist.map((h) => Math.round(h.totalMw)), symbol: 'none', lineStyle: { color: '#e6eef7', type: 'dashed' }, itemStyle: { color: '#e6eef7' } },
      ],
    };
  }, [histKey, key]);
  if (!ov) return <Window title="Competidores" onClose={() => ui.openWindow(null)} testId="competitors-panel"><Empty>El mercado aún no está activo.</Empty></Window>;
  const leader = [...list].sort((a, b) => b.marketShare - a.marketShare)[0];

  return (
    <Window title="Competidores" subtitle="Lo que se sabe en el mercado: registros públicos de permisos, plantas y licitaciones" width={1260} onClose={() => ui.openWindow(null)} testId="competitors-panel">
      <div className="stats-row">
        <Stat label="MW renovables en operación" value={`${fmtNum(ov.totalOperatingMw, 0)} MW`} hint="empresas del juego" />
        <Stat label="Tu cuota" value={fmtPct(ov.player.marketShare, 0)} tone={ov.player.marketShare > 0 ? 'good' : undefined} hint={`${fmtNum(ov.player.operatingMw, 0)} MW`} />
        <Stat label="Líder" value={ov.totalOperatingMw <= 0 ? 'Nadie aún' : leader && leader.marketShare > ov.player.marketShare ? leader.name : ov.player.name} hint={ov.totalOperatingMw <= 0 ? 'ninguna planta en operación' : `${fmtPct(Math.max(leader?.marketShare ?? 0, ov.player.marketShare), 0)} del mercado`} />
        <Stat label="Tu reputación" value={fmtNum(ov.player.reputation, 0)} />
        <Stat label="Competidores activos" value={list.filter((c) => c.status === 'activa').length} hint={list.some((c) => c.status === 'quebrada') ? `${list.filter((c) => c.status === 'quebrada').length} quebrada(s)` : undefined} />
      </div>
      <div className="window-body scroll">
        <div className="comp-grid">
          <div style={{ minWidth: 0 }}>
            <table className="grid-table">
              <thead><tr><th>Empresa</th><th className="num">Cuota</th><th className="num">Operando</th><th className="num">Proyectos visibles</th><th className="num">Licitaciones G/P</th><th className="num">Reputación</th></tr></thead>
              <tbody>
                <tr className="me">
                  <td><span className="swatch" style={{ background: PLAYER_COLOR }} /><b>{ov.player.name}</b> <span className="dim">(tú)</span></td>
                  <td className="num mono">{fmtPct(ov.player.marketShare, 0)}</td><td className="num mono">{fmtNum(ov.player.operatingMw, 0)} MW</td><td className="num dim">—</td><td className="num dim">—</td><td className="num mono">{fmtNum(ov.player.reputation, 0)}</td>
                </tr>
                {list.map((c, i) => (
                  <tr key={c.id} className={`clickable ${sel?.id === c.id ? 'selected' : ''}`} onClick={() => choose(c.id)} data-competitor={c.id}>
                    <td><span className="swatch" style={{ background: rivalColor(i) }} /><b>{c.name}</b>{c.status === 'quebrada' && <> <Pill tone="bad">Quebrada</Pill></>}
                      <div className="dim ellipsis" style={{ fontSize: 11, maxWidth: 330 }}>{c.apparentStrategy}</div></td>
                    <td className="num mono">{fmtPct(c.marketShare, 0)}<div style={{ width: 60, marginLeft: 'auto' }}><Bar value={c.marketShare} color={rivalColor(i)} height={4} /></div></td>
                    <td className="num mono">{fmtNum(c.operatingMw, 0)} MW</td>
                    <td className="num mono">{c.visibleProjects.length}</td>
                    <td className="num mono">{c.bidsWon} / {c.bidsLost}</td>
                    <td className="num mono">{fmtNum(c.reputation, 0)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
            <Section title="Capacidad por empresa" right={<span className="dim" style={{ fontSize: 11 }}>barra llena: en operación · clara: en desarrollo visible · ◆ experiencia acreditada</span>}>{chartOpt && <Chart option={chartOpt} height={250} />}</Section>
            <Section title="Cuota de mercado histórica" right={<span className="dim" style={{ fontSize: 11 }}>MW en operación de las empresas del juego, mensual</span>}>
              {shareOpt && hist!.some((h) => h.totalMw > 0) ? <Chart option={shareOpt} height={240} /> : <div className="dim" style={{ fontSize: 12 }}>Aún ninguna empresa del juego tiene plantas en operación{hist?.length ? ` (${hist.length} meses registrados)` : ''}.</div>}
            </Section>
          </div>
          {sel && <CompetitorCard c={sel} index={list.indexOf(sel)} />}
        </div>
      </div>
    </Window>
  );
}

function CompetitorCard({ c, index }: { c: CompetitorView; index: number }) {
  const winRate = c.bidsWon + c.bidsLost > 0 ? c.bidsWon / (c.bidsWon + c.bidsLost) : null;
  return (
    <div className="side-card" style={{ width: 'auto', borderTop: `3px solid ${rivalColor(index)}` }} data-testid="competitor-card">
      <div style={{ fontSize: 15, fontWeight: 700 }}>{c.name}</div>
      <div style={{ fontSize: 12, margin: '4px 0 6px', color: rivalColor(index) }}>{c.apparentStrategy}</div>
      <div className="dim" style={{ fontSize: 12 }}>{c.description}</div>
      <table className="kv" style={{ marginTop: 8 }}><tbody>
        <tr><td>Estado</td><td>{c.status === 'activa' ? 'Activa' : 'Quebrada'}</td></tr>
        <tr><td>Cuota de mercado</td><td>{fmtPct(c.marketShare, 1)}</td></tr>
        <tr><td>En operación</td><td>{fmtNum(c.operatingMw, 0)} MW</td></tr>
        <tr><td>Experiencia acreditada</td><td>{fmtNum(c.experienceMw, 0)} MW</td></tr>
        <tr><td>Reputación</td><td>{fmtNum(c.reputation, 0)}</td></tr>
        <tr><td>Licitaciones ganadas / perdidas</td><td>{c.bidsWon} / {c.bidsLost}{winRate !== null ? ` (${fmtPct(winRate, 0)})` : ''}</td></tr>
      </tbody></table>
      <div className="stat-label" style={{ margin: '12px 0 4px' }}>Proyectos visibles ({c.visibleProjects.length})</div>
      {c.visibleProjects.length === 0 ? <div className="dim" style={{ fontSize: 12 }}>Ningún proyecto con permisos en trámite todavía (los registros públicos empiezan con los permisos).</div> : (
        <div className="scroll" style={{ maxHeight: 260 }}>
          {c.visibleProjects.map((p) => {
            const st = p.stageId;
            return (
              <button key={p.id} className="choice rival-project" onClick={() => getGlobe()?.flyTo(p.lat, p.lon, 1.2)} title="Ver en el globo">
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div className="row" style={{ gap: 6 }}><b className="ellipsis">{p.name}</b><span className="spacer" /><StageBadge stage={st} label={p.stage} /></div>
                  <div className="dim" style={{ fontSize: 11 }}>{techShort(p.techId)} · {fmtNum(p.mw, 0)} MW</div>
                  {(st === 'construccion' || st === 'puesta_en_marcha') && <div style={{ marginTop: 4 }}><Bar value={p.buildProgress} color={STAGE_COLORS[st]} height={4} /></div>}
                </div>
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}
