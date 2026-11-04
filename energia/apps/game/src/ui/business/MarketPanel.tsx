import { Fragment, useState } from 'react';
import type { MyBidView, OpportunityView, RankingEntry } from '@voltaje/sim';
import { ui, useUi } from '../store';
import { ConfirmButton, Empty, Pill, Section, Stat, Tabs, Window } from '../common';
import { fmtDate, fmtMoney, fmtNum, fmtPct } from '../format';
import { fmtDaysLeft, fmtPrice, techShort } from './labels';
import { sim } from '../../worker/client';

type Tab = 'abiertas' | 'mias' | 'resultados';

const BID_STATUS: Record<string, { label: string; tone: 'good' | 'bad' | 'warn' | 'info' | 'dim' }> = {
  presentada: { label: 'Presentada', tone: 'info' }, ganada: { label: 'Ganada', tone: 'good' }, perdida: { label: 'Perdida', tone: 'bad' },
  descalificada: { label: 'Descalificada', tone: 'bad' }, retirada: { label: 'Retirada', tone: 'dim' },
};

/** Ícono del tipo de contrato. */
const CONTRACT_ICON: Record<string, string> = { ppa: '⚡', potencia: '▣', epc: '⚒', bot: '⟲' };

export function MarketPanel() {
  const biz = useUi((s) => s.views?.business);
  const pick = useUi((s) => s.pick.market);
  const [tab, setTab] = useState<Tab>('abiertas');
  const all = biz?.opportunities ?? [];
  const open = all.filter((o) => o.status === 'abierta' || o.status === 'evaluacion');
  const closed = all.filter((o) => o.status === 'adjudicada' || o.status === 'desierta').reverse();
  const mine = biz?.myBids ?? [];
  const list = tab === 'resultados' ? closed : open;
  const sel = all.find((o) => o.id === pick) ?? (tab !== 'mias' ? list[0] : undefined);
  const s = biz?.summary;
  const choose = (id: string) => ui.set((st) => ({ pick: { ...st.pick, market: id } }));

  return (
    <Window title="Mercado" subtitle="Licitaciones públicas y solicitudes privadas de clientes" width={1320} onClose={() => ui.openWindow(null)} testId="market-panel">
      <div className="stats-row">
        <Stat label="Oportunidades abiertas" value={open.filter((o) => o.status === 'abierta').length} hint={`${biz?.biddableCount ?? 0} sin oferta tuya`} />
        <Stat label="Ofertas vigentes" value={s?.openBids ?? 0} />
        <Stat label="Ganadas / perdidas" value={`${s?.bidsWon ?? 0} / ${s?.bidsLost ?? 0}`} />
        <Stat label="Reputación" value={s ? fmtNum(s.reputation, 0) : '—'} hint="0–100 · cuenta en el puntaje" tone={s && s.reputation >= 50 ? 'good' : undefined} />
        <Stat label="Experiencia" value={s ? `${fmtNum(s.experienceMw, 0)} MW` : '—'} hint="operados y entregados" />
        <Stat label="Caja en garantías" value={fmtMoney(s?.restrictedCashUsd ?? 0)} hint="colateral inmovilizado" tone={s && s.restrictedCashUsd > 0 ? 'warn' : undefined} />
      </div>
      <Tabs<Tab> value={tab} onChange={setTab} tabs={[
        { id: 'abiertas', label: `Oportunidades (${open.length})` },
        { id: 'mias', label: `Mis ofertas (${mine.length})` },
        { id: 'resultados', label: `Resultados (${closed.length})` },
      ]} />
      <div className="window-body" style={{ display: 'flex', gap: 14, minHeight: 0, overflow: 'hidden' }}>
        {tab === 'mias' ? <MyBids bids={mine} /> : (
          <>
            <div className="scroll" style={{ flex: 1, minWidth: 0 }}>
              {list.length === 0 ? <Empty>{tab === 'abiertas' ? 'No hay oportunidades abiertas ahora. Cada mes los clientes publican nuevas: deja correr el tiempo.' : 'Aún no se adjudicó ninguna oportunidad.'}</Empty> : (
                <OpportunityTable list={list} sel={sel?.id} onPick={choose} closed={tab === 'resultados'} />
              )}
            </div>
            {sel && <OpportunityCard o={sel} />}
          </>
        )}
      </div>
    </Window>
  );
}

function OpportunityTable({ list, sel, onPick, closed }: { list: OpportunityView[]; sel?: string; onPick: (id: string) => void; closed: boolean }) {
  return (
    <table className="grid-table opp-table">
      <thead>
        <tr>
          <th>Cliente</th><th>Contrato</th><th className="num">Tamaño</th><th className="num">{closed ? 'Adjudicada' : 'Cierre'}</th>
          <th className="num">Precio ref.</th><th className="num">Garantía</th><th>{closed ? 'Resultado' : 'Estado'}</th>
        </tr>
      </thead>
      <tbody>
        {list.map((o) => (
          <tr key={o.id} className={`clickable ${sel === o.id ? 'selected' : ''}`} data-opp={o.id} onClick={() => onPick(o.id)}>
            <td style={{ maxWidth: 260 }}>
              <div className="row" style={{ gap: 6 }}>
                <Pill tone={o.kind === 'licitacion_publica' ? 'info' : 'warn'}>{o.kind === 'licitacion_publica' ? 'Pública' : 'Privada'}</Pill>
                <b className="ellipsis">{o.clientName}</b>
              </div>
              <div className="dim ellipsis" style={{ fontSize: 11 }}>{o.clientTypeName}</div>
            </td>
            <td>
              <div className="row" style={{ gap: 5 }}><span className="dim">{CONTRACT_ICON[o.contract]}</span>{o.contractLabel}</div>
              <div className="dim" style={{ fontSize: 11 }}>{o.techs.map((t) => techShort(t.id)).join(' · ')}</div>
            </td>
            <td className="num mono">
              {fmtNum(o.mw, 0)} MW{o.contract === 'potencia' ? ' firmes' : ''}
              <div className="dim" style={{ fontSize: 11 }}>{o.contract === 'epc' ? 'llave en mano' : `${o.years} años`} · COD {o.codMonths} m</div>
            </td>
            <td className="num mono">
              {fmtDate(closed ? o.result?.date ?? o.awardDate : o.deadlineDate)}
              {!closed && <div style={{ fontSize: 11, color: o.daysToDeadline < 15 ? 'var(--warn)' : 'var(--text-dim)' }}>{o.status === 'evaluacion' ? 'en evaluación' : `faltan ${fmtDaysLeft(o.daysToDeadline)}`}</div>}
            </td>
            <td className="num mono">
              {fmtPrice(o.referencePrice, o.unit)}
              <div className="dim" style={{ fontSize: 11 }}>{o.ceilingPrice !== undefined ? `tope ${fmtNum(o.ceilingPrice, 1)}` : 'tope oculto'}</div>
            </td>
            <td className="num mono">{fmtMoney(o.bidBondUsd)}</td>
            <td>{closed ? <ResultCell o={o} /> : <StatusCell o={o} />}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

function StatusCell({ o }: { o: OpportunityView }) {
  if (o.myBid) return <Pill tone={BID_STATUS[o.myBid.status].tone}>Oferta {BID_STATUS[o.myBid.status].label.toLowerCase()}</Pill>;
  if (o.status === 'evaluacion') return <Pill tone="dim">En evaluación</Pill>;
  if (o.canBid.ok) return <Pill tone="good">Puedes ofertar</Pill>;
  return <span className="dim ellipsis" style={{ fontSize: 11.5, display: 'block', maxWidth: 190 }} title={o.canBid.blockers.join(' ')}>✕ {o.canBid.blockers[0]}</span>;
}

function ResultCell({ o }: { o: OpportunityView }) {
  if (o.status === 'desierta') return <Pill tone="dim">Desierta</Pill>;
  const me = o.myBid;
  return (
    <div style={{ fontSize: 12 }}>
      {me && <Pill tone={BID_STATUS[me.status].tone}>{BID_STATUS[me.status].label}{me.rank ? ` · ${me.rank}.º` : ''}</Pill>}
      <div className="dim ellipsis" style={{ maxWidth: 190 }}>{o.result?.winnerName ?? '—'}{o.result?.winnerPrice ? ` · ${fmtNum(o.result.winnerPrice, 1)}` : ''}</div>
    </div>
  );
}

function OpportunityCard({ o }: { o: OpportunityView }) {
  const cash = useUi((s) => s.game?.company.cashUsd ?? 0);
  const closed = o.status === 'adjudicada' || o.status === 'desierta';
  const w = o.weights;
  return (
    <div className="side-card scroll" data-testid="opp-card">
      <div className="row" style={{ alignItems: 'flex-start' }}>
        <div style={{ minWidth: 0 }}>
          <div style={{ fontSize: 15, fontWeight: 700 }}>{o.clientName}</div>
          <div className="dim" style={{ fontSize: 11.5 }}>{o.kindLabel} · {o.clientTypeName}</div>
        </div>
      </div>
      <table className="kv" style={{ marginTop: 8 }}><tbody>
        <tr><td>Contrato</td><td>{o.contractLabel}</td></tr>
        <tr><td>{o.contract === 'potencia' ? 'Potencia firme' : 'Capacidad'}</td><td>{fmtNum(o.mw, 0)} MW{o.contract !== 'epc' ? ` · ${o.years} años` : ''}</td></tr>
        <tr><td>Operación comercial (COD)</td><td>≤ {o.codMonths} meses tras firmar</td></tr>
        <tr><td>Recepción hasta</td><td>{fmtDate(o.deadlineDate)}</td></tr>
        <tr><td>Adjudicación</td><td>{fmtDate(o.awardDate)}</td></tr>
        <tr><td>Precio de referencia</td><td>{fmtPrice(o.referencePrice, o.unit)}</td></tr>
        <tr><td>Precio tope</td><td>{o.ceilingPrice !== undefined ? fmtPrice(o.ceilingPrice, o.unit) : <span className="dim">no publicado</span>}</td></tr>
        <tr><td>Garantía de seriedad</td><td>{fmtMoney(o.bidBondUsd)}</td></tr>
        <tr><td>Garantía de cumplimiento</td><td>{fmtMoney(o.performanceBondUsd)}</td></tr>
        <tr><td>Costo de preparar la oferta</td><td>{fmtMoney(o.prepCostUsd)}</td></tr>
        <tr><td>Multa por atraso</td><td>{fmtMoney(o.requirements.penaltyUsdMwMonth)}/MW-mes</td></tr>
        <tr><td>Atraso máximo</td><td>{o.requirements.maxDelayMonths} meses</td></tr>
      </tbody></table>
      <div className="stat-label" style={{ margin: '10px 0 4px' }}>Requisitos</div>
      <div style={{ fontSize: 12 }}>
        <Req ok={o.techs.some((t) => t.unlocked && t.modeled)}>Tecnología: {o.techs.map((t) => `${techShort(t.id)}${!t.modeled ? ' (Fase 4)' : !t.unlocked ? ' (sin investigar)' : ''}`).join(', ')}</Req>
        <Req ok={o.requirements.minExperienceMw <= 0 || !o.canBid.blockers.some((b) => /experiencia/i.test(b))}>Experiencia mínima: {o.requirements.minExperienceMw ? `${fmtNum(o.requirements.minExperienceMw, 0)} MW` : 'ninguna'}</Req>
        <Req ok={!o.canBid.blockers.some((b) => /patrimonio/i.test(b))}>Patrimonio mínimo: {o.requirements.minEquityUsd ? fmtMoney(o.requirements.minEquityUsd) : 'ninguno'}</Req>
      </div>
      <div className="stat-label" style={{ margin: '10px 0 4px' }}>Criterios de evaluación</div>
      <div className="weights">
        {([['Precio', w.precio], ['Técnica', w.tecnica], ['Experiencia', w.experiencia], ['Plazo', w.plazo]] as const).map(([k, v]) => (
          <div key={k} style={{ flex: v }} title={`${k}: ${fmtPct(v, 0)}`}><span>{k} {fmtPct(v, 0)}</span></div>
        ))}
      </div>
      {closed ? <ResultBlock o={o} /> : o.myBid ? (
        <div className="notice good" style={{ marginTop: 12 }}>
          <b>Tu oferta:</b> {fmtPrice(o.myBid.price, o.unit)} · {o.myBid.deliveryMonths} meses · {techShort(o.myBid.techId)}{o.myBid.projectId ? ` · ${o.myBid.projectId}` : ' · proyecto nuevo'}
          <div className="dim" style={{ fontSize: 11.5 }}>Garantía inmovilizada {fmtMoney(o.myBid.bondUsd)} · se adjudica el {fmtDate(o.awardDate)}</div>
          {o.status === 'abierta' && (
            <div style={{ marginTop: 6 }}>
              <ConfirmButton confirm="Se recupera la garantía; el costo de preparación no." onConfirm={() => sim.command({ type: 'withdrawBid', opportunityId: o.id })}>Retirar oferta</ConfirmButton>
            </div>
          )}
        </div>
      ) : (
        <>
          {!o.canBid.ok && o.status === 'abierta' && <div className="notice warn" style={{ marginTop: 12 }}><b>No puedes ofertar:</b> {o.canBid.blockers.join(' ')}</div>}
          <button className="primary" style={{ width: '100%', marginTop: 12 }} data-testid="open-bid" disabled={o.status !== 'abierta' || !o.techs.some((t) => t.modeled && t.unlocked)}
            onClick={() => ui.set({ bidFor: o.id })} title={cash < o.prepCostUsd ? 'Caja insuficiente' : undefined}>
            Armar oferta…
          </button>
        </>
      )}
    </div>
  );
}

function Req({ ok, children }: { ok: boolean; children: React.ReactNode }) {
  return <div className="row" style={{ gap: 6, alignItems: 'flex-start', marginBottom: 2 }}><span style={{ color: ok ? 'var(--good)' : 'var(--bad)' }}>{ok ? '✓' : '✕'}</span><span>{children}</span></div>;
}

function ResultBlock({ o }: { o: OpportunityView }) {
  const r = o.result;
  if (!r) return null;
  return (
    <>
      <div className="stat-label" style={{ margin: '12px 0 4px' }}>Resultado · {fmtDate(r.date)}</div>
      {o.status === 'desierta' ? <div className="notice warn">Desierta{r.reason ? `: ${r.reason}` : '.'}</div> : <Ranking ranking={r.ranking} unit={o.unit} />}
    </>
  );
}

/** Ranking con precios rivales revelados. */
export function Ranking({ ranking, unit }: { ranking: RankingEntry[]; unit: string }) {
  return (
    <table className="grid-table ranking" data-testid="ranking">
      <thead><tr><th>#</th><th>Ofertante</th><th className="num">Precio</th><th className="num">Plazo</th><th className="num">Puntaje</th></tr></thead>
      <tbody>
        {ranking.map((e, i) => (
          <tr key={`${e.actorId}-${i}`} className={e.actorId === 'jugador' ? 'me' : ''}>
            <td className="mono">{e.disqualified ? '—' : i + 1}</td>
            <td style={{ maxWidth: 170 }}>
              <div className="ellipsis" style={{ fontWeight: e.actorId === 'jugador' ? 700 : undefined }}>{e.actorId === 'jugador' ? `${e.name} (tú)` : e.name}</div>
              {e.external && <div className="dim" style={{ fontSize: 10.5 }}>internacional</div>}
              {e.disqualified && <div style={{ fontSize: 10.5, color: 'var(--bad)' }}>{e.disqualified}</div>}
            </td>
            <td className="num mono">{fmtPrice(e.price, unit)}</td>
            <td className="num mono">{e.deliveryMonths} m</td>
            <td className="num mono">{fmtNum(e.score, 1)}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

function MyBids({ bids }: { bids: MyBidView[] }) {
  const [open, setOpen] = useState<string | null>(bids.find((b) => b.ranking)?.opportunityId ?? null);
  if (!bids.length) return <div style={{ flex: 1 }}><Empty>Todavía no presentaste ofertas. Elige una oportunidad y pulsa «Armar oferta».</Empty></div>;
  return (
    <div className="scroll" style={{ flex: 1 }}>
      <table className="grid-table">
        <thead><tr><th>Cliente</th><th>Contrato</th><th className="num">Tu precio</th><th className="num">Plazo</th><th className="num">Puntaje</th><th>Estado</th><th className="num">Adjudicación</th><th>Ganador</th></tr></thead>
        <tbody>
          {bids.map((b) => (
            <Fragment key={b.opportunityId}>
              <tr className="clickable" data-mybid={b.opportunityId} onClick={() => setOpen(open === b.opportunityId ? null : b.opportunityId)}>
                <td><b>{b.clientName}</b><div className="dim" style={{ fontSize: 11 }}>{fmtNum(b.mw, 0)} MW · {techShort(b.bid.techId)}{b.bid.effort === 'reforzada' ? ' · reforzada' : ''}</div></td>
                <td>{b.contractLabel}</td>
                <td className="num mono">{fmtPrice(b.bid.price, b.unit)}</td>
                <td className="num mono">{b.bid.deliveryMonths} m</td>
                <td className="num mono">{b.bid.score ? fmtNum(b.bid.score.total, 1) : '—'}</td>
                <td><Pill tone={BID_STATUS[b.status].tone}>{BID_STATUS[b.status].label}{b.bid.rank ? ` · ${b.bid.rank}.º` : ''}</Pill></td>
                <td className="num mono">{fmtDate(b.awardDate)}</td>
                <td className="ellipsis" style={{ maxWidth: 220 }}>{b.winnerName ? `${b.winnerName} · ${fmtPrice(b.winnerPrice, b.unit)}` : <span className="dim">—</span>}</td>
              </tr>
              {open === b.opportunityId && b.ranking && (
                <tr><td colSpan={8} style={{ background: 'rgba(255,255,255,.02)' }}>
                  <div className="grid2">
                    <Section title="Ranking (precios revelados)"><Ranking ranking={b.ranking} unit={b.unit} /></Section>
                    {b.bid.score && (
                      <Section title="Tu puntaje por criterio">
                        <table className="kv"><tbody>
                          <tr><td>Precio</td><td>{fmtNum(b.bid.score.price, 1)}</td></tr>
                          <tr><td>Técnica</td><td>{fmtNum(b.bid.score.technical, 1)}</td></tr>
                          <tr><td>Experiencia</td><td>{fmtNum(b.bid.score.experience, 1)}</td></tr>
                          <tr><td>Plazo</td><td>{fmtNum(b.bid.score.delivery, 1)}</td></tr>
                          <tr className="kv-head"><td>Total ponderado</td><td>{fmtNum(b.bid.score.total, 1)}</td></tr>
                        </tbody></table>
                      </Section>
                    )}
                  </div>
                </td></tr>
              )}
            </Fragment>
          ))}
        </tbody>
      </table>
    </div>
  );
}
