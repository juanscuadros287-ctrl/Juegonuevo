# CLAUDE.md — Voltaje (simulador de empresa de energía)

Juego independiente de Dinastía (el juego Godot de la raíz del repo). Vive en `energia/` hasta que el usuario cree su repo propio (decidido; pendiente de que lo cree).

## Estado actual
- **Fase 1 completa**: globo 3D, capas de recursos, tiempo con velocidades, guardado/carga, menú principal, CI para Mac.
- **Fase 2 (motor) lista**: núcleo económico, Panamá (permisos, PPA, bancos, impuestos), solar FV y eólica con ciclo completo de proyecto, estados financieros, quiebra, Monte Carlo. Detalle en `docs/MOTOR_FASE2.md`.
- Siguiente: UI de la Fase 2 (paneles de proyecto y empresa, modelos 3D por avance) usando los selectores del motor.

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
  tech/         factor de capacidad (solar PR/temperatura, eólica Weibull + curva), CAPEX con proveedores/aranceles
  finance/      VAN, TIR, LCOE, WACC, deuda, modelo anual de proyecto; company.ts: contabilidad, cierre mensual, quiebra
  market/       spot simple (interfaz SpotMarket para la Fase 5)
  project/      tipos, comandos, avance diario/mensual, requisitos (grafo), sorteos, economía, valoración, viabilidad (Monte Carlo)
  selectors.ts  vistas para la UI (lista/detalle de proyectos, finanzas de la empresa, vista previa de sitio)
packages/data   YAML editables + esquemas Zod (game, layers, countries/*, technologies/*, studies, suppliers, resources/anclas)
  generated/    grid.bin, grid.json, world.json (salida de tools/build-resources.ts; se sirven como estáticos)
apps/game       Vite + React + Three.js
  worker/       el GameState vive solo en un Web Worker; la UI recibe instantáneas y envía comandos
  globe/        Globe.ts (shader propio: mapa base, capa, máscara de costa, cuadrícula, selección, facetas)
  ui/           paneles React; store.ts = estado de UI (no de juego)
  storage/      partidas en IndexedDB + exportar/importar .json
  theme/        theme.ts (colores del globo) y theme.css (UI): el estilo se cambia aquí
  src-tauri/    envoltorio nativo de Mac
tools/          build-resources.ts, screenshots.mjs
```
Reglas:
- Todo cambio de estado pasa por un `Command` (`applyCommand` / `step`). La IA usará los mismos comandos.
- En pausa los comandos se aplican con `applyCommands` sin avanzar el tiempo.
- Un flujo de RNG por subsistema (`world`, `market`, `projects`, `events`, `ai`).
- 1 tick = 1 día. Gastos fijos se cobran al cambiar de mes.
- Cada valor real en YAML lleva `fuente` o `supuesto` (lo exige el esquema `sourced`).
- Partidas: `{format:'voltaje-save', saveVersion, state}`. Si cambia el estado, subir `SAVE_VERSION` y añadir migración en `core/save.ts`.
- `step(state, commands, ctx)` con `ctx: SimContext = { data: gameData.simData, grid? }`. La grilla solo hace falta para `createProject`.
- El recurso real (`Site.realFactor`, `Operation.fcReal`) está en el estado pero ningún selector lo expone; la UI debe usar los selectores.
- Sorteos compartidos entre la simulación y el Monte Carlo en `project/outcomes.ts` (misma probabilidad en ambos).
- Todo movimiento de caja pasa por `postCash(state, categoría, monto, concepto)` (`finance/company.ts`).

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

## Pendientes conocidos
- El worker del juego aún no carga la grilla: hasta que la UI la pase en el `SimContext`, `createProject` se rechaza en el juego.
- Permisos, plazos y probabilidades de Panamá son aproximados (marcados `supuesto`); calibrar con desarrolladores locales si se consigue información.
- Reemplazar sol y viento por NASA POWER cuando haya red (script por escribir).
- El `.dmg` solo se ha configurado, no se ha compilado aquí (este entorno es Linux). Revisar el primer run de GitHub Actions.
- Costas a máximo zoom muestran el píxel de la máscara (≈5 km); si molesta, pasar a geometría vectorial.

## Preferencias del usuario
- Respuestas cortas y al punto.
- Nada gratis: toda acción tiene costo, tiempo y riesgo. Probabilidades realistas.
