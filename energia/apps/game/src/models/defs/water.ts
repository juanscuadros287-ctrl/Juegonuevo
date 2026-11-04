import { Builder, V3, Y0 } from '../kit';
import type { Ctx, PlantDef } from '../types';
import { building, crawlerCrane, excavator, lerp, river, towerCrane, trees, truck } from '../common';

const PI = Math.PI;

/** Agua que corre de a hacia b (vetas de espuma animadas). */
function flow(b: Builder, a: V3, e: V3, n: number, w: number, speed = 0.6) {
  if (!b.animOn) return;
  const dir = b.vec(e[0] - a[0], e[1] - a[1], e[2] - a[2]);
  const ry = Math.atan2(e[0] - a[0], e[2] - a[2]);
  const rx = -Math.atan2(e[1] - a[1], Math.hypot(e[0] - a[0], e[2] - a[2]));
  for (let i = 0; i < n; i++) {
    const ox = (((i * 0.618) % 1) - 0.5) * w;
    b.part('box', 'foam', a[0] + Math.cos(ry) * ox, a[1] + 0.002, a[2] - Math.sin(ry) * ox, 0.006, 0.002, 0.03, {
      ry, rx, keep: true, anim: { k: 'flow', dir, speed: speed * (0.8 + ((i * 0.37) % 0.4)), phase: (i * 0.381) % 1 },
    });
  }
}

/** Laderas del valle (rocas) a ambos lados de x = 0, entre z0 y z1. */
function valley(b: Builder, c: Ctx, z0: number, z1: number, inner = 0.25, hmax = 0.32) {
  for (const s of [-1, 1]) {
    for (let z = z0; z <= z1 + 1e-6; z += 0.15) {
      const w = 0.2 + c.rng() * 0.06, h = hmax * (0.75 + c.rng() * 0.3);
      b.part('rock', c.rng() < 0.5 ? 'rock' : 'rockDark', s * (inner + w / 2), Y0 - 0.02, z, w, h, 0.2, { ry: c.rng() * 3, keep: true });
      b.part('rock', 'grassDark', s * (inner + w / 2 + 0.06), Y0 - 0.02, z + 0.06, w * 0.9, h * 1.08, 0.18, { ry: c.rng() * 3, keep: true });
    }
  }
}

export const hidro_embalse: PlantDef = {
  label: 'Hidro de embalse', pin: 'agua', survey: 'gauge', sub: [0.36, 0.4, 0], typicalMw: 300, clear: 0.3,
  base(b, c) {
    valley(b, c, -0.5, 0.05, 0.25, 0.48);
    for (const x of [-0.16, 0.0, 0.16]) b.part('rock', c.rng() < 0.5 ? 'rockDark' : 'grassDark', x, Y0 - 0.03, -0.55, 0.22, 0.34, 0.14, { ry: c.rng() * 3, keep: true });
  },
  build(b, c) {
    const Hd = Math.max(0.17, Math.min(0.26, 0.16 + c.s.capacityMw / 3000));
    const N = 10, zf = -0.02;
    const layers = c.ph(0.08, 0.85) * N;
    const fill = c.building ? c.ph(0.88, 1) : c.s.stage === 'abandonado' ? 0.45 : 1;
    // río: aguas abajo siempre; aguas arriba hasta que se llena el embalse
    river(b, 0, 0.12, zf + 0.1, 0.56);
    if (fill < 1) river(b, 0, 0.12, -0.56, zf);
    if (fill > 0) b.box('waterDeep', 0, Y0 - 0.004, -0.27, 0.56, Hd * 0.74 * fill + 0.004, 0.5, { m: 'water', keep: true });
    // presa por capas
    const done = layers >= N;
    if (done) {
      b.part('dam', 'concrete', 0, Y0, zf + 0.065, 0.13, Hd, 0.6, { ry: -PI / 2, keep: true });
      // juntas entre bloques y coronación con pretil
      const slope = Math.atan2(0.13 - 0.036, Hd), len = Math.hypot(Hd, 0.13 - 0.036);
      for (let i = -3; i <= 3; i++) if (Math.abs(i) > 1) b.box('concreteDark', i * 0.075, Y0, zf + 0.13, 0.005, len, 0.004, { rx: -slope });
      for (const s of [-1, 1]) b.box('concreteDark', 0, Y0 + Hd, zf + (s < 0 ? 0.002 : 0.034), 0.6, 0.008, 0.004);
    }
    else for (let j = 0; j < Math.ceil(layers); j++) {
      const f = j / N, y = Y0 + f * Hd, h = Hd / N;
      const t = lerp(0.13, 0.036, f), w = lerp(0.36, 0.6, f);
      const part = Math.min(1, layers - j);
      const col = c.building ? (j % 2 ? 'concrete' : 'concreteDark') : 'concrete';
      if (part >= 1 && !(j === N - 1 && !c.building)) b.box(col, 0, y, zf + t / 2, w, h, t, { keep: true });
      else if (part >= 1) for (const s of [-1, 1]) b.box(col, s * (w / 4 + 0.03), y, zf + t / 2, w / 2 - 0.06, h, t, { keep: true });
      else {
        const nb = Math.ceil(w / 0.075);
        for (let k = 0; k < Math.floor(nb * part); k++) b.box(col, -w / 2 + (k + 0.5) * (w / nb), y, zf + t / 2, w / nb - 0.004, h, t);
      }
    }
    if (done) {
      // vertedero central: pilas, compuertas y agua por el paramento
      const top = Y0 + Hd;
      for (const x of [-0.065, -0.022, 0.022, 0.065]) b.box('concreteDark', x, top - 0.01, zf, 0.012, 0.03, 0.04);
      b.fine(() => { for (const x of [-0.044, 0, 0.044]) b.box('steelDark', x, top - 0.006, zf + 0.005, 0.03, 0.016, 0.006); });
      b.box('concreteDark', 0, top + 0.012, zf + 0.004, 0.14, 0.006, 0.03);
      if (c.running) {
        const a: V3 = [0, top - 0.006, zf + 0.04], e: V3 = [0, Y0 + 0.004, zf + 0.135];
        const len = Math.hypot(e[1] - a[1], e[2] - a[2]);
        b.part('box', 'water', 0, (a[1] + e[1]) / 2, (a[2] + e[2]) / 2, 0.1, 0.004, len, { m: 'water', rx: Math.atan2(a[1] - e[1], e[2] - a[2]), keep: true });
        flow(b, a, e, 10, 0.09, 0.9);
        flow(b, [0, Y0 + 0.003, zf + 0.15], [0, Y0 + 0.003, 0.52], 8, 0.1, 0.35);
        b.puffs('foam', 0, Y0 + 0.01, zf + 0.16, { n: 6, size: 0.035, rise: 0.04, life: 1.4, drift: [0, 0.06] });
      }
      b.fine(() => { for (const s of [-1, 1]) b.box('steelDark', s * 0.2, Y0 + Hd, zf + 0.005, 0.004, 0.012, 0.03); });
    }
    // casa de máquinas al pie, margen derecha
    const pp = c.ph(0.3, 0.9);
    building(b, 0.16, zf + 0.2, 0.11, 0.05, 0.07, { p: pp, roof: 'roof' });
    if (pp >= 1) {
      b.box('water', 0.12, Y0 - 0.004, zf + 0.25, 0.08, 0.008, 0.06, { m: 'water' });
      if (c.running) flow(b, [0.13, Y0 + 0.004, zf + 0.24], [0.04, Y0 + 0.004, zf + 0.34], 4, 0.05, 0.5);
    }
    // obra: ataguía y túnel de desvío, grúas torre y cable-grúa
    if (c.building && c.s.progress < 1) {
      if (fill <= 0) {
        b.part('gable', 'dirt', 0, Y0, -0.25, 0.2, 0.04, 0.05, { ry: 0 });
        b.box('machineryDark', -0.21, Y0, -0.15, 0.03, 0.03, 0.02);
      }
      towerCrane(b, -0.2, zf + 0.18, Hd + 0.12, -0.6, 0.26);
      towerCrane(b, 0.03, zf + 0.22, Hd + 0.08, 2.2, 0.22);
      for (const s of [-1, 1]) b.part('lattice', 'crane', s * 0.4, Y0 + 0.2, zf + 0.04, 0.016, 0.14, 0.016);
      b.line('steelDark', [[-0.4, Y0 + 0.34, zf + 0.04], [0, Y0 + 0.3, zf + 0.04], [0.4, Y0 + 0.34, zf + 0.04]]);
      truck(b, -0.08, 0.3, 1.2, 'gravel');
      excavator(b, 0.05, 0.4, 0.4);
    }
    trees(b, c, 4, (x, z) => z < 0.12 || Math.abs(x) < 0.2 || (x > 0.2 && z > 0.25));
    c.hot = b.pt(0.16, Y0 + 0.06, zf + 0.2);
  },
};

export const hidro_pasada: PlantDef = {
  label: 'Hidro de pasada', pin: 'agua', survey: 'gauge', sub: [-0.32, 0.36, 0], typicalMw: 30, clear: 0.4,
  build(b, c) {
    const zw = -0.05;
    const raised = c.building ? c.ph(0.85, 1) : 1;
    river(b, 0, 0.2, -0.56, 0.56);
    if (raised > 0) b.box('water', 0, Y0 - 0.004, -0.31, 0.2, 0.012 * raised + 0.004, 0.5, { m: 'water' });
    // azud con pilas y compuertas
    const pp = c.ph(0.1, 0.65), gp = c.ph(0.6, 0.8);
    if (pp > 0) for (const x of [-0.105, -0.035, 0.035, 0.105]) b.box('concrete', x, Y0 - 0.006, zw, 0.02, 0.07 * pp, 0.05, { keep: true });
    if (gp > 0) {
      for (const x of [-0.07, 0, 0.07]) b.box('steelDark', x, Y0 - 0.006, zw, 0.05, 0.03 * gp, 0.008);
      if (gp >= 1) b.box('concreteDark', 0, Y0 + 0.064, zw, 0.24, 0.008, 0.035, { keep: true });
    }
    if (c.building && c.s.progress < 0.8) {
      b.part('gable', 'dirt', 0.06, Y0 - 0.004, zw, 0.08, 0.035, 0.28, { ry: 0 });
      crawlerCrane(b, 0.18, zw + 0.06, PI, 0.3, 1.1);
    }
    // toma, canal y casa de máquinas en la margen derecha
    const hp = c.ph(0.2, 0.85);
    building(b, 0.24, 0.12, 0.12, 0.055, 0.08, { p: hp, roof: 'roof', gable: true });
    if (hp >= 1) {
      b.box('concrete', 0.13, Y0, -0.09, 0.05, 0.03, 0.03);
      b.beam('steel', [0.14, Y0 + 0.02, -0.08], [0.22, Y0 + 0.02, 0.08], 0.018, { g: 'cyl8' });
      b.box('water', 0.15, Y0 - 0.004, 0.18, 0.12, 0.008, 0.035, { m: 'water' });
    }
    if (c.running) {
      for (const x of [-0.07, 0, 0.07]) flow(b, [x, Y0 + 0.004, zw + 0.02], [x, Y0 + 0.004, 0.5], 3, 0.04, 0.45);
      b.puffs('foam', 0, Y0 + 0.004, zw + 0.04, { n: 6, size: 0.03, rise: 0.025, life: 1.2, drift: [0, 0.05] });
      flow(b, [0.2, Y0 + 0.004, 0.18], [0.05, Y0 + 0.004, 0.2], 3, 0.03, 0.4);
    }
    if (c.building && c.s.progress < 1) { truck(b, 0.36, -0.05, 1.4, 'gravel'); excavator(b, -0.18, -0.2, 0.5); }
    trees(b, c, 9, (x, z) => Math.abs(x) < 0.16 || (x > 0.15 && z > -0.15 && z < 0.25) || (x < -0.15 && z > 0.2));
    c.hot = b.pt(0.24, Y0 + 0.06, 0.12);
  },
};

export const hidro_bombeo: PlantDef = {
  label: 'Hidro de bombeo', pin: 'agua', survey: 'gauge', sub: [0.34, 0.38, 0], typicalMw: 500, clear: 0.45,
  base(b) {
    // meseta del embalse superior
    b.part('taper8', 'rockDark', -0.12, Y0 - 0.02, -0.2, 0.62, 0.22, 0.48, { keep: true });
    b.part('taper8', 'grassDark', -0.12, Y0 + 0.19, -0.2, 0.47, 0.012, 0.36, { keep: true });
  },
  build(b, c) {
    const top = Y0 + 0.2, ep = c.ph(0.1, 0.6);
    const fill = c.building ? c.ph(0.85, 1) : c.s.stage === 'abandonado' ? 0.4 : 1;
    if (ep > 0) b.part('cyl12', 'gravel', -0.12, top, -0.2, 0.42, 0.035 * ep, 0.3, { keep: true });
    if (fill > 0) b.part('cyl12', 'water', -0.12, top + 0.01, -0.2, 0.37, 0.024 * fill, 0.25, { m: 'water', keep: true });
    // embalse inferior
    b.part('cyl12', 'sand', -0.2, Y0 - 0.001, 0.3, 0.42, 0.003, 0.22, { keep: true });
    if (fill > 0) b.part('cyl12', 'water', -0.2, Y0 - 0.004, 0.3, 0.38, 0.008, 0.19, { m: 'water', keep: true });
    // tuberías forzadas
    const pp = c.ph(0.3, 0.8);
    for (const s of [-1, 1]) {
      const a: V3 = [0.03 + s * 0.012, top + 0.01, -0.12], e: V3 = [0.09 + s * 0.012, Y0 + 0.02, 0.1];
      if (pp <= 0) break;
      const end: V3 = [lerp(a[0], e[0], pp), lerp(a[1], e[1], pp), lerp(a[2], e[2], pp)];
      b.beam('steel', a, end, 0.016, { g: 'cyl8', keep: true });
      b.fine(() => { for (let i = 1; i < 4; i++) if (i / 4 <= pp) b.box('concreteDark', lerp(a[0], e[0], i / 4), Y0, lerp(a[2], e[2], i / 4), 0.026, lerp(a[1], e[1], i / 4) - Y0, 0.02); });
      if (c.running && pp >= 1) {
        const dir = b.vec(e[0] - a[0], e[1] - a[1], e[2] - a[2]);
        for (let i = 0; i < 3; i++) b.part('ball', 'water', a[0], a[1] + 0.008, a[2], 0.012, 0.012, 0.012, { m: 'glow', anim: { k: 'flow', dir, speed: 0.4, phase: i / 3 + s * 0.17 } });
      }
    }
    const hp = c.ph(0.2, 0.85);
    building(b, 0.11, 0.15, 0.11, 0.06, 0.08, { p: hp, gable: true });
    if (hp >= 1) b.box('water', 0.0, Y0 - 0.002, 0.24, 0.12, 0.004, 0.03, { m: 'water', ry: 0.6 });
    if (c.building && c.s.progress < 1) {
      towerCrane(b, 0.22, 0.06, 0.2, 2.6, 0.2);
      excavator(b, -0.22, 0.28, 0.3);
      truck(b, -0.05, 0.42, 0.2, 'gravel');
    }
    trees(b, c, 5, (x, z) => z < 0.05 || x < 0.05 || (x > 0.2 && z > 0.25));
    c.hot = b.pt(0.11, Y0 + 0.07, 0.15);
  },
};

