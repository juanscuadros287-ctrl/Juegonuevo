import type { GameState } from '../core/state';
import type { SimContext } from '../core/context';
import type { Command } from '../core/commands';
import { Rng, hashString, seedStream } from '../core/rng';
import type { CompetitorDef, SupplierDef } from '../data/types';
import { balanceSheet } from '../finance/company';
import { applicablePermits, financingBlockers, openFindings, permitBlockers, requiredStudyGroups, studyBlockers, studyGroupDone } from '../project/requirements';
import { findingCostUsd, permitCostUsd, studyCostUsd } from '../project/outcomes';
import { isTerminal } from '../project/helpers';
import { projectCapex, projectEconomics } from '../project/economics';
import { currentCapex } from '../tech/costs';
import { siteKey } from '../world/site';
import { evaluateSite } from '../tech/siting';
import { sellsEnergy } from '../tech/models';
import { hasPresence, presenceBlockers } from '../business/presence';
import { researchBlockers, researchNodes, studyUnlocked, techUnlocked } from '../business/research';
import { bidBlockers, nameplateMw, quoteBid, realisticDeliveryMonths } from '../business/bids';
import { publicOpportunity } from '../business/opportunities';
import type { Opportunity } from '../business/types';
import type { Project } from '../project/types';
import { insurancePremium } from '../world/events';
import { actorIdOf } from '../business/actor';
import { decideTeam } from './team';
import { saleValuation } from '../project/valuation';

/**
 * Toma de decisiones de un competidor IA. Recibe SU vista de actor y devuelve comandos normales
 * (los mismos que la UI puede enviar), que luego pasan por las mismas validaciones.
 *
 * Información incompleta (prueba en ai.test.ts): solo lee
 *  - su propia empresa y sus proyectos a través de la ESTIMACIÓN del recurso (`p.estimate`), nunca `site.realFactor`
 *    ni `operation.fcReal`;
 *  - las oportunidades a través de `publicOpportunity` (sin precio de reserva privado ni ofertas ajenas);
 *  - datos públicos: YAML, celdas de la grilla, índices de precios, sitios ocupados por proyectos visibles.
 * Utilidad determinista por estrategia: márgenes, tasa de descuento, apetito de riesgo y preferencias del YAML.
 * Los sorteos (ofertar o no, tamaño de un proyecto) usan el flujo RNG propio del competidor.
 */

export interface AiContext {
  def: CompetitorDef;
  /** Proyectos activos de todos los actores (ubicación y tecnología: información pública de permisos). */
  occupiedSites: Set<string>;
}

type ProjCmd = Command;

function supplierPick(ctx: SimContext, techId: string, tipo: SupplierDef['tipo'], pref: CompetitorDef['proveedores']): string | undefined {
  const list = Object.values(ctx.data.suppliers).filter((s) => s.tipo === tipo && s.tecnologias.includes(techId));
  if (!list.length) return undefined;
  const score = (s: SupplierDef) => pref === 'baratos' ? s.factor_precio - 0.2 * s.calidad : pref === 'calidad' ? -s.calidad - 0.5 * s.confiabilidad : Math.abs(s.factor_precio - 1) - 0.05 * s.calidad;
  return [...list].sort((a, b) => score(a) - score(b) || a.id.localeCompare(b.id))[0].id;
}

function freeCash(view: GameState, def: CompetitorDef): number {
  return view.company.cashUsd - def.reserva_meses * def.gastos_fijos_mensuales_usd;
}

/** Aporte propio pendiente de las obras en curso (lo que la empresa aún debe poner). */
function committedEquity(view: GameState): number {
  let s = 0;
  for (const p of view.projects) {
    if (!p.construction || p.operation || isTerminal(p)) continue;
    const f = p.financing!;
    const left = Math.max(0, f.budgetUsd - p.construction.spentUsd);
    const debtShare = f.budgetUsd > 0 ? f.debtUsd / f.budgetUsd : 0;
    s += left * (1 - debtShare) * (1 - f.partnerShare);
  }
  return s;
}

function ownEquityNeed(p: Project): number {
  const f = p.financing!;
  return (f.budgetUsd - f.debtUsd) * (1 - f.partnerShare) * 1.08; // + margen para sobrecostos
}

function projectSteps(view: GameState, ctx: SimContext, p: Project, ai: AiContext, budget: { cash: number }): ProjCmd[] {
  const def = ai.def;
  const id = p.id;
  const out: ProjCmd[] = [];
  const spend = (amount: number) => { if (budget.cash < amount) return false; budget.cash -= amount; return true; };
  if (p.sale?.status === 'en_proceso' || p.operation) return out;
  if (p.findings.some((f) => f.status === 'fatal')) return [{ type: 'abandonProject', projectId: id }];
  for (const f of p.findings) {
    if (f.status !== 'abierto') continue;
    const d = ctx.data.findings[f.id];
    if (!d.mitigable || f.attempts >= 2) return [{ type: p.devCostUsd > 150_000 ? 'sellProject' : 'abandonProject', projectId: id }];
    if (spend(findingCostUsd(d, p.mw))) out.push({ type: 'mitigateFinding', projectId: id, findingId: f.id });
  }
  if (openFindings(p).length) return out;
  if (p.construction) return out;

  // Estudios: uno por grupo requerido. Los cautos pagan la medición bancable; los baratos, la más barata.
  for (const g of requiredStudyGroups(ctx, p)) {
    if (studyGroupDone(ctx, p, g) || Object.values(p.studies).some((r) => r.status === 'en_curso' && ctx.data.studies[r.studyId]?.grupo === g)) continue;
    const opts = Object.values(ctx.data.studies).filter((s) => s.grupo === g && studyBlockers(ctx, p, s.id).length === 0 && studyUnlocked(view, ctx, s.id));
    if (!opts.length) continue;
    opts.sort((a, b) => def.proveedores === 'baratos' && !p.contractId ? studyCostUsd(a, p.mw) - studyCostUsd(b, p.mw) : (a.sigma_recurso ?? 1) - (b.sigma_recurso ?? 1) || studyCostUsd(a, p.mw) - studyCostUsd(b, p.mw));
    if (spend(studyCostUsd(opts[0], p.mw))) out.push({ type: 'commissionStudy', projectId: id, studyId: opts[0].id });
  }
  for (const d of applicablePermits(ctx, p)) {
    const r = p.permits[d.id];
    if (r && r.status !== 'rechazado') continue;
    if (permitBlockers(ctx, p, d.id).length) continue;
    if (r?.status === 'rechazado' && r.applications >= 2) return [{ type: 'abandonProject', projectId: id }];
    if (spend(permitCostUsd(d, p.mw))) out.push({ type: 'applyPermit', projectId: id, permitId: d.id });
  }
  const blockers = financingBlockers(ctx, p);
  // Tras medir el recurso: ¿sigue valiendo la pena? (con la estimación, nunca con el recurso real)
  const measured = p.estimate.source !== 'celda';
  if (measured && !p.contractId && !p.ppa && blockers.length > 0) {
    const eco = projectEconomics(view, ctx, p);
    if ((eco.model.irrEquity ?? -1) < def.tasa_descuento - 0.04) return [{ type: p.devCostUsd > 100_000 ? 'sellProject' : 'abandonProject', projectId: id }];
  }
  // PPA del canal genérico de la Fase 2 si no hay contrato de licitación (los agresivos prueban el spot)
  if (!p.contractId && (!p.ppa || (p.ppa.status === 'fallido' && def.estrategia !== 'agresiva' && p.ppa.startTick > 0 && view.tick - p.ppa.endTick > 200))) {
    const c = ctx.data.countries[p.countryCode];
    // Fase 6 (balance): entre los canales posibles elige el de mayor probabilidad de cierre (antes: el primero de la lista).
    const ch = !sellsEnergy(ctx.data.technologies[p.techId]) ? undefined : [...c.ppa.canales].sort((a, b) => b.prob_exito - a.prob_exito || a.id.localeCompare(b.id)).find((x) => (!x.tecnologias || x.tecnologias.includes(p.techId)) && p.mw >= x.mw_min && p.mw <= x.mw_max && x.requiere_permisos.every((g) => !applicablePermits(ctx, p).some((d) => d.grupo === g) || Object.values(p.permits).some((r) => r.status === 'aprobado' && c.permisos.find((y) => y.id === r.permitId)?.grupo === g)));
    if (ch && (def.estrategia !== 'agresiva' || !p.ppa) && spend(ch.costo_usd.base)) out.push({ type: 'seekPpa', projectId: id, channelId: ch.id });
  }
  if (blockers.length) return out;
  // Fase 6 (balance): vende el proyecto listo para construir solo si el comprador paga al menos 1,1 × lo invertido
  // (en la práctica, con PPA firmado: un proyecto merchant vale poco para un comprador); si no, sigue buscando PPA y,
  // tras 5 años, lo vende igual.
  if (def.vende === 'listo_para_construir' && !p.contractId && !p.financing) {
    if (saleValuation(view, ctx, p).valueUsd >= 1.1 * p.devCostUsd || view.tick - p.createdTick > 365 * 5) return [...out, { type: 'sellProject', projectId: id }];
    if (p.ppa?.status !== 'firmado') return out;
  }
  if (p.ppa?.status === 'en_proceso') return out;
  if (!p.suppliers) {
    const eq = supplierPick(ctx, p.techId, 'equipos', def.proveedores), epc = supplierPick(ctx, p.techId, 'epc', def.proveedores);
    if (eq && epc) out.push({ type: 'selectSuppliers', projectId: id, equipmentId: eq, epcId: epc });
    return out;
  }
  if (!p.financing || p.financing.status === 'fallido') {
    const capex = projectCapex(ctx, p, view).totalUsd;
    const c = ctx.data.countries[p.countryCode];
    // Si la caja no alcanza, busca más socio de capital (hasta el máximo del país) antes de rendirse.
    const factor = def.estrategia === 'agresiva' ? 0.6 : 1.1;
    const ownNeed = (share: number) => capex * (1 - def.apalancamiento) * (1 - share) * factor + 60_000;
    let partner = def.socio;
    while (budget.cash < ownNeed(partner) && partner + 0.1 <= c.finanzas.socio_equity.participacion_max + 1e-9) partner = Math.round((partner + 0.1) * 10) / 10;
    if (budget.cash < ownNeed(partner)) {
      if (view.tick - p.createdTick > 365 * 5) out.push({ type: 'sellProject', projectId: id });
      return out;
    }
    const dev = c.finanzas.prestamistas.find((l) => l.tipo === 'desarrollo');
    const useDev = dev && p.ppa?.status === 'firmado' && p.estimate.sigma <= dev.sigma_recurso_max && capex * def.apalancamiento >= dev.monto_min_usd && def.estrategia !== 'agresiva';
    const lender = useDev ? dev! : c.finanzas.prestamistas.find((l) => l.tipo === 'comercial')!;
    const debt = Math.min(def.apalancamiento, lender.apalancamiento_max);
    if (spend(lender.costo_asesores_usd.base)) out.push({ type: 'arrangeFinancing', projectId: id, lenderId: lender.id, debtFraction: debt, partnerShare: partner });
    return out;
  }
  if (p.financing.status === 'cerrado') {
    const need = ownEquityNeed(p) * (def.estrategia === 'agresiva' ? 0.85 : 1.1);
    if (budget.cash >= need) { budget.cash -= need; out.push({ type: 'startConstruction', projectId: id }); }
    else if (view.tick - p.financing.endTick > 270 && !p.contractId) out.push({ type: 'sellProject', projectId: id });
  }
  return out;
}

function projectCapexPerMw(view: GameState, ctx: SimContext, techId: string, country: string): number {
  return currentCapex(view, ctx, { techId, mw: 10, countryCode: country }).totalUsd / 10;
}

function techFor(view: GameState, ctx: SimContext, def: CompetitorDef, allowed: string[]): string | undefined {
  return def.tecnologias.find((t) => allowed.includes(t) && ctx.data.technologies[t] && techUnlocked(view, ctx, t));
}

/** Elige un sitio candidato libre para una tecnología (el de mejor recurso público de la celda). */
function pickSite(view: GameState, ctx: SimContext, ai: AiContext, techId: string, country: string) {
  if (!ctx.grid) return undefined;
  const tech = ctx.data.technologies[techId];
  const sites = (ctx.data.competitors?.sitios_candidatos ?? []).filter((s) => s.tecnologia === techId && s.pais === country);
  let best: { lat: number; lon: number; v: number } | undefined;
  const idx = Number((view.actorId ?? 'C0').replace(/\D/g, '')) || 0;
  for (const s of sites) {
    // Cada empresa negocia terrenos un poco distintos alrededor del sitio (≈2–4 km).
    for (const k of [0, 1, 2]) {
      const lat = s.lat + 0.02 * ((idx + k) % 3 - 1), lon = s.lon + 0.03 * k;
      if (ai.occupiedSites.has(siteKey(lat, lon))) continue;
      // Fase 4: mismas restricciones de sitio que el jugador (mar, costa, recurso mínimo, zona, agua…).
      const ev = evaluateSite(ctx, techId, lat, lon);
      if (!ev.ok || ev.countryCode !== country) continue;
      const v = tech.recurso ? ev.value : 1;
      if (!best || v > best.v) best = { lat, lon, v };
      break;
    }
  }
  return best;
}

/** Comandos del competidor para este turno de decisión. */
export function decideCompetitor(view: GameState, ctx: SimContext, ai: AiContext): Command[] {
  const def = ai.def;
  const me = actorIdOf(view);
  const cmds: Command[] = [];
  // Sorteos de decisión deterministas por (partida, competidor, día): decidir no consume flujos del estado.
  const rng = new Rng(seedStream((view.seed ^ hashString(`${me}@${view.tick}`)) >>> 0, 'ai'));
  const budget = { cash: freeCash(view, def) - committedEquity(view) };
  const crisis = view.company.cashUsd < def.reserva_meses * def.gastos_fijos_mensuales_usd;

  // I+D
  const r = view.business.research;
  const wantBudget = crisis ? 0 : def.investigacion.presupuesto_mensual_usd;
  if (ctx.data.research && r.budgetUsdMonth !== wantBudget) cmds.push({ type: 'setResearchBudget', usdPerMonth: wantBudget });
  if (ctx.data.research && wantBudget > 0 && !r.active && r.queue.length === 0) {
    const nodes = researchNodes(ctx);
    const next = def.investigacion.prioridades.find((n) => nodes[n] && researchBlockers(view, ctx, n).length === 0);
    if (next) cmds.push({ type: 'startResearch', nodeId: next });
  }

  // Fase 6: equipo y oficinas (mismos comandos que el jugador).
  cmds.push(...decideTeam(view, ctx, def, rng, budget, crisis));

  // Proyectos
  const active = view.projects.filter((p) => !isTerminal(p));
  for (const p of active) cmds.push(...projectSteps(view, ctx, p, ai, budget));
  // Fase 5: las prudentes aseguran sus plantas contra catástrofes donde el riesgo es apreciable (mismo comando que el jugador).
  if (ctx.data.world && (def.estrategia === 'conservadora' || def.estrategia === 'estatal' || def.estrategia === 'fondo')) {
    for (const p of active) {
      if (!p.operation || p.insurance) continue;
      const pr = insurancePremium(ctx, p, 'danos');
      if (pr.expectedLossFrac < 0.002 || budget.cash < pr.premiumUsdYear) continue;
      budget.cash -= pr.premiumUsdYear / 12;
      cmds.push({ type: 'buyInsurance', projectId: p.id, coverage: 'danos' });
    }
  }
  if (crisis && def.vende !== 'nunca') {
    const dev = active.find((p) => !p.construction && !p.operation && p.sale?.status !== 'en_proceso' && p.devCostUsd > 50_000);
    if (dev) cmds.push({ type: 'sellProject', projectId: dev.id });
  }

  // Contratos ganados «con proyecto nuevo»: vincular uno existente o crear uno.
  let created = 0;
  const predictId = () => `${me}-P${view.nextProjectId + created}`;
  for (const k of view.business.contracts) {
    if (k.status !== 'sin_proyecto' || k.kind === 'epc') continue;
    const need = k.kind === 'potencia' ? nameplateMw(ctx, { contract: 'potencia', mw: k.mw }, k.techId) : k.mw;
    const fit = active.find((p) => p.techId === k.techId && p.countryCode === k.countryCode && !p.contractId && (!p.ppa || p.ppa.status === 'fallido') && !p.construction && !p.operation && p.mw >= 0.9 * need && p.mw <= 1.5 * need);
    if (fit) { cmds.push({ type: 'assignContractProject', contractId: k.id, projectId: fit.id }); continue; }
    const site = pickSite(view, ctx, ai, k.techId, k.countryCode);
    const tech = ctx.data.technologies[k.techId];
    if (!site || !tech) continue;
    const mw = Math.min(tech.escala_mw.max, Math.ceil(need));
    cmds.push({ type: 'createProject', techId: k.techId, mw, lat: site.lat, lon: site.lon, name: `${def.nombre.split(' ')[0]} ${tech.nombre} ${mw} MW` });
    cmds.push({ type: 'assignContractProject', contractId: k.id, projectId: predictId() });
    ai.occupiedSites.add(siteKey(site.lat, site.lon));
    created++;
  }

  // Fase 4: expansión a otros países (mismo comando que el jugador: I+D del mercado + sociedad local).
  if (!crisis && def.expansion && view.company.cashUsd > def.expansion.caja_min_usd && created === 0) {
    const pending = Object.values(view.business.presence ?? {}).some((x) => x.status === 'en_tramite');
    const target = pending ? undefined : def.expansion.paises.find((iso) => !hasPresence(view, iso) && presenceBlockers(view, ctx, iso).length === 0);
    if (target) cmds.push({ type: 'openPresence', countryCode: target });
  }

  // Proyecto especulativo nuevo (en el país de origen o en uno donde ya tiene presencia)
  const devCount = active.filter((p) => !p.construction && !p.operation).length;
  if (!crisis && devCount < def.max_proyectos && budget.cash > 600_000 && created === 0 && rng.chance(0.25)) {
    const markets = [view.company.homeCountry, ...Object.keys(view.business.presence ?? {}).filter((iso) => hasPresence(view, iso)).sort()];
    const country = markets.length > 1 ? markets[Math.floor(rng.next() * markets.length)] : markets[0];
    const techId = techFor(view, ctx, def, def.tecnologias.filter((t) => (ctx.data.competitors?.sitios_candidatos ?? []).some((s) => s.tecnologia === t && s.pais === country)));
    const site = techId ? pickSite(view, ctx, ai, techId, country) : undefined;
    if (techId && site) {
      const tech = ctx.data.technologies[techId];
      // Tamaño que su caja puede sostener (con el máximo de socio y la deuda que suele pedir).
      const perMw = projectCapexPerMw(view, ctx, techId, country) * (1 - def.apalancamiento) * 0.35;
      const lo = Math.max(def.mw.min, tech.escala_mw.min), hi = Math.max(lo, Math.min(def.mw.max, tech.escala_mw.max, Math.floor(budget.cash / perMw)));
      const mw = Math.round(lo + (hi - lo) * rng.next());
      cmds.push({ type: 'createProject', techId, mw, lat: site.lat, lon: site.lon, name: `${def.nombre.split(' ')[0]} ${tech.nombre} ${mw} MW` });
      ai.occupiedSites.add(siteKey(site.lat, site.lon));
      budget.cash -= 300_000;
    }
  }

  // Ofertas
  if (!crisis && ctx.data.clients) {
    for (const real of view.market.opportunities) {
      if (real.status !== 'abierta') continue;
      const pub = publicOpportunity(real, me);
      if (pub.myBid) continue;
      if (pub.contract === 'epc' && !def.ofertar_epc) continue;
      // Vista saneada: sin precio de reserva privado y sin ofertas ajenas.
      const opp: Opportunity = { ...pub, reservePrice: pub.ceilingPrice ?? Infinity, bids: [] };
      const techId = techFor(view, ctx, def, opp.techs);
      if (!techId) continue;
      const need = nameplateMw(ctx, opp, techId);
      const link = opp.contract === 'epc' ? undefined : active
        .filter((p) => p.techId === techId && p.countryCode === opp.countryCode && !p.contractId && (!p.ppa || p.ppa.status === 'fallido') && !p.operation && p.sale?.status !== 'en_proceso' && p.mw >= 0.9 * need && p.mw <= 1.5 * need)
        .sort((a, b) => b.devCostUsd - a.devCostUsd)[0];
      if (!rng.chance(def.prob_ofertar)) continue;
      const q = quoteBid(view, ctx, opp, { techId, projectId: link?.id, marginPct: def.margen_objetivo, discountRate: opp.contract === 'epc' ? undefined : def.tasa_descuento,
        equipmentId: supplierPick(ctx, techId, 'equipos', def.proveedores), epcId: supplierPick(ctx, techId, 'epc', def.proveedores) });
      if (!q.ok) continue;
      let price = q.suggestedPrice;
      const cap = opp.ceilingPrice ?? opp.referencePrice * 1.08; // sin tope publicado, adivina con la referencia pública
      if (price > cap) {
        if (q.breakEvenPrice * 1.02 > cap) continue;
        price = cap * 0.995;
      }
      const realistic = realisticDeliveryMonths(view, ctx, opp, techId, link?.id);
      const slack = def.estrategia === 'agresiva' ? 0.95 : def.estrategia === 'conservadora' ? 1.15 : 1.05;
      const delivery = Math.min(opp.codMonths, Math.ceil(realistic * slack));
      // No promete lo que no puede cumplir: el agresivo arriesga hasta la mitad del atraso tolerado.
      if (realistic > opp.codMonths + (def.estrategia === 'agresiva' ? 0.5 * opp.maxDelayMonths : 0)) continue;
      const effort = def.estrategia === 'conservadora' || def.estrategia === 'estatal' ? 'reforzada' as const : 'estandar' as const;
      const bond = opp.bidBondUsd + opp.prepCostUsd * (effort === 'reforzada' ? 2.5 : 1);
      if (budget.cash < bond + opp.performanceBondUsd || view.business.restrictedCashUsd + opp.performanceBondUsd > 0.5 * Math.max(0, balanceSheet(view).equityUsd)) continue;
      const cmd: Command = { type: 'submitBid', opportunityId: opp.id, techId, price, deliveryMonths: Math.max(3, delivery), projectId: link?.id, effort,
        equipmentId: opp.contract === 'epc' ? supplierPick(ctx, techId, 'equipos', def.proveedores) : undefined,
        epcId: opp.contract === 'epc' ? supplierPick(ctx, techId, 'epc', def.proveedores) : undefined };
      if (bidBlockers(view, ctx, opp, cmd as Extract<Command, { type: 'submitBid' }>).length) continue;
      budget.cash -= bond;
      cmds.push(cmd);
    }
  }
  return cmds;
}
