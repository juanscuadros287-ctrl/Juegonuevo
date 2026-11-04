import { useEffect, useState } from 'react';
import { gameData } from '@voltaje/data';
import type { FinancingPreview, ProjectDetail } from '@voltaje/sim';
import { sim } from '../../worker/client';
import { ui, useUi } from '../store';
import { Pill, Section, Stat } from '../common';
import { dateOfTick, fmtDate, fmtMoney, fmtNum, fmtPct } from '../format';
import { cmd } from './ProjectWindow';

export function FinancingTab({ d }: { d: ProjectDetail }) {
  const g = useUi((s) => s.game);
  const pid = d.summary.id;
  const code = g?.projects.find((p) => p.id === pid)?.countryCode ?? gameData.game.pais_inicial;
  const fin = gameData.simData.countries[code].finanzas;
  const firstOk = d.lenders.find((l) => l.available)?.id ?? d.lenders[0]?.id ?? 'ninguno';
  const [lenderId, setLender] = useState(firstOk);
  const lender = d.lenders.find((l) => l.id === lenderId);
  const [debt, setDebt] = useState(0.6);
  const [partner, setPartner] = useState(0);
  const [prev, setPrev] = useState<FinancingPreview | null>(null);
  const f = d.financing;
  const debtFrac = lenderId === 'ninguno' ? 0 : Math.min(debt, lender?.maxLeverage ?? 0.7);

  useEffect(() => {
    let live = true;
    const t = setTimeout(() => sim.financePreview(pid, lenderId, debtFrac, partner).then((p) => live && setPrev(p)), 150);
    return () => { live = false; clearTimeout(t); };
  }, [pid, lenderId, debtFrac, partner, d.costs.capex.totalUsd]);

  if (f && f.status !== 'fallido') {
    const ld = d.lenders.find((l) => l.id === f.lenderId);
    return (
      <>
        <div className="stats-row">
          <Stat label="Estado" value={f.status === 'cerrado' ? 'Cierre financiero' : 'Due diligence'} tone={f.status === 'cerrado' ? 'good' : undefined} hint={f.status === 'en_proceso' && g ? `decisión ~${fmtDate(dateOfTick(g, f.endTick))}` : undefined} />
          <Stat label="Presupuesto" value={fmtMoney(f.budgetUsd)} />
          <Stat label="Deuda" value={fmtMoney(f.debtUsd)} hint={f.budgetUsd ? fmtPct(f.debtUsd / f.budgetUsd, 0) + ' del costo' : undefined} />
          <Stat label="Capital" value={fmtMoney(f.equityUsd)} hint={f.partnerShare ? `socio ${fmtPct(f.partnerShare, 0)}` : 'solo la empresa'} />
          <Stat label="Tasa" value={f.rate ? fmtPct(f.rate, 2) : '—'} hint={f.tenorYears ? `${f.tenorYears} años · DSCR ${fmtNum(f.dscrTarget, 2)}` : undefined} />
        </div>
        <Section title="Condiciones">
          <table className="kv" style={{ maxWidth: 620 }}><tbody>
            <tr><td>Prestamista</td><td style={{ fontFamily: 'inherit', whiteSpace: 'normal' }}>{ld?.nombre ?? 'Sin deuda (solo capital)'}</td></tr>
            <tr><td>Deuda pedida</td><td>{fmtPct(f.requestedDebtFraction, 0)}</td></tr>
            <tr><td>Comisiones y asesores</td><td>{fmtMoney(f.feesUsd)}</td></tr>
            <tr><td>Prima de desarrollo del socio</td><td>{fmtMoney(f.partnerPremiumUsd)}</td></tr>
            <tr><td>Tu aporte de capital</td><td>{fmtMoney(f.equityUsd * (1 - f.partnerShare))}</td></tr>
            {d.debt && <><tr><td>Deuda vigente</td><td>{fmtMoney(d.debt.outstandingUsd)}</td></tr><tr><td>Cuota mensual</td><td>{fmtMoney(d.debt.monthlyPayment)}</td></tr><tr><td>Cuotas pagadas</td><td>{d.debt.monthsPaid} / {d.debt.tenorMonths}</td></tr></>}
          </tbody></table>
        </Section>
      </>
    );
  }

  const budget = prev?.budgetUsd ?? d.costs.capex.totalUsd;
  const equity = prev ? prev.equityUsd : budget * (1 - debtFrac);
  const partnerPays = prev ? prev.partnerEquityUsd : equity * partner;
  const youPay = prev ? prev.ownEquityUsd : equity - partnerPays;
  const premium = prev ? prev.partnerPremiumUsd : partnerPays * fin.socio_equity.prima_desarrollo_frac;
  const advisors = prev ? prev.advisorsUsd : fin.prestamistas.find((l) => l.id === lenderId)?.costo_asesores_usd.base ?? 0;
  const cash = g?.company.cashUsd ?? 0;
  const canGo = d.canFinance.ok && (lenderId === 'ninguno' || !!lender?.available) && !prev?.belowLenderMinimum;
  const LIMIT: Record<FinancingPreview['limitedBy'], string> = { apalancamiento: 'limitada por el apalancamiento máximo', pedido: 'lo que pediste', dscr: 'limitada por el DSCR (cobertura del servicio de deuda)', sin_deuda: 'sin deuda' };

  return (
    <>
      {f?.status === 'fallido' && <div className="notice bad">El último intento de financiamiento fracasó{f.failReason ? `: ${f.failReason}` : '.'} Puedes volver a intentarlo.</div>}
      {!d.canFinance.ok && (
        <div className="notice warn">
          <b>Aún no se puede financiar:</b> {d.canFinance.blockers.join(' ')}
          {!d.suppliers.selected && <> <button className="link" onClick={() => ui.set({ projectTab: 'construccion' })}>Elegir proveedores →</button></>}
        </div>
      )}
      <Section title="Prestamista">
        <div className="grid3">
          {d.lenders.map((l) => (
            <button key={l.id} className={`choice ${lenderId === l.id ? 'selected' : ''}`} onClick={() => setLender(l.id)} style={{ display: 'block', textAlign: 'left' }}>
              <div className="row"><b>{l.nombre}</b><span className="spacer" />{l.available ? <Pill tone="good">Elegible</Pill> : <Pill tone="dim">No elegible</Pill>}</div>
              <div className="mono dim" style={{ fontSize: 11.5, margin: '4px 0' }}>{fmtNum(l.ratePct, 2)} % · {l.tenorYears} años · hasta {fmtPct(l.maxLeverage, 0)} · DSCR {fmtNum(l.dscr, 2)}</div>
              <div className="dim" style={{ fontSize: 11.5 }}>{l.reason ?? l.descripcion}</div>
            </button>
          ))}
          <button className={`choice ${lenderId === 'ninguno' ? 'selected' : ''}`} onClick={() => setLender('ninguno')} style={{ display: 'block', textAlign: 'left' }}>
            <div className="row"><b>Solo capital</b><span className="spacer" /><Pill tone="info">Inmediato</Pill></div>
            <div className="mono dim" style={{ fontSize: 11.5, margin: '4px 0' }}>0 % deuda · sin due diligence</div>
            <div className="dim" style={{ fontSize: 11.5 }}>La empresa (y el socio) pagan toda la obra. Más caro de capital, pero sin riesgo bancario.</div>
          </button>
        </div>
      </Section>
      <div className="grid2">
        <Section title="Estructura">
          {lenderId !== 'ninguno' && (
            <label style={{ display: 'block', marginBottom: 10 }}>Deuda pedida: <b className="mono">{fmtPct(debtFrac, 0)}</b> del costo
              <input type="range" min={0.3} max={lender?.maxLeverage ?? 0.7} step={0.05} value={debtFrac} onChange={(e) => setDebt(+e.target.value)} />
            </label>
          )}
          <label style={{ display: 'block' }}>Socio de capital: <b className="mono">{fmtPct(partner, 0)}</b> del capital
            <input type="range" min={0} max={fin.socio_equity.participacion_max} step={0.05} value={partner} onChange={(e) => setPartner(+e.target.value)} />
          </label>
          <div className="dim" style={{ fontSize: 11.5, marginTop: 6 }}>
            El socio aporta su parte del capital y de los sobrecostos, paga una prima de desarrollo del {fmtPct(fin.socio_equity.prima_desarrollo_frac, 0)} de su aporte y cobra su parte de los dividendos.
          </div>
        </Section>
        <Section title="Vista previa del efecto">
          <table className="kv" data-testid="fin-preview"><tbody>
            <tr><td>Presupuesto de obra</td><td>{fmtMoney(budget)}</td></tr>
            <tr><td>Deuda que daría el banco</td><td>{fmtMoney(prev?.debtUsd)}{prev && debtFrac > 0 && <span style={{ color: prev.limitedBy === 'dscr' || prev.limitedBy === 'apalancamiento' ? 'var(--warn)' : 'var(--text-dim)', fontFamily: 'var(--font)', fontSize: 11 }}> · {LIMIT[prev.limitedBy]}</span>}</td></tr>
            {prev && prev.debtUsd > 0 && <tr><td>Tasa · plazo · DSCR exigido</td><td>{fmtNum(prev.ratePct, 2)} % · {prev.tenorYears} años · {fmtNum(prev.dscrTarget, 2)}</td></tr>}
            <tr><td>Capital total</td><td>{fmtMoney(equity)}</td></tr>
            <tr><td>Aporte del socio</td><td>{fmtMoney(partnerPays)}</td></tr>
            <tr className="kv-head"><td>Tu aporte de capital</td><td style={{ color: youPay > cash ? 'var(--bad)' : undefined }}>{fmtMoney(youPay)}</td></tr>
            <tr><td>Prima que recibes del socio</td><td style={{ color: 'var(--good)' }}>{fmtMoney(premium)}</td></tr>
            <tr><td>Asesores (ahora) · comisión de estructuración</td><td>{fmtMoney(lenderId === 'ninguno' ? 0 : advisors)} · {fmtMoney(prev?.structuringFeeUsd ?? 0)}</td></tr>
            {prev && <tr className="kv-head"><td>Caja neta que pone la empresa</td><td style={{ color: prev.netOwnCashUsd > cash ? 'var(--bad)' : undefined }}>{fmtMoney(prev.netOwnCashUsd)}</td></tr>}
            {prev && prev.debtUsd > 0 && <tr><td>Probabilidad de aprobación · due diligence</td><td>{fmtPct(prev.approvalProbability, 0)} · {prev.dueDiligenceDays.base} d</td></tr>}
            <tr><td>TIR del capital</td><td>{fmtPct(prev?.irrEquity)}</td></tr>
            <tr><td>VAN del capital (100 %)</td><td>{fmtMoney(prev?.npvEquityUsd)}</td></tr>
          </tbody></table>
          {prev?.belowLenderMinimum && <div className="notice bad" style={{ fontSize: 12 }}>La deuda dimensionada queda bajo el monto mínimo de {lender?.nombre ?? 'este banco'}: el cierre fracasaría. Prueba otro banco o solo capital.</div>}
          {prev && prev.blockers.length > 0 && d.canFinance.ok && <div className="notice warn" style={{ fontSize: 12 }}>{prev.blockers.join(' ')}</div>}
          {youPay > cash && <div style={{ color: 'var(--warn)', fontSize: 11.5, marginTop: 6 }}>Tu caja ({fmtMoney(cash)}) no cubre tu aporte: la obra se paga mes a mes, pero sin caja la empresa entra en números rojos. Considera un socio o más deuda.</div>}
          <button className="primary" style={{ marginTop: 10, width: '100%' }} disabled={!canGo || cash < (lenderId === 'ninguno' ? 0 : advisors)}
            onClick={() => cmd({ type: 'arrangeFinancing', projectId: pid, lenderId, debtFraction: debtFrac, partnerShare: partner })}>
            {lenderId === 'ninguno' ? 'Cerrar financiamiento con capital' : `Solicitar financiamiento (${fmtMoney(advisors)} de asesores)`}
          </button>
        </Section>
      </div>
    </>
  );
}
