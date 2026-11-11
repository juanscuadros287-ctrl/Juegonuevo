/**
 * Sitios de proyectos sobre el globo: un modelo por proyecto en su lat/lon (vía siteVisual.ts),
 * nivel de detalle según la distancia y clic para abrir el proyecto.
 */
import * as THREE from 'three';
import { visualKindOf, type CompetitorsOverview, type GameState, type ProjectSummary } from '@voltaje/sim';
import { gameData } from '@voltaje/data';
import { createModelLights } from '../models';
import type { Globe } from './Globe';
import { createSiteVisual, STAGE_COLORS, type SiteVisual } from './siteVisual';
import { RouteLayer, type RouteView } from './routes';
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
  /** Trazados de líneas e interconexiones (proyectos y ruta prevista del diálogo). */
  private routes: RouteLayer;
  /** Ruta prevista del diálogo «Desarrollar» (se dibuja con los proyectos). */
  plannedRoute: RouteView | null = null;

  constructor(private globe: Globe) {
    globe.scene.add(this.group, this.lights);
    this.routes = new RouteLayer(globe.scene);
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
    this.routes.frame(cam);
    for (const e of this.entries.values()) {
      e.visual.setCameraDistance(cam.position.distanceTo(e.pos));
      e.visual.animate(dt);
    }
  };

  /** Sincroniza los modelos con los proyectos (vendidos y desmantelados se quitan). */
  sync(projects: readonly ProjectSummary[], state: GameState | null, rivals?: CompetitorsOverview | null) {
    const seen = new Set<string>();
    const routes = new Map<string, RouteView>();
    if (this.plannedRoute) routes.set('_plan', this.plannedRoute);
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
        put(key, { kind: visualKindOf(gameData.simData.technologies[p.techId]), capacityMw: p.mw, stage, progress: p.buildProgress, seed: seedOf(p.id), rivalColor: rivalColor(i) }, p.lat, p.lon);
      }
    });
    for (const p of projects) {
      if (p.stage === 'vendido' || p.stage === 'desmantelado') continue;
      const raw = state?.projects.find((x) => x.id === p.id);
      const to = raw?.site.extras?.to;
      const isLine = p.visualKind === 'linea_transmision';
      if (isLine && to) {
        // la línea se dibuja a lo largo de su trazado; en el origen queda una subestación (con el anillo de etapa)
        const building = p.stage === 'construccion' || p.stage === 'puesta_en_marcha' || p.stage === 'operacion';
        routes.set(p.id, { from: { lat: p.lat, lon: p.lon }, to, progress: p.stage === 'operacion' ? 1 : building ? p.buildProgress : 0, color: building ? STAGE_COLORS[p.stage] : '#e6eef7', dashed: !building });
      }
      put(p.id, { kind: isLine && to ? 'subestacion' : p.visualKind ?? p.techId, capacityMw: p.mw, stage: p.stage, progress: p.buildProgress, seed: seedOf(p.id), failing: !!raw?.operation?.outages.length, stageProgress: p.stageProgress }, p.lat, p.lon);
    }
    for (const [id, e] of this.entries) if (!seen.has(id)) { e.visual.dispose(); this.entries.delete(id); }
    this.routes.sync(routes);
  }

  /** Proyecto bajo el punto de pantalla (radio de 22 px; las propias primero). */
  pickAt(x: number, y: number): string | null {
    let best: string | null = null, bestD = 22;
    for (const [id, e] of this.entries) {
      const s = this.globe.toScreen(e.pos);
      if (!s) continue;
      // las plantas propias tienen prioridad cuando se superponen con las de un competidor
      const d = Math.hypot(s.x - x, s.y - y) + (this.rivalOwner.has(id) ? 10 : 0);
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
    this.routes.dispose();
  }
}
