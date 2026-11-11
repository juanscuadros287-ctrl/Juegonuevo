/**
 * Fase 4: contorno de color de los países con datos según la expansión (origen/presencia, en trámite, desbloqueado,
 * cerrado), un poco sobre la superficie y con colores vivos para que se distingan de las fronteras normales.
 */
import * as THREE from 'three';
import type { CountryShape } from '../world/loadWorld';
import { lonLatToVec3 } from './geo';

export type CountryMark = 'presencia' | 'tramite' | 'desbloqueado' | 'cerrado';

export const COUNTRY_MARK_COLORS: Record<CountryMark, string> = {
  presencia: '#4ade80', tramite: '#fbbf24', desbloqueado: '#7cc4ff', cerrado: '#94a3b8',
};
const OPACITY: Record<CountryMark, number> = { presencia: 1, tramite: 1, desbloqueado: 1, cerrado: 0.45 };

export class CountryHighlight {
  readonly group = new THREE.Group();
  private key = '';

  constructor(scene: THREE.Scene, private shapes: CountryShape[]) { scene.add(this.group); }

  /** `marks`: código ISO3 → estado. Solo se reconstruye si cambia. */
  set(marks: Record<string, CountryMark>) {
    const key = Object.entries(marks).sort().map(([k, v]) => `${k}:${v}`).join(',');
    if (key === this.key) return;
    this.key = key;
    this.clear();
    const byMark = new Map<CountryMark, number[]>();
    const a = new THREE.Vector3(), b = new THREE.Vector3();
    for (const s of this.shapes) {
      const m = marks[s.code];
      if (!m) continue;
      const pts = byMark.get(m) ?? [];
      byMark.set(m, pts);
      for (const r of [1.0012]) {
        for (const poly of s.polys) for (const ring of poly) {
          for (let i = 0; i < ring.length; i += 2) {
            const j = (i + 2) % ring.length;
            if (Math.abs(ring[i] - ring[j]) > 180) continue;
            lonLatToVec3(ring[i], ring[i + 1], r, a);
            lonLatToVec3(ring[j], ring[j + 1], r, b);
            pts.push(a.x, a.y, a.z, b.x, b.y, b.z);
          }
        }
      }
    }
    for (const [m, pts] of byMark) {
      const geo = new THREE.BufferGeometry();
      geo.setAttribute('position', new THREE.Float32BufferAttribute(pts, 3));
      const line = new THREE.LineSegments(geo, new THREE.LineBasicMaterial({ color: COUNTRY_MARK_COLORS[m], transparent: true, opacity: OPACITY[m], depthWrite: false }));
      line.renderOrder = 1;
      this.group.add(line);
    }
  }

  private clear() {
    for (const o of [...this.group.children]) {
      const l = o as THREE.LineSegments;
      l.geometry.dispose();
      (l.material as THREE.Material).dispose();
      l.removeFromParent();
    }
  }

  dispose() { this.clear(); this.group.removeFromParent(); }
}
