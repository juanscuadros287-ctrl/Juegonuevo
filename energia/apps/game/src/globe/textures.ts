import * as THREE from 'three';
import type { ResourceGrid } from '@voltaje/sim';
import type { LayerDef } from '@voltaje/data';
import type { CountryShape } from '../world/loadWorld';
import { theme } from '../theme/theme';

const hex = (c: string) => [parseInt(c.slice(1, 3), 16), parseInt(c.slice(3, 5), 16), parseInt(c.slice(5, 7), 16)];
const mix = (a: number[], b: number[], t: number) => a.map((x, i) => x + (b[i] - x) * t);

function countryPath(shapes: CountryShape[], w: number, h: number): Path2D {
  const path = new Path2D();
  for (const s of shapes) for (const poly of s.polys) for (const ring of poly) {
    for (let i = 0; i < ring.length; i += 2) {
      const x = ((ring[i] + 180) / 360) * w, y = ((90 - ring[i + 1]) / 180) * h;
      if (i === 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    path.closePath();
  }
  return path;
}

/** Imagen de la grilla (1 píxel por celda) con un color por celda. */
function gridImage(grid: ResourceGrid, color: (i: number) => number[] | null): HTMLCanvasElement {
  const c = document.createElement('canvas');
  c.width = grid.width; c.height = grid.height;
  const ctx = c.getContext('2d')!;
  const img = ctx.createImageData(grid.width, grid.height);
  for (let i = 0; i < grid.width * grid.height; i++) {
    const col = color(i);
    if (!col) continue;
    img.data[i * 4] = col[0]; img.data[i * 4 + 1] = col[1]; img.data[i * 4 + 2] = col[2]; img.data[i * 4 + 3] = 255;
  }
  ctx.putImageData(img, 0, 0);
  return c;
}

/** Desenfoque de caja 3×3 aplicado `passes` veces (suaviza los escalones de la grilla). */
function boxBlur(canvas: HTMLCanvasElement, passes: number) {
  const ctx = canvas.getContext('2d')!;
  const { width: w, height: h } = canvas;
  const img = ctx.getImageData(0, 0, w, h);
  let src = img.data;
  for (let p = 0; p < passes; p++) {
    const out = new Uint8ClampedArray(src.length);
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      for (let ch = 0; ch < 4; ch++) {
        let s = 0, n = 0;
        for (let dy = -1; dy <= 1; dy++) {
          const yy = y + dy;
          if (yy < 0 || yy >= h) continue;
          for (let dx = -1; dx <= 1; dx++) { s += src[(yy * w + ((x + dx + w) % w)) * 4 + ch]; n++; }
        }
        out[(y * w + x) * 4 + ch] = s / n;
      }
    }
    src = out;
  }
  img.data.set(src);
  ctx.putImageData(img, 0, 0);
}

/** Mapa base: océano con profundidad aproximada y tierra coloreada por bioma (lluvia, temperatura, relieve). */
export function buildBaseTexture(grid: ResourceGrid, shapes: CountryShape[], width = 4096): THREE.CanvasTexture {
  const g = theme.globe;
  const W = width, H = width / 2;
  const canvas = document.createElement('canvas');
  canvas.width = W; canvas.height = H;
  const ctx = canvas.getContext('2d')!;
  ctx.imageSmoothingEnabled = true;
  ctx.imageSmoothingQuality = 'high';

  const deep = hex(g.oceanDeep), shallow = hex(g.oceanShallow);
  const ocean = gridImage(grid, (i) => {
    const d = grid.valueAt('dist_costa_km', i);
    return mix(shallow, deep, Math.min(1, Math.sqrt(d / 600)));
  });
  boxBlur(ocean, 2);
  ctx.drawImage(ocean, 0, 0, W, H);

  const C = { ice: hex(g.ice), desert: hex(g.desert), steppe: hex(g.steppe), grass: hex(g.grass), forest: hex(g.forest), rain: hex(g.rainforest), mtn: hex(g.mountain) };
  const biome = gridImage(grid, (i) => {
    const t = grid.valueAt('temperatura', i), p = grid.valueAt('lluvia', i), rel = grid.valueAt('relieve', i);
    let col: number[];
    if (t < -8) col = C.ice;
    else if (p < 200) col = C.desert;
    else if (p < 450) col = mix(C.desert, C.steppe, (p - 200) / 250);
    else if (p < 800) col = mix(C.steppe, C.grass, (p - 450) / 350);
    else if (p < 1600) col = mix(C.grass, C.forest, (p - 800) / 800);
    else col = mix(C.forest, C.rain, Math.min(1, (p - 1600) / 900));
    if (t < 0 && t >= -8) col = mix(col, C.ice, (-t) / 10);
    return mix(col, C.mtn, Math.min(0.55, rel * 0.6));
  });
  // Extiende el color de tierra hacia el mar para que el recorte por la costa real no deje huecos
  const bctx = biome.getContext('2d')!;
  bctx.globalCompositeOperation = 'destination-over';
  for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [-1, -1]]) bctx.drawImage(biome, dx, dy);

  ctx.save();
  ctx.clip(countryPath(shapes, W, H), 'nonzero');
  ctx.drawImage(biome, 0, 0, W, H);
  ctx.restore();

  const tex = new THREE.CanvasTexture(canvas);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = 4;
  tex.generateMipmaps = false;
  tex.minFilter = THREE.LinearFilter;
  return tex;
}

/** Máscara tierra (blanco) / mar (negro) a alta resolución, para recortar capas en la costa real. */
export function buildLandMask(shapes: CountryShape[], width = 4096): THREE.CanvasTexture {
  const W = width, H = width / 2;
  const canvas = document.createElement('canvas');
  canvas.width = W; canvas.height = H;
  const ctx = canvas.getContext('2d')!;
  ctx.fillStyle = '#000'; ctx.fillRect(0, 0, W, H);
  ctx.fillStyle = '#fff';
  ctx.fill(countryPath(shapes, W, H), 'nonzero');
  const tex = new THREE.CanvasTexture(canvas);
  tex.generateMipmaps = false;
  tex.minFilter = THREE.LinearFilter;
  return tex;
}

/** Textura de una capa de recurso con su rampa de color. Las celdas no aplicables se rellenan con vecinas. */
export function buildLayerTexture(grid: ResourceGrid, layer: LayerDef): THREE.DataTexture {
  const w = grid.width, h = grid.height, n = w * h;
  const ramp = layer.rampa.map(hex);
  const [lo, hi] = layer.rango;
  const value = new Float32Array(n).fill(NaN);
  for (let i = 0; i < n; i++) {
    const land = grid.countryIdAt(i) !== 0;
    if ((layer.aplica === 'tierra') !== land) continue;
    if (layer.aplica === 'tierra' && grid.valueAt('temperatura', i) <= -29 && layer.id !== 'temperatura') continue; // Antártida
    value[i] = grid.valueAt(layer.id, i);
  }
  // dilatación: 3 pasadas
  for (let pass = 0; pass < 3; pass++) {
    const copy = value.slice();
    for (let i = 0; i < n; i++) {
      if (!Number.isNaN(copy[i])) continue;
      const r = Math.floor(i / w), c = i % w;
      let s = 0, k = 0;
      for (const j of [r > 0 ? i - w : -1, r < h - 1 ? i + w : -1, r * w + ((c + 1) % w), r * w + ((c - 1 + w) % w)]) {
        if (j >= 0 && !Number.isNaN(copy[j])) { s += copy[j]; k++; }
      }
      if (k) value[i] = s / k;
    }
  }
  const data = new Uint8Array(n * 4);
  for (let r = 0; r < h; r++) {
    for (let c = 0; c < w; c++) {
      const i = r * w + c;
      const o = ((h - 1 - r) * w + c) * 4; // DataTexture: fila 0 = sur
      const v = value[i];
      if (Number.isNaN(v)) continue;
      const t = Math.min(1, Math.max(0, (v - lo) / (hi - lo))) * (ramp.length - 1);
      const k = Math.min(ramp.length - 2, Math.floor(t));
      const col = mix(ramp[k], ramp[k + 1], t - k);
      data[o] = col[0]; data[o + 1] = col[1]; data[o + 2] = col[2]; data[o + 3] = 255;
    }
  }
  const tex = new THREE.DataTexture(data, w, h, THREE.RGBAFormat);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.magFilter = THREE.LinearFilter;
  tex.minFilter = THREE.LinearFilter;
  tex.wrapS = THREE.RepeatWrapping;
  tex.needsUpdate = true;
  return tex;
}

/** Color de la rampa para un valor (para leyendas y la ficha). */
export function rampCss(layer: LayerDef): string {
  return `linear-gradient(90deg, ${layer.rampa.join(', ')})`;
}
