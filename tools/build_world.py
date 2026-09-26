#!/usr/bin/env python3
"""Preprocesa los datos de dominio público (tools/raw, ver world_fetch.py) al formato compacto del juego:

  data/world/world.json            mapa mundial: contorno simplificado de todos los países (1:110m),
                                   continente, nombre en español, punto de etiqueta y si es jugable.
  data/world/countries/<ISO>.json  países jugables (perfil en data/world/profiles.json): rejilla del país
                                   a escala del juego (celdas de 200 m) con altura real (ETOPO1 10'),
                                   máscara de la frontera, tierra/mar, lagos, desiertos, distancia a ríos,
                                   latitud real y lugares poblados reales (nombres y posiciones).
  data/world/ATRIBUCION.md         fuentes y licencias.

Escala: cada país se reduce en proporción a su extensión real (km) → N chunks de 400 m por lado,
con un mínimo (países pequeños) y un máximo (países enormes) por rendimiento. El pueblo del jugador
se funda en un lugar poblado real de altura baja o media, cerca del centro del país; ese punto es el
(0, 0) del juego (el chunk central sigue siendo el terreno de siempre).

Requiere numpy y h5py (solo en desarrollo). Uso: python3 tools/build_world.py [tools/raw]
"""
import base64
import gzip
import json
import math
import os
import sys

import h5py
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
RAW = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'tools', 'raw')
OUT = os.path.join(ROOT, 'data', 'world')
CHUNK_M = 400.0
CELL_M = 200.0
RING = 2
MIN_N = 40
MAX_N = 72
MAX_GRID = 80
KM_PER_N = 26.0     # km reales por chunk en un país "normal" (antes de los límites)


def load(name):
    with open(os.path.join(RAW, name), encoding='utf-8') as f:
        return json.load(f)


def polys_of(geom):
    """Lista de polígonos; cada uno = lista de anillos (np.array Nx2 lon/lat)."""
    if geom is None:
        return []
    if geom['type'] == 'Polygon':
        return [[np.array(r, dtype=np.float64) for r in geom['coordinates']]]
    if geom['type'] == 'MultiPolygon':
        return [[np.array(r, dtype=np.float64) for r in p] for p in geom['coordinates']]
    return []


def ring_area(r):
    x, y = r[:, 0], r[:, 1]
    return 0.5 * abs(np.dot(x, np.roll(y, 1)) - np.dot(y, np.roll(x, 1)))


def points_in_rings(px, py, rings):
    """Regla par-impar sobre todos los anillos (los huecos restan)."""
    inside = np.zeros(px.shape, dtype=bool)
    for r in rings:
        x0 = r[:, 0]
        y0 = r[:, 1]
        x1 = np.roll(x0, -1)
        y1 = np.roll(y0, -1)
        bx0, bx1, by0, by1 = x0.min(), x0.max(), y0.min(), y0.max()
        m = (px >= bx0) & (px <= bx1) & (py >= by0) & (py <= by1)
        if not m.any():
            continue
        qx = px[m]
        qy = py[m]
        c = np.zeros(qx.shape, dtype=bool)
        for i in range(len(x0)):
            yi, yj, xi, xj = y0[i], y1[i], x0[i], x1[i]
            if yi == yj:
                continue
            cond = (yi > qy) != (yj > qy)
            if not cond.any():
                continue
            xint = (xj - xi) * (qy - yi) / (yj - yi) + xi
            c ^= cond & (qx < xint)
        inside[m] ^= c
    return inside


def main_polys(polys):
    """Parte principal del país: el polígono más grande y las islas cercanas (sin territorios lejanos)."""
    if not polys:
        return []
    areas = [ring_area(p[0]) for p in polys]
    big = int(np.argmax(areas))
    b = polys[big][0]
    cx, cy = b[:, 0].mean(), b[:, 1].mean()
    ext = max(b[:, 0].max() - b[:, 0].min(), b[:, 1].max() - b[:, 1].min())
    keep = []
    for p, a in zip(polys, areas):
        r = p[0]
        d = math.hypot(r[:, 0].mean() - cx, r[:, 1].mean() - cy)
        if d <= ext * 0.75 + 1.0 and a >= areas[big] * 0.0005:
            keep.append(p)
    return keep


class Topo:
    def __init__(self, path):
        f = h5py.File(path, 'r')
        self.lat = f['latitude'][:]
        self.lon = f['longitude'][:]
        self.z = f['topography'][:].astype(np.float32)
        self.step = self.lat[1] - self.lat[0]

    def sample(self, lon, lat):
        lon = ((lon + 180.0) % 360.0) - 180.0
        fi = (lat - self.lat[0]) / self.step
        fj = (lon - self.lon[0]) / self.step
        i0 = np.clip(np.floor(fi).astype(int), 0, len(self.lat) - 2)
        j0 = np.clip(np.floor(fj).astype(int), 0, len(self.lon) - 2)
        ti = np.clip(fi - i0, 0, 1)
        tj = np.clip(fj - j0, 0, 1)
        z = self.z
        a = z[i0, j0] * (1 - tj) + z[i0, j0 + 1] * tj
        b = z[i0 + 1, j0] * (1 - tj) + z[i0 + 1, j0 + 1] * tj
        return a * (1 - ti) + b * ti


def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    l2 = dx * dx + dy * dy
    if l2 <= 0:
        return np.hypot(px - ax, py - ay)
    t = np.clip(((px - ax) * dx + (py - ay) * dy) / l2, 0, 1)
    return np.hypot(px - (ax + t * dx), py - (ay + t * dy))


def b64gz(arr):
    return base64.b64encode(gzip.compress(arr.tobytes(), 9, mtime=0)).decode('ascii')


def simplify(ring, tol):
    """Douglas-Peucker simple para el mapa mundial."""
    pts = ring
    if len(pts) < 5:
        return pts
    keep = np.zeros(len(pts), dtype=bool)
    keep[0] = keep[-1] = True
    stack = [(0, len(pts) - 1)]
    while stack:
        s, e = stack.pop()
        if e <= s + 1:
            continue
        a, b = pts[s], pts[e]
        seg = pts[s + 1:e]
        d = seg_dist(seg[:, 0], seg[:, 1], a[0], a[1], b[0], b[1])
        k = int(np.argmax(d))
        if d[k] > tol:
            keep[s + 1 + k] = True
            stack.append((s, s + 1 + k))
            stack.append((s + 1 + k, e))
    return pts[keep]


def build_world_map(profiles):
    d = load('ne_110m_admin_0_countries.geojson')
    out = []
    for f in d['features']:
        p = f['properties']
        iso = p['ADM0_A3']
        rings = []
        for poly in polys_of(f['geometry']):
            r = simplify(poly[0], 0.12)
            if len(r) >= 4:
                rings.append([round(float(v), 2) for v in r.flatten()])
        out.append({'iso': iso, 'name': profiles.get(iso, {}).get('name', p.get('NAME_ES') or p['NAME']),
                    'continent': p['CONTINENT'], 'label': [round(p['LABEL_X'], 2), round(p['LABEL_Y'], 2)],
                    'playable': iso in profiles, 'pop': int(p.get('POP_EST') or 0), 'rings': rings})
    out.sort(key=lambda c: c['iso'])
    return out


def build_country(iso, prof, topo, admin, all_land, lakes, rivers, deserts, places):
    feats = [f for f in admin['features'] if f['properties']['ADM0_A3'] == iso]
    if not feats:
        print('  sin geometría:', iso)
        return None
    polys = main_polys([p for f in feats for p in polys_of(f['geometry'])])
    rings = [r for p in polys for r in p]
    outer = np.concatenate([p[0] for p in polys])
    lon_min, lon_max = outer[:, 0].min(), outer[:, 0].max()
    lat_min, lat_max = outer[:, 1].min(), outer[:, 1].max()
    lat_c = (lat_min + lat_max) / 2
    lon_c = (lon_min + lon_max) / 2
    kx = 111.32 * math.cos(math.radians(lat_c))
    ky = 110.57
    w_km = (lon_max - lon_min) * kx
    h_km = (lat_max - lat_min) * ky
    extent = max(w_km, h_km)
    n_country = int(min(MAX_N, max(MIN_N, round(extent / KM_PER_N))))
    km_chunk = extent / (n_country - 2)
    # Lugares poblados del país (parte principal).
    pl = [p for p in places if p['properties']['adm0_a3'] == iso]
    if pl:
        plon = np.array([p['properties']['longitude'] for p in pl])
        plat = np.array([p['properties']['latitude'] for p in pl])
        ins = points_in_rings(plon, plat, rings)
        pl = [p for p, i in zip(pl, ins) if i]
    # Pueblo inicial: el del perfil o uno de altura baja/media cerca del centro.
    start = None
    want = prof.get('start', '')
    for p in pl:
        if p['properties']['name'] == want:
            start = p
    if start is None and pl:
        best = 1e18
        for p in pl:
            lo, la = p['properties']['longitude'], p['properties']['latitude']
            e = float(topo.sample(np.array([lo]), np.array([la]))[0])
            pop = p['properties']['pop_max'] or 0
            dist = math.hypot((lo - lon_c) * kx, (la - lat_c) * ky) / km_chunk
            score = dist + (0 if 15 < e < 700 else 30) + (0 if pop < 400000 else 12)
            if score < best:
                best = score
                start = p
    if start is not None:
        lon0, lat0, start_name = start['properties']['longitude'], start['properties']['latitude'], start['properties']['name']
    else:
        lon0, lat0, start_name = lon_c, lat_c, ''
    off = max(abs(lon0 - lon_c) * kx, abs(lat0 - lat_c) * ky) / km_chunk
    n = int(min(MAX_GRID, n_country + 2 * math.ceil(off)))
    n += n % 2
    c0 = -(n // 2)
    m = (n + 2 * RING) * 2 + 1
    x0 = (c0 - RING) * CHUNK_M - CHUNK_M / 2
    xs = x0 + np.arange(m) * CELL_M
    gx, gz = np.meshgrid(xs, xs)
    # Metros del juego → km reales → lon/lat (norte = -z).
    lon = lon0 + (gx / CHUNK_M * km_chunk) / (111.32 * math.cos(math.radians(lat0)))
    lat = lat0 - (gz / CHUNK_M * km_chunk) / ky
    elev = topo.sample(lon, lat)
    fl = lon.ravel()
    fa = lat.ravel()
    in_c = points_in_rings(fl, fa, rings)
    bb = (fl.min(), fl.max(), fa.min(), fa.max())

    def overlap(r):
        return not (r[:, 0].max() < bb[0] or r[:, 0].min() > bb[1] or r[:, 1].max() < bb[2] or r[:, 1].min() > bb[3])

    land_r = [r for poly in all_land for r in poly if overlap(poly[0])]
    land = points_in_rings(fl, fa, land_r) | in_c
    lake_r = [r for poly in lakes for r in poly if overlap(poly[0])]
    lake = points_in_rings(fl, fa, lake_r) if lake_r else np.zeros(fl.shape, bool)
    des_r = [r for poly in deserts for r in poly if overlap(poly[0])]
    desert = points_in_rings(fl, fa, des_r) if des_r else np.zeros(fl.shape, bool)
    flags = (in_c.astype(np.uint8) * 1) | (land.astype(np.uint8) * 2) | (lake.astype(np.uint8) * 4) | (desert.astype(np.uint8) * 8)
    # Ríos: distancia (m del juego) al cauce más cercano y ancho según su importancia.
    rd = np.full(fl.shape, 1e9)
    rw = np.zeros(fl.shape)
    gxf = gx.ravel()
    gzf = gz.ravel()
    to_x = lambda lo_: (lo_ - lon0) * (111.32 * math.cos(math.radians(lat0))) / km_chunk * CHUNK_M
    to_z = lambda la_: -(la_ - lat0) * ky / km_chunk * CHUNK_M
    for rv in rivers:
        rank = rv['rank']
        for line in rv['lines']:
            if line[:, 0].max() < bb[0] or line[:, 0].min() > bb[1] or line[:, 1].max() < bb[2] or line[:, 1].min() > bb[3]:
                continue
            xs_ = to_x(line[:, 0])
            zs_ = to_z(line[:, 1])
            for i in range(len(xs_) - 1):
                d = seg_dist(gxf, gzf, xs_[i], zs_[i], xs_[i + 1], zs_[i + 1])
                better = d < rd
                rd = np.where(better, d, rd)
                rw = np.where(better, max(14.0, 64.0 - rank * 5.0), rw)
    rdist = np.clip(rd / 8.0, 0, 255).astype(np.uint8)
    rwid = np.clip(rw, 0, 255).astype(np.uint8)
    el16 = np.clip(elev, -12000, 9000).astype('<i2')
    # Lugares poblados en coordenadas del juego.
    out_places = []
    for p in sorted(pl, key=lambda q: -(q['properties']['pop_max'] or 0)):
        pr = p['properties']
        x = float(to_x(pr['longitude']))
        z = float(to_z(pr['latitude']))
        out_places.append({'name': pr['name'], 'x': round(x, 1), 'z': round(z, 1), 'pop': int(pr['pop_max'] or 0),
                           'capital': int(pr.get('adm0cap') or 0)})
    out_places = out_places[:160]
    area = sum(ring_area(p[0]) for p in polys) * kx * ky
    return {
        'iso': iso, 'name': prof['name'], 'size': n, 'country_chunks_side': n_country, 'km_per_chunk': round(km_chunk, 3),
        'extent_km': round(extent, 1), 'area_km2_approx': round(area), 'origin': [round(lon0, 5), round(lat0, 5)],
        'start_name': start_name, 'ring': RING, 'lat_range': [round(float(lat.min()), 3), round(float(lat.max()), 3)],
        'grid': {'m': m, 'cell': CELL_M, 'x0': x0, 'elev': b64gz(el16), 'flags': b64gz(flags), 'rdist': b64gz(rdist), 'rwid': b64gz(rwid),
                 'encoding': 'gzip+base64; elev int16 LE (m reales), flags u8 (1 país, 2 tierra, 4 lago, 8 desierto), rdist u8 (×8 m), rwid u8 (m)'},
        'places': out_places,
    }


def main():
    os.makedirs(os.path.join(OUT, 'countries'), exist_ok=True)
    with open(os.path.join(OUT, 'profiles.json'), encoding='utf-8') as f:
        profiles = json.load(f)['countries']
    world = build_world_map(profiles)
    with open(os.path.join(OUT, 'world.json'), 'w', encoding='utf-8') as f:
        json.dump({'_fuente': 'Natural Earth 1:110m (dominio público), simplificado', 'countries': world}, f, ensure_ascii=False, separators=(',', ':'))
    print('world.json:', len(world), 'países')
    topo = Topo(os.path.join(RAW, 'earth-topography-10arcmin.nc'))
    admin = load('ne_50m_admin_0_countries.geojson')
    all_land = [p for f in admin['features'] for p in polys_of(f['geometry'])]
    lakes = [p for f in load('ne_50m_lakes.geojson')['features'] for p in polys_of(f['geometry'])]
    regions = load('ne_50m_geography_regions_polys.geojson')
    deserts = [p for f in regions['features'] if f['properties'].get('FEATURECLA') == 'Desert' for p in polys_of(f['geometry'])]
    rivers = []
    for f in load('ne_50m_rivers_lake_centerlines.geojson')['features']:
        g = f['geometry']
        if g is None:
            continue
        lines = g['coordinates'] if g['type'] == 'MultiLineString' else [g['coordinates']]
        rivers.append({'rank': int(f['properties'].get('scalerank') or 6), 'lines': [np.array(l) for l in lines if len(l) > 1]})
    places = load('ne_10m_populated_places_simple.geojson')['features']
    only = set(sys.argv[2].split(',')) if len(sys.argv) > 2 else None
    for iso, prof in profiles.items():
        if only and iso not in only:
            continue
        c = build_country(iso, prof, topo, admin, all_land, lakes, rivers, deserts, places)
        if c is None:
            continue
        path = os.path.join(OUT, 'countries', iso + '.json')
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(c, f, ensure_ascii=False, separators=(',', ':'))
        print('%s: %d chunks (país %d), %.1f km/chunk, inicio %s, %d lugares, %d KB' % (iso, c['size'], c['country_chunks_side'], c['km_per_chunk'], c['start_name'], len(c['places']), os.path.getsize(path) // 1024))


if __name__ == '__main__':
    main()
