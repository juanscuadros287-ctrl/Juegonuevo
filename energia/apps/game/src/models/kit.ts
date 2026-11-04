/**
 * Kit de construcción de modelos: geometrías y materiales compartidos (cacheados a nivel de módulo),
 * un Builder que acumula "piezas" (geometría unitaria + transformación + color) y al final las agrupa
 * en InstancedMesh por (geometría, material). Así una planta completa son pocas llamadas de dibujo.
 */
import * as THREE from 'three';
import { mergeGeometries } from 'three/examples/jsm/utils/BufferGeometryUtils.js';
import { theme } from '../theme/theme';

export const PAL = theme.models;
type StrKeys<T> = { [K in keyof T]: T[K] extends string ? K : never }[keyof T];
/** Color: clave de la paleta (theme.models) o hex '#rrggbb'. */
export type Col = StrKeys<typeof PAL> | `#${string}`;

/** Altura del terreno (cara superior de la base) en unidades locales. */
export const Y0 = 0.02;

// ---------------------------------------------------------------- rng determinista
export function makeRng(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
export function hashStr(s: string): number {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 16777619);
  return h >>> 0;
}

// ---------------------------------------------------------------- geometrías compartidas
const Yax = new THREE.Vector3(0, 1, 0);

function beamGeo(a: THREE.Vector3, b: THREE.Vector3, t: number): THREE.BufferGeometry {
  const d = b.clone().sub(a), len = d.length();
  const g = new THREE.BoxGeometry(t, len, t).translate(0, len / 2, 0);
  g.applyQuaternion(new THREE.Quaternion().setFromUnitVectors(Yax, d.normalize()));
  return g.translate(a.x, a.y, a.z);
}

/** Celosía de 4 patas, altura 1, semiancho `base` abajo y `top` arriba. */
function latticeGeo(base: number, top: number, levels: number, t: number, diag = true): THREE.BufferGeometry {
  const parts: THREE.BufferGeometry[] = [];
  const corner = (k: number, y: number) => {
    const hw = base + (top - base) * y;
    const sx = k === 0 || k === 3 ? -1 : 1, sz = k < 2 ? -1 : 1;
    return new THREE.Vector3(sx * hw, y, sz * hw);
  };
  for (let k = 0; k < 4; k++) parts.push(beamGeo(corner(k, 0), corner(k, 1), t));
  for (let j = 0; j <= levels; j++) {
    const y0 = j / levels;
    for (let k = 0; k < 4; k++) {
      const k2 = (k + 1) % 4;
      if (j > 0) parts.push(beamGeo(corner(k, y0), corner(k2, y0), t * 0.7));
      if (diag && j < levels) {
        const y1 = (j + 1) / levels;
        parts.push(beamGeo(corner(k, y0), corner(k2, y1), t * 0.5));
        parts.push(beamGeo(corner(k2, y0), corner(k, y1), t * 0.5));
      }
    }
  }
  return mergeGeometries(parts.map((g) => g.toNonIndexed()));
}

/** Cabeza de torre de alta tensión (brazos + aisladores), en el marco de una torre de altura 1. */
export const PYLON = {
  arms: [{ y: 0.68, w: 0.36 }, { y: 0.84, w: 0.28 }],
  insulator: 0.07,
  /** Puntos de enganche de conductores (x, y) y del cable de guarda. */
  attach: [[-0.36, 0.61], [0.36, 0.61], [-0.28, 0.77], [0.28, 0.77], [0, 1.02]] as [number, number][],
};
function pylonHeadGeo(): THREE.BufferGeometry {
  const parts: THREE.BufferGeometry[] = [];
  const V = (x: number, y: number, z = 0) => new THREE.Vector3(x, y, z);
  for (const a of PYLON.arms) {
    for (const z of [-0.035, 0.035]) parts.push(beamGeo(V(-a.w, a.y, z), V(a.w, a.y, z), 0.018));
    for (const s of [-1, 1]) {
      parts.push(beamGeo(V(s * a.w, a.y, 0), V(s * 0.06, a.y + 0.09, 0), 0.012));
      parts.push(beamGeo(V(s * a.w, a.y, 0), V(s * a.w, a.y - PYLON.insulator, 0), 0.02));
    }
  }
  parts.push(beamGeo(V(0, 0.95, 0), V(0, 1.03, 0), 0.02));
  return mergeGeometries(parts.map((g) => g.toNonIndexed()));
}

function extrudeGeo(points: [number, number][], depth = 1): THREE.BufferGeometry {
  const sh = new THREE.Shape(points.map(([x, y]) => new THREE.Vector2(x, y)));
  const g = new THREE.ExtrudeGeometry(sh, { depth, bevelEnabled: false });
  g.translate(0, 0, -depth / 2);
  g.clearGroups();
  return g;
}

const factories: Record<string, () => THREE.BufferGeometry> = {
  box: () => new THREE.BoxGeometry(1, 1, 1).translate(0, 0.5, 0),
  cyl4: () => new THREE.CylinderGeometry(0.5, 0.5, 1, 4).rotateY(Math.PI / 4).translate(0, 0.5, 0),
  cyl6: () => new THREE.CylinderGeometry(0.5, 0.5, 1, 6).translate(0, 0.5, 0),
  cyl8: () => new THREE.CylinderGeometry(0.5, 0.5, 1, 8).rotateY(Math.PI / 8).translate(0, 0.5, 0),
  cyl12: () => new THREE.CylinderGeometry(0.5, 0.5, 1, 12).translate(0, 0.5, 0),
  cyl16: () => new THREE.CylinderGeometry(0.5, 0.5, 1, 16).translate(0, 0.5, 0),
  taper12: () => new THREE.CylinderGeometry(0.3, 0.5, 1, 12).translate(0, 0.5, 0),
  taper8: () => new THREE.CylinderGeometry(0.38, 0.5, 1, 8).rotateY(Math.PI / 8).translate(0, 0.5, 0),
  cone6: () => new THREE.ConeGeometry(0.5, 1, 6).translate(0, 0.5, 0),
  cone8: () => new THREE.ConeGeometry(0.5, 1, 8).translate(0, 0.5, 0),
  sphere: () => new THREE.IcosahedronGeometry(0.5, 1),
  ball: () => new THREE.IcosahedronGeometry(0.5, 0),
  band: () => new THREE.CylinderGeometry(0.5, 0.5, 1, 16, 1, true).translate(0, 0.5, 0),
  dome: () => new THREE.SphereGeometry(0.5, 12, 4, 0, Math.PI * 2, 0, Math.PI / 2),
  rock: () => new THREE.DodecahedronGeometry(0.5, 0).translate(0, 0.3, 0),
  // torre de enfriamiento hiperbólica (doble cara: se ve el interior desde arriba)
  hyper: () => new THREE.LatheGeometry(
    [[0.5, 0], [0.43, 0.22], [0.35, 0.5], [0.315, 0.7], [0.33, 0.86], [0.36, 1]].map(([r, y]) => new THREE.Vector2(r, y)), 16),
  // tejado a dos aguas / cuña / bandera / pala (extruidos en Z, profundidad 1)
  gable: () => extrudeGeo([[-0.5, 0], [0.5, 0], [0, 1]]),
  wedge: () => extrudeGeo([[-0.5, 0], [0.5, 0], [-0.5, 1]]),
  flag: () => extrudeGeo([[0, 0], [1, 0.5], [0, 1]], 0.15),
  // presa de gravedad: paramento aguas arriba vertical (x = -0.5), aguas abajo inclinado
  dam: () => extrudeGeo([[-0.5, 0], [0.5, 0], [-0.22, 1], [-0.5, 1]]),
  blade: () => extrudeGeo([[-0.035, 0], [0.04, 0], [0.065, 0.17], [0.022, 1], [-0.004, 1], [-0.03, 0.2]], 0.03),
  lattice: () => latticeGeo(0.5, 0.5, 8, 0.09),
  derrick: () => latticeGeo(0.5, 0.12, 6, 0.05),
  mast: () => latticeGeo(0.5, 0.5, 14, 0.14, false),
  pylonBody: () => latticeGeo(0.2, 0.04, 6, 0.014),
  pylonHead: pylonHeadGeo,
};
const geoCache = new Map<string, THREE.BufferGeometry>();
export function geo(key: string): THREE.BufferGeometry {
  let g = geoCache.get(key);
  if (!g) {
    const f = factories[key];
    if (!f) throw new Error('geometría desconocida: ' + key);
    g = f();
    g.computeBoundingSphere();
    geoCache.set(key, g);
  }
  return g;
}
/** Registra una geometría unitaria nueva (para modelos de terceros). */
export function registerGeometry(key: string, factory: () => THREE.BufferGeometry) { factories[key] = factory; }

// ---------------------------------------------------------------- materiales compartidos
export type MatKind = 'solid' | 'solid2' | 'gloss' | 'glow' | 'water' | 'puff';
const matCache = new Map<string, THREE.Material>();
export function mat(k: MatKind): THREE.Material {
  let m = matCache.get(k);
  if (m) return m;
  const r = PAL.roughness;
  switch (k) {
    case 'solid': m = new THREE.MeshStandardMaterial({ color: 0xffffff, flatShading: true, roughness: r, metalness: 0 }); break;
    case 'solid2': m = new THREE.MeshStandardMaterial({ color: 0xffffff, flatShading: true, roughness: r, metalness: 0, side: THREE.DoubleSide }); break;
    case 'gloss': m = new THREE.MeshStandardMaterial({ color: 0xffffff, flatShading: true, roughness: 0.32, metalness: 0.25 }); break;
    case 'glow': m = new THREE.MeshBasicMaterial({ color: 0xffffff, toneMapped: false }); break;
    case 'water': m = new THREE.MeshStandardMaterial({ color: 0xffffff, flatShading: true, roughness: 0.18, metalness: 0.05, transparent: true, opacity: 0.88 }); break;
    case 'puff': m = new THREE.MeshStandardMaterial({ color: 0xffffff, flatShading: true, roughness: 1, transparent: true, opacity: 0.72, depthWrite: false }); break;
  }
  matCache.set(k, m);
  return m;
}
const lineMat = new THREE.LineBasicMaterial({ vertexColors: true, transparent: true, opacity: 0.9 });

/** Libera geometrías y materiales compartidos (solo al cerrar el juego o en pruebas). */
export function disposeModelCache() {
  for (const g of geoCache.values()) g.dispose();
  for (const m of matCache.values()) m.dispose();
  geoCache.clear();
  matCache.clear();
}

/** Luces sugeridas para ver los modelos (el globo usa su propio shader y no las necesita). */
export function createModelLights(): THREE.Group {
  const g = new THREE.Group();
  g.add(new THREE.HemisphereLight(PAL.lightSky, PAL.lightGround, PAL.hemiIntensity));
  const sun = new THREE.DirectionalLight(0xffffff, PAL.sunIntensity);
  sun.position.set(3, 5, 2);
  g.add(sun);
  return g;
}

// ---------------------------------------------------------------- animación
export type Anim =
  | { k: 'spin'; axis: THREE.Vector3; speed: number; phase: number }
  | { k: 'puff'; life: number; rise: THREE.Vector3; drift: THREE.Vector3; size: number; phase: number }
  | { k: 'blink'; period: number; phase: number; duty: number }
  | { k: 'flow'; dir: THREE.Vector3; speed: number; phase: number }
  | { k: 'pulse'; speed: number; amp: number; phase: number };

export interface AnimRef { mesh: THREE.InstancedMesh; i: number; base: THREE.Matrix4; color: THREE.Color; a: Anim }

const _m = new THREE.Matrix4(), _m2 = new THREE.Matrix4(), _v = new THREE.Vector3(), _c = new THREE.Color();
export function runAnims(refs: AnimRef[], t: number, meshes: Set<THREE.InstancedMesh>) {
  for (const r of refs) {
    const a = r.a;
    switch (a.k) {
      case 'spin':
        _m.makeRotationAxis(a.axis, a.phase + t * a.speed);
        r.mesh.setMatrixAt(r.i, _m2.multiplyMatrices(r.base, _m));
        break;
      case 'puff': {
        const u = (t / a.life + a.phase) % 1;
        _v.copy(a.rise).multiplyScalar(u).addScaledVector(a.drift, u * u);
        const s = a.size * (0.35 + 1.3 * u) * (u > 0.75 ? (1 - u) / 0.25 : 1) * Math.min(1, u * 8);
        _m.makeTranslation(_v.x, _v.y, _v.z).multiply(r.base);
        _m.multiply(_m2.makeScale(s, s, s));
        r.mesh.setMatrixAt(r.i, _m);
        break;
      }
      case 'flow': {
        const u = (t * a.speed + a.phase) % 1;
        _v.copy(a.dir).multiplyScalar(u);
        const f = Math.sin(Math.PI * u);
        _m.makeTranslation(_v.x, _v.y, _v.z).multiply(r.base).multiply(_m2.makeScale(f, 1, f));
        r.mesh.setMatrixAt(r.i, _m);
        break;
      }
      case 'pulse': {
        const s = 1 + a.amp * Math.sin(t * a.speed + a.phase);
        r.mesh.setMatrixAt(r.i, _m.copy(r.base).multiply(_m2.makeScale(s, s, s)));
        break;
      }
      case 'blink': {
        const on = ((t / a.period + a.phase) % 1) < a.duty;
        r.mesh.setColorAt(r.i, on ? r.color : _c.copy(r.color).multiplyScalar(0.12));
        if (r.mesh.instanceColor) r.mesh.instanceColor.needsUpdate = true;
        break;
      }
    }
  }
  for (const m of meshes) m.instanceMatrix.needsUpdate = true;
}

// ---------------------------------------------------------------- builder
export type Lod = 1 | 2;
export interface PartOpts {
  m?: MatKind;
  /** 1 = visible desde detalle 1; 2 = solo en detalle completo. */
  lod?: Lod;
  rx?: number; ry?: number; rz?: number;
  anim?: Anim;
  /** No puede faltar en una planta abandonada. */
  keep?: boolean;
}
interface Part { g: string; m: MatKind; lod: Lod; mat: THREE.Matrix4; color: THREE.Color; anim?: Anim }
export type V3 = [number, number, number];

export interface Built {
  groups: [THREE.Group, THREE.Group];
  anims: AnimRef[];
  animMeshes: Set<THREE.InstancedMesh>;
}

export class Builder {
  private parts: Part[] = [];
  private lines: { lod: Lod; pos: number[]; col: number[] }[] = [{ lod: 1, pos: [], col: [] }, { lod: 2, pos: [], col: [] }];
  private stack: THREE.Matrix4[] = [new THREE.Matrix4()];
  private colCache = new Map<string, THREE.Color>();
  lod: Lod = 1;
  /** Desactiva animaciones (obra, abandono). */
  animOn = true;
  /** Abandonado: desatura colores y quita piezas de detalle al azar. */
  abandoned = false;

  constructor(private loss: () => number) {}

  get top() { return this.stack[this.stack.length - 1]; }

  color(c: Col): THREE.Color {
    let col = this.colCache.get(c);
    if (col) return col;
    const hex = c.startsWith('#') ? c : (PAL as unknown as Record<string, string>)[c];
    col = new THREE.Color(hex);
    if (this.abandoned) {
      const l = col.r * 0.3 + col.g * 0.59 + col.b * 0.11;
      col.lerp(new THREE.Color(l, l, l), PAL.abandonedDesaturate).lerp(new THREE.Color(PAL.abandonedTint), 0.18).multiplyScalar(PAL.abandonedDarken);
    }
    this.colCache.set(c, col);
    return col;
  }

  /** ¿Falta esta pieza? (solo en abandonado, con probabilidad p). */
  lost(p = 0.25): boolean { return this.abandoned && this.loss() < p; }

  push(x: number, y: number, z: number, ry = 0, s = 1) {
    const m = new THREE.Matrix4().compose(new THREE.Vector3(x, y, z), new THREE.Quaternion().setFromAxisAngle(Yax, ry), new THREE.Vector3(s, s, s));
    this.stack.push(this.top.clone().multiply(m));
  }
  pushM(m: THREE.Matrix4) { this.stack.push(this.top.clone().multiply(m)); }
  pop() { this.stack.pop(); }
  /** Ejecuta fn en un marco local trasladado/girado/escalado. */
  at(x: number, z: number, ry: number, fn: () => void, y = 0, s = 1) { this.push(x, y, z, ry, s); fn(); this.pop(); }
  /** Piezas de detalle fino (solo detalle 2). */
  fine(fn: () => void) { const p = this.lod; this.lod = 2; fn(); this.lod = p; }

  /** Punto local → espacio de la planta. */
  pt(x: number, y: number, z: number): THREE.Vector3 { return new THREE.Vector3(x, y, z).applyMatrix4(this.top); }
  /** Vector local → espacio de la planta (con escala). */
  vec(x: number, y: number, z: number): THREE.Vector3 { return new THREE.Vector3(x, y, z).applyMatrix3(new THREE.Matrix3().setFromMatrix4(this.top)); }

  partM(g: string, c: Col, local: THREE.Matrix4, o: PartOpts = {}) {
    const lod = o.lod ?? this.lod;
    if (this.abandoned && !o.keep && lod === 2 && this.loss() < 0.3) return;
    const m = o.m ?? 'solid';
    let color = this.color(c);
    if (this.abandoned && m === 'glow') color = color.clone().multiplyScalar(0.15);
    const anim = this.animOn ? o.anim : undefined;
    this.parts.push({ g, m, lod, mat: local.premultiply(this.top), color, anim });
  }

  part(g: string, c: Col, x: number, y: number, z: number, sx: number, sy: number, sz: number, o: PartOpts = {}) {
    const q = new THREE.Quaternion().setFromEuler(new THREE.Euler(o.rx ?? 0, o.ry ?? 0, o.rz ?? 0, 'YXZ'));
    this.partM(g, c, new THREE.Matrix4().compose(new THREE.Vector3(x, y, z), q, new THREE.Vector3(sx, sy, sz)), o);
  }
  /** Caja con la base en (x, y, z). */
  box(c: Col, x: number, y: number, z: number, sx: number, sy: number, sz: number, o?: PartOpts) { this.part('box', c, x, y, z, sx, sy, sz, o); }
  /** Cilindro de radio r y altura h con la base en (x, y, z). */
  cyl(c: Col, x: number, y: number, z: number, r: number, h: number, o: PartOpts & { seg?: 4 | 6 | 8 | 12 | 16 } = {}) {
    this.part('cyl' + (o.seg ?? 8), c, x, y, z, 2 * r, h, 2 * r, o);
  }
  /** Pieza alargada de a a b (cilindro o caja de grosor t). */
  beam(c: Col, a: V3, b: V3, t: number, o: PartOpts & { g?: string } = {}) {
    const A = new THREE.Vector3(...a), d = new THREE.Vector3(...b).sub(A), len = d.length();
    if (len < 1e-6) return;
    const q = new THREE.Quaternion().setFromUnitVectors(Yax, d.multiplyScalar(1 / len));
    this.partM(o.g ?? 'cyl6', c, new THREE.Matrix4().compose(A, q, new THREE.Vector3(t, len, t)), o);
  }
  /** Polilínea (líneas finas: cables, vientos). */
  line(c: Col, pts: V3[], o: { lod?: Lod; abs?: boolean } = {}) {
    if (this.abandoned && (o.lod ?? this.lod) === 2 && this.loss() < 0.4) return;
    const L = this.lines[(o.lod ?? this.lod) - 1], col = this.color(c);
    for (let i = 0; i + 1 < pts.length; i++) {
      for (const p of [pts[i], pts[i + 1]]) {
        const v = o.abs ? new THREE.Vector3(...p) : this.pt(...p);
        L.pos.push(v.x, v.y, v.z);
        L.col.push(col.r, col.g, col.b);
      }
    }
  }
  /** Emisor de vapor/humo: n bolas que suben y se disipan. */
  puffs(c: Col, x: number, y: number, z: number, o: { n?: number; size?: number; rise?: number; life?: number; drift?: [number, number]; lod?: Lod } = {}) {
    if (!this.animOn) return;
    const n = o.n ?? 6, rise = this.vec(0, o.rise ?? 0.3, 0), drift = this.vec(o.drift?.[0] ?? 0.08, 0, o.drift?.[1] ?? 0.02);
    for (let i = 0; i < n; i++) {
      this.part('ball', c, x, y, z, 1, 1, 1, {
        m: 'puff', lod: o.lod ?? 1, keep: true,
        anim: { k: 'puff', life: o.life ?? 3, rise, drift, size: o.size ?? 0.05, phase: i / n },
      });
    }
  }
  /** Luz que parpadea (glow). */
  blink(c: Col, x: number, y: number, z: number, r: number, period = 1.4, phase = 0, duty = 0.5) {
    this.part('ball', c, x, y, z, 2 * r, 2 * r, 2 * r, { m: 'glow', keep: true, anim: { k: 'blink', period, phase, duty } });
  }

  finish(): Built {
    const groups: [THREE.Group, THREE.Group] = [new THREE.Group(), new THREE.Group()];
    const buckets = new Map<string, Part[]>();
    for (const p of this.parts) {
      const k = `${p.lod}|${p.g}|${p.m}`;
      let arr = buckets.get(k);
      if (!arr) buckets.set(k, (arr = []));
      arr.push(p);
    }
    const anims: AnimRef[] = [];
    const animMeshes = new Set<THREE.InstancedMesh>();
    for (const [k, arr] of buckets) {
      const [lod, g, m] = k.split('|');
      const mesh = new THREE.InstancedMesh(geo(g), mat(m as MatKind), arr.length);
      mesh.name = g;
      arr.forEach((p, i) => {
        mesh.setMatrixAt(i, p.mat);
        mesh.setColorAt(i, p.color);
        if (p.anim) anims.push({ mesh, i, base: p.mat, color: p.color, a: p.anim });
      });
      if (arr.some((p) => p.anim)) {
        animMeshes.add(mesh);
        mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
        mesh.frustumCulled = false;
      } else mesh.computeBoundingSphere();
      if (m === 'puff' || m === 'water') mesh.renderOrder = m === 'puff' ? 3 : 2;
      groups[Number(lod) - 1].add(mesh);
    }
    for (const L of this.lines) {
      if (!L.pos.length) continue;
      const g = new THREE.BufferGeometry();
      g.setAttribute('position', new THREE.Float32BufferAttribute(L.pos, 3));
      g.setAttribute('color', new THREE.Float32BufferAttribute(L.col, 3));
      const ls = new THREE.LineSegments(g, lineMat);
      ls.userData.ownGeometry = true;
      groups[L.lod - 1].add(ls);
    }
    // estado inicial de las animaciones (para que la primera imagen ya sea correcta)
    runAnims(anims, 0, animMeshes);
    return { groups, anims, animMeshes };
  }
}

/** Libera lo propio de un Built (buffers de instancias y líneas; no las geometrías compartidas). */
export function disposeBuilt(b: Built) {
  for (const g of b.groups) {
    g.traverse((o) => {
      if (o instanceof THREE.InstancedMesh) o.dispose();
      else if (o instanceof THREE.LineSegments && o.userData.ownGeometry) o.geometry.dispose();
    });
    g.removeFromParent();
  }
}
