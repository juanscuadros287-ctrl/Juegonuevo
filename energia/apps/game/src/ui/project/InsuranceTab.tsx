import { gameData } from '@voltaje/data';
import type { ProjectDetail } from '@voltaje/sim';
import { useUi } from '../store';
import { ConfirmButton, Empty, Pill, Section, Stat } from '../common';
import { fmtDate, fmtMoney, fmtPct } from '../format';
import { cmd } from './ProjectWindow';

const COVERAGE: Record<'danos' | 'danos_lucro', { label: string; text: string }> = {
  danos: { label: 'Daños materiales', text: 'Paga la reparación de la planta u obra tras una catástrofe (huracán, terremoto, inundación), menos el deducible.' },
  danos_lucro: { label: 'Daños + lucro cesante', text: 'Además de la reparación, paga los ingresos perdidos mientras la planta está fuera de servicio (con el ingreso medio reciente).' },
};

export function InsuranceTab({ d }: { d: ProjectDetail }) {
  const v = useUi((s) => (s.views?.dispatch?.projectId === d.summary.id ? s.views.dispatch : null));
  const cash = useUi((s) => s.game?.company.cashUsd ?? 0);
  const worldEvents = useUi((s) => s.views?.power?.worldActive ?? []);
  if (!v) return <Empty>Solo se aseguran obras en construcción y plantas en operación.</Empty>;
  const ins = v.insurance;
  const s = gameData.simData.world?.seguros;
  const pid = d.summary.id;
  const threats = worldEvents.filter((e) => e.kind === 'desastre' && (!e.countries || e.countries.includes(v.countryCode)));
  const risk = gameData.simData.power?.paises[v.countryCode]?.riesgos ?? {};
  const RISK_LABEL: Record<string, string> = { huracan: 'Huracán', sismo: 'Terremoto', inundacion: 'Inundación', sequia: 'Sequía' };
  return (
    <>
      {!ins.insurable && <Empty>Este proyecto no se puede asegurar todavía: el seguro de catástrofe cubre obras en construcción y plantas en operación.</Empty>}
      <div className="stats-row">
        <Stat label="Seguro" value={ins.current ? (ins.current.active ? 'Vigente' : 'En carencia') : 'Sin seguro'} tone={ins.current?.active ? 'good' : ins.current ? 'warn' : 'bad'} hint={ins.current ? COVERAGE[ins.current.coverage].label : 'riesgo propio'} />
        <Stat label="Valor asegurado" value={fmtMoney(ins.insuredValueUsd)} hint="valor de reposición" />
        <Stat label="Pérdida esperada" value={fmtPct(ins.expectedLossPct / 100, 2)} hint="del valor por año (catástrofes)" />
        <Stat label="Prima vigente" value={ins.current ? fmtMoney(ins.current.premiumUsdYear) : '—'} hint="por año (se paga mensual)" />
        <Stat label="Indemnizaciones" value={fmtMoney(ins.current?.claims.reduce((a, c) => a + c.paidUsd, 0) ?? 0)} hint={`${ins.current?.claims.length ?? 0} siniestro(s)`} />
      </div>
      {threats.length > 0 && <div className="notice bad">Evento activo en {d.countryName}: {threats.map((t) => t.name).join(', ')}. Un seguro contratado ahora no cubre hasta pasada la carencia.</div>}
      <div className="grid2">
        <Section title="Cotizaciones">
          {ins.quotes.length === 0 ? <div className="dim">Sin cotizaciones.</div> : (
            <div style={{ display: 'grid', gap: 8 }} data-testid="insurance-quotes">
              {ins.quotes.map((q) => {
                const cur = ins.current?.coverage === q.coverage;
                const first = q.premiumUsdYear / 12;
                return (
                  <div key={q.coverage} className={`choice ${cur ? 'selected' : ''}`} style={{ display: 'block' }}>
                    <div className="row"><b>{COVERAGE[q.coverage].label}</b><span className="spacer" />{cur && <Pill tone="good">Contratado</Pill>}</div>
                    <div className="dim" style={{ fontSize: 11.5, margin: '3px 0 6px' }}>{COVERAGE[q.coverage].text}</div>
                    <table className="kv"><tbody>
                      <tr><td>Prima anual</td><td>{fmtMoney(q.premiumUsdYear)} ({q.ratePct.toFixed(2)} % del valor)</td></tr>
                      <tr><td>Primera prima (al contratar)</td><td>{fmtMoney(first)}</td></tr>
                      <tr><td>Deducible</td><td>{fmtPct(s?.deducible_frac ?? 0.05, 0)} del daño</td></tr>
                      <tr><td>Carencia</td><td>{s?.espera_dias ?? 30} días</td></tr>
                      {q.coverage === 'danos_lucro' && <tr><td>Lucro cesante</td><td>hasta {s?.lucro_dias_max ?? 180} días</td></tr>}
                    </tbody></table>
                    {!cur && (
                      <div style={{ marginTop: 6 }}>
                        <ConfirmButton className="primary" disabled={cash < first} title={cash < first ? 'Caja insuficiente' : undefined}
                          confirm={ins.current ? `Cambiar la cobertura reinicia la carencia (${s?.espera_dias ?? 30} días).` : `Pagar ${fmtMoney(first)} ahora.`}
                          onConfirm={() => cmd({ type: 'buyInsurance', projectId: pid, coverage: q.coverage })}>{ins.current ? 'Cambiar a esta cobertura' : 'Contratar'}</ConfirmButton>
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </Section>
        <div>
          <Section title="Riesgos naturales del país">
            <table className="kv"><tbody>
              {Object.entries(risk).map(([k, p]) => <tr key={k}><td>{RISK_LABEL[k] ?? k}</td><td>{fmtPct(p, 0)} por año</td></tr>)}
              {Object.keys(risk).length === 0 && <tr><td className="dim">Sin datos de riesgo</td><td /></tr>}
            </tbody></table>
            <div className="dim" style={{ fontSize: 11.5, marginTop: 6 }}>La prima sale de la pérdida esperada del sitio y la tecnología (con un recargo) o de una tasa mínima. Sin seguro, una catástrofe se paga con tu caja.</div>
          </Section>
          {ins.current && (
            <Section title="Póliza vigente">
              <table className="kv"><tbody>
                <tr><td>Cobertura</td><td>{COVERAGE[ins.current.coverage].label}</td></tr>
                <tr><td>Cubre desde</td><td>{fmtDate(ins.current.coveredFrom)}{!ins.current.active && <> <Pill tone="warn">carencia</Pill></>}</td></tr>
                <tr><td>Prima anual</td><td>{fmtMoney(ins.current.premiumUsdYear)}</td></tr>
                {ins.current.claims.map((c, i) => <tr key={i}><td>Siniestro {fmtDate(c.date)}</td><td style={{ color: 'var(--good)' }}>{fmtMoney(c.paidUsd)}</td></tr>)}
              </tbody></table>
              <div style={{ marginTop: 8 }}>
                <ConfirmButton className="danger" confirm="Sin seguro, los daños se pagan con tu caja." onConfirm={() => cmd({ type: 'cancelInsurance', projectId: pid })}>Cancelar seguro</ConfirmButton>
              </div>
            </Section>
          )}
        </div>
      </div>
    </>
  );
}
