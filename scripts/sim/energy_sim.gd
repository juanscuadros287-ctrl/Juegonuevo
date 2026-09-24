class_name EnergySim
extends RefCounted
## Economía real — electricidad y yacimientos de energía.
##
## - Las centrales (negocios con "power_plant": true, producto "electricidad") generan cada día
##   electricidad que NO se almacena (queda en su inventario hasta el fin del día).
## - Demanda: niveles de negocio con "power" (electricidad por trabajador y día) o, si no lo
##   declaran, los niveles de la época moderna (default_power_modern). Hogares: desde la tecnología
##   home_tech, cada adulto consume home_units_per_person_day (incluye a sus hijos).
## - Reparto POR RED (GridSim, docs/REDES.md): solo cuenta lo conectado por cables. En cada red,
##   primero sus centrales (a tus fábricas el traspaso es interno: la central factura y la fábrica
##   paga, neto cero para ti); lo que falta se compra a la red regional si esa red toca la entrada
##   regional (plaza/ruta comercial) y hay una ruta comercial terminada (el dinero sale del pueblo).
##   El sobrante se vende a los hogares conectados (factura mensual con tarifa configurable).
## - Sin electricidad suficiente una fábrica rinde unpowered_output (50 %) en la parte no cubierta;
##   los niveles con "requires_power" no producen nada sin ella. Se descuenta lo producido hoy y se
##   devuelven al almacén los insumos no usados.
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
## último día. La calcula GridSim.power_daily por red conectada (sin cable = 0).
static func supply_ratio(gs, b: Dictionary) -> float:
	if not grid_active(gs):
		return 1.0
	return clampf(float(state(gs).get("coverage", {}).get(str(int(b["id"])), 1.0)), 0.0, 1.0)


## Multiplicador de rendimiento por electricidad (1 = sin problemas; 0,5 sin nada).
static func factor(gs, b: Dictionary) -> float:
	if not grid_active(gs):
		return 1.0
	var c := supply_ratio(gs, b)
	return 1.0 - (1.0 - c) * (1.0 - unpowered_output(gs.level_def(b)))


## Redes: los niveles con "requires_power": true (industria avanzada) no producen NADA sin
## electricidad; los demás rinden unpowered_output (50 %) en la parte no cubierta.
static func requires_power(ld: Dictionary) -> bool:
	return bool(ld.get("requires_power", false))


static func unpowered_output(ld: Dictionary) -> float:
	return 0.0 if requires_power(ld) else float(cfg().get("unpowered_output", 0.5))


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
	# Redes: el reparto se hace por red eléctrica conectada (GridSim, docs/REDES.md): cada red reparte
	# la generación de SUS centrales entre SUS consumidores; solo la red que toca la entrada regional
	# (plaza o ruta comercial) compra lo que falta. Los hogares conectados acumulan su factura mensual.
	GridSim.power_daily(gs, st)


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
