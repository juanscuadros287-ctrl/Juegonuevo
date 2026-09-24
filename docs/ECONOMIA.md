# Economía real — catálogo de bienes, progresión industrial, comercios, energía y precios

## Resumen para el jugador
- **Catálogo de bienes** (pantalla *Catálogo*): 56 bienes con su modelo 3D girando, categoría (materia prima,
  intermedio, producto, energía, servicio), época y tecnología de aparición, precio de mercado, precio de importación
  y lo que pagan otros pueblos, existencias en tus almacenes y la **cadena completa**: de qué se hace, qué fábrica y
  qué nivel lo produce (con la receta), qué productos lo usan, en qué comercios se vende y cuánto lo piden los vecinos.
  Capturas: `docs/capturas/catalogo.png` (pantalla) y `docs/capturas/bienes_3d.png` (vitrina de todos los modelos).
- **Progresión**: en la colonia lo básico (pan, carne y embutidos, cuero y calzado, tela y ropa, muebles, herramientas y
  utensilios, velas y jabón, loza, vidrio, remedios, papel); en la revolución industrial acero, maquinaria, motores,
  conservas, periódicos, química, relojes, petróleo y combustible, y las primeras centrales de carbón; en la época
  moderna plásticos, electrónica, electrodomésticos, medicamentos, autos, aviones y energías renovables y nuclear.
- **Comercios especializados** venden al pueblo desde tus almacenes: carnicería, panadería, maderería, carbonería y
  leñería, ferretería, tienda de ropa y calzado, joyería, mueblería, botica/farmacia, concesionario, gasolinera y tienda
  de electrodomésticos (además de la Tienda general). El precio se ajusta en la pestaña **Precio** de cada comercio.
- **Los vecinos compran según sus deseos**: pan cada pocos días, carne cada semana, velas y jabón, carbón para cocinar,
  ropa nueva cada ~5 meses, calzado, utensilios, herramientas (si trabajan), madera para reparar la casa, muebles,
  medicinas (sobre todo si están enfermos: los remedios y medicamentos curan), periódico (industrial), joyas y relojes
  (ricos), electrodomésticos y autos (moderna, ricos) y gasolina (quien tiene auto). Si nadie vende algo, queda como
  **demanda insatisfecha** (oportunidad de negocio, `ShopSim.advice`).
- **Petróleo, gas, cobre y uranio**: no se ven al empezar. Al investigar *Petróleo* (industrial tardía), *Electricidad*
  o *Energía nuclear* aparecen sus yacimientos en la región (algunas regiones los tienen seguro — el menú de fundación
  lo indica como "subsuelo" — y las demás con cierta probabilidad según el tipo de mapa). Pozos petroleros y de gas,
  refinería (combustible), planta de plásticos, minas de cobre y uranio.
- **Electricidad**: desde *Dínamo y centrales eléctricas* (industrial) existe la red. Las fábricas y comercios de la
  época moderna consumen electricidad; **sin ella rinden la mitad** en la parte no cubierta. Centrales de carbón
  (industrial), gas (moderna), hidroeléctrica (solo mapas con río), eólica (mejor en costa y montaña), solar (peor en
  invierno) y nuclear (opcional, exige ingenieros). Con una ruta comercial terminada se puede comprar a la red regional
  (el dinero sale del pueblo). Desde *Electricidad* los hogares compran luz; el sobrante de tus centrales se les vende.
- **Precios reales**: materia prima < intermedio < producto, márgenes de 10–40 % por etapa bien gestionada, precios de
  otros pueblos ≈ 1,1–1,2 × el mercado local, y fluctuación mensual de materias primas y petróleo que crece con la
  dificultad.

## Archivos
| Archivo | Contenido |
|---|---|
| `data/goods_economia.json` | bienes nuevos (ganado, arcilla, cera, hierbas, petróleo, gas, cobre, uranio, cuero, vidrio, papel, químicos, plásticos, combustible, electricidad, pan, carne, embutidos, conservas, calzado, muebles, utensilios, velas y jabón, loza, remedios, medicamentos, periódicos, relojes, electrodomésticos) e índice `comercio` |
| `data/goods*.json` | a todos los bienes existentes se les agregó `category`, `era`, `tech`, `description`, `model` y `volatility` (y precios recalibrados: acero 6, ropa fina 14, maquinaria 70, motor 90) |
| `data/businesses_economia.json` | 45 negocios: materias primas, talleres, fábricas, pozos, centrales y comercios, cada uno con 3–4 niveles, modelos 3D y recetas |
| `data/businesses_industria.json` | industria de la Fase 8 armonizada: insumos y productividad recalibrados, electricidad en niveles modernos y 3–4 niveles por fábrica |
| `data/technologies_economia.json` | 18 tecnologías nuevas (ver abajo) |
| `data/shops.json` | comercio → bienes que vende (`sells`), `customers_mult`, límites del margen |
| `data/citizens.json` → `wants` | deseos de los vecinos por época y riqueza |
| `data/resources_energia.json` | yacimientos que se revelan con la tecnología (`requires_tech`), regiones que los tienen seguro, probabilidades por mapa y parámetros de la electricidad (`energy`) |
| `data/economy.json` → `fluctuation` | reversión y límites de la fluctuación mensual |
| `data/trade.json` | precios de otros pueblos recalibrados y bienes nuevos exportables; la ciudad, el puerto, el real de minas y la villa de artesanos venden/demandan algunos bienes nuevos |
| `scripts/sim/shop_sim.gd` | `ShopSim`: comercios, deseos semanales, precios, tope por personal, reporte y consejos |
| `scripts/sim/energy_sim.gd` | `EnergySim`: oferta/demanda eléctrica diaria, apagones, red regional, hogares, resumen |
| `scripts/ui/goods_catalog.gd` | `GoodsCatalog`: pantalla del catálogo (SubViewport 3D, filtros por categoría/época, fichas con enlaces) |
| `tests/test_economia_real.gd` | diagnóstico de márgenes de todas las recetas, cadenas completas, niveles, tecnologías y precios |
| `tests/test_tiendas_energia.gd` | comercios, deseos, medicinas, autos y gasolina, electricidad, petróleo, mapas, fluctuación, guardado y catálogo |
| `tests/screenshot_catalogo.gd` | capturas `catalogo.png` y `bienes_3d.png` |

Cambios mínimos en archivos compartidos:
- `market_sim.gd`: `begin_day` llama a `EnergySim.daily` (tras producir y antes de cerrar el día); `discretionary` llama a `ShopSim.weekly`.
- `economy_sim.gd`: `market_price` × `fluct`; `update_fluctuations`; el cierre mensual llama a `ShopSim.monthly` y `EnergySim.monthly`.
- `region_sim.gd`: `resource_def/label/color` leen también `resources_energia.json`; `strengths_text` avisa del subsuelo;
  `tech_deposit_types` y `reveal_tech_deposits` (yacimientos nuevos deterministas por semilla, lejos de edificios).

## Progresión (tecnologías de aparición por nivel)
| Negocio | Produce | Niveles (tecnología) |
|---|---|---|
| Estancia ganadera | ganado | — → rotación de cultivos → maquinaria agrícola → refrigeración |
| Barrero / Colmenar / Huerto de hierbas | arcilla / cera / hierbas | colonial → … → industrial |
| Obrador de pan | pan (harina) | — → ladrillo → máquina de vapor → electricidad |
| Matadero / Charcutería / Conservera | carne (ganado) / embutidos / conservas | — → saneamiento → refrigeración → automatización |
| Curtiembre / Zapatería | cuero / calzado | — → producción en serie → petroquímica → automatización |
| Carpintería / Calderería / Velería / Alfarería / Vidriería | muebles / utensilios / velas y jabón / loza / vidrio | colonial → fábricas → electricidad |
| Laboratorio de boticario / Laboratorio farmacéutico | remedios / medicamentos | herbolaria → saneamiento → vacunas · farmacéutica → medicina moderna → automatización |
| Molino de papel / Imprenta y editorial | papel / periódicos | imprenta → fábricas → electricidad · periódico → telégrafo → electricidad → televisión |
| Planta química / Relojería | químicos / relojes | química → petroquímica → automatización · relojería → producción en serie → electrónica |
| Pozo petrolero / Pozo de gas / Refinería / Planta de plásticos | petróleo / gas / combustible / plásticos | petróleo → electricidad/petroquímica → automatización |
| Mina de cobre / uranio / Electrodomésticos | cobre / uranio / electrodomésticos | electricidad / energía nuclear / electrodomésticos → … → automatización |
| Industria (Fase 8) | tela, ropa fina, acero, herramientas, maquinaria, motor, componentes, auto, avión, joyas | 3–4 niveles, el último con electricidad o automatización |

Cada nivel sube costo (×1,8–2,3), días de obra (×1,6–1,7), empleos y producción por trabajador, y su modelo es más
ancho (se escala y se le agrega un anexo). Tecnologías nuevas: vidriería (colonial); conservas, química industrial,
relojería, producción en serie, dínamo y centrales eléctricas, petróleo (industrial); petroquímica, electrodomésticos,
energía hidroeléctrica, eólica, solar y nuclear, industria farmacéutica, minería moderna, redes eléctricas, grandes
superficies comerciales y automatización industrial (moderna). Todas con prerrequisitos existentes.

## Comercios (`ShopSim`)
- Un comercio es un negocio con `"shop": true` y producto `comercio` (bien interno, precio base 1). El jugador fija el
  precio en la pestaña Precio: **margen = precio de la tienda / precio de mercado de `comercio` − 1** (el precio
  automático = mercado × (1 + margen)). Se reusa para la Tienda y la Panadería originales con su producto `comida`.
- Precio de venta de cada bien = mercado del bien × (1 + margen). Por encima del mercado compran menos (misma demanda
  elástica que `MarketSim.purchase`, ayudada por la publicidad); por encima de ×1,6 (`willing_markup`) no compran.
- Tope: clientes por semana = producción esperada (empleados × `prod_per_worker` = clientes/día) × 7 × `customers_mult`
  × cobertura eléctrica. Las existencias salen de **cualquiera de tus almacenes** (como la Tienda de la Fase 6) o del
  inventario propio del comercio. Los bienes de más de $20 se venden por unidades enteras.
- Deseos (`citizens.json → wants`): cada semana cada adulto (no preso, no el jugador) prueba cada deseo activo en su
  época/tecnología: si `every_days` < 7 compra `qty × 7/every_days`; si no, con probabilidad 7/`every_days` (o siempre si
  está enfermo y el deseo es `when_sick`). Solo si le quedan `min_wealth_days` días de necesidades básicas después de
  pagar; los deseos frecuentes además se limitan a la mitad de lo que le sobra sobre 6 días de necesidades. Con ahorros
  ≥ `rich_days` elige el bien más caro de la lista (ropa fina, embutidos, medicamentos). Felicidad por compra (tope 6
  por semana). `owns`/`requires_owned`: quien compra un auto queda como dueño y compra gasolina cada semana.
- Economía cerrada: el dinero va del vecino al comercio (tus ventas); nada se importa por esta vía.
- Estado: `gs.economy["shops"] = {month, last_month, owners}`; `ShopSim.wants_report(gs)` y `ShopSim.advice(gs)`.

## Energía (`EnergySim`, llamado cada día desde `MarketSim.begin_day`)
1. Revela yacimientos de tecnología (`RegionSim.reveal_tech_deposits`).
2. Sin *Dínamo* no hay red: factor 1 para todos.
3. Oferta = electricidad producida hoy por tus centrales (`power_plant`, producto `electricidad`, **no almacenable**:
   queda en su inventario y `BusinessSim.end_day` la borra). Las centrales térmicas toman carbón/gas/uranio de su
   almacén vinculado como cualquier receta.
4. Demanda = `power` × empleados de cada nivel que lo declara; los niveles de la época moderna sin `power` piden
   `default_power_modern` (1 por trabajador). Se reparte a prorrata; la central factura y la fábrica paga como insumo
   (neto cero para ti). Lo que falta se compra a la red regional (`import_price` × dificultad) si hay una ruta comercial
   terminada y se investigó *Electricidad*.
5. Apagón: la parte no cubierta rinde `unpowered_output` (50 %): se descuenta de lo producido hoy (de su almacén
   vinculado o de su patio) y los insumos no usados vuelven. `chain_status` = "sin electricidad suficiente".
6. Hogares (desde *Electricidad*): cada adulto con casa compra 0,45 u./día (incluye a sus hijos) del sobrante de tus
   centrales (ingreso de la central) o de la red regional; sin luz pierde un poco de felicidad.
7. Estado: `gs.economy["energy"]` (cobertura por edificio, acumulados del mes); `EnergySim.summary(gs)` para la UI.

**Combustible**: el bien se llama `combustible` (gasolina y diésel). Lo refina la Refinería y lo compran los dueños de
autos en la Gasolinera. La flota de camiones de la logística (otro módulo) cobra hoy su combustible en dinero con
`trade.json → fuel_price`; si se quiere que consuma el bien, debe usar el id `combustible`.

## Precios reales y calibración
Escala: un jornal ≈ $2/día (1700), las necesidades básicas ≈ $1/día. Un empleado de taller genera ≈ $4–8 de valor
agregado por día. Precios base (× dificultad × inflación × escasez × fluctuación):

| Categoría | Ejemplos |
|---|---|
| Materias primas | trigo 0,35 · arcilla 0,3 · lana 0,9 · carbón 1 · hierro 1,6 · cera 1,5 · petróleo 2,5 · cobre 2,5 · madera 3 · piedra 4 · plata 6 · ganado 7 · oro 14 · uranio 60 |
| Intermedios | harina 1,25 · papel 1,8 · vidrio 2,6 · cuero 2,8 · tela 3,2 · químicos 3,5 · plásticos 4,5 · acero 6 · componentes 16 · motor 90 |
| Productos | periódico 0,2 · pan 0,9 · velas y jabón 1,6 · carne 2,2 · loza 2,2 · remedios 2,2 · conservas 2,4 · utensilios 3,2 · embutidos 4 · herramientas 5,5 · ropa 8 · medicamentos 8 · calzado 9 · ropa fina 14 · muebles 16 · joyas 30 · relojes 40 · electrodomésticos 65 · maquinaria 70 · automóvil 800 · avión 7000 |
| Energía | leña 0,15 · electricidad 0,4 · combustible 4,2 |

**Calibración automática** (generador de datos): la productividad de cada nivel con receta se fija para un margen por
trabajador de 17 % (nivel 1), 24 % (2), 30 % (3) y 35 % (4), respetando que suba de un nivel al siguiente; si el valor
agregado por unidad no alcanza, el nivel mejora la eficiencia de insumos. Los salarios base van de 1,9 a 3,2 y los
títulos universitarios cuestan ×1,4 (y rinden ×1,3 si son de su rama).

Márgenes por trabajador y día (extracto de `tests/test_economia_real.gd`, precios base):

| Negocio (nivel) | Ingreso | Insumos | Salario+mant.+luz | Margen | Recupera la obra |
|---|---|---|---|---|---|
| Obrador de pan (1) | 6,30 | 3,06 | 2,17 | 17 % | 140 d |
| Matadero (2) | 17,71 | 11,27 | 2,19 | 24 % | 58 d |
| Zapatería (1) | 4,74 | 1,77 | 2,17 | 17 % | 186 d |
| Carpintería (3) | 8,94 | 4,05 | 2,21 | 30 % | 163 d |
| Siderúrgica (4, eléctrica) | 22,68 | 10,34 | 4,40 | 35 % | 163 d |
| Fábrica de maquinaria (2) | 15,02 | 7,61 | 3,80 | 24 % | 208 d |
| Refinería (1) | 25,58 | 18,27 | 2,96 | 17 % | 138 d |
| Laboratorio farmacéutico (2) | 10,80 | 2,73 | 5,48 | 24 % | 686 d |
| Industria automotriz (2) | 13,73 | 4,72 | 5,71 | 24 % | 506 d |
| Aeronáutica (3) | 16,17 | 4,45 | 6,87 | 30 % | 736 d |
| Herrería (3) — Fase 6 | 19,25 | 9,10 | 2,23 | 41 % | 51 d |

Todas las recetas quedan entre 17 % y 43 % (la prueba exige 5–50 % y avisa fuera de 10–40 %). Las extracciones rinden
más por trabajador (40–78 %, igual que las minas y campos de la Fase 6) porque dependen de yacimientos, tierra y
estaciones y venden barato; las centrales entre 14 % y 75 % (las renovables no pagan combustible pero cuestan mucho
construirlas y solo venden lo que se demanda). Una **cadena completa** integrada (de la materia prima al producto)
acumula los márgenes de cada etapa: 25–61 % con los niveles básicos y 42–81 % con los mejores.

**Fluctuación**: cada mes los bienes con `volatility` (materias primas 3–4 %, petróleo 7 %, gas 6 %, productos 1–2 %)
hacen un paseo aleatorio con reversión a 1 (25 %/mes), desvío × `event_freq_mult` de la dificultad (0,6 fácil … 2
extremo), limitado a 0,7–1,4. RNG propio por semilla, mes y bien (no altera el resto de la simulación).

**Otros pueblos** (`trade.json`): base ≈ 1,1–1,2 × el precio local (antes carbón, hierro, oro, plata, herramientas y
joyas se pagaban 3–4 × su valor). Los pueblos siguen pagando más por lo que demandan (×1,25–1,6) y menos si les
saturas el mercado.

## Enganchar el catálogo al HUD (archivo compartido, no editado aquí)
En `hud.gd`:
```gdscript
var goods_catalog: GoodsCatalog
# en _ready(), junto a research_screen:
goods_catalog = GoodsCatalog.new()
root.add_child(goods_catalog)
goods_catalog.setup()
# en _build_side_menu():
box.add_child(UIKit.button("Catálogo de bienes", func(): goods_catalog.open(), 160))
# en _unhandled_input(), rama KEY_ESCAPE (antes que las demás):
if goods_catalog.visible:
	goods_catalog.close()
```
`open("acero")` abre con un bien seleccionado (útil desde fichas de negocios o del almacén). El catálogo también cierra
solo con Esc. Opcional: agregar `ShopSim.advice(gs)` a las recomendaciones de `StatsSim.advice`.

## Pruebas
- `godot --headless res://tests/test_economia_real.tscn` — tabla de márgenes por receta, extracción/centrales, cadenas
  completas, niveles 3–4 crecientes, tecnologías, precios de otros pueblos, salarios y orden de precios.
- `godot --headless res://tests/test_tiendas_energia.tscn` — comercios, economía cerrada, precio y tope por personal,
  deseos insatisfechos y consejos, medicinas, autos y gasolina, apagones, centrales, red regional, hogares, petróleo
  revelado por tecnología, reglas de mapa, fluctuación por dificultad, guardado y catálogo.
