import * as THREE from 'three';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import type { LayerDef } from '@voltaje/data';
import type { World } from '../world/loadWorld';
import { theme } from '../theme/theme';
import { buildBaseTexture, buildLandMask, buildLayerTexture } from './textures';
import { lonLatToVec3, vec3ToLonLat } from './geo';

const vertex = /* glsl */ `
  varying vec3 vPos;
  varying vec3 vWorld;
  void main() {
    vPos = position;
    vec4 w = modelMatrix * vec4(position, 1.0);
    vWorld = w.xyz;
    gl_Position = projectionMatrix * viewMatrix * w;
  }
`;

const fragment = /* glsl */ `
  #define PI 3.141592653589793
  uniform sampler2D uBase;
  uniform sampler2D uLayer;
  uniform sampler2D uMask;
  uniform float uLayerMode;   // 0 sin capa, 1 tierra, 2 mar
  uniform float uLayerOpacity;
  uniform float uGrid;        // 0..1 intensidad de la cuadrícula
  uniform float uCells;       // celdas por 360°
  uniform vec4 uSel;          // lat0, lat1, lon0, lon1 (grados); lat0 > 90 = sin selección
  uniform vec3 uSelColor;
  uniform vec3 uSunDir;
  uniform float uAmbient;
  uniform float uSun;
  varying vec3 vPos;
  varying vec3 vWorld;

  void main() {
    vec3 n = normalize(vPos);
    float lat = asin(clamp(n.y, -1.0, 1.0));
    float lon = atan(-n.z, n.x);
    vec2 uv = vec2((lon + PI) / (2.0 * PI), (lat + PI * 0.5) / PI);

    vec3 col = texture2D(uBase, uv).rgb;
    if (uLayerMode > 0.5) {
      vec4 lay = texture2D(uLayer, uv);
      float land = smoothstep(0.3, 0.7, texture2D(uMask, uv).r);
      float m = uLayerMode < 1.5 ? land : 1.0 - land;
      col = mix(col, lay.rgb, lay.a * m * uLayerOpacity);
    }

    // cuadrícula de celdas de recurso (visible al acercarse)
    if (uGrid > 0.01) {
      vec2 cell = vec2(uv.x * uCells, uv.y * uCells * 0.5);
      vec2 f = abs(fract(cell) - 0.5);
      vec2 fw = fwidth(cell);
      float line = 1.0 - min(smoothstep(0.5 - fw.x * 1.2, 0.5, f.x) + smoothstep(0.5 - fw.y * 1.2, 0.5, f.y), 1.0);
      col = mix(col, col * 0.55, (1.0 - line) * uGrid);
    }

    // celda seleccionada
    float latD = degrees(lat), lonD = degrees(lon);
    if (uSel.x < 90.5 && latD >= uSel.y && latD <= uSel.x && lonD >= uSel.z && lonD <= uSel.w) {
      vec2 fw = fwidth(vec2(lonD, latD)) * 2.0;
      float edge = step(lonD, uSel.z + fw.x) + step(uSel.w - fw.x, lonD) + step(latD, uSel.y + fw.y) + step(uSel.x - fw.y, latD);
      col = edge > 0.0 ? uSelColor : mix(col, uSelColor, 0.18);
    }

    // sombreado plano (estética low-poly): normal de la faceta
    vec3 fn = normalize(cross(dFdx(vWorld), dFdy(vWorld)));
    float diff = max(dot(fn, normalize(uSunDir)), 0.0);
    col *= uAmbient + uSun * diff;
    gl_FragColor = vec4(col, 1.0);
    #include <colorspace_fragment>
  }
`;

export interface PickResult { lat: number; lon: number }

/** Globo 3D interactivo. Solo dibuja: no conoce reglas del juego. */
export class Globe {
  private renderer: THREE.WebGLRenderer;
  readonly scene = new THREE.Scene();
  readonly camera: THREE.PerspectiveCamera;
  private controls: OrbitControls;
  private material: THREE.ShaderMaterial;
  private globe: THREE.Mesh;
  private layerCache = new Map<string, THREE.DataTexture>();
  private raf = 0;
  private flight: { from: THREE.Vector3; to: THREE.Vector3; t: number; dur: number } | null = null;
  private down: { x: number; y: number } | null = null;
  private resizeObs: ResizeObserver;
  autoRotate = false;
  onPick: (p: PickResult) => void = () => {};
  /** Antes de elegir una celda: si devuelve true el clic lo consumió otro objeto (p. ej. un sitio). */
  onPickScreen: (x: number, y: number) => boolean = () => false;
  /** Llamadas por cuadro (animación de objetos sobre el globo). */
  readonly frameHooks = new Set<(dt: number, camera: THREE.PerspectiveCamera) => void>();
  onZoom: (distance: number) => void = () => {};

  constructor(private canvas: HTMLCanvasElement, private world: World) {
    const g = theme.globe;
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;

    this.camera = new THREE.PerspectiveCamera(40, 1, 0.01, 100);
    this.camera.position.set(0, 0, 3.2);

    // Texturas de mapa: 8192 px en Apple Silicon (costas nítidas al acercarse), 4096 si la GPU no da más.
    const texSize = Math.min(8192, this.renderer.capabilities.maxTextureSize);
    this.material = new THREE.ShaderMaterial({
      vertexShader: vertex,
      fragmentShader: fragment,
      uniforms: {
        uBase: { value: buildBaseTexture(world.grid, world.shapes, texSize) },
        uLayer: { value: null },
        uMask: { value: buildLandMask(world.shapes, texSize) },
        uLayerMode: { value: 0 },
        uLayerOpacity: { value: g.layerOpacity },
        uGrid: { value: 0 },
        uCells: { value: world.grid.width },
        uSel: { value: new THREE.Vector4(999, 0, 0, 0) },
        uSelColor: { value: new THREE.Color(g.selection) },
        uSunDir: { value: new THREE.Vector3(0.6, 0.5, 1) },
        uAmbient: { value: g.ambient },
        uSun: { value: g.sun },
      },
    });
    this.globe = new THREE.Mesh(new THREE.IcosahedronGeometry(1, theme.globeDetail), this.material);
    this.scene.add(this.globe);
    this.scene.add(this.buildBorders());
    this.scene.add(this.buildAtmosphere());
    this.scene.add(this.buildStars());

    this.controls = new OrbitControls(this.camera, canvas);
    this.controls.enableDamping = true;
    this.controls.dampingFactor = 0.08;
    this.controls.enablePan = false;
    this.controls.minDistance = 1.08;
    this.controls.maxDistance = 6;
    this.controls.zoomSpeed = 0.8;
    this.controls.addEventListener('start', () => { this.flight = null; this.lastInput = performance.now(); });
    this.controls.addEventListener('change', () => (this.lastInput = performance.now()));

    canvas.addEventListener('pointerdown', this.handleDown);
    canvas.addEventListener('pointerup', this.handleUp);
    this.resizeObs = new ResizeObserver(() => this.resize());
    this.resizeObs.observe(canvas);
    this.resize();
    this.loop();
  }

  private buildBorders(): THREE.LineSegments {
    const pts: number[] = [];
    const a = new THREE.Vector3(), b = new THREE.Vector3();
    for (const s of this.world.shapes) for (const poly of s.polys) for (const ring of poly) {
      for (let i = 0; i < ring.length; i += 2) {
        const j = (i + 2) % ring.length;
        if (Math.abs(ring[i] - ring[j]) > 180) continue;
        lonLatToVec3(ring[i], ring[i + 1], 1.0008, a);
        lonLatToVec3(ring[j], ring[j + 1], 1.0008, b);
        pts.push(a.x, a.y, a.z, b.x, b.y, b.z);
      }
    }
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.Float32BufferAttribute(pts, 3));
    return new THREE.LineSegments(geo, new THREE.LineBasicMaterial({ color: theme.globe.border, transparent: true, opacity: theme.globe.borderOpacity }));
  }

  private buildAtmosphere(): THREE.Mesh {
    const mat = new THREE.ShaderMaterial({
      uniforms: { uColor: { value: new THREE.Color(theme.globe.atmosphere) } },
      vertexShader: `varying vec3 vN; varying vec3 vV;
        void main(){ vec4 mv = modelViewMatrix * vec4(position,1.0); vN = normalize(normalMatrix*normal); vV = normalize(-mv.xyz); gl_Position = projectionMatrix*mv; }`,
      fragmentShader: `uniform vec3 uColor; varying vec3 vN; varying vec3 vV;
        void main(){ float f = pow(1.0 - abs(dot(vN, vV)), 3.0); gl_FragColor = vec4(uColor, f * 0.9); }`,
      side: THREE.BackSide,
      transparent: true,
      depthWrite: false,
      blending: THREE.AdditiveBlending,
    });
    return new THREE.Mesh(new THREE.SphereGeometry(1.09, 64, 32), mat);
  }

  private buildStars(): THREE.Points {
    const n = 1800, pos = new Float32Array(n * 3);
    for (let i = 0; i < n; i++) {
      const v = new THREE.Vector3().randomDirection().multiplyScalar(40 + Math.random() * 20);
      pos.set([v.x, v.y, v.z], i * 3);
    }
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    return new THREE.Points(geo, new THREE.PointsMaterial({ color: 0xbcd3ff, size: 0.12, sizeAttenuation: true, transparent: true, opacity: 0.7 }));
  }

  private handleDown = (e: PointerEvent) => { this.down = { x: e.clientX, y: e.clientY }; };
  private handleUp = (e: PointerEvent) => {
    if (!this.down || Math.hypot(e.clientX - this.down.x, e.clientY - this.down.y) > 5) return;
    this.down = null;
    const r = this.canvas.getBoundingClientRect();
    if (this.onPickScreen(e.clientX - r.left, e.clientY - r.top)) return;
    const ndc = new THREE.Vector2(((e.clientX - r.left) / r.width) * 2 - 1, -((e.clientY - r.top) / r.height) * 2 + 1);
    const ray = new THREE.Raycaster();
    ray.setFromCamera(ndc, this.camera);
    const hit = ray.ray.intersectSphere(new THREE.Sphere(new THREE.Vector3(), 1), new THREE.Vector3());
    if (hit) this.onPick(vec3ToLonLat(hit));
  };

  private resize() {
    const w = this.canvas.clientWidth, h = this.canvas.clientHeight;
    if (!w || !h) return;
    this.renderer.setSize(w, h, false);
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
  }

  private lastDist = -1;
  private lastFrame = performance.now();
  private lastInput = 0;
  /**
   * Con una ventana grande abierta el globo casi no se ve: se dibuja como mucho cada `throttleMs`
   * (salvo durante un vuelo de cámara o mientras el jugador lo mueve). Ahorra CPU/batería.
   */
  throttleMs = 0;
  private loop = () => {
    this.raf = requestAnimationFrame(this.loop);
    const now = performance.now();
    if (this.throttleMs > 0 && !this.flight && now - this.lastInput > 800 && now - this.lastFrame < this.throttleMs) return;
    const dt = Math.min(0.1, (now - this.lastFrame) / 1000);
    this.lastFrame = now;
    const dist = this.camera.position.length();
    if (this.flight) {
      const f = this.flight;
      f.t = Math.min(1, f.t + dt / f.dur);
      const k = f.t < 0.5 ? 2 * f.t * f.t : 1 - (-2 * f.t + 2) ** 2 / 2;
      const dir = f.from.clone().normalize().lerp(f.to.clone().normalize(), k).normalize();
      const len = THREE.MathUtils.lerp(f.from.length(), f.to.length(), k) + Math.sin(Math.PI * k) * 0.35 * f.from.angleTo(f.to);
      this.camera.position.copy(dir.multiplyScalar(len));
      if (f.t >= 1) this.flight = null;
    } else if (this.autoRotate) {
      this.camera.position.applyAxisAngle(new THREE.Vector3(0, 1, 0), 0.07 * dt);
    }
    // girar más lento cerca de la superficie
    this.controls.rotateSpeed = Math.max(0.05, Math.min(1, (dist - 1) * 0.7));
    this.controls.update();
    const grid = THREE.MathUtils.clamp((1.75 - dist) / 0.45, 0, 1);
    this.material.uniforms.uGrid.value = grid * 0.7;
    if (Math.abs(dist - this.lastDist) > 0.002) { this.lastDist = dist; this.onZoom(dist); }
    // el sol sigue a la cámara (siempre se ve la cara iluminada) con un leve desfase
    this.material.uniforms.uSunDir.value.copy(this.camera.position).normalize().add(new THREE.Vector3(0.35, 0.45, 0)).normalize();
    for (const h of this.frameHooks) h(dt, this.camera);
    this.renderer.render(this.scene, this.camera);
  };

  /** Proyecta un punto 3D a píxeles del lienzo; null si está detrás del globo. */
  toScreen(p: THREE.Vector3): { x: number; y: number } | null {
    const cam = this.camera.position;
    // oculto si la normal del punto mira en sentido contrario a la cámara
    if (p.clone().normalize().dot(cam.clone().sub(p).normalize()) < 0.02) return null;
    const v = p.clone().project(this.camera);
    return { x: ((v.x + 1) / 2) * this.canvas.clientWidth, y: ((1 - v.y) / 2) * this.canvas.clientHeight };
  }

  setLayer(layer: LayerDef | null, opacity = theme.globe.layerOpacity) {
    const u = this.material.uniforms;
    if (!layer) { u.uLayerMode.value = 0; return; }
    let tex = this.layerCache.get(layer.id);
    if (!tex) { tex = buildLayerTexture(this.world.grid, layer); this.layerCache.set(layer.id, tex); }
    u.uLayer.value = tex;
    u.uLayerMode.value = layer.aplica === 'tierra' ? 1 : 2;
    u.uLayerOpacity.value = opacity;
  }

  setSelection(cell: { lat: number; lon: number } | null) {
    const res = this.world.grid.res;
    const v = this.material.uniforms.uSel.value as THREE.Vector4;
    if (!cell) v.set(999, 0, 0, 0);
    else v.set(cell.lat + res / 2, cell.lat - res / 2, cell.lon - res / 2, cell.lon + res / 2);
  }

  /** Vuela la cámara hasta un punto. `distance` es la distancia al centro (1 = superficie). */
  flyTo(lat: number, lon: number, distance = this.camera.position.length(), seconds = 1.4) {
    const to = lonLatToVec3(lon, lat, Math.max(this.controls.minDistance, distance));
    this.flight = { from: this.camera.position.clone(), to, t: 0, dur: seconds };
  }

  jumpTo(lat: number, lon: number, distance: number) {
    this.camera.position.copy(lonLatToVec3(lon, lat, distance));
    this.flight = null;
  }

  zoomBy(factor: number) {
    const d = THREE.MathUtils.clamp(this.camera.position.length() * factor, this.controls.minDistance, this.controls.maxDistance);
    const { lat, lon } = vec3ToLonLat(this.camera.position);
    this.flyTo(lat, lon, d, 0.35);
  }

  dispose() {
    cancelAnimationFrame(this.raf);
    this.resizeObs.disconnect();
    this.canvas.removeEventListener('pointerdown', this.handleDown);
    this.canvas.removeEventListener('pointerup', this.handleUp);
    this.controls.dispose();
    this.renderer.dispose();
  }
}
