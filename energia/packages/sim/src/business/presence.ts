import type { GameState } from '../core/state';
import type { SimContext } from '../core/context';
import type { SimEvent } from '../core/events';
import { Rng } from '../core/rng';
import { postCash } from '../finance/company';
import { drawDays } from '../project/outcomes';
import { isTerminal } from '../project/helpers';
import { countryUnlocked, unlockingNode } from './research';
import type { Presence } from './types';

/**
 * Fase 4: presencia en otros países. Para desarrollar, ofertar o firmar en un país hay que (1) tenerlo desbloqueado
 * por I+D (nodo de mercado) y (2) abrir presencia: constitución de una sociedad local y representante legal
 * (costo inicial + días de trámite + costo mensual). El país de origen está siempre abierto.
 * Interfaz preparada para la Fase 6: `Presence.level` = 'representante' hoy; 'oficina' (oficina completa con equipo) después.
 */

export type PresenceCommand =
  | { type: 'openPresence'; countryCode: string }
  | { type: 'closePresence'; countryCode: string };

type Result = { ok: true } | { ok: false; error: string };
const fmt = (v: number) => `${Math.round(v).toLocaleString('es-PA')} USD`;

export function presenceOf(state: Pick<GameState, 'business'>, iso3: string): Presence | undefined {
  return state.business?.presence?.[iso3];
}

/** ¿El actor puede operar en el país hoy? (país de origen o presencia activa). */
export function hasPresence(state: Pick<GameState, 'business' | 'company'>, iso3: string): boolean {
  if (iso3 === state.company.homeCountry) return true;
  return presenceOf(state, iso3)?.status === 'activa';
}

/** Faltantes para operar en un país (I+D y presencia). Vacío = se puede. */
export function countryAccessBlockers(state: GameState, ctx: SimContext, iso3: string): string[] {
  const c = ctx.data.countries[iso3];
  if (!c) return ['País sin datos.'];
  const out: string[] = [];
  if (!countryUnlocked(state, ctx, iso3)) out.push(`Mercado cerrado: ${c.nombre} requiere investigación (${unlockingNode(ctx, 'paises', iso3)?.nombre ?? 'I+D'}).`);
  else if (!hasPresence(state, iso3)) {
    const p = presenceOf(state, iso3);
    out.push(p?.status === 'en_tramite' ? `La constitución en ${c.nombre} todavía está en trámite.` : `Sin presencia en ${c.nombre}: abre una sociedad local y un representante legal.`);
  }
  return out;
}

export function presenceBlockers(state: GameState, ctx: SimContext, iso3: string): string[] {
  const c = ctx.data.countries[iso3];
  if (!c) return ['País sin datos.'];
  const out: string[] = [];
  if (iso3 === state.company.homeCountry) out.push('Es el país de origen de la empresa.');
  const p = presenceOf(state, iso3);
  if (p && p.status !== 'cerrada') out.push(p.status === 'activa' ? 'Ya hay presencia en el país.' : 'La constitución ya está en trámite.');
  if (!countryUnlocked(state, ctx, iso3)) out.push(`Requiere investigación: ${unlockingNode(ctx, 'paises', iso3)?.nombre ?? 'I+D'}.`);
  if (!c.expansion) out.push(`${c.nombre} no admite presencia todavía.`);
  else if (state.company.cashUsd < c.expansion.constitucion_usd.base) out.push(`Caja insuficiente: la constitución cuesta ${fmt(c.expansion.constitucion_usd.base)}.`);
  return out;
}

export function applyPresenceCommand(state: GameState, ctx: SimContext | undefined, cmd: PresenceCommand, events: SimEvent[]): Result {
  if (!ctx) return { ok: false, error: 'Datos del juego no disponibles.' };
  const c = ctx.data.countries[cmd.countryCode];
  if (!c) return { ok: false, error: 'País sin datos.' };
  state.business.presence ??= {};
  if (cmd.type === 'openPresence') {
    const b = presenceBlockers(state, ctx, cmd.countryCode);
    if (b.length) return { ok: false, error: b.join(' ') };
    const e = c.expansion!;
    const rng = new Rng(state.rng.business ?? state.rng.projects);
    const days = drawDays(rng, e.dias);
    postCash(state, 'presencia', -e.constitucion_usd.base, `Constitución de sociedad en ${c.nombre}`);
    state.business.presence[c.iso3] = {
      status: 'en_tramite', level: 'representante', requestedTick: state.tick, readyTick: state.tick + days,
      setupCostUsd: e.constitucion_usd.base, monthlyCostUsd: e.representante_mensual_usd.base,
    };
    events.push({ type: 'presenceRequested', countryCode: c.iso3, severity: 'info', text: `Constitución de la sociedad en ${c.nombre} iniciada (${fmt(e.constitucion_usd.base)}, ~${days} días; luego ${fmt(e.representante_mensual_usd.base)}/mes de representante legal).` });
    return { ok: true };
  }
  const p = presenceOf(state, cmd.countryCode);
  if (!p || p.status === 'cerrada') return { ok: false, error: 'No hay presencia en ese país.' };
  const busy = state.projects.some((x) => x.countryCode === cmd.countryCode && !isTerminal(x)) || state.business.contracts.some((k) => k.countryCode === cmd.countryCode && (k.status === 'sin_proyecto' || k.status === 'en_desarrollo' || k.status === 'operando'));
  if (busy) return { ok: false, error: `Hay proyectos o contratos activos en ${c.nombre}: no se puede cerrar la sociedad.` };
  p.status = 'cerrada';
  p.closedTick = state.tick;
  events.push({ type: 'presenceClosed', countryCode: c.iso3, severity: 'info', text: `Sociedad en ${c.nombre} cerrada.` });
  return { ok: true };
}

/** Avance diario: la constitución termina. */
export function presenceDaily(state: GameState, ctx: SimContext, events: SimEvent[]) {
  const pr = state.business?.presence;
  if (!pr) return;
  for (const [iso, p] of Object.entries(pr)) {
    if (p.status === 'en_tramite' && state.tick >= p.readyTick) {
      p.status = 'activa';
      events.push({ type: 'presenceOpened', countryCode: iso, severity: 'bueno', text: `Sociedad constituida en ${ctx.data.countries[iso]?.nombre ?? iso}: ya puedes desarrollar proyectos y ofertar allí.` });
    }
  }
}

/** Cierre de mes: representante legal y gastos de la sociedad local. */
export function presenceMonthly(state: GameState, ctx: SimContext) {
  const pr = state.business?.presence;
  if (!pr) return;
  for (const [iso, p] of Object.entries(pr)) {
    if (p.status === 'cerrada') continue;
    postCash(state, 'presencia', -p.monthlyCostUsd, `Representante legal en ${ctx.data.countries[iso]?.nombre ?? iso}`);
  }
}

/** Países en los que algún actor (jugador o IA activa) tiene presencia o es su origen: allí se generan oportunidades. */
export function openCountries(state: GameState): Set<string> {
  const s = new Set<string>([state.company.homeCountry]);
  const add = (b: GameState['business'] | undefined, home: string) => {
    s.add(home);
    for (const [iso, p] of Object.entries(b?.presence ?? {})) if (p.status !== 'cerrada') s.add(iso);
  };
  add(state.business, state.company.homeCountry);
  for (const c of state.competitors ?? []) if (c.status === 'activa') add(c.business, c.company.homeCountry);
  return s;
}
