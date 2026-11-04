# Modelos 3D de sitios y plantas

Modelos low-poly generados por código (sin assets externos) en `apps/game/src/models/`. Sombreado plano, paleta única en `theme.models`, piezas instanciadas: una planta completa son ~10–15 llamadas de dibujo.

## API (`src/models/index.ts`)

```ts
import { createPlant, placeOnGlobe, createTransmissionLine, createModelLights } from './models';

const planta = createPlant({ kind: 'solar_fv', capacityMw: 100, stage: 'construccion', progress: 0.4, seed: 17 });
placeOnGlobe(planta, 8.5, -80.4, 0.011);   // lat, lon (grados), escala: tamaño de 1 unidad local en unidades del globo
scene.add(planta);

planta.update({ ...estado, progress: 0.6 }); // reconstruye solo si cambia algo visible (avance cuantizado a 1 %)
planta.animate(dt);                          // cada frame: palas, vapor, agua, luces
planta.setDetail(0 | 1 | 2);                 // 0 pin (vista lejana), 1 estructuras principales, 2 detalle completo
planta.dispose();                            // libera sus buffers (las geometrías/materiales compartidos se conservan)
```

| Export | Qué es |
|---|---|
| `PlantKind`, `PlantStage`, `PlantVisualState`, `DetailLevel` | tipos |
| `createPlant(state): PlantObject` | `THREE.Group` con `update`, `animate`, `setDetail`, `getDetail`, `dispose`, `state` |
| `createTransmissionLine(points, progress, opts?)` | torres + cables con catenaria a lo largo de una polilínea. `opts.up = 'radial'` para puntos sobre el globo (`lonLatToVec3`), `towerHeight`, `spacing`, `sag`. Tiene `update(points?, progress?)`, `setDetail`, `dispose` |
| `placeOnGlobe(obj, lat, lon, scale, lift = 0)` | coloca con +Y = normal de la esfera, −Z = norte, +X = este (convención de `globe/geo.ts`) |
| `createModelLights()` | luz hemisférica + direccional. **El globo usa un shader propio sin luces: al integrar, añadir este grupo a la escena** |
| `PLANT_KINDS`, `PLANT_STAGES`, `PLANT_DEFS`, `plantInfo(kind)` | registro: etiqueta en español, capacidad típica, familia del pin |
| `disposeModelCache()`, `registerGeometry(key, factory)` | liberar el caché compartido; añadir geometrías unitarias |

### Escala y colocación
- Unidades locales: la base octogonal mide ≈1,2 de ancho (radio 0,6), Y hacia arriba, terreno en `y = MODEL_GROUND_Y` (0,02). La base baja hasta y = −0,05 para tapar huecos con las facetas del globo.
- En el globo (radio 1, cámara mínima a 1,08) una escala de **0,008–0,015** se ve bien a escala iconográfica (la vista previa usa 0,011 con sitios a ~1,2° de distancia). Para la línea sobre el globo: `towerHeight ≈ 0,27 × escala` para que coincida con las torres de las plantas.
- LOD sugerido según distancia cámara→sitio: > 0,35 → `0`, > 0,16 → `1`, si no `2` (así lo hace la vista "globo" de `models.html`).

### Etapas
| Etapa | Qué se ve |
|---|---|
| `prospeccion` | estacas con banderines + un instrumento: torre de medición (eólica), piranómetro (solar/CSP), torre de perforación exploratoria (geotermia, nuclear, SMR), estación de aforo con río (hidro), boya de medición (marina), taquímetro (resto) |
| `estudios` | lo anterior + más estacas, caseta, camioneta, sondeos geotécnicos, segundo instrumento |
| `construccion` | terreno despejado (crece con el avance), casetas de obra, maquinaria; los elementos aparecen según `progress`: paneles por filas, torres por tramos → góndola → palas una a una, presa por capas y luego el embalse se llena, chimeneas y tanques que suben con anillo de encofrado, edificios losa → estructura + andamio → muros → techo, grúas torre y sobre orugas |
| `operacion` | completa y animada: palas, vapor (geotermia, nuclear, carbón, CSP), humo, agua en vertedero y canales, luces de subestación |
| `falla` | igual + humo negro y baliza roja en el punto crítico (`ctx.hot`) |
| `abandonado` | desaturado (`abandonedDesaturate/Darken/Tint`), sin animación, piezas de detalle y repetidas faltantes al azar (determinista por seed) |

`capacityMw` escala la cantidad: filas/mesas FV, anillos de heliostatos, nº de aerogeneradores (1 por 10 MW en tierra, 1 por 40 MW en mar), pozos geotérmicos, digestores, unidades nucleares/SMR/ciclo combinado, contenedores de baterías, transformadores, altura de presa…

Todas las plantas incluyen una subestación de conexión con torre de salida, salvo `subestacion` (es una, más grande) y `linea_transmision`.

## Arquitectura
```
models/
  index.ts      API pública, PlantObject, registro PLANT_DEFS, pin (LOD 0), placeOnGlobe
  kit.ts        caché de geometrías unitarias y materiales; Builder (piezas → InstancedMesh por geometría+material); animaciones
  common.ts     terreno, prospección/estudios, maquinaria, grúas, edificios, tanques, chimeneas, torres de enfriamiento, subestación
  lines.ts      createTransmissionLine
  types.ts      tipos y PlantDef
  defs/         solar.ts, wind.ts, water.ts, thermal.ts, grid.ts (un PlantDef por tecnología)
  tools/capturas.mjs   capturas + barrido de todas las combinaciones
```
- **Builder**: cada pieza = clave de geometría unitaria (`box`, `cyl8`, `taper12`, `blade`, `hyper`, `pylonBody`…) + material (`solid`, `solid2`, `gloss`, `glow`, `water`, `puff`) + matriz + color. `finish()` agrupa por (lod, geometría, material) en un `InstancedMesh` con `instanceColor`. Los colores van por instancia: no hay un material por color.
- Animaciones por instancia (`spin`, `puff`, `flow`, `blink`, `pulse`) se aplican en `animate(dt)` solo a las mallas que las tienen.
- Determinismo: la disposición usa un RNG propio sembrado con `seed` + tipo; las piezas que faltan en abandonado usan otro flujo.

## Añadir un modelo nuevo
1. Añadir el nombre a `PlantKind` en `types.ts`.
2. Crear su `PlantDef` en un archivo de `defs/` (o uno nuevo):
   ```ts
   export const mareomotriz: PlantDef = {
     label: 'Mareomotriz', pin: 'agua', survey: 'buoy', terrain: 'sea', sub: null, typicalMw: 20,
     build(b, c) {
       const n = c.count(2, 2, 8);                  // 1 turbina por 2 MW, entre 2 y 8
       for (let i = 0; i < n; i++) {
         const p = c.ph(0.1 + i * 0.08, 0.4 + i * 0.08); // avance de esta unidad (1 si ya opera)
         if (p <= 0) continue;
         b.cyl('steel', -0.3 + i * 0.1, Y0 - 0.02, 0, 0.02, 0.06 * p);
       }
       b.fine(() => { /* detalle que solo se ve en nivel 2 */ });
       if (c.running) b.puffs('foam', 0, Y0, 0.1, { size: 0.02, rise: 0.03 });
       c.hot = b.pt(0, Y0 + 0.05, 0);                // dónde se muestra una falla
     },
   };
   ```
   Herramientas: `b.box/cyl/part/beam/line/puffs/blink`, `b.at(x, z, giro, fn)` para marcos locales, `b.lost(p)` para piezas que faltan en abandonado; y en `common.ts`: `building`, `tank`, `chimney`, `coolingTower`, `fanCooler`, `pipeL`, `pylon`, `towerCrane`, `crawlerCrane`, `truck`, `excavator`, `scaffRing`, `trees`, `river`.
3. Registrarlo en `PLANT_DEFS` (`index.ts`). Aparece solo en la vista previa y en el barrido de pruebas.
4. Si hace falta una forma nueva: añadirla a `factories` en `kit.ts` (unitaria, base en y = 0) o con `registerGeometry`.

## Cambiar la paleta
Todo color sale de `theme.models` en `apps/game/src/theme/theme.ts`: terreno (`grass`, `dirt`, `sea`…), obra civil, metales, maquinaria (`crane`, `machinery`), combustibles, efectos (`steam`, `smoke`, luces), color de pin por familia (`pin`), anillo por etapa (`stage`), parámetros de abandonado y luces (`hemiIntensity`, `sunIntensity`, `roughness`). Cambiar una clave cambia todas las plantas que la usan; las piezas aceptan también un hex `'#rrggbb'` puntual.

## Vista previa y capturas
- `npm run dev` → `http://localhost:5173/models.html`: modos *cuadrícula* (las 20 tecnologías), *secuencia* (obra 0/33/66/100 %), *etapas* (las 6 etapas de un tipo) y *globo* (plantas sobre una esfera con LOD por distancia); controles de tecnología, etapa, avance, capacidad, semilla, detalle y animación. `window.__preview` permite manejarla desde scripts.
- Capturas: `npm run build && node apps/game/src/models/tools/capturas.mjs [filtro]` → `docs/capturas/modelos/`. Antes de las capturas hace un barrido de 2240 estados (tipo × capacidad × semilla × etapa × avance × LOD, más la línea) y falla si hay errores.
- `models.html` se añadió como segunda entrada en `apps/game/vite.config.ts` (`build.rollupOptions.input`).

## Capturas actuales
`todas-operacion`, `todas-prospeccion`, `todas-estudios`, `todas-construccion-050`, `todas-falla`, `todas-abandonado`, `todas-detalle1`, `todas-detalle0`, `construccion-{solar_fv,eolica_tierra,geotermica,hidro_embalse}`, `etapas-{solar_fv,eolica_tierra,nuclear,eolica_mar,hidro_embalse,geotermica}`, `globo-operacion`.

## Pendiente / ideas
- Iconos distintos por tecnología en el pin (hoy: color por familia + anillo por etapa).
- En la vista del globo la base octogonal "de maqueta" podría ocultarse (`ground`) si se prefiere el terreno del propio globo.
