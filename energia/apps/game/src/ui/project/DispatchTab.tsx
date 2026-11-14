import { useEffect, useMemo, useRef, useState } from 'react';
import { gameData } from '@voltaje/data';
import type { DispatchPolicy, PlantDispatchView, ProjectDetail } from '@voltaje/sim';
import { sim } from '../../worker/client';
import { ui, useUi } from '../store';
import { ConfirmButton, Empty, Pill, Section, Stat } from '../common';
import { Chart, CHART, baseOption } from '../Chart';
import { fmtMoney, fmtNum, fmtPct, monthLabel } from '../format';
import { cmd } from './ProjectWindow';

export type Settlement = 'produccion' | 'bloque' | 'financiero';

/** Modalidades de PPA explicadas (los parámetros salen de power.yaml). */
export function settlementInfo(s: Settlement): { label: string; text: string } {
  const m = gameData.simData.power?.ppa_modalidades;
  if (s === 'bloque') return { label: 'Bloque físico', text: `Comprometes ≈ ${fmtPct(m?.bloque.cobertura ?? 0.9, 0)} de la producción P50 a un precio ≈ ${fmtPct(m?.bloque.prima ?? 0.04, 0)} más alto. Si produces menos, compras la diferencia al spot; el excedente se vende al spot.` };
  if (s === 'financiero') return { label: 'Financiero (por diferencias)', text: `Toda la energía va al spot y se liquida (precio del PPA − spot medio) sobre ≈ ${fmtPct(m?.financiero.cobertura ?? 0.9, 0)} de la producción P50. Te cubre del precio medio, no de la forma horaria (canibalización).` };
  return { label: 'Según producción', text: 'El comprador paga cada MWh producido al precio del contrato. Sin riesgo de volumen ni de precio; es lo que pide un banco.' };
}

/** Selector de modalidad para pedir un PPA (Comercial y Despacho). */
export function SettlementPicker({ value, onChange }: { value: Settlement; onChange: (s: Settlement) => void }) {
  const has = !!gameData.simData.power;
  if (!has) return null;
  return (
    <div className="grid3" style={{ gap: 8 }} data-testid="settlement-picker">
      {(['produccion', 'bloque', 'financiero'] as const).map((s) => {
        const i = settlementInfo(s);
        return (
          <button key={s} className={`choice ${value === s ? 'selected' : ''}`} style={{ display: 'block', textAlign: 'left' }} onClick={() => onChange(s)} data-settlement={s}>
            <b>{i.label}</b>
            <div className="dim" style={{ fontSize: 11.5 }}>{i.text}</div>
          </button>
        );
      })}
    </div>
  );
}

const usd = (v: number | undefined | null, d = 0) => (v === undefined || v === null || !Number.isFinite(v) ? '—' : `${fmtNum(v, d)}`);

/** Un parámetro numérico de la política con «automático» (sin valor). */
function PolicyNumber({ label, hint, value, onChange, min, max, step, unit, auto = 'Automático', fmt, testId }: {
  label: string; hint: string; value: number | undefined; onChange: (v: number | undefined) => void; min: number; max: number; step: number; unit: string; auto?: string; fmt?: (v: number) => string; testId?: string;
}) {
  const on = value !== undefined;
  const v = value ?? (min + max) / 2;
  return (
    <div className="policy-field">
      <div className="row" style={{ gap: 6 }}>
        <label className="row" style={{ gap: 6, color: 'var(--text)', fontSize: 12.5 }}>
          <input type="checkbox" checked={on} onChange={(e) => onChange(e.target.checked ? Math.round(v / step) * step : undefined)} data-testid={testId ? `${testId}-on` : undefined} />
          {label}
        </label>
        <span className="spacer" />
        <span className="mono" style={{ color: on ? 'var(--accent)' : 'var(--text-dim)' }}>{on ? `${fmt ? fmt(v) : fmtNum(v, step < 1 ? 2 : 0)} ${unit}` : auto}</span>
      </div>
      <input type="range" min={min} max={max} step={step} value={v} disabled={!on} onChange={(e) => onChange(Number(e.target.value))} data-testid={testId} />
      <div className="dim" style={{ fontSize: 11 }}>{hint}</div>
    </div>
  );
}

const samePolicy = (a: DispatchPolicy, b: DispatchPolicy) => JSON.stringify(a) === JSON.stringify(Object.fromEntries(Object.entries(b).filter(([, v]) => v !== undefined)));
const cleanPolicy = (p: DispatchPolicy): DispatchPolicy => Object.fromEntries(Object.entries(p).filter(([, v]) => v !== undefined && v !== false)) as DispatchPolicy;

export function DispatchTab({ d }: { d: ProjectDetail }) {
  const v = useUi((s) => (s.views?.dispatch?.projectId === d.summary.id ? s.views.dispatch : null));
  if (!v) return <Empty>Calculando el despacho de la planta…</Empty>;
  if (!v.operating) return <Empty>La planta aún no opera. El despacho, la venta al mercado y los ingresos por fuente aparecen al entrar en operación; el seguro ya se puede contratar en la pestaña Seguro.</Empty>;
  return <DispatchBody d={d} v={v} />;
}

function DispatchBody({ d, v }: { d: ProjectDetail; v: PlantDispatchView }) {
  const pid = d.summary.id;
  const [draft, setDraft] = useState<DispatchPolicy>(v.policy);
  const [preview, setPreview] = useState<PlantDispatchView | null>(null);
  const [day, setDay] = useState<'laborable' | 'finde'>('laborable');
  const policyKey = JSON.stringify(v.policy);
  // al aplicar (o si cambia desde otro lado) el borrador vuelve a la política vigente
  useEffect(() => { setDraft(v.policy); setPreview(null); }, [policyKey]);
  const dirty = !samePolicy(cleanPolicy(draft), v.policy);
  const seq = useRef(0);
  useEffect(() => {
    if (!dirty) { setPreview(null); return; }
    const n = ++seq.current;
    const t = setTimeout(() => { void sim.dispatchPreview(pid, cleanPolicy(draft)).then((r) => { if (n === seq.current) setPreview(r); }); }, 220);
    return () => clearTimeout(t);
  }, [JSON.stringify(draft), dirty, pid]);
  const set = (patch: Partial<DispatchPolicy>) => setDraft((p) => ({ ...p, ...patch }));
  const o = v.policyOptions;
  const isStorage = v.mode === 'almacenamiento';
  const hourly = v.hourly.filter((h) => h.dayType === day);
  const prevHourly = preview?.hourly.filter((h) => h.dayType === day);
  const maxPrice = Math.max(50, ...v.hourly.map((h) => h.priceUsdMwh));
  const priceCap = Math.ceil(maxPrice * 1.3 / 10) * 10;

  const hourKey = `${v.month.label}|${day}|${hourly.map((h) => h.generationMw.toFixed(2)).join(',')}|${prevHourly?.map((h) => `${h.generationMw.toFixed(2)}/${h.chargeMw.toFixed(2)}`).join(',') ?? ''}`;
  const hourOpt = useMemo(() => {
    const base = baseOption(hourly.map((h) => `${h.hour} h`), { unit: ' MW' }) as Record<string, unknown>;
    const series: unknown[] = [
      { name: isStorage ? 'Descarga' : 'Generación', type: 'bar', stack: 'p', data: hourly.map((h) => +h.generationMw.toFixed(2)), itemStyle: { color: CHART.good, borderRadius: [2, 2, 0, 0] } },
    ];
    if (hourly.some((h) => h.chargeMw > 0)) series.push({ name: 'Carga (compra)', type: 'bar', stack: 'p', data: hourly.map((h) => -+h.chargeMw.toFixed(2)), itemStyle: { color: CHART.info } });
    if (prevHourly) {
      series.push({ name: 'Con la política nueva', type: 'line', data: prevHourly.map((h) => +(h.generationMw - h.chargeMw).toFixed(2)), lineStyle: { color: '#e6eef7', type: 'dashed', width: 2 }, itemStyle: { color: '#e6eef7' }, symbol: 'none', step: 'middle' });
    }
    series.push({ name: 'Precio spot', type: 'line', yAxisIndex: 1, data: hourly.map((h) => +h.priceUsdMwh.toFixed(1)), lineStyle: { color: CHART.accent, width: 2 }, itemStyle: { color: CHART.accent }, symbol: 'circle', symbolSize: 3 });
    return {
      ...base,
      grid: { left: 56, right: 60, top: 34, bottom: 28 },
      tooltip: { ...(base.tooltip as object), valueFormatter: undefined },
      yAxis: [(base as { yAxis: object }).yAxis, { type: 'value', splitLine: { show: false }, axisLabel: { color: CHART.text, formatter: (x: number) => `${x} $` } }],
      series,
    };
  }, [hourKey]);

  const revKey = v.revenue.map((r) => `${r.year}${r.month}${Math.round(r.ppaUsd + r.spotUsd)}`).join('|');
  const revOpt = useMemo(() => {
    const o2 = baseOption(v.revenue.map((r) => monthLabel(r.year, r.month)), { money: true });
    const s = (name: string, key: keyof PlantDispatchView['revenue'][number], color: string, neg = false) => ({ name, type: 'bar', stack: 'r', data: v.revenue.map((r) => (neg ? -Math.abs(r[key] as number) : (r[key] as number))), itemStyle: { color } });
    return {
      ...o2,
      series: [
        s('PPA', 'ppaUsd', CHART.good), s('Spot', 'spotUsd', CHART.info), s('Capacidad', 'capacityUsd', CHART.violet), s('Servicios', 'servicesUsd', '#22d3ee'),
        s('Compras al spot', 'purchasesUsd', CHART.bad, true),
        { name: 'Precio capturado', type: 'line', yAxisIndex: 1, data: v.revenue.map((r) => r.captureUsdMwh), lineStyle: { color: CHART.accent }, itemStyle: { color: CHART.accent }, symbol: 'none', connectNulls: true },
      ],
      yAxis: [(o2 as { yAxis: object }).yAxis, { type: 'value', splitLine: { show: false }, axisLabel: { color: CHART.text, formatter: (x: number) => `${x} $/MWh` } }],
    };
  }, [revKey]);

  const plan = v.plan;
  const pp = preview?.plan;
  const r12 = v.revenue12m;
  const total12 = r12.ppaUsd + r12.spotUsd + r12.capacityUsd + r12.servicesUsd - Math.abs(r12.purchasesUsd);
  const diff = (a?: number, b?: number, digits = 0, unit = '') => (a === undefined || b === undefined ? null : (
    <span style={{ color: b > a ? 'var(--good)' : b < a ? 'var(--bad)' : 'var(--text-dim)', fontSize: 11 }}>{b >= a ? '+' : '−'}{fmtNum(Math.abs(b - a), digits)}{unit}</span>
  ));

  return (
    <>
      {v.codBlocked && <div className="notice bad">La planta terminó la puesta en marcha pero no puede operar: faltan permisos para operar (licencia, conexión o acceso a la red). Revisa la pestaña Permisos.</div>}
      <div className="stats-row">
        <Stat label="Venta" value={v.sales.mode === 'ppa' ? 'PPA' : 'Merchant'} hint={v.sales.ppa?.status === 'firmado' ? settlementInfo(v.sales.ppa.settlement).label : 'sin contrato: vende al spot'} tone={v.sales.mode === 'ppa' ? 'good' : undefined} />
        <Stat label={`Spot medio · ${v.month.label}`} value={usd(plan?.avgSpotUsdMwh, 1)} hint="US$/MWh" />
        <Stat label={isStorage ? 'Precio de descarga' : 'Precio capturado'} value={usd(plan?.captureUsdMwh, 1)} hint={plan && plan.avgSpotUsdMwh > 0 ? `${fmtPct(plan.captureUsdMwh / plan.avgSpotUsdMwh, 0)} del spot medio` : 'US$/MWh'} tone={plan && plan.captureUsdMwh < plan.avgSpotUsdMwh * 0.85 ? 'warn' : undefined} />
        {isStorage || plan?.chargeUsdMwh ? <Stat label="Costo de la carga" value={usd(plan?.chargeUsdMwh, 1)} hint="US$/MWh comprado" /> : null}
        <Stat label={isStorage ? 'Uso de la batería' : 'Energía despachada'} value={fmtPct(plan?.genFrac ?? null, 0)} hint={plan?.curtailedFrac ? `vertida ${fmtPct(plan.curtailedFrac, 1)}` : 'de la disponible'} tone={plan && plan.curtailedFrac > 0.05 ? 'warn' : undefined} />
        <Stat label="Ingresos 12 meses" value={fmtMoney(total12)} hint={`PPA ${fmtMoney(r12.ppaUsd)} · spot ${fmtMoney(r12.spotUsd)}`} />
      </div>

      <div className="dispatch-grid">
        <Section title="Reglas de despacho" right={<span className="dim" style={{ fontSize: 11 }}>Vigente: {v.policyText}</span>}>
          <div className="policy-box" data-testid="dispatch-policy">
            {o.storageThresholds && <>
              <PolicyNumber label="Cargar solo bajo" unit="US$/MWh" min={0} max={priceCap} step={1} value={draft.cargarBajo} onChange={(x) => set({ cargarBajo: x })} testId="pol-cargar"
                hint="Compra energía para cargar solo si el spot está por debajo. Automático: carga en las horas más baratas si el arbitraje paga las pérdidas." />
              <PolicyNumber label="Descargar solo sobre" unit="US$/MWh" min={0} max={priceCap} step={1} value={draft.descargarSobre} onChange={(x) => set({ descargarSobre: x })} testId="pol-descargar"
                hint="Vende solo si el spot supera este precio (más margen por MWh, menos ciclos)." />
              <PolicyNumber label="Reserva mínima" unit="" min={0} max={0.9} step={0.05} value={draft.reservaMin} onChange={(x) => set({ reservaMin: x })} fmt={(x) => fmtPct(x, 0)} auto="Sin reserva" testId="pol-reserva"
                hint="Fracción de la energía que no se usa (reserva para contingencias o servicios; alarga la vida)." />
            </>}
            {o.minPrice && (
              <PolicyNumber label="Precio mínimo para producir" unit="US$/MWh" min={-50} max={Math.max(150, Math.round(maxPrice))} step={1} value={draft.precioMinimo} onChange={(x) => set({ precioMinimo: x })} testId="pol-minimo"
                hint={v.mode === 'termica' ? 'No enciende si el spot está bajo este valor (automático: su costo marginal).' : 'No produce si el spot está bajo este valor (automático: 0 sin PPA, no vende con precio negativo).'} />
            )}
            {o.h2MaxPrice && (
              <PolicyNumber label="Compra máxima de electricidad" unit="US$/MWh" min={0} max={priceCap} step={1} value={draft.compraMaxima} onChange={(x) => set({ compraMaxima: x })} testId="pol-compra"
                hint="El electrolizador solo consume si el spot está bajo este precio (automático: el valor del hidrógeno)." />
            )}
            {o.priority && (
              <div className="policy-field">
                <div style={{ fontSize: 12.5, marginBottom: 4 }}>Prioridad con PPA</div>
                <div className="grid2" style={{ gap: 6 }}>
                  {(['ppa', 'spot'] as const).map((k) => (
                    <button key={k} className={`choice ${(draft.prioridad ?? 'ppa') === k ? 'selected' : ''}`} style={{ textAlign: 'left' }} onClick={() => set({ prioridad: k })}>
                      <b>{k === 'ppa' ? 'Cumplir el PPA generando' : 'Comprar al spot si es más barato'}</b>
                      <div className="dim" style={{ fontSize: 11 }}>{k === 'ppa' ? 'Genera aunque el spot esté bajo tu costo.' : 'Apaga y compra en las horas baratas; cobra el PPA igual.'}</div>
                    </button>
                  ))}
                </div>
              </div>
            )}
            {o.ancillary && (
              <div className="policy-field">
                <label className="row" style={{ gap: 6, color: 'var(--text)', fontSize: 12.5 }}>
                  <input type="checkbox" checked={!!draft.servicios} onChange={(e) => set({ servicios: e.target.checked || undefined, fraccionServicios: e.target.checked ? draft.fraccionServicios ?? 0.3 : undefined })} data-testid="pol-servicios" />
                  Ofrecer servicios complementarios (reserva y regulación)
                  <span className="spacer" />
                  {draft.servicios && <span className="mono" style={{ color: 'var(--accent)' }}>{fmtPct(draft.fraccionServicios ?? 0.3, 0)} de la potencia</span>}
                </label>
                <input type="range" min={0.05} max={0.8} step={0.05} value={draft.fraccionServicios ?? 0.3} disabled={!draft.servicios} onChange={(e) => set({ fraccionServicios: Number(e.target.value) })} data-testid="pol-fraccion" />
                <div className="dim" style={{ fontSize: 11 }}>Se cobra por MW-hora reservado{plan?.servicesUsdMwH ? ` (≈ ${fmtNum(plan.servicesUsdMwH, 1)} US$/MW-h)` : ''}; esa potencia deja de vender energía. Si los actores ofrecen más que el requerimiento, el pago se diluye.</div>
              </div>
            )}
            {!o.storageThresholds && !o.minPrice && !o.h2MaxPrice && !o.priority && !o.ancillary && <div className="dim">Esta tecnología no tiene reglas configurables: produce todo lo que puede.</div>}
            <div className="row" style={{ marginTop: 10, gap: 6 }}>
              <button className="primary" disabled={!dirty} onClick={() => cmd({ type: 'setDispatchPolicy', projectId: pid, policy: cleanPolicy(draft) })} data-testid="apply-policy">Aplicar reglas</button>
              <button disabled={!dirty} onClick={() => setDraft(v.policy)}>Descartar</button>
              <span className="spacer" />
              <button disabled={Object.keys(v.policy).length === 0 && Object.keys(cleanPolicy(draft)).length === 0} onClick={() => setDraft({})} title="Despacho automático por precio">Automático</button>
            </div>
          </div>
          {dirty && (
            <div className="policy-preview" data-testid="policy-preview">
              <div className="stat-label" style={{ marginBottom: 4 }}>Vista previa del mes con las reglas nuevas</div>
              {!pp ? <div className="dim">Calculando…</div> : (
                <table className="kv"><tbody>
                  <tr><td>{isStorage ? 'Uso de la batería' : 'Energía despachada'}</td><td>{fmtPct(plan?.genFrac ?? 0, 0)} → <b>{fmtPct(pp.genFrac, 0)}</b> {diff((plan?.genFrac ?? 0) * 100, pp.genFrac * 100, 0, ' pp')}</td></tr>
                  <tr><td>{isStorage ? 'Precio de descarga' : 'Precio capturado'}</td><td>{usd(plan?.captureUsdMwh, 1)} → <b>{usd(pp.captureUsdMwh, 1)}</b> US$/MWh {diff(plan?.captureUsdMwh, pp.captureUsdMwh, 1)}</td></tr>
                  {(isStorage || pp.chargeUsdMwh > 0) && <tr><td>Costo de la carga</td><td>{usd(plan?.chargeUsdMwh, 1)} → <b>{usd(pp.chargeUsdMwh, 1)}</b> US$/MWh</td></tr>}
                  {(pp.servicesFrac > 0 || (plan?.servicesFrac ?? 0) > 0) && <tr><td>Potencia en servicios</td><td>{fmtPct(plan?.servicesFrac ?? 0, 0)} → <b>{fmtPct(pp.servicesFrac, 0)}</b></td></tr>}
                  {(pp.curtailedFrac > 0 || (plan?.curtailedFrac ?? 0) > 0) && <tr><td>Vertimiento</td><td>{fmtPct(plan?.curtailedFrac ?? 0, 1)} → <b>{fmtPct(pp.curtailedFrac, 1)}</b></td></tr>}
                  <tr><td>Reglas</td><td style={{ whiteSpace: 'normal', fontFamily: 'inherit' }}>{preview?.policyText}</td></tr>
                </tbody></table>
              )}
            </div>
          )}
        </Section>
        <Section title={`Perfil horario típico · ${v.month.label}`} right={
          <span className="row" style={{ gap: 4 }}>
            <button className={day === 'laborable' ? 'active' : ''} onClick={() => setDay('laborable')}>Laborable</button>
            <button className={day === 'finde' ? 'active' : ''} onClick={() => setDay('finde')}>Fin de semana</button>
          </span>}>
          <Chart option={hourOpt} height={300} />
          <div className="dim" style={{ fontSize: 11 }}>MW promedio por hora del día tipo; {isStorage ? 'la carga se muestra bajo cero' : 'la producción depende del recurso y de las reglas'}. {prevHourly ? 'La línea discontinua es la vista previa con las reglas nuevas.' : ''}</div>
        </Section>
      </div>

      <div className="dispatch-grid">
        <Section title="Ingresos por fuente (24 meses)">
          {v.revenue.length === 0 ? <Empty>Aún no hay meses cerrados en operación.</Empty> : <Chart option={revOpt} height={240} />}
          <table className="grid-table" style={{ marginTop: 6 }}>
            <thead><tr><th>Últimos 12 meses</th><th className="num">PPA</th><th className="num">Spot</th><th className="num">Capacidad</th><th className="num">Servicios</th><th className="num">Compras</th><th className="num">Neto</th></tr></thead>
            <tbody><tr>
              <td className="dim">US$</td>
              <td className="num mono">{fmtMoney(r12.ppaUsd)}</td><td className="num mono">{fmtMoney(r12.spotUsd)}</td><td className="num mono">{fmtMoney(r12.capacityUsd)}</td>
              <td className="num mono">{fmtMoney(r12.servicesUsd)}</td><td className="num mono" style={{ color: r12.purchasesUsd ? 'var(--bad)' : undefined }}>{fmtMoney(-Math.abs(r12.purchasesUsd))}</td>
              <td className="num mono"><b>{fmtMoney(total12)}</b></td>
            </tr></tbody>
          </table>
        </Section>
        <SalesSection d={d} v={v} />
      </div>
    </>
  );
}

/** PPA vs merchant: terminar el PPA vigente o buscar uno con su modalidad. */
function SalesSection({ d, v }: { d: ProjectDetail; v: PlantDispatchView }) {
  const pid = d.summary.id;
  const cash = useUi((s) => s.game?.company.cashUsd ?? 0);
  const [settlement, setSettlement] = useState<Settlement>('produccion');
  const ppa = v.sales.ppa;
  const signed = ppa?.status === 'firmado';
  const channels = d.ppaChannels;
  return (
    <Section title="Venta de la energía: PPA o merchant">
      {signed && ppa ? (
        <>
          <table className="kv"><tbody>
            <tr><td>Contrato</td><td style={{ whiteSpace: 'normal', fontFamily: 'inherit' }}>{d.ppa?.channelName ?? ppa.channelId}</td></tr>
            <tr><td>Modalidad</td><td>{settlementInfo(ppa.settlement).label}</td></tr>
            <tr><td>Precio</td><td>{fmtNum(ppa.priceUsdMwh, 1)} US$/MWh</td></tr>
            {ppa.committedMwhYear !== undefined && <tr><td>Volumen comprometido</td><td>{fmtNum(ppa.committedMwhYear / 1000, 1)} GWh/año</td></tr>}
            {ppa.yearsLeft !== undefined && <tr><td>Años restantes</td><td>{fmtNum(ppa.yearsLeft, 1)}</td></tr>}
            <tr><td>Spot medio del mes</td><td>{usd(v.plan?.avgSpotUsdMwh, 1)} US$/MWh</td></tr>
          </tbody></table>
          <div className="dim" style={{ fontSize: 11.5, margin: '6px 0' }}>{settlementInfo(ppa.settlement).text}</div>
          {ppa.canTerminate ? (
            <div className="notice warn row">
              <span style={{ flex: 1 }}>Terminar el PPA pasa la planta a merchant (spot). Penalidad: <b>{fmtMoney(ppa.terminationPenaltyUsd)}</b> (lo mayor entre {gameData.simData.power?.terminacion_ppa_meses ?? 12} meses de ingresos del contrato y lo que pierde el comprador). Un comprador de la planta pagaría menos por ella sin contrato.</span>
              <ConfirmButton className="danger" disabled={(ppa.terminationPenaltyUsd ?? 0) > cash} title={(ppa.terminationPenaltyUsd ?? 0) > cash ? 'Caja insuficiente' : undefined}
                confirm={`¿Pagar ${fmtMoney(ppa.terminationPenaltyUsd)} y vender al spot?`} onConfirm={() => cmd({ type: 'terminatePpa', projectId: pid })}>Terminar PPA</ConfirmButton>
            </div>
          ) : <div className="dim" style={{ fontSize: 11.5 }}>Este PPA viene de una licitación: terminarlo sería incumplir el contrato.</div>}
        </>
      ) : (
        <>
          <div className="notice row" style={{ borderColor: 'var(--panel-border)' }}>
            <span style={{ flex: 1 }}>{ppa?.status === 'en_proceso' ? <>Hay un PPA en proceso ({settlementInfo(ppa.settlement).label.toLowerCase()}). Mientras tanto la planta vende al spot.</> : <>La planta es <b>merchant</b>: vende todo al spot horario. Gana en meses caros y pierde en los baratos; un comprador la valora con descuento (≈ {fmtMoney(v.sales.saleValueUsd)}{v.sales.merchantDiscount ? ', con descuento merchant' : ''}).</>}</span>
          </div>
          {ppa?.status !== 'en_proceso' && (
            <>
              <div className="stat-label" style={{ margin: '8px 0 4px' }}>Modalidad del PPA a buscar</div>
              <SettlementPicker value={settlement} onChange={setSettlement} />
              <table className="grid-table" style={{ marginTop: 8 }}>
                <thead><tr><th>Canal</th><th className="num">Precio</th><th className="num">Prob.</th><th className="num">Costo</th><th /></tr></thead>
                <tbody>
                  {channels.map((c) => (
                    <tr key={c.id}>
                      <td><b>{c.nombre}</b><div className="dim" style={{ fontSize: 11 }}>{c.years} años{c.available ? '' : ` · ${c.reason}`}</div></td>
                      <td className="num mono">≈ {fmtNum(c.priceUsdMwh.base, 0)}</td>
                      <td className="num mono">{fmtPct(c.probability, 0)}</td>
                      <td className="num mono">{fmtMoney(c.costUsd)}</td>
                      <td className="num">{c.available && <button className="primary" disabled={cash < c.costUsd} onClick={() => cmd({ type: 'seekPpa', projectId: pid, channelId: c.id, settlement })} data-seek={c.id}>Buscar PPA</button>}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </>
          )}
        </>
      )}
      <div className="row" style={{ marginTop: 8 }}>
        <span className="dim" style={{ fontSize: 11.5, flex: 1 }}>Precios del mercado de {d.countryName}: curva de oferta, previsión y clima.</span>
        <button onClick={() => ui.openPowerMarket(v.countryCode)}>Mercado eléctrico →</button>
      </div>
      {!signed && ppa?.status !== 'en_proceso' && channels.length === 0 && <Pill tone="dim">Sin canales de PPA en este país</Pill>}
    </Section>
  );
}
