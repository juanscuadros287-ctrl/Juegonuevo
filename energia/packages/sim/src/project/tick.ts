import type { GameState } from '../core/state';
import type { SimContext } from '../core/context';
import type { SimEvent } from '../core/events';
import type { GameDate } from '../core/calendar';
import type { Rng } from '../core/rng';
import { accrue, postCash } from '../finance/company';
import { annuityPayment } from '../finance/math';
import { capacityFactor } from '../tech/capacityFactor';
import { landHa } from '../tech/costs';
import { normalizedProfile, spotPrice } from '../market/spot';
import { drawDays, drawDist, drawPermitDecision, drawStudyOutcome } from './outcomes';
import { DAYS_PER_MONTH, fmtUsd, isTerminal, note, updateStage } from './helpers';
import { decommission, payPartnerPremium } from './commands';
import { bookValue, saleValueUsd } from './valuation';
import { financingBlockers } from './requirements';
import { projectEconomics, startYear } from './economics';
import { runProjectModel, sizeDebt } from '../finance/projectModel';
import { p90 } from '../world/site';
import { researchEffects } from '../business/research';
import { recordLateDelivery } from '../supply/supply';
import type { Project } from './types';

/** Avance diario de un proyecto (`day` = día que acaba de transcurrir). */
export function projectDaily(state: GameState, ctx: SimContext, p: Project, rng: Rng, day: GameDate, events: SimEvent[]) {
  if (isTerminal(p)) return;
  const t = state.tick;
  const c = ctx.data.countries[p.countryCode];

  // Estudios
  for (const r of Object.values(p.studies)) {
    if (r.status !== 'en_curso' || t < r.endTick) continue;
    const s = ctx.data.studies[r.studyId];
    r.status = 'completado';
    if (s.sigma_recurso !== undefined) {
      const real = p.site.cellValue * p.site.realFactor;
      const measured = real * (1 + s.sigma_recurso * Math.max(-3, Math.min(3, rng.normal())));
      r.measured = measured;
      const prev = p.estimate.value;
      const better = s.sigma_recurso < p.estimate.sigma;
      if (better) p.estimate = { value: measured, sigma: s.sigma_recurso, source: s.id };
      r.outcome = better && measured < prev * 0.97 ? 'peor' : 'normal';
      const delta = ((measured / prev - 1) * 100).toFixed(1);
      const unit = p.site.layer === 'ghi' ? 'kWh/m²/día' : 'm/s';
      events.push(note(state, p, 'studyCompleted', `${s.nombre}: recurso ${measured.toFixed(2)} ${unit} (${+delta >= 0 ? '+' : ''}${delta} % frente a la estimación previa, ±${(s.sigma_recurso * 100).toFixed(1)} %).`,
        r.outcome === 'peor' ? 'malo' : 'bueno', { studyId: s.id, outcome: r.outcome }));
    } else {
      const d = drawStudyOutcome(rng, s, ctx.data.findings);
      r.outcome = d.outcome;
      if (d.outcome === 'peor') {
        r.capexFactor = d.capexFactor;
        p.capexFactor *= d.capexFactor ?? 1;
        events.push(note(state, p, 'studyCompleted', `${s.nombre}: peor de lo esperado. ${s.peor_descripcion ?? ''} (CAPEX +${(((d.capexFactor ?? 1) - 1) * 100).toFixed(1)} %).`, 'malo', { studyId: s.id, outcome: 'peor' }));
      } else if (d.outcome === 'bloqueo') {
        const f = ctx.data.findings[d.findingId!];
        r.findingId = f.id;
        p.findings.push({ id: f.id, studyId: s.id, status: f.mitigable ? 'abierto' : 'fatal', costUsd: 0, attempts: 0 });
        events.push(note(state, p, 'studyCompleted', `${s.nombre}: hallazgo que bloquea el proyecto.`, 'malo', { studyId: s.id, outcome: 'bloqueo' }));
        events.push(note(state, p, 'findingDiscovered', `${f.nombre}: ${f.descripcion}${f.mitigable ? '' : ' No es mitigable.'}`, 'malo', { findingId: f.id, mitigable: f.mitigable }));
      } else {
        events.push(note(state, p, 'studyCompleted', `${s.nombre}: sin sorpresas.`, 'bueno', { studyId: s.id, outcome: 'normal' }));
      }
    }
  }

  // Mitigación de hallazgos
  for (const f of p.findings) {
    if (f.status !== 'en_mitigacion' || t < (f.endTick ?? 0)) continue;
    const d = ctx.data.findings[f.id];
    const ok = rng.chance(d.prob_exito_mitigacion ?? 0.5);
    f.status = ok ? 'mitigado' : 'abierto';
    events.push(note(state, p, 'findingResolved', ok ? `Hallazgo resuelto: ${d.nombre}.` : `La mitigación de «${d.nombre}» no funcionó: hay que intentarlo otra vez o abandonar.`, ok ? 'bueno' : 'malo', { findingId: f.id, success: ok }));
  }

  // Permisos
  for (const r of Object.values(p.permits)) {
    if (r.status !== 'en_tramite' || t < r.endTick) continue;
    const d = c.permisos.find((x) => x.id === r.permitId)!;
    const dec = drawPermitDecision(rng, d, r.infoRequests);
    if (dec === 'info_adicional') {
      const delay = drawDays(rng, d.info_adicional.retraso_dias);
      const cost = d.info_adicional.costo_usd.base;
      r.infoRequests += 1;
      r.endTick = t + delay;
      r.costUsd += cost;
      p.devCostUsd += cost;
      postCash(state, 'inversion_desarrollo', -cost, `${p.name}: información adicional para ${d.nombre}`);
      events.push(note(state, p, 'permitInfoRequested', `${d.autoridad} pide información adicional para ${d.nombre}: +${delay} días y ${fmtUsd(cost)}.`, 'malo', { permitId: d.id, delayDays: delay, costUsd: cost }));
    } else {
      r.status = dec;
      const ok = dec === 'aprobado';
      events.push(note(state, p, 'permitDecided', ok ? `Aprobado: ${d.nombre} (${d.autoridad}).` : `Rechazado: ${d.nombre} (${d.autoridad}).${d.reintentable ? ' Se puede volver a solicitar.' : ''}`, ok ? 'bueno' : 'malo', { permitId: d.id, approved: ok }));
    }
  }

  // PPA
  if (p.ppa?.status === 'en_proceso' && t >= p.ppa.endTick) {
    const ch = c.ppa.canales.find((x) => x.id === p.ppa!.channelId)!;
    if (rng.chance(ch.prob_exito)) {
      p.ppa.status = 'firmado';
      p.ppa.priceUsdMwh = drawDist(rng, ch.precio_usd_mwh);
      p.ppa.codDeadlineTick = t + Math.round(ch.plazo_cod_meses * DAYS_PER_MONTH);
      events.push(note(state, p, 'ppaResult', `PPA firmado (${ch.nombre}): ${p.ppa.priceUsdMwh.toFixed(1)} USD/MWh por ${ch.plazo_anos} años. Operación comercial exigida en ${ch.plazo_cod_meses} meses.`, 'bueno', { channelId: ch.id, success: true, priceUsdMwh: p.ppa.priceUsdMwh }));
    } else {
      p.ppa.status = 'fallido';
      events.push(note(state, p, 'ppaResult', `No se consiguió el PPA (${ch.nombre}). Se puede intentar otra vez o vender al spot.`, 'malo', { channelId: ch.id, success: false }));
    }
  }

  // Financiamiento
  if (p.financing?.status === 'en_proceso' && t >= p.financing.endTick) closeFinancing(state, ctx, p, rng, events);

  // Venta
  if (p.sale?.status === 'en_proceso' && t >= p.sale.endTick) {
    const prob = p.operation ? 0.95 : p.construction ? 0.85 : 0.8;
    if (rng.chance(prob)) {
      const value = saleValueUsd(state, ctx, p) * (1 - p.partnerShare);
      const fee = value * 0.02;
      const book = bookValue(p);
      const debt = p.debt?.outstandingUsd ?? 0;
      postCash(state, 'venta_activos', value, `${p.name}: venta`);
      postCash(state, 'desarrollo_gasto', -fee, `${p.name}: comisión de venta`);
      accrue(state, 'resultado_venta', value - (book - debt));
      p.sale.status = 'vendido';
      p.sale.priceUsd = value;
      p.stage = 'vendido';
      p.endTick = t;
      events.push(note(state, p, 'projectSold', `Proyecto vendido por ${fmtUsd(value)}${debt > 0 ? ` (el comprador asume ${fmtUsd(debt)} de deuda)` : ''}.`, 'bueno', { priceUsd: value }));
      return;
    }
    p.sale.status = 'fallido';
    events.push(note(state, p, 'saleFailed', 'No apareció un comprador a un precio razonable.', 'malo'));
  }

  if (p.construction && !p.operation) constructionDaily(state, ctx, p, rng, day, events);
  if (p.operation) operationDaily(state, ctx, p, rng, day, events);
  updateStage(ctx, p);
}

/**
 * Dimensionamiento de la deuda con el caso del banco: recurso P90 y, si no hay PPA, spot con recorte del 20 %;
 * deuda = mín(apalancamiento máx., pedido, capacidad por DSCR). Lo usan el cierre financiero y la vista previa.
 */
export function bankDebtSizing(state: GameState, ctx: SimContext, p: Project, o: { lenderId: string; budgetUsd: number; rate: number; tenorYears: number; dscr: number; requestedFraction: number }) {
  const c = ctx.data.countries[p.countryCode];
  const l = c.finanzas.prestamistas.find((x) => x.id === o.lenderId)!;
  const hasPpa = p.ppa?.status === 'firmado';
  const eco = projectEconomics(state, ctx, p, { resource: p90(p.estimate.value, p.estimate.sigma), capexUsd: o.budgetUsd, lenderId: l.id });
  const tech = ctx.data.technologies[p.techId];
  const bank = runProjectModel({
    energyMwhYear1: eco.energyP50MwhYear, degradation: tech.degradacion_anual.base, lifeYears: tech.vida_util_anos.base,
    capexUsd: o.budgetUsd, fixedCostUsdYear: eco.model.rows[0].opexUsd - tech.om_variable_usd_mwh.base * eco.model.rows[0].energyMwh,
    varCostUsdMwh: tech.om_variable_usd_mwh.base, inflation: c.inflacion_anual.base,
    ppa: hasPpa ? { priceUsdMwh: p.ppa!.priceUsdMwh, years: p.ppa!.years, indexation: p.ppa!.indexation } : undefined,
    spotPriceUsdMwh: eco.priceAssumption === 'spot' ? eco.priceUsdMwh * 0.8 : eco.priceUsdMwh, taxRate: c.impuestos.renta.base,
    depreciationYears: c.impuestos.depreciacion_anos.base, taxCreditUsd: 0, taxCreditMaxFrac: 0, decommissionUsd: 0,
  });
  const cfads = bank.rows.map((r) => r.ebitdaUsd - r.taxUnleveredUsd);
  return sizeDebt({ cfads, dscr: o.dscr, rate: o.rate, tenorYears: o.tenorYears, maxLeverage: l.apalancamiento_max, requestedFraction: o.requestedFraction, budgetUsd: o.budgetUsd });
}

function closeFinancing(state: GameState, ctx: SimContext, p: Project, rng: Rng, events: SimEvent[]) {
  const f = p.financing!;
  const c = ctx.data.countries[p.countryCode];
  const l = c.finanzas.prestamistas.find((x) => x.id === f.lenderId)!;
  const blockers = financingBlockers(ctx, p);
  if (blockers.length || !rng.chance(l.prob_aprobacion)) {
    f.status = 'fallido';
    f.failReason = blockers.length ? blockers.join(' ') : 'El comité de crédito rechazó el proyecto.';
    events.push(note(state, p, 'financingResult', `${l.nombre}: ${f.failReason}`, 'malo', { success: false }));
    return;
  }
  const sized = bankDebtSizing(state, ctx, p, { lenderId: l.id, budgetUsd: f.budgetUsd, rate: f.rate, tenorYears: f.tenorYears, dscr: f.dscrTarget, requestedFraction: f.requestedDebtFraction });
  if (sized.debtUsd < l.monto_min_usd) {
    f.status = 'fallido';
    f.failReason = `Con la cobertura exigida (DSCR ${f.dscrTarget}) el banco solo prestaría ${fmtUsd(sized.debtUsd)}, menos de su mínimo.`;
    events.push(note(state, p, 'financingResult', `${l.nombre}: ${f.failReason}`, 'malo', { success: false }));
    return;
  }
  const commission = sized.debtUsd * l.comision_estructuracion;
  p.devCostUsd += commission;
  postCash(state, 'inversion_desarrollo', -commission, `${p.name}: comisión de estructuración`);
  f.feesUsd += commission;
  f.debtUsd = sized.debtUsd;
  f.equityUsd = f.budgetUsd - sized.debtUsd;
  f.status = 'cerrado';
  p.partnerShare = f.partnerShare;
  payPartnerPremium(state, ctx, p, events);
  const lim = sized.limitedBy === 'dscr' ? ' (limitada por la cobertura de deuda)' : '';
  events.push(note(state, p, 'financingResult',
    `Cierre financiero con ${l.nombre}: deuda ${fmtUsd(sized.debtUsd)}${lim} al ${(f.rate * 100).toFixed(2)} % a ${f.tenorYears} años; capital ${fmtUsd(f.equityUsd)}${f.partnerShare > 0 ? ` (socio ${Math.round(f.partnerShare * 100)} %)` : ''}.`,
    'bueno', { success: true, debtUsd: sized.debtUsd, equityUsd: f.equityUsd }));
}

function constructionDaily(state: GameState, ctx: SimContext, p: Project, rng: Rng, day: GameDate, events: SimEvent[]) {
  const k = p.construction!;
  const t = state.tick;
  const tech = ctx.data.technologies[p.techId];
  const c = ctx.data.countries[p.countryCode];

  if (!k.equipmentArrived && t >= k.equipmentArrivalTick) {
    k.equipmentArrived = true;
    if (k.equipmentLateDays > 0 && p.suppliers) recordLateDelivery(state, p.suppliers.equipmentId);
    events.push(note(state, p, 'equipmentArrived', k.equipmentLateDays > 0 ? `Llegaron los equipos con ${k.equipmentLateDays} días de retraso.` : 'Llegaron los equipos a tiempo.', k.equipmentLateDays > 0 ? 'malo' : 'bueno', { lateDays: k.equipmentLateDays }));
  }

  // Puesta en marcha
  if (k.commissioningStartTick !== undefined) {
    if (t >= k.commissioningStartTick + (k.commissioningDays ?? 0)) startOperation(state, ctx, p, rng, events);
    return;
  }

  if (k.stoppedDays > 0) { k.stoppedDays--; k.delayDays++; return; }
  const m = k.milestones.find((x) => !x.done);
  if (!m) return;
  const def = tech.hitos_construccion.find((x) => x.id === m.id);
  if (def?.requiere_equipos && !k.equipmentArrived) { k.delayDays++; return; }
  let rate = 1 / k.plannedDays;
  if (def?.sensible_lluvia && c.construccion.meses_lluviosos.includes(day.month)) rate *= c.construccion.factor_avance_lluvia;
  const before = k.progress;
  k.progress = Math.min(m.end, k.progress + rate);
  const spend = (k.progress - before) * k.budgetUsd;
  k.spentUsd += spend;
  k.monthSpendUsd += spend;
  if (k.progress >= m.end - 1e-12) {
    m.done = true;
    k.progress = m.end;
    events.push(note(state, p, 'milestoneCompleted', `Hito completado: ${m.nombre}.`, 'bueno', { milestoneId: m.id }));
    const epc = ctx.data.suppliers[p.suppliers!.epcId];
    if (rng.chance(epc.prob_sobrecosto_hito ?? 0.15)) {
      const amt = rng.triangular(0.02, 0.06, 0.2) * m.fraction * k.budgetUsd;
      k.overrunUsd += amt;
      k.monthOverrunUsd += amt;
      k.spentUsd += amt;
      events.push(note(state, p, 'costOverrun', `Sobrecosto en «${m.nombre}»: ${fmtUsd(amt)} (se paga con capital).`, 'malo', { amountUsd: amt, milestoneId: m.id }));
    }
    if (k.milestones.every((x) => x.done)) {
      const eq = ctx.data.suppliers[p.suppliers!.equipmentId];
      let days = drawDays(rng, tech.puesta_en_marcha_dias);
      const pDefect = (1 - eq.calidad) * 0.6 + (1 - epc.calidad) * 0.3;
      if (rng.chance(pDefect)) {
        const extra = Math.round(rng.triangular(15, 30, 75));
        days += extra;
        events.push(note(state, p, 'qualityDefect', `Defectos de calidad en las pruebas: ${extra} días extra para corregirlos.`, 'malo', { days: extra }));
      }
      k.commissioningStartTick = t;
      k.commissioningDays = days;
      events.push(note(state, p, 'commissioningStarted', `Obra terminada: comienza la puesta en marcha (~${days} días).`, 'bueno'));
    }
  }
}

function startOperation(state: GameState, ctx: SimContext, p: Project, rng: Rng, events: SimEvent[]) {
  const k = p.construction!;
  const tech = ctx.data.technologies[p.techId];
  const c = ctx.data.countries[p.countryCode];
  const eq = ctx.data.suppliers[p.suppliers!.equipmentId];
  // Se liquida el gasto pendiente del mes antes de pasar a operación
  settleConstructionMonth(state, ctx, p, events);
  const gross = p.devCostUsd + k.spentUsd + k.idcUsd;
  const fcBonus = researchEffects(state, ctx).fcMult(p.techId);
  const fcReal = capacityFactor(tech, p.site.cellValue * p.site.realFactor, p.site.temperatureC) * fcBonus;
  p.operation = {
    codTick: state.tick,
    endOfLifeTick: state.tick + Math.round(tech.vida_util_anos.base * 365.25),
    maintenance: 'preventivo',
    outages: [],
    fcReal,
    fcBonus,
    yearFactor: Math.max(0.6, 1 + tech.variabilidad.interanual * rng.normal()),
    failureMultiplier: 1 + (1 - eq.confiabilidad) * 2,
    month: { energyMwh: 0, availSum: 0, days: 0, repairUsd: 0 },
    history: [],
    totalEnergyMwh: 0,
    totalRevenueUsd: 0,
    grossAssetUsd: gross,
    accumulatedDepreciationUsd: 0,
  };
  if (p.debt && p.debt.outstandingUsd > 0) {
    p.debt.principalUsd = p.debt.outstandingUsd;
    p.debt.monthlyPayment = annuityPayment(p.debt.outstandingUsd, p.debt.rate / 12, p.debt.tenorMonths);
    p.debt.monthsPaid = 0;
  }
  const inc = c.incentivos[p.techId];
  if (inc) state.finance.taxCreditUsd += inc.credito_fiscal_frac_inversion.base * (k.spentUsd);
  const months = Math.round((state.tick - k.startTick) / DAYS_PER_MONTH);
  events.push(note(state, p, 'projectOperational', `¡Operación comercial! Obra en ${months} meses (${k.delayDays} días de retraso), costo ${fmtUsd(k.spentUsd)} (${k.overrunUsd > 0 ? `+${fmtUsd(k.overrunUsd)} de sobrecostos` : 'sin sobrecostos'}).`, 'bueno'));
}

function operationDaily(state: GameState, ctx: SimContext, p: Project, rng: Rng, day: GameDate, events: SimEvent[]) {
  const op = p.operation!;
  const tech = ctx.data.technologies[p.techId];
  const c = ctx.data.countries[p.countryCode];
  if (state.tick >= op.endOfLifeTick) {
    decommission(state, ctx, p, events, 'Fin de la vida útil: planta desmantelada');
    return;
  }
  for (const o of op.outages) o.daysLeft--;
  op.outages = op.outages.filter((o) => o.daysLeft > 0);
  const pf = op.maintenance === 'preventivo' ? tech.mantenimiento.preventivo_fallas_factor : 1;
  const ratePerDay = tech.fallas.eventos_ano_por_mw.base * p.mw * pf * op.failureMultiplier / 365;
  if (rng.chance(Math.min(0.5, ratePerDay))) {
    const frac = drawDist(rng, tech.fallas.fraccion_afectada);
    const days = drawDays(rng, tech.fallas.duracion_dias);
    const cost = drawDist(rng, tech.fallas.costo_reparacion_usd_kw) * frac * p.mw * 1000;
    op.outages.push({ fraction: frac, daysLeft: days });
    op.month.repairUsd += cost;
    (op.failures ??= []).push({ tick: state.tick, fraction: frac, days, costUsd: cost });
    if (op.failures.length > 100) op.failures.splice(0, op.failures.length - 100);
    if (frac * days >= 0.5) {
      events.push(note(state, p, 'plantFailure', `Falla: ${(frac * 100).toFixed(0)} % de la planta fuera de servicio por ${days} días (reparación ${fmtUsd(cost)}).`, 'malo', { fractionLost: frac, days, costUsd: cost }));
    }
  }
  const lost = Math.min(1, op.outages.reduce((a, o) => a + o.fraction, 0));
  const avail = (1 - lost) * (1 - tech.mantenimiento.programado_perdida);
  const prof = normalizedProfile(c.perfil_recurso_mensual[p.site.layer]);
  const noise = Math.max(0.05, 1 + tech.variabilidad.diaria * rng.normal());
  const age = (state.tick - op.codTick) / 365.25;
  const deg = Math.pow(1 - tech.degradacion_anual.base, age);
  const energy = p.mw * 24 * op.fcReal * prof[day.month - 1] * noise * op.yearFactor * deg * avail;
  op.month.energyMwh += energy;
  op.month.availSum += avail;
  op.month.days += 1;
}

/** Nuevo año: nuevo factor climático interanual en las plantas en operación. */
export function projectNewYear(ctx: SimContext, p: Project, rng: Rng) {
  if (!p.operation || isTerminal(p)) return;
  const tech = ctx.data.technologies[p.techId];
  p.operation.yearFactor = Math.max(0.6, 1 + tech.variabilidad.interanual * rng.normal());
}

function settleConstructionMonth(state: GameState, ctx: SimContext, p: Project, _events: SimEvent[]) {
  const k = p.construction!;
  const f = p.financing!;
  const spend = k.monthSpendUsd;
  const overrun = k.monthOverrunUsd;
  if (spend + overrun <= 0) return;
  const debtShare = f.budgetUsd > 0 ? f.debtUsd / f.budgetUsd : 0;
  let draw = 0;
  if (p.debt) {
    draw = Math.min(spend * debtShare, Math.max(0, f.debtUsd - p.debt.principalUsd));
    p.debt.principalUsd += draw;
    p.debt.outstandingUsd += draw;
  }
  const equityNeed = spend + overrun - draw;
  const partner = equityNeed * f.partnerShare;
  postCash(state, 'inversion_construccion', -(spend + overrun), `${p.name}: construcción`);
  if (draw > 0) postCash(state, 'deuda_desembolso', draw, `${p.name}: desembolso de deuda`);
  if (partner > 0) postCash(state, 'socio_aporte', partner, `${p.name}: aporte del socio`);
  k.monthSpendUsd = 0;
  k.monthOverrunUsd = 0;
  void ctx;
}

/** Cierre de mes de un proyecto: liquida construcción, opciones de terreno, operación y deuda. */
export function projectMonthly(state: GameState, ctx: SimContext, p: Project, rng: Rng, year: number, month: number, events: SimEvent[]) {
  if (isTerminal(p)) return;
  const tech = ctx.data.technologies[p.techId];
  const c = ctx.data.countries[p.countryCode];

  if (!p.construction && !p.operation) {
    const opt = landHa(tech, p.mw) * c.costos.opcion_terreno_usd_ha_ano.base / 12;
    p.devExpenseUsd += opt;
    postCash(state, 'desarrollo_gasto', -opt, `${p.name}: opción de terreno`);
  }

  if (p.construction && !p.operation) {
    settleConstructionMonth(state, ctx, p, events);
    if (p.debt && p.debt.outstandingUsd > 0) {
      const idc = p.debt.outstandingUsd * p.debt.rate / 12;
      p.debt.outstandingUsd += idc;
      p.construction.idcUsd += idc;
    }
    const k = p.construction;
    if (k.commissioningStartTick === undefined) {
      const rainy = c.construccion.meses_lluviosos.includes(month);
      if (rng.chance(c.construccion.huelga_prob_mensual)) {
        const d = drawDays(rng, c.construccion.huelga_duracion_dias);
        k.stoppedDays += d;
        events.push(note(state, p, 'constructionDelay', `Huelga y cierre de vías: la obra se detiene ${d} días.`, 'malo', { reason: 'huelga', days: d }));
      }
      if (rainy && rng.chance(c.construccion.clima_extremo_prob_mensual)) {
        const d = drawDays(rng, c.construccion.clima_extremo_dias);
        k.stoppedDays += d;
        events.push(note(state, p, 'constructionDelay', `Lluvias torrenciales: la obra se detiene ${d} días.`, 'malo', { reason: 'clima', days: d }));
      }
    }
  }

  // Multa por atraso de la fecha de operación comercial comprometida en el PPA
  if (p.ppa?.status === 'firmado' && !p.operation && state.tick > p.ppa.codDeadlineTick) {
    const pen = p.ppa.penaltyUsdMwMonth * p.mw;
    postCash(state, 'multas', -pen, `${p.name}: multa por atraso del PPA`);
    events.push(note(state, p, 'ppaPenalty', `Multa del PPA por no estar en operación a tiempo: ${fmtUsd(pen)}.`, 'malo', { amountUsd: pen }));
  }

  if (p.operation) operationMonthly(state, ctx, p, year, month);
}

function operationMonthly(state: GameState, ctx: SimContext, p: Project, year: number, month: number) {
  const op = p.operation!;
  const tech = ctx.data.technologies[p.techId];
  const c = ctx.data.countries[p.countryCode];
  const energy = op.month.energyMwh;
  const yearsOp = (state.tick - op.codTick) / 365.25;
  let price: number;
  if (p.ppa?.status === 'firmado' && yearsOp < p.ppa.years) price = p.ppa.priceUsdMwh * Math.pow(1 + p.ppa.indexation, Math.floor(yearsOp));
  else price = spotPrice(c, startYear(state), year, month);
  const revenue = energy * price;
  const infl = Math.pow(1 + c.inflacion_anual.base, Math.max(0, year - startYear(state)));
  const omF = op.maintenance === 'preventivo' ? tech.mantenimiento.preventivo_om_factor : tech.mantenimiento.correctivo_om_factor;
  const om = tech.om_fijo_usd_kw_ano.base * p.mw * 1000 * omF / 12 * infl * researchEffects(state, ctx).omMult(p.techId) + tech.om_variable_usd_mwh.base * energy;
  const ins = c.costos.seguro_frac_capex_ano.base * op.grossAssetUsd / 12;
  const land = landHa(tech, p.mw) * c.costos.arriendo_terreno_usd_ha_ano.base / 12 * infl;
  const repairs = op.month.repairUsd;
  postCash(state, 'ingresos', revenue, `${p.name}: venta de energía`);
  postCash(state, 'om', -om, `${p.name}: O&M`);
  postCash(state, 'seguro', -ins, `${p.name}: seguro`);
  postCash(state, 'terreno', -land, `${p.name}: arriendo`);
  postCash(state, 'reparaciones', -repairs, `${p.name}: reparaciones`);
  let interest = 0, principal = 0;
  const d = p.debt;
  if (d && d.outstandingUsd > 0.01) {
    interest = d.outstandingUsd * d.rate / 12;
    principal = d.monthsPaid >= d.tenorMonths - 1 ? d.outstandingUsd : Math.min(d.outstandingUsd, d.monthlyPayment - interest);
    d.outstandingUsd -= principal;
    d.monthsPaid += 1;
    postCash(state, 'intereses', -interest, `${p.name}: intereses`);
    postCash(state, 'deuda_amortizacion', -principal, `${p.name}: amortización`);
  }
  const depYears = c.impuestos.depreciacion_anos.base;
  const dep = Math.min(op.grossAssetUsd / (depYears * 12), op.grossAssetUsd - op.accumulatedDepreciationUsd);
  if (dep > 0) { op.accumulatedDepreciationUsd += dep; accrue(state, 'depreciacion', -dep); }
  const opex = om + ins + land + repairs;
  if (p.partnerShare > 0) {
    const projTax = Math.max(0, revenue - opex - dep - interest) * c.impuestos.renta.base;
    const distributable = revenue - opex - interest - principal - projTax;
    if (distributable > 0) postCash(state, 'socio_distribucion', -distributable * p.partnerShare, `${p.name}: dividendos del socio`);
  }
  const availability = op.month.days ? op.month.availSum / op.month.days : 0;
  op.history.push({ year, month, energyMwh: energy, revenueUsd: revenue, opexUsd: opex, availability });
  if (op.history.length > 120) op.history.splice(0, op.history.length - 120);
  op.totalEnergyMwh += energy;
  op.totalRevenueUsd += revenue;
  op.month = { energyMwh: 0, availSum: 0, days: 0, repairUsd: 0 };
}
