import type { GameState } from '../core/state';
import type { SimContext } from '../core/context';
import type { SimEvent } from '../core/events';
import { Rng } from '../core/rng';
import { accrue, postCash } from '../finance/company';
import { currentCapex } from '../tech/costs';
import { fxNominal } from '../market/macro';
import { drawDays } from '../project/outcomes';
import { isTerminal, note } from '../project/helpers';
import { bookValue } from '../project/valuation';
import type { Project } from '../project/types';
import { changeReputation } from './actor';
import { executeBond, postBond, releaseBond } from './bonds';
import { bidBlockers, buildMonths, defaultSuppliers } from './bids';
import type { Bid, Contract, Opportunity } from './types';

/**
 * Contratos ganados (Fase 3) y sus obligaciones:
 *  - PPA / BOT: el proyecto vinculado recibe un PPA firmado (precio, plazo, fecha de COD, multa mensual por
 *    atraso, que cobra el ciclo de proyecto de la Fase 2). Si pasa `terminationTick` sin COD, se ejecuta la
 *    garantía de cumplimiento y se rescinde. BOT: al terminar el plazo la planta se transfiere al Estado.
 *  - Potencia: pago mensual por MW firme mientras la planta opera (con multa si la disponibilidad cae).
 *  - EPC para terceros: obra propia con anticipo, pagos por avance y retención; daños por atraso (LD) con tope.
 *  - «Con proyecto nuevo»: hay `meses_asignar_proyecto` para vincular un proyecto propio; si no, se ejecuta la garantía.
 */

const DPM = 30.44;
const fmt = (v: number) => `${Math.round(v).toLocaleString('es-PA')} USD`;

export type ContractCommand = { type: 'assignContractProject'; contractId: string; projectId: string };

type Result = { ok: true } | { ok: false; error: string };

/** Firma el contrato del ganador. Devuelve false si no puede constituir la garantía de cumplimiento. */
export function signContract(state: GameState, ctx: SimContext, o: Opportunity, b: Bid, events: SimEvent[]): boolean {
  const def = ctx.data.clients!;
  const coll = def.garantias.colateral_frac;
  const extra = Math.max(0, o.performanceBondUsd - b.bondUsd) * coll;
  if (state.company.cashUsd < extra) return false;
  releaseBond(state, ctx, b.bondUsd, `Garantía de seriedad convertida (${o.clientName})`);
  postBond(state, ctx, o.performanceBondUsd, `Garantía de cumplimiento (${o.clientName})`);
  b.status = 'ganada';
  state.business.bidsWon += 1;
  const id = `${state.actorId ? `${state.actorId}-` : ''}K${state.business.nextContractId++}`;
  const cod = state.tick + Math.round(b.deliveryMonths * DPM);
  const k: Contract = {
    id, opportunityId: o.id, actorId: state.actorId ?? 'jugador', kind: o.contract, clientName: o.clientName, countryCode: o.countryCode,
    mw: o.mw, techId: b.techId, price: b.price, years: o.years, indexation: o.indexation, signedTick: state.tick,
    codDeadlineTick: cod, terminationTick: cod + Math.round(o.maxDelayMonths * DPM), bondUsd: o.performanceBondUsd,
    penaltyUsdMwMonth: o.penaltyUsdMwMonth, penaltiesUsd: 0, revenueUsd: 0, status: 'sin_proyecto',
    ...(o.currency === 'local' ? { currency: 'local' as const, fxAtSigning: fxNominal(state, ctx, o.countryCode) } : {}),
  };
  state.business.contracts.push(k);
  if (o.contract === 'epc') startEpc(state, ctx, k, b);
  else if (b.projectId) linkProject(state, k, state.projects.find((p) => p.id === b.projectId)!);
  else k.assignDeadlineTick = state.tick + Math.round(def.meses_asignar_proyecto * DPM);
  events.push(contractEvent(state, 'contractSigned', k, `Contrato ${k.id} firmado con ${k.clientName}: ${k.mw} MW, ${k.kind.toUpperCase()}, entrega comprometida en ${b.deliveryMonths} meses. Garantía de cumplimiento ${fmt(k.bondUsd)}.${k.status === 'sin_proyecto' && k.kind !== 'epc' ? ` Asigna un proyecto en ${def.meses_asignar_proyecto} meses.` : ''}`, 'bueno'));
  return true;
}

function contractEvent(state: GameState, type: 'contractSigned' | 'contractProjectAssigned' | 'contractFulfilled' | 'contractTerminated' | 'contractPenalty' | 'guaranteeExecuted' | 'guaranteeReleased' | 'epcDelivered' | 'epcUpdate',
  k: Contract, text: string, severity: 'info' | 'bueno' | 'malo', amountUsd?: number): SimEvent {
  void state;
  return { type, contractId: k.id, text, severity, ...(amountUsd !== undefined ? { amountUsd } : {}) } as SimEvent;
}

function linkProject(state: GameState, k: Contract, p: Project) {
  k.projectId = p.id;
  k.status = 'en_desarrollo';
  p.contractId = k.id;
  if (k.kind === 'ppa' || k.kind === 'bot') {
    p.ppa = {
      channelId: `contrato:${k.id}`, status: 'firmado', startTick: state.tick, endTick: state.tick, priceUsdMwh: k.price, years: k.years,
      indexation: k.indexation, codDeadlineTick: k.codDeadlineTick, penaltyUsdMwMonth: k.penaltyUsdMwMonth, costUsd: 0,
      ...(k.currency === 'local' ? { currency: 'local' as const, fxAtSigning: k.fxAtSigning } : {}),
    };
  }
  p.timeline.push({ tick: state.tick, text: `Vinculado al contrato ${k.id} (${k.clientName}): ${k.kind === 'potencia' ? `${k.mw} MW firmes a ${k.price.toFixed(1)} USD/kW-mes` : `${k.price.toFixed(1)} USD/MWh por ${k.years} años`}.`, kind: 'bueno' });
}

export function applyContractCommand(state: GameState, ctx: SimContext | undefined, cmd: ContractCommand, events: SimEvent[]): Result {
  if (!ctx?.data.clients) return { ok: false, error: 'No hay contratos en los datos.' };
  const k = state.business.contracts.find((x) => x.id === cmd.contractId);
  if (!k) return { ok: false, error: 'Contrato inexistente.' };
  if (k.status !== 'sin_proyecto' || k.kind === 'epc') return { ok: false, error: 'El contrato no está esperando un proyecto.' };
  const p = state.projects.find((x) => x.id === cmd.projectId);
  if (!p) return { ok: false, error: 'Proyecto inexistente.' };
  const fake = { id: '_', contract: k.kind, mw: k.mw, countryCode: k.countryCode, techs: [k.techId], status: 'abierta', deadlineTick: Infinity, bids: [], contractType: '', minExperienceMw: 0, minEquityUsd: 0, prepCostUsd: 0, bidBondUsd: 0, codMonths: 999 } as unknown as Opportunity;
  const b = bidBlockers(state, ctx, fake, { techId: k.techId, projectId: p.id }).filter((x) => !/Caja insuficiente|investigación|Mercado|experiencia|patrimonio/.test(x));
  if (p.operation) b.push('El proyecto ya opera: el contrato exige una planta nueva.');
  if (b.length) return { ok: false, error: b.join(' ') };
  linkProject(state, k, p);
  events.push(contractEvent(state, 'contractProjectAssigned', k, `${p.name} asignado al contrato ${k.id} (${k.clientName}).`, 'info'));
  return { ok: true };
}

function breach(state: GameState, ctx: SimContext, k: Contract, reason: string, events: SimEvent[]) {
  executeBond(state, ctx, k.bondUsd, `Garantía de cumplimiento ejecutada (${k.clientName})`);
  k.status = 'incumplido';
  k.endTick = state.tick;
  changeReputation(state, -15);
  const p = k.projectId ? state.projects.find((x) => x.id === k.projectId) : undefined;
  if (p) {
    p.contractId = undefined;
    if (p.ppa?.channelId === `contrato:${k.id}`) p.ppa.status = 'fallido';
    if (!isTerminal(p)) p.timeline.push({ tick: state.tick, text: `Contrato ${k.id} rescindido: ${reason}`, kind: 'malo' });
  }
  events.push(contractEvent(state, 'guaranteeExecuted', k, `${k.clientName} ejecutó la garantía de ${fmt(k.bondUsd)}: ${reason}`, 'malo', k.bondUsd));
  events.push(contractEvent(state, 'contractTerminated', k, `Contrato ${k.id} rescindido por incumplimiento. Reputación −15.`, 'malo'));
}

function startEpc(state: GameState, ctx: SimContext, k: Contract, b: Bid) {
  const def = ctx.data.clients!.epc;
  const tech = ctx.data.technologies[k.techId];
  const sup = { ...defaultSuppliers(ctx, k.techId), ...(b.equipmentId ? { equipmentId: b.equipmentId } : {}), ...(b.epcId ? { epcId: b.epcId } : {}) };
  const cap = currentCapex(state, ctx, { techId: k.techId, mw: k.mw, countryCode: k.countryCode, ...sup });
  const budget = cap.equipmentUsd + cap.freightUsd + cap.tariffsUsd + cap.epcUsd + 0.5 * cap.otherUsd;
  const rng = new Rng(state.rng.business);
  const epc = ctx.data.suppliers[sup.epcId!];
  const planned = Math.round(buildMonths(tech, k.mw) * DPM * (epc?.factor_plazo ?? 1) * rng.triangular(0.9, 1, 1.25));
  k.status = 'en_desarrollo';
  k.epc = {
    budgetUsd: budget, spentUsd: 0, progress: 0, plannedDays: planned, startTick: state.tick, stoppedDays: 0, delayDays: 0, overrunUsd: 0,
    collectedUsd: 0, ldUsd: 0, equipmentId: sup.equipmentId!, epcId: sup.epcId!, monthSpendUsd: 0, monthProgress: 0,
  };
  const value = contractValue(k);
  const adv = value * def.anticipo_frac;
  k.epc.collectedUsd += adv;
  k.revenueUsd += adv;
  postCash(state, 'ingresos_epc', adv, `${k.clientName}: anticipo EPC`);
}

export function contractValue(k: Contract): number {
  return k.kind === 'epc' ? k.price * k.mw * 1000 : 0;
}

/** Avance diario: obra EPC para terceros. */
export function contractsDaily(state: GameState, ctx: SimContext, month: number, events: SimEvent[]) {
  for (const k of state.business.contracts) {
    if (k.kind !== 'epc' || k.status !== 'en_desarrollo' || !k.epc) continue;
    const e = k.epc;
    if (e.stoppedDays > 0) { e.stoppedDays--; e.delayDays++; continue; }
    const c = ctx.data.countries[k.countryCode];
    let rate = 1 / e.plannedDays;
    if (c?.construccion.meses_lluviosos.includes(month)) rate *= 0.5 + 0.5 * c.construccion.factor_avance_lluvia;
    const d = Math.min(rate, 1 - e.progress);
    e.progress += d;
    e.monthProgress += d;
    const spend = d * e.budgetUsd;
    e.spentUsd += spend;
    e.monthSpendUsd += spend;
    if (e.progress >= 1 - 1e-9) deliverEpc(state, ctx, k, events);
  }
}

function settleEpcMonth(state: GameState, ctx: SimContext, k: Contract) {
  const e = k.epc!;
  const def = ctx.data.clients!.epc;
  if (e.monthSpendUsd > 0) postCash(state, 'costos_epc', -e.monthSpendUsd, `${k.clientName}: obra EPC`);
  const pay = contractValue(k) * (1 - def.anticipo_frac - def.retencion_frac) * e.monthProgress;
  if (pay > 0) { postCash(state, 'ingresos_epc', pay, `${k.clientName}: pago por avance EPC`); e.collectedUsd += pay; k.revenueUsd += pay; }
  e.monthSpendUsd = 0;
  e.monthProgress = 0;
}

function deliverEpc(state: GameState, ctx: SimContext, k: Contract, events: SimEvent[]) {
  const e = k.epc!;
  const def = ctx.data.clients!.epc;
  settleEpcMonth(state, ctx, k);
  const ret = contractValue(k) * def.retencion_frac;
  postCash(state, 'ingresos_epc', ret, `${k.clientName}: retención EPC liberada`);
  e.collectedUsd += ret;
  k.revenueUsd += ret;
  e.deliveredTick = state.tick;
  k.status = 'cumplido';
  k.codTick = state.tick;
  k.endTick = state.tick;
  releaseBond(state, ctx, k.bondUsd, `Garantía de cumplimiento devuelta (${k.clientName})`);
  state.business.epcDeliveredMw += k.mw;
  const late = Math.max(0, state.tick - k.codDeadlineTick);
  changeReputation(state, late > 0 ? 1 : 4);
  const margin = e.collectedUsd - e.spentUsd - e.ldUsd;
  events.push(contractEvent(state, 'epcDelivered', k, `Obra entregada a ${k.clientName} (${k.mw} MW)${late > 0 ? ` con ${late} días de atraso` : ' a tiempo'}. Margen ${fmt(margin)} (${(margin / Math.max(1, contractValue(k)) * 100).toFixed(1)} %).`, margin >= 0 ? 'bueno' : 'malo'));
}

/** Cierre de mes: obligaciones, pagos, multas, transferencias. */
export function contractsMonthly(state: GameState, ctx: SimContext, month: number, events: SimEvent[]) {
  const def = ctx.data.clients;
  if (!def) return;
  const rng = new Rng(state.rng.business);
  for (const k of state.business.contracts) {
    if (k.status === 'cumplido' || k.status === 'incumplido' || k.status === 'cedido') continue;
    const t = state.tick;
    if (k.kind === 'epc') {
      if (!k.epc) continue;
      settleEpcMonth(state, ctx, k);
      const c = ctx.data.countries[k.countryCode];
      const epc = ctx.data.suppliers[k.epc.epcId];
      if (c && rng.chance(c.construccion.huelga_prob_mensual)) k.epc.stoppedDays += drawDays(rng, c.construccion.huelga_duracion_dias);
      if (c && c.construccion.meses_lluviosos.includes(month) && rng.chance(c.construccion.clima_extremo_prob_mensual)) k.epc.stoppedDays += drawDays(rng, c.construccion.clima_extremo_dias);
      if (rng.chance((epc?.prob_sobrecosto_hito ?? 0.15) * 0.35)) {
        const amt = rng.triangular(0.02, 0.04, 0.1) * k.epc.budgetUsd * (1 - k.epc.progress);
        k.epc.overrunUsd += amt;
        k.epc.budgetUsd += amt / Math.max(0.05, 1 - k.epc.progress);
        events.push(contractEvent(state, 'epcUpdate', k, `Sobrecosto en la obra de ${k.clientName}: ${fmt(amt)} (lo absorbe tu margen).`, 'malo', amt));
      }
      if (t > k.codDeadlineTick) {
        const value = contractValue(k);
        const ld = Math.min(value * def.epc.ld_frac_semana * DPM / 7, value * def.epc.ld_tope_frac - k.epc.ldUsd);
        if (ld > 0) {
          k.epc.ldUsd += ld; k.penaltiesUsd += ld;
          postCash(state, 'multas', -ld, `${k.clientName}: daños por atraso EPC`);
          events.push(contractEvent(state, 'contractPenalty', k, `Atraso en la entrega a ${k.clientName}: daños de ${fmt(ld)}.`, 'malo', ld));
        }
      }
      if (t > k.terminationTick) breach(state, ctx, k, 'la obra no se entregó en el plazo máximo.', events);
      continue;
    }
    const p = k.projectId ? state.projects.find((x) => x.id === k.projectId) : undefined;
    if (k.status === 'sin_proyecto') {
      if (t > (k.assignDeadlineTick ?? k.codDeadlineTick)) breach(state, ctx, k, 'no se asignó un proyecto a tiempo.', events);
      else if (t > k.codDeadlineTick) penalty(state, k, events);
      continue;
    }
    if (!p || p.stage === 'abandonado' || p.stage === 'desmantelado') { breach(state, ctx, k, 'el proyecto comprometido se abandonó.', events); continue; }
    if (p.stage === 'vendido' && k.status === 'en_desarrollo') {
      k.status = 'cedido'; k.endTick = t;
      releaseBond(state, ctx, k.bondUsd, `Garantía devuelta: contrato ${k.id} cedido al comprador`);
      events.push(contractEvent(state, 'guaranteeReleased', k, `Contrato ${k.id} cedido junto con ${p.name}; se libera la garantía.`, 'info', k.bondUsd));
      continue;
    }
    if (k.status === 'en_desarrollo') {
      if (p.operation) {
        k.status = 'operando';
        k.codTick = p.operation.codTick;
        releaseBond(state, ctx, k.bondUsd, `Garantía de cumplimiento devuelta (${k.clientName})`);
        const onTime = p.operation.codTick <= k.codDeadlineTick;
        changeReputation(state, onTime ? 5 : 1);
        events.push(contractEvent(state, 'contractFulfilled', k, `${p.name} entró en operación ${onTime ? 'a tiempo' : 'con atraso'} para ${k.clientName}: se libera la garantía de ${fmt(k.bondUsd)}.${onTime ? ' Reputación +5.' : ''}`, 'bueno', k.bondUsd));
      } else if (t > k.terminationTick) {
        breach(state, ctx, k, 'no hubo operación comercial en el plazo máximo.', events);
        continue;
      } else if (t > k.codDeadlineTick) {
        changeReputation(state, -1);
        if (k.kind === 'potencia') penalty(state, k, events); // en PPA/BOT la multa la cobra el ciclo de proyecto
      }
    }
    if (k.status === 'operando' && p.operation) {
      const years = (t - k.codTick!) / 365.25;
      if (k.kind === 'potencia') {
        const last = p.operation.history.at(-1);
        let pay = k.mw * 1000 * k.price * Math.pow(1 + k.indexation, Math.floor(years)) * (k.currency === 'local' && k.fxAtSigning ? fxNominal(state, ctx, k.countryCode) / k.fxAtSigning : 1);
        if (last && last.availability < 0.85) {
          const pen = pay * 0.1;
          pay -= pen;
          k.penaltiesUsd += pen;
          events.push(contractEvent(state, 'contractPenalty', k, `${p.name}: disponibilidad ${(last.availability * 100).toFixed(0)} % por debajo del 85 % exigido; descuento de ${fmt(pen)} en el pago por potencia.`, 'malo', pen));
        }
        postCash(state, 'ingresos_potencia', pay, `${k.clientName}: potencia firme`);
        k.revenueUsd += pay;
      }
      if (years >= k.years) {
        k.status = 'cumplido'; k.endTick = t;
        if (k.kind === 'bot') transferBot(state, k, p, events);
        else events.push(contractEvent(state, 'contractFulfilled', k, `Contrato ${k.id} con ${k.clientName} terminado. ${k.kind === 'ppa' ? 'La planta pasa a vender al spot.' : ''}`, 'info'));
        p.contractId = undefined;
      }
    }
  }
}

function penalty(state: GameState, k: Contract, events: SimEvent[]) {
  const pen = k.penaltyUsdMwMonth * k.mw;
  if (pen <= 0) return;
  k.penaltiesUsd += pen;
  postCash(state, 'multas', -pen, `Contrato ${k.id}: multa por atraso`);
  events.push(contractEvent(state, 'contractPenalty', k, `Multa por atraso del contrato ${k.id} (${k.clientName}): ${fmt(pen)}.`, 'malo', pen));
}

function transferBot(state: GameState, k: Contract, p: Project, events: SimEvent[]) {
  const debt = p.debt?.outstandingUsd ?? 0;
  if (debt > 0) { postCash(state, 'deuda_amortizacion', -debt, `${p.name}: prepago de deuda (transferencia BOT)`); p.debt!.outstandingUsd = 0; }
  accrue(state, 'castigos', -bookValue(p));
  if (p.operation) p.operation.accumulatedDepreciationUsd = p.operation.grossAssetUsd;
  p.stage = 'vendido';
  p.endTick = state.tick;
  p.sale = { status: 'vendido', startTick: state.tick, endTick: state.tick, priceUsd: 0 };
  events.push(note(state, p, 'projectSold', `Fin del BOT con ${k.clientName}: la planta se transfiere al Estado sin pago.`, 'info', { priceUsd: 0 }));
}
