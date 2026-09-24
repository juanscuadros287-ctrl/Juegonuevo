extends Node
## Carga toda la configuración del juego desde res://data/*.json.
## Para agregar contenido (negocios, tecnologías, leyes…) basta con editar/añadir JSON.

const DATA_DIR := "res://data/"

var game: Dictionary = {}
var difficulties: Dictionary = {}
var map_types: Dictionary = {}
var names: Dictionary = {}
var citizens: Dictionary = {}
var weather: Dictionary = {}
var skills: Dictionary = {}
var buildings: Dictionary = {}
var businesses: Dictionary = {}
var goods: Dictionary = {}
var legal_types: Dictionary = {}
var technologies: Dictionary = {}
var interiors: Dictionary = {}
var economy: Dictionary = {}
var eras: Dictionary = {}
var professions: Dictionary = {}
var government: Dictionary = {}
var events: Dictionary = {}


func _ready() -> void:
	load_all()


func load_all() -> void:
	game = _load("game.json")
	difficulties = _load("difficulties.json")
	map_types = _load("map_types.json")
	names = _load("names.json")
	citizens = _load("citizens.json")
	weather = _load("weather.json")
	skills = _load("skills.json")
	buildings = _load_merged("buildings")
	businesses = _load_merged("businesses")
	goods = _load_merged("goods")
	legal_types = _load("legal_types.json")
	technologies = _load_merged("technologies")
	interiors = _load("interiors.json")
	economy = _load("economy.json")
	eras = _load("eras.json")
	professions = _load("professions.json")
	government = _load("government.json")
	events = _load("events.json")
	_extra = {}


## Carga <base>.json y fusiona encima todos los <base>_*.json (contenido modular por fase).
func _load_merged(base: String) -> Dictionary:
	var out := _load(base + ".json")
	var files := Array(DirAccess.get_files_at(DATA_DIR))
	files.sort()
	for f in files:
		var fname := str(f).trim_suffix(".remap").trim_suffix(".import")
		if fname.begins_with(base + "_") and fname.ends_with(".json"):
			var extra := _load(fname)
			for k in extra:
				if not str(k).begins_with("_"):
					out[k] = extra[k]
	return out


var _extra := {}


## Datos adicionales de un módulo: data/<name>.json (se cargan una vez y quedan en caché).
func extra(name: String) -> Dictionary:
	if not _extra.has(name):
		_extra[name] = _load(name + ".json") if FileAccess.file_exists(DATA_DIR + name + ".json") else {}
	return _extra[name]


func _load(file_name: String) -> Dictionary:
	var path := DATA_DIR + file_name
	if not FileAccess.file_exists(path):
		push_error("GameData: no existe %s" % path)
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	push_error("GameData: JSON inválido en %s" % path)
	return {}


func difficulty(id: String) -> Dictionary:
	return difficulties.get(id, difficulties.get("normal", {}))


func map_type(id: String) -> Dictionary:
	return map_types.get(id, map_types.get("interior", {}))


## Devuelve los ids de un diccionario de configuración ordenados por su campo "order".
func sorted_ids(dict: Dictionary) -> Array:
	var ids := dict.keys()
	ids.sort_custom(func(a, b): return int(dict[a].get("order", 0)) < int(dict[b].get("order", 0)))
	return ids


func skill_ids() -> Array:
	return skills.get("skills", {}).keys()


func skill_label(id: String) -> String:
	return str(skills.get("skills", {}).get(id, {}).get("label", id))


func education_label(level: int) -> String:
	var levels: Array = skills.get("education_levels", ["Ninguna"])
	return str(levels[clampi(level, 0, levels.size() - 1)])


func currency() -> String:
	return str(game.get("currency_symbol", "$"))


# --- Edificios y negocios ----------------------------------------------------------

## Definición de un tipo construible (vivienda, oficina o negocio).
func building_def(type_id: String) -> Dictionary:
	if buildings.has(type_id):
		return buildings[type_id]
	return businesses.get(type_id, {})


func level_def(type_id: String, level: int) -> Dictionary:
	var levels: Array = building_def(type_id).get("levels", [])
	if levels.is_empty():
		return {}
	return levels[clampi(level - 1, 0, levels.size() - 1)]


## Huella (lado en metros) del edificio en un nivel: la base "footprint" crece con el
## tamaño del modelo del nivel (o usa "footprint" del nivel si lo define).
func footprint(type_id: String, level := 1) -> float:
	var base := float(building_def(type_id).get("footprint", 4.0))
	var ld := level_def(type_id, level)
	if ld.has("footprint"):
		return float(ld["footprint"])
	if level <= 1:
		return base
	var w1 := _model_width(level_def(type_id, 1))
	var wl := _model_width(ld)
	if w1 <= 0.0 or wl <= 0.0:
		return base
	return base * clampf(wl / w1, 1.0, 2.5)


func _model_width(ld: Dictionary) -> float:
	var w := 0.0
	for piece in ld.get("model", []):
		if not (piece is Dictionary) or not piece.has("size"):
			continue
		var sz: Array = piece["size"]
		var pos: Array = piece.get("pos", [0, 0, 0])
		var ext := maxf(float(sz[0]), float(sz[2]) if sz.size() > 2 else float(sz[0])) * 0.5
		w = maxf(w, maxf(absf(float(pos[0])), absf(float(pos[2]) if pos.size() > 2 else 0.0)) + ext)
	return w * 2.0


## Personas que caben (camas) según nivel y calidad: "capacity_by_tier" o "capacity".
func capacity(type_id: String, level: int, tier := "normal") -> int:
	var ld := level_def(type_id, level)
	var bt: Dictionary = ld.get("capacity_by_tier", {})
	if bt.has(tier):
		return int(bt[tier])
	return int(ld.get("capacity", 0))


func max_level(type_id: String) -> int:
	return building_def(type_id).get("levels", []).size()


## Todos los tipos construibles ordenados: viviendas, oficina y luego negocios.
func buildable_ids() -> Array:
	var out := sorted_ids(buildings).filter(func(id): return str(buildings[id].get("category", "")) != "publico")
	out.append_array(sorted_ids(businesses))
	return out


func good_label(id: String) -> String:
	return str(goods.get(id, {}).get("label", id))


func tech_label(id: String) -> String:
	return str(technologies.get(id, {}).get("label", id))


func tech_ids() -> Array:
	return technologies.keys().filter(func(k): return not str(k).begins_with("_"))


func era_label(era: int) -> String:
	for e in eras.get("eras", []):
		if int(e["id"]) == era:
			return str(e["label"])
	return "Época %d" % era


func branch_label(id: String) -> String:
	for b in eras.get("branches", []):
		if b[0] == id:
			return str(b[1])
	return id


func profession_ids() -> Array:
	return sorted_ids(professions.get("professions", {}))


func profession_label(id: String) -> String:
	return str(professions.get("professions", {}).get(id, {}).get("label", id))


func career_label(id: String) -> String:
	return str(professions.get("professions", {}).get(id, {}).get("career", id))
