class_name TradeSim
extends RefCounted
## Fase 7 — otros pueblos, rutas comerciales pagadas por pueblo, exportación/importación, inmigración y evolución del transporte.
## Estado en GameState.trade (se guarda automáticamente):
##   towns:        Array de pueblos {id, name, archetype, distance, population, produces, demands, water, goods{g:{...}}, event}
##   connections:  Array de rutas activas {town_id, town_name, distance, road, rail, mode, opened_day, exported, imported, work}
##   projects:     Array de rutas en construcción {town_id, done_day, total_days, cost}
##   shipments:    envíos en camino {id, town_id, good, qty, kind ("vender"/"comprar"), value, arrive_day, mode}
##   contracts:    contratos automáticos {id, town_id, good, kind, qty, every, next_day, limit, active, fails}
##   month / last_month / totals: estadísticas (exportaciones, importaciones, fletes, inmigrantes)
## Parámetros en data/trade.json. Toda la plata entra/sale con gs.add_money (economía cerrada).

const KIND_SELL := "vender"
const KIND_BUY := "comprar"


static func cfg() -> Dictionary:
	return GameData.extra("trade")


# --- Estado ---------------------------------------------------------------------------

static func init_state(gs) -> void:
	for key in ["towns", "connections", "projects", "shipments", "contracts"]:
		if not gs.trade.has(key):
			gs.trade[key] = []
	for key in ["month", "last_month", "totals"]:
		if not gs.trade.has(key):
			gs.trade[key] = {}
	if not gs.trade.has("next_id"):
		gs.trade["next_id"] = 1
	if gs.trade["towns"].is_empty() and not gs.settings.is_empty():
		generate_towns(gs)


## Generador propio (no altera la secuencia aleatoria del resto de la simulación).
static func _rng(gs) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = int(gs.settings.get("seed", 0)) * 7919 + 104729
	if gs.trade.has("rng_state"):
		r.state = int(str(gs.trade["rng_state"]))
	return r


static func _save_rng(gs, r: RandomNumberGenerator) -> void:
	gs.trade["rng_state"] = str(r.state)


static func _next_id(gs) -> int:
	var n := int(gs.trade.get("next_id", 1))
	gs.trade["next_id"] = n + 1
	return n


static func _rand_range(r: RandomNumberGenerator, arr: Array) -> float:
	if arr.size() < 2:
		return float(arr[0]) if arr.size() == 1 else 1.0
	return r.randf_range(float(arr[0]), float(arr[1]))


# --- Pueblos ---------------------------------------------------------------------------

static func generate_towns(gs) -> void:
	var r := _rng(gs)
	var tc: Dictionary = cfg().get("towns", {})
	var archetypes: Dictionary = cfg().get("archetypes", {})
	var count_range: Array = tc.get("count", [4, 6])
	var count := r.randi_range(int(count_range[0]), int(count_range[1]))
	var names: Array = tc.get("names", ["Otro pueblo"]).duplicate()
	names.erase(str(gs.settings.get("town_name", "")))
	var order: Array = tc.get("required_archetypes", []).duplicate()
	var others: Array = archetypes.keys().filter(func(k): return not str(k).begins_with("_"))
	while order.size() < count:
		order.append(others[r.randi() % others.size()])
	var map_type := str(gs.settings.get("map_type", "interior"))
	var watery := map_type in ["costa", "rio"]
	var towns: Array = []
	for i in range(count):
		var arch_id := str(order[i])
		var arch: Dictionary = archetypes.get(arch_id, {})
		var name_idx := r.randi() % maxi(1, names.size())
		var tname := str(names[name_idx]) if not names.is_empty() else "Pueblo %d" % (i + 1)
		if not names.is_empty():
			names.remove_at(name_idx)
		var produces: Array = arch.get("produces", []).duplicate()
		var rare: Dictionary = arch.get("rare", {})
		for g in rare:
			if r.randf() < float(rare[g]) and not produces.has(g):
				produces.append(g)
		var demands: Array = arch.get("demands", []).duplicate()
		var pop_range: Array = tc.get("population", [250, 2600])
		var pop := int(r.randf_range(float(pop_range[0]), float(pop_range[1])))
		if arch_id == "ciudad":
			pop = int(pop * 1.8)
		var town := {
			"id": "t%d" % (i + 1),
			"name": tname,
			"archetype": arch_id,
			"distance": roundf(_rand_range(r, tc.get("distance_km", [35, 150]))),
			"population": pop,
			"produces": produces,
			"demands": demands,
			"water": watery and (bool(arch.get("water", false)) or r.randf() < float(tc.get("water_chance", 0.5))),
			"goods": {},
			"event": {},
		}
		_init_town_goods(town, r)
		towns.append(town)
	# El pueblo más cercano primero.
	towns.sort_custom(func(a, b): return float(a["distance"]) < float(b["distance"]))
	gs.trade["towns"] = towns
	_save_rng(gs, r)


static func _init_town_goods(town: Dictionary, r: RandomNumberGenerator) -> void:
	var pc: Dictionary = cfg().get("prices", {})
	var pop := float(town["population"])
	var goods := {}
	for g in trade_goods():
		var row := {"fluct": 1.0, "sat": 0.0, "scar": 0.0, "sells": false}
		if town["produces"].has(g):
			row["sells"] = true
			row["sell_mult"] = _rand_range(r, pc.get("produced_sell", [0.75, 0.95]))
			row["buy_mult"] = _rand_range(r, pc.get("produced_buy", [0.45, 0.6]))
			row["demand"] = pop * float(pc.get("other_demand_per_pop", 0.02))
			row["supply"] = pop * float(pc.get("supply_per_pop", 0.08))
		elif town["demands"].has(g):
			row["buy_mult"] = _rand_range(r, pc.get("demanded_buy", [1.25, 1.6]))
			row["demand"] = pop * float(pc.get("demand_per_pop", 0.06))
		else:
			row["buy_mult"] = _rand_range(r, pc.get("other_buy", [0.75, 0.95]))
			row["demand"] = pop * float(pc.get("other_demand_per_pop", 0.02))
		goods[g] = row
	town["goods"] = goods


static func towns(gs) -> Array:
	return gs.trade.get("towns", [])


static func town(gs, town_id: String) -> Dictionary:
	for t in towns(gs):
		if str(t["id"]) == town_id:
			return t
	return {}


static func trade_goods() -> Array:
	return cfg().get("goods", {}).keys().filter(func(k): return not str(k).begins_with("_"))


static func good_label(good: String) -> String:
	if GameData.goods.has(good):
		return GameData.good_label(good)
	return str(cfg().get("goods", {}).get(good, {}).get("label", good))


static func base_price(good: String) -> float:
	var g: Dictionary = cfg().get("goods", {}).get(good, {})
	if g.has("base"):
		return float(g["base"])
	return float(GameData.goods.get(good, {}).get("base_price", 1.0))


static func archetype_label(t: Dictionary) -> String:
	return str(cfg().get("archetypes", {}).get(str(t.get("archetype", "")), {}).get("label", ""))


# --- Conexiones -------------------------------------------------------------------------

## Pueblos conectados por ruta comercial: Array de Dictionary {"town_id", ...}.
## Contrato para otras fases: gs.trade["connections"] (solo rutas terminadas).
static func connected_towns(gs) -> Array:
	return gs.trade.get("connections", [])


static func is_connected_any(gs) -> bool:
	return not connected_towns(gs).is_empty()


static func connection(gs, town_id: String) -> Dictionary:
	for c in connected_towns(gs):
		if str(c["town_id"]) == town_id:
			return c
	return {}


static func project(gs, town_id: String) -> Dictionary:
	for p in gs.trade.get("projects", []):
		if str(p["town_id"]) == town_id:
			return p
	return {}


static func road_def(level: int) -> Dictionary:
	var roads: Array = cfg().get("roads", [])
	if roads.is_empty():
		return {}
	return roads[clampi(level, 0, roads.size() - 1)]


static func max_road_level() -> int:
	return cfg().get("roads", []).size() - 1


static func road_label(level: int) -> String:
	return str(road_def(level).get("label", "Camino"))


## Costo de abrir la ruta: acuerdo (derecho de paso) + camino de barro según la distancia.
static func connection_cost(gs, town_id: String) -> Dictionary:
	var t := town(gs, town_id)
	var cc: Dictionary = cfg().get("connection", {})
	var dist := float(t.get("distance", 50.0))
	var pm: float = gs.price_mult()
	var road := road_def(1)
	var agreement := (float(cc.get("agreement_base", 400)) + float(cc.get("agreement_per_km", 4)) * dist) * pm
	var road_cost := float(road.get("cost_per_km", 15)) * dist * pm
	var days := maxi(int(cc.get("min_days", 10)), int(ceilf(dist * float(road.get("days_per_km", 0.35)))))
	return {"agreement": agreement, "road": road_cost, "total": agreement + road_cost, "days": days}


static func open_block_reason(gs, town_id: String) -> String:
	if town(gs, town_id).is_empty():
		return "Ese pueblo no existe."
	if not connection(gs, town_id).is_empty():
		return "Ya tienes ruta con este pueblo."
	if not project(gs, town_id).is_empty():
		return "El camino ya está en construcción."
	var cost: float = float(connection_cost(gs, town_id)["total"])
	if gs.money < cost:
		return "Necesitas %s para el acuerdo y el camino." % Fmt.money(cost)
	return ""


## Paga el acuerdo y empieza a construir el camino de barro. Devuelve "" si todo salió bien.
static func open_route(gs, town_id: String) -> String:
	var why := open_block_reason(gs, town_id)
	if why != "":
		return why
	var q := connection_cost(gs, town_id)
	var t := town(gs, town_id)
	gs.add_money(-float(q["total"]))
	gs.add_counter("trade_investment", float(q["total"]))
	_stat(gs, "investment", float(q["total"]))
	gs.trade["projects"].append({"town_id": town_id, "start_day": gs.today(), "done_day": gs.today() + int(q["days"]),
		"total_days": int(q["days"]), "cost": float(q["total"])})
	gs.notify("Acuerdo firmado con %s. El camino estará listo en %d días." % [t["name"], int(q["days"])], "construccion")
	return ""


static func _complete_project(gs, p: Dictionary) -> void:
	var t := town(gs, str(p["town_id"]))
	var conn := {
		"town_id": str(p["town_id"]),
		"town_name": str(t.get("name", "")),
		"distance": float(t.get("distance", 50.0)),
		"road": 1,
		"rail": false,
		"mode": "a_pie",
		"opened_day": gs.today(),
		"exported": 0.0,
		"imported": 0.0,
		"immigrants": 0,
		"work": {},
	}
	gs.trade["connections"].append(conn)
	conn["mode"] = cheapest_mode(gs, str(p["town_id"]))
	gs.notify("¡Ruta comercial abierta con %s! Ya puedes comerciar y llegará gente por el camino." % t.get("name", ""), "importante")


## Mejora del camino (barro → empedrado → carretera de cemento). Sigue en uso durante la obra.
static func road_upgrade_quote(gs, town_id: String) -> Dictionary:
	var c := connection(gs, town_id)
	if c.is_empty():
		return {}
	var next := int(c.get("road", 1)) + 1
	if next > max_road_level():
		return {}
	var rd := road_def(next)
	var dist := float(c.get("distance", 50.0))
	return {"level": next, "label": str(rd.get("label", "")), "tech": str(rd.get("tech", "")),
		"cost": float(rd.get("cost_per_km", 30)) * dist * gs.price_mult(),
		"days": maxi(7, int(ceilf(dist * float(rd.get("days_per_km", 0.4)))))}


static func road_upgrade_block_reason(gs, town_id: String) -> String:
	var c := connection(gs, town_id)
	if c.is_empty():
		return "Primero abre la ruta."
	if c.get("work", {}).has("road"):
		return "Ya hay una obra en el camino."
	var q := road_upgrade_quote(gs, town_id)
	if q.is_empty():
		return "El camino ya está al máximo."
	if not gs.has_tech(str(q["tech"])):
		return "Requiere investigar %s." % GameData.tech_label(str(q["tech"]))
	if gs.money < float(q["cost"]):
		return "Necesitas %s." % Fmt.money(float(q["cost"]))
	return ""


static func upgrade_road(gs, town_id: String) -> String:
	var why := road_upgrade_block_reason(gs, town_id)
	if why != "":
		return why
	var c := connection(gs, town_id)
	var q := road_upgrade_quote(gs, town_id)
	gs.add_money(-float(q["cost"]))
	gs.add_counter("trade_investment", float(q["cost"]))
	_stat(gs, "investment", float(q["cost"]))
	c["work"]["road"] = {"level": int(q["level"]), "done_day": gs.today() + int(q["days"])}
	gs.notify("Reforma del camino a %s: %s (listo en %d días)." % [c["town_name"], q["label"], int(q["days"])], "construccion")
	return ""


static func rail_quote(gs, town_id: String) -> Dictionary:
	var c := connection(gs, town_id)
	var rc: Dictionary = cfg().get("rail", {})
	var dist := float(c.get("distance", 50.0))
	return {"cost": float(rc.get("cost_per_km", 90)) * dist * gs.price_mult(),
		"days": maxi(10, int(ceilf(dist * float(rc.get("days_per_km", 0.5))))), "tech": str(rc.get("tech", "ferrocarril"))}


static func rail_block_reason(gs, town_id: String) -> String:
	var c := connection(gs, town_id)
	if c.is_empty():
		return "Primero abre la ruta."
	if bool(c.get("rail", false)):
		return "Ya hay vía férrea."
	if c.get("work", {}).has("rail"):
		return "La vía férrea está en construcción."
	var q := rail_quote(gs, town_id)
	if not gs.has_tech(str(q["tech"])):
		return "Requiere investigar %s." % GameData.tech_label(str(q["tech"]))
	if gs.money < float(q["cost"]):
		return "Necesitas %s." % Fmt.money(float(q["cost"]))
	return ""


static func build_rail(gs, town_id: String) -> String:
	var why := rail_block_reason(gs, town_id)
	if why != "":
		return why
	var c := connection(gs, town_id)
	var q := rail_quote(gs, town_id)
	gs.add_money(-float(q["cost"]))
	gs.add_counter("trade_investment", float(q["cost"]))
	_stat(gs, "investment", float(q["cost"]))
	c["work"]["rail"] = {"done_day": gs.today() + int(q["days"])}
	gs.notify("Construcción de la vía férrea a %s (lista en %d días)." % [c["town_name"], int(q["days"])], "construccion")
	return ""


# --- Transporte ---------------------------------------------------------------------------

static func modes() -> Dictionary:
	return cfg().get("transport_modes", {})


static func mode_ids() -> Array:
	var m := modes()
	var ids := m.keys().filter(func(k): return not str(k).begins_with("_"))
	ids.sort_custom(func(a, b): return int(m[a].get("order", 0)) < int(m[b].get("order", 0)))
	return ids


static func mode_def(mode: String) -> Dictionary:
	return modes().get(mode, modes().get("a_pie", {}))


## Mejor edificio de infraestructura activo con personal: devuelve su multiplicador de capacidad (0 = no hay).
static func infra_mult(gs, type_id: String) -> float:
	var best := 0.0
	for b in gs.buildings:
		if str(b.get("type", "")) != type_id or not gs.owned_by_player(b) or str(b.get("status", "")) != "activo":
			continue
		var staff := 0
		for c in gs.employees_of(int(b["id"])):
			if c.job_kind == "empleo":
				staff += 1
		if staff <= 0:
			continue
		var jobs := maxi(1, int(gs.level_def(b).get("jobs", 1)))
		var m := float(gs.level_def(b).get("trade_capacity_mult", 1.0)) * (0.5 + 0.5 * minf(1.0, float(staff) / jobs))
		best = maxf(best, m)
	return best


## Motivo por el que un medio no se puede usar con ese pueblo ("" = disponible).
static func mode_block_reason(gs, town_id: String, mode: String) -> String:
	var md := mode_def(mode)
	var c := connection(gs, town_id)
	if c.is_empty():
		return "Sin ruta."
	if not gs.has_tech(str(md.get("tech", ""))):
		return "Requiere investigar %s." % GameData.tech_label(str(md.get("tech", "")))
	var maps: Array = md.get("maps", [])
	if not maps.is_empty() and not maps.has(str(gs.settings.get("map_type", "interior"))):
		return "Solo en mapas de costa o río."
	if bool(md.get("needs_water", false)) and not bool(town(gs, town_id).get("water", false)):
		return "Ese pueblo no tiene acceso por agua."
	if int(c.get("road", 0)) < int(md.get("min_road", 0)):
		return "Requiere %s." % road_label(int(md.get("min_road", 0))).to_lower()
	if bool(md.get("rail", false)) and not bool(c.get("rail", false)):
		return "Requiere vía férrea hasta el pueblo."
	var bt := str(md.get("building", ""))
	if bt != "" and infra_mult(gs, bt) <= 0.0:
		return "Requiere %s con al menos un empleado." % str(GameData.building_def(bt).get("label", bt)).to_lower()
	return ""


static func available_modes(gs, town_id: String) -> Array:
	return mode_ids().filter(func(m): return mode_block_reason(gs, town_id, m) == "")


## El medio más avanzado disponible (mayor orden).
static func best_mode(gs, town_id: String) -> String:
	var av := available_modes(gs, town_id)
	return str(av[av.size() - 1]) if not av.is_empty() else "a_pie"


## El medio disponible más barato por unidad con carga completa (el que se elige por defecto).
static func cheapest_mode(gs, town_id: String) -> String:
	var best := "a_pie"
	var best_cost := INF
	for m in available_modes(gs, town_id):
		var cap := mode_capacity(gs, str(m))
		var q := transport_quote(gs, town_id, cap, str(m))
		var unit: float = (float(q["cost"]) + float(mode_def(str(m)).get("monthly_upkeep", 0.0)) * gs.price_mult() * 0.25) / maxf(1.0, cap)
		if unit < best_cost:
			best_cost = unit
			best = str(m)
	return best


static func set_mode(gs, town_id: String, mode: String) -> String:
	var why := mode_block_reason(gs, town_id, mode)
	if why != "":
		return why
	connection(gs, town_id)["mode"] = mode
	return ""


## Medio en uso: el elegido si sigue disponible; si no, el mejor disponible.
static func active_mode(gs, town_id: String) -> String:
	var c := connection(gs, town_id)
	var m := str(c.get("mode", "a_pie"))
	if mode_block_reason(gs, town_id, m) != "":
		m = cheapest_mode(gs, town_id)
		if not c.is_empty():
			c["mode"] = m
	return m


static func mode_capacity(gs, mode: String) -> float:
	var md := mode_def(mode)
	var cap := float(md.get("capacity", 25))
	var bt := str(md.get("building", ""))
	if bt != "":
		cap *= maxf(1.0, infra_mult(gs, bt))
	return cap


## Cotización de transporte: {mode, trips, days, cost, fuel, wages, capacity}.
static func transport_quote(gs, town_id: String, qty: float, mode := "") -> Dictionary:
	var c := connection(gs, town_id)
	if mode == "":
		mode = active_mode(gs, town_id)
	var md := mode_def(mode)
	var dist := float(c.get("distance", town(gs, town_id).get("distance", 50.0)))
	var cap := mode_capacity(gs, mode)
	var trips := maxi(1, int(ceilf(maxf(0.0, qty) / maxf(1.0, cap))))
	var speed := float(md.get("speed_km_day", 25))
	if int(md.get("min_road", 0)) > 0 or mode == "a_pie":
		speed *= float(road_def(int(c.get("road", 0))).get("speed_mult", 1.0))
	var days := maxi(1, int(ceilf(dist / maxf(1.0, speed))))
	var pm: float = gs.price_mult()
	var per_trip := (float(md.get("trip_fixed", 2)) + float(md.get("per_km", 0.02)) * dist) * pm
	var fuel := float(md.get("fuel_per_km", 0.0)) * dist * float(cfg().get("fuel_price", 1.0)) * pm * trips
	var wages: float = float(md.get("crew", 1)) * float(md.get("crew_wage", 1.5)) * days * gs.price_level() * trips
	return {"mode": mode, "trips": trips, "days": days, "capacity": cap, "fuel": fuel, "wages": wages,
		"cost": per_trip * trips + fuel + wages}


# --- Precios por pueblo -------------------------------------------------------------------

static func _diff_trade(gs, key: String) -> float:
	return float(cfg().get("difficulty", {}).get(str(gs.settings.get("difficulty", "normal")), {}).get(key, 1.0))


static func _event_mult(t: Dictionary, good: String, today: int) -> float:
	var ev: Dictionary = t.get("event", {})
	if ev.is_empty() or str(ev.get("good", "")) != good or int(ev.get("until_day", 0)) < today:
		return 1.0
	return float(ev.get("mult", 1.0))


## Precio por unidad que el pueblo te paga (exportación). `extra` = unidades adicionales que ya le vendes.
static func export_price(gs, town_id: String, good: String, extra := 0.0) -> float:
	var t := town(gs, town_id)
	var row: Dictionary = t.get("goods", {}).get(good, {})
	if row.is_empty():
		return 0.0
	var pc: Dictionary = cfg().get("prices", {})
	var month_demand := maxf(1.0, float(row.get("demand", 10.0)))
	var sat := float(row.get("sat", 0.0)) + maxf(0.0, extra)
	var sat_f := maxf(float(pc.get("min_factor", 0.35)), 1.0 / (1.0 + float(pc.get("saturation_weight", 0.6)) * sat / month_demand))
	var p := base_price(good) * float(row.get("buy_mult", 1.0)) * float(row.get("fluct", 1.0)) * sat_f
	p *= _event_mult(t, good, gs.today()) * gs.price_mult() * _diff_trade(gs, "export")
	return p


## Precio por unidad que el pueblo te cobra (importación, con arancel). 0 = no lo vende.
static func import_price(gs, town_id: String, good: String, extra := 0.0) -> float:
	var t := town(gs, town_id)
	var row: Dictionary = t.get("goods", {}).get(good, {})
	if row.is_empty() or not bool(row.get("sells", false)):
		return 0.0
	var pc: Dictionary = cfg().get("prices", {})
	var supply := maxf(1.0, float(row.get("supply", 10.0)))
	var scar := float(row.get("scar", 0.0)) + maxf(0.0, extra)
	var scar_f := minf(float(pc.get("max_factor", 2.2)), 1.0 + float(pc.get("scarcity_weight", 0.5)) * scar / supply)
	var p := base_price(good) * float(row.get("sell_mult", 1.0)) * float(row.get("fluct", 1.0)) * scar_f
	p /= _event_mult(t, good, gs.today())  # Un auge de demanda allá encarece; una bonanza abarata.
	p *= gs.price_mult() * _diff_trade(gs, "import") * GovSim.import_mult(gs)
	return p


static func sells_good(gs, town_id: String, good: String) -> bool:
	return bool(town(gs, town_id).get("goods", {}).get(good, {}).get("sells", false))


## Cotización de venta: precio medio (baja a medida que saturas), bruto, transporte y neto.
static func quote_sale(gs, town_id: String, good: String, qty: float) -> Dictionary:
	var unit := export_price(gs, town_id, good, qty * 0.5)
	var gross := unit * qty
	var tq := transport_quote(gs, town_id, qty)
	return {"unit": unit, "gross": gross, "transport": float(tq["cost"]), "net": gross - float(tq["cost"]),
		"days": int(tq["days"]), "trips": int(tq["trips"]), "mode": str(tq["mode"])}


static func quote_purchase(gs, town_id: String, good: String, qty: float) -> Dictionary:
	var unit := import_price(gs, town_id, good, qty * 0.5)
	var goods_cost := unit * qty
	var tq := transport_quote(gs, town_id, qty)
	return {"unit": unit, "goods": goods_cost, "transport": float(tq["cost"]), "total": goods_cost + float(tq["cost"]),
		"days": int(tq["days"]), "trips": int(tq["trips"]), "mode": str(tq["mode"])}


static func incoming_units(gs) -> float:
	var n := 0.0
	for s in gs.trade.get("shipments", []):
		if str(s["kind"]) == KIND_BUY:
			n += float(s["qty"])
	return n


# --- Operaciones ---------------------------------------------------------------------------

## Vende `qty` unidades del almacén a un pueblo conectado. El dinero entra al llegar el envío.
static func sell(gs, town_id: String, good: String, qty: float, min_unit := 0.0) -> String:
	qty = floorf(qty)
	if connection(gs, town_id).is_empty():
		return "No tienes ruta comercial con ese pueblo."
	if qty <= 0.0:
		return "Cantidad inválida."
	if WarehouseSim.stock(gs, good) < qty:
		return "Solo tienes %d de %s en el almacén." % [int(WarehouseSim.stock(gs, good)), good_label(good)]
	var q := quote_sale(gs, town_id, good, qty)
	if min_unit > 0.0 and float(q["unit"]) < min_unit:
		return "El precio (%s) está por debajo del mínimo." % Fmt.money2(float(q["unit"]))
	if float(q["net"]) <= 0.0:
		return "El transporte cuesta más de lo que pagan."
	if gs.money < float(q["transport"]):
		return "Necesitas %s para el transporte." % Fmt.money(float(q["transport"]))
	WarehouseSim.remove(gs, good, qty)
	_pay_transport(gs, town_id, q)
	var row: Dictionary = town(gs, town_id)["goods"][good]
	row["sat"] = float(row.get("sat", 0.0)) + qty
	gs.trade["shipments"].append({"id": _next_id(gs), "town_id": town_id, "good": good, "qty": qty, "kind": KIND_SELL,
		"value": float(q["gross"]), "depart_day": gs.today(), "arrive_day": gs.today() + int(q["days"]), "mode": str(q["mode"])})
	return ""


## Compra `qty` unidades a un pueblo. Se paga al despachar y llega al almacén tras el viaje.
static func buy(gs, town_id: String, good: String, qty: float, max_unit := 0.0) -> String:
	qty = floorf(qty)
	if connection(gs, town_id).is_empty():
		return "No tienes ruta comercial con ese pueblo."
	if qty <= 0.0:
		return "Cantidad inválida."
	if not sells_good(gs, town_id, good):
		return "%s no vende %s." % [town(gs, town_id).get("name", ""), good_label(good)]
	if WarehouseSim.free_space(gs) - incoming_units(gs) < qty:
		return "No hay espacio en el almacén (libre: %d)." % int(maxf(0.0, WarehouseSim.free_space(gs) - incoming_units(gs)))
	var q := quote_purchase(gs, town_id, good, qty)
	if max_unit > 0.0 and float(q["unit"]) > max_unit:
		return "El precio (%s) supera el máximo." % Fmt.money2(float(q["unit"]))
	if gs.money < float(q["total"]):
		return "Necesitas %s." % Fmt.money(float(q["total"]))
	var goods_cost := float(q["goods"])
	var tariff := goods_cost - goods_cost / maxf(0.01, GovSim.import_mult(gs))
	gs.add_money(-goods_cost)
	if tariff > 0.0:
		GovSim.add_treasury(gs, tariff)  # El arancel queda en el tesoro del pueblo.
	gs.add_counter("imports", goods_cost)
	EconomySim.record_value(gs, "imports", goods_cost)
	_stat(gs, "imports", goods_cost)
	var c := connection(gs, town_id)
	c["imported"] = float(c.get("imported", 0.0)) + goods_cost
	_pay_transport(gs, town_id, q)
	var row: Dictionary = town(gs, town_id)["goods"][good]
	row["scar"] = float(row.get("scar", 0.0)) + qty
	gs.trade["shipments"].append({"id": _next_id(gs), "town_id": town_id, "good": good, "qty": qty, "kind": KIND_BUY,
		"value": goods_cost, "depart_day": gs.today(), "arrive_day": gs.today() + int(q["days"]), "mode": str(q["mode"])})
	return ""


## Paga el flete. Los sueldos de los cargadores/arrieros van a desempleados del pueblo si los hay.
static func _pay_transport(gs, _town_id: String, q: Dictionary) -> void:
	var cost := float(q["transport"])
	gs.add_money(-cost)
	gs.add_counter("transport", cost)
	_stat(gs, "transport", cost)
	var tq_mode := str(q.get("mode", "a_pie"))
	var md := mode_def(tq_mode)
	var wages: float = float(md.get("crew", 1)) * float(md.get("crew_wage", 1.5)) * int(q["days"]) * gs.price_level() * int(q["trips"])
	wages = minf(wages, cost)
	var crew := _local_crew(gs, int(md.get("crew", 1)) * int(q["trips"]))
	if crew.is_empty():
		return
	var share: float = wages / crew.size()
	for c in crew:
		c.money += share
		c.skills["comercio"] = minf(100.0, float(c.skills.get("comercio", 0.0)) + 0.1)


static func _local_crew(gs, n: int) -> Array:
	var today: int = gs.today()
	var adult := int(GameData.citizens.get("adult_age", 16))
	var out := []
	for c in gs.citizens.values():
		if out.size() >= n:
			break
		if c.job_id >= 0 or gs.is_player(c.id) or c.prison_until >= 0:
			continue
		var age: int = c.age_years(today)
		if age >= adult and age < 55:
			out.append(c)
	return out


# --- Contratos automáticos -------------------------------------------------------------------

static func add_contract(gs, town_id: String, good: String, kind: String, qty: float, every: int, limit := 0.0) -> String:
	if connection(gs, town_id).is_empty():
		return "No tienes ruta con ese pueblo."
	if qty < 1.0 or every < 1:
		return "Cantidad o frecuencia inválida."
	if kind == KIND_BUY and not sells_good(gs, town_id, good):
		return "Ese pueblo no vende %s." % good_label(good)
	gs.trade["contracts"].append({"id": _next_id(gs), "town_id": town_id, "good": good, "kind": kind, "qty": floorf(qty),
		"every": every, "next_day": gs.today(), "limit": limit, "active": true, "fails": 0, "done": 0})
	return ""


static func remove_contract(gs, id: int) -> void:
	var list: Array = gs.trade.get("contracts", [])
	for i in range(list.size()):
		if int(list[i]["id"]) == id:
			list.remove_at(i)
			return


static func toggle_contract(gs, id: int) -> void:
	for k in gs.trade.get("contracts", []):
		if int(k["id"]) == id:
			k["active"] = not bool(k.get("active", true))
			k["next_day"] = gs.today()


static func _run_contracts(gs) -> void:
	var today: int = gs.today()
	for k in gs.trade.get("contracts", []):
		if not bool(k.get("active", true)) or int(k["next_day"]) > today:
			continue
		k["next_day"] = today + int(k["every"])
		var tid := str(k["town_id"])
		var err := ""
		if str(k["kind"]) == KIND_SELL:
			var qty := minf(float(k["qty"]), floorf(WarehouseSim.stock(gs, str(k["good"]))))
			err = sell(gs, tid, str(k["good"]), qty, float(k.get("limit", 0.0))) if qty >= 1.0 else "sin existencias en el almacén"
		else:
			err = buy(gs, tid, str(k["good"]), float(k["qty"]), float(k.get("limit", 0.0)))
		if err == "":
			k["fails"] = 0
			k["done"] = int(k.get("done", 0)) + 1
		else:
			k["fails"] = int(k.get("fails", 0)) + 1
			k["last_error"] = err
			if int(k["fails"]) == 1 or int(k["fails"]) % 6 == 0:
				gs.notify("Contrato con %s (%s %s) no se cumplió: %s" % [town(gs, tid).get("name", ""), k["kind"], good_label(str(k["good"])), err.trim_suffix(".")], "negocio")


# --- Ciclo diario / mensual ------------------------------------------------------------------

static func daily(gs) -> void:
	if gs.trade.get("towns", []).is_empty():
		return
	var today: int = gs.today()
	# Obras de caminos.
	var projects: Array = gs.trade.get("projects", [])
	for p in projects.duplicate():
		if int(p["done_day"]) <= today:
			projects.erase(p)
			_complete_project(gs, p)
	for c in connected_towns(gs):
		var work: Dictionary = c.get("work", {})
		if work.has("road") and int(work["road"]["done_day"]) <= today:
			c["road"] = int(work["road"]["level"])
			work.erase("road")
			gs.notify("El camino a %s ahora es %s." % [c["town_name"], road_label(int(c["road"])).to_lower()], "construccion")
		if work.has("rail") and int(work["rail"]["done_day"]) <= today:
			c["rail"] = true
			work.erase("rail")
			gs.notify("La vía férrea a %s está terminada." % c["town_name"], "construccion")
	_deliver(gs, today)
	_run_contracts(gs)
	# Los pueblos absorben lo que les vendiste y reponen lo que les compraste.
	for t in towns(gs):
		for g in t.get("goods", {}):
			var row: Dictionary = t["goods"][g]
			if float(row.get("sat", 0.0)) > 0.0:
				row["sat"] = maxf(0.0, float(row["sat"]) - float(row.get("demand", 10.0)) / 30.0)
			if float(row.get("scar", 0.0)) > 0.0:
				row["scar"] = maxf(0.0, float(row["scar"]) - float(row.get("supply", 10.0)) / 30.0)
	if today % 7 == 5:
		_immigration(gs, 7.0 / 30.4)


static func _deliver(gs, today: int) -> void:
	var list: Array = gs.trade.get("shipments", [])
	for s in list.duplicate():
		if int(s["arrive_day"]) > today:
			continue
		var tname := str(town(gs, str(s["town_id"])).get("name", ""))
		if str(s["kind"]) == KIND_SELL:
			var value := float(s["value"])
			gs.add_money(value)
			gs.add_counter("exports", value)
			EconomySim.record_value(gs, "exports", value)
			_stat(gs, "exports", value)
			var c := connection(gs, str(s["town_id"]))
			c["exported"] = float(c.get("exported", 0.0)) + value
			list.erase(s)
		else:
			var accepted := WarehouseSim.add(gs, str(s["good"]), float(s["qty"]))
			s["qty"] = float(s["qty"]) - accepted
			if float(s["qty"]) <= 0.001:
				list.erase(s)
			else:
				s["arrive_day"] = today + 1
				if not bool(s.get("waiting", false)):
					s["waiting"] = true
					gs.notify("Llegó carga de %s pero no cabe en el almacén: %d de %s esperan." % [tname, int(s["qty"]), good_label(str(s["good"]))], "negocio")


static func monthly(gs) -> void:
	if gs.trade.get("towns", []).is_empty():
		return
	_fluctuate(gs)
	_upkeep(gs)
	gs.trade["last_month"] = gs.trade.get("month", {})
	gs.trade["month"] = {}


static func _fluctuate(gs) -> void:
	var r := _rng(gs)
	var pc: Dictionary = cfg().get("prices", {})
	var ev_mult := float(gs.diff().get("event_freq_mult", 1.0))
	var vol := float(pc.get("fluct_volatility", 0.05)) * ev_mult
	var rev := float(pc.get("fluct_revert", 0.15))
	var fr: Array = pc.get("fluct_range", [0.65, 1.6])
	var today: int = gs.today()
	for t in towns(gs):
		for g in t.get("goods", {}):
			var row: Dictionary = t["goods"][g]
			var f := float(row.get("fluct", 1.0))
			f += r.randfn(0.0, vol) - (f - 1.0) * rev
			row["fluct"] = clampf(f, float(fr[0]), float(fr[1]))
		var ev: Dictionary = t.get("event", {})
		if not ev.is_empty() and int(ev.get("until_day", 0)) < today:
			t["event"] = {}
		if t.get("event", {}).is_empty() and r.randf() < float(pc.get("event_monthly_chance", 0.02)) * ev_mult:
			var goods: Array = t.get("goods", {}).keys()
			var g := str(goods[r.randi() % goods.size()])
			var m := _rand_range(r, pc.get("event_mult", [0.6, 1.6]))
			var months := r.randi_range(int(pc.get("event_months", [3, 8])[0]), int(pc.get("event_months", [3, 8])[1]))
			t["event"] = {"good": g, "mult": m, "until_day": today + months * 30}
			if not connection(gs, str(t["id"])).is_empty():
				var what := "gran demanda de" if m > 1.0 else "exceso de"
				gs.notify("En %s hay %s %s: los precios cambian por %d meses." % [t["name"], what, good_label(g).to_lower(), months], "negocio")
	_save_rng(gs, r)


## Mantenimiento mensual: caminos, vías férreas y flota (bueyes, trenes, camiones…).
static func _upkeep(gs) -> void:
	var total := monthly_upkeep_estimate(gs)
	if total > 0.0:
		gs.add_money(-total)
		gs.add_counter("trade_upkeep", total)
		_stat(gs, "upkeep", total)


static func monthly_upkeep_estimate(gs) -> float:
	var pm: float = gs.price_mult()
	var total := 0.0
	for c in connected_towns(gs):
		var dist := float(c.get("distance", 50.0))
		total += float(road_def(int(c.get("road", 1))).get("upkeep_per_km", 0.05)) * dist * pm
		if bool(c.get("rail", false)):
			total += float(cfg().get("rail", {}).get("upkeep_per_km", 0.08)) * dist * pm
		total += float(mode_def(active_mode(gs, str(c["town_id"]))).get("monthly_upkeep", 0.0)) * pm
	return total


static func _stat(gs, key: String, amount: float) -> void:
	var m: Dictionary = gs.trade.get("month", {})
	m[key] = float(m.get(key, 0.0)) + amount
	gs.trade["month"] = m
	var t: Dictionary = gs.trade.get("totals", {})
	t[key] = float(t.get(key, 0.0)) + amount
	gs.trade["totals"] = t


# --- Inmigración -------------------------------------------------------------------------------

## Calidad de las conexiones para atraer gente (0 si no hay ninguna).
static func connection_factor(gs) -> float:
	var ic: Dictionary = cfg().get("immigration", {})
	var ref := float(ic.get("town_pop_ref", 1000))
	var sum := 0.0
	for c in connected_towns(gs):
		var t := town(gs, str(c["town_id"]))
		var pop_f := clampf(float(t.get("population", ref)) / ref, 0.4, 2.5)
		var road_f := float(road_def(int(c.get("road", 1))).get("immigration", 1.0))
		var mode_f := float(mode_def(active_mode(gs, str(c["town_id"]))).get("immigration", 1.0))
		var dist_f := clampf(80.0 / maxf(20.0, float(c.get("distance", 80.0))), 0.5, 1.5)
		sum += pop_f * road_f * mode_f * dist_f
	if sum <= 0.0:
		return 0.0
	return pow(sum, float(ic.get("connection_exponent", 0.7)))


## Atractivo del pueblo: empleo, vivienda libre, felicidad y salarios. Devuelve el detalle para la interfaz.
static func attractiveness(gs) -> Dictionary:
	var ic: Dictionary = cfg().get("immigration", {})
	var w: Dictionary = ic.get("weights", {})
	var emp := StatsSim.employment(gs)
	var vac := float(emp.get("vacancies", 0))
	var unemployed := float(emp.get("unemployed", 0))
	var workforce := maxf(1.0, float(emp.get("workforce", 1)))
	var jobs := clampf((vac - unemployed * 0.3) / maxf(4.0, workforce * 0.25), -1.0, 1.0)
	var free := float(free_housing(gs))
	var homeless := 0
	for c in gs.citizens.values():
		if c.home_id < 0:
			homeless += 1
	var housing := clampf((free - homeless) / 8.0, -1.0, 1.0)
	var happy := clampf((gs.avg_happiness() - 55.0) / 25.0, -1.0, 1.0)
	var avg_wage := float(emp.get("avg_wage", 0.0))
	var ref_wage: float = 2.0 * gs.price_level()
	var wages := clampf(avg_wage / ref_wage - 1.0, -0.5, 1.0) if float(emp.get("employed", 0)) > 0 else -0.2
	var score := 1.0 + float(w.get("jobs", 0.6)) * jobs + float(w.get("housing", 0.5)) * housing \
			+ float(w.get("happiness", 0.6)) * happy + float(w.get("wages", 0.4)) * wages
	score = clampf(score, float(ic.get("attract_min", 0.05)), float(ic.get("attract_max", 3.0)))
	var conn := connection_factor(gs)
	return {"score": score, "jobs": jobs, "housing": housing, "happiness": happy, "wages": wages,
		"connections": conn, "free_housing": free, "homeless": homeless, "vacancies": vac,
		"families_month": float(ic.get("base_families_month", 0.5)) * conn * score}


## Plazas libres en chozas del pueblo y en tus viviendas.
static func free_housing(gs) -> int:
	var occ := PopulationSim.home_occupancy(gs)
	var free := 0
	for b in gs.buildings:
		if not Housing.is_home(b) or str(b.get("status", "")) != "activo":
			continue
		var owner := str(b.get("owner", "pueblo"))
		if owner == "ciudadano" or bool(b.get("for_sale", false)):
			continue
		var p: Citizen = gs.player_citizen()
		if p != null and p.home_id == int(b["id"]):
			continue
		free += maxi(0, gs.building_capacity(b) - int(occ.get(int(b["id"]), 0)))
	return free


static func _immigration(gs, fraction: float) -> void:
	if not is_connected_any(gs):
		return
	var ic: Dictionary = cfg().get("immigration", {})
	var a := attractiveness(gs)
	var expected := float(a["families_month"]) * fraction
	expected = minf(expected, float(ic.get("max_families_month", 5)) * fraction)
	var r := _rng(gs)
	var n := int(floorf(expected))
	if r.randf() < expected - floorf(expected):
		n += 1
	var conns := connected_towns(gs)
	for i in range(n):
		# El pueblo de origen: al azar, ponderado por su aporte.
		var c: Dictionary = conns[r.randi() % conns.size()]
		_arrive_family(gs, r, c)
	_save_rng(gs, r)


static func _arrive_family(gs, r: RandomNumberGenerator, conn: Dictionary) -> void:
	var ic: Dictionary = cfg().get("immigration", {})
	var fam: Dictionary = ic.get("family", {})
	var ages: Array = ic.get("age", [18, 40])
	var members: Array = []
	var roll := r.randf()
	var surname := PopulationSim.random_surname(gs)
	var age := r.randi_range(int(ages[0]), int(ages[1]))
	if roll < float(fam.get("single", 0.35)):
		members.append(PopulationSim.create_citizen(gs, "M" if r.randf() < 0.6 else "F", age, surname))
	else:
		var husband := PopulationSim.create_citizen(gs, "M", age, surname)
		var w_age := clampi(age + r.randi_range(-6, 2), 18, 42)
		var wife := PopulationSim.create_citizen(gs, "F", w_age, PopulationSim.random_surname(gs))
		PopulationSim.marry(husband, wife)
		members.append_array([husband, wife])
		if roll >= float(fam.get("single", 0.35)) + float(fam.get("couple", 0.15)):
			var kids := r.randi_range(1, int(fam.get("kids_max", 3)))
			var max_child := mini(15, w_age - 18)
			for k in range(kids):
				var kid := PopulationSim.create_citizen(gs, "M" if r.randf() < 0.5 else "F", r.randi_range(0, maxi(0, max_child)), surname)
				PopulationSim.link_parents(kid, husband, wife)
				members.append(kid)
	# Vivienda: una choza del pueblo con espacio si la hay; si no, quedan sin hogar
	# (el mercado de vivienda mensual les buscará alquiler o autoconstruirán).
	var home := _free_town_hut(gs, members.size())
	for m in members:
		m.home_id = int(home["id"]) if not home.is_empty() else -1
		EventBus.citizen_born.emit(m.id)
	conn["immigrants"] = int(conn.get("immigrants", 0)) + members.size()
	gs.count("immigrants", members.size())
	_stat(gs, "immigrants", float(members.size()))
	var head: Citizen = members[0]
	var who := "%s" % head.full_name() if members.size() == 1 else "La familia %s (%d personas)" % [head.last_name, members.size()]
	var where := "" if not home.is_empty() else " No tienen vivienda: construye o alquila casas."
	gs.notify("%s llegó desde %s por el camino.%s" % [who, conn.get("town_name", ""), where], "info")


static func _free_town_hut(gs, size: int) -> Dictionary:
	var occ := PopulationSim.home_occupancy(gs)
	for b in gs.buildings:
		if Housing.is_home(b) and str(b.get("owner", "")) == "pueblo" and str(b.get("status", "")) == "activo":
			if gs.building_capacity(b) - int(occ.get(int(b["id"]), 0)) >= size:
				return b
	return {}
