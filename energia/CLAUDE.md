# CLAUDE.md — Voltaje (simulador de empresa de energía)

Juego independiente de Dinastía (el juego Godot de la raíz del repo). Vive en `energia/` hasta que el usuario cree su repo propio (decidido; pendiente de que lo cree).

## Estado actual
- **Fase 1 completa**: globo 3D, capas de recursos, tiempo con velocidades, guardado/carga, menú principal, CI para Mac.
- Siguiente: **Fase 2** (núcleo económico + Panamá + solar y eólica con ciclo completo de proyecto).

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
  core/         rng (xoshiro128**), calendario, estado, comandos, step(), guardado + hash
  world/        ResourceGrid: decodifica la grilla de recursos
packages/data   YAML editables + esquemas Zod (game, layers, countries/*, resources/anclas)
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

## Pendientes conocidos
- Reemplazar sol y viento por NASA POWER cuando haya red (script por escribir).
- El `.dmg` solo se ha configurado, no se ha compilado aquí (este entorno es Linux). Revisar el primer run de GitHub Actions.
- Costas a máximo zoom muestran el píxel de la máscara (≈5 km); si molesta, pasar a geometría vectorial.

## Preferencias del usuario
- Respuestas cortas y al punto.
- Nada gratis: toda acción tiene costo, tiempo y riesgo. Probabilidades realistas.
