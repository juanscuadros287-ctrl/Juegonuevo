import type { GameState } from '../core/state';
import type { SimContext } from '../core/context';
import type { SimEvent } from '../core/events';
import type { GameDate } from '../core/calendar';
import type { Rng } from '../core/rng';
import { accrue, postCash } from '../finance/company';
import { annuityPayment } from '../finance/math';
import { capacityFactor } from '../tech/capacityFactor';
import { expectedAvailability, landHa } from '../tech/costs';
import { normalizedProfile, spotPrice } from '../market/spot';
import { drawDays, drawDist, drawPermitDecision, drawStudyOutcome, drawWells } from './outcomes';
import { effectiveDegradation, geoWellProbabilities, productionProfile, productTerms, sellsEnergy, techMode, thermalDispatch } from '../tech/models';
import { contractCurrency, fxNominal, fxReal, localCostFxFactor, usdInflation } from '../market/macro';
import { DAYS_PER_MONTH, fmtUsd, isTerminal, note, updateStage } from './helpers';
import { decommission, payPartnerPremium } from './commands';
import { bookValue, saleValueUsd } from './valuation';
import { financingBlockers } from './requirements';
import { ppaFxFactor, projectEconomics, startYear } from './economics';
import { runProjectModel, sizeDebt } from '../finance/projectModel';
import { p90 } from '../world/site';
import { researchEffects } from '../business/research';
import { recordLateDelivery } from '../supply/supply';
import type { Project } from './types';
import { projectPlan, policyKey, type MonthPlan } from '../market/dispatch';
import { yearMonthIndex } from '../market/power';
import { h2KgPerMwh } from '../tech/models';
import { insuranceMonthly, worldCreditFactor } from '../world/events';
import { operatingPermitBlockers } from './requirements';

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
    if (s.pozos_exploratorios && ctx.data.technologies[p.techId]?.geotermia) {
      geothermalExploration(state, ctx, p, s.id, rng, events);
      continue;
    }
    if (s.sigma_recurso !== undefined) {
      const real = p.site.cellValue * p.site.realFactor;
      const measured = real * (1 + s.sigma_recurso * Math.max(-3, Math.min(3, rng.normal())));
      r.measured = measured;
      const prev = p.estimate.value;
      const better = s.sigma_recurso < p.estimate.sigma;
      if (better) p.estimate = { value: measured, sigma: s.sigma_recurso, source: s.id };
      r.outcome = better && measured < prev * 0.97 ? 'peor' : 'normal';
      const delta = ((measured / prev - 1) * 100).toFixed(1);
      const unit = LAYER_UNITS[p.site.layer] ?? '';
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
      if (contractCurrency(c, ch.moneda) === 'local') { p.ppa.currency = 'local'; p.ppa.fxAtSigning = fxNominal(state, ctx, p.countryCode); }
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
    energyMwhYear1: eco.energyP50MwhYear, degradation: effectiveDegradation(tech, c), lifeYears: tech.vida_util_anos.base,
    capexUsd: o.budgetUsd, fixedCostUsdYear: eco.model.rows[0].opexUsd - (tech.om_variable_usd_mwh.base + eco.fuelCostUsdMwh) * eco.model.rows[0].energyMwh,
    varCostUsdMwh: tech.om_variable_usd_mwh.base, inflation: usdInflation(c), fuelCostUsdMwhYear1: eco.fuelCostUsdMwh,
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
    if (t >= k.commissioningStartTick + (k.commissioningDays ?? 0)) {
      // Fase 5: sin licencia de generación y contrato de conexión no se puede operar (la planta espera).
      const missing = operatingPermitBlockers(ctx, p);
      if (missing.length) {
        if (!p.codBlocked) events.push(note(state, p, 'operationBlocked', `Puesta en marcha terminada, pero no se puede operar sin: ${missing.join(', ')}.`, 'malo', { missing }));
        p.codBlocked = true;
      } else { p.codBlocked = undefined; startOperation(state, ctx, p, rng, events); }
    }
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
    if (tech.geotermia && k.wells && /perfor/.test(m.id)) drillProductionWells(state, ctx, p, rng, events);
    const ro = tech.riesgo_obra;
    if (rng.chance(Math.min(0.95, (epc.prob_sobrecosto_hito ?? 0.15) * (ro?.sobrecosto_prob_factor ?? 1)))) {
      const amt = rng.triangular(0.02, 0.06, 0.2) * (ro?.sobrecosto_magnitud_factor ?? 1) * m.fraction * k.budgetUsd;
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
  const fcReal = capacityFactor(tech, p.site.cellValue * p.site.realFactor, p.site.temperatureC, p.site.extras) * fcBonus;
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
  if (tech.eficiencia) {
    // ESCO: el ahorro garantizado se fija con la estimación (auditoría), no con el ahorro real.
    const est = capacityFactor(tech, p.estimate.value, p.site.temperatureC, p.site.extras);
    p.operation.guaranteedMwhYear = tech.eficiencia.ahorro_garantizado_frac * p.mw * 8760 * est * expectedAvailability(tech, p.mw);
  }
  if (p.debt && p.debt.outstandingUsd > 0) {
    p.debt.principalUsd = p.debt.outstandingUsd;
    p.debt.monthlyPayment = annuityPayment(p.debt.outstandingUsd, p.debt.rate / 12, p.debt.tenorMonths);
    p.debt.monthsPaid = 0;
  }
  const inc = c.incentivos[p.techId];
  if (inc) state.finance.taxCreditUsd += inc.credito_fiscal_frac_inversion.base * worldCreditFactor(state, p.countryCode) * (k.spentUsd);
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
  const prof = tech.modelo_fc === 'solar_fv' || tech.modelo_fc === 'eolica' ? normalizedProfile(c.perfil_recurso_mensual[p.site.layer]) : productionProfile(c, tech, p.site.layer);
  const noise = Math.max(0.05, 1 + tech.variabilidad.diaria * rng.normal());
  const age = (state.tick - op.codTick) / 365.25;
  const deg = Math.pow(1 - (tech.almacenamiento ? effectiveDegradation(tech, c) : tech.degradacion_anual.base), age);
  // Fase 4: despacho (térmicas por margen sobre el costo marginal; almacenamiento solo si hay arbitraje) y costos variables.
  const terms = techMode(tech) === 'generacion' ? null : monthTerms(state, ctx, p, day.year, day.month);
  if (terms && terms.mode === 'termica' && p.ppa?.status === 'firmado' && age < p.ppa.years) {
    terms.dispatch = thermalDispatch(tech, terms.fuel.varUsdMwh + tech.om_variable_usd_mwh.base, p.ppa.priceUsdMwh * ppaFxFactor(state, ctx, p.countryCode, p.ppa));
  }
  // Fase 5: despacho horario contra los precios del mes (vertimiento, térmicas por hora, arbitraje, H2, servicios).
  const plan = currentPlan(state, ctx, p, day.year, day.month);
  if (plan && terms) {
    terms.dispatch = plan.genFrac;
    if (terms.mode === 'almacenamiento') terms.fuel = { ...terms.fuel, varUsdMwh: plan.chargeUsdMwh, fuelUsdMwh: plan.chargeUsdMwh };
    if (terms.mode === 'hidrogeno') { const v = plan.chargeUsdMwh + (tech.hidrogeno?.agua_usd_kg ?? 0) * h2KgPerMwh(tech); terms.fuel = { ...terms.fuel, varUsdMwh: v, fuelUsdMwh: v }; }
  }
  const availableMwh = p.mw * 24 * op.fcReal * prof[day.month - 1] * noise * op.yearFactor * deg * avail;
  const energy = availableMwh * (plan && !terms ? plan.genFrac : terms?.dispatch ?? 1);
  if (plan) {
    if (plan.curtailedFrac > 0) op.monthCurtailedMwh = (op.monthCurtailedMwh ?? 0) + availableMwh * plan.curtailedFrac;
    if (plan.servicesFrac > 0) op.monthServiceMwH = (op.monthServiceMwH ?? 0) + p.mw * 24 * plan.servicesFrac * avail;
  }
  if (terms && terms.fuel.varUsdMwh > 0) {
    op.monthFuelUsd = (op.monthFuelUsd ?? 0) + energy * (terms.fuel.varUsdMwh - terms.fuel.carbonUsdMwh);
    op.monthCo2T = (op.monthCo2T ?? 0) + energy * terms.fuel.co2TPerMwh;
  }
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
      const ro = tech.riesgo_obra;
      if (ro && rng.chance(ro.retraso_prob_mensual)) {
        const d = drawDays(rng, ro.retraso_dias);
        k.stoppedDays += d;
        events.push(note(state, p, 'constructionDelay', `Problema técnico de obra (${tech.nombre}): ${d} días de retraso.`, 'malo', { reason: 'tecnico', days: d }));
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

  if (p.operation) operationMonthly(state, ctx, p, year, month, events);
  insuranceMonthly(state, ctx, p);
}

function operationMonthly(state: GameState, ctx: SimContext, p: Project, year: number, month: number, events?: SimEvent[]) {
  const op = p.operation!;
  const tech = ctx.data.technologies[p.techId];
  const c = ctx.data.countries[p.countryCode];
  const energy = op.month.energyMwh;
  const yearsOp = (state.tick - op.codTick) / 365.25;
  let price: number;
  const terms = techMode(tech) === 'generacion' ? null : monthTerms(state, ctx, p, year, month);
  const plan = currentPlan(state, ctx, p, year, month);
  const mode = techMode(tech);
  // Precio de mercado de lo producido: el capturado hora a hora (Fase 5) o el de la Fase 4 sin datos de mercado.
  const marketPrice = plan && (mode === 'generacion' || mode === 'termica' || mode === 'almacenamiento') ? plan.captureUsdMwh
    : terms ? terms.priceUsdMwh : spotPrice(c, startYear(state), year, month) * fxReal(state, c.iso3);
  const ppaActive = sellsEnergy(tech) && p.ppa?.status === 'firmado' && yearsOp < p.ppa.years;
  let ppaUsd = 0, spotUsd = 0, purchasesUsd = 0;
  if (ppaActive) {
    const ppaPrice = p.ppa!.priceUsdMwh * Math.pow(1 + p.ppa!.indexation, Math.floor(yearsOp)) * ppaFxFactor(state, ctx, p.countryCode, p.ppa!);
    price = ppaPrice;
    const s = p.ppa!.settlement ?? 'produccion';
    const committed = (p.ppa!.committedMwhYear ?? 0) * op.month.days / 365.25;
    const avgSpot = plan?.avgSpotUsdMwh ?? marketPrice;
    if (s === 'bloque') {
      ppaUsd = committed * ppaPrice;
      spotUsd = Math.max(0, energy - committed) * marketPrice;
      purchasesUsd = Math.max(0, committed - energy) * avgSpot;
    } else if (s === 'financiero') {
      spotUsd = energy * marketPrice;
      ppaUsd = committed * (ppaPrice - avgSpot);
    } else ppaUsd = energy * ppaPrice;
  } else {
    price = marketPrice;
    spotUsd = energy * marketPrice;
  }
  const revenue = ppaUsd + spotUsd;
  if (purchasesUsd > 0) postCash(state, 'compras_energia', -purchasesUsd, `${p.name}: compra al spot para cumplir el PPA`);
  // Fase 5: mercado de capacidad y servicios complementarios.
  let capacityUsd = 0, servicesUsd = 0;
  const pc = ctx.data.power?.paises[p.countryCode];
  const availability0 = op.month.days ? op.month.availSum / op.month.days : 0;
  const potencia = state.business?.contracts?.some((k) => k.projectId === p.id && k.kind === 'potencia' && k.status !== 'incumplido');
  if (pc?.capacidad && !potencia && (mode === 'generacion' || mode === 'termica' || mode === 'almacenamiento')) {
    const credit = ctx.data.power!.credito_firme_tecnologia[p.techId] ?? 0;
    const infl0 = Math.pow(1 + usdInflation(c), Math.max(0, year - startYear(state))) * fxReal(state, c.iso3);
    capacityUsd = pc.capacidad.precio_usd_kw_mes.base * infl0 * credit * p.mw * 1000 * availability0 * (op.month.days / 30.44);
    postCash(state, 'ingresos_capacidad', capacityUsd, `${p.name}: pago por capacidad`);
  }
  if (plan && (op.monthServiceMwH ?? 0) > 0) {
    servicesUsd = (op.monthServiceMwH ?? 0) * plan.servicesUsdMwH;
    postCash(state, 'ingresos_servicios', servicesUsd, `${p.name}: servicios complementarios`);
  }
  const curtailedMwh = op.monthCurtailedMwh ?? 0;
  op.monthCurtailedMwh = 0;
  op.monthServiceMwH = 0;
  // Costos en USD: inflación del USD (o la local si la moneda está fija) y la parte local expuesta al tipo de cambio.
  const infl = Math.pow(1 + usdInflation(c), Math.max(0, year - startYear(state))) * localCostFxFactor(state, c);
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
  // Fase 4: combustible / energía comprada e impuesto al carbono.
  const fuel = op.monthFuelUsd ?? 0;
  const co2 = op.monthCo2T ?? 0;
  const carbon = terms && terms.fuel.co2TPerMwh > 0 ? co2 * terms.fuel.carbonUsdMwh / terms.fuel.co2TPerMwh : 0;
  if (fuel > 0) postCash(state, 'combustible', -fuel, `${p.name}: ${tech.almacenamiento || tech.hidrogeno ? 'energía comprada' : tech.transmision ? 'pérdidas' : 'combustible'}`);
  if (carbon > 0) postCash(state, 'carbono', -carbon, `${p.name}: impuesto al carbono (${co2.toFixed(0)} tCO2)`);
  op.monthFuelUsd = 0;
  op.monthCo2T = 0;
  // ESCO: si el ahorro real del mes queda bajo el garantizado, se paga la diferencia al precio del contrato.
  let shortfallPen = 0;
  if (op.guaranteedMwhYear && op.month.days > 0) {
    const short = op.guaranteedMwhYear * op.month.days / 365.25 - energy;
    if (short > 0) {
      shortfallPen = short * price;
      postCash(state, 'multas', -shortfallPen, `${p.name}: ahorro garantizado no alcanzado`);
      events?.push(note(state, p, 'savingsShortfall', `Ahorro del mes ${Math.round(short)} MWh por debajo del garantizado: se compensa al cliente con ${fmtUsd(shortfallPen)}.`, 'malo', { shortfallMwh: short, penaltyUsd: shortfallPen }));
    }
  }
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
  const opex = om + ins + land + repairs + fuel + carbon + shortfallPen + purchasesUsd;
  if (p.partnerShare > 0) {
    const projTax = Math.max(0, revenue + capacityUsd + servicesUsd - opex - dep - interest) * c.impuestos.renta.base;
    const distributable = revenue + capacityUsd + servicesUsd - opex - interest - principal - projTax;
    if (distributable > 0) postCash(state, 'socio_distribucion', -distributable * p.partnerShare, `${p.name}: dividendos del socio`);
  }
  const availability = op.month.days ? op.month.availSum / op.month.days : 0;
  op.history.push({ year, month, energyMwh: energy, revenueUsd: revenue + capacityUsd + servicesUsd - purchasesUsd, opexUsd: opex, availability,
    ppaUsd, spotUsd, capacityUsd, servicesUsd, purchasesUsd, curtailedMwh, captureUsdMwh: marketPrice });
  if (op.history.length > 120) op.history.splice(0, op.history.length - 120);
  op.totalEnergyMwh += energy;
  op.totalRevenueUsd += revenue + capacityUsd + servicesUsd - purchasesUsd;
  op.month = { energyMwh: 0, availSum: 0, days: 0, repairUsd: 0 };
}

const LAYER_UNITS: Record<string, string> = {
  ghi: 'kWh/m²/día', dni: 'kWh/m²/día', viento_tierra: 'm/s', viento_mar: 'm/s', geotermia: 'mW/m²', hidro: '(índice hidro)',
  biomasa: 'g/m²/año', sin_recurso: '(índice)',
};

/** Términos del mes (precio del producto, despacho, combustible) con el spot del mes y el tipo de cambio actual. */
function monthTerms(state: GameState, ctx: SimContext, p: Project, year: number, month: number) {
  const tech = ctx.data.technologies[p.techId];
  const c = ctx.data.countries[p.countryCode];
  const y0 = startYear(state);
  const to = p.site.extras?.to;
  const other = to && to.countryCode !== p.countryCode ? ctx.data.countries[to.countryCode] : undefined;
  return productTerms(state, ctx, tech, c, {
    spotUsdMwh: spotPrice(c, y0, year, month) * fxReal(state, c.iso3), capture: tech.termica?.prima_captura ?? 1, yearsFromStart: year - y0,
    resourceValue: p.site.cellValue * p.site.realFactor, extras: p.site.extras,
    otherSpotUsdMwh: other ? spotPrice(other, y0, year, month) * fxReal(state, other.iso3) : undefined,
  });
}

/**
 * Geotermia: campaña de pozos exploratorios. Cada pozo sale seco, de baja entalpía o productivo según el recurso REAL;
 * si al menos uno encuentra fluido, las pruebas de producción reemplazan la estimación. Si todos salen secos, hallazgo.
 */
function geothermalExploration(state: GameState, ctx: SimContext, p: Project, studyId: string, rng: Rng, events: SimEvent[]) {
  const s = ctx.data.studies[studyId];
  const tech = ctx.data.technologies[p.techId];
  const r = p.studies[studyId];
  const real = p.site.cellValue * p.site.realFactor;
  const pr = geoWellProbabilities(tech, real);
  const w = drawWells(rng, s.pozos_exploratorios!, pr.dry, pr.low);
  const txt = `${s.nombre}: ${w.productive} productivo(s), ${w.low} de baja entalpía y ${w.dry} seco(s) de ${s.pozos_exploratorios}.`;
  if (w.productive + w.low === 0) {
    r.outcome = 'bloqueo';
    const fid = s.hallazgo_pozos_secos ?? 'reservorio_no_comercial';
    const f = ctx.data.findings[fid];
    r.findingId = fid;
    if (f) p.findings.push({ id: fid, studyId, status: f.mitigable ? 'abierto' : 'fatal', costUsd: 0, attempts: 0 });
    events.push(note(state, p, 'studyCompleted', `${txt} Ningún pozo encontró un reservorio comercial.`, 'malo', { studyId, outcome: 'bloqueo' }));
    if (f) events.push(note(state, p, 'findingDiscovered', `${f.nombre}: ${f.descripcion}`, 'malo', { findingId: fid, mitigable: f.mitigable }));
    return;
  }
  // Pruebas de producción: medición del recurso; los pozos de baja entalpía bajan la lectura del reservorio.
  const lowShare = w.low / (w.low + w.productive);
  const measured = real * (1 + (s.sigma_recurso ?? 0.08) * Math.max(-3, Math.min(3, rng.normal()))) * (1 - 0.1 * lowShare);
  const prev = p.estimate.value;
  r.measured = measured;
  if ((s.sigma_recurso ?? 1) < p.estimate.sigma) p.estimate = { value: measured, sigma: s.sigma_recurso!, source: s.id };
  r.outcome = measured < prev * 0.97 || w.dry > 0 ? 'peor' : 'normal';
  const mwWell = geoWellProbabilities(tech, measured).mwPerWell;
  events.push(note(state, p, 'studyCompleted', `${txt} Reservorio ≈${measured.toFixed(0)} mW/m² (≈${mwWell.toFixed(1)} MW por pozo productor).`, r.outcome === 'peor' ? 'malo' : 'bueno', { studyId, outcome: r.outcome }));
}

/**
 * Geotermia: al terminar el hito de perforación se conocen los pozos reales. Hacen falta productores según el MW por
 * pozo REAL y cada pozo de desarrollo puede salir seco; los pozos extra sobre lo planificado son sobrecosto.
 */
function drillProductionWells(state: GameState, ctx: SimContext, p: Project, rng: Rng, events: SimEvent[]) {
  const tech = ctx.data.technologies[p.techId];
  const g = tech.geotermia!;
  const k = p.construction!;
  const w = k.wells!;
  const real = p.site.cellValue * p.site.realFactor;
  const pr = geoWellProbabilities(tech, real, true);
  const needProducers = Math.max(1, Math.ceil(p.mw / Math.max(0.5, pr.mwPerWell)));
  let producers = 0, drilled = 0, dry = 0;
  while (producers < needProducers && drilled < needProducers * 4) {
    drilled++;
    if (rng.chance(pr.dry)) dry++; else producers++;
  }
  const injectors = Math.max(1, Math.ceil(producers * g.reinyectores_por_productor));
  const extraWells = drilled + injectors - (w.plannedProducers + w.plannedInjectors);
  w.drilled = drilled + injectors;
  w.dry = dry;
  const cost = Math.max(0, extraWells) * drawDist(rng, g.costo_pozo_usd);
  if (cost > 0) { k.overrunUsd += cost; k.monthOverrunUsd += cost; k.spentUsd += cost; }
  events.push(note(state, p, 'wellsDrilled',
    `Perforación terminada: ${producers} productores (${dry} pozo(s) seco(s)) y ${injectors} reinyectores; planificados ${w.plannedProducers} + ${w.plannedInjectors}.${cost > 0 ? ` Sobrecosto ${fmtUsd(cost)} (lo paga el capital).` : ''}`,
    cost > 0 || dry > 0 ? 'malo' : 'bueno', { producers, injectors, dry, extraCostUsd: cost }));
}

/**
 * Fase 5: plan de despacho del mes de una planta en operación (cacheado en `operation.plan`; se recalcula si cambian los
 * precios del mes o la política). Sin datos del mercado eléctrico devuelve undefined (comportamiento de la Fase 4).
 */
export function currentPlan(state: GameState, ctx: SimContext, p: Project, year: number, month: number): MonthPlan | undefined {
  const op = p.operation;
  if (!op || !ctx.data.power?.paises[p.countryCode]) return undefined;
  const tech = ctx.data.technologies[p.techId];
  const ps = state.market?.power;
  const key = `${ps?.version ?? 0}|${policyKey(p)}`;
  const target = yearMonthIndex(year, month);
  if (op.plan && op.plan.ym === target && op.plan.key === key) return op.plan;
  const mode = techMode(tech);
  const terms = mode === 'termica' || mode === 'hidrogeno' ? monthTerms(state, ctx, p, year, month) : undefined;
  const yearsOp = (state.tick - op.codTick) / 365.25;
  const ppaPrice = sellsEnergy(tech) && p.ppa?.status === 'firmado' && yearsOp < p.ppa.years && (p.ppa.settlement ?? 'produccion') === 'produccion'
    ? p.ppa.priceUsdMwh * Math.pow(1 + p.ppa.indexation, Math.floor(yearsOp)) * ppaFxFactor(state, ctx, p.countryCode, p.ppa) : undefined;
  const h2Value = tech.hidrogeno && terms ? terms.priceUsdMwh - tech.hidrogeno.agua_usd_kg * h2KgPerMwh(tech) - tech.om_variable_usd_mwh.base : undefined;
  const d = projectPlan(state, ctx, p, year, month, {
    thermalMcUsdMwh: terms && mode === 'termica' ? terms.fuel.varUsdMwh + tech.om_variable_usd_mwh.base : undefined,
    ppaPriceUsdMwh: ppaPrice, h2ValueUsdMwh: h2Value, fcRef: op.fcReal,
  });
  if (!d) return undefined;
  const { gen: _g, charge: _c, price: _p, ...plan } = d;
  void _g; void _c; void _p;
  plan.key = key;
  op.plan = plan;
  return plan;
}
