# Diseño: mapa del país y mapa mundial (Fases 9 y 10)

Pedido de Sebastián: un mapa muy grande y variado, regiones con nombre y fronteras
invisibles, pueblos vecinos en el mismo mapa, comprar terreno (distinto de expandir la
vista), varios países en un mapa mundial, viajes, gerentes y carga internacional solo
por aeropuertos.

## Tres conceptos distintos (no mezclarlos)

| Concepto | Qué es | Cómo se obtiene | Qué da |
|---|---|---|---|
| **Revelar / expandir el mapa** | Ver más territorio del país | Abrir comercio con un pueblo (se revela su zona), pagar expediciones o comprar terreno vecino | Solo visibilidad: poder mirar, planear y comerciar |
| **Comprar terreno** | Ser dueño de parcelas para construir o extraer | Se compra al **Estado** o al **dueño privado**; precio fluctuante (gobierno regional, demanda, recursos, cercanía a pueblos) | Derecho a construir y extraer ahí |
| **Pueblos vecinos (NPC)** | Otros municipios con economía propia | Existen desde el inicio; se accede abriendo ruta | Comercio, inmigración, turismo, invertir allá |

Los ciudadanos también tienen libre comercio: compran casas, terrenos y bienes.

## Fase 9 — País en un solo mapa continuo

**Tamaño y estructura**
- El país es una rejilla de *chunks* de 400 m (la unidad actual). Un país mide, por ejemplo, 24×24 chunks (≈10 km por lado); lo define `data/countries.json`.
- El terreno es continuo: el mismo ruido en coordenadas globales para que los chunks encajen. Los biomas varían por latitud, humedad y altura: llanura, bosque, selva, desierto, montaña, nevado, costa, río, pantano.
- **Streaming**: solo se construyen las mallas de los chunks revelados que están cerca de la cámara, con LOD en los lejanos. Los chunks no revelados se ven como niebla o bruma.
- La cámara puede recorrer todo lo revelado del país sin teletransporte, y se puede alejar mucho para verlo completo.

**Regiones y fronteras invisibles**
- El país se divide en regiones o municipios con nombre propio (agrupación Voronoi de chunks).
- Las fronteras se ven en el minimapa y, con la cámara alejada, como líneas tenues en 3D.
- Cada región tiene políticas propias: impuestos locales (±), salario mínimo, regulación, misiones regionales y precio del suelo. Afecta impuestos, objetivos y reglas de lo que construyas ahí.
- Hay dos niveles de gobierno: el nacional (el actual de la Fase 5) y el regional (modificadores y misiones).

**Pueblos NPC en el mapa**
- Los pueblos de la Fase 7 pasan a tener posición real en el país (cerca o lejos, siempre en el mismo país).
- Abrir ruta con un pueblo revela su región; su casco urbano se dibuja como un grupo de edificios low-poly.
- Su economía está "en pausa": producen y venden cantidades fijas por mes, con precios por oferta y demanda (ya existe en `trade_sim`).
- El jugador puede automatizar compras y ventas y reaccionar a la escasez.

**Mercado de tierras**
- Cada chunk y parcela tiene un dueño: Estado, particular (NPC) o jugador.
- El precio depende de la región (política), el bioma, los yacimientos, la cercanía a pueblos y carreteras, y la demanda. Fluctúa.
- Comprarle al Estado sigue sus reglas (licitación o precio fijo); a un particular, mediante una oferta que puede aceptar o rechazar.

**Datos y código**
- `GameState.map`: `{country_id, chunks_revealed, parcels: {id: owner}, regions: {...}}`.
- `terrain.gd` pasa a gestionar muchos chunks (`TerrainChunk`) con streaming. Las zonas 5×5 actuales se convierten en parcelas de chunk.
- Minimapa del país con regiones, pueblos, rutas, lo revelado y lo propio.

## Fase 10 — Mapa mundial y otros países

**Mapa mundial**
- Es una pantalla aparte con países (`data/countries.json`). Cada país tiene ventajas y desventajas: recursos, biomas, impuestos, costo laboral, idioma, estabilidad política y época.
- Al empezar la partida se **elige el país de inicio**.

**Entrar a otro país**
- Es más costoso: licencia o permiso de inversión, más la compra de terreno ahí.
- Cada país tiene su propio mapa (chunks, regiones, pueblos, gobierno y biomas nuevos).
- El dinero y las cuentas son los mismos, con conversión de moneda opcional.

**Viajar**
- Para ver otro país se va al mapa mundial y se viaja allá. El viaje toma tiempo y cuesta.
- El personaje está físicamente en un país a la vez.

**Gerentes**
- Para operar en un país donde el personaje no está, se contrata un gerente local: sueldo según su nivel, y su eficiencia depende de la habilidad.
- Sin gerente ni presencia, los proyectos allá no avanzan.

**Carga internacional solo por aeropuertos**
- Vuelos comerciales: se paga por unidad o kg, con capacidad limitada.
- O un **hangar** propio con aviones de carga comprados (mantenimiento y combustible), con rutas manuales o automáticas.
- En el aeropuerto hay **almacenes grandes** donde llegan camiones que distribuyen a donde se configure (rutas automatizables, como las de la Fase 6).

**Datos y código**
- `buildings` y `citizens` ganan el campo `country_id`.
- El mundo 3D renderiza solo el país activo.
- Todos los países con presencia del jugador se simulan completos. El resto, en modo NPC resumido.

## Vehículos y depósitos (se aplica desde ya)
- Cada tipo de vehículo se compra y se mantiene en su edificio:
  - Caballeriza: caballos, mulas y carretas.
  - Depósito de camiones: carros motorizados, camiones y tráileres, con combustible.
  - Hangar: aviones de carga.
- Cada vehículo tiene capacidad máxima, mantenimiento (alimento o combustible) y rutas por vehículo, manuales o automáticas.

## Orden de implementación
1. En curso: almacenes individuales con fábrica en verde, flota con depósitos, catálogo de bienes y diseños, tiendas especializadas, energía y calibración de precios.
2. **Fase 9A**: terreno por chunks con streaming, biomas, niebla, minimapa y cámara de país.
3. **Fase 9B**: regiones con nombre y política, fronteras, mercado de tierras, pueblos NPC con posición y revelado por rutas.
4. **Fase 10**: países, mapa mundial, viajes, gerentes, aeropuertos internacionales y hangares.

La 9A y la 9B se pueden hacer en paralelo si la 9A publica primero la API del mapa (`MapSim.chunk_of(x,z)`, `MapSim.is_revealed`, `MapSim.region_at`, `MapSim.owner_of`).
