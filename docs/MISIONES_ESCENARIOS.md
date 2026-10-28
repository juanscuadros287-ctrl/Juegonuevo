# Misiones guía, escenarios de inicio, dificultad y logros

Pedido de la sección I de `docs/PENDIENTES.md` (misiones guía, escenarios, dificultad y logros).

El código está en:
- `scripts/sim/progress_sim.gd`: `ProgressSim`, misiones y logros.
- `scripts/sim/scenario_sim.gd`: `ScenarioSim`, escenarios.
- `scripts/ui/guide_panel.gd`: `GuidePanel`, panel, aviso y ventana de logros.

Los datos están en `data/progreso.json`. La prueba es `tests/test_misiones_escenarios.tscn`. Las capturas están en `docs/capturas/misiones/`.

## Misiones guía

Hay 7 misiones. Todas son opcionales y su orden no importa.

| Misión | Se cumple cuando | Premio base |
|---|---|---|
| Primera fábrica | tienes un negocio propio activo | 200 |
| Contratar personal | tienes 3 empleados en tus edificios | 120 |
| Primer contrato | tienes cualquier contrato en `ContractSim.contracts` | 150 |
| Primer vehículo y ruta | tienes un vehículo y una ruta de carga (`LogisticsSim`) | 200 |
| Primera venta mayorista | hiciste un envío a un pueblo vecino (`trade.totals.exports > 0`) o cobraste una entrega de un contrato de venta | 150 |
| Investigar | tienes una tecnología más que al empezar | 120 |
| Tener un heredero | tienes un hijo vivo | 150 |

### Interfaz

- El panel es pequeño y está arriba a la derecha, bajo la barra superior.
- El título muestra el avance, por ejemplo «Misiones guía 2/7».
- Tiene dos botones: **plegar** (deja solo el título) y **ocultar** (no queda nada en pantalla).
- Para volver a mostrarlo: **Mi dinastía → Misiones guía**.
- Si el panel lateral (ficha o edificio) está abierto, el panel de misiones se corre a su izquierda.
- No hay pop-ups. La pista de cada misión aparece al pasar el ratón.
- Al cumplir una misión no sale un toast del HUD. Aparece un aviso discreto abajo a la derecha, encima del «Guardado ✓», y una línea en el centro de notificaciones.
- El estado del panel (oculto o plegado) se guarda con la partida.

### Revisión

- Las misiones se revisan cada 7 días y al empezar cada mes, desde `GameState.simulate_country_day`, en el pase del país de origen.
- Lo que ya se cumple al empezar o al cargar una partida vieja cuenta como hecho, pero **sin premio**. Por ejemplo, la granja del escenario quebrada.

### Recompensa con origen

El premio es `premio base × gs.price_mult()`. Se paga así:

1. Primero sale del tesoro del pueblo, como fondo de fomento (`GovSim.treasury_pay`).
2. Si el tesoro no alcanza, la cámara de comercio exterior paga el resto: `FlowSim.external_in(gs, resto, "premio_mision_guia")`.

Cada misión cumplida guarda `reward`, `from_treasury` y `from_external`. También se añade una línea a `progress.rewards_log`.

El premio cuenta en `subsidies` del mes. `test_conservacion` y la prueba nueva verifican que el total conservado no cambia.

## Escenarios de inicio

El escenario se elige en el menú principal, en Nueva partida, en la columna «Escenario». Cada uno tiene su descripción y sus cifras. Se guarda en `settings.scenario` y en la cabecera de la ranura (`meta.scenario`, chip en la lista de partidas).

| Escenario | Efecto |
|---|---|
| Normal | Sin cambios. Con la misma semilla da el mismo estado que antes. |
| Empezar pobre | 15 % del capital y puntaje de crédito 590. |
| Empresa quebrada | Heredas la «Granja de la familia», ya activa y valorada por su costo de obra, y un préstamo del banco externo en **mora** (2 cuotas atrasadas) de 1,6 × el capital de la dificultad, al 13 % y a 36 meses. Además tienes el 35 % del capital y puntaje 520. |
| Otro país | Elegir este escenario abre el **mapa mundial** del menú, el selector de país que ya existía, para escoger el destino. Traes el 70 % del capital, puntaje 600 (sin historial local) y +15 en comercio. |
| Época industrial | Año 1830 y época 2. Tienes todas las tecnologías de la época 1, incluida la que da paso a la industrial. Capital × 2. |
| Época moderna | Año 1950 y época 3. Tienes todas las tecnologías de las épocas 1 y 2. Capital × 4. |

### Empresa quebrada

El préstamo heredado lleva `purpose: "herencia_quiebra"`. Representa una deuda de antes de empezar, así que **no mueve dinero** al crearse: nadie gana ni pierde nada.

Se negocia con `CreditSim` desde Finanzas, con estas opciones:
- **Plazo**: puntaje ≥ 420.
- **Gracia**: mora ≤ 2 y puntaje ≥ 480.
- **Dación**: entregar la granja.
- **Rebaja**: requiere tener en caja cerca del 84 % de la deuda.

Si se deja pasar otra cuota sin pagar, llega el embargo normal de `BankSim`, a las 3 cuotas.

### Época

`TimeManager.start_year()` lee `settings.start_year`; si no existe, usa el de `game.json`. Así las fechas y el año se ajustan solos.

`ScenarioSim.apply_early` corre antes de crear la población y el gobierno, para que el régimen corresponda a la época. `ScenarioSim.apply_late` corre al final de `new_game`.

El capital inicial sigue siendo parte del estado inicial, como hasta ahora; no es un pago.

## Dificultad

El menú muestra Fácil, Normal y Difícil, además de Extremo, que ya existía y se mantiene. Cada nivel describe:
- capital;
- ciudadanos;
- interés del banco;
- enfermedades;
- precios;
- frecuencia de eventos negativos;
- **agresividad de los rivales**.

El campo nuevo `npc_aggression` (en `data/difficulties.json`) vale 0,6 en Fácil, 1 en Normal, 1,4 en Difícil y 1,8 en Extremo. Lo usa `LaborSim.npc_aggression(gs)` para tres cosas:
- la probabilidad de que una empresa NPC empiece una guerra de precios;
- el recorte de precio de la guerra (nunca a pérdida);
- la probabilidad de ofertas a tus empleados.

En Normal todo da exactamente lo mismo que antes. El capital, la tasa del banco y la frecuencia de eventos ya dependían de la dificultad.

## Logros

Hay 23 logros. La ventana está en **Mi dinastía → Logros**:

- primeras metas: Bien orientado (toda la guía), Primer negocio;
- empresas y empleo: Empresario (5 negocios), Conglomerado (20), Gran empleador (50 empleados);
- patrimonio: Primeros ahorros (10 mil), Fortuna (100 mil), Primer millón;
- dinastía: Tres generaciones, Linaje (5 generaciones);
- mercado y comercio: Monopolio (único productor de un bien en el país, con ≥ 2 negocios), Exportador (50 mil exportados), Multinacional (presencia en 5 países);
- finanzas: Sin deudas (10 años seguidos sin deudas ni saldo en rojo), Buen pagador (puntaje 800);
- ciencia y épocas: Ilustrado (10 tecnologías en la partida), Nueva época, Mundo moderno;
- pueblo y tiempo: Ciudad (300 habitantes), Centenario (100 años de partida);
- de escenario o dificultad: Remontada (saldar la deuda heredada), Desde abajo (50 mil en el escenario pobre), A pulso (100 mil en Difícil o Extremo).

Los patrimonios se miden en precios constantes: `net_worth / price_level`.

Los logros se revisan cada mes. Cada uno da un aviso discreto; si llegan varios a la vez, se funden en «+N más».

Se guardan en dos lugares:
- en la partida: `progress.achievements`, con su fecha;
- en el **perfil global** `user://logros.cfg` (ConfigFile, sección `logros`, con la fecha real, la fecha del juego, el jugador, el pueblo, la dificultad y el escenario).

La ventana muestra tres estados: «Desbloqueado el …», «Conseguido en otra partida» (está en el perfil) o «Bloqueado».

El perfil solo se escribe cuando `ProgressSim.profile_enabled` está activo. El menú principal lo activa al entrar a jugar, salvo en escenas de `res://tests/`. Así las pruebas no ensucian el perfil del jugador. Al entrar a jugar también se copian al perfil los logros de la partida cargada.

## Guardado y compatibilidad

`GameState.progress` es una clave nueva de `to_dict`. No hace falta migración (ver `docs/GUARDADO.md`, tolerancia):

- **Partida vieja sin `progress`**: se crea al cargar. Lo ya cumplido queda hecho sin premio. Los logros se otorgan en la primera revisión mensual.
- **Partida vieja sin `scenario` ni `difficulty`**: queda en `normal` / `normal` (`SETTINGS_FALLBACK`).
- **Escenario desconocido**: queda en `normal`.

El formato sigue en la versión 8.

## Pruebas

`godot --headless tests/test_misiones_escenarios.tscn` debe dar «TODO OK». Cubre:
- los datos (5–8 misiones, ≥ 20 logros, descripciones y agresividad);
- que el escenario normal deja la partida idéntica;
- cada misión y su premio pagado una sola vez, desde el tesoro o desde el exterior con su motivo, con conservación;
- que ocultar o plegar se guarda;
- cada escenario: capital, crédito, país, época, año y tecnologías;
- el escenario quebrada: empresa, mora, opciones de `CreditSim`, negociación de gracia y conservación a 3 meses;
- la dificultad: capital, tasa, eventos y agresividad;
- los logros: millón, a pulso, monopolio, sin deudas, perfil global y guardado;
- las partidas viejas, también por ranura real;
- la simulación de 4 meses;
- la interfaz: panel, plegar, ocultar, ventana, aviso y menú con escenarios. En el menú, «Otro país» abre el mapa mundial.

Capturas:

```
xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 \
    tests/screenshot_misiones.tscn -- docs/capturas/misiones
```
