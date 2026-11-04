import { useEffect, useRef } from 'react';
import { gameData } from '@voltaje/data';
import type { World } from '../world/loadWorld';
import { Globe } from './Globe';
import { ui } from '../ui/store';

let globeRef: Globe | null = null;
export const getGlobe = () => globeRef;

export function GlobeView({ world }: { world: World }) {
  const canvas = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const g = new Globe(canvas.current!, world);
    globeRef = g;
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
      if (s.layerId !== prev.layerId || s.layerOpacity !== prev.layerOpacity || s === prev) {
        g.setLayer(gameData.layers.find((l) => l.id === s.layerId) ?? null, s.layerOpacity);
      }
      if (s.selected !== prev.selected) g.setSelection(s.selected);
      prev = s;
    };
    sync();
    const unsub = ui.subscribe(sync);
    return () => { unsub(); g.dispose(); globeRef = null; };
  }, [world]);

  return <canvas ref={canvas} style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', display: 'block', cursor: 'grab' }} />;
}
