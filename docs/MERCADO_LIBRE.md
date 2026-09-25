# Libre mercado: empresarios NPC, contratos, pueblos que crecen y plan de gobierno

Pedido de Sebastián: no ser el único empresario. En tu pueblo y en los vecinos hay ciudadanos con sus
propios negocios, que se heredan en la familia. El mercado es "por parte y parte": tú cubres lo que
produces y los demás cubren el resto. Los clientes te piden lo que quieren con un contrato que
aceptas o rechazas, y tú también puedes ofrecerles. El gobierno ejecuta su propio plan de obras.

Configuración: `data/mercado.json`. Obras del gobierno: `data/buildings_gobierno.json`.
Estado: `GameState.market` (se guarda; las partidas viejas lo crean al cargar, `SAVE_VERSION` 7).

## Archivos

| Archivo | Qué hace |
|---|---|
| `scripts/sim/free_market_sim.gd` | Orquesta los sistemas (ganchos en `GameState.simulate_day`), estado, RNG propio y `money_snapshot` |
| `scripts/sim/npc_business_sim.gd` | Empresas NPC del pueblo del jugador |
| `scripts/sim/town_economy_sim.gd` | Crecimiento y comercio de los pueblos vecinos |
| `scripts/sim/contract_sim.gd` | Contratos de compra y venta, únicos o recurrentes a precio fijo |
| `scripts/sim/gov_plans_sim.gd` | Plan de gobierno (obras propias o licitadas) |
| `scripts/ui/contracts_panel.gd` | Botón **Contratos** del HUD |

Ganchos mínimos en archivos compartidos:
- `BusinessSim.earn/pay`: si el edificio es una empresa NPC o una obra propia del gobierno, el dinero va
  a su caja o al tesoro (`NpcBusinessSim.book`). Nunca toca el dinero del jugador.
- `MarketSim.begin_day`: las empresas NPC también venden a los ciudadanos y compiten con las tuyas
  (mismo orden por calidad y precio).
- `EventsSim.daily`: la cobertura de salud y policía suma la de las obras del gobierno.
- `ConstructionSim.daily`: tu constructora solo trabaja en tus obras y en las públicas que ganaste.
- `StatsSim.goods_table`: el aviso "Nadie vende X" cuenta también a los vendedores NPC.
- `EnergySim.demand_of`: si una empresa NPC consume electricidad, la paga de su caja. Su acometida la paga el dueño.
- `world.gd`: verificación de terreno para colocar obras NPC (agua y pendiente) y bandera azul en las empresas NPC.

## Empresarios NPC (tu pueblo)

- **Cuándo abren:** una vez al mes, desde el mes 6 y con pocas aperturas por año según la época
  (1, 2 y 3). Nunca hay más de un negocio NPC por cada 22 habitantes.
- **Qué abren:** lo que más falta según el mes anterior. Cuenta lo importado, parte del
  autoabastecimiento y el faltante. Además se estiman las ventas con quienes pueden pagar: si no
  alcanzan un mínimo, no abren. Solo abren tipos permitidos por la época, la tecnología y el mapa
  (tienda, panadería, taberna, aguatero, leñador, granja y pescadería).
- **Quién abre:**
  - Un adulto de 22 a 60 años con habilidad en el oficio.
  - El capital sale de sus ahorros y de los de su familia (cónyuge, hijos adultos y padres).
  - También pueden entrar hasta 3 **socios** vecinos, que cobran parte de los dividendos.
  - Si todavía falta dinero, un **préstamo de TU banco**, si tienes uno que preste: el dinero sale de tu caja y vuelve con las cuotas.
  - La familia del jugador no participa.
- **Obra real:**
  - Busca un lugar libre en terreno desbloqueado cerca de la plaza (`placement_block_reason`, más agua y pendiente si hay mundo 3D).
  - La obra tarda lo normal, con jornaleros pagados de la caja de la empresa.
  - Los materiales se compran fuera: ese dinero sale del pueblo.
- **Operación:**
  - El dueño atiende sin sueldo y contrata solo cuando vende casi todo y la ganancia alcanza para otro sueldo.
  - Paga sueldos, mantenimiento, insumos e impuestos de renta, propiedad y nómina, que van al tesoro.
  - Insumos y mantenimiento se compran a **proveedores del pueblo** (vecinos sin empleo que cultivan, recogen o reparan): ese dinero no sale del pueblo.
  - El precio es automático: precio de mercado más un margen propio.
  - Reparte dividendos al dueño y a los socios.
  - Si la caja no alcanza, pone el dueño. Si no hay sueldo, la gente renuncia.
- **Quiebra:** caja en rojo 3 meses, o 6 meses de pérdidas con la caja casi vacía. Cierra, queda en
  venta y lo puede comprar otro ciudadano (si hay clientes) o el jugador. A los 6 meses sin
  comprador se demuele.
- **Herencia:**
  - Al morir el dueño, hereda el hijo o la hija adulta mayor. Si no hay, el cónyuge, luego un hijo menor, un nieto o un hermano.
  - El historial de dueños se ve en el panel del edificio.
  - Si el heredero es el jugador, el negocio pasa a ser suyo.
  - Sin herederos, la caja va al tesoro (bienes vacantes) y el **Estado** vende la empresa.
- **Comprarla:**
  - En el panel del edificio, **Ofrecer comprar** con el monto que quieras.
  - El dueño responde en 2 a 5 días. Acepta si cubre lo que pide (valor × 1,15–1,45); si llega al 85 %, a veces.
  - El dinero va al dueño, que además se lleva la caja. Respeta el límite de negocios de tu oficina.
  - Si la vende el Estado o está en quiebra, se compra al precio publicado.

## Pueblos vecinos que crecen

Cada pueblo de la Fase 7 tiene ahora:
- `cash`: su caja, con la que paga tus contratos.
- `sectors`: empresarios resumidos, es decir, cuántos negocios hay por bien.
- `gov_aid`: ayuda de su gobierno, de 0 a 1.

Cada mes:
- **Crece** según la época (0,8 %, 1,8 % y 2,2 % anual) más la ayuda de su gobierno (hasta +1 %).
  Su demanda y su oferta escalan con la población.
- Abre negocios en sus sectores y aumenta su oferta.
- A veces sus empresarios empiezan a producir algo que antes importaban. Desde entonces lo venden y
  lo piden menos.
- **Comercia con los otros pueblos** de forma resumida: quien produce le vende a quien lo pide. Su
  dinero cambia de manos (suma cero) y parte de esa demanda queda cubierta, así que tu precio allá baja un poco.

## Contratos de compra y venta (botón «Contratos»)

Pedido de Sebastián: "que me puedan pedir, o yo pedir, contrato recurrente: comprar automáticamente X
cantidad por X tiempo, cada X tiempo, y lo mismo para venta, algo 100 % fijo".

### Modelo general

Cada contrato (`gs.market["contracts"]`) tiene:

| Campo | Qué es |
|---|---|
| `dir` | `"venta"` (el jugador vende) o `"compra"` (el jugador compra) |
| `client` | contraparte: `town:<id>` (pueblo con ruta), `npc:<id>` (empresa NPC), `gov` (gobierno) o `import` (importación externa, solo compra) |
| `good`, `qty`, `unit_price` | bien, cantidad por entrega y precio unitario **fijo** (no cambia aunque cambie el mercado) |
| `period` | frecuencia en días: 7, 15, 30, 60, 90 o personalizada |
| `installments` | número de entregas (o se calcula desde una fecha de fin con `installments_until`) |
| `start_day`, `end_day`, `next_due` | primera entrega, última entrega y próxima entrega |
| `penalty` / `cp_penalty` | penalidad del jugador / de la contraparte por incumplir una entrega (20 % del valor de la entrega) |
| `auto` | entrega automática sí o no |
| `wid` | almacén destino de una compra (bodega de la plaza por defecto) |
| `done`, `failed`, `cp_failed` | entregas hechas, incumplidas por el jugador y por la contraparte |
| `paid`, `owed`, `debt` | lo pagado, lo que te debe el comprador y lo que tú debes al proveedor |

**Migración:** al cargar (`FreeMarketSim.init_state` → `ContractSim.migrate`), los contratos, solicitudes
y ofertas sin `dir` pasan a venta con frecuencia 30 (las antiguas cuotas mensuales), con fechas de inicio y fin
calculadas, `cp_penalty` = penalidad y almacén = bodega de la plaza. Es idempotente (`"v": 2`).

### Ventas (el jugador vende)

- **Solicitudes entrantes:**
  - Llegan **solo para bienes que produce alguno de tus negocios**.
  - Clientes:
    - Pueblos con ruta comercial: piden lo que usan y no producen, y prefieren lo que demandan.
    - Empresas NPC: insumos o mercancía según `input_wants`.
    - El gobierno: materiales de sus obras.
  - Las recurrentes vienen con frecuencia de 15, 30 o 60 días (`request_periods`), con la misma duración total aproximada que antes.
  - Llega una notificación y queda en la **Bandeja** con **Aceptar / Rechazar / Contraofertar**. Vence a los 15 días.
  - Rechazar baja un poco la reputación. El cliente compra a otro proveedor: otro pueblo, importación u otro NPC.
- **Entrega:**
  - Sale de la bodega de la plaza (la salida del pueblo), luego de los otros almacenes y luego del inventario de tus negocios.
  - A un pueblo viaja por la ruta comercial: pagas el flete de `TradeSim` y el pueblo paga **desde su caja al llegar**.
  - En el pueblo, el pago es inmediato desde la caja de la empresa NPC o del tesoro.
  - Si el comprador no tiene fondos, queda debiendo y paga cada mes (ese es su incumplimiento).
  - Automática: entrega desde 3 días antes de la fecha si hay existencias. Manual: botón **Entregar ahora**
    desde media frecuencia antes (máximo 15 días).
- **Incumplimiento:** pagas la penalidad al cliente y tu reputación baja 12 puntos. Un contrato
  único queda incumplido; uno recurrente se cancela a la segunda falla.

### Compras (el jugador compra) — nuevo

- **Proveedores** (`supplier_keys`):
  - empresas NPC que producen ese bien, con su **stock real** (`inventory`);
  - pueblos vecinos con ruta que lo producen (`TradeSim.sells_good`); su stock es `supply − scar`;
  - la **importación externa** como último recurso: siempre tiene, pero cuesta el precio de mercado × 1,4 × arancel y tarda 7 días.
- **Cada entrega** (automática el día acordado; manual con **Recibir ahora**, a más tardar 3 días después):
  - la empresa NPC descuenta su stock y el bien entra al almacén elegido con `WarehouseSim.add_to` (respeta la capacidad);
  - desde otro pueblo llega tras los días de viaje de la ruta; el flete lo pagas al despachar;
  - **se paga al recibir**: a la caja de la empresa NPC (como venta suya), a la caja del pueblo o afuera (importación; el arancel queda en el tesoro).
    Si al llegar no te alcanza, queda como deuda y se paga cada mes.
- **Proveedor sin stock:** incumple. Te paga su penalidad (de su caja; el dueño pone si falta) y baja su **fiabilidad** (0–100, empieza en 80).
  A la segunda falla el contrato termina por culpa del proveedor.
- **Jugador sin dinero o sin espacio** (el espacio cuenta lo que ya viene en camino): el incumplidor eres tú. Pagas la penalidad al proveedor
  y baja tu reputación, igual que en una venta.

### Quién propone

- **El jugador propone** (pestaña **Proponer**): dirección, contraparte, bien, cantidad, precio (con la referencia de mercado),
  frecuencia, número de entregas, primera entrega, automática y, si es compra, el almacén destino. Muestra el estimado del total.
  La contraparte responde en 2–5 días (`evaluate_offer`) según:
  - su necesidad (venta) o su capacidad de producir esa cantidad por período (compra);
  - el precio frente a la referencia del mercado;
  - la duración: por un compromiso largo pide un descuento de 1 % por entrega extra (máximo 10 %);
  - tu reputación con ella;
  - su caja (si puede pagar dos entregas) o la tuya (si puedes pagar una); un proveedor NPC con la caja apretada vende 5 % más barato.

  Si el precio no le sirve pero está a menos de 15 % de su límite, responde con una **contraoferta** de precio: la aceptas o la rechazas
  en la Bandeja (vence a los 15 días).
- **Los NPC proponen:**
  - de venta, solo de bienes que produces (arriba);
  - de compra: una vez al mes, un proveedor (empresa NPC o pueblo con ruta) te ofrece venderte algo que tus negocios consumen
    (insumos de recetas o la mercadería de tus comercios) cuando tus existencias no alcanzan para un mes (`player_needs`).
  - Todas llegan a la Bandeja con **Aceptar / Rechazar / Contraofertar**. Contraofertar la convierte en una propuesta tuya con
    otro precio que la contraparte responde en unos días.
- **Cancelar** un contrato activo: pagas una penalidad a la contraparte y baja un poco tu reputación.

### Interfaz (`contracts_panel.gd`)

Pestañas **Bandeja** (solicitudes, ofertas de proveedores y contraofertas), **Proponer** (formulario), **Activos** (próxima
entrega, entregas hechas/total, cumplimiento, deuda, **Entregar/Recibir ahora**, **Automática** y **Cancelar** con la penalidad)
e **Historial** (contratos cerrados y quién incumplió, propuestas, reputación por cliente y fiabilidad de proveedores).

Configuración en `data/mercado.json → contracts` (`request_periods`, `duration_discount`, `counter_ratio`, `npc_supply_wholesale`,
`import_premium`, `import_days`, `reliability_*`, `supply_*`, `shop_need_month`).

- **Reputación por cliente (0–100):** sube 4 puntos al cumplir. Cambia el precio que te ofrecen
  (×0,9 a ×1,1) y cada cuánto te piden (×0,2 a ×2).

## Plan de gobierno

- Cada trimestre el gobierno mide:
  - felicidad baja → **parque**;
  - poca cobertura de salud → **centro de salud**;
  - crimen → **comisaría**;
  - familias sin hogar → **vivienda social**;
  - niños sin escuela → **escuela pública**.
- Elige la necesidad más grave que puede pagar sin bajar de la reserva mínima del tesoro. Una obra a la vez.
- **Licita** la obra al jugador (35 %) con las licitaciones de `GovSim`. Si pierde la licitación o
  vence, la construye él mismo.
- Si tú produces los materiales, **te los pide por contrato**. Si no llegan, los importa.
- Las obras propias quedan con owner "gobierno" y contractor "gobierno". Los jornales salen del
  tesoro, igual que el personal (salario pedido) y el mantenimiento mensual.
- **Presupuesto de personal:** el gobierno solo contrata lo que pagan los impuestos del mes más 1/36 de lo que
  el tesoro tiene sobre su reserva. Si no alcanza, recorta personal en vez de vaciar el tesoro.
- Efectos:
  - salud y policía suman cobertura;
  - el parque da felicidad (con `GovSim.project_happiness`);
  - la escuela da educación básica tras 4 años;
  - la vivienda social aloja gratis a familias sin hogar.
- Se ven en **Gobierno → Plan de gobierno**, con su estado y las necesidades medidas.

## Economía cerrada

- Ningún sistema crea dinero. Todo pago tiene origen y destino: caja NPC, ciudadano, jugador, tesoro o caja de pueblo.
- Lo único que sale del pueblo son las compras afuera: los materiales de las obras, la electricidad de la red regional, el flete y las compras por contrato a la importación externa (menos el arancel, que va al tesoro). Las compras a empresas NPC y a pueblos vecinos van a sus cajas.
- Las exportaciones a pueblos vecinos traen dinero de sus cajas, que se alimentan de su propia economía.
- `FreeMarketSim.money_snapshot(gs)` suma todo. La prueba lo verifica en:
  - aperturas;
  - entregas;
  - penalidades;
  - compras de empresas;
  - impuestos y dividendos;
  - comercio entre pueblos.

## Pruebas

`godot --headless tests/test_mercado.tscn` cubre:
- apertura por demanda y herencia (hijo, luego sin herederos y venta del Estado);
- solicitudes solo para bienes producidos;
- aceptar, entregar y cobrar (local y a un pueblo, con flete);
- entregas recurrentes automáticas;
- incumplir y la penalidad;
- ofertas salientes aceptadas y rechazadas;
- comprar una empresa NPC;
- el plan de gobierno (obra propia, licitación y pedido de materiales);
- el crecimiento de los pueblos;
- la conservación del dinero;
- guardar y cargar (incluida una partida vieja);
- 8 años de simulación;
- la interfaz.

`godot --headless tests/test_contratos.tscn` cubre los contratos recurrentes:
- compra cada 15 días × 4 entregas: llega el bien, se paga, precio fijo aunque cambie el mercado y el dinero se conserva;
- venta recurrente quincenal (solicitud) y semanal (propuesta);
- proveedor sin stock (penalidad, fiabilidad y fin del contrato);
- jugador sin dinero o sin espacio;
- contraofertas (del proveedor, del cliente y a una solicitud de la bandeja);
- compra a un pueblo (flete y demora) y a la importación;
- ofertas de proveedores NPC y cancelar con penalidad;
- migración de un contrato viejo, guardar y cargar, y la interfaz.
