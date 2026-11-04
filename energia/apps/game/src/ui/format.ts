import { formatDate, fromEpochDay, type GameDate, type GameState } from '@voltaje/sim';

const usd0 = new Intl.NumberFormat('es-PA', { style: 'currency', currency: 'USD', maximumFractionDigits: 0 });
const num = new Intl.NumberFormat('es-PA', { maximumFractionDigits: 1 });

export const fmtUsd = (v: number) => usd0.format(v);
export const fmtNum = (v: number, digits = 1) => new Intl.NumberFormat('es-PA', { maximumFractionDigits: digits }).format(v);
export const fmtCompact = (v: number) => new Intl.NumberFormat('es-PA', { notation: 'compact', maximumFractionDigits: 1 }).format(v);
export const fmtLat = (lat: number) => `${num.format(Math.abs(lat))}° ${lat >= 0 ? 'N' : 'S'}`;
export const fmtLon = (lon: number) => `${num.format(Math.abs(lon))}° ${lon >= 0 ? 'E' : 'O'}`;

/** Montos grandes compactos: US$ 12,3 M, US$ 850 k. */
export function fmtMoney(v: number | null | undefined): string {
  if (v === null || v === undefined || !Number.isFinite(v)) return '—';
  const a = Math.abs(v), s = v < 0 ? '−' : '';
  if (a >= 1e9) return `${s}US$ ${fmtNum(a / 1e9, 2)} mil M`;
  if (a >= 1e6) return `${s}US$ ${fmtNum(a / 1e6, a >= 1e8 ? 0 : 2)} M`;
  if (a >= 1e4) return `${s}US$ ${fmtNum(a / 1e3, 0)} k`;
  return `${s}US$ ${fmtNum(a, 0)}`;
}

/** Fracción → porcentaje ("12,3 %"); null → "—". */
export function fmtPct(v: number | null | undefined, digits = 1): string {
  if (v === null || v === undefined || !Number.isFinite(v)) return '—';
  return `${fmtNum(v * 100, digits)} %`;
}

export const fmtDate = (d: GameDate | undefined, short = true) => (d ? formatDate(d, short) : '—');
export const dateOfTick = (g: GameState, tick: number) => fromEpochDay(g.startEpochDay + tick);
export const MONTHS_SHORT = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
export const monthLabel = (year: number, month: number) => `${MONTHS_SHORT[month - 1]} ${String(year).slice(2)}`;
export const fmtDays = (d: { min: number; base: number; max: number }) => (d.min === d.max ? `${d.base} d` : `${d.min}–${d.max} d`);
