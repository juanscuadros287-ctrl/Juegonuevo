import type { GameState } from '../core/state';
import type { SimContext } from '../core/context';
import type { SimEvent } from '../core/events';
import { Rng, seedStream } from '../core/rng';
import { fromEpochDay } from '../core/calendar';
import type { CountrySimDef } from '../data/types';
import { drawDist } from '../project/outcomes';

/**
 * Fase 4: macroeconomía por país y combustibles.
 *
 * Tipo de cambio: el motor guarda el tipo de cambio REAL de cada país (1 al inicio). El nominal (USD por unidad local) es
 *   nominal(t) = usd_por_unidad₀ · real(t) · ((1 + π_USD) / (1 + π_local))^años     (paridad de poder de compra + desvío real)
 * El desvío real sigue un proceso log-normal con reversión a la media, deriva propia y shocks (devaluaciones).
 * Una moneda con volatilidad 0 y deriva 0 está fija al USD (Panamá: el nominal no cambia).
 *
 * Con eso, en USD:
 *   - el spot y los costos locales (indexados a la inflación local) valen precio₀ · (1 + π_USD)^años · real(t);
 *   - un contrato en moneda local sin indexar pierde (1 + π_USD)/(1 + π_local) por año además del desvío real;
 *   - la deuda está en USD: una devaluación (real < 1) baja ingresos en USD y deja igual el servicio de la deuda.
 *
 * Combustibles: índice log-normal mensual con reversión a 1 (como los materiales de la Fase 3), flujo RNG `fuels`.
 */

const DT = 1 / 12;

/** Moneda fija al USD (dolarizada o con paridad fija). */
export function isPegged(c: CountrySimDef): boolean {
  return (c.tipo_cambio.volatilidad_anual ?? 0) === 0 && (c.tipo_cambio.deriva_anual ?? 0) === 0 && !(c.tipo_cambio.shock_prob_anual ?? 0);
}

/** Inflación de los precios del país expresados en USD (la local si la moneda está fija; si no, la del USD). */
export function usdInflation(c: CountrySimDef): number {
  return c.inflacion_usd_anual ?? c.inflacion_anual.base;
}

export function usdInflationGlobal(ctx: SimContext): number {
  return ctx.data.markets?.inflacion_usd.base ?? 0.025;
}

/** Tipo de cambio real (1 = el del inicio). */
export function fxReal(state: Pick<GameState, 'market'>, iso3: string): number {
  return state.market?.fx?.[iso3] ?? 1;
}

/** Años de partida (fracción). */
function years(state: Pick<GameState, 'tick'>): number {
  return state.tick / 365.25;
}

/** Tipo de cambio nominal hoy (USD por unidad local). */
export function fxNominal(state: Pick<GameState, 'market' | 'tick'>, ctx: SimContext, iso3: string): number {
  const c = ctx.data.countries[iso3];
  if (!c) return 1;
  if (isPegged(c)) return c.moneda.usd_por_unidad;
  const ppp = Math.pow((1 + usdInflationGlobal(ctx)) / (1 + c.inflacion_anual.base), years(state));
  return c.moneda.usd_por_unidad * fxReal(state, iso3) * ppp;
}

/** Factor sobre los costos de operación por la parte pagada en moneda local (1 en monedas fijas o sin desvío). */
export function localCostFxFactor(state: Pick<GameState, 'market'>, c: CountrySimDef): number {
  const r = fxReal(state, c.iso3);
  if (r === 1) return 1;
  return 1 + (c.costos.fraccion_costos_locales ?? 0.5) * (r - 1);
}

/**
 * Indexación anual efectiva EN USD de un contrato: en USD = la del contrato; en moneda local =
 * (1 + i)·(1 + π_USD)/(1 + π_local) − 1 (en monedas fijas al USD es la misma i).
 */
export function usdIndexation(ctx: SimContext, c: CountrySimDef, indexation: number, currency: 'USD' | 'local' | undefined): number {
  if (currency !== 'local' || isPegged(c)) return indexation;
  return (1 + indexation) * (1 + usdInflationGlobal(ctx)) / (1 + c.inflacion_anual.base) - 1;
}

/** Moneda por defecto de los contratos de un país. */
export function contractCurrency(c: CountrySimDef | undefined, override?: 'USD' | 'local'): 'USD' | 'local' {
  return override ?? c?.mercado.moneda_contratos ?? 'USD';
}

/** Índice de un combustible (1 = precio de referencia). */
export function fuelIndex(state: Pick<GameState, 'market'> | null | undefined, fuelId: string): number {
  return state?.market?.fuels?.[fuelId] ?? 1;
}

/** Inicializa (perezosamente) tipos de cambio y combustibles. Determinista. */
export function ensureMacro(state: GameState, ctx: SimContext) {
  const m = state.market;
  if (!m) return;
  if (!state.rng.fx) state.rng.fx = seedStream(state.seed, 'fx');
  if (!state.rng.fuels) state.rng.fuels = seedStream(state.seed, 'fuels');
  if (!m.fx) m.fx = {};
  for (const iso of Object.keys(ctx.data.countries).sort()) if (m.fx[iso] === undefined) m.fx[iso] = 1;
  if (!m.fuels) m.fuels = {};
  for (const f of ctx.data.markets?.combustibles ?? []) if (m.fuels[f.id] === undefined) m.fuels[f.id] = 1;
  if (!m.macroHistory) m.macroHistory = [];
}

/** Cierre de mes: nuevos tipos de cambio reales (con shocks) e índices de combustibles. */
export function macroMonthly(state: GameState, ctx: SimContext, year: number, month: number, events: SimEvent[], openCountries: Set<string>) {
  const m = state.market;
  if (!m?.fx) return;
  const rfx = new Rng(state.rng.fx);
  for (const iso of Object.keys(ctx.data.countries).sort()) {
    const c = ctx.data.countries[iso];
    if (isPegged(c)) { m.fx[iso] = 1; continue; }
    const tc = c.tipo_cambio;
    let lx = Math.log(m.fx[iso] ?? 1);
    lx = lx * (1 - (tc.reversion_anual ?? 0.25) * DT) + (tc.deriva_anual ?? 0) * DT + tc.volatilidad_anual * Math.sqrt(DT) * rfx.normal();
    if (tc.shock_prob_anual && rfx.chance(tc.shock_prob_anual * DT)) {
      const mag = tc.shock_magnitud ? drawDist(rfx, tc.shock_magnitud) : 0.2;
      lx += Math.log(Math.max(0.2, 1 - mag));
      if (openCountries.has(iso)) {
        events.push({ type: 'currencyShock', countryCode: iso, changePct: -mag * 100, severity: 'malo',
          text: `Devaluación en ${c.nombre}: el ${c.moneda.codigo} cae ${(mag * 100).toFixed(0)} % frente al USD. Los ingresos en moneda local valen menos en USD; la deuda en USD no cambia.` });
      }
    }
    m.fx[iso] = Math.min(3, Math.max(0.25, Math.exp(lx)));
  }
  const rf = new Rng(state.rng.fuels);
  for (const f of ctx.data.markets?.combustibles ?? []) {
    const before = m.fuels![f.id] ?? 1;
    const lx = Math.log(before) * (1 - f.reversion_anual * DT) + f.volatilidad_anual * Math.sqrt(DT) * rf.normal();
    const now = Math.min(f.max, Math.max(f.min, Math.exp(lx)));
    m.fuels![f.id] = now;
    const ch = now / before - 1;
    if (Math.abs(ch) >= 0.15) {
      events.push({ type: 'fuelPriceChange', fuelId: f.id, changePct: ch * 100, severity: 'info',
        text: `${f.nombre}: el precio ${ch > 0 ? 'sube' : 'baja'} ${Math.abs(ch * 100).toFixed(0)} % en el mes.` });
    }
  }
  const fxUsd: Record<string, number> = {};
  for (const iso of Object.keys(m.fx)) fxUsd[iso] = fxNominal(state, ctx, iso);
  m.macroHistory!.push({ year, month, fxUsdPerUnit: fxUsd, fuels: { ...m.fuels } });
  if (m.macroHistory!.length > 120) m.macroHistory!.splice(0, m.macroHistory!.length - 120);
}

/** Precio actual de un combustible (USD/MMBtu) en un país, sin logística de biomasa. */
export function fuelPriceUsdMmbtu(state: Pick<GameState, 'market'> | null, ctx: SimContext, c: CountrySimDef, fuelType: string): number {
  const map = c.combustibles?.[fuelType];
  const id = map?.indice ?? fuelType;
  const f = ctx.data.markets?.combustibles.find((x) => x.id === id);
  if (!f) return 0;
  return f.precio_usd_mmbtu.base * fuelIndex(state, id) * (map?.factor ?? 1);
}

export function fuelEmissionsKgMmbtu(ctx: SimContext, c: CountrySimDef, fuelType: string): number {
  const id = c.combustibles?.[fuelType]?.indice ?? fuelType;
  return ctx.data.markets?.combustibles.find((x) => x.id === id)?.emisiones_kgco2_mmbtu ?? 0;
}

/** Precio del carbono (USD/tCO2) en el año dado. */
export function carbonPriceUsdT(c: CountrySimDef, yearsFromStart: number): number {
  if (!c.carbono) return 0;
  return c.carbono.precio_usd_tco2.base * Math.pow(1 + c.carbono.crecimiento_anual, Math.max(0, yearsFromStart));
}

export function currentYearOf(state: GameState): number {
  return fromEpochDay(state.startEpochDay + state.tick).year;
}
