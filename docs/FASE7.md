# Fase 7 — Otros pueblos, rutas comerciales, comercio exterior, inmigración y transporte

Todo se configura en `data/trade.json`; la infraestructura (estación de tren, puerto, aeropuerto) está en
`data/businesses_comercio.json`. La lógica vive en `scripts/sim/trade_sim.gd`; la interfaz en
`scripts/ui/trade_panel.gd` (botón *Comercio exterior*) y el camino del mapa en `scripts/world/trade_visuals.gd`.

## Otros pueblos
- Al iniciar se generan de 4 a 6 pueblos (semilla propia: no altera el resto de la simulación) con nombre, distancia
  (35–150 km), población, tipo (real de minas, villa maderera, pueblo agrícola, villa de artesanos, pueblo cantero,
  ciudad, puerto), bienes que **producen** (y te venden) y bienes que **demandan** (y te pagan mejor).
- Siempre hay un real de minas, una villa maderera, un pueblo agrícola y una villa de artesanos: lo que tu región no
  tiene (carbón, hierro, oro, plata, madera, herramientas…) se puede comprar.
- En mapas de costa o río algunos pueblos tienen acceso por agua (barcos).

## Rutas comerciales (una por pueblo)
- Abrir la ruta cuesta **acuerdo de paso** (`agreement_base + agreement_per_km × km`) + **camino de barro**
  (`cost_per_km × km`), todo × dificultad × inflación. La obra tarda según la distancia.
- El camino evoluciona con reformas pagadas: barro → empedrado (`caminos_empedrados`) → carretera de cemento
  (`automovil`). Mejor camino = viajes más rápidos y más inmigración. Con `ferrocarril` se puede tender una **vía férrea**.
- Mantenimiento mensual por km de camino/vía y de la flota del medio elegido.
- En el mapa se ve **un solo camino** que sale de la plaza hacia el borde oeste (barro, empedrado o carretera con
  línea central, y vía férrea al lado), con carretas que van y vienen según los envíos en camino.

## Comercio
- **Vender** saca del almacén de la compañía (`WarehouseSim`); el flete se paga al despachar y el pueblo **paga al
  llegar** (`gs.add_money`, contador `exports`, `EconomySim.record_value("exports")`).
- **Comprar**: se paga al despachar (bienes + flete); el **arancel** del gobierno (`GovSim.import_mult`) va al tesoro;
  la carga llega al almacén tras el viaje (se reserva espacio; si no cabe, espera).
- Precios propios por pueblo y bien: multiplicadores de compra/venta, **saturación** (si les vendes mucho baja lo que
  pagan; se recupera según su demanda mensual), **escasez** al comprarles mucho, fluctuación mensual (volatilidad ×
  `event_freq_mult` de la dificultad), eventos locales (auges/excesos) y ajuste por dificultad (`difficulty` en trade.json).
- **Contratos automáticos**: vender o comprar X unidades cada N días, con precio límite opcional; se pueden pausar.

## Transporte externo
| Medio | Tecnología | Requisitos | Capacidad | Notas |
|---|---|---|---|---|
| Cargadores y mulas | — | — | 25 | Lento; los sueldos van a desempleados del pueblo |
| Carretas de bueyes | `carretas` | camino | 80 | Mantenimiento de bueyes |
| Barco | `navegacion` | mapa costa/río, puerto con personal, pueblo con agua | 300 | |
| Ferrocarril | `ferrocarril` | estación de tren con personal + vía férrea | 500 | La estación central (nivel 2) lleva más |
| Camiones | `automovil` | carretera de cemento | 150 | Gasolina por km |
| Avión de carga | `aviacion` | aeropuerto con personal | 40 | Muy rápido y caro |

Cada viaje cuesta: fijo + por km + gasolina + sueldos de la tripulación × días. Por defecto se usa el medio
disponible más barato por unidad; el jugador puede elegir otro en cada ruta.

## Inmigración
- **Solo llega gente por las rutas** (sin rutas, la población solo crece por nacimientos).
- Familias por mes = `base_families_month` × factor de conexiones (población del pueblo, distancia, calidad del
  camino y del transporte) × atractivo (empleo/vacantes, vivienda libre, felicidad, salarios).
- Llegan solteros, parejas o familias con hijos (`PopulationSim.create_citizen`). Si hay una choza del pueblo con
  espacio se instalan ahí; si no, quedan **sin hogar** y el mercado de vivienda mensual les busca alquiler o
  autoconstruyen (presión para construir). Se notifica cada llegada.

## Contrato para otras fases
- `TradeSim.connected_towns(gs)` → `gs.trade["connections"]` (solo rutas terminadas; cada una con `town_id`,
  `town_name`, `distance`, `road`, `rail`, `mode`…). `TradeSim.is_connected_any(gs)`.
- `TradeSim.connection_factor(gs)` y `TradeSim.attractiveness(gs)` pueden servir al turismo (Fase 8).

## Pruebas
`godot --headless res://tests/test_fase7.tscn` — pueblos, rutas, compra/venta, contratos, evolución del transporte,
guardado determinista, dificultad, interfaz/visuales y diagnóstico de balance (1 y 2 rutas durante 3 años).
