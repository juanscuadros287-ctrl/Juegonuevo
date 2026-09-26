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

Sin tocar la generación ni el LOD: `TerrainLook.apply(terrain)` (una línea en `world.gd`) cambia el
shader de los materiales existentes por copias con la gradación de
`shaders/terrain_grade.gdshaderinc` (pasto menos "neón", manchas secas y húmedas, leve
oscurecimiento a distancia). Los uniformes se llaman igual, así que estación, nieve y niebla siguen
funcionando. **Si la Fase 9B cambia `terrain.gdshader` o `terrain_chunk.gdshader`, hay que llevar el
cambio a las copias `*_plus` (o quitar la línea del enganche).**

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

## Archivos

Nuevos: `scripts/world/{sky_rig,graphics_settings,road_mesh,street_lights,vegetation,water_look,terrain_look}.gd`,
`shaders/{building,road,water,foliage,light_pool,terrain_plus,terrain_chunk_plus}.gdshader`,
`shaders/terrain_grade.gdshaderinc`, `tests/screenshot_graficos.{gd,tscn}`.

Modificados: `mesh_lib.gd`, `world.gd`, `transit_visuals.gd`, `trade_visuals.gd`,
`logistics_visuals.gd`, `citizen_agent.gd`, `tourism_visuals.gd`, `mining_visuals.gd` y
`utilities_visuals.gd` (una línea: estilo de etiqueta).
