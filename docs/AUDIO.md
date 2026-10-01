# Audio — música, efectos y ambiente

Todo el audio de Dinastía es **procedimental y propio**: lo genera `tools/make_audio.py` con
síntesis (Karplus-Strong para cuerdas pulsadas, aditiva para piano, cuerdas y metales, FM para el
piano eléctrico y campanas, ruido filtrado para ambientes) y una reverb por convolución con
respuesta al impulso sintética. **No se usan muestras ni paquetes de terceros**, así que no hay
licencias que cumplir. Total: ~13 MB en OGG Vorbis (límite 25 MB).

## Arquitectura

| Pieza | Archivo | Qué hace |
|---|---|---|
| Buses | `default_bus_layout.tres` | Master ← Music (con filtro paso bajo), SFX, Ambience, UI |
| Opciones | `scripts/audio/audio_settings.gd` (`AudioSettings`) | volúmenes, silencio, música por época, pista; `user://audio.cfg` |
| Motor | `scripts/autoload/audio_manager.gd` (autoload `AudioManager`) | música, efectos, ambiente, sonido 3D |
| Archivos | `assets/audio/{music,sfx,amb}/*.ogg` | generados por `tools/make_audio.py` |
| Prueba | `tests/test_audio.tscn` | buses, opciones, música por época, eventos, voces, headless |

`AudioManager` **solo lee** el estado (GameState, TimeManager, nodos del mundo) y tiene su propio
generador aleatorio: no toca `GameState.rng` ni altera la simulación ni su determinismo.
Detecta el contexto solo: escena con `camera_rig` y partida en marcha → juego; escena con
`slots_box` → menú principal; cualquier otra (pruebas) → silencio.

Integración con la interfaz (cambios mínimos):
- `hud.gd`: `toast()` llama a `AudioManager.on_toast()`; `_open/_close` de ventanas y
  `_animate_dock` (paneles) llaman a `AudioManager.panel()`; Opciones incluye
  `AudioSettings.build_ui()`; el menú de Esc tiene «Sonido y música» (abre Opciones).
- `main_menu.gd`: botón «Opciones» con sonido y calidad gráfica.
- Todos los botones (`BaseButton`) y pestañas (`TabBar`/`TabContainer`) suenan solos: el
  AudioManager se engancha a `SceneTree.node_added`, sin tocar cada panel.

## Opciones (Esc → Opciones o «Sonido y música»; también en el menú principal)

- Deslizadores **General, Música, Efectos, Ambiente, Interfaz** (0–100 %, cada uno a su bus).
- **Silenciar todo** (silencia Master).
- **Música según la época** (sí/no). Si no, alterna entre las 9 piezas del juego.
- **Pista**: «Automática» (varía sola con fundidos) o una pieza fija que se repite en bucle.
- Se guarda en `user://audio.cfg` (junto a `ui_settings.cfg` y `graficos.cfg`) y se aplica al
  arrancar (`AudioManager._ready` → `AudioSettings.apply()`).

## Música

| Id | Título | Instrumentación | Tonalidad · tempo |
|---|---|---|---|
| `menu` | Dinastía (menú) | cuerdas, arpa, flauta, trompa, timbal | Re mayor · 72 |
| `colonial_1` | Plaza de la Colonia | guitarra punteada, flauta, arpa, tambor de marco, maraca | Sol mayor · vals 96 |
| `colonial_2` | Caminos de herradura | guitarra, flauta, arpa | La dórico · 104 |
| `colonial_3` | Atardecer en la hacienda | arpa, cuerdas, flauta, guitarra | Re mixolidio · 78 |
| `industrial_1` | Vapor y progreso | piano (Alberti), metales, chelo, escobillas | Do mayor · 100 |
| `industrial_2` | Talleres del río | piano, chelo, cuerdas, metales | La menor · 80 |
| `industrial_3` | La gran estación | coral de metales, piano, timbal | Fa mayor · 92 |
| `moderna_1` | Luces de ciudad | lo-fi: piano eléctrico, sub-bajo, batería con swing, sinte suave | Fa lidio · 78 |
| `moderna_2` | Café digital | lo-fi: ii–V–I con novenas y trecenas, celesta | Re dórico · 84 |
| `moderna_3` | Horizonte | ambient: pad de sintetizador, arpegios de celesta | Mi♭ mayor · 70 |
| `crisis` | Tiempos difíciles | chelos, piano escaso | Re menor armónico · 64 |

Cómo se componen: progresiones de acordes por sección (intro · A · B · A · final), acordes con
conducción de voces (inversión más cercana a la anterior), melodías por **motivos** (pregunta que
termina abierta y respuesta que cae en la tónica; la sección A repite su motivo para que se
recuerde), notas fuertes sobre notas del acorde y notas de paso ajustadas al acorde (sin choques
de semitono), humanización leve de tiempo y dinámica, envolventes ADSR en todo, reverb y
limitador suave. Cada pieza (65–105 s) se pliega sobre sí misma para que el bucle no corte.

Reglas en el juego:
- Menú principal → `menu`. Partida → piezas de la época actual (`TechSim.era`), en orden
  aleatorio sin repetir la anterior, con 4–14 s de silencio entre piezas y **fundido cruzado** de 3 s.
- **Crisis** (dinero negativo o ciclo económico del país en «crisis»): entra `crisis`.
- **Noche o crisis**: el filtro paso bajo del bus Music baja suavemente (música más «oscura»).
- Al cambiar de época la pieza actual se funde con una de la nueva época.

## Efectos

**Interfaz** (bus UI, 4 voces): `ui_click` (botones), `ui_tab` (pestañas), `ui_open` / `ui_close`
(paneles y ventanas), `notif_info`, `notif_good` (nacimiento, boda, negocio, obra terminada),
`notif_bad` (muerte, salud, emigración, avisos), `notif_important` (importante, familia),
`money_in` / `money_out` (el dinero cambia justo después de una acción del jugador; los cambios
por el paso del tiempo no suenan), `error` (avisos de error del HUD). Máximo un aviso cada 0,35 s;
en saltos de años y a ×3 no suenan.

**Mundo 3D** (bus SFX, **10 voces** en un pool de `AudioStreamPlayer3D`, atenuación por distancia
inversa a la cámara, filtro por distancia; si se llena se roba el efecto suelto más lejano):
- `construction_loop`: martillos y serrucho en las 2 obras más cercanas al punto que mira la cámara.
- Vehículos (3 más cercanos, el sonido sigue al modelo): `cart_loop` (mula, carreta; comercio en la
  época colonial), `steam_loop` (carro de vapor), `truck_loop` (camión, tráiler; comercio después),
  `bus_loop` (transporte público).
- `train_whistle` + `train_loop` cada 45–110 s si hay una vía férrea cerca; `ship_horn` en la
  costa desde la época industrial; `plane_pass` en la época moderna.
- `church_bell` a las 6, 12 y 18 h (2, 3 y 2 campanadas) desde la iglesia o la plaza, a ×1 o menos.
- `thunder_1/2` durante las tormentas (en el bus de ambiente).

**Ambiente** (bus Ambience, capas en bucle de 20 s con fundidos): `amb_birds` (de día, sin lluvia),
`amb_crickets` (de noche, grillos y alguna rana), `amb_wind` (montaña, frío, tormenta, altura),
`amb_river` / `amb_sea` (según el agua alrededor y si el mapa es de costa), `amb_town_1/2/3`
(pueblo colonial con cascos y campanillas · taller industrial con golpes y vapor · tráfico
moderno), `amb_rain`, `amb_storm`, y `amb_general` (con zoom muy alejado reemplaza a las capas
locales; los efectos 3D dejan de asignarse).

## Rendimiento

- Pools fijos: 2 reproductores de música, 4 de interfaz, 10 3D y una capa por ambiente (se
  crean al primer uso y se detienen en silencio).
- El mundo se escanea una vez por segundo (obras, vehículos, agua, pueblo); cada fotograma solo
  se mueven los ≤ 5 emisores asignados.
- Streams cargados bajo demanda y reutilizados.
- En headless (pruebas) Godot usa el driver de audio Dummy y todo funciona igual.

## Regenerar el audio

```
pip install numpy scipy soundfile        # soundfile trae libsndfile con Vorbis
python3 tools/make_audio.py              # todo (≈1 min con 4 núcleos)
python3 tools/make_audio.py music        # solo música  (también: sfx, amb)
python3 tools/make_audio.py --only colonial_1,ui_click
python3 tools/make_audio.py --check      # pico, RMS, DC y recorte, sin escribir
godot --headless --import                # genera los .import de los archivos nuevos
```

Sin `soundfile` usa `oggenc` o `ffmpeg` si están; si no, escribe WAV de 16 bits (el juego carga
`.ogg` o `.wav` indistintamente). Es determinista: misma versión del script → mismos archivos.
Para cambiar una pieza, edita su función `piece_*` (tonalidad, modo, tempo, progresiones y plan de
capas) y regenera solo esa con `--only`.
