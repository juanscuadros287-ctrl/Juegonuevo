import type { SimData } from '../data/types';
import type { ResourceGrid } from '../world/grid';

/**
 * Lo que el motor necesita además del estado: datos (YAML validados) y, si está cargada, la grilla
 * de recursos. No se guarda en la partida: se reconstruye al cargar.
 * Sin `grid` el juego avanza igual; solo `createProject` (que lee el recurso de la celda) se rechaza.
 */
export interface SimContext {
  data: SimData;
  grid?: ResourceGrid;
}
