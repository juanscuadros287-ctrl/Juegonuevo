# Trabajo y mundo — secciones B y D de PENDIENTES

Pedido de Sebastián: "dentro de la medida de lo normal, nada exagerado". Todo es moderado, raro y con aviso.
La configuración está en `data/trabajo_mundo.json` y las tecnologías nuevas en `data/technologies_clima.json`.

## Resumen para el jugador
- **Experiencia por oficio.** Cada empleado acumula años en su sector (la habilidad del negocio: agricultura,
  minería, artesanía…). Con 10 años es veterano: rinde **+20 %** (lineal: 5 años = +10 %) y pide hasta un
  **10 % más de sueldo**. Se ve en la pestaña **Empleados**, en la lista de candidatos ("oficio 4.2 a (+8 %)") y
  en la ficha del ciudadano (**Oficios**). Si renuncia o lo despides, la experiencia se va con él y la competencia
  NPC puede contratarlo.
- **Sindicatos y huelgas** (desde la Revolución industrial). En un negocio con 3 empleados o más, si los sueldos
  están bajo el mercado, la felicidad es baja o falta personal (demasiadas horas), los empleados pueden organizarse:
  cada mes hay a lo sumo un **10 %** de probabilidad (según la presión). Primero **piden un aumento** (6–18 %) y
  te avisan. En la pestaña Empleados puedes **Aceptar**, hacer una **Contraoferta** (la mitad) o **Rechazar**.
  Una contraoferta de al menos la mitad se acepta con probabilidad creciente; si no, o si rechazas o no respondes
  en 14 días, hay una **huelga de 3 a 10 días** con la producción al **0–30 %**. Termina sola con un **acuerdo**
  (la mitad del aumento pedido). Después, un año de calma en ese negocio.
- **Competencia NPC.** Las empresas NPC que venden lo mismo que tú pueden **bajar precios** unos 30–75 días
  (máx. 12 %, y solo lo que les permite su margen: nunca venden a pérdida; si pierden dinero no bajan). A veces
  **ofrecen más sueldo** (+12–22 %) a tu empleado más experimentado del mismo oficio: te avisan y en la pestaña
  Empleados puedes **Igualar** o **Dejarlo ir**. Si no respondes en 7 días, se va con un 70 % de probabilidad.
- **Clima y estaciones.** Sequías, heladas, inundaciones, olas de calor y malas cosechas según la estación y el
  clima de la zona (`MapSim.climate_at`: un pueblo seco sufre más sequías, uno frío o alto más heladas, uno de
  río más inundaciones). Afectan al **agro** (granja, trigal, algodonal, rebaño, estancia, colmenar, huerto de
  hierbas), cada edificio según su clima local; la **inundación** también a los edificios **junto al río**
  (menos producción y una reparación). Mientras duran **suben los precios** de los bienes agrícolas (los
  procesados —harina, pan, carne— la mitad). **Pronóstico**: casi siempre hay aviso unos días antes (las heladas
  solo con el telégrafo). En promedio ~4 % de probabilidad mensual y 60 días de calma entre eventos.
- **Mitigación con tecnología** (nuevas): *Canales de riego* (colonial: sequía −50 %, ola de calor −30 %, plagas
  −15 %), *Diques y encauzamiento* (industrial: inundación −65 %), *Invernaderos* (moderna: helada −65 %, plagas
  −30 %, sequía −20 %). La tecnología también atenúa el alza de precios.
- **Contaminación.** Industrias pesadas, centrales de carbón o gas, minas y refinerías emiten según su nivel
  (`pollution`) y su producción (empleados/puestos). Se **acumula en la zona** y enferma y entristece a los
  vecinos que viven a menos de 45 m (hasta ×1,6 de probabilidad de enfermar y −6 de felicidad). El panel del
  edificio muestra "Contaminación: X (−Y % con filtros) · acumulada en la zona · N viviendas afectadas" y humo
  proporcional sobre el edificio (capa visual `PollutionVisuals`).
  - **Multas**: las cobra el gobierno según su política (`env_fine`: los virreyes no multan; liberales y
    conservadores poco; el Partido Social más; el Verde mucho) sobre la emisión real. La **licencia ambiental**
    del lobby (PoliticsSim) exime. Llega un aviso mensual con el total.
  - **Filtros y depuradoras**: mejora por negocio en el Resumen del edificio. Con *Filtros industriales*
    (industrial) −50 % (cuesta 25 % del nivel, mantenimiento 2 %/mes); con *Precipitadores electrostáticos*
    (moderna) −80 % (35 %, 2,5 %/mes). El equipo se importa (el dinero sale del pueblo).
  - **Renovables**: las centrales eólica, solar e hidroeléctrica no contaminan.
- **Guerras entre países sin combate.** Rara (0,6 % mensual, desde el año 2 y con 5 años de calma después):
  entre dos países ficticios de `data/countries.json` (nunca el tuyo) o potencias externas. Durante 4–12 meses
  sube la demanda (precio de mercado ×1,10–1,25) de 3–5 bienes (acero, hierro, carbón, alimentos, ropa,
  calzado, combustible…), se encarece (×1,3–1,6) o **corta** (×2, contrabando) la importación de 2–4 bienes
  (maquinaria, motores, componentes, medicamentos…), y los pueblos conectados piden un bien de guerra (sus
  precios de exportación ×1,3). Aviso al empezar y al terminar; termina sola.

## Archivos
| Archivo | Contenido |
|---|---|
| `scripts/sim/labor_sim.gd` | `LaborSim`: experiencia por oficio, sindicatos y huelgas, guerras de precio y ofertas NPC. RNG propio (`rf/rr/ri`: semilla + día + sal) |
| `scripts/sim/climate_sim.gd` | `ClimateSim`: eventos por estación y clima de la zona, pronóstico, efecto por edificio (`output_mult`), alza de precios (`price_mult`), inundación junto al río |
| `scripts/sim/pollution_sim.gd` | `PollutionSim`: emisión, acumulación, exposición por vivienda, enfermedad/felicidad, multa, filtros, texto del panel |
| `scripts/sim/war_sim.gd` | `WarSim`: guerras, demanda (`price_mult`), importación (`import_mult`), eventos de pueblos |
| `scripts/world/pollution_visuals.gd` | Humo proporcional sobre los edificios contaminantes |
| `data/trabajo_mundo.json` | Parámetros de todo lo anterior |
| `data/technologies_clima.json` | Canales de riego, diques, filtros industriales, invernaderos, precipitadores (efecto `clima`) |
| `tests/test_trabajo_mundo.gd/.tscn` | Pruebas de todo (ver abajo) |

## Estado y guardado
- `GameState.labor`: `unions` (por id de edificio: `state` demanda/huelga, `pct`, plazos, `factor`), `price_wars`
  (por id de empresa NPC: `until`, `base_markup`, `cut`), `offers` (ofertas a tus empleados), `cooldown`,
  `next_id`, `seeded`.
- `GameState.world_events`: `climate` (`events` con `start/until/sev`, `price` y `bmult` precalculados, `cool_until`),
  `pollution` (`acc` por fuente, `exposure` por vivienda, `fines_last`, `filters_upkeep_last`), `war` (`active`,
  `last_end`, `count`).
- `Citizen.trade_exp` (oficio → años). Edificio: `b["filters"]` (0, 1 o 2).
- Todo con valores por defecto: una partida vieja carga sin estos campos y los adultos reciben parte de su
  experiencia general como experiencia en su mejor habilidad (`initial_share` = 0,5).

## Enganches en archivos compartidos (cambios de una línea)
- `game_state.gd`: variables `labor` y `world_events`, `_clear`, `to_dict/load_dict`, `_init_expansions`
  (init de los 4 módulos), `simulate_day` (diario: `LaborSim/ClimateSim/WarSim.daily` antes de `PlayerSim.daily`;
  mensual: `LaborSim` y `PollutionSim` tras `FreeMarketSim`, `ClimateSim` y `WarSim` tras `EventsSim`).
- `citizen.gd`: campo `trade_exp` (guardado).
- `business_sim.gd`: `productivity` × `LaborSim.exp_mult`; `asked_wage` × `LaborSim.wage_mult`;
  `expected_output` × `LaborSim.strike_mult` × `ClimateSim.output_mult`.
- `npc_business_sim.gd`: `_output` × `ClimateSim.output_mult`.
- `economy_sim.gd`: `good_factor` × `ClimateSim.price_mult` × `WarSim.price_mult` (sube también la referencia de
  los vecinos, así que no compran menos por el alza: pagan más).
- `market_sim.gd`: importación de los vecinos × `WarSim.import_mult(gs, good)`.
- `population_sim.gd`: `_health` × `PollutionSim.disease_mult`; `_happiness` + `PollutionSim.happiness_delta`.
- `events_sim.gd`: la contaminación global suma `PollutionSim.total_emission` (con producción y filtros).
- `gov_sim.gd`: la multa ambiental usa `PollutionSim.fine` (emisión real; respeta la licencia ambiental).
- `tech_sim.gd`: texto del efecto `clima`.
- UI: `building_panel.gd` (líneas de contaminación/clima/sindicato en el resumen, botón de filtros, caja del
  sindicato y de ofertas en Empleados, experiencia por oficio), `hud.gd` (Oficios en la ficha), `world.gd`
  (`PollutionVisuals`).
- **No** se tocaron map_sim, country_gen, terrain, trade_sim, construction_sim ni transit_sim. La guerra escribe en
  `gs.trade.towns[i]["event"]` (el mecanismo de eventos de pueblo que ya existe), solo si el pueblo no tiene uno
  vigente, y lo borra al terminar.

## Economía cerrada
- Sueldos (aumentos, acuerdos, ofertas igualadas): del jugador o de la caja NPC a los ciudadanos.
- Multas: del jugador al tesoro. Huelga, clima, precios y guerra: no mueven dinero por sí mismos.
- Salen del pueblo (como el mantenimiento o las importaciones): filtros (compra y mantenimiento) y la reparación
  por inundación. Nada crea dinero (lo verifica la prueba).
- Cada sistema usa su propio RNG determinista, así el resto de la simulación no cambia su secuencia aleatoria.

## Pruebas
`godot --headless res://tests/test_trabajo_mundo.tscn`: datos y árbol sin superposiciones; experiencia (+20 %
veterano, sueldo, acumulación, se va con él y la NPC lo contrata); sindicato colonial no, pedido, rechazo, huelga
que baja la producción y termina con acuerdo, plazo vencido, aceptar y contraoferta; guerra de precios sin pérdida
y fin, oferta de sueldo igualada / rechazada / vencida; sequía con pronóstico que baja la producción agrícola y
sube el precio, riego e invernaderos que mitigan, inundación junto al río y diques; contaminación que se acumula y
enferma a los vecinos, casas lejanas sin efecto, multa, filtro que la reduce, mantenimiento, licencia ambiental,
renovables y virreyes sin multa; guerra que cambia precios e importaciones y termina; dinero conservado; guardado,
carga y partida vieja.
