#!/usr/bin/env python3
"""Descarga UNA vez (en desarrollo) los datos de dominio público del mapa mundial a tools/raw/.
El juego nunca descarga nada: tools/build_world.py los convierte en data/world/.

Fuentes (dominio público):
- Natural Earth (https://www.naturalearthdata.com), repositorio nvkelso/natural-earth-vector:
  fronteras de países admin-0 (1:50m y 1:110m), ríos y lagos (1:50m), lugares poblados (1:10m) y
  regiones geográficas (desiertos, cordilleras) 1:50m.
- ETOPO1 (NOAA, dominio público) remuestreado a 10 minutos de arco por Fatiando a Terra
  (earth-topography-10arcmin, licencia: public domain). DOI del original: 10.7289/V5C8276M.

Uso: python3 tools/world_fetch.py [carpeta_destino]   (por defecto tools/raw)
"""
import os
import ssl
import sys
import urllib.request

NE = 'https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/'
FILES = {
    'ne_50m_admin_0_countries.geojson': NE + 'geojson/ne_50m_admin_0_countries.geojson',
    'ne_110m_admin_0_countries.geojson': NE + 'geojson/ne_110m_admin_0_countries.geojson',
    'ne_50m_rivers_lake_centerlines.geojson': NE + 'geojson/ne_50m_rivers_lake_centerlines.geojson',
    'ne_50m_lakes.geojson': NE + 'geojson/ne_50m_lakes.geojson',
    'ne_10m_populated_places_simple.geojson': NE + 'geojson/ne_10m_populated_places_simple.geojson',
    'ne_50m_geography_regions_polys.geojson': NE + 'geojson/ne_50m_geography_regions_polys.geojson',
    'NATURAL_EARTH_LICENSE.md': NE + 'LICENSE.md',
    'earth-topography-10arcmin.nc': 'https://github.com/fatiando-data/earth-topography-10arcmin/releases/download/v1/earth-topography-10arcmin.nc',
}


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), 'raw')
    os.makedirs(out, exist_ok=True)
    ca = os.environ.get('SSL_CERT_FILE') or ('/root/.ccr/ca-bundle.crt' if os.path.exists('/root/.ccr/ca-bundle.crt') else None)
    ctx = ssl.create_default_context(cafile=ca) if ca else ssl.create_default_context()
    for name, url in FILES.items():
        path = os.path.join(out, name)
        if os.path.exists(path) and os.path.getsize(path) > 0:
            print('ya existe', name)
            continue
        data = urllib.request.urlopen(url, context=ctx, timeout=300).read()
        with open(path, 'wb') as f:
            f.write(data)
        print('descargado', name, len(data))


if __name__ == '__main__':
    main()
