/**
 * Grilla global de recursos (generada por tools/build-resources.ts).
 * Decodificación pura a partir de los bytes y los metadatos; sin dependencias de navegador.
 */
export interface GridLayerMeta { id: string; offset: number; min: number; max: number }
export interface GridCountry {
  id: number; code: string; iso3: string; nombre: string; continente: string;
  poblacion: number; pib_musd: number; lat: number; lon: number; celdas: number;
}
export interface GridMeta {
  version: number;
  resolucion_grados: number;
  ancho: number;
  alto: number;
  capas: GridLayerMeta[];
  pais: { offset: number; tipo: 'uint16' };
  paises: GridCountry[];
}

export interface CellInfo {
  index: number;
  row: number;
  col: number;
  lat: number; // centro de la celda
  lon: number;
  land: boolean;
  country: GridCountry | null;
  values: Record<string, number>;
}

export class ResourceGrid {
  readonly width: number;
  readonly height: number;
  readonly res: number;
  private readonly bytes: Uint8Array;
  private readonly countryIds: Uint16Array;
  private readonly layers = new Map<string, GridLayerMeta>();
  private readonly countriesById = new Map<number, GridCountry>();
  readonly countriesByCode = new Map<string, GridCountry>();

  constructor(readonly meta: GridMeta, buffer: ArrayBuffer | Uint8Array) {
    this.bytes = buffer instanceof Uint8Array ? buffer : new Uint8Array(buffer);
    this.width = meta.ancho;
    this.height = meta.alto;
    this.res = meta.resolucion_grados;
    const n = this.width * this.height;
    const expected = meta.capas.length * n + 2 * n;
    if (this.bytes.byteLength !== expected) throw new Error(`Grilla con tamaño inesperado: ${this.bytes.byteLength} ≠ ${expected}`);
    // copia alineada para leer uint16 (little-endian)
    const raw = this.bytes.subarray(meta.pais.offset, meta.pais.offset + 2 * n);
    this.countryIds = new Uint16Array(n);
    for (let i = 0; i < n; i++) this.countryIds[i] = raw[2 * i] | (raw[2 * i + 1] << 8);
    for (const l of meta.capas) this.layers.set(l.id, l);
    for (const c of meta.paises) { this.countriesById.set(c.id, c); this.countriesByCode.set(c.code, c); }
  }

  get layerIds(): string[] { return [...this.layers.keys()]; }

  indexOf(lat: number, lon: number): number {
    const r = Math.min(this.height - 1, Math.max(0, Math.floor((90 - lat) / this.res)));
    const c = (((Math.floor((lon + 180) / this.res)) % this.width) + this.width) % this.width;
    return r * this.width + c;
  }

  valueAt(layer: string, index: number): number {
    const l = this.layers.get(layer);
    if (!l) throw new Error(`Capa desconocida: ${layer}`);
    return l.min + (this.bytes[l.offset + index] / 255) * (l.max - l.min);
  }

  /** Byte cuantizado (0–255) para pintar texturas rápido. */
  rawLayer(layer: string): Uint8Array {
    const l = this.layers.get(layer);
    if (!l) throw new Error(`Capa desconocida: ${layer}`);
    return this.bytes.subarray(l.offset, l.offset + this.width * this.height);
  }

  countryIdAt(index: number): number { return this.countryIds[index]; }
  countryById(id: number): GridCountry | null { return this.countriesById.get(id) ?? null; }

  cell(lat: number, lon: number): CellInfo {
    const index = this.indexOf(lat, lon);
    const row = Math.floor(index / this.width), col = index % this.width;
    const cid = this.countryIds[index];
    const values: Record<string, number> = {};
    for (const id of this.layers.keys()) values[id] = this.valueAt(id, index);
    return {
      index, row, col,
      lat: 90 - (row + 0.5) * this.res,
      lon: -180 + (col + 0.5) * this.res,
      land: cid !== 0,
      country: this.countriesById.get(cid) ?? null,
      values,
    };
  }

  /** Celdas de un país (índices). */
  cellsOfCountry(code: string): number[] {
    const c = this.countriesByCode.get(code);
    if (!c) return [];
    const out: number[] = [];
    for (let i = 0; i < this.countryIds.length; i++) if (this.countryIds[i] === c.id) out.push(i);
    return out;
  }
}
