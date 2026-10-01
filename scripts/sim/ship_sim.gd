class_name ShipSim
extends RefCounted
## Barcos, puertos y astilleros (docs/RUTAS_BARCOS.md).
## - Puerto (Muelle → Puerto comercial → Puerto de contenedores, businesses_comercio.json): solo en la
##   costa o a la orilla de un río o lago (`requires_shore`). Es un almacén (bodega portuaria) y los
##   almacenes construidos AL LADO (a menos de `port_reach` entre bordes) quedan vinculados al puerto:
##   los barcos cargan y descargan en el puerto y en esos almacenes (`port_of`).
## - Astillero (businesses_naval.json): el garaje de los barcos; debe tocar el agua. Su nivel define qué
##   barcos ofrece (bote, velero, vapor, carguero, portacontenedores), con capacidad, velocidad,
##   mantenimiento, combustible por km y tripulación (`crew`).
## - Rutas NACIONALES: rutas de la Fase 6 (LogisticsSim) con un medio de agua entre dos puntos de puerto
##   unidos por agua navegable (`ports_connected`: búsqueda sobre una cuadrícula de agua; dos puertos de
##   mar siempre se unen por el mar abierto).
## - Rutas INTERNACIONALES (`ship_intl`): barco propio (sale de un puerto de mar tuyo con un barco de
##   un astillero conectado, vuelve vacío) o naviera (flete por unidad, salidas cada N días). Más barato y
##   más lento que el avión. Se guardan como envíos de AirSim (countries.air.flights con "ship": true) y
##   al llegar pagan el arancel del destino y el tipo de cambio igual que la carga aérea (AirSim._deliver).

static var _water_cache := {}   # clave -> {ok, path}


static func cfg() -> Dictionary:
	return GameData.extra("rutas")


static func wcfg() -> Dictionary:
	return cfg().get("water", {})


# --- Agua -----------------------------------------------------------------------------------------

static func water_level(gs) -> float:
	return MapSim.gen(gs).water_level


static func is_water(gs, p: Vector2) -> bool:
	return MapSim.height_at(p.x, p.y, gs) < water_level(gs) - 0.2


## "mar", "rio" (río o lago) o "" si el punto no es agua.
static func water_kind(gs, p: Vector2) -> String:
	if not is_water(gs, p):
		return ""
	# La orilla puede clasificarse como costa o río: se mira también el agua alrededor (hasta 60 m).
	if MapSim.biome_at(p.x, p.y, gs) == "mar":
		return "mar"
	for r in [25.0, 60.0]:
		for i in range(8):
			var q: Vector2 = p + Vector2(cos(TAU * i / 8.0), sin(TAU * i / 8.0)) * r
			if is_water(gs, q) and MapSim.biome_at(q.x, q.y, gs) == "mar":
				return "mar"
	return "rio"


## Punto de agua más cercano al borde de una huella (Vector2.INF si no toca el agua).
static func shore_point(gs, x: float, z: float, footprint: float) -> Vector2:
	var reach := float(wcfg().get("shore_reach", 10.0))
	var c := Vector2(x, z)
	var r0 := footprint * 0.5
	var d := r0 + 1.0
	while d <= r0 + reach + 0.01:
		for i in range(16):
			var a := TAU * i / 16.0
			var p := c + Vector2(cos(a), sin(a)) * d
			if is_water(gs, p):
				return p
		d += 2.0
	return Vector2.INF


static func requires_shore(type_id: String) -> bool:
	return bool(GameData.building_def(type_id).get("requires_shore", false))


## ConstructionSim.placement_block_reason: puerto y astillero deben tocar el agua.
static func placement_block_reason(gs, type_id: String, x: float, z: float, level := 1) -> String:
	if not requires_shore(type_id):
		return ""
	if shore_point(gs, x, z, GameData.footprint(type_id, level)) == Vector2.INF:
		return "Debe tocar el agua: constrúyelo en la costa o a la orilla de un río o lago"
	return ""


## Busca un punto de tierra junto al agua cerca de `near` (para pruebas, capturas y sugerencias).
## kind: "" (cualquier agua), "mar" o "rio". Devuelve Vector2.INF si no encuentra.
static func find_shore(gs, near: Vector2, radius: float, step := 20.0, kind := "", footprint := 6.0) -> Vector2:
	var best := Vector2.INF
	var bd := INF
	var wl := water_level(gs)
	var n := int(radius / step)
	for ix in range(-n, n + 1):
		for iz in range(-n, n + 1):
			var p := near + Vector2(ix, iz) * step
			if p.distance_to(near) >= bd or not MapSim.in_country(gs, p.x, p.y):
				continue
			if MapSim.height_at(p.x, p.y, gs) < wl + 1.0:
				continue
			var s := shore_point(gs, p.x, p.y, footprint)
			if s == Vector2.INF or (kind != "" and water_kind(gs, s) != kind):
				continue
			# Toda la huella en tierra (como exige el mundo 3D).
			var dry := true
			for dx in [-1.0, 0.0, 1.0]:
				for dz in [-1.0, 0.0, 1.0]:
					if MapSim.height_at(p.x + dx * footprint * 0.5, p.y + dz * footprint * 0.5, gs) < wl + 0.5:
						dry = false
			if dry:
				bd = p.distance_to(near)
				best = p
	return best


# --- Puertos --------------------------------------------------------------------------------------

static func is_port_type(type_id: String) -> bool:
	return bool(GameData.building_def(type_id).get("port", false))


static func ports(gs) -> Array:
	var out := []
	for b in gs.buildings:
		if is_port_type(str(b.get("type", ""))) and gs.owned_by_player(b) and gs.is_active(b):
			out.append(b)
	return out


static func _pos(b: Dictionary) -> Vector2:
	return Vector2(float(b.get("x", 0.0)), float(b.get("z", 0.0)))


## Puerto al que pertenece un punto de ruta: el propio puerto o el almacén vinculado a él (al lado). -1 si ninguno.
static func port_of(gs, id: int) -> int:
	if id == LogisticsSim.PLAZA:
		return -1
	var b: Dictionary = gs.get_building(id)
	if b.is_empty():
		return -1
	if is_port_type(str(b.get("type", ""))):
		return id if gs.owned_by_player(b) and gs.is_active(b) else -1
	if not WarehouseSim.is_warehouse_building(gs, b):
		return -1
	var reach := float(cfg().get("port_reach", 12.0))
	var best := -1
	var bd := INF
	for p in ports(gs):
		var gap := WarehouseSim.edge_gap(_pos(b), gs.footprint_of(b) * 0.5, _pos(p), gs.footprint_of(p) * 0.5)
		if gap <= reach and gap < bd:
			bd = gap
			best = int(p["id"])
	return best


## Almacenes vinculados a un puerto (al lado).
static func port_warehouses(gs, port_id: int) -> Array:
	var out := []
	for b in gs.buildings:
		if int(b["id"]) != port_id and port_of(gs, int(b["id"])) == port_id:
			out.append(int(b["id"]))
	return out


## Punto de agua del muelle de un edificio (puerto o astillero).
static func dock_point(gs, b: Dictionary) -> Vector2:
	return shore_point(gs, float(b["x"]), float(b["z"]), gs.footprint_of(b))


## "mar", "rio" o "" (sin agua) del muelle de un puerto.
static func port_water(gs, port_id: int) -> String:
	var b: Dictionary = gs.get_building(port_id)
	if b.is_empty():
		return ""
	var d := dock_point(gs, b)
	return "" if d == Vector2.INF else water_kind(gs, d)


# --- Conexión por agua ------------------------------------------------------------------------------

## ¿Se puede navegar de un punto de agua a otro? {ok, path}. Búsqueda en anchura sobre una cuadrícula
## de agua alrededor de ambos puntos; dos puntos de mar se unen siempre por el mar abierto.
static func water_route(gs, a: Vector2, b: Vector2) -> Dictionary:
	if a == Vector2.INF or b == Vector2.INF:
		return {"ok": false, "path": PackedVector2Array()}
	var key := "%s|%d|%d|%d|%d" % [MapSim.country_id(gs), int(a.x), int(a.y), int(b.x), int(b.y)]
	if _water_cache.has(key):
		return _water_cache[key]
	var res := _bfs(gs, a, b)
	if not bool(res["ok"]) and water_kind(gs, a) == "mar" and water_kind(gs, b) == "mar":
		res = {"ok": true, "path": PackedVector2Array([a, b]), "open_sea": true}
	if _water_cache.size() > 64:
		_water_cache.clear()
	_water_cache[key] = res
	return res


static func _bfs(gs, a: Vector2, b: Vector2) -> Dictionary:
	var margin := float(wcfg().get("margin", 240.0))
	var cell := float(wcfg().get("cell", 12.0))
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(margin, margin)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(margin, margin)
	var max_cells := int(wcfg().get("max_cells", 60000))
	while ((hi.x - lo.x) / cell) * ((hi.y - lo.y) / cell) > max_cells:
		cell *= 1.5
	var nx := int(ceil((hi.x - lo.x) / cell)) + 1
	var nz := int(ceil((hi.y - lo.y) / cell)) + 1
	var wl := water_level(gs) - 0.2
	var water := PackedByteArray()
	water.resize(nx * nz)
	water.fill(2)   # 2 = sin evaluar
	var to_i := func(p: Vector2) -> int:
		return clampi(int(round((p.y - lo.y) / cell)), 0, nz - 1) * nx + clampi(int(round((p.x - lo.x) / cell)), 0, nx - 1)
	var s: int = to_i.call(a)
	var g: int = to_i.call(b)
	var prev := PackedInt32Array()
	prev.resize(nx * nz)
	prev.fill(-1)
	prev[s] = s
	var queue := PackedInt32Array([s])
	var head := 0
	var found := s == g
	while head < queue.size() and not found:
		var cur := queue[head]
		head += 1
		var cx := cur % nx
		var cz := cur / nx
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var x2: int = cx + d.x
			var z2: int = cz + d.y
			if x2 < 0 or z2 < 0 or x2 >= nx or z2 >= nz:
				continue
			var n := z2 * nx + x2
			if prev[n] >= 0:
				continue
			if water[n] == 2:
				var p := Vector2(lo.x + x2 * cell, lo.y + z2 * cell)
				water[n] = 1 if (MapSim.height_at(p.x, p.y, gs) < wl or n == g) else 0
			if water[n] == 0:
				continue
			prev[n] = cur
			if n == g:
				found = true
				break
			queue.append(n)
	if not found:
		return {"ok": false, "path": PackedVector2Array()}
	var cells := PackedVector2Array()
	var k := g
	while true:
		cells.append(Vector2(lo.x + (k % nx) * cell, lo.y + (k / nx) * cell))
		if k == s:
			break
		k = prev[k]
	cells.reverse()
	cells[0] = a
	cells[cells.size() - 1] = b
	return {"ok": true, "path": _simplify(cells)}


## Quita puntos intermedios alineados (camino más liviano para dibujar).
static func _simplify(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.size() <= 2:
		return pts
	var out := PackedVector2Array([pts[0]])
	for i in range(1, pts.size() - 1):
		var d1 := (pts[i] - out[out.size() - 1]).normalized()
		var d2 := (pts[i + 1] - pts[i]).normalized()
		if d1.dot(d2) < 0.999:
			out.append(pts[i])
	out.append(pts[pts.size() - 1])
	return out


## ¿Están dos puertos (o puntos de puerto) unidos por agua navegable?
static func ports_connected(gs, port_a: int, port_b: int) -> bool:
	if port_a == port_b:
		return true
	var a: Dictionary = gs.get_building(port_a)
	var b: Dictionary = gs.get_building(port_b)
	if a.is_empty() or b.is_empty():
		return false
	return bool(water_route(gs, dock_point(gs, a), dock_point(gs, b))["ok"])


## Camino por el agua entre dos edificios con muelle (puerto o astillero): muelle → agua → muelle.
static func water_path(gs, a: Dictionary, b: Dictionary) -> PackedVector2Array:
	var da := dock_point(gs, a)
	var db := dock_point(gs, b)
	var r := water_route(gs, da, db)
	if not bool(r["ok"]):
		return PackedVector2Array([_pos(a), _pos(b)])
	var out := PackedVector2Array([_pos(a)])
	out.append_array(r["path"])
	out.append(_pos(b))
	return out


# --- Barcos -----------------------------------------------------------------------------------------

static func is_ship_mode(mode: String) -> bool:
	return bool(LogisticsSim.mode_def(mode).get("water", false))


static func ship_modes() -> Array:
	return GameData.sorted_ids(LogisticsSim.modes()).filter(func(m): return is_ship_mode(str(m)))


static func shipyards(gs) -> Array:
	var out := []
	for b in LogisticsSim.stations(gs):
		if str(b.get("type", "")) == "astillero":
			out.append(b)
	return out


## ¿El astillero puede llevar sus barcos al puerto? (mismo cuerpo de agua).
static func shipyard_serves(gs, yard: Dictionary, port_id: int) -> bool:
	var p: Dictionary = gs.get_building(port_id)
	if p.is_empty():
		return false
	return bool(water_route(gs, dock_point(gs, yard), dock_point(gs, p))["ok"])


# --- Viajes internacionales (barco propio o naviera) ------------------------------------------------

static func icfg() -> Dictionary:
	return cfg().get("ship_intl", {})


## Días de viaje entre países: km / (km por día del barco); la naviera usa vapor (o vela antes de la Máquina de vapor).
static func voyage_days(gs, km: float, mode: String) -> int:
	var kmd := float(LogisticsSim.mode_def(mode).get("km_day", 0.0))
	if kmd <= 0.0:
		kmd = 520.0 if gs.has_tech("maquina_vapor") else 170.0
	return maxi(int(icfg().get("min_days", 3)), int(ceil(km / kmd)))


static func naviera_unit_fee(gs, km: float) -> float:
	var c: Dictionary = icfg().get("commercial", {})
	return snappedf((float(c.get("per_unit_base", 0.15)) + float(c.get("per_unit_per_1000km", 0.18)) * km / 1000.0) * AirSim._home_pm(gs), 0.01)


## Próxima salida de la naviera con espacio: {day, free}.
static func naviera_slot(gs, from_iso: String, to_iso: String) -> Dictionary:
	var c: Dictionary = icfg().get("commercial", {})
	var every := maxi(1, int(c.get("every_days", 7)))
	var cap := float(c.get("capacity", 600))
	var dep := int(ceil(float(gs.today()) / every)) * every
	for i in range(6):
		var used := float(AirSim.st(gs)["commercial"].get("sea|%s|%s|%d" % [from_iso, to_iso, dep], 0.0))
		if used < cap - 0.01:
			return {"day": dep, "free": cap - used}
		dep += every
	return {"day": dep, "free": 0.0}


static func ship_fuel(gs, km: float, mode: String) -> float:
	var md := LogisticsSim.mode_def(mode)
	if float(md.get("fuel_per_km", 0.0)) <= 0.0:
		return 0.0   # A vela: sin combustible.
	var size := float(md.get("capacity", 500.0)) / 500.0
	return snappedf(km * float(icfg().get("fuel_per_km", 0.08)) * size * float(GameData.extra("trade").get("fuel_price", 1.0)) * AirSim._home_pm(gs), 0.01)


## Envía carga en barco a otro país. opts: from_iso, from, to_iso, to, good, qty, mode ("barco" propio |
## "naviera"), vehicle (id de barco o -1 = cualquiera libre), route. Devuelve {"error"} o {"flight"}.
static func ship_intl(gs, opts: Dictionary) -> Dictionary:
	var from_iso := str(opts.get("from_iso", CountriesSim.current_id()))
	var to_iso := str(opts.get("to_iso", from_iso))
	var from_id := int(opts.get("from", 0))
	var to_id := int(opts.get("to", 0))
	var good := str(opts.get("good", ""))
	var qty := float(opts.get("qty", 0.0))
	var mode := str(opts.get("mode", "barco"))
	var vid := int(opts.get("vehicle", -1))
	if from_iso == to_iso:
		return {"error": "Dentro del país el barco usa una ruta entre puertos (panel Rutas)"}
	if not ["barco", "naviera"].has(mode):
		return {"error": "Medio desconocido"}
	for iso in [from_iso, to_iso]:
		if not CountriesSim.has_presence(gs, iso):
			return {"error": "No tienes presencia en %s" % CountriesSim.country_label(iso)}
	if not CountriesSim.can_control(gs, from_iso):
		return {"error": "Sin gerente en %s: nadie despacha la carga" % CountriesSim.country_label(from_iso)}
	if not LogisticsSim.transportable_goods().has(good):
		return {"error": "Elige un bien para transportar"}
	if qty <= 0.0:
		return {"error": "La cantidad debe ser mayor que cero"}
	var tech := str(icfg().get("tech", "navegacion"))
	if not gs.has_tech(tech):
		return {"error": "Requiere investigar: %s" % GameData.tech_label(tech)}
	var km := TravelSim.distance_km(from_iso, to_iso)
	var chk = CountriesSim.with_country(gs, from_iso, func() -> Dictionary:
		var port := port_of(gs, from_id)
		if port < 0:
			return {"error": "El origen debe ser un puerto tuyo o un almacén al lado de un puerto"}
		if port_water(gs, port) != "mar":
			return {"error": "Para ir a otro país el puerto de origen debe estar en la costa del mar"}
		var out := {"stock": LogisticsSim.endpoint_stock(gs, from_id, good), "port": port}
		if mode == "barco":
			var now := float(gs.today()) + TimeManager.hour_float() / 24.0
			var why := "No hay barcos de altura libres con tripulación en %s (compra un velero, vapor, carguero o portacontenedores en un astillero)" % CountriesSim.country_label(from_iso)
			for v in LogisticsSim.vehicles(gs):
				var m := str(v.get("mode", ""))
				if not is_ship_mode(m) or not bool(LogisticsSim.mode_def(m).get("intl", false)) or (vid >= 0 and int(v["id"]) != vid) or not VehicleCatalog.can_carry(m, good):
					continue
				var y: Dictionary = gs.get_building(int(v["base"]))
				if y.is_empty() or not gs.is_active(y):
					continue
				if not FleetSim.base_linked(gs, y, m):
					why = FleetSim.base_reason(gs, y, m)
					continue
				if LogisticsSim.crew_size(gs, y) < LogisticsSim.crew_per(m):
					why = "Contrata tripulación en %s (%d por barco)" % [gs.building_label(y), LogisticsSim.crew_per(m)]
					continue
				if not shipyard_serves(gs, y, port):
					why = "%s no está unido por agua con el puerto de origen" % gs.building_label(y)
					continue
				if LogisticsSim.vehicle_busy(gs, int(v["id"]), now):
					continue
				out["vehicle"] = int(v["id"])
				out["ship_mode"] = m
				out["cap"] = LogisticsSim.vehicle_capacity(gs, v, good)   # Especialidad: petrolero, granelero, frigorífico.
				return out
			return {"error": why}
		return out)
	if chk == null or (chk as Dictionary).has("error"):
		return {"error": str((chk as Dictionary).get("error", "Origen inválido")) if chk != null else "Origen inválido"}
	var chk_to = CountriesSim.with_country(gs, to_iso, func() -> String:
		var port := port_of(gs, to_id)
		if port < 0:
			return "El destino debe ser un puerto tuyo o un almacén al lado de un puerto en %s" % CountriesSim.country_label(to_iso)
		if port_water(gs, port) != "mar":
			return "El puerto de destino debe estar en la costa del mar"
		return "")
	if str(chk_to) != "":
		return {"error": str(chk_to)}
	qty = minf(qty, float(chk["stock"]))
	if qty <= 0.01:
		return {"error": "Sin %s en el origen" % GameData.good_label(good).to_lower()}
	var fee := 0.0
	var fuel := 0.0
	var depart_day: int = gs.today()
	var days := 0
	var smode := "vapor_barco"
	if mode == "barco":
		vid = int(chk["vehicle"])
		smode = str(chk["ship_mode"])
		qty = minf(qty, float(chk["cap"]))
		days = voyage_days(gs, km, smode)
		fuel = ship_fuel(gs, km * 2.0, smode)   # ida y vuelta (regresa vacío)
		if gs.money < fuel:
			return {"error": "Dinero insuficiente para el combustible (%s)" % Fmt.money(fuel)}
	else:
		var slot := naviera_slot(gs, from_iso, to_iso)
		if float(slot["free"]) <= 0.0:
			return {"error": "Los barcos de la naviera en esa ruta están llenos"}
		qty = minf(qty, float(slot["free"]))
		depart_day = int(slot["day"])
		days = voyage_days(gs, km, "")
		var unit := naviera_unit_fee(gs, km)
		fee = snappedf(unit * qty, 0.01)
		if gs.money < fee:
			qty = floorf(maxf(0.0, gs.money) / maxf(0.01, unit))
			fee = snappedf(unit * qty, 0.01)
			if qty <= 0.0:
				return {"error": "Dinero insuficiente para el flete (%s por unidad)" % Fmt.money2(unit)}
	var taken_val = CountriesSim.with_country(gs, from_iso, func() -> Array:
		var t := LogisticsSim.endpoint_take(gs, from_id, good, qty)
		var val := t * EconomySim.market_price(gs, good)
		if mode == "barco":
			var v := LogisticsSim.get_vehicle(gs, vid)
			var y: Dictionary = gs.get_building(int(v.get("base", -1)))
			if fuel > 0.0:
				if not y.is_empty():
					BusinessSim.pay(gs, y, fuel, "insumos")
				else:
					gs.add_money(-fuel)
			v["km"] = float(v.get("km", 0.0)) + km * 2.0
			v["trips"] = int(v.get("trips", 0)) + 1
			v["air_busy_until"] = float(gs.today()) + 2.0 * days
		return [t, val])
	var taken := float(taken_val[0])
	if fee > 0.0:
		gs.add_money(-fee)
		var ck := "sea|%s|%s|%d" % [from_iso, to_iso, depart_day]
		AirSim.st(gs)["commercial"][ck] = float(AirSim.st(gs)["commercial"].get(ck, 0.0)) + taken
	CountriesSim.add_outflow(gs, fee + fuel)
	var a := AirSim.st(gs)
	var id := int(a["next_id"])
	a["next_id"] = id + 1
	var f := {"id": id, "mode": mode, "ship": true, "ship_mode": smode, "from_iso": from_iso, "from": from_id, "to_iso": to_iso, "to": to_id,
			"good": good, "qty": taken, "depart": depart_day, "arrive": depart_day + days, "vehicle": vid, "fee": fee, "fuel": fuel,
			"km": snappedf(km, 0.1), "value_origin": float(taken_val[1]), "delivered": false,
			"status": "navegando" if depart_day <= gs.today() else "esperando zarpe", "route": int(opts.get("route", -1))}
	a["flights"].append(f)
	a["stats"]["fees"] = float(a["stats"]["fees"]) + fee
	a["stats"]["fuel"] = float(a["stats"]["fuel"]) + fuel
	gs.notify("Carga marítima %s: %s %s de %s a %s (%s, llega en %d días)." % ["en barco propio" if mode == "barco" else "con naviera",
			AirSim._num(taken), GameData.good_label(good).to_lower(), CountriesSim.country_label(from_iso), CountriesSim.country_label(to_iso),
			Fmt.money(fee + fuel), depart_day + days - gs.today()], "negocio")
	return {"flight": f}


## Viajes internacionales en barco que salen o llegan al país cargado: [{flight, t, port, outgoing}].
static func voyages_here(gs) -> Array:
	var out := []
	var here := CountriesSim.current_id() if CountriesSim.ready(gs) else ""
	for f in AirSim.st(gs).get("flights", []):
		if not bool(f.get("ship", false)) or bool(f.get("delivered", false)):
			continue
		var tot := maxf(1.0, float(int(f["arrive"]) - int(f["depart"])))
		var t := clampf((float(gs.today()) + TimeManager.hour_float() / 24.0 - float(f["depart"])) / tot, 0.0, 1.0)
		if str(f["from_iso"]) == here:
			out.append({"flight": f, "t": t, "port": port_of(gs, int(f["from"])), "outgoing": true})
		elif str(f["to_iso"]) == here:
			out.append({"flight": f, "t": t, "port": port_of(gs, int(f["to"])), "outgoing": false})
	return out
