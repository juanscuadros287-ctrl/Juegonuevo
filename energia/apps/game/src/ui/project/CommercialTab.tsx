import type { ProjectDetail } from '@voltaje/sim';
import { ui, useUi } from '../store';
import { Pill, Section, Stat } from '../common';
import { dateOfTick, fmtDate, fmtMoney, fmtNum, fmtPct } from '../format';
import { cmd } from './ProjectWindow';
import { useState } from 'react';
import { SettlementPicker, type Settlement } from './DispatchTab';

export function CommercialTab({ d }: { d: ProjectDetail }) {
  const g = useUi((s) => s.game);
  const cash = g?.company.cashUsd ?? 0;
  const pid = d.summary.id;
  const ppa = d.ppa;
  const e = d.economics;
  const [settlement, setSettlement] = useState<Settlement>('produccion');
  return (
    <>
      <div className="stats-row">
        <Stat label="Contrato" value={ppa?.status === 'firmado' ? 'PPA firmado' : ppa?.status === 'en_proceso' ? 'En proceso' : 'Sin PPA (spot)'} tone={ppa?.status === 'firmado' ? 'good' : undefined} />
        <Stat label="Precio" value={ppa?.status === 'firmado' ? `${fmtNum(ppa.priceUsdMwh, 1)}` : e ? fmtNum(e.priceUsdMwh, 1) : '—'} hint={ppa?.status === 'firmado' ? `US$/MWh · ${ppa.years} años · indexado ${fmtPct(ppa.indexation)}` : 'US$/MWh · spot capturado'} />
        <Stat label="Energía P50" value={`${fmtNum(d.resource.energyP50MwhYear / 1000, 1)} GWh`} hint="por año" />
        <Stat label="Ingreso anual P50" value={e ? fmtMoney(e.energyP50MwhYear * e.priceUsdMwh) : '—'} />
      </div>
      {d.contractId && (
        <div className="notice good row">
          <span style={{ flex: 1 }}>Este proyecto cumple el contrato <b>{d.contractId}</b> ganado en el mercado: su fecha de operación comercial, multas y garantía están en Contratos.</span>
          <button onClick={() => ui.openPanel('contracts', d.contractId)}>Ver contrato →</button>
        </div>
      )}
      {!d.contractId && !ppa && (
        <div className="notice row" style={{ borderColor: 'var(--panel-border)' }}>
          <span style={{ flex: 1 }} className="dim">También puedes vincular este proyecto a una licitación o solicitud privada del Mercado al armar la oferta.</span>
          <button onClick={() => ui.openWindow('market')}>Ir al mercado →</button>
        </div>
      )}
      {ppa && (
        <Section title="Contrato actual">
          <table className="kv" style={{ maxWidth: 560 }}><tbody>
            <tr><td>Canal</td><td style={{ fontFamily: 'inherit', whiteSpace: 'normal' }}>{ppa.channelName}</td></tr>
            <tr><td>Estado</td><td>{ppa.status === 'firmado' ? <Pill tone="good">Firmado</Pill> : ppa.status === 'en_proceso' ? <Pill tone="info">Resultado el {g ? fmtDate(dateOfTick(g, ppa.endTick)) : ''}</Pill> : <Pill tone="bad">No adjudicado</Pill>}</td></tr>
            {ppa.status === 'firmado' && g && <>
              <tr><td>Precio inicial</td><td>{fmtNum(ppa.priceUsdMwh, 2)} US$/MWh</td></tr>
              <tr><td>Plazo</td><td>{ppa.years} años</td></tr>
              <tr><td>Fecha límite de operación (COD)</td><td>{fmtDate(dateOfTick(g, ppa.codDeadlineTick))}</td></tr>
              <tr><td>Multa por atraso</td><td>{fmtMoney(ppa.penaltyUsdMwMonth)} por MW·mes</td></tr>
            </>}
            <tr><td>Costo de la oferta</td><td>{fmtMoney(ppa.costUsd)}</td></tr>
          </tbody></table>
        </Section>
      )}
      <Section title="Canales de venta de energía">
        {!ppa || ppa.status === 'fallido' ? (
          <div style={{ marginBottom: 10 }}>
            <div className="stat-label" style={{ marginBottom: 4 }}>Modalidad del PPA</div>
            <SettlementPicker value={settlement} onChange={setSettlement} />
          </div>
        ) : null}
        <table className="grid-table">
          <thead><tr><th>Canal</th><th className="num">Precio (US$/MWh)</th><th className="num">Plazo</th><th className="num">Prob. de éxito</th><th className="num">Costo de ofertar</th><th>Disponibilidad</th><th /></tr></thead>
          <tbody>
            {d.ppaChannels.map((c) => (
              <tr key={c.id}>
                <td style={{ maxWidth: 420 }}><div style={{ fontWeight: 600 }}>{c.nombre}</div><div className="dim" style={{ fontSize: 11.5 }}>{c.descripcion}</div></td>
                <td className="num mono">{fmtNum(c.priceUsdMwh.min, 0)}–{fmtNum(c.priceUsdMwh.max, 0)} <span className="dim">(≈{fmtNum(c.priceUsdMwh.base, 0)})</span></td>
                <td className="num mono">{c.years} años</td>
                <td className="num mono">{fmtPct(c.probability, 0)}</td>
                <td className="num mono">{fmtMoney(c.costUsd)}</td>
                <td>{c.available ? <Pill tone="good">Disponible</Pill> : <span style={{ color: 'var(--warn)', fontSize: 12 }}>{c.reason}</span>}</td>
                <td className="num">{c.available && d.summary.active && <button className="primary" disabled={cash < c.costUsd} onClick={() => cmd({ type: 'seekPpa', projectId: pid, channelId: c.id, ...(settlement !== 'produccion' ? { settlement } : {}) })}>Presentar oferta</button>}</td>
              </tr>
            ))}
          </tbody>
        </table>
        <div className="dim" style={{ fontSize: 11.5, marginTop: 8 }}>Sin PPA la planta vende al mercado spot: en promedio paga más pero varía por estación y los bancos prestan menos (DSCR más exigente).</div>
      </Section>
    </>
  );
}
