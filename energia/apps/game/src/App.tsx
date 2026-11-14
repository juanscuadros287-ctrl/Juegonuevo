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
import { MarketPanel } from './ui/business/MarketPanel';
import { ContractsPanel } from './ui/business/ContractsPanel';
import { ResearchPanel } from './ui/business/ResearchPanel';
import { CompetitorsPanel } from './ui/business/CompetitorsPanel';
import { SuppliersPanel } from './ui/business/SuppliersPanel';
import { BidDialog } from './ui/business/BidDialog';
import { CatalogPanel } from './ui/world/CatalogPanel';
import { CountriesPanel } from './ui/world/CountriesPanel';
import { PowerMarketPanel } from './ui/power/PowerMarketPanel';
import { WorldPanel } from './ui/power/WorldPanel';
import { Banners } from './ui/power/Banners';
import { isGrave } from './ui/power/worldLabels';
import { FUELS_PICK, ui, useUi, type LogEntry, type ToastKind, type UiLink } from './ui/store';
import { sim } from './worker/client';
import { loadGame, saveGame } from './ui/session';
import { fmtMoney } from './ui/format';

const KIND: Record<string, ToastKind> = { info: 'info', bueno: 'good', malo: 'bad' };
/** Eventos informativos que también merecen notificación (el resto va solo al registro). */
const TOAST_INFO = new Set(['projectCreated', 'studyCompleted', 'permitDecided', 'commissioningStarted', 'saleStarted', 'bidSubmitted', 'contractSigned', 'researchStarted', 'contractProjectAssigned',
  'presenceRequested', 'presenceOpened', 'presenceClosed', 'wellsDrilled', 'insuranceChanged', 'dispatchPolicyChanged', 'climateOutlook', 'worldEvent']);

/** A qué ventana lleva un evento de negocio (Fase 3). */
function businessLink(e: SimEvent): UiLink | undefined {
  // Fase 5: eventos del mundo y clima → ventana Mundo
  if (e.type === 'worldEvent' || e.type === 'worldEventEnded' || e.type === 'climateOutlook') return { window: 'world' };
  if ('opportunityId' in e && (e.type.startsWith('bid') || e.type.startsWith('opportunity'))) return { window: 'market', id: e.opportunityId };
  if ('contractId' in e) return { window: 'contracts', id: e.contractId };
  if ('nodeId' in e) return { window: 'research', id: e.nodeId };
  if ('competitorId' in e) return { window: 'competitors', id: e.competitorId };
  if (e.type === 'supplyPriceChange') return { window: 'suppliers' };
  // Fase 4: presencia y tipo de cambio → ficha del país; combustibles → su pestaña
  if (e.type === 'fuelPriceChange') return { window: 'countries', id: FUELS_PICK };
  if ('countryCode' in e && typeof e.countryCode === 'string') return { window: 'countries', id: e.countryCode };
  return undefined;
}

function useGameEvents() {
  useEffect(() => {
    let months = 0;
    let lastAuto = performance.now();
    const cfg = gameData.game.autoguardado;
    return sim.onEvents((events: SimEvent[]) => {
      const g = sim.state;
      const log: Omit<LogEntry, 'id'>[] = [];
      for (const e of events) {
        // cada evento trae el día en que ocurrió (varios días pueden llegar juntos a velocidad alta)
        const tick = e.tick ?? g?.tick ?? 0;
        const date = g ? formatDate(fromEpochDay(g.startEpochDay + tick), true) : '';
        if ('projectId' in e) {
          log.push({ tick, date, text: e.text, severity: e.severity, projectId: e.projectId });
          if (e.severity !== 'info' || TOAST_INFO.has(e.type)) ui.toast(e.text, KIND[e.severity], e.projectId);
          if (e.type === 'projectCreated') ui.openProject(e.projectId);
          continue;
        }
        // el motor publica también la firma de contratos de la IA (ids «C2-K1»): no son del jugador
        if ('contractId' in e && /^C\d+-/.test(e.contractId)) continue;
        const link = businessLink(e);
        // Fase 5: los eventos graves del mundo además muestran un aviso grande
        if (e.type === 'worldEvent') {
          const v = sim.views?.power?.worldActive.find((x) => x.uid === e.uid);
          const kind = v?.kind ?? gameData.simData.world?.eventos.find((x) => x.id === e.eventId)?.tipo ?? '';
          if (isGrave({ id: e.eventId, kind })) {
            ui.banner({ uid: e.uid, title: v?.name ?? e.text, text: e.text, scope: v?.scopeLabel ?? '' });
            log.push({ tick, date, text: e.text, severity: e.severity, link: link! });
            continue;
          }
        }
        if (link && 'text' in e && 'severity' in e) {
          log.push({ tick, date, text: e.text, severity: e.severity, link });
          if (e.severity !== 'info' || TOAST_INFO.has(e.type)) ui.toast(e.text, KIND[e.severity], undefined, link);
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
      const el = e.target as HTMLInputElement;
      const tag = el.tagName;
      // en campos de texto solo Esc (cerrar); deslizadores y casillas no capturan las teclas
      const typing = tag === 'TEXTAREA' || tag === 'SELECT' || (tag === 'INPUT' && !['range', 'radio', 'checkbox'].includes(el.type));
      if (s.screen !== 'game' || (typing && e.key !== 'Escape')) return;
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
      if (k === 'm') ui.openWindow('market');
      if (k === 'c') ui.openWindow('contracts');
      if (k === 'i') ui.openWindow('research');
      if (k === 'r') ui.openWindow('competitors');
      if (k === 'v') ui.openWindow('suppliers');
      if (k === 'x') ui.openWindow('countries');
      if (k === 't') ui.openWindow('catalog');
      if (k === 'l') ui.openWindow('power');
      if (k === 'w') ui.openWindow('world');
      if (e.key === 'Escape') {
        if (s.dialog) ui.set({ dialog: null });
        else if (s.bidFor) ui.set({ bidFor: null });
        else if (s.pickingRoute) ui.set({ pickingRoute: false });
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
  if (w === 'market') return <MarketPanel />;
  if (w === 'contracts') return <ContractsPanel />;
  if (w === 'research') return <ResearchPanel />;
  if (w === 'competitors') return <CompetitorsPanel />;
  if (w === 'suppliers') return <SuppliersPanel />;
  if (w === 'countries') return <CountriesPanel />;
  if (w === 'catalog') return <CatalogPanel />;
  if (w === 'power') return <PowerMarketPanel />;
  if (w === 'world') return <WorldPanel />;
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
  // gancho para la prueba de humo: leer y cargar la partida como texto (atajos de prueba sobre el JSON)
  useEffect(() => {
    const w = window as unknown as { __voltaje?: object };
    w.__voltaje = Object.assign(w.__voltaje ?? {}, { saveText: () => sim.save(), loadText: (t: string) => loadGame(t), command: (c: Parameters<typeof sim.command>[0]) => sim.command(c),
      select: (lat: number, lon: number) => { ui.openWindow(null); ui.set({ selected: { lat, lon } }); },
      worldEvent: (id: string, countries: string[] | null) => sim.debugWorldEvent(id, countries),
      autopilot: (maxDays?: number, extraDays?: number) => sim.debugAutopilot(maxDays, extraDays),
      oppMarks: () => ui.get().views?.power?.oppMarks ?? [] });
  }, []);

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
          <Banners />
          <Windows />
          <DevelopDialog world={world} />
          <BidDialog />
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
