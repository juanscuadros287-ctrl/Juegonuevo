class_name TechSim
extends RefCounted
## Investigación: los laboratorios producen puntos que avanzan el proyecto actual.
## Las tecnologías desbloquean niveles de edificios/muebles (campo "tech" en los JSON),
## aplican efectos (producción, enfermedad, mortalidad, obras, felicidad) y cambian de época.


static func init_state(gs) -> void:
	gs.research = {"era": 1, "current": "", "progress": 0.0, "bank": 0.0, "queue": [],
		"points_today": 0.0, "points_yesterday": 0.0, "mods": {}}


static func tech(id: String) -> Dictionary:
	return GameData.technologies.get(id, {})


static func era(gs) -> int:
	return int(gs.research.get("era", 1))


static func cost(id: String) -> float:
	return float(tech(id).get("cost", 100))


## "" si se puede investigar; si no, el motivo.
static func block_reason(gs, id: String) -> String:
	var t := tech(id)
	if t.is_empty():
		return "Desconocida"
	if gs.techs.has(id):
		return "Ya investigada"
	if int(t.get("era", 1)) > era(gs):
		return "Requiere la %s" % GameData.era_label(int(t.get("era", 1)))
	var missing := []
	for r in t.get("requires", []):
		if not gs.techs.has(r):
			missing.append(GameData.tech_label(r))
	if not missing.is_empty():
		return "Requiere: " + ", ".join(missing)
	return ""


static func set_current(gs, id: String) -> String:
	var r := block_reason(gs, id)
	if r != "":
		return r
	if str(gs.research.get("current", "")) != id:
		gs.research["current"] = id
		gs.research["progress"] = 0.0
	gs.research["queue"].erase(id)
	return ""


static func enqueue(gs, id: String) -> String:
	if gs.techs.has(id) or gs.research["queue"].has(id) or gs.research["current"] == id:
		return "Ya está en la cola"
	if tech(id).is_empty():
		return "Desconocida"
	gs.research["queue"].append(id)
	if str(gs.research["current"]) == "":
		_next_from_queue(gs)
	return ""


## Suma puntos al proyecto actual (o al banco si no hay proyecto).
static func add_points(gs, pts: float) -> void:
	pts *= mult(gs, "research")
	gs.research["points_today"] = float(gs.research.get("points_today", 0.0)) + pts
	var cur := str(gs.research.get("current", ""))
	if cur == "":
		gs.research["bank"] = float(gs.research.get("bank", 0.0)) + pts
		return
	var total := float(gs.research["progress"]) + pts + float(gs.research.get("bank", 0.0))
	gs.research["bank"] = 0.0
	if total >= cost(cur):
		gs.research["bank"] = total - cost(cur)
		complete(gs, cur)
	else:
		gs.research["progress"] = total


static func end_day(gs) -> void:
	gs.research["points_yesterday"] = float(gs.research.get("points_today", 0.0))
	gs.research["points_today"] = 0.0


static func complete(gs, id: String) -> void:
	if not gs.techs.has(id):
		gs.techs.append(id)
	gs.research["current"] = ""
	gs.research["progress"] = 0.0
	var t := tech(id)
	var msg := "Investigación completada: %s." % GameData.tech_label(id)
	var unlocks := unlocks_of(id)
	if not unlocks.is_empty():
		msg += " Desbloquea: %s." % ", ".join(unlocks.slice(0, 4))
	if t.has("future"):
		msg += " (%s)" % t["future"]
	for e in t.get("effects", []):
		if e.get("type", "") == "era" and int(e["value"]) > era(gs):
			gs.research["era"] = int(e["value"])
			gs.notify("¡Nueva época: %s!" % GameData.era_label(int(e["value"])), "importante")
	_recompute_mods(gs)
	gs.notify(msg, "importante")
	EventBus.tech_researched.emit(id)
	_next_from_queue(gs)


static func _next_from_queue(gs) -> void:
	var q: Array = gs.research.get("queue", [])
	while not q.is_empty():
		var nxt: String = q.pop_front()
		if block_reason(gs, nxt) == "":
			gs.research["current"] = nxt
			gs.research["progress"] = 0.0
			return


static func _recompute_mods(gs) -> void:
	var mods := {}
	for id in gs.techs:
		for e in tech(id).get("effects", []):
			var key := str(e.get("type", ""))
			if e.has("key"):
				key += ":" + str(e["key"])
			if key.begins_with("era"):
				continue
			if str(e.get("type", "")) == "happiness":
				mods[key] = float(mods.get(key, 0.0)) + float(e["value"])
			else:
				mods[key] = float(mods.get(key, 1.0)) * float(e["value"])
	gs.research["mods"] = mods


## Multiplicador acumulado de un tipo de efecto (1 si no hay).
static func mult(gs, type: String, key := "") -> float:
	var mods: Dictionary = gs.research.get("mods", {})
	var m := float(mods.get(type, 1.0))
	if type == "research":
		m *= HeirsSim.research_mult(gs)   # Sección C: talento de ciencia del jefe de familia.
	if key != "":
		m *= float(mods.get(type + ":" + key, 1.0)) * float(mods.get(type + ":all", 1.0))
	return m


static func happiness_bonus(gs) -> float:
	return float(gs.research.get("mods", {}).get("happiness", 0.0)) + GovSim.project_happiness(gs) + EventsSim.pollution_happiness(gs)


## Multiplicador combinado de tecnología, obras públicas, eventos y contaminación.
static func world_mult(gs, key: String) -> float:
	var m := mult(gs, key) * GovSim.project_mult(gs, key) * EventsSim.mult(gs, key)
	if key == "disease":
		m *= EventsSim.pollution_disease_mult(gs)
	return m


## Qué desbloquea una tecnología (niveles de edificios y objetos de las casas).
static func unlocks_of(id: String) -> Array:
	var out := []
	for src in [GameData.buildings, GameData.businesses]:
		for type_id in src:
			var levels: Array = src[type_id].get("levels", [])
			for i in range(levels.size()):
				if str(levels[i].get("tech", "")) == id:
					out.append(str(levels[i].get("label", type_id)))
	for slot in GameData.interiors.get("items", {}):
		for item in GameData.interiors["items"][slot]:
			if str(item.get("tech", "")) == id:
				out.append(str(item.get("label", "")))
	return out


static func effects_text(id: String) -> Array:
	var out := []
	for e in tech(id).get("effects", []):
		var v := float(e.get("value", 1.0))
		match str(e.get("type", "")):
			"production":
				var k := str(e.get("key", ""))
				out.append("Producción de %s +%d%%" % ["todo" if k == "all" else GameData.good_label(k), int(round((v - 1.0) * 100.0))])
			"disease":
				out.append("Enfermedades −%d%%" % int(round((1.0 - v) * 100.0)))
			"mortality":
				out.append("Mortalidad −%d%% (más esperanza de vida)" % int(round((1.0 - v) * 100.0)))
			"construction_speed":
				out.append("Obras +%d%% más rápidas" % int(round((v - 1.0) * 100.0)))
			"research":
				out.append("Investigación +%d%%" % int(round((v - 1.0) * 100.0)))
			"happiness":
				out.append("Felicidad +%d" % int(v))
			"era":
				out.append("Abre la %s" % GameData.era_label(int(v)))
			"clima":   # Mundo: mitigación de eventos climáticos (ClimateSim).
				out.append("Daño por %s −%d%%" % [str(ClimateSim.ev_def(str(e.get("key", ""))).get("label", e.get("key", ""))).to_lower(), int(round((1.0 - v) * 100.0))])
	return out


## Puntos diarios estimados de un laboratorio.
static func lab_output(gs, b: Dictionary) -> float:
	var out := BusinessSim.expected_output(gs, b)
	var cur := str(gs.research.get("current", ""))
	if cur != "" and str(b.get("specialty", "general")) == str(tech(cur).get("branch", "")):
		out *= 1.5
	return out * mult(gs, "research")
