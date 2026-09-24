class_name LogisticsSim
extends RefCounted
## Fase 6 — recursos por región, yacimientos, recetas de producción, transporte interno
## (a pie / caballos / camiones), carreteras y rutas manuales/automáticas.
## El estado vive en GameState.logistics y se guarda automáticamente:
##   region, deposits (RegionSim) · warehouse (WarehouseSim) · roads (RoadSim)
##   routes, shipments, next_route_id, stats (este archivo)
##
## Diseño del transporte (ver docs/FASE6.md):
## - Los talleres/fábricas con "inputs" toman insumos del almacén de la compañía y, con
##   "output": "warehouse", guardan lo producido en el almacén (sin transporte).
## - Las extracciones (minas con requires_deposit, campos con "extraction") descargan directo al
##   almacén solo si están a menos de warehouse.walk_reach de un almacén o de la bodega de la
##   plaza (sus propios trabajadores lo cargan). Más lejos, la producción queda en el sitio
##   (inventario del edificio) y la llevan las RUTAS de transporte con cargadores o carretas.
## - Las rutas mueven cualquier bien entre edificios y el almacén: manual (un envío) o
##   automática (cada X días lleva X cantidad). Los cargadores/arrieros son empleados de la
##   Central de transporte; las carretas y camiones exigen tecnología y carretera.

const PLAZA := 0   # Punto de almacén: la bodega de la plaza (0, 0).


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
	if not L.has("warehouse"):
		L["warehouse"] = {}


static func daily(gs) -> void:
	var today: int = gs.today()
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
	gs.logistics["stats"] = st


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


## Puntos donde se puede descargar al almacén: la bodega de la plaza y tus almacenes activos.
static func warehouse_points(gs) -> Array:
	var out := [{"id": PLAZA, "pos": Vector2.ZERO}]
	for b in gs.buildings:
		if gs.owned_by_player(b) and b["status"] == "activo" and float(gs.level_def(b).get("warehouse_capacity", 0.0)) > 0.0:
			out.append({"id": int(b["id"]), "pos": Vector2(float(b["x"]), float(b["z"]))})
	return out


## Distancia al almacén (o bodega) más cercano.
static func warehouse_distance(gs, x: float, z: float) -> float:
	var best := INF
	for p in warehouse_points(gs):
		best = minf(best, Vector2(x, z).distance_to(p["pos"]))
	return best


## Una extracción está "al alcance" si sus trabajadores pueden cargar a pie hasta un almacén.
static func in_reach(gs, b: Dictionary) -> bool:
	return warehouse_distance(gs, float(b["x"]), float(b["z"])) <= float(wcfg().get("walk_reach", 30.0))


## Dónde queda la producción de un negocio de la cadena: "warehouse" o "local" (en el sitio).
static func output_target(gs, b: Dictionary) -> String:
	var def: Dictionary = gs.building_def(b)
	var ld: Dictionary = gs.level_def(b)
	if not outputs_to_warehouse(def, ld):
		return "local"
	if is_extraction(def, ld) and not in_reach(gs, b):
		return "local"
	return "warehouse"


static func local_capacity(gs, b: Dictionary) -> float:
	if BusinessSim.is_business(b):
		return maxf(BusinessSim.storage_cap(gs, b), 100.0)
	return 200.0


## Insumo disponible para un negocio: su inventario local + el almacén de la compañía.
static func input_available(gs, b: Dictionary, good: String) -> float:
	return float(b["inventory"].get(good, 0.0)) + WarehouseSim.stock(gs, good)


static func take_input(gs, b: Dictionary, good: String, qty: float) -> void:
	var inv: Dictionary = b["inventory"]
	var local := minf(float(inv.get(good, 0.0)), qty)
	if local > 0.0:
		inv[good] = float(inv[good]) - local
	if qty - local > 0.0:
		WarehouseSim.remove(gs, good, qty - local)


## Produce `out` unidades con receta/yacimiento/almacén. Devuelve lo realmente producido.
static func produce_chain(gs, b: Dictionary, product: String, out: float) -> float:
	var def: Dictionary = gs.building_def(b)
	var ld: Dictionary = gs.level_def(b)
	var inputs := recipe_inputs(def, ld)
	var target := output_target(gs, b)
	var inv: Dictionary = b["inventory"]
	b["chain_status"] = ""
	# 1) Espacio donde guardar lo producido.
	var room := INF
	if target == "warehouse":
		var per_unit_in := 0.0
		for g in inputs:
			per_unit_in += float(inputs[g])
		room = WarehouseSim.free_space(gs) / maxf(0.0001, 1.0 - per_unit_in) if per_unit_in < 1.0 else INF
	elif bool(GameData.goods.get(product, {}).get("storable", true)):
		room = maxf(0.0, local_capacity(gs, b) - float(inv.get(product, 0.0)))
	if out > room:
		out = maxf(0.0, room)
		b["chain_status"] = "almacén lleno" if target == "warehouse" else "patio lleno: falta transporte"
		_warn(gs, b, "full", ("%s: el almacén de la compañía está lleno; se perdió producción. Construye o mejora un almacén." if target == "warehouse"
				else "%s acumuló su producción en el sitio: crea una ruta de transporte hacia el almacén.") % gs.building_label(b))
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
			_warn(gs, b, "inputs", "%s no tiene suficiente %s en el almacén: produce menos." % [gs.building_label(b), " ni ".join(missing)])
		for g in inputs:
			take_input(gs, b, g, float(inputs[g]) * out)
	if out <= 0.0:
		b["produced_today"] = 0.0
		return 0.0
	# 4) Guardar.
	RegionSim.deplete(gs, dep, out)
	var stored := out
	if target == "warehouse":
		stored = WarehouseSim.add(gs, product, out)
		if stored < out - 0.001:
			b["chain_status"] = "almacén lleno"
			_warn(gs, b, "full", "%s: el almacén de la compañía está lleno; se perdió producción." % gs.building_label(b))
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


# --- Puntos de origen/destino de las rutas ---------------------------------------------------

static func is_warehouse_endpoint(gs, id: int) -> bool:
	if id == PLAZA:
		return true
	var b: Dictionary = gs.get_building(id)
	return not b.is_empty() and float(gs.level_def(b).get("warehouse_capacity", 0.0)) > 0.0


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
		return str(wcfg().get("plaza_label", "Bodega de la plaza"))
	var b: Dictionary = gs.get_building(id)
	if b.is_empty():
		return "(demolido)"
	return gs.building_label(b) + (" (almacén)" if is_warehouse_endpoint(gs, id) else "")


## Posibles orígenes/destinos: la bodega, tus almacenes y tus negocios (no servicios).
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
		return WarehouseSim.stock(gs, good)
	return float(gs.get_building(id).get("inventory", {}).get(good, 0.0))


static func endpoint_room(gs, id: int, good: String) -> float:
	if is_warehouse_endpoint(gs, id):
		return WarehouseSim.free_space(gs)
	var b: Dictionary = gs.get_building(id)
	if b.is_empty():
		return 0.0
	return maxf(0.0, local_capacity(gs, b) - float(b["inventory"].get(good, 0.0)))


static func endpoint_take(gs, id: int, good: String, qty: float) -> float:
	if is_warehouse_endpoint(gs, id):
		return WarehouseSim.remove(gs, good, qty)
	var b: Dictionary = gs.get_building(id)
	if b.is_empty():
		return 0.0
	var inv: Dictionary = b["inventory"]
	var take := minf(qty, float(inv.get(good, 0.0)))
	inv[good] = float(inv.get(good, 0.0)) - take
	return take


static func endpoint_put(gs, id: int, good: String, qty: float) -> float:
	if is_warehouse_endpoint(gs, id):
		return WarehouseSim.add(gs, good, qty)
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


# --- Medios de transporte y centrales ----------------------------------------------------------

static func modes() -> Dictionary:
	return tcfg().get("modes", {})


static func mode_def(mode: String) -> Dictionary:
	return modes().get(mode, {})


static func mode_label(mode: String) -> String:
	return str(mode_def(mode).get("label", mode))


static func centrals(gs) -> Array:
	var out := []
	for b in gs.buildings:
		if gs.owned_by_player(b) and b["status"] == "activo" and gs.level_def(b).has("transport_modes"):
			out.append(b)
	return out


## Trabajadores de una central disponibles hoy (empleados, no enfermos).
static func crew_size(gs, b: Dictionary) -> int:
	var n := 0
	for c in gs.employees_of(int(b["id"])):
		if c.job_kind == "empleo" and not c.sick:
			n += 1
	return n


static func busy_in(gs, central_id: int, now: float) -> int:
	var n := 0
	for s in shipments(gs):
		if float(s["back"]) > now:
			for pair in s.get("crew", []):
				if int(pair[0]) == central_id:
					n += int(pair[1])
	return n


## {total, free} de cargadores/arrieros para un medio.
static func carriers(gs, mode: String, now := -1.0) -> Dictionary:
	if now < 0.0:
		now = float(gs.today())
	var total := 0
	var free := 0
	for b in centrals(gs):
		if not (gs.level_def(b)["transport_modes"] as Array).has(mode):
			continue
		var n := crew_size(gs, b)
		total += n
		free += maxi(0, n - busy_in(gs, int(b["id"]), now))
	return {"total": total, "free": free}


static func _vehicle_upkeep(gs) -> void:
	var pm: float = gs.price_mult()
	for b in centrals(gs):
		var vu := float(gs.level_def(b).get("vehicle_upkeep", 0.0))
		if vu > 0.0:
			var n := crew_size(gs, b)
			if n > 0:
				BusinessSim.pay(gs, b, vu * n * pm, "mantenimiento")


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


## Motivo por el que una ruta no puede operar con ese medio ("" si puede).
static func route_block_reason(gs, from_id: int, to_id: int, mode: String) -> String:
	if from_id == to_id:
		return "Origen y destino son el mismo lugar"
	if is_warehouse_endpoint(gs, from_id) and is_warehouse_endpoint(gs, to_id):
		return "Ambos puntos son el mismo almacén de la compañía"
	if not endpoint_valid(gs, from_id) or not endpoint_valid(gs, to_id):
		return "Origen o destino ya no existe"
	var md := mode_def(mode)
	if md.is_empty():
		return "Medio de transporte desconocido"
	if not gs.has_tech(str(md.get("tech", ""))):
		return "Requiere investigar: %s" % GameData.tech_label(str(md.get("tech", "")))
	if int(carriers(gs, mode)["total"]) <= 0:
		return "Necesitas una central de transporte con %s y empleados" % mode_label(mode).to_lower()
	if bool(md.get("road", false)) and not RoadSim.connected(gs, endpoint_pos(gs, from_id), endpoint_pos(gs, to_id)):
		return "%s necesita carretera que una origen y destino" % mode_label(mode)
	return ""


## Crea una ruta. opts: from, to, good, qty, mode, auto, every. Devuelve {"error"} o {"route"}.
static func create_route(gs, opts: Dictionary) -> Dictionary:
	var from_id := int(opts.get("from", PLAZA))
	var to_id := int(opts.get("to", PLAZA))
	var good := str(opts.get("good", ""))
	var qty := float(opts.get("qty", 0.0))
	var mode := str(opts.get("mode", "pie"))
	if not transportable_goods().has(good):
		return {"error": "Elige un bien para transportar"}
	if qty <= 0.0:
		return {"error": "La cantidad debe ser mayor que cero"}
	var reason := route_block_reason(gs, from_id, to_id, mode)
	if reason != "":
		return {"error": reason}
	var id := int(gs.logistics.get("next_route_id", 1))
	gs.logistics["next_route_id"] = id + 1
	var auto := bool(opts.get("auto", false))
	var r := {"id": id, "from": from_id, "to": to_id, "good": good, "qty": qty, "mode": mode,
		"auto": auto, "every": maxi(1, int(opts.get("every", 7))), "next_day": gs.today(),
		"remaining": qty, "active": true, "moved": 0.0, "status": "", "trips": 0}
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


## Datos de un viaje: distancia, días de ida y cuántas vueltas caben en un día de trabajo.
static func trip_info(gs, from_id: int, to_id: int, mode: String) -> Dictionary:
	var md := mode_def(mode)
	var p1 := endpoint_pos(gs, from_id)
	var p2 := endpoint_pos(gs, to_id)
	var dist := p1.distance_to(p2) * float(tcfg().get("route_factor", 1.25))
	var speed := float(md.get("speed", 180.0))
	if bool(md.get("road", false)):
		speed *= RoadSim.speed_mult(gs, p1, p2)
	var travel := maxf(0.02, dist / speed)
	var trips := clampi(int(0.66 / (2.0 * travel)), 1, int(tcfg().get("max_trips_per_day", 4)))
	var cap := float(md.get("capacity", 10.0))
	return {"distance": dist, "travel": travel, "trips": trips, "per_carrier": cap * trips}


## Intenta despachar un envío de la ruta ahora. Devuelve las unidades cargadas.
static func dispatch(gs, r: Dictionary, depart: float) -> float:
	var from_id := int(r["from"])
	var to_id := int(r["to"])
	var mode := str(r["mode"])
	var good := str(r["good"])
	var auto := bool(r.get("auto", false))
	var reason := route_block_reason(gs, from_id, to_id, mode)
	if reason != "":
		r["status"] = reason
		return 0.0
	var want := float(r["qty"]) if auto else float(r.get("remaining", r["qty"]))
	var avail := endpoint_stock(gs, from_id, good)
	var room := endpoint_room(gs, to_id, good) - _in_flight_to(gs, to_id, good)
	var qty := minf(want, minf(avail, room))
	if qty <= 0.01:
		r["status"] = "Sin %s en el origen" % GameData.good_label(good).to_lower() if avail <= 0.01 else "Destino lleno"
		if auto:
			r["next_day"] = gs.today() + 1
		return 0.0
	var info := trip_info(gs, from_id, to_id, mode)
	var per_carrier := float(info["per_carrier"])
	var need := int(ceil(qty / per_carrier))
	var crew := []
	var got := 0
	for b in centrals(gs):
		if got >= need:
			break
		if not (gs.level_def(b)["transport_modes"] as Array).has(mode):
			continue
		var free := crew_size(gs, b) - busy_in(gs, int(b["id"]), depart)
		var use := mini(free, need - got)
		if use > 0:
			crew.append([int(b["id"]), use])
			got += use
	if got <= 0:
		r["status"] = "Sin cargadores libres (esperando)"
		if auto:
			r["next_day"] = gs.today() + 1
		return 0.0
	qty = minf(qty, got * per_carrier)
	var taken := endpoint_take(gs, from_id, good, qty)
	if taken <= 0.0:
		return 0.0
	var travel := float(info["travel"])
	var trips := int(info["trips"])
	shipments(gs).append({
		"route": int(r["id"]), "good": good, "qty": taken, "from": from_id, "to": to_id, "mode": mode,
		"crew": crew, "carriers": got, "depart": depart, "travel": travel, "trips": trips,
		"arrive": depart + (2.0 * trips - 1.0) * travel, "back": depart + 2.0 * trips * travel,
		"ax": endpoint_pos(gs, from_id).x, "az": endpoint_pos(gs, from_id).y,
		"bx": endpoint_pos(gs, to_id).x, "bz": endpoint_pos(gs, to_id).y, "delivered": false,
	})
	r["trips"] = int(r.get("trips", 0)) + 1
	r["status"] = "En camino: %s %s (%d %s)" % [_num(snappedf(taken, 0.1)), GameData.good_label(good).to_lower(), got, "cargadores" if mode == "pie" else "vehículos"]
	if auto:
		r["next_day"] = gs.today() + int(r.get("every", 7))
	else:
		r["remaining"] = maxf(0.0, float(r.get("remaining", r["qty"])) - taken)
		if float(r["remaining"]) <= 0.01:
			r["active"] = false
			r["status"] = "Último envío en camino"
	return taken


static func _in_flight_to(gs, to_id: int, good: String) -> float:
	if is_warehouse_endpoint(gs, to_id):
		var total := 0.0
		for s in shipments(gs):
			if not bool(s["delivered"]) and is_warehouse_endpoint(gs, int(s["to"])):
				total += float(s["qty"])
		return total
	var t := 0.0
	for s in shipments(gs):
		if not bool(s["delivered"]) and int(s["to"]) == to_id and str(s["good"]) == good:
			t += float(s["qty"])
	return t


## Entrega los envíos que ya llegaron y libera a los cargadores que regresaron.
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


## Unidades que esperan transporte en el sitio (extracciones lejos del almacén).
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
