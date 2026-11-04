import { Y0 } from '../kit';
import type { PlantDef } from '../types';
import { building, excavator, scaffRing, fanCooler, tank, towerCrane, trees, truck } from '../common';

const PI = Math.PI;

export const solar_fv: PlantDef = {
  label: 'Solar FV', pin: 'solar', survey: 'solar', sub: [0.3, 0.36, 0], typicalMw: 100,
  build(b, c) {
    const cap = c.s.capacityMw;
    const rows = Math.max(4, Math.min(10, Math.round(4 + cap / 35)));
    const tables = Math.max(3, Math.min(6, Math.round(2.5 + cap / 60)));
    const x0 = -0.4, x1 = 0.4, z0 = -0.4, z1 = 0.12;
    const dz = (z1 - z0) / (rows - 1), tw = (x1 - x0) / tables - 0.014;
    const posts = c.ph(0.1, 0.55) * rows, panels = c.ph(0.3, 0.95) * rows;
    const inside = (x: number, z: number) => Math.abs(x) + Math.abs(z) < 0.74 && Math.abs(x) < 0.5 && !(x > 0.12 && z > 0.0);
    if (c.running || c.s.stage === 'abandonado') b.box('gravel', 0, Y0, 0.2, 0.86, 0.003, 0.03, { keep: true });
    let postRow = -1, panelRow = -1;
    for (let r = 0; r < rows; r++) {
      const z = z0 + r * dz;
      for (let t = 0; t < tables; t++) {
        const cx = x0 + (t + 0.5) * (x1 - x0) / tables;
        if (!inside(cx + Math.sign(cx) * tw / 2, z - 0.04)) continue;
        const k = r * tables + t;
        if (k < posts * tables) {
          postRow = r;
          b.fine(() => { for (const s of [-1, 1]) b.box('steelDark', cx + s * tw * 0.4, Y0, z, 0.005, 0.03, 0.005); });
          b.box('steelDark', cx, Y0 + 0.028, z, tw, 0.004, 0.006);
        }
        if (k < panels * tables) {
          panelRow = r;
          if (b.lost(0.25)) continue;
          b.box('panel', cx, Y0 + 0.024, z, tw, 0.005, 0.07, { m: 'gloss', rx: -0.42 });
          b.fine(() => b.box('panelFrame', cx, Y0 + 0.021, z, tw + 0.004, 0.003, 0.074, { rx: -0.42 }));
        }
      }
      if (r % 2 === 0 && c.ph(0.7, 0.95) * rows > r) b.box('white', x1 + 0.035, Y0, z + dz / 2, 0.025, 0.022, 0.018);
    }
    if (c.building && c.s.progress < 1) {
      if (postRow >= 0 && posts < rows) excavator(b, x0 + 0.1 + c.rng() * 0.5, z0 + Math.min(postRow + 1, rows - 1) * dz, PI);
      if (panelRow >= 0 && panels < rows) truck(b, 0.1, z0 + panelRow * dz + dz / 2, 0, 'panels');
    }
    trees(b, c, 5, (x, z) => z < 0.2 || x > 0.15);
    c.hot = b.pt(x1 + 0.035, Y0 + 0.03, z0 + dz / 2);
  },
};

export const csp: PlantDef = {
  label: 'Solar CSP', pin: 'solar', survey: 'solar', sub: [0.34, 0.36, 0], typicalMw: 100,
  build(b, c) {
    const tx = 0, tz = -0.1, H = 0.44;
    const rings = Math.max(3, Math.min(6, Math.round(2 + c.s.capacityMw / 40)));
    // torre
    const tp = c.ph(0.05, 0.5);
    b.cyl('concreteDark', tx, Y0, tz, 0.05, 0.006);
    if (tp > 0) {
      b.part('taper8', 'concrete', tx, Y0, tz, 0.07, H * tp, 0.07, { keep: true });
      if (tp < 1) {
        scaffRing(b, tx, Y0 + H * tp - 0.02, tz, 0.032, 0.01);
        towerCrane(b, tx + 0.07, tz + 0.03, H + 0.06, 2.4, 0.22);
      }
    }
    if (c.ph(0.5, 0.6) >= 1) {
      b.cyl('receiver', tx, Y0 + H, tz, 0.03, 0.05);
      if (c.running) b.cyl('hot', tx, Y0 + H + 0.006, tz, 0.032, 0.04, { m: 'glow', keep: true, anim: { k: 'pulse', speed: 2.2, amp: 0.05, phase: 0 } });
      b.cyl('steel', tx, Y0 + H + 0.05, tz, 0.022, 0.012);
      b.blink('lightWarn', tx, Y0 + H + 0.068, tz, 0.006, 1.5);
    }
    // campo de heliostatos, anillo por anillo
    const hp = c.ph(0.35, 0.95) * rings;
    for (let k = 0; k < rings; k++) {
      const r = 0.1 + k * 0.058, n = Math.floor((2 * PI * r) / 0.048);
      const filled = Math.min(1, hp - k);
      if (filled <= 0) break;
      for (let i = 0; i < n * filled; i++) {
        const a = (i + (k % 2) * 0.5) / n * 2 * PI;
        const x = tx + Math.cos(a) * r, z = tz + Math.sin(a) * r;
        if ((z > 0.15 && Math.abs(x) < 0.32) || Math.hypot(x, z) > 0.54) continue;
        if (b.lost(0.3)) continue;
        const ry = Math.atan2(tx - x, tz - z);
        b.fine(() => b.box('steelDark', x, Y0, z, 0.004, 0.02, 0.004));
        b.box('mirror', x, Y0 + 0.016, z, 0.034, 0.003, 0.028, { m: 'gloss', ry, rx: 0.55 });
      }
    }
    // bloque de potencia y almacenamiento de sales
    building(b, -0.1, 0.32, 0.15, 0.06, 0.08, { p: c.ph(0.2, 0.8) });
    tank(b, 0.08, 0.28, 0.035, 0.045, c.ph(0.3, 0.7), 'tank');
    tank(b, 0.165, 0.28, 0.035, 0.045, c.ph(0.35, 0.75), 'steel');
    const fans = fanCooler(b, -0.1, 0.205, 3, 0, c.ph(0.5, 0.85));
    if (c.running) for (const f of fans) b.puffs('steam', f[0], f[1], f[2], { n: 4, size: 0.03, rise: 0.14, life: 2.6 });
    if (c.building && c.s.progress < 1) truck(b, 0.2, 0.14, 0.4, 'box');
    c.hot = b.pt(tx, Y0 + H + 0.03, tz);
  },
};
