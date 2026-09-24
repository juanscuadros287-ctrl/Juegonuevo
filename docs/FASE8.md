# Fase 8 — Turismo, publicidad, industria avanzada y dinastía

## Turismo (`scripts/sim/tourism_sim.gd`, `data/tourism.json`, `data/businesses_turismo.json`)
- **Atracciones** (negocios del sector *Turismo*, producto `entrada`): mirador, feria (luego parque de diversiones),
  plaza de toros (luego coliseo y estadio), termas, teatro de temporada, museo y playa (solo en costa). Cada nivel
  tiene `attraction` (puntos de atractivo), `ticket_value` (multiplica el precio de referencia de la entrada), tecnología y modelo 3D.
- **Hospedaje** (producto `alojamiento`): mesón → hotel → gran hotel → resort. Camas = empleados × `prod_per_worker`.
  Los huéspedes se quedan 1–3 noches y pagan cada noche.
- **Los turistas llegan SOLO por las conexiones** (`TradeSim.connected_towns(gs)`): sin conexiones no hay turistas.
  Turistas/día = `tourists_per_point` × atractivo × Σ conexiones (calidad del transporte / (1 + distancia/100) × tamaño
  del pueblo si viene `population`) × felicidad × seguridad (`problems.crime`) × limpieza × publicidad × estación × clima,
  con saturación suave por conexión. Transporte: se lee `transport` (o `quality` numérico) de cada conexión
  (tabla en `tourism.json`, p. ej. carreta 0.6, tren 1.3, avión 2.0).
- Parte de los turistas quiere pasar la noche (más cuanto más lejos): sin camas, la mitad cancela.
- **Gasto** (todo es dinero de afuera, vía `BusinessSim.earn`): entradas (si el precio es aceptable; por encima de la
  referencia van menos), alojamiento y compras en tus negocios (`MarketSim.sellers("ocio"/"comida")`, del inventario).
- **Precio de entrada/noche** configurable desde la pestaña *Precio* de la ficha o desde el panel *Turismo y publicidad → Atracciones*
  (manual o automático = mercado × valor del nivel × margen). Los vecinos también visitan atracciones con sus ahorros (bien discrecional).
- Las obras públicas (plaza, iglesia, puente, acueducto) suman atractivo.
- **Visuales** (`scripts/world/tourism_visuals.gd`): turistas con ropa llamativa, sombrero y mochila que entran por
  el lado de su pueblo, recorren tus atracciones y la plaza, y se van (tope `max_visuals`).

## Publicidad (`scripts/sim/advertising_sim.gd`, `data/advertising.json`)
- Medios: pregonero y carteles (sin tecnología; paga a un vecino → el dinero se queda en el pueblo), periódico (`periodico`),
  radio (`radio`) y TV (`television`) (el dinero sale del pueblo).
- Objetivo: un negocio, todos tus negocios o promoción turística del pueblo (requiere conexiones). Costo mensual
  × dificultad × inflación × audiencia (población o nº de conexiones). Duración 1–24 meses; se cobra cada mes; cancelar cuando quieras.
- `AdvertisingSim.demand_mult(gs, b)` (≥1, usado por `MarketSim`) y `tourism_mult(gs)`: suma de efectos con rendimientos decrecientes y tope.
- **Medios propios** (negocio *Medios de comunicación*: periódico → emisora de radio → canal de TV): descuento en tus campañas
  (50–70%) y venta de espacios publicitarios a anunciantes de los pueblos conectados.
- El panel muestra costo, efecto estimado (demanda, turistas, ventas extra) y campañas activas.

## Industria avanzada (solo datos: `data/businesses_industria.json`, `data/goods_industria.json`, `data/technologies_industria.json`)
Esquema acordado con la Fase 6 en cada nivel: `inputs {bien: cantidad por unidad}` (del almacén), `output: "warehouse"`,
`product`, `skill`, `jobs`, `prod_per_worker`, `tech`, `pollution`, costos/materiales, modelo 3D, y `required_profession: "ingeniero"` en niveles altos.

| Fábrica | Insumos | Producto (precio base) |
|---|---|---|
| Industria textil | lana / algodón | tela (3) |
| Confección | tela | ropa_fina (7,5) |
| Siderúrgica | hierro + carbón | acero (4,5) |
| Herramientas | acero + madera | herramientas (8) |
| Maquinaria | acero + herramientas | maquinaria (55) |
| Motores | acero + herramientas | motor (70) |
| Electrónica | acero + plata (+ oro) | componentes_electronicos (16) |
| Automotriz | acero, motor, tela, componentes | automovil_bien (800) |
| Aeronáutica | acero, motores, tela, componentes | avion_bien (7000) |
| Orfebrería | oro + plata | joyas (30) |

Nueva tecnología: **Electrónica** (época moderna, rama industria; requiere electricidad y radio).
Las materias primas (`hierro, carbon, lana, algodon, oro, plata, trigo`) las define la Fase 6. Los productos tienen `export: true` para la Fase 7.

## Herencia y dinastía (`scripts/sim/dynasty_sim.gd`, `data/dynasty.json`)
- **Impuesto a la herencia**: campo `inheritance_tax` del gobierno si existe; si no, entre 5% y 30% según su campo `social`.
  Se cobra sobre el patrimonio neto (`EconomySim.net_worth`) que supera la exención; va al tesoro. Lo que no alcanza en
  efectivo queda en cuotas mensuales (con recargo si no se pagan).
- Las deudas y préstamos del jugador pasan al heredero (y se informan en la sucesión).
- **Registro de la dinastía** en *Mi Personaje*: jefes de familia con años al frente, patrimonio e impuesto pagado; estimación del impuesto si murieras hoy.
- **Aviso** cada 2 años cuando el jefe de familia tiene 60+ años y no tiene heredero.

## Pruebas
`godot --headless res://tests/test_fase8.tscn` — esquema de datos de industria/turismo, sin conexiones no hay turistas,
turistas con conexión (entradas, alojamiento, comercio, dinero de afuera), factores (transporte, conexiones, crimen, variedad),
publicidad (costos, efecto, tope, cancelación, expiración, medios propios), dinastía (impuesto, deudas, registro, cuotas, aviso, fin), guardado y balance a 1 año.
