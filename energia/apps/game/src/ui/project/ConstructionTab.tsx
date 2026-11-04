import { useEffect, useState } from 'react';
import type { ProjectDetail, SupplierOption } from '@voltaje/sim';
import { useUi } from '../store';
import { Bar, Pill, Section, Stat } from '../common';
import { dateOfTick, fmtDate, fmtMoney, fmtNum, fmtPct } from '../format';
import { cmd } from './ProjectWindow';

function SupplierTable({ title, list, value, onPick, kind, locked }: { title: string; list: SupplierOption[]; value: string; onPick: (id: string) => void; kind: 'equipos' | 'epc'; locked: boolean }) {
  return (
    <Section title={title}>
      <table className="grid-table">
        <thead>
          <tr>
            <th style={{ width: 28 }} /><th>Proveedor</th><th>Origen</th><th className="num">Precio</th><th>Calidad</th><th>Confiabilidad</th>
            {kind === 'equipos' ? <th className="num">Entrega</th> : <><th className="num">Plazo de obra</th><th className="num">Sobrecosto por hito</th></>}
          </tr>
        </thead>
        <tbody>
          {list.map((s) => (
            <tr key={s.id} className={locked ? '' : 'clickable'} onClick={() => !locked && onPick(s.id)} data-supplier={s.id}>
              <td><input type="radio" checked={value === s.id} readOnly disabled={locked} /></td>
              <td style={{ maxWidth: 360 }}><div style={{ fontWeight: 600 }}>{s.nombre}</div><div className="dim" style={{ fontSize: 11.5 }}>{s.descripcion}</div></td>
              <td>{s.origen}</td>
              <td className="num mono" style={{ color: s.priceFactor < 1 ? 'var(--good)' : s.priceFactor > 1 ? 'var(--warn)' : undefined }}>{s.priceFactor === 1 ? 'referencia' : `${s.priceFactor > 1 ? '+' : '−'}${fmtPct(Math.abs(s.priceFactor - 1), 0)}`}</td>
              <td><Score v={s.quality} /></td>
              <td><Score v={s.reliability} /></td>
              {kind === 'equipos'
                ? <td className="num mono">{s.leadDays ? `${s.leadDays} d` : '—'}</td>
                : <><td className="num mono">{s.scheduleFactor ? `×${fmtNum(s.scheduleFactor, 2)}` : '—'}</td><td className="num mono">{s.overrunProb !== undefined ? fmtPct(s.overrunProb, 0) : '—'}</td></>}
            </tr>
          ))}
        </tbody>
      </table>
    </Section>
  );
}

function Score({ v }: { v: number }) {
  return <div className="row" style={{ gap: 6 }}><div style={{ width: 70 }}><Bar value={v} color={v >= 0.85 ? 'var(--good)' : v >= 0.7 ? 'var(--warn)' : 'var(--bad)'} /></div><span className="mono dim" style={{ fontSize: 11 }}>{Math.round(v * 100)}</span></div>;
}

export function ConstructionTab({ d }: { d: ProjectDetail }) {
  const g = useUi((s) => s.game);
  const pid = d.summary.id;
  const sel = d.suppliers.selected;
  const [eq, setEq] = useState(sel?.equipmentId ?? d.suppliers.equipment[0]?.id ?? '');
  const [epc, setEpc] = useState(sel?.epcId ?? d.suppliers.epc[0]?.id ?? '');
  useEffect(() => { if (sel) { setEq(sel.equipmentId); setEpc(sel.epcId); } }, [sel?.equipmentId, sel?.epcId]);
  const k = d.construction;
  const lockedSup = !!k || !!d.operation || d.financing?.status === 'cerrado' || d.financing?.status === 'en_proceso' || !d.summary.active;
  const changed = !sel || sel.equipmentId !== eq || sel.epcId !== epc;

  return (
    <>
      {k && g && (
        <>
          <div className="stats-row">
            <Stat label="Avance de obra" value={fmtPct(k.progress, 0)} hint={k.commissioningStartTick !== undefined ? 'en puesta en marcha' : k.stoppedDays > 0 ? `parada: ${k.stopReason ?? ''}` : undefined} tone={k.stoppedDays > 0 ? 'warn' : undefined} />
            <Stat label="Inicio" value={fmtDate(k.startDate)} />
            <Stat label="Fin previsto" value={fmtDate(k.expectedEndDate)} hint={k.delayDays > 0 ? `${k.delayDays} días de atraso` : 'a tiempo'} tone={k.delayDays > 30 ? 'warn' : undefined} />
            <Stat label="Gastado" value={fmtMoney(k.spentUsd)} hint={`de ${fmtMoney(k.budgetUsd + k.overrunUsd)}`} />
            <Stat label="Sobrecostos" value={fmtMoney(k.overrunUsd)} tone={k.overrunUsd > 0 ? 'bad' : undefined} />
            <Stat label="Equipos" value={k.equipmentArrived ? 'En sitio' : fmtDate(dateOfTick(g, k.equipmentArrivalTick))} hint={k.equipmentLateDays > 0 ? `${k.equipmentLateDays} días tarde` : undefined} tone={k.equipmentLateDays > 0 ? 'warn' : undefined} />
          </div>
          <Section title="Hitos de obra">
            <div style={{ marginBottom: 10 }}><Bar value={k.progress} height={10} color="var(--warn)" /></div>
            <table className="grid-table">
              <thead><tr><th>Hito</th><th className="num">Peso</th><th style={{ width: 260 }}>Avance</th><th>Estado</th></tr></thead>
              <tbody>
                {k.milestones.map((m) => {
                  const pr = Math.max(0, Math.min(1, (k.progress - m.start) / Math.max(1e-6, m.end - m.start)));
                  return (
                    <tr key={m.id}>
                      <td>{m.nombre}</td>
                      <td className="num mono">{fmtPct(m.fraction, 0)}</td>
                      <td><Bar value={m.done ? 1 : pr} color={m.done ? 'var(--good)' : 'var(--warn)'} /></td>
                      <td>{m.done ? <Pill tone="good">Terminado</Pill> : pr > 0 ? <Pill tone="info">En curso</Pill> : <Pill tone="dim">Pendiente</Pill>}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </Section>
        </>
      )}
      {!k && !d.operation && d.summary.active && (
        <div className={`notice ${d.canStartConstruction.ok ? 'good' : 'warn'} row`}>
          <div style={{ flex: 1 }}>
            {d.canStartConstruction.ok ? <><b>Listo para construir.</b> El EPC moviliza la obra y la deuda empieza a desembolsarse mes a mes.</> : <><b>Para iniciar la obra:</b> {d.canStartConstruction.blockers.join(' ')}</>}
          </div>
          <button className="primary" disabled={!d.canStartConstruction.ok} onClick={() => cmd({ type: 'startConstruction', projectId: pid })}>Iniciar construcción</button>
        </div>
      )}
      <SupplierTable title="Proveedor de equipos" list={d.suppliers.equipment} value={eq} onPick={setEq} kind="equipos" locked={lockedSup} />
      <SupplierTable title="Contratista EPC" list={d.suppliers.epc} value={epc} onPick={setEpc} kind="epc" locked={lockedSup} />
      {!lockedSup && (
        <div className="row" style={{ justifyContent: 'flex-end', marginTop: 8 }}>
          {sel && !changed && <span className="dim">Proveedores elegidos. CAPEX: {fmtMoney(d.costs.capex.totalUsd)} ({fmtNum(d.costs.capex.perKwUsd, 0)} US$/kW)</span>}
          <button className="primary" disabled={!changed || !eq || !epc} data-testid="select-suppliers" onClick={() => cmd({ type: 'selectSuppliers', projectId: pid, equipmentId: eq, epcId: epc })}>
            {sel ? 'Cambiar proveedores' : 'Elegir estos proveedores'}
          </button>
        </div>
      )}
      {lockedSup && sel && <div className="dim" style={{ fontSize: 11.5 }}>Los proveedores quedan fijos una vez que el banco evalúa el presupuesto.</div>}
    </>
  );
}
