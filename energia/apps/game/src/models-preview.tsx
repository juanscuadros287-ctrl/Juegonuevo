/**
 * Vista previa de los modelos 3D (models.html): cuadrícula con todas las tecnologías,
 * secuencia de obra, todas las etapas de un tipo y colocación sobre el globo.
 * Expone window.__preview para las capturas automáticas.
 */
import { useEffect, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import * as THREE from 'three';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import './theme/theme.css';
import {
  PLANT_KINDS, PLANT_STAGES, PlantObject, createModelLights, createPlant, createTransmissionLine, placeOnGlobe, plantInfo,
  type DetailLevel, type PlantKind, type PlantStage, type TransmissionLineObject,
} from './models';
import { lonLatToVec3 } from './globe/geo';
import { theme } from './theme/theme';

type Mode = 'cuadricula' | 'secuencia' | 'etapas' | 'globo';
interface Params { mode: Mode; kind: PlantKind; stage: PlantStage; progress: number; capMul: number; seed: number; detail: DetailLevel; animate: boolean; ui: boolean }
const STAGE_LABEL: Record<PlantStage, string> = { prospeccion: 'Prospección', estudios: 'Estudios', construccion: 'Construcción', operacion: 'Operación', falla: 'Falla', abandonado: 'Abandonado' };

class Preview {
  renderer: THREE.WebGLRenderer;
  scene = new THREE.Scene();
  camera = new THREE.PerspectiveCamera(24, 1, 0.001, 200);
  controls: OrbitControls;
  root = new THREE.Group();
  plants: PlantObject[] = [];
  lines: TransmissionLineObject[] = [];
  labels: { el: HTMLDivElement; pos: THREE.Vector3 }[] = [];
  last = performance.now();
  frames = 0;
  p!: Params;

  constructor(private canvas: HTMLCanvasElement, private labelLayer: HTMLDivElement) {
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, preserveDrawingBuffer: true });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.scene.add(createModelLights(), this.root);
    this.controls = new OrbitControls(this.camera, canvas);
    this.controls.enableDamping = true;
    new ResizeObserver(() => this.resize()).observe(canvas);
    this.resize();
    this.loop();
  }

  resize() {
    const w = this.canvas.clientWidth, h = this.canvas.clientHeight;
    if (!w || !h) return;
    this.renderer.setSize(w, h, false);
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
  }

  clear() {
    for (const p of this.plants) p.dispose();
    for (const l of this.lines) l.dispose();
    this.plants = [];
    this.lines = [];
    this.root.clear();
    this.labelLayer.innerHTML = '';
    this.labels = [];
  }

  label(text: string, pos: THREE.Vector3) {
    const el = document.createElement('div');
    el.textContent = text;
    el.style.cssText = 'position:absolute;transform:translate(-50%,0);font-size:12px;font-weight:600;color:#e6eef7;text-shadow:0 1px 3px #000;white-space:nowrap;pointer-events:none';
    this.labelLayer.appendChild(el);
    this.labels.push({ el, pos });
  }

  add(kind: PlantKind, stage: PlantStage, progress: number, x: number, z: number, text: string) {
    const p = this.p;
    const obj = createPlant({ kind, stage, progress, capacityMw: plantInfo(kind).typicalMw * p.capMul, seed: p.seed });
    obj.position.set(x, 0, z);
    obj.setDetail(p.detail);
    this.root.add(obj);
    this.plants.push(obj);
    this.label(text, new THREE.Vector3(x, -0.02, z + 0.68));
  }

  set(p: Params, resetCamera: boolean) {
    this.p = p;
    this.clear();
    this.scene.background = null;
    const cam = (pos: [number, number, number], target: [number, number, number]) => {
      if (!resetCamera) return;
      this.camera.position.set(...pos);
      this.controls.target.set(...target);
      this.controls.update();
    };
    if (p.mode === 'cuadricula') {
      const cols = 5, sp = 1.55;
      PLANT_KINDS.forEach((k, i) => {
        const x = (i % cols - (cols - 1) / 2) * sp, z = (Math.floor(i / cols) - 1.5) * sp * 1.05;
        this.add(k, p.stage, p.progress, x, z, plantInfo(k).label);
      });
      cam([0, 11.2, 9.9], [0, -0.45, 0.3]);
    } else if (p.mode === 'secuencia') {
      [0, 0.33, 0.66, 1].forEach((pr, i) => this.add(p.kind, 'construccion', pr, ((i % 2) - 0.5) * 1.5, (Math.floor(i / 2) - 0.5) * 1.6, `${plantInfo(p.kind).label} · ${Math.round(pr * 100)} %`));
      cam([0, 4.4, 4.8], [0, -0.15, 0.2]);
    } else if (p.mode === 'etapas') {
      PLANT_STAGES.forEach((s, i) => {
        const x = ((i % 3) - 1) * 1.45, z = (Math.floor(i / 3) - 0.5) * 1.6;
        this.add(p.kind, s, p.progress, x, z, STAGE_LABEL[s]);
      });
      cam([0, 4.8, 6.1], [0, -0.15, 0.25]);
    } else {
      // globo: esfera simple + plantas en Panamá, con LOD según distancia
      const globe = new THREE.Mesh(new THREE.IcosahedronGeometry(1, 40), new THREE.MeshStandardMaterial({ color: theme.globe.grass, flatShading: true, roughness: 1 }));
      this.root.add(globe);
      const sites: [PlantKind, number, number][] = [
        ['solar_fv', 7.4, -81.6], ['eolica_tierra', 7.4, -80.4], ['hidro_embalse', 8.6, -81.6], ['subestacion', 8.6, -80.4],
        ['geotermica', 9.8, -81.6], ['baterias', 9.8, -80.4], ['nuclear', 8.6, -79.2], ['eolica_mar', 7.2, -79.2],
      ];
      for (const [k, lat, lon] of sites) {
        const obj = createPlant({ kind: k, stage: p.stage, progress: p.progress, capacityMw: plantInfo(k).typicalMw * p.capMul, seed: p.seed });
        placeOnGlobe(obj, lat, lon, 0.011);
        this.root.add(obj);
        this.plants.push(obj);
      }
      const pts = [[-80.4, 8.95], [-80.55, 9.2], [-80.4, 9.45]].map(([lon, lat]) => lonLatToVec3(lon, lat, 1));
      const line = createTransmissionLine(pts, p.stage === 'construccion' ? p.progress : 1, { up: 'radial', towerHeight: 0.003 });
      this.root.add(line);
      this.lines.push(line);
      const c = lonLatToVec3(-80.6, 8.4, 1);
      const eye = lonLatToVec3(-80.6, 5.6, 1.08);
      if (resetCamera) {
        this.camera.position.copy(eye);
        this.controls.target.copy(c);
        this.camera.up.copy(c.clone().normalize());
        this.controls.update();
      }
    }
    if (p.mode !== 'globo') this.camera.up.set(0, 1, 0);
  }

  loop = () => {
    requestAnimationFrame(this.loop);
    const now = performance.now(), dt = Math.min(0.1, (now - this.last) / 1000);
    this.last = now;
    this.controls.update();
    if (this.p?.mode === 'globo') {
      const d = this.camera.position.distanceTo(this.controls.target);
      const lvl: DetailLevel = this.p.detail < 2 ? this.p.detail : d > 0.35 ? 0 : d > 0.16 ? 1 : 2;
      for (const pl of this.plants) if (pl.getDetail() !== lvl) pl.setDetail(lvl);
      for (const l of this.lines) l.setDetail(lvl);
    }
    if (this.p?.animate !== false) for (const pl of this.plants) pl.animate(dt);
    this.renderer.render(this.scene, this.camera);
    const w = this.canvas.clientWidth, h = this.canvas.clientHeight, v = new THREE.Vector3();
    for (const l of this.labels) {
      v.copy(l.pos).project(this.camera);
      l.el.style.left = `${((v.x + 1) / 2) * w}px`;
      l.el.style.top = `${((1 - v.y) / 2) * h}px`;
      l.el.style.display = v.z < 1 ? '' : 'none';
    }
    this.frames++;
  };

  stats() {
    let calls = 0, inst = 0;
    this.root.traverse((o) => { if ((o as THREE.Mesh).isMesh || (o as THREE.LineSegments).isLineSegments) { if (o.visible && o.parent?.visible) { calls++; inst += (o as THREE.InstancedMesh).count ?? 1; } } });
    return { objects: calls, instances: inst, renderCalls: this.renderer.info.render.calls, triangles: this.renderer.info.render.triangles };
  }
}

/** Prueba de humo: todas las combinaciones de tipo × etapa × avance × capacidad, con update/LOD/animate/dispose. */
function sweep() {
  const errors: string[] = [];
  let n = 0;
  for (const kind of PLANT_KINDS) for (const cap of [0, 0.1, 1, 4]) for (const seed of [1, 99]) {
    const obj = createPlant({ kind, stage: 'prospeccion', progress: 0, capacityMw: plantInfo(kind).typicalMw * cap, seed });
    try {
      for (const stage of PLANT_STAGES) for (const pr of stage === 'construccion' ? [0, 0.05, 0.15, 0.33, 0.5, 0.66, 0.85, 0.95, 1] : [0]) {
        obj.update({ kind, stage, progress: pr, capacityMw: plantInfo(kind).typicalMw * cap, seed });
        for (const d of [0, 1, 2] as DetailLevel[]) { obj.setDetail(d); obj.animate(0.016); }
        n++;
      }
    } catch (e) { errors.push(`${kind} ×${cap}: ${(e as Error).message}`); }
    obj.dispose();
  }
  const line = createTransmissionLine([new THREE.Vector3(0, 0, 0), new THREE.Vector3(1, 0, 0.3), new THREE.Vector3(2, 0, 0)], 0);
  for (const pr of [0, 0.3, 0.6, 0.8, 1]) line.update(undefined, pr);
  line.dispose();
  return { n, errors };
}

const DEFAULT: Params = { mode: 'cuadricula', kind: 'solar_fv', stage: 'operacion', progress: 0.5, capMul: 1, seed: 7, detail: 2, animate: true, ui: true };

function App() {
  const canvas = useRef<HTMLCanvasElement>(null), labels = useRef<HTMLDivElement>(null);
  const prev = useRef<Preview | null>(null);
  const [p, setP] = useState<Params>(DEFAULT);
  const lastMode = useRef<string>('');

  useEffect(() => {
    const pv = new Preview(canvas.current!, labels.current!);
    prev.current = pv;
    (window as unknown as { __preview: unknown }).__preview = {
      set: (q: Partial<Params>) => setP((o) => ({ ...o, ...q })),
      stats: () => pv.stats(),
      frames: () => pv.frames,
      sweep,
    };
  }, []);

  useEffect(() => {
    const pv = prev.current;
    if (!pv) return;
    const camKey = p.mode + (p.mode === 'globo' ? '' : '');
    pv.set(p, camKey !== lastMode.current);
    lastMode.current = camKey;
  }, [p]);

  const up = (q: Partial<Params>) => setP((o) => ({ ...o, ...q }));
  return (
    <div style={{ position: 'relative', width: '100%', height: '100%' }}>
      <canvas ref={canvas} style={{ width: '100%', height: '100%', display: 'block' }} />
      <div ref={labels} style={{ position: 'absolute', inset: 0, pointerEvents: 'none', overflow: 'hidden' }} />
      <div className="panel" style={{ position: 'absolute', top: 12, left: 12, padding: 12, width: 230, display: p.ui ? 'grid' : 'none', gap: 8 }} data-testid="controles">
        <h3>Modelos 3D</h3>
        <div className="row" style={{ flexWrap: 'wrap', gap: 4 }}>
          {(['cuadricula', 'secuencia', 'etapas', 'globo'] as Mode[]).map((m) => (
            <button key={m} className={p.mode === m ? 'active' : ''} onClick={() => up({ mode: m })}>{m}</button>
          ))}
        </div>
        <label>Tecnología
          <select value={p.kind} onChange={(e) => up({ kind: e.target.value as PlantKind })} style={{ width: '100%' }}>
            {PLANT_KINDS.map((k) => <option key={k} value={k}>{plantInfo(k).label}</option>)}
          </select>
        </label>
        <label>Etapa
          <select value={p.stage} onChange={(e) => up({ stage: e.target.value as PlantStage })} style={{ width: '100%' }}>
            {PLANT_STAGES.map((s) => <option key={s} value={s}>{STAGE_LABEL[s]}</option>)}
          </select>
        </label>
        <label>Avance de obra: <span className="mono">{Math.round(p.progress * 100)} %</span>
          <input type="range" min={0} max={1} step={0.01} value={p.progress} onChange={(e) => up({ progress: Number(e.target.value) })} />
        </label>
        <label>Capacidad: <span className="mono">×{p.capMul.toFixed(2)}</span>
          <input type="range" min={0.1} max={4} step={0.05} value={p.capMul} onChange={(e) => up({ capMul: Number(e.target.value) })} />
        </label>
        <label>Semilla <input type="number" value={p.seed} onChange={(e) => up({ seed: Number(e.target.value) })} /></label>
        <div className="row">Detalle
          {([0, 1, 2] as DetailLevel[]).map((d) => <button key={d} className={p.detail === d ? 'active' : ''} onClick={() => up({ detail: d })}>{d}</button>)}
        </div>
        <label className="row"><input type="checkbox" checked={p.animate} onChange={(e) => up({ animate: e.target.checked })} /> Animar</label>
      </div>
    </div>
  );
}

createRoot(document.getElementById('root')!).render(<App />);
