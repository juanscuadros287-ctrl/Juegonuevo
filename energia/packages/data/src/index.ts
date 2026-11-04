/// <reference types="vite/client" />
import game from '../game.yaml';
import layers from '../layers.yaml';
import studies from '../studies.yaml';
import suppliers from '../suppliers.yaml';
import { buildGameData } from './load';

const countryFiles = import.meta.glob('../countries/*.yaml', { eager: true, import: 'default' });
const technologyFiles = import.meta.glob('../technologies/*.yaml', { eager: true, import: 'default' });

export * from './schemas';
export * from './load';

/** Datos del juego validados (se cargan una vez al importar). */
export const gameData = buildGameData({ game, layers, countries: countryFiles, technologies: technologyFiles, studies, suppliers });
