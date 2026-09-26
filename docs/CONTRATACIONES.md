# Contrataciones — vacantes, postulantes y personal

Pedido de Sebastián: "cuando abro una empresa y ya se construye, o algo para transporte, que tenga su categoría de
contrataciones o empleados y poder poner rechazar o contratar". Todo moderado; configuración en `data/contrataciones.json`.

## Para el jugador
- **Vacantes automáticas.** Al terminar la obra o una mejora de un negocio tuyo (incluidos caballeriza, depósito de
  camiones, hangar, empresa de buses, central de transporte y los servicios públicos) se publica su vacante y llega el
  aviso *"Tu negocio X está listo: tiene N vacantes de operario ($/día)"*. Cada vacante tiene puesto (**operario**,
  **conductor**, **cargador** o **profesional** si el nivel exige título), ocupados/total, **sueldo ofrecido** (sugerido
  por mercado, editable), **requisitos** (educación y profesión) y estado (Publicada / Pausada / Completa / auto).
  El gerente de sucursal de otro país se sigue contratando en *Mis países* (Fase 10).
- **Postulantes.** Mientras la vacante está publicada llegan postulantes con el tiempo: desempleados, jornaleros y
  empleados de otras empresas (NPC o gobierno) que buscan ganar al menos un 10 % más. Llegan **más y mejores** con
  más sueldo frente al mercado (≈ (sueldo/mercado)^2,5), mejor **reputación como empleador** y **publicidad** (una
  campaña activa +25 %, tu periódico o medio +20 %). Cada ficha trae retrato, edad, educación, profesión, habilidad,
  experiencia en el oficio (LaborSim), sueldo pedido, si cumple los requisitos y su antecedente ("desempleado",
  "fue despedido de X", "dejó su empleo en X", "trabaja en X: busca mejor sueldo").
- **Decidir.** *Contratar* (usa `BusinessSim.hire`; al sueldo publicado si alcanza lo que pide, si no al pedido; si
  trabaja en otra empresa renuncia allí). *Rechazar* (y "Rechazar a los que no cumplen"). *Contraofertar*: acepta si
  llega a lo que pide; entre el 90 y el 100 % quizá (más cerca, más probable); debajo rechaza y retira su postulación.
  Las postulaciones **vencen a los 14 días**.
- **Reputación (0–100, empieza en 50).** Contratar +0,4; rechazar −0,25 (a quien no cumple, 0); vencida −0,35;
  contraoferta rechazada −0,3. Cada mes se acerca un 15 % a un objetivo según tus sueldos frente a lo que piden tus
  empleados y su felicidad.
- **Auto-contratación por vacante:** contrata sola al mejor postulante que cumpla requisitos y pida hasta el sueldo
  máximo que fijes; al completarse, la vacante se pausa.
- **Transporte.** Cada vehículo necesita un conductor (empleado de su estación): sin él queda **detenido**, y el panel
  lo muestra en rojo ("Vehículos: 3 · 1 DETENIDOS por falta de conductor") y en la tarjeta *Vehículos detenidos*. Al
  comprar un vehículo (o un bus) se publica la vacante de conductor con aviso.

## Interfaz
- **Empresas → Contrataciones** (`scripts/ui/hiring_panel.gd`, ventana a pantalla completa), con el contador de
  postulantes nuevos en el botón de la categoría Empresas y en el menú ("Contrataciones (3)"):
  - *Vacantes*: tarjetas de resumen (puestos libres, postulantes, reputación, vehículos detenidos, publicidad) y una
    tarjeta por edificio agrupada en Negocios / Transporte (conductores y cargadores) / Servicios públicos: sueldo,
    publicar/pausar, auto-contratar hasta X y postulantes/día estimados.
  - *Postulantes*: fichas con filtros (empresa, solo quienes cumplen, orden) y Contratar / Rechazar / Contraofertar.
  - *Personal*: todos tus empleados por empresa con sueldo, experiencia, felicidad, riesgo de irse (alto/medio/bajo),
    − / + sueldo y Despedir.
- **Pestaña Empleados del edificio**: sección "Vacantes y postulantes" con la misma tarjeta y fichas.
- Capturas en `docs/capturas/contrataciones/` (`tests/screenshot_contrataciones.tscn`).

## Archivos
| Archivo | Contenido |
|---|---|
| `scripts/sim/hiring_sim.gd` | `HiringSim`: vacantes, llegadas, contratar/rechazar/contraoferta, auto-contratación, reputación, vehículos detenidos |
| `scripts/ui/hiring_panel.gd` | `HiringPanel`: ventana de 3 pestañas y `building_section()` para el edificio |
| `data/contrataciones.json` | Parámetros |
| `tests/test_contrataciones.gd/.tscn` | Pruebas |

## Estado y guardado
`GameState.labor["hiring"]` (se guarda con `labor` y es por país como el resto de `labor`): `vacancies` (por id de
edificio: `wage`, `published`, `auto`, `auto_max`, `opened`), `apps` (postulaciones: `cid`, `bid`, `asked`, `prev`,
`from`, `expires`, `status` nueva/vista/contratada/rechazada/retirada/vencida), `left` (quién fue despedido o
renunció), `reputation`, `next_id`. Partida vieja: se crea vacío; los empleados actuales no cambian y las vacantes de
negocios ya existentes quedan "Sin publicar" hasta que las publiques (no hay avisos en masa al cargar).

## Enganches en archivos compartidos (una línea cada uno)
- `game_state.gd`: `HiringSim.init_state` en `_init_expansions`, `HiringSim.daily` tras `LaborSim.daily`,
  `HiringSim.monthly` tras `LaborSim.monthly`.
- `construction_sim.gd` (`_complete`): `HiringSim.on_building_ready`.
- `logistics_sim.gd` (`buy_vehicle`) y `transit_sim.gd` (`buy_bus`): `HiringSim.on_vehicle_bought`.
- `business_sim.gd` (`fire`): `HiringSim.note_left` (antecedente de la ficha). `hire` no cambia: contratar directo sigue igual.
- `hud.gd`: entrada "Contrataciones" en `CATEGORIES` (Empresas), variable/creación de `hiring_panel`, casos en
  `_item_active` y `_open_item`, sufijo del contador en el menú.
- `building_panel.gd`: sección de vacantes y postulantes en `_employees_tab` y `_after_hiring`.

## Economía cerrada
HiringSim no mueve dinero: solo decide quién trabaja y a qué sueldo; los sueldos los paga `BusinessSim.produce` como
siempre. RNG propio (semilla + día + edificio): no altera la secuencia del resto. La prueba lo verifica.

## Pruebas
`godot --headless res://tests/test_contrataciones.tscn`: vacante y aviso al terminar la obra; llegan postulantes y más
con más sueldo; contador; contratar a un desempleado y a un empleado de otra empresa; rechazar; contraoferta aceptada y
rechazada; requisito de profesión y "rechazar a los que no cumplen"; auto-contratación (y con máximo bajo no contrata);
vacante de conductor al comprar una mula y vehículo detenido; cargadores de la central; postulaciones vencidas; dinero
conservado; guardado, carga y partida vieja; `BusinessSim.hire` directo y antecedente "fue despedido".
