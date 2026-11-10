# Motor — Fase 4: más tecnologías, más países, permisos distintos

Todo en `packages/sim` (lógica pura, determinista) y `packages/data` (YAML + Zod). La API de las fases 2 y 3 se mantiene: solo se agregó (campos opcionales, funciones nuevas, un parámetro opcional `to` en `previewSite`).

## 1. Arquitectura nueva

```
packages/sim/src
  tech/models.ts      modo económico por tecnología, geotermia (pozos), factor de sitio del CAPEX, perfiles, despacho térmico,
                      arbitraje de almacenamiento, H2, líneas, ESCO: productTerms() = precio del producto + combustible + despacho
  tech/siting.ts      evaluateSite(): restricciones públicas del sitio (tierra/mar, recurso mínimo, costa, profundidad, relieve, agua,
                      zona habilitada del país, tecnologías prohibidas, longitud de líneas) — la usan createProject, previewSite y la IA
  tech/capacityFactor.ts  + hidro (índice hidro × lluvia), CSP (múltiplo solar por horas de almacenamiento), térmicas, almacenamiento…
  market/macro.ts     tipo de cambio real por país (log-normal con reversión, deriva y shocks), nominal por PPP, combustibles indexados
  business/presence.ts  presencia por país (constitución + representante legal), acceso al mercado, países abiertos
  selectorsWorld.ts   catálogo de tecnologías, LCOE típico por país, ficha de país (permisos como grafo, ruta crítica), países, combustibles
packages/data
  markets.yaml        inflación del USD y 7 índices de combustibles (gas Henry Hub, GNL, carbón, fuel oil, uranio, biomasa, biogás)
  technologies/*.yaml 18 tecnologías nuevas (20 en total)
  countries/*.yaml    12 países nuevos (13 en total)
```

### Modos económicos (`techMode`)
| Modo | Tecnologías | Producto (MWh/año) | Precio sin contrato | Costo variable |
|---|---|---|---|---|
| generación | solar, eólica tierra/mar, geotermia, hidro pasada/embalse, CSP | energía | spot capturado | — |
| térmica | gas CC, carbón, petróleo, nuclear, SMR, biomasa, biogás | energía × despacho | spot × prima de captura | heat rate × combustible + CO2 × carbono |
| almacenamiento | baterías, bombeo | energía descargada | spot × factor punta | spot × factor valle ÷ eficiencia |
| hidrógeno | electrolizador | electricidad consumida | kg/MWh × precio del H2 | spot × factor de compra + agua |
| transmisión | línea, interconexión | energía transportada | peaje (+ 40 % del diferencial entre países) | pérdidas × spot |
| eficiencia | ESCO | MWh ahorrados | precio del ahorro | — (penalidad si no se llega al garantizado) |

La misma función (`productTerms`) la usan la operación diaria/mensual, `projectEconomics`, la cotización de ofertas, la vista previa y el catálogo. Solo generación y térmicas venden por PPA (`sellsEnergy`).

- **Despacho térmico**: `clamp((precio/costo marginal − 0,6)/0,8, 0,05, 1)` (0,4 en carga base). Con PPA despacha según el precio del contrato. Así el carbón casi no despacha en España (EU ETS 75 USD/t) y los motores de fuel oil son de punta.
- **Almacenamiento**: cicla (`ciclos_ano_max`) solo si `punta × eficiencia > valle`; degradación = calendario + ciclos × `degradacion_por_ciclo`.
- **Geotermia**: calidad del reservorio = (flujo de calor − 60)/(200 − 60). Pozo exploratorio seco 65 % → 22 % según la calidad (Olkaria ≈ 25 %), baja entalpía 25 % → 10 %, MW por pozo 2 → 8. Pozos de desarrollo: secos × 0,55 (IFC 2013). El CAPEX base supone 5 MW/pozo: `siteCapexFactor` lo ajusta con la estimación. Estudio `perforacion_exploratoria` (3 pozos, ~15 MUSD): sortea los pozos con el recurso REAL; si los 3 salen secos ⇒ hallazgo `reservorio_no_comercial` (mitigable con otra campaña, 45 %). Al terminar el hito `perforacion` se perforan los pozos reales: los secos y la diferencia de MW por pozo son sobrecosto (evento `wellsDrilled`).
- **Hidro**: FC = fc_min + (fc_max − fc_min)·(índice·(lluvia/1500)^0,15/100)^0,8; perfil mensual fuerte por país (`perfil_recurso_mensual.hidro`); el embalse mezcla 60 % del perfil de precios (regula y vende en meses caros). Variabilidad interanual 13 %.
- **CSP**: múltiplo solar = 1,2 + 0,12·horas; FC = mín(0,65, SM·DNI·0,62/22,8). 10 h a DNI 8 ⇒ ≈ 52 %.
- **Eólica marina**: misma curva que en tierra con turbina de 15 MW; solo en el mar a 8–150 km de la costa de un país con datos (`ResourceGrid.nearestCountry`); profundidad ≈ 1,5 m/km; flotante desde 60 m (+55 % CAPEX); +0,2 % de CAPEX por km sobre 30 km.
- **Líneas**: `createProject` acepta `toLat/toLon`; longitud = gran círculo × 1,15; CAPEX = subestaciones + `costo_usd_mw_km`·km. La interconexión exige que los extremos estén en países distintos y presencia en ambos.
- **ESCO**: el ahorro garantizado (85 % de la estimación de la auditoría) se fija al COD; si el ahorro real del mes es menor se paga la diferencia al precio del contrato (`savingsShortfall`, categoría `multas`).
- **Riesgos de obra por tecnología** (`riesgo_obra`): multiplican la probabilidad y magnitud de sobrecostos por hito y agregan paros técnicos mensuales. Nuclear ×3/×3 (Vogtle, Flamanville), embalses ×2/×2,2 (Ansar 2014), SMR ×2,5. Mismo sorteo en el Monte Carlo de viabilidad.

### LCOE típico (pruebas, `typicalEconomics`, 7 % real, sitio típico = percentil 75 de la capa en el país)
Solar CHL ≈ 58, eólica USA ≈ 56, geotermia KEN ≈ 77, hidro de pasada ≈ 67–81, embalse ≈ 91–110, CSP ≈ 150–220, eólica marina ≈ 120–128, biomasa/biogás ≈ 95–105, gas CC USA ≈ 45 (PAN con GNL ≈ 96), carbón USA ≈ 84, motores de fuel oil PAN ≈ 210 (despacho 29 %), nuclear ≈ 133–145, SMR ≈ 160–175, baterías (LCOS con carga) ≈ 190–250, bombeo ≈ 160–225, línea ≈ 9 USD/MWh transportado, ESCO ≈ 25 USD/MWh ahorrado, H2 ≈ 5–6,7 USD/kg. Todos dentro de Lazard LCOE+ 2024 / IRENA 2023 / NREL ATB 2024 / IEA (ver `test/phase4.test.ts`).

## 2. Países (12 nuevos + Panamá)
Costa Rica, Colombia, República Dominicana, Chile, México, Brasil, Kenia, Islandia, España, Indonesia, Filipinas y EE. UU. (solo Texas/ERCOT: `zona`). Cada YAML trae moneda con tipo de cambio (volatilidad, reversión, shocks), inflación, prima de riesgo país (Damodaran ene-2025, aprox.), impuestos, aranceles, incentivos, costo local, mercado (demanda, pico, spot, perfil, matriz, factores punta/valle, moneda de los contratos), estacionalidad del recurso, bancos, construcción (lluvias, huelgas, clima extremo), combustibles locales, carbono, tecnologías prohibidas, costos de expansión y **su propio grafo de permisos** con autoridades reales:

| País | Particularidades de permisos |
|---|---|
| Costa Rica | SETENA, elegibilidad del ICE (Ley 7200, cupo), concesión de agua MINAE; geotermia reservada al ICE y solo renovables privadas |
| Colombia | **Consulta previa** (Mininterior, 180–1.100 días, 55 % aprobado + 33 % info, hasta 3 pedidos), CAR (10–100 MW) o ANLA, concepto de conexión UPME (red saturada), subastas en pesos indexadas |
| Rep. Dominicana | MIMARENA, concesión provisional y definitiva (Poder Ejecutivo, lenta), licitaciones de EDEs |
| Chile | **SEIA**: DIA (< 200 MW) o EIA (grandes y obras mayores), derechos de agua DGA, autorización del Coordinador (art. 102), licitaciones de la CNE en USD |
| México | EVIS y consulta indígena (SENER), MIA (SEMARNAT), estudios del CENACE (largos), permiso de la CNE con la planeación vinculante de 2025, licencias municipales/estatales |
| Brasil | Licenciamiento en tres etapas (LP → LI; la LO no se modela), FUNAI/INCRA, parecer de acceso del ONS, outorga de ANEEL, leilões en reales; nuclear prohibida (monopolio) |
| Kenia | NEMA, tierras comunitarias, EPRA, licencia geotérmica, PPA con KPLC (cupos tras la moratoria) |
| Islandia | **Rammaáætlun** (Plan Maestro del Parlamento, 540–2.200 días, 50 %), Skipulagsstofnun, Orkustofnun; sin fósiles ni nuclear |
| España | Concurso de acceso y conexión (REE, garantía), DIA, AAP → AAC (RD 1955/2000, RD-ley 23/2020), subastas REER en EUR; EU ETS; sin nuevo carbón ni nuclear |
| Indonesia | AMDAL, uso de bosque (PPKH), WKP geotérmica por licitación, IUPTL, PLN comprador único con tope (Perpres 112/2022) |
| Filipinas | Contrato de servicio del DOE, **FPIC** (NCIP, muy incierto), ECC (DENR), COC de la ERC, GEA en pesos; tifones |
| EE. UU. (Texas) | Cola de interconexión de ERCOT (≈ 2 años), PUCT, TCEQ/USFWS, FAA, NRC (nuclear), BOEM (eólica marina, 30 % por la política de 2025); ITC 30 % (IRA) |

Panamá agrega: EIA cat. III mayor, concesión de agua, concesiones hidro y geotérmica, licencia térmica, concesión marítima (AMP), servidumbres y autorización de interconexión (CRIE/SIEPAC); nuclear prohibida.

## 3. Expansión
- Para operar en un país hace falta su nodo de I+D (`mercado_*`) **y** presencia: comando `openPresence {countryCode}` (constitución: costo + días; luego representante legal mensual, categoría `presencia`). `closePresence` solo sin proyectos ni contratos activos. El país de origen siempre está abierto. `Presence.level = 'representante'` (Fase 6: `'oficina'`).
- `createProject` y `submitBid` exigen acceso (`countryAccessBlockers`).
- **Oportunidades**: los tipos de cliente de un país solo se generan si algún actor (jugador o IA activa) tiene presencia u origen allí (`openCountries`). 16 tipos nuevos: una subasta pública por país y llave en mano industrial (solar, baterías, biogás, eficiencia/ESCO) en COL, MEX, BRA y ESP.
- **IA**: `expansion: {paises, caja_min_usd}` en `competitors.yaml` (Solaris → COL, CHL; Meridian → CRI, DOM). Con el mercado investigado y caja, emite `openPresence`; luego crea proyectos especulativos en sitios candidatos de esos países (validados con `evaluateSite`). Mismos comandos y reglas que el jugador.

## 4. Riesgo cambiario e inflación
- Estado: `market.fx[iso3]` (tipo de cambio real), `market.fuels[id]`, `market.macroHistory` (120 meses). Flujos RNG nuevos: `fx`, `fuels`.
- `fxNominal = usd_por_unidad₀ · real · ((1+π_USD)/(1+π_local))^años` (moneda fija al USD ⇒ constante).
- En USD: spot = spot₀ · perfil · (1 + π_USD)^años · real (`inflacion_usd_anual`, derivada al cargar: la local si la moneda está fija). Costos de operación: inflación USD × (1 + fracción local · (real − 1)).
- PPA y contratos en moneda local (`moneda: local` en el canal o el tipo de cliente; por defecto `mercado.moneda_contratos`): precio en USD × `fxNominal(hoy)/fxNominal(firma)`; en la economía, indexación efectiva en USD = (1+i)(1+π_USD)/(1+π_local) − 1. La deuda siempre es en USD.
- Evento `currencyShock` (si algún actor está en el país) y `fuelPriceChange`.

## 5. API nueva para la UI
### Comandos
`openPresence {countryCode}`, `closePresence {countryCode}`; `createProject` acepta `toLat?`, `toLon?` (líneas e interconexiones).

### Selectores
- `selectTechCatalog(state, ctx, {countryCode?})` → por tecnología: modo, `visualKind`, capa, `unlocked` + nodo de I+D, parámetros (CAPEX, O&M, FC, vida, obra, emisiones, escala, heat rate, combustible, horas y eficiencia de almacenamiento, H2, costo de línea, peaje, ESCO), restricciones de sitio, riesgos y `byCountry[]` (permitida o motivo, `typical`: recurso, FC, CAPEX USD/kW, LCOE, LCOH, TIR, combustible, despacho, precio).
- `selectCountrySheet(state, ctx, iso3)` → desbloqueo, presencia (estado, costos, días, bloqueos), moneda (fija o no, USD por unidad al inicio y hoy, índice real, volatilidad, shocks, moneda de contratos, historial), macro, mercado (spot y perfil mensual, punta/valle, matriz), estacionalidad, impuestos, incentivos, costos, carbono, combustibles, restricciones, zona, riesgos de obra, bancos, canales de PPA, `permits: {nodes, edges}` (grafo) y `permitPaths` (ruta crítica esperada y probabilidad de aprobar todo por tecnología).
- `selectCountries(state, ctx)` → lista con presencia, spot, moneda, riesgo, proyectos propios y oportunidades abiertas.
- `selectFuelMarkets(state, ctx)` → precios e historial de combustibles.
- `previewSite(state, ctx, techId, mw, lat, lon, to?)` → además: `countryName`, `layer`, `visualKind`, `errors[]`, `accessBlockers[]` (I+D/presencia), `restrictions[]`, `site` (lluvia, relieve, distancia a la costa, profundidad, índice hidro, biomasa, `to.km`), `capexUsdKw`, `siteCapexFactor`, `lcoeUsdMwh`, `irrEquity`, `lcohUsdKg`, `fuelCostUsdMwh`, `dispatch`, `techUnlocked`.
- `ProjectSummary.visualKind` y `countryCode`; `visualKindOf(tech)`. Mapeo a `PlantKind`: campo `visual` del YAML (`gas_natural→gas`, `eolica_marina→eolica_mar`, `hidrogeno_verde→hidrogeno`, `interconexion→linea_transmision`, `eficiencia_energetica→eficiencia_industrial`; el resto igual al id).
- `Economics` agrega `mode`, `dispatch`, `fuelCostUsdMwh`, `carbonCostUsdMwh`, `co2TPerMwh`, `lcohUsdKg?`.
- Utilidades: `evaluateSite`, `typicalEconomics`, `permitGraph`, `expectedPermitPath`, `productTerms`, `geoWellProbabilities`, `fxNominal`, `fxReal`, `projectMonthly`/`projectDaily`.

### Eventos
`presenceRequested`, `presenceOpened`, `presenceClosed`, `currencyShock`, `fuelPriceChange`, `wellsDrilled` (proyecto), `savingsShortfall` (proyecto); `constructionDelay` con `reason: 'tecnico'`.

### Contabilidad
Categorías nuevas: `combustible` (combustible, energía comprada, pérdidas), `carbono`, `presencia`.

## 6. Guardado
`SAVE_VERSION = 4`. Migración 3→4: `business.presence = {}` (jugador y competidores), flujos `fx` y `fuels`. Tipos de cambio e índices se inicializan en 1 en el próximo `step`/`applyCommands` (`ensureMacro`). `Site.extras`, `PpaContract.currency/fxAtSigning`, `Construction.wells`, `Operation.guaranteedMwhYear/monthFuelUsd/monthCo2T` son opcionales.

## 7. Supuestos y límites
- Datos de países aproximados (2024–2025) y marcados `fuente`/`supuesto`; los marcos legales citados deben verificarse fuera del juego.
- Sin mercado horario: punta/valle son factores por país; el despacho térmico es mensual por margen (la Fase 5 traerá el merit order).
- Inflación por país determinista; la incertidumbre macro está en el tipo de cambio real (con shocks) y en los combustibles.
- Profundidad del mar aproximada por la distancia a la costa; geotermia con el flujo de calor de la grilla como indicador de calidad.
- Nuclear solo en México y Texas (en el resto prohibida por ley o sin regulador). Islandia sin fósiles.
- El ESCO se modela como proyecto propio (la ESCO invierte y cobra el ahorro); el llave en mano industrial va por EPC para terceros.
- La venta de proyectos merchant en Panamá (spot ≈ 95) es muy rentable: la prueba de balance de la IA ahora exige máximo < 12× y mediana < 4× del capital inicial (antes < 6×), porque las trayectorias de licitaciones cambian con la expansión.
- Bancos: un arbitraje de baterías puro no consigue deuda (DSCR); hace falta capital o un contrato de potencia.
