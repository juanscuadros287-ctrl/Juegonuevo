class_name FleetSim
extends RefCounted
## Compra central de vehículos (panel «Vehículos», docs/RUTAS_BARCOS.md).
## - El jugador compra en UN solo panel y elige a qué COMPAÑÍA (negocio suyo) se asigna el vehículo: ese es
##   su parqueadero, su punto de salida y de regreso. El vehículo aparece ahí (v["base"]).
## - Si la compañía no puede recibirlo, se marca el error y NO se cobra:
##     animales            → la compañía en tierra firme
##     carretas y camiones → la compañía toca una carretera
##     trenes              → la compañía toca una vía férrea
##     barcos              → la compañía es un puerto o un astillero (necesitan agua)
##     aviones             → la compañía es un aeropuerto o un hangar (necesitan pista)
##   o si llegó a su cupo del tipo (módulo «Flota»).
## - Cupos: `fleet_limit(gs, b, tipo)` consume `ModulesSim.fleet_limit(gs, b, tipo)` y `ModulesSim.fleet_types(gs, b)`
##   si existen (módulo Flota del negocio, otro sistema); si no, un cupo por defecto según el nivel del negocio
##   (rutas.json default_fleet.per_level × nivel) y, en las bases de flota viejas, su "garage".
## - A pie (flota nivel 1): no se compra nada; se abre la vacante de cargador (HiringSim) en la central.
## - Cada vehículo abre su vacante de conductor, arriero, jinete o tripulación (HiringSim.on_vehicle_bought).
## - Bases de flota (caballeriza, depósito de camiones, cochera de tren, astillero, hangar): ya no son
##   obligatorias; si el vehículo queda en la base de su tipo, su mantenimiento es 25 % más barato.
## - Partidas viejas: los vehículos siguen en su base; si su base ya no existe, se reasignan a la compañía
##   más cercana que pueda recibirlos (o se venden al 40 % si no hay ninguna).

static var _modules_script = null
static var _modules_checked := false


static func rcfg() -> Dictionary:
	return GameData.extra("rutas")


# --- Contrato con ModulesSim (módulo «Flota») ------------------------------------------------------

static func _modules():
	if not _modules_checked:
		_modules_checked = true
		for c in ProjectSettings.get_global_class_list():
			if str(c.get("class", "")) == "ModulesSim":
				_modules_script = load(str(c["path"]))
	return _modules_script


static func _has_static(script, fname: String) -> bool:
	if script == null:
		return false
	for m in (script as Script).get_script_method_list():
		if str(m.get("name", "")) == fname:
			return true
	return false


## Cupo de vehículos de un tipo en una compañía.
static func fleet_limit(gs, b: Dictionary, tipo: String) -> int:
	var M = _modules()
	if _has_static(M, "fleet_limit"):
		return int(M.call("fleet_limit", gs, b, tipo))
	var garage := int(gs.level_def(b).get("garage", 0))
	if garage > 0 and is_base_for(b, tipo):
		return garage
	var per := int(rcfg().get("default_fleet", {}).get("per_level", {}).get(tipo, 1))
	return per * maxi(1, int(b.get("level", 1)))


## Tipos de vehículo que admite la compañía.
static func fleet_types(gs, b: Dictionary) -> Array:
	var M = _modules()
	if _has_static(M, "fleet_types"):
		var r = M.call("fleet_types", gs, b)
		if r is Array:
			return r
	return VehicleCatalog.TIPOS.filter(func(t): return t != "pie")


## ¿Es este edificio la base de flota natural del tipo? (caballeriza, depósito, cochera, astillero, hangar)
static func is_base_for(b: Dictionary, tipo: String) -> bool:
	var t := str(b.get("type", ""))
	match tipo:
		"animal", "carreta":
			return t == "caballeriza"
		"camion":
			return t == "deposito_camiones"
		"tren":
			return t == "cochera_tren"
		"barco":
			return t == "astillero"
		"avion":
			return t == "hangar"
	return false


static func used(gs, b: Dictionary, tipo: String) -> int:
	var n := 0
	for v in LogisticsSim.vehicles_of(gs, int(b["id"])):
		if VehicleCatalog.tipo_of(str(v["mode"])) == tipo:
			n += 1
	return n


# --- ¿Puede la compañía recibir el vehículo? --------------------------------------------------------

static func _pos(b: Dictionary) -> Vector2:
	return Vector2(float(b.get("x", 0.0)), float(b.get("z", 0.0)))


## Motivo de red: la compañía no toca lo que exige el vehículo ("" si sí).
static func network_reason(gs, b: Dictionary, mode: String) -> String:
	var p := _pos(b)
	var half: float = gs.footprint_of(b) * 0.5
	var gcfg: Dictionary = rcfg().get("garage", {})
	var label: String = gs.building_label(b)
	match VehicleCatalog.tipo_of(mode):
		"pie", "animal":
			return "" if not ShipSim.is_water(gs, p) else "%s está en el agua" % label
		"carreta", "camion":
			var reach := half + float(gcfg.get("road_reach", 6.0))
			for r in RoadSim.roads(gs):
				if RoadSim.dist_point_segment(p, RoadSim.seg_a(r), RoadSim.seg_b(r)) <= reach:
					return ""
			return "%s no toca una carretera: los %s necesitan salir por carretera" % [label, LogisticsSim.mode_short(mode)]
		"tren":
			var q := RailSim.nearest_point(gs, p)
			if q != Vector2.INF and p.distance_to(q) <= half + float(gcfg.get("rail_reach", 6.0)):
				return ""
			return "%s no toca una vía férrea: los trenes necesitan rieles (traza una vía hasta ahí)" % label
		"barco":
			if str(b.get("type", "")) in ["puerto", "astillero"] and ShipSim.dock_point(gs, b) != Vector2.INF:
				return ""
			return "Los barcos necesitan agua: asígnalos a un puerto o un astillero tuyo"
		"avion":
			if str(b.get("type", "")) in ["aeropuerto", "hangar"]:
				return ""
			return "Los aviones necesitan pista: asígnalos a un aeropuerto o un hangar tuyo"
	return ""


## ¿Sigue conectado el vehículo a su red desde su compañía? (partidas viejas: conexión provisional)
static func base_linked(gs, b: Dictionary, mode: String) -> bool:
	if b.is_empty():
		return false
	if bool(b.get("conn_legacy", false)) or str(b.get("type", "")) == "central_transporte":
		return true
	return network_reason(gs, b, mode) == ""


static func base_reason(gs, b: Dictionary, mode: String) -> String:
	if base_linked(gs, b, mode):
		return ""
	return network_reason(gs, b, mode)


static func is_company(gs, b: Dictionary) -> bool:
	return not b.is_empty() and gs.owned_by_player(b) and (BusinessSim.is_business(b) or GarageSim.is_garage(b))


## Motivo por el que no se puede comprar ese modelo para esa compañía ("" si se puede). No cobra nada.
static func buy_block_reason(gs, b: Dictionary, mode: String, comp: Dictionary = {}) -> String:
	var md := LogisticsSim.mode_def(mode)
	if md.is_empty():
		return "Modelo desconocido"
	if not bool(md.get("vehicle", false)):
		return "A pie no se compra nada: abre la vacante de cargador en la central de transporte"
	if not gs.has_tech(str(md.get("tech", ""))):
		return "Requiere investigar: %s" % GameData.tech_label(str(md.get("tech", "")))
	if not is_company(gs, b):
		return "Elige una compañía tuya"
	if str(b.get("status", "")) != "activo":
		return "%s no está activa" % gs.building_label(b)
	var tipo := VehicleCatalog.tipo_of(mode)
	if not fleet_types(gs, b).has(tipo):
		return "%s no admite %s (módulo Flota)" % [gs.building_label(b), VehicleCatalog.tipo_label(tipo).to_lower()]
	var net := network_reason(gs, b, mode)
	if net != "":
		return net
	var lim := fleet_limit(gs, b, tipo)
	if used(gs, b, tipo) >= lim:
		return "No caben más vehículos (%d): %s llegó a su cupo de %s" % [lim, gs.building_label(b), VehicleCatalog.tipo_label(tipo).to_lower()]
	if VehicleCatalog.is_train(mode) and VehicleCatalog.comp_wagons(comp) > int(md.get("max_wagons", 10)):
		return "Máximo %d vagones para esa locomotora" % int(md.get("max_wagons", 10))
	var price := total_price(gs, mode, comp)
	if gs.money < price:
		return "Dinero insuficiente (%s)" % Fmt.money(price)
	return ""


static func total_price(gs, mode: String, comp: Dictionary = {}) -> float:
	var p: float = float(LogisticsSim.mode_def(mode).get("price", 0.0)) * gs.price_mult()
	if VehicleCatalog.is_train(mode):
		p += VehicleCatalog.comp_price(gs, comp if not comp.is_empty() else VehicleCatalog.default_comp())
	return p


## Compra un vehículo y lo asigna a la compañía (aparece ahí). Devuelve {"vehicle"} o {"error"} (sin cobrar).
static func buy(gs, b: Dictionary, mode: String, comp: Dictionary = {}) -> Dictionary:
	if VehicleCatalog.is_train(mode) and comp.is_empty():
		comp = VehicleCatalog.default_comp()
	var why := buy_block_reason(gs, b, mode, comp)
	if why != "":
		return {"error": why}
	BusinessSim.pay(gs, b, total_price(gs, mode, comp), "obras")
	var id := int(gs.logistics.get("next_vehicle_id", 1))
	gs.logistics["next_vehicle_id"] = id + 1
	var n := 0
	for v in LogisticsSim.vehicles(gs):
		if str(v["mode"]) == mode:
			n += 1
	var v := {"id": id, "mode": mode, "base": int(b["id"]), "name": "%s %d" % [str(LogisticsSim.mode_def(mode).get("unit", LogisticsSim.mode_label(mode))), n + 1],
		"bought": gs.today(), "km": 0.0, "trips": 0}
	if VehicleCatalog.is_train(mode):
		v["comp"] = comp.duplicate()
	LogisticsSim.vehicles(gs).append(v)
	HiringSim.on_vehicle_bought(gs, b, v)   # Contrataciones: vacante de conductor, arriero o tripulación.
	return {"vehicle": v}


static func sell(gs, vid: int) -> String:
	return LogisticsSim.sell_vehicle(gs, vid)


## A pie: no se compra nada, se abre la vacante de cargador en la compañía (central de transporte).
static func open_porter(gs, b: Dictionary) -> String:
	if b.is_empty() or not gs.owned_by_player(b):
		return "Elige una central de transporte tuya"
	if HiringSim.open_slots(gs, b) <= 0:
		return "%s no tiene puestos libres" % gs.building_label(b)
	HiringSim.ensure_vacancy(gs, b)
	HiringSim.publish(gs, b, true)
	return ""


## Compañías posibles para un modelo: [{id, label, reason, used, limit}].
static func companies(gs, mode: String) -> Array:
	var out := []
	var tipo := VehicleCatalog.tipo_of(mode)
	for b in gs.buildings:
		if not is_company(gs, b) or str(b.get("status", "")) != "activo":
			continue
		out.append({"id": int(b["id"]), "label": gs.building_label(b), "reason": buy_block_reason(gs, b, mode) if gs.money >= 0 else "",
				"used": used(gs, b, tipo), "limit": fleet_limit(gs, b, tipo)})
	out.sort_custom(func(a, c): return str(a["reason"]) == "" and str(c["reason"]) != "")
	return out


# --- Vagones ------------------------------------------------------------------------------------------

static func add_wagons_block_reason(gs, vid: int, wt: String, n := 1) -> String:
	var v := LogisticsSim.get_vehicle(gs, vid)
	if v.is_empty():
		return "Ese tren no existe"
	if not VehicleCatalog.is_train(str(v["mode"])):
		return "Solo los trenes llevan vagones"
	if not VehicleCatalog.wagon_types().has(wt):
		return "Tipo de vagón desconocido"
	var md := LogisticsSim.mode_def(str(v["mode"]))
	if VehicleCatalog.comp_wagons(VehicleCatalog.comp_of(v)) + n > int(md.get("max_wagons", 10)):
		return "Máximo %d vagones para esa locomotora" % int(md.get("max_wagons", 10))
	var price := VehicleCatalog.comp_price(gs, {wt: n})
	if gs.money < price:
		return "Dinero insuficiente (%s)" % Fmt.money(price)
	return ""


static func add_wagons(gs, vid: int, wt: String, n := 1) -> String:
	var why := add_wagons_block_reason(gs, vid, wt, n)
	if why != "":
		return why
	var v := LogisticsSim.get_vehicle(gs, vid)
	var st: Dictionary = gs.get_building(int(v["base"]))
	var price := VehicleCatalog.comp_price(gs, {wt: n})
	if st.is_empty():
		gs.add_money(-price)
	else:
		BusinessSim.pay(gs, st, price, "obras")
	var comp := VehicleCatalog.comp_of(v)
	comp[wt] = int(comp.get(wt, 0)) + n
	return ""


## Quita vagones (se venden al 40 %).
static func remove_wagons(gs, vid: int, wt: String, n := 1) -> String:
	var v := LogisticsSim.get_vehicle(gs, vid)
	if v.is_empty():
		return "Ese tren no existe"
	var comp := VehicleCatalog.comp_of(v)
	var k := mini(n, int(comp.get(wt, 0)))
	if k <= 0:
		return "No tiene vagones de ese tipo"
	comp[wt] = int(comp[wt]) - k
	if int(comp[wt]) <= 0:
		comp.erase(wt)
	gs.add_money(VehicleCatalog.comp_price(gs, {wt: k}) * 0.4)
	return ""


# --- Asignación a rutas -----------------------------------------------------------------------------

## Asigna el vehículo a una ruta de carga (o -1 = ninguna: sus rutas pasan a "cualquier vehículo libre").
static func assign(gs, vid: int, route_id: int) -> String:
	var v := LogisticsSim.get_vehicle(gs, vid)
	if v.is_empty():
		return "Ese vehículo no existe"
	for r in LogisticsSim.routes(gs):
		if int(r.get("vehicle", -1)) == vid and int(r["id"]) != route_id:
			r["vehicle"] = -1
	if route_id < 0:
		return ""
	var r := LogisticsSim.get_route(gs, route_id)
	if r.is_empty():
		return "Esa ruta no existe"
	if str(r["mode"]) != str(v["mode"]) and RouteSim.family(str(r["mode"])) != RouteSim.family(str(v["mode"])):
		return "Ese vehículo no sirve para esa ruta (%s)" % LogisticsSim.mode_label(str(r["mode"]))
	var why := LogisticsSim.route_block_reason(gs, int(r["from"]), int(r["to"]), str(v["mode"]), vid, r.get("stops", []))
	if why != "" and not why.begins_with("Contrata"):
		return why
	r["vehicle"] = vid
	r["mode"] = str(v["mode"])
	return ""


# --- Mantenimiento, bases y migración -----------------------------------------------------------------

## Descuento de mantenimiento si el vehículo está en la base de flota de su tipo.
static func upkeep_mult(gs, b: Dictionary, mode: String) -> float:
	return 1.0 - float(rcfg().get("fleet_base_discount", 0.25)) if is_base_for(b, VehicleCatalog.tipo_of(mode)) else 1.0


## Nueva compañía para los vehículos de `b` (al demolerla o si su base no existe). Devuelve cuántos se vendieron.
static func rehome_from(gs, b: Dictionary) -> int:
	var sold := 0
	var p := _pos(b)
	for v in LogisticsSim.vehicles_of(gs, int(b["id"])).duplicate():
		var best := {}
		var bd := INF
		for c in gs.buildings:
			if int(c["id"]) == int(b["id"]) or not is_company(gs, c) or str(c.get("status", "")) != "activo":
				continue
			if network_reason(gs, c, str(v["mode"])) != "":
				continue
			var d := p.distance_to(_pos(c))
			if d < bd:
				bd = d
				best = c
		if best.is_empty():
			var refund := LogisticsSim.vehicle_price(gs, str(v["mode"])) * 0.4
			LogisticsSim._drop_vehicle(gs, v)
			gs.add_money(refund)
			sold += 1
		else:
			v["base"] = int(best["id"])
			gs.notify("%s pasó a %s." % [str(v["name"]), gs.building_label(best)], "negocio")
	return sold


## Partidas anteriores: compañías con vehículos que no tocan su red reciben conexión provisional
## (b["conn_legacy"]) para que la partida siga igual. Devuelve cuántas.
static func grandfather(gs) -> int:
	migrate(gs)
	var n := 0
	for v in LogisticsSim.vehicles(gs):
		var b: Dictionary = gs.get_building(int(v.get("base", -1)))
		if not b.is_empty() and not bool(b.get("conn_legacy", false)) and network_reason(gs, b, str(v["mode"])) != "":
			b["conn_legacy"] = true
			n += 1
	return n


## Punto por donde sale el vehículo de su compañía (hacia la carretera, la vía, el agua o la pista).
static func exit_point(gs, b: Dictionary, mode: String) -> Vector2:
	var p := _pos(b)
	match VehicleCatalog.tipo_of(mode):
		"carreta", "camion":
			var best := p
			var bd := INF
			for r in RoadSim.roads(gs):
				var a := RoadSim.seg_a(r)
				var ab := RoadSim.seg_b(r) - a
				var q := a + ab * clampf((p - a).dot(ab) / maxf(0.0001, ab.length_squared()), 0.0, 1.0)
				if p.distance_to(q) < bd:
					bd = p.distance_to(q)
					best = q
			return best if bd < 40.0 else p
		"tren":
			var q := RailSim.nearest_point(gs, p)
			return q if q != Vector2.INF and p.distance_to(q) < 40.0 else p
		"barco":
			var d := ShipSim.dock_point(gs, b)
			return d if d != Vector2.INF else p
	return p + Vector2(0, gs.footprint_of(b) * 0.5 + 1.0)


## Migración: vehículos cuya base ya no existe → compañía más cercana; trenes con vagones sin tipo.
static func migrate(gs) -> void:
	for v in LogisticsSim.vehicles(gs).duplicate():
		if VehicleCatalog.is_train(str(v.get("mode", ""))):
			VehicleCatalog.comp_of(v)
		var b: Dictionary = gs.get_building(int(v.get("base", -1)))
		if b.is_empty():
			rehome_from(gs, {"id": int(v.get("base", -1)), "x": 0.0, "z": 0.0})
