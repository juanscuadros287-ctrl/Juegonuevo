# Sistema gráfico

Mejora general de la imagen: luz y postproceso, modelos, carreteras y rieles, agua, vegetación,
personas y vehículos, etiquetas 3D y calidad configurable. Todo es procedural (sin texturas ni
modelos importados) y degrada bien de Forward+ (Metal en Mac M1) a Compatibility (OpenGL).

Capturas antes/después en `docs/capturas/graficos/` (`antes_*.png` / `despues_*.png`), generadas
con `tests/screenshot_graficos.tscn`:

```
xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 \
    res://tests/screenshot_graficos.tscn -- docs/capturas/graficos despues
```

Las capturas se hacen en Compatibility (OpenGL/llvmpipe): no muestran SSAO, glow ni la dispersión
de la niebla, que solo existen en Forward+.

## 1. Iluminación y postproceso — `scripts/world/sky_rig.gd`

`world.gd` crea un `SkyRig` (antes `_build_environment`) y cada frame llama
`sky_rig.update(hora, oscurecimiento_del_clima)`.

- Un solo `Environment` con cielo procedural (`ProceduralSkyMaterial`) con disco solar.
- Ciclo día/noche suave: los colores del cenit, horizonte y luz del sol se interpolan por la altura
  del sol (`SKY_KEYS`): noche azul oscura, crepúsculo morado, amanecer/atardecer naranja, día azul.
  El sol sale a las 6 y se pone a las 18 (altura máxima ~62°). De noche la misma luz direccional
  hace de luna (azulada y tenue); el cambio ocurre con la energía en cero, sin saltos.
- Tonemapping ACES con exposición que sube un poco de noche; luz ambiental del cielo.
- Sombras direccionales: sesgo 0,03 y sesgo normal 1,1 (sin acné ni peter-panning), desenfoque
  suave; calidad Alta = 4 cascadas mezcladas, Media = 2 cascadas.
- Solo Forward+: SSAO (Alta), glow suave (Media/Alta; los emisivos de noche florecen) y dispersión
  del sol en la niebla. En Compatibility se omiten (no existen en ese renderer).
- La densidad de la niebla la sigue controlando `camera_rig.gd` (Fase 9A/9B); SkyRig solo pone su
  color según la hora.
- `night_factor` (0 día → 1 noche, sube un poco con clima nublado) llama a `MeshLib.set_night()`:
  enciende ventanas de vidrio (no todas: patrón aleatorio por piso/columna), rendijas de postigos
  de madera, faroles y faros de buses.

### Faroles — `scripts/world/street_lights.gd`

Faroles en la plaza (6) y cada 18 m a lo largo de las carreteras, alternando lados, con el brazo
hacia la calzada. Postes y pantallas en dos `MultiMesh` para todo el pueblo; la pantalla es
emisiva. Bajo cada farol hay un "charco de luz" aditivo (`shaders/light_pool.gdshader`) que imita
la luz sobre el suelo sin luces reales (funciona en Compatibility). En Alta + Forward+ se añaden
hasta 10 `OmniLight3D` reales cerca de la plaza. Se reconstruye solo cuando cambian las carreteras.

## 2. Calidad gráfica — `scripts/world/graphics_settings.gd`

API para la interfaz (la UI la maneja otro agente; este módulo no toca `scripts/ui/`):

| Función | Qué hace |
|---|---|
| `GraphicsSettings.level() -> int` | Nivel actual: `LOW` (0), `MEDIUM` (1), `HIGH` (2). |
| `GraphicsSettings.apply(nivel)` | Guarda en `user://graficos.cfg` y aplica al instante (llama `apply_graphics(perfil)` en el grupo `graphics_listeners`). |
| `GraphicsSettings.make_selector() -> Control` | Fila "Calidad gráfica [Baja/Media/Alta]" lista para añadir a un menú de opciones (solo usa `apply`). Ej.: `pb.add_child(GraphicsSettings.make_selector())` en el modal de pausa de `hud.gd`. |
| `GraphicsSettings.profile() -> Dictionary` | Valores efectivos: sombras, distancia de sombras, cascadas, SSAO, glow, MSAA/FXAA, distancias de dibujo de edificios/detalles/árboles, pasto, luces reales. |

Por defecto: Alta en Forward+ (Mac M1), Media en Compatibility.

| | Baja | Media | Alta |
|---|---|---|---|
| Sombras | no | 2 cascadas, 160 m | 4 cascadas, 260 m, suaves |
| SSAO | no | no | sí (Forward+) |
| Glow | no | sí (Forward+) | sí (Forward+) |
| Antialias | FXAA | MSAA 2× | MSAA 4× (Forward+) |
| Edificios (distancia) | 260 m | 480 m | 900 m |
| Detalles de fachada | 60 m | 110 m | 180 m |
| Árboles del pueblo | 240 m | 420 m | 800 m |
| Pasto y flores | no | 55 m | 85 m |

## 3. MeshLib y modelos — `scripts/world/mesh_lib.gd`, `shaders/building.gdshader`

- **Primitivas con sombreado plano**: `cylinder()` (con tapas; cono si top = 0), `sphere()`,
  `bevel_box()` (caja biselada), `hip_roof()` (cuatro aguas), `arch()`, `stairs()`, `torus()` y
  `wheel()` (rueda: llanta + disco). Todas cacheadas.
- **`build_model()` une las piezas** de un modelo JSON en una sola malla con un único material
  compartido (`building_mat()`): el color va por vértice y el tipo de material por UV2. Un edificio
  pasa de 5–60 nodos/llamadas de dibujo a 1–2. Los modelos se cachean por (piezas, tinte, variante).
- **Material por tipo** (explícito con `"m": "ladrillo"` en la pieza, o deducido del color y la forma):
  estuco/adobe, ladrillo (hiladas y mortero), madera (tablas), piedra (sillares), teja, paja, concreto
  (paneles), metal (corrugado), vidrio (brillante, se enciende de noche) y postigo. Patrones
  procedurales en el shader, que se desvanecen a distancia (sin moiré).
- **Detalles automáticos** (segunda malla con distancia de dibujo corta, sin sombra): marco,
  travesaño y alféizar en ventanas; marco, dintel, escalón de piedra y pomo en puertas; cumbrera y
  aleros en techos a dos aguas; zócalo, cornisa y esquineras en el volumen principal; parteluces,
  esquinas, zócalo y cornisa en edificios de pisos. Nuevas piezas JSON: `bevel`, `hip`, `arch`,
  `stairs`, `torus`, `win` (ventana con marco), `door`, `chimney`, `fence`.
- **Paleta y variación**: saturación acotada (paleta más armónica) y, por edificio, una de 5
  variantes de tono/brillo sutiles (`variant = id % 5`) para que no se vean clonados.
- **Personas**: torso con cintura, cuello, cabeza, pelo, falda o pantalón, piernas y brazos
  separados que se balancean al caminar (`MeshLib.animate_person`); ropa según la época
  (`CitizenAgent.ERA_CLOTH`: colonial terrosa, industrial oscura, moderna viva).
- **Vehículos**: ruedas con llanta y disco (carretas, carros de vapor, camiones, buses); buses con
  faros que se encienden de noche, parachoques y franja.
- **Andamio** de obra unido en una malla con plataformas y diagonales.
- **Etiquetas 3D** (`MeshLib.style_label`): tamaño fijo en pantalla, se desvanecen a partir de cierta
  distancia y se dibujan encima de la geometría cercana (yacimientos, almacenes, minas, paraderos,
  servicios públicos).

## 4. Carreteras, rieles y puentes — `scripts/world/road_mesh.gd`, `shaders/road.gdshader`

- Franjas continuas con 5 vértices a lo ancho y una muestra por metro: cada vértice toma la altura
  del terreno bajo él y a medio camino del vecino (no se hunde entre triángulos), con faldones que
  tapan huecos en los bordes y tapas semicirculares en los extremos (empalmes e intersecciones
  limpias). El shader acerca un poco el vértice a la cámara (sesgo de profundidad proporcional a la
  distancia): sin z-fighting con el terreno.
- Patrones procedurales por tipo: tierra con huellas y bordes con pasto (barro), empedrado con
  juntas y bordillo, asfalto con bordes blancos y línea central amarilla discontinua (cemento). Los
  patrones de superficie usan coordenadas del mundo: dos tramos superpuestos dibujan lo mismo.
- Los caminos automáticos (casa → plaza) ya no son tablones de cajas: usan la misma franja.
- Vía férrea: balasto trapezoidal (base pegada al terreno), durmientes cada 0,65 m y rieles con
  perfil, todo a la altura del lecho suavizado (alineados en curvas y sin flotar).
- Puentes: pilares de piedra, vigas laterales, postes y barandas donde el trazado cruza agua.
- `TransitVisuals.strip_mesh/rail_node/bridge_pillars` delegan en `RoadMesh` (misma API).

## 5. Agua — `scripts/world/water_look.gd`, `shaders/water.gdshader`

Una línea en `world.gd` tras `terrain.make_water()` cambia el material del plano de agua. Color por
profundidad (turquesa en la orilla → azul profundo), fresnel, ondas suaves en la normal (se aplanan
a lo lejos) y espuma animada en la orilla. La profundidad sale de un mapa de alturas del terreno
horneado (192², 480 m alrededor del pueblo) en lugar de la textura de profundidad: funciona igual
en Forward+ y Compatibility. Fuera de ese recuadro se usa una profundidad media.

## 6. Vegetación — `scripts/world/vegetation.gd`, `shaders/foliage.gdshader`

- Los conos del pueblo se reemplazan por 5 modelos low-poly: coníferas (tres pisos), frondosos
  (copas en racimo), palmeras (tronco curvo y hojas), arbustos y cactus, elegidos por bioma, clima
  y altura, con rotación, escala y tono aleatorios. `MultiMesh` por celdas de 100 m (recorte por
  cámara y distancia de dibujo).
- Pasto y flores dispersos alrededor de la cámara (Media/Alta), evitando caminos, edificios, agua y
  pendientes; se regeneran al moverse.
- `MeshLib.vertex_color_mat()` ahora es el shader de follaje: sombreado plano y balanceo con el
  viento solo en piezas verdes (copas, hojas, pasto); troncos y rocas quietos. Aplica también a los
  árboles de los chunks del país.
- No modifica `terrain.gd`: lee `tree_positions`/`_tree_xforms`, oculta los dos MultiMesh de conos
  del pueblo y registra un "ocultador" en `terrain._tree_mms` para que `Terrain.clear_trees()` tale
  también estos árboles.

## 7. Terreno — `scripts/world/terrain_look.gd`, `shaders/terrain_*_plus.gdshader`

`TerrainLook.apply(terrain)` (una línea en `world.gd`) cambia el shader de los materiales existentes
por las versiones con la gradación de `shaders/terrain_grade.gdshaderinc` (pasto menos "neón",
manchas secas y húmedas, leve oscurecimiento a distancia; las manchas finas se apagan a distancia
para no hacer moiré).

- Chunks del país: `terrain_chunk.gdshader` y `terrain_chunk_plus.gdshader` **incluyen el mismo
  cuerpo** (`shaders/terrain_chunk_body.gdshaderinc`); la versión *plus* solo define
  `TERRAIN_GRADE`. Ya no hay copia que sincronizar. (Antes la copia *plus* era la de la Fase 9A y al
  engancharse borraba el velo, las fronteras de municipio y el recorte de la capa lejana: la tesela
  de 80 m se dibujaba encima de las mallas detalladas y todo se veía borroso y en bloques.)
- Pueblo: `terrain_plus.gdshader` sigue siendo copia de `terrain.gdshader`.
- También pasa la rejilla real del país al agua (color por profundidad, ver §9).

## 8. Rendimiento

`tests/screenshot_graficos.gd` imprime y guarda (`*_rendimiento.txt`) el tiempo de frame, las
llamadas de dibujo, objetos y primitivas de cada vista. Con xvfb + llvmpipe (render por CPU, 4
núcleos compartidos con otros agentes) el tiempo de frame es solo orientativo; las llamadas de
dibujo y los objetos sí son comparables.

Misma escena (pueblo con 10 viviendas de varias épocas, negocios, carreteras, rieles y mina), medida
alternando antes/después en la misma máquina (dos corridas cada una):

| Vista | Draw calls antes → después | Objetos | Primitivas | ms/frame (llvmpipe) |
|---|---|---|---|---|
| Pueblo de día | 2570 → 1106 (−57 %) | 4722 → 3257 | 2,01 M → 1,50 M | 713–753 → 680–730 |
| Atardecer | 2022 → 903 (−55 %) | 4174 → 3054 | 1,77 M → 1,19 M | 641–666 → 605–742 |
| Noche | 1684 → 1059 (−37 %) | 3836 → 3210 | 2,26 M → 1,35 M | 634–664 → 676–711 |

Con todo lo nuevo (faroles, pasto, patrones procedurales, agua con shader, sombras en cascadas) el
tiempo de frame queda igual dentro del ruido de la máquina y la carga de la GPU baja: menos de la
mitad de llamadas de dibujo y ~25–40 % menos primitivas. Lo más caro en llvmpipe son las sombras
(pasadas por cascada), por eso Media usa 2 cascadas y Baja las apaga. En un M1 (Forward+/Metal) la
reducción de draw calls es lo que más pesa; SSAO y glow se limitan a Alta/Media.

Claves: modelos unidos en 1–2 mallas por edificio con un material compartido, detalles de fachada
con distancia de dibujo corta y sin sombra, vegetación/faroles/pasto en `MultiMesh`, visibility
ranges por calidad, y carreteras/pasto sin sombra.

## 9. Mapa v2 — el país a cualquier zoom

Capturas en `docs/capturas/mapa_v2/` (`tests/screenshot_mapa_v2.tscn`, ver §9.6).

### 9.1 LOD y transición (`scripts/world/terrain.gd`)

| Nivel | Celda | Distancia (3D a la cámara) | Máximo | Árboles 3D |
|---|---|---|---|---|
| Alta | 5 m (80×80) | < 700 m | 9 chunks | tronco + copa |
| Media | **10 m (40×40)** (antes 20 m) | < máx(2 km, 1,3 × altura de cámara), hasta 3,4 km | 56 | copas (menos y más chicas) |
| **Media-baja (nueva, `LOD_LOW`)** | 20 m (20×20) | < máx(2,6 km, 2 × altura de cámara), hasta 7,5 km | 150 | no (las pone el shader) |
| Lejana | 80 m, teselas 4×4 chunks | todo el país | — | no |

Antes, con la cámara a 1–4 km (vista de región o municipio) ningún chunk entraba en la media (el
límite era 2,8 km en 3D y la cámara ya estaba a esa altura): todo era la tesela de 80 m. Ahora la
malla detallada llega más lejos cuanto más alta está la cámara, con presupuesto fijo de chunks.

**Transición suave**: en la banda final del radio que cubre la malla detallada (`fade_near..fade_far`,
≈ 8 % del radio, mínimo 250 m) la malla detallada y la tesela lejana se mezclan con un tramado
complementario por píxel (cada píxel dibuja una u otra), así un chunk que entra o sale no "salta".
El radio se suaviza entre actualizaciones.

### 9.2 Shader del terreno (`terrain_chunk_body.gdshaderinc`)

- Atributo nuevo por vértice (UV): x = densidad de árboles del bioma, y = aridez (desierto 1,
  costa 0,5) o montaña (−1) / nevado (−2). La tesela lejana los suaviza como los colores.
- Ruido de detalle en coordenadas del mundo **filtrado por el tamaño del píxel** (cada octava se apaga
  por debajo de ~2 px): variación de color por bioma (zonas secas/húmedas), por pendiente (roca con
  estratos) y por altura (páramo pardo, nieve en las cumbres con vetas de roca), arena en costas y
  orillas (se ensancha un poco de lejos para que la costa se lea).
- **Bosque y selva**: copas procedurales (Voronoi, una por celda con probabilidad = densidad). La
  celda mide 9 m de cerca y crece con la distancia (≥ ~6 px, mezclando dos octavas sin saltos); cada
  copa es una cúpula que inclina la normal (bump por derivadas de pantalla), así la luz real la
  sombrea y los claros quedan oscuros. De lejos el bosque tiene textura y relieve, no manchas planas.
- **Relieve**: normal suave del vértice con las laderas exageradas según la distancia (×1,5 cerca →
  ×4 lejos, más en montaña), sombreado cartográfico suave desde el noroeste (solo de lejos) y crestas
  de montaña procedurales cuya pendiente se calcula en el mundo (diferencias finitas) e inclina la
  normal. De cerca se conservan las facetas low-poly (ahora solo hasta ~650 m).
- **Ríos reales** como líneas azules con grosor mínimo en pantalla (se apagan de cerca, donde manda
  el cauce tallado). La distancia al río de la rejilla de 200 m interpolada dejaba "cuentas"; en
  `Terrain._build_river_texture()` se reconstruye el cauce (cada celda cercana se proyecta sobre el
  río contra el gradiente de la distancia, las vecinas se unen con segmentos) y se rasteriza la
  distancia exacta en una textura de 25 m por píxel (~70–110 ms al iniciar Colombia).
- Velo de niebla, fronteras de municipio (un poco más tenues: 0,32) y recorte de la capa lejana como
  en la Fase 9B.

### 9.3 Agua (`shaders/water.gdshader`)

Fuera del recuadro horneado del pueblo, el color sale de la batimetría real (ETOPO1, en `geo_tex`):
orilla y plataforma turquesa, talud azul y océano profundo azul oscuro; lagos y ríos poco profundos.

### 9.4 Etiquetas (`scripts/world/label_declutter.gd`)

- `LabelDeclutter` (lo crea `CountryOverlay`) proyecta cada 0,1 s las etiquetas registradas, estima
  su rectángulo en pantalla (fuente, tamaño, contorno, `pixel_size`, `offset`) y las coloca por
  prioridad (a igual prioridad, la más cercana): si choca prueba a desplazarla arriba o abajo y, si
  no cabe, la oculta. Los cambios se animan (`transparency` y `offset` suaves).
- Prioridades: tu pueblo 100 > pueblos 10 + log10(población) > municipios sin pueblo 3 > almacenes
  2 > resto 1 > minas 0,8 > yacimientos 0,5. `MeshLib.style_label(lab, dist, prio, escala)` registra
  cualquier etiqueta 3D.
- Desvanecido por distancia: los nombres del país se apagan con la altura (como antes) y además a
  más de 3–5 veces la altura de la cámara (lo del horizonte en vistas inclinadas).
- Yacimientos y minas: texto más chico (×0,8) y visibles solo de cerca (110–140 m).

### 9.5 Minimapa (`scripts/ui/minimap.gd`)

Abajo a la izquierda alineado con la barra de categorías (x = 8, sin el hueco del dock viejo), con el
estilo flotante de UIKit (`float_style`, igual que la barra). Si la ventana es tan baja que chocaría
con la barra de categorías, se corre a su derecha.

### 9.6 Rendimiento

`tests/screenshot_mapa_v2.gd` mide cada vista (12 frames) y guarda `docs/capturas/mapa_v2/rendimiento.txt`.
Misma escena antes (commit 20020cb, con la copia vieja del shader) y después, xvfb + llvmpipe (render por
CPU, 4 núcleos compartidos con otros agentes: el tiempo de frame es orientativo). Imágenes de antes:
`antes_*.png`.

| Vista | Cámara | ms/frame antes → después | Draw calls | Primitivas | Chunks detallados antes → después |
|---|---|---|---|---|---|
| Colombia completa | 29,8 km | 674 → 932 | 958 → 958 | 0,48 M → 0,48 M | 0 → 0 |
| Región | 2,5 km | 345 → 675 | 547 → 582 | 0,16 M → 0,26 M | 21 media (20 m) → 27 media (10 m) + 60 media-baja |
| Municipio completo | 6 km | 322 → 681 | 547 → 666 | 0,15 M → 0,26 M | 0 → 119 media-baja |
| Montañas / costa | 7–9 km | 282–311 → 452–454 | igual | igual | 0 → 0 |
| Pueblo de cerca | 150 m | 749 → 703 | 940 → 930 | 2,02 M → 2,02 M | 9 alta + 58 media → 9 + 56 + 29 |

- **GPU**: las llamadas de dibujo y las primitivas casi no cambian (+0–20 % en vistas medias, por los
  chunks de 20 m que antes no existían; cada uno es 1 llamada y ~900 triángulos). El shader del terreno
  es más caro por píxel (copas Voronoi 2×9 celdas, 3 fbm de 4 octavas, crestas con 3 muestras solo en
  montaña): en llvmpipe, que sombrea en CPU, eso sube el frame de las vistas lejanas ~1,5–2×; en una GPU
  real (M1/Metal, Forward+) es un costo de fragmento pequeño frente a sombras y postproceso.
- **CPU (hilos)**: chunk medio de 10 m ≈ 20 ms (antes 5–8 ms el de 20 m); media-baja ≈ 5–8 ms; tesela
  lejana ≈ 9–13 ms. El cálculo acumulado en hilos de toda la sesión de capturas pasó de ≈ 5,8 s a
  ≈ 11,3 s (más chunks detallados en vistas medias), siempre fuera del hilo principal y con el mismo
  presupuesto de subida por frame (5 ms). Textura de ríos: 70–150 ms una vez al iniciar el país.
- Si hiciera falta bajar el costo: `MAX_LOW` (150) y `LOW_DIST_MAX` (7,5 km) en `terrain.gd`, o
  quitar las copas de la tesela lejana (`forest` en el shader).

## Archivos

Mapa v2 — nuevos: `scripts/world/label_declutter.gd`, `shaders/terrain_chunk_body.gdshaderinc`,
`tests/screenshot_mapa_v2.{gd,tscn}`; modificados: `terrain.gd`, `terrain_look.gd`, `country_overlay.gd`,
`mesh_lib.gd` (style_label), `logistics_visuals.gd`, `mining_visuals.gd`, `minimap.gd`, `water.gdshader`,
`terrain_chunk*.gdshader`, `terrain_grade.gdshaderinc`.

Nuevos: `scripts/world/{sky_rig,graphics_settings,road_mesh,street_lights,vegetation,water_look,terrain_look}.gd`,
`shaders/{building,road,water,foliage,light_pool,terrain_plus,terrain_chunk_plus}.gdshader`,
`shaders/terrain_grade.gdshaderinc`, `tests/screenshot_graficos.{gd,tscn}`.

Modificados: `mesh_lib.gd`, `world.gd`, `transit_visuals.gd`, `trade_visuals.gd`,
`logistics_visuals.gd`, `citizen_agent.gd`, `tourism_visuals.gd`, `mining_visuals.gd` y
`utilities_visuals.gd` (una línea: estilo de etiqueta).
