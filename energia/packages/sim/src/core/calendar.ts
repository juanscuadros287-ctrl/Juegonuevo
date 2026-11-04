/** Calendario del juego. El tiempo es un número entero de días desde la fecha de inicio. */
export interface GameDate { year: number; month: number; day: number } // month 1–12

const MS_DAY = 86400000;

export function parseIsoDate(iso: string): GameDate {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso);
  if (!m) throw new Error(`Fecha inválida: ${iso}`);
  return { year: +m[1], month: +m[2], day: +m[3] };
}

/** Días desde 1970-01-01 (aritmética pura en UTC, sin depender del reloj del sistema). */
export function toEpochDay(d: GameDate): number {
  return Math.round(Date.UTC(d.year, d.month - 1, d.day) / MS_DAY);
}

export function fromEpochDay(n: number): GameDate {
  const dt = new Date(n * MS_DAY);
  return { year: dt.getUTCFullYear(), month: dt.getUTCMonth() + 1, day: dt.getUTCDate() };
}

export function daysInMonth(year: number, month: number): number {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

export const MONTHS_ES = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];

export function formatDate(d: GameDate, short = false): string {
  const m = MONTHS_ES[d.month - 1];
  return short ? `${d.day} ${m.slice(0, 3)} ${d.year}` : `${d.day} de ${m} de ${d.year}`;
}
