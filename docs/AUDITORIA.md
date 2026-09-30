# Auditoría de Dinastía (septiembre 2026)

Hice la auditoría sobre el commit `ba39115` (Mapa v2), con Godot 4.3 headless. Para las pruebas dinámicas usé scripts temporales `tests/_audit_*`, que ya borré. Esos scripts repetían el día de `GameState.simulate_country_day` paso a paso y medían, antes y después de cada sistema:

- el dinero de cada bolsillo: jugador, ciudadanos, cajas de las empresas NPC y fundaciones, tesoro, tesoros municipales, pueblos vecinos, bolsa (`world_cash`) y aseguradora externa;
- el tiempo de cada sistema.

Además revisaban cada trimestre si había estados imposibles.

No reporto como faltante lo que ya están haciendo otros agentes:
- barcos y rutas unificadas;
- slots de guardado, autoguardado y exportación a macOS.

**Estado general.** Pasan las 21 suites existentes: `test_runner`, `test_fase6` a `test_fase10`, `test_mercado`, `test_mapa`, `ui_smoke`, etc. En ninguna partida larga apareció un error de script del juego. Los únicos "ERROR" del log salen del renderizador *dummy* en modo headless (`mesh_get_surface_count`) y son inofensivos. Los datos JSON están limpios:
- no hay IDs duplicados entre archivos;
- ninguna tecnología falta ni desbloquea nada;
- no hay ciclos en el árbol;
- todas las recetas ganan a precio base;
- ningún bien queda sin productor.

Los problemas de verdad están en otros tres frentes:
1. el **balance macroeconómico**: el dinero se evapora y el pueblo se muere si el jugador no lo sostiene;
2. el **rendimiento** con poblaciones grandes;
3. varias **reglas de fin de partida** poco divertidas.

---

## Métricas de las simulaciones largas

Leyenda de columnas:
- **Modo:** *pasivo* = el jugador no hace nada; *activo* = un bot que construye, contrata, investiga, pide crédito, se casa, abre rutas y demuele; *rico+tec* = activo con caja repuesta a $30.000 y 5 tecnologías regaladas cada 3 años, para llegar a la época industrial.
- **Pobl.:** población al inicio → al final.
- **Tesoro:** tesoro del gobierno al final.
- **Dinero interno Δ:** jugador + ciudadanos + cajas + tesoros, del inicio al final. Los pueblos vecinos se cuentan aparte.
- **Pueblos Δ:** cambio en la caja de los pueblos vecinos.
- **ms/día:** tiempo real por día simulado.

| Partida | Modo | Años (fin) | Pobl. | Desempleo final | Felic. | Crimen | Nivel de precios | Tesoro | Dinero jugador | Dinero interno Δ | Pueblos Δ | ms/día |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| COL normal s7 | pasivo | 8 (muere sin herederos, 1708) | 31→34 | 93 % | 63 | 19 | 0,94 | 2173 | +2116 | 12.8k→4.3k | +73k | 11–16 |
| COL difícil s11 | pasivo | 35 (muere, 1735) | 25→42 | 100 % | 61 | 28 | 1,19 | 2107 | **−35.483** | 10k→−33k | +220k | 11–26 |
| COL normal s7 | activo | 50 (vivo) | 31→37 | 100 % | 53 | 47 (pico 63) | 1,37 | 71 (en 0 entre años 32 y 40) | **−35.201** | 12.8k→−35k | +372k | 12–40 |
| MEX fácil s3 | pasivo | 33 (muere) | 43→58 | 100 % | 58 | 22 | 0,93 | 0 | −10.414 | 17k→−10k | +160k | 13–17 |
| ESP extremo s21 | activo | 13 (muere) | 15→18 | 100 % | 68 | 40 | 1,09 | 3406 | −15.923 | 8k→−12k | +139k | 7 |
| Respaldo (sin país) s7 | pasivo | 28 (muere) | 31→41 | 100 % | 56 | 36 | **0,72** (deflación) | 0 | −10.389 | 12.8k→−10k | +96k | 11–15 |
| COL normal s5 | rico+tec | 12 (se cortó por tiempo) | 31→490 | 44 % | 73 | 4 | 1,61 (inflación del 5–7 %/año) | 153 | 46k | +524k (inyectado) | +123k | 22 → **744** |
| USA difícil s9 | rico+tec | 17 (se cortó por tiempo) | 22→622 | 58 % | 73 | 10 | 1,93 | 174 | 62k | (inyectado) | +231k | 10 → **1350** |
| Pueblo grande COL s13 (561 hab., 111 negocios, 275 edificios) | pasivo, con dinero inicial | 3 | 561→630 | 100 % en el año 2 (quiebra) | 65 | 20 | 0,96 | 21.8k | 81.7k → −2.1k | −123k | +9k | **581–1286** |

Esto dice cada paso, en todas las partidas, sobre el dinero interno:

| Paso | Efecto |
|---|---|
| `PopulationSim.daily` | −1.000/año en un pueblo de 30 hab. Son importaciones justificadas, pero nada las compensa |
| `BusinessSim.produce` | −78k en 2 años en el pueblo grande: mantenimiento e insumos pagados a nadie |
| `MarketSim.monthly_housing` | −38k: chozas autoconstruidas pagadas a nadie |
| `FreeMarketSim.monthly` | Crea entre +73k y +400k en las cajas de los pueblos vecinos |
| `BankSim.monthly` | Solo entradas por préstamos externos (justificadas) |

En todas las partidas los **precios de bienes** quedaron sanos (factor entre 0,9 y 1,1, nunca 0, negativos ni NaN). Tampoco aparecieron NaN, stocks negativos, capacidades ≤ 0 ni préstamos o rutas colgando.

---

## A. Errores confirmados

| # | Severidad | Error | Evidencia y cómo reproducirlo |
|---|---|---|---|
| A1 | **Alta** | **Rendimiento cuadrático en `PopulationSim.daily`.** Cada ciudadano, cada día, recorre todos los edificios varias veces. `TechSim.happiness_bonus` llama a `GovSim.project_happiness`. `TechSim.world_mult("disease")` en `_health` y `world_mult("mortality")` en `daily_death_probability` llaman a `GovSim.project_mult`. Cada una recorre `gs.buildings`: ≈54 µs por llamada con 193 edificios. | `tech_sim.gd:146-156`, `gov_sim.gd:563-587`, `population_sim.gd:148,352,402`. Con 600 hab. y 275 edificios, PopulationSim tarda **778 ms/día** y el día completo 1,3 s. En x3 (7 días/s) serían ~9 s por segundo real: injugable. Con 30 hab. son 12 ms/día. **Arreglo:** calcular estos multiplicadores una vez por día (caché en `begin_day`) o al cambiar los edificios. |
| A2 | **Alta** | **Fugas estructurales de dinero sin destinatario** (sumideros no documentados, contra el principio de "economía cerrada"). Van a la nada: el mantenimiento y el `unit_cost` de los negocios del jugador, la parte en dinero del costo de obra (los jornales se pagan aparte, así que la mano de obra se cobra dos veces), la choza autoconstruida, las reparaciones por incendio y el anticipo de las obras públicas. | `business_sim.gd:180,207,218` (`pay` sin receptor); `construction_sim.gd:299-302` + `:339-342`; `market_sim.gd:263-265`; `events_sim.gd:209`; `gov_sim.gd:541`. En el pueblo grande se perdieron 123k en 3 años (−78k por produce y −38k por vivienda). Estas fugas causan la deflación y el empobrecimiento de la tabla anterior. **Arreglo:** mandar ese dinero a proveedores locales (`NpcBusinessSim._pay_local` ya existe), a constructoras o al tesoro, o registrarlo como importación explícita. |
| A3 | **Alta** | **El saldo negativo del jugador no tiene tope ni consecuencia real.** Con `pay_with`, la familia del jugador "nunca pasa hambre" y se endeuda sin límite. `_seize` embarga "nada" cuando no hay bienes, reinicia el contador y se repite cada 3 meses. | `population_sim.gd:229-240`, `bank_sim.gd:283-325`. En 4 de 6 partidas el jugador terminó entre −10.000 y −35.000 durante décadas, con avisos "EMBARGO: … nada" en bucle (más de 100 avisos de categoría *jugador*). |
| A4 | Media | **Contratar en un negocio cerrado.** `BusinessSim.hire` no revisa `status`. `produce` salta los cerrados, así que esos empleados quedan "empleados" sin sueldo y fuera del mercado laboral. El botón «Contratar…» del panel sigue visible. | `business_sim.gd:288-311`, `building_panel.gd:373`. La auditoría detectó 15 casos (`citizen_employed_in_closed_business`, aguatero cerrado). |
| A5 | Media | **El tesoro municipal puede quedar negativo.** La recompensa de una misión regional se resta del tesoro del municipio, que empieza en 0, sin revisar si hay fondos: se crea dinero. Ese tesoro tampoco entra en `FreeMarketSim.money_snapshot` ni en `CountriesSim.money_total`, así que las pruebas de conservación no lo ven. | `municipal_sim.gd:83` (`treasury: 0.0`) y `:428`; `free_market_sim.gd:116-128`. |
| A6 | Media | **El dinero de los muertos desaparece.** `_remove` borra al ciudadano con su `money`; no hay herencia para NPC salvo sus empresas. Las casas que eran suyas (`owner: ciudadano`, `owner_id`) quedan a nombre de un muerto. | `population_sim.gd:421-426`. Se perdieron hasta 4.764 en 3 años en el pueblo grande. Hubo hasta 2.199 detecciones de `house_owner_dead_or_gone` (MEX: 1.963). |
| A7 | Media | **Hacinamiento desde el día 1.** `generate_initial` mete familias de hasta 7 personas en chozas de capacidad 4. Ya en 1700 hay −8 de felicidad por hacinamiento. | `population_sim.gd:14-38`. En todas las partidas: `home_overcrowded` desde 1700, con ejemplos como "vivienda 6/4" y "7/4". |
| A8 | Media | **Gente sin techo con camas libres.** Hay casas del jugador vacías, pero la familia necesita tener 2 meses de renta ahorrados, y la renta se calcula por persona (`rent × size`). | `market_sim.gd:247-249`. Detectado de 29 a 199 veces por partida, por ejemplo "homeless 6, free 85". |
| A9 | Media | **Fin de partida abrupto.** Si el jefe muere sin hijos, termina la dinastía, aunque tenga cónyuge o hermanos, salvo que el jugador los haya puesto en la lista de herederos. En la partida pasiva de COL, el personaje de 25 años murió en 1708 (8 años de juego). | `player_sim.gd:320-331`. |
| A10 | Baja | **Liquidación por quiebra que crea dinero.** El remate del inventario entra a `gs.money` sin que nadie lo pague. | `business_sim.gd:340-351`. |
| A11 | Baja | **Contabilidad del banco propio.** El capital devuelto usa `gs.money +=` en vez de `add_money`, así que no aparece en ingresos, finanzas ni historial. | `bank_sim.gd:233`. |
| A12 | Baja | **Guardar y cargar no es idéntico en partidas con edificios sin `tier`.** `normalize_building` agrega `tier: "normal"` a negocios creados con `make_building`. El estado cargado difiere (1.203.437 frente a 1.204.483 caracteres de JSON). El juego sigue bien, pero rompe la comparación de determinismo. | `construction_sim.gd:10-31` frente a `:47-48`. |
| A13 | Baja | **Textos desactualizados.** "Requiere investigar: X **(Fase 4)**" muestra al jugador la fase de desarrollo. La ayuda de logística dice que los aviones de carga "llegarán en una fase posterior", pero ya existen (Fase 10). | `construction_sim.gd:123`, `logistics_panel.gd:261`. |

---

## B. Incoherencias

1. **El pueblo sin el jugador se muere.** En las 6 partidas no ricas:
   - el desempleo llega a 93–100 %;
   - las empresas NPC abren entre 1 y 4 negocios en 30–50 años y quiebran;
   - el tesoro del gobierno llega a 0 en MEX, en el mapa de respaldo y en la COL activa (años 16–32);
   - la caja total de los ciudadanos baja a $0–50 (de $500–2.700 al empezar).

   El dinero sale por importaciones y fugas (A2) y no vuelve a entrar: sin rutas abiertas no hay exportaciones, remesas ni gasto del gobierno. En la vida real un pueblo de 30–60 personas tiene artesanos y comercio propio.
2. **Los pueblos vecinos crean dinero de la nada.** `TownEconomySim.monthly` suma cada mes `pop × 0,9 × 15 %` y recorta la caja entre 0 y un tope (`town_economy_sim.gd:87-89`). Su caja total pasa de 34k a 400k en 50 años, mientras tu pueblo se empobrece. Es aceptable como "resto del mundo", pero hay que documentarlo y conviene que su riqueza dependa de su comercio.
3. **La doble moral de la "economía cerrada".** Los documentos (README, ECONOMIA.md) dicen que el dinero "no aparece de la nada", pero:
   - mantenimiento, obras e insumos lo destruyen (A2);
   - pueblos, quiebras y misiones municipales lo crean (B2, A10, A5).

   La inflación resultante no la manejan la oferta y la demanda sino estos sumideros: deflación a 0,72 en partidas pasivas, 5–7 % anual en las ricas.
4. **Doble cobro de la mano de obra en las obras.** El costo de obra (`cost`) ya supone la construcción, y además se pagan jornales diarios de 2,2 × trabajadores × días (A2).
5. **El acero aparece en la colonia.** El bien `acero` es de la época 2, pero su productor, la *Fundición*, solo pide la tecnología `carbon` (época 1).
6. **El heredero por defecto excluye al cónyuge.** `DINASTIA.md` permite al cónyuge en la lista, pero la regla por defecto solo mira a los hijos (A9). En la vida real la viuda o el hermano heredan.
7. **Educación mínima alta al inicio.** Con población colonial pequeña, 53 de 68 intentos de contratar fallaron con "se requiere educación Básica" (laboratorio, escuela, hospital). La escuela, a su vez, exige personal educado: hay un círculo difícil de romper sin ayuda.
8. **Un jefe de familia de 25–33 años muere con frecuencia.** 5 de 7 partidas terminaron por muerte del jugador antes de 35 años de juego. La mortalidad colonial es realista, pero no es divertido perder la partida sin aviso ni opciones.

---

## C. Riesgos

**Rendimiento**
- A1 es el cuello de botella principal. Hay otros O(N) por consulta que se multiplican:
  - `gs.employees_of` y `residents_of` recorren todos los ciudadanos, y se llaman por edificio en `produce`, `expected_output`, `_hire` y el panel;
  - `MarketSim.discretionary` tarda 7,7 ms por semana con 600 hab.;
  - `home_occupancy` tarda 0,25 ms y se recalcula varias veces al día;
  - `_births` + `_marriages` suman 0,8 ms/día.

  Con 3 países (Fase 10) el costo se multiplica. **Hay que medir con 1000 habitantes antes de publicar.**
- `CountryIndicator`, `world.gd` (refresca todos los agentes cada 2 s) y `hud._process` (cada 0,25 s) escalan con la población. No los medí en GPU.

**Guardado**
- Formato binario `store_var` (el archivo pesa 1,86 MB con 600 hab.; guarda en 52 ms y carga en 191 ms). Está atado a la versión de Godot. No hay escritura atómica (escribir a un temporal y renombrar), así que un cierre a mitad de guardado corrompe la partida. `SAVE_VERSION` sigue en 7 y todas las migraciones son "por defecto al cargar".
- Los parches por *load_dict* se acumulan en `_init_expansions`: hay que añadir una prueba de carga de partidas viejas por cada fase.

**Balance**
- La economía pasiva colapsa (B1). Con dinero y tecnología, la población crece de 22 a 622 en 17 años (+40 %/año, por inmigración) y aparecen 44 personas sin techo. No hay control de crecimiento ni de vivienda.
- La inflación depende de las fugas (B3). Si se arreglan A2 y B2 sin recalibrar, cambiará todo el balance: arreglar y calibrar juntos.

---

## D. Mejoras propuestas

Impacto: A = alto, M = medio, B = bajo. Esfuerzo: S = pequeño, M = mediano, L = grande.

### Más real

| Mejora | Imp. | Esf. | Cómo hacerla |
|---|---|---|---|
| Artesanos y comercio NPC de base: carpintero, herrero, panadero del pueblo desde el inicio | A | M | Que `NpcBusinessSim` siembre 2–4 talleres al empezar y baje el umbral de ahorro para emprender en la colonia |
| Herencia NPC: dinero y casas al cónyuge o hijos | A | S | En `_remove`, repartir `money` y `owner_id` a la familia (o al tesoro si no hay familia) |
| Cerrar el circuito del dinero: mantenimiento, obras e insumos a proveedores locales o al tesoro | A | M | Reusar `_pay_local`; lo importado cuenta como `imports` |
| Remesas, exportación espontánea y arrieros NPC que venden la cosecha a otros pueblos | M | M | Un flujo mensual de los pueblos conectados a los ciudadanos productores |
| Vejez y pensiones: los mayores de 65 viven de sus hijos o de una caja de ahorro | M | M | En `_payers`, los hijos pagan a los padres ancianos |
| Mortalidad del jugador más baja (élite con médico) y enfermedades con nombre (fiebre amarilla, viruela) por época | M | S | Un multiplicador de salud para el jefe; `events.json` con nombres por época |
| Estaciones reales por hemisferio y latitud (Colombia sin invierno) | M | M | `WeatherSim` con la latitud del país (ya está en `CountryGen`) |
| Hitos históricos por país: independencia (1810 COL), abolición, ferrocarril, crisis de 1929, guerras mundiales | A | M | `data/historia.json` con fecha, país y efectos (régimen, arancel, demanda) |

### Más divertido

| Mejora | Imp. | Esf. | Cómo hacerla |
|---|---|---|---|
| Objetivos por época y "contratos de vida": ser el más rico del pueblo, llevar el tren, 3 generaciones | A | M | Un `GoalsSim` con metas por época, recompensa de reputación y dinero, y un panel |
| Logros (≈40) con aviso y galería | M | S | Escuchar señales de `EventBus` y guardar en `user://logros` |
| Dilemas con decisión (tipo Tropico): huelga, soborno del alcalde, epidemia (cerrar el mercado o no), pedido del virrey | A | M | Eventos con 2–3 opciones y efectos en `events.json` y un modal |
| Rivales NPC con nombre y personalidad (agresivo, prudente, corrupto) que compiten por licitaciones, tierras y matrimonios | A | L | Promover las 3 familias NPC más ricas a "casas rivales" con IA simple |
| Continuar como hermano, cónyuge o sobrino al morir, en vez de perder | A | S | Ampliar `on_player_death` con familia extendida y la opción de adoptar un heredero |
| Crisis memorables con arco: aviso → pico → recuperación (pánico bancario, plaga, incendio grande) | M | M | Reusar las señales de `GlobalEconSim` con narrativa y toasts |
| Curva de dificultad: los primeros 5 años más guiados, después más eventos | M | S | `event_freq_mult` creciente con los años de partida |

### Más completo

| Mejora | Imp. | Esf. | Cómo hacerla |
|---|---|---|---|
| Tutorial guiado de 10 pasos: construir granja, contratar, precio, casa, oficina, investigación | A | M | Una secuencia de misiones "tutorial" con flechas en el HUD (`GovSim` ya tiene misiones) |
| Crecimiento urbano con límites: vivienda social automática del gobierno si hay más de 5 % sin techo; urbanización NPC | M | M | `GovPlansSim` ya tiene `vivienda_social`: dispararla por umbral |
| Personalidad y rutinas visibles de los ciudadanos: ir al mercado, iglesia los domingos, fiestas patronales | M | M | Ampliar `citizen_agent.gd` con horarios por día de la semana y eventos del pueblo |
| Estadística "de dónde viene y a dónde va el dinero" (diagrama de flujos por mes) | A | M | Usar el mismo cálculo de bolsillos de esta auditoría, guardado en el historial |

### Experiencia, UI y audio

| Mejora | Imp. | Esf. | Cómo hacerla |
|---|---|---|---|
| **Audio (hoy no existe: ni un `AudioStream` en el código ni archivos de sonido).** Música por época (guitarra colonial → piano industrial → jazz/moderno) y ambiente: campo, lluvia, ciudad, fábricas | A | M | Un autoload `AudioManager` con 2 buses; cambiar la pista con `era` y `weather_changed` |
| Sonidos de interfaz: clic, caja registradora, construcción terminada, aviso importante | A | S | Conectar a `notification_posted` y `building_changed` |
| Números flotantes de dinero sobre los edificios (+$12 ventas, −$3 sueldos) | A | S | `Label3D` temporal en `world.gd` al cerrar el mes, o al vender en `earn` |
| Aviso claro de saldo negativo y su riesgo en la barra superior, en rojo con cuenta regresiva | M | S | Usar `player.negative_months` en `hud._update_top_bar` |
| Pantalla de fin: línea de tiempo de la dinastía, gráficas y "continuar con…" | M | M | Reusar el registro de `DynastySim` y `UIHistory` |
| Ayudas contextuales: por qué no puedo contratar, por qué la gente no alquila | M | S | Tooltips con el motivo de `hire` y `monthly_housing` en el panel |
| Clima visual por latitud y días más cortos en invierno lejos del ecuador | B | S | `sky_rig.gd` con la latitud real |

---

## E. Top 10 recomendado (en orden)

1. **Arreglar el rendimiento de `PopulationSim`** (A1): caché diaria de `project_mult`, `project_happiness` y `pollution_*`, índices de empleados y residentes. Es S–M y sin él no se puede probar nada grande.
2. **Cerrar las fugas y creaciones de dinero** (A2, A5, A6, A10, B2), con una prueba permanente de conservación por bolsillos, igual a la de esta auditoría, en `tests/`.
3. **Recalibrar la economía base** para que un pueblo pasivo no colapse (B1): artesanos NPC iniciales, herencia NPC y arrieros o exportación espontánea.
4. **Deuda del jugador con consecuencias claras** (A3): tope, aviso visible, bancarrota personal y opción de rescate.
5. **Continuidad de la dinastía** (A9): heredar al cónyuge, hermanos o sobrinos, adoptar, menos muertes prematuras del jefe.
6. **Audio básico**: música por época y sonidos de interfaz y acción.
7. **Tutorial y objetivos por época**, más logros.
8. **Dilemas y eventos históricos** por país y época.
9. **Feedback visual del dinero**: números flotantes y diagrama de flujos en Estadísticas.
10. **Arreglos menores**: A4 (contratar en un negocio cerrado), A7 (hacinamiento inicial), A8 (renta por persona), A12 y A13 (textos).

---

## Anexo: cómo se midió

- Configuraciones: semillas 3, 5, 7, 9, 11, 13 y 21; países COL, MEX, ESP, USA y respaldo; dificultades fácil, normal, difícil y extremo; de 3 a 60 años. El máximo real fue 50 años: las partidas pasivas terminan por muerte del jugador y las ricas se cortaron por tiempo, a más de 1 s por día.
- Estados imposibles revisados cada trimestre: NaN o infinitos, hogar o empleo en edificios inexistentes, cónyuges asimétricos, capacidad ≤ 0, inventario o stock negativo, empleados de más, préstamos de muertos, prestamista demolido, contratos o rutas huérfanos, tesoros negativos y precios fuera de ×0,33–×3. **Solo aparecieron** los casos de A4, A6, A7 y A8.
- La demolición de una casa habitada y de un negocio con empleados, en el año 12 del modo activo, no dejó referencias colgando: `demolish` limpia empleos y hogares.
