# Fase 9B — Mapa mundial con países reales, municipios grandes, mercado de tierras y pueblos NPC

Diseño general en `docs/MAPA_MUNDIAL.md` (sección CAMBIO). Sigue a la Fase 9A (`docs/FASE9A.md`).

## 1. Mapa mundial con países reales
- **Datos de dominio público**, descargados una sola vez en desarrollo (`tools/world_fetch.py` → `tools/raw/`, ignorado
  por git) y preprocesados con `tools/build_world.py` (requiere `numpy` y `h5py` solo en desarrollo):
  - Natural Earth: fronteras admin-0 (1:50m países jugables, 1:110m mapa mundial), ríos y lagos 1:50m, lugares
    poblados 1:10m, desiertos (regiones 1:50m).
  - Relieve ETOPO1 (NOAA) remuestreado a 10′ (Fatiando a Terra).
  - Licencias y atribución: `data/world/ATRIBUCION.md`. En tiempo de ejecución no se descarga nada.
- Archivos del juego (2,4 MB): `data/world/world.json` (177 países para el mapa mundial),
  `data/world/profiles.json` (38 países jugables: moneda, idioma, inflación, recursos reales y del juego; `default`
  para el resto) y `data/world/countries/<ISO>.json` (rejilla de 200 m del país a escala del juego, en gzip+base64:
  altura real, máscara de frontera, tierra/mar, lagos, desiertos, distancia y ancho de ríos; lugares poblados reales).
- **Escala**: 1 chunk (400 m) ≈ extensión real / N, con N = extensión (km) / 26, entre 40 (países pequeños) y 72
  (enormes); la rejilla cuadrada llega a 80 con el margen. Colombia: 71 chunks de país (1 chunk ≈ 27 km), Uruguay 40,
  Brasil/Rusia 72. Se conserva la forma (máscara real), costas, cordilleras (ETOPO), ríos y lagos, y el clima por
  latitud y altura reales (+ desiertos de Natural Earth y la franja subtropical).
- Tu pueblo se funda en un lugar poblado real de altura baja o media cerca del centro (o el del perfil: Colombia →
  Barrancabermeja). Ese punto es el (0, 0): **el chunk central sigue siendo el terreno viejo** (probado en Colombia).
- Municipios sembrados en los lugares poblados reales (Bogotá, Medellín, Cali…), con su nombre; los pueblos de
  comercio (TradeSim/TownEconomySim) toman el nombre real de su municipio.
- **Pantalla del mapa mundial** (`scripts/ui/world_map.gd`, clase `WorldMap`): continentes y países reales,
  jugables coloreados por continente; clic para ver perfil (idioma, moneda, inflación, recursos, escala) y "Elegir".
  En el menú de partida nueva: selector de país + botón **Mapa mundial…**. Por defecto Colombia.
- Los 5 países ficticios (`data/countries.json`, ahora de 60–76 chunks) quedan como **respaldo de pruebas**: una
  partida sin `country_id` sigue usándolos según el tipo de mapa.
- Código: `WorldData` (`scripts/world/world_data.gd`) lee y decodifica; `CountryGen` tiene el modo real
  (`real`, `_country_real`, `_climate_real`, `real_elevation`, `real_lat/lon`, `places`); `in_country` e
  `in_country_chunk` siguen la frontera real.

## 2. Más grande
- Municipios de 6×6 a 10×10 chunks (mediana 51–96 según el país; 30–60 municipios en los países de respaldo,
  6–60 en los reales según su superficie). Voronoi con relajación de Lloyd y bordes irregulares; el municipio del
  jugador contiene su pueblo y los 8 vecinos.
- **Al inicio se revela todo tu municipio**; los municipios vecinos se ven con velo ligero.
- Capa lejana en **teselas de 4×4 chunks con celdas de 80 m** (normales suaves, colores suavizados), un solo
  material con texturas de niebla/municipios/recorte; los chunks detallados recortan la tesela en el shader.

### Tiempos medidos (`test_mapa`, CPU del contenedor; la captura usa llvmpipe, mucho más lento)
| Malla | Cálculo (hilo) |
|---|---|
| Alta 80×80 (5 m) | ≈ 60–115 ms |
| Media 20×20 (20 m) | ≈ 5–8 ms |
| Tesela lejana 4×4 chunks (80 m) | ≈ 7–8 ms |
| Colombia completa (441 teselas) | ≈ 3,6 s de CPU ≈ 1,2 s con 3 hilos |
| Generación del país real (CountryGen) | 20–60 ms |
Mientras haya mallas detalladas pendientes cerca de la cámara, la capa lejana usa un solo hilo.

## 3. Niebla y lectura visual (`shaders/terrain_chunk.gdshader`)
- Velo translúcido (desatura y aclara, deja ver relieve y biomas): 0 explorado, 0,22 vecinos, 0,45 sin explorar,
  0,8 otros países; interpolado entre chunks (bordes suaves).
- Fronteras de municipio dibujadas en el shader (tenues, más cálidas alrededor del tuyo; ancho según la altura).
- Nombres grandes de municipios (Label3D de tamaño fijo) y el tuyo en dorado.
- Vista media: normales suaves por vértice lejos y facetas low-poly solo de cerca (mezcla por distancia).
- Cámara de país casi cenital (86°) y encuadre de la frontera real (no del cuadrado).

## 4. Regiones y municipios (`MunicipalSim`, `data/municipios.json`)
- `GameState.map.regions`: nombre, departamento, población, **política** (impuesto local ±, salario mínimo local,
  regulación baja/media/alta, precio base del suelo), **alcalde** NPC con postura y mandato de 4 años (al cambiar,
  la política se mueve), tesoro municipal y exención. `map.departments`: 5 departamentos con gobernador.
- `MapSim.region_at` devuelve el municipio real (id `m<n>`, política, alcalde, departamento, gobernador).
- Reglas aplicadas a lo que construyes: impuesto local sobre la ganancia del negocio (GovSim, al tesoro del
  municipio; negativo = rebaja), salario mínimo local (GovSim), sobrecosto de permisos por regulación.
  Tu municipio empieza neutro (no cambia el balance del pueblo).
- **Misiones regionales** (cada 4 meses, máx. 3): abrir negocios, comprar parcelas, abrir ruta, dar empleo o
  construir camino en un municipio explorado; recompensa en dinero y meses sin impuesto local.

## 5. Mercado de tierras (`LandSim`)
- Territorio = chunk (25 parcelas de 80 m). Dueño: Estado, particular NPC (nombre) o jugador. Dueño por defecto
  determinista (Estado cerca de tu pueblo, en cascos urbanos y agua; resto repartido), cambios en `map.parcels`.
- Precio = suelo base del municipio × bioma/yacimientos × cercanía a pueblos × carreteras/rutas × demanda × índice
  mensual del municipio (paseo aleatorio) × nivel de precios.
- Estado: precio fijo (salvo regulación alta) o **licitación** (garantía, rival 85–120 % del precio, 10 días).
- Particular: **oferta** que acepta o rechaza en 2–5 días (≥115 % acepta, <85 % rechaza).
- Libre comercio: 1–4 ventas NPC por mes (ciudadanos con ahorros también compran). Registro en `map.land_sales`.
- La compra se une al instante (25 parcelas en `unlocked_zones`, chunk revelado, malla rehecha).
- Parcela suelta al gobierno fuera del pueblo: precio de mercado; dentro del chunk del pueblo, la fórmula de siempre.
- Interfaz: minimapa → Ampliar: municipio, alcalde, política, dueño, precio, Comprar / Licitar / Ofertar, misión del
  municipio, trámites en curso y **capa de propiedad** (Estado / particulares / tuyo).

## 6. Pueblos NPC con posición real
- `MapSim.assign_towns` ubica los pueblos de TradeSim en municipios con pueblo (`map.town_assign`);
  `trade_town_pos` es su posición real. Distancia de ruta ajustada por la real con límites ×0,85–×1,15 (solo en países reales; los de respaldo conservan las distancias de la Fase 7).
- Abrir una ruta revela **todo su municipio** y el corredor.
- Cascos urbanos: casas low-poly proporcionales a la población (2 MultiMesh para todo el país).
- Carreteras fuera del pueblo por tierra propia o del Estado explorada (`MapSim.public_way_ok`); TransitSim usa los
  límites del país; WaterSim y el panel de logística conocen el relieve y las parcelas fuera del pueblo.

## 7. Guardado y migración
Campos nuevos en `GameState.map`: `regions`, `departments`, `region_missions`, `town_assign`, `parcels` (por
territorio), `land_offers`, `land_tenders`, `land_sales`, `land_index`, `land_demand`. Partidas 9A: se crean con
valores por defecto, se revela el municipio del jugador y se ubican los pueblos.

## 8. Pruebas y capturas
`tests/test_mapa.tscn` amplía la 9A con: tamaño de municipios, política aplicada a un negocio (impuesto, rebaja,
salario), misiones, compra al Estado (fijo y licitación) y a un particular (rechaza y acepta), precio que fluctúa y
ventas NPC, pueblo NPC en su municipio, ruta que revela el municipio, carretera fuera del pueblo, guardar/cargar,
migración 9A, países reales (perfiles, escala, frontera, nombres, relieve andino, chunk central idéntico en
Colombia) y botón Comprar/capa de propiedad en el minimapa.
Capturas (`tests/screenshot_mapa.tscn`): `docs/capturas/pais_completo.png` (Colombia con zoom máximo),
`municipio.png`, `propiedad.png` y `mapa_mundial.png`.
