import { useEffect, useRef } from 'react';
import { gameData } from '@voltaje/data';
import type { World } from '../world/loadWorld';
import { Globe } from './Globe';
import { ui } from '../ui/store';
import { SiteLayer } from './sites';
import { lonLatToVec3 } from './geo';
import { CountryHighlight, type CountryMark } from './countries';
import { WorldMarks } from './worldMarks';

let globeRef: Globe | null = null;
let sitesRef: SiteLayer | null = null;
export const getGlobe = () => globeRef;
export const getSites = () => sitesRef;
let worldRef: World | null = null;
/** Centro aproximado de un país de la grilla (para volar la cámara). */
export const countryCenter = (code: string): { lat: number; lon: number } | null => {
  const c = worldRef?.grid.countriesByCode.get(code);
  return c ? { lat: c.lat, lon: c.lon } : null;
};

export function GlobeView({ world }: { world: World }) {
  const canvas = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const g = new Globe(canvas.current!, world);
    worldRef = world;
    globeRef = g;
    const sites = new SiteLayer(g);
    sitesRef = sites;
    sites.onPick = (id) => { if (ui.get().screen === 'game') ui.openProject(id); };
    sites.onPickRival = (id) => { if (ui.get().screen === 'game') ui.openPanel('competitors', id); };
    // Fase 5: oportunidades y eventos del mundo (los sitios tienen prioridad en el clic)
    const marks = new WorldMarks(g, world);
    marks.onPickOpportunity = (id) => { if (ui.get().screen === 'game') ui.openPanel('market', id); };
    marks.onPickEvent = () => { if (ui.get().screen === 'game') ui.openPanel('world'); };
    const sitesPick = g.onPickScreen;
    // un marcador justo bajo el cursor (9 px: el tamaño del ícono) gana; si no, los sitios; si no, la celda
    g.onPickScreen = (x, y) => (ui.get().screen === 'game' && marks.pickAt(x, y, 9)) || sitesPick(x, y);
    // gancho para la prueba de humo (tools/screenshots.mjs): mover la cámara y ubicar sitios
    const w = window as unknown as { __voltaje?: object };
    w.__voltaje = Object.assign(w.__voltaje ?? {}, {
      flyTo: (lat: number, lon: number, d: number, s = 0.1) => g.flyTo(lat, lon, d, s),
      siteScreenPos: (id: string) => sites.screenPos(id),
      rivalSites: () => sites.rivalIds(),
      oppScreenPos: (id: string) => marks.oppScreenPos(id),
      eventScreenPos: () => marks.eventScreenPos(),
      geoScreenPos: (lat: number, lon: number) => g.toScreen(lonLatToVec3(lon, lat, 1)),
    });
    const highlight = new CountryHighlight(g.scene, world.shapes);
    const home = world.grid.countriesByCode.get(gameData.game.pais_inicial);
    g.jumpTo(home?.lat ?? 0, (home?.lon ?? 0) + 40, 3.4);
    let lastPick = { t: 0, code: '' };
    g.onPick = ({ lat, lon }) => {
      const st = ui.get();
      if (st.screen !== 'game') return;
      const c = world.grid.cell(lat, lon);
      // eligiendo el extremo final de una línea: el clic fija el punto y vuelve al diálogo
      if (st.pickingRoute && st.developAt) {
        ui.set({ pickingRoute: false, developAt: { ...st.developAt, to: { lat: c.lat, lon: c.lon } } });
        return;
      }
      // doble clic sobre un país con datos → su ficha
      const code = c.country?.code ?? '';
      const now = performance.now();
      if (code && code === lastPick.code && now - lastPick.t < 450 && gameData.simData.countries[code]) {
        lastPick = { t: 0, code: '' };
        ui.openCountry(code);
        return;
      }
      lastPick = { t: now, code };
      ui.set({ selected: { lat: c.lat, lon: c.lon } });
    };
    let prev = ui.get();
    const sync = () => {
      const s = ui.get();
      g.autoRotate = s.screen === 'menu';
      // ventanas grandes o diálogos tapan el globo: se redibuja a ~4 cuadros por segundo
      g.throttleMs = s.screen === 'game' && (s.window || (s.developAt && !s.pickingRoute) || s.bidFor || s.dialog) ? 250 : 0;
      if (s.layerId !== prev.layerId || s.layerOpacity !== prev.layerOpacity || s === prev) {
        g.setLayer(gameData.layers.find((l) => l.id === s.layerId) ?? null, s.layerOpacity);
      }
      if (s.selected !== prev.selected) g.setSelection(s.selected);
      // ruta prevista de una línea (diálogo «Desarrollar»)
      const plan = s.developAt?.to ? { from: s.developAt, to: s.developAt.to } : null;
      const planChanged = plan?.to !== (prev.developAt?.to ?? null) || (!!s.developAt) !== (!!prev.developAt);
      if (planChanged) sites.plannedRoute = plan ? { from: { lat: plan.from.lat, lon: plan.from.lon }, to: plan.to, progress: 0, color: '#ffcb3d', dashed: true } : null;
      if (s.views?.business?.countries !== prev.views?.business?.countries || s.screen !== prev.screen) {
        const marks: Record<string, CountryMark> = {};
        if (s.screen === 'game') for (const c of s.views?.business?.countries ?? []) {
          marks[c.iso3] = c.presence === 'origen' || c.presence === 'activa' ? 'presencia' : c.presence === 'en_tramite' ? 'tramite' : c.unlocked ? 'desbloqueado' : 'cerrado';
        }
        highlight.set(marks);
      }
      if (s.views?.power !== prev.views?.power || s.screen !== prev.screen) {
        const p = s.screen === 'game' ? s.views?.power : null;
        marks.setOpportunities(p?.oppMarks ?? []);
        marks.setEvents(p?.worldActive ?? []);
      }
      if (s.views !== prev.views || s.screen !== prev.screen || planChanged) sites.sync(s.screen === 'game' ? s.views?.projects ?? [] : [], s.game, s.screen === 'game' ? s.views?.business?.competitors : null);
      prev = s;
    };
    sync();
    const unsub = ui.subscribe(sync);
    return () => { unsub(); marks.dispose(); sites.dispose(); highlight.dispose(); g.dispose(); globeRef = null; sitesRef = null; };
  }, [world]);

  return <canvas ref={canvas} style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', display: 'block', cursor: 'grab' }} />;
}
