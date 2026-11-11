/**
 * Fase 4: trazados de líneas e interconexiones sobre el globo (src/models, `createTransmissionLine` en modo radial)
 * más una línea de guía de color (visible de lejos). La usan los proyectos de transmisión y la ruta prevista del
 * diálogo «Desarrollar».
 */
import * as THREE from 'three';
import { createTransmissionLine, type TransmissionLineObject } from '../models';
import { lonLatToVec3 } from './geo';

export interface RouteView {
  from: { lat: number; lon: number };
  to: { lat: number; lon: number };
  /** Avance de obra 0–1 (torres y luego cables). 0 = solo la guía. */
  progress: number;
  color: string;
  /** Guía discontinua (ruta prevista o en desarrollo). */
  dashed: boolean;
}

interface Entry { key: string; group: THREE.Group; line: TransmissionLineObject | null; guide: THREE.Mesh; mid: THREE.Vector3; detail: number }

/** Cinta sobre la esfera a lo largo de `pts` (ancho en unidades del globo); `dashed` deja huecos alternos. */
function ribbon(pts: THREE.Vector3[], width: number, dashed: boolean): THREE.BufferGeometry {
  const pos: number[] = [];
  const half = width / 2;
  const side = (i: number) => {
    const a = pts[Math.max(0, i - 1)], b = pts[Math.min(pts.length - 1, i + 1)];
    return new THREE.Vector3().crossVectors(b.clone().sub(a), pts[i]).normalize().multiplyScalar(half);
  };
  // largo de cada trazo de la línea discontinua ≈ 2 segmentos
  for (let i = 0; i + 1 < pts.length; i++) {
    if (dashed && Math.floor(i / 2) % 2 === 1) continue;
    const s0 = side(i), s1 = side(i + 1);
    const a0 = pts[i].clone().add(s0), a1 = pts[i].clone().sub(s0), b0 = pts[i + 1].clone().add(s1), b1 = pts[i + 1].clone().sub(s1);
    pos.push(a0.x, a0.y, a0.z, a1.x, a1.y, a1.z, b0.x, b0.y, b0.z, a1.x, a1.y, a1.z, b1.x, b1.y, b1.z, b0.x, b0.y, b0.z);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  return g;
}

/** Escala de los modelos del globo (la misma que siteVisual): la altura de torre ≈ 0,27 × escala. */
const SCALE = 0.008;

/** Puntos del gran círculo entre dos coordenadas (cada ~0,2°), a radio `r`. */
export function greatCircle(a: { lat: number; lon: number }, b: { lat: number; lon: number }, r = 1, stepDeg = 0.2): THREE.Vector3[] {
  const va = lonLatToVec3(a.lon, a.lat, 1), vb = lonLatToVec3(b.lon, b.lat, 1);
  const ang = va.angleTo(vb);
  const n = Math.max(2, Math.ceil((ang * 180) / Math.PI / stepDeg));
  const out: THREE.Vector3[] = [];
  for (let i = 0; i <= n; i++) {
    const t = i / n;
    // slerp
    const s = Math.sin(ang) || 1;
    const p = ang < 1e-6 ? va.clone() : va.clone().multiplyScalar(Math.sin((1 - t) * ang) / s).add(vb.clone().multiplyScalar(Math.sin(t * ang) / s));
    out.push(p.normalize().multiplyScalar(r));
  }
  return out;
}

export class RouteLayer {
  readonly group = new THREE.Group();
  private entries = new Map<string, Entry>();

  constructor(scene: THREE.Scene) { scene.add(this.group); }

  /** Reemplaza el conjunto de trazados. */
  sync(routes: Map<string, RouteView>) {
    for (const [id, r] of routes) {
      const key = `${r.from.lat},${r.from.lon},${r.to.lat},${r.to.lon}|${r.color}|${r.dashed}|${Math.round(r.progress * 50)}`;
      const e = this.entries.get(id);
      if (e?.key === key) continue;
      if (e) this.remove(id);
      this.entries.set(id, this.build(key, r));
    }
    for (const id of [...this.entries.keys()]) if (!routes.has(id)) this.remove(id);
  }

  private build(key: string, r: RouteView): Entry {
    const group = new THREE.Group();
    const pts = greatCircle(r.from, r.to, 1.0008, 0.05);
    const guide = new THREE.Mesh(ribbon(pts, 0.0007, r.dashed), new THREE.MeshBasicMaterial({ color: r.color, transparent: true, opacity: 0.9, depthWrite: false, side: THREE.DoubleSide }));
    guide.renderOrder = 3;
    group.add(guide);
    // extremo final: disco del mismo color
    const end = new THREE.Mesh(new THREE.CircleGeometry(0.0009, 20), guide.material);
    end.position.copy(pts[pts.length - 1]);
    end.lookAt(pts[pts.length - 1].clone().multiplyScalar(2));
    end.renderOrder = 3;
    group.add(end);
    let line: TransmissionLineObject | null = null;
    if (r.progress > 0) {
      line = createTransmissionLine(greatCircle(r.from, r.to, 1.0002), r.progress, { up: 'radial', towerHeight: 0.27 * SCALE * 1.6, spacing: 0.27 * SCALE * 1.6 * 2.2 });
      group.add(line);
    }
    this.group.add(group);
    return { key, group, line, guide, mid: pts[Math.floor(pts.length / 2)].clone(), detail: -1 };
  }

  private remove(id: string) {
    const e = this.entries.get(id);
    if (!e) return;
    e.line?.dispose();
    // solo los hijos directos (guía y extremo): las piezas de la línea usan geometrías compartidas del caché de modelos
    for (const o of e.group.children) if (o instanceof THREE.Mesh) o.geometry.dispose();
    (e.guide.material as THREE.Material).dispose();
    e.group.removeFromParent();
    this.entries.delete(id);
  }

  /** Nivel de detalle de las torres según la distancia de la cámara. */
  frame(cam: THREE.PerspectiveCamera) {
    for (const e of this.entries.values()) {
      if (!e.line) continue;
      const d = cam.position.distanceTo(e.mid);
      const lvl = d > 0.5 ? 0 : d > 0.2 ? 1 : 2;
      if (lvl !== e.detail) { e.detail = lvl; e.line.setDetail(lvl as 0 | 1 | 2); e.line.visible = lvl > 0; }
    }
  }

  dispose() {
    for (const id of [...this.entries.keys()]) this.remove(id);
    this.group.removeFromParent();
  }
}
