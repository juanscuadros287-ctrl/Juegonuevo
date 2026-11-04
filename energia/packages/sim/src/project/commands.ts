import type { GameState } from '../core/state';
import type { SimContext } from '../core/context';
import type { SimEvent } from '../core/events';
import { Rng } from '../core/rng';
import { postCash, accrue } from '../finance/company';
import { hiddenResourceFactor } from '../world/site';
import { capexBreakdown } from '../tech/costs';
import { drawDays, drawDist, findingCostUsd, permitCostUsd, studyCostUsd } from './outcomes';
import { financingBlockers, openFindings, permitBlockers, permitGroupApplicable, permitGroupApproved, studyBlockers } from './requirements';
import { DAYS_PER_MONTH, fmtUsd, isTerminal, note, payDev, updateStage } from './helpers';
import { bookValue } from './valuation';
import type { Project } from './types';

export type ProjectCommand =
  | { type: 'createProject'; techId: string; mw: number; lat: number; lon: number; name?: string }
  | { type: 'commissionStudy'; projectId: string; studyId: string }
  | { type: 'applyPermit'; projectId: string; permitId: string }
  | { type: 'seekPpa'; projectId: string; channelId: string }
  | { type: 'mitigateFinding'; projectId: string; findingId: string }
  | { type: 'selectSuppliers'; projectId: string; equipmentId: string; epcId: string }
  | { type: 'arrangeFinancing'; projectId: string; lenderId: string; debtFraction: number; partnerShare: number }
  | { type: 'startConstruction'; projectId: string }
  | { type: 'setMaintenancePolicy'; projectId: string; policy: 'preventivo' | 'correctivo' }
  | { type: 'sellProject'; projectId: string }
  | { type: 'abandonProject'; projectId: string }
  | { type: 'decommissionProject'; projectId: string };

export type Result = { ok: true } | { ok: false; error: string };
const fail = (error: string): Result => ({ ok: false, error });
const OK: Result = { ok: true };

function canPay(state: GameState, amount: number): boolean {
  return state.company.cashUsd >= amount;
}
const noCash = (amount: number) => fail(`Caja insuficiente: hacen falta ${fmtUsd(amount)}.`);

export function findProject(state: GameState, id: string): Project | undefined {
  return state.projects.find((p) => p.id === id);
}

export function applyProjectCommand(state: GameState, ctx: SimContext | undefined, cmd: ProjectCommand, events: SimEvent[]): Result {
  if (!ctx) return fail('Datos del juego no disponibles.');
  const rng = new Rng(state.rng.projects);
  if (cmd.type === 'createProject') return createProject(state, ctx, cmd, rng, events);
  const p = findProject(state, cmd.projectId);
  if (!p) return fail('Proyecto inexistente.');
  if (isTerminal(p)) return fail('El proyecto ya está cerrado.');
  if (p.sale?.status === 'en_proceso' && cmd.type !== 'setMaintenancePolicy') return fail('El proyecto está en venta.');
  const c = ctx.data.countries[p.countryCode];
  const tech = ctx.data.technologies[p.techId];
  const r = ((): Result => {
    switch (cmd.type) {
      case 'commissionStudy': {
        if (p.construction || p.operation) return fail('Ya no se pueden encargar estudios de desarrollo.');
        const b = studyBlockers(ctx, p, cmd.studyId);
        if (b.length) return fail(b.join(' '));
        const s = ctx.data.studies[cmd.studyId];
        const cost = studyCostUsd(s, p.mw);
        if (!canPay(state, cost)) return noCash(cost);
        payDev(state, p, cost, s.nombre);
        const days = drawDays(rng, s.duracion_dias);
        p.studies[s.id] = { studyId: s.id, status: 'en_curso', startTick: state.tick, endTick: state.tick + days, costUsd: cost };
        events.push(note(state, p, 'studyStarted', `Encargado: ${s.nombre} (${fmtUsd(cost)}, ~${days} días).`, 'info', { studyId: s.id }));
        return OK;
      }
      case 'applyPermit': {
        if (p.construction || p.operation) return fail('El proyecto ya está en obra.');
        const b = permitBlockers(ctx, p, cmd.permitId);
        if (b.length) return fail(b.join(' '));
        const d = c.permisos.find((x) => x.id === cmd.permitId)!;
        const cost = permitCostUsd(d, p.mw);
        if (!canPay(state, cost)) return noCash(cost);
        payDev(state, p, cost, d.nombre);
        const days = drawDays(rng, d.duracion_dias);
        const prev = p.permits[d.id];
        p.permits[d.id] = { permitId: d.id, status: 'en_tramite', startTick: state.tick, endTick: state.tick + days, costUsd: (prev?.costUsd ?? 0) + cost, infoRequests: 0, applications: (prev?.applications ?? 0) + 1 };
        events.push(note(state, p, 'permitRequested', `Solicitado: ${d.nombre} ante ${d.autoridad} (${fmtUsd(cost)}).`, 'info', { permitId: d.id }));
        return OK;
      }
      case 'seekPpa': {
        const ch = c.ppa.canales.find((x) => x.id === cmd.channelId);
        if (!ch) return fail('Canal de venta desconocido.');
        if (p.ppa && (p.ppa.status === 'firmado' || p.ppa.status === 'en_proceso')) return fail('Ya hay un PPA firmado o en proceso.');
        if (p.mw < ch.mw_min || p.mw > ch.mw_max) return fail(`${ch.nombre}: el proyecto debe tener entre ${ch.mw_min} y ${ch.mw_max} MW.`);
        for (const g of ch.requiere_permisos) if (permitGroupApplicable(ctx, p, g) && !permitGroupApproved(ctx, p, g)) return fail(`${ch.nombre} exige antes el permiso: ${g.replace(/_/g, ' ')}.`);
        const cost = ch.costo_usd.base;
        if (!canPay(state, cost)) return noCash(cost);
        payDev(state, p, cost, `Oferta ${ch.nombre}`);
        const days = drawDays(rng, ch.duracion_dias);
        p.ppa = { channelId: ch.id, status: 'en_proceso', startTick: state.tick, endTick: state.tick + days, priceUsdMwh: 0, years: ch.plazo_anos, indexation: ch.indexacion_anual, codDeadlineTick: 0, penaltyUsdMwMonth: ch.multa_usd_mw_mes, costUsd: cost };
        events.push(note(state, p, 'processStarted', `Buscando PPA: ${ch.nombre} (~${days} días).`, 'info', { process: 'ppa' }));
        return OK;
      }
      case 'mitigateFinding': {
        const f = p.findings.find((x) => x.id === cmd.findingId && (x.status === 'abierto'));
        if (!f) return fail('No hay un hallazgo abierto con ese id.');
        const d = ctx.data.findings[f.id];
        if (!d.mitigable) return fail('Este hallazgo no se puede mitigar.');
        const cost = findingCostUsd(d, p.mw);
        if (!canPay(state, cost)) return noCash(cost);
        payDev(state, p, cost, `Mitigación: ${d.nombre}`);
        const days = d.retraso_dias ? drawDays(rng, d.retraso_dias) : 60;
        f.status = 'en_mitigacion';
        f.endTick = state.tick + days;
        f.costUsd += cost;
        f.attempts += 1;
        events.push(note(state, p, 'processStarted', `Mitigando «${d.nombre}» (${fmtUsd(cost)}, ~${days} días).`, 'info', { process: 'mitigacion' }));
        return OK;
      }
      case 'selectSuppliers': {
        if (p.construction || p.operation) return fail('La obra ya empezó: no se puede cambiar de proveedor.');
        if (p.financing?.status === 'cerrado' || p.financing?.status === 'en_proceso') return fail('El financiamiento ya se basa en estos proveedores.');
        const eq = ctx.data.suppliers[cmd.equipmentId], epc = ctx.data.suppliers[cmd.epcId];
        if (!eq || eq.tipo !== 'equipos' || !eq.tecnologias.includes(p.techId)) return fail('Proveedor de equipos inválido para esta tecnología.');
        if (!epc || epc.tipo !== 'epc' || !epc.tecnologias.includes(p.techId)) return fail('Contratista EPC inválido para esta tecnología.');
        p.suppliers = { equipmentId: eq.id, epcId: epc.id };
        p.timeline.push({ tick: state.tick, text: `Proveedores elegidos: ${eq.nombre} y ${epc.nombre}.`, kind: 'info' });
        return OK;
      }
      case 'arrangeFinancing': {
        if (p.construction || p.operation) return fail('El proyecto ya está financiado.');
        if (p.financing && p.financing.status !== 'fallido') return fail('Ya hay un financiamiento cerrado o en proceso.');
        const b = financingBlockers(ctx, p);
        if (b.length) return fail(b.join(' '));
        if (!p.suppliers) return fail('Elige proveedor de equipos y EPC antes de financiar (el banco necesita el presupuesto).');
        const se = c.finanzas.socio_equity;
        if (!(cmd.partnerShare >= 0 && cmd.partnerShare <= se.participacion_max)) return fail(`La participación del socio debe estar entre 0 y ${se.participacion_max * 100} %.`);
        if (!(cmd.debtFraction >= 0 && cmd.debtFraction <= 0.95)) return fail('Fracción de deuda inválida.');
        const budget = capexBreakdown(ctx, { techId: p.techId, mw: p.mw, countryCode: p.countryCode, capexFactor: p.capexFactor, equipmentId: p.suppliers.equipmentId, epcId: p.suppliers.epcId }).totalUsd;
        if (cmd.debtFraction === 0) {
          // Todo con capital propio (y del socio): cierre inmediato, sin banco.
          p.financing = { status: 'cerrado', lenderId: 'ninguno', startTick: state.tick, endTick: state.tick, requestedDebtFraction: 0, partnerShare: cmd.partnerShare, rate: 0, tenorYears: 0, dscrTarget: 0, budgetUsd: budget, debtUsd: 0, equityUsd: budget, feesUsd: 0, partnerPremiumUsd: 0 };
          p.partnerShare = cmd.partnerShare;
          payPartnerPremium(state, ctx, p, events);
          events.push(note(state, p, 'financingResult', `Cierre financiero solo con capital: ${fmtUsd(budget)}.`, 'bueno', { success: true, debtUsd: 0, equityUsd: budget }));
          return OK;
        }
        const l = c.finanzas.prestamistas.find((x) => x.id === cmd.lenderId);
        if (!l) return fail('Prestamista desconocido.');
        if (cmd.debtFraction > l.apalancamiento_max) return fail(`${l.nombre} presta como máximo el ${Math.round(l.apalancamiento_max * 100)} % del costo.`);
        if (l.requiere_ppa && p.ppa?.status !== 'firmado') return fail(`${l.nombre} exige un PPA firmado.`);
        if (p.estimate.sigma > l.sigma_recurso_max + 1e-9) return fail(`${l.nombre} exige una medición de recurso bancable (incertidumbre ≤ ${(l.sigma_recurso_max * 100).toFixed(1)} %; hoy ${(p.estimate.sigma * 100).toFixed(1)} %).`);
        if (budget * cmd.debtFraction < l.monto_min_usd) return fail(`${l.nombre} no presta menos de ${fmtUsd(l.monto_min_usd)}.`);
        const cost = l.costo_asesores_usd.base;
        if (!canPay(state, cost)) return noCash(cost);
        payDev(state, p, cost, `Asesores de financiamiento (${l.nombre})`);
        const days = drawDays(rng, l.diligencia_dias);
        const rate = c.finanzas.tasa_libre_riesgo.base + drawDist(rng, l.spread);
        p.financing = {
          status: 'en_proceso', lenderId: l.id, startTick: state.tick, endTick: state.tick + days, requestedDebtFraction: cmd.debtFraction,
          partnerShare: cmd.partnerShare, rate, tenorYears: l.plazo_anos, dscrTarget: p.ppa?.status === 'firmado' ? l.dscr_ppa : l.dscr_merchant,
          budgetUsd: budget, debtUsd: 0, equityUsd: 0, feesUsd: cost, partnerPremiumUsd: 0,
        };
        events.push(note(state, p, 'processStarted', `Due diligence con ${l.nombre} (~${days} días, tasa indicativa ${(rate * 100).toFixed(2)} %).`, 'info', { process: 'financiamiento' }));
        return OK;
      }
      case 'startConstruction': {
        if (p.construction || p.operation) return fail('La obra ya empezó.');
        if (p.financing?.status !== 'cerrado') return fail('Falta el cierre financiero.');
        if (!p.suppliers) return fail('Faltan proveedores.');
        if (openFindings(p).length) return fail('Hay hallazgos sin resolver.');
        const epc = ctx.data.suppliers[p.suppliers.epcId], eq = ctx.data.suppliers[p.suppliers.equipmentId];
        const planned = Math.round(drawDist(rng, tech.construccion_meses) * DAYS_PER_MONTH * (epc.factor_plazo ?? 1));
        let acc = 0;
        const milestones = tech.hitos_construccion.map((m) => {
          const s = acc; acc += m.fraccion;
          return { id: m.id, nombre: m.nombre, fraction: m.fraccion, start: s, end: Math.min(1, acc), done: false };
        });
        let lead = eq.plazo_entrega_dias ? drawDays(rng, eq.plazo_entrega_dias) : 90;
        let late = 0;
        if (rng.chance(1 - eq.confiabilidad)) { late = Math.round(lead * (rng.triangular(1.1, 1.3, 1.8) - 1)); lead += late; }
        p.construction = {
          startTick: state.tick, plannedDays: planned, progress: 0, milestones, equipmentArrivalTick: state.tick + lead, equipmentArrived: false,
          equipmentLateDays: late, stoppedDays: 0, delayDays: 0, budgetUsd: p.financing.budgetUsd, overrunUsd: 0, spentUsd: 0, idcUsd: 0,
          monthSpendUsd: 0, monthOverrunUsd: 0,
        };
        if (p.financing.debtUsd > 0) {
          p.debt = { principalUsd: 0, outstandingUsd: 0, rate: p.financing.rate, tenorMonths: p.financing.tenorYears * 12, monthsPaid: 0, monthlyPayment: 0 };
        }
        events.push(note(state, p, 'constructionStarted', `Inicio de obra con ${epc.nombre}: ${Math.round(planned / DAYS_PER_MONTH)} meses previstos.`, 'bueno'));
        return OK;
      }
      case 'setMaintenancePolicy': {
        if (!p.operation) return fail('La planta no está en operación.');
        p.operation.maintenance = cmd.policy;
        p.timeline.push({ tick: state.tick, text: `Mantenimiento ${cmd.policy}.`, kind: 'info' });
        return OK;
      }
      case 'sellProject': {
        const days = drawDays(rng, p.operation ? { min: 60, base: 90, max: 150 } : { min: 45, base: 75, max: 120 });
        p.sale = { status: 'en_proceso', startTick: state.tick, endTick: state.tick + days, priceUsd: 0 };
        events.push(note(state, p, 'saleStarted', `Proyecto puesto a la venta (~${days} días para cerrar con un comprador).`, 'info'));
        return OK;
      }
      case 'abandonProject': {
        const debt = p.debt?.outstandingUsd ?? 0;
        if (debt > 0) postCash(state, 'deuda_amortizacion', -debt, `${p.name}: prepago de deuda por abandono`);
        const book = bookValue(p);
        accrue(state, 'castigos', -book);
        if (p.debt) p.debt.outstandingUsd = 0;
        p.stage = 'abandonado';
        p.endTick = state.tick;
        events.push(note(state, p, 'projectAbandoned', `Proyecto abandonado. Se castigan ${fmtUsd(book)} invertidos.`, 'malo', { writeOffUsd: book }));
        return OK;
      }
      case 'decommissionProject': {
        if (!p.operation) return fail('Solo se desmantelan plantas en operación.');
        decommission(state, ctx, p, events, 'Desmantelamiento anticipado');
        return OK;
      }
    }
  })();
  updateStage(ctx, p);
  return r;
}

export function payPartnerPremium(state: GameState, ctx: SimContext, p: Project, _events: SimEvent[]) {
  const f = p.financing!;
  if (f.partnerShare <= 0) return;
  const c = ctx.data.countries[p.countryCode];
  const premium = f.partnerShare * f.equityUsd * c.finanzas.socio_equity.prima_desarrollo_frac;
  f.partnerPremiumUsd = premium;
  postCash(state, 'prima_desarrollo', premium, `${p.name}: prima de desarrollo pagada por el socio`);
}

export function decommission(state: GameState, ctx: SimContext, p: Project, events: SimEvent[], reason: string) {
  const tech = ctx.data.technologies[p.techId];
  const op = p.operation!;
  const cost = tech.costo_desmantelamiento_frac_capex.base * op.grossAssetUsd;
  postCash(state, 'desarrollo_gasto', -cost, `${p.name}: desmantelamiento`);
  const debt = p.debt?.outstandingUsd ?? 0;
  if (debt > 0) { postCash(state, 'deuda_amortizacion', -debt, `${p.name}: prepago de deuda`); p.debt!.outstandingUsd = 0; }
  const book = op.grossAssetUsd - op.accumulatedDepreciationUsd;
  accrue(state, 'castigos', -book);
  op.accumulatedDepreciationUsd = op.grossAssetUsd;
  p.stage = 'desmantelado';
  p.endTick = state.tick;
  events.push(note(state, p, 'projectDecommissioned', `${reason}: ${fmtUsd(cost)}.`, 'info', { costUsd: cost }));
}

function createProject(state: GameState, ctx: SimContext, cmd: Extract<ProjectCommand, { type: 'createProject' }>, _rng: Rng, events: SimEvent[]): Result {
  const tech = ctx.data.technologies[cmd.techId];
  if (!tech) return fail('Tecnología desconocida.');
  if (!ctx.grid) return fail('La grilla de recursos no está cargada.');
  if (!(cmd.mw >= tech.escala_mw.min && cmd.mw <= tech.escala_mw.max)) return fail(`${tech.nombre}: entre ${tech.escala_mw.min} y ${tech.escala_mw.max} MW.`);
  if (!(Math.abs(cmd.lat) <= 90 && Math.abs(cmd.lon) <= 180)) return fail('Ubicación inválida.');
  const cell = ctx.grid.cell(cmd.lat, cmd.lon);
  if (!cell.land || !cell.country) return fail('El sitio no está en tierra firme.');
  const country = ctx.data.countries[cell.country.code];
  if (!country) return fail(`Todavía no se puede desarrollar en ${cell.country.nombre}.`);
  if (!tech.recurso) return fail('Tecnología sin recurso de grilla.');
  const value = cell.values[tech.recurso] ?? 0;
  if (!(value > 0)) return fail('El sitio no tiene recurso para esta tecnología.');
  const cost = country.costos.prospeccion_usd.base;
  if (!canPay(state, cost)) return noCash(cost);
  const id = `P${state.nextProjectId++}`;
  const name = (cmd.name?.trim() || `${tech.nombre} ${cmd.mw} MW (${id})`).slice(0, 60);
  const p: Project = {
    id, name, techId: tech.id, countryCode: country.iso3, mw: cmd.mw, createdTick: state.tick, stage: 'identificado',
    site: {
      lat: cmd.lat, lon: cmd.lon, cellIndex: cell.index, layer: tech.recurso, cellValue: value,
      temperatureC: cell.values.temperatura ?? 25,
      realFactor: hiddenResourceFactor(state.seed, tech.recurso, cmd.lat, cmd.lon, tech.sigma_recurso_sitio),
    },
    estimate: { value, sigma: tech.sigma_recurso_sitio, source: 'celda' },
    studies: {}, permits: {}, findings: [], capexFactor: 1, devCostUsd: 0, devExpenseUsd: 0, partnerShare: 0, timeline: [],
  };
  state.projects.push(p);
  payDev(state, p, cost, 'Prospección y opción de terreno');
  events.push(note(state, p, 'projectCreated', `Proyecto creado: ${name} en ${country.nombre} (${fmtUsd(cost)} de prospección).`, 'info'));
  return OK;
}

