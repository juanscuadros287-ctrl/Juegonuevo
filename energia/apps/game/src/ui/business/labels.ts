import { gameData } from '@voltaje/data';
import { STAGE_LABELS, type ProjectStage } from '@voltaje/sim';
import { fmtNum } from '../format';

const TECH_FALLBACK: Record<string, string> = {
  baterias: 'Baterías', hidro_pasada: 'Hidro de pasada', hidro_embalse: 'Hidro con embalse', hidro_bombeo: 'Hidro de bombeo', geotermica: 'Geotérmica',
  csp: 'Solar de concentración', eolica_marina: 'Eólica marina', biomasa: 'Biomasa', biogas: 'Biogás', gas_natural: 'Gas natural', hidrogeno_verde: 'Hidrógeno verde',
};

/** Nombre legible de una tecnología (las de la Fase 4 aún no tienen YAML de tecnología). */
export const techName = (id: string) => gameData.simData.technologies[id]?.nombre ?? TECH_FALLBACK[id] ?? id.replace(/_/g, ' ');

/** Nombre corto para tablas. */
export const techShort = (id: string) => ({ solar_fv: 'Solar FV', eolica_tierra: 'Eólica' } as Record<string, string>)[id] ?? techName(id);

/** Precio con su unidad: 64,2 US$/MWh. */
export const fmtPrice = (v: number | null | undefined, unit: string, digits?: number) =>
  v === null || v === undefined || !Number.isFinite(v) ? '—' : `${fmtNum(v, digits ?? (v >= 100 ? 0 : 1))} ${unit.replace('USD', 'US$')}`;

/** Color de cada competidor (anillo en el globo, gráficas). Distinto de los colores de etapa del jugador. */
export const RIVAL_COLORS = ['#ef4444', '#e879f9', '#22d3ee', '#a3e635', '#fb7185', '#f97316'];
export const rivalColor = (index: number) => RIVAL_COLORS[index % RIVAL_COLORS.length];
export const PLAYER_COLOR = '#ffcb3d';

const LABEL_TO_STAGE = Object.fromEntries(Object.entries(STAGE_LABELS).map(([k, v]) => [v, k])) as Record<string, ProjectStage>;
/** Las vistas de competidores traen la etapa como texto: se vuelve a la etapa del motor. */
export const stageFromLabel = (label: string): ProjectStage => LABEL_TO_STAGE[label] ?? 'permisos';

/** Días → «12 d» / «3,5 meses». */
export const fmtDaysLeft = (d: number) => (d < 60 ? `${Math.round(d)} d` : `${fmtNum(d / 30.44, 1)} meses`);
