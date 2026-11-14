# UI de las Fases 2, 3, 4 y 5 — pantallas y flujos

Todo en `apps/game/src`. Estilo de juego de gestión: ventanas grandes sobre el globo, tablas, KPI y gráficas (ECharts modular, `ui/Chart.tsx`). Colores y medidas en `theme/theme.css` (sección «Fase 2»); color por etapa en `globe/siteVisual.ts` (`STAGE_COLORS`, compartido con la UI).

## Arquitectura de datos
- El `GameState` vive en el worker (`worker/sim.worker.ts`). Al arrancar, el cliente envía `init` con las URL de `grid.json`/`grid.bin`; el worker carga la `ResourceGrid` y la pone en `ctx.grid`. Los comandos esperan hasta que la grilla está lista.
- Con cada instantánea el worker envía también las **vistas** (`Views`): `selectProjects`, `selectCompanyFinancials` y `selectProjectDetail` del proyecto enfocado (`sim.focus(id)`, lo hace `ui.openProject`). Instantáneas limitadas a una cada 100 ms mientras corre el tiempo.
- Peticiones bajo demanda (request/response): `preview` (vista previa de sitio), `viability` (Monte Carlo, 500 corridas), `finPreview` (efecto de una estructura de deuda con `projectEconomics`).
- La vista previa del sitio usa `previewSite` + una **copia** del estado (`structuredClone`) donde se aplica `createProject` para obtener TIR, VAN, LCOE, desarrollo por venir y probabilidad de éxito con los mismos selectores. La partida no se toca.
- `ui/store.ts`: estado de UI (`window`, `projectId`, `projectTab`, `developAt`, registro de eventos `log`, `unread`, `toasts`). Nada de esto se guarda; el registro se reconstruye al cargar desde las líneas de tiempo de los proyectos.

## Pantallas
| Pantalla | Archivo | Contenido |
|---|---|---|
| Barra superior | `ui/TopBar.tsx` | Proyectos (con nº de alertas), Finanzas, Eventos (no leídos), fecha, velocidades, caja + meses de caja (clic → finanzas), guardar/cargar/menú |
| Ficha de celda | `ui/Inspector.tsx` | botón **Desarrollar proyecto aquí** (solo tierra y país con mercado; si no, motivo), proyectos de la celda, recursos, país |
| Desarrollar | `ui/DevelopDialog.tsx` | tecnología (solar FV / eólica), MW en el rango de `escala_mw`, nombre, recurso P50/P90/σ, FC, energía, terreno, CAPEX, LCOE, TIR/VAN del capital, desarrollo por venir, prob. de llegar a obra; costo de prospección y caja |
| Proyectos | `ui/ProjectsPanel.tsx` | KPI de cartera, filtros por etapa, tabla (etapa, avance del ciclo, próximo paso, FC P50, TIR, VAN, alertas). Clic → detalle y la cámara vuela al sitio |
| Detalle | `ui/project/*` | ver abajo |
| Finanzas | `ui/FinancePanel.tsx` | KPI (caja, patrimonio, deuda, ingresos/EBITDA 12 m, meses de caja, riesgo de quiebra); Resumen (caja y deuda, flujo mensual), P&G y Flujo de caja (12 meses + mes en curso), Balance, Deuda y riesgo |
| Eventos | `ui/EventLog.tsx` | registro filtrable por severidad y proyecto; clic abre el proyecto |
| Notificaciones | `ui/Toasts.tsx` | eventos `bueno`/`malo` y algunos informativos; clic abre el proyecto |
| Quiebra | `ui/GameOver.tsx` | resumen final; cargar partida o volver al menú |

### Detalle de proyecto (`ui/project/ProjectWindow.tsx`)
Cabecera: nombre, etapa, tecnología, MW, coordenadas (clic → vuela al sitio), próximo paso. Acciones: **Comprobar viabilidad**, Vender (confirmación con el valor estimado), Abandonar (muestra lo que se castiga) o Desmantelar si opera. Las confirmaciones son en línea (segundo clic), sin diálogos del navegador.

| Pestaña | Contenido |
|---|---|
| Resumen | KPI (VAN y TIR del capital, LCOE, DSCR, precio supuesto, prob. de éxito, valor de venta); **Gantt** con lo hecho, en curso y previsto (estudios pendientes por grupo, permisos en secuencia parcialmente paralela, cierre financiero, obra y puesta en marcha con duraciones base) y línea de hoy; costos incurridos y por venir; recurso y producción; inversión; historial; riesgos |
| Estudios | hallazgos con mitigación (costo, prob.); estudios por grupo: costo, duración, σ tras el estudio, barra de resultados posibles, estado, bloqueos, Encargar |
| Permisos | grafo por niveles (columnas según `requiere.permisos`), requisitos, costo, plazo, prob. de aprobación, pedidos de información, bloqueos, Solicitar / Volver a solicitar |
| Comercial | contrato actual (precio, plazo, COD límite, multa) y canales PPA con disponibilidad |
| Financiación | prestamistas (elegibilidad y motivo) o solo capital; deslizadores de deuda y socio; vista previa: deuda que daría el banco (avisa si la limita el DSCR), tu aporte, prima del socio, TIR/VAN/DSCR; luego condiciones y deuda vigente |
| Construcción | proveedores de equipos y EPC comparados (precio, calidad, confiabilidad, entrega/plazo, sobrecosto); iniciar obra con bloqueos; avance, hitos, equipos, atrasos y sobrecostos |
| Operación | FC real 12 meses vs P50, producción mensual vs esperada, ingresos/costos/disponibilidad, política de mantenimiento, fallas |

La tarjeta de viabilidad muestra probabilidad de llegar a operación, meses P50/P90, costo por gastar P50/P90, TIR P50/P10, VAN esperado y causas de fracaso; avisa si se calculó en otra fecha.

## Sitios en el globo
- `globe/sites.ts` (`SiteLayer`): un modelo por proyecto (vendidos y desmantelados se quitan), luces de los modelos (`createModelLights`, la direccional sigue a la cámara), LOD por distancia, `animate(dt)` por cuadro y clic por proximidad en pantalla (22 px) → abre el proyecto antes de seleccionar la celda.
- `globe/siteVisual.ts` es el **único** adaptador a `src/models`: `createSiteVisual({kind, capacityMw, stage, progress, seed})`. Etapas: identificado → `prospeccion`; estudios/permisos/cierre → `estudios`; construcción/puesta en marcha → `construccion` (progress = `buildProgress`; 1 en puesta en marcha); operación → `operacion` o `falla` si hay salidas forzadas; abandonado → `abandonado`. Añade un anillo de color por etapa con el avance de obra. Escala 0,008; de lejos (LOD 0) crece hasta ×2,4.
- `Globe.ts` expone `scene`, `camera`, `frameHooks`, `onPickScreen` y `toScreen()`.

## Atajos
Espacio pausa/reanuda · 1–5 velocidades · P proyectos · M mercado · C contratos · I investigación (I+D) · F finanzas · E eventos · R competidores · V proveedores · X países · T tecnologías · L mercado eléctrico · W mundo · Esc cierra (diálogo → oferta → elegir punto final de una línea → desarrollar → ventana → selección) · ⌘/Ctrl+S guardar · +/− zoom. Con un deslizador enfocado los atajos siguen funcionando; en campos de texto solo Esc.

## Fase 3: mercado, contratos, I+D, competidores y proveedores
Todo en `ui/business/`. Las vistas vienen de `selectorsBusiness.ts` y se calculan en el worker:
- `Views.business` (`worker/protocol.ts`): `summary` (`selectBusinessSummary`), `competitors` (`selectCompetitors`, también para el globo) y `biddableCount` van **siempre**; `opportunities`+`myBids` (Mercado), `contracts`+`myBids` (Contratos), `research` (I+D) y `suppliers` (Proveedores) **solo mientras su ventana está abierta** (`sim.panel(id)`, lo hacen `ui.openWindow`/`ui.openPanel`).
- Bajo pedido: `quote` → `selectBidQuote` + proveedores de la tecnología (diálogo de oferta, 120 ms de espera); `finPreview` → `previewFinancing`.
- El worker llama `applyCommands(state, [], ctx)` al crear o cargar una partida: el mundo de la Fase 3 (mercado, IA) existe aunque el juego esté en pausa.

| Pantalla | Archivo | Contenido |
|---|---|---|
| Barra superior | `ui/TopBar.tsx` | Proyectos · Mercado (nº de oportunidades sin oferta tuya) · Contratos (sin proyecto o atrasados) · I+D (aviso si no hay nada en curso) · Finanzas · Eventos · **Más ▾** (Competidores, Proveedores). Bajo 1360 px se ocultan marca y «Caja» y la fecha pasa a corta |
| Mercado | `MarketPanel.tsx` | KPI (abiertas, ofertas vigentes, ganadas/perdidas, reputación, experiencia, caja en garantías); pestañas **Oportunidades** (pública/privada, cliente, contrato y tecnologías, MW, años, COD, cierre y días, referencia y tope u «oculto», estado: puedes ofertar / motivo / tu oferta), **Mis ofertas** (precio, plazo, puntaje, estado y puesto; fila desplegable con el ranking y tu puntaje por criterio) y **Resultados**. Ficha: tu oferta (retirar) o **Armar oferta…**, ranking con precios revelados si está cerrada, condiciones, garantías, multas, requisitos ✓/✕ y pesos de evaluación |
| Armar oferta | `BidDialog.tsx` | tecnología (Fase 4 y sin investigar deshabilitadas), proyecto propio elegible o nuevo, esfuerzo estándar/reforzado, proveedores de equipos y EPC; equilibrio (VAN = 0), sugerido y tu precio; margen (−15 % a +60 %) o precio escrito; avisos de tope/equilibrio; plazo de COD con aviso si es < 80 % del realista; puntaje estimado por criterio y total; preparación, garantía de seriedad, colateral y comisión, garantía de cumplimiento, caja necesaria; bloqueos; confirmación en línea |
| Contratos | `ContractsPanel.tsx` | KPI (activos, sin proyecto, atrasados, garantías, multas, ingresos); tabla (tipo, precio, estado, COD límite y días, avance, garantía); ficha con fechas, obligaciones, EPC (avance, presupuesto, cobrado, sobrecostos, daños, margen), proyecto vinculado y **Asignar proyecto** (misma tecnología, 0,9–1,5× MW, sin PPA ni contrato) |
| I+D | `ResearchPanel.tsx` | árbol por ramas (carriles) y columnas por profundidad; líneas SVG de prerrequisitos (resaltadas para el nodo elegido); nodos con estado, costo, meses, «F4» si llega en la Fase 4 y avance. Panel: presupuesto mensual (0–250 k), ficha (efectos, costo, meses con tu presupuesto, contratiempo, requisitos), Investigar / Poner en cola / Encolar tras requisitos / Cancelar; cola |
| Competidores | `CompetitorsPanel.tsx` | KPI (MW en operación, tu cuota, líder, reputación, activas); tabla (cuota, MW, proyectos visibles, licitaciones G/P, reputación); gráfica de capacidad (operación, desarrollo visible, experiencia); ficha (estrategia aparente, descripción, proyectos visibles → vuela al sitio) |
| Proveedores | `SuppliersPanel.tsx` | KPI (CAPEX solar/eólica hoy, materiales, demanda); **Catálogo** por tipo (equipos, inversores, EPC, logística): precio hoy vs. lista, calidad, confiabilidad, entrega, cola/capacidad, relación; **Precios e índices**: gráficas de equipos/obra por tecnología y de materiales + demanda, tabla de índices |

Otros cambios:
- **Construcción**: tablas opcionales de **inversores** (solo FV) y **logística**; `selectSuppliers` con `inverterId`/`logisticsId` (clic de nuevo = volver a lo incluido en el paquete).
- **Financiación**: la vista previa usa `previewFinancing` (deuda del banco y qué la limita, tasa/plazo/DSCR, asesores y comisión, caja neta propia, probabilidad y due diligence, aviso de monto mínimo, bloqueos).
- **Operación**: producción esperada con el perfil estacional (`operation.expectedMonthlyMwh`, P50 y P90); sin operación, el perfil esperado del año; tabla de fallas (`operation.failureLog`).
- **Viabilidad**: compara `npvExpectedUsd` (con riesgo) con `npvDeterministicUsd` (misma base) y muestra el costo del riesgo y el precio supuesto.
- **Proyectos**: barra de avance con `stageProgress`; el anillo del globo también.
- **Comercial**: enlace al contrato del mercado (`contractId`) o al Mercado.
- **Eventos**: fecha desde `tick` de cada evento; los de negocio enlazan a su ventana; filtro «Mercado, contratos, I+D y competencia». Los `contractSigned` de la IA (ids `C1-K1`) se descartan.
- **Globo**: plantas visibles de los competidores con `siteVisual` y un anillo exterior del color de la empresa (`ui/business/labels.ts`); clic → Competidores. Ante superposición el clic prefiere las propias. Las oportunidades no tienen ubicación en el motor: no hay marcadores de oportunidades.
- **Rendimiento**: con una ventana o diálogo abierto el globo se dibuja a ~4 cuadros/s (`Globe.throttleMs`), salvo en vuelos de cámara o mientras se mueve.

## Prueba de humo
`npm run build && npm run screens` (`tools/screenshots.mjs`, ≈ 2–2,5 min): una sola página (cargar el mundo y armar las texturas en CPU es lo más lento) con `?tex=4096&aa=0` (texturas de 4096 px y sin antialias, solo para la prueba). Entre partes vuelve al menú; las capturas de 1280×800 se toman cambiando el tamaño de la ventana.
- Fase 1 (menú, capas, tiempo) y Fase 2 en 1600×960: nueva partida → celda de Coclé (8,6° N 80,3° O) → solar de 10 MW → estudios satelital y de prefactibilidad → ×8 ≈ 6 meses → clic en el marcador del globo → todas las pestañas → proveedores → viabilidad → proyectos, finanzas, P&G, eventos → lo clave en 1280×800 → guardar, salir al menú, continuar (verifica fecha y proyecto).
- Fase 3 (semilla 59: licitación de ETESA de 31 MW abierta en enero): I+D (presupuesto 100 k, PPA corporativo + EPC en cola) → Mercado → armar oferta (margen 3 %; también en 1280) → presentar y confirmar → ×8 hasta la adjudicación → Mis ofertas con el ranking → Contratos → I+D → Competidores → Proveedores (catálogo y precios) → plantas rivales en el globo → I+D en 1280.
- Falla con errores de consola. `SCREENS_PORT` cambia el puerto de `vite preview` (4173); `SCREENS_ONLY=3` corre solo la Fase 3; `SCREENS_TIMING=1` imprime el tiempo de cada captura. Expone `window.__voltaje` (`flyTo`, `siteScreenPos`, `rivalSites`) solo para esta prueba.

## Fase 4: todas las tecnologías, países y expansión
Vistas de `selectorsWorld.ts` calculadas en el worker (`Views.business`, `worker/protocol.ts`):
- `countries` (`selectCountries`) va **siempre** (barra, globo, ficha de celda).
- Ventana Países (`sim.panel('countries')`): `fuels` (`selectFuelMarkets`) y `countrySheet` (`selectCountrySheet`) del país elegido (`sim.country(iso3)`, lo hacen `ui.openCountry`/`ui.openPanel('countries', iso3)`).
- Ventana Tecnologías (`sim.panel('catalog')`): `catalog` (`selectTechCatalog` de todos los países) con caché en el worker por (semilla, mes, nº de nodos de I+D): el LCOE típico de 20 × 13 se recalcula una vez por mes.
- Vista previa (`preview`) con `to` para líneas. Si el sitio sirve pero falta I+D o presencia, el worker estima igual sobre la copia del estado (ahí marca la I+D y la presencia necesarias) para que se vea si vale la pena abrir el mercado; el botón Crear queda deshabilitado con el motivo.

| Pantalla | Archivo | Contenido |
|---|---|---|
| Desarrollar | `ui/DevelopDialog.tsx` | lista de las 20 tecnologías por modo (renovable, térmica, almacenamiento, H₂, transmisión, ESCO) con disponibilidad **en ese sitio**: ✓, I+D (nodo), País (prohibida, zona, mercado cerrado, sin presencia) o Sitio (motivo de `evaluateSite`); se calcula en la UI con `evaluateSite` + `techUnlocked` + `countryAccessBlockers` sobre la grilla de la UI. Parámetros clave (CAPEX, O&M, FC, vida, obra, emisiones, escala), MW con paso según el rango, avisos con «Ir a I+D» / «Ficha del país». Vista previa por modo: generación (recurso P50/P90/σ, FC, energía, terreno; geotermia: flujo de calor y pozos; mar: costa y profundidad; hidro: lluvia y relieve), térmica (combustible, heat rate, costo variable con CO₂, despacho), almacenamiento (horas/MWh, ida y vuelta, ciclos, degradación, energía descargada, costo de la carga, LCOS), hidrógeno (kWh/kg, t/año, LCOH), transmisión (destino, longitud, pérdidas, US$/MW-km, peaje, energía transportada), ESCO (ahorro, garantizado, precio); economía (CAPEX, US$/kW con factor de sitio, LCOE/LCOS/LCOH, TIR, VAN, desarrollo, prob.) y restricciones |
| Punto final de una línea | `DevelopDialog` + `globe/GlobeView.tsx` | «Elegir punto final en el globo» oculta el diálogo (`ui.pickingRoute`) y muestra un aviso; el siguiente clic en el globo fija `developAt.to` y vuelve al diálogo. La ruta prevista se dibuja en el globo (cinta discontinua + extremo) |
| Tecnologías (T) | `ui/world/CatalogPanel.tsx` | KPI (investigadas, más barata en el país, prohibidas, spot); filtros por modo, país y «solo investigadas»; **Tabla comparativa** ordenable (CAPEX con rango, O&M, FC, vida · obra, gCO₂/kWh, LCOE típico con FC y despacho, TIR; «prohibida» con el motivo); **Gráfica de LCOE** (barras horizontales: en el país, mínimo y máximo entre países); ficha con parámetros, restricciones de sitio, riesgos propios y LCOE/LCOH por país |
| Países (X) | `ui/world/CountriesPanel.tsx` | KPI (presencia, desbloqueados, costo mensual de presencia, proyectos fuera, oportunidades); pestañas **Países** (estado con el color del globo, acceso, spot hoy, moneda y unidades por US$, tipo de cambio real, riesgo, inflación, mis proyectos, oportunidades), **Ficha** y **Combustibles** |
| Ficha de país | `CountriesPanel.tsx` + `PermitGraphView.tsx` | Presencia y acceso (I+D, constitución costo/días, representante/mes, fecha de lista, **Abrir presencia** / **Cerrar presencia** con confirmación en línea y bloqueos); mercado (spot hoy, demanda, pico, punta/valle, perfil mensual, matriz); moneda (hoy vs inicio, índice real, volatilidad, shocks, contratos en US$ o moneda local, gráfica del tipo de cambio); **grafo de permisos** (columnas por requisitos, autoridad, duración, prob. de aprobación con barra aprobado/info/rechazo; con la tecnología elegida se atenúan los que no aplican y se resalta la ruta crítica con la duración base; resumen del motor: nº de permisos, meses esperados con pedidos de información, prob. de aprobar todos, costo); macro e impuestos; incentivos, carbono, combustibles locales, zona y tecnologías prohibidas; bancos y canales PPA. «⌖ Ver en el globo» vuela al país |
| Combustibles | `CountriesPanel.tsx` (pestaña; también en «Más ▾») | gráfica del precio (referencia × índice, o índice) por mes; tabla con referencia, hoy, índice, mín./máx., emisiones y qué tecnologías lo usan |

Otros cambios:
- **Globo**: cada proyecto (propio y de la IA) usa su `visualKind` (`ProjectSummary.visualKind`; para la IA `visualKindOf` de la tecnología). Líneas e interconexiones: subestación en el origen (con el anillo de etapa) y el trazado con `createTransmissionLine` en modo radial a lo largo del gran círculo (`globe/routes.ts`; torres según el avance de obra; cinta discontinua clara antes de la obra). Contornos de color de los países con datos (`globe/countries.ts`): verde = origen o presencia, ámbar = en trámite, celeste = desbloqueado, gris = cerrado. **Doble clic** sobre un país con datos abre su ficha.
- **Ficha de celda**: «Desarrollar» también en el mar cerca de un país con datos (eólica marina) y botón «Ficha de {país}» con su estado.
- **Detalle de proyecto**: para térmicas, almacenamiento, H₂, líneas y ESCO la sección «Recurso y producción» pasa a mostrar el producto, combustible/carga, despacho, carbono, emisiones, LCOH, duración o destino; el KPI de LCOE se rotula LCOS/LCOH según el modo.
- **Eventos**: `presenceRequested/Opened/Closed` y `currencyShock` enlazan a la ficha del país; `fuelPriceChange` a Combustibles; `wellsDrilled` y `savingsShortfall` al proyecto. Filtro «Países, monedas y combustibles» en el registro.
- **Finanzas**: las categorías `combustible`, `carbono` y `presencia` salen solas en P&G y flujo (vienen de `CATEGORIES`).
- **Navegación**: «Más ▾» = Países y expansión (X), Tecnologías (T), Combustibles, Competidores (R), Proveedores (V).
- Utilidades: `ui/tech.ts` (íconos, modos, etiquetas de producto, combustibles, paso de MW).

### Prueba de humo (Fase 4)
`SCREENS_ONLY=4` corre solo esta parte (≈ 1 min). Atajo de prueba como en las pruebas del motor: se lee la partida (`__voltaje.saveText`), se agregan nodos de I+D (baterías, geotermia, líneas, mercados regional/Costa Rica/Colombia…) y caja, y se carga (`__voltaje.loadText`). Luego: ×8 unos meses → Países → ficha de Costa Rica con el grafo de permisos (hidro de pasada) → abrir presencia → Tecnologías (tabla y gráfica de LCOE en Chile) → Combustibles → desarrollar baterías (Panamá) y geotermia (Barú) con vista previa → línea Coclé → ciudad de Panamá con el punto final elegido en el globo → más proyectos por comando (`__voltaje.command`) → globo con los modelos, la línea y los países resaltados. Capturas `40`–`53`. Ganchos nuevos solo para la prueba: `saveText`, `loadText`, `command`, `select`, `geoScreenPos`.

## Fase 5: mercado eléctrico, despacho, seguros y mundo
Vistas de `selectorsPower.ts` calculadas en el worker (`Views.power` y `Views.dispatch`, `worker/protocol.ts`):
- **Siempre** (livianas): `worldActive` (eventos activos: barra, avisos y globo), `climate` (ENSO e hidrología del país de origen), `revenue` (`selectRevenueBySource`) y `oppMarks` (oportunidades abiertas con `opportunityLocation`, caché por id).
- Ventana Mercado eléctrico (`sim.panel('power')`): `markets` (`selectPowerMarkets`) y `market` (`selectPowerMarket` del país elegido con `sim.powerCountry(iso)`, por defecto el de origen). Ventana Mundo (`'world'`): `world` (`selectWorldEvents`). Competidores: `shareHistory` (`selectMarketShareHistory`).
- `dispatch` (`selectPlantDispatch`) solo del proyecto enfocado, en obra u operación, y solo en las pestañas Operación, Despacho y venta, y Seguro (`sim.focus(id, tab)`; `ui.setProjectTab`).
- Bajo pedido: `dispatchPreview` = `selectPlantDispatch` sobre una copia superficial del estado con la política nueva (el plan del mes se recalcula; la partida no se toca).

| Pantalla | Archivo | Contenido |
|---|---|---|
| Mercado eléctrico (L, «Más ▾») | `ui/power/PowerMarketPanel.tsx` | país elegible y «⌖» al globo; KPI (spot medio vs histórico, punta/valle, mín./máx. con piso/techo, valor del agua, clima e hidrología, cambio a 12 meses); **Mes en curso**: curva de oferta (merit order) en bloques coloreados por tecnología con la demanda de punta/valle y el precio medio, y precios por hora del día tipo (laborable/fin de semana, demanda y vertimiento); **Previsión e historial**: 12 meses con banda P10–P90, punta y valle, e historial (rango horario e hidrología); **Parque, capacidad y servicios**: MW por tecnología (existente vs empresas del juego), mercado de capacidad, servicios complementarios (requerimiento vs ofrecido) y clima; **Comparar países**: barras y tabla |
| Despacho y venta (pestaña, solo en operación) | `ui/project/DispatchTab.tsx` | KPI (venta PPA/merchant, spot medio, precio capturado o de descarga con % del spot, costo de carga, despacho y vertimiento, ingresos 12 meses); **reglas** según `policyOptions` (cargar bajo / descargar sobre / reserva mínima, precio mínimo, prioridad PPA/spot, servicios y fracción, compra máxima de H₂), cada una con «automático»; vista previa del mes (antes → después) y línea discontinua en la gráfica; **perfil horario** del mes (generación/descarga, carga bajo cero, precio); **ingresos por fuente** 24 meses (PPA, spot, capacidad, servicios, compras) y tabla de 12 meses; **PPA o merchant**: con PPA, modalidad, volumen, años y **Terminar PPA** con la penalidad (confirmación en línea); sin PPA, valor de venta con descuento merchant y **Buscar PPA** con modalidad (según producción / bloque físico / financiero, explicadas con los parámetros de `power.yaml`) |
| Seguro (pestaña, en obra u operación) | `ui/project/InsuranceTab.tsx` | KPI (estado/carencia, valor asegurado, pérdida esperada, prima, indemnizaciones); cotizaciones daños y daños + lucro cesante (prima anual y %, primera prima, deducible, carencia, días de lucro), **Contratar** / cambiar cobertura (reinicia la carencia) con confirmación; riesgos naturales del país; póliza vigente con siniestros y **Cancelar seguro**; aviso si hay un desastre activo en el país |
| Mundo (W, «Más ▾» y chip «Mundo» de la barra) | `ui/power/WorldPanel.tsx` | KPI (activos, graves, ENSO, próxima elección, regulación modificada, avances); **Eventos** activos y pasados filtrables por país: tipo, nombre, alcance, fechas y días restantes, texto, efectos, daños, «te afecta», «⌖ globo»; **Gobiernos y regulación** (gobierno, próxima elección, carbono, plazo de permisos, crédito fiscal, ficha del país); **Avances y costos** |
| Avisos | `ui/power/Banners.tsx` | evento grave (`worldEvent` de tipo desastre, conflicto, salud, crisis petrolera o cambiaria): aviso rojo bajo la barra (14 s o ✕); clic → Mundo |

Otros cambios:
- **Barra**: chip «Mundo» con el color de ENSO y el nº de eventos activos (rojo si hay graves); bajo 1720 px fecha corta y sin nombre de empresa. «Más ▾» = Mercado eléctrico (L), Mundo (W), Países (X), Tecnologías (T), Combustibles, Competidores (R), Proveedores (V).
- **Globo** (`globe/worldMarks.ts`): rombos de las oportunidades abiertas (celeste; ámbar con ✓ si ya ofertaste) → clic abre Mercado con la oportunidad; eventos por país: contorno pulsante y halo del color del tipo + ícono → clic abre Mundo. Un marcador a ≤ 9 px gana el clic; si no, los sitios y la celda.
- **Comercial**: selector de modalidad del PPA. **Mercado**: «⌖ globo» en la ficha de la oportunidad.
- **Competidores**: cuota de mercado histórica apilada y `stageId` (fichas y globo).
- **Contratos**: país del contrato y **Asignar proyecto** con `ContractView.eligibleProjects` (ya no replica el filtro).
- **Finanzas**: ingresos por fuente (12 meses y mensual) en el Resumen; las categorías nuevas salen solas en P&G y flujo.
- **Eventos**: `worldEvent`, `worldEventEnded` y `climateOutlook` enlazan a Mundo; `plantDamaged`, `insuranceChanged`, `dispatchPolicyChanged`, `ppaTerminated`, `operationBlocked` al proyecto (badge rojo en «Despacho y venta» si `codBlocked`). Filtro «Mundo, países, monedas y combustibles».

### Prueba de humo (Fase 5)
`SCREENS_ONLY=5` (≈ 1 min). Semilla 7; atajo de prueba en el JSON (I+D de baterías y Chile, presencia en Chile, caja) y luego `__voltaje.autopilot(maxDías, díasExtra)`: piloto automático en el worker (`worker/devPilot.ts`, solo para la prueba; los mismos comandos que la UI, como `operatingPlant` de las pruebas del motor) que lleva una solar de 20 MW en Coclé y una batería de 40 MW cerca de Santiago a operación (≈ 4 años) y ~14 meses más. Luego: oportunidad en el globo (clic → Mercado) → Mercado eléctrico (4 pestañas, Chile) → batería: Operación con datos, Despacho, política editada con vista previa y aplicada → solar: Despacho → Seguro (contratar daños + lucro) → `__voltaje.worldEvent('huracan', ['PAN'])` y sequía en Chile → avisos y globo → Mundo → Gobiernos → Competidores (cuota) → Finanzas (ingresos por fuente). Capturas `60`–`76`. Ganchos nuevos solo para la prueba: `autopilot`, `worldEvent`, `oppMarks`, `oppScreenPos`, `eventScreenPos`.
