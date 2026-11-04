/**
 * Genera la grilla global de recursos (0,5° × 0,5°) y la geometría de países.
 *
 * Entradas (se descargan a tools/raw/ si faltan):
 *  - Natural Earth 1:50m (dominio público): países, regiones geográficas (montañas, desiertos, mesetas), ríos.
 *  - PB2002 (Bird 2003, vía fraxen/tectonicplates): límites de placas tectónicas.
 *  - packages/data/resources/anclas.yaml: puntos de referencia aproximados de sol, viento, lluvia y geotermia.
 *
 * Salidas (packages/data/generated/):
 *  - grid.bin   capas cuantizadas a uint8 + país (uint16) por celda
 *  - grid.json  metadatos (dimensiones, capas, rangos de cuantización, lista de países)
 *  - world.json polígonos de países simplificados para el render
 *
 * El modelo físico de cada capa está documentado en docs/RECURSOS.md.
 * Uso: npm run resources
 */
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parse } from 'yaml';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const RAW = join(ROOT, 'tools/raw');
const OUT = join(ROOT, 'packages/data/generated');

const SOURCES: Record<string, string> = {
  'ne_50m_admin_0_countries.geojson':
    'https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_admin_0_countries.geojson',
  'ne_50m_geography_regions_polys.geojson':
    'https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_geography_regions_polys.geojson',
  'ne_50m_rivers_lake_centerlines_scale_rank.geojson':
    'https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_rivers_lake_centerlines_scale_rank.geojson',
  'PB2002_boundaries.json':
    'https://raw.githubusercontent.com/fraxen/tectonicplates/master/GeoJSON/PB2002_boundaries.json',
};

async function ensureRaw() {
  mkdirSync(RAW, { recursive: true });
  for (const [file, url] of Object.entries(SOURCES)) {
    const p = join(RAW, file);
    if (existsSync(p)) continue;
    console.log('Descargando', url);
    const res = await fetch(url);
    if (!res.ok) throw new Error(`No se pudo descargar ${url}: ${res.status}`);
    writeFileSync(p, Buffer.from(await res.arrayBuffer()));
  }
}

// ---------------------------------------------------------------- grilla
const RES = 0.5;
const W = 360 / RES; // 720
const H = 180 / RES; // 360
const N = W * H;
const R_EARTH = 6371;
const latOf = (r: number) => 90 - (r + 0.5) * RES;
const lonOf = (c: number) => -180 + (c + 0.5) * RES;
const rowOf = (lat: number) => Math.min(H - 1, Math.max(0, Math.floor((90 - lat) / RES)));
const colOf = (lon: number) => (((Math.floor((lon + 180) / RES) % W) + W) % W);
const deg = Math.PI / 180;

function haversine(lat1: number, lon1: number, lat2: number, lon2: number) {
  const dLat = (lat2 - lat1) * deg;
  const dLon = (lon2 - lon1) * deg;
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(lat1 * deg) * Math.cos(lat2 * deg) * Math.sin(dLon / 2) ** 2;
  return 2 * R_EARTH * Math.asin(Math.min(1, Math.sqrt(a)));
}

type Ring = number[][];
type Polygon = Ring[];

function polygonsOf(geom: any): Polygon[] {
  if (!geom) return [];
  if (geom.type === 'Polygon') return [geom.coordinates];
  if (geom.type === 'MultiPolygon') return geom.coordinates;
  return [];
}

/** Rellena por scanline las celdas cuyo centro cae dentro del polígono (regla par-impar, con huecos). */
function rasterPolygon(poly: Polygon, set: (idx: number) => void) {
  let minLat = 90, maxLat = -90;
  for (const p of poly[0]) { minLat = Math.min(minLat, p[1]); maxLat = Math.max(maxLat, p[1]); }
  for (let r = rowOf(maxLat); r <= rowOf(minLat); r++) {
    const lat = latOf(r);
    const xs: number[] = [];
    for (const ring of poly) {
      for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
        const [x1, y1] = ring[j], [x2, y2] = ring[i];
        if ((y1 > lat) !== (y2 > lat)) xs.push(x1 + ((lat - y1) / (y2 - y1)) * (x2 - x1));
      }
    }
    xs.sort((a, b) => a - b);
    for (let k = 0; k + 1 < xs.length; k += 2) {
      const c0 = Math.ceil((xs[k] + 180) / RES - 0.5);
      const c1 = Math.floor((xs[k + 1] + 180) / RES - 0.5);
      for (let c = c0; c <= c1; c++) if (c >= 0 && c < W) set(r * W + c);
    }
  }
}

/** Marca las celdas por donde pasa una polilínea (muestreo cada 0,1°). */
function rasterLine(coords: number[][], set: (idx: number) => void) {
  for (let i = 1; i < coords.length; i++) {
    const [x1, y1] = coords[i - 1], [x2, y2] = coords[i];
    if (Math.abs(x2 - x1) > 180) continue; // cruce del antimeridiano
    const steps = Math.max(1, Math.ceil(Math.hypot(x2 - x1, y2 - y1) / 0.1));
    for (let s = 0; s <= steps; s++) {
      const t = s / steps;
      set(rowOf(y1 + (y2 - y1) * t) * W + colOf(x1 + (x2 - x1) * t));
    }
  }
}

/** Distancia (km) desde cada celda a la fuente más cercana (Dijkstra en grilla de 8 vecinos, envolvente en longitud). */
function distanceField(sources: Uint8Array): Float32Array {
  const dist = new Float32Array(N).fill(Infinity);
  const heap: number[] = []; // pares [dist, idx] aplanados
  const push = (d: number, i: number) => {
    heap.push(d, i);
    let k = heap.length / 2 - 1;
    while (k > 0) {
      const p = (k - 1) >> 1;
      if (heap[2 * p] <= heap[2 * k]) break;
      [heap[2 * p], heap[2 * k]] = [heap[2 * k], heap[2 * p]];
      [heap[2 * p + 1], heap[2 * k + 1]] = [heap[2 * k + 1], heap[2 * p + 1]];
      k = p;
    }
  };
  const pop = (): [number, number] => {
    const d = heap[0], i = heap[1];
    const lastIdx = heap.pop()!, lastDist = heap.pop()!;
    if (heap.length) {
      heap[0] = lastDist; heap[1] = lastIdx;
      let k = 0;
      const n = heap.length / 2;
      for (;;) {
        const l = 2 * k + 1, r = l + 1;
        let m = k;
        if (l < n && heap[2 * l] < heap[2 * m]) m = l;
        if (r < n && heap[2 * r] < heap[2 * m]) m = r;
        if (m === k) break;
        [heap[2 * m], heap[2 * k]] = [heap[2 * k], heap[2 * m]];
        [heap[2 * m + 1], heap[2 * k + 1]] = [heap[2 * k + 1], heap[2 * m + 1]];
        k = m;
      }
    }
    return [d, i];
  };
  for (let i = 0; i < N; i++) if (sources[i]) { dist[i] = 0; push(0, i); }
  const dy = RES * deg * R_EARTH;
  while (heap.length) {
    const [d, i] = pop();
    if (d > dist[i]) continue;
    const r = Math.floor(i / W), c = i % W;
    for (let a = -1; a <= 1; a++) {
      const rr = r + a;
      if (rr < 0 || rr >= H) continue;
      const dx = Math.cos(latOf(rr) * deg) * dy;
      for (let b = -1; b <= 1; b++) {
        if (!a && !b) continue;
        const j = rr * W + ((c + b + W) % W);
        const nd = d + Math.hypot(a * dy, b * dx);
        if (nd < dist[j]) { dist[j] = nd; push(nd, j); }
      }
    }
  }
  return dist;
}

/** Desenfoque de caja separable (radio en celdas), envolvente en longitud. */
function blur(src: Float32Array, radius: number): Float32Array {
  const tmp = new Float32Array(N), out = new Float32Array(N);
  for (let r = 0; r < H; r++) {
    for (let c = 0; c < W; c++) {
      let s = 0;
      for (let k = -radius; k <= radius; k++) s += src[r * W + ((c + k + W) % W)];
      tmp[r * W + c] = s / (2 * radius + 1);
    }
  }
  for (let r = 0; r < H; r++) {
    for (let c = 0; c < W; c++) {
      let s = 0, n = 0;
      for (let k = -radius; k <= radius; k++) {
        const rr = r + k;
        if (rr < 0 || rr >= H) continue;
        s += tmp[rr * W + c]; n++;
      }
      out[r * W + c] = s / n;
    }
  }
  return out;
}

/** Interpolación lineal por tramos sobre |lat|. */
function byLat(table: [number, number][], lat: number) {
  const a = Math.abs(lat);
  for (let i = 1; i < table.length; i++) {
    if (a <= table[i][0]) {
      const [x0, y0] = table[i - 1], [x1, y1] = table[i];
      return y0 + ((a - x0) / (x1 - x0)) * (y1 - y0);
    }
  }
  return table[table.length - 1][1];
}

// Líneas base por latitud (supuestos documentados en docs/RECURSOS.md).
const GHI_BASE: [number, number][] = [[0, 4.7], [10, 5.1], [20, 5.6], [25, 5.6], [30, 5.2], [35, 4.7], [40, 4.2], [45, 3.7], [50, 3.1], [55, 2.7], [60, 2.3], [70, 1.9], [90, 1.8]];
const WIND_LAND_BASE: [number, number][] = [[0, 4.2], [10, 5.0], [20, 5.5], [30, 6.0], [40, 6.5], [50, 6.8], [60, 6.5], [90, 6.5]];
const WIND_SEA_N: [number, number][] = [[0, 5.5], [5, 6.0], [10, 7.0], [25, 7.5], [32, 7.0], [40, 8.5], [50, 10.0], [60, 10.0], [90, 8.5]];
const WIND_SEA_S: [number, number][] = [[0, 5.5], [5, 6.0], [10, 7.0], [25, 7.5], [32, 7.5], [40, 9.5], [50, 11.0], [60, 11.0], [90, 9.0]];
const RAIN_BASE: [number, number][] = [[0, 2000], [10, 1500], [20, 700], [25, 400], [30, 500], [40, 750], [50, 650], [60, 500], [70, 300], [90, 150]];

type Anchor = { name: string; lat: number; lon: number; v: (number | null)[]; r: number };

/** Ajusta un campo base con los residuos de las anclas (núcleo gaussiano; lejos de anclas vuelve a la base). */
function applyAnchors(field: Float32Array, mask: Uint8Array | null, anchors: Anchor[], k: number, w0 = 0.15) {
  const residuals = anchors
    .filter((a) => a.v[k] != null)
    .map((a) => ({ ...a, res: (a.v[k] as number) - field[rowOf(a.lat) * W + colOf(a.lon)] }));
  const out = new Float32Array(field);
  for (let r = 0; r < H; r++) {
    const lat = latOf(r);
    for (let c = 0; c < W; c++) {
      const i = r * W + c;
      if (mask && !mask[i]) continue;
      const lon = lonOf(c);
      let sw = w0, s = 0;
      for (const a of residuals) {
        if (Math.abs(a.lat - lat) * 111 > a.r * 3) continue;
        const d = haversine(lat, lon, a.lat, a.lon);
        if (d > a.r * 3) continue;
        const w = Math.exp(-((d / a.r) ** 2));
        sw += w; s += w * a.res;
      }
      out[i] = field[i] + s / sw;
    }
  }
  return out;
}

async function main() {
  await ensureRaw();
  const read = (f: string) => JSON.parse(readFileSync(join(RAW, f), 'utf8'));
  const anclas = parse(readFileSync(join(ROOT, 'packages/data/resources/anclas.yaml'), 'utf8'));
  const R0 = anclas.radio_defecto_km as number;
  const landAnchors: Anchor[] = anclas.tierra.map((a: any[]) => ({ name: a[0], lat: a[1], lon: a[2], v: [a[3], a[4], a[5]], r: a[6] ?? R0 }));
  const seaAnchors: Anchor[] = anclas.mar.map((a: any[]) => ({ name: a[0], lat: a[1], lon: a[2], v: [a[3]], r: a[4] ?? R0 }));
  const geoAnchors = anclas.geotermia.map((a: any[]) => ({ name: a[0], lat: a[1], lon: a[2], v: a[3], r: a[4] }));

  // ---- países
  console.log('Rasterizando países…');
  const countriesGeo = read('ne_50m_admin_0_countries.geojson');
  const country = new Uint16Array(N);
  const countries: { id: number; code: string; iso3: string; nombre: string; continente: string; poblacion: number; pib_musd: number; lat: number; lon: number; celdas: number }[] = [];
  const worldPolys: { id: number; code: string; polys: number[][][] }[] = [];
  countriesGeo.features.forEach((f: any, k: number) => {
    const p = f.properties;
    const id = k + 1;
    const polys = polygonsOf(f.geometry);
    let cells = 0;
    for (const poly of polys) rasterPolygon(poly, (i) => { if (!country[i]) cells++; country[i] = id; });
    // Países muy pequeños: al menos la celda de su punto de etiqueta
    const lx = p.LABEL_X ?? polys[0]?.[0]?.[0]?.[0] ?? 0, ly = p.LABEL_Y ?? polys[0]?.[0]?.[0]?.[1] ?? 0;
    if (cells === 0) { const i = rowOf(ly) * W + colOf(lx); if (!country[i]) { country[i] = id; cells = 1; } }
    countries.push({ id, code: p.ADM0_A3, iso3: p.ISO_A3, nombre: p.NAME_ES ?? p.NAME, continente: p.CONTINENT, poblacion: p.POP_EST, pib_musd: p.GDP_MD, lat: +ly.toFixed(2), lon: +lx.toFixed(2), celdas: cells });
    // geometría simplificada para el render: redondeo a 0,02° y descarte de puntos repetidos
    const simp = polys.map((poly) => poly.map((ring) => {
      const out: number[] = [];
      let px = NaN, py = NaN;
      for (const [x, y] of ring) {
        const qx = Math.round(x * 50) / 50, qy = Math.round(y * 50) / 50;
        if (qx === px && qy === py) continue;
        out.push(qx, qy); px = qx; py = qy;
      }
      return out;
    }).filter((r) => r.length >= 6));
    worldPolys.push({ id, code: p.ADM0_A3, polys: simp.filter((p) => p.length) });
  });
  const land = new Uint8Array(N);
  for (let i = 0; i < N; i++) land[i] = country[i] ? 1 : 0;

  // ---- distancia a la costa (km): positiva en tierra y en mar
  console.log('Distancias…');
  const coast = new Uint8Array(N);
  for (let r = 0; r < H; r++) for (let c = 0; c < W; c++) {
    const i = r * W + c;
    const n = [r > 0 ? i - W : i, r < H - 1 ? i + W : i, r * W + ((c + 1) % W), r * W + ((c - 1 + W) % W)];
    if (n.some((j) => land[j] !== land[i])) coast[i] = 1;
  }
  const dCoast = distanceField(coast);

  // ---- placas
  const plates = read('PB2002_boundaries.json');
  const pbAll = new Uint8Array(N), pbSub = new Uint8Array(N);
  for (const f of plates.features) {
    const lines = f.geometry.type === 'LineString' ? [f.geometry.coordinates] : f.geometry.coordinates;
    for (const l of lines) {
      rasterLine(l, (i) => (pbAll[i] = 1));
      if (f.properties.Type === 'subduction') rasterLine(l, (i) => (pbSub[i] = 1));
    }
  }
  const dPlate = distanceField(pbAll);
  const dSub = distanceField(pbSub);

  // ---- relieve y desiertos
  console.log('Relieve, desiertos, ríos…');
  const regions = read('ne_50m_geography_regions_polys.geojson');
  const mtn = new Float32Array(N), desert = new Float32Array(N);
  const HIGH_PLATEAUS = new Set(['PLATEAU OF TIBET', 'ALTIPLANO', 'ETHIOPIAN HIGHLANDS', 'PAMIRS', 'Polar Plateau']);
  for (const f of regions.features) {
    const cla = f.properties.FEATURECLA, name = f.properties.NAME;
    let v = 0;
    if (cla === 'Range/mtn') v = 1;
    else if (cla === 'Plateau') v = HIGH_PLATEAUS.has(name) ? 1 : 0.35;
    else if (cla === 'Foothills') v = 0.4;
    if (v) for (const poly of polygonsOf(f.geometry)) rasterPolygon(poly, (i) => (mtn[i] = Math.max(mtn[i], v)));
    if (cla === 'Desert') for (const poly of polygonsOf(f.geometry)) rasterPolygon(poly, (i) => (desert[i] = 1));
  }
  // Arcos volcánicos y cordilleras costeras sobre zonas de subducción
  for (let i = 0; i < N; i++) if (land[i] && dSub[i] < 250) mtn[i] = Math.max(mtn[i], 0.55 * (1 - dSub[i] / 250) + 0.2);
  const relief = blur(mtn, 1);
  const desertB = blur(desert, 2);

  const rivers = read('ne_50m_rivers_lake_centerlines_scale_rank.geojson');
  const riv = new Float32Array(N);
  for (const f of rivers.features) {
    const w = Math.max(0.25, 1 - (f.properties.scalerank ?? 6) / 10);
    const lines = f.geometry?.type === 'LineString' ? [f.geometry.coordinates] : f.geometry?.coordinates ?? [];
    for (const l of lines) rasterLine(l, (i) => (riv[i] = Math.max(riv[i], w)));
  }
  const rivB = blur(riv, 2);
  let rivMax = 0; for (let i = 0; i < N; i++) rivMax = Math.max(rivMax, rivB[i]);

  // ---- campos base
  console.log('Modelos de capas…');
  const ghi0 = new Float32Array(N), wl0 = new Float32Array(N), ws0 = new Float32Array(N), rain0 = new Float32Array(N);
  for (let r = 0; r < H; r++) {
    const lat = latOf(r);
    for (let c = 0; c < W; c++) {
      const i = r * W + c;
      const cont = Math.min(1, dCoast[i] / 1500);
      ghi0[i] = byLat(GHI_BASE, lat) + 0.7 * desertB[i] + 0.5 * relief[i] * (Math.abs(lat) < 40 ? 1 : 0.3);
      wl0[i] = byLat(WIND_LAND_BASE, lat) + 0.9 * Math.exp(-dCoast[i] / 40) + 0.5 * relief[i] + 0.3 * desertB[i] - 0.6 * cont * (Math.abs(lat) < 25 ? 1 : 0);
      ws0[i] = byLat(lat >= 0 ? WIND_SEA_N : WIND_SEA_S, lat) - 1.0 * Math.exp(-dCoast[i] / 30);
      rain0[i] = byLat(RAIN_BASE, lat) * (1 - 0.85 * desertB[i]) * (1 - (Math.abs(lat) > 30 ? 0.45 : 0.25) * cont) * (1 + 0.35 * relief[i]);
    }
  }
  const ghi = applyAnchors(ghi0, land, landAnchors, 0);
  const windLand = applyAnchors(wl0, land, landAnchors, 1);
  const rain = applyAnchors(rain0, land, landAnchors, 2);
  const sea = new Uint8Array(N); for (let i = 0; i < N; i++) sea[i] = land[i] ? 0 : 1;
  const windSea = applyAnchors(ws0, sea, seaAnchors, 0);

  const L = {
    ghi: new Float32Array(N), dni: new Float32Array(N), viento_tierra: new Float32Array(N), viento_mar: new Float32Array(N),
    geotermia: new Float32Array(N), hidro: new Float32Array(N), biomasa: new Float32Array(N), lluvia: new Float32Array(N),
    temperatura: new Float32Array(N), relieve: new Float32Array(N), dist_costa_km: new Float32Array(N),
  };
  const clamp = (x: number, a: number, b: number) => Math.min(b, Math.max(a, x));
  for (let r = 0; r < H; r++) {
    const lat = latOf(r);
    for (let c = 0; c < W; c++) {
      const i = r * W + c;
      const lon = lonOf(c);
      L.dist_costa_km[i] = dCoast[i];
      L.relieve[i] = relief[i];
      if (!land[i]) { L.viento_mar[i] = clamp(windSea[i], 3, 12.5); continue; }
      const g = clamp(ghi[i], 0.8, 7.6);
      const p = clamp(rain[i], 0, 6000);
      L.ghi[i] = g;
      L.lluvia[i] = p;
      // DNI: proporcional a GHI y a la claridad del cielo (más seco ⇒ más directo)
      const k = 1.4 - 0.75 * clamp((p - 200) / 2200, 0, 1);
      L.dni[i] = clamp(g * k, 0.8, 10.5);
      L.viento_tierra[i] = clamp(windLand[i], 2.5, 11.5);
      // Temperatura media anual (°C): latitud + altitud (relieve)
      const contT = Math.min(1, dCoast[i] / 1500);
      let t = 27 - 0.0095 * Math.max(0, Math.abs(lat) - 10) ** 2 - 12 * relief[i];
      if (Math.abs(lat) > 40) t += 4 * Math.exp(-dCoast[i] / 300) - 10 * contT;
      if (lat < -60) t = -30;
      L.temperatura[i] = clamp(t, -30, 30);
      // Geotermia (mW/m²): base continental + límites de placas + arco volcánico + zonas conocidas
      let q = 62 + 55 * Math.exp(-dPlate[i] / 120) + 45 * Math.exp(-(((dSub[i] - 170) / 110) ** 2));
      for (const a of geoAnchors) {
        if (Math.abs(a.lat - lat) * 111 > a.r * 3) continue;
        const d = haversine(lat, lon, a.lat, a.lon);
        q = Math.max(q, 62 + (a.v - 62) * Math.exp(-((d / a.r) ** 2)));
      }
      L.geotermia[i] = clamp(q, 40, 260);
      // Hidro (índice 0–100): lluvia × relieve × ríos; congelado reduce
      const wet = clamp(p / 2500, 0, 1);
      const rv = rivMax ? rivB[i] / rivMax : 0;
      let h = 180 * wet ** 0.7 * (0.25 + 0.75 * relief[i]) * (0.5 + 0.5 * Math.sqrt(rv));
      if (t < -5) h *= 0.25;
      L.hidro[i] = clamp(h, 0, 100);
      // Biomasa: modelo de Miami (Lieth 1975), NPP en g de materia seca/m²/año
      const nT = 3000 / (1 + Math.exp(1.315 - 0.119 * t));
      const nP = 3000 * (1 - Math.exp(-0.000664 * p));
      L.biomasa[i] = t < -10 ? 0 : clamp(Math.min(nT, nP), 0, 3000);
    }
  }

  // ---- cuantización y escritura
  mkdirSync(OUT, { recursive: true });
  const ranges: Record<string, [number, number]> = {
    ghi: [0, 8], dni: [0, 11], viento_tierra: [0, 12.75], viento_mar: [0, 12.75], geotermia: [0, 255], hidro: [0, 100],
    biomasa: [0, 3060], lluvia: [0, 6120], temperatura: [-31.75, 32], relieve: [0, 1], dist_costa_km: [0, 2550],
  };
  const ids = Object.keys(L) as (keyof typeof L)[];
  const buf = Buffer.alloc(N * ids.length + N * 2);
  const meta: any = { version: 1, resolucion_grados: RES, ancho: W, alto: H, origen: 'lat 90 → -90 por filas, lon -180 → 180 por columnas; centro de celda', capas: [], pais: { offset: N * ids.length, tipo: 'uint16' } };
  ids.forEach((id, k) => {
    const [a, b] = ranges[id];
    const off = k * N;
    for (let i = 0; i < N; i++) buf[off + i] = Math.round(clamp((L[id][i] - a) / (b - a), 0, 1) * 255);
    meta.capas.push({ id, offset: off, min: a, max: b });
  });
  for (let i = 0; i < N; i++) buf.writeUInt16LE(country[i], N * ids.length + i * 2);
  meta.paises = countries;
  writeFileSync(join(OUT, 'grid.bin'), buf);
  writeFileSync(join(OUT, 'grid.json'), JSON.stringify(meta));
  writeFileSync(join(OUT, 'world.json'), JSON.stringify(worldPolys));

  // ---- resumen de control
  const at = (id: keyof typeof L, lat: number, lon: number) => +L[id][rowOf(lat) * W + colOf(lon)].toFixed(1);
  for (const [n, la, lo] of [['Penonomé', 8.6, -80.3], ['Chiriquí', 8.6, -82.4], ['Andes Perú', -12, -75], ['Noruega', 61, 7], ['Yakutsk', 62, 129.7], ['Ciudad de Panamá', 8.98, -79.52], ['Sahara', 24, 10], ['Berlín', 52.5, 13.4], ['Islandia', 64.8, -18], ['Amazonas', -3, -60]] as const) {
    console.log(n.padEnd(18), 'GHI', at('ghi', la, lo), 'viento', at('viento_tierra', la, lo), 'geo', at('geotermia', la, lo), 'hidro', at('hidro', la, lo), 'NPP', at('biomasa', la, lo), 'lluvia', at('lluvia', la, lo), 'T', at('temperatura', la, lo));
  }
  const pct = (id: keyof typeof L) => { const v = [] as number[]; for (let i = 0; i < N; i++) if (land[i] && latOf(Math.floor(i / W)) > -60) v.push(L[id][i]); v.sort((a, b) => a - b); return [0.1, 0.5, 0.9, 0.99].map((q) => +v[Math.floor(q * (v.length - 1))].toFixed(1)); };
  for (const id of ['ghi', 'viento_tierra', 'geotermia', 'hidro', 'biomasa', 'lluvia', 'temperatura'] as const) console.log('p10/50/90/99', id, pct(id));
  console.log('Listo:', (buf.length / 1e6).toFixed(1), 'MB grilla,', countries.length, 'países');
}

main().catch((e) => { console.error(e); process.exit(1); });
