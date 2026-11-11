import { useState } from 'react';
import { gameData } from '@voltaje/data';
import { nameplateMw, type ContractView } from '@voltaje/sim';
import { sim } from '../../worker/client';
import { ui, useUi } from '../store';
import { Bar, ConfirmButton, Empty, Pill, Section, Stat, StageBadge, Window } from '../common';
import { fmtDate, fmtMoney, fmtNum, fmtPct } from '../format';
import { fmtDaysLeft, fmtPrice, techShort } from './labels';

/** Arreglo vacío estable (useSyncExternalStore exige la misma referencia si no hay cambios). */
const EMPTY: never[] = [];

const STATUS_TONE: Record<string, 'good' | 'bad' | 'warn' | 'info' | 'dim'> = {
  sin_proyecto: 'warn', en_desarrollo: 'info', operando: 'good', cumplido: 'good', incumplido: 'bad', cedido: 'dim',
};

export function ContractsPanel() {
  const list = useUi((s) => s.views?.business?.contracts ?? EMPTY);
  const pick = useUi((s) => s.pick.contracts);
  const [showAll, setShowAll] = useState(false);
  const shown = list.filter((k) => showAll || k.active);
  const sel = list.find((k) => k.id === pick) ?? shown[0];
  const active = list.filter((k) => k.active);
  const bonds = active.reduce((a, k) => a + k.bondUsd, 0);
  const penalties = list.reduce((a, k) => a + k.penaltiesUsd, 0);
  const revenue = list.reduce((a, k) => a + k.revenueUsd, 0);
  const late = active.filter((k) => k.late).length;
  const choose = (id: string) => ui.set((s) => ({ pick: { ...s.pick, contracts: id } }));

  return (
    <Window title="Contratos" subtitle="Obligaciones con clientes: fechas de operación comercial, garantías y multas" width={1260} onClose={() => ui.openWindow(null)} testId="contracts-panel">
      <div className="stats-row">
        <Stat label="Contratos activos" value={active.length} />
        <Stat label="Sin proyecto asignado" value={active.filter((k) => k.status === 'sin_proyecto').length} tone={active.some((k) => k.status === 'sin_proyecto') ? 'warn' : undefined} />
        <Stat label="Atrasados" value={late} tone={late ? 'bad' : undefined} />
        <Stat label="Garantías vigentes" value={fmtMoney(bonds)} />
        <Stat label="Multas pagadas" value={fmtMoney(penalties)} tone={penalties ? 'bad' : undefined} />
        <Stat label="Ingresos por contratos" value={fmtMoney(revenue)} tone={revenue ? 'good' : undefined} />
      </div>
      <div className="row" style={{ margin: '12px 0 6px', gap: 4 }}>
        <button className={!showAll ? 'active' : ''} onClick={() => setShowAll(false)}>Activos</button>
        <button className={showAll ? 'active' : ''} onClick={() => setShowAll(true)}>Todos ({list.length})</button>
        <span className="spacer" />
        <button onClick={() => ui.openWindow('market')}>Ir al mercado →</button>
      </div>
      <div className="window-body" style={{ display: 'flex', gap: 14, minHeight: 0, overflow: 'hidden', paddingTop: 4 }}>
        <div className="scroll" style={{ flex: 1, minWidth: 0 }}>
          {shown.length === 0 ? <Empty>{list.length ? 'Ningún contrato activo.' : 'Aún no tienes contratos. Gana una licitación o una solicitud privada en el Mercado.'}</Empty> : (
            <table className="grid-table">
              <thead><tr><th>Cliente</th><th>Tipo</th><th className="num">Precio</th><th>Estado</th><th className="num">COD límite</th><th style={{ width: 120 }}>Avance</th><th className="num">Garantía</th></tr></thead>
              <tbody>
                {shown.map((k) => (
                  <tr key={k.id} className={`clickable ${sel?.id === k.id ? 'selected' : ''}`} onClick={() => choose(k.id)} data-contract={k.id}>
                    <td><b>{k.clientName}</b><div className="dim" style={{ fontSize: 11 }}>{k.id} · {techShort(k.techId)} · {fmtNum(k.mw, 0)} MW</div></td>
                    <td>{k.kindLabel}</td>
                    <td className="num mono">{fmtPrice(k.price, k.unit)}</td>
                    <td><Pill tone={k.late ? 'bad' : STATUS_TONE[k.status]}>{k.late ? 'Atrasado' : k.statusLabel}</Pill></td>
                    <td className="num mono">{fmtDate(k.codDeadlineDate)}{k.active && k.status !== 'operando' && <div style={{ fontSize: 11, color: k.daysToCod < 0 ? 'var(--bad)' : 'var(--text-dim)' }}>{k.daysToCod < 0 ? `${fmtDaysLeft(-k.daysToCod)} tarde` : `faltan ${fmtDaysLeft(k.daysToCod)}`}</div>}</td>
                    <td><Bar value={progressOf(k)} color={k.late ? 'var(--bad)' : 'var(--warn)'} /></td>
                    <td className="num mono">{fmtMoney(k.bondUsd)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
        {sel && <ContractCard k={sel} />}
      </div>
    </Window>
  );
}

const progressOf = (k: ContractView) => (k.epc ? k.epc.progress : k.status === 'operando' || k.status === 'cumplido' ? 1 : k.project ? Math.max(0.05, k.project.buildProgress) : 0);

function ContractCard({ k }: { k: ContractView }) {
  return (
    <div className="side-card scroll" data-testid="contract-card">
      <div style={{ fontSize: 15, fontWeight: 700 }}>{k.clientName}</div>
      <div className="dim" style={{ fontSize: 11.5 }}>{k.id} · {k.kindLabel} · {gameData.simData.countries[k.countryCode]?.nombre ?? k.countryCode} · firmado el {fmtDate(k.signedDate)}</div>
      <div style={{ margin: '8px 0' }}><Pill tone={k.late ? 'bad' : STATUS_TONE[k.status]}>{k.late ? 'Atrasado' : k.statusLabel}</Pill></div>
      <table className="kv"><tbody>
        <tr><td>Precio</td><td>{fmtPrice(k.price, k.unit)}</td></tr>
        <tr><td>{k.kind === 'potencia' ? 'Potencia firme' : 'Capacidad'}</td><td>{fmtNum(k.mw, 0)} MW · {techShort(k.techId)}</td></tr>
        {k.kind !== 'epc' && <tr><td>Plazo</td><td>{k.years} años</td></tr>}
        {k.assignDeadlineDate && k.status === 'sin_proyecto' && <tr><td>Asignar proyecto antes del</td><td style={{ color: 'var(--warn)' }}>{fmtDate(k.assignDeadlineDate)}</td></tr>}
        <tr><td>{k.kind === 'epc' ? 'Entrega límite' : 'COD límite'}</td><td>{fmtDate(k.codDeadlineDate)}</td></tr>
        <tr><td>Plazo máximo (rescisión)</td><td>{fmtDate(k.terminationDate)}</td></tr>
        <tr><td>Garantía de cumplimiento</td><td>{fmtMoney(k.bondUsd)}</td></tr>
        <tr><td>Multas pagadas</td><td style={{ color: k.penaltiesUsd ? 'var(--bad)' : undefined }}>{fmtMoney(k.penaltiesUsd)}</td></tr>
        <tr><td>Ingresos cobrados</td><td>{fmtMoney(k.revenueUsd)}</td></tr>
      </tbody></table>
      {k.obligations.length > 0 && (
        <>
          <div className="stat-label" style={{ margin: '10px 0 4px' }}>Obligaciones</div>
          <ul className="obligations">{k.obligations.map((t, i) => <li key={i}>{t}</li>)}</ul>
        </>
      )}
      {k.epc && <EpcBlock k={k} />}
      {k.project && (
        <Section title="Proyecto vinculado">
          <button className="choice" style={{ width: '100%', display: 'block', textAlign: 'left' }} onClick={() => ui.openProject(k.project!.id)}>
            <div className="row"><b>{k.project.name}</b><span className="spacer" /><StageBadge stage={k.project.stageId} label={k.project.stage} /></div>
            <div style={{ marginTop: 6 }}><Bar value={k.project.buildProgress} color="var(--warn)" /></div>
            <div className="dim" style={{ fontSize: 11, marginTop: 3 }}>Obra {fmtPct(k.project.buildProgress, 0)} · abrir proyecto →</div>
          </button>
        </Section>
      )}
      {k.status === 'sin_proyecto' && <AssignProject k={k} />}
    </div>
  );
}

function EpcBlock({ k }: { k: ContractView }) {
  const e = k.epc!;
  return (
    <Section title="Obra para el cliente (EPC)">
      <div style={{ marginBottom: 6 }}><Bar value={e.progress} height={9} color="var(--warn)" /></div>
      <table className="kv"><tbody>
        <tr><td>Avance</td><td>{fmtPct(e.progress, 0)}</td></tr>
        <tr><td>Valor del contrato</td><td>{fmtMoney(e.contractValueUsd)}</td></tr>
        <tr><td>Presupuesto de obra</td><td>{fmtMoney(e.budgetUsd)}</td></tr>
        <tr><td>Gastado</td><td>{fmtMoney(e.spentUsd)}</td></tr>
        <tr><td>Cobrado</td><td>{fmtMoney(e.collectedUsd)}</td></tr>
        <tr><td>Sobrecostos</td><td style={{ color: e.overrunUsd ? 'var(--bad)' : undefined }}>{fmtMoney(e.overrunUsd)}</td></tr>
        <tr><td>Daños por atraso</td><td style={{ color: e.ldUsd ? 'var(--bad)' : undefined }}>{fmtMoney(e.ldUsd)}</td></tr>
        <tr className="kv-head"><td>Margen esperado</td><td style={{ color: e.expectedMarginUsd < 0 ? 'var(--bad)' : 'var(--good)' }}>{fmtMoney(e.expectedMarginUsd)}</td></tr>
      </tbody></table>
    </Section>
  );
}

/** Asignar un proyecto propio a un contrato «con proyecto nuevo» (`ContractView.eligibleProjects` del motor). */
function AssignProject({ k }: { k: ContractView }) {
  const need = k.kind === 'potencia' ? nameplateMw({ data: gameData.simData }, { contract: 'potencia', mw: k.mw }, k.techId) : k.mw;
  const ok = k.eligibleProjects;
  const country = gameData.simData.countries[k.countryCode]?.nombre ?? k.countryCode;
  const [pid, setPid] = useState(ok[0]?.id ?? '');
  return (
    <Section title="Asignar proyecto">
      {ok.length === 0 ? (
        <div className="notice warn">Ningún proyecto propio cumple: {techShort(k.techId)} en {country}, entre {fmtNum(0.9 * need, 0)} y {fmtNum(1.5 * need, 0)} MW, sin otro contrato ni PPA y antes de la obra. Crea uno en el globo («Desarrollar proyecto aquí»).</div>
      ) : (
        <div className="row" style={{ gap: 6 }}>
          <select value={pid} onChange={(e) => setPid(e.target.value)} style={{ flex: 1 }} data-testid="assign-project">
            {ok.map((p) => <option key={p.id} value={p.id}>{p.name} · {fmtNum(p.mw, 0)} MW · {p.stage}</option>)}
          </select>
          <ConfirmButton className="primary" disabled={!pid} confirm="El proyecto recibe el PPA del contrato." onConfirm={() => sim.command({ type: 'assignContractProject', contractId: k.id, projectId: pid })}>Asignar</ConfirmButton>
        </div>
      )}
    </Section>
  );
}
