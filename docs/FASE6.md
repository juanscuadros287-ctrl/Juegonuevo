# Fase 6 — Recursos por región, almacén, cadenas de producción y transporte interno

## Resumen para el jugador
1. **Elige dónde fundar** (menú *Nueva partida → Lugar de fundación*): 3-4 lugares según el tipo de mapa y la semilla.
   Cada uno es fuerte en ciertos recursos (oro, plata, carbón, hierro, madera, piedra, tierra fértil, pastos, pesca) y trae
   **yacimientos** ubicados en el mapa (mini-mapa en el menú, marcadores 3D con banderín en el juego).
2. **Extrae materias primas**: minas de oro/plata/carbón/hierro (solo junto a un yacimiento de su tipo; lo agotan
   lentamente), campo de trigo, algodonal, rebaño de ovejas, además del leñador y la cantera de siempre.
3. **Almacén de la compañía**: las materias primas y productos van al almacén (1 unidad = 1 espacio). La bodega de la plaza
   da 200 espacios; el edificio **Almacén** (Bodega → Almacén de ladrillo → Depósito industrial → Centro logístico) suma más.
4. **Talleres con recetas** toman insumos del almacén y guardan productos más caros:
   molino (2,2 trigo → 1 harina), herrería (1 hierro + 1 carbón → 1 herramientas), tejeduría (2 lana → 1 tela),
   hilandería (2 algodón → 1 tela), sastrería (1,2 tela → 1 ropa), orfebrería (1 oro → 1 joyas).
5. **Transporte interno**: las minas y campos **lejos** de un almacén (más de 30 m) guardan su producción en el sitio.
   Crea **rutas** (panel *Logística → Transporte*): origen, destino, bien, cantidad y medio; **manual** (un envío) o
   **automática** (cada X días lleva X). Los cargadores (a pie) y arrieros (caballos y carretas) son empleados de la
   **Central de transporte** (sin estudios, con salario; los caballos tienen mantenimiento diario).
6. **Carreteras** (panel *Logística → Carreteras*): solo las necesitan caballos, carretas y vehículos. Tramos de barro
   (y empedrados con la tecnología *Caminos empedrados*), con costo por metro, dibujados sobre el terreno.
7. La **Tienda** vende ropa, herramientas y joyas del almacén a los ciudadanos (consumo discrecional); lo principal se
   venderá afuera (Fase 7). La madera y piedra del almacén sirven para construir.

## Diseño técnico

### Archivos
| Archivo | Contenido |
|---|---|
| `data/resources.json` | recursos, regiones por tipo de mapa, radios, transporte (medios) y carreteras (tipos). `GameData.extra("resources")` |
| `data/goods_recursos.json` | materias primas, productos elaborados (`shop_sale`), `transporte` (interno) |
| `data/businesses_recursos.json` | minas, campos, talleres con recetas y la Central de transporte (generado con modelos low‑poly) |
| `data/buildings_logistica.json` | edificio Almacén (`warehouse_capacity` por nivel) |
| `scripts/sim/region_sim.gd` | `RegionSim`: candidatos de región, yacimientos, multiplicador regional, agotamiento |
| `scripts/sim/road_sim.gd` | `RoadSim`: tramos, costos, red conexa (unión de tramos), conexión y velocidad |
| `scripts/sim/logistics_sim.gd` | `LogisticsSim`: cadenas de producción, puntos de almacén, rutas, envíos, cargadores |
| `scripts/sim/warehouse_sim.gd` | API estable + `value`, `shop_context`, `shop_sell` |
| `scripts/ui/logistics_panel.gd` | panel con pestañas Región, Almacén, Producción, Transporte, Carreteras |
| `scripts/ui/region_preview.gd` | mini-mapa del menú de nueva partida |
| `scripts/world/logistics_visuals.gd` | marcadores de yacimientos, carreteras, modo carretera, agentes de transporte |
| `tests/test_fase6.gd` | pruebas y diagnóstico de rentabilidad de la cadena |

### Estado (`GameState.logistics`, se guarda solo)
```
region      {id, label, name, place, description, strengths:{recurso: mult}, deposits:{tipo: n}}
deposits    [{id, type, x, z, amount, initial}]
warehouse   {bien: cantidad}                      (WarehouseSim)
roads       [{id, ax, az, bx, bz, kind}]          (RoadSim)
routes      [{id, from, to, good, qty, mode, auto, every, next_day, remaining, active, moved, status, trips}]
shipments   [{route, good, qty, from, to, mode, crew:[[central_id, n]], carriers, depart, travel, trips, arrive, back, ax, az, bx, bz, delivered}]
stats       {month_moved, last_month_moved, total_moved}
```
`GameState.settings["region"]` guarda el id del lugar elegido. Las partidas antiguas o sin región reciben la primera
candidata al cargar (`LogisticsSim.init_state`).

### Esquema de datos de negocios (acordado con la Fase 8)
En el **nivel** del negocio (o en la definición, como respaldo):
- `"inputs": {"bien": cantidad_por_unidad}` → se consumen del inventario local del edificio y luego de `WarehouseSim`;
  si faltan, la producción se limita proporcionalmente (`chain_status` = "faltan insumos: …" y aviso).
- `"output": "warehouse"` → lo producido va a `WarehouseSim.add`. Si el almacén está lleno la producción se limita
  (sin gastar insumos de más) y se avisa. Sin este campo se mantiene el comportamiento anterior.
- `"requires_deposit": "oro"` → solo se construye a menos de `deposit_radius` (11 m) de un yacimiento de ese tipo con
  mineral; la extracción descuenta del yacimiento; agotado, la mina no produce.
- En la definición: `"extraction": true` (campos) y `"region_resource": "tierra_fertil"` (multiplicador regional).
  Los negocios originales usan `business_resource` de `resources.json` (granja → tierra fértil, pescadería → pesca…).
- En el nivel de la central: `"transport_modes": ["pie", "carreta"]`, `"vehicle_upkeep"` (por empleado y día × `price_mult`).
- En un bien: `"shop_sale": true` → la Tienda (o un negocio con `"warehouse_shop": true`) lo vende desde el almacén.

`BusinessSim.produce` delega en `LogisticsSim.produce_chain` cuando el negocio usa alguno de esos campos
(`LogisticsSim.uses_chain`). Orden: espacio disponible → yacimiento → insumos → guardar.

### Transporte: decisión de diseño
- **Talleres y fábricas** (con `inputs`/`output` pero sin `extraction`): siempre toman del almacén y guardan en él
  (la compañía mueve la mercancía dentro del pueblo). Así los datos de la Fase 8 funcionan sin rutas.
- **Extracciones** (`requires_deposit` o `extraction`): si están a menos de `warehouse.walk_reach` (30 m) de la bodega
  de la plaza o de un Almacén, sus trabajadores descargan directo. Si están más lejos, la producción queda en el sitio
  (inventario del edificio, tope `storage_cap`) y hay que traerla con una **ruta** o construir un Almacén al lado.
  Los yacimientos iniciales se generan a 33-37 m de la plaza, justo fuera del alcance: la primera decisión logística es
  construir un almacén junto a la mina o contratar cargadores.
- **Rutas**: puntos de origen/destino = bodega de la plaza (id 0), almacenes y tus negocios. Un envío toma la carga del
  origen al salir y la entrega al llegar (si el destino no tiene espacio, lo que sobra vuelve al origen).
  Viaje: distancia × `route_factor` / velocidad del medio (× velocidad de la carretera). Si la ida y vuelta cabe en
  la jornada, cada cargador hace varias vueltas al día (máx. 4). Los cargadores quedan ocupados hasta regresar.
  Una ruta con `road: true` exige que origen y destino estén a menos de `roads.reach` (12 m) de la misma red.
- **Medios** (`resources.json → transport.modes`): a pie 10 u./viaje, 180 m/día-juego; caballos y carretas
  60 u./viaje, 360 m/día, requiere `carretas` y carretera; camiones 250 u./viaje con `automovil`.

### Carreteras
Tramos rectos de 3-80 m en terreno propio y fuera del agua (el mundo 3D lo verifica). Costo por metro × `price_mult`
(el empedrado además usa piedra del almacén/negocios o la importa). Los extremos se ajustan a extremos existentes a
menos de 3 m; los tramos que se tocan o cruzan forman una red. "Empedrar todos" convierte el barro con descuento.
Construcción inmediata (simplificación). Modo de colocación en `LogisticsVisuals`: clic inicio, clic fin (encadena),
clic derecho o Esc termina.

### Cambios en archivos compartidos (mínimos)
- `business_sim.gd`: `expected_output` × `RegionSim.region_mult`; `produce` salta el producto interno `transporte` y
  delega en `LogisticsSim.produce_chain` para negocios con recetas/almacén/yacimiento.
- `construction_sim.gd`: `stock_of` incluye el almacén; `_consume_stock` usa el almacén después de los negocios;
  `placement_block_reason` agrega `RegionSim.deposit_block_reason`.
- `market_sim.gd`: `discretionary` reserva `shop_share` (35 %) del gasto semanal para productos del almacén en tus
  tiendas cuando los hay (sin tienda o sin productos, nada cambia).
- `main_menu.gd`: selector *Lugar de fundación* + mini-mapa; pasa `"region"` a `GameState.new_game`.

### Balance (diagnóstico en `tests/test_fase6.gd`)
Con precios base y trabajadores normales, un empleado genera ≈ 4 de valor al día (salario ≈ 2,2), igual que los
negocios existentes. Ejemplo en Fácil: 2 mineros de hierro + 2 de carbón + 4 herreros, 60 días: costos ≈ $1.190,
valor producido ≈ $2.575 a precio de mercado (herramientas $4,67 vs hierro $1,36 + carbón $0,85). La Tienda solo vende
una parte al pueblo; el grueso se exportará en la Fase 7.
