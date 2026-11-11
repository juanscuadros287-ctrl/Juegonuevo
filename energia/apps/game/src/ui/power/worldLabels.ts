import type { WorldEventView } from '@voltaje/sim';

/** Etiqueta y color por tipo de evento del mundo (events.yaml `tipo`). */
export const KIND: Record<string, { label: string; color: string; glyph: string }> = {
  desastre: { label: 'Desastre', color: '#f87171', glyph: '!' },
  conflicto: { label: 'Conflicto', color: '#f97316', glyph: '×' },
  salud: { label: 'Salud', color: '#c084fc', glyph: '+' },
  economico: { label: 'Economía', color: '#fbbf24', glyph: '$' },
  social: { label: 'Social', color: '#fbbf24', glyph: '≡' },
  regulatorio: { label: 'Regulación', color: '#60a5fa', glyph: '§' },
  politico: { label: 'Política', color: '#60a5fa', glyph: '◆' },
  tecnologia: { label: 'Tecnología', color: '#4ade80', glyph: '▲' },
};
export const kindOf = (k: string) => KIND[k] ?? { label: k, color: '#94a3b8', glyph: '•' };

/** Glifo propio de algunos eventos (marcador del globo). */
const GLYPH: Record<string, string> = { huracan: '@', terremoto: '!', inundacion: '≈', sequia: '☼', guerra_regional: '×', pandemia: '+', crisis_petrolera: '$', huelga_nacional: '≡', devaluacion: '$' };
export const glyphOf = (e: Pick<WorldEventView, 'id' | 'kind'>) => GLYPH[e.id] ?? kindOf(e.kind).glyph;

/** Eventos graves: aviso grande y resaltado fuerte en el globo. */
export const isGrave = (e: Pick<WorldEventView, 'id' | 'kind'>) => ['desastre', 'conflicto', 'salud'].includes(e.kind) || e.id === 'crisis_petrolera' || e.id === 'devaluacion';
