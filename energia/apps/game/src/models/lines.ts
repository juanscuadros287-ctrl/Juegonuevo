/** Línea de transmisión a lo largo de una polilínea arbitraria (local o sobre el globo). */
import * as THREE from 'three';
import { geo, mat, PAL, PYLON } from './kit';
import type { DetailLevel } from './types';

export interface TransmissionLineOptions {
  /** 'y' = arriba es +Y (modelo local); 'radial' = arriba es la normal de la esfera (puntos sobre el globo). */
  up?: 'y' | 'radial';
  /** Altura de torre en las unidades de los puntos. Por defecto 0.3 (escala de los modelos). */
  towerHeight?: number;
  /** Distancia entre torres. Por defecto 1.3 × altura. */
  spacing?: number;
  /** Flecha del cable como fracción del vano. */
  sag?: number;
}

const _m = new THREE.Matrix4(), _s = new THREE.Matrix4();

export class TransmissionLineObject extends THREE.Group {
  private points: THREE.Vector3[] = [];
  private progress = 1;
  private parts: THREE.Object3D[] = [];
  private far = new THREE.Group();
  private near = new THREE.Group();
  private earth = new THREE.Group();
  private detail: DetailLevel = 2;

  constructor(points: THREE.Vector3[], progress = 1, private opts: TransmissionLineOptions = {}) {
    super();
    this.name = 'linea_transmision';
    this.add(this.far, this.near, this.earth);
    this.update(points, progress);
  }

  /** Cambia el trazado y/o el avance (0..1: torres de una en una, luego el tendido de cables). */
  update(points: THREE.Vector3[] = this.points, progress = this.progress) {
    this.points = points.map((p) => p.clone());
    this.progress = THREE.MathUtils.clamp(progress, 0, 1);
    this.clear3d();
    if (this.points.length < 2) return;
    const h = this.opts.towerHeight ?? 0.3, radial = this.opts.up === 'radial';
    const sagF = this.opts.sag ?? 0.04;
    // longitud acumulada
    const cum = [0];
    for (let i = 1; i < this.points.length; i++) cum.push(cum[i - 1] + this.points[i].distanceTo(this.points[i - 1]));
    const L = cum[cum.length - 1];
    const N = Math.max(1, Math.round(L / (this.opts.spacing ?? h * 1.3)));
    const at = (d: number) => {
      let i = 1;
      while (i < cum.length - 1 && cum[i] < d) i++;
      const a = this.points[i - 1], b = this.points[i];
      const t = (d - cum[i - 1]) / Math.max(1e-9, cum[i] - cum[i - 1]);
      return { p: a.clone().lerp(b, THREE.MathUtils.clamp(t, 0, 1)), dir: b.clone().sub(a).normalize() };
    };
    const towers: { m: THREE.Matrix4; g: number; up: THREE.Vector3 }[] = [];
    for (let i = 0; i <= N; i++) {
      const { p, dir } = at((i / N) * L);
      const up = radial ? p.clone().normalize() : new THREE.Vector3(0, 1, 0);
      const fwd = dir.clone().addScaledVector(up, -up.dot(dir)).normalize();
      const side = new THREE.Vector3().crossVectors(up, fwd).normalize();
      const m = new THREE.Matrix4().makeBasis(side, up, fwd).setPosition(p).multiply(_s.makeScale(h, h, h));
      const start = (i / (N + 1)) * 0.6;
      towers.push({ m, g: THREE.MathUtils.clamp((this.progress - start) / 0.12, 0, 1), up });
    }
    // torres (instanciadas)
    const built = towers.filter((t) => t.g > 0);
    const steel = new THREE.Color(PAL.steel);
    if (built.length) {
      const body = new THREE.InstancedMesh(geo('pylonBody'), mat('solid'), built.length);
      built.forEach((t, i) => { body.setMatrixAt(i, _m.copy(t.m).multiply(_s.makeScale(1, Math.max(0.08, t.g) * 0.97, 1))); body.setColorAt(i, steel); });
      body.computeBoundingSphere();
      this.add3d(this.near, body);
      const done = built.filter((t) => t.g >= 1);
      if (done.length) {
        const head = new THREE.InstancedMesh(geo('pylonHead'), mat('solid'), done.length);
        done.forEach((t, i) => { head.setMatrixAt(i, t.m); head.setColorAt(i, steel); });
        head.computeBoundingSphere();
        this.add3d(this.near, head);
      }
    }
    // cables: tendido vano a vano
    const cond: number[] = [], gw: number[] = [];
    for (let i = 0; i < N; i++) {
      const A = towers[i], B = towers[i + 1];
      if (A.g < 1 || B.g < 1 || this.progress < 0.6 + (0.4 * (i + 1)) / N - 1e-6) continue;
      const up = A.up.clone().add(B.up).normalize();
      PYLON.attach.forEach(([ax, ay], k) => {
        const a = new THREE.Vector3(ax, ay, 0).applyMatrix4(A.m), b = new THREE.Vector3(ax, ay, 0).applyMatrix4(B.m);
        const sag = a.distanceTo(b) * sagF, arr = k === 4 ? gw : cond;
        let prev = a;
        for (let s = 1; s <= 8; s++) {
          const t = s / 8, p = a.clone().lerp(b, t).addScaledVector(up, -4 * sag * t * (1 - t));
          arr.push(prev.x, prev.y, prev.z, p.x, p.y, p.z);
          prev = p;
        }
      });
    }
    const lineMat = new THREE.LineBasicMaterial({ color: PAL.steelDark });
    const mk = (arr: number[], g: THREE.Group) => {
      if (!arr.length) return;
      const bg = new THREE.BufferGeometry();
      bg.setAttribute('position', new THREE.Float32BufferAttribute(arr, 3));
      this.add3d(g, new THREE.LineSegments(bg, lineMat));
    };
    mk(cond, this.near);
    mk(gw, this.earth);
    // vista lejana: trazado simple
    const farPts: number[] = [];
    const last = towers.filter((t) => t.g > 0).length;
    for (let i = 0; i + 1 < last; i++) {
      const a = new THREE.Vector3().setFromMatrixPosition(towers[i].m), b = new THREE.Vector3().setFromMatrixPosition(towers[i + 1].m);
      farPts.push(a.x, a.y, a.z, b.x, b.y, b.z);
    }
    mk(farPts, this.far);
    this.setDetail(this.detail);
  }

  setDetail(level: DetailLevel) {
    this.detail = level;
    this.far.visible = level === 0;
    this.near.visible = level >= 1;
    this.earth.visible = level === 2;
  }

  animate(_dt: number) { /* sin animación */ }

  dispose() { this.clear3d(); this.removeFromParent(); }

  private add3d(g: THREE.Group, o: THREE.Object3D) { g.add(o); this.parts.push(o); }
  private clear3d() {
    for (const o of this.parts) {
      if (o instanceof THREE.InstancedMesh) o.dispose();
      else if (o instanceof THREE.LineSegments) { o.geometry.dispose(); (o.material as THREE.Material).dispose(); }
      o.removeFromParent();
    }
    this.parts = [];
  }
}

/** Torres + cables con catenaria a lo largo de `points`. progress 0..1 = avance de obra. */
export function createTransmissionLine(points: THREE.Vector3[], progress = 1, opts?: TransmissionLineOptions): TransmissionLineObject {
  return new TransmissionLineObject(points, progress, opts);
}
