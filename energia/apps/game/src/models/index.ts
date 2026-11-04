/**
 * Modelos 3D low-poly de sitios y plantas, generados por código.
 * API pública: createPlant, createTransmissionLine, placeOnGlobe, createModelLights. Ver docs/MODELOS.md.
 */
import * as THREE from 'three';
import { lonLatToVec3 } from '../globe/geo';
import { Builder, Built, Col, PAL, Y0, disposeBuilt, hashStr, makeRng, runAnims } from './kit';
import { connection, excavator, ground, siteOffice, survey, truck } from './common';
import type { Ctx, DetailLevel, PinFamily, PlantDef, PlantKind, PlantStage, PlantVisualState } from './types';
import { csp, solar_fv } from './defs/solar';
import { eolica_mar, eolica_tierra } from './defs/wind';
import { hidro_bombeo, hidro_embalse, hidro_pasada } from './defs/water';
import { biogas, biomasa, carbon, gas, geotermica, nuclear, petroleo, smr } from './defs/thermal';
import { baterias, eficiencia_industrial, hidrogeno, linea_transmision, subestacion } from './defs/grid';

export type { PlantKind, PlantStage, PlantVisualState, DetailLevel, PlantDef, Ctx } from './types';
export { createTransmissionLine, TransmissionLineObject, type TransmissionLineOptions } from './lines';
export { createModelLights, disposeModelCache, registerGeometry } from './kit';

/** Registro de modelos: añadir aquí un PlantDef nuevo (ver docs/MODELOS.md). */
export const PLANT_DEFS: Record<PlantKind, PlantDef> = {
  solar_fv, csp, eolica_tierra, eolica_mar, geotermica, hidro_pasada, hidro_embalse, hidro_bombeo,
  biomasa, biogas, nuclear, smr, gas, carbon, petroleo, baterias, hidrogeno, subestacion, linea_transmision, eficiencia_industrial,
};
export const PLANT_KINDS = Object.keys(PLANT_DEFS) as PlantKind[];
export const PLANT_STAGES: PlantStage[] = ['prospeccion', 'estudios', 'construccion', 'operacion', 'falla', 'abandonado'];

/** Sitio de casetas de obra por tipo (donde no estorba). */
const SITE: Partial<Record<PlantKind, [number, number, number]>> = {
  hidro_pasada: [0.36, -0.3, -0.3], biomasa: [0.12, 0.3, 0], carbon: [0.12, 0.3, 0], eolica_tierra: [-0.42, 0.36, 0.3],
  linea_transmision: [-0.3, -0.3, 0.2], subestacion: [0.38, 0.4, 0.3], eficiencia_industrial: [-0.38, 0.3, 0.3],
};

function normalize(s: PlantVisualState): PlantVisualState {
  return {
    kind: s.kind,
    capacityMw: Math.max(0, Number.isFinite(s.capacityMw) ? s.capacityMw : 0),
    stage: s.stage,
    progress: THREE.MathUtils.clamp(Number.isFinite(s.progress) ? s.progress : 0, 0, 1),
    seed: Math.floor(s.seed) >>> 0,
  };
}

function buildPlant(s: PlantVisualState): Built {
  const def = PLANT_DEFS[s.kind];
  const b = new Builder(makeRng((s.seed ^ 0x9e3779b9) >>> 0));
  b.abandoned = s.stage === 'abandonado';
  b.animOn = s.stage === 'operacion' || s.stage === 'falla';
  const building = s.stage === 'construccion';
  const c: Ctx = {
    s,
    rng: makeRng((s.seed * 2654435761) ^ hashStr(s.kind)),
    building,
    running: b.animOn,
    ph: (a, e) => (building ? THREE.MathUtils.clamp((s.progress - a) / (e - a), 0, 1) : 1),
    count: (per, min, max) => Math.max(min, Math.min(max, Math.round(s.capacityMw / per))),
  };
  ground(b, c, def);
  if (def.base) {
    b.animOn = s.stage !== 'abandonado';
    def.base(b, c);
    b.animOn = c.running;
  }
  if (s.stage === 'prospeccion' || s.stage === 'estudios') {
    survey(b, c, def.survey, def.terrain === 'sea');
  } else {
    def.build(b, c);
    if (def.sub) connection(b, c, ...def.sub);
    if (building && s.progress < 1 && def.terrain !== 'sea') {
      const [x, z, ry] = SITE[s.kind] ?? [-0.4, 0.34, 0.4];
      siteOffice(b, c, x, z, ry);
      // movimiento de tierras al inicio de la obra
      if (s.progress < 0.2) {
        excavator(b, 0.06, 0.06, c.rng() * 6);
        truck(b, -0.1, 0.14, c.rng() * 6, 'gravel');
      }
    }
    if (s.stage === 'falla') {
      const h = c.hot ?? new THREE.Vector3(0, Y0 + 0.1, 0);
      b.puffs('smokeDark', h.x, h.y + 0.01, h.z, { n: 8, size: 0.05, rise: 0.3, life: 3, drift: [0.06, 0.03] });
      b.blink('lightWarn', h.x, h.y + 0.035, h.z, 0.014, 0.8, 0, 0.5);
    }
  }
  return b.finish();
}

const PIN_STAGE = PAL.stage as Record<PlantStage, string>;
function buildPin(family: PinFamily, stage: PlantStage): Built {
  const b = new Builder(() => 1);
  b.animOn = stage !== 'abandonado' && stage !== 'operacion';
  const col = (PAL.pin as Record<PinFamily, string>)[family] as Col;
  b.cyl('white', 0, 0, 0, 0.018, 0.42, { seg: 6 });
  b.cyl(PIN_STAGE[stage] as Col, 0, 0.4, 0, 0.17, 0.03, { seg: 6 });
  b.cyl(col, 0, 0.43, 0, 0.15, 0.07, { seg: 6 });
  b.part('cone6', col, 0, 0.5, 0, 0.14, 0.06, 0.14);
  if (stage === 'falla') b.blink('lightWarn', 0, 0.6, 0, 0.04, 0.8);
  if (stage === 'construccion') b.part('ball', 'crane', 0, 0.6, 0, 0.06, 0.06, 0.06, { m: 'glow', anim: { k: 'pulse', speed: 4, amp: 0.25, phase: 0 } });
  return b.finish();
}

/** Planta 3D: THREE.Group con update(state), animate(dt), setDetail(nivel) y dispose(). */
export class PlantObject extends THREE.Group {
  state!: PlantVisualState;
  private built: Built | null = null;
  private pin: Built | null = null;
  private key = '';
  private detail: DetailLevel = 2;
  private t = 0;

  constructor(state: PlantVisualState) {
    super();
    this.update(state);
  }

  /** Reconstruye solo si cambia algo visible (el avance se cuantiza a centésimas). */
  update(state: PlantVisualState) {
    const s = normalize(state);
    const key = `${s.kind}|${s.stage}|${Math.round(s.capacityMw)}|${s.seed}|${s.stage === 'construccion' ? Math.round(s.progress * 100) : 0}`;
    this.state = s;
    if (key === this.key) return;
    const pinKey = this.key.split('|').slice(0, 2).join('|');
    this.key = key;
    this.name = 'planta:' + s.kind;
    if (this.built) disposeBuilt(this.built);
    this.built = buildPlant(s);
    this.add(...this.built.groups);
    if (!this.pin || pinKey !== `${s.kind}|${s.stage}`) {
      if (this.pin) disposeBuilt(this.pin);
      this.pin = buildPin(PLANT_DEFS[s.kind].pin, s.stage);
      this.add(...this.pin.groups);
    }
    this.setDetail(this.detail);
  }

  /** 0 = pin (vista lejana), 1 = estructuras principales, 2 = detalle completo. */
  setDetail(level: DetailLevel) {
    this.detail = level;
    if (this.built) {
      this.built.groups[0].visible = level >= 1;
      this.built.groups[1].visible = level === 2;
    }
    if (this.pin) for (const g of this.pin.groups) g.visible = level === 0;
  }

  getDetail(): DetailLevel { return this.detail; }

  /** Avanza las animaciones (palas, vapor, agua, luces). dt en segundos. */
  animate(dt: number) {
    this.t += dt;
    const src = this.detail === 0 ? this.pin : this.built;
    if (src && src.anims.length) runAnims(src.anims, this.t, src.animMeshes);
  }

  dispose() {
    if (this.built) disposeBuilt(this.built);
    if (this.pin) disposeBuilt(this.pin);
    this.built = this.pin = null;
    this.key = '';
    this.removeFromParent();
  }
}

export function createPlant(state: PlantVisualState): PlantObject {
  return new PlantObject(state);
}

/** Etiqueta, capacidad típica y familia de cada tecnología. */
export function plantInfo(kind: PlantKind) {
  const d = PLANT_DEFS[kind];
  return { label: d.label, typicalMw: d.typicalMw, family: d.pin };
}

const _east = new THREE.Vector3(), _north = new THREE.Vector3(), _n = new THREE.Vector3(), _basis = new THREE.Matrix4();
/**
 * Coloca un objeto sobre el globo (radio 1) en lat/lon (grados), con +Y hacia la normal de la esfera,
 * -Z hacia el norte y +X hacia el este. `scale` = tamaño de 1 unidad local en unidades del globo.
 */
export function placeOnGlobe(obj: THREE.Object3D, lat: number, lon: number, scale: number, lift = 0): THREE.Object3D {
  lonLatToVec3(lon, lat, 1, _n).normalize();
  _east.set(0, 1, 0).cross(_n);
  if (_east.lengthSq() < 1e-10) _east.set(0, 0, -1);
  _east.normalize();
  _north.crossVectors(_n, _east).normalize();
  _basis.makeBasis(_east, _n, _north.negate());
  obj.quaternion.setFromRotationMatrix(_basis);
  obj.position.copy(_n).multiplyScalar(1 + lift);
  obj.scale.setScalar(scale);
  obj.updateMatrixWorld();
  return obj;
}

/** Altura de la superficie del terreno de los modelos (unidades locales). */
export const MODEL_GROUND_Y = Y0;
