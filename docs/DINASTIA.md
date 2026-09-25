# Dinastía y poder (sección C de PENDIENTES)

Pedido de Sebastián: educación de herederos con talentos, política (campañas, cargos, lobby y escándalos)
y matrimonio con unión de fortunas y orden de herederos elegido por el jugador. Todo moderado y dentro de
la economía cerrada: el dinero solo cambia de manos.

Archivos:

| Archivo | Qué hace |
|---|---|
| `scripts/sim/heirs_sim.gd` (`HeirsSim`) | Talentos, educación pagada, orden de herederos y bonos del jefe de familia |
| `scripts/sim/politics_sim.gd` (`PoliticsSim`) | Facciones y campañas, cargos públicos, lobby, corrupción y escándalos |
| `scripts/sim/marriage_sim.gd` (`MarriageSim`) | Ficha de patrimonio, propuestas, unión de fortunas y matrimonios estratégicos |
| `data/dynasty.json` | Parámetros: `talents`, `education`, `marriage`, `politics` |
| `scripts/ui/player_panel.gd` | Panel "Mi Personaje": familia, herederos, matrimonio y política |
| `tests/test_dinastia.gd` | Pruebas de la sección |

## Estado guardado (con valores por defecto)

Todo vive dentro de `GameState.player`, que ya se guarda y se carga. Una partida antigua carga sin estos
datos y se completa sola:

- `player["familia"]`: `talents` {id: {talento: 0-100}}, `edu` {id: {plan, focus, months}}, `heir_order` [ids].
- `player["politica"]`: `offices`, `campaigns`, `lobbies`, `factions`, `corruption`, `scandals`, `log`.
- `player["marriages_log"]`: registro de lo que aportó cada cónyuge.
- La reputación de la familia es la que ya existía: `government["reputation"]`.

## 9. Educación de herederos y talentos

- Hay cinco talentos: **negocios, política, ciencia, artes y oficio** (de 0 a 100).
- **Talento innato:** 5-35, fijo para cada persona (sale de su semilla).
- **Personas que no son de tu familia:** su talento se calcula con el innato, sus estudios y sus habilidades.
- **Tu familia:** los talentos se guardan la primera vez. En los hijos pesa un poco el talento de los padres.
- **Planes de educación:** cada hijo o hermano tiene un plan y un talento a reforzar. Cuota mensual × dificultad × inflación.

| Plan | Edad | Cuota | Mejora al mes (talento elegido / los demás) | Adónde va el dinero |
|---|---|---|---|---|
| Tutor privado | 4-17 | 12 | +1.4 / +0.2 | al adulto más educado del pueblo que no sea de tu familia |
| Colegio | 6-17 | 8 | +1.1 / +0.5 | al tesoro |
| Universidad | 16-30, con escuela | 20 | +1.9 / +0.4 | al tesoro |
| Carrera en el extranjero | 17-30, desde la época industrial | 55 | +3.1 / +0.7 | sale del pueblo, como una importación |

- Los hijos que ya estudian en un colegio del pueblo (EducationSim) ganan +0.3 al mes sin costo extra.
- Si el hijo ya no tiene la edad del plan, el plan termina y llega un aviso.
- **Bonos del jefe de familia:** el personaje actual los da según sus talentos. Empiezan en 40 y llegan al máximo en 100:
  - negocios: hasta −6 % de mantenimiento de tus negocios (en `BusinessSim.produce`);
  - oficio: hasta −3 % de mantenimiento;
  - política: hasta −8 % del impuesto a las ganancias (en `GovSim._collect_taxes`);
  - ciencia: hasta +10 % de investigación (en `TechSim.mult("research")`);
  - artes: hasta +1 punto de reputación al mes.
- Por eso importa a quién educas: cuando un heredero toma el control, los bonos pasan a ser los suyos. El aviso de sucesión dice cuáles quedan.

## 10. Política

- **Facciones (virreinato):** puedes apoyar a una facción de la época. Cuando llega el cambio de virrey,
  la facción más apoyada gana con probabilidad `apoyo / (apoyo + 600 × dificultad)`. Si no gana, el
  gobierno se elige al azar como antes. El apoyo se reinicia en cada cambio.
- **Campañas (elecciones):** se usa `GovSim.donate`, igual que antes. Cambio: el aporte ya no desaparece,
  se reparte entre los adultos más pobres, que son los trabajadores de campaña.
- **Cargos:**
  - Puede postularse el jugador o un familiar adulto (21 años o más) con talento político suficiente.
  - La campaña se paga, se reparte entre ciudadanos y se resuelve en unos meses.
  - La probabilidad de ganar depende del talento, la reputación, el gasto extra y la política del jefe. Va del 10 % al 85 %.

| Cargo | Época | Campaña | Talento mínimo | Sueldo al mes (tesoro) | Rebaja de impuesto | Influencia en lobby |
|---|---|---|---|---|---|---|
| Concejal | colonial | 150 | 30 | 45 | 4 % | +10 % |
| Alcalde | industrial | 450 | 45 | 90 | 8 % | +20 % |
| Gobernador | moderna | 1200 | 60 | 160 | 12 % | +30 % |

  - **Obligaciones:** quien asume deja su empleo. El período dura 4 años. Pierde el cargo si la reputación de la familia baja de 20, si muere o si va a la cárcel.
  - Solo un miembro de la familia puede tener cada cargo.
- **Lobby:**
  - **Bajar el impuesto a un sector:** solo sectores donde tienes negocios. Rebaja el impuesto a las ganancias de ese sector en un 25 % relativo durante 3 años.
  - **Licencia ambiental:** 3 años sin multas ambientales.
  - **Lobby legal:** 45 % de éxito, más la influencia de los cargos. El dinero va a asesores (ciudadanos).
  - **Soborno:** cuesta el 60 % del precio legal y tiene 75 % de éxito. El dinero va a un funcionario (un empleado público o el adulto más rico que no sea de tu familia). Suma 22 puntos de corrupción.
  - La rebaja total del impuesto a las ganancias tiene un tope del 35 %. Suma el talento, los cargos y el lobby.
- **Escándalo:**
  - Riesgo mensual = corrupción × 0,08 %. Con un soborno reciente es cerca del 1,8 % al mes.
  - La corrupción baja 1,5 puntos al mes.
  - Si hay escándalo:
    - multa (200 + 8 × corrupción) × dificultad, que va al tesoro;
    - −15 de reputación;
    - todos los cargos de la familia se pierden;
    - se anula todo lo conseguido con sobornos;
    - la corrupción baja al 30 %.
  - Siempre llega a las notificaciones (categoría "jugador").

## 11. Matrimonio y herencia

- **Orden de herederos:** solo el jugador lo decide. Es una lista en el panel con botones ▲, ▼ y ✕, más
  "Añadir a la lista". Puede incluir hijos (también adoptados), el cónyuge y los hermanos.
  - Al morir, hereda el primero **vivo** de la lista.
  - Si la lista está vacía o nadie de ella vive, se usa la regla anterior: el heredero designado o el hijo mayor.
  - Después de la sucesión, la lista conserva a quienes siguen siendo hijos, cónyuge o hermanos del nuevo jefe.
- **Ficha antes de proponer:** muestra dinero, casas, empresas NPC, patrimonio total, fortuna de su familia,
  estatus (el suyo y el tuyo), talentos y familia. Aparece en el panel y en la ficha de la persona (HUD).
- **Propuesta del jugador:**
  - Hace falta una relación mínima de 20.
  - La probabilidad sale de la relación, la diferencia de fortuna, la diferencia de estatus y cuánto te conocen sus padres. Va del 3 % al 95 %.
  - Si rechaza, baja la relación y llega un aviso.
- **Unión de fortunas:** al casarte, el dinero del cónyuge, sus casas y sus empresas NPC pasan a la familia.
  - La caja de sus empresas primero va al cónyuge y después se suma al dinero familiar.
  - No se crea dinero.
  - No se transfieren: sus deudas personales ni las unidades de edificios de bienes raíces.
- **Matrimonios estratégicos:** se usan con hijos o hermanos adultos y solteros.
  - Los candidatos del pueblo se ordenan por la fortuna de su familia.
  - La otra familia acepta o rechaza según estatus, fortuna, talentos de tu familiar y relación.
  - **Pedir dote:** −15 % de probabilidad. La dote es el 12 % de los ahorros de su familia y sale del bolsillo de sus miembros.
  - **Unir empresas:** −25 % de probabilidad. Las empresas NPC de su familia pasan a la tuya. Su caja queda con ellos.
- **Pareja de otro pueblo:**
  - Requiere una conexión comercial.
  - La boda cuesta 150; el dinero se reparte entre ciudadanos.
  - Si aceptan, la pareja llega al pueblo como un inmigrante.

## Archivos compartidos que se tocaron (una línea o un bloque pequeño)

- `business_sim.gd`: el descuento de mantenimiento suma `HeirsSim.upkeep_discount`.
- `gov_sim.gd`:
  - `PoliticsSim.profit_tax_mult` en el impuesto a las ganancias;
  - la licencia ambiental evita la multa;
  - la facción apoyada en el cambio de virrey;
  - `donate` reparte el dinero entre ciudadanos.
- `tech_sim.gd`: `mult("research")` multiplica por `HeirsSim.research_mult`.
- `player_sim.gd`:
  - `propose` pasa a `MarriageSim`;
  - `on_player_death` usa el orden de herederos.
- `dynasty_sim.gd`: `monthly` llama a `HeirsSim` y `PoliticsSim`, y `has_heir` tiene en cuenta la lista.
- `hud.gd`: la ficha de la persona muestra sus talentos y, si puedes cortejarla, su patrimonio y la probabilidad de que acepte.
