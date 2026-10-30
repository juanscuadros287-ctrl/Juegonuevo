# Vida social y socios

Este documento cubre cinco cosas:

- socios en tus empresas;
- hablar con la gente que camina por el pueblo, incluido tu personaje;
- el dispositivo de cada época, abajo a la derecha;
- conversaciones con emociones, memoria y consecuencias;
- cómo se guarda todo.

Hay dos reglas que valen para todo:

- **Economía cerrada.** El dinero solo cambia de bolsillo. No se crea ni se destruye. `tests/test_conservacion` sigue dando una deriva de 0.
- **Moderado.** Llega a lo sumo un aviso social cada 15 días. Lo demás espera en el buzón del dispositivo. Las propuestas espontáneas de los contactos son raras: como máximo una cada 45 días.

| Archivo | Qué hace |
|---|---|
| `scripts/sim/social_sim.gd` (`SocialSim`) | Emociones, personalidad, saludos, conversaciones, memoria, favores, trabajo, cenas, regalos, dispositivo, mensajes, sucesión |
| `scripts/sim/partners_sim.gd` (`PartnersSim`) | Socios: aportes, reparto de utilidades, comprar o vender participación, desacuerdos, herencia |
| `scripts/ui/social_ui.gd` (`SocialUI`) | Botón y ventana del dispositivo, conversación, oferta de trabajo, formulario de sociedad, sección «Ánimo y relación» de la ficha |
| `scripts/ui/partners_tab.gd` (`PartnersTab`) | Pestaña «Socios» del panel de edificio |
| `data/social.json` | Parámetros de todo lo anterior |
| `tests/test_social.gd` | Pruebas: más de 110 comprobaciones, de la simulación a la interfaz |
| `tests/screenshot_social.gd` | Capturas en `docs/capturas/social/` |

## 1. Socios

Un **socio** es un ciudadano adulto que entra en una de tus empresas con fines de lucro. Aporta una de dos cosas:

- **Capital:** dinero que pasa de su bolsillo al tuyo en el momento de aceptar.
- **Habilidades:** su oficio en el sector, o su talento para los negocios. Sube la producción del negocio en +0,15 % por punto, con un máximo de +12 %. La habilidad mínima es 35.

A cambio recibe un **% de la utilidad de cada mes**. Tú conservas siempre el control: entre todos los socios suman como máximo el **49 %**. Cada negocio admite hasta 3 socios.

**Valor del negocio.** Se calcula así:

> valor = lo invertido (`EconomySim.property_value`) + utilidad del mes pasado × 18

**Parte justa por un aporte de capital:**

> parte justa = capital / (valor + capital)

**Parte justa por habilidades:** 1,2 × la mejora de producción que aporta, entre el 3 % y el 15 %.

**Probabilidad de que acepte.** Va del 3 % al 95 % y la suben:

- la relación;
- ofrecerle más de lo justo (ofrecerle menos la baja);
- que el negocio haya ganado el mes pasado (las pérdidas la bajan);
- su ambición;
- su confianza.

**Reparto de utilidades.** Ocurre en `PlayerSim.monthly`, después de `BusinessSim.monthly`, con el mes ya cerrado:

- El socio cobra utilidad × su %. El dinero sale de `gs.money` y va a `c.money`.
- Si hubo pérdidas, no se reparte nada.
- No se paga dos veces el mismo mes.
- El pago no se anota en el libro del negocio, para no deformar la utilidad del mes siguiente. Se suma al contador del mes `partner_payouts`.

**Comprar o vender participación:**

- **Comprarle su parte:** pide su % × el valor del negocio, más una prima. La prima es del 5 %, o del 15 % si está descontento.
- **Ofrecerle el 85 %:** puede rechazar. Si rechaza, baja su satisfacción.
- **Venderle un 5 % más:** paga ese 5 % × el valor del negocio, si tiene el dinero y quiere.

**Satisfacción** (0-100). Sube con las utilidades y baja con las pérdidas, y baja más si el negocio lleva 3 meses perdiendo. Con el tiempo tiende a 60.

**Desacuerdos.** Si la satisfacción baja de 30, cada mes hay un 35 % de probabilidad de que el socio abra un desacuerdo. El motivo puede ser:

- las pérdidas;
- el reparto;
- tu política de precios, si vendes por debajo del 70 % del precio normal.

Mientras el desacuerdo sigue abierto, la producción del negocio baja un 8 %. Llega un aviso. Cómo resolverlo, en la pestaña Socios:

| Opción | Efecto |
|---|---|
| Negociar | Probabilidad según la relación, tu talento para los negocios y su satisfacción. Si sale bien, se resuelve. Si sale mal, baja la relación |
| Compensar | Le pagas el doble del último reparto (mínimo el 1 % del valor del negocio). Se resuelve |
| Ceder 3 % | Le das un 3 % más de participación, sin dinero. Se resuelve |
| Ignorar | Bajan la satisfacción y la relación |
| Comprar su parte | Termina la sociedad |

Si el desacuerdo sigue 4 meses, el socio **exige que le compres su parte**:

- si tienes el dinero, la compra se hace sola, al precio que pide;
- si no lo tienes, recibes un aviso y el castigo a la producción sigue.

**Cuándo termina una sociedad:**

- **El socio muere:** su parte pasa a su primer heredero adulto (`PopulationSim.heirs_of`). Si no hay ninguno, vuelve a ti.
- **El socio emigra:** su parte vuelve a ti, sin pago.
- **El negocio deja de ser tuyo** (vendido, demolido o rematado): la sociedad se disuelve.
- **El socio pasa a ser el jefe de familia:** su parte vuelve a la familia.

**Dónde se usa:**

- la pestaña **Socios** del negocio, con el botón «Traer un socio…», que abre una lista de candidatos;
- el botón «Proponer sociedad…» de la ficha de persona;
- conversaciones: tras hablar de negocios con alguien ambicioso o con dinero, puede aparecer la respuesta «Proponerle ser socio(a)»;
- el buzón: un buen contacto puede ofrecerte invertir en tu empresa.

## 2. La gente que camina

Haz clic en cualquier persona para abrir su **ficha**. La sección nueva **«Ánimo y relación»** muestra:

- su **ánimo**: alegre, enojado(a), triste o tranquilo(a);
- su **rasgo** principal y lo que le gusta;
- las **cuatro emociones**, con barras de 0 a 100: alegría, enojo, tristeza y confianza;
- los favores que te debe;
- lo que **recuerda** de ustedes (las 3 últimas cosas);
- si es tu socio(a) y cómo está la sociedad.

**Acciones nuevas de la ficha:**

| Acción | Efecto |
|---|---|
| Saludar | Una vez al día. Con un desconocido se presentan (+3 a 5) y pasa a ser contacto. Con un conocido, +1 a 3 (menos si está enojado) |
| Conversar… | Abre la conversación (sección 4). Una por persona y día |
| Ofrecer trabajo… | Elige uno de tus negocios con vacantes y el sueldo. Muestra la probabilidad de que acepte. Si ya tiene empleo, se cambia solo si le pagas un 15 % más, o lo mismo si la relación es de 60 o más. Un dueño de negocio NPC no deja el suyo. Si acepta, te debe un favor |
| Invitar a cenar | La comida se compra en el pueblo (`FlowSim.pay_local`). Cuesta 4 × precios. Si acepta, sube la relación de +6 a +12, más alegría y confianza |
| Regalo | Cuesta 10 × precios y va a proveedores locales. Sube la relación +6 y te queda debiendo un favor. Uno al mes |
| Proponer sociedad… | Formulario con la empresa, el tipo de aporte, el capital y el %. Muestra la parte justa, el valor y la probabilidad |

Siguen las acciones de antes: cita, matrimonio, invitar a vivir contigo, adoptar, ver su casa y seguir con la cámara. El botón «Conversar» rápido de antes ahora abre la conversación completa. `PlayerSim.talk` sigue existiendo.

Mientras conversa contigo, la persona **se detiene**: se activa `CitizenAgent.hold`.

**Tu propio personaje** también tiene ficha. Lleva el anillo dorado de siempre. Su sección «Mi ánimo» muestra sus emociones, cuántos contactos tienes y el dispositivo de la época. El botón **«Mi carta / Mi telégrafo / Mi teléfono / Mi celular»** abre el dispositivo.

## 3. Dispositivo por época (abajo a la derecha)

Un botón redondo abajo a la derecha muestra el dispositivo actual, con un globo rojo de mensajes sin leer. Cuando el panel lateral está abierto, el botón se corre a la izquierda.

| Dispositivo | Llega con | Demora (ida, y lo mismo de vuelta) | Costo por envío | Llamar | Chat |
|---|---|---|---|---|---|
| Carta | desde el inicio | 3 a 6 días | 0,5 | no | no |
| Telégrafo | tecnología `telegrafo` | 1 día | 1,5 | no | no |
| Teléfono | `electricidad` | al instante | 0,4 | sí | no |
| Celular | `electronica` | al instante | 0,1 | sí | sí |

Los costos se multiplican por la dificultad y la inflación. Lo cobra el Estado: correo, telégrafo y telefonía van al tesoro.

La ventana del dispositivo tiene tres pestañas:

- **Contactos:** primero la familia, luego todos los que tienen relación mayor que 0, ordenados de mejor a peor. En cada uno se puede:
  - **Escribir** (carta o telegrama) o **Llamar**, según el dispositivo;
  - **Invitar a casa**;
  - **Chat**, con el celular;
  - abrir su **ficha**.
- **Buzón:** respuestas, cartas de presentación y propuestas, con los botones Aceptar y Rechazar. Las propuestas pueden ser una inversión, un pedido de trabajo o una presentación.
- **Chat:** solo con el celular. Frases rápidas («¿Cómo estás?», «¿Tomamos un café?», «Gracias por todo», «Tengo una idea de negocio»). Responde según su ánimo y su personalidad. Un chat por contacto y día.

**Cómo funcionan las demoras.** Una carta va primero a la bandeja de salida (`outbox`) y llega días después:

- **Carta normal:** cuando llega, sube la relación de +2 a +4. La respuesta vuelve al buzón con la misma demora.
- **Invitación:** cuando llega, la persona decide. Si acepta, viene a cenar ese día y se cobra la cena. Si no, la respuesta vuelve con demora.

**Al morir el jugador**, el heredero **no hereda las relaciones**: solo las familiares (`SocialSim.on_succession`).

- Cada familiar del nuevo jefe (cónyuge, hijos, hermanos y padres) conserva la relación que tenía, con un mínimo de 50.
- Se borran los contactos, recuerdos, chats, mensajes y envíos de quienes no son familia.
- Las sociedades siguen, porque son contratos de la empresa, pero la relación con cada socio vuelve a empezar.

## 4. Conversaciones

`SocialSim.start_conversation` y `SocialSim.choose`. Cada conversación tiene hasta 3 respuestas. Luego la persona se despide.

**Saludo inicial.** Depende de su **memoria**:

- si no se conocen, se presenta;
- si el último recuerdo es bueno, lo menciona («Todavía me acuerdo: le diste ánimos cuando estaba triste»);
- si es malo, te lo reprocha;
- además, comenta su ánimo («Ando un poco decaído(a)…»).

**Temas.** Hay 4 o 5 opciones cada vez, más «Despedirse»:

| Tema | A quién le gusta | Efecto si sale bien |
|---|---|---|
| Preguntar por su familia | sensible | +alegría, +confianza. Menciona a su cónyuge y sus hijos |
| Preguntarle cómo le va | — | Cuenta su trabajo. Si no tiene, aparecen «Ofrecerle trabajo» y «Darle ánimos» |
| Hablar de negocios | ambicioso | Da un dato de mercado real (el bien más caro respecto a su precio normal). Puede aparecer «Proponerle ser socio(a)» |
| Contar una anécdota graciosa | sociable | +alegría. A alguien muy orgulloso le puede ofender |
| Comentar las noticias del pueblo | sociable | Desempleo real y un dato de precios |
| Pedirle su consejo | orgulloso | Dato de mercado y un consejo |
| Darle ánimos (si está triste) | sensible | −tristeza. Te queda agradecido: te debe un favor |
| Preguntarle qué le molesta (si está enojado) | — | −enojo. Te cuenta el motivo real: deudas, enfermedad o un mal día |
| Pedirle un favor (relación de 40 o más) | — | Abre tres opciones: que te presente a alguien de confianza (un familiar o compañero de trabajo, con +15 de relación), un dato de mercado o un buen trabajador sin empleo (+8) |

**Probabilidad de éxito.** Va del 5 % al 95 %. Empieza en 0,55 y se ajusta:

- más por su rasgo, si el tema le gusta;
- más por la relación y por su alegría;
- menos si está enojado;
- −0,2 por cada vez que se habló del mismo tema en los últimos 30 días.

**Si sale bien:** sube la relación según el tema y su rasgo (a la mitad si el tema se repitió) y cambian sus emociones.

**Si sale mal:** baja la relación −1,5, o −4 si se ofendió, y sube su enojo.

**Memoria.** Cada persona recuerda las últimas 8 cosas (fecha, tema, bien o mal y una frase corta).

**Emociones.** Cada emoción tiene una **base**, que sale de su vida:

- felicidad;
- salud;
- necesidades cubiertas;
- desempleo;
- alquiler impago;
- cárcel;
- relación contigo.

A esa base se suma lo que dejaron tus interacciones. Esa parte se desvanece un 40 % cada mes.

**Personalidad.** Cuatro rasgos, de 0 a 1, fijos por persona: sociable, ambicioso, orgulloso y sensible.

**Favores.** Quien recibe trabajo, consuelo o un regalo te queda **debiendo un favor**, hasta un máximo de 3. Con un favor debido, te ayuda casi seguro (95 %). Si no te debe nada, pedirle un favor le cuesta confianza.

**Consecuencias en los negocios:**

- datos de mercado;
- contactos nuevos (presentados por alguien);
- trabajadores recomendados;
- socios que aportan capital o habilidades;
- propuestas que llegan por el buzón.

## 5. Guardado

Todo vive dentro de `GameState.player`, que ya se guarda (en binario y en JSON):

- `player["social"]`: `contacts`, `inbox`, `outbox`, `chats`, `next_msg`, `last_note`, `last_offer`, `convo`.
- `player["socios"]`: `list`, `next`, `log`.

Una **partida vieja** carga sin estas claves:

- `SocialSim.state` y `PartnersSim.state` las crean con valores por defecto;
- convierten a entero los ids que vuelven como decimales desde JSON;
- mientras el jugador no use la vida social, `daily` y `monthly` no hacen nada;
- `output_mult` devuelve 1 si no hay socios.

No cambia `SAVE_VERSION`.

## Archivos compartidos que se tocaron (una línea o un bloque pequeño)

- `business_sim.gd` (`expected_output`): `total *= PartnersSim.output_mult(gs, b)`.
- `population_sim.gd` (`_remove`): `PartnersSim.on_citizen_removed(gs, c, reason)`.
- `player_sim.gd`:
  - `daily` llama a `SocialSim.daily`;
  - `monthly` llama a `SocialSim.monthly` y `PartnersSim.monthly`;
  - `on_player_death` guarda las relaciones viejas y llama a `SocialSim.on_succession`.
- `hud.gd`:
  - crea `social_ui`;
  - la ficha llama a `social_ui.fill_sheet` y `social_ui.add_actions` (el botón «Conversar» rápido se reemplazó);
  - Esc cierra primero lo social;
  - `_all_modals` incluye los modales sociales.
- `building_panel.gd`: la pestaña «Socios» (`PartnersTab`).
- `citizen_agent.gd`: `var hold` detiene a la persona mientras conversa.
- `ui_kit.gd`: nueva categoría de aviso `social` (color, icono `chat` y etiqueta «Social»).
- `ui_icons.gd`: iconos `letter`, `telegraph`, `phone`, `mobile`, `chat` y `handshake`.

## Capturas

`docs/capturas/social/`: `ficha_persona`, `conversacion`, `dispositivo_carta_contactos`, `dispositivo_buzon`, `dispositivo_celular_chat`, `socios_desacuerdo`, `proponer_sociedad`, `ofrecer_trabajo`, `mi_personaje`.

```
xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 \
    tests/screenshot_social.tscn -- docs/capturas/social
```
