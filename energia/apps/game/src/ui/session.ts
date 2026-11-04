import { gameData } from '@voltaje/data';
import { currentDate, formatDate, fromEpochDay } from '@voltaje/sim';
import { sim } from '../worker/client';
import { saves, type SaveRecord } from '../storage/saves';
import { getGlobe } from '../globe/GlobeView';
import { LOG_MAX, ui, type LogEntry } from './store';
import { loadWorld } from '../world/loadWorld';

/** Reconstruye el registro de eventos desde las líneas de tiempo de los proyectos (no se guarda aparte). */
function rebuildLog() {
  const g = sim.state;
  const entries: Omit<LogEntry, 'id'>[] = [];
  for (const p of g?.projects ?? []) for (const t of p.timeline) entries.push({ tick: t.tick, date: formatDate(fromEpochDay(g!.startEpochDay + t.tick), true), text: `${p.name}: ${t.text}`, severity: t.kind, projectId: p.id });
  entries.sort((a, b) => a.tick - b.tick);
  ui.set({ log: [], unread: 0 });
  ui.log(entries.slice(-LOG_MAX));
  ui.set({ unread: 0 });
}

function enterGame() {
  const home = gameData.game.pais_inicial;
  sim.focus(null);
  ui.set({ screen: 'game', dialog: null, selected: null, speedId: null, window: null, projectId: null, developAt: null, log: [], unread: 0 });
  sim.setSpeed(0);
  loadWorld().then((w) => {
    const meta = w.grid.countriesByCode.get(home);
    if (meta) getGlobe()?.flyTo(meta.lat, meta.lon, 1.45, 2.2);
  });
}

export function startNewGame(companyName: string, seed: number) {
  sim.newGame(seed, companyName);
  enterGame();
}

export async function loadGame(text: string) {
  await sim.load(text);
  enterGame();
  // la instantánea llega justo después de 'loaded'
  const off = sim.onState(() => { off(); rebuildLog(); });
}

export async function saveGame(kind: 'auto' | 'manual', label?: string): Promise<SaveRecord> {
  const text = await sim.save();
  const g = sim.state!;
  const slot = kind === 'auto' ? await saves.nextAutoSlot(gameData.game.autoguardado.ranuras) : `manual-${Date.now()}`;
  const rec: SaveRecord = {
    slot, kind,
    label: label?.trim() || (kind === 'auto' ? 'Autoguardado' : g.company.name),
    company: g.company.name,
    gameDate: formatDate(currentDate(g), true),
    savedAt: Date.now(),
    data: text,
  };
  await saves.put(rec);
  return rec;
}

export function quitToMenu() {
  sim.quit();
  ui.setSpeed(null);
  ui.set({ screen: 'menu', game: null, views: null, dialog: null, selected: null, layerId: null, window: null, projectId: null, developAt: null, log: [], unread: 0 });
  getGlobe()?.flyTo(10, -40, 3.4, 2);
}
