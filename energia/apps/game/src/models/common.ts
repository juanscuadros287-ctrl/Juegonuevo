/** Piezas comunes a varias plantas: terreno, obra, maquinaria, edificios, subestación, prospección. */
import { Builder, Col, PYLON, V3, Y0 } from './kit';
import type { Ctx, PlantDef, SurveyKind } from './types';

const PI = Math.PI;
export const clamp01 = (x: number) => (x < 0 ? 0 : x > 1 ? 1 : x);
export const lerp = (a: number, b: number, t: number) => a + (b - a) * t;

// ---------------------------------------------------------------- terreno
export function ground(b: Builder, c: Ctx, def: PlantDef) {
  if (def.terrain === 'sea') {
    b.cyl('soil', 0, -0.06, 0, 0.64, 0.06, { keep: true });
    b.cyl('sea', 0, -0.012, 0, 0.62, 0.032, { keep: true, m: 'gloss' });
    return;
  }
  b.cyl('soil', 0, -0.05, 0, 0.64, 0.05, { keep: true });
  b.cyl('grass', 0, 0, 0, 0.6, Y0, { keep: true });
  if (c.building && def.clear !== 0) {
    const r = (def.clear ?? 0.5) * (0.3 + 0.7 * c.ph(0, 0.12));
    b.cyl('dirt', 0, Y0, 0, r, 0.003, { keep: true });
  }
}

/** Árboles en el borde de la base (no donde `avoid` devuelve true). */
export function trees(b: Builder, c: Ctx, n: number, avoid: (x: number, z: number) => boolean = () => false) {
  b.fine(() => {
    for (let i = 0; i < n * 3 && n > 0; i++) {
      const a = c.rng() * PI * 2, r = 0.45 + c.rng() * 0.09;
      const x = Math.cos(a) * r, z = Math.sin(a) * r;
      if (avoid(x, z)) continue;
      const s = 0.8 + c.rng() * 0.5;
      b.cyl('trunk', x, Y0, z, 0.006 * s, 0.025 * s, { seg: 6 });
      b.part('cone6', c.rng() < 0.5 ? 'tree' : 'grassDark', x, Y0 + 0.018 * s, z, 0.06 * s, 0.08 * s, 0.06 * s, { ry: c.rng() * 3 });
      n--;
    }
  });
}

/** Franja de río a lo largo de Z. */
export function river(b: Builder, x: number, w: number, z0: number, z1: number, y = Y0 - 0.006, h = 0.008) {
  b.box('sand', x, Y0 - 0.001, (z0 + z1) / 2, w + 0.04, 0.003, Math.abs(z1 - z0), { keep: true });
  b.box('water', x, y, (z0 + z1) / 2, w, h, Math.abs(z1 - z0), { keep: true, m: 'water' });
}

export function catenary(a: V3, z: V3, sagFrac = 0.06, n = 8): V3[] {
  const dx = z[0] - a[0], dy = z[1] - a[1], dz = z[2] - a[2];
  const sag = Math.hypot(dx, dy, dz) * sagFrac;
  const pts: V3[] = [];
  for (let i = 0; i <= n; i++) {
    const t = i / n;
    pts.push([a[0] + dx * t, a[1] + dy * t - 4 * sag * t * (1 - t), a[2] + dz * t]);
  }
  return pts;
}

// ---------------------------------------------------------------- prospección y estudios
export function stake(b: Builder, x: number, z: number, h = 0.07) {
  b.box('stake', x, Y0, z, 0.007, h, 0.007);
  b.part('flag', 'flag', x + 0.003, Y0 + h - 0.025, z, 0.04, 0.024, 0.03);
}

export function metMast(b: Builder, x: number, z: number, h: number) {
  b.part('mast', 'steel', x, Y0, z, 0.016, h, 0.016);
  for (const f of [0.97, 0.66]) {
    b.box('steelDark', x, Y0 + h * f, z, 0.07, 0.003, 0.003);
    b.fine(() => { for (const s of [-1, 1]) b.part('ball', 'white', x + s * 0.035, Y0 + h * f + 0.006, z, 0.012, 0.008, 0.012); });
  }
  b.part('flag', 'white', x, Y0 + h, z, 0.025, 0.012, 0.03);
  b.blink('lightWarn', x, Y0 + h + 0.006, z, 0.006, 1.6);
  for (let k = 0; k < 3; k++) {
    const a = k * PI * 2 / 3 + 0.4, ax = x + Math.cos(a) * h * 0.38, az = z + Math.sin(a) * h * 0.38;
    for (const f of [0.95, 0.55]) b.line('steelDark', [[x, Y0 + h * f, z], [ax, Y0, az]]);
    b.box('concreteDark', ax, Y0, az, 0.012, 0.006, 0.012);
  }
}

function solarStation(b: Builder, x: number, z: number) {
  b.box('concreteDark', x, Y0, z, 0.05, 0.006, 0.05);
  b.cyl('steel', x, Y0, z, 0.005, 0.12);
  b.box('steelDark', x, Y0 + 0.115, z, 0.08, 0.004, 0.006);
  for (const s of [-1, 1]) b.part('dome', 'white', x + s * 0.038, Y0 + 0.119, z, 0.02, 0.016, 0.02);
  b.part('dome', 'mirror', x, Y0 + 0.119, z, 0.014, 0.012, 0.014, { m: 'gloss' });
  b.box('panel', x, Y0 + 0.06, z + 0.012, 0.05, 0.003, 0.035, { m: 'gloss', rx: -0.6 });
  b.box('white', x - 0.008, Y0 + 0.03, z - 0.008, 0.025, 0.03, 0.012);
  b.fine(() => {
    const r = 0.07;
    const pts: V3[] = [[x - r, Y0 + 0.03, z - r], [x + r, Y0 + 0.03, z - r], [x + r, Y0 + 0.03, z + r], [x - r, Y0 + 0.03, z + r], [x - r, Y0 + 0.03, z - r]];
    for (const p of pts.slice(0, 4)) b.box('steelDark', p[0], Y0, p[2], 0.004, 0.03, 0.004);
    b.line('steelDark', pts);
  });
}

export function drillRig(b: Builder, x: number, z: number, k = 1, ry = 0) {
  b.at(x, z, ry, () => {
    b.box('machineryDark', 0, Y0, 0, 0.13 * k, 0.02 * k, 0.09 * k);
    b.part('derrick', 'crane', 0, Y0 + 0.02 * k, 0, 0.075 * k, 0.28 * k, 0.075 * k);
    b.box('steelDark', 0, Y0 + 0.3 * k, 0, 0.022 * k, 0.012 * k, 0.022 * k);
    b.box('machinery', 0.05 * k, Y0 + 0.02 * k, 0.02 * k, 0.03 * k, 0.025 * k, 0.04 * k);
    b.box('steelDark', -0.1 * k, Y0, 0.02 * k, 0.06 * k, 0.022 * k, 0.035 * k);
    b.fine(() => {
      b.box('white', -0.09 * k, Y0, -0.05 * k, 0.05 * k, 0.03 * k, 0.03 * k);
      for (let i = 0; i < 4; i++) b.cyl('steelDark', 0.02 * k + i * 0.006 * k, Y0 + 0.003 * k, 0.075 * k, 0.003 * k, 0.11 * k, { rz: PI / 2, seg: 6 });
      b.box('water', -0.1 * k, Y0 + 0.022 * k, 0.02 * k, 0.05 * k, 0.001, 0.028 * k, { m: 'water' });
    });
  });
}

export function hut(b: Builder, x: number, z: number, w: number, h: number, d: number, ry = 0, wall: Col = 'wall', roof: Col = 'roof') {
  b.at(x, z, ry, () => {
    b.box(wall, 0, Y0, 0, w, h, d);
    b.part('gable', roof, 0, Y0 + h, 0, w + 0.008, h * 0.4, d + 0.008, { ry: PI / 2 });
    b.fine(() => b.box('window', 0, Y0 + h * 0.5, 0, w + 0.002, h * 0.22, d * 0.4));
  });
}

function gaugeStation(b: Builder) {
  river(b, 0, 0.14, -0.56, 0.56);
  hut(b, 0.17, 0.02, 0.06, 0.045, 0.05);
  b.box('concreteDark', 0.1, Y0, 0.02, 0.04, 0.008, 0.03);
  for (let i = 0; i < 5; i++) b.box(i % 2 ? 'white' : 'stripe', 0.06, Y0 - 0.006 + i * 0.012, 0.0, 0.006, 0.012, 0.004);
  for (const s of [-1, 1]) b.box('steel', s * 0.12, Y0, -0.1, 0.006, 0.08, 0.006);
  b.line('steelDark', catenary([-0.12, Y0 + 0.078, -0.1], [0.12, Y0 + 0.078, -0.1], 0.08));
  b.box('white', 0.01, Y0 + 0.045, -0.1, 0.012, 0.01, 0.01);
  b.fine(() => b.cyl('steelDark', 0.14, Y0, 0.07, 0.003, 0.07));
}

export function boat(b: Builder, x: number, z: number, ry: number, len = 0.12) {
  b.at(x, z, ry, () => {
    b.box('roofRed', 0, Y0 - 0.008, 0, len, 0.012, len * 0.28);
    b.box('white', 0, Y0 + 0.004, 0, len, 0.008, len * 0.28);
    b.part('wedge', 'white', len / 2 + len * 0.06, Y0 - 0.008, 0, len * 0.12, 0.02, len * 0.28, { ry: PI, rz: 0 });
    b.box('white', -len * 0.2, Y0 + 0.012, 0, len * 0.3, len * 0.15, len * 0.22);
    b.box('window', -len * 0.2, Y0 + 0.012 + len * 0.09, 0, len * 0.31, len * 0.04, len * 0.2);
  });
}

function buoy(b: Builder, x: number, z: number) {
  b.cyl('buoy', x, Y0 - 0.012, z, 0.028, 0.03);
  b.part('cone8', 'buoy', x, Y0 + 0.018, z, 0.03, 0.03, 0.03);
  b.box('white', x - 0.008, Y0 + 0.04, z - 0.008, 0.016, 0.014, 0.016);
  b.cyl('steel', x, Y0 + 0.04, z, 0.002, 0.04);
  b.blink('lightAmber', x, Y0 + 0.082, z, 0.006, 1.2);
}

function surveyTripod(b: Builder, x: number, z: number) {
  for (let k = 0; k < 3; k++) {
    const a = k * PI * 2 / 3;
    b.beam('steelDark', [x, Y0 + 0.055, z], [x + Math.cos(a) * 0.02, Y0, z + Math.sin(a) * 0.02], 0.003);
  }
  b.box('crane', x, Y0 + 0.055, z, 0.014, 0.014, 0.014);
  for (const [px, pz] of [[0.12, -0.1], [-0.14, 0.08]]) for (let i = 0; i < 4; i++) b.cyl(i % 2 ? 'white' : 'stripe', x + px, Y0 + i * 0.016, z + pz, 0.003, 0.016, { seg: 6 });
}

export function pickup(b: Builder, x: number, z: number, ry: number, color: Col = 'white') {
  b.at(x, z, ry, () => {
    b.box('machineryDark', 0, Y0, 0, 0.05, 0.006, 0.022);
    b.box(color, 0.006, Y0 + 0.005, 0, 0.05, 0.009, 0.022);
    b.box(color, 0.008, Y0 + 0.014, 0, 0.02, 0.01, 0.02);
    b.box('window', 0.008, Y0 + 0.016, 0, 0.021, 0.005, 0.021);
  });
}

/** Prospección (1 instrumento + estacas) y estudios (más instrumentos, oficina, sondeos). */
export function survey(b: Builder, c: Ctx, kind: SurveyKind, sea: boolean) {
  const studies = c.s.stage === 'estudios';
  const corners: [number, number][] = [[-0.42, -0.4], [0.42, -0.4], [0.42, 0.4], [-0.42, 0.4]];
  const mids: [number, number][] = [[0, -0.46], [0.46, 0], [0, 0.46], [-0.46, 0]];
  for (const [x, z] of studies ? [...corners, ...mids] : corners) {
    if (sea) b.part('cone8', 'buoy', x, Y0 - 0.01, z, 0.03, 0.04, 0.03);
    else stake(b, x, z);
  }
  switch (kind) {
    case 'mast': metMast(b, 0, 0, studies ? 0.6 : 0.5); if (studies) metMast(b, -0.22, -0.18, 0.4); break;
    case 'solar': solarStation(b, 0, 0); if (studies) solarStation(b, -0.2, -0.15); break;
    case 'drill': drillRig(b, 0, 0, studies ? 1.2 : 0.85); break;
    case 'gauge': gaugeStation(b); break;
    case 'buoy':
      buoy(b, 0, 0);
      if (studies) { buoy(b, -0.22, 0.12); b.cyl('crane', 0.2, -0.04, -0.15, 0.018, 0.08); metMast(b, 0.2, -0.15, 0.45); }
      break;
    case 'survey': b.at(0.05, 0.05, 0, () => surveyTripod(b, 0, 0), -0.012, 1.6); if (studies) drillRig(b, -0.12, -0.12, 0.6, 0.5); break;
  }
  if (studies) {
    if (sea) boat(b, -0.25, 0.28, 0.4);
    else {
      b.at(-0.3, 0.3, 0.3, () => {
        b.box('white', 0, Y0, 0, 0.12, 0.045, 0.05);
        b.box('roof', 0, Y0 + 0.045, 0, 0.122, 0.005, 0.052);
        b.box('window', 0, Y0 + 0.022, 0, 0.09, 0.012, 0.052);
      });
      pickup(b, -0.12, 0.36, -0.2);
      for (let i = 0; i < 3; i++) {
        const x = (c.rng() - 0.5) * 0.6, z = (c.rng() - 0.5) * 0.5 - 0.05;
        b.cyl('concreteDark', x, Y0, z, 0.012, 0.012);
        b.cyl('flag', x, Y0 + 0.012, z, 0.004, 0.02, { seg: 6 });
      }
    }
  }
}

// ---------------------------------------------------------------- obra y maquinaria
export function towerCrane(b: Builder, x: number, z: number, h: number, ry: number, jib = 0.28) {
  b.at(x, z, ry, () => {
    b.box('concreteDark', 0, Y0, 0, 0.04, 0.008, 0.04);
    b.part('lattice', 'crane', 0, Y0, 0, 0.02, h, 0.02);
    const top = Y0 + h;
    b.part('lattice', 'crane', -jib * 0.32, top, 0, 0.016, jib * 1.32, 0.016, { rz: -PI / 2 });
    b.box('concrete', -jib * 0.3, top - 0.012, 0, 0.03, 0.022, 0.022);
    b.box('white', 0.012, top - 0.018, 0.014, 0.014, 0.016, 0.012);
    b.part('lattice', 'crane', 0, top, 0, 0.012, 0.05, 0.012);
    b.line('steelDark', [[jib, top + 0.008, 0], [0, top + 0.05, 0], [-jib * 0.32, top + 0.008, 0]]);
    b.line('steelDark', [[jib * 0.62, top, 0], [jib * 0.62, top - h * 0.55, 0]]);
    b.box('machineryDark', jib * 0.62, top - h * 0.55 - 0.012, 0, 0.012, 0.012, 0.012);
    b.blink('lightWarn', jib, top + 0.012, 0, 0.005, 1.8);
  });
}

/** Grúa sobre orugas con pluma inclinada; devuelve la punta. */
export function crawlerCrane(b: Builder, x: number, z: number, ry: number, boom: number, angle = 1.25) {
  b.at(x, z, ry, () => {
    for (const s of [-1, 1]) b.box('machineryDark', 0, Y0, s * 0.022, 0.075, 0.016, 0.018);
    b.box('crane', -0.005, Y0 + 0.016, 0, 0.05, 0.026, 0.042);
    b.box('concrete', -0.035, Y0 + 0.018, 0, 0.018, 0.03, 0.04);
    b.box('window', 0.02, Y0 + 0.03, 0.015, 0.012, 0.012, 0.012);
    const tilt = PI / 2 - angle;
    b.part('lattice', 'crane', 0.012, Y0 + 0.035, 0, 0.014, boom, 0.014, { rz: -tilt });
    const tx = 0.012 + boom * Math.sin(tilt), ty = Y0 + 0.035 + boom * Math.cos(tilt);
    b.line('steelDark', [[tx, ty, 0], [tx, ty - boom * 0.35, 0]]);
    b.line('steelDark', [[tx, ty, 0], [-0.03, Y0 + 0.05, 0]]);
    b.box('machineryDark', tx - 0.006, ty - boom * 0.35 - 0.012, -0.006, 0.012, 0.012, 0.012);
  });
}

export type Cargo = 'none' | 'box' | 'logs' | 'panels' | 'tank' | 'blade' | 'gravel';
export function truck(b: Builder, x: number, z: number, ry: number, cargo: Cargo = 'none', cab: Col = 'machinery') {
  b.fine(() => b.at(x, z, ry, () => {
    b.box('machineryDark', 0, Y0, 0, 0.08, 0.008, 0.024);
    b.box(cab, 0.03, Y0 + 0.006, 0, 0.022, 0.024, 0.024);
    b.box('window', 0.0415, Y0 + 0.018, 0, 0.001, 0.009, 0.02);
    b.box('steelDark', -0.012, Y0 + 0.008, 0, 0.054, 0.004, 0.024);
    const y = Y0 + 0.012;
    switch (cargo) {
      case 'box': b.box('white', -0.012, y, 0, 0.052, 0.024, 0.024); break;
      case 'logs': for (let i = 0; i < 3; i++) b.cyl('trunk', -0.012, y + 0.006 + (i === 2 ? 0.008 : 0), (i === 2 ? 0 : i - 0.5) * 0.01, 0.005, 0.052, { rz: PI / 2, seg: 6 }); break;
      case 'panels': b.box('panel', -0.012, y, 0, 0.05, 0.012, 0.022, { m: 'gloss' }); break;
      case 'tank': b.cyl('tank', -0.04, y + 0.012, 0, 0.011, 0.055, { rz: -PI / 2, seg: 12 }); break;
      case 'gravel': b.part('gable', 'gravel', -0.012, y, 0, 0.05, 0.016, 0.02, { ry: PI / 2 }); break;
      case 'blade': b.part('blade', 'white', -0.04, y + 0.004, 0, 0.12, 0.12, 0.12, { rz: -PI / 2, rx: PI / 2 }); break;
      default: break;
    }
  }));
}

export function excavator(b: Builder, x: number, z: number, ry: number) {
  b.fine(() => b.at(x, z, ry, () => {
    b.box('machineryDark', 0, Y0, 0, 0.05, 0.012, 0.035);
    b.box('machinery', -0.004, Y0 + 0.012, 0, 0.038, 0.02, 0.03);
    b.box('window', 0.008, Y0 + 0.022, 0.01, 0.012, 0.012, 0.011);
    b.beam('machinery', [0.012, Y0 + 0.028, 0], [0.05, Y0 + 0.055, 0], 0.007, { g: 'box' });
    b.beam('machinery', [0.05, Y0 + 0.055, 0], [0.068, Y0 + 0.012, 0], 0.006, { g: 'box' });
    b.box('machineryDark', 0.068, Y0 + 0.002, 0, 0.016, 0.012, 0.016);
  }));
}

/** Andamio plano (celosía) de ancho w y alto h centrado en (x, z), girado ry. */
export function scaffold(b: Builder, x: number, z: number, w: number, h: number, ry = 0) {
  b.part('lattice', 'scaffold', x, Y0, z, w, h, 0.01, { ry });
}

/** Casetas de obra (contenedores apilados) y un camión. */
export function siteOffice(b: Builder, c: Ctx, x: number, z: number, ry = 0) {
  b.at(x, z, ry, () => {
    b.box('white', 0, Y0, 0, 0.08, 0.026, 0.028);
    b.box('wallAlt', 0.0, Y0, 0.034, 0.08, 0.026, 0.028);
    b.box('white', 0.0, Y0 + 0.026, 0.017, 0.08, 0.026, 0.028, { ry: 0 });
    b.fine(() => {
      b.box('window', 0, Y0 + 0.012, -0.0005, 0.06, 0.008, 0.03);
      b.box('window', 0, Y0 + 0.038, 0.017, 0.06, 0.008, 0.03);
      b.box('gravel', 0.0, Y0, 0.1, 0.13, 0.003, 0.08);
    });
    truck(b, -0.02, 0.1, 0.1 + c.rng() * 0.2, c.rng() < 0.5 ? 'gravel' : 'box');
  });
}

/** Anillo de andamio/encofrado (banda abierta) alrededor de algo cilíndrico en obra. */
export function scaffRing(b: Builder, x: number, y: number, z: number, r: number, h: number) {
  b.part('band', 'scaffold', x, y, z, 2 * r, h * 2, 2 * r, { m: 'solid2' });
}

// ---------------------------------------------------------------- edificios y equipos
export interface BuildingOpts { wall?: Col; roof?: Col; gable?: boolean; p?: number; ry?: number; windows?: boolean; frame?: Col }
/** Nave/edificio con fases de obra: losa → estructura + andamio → muros → techo. Devuelve la altura del techo. */
export function building(b: Builder, x: number, z: number, w: number, h: number, d: number, o: BuildingOpts = {}): number {
  const p = o.p ?? 1;
  if (p <= 0) return Y0;
  b.at(x, z, o.ry ?? 0, () => {
    b.box('concreteDark', 0, Y0, 0, w + 0.012, 0.004, d + 0.012);
    if (p < 1) {
      const fh = h * clamp01(p * 1.7);
      const nx = Math.max(2, Math.round(w / 0.05)), nz = Math.max(2, Math.round(d / 0.05));
      for (let i = 0; i <= nx; i++) for (const s of [-1, 1]) b.box(o.frame ?? 'steelDark', -w / 2 + (i * w) / nx, Y0, s * d / 2, 0.004, fh, 0.004);
      for (let i = 1; i < nz; i++) for (const s of [-1, 1]) b.box(o.frame ?? 'steelDark', s * w / 2, Y0, -d / 2 + (i * d) / nz, 0.004, fh, 0.004);
      if (fh > h * 0.5) for (const s of [-1, 1]) b.box(o.frame ?? 'steelDark', 0, Y0 + fh - 0.004, s * d / 2, w, 0.004, 0.004);
      const wh = h * clamp01((p - 0.35) / 0.55);
      if (wh > 0.002) b.box(o.wall ?? 'wall', 0, Y0, 0, w, wh, d);
      if (p > 0.15 && p < 0.97) scaffold(b, 0, d / 2 + 0.008, w * 0.9, fh * 0.95);
    } else {
      b.box(o.wall ?? 'wall', 0, Y0, 0, w, h, d);
      if (o.windows !== false) b.fine(() => b.box('window', 0, Y0 + h * 0.55, 0, w * 0.86, Math.min(0.016, h * 0.18), d + 0.002));
    }
    if (p >= 0.92) {
      if (o.gable) b.part('gable', o.roof ?? 'roof', 0, Y0 + h, 0, w + 0.01, Math.min(w, d) * 0.3, d + 0.01, { ry: w > d ? 0 : PI / 2, keep: true });
      else b.box(o.roof ?? 'roof', 0, Y0 + h, 0, w + 0.006, 0.006, d + 0.006, { keep: true });
    }
  });
  return Y0 + h;
}

/** Tanque vertical. p = avance (0..1). */
export function tank(b: Builder, x: number, z: number, r: number, h: number, p = 1, col: Col = 'tank') {
  if (p <= 0) return;
  b.cyl('concreteDark', x, Y0, z, r * 1.08, 0.004, { seg: 12 });
  b.cyl(col, x, Y0, z, r, h * p, { seg: 12 });
  if (p >= 1) {
    b.part('cone8', col, x, Y0 + h, z, r * 2, r * 0.3, r * 2);
    b.fine(() => b.cyl('steel', x, Y0 + h * 0.62, z, r * 1.01, h * 0.04, { seg: 12 }));
  } else scaffRing(b, x, Y0 + h * p - 0.008, z, r * 1.08, 0.006);
}

/** Chimenea. Devuelve la altura de la boca. */
export function chimney(b: Builder, x: number, z: number, r: number, h: number, p = 1, stripes = false): number {
  if (p <= 0) return Y0;
  const hh = h * p;
  b.part('taper8', 'concrete', x, Y0, z, r * 2, hh, r * 2);
  if (stripes && p >= 1) for (let i = 0; i < 4; i++) b.part('taper8', i % 2 ? 'white' : 'stripe', x, Y0 + h * (0.76 + i * 0.06), z, r * 1.64, h * 0.06, r * 1.64);
  b.cyl('steelDark', x, Y0 + hh - 0.004, z, r * 0.8, 0.006, { seg: 8 });
  if (p < 1) scaffRing(b, x, Y0 + hh - 0.016, z, r * 1.3, 0.008);
  return Y0 + hh;
}

/** Torre de enfriamiento hiperbólica. Devuelve la boca. */
export function coolingTower(b: Builder, x: number, z: number, r: number, h: number, p = 1): number {
  if (p <= 0) return Y0;
  b.part('hyper', 'concrete', x, Y0, z, r * 2, h * p, r * 2, { m: 'solid2', keep: true });
  b.cyl('concreteDark', x, Y0, z, r * 1.02, 0.008, { seg: 16 });
  if (p < 1) {
    const prof = [[0.5, 0], [0.43, 0.22], [0.35, 0.5], [0.315, 0.7], [0.33, 0.86], [0.36, 1]];
    let k = 1;
    while (k < prof.length - 1 && prof[k][1] < p) k++;
    const t = (p - prof[k - 1][1]) / (prof[k][1] - prof[k - 1][1]);
    scaffRing(b, x, Y0 + h * p - 0.014, z, 2 * r * lerp(prof[k - 1][0], prof[k][0], t) + 0.004, 0.008);
  }
  return Y0 + h * p;
}

/** Bloque de torres de enfriamiento mecánicas (ventiladores arriba). Devuelve las bocas. */
export function fanCooler(b: Builder, x: number, z: number, n: number, ry = 0, p = 1): [number, number, number][] {
  const out: [number, number, number][] = [];
  if (p <= 0) return out;
  const w = n * 0.045, h = 0.05 * p;
  b.at(x, z, ry, () => {
    b.box('wallAlt', 0, Y0, 0, w, h, 0.05);
    if (p >= 1) for (let i = 0; i < n; i++) {
      const fx = -w / 2 + 0.0225 + i * 0.045;
      b.cyl('steel', fx, Y0 + h, 0, 0.017, 0.012, { seg: 12 });
      b.cyl('machineryDark', fx, Y0 + h + 0.011, 0, 0.014, 0.002, { seg: 12 });
      const v = b.pt(fx, Y0 + h + 0.014, 0);
      out.push([v.x, v.y, v.z]);
    }
  });
  return out;
}

/** Tubería horizontal elevada en L de a hasta b (por la esquina [b.x, a.z]). */
export function pipeL(b: Builder, a: [number, number], z: [number, number], y = Y0 + 0.022, r = 0.007, col: Col = 'pipeHot', p = 1) {
  if (p <= 0) return;
  const corner: [number, number] = [z[0], a[1]];
  const l1 = Math.abs(corner[0] - a[0]), l2 = Math.abs(z[1] - corner[1]), L = (l1 + l2) * p;
  const seg = (s: [number, number], e: [number, number], len: number) => {
    const d = Math.hypot(e[0] - s[0], e[1] - s[1]);
    if (d < 1e-4 || len <= 0) return;
    const f = Math.min(1, len / d), ex = s[0] + (e[0] - s[0]) * f, ez = s[1] + (e[1] - s[1]) * f;
    b.beam(col, [s[0], y, s[1]], [ex, y, ez], r * 2, { g: 'cyl8' });
    b.fine(() => {
      const n = Math.floor((d * f) / 0.05);
      for (let i = 1; i <= n; i++) {
        const t = (i * 0.05) / d;
        b.box('steelDark', s[0] + (e[0] - s[0]) * t, Y0, s[1] + (e[1] - s[1]) * t, 0.004, y - Y0, 0.004);
      }
    });
  };
  seg(a, corner, L);
  seg(corner, z, L - l1);
}

// ---------------------------------------------------------------- red: torres y subestación
/** Torre de alta tensión en (x, z) de altura h; devuelve los enganches en espacio local de la planta. */
export function pylon(b: Builder, x: number, z: number, h: number, ry = 0, growth = 1): V3[] {
  const out: V3[] = [];
  if (growth <= 0) return out;
  b.at(x, z, ry, () => {
    b.fine(() => b.box('concreteDark', 0, Y0, 0, h * 0.46, 0.004, h * 0.46));
    b.part('pylonBody', 'steel', 0, Y0, 0, h, h * Math.max(0.08, growth) * 0.97, h, { keep: true });
    if (growth >= 1) {
      b.part('pylonHead', 'steel', 0, Y0, 0, h, h, h, { keep: true });
      for (const [ax, ay] of PYLON.attach) {
        const v = b.pt(ax * h, Y0 + ay * h, 0);
        out.push([v.x, v.y, v.z]);
      }
    }
  });
  return out;
}

/**
 * Subestación de conexión pequeña (transformadores, pórticos, caseta) con una torre de salida.
 * p = avance de su obra.
 */
export function connection(b: Builder, c: Ctx, x: number, z: number, ry: number, p = c.ph(0.55, 0.95)) {
  if (p <= 0) return;
  b.at(x, z, ry, () => {
    b.box('gravel', 0, Y0, 0, 0.24, 0.004, 0.17, { keep: true });
    for (const s of [-1, 1]) b.box('concreteDark', s * 0.045, Y0, 0.03, 0.055, 0.006, 0.045);
    const gantry: V3[] = [];
    if (p > 0.25) {
      for (const s of [-1, 1]) b.box('steel', s * 0.09, Y0, -0.05, 0.006, 0.085, 0.006);
      b.box('steel', 0, Y0 + 0.08, -0.05, 0.19, 0.006, 0.006);
      for (const gx of [-0.05, 0, 0.05]) gantry.push([gx, Y0 + 0.08, -0.05]);
      b.fine(() => { for (const gx of [-0.05, 0, 0.05]) b.cyl('insulator', gx, Y0, -0.01, 0.004, 0.05); });
    }
    if (p > 0.5) for (const s of [-1, 1]) {
      b.box('transformer', s * 0.045, Y0 + 0.006, 0.03, 0.045, 0.04, 0.035);
      b.box('steelDark', s * 0.045, Y0 + 0.01, 0.03, 0.052, 0.03, 0.022);
      b.cyl('transformer', s * 0.045 - 0.022, Y0 + 0.05, 0.03 - 0.012, 0.007, 0.03, { rz: PI / 2 });
      b.fine(() => { for (const k of [-1, 0, 1]) b.cyl('insulator', s * 0.045 + k * 0.012, Y0 + 0.046, 0.03, 0.003, 0.022, { seg: 6 }); });
    }
    if (p > 0.75) {
      building(b, -0.085, 0.055, 0.05, 0.035, 0.045, { windows: false });
      if (c.running) b.blink('lightOk', 0.09, Y0 + 0.095, -0.05, 0.006, 1.1, c.rng());
    }
    b.fine(() => {
      const fx = 0.125, fz = 0.09, fy = Y0 + 0.025;
      const ring: V3[] = [[-fx, fy, -fz], [fx, fy, -fz], [fx, fy, fz], [-fx, fy, fz], [-fx, fy, -fz]];
      for (let i = 0; i < 4; i++) for (let k = 0; k < 4; k++) {
        const a = ring[i], e = ring[i + 1], t = k / 4;
        b.box('steelDark', a[0] + (e[0] - a[0]) * t, Y0, a[2] + (e[2] - a[2]) * t, 0.003, 0.025, 0.003);
      }
      b.line('steelDark', ring);
    });
    const att = pylon(b, 0, -0.17, 0.17, 0, clamp01((p - 0.2) / 0.5));
    if (att.length && gantry.length && p >= 0.9) {
      const g = gantry.map((v) => { const w = b.pt(...v); return [w.x, w.y, w.z] as V3; });
      for (let i = 0; i < 3; i++) b.line('steelDark', catenary(g[i], att[[0, 2, 1][i]], 0.05, 6), { abs: true });
    }
  });
}
