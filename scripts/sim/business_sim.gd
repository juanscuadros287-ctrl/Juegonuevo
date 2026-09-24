class_name BusinessSim
extends RefCounted
## Negocios del jugador: producción, salarios, mantenimiento, contabilidad,
## contratación manual y renuncias. Parámetros en data/businesses.json.

const LEDGER_KEYS := ["ventas", "alquileres", "intereses", "subsidios", "salarios", "mantenimiento", "insumos", "impuestos", "multas", "reparaciones", "robos", "incobrables", "obras"]
const INCOME_KEYS := ["ventas", "alquileres", "intereses", "subsidios"]
## Movimientos que no son ingreso ni gasto (inversión y capital prestado).
const NON_PNL_KEYS := ["obras", "prestado"]


# --- Consultas -----------------------------------------------------------------------

static func is_business(b: Dictionary) -> bool:
	return str(GameData.building_def(str(b.get("type", ""))).get("category", "")) == "negocio"


## Negocios que cuentan para el límite de la oficina (los servicios públicos no cuentan).
static func business_count(gs) -> int:
	var n := 0
	for b in gs.buildings:
		if gs.owned_by_player(b) and is_business(b) and counts_for_limit(gs.building_def(b)):
			n += 1
	return n


## Servicios públicos e infraestructura de transporte no cuentan para el límite de la oficina.
static func counts_for_limit(def: Dictionary) -> bool:
	return not def.has("service") and not bool(def.get("trade_infra", false)) and str(def.get("product", "")) != "transporte"


static func max_businesses(gs) -> int:
	var slots := int(GameData.game.get("base_business_slots", 2))
	var best := 0
	for b in gs.buildings:
		if gs.owned_by_player(b) and b["type"] == "oficina" and b["status"] != "construccion":
			best = maxi(best, int(gs.level_def(b).get("business_slots", 0)))
	return slots + best


static func office_discount(gs) -> float:
	var best := 0.0
	for b in gs.buildings:
		if gs.owned_by_player(b) and b["type"] == "oficina" and b["status"] != "construccion":
			best = maxf(best, float(gs.level_def(b).get("upkeep_discount", 0.0)))
	return best


static func default_price(gs, def: Dictionary) -> float:
	var g: Dictionary = GameData.goods.get(str(def.get("product", "")), {})
	return snappedf(float(g.get("base_price", 0.0)) * gs.price_mult() * 1.1, 0.01)


static func max_price(gs, b: Dictionary) -> float:
	var def: Dictionary = gs.building_def(b)
	var g: Dictionary = GameData.goods.get(str(def.get("product", "")), {})
	var legal: Dictionary = GameData.legal_types.get(str(b.get("legal", "sas")), {})
	return float(g.get("base_price", 1.0)) * gs.price_mult() * float(legal.get("max_price_factor", 10.0))


static func set_price(gs, b: Dictionary, price: float) -> void:
	b["price"] = clampf(snappedf(price, 0.01), 0.01, max_price(gs, b))


## Productividad de un empleado (≈1 = normal).
static func productivity(c: Citizen, skill: String) -> float:
	var s := float(c.skills.get(skill, 0.0))
	var p := 0.6 + s / 100.0 * 0.8 + minf(c.experience, 20.0) * 0.01 + c.education * 0.1
	if c.profession != "" and str(GameData.professions.get("professions", {}).get(c.profession, {}).get("skill", "")) == skill:
		p *= 1.3
	p *= clampf(c.health / 100.0, 0.3, 1.0)
	p *= 0.75 + c.happiness / 100.0 * 0.5
	return p


static func asked_wage(gs, c: Citizen, type_id: String) -> float:
	var def := GameData.building_def(type_id)
	var s := float(c.skills.get(str(def.get("skill", "")), 0.0))
	var w := float(def.get("base_wage", 2.0)) * (0.8 + s / 200.0 + minf(c.experience, 30.0) * 0.01 + c.education * 0.1 + (0.4 if c.profession != "" else 0.0))
	return snappedf(w * gs.price_mult(), 0.05)


## Producción diaria estimada con los empleados actuales.
static func expected_output(gs, b: Dictionary) -> float:
	var def: Dictionary = gs.building_def(b)
	var ld: Dictionary = gs.level_def(b)
	var total := 0.0
	for c in gs.employees_of(int(b["id"])):
		if c.job_kind == "empleo" and not c.sick:
			total += productivity(c, str(def.get("skill", "")))
	total *= float(ld.get("prod_per_worker", 1.0))
	if def.get("seasonal", false):
		total *= float(WeatherSim.season_data(gs).get("farming", 1.0)) * float(WeatherSim.weather_data(gs).get("farming", 1.0)) * EventsSim.mult(gs, "farming")
	total *= float(def.get("resource_bonus", {}).get(str(gs.settings.get("map_type", "")), 1.0))
	total *= RegionSim.region_mult(gs, b)   # Fase 6: recursos de la región.
	total *= TechSim.mult(gs, "production", str(def.get("product", "")))
	return total


static func storage_cap(gs, b: Dictionary) -> float:
	var ld: Dictionary = gs.level_def(b)
	return float(ld.get("prod_per_worker", 1.0)) * float(ld.get("jobs", 1)) * 20.0


# --- Contabilidad ---------------------------------------------------------------------

static func ledger_add(b: Dictionary, key: String, amount: float) -> void:
	var led: Dictionary = b["ledger"]
	for period in ["month", "total"]:
		var p: Dictionary = led[period]
		p[key] = float(p.get(key, 0.0)) + amount


static func period_profit(b: Dictionary, period: String) -> float:
	var p: Dictionary = b["ledger"].get(period, {})
	var profit := 0.0
	for k in p:
		if k in INCOME_KEYS:
			profit += float(p[k])
		elif not k in NON_PNL_KEYS:
			profit -= float(p[k])
	return profit


static func period_value(b: Dictionary, period: String, key: String) -> float:
	return float(b["ledger"].get(period, {}).get(key, 0.0))


static func is_nonprofit(b: Dictionary) -> bool:
	return not bool(GameData.legal_types.get(str(b.get("legal", "sas")), {}).get("profits_to_owner", true))


## Ingreso de un edificio del jugador (ventas o alquiler).
static func earn(gs, b: Dictionary, amount: float, key := "ventas") -> void:
	if NpcBusinessSim.book(gs, b, amount, key, true):
		return  # Libre mercado: empresa NPC (caja propia) u obra del gobierno (tesoro).
	ledger_add(b, key, amount)
	if is_nonprofit(b):
		b["reserve"] = float(b["reserve"]) + amount
	else:
		gs.add_money(amount)


## Gasto de un edificio del jugador. Las fundaciones pagan primero con su reserva.
static func pay(gs, b: Dictionary, amount: float, key: String) -> void:
	if NpcBusinessSim.book(gs, b, amount, key, false):
		return  # Libre mercado: empresa NPC (caja propia) u obra del gobierno (tesoro).
	ledger_add(b, key, amount)
	var left := amount
	if is_nonprofit(b):
		var use := minf(float(b["reserve"]), left)
		b["reserve"] = float(b["reserve"]) - use
		left -= use
	if left > 0.0:
		gs.add_money(-left)


# --- Simulación ------------------------------------------------------------------------

static func produce(gs) -> void:
	var points := 0.0
	var pm: float = gs.price_mult()
	var discount := office_discount(gs)
	for b in gs.buildings:
		if not gs.owned_by_player(b) or b["status"] == "construccion" or b["status"] == "cerrado":
			continue
		var def: Dictionary = gs.building_def(b)
		var ld: Dictionary = gs.level_def(b)
		pay(gs, b, float(ld.get("upkeep", 0.0)) * pm * (1.0 - discount), "mantenimiento")
		if def.get("category", "") != "negocio":
			continue
		var skill := str(def.get("skill", ""))
		for c in gs.employees_of(int(b["id"])):
			if c.job_kind != "empleo":
				continue
			c.money += c.wage
			pay(gs, b, c.wage, "salarios")
			c.experience += 1.0 / 365.0
			c.skills[skill] = minf(100.0, float(c.skills.get(skill, 0.0)) + 0.02)
		if b["status"] != "activo":
			continue  # En mejora: no produce ni factura.
		var product := str(def.get("product", ""))
		if product == "credito" or product == "educacion" or product == "servicio" or product == "transporte":
			continue
		if product == "investigacion":
			TechSim.add_points(gs, TechSim.lab_output(gs, b) / TechSim.mult(gs, "research"))
			continue
		if bool(b.get("auto_price", false)):
			b["price"] = clampf(snappedf(EconomySim.market_price(gs, product) * (1.0 + float(b.get("markup", 0.0))), 0.01), 0.01, max_price(gs, b))
		var out := expected_output(gs, b)
		if product == "construccion":
			points += out
			continue
		var unit_cost := float(ld.get("unit_cost", 0.0)) * pm
		if LogisticsSim.uses_chain(def, ld):
			# Fase 6: recetas ("inputs" del almacén), yacimientos y "output": "warehouse".
			out = LogisticsSim.produce_chain(gs, b, product, out)
			if unit_cost > 0.0 and out > 0.0:
				pay(gs, b, out * unit_cost, "insumos")
			continue
		var inv: Dictionary = b["inventory"]
		var storable := bool(GameData.goods.get(product, {}).get("storable", true))
		if storable:
			out = minf(out, maxf(0.0, storage_cap(gs, b) - float(inv.get(product, 0.0))))
		if unit_cost > 0.0 and out > 0.0:
			pay(gs, b, out * unit_cost, "insumos")
		inv[product] = float(inv.get(product, 0.0)) + out
	gs.set_meta("construction_points", points)


static func end_day(gs) -> void:
	for b in gs.buildings:
		if not gs.owned_by_player(b):
			continue
		var product := str(gs.building_def(b).get("product", ""))
		if product != "" and not bool(GameData.goods.get(product, {}).get("storable", true)):
			b["inventory"][product] = 0.0


static func monthly(gs) -> void:
	var bk: Dictionary = GameData.economy.get("bankruptcy", {})
	for b in gs.buildings:
		if not gs.owned_by_player(b):
			continue
		var led: Dictionary = b["ledger"]
		led["last_month"] = led["month"]
		led["month"] = {}
		if not is_business(b) or b["status"] != "activo":
			continue
		if period_profit(b, "last_month") < 0.0:
			b["loss_months"] = int(b.get("loss_months", 0)) + 1
			var n := int(b["loss_months"])
			if n == int(bk.get("warn_months", 3)):
				gs.notify("%s lleva %d meses perdiendo dinero: ajusta precios, personal o ciérralo." % [gs.building_label(b), n], "jugador")
			if n >= int(bk.get("loss_months", 6)) and gs.money < 0.0:
				go_bankrupt(gs, b)
		else:
			b["loss_months"] = 0
	# Renuncias por salario bajo y jubilación.
	var ratio := float(GameData.citizens.get("quit_wage_ratio", 0.8))
	var chance := float(GameData.citizens.get("quit_monthly_chance", 0.3))
	var retire := int(GameData.citizens.get("retirement_age", 65))
	var today: int = gs.today()
	for c in gs.citizens.values():
		if c.job_kind != "empleo":
			continue
		var b: Dictionary = gs.get_building(c.job_id)
		if b.is_empty():
			fire(gs, c, "")
			continue
		if c.age_years(today) >= retire:
			fire(gs, c, "%s se jubiló de %s." % [c.full_name(), gs.building_label(b)])
		elif c.wage < asked_wage(gs, c, str(b["type"])) * ratio and gs.rng.randf() < chance:
			fire(gs, c, "%s renunció a %s por salario bajo." % [c.full_name(), gs.building_label(b)])


# --- Personal ---------------------------------------------------------------------------

## Candidatos: adultos sin empleo formal (incluye jornaleros), ordenados por habilidad.
static func candidates(gs, b: Dictionary) -> Array:
	var skill := str(gs.building_def(b).get("skill", ""))
	var today: int = gs.today()
	var adult := int(GameData.citizens.get("adult_age", 16))
	var retire := int(GameData.citizens.get("retirement_age", 65))
	var out := []
	for c in gs.citizens.values():
		if c.job_kind == "empleo" or c.job_kind == "dueño" or gs.is_player(c.id):   # Libre mercado: el dueño NPC atiende su negocio.
			continue
		var age: int = c.age_years(today)
		if age < adult or age >= retire:
			continue
		out.append(c)
	out.sort_custom(func(a, bb): return float(a.skills.get(skill, 0)) + a.experience > float(bb.skills.get(skill, 0)) + bb.experience)
	return out


static func hire(gs, b: Dictionary, c: Citizen, wage: float) -> String:
	var jobs := int(gs.level_def(b).get("jobs", 0))
	var current := 0
	for e in gs.employees_of(int(b["id"])):
		if e.job_kind == "empleo":
			current += 1
	if current >= jobs:
		return "No hay vacantes (%d/%d). Mejora el negocio para más empleos." % [current, jobs]
	if c.job_kind == "empleo":
		return "%s ya tiene empleo." % c.full_name()
	var min_edu := int(gs.level_def(b).get("min_education", 0))
	if c.education < min_edu:
		return "%s no está calificado(a): se requiere educación %s." % [c.full_name(), GameData.education_label(min_edu)]
	if wage < GovSim.min_wage(gs):
		return "El salario mínimo legal es %s/día." % Fmt.money2(GovSim.min_wage(gs))
	var prof := str(gs.level_def(b).get("required_profession", ""))
	if prof != "" and c.profession != prof:
		return "%s no es %s: este nivel exige ese título universitario." % [c.full_name(), GameData.profession_label(prof).to_lower()]
	c.job_id = int(b["id"])
	c.job_kind = "empleo"
	c.wage = maxf(0.1, wage)
	gs.notify("Contrataste a %s en %s (%s/día)." % [c.full_name(), gs.building_label(b), Fmt.money2(c.wage)], "negocio")
	EventBus.citizens_moved.emit()
	return ""


static func fire(gs, c: Citizen, message := "") -> void:
	c.job_id = -1
	c.job_kind = ""
	c.wage = 0.0
	c.happiness = maxf(0.0, c.happiness - 5.0)
	if message != "":
		gs.notify(message, "negocio")
	EventBus.citizens_moved.emit()


static func job_label(gs, c: Citizen) -> String:
	if c.job_id < 0:
		return "Autoabastecimiento (sin empleo)"
	var b: Dictionary = gs.get_building(c.job_id)
	if b.is_empty():
		return "—"
	if c.job_kind == "obra":
		return "Jornalero en obra: %s (%s/día)" % [gs.building_label(b), Fmt.money2(c.wage)]
	return "%s (%s/día)" % [gs.building_label(b), Fmt.money2(c.wage)]


# --- Quiebra y reapertura ----------------------------------------------------------------------

## Quiebra: cierra el negocio, despide al personal y remata el inventario.
static func go_bankrupt(gs, b: Dictionary) -> void:
	var liq := float(GameData.economy.get("bankruptcy", {}).get("inventory_liquidation", 0.5))
	var recovered := 0.0
	for g in b["inventory"]:
		recovered += float(b["inventory"][g]) * float(GameData.goods.get(g, {}).get("base_price", 0.0)) * gs.price_mult() * liq
		b["inventory"][g] = 0.0
	for c in gs.employees_of(int(b["id"])):
		if c.job_kind == "empleo":
			fire(gs, c)
	b["status"] = "cerrado"
	b["loss_months"] = 0
	gs.add_money(recovered)
	gs.count("bankruptcies")
	gs.notify("QUIEBRA: %s cerró tras meses de pérdidas. Remate de inventario: %s." % [gs.building_label(b), Fmt.money(recovered)], "jugador")
	EventBus.building_changed.emit(int(b["id"]))


static func reopen_cost(gs, b: Dictionary) -> float:
	return float(gs.level_def(b).get("cost", 0)) * 0.2 * gs.price_mult()


static func reopen(gs, b: Dictionary) -> String:
	if b["status"] != "cerrado" or not gs.owned_by_player(b):
		return "No está cerrado"
	var cost := reopen_cost(gs, b)
	if gs.money < cost:
		return "Necesitas %s" % Fmt.money(cost)
	gs.add_money(-cost)
	ledger_add(b, "obras", cost)
	b["status"] = "activo"
	gs.notify("Reabriste %s." % gs.building_label(b), "negocio")
	EventBus.building_changed.emit(int(b["id"]))
	return ""
