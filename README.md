# Dinastía

Simulación económica y construcción de pueblo desde 1700 (Godot 4, GDScript, 3D low‑poly).
Eres el único empresario del pueblo: todo el crecimiento depende de tus decisiones.

> El nombre del juego se cambia en `data/game.json` y `project.godot`.

## Estado: Fase 1 de 7

| Fase | Contenido | Estado |
|---|---|---|
| 1 | Mapa 3D, cámara, tiempo y ciudadanos | ✅ |
| 2 | Construcción y negocios | ⏳ |
| 3 | Economía, precios y banca | ⏳ |
| 4 | Árbol de investigación y épocas | ⏳ |
| 5 | Gobierno, impuestos, servicios públicos y proyectos | ⏳ |
| 6 | Transporte y otros pueblos | ⏳ |
| 7 | Turismo, publicidad, industria avanzada y herederos | ⏳ |

### Fase 1 incluye
- **Inicio**: dificultad (Fácil/Normal/Difícil/Extremo) y tipo de mapa (Interior, Costa, Montaña, Río), semilla.
- **Mapa 3D low‑poly** procedural 400×400 dividido en 5×5 zonas (las bloqueadas se ven oscuras), agua, bosques, rocas, pueblo inicial con chozas, plaza, pozo y caminos.
- **Cámara**: mover (WASD/flechas o clic derecho), rotar (Q/E o botón central), zoom (rueda, +/-, pellizco en trackpad). De cerca se ven calles y personas; de lejos todo el mapa.
- **Tiempo**: fecha y reloj, pausa + x1 (1 s = 1 h), x2 (1 s = 1 día), x3 (1 s = 1 semana), x4 (salto de 2/5/10 años con reporte). Día/noche.
- **Estaciones y clima**: afectan ingresos agrícolas, salud, felicidad y demanda de energía; lluvia/nieve visibles.
- **Ciudadanos**: nombre, edad, salud, habilidades, experiencia, educación, dinero, deudas, familia, felicidad, trabajo y vivienda. Envejecen, enferman, mueren, se casan, tienen hijos (la población solo crece por nacimientos) y emigran si son infelices. Gastan según prioridad (comida → agua → vivienda → energía → ocio) con billetera familiar.
- **Tu personaje** envejece y puede morir (herencia en Fase 7).
- **Interfaz**: barra superior, notificaciones, panel de ciudadano/vivienda (clic sobre personas o casas), lista de población, registro de notificaciones.
- **Guardado/carga** (JSON en `user://saves/`) + autoguardado anual.

## Controles
| Acción | Tecla |
|---|---|
| Pausa / velocidades | Espacio, 1, 2, 3 · 4 = salto de años |
| Menú (guardar/cargar) | Esc |
| Seleccionar persona o casa | Clic izquierdo |

## Ejecutar
1. Instala **Godot 4.3+** (versión estándar, no .NET).
2. Abre `project.godot` y presiona F5.

## Exportar a macOS (Apple Silicon)
1. Godot → *Editor → Manage Export Templates* → descargar.
2. *Project → Export…* → preset **macOS** (universal, firma ad‑hoc) → *Export Project* → `build/Dinastia.zip`.
3. Primera apertura en Mac: clic derecho → *Abrir* (app sin notarizar).

## Estructura (contenido modular)
```
data/            Configuración JSON (dificultades, mapas, clima, ciudadanos, nombres, edificios…)
scripts/autoload EventBus, GameData, GameState, TimeManager, SaveManager
scripts/sim      Simulación pura (Citizen, PopulationSim, WeatherSim) – sin gráficos
scripts/world    Terreno, cámara, agentes 3D, clima visual
scripts/ui       HUD y menú principal
tests/           Pruebas headless y diagnóstico de balance
```
Para agregar contenido basta con editar los JSON de `data/` (en próximas fases: `businesses.json`, `technologies.json`, `laws.json`).

## Pruebas
```
godot --headless res://tests/test_runner.tscn   # pruebas de simulación, guardado, mapas y salto x4
godot --headless res://tests/balance.tscn       # diagnóstico demográfico a 40 años
```
