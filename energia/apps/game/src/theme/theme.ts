/**
 * Tema visual centralizado. Cambiar aquí los colores del globo y en theme.css los de la UI.
 * Todo el render lee de este objeto: no hay colores sueltos en el código del globo.
 */
export const theme = {
  globe: {
    oceanDeep: '#14324f',
    oceanShallow: '#2c6a8f',
    ice: '#eef3f7',
    desert: '#e2c98f',
    steppe: '#c5c883',
    grass: '#8fb86a',
    forest: '#4f8a4b',
    rainforest: '#2f6b3c',
    mountain: '#8a8a78',
    border: '#0b1b2b',
    borderOpacity: 0.55,
    selection: '#ffe14d',
    homeCountry: '#ffffff',
    atmosphere: '#7cc4ff',
    ambient: 0.62,
    sun: 0.55,
    layerOpacity: 0.82,
  },
  /** Facetas del globo: cuanto menor, más "low-poly". */
  globeDetail: 28,
};
export type Theme = typeof theme;
