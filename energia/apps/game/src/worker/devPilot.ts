/**
 * Solo para la prueba de humo (`__voltaje.autopilot`): piloto automático que lleva los proyectos del jugador hasta la
 * operación con los mismos comandos que la UI (el mismo criterio que `operatingPlant` de las pruebas del motor):
 * mitigar hallazgos, un estudio por grupo, todos los permisos, proveedores más baratos, capital propio y obra.
 * No es una regla del juego: solo decide comandos con información visible (selectores).
 */
import { selectProjectDetail, step, type Command, type GameState, type SimContext, type SimEvent } from '@voltaje/sim';

function pilot(state: GameState, ctx: SimContext, projectId: string): Command[] {
  const d = selectProjectDetail(state, ctx, projectId);
  if (!d || !d.summary.active || d.operation) return [];
  const cmds: Command[] = [];
  for (const f of d.findings) if (f.status === 'abierto' && f.mitigable) cmds.push({ type: 'mitigateFinding', projectId, findingId: f.id });
  if (d.findings.some((f) => f.status !== 'mitigado')) return cmds;
  const byGroup = new Map<string, typeof d.studies>();
  for (const s of d.studies) { const a = byGroup.get(s.grupo) ?? []; a.push(s); byGroup.set(s.grupo, a); }
  for (const [, list] of byGroup) {
    if (!list.some((s) => s.required) || list.some((s) => s.status === 'en_curso' || s.status === 'completado')) continue;
    const avail = list.filter((s) => s.status === 'disponible').sort((a, b) => (a.sigmaAfter ?? 1) - (b.sigmaAfter ?? 1));
    if (avail.length) cmds.push({ type: 'commissionStudy', projectId, studyId: avail[0].id });
  }
  for (const p of d.permits) if (p.status === 'disponible' || (p.status === 'rechazado' && p.blockers.length === 0)) cmds.push({ type: 'applyPermit', projectId, permitId: p.id });
  if (d.canFinance.blockers.length === 1 && /proveedor/i.test(d.canFinance.blockers[0])) {
    const cheap = <T extends { priceFactor: number }>(l: T[]) => [...l].sort((a, b) => a.priceFactor - b.priceFactor)[0];
    const eq = cheap(d.suppliers.equipment), epc = cheap(d.suppliers.epc);
    if (eq && epc) cmds.push({ type: 'selectSuppliers', projectId, equipmentId: eq.id, epcId: epc.id });
  } else if (d.canFinance.ok) {
    cmds.push({ type: 'arrangeFinancing', projectId, lenderId: d.lenders[0]?.id ?? '', debtFraction: 0, partnerShare: 0 });
  }
  if (d.canStartConstruction.ok) cmds.push({ type: 'startConstruction', projectId });
  return cmds;
}

/** Avanza hasta `maxDays` días (o hasta que todos los proyectos operen y pasen `extraDays`). Devuelve los eventos. */
export function runAutopilot(state: GameState, ctx: SimContext, maxDays: number, extraDays: number): SimEvent[] {
  const events: SimEvent[] = [];
  let after = -1;
  for (let i = 0; i < maxDays; i++) {
    let cmds: Command[] = [];
    if (state.tick % 7 === 0) for (const p of state.projects) cmds = cmds.concat(pilot(state, ctx, p.id));
    events.push(...step(state, cmds, ctx));
    if (state.finance.bankrupt) break;
    const live = state.projects.filter((p) => !['vendido', 'desmantelado', 'abandonado'].includes(p.stage));
    if (after < 0 && live.length && live.every((p) => p.operation)) after = i;
    if (after >= 0 && i - after >= extraDays) break;
  }
  return events;
}
