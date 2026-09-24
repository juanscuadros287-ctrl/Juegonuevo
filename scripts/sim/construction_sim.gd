class_name ConstructionSim
extends RefCounted
## Construcción y mejora de edificios: costos (dinero + materiales), obra con
## trabajadores (jornaleros o tu constructora) y tiempo. Expansión de zonas.

const MIN_TOWN_CENTER_DIST := 9.5


## Crea un diccionario de edificio con todos los campos por defecto.
static func make_building(gs, type_id: String, level: int, x: float, z: float, rot: float, owner: String) -> Dictionary:
	var b := {
		"id": gs.next_building_id, "type": type_id, "level": level,
		"x": x, "z": z, "rot": rot, "owner": owner, "owner_id": -1,
		"status": "activo", "work_done": 0.0, "work_needed": 0.0, "target_level": level,
		"name": "", "legal": "sas", "price": 0.0, "inventory": {}, "reserve": 0.0,
		"rent": 0.0, "for_sale": false, "sale_price": 0.0,
		"ledger": {"month": {}, "last_month": {}, "total": {}},
		"built_day": gs.today(),
	}
	gs.next_building_id += 1
	var ld := GameData.level_def(type_id, level)
	b["rent"] = float(ld.get("rent", 0.0))
	b["sale_price"] = float(ld.get("sale_price", 0.0))
	var def := GameData.building_def(type_id)
	if def.has("product"):
		b["price"] = BusinessSim.default_price(gs, def)
		b["auto_price"] = true
		b["markup"] = 0.1
	return b


## Normaliza edificios cargados de partidas antiguas.
static func normalize_building(src: Dictionary) -> Dictionary:
	var b := src.duplicate(true)
	b["id"] = int(b.get("id", 0))
	if str(b.get("type", "")) == "choza":
		b["type"] = "vivienda"
	b["level"] = int(b.get("level", 1))
	b["target_level"] = int(b.get("target_level", b["level"]))
	b["owner_id"] = int(b.get("owner_id", -1))
	for k in ["status", "name", "legal"]:
		if not b.has(k):
			b[k] = {"status": "activo", "name": "", "legal": "sas"}[k]
	for k in ["work_done", "work_needed", "price", "reserve", "rent", "sale_price"]:
		b[k] = float(b.get(k, 0.0))
	b["for_sale"] = bool(b.get("for_sale", false))
	if not b.has("tier"):
		b["tier"] = "normal"
	if not b.has("inventory"):
		b["inventory"] = {}
	if not b.has("ledger"):
		b["ledger"] = {"month": {}, "last_month": {}, "total": {}}
	if float(b["rent"]) <= 0.0:
		b["rent"] = float(GameData.level_def(b["type"], b["level"]).get("rent", 0.0))
	return b


# --- Costos ---------------------------------------------------------------------------

## Costo de construir (level 1) o mejorar a un nivel. Devuelve:
## {money, materials:{g:qty}, from_stock:{g:qty}, import:{g:qty}, import_cost, total, days, workers}
static func cost_for(gs, type_id: String, level: int, is_upgrade: bool, tier := "normal") -> Dictionary:
	var ld := GameData.level_def(type_id, level)
	var pm: float = gs.price_mult()
	var factor := float(GameData.game.get("upgrade_cost_factor", 0.8)) if is_upgrade else 1.0
	if type_id == "vivienda":
		factor *= float(Housing.tier_def_by_id(tier).get("cost_mult", 1.0))
	var money := float(ld.get("cost", 0)) * pm * factor
	var mats: Dictionary = ld.get("materials", {})
	var from_stock := {}
	var imports := {}
	var import_cost := 0.0
	for g in mats:
		var need := ceilf(float(mats[g]) * factor)
		var have := stock_of(gs, g)
		var use := minf(have, need)
		from_stock[g] = use
		imports[g] = need - use
		import_cost += (need - use) * float(GameData.goods.get(g, {}).get("import_price", 5.0)) * pm * GovSim.import_mult(gs)
	return {
		"money": money, "materials": mats, "from_stock": from_stock, "import": imports,
		"import_cost": import_cost, "total": money + import_cost,
		"days": int(ld.get("build_days", 10)), "workers": int(ld.get("workers", 2)),
	}


## Unidades de un bien disponibles en el inventario de tus negocios y en el almacén de la compañía.
static func stock_of(gs, good: String) -> float:
	var total := 0.0
	for b in gs.buildings:
		if gs.owned_by_player(b):
			total += float(b.get("inventory", {}).get(good, 0.0))
	return total + WarehouseSim.stock(gs, good)


static func _consume_stock(gs, good: String, qty: float) -> void:
	var left := qty
	for b in gs.buildings:
		if left <= 0.0:
			return
		if not gs.owned_by_player(b):
			continue
		var inv: Dictionary = b.get("inventory", {})
		var have := float(inv.get(good, 0.0))
		if have > 0.0:
			var take := minf(have, left)
			inv[good] = have - take
			left -= take
	if left > 0.0:
		WarehouseSim.remove(gs, good, left)   # Fase 6: el resto sale del almacén.


## Explica por qué no se puede construir/mejorar ("" si se puede).
static func level_block_reason(gs, type_id: String, level: int) -> String:
	var def := GameData.building_def(type_id)
	var ld := GameData.level_def(type_id, level)
	if ld.is_empty():
		return "Nivel máximo alcanzado"
	var tech := str(ld.get("tech", ""))
	if not gs.has_tech(tech):
		return "Requiere investigar: %s (Fase 4)" % GameData.tech_label(tech)
	var maps: Array = def.get("map_types", [])
	if not maps.is_empty() and not maps.has(str(gs.settings.get("map_type", ""))):
		return "Solo en mapas: %s" % ", ".join(maps.map(func(m): return str(GameData.map_type(m).get("label", m))))
	return ""


static func build_block_reason(gs, type_id: String, tier := "normal") -> String:
	var r := level_block_reason(gs, type_id, 1)
	if r != "":
		return r
	var def := GameData.building_def(type_id)
	if str(def.get("category", "")) == "negocio" and BusinessSim.counts_for_limit(def) and BusinessSim.business_count(gs) >= BusinessSim.max_businesses(gs):
		return "Límite de negocios (%d). Construye o mejora tu oficina." % BusinessSim.max_businesses(gs)
	var cost := cost_for(gs, type_id, 1, false, tier)
	if gs.money < float(cost["total"]):
		return "Dinero insuficiente (%s)" % Fmt.money(cost["total"])
	return ""


## Validez de ubicación (sin terreno: el mundo 3D verifica agua y pendiente).
static func placement_block_reason(gs, type_id: String, x: float, z: float, ignore_id := -1, level := 1) -> String:
	var fp := GameData.footprint(type_id, level)
	if Vector2(x, z).length() < MIN_TOWN_CENTER_DIST + fp * 0.5:
		return "Demasiado cerca de la plaza"
	var zs: float = gs.MAP_SIZE / gs.ZONE_GRID
	var half: float = gs.MAP_SIZE * 0.5
	var zx := clampi(int((x + half) / zs), 0, gs.ZONE_GRID - 1)
	var zy := clampi(int((z + half) / zs), 0, gs.ZONE_GRID - 1)
	if not gs.is_zone_unlocked(zx, zy):
		return "Terreno del gobierno: cómpralo primero (Construir → Comprar terreno)"
	for b in gs.buildings:
		if int(b["id"]) == ignore_id:
			continue
		var ofp: float = gs.footprint_of(b)
		if Vector2(x, z).distance_to(Vector2(float(b["x"]), float(b["z"]))) < (fp + ofp) * 0.5 + 0.8:
			return "Se superpone con otro edificio"
	var dep := RegionSim.deposit_block_reason(gs, type_id, x, z)   # Fase 6: minas junto a su yacimiento.
	if dep != "":
		return dep
	return WaterSim.placement_block_reason(gs, type_id, x, z)   # Redes: la toma de río va junto al agua dulce.


# --- Acciones del jugador ------------------------------------------------------------

static func start_construction(gs, type_id: String, x: float, z: float, rot: float, bname := "", legal := "sas", tier := "normal") -> Dictionary:
	var reason := build_block_reason(gs, type_id, tier)
	if reason == "":
		reason = placement_block_reason(gs, type_id, x, z)
	if reason != "":
		return {"error": reason}
	var cost := cost_for(gs, type_id, 1, false, tier)
	_pay_cost(gs, cost)
	var b := make_building(gs, type_id, 1, x, z, rot, "jugador")
	b["status"] = "construccion"
	b["work_needed"] = float(cost["days"] * cost["workers"])
	b["name"] = bname
	b["legal"] = legal if GameData.legal_types.has(legal) else "sas"
	if type_id == "vivienda":
		apply_tier(b, tier)
	BusinessSim.ledger_add(b, "obras", float(cost["total"]))
	gs.add_building(b)
	LogisticsSim.on_buildings_changed(gs)   # Vínculo fábrica ↔ almacén al lado.
	gs.notify("Obra iniciada: %s (%d días con %d trabajadores)." % [gs.building_label(b), cost["days"], cost["workers"]], "construccion")
	EventBus.building_changed.emit(int(b["id"]))
	return {"building": b}


## Días estimados que faltan para terminar una obra (según la cuadrilla actual).
static func days_left(gs, b: Dictionary) -> int:
	var crew := 0
	for c in gs.citizens.values():
		if c.job_id == int(b["id"]) and c.job_kind == "obra" and not c.sick:
			crew += 1
	if crew == 0:
		crew = int(GameData.level_def(str(b["type"]), int(b["target_level"])).get("workers", 2))
	var rate := maxf(0.1, crew * TechSim.mult(gs, "construction_speed"))
	return int(ceil(maxf(0.0, float(b["work_needed"]) - float(b["work_done"])) / rate))


## Al mejorar, el edificio crece: debe quedar espacio libre alrededor para el nuevo tamaño.
static func upgrade_space_reason(gs, b: Dictionary, next: int) -> String:
	var fp := GameData.footprint(str(b["type"]), next)
	var p := Vector2(float(b["x"]), float(b["z"]))
	for o in gs.buildings:
		if int(o["id"]) == int(b["id"]):
			continue
		if p.distance_to(Vector2(float(o["x"]), float(o["z"]))) < (fp + float(gs.footprint_of(o))) * 0.5 + 0.8:
			return "No hay espacio para ampliar (%.0f m): choca con %s. Muévelo o demuele el vecino." % [fp, gs.building_label(o)]
	return ""


static func start_upgrade(gs, b: Dictionary) -> String:
	if not gs.owned_by_player(b):
		return "No es tuyo"
	if not gs.is_active(b):
		return "Ya está en obras"
	var next := int(b["level"]) + 1
	var reason := level_block_reason(gs, str(b["type"]), next)
	if reason != "":
		return reason
	reason = upgrade_space_reason(gs, b, next)
	if reason != "":
		return reason
	reason = GridSim.upgrade_block_reason(gs, b, next)   # Redes: casas altas exigen cable/tubería cerca.
	if reason != "":
		return reason
	var cost := cost_for(gs, str(b["type"]), next, true, str(b.get("tier", "normal")))
	if gs.money < float(cost["total"]):
		return "Dinero insuficiente (%s)" % Fmt.money(cost["total"])
	_pay_cost(gs, cost)
	b["status"] = "mejorando"
	b["target_level"] = next
	b["work_done"] = 0.0
	b["work_needed"] = float(cost["days"] * cost["workers"])
	BusinessSim.ledger_add(b, "obras", float(cost["total"]))
	gs.notify("Mejora iniciada: %s → %s. No facturará durante la obra." % [gs.building_label(b), GameData.level_def(b["type"], next).get("label", "")], "construccion")
	EventBus.building_changed.emit(int(b["id"]))
	return ""


static func apply_tier(b: Dictionary, tier: String) -> void:
	b["tier"] = tier
	var ld := GameData.level_def("vivienda", int(b["level"]))
	var td := Housing.tier_def_by_id(tier)
	b["rent"] = float(ld.get("rent", 0.0)) * float(td.get("rent_mult", 1.0))
	b["sale_price"] = float(ld.get("sale_price", 0.0)) * float(td.get("sale_mult", 1.0))


## Remodelación: sube la calidad (normal → media → alta) de una vivienda.
static func renovation_cost(gs, b: Dictionary) -> Dictionary:
	var idx := Housing.tier_index(b)
	if idx >= Housing.TIERS.size() - 1:
		return {}
	var next: String = Housing.TIERS[idx + 1]
	var cur_c := cost_for(gs, "vivienda", int(b["level"]), false, str(b.get("tier", "normal")))
	var new_c := cost_for(gs, "vivienda", int(b["level"]), false, next)
	return {"tier": next, "total": maxf(0.0, float(new_c["total"]) - float(cur_c["total"])),
		"days": maxi(5, int(new_c["days"]) / 2), "workers": int(new_c["workers"])}


static func start_renovation(gs, b: Dictionary) -> String:
	if not gs.owned_by_player(b) or not Housing.is_home(b):
		return "Solo puedes remodelar tus viviendas"
	if not gs.is_active(b):
		return "Ya está en obras"
	var rc := renovation_cost(gs, b)
	if rc.is_empty():
		return "Ya tiene la calidad máxima"
	if gs.money < float(rc["total"]):
		return "Dinero insuficiente (%s)" % Fmt.money(rc["total"])
	gs.add_money(-float(rc["total"]))
	BusinessSim.ledger_add(b, "obras", float(rc["total"]))
	b["status"] = "mejorando"
	b["target_level"] = int(b["level"])
	b["target_tier"] = rc["tier"]
	b["work_done"] = 0.0
	b["work_needed"] = float(rc["days"] * rc["workers"])
	gs.notify("Remodelación iniciada: %s pasará a calidad %s." % [gs.building_label(b), Housing.tier_label(rc["tier"])], "construccion")
	EventBus.building_changed.emit(int(b["id"]))
	return ""


static func _pay_cost(gs, cost: Dictionary) -> void:
	for g in cost["from_stock"]:
		_consume_stock(gs, g, float(cost["from_stock"][g]))
	gs.add_money(-float(cost["total"]))


static func demolish(gs, b: Dictionary) -> void:
	var id := int(b["id"])
	for c in gs.citizens.values():
		if c.job_id == id:
			c.job_id = -1
			c.job_kind = ""
			c.wage = 0.0
		if c.home_id == id:
			c.home_id = -1
	LogisticsSim.before_demolish(gs, b)   # El stock de un almacén pasa a los demás.
	gs.remove_building(id)
	LogisticsSim.on_buildings_changed(gs)
	gs.notify("Demoliste %s." % gs.building_label(b), "construccion")
	EventBus.building_removed.emit(id)
	EventBus.citizens_moved.emit()


# --- Simulación diaria de obras ---------------------------------------------------------

static func daily(gs) -> void:
	var sites := []
	for b in gs.buildings:
		if b["status"] == "construccion" or b["status"] == "mejorando":
			sites.append(b)
	if sites.is_empty():
		return
	var wage: float = float(GameData.game.get("construction_day_wage", 2.2)) * gs.price_mult()
	var points_share: float = float(gs.get_meta("construction_points", 0.0)) / sites.size() if gs.has_meta("construction_points") else 0.0
	for b in sites:
		var lvl := int(b["target_level"])
		var need_workers := int(GameData.level_def(b["type"], lvl).get("workers", 2))
		var crew := _crew(gs, b, need_workers)
		var work := points_share
		for c in crew:
			if c.sick:
				continue
			work += 1.0
			c.money += wage
			BusinessSim.pay(gs, b, wage, "obras")
		b["work_done"] = float(b["work_done"]) + work * TechSim.mult(gs, "construction_speed")
		if float(b["work_done"]) >= float(b["work_needed"]):
			_complete(gs, b, crew)


## Contrata jornaleros entre los desempleados hasta completar la cuadrilla.
static func _crew(gs, b: Dictionary, need: int) -> Array:
	var id := int(b["id"])
	var crew := []
	for c in gs.citizens.values():
		if c.job_id == id and c.job_kind == "obra":
			crew.append(c)
	if crew.size() >= need:
		return crew
	var today: int = gs.today()
	for c in gs.citizens.values():
		if crew.size() >= need:
			break
		if c.job_id >= 0 or gs.is_player(c.id) or c.sick:
			continue
		var age: int = c.age_years(today)
		if age < int(GameData.citizens.get("adult_age", 16)) or age > 60:
			continue
		c.job_id = id
		c.job_kind = "obra"
		c.wage = float(GameData.game.get("construction_day_wage", 2.2))
		crew.append(c)
	return crew


static func _complete(gs, b: Dictionary, crew: Array) -> void:
	for c in crew:
		c.job_id = -1
		c.job_kind = ""
		c.wage = 0.0
	var upgraded: bool = b["status"] == "mejorando"
	if str(b.get("owner", "")) == "gobierno":
		b["status"] = "activo"
		b["work_done"] = 0.0
		gs.notify("Obra pública terminada: %s." % gs.level_def(b).get("label", ""), "construccion")
		GovSim.on_project_complete(gs, b)
		EventBus.building_changed.emit(int(b["id"]))
		for c in crew:
			c.job_id = -1
			c.job_kind = ""
			c.wage = 0.0
		return
	b["level"] = int(b["target_level"])
	if b.has("target_tier"):
		apply_tier(b, str(b["target_tier"]))
		b.erase("target_tier")
	b["status"] = "activo"
	b["work_done"] = 0.0
	b["work_needed"] = 0.0
	LogisticsSim.on_buildings_changed(gs)   # Un almacén terminado vincula a sus vecinos.
	var ld: Dictionary = gs.level_def(b)
	if Housing.is_home(b):
		var td := Housing.tier_def(b)
		b["rent"] = maxf(float(b["rent"]), float(ld.get("rent", 0.0)) * float(td.get("rent_mult", 1.0)))
		b["sale_price"] = maxf(float(b["sale_price"]), float(ld.get("sale_price", 0.0)) * float(td.get("sale_mult", 1.0)))
	gs.notify("%s: %s." % ["Mejora terminada" if upgraded else "Construcción terminada", gs.building_label(b) if b["name"] != "" else ld.get("label", "")], "construccion")
	EventBus.building_changed.emit(int(b["id"]))


# --- Expansión de terreno -------------------------------------------------------------

static func zone_cost(gs) -> float:
	var n: int = gs.unlocked_zones.size() - 1
	return float(GameData.game.get("zone_expansion_cost", 2500)) * pow(float(GameData.game.get("zone_expansion_growth", 1.5)), n) * gs.price_mult()


static func zone_block_reason(gs, zx: int, zy: int) -> String:
	if zx < 0 or zy < 0 or zx >= gs.ZONE_GRID or zy >= gs.ZONE_GRID:
		return "Fuera del mapa"
	if gs.is_zone_unlocked(zx, zy):
		return "Ya compraste este terreno"
	var adjacent := false
	for z in gs.unlocked_zones:
		if absi(int(z[0]) - zx) + absi(int(z[1]) - zy) == 1:
			adjacent = true
	if not adjacent:
		return "Debe ser vecina de una zona desbloqueada"
	if gs.money < zone_cost(gs):
		return "Dinero insuficiente (%s)" % Fmt.money(zone_cost(gs))
	return ""


static func unlock_zone(gs, zx: int, zy: int) -> String:
	var reason := zone_block_reason(gs, zx, zy)
	if reason != "":
		return reason
	var cost := zone_cost(gs)
	gs.add_money(-cost)
	# El terreno se le compra al gobierno: el dinero va al tesoro público.
	GovSim.add_treasury(gs, cost)
	gs.unlocked_zones.append([zx, zy])
	gs.notify("Compraste un terreno al gobierno por %s. Ya puedes construir en esa zona." % Fmt.money(cost), "construccion")
	EventBus.zones_changed.emit()
	return ""



# --- Mover / girar ---------------------------------------------------------------------------

## Girar en el mismo sitio es gratis; trasladar cuesta desmontar y rearmar (15% de la obra).
static func move_cost(gs, b: Dictionary, x: float, z: float) -> float:
	if Vector2(x, z).distance_to(Vector2(float(b["x"]), float(b["z"]))) < 0.3:
		return 0.0
	return float(cost_for(gs, str(b["type"]), int(b["level"]), false, str(b.get("tier", "normal")))["total"]) * 0.15


static func move_building(gs, b: Dictionary, x: float, z: float, rot: float) -> String:
	if not gs.owned_by_player(b):
		return "Solo puedes mover tus edificios"
	var reason := placement_block_reason(gs, str(b["type"]), x, z, int(b["id"]), int(b["level"]))
	if reason != "":
		return reason
	var cost := move_cost(gs, b, x, z)
	if gs.money < cost:
		return "Mover cuesta %s" % Fmt.money(cost)
	if cost > 0.0:
		gs.add_money(-cost)
		BusinessSim.ledger_add(b, "obras", cost)
	b["x"] = x
	b["z"] = z
	b["rot"] = rot
	LogisticsSim.on_buildings_changed(gs)   # Recalcula el vínculo fábrica ↔ almacén.
	EventBus.building_changed.emit(int(b["id"]))
	EventBus.citizens_moved.emit()
	return ""
