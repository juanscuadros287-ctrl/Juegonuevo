# Terrenos, costo por fábrica, transporte en finanzas, precios e inmobiliaria

Pedido de Sebastián:
1. *"Que pueda manejar mis terrenos, ya que sabemos que se valorizan o bajan: venderlos, o que los empresarios me
   puedan hacer ofertas por ellos."*
2. *"Cómo funcionan los precios: tenemos que saber un aproximado de cada fábrica, porque hay que pagar transporte,
   sueldos y eso."*
3. *"Si se arma algo de transporte, tiene que ser una empresa totalmente aparte o un ministerio de transporte dentro
   de la misma empresa, para que entre en las finanzas."*
4. *"Saber si hay una tabla para ver cómo fluctúan los valores."*
5. Sección H de `docs/PENDIENTES.md`: la inmobiliaria como compañía especializada.

Capturas: `docs/capturas/terrenos_costos/` (`mis_terrenos.png`, `costos_fabrica.png`, `calculadora.png`,
`transporte_empresa.png`, `finanzas_transporte.png`, `precios.png`, `inmobiliaria.png`). Para regenerarlas:

```
xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 \
    tests/screenshot_terrenos.tscn -- docs/capturas/terrenos_costos
```

---

## Para el jugador

### Cómo se forman los precios
- Cada bien tiene un **precio base** (materia prima barata, intermedio medio, producto caro) que se multiplica por:
  la **dificultad**, el **nivel de precios** (inflación acumulada = IPC), la **escasez o exceso** de ese bien en el
  pueblo (sube si falta, baja si sobra), la **fluctuación mensual** (las materias primas y el petróleo se mueven
  más), el **clima** (sequías, heladas), la **guerra** y el **tipo de cambio** del país.
- La pestaña **Estadísticas → Precios** muestra todos los bienes con su precio de hoy, cuánto cambió en 1 mes,
  12 meses y 5 años, el mínimo y el máximo, una mini tendencia y **la causa** (escasez, clima, guerra, ciclo del
  mercado, inflación, tipo de cambio, ciclo económico). Haz clic en un bien para verlo en la gráfica junto al IPC,
  el salario promedio y el valor del suelo (todo en base 100 para comparar). El historial se guarda en la partida.

### Cómo leer el costo de una fábrica
- Abre el negocio → pestaña **Costos**. Arriba está el **costo por unidad** del mes pasado y de qué se compone
  (dona y tabla):
  - **Insumos**: lo que consume la receta, a lo que te cuesta producirlo si lo haces tú (si no, a precio de mercado),
    más los materiales por unidad.
  - **Sueldos** de sus empleados.
  - **Mantenimiento y energía** (incluye la luz).
  - **Transporte**: los fletes que te cobra tu empresa de transporte o la parte de tu división interna que le toca.
  - **Depreciación**: lo que costó la obra repartido en 20 años.
  - **Impuestos** pagados ese mes.
- **Precio de venta promedio** y **margen por unidad**: si el margen es rojo, cada unidad te cuesta más de lo que
  vale. **Punto de equilibrio**: cuántas unidades al mes necesitas para cubrir los costos fijos (sueldos,
  mantenimiento, depreciación); con plantilla incompleta o sin vender, el costo por unidad sube.
- Antes de construir: **Construir → Calculadora de costos** en cada negocio productor. Estima el costo por unidad a
  plantilla completa con los candidatos que hay hoy (su productividad y el sueldo que piden), el precio de mercado y
  el margen esperado. Tras tres meses de operación el costo real suele quedar dentro de ±20 % de lo estimado.

### Mis terrenos
- **Empresas → Mis terrenos**: cada territorio (400 m) donde tienes parcelas, con municipio, precio de compra, valor
  de hoy, **plusvalía o minusvalía** ($ y %), uso (vacío, con edificio, con yacimiento, arrendado) e **impuesto
  predial** mensual (0,6 % anual del valor, más con regulación alta o impuesto local; va al tesoro del municipio).
- Gráfica del valor de cada terreno y del índice de su municipio.
- **Vender al Estado** (precio fijo: 90 % del valor; el tesoro debe tener fondos), **poner en venta** con el precio
  que pidas (sugerido: valor + 5 %; un ciudadano o empresario lo compra si le parece justo) o **arrendar** (renta
  mensual de un ciudadano o empresa NPC).
- **Ofertas**: los empresarios NPC (para expandirse) y los ciudadanos ricos (para construir) te ofrecen comprar tus
  terrenos, más seguido en los municipios que se valorizan. Llega un aviso y la oferta queda en la bandeja con
  **Aceptar**, **Rechazar** o **Contraofertar** (si tu precio cabe en lo que pueden pagar, cierran; si no, te dicen
  su última oferta o se retiran).
- **Con edificios tuyos el terreno no se vende suelto**: solo con **Vender todo** (terreno + negocios), y los negocios
  pasan a ser la empresa del comprador. Viviendas, oficinas, bancos y almacenes con mercancía o vehículos no se
  venden así. El terreno del pueblo (la plaza) no se vende.
- **Recomprar** lo que vendiste exige **negociar con su dueño**: unos piden alto, otros bajo (necesitan el dinero) y
  otros no quieren vender; el apego sube con los años.

### Transporte: división interna o empresa aparte
- En cada edificio de transporte (central, caballeriza, depósito de camiones, cochera, astillero, hangar, empresa de
  buses, estación, puerto, aeropuerto) → pestaña **Organización**:
  - **División interna** (por defecto): no factura; sus costos se reparten cada mes entre los negocios que usaron
    sus envíos según las unidades·km y aparecen como *transporte* en el costeo de cada fábrica.
  - **Empresa aparte**: razón social y forma legal propias; cobra un flete por cada envío a tus negocios (tarifa de
    mercado o la que fijes) y, si le sobra capacidad, a empresas NPC. Tiene sus propios ingresos y ganancias.
- **Finanzas → Transporte y consolidado del grupo**: cada transportadora como línea propia (ingresos, fletes
  internos, costos, resultado) y el **consolidado** del grupo, que elimina los fletes entre tus empresas para no
  contarlos dos veces.

### Inmobiliaria (sección H)
- Para hacer apartamentos, edificios o rascacielos necesitas una **Inmobiliaria** (Construir → Negocios).
- Su pestaña **Inmobiliaria**: proyectos (casas y multifamiliares) con presupuesto, precio de venta y renta por
  unidad, margen y rentabilidad; **comprar terreno a nombre de la compañía** (queda en su libro y ella paga el
  predial); y **recomprar apartamentos** vendidos negociando con su dueño (si acepta, su familia se queda como
  inquilina).
- Los apartamentos se siguen vendiendo **1 a 1 según la demanda** y cada unidad vendida es del comprador
  (`RealEstateSim`, ver `docs/BIENES_RAICES.md`).

---

## Para desarrolladores

### Archivos
| Archivo | Contenido |
|---|---|
| `scripts/sim/terrenos_costos_sim.gd` | `TerrenosCostosSim`: único gancho (init, diario al final del día, mensual tras `EconomySim.monthly`) |
| `scripts/sim/land_portfolio_sim.gd` | `LandPortfolioSim`: cartera, valor, predial, ventas, ofertas, arriendo, vender todo |
| `scripts/sim/cost_sim.gd` | `CostSim`: costeo mensual por negocio y calculadora (`estimate`, `estimate_text`) |
| `scripts/sim/transport_div_sim.gd` | `TransportDivSim`: unidades·km por envío, reparto interno, fletes, clientes NPC, finanzas y consolidado |
| `scripts/sim/price_history_sim.gd` | `PriceHistorySim`: historial mensual con compresión anual, variaciones, mín/máx y causas |
| `scripts/sim/negotiation_sim.gd` | `NegotiationSim`: personalidad del dueño (se niega / alto / normal / bajo), apego y necesidad |
| `scripts/sim/agency_sim.gd` | `AgencySim`: inmobiliaria, terrenos a nombre de la empresa, opciones de proyectos, recompra de unidades |
| `scripts/ui/lands_window.gd` | `LandsWindow` (Mis terrenos) |
| `scripts/ui/costs_tab.gd`, `transport_org_tab.gd`, `agency_tab.gd`, `prices_tab.gd` | pestañas Costos, Organización (+ sección de Finanzas), Inmobiliaria y Precios |
| `data/terrenos_costos.json` | parámetros (predial, ofertas, arriendo, depreciación, tarifas de flete, historial, negociación, inmobiliaria) |
| `data/businesses_inmobiliaria.json` | negocio `inmobiliaria` (3 niveles) |
| `tests/test_terrenos_costos.gd` | pruebas; `tests/screenshot_terrenos.gd` capturas |

### Estado (todo con valores por defecto; las partidas viejas se completan al cargar)
- `GameState.map.land_pf` = `{lots {"cx,cy": {basis, parcels, since, hist [[día, valor, índice]], listing, lease,
  company}}, offers [...], next_id, predial_last, predial_total, sales [...]}`. Los terrenos se reconstruyen desde
  `unlocked_zones` (`sync`): parcelas sin compra registrada toman el valor del día.
- `GameState.economy.transport` = `{month {tkm {estación: {negocio: u·km}}, billed}, last {…, npc}, alloc {negocio:
  {amount, by {estación: monto}}}, total_billed}`; `economy.price_hist` = `{m: [...], y: [...]}`;
  `economy.costing_goods` = costo por unidad propio de cada bien (para valorar insumos).
- Por edificio: `costing`, `cost_hist`, `cost_*_m` (acumuladores), `units_today`, `transport_org`, `company_name`,
  `freight_rate`, `fletes_internos_*`, `fletes_npc_last`, `agency_id` (proyectos); por unidad vendida `sold_day`.
- Parcelas vendidas a un ciudadano: `map.parcels["cx,cy"] = {owner: "npc", name, citizen_id, since}`.

### Reglas y conservación del dinero
- Toda venta la paga un ciudadano (sus ahorros y luego, si es empresario, la caja de su empresa hasta el 35 %), o
  el tesoro (venta al Estado). El predial sale del jugador (o de la empresa dueña) al tesoro del municipio.
- Fletes de una empresa de transporte a tus negocios: solo asientos (`ventas` de la transportadora, `fletes` del
  negocio); no mueven dinero, no causan IVA y el consolidado los elimina. Los fletes a empresas NPC sí son dinero
  (de su caja a la tuya, con IVA como cualquier venta). La renta de impuestos se calcula por edificio (la
  transportadora con ganancia paga renta aunque la fábrica tenga pérdida: son razones sociales distintas).
- El reparto interno es solo informativo (costeo); el costo real ya salió del libro de la estación.
- Un envío entre almacenes (sin negocio beneficiario) reparte su costo entre los productores según el valor que
  producen. Las estaciones que no son de transporte (una fábrica con sus propios camiones) ya tienen ese costo en
  su libro.

### Cambios mínimos en archivos compartidos
- `game_state.gd`: 3 líneas (`TerrenosCostosSim.init_state/daily/monthly`).
- `business_sim.gd`: `LEDGER_KEYS` incluye `fletes`; `b["units_today"] = out` en la producción sin cadena.
- `land_sim.gd`: registra el precio de compra en la cartera y `negotiation()` para dueños ciudadanos (la oferta a un
  particular genérico sigue igual). `map_sim.gd`: `on_zone_bought` avisa a la cartera.
- `realestate_sim.gd`: los proyectos exigen inmobiliaria (`AgencySim.block_reason`), guardan `agency_id` y
  `sold_day`. `tests/test_bienes_raices.gd` y `tests/ui_smoke.gd` crean una inmobiliaria antes de los proyectos.
- UI: `hud.gd` (entrada «Mis terrenos» y ventana), `building_panel.gd` (3 pestañas), `stats_panel.gd` (pestaña
  Precios), `finance_panel.gd` (1 línea), `build_menu.gd` (calculadora), `data_table.gd` (formato `spark` y celdas
  «—»).

### Pruebas
`godot --headless tests/test_terrenos_costos.tscn`: valor que sube y baja con plusvalía correcta, predial al
municipio, venta al Estado, oferta rechazada, contraoferta, aceptada, venta con precio pedido, arriendo, vender todo,
negociación determinista con apego, costeo (total = desglose), calculadora ±20 % tras 3 meses, transporte interno
repartido, empresa que factura sin duplicar en el consolidado, clientes NPC, historial de precios con tope,
inmobiliaria (requisito, terreno a nombre de la empresa, proyecto, recompra negociada), dinero conservado,
guardar/cargar y partida vieja.
