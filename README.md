# Dinastía

Simulación económica y construcción de pueblo desde 1700 (Godot 4, GDScript, 3D low‑poly).
Empiezas como empresario en un pueblo que crece: con el libre mercado, otros ciudadanos abren sus negocios, los pueblos vecinos crecen y el gobierno ejecuta su propio plan.

> El nombre del juego se cambia en `data/game.json` y `project.godot`.

## Estado: Fases 1–8 completas

| Fase | Contenido | Estado |
|---|---|---|
| 1 | Mapa 3D, cámara, tiempo y ciudadanos | ✅ |
| 2 | Construcción, negocios, tu personaje y vivienda | ✅ |
| 3 | Economía, precios y banca | ✅ |
| 4 | Árbol de investigación y épocas | ✅ |
| 5 | Gobierno, impuestos, servicios públicos y proyectos | ✅ |
| 6 | Recursos, almacén, cadenas de producción, transporte interno y carreteras | ✅ |
| 7 | Otros pueblos, rutas comerciales, comercio exterior, inmigración y transporte externo | ✅ |
| 8 | Turismo, publicidad, industria avanzada y dinastía | ✅ |

### Libre mercado
Ver `docs/MERCADO_LIBRE.md`.
- **Empresarios NPC:** los ciudadanos con ahorros abren negocios donde falta oferta y compiten contigo. Se heredan en la familia, pueden quebrar y se pueden comprar.
- **Pueblos vecinos:** crecen según la época y la ayuda de su gobierno, y comercian entre ellos.
- **Contratos de compraventa:** botón *Contratos*, con solicitudes entrantes que aceptas o rechazas, ofertas que envías, entregas, penalidades y reputación.
- **Plan de gobierno:** parques, salud, policía, escuelas y vivienda social.

### Redes de servicios públicos
Ver `docs/REDES.md`. Incluye tendido aéreo y cable subterráneo por tramos, reparto de energía por red,
industria que exige electricidad, casas altas que necesitan luz y agua, facturas mensuales, pozos
comunitarios, toma de río, planta de agua con tuberías y la capa verde/roja en el mundo (botón
*Servicios públicos*).

### Fases 6, 7 y 8
Ver `docs/FASE6.md` (recursos, almacén, recetas, rutas, carreteras), `docs/FASE7.md` (pueblos, rutas comerciales, exportación/importación, inmigración, transporte externo) y `docs/FASE8.md` (turismo, publicidad, industria avanzada, herencia y dinastía).

### Bienes raíces y crédito bancario
Apartamentos, edificios residenciales y rascacielos divididos en **unidades** que se arriendan o venden por separado
(precio y renta por unidad según nivel, calidad, época, demanda y piso), **ficha de factibilidad**, obra **pagada por
etapas**, **preventa sobre planos**, **crédito constructor**, créditos con banco/tipo de pago/tabla de amortización
(francés, alemán, bullet, gracia) e **hipotecas** para los ciudadanos. Ver `docs/BIENES_RAICES.md`.

### Fase 5 incluye
- **Gobierno** (botón *Gobierno*): en la colonia, virreyes por decreto que cambian cada 15–25 años; desde la república, **elecciones** cada 4 años donde votan los ciudadanos (pobres y ricos prefieren políticas distintas) y puedes **financiar campañas**. Cada gobierno trae sus políticas.
- **Impuestos**: ganancias (fundaciones exentas), propiedad y nómina; **salario mínimo**, **aranceles** a lo importado, **ayuda a los pobres**, **multas ambientales**. Todo va al **tesoro público**.
- **Misiones del gobierno** según las necesidades del pueblo (empleos, crimen, hospital, escuela, sin hogar, alumnos, contaminación) con recompensas en dinero y meses sin impuesto de renta.
- **Licitaciones de obras públicas** (plaza, iglesia, acueducto, puente, hospital de caridad): ofertas contra competidores (tu reputación ayuda), construyes y el gobierno paga el contrato; la obra da beneficios al pueblo.
- **Servicios públicos** por investigación, gestionados como negocios subsidiados (no cuentan para el límite de negocios): policía, bomberos, hospitales (exigen médicos; puedes cobrar la consulta) y cárceles (contrato del gobierno por preso y día).
- **Problemas y eventos**: crimen según pobreza, desempleo e infelicidad (robos a tus negocios y a ciudadanos, arrestos, presos); incendios (peores en chozas de paja y en verano); contaminación de la industria; epidemias, sequías, buenas cosechas, crisis económicas, auges comerciales, temporadas de incendios.

### Fase 4 incluye
- **Árbol de investigación visual** (botón *Investigación*): 3 épocas (Colonial → Revolución industrial → Moderna) y 10 ramas (agricultura, construcción, energía, transporte, medicina, industria, seguridad, comunicación, finanzas, educación). Proyecto actual, cola con prerrequisitos automáticos y tiempo estimado.
- **Laboratorios** (Gabinete → Laboratorio → Centro de investigación): solo generan gastos; producen puntos según educación y habilidad de ciencia; especialidad por rama (+50%); los niveles altos exigen personal con educación.
- **Efectos reales**: desbloquean niveles de casas/negocios y muebles de época; medicina reduce enfermedades y mortalidad (más esperanza de vida); mejoras de producción, velocidad de obra, felicidad e investigación.
- **Educación**: la escuela y el colegio dan habilidades básicas/secundarias; las **profesiones** (científico, médico, ingeniero, administrador, profesor) solo las da la **universidad** con carreras que tú eliges. Laboratorios avanzados exigen científicos, constructoras grandes ingenieros, bancos grandes administradores (y los hospitales de la Fase 5, médicos). Al inicio algunos habitantes ya tienen estudios básicos y unos pocos una profesión.
- **Construcción en modo libre**: coloca donde quieras y gira a cualquier ángulo (R/T 15°, Shift+rueda libre). Botón *Mover / girar* en tus edificios (girar gratis, trasladar cuesta 15% de la obra).

### Fase 3 incluye
- **Economía cerrada y realista**: el dinero no aparece de la nada. Los desempleados se autoabastecen en especie (cultivan, buscan agua y leña) con peor calidad de vida; el dinero entra solo por salarios, obras y préstamos, circula cuando la gente compra en tus negocios (incluido el gasto de sus ahorros) y sale por importaciones. La inmigración y el comercio con otros pueblos llegarán con los caminos (Fase 6).
- **Terreno del gobierno**: para construir en zonas nuevas hay que comprarle el terreno al gobierno (el dinero va al tesoro público).
- **Estadísticas**: comercio por bien (precio y tendencia ▲▼, demanda, lo que venden tus negocios, lo que queda sin cubrir), qué se pide más y menos, necesidades cubiertas/a medias/sin cubrir, empleo buscado y vacantes, demanda de vivienda por calidad (normal/media/alta), población y recomendaciones automáticas.
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
| Construir/mover: girar / cancelar | R-T (15°), Shift+rueda (libre) / clic derecho o Esc |
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
Para agregar contenido basta con editar los JSON de `data/` — `businesses.json` (negocios y niveles), `buildings.json` (viviendas, calidades, oficina), `interiors.json` (muebles por época y calidad), `goods.json`, `legal_types.json`, `economy.json` (inflación, precios, banca, quiebras), `technologies.json` y `eras.json` (árbol de investigación), `professions.json`, `government.json` (gobiernos, leyes, misiones, licitaciones) y `events.json` (crimen, incendios, contaminación, eventos), `technologies.json`. Los modelos 3D de cada nivel también están en JSON.

## Pruebas
```
godot --headless res://tests/test_runner.tscn   # pruebas de simulación, guardado, mapas y salto x4
godot --headless res://tests/balance.tscn       # diagnóstico demográfico a 40 años
godot --headless res://tests/ui_smoke.tscn      # abre todos los paneles de la interfaz
godot --headless res://tests/economy_diag.tscn  # inflación y precios a 30 años
godot --headless res://tests/test_fase6.tscn    # recursos y logística
godot --headless res://tests/test_fase7.tscn    # comercio exterior
godot --headless res://tests/test_fase8.tscn    # turismo, publicidad, industria, dinastía
godot --headless res://tests/test_bienes_raices.tscn  # unidades, proyectos por etapas, preventa, créditos, hipotecas
godot --headless res://tests/test_redes.tscn    # redes eléctricas y de agua
```

Ideas acordadas para próximas fases: ver `docs/ROADMAP.md`.
