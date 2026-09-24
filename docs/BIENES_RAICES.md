# Bienes raíces y crédito bancario

Pedido de Sebastián: *"En el negocio de los bienes raíces, cuando haya rascacielos o apartamentos, el proyecto se
financia por partes. Hay que saber cuánto cuesta, en cuánto se arrienda al mes cada uno en caso de arrendar o, en caso
de vender, en cuánto se vende cada uno. Recuerda los bancos: crédito con la tasa que tengan y con el pago que se
necesite, mensual o como se haya firmado."*

Código: `scripts/sim/realestate_sim.gd` (unidades, precios, proyectos, preventa, mercado),
`scripts/sim/loan_contract.gd` (bancos, tipos de crédito, tablas, crédito constructor, hipotecas),
`scripts/ui/units_tab.gd`, `scripts/ui/realestate_panel.gd`, `scripts/ui/loan_dialog.gd`.
Datos: `data/realestate.json` (se lee con `GameData.extra("realestate")`). Pruebas: `tests/test_bienes_raices.tscn`.

## 1. Unidades por edificio

Los niveles multifamiliares de la vivienda (apartamentos, edificio residencial, rascacielos, y cualquier nivel con
capacidad > `family_capacity` = 10 personas) se dividen en **unidades** (`b["units"]`):

| Nivel | Pisos | Por piso | Unidades | Capacidad |
|---|---|---|---|---|
| 4 Edificio de apartamentos | 3 | familiar, familiar, estudio | 9 | 30 |
| 5 Edificio residencial | 8 | familiar, familiar, estudio | 24 | 80 |
| 6 Rascacielos | 25 | amplio, familiar | 50 | 250 |

Tipos: estudio (38 m², 2 personas), familiar (65 m², 4), amplio (95 m², 6). La suma de capacidades es la capacidad del
edificio. Cada unidad tiene `id`, código (`P3-02` = piso 3, unidad 2), piso, tipo, área, estado, inquilino o dueño,
familia (`household`), precio, renta y si está **en venta** / **en arriendo**.

Estados: `disponible` (tuya y vacía), `arrendada`, `vendida` (de un ciudadano), `preventa` (vendida sobre planos, sin
entregar), `embargada` (la remata un banco externo o el pueblo).

**Migración**: al cargar una partida vieja (o al terminar una mejora a apartamentos) se crean las unidades y cada
familia que ya vivía ahí recibe una unidad como inquilina con la renta sugerida. Si hubiera más familias que unidades,
las sobrantes siguen pagando la renta por persona de antes: nadie queda en la calle.

Un multifamiliar ya no se vende entero (`for_sale` del edificio queda en falso): se vende por unidades. Los dueños
viven gratis y pagan una **cuota de administración** mensual (su parte, por área, del mantenimiento del edificio), que
cobra el jugador como administrador.

## 2. Precios: valor, renta y pisos

```
valor del edificio = costo de reposición × (1 + margen del promotor 24%) × demanda del pueblo × época
precio de la unidad = valor × área × (1 + 1,5% × (piso − 1)) / Σ(área × factor de piso)
renta mensual       = precio × tasa de capitalización de la época / 12
```

- **Costo de reposición**: obra nueva de ese nivel y calidad con todos los materiales importados, a precios de hoy
  (dificultad × inflación). La **calidad** (normal/media/alta) entra por el `cost_mult` de la calidad.
- **Demanda** (0,90–1,15, suavizada cada mes): familias sin techo, hacinadas o en chozas del pueblo contra unidades
  vacías.
- **Época**: valor ×0,96 / ×1,00 / ×1,04 y tasa de capitalización 8,5% / 7% / 6% (colonial, industrial, moderna).
- **Pisos altos valen más** sin cambiar el total del edificio.
- Resultado en la colonia con demanda normal: **margen de venta ≈ 19%** y **arriendo ≈ 8,5% anual del valor**
  (industrial ≈ 24% y 7%; moderna ≈ 29% y 6%).
- Las unidades disponibles actualizan precio y renta cada mes; si el jugador fija un valor a mano queda fijo
  («Precios automáticos» lo devuelve al cálculo).

## 3. Ficha del proyecto (factibilidad)

`RealEstateSim.feasibility(gs, nivel, calidad, es_mejora, edificio)` usa `ConstructionSim.cost_for` y da: costo total,
costo por unidad, unidades y pisos, días y trabajadores, costo de cada etapa, renta por unidad (media, mínima, máxima)
y total, precio por unidad y total, **margen de venta**, **rentabilidad del arriendo** (bruta sobre costo, sobre valor
y neta de mantenimiento e impuesto predial) y **meses para recuperar la inversión** arrendando.

Se ve en: menú **Construir** (sección «Proyectos inmobiliarios»), panel **Bienes raíces → Nuevo proyecto**, pestaña
**Unidades** del edificio (antes de mejorar a un nivel multifamiliar y durante/después de la obra, con los precios
reales fijados).

## 4. Financiación por partes

### Pago por etapas
Obra nueva (`start_project`) o mejora (`start_project_upgrade`) de un multifamiliar: el costo se divide en
**cimentación 20% → estructura 45% → acabados 35%** (del trabajo y del dinero). Cada etapa se cobra cuando la obra
llega a ella (`RealEstateSim.daily`, antes de `ConstructionSim.daily`). Si no hay dinero, la obra **se pausa**:
lo avanzado se conserva, no se trabaja lo que no está pagado y los jornaleros quedan libres. Al conseguir el dinero
se reanuda sola. La mejora normal («Mejorar», pago total al iniciar) sigue existiendo.

### Preventa sobre planos
Durante la obra, las unidades marcadas **En venta** pueden separarlas las familias: pagan una **cuota inicial del 10%**
hoy, **cuotas mensuales** que suman otro 20% durante la obra y el **saldo al entregar**, con ahorros o con
**hipoteca**. El dinero sale del ciudadano y entra al jugador (economía cerrada). Si el comprador deja de pagar 3
cuotas, o no consigue el saldo al entregar, la preventa se rescinde y se le devuelve lo pagado. Si el jugador
**cancela el proyecto**, se devuelve todo a los compradores; una obra nueva se demuele y una mejora vuelve al nivel
anterior (lo pagado en etapas se pierde y el crédito sigue debiéndose).

### Crédito constructor
Al iniciar el proyecto se elige banco y % financiado (hasta 60%). El banco pone su % de **cada etapa** cuando se paga
(desembolsos); los **intereses mensuales se cobran solo sobre lo desembolsado**. Cada venta de unidad abona el 70% de
su precio al crédito; el saldo vence 12 meses después de la obra estimada. Al terminar la obra el cupo se cierra.

## 5. Crédito bancario completo

`LoanContract` extiende `BankSim` sin romper su API (`payment`, `request_player_loan`, `player_rate`, `credit_limit`
siguen iguales; los préstamos viejos sin `type` se cobran igual que antes).

- **Bancos**: el externo (Banco del Reino), bancos NPC de `data/realestate.json` (Banco Comercial −0,5 pts y cupo 80%,
  Caja Cooperativa +1,5 pts y cupo 120%, Banco Hipotecario −1,5 pts desde la Revolución industrial) y **tus bancos**:
  solo una fundación puede prestarte desde su reserva (un banco S.A.S. no presta a su dueño); lo pagado vuelve a la
  reserva y los intereses son ingreso del banco.
- **Tasa** = tasa base de la dificultad (4–14%) + ajuste de la época (+2 / 0 / −1 pts) + margen del banco + riesgo del
  cliente (apalancamiento y mora, de `BankSim.player_rate`).
- **Tipos de pago**: cuota fija (**francés**, igual a `BankSim.payment()`), abono constante a capital (**alemán**),
  **solo intereses y capital al final** (bullet) y **con período de gracia** de N meses (solo intereses y luego cuota
  fija por el resto del plazo).
- **Contrato**: Finanzas → «Pedir crédito…» muestra tasa, primera cuota, cuota máxima, intereses totales y la **tabla
  de amortización** antes de **Firmar**. Luego cada mes `BankSim.monthly` cobra lo firmado (`LoanContract.due`).
- **Pagos anticipados**: «Abonar» reduce el capital y recalcula la cuota con el plazo restante. «Tabla» muestra la
  tabla restante.
- **Mora y embargo**: igual que antes (recargo, 3 cuotas impagas → embargo de propiedades).

### Hipotecas para ciudadanos
Cuando una familia compra una unidad y no le alcanza, pide hipoteca: cuota inicial ≥ 20%, cuota ≤ 35% del ingreso
familiar, plazo 120/180/240 meses según la época. Primero a **tus bancos** (con «Otorgar hipotecas» activo, cupo por
empleados y capital) con tu **tasa hipotecaria** (panel Bienes raíces → Hipotecas): tu banco pone el dinero y gana los
intereses. Si no, la otorga el **banco externo** (tasa base + época + 3 pts; el dinero viene de afuera y las cuotas
salen del pueblo, como el crédito externo del jugador). Si el deudor no paga 3 cuotas, la unidad se **embarga**: vuelve
a ti si el acreedor es tu banco; si es externo, el banco la remata al 85% y el dinero sale del pueblo. Si el dueño
muere, su familia hereda la unidad; sin herederos, el pueblo la remata y el dinero va al tesoro.

## 6. Interfaz

- **Bienes raíces** (menú lateral): Resumen (demanda, unidades por estado, arriendos, ventas, preventas, cuotas de
  administración, hipotecas, desalojos por mes/total), Proyectos (cada edificio con su etapa, unidades y dinero),
  Nuevo proyecto (nivel, calidad, ficha, crédito constructor → colocar en el mapa) e Hipotecas (tus bancos).
- **Panel de edificio → Unidades**: estado del proyecto (etapas, pausa, crédito, preventas, cancelar), ficha y tabla
  de unidades con precio, renta, «Venta» y «Arr.» por unidad y botones para todas.
- **Finanzas**: «Pedir crédito…» (banco, tipo, plazo, gracia, tabla, Firmar) y la lista de créditos con banco, tipo,
  saldo, cuota, abono anticipado y tabla.

## 7. Guardado

`GameState.realestate` (demanda y contadores) se guarda en `to_dict/load_dict`; las unidades y el proyecto viven en
el diccionario del edificio y los contratos en `loans` (campos nuevos `type`, `grace`, `limit`, `disbursed`,
`maturity_day`, `unit_ref`). Todo tiene valores por defecto: las partidas viejas cargan y migran solas.

## 8. Ganchos en archivos compartidos

| Archivo | Cambio |
|---|---|
| `game_state.gd` | var `realestate`, guardado, `RealEstateSim.init_state`, `daily` antes de las obras y `monthly` antes de `monthly_housing` |
| `construction_sim.gd` | obras con `paused` no avanzan; `_complete` llama `RealEstateSim.on_building_ready` |
| `population_sim.gd` | `_pay_housing` cobra la renta por unidad si el edificio tiene unidades |
| `market_sim.gd` | el mercado de vivienda viejo ignora los multifamiliares (los maneja RealEstateSim) |
| `bank_sim.gd` | `monthly` usa `LoanContract.due`; no borra un crédito constructor abierto; pagos a tu fundación; `_default` avisa a RealEstateSim |
| `economy_sim.gd` | valor de un multifamiliar = unidades aún tuyas; `loans_granted` solo cuenta la cartera de tus bancos |
| `event_bus.gd`, `world.gd` | señal y modo de colocación de un proyecto multifamiliar |
| `hud.gd`, `building_panel.gd`, `build_menu.gd`, `finance_panel.gd` | botón/panel, pestaña, sección de proyectos y crédito |

## Balance observado

Un pueblo sin empleos (prueba de 10 años sin negocios) arrienda unidades mientras las familias tienen ahorros y luego
las desaloja por no pagar: el negocio inmobiliario depende de que haya salarios. Con 10 años de simulación la demanda se
mantiene en su rango y la obra con crédito constructor termina sin colapso.
