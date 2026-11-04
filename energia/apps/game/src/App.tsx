import { useEffect, useState } from 'react';
import { gameData } from '@voltaje/data';
import { loadWorld, type World } from './world/loadWorld';
import { GlobeView, getGlobe } from './globe/GlobeView';
import { MainMenu } from './ui/MainMenu';
import { TopBar } from './ui/TopBar';
import { LayerPanel } from './ui/LayerPanel';
import { Inspector } from './ui/Inspector';
import { Dialogs } from './ui/SaveDialog';
import { Toasts } from './ui/Toasts';
import { ui, useUi } from './ui/store';
import { sim } from './worker/client';
import { saveGame } from './ui/session';
import { fmtUsd } from './ui/format';

function useGameEvents() {
  useEffect(() => {
    let months = 0;
    let lastAuto = performance.now();
    const cfg = gameData.game.autoguardado;
    return sim.onEvents((events) => {
      for (const e of events) {
        if (e.type === 'newYear') ui.toast(`Comienza ${e.year}`);
        if (e.type === 'cashNegative') ui.toast(`Caja negativa: ${fmtUsd(e.cashUsd)}. Sin financiación la empresa quebrará.`, 'bad');
        if (e.type === 'commandRejected') ui.toast(e.error, 'warn');
        if (e.type === 'newMonth') {
          months++;
          if (months % cfg.cada_meses === 0 && (performance.now() - lastAuto) / 1000 >= cfg.min_segundos_reales) {
            lastAuto = performance.now();
            saveGame('auto').then(() => ui.toast('Partida guardada automáticamente')).catch(() => {});
          }
        }
      }
    });
  }, []);
}

function useKeyboard() {
  useEffect(() => {
    let lastSpeed = gameData.game.velocidades[0].id;
    const onKey = (e: KeyboardEvent) => {
      const s = ui.get();
      if (s.screen !== 'game' || (e.target as HTMLElement).tagName === 'INPUT') return;
      if ((e.metaKey || e.ctrlKey) && e.key === 's') { e.preventDefault(); ui.set({ dialog: 'save' }); return; }
      if (e.key === ' ') {
        e.preventDefault();
        if (s.speedId) { lastSpeed = s.speedId; ui.setSpeed(null); } else ui.setSpeed(lastSpeed);
      }
      const n = parseInt(e.key, 10);
      if (n >= 1 && n <= gameData.game.velocidades.length) ui.setSpeed(gameData.game.velocidades[n - 1].id);
      if (e.key === 'Escape') ui.set(s.dialog ? { dialog: null } : { selected: null });
      if (e.key === '+' || e.key === '=') getGlobe()?.zoomBy(0.8);
      if (e.key === '-') getGlobe()?.zoomBy(1.25);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);
}

export function App() {
  const [world, setWorld] = useState<World | null>(null);
  const [error, setError] = useState('');
  const screen = useUi((s) => s.screen);
  useGameEvents();
  useKeyboard();

  useEffect(() => {
    loadWorld().then(setWorld).catch((e) => setError(String(e)));
  }, []);

  if (error) return <div style={{ padding: 40, color: 'var(--bad)' }}>Error cargando el mundo: {error}</div>;
  if (!world) return <div style={{ display: 'grid', placeItems: 'center', height: '100%' }} className="dim">Cargando el mundo…</div>;

  return (
    <>
      <GlobeView world={world} />
      {screen === 'menu' && <MainMenu />}
      {screen === 'game' && (
        <>
          <TopBar />
          <LayerPanel />
          <Inspector world={world} />
          <ZoomButtons />
        </>
      )}
      <Dialogs />
      <Toasts />
    </>
  );
}

function ZoomButtons() {
  return (
    <div className="panel" style={{ position: 'absolute', bottom: 16, right: 12, display: 'grid', padding: 4, gap: 4 }}>
      <button onClick={() => getGlobe()?.zoomBy(0.8)} title="Acercar (+)">＋</button>
      <button onClick={() => getGlobe()?.zoomBy(1.25)} title="Alejar (−)">−</button>
    </div>
  );
}
