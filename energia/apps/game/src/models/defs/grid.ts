import * as THREE from 'three';
import { Builder, V3, Y0 } from '../kit';
import type { Ctx, PlantDef } from '../types';
import { building, catenary, chimney, clamp01, crawlerCrane, pipeL, pylon, tank, towerCrane, trees, truck } from '../common';

const PI = Math.PI;
const clampi = (v: number, a: number, b: number) => Math.max(a, Math.min(b, Math.round(v)));

// ---------------------------------------------------------------- baterías
export const baterias: PlantDef = {
  label: 'Baterías', pin: 'almacenamiento', survey: 'survey', sub: [0.34, 0.37, 0], typicalMw: 100,
  build(b, c) {
    const n = clampi(c.s.capacityMw / 6, 4, 24);
    const cols = 3, rows = Math.ceil(n / cols);
    const dz = Math.min(0.085, 0.62 / rows);
    b.box('gravel', -0.12, Y0, -0.4 + (rows * dz) / 2 - 0.02, 0.6, 0.003, rows * dz + 0.04, { keep: true });
    const plinths = c.ph(0.05, 0.3), placed = c.ph(0.3, 0.9) * n;
    let current: [number, number] | null = null;
    for (let i = 0; i < n; i++) {
      const col = i % cols, row = Math.floor(i / cols);
      const x = -0.3 + col * 0.18, z = -0.38 + row * dz;
      if (i / n < plinths) b.box('concreteDark', x, Y0, z, 0.13, 0.006, 0.05);
      if (i >= placed) { if (!current && i / n < plinths) current = [x, z]; continue; }
      if (b.lost(0.3)) continue;
      b.box('battery', x, Y0 + 0.006, z, 0.12, 0.042, 0.04);
      b.box('steel', x + 0.066, Y0 + 0.006, z, 0.014, 0.034, 0.034);
      b.fine(() => b.box('batteryAccent', x, Y0 + 0.04, z, 0.121, 0.004, 0.041));
      if (col < cols - 1) b.fine(() => b.box('white', x + 0.093, Y0, z, 0.02, 0.025, 0.03));
      if (c.running) b.blink(c.s.stage === 'falla' && i === 0 ? 'lightWarn' : 'lightOk', x - 0.05, Y0 + 0.054, z - 0.021, 0.004, 1.6 + (i % 3) * 0.3, (i * 0.37) % 1, 0.6);
    }
    if (c.building && c.s.progress < 1 && current) {
      crawlerCrane(b, current[0] - 0.05, current[1] + 0.08, PI * 0.2, 0.18, 1.1);
      truck(b, 0.2, 0.2, PI / 2, 'box');
    }
    trees(b, c, 5, (x, z) => z < 0.25 || (x > 0.15 && z > 0.2));
    c.hot = b.pt(-0.3, Y0 + 0.05, -0.38);
  },
};

// ---------------------------------------------------------------- hidrógeno
export const hidrogeno: PlantDef = {
  label: 'Hidrógeno verde', pin: 'almacenamiento', survey: 'survey', sub: [0.34, 0.37, 0], typicalMw: 50,
  build(b, c) {
    const hp = c.ph(0.1, 0.75);
    const k = clampi(c.s.capacityMw / 20, 2, 5);
    building(b, -0.14, -0.16, 0.08 + k * 0.045, 0.08, 0.15, { p: hp, wall: 'wallAlt', roof: 'roof' });
    if (hp >= 1) b.fine(() => b.box('hydrogen', -0.14, Y0 + 0.07, -0.16, 0.08 + k * 0.045 + 0.002, 0.008, 0.152));
    // transformadores-rectificadores
    if (c.ph(0.3, 0.6) > 0) for (let i = 0; i < k; i++) b.box('transformer', -0.14 - (k * 0.045) / 2 + i * 0.045, Y0, 0.0, 0.03, 0.03, 0.03);
    // tanques horizontales (salchichas) y esfera
    const tp = c.ph(0.4, 0.9);
    for (let i = 0; i < 3; i++) {
      if (tp * 3 <= i || b.lost(0.3)) continue;
      const z = -0.3 + i * 0.065;
      b.cyl('tank', 0.04, Y0 + 0.03, z, 0.026, 0.16, { rz: -PI / 2, seg: 12 });
      for (const ex of [0.04, 0.2]) b.part('sphere', 'tank', ex, Y0 + 0.03, z, 0.052, 0.052, 0.052);
      b.fine(() => b.cyl('hydrogen', 0.11, Y0 + 0.03, z, 0.027, 0.012, { rz: -PI / 2, seg: 12 }));
      for (const ex of [0.07, 0.17]) b.box('concreteDark', ex, Y0, z, 0.012, 0.012, 0.03);
    }
    if (tp >= 1) {
      for (let i = 0; i < 4; i++) { const a = (i * PI) / 2 + PI / 4; b.cyl('steelDark', 0.2 + Math.cos(a) * 0.04, Y0, 0.05 + Math.sin(a) * 0.04, 0.005, 0.07); }
      b.part('sphere', 'tank', 0.2, Y0 + 0.1, 0.05, 0.13, 0.13, 0.13);
      pipeL(b, [0.0, -0.05], [0.2, 0.05], Y0 + 0.02, 0.004, 'hydrogen');
    }
    // compresores, tratamiento de agua y venteo
    if (c.ph(0.5, 0.8) > 0) {
      b.box('hydrogen', -0.03, Y0, 0.12, 0.08, 0.035, 0.05);
      tank(b, -0.32, 0.12, 0.03, 0.06, c.ph(0.5, 0.8), 'white');
      tank(b, -0.24, 0.14, 0.025, 0.05, c.ph(0.5, 0.8), 'white');
      b.cyl('steel', 0.07, Y0, 0.16, 0.004, 0.12);
      if (c.running) {
        b.puffs('steam', 0.07, Y0 + 0.12, 0.16, { n: 3, size: 0.015, rise: 0.08, life: 2 });
        b.blink('hydrogen', -0.03, Y0 + 0.042, 0.12, 0.006, 1.3);
      }
    }
    if (c.building && c.s.progress < 1) { towerCrane(b, 0.0, -0.06, 0.18, 2.4, 0.2); truck(b, 0.1, 0.32, 0.3, 'tank'); }
    trees(b, c, 5, (x, z) => z < 0.25 || (x > 0.15 && z > 0.2));
    c.hot = b.pt(-0.14, Y0 + 0.09, -0.16);
  },
};

// ---------------------------------------------------------------- subestación (grande)
export const subestacion: PlantDef = {
  label: 'Subestación', pin: 'red', survey: 'survey', sub: null, typicalMw: 500,
  build(b, c) {
    b.box('gravel', 0, Y0, -0.02, 0.8, 0.004, 0.62, { keep: true });
    const fp = c.ph(0, 0.2), gp = c.ph(0.2, 0.55), tp = c.ph(0.5, 0.8), lp = c.ph(0.85, 1);
    const bays = [-0.3, -0.15, 0, 0.15, 0.3];
    if (fp > 0) for (const x of bays) b.box('concreteDark', x, Y0, -0.2, 0.05, 0.006, 0.18);
    const gantryPts: V3[] = [];
    if (gp > 0) {
      for (const x of bays) for (const z of [-0.26, -0.12]) b.box('steel', x, Y0, z, 0.007, 0.12 * gp, 0.007);
      if (gp >= 1) {
        for (const z of [-0.26, -0.12]) b.box('steel', 0, Y0 + 0.115, z, 0.62, 0.007, 0.007);
        for (const x of bays) {
          b.fine(() => { for (const d of [-0.012, 0, 0.012]) b.cyl('insulator', x + d, Y0, -0.19, 0.004, 0.05, { seg: 6 }); });
          gantryPts.push([x, Y0 + 0.115, -0.26]);
        }
        for (const d of [-0.012, 0, 0.012]) b.line('steelDark', [[-0.31, Y0 + 0.1 + d, -0.12], [0.31, Y0 + 0.1 + d, -0.12]]);
      }
    }
    const k = clampi(c.s.capacityMw / 250, 2, 4);
    for (let i = 0; i < k; i++) {
      if (tp * k <= i) continue;
      const x = -0.27 + (i * 0.54) / Math.max(1, k - 1);
      b.box('concreteDark', x, Y0, 0.06, 0.1, 0.006, 0.08);
      b.box('transformer', x, Y0 + 0.006, 0.06, 0.07, 0.06, 0.06);
      b.box('steelDark', x, Y0 + 0.012, 0.06, 0.08, 0.045, 0.04);
      b.cyl('transformer', x - 0.035, Y0 + 0.07, 0.04, 0.009, 0.07, { rz: PI / 2 });
      b.fine(() => { for (const d of [-0.02, 0, 0.02]) b.cyl('insulator', x + d, Y0 + 0.066, 0.065, 0.004, 0.035, { seg: 6 }); });
      if (lp >= 1) b.line('steelDark', [[x, Y0 + 0.1, 0.065], [x, Y0 + 0.1, -0.12]]);
      if (c.running) b.blink(i % 2 ? 'lightAmber' : 'lightOk', x + 0.03, Y0 + 0.075, 0.09, 0.006, 0.9 + i * 0.25, i * 0.3);
    }
    building(b, -0.24, 0.22, 0.14, 0.05, 0.08, { p: c.ph(0.3, 0.8), gable: true });
    // líneas de llegada
    const att = [pylon(b, -0.15, -0.44, 0.22, 0, clamp01(gp * 1.5)), pylon(b, 0.15, -0.44, 0.22, 0, clamp01(gp * 1.5 - 0.3))];
    if (lp > 0 && gantryPts.length) {
      for (let p = 0; p < 2; p++) for (let i = 0; i < 2; i++) {
        if (att[p].length === 0) continue;
        const g = gantryPts[p * 2 + i + (p ? 1 : 0)];
        b.line('steelDark', catenary(att[p][i * 2], g, 0.05, 6), { abs: true });
        b.line('steelDark', catenary(att[p][i * 2 + 1], g, 0.05, 6), { abs: true });
      }
    }
    b.fine(() => {
      const fx = 0.42, fz0 = -0.34, fz1 = 0.3, y = Y0 + 0.03;
      const ring: V3[] = [[-fx, y, fz0], [fx, y, fz0], [fx, y, fz1], [-fx, y, fz1], [-fx, y, fz0]];
      for (let i = 0; i < 4; i++) for (let t = 0; t < 8; t++) {
        const a = ring[i], e = ring[i + 1];
        b.box('steelDark', a[0] + ((e[0] - a[0]) * t) / 8, Y0, a[2] + ((e[2] - a[2]) * t) / 8, 0.004, 0.03, 0.004);
      }
      b.line('steelDark', ring);
    });
    if (c.building && c.s.progress < 1) { crawlerCrane(b, 0.25, 0.22, PI * 0.8, 0.22, 1.2); truck(b, 0.05, 0.24, 0, 'box'); }
    c.hot = b.pt(-0.27, Y0 + 0.07, 0.06);
  },
};

// ---------------------------------------------------------------- línea de transmisión (tramo de muestra)
export const linea_transmision: PlantDef = {
  label: 'Línea de transmisión', pin: 'red', survey: 'survey', sub: null, typicalMw: 500, clear: 0,
  build(b, c) {
    const xs = [-0.4, 0, 0.4], H = 0.3;
    b.box(c.building ? 'dirt' : 'grassDark', 0, Y0, 0, 1.08, 0.002, 0.1, { keep: true });
    const att = xs.map((x, i) => pylon(b, x, 0, H, PI / 2, c.ph(0.05 + i * 0.2, 0.3 + i * 0.2)));
    const sp = c.ph(0.75, 1);
    const n = att[0].length;
    if (sp > 0) for (let k = 0; k < n; k++) {
      const segs: [V3, V3][] = [];
      if (att[0].length) segs.push([[-0.56, att[0][k][1] - 0.02, att[0][k][2]], att[0][k]]);
      for (let i = 0; i + 1 < att.length; i++) if (att[i].length && att[i + 1].length) segs.push([att[i][k], att[i + 1][k]]);
      if (att[2].length) segs.push([att[2][k], [0.56, att[2][k][1] - 0.02, att[2][k][2]]]);
      segs.slice(0, Math.ceil(segs.length * sp)).forEach(([a, e]) => b.line('steelDark', catenary(a, e, 0.04, 8), { abs: true }));
    }
    if (c.building && c.s.progress < 1) {
      const i = Math.min(2, Math.floor(c.s.progress / 0.25));
      crawlerCrane(b, xs[i] + 0.08, 0.12, PI * 0.6, 0.32, 1.25);
      truck(b, xs[i] - 0.08, 0.15, 0.2, 'box');
      if (sp > 0) b.box('crane', -0.48, Y0, -0.12, 0.05, 0.03, 0.04);
    }
    trees(b, c, 10, (_x, z) => Math.abs(z) < 0.12);
    c.hot = b.pt(0, Y0 + H, 0);
  },
};

// ---------------------------------------------------------------- eficiencia industrial (fábrica existente + mejoras)
function factory(b: Builder, c: Ctx) {
  const w = 0.42, d = 0.26, h = 0.07, teeth = 5;
  b.box('concreteDark', -0.05, Y0, -0.08, w + 0.02, 0.004, d + 0.02, { keep: true });
  b.box('wall', -0.05, Y0, -0.08, w, h, d, { keep: true });
  b.fine(() => b.box('window', -0.05, Y0 + h * 0.5, -0.08, w + 0.002, 0.012, d * 0.9));
  for (let i = 0; i < teeth; i++) {
    const z = -0.08 - d / 2 + (i + 0.5) * (d / teeth);
    b.part('wedge', 'roof', -0.05, Y0 + h, z, d / teeth, 0.03, w, { ry: PI / 2, keep: true });
    b.fine(() => b.box('window', -0.05, Y0 + h, z - d / teeth / 2 + 0.002, w * 0.96, 0.026, 0.002));
  }
  building(b, 0.24, 0.13, 0.12, 0.06, 0.08, { wall: 'wallAlt' });
  for (let i = 0; i < 3; i++) b.fine(() => b.box('steelDark', -0.2 + i * 0.07, Y0, 0.051, 0.04, 0.045, 0.004));
  const ch = chimney(b, -0.3, -0.27, 0.016, 0.16);
  const retro = c.s.stage === 'operacion' || c.s.stage === 'falla' || (c.building && c.s.progress > 0.6);
  if (b.animOn) b.puffs(retro ? 'steam' : 'smoke', -0.3, ch + 0.005, -0.27, { n: 5, size: retro ? 0.02 : 0.035, rise: 0.2, life: 3 });
  truck(b, -0.13, 0.12, PI / 2, 'box', 'white');
  truck(b, 0.0, 0.14, PI / 2 + 0.1, 'box', 'roofRed');
}

export const eficiencia_industrial: PlantDef = {
  label: 'Eficiencia industrial', pin: 'eficiencia', survey: 'survey', sub: [0.34, 0.38, 0], typicalMw: 10, clear: 0,
  base: factory,
  build(b, c) {
    const w = 0.42, d = 0.26, h = 0.07, teeth = 5;
    // FV en cubierta: paneles sobre cada diente de sierra
    const pv = c.ph(0.3, 0.9) * teeth;
    const slope = Math.atan2(0.03, d / teeth);
    for (let i = 0; i < Math.ceil(pv) && i < teeth; i++) {
      const z = -0.08 - d / 2 + (i + 0.5) * (d / teeth);
      const n = 6, part = Math.min(1, pv - i);
      for (let k = 0; k < Math.floor(n * part); k++) {
        if (b.lost(0.3)) continue;
        b.box('panel', -0.05 - w / 2 + (k + 0.5) * (w / n), Y0 + h + 0.016, z, w / n - 0.008, 0.004, d / teeth / Math.cos(slope) * 0.86, { m: 'gloss', rx: -slope });
      }
    }
    // bombas de calor y recuperación de calor
    const hp = c.ph(0.1, 0.5);
    for (let i = 0; i < 3; i++) {
      if (hp * 3 <= i) continue;
      const x = 0.18 + i * 0.06;
      b.box('white', x, Y0, -0.12, 0.05, 0.035, 0.05);
      b.cyl('steelDark', x, Y0 + 0.035, -0.12, 0.018, 0.003, { seg: 12 });
      if (c.running) b.part('box', 'steel', x, Y0 + 0.039, -0.12, 0.032, 0.002, 0.005, { anim: { k: 'spin', axis: new THREE.Vector3(0, 1, 0), speed: 8, phase: i } });
    }
    tank(b, 0.21, -0.25, 0.025, 0.06, c.ph(0.3, 0.6), 'pipeHot');
    if (c.ph(0.3, 0.6) >= 1) pipeL(b, [0.21, -0.25], [0.13, -0.1], Y0 + 0.03, 0.004, 'pipeHot');
    if (c.building && c.s.progress < 1) {
      crawlerCrane(b, 0.22, 0.0, PI * 0.95, 0.24, 1.2);
      truck(b, 0.3, -0.33, 0.1, 'panels');
      for (let i = 0; i < 3; i++) b.part('lattice', 'scaffold', -0.05 + (i - 1) * 0.12, Y0, 0.059, 0.11, 0.09, 0.012);
    }
    trees(b, c, 6, (x, z) => z < 0.2 && z > -0.36 || (x > 0.15 && z > 0.2));
    c.hot = b.pt(-0.05, Y0 + h + 0.03, -0.08);
  },
};
