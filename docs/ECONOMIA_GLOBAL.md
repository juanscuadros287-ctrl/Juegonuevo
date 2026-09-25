# Economía global: bolsa, ciclos, monedas, seguros, calidad y marca

Pedido de Sebastián (docs/PENDIENTES.md, sección A). Todo es moderado: los efectos del ciclo llegan de forma
gradual y tienen topes, y la economía sigue cerrada (el dinero cambia de manos; nunca aparece de la nada).

Configuración: `data/economia_global.json`. Estado: `GameState.world_econ` (se guarda; las partidas viejas lo
crean al cargar con valores por defecto, sin cambiar `SAVE_VERSION`).

## Archivos

| Archivo | Qué hace |
|---|---|
| `scripts/sim/global_econ_sim.gd` | `GlobalEconSim`: orquesta, guarda el estado, lleva los ciclos por país y las monedas, y tiene un generador aleatorio propio y guardado |
| `scripts/sim/stock_sim.gd` | `StockSim`: bolsa mundial, ley, S.A., emisión, recompra, compra hostil, empresas NPC y extranjeras |
| `scripts/sim/insurance_sim.gd` | `InsuranceSim`: pólizas del jugador y tu propia aseguradora |
| `scripts/sim/quality_sim.gd` | `QualitySim`: calidad de producto, marca y precio aceptado |
| `data/businesses_seguros.json` | Negocio **Aseguradora** (agencia → compañía de seguros) |
| `scripts/ui/global_econ_window.gd` | Pantalla **Economía mundial** con tres pestañas: Ciclos y monedas, Bolsa y Seguros |
| `scripts/ui/stock_panel.gd`, `insurance_panel.gd` | Pestañas de la bolsa y de los seguros |
| `scripts/ui/cycle_indicator.gd` | Indicador del ciclo en la barra superior (color, ⚠ y señales en el tooltip) |
| `tests/test_economia_global.gd` | Pruebas |

### Ganchos en archivos compartidos (1 o 2 líneas cada uno)
- `game_state.gd`: `var world_econ`, `_clear`, `to_dict`/`load_dict`, `GlobalEconSim.init_state` en
  `_init_expansions`, `GlobalEconSim.daily` tras `TradeSim.daily` y `GlobalEconSim.monthly` tras `EconomySim.monthly`.
- `gov_sim.gd`: al final de `monthly`, `GlobalEconSim.gov_monthly` (el gobierno decide la ley de la bolsa).
- `events_sim.gd`: `InsuranceSim.on_theft` tras un robo y `InsuranceSim.on_fire` tras cada incendio.
- `market_sim.gd`: en `purchase`, el precio aceptado × `QualitySim.accept_mult` y la importación ×
  `GlobalEconSim.import_fx_mult`; en `discretionary`, el gasto × `GlobalEconSim.demand_mult`.
- `shop_sim.gd`: en `_buy`, el precio de referencia × `QualitySim.accept_mult`.
- `trade_sim.gd`: `export_price` e `import_price` × `GlobalEconSim.trade_fx_mult(gs, town_id)`.
- `loan_contract.gd` (`era_rate_add` + `credit_rate_add`), `bank_sim.gd` (`credit_limit` × `credit_limit_mult`).
- `economy_sim.gd` (valor de las casas) y `realestate_sim.gd` (`value_total`) × `property_mult`.
- `building_panel.gd`: una línea con `GlobalEconSim.panel_lines` (calidad, marca y seguros del edificio).
- `hud.gd`: la ventana `GlobalEconWindow`, el botón «Economía mundial» del menú lateral y `CycleIndicator` en la barra.

## 1. Bolsa de valores mundial (`StockSim`)
- **Desbloqueo:** en la Revolución industrial (época 2) **y** con la **Ley de Mercado de Valores** aprobada. El
  jugador la propone (paga los estudios, que van al tesoro) y el gobierno decide en 30–60 días. La probabilidad
  depende del gobierno: los liberales la aprueban más que los sociales, y los cargos políticos de tu familia
  ayudan. Si la rechaza, se puede volver a proponer en 180 días. El gobierno también puede crearla por su cuenta
  (1,5 % al mes en la época industrial y 5 % en la moderna).
- **Tu S.A.:** todos tus negocios con fines de lucro forman una sociedad anónima de 1000 acciones, todas tuyas. La
  inscripción cuesta $250 × precios y va al tesoro.
- **Emisión:** se pueden emitir hasta el 35 % de las acciones, una vez cada 90 días, con un 5 % de descuento. Las
  compran los ciudadanos con ahorros (el 25 % de lo que les sobra sobre 60 días de necesidades) y las cajas de
  los pueblos vecinos (4 %). El capital entra a tu caja. Si no hay suficientes ahorradores, la emisión se coloca
  solo en parte.
- **Precio:** cada mes el precio se acerca un 30 % al valor fundamental:
  `máx(patrimonio × 0,6; ganancia anual × P/G del ciclo) / acciones`. A eso se suma la presión de las compras y
  ventas (que se disipa a la mitad cada mes) y un ruido del 3 %. El precio no se mueve más de ±15 % al mes. El P/G
  depende de la fase: 12 en auge, 10 normal, 8 en recesión y 6,5 en crisis.
- **Dividendos:** cada mes se reparte una parte de la ganancia (30 % por defecto, hasta 80 %, lo fijas tú). A los
  demás accionistas les llega su parte, que sale de tu caja. Si tu caja está en rojo, no se reparte.
- **Compra hostil:** si tienes menos del 50 %, el ciudadano más rico (fuera de tu familia) puede empezar a
  comprar: cada mes compra hasta un 8 % a los accionistas dispersos, con un 5 % de prima. Si pasa del 50 %,
  **pierdes el control**: se reparte el 70 % de las ganancias y no puedes emitir ni cambiar los dividendos.
- **Defensa, la recompra:** tu empresa recompra acciones y las retira, así sube tu porcentaje. Primero se
  compran a los accionistas dispersos; si ya solo queda el que hizo la compra hostil, él vende con un 25 % de
  prima. Al volver a pasar del 50 %, recuperas el control.
- **Empresas NPC:** una empresa NPC abierta hace más de 6 meses y que vale al menos $1500 × precios puede salir a
  bolsa (12 % al mes; como máximo 6 en bolsa). El fundador vende el 40 % a los ahorradores y cobra ese dinero. El
  jugador compra a los accionistas dispersos, nunca al fundador. Los accionistas minoritarios cobran el 35 % de la
  ganancia, que sale de la caja de la empresa (como máximo la mitad de lo que tenga). Si la empresa quiebra,
  cierra o cambia de dueño, sale de la bolsa.
- **Empresas extranjeras (resumidas):** hay una por país (hasta 8), con 100 000 acciones que cotizan en su moneda.
  Su ganancia por acción crece con la inflación y el ciclo de su país, y el precio es la ganancia por el P/G de
  ese país. Reparten el 40 %. Al comprar, el dinero sale del pueblo hacia la caja del «resto del mundo»
  (`world_cash`); al vender y cobrar dividendos, vuelve. En la tabla se ve el precio en su moneda y convertido.
- **Comisión:** 1 % de cada compra o venta, que va al tesoro.
- Titulares: `p` (jugador), `c:<id>` (ciudadano), `t:<id>` (pueblo), `g` (Estado) y `w` (resto del mundo). Cuando
  muere un titular, sus acciones pasan al cónyuge o a un hijo; si no tiene, al Estado. Si el heredero es el
  jugador, se suman a las suyas.

## 2. Ciclos económicos por país
- **Fases:** auge (6–16 meses), normal (12–30), recesión (5–12) y crisis (3–8), que puede ser **pánico
  bancario** o **burbuja inmobiliaria**. Al terminar una fase se sortea la siguiente:
  - desde normal: auge 45 %, recesión 43 %, crisis 12 %;
  - desde auge: normal 55 %, crisis 25 %, recesión 20 %;
  - desde recesión: normal 80 %, crisis 20 %;
  - desde crisis: recesión 55 %, normal 45 %.

  En tu país, si el crédito real de la partida crece más de un 25 % al año, sube la probabilidad de crisis y la
  crisis será un pánico bancario. Tu país no cambia de fase en los primeros 8 meses.
- **Señales previas:** una vez sorteada la fase siguiente, pasan de 3 a 5 meses antes de que llegue. En ese
  tiempo, los **indicadores adelantados** se mueven hacia la fase que viene:
  - la confianza empresarial cae antes de una recesión y se recupera antes de un auge;
  - el crédito se dispara (más de 15 %/año) antes de un pánico bancario;
  - la vivienda sube más de 9 %/año y las propiedades se inflan hasta ×1,12 antes de que estalle una burbuja.

  `GlobalEconSim.signals` las describe con palabras, `risk` da un riesgo de 0 a 100 y en tu país llegan como
  notificación. En la barra superior, el indicador toma el color de la fase y muestra ⚠ si el riesgo es de 40 o
  más.
- **Efectos**, que cambian un 35 % al mes hacia los de la fase, así que son graduales:

| | Auge | Normal | Recesión | Crisis |
|---|---|---|---|---|
| Gasto discrecional | ×1,08 | ×1 | ×0,88 | ×0,80 |
| Tasa de crédito | −0,5 pts | 0 | +1 pt | +2,5 pts (+1 pt más si es pánico) |
| Cupo del banco | ×1,1 | ×1 | ×0,85 | ×0,65 (×0,8 más si es pánico) |
| Propiedades | ×1,07 | ×1 | ×0,94 | ×0,86 (×0,93 más si es burbuja) |
| P/G de la bolsa | 12 | 10 | 8 | 6,5 |
| Moneda (desvío real) | −3 % | 0 | +4 % | +8 % |

## 3. Moneda e inflación por país
- Cada país usa `currency`, `base_inflation` y `exchange_rate_to_ref` de `data/countries.json`. Si el mapa agrega
  países o los cambia por reales, `GlobalEconSim` agrega los nuevos al cargar; solo exige ese formato.
- **Tipo de cambio** (unidades de la moneda local por 1 unidad de referencia):
  `nominal = inicial × (precios del país / precios de referencia) × desvío real`.
  - Los precios de referencia suben un 3 % al año.
  - Los precios de los demás países suben con su `base_inflation`, más el ciclo y un poco de ruido.
  - En tu país, los precios son el `price_level` simulado por `EconomySim`: la inflación es la de la partida (dinero,
    crédito y escasez), que ya es nacional y no por pueblo.
  - El **desvío real** vuelve un 15 % al mes hacia 1 + el efecto del ciclo, con un ruido del 1,2 %, y queda
    entre 0,8 y 1,25.
- **Comercio:**
  - `trade_fx_mult` = 1 + parte × (desvío real − 1). La parte es 0,35 con pueblos de tu país (los bienes
    comerciados tienen precio internacional) y 1 con un pueblo extranjero (campo `country` del pueblo; en ese
    caso se usa el desvío relativo entre los dos países).
  - Si tu moneda se deprecia, importar cuesta más y exportar paga más en tu moneda.
  - Las importaciones de los vecinos (`MarketSim.purchase`) usan una parte de 0,5.
- **Una sola cuenta:** el dinero del jugador está en la moneda de su país. Los montos extranjeros se muestran como
  `12,50 S/A (≈ $15)` con `GlobalEconSim.fmt_foreign`.

## 4. Seguros (`InsuranceSim`)
- **Pólizas con la aseguradora externa (La Previsora)**. La prima mensual es la pérdida esperada × 1,45:

| Póliza | Prima | Deducible | Paga cuando |
|---|---|---|---|
| Incendio (cualquier edificio) | (valor + ½ inventario) × 0,11 % × 1,5 si tiene techo de paja (nivel 1) × (1 − 0,6 × cobertura de bomberos) | 10 % | `EventsSim._fires` (reparación e inventario quemado, o el valor total si se destruye) |
| Robo (negocios) | 1,2 × nivel de precios × (0,4 + crimen/40) | 15 % | `EventsSim._crime` (lo robado y el inventario) |
| Cosecha (campos estacionales) | ingreso mensual esperado × 3,5 % | 20 % | Cierre de mes con sequía o mal clima (factor < 0,85; el invierno normal no cuenta) |
| Pérdida de carga (global) | 2 % del comercio exterior del mes anterior | 10 % | Un envío de `TradeSim` se pierde (2,5 % de probabilidad por envío) |

  La aseguradora externa tiene su propia caja, que empieza en $20 000 × precios: las primas entran y los
  siniestros salen. Si no alcanza, paga lo que tiene y avisa. En el negocio asegurado, la indemnización se
  descuenta del mismo gasto (reparaciones o robos), así que la pérdida neta es el deducible.
- **Tu aseguradora** (negocio «Aseguradora»: agencia con 20 pólizas por empleado y compañía con 30):
  - **Clientes:** empresas NPC abiertas, casas de ciudadanos y negocios de los pueblos con ruta comercial.
    Compra la fracción `1,4 − 0,6 × tarifa` (entre 5 % y 90 %), y la tarifa es un múltiplo de la prima justa
    que eliges (0,5–2,5).
  - **Primas:** cada mes las paga la caja de la empresa NPC, el dueño de la casa o la caja del pueblo. Quien no
    puede pagar pierde la póliza.
  - **Siniestros reales:** los incendios del pueblo (`on_fire`), robos estadísticos en las empresas NPC clientes
    (según el crimen) e incendios estadísticos en los pueblos, con un 20 % de pérdida total. Se pagan con tu
    dinero y figuran como gasto «siniestros».
  - **Riesgo:** con una tarifa baja tienes muchos clientes y poco margen; un mal año de incendios cuesta caro.

## 5. Calidad y marca (`QualitySim`)
**Fórmula de la calidad**: una media geométrica ponderada. Va de 0,4 a 1,8 y 1 es la calidad normal. Se ve en el
panel del negocio con cada factor.

```
Q = L^0,30 × T^0,20 × M^0,15 × S^0,25 × I^0,10
L  nivel         = (0,85 + 0,15 × (nivel − 1)) × calidad del nivel (datos)
T  tecnología    = 0,85 + 0,10 × (época − 1) + 0,6 × (bono de producción del bien − 1)       [0,7–1,5]
M  maquinaria    = (1 + 0,10 × mejoras de calidad) × 1,10 si el nivel usa maquinaria/motor/herramientas o
                   electricidad (× (0,85 + 0,15 × cobertura eléctrica))
S  personal      = productividad media de los empleados (habilidad, experiencia, estudios, salud) [0,5–1,5]
I  insumos       = calidad media de lo que produces de cada insumo; lo que se compra fuera cuenta 1 [0,5–1,6]
```

- **Mejoras de calidad**, con `QualitySim.buy_upgrade`: hasta 3. Cada una cuesta el 20 % del nivel y un 50 %
  más que la anterior. El dinero va a artesanos del pueblo o, si no hay, al tesoro.
- **Marca** de 0 a 100, una por empresa (cada negocio productor, tuyo o NPC). Empieza en 50 y cada mes cambia
  así:
  - suma 6 × (Q − 1);
  - suma 0,3 si vendió y resta 0,5 si no vendió;
  - resta 5 por cada incumplimiento tuyo en un contrato de ese bien;
  - se acerca un 3 % a 50.

  Hay que sostener la calidad: con Q = 1,1 tiende a unos 80; con Q = 0,9, a unos 40.
- **Precio aceptado:** `accept_mult = 1 + 0,3 × (Q − 1) + 0,2 × (marca − 50) / 50`, entre 0,85 y 1,3. En
  `MarketSim.purchase` sube el precio máximo que aceptan pagar y el precio de referencia de la demanda elástica.
  En `ShopSim._buy` hace lo mismo con los comercios. Una marca fuerte vende más caro sin perder clientes; una
  marca mala pierde clientes aunque su precio sea el de mercado.

## Interfaz
- **Menú lateral → Economía mundial** (o clic en el indicador del ciclo en la barra superior). Tiene tres
  pestañas:
  - **Ciclos y monedas:** fase, indicadores, riesgo, señales, efectos del día, tu moneda y la tabla de países.
  - **Bolsa:** la ley, tu S.A. (convertir, emitir, recomprar, dividendos y accionistas), las empresas NPC y
    extranjeras con su precio convertido, y comprar o vender.
  - **Seguros:** pólizas por edificio con su prima, seguro de carga, tu aseguradora (tarifa, clientes, primas y
    siniestros) y el registro de siniestros.
- **Panel del edificio:** la calidad con su fórmula, la marca, el precio aceptado y los seguros.

## Pruebas
`godot --headless res://tests/test_economia_global.tscn` comprueba:
- la bolsa bloqueada sin época o sin ley, y la ley decidida por GovSim;
- la emisión con entrada de capital y el dinero conservado;
- la compra hostil y la recompra;
- que la recesión y la crisis bajan el gasto;
- que el pánico bancario encarece y reduce el crédito;
- que el tipo de cambio encarece la importación y que fluctúa;
- que el seguro paga un incendio (el negocio solo pierde el deducible) y el seguro de cosecha;
- la aseguradora propia (primas, siniestro y conservación del dinero);
- que la calidad y la marca suben el precio aceptado;
- los ciclos con señales previas en 20 años;
- las acciones extranjeras y de empresas NPC;
- guardar, cargar y abrir una partida vieja;
- una simulación larga y la interfaz.
