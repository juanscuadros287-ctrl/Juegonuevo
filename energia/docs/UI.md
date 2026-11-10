# UI de las Fases 2 y 3 — pantallas y flujos

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
Espacio pausa/reanuda · 1–5 velocidades · P proyectos · M mercado · C contratos · I investigación (I+D) · F finanzas · E eventos · R competidores · V proveedores · Esc cierra (diálogo → oferta → desarrollar → ventana → selección) · ⌘/Ctrl+S guardar · +/− zoom. Con un deslizador enfocado los atajos siguen funcionando; en campos de texto solo Esc.

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
