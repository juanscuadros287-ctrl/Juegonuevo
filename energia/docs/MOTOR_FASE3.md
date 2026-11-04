# Motor — Fase 3: licitaciones, clientes, proveedores, competidores IA e I+D

Todo en `packages/sim` (lógica pura, determinista) y `packages/data` (YAML + Zod). La API de la Fase 2 se mantiene: solo se agregó.

## 1. Arquitectura

```
packages/sim/src
  business/   types (estado), actor (vistas de actor), research (I+D), bids (ofertas y cotización),
              opportunities (generación y adjudicación), contracts (obligaciones, EPC), bonds (garantías),
              tick (avance diario/mensual de un actor), world (inicialización perezosa)
  supply/     supply.ts: índices de materiales, curva de aprendizaje, demanda mundial, colas y relación con proveedores
  ai/         brain.ts (decisiones por estrategia), competitors.ts (init, turnos, avance, quiebra)
  selectorsBusiness.ts   selectores de la Fase 3 para la UI
packages/data
  research.yaml  clients.yaml  competitors.yaml   (nuevos)
  suppliers.yaml (inversores, logística, capacidad y dinámica de precios)   studies.yaml (2 estudios desbloqueables)
```

### Actores
Jugador y competidores son **actores** con la misma forma: `company`, `finance`, `projects`, `nextProjectId`, `business` (`BusinessState`: reputación, experiencia, I+D, contratos, relación con proveedores, caja en garantías). Los del jugador están en la raíz de `GameState` (como en la Fase 2); los de cada IA en `state.competitors[i]`.

`actorView(state, comp)` devuelve un `GameState` cuyo `company/finance/projects/business` son los del competidor (referencias) y cuyos flujos RNG `projects`/`business` son el propio del competidor (`ai_C1`…). Con esa vista la IA corre **exactamente** el mismo código: `applyCommand`, `actorDaily`, `actorMonthly` (proyectos, I+D, contratos, gastos fijos, impuestos, quiebra). No hay reglas propias de la IA. Los proyectos de la IA llevan prefijo (`C2-P3`), los contratos también (`C2-K1`). `serialize` rechaza vistas.

### Orden de un día (`step`)
1. inicialización perezosa del mundo (primer paso con datos, también tras migrar): índices, reputación inicial, competidores, primeras oportunidades;
2. comandos del jugador; 3. turnos de decisión de la IA (cada `dias_decision`, escalonados) → comandos normales;
4. avance diario del jugador y de cada IA; 5. licitaciones: cierre de recepción y adjudicación;
6. al cambiar de mes: cierre de cada actor, mercado de equipos (`supply`), nuevas oportunidades.

Flujos RNG nuevos: `supply`, `tenders`, `business` y uno por competidor `ai_<id>` (la migración 2→3 los siembra). Las decisiones de la IA usan un RNG derivado de (semilla, competidor, día) y no consumen flujos del estado.

## 2. Oportunidades y clientes (`clients.yaml`)
Cada tipo de cliente genera oportunidades cada mes (Poisson con `frecuencia_anual/12`). Panamá:

| Tipo | Contrato | Habilita (I+D) | Notas |
|---|---|---|---|
| Licitación de energía ETESA | PPA (USD/MWh) | `ppa_simple` (inicial) | tope publicado, 10–80 MW, 10–20 años |
| Licitación de potencia ETESA | potencia (USD/kW-mes) | `contrato_potencia` | MW firmes; potencia firme por tecnología (eólica 20 %, solar 5 %) |
| Minería, industria, centro de datos | PPA corporativo | `ppa_corporativo` | precio de reserva **oculto**; exigencias de experiencia/patrimonio |
| Hoteles, zonas francas | EPC llave en mano (USD/kW) | `epc_llave_en_mano` | construyes para el cliente con margen |
| Municipio / entidad pública | BOT (USD/MWh) | `bot` | al terminar el plazo la planta pasa al Estado |

El precio de referencia sigue al mercado: EPC × índice de CAPEX; PPA/BOT × (0,75·índice de CAPEX + 0,25·inflación); potencia × inflación. País nuevo = agregar tipos con `pais` (y su `countries/XXX.yaml`).

## 3. Ofertas y adjudicación
`submitBid {opportunityId, techId, price, deliveryMonths, projectId?, effort?, equipmentId?, epcId?}`
- Unidad del precio: USD/MWh (ppa, bot), USD/kW-mes (potencia), USD/kW (epc).
- `projectId`: vincula un proyecto propio (misma tecnología y país, 0,9–1,5 × MW requeridos, sin otro contrato). Sin él te comprometes a uno nuevo y tienes `meses_asignar_proyecto` (9) para asignarlo con `assignContractProject`.
- Costos: preparación (`costo_preparacion_usd`, × 2,5 si `effort: 'reforzada'`) a resultados; garantía de seriedad inmovilizada (colateral 50 % del valor; comisión 1,5 %/año). Se devuelve al perder o retirar (`withdrawBid`, solo mientras está abierta).
- Validación (`bidBlockers`, la misma para la IA): plazo abierto, tipo de contrato y tecnología investigados, mercado abierto, experiencia mínima, patrimonio mínimo, caja, plazo 3…`codMonths`.
- **Puntaje** (pesos del YAML): precio `100·mín/precio`; técnica `50 + 25·madurez del proyecto + 8 si medición bancable + 12 reforzada + I+D (+ calidad de proveedores en EPC) − 15 si el plazo no es creíble`; experiencia `30 + 35·mín(1, MW de experiencia / (2·MW pedidos)) + 0,35·reputación`; plazo `100·mín/plazo`. Ruido del comité ±1,5 puntos. Ofertas sobre el tope/reserva se descalifican.
- Hay **ofertantes externos** (empresas internacionales no simuladas; 1–3 por oportunidad según el YAML) con precios alrededor de la referencia: sin ellos el jugador ganaría siempre al tope.
- Resultado: ranking completo con precios revelados (`opportunity.result`). El ganador debe constituir la garantía de cumplimiento; si no tiene caja pierde la de seriedad y gana el siguiente.
- `quoteBid` / `selectBidQuote`: precio de equilibrio (VAN = 0 a la tasa del país o la indicada), precio sugerido con margen, CAPEX, FC, garantías, puntaje técnico estimado, plazo realista. PPA: el período posterior al contrato vende al spot (× 0,85); BOT: sin cola; potencia: la energía se vende al spot y el cargo cubre el resto.

## 4. Contratos y obligaciones
- **PPA/BOT** con proyecto: el proyecto recibe `ppa` firmado (precio, años, indexación, fecha de COD = plazo ofertado, multa mensual). La multa por atraso la cobra el ciclo de proyecto de la Fase 2. Con COD → se libera la garantía; reputación +5 si fue a tiempo (+1 tarde). Pasado `codDeadline + meses_max_atraso` sin COD → **se ejecuta la garantía** (se pierde el valor completo), reputación −15, el PPA queda `fallido`. Abandonar el proyecto = incumplimiento; venderlo cede el contrato (se libera la garantía). BOT: al cumplir el plazo la planta se transfiere sin pago (castigo del valor en libros, prepago de deuda).
- **Potencia**: pago mensual `MW firmes·1000·precio·indexación` mientras opera; −10 % si la disponibilidad del mes < 85 %; multa por atraso.
- **EPC para terceros**: presupuesto = equipos + flete + aranceles + EPC + 50 % de «otros» (precios del día); duración = construcción × (MW/típico)^0,3 (entre 0,4 y 1,3) × factor del EPC × triangular(0,9; 1; 1,25). Cobros: 10 % anticipo, 80 % por avance (mensual), 10 % retención al entregar. Riesgos: huelgas, lluvias, sobrecostos (35 % de la probabilidad por hito del EPC, por mes). Daños por atraso 0,5 %/semana hasta 10 %; pasado el plazo máximo se ejecuta la garantía. Al entregar: +MW de experiencia, reputación +4 (+1 si tarde).

## 5. Proveedores y cadena de suministro (`suppliers.yaml`)
- Tipos: `equipos` (módulos, turbinas), `inversores` (solo FV: reemplazan `fraccion_inversores` = 12 % de los equipos), `epc`, `logistica` (reemplaza el flete y multiplica el plazo de entrega). `selectSuppliers` acepta `inverterId?` y `logisticsId?` (opcionales).
- Índices mensuales (flujo `supply`): materiales (polisilicio σ 35 %/año, acero 18 %, cobre 20 %) y demanda mundial (σ 12 %), log-normales con reversión a 1 y límites.
- `equipmentIndex(tech) = (1+aprendizaje)^años × (1 − Σw + Σ w·material) × demanda^0,3`; `epcIndex = (1+aprendizaje_epc)^años`. Solar −3,5 %/año en equipos y −1,2 % en obra; eólica −1,2 % y −0,5 %.
- Cola por proveedor (MW pedidos al iniciar obra, se descuenta `capacidad_mw_ano/12` por mes): plazo × (1 + 0,6·cola/capacidad) × demanda^0,8; precio × (1 + 0,08·max(0, cola/capacidad − 0,5)).
- Relación (por actor): 1,5 % de descuento por pedido (máx. 6 %), +1 % de confiabilidad por pedido (máx. 5 %), −2 % por cada entrega atrasada.
- El presupuesto se fija al pedir el financiamiento (`currentCapex`); el plazo de entrega y la confiabilidad, al iniciar la obra.

## 6. Competidores IA (`competitors.yaml`)
Cinco empresas: **Solaris Andina** (agresiva en precio, vende proyectos listos para construir), **Istmo Generación** (conservadora), **EGESA Renovables** (estatal: reputación 75, 400 MW de experiencia), **Vientos del Istmo Tech** (especialista eólica, invierte en I+D) y **Meridian Infra Fund** (fondo, capital barato). Cada una con caja, gastos fijos, margen objetivo, tasa de descuento, apalancamiento, socio, tamaño de proyectos, preferencia de proveedores, probabilidad de ofertar, prioridades de I+D.

Decisión (`decideCompetitor`, cada 14–30 días): presupuesto de I+D y siguiente nodo; para cada proyecto, el mismo «piloto» que haría un jugador (estudios —bancables si es cauta—, permisos, PPA, proveedores, financiamiento buscando más socio si falta caja, obra solo si la caja cubre el aporte propio, vender o abandonar si la economía estimada no da); crea proyectos en sitios candidatos públicos libres (tamaño según su caja); oferta en oportunidades si el precio sugerido cabe bajo el tope (o la referencia pública × 1,08 si es privada) y si puede cumplir el plazo.

**Información incompleta** (prueba explícita): la IA solo lee su estimación del recurso (`p.estimate`), oportunidades saneadas con `publicOpportunity` (sin reserva privada ni ofertas ajenas), datos públicos (YAML, grilla, índices, sitios ocupados). Cambiar el recurso real, los precios de reserva y las ofertas ajenas no cambia sus comandos.

Quiebra: misma regla que el jugador. La IA quebrada se detiene, sus ofertas se retiran con pérdida de garantía y sus contratos se rescinden; evento público `competitorBankrupt`.

**Sin grilla** (`ctx.grid` ausente, como hoy en el worker del juego) la IA no puede crear proyectos (igual que el jugador): solo oferta EPC, investiga y oferta comprometiéndose a proyectos que luego no puede crear (y pierde garantías). La UI debe pasar la grilla en el `SimContext`.

Rendimiento: 10 años con 5 IA ≈ 0,6–1 s (prueba: < 5 s).

## 7. I+D (`research.yaml`)
37 nodos en 5 ramas. Iniciales (gratis): solar FV, eólica en tierra, estudios básicos, Panamá, PPA simple.
- Tecnologías (Fase 4, `fase_modelo: 4`): baterías, hidro de pasada/embalse/bombeo, geotérmica, CSP, eólica marina, biomasa/biogás, gas, hidrógeno verde. Se pueden investigar; aparecen en las oportunidades pero no se puede construir hasta que tengan modelo.
- Estudios: LiDAR de escaneo (`medicion_eolica_lidar`, bancable en 8 meses), prefactibilidad digital, geofísica y batimetría (Fase 4).
- Mercados: oficina regional → Costa Rica, Colombia, República Dominicana → Chile (Fase 4).
- Contratos: PPA corporativo, EPC llave en mano, potencia firme, BOT.
- Eficiencia: CAPEX −4 % (todas) y −5 % (FV modular), FC +4 % (FV bifacial) y +5 % (eólica), O&M −10 % y −8 % (FV), permisos −15 % del plazo, +6 puntos técnicos.

Mecánica: `setResearchBudget`, `startResearch` (si hay una activa, va a la cola), `queueResearch` (acepta prerrequisitos en curso/cola), `cancelResearch` (se pierde lo gastado y la mitad del avance). Avance diario = mín(1/duración, presupuesto/costo); se paga lo devengado al cierre del mes (`investigacion`). Sin caja o sin presupuesto se detiene. Contratiempo al terminar (`prob_contratiempo`): vuelve 10–30 %.

Dónde se aplican los efectos: CAPEX en `currentCapex` (presupuesto del financiamiento, economía, viabilidad, selectores, cotizaciones); O&M en el cierre mensual de la planta y en la economía; FC al entrar en operación (`operation.fcBonus`, ya incluido en `fcReal`; no retroactivo) y en las estimaciones; plazo de permisos en `applyPermit`; tecnologías y países en `createProject`; estudios en `commissionStudy`; contratos y técnica en las ofertas.

## 8. API nueva para la UI
### Comandos
`submitBid`, `withdrawBid`, `assignContractProject {contractId, projectId}`, `startResearch {nodeId}`, `queueResearch {nodeId}`, `cancelResearch {nodeId}`, `setResearchBudget {usdPerMonth}`; `selectSuppliers` acepta `inverterId?`, `logisticsId?`.

### Selectores (`selectorsBusiness.ts`)
- `selectOpportunities(state, ctx, {includeClosed?})` → `OpportunityView[]`: cliente, tipo, contrato, MW, años, unidad, tecnologías (modelada/desbloqueada), tope (si es público), referencia, fechas, garantías, costo de preparación, pesos, requisitos, `canBid {ok, techId, blockers}`, `myBid`, `result` (solo cerradas: ranking con precios).
- `selectBidQuote(state, ctx, oppId, {techId, projectId?, marginPct?, price?, deliveryMonths?, effort?, equipmentId?, epcId?})` → `BidQuoteView` (equilibrio, sugerido, CAPEX, FC, garantías, puntajes, plazo realista, `blockers`, `eligibleProjects`, puntaje estimado).
- `selectMyBids` → ofertas del jugador con estado, ranking y ganador.
- `selectContracts` → `ContractView[]`: estado, fechas (COD, plazo máximo, asignación), días a COD, atraso, garantía, multas, ingresos, proyecto vinculado (etapa, avance), EPC (avance, presupuesto, cobrado, margen esperado), `obligations` en texto.
- `selectCompetitors` → empresas (nombre, estrategia aparente, estado, reputación, experiencia, MW operando, proyectos visibles desde permisos con ubicación y avance, ofertas ganadas/perdidas, cuota de mercado) + resumen del jugador.
- `selectResearchTree` → presupuesto, activa (avance, ETA), cola, nodos (rama, costo, meses, meses con el presupuesto, prerrequisitos, estado `completado|en_curso|en_cola|disponible|bloqueado`, avance, bloqueos, texto de efectos, `modelPhase`).
- `selectSupplierCatalog` → proveedores (precio actual vs base, calidad, confiabilidad, plazo actual, cola, relación), índices por tecnología (equipos, EPC, cambio a 12 meses, CAPEX USD/kW actual), materiales, demanda, historial mensual.
- `selectBusinessSummary` → reputación, experiencia, caja en garantías, ofertas, contratos activos, presupuesto de I+D, patrimonio.
- `selectProjectDetail` agrega `suppliers.inverters`, `suppliers.logistics`, `contractId`; `SupplierOption.priceFactor` es ahora el precio actual (con `basePriceFactor`). `BalanceSheet` agrega `restrictedCashUsd`.

### Eventos (todos con `text` y `severity`)
`opportunityOpened, bidSubmitted, bidWithdrawn, bidResult {won, rank, winnerName, winnerPrice}, opportunityDeserted, contractSigned, contractProjectAssigned, contractFulfilled, contractTerminated, contractPenalty, guaranteeExecuted, guaranteeReleased, epcDelivered, epcUpdate, researchStarted, researchCompleted, researchSetback, researchCancelled, supplyPriceChange, competitorWonTender, competitorPlantOperational, competitorBankrupt`.

### Pedidos de la UI de la Fase 2 (agregados)
- `SimEvent.tick`: `step` y `applyCommands` lo ponen en todos los eventos (los de comandos, el día en que se aplicaron).
- `ProjectDetail.countryCode`; `ProjectSummary.stageProgress` (0–1: madurez del desarrollo, avance de obra, puesta en marcha, 1 en operación).
- `StudyOption.startDate`, `PermitOption.startDate`.
- `ProjectDetail.resource.monthlyMwh` y `operation.expectedMonthlyMwh`: `{month, p50Mwh, p90Mwh}[12]` con el perfil estacional del país (suma = energía anual; con degradación si opera). `expectedMonthlyProduction()` exportada.
- `operation.failureLog`: fallas pasadas con fecha, fracción, días y costo (el estado guarda `operation.failures`, últimas 100; las partidas viejas no las traen).
- `previewFinancing(state, ctx, projectId, {lenderId, debtFraction, partnerShare})` → `FinancingPreview`: presupuesto, deuda dimensionada por ese banco (mismo cálculo que el cierre: `bankDebtSizing`), qué la limita, tasa, plazo, DSCR, comisión, asesores, aporte propio y del socio, prima del socio, caja neta propia, probabilidad, días de due diligence, si queda bajo el mínimo del banco, TIR/VAN con esa estructura, bloqueos.
- **Viabilidad (bug corregido)**: el Monte Carlo suponía siempre un PPA de licitación (≈68 USD/MWh, 40 % de éxito) mientras la economía determinista usaba el spot (≈98) y, además, descontaba con la prima de riesgo de etapa (17,6 % en estudios) un riesgo que ya simula. Resultado: VAN esperado −1,5 M con 95 % de éxito y TIR P50 10,8 % frente a 15,2 %. Ahora: mismo precio que la economía (PPA firmado o en proceso; el canal de `opts.ppaChannelId` si se pide; si no, spot), tasa sin prima de etapa descontando desde el COD, y `npvDeterministicUsd` (misma base, sin azar) y `ppaChannelId` en el resultado. El VAN de `projectEconomics` sigue siendo el «ajustado por etapa» (más conservador): la UI debe comparar `npvExpectedUsd` con `npvDeterministicUsd`.

### Contabilidad
Conceptos nuevos: `ingresos_potencia, ingresos_epc, costos_epc, licitaciones, garantias_comision, garantias_ejecutadas, investigacion` (resultados) y `garantias` (caja inmovilizada, inversión).

## 9. Guardado
`SAVE_VERSION = 3`. Migración 2→3: `business` vacío, `market` sin inicializar, `competitors: []`, flujos `supply/tenders/business`. El mundo (IA incluida) se arma en el siguiente `step`/`applyCommands` con datos. `stateHash` ignora claves con valor `undefined` (JSON no las guarda).

## 10. Supuestos y límites
- Precios de referencia, garantías, pesos y frecuencias de licitaciones son aproximados (marcados `supuesto`).
- Los ofertantes externos son una distribución, no empresas simuladas.
- En los PPA corporativos toda la energía del proyecto se vende al precio del contrato (el proyecto debe tener 0,9–1,5× los MW pedidos).
- La potencia contratada no entra en `projectEconomics` (la UI muestra el contrato aparte).
- La obra EPC para terceros no espera la llegada de equipos (solo huelgas, lluvia y sobrecostos).
- La IA empieza sin plantas propias aunque tenga «experiencia» histórica (cuenta para el puntaje, no da ingresos). En las pruebas de balance (3 semillas × 10 años) quiebran algunas (sobre todo la agresiva), no la mayoría, y ninguna multiplica su capital sin límite.
- Panamá es el único país con datos: los mercados nuevos se investigan pero no se pueden usar hasta la Fase 4.
