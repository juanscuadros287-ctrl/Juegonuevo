/**
 * Fase 5: marcadores sobre el globo
 * - oportunidades del mercado (`OpportunityView.location`, aproximada): rombo celeste (ámbar si ya ofertaste); clic → Mercado;
 * - eventos del mundo activos: contorno pulsante del país afectado con el color del tipo de evento y un ícono en su centro
 *   (los globales no se marcan en el mapa: van en la barra y en la ventana Mundo). Clic en el ícono → Mundo.
 */
import * as THREE from 'three';
import type { WorldEventView } from '@voltaje/sim';
import type { CountryShape, World } from '../world/loadWorld';
import type { OpportunityMark } from '../worker/protocol';
import type { Globe } from './Globe';
import { lonLatToVec3 } from './geo';
import { glyphOf, isGrave, kindOf } from '../ui/power/worldLabels';

const texCache = new Map<string, THREE.Texture>();
function iconTexture(key: string, draw: (g: CanvasRenderingContext2D) => void): THREE.Texture {
  let t = texCache.get(key);
  if (t) return t;
  const c = document.createElement('canvas');
  c.width = c.height = 64;
  draw(c.getContext('2d')!);
  t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  texCache.set(key, t);
  return t;
}

const oppTexture = (mine: boolean) => iconTexture(`opp:${mine}`, (g) => {
  g.translate(32, 32);
  g.rotate(Math.PI / 4);
  g.fillStyle = 'rgba(8,18,30,.85)';
  g.fillRect(-17, -17, 34, 34);
  g.fillStyle = mine ? '#ffcb3d' : '#60a5fa';
  g.fillRect(-13, -13, 26, 26);
  g.rotate(-Math.PI / 4);
  g.fillStyle = '#08121e';
  g.font = 'bold 22px sans-serif';
  g.textAlign = 'center'; g.textBaseline = 'middle';
  g.fillText(mine ? '✓' : '$', 0, 1);
});

const eventTexture = (e: Pick<WorldEventView, 'id' | 'kind'>) => iconTexture(`ev:${e.id}:${e.kind}`, (g) => {
  const col = kindOf(e.kind).color;
  g.beginPath(); g.arc(32, 32, 27, 0, Math.PI * 2); g.fillStyle = 'rgba(8,18,30,.9)'; g.fill();
  g.lineWidth = 6; g.strokeStyle = col; g.stroke();
  g.fillStyle = col; g.font = 'bold 30px sans-serif'; g.textAlign = 'center'; g.textBaseline = 'middle';
  g.fillText(glyphOf(e), 32, 34);
});

interface Pickable { kind: 'opp' | 'event'; id: string; pos: THREE.Vector3 }

export class WorldMarks {
  private group = new THREE.Group();
  private outlines = new THREE.Group();
  private sprites: { sprite: THREE.Sprite; grave: boolean }[] = [];
  private pickables: Pickable[] = [];
  private eventKey = '';
  private oppKey = '';
  private t = 0;
  onPickOpportunity: (id: string) => void = () => {};
  onPickEvent: (uid: string) => void = () => {};

  constructor(private globe: Globe, private world: World) {
    globe.scene.add(this.group, this.outlines);
    globe.frameHooks.add(this.frame);
  }

  private frame = (dt: number, cam: THREE.PerspectiveCamera) => {
    this.t += dt;
    // pulso de los contornos y tamaño de los íconos según la distancia
    const pulse = 0.55 + 0.45 * Math.sin(this.t * 3);
    for (const o of this.outlines.children) ((o as THREE.LineSegments).material as THREE.LineBasicMaterial).opacity = (o.userData.grave ? 0.5 : 0.3) + (o.userData.grave ? 0.5 : 0.3) * pulse;
    const d = cam.position.length();
    const s = THREE.MathUtils.clamp(0.022 * (d / 2.2), 0.012, 0.05);
    for (const x of this.sprites) x.sprite.scale.setScalar(x.grave ? s * 1.25 : s);
    for (const c of this.group.children) if (c.userData.opp) c.scale.setScalar(s * 0.75);
  };

  /** Oportunidades abiertas con ubicación. */
  setOpportunities(marks: readonly OpportunityMark[]) {
    const key = marks.map((m) => `${m.id}${m.myBid ? '*' : ''}`).join(',');
    if (key === this.oppKey) return;
    this.oppKey = key;
    for (const c of [...this.group.children]) if (c.userData.opp) { (c as THREE.Sprite).material.dispose(); c.removeFromParent(); }
    this.pickables = this.pickables.filter((p) => p.kind !== 'opp');
    for (const m of marks) {
      const sp = new THREE.Sprite(new THREE.SpriteMaterial({ map: oppTexture(m.myBid), depthWrite: false, sizeAttenuation: true }));
      const pos = lonLatToVec3(m.lon, m.lat, 1.006);
      sp.position.copy(pos);
      sp.userData.opp = m.id;
      sp.renderOrder = 3;
      this.group.add(sp);
      this.pickables.push({ kind: 'opp', id: m.id, pos });
    }
  }

  /** Eventos activos con países (contorno + ícono). */
  setEvents(events: readonly WorldEventView[]) {
    const local = events.filter((e) => e.countries && e.countries.length);
    const key = local.map((e) => `${e.uid}:${e.countries!.join('/')}`).join(',');
    if (key === this.eventKey) return;
    this.eventKey = key;
    for (const o of [...this.outlines.children]) { const l = o as THREE.LineSegments; l.geometry.dispose(); (l.material as THREE.Material).dispose(); l.removeFromParent(); }
    for (const x of this.sprites) { x.sprite.material.dispose(); x.sprite.removeFromParent(); }
    this.sprites = [];
    this.pickables = this.pickables.filter((p) => p.kind !== 'event');
    const perCountry = new Map<string, number>();
    for (const e of local) {
      const grave = isGrave(e);
      for (const code of e.countries!) {
        const shape = this.world.shapes.find((s) => s.code === code);
        if (shape) this.outlines.add(outline(shape, kindOf(e.kind).color, grave, 1.0022 + 0.0008 * (perCountry.get(code) ?? 0)));
        const c = this.world.grid.countriesByCode.get(code);
        if (!c) continue;
        // varios eventos en el mismo país: íconos uno al lado del otro
        const n = perCountry.get(code) ?? 0;
        perCountry.set(code, n + 1);
        const pos = lonLatToVec3(c.lon + n * 1.6, c.lat + 0.8, 1.012);
        const sp = new THREE.Sprite(new THREE.SpriteMaterial({ map: eventTexture(e), depthWrite: false }));
        sp.position.copy(pos);
        sp.renderOrder = 4;
        this.group.add(sp);
        this.sprites.push({ sprite: sp, grave });
        this.pickables.push({ kind: 'event', id: String(e.uid), pos });
      }
    }
  }

  /** Clic: marcador bajo el punto de pantalla (16 px). */
  pickAt(x: number, y: number): boolean {
    let best: Pickable | null = null, bestD = 16;
    for (const p of this.pickables) {
      const s = this.globe.toScreen(p.pos);
      if (!s) continue;
      const d = Math.hypot(s.x - x, s.y - y);
      if (d < bestD) { bestD = d; best = p; }
    }
    if (!best) return false;
    if (best.kind === 'opp') this.onPickOpportunity(best.id); else this.onPickEvent(best.id);
    return true;
  }

  /** Posición en pantalla de un marcador de oportunidad (pruebas). */
  oppScreenPos(id: string) {
    const p = this.pickables.find((x) => x.kind === 'opp' && x.id === id);
    return p ? this.globe.toScreen(p.pos) : null;
  }

  dispose() {
    this.globe.frameHooks.delete(this.frame);
    this.setEvents([]);
    this.setOpportunities([]);
    this.group.removeFromParent();
    this.outlines.removeFromParent();
  }
}

function outline(s: CountryShape, color: string, grave: boolean, r: number): THREE.LineSegments {
  const pts: number[] = [];
  const a = new THREE.Vector3(), b = new THREE.Vector3();
  for (const poly of s.polys) for (const ring of poly) {
    for (let i = 0; i < ring.length; i += 2) {
      const j = (i + 2) % ring.length;
      if (Math.abs(ring[i] - ring[j]) > 180) continue;
      lonLatToVec3(ring[i], ring[i + 1], r, a);
      lonLatToVec3(ring[j], ring[j + 1], r, b);
      pts.push(a.x, a.y, a.z, b.x, b.y, b.z);
    }
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(pts, 3));
  const l = new THREE.LineSegments(geo, new THREE.LineBasicMaterial({ color, transparent: true, opacity: 0.8, depthWrite: false }));
  l.renderOrder = 2;
  l.userData.grave = grave;
  return l;
}
