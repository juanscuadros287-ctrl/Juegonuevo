# Recursos por zona — cómo se generan

Grilla global de **0,5° × 0,5°** (720 × 360 celdas, ≈55 km en el ecuador). La genera `npm run resources` (`tools/build-resources.ts`) y queda en `packages/data/generated/`.

## Fuentes reales usadas
| Dato | Fuente | Uso |
|---|---|---|
| Países y costas | Natural Earth 1:50m (dominio público) | país por celda, costa, distancia a la costa, mapa y fronteras |
| Montañas, mesetas, desiertos | Natural Earth, regiones geográficas | relieve aproximado, desiertos |
| Ríos | Natural Earth, ríos y lagos (por rango de escala) | cercanía a ríos (hidro) |
| Placas tectónicas | PB2002 (Bird 2003) | geotermia (límites y zonas de subducción) |
| Campos geotérmicos | Ubicación de campos en operación o exploración | geotermia |

## Lo que es aproximado (y por qué)
El entorno de desarrollo no tiene acceso a NASA POWER, Global Solar Atlas ni Global Wind Atlas. Por eso **sol, viento y lluvia** salen de:
1. una **línea base por latitud** (tablas en el script);
2. ajustes por **desierto, relieve y cercanía a la costa**;
3. ~180 **puntos de referencia** (`packages/data/resources/anclas.yaml`) con valores redondeados del orden de magnitud que publican esos atlas. Cada punto corrige su zona con un peso gaussiano (radio configurable). Lejos de los puntos se vuelve a la línea base.

Error esperado: GHI ±10 %, viento ±1,5 m/s, lluvia ±30 %. En Panamá hay 9 puntos con radio corto.

## Modelo de cada capa
| Capa | Unidad | Modelo |
|---|---|---|
| GHI | kWh/m²/día | base(lat) + 0,7·desierto + relieve en trópicos + puntos de referencia |
| DNI | kWh/m²/día | GHI × factor de claridad (1,4 seco → 0,65 muy lluvioso) |
| Viento en tierra (100 m) | m/s | base(lat) + costa + relieve + desierto − continentalidad tropical + puntos |
| Viento mar adentro (100 m) | m/s | base(lat) por hemisferio (alisios, calmas ecuatoriales, vientos del oeste) − efecto costa + puntos marinos |
| Geotermia | mW/m² | 62 continental + límites de placas + arco volcánico (~170 km de la subducción) + campos conocidos |
| Hidro | índice 0–100 | lluvia^0,7 × relieve × cercanía a ríos (reducido si es zona congelada) |
| Biomasa (NPP) | g/m²/año | modelo de Miami (Lieth 1975) con temperatura y lluvia |
| Temperatura | °C | latitud, relieve, efecto marítimo y continentalidad |

Comprobaciones automáticas en `packages/sim/test/grid.test.ts` (Sahara, Atacama, Berlín, Patagonia, Mar del Norte, Islandia, Amazonas, Panamá).

## Qué ve el jugador
La ficha muestra el **valor de la celda**. El recurso real de un sitio concreto queda oculto y se descubre con estudios (Fase 2): estimación satelital con incertidumbre amplia → medición en sitio con incertidumbre menor.
