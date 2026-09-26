class_name LogisticsSim
extends RefCounted
## Fase 6 — recursos por región, yacimientos, recetas de producción, almacenes individuales,
## transporte interno con flota (cargadores, carretas, carros de vapor, camiones, tráileres),
## carreteras y rutas manuales/automáticas.
## El estado vive en GameState.logistics y se guarda automáticamente:
##   region, deposits (RegionSim) · warehouses (WarehouseSim) · roads (RoadSim)
##   routes, shipments, next_route_id, vehicles, next_vehicle_id, stats (este archivo)
##
## Diseño (ver docs/FASE6.md):
## - Cada almacén tiene su propio stock y capacidad. Una fábrica, taller, mina o campo queda
##   VINCULADO al almacén que tenga al lado (WarehouseSim.warehouse_for): toma los insumos
##   ("inputs") solo de su inventario local y de ese almacén, y guarda la producción
##   ("output": "warehouse") solo ahí. Si ese almacén está lleno, la producción se detiene.
## - Sin almacén al lado, la producción queda en el sitio (inventario local, capacidad
##   limitada) y los insumos deben llegar al sitio: hay que moverlos con RUTAS.
## - Las rutas mueven cualquier bien entre almacenes, fábricas y la bodega de la plaza (la
##   salida del pueblo): manual (un envío) o automática (cada X días lleva X cantidad).
## - Flota: cada medio tiene capacidad por viaje. Los cargadores a pie son empleados sin estudios
##   de la Central de transporte. Los vehículos son INDIVIDUALES y se compran en su edificio:
##   Caballeriza (mulas, carretas: comen alimento), Depósito de camiones (carros de vapor,
##   camiones, tráileres: combustible por km, surtidor opcional) y Hangar (aviones, previsto).
##   Cada vehículo necesita un conductor o arriero (empleado de su edificio) y sale de ahí.
##   Una ruta puede tener un vehículo asignado (manual = un viaje; automática = cada X días)
##   o usar cualquier unidad libre del medio. Vehículos libres = viajes simultáneos.
## - Compra automática de insumos: una ruta con "buy" sale de la bodega de la plaza (salida
##   del pueblo) y compra al precio de importación lo que falte para cargar el vehículo.

const PLAZA := 0   # Bodega de la plaza (almacén principal y salida del pueblo).


static func cfg() -> Dictionary:
	return GameData.extra("resources")


static func wcfg() -> Dictionary:
	return cfg().get("warehouse", {})


static func tcfg() -> Dictionary:
	return cfg().get("transport", {})


static func init_state(gs) -> void:
	if gs.logistics.is_empty():
		gs.logistics = {}
	var L: Dictionary = gs.logistics
	if not L.has("region"):
		var mt := str(gs.settings.get("map_type", "interior"))
		var sd := int(gs.settings.get("seed", 0))
		var reg := RegionSim.find(mt, sd, str(gs.settings.get("region", "")))
		L["region"] = reg
		gs.settings["region"] = str(reg.get("id", ""))
		L["deposits"] = RegionSim.generate_deposits(mt, sd, reg)
	for k in ["deposits", "roads", "routes", "shipments"]:
		if not L.has(k):
			L[k] = []
	for k in ["next_route_id", "next_road_id"]:
		L[k] = int(L.get(k, 1))
	if not L.has("stats"):
		L["stats"] = {}
	WarehouseSim._stores(gs)   # Crea los almacenes individuales (migra el almacén global antiguo).
	WarehouseSim.relink_all(gs)


static func daily(gs) -> void:
	var today: int = gs.today()
	WarehouseSim.prune(gs)
	_complete_shipments(gs, float(today))
	_vehicle_upkeep(gs)
	for r in routes(gs).duplicate():
		if not bool(r.get("active", true)):
			continue
		if bool(r.get("auto", false)) and today < int(r.get("next_day", 0)):
			continue
		dispatch(gs, r, float(today) + float(tcfg().get("depart_hour", 7)) / 24.0)


static func monthly(gs) -> void:
	var st: Dictionary = gs.logistics.get("stats", {})
	st["last_month_moved"] = float(st.get("month_moved", 0.0))
	st["month_moved"] = 0.0
	st["last_month_fuel"] = float(st.get("month_fuel", 0.0))
	st["month_fuel"] = 0.0
	gs.logistics["stats"] = st


## Ganchos de ConstructionSim: al construir, terminar, mover o demoler se recalculan los vínculos.
static func on_buildings_changed(gs) -> void:
	WarehouseSim.relink_all(gs)


## Antes de demoler: el stock de un almacén se reparte en los demás (lo que no cabe se pierde).
static func before_demolish(gs, b: Dictionary) -> void:
	if gs.level_def(b).has("transport_modes"):
		_sell_fleet_of(gs, b)
	if not WarehouseSim.is_warehouse_building(gs, b):
		return
	var wid := int(b["id"])
	var st := WarehouseSim.stock_all_in(gs, wid)
	(gs.logistics["warehouses"] as Dictionary).erase(str(wid))
	b["status"] = "construccion"   # Deja de contar como almacén mientras se reparte.
	WarehouseSim.invalidate()
	var lost := 0.0
	for g in st:
		lost += float(st[g]) - WarehouseSim.add(gs, str(g), float(st[g]))
	if lost > 0.5:
		gs.notify("Al demoler %s se perdieron %s unidades que no cabían en tus otros almacenes." % [gs.building_label(b), Fmt.thousands(lost)], "negocio")


# --- Cadenas de producción (llamado desde BusinessSim.produce) -------------------------------

## ¿Usa este negocio recetas, almacén o yacimientos?
static func uses_chain(def: Dictionary, ld: Dictionary) -> bool:
	return ld.has("inputs") or ld.has("output") or ld.has("requires_deposit") or def.has("inputs") or def.has("output") or bool(def.get("extraction", false))


static func is_extraction(def: Dictionary, ld: Dictionary) -> bool:
	return bool(def.get("extraction", ld.get("extraction", false))) or str(ld.get("requires_deposit", "")) != ""


static func recipe_inputs(def: Dictionary, ld: Dictionary) -> Dictionary:
	return ld.get("inputs", def.get("inputs", {}))


static func outputs_to_warehouse(def: Dictionary, ld: Dictionary) -> bool:
	return str(ld.get("output", def.get("output", ""))) == "warehouse"


## Todos los almacenes como puntos: [{id, pos}] (la bodega de la plaza primero).
static func warehouse_points(gs) -> Array:
	var out := []
	for wid in WarehouseSim.ids(gs):
		out.append({"id": wid, "pos": WarehouseSim.pos_of(gs, wid)})
	return out


## Distancia (entre centros) al almacén más cercano.
static func warehouse_distance(gs, x: float, z: float) -> float:
	var best := INF
	for p in warehouse_points(gs):
		best = minf(best, Vector2(x, z).distance_to(p["pos"]))
	return best


## ¿Tiene un almacén al lado? (queda vinculado y descarga directo).
static func in_reach(gs, b: Dictionary) -> bool:
	return WarehouseSim.warehouse_for(gs, b) >= 0


## Dónde queda la producción de un negocio de la cadena: "warehouse" (su almacén vinculado) o "local".
static func output_target(gs, b: Dictionary) -> String:
	if not outputs_to_warehouse(gs.building_def(b), gs.level_def(b)):
		return "local"
	return "warehouse" if WarehouseSim.warehouse_for(gs, b) >= 0 else "local"


static func local_capacity(gs, b: Dictionary) -> float:
	if BusinessSim.is_business(b):
		return maxf(BusinessSim.storage_cap(gs, b), 100.0)
	return 200.0


## Insumo disponible para un negocio: su inventario local + su almacén vinculado.
static func input_available(gs, b: Dictionary, good: String) -> float:
	var wid := WarehouseSim.warehouse_for(gs, b)
	return float(b["inventory"].get(good, 0.0)) + (WarehouseSim.stock_in(gs, wid, good) if wid >= 0 else 0.0)


static func take_input(gs, b: Dictionary, good: String, qty: float) -> void:
	var inv: Dictionary = b["inventory"]
	var local := minf(float(inv.get(good, 0.0)), qty)
	if local > 0.0:
		inv[good] = float(inv[good]) - local
	var wid := WarehouseSim.warehouse_for(gs, b)
	if qty - local > 0.0 and wid >= 0:
		WarehouseSim.remove_from(gs, wid, good, qty - local)


## Produce `out` unidades con receta/yacimiento/almacén. Devuelve lo realmente producido.
static func produce_chain(gs, b: Dictionary, product: String, out: float) -> float:
	var def: Dictionary = gs.building_def(b)
	var ld: Dictionary = gs.level_def(b)
	var inputs := recipe_inputs(def, ld)
	var wid := WarehouseSim.warehouse_for(gs, b)
	var target := output_target(gs, b)
	var inv: Dictionary = b["inventory"]
	var wname := WarehouseSim.label_of(gs, wid) if wid >= 0 else ""
	b["chain_status"] = ""
	# 1) Espacio donde guardar lo producido (solo en SU almacén vinculado o en el sitio).
	var room := INF
	if target == "warehouse":
		var per_unit_in := 0.0
		for g in inputs:
			per_unit_in += float(inputs[g])
		room = WarehouseSim.free_in(gs, wid) / maxf(0.0001, 1.0 - per_unit_in) if per_unit_in < 1.0 else INF
	elif bool(GameData.goods.get(product, {}).get("storable", true)):
		room = maxf(0.0, local_capacity(gs, b) - float(inv.get(product, 0.0)))
	if out > room:
		out = maxf(0.0, room)
		if target == "warehouse":
			b["chain_status"] = "almacén lleno"
			_warn(gs, b, "full", "%s: el almacén «%s» está lleno (%s/%s); la producción se detuvo. Mejóralo, construye otro almacén al lado o saca mercancía con una ruta." % [
				gs.building_label(b), wname, Fmt.thousands(WarehouseSim.used_in(gs, wid)), Fmt.thousands(WarehouseSim.capacity_of(gs, wid))])
		else:
			b["chain_status"] = "patio lleno: sin almacén al lado"
			_warn(gs, b, "full", "%s no tiene almacén al lado y su patio se llenó: construye un almacén junto a ella o crea una ruta de transporte." % gs.building_label(b))
	# 2) Yacimiento.
	var dep := {}
	if str(ld.get("requires_deposit", "")) != "":
		dep = RegionSim.deposit_for(gs, b)
		if dep.is_empty():
			out = 0.0
			b["chain_status"] = "sin yacimiento"
			_warn(gs, b, "deposit", "%s no tiene yacimiento de %s (agotado o lejos)." % [gs.building_label(b), RegionSim.resource_label(str(ld["requires_deposit"])).to_lower()])
		else:
			out = minf(out, float(dep["amount"]))
	# 3) Insumos de la receta (se limita proporcionalmente si faltan).
	if not inputs.is_empty() and out > 0.0:
		var ratio := 1.0
		var missing := []
		for g in inputs:
			var need := float(inputs[g]) * out
			if need > 0.0:
				var have := input_available(gs, b, g)
				if have < need:
					missing.append(GameData.good_label(g).to_lower())
				ratio = minf(ratio, have / need)
		if ratio < 1.0:
			out *= maxf(0.0, ratio)
			b["chain_status"] = "faltan insumos: " + ", ".join(missing)
			if wid >= 0:
				_warn(gs, b, "inputs", "%s no tiene suficiente %s en su almacén «%s»: produce menos. Lleva insumos a ese almacén con una ruta." % [gs.building_label(b), " ni ".join(missing), wname])
			else:
				_warn(gs, b, "inputs", "%s no tiene almacén al lado ni %s en el sitio: construye un almacén junto a ella o trae los insumos con una ruta." % [gs.building_label(b), " ni ".join(missing)])
		for g in inputs:
			take_input(gs, b, g, float(inputs[g]) * out)
	if out <= 0.0:
		b["produced_today"] = 0.0
		return 0.0
	# 4) Guardar.
	RegionSim.deplete(gs, dep, out)
	var stored := out
	if target == "warehouse":
		stored = WarehouseSim.add_to(gs, wid, product, out)
		if stored < out - 0.001:
			b["chain_status"] = "almacén lleno"
			_warn(gs, b, "full", "%s: el almacén «%s» está lleno; se detuvo la producción." % [gs.building_label(b), wname])
	else:
		inv[product] = float(inv.get(product, 0.0)) + out
	b["produced_today"] = stored
	return stored


## Aviso con pausa (no más de uno cada full_warning_days por edificio y motivo).
static func _warn(gs, b: Dictionary, key: String, text: String) -> void:
	var w: Dictionary = b.get("log_warn", {})
	var today: int = gs.today()
	if today - int(w.get(key, -9999)) < int(wcfg().get("full_warning_days", 20)):
		return
	w[key] = today
	b["log_warn"] = w
	gs.notify(text, "negocio")


## Texto de la receta: "1 hierro + 1 carbón → 1 herramientas".
static func recipe_text(type_id: String, level: int) -> String:
	var def := GameData.building_def(type_id)
	var ld := GameData.level_def(type_id, level)
	var inputs := recipe_inputs(def, ld)
	var product := GameData.good_label(str(def.get("product", "")))
	if inputs.is_empty():
		if str(ld.get("requires_deposit", "")) != "":
			return "Yacimiento de %s → %s" % [RegionSim.resource_label(str(ld["requires_deposit"])).to_lower(), product]
		return "→ %s" % product
	var parts := []
	for g in inputs:
		parts.append("%s %s" % [_num(float(inputs[g])), GameData.good_label(g).to_lower()])
	return "%s → 1 %s" % [" + ".join(parts), product.to_lower()]


static func _num(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else ("%.1f" % v).replace(".", ",")


## Negocios de la cadena (para el panel).
static func chain_buildings(gs) -> Array:
	var out := []
	for b in gs.buildings:
		if gs.owned_by_player(b) and BusinessSim.is_business(b) and uses_chain(gs.building_def(b), gs.level_def(b)):
			out.append(b)
	return out


## Texto corto del vínculo de un negocio con su almacén.
static func link_text(gs, b: Dictionary) -> String:
	var wid := WarehouseSim.warehouse_for(gs, b)
	if wid < 0:
		return "sin almacén al lado"
	return "almacén vinculado: %s" % WarehouseSim.label_of(gs, wid)


# --- Puntos de origen/destino de las rutas ---------------------------------------------------

static func is_warehouse_endpoint(gs, id: int) -> bool:
	return WarehouseSim.exists(gs, id)


static func endpoint_valid(gs, id: int) -> bool:
	if id == PLAZA:
		return true
	var b: Dictionary = gs.get_building(id)
	return not b.is_empty() and gs.owned_by_player(b) and b["status"] != "construccion"


static func endpoint_pos(gs, id: int) -> Vector2:
	if id == PLAZA:
		return Vector2.ZERO
	var b: Dictionary = gs.get_building(id)
	return Vector2(float(b.get("x", 0.0)), float(b.get("z", 0.0)))


static func endpoint_label(gs, id: int) -> String:
	if id == PLAZA:
		return "%s (salida del pueblo)" % str(wcfg().get("plaza_label", "Bodega de la plaza"))
	var b: Dictionary = gs.get_building(id)
	if b.is_empty():
		return "(demolido)"
	return gs.building_label(b) + (" (almacén)" if is_warehouse_endpoint(gs, id) else "")


## Posibles orígenes/destinos: la bodega (salida del pueblo), tus almacenes y tus negocios (no servicios).
static func endpoints(gs) -> Array:
	var out := [PLAZA]
	for b in gs.buildings:
		if not gs.owned_by_player(b) or b["status"] == "construccion":
			continue
		var def: Dictionary = gs.building_def(b)
		if is_warehouse_endpoint(gs, int(b["id"])) or (BusinessSim.is_business(b) and not def.has("service") and not gs.level_def(b).has("transport_modes")):
			out.append(int(b["id"]))
	return out


static func endpoint_stock(gs, id: int, good: String) -> float:
	if is_warehouse_endpoint(gs, id):
		return WarehouseSim.stock_in(gs, id, good)
	return float(gs.get_building(id).get("inventory", {}).get(good, 0.0))


static func endpoint_room(gs, id: int, good: String) -> float:
	if is_warehouse_endpoint(gs, id):
		return WarehouseSim.free_in(gs, id)
	var b: Dictionary = gs.get_building(id)
	if b.is_empty():
		return 0.0
	return maxf(0.0, local_capacity(gs, b) - float(b["inventory"].get(good, 0.0)))


static func endpoint_take(gs, id: int, good: String, qty: float) -> float:
	if is_warehouse_endpoint(gs, id):
		return WarehouseSim.remove_from(gs, id, good, qty)
	var b: Dictionary = gs.get_building(id)
	if b.is_empty():
		return 0.0
	var inv: Dictionary = b["inventory"]
	var take := minf(qty, float(inv.get(good, 0.0)))
	inv[good] = float(inv.get(good, 0.0)) - take
	return take


static func endpoint_put(gs, id: int, good: String, qty: float) -> float:
	if is_warehouse_endpoint(gs, id):
		return WarehouseSim.add_to(gs, id, good, qty)
	var b: Dictionary = gs.get_building(id)
	if b.is_empty():
		return 0.0
	var acc := minf(qty, endpoint_room(gs, id, good))
	b["inventory"][good] = float(b["inventory"].get(good, 0.0)) + acc
	return acc


## Bienes que se pueden transportar (almacenables y no internos).
static func transportable_goods() -> Array:
	return GameData.sorted_ids(GameData.goods).filter(func(g):
		var gd: Dictionary = GameData.goods[g]
		return bool(gd.get("storable", true)) and not bool(gd.get("internal", false)) and not str(g).begins_with("_"))


# --- Medios de transporte y estaciones ---------------------------------------------------------
# Estación = edificio activo del jugador con "transport_modes" en su nivel:
#   Central de transporte (cargadores a pie; sus niveles 2-3 traen carretas/camiones INCLUIDOS),
#   Caballeriza (mulas y carretas), Depósito de camiones (carros de vapor, camiones, tráileres)
#   y Hangar (aviones de carga, previsto). Los vehículos individuales se compran en la estación
#   de su medio ("base" en resources.json) y viven en gs.logistics["vehicles"].

static func modes() -> Dictionary:
	return tcfg().get("modes", {})


static func mode_def(mode: String) -> Dictionary:
	return modes().get(mode, {})


static func mode_label(mode: String) -> String:
	return str(mode_def(mode).get("label", mode))


static func mode_short(mode: String) -> String:
	return str(mode_def(mode).get("short", mode_label(mode).to_lower()))


static func is_vehicle(mode: String) -> bool:
	return bool(mode_def(mode).get("vehicle", mode != "pie"))


static func is_planned(mode: String) -> bool:
	return bool(mode_def(mode).get("planned", false))


## Edificio donde se compran los vehículos del medio.
static func mode_base(mode: String) -> String:
	return str(mode_def(mode).get("base", "central_transporte"))


## Tipos de carretera que exige el medio ([] = cualquiera).
static func road_kinds(mode: String) -> Array:
	return mode_def(mode).get("road_kinds", [])


## Estaciones de transporte activas (centrales, caballerizas, depósitos, hangares).
static func stations(gs) -> Array:
	var out := []
	for b in gs.buildings:
		if gs.owned_by_player(b) and b["status"] == "activo" and gs.level_def(b).has("transport_modes"):
			out.append(b)
	return out


## Compatibilidad: antes solo existía la Central de transporte.
static func centrals(gs) -> Array:
	return stations(gs)


static func central_supports(gs, c: Dictionary, mode: String) -> bool:
	return (gs.level_def(c).get("transport_modes", []) as Array).has(mode)


## Trabajadores de una estación disponibles hoy (empleados, no enfermos): cargadores, arrieros y conductores.
static func crew_size(gs, b: Dictionary) -> int:
	var n := 0
	for c in gs.employees_of(int(b["id"])):
		if c.job_kind == "empleo" and not c.sick:
			n += 1
	return n


# --- Vehículos individuales -------------------------------------------------------------------

static func vehicles(gs) -> Array:
	if not gs.logistics.has("vehicles"):
		gs.logistics["vehicles"] = []
	return gs.logistics["vehicles"]


static func get_vehicle(gs, vid: int) -> Dictionary:
	for v in vehicles(gs):
		if int(v["id"]) == vid:
			return v
	return {}


static func vehicles_of(gs, station_id: int, mode := "") -> Array:
	var out := []
	for v in vehicles(gs):
		if int(v["base"]) == station_id and (mode == "" or str(v["mode"]) == mode):
			out.append(v)
	return out


static func vehicle_label(gs, v: Dictionary) -> String:
	if v.is_empty():
		return "(sin vehículo)"
	return "%s (%s)" % [str(v.get("name", "")), mode_label(str(v["mode"]))]


## Vehículos que vienen con el nivel de la estación (anónimos, sin compra).
static func included_at(gs, st: Dictionary, mode: String) -> int:
	if not central_supports(gs, st, mode):
		return 0
	return int(gs.level_def(st).get("vehicles_included", {}).get(mode, 0))


## Vehículos de un medio en una estación (incluidos + comprados). A pie: ilimitado (cuentan las personas).
static func vehicles_at(gs, st: Dictionary, mode: String) -> int:
	if not central_supports(gs, st, mode):
		return 0
	if not is_vehicle(mode):
		return 1 << 20
	return included_at(gs, st, mode) + vehicles_of(gs, int(st["id"]), mode).size()


static func garage_capacity(gs, st: Dictionary) -> int:
	return int(gs.level_def(st).get("garage", 0))


static func bought_vehicles(gs, st: Dictionary) -> int:
	return vehicles_of(gs, int(st["id"])).size()


## ¿Está el vehículo de viaje?
static func vehicle_busy(gs, vid: int, now: float) -> bool:
	if float(get_vehicle(gs, vid).get("air_busy_until", -1.0)) > now:
		return true   # Fase 10: avión en un vuelo internacional (AirSim).
	for s in shipments(gs):
		if float(s["back"]) > now:
			for x in s.get("vehicles", []):
				if int(x) == vid:   # Tras cargar un JSON los ids pueden venir como float.
					return true
	return false


## Personas ocupadas (mode == "") o unidades de un medio ocupadas en una estación.
static func busy_in(gs, station_id: int, now: float, mode := "") -> int:
	var n := 0
	for s in shipments(gs):
		if float(s["back"]) > now and (mode == "" or str(s["mode"]) == mode):
			for pair in s.get("crew", []):
				if int(pair[0]) == station_id:
					n += int(pair[1])
	return n


## Vehículos INCLUIDOS (anónimos) de viaje: unidades del envío menos los individuales de esa estación.
static func _included_busy(gs, station_id: int, mode: String, now: float) -> int:
	var n := 0
	for s in shipments(gs):
		if float(s["back"]) <= now or str(s["mode"]) != mode:
			continue
		for pair in s.get("crew", []):
			if int(pair[0]) != station_id:
				continue
			var own := 0
			for vid in s.get("vehicles", []):
				if int(get_vehicle(gs, int(vid)).get("base", -1)) == station_id:
					own += 1
			n += maxi(0, int(pair[1]) - own)
	return n


static func _free_people(gs, st: Dictionary, now: float) -> int:
	return maxi(0, crew_size(gs, st) - busy_in(gs, int(st["id"]), now))


static func _free_vehicles(gs, st: Dictionary, mode: String, now: float) -> Array:
	var out := []
	for v in vehicles_of(gs, int(st["id"]), mode):
		if not vehicle_busy(gs, int(v["id"]), now):
			out.append(v)
	return out


## Unidades (cargadores, o vehículos con su conductor) libres de un medio en una estación.
static func free_units(gs, st: Dictionary, mode: String, now: float) -> int:
	if not central_supports(gs, st, mode):
		return 0
	var people := _free_people(gs, st, now)
	if not is_vehicle(mode):
		return people
	var inc := maxi(0, included_at(gs, st, mode) - _included_busy(gs, int(st["id"]), mode, now))
	return mini(people, inc + _free_vehicles(gs, st, mode, now).size())


## {total, free, vehicles, crew} de un medio: total = unidades que pueden operar a la vez.
static func carriers(gs, mode: String, now := -1.0) -> Dictionary:
	if now < 0.0:
		now = float(gs.today())
	var total := 0
	var free := 0
	var veh := 0
	var crew := 0
	for b in stations(gs):
		if not central_supports(gs, b, mode):
			continue
		var n := crew_size(gs, b)
		var v := vehicles_at(gs, b, mode)
		crew += n
		veh += v if is_vehicle(mode) else 0
		total += mini(n, v)
		free += free_units(gs, b, mode, now)
	return {"total": total, "free": free, "vehicles": veh, "crew": crew}


static func vehicle_price(gs, mode: String) -> float:
	return float(mode_def(mode).get("price", 0.0)) * gs.price_mult()


## Motivo por el que no se puede comprar un vehículo en esa estación ("" si se puede).
static func buy_block_reason(gs, st: Dictionary, mode: String) -> String:
	var md := mode_def(mode)
	if md.is_empty() or not is_vehicle(mode):
		return "Ese medio no usa vehículos"
	if st.is_empty() or str(st.get("type", "")) != mode_base(mode):
		return "Los %s se compran en: %s" % [mode_short(mode), str(GameData.building_def(mode_base(mode)).get("label", mode_base(mode)))]
	if not gs.has_tech(str(md.get("tech", ""))):
		return "Requiere investigar: %s" % GameData.tech_label(str(md.get("tech", "")))
	if not central_supports(gs, st, mode):
		return "%s no admite %s: mejóralo" % [gs.building_label(st), mode_short(mode)]
	if str(st.get("status", "")) != "activo":
		return "El edificio no está activo"
	if bought_vehicles(gs, st) >= garage_capacity(gs, st):
		return "No caben más vehículos (%d): mejora el edificio" % garage_capacity(gs, st)
	if gs.money < vehicle_price(gs, mode):
		return "Dinero insuficiente (%s)" % Fmt.money(vehicle_price(gs, mode))
	return ""


## Compra un vehículo individual en su estación. Devuelve {"error"} o {"vehicle"}.
static func buy_vehicle(gs, st: Dictionary, mode: String) -> Dictionary:
	var reason := buy_block_reason(gs, st, mode)
	if reason != "":
		return {"error": reason}
	BusinessSim.pay(gs, st, vehicle_price(gs, mode), "obras")
	var id := int(gs.logistics.get("next_vehicle_id", 1))
	gs.logistics["next_vehicle_id"] = id + 1
	var n := 0
	for v in vehicles(gs):
		if str(v["mode"]) == mode:
			n += 1
	var v := {"id": id, "mode": mode, "base": int(st["id"]), "name": "%s %d" % [str(mode_def(mode).get("unit", mode_label(mode))), n + 1],
		"bought": gs.today(), "km": 0.0, "trips": 0}
	vehicles(gs).append(v)
	return {"vehicle": v}


## Vende un vehículo (40 % de su precio). No se vende uno que está de viaje.
## Sus rutas pasan a usar "cualquier vehículo libre" del medio.
static func sell_vehicle(gs, vid: int) -> String:
	var v := get_vehicle(gs, vid)
	if v.is_empty():
		return "Ese vehículo no existe"
	var now: float = float(gs.today()) + TimeManager.hour_float() / 24.0
	if vehicle_busy(gs, vid, now):
		return "%s está de viaje" % str(v["name"])
	_drop_vehicle(gs, v)
	var st: Dictionary = gs.get_building(int(v["base"]))
	if not st.is_empty():
		BusinessSim.earn(gs, st, vehicle_price(gs, str(v["mode"])) * 0.4, "ventas")
	else:
		gs.add_money(vehicle_price(gs, str(v["mode"])) * 0.4)
	return ""


static func _drop_vehicle(gs, v: Dictionary) -> void:
	vehicles(gs).erase(v)
	for r in routes(gs):
		if int(r.get("vehicle", -1)) == int(v["id"]):
			r["vehicle"] = -1
			r["status"] = "Vehículo vendido: usa cualquier %s libre" % mode_short(str(v["mode"])).trim_suffix("s")


## Surtidor de combustible propio en un depósito: abarata el combustible de sus vehículos.
static func fuel_pump_price(gs, st: Dictionary) -> float:
	return float(gs.level_def(st).get("fuel_pump_price", 0.0)) * gs.price_mult()


static func buy_fuel_pump(gs, st: Dictionary) -> String:
	if fuel_pump_price(gs, st) <= 0.0:
		return "Este edificio no admite surtidor"
	if bool(st.get("fuel_pump", false)):
		return "Ya tiene surtidor"
	if gs.money < fuel_pump_price(gs, st):
		return "Dinero insuficiente (%s)" % Fmt.money(fuel_pump_price(gs, st))
	BusinessSim.pay(gs, st, fuel_pump_price(gs, st), "obras")
	st["fuel_pump"] = true
	return ""


static func fuel_discount(gs, st: Dictionary) -> float:
	return float(gs.level_def(st).get("fuel_pump_discount", 0.0)) if bool(st.get("fuel_pump", false)) else 0.0


## Mantenimiento diario de cada vehículo (incluidos y comprados) × price_mult:
## los animales comen (alimento → "insumos"), los motores se mantienen ("mantenimiento").
static func _vehicle_upkeep(gs) -> void:
	var pm: float = gs.price_mult()
	for b in stations(gs):
		var feed := 0.0
		var service := 0.0
		for m in modes():
			if not is_vehicle(m):
				continue
			var cost := float(mode_def(m).get("upkeep", 0.0)) * vehicles_at(gs, b, m)
			if bool(mode_def(m).get("animal", false)):
				feed += cost
			else:
				service += cost
		if feed > 0.0:
			BusinessSim.pay(gs, b, feed * pm, "insumos")
		if service > 0.0:
			BusinessSim.pay(gs, b, service * pm, "mantenimiento")


## Estaciones demolidas: sus vehículos se venden (40 %).
static func _sell_fleet_of(gs, station: Dictionary) -> void:
	var gone := vehicles_of(gs, int(station["id"]))
	if gone.is_empty():
		return
	var refund := 0.0
	for v in gone:
		refund += vehicle_price(gs, str(v["mode"])) * 0.4
		_drop_vehicle(gs, v)
	gs.add_money(refund)
	gs.notify("Se vendieron %d vehículos de %s por %s." % [gone.size(), gs.building_label(station), Fmt.money(refund)], "negocio")


# --- Rutas ------------------------------------------------------------------------------------

static func routes(gs) -> Array:
	if not gs.logistics.has("routes"):
		gs.logistics["routes"] = []
	return gs.logistics["routes"]


static func shipments(gs) -> Array:
	if not gs.logistics.has("shipments"):
		gs.logistics["shipments"] = []
	return gs.logistics["shipments"]


static func get_route(gs, id: int) -> Dictionary:
	for r in routes(gs):
		if int(r["id"]) == id:
			return r
	return {}


## Motivo por el que una ruta no puede operar con ese medio o vehículo ("" si puede).
static func route_block_reason(gs, from_id: int, to_id: int, mode: String, vehicle_id := -1) -> String:
	if from_id == to_id:
		return "Origen y destino son el mismo lugar"
	if not endpoint_valid(gs, from_id) or not endpoint_valid(gs, to_id):
		return "Origen o destino ya no existe"
	if vehicle_id >= 0:
		var v := get_vehicle(gs, vehicle_id)
		if v.is_empty():
			return "Ese vehículo ya no existe"
		mode = str(v["mode"])
	var md := mode_def(mode)
	if md.is_empty():
		return "Medio de transporte desconocido"
	if is_planned(mode):
		return "%s: aún no disponible" % mode_label(mode)
	if mode == "avion":
		var air := AirSim.domestic_block_reason(gs, from_id, to_id)   # Fase 10: aviones entre aeropuertos del país.
		if air != "":
			return air
	if not gs.has_tech(str(md.get("tech", ""))):
		return "Requiere investigar: %s" % GameData.tech_label(str(md.get("tech", "")))
	if vehicle_id >= 0:
		var st: Dictionary = gs.get_building(int(get_vehicle(gs, vehicle_id)["base"]))
		if st.is_empty() or str(st.get("status", "")) != "activo":
			return "El edificio de ese vehículo no está activo"
		if crew_size(gs, st) <= 0:
			return "Contrata %s en %s" % ["arrieros" if bool(md.get("animal", false)) else "conductores", gs.building_label(st)]
	else:
		var c := carriers(gs, mode)
		if int(c["total"]) <= 0:
			var any_station := false
			for b in stations(gs):
				if central_supports(gs, b, mode):
					any_station = true
			var base_label := str(GameData.building_def(mode_base(mode)).get("label", "central de transporte"))
			if not any_station:
				return "Necesitas un edificio para %s: %s (Central de transporte para cargadores)" % [mode_short(mode), base_label] if is_vehicle(mode) \
						else "Necesitas una central de transporte con cargadores"
			if is_vehicle(mode) and int(c["vehicles"]) <= 0:
				return "No tienes %s: cómpralos en %s" % [mode_short(mode), base_label]
			return "Contrata %s en la central de transporte o en %s" % ["cargadores" if not is_vehicle(mode) else "conductores", base_label]
	if bool(md.get("road", false)) and not RoadSim.connected(gs, endpoint_pos(gs, from_id), endpoint_pos(gs, to_id), road_kinds(mode)):
		var kinds := road_kinds(mode)
		if kinds.is_empty():
			return "%s necesitan carretera que una origen y destino" % mode_label(mode)
		return "%s necesitan carretera de %s que una origen y destino" % [mode_label(mode), " o ".join(kinds.map(func(k): return RoadSim.kind_label(k).to_lower()))]
	return ""


## Crea una ruta. opts: from, to, good, qty, mode, auto, every, vehicle (id o -1 = cualquiera libre),
## buy (comprar en la salida del pueblo lo que falte; solo con origen en la plaza), max_stock
## (no llevar más si el destino ya tiene esa cantidad; 0 = sin tope). Devuelve {"error"} o {"route"}.
## Con un vehículo asignado y modo manual se hace UN viaje (hasta la capacidad del vehículo).
static func create_route(gs, opts: Dictionary) -> Dictionary:
	var from_id := int(opts.get("from", PLAZA))
	var to_id := int(opts.get("to", PLAZA))
	var good := str(opts.get("good", ""))
	var qty := float(opts.get("qty", 0.0))
	var mode := str(opts.get("mode", "pie"))
	var vid := int(opts.get("vehicle", -1))
	if vid >= 0 and not get_vehicle(gs, vid).is_empty():
		mode = str(get_vehicle(gs, vid)["mode"])
	if not transportable_goods().has(good):
		return {"error": "Elige un bien para transportar"}
	if qty <= 0.0:
		return {"error": "La cantidad debe ser mayor que cero"}
	var buy := bool(opts.get("buy", false))
	if buy and from_id != PLAZA:
		return {"error": "La compra automática sale de la bodega de la plaza (salida del pueblo)"}
	if buy and buy_unit_price(gs, good) <= 0.0:
		return {"error": "%s no se puede comprar afuera" % GameData.good_label(good)}
	var reason := route_block_reason(gs, from_id, to_id, mode, vid)
	if reason != "":
		return {"error": reason}
	var auto := bool(opts.get("auto", false))
	if vid >= 0 and not auto:
		qty = minf(qty, float(trip_info(gs, from_id, to_id, mode)["per_carrier"]))   # Un viaje.
	var id := int(gs.logistics.get("next_route_id", 1))
	gs.logistics["next_route_id"] = id + 1
	var r := {"id": id, "from": from_id, "to": to_id, "good": good, "qty": qty, "mode": mode,
		"auto": auto, "every": maxi(1, int(opts.get("every", 7))), "next_day": gs.today(),
		"remaining": qty, "active": true, "moved": 0.0, "status": "", "trips": 0,
		"vehicle": vid, "buy": buy, "max_stock": maxf(0.0, float(opts.get("max_stock", 0.0))), "spent": 0.0}
	routes(gs).append(r)
	# El primer envío sale de inmediato.
	dispatch(gs, r, float(gs.today()) + maxf(TimeManager.hour_float(), float(tcfg().get("depart_hour", 7))) / 24.0)
	return {"route": r}


static func remove_route(gs, id: int) -> void:
	var rs := routes(gs)
	for i in range(rs.size()):
		if int(rs[i]["id"]) == id:
			rs.remove_at(i)
			return


static func set_route_active(gs, id: int, active: bool) -> void:
	var r := get_route(gs, id)
	if not r.is_empty():
		r["active"] = active
		if active:
			r["next_day"] = mini(int(r.get("next_day", 0)), gs.today())


## Datos de un viaje: distancia, días de ida, vueltas por día, carga por unidad y combustible.
static func trip_info(gs, from_id: int, to_id: int, mode: String) -> Dictionary:
	var md := mode_def(mode)
	var p1 := endpoint_pos(gs, from_id)
	var p2 := endpoint_pos(gs, to_id)
	var dist := p1.distance_to(p2) * float(tcfg().get("route_factor", 1.25))
	var speed := float(md.get("speed", 180.0))
	if bool(md.get("road", false)):
		speed *= RoadSim.speed_mult(gs, p1, p2, road_kinds(mode))
	var travel := maxf(0.02, dist / speed)
	var trips := clampi(int(0.66 / (2.0 * travel)), 1, int(tcfg().get("max_trips_per_day", 4)))
	var cap := float(md.get("capacity", 10.0))
	# Combustible por vehículo: ida y vuelta de cada viaje.
	var pm: float = gs.price_mult()
	var km := dist / 1000.0 * 2.0 * trips
	var fuel := float(md.get("fuel_per_km", 0.0)) * km * _fuel_price() * pm
	return {"distance": dist, "travel": travel, "trips": trips, "per_carrier": cap * trips, "capacity": cap,
		"fuel_per_vehicle": fuel, "km_per_vehicle": km}


static func _fuel_price() -> float:
	return float(GameData.extra("trade").get("fuel_price", 1.0))


## Precio de compra en la salida del pueblo (importador): precio de importación × dificultad × aranceles.
static func buy_unit_price(gs, good: String) -> float:
	var pm: float = gs.price_mult()
	return float(GameData.goods.get(good, {}).get("import_price", 0.0)) * pm * GovSim.import_mult(gs)


## Reúne las unidades para un envío. Con vehículo asignado solo ese; si no, cualquier unidad libre
## del medio (primero los vehículos incluidos de las centrales, luego los comprados).
## Devuelve {"crew": [[estación, n]], "vehicles": [ids], "got": n}.
static func _allocate(gs, r: Dictionary, mode: String, need: int, depart: float) -> Dictionary:
	var crew := []
	var vids := []
	var got := 0
	var vid := int(r.get("vehicle", -1))
	if vid >= 0:
		var v := get_vehicle(gs, vid)
		var st: Dictionary = gs.get_building(int(v.get("base", -1)))
		if not v.is_empty() and not st.is_empty() and not vehicle_busy(gs, vid, depart) and _free_people(gs, st, depart) > 0:
			crew.append([int(st["id"]), 1])
			vids.append(vid)
			got = 1
		return {"crew": crew, "vehicles": vids, "got": got}
	for b in stations(gs):
		if got >= need:
			break
		if not central_supports(gs, b, mode):
			continue
		var use := mini(free_units(gs, b, mode, depart), need - got)
		if use <= 0:
			continue
		if is_vehicle(mode):
			var inc := maxi(0, included_at(gs, b, mode) - _included_busy(gs, int(b["id"]), mode, depart))
			var from_own := maxi(0, use - inc)
			for v in _free_vehicles(gs, b, mode, depart).slice(0, from_own):
				vids.append(int(v["id"]))
		crew.append([int(b["id"]), use])
		got += use
	return {"crew": crew, "vehicles": vids, "got": got}


## Intenta despachar un envío de la ruta ahora. Devuelve las unidades cargadas.
static func dispatch(gs, r: Dictionary, depart: float) -> float:
	var from_id := int(r["from"])
	var to_id := int(r["to"])
	var mode := str(r["mode"])
	var good := str(r["good"])
	var auto := bool(r.get("auto", false))
	var buy := bool(r.get("buy", false))
	var reason := route_block_reason(gs, from_id, to_id, mode, int(r.get("vehicle", -1)))
	if reason != "":
		r["status"] = reason
		return 0.0
	var want := float(r["qty"]) if auto else float(r.get("remaining", r["qty"]))
	if float(r.get("max_stock", 0.0)) > 0.0:
		want = minf(want, float(r["max_stock"]) - endpoint_stock(gs, to_id, good) - _in_flight_to(gs, to_id, good, true))
		if want <= 0.01:
			r["status"] = "El destino ya tiene %s de %s" % [Fmt.thousands(endpoint_stock(gs, to_id, good)), GameData.good_label(good).to_lower()]
			if auto:
				r["next_day"] = gs.today() + 1
			return 0.0
	var avail := endpoint_stock(gs, from_id, good)
	if buy:
		avail = INF   # Lo que falte se compra en la salida del pueblo.
	var room := endpoint_room(gs, to_id, good) - _in_flight_to(gs, to_id, good)
	var qty := minf(want, minf(avail, room))
	if qty <= 0.01:
		r["status"] = "Sin %s en el origen" % GameData.good_label(good).to_lower() if avail <= 0.01 else "Destino lleno"
		if auto:
			r["next_day"] = gs.today() + 1
		return 0.0
	var info := trip_info(gs, from_id, to_id, mode)
	var per_carrier := float(info["per_carrier"])
	var alloc := _allocate(gs, r, mode, int(ceil(qty / per_carrier)), depart)
	var got := int(alloc["got"])
	if got <= 0:
		r["status"] = ("%s ocupado o sin conductor (esperando)" % str(get_vehicle(gs, int(r["vehicle"])).get("name", "Vehículo"))) if int(r.get("vehicle", -1)) >= 0 \
				else "Sin %s libres (esperando)" % mode_short(mode)
		if auto:
			r["next_day"] = gs.today() + 1
		return 0.0
	qty = minf(qty, got * per_carrier)
	# Compra automática de insumos en la salida del pueblo (solo lo que no hay en la bodega).
	var bought := 0.0
	var spent := 0.0
	if buy:
		var have := endpoint_stock(gs, from_id, good)
		bought = maxf(0.0, qty - have)
		if bought > 0.0:
			var unit := buy_unit_price(gs, good)
			var affordable := floorf(maxf(0.0, gs.money) / maxf(0.01, unit))
			bought = minf(bought, affordable)
			qty = have + bought
			spent = bought * unit
			if qty <= 0.01:
				r["status"] = "Sin dinero para comprar %s" % GameData.good_label(good).to_lower()
				if auto:
					r["next_day"] = gs.today() + 1
				return 0.0
	var taken := endpoint_take(gs, from_id, good, qty - bought) + bought
	if taken <= 0.0:
		return 0.0
	if spent > 0.0:
		var payer: Dictionary = gs.get_building(to_id)
		if not payer.is_empty() and BusinessSim.is_business(payer):
			BusinessSim.pay(gs, payer, spent, "insumos")
		else:
			gs.add_money(-spent)
		r["spent"] = float(r.get("spent", 0.0)) + spent
	# Combustible de los vehículos motorizados (lo paga su estación; el surtidor lo abarata).
	var fuel_total := 0.0
	var fpv := float(info["fuel_per_vehicle"])
	for pair in alloc["crew"]:
		var st: Dictionary = gs.get_building(int(pair[0]))
		if fpv > 0.0 and not st.is_empty():
			var cost := fpv * int(pair[1]) * (1.0 - fuel_discount(gs, st))
			BusinessSim.pay(gs, st, cost, "insumos")
			fuel_total += cost
	if fuel_total > 0.0:
		var stt: Dictionary = gs.logistics.get("stats", {})
		stt["month_fuel"] = float(stt.get("month_fuel", 0.0)) + fuel_total
		stt["total_fuel"] = float(stt.get("total_fuel", 0.0)) + fuel_total
		gs.logistics["stats"] = stt
	for vid in alloc["vehicles"]:
		var v := get_vehicle(gs, int(vid))
		v["km"] = float(v.get("km", 0.0)) + float(info["km_per_vehicle"])
		v["trips"] = int(v.get("trips", 0)) + 1
	var travel := float(info["travel"])
	var trips := int(info["trips"])
	shipments(gs).append({
		"route": int(r["id"]), "good": good, "qty": taken, "from": from_id, "to": to_id, "mode": mode,
		"crew": alloc["crew"], "vehicles": alloc["vehicles"], "carriers": got, "depart": depart, "travel": travel, "trips": trips,
		"arrive": depart + (2.0 * trips - 1.0) * travel, "back": depart + 2.0 * trips * travel,
		"ax": endpoint_pos(gs, from_id).x, "az": endpoint_pos(gs, from_id).y,
		"bx": endpoint_pos(gs, to_id).x, "bz": endpoint_pos(gs, to_id).y, "delivered": false,
		"fuel": fuel_total, "bought": bought,
	})
	r["trips"] = int(r.get("trips", 0)) + 1
	var who := str(get_vehicle(gs, int(r["vehicle"])).get("name", "")) if int(r.get("vehicle", -1)) >= 0 else "%d %s" % [got, mode_short(mode)]
	r["status"] = "En camino: %s %s (%s%s%s)" % [_num(snappedf(taken, 0.1)), GameData.good_label(good).to_lower(), who,
			", combustible %s" % Fmt.money2(fuel_total) if fuel_total > 0.0 else "",
			", compró %s por %s" % [_num(snappedf(bought, 0.1)), Fmt.money(spent)] if bought > 0.0 else ""]
	if auto:
		r["next_day"] = gs.today() + int(r.get("every", 7))
	else:
		r["remaining"] = maxf(0.0, float(r.get("remaining", r["qty"])) - taken)
		if int(r.get("vehicle", -1)) >= 0:
			r["remaining"] = 0.0   # Manual con vehículo asignado: un solo viaje.
		if float(r["remaining"]) <= 0.01:
			r["active"] = false
			r["status"] = "Último envío en camino"
	return taken


static func _in_flight_to(gs, to_id: int, good: String, only_good := false) -> float:
	var whole := is_warehouse_endpoint(gs, to_id) and not only_good   # En un almacén cuenta todo lo que llega (1 u. = 1 espacio).
	var t := 0.0
	for s in shipments(gs):
		if not bool(s["delivered"]) and int(s["to"]) == to_id and (whole or str(s["good"]) == good):
			t += float(s["qty"])
	return t


## Entrega los envíos que ya llegaron y libera a los cargadores y vehículos que regresaron.
static func _complete_shipments(gs, now: float) -> void:
	var st: Dictionary = gs.logistics.get("stats", {})
	var keep := []
	for s in shipments(gs):
		if not bool(s["delivered"]) and float(s["arrive"]) <= now:
			s["delivered"] = true
			var good := str(s["good"])
			var qty := float(s["qty"])
			var acc := endpoint_put(gs, int(s["to"]), good, qty) if endpoint_valid(gs, int(s["to"])) else 0.0
			if acc < qty - 0.01:
				var back := endpoint_put(gs, int(s["from"]), good, qty - acc) if endpoint_valid(gs, int(s["from"])) else 0.0
				gs.notify("Transporte: el destino no tenía espacio; %s de %s %s." % [_num(snappedf(qty - acc, 0.1)), GameData.good_label(good).to_lower(),
						"volvieron al origen" if back > 0.0 else "se perdieron"], "negocio")
			st["month_moved"] = float(st.get("month_moved", 0.0)) + acc
			st["total_moved"] = float(st.get("total_moved", 0.0)) + acc
			var r := get_route(gs, int(s["route"]))
			if not r.is_empty():
				r["moved"] = float(r.get("moved", 0.0)) + acc
				if not bool(r.get("auto", false)) and not bool(r.get("active", true)) and float(r.get("remaining", 0.0)) <= 0.01 and not _has_pending(gs, int(r["id"]), s):
					gs.notify("Ruta completada: %s → %s (%s %s)." % [endpoint_label(gs, int(r["from"])), endpoint_label(gs, int(r["to"])),
							_num(snappedf(float(r["moved"]), 0.1)), GameData.good_label(good).to_lower()], "negocio")
					remove_route(gs, int(r["id"]))
		if not (bool(s["delivered"]) and float(s["back"]) <= now):
			keep.append(s)
	gs.logistics["shipments"] = keep
	gs.logistics["stats"] = st


static func _has_pending(gs, route_id: int, except: Dictionary) -> bool:
	for s in shipments(gs):
		if not is_same(s, except) and int(s["route"]) == route_id and not bool(s["delivered"]):
			return true
	return false


## Unidades que esperan transporte en el sitio (negocios sin almacén al lado).
static func pending_at_sites(gs) -> Dictionary:
	var out := {}
	for b in chain_buildings(gs):
		if output_target(gs, b) != "local":
			continue
		var product := str(gs.building_def(b).get("product", ""))
		var q := float(b["inventory"].get(product, 0.0))
		if q > 0.01:
			out[int(b["id"])] = q
	return out
