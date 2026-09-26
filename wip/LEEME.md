# Trabajo en curso guardado (sin integrar)

Los agentes se detuvieron por el límite semanal de uso. Su avance quedó guardado aquí como parches sobre el commit base indicado en cada parche (ver `git merge-base`), para retomarlo después. Todavía NO está aplicado al juego.

| Parche | Contenido |
|---|---|
| fase9b_mapa.patch | País más grande, municipios grandes, niebla translúcida y Fase 9B (regiones, mercado de tierras, pueblos en el mapa) |
| graficos.patch | Iluminación, cielo, sombras, modelos, carreteras, agua y vegetación |

Retomar: `git apply wip/<parche>.patch` en una rama nueva desde `f32063a` (o merge y resolver), terminar lo pendiente y correr todas las pruebas.
