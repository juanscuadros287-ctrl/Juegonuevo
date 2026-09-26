# Fase 10 — Varios países, viajes, gerentes y aviación

Diseño general en `docs/MAPA_MUNDIAL.md` (sección Fase 10). Sigue a la Fase 9B (`docs/FASE9B.md`).

## Resumen para el jugador
1. **Entrar a otro país** (Mi dinastía → *Mis países y mapa mundial*, o clic en el indicador del país en la barra
   superior): eliges un país en el mapa mundial y compras la **licencia de inversión** (precio según el país:
   Perú ≈ $5.400, EE. UU. ≈ $13.200 en normal). Al comprarla se genera el país: su mapa real por chunks,
   municipios, pueblo con ~26 habitantes, gobierno con su tesoro e impuestos. Luego compras el **terreno de
   entrada** (la parcela central del pueblo, al Estado de ese país): desde ahí tienes **presencia**, y desde ahí
   compras más terreno allá como siempre.
2. **Viajar**: el personaje está en un solo país. Mapa mundial → *Viajar*. Toma días y cuesta según la distancia
   real y la época: barco de vela y diligencia (colonial, 170 km/día), barco de vapor y tren (industrial, 520 km/día),
   avión comercial (con Aviación, 9000 km/día). Colombia → Perú: 1818 km, 11 días en la época colonial y 1 en avión.
   De viaje no estás en ningún país. Al llegar, la cámara pasa a ese país.
3. **Ver otro país**: *Ver país* muestra un país donde tienes presencia. Si no estás ahí y no tienes gerente es
   **vista remota**: se ve, pero no se puede construir ni comprar terreno.
4. **Gerentes**: donde no está tu personaje hace falta un gerente local (un ciudadano de ese país). Tres niveles
   (Administrador, Gerente experimentado, Director ejecutivo) con sueldo mensual y eficiencia según su habilidad.
   Sin gerente ni presencia **las obras no avanzan** y tus negocios rinden al 55 %. El gerente pide aumentos (tienes
   30 días para responder), con lealtad baja puede **renunciar** o **robar** (moderado: parte de un sueldo, con
   tope del 2 % de tu dinero, y te avisa). Esto también vale para tu país de origen cuando viajas.
5. **Aviación** (Logística y transporte → *Aviación*):
   - El **Aeropuerto** es un almacén grande (3000 / 8000 espacios): los camiones distribuyen desde ahí con las rutas
     de la Fase 6.
   - **Hangar**: compras aviones de carga (400 por viaje, mantenimiento diario, combustible por km). **Dentro del
     país** vuelan entre dos aeropuertos tuyos con las rutas de *Logística → Transporte* (manuales o automáticas;
     mucho más rápidos que los camiones). **Entre países** vuelan con *Enviar carga por avión* (manual) o con
     rutas automáticas del panel Aviación. El avión regresa vacío y queda ocupado hasta volver.
   - **Vuelo comercial**: sin aviones propios; pagas por unidad (según la distancia) y cada salida (cada 3 días) lleva
     como máximo 150 unidades por ruta; lo que no cabe va en la siguiente. Sirve también dentro del país.
   - **Entre países la mercancía solo va por avión** (propio o comercial). Al llegar pagas el **arancel del destino**
     sobre el valor del bien allá, convertido a su moneda con el tipo de cambio.
6. **Una sola cuenta**: el mismo dinero en todas partes. Los montos de otro país se muestran también en su moneda
   (p. ej. "0,93 S/ (≈ $1000)").
7. **Indicador** en la barra superior: "En Colombia", "De viaje a Perú (3 d)" o "En Perú · viendo Colombia (remoto)".

## Diseño técnico: contexto por país

GovSim, MapSim, TradeSim, LogisticsSim, etc. están hechos para **un** país (leen `GameState.map`,
`GameState.government`, `GameState.buildings`…). En vez de reescribirlos, cada país con presencia tiene su propio
juego de esos campos y se **intercambian las referencias** (no se copian datos):

| Por país (se intercambian) | Global (compartido) |
|---|---|
| `citizens`, `buildings`, `government`, `problems`, `logistics`, `trade`, `tourism`, `market`, `realestate`, `economy`, `map`, `transit`, `utilities`, `labor`, `world_events`, `weather`, `season`, `unlocked_zones` y `settings.town_name/region/country_id` | `money` y `cash` (una sola cuenta), jugador y familia (viven en el país de origen), `techs`, `research`, `loans`, `world_econ` (ciclos y monedas), `informal`, historial, avisos, ids de ciudadanos y edificios (únicos en la partida) |

- En `GameState` están siempre los datos del país **activo** (el que dibuja el mundo 3D, que así renderiza solo ese
  país). Los demás esperan en `countries.stash[iso]`.
- `CountriesSim.swap_to(iso)` / `with_country(iso, fn)` cargan otro país; `with_country` bloquea `EventBus` si ese
  país no es el que se ve (el mundo 3D no reacciona) y sus avisos se muestran al final con el prefijo `[País]`.
- **Día** (`GameState.simulate_day`): 1) pase principal en el **país de origen** con todo lo global (jugador,
  banco, bolsa, investigación, historial); 2) un pase por cada otro país con presencia: `simulate_country_day(new_month,
  false)` corre la simulación **completa** del país (población, negocios, obras, mercado, gobierno, logística,
  comercio, turismo, redes…) sin lo global; 3) vuelve al país activo; luego `TravelSim.daily` y `AirSim.daily`.
- **Gobierno por país**: cada país tiene su `government` (tesoro, régimen, misiones) creado con `GovSim.init_state`,
  más una **capa de modificadores** (`data/fase10.json → countries`): `tax_mult` (impuestos de renta, propiedad y
  nómina; `government.tax_mult`, 1 en el país de origen), `tariff` (arancel base a la carga aérea), `license_mult` y
  `stability`. El país de origen no cambia (multiplicadores 1).
- **Precios y cambio**: cada país tiene su `economy.price_level` (inflación propia). Además, `price_mult()` del país
  cargado se multiplica por `CountriesSim._fx_mult` = desvío real de tu moneda / desvío real de la del país (0,8–1,25,
  1 en tu país): si su moneda está débil, allá todo te sale más barato.
- Los países **sin** presencia siguen en modo NPC resumido en `GlobalEconSim` (ciclos, inflación y monedas).
- Cachés estáticas sin país en la clave (RealEstateSim, GridSim, WarehouseSim, WaterSim, TransitSim, MarketSim) se
  invalidan al intercambiar; `MapSim` guarda hasta 4 generadores de país (`_gens`) para no rehacerlos.
- `buildings[i].country_id` y `Citizen.country_id`: se marcan al crear (`ConstructionSim.make_building`) y al
  intercambiar o cargar (`CountriesSim.stamp`).

### Archivos nuevos
| Archivo | Qué hace |
|---|---|
| `data/fase10.json` | licencia, modificadores por país, coordenadas de los países de respaldo, medios de viaje, gerentes y aviación |
| `scripts/sim/countries_sim.gd` | `CountriesSim`: estado, licencia y entrada, intercambio de contexto, pases del día, control remoto, rendimiento, resumen, dinero total, guardado |
| `scripts/sim/travel_sim.gd` | `TravelSim`: distancia real (haversine entre países del mapa mundial), medio por época, cotización, viaje y llegada |
| `scripts/sim/manager_sim.gd` | `ManagerSim`: candidatos, contratar/despedir, eficiencia, sueldo, lealtad, aumento, renuncia y robo |
| `scripts/sim/air_sim.gd` | `AirSim`: aeropuertos, flota, vuelos propios y comerciales, arancel y cambio, rutas automáticas entre países |
| `scripts/ui/countries_window.gd` | `CountriesWindow`: pestañas *Mapa mundial* (licencia, terreno, viajar, ver) y *Mis países* (presencia, gerente, resultados) |
| `scripts/ui/game_world_map.gd` | `GameWorldMap` (hereda `WorldMap`): presencia, dónde estás, viaje en curso y aviones en vuelo |
| `scripts/ui/aviation_window.gd` | `AviationWindow`: aeropuertos, hangares y flota, vuelos, rutas y formulario de envío |
| `scripts/ui/country_indicator.gd` | `CountryIndicator`: barra superior; al llegar de un viaje pide al HUD cambiar de país |
| `tests/test_fase10.gd/.tscn` | pruebas · `tests/screenshot_fase10.gd/.tscn` capturas |

### Ganchos en archivos compartidos (1–3 líneas cada uno)
- `game_state.gd`: `var countries`, `_clear`, `to_dict`/`load_dict`, `CountriesSim.init_state` en `new_game` y
  `load_dict`; `simulate_day` → `day_begin` + `simulate_country_day(new_month, primary)` + `day_end` (lo global con
  `if primary`); `init_country_systems`; `price_mult × CountriesSim._fx_mult`; prefijo y avisos diferidos en `notify`.
- `citizen.gd`: `country_id` (guardado). `construction_sim.gd`: `country_id` en `make_building`/`normalize_building`;
  obras del jugador solo avanzan con `CountriesSim.works_advance()` (× `work_mult`); `build_block_reason` y
  `zone_block_reason` con `control_block_reason` (vista remota).
- `business_sim.gd`: `expected_output × CountriesSim.op_mult()`. `gov_sim.gd`: impuestos × `government.tax_mult`.
- `logistics_sim.gd`: se quitó el rechazo de "fase posterior"; el avión exige dos aeropuertos
  (`AirSim.domestic_block_reason`); `vehicle_busy` respeta `air_busy_until` (vuelo internacional).
- `map_sim.gd`: caché de varios generadores (`_gens`, `_use_gen`).
- `hud.gd`: `CATEGORIES` (+ "Mis países y mapa mundial" en Mi dinastía, + "Aviación" en Logística), las dos
  ventanas, el indicador en la barra y `switch_country` (recarga la escena con el país elegido).
- `logistics_visuals.gd`: modelo de avión de carga que despega, cruza y aterriza.
- Datos: `resources.json` (avión sin `planned`), `businesses_recursos.json` (hangar sin `planned`),
  `businesses_comercio.json` (aeropuerto con `warehouse_capacity` 3000/8000).

## Dinero (economía cerrada)
- Licencia → tesoro del país destino. Terreno de entrada → tesoro del país destino. Sueldo del gerente → bolsillo
  del gerente (ciudadano de ese país). Robo → bolsillo del gerente. Arancel → tesoro del país destino.
- Salen de la economía (proveedores extranjeros, como una importación) y quedan contados en
  `countries.stats.outflow`: pasajes, combustible de los aviones y fletes comerciales.
- `CountriesSim.money_total` suma todas las economías simuladas + tu cuenta + el dinero fuera de los pueblos;
  la prueba comprueba que `money_total + outflow` no cambia con terreno, sueldo, flete + arancel y pasaje.

## Rendimiento (medido en `test_fase10`, CPU del contenedor, 30 días por medición)
| Países con presencia | ms por día simulado |
|---|---|
| 1 (Colombia) | ≈ 7,4–8,3 |
| 2 (+ Perú) | ≈ 16–17 |
| 3 (+ Chile) | ≈ 21 |

Por país (media móvil, `CountriesSim.perf()`; no se guarda porque no es determinista): Colombia ≈ 9 ms, Perú ≈ 6 ms, Chile ≈ 6,5 ms. El costo crece
linealmente con la población y los edificios de cada país (un país nuevo empieza con ~26 habitantes); el intercambio de
contexto cuesta < 1 ms. A x3 (1 s = 1 semana) son 7 días por segundo: con 3 países ≈ 150 ms por segundo real,
y el salto de años (x4) sigue con su presupuesto de 12 ms por frame. Generar un país real al comprar la licencia
tarda ≈ 0,3–1 s (una sola vez).

## Guardado
`GameState.countries` se guarda (los ciudadanos de los países guardados como diccionarios; los edificios se
normalizan al cargar). Sin `SAVE_VERSION` nuevo: una partida vieja queda con **un solo país** (el de su mapa), el
personaje en él y todos sus edificios y ciudadanos marcados con ese `country_id`.

## Pruebas y capturas
- `tests/test_fase10.tscn`: partida vieja con un país, licencia y entrada (precio por país, pago al tesoro, mapa y
  municipios del país, capa de impuestos, activar otro país), viaje (distancia real, días, costo, época, llegada),
  gerentes y obras (vista remota, obra detenida sin gerente, avanza con gerente y donde está el personaje,
  sueldo, robo/renuncia/aumento), avión dentro del país (aeropuerto almacén, solo entre aeropuertos, más rápido que
  el camión, llega), carga entre países solo por avión con arancel y tipo de cambio, vuelo comercial (capacidad,
  precio por unidad, siguiente salida, vuelo interno), dinero conservado, guardar y cargar, rendimiento con 2 y 3
  países e interfaz.
- Capturas (`tests/screenshot_fase10.tscn`) en `docs/capturas/fase10/`: `mapa_mundial_presencia.png`,
  `mis_paises.png`, `aviacion.png`, `avion_en_ruta.png`, `vista_remota_peru.png`.

## Límites conocidos
- El puerto como vía de carga entre países (opcional) no está: entre países solo avión.
- La vista remota sin gerente bloquea construir y comprar terreno; otras órdenes (precios, contratar) siguen
  disponibles en los paneles.
- El efectivo y el IVA (Sección E, `informal`) son globales: el IVA de las ventas en otro país lo cobra el gobierno
  del país de origen (se liquida primero en el pase principal). El dinero se conserva.
- La familia del jugador vive siempre en el país de origen (el pase principal); viajar mueve solo al personaje.
- El historial mensual (`history`) y las gráficas son del país de origen; los resultados de los demás países están
  en *Mis países* (`presence[iso].last_month`).
- Los países de respaldo (`data/countries.json`) no están en el mapa mundial: en esas partidas se eligen en la lista
  del panel; su distancia usa coordenadas inventadas (`fallback_coords`).
