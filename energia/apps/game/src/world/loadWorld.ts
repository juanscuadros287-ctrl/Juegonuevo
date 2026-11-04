import { ResourceGrid, type GridMeta } from '@voltaje/sim';

/** Polígonos de un país: lista de polígonos, cada uno lista de anillos [lon, lat, lon, lat, …]. */
export interface CountryShape { id: number; code: string; polys: number[][][] }

export interface World { grid: ResourceGrid; shapes: CountryShape[] }

let cache: Promise<World> | null = null;

export function loadWorld(): Promise<World> {
  cache ??= (async () => {
    const [meta, bin, shapes] = await Promise.all([
      fetch('grid.json').then((r) => r.json() as Promise<GridMeta>),
      fetch('grid.bin').then((r) => r.arrayBuffer()),
      fetch('world.json').then((r) => r.json() as Promise<CountryShape[]>),
    ]);
    return { grid: new ResourceGrid(meta, bin), shapes };
  })();
  return cache;
}
