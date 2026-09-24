# Fase 6 — Recursos por región, almacén, cadenas de producción y transporte interno

## Resumen para el jugador
1. **Elige dónde fundar** (menú *Nueva partida → Lugar de fundación*): 3-4 lugares según el tipo de mapa y la semilla.
   Cada uno es fuerte en ciertos recursos (oro, plata, carbón, hierro, madera, piedra, tierra fértil, pastos, pesca) y trae
   **yacimientos** ubicados en el mapa (mini-mapa en el menú, marcadores 3D con banderín en el juego).
2. **Extrae materias primas**: minas de oro/plata/carbón/hierro (solo junto a un yacimiento de su tipo; lo agotan
   lentamente), campo de trigo, algodonal, rebaño de ovejas, además del leñador y la cantera de siempre.
3. **Almacenes individuales**: cada almacén tiene su PROPIO stock y su capacidad máxima (1 unidad = 1 espacio). La bodega
   de la plaza (200 espacios) es el almacén principal y la salida del pueblo; cada edificio **Almacén** (Bodega → Almacén
   de ladrillo → Depósito industrial → Centro logístico) es otro almacén con su capacidad.
   **Vínculo por adyacencia**: una fábrica, taller, mina o campo construido AL LADO de un almacén (a menos de 12 m entre
   bordes) queda vinculado y se marca en **verde** (anillo, banderín y flecha hacia su almacén; al colocarlo, el ghost se
   pinta verde brillante y aparece la flecha). Toma los insumos y guarda lo que produce SOLO en ese almacén; si se llena,
   la producción se detiene con aviso. Sin almacén al lado (anillo **rojo**, ghost ámbar), lo producido queda en el sitio
   y los insumos deben llegar con rutas. Captura: `docs/capturas/almacen_verde.png`.
4. **Talleres con recetas** toman insumos de su almacén vinculado y guardan ahí productos más caros:
   molino (2,2 trigo → 1 harina), herrería (1 hierro + 1 carbón → 1 herramientas), tejeduría (2 lana → 1 tela),
   hilandería (2 algodón → 1 tela), sastrería (1,2 tela → 1 ropa), orfebrería (1 oro → 1 joyas).
5. **Transporte interno con flota**: crea **rutas** (panel *Logística → Transporte*) entre almacenes, entre fábrica y
   almacén o hacia la salida del pueblo: origen, destino, bien, cantidad, medio y **vehículo** (uno concreto o cualquiera
   libre); **manual** (un envío; con vehículo asignado, UN viaje hasta su capacidad) o **automática** (cada X días lleva X).
   Cada medio tiene su capacidad por viaje y cada vehículo sale de su edificio:

   | Medio | Carga/viaje | Edificio donde se compra | Requiere | Costo diario |
   |---|---|---|---|---|
   | Cargadores a pie | 10 | Central de transporte (son empleados) | — | salario |
   | Mulas de carga | 25 | **Caballeriza** | — (sin carretera) | alimento |
   | Carretas de caballos | 60 | **Caballeriza** | *Carretas de tiro* + carretera | alimento |
   | Carros de carga a vapor | 140 | **Depósito de camiones** | *Máquina de vapor* + carretera empedrada/cemento | mant. + combustible/km |
   | Camiones de carga | 250 | **Depósito de camiones** | *Automóvil* + carretera empedrada/cemento | mant. + combustible/km |
   | Tráileres | 600 | **Depósito de camiones** (Terminal de carga) | *Industria automotriz* + cemento | mant. + combustible/km |
   | Aviones de carga | 400 | **Hangar** (previsto) | *Aviación* — fase posterior | — |

   Cada vehículo necesita un conductor o arriero (empleado sin estudios de su edificio); los vehículos libres limitan
   los viajes a la vez. El Depósito admite un **surtidor de combustible** propio (−30 % de combustible).
   **Compra automática de insumos**: una ruta automática desde la bodega de la plaza con «Comprar en la salida del pueblo»
   compra lo que falte al precio de importación y lo lleva (con un tope opcional de stock en el destino).
6. **Carreteras** (panel *Logística → Carreteras*): solo las necesitan carretas y vehículos. Tramos de barro, empedrados
   (*Caminos empedrados*) y de cemento (*Automóvil*), con costo por metro, dibujados sobre el terreno. Botones para mejorar
   todos los tramos más lentos a empedrado o a cemento.
7. La **Tienda** vende ropa, herramientas y joyas del almacén a los ciudadanos (consumo discrecional); lo principal se
   venderá afuera (Fase 7). La madera y piedra del almacén sirven para construir.

## Diseño técnico

### Archivos
| Archivo | Contenido |
|---|---|
| `data/resources.json` | recursos, regiones por tipo de mapa, radios, almacenes (`warehouse.link_distance`, `plaza_half`, `plaza_capacity`), transporte (medios con capacidad, precio, mantenimiento, combustible, edificio base) y carreteras (tipos). `GameData.extra("resources")` |
| `data/goods_recursos.json` | materias primas, productos elaborados (`shop_sale`), `transporte` (interno) |
| `data/businesses_recursos.json` | minas, campos, talleres con recetas, Central de transporte, **Caballeriza**, **Depósito de camiones** y **Hangar** (previsto) |
| `data/buildings_logistica.json` | edificio Almacén (`warehouse_capacity` por nivel) |
| `scripts/sim/region_sim.gd` | `RegionSim`: candidatos de región, yacimientos, multiplicador regional, agotamiento |
| `scripts/sim/road_sim.gd` | `RoadSim`: tramos, costos, red conexa (unión de tramos), conexión y velocidad |
| `scripts/sim/logistics_sim.gd` | `LogisticsSim`: cadenas de producción, rutas, envíos, estaciones y vehículos individuales, combustible, compra automática |
| `scripts/sim/warehouse_sim.gd` | almacenes individuales, vínculo por adyacencia, API agregada estable + por almacén, `value`, `shop_context`, `shop_sell` |
| `scripts/ui/logistics_panel.gd` | panel con pestañas Región, Almacén, Producción, Transporte (flota y rutas por vehículo), Carreteras |
| `scripts/ui/warehouse_tab.gd` | pestaña "Almacén" del panel de edificio (stock/capacidad/abastece, o almacén vinculado verde/rojo) |
| `scripts/ui/fleet_tab.gd` | flota de una estación: comprar/vender vehículos, surtidor (pestaña "Vehículos" y panel de Logística) |
| `scripts/ui/region_preview.gd` | mini-mapa del menú de nueva partida |
| `scripts/world/logistics_visuals.gd` | yacimientos, carreteras, modo carretera, agentes (cargador, mula, carreta, carro de vapor, camión, tráiler), indicadores verde/rojo de vínculo, etiquetas de almacén y ghost verde |
| `tests/test_fase6.gd` | pruebas y diagnóstico de rentabilidad de la cadena |
| `tests/test_almacenes.gd` | almacenes individuales, vínculo, flota, rutas por vehículo, combustible, compra automática, UI |
| `tests/screenshot_almacen.gd` | captura `docs/capturas/almacen_verde.png` |

### Estado (`GameState.logistics`, se guarda solo)
```
region      {id, label, name, place, description, strengths:{recurso: mult}, deposits:{tipo: n}}
deposits    [{id, type, x, z, amount, initial}]
warehouses  {"<id>": {bien: cantidad}}             (WarehouseSim; "0" = bodega de la plaza; claves String)
roads       [{id, ax, az, bx, bz, kind}]          (RoadSim)
routes      [{id, from, to, good, qty, mode, auto, every, next_day, remaining, active, moved, status, trips,
              vehicle, buy, max_stock, spent}]
shipments   [{route, good, qty, from, to, mode, crew:[[estación, n]], vehicles:[ids], carriers, depart, travel, trips,
              arrive, back, ax, az, bx, bz, delivered, fuel, bought}]
vehicles    [{id, mode, base, name, bought, km, trips}]   next_vehicle_id
stats       {month_moved, last_month_moved, total_moved, month_fuel, last_month_fuel, total_fuel}
```
En los edificios: `b["warehouse_id"]` (almacén vinculado, -1 = ninguno; se recalcula al construir, terminar, mover y
demoler) y `b["fuel_pump"]` en los depósitos de camiones. **Migración**: las partidas con el antiguo almacén global
(`logistics["warehouse"]`) lo reparten al cargar entre los almacenes con espacio, empezando por la bodega de la plaza.
`GameState.settings["region"]` guarda el id del lugar elegido. Las partidas antiguas o sin región reciben la primera
candidata al cargar (`LogisticsSim.init_state`).

### Esquema de datos de negocios (acordado con la Fase 8)
En el **nivel** del negocio (o en la definición, como respaldo):
- `"inputs": {"bien": cantidad_por_unidad}` → se consumen del inventario local del edificio y luego de SU almacén
  vinculado (`WarehouseSim.warehouse_for`); si faltan, la producción se limita proporcionalmente
  (`chain_status` = "faltan insumos: …" y aviso que dice en qué almacén faltan).
- `"output": "warehouse"` → lo producido va a su almacén vinculado (`WarehouseSim.add_to`). Si está lleno la producción
  se detiene (`chain_status` = "almacén lleno", aviso con el nombre del almacén). Sin almacén al lado queda en el
  inventario local (tope `storage_cap`, mín. 100) → "patio lleno: sin almacén al lado". Sin este campo, nada cambia.
- `"requires_deposit": "oro"` → solo se construye a menos de `deposit_radius` (11 m) de un yacimiento de ese tipo con
  mineral; la extracción descuenta del yacimiento; agotado, la mina no produce.
- En la definición: `"extraction": true` (campos) y `"region_resource": "tierra_fertil"` (multiplicador regional).
  Los negocios originales usan `business_resource` de `resources.json` (granja → tierra fértil, pescadería → pesca…).
- En el nivel de una estación de transporte: `"transport_modes"` (medios que opera), `"vehicles_included"`
  (solo la Central de niveles 2-3, por compatibilidad), `"garage"` (vehículos que se pueden comprar ahí),
  `"fuel_pump_price"`/`"fuel_pump_discount"` (depósito). El mantenimiento de cada vehículo está en el medio (`upkeep`).
- En un bien: `"shop_sale": true` → la Tienda (o un negocio con `"warehouse_shop": true`) lo vende desde el almacén.

`BusinessSim.produce` delega en `LogisticsSim.produce_chain` cuando el negocio usa alguno de esos campos
(`LogisticsSim.uses_chain`). Orden: espacio disponible → yacimiento → insumos → guardar.

### Almacenes y vínculo: decisión de diseño
- **Almacenes individuales** (`WarehouseSim`): bodega de la plaza (id 0, virtual, 200 espacios, medio lado 9 m) y cada
  edificio con `warehouse_capacity`. `ids()` los devuelve con la plaza primero y luego por cercanía a la plaza.
- **Vínculo**: distancia entre bordes de las huellas cuadradas (sin considerar la rotación) ≤ `warehouse.link_distance`
  (12 m). Si hay varios, el más cercano. Solo se vinculan negocios de la cadena (`LogisticsSim.uses_chain`); un almacén
  no se vincula a otro.
- **API agregada** (Fase 7 vende/compra con ella, Fase 8 la usa): `capacity/used/free_space/stock/all_stock` suman todos
  los almacenes; `add` reparte en los que tienen espacio (primero la bodega de la plaza = salida del pueblo, luego los
  más cercanos a ella); `remove` toma de donde haya en el mismo orden. Por almacén: `stock_in`, `add_to`, `remove_from`,
  `capacity_of`, `used_in`, `free_in`, `stock_all_in`, `warehouse_for(gs, b)`, `linked_to(gs, wid)`.
- **Demoler un almacén**: su stock pasa a los demás (lo que no cabe se pierde con aviso) y sus fábricas se revinculan.
- **Nota para la Fase 8**: las fábricas con `inputs`/`output: warehouse` ya NO usan un almacén global: necesitan un
  almacén al lado (o que las rutas les lleven los insumos). En pruebas, poner el almacén a < 12 m del borde o usar
  `WarehouseSim.add_to(gs, WarehouseSim.warehouse_for(gs, fabrica), …)`.

### Transporte: decisión de diseño
- **Rutas**: puntos de origen/destino = bodega de la plaza (id 0, "salida del pueblo"), almacenes y tus negocios. Se
  permiten rutas entre almacenes. Un envío toma la carga del origen al salir y la entrega al llegar (si el destino no
  tiene espacio, lo que sobra vuelve al origen). Viaje: distancia × `route_factor` / velocidad del medio (× velocidad de
  la carretera). Si la ida y vuelta cabe en la jornada, cada unidad hace varias vueltas al día (máx. 4) y queda ocupada
  hasta regresar.
- **Estaciones** (`LogisticsSim.stations`): Central de transporte (cargadores; niveles 2-3 traen 3 carretas / 2 carretas
  + 2 camiones incluidos, por compatibilidad), Caballeriza (mulas, carretas), Depósito de camiones (carros de vapor,
  camiones, tráileres) y Hangar (aviones, previsto: se compran pero no hacen rutas). Los vehículos se compran uno a uno
  (`buy_vehicle`, precio × `price_mult`, `garage` por nivel), se venden al 40 % y, si se demuele su edificio, se venden
  solos. Unidades libres de un medio en una estación = mín(empleados libres, vehículos libres).
- **Ruta con vehículo asignado** (`vehicle`): solo ese vehículo (y un conductor de su edificio). Manual = un viaje.
  Sin vehículo: cualquier unidad libre del medio (primero los incluidos, luego los comprados).
- **Costos**: los animales comen a diario (`upkeep`, rubro "insumos"), los motores tienen mantenimiento ("mantenimiento")
  y gastan combustible por km recorrido (`fuel_per_km` × km de ida y vuelta × `trade.fuel_price` × `price_mult`, rubro
  "insumos" de su estación; −30 % con surtidor).
- **Carreteras por medio**: `road_kinds` del medio (carros de vapor y camiones: empedrado o cemento; tráileres: cemento).
  `RoadSim.connected/speed_mult/components` aceptan una lista de tipos.
- **Compra automática de insumos** (`buy`): solo con origen en la plaza; al despachar compra lo que falte al precio de
  importación × `price_mult` × aranceles (`GovSim.import_mult`), lo paga el negocio destino (o la compañía) y lo carga.
  `max_stock` evita llevar más si el destino ya tiene esa cantidad.

### Carreteras
Tramos rectos de 3-80 m en terreno propio y fuera del agua (el mundo 3D lo verifica). Costo por metro × `price_mult`
(el empedrado y el cemento además usan piedra de los almacenes/negocios o la importan). Los extremos se ajustan a extremos existentes a
menos de 3 m; los tramos que se tocan o cruzan forman una red. "Mejorar todos" convierte los tramos más lentos a
empedrado o a cemento, descontando la mitad de lo ya invertido.
Construcción inmediata (simplificación). Modo de colocación en `LogisticsVisuals`: clic inicio, clic fin (encadena),
clic derecho o Esc termina.

### Cambios en archivos compartidos (mínimos)
- `business_sim.gd`: `expected_output` × `RegionSim.region_mult`; `produce` salta el producto interno `transporte` y
  delega en `LogisticsSim.produce_chain` para negocios con recetas/almacén/yacimiento.
- `construction_sim.gd`: `stock_of` incluye el almacén; `_consume_stock` usa el almacén después de los negocios;
  `placement_block_reason` agrega `RegionSim.deposit_block_reason`. **Almacenes individuales**: llama a
  `LogisticsSim.on_buildings_changed` al iniciar una obra, terminarla y mover un edificio, y a
  `LogisticsSim.before_demolish` + `on_buildings_changed` al demoler (ganchos de una línea).
- `building_panel.gd` (almacenes individuales): pestaña "Almacén" (`WarehouseTab`) en almacenes y negocios de la cadena,
  pestaña "Vehículos" (`FleetTab`) en estaciones de transporte y una línea en el resumen: "Almacén vinculado: X" en
  verde o "ninguno" en rojo.
- `world.gd` (almacenes individuales): en `_update_placement` el material del ghost lo decide
  `LogisticsVisuals.instance.placement_feedback(...)` (verde brillante si queda al lado de un almacén, ámbar si no;
  dibuja la flecha) y la pista agrega `placement_text()`; `cancel_placement` llama a `clear_placement_feedback()`.
- `trade_sim.gd`: sin cambios; usa la API agregada (las importaciones llegan primero a la bodega de la plaza y las
  exportaciones salen de cualquier almacén, primero de la plaza).
- `market_sim.gd`: `discretionary` reserva `shop_share` (35 %) del gasto semanal para productos del almacén en tus
  tiendas cuando los hay (sin tienda o sin productos, nada cambia).
- `main_menu.gd`: selector *Lugar de fundación* + mini-mapa; pasa `"region"` a `GameState.new_game`.

### Balance (diagnóstico en `tests/test_fase6.gd`)
Con precios base y trabajadores normales, un empleado genera ≈ 4 de valor al día (salario ≈ 2,2), igual que los
negocios existentes. Ejemplo en Fácil: 2 mineros de hierro + 2 de carbón + 4 herreros, 60 días: costos ≈ $1.190,
valor producido ≈ $1.575 (margen 32 %) a precio de mercado (herramientas $4,67 vs hierro $1,36 + carbón $0,85). Con
almacenes individuales las tres quedan junto a la bodega de la plaza (200 espacios), que se llena hacia el día 40 y
detiene las minas: hay que ampliar con un Almacén al lado de cada extracción/fábrica y mover el mineral con rutas (o
vender/exportar). La Tienda solo vende una parte al pueblo; el grueso se exporta (Fase 7).

Flota (Fácil, `price_mult` ≈ 1): mula $60 (25 u., alimento $0,12/día), carreta $150 (60 u., $0,35/día), carro de vapor
$1.200 (140 u.), camión $3.000 (250 u., $0,8/día + $4/km), tráiler $8.000 (600 u.). Un camión en una ruta de ≈ 50 m
(empedrada) hace 4 vueltas al día, mueve hasta 1.000 u. por despacho y gasta ≈ $1,3 de combustible ($0,9 con surtidor).
