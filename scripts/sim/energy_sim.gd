class_name EnergySim
extends RefCounted
## Economía real — electricidad y yacimientos de energía.
##
## - Las centrales (negocios con "power_plant": true, producto "electricidad") generan cada día
##   electricidad que NO se almacena (queda en su inventario hasta el fin del día).
## - Demanda: niveles de negocio con "power" (electricidad por trabajador y día) o, si no lo
##   declaran, los niveles de la época moderna (default_power_modern). Hogares: desde la tecnología
##   home_tech, cada adulto consume home_units_per_person_day (incluye a sus hijos).
## - Reparto: primero tus centrales (a tus fábricas el traspaso es interno: la central factura y la
##   fábrica paga, neto cero para ti); lo que falta se compra a la red regional si hay una ruta
##   comercial terminada (el dinero sale del pueblo). El sobrante se vende a los hogares.
## - Sin electricidad suficiente una fábrica rinde unpowered_output (50 %) en la parte no cubierta:
##   se descuenta lo producido hoy y se devuelven al almacén los insumos no usados.
## - Solo existe demanda cuando se investigó grid_tech (dínamo): antes nadie usa electricidad.
## Configuración: data/resources_energia.json → energy. Estado: gs.economy["energy"] (se guarda solo).
## Se llama desde MarketSim.begin_day (después de BusinessSim.produce y antes de BusinessSim.end_day).

const PRODUCT := "electricidad"


static func cfg() -> Dictionary:
	return GameData.extra("resources_energia").get("energy", {})


static func state(gs) -> Dictionary:
	if not gs.economy.has("energy"):
		gs.economy["energy"] = {"day": -1, "coverage": {}, "month": {}, "last_month": {}}
	return gs.economy["energy"]


static func grid_active(gs) -> bool:
	return gs.has_tech(str(cfg().get("grid_tech", "dinamo")))


static func homes_active(gs) -> bool:
	return gs.has_tech(str(cfg().get("home_tech", "electricidad")))


static func is_plant(def: Dictionary) -> bool:
	return bool(def.get("power_plant", false)) or str(def.get("product", "")) == PRODUCT


## Electricidad por trabajador y día que pide un nivel (0 = no usa).
static func level_power(def: Dictionary, ld: Dictionary) -> float:
	if is_plant(def):
		return 0.0
	if ld.has("power"):
		return float(ld["power"])
	var tech := str(ld.get("tech", ""))
	if tech != "" and int(GameData.technologies.get(tech, {}).get("era", 1)) >= 3:
		return float(cfg().get("default_power_modern", 1.0))
	return 0.0


static func _workers(gs, b: Dictionary) -> int:
	var n := 0
	for c in gs.employees_of(int(b["id"])):
		if c.job_kind == "empleo" and not c.sick:
			n += 1
	return n


## kW que pide un nivel a plantilla completa (campo "power_demand"; si falta, power × empleos).
static func level_demand_kw(def: Dictionary, ld: Dictionary) -> float:
	if is_plant(def):
		return 0.0
	if ld.has("power_demand"):
		return float(ld["power_demand"])
	return level_power(def, ld) * int(ld.get("jobs", 1))


## kW nominales de una central a plantilla completa (campo "power_output").
static func level_output_kw(def: Dictionary, ld: Dictionary) -> float:
	if not is_plant(def):
		return 0.0
	return float(ld.get("power_output", float(ld.get("prod_per_worker", 0.0)) * int(ld.get("jobs", 1))))


## Demanda diaria (kW) de un edificio del jugador: power_demand × fracción de la plantilla trabajando.
static func demand_of(gs, b: Dictionary) -> float:
	if not gs.owned_by_player(b) or b["status"] != "activo" or not BusinessSim.is_business(b):
		return 0.0
	var ld: Dictionary = gs.level_def(b)
	return level_demand_kw(gs.building_def(b), ld) * float(_workers(gs, b)) / maxf(1.0, float(ld.get("jobs", 1)))


## PUNTO ÚNICO para la red eléctrica: fracción (0–1) de la energía que pidió `b` que recibió en el
## último día. Hoy es global (tus centrales + red regional, repartido a prorrata); la red de cables
## podrá reemplazar el reparto de EnergySim.daily para contar solo lo conectado.
static func supply_ratio(gs, b: Dictionary) -> float:
	if not grid_active(gs):
		return 1.0
	return clampf(float(state(gs).get("coverage", {}).get(str(int(b["id"])), 1.0)), 0.0, 1.0)


## Multiplicador de rendimiento por electricidad (1 = sin problemas; 0,5 sin nada).
static func factor(gs, b: Dictionary) -> float:
	if not grid_active(gs):
		return 1.0
	var c := supply_ratio(gs, b)
	return 1.0 - (1.0 - c) * (1.0 - float(cfg().get("unpowered_output", 0.5)))


static func price(gs) -> float:
	return EconomySim.market_price(gs, PRODUCT)


static func grid_price(gs) -> float:
	return float(GameData.goods.get(PRODUCT, {}).get("import_price", 0.6)) * gs.price_mult()


## ¿Se puede comprar a la red regional? (ruta comercial terminada + tecnología eléctrica moderna)
static func grid_available(gs) -> bool:
	return bool(cfg().get("grid_import", true)) and homes_active(gs) and TradeSim.is_connected_any(gs)


# --- Simulación diaria ---------------------------------------------------------------------------

static func daily(gs) -> void:
	var st := state(gs)
	var today: int = gs.today()
	if int(st.get("day", -1)) == today:
		return
	st["day"] = today
	RegionSim.reveal_tech_deposits(gs)
	if not grid_active(gs):
		st["coverage"] = {}
		return
	# 1) Oferta de tus centrales (producida hoy por BusinessSim.produce).
	var plants := []
	var supply := 0.0
	for b in gs.buildings:
		if gs.owned_by_player(b) and b["status"] == "activo" and is_plant(gs.building_def(b)):
			var e := float(b["inventory"].get(PRODUCT, 0.0))
			if e > 0.0:
				plants.append([b, e])
				supply += e
	# 2) Demanda de tus negocios.
	var users := []
	var demand := 0.0
	for b in gs.buildings:
		var d := demand_of(gs, b)
		if d > 0.0:
			users.append([b, d])
			demand += d
	var p := price(gs)
	var own_to_business := minf(supply, demand)
	var ratio_own := own_to_business / demand if demand > 0.0 else 1.0
	var grid_ok := grid_available(gs)
	var gp := grid_price(gs)
	var cov := {}
	var lost_value := 0.0
	var grid_units := 0.0
	for pair in users:
		var b: Dictionary = pair[0]
		var need: float = pair[1]
		var own := need * ratio_own
		var from_grid := 0.0
		if own < need and grid_ok:
			from_grid = need - own
		if own > 0.0:
			BusinessSim.pay(gs, b, own * p, "insumos")   # Traspaso interno: lo cobra tu central.
		if from_grid > 0.0:
			BusinessSim.pay(gs, b, from_grid * gp, "insumos")   # Red regional: sale del pueblo.
			grid_units += from_grid
		var c := clampf((own + from_grid) / need, 0.0, 1.0)
		cov[str(int(b["id"]))] = c
		if c < 0.999:
			lost_value += _apply_shortfall(gs, b, (1.0 - c) * (1.0 - float(cfg().get("unpowered_output", 0.5))))
	_bill_plants(gs, plants, own_to_business * p)
	# 3) Hogares: el sobrante de tus centrales (o la red regional) se vende a los vecinos.
	var home := {"units": 0.0, "powered": 0, "unpowered": 0, "revenue": 0.0}
	var surplus := supply - own_to_business
	if homes_active(gs):
		home = _homes(gs, surplus, grid_ok)
		_bill_plants(gs, plants, float(home["revenue"]))
	st["coverage"] = cov
	var m: Dictionary = st.get("month", {})
	for kv in [["supply", supply], ["demand", demand], ["own_business", own_to_business], ["grid_units", grid_units + float(home.get("grid_units", 0.0))],
			["homes_units", float(home["units"])], ["homes_powered", float(home["powered"])], ["homes_unpowered", float(home["unpowered"])],
			["lost_value", lost_value], ["wasted", maxf(0.0, surplus - float(home.get("own_units", 0.0)))], ["days", 1.0]]:
		m[kv[0]] = float(m.get(kv[0], 0.0)) + float(kv[1])
	st["month"] = m
	st["today"] = {"supply": supply, "demand": demand, "grid": grid_ok, "homes": home}


## Reparte ingresos entre las centrales según lo que produjo cada una.
static func _bill_plants(gs, plants: Array, amount: float) -> void:
	if amount <= 0.0 or plants.is_empty():
		return
	var total := 0.0
	for pr in plants:
		total += float(pr[1])
	for pr in plants:
		BusinessSim.earn(gs, pr[0], amount * float(pr[1]) / maxf(0.0001, total), "ventas")


## Descuenta la producción perdida por falta de electricidad y devuelve los insumos no usados.
## Devuelve el valor perdido (a precio de mercado).
static func _apply_shortfall(gs, b: Dictionary, lost_frac: float) -> float:
	var def: Dictionary = gs.building_def(b)
	var ld: Dictionary = gs.level_def(b)
	var product := str(def.get("product", ""))
	if lost_frac <= 0.0 or product == "" or not GameData.goods.has(product) or bool(GameData.goods[product].get("internal", false)):
		return 0.0
	var made := float(b.get("produced_today", -1.0))
	if made < 0.0:
		made = BusinessSim.expected_output(gs, b)
	var lost := made * lost_frac
	if lost <= 0.0:
		return 0.0
	var taken := 0.0
	var wid := -1
	if LogisticsSim.uses_chain(def, ld) and LogisticsSim.output_target(gs, b) == "warehouse":
		wid = WarehouseSim.warehouse_for(gs, b)
		taken = WarehouseSim.remove_from(gs, wid, product, lost)
	else:
		var inv: Dictionary = b["inventory"]
		taken = minf(lost, float(inv.get(product, 0.0)))
		inv[product] = float(inv.get(product, 0.0)) - taken
	if b.has("produced_today"):
		b["produced_today"] = maxf(0.0, made - taken)
	# Los insumos no usados vuelven a su almacén vinculado (o al sitio).
	var inputs := LogisticsSim.recipe_inputs(def, ld)
	for g in inputs:
		var back := float(inputs[g]) * taken
		if wid >= 0:
			back -= WarehouseSim.add_to(gs, wid, str(g), back)
		if back > 0.0001:
			b["inventory"][str(g)] = float(b["inventory"].get(str(g), 0.0)) + back
	if taken > 0.0:
		b["chain_status"] = "sin electricidad suficiente"
	return taken * EconomySim.market_price(gs, product)


## Consumo de los hogares. Devuelve {units, own_units, grid_units, powered, unpowered, revenue}.
static func _homes(gs, surplus: float, grid_ok: bool) -> Dictionary:
	var per := float(cfg().get("home_units_per_person_day", 0.3)) * 1.5
	var p := price(gs)
	var gp := grid_price(gs)
	var out := {"units": 0.0, "own_units": 0.0, "grid_units": 0.0, "powered": 0, "unpowered": 0, "revenue": 0.0}
	var today: int = gs.today()
	var adult := int(GameData.citizens.get("adult_age", 16))
	var hp := float(cfg().get("home_powered_happiness", 1.5)) / 7.0
	var hu := float(cfg().get("home_unpowered_happiness", -3.0)) / 7.0
	var left := surplus
	for c in gs.citizens.values():
		if c.age_years(today) < adult or c.home_id < 0:
			continue
		if gs.is_player(c.id):
			continue
		var from_own := minf(per, maxf(0.0, left))
		var from_grid := (per - from_own) if grid_ok else 0.0
		var cost := from_own * p + from_grid * gp
		if from_own + from_grid < per * 0.999 or c.money < cost:
			out["unpowered"] = int(out["unpowered"]) + 1
			c.happiness = clampf(c.happiness + hu, 0.0, 100.0)
			continue
		c.money -= cost
		left -= from_own
		out["units"] = float(out["units"]) + per
		out["own_units"] = float(out["own_units"]) + from_own
		out["grid_units"] = float(out["grid_units"]) + from_grid
		out["revenue"] = float(out["revenue"]) + from_own * p
		out["powered"] = int(out["powered"]) + 1
		c.happiness = clampf(c.happiness + hp, 0.0, 100.0)
	if float(out["own_units"]) > 0.0:
		EconomySim.record_discretionary(gs, PRODUCT, float(out["own_units"]), float(out["revenue"]))
	return out


static func monthly(gs) -> void:
	var st := state(gs)
	st["last_month"] = st.get("month", {})
	st["month"] = {}


## Resumen para la interfaz (catálogo y paneles).
static func summary(gs) -> Dictionary:
	var st := state(gs)
	var m: Dictionary = st.get("last_month", {})
	if m.is_empty():
		m = st.get("month", {})
	var days := maxf(1.0, float(m.get("days", 0.0)))
	return {
		"active": grid_active(gs), "homes": homes_active(gs), "grid": grid_available(gs),
		"supply_day": float(m.get("supply", 0.0)) / days, "demand_day": float(m.get("demand", 0.0)) / days,
		"grid_day": float(m.get("grid_units", 0.0)) / days, "homes_day": float(m.get("homes_units", 0.0)) / days,
		"lost_value": float(m.get("lost_value", 0.0)), "wasted_day": float(m.get("wasted", 0.0)) / days,
		"homes_powered": float(m.get("homes_powered", 0.0)) / days, "homes_unpowered": float(m.get("homes_unpowered", 0.0)) / days,
		"price": price(gs), "grid_price": grid_price(gs),
	}
