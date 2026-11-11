# CLAUDE.md — Voltaje (simulador de empresa de energía)

Juego independiente de Dinastía (el juego Godot de la raíz del repo). Vive en `energia/` hasta que el usuario cree su repo propio (decidido; pendiente de que lo cree).

## Estado actual
- **Fase 1 completa**: globo 3D, capas de recursos, tiempo con velocidades, guardado/carga, menú principal, CI para Mac.
- **Fase 2 (motor) lista**: núcleo económico, Panamá (permisos, PPA, bancos, impuestos), solar FV y eólica con ciclo completo de proyecto, estados financieros, quiebra, Monte Carlo. Detalle en `docs/MOTOR_FASE2.md`.
- **Fase 3 (motor) lista**: licitaciones y clientes, ofertas por puntaje, contratos con garantías y penalidades, EPC para terceros, cadena de suministro dinámica, 5 competidores IA con los mismos comandos, árbol de I+D. Detalle en `docs/MOTOR_FASE3.md`. Siguiente: UI de la Fase 3.
- **Fase 4 (motor) lista**: 18 tecnologías nuevas (geotermia con pozos secos, hidro pasada/embalse/bombeo, CSP, eólica marina, biomasa, biogás, gas, carbón, petróleo, nuclear, SMR, baterías, H2 verde, líneas, interconexiones, ESCO), 12 países con permisos propios, presencia por país, tipo de cambio y combustibles, catálogo y fichas de país. Detalle en `docs/MOTOR_FASE4.md`. Siguiente: UI de las fases 3 y 4.
- **Fase 5 (motor) lista**: mercado eléctrico horario por país (merit order con días tipo, clima/El Niño, capacidad y servicios), despacho de plantas con reglas configurables, PPA en bloque/financiero, permisos para operar, eventos del mundo (crisis, guerras, pandemias, desastres, elecciones, regulación, avances), seguros, valoración merchant del comprador (balance de la IA otra vez < 6×). Detalle en `docs/MOTOR_FASE5.md`. Siguiente: UI de la Fase 5.
- **Fase 2 (UI) lista**: desarrollar en un sitio, panel y detalle de proyectos (Gantt, estudios, permisos, PPA, financiación, construcción, operación, viabilidad), finanzas de la empresa, registro de eventos, quiebra, sitios 3D en el globo. Detalle en `docs/UI.md`.

## Comandos (desde `energia/`)
| Comando | Qué hace |
|---|---|
| `npm install` | dependencias |
| `npm run dev` | juego en el navegador (http://localhost:5173) |
| `npm test` | pruebas del motor y de los datos (Vitest) |
| `npm run typecheck` | TypeScript estricto |
| `npm run build && npm run screens` | prueba de humo de la UI + capturas en `docs/capturas/` |
| `npm run resources` | regenera la grilla de recursos |
| `npm run mac` | `.dmg` Apple Silicon (solo en macOS; también lo hace GitHub Actions) |

## Arquitectura
```
packages/sim    motor puro TS: sin DOM, sin Math.random/Date.now. Determinista.
  core/         rng (xoshiro128**), calendario, estado, comandos, eventos, step(), guardado + hash, SimContext
  data/         types.ts: forma de los datos que recibe el motor (SimData)
  world/        ResourceGrid; site.ts: recurso real oculto por sitio
  tech/         factor de capacidad (solar PR/temperatura, eólica Weibull + curva, hidro, CSP…), CAPEX con proveedores/aranceles;
                Fase 4: models.ts (modo económico por tecnología, pozos geotérmicos, despacho, arbitraje), siting.ts (restricciones de sitio)
  finance/      VAN, TIR, LCOE, WACC, deuda, modelo anual de proyecto; company.ts: contabilidad, cierre mensual, quiebra
  market/       spot simple (interfaz SpotMarket); macro.ts (Fase 4): tipo de cambio real y combustibles;
                Fase 5: power.ts (mercado horario por país, clima, previsiones), dispatch.ts (despacho de una planta)
  project/      tipos, comandos, avance diario/mensual, requisitos (grafo), sorteos, economía, valoración, viabilidad (Monte Carlo)
  selectors.ts  vistas para la UI (lista/detalle de proyectos, finanzas de la empresa, vista previa de sitio y de financiamiento)
  business/     Fase 3: actores (vistas), I+D, ofertas, oportunidades, contratos/EPC, garantías, avance por actor
  supply/       Fase 3: índices de materiales, curvas de aprendizaje, colas y relación con proveedores
  ai/           Fase 3: competidores IA (decisiones por estrategia; corren el mismo código vía vistas de actor)
  selectorsBusiness.ts  vistas de la Fase 3 (oportunidades, cotización, ofertas, contratos, competidores, I+D, proveedores)
  selectorsWorld.ts     vistas de la Fase 4 (catálogo de tecnologías con LCOE típico por país, ficha de país con permisos como grafo, países, combustibles)
  world/events.ts       Fase 5: eventos del mundo, elecciones, regulación por país, daños y seguros
  selectorsPower.ts     vistas de la Fase 5 (mercado por país, despacho de una planta, ingresos por fuente, eventos del mundo, clima)
packages/data   YAML editables + esquemas Zod (game, layers, countries/*, technologies/*, studies, suppliers, research, clients, competitors, markets, power, events, resources/anclas)
  generated/    grid.bin, grid.json, world.json (salida de tools/build-resources.ts; se sirven como estáticos)
apps/game       Vite + React + Three.js
  worker/       el GameState vive solo en un Web Worker (carga la grilla y calcula las vistas de los selectores); la UI recibe instantáneas + vistas y envía comandos
  globe/        Globe.ts (shader propio: mapa base, capa, máscara de costa, cuadrícula, selección, facetas); sites.ts + siteVisual.ts (adaptador único a models/)
  ui/           paneles React; store.ts = estado de UI (no de juego); project/ = pestañas del detalle de proyecto
  storage/      partidas en IndexedDB + exportar/importar .json
  theme/        theme.ts (colores del globo) y theme.css (UI): el estilo se cambia aquí
  src-tauri/    envoltorio nativo de Mac
tools/          build-resources.ts, screenshots.mjs
```
Reglas:
- Todo cambio de estado pasa por un `Command` (`applyCommand` / `step`). La IA usará los mismos comandos.
- En pausa los comandos se aplican con `applyCommands` sin avanzar el tiempo.
- Un flujo de RNG por subsistema (`world`, `market` (clima, Fase 5), `projects`, `events` (eventos del mundo, Fase 5), `ai`, `supply`, `tenders`, `business`, `fx`, `fuels`, y `ai_<id>` por competidor).
- Actores: el jugador (raíz del estado) y cada competidor (`state.competitors[i]`) tienen empresa, finanzas, proyectos y `business`. La IA usa `actorView` y corre exactamente el mismo código; nunca agregar reglas solo para la IA. La IA solo lee información pública (`publicOpportunity`, `p.estimate`); hay prueba.
- El mundo de la Fase 3 se inicializa perezosamente en el primer `step`/`applyCommands` con datos (`business/world.ts`).
- Precios de equipos: usar `currentCapex(state, ctx, …)` (índices, proveedores, relación, I+D), no `capexBreakdown` directo.
- 1 tick = 1 día. Gastos fijos se cobran al cambiar de mes.
- Cada valor real en YAML lleva `fuente` o `supuesto` (lo exige el esquema `sourced`).
- Partidas: `{format:'voltaje-save', saveVersion, state}`. Si cambia el estado, subir `SAVE_VERSION` y añadir migración en `core/save.ts`.
- `step(state, commands, ctx)` con `ctx: SimContext = { data: gameData.simData, grid? }`. La grilla solo hace falta para `createProject`.
- El recurso real (`Site.realFactor`, `Operation.fcReal`) está en el estado pero ningún selector lo expone; la UI debe usar los selectores.
- Sorteos compartidos entre la simulación y el Monte Carlo en `project/outcomes.ts` (misma probabilidad en ambos).
- Todo movimiento de caja pasa por `postCash(state, categoría, monto, concepto)` (`finance/company.ts`).
- Fase 4: precio/combustible/despacho de cualquier tecnología solo con `productTerms` (`tech/models.ts`); restricciones de sitio solo con `evaluateSite` (`tech/siting.ts`); CAPEX de un proyecto con `projectCapex` (incluye el factor de sitio).
- Fase 4: para operar fuera del país de origen hace falta el nodo de mercado de I+D y presencia (`openPresence`); las oportunidades de un país solo se generan si algún actor está allí (`openCountries`).
- Fase 4: precios en USD = inflación del USD × tipo de cambio real (moneda fija al USD ⇒ inflación local); contratos en moneda local siguen al tipo de cambio desde la firma; la deuda siempre en USD.
- Fase 5: el spot sale solo de `market/power.ts` (`monthPrices`, `spotMonthUsd`, `spotYearUsd`); `spotPrice` (YAML) queda como referencia histórica y para la calibración. La economía usa la previsión de largo plazo (`longRun`); la operación, los precios del mes. El despacho de cualquier planta, solo con `planOnPrices`/`currentPlan`.
- Fase 5: los efectos de los eventos del mundo se leen con `world*Factor` (combustibles, demanda, hidrología, CAPEX, plazos, carbono, crédito fiscal) y valen igual para todos los actores; los daños recorren jugador e IA.
- Fase 5: la foto del parque (`fleetSnapshots`) y las cachés de previsión dependen solo de lo guardado en el estado al inicio del mes (versión del mercado): guardar/cargar a mitad de mes da el mismo resultado.

## Decisiones
| Fecha | Decisión |
|---|---|
| 2026-11-03 | Stack aprobado: TS + Three.js + React + Tauri 2. |
| 2026-11-03 | País inicial: Panamá. Año de inicio 2026. UI en español. |
| 2026-11-03 | Repo propio (pendiente de que el usuario lo cree); mientras tanto en `energia/`. |
| 2026-11-04 | RNG xoshiro128** en lugar de PCG32 (32 bits nativos en JS, sin BigInt). |
| 2026-11-04 | Estado de UI con un store mínimo (`useSyncExternalStore`) en lugar de Zustand: no hacía falta otra dependencia. |
| 2026-11-04 | Grilla 0,5°. Sol/viento/lluvia aproximados con puntos de referencia (sin acceso a NASA POWER desde este entorno). Ver docs/RECURSOS.md. |
| 2026-11-04 | Texturas del globo de 8192 px si la GPU lo permite (costas nítidas al acercarse). |
| 2026-11-04 | Velocidades: ×1 = 1 día/s, ×2 = 3, ×4 = 7, ×8 = 30 (editable en game.yaml). Autoguardado cada 3 meses de juego (mín. 45 s reales), 3 ranuras rotativas. |
| 2026-11-04 | Fase 2: `SimContext` (datos + grilla opcional) como 3.er parámetro de `step`; el motor define `SimData` y `@voltaje/data` lo valida (sin dependencia circular). |
| 2026-11-04 | Recurso real = celda × N(1, σ) determinista por (semilla, capa, sitio a 0,01°); σ solar 7 %, viento 12 %. Los estudios de medición reemplazan la estimación si reducen σ. |
| 2026-11-04 | Etapa del proyecto derivada del avance (estudios y permisos en paralelo según el grafo). |
| 2026-11-04 | Contabilidad consolidada (impuesto a nivel empresa, mensual, con arrastre de pérdidas); estudios y permisos se capitalizan y se castigan si se abandona. |
| 2026-11-04 | Quiebra: 3 meses de caja negativa sin crédito de emergencia (hasta 50 % del valor neto de las plantas). |
| 2026-11-04 | SAVE_VERSION 2 con migración desde v1 (las partidas de la Fase 1 cargan sin proyectos). |
| 2026-11-04 | Fase 3: la IA es un actor completo con vistas de actor (`actorView`) sobre el mismo código; decisiones deterministas por (semilla, competidor, día). |
| 2026-11-04 | Fase 3: ofertantes externos (distribución alrededor del precio de referencia) además de las 5 IA, para que siempre haya competencia. |
| 2026-11-04 | Fase 3: garantías con 50 % de colateral en caja y 1,5 %/año; ejecución = se pierde el valor completo. Reputación 0–100 (jugador 25). |
| 2026-11-04 | Fase 3: SAVE_VERSION 3 con migración desde v2; `stateHash` ignora claves `undefined`. |
| 2026-11-04 | Viabilidad: mismo supuesto de precio que la economía (spot si no hay PPA) y tasa sin prima de etapa (el riesgo se simula); `npvDeterministicUsd` comparable. |
| 2026-11-04 | UI Fase 2: los selectores corren en el worker (tienen datos + grilla) y viajan con cada instantánea; detalle solo del proyecto enfocado; viabilidad y vistas previas bajo pedido. |
| 2026-11-04 | Vista previa de sitio = `previewSite` + `createProject` sobre una copia del estado para obtener TIR/VAN/LCOE con los mismos selectores (sin tocar la partida). |
| 2026-11-04 | Registro de eventos solo en la UI; al cargar se reconstruye con las líneas de tiempo de los proyectos (no se cambia el formato de guardado). |
| 2026-11-04 | Sitios del globo vía `globe/siteVisual.ts` sobre `src/models` (escala 0,008, anillo de avance por etapa, clic por proximidad en pantalla). |
| 2026-11-10 | Fase 4: cada tecnología tiene un modo económico (generación, térmica, almacenamiento, hidrógeno, transmisión, eficiencia) con un «producto» en MWh y un precio; sin mercado horario (factores punta/valle por país). |
| 2026-11-10 | Fase 4: 12 países nuevos (CRI, COL, DOM, CHL, MEX, BRA, KEN, ISL, ESP, IDN, PHL, USA solo Texas/ERCOT); nuclear solo en MEX y USA. |
| 2026-11-10 | Fase 4: expansión = I+D del mercado + presencia (constitución + representante mensual); oficinas completas en la Fase 6 (`Presence.level`). |
| 2026-11-10 | Fase 4: SAVE_VERSION 4 con migración desde v3 (presencia vacía, flujos `fx`/`fuels`). |
| 2026-11-10 | Fase 4: la prueba de balance de la IA pasa a máximo < 12× y mediana < 4× del capital inicial (la venta de proyectos merchant en Panamá es muy rentable y la expansión cambia las trayectorias). |
| 2026-11-11 | Fase 5: precios con días tipo (12 meses × laborable/fin de semana × 24 h), no 8.760 horas; parque existente derivado de la matriz y calibrado (un factor térmico por país) al spot histórico del YAML. |
| 2026-11-11 | Fase 5: economía, bancos y compradores usan la previsión «de largo plazo» (sin el clima ni los eventos del año); el comprador de un proyecto merchant recorta 12 % el precio y pide +3 pp. La prueba de balance de la IA vuelve a < 6×. |
| 2026-11-11 | Fase 5: SAVE_VERSION 5 con migración desde v4 (mercado y eventos se inicializan en el próximo paso). |
| 2026-11-11 | Fase 5: el LCOE de catálogo (`typicalEconomics`) sigue con el mercado de referencia de la Fase 4 (`staticMarket`) para comparar con Lazard/NREL. |

## Pendientes conocidos
- UI: el motor ya expone `resource.monthlyMwh`/`operation.expectedMonthlyMwh` (perfil estacional) y `SimEvent.tick`; falta usarlos en la UI.
- Fase 3: la UI de licitaciones, contratos, competidores, I+D y proveedores está por hacer (selectores en `selectorsBusiness.ts`).
- Fase 3: precios de licitaciones, garantías y pesos aproximados (`supuesto`); la IA empieza sin plantas (su experiencia histórica solo da puntaje).
- Falta una captura de una planta en operación (requiere años de juego); la pestaña Operación solo se probó vacía.
- Permisos, plazos y probabilidades de Panamá son aproximados (marcados `supuesto`); calibrar con desarrolladores locales si se consigue información.
- Reemplazar sol y viento por NASA POWER cuando haya red (script por escribir).
- El `.dmg` solo se ha configurado, no se ha compilado aquí (este entorno es Linux). Revisar el primer run de GitHub Actions.
- Costas a máximo zoom muestran el píxel de la máscara (≈5 km); si molesta, pasar a geometría vectorial.

- Fase 4: datos de los 12 países aproximados (marcados `supuesto`); calibrar spot, permisos y probabilidades con fuentes locales. Profundidad del mar aproximada por distancia a la costa.
- Fase 4: la UI debe usar `selectTechCatalog`, `selectCountrySheet`, `selectCountries`, `previewSite(..., to?)` (líneas) y `ProjectSummary.visualKind`; comandos `openPresence`/`closePresence`.
- Fase 4: sin despacho horario (Fase 5): baterías y bombeo usan factores punta/valle; las térmicas despachan por margen mensual. (Resuelto en la Fase 5 salvo en el catálogo.)
- Fase 5: la UI debe usar `selectPowerMarket`, `selectPowerMarkets`, `selectPlantDispatch`, `selectRevenueBySource`, `selectWorldEvents`, `selectMarketShareHistory`; comandos `setDispatchPolicy`, `buyInsurance`, `cancelInsurance`, `terminatePpa`, `seekPpa.settlement`. Eventos `worldEvent`, `climateOutlook`, `plantDamaged`, `operationBlocked`.
- Fase 5: datos de mercado por país aproximados (`supuesto`); sin interconexiones en el despacho; sin picos de una hora (días representativos).

## Preferencias del usuario
- Respuestas cortas y al punto.
- Nada gratis: toda acción tiene costo, tiempo y riesgo. Probabilidades realistas.
