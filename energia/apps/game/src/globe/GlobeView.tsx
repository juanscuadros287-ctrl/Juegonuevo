import { useEffect, useRef } from 'react';
import { gameData } from '@voltaje/data';
import type { World } from '../world/loadWorld';
import { Globe } from './Globe';
import { ui } from '../ui/store';
import { SiteLayer } from './sites';

let globeRef: Globe | null = null;
let sitesRef: SiteLayer | null = null;
export const getGlobe = () => globeRef;
export const getSites = () => sitesRef;

export function GlobeView({ world }: { world: World }) {
  const canvas = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const g = new Globe(canvas.current!, world);
    globeRef = g;
    const sites = new SiteLayer(g);
    sitesRef = sites;
    sites.onPick = (id) => { if (ui.get().screen === 'game') ui.openProject(id); };
    sites.onPickRival = (id) => { if (ui.get().screen === 'game') ui.openPanel('competitors', id); };
    // gancho para la prueba de humo (tools/screenshots.mjs): mover la cámara y ubicar sitios
    (window as unknown as { __voltaje?: object }).__voltaje = {
      flyTo: (lat: number, lon: number, d: number, s = 0.1) => g.flyTo(lat, lon, d, s),
      siteScreenPos: (id: string) => sites.screenPos(id),
      rivalSites: () => sites.rivalIds(),
    };
    const home = world.grid.countriesByCode.get(gameData.game.pais_inicial);
    g.jumpTo(home?.lat ?? 0, (home?.lon ?? 0) + 40, 3.4);
    g.onPick = ({ lat, lon }) => {
      if (ui.get().screen !== 'game') return;
      const c = world.grid.cell(lat, lon);
      ui.set({ selected: { lat: c.lat, lon: c.lon } });
    };
    let prev = ui.get();
    const sync = () => {
      const s = ui.get();
      g.autoRotate = s.screen === 'menu';
      // ventanas grandes o diálogos tapan el globo: se redibuja a ~4 cuadros por segundo
      g.throttleMs = s.screen === 'game' && (s.window || s.developAt || s.bidFor || s.dialog) ? 250 : 0;
      if (s.layerId !== prev.layerId || s.layerOpacity !== prev.layerOpacity || s === prev) {
        g.setLayer(gameData.layers.find((l) => l.id === s.layerId) ?? null, s.layerOpacity);
      }
      if (s.selected !== prev.selected) g.setSelection(s.selected);
      if (s.views !== prev.views || s.screen !== prev.screen) sites.sync(s.screen === 'game' ? s.views?.projects ?? [] : [], s.game, s.screen === 'game' ? s.views?.business?.competitors : null);
      prev = s;
    };
    sync();
    const unsub = ui.subscribe(sync);
    return () => { unsub(); sites.dispose(); g.dispose(); globeRef = null; sitesRef = null; };
  }, [world]);

  return <canvas ref={canvas} style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', display: 'block', cursor: 'grab' }} />;
}
