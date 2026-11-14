# Motor — Fase 6: equipo, reputación, oficinas, expansión global y balance

Todo en `packages/sim` (puro, determinista) y `packages/data` (YAML + Zod, archivo nuevo `team.yaml`). La API de las fases
2–5 se mantiene: solo se agregó (campos opcionales, comandos, selectores, parámetros opcionales). `SAVE_VERSION = 6`.
Balance: ver `docs/BALANCE.md`.

## 1. Arquitectura nueva
```
packages/sim/src
  team/types.ts     Person, Candidate, Employee, TeamState, ReputationState, OfficeState, LaborMarket
  team/team.ts      salarios e indemnizaciones por país, oficinas (nivel, capacidad, costos, sede regional), reputación por eje
                    (repOf, changeRep, repCause, repFactor), puntaje por área y modificadores (permisos, estudios, obra,
                    financiamiento, ofertas, PPA, O&M, conflictos), mercado laboral, ensureTeam (inicialización perezosa)
  team/commands.ts  comandos del equipo, las oficinas y la inversión social
  team/tick.ts      avance diario (capacitación, mejoras de oficina), cierre de mes del actor (salarios, oficinas, moral,
                    renuncias, experiencia, conflictos y accidentes de obra, reputación) y del mundo (candidatos, invitaciones)
  ai/team.ts        decisiones de equipo y oficinas de la IA (y de los bots del arnés de balance)
  selectorsTeam.ts  vistas de la Fase 6
packages/data/team.yaml   roles, k de cada efecto, mercado laboral por país, nombres, oficinas, regiones, reputación,
                          riesgos de obra, equipos iniciales y objetivos de la IA
```
Flujos RNG nuevos: `labor` (mercado laboral, invitaciones) y `team` (moral/renuncias, conflictos, accidentes, ofertas,
capacitación). Orden del cierre de mes en `step`: … oportunidades → **mercado laboral e invitaciones** (`teamWorldMonthly`).
Cada actor cierra su equipo dentro de `actorMonthly` (`teamMonthly`). Las vistas de actor llevan `root` (la partida
completa, nunca se guarda) para las ofertas a personal de otras empresas.

## 2. Equipo
**Roles** (10): ingeniero eléctrico, civil, de recurso, geólogo/geofísico, abogado ambiental y regulatorio, especialista
social, financiero/estructurador, gerente de proyecto, comercial, analista de mercado. Cada rol aporta a una o más áreas
con un peso (`areas`) y tiene una capacidad de proyectos (`capacidad`).

**Puntaje por área y proyecto** (`areaScore`): sin personal propio = consultor externo (`puntaje_externo` 35), con el que
**todos los efectos valen 1** (los datos de países/tecnologías son los de un desarrollador típico con asesores externos;
así la IA sin equipo y las pruebas anteriores no cambian). Cada persona aporta
`habilidad × (0,85 + 0,15·mín(1, años/15)) × peso del rol × ubicación/idioma`, diluido hacia el externo según su carga:
`c = 35 + máx(0, aporte − 35) × mín(1, capacidad/carga)`. Puntaje = 35 + Σ pesos (1; 0,35; 0,15) × (c_i − 35), tope 100.
Ganancia `g = (puntaje − 35)/65 ∈ [0, 1]`. Cada efecto es `1 ± k·g` (acotado por construcción):

| Área (roles) | Efecto (k en `team.yaml → efectos`) |
|---|---|
| permisos (abogado, social, gerente) | aprobación ×(1 + 0,15g), rechazo ×(1 − 0,4g), pedidos de info ×(1 − 0,35g), plazo ×(1 − 0,2g) |
| social (especialista, abogado) | permisos sociales (consulta, tierras, participación): aprobación ×(1 + 0,25g) con g = 0,4·permisos + 0,6·social; conflictos de obra ×(1 − 0,6g) |
| recurso (ing. de recurso, geólogo) | hallazgos bloqueantes ×(1 − 0,3g), sorpresas de CAPEX ×(1 − 0,25g), σ de la medición ×(1 − 0,2g), pozos secos ×(1 − 0,25g) |
| obra (gerente, civil, eléctrico, geólogo) | prob. de sobrecosto por hito ×(1 − 0,35g), magnitud ×(1 − 0,25g), paros técnicos ×(1 − 0,3g), accidentes ×(1 − 0,5g) |
| finanzas (financiero) | spread ×(1 − 0,15g), asesores ×(1 − 0,3g), due diligence ×(1 − 0,25g) |
| ofertas (comercial, analista) | puntaje técnico +10g, preparación ×(1 − 0,25g), éxito del PPA ×(1 + 0,2g) (tope 95 %) |
| mercado (analista, comercial) | precio del PPA ×(1 + 0,04g) |
| operación (ing. eléctrico) | fallas ×(1 − 0,3g), costo de reparación ×(1 − 0,2g) |

La aprobación final de un permiso nunca pasa del 98 % (en cada decisión aprobado/(aprobado + rechazado) ≤ 0,98).
Ubicación: abogado y social fuera de su país ×0,6 (×0,8 con sede regional en la región); sin el idioma del país ×0,75
(×0,5 para abogado/social). Los mismos modificadores se aplican en la simulación (`project/tick.ts`, `project/commands.ts`)
y en el Monte Carlo de viabilidad (`project/viability.ts`).

**Carga**: asignada (`assignEmployee` con proyectos) = proyectos activos asignados; en la oficina (sin asignación) = todos
los proyectos de la empresa que necesitan su área principal hoy (desarrollo, obra u operación; ofertas abiertas para el comercial).

**Mercado laboral** (compartido): ≈ 7 candidatos por país abierto, renovados cada mes, vigencia 45–120 días; habilidad
triangular 20–50–92, experiencia correlacionada; idiomas (nativo + inglés con la probabilidad del país). Salario pedido =
salario base del país × rol × nivel(habilidad, años) × inflación del USD del país × (0,92–1,12). Cargas sociales por
país; reclutamiento = 20 % del salario anual; indemnización = meses por año (mínimo y tope) según la ley del país (México
mínimo 3 meses, España 33 días por año, EE. UU. a voluntad, etc.).

**Moral y rotación** (mensual): objetivo = 55 + 120·(salario/mercado − 1) − 25·sobrecarga + 5 con oficina; la moral recorre
el 30 % de la distancia. Renuncia = 0,6 %/mes + 8 %·((45 − moral)/45)². El mercado sube con la inflación: quien no recibe
aumentos se va. Las IA (y el jugador) pueden ofertar a personas de otras empresas (`poachEmployee`): acepta con
p = 3·(oferta/salario − 1,05) − (moral − 50)/100 ∈ [0; 0,85]; el honorario se paga aunque rechace. El dueño recibe el aviso.

**Equipo inicial**: el jugador arranca con un ingeniero de recurso y un gerente de proyecto; cada IA con 2–4 personas según
su estrategia. Su costo se **descontó de los gastos fijos** (que ya lo incluían): el gasto total no cambia.

## 3. Reputación (por eje)
- **Clientes** (global) = `business.reputation` (la reputación única de la Fase 3, que se mantiene como alias).
- **Gobierno** y **comunidad** por país (`business.rep`). Al migrar o empezar: los del país de origen = la reputación previa;
  un país nuevo empieza en 30.
- Causas (`team.yaml → reputacion.causas`): obra a tiempo (+2 gob, +1 com, +1 cli) o atrasada; permiso aprobado/rechazado;
  abandono (−2/−2; en obra −5/−4/−3); conflicto comunitario (−6 com); accidente (−3/−3); plantas operando (anual);
  despidos masivos; inversión social (+); contratos (los de la Fase 3, en clientes). Reversión 1 %/mes hacia 40; la oficina
  suma +0,1/mes (sede +0,2) con el gobierno. Registro de las últimas 80 causas e historial mensual.
- Efectos: licitaciones (la reputación del puntaje de experiencia es 0,6·clientes + 0,4·gobierno en públicas, 0,8·clientes +
  0,2·comunidad en privadas; +8 si es una invitación directa), permisos sociales ×f(comunidad) (±15 %), conflictos ×(2 − f)
  (±50 %), spread de bancos de desarrollo ×(2 − f(gobierno)) (±20 %), invitaciones directas.
- **Invitaciones directas**: con oficina local o sede y reputación (0,7·clientes + 0,3·gobierno) > 50, cada mes y país
  p = 4 %·(rep − 50)/50 de una solicitud privada solo para el invitado (casi sin ofertantes externos).
- **Conflictos y accidentes de obra** (mensual): 1,2 %/mes × (1 − 0,6·g social) × (2 − f comunidad); 0,3 %/mes × modificador de
  obra. Paran la obra y cuestan una fracción del presupuesto.
- `investInCommunity {countryCode, amountUsd}`: ≈ 40 kUSD por punto con rendimiento decreciente, tope 15 puntos/año/país.

## 4. Oficinas
| Nivel | Capacidad | Apertura | Mensual | Efectos |
|---|---|---|---|---|
| representante (presencia de la Fase 4) | 2 personas | constitución de la Fase 4 | representante de la Fase 4 | estudios y permisos +5 % (sin oficina local) |
| oficina local | 15 | 60 kUSD × índice, 60 días | 9 kUSD × índice | costo de desarrollo de referencia, +0,1 rep. gobierno/mes, invitaciones privadas, +5 moral |
| sede regional | 45 | 250 kUSD × índice, 120 días | 32 kUSD × índice | −3 % desarrollo, +0,2/mes, −3 % en los países vecinos de la región, abogado/social de la sede rinden ×0,8 en la región; exige ≥ 4 personas en el país |

El país de origen arranca con oficina local (su costo está en los gastos fijos). `Presence.level` es alias del nivel.
`closePresence` exige no tener personal contratado en el país.

## 5. IA
`decideTeam` (dentro de `decideCompetitor`): contrata hacia el objetivo de su estrategia (`team.yaml → ia.objetivos`: una
persona por cada N proyectos activos, roles en orden), una por turno y solo con caja para un año; sube el salario a quien
tiene moral baja y cobra bajo mercado; en crisis despide a la persona de menor habilidad por dólar; la agresiva y el fondo
ofertan a personal de otras empresas (perfil público: rol, habilidad, país); abre oficina local donde tiene ≥ 2 proyectos
(o la oficina está llena) y sede regional si es grande; las prudentes invierten en comunidades con obra y reputación baja.
Cambios de balance en `ai/brain.ts` (ver BALANCE.md): vende RTB solo con valor y elige el canal de PPA más probable.

## 6. API nueva para la UI
### Comandos
`hireCandidate {candidateId, salaryUsdMonth?}`, `fireEmployee {employeeId}`, `assignEmployee {employeeId, projectIds}` (vacío
= oficina), `setSalary {employeeId, salaryUsdMonth}`, `trainEmployee {employeeId}`, `poachEmployee {employeeId, salaryUsdMonth}`,
`upgradeOffice {countryCode}`, `downgradeOffice {countryCode}`, `investInCommunity {countryCode, amountUsd}`.

### Selectores (`selectorsTeam.ts`)
- `selectLaborMarket(state, ctx, {countryCode?})` → países (oficina, capacidad, personal) y candidatos: rol, habilidad,
  experiencia, idiomas, salario pedido, costo con cargas, mercado, reclutamiento, días restantes, áreas con habilidad
  efectiva, **impacto** (puntaje del área principal hoy y con la persona, con sus efectos), `canHire` + `blockers`.
- `selectTeam(state, ctx)` → plantilla, costo mensual, moral media, contrataciones/renuncias/despidos, historial y por
  persona: salario vs mercado, moral y su objetivo, riesgo de renuncia mensual, carga/capacidad/dilución, asignación,
  capacitación, indemnización, aporte por área y **por proyecto** (puntaje con y sin la persona); `areas[]` con puntaje,
  ganancia y efectos cuantificados (`EffectLine`: multiplicador y texto).
- `selectProjectTeam(state, ctx, projectId)` → puntaje por área con quién aporta, y los modificadores que se aplican hoy
  (permisos por autoridad, estudios, obra, financiamiento por prestamista, PPA, O&M, costo de desarrollo, prob. de conflicto).
- `selectWorkload(state, ctx)` → carga por persona y por proyecto (dedicados, oficina, puntajes por área).
- `selectReputation(state, ctx)` → clientes; por país gobierno y comunidad con sus efectos (aprobación social, conflictos,
  spread de banca de desarrollo, reputación en licitaciones públicas/privadas, prob. de invitación); causas recientes; historial.
- `selectOffices(state, ctx)` → por país: nivel, personal/capacidad, costo mensual, efectos, mejora en curso, opción de
  mejora (costo, mensual, días, capacidad, nuevo multiplicador de desarrollo, bloqueos) y de reducción, datos laborales.
- `selectCompanyOverview(state, ctx)` → países (oficina, proyectos, MW), MW por tecnología (operación, obra, desarrollo),
  balance, experiencia, plantilla y **ranking** contra los competidores (patrimonio y MW).
- Utilidades: `areaScore`, `areaEffectLines`, `permitModifiers`, `studyModifiers`, `buildModifiers`, `financeModifiers`,
  `bidModifiers`, `ppaModifiers`, `omModifiers`, `devCostMult`, `officeLevel`, `marketSalaryUsd`, `severanceUsd`, `repOf`,
  `blendedReputation`, `quitProbability`, `moraleTarget`, `invitationProb`, `hireBlockers`, `upgradeBlockers`.

### Pedidos de la UI de la Fase 4 (agregados)
- `CompetitorView.visibleProjects[].visualKind` y `countryCode`.
- `PermitGraphNode.excludes` (tecnologías excluidas).
- `permitPaths[].criticalPath`: ids de permisos de la ruta crítica, del primero al último.
- `ProjectSummary.to?: {lat, lon, km, countryCode?}` (extremo de líneas e interconexiones).
- `TypicalEconomics.lcoeRefUsdMwh` y `fcRef`: LCOE de las térmicas a plena carga del factor de referencia (gas en Chile
  dentro del rango Lazard; la prueba exige 45–115 USD/MWh); `lcoeUsdMwh` sigue siendo el del despacho previsto (alto donde casi no despacha:
  motores de fuel oil ≈ 550–600, gas con GNL caro). `EconomicsOptions.dispatchOverride`.

### Eventos
`employeeHired`, `hireRejected`, `employeeFired`, `employeeQuit` (`reason: 'moral' | 'oferta'`), `employeePoached`,
`poachRejected`, `employeeAssigned`, `salaryChanged`, `trainingStarted`, `trainingCompleted`, `officeUpgradeStarted`,
`officeChanged`, `reputationChanged` (eje, país, delta, causa), `communityInvestment`, `directInvitation`; de proyecto:
`communityConflict`, `constructionAccident`. `Opportunity.invitedActorId` (solicitud directa).

### Contabilidad
Categorías nuevas: `personal` (salarios + cargas, reclutamiento, capacitación, indemnizaciones), `oficinas`, `inversion_social`.

## 7. Guardado
`SAVE_VERSION = 6`. Migración 5→6: flujos `labor` y `team`; `market.labor` vacío ⇒ en el próximo `step`/`applyCommands`
`ensureTeam` crea el mercado laboral, los equipos iniciales (descontados de los gastos fijos) y la reputación por eje
(gobierno y comunidad del país de origen = reputación previa). Campos nuevos opcionales: `business.team/rep/offices`,
`Opportunity.invitedActorId`, `Presence.level: 'sede'`.

## 8. Rendimiento
10 años con 5 IA y los 13 países abiertos ≈ 2–4 s (prueba < 8 s). Arnés de balance: ≈ 1 s por partida de 15 años.

## 9. Supuestos y límites
- k de los efectos, salarios, cargas e indemnizaciones aproximados (`supuesto` con la ley o la referencia en `team.yaml`).
- Sin personal propio todo es neutro (consultor externo); el equipo nunca empeora por debajo de eso, salvo por la
  reputación (comunidad, gobierno), que sí puede castigar a una empresa desconocida.
- La IA ve el perfil público de las personas de otras empresas (rol, habilidad, país), nunca su salario ni su moral.
- La capacitación sube la habilidad con rendimiento decreciente; la experiencia sube 1 año por año.
- No hay convenios colectivos, huelgas internas ni bonos por desempeño.
