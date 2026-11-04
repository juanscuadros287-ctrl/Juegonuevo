import * as THREE from 'three';
import { Builder, Y0 } from '../kit';
import type { Ctx, PlantDef } from '../types';
import { boat, building, clamp01, crawlerCrane, trees, truck } from '../common';

const PI = Math.PI;
const H = 0.36, L = 0.14;
const ZAX = new THREE.Vector3(0, 0, 1);

/** Aerogenerador. g = avance de su montaje (0..1): cimentación → torre por tramos → góndola → palas una a una. */
function turbine(b: Builder, c: Ctx, x: number, z: number, ry: number, g: number, sea: boolean, stop: boolean) {
  b.at(x, z, ry, () => {
    if (sea) {
      b.cyl('steelDark', 0, Y0 - 0.03, 0, 0.014, 0.04);
      b.cyl('crane', 0, Y0, 0, 0.017, 0.03, { keep: true });
      b.fine(() => b.box('crane', -0.02, Y0 + 0.026, -0.02, 0.04, 0.004, 0.04));
    } else b.cyl('concreteDark', 0, Y0, 0, 0.03, 0.006, { keep: true });
    const base = sea ? Y0 + 0.03 : Y0;
    const hh = H - (base - Y0);
    const tg = clamp01(g / 0.6), segs = Math.floor(tg * 3 + 1e-6);
    if (segs > 0) b.part('taper12', 'white', 0, base, 0, 0.03, (hh * segs) / 3, 0.03, { keep: true });
    if (g >= 0.7 && !b.lost(0.15)) {
      b.box('white', 0, Y0 + H - 0.004, -0.012, 0.024, 0.024, 0.06, { keep: true });
      b.part('sphere', 'white', 0, Y0 + H + 0.008, 0.022, 0.02, 0.02, 0.026);
      const blades = g >= 1 ? 3 : Math.floor(((g - 0.75) / 0.25) * 3 + 1e-6);
      const speed = stop ? 0 : 1.0 + c.rng() * 0.35, ph = c.rng() * 6;
      for (let i = 0; i < blades; i++) {
        if (b.lost(0.3)) continue;
        b.part('blade', 'white', 0, Y0 + H + 0.008, 0.03, L, L, L, {
          rz: ph + (i * 2 * PI) / 3, keep: true,
          anim: speed ? { k: 'spin', axis: ZAX, speed, phase: 0 } : undefined,
        });
      }
      if (c.running) b.blink('lightWarn', 0, Y0 + H + 0.016, -0.03, 0.005, 2, c.rng(), 0.35);
    }
  });
}

function layout(c: Ctx, n: number, exclude: (x: number, z: number) => boolean): [number, number][] {
  const slots: { p: [number, number]; k: number }[] = [];
  for (let i = -1; i <= 1; i++) for (let j = -1; j <= 1; j++) {
    const x = i * 0.32 + (c.rng() - 0.5) * 0.06, z = -0.08 + j * 0.29 + (c.rng() - 0.5) * 0.05;
    if (exclude(x, z)) continue;
    slots.push({ p: [x, z], k: Math.hypot(x, z + 0.08) + c.rng() * 0.25 });
  }
  slots.sort((a, b) => a.k - b.k);
  return slots.slice(0, n).map((s) => s.p);
}

function farm(b: Builder, c: Ctx, sea: boolean) {
  const n = sea ? Math.max(2, Math.min(8, Math.round(c.s.capacityMw / 40))) : Math.max(1, Math.min(8, Math.round(c.s.capacityMw / 10)));
  const pos = layout(c, n, (x, z) => x > 0.2 && z > 0.12);
  const wind = (c.rng() - 0.5) * 0.6;
  const failing = c.s.stage === 'falla' ? Math.floor(c.rng() * n) : -1;
  // caminos internos (en tierra)
  if (!sea && c.ph(0, 0.1) > 0) {
    for (let i = 1; i < pos.length; i++) {
      let best = 0, bd = 9;
      for (let j = 0; j < i; j++) { const d = Math.hypot(pos[i][0] - pos[j][0], pos[i][1] - pos[j][1]); if (d < bd) { bd = d; best = j; } }
      const a = pos[i], e = pos[best];
      b.box('gravel', (a[0] + e[0]) / 2, Y0, (a[1] + e[1]) / 2, 0.016, 0.003, bd, { ry: Math.atan2(e[0] - a[0], e[1] - a[1]), keep: true });
    }
    b.box('gravel', 0.32, Y0, 0.12, 0.016, 0.003, 0.2, { keep: true });
  }
  let craneAt = -1;
  pos.forEach(([x, z], i) => {
    const s = 0.1 + (i / n) * 0.65;
    const g = c.building ? clamp01((c.s.progress - s) / 0.25) : 1;
    if (c.building && c.s.progress < s - 0.08) return;
    if (g > 0 && g < 1 && craneAt < 0) craneAt = i;
    if (c.building && !sea) b.cyl('dirt', x + 0.03, Y0, z + 0.03, 0.085, 0.003, { keep: true });
    turbine(b, c, x, z, wind, g, sea, i === failing);
    if (i === failing) c.hot = b.pt(x, Y0 + H, z);
  });
  if (c.building && craneAt >= 0) {
    const [x, z] = pos[craneAt];
    if (sea) {
      b.at(x + 0.09, z + 0.03, 0.3, () => {
        for (const sx of [-1, 1]) for (const sz of [-1, 1]) b.cyl('steelDark', sx * 0.06, Y0 - 0.02, sz * 0.035, 0.006, 0.2);
        b.box('white', 0, Y0 + 0.04, 0, 0.15, 0.022, 0.09);
        b.box('crane', 0.02, Y0 + 0.062, 0.0, 0.05, 0.003, 0.05);
      });
      b.at(x + 0.09, z + 0.03, 0.3, () => building(b, -0.05, 0, 0.04, 0.04, 0.06), 0.042);
      b.at(x + 0.09, z + 0.03, 0.3, () => crawlerCrane(b, 0.02, 0, PI, 0.42, 1.3), 0.042);
      boat(b, x - 0.12, z + 0.12, 0.8, 0.1);
    } else {
      crawlerCrane(b, x + 0.06, z + 0.06, PI * 0.75, 0.46, 1.32);
      truck(b, x - 0.06, z + 0.08, 0.6, 'blade');
    }
  }
  if (!sea) trees(b, c, 6, (x, z) => pos.some((p) => Math.hypot(p[0] - x, p[1] - z) < 0.09) || (x > 0.15 && z > 0.15));
}

function offshoreSubstation(b: Builder, c: Ctx) {
  const p = c.ph(0.55, 0.95);
  if (p <= 0) return;
  b.at(0.34, 0.32, 0.2, () => {
    for (const sx of [-1, 1]) for (const sz of [-1, 1]) b.cyl('crane', sx * 0.04, Y0 - 0.02, sz * 0.035, 0.007, 0.075);
    if (p > 0.4) {
      b.box('white', 0, Y0 + 0.055, 0, 0.12, 0.05, 0.1);
      b.box('transformer', 0.02, Y0 + 0.105, -0.01, 0.06, 0.02, 0.05);
      b.box('steelDark', -0.04, Y0 + 0.105, 0.02, 0.05, 0.004, 0.05);
      b.fine(() => b.cyl('lightAmber', -0.04, Y0 + 0.109, 0.02, 0.016, 0.001, { m: 'glow', seg: 8 }));
      if (c.running) b.blink('lightOk', 0.055, Y0 + 0.13, 0.04, 0.006, 1.2);
    }
  });
}

export const eolica_tierra: PlantDef = {
  label: 'Eólica en tierra', pin: 'viento', survey: 'mast', sub: [0.34, 0.37, 0], typicalMw: 60, clear: 0,
  build: (b, c) => farm(b, c, false),
};

export const eolica_mar: PlantDef = {
  label: 'Eólica marina', pin: 'viento', survey: 'buoy', terrain: 'sea', sub: null, typicalMw: 300,
  build(b, c) { farm(b, c, true); offshoreSubstation(b, c); },
};
