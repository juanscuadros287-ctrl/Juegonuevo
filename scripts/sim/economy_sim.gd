class_name EconomySim
extends RefCounted
## Economía real: oferta y demanda por bien (precios suben con escasez y bajan con exceso),
## inflación según dinero en circulación, crédito y producción, y estadísticas macro.


static func cfg() -> Dictionary:
	return GameData.economy


static func init_state(gs) -> void:
	gs.economy = {"price_level": 1.0, "inflation_month": 0.0, "goods": {}, "money_prev": total_money(gs),
		"output_prev": 0.0, "credit_prev": 0.0, "month": {}}
	for g in GameData.goods:
		gs.economy["goods"][g] = {"factor": 1.0, "demand": 0.0, "local": 0.0, "shortfall": 0.0}


static func good_state(gs, good: String) -> Dictionary:
	var goods: Dictionary = gs.economy.get("goods", {})
	if not goods.has(good):
		goods[good] = {"factor": 1.0, "demand": 0.0, "local": 0.0, "shortfall": 0.0}
		gs.economy["goods"] = goods
	return goods[good]


## Multiplicador de oferta/demanda de un bien (1 = normal).
static func good_factor(gs, good: String) -> float:
	# Mundo: escasez por clima (ClimateSim) y demanda de guerra (WarSim).
	return float(good_state(gs, good).get("factor", 1.0)) * ClimateSim.price_mult(gs, good) * WarSim.price_mult(gs, good)


## Precio de mercado por unidad (referencia para ciudadanos y precios automáticos).
## Incluye la fluctuación mensual de los bienes con "volatility" (economía real).
static func market_price(gs, good: String) -> float:
	return float(GameData.goods.get(good, {}).get("base_price", 0.0)) * gs.price_mult() * good_factor(gs, good) * fluct(gs, good)


## Fluctuación de mercado de un bien (1 = sin fluctuación).
static func fluct(gs, good: String) -> float:
	var goods: Dictionary = gs.economy.get("goods", {})
	return float(goods[good].get("fluct", 1.0)) if goods.has(good) else 1.0


## Economía real: paseo aleatorio con reversión a 1 para los bienes con "volatility" (materias primas,
## petróleo…). La amplitud escala con event_freq_mult de la dificultad. RNG propio y determinista
## (semilla + mes + bien) para no alterar la simulación del resto.
static func update_fluctuations(gs, month := -1) -> void:
	var fc: Dictionary = cfg().get("fluctuation", {})
	var mult := float(gs.diff().get("event_freq_mult", 1.0))
	var revert := float(fc.get("revert", 0.25))
	var lo := float(fc.get("min", 0.7))
	var hi := float(fc.get("max", 1.4))
	if month < 0:
		month = int(float(gs.today()) / 30.0)
	for g in GameData.goods:
		var vol := float(GameData.goods[g].get("volatility", 0.0))
		if vol <= 0.0:
			continue
		var st := good_state(gs, g)
		var rng := RandomNumberGenerator.new()
		rng.seed = int(gs.settings.get("seed", 0)) * 1009 + month * 31 + str(g).hash()
		var f := float(st.get("fluct", 1.0))
		f = f + (1.0 - f) * revert + rng.randfn(0.0, vol * mult)
		st["fluct"] = clampf(f, lo, hi)


## Registra una compra: pedido, cubierto por tus negocios, importado, autoabastecido,
## faltante por falta de inventario e ingresos. Alimenta precios y Estadísticas.
static func record_purchase(gs, good: String, qty: float, local: float, imported: float, self_q: float, shortage: float, revenue: float) -> void:
	var st := good_state(gs, good)
	st["demand"] = float(st["demand"]) + qty
	st["local"] = float(st["local"]) + local
	st["shortfall"] = float(st["shortfall"]) + shortage
	var m: Dictionary = gs.economy.get("month", {})
	m["local_sales_units"] = float(m.get("local_sales_units", 0.0)) + local
	var gm: Dictionary = m.get("goods", {})
	var row: Dictionary = gm.get(good, {})
	for pair in [["demand", qty], ["local", local], ["imported", imported], ["self", self_q], ["shortage", shortage], ["revenue", revenue]]:
		row[pair[0]] = float(row.get(pair[0], 0.0)) + float(pair[1])
	gm[good] = row
	m["goods"] = gm
	gs.economy["month"] = m


static func record_discretionary(gs, good: String, units: float, revenue: float) -> void:
	var m: Dictionary = gs.economy.get("month", {})
	var gm: Dictionary = m.get("goods", {})
	var row: Dictionary = gm.get(good, {})
	row["extra"] = float(row.get("extra", 0.0)) + units
	row["revenue"] = float(row.get("revenue", 0.0)) + revenue
	gm[good] = row
	m["goods"] = gm
	m["local_sales_units"] = float(m.get("local_sales_units", 0.0)) + units
	gs.economy["month"] = m


## Necesidades: personas-día con la necesidad cubierta total, parcial o sin cubrir.
static func record_need(gs, need: String, quality: float) -> void:
	var m: Dictionary = gs.economy.get("month", {})
	var nm: Dictionary = m.get("needs", {})
	var row: Dictionary = nm.get(need, {})
	var key := "met" if quality >= 0.99 else ("partial" if quality > 0.0 else "unmet")
	row[key] = float(row.get(key, 0.0)) + 1.0
	nm[need] = row
	m["needs"] = nm
	gs.economy["month"] = m


static func record_value(gs, key: String, amount: float) -> void:
	var m: Dictionary = gs.economy.get("month", {})
	m[key] = float(m.get(key, 0.0)) + amount
	gs.economy["month"] = m


static func total_money(gs) -> float:
	var m := maxf(0.0, float(gs.money))
	for c in gs.citizens.values():
		m += maxf(0.0, c.money)
	for b in gs.buildings:
		m += maxf(0.0, float(b.get("reserve", 0.0)))
	return m


static func total_credit(gs) -> float:
	var t := 0.0
	for l in gs.loans:
		t += float(l.get("balance", 0.0))
	return t


static func unemployment(gs) -> float:
	var today: int = gs.today()
	var adult := int(GameData.citizens.get("adult_age", 16))
	var retire := int(GameData.citizens.get("retirement_age", 65))
	var workforce := 0
	var unemployed := 0
	for c in gs.citizens.values():
		var age: int = c.age_years(today)
		if age < adult or age >= retire or gs.is_player(c.id):
			continue
		workforce += 1
		if c.job_id < 0:
			unemployed += 1
	return float(unemployed) / maxf(1.0, workforce)


static func stock_of(gs, good: String) -> float:
	var total := 0.0
	for b in MarketSim.sellers(good):
		total += float(b["inventory"].get(good, 0.0))
	return total


## Cierre mensual: ajusta precios por escasez/exceso e inflación.
static func monthly(gs) -> void:
	var pf: Dictionary = cfg().get("price_factor", {})
	var scarcity := 0.0
	var weight := 0.0
	for g in gs.economy.get("goods", {}):
		var st: Dictionary = gs.economy["goods"][g]
		var demand := float(st["demand"])
		if demand <= 0.0:
			continue
		var f := float(st["factor"])
		var short_ratio := float(st["shortfall"]) / demand
		var stock := stock_of(gs, g)
		var daily_demand := demand / 30.0
		if MarketSim.sellers(g).is_empty():
			f += (1.0 - f) * 0.2  # Sin productores locales: economía de subsistencia, precio normal.
		elif short_ratio > float(pf.get("shortage_threshold", 0.15)):
			f *= 1.0 + float(pf.get("shortage_step", 0.04)) * minf(1.0, short_ratio * 2.0)
		elif stock > daily_demand * float(pf.get("surplus_stock_days", 5)):
			f *= 1.0 - float(pf.get("surplus_step", 0.03))
		else:
			f += (1.0 - f) * 0.05
		# Con importación disponible el precio no supera al importado.
		var imp := float(GameData.goods.get(g, {}).get("import_price", 0.0))
		var base := float(GameData.goods.get(g, {}).get("base_price", 1.0))
		var cap := float(pf.get("max", 2.2))
		if imp > 0.0 and base > 0.0:
			cap = minf(cap, imp / base * 1.1)
		st["factor"] = clampf(f, float(pf.get("min", 0.5)), cap)
		scarcity += (float(st["factor"]) - 1.0) * demand
		weight += demand
		st["demand"] = 0.0
		st["local"] = 0.0
		st["shortfall"] = 0.0
	scarcity = scarcity / weight if weight > 0.0 else 0.0
	# Inflación: dinero y crédito que crecen más rápido que la producción, más escasez.
	var inf_cfg: Dictionary = cfg().get("inflation", {})
	var money := total_money(gs)
	var credit := total_credit(gs)
	var output := float(gs.economy.get("month", {}).get("local_sales_units", 0.0)) + float(gs.citizens.size()) * 30.0
	var g_money := (money - float(gs.economy.get("money_prev", money))) / maxf(1.0, float(gs.economy.get("money_prev", money)))
	var g_output := (output - float(gs.economy.get("output_prev", output))) / maxf(1.0, float(gs.economy.get("output_prev", output)))
	var g_credit := (credit - float(gs.economy.get("credit_prev", credit))) / maxf(100.0, money)
	var raw := float(inf_cfg.get("base_monthly", 0.0012))
	raw += float(inf_cfg.get("money_weight", 0.25)) * clampf(g_money - g_output, -0.2, 0.2)
	raw += float(inf_cfg.get("credit_weight", 0.4)) * g_credit
	raw += float(inf_cfg.get("scarcity_weight", 0.02)) * scarcity
	raw = clampf(raw, float(inf_cfg.get("min_monthly", -0.01)), float(inf_cfg.get("max_monthly", 0.02)))
	var s := float(inf_cfg.get("smoothing", 0.5))
	var infl := float(gs.economy.get("inflation_month", 0.0)) * s + raw * (1.0 - s)
	gs.economy["inflation_month"] = infl
	gs.economy["price_level"] = clampf(float(gs.economy.get("price_level", 1.0)) * (1.0 + infl),
			float(inf_cfg.get("min_level", 0.5)), float(inf_cfg.get("max_level", 50.0)))
	update_fluctuations(gs)
	ShopSim.monthly(gs)
	EnergySim.monthly(gs)
	gs.economy["money_prev"] = money
	gs.economy["output_prev"] = output
	gs.economy["credit_prev"] = credit
	var closing: Dictionary = gs.economy.get("month", {})
	var prices := {}
	for g in GameData.goods:
		prices[g] = market_price(gs, g)
	closing["prices"] = prices
	gs.economy["last_month"] = closing
	var hist: Array = gs.economy.get("stats_hist", [])
	hist.append({"day": gs.today(), "goods": closing.get("goods", {}), "prices": prices})
	if hist.size() > 24:
		hist.pop_front()
	gs.economy["stats_hist"] = hist
	gs.economy["month"] = {}


static func annual_inflation(gs) -> float:
	return pow(1.0 + float(gs.economy.get("inflation_month", 0.0)), 12.0) - 1.0


# --- Patrimonio y clasificación ------------------------------------------------------------

static func property_value(gs, b: Dictionary) -> float:
	if b["status"] == "cerrado":
		return BusinessSim.period_value(b, "total", "obras") * 0.3
	if RealEstateSim.has_units(b):
		return RealEstateSim.owned_value(gs, b)   # Bienes raíces: solo las unidades que aún son tuyas.
	if Housing.is_home(b):
		return float(b.get("sale_price", 0.0)) * float(gs.economy.get("price_level", 1.0))
	return BusinessSim.period_value(b, "total", "obras") * float(cfg().get("property_value_ratio", 0.7))


static func player_assets(gs) -> float:
	var v := 0.0
	for b in gs.player_buildings():
		v += property_value(gs, b)
	return v


static func player_debt(gs) -> float:
	var d := 0.0
	for l in gs.loans:
		if str(l["borrower"]) == "jugador":
			d += float(l["balance"])
	return d


static func loans_granted(gs) -> float:
	var d := 0.0
	for l in gs.loans:
		# Solo la cartera de tus bancos (los bancos NPC y el externo no son tuyos).
		if str(l["lender"]).is_valid_int() and str(l["borrower"]) != "jugador":
			d += float(l["balance"])
	return d


static func net_worth(gs) -> float:
	return gs.money + player_assets(gs) + loans_granted(gs) - player_debt(gs)


## "rentable", "equilibrio" o "deficitaria" según el margen del mes anterior.
static func classify(b: Dictionary) -> String:
	var inc := BusinessSim.period_value(b, "last_month", "ventas") + BusinessSim.period_value(b, "last_month", "alquileres") + BusinessSim.period_value(b, "last_month", "intereses")
	var profit := BusinessSim.period_profit(b, "last_month")
	if inc <= 0.0 and profit >= 0.0:
		return "sin datos"
	var margin := profit / maxf(1.0, inc)
	var c: Dictionary = cfg().get("classification", {})
	if margin > float(c.get("profitable_margin", 0.05)):
		return "rentable"
	if margin >= float(c.get("breakeven_margin", -0.05)):
		return "equilibrio"
	return "deficitaria"
