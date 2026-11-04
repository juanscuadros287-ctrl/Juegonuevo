# Motor — Fase 2: núcleo económico, Panamá, solar FV y eólica en tierra

Todo vive en `packages/sim` (lógica pura, determinista) y `packages/data` (YAML + Zod). Sin DOM, sin `Math.random`, sin `Date.now`.

## 1. Contexto y API

```ts
interface SimContext { data: SimData; grid?: ResourceGrid }   // no se guarda; se reconstruye al cargar
step(state, commands, ctx?): SimEvent[]                        // 1 día
applyCommands(state, commands, ctx?): SimEvent[]               // en pausa
```
- `ctx.data` = `gameData.simData` (de `@voltaje/data`).
- `ctx.grid` hace falta solo para `createProject` (lee el recurso de la celda). Sin grilla el tiempo corre igual y `createProject` se rechaza con mensaje.
- Sin `ctx` solo corren el calendario y los gastos fijos (compatibilidad con pruebas mínimas).

### Comandos (`Command`)
| Comando | Efecto | Costo/tiempo |
|---|---|---|
| `createProject {techId, mw, lat, lon, name?}` | proyecto propio en una celda | prospección (8 000 USD) |
| `commissionStudy {projectId, studyId}` | encarga un estudio | `studies.yaml` |
| `applyPermit {projectId, permitId}` | solicita un permiso (respeta el grafo) | `countries/PAN.yaml` |
| `seekPpa {projectId, channelId}` | `licitacion_etesa` o `gran_cliente` | oferta + espera, puede fallar |
| `mitigateFinding {projectId, findingId}` | intenta resolver un hallazgo que bloquea | costo + días, puede fallar |
| `selectSuppliers {projectId, equipmentId, epcId}` | proveedor de equipos y EPC | define el presupuesto |
| `arrangeFinancing {projectId, lenderId, debtFraction, partnerShare}` | due diligence y cierre financiero | asesores + comisión; puede fallar. `debtFraction = 0` ⇒ cierre inmediato solo con capital |
| `startConstruction {projectId}` | inicia la obra | exige cierre financiero y sin hallazgos abiertos |
| `setMaintenancePolicy {projectId, policy}` | `preventivo` / `correctivo` | O&M vs fallas |
| `sellProject {projectId}` | busca comprador (45–150 días) | 2 % de comisión; puede fallar |
| `abandonProject {projectId}` | castiga lo invertido; prepaga la deuda | — |
| `decommissionProject {projectId}` | desmantela una planta | % del CAPEX |

### Selectores (solo lectura, no usan RNG)
- `selectProjects(state, ctx): ProjectSummary[]` — lista con etapa, `buildProgress` 0–1 (modelos 3D), siguiente paso, FC P50, TIR/VAN estimados, avisos.
- `selectProjectDetail(state, ctx, id): ProjectDetail` — línea de tiempo (pasado + planificado), estudios/permisos disponibles con costo, duración, probabilidades y bloqueos, hallazgos, canales de PPA, prestamistas, proveedores, construcción (hitos), operación (historial mensual, FC real de 12 meses), deuda, costos incurridos y por venir, `economics` (VAN/TIR/LCOE/DSCR), probabilidad de éxito, valor de venta, riesgos, `canFinance` / `canStartConstruction`.
- `selectCompanyFinancials(state, ctx)` — estados mensuales (P&G + flujo de caja), mes en curso, balance, últimos 12 meses, pérdidas fiscales, crédito fiscal, riesgo de quiebra y meses de caja.
- `previewSite(state, ctx, techId, mw, lat, lon)` — antes de crear: recurso de la celda ± σ, FC P50/P90, CAPEX, terreno.
- `checkViability(state, ctx, projectId, {runs?, seed?})` — Monte Carlo (ver §7).
- `STAGE_LABELS`, `CATEGORIES` (etiquetas de conceptos contables).

### Eventos (`SimEvent`)
Todos los de proyecto llevan `projectId`, `text` (español) y `severity` (`info|bueno|malo`):
`projectCreated, studyStarted, processStarted, studyCompleted{outcome}, findingDiscovered, findingResolved, permitRequested, permitInfoRequested, permitDecided{approved}, ppaResult, financingResult, constructionStarted, equipmentArrived, milestoneCompleted, constructionDelay, costOverrun, qualityDefect, commissioningStarted, projectOperational, plantFailure, ppaPenalty, saleStarted, projectSold, saleFailed, projectAbandoned, projectDecommissioned`.
De empresa: `newMonth, newYear, commandRejected, cashNegative{monthsNegative}, emergencyCredit, bankruptcy`.

## 2. Ciclo de proyecto

```
identificado → estudios → permisos → cierre_financiero → construcción → puesta_en_marcha → operación
                                        (vendido / abandonado / desmantelado en cualquier momento)
```
La etapa se **deriva** del avance (estudios y permisos corren en paralelo cuando el grafo lo permite):
`cierre_financiero` = todos los estudios requeridos hechos, todos los permisos aplicables aprobados y sin hallazgos abiertos.

- **Estudios** (`studies.yaml`): cada uno pertenece a un *grupo*; la tecnología pide grupos (`medicion_recurso, prefactibilidad, factibilidad, eia, conexion`). Un grupo se cumple con cualquier estudio aplicable (p. ej. solar: satelital o estación). Resultado al terminar: normal / peor (CAPEX × factor triangular) / bloqueo (hallazgo: arqueología, especie, comunidad, aves, tierra, suelo, red). EIA categoría I/II/III según MW (umbral supuesto).
- **Hallazgos**: bloquean permisos, financiamiento y obra. `mitigateFinding` cuesta y tarda; éxito con probabilidad `prob_exito_mitigacion`; si falla, se puede reintentar.
- **Permisos** (PAN.yaml): grafo por `requiere.estudios` (grupos de estudio) y `requiere.permisos` (grupos de permiso; los que no aplican al proyecto se ignoran). Decisión al vencer el plazo: aprobado / rechazado / info adicional (cobra y suma días automáticamente; tras `max_intentos_info` se renormaliza entre aprobado y rechazado). Rechazado ⇒ se puede volver a pedir si `reintentable`.
  Panamá: uso de suelo (municipio) → participación ciudadana (≥10 MW) → aprobación del EIA (MiAmbiente) ; viabilidad de conexión (ETESA) ; licencia (solar) o concesión (eólica) de ASEP ; contrato de acceso a la red (ETESA).
- **PPA**: licitación ETESA (15 años, ~68 USD/MWh, 40 % de éxito, multa si no hay COD en 36 meses) o gran cliente (10 años, ~78, ≤30 MW). Sin PPA se vende al spot.
- **Financiamiento**: banco comercial (SOFR+3,2 %, 14 años, DSCR 1,30 con PPA / 1,60 merchant, ≤70 %) o banco de desarrollo (SOFR+2,2 %, 18 años, DSCR 1,25, ≤75 %, exige PPA y medición con σ ≤ 3,5 %, mínimo 15 MUSD, más lento). Socio de capital opcional (≤80 %): pone su parte del equity y de los sobrecostos, paga una prima de desarrollo del 10 % de su aporte y cobra su parte de los dividendos.
- **Construcción**: duración triangular × factor de plazo del EPC; hitos con fracción de tiempo y costo; avance diario `1/plazo` (× 0,8 en meses lluviosos para hitos sensibles); hitos de montaje esperan los equipos (entrega con retraso si falla la confiabilidad del proveedor); huelgas y lluvias extremas paran la obra; sobrecosto por hito con `prob_sobrecosto_hito` del EPC (2–20 % del hito, lo paga el equity); defectos en la puesta en marcha según calidad (equipos 60 %, EPC 30 %).
- **Financiamiento de la obra**: el gasto mensual se paga con deuda en proporción `deuda/presupuesto` hasta el monto aprobado; el resto, equity (empresa + socio). Intereses durante construcción capitalizados en la deuda. En COD la deuda pasa a cuota francesa mensual.
- **Operación** (diaria, liquidación mensual):
  `E_día = MW·24·FC_real·perfil_mes·ruido·factor_año·(1−deg)^edad·disponibilidad`
  ruido ~ N(1, σ_diaria) (≥0,05), factor_año ~ N(1, σ_interanual) por año; fallas: Poisson diario con tasa `eventos_ano_por_mw·MW·factor_mantenimiento·(1+2·(1−confiabilidad))`, cada una saca una fracción por d días y cuesta `costo_por_kW_afectado`. Ingresos: PPA (indexado) mientras dure; después spot. Costos: O&M fijo (× política) + variable, seguro (0,3 % del activo), arriendo, reparaciones, intereses y amortización, depreciación lineal (20 años).
- Fin de vida: desmantelamiento automático (costo % del CAPEX).

## 3. Recurso oculto vs estimado
- `realFactor = 1 + σ_sitio·z`, `z ~ N(0,1)` truncada ±3, **determinista por (semilla, capa, sitio redondeado a 0,01°)** — no depende del orden de creación. σ_sitio: solar 7 %, viento 12 % (sobre la velocidad).
- Estimación inicial = valor de la celda con σ_sitio. Un estudio de medición da `medido = real·(1 + σ_estudio·z)` y reemplaza la estimación si su σ es menor. Satelital σ 4,5 %, estación 12 meses 2,5 %, mesoescala eólica 9 %, torre/LiDAR 3,5 %.
- P90 = P50·(1 − 1,2816σ). La producción usa siempre el real; selectores y viabilidad, solo la estimación. `Site.realFactor` y `Operation.fcReal` están en el estado (el guardado los necesita) pero ningún selector los expone.

## 4. Factor de capacidad
- **Solar FV** (base AC, seguidor de un eje): `FC = GHI·PR·[1 + γ(T_amb + 20 − 25)]·g_seg / 24`, PR = 0,84 (sin temperatura), γ = −0,35 %/°C, g_seg = 1,12. Panamá: 16,5–19,4 % (arco seco 18–19,4 %).
- **Eólica**: turbina de referencia 4,5 MW, rotor 155 m (≈240 W/m²), buje 110 m (cizalle α = 0,14), Cp 0,45, arranque 3 m/s, corte 25 m/s, Weibull k = 2 con `c = v̄/Γ(1+1/k)`, ρ corregida por temperatura, pérdidas 12 % (sin disponibilidad). Penonomé (6,45 m/s a 100 m): 34,7 %.
- La disponibilidad (mantenimiento programado + fallas) se aplica aparte (~98–99 %).

## 5. Costos
`CAPEX = base·MW·[%equipos·precio_prov·(1+flete)·(1+arancel+ITBMS si no exento) + %EPC·precio_EPC·costo_local + %otros]·factor_estudios`.
Panamá exime de arancel e ITBMS a solar (Ley 37/2013) y eólica (Ley 44/2011) — aproximado. Costo local de obra 1,05. Crédito fiscal 5 % de la inversión (usable hasta 50 % del impuesto de cada mes).

## 6. Finanzas
- `finance/math.ts`: `npv`, `irr` (rejilla de cambio de signo + bisección + Newton; `null` sin solución), `annuityPayment`, `amortizationSchedule`, `lcoe`, `crf`, `costOfEquity`, `wacc`, `debtCapacityFrench`, `percentile`.
- `finance/projectModel.ts`: modelo anual (t0 inversión; t1…vida). Impuesto 25 % con depreciación lineal y arrastre de pérdidas, separado sin deuda (flujo del proyecto) y con intereses (flujo del equity). `sizeDebt` = mín(apalancamiento máx., pedido, capacidad por DSCR con cuota francesa sobre el CFADS P90).
- Tasa de descuento: `ke = rf + β·ERP + prima país + prima de etapa + prima de tecnología` (rf 4,3 %, ERP 4,5 %, β 1, prima país 2,8 %; etapa 8 % identificado → 0 en operación; eólica +1 %). `WACC = E/V·ke + D/V·kd·(1−t)`.
- LCOE de referencia del modelo a 7 % real sin impuestos.
- **Estimaciones del proyecto** (`projectEconomics`): recurso P50 del jugador, CAPEX del presupuesto actual, PPA firmado o en proceso (si no, spot capturado), deuda dimensionada como lo haría el banco comercial si aún no hay cierre.
- **Spot** (`market/spot.ts`, interfaz `SpotMarket` para la Fase 5): media 95 USD/MWh × perfil mensual (seca cara, lluviosa barata) × inflación. Factor de captura = Σ precio·producción mensual (solar y viento producen más en la estación seca).
- **Empresa** (`finance/company.ts`): contabilidad consolidada por conceptos (`CATEGORIES`). Estudios y permisos se capitalizan en el proyecto (castigo si se abandona); opción de terreno y gastos fijos van a resultados. Cierre mensual: impuesto sobre la renta con arrastre de pérdidas y crédito fiscal; estado del mes (P&G, flujo operativo/inversión/financiamiento, caja y deuda al cierre); balance = caja + desarrollo + obras + plantas (neto) − deuda − participación de socios.
- **Quiebra**: si la caja cierra el mes en negativo se intenta un crédito de emergencia (14 %, hasta 50 % del valor neto de las plantas menos la deuda). Si no alcanza, cuenta un mes negativo; 3 meses seguidos ⇒ evento `bankruptcy`, `finance.bankrupt = true`, `step` deja de avanzar y todo comando se rechaza.

## 7. Verificador de viabilidad
`checkViability` corre N vidas (500 por defecto) del resto del ciclo con un RNG propio (`seedStream(seed, 'viabilidad')`; por defecto la semilla sale de partida + proyecto + día, así que el mismo día da el mismo resultado). No toca el estado. Por corrida: estudios restantes con dependencias y resultados (peor/bloqueo + 2 intentos de mitigación), permisos por el grafo con pedidos de información y un reintento, PPA (2 intentos o spot), financiamiento (2 intentos), construcción (lluvia, huelgas, clima, espera de equipos, sobrecostos por hito, defectos), recurso muestreado de la estimación del jugador. Devuelve `probCod`, meses a COD P50/P90, costo por gastar P50/P90, TIR de equity P50/P10, VAN esperado (las corridas fallidas restan su costo hundido) y causas de fracaso.

## 8. Guardado
`SAVE_VERSION = 2`. Migración 1→2: agrega `projects: []`, `nextProjectId: 1`, `finance` vacío (las partidas de la Fase 1 cargan y siguen).

## 9. Supuestos importantes y límites
- Números de Panamá (permisos, plazos, probabilidades, PPA, incentivos) son aproximados y están marcados `supuesto` en los YAML; las leyes citadas deben verificarse antes de usarse fuera del juego.
- El impuesto se calcula consolidado a nivel empresa (no por sociedad de propósito especial); la distribución al socio usa un impuesto del proyecto aislado.
- Merchant: el banco dimensiona con el spot capturado × 0,8. El spot de Panamá es alto (~95 USD/MWh) — vender sin PPA rinde más en promedio pero el banco presta menos.
- Una empresa con 750 kUSD no puede construir sola: necesita socio de capital, vender proyectos en desarrollo o empezar pequeño. Es deliberado.
- `credito_max_frac_impuesto` se aplica como 50 % fijo en el cierre mensual (igual en ambos incentivos actuales).
