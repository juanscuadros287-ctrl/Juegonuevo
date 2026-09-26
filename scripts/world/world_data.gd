class_name WorldData
extends RefCounted
## Mapa mundial con países reales (datos de dominio público preprocesados por tools/build_world.py):
##   data/world/world.json            contornos simplificados de todos los países (mapa mundial)
##   data/world/profiles.json         perfiles de los países jugables (moneda, idioma, recursos, inflación)
##   data/world/countries/<ISO>.json  rejilla del país a escala del juego (altura real, frontera, tierra,
##                                    lagos, desiertos, ríos) y lugares poblados reales
## En tiempo de ejecución no se descarga nada. Solo lectura: se puede usar desde hilos tras cargar.

const DIR := "res://data/world/"

static var _world: Dictionary = {}
static var _profiles: Dictionary = {}
static var _countries: Dictionary = {}     # iso -> datos decodificados
static var _mutex := Mutex.new()
static var _defs: Dictionary = {}


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func world() -> Dictionary:
	if _world.is_empty():
		_world = _read_json(DIR + "world.json")
	return _world


static func profiles() -> Dictionary:
	if _profiles.is_empty():
		_profiles = _read_json(DIR + "profiles.json")
	return _profiles


## ¿Es un país real jugable (tiene perfil y rejilla)?
static func is_real(id: String) -> bool:
	return profiles().get("countries", {}).has(id) and FileAccess.file_exists(DIR + "countries/%s.json" % id)


## Países reales jugables, ordenados por nombre.
static func playable_ids() -> Array:
	var ids := []
	for id in profiles().get("countries", {}):
		if FileAccess.file_exists(DIR + "countries/%s.json" % id):
			ids.append(str(id))
	ids.sort_custom(func(a, b) -> bool: return country_name(a) < country_name(b))
	return ids


static func country_name(id: String) -> String:
	var p: Dictionary = profiles().get("countries", {}).get(id, {})
	if p.has("name"):
		return str(p["name"])
	for c in world().get("countries", []):
		if str(c.get("iso", "")) == id:
			return str(c.get("name", id))
	return id


## Perfil del país (valores por defecto para los que no están definidos).
static func profile(id: String) -> Dictionary:
	var p: Dictionary = profiles().get("default", {}).duplicate(true)
	p.merge(profiles().get("countries", {}).get(id, {}), true)
	return p


## Datos de la rejilla del país ya decodificados: {iso, size, km_per_chunk, origin, grid{m, cell, x0,
## elev: PackedInt32Array (m reales), flags: PackedByteArray, rdist: PackedByteArray, rwid: PackedByteArray},
## places, lat_range, start_name}.
static func country_data(id: String) -> Dictionary:
	_mutex.lock()
	if _countries.has(id):
		var cached: Dictionary = _countries[id]
		_mutex.unlock()
		return cached
	var d := _read_json(DIR + "countries/%s.json" % id)
	if not d.is_empty():
		var g: Dictionary = d["grid"]
		var m := int(g["m"])
		var raw := _unpack(str(g["elev"]), m * m * 2)
		var elev := PackedInt32Array()
		elev.resize(m * m)
		for i in range(m * m):
			elev[i] = raw.decode_s16(i * 2)
		g["elev"] = elev
		g["flags"] = _unpack(str(g["flags"]), m * m)
		g["rdist"] = _unpack(str(g["rdist"]), m * m)
		g["rwid"] = _unpack(str(g["rwid"]), m * m)
	_countries[id] = d
	_mutex.unlock()
	return d


static func _unpack(b64: String, size: int) -> PackedByteArray:
	var comp := Marshalls.base64_to_raw(b64)
	return comp.decompress(size, FileAccess.COMPRESSION_GZIP)


## Definición de país (mismo formato que los países de respaldo de data/countries.json).
static func country_def(id: String) -> Dictionary:
	if _defs.has(id):
		return _defs[id]
	_defs[id] = _make_def(id)
	return _defs[id]


static func _make_def(id: String) -> Dictionary:
	var p := profile(id)
	var d := country_data(id)
	var size := int(d.get("size", 64))
	var land := int(d.get("country_chunks_side", size))
	var res: Dictionary = p.get("resources", {})
	var desc := "%s · idioma: %s · moneda: %s. Recursos: %s. Escala 1 chunk = %.1f km reales." % [
		str(p.get("name", id)), str(p.get("language", "")), str(p.get("currency", {}).get("name", "")),
		", ".join(PackedStringArray(p.get("real_resources", []))), float(d.get("km_per_chunk", 0.0))]
	return {"label": str(p.get("name", id)), "real": true, "iso": id, "size": size, "order": 100,
			"inspiration": "País real (Natural Earth, ETOPO1)", "description": desc,
			"terrain": {"forest": float(p.get("forest", 0.4)), "humidity": float(p.get("humidity", 0.0))},
			"zones": clampi(int(land * land * 0.5 / 64.0), 10, 60), "town_ratio": float(p.get("town_ratio", 0.75)),
			"resources": res, "real_resources": p.get("real_resources", []), "language": str(p.get("language", "")),
			"currency": p.get("currency", {}), "base_inflation": float(p.get("base_inflation", 0.05)),
			"exchange_rate_to_ref": float(p.get("usd_per_unit", 1.0)), "km_per_chunk": float(d.get("km_per_chunk", 0.0))}
