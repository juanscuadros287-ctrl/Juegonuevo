const usd0 = new Intl.NumberFormat('es-PA', { style: 'currency', currency: 'USD', maximumFractionDigits: 0 });
const num = new Intl.NumberFormat('es-PA', { maximumFractionDigits: 1 });

export const fmtUsd = (v: number) => usd0.format(v);
export const fmtNum = (v: number, digits = 1) => new Intl.NumberFormat('es-PA', { maximumFractionDigits: digits }).format(v);
export const fmtCompact = (v: number) => new Intl.NumberFormat('es-PA', { notation: 'compact', maximumFractionDigits: 1 }).format(v);
export const fmtLat = (lat: number) => `${num.format(Math.abs(lat))}° ${lat >= 0 ? 'N' : 'S'}`;
export const fmtLon = (lon: number) => `${num.format(Math.abs(lon))}° ${lon >= 0 ? 'E' : 'O'}`;
