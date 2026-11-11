# Motor — Fase 5: mi planta en el mercado, spot horario, despacho, eventos del mundo y seguros

Todo en `packages/sim` (puro, determinista) y `packages/data` (YAML + Zod). La API de las fases 2–4 se mantiene: solo se agregó
(campos opcionales, funciones y comandos nuevos, parámetros opcionales). `SAVE_VERSION = 5`.

## 1. Arquitectura nueva

```
packages/sim/src
  market/power.ts     mercado eléctrico por país: parque existente (de la matriz), calibración, precios horarios del mes
                      (12 meses × {laborable, fin de semana} × 24 h), clima (El Niño/La Niña, hidrología), foto del parque de
                      los actores, previsiones (con banda P10–P90) e historial; storageDay() (arbitraje de un día)
  market/dispatch.ts  despacho de una planta contra los precios horarios (DispatchPolicy, MonthPlan, planOnPrices, projectPlan)
  world/events.ts     eventos del mundo, elecciones, regulación por país, avances tecnológicos, daños y seguros
  business/share.ts   historial mensual de cuota de mercado (pedido de la UI de la Fase 3)
  selectorsPower.ts   selectores de la Fase 5
packages/data
  power.yaml          formas de demanda y de recurso horarias, clases del parque, clima, valor del agua, escasez, comprador,
                      modalidades de PPA, crédito firme por tecnología y el mercado de cada uno de los 13 países
  events.yaml         19 eventos, gobiernos (elecciones) y parámetros de los seguros
```

Orden del cierre de mes en `step`: actores → competidores → suministro → macro (tipo de cambio y combustibles) →
**eventos del mundo** (`worldMonthly`) → **mercado eléctrico** (`powerMonthly`: registra el mes que terminó, sortea el clima
si empieza un año y calcula el mes nuevo) → cuota de mercado → oportunidades. `applyCommands` inicializa perezosamente
(`ensureWorldEvents`, `ensurePower`). Flujos RNG: `market` (clima) y `events` (eventos del mundo), ya existentes desde la v2.

## 2. Mercado eléctrico (`market/power.ts`)

Por país y mes, para cada tipo de día y hora:
1. **Demanda** = demanda media × (1 + crecimiento)^años × perfil mensual × forma horaria × eventos × El Niño.
2. **Oferta**: solar y eólica (MW × FC de la clase × forma horaria × estacionalidad del país), base (geotermia, nuclear),
   hidro de pasada (hidrología del año × perfil mensual), hidro de embalse (40 % plano por caudal ecológico; 60 % recorta la
   punta de la demanda residual; los embalses regulan una parte de la estacionalidad según `hidro_embalse_frac`), y
   térmicas en orden de mérito: cada clase en 5 bloques de eficiencia (heat rate × 0,85…1,4), costo marginal = heat rate ×
   combustible (índice + eventos) + CO2 × (carbono del país + regulación) + O&M variable.
3. **Precio** = costo marginal de la unidad marginal. Sobra renovable ⇒ vertimiento y **precio piso**. Alcanza la hidro ⇒
   **valor del agua** (fracción del costo térmico medio, sube en meses secos). Uso de la térmica > 95 % ⇒ rampa hasta el
   **precio techo** (escasez). Congestión: renovable variable sobre `red.limite_vre_frac` × demanda se vierte.
4. **Almacenamiento de los actores** (segunda pasada): carga en horas baratas, descarga en caras ⇒ aplana la curva.

**Parque**: la matriz (participación en la generación) y la demanda dan los MW por clase (`baseFleet`); se agregan turbinas
de punta hasta cubrir la punta × margen de reserva. El parque existente crece con la demanda; **las plantas de los actores se
suman encima** (`fleetSnapshots`, foto pública al inicio de cada mes con el FC típico de la tecnología, nunca el real), así que
más oferta ⇒ precios más bajos (canibalización solar al mediodía).

**Calibración**: un factor por país sobre los costos marginales térmicos (bisección) hace que el año base, con hidrología
normal y sin actores, dé exactamente el `precio_spot_medio_usd_mwh` histórico del YAML (Panamá 95). No se bajó el spot
histórico: lo que cambia es que ahora es endógeno.

**Clima**: cada año El Niño (25 %), La Niña (22 %) o neutral, con persistencia 35 %; hidrología por país log-normal
(σ del país) × efecto ENSO (Panamá 0,8 con El Niño, Colombia 0,65, Chile 1,15, Kenia 1,15). Evento `climateOutlook`.

**Previsiones**: el mes en curso es el calculado; los demás usan la información de hoy (hidrología conocida del año en curso,
combustibles que vuelven a su media, eventos vigentes, obras que entran en su fecha). **Largo plazo** (`longRun`, lo que usan
la economía, los bancos y los compradores): hidrología normal, combustibles a 3 años, sin eventos temporales y con todas las
obras: un año seco o una crisis no se extrapolan a 25 años de vida. Caché por versión del mercado (no se guarda).

Precio final = precio real × inflación del USD del país × tipo de cambio real (misma convención que la Fase 4).
`spotMonthUsd`, `spotYearUsd` y `powerSpotMarket` (implementa la interfaz `SpotMarket` de la Fase 2). Sin `power.yaml`
todo vuelve al spot simple de la Fase 4.

**Capacidad y servicios** (`capacidad`, `servicios` por país): pago mensual = precio × crédito firme de la tecnología × MW ×
disponibilidad (sin contrato de potencia); servicios = MW-h ofrecidos × precio, diluido si la oferta de los actores supera
el requerimiento (fracción de la demanda). PAN, COL, DOM, CHL, MEX tienen capacidad; PAN, COL, DOM, CHL, MEX, ESP, PHL, USA servicios.

## 3. Despacho (`market/dispatch.ts`) y planta propia

`planOnPrices(state, ctx, monthPrices, {tech, policy, thermalMc, ppaPrice, h2Value, fcRef})` → `genFrac` (fracción de la
energía disponible que se produce), precio capturado, spot medio, costo de carga, vertimiento y servicios:
- **Solar/eólica/pasada**: forma horaria; no produce si el spot < `precioMinimo` (por defecto 0 sin PPA: precio negativo ⇒
  vertimiento); congestión ⇒ vertimiento.
- **Embalse y CSP**: mueven la energía regulable a las horas más caras.
- **Térmicas**: generan en las horas con precio ≥ costo marginal (las de base se comprometen por día); con PPA «según
  producción» y prioridad PPA generan si el contrato cubre el costo.
- **Almacenamiento** (`storageDay`): descarga en las horas caras y carga en las baratas mientras precio_descarga −
  precio_carga/eficiencia > O&M variable, con umbrales `cargarBajo`/`descargarSobre`, `reservaMin` y tope de ciclos.
- **Hidrógeno**: compra en las horas más baratas bajo el valor del H2 (o `compraMaxima`).
- **Servicios**: `servicios` + `fraccionServicios` reservan potencia (almacenamiento, térmicas, embalse).

La operación diaria usa el plan del mes (cacheado en `operation.plan`, se rehace si cambian los precios o la política).
La liquidación mensual separa **PPA, spot, capacidad, servicios y compras al spot** (`OperationMonth.ppaUsd`, `spotUsd`,
`capacityUsd`, `servicesUsd`, `purchasesUsd`, `curtailedMwh`, `captureUsdMwh`). PPA:
- `produccion` (por defecto, como antes): se paga lo producido;
- `bloque` (físico): volumen comprometido = P50 × 90 %, +4 % de precio; si produce menos, **compra la diferencia al spot**;
  el excedente va al spot;
- `financiero` (CfD): la energía va al spot y se liquida (PPA − spot medio) sobre el volumen comprometido.

**Permisos para operar**: al terminar la puesta en marcha se exige licencia de generación, viabilidad de conexión y contrato
de acceso a la red (los grupos que apliquen); si faltan, la planta espera (`codBlocked`, evento `operationBlocked`).

**Economía**: `projectTerms` usa la previsión horaria de largo plazo (captura, despacho, carga); `projectEconomics` resta a los
costos fijos los ingresos esperados de capacidad y servicios. `staticMarket: true` = referencia de la Fase 4 (el LCOE de
catálogo de `typicalEconomics` sigue así para comparar con Lazard/NREL).

**Valoración de venta** (`saleValuation`): un comprador de un proyecto sin PPA recorta la curva de precios 12 % y exige +3 pp
(`comprador` en power.yaml). Con eso y el spot endógeno, la IA agresiva ya no crece sin límite: la prueba de balance vuelve a
**patrimonio máximo < 6× el capital inicial en 10 años (3 semillas)** (fases 3, 4 y 5).

## 4. Eventos del mundo (`world/events.ts`, `events.yaml`)
Cada mes, por evento: global (`prob_anual/12`) o por país (con `amenaza`, la probabilidad es `riesgos[amenaza]` del país).
Eventos: crisis petrolera, conflicto regional (fletes, aranceles, plazos), pandemia, avances en solar/baterías/eólica
(permanentes), sobreoferta de equipos, huracán, terremoto, inundación, sequía, huelga nacional, crisis cambiaria, impuesto al
carbono, reforma de permisos, endurecimiento ambiental, nuevos incentivos y recorte de incentivos. **Elecciones** periódicas
por país (`elecciones` en power.yaml): gobierno pro-renovables / de centro / pro-fósiles que cambia permisos, incentivos y carbono.

Efectos (iguales para todos los actores): `worldFuelFactor` (combustibles y spot), `worldDemandFactor`, `worldHydrologyFactor`,
`worldCapexFactor` (en `currentCapex`), `worldLeadTimeFactor` (entrega de equipos), `worldPermitFactor` (plazo de permisos),
`worldCarbonAddUsdT` (carbono), `worldCreditFactor` (crédito fiscal). Desastres: cada planta u obra del país (jugador e IA)
se daña con la vulnerabilidad de su tecnología (fracción, días fuera de servicio, costo = valor × fracción × costo de
reposición); obras paradas. Devaluación inmediata del tipo de cambio real.

**Seguros**: `buyInsurance {projectId, coverage: 'danos' | 'danos_lucro'}` / `cancelInsurance`. Prima anual = valor asegurado ×
máx(tasa mínima, pérdida esperada del sitio × recargo 1,6) (× 1,35 con lucro cesante); primera prima al contratar y luego
mensual (`seguro`). Carencia 30 días, deducible 5 %, lucro cesante hasta 180 días con el ingreso medio reciente. Las
indemnizaciones van a `indemnizaciones`. La IA prudente (conservadora, estatal, fondo) asegura con el mismo comando.
`triggerWorldEvent` fuerza un evento (pruebas/escenarios; no es un comando de juego).

## 5. API nueva para la UI

### Comandos
- `setDispatchPolicy {projectId, policy: {cargarBajo?, descargarSobre?, reservaMin?, precioMinimo?, prioridad?: 'ppa'|'spot', servicios?, fraccionServicios?, compraMaxima?}}`
- `buyInsurance {projectId, coverage}`, `cancelInsurance {projectId}`
- `terminatePpa {projectId}` (penalidad = máx(12 meses de ingresos del contrato, VP de lo que pierde el comprador); no si viene de una licitación)
- `seekPpa` acepta `settlement?: 'produccion' | 'bloque' | 'financiero'`

### Selectores (`selectorsPower.ts`)
- `selectPowerMarket(state, ctx, iso)` → horas del mes (48 puntos: precio, demanda, vertimiento), media/punta/valle/mín/máx,
  techo y piso, **curva de oferta** (bloques con MW acumulados y costo), valor del agua, **previsión de 12 meses con banda
  P10–P90**, historial (120 meses), clima, parque por clase (existente vs actores), mercado de capacidad y servicios.
- `selectPowerMarkets(state, ctx)` → resumen por país (precio, punta, valle, hidrología, cambio a 12 meses).
- `selectPlantDispatch(state, ctx, projectId)` → política y su texto, opciones válidas para el formulario, plan del mes,
  **perfil horario típico (generación/descarga, carga, precio)**, ingresos por fuente (24 meses y total 12 meses), modo de
  venta (PPA con modalidad, volumen, años restantes, penalidad de terminación; o merchant), valor de venta (con descuento
  merchant), seguro (vigente, carencia, siniestros, cotizaciones, pérdida esperada) y `codBlocked`.
- `selectRevenueBySource(state)` → energía, capacidad, servicios, compras e indemnizaciones de la empresa (12 meses).
- `selectWorldEvents(state, ctx, {countryCode?})` → eventos activos y pasados con efectos en texto, regulación vigente y
  gobierno por país, próximas elecciones, cambios permanentes de costo por tecnología, clima.
- `selectClimate(state, ctx, iso)`; `effectTexts(efectos)`.
- Utilidades: `monthPrices`, `spotMonthUsd`, `spotYearUsd`, `forecastBand`, `countryFleetMw`, `computeMonthPrices`,
  `calibrationFactor`, `storageDay`, `planOnPrices`, `projectPlan`, `currentPlan`, `insurancePremium`, `saleValuation`,
  `ppaTerminationPenalty`, `capacityAndServicesUsdYear`, `operatingPermitBlockers`.

### Pedidos de la UI de la Fase 3 (agregados)
- **Bug**: los eventos de contrato de la IA (`contractSigned`… con ids `C1-K1`) ya no llegan al registro del jugador (prueba).
- `OpportunityView.location` (`opportunityLocation`): lat/lon aproximada y determinista (sitio candidato público del país).
- `selectMarketShareHistory(state)` (estado `market.shareHistory`, 120 meses).
- `ContractView.countryCode` y `ContractView.eligibleProjects` (para asignar contratos «sin proyecto»).
- `stageId: ProjectStage` en `CompetitorView.visibleProjects`, `ContractView.project` y los proyectos elegibles (`stage` sigue siendo el texto).

### Eventos
`climateOutlook`, `worldEvent`, `worldEventEnded` (con `countryCode`, solo si afectan a países del jugador o son globales);
de proyecto: `plantDamaged`, `insuranceChanged`, `dispatchPolicyChanged`, `ppaTerminated`, `operationBlocked`.

### Contabilidad
Categorías nuevas: `ingresos_capacidad`, `ingresos_servicios` (cuentan en `revenueUsd`), `compras_energia`, `indemnizaciones`.

## 6. Guardado
`SAVE_VERSION = 5`. Migración 4→5: `market.power` y `market.world` vacíos (se inicializan en el próximo paso con datos;
el clima del año sale del flujo `market`), flujos `market`/`events` si faltaran. Campos nuevos opcionales: `Project.dispatch`,
`Project.insurance`, `Project.codBlocked`, `PpaContract.settlement/committedMwhYear`, `Operation.plan/monthCurtailedMwh/monthServiceMwH`,
`OperationMonth.*Usd`, `MarketState.shareHistory`.

## 7. Rendimiento
Precios de 13 países por mes: 2 × 24 horas × ≈ 40 bloques. 10 años con 5 IA y todos los países ≈ 1–2,5 s (prueba < 8 s).

## 8. Supuestos y límites
- Días representativos: no hay picos raros de una hora (ERCOT con 5.000 USD/MWh aparece solo con escasez sistémica). En
  sistemas con mucha hidro de embalse los precios horarios son planos (la hidro recorta la punta), como en la realidad.
- El parque existente crece con la demanda con la misma mezcla; los actores se suman encima (no desplazan inversiones ajenas).
- Sin interconexiones en el despacho (las líneas de la Fase 4 siguen cobrando peaje + diferencial medio).
- Datos de mercado por país aproximados (`supuesto`): formas horarias, embalse, σ hidrológica, ENSO, techos/pisos, capacidad,
  servicios, riesgos naturales y efectos de los eventos. Calibrar con CND, XM, CEN, CENACE, REE/OMIE, ERCOT si se consiguen series.
- La foto del parque y las previsiones usan el FC típico de cada tecnología (información pública), no el recurso real.
- Las modalidades de PPA (bloque, financiero) se eligen al pedir el PPA del canal genérico; los contratos de licitación son «según producción».
