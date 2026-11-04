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
  /**
   * Modelos 3D de sitios y plantas (src/models). Toda la paleta de los modelos vive aquí:
   * cambiar un color cambia todas las plantas que lo usan. Ver docs/MODELOS.md.
   */
  models: {
    // terreno
    grass: '#93c26b', grassDark: '#78a957', soil: '#8a6a48', dirt: '#cfa46c', gravel: '#c4beb1', sand: '#e6d39f',
    rock: '#a39a88', rockDark: '#857c6d', tree: '#4f8f47', trunk: '#7a5a3c',
    sea: '#2f7fb8', water: '#4a9fd2', waterDeep: '#2f78ad', foam: '#eaf7ff',
    // construcción civil
    concrete: '#dcd8cf', concreteDark: '#aaa59b', asphalt: '#5d5f63', wall: '#ece6d8', wallAlt: '#d7dde3',
    roof: '#5d7489', roofRed: '#b9644c', window: '#3d5672', brick: '#b06f55',
    // metal y equipos
    steel: '#a7b0ba', steelDark: '#646d78', white: '#f5f6f3', tank: '#eceff1', pipe: '#cfd4d9', pipeHot: '#d9cfb8',
    transformer: '#6e8f7c', insulator: '#f0e9df', copper: '#c27a45',
    panel: '#203f6e', panelFrame: '#cfd5db', mirror: '#cfeaf7', receiver: '#3a3a3a',
    // obra y maquinaria
    crane: '#f2b632', machinery: '#f29a2e', machineryDark: '#3c4047', scaffold: '#e8a33c',
    stake: '#efe8d6', flag: '#ff6a3d', buoy: '#ffd23f', safety: '#ff8a2a',
    // combustibles y procesos
    biomass: '#a47a4b', coal: '#2f2d2c', digester: '#7fa86a', membrane: '#e9efe3',
    battery: '#eef1f4', batteryAccent: '#3fb37f', hydrogen: '#6fd0e6', stripe: '#d9443a',
    // efectos
    steam: '#ffffff', smoke: '#9a9a9a', smokeDark: '#2b2929',
    lightOk: '#7dff9a', lightWarn: '#ff3b30', lightAmber: '#ffc93c', hot: '#ffb347', flame: '#ff7b2e',
    /** Color del pin (vista lejana, detalle 0) por familia de tecnología. */
    pin: {
      solar: '#ffc93c', viento: '#9fe3ff', agua: '#3d8fd4', geo: '#ff7a59', bio: '#8fbf4a', nuclear: '#b48cff',
      fosil: '#8d8d8d', almacenamiento: '#3fb37f', red: '#e9e9e9', eficiencia: '#7ad15a',
    },
    /** Anillo del pin según la etapa. */
    stage: {
      prospeccion: '#ffffff', estudios: '#9fd2ff', construccion: '#f2b632', operacion: '#5fd17a', falla: '#ff3b30', abandonado: '#6f6f6f',
    },
    /** Abandonado: cuánto se desatura (0..1), oscurece y hacia qué tono se lleva. */
    abandonedDesaturate: 0.8, abandonedDarken: 0.78, abandonedTint: '#8a7a62',
    /** Material: rugosidad general y luces sugeridas (createModelLights). */
    roughness: 0.85, lightSky: '#ffffff', lightGround: '#7a6e5a', hemiIntensity: 1.5, sunIntensity: 2.2,
  },
};
export type Theme = typeof theme;
