# CLAUDE.md — Voltaje (simulador de empresa de energía)

Juego independiente de Dinastía (el juego Godot de la raíz del repo). Vive en `energia/` hasta que el usuario cree su repo propio (decidido; pendiente de que lo cree).

## Estado actual
- **Fase 1 completa**: globo 3D, capas de recursos, tiempo con velocidades, guardado/carga, menú principal, CI para Mac.
- **Fase 2 (motor) lista**: núcleo económico, Panamá (permisos, PPA, bancos, impuestos), solar FV y eólica con ciclo completo de proyecto, estados financieros, quiebra, Monte Carlo. Detalle en `docs/MOTOR_FASE2.md`.
- **Fase 3 (motor) lista**: licitaciones y clientes, ofertas por puntaje, contratos con garantías y penalidades, EPC para terceros, cadena de suministro dinámica, 5 competidores IA con los mismos comandos, árbol de I+D. Detalle en `docs/MOTOR_FASE3.md`.
- **Fase 4 (motor) lista**: 18 tecnologías nuevas (geotermia con pozos secos, hidro pasada/embalse/bombeo, CSP, eólica marina, biomasa, biogás, gas, carbón, petróleo, nuclear, SMR, baterías, H2 verde, líneas, interconexiones, ESCO), 12 países con permisos propios, presencia por país, tipo de cambio y combustibles, catálogo y fichas de país. Detalle en `docs/MOTOR_FASE4.md`.
- **Fase 4 (UI) lista**: desarrollar cualquiera de las 20 tecnologías (disponibilidad por I+D/país/sitio, vista previa por modo económico, punto final de líneas en el globo con la ruta dibujada), `visualKind` en el globo (propias y de la IA), trazados de líneas, países resaltados por presencia/desbloqueo, ventana Tecnologías (catálogo y LCOE por país), ventana Países (lista, ficha con moneda, mercado, grafo de permisos con ruta crítica, abrir/cerrar presencia, combustibles), eventos y finanzas nuevas. Detalle en `docs/UI.md`. Siguiente: Fase 5.
- **Fase 3 (UI) lista**: Mercado (oportunidades, armar oferta con cotización y puntaje, mis ofertas y resultados con ranking), Contratos (obligaciones, asignar proyecto), I+D (árbol con prerrequisitos, presupuesto, cola), Competidores (tabla, fichas, gráfica, plantas en el globo), Proveedores (catálogo, índices), inversores/logística en Construcción, `previewFinancing`, perfil estacional, `stageProgress`. Detalle en `docs/UI.md`.
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
  market/       spot simple (interfaz SpotMarket para la Fase 5); macro.ts (Fase 4): tipo de cambio real por país y combustibles
  project/      tipos, comandos, avance diario/mensual, requisitos (grafo), sorteos, economía, valoración, viabilidad (Monte Carlo)
  selectors.ts  vistas para la UI (lista/detalle de proyectos, finanzas de la empresa, vista previa de sitio y de financiamiento)
  business/     Fase 3: actores (vistas), I+D, ofertas, oportunidades, contratos/EPC, garantías, avance por actor
  supply/       Fase 3: índices de materiales, curvas de aprendizaje, colas y relación con proveedores
  ai/           Fase 3: competidores IA (decisiones por estrategia; corren el mismo código vía vistas de actor)
  selectorsBusiness.ts  vistas de la Fase 3 (oportunidades, cotización, ofertas, contratos, competidores, I+D, proveedores)
  selectorsWorld.ts     vistas de la Fase 4 (catálogo de tecnologías con LCOE típico por país, ficha de país con permisos como grafo, países, combustibles)
packages/data   YAML editables + esquemas Zod (game, layers, countries/*, technologies/*, studies, suppliers, research, clients, competitors, markets, resources/anclas)
  generated/    grid.bin, grid.json, world.json (salida de tools/build-resources.ts; se sirven como estáticos)
apps/game       Vite + React + Three.js
  worker/       el GameState vive solo en un Web Worker (carga la grilla y calcula las vistas de los selectores); la UI recibe instantáneas + vistas y envía comandos
  globe/        Globe.ts (shader propio: mapa base, capa, máscara de costa, cuadrícula, selección, facetas); sites.ts + siteVisual.ts (adaptador único a models/)
  ui/           paneles React; store.ts = estado de UI (no de juego); project/ = pestañas del detalle de proyecto; business/ = mercado, oferta, contratos, I+D, competidores, proveedores;
                world/ = Fase 4: países (ficha, grafo de permisos, combustibles) y catálogo de tecnologías; tech.ts = íconos/modos
  globe/        (Fase 4) routes.ts = trazados de líneas (createTransmissionLine radial); countries.ts = contornos por presencia/desbloqueo
  storage/      partidas en IndexedDB + exportar/importar .json
  theme/        theme.ts (colores del globo) y theme.css (UI): el estilo se cambia aquí
  src-tauri/    envoltorio nativo de Mac
tools/          build-resources.ts, screenshots.mjs
```
Reglas:
- Todo cambio de estado pasa por un `Command` (`applyCommand` / `step`). La IA usará los mismos comandos.
- En pausa los comandos se aplican con `applyCommands` sin avanzar el tiempo.
- Un flujo de RNG por subsistema (`world`, `market`, `projects`, `events`, `ai`, `supply`, `tenders`, `business`, `fx`, `fuels`, y `ai_<id>` por competidor).
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
| 2026-11-10 | UI Fase 3: vistas de negocio pesadas solo con su ventana abierta (`sim.panel`); resumen y competidores siempre. Cotización y vista previa de financiamiento bajo pedido. |
| 2026-11-10 | UI Fase 3: Mercado/Contratos/I+D en la barra y Competidores/Proveedores en «Más ▾»; atajos M, C, I, R, V. |
| 2026-11-10 | Globo: plantas visibles de la IA con `siteVisual` + anillo exterior del color de la empresa; el clic prefiere las propias. Con ventana abierta el globo se dibuja a ~4 cuadros/s. |
| 2026-11-10 | Prueba de humo en una sola página con `?tex=4096&aa=0` (≈ 2–2,5 min en CPU); semilla 59 para la licitación de la Fase 3. |
| 2026-11-11 | UI Fase 4: Países (X) y Tecnologías (T) en «Más ▾» junto con Combustibles; catálogo calculado en el worker solo con la ventana abierta y con caché mensual; ficha de país solo del país elegido. |
| 2026-11-11 | UI Fase 4: la disponibilidad de cada tecnología en el sitio se calcula en la UI con `evaluateSite` sobre la grilla de la UI (sin ida y vuelta al worker); la vista previa estima aunque falte I+D o presencia (copia del estado con esos accesos) para decidir si conviene abrir el mercado. |
| 2026-11-11 | UI Fase 4: líneas = subestación en el origen + trazado de gran círculo con torres según el avance; punto final con un segundo clic (`ui.pickingRoute`). Doble clic en un país con datos → su ficha. |
| 2026-11-11 | Prueba de humo Fase 4 con atajo de prueba (I+D y caja editados en el JSON de la partida vía `__voltaje.saveText/loadText`), como en las pruebas del motor; total ≈ 3 min. |

## Pendientes conocidos
- Motor: cuando la IA gana una licitación, `signContract` publica `contractSigned` (ids `C1-K1`) en los eventos del jugador; la UI los descarta por el prefijo. Debería ir al `sink` de la IA.
- Motor (para la UI): ubicación de las oportunidades (marcadores en el globo), historial de cuota de mercado, país en `ContractView`, proyectos elegibles por contrato (hoy la UI replica el filtro de `assignContractProject`).
- La prueba de humo pierde la licitación (empresa nueva: reputación y experiencia bajas); la ventana Contratos solo se capturó vacía.
- Fase 3: precios de licitaciones, garantías y pesos aproximados (`supuesto`); la IA empieza sin plantas (su experiencia histórica solo da puntaje).
- Falta una captura de una planta en operación (requiere años de juego); la pestaña Operación solo se probó vacía.
- Permisos, plazos y probabilidades de Panamá son aproximados (marcados `supuesto`); calibrar con desarrolladores locales si se consigue información.
- Reemplazar sol y viento por NASA POWER cuando haya red (script por escribir).
- El `.dmg` solo se ha configurado, no se ha compilado aquí (este entorno es Linux). Revisar el primer run de GitHub Actions.
- Costas a máximo zoom muestran el píxel de la máscara (≈5 km); si molesta, pasar a geometría vectorial.

- Fase 4: datos de los 12 países aproximados (marcados `supuesto`); calibrar spot, permisos y probabilidades con fuentes locales. Profundidad del mar aproximada por distancia a la costa.
- Motor (para la UI, Fase 4): `visualKind` y país en `CompetitorView.visibleProjects` (hoy la UI usa `visualKindOf`); `excluye` de los permisos en `PermitGraphNode` (la UI solo filtra por tecnologías y MW); ruta crítica como lista de ids en `permitPaths` (la UI la recalcula con la duración base); extremo de las líneas en `ProjectSummary` (hoy se lee de `site.extras.to` del estado).
- UI Fase 4: los modelos del globo en la prueba de humo están en prospección (sin años de juego no hay obras ni plantas en operación propias); las etapas avanzadas se ven en `models.html`.
- Fase 4: el LCOE típico del gas en Chile (~540 US$/MWh con despacho bajo) parece alto; revisar el despacho del catálogo con GNL caro.
- Fase 4: sin despacho horario (Fase 5): baterías y bombeo usan factores punta/valle; las térmicas despachan por margen mensual.

## Preferencias del usuario
- Respuestas cortas y al punto.
- Nada gratis: toda acción tiene costo, tiempo y riesgo. Probabilidades realistas.
