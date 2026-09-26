class_name CountryGen
extends RefCounted
## Fase 9A — Generador del país continuo (sin nodos, solo funciones puras).
## - El país es una rejilla de chunks de 400 m; el chunk (0, 0) es el del pueblo y cubre
##   [-200, 200] × [-200, 200] con el terreno EXACTO de antes (mismo ruido y fórmula por map_type).
## - Fuera del pueblo, el relieve sale de ruido en coordenadas globales (sin costuras) y del perfil
##   del país (data/countries.json): montañas, lagos, ríos largos, costas, islas, desiertos...
## - Entre 200 y 200 + BLEND m se mezcla el terreno viejo con el del país.
## - Países reales (mapa mundial): la altura, la frontera, la costa, los lagos, los ríos y los desiertos salen
##   de la rejilla preprocesada (WorldData, Natural Earth + ETOPO1) a escala del juego; el ruido solo añade
##   detalle. El clima sale de la latitud y la altura reales. Los municipios se siembran en lugares reales.
## Es de solo lectura tras init(): se puede usar desde hilos (WorkerThreadPool).

const CHUNK := 400.0
const HALF_CHUNK := 200.0
const TOWN_FLAT_RADIUS := 30.0
const TOWN_HEIGHT := 3.0
const BLEND := 480.0

const BIOMES := ["mar", "costa", "rio", "pantano", "llanura", "bosque", "selva", "desierto", "montana", "nevado"]
const BIOME_LABELS := {"mar": "Mar", "costa": "Costa", "rio": "Río o lago", "pantano": "Pantano", "llanura": "Llanura",
		"bosque": "Bosque", "selva": "Selva", "desierto": "Desierto", "montana": "Montaña", "nevado": "Nevado"}
const B_MAR := 0
const B_COSTA := 1
const B_RIO := 2
const B_PANTANO := 3
const B_LLANURA := 4
const B_BOSQUE := 5
const B_SELVA := 6
const B_DESIERTO := 7
const B_MONTANA := 8
const B_NEVADO := 9
const BIOME_COLORS := [
	Color(0.62, 0.58, 0.44), Color(0.86, 0.8, 0.58), Color(0.55, 0.55, 0.42), Color(0.34, 0.42, 0.25),
	Color(0.4, 0.57, 0.28), Color(0.22, 0.42, 0.2), Color(0.12, 0.34, 0.14), Color(0.84, 0.71, 0.48),
	Color(0.45, 0.42, 0.37), Color(0.92, 0.93, 0.96)]
## Color de cada bioma para el minimapa (el agua se ve azul).
const BIOME_MAP_COLORS := [
	Color(0.16, 0.36, 0.58), Color(0.86, 0.8, 0.58), Color(0.25, 0.5, 0.72), Color(0.33, 0.43, 0.3),
	Color(0.5, 0.68, 0.34), Color(0.25, 0.48, 0.24), Color(0.12, 0.36, 0.15), Color(0.88, 0.76, 0.5),
	Color(0.55, 0.5, 0.44), Color(0.93, 0.94, 0.97)]

var map_type := "interior"
var seed_value := 1
var country_id := ""
var profile: Dictionary = {}
var terrain_p: Dictionary = {}
var cfg: Dictionary = {}
var water_level := 0.0
var size := 30                 # chunks por lado
var c0 := -15                  # índice de chunk mínimo (x e y)
var c1 := 14                   # índice de chunk máximo
var x_min := 0.0
var x_max := 0.0
var center := Vector2.ZERO
var half_ext := 6000.0
var coast_sides: Array = []
# País real (WorldData)
var real := false
var km_per_chunk := 0.0
var origin := Vector2.ZERO        # lon, lat reales del (0, 0) del juego
var places: Array = []            # [{name, x, z, pop, capital}]
var _gm := 0
var _gx0 := 0.0
var _gcell := 200.0
var _hbase := PackedFloat32Array()   # altura base del juego (desde la altura real)
var _elev := PackedFloat32Array()    # altura real (m)
var _fin := PackedFloat32Array()     # dentro del país (0/1)
var _fland := PackedFloat32Array()   # tierra (0/1)
var _flake := PackedFloat32Array()
var _fdes := PackedFloat32Array()
var _rdist := PackedFloat32Array()   # m del juego al río más cercano
var _rwid := PackedFloat32Array()    # ancho (m) de ese río
var _chunk_in := PackedByteArray()
var scale := 1.0               # escala de los rasgos grandes (país / 32 chunks)
var coast_w := 1300.0

# Parámetros del perfil (cacheados para los hilos)
var _mountain := 0.5
var _peak := 120.0
var _forest_p := 0.4
var _lakes := 0.3
var _rivers := 0.5
var _desert := 0.2
var _swamp := 0.3
var _islands := 0.0
var _humidity := 0.0
var _temperature := 0.3
var _lat_grad := 0.6
var _plateaus := 0.0
var _canyons := 0.0

# Ruido del terreno viejo (idéntico a la versión de 400 m)
var _noise := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _ridge := FastNoiseLite.new()
var _forest := FastNoiseLite.new()
# Ruido del país
var _cont := FastNoiseLite.new()
var _hill := FastNoiseLite.new()
var _mount := FastNoiseLite.new()
var _mridge := FastNoiseLite.new()
var _river := FastNoiseLite.new()
var _warp := FastNoiseLite.new()
var _lake := FastNoiseLite.new()
var _hum := FastNoiseLite.new()
var _temp := FastNoiseLite.new()
var _island := FastNoiseLite.new()
var _plat := FastNoiseLite.new()

# Municipios (Voronoi de chunks)
var zones: Array = []           # [{id, seed: Vector2i, town: bool, town_chunk: Vector2i, town_pos: Vector2, player: bool}]
var _zone_of_chunk := PackedInt32Array()


func init(p_type: String, p_seed: int, p_country: String) -> CountryGen:
	map_type = p_type
	seed_value = p_seed
	country_id = p_country
	cfg = GameData.map_type(p_type)
	water_level = float(cfg.get("water_level", 0.0))
	profile = country_def(p_country)
	terrain_p = profile.get("terrain", {})
	size = clampi(int(profile.get("size", 64)), 8, 96)
	real = bool(profile.get("real", false))
	c0 = -(size / 2)
	c1 = c0 + size - 1
	x_min = c0 * CHUNK - HALF_CHUNK
	x_max = c1 * CHUNK + HALF_CHUNK
	center = Vector2((x_min + x_max) * 0.5, (x_min + x_max) * 0.5)
	half_ext = size * HALF_CHUNK
	coast_sides = terrain_p.get("coast", [])
	_mountain = float(terrain_p.get("mountain", 0.5))
	_peak = float(terrain_p.get("peak_height", 120.0))
	_forest_p = float(terrain_p.get("forest", 0.4))
	_lakes = float(terrain_p.get("lakes", 0.3))
	_rivers = float(terrain_p.get("rivers", 0.5))
	_desert = float(terrain_p.get("desert", 0.2))
	_swamp = float(terrain_p.get("swamp", 0.3))
	_islands = float(terrain_p.get("islands", 0.0))
	_humidity = float(terrain_p.get("humidity", 0.0))
	_temperature = float(terrain_p.get("temperature", 0.3))
	_lat_grad = float(terrain_p.get("lat_gradient", 0.6))
	_plateaus = float(terrain_p.get("plateaus", 0.0))
	_canyons = float(terrain_p.get("canyons", 0.0))
	_setup(_noise, p_seed, 0.006, 4)
	_setup(_detail, p_seed + 11, 0.035, 2)
	_setup(_ridge, p_seed + 23, 0.009, 3)
	_setup(_forest, p_seed + 37, 0.012, 2)
	var cs := p_seed * 7 + p_country.hash() % 100000
	# Fase 9B: los rasgos grandes (continente, cordilleras, clima, islas) crecen con el país para que
	# un país de 25 km tenga regiones amplias y no un mosaico repetido.
	scale = clampf(size / 32.0, 1.0, 2.6)
	var sq := sqrt(scale)
	coast_w = 1300.0 * sq
	_setup(_cont, cs + 101, 1.0 / (3200.0 * scale), 4)
	_setup(_hill, cs + 102, 1.0 / 380.0, 3)
	_setup(_mount, cs + 103, 1.0 / (2600.0 * scale), 3)
	_setup(_mridge, cs + 104, 1.0 / (1150.0 * sq), 4)
	_setup(_river, cs + 105, 1.0 / (2300.0 * sq), 2)
	_setup(_warp, cs + 106, 1.0 / 900.0, 2)
	_setup(_lake, cs + 107, 1.0 / (700.0 * sq), 2)
	_setup(_hum, cs + 108, 1.0 / (2400.0 * scale), 3)
	_setup(_temp, cs + 109, 1.0 / (3000.0 * scale), 2)
	_setup(_island, cs + 110, 1.0 / (1500.0 * sq), 3)
	_setup(_plat, cs + 111, 1.0 / (1700.0 * sq), 3)
	if real:
		_setup_real()
	_build_zones()
	return self


## Carga la rejilla del país real y la convierte a alturas del juego.
func _setup_real() -> void:
	var d := WorldData.country_data(country_id)
	var g: Dictionary = d.get("grid", {})
	_gm = int(g.get("m", 0))
	_gx0 = float(g.get("x0", 0.0))
	_gcell = float(g.get("cell", 200.0))
	km_per_chunk = float(d.get("km_per_chunk", 20.0))
	var o: Array = d.get("origin", [0.0, 0.0])
	origin = Vector2(float(o[0]), float(o[1]))
	places = d.get("places", [])
	var n := _gm * _gm
	_hbase.resize(n)   # (los Packed*Array son valores: se redimensiona cada uno)
	_elev.resize(n)
	_fin.resize(n)
	_fland.resize(n)
	_flake.resize(n)
	_fdes.resize(n)
	_rdist.resize(n)
	_rwid.resize(n)
	var elev: PackedInt32Array = g["elev"]
	var fl: PackedByteArray = g["flags"]
	var rd: PackedByteArray = g["rdist"]
	var rw: PackedByteArray = g["rwid"]
	for i in range(n):
		var e := float(elev[i])
		var f := fl[i]
		_elev[i] = e
		_fin[i] = 1.0 if f & 1 else 0.0
		_fland[i] = 1.0 if f & 2 else 0.0
		_flake[i] = 1.0 if f & 4 else 0.0
		_fdes[i] = 1.0 if f & 8 else 0.0
		_rdist[i] = float(rd[i]) * 8.0
		_rwid[i] = float(rw[i])
		_hbase[i] = real_to_game(e)
	_chunk_in.resize(size * size)
	for cy in range(c0, c1 + 1):
		for cx in range(c0, c1 + 1):
			var inside := _cell_nearest(_fin, cx * CHUNK, cy * CHUNK) > 0.5
			if maxi(absi(cx), absi(cy)) <= 1:
				inside = true
			_chunk_in[(cy - c0) * size + (cx - c0)] = 1 if inside else 0


## Altura real (m) → altura del juego: la costa a 4 m y los picos de 5.000 m a unos 180 m (el pueblo
## de siempre está entre 3 y 20 m). Más escalonado en lo bajo para que los valles se lean.
static func real_to_game(e: float) -> float:
	if e <= 0.0:
		return clampf(-4.0 + e / 150.0, -14.0, -4.0)
	return 4.0 + 176.0 * pow(minf(e, 6500.0) / 5000.0, 0.75)


func _grid_f(x: float, z: float) -> Vector2:
	return Vector2(clampf((x - _gx0) / _gcell, 0.0, _gm - 1.001), clampf((z - _gx0) / _gcell, 0.0, _gm - 1.001))


func _cell_bilinear(arr: PackedFloat32Array, x: float, z: float) -> float:
	var f := _grid_f(x, z)
	var i := int(f.x)
	var j := int(f.y)
	var tx := f.x - i
	var tz := f.y - j
	var k := j * _gm + i
	return lerpf(lerpf(arr[k], arr[k + 1], tx), lerpf(arr[k + _gm], arr[k + _gm + 1], tx), tz)


func _cell_nearest(arr: PackedFloat32Array, x: float, z: float) -> float:
	var f := _grid_f(x, z)
	return arr[roundi(f.y) * _gm + roundi(f.x)]


## Latitud real de un punto del juego (norte = -z).
func real_lat(z: float) -> float:
	return origin.y - z / CHUNK * km_per_chunk / 110.57


func real_lon(x: float) -> float:
	return origin.x + x / CHUNK * km_per_chunk / (111.32 * cos(deg_to_rad(origin.y)))


## Altura real (m) en un punto (países reales).
func real_elevation(x: float, z: float) -> float:
	return _cell_bilinear(_elev, x, z) if real else 0.0


## Relieve de un país real: altura base de la rejilla + detalle; costa, lagos y ríos de los datos.
func _country_real(x: float, z: float) -> Vector2:
	var e := _cell_bilinear(_hbase, x, z)
	var steep := clampf((e - 12.0) / 90.0, 0.0, 1.0)
	e += _hill.get_noise_2d(x, z) * (2.0 + 5.0 * steep) + _detail.get_noise_2d(x, z) * 1.2
	if steep > 0.0:
		var r := 1.0 - absf(_mridge.get_noise_2d(x, z))
		e += (r * r - 0.35) * 42.0 * steep
	# Costa: máscara de tierra (1:50m) con un borde irregular.
	var land := _cell_bilinear(_fland, x, z) + _island.get_noise_2d(x, z) * 0.22
	var town_guard := 1.0 - smoothstep(1100.0, 2200.0, Vector2(x, z).length())
	land = maxf(land, town_guard)
	var lk := smoothstep(0.45, 0.6, _cell_bilinear(_flake, x, z) + _lake.get_noise_2d(x, z) * 0.12) * (1.0 - town_guard)
	var k := smoothstep(0.38, 0.62, land)
	e = maxf(e, water_level + 1.2 + 3.0 * smoothstep(0.62, 0.9, land)) if k > 0.5 else e
	if k < 1.0:
		e = lerpf(minf(-6.0, _cell_bilinear(_hbase, x, z)), e, k)
	if lk > 0.0:
		e = lerpf(e, water_level - 3.0, lk)
	# Ríos reales: distancia al cauce con meandros.
	var rw := _cell_nearest(_rwid, x, z)
	if rw > 0.0 and k > 0.5 and rw * 0.5 * (1.0 - town_guard) > 2.0:
		var rd := _cell_bilinear(_rdist, x, z) + _warp.get_noise_2d(x, z) * 30.0
		var half_w := rw * 0.5 * (1.0 - town_guard)
		var bank := 1.0 - smoothstep(half_w, half_w * 4.0, rd)
		if bank > 0.0:
			e = lerpf(e, minf(e, water_level + 2.5 + e * 0.15), bank * 0.6)
		var carve := 1.0 - smoothstep(half_w * 0.5, half_w, rd)
		if carve > 0.0:
			e = lerpf(e, water_level - 2.5, carve)
	return Vector2(e, 1.0 - k)


## Clima real: temperatura por latitud y altura reales; humedad del perfil, desiertos de Natural Earth
## y franja subtropical seca.
func _climate_real(x: float, z: float) -> Vector2:
	var lat := absf(real_lat(z))
	var el := maxf(real_elevation(x, z), 0.0)
	var tc := 27.0 - 0.45 * maxf(lat - 12.0, 0.0) - el * 0.0062 + _temp.get_noise_2d(x, z) * 1.5
	var t := (tc - 12.0) / 14.0
	var m := _humidity + _hum.get_noise_2d(x, z) * 0.55
	m -= 0.18 * (smoothstep(15.0, 22.0, lat) * (1.0 - smoothstep(30.0, 36.0, lat)))
	m -= 1.1 * _cell_bilinear(_fdes, x, z)
	return Vector2(t, m)


static func countries_cfg() -> Dictionary:
	return GameData.extra("countries")


static func country_def(id: String) -> Dictionary:
	var all: Dictionary = countries_cfg().get("countries", {})
	if all.has(id):
		return all[id]
	if WorldData.is_real(id):
		return WorldData.country_def(id)   # país real del mapa mundial
	return {"label": "País", "size": 30, "terrain": {}, "zones": 20, "town_ratio": 0.6, "resources": {}}


func _setup(n: FastNoiseLite, s: int, freq: float, octaves: int) -> void:
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = octaves


# --- Altura ---------------------------------------------------------------------------------

## Terreno viejo del pueblo (400 m), idéntico a la Fase 1-8.
func old_height(x: float, z: float) -> float:
	var h := float(cfg.get("base_height", 4.5)) + _noise.get_noise_2d(x, z) * float(cfg.get("hill_amp", 7.0))
	h += _detail.get_noise_2d(x, z) * 1.2
	if map_type == "montana":
		var r := 1.0 - absf(_ridge.get_noise_2d(x, z))
		r *= r
		var mask := smoothstep(-20.0, -170.0, z)
		h += r * 55.0 * mask + r * 3.0
	var dist := Vector2(x, z).length()
	h = lerpf(TOWN_HEIGHT, h, smoothstep(TOWN_FLAT_RADIUS, TOWN_FLAT_RADIUS + 22.0, dist))
	match map_type:
		"costa":
			var coast := 85.0 + _ridge.get_noise_1d(z) * 15.0
			h = lerpf(h, -9.0, smoothstep(coast - 30.0, coast + 25.0, x))
		"rio":
			var rx := 62.0 + sin(z * 0.012) * 30.0 + _ridge.get_noise_1d(z * 0.5) * 12.0
			h = lerpf(water_level - 2.5, h, smoothstep(5.0, 18.0, absf(x - rx)))
	return h


## Peso del terreno del país frente al del pueblo (0 dentro del chunk del pueblo).
func blend_at(x: float, z: float) -> float:
	return smoothstep(HALF_CHUNK, HALF_CHUNK + BLEND, maxf(absf(x), absf(z)))


## Altura continua en cualquier punto del país (m).
func height(x: float, z: float) -> float:
	var s := blend_at(x, z)
	if real and s > 0.0:
		var cr := _country_real(x, z)
		return cr.x if s >= 1.0 else lerpf(old_height(x, z), cr.x, s)
	if s <= 0.0:
		return old_height(x, z)
	var c: Vector2 = _country(x, z)
	if s >= 1.0:
		return c.x
	return lerpf(old_height(x, z), c.x, s)


## Relieve del país: devuelve (altura, mar) donde mar ∈ [0, 1] indica mar abierto.
func _country(x: float, z: float) -> Vector2:
	if real:
		return _country_real(x, z)
	var u := (x - center.x) / half_ext
	var v := (z - center.y) / half_ext
	var cont := _cont.get_noise_2d(x, z)
	# Costas del país (lados con mar) e islas: se calculan primero para los deltas.
	var land := 1.0
	var near_sea := 0.0
	var jag := _island.get_noise_2d(x, z) * 520.0 * sqrt(scale)
	var all_sides := coast_sides.has("todos")
	var dmin := 1e9
	if all_sides or coast_sides.has("oeste"):
		dmin = minf(dmin, (x - x_min) + jag)
	if all_sides or coast_sides.has("este"):
		dmin = minf(dmin, (x_max - x) + jag)
	if all_sides or coast_sides.has("norte"):
		dmin = minf(dmin, (z - x_min) + jag)
	if all_sides or coast_sides.has("sur"):
		dmin = minf(dmin, (x_max - z) + jag)
	if dmin < 1e8:
		land = smoothstep(0.0, coast_w, dmin)
		near_sea = 1.0 - smoothstep(coast_w, coast_w * 3.2, dmin)
	if _islands > 0.0:
		var il := cont * 0.7 + _island.get_noise_2d(x * 1.3, z * 1.3) * 0.75 + 0.42 - _islands * 0.55 - pow(maxf(absf(u), absf(v)), 4.0) * 0.4
		land = minf(land, smoothstep(-0.04, 0.1, il))
		near_sea = maxf(near_sea, 1.0 - smoothstep(0.1, 0.4, il))
	# El entorno del pueblo siempre es tierra firme.
	var town_guard := 1.0 - smoothstep(1100.0, 2200.0, Vector2(x, z).length())
	land = maxf(land, town_guard)
	# Relieve base y colinas.
	var e := 5.5 + cont * 6.0 + _hill.get_noise_2d(x, z) * (3.0 + 5.0 * (1.0 - _mountain * 0.5))
	e += _detail.get_noise_2d(x, z) * 1.2
	# Cordilleras: máscara grande × crestas (picos y valles).
	var mm := _mount.get_noise_2d(x, z) * 0.9 + (_mountain - 0.55) * 0.9
	if map_type == "montana":
		mm += smoothstep(-150.0, -2200.0, z) * 0.7
	var mask := smoothstep(0.0, 0.42, mm)
	if mask > 0.0:
		var r := 1.0 - absf(_mridge.get_noise_2d(x, z))
		r *= r
		e += mask * (r * _peak + 14.0 * mask)
	# Mesetas escalonadas con escarpes (fuera de las cordilleras).
	var pk := 0.0
	if _plateaus > 0.0:
		var pn := _plat.get_noise_2d(x, z)
		var thr := 0.5 - _plateaus * 0.42
		pk = smoothstep(thr, thr + 0.05, pn) * (1.0 - mask)
		if pk > 0.0:
			var top := 20.0 + 16.0 * smoothstep(thr, thr + 0.5, pn)
			var tier := smoothstep(thr + 0.18, thr + 0.22, pn) * 14.0
			e = lerpf(e, maxf(e, top + tier + _detail.get_noise_2d(x, z) * 0.8), pk)
	# Lagos (fuera de las montañas altas y de las mesetas).
	if _lakes > 0.0:
		var ln := _lake.get_noise_2d(x, z)
		var lthr := 0.68 - _lakes * 0.32 - near_sea * 0.12
		if ln > lthr:
			e = lerpf(e, water_level - 3.0, smoothstep(lthr, lthr + 0.1, ln) * (1.0 - mask) * (1.0 - pk))
	# Ríos largos: líneas de cero de un ruido deformado; cruzan muchos chunks. Cerca del mar se
	# ensanchan (deltas); en mesetas y montañas con cañones se hunden entre paredes verticales.
	if _rivers > 0.0:
		var wx := _warp.get_noise_2d(x, z) * 260.0
		var wz := _warp.get_noise_2d(z + 777.0, x - 333.0) * 260.0
		var rn := absf(_river.get_noise_2d(x + wx, z + wz))
		var w := (0.006 + 0.012 * _rivers) * (1.0 + 2.4 * near_sea * land)
		var rough := maxf(mask, pk)
		var fade := 1.0 - smoothstep(0.35, 0.8, mask) * (1.0 - _canyons)
		var bank := (1.0 - smoothstep(w, w * 3.2, rn)) * fade * (1.0 - rough * _canyons)
		if bank > 0.0:
			e = lerpf(e, minf(e, 3.0), bank * 0.7)   # valle
		var carve := (1.0 - smoothstep(w * 0.45, w, rn)) * fade
		if carve > 0.0:
			e = lerpf(e, water_level - 2.5, carve)
	# Rasgos del tipo de mapa, prolongados por todo el país.
	var sea := 0.0
	match map_type:
		"costa":
			var az := absf(z)
			var coast := 85.0 + _ridge.get_noise_1d(z) * 15.0 + z * z / 5200.0 + _warp.get_noise_1d(z * 0.35) * 260.0 * smoothstep(300.0, 2500.0, az)
			var k := smoothstep(coast - 30.0, coast + 25.0, x)
			e = lerpf(e, -9.0 - 5.0 * k, k)
			sea = k
		"rio":
			var az2 := absf(z)
			var rx := 62.0 + sin(z * 0.012) * 30.0 + _ridge.get_noise_1d(z * 0.5) * 12.0 + _warp.get_noise_1d(z * 0.08) * 700.0 * smoothstep(400.0, 3000.0, az2)
			var wide := 8.0 * smoothstep(300.0, 4000.0, az2)
			e = lerpf(water_level - 2.5, e, smoothstep(5.0 + wide, 18.0 + wide * 1.5, absf(x - rx)))
	# Mar abierto.
	if land < 1.0:
		e = lerpf(-14.0, e, land)
		if e > water_level and land < 0.5:
			e = lerpf(water_level - 1.0, e, land * 2.0)
	sea = maxf(sea, 1.0 - land)
	return Vector2(e, sea)


## Temperatura (-1 frío .. 1 caliente) y humedad (-1 seco .. 1 húmedo).
func climate(x: float, z: float, h: float) -> Vector2:
	if real:
		return _climate_real(x, z)
	var v := (z - center.y) / half_ext   # norte = -1 (más frío), sur = +1
	var t := _temperature + v * 0.5 * _lat_grad + _temp.get_noise_2d(x, z) * 0.25 - maxf(h, 0.0) / 150.0
	var m := _humidity + _hum.get_noise_2d(x, z) * 0.65 - _desert * 0.45
	return Vector2(t, m)


## Bioma (índice en BIOMES) dados el punto y su altura.
func biome_id(x: float, z: float, h: float) -> int:
	var s := blend_at(x, z)
	var sea := 0.0
	var mask := 0.0
	if s > 0.0 or map_type == "costa":
		sea = _country(x, z).y
	if h < water_level - 0.3:
		return B_MAR if sea > 0.5 else B_RIO
	if h < water_level + 1.1 and sea > 0.02:
		return B_COSTA
	var cl := climate(x, z, h)
	if cl.x < -0.62 or h > 150.0:
		return B_NEVADO
	if real:
		# Montaña por la altura real y lo abrupto del relieve.
		var el := real_elevation(x, z)
		var r := 1.0 - absf(_mridge.get_noise_2d(x, z))
		if el > 2800.0 or (el > 1200.0 and r > 0.72) or (h > 60.0 and r > 0.85):
			return B_MONTANA
	elif s > 0.0:
		mask = smoothstep(0.0, 0.42, _mount.get_noise_2d(x, z) * 0.9 + (_mountain - 0.55) * 0.9)
	if not real and h > 38.0 and (mask > 0.3 or h > 60.0):
		return B_MONTANA
	if h < 4.8 and cl.y > 0.25 - _swamp * 0.35 and _lake.get_noise_2d(x * 1.7, z * 1.7) > 0.1:
		return B_PANTANO
	if cl.x > 0.3 and cl.y < -0.25:
		return B_DESIERTO
	if cl.x > 0.42 and cl.y > 0.15:
		return B_SELVA
	if _forest.get_noise_2d(x * 0.25, z * 0.25) * 0.8 + cl.y * 0.5 + _forest_p * 0.6 > 0.45:
		return B_BOSQUE
	return B_LLANURA


func biome_at(x: float, z: float) -> String:
	return BIOMES[biome_id(x, z, height(x, z))]


## Color del suelo del país (antes de oscurecer lo ajeno o la niebla). `slope` = 1 - normal.y.
func ground_color(x: float, z: float, h: float, slope: float, biome: int) -> Color:
	var var_n := _detail.get_noise_2d(x * 3.0, z * 3.0) * 0.06
	var c: Color = BIOME_COLORS[biome]
	var grass := 1.0 if biome in [B_LLANURA, B_BOSQUE, B_SELVA, B_PANTANO] else 0.0
	if h < water_level - 0.2:
		c = Color(0.62, 0.58, 0.44)
		grass = 0.0
	elif biome != B_NEVADO and slope > 0.3:
		c = Color(0.5, 0.47, 0.44)
		grass = 0.0
	c = Color(c.r + var_n, c.g + var_n * 1.5, c.b + var_n)
	c.a = grass
	return c


## Color del terreno viejo (misma paleta que antes) para el entorno del pueblo.
func old_color(x: float, z: float, h: float, ny: float) -> Color:
	var grass := 0.0
	var c: Color
	var v := _detail.get_noise_2d(x * 3.0, z * 3.0) * 0.06
	if h < water_level - 0.2:
		c = Color(0.62, 0.58, 0.44)
	elif h < water_level + 0.8:
		c = Color(0.86, 0.8, 0.58)
	elif ny < 0.72:
		c = Color(0.5 + v, 0.47 + v, 0.44 + v)
	elif h > 34.0:
		c = Color(0.94, 0.95, 0.98)
	elif h > 22.0:
		c = Color(0.52 + v, 0.49 + v, 0.4 + v)
	else:
		c = Color(0.35 + v, 0.58 + v * 1.5, 0.27 + v)
		grass = 1.0
		if Vector2(x, z).length() < TOWN_FLAT_RADIUS - 4.0:
			c = c.lerp(Color(0.55, 0.52, 0.34), 0.25)
	c.a = grass
	return c


## Color final: mezcla la paleta vieja (pueblo) con la de biomas (país).
func color_at(x: float, z: float, h: float, ny: float) -> Color:
	var s := blend_at(x, z)
	if s <= 0.0:
		return old_color(x, z, h, ny)
	var gc := ground_color(x, z, h, 1.0 - ny, biome_id(x, z, h))
	if s >= 1.0:
		return gc
	return old_color(x, z, h, ny).lerp(gc, s)


## Densidad de árboles por bioma (0..1) y su color de copa.
static func tree_density(biome: int) -> float:
	match biome:
		B_SELVA: return 0.85
		B_BOSQUE: return 0.62
		B_PANTANO: return 0.2
		B_LLANURA: return 0.06
		B_MONTANA: return 0.08
		B_NEVADO: return 0.03
		B_DESIERTO: return 0.012
		B_COSTA: return 0.03
	return 0.0


static func tree_color(biome: int) -> Color:
	match biome:
		B_SELVA: return Color(0.1, 0.36, 0.14)
		B_PANTANO: return Color(0.3, 0.4, 0.2)
		B_NEVADO: return Color(0.55, 0.62, 0.6)
		B_DESIERTO: return Color(0.35, 0.5, 0.25)
		B_COSTA: return Color(0.28, 0.5, 0.22)
		B_MONTANA: return Color(0.16, 0.32, 0.2)
	return Color(0.2, 0.42, 0.2)


# --- Chunks y límites -------------------------------------------------------------------------

static func chunk_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori((x + HALF_CHUNK) / CHUNK), floori((z + HALF_CHUNK) / CHUNK))


static func chunk_rect(cx: int, cy: int) -> Rect2:
	return Rect2(cx * CHUNK - HALF_CHUNK, cy * CHUNK - HALF_CHUNK, CHUNK, CHUNK)


func in_country_chunk(cx: int, cy: int) -> bool:
	if cx < c0 or cx > c1 or cy < c0 or cy > c1:
		return false
	return not real or _chunk_in[(cy - c0) * size + (cx - c0)] == 1


## Dentro del país: en los reales, el chunk está dentro de la frontera real (misma regla que los chunks).
func in_country(x: float, z: float) -> bool:
	if x < x_min or x > x_max or z < x_min or z > x_max:
		return false
	if not real:
		return true
	var c := chunk_of(x, z)
	return in_country_chunk(c.x, c.y)


# --- Municipios (Voronoi de chunks) -----------------------------------------------------------

func _build_zones() -> void:
	zones = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 53 + country_id.hash() % 10000 + 17
	# Fase 9B: municipios grandes (de 6×6 a 10×10 chunks, unos 30–60 por país).
	var n := clampi(int(profile.get("zones", size * size / 70)), 4, 90)
	var ratio := float(profile.get("town_ratio", 0.6))
	var seeds: Array[Vector2] = [Vector2.ZERO]
	var fixed := {0: true}          # semillas que no se mueven (el jugador y los lugares reales)
	var seed_place := {}            # índice de semilla -> lugar real
	var in_count := size * size
	if real:
		in_count = 0
		for v in _chunk_in:
			in_count += int(v)
		n = clampi(in_count / 50, 6, 60)
	var min_gap := sqrt(float(in_count) / float(n)) * 0.72
	if real:
		# Municipios sembrados en lugares poblados reales (los más grandes primero).
		for pl in places:
			if seeds.size() >= n:
				break
			var pc := Vector2(float(pl["x"]) / CHUNK, float(pl["z"]) / CHUNK)
			var ci := Vector2i(roundi(pc.x), roundi(pc.y))
			if not in_country_chunk(ci.x, ci.y):
				continue
			var ok_p := true
			for sd in seeds:
				if (pc - sd).length() < min_gap:
					ok_p = false
					break
			if ok_p:
				fixed[seeds.size()] = true
				seed_place[seeds.size()] = pl
				seeds.append(pc)
	var tries := 0
	while seeds.size() < n and tries < n * 120:
		tries += 1
		var p := Vector2(rng.randi_range(c0 + 2, c1 - 2), rng.randi_range(c0 + 2, c1 - 2))
		if real and not in_country_chunk(int(p.x), int(p.y)):
			continue
		var ok := true
		for s in seeds:
			if (p - s).length() < min_gap:
				ok = false
				break
		if ok:
			seeds.append(p)
	# Relajación de Lloyd (2 pasadas): tamaños más parejos. El municipio 0 (jugador) queda en la plaza.
	var total := size * size
	_zone_of_chunk.resize(total)
	for it in range(2):
		var sums: Array[Vector2] = []
		var counts := PackedInt32Array()
		sums.resize(seeds.size())
		counts.resize(seeds.size())
		for i in range(seeds.size()):
			sums[i] = Vector2.ZERO
		for cy in range(c0, c1 + 1):
			for cx in range(c0, c1 + 1):
				if real and not in_country_chunk(cx, cy):
					continue
				var best := _nearest_seed(seeds, Vector2(cx, cy))
				sums[best] += Vector2(cx, cy)
				counts[best] += 1
		for i in range(1, seeds.size()):
			if counts[i] > 0 and not fixed.has(i):
				seeds[i] = sums[i] / counts[i]
	for i in range(seeds.size()):
		var sc := Vector2i(roundi(seeds[i].x), roundi(seeds[i].y))
		zones.append({"id": i, "seed": sc, "town": false, "player": i == 0, "town_chunk": sc, "town_pos": Vector2(sc) * CHUNK,
				"chunks": 0, "land": 0, "centroid": Vector2.ZERO, "neighbors": [], "bbox": Rect2i(),
				"real_name": str(seed_place[i]["name"]) if seed_place.has(i) else "", "real_pop": int(seed_place[i]["pop"]) if seed_place.has(i) else 0})
	# Asignación final con bordes irregulares (ruido suave + un poco de ruido por chunk).
	var sums2: Array[Vector2] = []
	sums2.resize(seeds.size())
	for i in range(seeds.size()):
		sums2[i] = Vector2.ZERO
	for cy in range(c0, c1 + 1):
		for cx in range(c0, c1 + 1):
			if real and not in_country_chunk(cx, cy):
				_zone_of_chunk[(cy - c0) * size + (cx - c0)] = -1
				continue
			var jitter := Vector2(_warp.get_noise_2d(cx * 240.0, cy * 240.0), _warp.get_noise_2d(cy * 240.0 + 5000.0, cx * 240.0)) * 2.6
			jitter += Vector2(_warp.get_noise_2d(cx * 97.0, cy * 97.0), _warp.get_noise_2d(cy * 97.0 + 500.0, cx * 97.0)) * 0.7
			var best := _nearest_seed(seeds, Vector2(cx, cy) + jitter)
			if maxi(absi(cx), absi(cy)) <= 1:
				best = 0   # el pueblo del jugador y sus vecinos siempre son de su municipio
			_zone_of_chunk[(cy - c0) * size + (cx - c0)] = best
			var z: Dictionary = zones[best]
			z["chunks"] = int(z["chunks"]) + 1
			sums2[best] += Vector2(cx, cy)
			if height(cx * CHUNK, cy * CHUNK) > water_level + 1.0:
				z["land"] = int(z["land"]) + 1
			var bb: Rect2i = z["bbox"]
			z["bbox"] = Rect2i(cx, cy, 1, 1) if bb.size == Vector2i.ZERO else bb.merge(Rect2i(cx, cy, 1, 1))
	for z in zones:
		if int(z["chunks"]) > 0:
			z["centroid"] = sums2[int(z["id"])] / int(z["chunks"]) * CHUNK
	# Vecindad entre municipios.
	for cy in range(c0, c1 + 1):
		for cx in range(c0, c1 + 1):
			var zi := zone_index(cx, cy)
			if zi < 0:
				continue
			for d in [Vector2i(1, 0), Vector2i(0, 1)]:
				var zj := zone_index(cx + d.x, cy + d.y)
				if zj >= 0 and zj != zi:
					var ni: Array = zones[zi]["neighbors"]
					if not ni.has(zj):
						ni.append(zj)
						(zones[zj]["neighbors"] as Array).append(zi)
	# Pueblos: el del jugador siempre; los demás según town_ratio, en un chunk de tierra cerca del centro.
	for z in zones:
		if bool(z["player"]):
			z["town"] = true
			z["town_chunk"] = Vector2i.ZERO
			z["town_pos"] = Vector2.ZERO
			continue
		var zi_real := int(z["id"])
		if real and seed_place.has(zi_real):
			# Pueblo real en su posición (si cae en tierra), si no en el chunk de tierra más cercano.
			var pl2: Dictionary = seed_place[zi_real]
			var pp := Vector2(float(pl2["x"]), float(pl2["z"]))
			if height(pp.x, pp.y) > water_level + 1.5 and zone_index(chunk_of(pp.x, pp.y).x, chunk_of(pp.x, pp.y).y) == zi_real:
				z["town"] = true
				z["town_chunk"] = chunk_of(pp.x, pp.y)
				z["town_pos"] = pp
				continue
		if int(z["land"]) < 6 or rng.randf() > ratio:
			continue
		var s := Vector2i(roundi(float(z["centroid"].x) / CHUNK), roundi(float(z["centroid"].y) / CHUNK))
		var found := false
		for r in range(0, 6):
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if found or maxi(absi(dx), absi(dy)) != r:
						continue
					var c := s + Vector2i(dx, dy)
					if not in_country_chunk(c.x, c.y) or zone_index(c.x, c.y) != int(z["id"]):
						continue
					var p := Vector2(c) * CHUNK + Vector2(rng.randf_range(-120, 120), rng.randf_range(-120, 120))
					var h := height(p.x, p.y)
					if h > water_level + 1.5 and h < 60.0 and height(p.x + 40.0, p.y) > water_level + 1.0 and height(p.x, p.y + 40.0) > water_level + 1.0:
						z["town"] = true
						z["town_chunk"] = c
						z["town_pos"] = p
						found = true


func _nearest_seed(seeds: Array[Vector2], p: Vector2) -> int:
	var best := 0
	var bd := 1e18
	for i in range(seeds.size()):
		var dd := p.distance_squared_to(seeds[i])
		if dd < bd:
			bd = dd
			best = i
	return best


## Chunks de un municipio (Vector2i).
func zone_chunks(zid: int) -> Array:
	var out := []
	if zid < 0 or zid >= zones.size():
		return out
	var bb: Rect2i = zones[zid]["bbox"]
	for cy in range(bb.position.y, bb.end.y):
		for cx in range(bb.position.x, bb.end.x):
			if zone_index(cx, cy) == zid:
				out.append(Vector2i(cx, cy))
	return out


## Municipio de un chunk (-1 fuera del país).
func zone_index(cx: int, cy: int) -> int:
	if cx < c0 or cx > c1 or cy < c0 or cy > c1:
		return -1
	return _zone_of_chunk[(cy - c0) * size + (cx - c0)]


# --- Vista general (minimapa y malla lejana) ------------------------------------------------

## Muestra alturas y biomas en una rejilla regular. Devuelve {x0, z0, step, w, h, heights, biomes}.
func sample_grid(x0: float, z0: float, step: float, w: int, h: int) -> Dictionary:
	var hs := PackedFloat32Array()
	var bs := PackedByteArray()
	hs.resize(w * h)
	bs.resize(w * h)
	for j in range(h):
		var z := z0 + j * step
		for i in range(w):
			var x := x0 + i * step
			var hh := height(x, z)
			hs[j * w + i] = hh
			bs[j * w + i] = biome_id(x, z, hh)
	return {"x0": x0, "z0": z0, "step": step, "w": w, "h": h, "heights": hs, "biomes": bs}
