# Datos del mapa mundial: fuentes y licencias

Todo lo que hay en `data/world/` sale de datos de **dominio público**, descargados una sola vez en desarrollo
(`tools/world_fetch.py`) y preprocesados con `tools/build_world.py`. El juego no descarga nada al ejecutarse.

| Datos | Fuente | Licencia |
|---|---|---|
| Fronteras de países admin-0 (1:50m para los países jugables, 1:110m para el mapa mundial), costas, ríos y lagos (1:50m), lugares poblados (1:10m), desiertos (regiones geográficas 1:50m) | [Natural Earth](https://www.naturalearthdata.com) (repositorio `nvkelso/natural-earth-vector`) | Dominio público. «All versions of Natural Earth raster + vector map data are in the public domain.» Crédito opcional: *Made with Natural Earth. Free vector and raster map data @ naturalearthdata.com.* |
| Relieve (altura del terreno y batimetría) | ETOPO1 Global Relief Model (NOAA, DOI [10.7289/V5C8276M](https://doi.org/10.7289/V5C8276M)), remuestreado a 10 minutos de arco por Fatiando a Terra (`fatiando-data/earth-topography-10arcmin`) | Dominio público (NOAA; el remuestreo declara `license: public domain`) |

Los perfiles de los países (`profiles.json`: moneda, idioma, inflación base, recursos dominantes) son un
resumen propio y aproximado para el juego.

Agradecimientos: Tom Patterson, Nathaniel Vaughn Kelso y los colaboradores de Natural Earth; NOAA NCEI;
Fatiando a Terra.
