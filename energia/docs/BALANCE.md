# Balance global (Fase 6)

## Cómo se mide
- **Arnés**: `packages/sim/test/balance.ts`. El jugador juega solo con un **bot de estrategia simple** que usa exactamente la
  toma de decisiones de la IA (`decideCompetitor` + `decideTeam` sobre el estado del jugador, mismos comandos, misma
  información pública) contra las 5 IA. 15 años, partida estándar (Panamá, capital del `game.yaml`).
- **Pruebas**: `packages/sim/test/balance-strategies.test.ts` (parte de `npm test`, ≈ 15 s) exige las condiciones de abajo
  en ≥ 3 semillas por estrategia.
- **Reporte**: `npm run balance` (desde `energia/`; `BALANCE_SEEDS=1,2,…` y `BALANCE_YEARS=15` opcionales) imprime las
  tablas de este documento.

| Estrategia | Perfil del bot |
|---|---|
| pasivo | No hace nada: solo paga gastos fijos y su equipo inicial. |
| solar conservador | Solar FV en Panamá, 1 proyecto a la vez de 10–15 MW, proveedores de calidad, socio 60 %, deuda 60 %, busca PPA y vende el proyecto listo para construir solo si el comprador paga ≥ 1,1 × lo invertido. |
| agresivo apalancado | Solar y eólica, 2 proyectos a la vez de 20–50 MW, equipos baratos, deuda 80 %, oferta casi todo (también EPC) con margen de 3 %, reserva de solo 4 meses, construye y vende en crisis. |
| diversificado internacional | Fondo con equipo financiero; I+D de mercados (Centroamérica, Rep. Dominicana, Costa Rica, Colombia), se expande cuando tiene ≥ 2,5 MUSD, 1 proyecto a la vez de 15–30 MW, vende RTB con valor. |

## Condiciones exigidas (y resultado)
| Condición | Prueba | Resultado (6 semillas, 15 años) |
|---|---|---|
| Pasivo pierde dinero y quiebra en pocos años | quiebra en 3–8 años, patrimonio cae todos los años | 6/6 quiebran, años 5,6–6,9 |
| Conservador crece de forma modesta y estable | semillas 1, 3, 5: sobrevive, patrimonio final 1,5–15 × | 3/6 sobreviven con 3,5–10 ×; las otras 3 quiebran (años 4,5–12) |
| Agresivo puede crecer mucho o quebrar | ≥ 2 quiebras y algún resultado > 5 × en 6 semillas | 4/6 quiebran; el mejor termina en 5,2 × con oscilaciones de ± 10 MUSD |
| Diversificado internacional viable con buen equipo | semillas 1, 3, 5: sobrevive, ≥ 2 países, > 3 × | 3/6 sobreviven con 8–20 × y 3 países; las otras 3 quiebran (3,7–9,9 años) |
| IA con resultados variados, ninguna domina siempre | ≥ 2 ganadoras distintas, dispersión > 0,3 ×, ninguna > 12 ×, alguna quiebra | primeros lugares: Solaris 6, Vientos 5, Meridian 5, EGESA 2 de 18; varias quiebras por partida |
| TIR de proyectos típicos en rangos reales | combinaciones desarrolladas en la realidad: 3–22 % | tabla de abajo |

### Reporte (`npm run balance`, semillas 1–6)
| Estrategia | Quiebras | Mediana × capital | Mín | Máx |
|---|---|---|---|---|
| pasivo | 6/6 | 0,0 | 0,0 | 0,0 |
| solar conservador | 3/6 | 3,5 | 0,0 | 10,2 |
| agresivo | 4/6 | 0,0 | −4,4 | 5,2 |
| diversificado | 3/6 | 8,3 | 0,0 | 19,8 |

Patrimonio por año (MUSD) de las partidas que sobreviven:
- conservador 1: 1,0 0,8 1,7 1,5 2,5 2,3 2,1 1,8 5,5 5,2 9,1 8,8 12,8 12,5 12,3
- conservador 3: 1,0 0,8 2,3 2,1 1,9 3,0 2,8 2,5 −1,9 1,9 1,6 1,4 3,1 2,8 4,3
- conservador 5: 1,0 0,8 0,8 0,6 2,3 2,1 1,8 3,5 3,3 3,0 5,2 4,9 4,6 10,4 10,1
- diversificado 1: 0,9 0,7 2,3 2,0 4,0 3,7 3,3 3,0 9,2 8,9 16,5 16,2 24,4 24,1 23,7 (3 países)
- agresivo 6: 1,0 0,7 4,2 3,9 −5,5 −1,4 −0,5 6,6 6,1 −5,4 −6,4 9,1 8,7 8,3 7,4

El crecimiento es «a saltos»: cada proyecto vendido listo para construir con PPA rinde 0,6–1,5 MUSD; entre ventas la
empresa quema ≈ 220 kUSD/año de estructura. Las caídas puntuales a patrimonio negativo son obras con deuda y sobrecostos
o castigos de proyectos abandonados.

### TIR del capital de proyectos típicos (sitio típico del país, sin PPA, mercado de referencia de la Fase 4)
| Tecnología | PAN | CRI | COL | DOM | CHL | MEX | BRA | KEN | ESP | USA | IDN | PHL |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| solar FV | 15,0 | 12,3 | 7,2 | 20,7 | 9,4 | 11,3 | 3,8 | 14,4 | 6,6 | 3,7 | 11,1 | 15,8 |
| eólica | 10,1 | 14,9 | −7,1 | 18,6 | 14,4 | 5,7 | −1,2 | 12,8 | 6,0 | 5,3 | −1,6 | 11,2 |
| geotermia | 10,1 | 9,4 | 5,6 | 10,8 | 4,5 | 5,4 | 1,6 | 11,1 | 4,7 | 1,2 | 10,7 | 13,1 |
| hidro de pasada | 8,7 | 9,3 | 9,2 | 17,6 | 6,2 | 8,2 | 3,7 | 11,6 | 6,4 | 4,5 | 11,5 | 11,9 |
| gas CC | 8,0 | −5,7 | 0,0 | 20,4 | — | 17,8 | — | −0,7 | — | 10,4 | 13,2 | 9,5 |

Referencia: IEA *Cost of Capital Observatory* 2024 (TIR del capital de renovables ≈ 8–16 % en emergentes, 5–9 % en
mercados maduros con PPA). Las celdas bajas o negativas son combinaciones que el mercado real no desarrolla en el sitio
típico (eólica en Colombia fuera de La Guajira, en Brasil fuera del noreste o en Indonesia; gas con GNL caro donde casi no
despacha): la prueba exige el rango solo en las combinaciones habituales y que la eólica típica de Colombia NO sea negocio.

## Ajustes y justificación
| Ajuste | Antes | Ahora | Justificación |
|---|---|---|---|
| Capital inicial (`game.yaml`) | 750 kUSD | 1,2 MUSD | Un solo proyecto cuesta 300–600 kUSD de desarrollo y tarda 2–3 años; con 750 kUSD cualquier demora de permisos o un PPA fallido quebraba a todas las estrategias (0/6 sobrevivían). 1–3 MUSD es el capital semilla típico de un desarrollador pequeño. Pasivo sigue quebrando en 5,6–6,9 años. |
| Prima del comprador por riesgo de obra (`power.yaml → comprador`) | 0 | +0,5 pp listo para construir, +0,25 pp en obra | Sin ella un RTB de 20 MW con PPA se vendía a ≈ 140 kUSD/MW (el conservador multiplicaba por 17); con ella ≈ 60–100 kUSD/MW, el rango de transacciones de M&A en Latinoamérica. La valoración es muy sensible: con +1 pp (≈ 50 kUSD/MW) ninguna estrategia de venta sobrevivía. |
| IA: venta de proyectos listos para construir (`ai/brain.ts`) | vendía siempre al estar listo | solo si el comprador paga ≥ 1,1 × lo invertido (o tras 5 años); si no, sigue buscando PPA | Vender un proyecto merchant a un comprador que lo valora en el piso (30 % del desarrollo) destruía caja. Regla de decisión con información pública. |
| IA: canal de PPA (`ai/brain.ts`) | el primero de la lista | el de mayor probabilidad de cierre | Comportamiento racional; mismo código para jugador e IA. |
| Equipo inicial explícito (`team.yaml`) | implícito en los gastos fijos | 2 personas (jugador) y 2–4 por IA; su costo se descuenta de los gastos fijos | El gasto total no cambia; ahora rota, se puede despedir o capacitar y tiene efectos. |
| Reputación de oficina (`team.yaml`) | — | +0,1/mes (oficina), +0,2/mes (sede), reversión 1 %/mes hacia 40 | Equilibrio ≈ 50 con oficina y ≈ 60 con sede: la presencia ayuda, no garantiza. |

No se tocaron costos de equipos, permisos, precios ni probabilidades de los países: el juego no se hizo «gratis».

## Lectura de diseño
- La estrategia de desarrollador pequeño (desarrollar → PPA → vender RTB) es viable pero arriesgada: ≈ la mitad de las
  partidas fracasa porque un primer proyecto sin PPA o con un permiso rechazado consume la caja. Un jugador humano puede
  bajar el riesgo con equipo (abogado/social: más aprobaciones y plazos más cortos), socios y PPA corporativos.
- El agresivo gana mucho solo si sus primeras obras salen bien; la deuda al 80 % hace que un sobrecosto o un año seco lo
  quiebre.
- Ninguna IA domina: Solaris (agresiva) gana o quiebra; Meridian (fondo) es la más estable; EGESA y Vientos dependen de
  su primer proyecto.

## Límites
- Los bots son las reglas de la IA, no un jugador óptimo: subestiman lo que logra un humano (que puede elegir sitios,
  negociar socios y reaccionar antes a una crisis).
- 6 semillas × 15 años: la dispersión es grande; las cifras sirven para comparar estrategias, no como promedio exacto.
