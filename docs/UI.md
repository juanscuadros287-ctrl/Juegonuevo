# Interfaz (UI) — sistema de diseño, HUD, paneles y gráficas

Todo vive en `scripts/ui/`. La interfaz **solo lee** el estado (`GameState`) y llama a las APIs de
simulación existentes; no contiene lógica de juego.

Capturas antes/después: `docs/capturas/ui/antes/` y `docs/capturas/ui/despues/` (1600×900), más
`docs/capturas/ui/despues_1280x800/` y `docs/capturas/ui/despues_2560x1600/`. Para regenerarlas:

```
xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 \
    tests/screenshot_ui.tscn -- docs/capturas/ui/despues
```

## 1. Sistema de diseño (`ui_kit.gd`)

| Token | Uso |
|---|---|
| `BG`, `BG_LIGHT`, `BG_RAISED`, `BG_DEEP` | panel, tarjeta, botón/campo, fondo de gráficas y tablas |
| `ACCENT` (dorado) · `ACCENT_2` (azul) | títulos, selección · datos y enlaces |
| `TEXT`, `TEXT_DIM`, `TEXT_FAINT` | jerarquía de texto (contraste ≥ 4.5:1 sobre `BG` para `TEXT`/`TEXT_DIM`) |
| `GOOD` / `BAD` / `WARN` / `INFO` / `NEUTRAL` | ganancia / pérdida / aviso / información / sin cambio |
| `SERIES` | 8 colores distinguibles para gráficas |
| `FS_TITLE 20`, `FS_H2 16`, `FS_BODY 14`, `FS_SMALL 12`, `FS_TINY 11` | tipografía |
| `SP_XS…SP_L`, `RADIUS` | espaciados y radio de esquinas |

`UIKit.make_theme()` crea (una vez) el `Theme` común: paneles redondeados con sombra suave, botones
con estados *hover/pressed/disabled/focus*, pestañas con subrayado dorado, campos, menús
emergentes, tooltips, barras de progreso y de desplazamiento finas, listas, casillas y deslizadores.
El minimapa y el mapa ampliado (del agente del mapa) heredan este tema porque cuelgan de `hud.root`.

Constructores: `header()` (cabecera de panel con icono, título, botones extra y cerrar), `section()`
(sección plegable, recuerda su estado), `card()`, `kpi_card()` (icono, valor, tendencia, sparkline),
`chip()`, `progress()`, `meter_row()` (icono · etiqueta · barra · valor, verde/ámbar/rojo),
`money_label()`, `trend_bbcode()` (▲▼ coloreado; `invert` si subir es malo), `icon()`,
`icon_button()`, `primary()`/`danger()` (botón principal/destructivo), `modal()` (con icono, entra con
animación y se pone por encima de todo), `flow()`.

Animaciones: `animate_in()` / `animate_out()` (opacidad + desplazamiento), `pop_in()` (modales). El
panel lateral se desliza al abrir/cerrar (tween de márgenes), los toasts entran con rebote y salen
con desvanecido, y las gráficas se dibujan con animación.

### Escala (Retina / tamaño de interfaz)
`UIKit.hook_scale(nodo)` fija `Window.content_scale_factor` = máx(escala del sistema, tamaño de
ventana/1600×900) × ajuste del jugador, sin dejar un área lógica menor que 1200×700. En una Mac
Retina (escala 2) la UI se ve al mismo tamaño físico que en una pantalla normal; la selección 3D
sigue funcionando porque Godot convierte las coordenadas del ratón. El ajuste (70–160 %) está en
**Menú → Opciones** y se guarda en `user://ui_settings.cfg`.

**Integración con gráficos:** si existe el autoload `GraphicsSettings`, Opciones muestra una
sección «Gráficos»: llama a `GraphicsSettings.build_options_ui(caja: VBoxContainer)` si existe; si
no, ofrece Baja/Media/Alta/Ultra con `set_quality(i)` (y lee `quality`).

## 2. Iconos (`ui_icons.gd`)
~90 iconos propios de trazo (rejilla 24×24, sin copyright) escritos como SVG en el código y
rasterizados en tiempo de ejecución (×3, `size_override` al tamaño lógico → nítidos en Retina). Se
dibujan en blanco y se colorean con `modulate` o con los colores de icono del tema.
`UIIcons.tex("money", 18)`, lista en `UIIcons.names()`. Incluye indicadores (dinero, población,
felicidad, salud, crimen, inflación, PIB, tesoro, empleo), secciones (construir, empresas, finanzas,
estadísticas, gobierno, logística, comercio, contratos, transporte, servicios, bienes raíces,
catálogo, investigación, personaje, familia, dinastía), clima, tiempo (pausa, velocidades, salto),
notificaciones y controles.

## 3. HUD (`hud.gd`)
- **Barra superior** (46 px): pueblo y época · dinero, población, felicidad, salud con icono, valor
  y tendencia ▲▼ respecto al cierre del mes anterior (tooltips con detalle; clic abre Finanzas,
  Población o Estadísticas) · mini-retrato del jugador y aviso **SIN HEREDERO** · clima con icono y
  temperatura · indicador del ciclo económico (`CycleIndicator`, clic → Economía mundial) · fecha · controles de tiempo (pausa, tiempo real, ×1, ×2, ×3, salto) · campana con
  contador de no leídas · menú.
- **Barra de iconos** (izquierda) agrupada en categorías con **menús desplegables**:

  | Categoría | Entradas (atajo) |
  |---|---|
  | Mi dinastía (F1) | Mi personaje (P), Familia y herederos |
  | Construir (B) | — |
  | Empresas (F2) | Mis empresas (C), Bienes raíces (V), Contratos (K) |
  | Economía (F3) | Finanzas (F), Efectivo y riesgo, Estadísticas (Y), Economía mundial, Bolsa de valores, Seguros, Catálogo de bienes (O) |
  | Logística y transporte (F4) | Logística (L), Transporte público (J), Servicios públicos (U), Comercio exterior (X) |
  | Sociedad (F5) | Población (Z), Pueblos vecinos, Gobierno (G), Turismo y publicidad |
  | Ciencia (I) | Investigación |

  Notificaciones: N. Al pasar el ratón por otra categoría con el menú abierto, cambia. Clic fuera o
  Esc lo cierra. La categoría del panel abierto queda resaltada. Los atajos no se disparan mientras
  escribes en un campo ni dentro de una casa.
- **Toasts**: icono y color por categoría, franja lateral, entrada animada y salida con
  desvanecido. Se agrupan: el mismo texto suma «×N»; avisos seguidos de la misma categoría (o si ya
  hay 4 en pantalla) se funden en uno con «+N más».
- **Centro de notificaciones** (campana o N): filtros por categoría con contadores, lista con icono,
  fecha y texto (150 más recientes).
- **Ficha de persona**: retrato generado, etiquetas (edad, trabajo, relación, enfermo/cárcel),
  barras de salud, felicidad y necesidades, patrimonio, educación y habilidades, **talentos**,
  **árbol familiar** (padres, cónyuge, hijos; clic para ir a esa persona) y acciones con iconos.
  Se reconstruye al seleccionar o tras una acción; el refresco periódico solo toca las barras.
- **Población**: tabla (`DataTable`) ordenable por columna, con búsqueda, barras de salud y
  felicidad y clic para abrir la ficha.
- Modales con icono; Menú con Continuar/Guardar/Cargar/**Opciones**/Menú principal/Salir y lista
  de atajos. Reporte de salto de años en tabla coloreada.

## 4. Paneles
Todos usan `UIKit.header()` (icono + título + ↻ + cerrar). Destacados:
- **Edificio** (`building_panel.gd`): cabecera compacta con chips de estado, nivel, dueño y
  clasificación; tarjetas «Resultado mes ant.» y «Producción» con **mini-gráficas** (ingresos por
  día e inventario, muestreados por `UIHistory`); barras de empleados e inventario; en Resumen,
  **barras de ingresos y gastos por concepto**. Las pestañas se mantienen (las pruebas las usan).
- **Estadísticas** (`stats_panel.gd`), pestañas: *Resumen* (8 tarjetas: población, empleo,
  felicidad, salud, crimen, inflación, PIB del pueblo, tesoro — con tendencia y sparkline; medidores
  de necesidades, empleo, crimen y contaminación; gráfica de felicidad y salud; recomendaciones),
  *Población* (pirámide por edad y sexo, **dona de empleo por sector**, tabla de necesidades,
  vivienda), *Mercado* (tabla ordenable de bienes; **líneas de precios** y demanda), *Comercio*
  (**barras** de abastecimiento local/importado/autoabastecido y comercio por pueblo), *Pueblos*
  (**tarjetas por pueblo**: arquetipo, población, distancia, crecimiento, relación/ruta,
  **reputación**, sectores y precios de compra/venta) y *Empresas* (tabla de empresas NPC).
  `show_tab(id)` abre una pestaña.
- **Mis empresas**: tarjetas por negocio con franja de color por estado (rentable/equilibrio/
  deficitaria/cerrado), nivel, resultado, margen, empleados y alertas (vacantes, meses con
  pérdidas, sin almacén); resumen en tarjetas.
- **Finanzas**: tarjetas (dinero, patrimonio, deudas, resultado) con sparkline y tendencia,
  economía del pueblo en chips + tabla de precios, créditos, inversión e historial.
- **Mi personaje**: ficha visual (retrato, barras, patrimonio, talentos, árbol familiar) sobre el
  texto y las acciones de dinastía existentes. `scroll_to_family()`.
- **Contratos**: pestañas con icono.
- **Efectivo y riesgo** (`cash_panel.gd`), **Economía mundial** (`global_econ_window.gd`, con
  pestañas Ciclos y monedas / Bolsa (`stock_panel.gd`) / Seguros (`insurance_panel.gd`)): cabecera
  estándar, pestañas con icono, ventana flotante con sombra y animación de entrada; accesibles desde
  la categoría Economía. Finanzas muestra efectivo/banco e impuesto a la venta en chips.

## 5. Gráficas y datos (todas con `_draw`, sin crear nodos por punto)
| Clase | Qué hace |
|---|---|
| `LineChart` | curvas suavizadas (Catmull-Rom), relleno degradado, ejes limpios con números compactos, leyenda, animación de dibujo, punto con valor y fecha al pasar el ratón. `set_data(titulo, series, dinero?, etiquetas_x)` |
| `BarChart` | barras horizontales (1–3 series, color por fila opcional), animación y valor al pasar el ratón |
| `DonutChart` | dona/torta con leyenda, total al centro, barrido animado, resaltado del sector |
| `Sparkline` | mini tendencia con relleno |
| `Gauge` | medidor semicircular verde/ámbar/rojo con aguja animada (`invert` para crimen) |
| `PyramidChart` | pirámide de población por grupos de 10 años y sexo |
| `DataTable` | tabla rápida: encabezado fijo, filas alternadas, orden por columna, barras en línea, colores por valor, rueda y clic por fila (miles de filas sin miles de nodos) |
| `Portrait` | retrato generado (piel, pelo, ropa por época, canas, barba, sombrero antiguo) |
| `FamilyTree` | árbol familiar simple |
| `MenuBackground` | fondo ilustrado animado del menú principal |
| `UIHistory` | muestras solo de interfaz (ingresos/inventario diarios por edificio, tesoro mensual); no se guardan |

## 6. Menú principal
Fondo ilustrado (atardecer, colinas, pueblo colonial con iglesia y ventanas encendidas, nubes que
se mueven), título con corona, botones grandes con iconos. Nueva partida en dos columnas: personaje
y pueblo; **dificultad en tarjetas con icono** (brote, escudo, alerta, calavera) y resumen;
**tarjeta del país** con inspiración, descripción, moneda, **ventajas/desventajas de recursos** e
inflación base; mini-mapa del lugar de fundación.

## 7. Rendimiento
- Ningún panel se reconstruye cada frame. La barra superior actualiza textos cada 0,25 s y
  tooltips/retrato cada 2 s; el panel de edificio actualiza su texto cada 0,25 s y la cabecera con
  gráficas cada ~3 s; la ficha de persona solo sus barras. Estadísticas se reconstruye al abrir, al
  cambiar de pestaña o con ↻.
- Tablas grandes (población, mercado, empresas) con `DataTable` dibujada.
- Iconos rasterizados una vez y cacheados por nombre y tamaño.

## 8. Pruebas
`tests/ui_smoke.tscn` abre todos los paneles, cada categoría y entrada del menú desplegable, las
pestañas de estadísticas, la tabla de población (búsqueda y orden), toasts agrupados, el centro de
notificaciones con filtro, Opciones, atajos de teclado, todas las gráficas, todos los iconos y el
menú principal. `tests/screenshot_ui.tscn` genera las capturas.
