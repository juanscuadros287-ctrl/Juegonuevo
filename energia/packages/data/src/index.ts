/// <reference types="vite/client" />
import game from '../game.yaml';
import layers from '../layers.yaml';
import studies from '../studies.yaml';
import suppliers from '../suppliers.yaml';
import research from '../research.yaml';
import clients from '../clients.yaml';
import competitors from '../competitors.yaml';
import markets from '../markets.yaml';
import power from '../power.yaml';
import events from '../events.yaml';
import team from '../team.yaml';
import { buildGameData } from './load';

const countryFiles = import.meta.glob('../countries/*.yaml', { eager: true, import: 'default' });
const technologyFiles = import.meta.glob('../technologies/*.yaml', { eager: true, import: 'default' });

export * from './schemas';
export * from './load';

/** Datos crudos (YAML parseados, sin validar): para pruebas que modifican datos. Usar `structuredClone` antes de mutar. */
export const rawGameData = { game, layers, countries: countryFiles, technologies: technologyFiles, studies, suppliers, research, clients, competitors, markets, power, events, team };

/** Datos del juego validados (se cargan una vez al importar). */
export const gameData = buildGameData(rawGameData);
