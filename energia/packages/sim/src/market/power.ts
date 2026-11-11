import type { GameState } from '../core/state';
import type { SimContext } from '../core/context';
import type { SimEvent } from '../core/events';
import { Rng, seedStream } from '../core/rng';
import { fromEpochDay } from '../core/calendar';
import type { CountrySimDef, PowerClassDef, PowerCountryDef, PowerDef, SimData, TechnologyDef } from '../data/types';
import { normalizedProfile, spotPrice } from './spot';
import { fuelEmissionsKgMmbtu, fxReal, usdInflation } from './macro';
import { worldCarbonAddUsdT, worldDemandFactor, worldFuelFactor, worldHydrologyFactor } from '../world/events';
import { TERMINAL_STAGES, type Project } from '../project/types';

/**
 * Fase 5: mercado eléctrico por país.
 *
 * Por país y mes se calcula el precio spot de 2 días tipo (laborable, fin de semana) × 24 horas:
 *  1. demanda horaria = media anual × crecimiento × perfil mensual × forma horaria × eventos del mundo × El Niño;
 *  2. oferta: renovables variables (solar y eólica con perfiles horarios y estacionales), base (geotermia, nuclear),
 *     hidro de pasada (según la hidrología del año) y embalse (energía diaria limitada que recorta la punta de la demanda
 *     residual), térmicas en orden de mérito (costo marginal = heat rate × combustible + carbono + O&M variable);
 *  3. precio = costo marginal de la unidad marginal; si sobra renovable ⇒ vertimiento y precio piso; si la hidro alcanza ⇒
 *     valor del agua; si falta térmica ⇒ escasez (rampa hasta el precio techo);
 *  4. segunda pasada con el almacenamiento de los actores (carga en horas baratas, descarga en caras).
 * El parque existente se deriva de la matriz del país y crece con la demanda; las plantas de los actores (jugador e IA)
 * se suman encima, así que más oferta ⇒ precio más bajo (canibalización solar al mediodía).
 * Los costos marginales térmicos se calibran con un factor por país para que el año base sin actores dé el spot medio
 * histórico del YAML. Todo es determinista: el clima del año sale del flujo RNG `market`.
 */

export const DAY_TYPES = ['laborable', 'finde'] as const;
/** Peso de cada tipo de día (5 laborables y 2 de fin de semana). */
export const DAY_WEIGHTS = [5 / 7, 2 / 7];

export interface FleetSnapshot {
  /** MW por clase de las plantas de los actores en operación. */
  mw: Record<string, number>;
  /** Térmicas de los actores (con su propio heat rate). */
  thermal: { techId: string; mw: number }[];
  /** Almacenamiento de los actores (MW, horas, eficiencia) y MW ofrecidos en servicios complementarios. */
  storage: { mw: number; hours: number; eff: number };
  servicesMw: number;
  /** Plantas de los actores en obra (para las previsiones): clase o tecnología, MW y mes esperado de operación. */
  construction: { cls?: string; techId: string; mw: number; codYm: number }[];
}

export interface MonthPrices {
  year: number;
  month: number;
  /** USD/MWh por [tipo de día][hora]. */
  prices: number[][];
  /** MW por [tipo de día][hora]. */
  demand: number[][];
  /** Fracción de la renovable variable vertida por congestión o exceso [tipo de día][hora]. */
  curtail: number[][];
  avg: number;
  peak: number;
  offpeak: number;
  min: number;
  max: number;
  /** Para la curva de oferta y el clima. */
  hydrology: number;
  thermalMc: { cls: string; mw: number; mc: number }[];
  waterValue: number;
}

export interface PowerHistoryEntry { year: number; month: number; avg: number; peak: number; offpeak: number; min: number; max: number; hydrology: number }

export interface PowerState {
  /** Sube cada vez que cambia algo que afecta las previsiones (nuevo mes, nuevo parque). */
  version: number;
  /** Mes calculado (año·12 + mes − 1). */
  ym: number;
  enso: 'nino' | 'nina' | 'neutral';
  ensoYear: number;
  /** Hidrología del año por país (1 = normal). */
  hydrology: Record<string, number>;
  fleet: Record<string, FleetSnapshot>;
  current: Record<string, MonthPrices>;
  history: Record<string, PowerHistoryEntry[]>;
}

const ym = (year: number, month: number) => year * 12 + month - 1;
const fromYm = (v: number) => ({ year: Math.floor(v / 12), month: (v % 12) + 1 });

export function powerDef(ctx: SimContext): PowerDef | undefined {
  return ctx.data.power;
}
export function powerCountry(ctx: SimContext, iso: string): PowerCountryDef | undefined {
  return ctx.data.power?.paises[iso];
}

// ───────────────────────── Parque existente y calibración (puros, por datos) ─────────────────────────

const baseFleetCache = new WeakMap<SimData, Map<string, Record<string, number>>>();
const calibCache = new WeakMap<SimData, Map<string, number>>();

function mixFor(pc: PowerCountryDef, key: string): Record<string, number> {
  if (key === 'termica') return pc.mezcla_termica ?? { fueloil: 0.5, gas: 0.5 };
  if (key === 'otros') return pc.mezcla_otros ?? { biomasa: 0.5, fueloil: 0.5 };
  return { [key]: 1 };
}

/** MW instalados por clase del parque existente al inicio (derivados de la matriz y la demanda). */
export function baseFleet(ctx: SimContext, iso: string): Record<string, number> {
  let m = baseFleetCache.get(ctx.data);
  if (!m) { m = new Map(); baseFleetCache.set(ctx.data, m); }
  const hit = m.get(iso);
  if (hit) return hit;
  const P = ctx.data.power!, pc = P.paises[iso], c = ctx.data.countries[iso];
  const out: Record<string, number> = {};
  const demandMwh = (c.mercado.demanda_anual_twh?.base ?? 10) * 1e6;
  for (const [key, share] of Object.entries(c.mercado.matriz ?? {})) {
    if (typeof share !== 'number' || share <= 0) continue;
    const mix = mixFor(pc, key);
    const tot = Object.values(mix).reduce((a, b) => a + b, 0) || 1;
    for (const [cls, w] of Object.entries(mix)) {
      const def = P.clases[cls];
      if (!def) continue;
      out[cls] = (out[cls] ?? 0) + share * (w / tot) * demandMwh / (8760 * def.fc);
    }
  }
  for (const [cls, mw] of Object.entries(pc.parque_mw ?? {})) out[cls] = mw;
  // Margen de reserva: si la potencia firme no cubre la punta × margen, hay turbinas de punta.
  const peak = c.mercado.pico_mw?.base ?? demandMwh / 8760 * 1.5;
  let firm = 0;
  for (const [cls, mw] of Object.entries(out)) firm += mw * (P.clases[cls]?.credito_firme ?? 0);
  const need = peak * pc.margen_reserva - firm;
  if (need > 0 && P.clases.punta) out.punta = (out.punta ?? 0) + need / P.clases.punta.credito_firme;
  m.set(iso, out);
  return out;
}

/** Clase del mercado a la que pertenece una tecnología del juego (undefined: almacenamiento, H2, líneas, ESCO). */
export function techClass(ctx: SimContext, techId: string): string | undefined {
  const P = ctx.data.power;
  if (!P) return undefined;
  for (const [id, k] of Object.entries(P.clases)) if (k.tecnologias.includes(techId)) return id;
  return undefined;
}

export interface MarketInputs {
  year: number;
  month: number;
  yearsFromStart: number;
  hydrology: number;
  demandFactor: number;
  /** USD/MMBtu del combustible (tipo de la clase) con índice y eventos. */
  fuelPrice: (fuelType: string) => number;
  carbonUsdT: number;
  fleet?: FleetSnapshot;
  /** Plantas en obra que ya estarían operando (previsiones). */
  extraMw?: Record<string, number>;
  extraThermal?: { techId: string; mw: number }[];
  /** Multiplicador final (inflación del USD × tipo de cambio real). */
  priceMult: number;
}

interface Block { cls: string; mw: number; mc: number }

/** Dispersión de eficiencias dentro de una clase térmica (fracción de la potencia, multiplicador del heat rate). */
const HR_BLOCKS: [number, number][] = [[0.2, 0.85], [0.25, 0.95], [0.25, 1.05], [0.2, 1.2], [0.1, 1.4]];

/** Reparte la energía de embalse recortando la punta de la demanda residual (nivel L por bisección). */
function peakShave(res: number[], energy: number, cap: number): number[] {
  const pos = res.map((r) => Math.max(0, r));
  const total = pos.reduce((a, b) => a + Math.min(cap, b), 0);
  if (total <= energy) return pos.map((p) => Math.min(cap, p));
  let lo = 0, hi = Math.max(...pos);
  for (let i = 0; i < 40; i++) {
    const L = (lo + hi) / 2;
    const e = pos.reduce((a, p) => a + Math.min(cap, Math.max(0, p - L)), 0);
    if (e > energy) lo = L; else hi = L;
  }
  return pos.map((p) => Math.min(cap, Math.max(0, p - hi)));
}

function shape24(v: number[]): number[] {
  const mean = v.reduce((a, b) => a + b, 0) / 24 || 1;
  return v.map((x) => Math.max(0, x) / mean);
}

/**
 * Precios del mes para un país (puro). `k` = factor de calibración de los costos marginales térmicos del parque existente.
 */
export function computeMonthPrices(ctx: SimContext, iso: string, inp: MarketInputs, k: number): MonthPrices {
  const P = ctx.data.power!, pc = P.paises[iso], c = ctx.data.countries[iso];
  const base = baseFleet(ctx, iso);
  const scale = Math.pow(1 + pc.crecimiento_demanda, Math.max(0, inp.yearsFromStart));
  const mi = inp.month - 1;
  const monthDem = normalizedProfile(pc.perfil_demanda_mensual)[mi];
  const forms = P.formas_demanda[pc.forma_demanda];
  // Normaliza las formas para que el día promedio de la semana valga 1.
  const wMean = (DAY_WEIGHTS[0] * forms.laborable.reduce((a, b) => a + b, 0) + DAY_WEIGHTS[1] * forms.finde.reduce((a, b) => a + b, 0)) / 24;
  const dshape = [forms.laborable.map((x) => x / wMean), forms.finde.map((x) => x / wMean)];
  const davg = (c.mercado.demanda_anual_twh?.base ?? 10) * 1e6 / 8760 * scale * monthDem * inp.demandFactor;
  const fleet = inp.fleet;
  const mw = (cls: string) => (base[cls] ?? 0) * scale + (fleet?.mw[cls] ?? 0) + (inp.extraMw?.[cls] ?? 0);
  const cl = P.clases;
  const solarShape = shape24(P.formas_recurso.solar), windShape = shape24(P.formas_recurso.eolica);
  const ghiM = normalizedProfile(c.perfil_recurso_mensual.ghi)[mi];
  const windM = normalizedProfile(c.perfil_recurso_mensual.viento_tierra ?? c.perfil_recurso_mensual.viento_mar)[mi];
  const hydroM = normalizedProfile(c.perfil_recurso_mensual.hidro)[mi];
  const hf = hydroM * inp.hydrology;
  const solarMw = mw('solar'), windMw = mw('eolica'), hydroMw = mw('hidro');
  let baseOut = 0;
  for (const [id, d] of Object.entries(cl)) if (d.tipo === 'base') baseOut += mw(id) * d.disponibilidad;
  const hc = cl.hidro;
  const ror = hydroMw * (1 - pc.hidro_embalse_frac), resv = hydroMw * pc.hidro_embalse_frac;
  const rorOut = Math.min(ror * (hc?.disponibilidad ?? 0.92), ror * (hc?.fc ?? 0.5) * hf);
  // Los embalses regulan parte de la estacionalidad (guardan agua de la estación húmeda para la seca): más embalse, más
  // regulación. El 40 % de su energía diaria sale plana (caudal ecológico, cascadas); el resto recorta la punta.
  const resEnergyDay = resv * (hc?.fc ?? 0.5) * inp.hydrology * (1 + (hydroM - 1) * (1 - pc.hidro_embalse_frac)) * 24;
  const resFlat = 0.4 * resEnergyDay / 24;
  const resEnergy = 0.6 * resEnergyDay;
  const resCap = resv * (hc?.disponibilidad ?? 0.92);

  // Bloques térmicos (orden de mérito)
  const blocks: Block[] = [];
  const classMc = (d: PowerClassDef, hrMult: number) => {
    if (!d.combustible || !d.heat_rate_btu_kwh) return d.om_variable_usd_mwh;
    const mmbtu = d.heat_rate_btu_kwh * hrMult / 1000;
    const co2 = mmbtu * fuelEmissionsKgMmbtu(ctx, c, d.combustible) / 1000;
    return mmbtu * inp.fuelPrice(d.combustible) + co2 * inp.carbonUsdT + d.om_variable_usd_mwh;
  };
  for (const [id, d] of Object.entries(cl)) {
    if (d.tipo !== 'termica') continue;
    const total = (base[id] ?? 0) * scale * d.disponibilidad;
    if (total > 0) for (const [f, hm] of HR_BLOCKS) blocks.push({ cls: id, mw: total * f, mc: classMc(d, hm) * k });
    const own = ((fleet?.mw[id] ?? 0) + (inp.extraMw?.[id] ?? 0));
    void own; // las térmicas de los actores van con su propio heat rate (abajo)
  }
  for (const t of [...(fleet?.thermal ?? []), ...(inp.extraThermal ?? [])]) {
    const tech = ctx.data.technologies[t.techId];
    if (!tech?.combustible) continue;
    const mmbtu = tech.combustible.heat_rate_btu_kwh.base / 1000;
    const co2 = mmbtu * fuelEmissionsKgMmbtu(ctx, c, tech.combustible.tipo) / 1000;
    blocks.push({ cls: tech.id, mw: t.mw * 0.9, mc: mmbtu * inp.fuelPrice(tech.combustible.tipo) + co2 * inp.carbonUsdT + tech.om_variable_usd_mwh.base });
  }
  blocks.sort((a, b) => a.mc - b.mc || a.cls.localeCompare(b.cls));
  const thermalAvail = blocks.reduce((a, b) => a + b.mw, 0);
  // Valor del agua: referido al costo medio de la térmica que la hidro desplaza (sin las turbinas de punta).
  const core = blocks.filter((b) => b.cls !== 'punta');
  const refSet = core.length ? core : blocks;
  const refMw = refSet.reduce((a, b) => a + b.mw, 0);
  const refMc = refMw > 0 ? refSet.reduce((a, b) => a + b.mw * b.mc, 0) / refMw : 100 * k;
  const wv = P.valor_agua;
  const waterValue = refMc * Math.max(wv.min, Math.min(wv.max, wv.base * Math.pow(Math.max(0.05, hf), -wv.exponente)));
  const cap = pc.precio_techo_usd_mwh, floor = pc.precio_piso_usd_mwh;
  const vreLimit = pc.red ? pc.red.limite_vre_frac * davg : Infinity;

  const st = fleet?.storage;
  const solve = (extraLoad?: number[][]) => {
    const prices: number[][] = [], demand: number[][] = [], curtail: number[][] = [];
    for (let d = 0; d < 2; d++) {
      const D = dshape[d].map((s, h) => davg * s + (extraLoad?.[d][h] ?? 0));
      const vre = solarShape.map((s, h) => solarMw * (cl.solar?.fc ?? 0.21) * s * ghiM * (cl.solar?.disponibilidad ?? 1) + windMw * (cl.eolica?.fc ?? 0.33) * windShape[h] * windM * (cl.eolica?.disponibilidad ?? 1));
      const cur = vre.map((v) => (v > vreLimit ? (v - vreLimit) / v : 0));
      const R = D.map((x, h) => x - vre[h] * (1 - cur[h]) - baseOut - rorOut - resFlat);
      const H = peakShave(R, resEnergy, Math.max(0, resCap - resFlat));
      const pr: number[] = [];
      for (let h = 0; h < 24; h++) {
        if (R[h] < 0) {
          // Sobra renovable: se vierte y el precio cae al piso.
          const v = vre[h] * (1 - cur[h]);
          cur[h] = v > 0 ? Math.min(1, cur[h] + (-R[h]) / vre[h]) : cur[h];
          pr.push(floor);
          continue;
        }
        const T = R[h] - H[h];
        if (T <= 1e-6) { pr.push(waterValue); continue; }
        if (T >= thermalAvail) { pr.push(cap); continue; }
        let acc = 0, mc = blocks[blocks.length - 1]?.mc ?? cap;
        for (const b of blocks) { acc += b.mw; if (acc >= T) { mc = b.mc; break; } }
        const u = T / thermalAvail, th = P.escasez.umbral;
        if (u > th) mc = mc + (cap - mc) * Math.pow((u - th) / (1 - th), 2);
        pr.push(Math.min(cap, Math.max(mc, waterValue * 0.5)));
      }
      prices.push(pr); demand.push(D); curtail.push(cur);
    }
    return { prices, demand, curtail };
  };
  let r = solve();
  if (st && st.mw > 0) {
    // Segunda pasada: el almacenamiento de los actores aplana la curva (carga barata, descarga cara).
    const load: number[][] = [];
    for (let d = 0; d < 2; d++) {
      const plan = storageDay(r.prices[d], { hours: st.hours, eff: st.eff, cyclesCap: 1, minSpread: 1 });
      load.push(plan.charge.map((c2, h) => st.mw * (c2 - plan.discharge[h])));
    }
    r = solve(load);
  }
  const mult = inp.priceMult;
  const prices = r.prices.map((row) => row.map((x) => x * mult));
  let avg = 0, peak = 0, off = 0, mn = Infinity, mx = -Infinity;
  for (let d = 0; d < 2; d++) for (let h = 0; h < 24; h++) {
    const x = prices[d][h], w = DAY_WEIGHTS[d] / 24;
    avg += x * w;
    if (h >= 8 && h < 20 && d === 0) peak += x / 12; else off += x * w;
    mn = Math.min(mn, x); mx = Math.max(mx, x);
  }
  off /= (1 - DAY_WEIGHTS[0] * 12 / 24);
  const thermalMc: MonthPrices['thermalMc'] = blocks.map((b) => ({ cls: b.cls, mw: b.mw, mc: b.mc * mult }));
  return { year: inp.year, month: inp.month, prices, demand: r.demand, curtail: r.curtail, avg, peak, offpeak: off, min: mn, max: mx, hydrology: inp.hydrology, thermalMc, waterValue: waterValue * mult };
}

/** Factor de calibración de los costos marginales térmicos del país (año base, hidrología normal, sin actores). */
export function calibrationFactor(ctx: SimContext, iso: string): number {
  let m = calibCache.get(ctx.data);
  if (!m) { m = new Map(); calibCache.set(ctx.data, m); }
  const hit = m.get(iso);
  if (hit !== undefined) return hit;
  const c = ctx.data.countries[iso];
  const target = c.mercado.precio_spot_medio_usd_mwh.base;
  const mean = (k: number) => {
    let s = 0;
    for (let mo = 1; mo <= 12; mo++) s += computeMonthPrices(ctx, iso, baseInputs(ctx, c, mo), k).avg;
    return s / 12;
  };
  let lo = 0.3, hi = 3;
  if (mean(lo) >= target) { m.set(iso, lo); return lo; }
  if (mean(hi) <= target) { m.set(iso, hi); return hi; }
  for (let i = 0; i < 30; i++) {
    const mid = (lo + hi) / 2;
    if (mean(mid) > target) hi = mid; else lo = mid;
  }
  const k = (lo + hi) / 2;
  m.set(iso, k);
  return k;
}

function staticFuelPrice(ctx: SimContext, c: CountrySimDef) {
  return (fuelType: string) => {
    const map = c.combustibles?.[fuelType];
    const id = map?.indice ?? fuelType;
    const f = ctx.data.markets?.combustibles.find((x) => x.id === id);
    return f ? f.precio_usd_mmbtu.base * (map?.factor ?? 1) : 0;
  };
}

function baseInputs(ctx: SimContext, c: CountrySimDef, month: number): MarketInputs {
  return { year: 0, month, yearsFromStart: 0, hydrology: 1, demandFactor: 1, fuelPrice: staticFuelPrice(ctx, c), carbonUsdT: c.carbono?.precio_usd_tco2.base ?? 0, priceMult: 1 };
}

// ───────────────────────── Estado: clima, parque de los actores, precios del mes ─────────────────────────

function allProjects(state: GameState): Project[] {
  const out = [...state.projects];
  for (const comp of state.competitors ?? []) if (comp.status === 'activa') out.push(...comp.projects);
  return out;
}

/** Foto del parque de los actores por país (pública: plantas en operación y en obra). */
export function fleetSnapshots(state: GameState, ctx: SimContext): Record<string, FleetSnapshot> {
  const out: Record<string, FleetSnapshot> = {};
  const get = (iso: string) => (out[iso] ??= { mw: {}, thermal: [], storage: { mw: 0, hours: 0, eff: 0 }, servicesMw: 0, construction: [] });
  const startEpoch = state.startEpochDay;
  for (const p of allProjects(state)) {
    if (TERMINAL_STAGES.includes(p.stage)) continue;
    const tech = ctx.data.technologies[p.techId];
    if (!tech) continue;
    const cls = techClass(ctx, p.techId);
    const f = get(p.countryCode);
    if (p.operation) {
      if (tech.combustible && cls && ctx.data.power?.clases[cls]?.tipo === 'termica') f.thermal.push({ techId: p.techId, mw: p.mw });
      else if (cls) f.mw[cls] = (f.mw[cls] ?? 0) + p.mw * fcScale(ctx, tech, cls, p);
      else if (tech.almacenamiento) {
        const h = tech.almacenamiento.horas.base, e = tech.almacenamiento.eficiencia_ida_vuelta.base;
        const tot = f.storage.mw + p.mw;
        f.storage = { mw: tot, hours: (f.storage.hours * f.storage.mw + h * p.mw) / tot, eff: (f.storage.eff * f.storage.mw + e * p.mw) / tot };
      }
      const pol = p.dispatch;
      if (pol?.servicios) f.servicesMw += p.mw * (pol.fraccionServicios ?? 0.3);
    } else if (p.construction) {
      const k = p.construction;
      const codTick = k.startTick + k.plannedDays + k.delayDays + 30;
      const d = fromEpochDay(startEpoch + codTick);
      f.construction.push({ cls, techId: p.techId, mw: p.mw * (cls && !tech.combustible ? fcScale(ctx, tech, cls, p) : 1), codYm: ym(d.year, d.month) });
    }
  }
  return out;
}

/** Ajusta los MW de un actor por su factor de planta frente al típico de la clase (un sitio mejor produce más). */
function fcScale(ctx: SimContext, tech: TechnologyDef, cls: string, p: Project): number {
  // La foto usa el factor típico de la tecnología (información pública), nunca el recurso real oculto.
  const def = ctx.data.power!.clases[cls];
  if (def.tipo === 'termica' || def.tipo === 'base') return 1;
  void p;
  return Math.max(0.3, Math.min(2.5, tech.factor_capacidad_ref.base / def.fc));
}

export function currentYm(state: GameState): number {
  const d = fromEpochDay(state.startEpochDay + state.tick);
  return ym(d.year, d.month);
}

function startYearOf(state: GameState): number {
  return fromEpochDay(state.startEpochDay).year;
}

/** El Niño / La Niña y la hidrología del año por país (flujo `market`). */
function drawClimate(state: GameState, ctx: SimContext, ps: PowerState, year: number) {
  const P = ctx.data.power!;
  if (!state.rng.market) state.rng.market = seedStream(state.seed, 'market');
  const rng = new Rng(state.rng.market);
  const prev = ps.enso;
  const u = rng.next();
  let enso: PowerState['enso'];
  if (prev !== 'neutral' && u < P.clima.persistencia) enso = prev;
  else {
    const v = rng.next();
    enso = v < P.clima.prob_nino ? 'nino' : v < P.clima.prob_nino + P.clima.prob_nina ? 'nina' : 'neutral';
  }
  ps.enso = enso;
  ps.ensoYear = year;
  for (const iso of Object.keys(ctx.data.countries).sort()) {
    const pc = P.paises[iso];
    if (!pc) continue;
    const z = Math.max(-2.5, Math.min(2.5, rng.normal()));
    const e = enso === 'nino' ? pc.enso?.nino_hidro ?? 1 : enso === 'nina' ? pc.enso?.nina_hidro ?? 1 : 1;
    ps.hydrology[iso] = Math.max(0.35, Math.min(1.8, Math.exp(pc.sigma_hidrologia * z - pc.sigma_hidrologia ** 2 / 2) * e));
  }
}

function ensoDemand(ctx: SimContext, ps: PowerState, iso: string): number {
  return ps.enso === 'nino' ? powerCountry(ctx, iso)?.enso?.nino_demanda ?? 1 : 1;
}

function stateInputs(state: GameState, ctx: SimContext, ps: PowerState, iso: string, year: number, month: number, forecast: boolean, longRun = false): MarketInputs {
  const c = ctx.data.countries[iso];
  const y0 = startYearOf(state);
  const target = ym(year, month), now = currentYm(state);
  const dt = Math.max(0, (target - now) / 12);
  const fuels = ctx.data.markets?.combustibles ?? [];
  const tick = state.tick + Math.round((target - now) * 30.44);
  const fuelPrice = (fuelType: string) => {
    const map = c.combustibles?.[fuelType];
    const id = map?.indice ?? fuelType;
    const f = fuels.find((x) => x.id === id);
    if (!f) return 0;
    const idx = state.market?.fuels?.[id] ?? 1;
    const expIdx = forecast ? 1 + (idx - 1) * Math.exp(-f.reversion_anual * (longRun ? Math.max(dt, LONG_RUN_YEARS) : dt)) : idx;
    return f.precio_usd_mmbtu.base * expIdx * (map?.factor ?? 1) * (longRun ? 1 : worldFuelFactor(state, id, iso, tick));
  };
  const sameYear = year === fromYm(now).year && !longRun;
  const hydro = (sameYear ? ps.hydrology[iso] ?? 1 : 1) * (longRun ? 1 : worldHydrologyFactor(state, iso, tick));
  const fleet = ps.fleet[iso];
  let extraMw: Record<string, number> | undefined, extraThermal: { techId: string; mw: number }[] | undefined;
  if (forecast && fleet) {
    for (const k of fleet.construction) {
      if (k.codYm > target && !longRun) continue;
      const tech = ctx.data.technologies[k.techId];
      if (tech?.combustible && k.cls && ctx.data.power!.clases[k.cls].tipo === 'termica') (extraThermal ??= []).push({ techId: k.techId, mw: k.mw });
      else if (k.cls) (extraMw ??= {})[k.cls] = (extraMw?.[k.cls] ?? 0) + k.mw;
    }
  }
  const infl = Math.pow(1 + usdInflation(c), Math.max(0, year - y0));
  return {
    year, month, yearsFromStart: year - y0, hydrology: hydro,
    demandFactor: longRun ? 1 : worldDemandFactor(state, iso, tick) * (sameYear ? ensoDemand(ctx, ps, iso) : 1),
    fuelPrice, carbonUsdT: (c.carbono ? c.carbono.precio_usd_tco2.base * Math.pow(1 + c.carbono.crecimiento_anual, Math.max(0, year - y0)) : 0) + worldCarbonAddUsdT(state, iso),
    fleet, extraMw, extraThermal, priceMult: infl * fxReal(state, iso),
  };
}

/** Inicializa (perezosamente) el mercado eléctrico. Determinista. */
export function ensurePower(state: GameState, ctx: SimContext) {
  if (!ctx.data.power || !state.market) return;
  if (state.market.power) return;
  const ps: PowerState = { version: 1, ym: currentYm(state), enso: 'neutral', ensoYear: 0, hydrology: {}, fleet: {}, current: {}, history: {} };
  state.market.power = ps;
  drawClimate(state, ctx, ps, fromYm(ps.ym).year);
  refreshMonth(state, ctx, ps);
}

function refreshMonth(state: GameState, ctx: SimContext, ps: PowerState) {
  ps.fleet = fleetSnapshots(state, ctx);
  const { year, month } = fromYm(ps.ym);
  for (const iso of Object.keys(ctx.data.countries).sort()) {
    if (!ctx.data.power!.paises[iso]) continue;
    ps.current[iso] = computeMonthPrices(ctx, iso, stateInputs(state, ctx, ps, iso, year, month, false), calibrationFactor(ctx, iso));
  }
  ps.version++;
}

/** Cierre del mes: registra el mes que terminó, sortea el clima si empieza un año y calcula los precios del mes nuevo. */
export function powerMonthly(state: GameState, ctx: SimContext, events: SimEvent[]) {
  const ps = state.market?.power;
  if (!ps || !ctx.data.power) return;
  for (const [iso, mp] of Object.entries(ps.current)) {
    const h = (ps.history[iso] ??= []);
    h.push({ year: mp.year, month: mp.month, avg: mp.avg, peak: mp.peak, offpeak: mp.offpeak, min: mp.min, max: mp.max, hydrology: mp.hydrology });
    if (h.length > 120) h.splice(0, h.length - 120);
  }
  const prevYear = fromYm(ps.ym).year;
  ps.ym = currentYm(state);
  const { year } = fromYm(ps.ym);
  if (year !== prevYear) {
    const before = ps.enso;
    drawClimate(state, ctx, ps, year);
    if (ps.enso !== before && ps.enso !== 'neutral') {
      events.push({ type: 'climateOutlook', enso: ps.enso, severity: 'info',
        text: ps.enso === 'nino' ? 'Los meteorólogos confirman El Niño para este año: menos lluvia en Centroamérica y Colombia (hidro más cara).' : 'Se instala La Niña: más lluvias en Centroamérica y Colombia (hidro abundante, spot más bajo).' });
    }
  }
  refreshMonth(state, ctx, ps);
}

const forecastCache = new WeakMap<PowerState, Map<string, MonthPrices>>();
/** Horizonte de la previsión «de largo plazo» (combustibles vuelven a su media, sin eventos temporales, hidrología normal). */
export const LONG_RUN_YEARS = 3;

/**
 * Precios horarios de un mes: el del mes en curso es el calculado; los demás son una previsión con la información pública
 * de hoy (hidrología conocida del año en curso, normal después; combustibles que vuelven a su media; eventos vigentes;
 * plantas en obra que entran en su fecha esperada). Sin datos de la Fase 5 devuelve undefined.
 */
export function monthPrices(state: GameState, ctx: SimContext, iso: string, year: number, month: number, longRun = false): MonthPrices | undefined {
  if (!ctx.data.power?.paises[iso]) return undefined;
  const ps = state.market?.power ?? ephemeralPower(state, ctx);
  if (!ps) return undefined;
  const t = ym(year, month);
  if (t === ps.ym && ps.current[iso] && !longRun) return ps.current[iso];
  let cache = forecastCache.get(ps);
  if (!cache) { cache = new Map(); forecastCache.set(ps, cache); }
  const key = `${ps.version}|${iso}|${t}|${longRun ? 'L' : ''}`;
  const hit = cache.get(key);
  if (hit) return hit;
  // Meses pasados: no se recalculan (la previsión del pasado no existe); se usa el mismo mes del año actual.
  const target = t < ps.ym ? ps.ym + ((month - 1 - (ps.ym % 12) + 12) % 12) : t;
  const tt = fromYm(target);
  const mp = computeMonthPrices(ctx, iso, stateInputs(state, ctx, ps, iso, longRun ? year : tt.year, longRun ? month : tt.month, true, longRun), calibrationFactor(ctx, iso));
  if (cache.size > 4000) cache.clear();
  cache.set(key, mp);
  return mp;
}

const ephemeralCache = new WeakMap<object, PowerState>();
/** Estado del mercado calculado al vuelo (selectores sobre partidas sin inicializar); no se guarda. */
function ephemeralPower(state: GameState, ctx: SimContext): PowerState | undefined {
  if (!state.market) return undefined;
  const key = state.market;
  const hit = ephemeralCache.get(key);
  if (hit && hit.ym === currentYm(state)) return hit;
  const ps: PowerState = { version: 1, ym: currentYm(state), enso: 'neutral', ensoYear: 0, hydrology: {}, fleet: fleetSnapshots(state, ctx), current: {}, history: {} };
  for (const iso of Object.keys(ctx.data.countries)) ps.hydrology[iso] = 1;
  ephemeralCache.set(key, ps);
  return ps;
}

/** Spot medio (USD/MWh) del mes según el mercado de la Fase 5; sin datos, el spot simple de la Fase 2–4. */
export function spotMonthUsd(state: GameState, ctx: SimContext, iso: string, year: number, month: number, longRun = false): number {
  const mp = monthPrices(state, ctx, iso, year, month, longRun);
  if (mp) return mp.avg;
  const c = ctx.data.countries[iso];
  return spotPrice(c, startYearOf(state), year, month) * fxReal(state, iso);
}

/** Spot medio anual en USD. */
export function spotYearUsd(state: GameState, ctx: SimContext, iso: string, year: number, longRun = false): number {
  let s = 0;
  for (let m = 1; m <= 12; m++) s += spotMonthUsd(state, ctx, iso, year, m, longRun);
  return s / 12;
}

/** Implementación de la interfaz `SpotMarket` sobre el mercado de la Fase 5. */
export function powerSpotMarket(state: GameState, ctx: SimContext) {
  return { priceUsdMwh: (countryCode: string, year: number, month: number) => spotMonthUsd(state, ctx, countryCode, year, month) };
}

// ───────────────────────── Almacenamiento: arbitraje de un día ─────────────────────────

export interface StorageDayPlan { charge: number[]; discharge: number[]; profitPerMw: number }

/**
 * Arbitraje de un día (por MW): descarga en las horas más caras y carga en las más baratas mientras
 * precio_descarga − precio_carga / eficiencia > `minSpread` (O&M variable) y se respeten los umbrales opcionales.
 * `hours` = MWh por MW utilizables (duración × (1 − reserva mínima)); `cyclesCap` = ciclos máximos por día.
 */
export function storageDay(prices: number[], o: { hours: number; eff: number; cyclesCap: number; minSpread?: number; chargeBelow?: number; dischargeAbove?: number }): StorageDayPlan {
  const charge = new Array(24).fill(0), discharge = new Array(24).fill(0);
  const maxOut = Math.max(0, o.hours * o.cyclesCap);
  const desc = [...prices.keys()].sort((a, b) => prices[b] - prices[a] || a - b);
  const asc = [...prices.keys()].sort((a, b) => prices[a] - prices[b] || a - b);
  const eff = Math.max(0.05, o.eff);
  let out = 0, profit = 0;
  for (const hd of desc) {
    if (out >= maxOut - 1e-9) break;
    if (charge[hd] > 0) continue;
    if (o.dischargeAbove !== undefined && prices[hd] < o.dischargeAbove) break;
    const amount = Math.min(1, maxOut - out);
    // Carga necesaria: amount / eff, en las horas más baratas libres (1 MW por hora).
    let need = amount / eff, cost = 0;
    const take: [number, number][] = [];
    for (const hc of asc) {
      if (need <= 1e-12) break;
      if (discharge[hc] > 0 || hc === hd) continue;
      if (o.chargeBelow !== undefined && prices[hc] > o.chargeBelow) break;
      const room = 1 - charge[hc] - take.filter(([h]) => h === hc).reduce((a, [, x]) => a + x, 0);
      if (room <= 1e-12) continue;
      const x = Math.min(room, need);
      take.push([hc, x]);
      cost += x * prices[hc];
      need -= x;
    }
    if (need > 1e-9) break;
    const gain = prices[hd] * amount - cost;
    if (gain <= (o.minSpread ?? 0) * amount) break;
    discharge[hd] = amount;
    for (const [h, x] of take) charge[h] += x;
    out += amount;
    profit += gain;
  }
  return { charge, discharge, profitPerMw: profit };
}

export { ym as yearMonthIndex, fromYm as yearMonthFromIndex };
