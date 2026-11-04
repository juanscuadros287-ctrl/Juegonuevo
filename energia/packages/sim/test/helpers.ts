import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { gameData } from '@voltaje/data';
import {
  ResourceGrid, createNewGame, selectProjectDetail, step, type Command, type GameState, type GridMeta, type SimContext, type SimEvent,
} from '../src';

const dir = join(__dirname, '../../data/generated');
export const grid = new ResourceGrid(JSON.parse(readFileSync(join(dir, 'grid.json'), 'utf8')) as GridMeta, readFileSync(join(dir, 'grid.bin')));
export const ctx: SimContext = { data: gameData.simData, grid };
export const data = gameData.simData;

/** Sitios de referencia en Panamá. */
export const SITES = {
  /** Arco seco (Coclé/Herrera), GHI ≈ 5,3 */
  solar: { lat: 8.2, lon: -80.7 },
  /** Penonomé, viento ≈ 6,4 m/s a 100 m */
  eolica: { lat: 8.6, lon: -80.3 },
};

export function newGame(seed = 1, cash?: number, competitors = true): GameState {
  const s = createNewGame(gameData.sim, { seed, companyName: 'Prueba S.A.', competitors });
  if (cash !== undefined) { s.company.cashUsd = cash; s.company.ledger[0].amountUsd = cash; }
  return s;
}

export interface PilotOptions {
  lenderId?: string;
  debtFraction?: number;
  partnerShare?: number;
  equipmentId?: string;
  epcId?: string;
  ppaChannel?: string | null;
  /** Medición de recurso preferida (por defecto la más precisa). */
  preferCheapMeasurement?: boolean;
}

/**
 * Piloto automático: decide los comandos para avanzar un proyecto (como lo haría un jugador razonable).
 * Usa solo selectores (información visible), igual que la UI o la IA.
 */
export function pilot(state: GameState, projectId: string, o: PilotOptions = {}): Command[] {
  const d = selectProjectDetail(state, ctx, projectId);
  if (!d || !d.summary.active) return [];
  const cmds: Command[] = [];
  for (const f of d.findings) if (f.status === 'abierto' && f.mitigable) cmds.push({ type: 'mitigateFinding', projectId, findingId: f.id });
  if (d.findings.some((f) => f.status !== 'mitigado')) return cmds;
  // Estudios: uno por grupo requerido
  const byGroup = new Map<string, typeof d.studies>();
  for (const s of d.studies) { const a = byGroup.get(s.grupo) ?? []; a.push(s); byGroup.set(s.grupo, a); }
  for (const [, list] of byGroup) {
    if (!list.some((s) => s.required)) continue;
    if (list.some((s) => s.status === 'en_curso' || s.status === 'completado')) continue;
    const avail = list.filter((s) => s.status === 'disponible');
    if (!avail.length) continue;
    avail.sort((a, b) => o.preferCheapMeasurement ? a.costUsd - b.costUsd : (a.sigmaAfter ?? 1) - (b.sigmaAfter ?? 1));
    cmds.push({ type: 'commissionStudy', projectId, studyId: avail[0].id });
  }
  for (const p of d.permits) if (p.status === 'disponible' || (p.status === 'rechazado' && p.blockers.length === 0)) cmds.push({ type: 'applyPermit', projectId, permitId: p.id });
  if (o.ppaChannel !== null && (!d.ppa || d.ppa.status === 'fallido')) {
    const ch = d.ppaChannels.find((c) => c.id === (o.ppaChannel ?? 'licitacion_etesa') && c.available);
    if (ch) cmds.push({ type: 'seekPpa', projectId, channelId: ch.id });
  }
  const waitingPpa = d.ppa?.status === 'en_proceso';
  if (d.canFinance.blockers.length === 1 && d.canFinance.blockers[0] === 'Elegir proveedores.') {
    cmds.push({ type: 'selectSuppliers', projectId, equipmentId: o.equipmentId ?? (d.techName.startsWith('Solar') ? 'modulos_asia_tier1' : 'turbinas_america'), epcId: o.epcId ?? 'epc_regional' });
  } else if (d.canFinance.ok && !waitingPpa) {
    cmds.push({ type: 'arrangeFinancing', projectId, lenderId: o.lenderId ?? 'banco_comercial', debtFraction: o.debtFraction ?? 0.7, partnerShare: o.partnerShare ?? 0 });
  }
  if (d.canStartConstruction.ok) cmds.push({ type: 'startConstruction', projectId });
  return cmds;
}

/** Corre `days` días aplicando el piloto a todos los proyectos activos cada 7 días. */
export function runWithPilot(state: GameState, days: number, o: PilotOptions = {}, extra: Record<number, Command[]> = {}): SimEvent[] {
  const all: SimEvent[] = [];
  for (let i = 0; i < days; i++) {
    let cmds: Command[] = extra[state.tick] ? [...extra[state.tick]] : [];
    if (state.tick % 7 === 0) for (const p of state.projects) cmds = cmds.concat(pilot(state, p.id, o));
    all.push(...step(state, cmds, ctx));
  }
  return all;
}
