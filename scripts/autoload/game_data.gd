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
	buildings = _load("buildings.json")
	businesses = _load("businesses.json")
	goods = _load("goods.json")
	legal_types = _load("legal_types.json")
	technologies = _load("technologies.json")
	interiors = _load("interiors.json")


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


func max_level(type_id: String) -> int:
	return building_def(type_id).get("levels", []).size()


## Todos los tipos construibles ordenados: viviendas, oficina y luego negocios.
func buildable_ids() -> Array:
	var out := sorted_ids(buildings)
	out.append_array(sorted_ids(businesses))
	return out


func good_label(id: String) -> String:
	return str(goods.get(id, {}).get("label", id))


func tech_label(id: String) -> String:
	return str(technologies.get(id, {}).get("label", id))
