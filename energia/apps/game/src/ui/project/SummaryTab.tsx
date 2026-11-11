import { MODE_LABEL, MODE_PRODUCT, countryName, fuelName } from '../tech';
import { gameData } from '@voltaje/data';
import type { GameState, Project, ProjectDetail } from '@voltaje/sim';
import { useUi } from '../store';
import { Section, Stat } from '../common';
import { dateOfTick, fmtDate, fmtMoney, fmtNum, fmtPct, MONTHS_SHORT } from '../format';

const DPM = 30.4375;

interface GanttRow { label: string; start: number; end: number; kind: 'hecho' | 'curso' | 'plan' | 'malo'; group: string }

/** Filas del Gantt: lo hecho y en curso (ticks reales del estado) + lo previsto (duraciones base, en secuencia). */
export function ganttRows(g: GameState, p: Project, d: ProjectDetail): GanttRow[] {
  const now = g.tick;
  const rows: GanttRow[] = [{ label: 'Prospección', start: p.createdTick, end: p.createdTick + 3, kind: 'hecho', group: 'desarrollo' }];
  const sName = (id: string) => d.studies.find((x) => x.id === id)?.nombre ?? id;
  const pName = (id: string) => d.permits.find((x) => x.id === id)?.nombre ?? id;
  let studiesEnd = now;
  for (const r of Object.values(p.studies)) {
    rows.push({ label: sName(r.studyId), start: r.startTick, end: r.endTick, kind: r.status === 'en_curso' ? 'curso' : r.outcome === 'bloqueo' ? 'malo' : 'hecho', group: 'estudios' });
    if (r.status === 'en_curso') studiesEnd = Math.max(studiesEnd, r.endTick);
  }
  // estudios requeridos pendientes: uno por grupo
  const groups = new Set<string>();
  for (const s of d.studies) {
    if (!s.required || s.status === 'completado' || s.status === 'en_curso' || groups.has(s.grupo)) continue;
    groups.add(s.grupo);
    rows.push({ label: s.nombre, start: now, end: now + s.durationDays.base, kind: 'plan', group: 'estudios' });
    studiesEnd = Math.max(studiesEnd, now + s.durationDays.base);
  }
  let permitsEnd = studiesEnd;
  for (const r of Object.values(p.permits)) {
    rows.push({ label: pName(r.permitId), start: r.startTick, end: r.endTick, kind: r.status === 'en_tramite' || r.status === 'info_adicional' ? 'curso' : r.status === 'rechazado' ? 'malo' : 'hecho', group: 'permisos' });
    if (r.status === 'en_tramite' || r.status === 'info_adicional') permitsEnd = Math.max(permitsEnd, r.endTick);
  }
  let cursor = studiesEnd;
  for (const x of d.permits) {
    if (x.status !== 'disponible' && x.status !== 'bloqueado') continue;
    rows.push({ label: x.nombre, start: cursor, end: cursor + x.durationDays.base, kind: 'plan', group: 'permisos' });
    cursor += Math.round(x.durationDays.base * 0.6); // parte de los trámites corre en paralelo
    permitsEnd = Math.max(permitsEnd, cursor + x.durationDays.base * 0.4);
  }
  if (p.ppa) rows.push({ label: `PPA: ${d.ppa?.channelName ?? ''}`, start: p.ppa.startTick, end: p.ppa.endTick, kind: p.ppa.status === 'en_proceso' ? 'curso' : p.ppa.status === 'fallido' ? 'malo' : 'hecho', group: 'comercial' });
  let finEnd = permitsEnd;
  if (p.financing) {
    rows.push({ label: 'Cierre financiero', start: p.financing.startTick, end: Math.max(p.financing.endTick, p.financing.startTick + 3), kind: p.financing.status === 'en_proceso' ? 'curso' : p.financing.status === 'fallido' ? 'malo' : 'hecho', group: 'financiacion' });
    finEnd = Math.max(finEnd, p.financing.endTick);
  } else if (!p.construction && !p.operation) {
    rows.push({ label: 'Cierre financiero', start: permitsEnd, end: permitsEnd + 90, kind: 'plan', group: 'financiacion' });
    finEnd = permitsEnd + 90;
  }
  const tech = gameData.simData.technologies[p.techId];
  if (p.construction) {
    const k = p.construction;
    const end = k.startTick + Math.round(k.plannedDays + k.delayDays);
    rows.push({ label: 'Construcción', start: k.startTick, end: p.operation ? p.operation.codTick : Math.max(end, now), kind: p.operation ? 'hecho' : 'curso', group: 'obra' });
    if (k.commissioningStartTick !== undefined) rows.push({ label: 'Puesta en marcha', start: k.commissioningStartTick, end: k.commissioningStartTick + (k.commissioningDays ?? 30), kind: p.operation ? 'hecho' : 'curso', group: 'obra' });
  } else if (!p.operation) {
    const days = tech.construccion_meses.base * DPM;
    rows.push({ label: 'Construcción', start: finEnd, end: finEnd + days, kind: 'plan', group: 'obra' });
    rows.push({ label: 'Puesta en marcha', start: finEnd + days, end: finEnd + days + tech.puesta_en_marcha_dias.base, kind: 'plan', group: 'obra' });
  }
  if (p.operation) rows.push({ label: 'Operación comercial', start: p.operation.codTick, end: Math.max(now, p.operation.codTick + 30), kind: 'curso', group: 'operacion' });
  return rows;
}

const BAR_COLOR: Record<GanttRow['group'], string> = {
  desarrollo: '#94a3b8', estudios: '#60a5fa', permisos: '#a78bfa', comercial: '#2dd4bf', financiacion: '#f472b6', obra: '#fbbf24', operacion: '#4ade80',
};

export function Gantt({ g, rows }: { g: GameState; rows: GanttRow[] }) {
  const t0 = Math.min(...rows.map((r) => r.start));
  const t1 = Math.max(g.tick + 30, ...rows.map((r) => r.end));
  const span = Math.max(60, t1 - t0);
  const x = (t: number) => `${((t - t0) / span) * 100}%`;
  // marcas: cada mes, cada trimestre o cada año según el rango
  const marks: { t: number; label: string }[] = [];
  const step = span > 1500 ? 12 : span > 500 ? 3 : 1;
  const d0 = dateOfTick(g, t0);
  for (let i = 1; i < 200; i++) {
    const m = d0.month - 1 + i;
    if (m % step) continue;
    const y = d0.year + Math.floor(m / 12), mo = (m % 12) + 1;
    const t = t0 + (Date.UTC(y, mo - 1, 1) - Date.UTC(d0.year, d0.month - 1, d0.day)) / 86400000;
    if (t > t1) break;
    marks.push({ t, label: step === 12 || mo === 1 ? String(y) : MONTHS_SHORT[mo - 1] });
  }
  return (
    <div className="gantt" data-testid="gantt">
      <div className="gantt-axis">
        <div />
        <div className="gantt-track">
          {marks.map((m) => <span key={m.t} className="gantt-mark" style={{ left: x(m.t) }}>{m.label}</span>)}
        </div>
      </div>
      {rows.map((r, i) => (
        <div key={i} className="gantt-row">
          <div className="gantt-label ellipsis" title={r.label}>{r.label}</div>
          <div className="gantt-track">
            {marks.map((m) => <span key={m.t} className="gantt-grid" style={{ left: x(m.t) }} />)}
            <div className={`gantt-bar ${r.kind}`} title={`${r.label}: ${fmtDate(dateOfTick(g, r.start))} → ${fmtDate(dateOfTick(g, r.end))}`}
              style={{ left: x(r.start), width: `max(4px, ${((r.end - r.start) / span) * 100}%)`, ['--c' as string]: r.kind === 'malo' ? 'var(--bad)' : BAR_COLOR[r.group] }} />
          </div>
        </div>
      ))}
      <div className="gantt-row gantt-legend">
        <div />
        <div className="row dim" style={{ gap: 14, fontSize: 11 }}>
          <span><i className="lg hecho" /> hecho</span><span><i className="lg curso" /> en curso</span><span><i className="lg plan" /> previsto</span><span><i className="lg malo" /> fallido</span>
          <span className="spacer" /><span><i className="lg today" /> hoy</span>
        </div>
      </div>
      <div className="gantt-today" style={{ left: `calc(var(--gl) + (100% - var(--gl)) * ${(g.tick - t0) / span})` }} />
    </div>
  );
}

export function SummaryTab({ d }: { d: ProjectDetail }) {
  const g = useUi((s) => s.game);
  const p = g?.projects.find((x) => x.id === d.summary.id);
  const e = d.economics;
  const c = d.costs;
  const layer = gameData.layers.find((l) => l.id === d.site.layer);
  return (
    <>
      <div className="stats-row">
        <Stat label="VAN del capital" value={fmtMoney(e?.npvEquityUsd)} tone={e && e.npvEquityUsd < 0 ? 'bad' : 'good'} hint={e ? `ke ${fmtPct(e.costOfEquity)}` : undefined} />
        <Stat label="TIR del capital" value={fmtPct(e?.model.irrEquity)} hint={`TIR proyecto ${fmtPct(e?.model.irrProject)}`} />
        {e?.mode === 'hidrogeno'
          ? <Stat label="LCOH" value={e.lcohUsdKg ? fmtNum(e.lcohUsdKg, 2) : '—'} hint="US$/kg de H₂" />
          : <Stat label={e ? MODE_PRODUCT[e.mode].lcoe : 'LCOE'} value={e ? `${fmtNum(e.lcoeUsdMwh, 1)}` : '—'} hint="US$/MWh (7 % real)" />}
        <Stat label="DSCR mínimo" value={e?.model.minDscr ? fmtNum(e.model.minDscr, 2) : '—'} hint={e?.model.avgDscr ? `medio ${fmtNum(e.model.avgDscr, 2)}` : 'sin deuda'} />
        <Stat label="Precio supuesto" value={e ? fmtNum(e.priceUsdMwh, 0) : '—'} hint={e ? (e.priceAssumption === 'ppa' ? 'US$/MWh · PPA' : 'US$/MWh · spot') : undefined} />
        <Stat label="Prob. de éxito" value={fmtPct(d.successProbability, 0)} tone={d.successProbability < 0.4 ? 'warn' : undefined} />
        <Stat label="Valor de venta" value={fmtMoney(d.saleValueUsd)} hint="tu participación" />
      </div>

      <Section title="Línea de tiempo del proyecto">
        {g && p ? <Gantt g={g} rows={ganttRows(g, p, d)} /> : null}
      </Section>

      <div className="grid3">
        <Section title="Costos">
          <table className="kv"><tbody>
            <tr className="kv-head"><td>Incurridos</td><td>{fmtMoney(c.incurredUsd.total)}</td></tr>
            <tr><td>Desarrollo (capitalizado)</td><td>{fmtMoney(c.incurredUsd.development)}</td></tr>
            <tr><td>Opción de terreno (gasto)</td><td>{fmtMoney(c.incurredUsd.landOptions)}</td></tr>
            <tr><td>Construcción</td><td>{fmtMoney(c.incurredUsd.construction)}</td></tr>
            <tr><td>Intereses de obra</td><td>{fmtMoney(c.incurredUsd.idc)}</td></tr>
            <tr className="kv-head"><td>Por venir</td><td>{fmtMoney(c.upcomingUsd.total)}</td></tr>
            <tr><td>Estudios</td><td>{fmtMoney(c.upcomingUsd.studies)}</td></tr>
            <tr><td>Permisos</td><td>{fmtMoney(c.upcomingUsd.permits)}</td></tr>
            <tr><td>Financiamiento</td><td>{fmtMoney(c.upcomingUsd.financing)}</td></tr>
            <tr><td>Construcción</td><td>{fmtMoney(c.upcomingUsd.construction)}</td></tr>
          </tbody></table>
        </Section>
        {e && e.mode !== 'generacion' ? <ProductSection d={d} /> : <Section title="Recurso y producción">
          <table className="kv"><tbody>
            <tr><td>Recurso P50</td><td>{fmtNum(d.resource.p50, 2)} <span className="dim">{layer?.unidad}</span></td></tr>
            <tr><td>Recurso P90</td><td>{fmtNum(d.resource.p90, 2)} <span className="dim">{layer?.unidad}</span></td></tr>
            <tr><td>Incertidumbre</td><td>± {fmtPct(d.resource.sigma)}</td></tr>
            <tr><td>Fuente</td><td style={{ fontFamily: 'inherit', whiteSpace: 'normal' }}>{d.resource.source === 'celda' ? 'Valor de la celda' : d.studies.find((s) => s.id === d.resource.source)?.nombre ?? d.resource.source}</td></tr>
            <tr><td>FC P50 / P90</td><td>{fmtPct(d.resource.fcP50)} / {fmtPct(d.resource.fcP90)}</td></tr>
            <tr><td>Energía P50</td><td>{fmtNum(d.resource.energyP50MwhYear / 1000, 1)} <span className="dim">GWh/año</span></td></tr>
            <tr><td>Energía P90</td><td>{fmtNum(d.resource.energyP90MwhYear / 1000, 1)} <span className="dim">GWh/año</span></td></tr>
            <tr><td>Temperatura media</td><td>{fmtNum(d.site.temperatureC, 1)} °C</td></tr>
          </tbody></table>
        </Section>}
        <Section title="Inversión estimada">
          <table className="kv"><tbody>
            <tr><td>CAPEX de obra</td><td>{fmtMoney(c.capex.totalUsd)}</td></tr>
            <tr><td>Por kW</td><td>{fmtNum(c.capex.perKwUsd, 0)} <span className="dim">US$/kW</span></td></tr>
            <tr><td>Equipos</td><td>{fmtMoney(c.capex.equipmentUsd)}</td></tr>
            <tr><td>EPC</td><td>{fmtMoney(c.capex.epcUsd)}</td></tr>
            <tr><td>Flete</td><td>{fmtMoney(c.capex.freightUsd)}</td></tr>
            <tr><td>Aranceles</td><td>{fmtMoney(c.capex.tariffsUsd)}</td></tr>
            <tr><td>Otros</td><td>{fmtMoney(c.capex.otherUsd)}</td></tr>
            <tr><td>Deuda supuesta</td><td>{fmtMoney(e?.debtUsd)}</td></tr>
            <tr><td>WACC</td><td>{fmtPct(e?.wacc)}</td></tr>
          </tbody></table>
        </Section>
      </div>

      <div className="grid2">
        <Section title="Historial">
          <div className="timeline scroll">
            {[...d.timeline].reverse().map((t, i) => (
              <div key={i} className={`tl-item ${t.kind}`}>
                <span className="mono dim tl-date">{fmtDate(t.date)}</span>
                <span>{t.text}</span>
              </div>
            ))}
          </div>
        </Section>
        <Section title="Riesgos de la tecnología">
          {d.risks.map((r) => <div key={r.id} style={{ marginBottom: 6 }}><b>{r.nombre}.</b> <span className="dim">{r.descripcion}</span></div>)}
        </Section>
      </div>
    </>
  );
}

/** Fase 4: producto, combustible y despacho de las tecnologías que no son de generación renovable. */
function ProductSection({ d }: { d: ProjectDetail }) {
  const e = d.economics!;
  const g = useUi((s) => s.game);
  const p = g?.projects.find((x) => x.id === d.summary.id);
  const tech = gameData.simData.technologies[p?.techId ?? ''];
  const to = p?.site.extras?.to;
  const usd = (v: number | undefined) => (v === undefined || !Number.isFinite(v) ? '—' : <>{fmtNum(v, 1)} <span className="dim">US$/MWh</span></>);
  return (
    <Section title={MODE_LABEL[e.mode]}>
      <table className="kv"><tbody>
        <tr><td>{MODE_PRODUCT[e.mode].energy}</td><td>{fmtNum(d.resource.energyP50MwhYear / 1000, 1)} <span className="dim">GWh/año</span></td></tr>
        {e.mode === 'termica' && <tr><td>Combustible</td><td style={{ fontFamily: 'inherit' }}>{fuelName(tech?.combustible?.tipo)}</td></tr>}
        {(e.mode === 'termica' || e.mode === 'almacenamiento') && <tr><td>Despacho / uso</td><td>{fmtPct(e.dispatch, 0)}</td></tr>}
        <tr><td>{e.mode === 'almacenamiento' ? 'Costo de la carga' : e.mode === 'transmision' ? 'Costo de las pérdidas' : e.mode === 'hidrogeno' ? 'Electricidad' : 'Combustible'}</td><td>{usd(e.fuelCostUsdMwh)}</td></tr>
        {e.carbonCostUsdMwh > 0 && <tr><td>Carbono</td><td>{usd(e.carbonCostUsdMwh)}</td></tr>}
        {e.co2TPerMwh > 0 && <tr><td>Emisiones</td><td>{fmtNum(e.co2TPerMwh * 1000, 0)} <span className="dim">kgCO₂/MWh</span></td></tr>}
        {e.mode === 'hidrogeno' && <tr><td>LCOH</td><td>{e.lcohUsdKg ? fmtNum(e.lcohUsdKg, 2) : '—'} <span className="dim">US$/kg</span></td></tr>}
        {tech?.almacenamiento && <tr><td>Duración</td><td>{fmtNum(tech.almacenamiento.horas.base, 1)} h · {fmtPct(tech.almacenamiento.eficiencia_ida_vuelta.base, 0)} ida y vuelta</td></tr>}
        {to && <tr><td>Destino</td><td style={{ fontFamily: 'inherit' }}>{countryName(to.countryCode)} · {fmtNum(to.km, 0)} km</td></tr>}
        <tr><td>Precio del producto</td><td>{usd(e.priceUsdMwh)}</td></tr>
        <tr><td>Estimación</td><td style={{ fontFamily: 'inherit', whiteSpace: 'normal' }}>{d.resource.source === 'celda' ? 'Valor de la celda' : d.studies.find((s) => s.id === d.resource.source)?.nombre ?? d.resource.source} (± {fmtPct(d.resource.sigma)})</td></tr>
      </tbody></table>
    </Section>
  );
}
