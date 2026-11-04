# Especificación del usuario (texto original resumido sin perder requisitos)

Simulación de gestión para macOS (Apple Silicon), 3D: dirijo una empresa de desarrollo de proyectos de energía que trabaja con gobiernos y privados en todo el mundo. Debe sentirse como la vida real: cada proyecto tiene investigación, permisos, costos, proveedores, riesgos y resultados que pueden fallar.

## Reglas de trabajo
- Construir por fases; al final de cada fase el juego se ejecuta y se juega.
- Preguntar solo decisiones realmente del usuario; en lo demás decidir y avisar.
- Mantener CLAUDE.md (arquitectura, decisiones, estado) actualizado en cada fase.
- Pruebas para el motor (economía, costos, permisos, riesgos).
- Motor de simulación separado (lógica pura, determinista, testeable) de render/UI.
- Datos en JSON/YAML editables, no hardcodeados. Guardado y carga.

## Estilo visual
- Globo 3D interactivo con capas: irradiación, viento, geotermia, hidrología, biomasa…
- Low-poly estilizado y limpio. Sitios y plantas en 3D (paneles, turbinas, torres de perforación, presas, subestaciones) que cambian según el avance de la obra.
- UI de gestión con paneles, tablas y gráficas legibles (estilo Capitalism / Tropico). Estilo fácil de cambiar.

## Modo de juego
- Sandbox, sin campaña. Progresión por I+D (árbol): tecnologías de energía, tipos de estudios, países/mercados, tipos de contrato, mejoras de eficiencia y reducción de costos.
- Empiezo en un país pequeño (Panamá) con empresa pequeña y me expando al mundo.

## Sistemas
1. Recursos por zona con datos reales aproximados; lo desarrollable y su rentabilidad dependen del recurso real.
2. Tecnologías: geotérmica, solar FV, CSP, eólica on/offshore, hidro (pasada, embalse, bombeo), biomasa, biogás, nuclear (incl. SMR), gas, carbón, petróleo; hidrógeno verde, baterías/almacenamiento, líneas de transmisión, interconexiones; eficiencia energética y llave en mano para industria. Cada una con CAPEX, O&M, factor de capacidad, vida útil, degradación, tiempos de construcción, emisiones (parámetros reales).
3. Ciclo de proyecto paso a paso con tiempo y costo en cada etapa:
   - Prospección/oportunidades (licitaciones públicas, solicitudes privadas, proyectos propios).
   - Propuestas y licitaciones: armo la oferta (precio, plazos, margen) y compito.
   - Estudios: medición del recurso, prefactibilidad, factibilidad, EIA, estudios de red. Pueden fallar o dar peor resultado (pozo seco, recurso menor, hallazgos arqueológicos, oposición comunitaria).
   - Permisos por país: licencia ambiental, consulta previa, uso de suelo, concesión de agua/minería/recurso, conexión a red, licencia de generación, PPA. Cada uno con requisitos, costo, duración y probabilidad. Comprobar viabilidad antes de comprometerse.
   - Financiación: deuda, equity, bancos de desarrollo, bonos verdes, subsidios, garantías. Tasas según riesgo país.
   - Construcción: proveedores y contratistas (equipos, EPC, perforación, logística) con calidad, precio y confiabilidad distintos. Retrasos, sobrecostos, clima, huelgas, fallas de calidad.
   - O&M: producción según recurso real, degradación, fallas, mantenimiento programado vs. correctivo.
4. Economía: costos por tecnología y país, inflación, tipos de cambio, aranceles, materiales y combustibles. Mercado eléctrico por país: spot por hora/estación/clima/demanda, PPA, capacidad, servicios complementarios. Estados financieros: flujo de caja, ingresos, deuda, TIR/VAN por proyecto, riesgo de quiebra.
5. Mundo dinámico: crisis petrolera, cambios de gobierno y regulación, subsidios, guerras, desastres, pandemias, avances tecnológicos, caídas de precio de equipos. Competidores IA con estrategias distintas que licitan, compran recursos y construyen.
6. Mi propia planta: desarrollar, financiar, operar; permisos de generación y conexión; vender por PPA o spot; despacho (generar, almacenar en baterías/bombeo/hidrógeno, vender según precio, demanda, clima).
7. Mi empresa: contratar ingenieros, geólogos, abogados ambientales, financieros, gerentes de proyecto (habilidades, salario, efecto real en probabilidad, costo y tiempo). Reputación (gobiernos, clientes, comunidades). Oficinas por país/región. I+D.

## Fases
- Fase 2: núcleo económico + 1 país + solar y eólica con ciclo completo.
- Fase 3: licitaciones, clientes, proveedores, competidores IA, árbol de investigación.
- Fase 4: más tecnologías y países con sistemas de permisos distintos.
- Fase 5: planta propia en mercado spot, despacho, eventos del mundo.
- Fase 6: equipo, reputación, expansión global, pulido visual y balance.

## Realismo
- Rangos de costos y parámetros reales con fuente o supuesto en los datos.
- Azar con probabilidades coherentes con la realidad, mejoradas por buen equipo e inversión previa.
- Nada gratis: cada decisión tiene costo, tiempo y riesgo.

## Preferencia del usuario
Respuestas cortas, al punto. Idioma: español.
