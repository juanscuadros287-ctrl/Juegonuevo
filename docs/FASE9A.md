# Fase 9A — País continuo por chunks, biomas, niebla, minimapa y cámara de país

Diseño general en `docs/MAPA_MUNDIAL.md`. Esta fase convierte el mapa de 400 m en un **país** de
**24 a 40 chunks de 400 m por lado** (de 9,6 a 16 km), en un solo mapa continuo. El pueblo del jugador conserva exactamente su terreno de siempre en el chunk central.

## Conceptos: revelar ≠ comprar
| | Qué es | Cómo | Dónde |
|---|---|---|---|
| **Revelar** | Ver territorio (sale de la niebla) | Inicio: pueblo + 8 vecinos. Expediciones pagadas (minimapa → Ampliar). Rutas comerciales abiertas. Comprar una parcela. | `GameState.map.chunks_revealed` |
| **Comprar** | Ser dueño y poder construir | Construir → Comprar terreno (parcelas de 80 m, la misma lógica de siempre, ahora también fuera del pueblo) | `GameState.unlocked_zones` (índices globales) |

Al comprar una parcela, su chunk queda revelado y la malla se rehace **al instante** (`Terrain.build_mesh`),
sin cargas ni teletransporte: se une al terreno que ya tenías.

## Países (`data/countries.json`)
Cinco países ficticios con inspiración real; cada uno define tamaño (`size`, 24–40), perfil de terreno
(`terrain`: montaña, altura de picos, bosque, lagos, ríos, desierto, pantano, islas, mesetas, cañones, humedad,
temperatura, gradiente de latitud y lados con costa), municipios (`zones`, `town_ratio`), abundancia de recursos
(`resources`), y los campos de economía por país para la Fase 10 (`currency {name, symbol}`, `base_inflation`,
`exchange_rate_to_ref`; aún no se usan).

| País | Tamaño | Inspiración | Carácter |
|---|---|---|---|
| Andoria | 32×32 | Andes y Amazonía | cordilleras nevadas, cañones, selva al sur, muchos ríos |
| Pampaverde | 30×30 | Pampa y litoral | llanura, lagunas, ríos lentos, costa este |
| Islas Coralinas | 30×30 | Caribe, Filipinas | archipiélago, selva, manglares, mucha pesca |
| Arenalia | 34×34 | Marruecos, Sonora, Atacama | desierto, mesetas escalonadas, cañones, oasis, minerales |
| Nordhavia | 36×36 | Noruega, Patagonia | bosque boreal, lagos, nevados, fiordos al oeste |

El país se elige en el menú de partida nueva (se propone uno según el tipo de mapa: `default_by_map_type`).
Sus recursos ajustan los yacimientos y fortalezas de los lugares de fundación (`MapSim.apply_country_resources`,
llamado desde `RegionSim.candidates`).

## Generación (`scripts/world/country_gen.gd`, clase `CountryGen`)
- Chunk `(cx, cy)` cubre `[cx·400−200, cx·400+200]`; el `(0, 0)` es el del pueblo (plaza en 0,0).
- `old_height` es copia literal del terreno de antes (mismo ruido, río, costa y cordillera según `map_type`).
  Dentro del chunk del pueblo la altura es exactamente esa; entre 200 y 680 m se mezcla con el relieve del país.
- Relieve del país con ruido en coordenadas **globales** (sin costuras): continente, colinas, cordilleras
  (máscara × crestas), mesetas escalonadas con escarpes, lagos, ríos largos (líneas de cero de un ruido
  deformado, cruzan muchos chunks; se ensanchan en deltas cerca del mar y se encajonan en cañones), costas del
  país por lados, islas. Los rasgos del tipo de mapa se prolongan: el río del mapa *Río* sigue serpenteando
  por todo el país, la bahía de *Costa* se abre, la cordillera de *Montaña* crece al norte.
- Clima por latitud (norte más frío), altura y humedad → biomas: mar, costa, río/lago, pantano, llanura,
  bosque, selva, desierto, montaña y nevado, con colores y vegetación propios.
- Municipios: Voronoi de chunks (con bordes irregulares). Cada municipio tiene o no un pueblo (`town`), en un
  chunk de tierra cerca de su semilla; el del jugador es el municipio 0 con el pueblo en (0,0). La 9B les
  pondrá nombre y política; hoy llevan un nombre provisional (`placeholder_name`).
- Es de solo lectura tras `init()`: se usa desde hilos.

## Terreno con streaming y LOD (`scripts/world/terrain.gd`)
- La API de siempre se mantiene: `generate`, `height_at`, `is_land`, `zone_of`, `is_unlocked`, `build_mesh`,
  `set_season`, `scatter_nature`, `make_water`, `clear_trees`, `ray_ground`, `footprint_ok`, y los campos
  `heights`, `half`, `cell`, `RES`, `water_level` (WaterSim y RegionSim los usan).
- `height_at` en el pueblo usa la rejilla de 2,5 m de siempre; fuera, la misma interpolación sobre la rejilla
  global de 2,5 m (continua en los bordes, con caché).
- `start_country()` (lo llama el mundo) crea todos los chunks del país + un anillo exterior de 2 en bruma:
  - **Lejano** (8×8 celdas, 50 m): todo el país, en tandas de 24 chunks por hilo; además pinta el minimapa.
  - **Medio** (20×20, 20 m) hasta 2,8 km de la cámara (máx. 48), con copas de árboles simplificadas.
  - **Alto** (80×80, 5 m) hasta 700 m (máx. 9), con árboles completos por bioma. El pueblo usa su malla de siempre.
  - Mallas indexadas con faldones (sin grietas entre LODs) y normal plana en el shader
    (`shaders/terrain_chunk.gdshader`, estilo low-poly sin duplicar vértices).
  - Cálculo en `WorkerThreadPool` (hasta 3 hilos); la subida a la escena tiene un presupuesto de 5 ms por frame.
    Tiempos medidos (`test_mapa`): alto ≈ 60 ms (en hilo), medio ≈ 5 ms, lejano ≈ 1 ms; pueblo 160×160 ≈ 90 ms.
  - Lo no revelado se dibuja con la misma malla lejana y el material de bruma (relieve tenue, nunca un vacío).
- `CountryOverlay` (`scripts/world/country_overlay.gd`): líneas tenues entre municipios y marcadores de los
  pueblos (casco urbano low-poly, punto y nombre; "sin explorar" en la niebla), visibles al alejarse.
- Agua: un solo plano al nivel del mar que cubre el país.

## Cámara de país (`scripts/world/camera_rig.gd`)
- Igual que antes hasta 330 m. Luego se aleja hasta ver el país completo (`max_dist` ≈ lado del país × 1,08,
  unos 13–16 km), con inclinación más cenital, plano lejano y cercano dinámicos y niebla más leve en altura.
- Paneo más rápido a gran altura; límites = rectángulo del país; zoom en escala logarítmica.
- **M**: ver país / volver al pueblo. **H**: volver al pueblo. También botones en el minimapa.

## Minimapa (`scripts/ui/minimap.gd`)
Esquina inferior izquierda del HUD (junto al menú). Capas: biomas con relieve, niebla, fronteras de municipios,
tu terreno (dorado), pueblos (el tuyo dorado; los de la niebla en gris), yacimientos, carreteras, rutas
comerciales y el encuadre de la cámara. Clic o arrastre mueve la cámara. **Ampliar** abre el mapa grande con
información del territorio (bioma, altura, temperatura relativa, municipio, parcelas propias) y **Enviar
expedición** (costo y días crecen con la distancia; revela el chunk y sus 8 vecinos al volver).

## API pública (`scripts/sim/map_sim.gd`, clase `MapSim`)
- `chunk_of(x, z)`, `chunk_rect(cx, cy)`, `country_rect(gs)`, `country_bounds_m(gs)`, `in_country(gs, x, z)`.
- `is_revealed(gs, cx, cy)`, `reveal(gs, cx, cy)`, `reveal_around(gs, pos, radius)` (gancho para TradeSim y 9B).
- `biome_at(x, z)`, `height_at(x, z)`, `slope_at(x, z)`, `climate_at(x, z)` (temperatura, humedad, altura,
  bioma y °C relativos al pueblo; WeatherSim puede leerlo).
- `owner_of(gs, x, z)` → `"jugador"`, dueño privado de `map.parcels` (9B), `"estado"` o `""` fuera del país.
- `zone_at(gs, x, z)` (parcela de 80 m en índices globales), `municipality_at(gs, x, z)`, `municipalities(gs)`.
- `region_at(gs, x, z)`: stub con una sola región (la 9B la divide).
- `terrain_cost_mult(a, b, gs, include_water)` y `terrain_cost_mult_path(points, gs, include_water)`:
  multiplicador del costo de una vía por pendiente (excavar), cresta (túnel), agua (puente), cañón y altura
  (parámetros en `countries.json → terrain_cost`). Enganchado en `RoadSim.segment_cost` y en
  `TransitSim.road_plan` (allí sin agua, porque TransitSim ya cobra los puentes). GridSim puede usarlo igual.
- Expediciones: `expedition_cost/days/block_reason`, `start_expedition`, `daily`.
- `trade_town_pos(gs, town_id)`: posición provisional de un pueblo comercial (Fase 7) en el país; al abrir una
  ruta, `daily` revela el pueblo y el corredor del camino.
- `currency(gs)`: moneda e inflación base del país (Fase 10).

## Guardado y migración
`GameState.map = {country_id, chunks_revealed {"cx,cy": true}, expeditions, expeditions_done, parcels,
regions, routes_revealed}`; `settings.country_id`. Una partida vieja (sin `map`) se convierte en país según su
tipo de mapa, con su terreno en el chunk central, el pueblo y sus 8 vecinos revelados y sus parcelas compradas.

## Pruebas y capturas
- `tests/test_mapa.tscn`: países y municipios, chunk del pueblo idéntico al terreno viejo (4 tipos de mapa),
  costuras (ruido, `height_at` y mallas vecinas), río que cruza chunks, revelado, `owner_of`, compra que se une
  al instante, expediciones, revelado por rutas, costo de vías por terreno, guardar/cargar, migración, tiempos de
  construcción y el mundo con streaming, cámara de país y minimapa.
- Capturas (`tests/screenshot_mapa.tscn`): `docs/capturas/pais_zoom_maximo.png`, `pais_biomas.png`, `minimapa.png`.

## Pendiente para la 9B
Nombres y políticas de municipios/regiones, dueños privados (`map.parcels`), posiciones reales de los pueblos de
comercio (hoy `trade_town_pos` es provisional), carreteras y TransitSim fuera del chunk del pueblo
(`TransitSim._inside_map` sigue limitado a los 400 m).
