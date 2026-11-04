import type { ProjectDetail, StudyOption } from '@voltaje/sim';
import { useUi } from '../store';
import { Empty, Pill, Section } from '../common';
import { fmtDate, fmtDays, fmtMoney, fmtPct } from '../format';
import { cmd } from './ProjectWindow';

const GROUP_LABELS: Record<string, string> = {
  medicion_recurso: 'Medición del recurso', prefactibilidad: 'Prefactibilidad', factibilidad: 'Factibilidad', eia: 'Impacto ambiental', conexion: 'Conexión a la red',
};
const OUTCOME: Record<string, { label: string; tone: 'good' | 'warn' | 'bad' }> = {
  normal: { label: 'Sin sorpresas', tone: 'good' }, peor: { label: 'Peor de lo esperado', tone: 'warn' }, bloqueo: { label: 'Hallazgo', tone: 'bad' },
};

function StatusCell({ s }: { s: StudyOption }) {
  if (s.status === 'completado') { const o = OUTCOME[s.outcome ?? 'normal']; return <Pill tone={o.tone}>{o.label}</Pill>; }
  if (s.status === 'en_curso') return <Pill tone="info">En curso · {fmtDate(s.endDate)}</Pill>;
  if (s.status === 'bloqueado') return <Pill tone="dim">Bloqueado</Pill>;
  return s.required ? <Pill tone="warn">Requerido</Pill> : <Pill tone="dim">Opcional</Pill>;
}

export function StudiesTab({ d }: { d: ProjectDetail }) {
  const cash = useUi((s) => s.game?.company.cashUsd ?? 0);
  const pid = d.summary.id;
  const groups = [...new Set(d.studies.map((s) => s.grupo))];
  const locked = !!d.construction || !!d.operation || !d.summary.active;
  return (
    <>
      {d.findings.length > 0 && (
        <Section title="Hallazgos">
          <table className="grid-table">
            <thead><tr><th>Hallazgo</th><th>Estado</th><th className="num">Costo de mitigar</th><th className="num">Prob. de éxito</th><th /></tr></thead>
            <tbody>
              {d.findings.map((f) => (
                <tr key={f.id}>
                  <td><div style={{ fontWeight: 600 }}>{f.nombre}</div><div className="dim" style={{ fontSize: 11.5 }}>{f.descripcion}</div></td>
                  <td>{f.status === 'abierto' ? <Pill tone="bad">Bloquea el proyecto</Pill> : f.status === 'en_mitigacion' ? <Pill tone="info">Mitigando · {fmtDate(f.endDate)}</Pill> : f.status === 'mitigado' ? <Pill tone="good">Resuelto</Pill> : <Pill tone="bad">Fatal</Pill>}</td>
                  <td className="num mono">{f.mitigable ? fmtMoney(f.costUsd) : '—'}</td>
                  <td className="num mono">{f.mitigable ? fmtPct(f.successProbability, 0) : '—'}</td>
                  <td className="num">
                    {f.status === 'abierto' && f.mitigable && (
                      <button className="primary" disabled={cash < f.costUsd} onClick={() => cmd({ type: 'mitigateFinding', projectId: pid, findingId: f.id })}>Mitigar</button>
                    )}
                    {f.status === 'abierto' && !f.mitigable && <span className="dim">No mitigable: abandonar o vender</span>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </Section>
      )}
      {groups.map((g) => {
        const list = d.studies.filter((s) => s.grupo === g);
        const done = list.some((s) => s.status === 'completado' && s.outcome !== 'bloqueo');
        return (
          <Section key={g} title={GROUP_LABELS[g] ?? g} right={done ? <Pill tone="good">Cumplido</Pill> : list.some((s) => s.required) ? <Pill tone="warn">Pendiente</Pill> : null}>
            <table className="grid-table">
              <thead><tr><th>Estudio</th><th className="num">Costo</th><th className="num">Duración</th><th className="num">σ tras el estudio</th><th>Resultados posibles</th><th>Estado</th><th /></tr></thead>
              <tbody>
                {list.map((s) => (
                  <tr key={s.id} data-study={s.id}>
                    <td style={{ maxWidth: 380 }}>
                      <div style={{ fontWeight: 600 }}>{s.nombre}</div>
                      <div className="dim" style={{ fontSize: 11.5 }}>{s.descripcion}</div>
                      {s.blockers.length > 0 && <div style={{ fontSize: 11.5, color: 'var(--warn)' }}>{s.blockers.join(' ')}</div>}
                    </td>
                    <td className="num mono">{fmtMoney(s.costUsd)}</td>
                    <td className="num mono">{fmtDays(s.durationDays)}</td>
                    <td className="num mono">{s.sigmaAfter !== undefined ? `± ${fmtPct(s.sigmaAfter)}` : '—'}</td>
                    <td><ProbBar parts={[[s.probs.normal, 'var(--good)', 'normal'], [s.probs.peor, 'var(--warn)', 'peor'], [s.probs.bloqueo, 'var(--bad)', 'hallazgo']]} /></td>
                    <td><StatusCell s={s} /></td>
                    <td className="num">
                      {s.status === 'disponible' && !locked && (
                        <button className={s.required ? 'primary' : ''} data-testid={`study-${s.id}`} disabled={cash < s.costUsd}
                          onClick={() => cmd({ type: 'commissionStudy', projectId: pid, studyId: s.id })}>Encargar</button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </Section>
        );
      })}
      {d.studies.length === 0 && <Empty>No hay estudios aplicables.</Empty>}
    </>
  );
}

/** Barra apilada de probabilidades con leyenda corta. */
export function ProbBar({ parts }: { parts: [number, string, string][] }) {
  return (
    <div style={{ minWidth: 150 }}>
      <div className="probbar">{parts.map(([p, c, l]) => <div key={l} style={{ width: `${p * 100}%`, background: c }} title={`${l}: ${fmtPct(p, 0)}`} />)}</div>
      <div className="dim mono" style={{ fontSize: 10.5, marginTop: 2 }}>{parts.filter(([p]) => p > 0).map(([p, , l]) => `${l} ${Math.round(p * 100)}%`).join(' · ')}</div>
    </div>
  );
}
