class_name RegionSim
extends RefCounted
## Fase 6 — Recursos por región y yacimientos.
## Al fundar el pueblo se elige un lugar entre 3-4 candidatos del tipo de mapa; cada lugar
## multiplica ciertos recursos (strengths) y trae yacimientos ubicados en el mapa.
## Configuración: data/resources.json (GameData.extra("resources")).

static func cfg() -> Dictionary:
	return GameData.extra("resources")


static func resource_label(id: String) -> String:
	return str(cfg().get("resources", {}).get(id, {}).get("label", GameData.good_label(id)))


static func resource_color(id: String) -> Color:
	return MeshLib.arr_color(cfg().get("resources", {}).get(id, {}).get("color"), Color(0.6, 0.6, 0.6))


static func deposit_types() -> Array:
	var out := []
	var res: Dictionary = cfg().get("resources", {})
	for k in GameData.sorted_ids(res):
		if bool(res[k].get("deposit", false)):
			out.append(k)
	return out


# --- Lugares para fundar el pueblo ---------------------------------------------------------

## Candidatos deterministas según tipo de mapa y semilla (3-4 lugares).
static func candidates(map_type: String, seed_value: int) -> Array:
	var regions: Dictionary = cfg().get("regions", {})
	var pool: Array = regions.get(map_type, regions.get("interior", []))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 31 + 7
	var idx := range(pool.size())
	_shuffle(idx, rng)
	var names: Array = cfg().get("place_names", ["San Rafael"]).duplicate()
	_shuffle(names, rng)
	var out := []
	for i in range(mini(4, pool.size())):
		var t: Dictionary = pool[idx[i]].duplicate(true)
		t["place"] = str(names[i % names.size()])
		t["name"] = "%s de %s" % [str(t.get("label", "")), t["place"]]
		out.append(t)
	return out


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


## Región por id (o la primera candidata si no existe).
static func find(map_type: String, seed_value: int, id: String) -> Dictionary:
	var cands := candidates(map_type, seed_value)
	for c in cands:
		if str(c.get("id", "")) == id:
			return c
	return cands[0] if not cands.is_empty() else {"id": "", "label": "Región", "name": "Región", "strengths": {}, "deposits": {}}


## Texto corto de fortalezas: "Oro ×2 yac. · Tierra fértil +40%".
static func strengths_text(region: Dictionary) -> String:
	var parts := []
	var deps: Dictionary = region.get("deposits", {})
	for t in deps:
		if int(deps[t]) > 0:
			parts.append("%s (%d yacimiento%s)" % [resource_label(t), int(deps[t]), "s" if int(deps[t]) > 1 else ""])
	var st: Dictionary = region.get("strengths", {})
	for r in st:
		var pct := int(round((float(st[r]) - 1.0) * 100.0))
		if pct != 0:
			parts.append("%s %+d%%" % [resource_label(r), pct])
	return " · ".join(parts) if not parts.is_empty() else "Sin recursos destacados"


static func region(gs) -> Dictionary:
	return gs.logistics.get("region", {})


## Multiplicador de producción de un negocio según los recursos de la región.
static func region_mult(gs, b: Dictionary) -> float:
	var def: Dictionary = gs.building_def(b)
	var res := str(def.get("region_resource", cfg().get("business_resource", {}).get(str(b.get("type", "")), "")))
	if res == "":
		return 1.0
	return float(region(gs).get("strengths", {}).get(res, 1.0))


# --- Yacimientos -----------------------------------------------------------------------------

## Ubica los yacimientos de una región en el mapa (x, z, tipo y cantidad).
## El primero de cada tipo fuerte queda en el terreno inicial (cerca del pueblo pero fuera
## del alcance a pie de la plaza); los demás en zonas vecinas que hay que comprar.
static func generate_deposits(map_type: String, seed_value: int, reg: Dictionary) -> Array:
	# Solo se calculan las alturas del terreno (sin malla) para evitar agua y pendientes.
	var terrain := Terrain.new()
	terrain.generate(map_type, seed_value)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 97 + str(reg.get("id", "")).hash()
	var res_cfg: Dictionary = cfg().get("resources", {})
	var spacing := float(cfg().get("deposit_min_spacing", 18.0))
	var out := []
	var plan := []   # [tipo, anillo(0 = terreno inicial, 1 = vecino, 2 = lejano), factor de cantidad]
	var deps: Dictionary = reg.get("deposits", {})
	for t in deposit_types():
		var n := int(deps.get(t, 0))
		for i in range(n):
			plan.append([t, 0 if i == 0 else 1, 1.0])
	# Un yacimiento menor de otro tipo, lejos (a veces).
	if rng.randf() < float(cfg().get("minor_deposit_chance", 0.5)):
		var others := deposit_types().filter(func(t): return int(deps.get(t, 0)) == 0)
		if not others.is_empty():
			plan.append([others[rng.randi() % others.size()], 2, float(cfg().get("minor_deposit_amount", 0.35))])
	for p in plan:
		var t: String = p[0]
		var ring: int = p[1]
		var pos := _find_spot(terrain, rng, ring, out, spacing, map_type)
		var rng_amt: Array = res_cfg.get(t, {}).get("amount", [1000, 2000])
		var amount := snappedf(rng.randf_range(float(rng_amt[0]), float(rng_amt[1])) * float(p[2]), 1.0)
		out.append({"id": out.size() + 1, "type": t, "x": pos.x, "z": pos.y, "amount": amount, "initial": amount})
	terrain.free()
	return out


static func _find_spot(terrain: Terrain, rng: RandomNumberGenerator, ring: int, placed: Array, spacing: float, map_type: String) -> Vector2:
	var radii: Array = [[33.0, 37.0], [52.0, 115.0], [80.0, 150.0]][ring]
	var best := Vector2(35, 0)
	for attempt in range(120):
		var r := rng.randf_range(float(radii[0]), float(radii[1]))
		var ang := rng.randf() * TAU
		if map_type == "montana" and ring > 0 and attempt < 60:
			ang = rng.randf_range(PI * 1.1, PI * 1.9)   # Hacia la cordillera (norte, z negativo).
		var p := Vector2(cos(ang), sin(ang)) * r
		if ring == 0:
			p.x = clampf(p.x, -37.0, 37.0)
			p.y = clampf(p.y, -37.0, 37.0)
		p = p.snapped(Vector2(0.5, 0.5))
		var ok := true
		for d in placed:
			if p.distance_to(Vector2(float(d["x"]), float(d["z"]))) < spacing:
				ok = false
				break
		if not ok or not terrain.is_land(p.x, p.y, 0.8):
			continue
		best = p
		# Relajamos la exigencia de pendiente en los últimos intentos.
		if attempt > 90 or terrain.footprint_ok(p.x, p.y, 6.0) == "":
			return p
	return best


static func deposits(gs) -> Array:
	return gs.logistics.get("deposits", [])


static func get_deposit(gs, id: int) -> Dictionary:
	for d in deposits(gs):
		if int(d["id"]) == id:
			return d
	return {}


## Yacimiento más cercano de un tipo con mineral restante (o {} si no hay dentro del radio).
static func nearest_deposit(gs, type: String, x: float, z: float, max_dist := -1.0) -> Dictionary:
	if max_dist < 0.0:
		max_dist = float(cfg().get("deposit_radius", 11.0))
	var best := {}
	var best_d := max_dist
	for d in deposits(gs):
		if str(d["type"]) != type or float(d["amount"]) <= 0.0:
			continue
		var dist := Vector2(x, z).distance_to(Vector2(float(d["x"]), float(d["z"])))
		if dist <= best_d:
			best_d = dist
			best = d
	return best


## "" si el tipo no exige yacimiento o hay uno cerca; si no, el motivo.
static func deposit_block_reason(gs, type_id: String, x: float, z: float) -> String:
	var need := str(GameData.level_def(type_id, 1).get("requires_deposit", ""))
	if need == "":
		return ""
	if nearest_deposit(gs, need, x, z).is_empty():
		return "Debe construirse junto a un yacimiento de %s (míralos en Logística → Región)" % resource_label(need).to_lower()
	return ""


## Yacimiento que explota un edificio (el más cercano de su tipo).
static func deposit_for(gs, b: Dictionary) -> Dictionary:
	var need := str(gs.level_def(b).get("requires_deposit", ""))
	if need == "":
		return {}
	return nearest_deposit(gs, need, float(b["x"]), float(b["z"]))


## Descuenta mineral extraído y avisa cuando el yacimiento se agota.
static func deplete(gs, dep: Dictionary, qty: float) -> void:
	if dep.is_empty() or qty <= 0.0:
		return
	var before := float(dep["amount"])
	dep["amount"] = maxf(0.0, before - qty)
	var initial := maxf(1.0, float(dep.get("initial", before)))
	if before > initial * 0.1 and float(dep["amount"]) <= initial * 0.1:
		gs.notify("El yacimiento de %s está casi agotado (quedan %d unidades)." % [resource_label(str(dep["type"])).to_lower(), int(dep["amount"])], "negocio")
	elif float(dep["amount"]) <= 0.0:
		gs.notify("Se agotó un yacimiento de %s. La mina ya no produce." % resource_label(str(dep["type"])).to_lower(), "jugador")
