/**
 * Sitios de proyectos sobre el globo: un modelo por proyecto en su lat/lon (vía siteVisual.ts),
 * nivel de detalle según la distancia y clic para abrir el proyecto.
 */
import * as THREE from 'three';
import type { CompetitorsOverview, GameState, ProjectSummary } from '@voltaje/sim';
import { createModelLights } from '../models';
import type { Globe } from './Globe';
import { createSiteVisual, type SiteVisual } from './siteVisual';
import { lonLatToVec3 } from './geo';
import { rivalColor, stageFromLabel } from '../ui/business/labels';

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
  /** Clic en una planta de un competidor. */
  onPickRival: (competitorId: string) => void = () => {};
  private rivalOwner = new Map<string, string>();

  constructor(private globe: Globe) {
    globe.scene.add(this.group, this.lights);
    this.sun = this.lights.children.find((c): c is THREE.DirectionalLight => c instanceof THREE.DirectionalLight);
    globe.frameHooks.add(this.frame);
    globe.onPickScreen = (x, y) => {
      const id = this.pickAt(x, y);
      if (!id) return false;
      const rival = this.rivalOwner.get(id);
      if (rival) this.onPickRival(rival); else this.onPick(id);
      return true;
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
  sync(projects: readonly ProjectSummary[], state: GameState | null, rivals?: CompetitorsOverview | null) {
    const seen = new Set<string>();
    const put = (id: string, view: Parameters<typeof createSiteVisual>[0], lat: number, lon: number) => {
      seen.add(id);
      const e = this.entries.get(id);
      if (e) { e.visual.update(view); return; }
      const visual = createSiteVisual(view);
      visual.place(lat, lon);
      this.group.add(visual.object);
      this.entries.set(id, { visual, pos: lonLatToVec3(lon, lat, 1) });
    };
    // plantas visibles de los competidores (registros públicos), con su color
    this.rivalOwner.clear();
    rivals?.competitors.forEach((c, i) => {
      for (const p of c.visibleProjects) {
        const key = `rival:${p.id}`;
        this.rivalOwner.set(key, c.id);
        const stage = stageFromLabel(p.stage);
        put(key, { kind: p.techId, capacityMw: p.mw, stage, progress: p.buildProgress, seed: seedOf(p.id), rivalColor: rivalColor(i) }, p.lat, p.lon);
      }
    });
    for (const p of projects) {
      if (p.stage === 'vendido' || p.stage === 'desmantelado') continue;
      const raw = state?.projects.find((x) => x.id === p.id);
      put(p.id, { kind: p.techId, capacityMw: p.mw, stage: p.stage, progress: p.buildProgress, seed: seedOf(p.id), failing: !!raw?.operation?.outages.length, stageProgress: p.stageProgress }, p.lat, p.lon);
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

  /** Ids de las plantas de competidores en el globo (para pruebas). */
  rivalIds() { return [...this.rivalOwner.keys()]; }

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
