import type * as THREE from 'three';
import type { Builder } from './kit';

export type PlantKind =
  | 'solar_fv' | 'csp' | 'eolica_tierra' | 'eolica_mar' | 'geotermica' | 'hidro_pasada' | 'hidro_embalse' | 'hidro_bombeo'
  | 'biomasa' | 'biogas' | 'nuclear' | 'smr' | 'gas' | 'carbon' | 'petroleo' | 'baterias' | 'hidrogeno' | 'subestacion'
  | 'linea_transmision' | 'eficiencia_industrial';

export type PlantStage = 'prospeccion' | 'estudios' | 'construccion' | 'operacion' | 'falla' | 'abandonado';

export interface PlantVisualState {
  kind: PlantKind;
  /** Escala la cantidad de elementos (filas de paneles, nº de turbinas, unidades). */
  capacityMw: number;
  stage: PlantStage;
  /** 0..1 avance de obra (solo en 'construccion'). */
  progress: number;
  /** Variación determinista de la disposición. */
  seed: number;
}

export type DetailLevel = 0 | 1 | 2;
export type PinFamily = 'solar' | 'viento' | 'agua' | 'geo' | 'bio' | 'nuclear' | 'fosil' | 'almacenamiento' | 'red' | 'eficiencia';
export type SurveyKind = 'mast' | 'solar' | 'drill' | 'gauge' | 'buoy' | 'survey';

/** Contexto que recibe cada constructor de modelo. */
export interface Ctx {
  s: PlantVisualState;
  /** Aleatorio de disposición (determinista por seed + tipo). */
  rng: () => number;
  /** Etapa de obra. */
  building: boolean;
  /** Operación o falla (la planta funciona o funcionaba). */
  running: boolean;
  /** Avance de una fase de obra: (progress - a) / (b - a) acotado a 0..1; 1 si la obra terminó. */
  ph(a: number, b: number): number;
  /** Cantidad de elementos según capacidad: round(mw / porUnidad) acotado. */
  count(perUnit: number, min: number, max: number): number;
  /** Punto (espacio de la planta) donde se muestra la falla: humo y luz roja. */
  hot?: THREE.Vector3;
}

export interface PlantDef {
  pin: PinFamily;
  terrain?: 'land' | 'sea';
  /** Instrumento de prospección/estudios. */
  survey: SurveyKind;
  /** Posición [x, z, giro] de la subestación de conexión; null = sin subestación propia. */
  sub: [number, number, number] | null;
  /** Radio de terreno despejado en obra. */
  clear?: number;
  /** Lo que existe en todas las etapas (p. ej. la fábrica en eficiencia industrial). */
  base?: (b: Builder, c: Ctx) => void;
  /** Construye la planta (en obra usa c.ph para mostrar el avance). */
  build: (b: Builder, c: Ctx) => void;
  /** Capacidad típica en MW (vista previa y valor por defecto). */
  typicalMw: number;
  label: string;
}
