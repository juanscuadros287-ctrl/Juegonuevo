# Plan de arquitectura y roadmap — Simulador de empresa de energía global

> Nombre provisional: **Voltaje** (se cambia en `packages/data/game.yaml`).
> Estado: **Fase 0 aprobada** (stack aprobado, país inicial Panamá, repo propio).

---

## 1. Stack final

| Capa | Elección | Por qué |
|---|---|---|
| Lenguaje | TypeScript 5 (strict) | Un solo lenguaje para motor, UI y herramientas. |
| Motor de simulación | TS puro, sin DOM, corre en un **Web Worker** | Determinista, testeable, no bloquea los 60 fps. |
| 3D | Three.js (globo, capas, plantas low‑poly generadas por código) | Ligero y sin assets externos al inicio. |
| UI de gestión | React 18 + Zustand (solo estado de UI) + ECharts (gráficas) | Tablas, paneles y gráficas densas son mucho más fáciles en web que en Godot. |
| Empaquetado Mac | **Tauri 2** (Apple Silicon, `.app` / `.dmg` ~10 MB) | Nativo y pequeño; Electron solo si Tauri falla. |
| Datos | YAML editables + validación con **Zod** al cargar | Error claro si un archivo de datos está mal. |
| Pruebas | Vitest (motor), Playwright (humo de UI y capturas) | |
| Build | Vite + npm workspaces | |

**Sobre Godot:** tu otro juego (Dinastía) ya usa Godot, pero aquí no lo recomiendo: este juego es sobre todo UI de gestión (tablas, gráficas, formularios de oferta), y eso en la web es mucho más rápido de construir.

**Nota Mac:** el `.app` de Tauri se compila en macOS. Lo dejo listo con GitHub Actions (runner `macos-14`, Apple Silicon) para generar el `.dmg` en cada fase. Mientras tanto el juego también corre en el navegador (`npm run dev`). La app va sin firma de Apple: la primera vez se abre con clic derecho → Abrir.

---

## 2. Estructura del repo

```
energia/
├─ CLAUDE.md                  arquitectura, decisiones, estado (se actualiza cada fase)
├─ PLAN.md                    este documento
├─ packages/
│  ├─ sim/                    MOTOR (lógica pura, sin gráficos)
│  │  ├─ src/
│  │  │  ├─ core/             reloj, RNG con semilla, comandos, eventos, guardado
│  │  │  ├─ world/            grilla de recursos, países, clima
│  │  │  ├─ tech/             tecnologías, curvas de costo, degradación
│  │  │  ├─ project/          máquina de estados del proyecto, estudios, permisos
│  │  │  ├─ finance/          VAN, TIR, LCOE, WACC, deuda, estados financieros
│  │  │  ├─ market/           demanda, precio spot, PPA, despacho
│  │  │  ├─ supply/           proveedores, EPC, logística
│  │  │  ├─ ai/               competidores
│  │  │  ├─ company/          equipo, reputación, oficinas, I+D
│  │  │  └─ events/           eventos del mundo
│  │  └─ test/
│  └─ data/                   DATOS EDITABLES (YAML + esquemas Zod)
│     ├─ technologies/*.yaml  CAPEX, O&M, FC, vida útil, degradación, plazos, emisiones + fuente
│     ├─ countries/*.yaml     riesgo, inflación, FX, aranceles, mercado, permisos
│     ├─ permits/*.yaml       plantillas de permisos por país
│     ├─ studies.yaml, suppliers.yaml, events.yaml, research.yaml, staff.yaml
│     └─ resources/           grilla de recursos precomputada (binario compacto)
├─ apps/game/                 RENDER + UI (Three.js + React), sin lógica de juego
│  ├─ src/globe/              globo, capas, cámara, sitios
│  ├─ src/models/             modelos low‑poly procedurales por tecnología y avance
│  ├─ src/ui/                 paneles, tablas, gráficas
│  ├─ src/theme/              tokens de color, materiales, tipografía (estilo cambiable)
│  └─ src-tauri/              empaquetado Mac
└─ tools/                     scripts que generan la grilla de recursos desde datasets
```

---

## 3. Arquitectura del motor

**Regla de oro:** la UI nunca cambia el estado directamente. Todo pasa por **comandos**.

```
UI / IA ──comando──▶ Worker (sim) ──▶ validar ──▶ aplicar ──▶ nuevo estado + eventos
                          ▲                                        │
                          └──────── tick(día) ◀── reloj ◀──────────┘
UI ◀── snapshot (solo lectura) + eventos (notificaciones)
```

- **Estado**: un objeto plano serializable (`GameState`). Guardar = JSON comprimido del estado + semilla + versión. Cargar = validar y migrar si cambió la versión.
- **Determinismo**: RNG con semilla (PCG32), sin `Date.now()` ni `Math.random()` en el motor. Misma semilla + mismos comandos ⇒ mismo resultado (hay prueba de esto). Cada subsistema usa su propio flujo de RNG para que añadir un sistema no cambie los demás.
- **Tiempo**: 1 tick = 1 día. Velocidades: pausa, ×1, ×2, ×4, ×8. Contabilidad mensual. El mercado eléctrico se simula con **días representativos** (12 meses × 24 h = 288 horas por año y país, más variación de clima), suficiente para precio spot por hora y despacho sin coste de CPU excesivo.
- **Comandos compartidos**: los competidores IA usan exactamente los mismos comandos y las mismas reglas que tú. Nada de trampas.
- **Información incompleta**: el recurso "real" de un sitio está oculto. Lo que ves es una estimación con incertidumbre (P50/P90) que se reduce con estudios (ej. solar: satélite ±8–10 % → medición en sitio ±3–5 %). La producción real usa el valor oculto.

### Ciclo de proyecto (máquina de estados)

```
Oportunidad → Prospección → Medición de recurso → Prefactibilidad → Factibilidad
→ EIA + estudios de red → Permisos (grafo por país) → Cierre financiero
→ Construcción (hitos) → Puesta en marcha (COD) → Operación → Repotenciación / Desmantelamiento
```

Cada etapa define en datos: **costo, duración (distribución), requisitos, resultados posibles con probabilidad** y modificadores (equipo, estudios previos, reputación, país). En cada puerta decides: avanzar, pausar, vender el proyecto o abandonarlo (con costo hundido).

- **Permisos**: grafo de dependencias por país (ej. la licencia ambiental exige EIA; la conexión exige estudio de red; algunos corren en paralelo). Cada uno con costo, duración, probabilidad de aprobación, rechazo o pedido de información adicional.
- **Comprobar viabilidad antes de comprometerte**: botón que corre 500 simulaciones Monte Carlo (en un RNG aparte, no altera la partida) y muestra probabilidad de llegar a COD, plazo P50/P90, costo P50/P90 y TIR esperada.
- **Finanzas**: WACC = tasa libre de riesgo + prima de riesgo país + prima de tecnología/etapa. Deuda, equity, banca de desarrollo, bonos verdes, subsidios y garantías bajan la tasa o el riesgo, cada uno con condiciones y costo.

### Economía
- Moneda interna USD nominal; cada país tiene moneda local, inflación y tipo de cambio con deriva aleatoria. Ingresos en moneda local y deuda en USD crean riesgo cambiario real.
- Curvas de costo por tecnología (aprendizaje) + índices de materiales (acero, cobre, polisilicio, litio) y combustibles (gas, carbón, petróleo).
- Estados financieros de la empresa: P&G, flujo de caja, balance, deuda, covenants. Quiebra si te quedas sin caja y no puedes refinanciar.

---

## 4. Mapa y recursos

- **Grilla global 0,5° × 0,5°** (~260 mil celdas, ~70 mil en tierra). Por celda: irradiación (GHI y DNI), viento a 100 m (tierra) y mar adentro, flujo de calor geotérmico, índice hidro (escorrentía × pendiente), biomasa (productividad primaria), estrés hídrico, áreas protegidas, densidad de población, país. Empaquetado en binario (~3–5 MB).
- **Fuentes**: NASA POWER (solar y viento, abierto), Global Solar Atlas y Global Wind Atlas (referencia de calibración), base de datos de flujo de calor IHFC, HydroSHEDS, MODIS NPP, WDPA, Natural Earth (fronteras, dominio público). Si un dataset no se puede descargar desde este entorno, uso una aproximación documentada (latitud, clima, relieve) y lo marco en el archivo como `aproximado`.
- **Zoom cercano**: dentro de una celda la variación del sitio se genera con ruido determinista por celda (marcado como sintético), para que dos sitios vecinos no sean idénticos.
- **Globo**: esfera low‑poly con países extruidos y sombreado plano; las capas son texturas de color sobre el globo con leyenda. Los sitios y plantas aparecen al acercarse.

---

## 5. Realismo de los datos

Cada valor en YAML lleva `fuente:` y, si es supuesto, `supuesto:` con la razón. Fuentes principales: NREL ATB 2024, IRENA *Renewable Power Generation Costs* 2023, Lazard LCOE+ 2024, IEA WEO, datos de reguladores nacionales. Ejemplo:

```yaml
id: solar_fv_utility
capex_usd_kw: { min: 650, base: 850, max: 1300, fuente: "IRENA 2023 / NREL ATB 2024" }
om_fijo_usd_kw_ano: { base: 12, fuente: "NREL ATB 2024" }
degradacion_anual: { base: 0.005, fuente: "Jordan & Kurtz, NREL 2013" }
vida_util_anos: 30
construccion_meses: { min: 8, base: 12, max: 20 }
emisiones_gco2_kwh: 0
```

El año de inicio por defecto es **2026** con costos actuales.

---

## 6. Pruebas del motor

- Finanzas: VAN, TIR, LCOE y amortización contra valores calculados a mano / hojas de referencia.
- LCOE de cada tecnología cae dentro del rango de NREL/IRENA para un sitio típico.
- Permisos y estudios: con 10 000 corridas, la tasa de aprobación converge a la probabilidad configurada; el buen equipo la mejora en la magnitud esperada.
- Determinismo: misma semilla + comandos ⇒ mismo hash del estado tras 10 años simulados.
- Guardar → cargar → seguir = mismo resultado que sin guardar.
- Balance: proyectos típicos dan TIR realistas (ej. solar en buen sitio 7–12 % nominal); una empresa pasiva no se enriquece; una que sobreapalanca puede quebrar.
- Validación de todos los YAML contra sus esquemas.

---

## 7. Roadmap por fases

Cada fase termina con: el juego corre y se juega, pruebas en verde, `CLAUDE.md` actualizado, capturas, commit y push.

### Fase 1 — Globo, capas, tiempo, guardado
- Monorepo, Vite, React, Three.js, Tauri, CI de Mac (`.dmg`).
- Globo 3D con rotación, zoom e inercia; fronteras de países; clic en zona → ficha de recursos de la celda.
- Capas: solar, viento (tierra y mar), geotermia, hidro, biomasa, con leyenda y conmutador.
- Grilla de recursos generada por `tools/` (primero solar y viento reales; el resto puede empezar aproximado).
- Reloj: pausa y velocidades, fecha, barra superior.
- Guardado/carga (varias ranuras, autoguardado) y menú principal.
- Tema visual centralizado.
- **Jugable**: explorar el mundo, ver recursos, correr el tiempo, guardar y cargar.

### Fase 2 — Núcleo económico + 1 país + solar y eólica
- Empresa con caja inicial pequeña; país inicial con mercado, permisos y moneda.
- Elegir sitio → crear proyecto propio → ciclo completo: estudios (con fallos y resultados peores), permisos con grafo, financiación (deuda/equity), construcción por hitos (retrasos, sobrecostos), operación (producción por recurso real, degradación, fallas).
- Venta a precio regulado/PPA simple (el spot completo llega en la Fase 5).
- Panel del proyecto: línea de tiempo, costos, riesgos, VAN/TIR, verificador de viabilidad Monte Carlo.
- Panel de empresa: P&G, flujo de caja, deuda, quiebra.
- Modelos 3D de planta solar y parque eólico que crecen con la obra.
- **Jugable**: desarrollar, financiar, construir y operar una planta solar o eólica y ganar o perder dinero.

### Fase 3 — Licitaciones, clientes, proveedores, IA, investigación
- Licitaciones públicas y solicitudes de privados; armas la oferta (precio, plazo, margen, garantías) y compites. Adjudicación por precio + puntaje técnico + reputación.
- Proveedores de equipos, EPC y logística con precio, calidad y confiabilidad distintos; aranceles y tiempos de entrega.
- 3–5 competidores IA con estilos distintos (agresivo en precio, conservador, estatal, especialista).
- Árbol de I+D: tecnologías, tipos de estudio, mercados, tipos de contrato, eficiencia y costos.

### Fase 4 — Más tecnologías y países
- Geotérmica (pozos que pueden salir secos), hidro (pasada, embalse, bombeo), CSP, biomasa, biogás, baterías, gas, carbón, petróleo, nuclear y SMR, hidrógeno verde, líneas de transmisión, eficiencia energética y llave en mano para industria.
- 8–12 países con sistemas de permisos distintos (ej. consulta previa, concesiones de agua, subastas).
- Modelos 3D de cada tecnología.

### Fase 5 — Tu planta en el mercado, spot, despacho, eventos
- Mercado por país: demanda horaria/estacional, curva de oferta (merit order) con tus plantas y las de la IA, precio spot, capacidad y servicios complementarios.
- Despacho: generar, almacenar (baterías, bombeo, hidrógeno) o vender según precio, demanda y clima; reglas automáticas configurables.
- Interconexiones entre países.
- Eventos: crisis petrolera, cambios de gobierno y regulación, subsidios, guerras, desastres, pandemias, avances tecnológicos, caídas de precio de equipos.

### Fase 6 — Equipo, reputación, expansión, pulido
- Contratar ingenieros, geólogos, abogados ambientales, financieros y gerentes de proyecto, con habilidades y salario, y efecto medible en probabilidad, costo y tiempo.
- Reputación con gobiernos, clientes y comunidades.
- Oficinas por país/región (requisito para operar allí, con costo fijo).
- Balance general con simulaciones largas automáticas, pulido visual, sonido, tutorial opcional.

---

## 8. Decisiones que tomé (cámbialas si quieres)
- Nombre provisional "Voltaje"; UI en español (con textos en archivos para traducir después).
- Año de inicio 2026, costos actuales.
- Plantas modeladas por código (sin assets descargados) para poder cambiar el estilo fácil.

## 9. Decisiones del usuario (2026-11-03)
1. Stack aprobado: TypeScript + Three.js + React + Tauri.
2. País inicial: **Panamá**.
3. Repo propio (separado de Dinastía).
