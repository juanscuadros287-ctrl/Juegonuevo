# Sección E — Impuestos, efectivo y mercado negro

Pedido de Sebastián: impuesto a la venta además del impuesto a la ganancia; dos tipos de dinero
(efectivo y banco); ventas sin declarar solo con gente de confianza; mercado negro con investigación;
inspecciones, multas, cárcel y la opción de soborno. Todo llega a Notificaciones.

Código: `scripts/sim/money_sim.gd` (MoneySim). Datos: `data/mercado_negro.json` y
`data/technologies_negro.json`. Interfaz: `scripts/ui/cash_panel.gd` (botón **Efectivo y riesgo**).
Pruebas: `tests/test_efectivo.tscn`.

## 1. Impuesto a la venta

| Época | Nombre | Tasa base |
|---|---|---|
| Colonial | Alcabala | 2 % |
| Industrial | Impuesto a las ventas | 3 % |
| Moderna | IVA | 5 % (× 1,3 sobre la tasa del gobierno) |

- Cada gobierno tiene su tasa en `mercado_negro.json → sales_tax.by_gov` (virrey austero 2 %, mercantilista 3 %, reformista 2,5 %, liberal 2 %, conservador 3,5 %, social 5 %, verde 4 %). Si `government.json` define `sales_tax` para un gobierno, esa manda.
- Se **causa en cada venta declarada** de tus negocios (`BusinessSim.earn` con clave `ventas`) y en cada cobro de un contrato de venta declarado (`ContractSim._collect`). El dinero entra completo a tu banco; el impuesto queda pendiente (`b["iva_due"]` por negocio y `informal["iva_due"]` para contratos).
- Se **paga al tesoro cada mes** junto con los demás impuestos (`GovSim._collect_taxes` → `MoneySim.collect_sales_tax`). Aparece en el libro contable del negocio como `iva`, en `government.taxes_last["iva"]` y en Finanzas (pagado y causado).
- No causan IVA: alquileres, intereses, subsidios, venta de viviendas y las fundaciones sin fines de lucro.
- **Balance**: la tasa inicial es baja (2 % en la Colonia) y se descuenta de la ganancia del mes siguiente, así que el impuesto a la ganancia baja un poco. No se cambiaron las demás tasas. Las pruebas existentes pasan sin ajustes.

## 2. Efectivo y banco

- `gs.money` sigue siendo el **total** del jugador: nada de lo existente cambia.
- `gs.cash` es la parte en efectivo. `MoneySim.bank(gs) = gs.money − gs.cash`.
- API: `MoneySim.cash(gs)`, `bank(gs)`, `deposit(gs, monto)`, `withdraw(gs, monto)`, `pay_cash(gs, monto)`. Las acciones devuelven `""` si salen bien o el motivo si no.
- **Por el banco** (como siempre, con `gs.add_money`): gobierno, impuestos, créditos, empresas formales y contratos declarados.
- **En efectivo**: sueldos en negro, jornaleros y proveedores informales de los negocios ocultos, y sobornos.
- **Depósitos**: cada mes se puede depositar sin sospechas un margen libre (200 × precios) más el 25 % de las ventas legales del mes anterior (el "lavado" por tus negocios). Con *Contabilidad paralela* sube al 50 %. Lo que exceda suma riesgo (5 puntos por cada 1.000).
- Si el banco queda en rojo y tienes efectivo, el efectivo lo cubre al final del día. Eso cuenta como depósito.

## 3. Ventas no declaradas

- **Negocios**: casilla *No declarar* por negocio. Solo funciona con **personas de confianza**: familiares adultos y conocidos con relación ≥ 55 (se sube conversando). Cada una permite cobrar el 5 % de las ventas al público sin factura, hasta un máximo del 50 %. Esa parte entra en **efectivo**, no causa IVA y no aparece en el libro oficial, así que tampoco paga impuesto a la ganancia. Queda en `b["cash_ledger"]`.
- **Contratos de venta**: casilla *No declarar* si la contraparte lo acepta. Solo aceptan empresas NPC o pueblos con reputación ≥ 70 (de `ContractSim.reputation`). El gobierno y la importación nunca aceptan. El cobro entra en efectivo y sin IVA.
- **Sueldos en negro**: casilla por negocio. El sueldo se paga en efectivo con un 15 % de descuento y sin impuesto de nómina. Si falta efectivo, se paga normal por el banco. En el libro aparece como `salarios_negro`.
- Cada operación no declarada suma riesgo: 4 puntos por cada 1.000 vendidos y 5 por cada 1.000 en sueldos, a precios ajustados.

## 4. Mercado negro

Rama propia del árbol, **Economía informal**, en una fila nueva de `eras.json`, así que no se superpone con otras ramas:

| Tecnología | Época | Requiere | Habilita |
|---|---|---|---|
| Economía informal | 1 | Contabilidad | base de la rama |
| Cultivo ilícito | 1 | Economía informal, Herbolaria | Cultivo ilícito (cosecha ilícita) |
| Destilería clandestina | 1 | Economía informal | Destilería clandestina (aguardiente clandestino) |
| Rutas de contrabando | 1 | Economía informal, Navegación | Bodega de contrabando (mercancía de contrabando, importada sin arancel) |
| Contabilidad paralela | 2 | Economía informal, Banca moderna | más margen de depósito |
| Fábrica de contrabando | 2 | Rutas de contrabando, Fábricas | Fábrica de contrabando (tabaco de contrabando) |

**Negocios ocultos.** No aparecen en el mapa y se guardan en `informal["hidden"]`. Se montan desde el panel pagando en efectivo; el montaje se reparte entre ciudadanos.

- **Cada día**: producen y pagan jornaleros e insumos en efectivo, que se reparten entre los vecinos más pobres. Si falta efectivo, se paran y te llega un aviso. Los insumos de la bodega de contrabando se pagan afuera, como una importación.
- **Cada semana**: venden solo en efectivo, con **demanda propia** (`demand` unidades por adulto a la semana) y **precios altos**. Solo compran los vecinos con ahorros de sobra (30 días de necesidades), y gastan como mucho el 8 % de su excedente.
- **Riesgo**: cada día suman riesgo, más los de mayor escala.

## 5. Riesgo, inspección y consecuencias

- **Riesgo** de 0 a 100. Cada mes baja un 8 % y 3 puntos más.
- **Inspección mensual**: probabilidad = riesgo/100 × (0,35 + 0,5 × cobertura policial) × dureza del gobierno. La dureza va de 0,8 (virrey austero) a 1,3 (conservador). El tope es 70 %.
- **Hallazgo**, si hay algo que encontrar: probabilidad = 0,3 + 0,5 × riesgo/100 + 0,25 × policía. Si no encuentran nada, el riesgo baja un 30 %.
- **Caso abierto**: multa de (150 + 10 × riesgo) × precios, más el 30 % de lo no declarado el mes anterior. Tienes **10 días** para responder:
  - **Soborno**: probabilidad = 0,2 + 0,45 × (monto / multa) + 0,003 × corrupción de la familia − 0,2 × policía, dividida por la dureza del gobierno. Queda entre 5 % y 90 %.
    - **Aceptado**: el caso se archiva, el dinero va a un funcionario (`PoliticsSim._pay_official`), la corrupción de la familia sube 15 (con más riesgo de escándalo en `PoliticsSim`) y el riesgo baja.
    - **Rechazado**: no te cobran el soborno, pero la corrupción sube 5 y la multa sube × 1,5. El caso se resuelve en el acto.
  - **Aceptar la sanción**, o dejar vencer el plazo.
- **Sanción**:
  - Multa al tesoro, del banco primero.
  - Decomiso del 50 % del efectivo (100 % si es grave).
  - Cierre de todos los negocios ocultos y decomiso de su mercancía.
  - Tus negocios vuelven a declarar todo.
  - La reputación pública baja 8 puntos (16 si es grave).
- **Caso grave** (riesgo ≥ 70 o tercera falta): cárcel de 60 a 180 días para el jefe o para un familiar adulto que asume la culpa.
- **Notificaciones** en la categoría *jugador*: inspección, hallazgo, sanción y decomiso, soborno aceptado o rechazado, depósitos sospechosos y negocios parados. También quedan en el historial del panel.

## 6. Economía cerrada

| Movimiento | Destino |
|---|---|
| IVA, multas y decomisos de efectivo | Tesoro |
| Sobornos | Un funcionario del pueblo |
| Montaje, sueldos e insumos informales | Ciudadanos |
| Ventas ocultas | Salen del dinero de los vecinos y entran en tu efectivo |
| Insumos de la mercancía de contrabando | Afuera (como una importación) |
| Mercancía decomisada | Se destruye (no es dinero) |

## 7. Estado y guardado

- En `GameState`:
  - `cash`: 0 por defecto.
  - `informal`: `risk`, `log`, `hidden`, `next_hidden_id`, `iva_due`, `deposited_month`, `case`, `offenses`, `month`, `last_month`, `totals`, `trusted`, `rng_state`.
- En cada edificio: `iva_due`, `undeclared`, `black_wages` y `cash_ledger`.
- En cada contrato: `undeclared`.
- Las partidas antiguas cargan con valores por defecto (`MoneySim.init_state`, llamado en `_init_expansions`).
- MoneySim usa su propio generador aleatorio (`informal.rng_state`), así que no altera la secuencia de `gs.rng` del resto de la simulación.

## 8. Enganches en archivos compartidos

| Archivo | Cambio |
|---|---|
| `game_state.gd` | Variables `cash` e `informal`, limpieza, guardado y carga, `MoneySim.init_state`, `MoneySim.daily` y `MoneySim.monthly` |
| `business_sim.gd` | Claves `iva` y `salarios_negro` en `LEDGER_KEYS`; `earn` → `MoneySim.on_sale`; sueldos → `MoneySim.pay_wage_black` |
| `gov_sim.gd` | `_collect_taxes` → `MoneySim.collect_sales_tax` |
| `contract_sim.gd` | `_collect` → `MoneySim.on_contract_income` |
| `hud.gd` | Botón, variable y visibilidad del panel `cash` |
| `finance_panel.gd` | Dos líneas: efectivo/banco e IVA |
| `eras.json` | Rama `informal` |
