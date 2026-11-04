# UI de la Fase 2 — pantallas y flujos

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
Espacio pausa/reanuda · 1–5 velocidades · P proyectos · F finanzas · E eventos · Esc cierra (diálogo → desarrollar → ventana → selección) · ⌘/Ctrl+S guardar · +/− zoom.

## Prueba de humo
`npm run build && npm run screens` (`tools/screenshots.mjs`): Fase 1 (menú, capas, tiempo) y Fase 2 en 1600×960: nueva partida → celda de Coclé (8,6° N 80,3° O) → solar de 10 MW → estudios satelital y de prefactibilidad → ×8 ≈ 6 meses → clic en el marcador del globo → todas las pestañas → proveedores → viabilidad → proyectos, finanzas, P&G, eventos → guardar, recargar, continuar (verifica fecha y proyecto). Repite lo clave en 1280×800. Falla con errores de consola. Expone `window.__voltaje` (`flyTo`, `siteScreenPos`) solo para esta prueba.
