class_name MineSim
extends RefCounted
## Minas por partes (docs/MINAS.md). Configuración: data/mining.json (GameData.extra("mining")).
##
## - Yacimientos como ÁREAS irregulares: cada yacimiento de logistics["deposits"] tiene
##   radius (m), shape (12 multiplicadores radiales) y grade (ley). Los yacimientos puntuales
##   de partidas viejas (o de pruebas) se migran solos al leerlos (ensure_area), centrados en
##   el mismo punto y con ley 1.
## - El CENTRO DE EXCAVACIÓN es el negocio con requires_deposit (mina, pozo): se construye dentro
##   del área. Sin frentes solo ocupa center_share de los empleos del nivel.
## - FRENTES (tajo, socavón, torre de extracción; en pozos: torre de perforación, balancín) y
##   EXTRAS (escombrera) viven dentro del edificio: b["mine"] = {parts:[{id, kind, x, z, rot,
##   status: "obra"|"activo", days_left}], implicit, next_part, deposit_id}. Cada frente suma
##   capacidad (puestos productivos) y empleos; cuesta dinero y días de obra.
## - Producción ≈ min(empleados, capacidad) × productividad × ley × rendimiento (baja cuando
##   queda poca reserva) × (1 + bono de escombrera).
## - Migración: una mina sin b["mine"] (partidas viejas, NPC o pruebas que la crean directo)
##   recibe 1 frente implícito, así produce igual que antes.


static func cfg() -> Dictionary:
	return GameData.extra("mining")


# --- Datos -------------------------------------------------------------------------------------

## GameData.load_all llama esto: los centros de excavación usan los modelos (más grandes) de
## mining.json y su huella por nivel. Las piezas con "ore" toman el color del mineral.
static func patch_defs(gd) -> void:
	var m: Dictionary = gd.extra("mining")
	var models: Dictionary = m.get("center_models", {})
	var fps: Array = m.get("center_footprint", [])
	var pozos: Array = m.get("pozo_types", [])
	for t in gd.businesses:
		var def = gd.businesses[t]
		if not (def is Dictionary):
			continue
		var levels: Array = def.get("levels", [])
		if levels.is_empty() or str(levels[0].get("requires_deposit", "")) == "":
			continue
		var set_models: Array = models.get("pozo" if pozos.has(t) else "mina", [])
		if set_models.is_empty():
			continue
		var res := str(levels[0]["requires_deposit"])
		var rdef: Dictionary = gd.extra("resources").get("resources", {}).get(res, gd.extra("resources_energia").get("resources", {}).get(res, {}))
		var col: Array = rdef.get("color", [0.6, 0.6, 0.6])
		if not fps.is_empty():
			def["footprint"] = float(fps[0])
		for i in range(levels.size()):
			levels[i]["model"] = tint_parts(set_models[mini(i, set_models.size() - 1)], col)
			if i < fps.size():
				levels[i]["footprint"] = float(fps[i])


## Copia de un modelo con las piezas "ore" del color del mineral.
static func tint_parts(parts: Array, col: Array) -> Array:
	var out := []
	for p in parts:
		var q: Dictionary = (p as Dictionary).duplicate(true)
		if bool(q.get("ore", false)):
			q["c"] = col.duplicate()
		out.append(q)
	return out


static func is_mine_type(type_id: String) -> bool:
	return str(GameData.level_def(type_id, 1).get("requires_deposit", "")) != ""


static func is_mine(gs, b: Dictionary) -> bool:
	return not b.is_empty() and str(gs.level_def(b).get("requires_deposit", "")) != ""


## "mina" o "pozo" (qué frentes admite).
static func set_of(type_id: String) -> String:
	return "pozo" if (cfg().get("pozo_types", []) as Array).has(type_id) else "mina"


static func kind_def(kind: String) -> Dictionary:
	var f: Dictionary = cfg().get("face_types", {}).get(kind, {})
	return f if not f.is_empty() else cfg().get("extras", {}).get(kind, {})


static func is_face_kind(kind: String) -> bool:
	return cfg().get("face_types", {}).has(kind)


static func kind_label(kind: String) -> String:
	return str(kind_def(kind).get("label", kind))


## Frente básico del conjunto (el que cuentan los frentes implícitos).
static func basic_kind(type_id: String) -> String:
	return "pozo_bombeo" if set_of(type_id) == "pozo" else "tajo"


# --- Yacimientos como áreas --------------------------------------------------------------------

## Completa radio, forma y ley de un yacimiento (migra los puntuales). Determinista.
static func ensure_area(d: Dictionary) -> void:
	if d.has("radius") and d.has("shape"):
		return
	var t := str(d.get("type", ""))
	var c := cfg()
	var dc: Dictionary = c.get("deposits", {}).get(t, {})
	var rr: Array = dc.get("radius", [20.0, 28.0])
	var amt: Array = RegionSim.resource_def(t).get("amount", [1000, 2000])
	var initial := float(d.get("initial", d.get("amount", 0.0)))
	var f := clampf(inverse_lerp(float(amt[0]), float(amt[1]), initial), 0.0, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s_%d_%.1f_%.1f" % [t, int(d.get("id", 0)), float(d.get("x", 0.0)), float(d.get("z", 0.0))])
	var r := lerpf(float(rr[0]), float(rr[1]), f) * rng.randf_range(0.95, 1.05)
	var min_r := float(c.get("min_radius", 16.0))
	var dist := Vector2(float(d.get("x", 0.0)), float(d.get("z", 0.0))).length()
	r = clampf(r, min_r, maxf(min_r, dist - float(c.get("town_margin", 14.0))))   # No cubre la plaza.
	var raw := []
	for i in range(12):
		raw.append(rng.randf_range(0.78, 1.18))
	var shape := []
	for i in range(12):
		shape.append(snappedf((float(raw[i]) * 2.0 + float(raw[(i + 11) % 12]) + float(raw[(i + 1) % 12])) / 4.0, 0.01))
	d["radius"] = snappedf(r, 0.1)
	d["shape"] = shape
	if not d.has("grade"):
		d["grade"] = 1.0   # Yacimientos migrados: misma producción que antes.


## Yacimiento recién generado: además de su área, una ley aleatoria según el tipo.
static func init_new_deposit(d: Dictionary) -> void:
	var gr: Array = cfg().get("deposits", {}).get(str(d.get("type", "")), {}).get("grade", [1.0, 1.0])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("ley_%s_%d_%.1f" % [str(d.get("type", "")), int(d.get("id", 0)), float(d.get("x", 0.0)) + float(d.get("z", 0.0))])
	d["grade"] = snappedf(rng.randf_range(float(gr[0]), float(gr[1])), 0.01)
	ensure_area(d)


## Radio del área en una dirección (ángulo como Vector2.angle(): atan2(z, x)).
static func radius_at(d: Dictionary, ang: float) -> float:
	ensure_area(d)
	var shape: Array = d["shape"]
	var n := shape.size()
	var t := fposmod(ang, TAU) / TAU * n
	var i0 := int(floor(t)) % n
	var i1 := (i0 + 1) % n
	var f := smoothstep(0.0, 1.0, t - floor(t))
	return float(d["radius"]) * lerpf(float(shape[i0]), float(shape[i1]), f)


## ¿El punto (x, z) está dentro del área del yacimiento?
static func contains(d: Dictionary, x: float, z: float, margin := 0.0) -> bool:
	ensure_area(d)
	var v := Vector2(x - float(d["x"]), z - float(d["z"]))
	var len := v.length()
	if len > float(d["radius"]) * 1.25 + margin:
		return false
	return len <= radius_at(d, v.angle()) + margin


## Rendimiento por reserva: 1 hasta decline_start; baja linealmente hasta decline_min al agotarse.
static func depletion_mult(d: Dictionary) -> float:
	if d.is_empty():
		return 1.0
	var c := cfg()
	var frac := float(d.get("amount", 0.0)) / maxf(1.0, float(d.get("initial", d.get("amount", 1.0))))
	var start := float(c.get("decline_start", 0.3))
	if frac >= start:
		return 1.0
	var mn := float(c.get("decline_min", 0.5))
	return mn + (1.0 - mn) * clampf(frac / start, 0.0, 1.0)


static func reserve_frac(d: Dictionary) -> float:
	if d.is_empty():
		return 0.0
	return clampf(float(d.get("amount", 0.0)) / maxf(1.0, float(d.get("initial", d.get("amount", 1.0)))), 0.0, 1.0)


static func grade_text(g: float) -> String:
	var word := "alta" if g >= 1.08 else ("baja" if g < 0.93 else "media")
	return "%s (×%.2f)" % [word, g]


# --- Estado de una mina ------------------------------------------------------------------------

## Estado de minas del edificio. Sin él (partida vieja, NPC, prueba): 1 frente implícito.
static func state(b: Dictionary) -> Dictionary:
	if not b.has("mine") or not (b["mine"] is Dictionary):
		b["mine"] = {"parts": [], "implicit": 1, "next_part": 1}
	var m: Dictionary = b["mine"]
	if not m.has("parts"):
		m["parts"] = []
	m["implicit"] = int(m.get("implicit", 0))
	m["next_part"] = int(m.get("next_part", 1))
	return m


## Gancho de ConstructionSim.start_construction: una mina NUEVA empieza sin frentes.
static func on_new_building(_gs, b: Dictionary) -> void:
	if is_mine_type(str(b.get("type", ""))):
		b["mine"] = {"parts": [], "implicit": 0, "next_part": 1}


static func parts(b: Dictionary) -> Array:
	return state(b)["parts"]


static func faces(b: Dictionary, only_active := false) -> Array:
	return parts(b).filter(func(p): return is_face_kind(str(p["kind"])) and (not only_active or str(p.get("status", "")) == "activo"))


static func extras(b: Dictionary, only_active := false) -> Array:
	return parts(b).filter(func(p): return not is_face_kind(str(p["kind"])) and (not only_active or str(p.get("status", "")) == "activo"))


static func face_count(b: Dictionary) -> int:
	return faces(b).size() + int(state(b)["implicit"])


static func max_faces(gs, b: Dictionary) -> int:
	var arr: Array = cfg().get("max_faces", [2, 3, 4])
	return int(arr[clampi(int(b.get("level", 1)) - 1, 0, arr.size() - 1)])


static func _level_jobs(gs, b: Dictionary) -> int:
	return int(gs.level_def(b).get("jobs", 0))


## Puestos productivos que el centro solo puede ocupar.
static func center_capacity(gs, b: Dictionary) -> int:
	return mini(_level_jobs(gs, b), int(ceil(_level_jobs(gs, b) * float(cfg().get("center_share", 0.3)))))


## Puestos que suma un frente de ese tipo (un frente básico completa los empleos del nivel).
static func face_capacity(gs, b: Dictionary, kind: String) -> int:
	var base := _level_jobs(gs, b) - center_capacity(gs, b)
	return maxi(1, int(round(base * float(kind_def(kind).get("capacity_mult", 1.0)))))


## Capacidad total (puestos productivos) = centro + frentes activos + implícitos.
static func capacity(gs, b: Dictionary) -> int:
	if not is_mine(gs, b):
		return _level_jobs(gs, b)
	var total := center_capacity(gs, b) + int(state(b)["implicit"]) * face_capacity(gs, b, basic_kind(str(b["type"])))
	for p in faces(b, true):
		total += face_capacity(gs, b, str(p["kind"]))
	return total


## Empleos que admite el negocio (BusinessSim.hire). En minas = capacidad de los frentes.
static func jobs(gs, b: Dictionary) -> int:
	if not is_mine(gs, b):
		return _level_jobs(gs, b)
	return capacity(gs, b)


## Suma de productividades que cuenta (BusinessSim.expected_output): en una mina solo los
## mejores `capacity` empleados trabajan en un frente; los demás no tienen dónde picar.
static func workforce(gs, b: Dictionary, prods: Array) -> float:
	var total := 0.0
	if not is_mine(gs, b):
		for p in prods:
			total += float(p)
		return total
	var cap := capacity(gs, b)
	var sorted := prods.duplicate()
	sorted.sort()
	sorted.reverse()
	for i in range(mini(cap, sorted.size())):
		total += float(sorted[i])
	return total


## Ley × rendimiento por reserva × bono de extras (1 en negocios que no son minas).
static func yield_mult(gs, b: Dictionary) -> float:
	if not is_mine(gs, b):
		return 1.0
	var dep := RegionSim.deposit_for(gs, b)
	var bonus := 0.0
	for p in extras(b, true):
		bonus += float(kind_def(str(p["kind"])).get("bonus", 0.0))
	if dep.is_empty():
		return 1.0 + bonus
	return float(dep.get("grade", 1.0)) * depletion_mult(dep) * (1.0 + bonus)


## Producción diaria con todos los puestos productivos cubiertos por trabajadores normales.
static func potential_output(gs, b: Dictionary) -> float:
	var def: Dictionary = gs.building_def(b)
	var ld: Dictionary = gs.level_def(b)
	return capacity(gs, b) * float(ld.get("prod_per_worker", 1.0)) * RegionSim.region_mult(gs, b) \
		* TechSim.mult(gs, "production", str(def.get("product", ""))) * yield_mult(gs, b)


# --- Frentes y extras --------------------------------------------------------------------------

static func part_cost(gs, b: Dictionary, kind: String) -> float:
	return float(GameData.level_def(str(b["type"]), 1).get("cost", 0.0)) * float(kind_def(kind).get("cost_frac", 0.3)) * gs.price_mult()


static func part_footprint(kind: String) -> float:
	return float(kind_def(kind).get("footprint", 7.0))


## Tipos de frente/extra del conjunto de la mina, con el motivo si aún no se puede ("" = sí).
static func available_kinds(gs, b: Dictionary) -> Array:
	var out := []
	var set_id := set_of(str(b["type"]))
	var ft: Dictionary = cfg().get("face_types", {})
	var keys := ft.keys()
	keys.sort_custom(func(a, c): return int(ft[a].get("order", 0)) < int(ft[c].get("order", 0)))
	for k in keys:
		var fd: Dictionary = ft[k]
		if str(fd.get("set", "mina")) != set_id:
			continue
		out.append({"kind": k, "reason": kind_reason(gs, b, k)})
	var ex: Dictionary = cfg().get("extras", {})
	for k in ex:
		if str(ex[k].get("set", "mina")) == set_id:
			out.append({"kind": k, "reason": kind_reason(gs, b, k)})
	return out


## Por qué no se puede agregar ese tipo de frente/extra (sin mirar la ubicación).
static func kind_reason(gs, b: Dictionary, kind: String) -> String:
	var kd := kind_def(kind)
	if kd.is_empty():
		return "Tipo desconocido"
	if not gs.owned_by_player(b):
		return "Solo en tus minas"
	if int(b.get("level", 1)) < int(kd.get("min_level", 1)):
		return "Requiere mejorar la mina a nivel %d (%s)" % [int(kd["min_level"]), str(GameData.level_def(str(b["type"]), int(kd["min_level"])).get("label", ""))]
	var tech := str(kd.get("tech", ""))
	if tech != "" and not gs.has_tech(tech):
		return "Requiere investigar: %s" % GameData.tech_label(tech)
	if is_face_kind(kind):
		if face_count(b) >= max_faces(gs, b):
			return "Máximo %d frentes en este nivel: mejora la mina para abrir más" % max_faces(gs, b)
	elif parts(b).filter(func(p): return str(p["kind"]) == kind).size() >= int(kd.get("max", 1)):
		return "Ya tiene %s" % str(kd.get("label", kind)).to_lower()
	if gs.money < part_cost(gs, b, kind):
		return "Dinero insuficiente (%s)" % Fmt.money(part_cost(gs, b, kind))
	return ""


## "" si se puede poner ese frente/extra en (x, z); si no, el motivo.
static func part_block_reason(gs, b: Dictionary, kind: String, x: float, z: float) -> String:
	var r := kind_reason(gs, b, kind)
	if r != "":
		return r
	var fp := part_footprint(kind)
	var center := Vector2(float(b["x"]), float(b["z"]))
	var maxd := float(cfg().get("face_max_distance", 55.0))
	if center.distance_to(Vector2(x, z)) > maxd:
		return "Demasiado lejos del centro de excavación (máx. %d m)" % int(maxd)
	if is_face_kind(kind):
		var dep := RegionSim.deposit_for(gs, b)
		if dep.is_empty():
			return "La mina no tiene yacimiento con reserva"
		if not contains(dep, x, z):
			return "Los frentes van DENTRO del área del yacimiento de %s (zona teñida en el suelo)" % RegionSim.resource_label(str(dep["type"])).to_lower()
	if Vector2(x, z).length() < ConstructionSim.MIN_TOWN_CENTER_DIST + fp * 0.5:
		return "Demasiado cerca de la plaza"
	var zs: float = gs.MAP_SIZE / gs.ZONE_GRID
	var half: float = gs.MAP_SIZE * 0.5
	if not gs.is_zone_unlocked(clampi(int((x + half) / zs), 0, gs.ZONE_GRID - 1), clampi(int((z + half) / zs), 0, gs.ZONE_GRID - 1)):
		return "Terreno del gobierno: cómpralo primero"
	for o in gs.buildings:
		if Vector2(x, z).distance_to(Vector2(float(o["x"]), float(o["z"]))) < (fp + float(gs.footprint_of(o))) * 0.5 + 0.5:
			return "Se superpone con %s" % gs.building_label(o)
	var hit := parts_block_reason(gs, x, z, fp)
	if hit != "":
		return hit
	return ""


## Choque con frentes/extras de cualquier mina (gancho de ConstructionSim.placement_block_reason).
static func parts_block_reason(gs, x: float, z: float, fp: float, ignore_id := -1) -> String:
	for o in gs.buildings:
		if int(o["id"]) == ignore_id or not o.has("mine") or not (o["mine"] is Dictionary):
			continue
		for p in (o["mine"] as Dictionary).get("parts", []):
			if Vector2(x, z).distance_to(Vector2(float(p["x"]), float(p["z"]))) < (fp + part_footprint(str(p["kind"]))) * 0.5 + 0.5:
				return "Se superpone con un frente de %s" % gs.building_label(o)
	return ""


## Construye un frente o extra (paga y queda en obra build_days días).
static func add_part(gs, b: Dictionary, kind: String, x: float, z: float, rot := 0.0) -> String:
	var reason := part_block_reason(gs, b, kind, x, z)
	if reason != "":
		return reason
	var m := state(b)
	var cost := part_cost(gs, b, kind)
	BusinessSim.pay(gs, b, cost, "obras")
	var days := int(kind_def(kind).get("build_days", 8))
	m["parts"].append({"id": int(m["next_part"]), "kind": kind, "x": x, "z": z, "rot": rot, "status": "obra", "days_left": days})
	m["next_part"] = int(m["next_part"]) + 1
	gs.notify("Obra iniciada: %s en %s (%s, %d días)." % [kind_label(kind).to_lower(), gs.building_label(b), Fmt.money(cost), days], "construccion")
	EventBus.building_changed.emit(int(b["id"]))
	return ""


## Demuele un frente/extra (sin reembolso).
static func remove_part(gs, b: Dictionary, part_id: int) -> void:
	var m := state(b)
	var arr: Array = m["parts"]
	for i in range(arr.size()):
		if int(arr[i]["id"]) == part_id:
			arr.remove_at(i)
			EventBus.building_changed.emit(int(b["id"]))
			return


## Obras de frentes, mantenimiento y cierre de minas agotadas (una vez al día).
static func daily(gs) -> void:
	var pm: float = gs.price_mult()
	var speed := TechSim.mult(gs, "construction_speed")
	for b in gs.buildings:
		if not b.has("mine") or not gs.owned_by_player(b) or not is_mine(gs, b):
			continue
		var m := state(b)
		for p in m["parts"]:
			if str(p.get("status", "")) == "obra":
				p["days_left"] = float(p.get("days_left", 0)) - speed
				if float(p["days_left"]) <= 0.0:
					p["status"] = "activo"
					p["days_left"] = 0
					gs.notify("Terminado: %s de %s." % [kind_label(str(p["kind"])).to_lower(), gs.building_label(b)], "construccion")
					EventBus.building_changed.emit(int(b["id"]))
			elif str(b["status"]) != "cerrado":
				var up := float(kind_def(str(p["kind"])).get("upkeep", 0.0)) * pm
				if up > 0.0:
					BusinessSim.pay(gs, b, up, "mantenimiento")
		_check_exhausted(gs, b, m)


## Cierre al agotarse: el yacimiento que explotaba quedó en 0 y no hay otro.
static func _check_exhausted(gs, b: Dictionary, m: Dictionary) -> void:
	if str(b["status"]) != "activo" or not m.has("deposit_id"):
		return
	var dep := RegionSim.get_deposit(gs, int(m["deposit_id"]))
	if not dep.is_empty() and float(dep["amount"]) > 0.0:
		return
	if not RegionSim.deposit_for(gs, b).is_empty():
		return
	for c in gs.employees_of(int(b["id"])):
		if c.job_kind == "empleo":
			BusinessSim.fire(gs, c)
	b["status"] = "cerrado"
	b["chain_status"] = "sin yacimiento"
	gs.notify("%s cerró: su yacimiento se agotó. Demuélela o construye otra mina en un yacimiento con reserva." % gs.building_label(b), "jugador")
	EventBus.building_changed.emit(int(b["id"]))
