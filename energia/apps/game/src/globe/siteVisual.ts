/**
 * Adaptador único entre los proyectos del motor y los modelos 3D (src/models).
 * Si cambia la API de los modelos, solo se toca este archivo.
 */
import * as THREE from 'three';
import type { ProjectStage } from '@voltaje/sim';
import { createPlant, placeOnGlobe, PLANT_KINDS, type PlantKind, type PlantObject, type PlantStage } from '../models';

export interface SiteView {
  /** techId del motor (solar_fv, eolica_tierra…). */
  kind: string;
  capacityMw: number;
  stage: ProjectStage;
  /** Avance de obra 0–1 (ProjectSummary.buildProgress). */
  progress: number;
  seed: number;
  /** Planta con una falla en curso (salida forzada). */
  failing?: boolean;
}

export interface SiteVisual {
  object: THREE.Object3D;
  update(view: SiteView): void;
  animate(dt: number): void;
  /** Ajusta el nivel de detalle según la distancia cámara→sitio. */
  setCameraDistance(d: number): void;
  place(lat: number, lon: number): void;
  dispose(): void;
}

/** Etapa del motor → etapa visual del modelo. */
export function visualStage(stage: ProjectStage, failing = false): PlantStage {
  switch (stage) {
    case 'identificado': return 'prospeccion';
    case 'estudios': case 'permisos': case 'cierre_financiero': return 'estudios';
    case 'construccion': case 'puesta_en_marcha': return 'construccion';
    case 'operacion': return failing ? 'falla' : 'operacion';
    default: return 'abandonado';
  }
}

/** Color por etapa (el mismo que usa la UI en ui/stages.ts). */
export const STAGE_COLORS: Record<ProjectStage, string> = {
  identificado: '#94a3b8', estudios: '#60a5fa', permisos: '#a78bfa', cierre_financiero: '#f472b6',
  construccion: '#fbbf24', puesta_en_marcha: '#fb923c', operacion: '#4ade80',
  vendido: '#64748b', abandonado: '#64748b', desmantelado: '#64748b',
};

const SCALE = 0.008;
const RING_IN = 0.66, RING_OUT = 0.76;

function toPlantState(v: SiteView) {
  const kind = ((PLANT_KINDS as string[]).includes(v.kind) ? v.kind : 'solar_fv') as PlantKind;
  const progress = v.stage === 'puesta_en_marcha' ? 1 : Math.max(0, Math.min(1, v.progress));
  return { kind, capacityMw: v.capacityMw, stage: visualStage(v.stage, v.failing), progress, seed: v.seed };
}

/** Fracción del anillo: avance de obra; completo en operación; un cuarto mientras se desarrolla. */
function ringFraction(v: SiteView): number {
  if (v.stage === 'operacion') return 1;
  if (v.stage === 'construccion' || v.stage === 'puesta_en_marcha') return Math.max(0.03, v.progress);
  return 0.25;
}

export function createSiteVisual(view: SiteView): SiteVisual {
  const root = new THREE.Group();
  const plant: PlantObject = createPlant(toPlantState(view));
  const bgMat = new THREE.MeshBasicMaterial({ color: 0x0b1b2b, transparent: true, opacity: 0.55, side: THREE.DoubleSide, depthWrite: false });
  const ringMat = new THREE.MeshBasicMaterial({ color: STAGE_COLORS[view.stage], side: THREE.DoubleSide, depthWrite: false });
  const ringBg = new THREE.Mesh(new THREE.RingGeometry(RING_IN, RING_OUT, 48), bgMat);
  const ring = new THREE.Mesh(new THREE.RingGeometry(RING_IN, RING_OUT, 48), ringMat);
  for (const m of [ringBg, ring]) { m.rotation.x = -Math.PI / 2; m.position.y = 0.03; m.renderOrder = 2; }
  ring.position.y = 0.032;
  root.add(plant, ringBg, ring);
  let ringKey = '';
  let detail = -1;

  const visual: SiteVisual = {
    object: root,
    update(v) {
      plant.update(toPlantState(v));
      const frac = ringFraction(v);
      const key = `${v.stage}|${Math.round(frac * 100)}`;
      if (key === ringKey) return;
      ringKey = key;
      ringMat.color.set(STAGE_COLORS[v.stage]);
      ring.geometry.dispose();
      // el anillo empieza al norte (−Z) y avanza en sentido horario visto desde arriba
      ring.geometry = new THREE.RingGeometry(RING_IN, RING_OUT, 48, 1, Math.PI / 2, -Math.PI * 2 * frac);
    },
    animate(dt) { plant.animate(dt); },
    setCameraDistance(d) {
      const lvl = d > 0.35 ? 0 : d > 0.16 ? 1 : 2;
      if (lvl !== detail) { detail = lvl; plant.setDetail(lvl); }
      // de lejos el pin crece un poco para seguir siendo visible
      const k = lvl === 0 ? Math.min(2.4, Math.max(1, d / 0.35)) : 1;
      root.scale.setScalar(SCALE * k);
    },
    place(lat, lon) { placeOnGlobe(root, lat, lon, SCALE); },
    dispose() {
      plant.dispose();
      ring.geometry.dispose(); ringMat.dispose();
      ringBg.geometry.dispose(); bgMat.dispose();
      root.removeFromParent();
    },
  };
  visual.update(view);
  return visual;
}
