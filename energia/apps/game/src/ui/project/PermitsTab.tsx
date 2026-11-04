import { gameData } from '@voltaje/data';
import type { PermitOption, ProjectDetail } from '@voltaje/sim';
import { useUi } from '../store';
import { Pill, Section } from '../common';
import { fmtDate, fmtDays, fmtMoney, fmtPct } from '../format';
import { cmd } from './ProjectWindow';
import { ProbBar } from './StudiesTab';

const STUDY_GROUP: Record<string, string> = { medicion_recurso: 'medición', prefactibilidad: 'prefactibilidad', factibilidad: 'factibilidad', eia: 'EIA', conexion: 'estudio de conexión' };

function statusPill(x: PermitOption) {
  switch (x.status) {
    case 'aprobado': return <Pill tone="good">Aprobado</Pill>;
    case 'en_tramite': return <Pill tone="info">En trámite · {fmtDate(x.endDate)}</Pill>;
    case 'rechazado': return <Pill tone="bad">Rechazado</Pill>;
    case 'bloqueado': return <Pill tone="dim">Bloqueado</Pill>;
    default: return <Pill tone="warn">Disponible</Pill>;
  }
}

/** Permisos como grafo por niveles: cada columna depende de las anteriores (requiere.permisos). */
export function PermitsTab({ d }: { d: ProjectDetail }) {
  const cash = useUi((s) => s.game?.company.cashUsd ?? 0);
  const pid = d.summary.id;
  const code = useUi((s) => s.game?.projects.find((p) => p.id === pid)?.countryCode) ?? gameData.game.pais_inicial;
  const country = gameData.simData.countries[code];
  const defs = new Map(country.permisos.map((p) => [p.id, p]));
  const groupOf = new Map(d.permits.map((p) => [defs.get(p.id)?.grupo ?? p.id, p]));
  const level = new Map<string, number>();
  const depth = (id: string, seen = new Set<string>()): number => {
    if (level.has(id)) return level.get(id)!;
    if (seen.has(id)) return 0;
    seen.add(id);
    const req = defs.get(id)?.requiere.permisos ?? [];
    const lv = req.reduce((m, g) => { const dep = groupOf.get(g); return dep ? Math.max(m, depth(dep.id, seen) + 1) : m; }, 0);
    level.set(id, lv);
    return lv;
  };
  d.permits.forEach((p) => depth(p.id));
  const cols: PermitOption[][] = [];
  for (const p of d.permits) (cols[level.get(p.id)!] ??= []).push(p);
  const locked = !!d.construction || !!d.operation || !d.summary.active;
  const approved = d.permits.filter((p) => p.status === 'aprobado').length;

  return (
    <Section title={`Permisos de ${d.countryName}`} right={<span className="dim">{approved} de {d.permits.length} aprobados</span>}>
      <div className="permit-graph">
        {cols.map((col, i) => (
          <div key={i} className="permit-col">
            <div className="dim permit-col-head">{i === 0 ? 'Primero' : `Nivel ${i + 1}`}</div>
            {col.map((x) => {
              const def = defs.get(x.id);
              const reqP = (def?.requiere.permisos ?? []).map((g) => groupOf.get(g)).filter((v): v is PermitOption => !!v);
              const reqS = def?.requiere.estudios ?? [];
              return (
                <div key={x.id} className={`permit-node ${x.status}`} data-permit={x.id}>
                  <div className="row" style={{ alignItems: 'flex-start' }}>
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ fontWeight: 600 }}>{x.nombre}</div>
                      <div className="dim" style={{ fontSize: 11 }}>{x.autoridad}</div>
                    </div>
                    {statusPill(x)}
                  </div>
                  {(reqS.length > 0 || reqP.length > 0) && (
                    <div className="permit-req">
                      Requiere: {[...reqS.map((g) => STUDY_GROUP[g] ?? g), ...reqP.map((r) => r.nombre)].map((t, k) => <span key={k} className="chip">{t}</span>)}
                    </div>
                  )}
                  <div className="row mono dim" style={{ fontSize: 11.5, gap: 10, margin: '6px 0' }}>
                    <span>{fmtMoney(x.costUsd)}</span><span>{fmtDays(x.durationDays)}</span><span>aprobación {fmtPct(x.approvalProbability, 0)}</span>
                  </div>
                  <ProbBar parts={[[x.probs.aprobado, 'var(--good)', 'aprobado'], [x.probs.info_adicional, 'var(--warn)', 'más info'], [x.probs.rechazado, 'var(--bad)', 'rechazo']]} />
                  {x.infoRequests > 0 && <div style={{ fontSize: 11.5, color: 'var(--warn)', marginTop: 4 }}>La autoridad pidió información adicional {x.infoRequests} {x.infoRequests === 1 ? 'vez' : 'veces'}.</div>}
                  {x.blockers.length > 0 && <div style={{ fontSize: 11.5, color: 'var(--warn)', marginTop: 4 }}>{x.blockers.join(' ')}</div>}
                  {(x.status === 'disponible' || (x.status === 'rechazado' && x.blockers.length === 0)) && !locked && (
                    <button className="primary" style={{ marginTop: 8, width: '100%' }} disabled={cash < x.costUsd} data-testid={`permit-${x.id}`}
                      onClick={() => cmd({ type: 'applyPermit', projectId: pid, permitId: x.id })}>
                      {x.status === 'rechazado' ? 'Volver a solicitar' : 'Solicitar'} ({fmtMoney(x.costUsd)})
                    </button>
                  )}
                  <div className="dim" style={{ fontSize: 11, marginTop: 6 }}>{x.descripcion}</div>
                </div>
              );
            })}
          </div>
        ))}
      </div>
    </Section>
  );
}
