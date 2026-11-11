import { useEffect, useState } from 'react';
import { gameData } from '@voltaje/data';
import type { OpportunityView } from '@voltaje/sim';
import { sim } from '../../worker/client';
import type { QuoteReply } from '../../worker/protocol';
import { ui, useUi } from '../store';
import { Bar, ConfirmButton, Pill } from '../common';
import { fmtMoney, fmtNum, fmtPct } from '../format';
import { fmtPrice, techName } from './labels';

/** Diálogo «Armar oferta»: tecnología, proyecto, precio, plazo, esfuerzo y proveedores con la cotización del motor. */
export function BidDialog() {
  const id = useUi((s) => s.bidFor);
  const o = useUi((s) => s.views?.business?.opportunities?.find((x) => x.id === s.bidFor));
  if (!id || !o) return null;
  return <BidForm key={o.id} o={o} />;
}

function BidForm({ o }: { o: OpportunityView }) {
  const cash = useUi((s) => s.game?.company.cashUsd ?? 0);
  const tick = useUi((s) => s.game?.tick ?? 0);
  const techs = o.techs.filter((t) => t.modeled && t.unlocked);
  const [techId, setTech] = useState(o.canBid.techId && techs.some((t) => t.id === o.canBid.techId) ? o.canBid.techId : techs[0]?.id ?? '');
  const [projectId, setProject] = useState('');
  const [margin, setMargin] = useState(0.12);
  const [manual, setManual] = useState<number | null>(null);
  const [delivery, setDelivery] = useState<number | null>(null);
  const [effort, setEffort] = useState<'estandar' | 'reforzada'>('estandar');
  const [equipmentId, setEq] = useState('');
  const [epcId, setEpc] = useState('');
  const [r, setR] = useState<QuoteReply | null>(null);
  const q = r?.quote ?? null;

  useEffect(() => {
    let live = true;
    const t = setTimeout(() => {
      sim.quote({
        opportunityId: o.id, techId, projectId: projectId || undefined, marginPct: margin, price: manual ?? undefined, deliveryMonths: delivery ?? undefined,
        effort, equipmentId: equipmentId || undefined, epcId: epcId || undefined,
      }).then((x) => { if (live) setR(x); });
    }, 120);
    return () => { live = false; clearTimeout(t); };
  }, [o.id, techId, projectId, margin, manual, delivery, effort, equipmentId, epcId, tick]);

  // plazo inicial: el realista (sin pasar el máximo de la oportunidad)
  useEffect(() => { if (q && delivery === null) setDelivery(Math.max(3, Math.min(o.codMonths, Math.ceil(q.realisticDeliveryMonths)))); }, [q, delivery, o.codMonths]);
  // si cambia el proyecto o la tecnología, se recalcula el plazo realista
  useEffect(() => setDelivery(null), [projectId, techId]);

  const close = () => ui.set({ bidFor: null });
  const price = manual ?? q?.suggestedPrice ?? 0;
  const months = delivery ?? o.codMonths;
  const w = o.weights;
  const priceScore = q ? 100 * Math.min(1, o.referencePrice / Math.max(1e-6, price)) : 0;
  const deliveryScore = 100 * Math.min(1, o.codMonths / Math.max(1, months));
  const crit = q ? [
    { k: 'Precio', w: w.precio, v: priceScore, hint: 'frente al precio de referencia' },
    { k: 'Técnica', w: w.tecnica, v: q.technicalScore, hint: 'madurez del proyecto, medición, I+D, esfuerzo' },
    { k: 'Experiencia', w: w.experiencia, v: q.experienceScore, hint: 'MW de experiencia y reputación' },
    { k: 'Plazo', w: w.plazo, v: deliveryScore, hint: 'frente al plazo máximo' },
  ] : [];
  const prep = effort === 'reforzada' ? q?.prepCostReforzadaUsd ?? o.prepCostUsd * 2.5 : q?.prepCostUsd ?? o.prepCostUsd;
  const collateral = gameData.simData.clients?.garantias.colateral_frac ?? 0.5;
  const fee = gameData.simData.clients?.garantias.comision_anual ?? 0.015;
  const cashNeed = prep + o.bidBondUsd * collateral;
  const overCeiling = o.ceilingPrice !== undefined && price > o.ceilingPrice;
  const blockers = q?.blockers ?? [];
  const tooFast = q && months < 0.8 * q.realisticDeliveryMonths;
  const eqList = (r?.suppliers ?? []).filter((s) => s.tipo === 'equipos');
  const epcList = (r?.suppliers ?? []).filter((s) => s.tipo === 'epc');
  const ok = !!q?.ok && blockers.length === 0 && !overCeiling && price > 0 && cash >= cashNeed;
  const unit = o.unit;
  const sliderMin = -0.15, sliderMax = 0.6;

  const submit = () => {
    sim.command({
      type: 'submitBid', opportunityId: o.id, techId, price: Math.round(price * 100) / 100, deliveryMonths: months,
      projectId: projectId || undefined, effort, equipmentId: equipmentId || undefined, epcId: epcId || undefined,
    });
    close();
  };

  return (
    <div className="modal-back" onMouseDown={(e) => e.target === e.currentTarget && close()}>
      <div className="panel modal bid-dialog" data-testid="bid-dialog">
        <div className="row" style={{ alignItems: 'flex-start', marginBottom: 10 }}>
          <div style={{ minWidth: 0 }}>
            <div className="window-title">Armar oferta · {o.clientName}</div>
            <div className="dim window-sub">{o.contractLabel} · {fmtNum(o.mw, 0)} MW{o.contract === 'potencia' ? ' firmes' : ''}{o.contract !== 'epc' ? ` · ${o.years} años` : ''} · COD ≤ {o.codMonths} meses · referencia {fmtPrice(o.referencePrice, unit)}{o.ceilingPrice !== undefined ? ` · tope ${fmtPrice(o.ceilingPrice, unit)}` : ' · tope oculto'}</div>
          </div>
          <span className="spacer" />
          <button onClick={close} title="Cerrar (Esc)">✕</button>
        </div>

        <div className="bid-grid">
          <div>
            <div className="field-label">Tecnología</div>
            <div className="row" style={{ gap: 6, flexWrap: 'wrap' }}>
              {o.techs.map((t) => (
                <button key={t.id} className={`choice ${techId === t.id ? 'selected' : ''}`} disabled={!t.modeled || !t.unlocked} onClick={() => { setTech(t.id); setProject(''); setEq(''); setEpc(''); }}
                  title={!t.modeled ? 'Llega en la Fase 4' : !t.unlocked ? 'Investígala en I+D' : undefined}>
                  {techName(t.id)}{!t.modeled ? ' · Fase 4' : !t.unlocked ? ' · sin investigar' : ''}
                </button>
              ))}
            </div>

            {o.contract !== 'epc' && (
              <>
                <div className="field-label">Proyecto</div>
                <select value={projectId} onChange={(e) => setProject(e.target.value)} style={{ width: '100%' }} data-testid="bid-project">
                  <option value="">Proyecto nuevo (asignarlo en ≤ 9 meses tras ganar)</option>
                  {(q?.eligibleProjects ?? []).map((p) => <option key={p.id} value={p.id}>{p.name} · {fmtNum(p.mw, 0)} MW · {p.stage}</option>)}
                </select>
                <div className="hint">{q?.eligibleProjects.length ? 'Vincular un proyecto maduro sube el puntaje técnico y acorta el plazo realista.' : `Ningún proyecto propio encaja (misma tecnología, ${fmtNum(0.9 * (q?.nameplateMw ?? o.mw), 0)}–${fmtNum(1.5 * (q?.nameplateMw ?? o.mw), 0)} MW, sin contrato).`}</div>
              </>
            )}

            <div className="field-label">Esfuerzo de la oferta</div>
            <div className="grid2" style={{ gap: 8 }}>
              {(['estandar', 'reforzada'] as const).map((e) => (
                <button key={e} className={`choice ${effort === e ? 'selected' : ''}`} style={{ display: 'block', textAlign: 'left' }} onClick={() => setEffort(e)} data-effort={e}>
                  <b>{e === 'estandar' ? 'Estándar' : 'Reforzada'}</b> <span className="mono dim">{fmtMoney(e === 'estandar' ? q?.prepCostUsd ?? o.prepCostUsd : q?.prepCostReforzadaUsd ?? o.prepCostUsd * 2.5)}</span>
                  <div className="dim" style={{ fontSize: 11.5 }}>{e === 'estandar' ? 'Documentación base.' : 'Ingeniería y visitas de sitio: +12 puntos técnicos.'}</div>
                </button>
              ))}
            </div>

            <div className="field-label">Proveedores {o.contract === 'epc' ? '(cuentan en el puntaje técnico)' : '(para el costo cotizado)'}</div>
            <div className="grid2" style={{ gap: 8 }}>
              <label>Equipos
                <select value={equipmentId} onChange={(e) => setEq(e.target.value)} style={{ width: '100%', marginTop: 4 }}>
                  <option value="">Por defecto</option>
                  {eqList.map((s) => <option key={s.id} value={s.id}>{s.nombre} · {priceTag(s.priceFactor)} · cal. {Math.round(s.quality * 100)}</option>)}
                </select>
              </label>
              <label>Contratista EPC
                <select value={epcId} onChange={(e) => setEpc(e.target.value)} style={{ width: '100%', marginTop: 4 }}>
                  <option value="">Por defecto</option>
                  {epcList.map((s) => <option key={s.id} value={s.id}>{s.nombre} · {priceTag(s.priceFactor)} · cal. {Math.round(s.quality * 100)}</option>)}
                </select>
              </label>
            </div>

            <div className="field-label">Cotización</div>
            {q && !q.ok && <div className="notice bad">{q.error}</div>}
            <table className="kv"><tbody>
              <tr><td>{o.contract === 'epc' ? 'Costo de la obra' : 'CAPEX estimado'}</td><td>{fmtMoney(q?.capexUsd)} <span className="dim">({fmtNum(q?.capexUsdKw ?? 0, 0)} US$/kW)</span></td></tr>
              {o.contract !== 'epc' && <tr><td>Planta · FC P50 · energía</td><td>{fmtNum(q?.nameplateMw ?? 0, 0)} MW · {fmtPct(q?.fcP50)} · {fmtNum((q?.energyMwhYear ?? 0) / 1000, 1)} GWh/año</td></tr>}
              <tr><td>Tasa de descuento</td><td>{fmtPct(q?.discountRate)}</td></tr>
              <tr><td>Plazo realista</td><td>{q ? `${fmtNum(q.realisticDeliveryMonths, 0)} meses` : '—'}</td></tr>
            </tbody></table>
          </div>

          <div>
            <div className="field-label">Precio</div>
            <div className="price-box">
              <div><div className="stat-label">Equilibrio (VAN = 0)</div><div className="mono price-big">{fmtPrice(q?.breakEvenPrice, unit)}</div></div>
              <div><div className="stat-label">Sugerido</div><div className="mono price-big dim">{fmtPrice(q ? q.breakEvenPrice * (1 + margin) : null, unit)}</div></div>
              <div><div className="stat-label">Tu oferta</div><div className="mono price-big" style={{ color: overCeiling ? 'var(--bad)' : 'var(--accent)' }} data-testid="bid-price">{fmtPrice(price, unit)}</div></div>
            </div>
            <label style={{ display: 'block', marginTop: 8 }}>Margen sobre el equilibrio: <b className="mono">{fmtPct(manual !== null && q ? price / q.breakEvenPrice - 1 : margin, 0)}</b>
              <input type="range" min={sliderMin} max={sliderMax} step={0.01} value={manual !== null && q ? Math.max(sliderMin, Math.min(sliderMax, price / q.breakEvenPrice - 1)) : margin}
                onChange={(e) => { setMargin(+e.target.value); setManual(null); }} data-testid="bid-margin" />
            </label>
            <div className="row" style={{ gap: 8 }}>
              <label style={{ flex: 1 }}>o escribe el precio ({unit.replace('USD', 'US$')})
                <input type="number" step="0.1" min={0} value={manual ?? ''} placeholder={q ? fmtNum(q.suggestedPrice, 2) : ''} onChange={(e) => setManual(e.target.value === '' ? null : Math.max(0, +e.target.value))} />
              </label>
            </div>
            <div className="hint">
              {overCeiling ? <span style={{ color: 'var(--bad)' }}>Sobre el tope publicado: la oferta se descalifica.</span>
                : o.ceilingPrice === undefined ? 'El cliente no publica su precio máximo: una oferta muy alta se descalifica.'
                  : price < (q?.breakEvenPrice ?? 0) ? <span style={{ color: 'var(--warn)' }}>Bajo el equilibrio: si ganas, el proyecto pierde valor.</span> : 'Entre el equilibrio y el tope.'}
            </div>

            <div className="field-label">Plazo de operación comercial: <b className="mono" style={{ color: 'var(--text)' }}>{months} meses</b></div>
            <input type="range" min={3} max={o.codMonths} step={1} value={months} onChange={(e) => setDelivery(+e.target.value)} data-testid="bid-delivery" />
            <div className="hint">{tooFast ? <span style={{ color: 'var(--warn)' }}>Menos del 80 % del plazo realista: −15 puntos técnicos y riesgo de multas.</span> : `Multa si te atrasas: ${fmtMoney(o.requirements.penaltyUsdMwMonth * o.mw)}/mes; a los ${o.requirements.maxDelayMonths} meses se ejecuta la garantía.`}</div>

            <div className="field-label">Puntaje estimado (si los rivales ofertan a la referencia)</div>
            <div className="score-list" data-testid="bid-score">
              {crit.map((c) => (
                <div key={c.k} className="score-row" title={c.hint}>
                  <span>{c.k} <span className="dim">{fmtPct(c.w, 0)}</span></span>
                  <Bar value={c.v / 100} color={c.v >= 75 ? 'var(--good)' : c.v >= 50 ? 'var(--warn)' : 'var(--bad)'} />
                  <span className="mono">{fmtNum(c.v, 0)}</span>
                </div>
              ))}
              <div className="score-row total"><span>Total ponderado</span><span /><span className="mono">{q ? fmtNum(crit.reduce((a, c) => a + c.w * c.v, 0), 1) : '—'}</span></div>
            </div>

            <div className="field-label">Lo que cuesta ofertar</div>
            <table className="kv"><tbody>
              <tr><td>Preparación (a resultados, no se recupera)</td><td>{fmtMoney(prep)}</td></tr>
              <tr><td>Garantía de seriedad</td><td>{fmtMoney(o.bidBondUsd)}</td></tr>
              <tr><td>· caja inmovilizada ({fmtPct(collateral, 0)} de colateral)</td><td>{fmtMoney(o.bidBondUsd * collateral)}</td></tr>
              <tr><td>· comisión ({fmtPct(fee, 1)}/año)</td><td>{fmtMoney((o.bidBondUsd * fee * Math.max(1, o.daysToDeadline + 30)) / 365)}</td></tr>
              <tr><td>Si ganas: garantía de cumplimiento</td><td>{fmtMoney(o.performanceBondUsd)}</td></tr>
              <tr className="kv-head"><td>Caja necesaria hoy</td><td style={{ color: cash < cashNeed ? 'var(--bad)' : undefined }}>{fmtMoney(cashNeed)}</td></tr>
            </tbody></table>
          </div>
        </div>

        {(blockers.length > 0 || cash < cashNeed) && (
          <div className="notice warn" style={{ marginTop: 10 }}><b>No se puede presentar:</b> {[...blockers, ...(cash < cashNeed ? ['Caja insuficiente para la preparación y el colateral.'] : [])].join(' ')}</div>
        )}
        <div className="row" style={{ justifyContent: 'flex-end', marginTop: 12, gap: 8 }}>
          {q && <Pill tone="dim">Se adjudica el {o.awardDate.day}/{o.awardDate.month}/{o.awardDate.year}</Pill>}
          <span className="spacer" />
          <button onClick={close}>Cancelar</button>
          <ConfirmButton className="primary" disabled={!ok} confirm={`¿Ofertar ${fmtPrice(price, unit)} a ${months} meses? Pagas ${fmtMoney(prep)} y se inmovilizan ${fmtMoney(o.bidBondUsd * collateral)}.`} onConfirm={submit}>
            Presentar oferta
          </ConfirmButton>
        </div>
      </div>
    </div>
  );
}

const priceTag = (f: number) => (Math.abs(f - 1) < 0.005 ? 'precio ref.' : `${f > 1 ? '+' : '−'}${Math.round(Math.abs(f - 1) * 100)} %`);
