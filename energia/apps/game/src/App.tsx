import { useEffect, useState } from 'react';
import { gameData } from '@voltaje/data';
import { formatDate, fromEpochDay, type SimEvent } from '@voltaje/sim';
import { loadWorld, type World } from './world/loadWorld';
import { GlobeView, getGlobe } from './globe/GlobeView';
import { MainMenu } from './ui/MainMenu';
import { TopBar } from './ui/TopBar';
import { LayerPanel } from './ui/LayerPanel';
import { Inspector } from './ui/Inspector';
import { Dialogs } from './ui/SaveDialog';
import { Toasts } from './ui/Toasts';
import { DevelopDialog } from './ui/DevelopDialog';
import { ProjectsPanel } from './ui/ProjectsPanel';
import { ProjectWindow } from './ui/project/ProjectWindow';
import { FinancePanel } from './ui/FinancePanel';
import { EventLog } from './ui/EventLog';
import { GameOver } from './ui/GameOver';
import { ui, useUi, type LogEntry, type ToastKind } from './ui/store';
import { sim } from './worker/client';
import { saveGame } from './ui/session';
import { fmtMoney } from './ui/format';

const KIND: Record<string, ToastKind> = { info: 'info', bueno: 'good', malo: 'bad' };
/** Eventos informativos que también merecen notificación (el resto va solo al registro). */
const TOAST_INFO = new Set(['projectCreated', 'studyCompleted', 'permitDecided', 'commissioningStarted', 'saleStarted']);

function useGameEvents() {
  useEffect(() => {
    let months = 0;
    let lastAuto = performance.now();
    const cfg = gameData.game.autoguardado;
    return sim.onEvents((events: SimEvent[]) => {
      const g = sim.state;
      const tick = g?.tick ?? 0;
      const date = g ? formatDate(fromEpochDay(g.startEpochDay + tick), true) : '';
      const log: Omit<LogEntry, 'id'>[] = [];
      for (const e of events) {
        if ('projectId' in e) {
          log.push({ tick, date, text: e.text, severity: e.severity, projectId: e.projectId });
          if (e.severity !== 'info' || TOAST_INFO.has(e.type)) ui.toast(e.text, KIND[e.severity], e.projectId);
          if (e.type === 'projectCreated') ui.openProject(e.projectId);
          continue;
        }
        switch (e.type) {
          case 'newYear': ui.toast(`Comienza ${e.year}`); break;
          case 'cashNegative': {
            const t = `Caja negativa: ${fmtMoney(e.cashUsd)} (${e.monthsNegative} mes(es) seguidos). Sin financiación la empresa quebrará.`;
            log.push({ tick, date, text: t, severity: 'malo' }); ui.toast(t, 'bad'); break;
          }
          case 'emergencyCredit': log.push({ tick, date, text: e.text, severity: 'malo' }); ui.toast(e.text, 'warn'); break;
          case 'bankruptcy': log.push({ tick, date, text: e.text, severity: 'malo' }); ui.setSpeed(null); break;
          case 'commandRejected': ui.toast(e.error, 'warn'); break;
          case 'newMonth':
            months++;
            if (months % cfg.cada_meses === 0 && (performance.now() - lastAuto) / 1000 >= cfg.min_segundos_reales) {
              lastAuto = performance.now();
              saveGame('auto').then(() => ui.toast('Partida guardada automáticamente')).catch(() => {});
            }
            break;
        }
      }
      ui.log(log);
    });
  }, []);
}

function useKeyboard() {
  useEffect(() => {
    let lastSpeed = gameData.game.velocidades[0].id;
    const onKey = (e: KeyboardEvent) => {
      const s = ui.get();
      const tag = (e.target as HTMLElement).tagName;
      if (s.screen !== 'game' || tag === 'INPUT' || tag === 'SELECT' || tag === 'TEXTAREA') return;
      if ((e.metaKey || e.ctrlKey) && e.key === 's') { e.preventDefault(); ui.set({ dialog: 'save' }); return; }
      if (e.metaKey || e.ctrlKey || e.altKey) return;
      if (e.key === ' ') {
        e.preventDefault();
        if (s.speedId) { lastSpeed = s.speedId; ui.setSpeed(null); } else ui.setSpeed(lastSpeed);
      }
      const n = parseInt(e.key, 10);
      if (n >= 1 && n <= gameData.game.velocidades.length) ui.setSpeed(gameData.game.velocidades[n - 1].id);
      const k = e.key.toLowerCase();
      if (k === 'p') ui.openWindow('projects');
      if (k === 'f') ui.openWindow('finance');
      if (k === 'e') ui.openWindow('events');
      if (e.key === 'Escape') {
        if (s.dialog) ui.set({ dialog: null });
        else if (s.developAt) ui.set({ developAt: null });
        else if (s.window) ui.openWindow(null);
        else ui.set({ selected: null });
      }
      if (e.key === '+' || e.key === '=') getGlobe()?.zoomBy(0.8);
      if (e.key === '-') getGlobe()?.zoomBy(1.25);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);
}

function Windows() {
  const w = useUi((s) => s.window);
  if (w === 'projects') return <ProjectsPanel />;
  if (w === 'project') return <ProjectWindow />;
  if (w === 'finance') return <FinancePanel />;
  if (w === 'events') return <EventLog />;
  return null;
}

export function App() {
  const [world, setWorld] = useState<World | null>(null);
  const [error, setError] = useState('');
  const screen = useUi((s) => s.screen);
  // con una ventana grande abierta se ocultan los paneles laterales (el globo sigue visible detrás)
  const win = useUi((s) => s.window);
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
          {!win && <LayerPanel />}
          {!win && <Inspector world={world} />}
          <ZoomButtons />
          <Windows />
          <DevelopDialog />
          <GameOver />
        </>
      )}
      <Dialogs />
      <Toasts />
    </>
  );
}

function ZoomButtons() {
  return (
    <div className="panel" style={{ position: 'absolute', bottom: 16, left: 12, display: 'grid', padding: 4, gap: 4 }}>
      <button onClick={() => getGlobe()?.zoomBy(0.8)} title="Acercar (+)">＋</button>
      <button onClick={() => getGlobe()?.zoomBy(1.25)} title="Alejar (−)">−</button>
    </div>
  );
}
