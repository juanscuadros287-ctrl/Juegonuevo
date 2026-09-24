# Dinastía

Simulación económica y construcción de pueblo desde 1700 (Godot 4, GDScript, 3D low‑poly).
Eres el único empresario del pueblo: todo el crecimiento depende de tus decisiones.

> El nombre del juego se cambia en `data/game.json` y `project.godot`.

## Estado: Fase 3 de 7

| Fase | Contenido | Estado |
|---|---|---|
| 1 | Mapa 3D, cámara, tiempo y ciudadanos | ✅ |
| 2 | Construcción, negocios, tu personaje y vivienda | ✅ |
| 3 | Economía, precios y banca | ✅ |
| 4 | Árbol de investigación y épocas | ⏳ |
| 5 | Gobierno, impuestos, servicios públicos y proyectos | ⏳ |
| 6 | Transporte y otros pueblos | ⏳ |
| 7 | Turismo, publicidad, industria avanzada y herederos | ⏳ |

### Fase 3 incluye
- **Oferta y demanda** por bien: el precio de mercado sube con escasez (tus negocios sin inventario) y baja con exceso de oferta. Precio automático con margen configurable.
- **Inflación** según dinero en circulación, crédito y producción: afecta costos, salarios pedidos, construcción y subsistencia (si no subes sueldos, tus empleados renuncian).
- **Clasificación** de cada negocio: rentable / equilibrio / deficitaria. **Quiebra** tras 6 meses de pérdidas con saldo negativo (se puede reabrir).
- **Banco externo**: préstamos al jugador (tasa según riesgo, límite según patrimonio), cuotas mensuales, mora, **embargo** tras 3 cuotas impagas o 3 meses en negativo.
- **Tu banco** (Casa de préstamos → Banco → Banco nacional): prestas a ciudadanos (consumo, vivienda, construir) con la tasa que elijas; intereses, morosidad, incobrables.
- **Panel de Finanzas**: dinero, patrimonio, deudas, cartera, ingresos/gastos, intereses, inversión y ROI por empresa, indicadores del pueblo y **gráficas históricas**.

### Fase 2 incluye
- **Construcción** (botón *Construir*): viviendas, oficina y negocios. Cuestan dinero + materiales (madera/piedra: de tus negocios o importados), días de obra y trabajadores (jornaleros desempleados o tu constructora). Andamios visibles. *R* rota, *Shift* mantiene el modo.
- **Negocios** (granja, aguatero, leñador, aserradero, cantera, pescadería, panadería, tienda, taberna, constructora) con niveles, tipo legal (S.A.S. o fundación sin lucro), precio, inventario y finanzas mensuales. Sin oficina: máx. 2 negocios.
- **Contratación manual**: candidatos con habilidad, experiencia, educación y salario pedido; contratar, despedir, subir/bajar sueldo (renuncian si pagas poco).
- **Economía que circula**: los ciudadanos compran a tus negocios (calidad/precio); si no hay oferta se autoabastecen o importan más caro.
- **Mejoras con obra**: subir de nivel cuesta y tarda; **durante la obra el negocio no factura**. Niveles superiores requieren investigación (Fase 4).
- **Viviendas**: todos empiezan en **chozas de bahareque (barro y paja)**; cada nivel siguiente (adobe y teja → ladrillo → apartamentos → edificio → rascacielos) requiere investigación. Calidad **Normal / Media / Alta** cambia costo, renta, venta y acabados, siempre con el estilo de la época del nivel (paja/teja, corral, corredor…). Rentar, vender o vivir en ellas; remodelar calidad.
- **Vista interior** (estilo Los Sims): objetos cotidianos automáticos según nivel, calidad y época. Choza: jergón o catre de paja, tinaja de barro, fogón, canastos de fique, mechero de sebo; adobe: catre, fogón de barro, baúl; ladrillo: cama con dosel, bañera, clavicordio; con investigación: inodoro, bombilla, radio… Interactúa con quien vive ahí.
- **Tu personaje** es un ciudadano real: nombre, apellido, sexo y edad al inicio; enferma (médico), envejece y muere. Conoce gente en la calle (conversar, citas, matrimonio), busca hijos con tu pareja, adopta, invita a vivir contigo, elige heredero: **al morir, tu hijo(a) continúa la dinastía**.
- **Tiempo real** (1 s = 1 s) además de x1/x2/x3/x4.
- **Expandir terreno**: compra zonas vecinas.

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
| Pausa / velocidades | Espacio · 1 real · 2 x1 · 3 x2 · 4 x3 · 5 salto de años |
| Menú (guardar/cargar) | Esc |
| Seleccionar persona o edificio | Clic izquierdo |
| Construir: rotar / cancelar | R / clic derecho o Esc |
| Interior: rotar / zoom / salir | Q-E / rueda / Esc |

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
Para agregar contenido basta con editar los JSON de `data/` — `businesses.json` (negocios y niveles), `buildings.json` (viviendas, calidades, oficina), `interiors.json` (muebles por época y calidad), `goods.json`, `legal_types.json`, `economy.json` (inflación, precios, banca, quiebras), `technologies.json`. Los modelos 3D de cada nivel también están en JSON.

## Pruebas
```
godot --headless res://tests/test_runner.tscn   # pruebas de simulación, guardado, mapas y salto x4
godot --headless res://tests/balance.tscn       # diagnóstico demográfico a 40 años
godot --headless res://tests/ui_smoke.tscn      # abre todos los paneles de la interfaz
godot --headless res://tests/economy_diag.tscn  # inflación y precios a 30 años
```
