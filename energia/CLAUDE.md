# CLAUDE.md — Voltaje (simulador de empresa de energía)

Proyecto independiente de Dinastía (el juego Godot en la raíz del repo). No mezclar código.

## Estado actual
- **Fase 0**: plan de arquitectura escrito en `PLAN.md`. Esperando aprobación del usuario (stack, país inicial, ubicación del repo). No hay código todavía.

## Arquitectura (resumen; detalle en PLAN.md)
- `packages/sim`: motor puro en TypeScript. Sin DOM, sin `Math.random`/`Date.now`. Determinista (PCG32 con semilla, un flujo de RNG por subsistema). Corre en Web Worker.
- `packages/data`: YAML editables validados con Zod. Cada valor numérico real lleva `fuente:` o `supuesto:`.
- `apps/game`: Three.js (globo y modelos low‑poly procedurales) + React (UI). Solo lee snapshots y envía comandos.
- Todo cambio de estado ocurre por comandos; la IA usa los mismos comandos.
- 1 tick = 1 día; mercado con días representativos (12 × 24 h).
- Empaquetado Mac con Tauri 2; el `.dmg` se construye en GitHub Actions (`macos-14`).

## Reglas de trabajo
- Cada fase termina jugable, con pruebas en verde (Vitest) y este archivo actualizado.
- Nada gratis: toda acción tiene costo, tiempo y riesgo.
- Probabilidades coherentes con la realidad, mejoradas por equipo, estudios previos y reputación.
- El usuario quiere respuestas cortas y al punto.

## Decisiones
| Fecha | Decisión |
|---|---|
| 2026-11-03 | Stack propuesto: TS + Three.js + React + Tauri (pendiente de aprobación). |
| 2026-11-03 | Ubicación provisional: carpeta `energia/` en este repo. |
| 2026-11-03 | Año de inicio 2026; UI en español. |
