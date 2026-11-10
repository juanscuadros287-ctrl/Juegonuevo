import { useMemo, useState } from 'react';
import { gameData } from '@voltaje/data';
import type { SupplierCatalog, SupplierCatalogItem } from '@voltaje/sim';
import { ui, useUi } from '../store';
import { Bar, Empty, Section, Stat, Tabs, Window } from '../common';
import { Chart, CHART, baseOption } from '../Chart';
import { fmtNum, fmtPct, monthLabel } from '../format';
import { techShort } from './labels';

type Tab = 'catalogo' | 'precios';
const TYPES: { id: string; label: string }[] = [
  { id: 'equipos', label: 'Equipos (módulos y turbinas)' }, { id: 'inversores', label: 'Inversores (solo FV)' },
  { id: 'epc', label: 'Contratistas EPC' }, { id: 'logistica', label: 'Logística' },
];
const SERIES_COLORS = [CHART.accent, CHART.info, CHART.good, CHART.violet, CHART.bad, '#2dd4bf'];

export function SuppliersPanel() {
  const cat = useUi((s) => s.views?.business?.suppliers);
  const [tab, setTab] = useState<Tab>('catalogo');
  if (!cat) return <Window title="Proveedores" onClose={() => ui.openWindow(null)} testId="suppliers-panel"><Empty>Cargando…</Empty></Window>;
  const sol = cat.techIndices.find((t) => t.techId === 'solar_fv');
  const wind = cat.techIndices.find((t) => t.techId === 'eolica_tierra');
  const chg = (v: number | null) => (v === null ? 'vs. inicio de la partida' : `${v >= 0 ? '+' : '−'}${fmtPct(Math.abs(v), 1)} en 12 meses`);
  return (
    <Window title="Proveedores y cadena de suministro" subtitle="Precios actuales, plazos de entrega, colas de pedidos y tu relación con cada proveedor" width={1300} onClose={() => ui.openWindow(null)} testId="suppliers-panel">
      <div className="stats-row">
        {sol && <Stat label="CAPEX solar FV hoy" value={`${fmtNum(sol.capexUsdKwNow, 0)} US$/kW`} hint={`equipos ×${fmtNum(sol.equipment, 2)}${sol.equipmentChange12m !== null ? ` · ${chg(sol.equipmentChange12m)}` : ''}`} tone={sol.equipmentChange12m !== null ? (sol.equipmentChange12m > 0 ? 'warn' : 'good') : undefined} />}
        {wind && <Stat label="CAPEX eólica hoy" value={`${fmtNum(wind.capexUsdKwNow, 0)} US$/kW`} hint={`equipos ×${fmtNum(wind.equipment, 2)}${wind.equipmentChange12m !== null ? ` · ${chg(wind.equipmentChange12m)}` : ''}`} tone={wind.equipmentChange12m !== null ? (wind.equipmentChange12m > 0 ? 'warn' : 'good') : undefined} />}
        {cat.materials.map((m) => <Stat key={m.id} label={m.nombre} value={`×${fmtNum(m.index, 2)}`} hint={chg(m.change12m)} tone={m.index > 1.1 ? 'warn' : m.index < 0.9 ? 'good' : undefined} />)}
        <Stat label="Demanda mundial" value={`×${fmtNum(cat.demandIndex, 2)}`} hint="alarga plazos y sube precios" tone={cat.demandIndex > 1.1 ? 'warn' : undefined} />
      </div>
      <Tabs<Tab> value={tab} onChange={setTab} tabs={[{ id: 'catalogo', label: 'Catálogo' }, { id: 'precios', label: 'Precios e índices' }]} />
      <div className="window-body scroll">
        {tab === 'catalogo' ? TYPES.map((t) => {
          const list = cat.suppliers.filter((s) => s.tipo === t.id);
          return list.length ? <SupplierGroup key={t.id} title={t.label} list={list} type={t.id} /> : null;
        }) : <PriceCharts cat={cat} />}
      </div>
    </Window>
  );
}

function SupplierGroup({ title, list, type }: { title: string; list: SupplierCatalogItem[]; type: string }) {
  const defs = gameData.simData.suppliers;
  return (
    <Section title={title}>
      <table className="grid-table">
        <thead>
          <tr>
            <th>Proveedor</th><th>Tecnologías</th><th>Origen</th><th className="num">Precio hoy</th><th>Calidad</th><th>Confiabilidad</th>
            {type === 'epc' ? <><th className="num">Plazo de obra</th><th className="num">Sobrecosto/hito</th></>
              : type === 'logistica' ? <><th className="num">Flete</th><th className="num">Plazo de entrega</th></>
                : <><th className="num">Entrega</th><th style={{ width: 130 }}>Cola / capacidad</th></>}
            <th>Relación</th>
          </tr>
        </thead>
        <tbody>
          {list.map((s) => {
            const d = defs[s.id];
            const load = s.capacityMwYear ? s.backlogMw / s.capacityMwYear : 0;
            return (
              <tr key={s.id} data-supplier={s.id}>
                <td style={{ maxWidth: 330 }}><b>{s.nombre}</b><div className="dim" style={{ fontSize: 11.5 }}>{s.descripcion}</div></td>
                <td>{s.tecnologias.map((x) => techShort(x)).join(', ')}</td>
                <td>{s.origen}</td>
                <td className="num mono">
                  <span style={{ color: s.priceFactor < 0.995 ? 'var(--good)' : s.priceFactor > 1.005 ? 'var(--warn)' : undefined }}>{factor(s.priceFactor)}</span>
                  {Math.abs(s.priceFactor - s.basePriceFactor) > 0.004 && <div className="dim" style={{ fontSize: 11 }}>lista {factor(s.basePriceFactor)}</div>}
                </td>
                <td><Score v={s.quality} /></td>
                <td><Score v={s.reliability} /></td>
                {type === 'epc' ? <>
                  <td className="num mono">×{fmtNum(d?.factor_plazo ?? 1, 2)}</td>
                  <td className="num mono">{d?.prob_sobrecosto_hito !== undefined ? fmtPct(d.prob_sobrecosto_hito, 0) : '—'}</td>
                </> : type === 'logistica' ? <>
                  <td className="num mono">{d?.flete_frac !== undefined ? `${fmtPct(d.flete_frac, 1)} de equipos` : '—'}</td>
                  <td className="num mono">×{fmtNum(d?.factor_plazo_entrega ?? 1, 2)}</td>
                </> : <>
                  <td className="num mono">{s.leadDays ? `${s.leadDays} d` : '—'}</td>
                  <td>{s.capacityMwYear ? <><Bar value={Math.min(1, load)} color={load > 0.5 ? 'var(--warn)' : 'var(--info)'} height={5} /><div className="dim mono" style={{ fontSize: 11 }}>{fmtNum(s.backlogMw, 0)} / {fmtNum(s.capacityMwYear, 0)} MW·año</div></> : <span className="dim">—</span>}</td>
                </>}
                <td style={{ fontSize: 12 }}>{s.relation.orders ? <>{s.relation.orders} pedido(s) · {fmtNum(s.relation.mw, 0)} MW<div className="dim" style={{ fontSize: 11 }}>dto. {fmtPct(s.relation.discount, 1)}{s.relation.lateDeliveries ? ` · ${s.relation.lateDeliveries} atraso(s)` : ''}</div></> : <span className="dim">sin pedidos</span>}</td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </Section>
  );
}

const factor = (f: number) => (Math.abs(f - 1) < 0.005 ? 'referencia' : `${f > 1 ? '+' : '−'}${fmtPct(Math.abs(f - 1), 1)}`);

function Score({ v }: { v: number }) {
  return <div className="row" style={{ gap: 6 }}><div style={{ width: 60 }}><Bar value={v} color={v >= 0.85 ? 'var(--good)' : v >= 0.7 ? 'var(--warn)' : 'var(--bad)'} /></div><span className="mono dim" style={{ fontSize: 11 }}>{Math.round(v * 100)}</span></div>;
}

function PriceCharts({ cat }: { cat: SupplierCatalog }) {
  const h = cat.history;
  const key = h.length ? `${h.length}-${h[h.length - 1].year}-${h[h.length - 1].month}` : '0';
  const labels = h.map((x) => monthLabel(x.year, x.month));
  const techs = cat.techIndices.map((t) => t.techId);
  const eqOpt = useMemo(() => {
    const o = baseOption(labels, {});
    return {
      ...o,
      yAxis: { ...(o as { yAxis: object }).yAxis, scale: true, axisLabel: { color: CHART.text, formatter: (v: number) => `×${v.toFixed(2)}` } },
      series: techs.flatMap((t, i) => [
        { name: `Equipos ${techShort(t)}`, type: 'line', data: h.map((x) => +(x.equipment[t] ?? 1).toFixed(4)), symbol: 'none', lineStyle: { color: SERIES_COLORS[i], width: 2 }, itemStyle: { color: SERIES_COLORS[i] } },
        { name: `Obra ${techShort(t)}`, type: 'line', data: h.map((x) => +(x.epc[t] ?? 1).toFixed(4)), symbol: 'none', lineStyle: { color: SERIES_COLORS[i], type: 'dashed' }, itemStyle: { color: SERIES_COLORS[i] } },
      ]),
    };
  }, [key]);
  const matOpt = useMemo(() => {
    const o = baseOption(labels, {});
    return {
      ...o,
      yAxis: { ...(o as { yAxis: object }).yAxis, scale: true, axisLabel: { color: CHART.text, formatter: (v: number) => `×${v.toFixed(2)}` } },
      series: [
        ...cat.materials.map((m, i) => ({ name: m.nombre, type: 'line', data: h.map((x) => +(x.materials[m.id] ?? 1).toFixed(4)), symbol: 'none', lineStyle: { color: SERIES_COLORS[(i + 2) % SERIES_COLORS.length] }, itemStyle: { color: SERIES_COLORS[(i + 2) % SERIES_COLORS.length] } })),
        { name: 'Demanda mundial', type: 'line', data: h.map((x) => +x.demandIndex.toFixed(4)), symbol: 'none', lineStyle: { color: CHART.dim, type: 'dotted', width: 2 }, itemStyle: { color: CHART.dim } },
      ],
    };
  }, [key]);
  if (h.length < 2) return <Empty>El historial de precios empieza a llenarse con el cierre de cada mes. Deja correr el tiempo.</Empty>;
  return (
    <>
      <div className="grid2">
        <Section title="Índice de precios de equipos y obra (1 = inicio)"><Chart option={eqOpt} height={260} /></Section>
        <Section title="Materiales y demanda mundial"><Chart option={matOpt} height={260} /></Section>
      </div>
      <Section title="Índices por tecnología">
        <table className="grid-table">
          <thead><tr><th>Tecnología</th><th className="num">Equipos</th><th className="num">Obra (EPC)</th><th className="num">Cambio en 12 meses</th><th className="num">CAPEX actual</th></tr></thead>
          <tbody>
            {cat.techIndices.map((t) => (
              <tr key={t.techId}>
                <td>{techShort(t.techId)}</td>
                <td className="num mono">×{fmtNum(t.equipment, 3)}</td>
                <td className="num mono">×{fmtNum(t.epc, 3)}</td>
                <td className="num mono" style={{ color: t.equipmentChange12m === null ? undefined : t.equipmentChange12m > 0 ? 'var(--warn)' : 'var(--good)' }}>{t.equipmentChange12m === null ? '—' : `${t.equipmentChange12m >= 0 ? '+' : '−'}${fmtPct(Math.abs(t.equipmentChange12m), 1)}`}</td>
                <td className="num mono">{fmtNum(t.capexUsdKwNow, 0)} US$/kW</td>
              </tr>
            ))}
          </tbody>
        </table>
      </Section>
    </>
  );
}
