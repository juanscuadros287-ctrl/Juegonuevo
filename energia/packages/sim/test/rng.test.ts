import { describe, expect, it } from 'vitest';
import { Rng, seedStream } from '../src';

describe('RNG determinista', () => {
  it('misma semilla y flujo ⇒ misma secuencia', () => {
    const a = new Rng(seedStream(42, 'projects'));
    const b = new Rng(seedStream(42, 'projects'));
    for (let i = 0; i < 1000; i++) expect(a.next()).toBe(b.next());
  });

  it('flujos distintos son independientes', () => {
    const a = new Rng(seedStream(42, 'projects'));
    const b = new Rng(seedStream(42, 'market'));
    let same = 0;
    for (let i = 0; i < 1000; i++) if (a.next() === b.next()) same++;
    expect(same).toBe(0);
  });

  it('uniforme: media ≈ 0,5 y sin sesgo por decil', () => {
    const r = new Rng(seedStream(7, 'world'));
    const bins = new Array(10).fill(0);
    let sum = 0;
    const n = 200_000;
    for (let i = 0; i < n; i++) { const x = r.next(); sum += x; bins[Math.floor(x * 10)]++; }
    expect(sum / n).toBeCloseTo(0.5, 2);
    for (const b of bins) expect(Math.abs(b / n - 0.1)).toBeLessThan(0.005);
  });

  it('chance(p) converge a p', () => {
    const r = new Rng(seedStream(1, 'events'));
    let hits = 0;
    for (let i = 0; i < 100_000; i++) if (r.chance(0.23)) hits++;
    expect(hits / 100_000).toBeCloseTo(0.23, 2);
  });

  it('normal y triangular tienen la media correcta', () => {
    const r = new Rng(seedStream(3, 'ai'));
    let s = 0, t = 0;
    const n = 100_000;
    for (let i = 0; i < n; i++) { s += r.normal(10, 2); t += r.triangular(6, 12, 24); }
    expect(s / n).toBeCloseTo(10, 1);
    expect(t / n).toBeCloseTo((6 + 12 + 24) / 3, 1);
  });

  it('el estado es serializable y continúa igual tras JSON', () => {
    const r = new Rng(seedStream(99, 'world'));
    r.next(); r.next();
    const copy = new Rng(JSON.parse(JSON.stringify(r.state)));
    expect(copy.next()).toBe(r.next());
  });
});
