/** Fase 4: etiquetas, íconos y modos de las tecnologías para la UI (desarrollar, catálogo, fichas). */
import { gameData } from '@voltaje/data';
import { techMode, type TechMode, type TechnologyDef } from '@voltaje/sim';

export const TECH_ICON: Record<string, string> = {
  solar_fv: '☀', csp: '◎', eolica_tierra: '✇', eolica_marina: '⚓', geotermica: '♨', hidro_pasada: '≈', hidro_embalse: '▼', hidro_bombeo: '⇅',
  biomasa: '❦', biogas: '◍', gas_natural: '▲', carbon: '■', petroleo: '◆', nuclear: '☢', smr: '⚛', baterias: '▮', hidrogeno_verde: 'H₂',
  linea_transmision: '⚡', interconexion: '⇄', eficiencia_energetica: '✦',
};

export const MODE_ORDER: TechMode[] = ['generacion', 'termica', 'almacenamiento', 'hidrogeno', 'transmision', 'eficiencia'];
export const MODE_LABEL: Record<TechMode, string> = {
  generacion: 'Generación renovable', termica: 'Térmica (combustible)', almacenamiento: 'Almacenamiento', hidrogeno: 'Hidrógeno',
  transmision: 'Transmisión', eficiencia: 'Eficiencia (ESCO)',
};
export const MODE_SHORT: Record<TechMode, string> = {
  generacion: 'Renovable', termica: 'Térmica', almacenamiento: 'Almacen.', hidrogeno: 'H₂', transmision: 'Red', eficiencia: 'ESCO',
};
/** Qué es el «producto» (MWh) de cada modo y en qué unidad se nivela su costo. */
export const MODE_PRODUCT: Record<TechMode, { energy: string; lcoe: string }> = {
  generacion: { energy: 'Energía P50', lcoe: 'LCOE' }, termica: { energy: 'Energía despachada', lcoe: 'LCOE' },
  almacenamiento: { energy: 'Energía descargada', lcoe: 'LCOS (con carga)' }, hidrogeno: { energy: 'Electricidad consumida', lcoe: 'Costo nivelado / MWh' },
  transmision: { energy: 'Energía transportada', lcoe: 'Costo nivelado / MWh transp.' }, eficiencia: { energy: 'Ahorro (MWh/año)', lcoe: 'Costo / MWh ahorrado' },
};

export const allTechs = (): TechnologyDef[] => Object.values(gameData.simData.technologies);
export const modeOf = (id: string): TechMode => techMode(gameData.simData.technologies[id]);

/** Nombre de un combustible (markets.yaml). */
export function fuelName(id: string | undefined): string {
  if (!id) return '—';
  const f = gameData.simData.markets?.combustibles.find((x) => x.id === id);
  return f?.nombre ?? ({ fueloil: 'Fuel oil', uranio: 'Uranio', biomasa: 'Biomasa', biogas: 'Biogás', carbon: 'Carbón' } as Record<string, string>)[id] ?? id;
}

/** Paso del deslizador de MW según el rango de la tecnología. */
export function mwStep(lo: number, hi: number): number {
  const span = hi - lo;
  if (span <= 60) return 1;
  if (span <= 300) return 5;
  if (span <= 1500) return 10;
  return 50;
}

export const countryName = (iso3: string | undefined) => (iso3 ? gameData.simData.countries[iso3]?.nombre ?? iso3 : '—');
