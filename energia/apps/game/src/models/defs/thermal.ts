import { Builder, Col, Y0 } from '../kit';
import type { Ctx, PlantDef } from '../types';
import {
  building, chimney, clamp01, excavator, scaffRing, coolingTower, crawlerCrane, drillRig, fanCooler, pipeL, tank, towerCrane, trees, truck,
} from '../common';

const PI = Math.PI;
const clampi = (v: number, a: number, b: number) => Math.max(a, Math.min(b, Math.round(v)));

function steamFrom(b: Builder, c: Ctx, pts: [number, number, number][], o: { size?: number; rise?: number; n?: number; col?: Col } = {}) {
  if (!c.running) return;
  for (const p of pts) b.puffs(o.col ?? 'steam', p[0], p[1], p[2], { n: o.n ?? 5, size: o.size ?? 0.035, rise: o.rise ?? 0.16, life: 2.8 });
}

// ---------------------------------------------------------------- geotermia
export const geotermica: PlantDef = {
  label: 'Geotérmica', pin: 'geo', survey: 'drill', sub: [0.34, 0.36, 0], typicalMw: 50,
  build(b, c) {
    const m = clampi(2 + c.s.capacityMw / 20, 3, 7);
    const sep: [number, number] = [-0.06, -0.06];
    const wells: [number, number][] = [];
    for (let i = 0; i < m; i++) {
      const a = lerpA(-2.75, -0.35, m === 1 ? 0.5 : i / (m - 1)) + (c.rng() - 0.5) * 0.15;
      const r = 0.37 + (c.rng() - 0.5) * 0.06;
      wells.push([Math.cos(a) * r, Math.sin(a) * r + 0.02]);
    }
    let drilling = -1;
    wells.forEach(([x, z], i) => {
      const s = (i / m) * 0.5;
      const g = c.building ? clamp01((c.s.progress - s) / (0.5 / m)) : 1;
      if (c.building && c.s.progress < s) return;
      b.box('concreteDark', x, Y0, z, 0.07, 0.004, 0.07, { keep: true });
      if (g < 1) { if (drilling < 0) drilling = i; return; }
      b.cyl('steel', x, Y0, z, 0.009, 0.03);
      b.box('stripe', x - 0.012, Y0 + 0.018, z - 0.003, 0.024, 0.006, 0.006);
      b.cyl('steel', x, Y0 + 0.03, z, 0.006, 0.012);
      b.fine(() => b.cyl('concrete', x + 0.025, Y0, z + 0.02, 0.012, 0.035, { seg: 8 }));
      pipeL(b, [x, z], sep, Y0 + 0.022, 0.006, 'pipeHot', c.ph(0.45 + (i / m) * 0.3, 0.6 + (i / m) * 0.3));
      if (c.running && i === 0) b.puffs('steam', x + 0.025, Y0 + 0.04, z + 0.02, { n: 4, size: 0.022, rise: 0.12, life: 2.2 });
    });
    if (drilling >= 0) drillRig(b, wells[drilling][0], wells[drilling][1], 1.1, c.rng() * 3);
    // separadores, casa de máquinas, torres de enfriamiento
    if (c.ph(0.4, 0.6) > 0) for (const dx of [0, 0.035]) b.cyl('pipe', sep[0] + dx, Y0, sep[1], 0.016, 0.065 * c.ph(0.4, 0.6), { seg: 12 });
    const hp = c.ph(0.25, 0.85);
    building(b, -0.03, 0.14, 0.2, 0.075, 0.1, { p: hp, wall: 'wallAlt' });
    if (hp >= 1) pipeL(b, sep, [-0.03, 0.09], Y0 + 0.03, 0.009, 'pipeHot');
    const fans = fanCooler(b, 0.19, -0.02, 3, PI / 2, c.ph(0.5, 0.9));
    steamFrom(b, c, fans, { size: 0.045, rise: 0.22 });
    if (c.building && c.s.progress < 1 && hp > 0) towerCrane(b, -0.17, 0.25, 0.18, 0.5, 0.2);
    if (c.building && c.s.progress < 1) truck(b, 0.1, 0.3, 0.2, 'tank');
    trees(b, c, 4, (x, z) => z < 0.1 || (x > 0.15 && z > 0.2));
    c.hot = b.pt(-0.03, Y0 + 0.08, 0.14);
  },
};
const lerpA = (a: number, b: number, t: number) => a + (b - a) * t;

// ---------------------------------------------------------------- biomasa
export const biomasa: PlantDef = {
  label: 'Biomasa', pin: 'bio', survey: 'survey', sub: [0.34, 0.37, 0], typicalMw: 30,
  build(b, c) {
    const bp = c.ph(0.15, 0.8);
    const top = building(b, -0.03, -0.06, 0.12, 0.2, 0.12, { p: bp, wall: 'wallAlt', roof: 'steelDark' });
    building(b, 0.12, -0.04, 0.14, 0.08, 0.1, { p: c.ph(0.25, 0.85), gable: true });
    const ch = chimney(b, -0.15, -0.22, 0.022, 0.38, c.ph(0.2, 0.75));
    if (bp >= 1 && ch > Y0 + 0.3) b.beam('steel', [-0.06, top - 0.04, -0.1], [-0.15, Y0 + 0.08, -0.22], 0.018, { g: 'cyl8' });
    // patio de combustible
    const yp = c.ph(0.6, 1);
    if (yp > 0 || !c.building) {
      b.box('concreteDark', -0.22, Y0, 0.2, 0.26, 0.004, 0.2, { keep: true });
      for (const [x, z, s] of [[-0.28, 0.15, 1], [-0.17, 0.24, 0.8], [-0.3, 0.27, 0.7]] as const) {
        if (b.lost(0.4)) continue;
        b.part('cone8', 'biomass', x, Y0, z, 0.13 * s, 0.07 * s * Math.max(0.2, yp), 0.13 * s);
      }
      b.fine(() => { for (let i = 0; i < 6; i++) b.cyl('trunk', -0.12, Y0 + 0.006 + (i > 3 ? 0.01 : 0), 0.12 + (i % 4) * 0.012, 0.006, 0.08, { rz: PI / 2, seg: 6 }); });
      if (bp >= 1) b.beam('steel', [-0.18, Y0 + 0.01, 0.12], [-0.05, top - 0.02, 0.0], 0.016, { g: 'box' });
    }
    const fans = fanCooler(b, 0.17, -0.22, 3, 0, c.ph(0.5, 0.9));
    steamFrom(b, c, fans, { size: 0.03, rise: 0.14 });
    if (c.running) b.puffs('smoke', -0.15, ch + 0.01, -0.22, { n: 6, size: 0.04, rise: 0.25, life: 3.2 });
    if (c.building && c.s.progress < 1) towerCrane(b, 0.06, -0.18, 0.28, 2.6, 0.22);
    truck(b, -0.05, 0.3, 0.3, 'logs');
    trees(b, c, 5, (x, z) => z < 0.1 && x > -0.3 || (x > 0.15 && z > 0.2) || (x < -0.05 && z > 0.05));
    c.hot = b.pt(-0.15, ch, -0.22);
  },
};

// ---------------------------------------------------------------- biogás
export const biogas: PlantDef = {
  label: 'Biogás', pin: 'bio', survey: 'survey', sub: [0.34, 0.37, 0], typicalMw: 5,
  build(b, c) {
    const k = clampi(c.s.capacityMw / 1.8, 2, 4);
    for (let i = 0; i < k; i++) {
      const x = -0.3 + i * 0.17, z = -0.16;
      const wp = c.ph(0.1 + i * 0.08, 0.45 + i * 0.08), dp = c.ph(0.6 + i * 0.05, 0.8 + i * 0.05);
      if (wp <= 0) continue;
      b.cyl('concreteDark', x, Y0, z, 0.075, 0.004, { seg: 16 });
      b.cyl('concrete', x, Y0, z, 0.065, 0.06 * wp, { seg: 16, keep: true });
      if (dp > 0) b.part('dome', 'digester', x, Y0 + 0.06, z, 0.13, 0.09 * dp, 0.13, { keep: true });
      if (wp < 1) scaffRing(b, x, Y0 + 0.06 * wp - 0.008, z, 0.07, 0.005);
      if (dp >= 1) pipeL(b, [x, z + 0.065], [0.22, -0.02], Y0 + 0.018, 0.004, 'crane');
    }
    const gp = c.ph(0.55, 0.85);
    if (gp > 0) {
      b.cyl('concrete', 0.24, Y0, 0.02, 0.085, 0.012, { seg: 16 });
      b.part('dome', 'membrane', 0.24, Y0 + 0.012, 0.02, 0.17, 0.14 * gp, 0.17, { keep: true });
    }
    // motores de cogeneración en contenedor y antorcha
    const ep = c.ph(0.65, 0.95);
    if (ep > 0) for (let i = 0; i < 2; i++) {
      b.box('batteryAccent', -0.1, Y0, 0.14 + i * 0.05, 0.11, 0.035, 0.035);
      b.cyl('steel', -0.13, Y0 + 0.035, 0.14 + i * 0.05, 0.006, 0.05);
      if (c.running) b.puffs('smoke', -0.13, Y0 + 0.088, 0.14 + i * 0.05, { n: 3, size: 0.015, rise: 0.08, life: 1.8 });
    }
    if (c.ph(0.7, 0.9) > 0) {
      b.cyl('steelDark', 0.1, Y0, 0.28, 0.006, 0.14);
      if (c.running) b.part('cone6', 'flame', 0.1, Y0 + 0.14, 0.28, 0.022, 0.05, 0.022, { m: 'glow', anim: { k: 'pulse', speed: 9, amp: 0.18, phase: 0 } });
    }
    b.box('steelDark', -0.33, Y0, 0.13, 0.06, 0.03, 0.06);
    b.part('wedge', 'steelDark', -0.33, Y0 + 0.03, 0.13, 0.06, 0.03, 0.06);
    truck(b, -0.33, 0.28, 0.1, 'tank', 'batteryAccent');
    if (c.building && c.s.progress < 1) excavator(b, 0.0, 0.0, 2.4);
    trees(b, c, 6, (x, z) => z < 0.1 && z > -0.3 || (x > 0.15 && z > 0.2));
    c.hot = b.pt(-0.1, Y0 + 0.04, 0.16);
  },
};

// ---------------------------------------------------------------- nuclear y SMR
function containment(b: Builder, c: Ctx, x: number, z: number, r: number, h: number, p: number, dome: boolean) {
  if (p <= 0) return;
  b.cyl('concreteDark', x, Y0, z, r * 1.1, 0.006, { seg: 16 });
  b.cyl('concrete', x, Y0, z, r, h * p, { seg: 16, keep: true });
  if (dome) b.part('dome', 'concrete', x, Y0 + h, z, r * 2, r * 0.9, r * 2, { keep: true });
  else scaffRing(b, x, Y0 + h * p - 0.014, z, r * 1.06, 0.008);
  b.fine(() => { if (p >= 1) b.cyl('steel', x, Y0 + h * 0.8, z, r * 1.005, 0.006, { seg: 16 }); });
  void c;
}

export const nuclear: PlantDef = {
  label: 'Nuclear', pin: 'nuclear', survey: 'drill', sub: [0.34, 0.38, 0], typicalMw: 1100, clear: 0.55,
  build(b, c) {
    const u = clampi(c.s.capacityMw / 1100, 1, 2);
    const xs = u === 1 ? [-0.14] : [-0.3, -0.08];
    xs.forEach((x, i) => {
      const cp = c.ph(0.05 + i * 0.08, 0.6 + i * 0.08);
      containment(b, c, x, -0.14, 0.075, 0.15, cp, c.ph(0.6 + i * 0.08, 0.7 + i * 0.08) >= 1);
      building(b, x + 0.02, 0.07, 0.15, 0.07, 0.1, { p: c.ph(0.3 + i * 0.05, 0.85), wall: 'wallAlt' });
      building(b, x - 0.07, -0.02, 0.05, 0.08, 0.06, { p: c.ph(0.2, 0.7), windows: false });
      if (cp > 0 && cp < 1) towerCrane(b, x + 0.11, -0.22, 0.3, 2.3, 0.24);
    });
    const towers: [number, number][] = u === 1 ? [[0.22, -0.18]] : [[0.24, -0.26], [0.2, 0.04]];
    towers.forEach(([x, z], i) => {
      const h = coolingTower(b, x, z, 0.11, 0.33, c.ph(0.2 + i * 0.1, 0.8 + i * 0.05));
      if (c.running) b.puffs('steam', x, h, z, { n: 7, size: 0.1, rise: 0.3, life: 4, drift: [0.12, 0.04] });
    });
    b.fine(() => b.box('concrete', xs[0] - 0.06, Y0, 0.24, 0.12, 0.03, 0.07));
    if (c.building && c.s.progress < 1) { truck(b, 0.05, 0.3, 0.5, 'box'); crawlerCrane(b, -0.3, 0.28, 0.4, 0.25, 1.2); }
    trees(b, c, 5, (x, z) => z < 0.18 || (x > 0.15 && z > 0.2));
    c.hot = b.pt(xs[0], Y0 + 0.2, -0.14);
  },
};

export const smr: PlantDef = {
  label: 'SMR', pin: 'nuclear', survey: 'drill', sub: [0.34, 0.37, 0], typicalMw: 300,
  build(b, c) {
    const k = clampi(c.s.capacityMw / 77, 1, 6);
    const w = 0.07 * k + 0.06, rp = c.ph(0.1, 0.75);
    const top = building(b, -0.08, -0.1, w, 0.08, 0.15, { p: rp, wall: 'wallAlt', roof: 'concreteDark' });
    for (let i = 0; i < k; i++) {
      const x = -0.08 - w / 2 + 0.06 + i * 0.07;
      const mp = c.ph(0.45 + (i / k) * 0.35, 0.5 + (i / k) * 0.35);
      if (rp >= 1 && mp >= 1) {
        b.cyl('steel', x, top, -0.1, 0.024, 0.012, { seg: 12 });
        b.part('dome', 'concrete', x, top + 0.012, -0.1, 0.048, 0.02, 0.048);
      }
    }
    building(b, -0.05, 0.12, 0.18, 0.06, 0.08, { p: c.ph(0.3, 0.85), gable: true });
    const fans = fanCooler(b, 0.22, -0.18, 3, PI / 2, c.ph(0.5, 0.9));
    steamFrom(b, c, fans, { size: 0.04, rise: 0.2 });
    if (c.building && c.s.progress < 1) {
      crawlerCrane(b, 0.12, -0.0, PI * 0.9, 0.3, 1.2);
      truck(b, 0.12, 0.3, 0.2, 'tank');
    }
    b.fine(() => {
      const f = 0.47, y = Y0 + 0.03;
      for (let i = 0; i < 12; i++) b.box('steelDark', -f + (i / 11) * f * 1.4, Y0, -0.4, 0.004, 0.03, 0.004);
      b.line('steelDark', [[-f, y, -0.4], [-f + f * 1.4, y, -0.4]]);
    });
    trees(b, c, 5, (x, z) => (z > -0.35 && z < 0.2) || (x > 0.15 && z > 0.2));
    c.hot = b.pt(-0.08, top + 0.02, -0.1);
  },
};

// ---------------------------------------------------------------- gas, carbón, petróleo
export const gas: PlantDef = {
  label: 'Ciclo combinado', pin: 'fosil', survey: 'survey', sub: [0.34, 0.37, 0], typicalMw: 600,
  build(b, c) {
    const u = clampi(c.s.capacityMw / 300, 1, 3);
    const span = 0.14;
    let stackTop = Y0;
    for (let i = 0; i < u; i++) {
      const x = -0.22 + i * span;
      const p = c.ph(0.1 + i * 0.1, 0.65 + i * 0.1);
      if (p <= 0) continue;
      b.box('wallAlt', x, Y0, -0.24, 0.05, 0.045 * Math.min(1, p * 2), 0.1);
      building(b, x, -0.09, 0.075, 0.13, 0.13, { p, wall: 'steel', roof: 'steelDark', windows: false });
      stackTop = chimney(b, x, 0.02, 0.018, 0.27, clamp01((p - 0.4) / 0.6));
      if (c.running) b.puffs('steam', x, stackTop, 0.02, { n: 4, size: 0.03, rise: 0.15, life: 2.2 });
    }
    building(b, -0.22 + ((u - 1) * span) / 2, 0.17, u * span, 0.075, 0.09, { p: c.ph(0.3, 0.85), gable: true });
    const fans = fanCooler(b, 0.24, -0.16, 3, PI / 2, c.ph(0.55, 0.9));
    steamFrom(b, c, fans, { size: 0.03, rise: 0.12 });
    const gp = c.ph(0.05, 0.4);
    if (gp > 0) {
      b.beam('crane', [-0.55, Y0 + 0.012, -0.36], [lerpA(-0.55, -0.34, gp), Y0 + 0.012, -0.36], 0.012, { g: 'cyl8' });
      if (gp >= 1) { b.box('steelDark', -0.36, Y0, -0.38, 0.06, 0.025, 0.04); b.cyl('crane', -0.36, Y0 + 0.025, -0.36, 0.008, 0.02); }
    }
    if (c.building && c.s.progress < 1) towerCrane(b, 0.04, -0.05, 0.25, 2.8, 0.24);
    trees(b, c, 5, (x, z) => z < 0.25 && x > -0.35 || (x > 0.15 && z > 0.2));
    c.hot = b.pt(-0.22, stackTop, 0.02);
  },
};

export const carbon: PlantDef = {
  label: 'Carbón', pin: 'fosil', survey: 'survey', sub: [0.34, 0.38, 0], typicalMw: 600, clear: 0.55,
  build(b, c) {
    const bp = c.ph(0.1, 0.75);
    const top = building(b, -0.06, -0.1, 0.13, 0.26, 0.13, { p: bp, wall: 'wallAlt', roof: 'steelDark' });
    building(b, 0.09, -0.08, 0.13, 0.09, 0.12, { p: c.ph(0.25, 0.85), gable: true });
    const ch = chimney(b, -0.24, -0.27, 0.03, 0.52, c.ph(0.15, 0.7), true);
    if (bp >= 1 && ch > Y0 + 0.4) b.beam('steelDark', [-0.08, top - 0.06, -0.16], [-0.24, Y0 + 0.1, -0.27], 0.022, { g: 'cyl8' });
    const tp = c.ph(0.25, 0.85);
    const th = coolingTower(b, 0.24, -0.2, 0.1, 0.3, tp);
    // patio de carbón y cintas
    b.box('concreteDark', -0.24, Y0, 0.2, 0.28, 0.004, 0.2, { keep: true });
    const yp = c.building ? c.ph(0.8, 1) : 1;
    if (yp > 0) for (const [x, z, s] of [[-0.3, 0.15, 1], [-0.17, 0.22, 0.85], [-0.3, 0.27, 0.7]] as const) b.part('gable', 'coal', x, Y0, z, 0.12 * s, 0.05 * s * yp, 0.09 * s);
    if (bp >= 1) b.beam('steel', [-0.2, Y0 + 0.01, 0.12], [-0.08, top - 0.03, -0.04], 0.016, { g: 'box' });
    if (c.running) {
      b.puffs(c.s.stage === 'falla' ? 'smokeDark' : 'smoke', -0.24, ch + 0.01, -0.27, { n: 7, size: 0.05, rise: 0.3, life: 3.6, drift: [0.14, 0.05] });
      b.puffs('steam', 0.24, th, -0.2, { n: 6, size: 0.09, rise: 0.26, life: 3.8 });
    }
    if (c.building && c.s.progress < 1) { towerCrane(b, 0.06, -0.27, 0.34, 2.2, 0.25); truck(b, 0.05, 0.25, 0.3, 'gravel'); }
    truck(b, -0.05, 0.32, 0.2, c.running ? 'gravel' : 'none');
    trees(b, c, 4, (x, z) => z < 0.32 || (x > 0.15 && z > 0.2));
    c.hot = b.pt(-0.06, top, -0.1);
  },
};

export const petroleo: PlantDef = {
  label: 'Petróleo (fuel oil)', pin: 'fosil', survey: 'survey', sub: [0.34, 0.37, 0], typicalMw: 100,
  build(b, c) {
    // parque de tanques con muro de contención
    const tp = c.ph(0.1, 0.6);
    if (tp > 0) {
      const cx = -0.22, cz = -0.2, w = 0.3, d = 0.26;
      for (const s of [-1, 1]) {
        b.box('concrete', cx, Y0, cz + s * d / 2, w, 0.014, 0.008);
        b.box('concrete', cx + s * w / 2, Y0, cz, 0.008, 0.014, d);
      }
      const tanks: [number, number, number][] = [[-0.29, -0.26, 0.055], [-0.15, -0.26, 0.05], [-0.29, -0.13, 0.045], [-0.15, -0.13, 0.045]];
      tanks.forEach(([x, z, r], i) => { if (!b.lost(0.3)) tank(b, x, z, r, 0.07, clamp01(tp * 4 - i), i % 2 ? 'tank' : 'white'); });
      if (tp >= 1) pipeL(b, [-0.1, -0.2], [0.0, 0.03], Y0 + 0.02, 0.005, 'steelDark');
    }
    const k = clampi(c.s.capacityMw / 18, 3, 8);
    const hp = c.ph(0.25, 0.85);
    const w = Math.max(0.2, k * 0.04);
    const top = building(b, 0.04, 0.09, w, 0.06, 0.1, { p: hp, wall: 'wallAlt' });
    if (hp >= 1) for (let i = 0; i < k; i++) {
      const x = 0.04 - w / 2 + (i + 0.5) * (w / k);
      b.cyl('steel', x, top, 0.12, 0.008, 0.1);
      b.fine(() => b.box('steelDark', x, top, 0.065, w / k - 0.006, 0.012, 0.03));
      if (c.running) b.puffs('smoke', x, top + 0.1, 0.12, { n: 3, size: 0.022, rise: 0.12, life: 2.4 });
    }
    truck(b, 0.08, -0.12, 2.6, 'tank', 'white');
    if (c.building && c.s.progress < 1) towerCrane(b, 0.22, -0.05, 0.18, 2.8, 0.2);
    trees(b, c, 5, (x, z) => z < 0.2 || (x > 0.15 && z > 0.2));
    c.hot = b.pt(0.04, top + 0.06, 0.12);
  },
};
