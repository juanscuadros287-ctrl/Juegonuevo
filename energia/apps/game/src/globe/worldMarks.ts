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
import { gameData } from '@voltaje/data';
import { glyphOf, isGrave, kindOf } from '../ui/power/worldLabels';

/** Halo suave (resaltado de la región afectada). */
const haloTexture = (color: string) => iconTexture(`halo:${color}`, (g) => {
  const gr = g.createRadialGradient(32, 32, 0, 32, 32, 32);
  gr.addColorStop(0, color + 'cc'); gr.addColorStop(0.55, color + '66'); gr.addColorStop(1, color + '00');
  g.fillStyle = gr; g.fillRect(0, 0, 64, 64);
});

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
  g.beginPath(); g.arc(32, 32, 28, 0, Math.PI * 2); g.fillStyle = col; g.fill();
  g.lineWidth = 4; g.strokeStyle = '#08121e'; g.stroke();
  g.fillStyle = '#08121e'; g.font = 'bold 34px sans-serif'; g.textAlign = 'center'; g.textBaseline = 'middle';
  g.fillText(glyphOf(e), 32, 34);
});

interface Pickable { kind: 'opp' | 'event'; id: string; pos: THREE.Vector3 }

export class WorldMarks {
  private group = new THREE.Group();
  private outlines = new THREE.Group();
  private sprites: { sprite: THREE.Sprite; grave: boolean }[] = [];
  private halos: { sprite: THREE.Sprite; size: number; grave: boolean }[] = [];
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
    const s = THREE.MathUtils.clamp(0.034 * (d / 2.2), 0.016, 0.07);
    for (const h of this.halos) {
      // sin prueba de profundidad (el sprite plano cortaría la esfera): se oculta si queda del otro lado del globo
      h.sprite.visible = h.sprite.position.dot(cam.position) > 1.05;
      h.sprite.scale.setScalar(h.size);
      h.sprite.material.opacity = (h.grave ? 0.45 : 0.3) + 0.25 * pulse;
    }
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
    for (const x of [...this.sprites, ...this.halos]) { x.sprite.material.dispose(); x.sprite.removeFromParent(); }
    this.sprites = [];
    this.halos = [];
    this.pickables = this.pickables.filter((p) => p.kind !== 'event');
    const perCountry = new Map<string, number>();
    for (const e of local) {
      const grave = isGrave(e);
      for (const code of e.countries!) {
        const shape = this.world.shapes.find((s) => s.code === code);
        if (shape) this.outlines.add(outline(shape, kindOf(e.kind).color, grave, 1.0022 + 0.0008 * (perCountry.get(code) ?? 0)));
        const c = region(this.world, code, shape);
        if (!c) continue;
        // varios eventos en el mismo país: íconos uno al lado del otro
        const n = perCountry.get(code) ?? 0;
        perCountry.set(code, n + 1);
        if (n === 0) {
          const halo = new THREE.Sprite(new THREE.SpriteMaterial({ map: haloTexture(kindOf(e.kind).color), depthWrite: false, depthTest: false, transparent: true }));
          halo.position.copy(lonLatToVec3(c.lon, c.lat, 1.004));
          halo.renderOrder = 1;
          this.group.add(halo);
          this.halos.push({ sprite: halo, size: THREE.MathUtils.clamp((c.extentDeg * Math.PI) / 180 * 1.3, 0.05, 0.25), grave });
        }
        const pos = lonLatToVec3(c.lon + n * 2.2, c.lat, 1.014);
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
  pickAt(x: number, y: number, radius = 16): boolean {
    let best: Pickable | null = null, bestD = radius;
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

  /** Íconos de eventos en pantalla (pruebas). */
  eventScreenPos() {
    return this.pickables.filter((x) => x.kind === 'event').map((p) => ({ uid: p.id, pos: [p.pos.x, p.pos.y, p.pos.z], screen: this.globe.toScreen(p.pos), scale: this.sprites[0]?.sprite.scale.x, visible: this.sprites[0]?.sprite.visible, parent: !!this.sprites[0]?.sprite.parent?.parent }));
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

/** Centro y tamaño de la región afectada: la zona del país si tiene (Texas en EE. UU.) o el polígono más grande. */
function region(world: World, code: string, shape?: CountryShape): { lat: number; lon: number; extentDeg: number } | null {
  const z = gameData.simData.countries[code]?.zona;
  if (z) return { lat: (z.lat_min + z.lat_max) / 2, lon: (z.lon_min + z.lon_max) / 2, extentDeg: Math.max(z.lat_max - z.lat_min, z.lon_max - z.lon_min) };
  let best: number[] | null = null;
  for (const poly of shape?.polys ?? []) if (poly[0] && (!best || poly[0].length > best.length)) best = poly[0];
  if (best) {
    let a = 90, b = -90, c = 180, d = -180;
    for (let i = 0; i < best.length; i += 2) { c = Math.min(c, best[i]); d = Math.max(d, best[i]); a = Math.min(a, best[i + 1]); b = Math.max(b, best[i + 1]); }
    return { lat: (a + b) / 2, lon: (c + d) / 2, extentDeg: Math.min(b - a, (d - c) * Math.cos(((a + b) / 2) * Math.PI / 180)) * 1.6 };
  }
  const g = world.grid.countriesByCode.get(code);
  return g ? { lat: g.lat, lon: g.lon, extentDeg: 6 } : null;
}
