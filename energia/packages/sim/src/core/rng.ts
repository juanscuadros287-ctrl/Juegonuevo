/**
 * Generador pseudoaleatorio determinista: xoshiro128** (Blackman & Vigna).
 * Estado de 4 × uint32, serializable. Nunca usar Math.random() en el motor.
 */
export type RngState = [number, number, number, number];

/** splitmix32: expande una semilla de 32 bits en un estado bien mezclado. */
function splitmix32(seed: number): () => number {
  let s = seed >>> 0;
  return () => {
    s = (s + 0x9e3779b9) >>> 0;
    let z = s;
    z = Math.imul(z ^ (z >>> 16), 0x85ebca6b) >>> 0;
    z = Math.imul(z ^ (z >>> 13), 0xc2b2ae35) >>> 0;
    return (z ^ (z >>> 16)) >>> 0;
  };
}

/** Hash FNV-1a de 32 bits de un texto. */
export function hashString(text: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) {
    h ^= text.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}

/** Estado inicial de un flujo de RNG derivado de la semilla de la partida y el nombre del subsistema. */
export function seedStream(seed: number, stream: string): RngState {
  const sm = splitmix32((seed ^ hashString(stream)) >>> 0);
  const s: RngState = [sm(), sm(), sm(), sm()];
  if ((s[0] | s[1] | s[2] | s[3]) === 0) s[0] = 1;
  return s;
}

const rotl = (x: number, k: number) => ((x << k) | (x >>> (32 - k))) >>> 0;

/** Avanza el estado (lo modifica) y devuelve un uint32. */
export function nextU32(s: RngState): number {
  const result = Math.imul(rotl(Math.imul(s[1], 5) >>> 0, 7), 9) >>> 0;
  const t = (s[1] << 9) >>> 0;
  s[2] ^= s[0];
  s[3] ^= s[1];
  s[1] ^= s[2];
  s[0] ^= s[3];
  s[2] ^= t;
  s[3] = rotl(s[3], 11);
  s[0] >>>= 0; s[1] >>>= 0; s[2] >>>= 0; s[3] >>>= 0;
  return result;
}

/** Envoltorio cómodo sobre un estado (el estado sigue viviendo en GameState). */
export class Rng {
  constructor(public readonly state: RngState) {}
  /** Uniforme en [0, 1). */
  next(): number {
    return nextU32(this.state) / 4294967296;
  }
  range(min: number, max: number): number {
    return min + (max - min) * this.next();
  }
  int(min: number, maxInclusive: number): number {
    return min + Math.floor(this.next() * (maxInclusive - min + 1));
  }
  chance(p: number): boolean {
    return this.next() < p;
  }
  /** Normal estándar (Box-Muller). */
  normal(mean = 0, sd = 1): number {
    const u = 1 - this.next();
    const v = this.next();
    return mean + sd * Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
  }
  /** Triangular (min, moda, max): útil para plazos y costos. */
  triangular(min: number, mode: number, max: number): number {
    const u = this.next();
    const f = (mode - min) / (max - min);
    return u < f ? min + Math.sqrt(u * (max - min) * (mode - min)) : max - Math.sqrt((1 - u) * (max - min) * (max - mode));
  }
  pick<T>(items: readonly T[]): T {
    return items[Math.floor(this.next() * items.length)];
  }
}
