class_name Housing
extends RefCounted
## Calidades de vivienda (normal/media/alta) e interiores automáticos:
## cada espacio de la casa usa el mejor objeto permitido por su calidad y la época (tecnologías).

const TIERS := ["normal", "media", "alta"]


static func tier_def(b: Dictionary) -> Dictionary:
	return tier_def_by_id(str(b.get("tier", "normal")))


static func tier_def_by_id(tier: String) -> Dictionary:
	return GameData.buildings.get("vivienda", {}).get("tiers", {}).get(tier, {})


static func tier_index(b: Dictionary) -> int:
	return maxi(0, TIERS.find(str(b.get("tier", "normal"))))


static func tier_label(tier: String) -> String:
	return str(tier_def_by_id(tier).get("label", tier))


static func is_home(b: Dictionary) -> bool:
	return str(b.get("type", "")) == "vivienda"


## Lista de objetos del interior: [{slot, item, pos: Vector2 (normalizada), rot, index}]
static func interior_items(gs, b: Dictionary) -> Array:
	var cfg := GameData.interiors
	var catalog: Dictionary = cfg.get("items", {})
	var layout: Dictionary = cfg.get("layout", {})
	var tier := tier_index(b)
	var level := int(b.get("level", 1))
	var out := []
	for slot in catalog:
		var best: Dictionary = {}
		for item in catalog[slot]:
			if not item_allowed(item, level, tier) or not gs.has_tech(str(item.get("tech", ""))):
				continue
			if best.is_empty() or int(item.get("rank", 0)) > int(best.get("rank", 0)):
				best = item
		if best.is_empty() or best.get("parts", []).is_empty():
			continue
		var l: Dictionary = layout.get(slot, {"pos": [0, 0], "rot": 0})
		var count := 1
		if slot == "cama":
			count = clampi(ceili(gs.building_capacity(b) / 3.0), 1, 3)
		for i in range(count):
			var p := Vector2(float(l["pos"][0]) + i * float(cfg.get("extra_beds_step", 0.2)), float(l["pos"][1]))
			out.append({"slot": slot, "item": best, "pos": p, "rot": float(l.get("rot", 0)), "index": i})
	return out


## Un objeto se permite si la casa cumple alguno de sus requisitos [nivel, calidad].
static func item_allowed(item: Dictionary, level: int, tier: int) -> bool:
	var reqs: Array = item.get("req", [[1, int(item.get("tier_min", 0))]])
	for r in reqs:
		if level >= int(r[0]) and tier >= int(r[1]):
			return true
	return false


static func floor_color(b: Dictionary) -> Color:
	var floors: Dictionary = GameData.interiors.get("floors", {})
	var by_level: Dictionary = floors.get(str(int(b.get("level", 1))), floors.get("default", {}))
	return MeshLib.arr_color(by_level.get(str(b.get("tier", "normal"))), Color(0.5, 0.4, 0.3))


## Modelo exterior según nivel y calidad (algunas calidades tienen modelo propio).
static func exterior_parts(b: Dictionary) -> Array:
	var ld := GameData.level_def(str(b.get("type", "")), int(b.get("level", 1)))
	var tm: Dictionary = ld.get("tier_models", {})
	var tier := str(b.get("tier", "normal"))
	if tm.has(tier):
		return tm[tier]
	return ld.get("model", [])


static func room_def(b: Dictionary) -> Dictionary:
	var rooms: Array = GameData.interiors.get("rooms", [])
	if rooms.is_empty():
		return {"size": [8, 7], "wall_h": 2.8, "wall": [0.8, 0.7, 0.5]}
	return rooms[clampi(int(b.get("level", 1)) - 1, 0, rooms.size() - 1)]


## Descripción corta de los objetos (para la interfaz).
static func interior_summary(gs, b: Dictionary) -> String:
	var names := []
	var seen := {}
	for it in interior_items(gs, b):
		var label := str(it["item"].get("label", ""))
		if not seen.has(label):
			seen[label] = true
			names.append(label)
	return ", ".join(names)
