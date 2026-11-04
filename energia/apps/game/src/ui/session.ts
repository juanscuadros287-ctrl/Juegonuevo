import { gameData } from '@voltaje/data';
import { currentDate, formatDate } from '@voltaje/sim';
import { sim } from '../worker/client';
import { saves, type SaveRecord } from '../storage/saves';
import { getGlobe } from '../globe/GlobeView';
import { ui } from './store';
import { loadWorld } from '../world/loadWorld';

function enterGame() {
  const home = gameData.game.pais_inicial;
  ui.set({ screen: 'game', dialog: null, selected: null, speedId: null });
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
  ui.set({ screen: 'menu', game: null, dialog: null, selected: null, layerId: null });
  getGlobe()?.flyTo(10, -40, 3.4, 2);
}
