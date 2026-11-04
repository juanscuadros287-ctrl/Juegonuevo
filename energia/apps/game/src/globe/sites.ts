/**
 * Sitios de proyectos sobre el globo: un modelo por proyecto en su lat/lon (vía siteVisual.ts),
 * nivel de detalle según la distancia y clic para abrir el proyecto.
 */
import * as THREE from 'three';
import type { GameState, ProjectSummary } from '@voltaje/sim';
import { createModelLights } from '../models';
import type { Globe } from './Globe';
import { createSiteVisual, type SiteVisual } from './siteVisual';
import { lonLatToVec3 } from './geo';

interface Entry { visual: SiteVisual; pos: THREE.Vector3 }

/** Semilla visual estable por proyecto. */
function seedOf(id: string): number {
  let h = 2166136261;
  for (let i = 0; i < id.length; i++) h = Math.imul(h ^ id.charCodeAt(i), 16777619);
  return h >>> 0;
}

export class SiteLayer {
  private group = new THREE.Group();
  // el globo usa un shader sin luces: los modelos necesitan las suyas
  private lights = createModelLights();
  private sun: THREE.DirectionalLight | undefined;
  private entries = new Map<string, Entry>();
  onPick: (projectId: string) => void = () => {};

  constructor(private globe: Globe) {
    globe.scene.add(this.group, this.lights);
    this.sun = this.lights.children.find((c): c is THREE.DirectionalLight => c instanceof THREE.DirectionalLight);
    globe.frameHooks.add(this.frame);
    globe.onPickScreen = (x, y) => {
      const id = this.pickAt(x, y);
      if (id) { this.onPick(id); return true; }
      return false;
    };
  }

  private frame = (dt: number, cam: THREE.PerspectiveCamera) => {
    // la luz direccional sigue a la cámara, como el sol del shader del globo
    this.sun?.position.copy(cam.position).normalize().add(new THREE.Vector3(0.35, 0.45, 0)).multiplyScalar(5);
    for (const e of this.entries.values()) {
      e.visual.setCameraDistance(cam.position.distanceTo(e.pos));
      e.visual.animate(dt);
    }
  };

  /** Sincroniza los modelos con los proyectos (vendidos y desmantelados se quitan). */
  sync(projects: readonly ProjectSummary[], state: GameState | null) {
    const seen = new Set<string>();
    for (const p of projects) {
      if (p.stage === 'vendido' || p.stage === 'desmantelado') continue;
      seen.add(p.id);
      const raw = state?.projects.find((x) => x.id === p.id);
      const view = { kind: p.techId, capacityMw: p.mw, stage: p.stage, progress: p.buildProgress, seed: seedOf(p.id), failing: !!raw?.operation?.outages.length };
      const e = this.entries.get(p.id);
      if (e) { e.visual.update(view); continue; }
      const visual = createSiteVisual(view);
      visual.place(p.lat, p.lon);
      this.group.add(visual.object);
      this.entries.set(p.id, { visual, pos: lonLatToVec3(p.lon, p.lat, 1) });
    }
    for (const [id, e] of this.entries) if (!seen.has(id)) { e.visual.dispose(); this.entries.delete(id); }
  }

  /** Proyecto bajo el punto de pantalla (radio de 22 px). */
  pickAt(x: number, y: number): string | null {
    let best: string | null = null, bestD = 22;
    for (const [id, e] of this.entries) {
      const s = this.globe.toScreen(e.pos);
      if (!s) continue;
      const d = Math.hypot(s.x - x, s.y - y);
      if (d < bestD) { bestD = d; best = id; }
    }
    return best;
  }

  /** Posición en pantalla de un sitio (para pruebas y etiquetas). */
  screenPos(id: string) {
    const e = this.entries.get(id);
    return e ? this.globe.toScreen(e.pos) : null;
  }

  dispose() {
    for (const e of this.entries.values()) e.visual.dispose();
    this.entries.clear();
    this.globe.frameHooks.delete(this.frame);
    this.group.removeFromParent();
    this.lights.removeFromParent();
  }
}
