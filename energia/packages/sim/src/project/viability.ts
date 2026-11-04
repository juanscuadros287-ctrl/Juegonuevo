import type { GameState } from '../core/state';
import type { SimContext } from '../core/context';
import { Rng, hashString, seedStream } from '../core/rng';
import { percentile } from '../finance/math';
import { capexBreakdown } from '../tech/costs';
import { DAYS_PER_MONTH } from './helpers';
import { drawDays, drawDist, drawPermitDecision, drawStudyOutcome, findingCostUsd, permitCostUsd, studyCostUsd } from './outcomes';
import { applicablePermits, permitGroupApplicable, requiredStudyGroups, studyGroupApplicable } from './requirements';
import { bankableStudy } from './valuation';
import { projectEconomics } from './economics';
import type { Project } from './types';

export interface ViabilityResult {
  runs: number;
  /** Probabilidad de llegar a operación comercial. */
  probCod: number;
  monthsToCodP50: number | null;
  monthsToCodP90: number | null;
  /** Costo total por gastar (desarrollo restante + construcción con sobrecostos), USD. */
  costP50Usd: number | null;
  costP90Usd: number | null;
  irrEquityP50: number | null;
  /** P10 = escenario malo (solo el 10 % de las corridas exitosas rinde menos). */
  irrEquityP10: number | null;
  /** VAN esperado del equity (incluye las corridas que fracasan con su costo hundido). */
  npvExpectedUsd: number;
  /** Causas de fracaso: estudio/hallazgo, permiso, financiamiento. */
  failures: Record<string, number>;
}

interface RunOut { ok: boolean; reason?: string; days: number; cost: number; irr: number | null; npv: number }

/**
 * Verificador de viabilidad: N corridas Monte Carlo del resto del ciclo con un RNG propio.
 * No modifica el estado. Usa la estimación del jugador (P50 ± σ), nunca el recurso real oculto.
 */
export function checkViability(state: GameState, ctx: SimContext, projectId: string, opts: { runs?: number; seed?: number } = {}): ViabilityResult {
  const p = state.projects.find((x) => x.id === projectId);
  if (!p) throw new Error(`Proyecto inexistente: ${projectId}`);
  const runs = Math.max(1, Math.floor(opts.runs ?? 500));
  const seed = opts.seed ?? ((state.seed ^ hashString(`${projectId}@${state.tick}`)) >>> 0);
  const rng = new Rng(seedStream(seed, 'viabilidad'));
  const outs: RunOut[] = [];
  for (let i = 0; i < runs; i++) outs.push(runOnce(state, ctx, p, rng));
  const ok = outs.filter((o) => o.ok);
  const failures: Record<string, number> = {};
  for (const o of outs) if (!o.ok) failures[o.reason!] = (failures[o.reason!] ?? 0) + 1;
  const irrs = ok.map((o) => o.irr).filter((x): x is number => x !== null);
  return {
    runs,
    probCod: ok.length / runs,
    monthsToCodP50: ok.length ? percentile(ok.map((o) => o.days / DAYS_PER_MONTH), 0.5) : null,
    monthsToCodP90: ok.length ? percentile(ok.map((o) => o.days / DAYS_PER_MONTH), 0.9) : null,
    costP50Usd: ok.length ? percentile(ok.map((o) => o.cost), 0.5) : null,
    costP90Usd: ok.length ? percentile(ok.map((o) => o.cost), 0.9) : null,
    irrEquityP50: irrs.length ? percentile(irrs, 0.5) : null,
    irrEquityP10: irrs.length ? percentile(irrs, 0.1) : null,
    npvExpectedUsd: outs.reduce((a, o) => a + o.npv, 0) / runs,
    failures,
  };
}

function runOnce(state: GameState, ctx: SimContext, p: Project, rng: Rng): RunOut {
  const t0 = state.tick;
  const c = ctx.data.countries[p.countryCode];
  const tech = ctx.data.technologies[p.techId];
  let dev = 0;
  let capexFactor = p.capexFactor;
  const fail = (reason: string): RunOut => ({ ok: false, reason, days: 0, cost: dev, irr: null, npv: -dev });

  /** Mitiga un hallazgo (hasta 2 intentos). Devuelve días o null si fracasa. */
  const mitigate = (findingId: string): number | null => {
    const f = ctx.data.findings[findingId];
    if (!f.mitigable) return null;
    let days = 0;
    for (let k = 0; k < 2; k++) {
      dev += findingCostUsd(f, p.mw);
      days += f.retraso_dias ? drawDays(rng, f.retraso_dias) : 60;
      if (rng.chance(f.prob_exito_mitigacion ?? 0.5)) return days;
    }
    return null;
  };

  let blocker: string | null = null;
  // Hallazgos ya abiertos
  let findingsDelay = 0;
  for (const f of p.findings) {
    if (f.status === 'fatal') return fail('hallazgo');
    if (f.status === 'abierto' || f.status === 'en_mitigacion') {
      const d = mitigate(f.id);
      if (d === null) return fail('hallazgo');
      findingsDelay = Math.max(findingsDelay, d);
    }
  }

  // Estudios (grupos), con dependencias
  const groupDone = new Map<string, number>();
  const studyGroupFinish = (g: string): number => {
    if (groupDone.has(g)) return groupDone.get(g)!;
    if (!studyGroupApplicable(ctx, p, g)) { groupDone.set(g, 0); return 0; }
    const recs = Object.values(p.studies).filter((r) => ctx.data.studies[r.studyId]?.grupo === g);
    const done = recs.find((r) => r.status === 'completado');
    if (done) { groupDone.set(g, findingsDelay); return findingsDelay; }
    const running = recs.find((r) => r.status === 'en_curso');
    const s = running ? ctx.data.studies[running.studyId] : bankableStudy(ctx, p, g);
    let start = 0;
    if (!running) for (const req of s.requiere) start = Math.max(start, studyGroupFinish(req));
    if (!running) dev += studyCostUsd(s, p.mw);
    let end = running ? Math.max(0, running.endTick - t0) : start + drawDays(rng, s.duracion_dias);
    if (s.sigma_recurso === undefined) {
      const d = drawStudyOutcome(rng, s, ctx.data.findings);
      if (d.outcome === 'peor') capexFactor *= d.capexFactor ?? 1;
      if (d.outcome === 'bloqueo') {
        const m = mitigate(d.findingId!);
        if (m === null) blocker = 'hallazgo';
        else end += m;
      }
    }
    end = Math.max(end, findingsDelay);
    groupDone.set(g, end);
    return end;
  };
  let studiesEnd = 0;
  for (const g of requiredStudyGroups(ctx, p)) studiesEnd = Math.max(studiesEnd, studyGroupFinish(g));
  if (blocker) return fail(blocker);

  // Permisos (grafo)
  const permitDone = new Map<string, number>();
  const permits = applicablePermits(ctx, p);
  const permitGroupFinish = (g: string): number => {
    if (permitDone.has(g)) return permitDone.get(g)!;
    const d = permits.find((x) => x.grupo === g);
    if (!d) { permitDone.set(g, 0); return 0; }
    const rec = p.permits[d.id];
    if (rec?.status === 'aprobado') { permitDone.set(g, 0); return 0; }
    let start = 0;
    for (const sg of d.requiere.estudios) start = Math.max(start, studyGroupFinish(sg));
    for (const pg of d.requiere.permisos) if (permitGroupApplicable(ctx, p, pg)) start = Math.max(start, permitGroupFinish(pg));
    let time = start;
    let tries = 0;
    let info = rec?.status === 'en_tramite' ? rec.infoRequests : 0;
    if (rec?.status === 'en_tramite') time = Math.max(time, rec.endTick - t0);
    else { dev += permitCostUsd(d, p.mw); time += drawDays(rng, d.duracion_dias); }
    for (;;) {
      const dec = drawPermitDecision(rng, d, info);
      if (dec === 'aprobado') break;
      if (dec === 'info_adicional') { info++; dev += d.info_adicional.costo_usd.base; time += drawDays(rng, d.info_adicional.retraso_dias); continue; }
      if (!d.reintentable || tries >= 1) { blocker = 'permiso'; break; }
      tries++; info = 0;
      dev += permitCostUsd(d, p.mw);
      time += drawDays(rng, d.duracion_dias);
    }
    permitDone.set(g, time);
    return time;
  };
  let permitsEnd = studiesEnd;
  for (const d of permits) permitsEnd = Math.max(permitsEnd, permitGroupFinish(d.grupo));
  if (blocker) return fail(blocker);

  // PPA
  let ppaPrice: number | undefined;
  let ppaEnd = 0;
  if (p.ppa?.status === 'firmado') ppaPrice = p.ppa.priceUsdMwh;
  else {
    const ch = (p.ppa?.status === 'en_proceso' ? c.ppa.canales.find((x) => x.id === p.ppa!.channelId) : undefined)
      ?? c.ppa.canales.find((x) => p.mw >= x.mw_min && p.mw <= x.mw_max);
    if (ch) {
      let start = 0;
      for (const g of ch.requiere_permisos) if (permitGroupApplicable(ctx, p, g)) start = Math.max(start, permitGroupFinish(g));
      let time = p.ppa?.status === 'en_proceso' ? Math.max(0, p.ppa.endTick - t0) : start + drawDays(rng, ch.duracion_dias);
      if (p.ppa?.status !== 'en_proceso') dev += ch.costo_usd.base;
      for (let k = 0; k < 2 && ppaPrice === undefined; k++) {
        if (rng.chance(ch.prob_exito)) ppaPrice = drawDist(rng, ch.precio_usd_mwh);
        else if (k === 0) { dev += ch.costo_usd.base; time += drawDays(rng, ch.duracion_dias); }
      }
      ppaEnd = time;
    }
  }

  // Financiamiento
  let finEnd = Math.max(permitsEnd, Math.min(ppaEnd, permitsEnd + 180));
  if (p.financing?.status !== 'cerrado') {
    const l = c.finanzas.prestamistas.find((x) => x.id === p.financing?.lenderId) ?? c.finanzas.prestamistas.find((x) => x.tipo === 'comercial')!;
    let ok = false;
    for (let k = 0; k < 2 && !ok; k++) {
      if (!(p.financing?.status === 'en_proceso' && k === 0)) dev += l.costo_asesores_usd.base;
      finEnd += p.financing?.status === 'en_proceso' && k === 0 ? Math.max(0, p.financing.endTick - t0) : drawDays(rng, l.diligencia_dias);
      ok = rng.chance(l.prob_aprobacion);
    }
    if (!ok) return fail('financiamiento');
  }

  // Construcción y puesta en marcha
  const eqId = p.suppliers?.equipmentId ?? Object.values(ctx.data.suppliers).find((s) => s.tipo === 'equipos' && s.tecnologias.includes(p.techId))?.id;
  const epcId = p.suppliers?.epcId ?? Object.values(ctx.data.suppliers).find((s) => s.tipo === 'epc' && s.tecnologias.includes(p.techId) && (s.factor_precio === 1))?.id
    ?? Object.values(ctx.data.suppliers).find((s) => s.tipo === 'epc')?.id;
  const eq = eqId ? ctx.data.suppliers[eqId] : undefined;
  const epc = epcId ? ctx.data.suppliers[epcId] : undefined;
  const budget = p.financing?.status === 'cerrado' ? p.financing.budgetUsd * (capexFactor / p.capexFactor)
    : capexBreakdown(ctx, { techId: p.techId, mw: p.mw, countryCode: p.countryCode, capexFactor, equipmentId: eqId, epcId }).totalUsd;
  const k = p.construction;
  const progress = k?.progress ?? 0;
  const planned = k ? k.plannedDays : drawDist(rng, tech.construccion_meses) * DAYS_PER_MONTH * (epc?.factor_plazo ?? 1);
  let consDays = (1 - progress) * planned;
  // lluvia en hitos sensibles (fracción de meses lluviosos)
  const rainyFrac = c.construccion.meses_lluviosos.length / 12;
  const sensFrac = tech.hitos_construccion.filter((m) => m.sensible_lluvia).reduce((a, m) => a + m.fraccion, 0);
  consDays += (1 - progress) * planned * sensFrac * rainyFrac * (1 / c.construccion.factor_avance_lluvia - 1);
  const months = consDays / DAYS_PER_MONTH;
  for (let m = 0; m < Math.ceil(months); m++) {
    if (rng.chance(c.construccion.huelga_prob_mensual)) consDays += drawDays(rng, c.construccion.huelga_duracion_dias);
    if (rng.chance(c.construccion.clima_extremo_prob_mensual * rainyFrac)) consDays += drawDays(rng, c.construccion.clima_extremo_dias);
  }
  // equipos
  if (!k?.equipmentArrived && eq) {
    const needAt = tech.hitos_construccion.find((m) => m.requiere_equipos);
    let lead = k ? Math.max(0, k.equipmentArrivalTick - t0) : (eq.plazo_entrega_dias ? drawDays(rng, eq.plazo_entrega_dias) : 90);
    if (!k && rng.chance(1 - eq.confiabilidad)) lead *= rng.triangular(1.1, 1.3, 1.8);
    if (needAt) {
      let acc = 0;
      for (const m of tech.hitos_construccion) { if (m.id === needAt.id) break; acc += m.fraccion; }
      const needDay = Math.max(0, acc - progress) * planned;
      consDays += Math.max(0, lead - needDay);
    }
  }
  let overrun = 0;
  for (const m of tech.hitos_construccion) {
    const done = k?.milestones.find((x) => x.id === m.id)?.done;
    if (done) continue;
    if (rng.chance(epc?.prob_sobrecosto_hito ?? 0.15)) overrun += rng.triangular(0.02, 0.06, 0.2) * m.fraccion * budget;
  }
  let comm = k?.commissioningStartTick !== undefined ? Math.max(0, k.commissioningStartTick + (k.commissioningDays ?? 0) - t0) : drawDays(rng, tech.puesta_en_marcha_dias);
  if (k?.commissioningStartTick === undefined && eq && epc && rng.chance((1 - eq.calidad) * 0.6 + (1 - epc.calidad) * 0.3)) comm += rng.triangular(15, 30, 75);
  const consStart = k ? 0 : finEnd;
  const codDays = (k?.commissioningStartTick !== undefined ? 0 : consStart + consDays) + comm;

  const spent = k?.spentUsd ?? 0;
  const capexTotal = budget + overrun + (k?.overrunUsd ?? 0);
  const remainingCapex = Math.max(0, capexTotal - spent);
  // Recurso: incertidumbre del jugador
  const resource = p.estimate.value * Math.max(0.3, 1 + p.estimate.sigma * rng.normal());
  const eco = projectEconomics(state, ctx, p, { resource, capexUsd: capexTotal, ppaPriceUsdMwh: ppaPrice, merchant: ppaPrice === undefined });
  const years = codDays / 365;
  const npv = eco.npvEquityUsd / Math.pow(1 + eco.costOfEquity, years) - dev;
  return { ok: true, days: codDays, cost: dev + remainingCapex, irr: eco.model.irrEquity, npv };
}
