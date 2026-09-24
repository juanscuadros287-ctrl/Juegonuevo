class_name NpcBusinessSim
extends RefCounted
## Libre mercado — empresarios NPC del pueblo del jugador.
## Un ciudadano con ahorros (propios y de su familia, o un préstamo de TU banco si existe) y
## habilidad abre un negocio donde hay demanda sin cubrir ("nadie vende X": la gente se
## autoabastece o importa). El negocio es un edificio real: owner "ciudadano", owner_id, "npc": true.
##   - Su caja es b["reserve"] (cuenta en EconomySim.total_money). Ingresos y gastos que pasan por
##     BusinessSim.earn/pay se desvían aquí (book): nunca tocan el dinero del jugador.
##   - Se construye con la obra normal (ConstructionSim.daily, jornaleros pagados de su caja).
##   - Contrata, paga sueldos, mantenimiento, insumos e impuestos; reparte dividendos al dueño.
##   - Compite con tus negocios en MarketSim (mismo orden por calidad/precio).
##   - Quiebra si pierde dinero meses seguidos; al morir el dueño lo hereda su familia; sin
##     herederos lo vende el Estado (el dinero va al tesoro) o cierra.
##   - Puedes ofrecer comprarlo: el dueño acepta o rechaza unos días después.

const STATE_BUILDING := "obra"
const STATE_OPEN := "abierto"
const STATE_FOR_SALE := "en_venta"

static var _staff: Dictionary = {}     # id edificio -> Array[Citizen] (se recalcula cada día)
static var _terrain_check: Callable = Callable()


static func cfg() -> Dictionary:
	return FreeMarketSim.cfg().get("npc", {})


## El mundo 3D registra su verificación de terreno (agua/pendiente). Sin mundo se usa el llano del pueblo.
static func set_terrain_check(c: Callable) -> void:
	_terrain_check = c


static func is_npc(b: Dictionary) -> bool:
	return bool(b.get("npc", false)) and str(b.get("owner", "")) == "ciudadano"


static func npc_buildings(gs) -> Array:
	return gs.buildings.filter(func(b): return is_npc(b))


## Edificios cuyo dinero NO es del jugador: empresas NPC (caja propia) y obras del gobierno
## construidas por él mismo (tesoro). Devuelve true si el movimiento quedó registrado.
static func book(gs, b: Dictionary, amount: float, key: String, income: bool) -> bool:
	if is_npc(b):
		BusinessSim.ledger_add(b, key, amount)
		b["reserve"] = float(b.get("reserve", 0.0)) + (amount if income else -amount)
		return true
	if GovPlansSim.is_gov_funded(b):
		BusinessSim.ledger_add(b, key, amount)
		GovSim.add_treasury(gs, amount if income else -amount)
		return true
	return false


# --- Personal (índice diario) ---------------------------------------------------------------------

static func staff_index(gs) -> Dictionary:
	_staff = {}
	for c in gs.citizens.values():
		if c.job_kind != "empleo" or c.job_id < 0:
			continue
		if not _staff.has(c.job_id):
			_staff[c.job_id] = []
		_staff[c.job_id].append(c)
	return _staff


static func staff_of(b: Dictionary) -> Array:
	return _staff.get(int(b["id"]), [])


static func candidates(gs, skill: String) -> Array:
	var today: int = gs.today()
	var adult := int(GameData.citizens.get("adult_age", 16))
	var retire := int(GameData.citizens.get("retirement_age", 65))
	var out := []
	for c in gs.citizens.values():
		if c.job_id >= 0 or gs.is_player(c.id) or c.prison_until >= 0 or c.school_id >= 0:
			continue
		var age: int = c.age_years(today)
		if age < adult or age >= retire:
			continue
		out.append(c)
	out.sort_custom(func(a, b): return float(a.skills.get(skill, 0.0)) + a.experience > float(b.skills.get(skill, 0.0)) + b.experience)
	return out


## Contratación silenciosa (NPC y gobierno): sin notificación al jugador.
static func hire_silent(gs, b: Dictionary, c: Citizen) -> void:
	c.job_id = int(b["id"])
	c.job_kind = "empleo"
	c.wage = maxf(GovSim.min_wage(gs), BusinessSim.asked_wage(gs, c, str(b["type"])))
	if not _staff.has(c.job_id):
		_staff[c.job_id] = []
	_staff[c.job_id].append(c)


## El dueño trabaja en su propio negocio (sin sueldo: vive de las ganancias).
static func owner_works(gs, b: Dictionary) -> bool:
	var o: Citizen = gs.citizens.get(int(b.get("owner_id", -1)))
	return o != null and o.job_id == int(b["id"]) and o.job_kind == "dueño"


static func _owner_joins(gs, b: Dictionary) -> void:
	var o: Citizen = gs.citizens.get(int(b.get("owner_id", -1)))
	if o == null or gs.is_player(o.id) or o.job_id >= 0 or o.prison_until >= 0 or o.school_id >= 0:
		return
	var age: int = o.age_years(gs.today())
	if age < int(GameData.citizens.get("adult_age", 16)) or age >= int(GameData.citizens.get("retirement_age", 65)):
		return
	o.job_id = int(b["id"])
	o.job_kind = "dueño"
	o.wage = 0.0


static func _owner_leaves(gs, b: Dictionary) -> void:
	for c in gs.citizens.values():
		if c.job_id == int(b["id"]) and c.job_kind == "dueño":
			c.job_id = -1
			c.job_kind = ""
			c.wage = 0.0


static func release(gs, c: Citizen) -> void:
	if _staff.has(c.job_id):
		_staff[c.job_id].erase(c)
	c.job_id = -1
	c.job_kind = ""
	c.wage = 0.0


static func fill_jobs(gs, b: Dictionary, target: int) -> int:
	var skill := str(gs.building_def(b).get("skill", ""))
	var min_edu := int(gs.level_def(b).get("min_education", 0))
	var hired := 0
	var have := staff_of(b).size()
	if have >= target:
		return 0
	for c in candidates(gs, skill):
		if have + hired >= target:
			break
		if c.education < min_edu:
			continue
		hire_silent(gs, b, c)
		hired += 1
	return hired


# --- Producción diaria -------------------------------------------------------------------------------

static func _output(gs, b: Dictionary, emps: Array) -> float:
	var def: Dictionary = gs.building_def(b)
	var ld: Dictionary = gs.level_def(b)
	var total := 0.0
	var skill := str(def.get("skill", ""))
	for c in emps:
		if not c.sick:
			total += BusinessSim.productivity(c, skill)
	total *= float(ld.get("prod_per_worker", 1.0))
	if def.get("seasonal", false):
		total *= float(WeatherSim.season_data(gs).get("farming", 1.0)) * float(WeatherSim.weather_data(gs).get("farming", 1.0)) * EventsSim.mult(gs, "farming")
	total *= float(def.get("resource_bonus", {}).get(str(gs.settings.get("map_type", "")), 1.0))
	total *= TechSim.mult(gs, "production", str(def.get("product", "")))
	return total


## Paga desde la caja del negocio; si no alcanza, el dueño pone de su bolsillo. Devuelve lo pagado.
static func _spend(gs, b: Dictionary, amount: float, key: String, allow_owner := true) -> float:
	if amount <= 0.0:
		return 0.0
	var cash := maxf(0.0, float(b.get("reserve", 0.0)))
	var paid := minf(cash, amount)
	if paid < amount and allow_owner:
		var owner: Citizen = gs.citizens.get(int(b.get("owner_id", -1)))
		if owner != null and not gs.is_player(owner.id):
			var extra := minf(maxf(0.0, owner.money), amount - paid)
			owner.money -= extra
			b["reserve"] = float(b["reserve"]) + extra
			paid += extra
	b["reserve"] = float(b["reserve"]) - paid
	BusinessSim.ledger_add(b, key, paid)
	return paid


## Proveedores locales: vecinos sin empleo que venden lo que cultivan, recogen o reparan.
static var _suppliers: Array = []


## Paga a proveedores del pueblo (el dinero de insumos y mantenimiento se queda en el pueblo).
static func _pay_local(gs, amount: float) -> void:
	if amount <= 0.0:
		return
	if _suppliers.is_empty():
		GovSim.add_treasury(gs, amount)   # Sin vecinos que vendan: lo cobra el mercado municipal.
		return
	var n := mini(3, _suppliers.size())
	var start := int(floorf(FreeMarketSim.rf(gs) * _suppliers.size()))
	for i in range(n):
		var c: Citizen = _suppliers[(start + i) % _suppliers.size()]
		c.money += amount / n


static func produce(gs) -> void:
	staff_index(gs)
	_suppliers = []
	var today: int = gs.today()
	var adult := int(GameData.citizens.get("adult_age", 16))
	for c in gs.citizens.values():
		if c.job_id < 0 and not gs.is_player(c.id) and c.prison_until < 0 and c.age_years(today) >= adult:
			_suppliers.append(c)
	var pm: float = gs.price_mult()
	for b in gs.buildings:
		if not is_npc(b) or str(b["status"]) != "activo":
			continue
		var def: Dictionary = gs.building_def(b)
		var ld: Dictionary = gs.level_def(b)
		var emps: Array = staff_of(b)
		var workers: Array = emps.duplicate()
		if owner_works(gs, b):
			workers.append(gs.citizens[int(b["owner_id"])])
		# Sueldos: si la caja no alcanza, quedan impagos y la gente renuncia.
		var unpaid := false
		for c in emps:
			var paid := _spend(gs, b, c.wage, "salarios")
			c.money += paid
			if paid + 0.0001 < c.wage:
				unpaid = true
		b["unpaid_days"] = int(b.get("unpaid_days", 0)) + 1 if unpaid else 0
		_pay_local(gs, _spend(gs, b, float(ld.get("upkeep", 0.0)) * pm, "mantenimiento", false))
		var product := str(def.get("product", ""))
		if product == "" or not GameData.goods.has(product):
			continue
		b["price"] = clampf(snappedf(EconomySim.market_price(gs, product) * (1.0 + float(b.get("markup", 0.08))), 0.01), 0.01, BusinessSim.max_price(gs, b))
		var out := _output(gs, b, workers)
		var inv: Dictionary = b["inventory"]
		if bool(GameData.goods.get(product, {}).get("storable", true)):
			out = minf(out, maxf(0.0, BusinessSim.storage_cap(gs, b) - float(inv.get(product, 0.0))))
		# Insumos comprados por contrato (p. ej. harina para la panadería) reemplazan parte del costo.
		var unit_cost := float(ld.get("unit_cost", 0.0)) * pm
		var covered := 0.0
		for g in inv:
			if str(g) == product or out - covered <= 0.0:
				continue
			var use := minf(float(inv[g]), (out - covered) * 0.5)
			if use > 0.0:
				inv[g] = float(inv[g]) - use
				covered += use * 2.0
		var cost_units := maxf(0.0, out - covered)
		if unit_cost > 0.0 and cost_units > 0.0:
			var cash := maxf(0.0, float(b["reserve"]))
			if cash < cost_units * unit_cost:
				cost_units = cash / unit_cost
				out = covered + cost_units
			_pay_local(gs, _spend(gs, b, cost_units * unit_cost, "insumos", false))
		inv[product] = float(inv.get(product, 0.0)) + maxf(0.0, out)


# --- Día --------------------------------------------------------------------------------------------------

static func daily(gs) -> void:
	for b in npc_buildings(gs):
		# Bienes no almacenables (ocio) se pierden al final del día.
		var product := str(gs.building_def(b).get("product", ""))
		if product != "" and not bool(GameData.goods.get(product, {}).get("storable", true)):
			b["inventory"][product] = 0.0
		if str(b.get("npc_state", "")) == STATE_BUILDING and str(b["status"]) == "activo":
			_on_opened(gs, b)
		if int(b.get("unpaid_days", 0)) >= 7:
			var emps: Array = staff_of(b).duplicate()
			if not emps.is_empty():
				var c: Citizen = emps[emps.size() - 1]
				release(gs, c)
				gs.notify("%s renunció a %s: no le pagaban." % [c.full_name(), gs.building_label(b)], "info")
			b["unpaid_days"] = 0
		_check_owner(gs, b)
	_resolve_purchase_offers(gs)


static func _on_opened(gs, b: Dictionary) -> void:
	b["npc_state"] = STATE_OPEN
	var jobs := int(gs.level_def(b).get("jobs", 1))
	_owner_joins(gs, b)
	# Empieza pequeño: el dueño atiende; contrata cuando las ventas lo piden (ver _monthly_accounts).
	fill_jobs(gs, b, 0 if owner_works(gs, b) else mini(1, jobs))
	var owner_name: String = gs.person_name(int(b.get("owner_id", -1)))
	gs.notify("%s abrió %s: competirá por los clientes del pueblo." % [owner_name, gs.building_label(b)], "negocio")
	FreeMarketSim.log_event(gs, "Abrió %s (%s)." % [gs.building_label(b), owner_name])
	EventBus.building_changed.emit(int(b["id"]))


# --- Aperturas ----------------------------------------------------------------------------------------------

static func _year_key(gs) -> String:
	return str(TimeManager.year())


static func openings_this_year(gs) -> int:
	return int(gs.market.get("npc", {}).get("openings", {}).get(_year_key(gs), 0))


static func max_openings(gs) -> int:
	return int(cfg().get("max_openings_per_year", {}).get(str(gs.era()), 1))


## Demanda sin cubrir del último mes: {bien: {"uncovered", "demand"}} (importado + parte del autoabastecimiento).
static func unmet_demand(gs) -> Dictionary:
	var last: Dictionary = gs.economy.get("last_month", {})
	var gm: Dictionary = last.get("goods", {})
	var w := float(cfg().get("self_supply_weight", 0.35))
	var out := {}
	for g in gm:
		var row: Dictionary = gm[g]
		var demand := float(row.get("demand", 0.0))
		if demand <= 0.0:
			continue
		out[g] = {"uncovered": float(row.get("imported", 0.0)) + float(row.get("self", 0.0)) * w + float(row.get("shortage", 0.0)) * 0.5,
			"demand": demand}
	return out


static func type_for_good(gs, good: String) -> Array:
	var out := []
	for t in cfg().get("types", []):
		var type_id := str(t)
		var def := GameData.building_def(type_id)
		if str(def.get("product", "")) != good:
			continue
		if ConstructionSim.level_block_reason(gs, type_id, 1) != "":
			continue
		out.append(type_id)
	return out


## Capital necesario para abrir: parte de la obra + reserva para sueldos.
static func capital_needed(gs, type_id: String) -> Dictionary:
	var ld := GameData.level_def(type_id, 1)
	var def := GameData.building_def(type_id)
	var pm: float = gs.price_mult()
	var build := float(ld.get("cost", 300)) * pm * float(cfg().get("capital_factor", 0.7))
	var crew_wages := float(int(ld.get("build_days", 10)) * int(ld.get("workers", 2))) * float(GameData.game.get("construction_day_wage", 2.2)) * pm
	var jobs := maxi(1, int(ceil(int(ld.get("jobs", 1)) * 0.5)))
	var reserve := float(def.get("base_wage", 2.0)) * pm * jobs * float(cfg().get("wage_reserve_days", 20))
	return {"build": build, "crew": crew_wages, "reserve": reserve, "total": build + crew_wages + reserve}


static func family_of(gs, c: Citizen) -> Array:
	var today: int = gs.today()
	var adult := int(GameData.citizens.get("adult_age", 16))
	var out: Array = [c]
	if c.spouse_id >= 0 and gs.citizens.has(c.spouse_id):
		out.append(gs.citizens[c.spouse_id])
	for kid_id in c.children_ids:
		if gs.citizens.has(kid_id):
			var k: Citizen = gs.citizens[kid_id]
			if k.age_years(today) >= adult and not out.has(k):
				out.append(k)
	for pid in c.parent_ids:
		if gs.citizens.has(pid) and not out.has(gs.citizens[pid]):
			out.append(gs.citizens[pid])
	return out.filter(func(m): return not gs.is_player(m.id))


static func family_savings(gs, c: Citizen) -> float:
	var share := float(cfg().get("family_pool_share", 0.8))
	var total := 0.0
	for m in family_of(gs, c):
		total += maxf(0.0, m.money) * (1.0 if m == c else share)
	return total


static func _owns_npc(gs, cid: int) -> bool:
	for b in gs.buildings:
		if is_npc(b) and int(b.get("owner_id", -1)) == cid:
			return true
	return false


static func _player_family(gs, c: Citizen) -> bool:
	var p: Citizen = gs.player_citizen()
	if p == null:
		return false
	return c.id == p.id or c.id == p.spouse_id or p.children_ids.has(c.id) or p.parent_ids.has(c.id) or c.home_id == p.home_id


## Banco del jugador que puede prestar (o {}).
static func _lender_bank(gs, amount: float) -> Dictionary:
	if gs.money < amount:
		return {}
	for b in gs.buildings:
		if gs.owned_by_player(b) and BankSim.is_bank(b) and str(b["status"]) == "activo":
			BankSim.bank_settings(gs, b)
			if bool(b["lending"]) and BankSim.bank_loans(gs, b).size() < BankSim.bank_capacity(gs, b) and amount <= float(b["max_loan"]) * 3.0:
				return b
	return {}


## Mejor emprendedor para un tipo: {"citizen", "loan"} o {}.
static func find_entrepreneur(gs, type_id: String) -> Dictionary:
	var def := GameData.building_def(type_id)
	var skill := str(def.get("skill", ""))
	var need: float = float(capital_needed(gs, type_id)["total"])
	var today: int = gs.today()
	var best: Citizen = null
	var best_score := -INF
	var best_loan := 0.0
	for c in gs.citizens.values():
		if gs.is_player(c.id) or c.prison_until >= 0 or _player_family(gs, c):
			continue
		var age: int = c.age_years(today)
		if age < int(cfg().get("min_age", 22)) or age > int(cfg().get("max_age", 60)):
			continue
		var sk := float(c.skills.get(skill, 0.0))
		if sk < float(cfg().get("min_skill", 15)) or _owns_npc(gs, c.id):
			continue
		var savings := family_savings(gs, c)
		var pool := savings
		if savings < need:
			for pc in partner_candidates(gs, c):
				pool += float(pc["avail"])
		var loan := 0.0
		if pool < need:
			loan = need - pool
			if loan > need * float(cfg().get("loan_share_max", 0.6)) or not BankSim.citizen_loan(gs, c.id).is_empty():
				continue
			if _lender_bank(gs, loan).is_empty():
				continue
		var score: float = sk + c.experience * 0.5 + savings / maxf(1.0, need) * 20.0 - loan / maxf(1.0, need) * 15.0
		if score > best_score:
			best_score = score
			best = c
			best_loan = loan
	if best == null:
		return {}
	return {"citizen": best, "loan": best_loan}


## Socios: vecinos (no familia) con ahorros que aportan capital a cambio de parte de las ganancias.
static func partner_candidates(gs, owner: Citizen) -> Array:
	var fam := family_of(gs, owner)
	var today: int = gs.today()
	var min_money := float(cfg().get("partner_min_money", 30))
	var share := float(cfg().get("partner_share", 0.6))
	var out := []
	for c in gs.citizens.values():
		if fam.has(c) or gs.is_player(c.id) or _player_family(gs, c) or c.money < min_money or c.age_years(today) < 18:
			continue
		out.append({"citizen": c, "avail": c.money * share})
	out.sort_custom(func(a, b): return float(a["avail"]) > float(b["avail"]))
	return out.slice(0, int(cfg().get("max_partners", 3)))


## Busca un lugar libre en terreno desbloqueado, cerca de la plaza.
static func find_spot(gs, type_id: String) -> Dictionary:
	var rad: Array = cfg().get("search_radius", [14, 60])
	var max_r := float(rad[1]) if _terrain_check.is_valid() else minf(float(rad[1]), 29.0)
	var fp := GameData.footprint(type_id, 1)
	for attempt in range(90):
		var ang := FreeMarketSim.rf(gs) * TAU
		var r := FreeMarketSim.rr(gs, float(rad[0]), float(rad[0]) + (max_r - float(rad[0])) * minf(1.0, 0.35 + attempt / 60.0))
		var x := cos(ang) * r
		var z := sin(ang) * r
		if ConstructionSim.placement_block_reason(gs, type_id, x, z) != "":
			continue
		if _terrain_check.is_valid():
			var why = _terrain_check.call(x, z, fp)
			if why is String and str(why) != "":
				continue
		return {"x": x, "z": z, "rot": atan2(-x, -z)}
	return {}


static func monthly(gs) -> void:
	# Dueños cuyo negocio ya no existe o ya no es suyo (incendio, venta) vuelven a estar libres.
	for c in gs.citizens.values():
		if c.job_kind == "dueño":
			var ob: Dictionary = gs.get_building(c.job_id)
			if ob.is_empty() or not is_npc(ob) or int(ob.get("owner_id", -1)) != c.id or str(ob["status"]) != "activo":
				c.job_id = -1
				c.job_kind = ""
				c.wage = 0.0
	_monthly_accounts(gs)
	_estate_sales(gs)
	_consider_opening(gs)


static func _consider_opening(gs) -> void:
	var month_idx: int = gs.today() / 30
	if month_idx < int(cfg().get("first_month", 6)):
		return
	if openings_this_year(gs) >= max_openings(gs):
		return
	var npcs := npc_buildings(gs).filter(func(b): return str(b.get("npc_state", "")) != STATE_FOR_SALE)
	if npcs.size() >= maxi(1, int(gs.citizens.size() / maxf(1.0, float(cfg().get("citizens_per_business", 22))))):
		return
	# Un intento al mes con probabilidad ~ aperturas restantes / meses restantes del año.
	var left := max_openings(gs) - openings_this_year(gs)
	var months_left := maxi(1, 12 - (month_idx % 12))
	if FreeMarketSim.rf(gs) > clampf(float(left) / months_left * 1.5, 0.1, 1.0):
		return
	try_open(gs)


## Intenta abrir un negocio NPC donde haya más demanda sin cubrir. Devuelve el edificio o {}.
## Ventas mensuales esperadas de un nuevo vendedor: lo que hoy se importa (pagado), una parte de lo
## que ya venden otros y del autoabastecimiento de quienes tienen con qué pagar.
static func expected_revenue(gs, good: String) -> float:
	var row: Dictionary = gs.economy.get("last_month", {}).get("goods", {}).get(good, {})
	var with_money := 0
	var adults := 0
	var today: int = gs.today()
	for c in gs.citizens.values():
		if c.age_years(today) >= 16 and not gs.is_player(c.id):
			adults += 1
			if c.money > 5.0:
				with_money += 1
	var payers := float(with_money) / maxf(1.0, adults)
	var units := float(row.get("imported", 0.0)) + float(row.get("local", 0.0)) * 0.3 + float(row.get("self", 0.0)) * payers * 0.5
	return units * EconomySim.market_price(gs, good)


static func try_open(gs, force_good := "") -> Dictionary:
	var unmet := unmet_demand(gs)
	var goods := []
	for g in unmet:
		var u: Dictionary = unmet[g]
		if force_good != "" and g != force_good:
			continue
		if force_good == "":
			if float(u["uncovered"]) < float(cfg().get("min_uncovered_units", 40)):
				continue
			if float(u["uncovered"]) / maxf(1.0, float(u["demand"])) < float(cfg().get("min_uncovered_share", 0.25)):
				continue
			if expected_revenue(gs, str(g)) < float(cfg().get("min_expected_revenue", 40)) * gs.price_mult():
				continue
		goods.append(g)
	if force_good != "" and goods.is_empty():
		goods.append(force_good)
	goods.sort_custom(func(a, b): return float(unmet.get(a, {}).get("uncovered", 0.0)) > float(unmet.get(b, {}).get("uncovered", 0.0)))
	for g in goods:
		var types := type_for_good(gs, str(g))
		if types.is_empty():
			continue
		var type_id: String = str(FreeMarketSim.pick(gs, types))
		var who := find_entrepreneur(gs, type_id)
		if who.is_empty():
			continue
		var spot := find_spot(gs, type_id)
		if spot.is_empty():
			continue
		return open_business(gs, who["citizen"], type_id, float(spot["x"]), float(spot["z"]), float(spot["rot"]), float(who["loan"]))
	return {}


## Abre el negocio: paga de los ahorros familiares (y préstamo de tu banco si hace falta) y empieza la obra.
static func open_business(gs, owner: Citizen, type_id: String, x: float, z: float, rot: float, loan := 0.0) -> Dictionary:
	var cap := capital_needed(gs, type_id)
	var need := float(cap["total"])
	if loan > 0.0:
		var bank := _lender_bank(gs, loan)
		if bank.is_empty():
			return {}
		var l := BankSim._new_loan(gs, str(int(bank["id"])), str(owner.id), loan, float(bank.get("loan_rate", float(cfg().get("loan_rate", 0.12)))), int(cfg().get("loan_months", 36)), "negocio")
		gs.add_money(-loan)
		BusinessSim.ledger_add(bank, "prestado", loan)
		owner.money += loan
		owner.debt = float(l["balance"])
		gs.notify("Tu banco prestó %s a %s para abrir un negocio." % [Fmt.money(loan), owner.full_name()], "negocio")
	# Aporte familiar: primero el emprendedor, luego su familia.
	var left := need
	for m in family_of(gs, owner):
		if left <= 0.0:
			break
		var avail: float = maxf(0.0, m.money) * (1.0 if m == owner else float(cfg().get("family_pool_share", 0.8)))
		var take := minf(avail, left)
		m.money -= take
		left -= take
	var partners := []
	for pc in partner_candidates(gs, owner):
		if left <= 0.01:
			break
		var pcit: Citizen = pc["citizen"]
		var take := minf(float(pc["avail"]), left)
		pcit.money -= take
		left -= take
		partners.append({"id": pcit.id, "name": pcit.full_name(), "share": take / maxf(1.0, need)})
	if left > 0.01:
		owner.money -= left   # No debería pasar (find_entrepreneur lo verifica): queda como deuda del dueño.
	var b := ConstructionSim.make_building(gs, type_id, 1, x, z, rot, "ciudadano")
	b["owner_id"] = owner.id
	b["npc"] = true
	b["npc_state"] = STATE_BUILDING
	b["contractor"] = "npc"
	b["status"] = "construccion"
	var ld := GameData.level_def(type_id, 1)
	b["work_needed"] = float(int(ld.get("build_days", 10)) * int(ld.get("workers", 2)))
	b["name"] = "%s %s" % [str(ld.get("label", type_id)), owner.last_name]
	b["markup"] = FreeMarketSim.range_of(gs, cfg().get("markup_range", [0.02, 0.15]))
	b["auto_price"] = true
	b["reserve"] = float(cap["crew"]) + float(cap["reserve"])   # Caja: jornales de la obra y sueldos iniciales.
	b["founded_day"] = gs.today()
	b["founder"] = owner.full_name()
	b["partners"] = partners
	b["owners"] = [{"id": owner.id, "name": owner.full_name(), "how": "fundador", "day": gs.today()}]
	_snapshot_family(gs, b, owner)
	BusinessSim.ledger_add(b, "obras", float(cap["build"]))  # Materiales (salen del pueblo) = inversión.
	gs.add_building(b)
	var op: Dictionary = gs.market["npc"].get("openings", {})
	op[_year_key(gs)] = int(op.get(_year_key(gs), 0)) + 1
	gs.market["npc"]["openings"] = op
	FreeMarketSim.stat(gs, "npc_opened", 1.0)
	gs.notify("%s empezó a construir %s con sus ahorros%s%s." % [owner.full_name(), b["name"], " y %d socio(s)" % partners.size() if not partners.is_empty() else "", " y un préstamo" if loan > 0.0 else ""], "construccion")
	EventBus.building_changed.emit(int(b["id"]))
	return b


static func _snapshot_family(gs, b: Dictionary, owner: Citizen) -> void:
	b["owner_spouse"] = owner.spouse_id
	b["owner_parents"] = owner.parent_ids.duplicate()
	b["owner_name"] = owner.full_name()


# --- Cuentas mensuales --------------------------------------------------------------------------------------

static func _monthly_accounts(gs) -> void:
	var p := GovSim.policy(gs)
	var npc_cfg := cfg()
	var bk_neg := int(npc_cfg.get("bankrupt_negative_months", 3))
	var bk_loss := int(npc_cfg.get("bankrupt_loss_months", 6))
	var taxes_month := 0.0
	for b in npc_buildings(gs):
		var led: Dictionary = b["ledger"]
		led["last_month"] = led["month"]
		led["month"] = {}
		var owner: Citizen = gs.citizens.get(int(b.get("owner_id", -1)))
		if owner != null:
			_snapshot_family(gs, b, owner)
		if str(b["status"]) != "activo" or str(b.get("npc_state", "")) != STATE_OPEN:
			continue
		# Impuestos: renta, propiedad y nómina (van al tesoro).
		var profit := BusinessSim.period_profit(b, "last_month")
		var tax := 0.0
		if profit > 0.0:
			tax += profit * float(p.get("profit_tax", 0.0))
		tax += EconomySim.property_value(gs, b) * float(p.get("property_tax", 0.0)) / 12.0
		tax += BusinessSim.period_value(b, "last_month", "salarios") * float(p.get("wage_tax", 0.0))
		var paid := _spend(gs, b, tax, "impuestos", false)
		GovSim.add_treasury(gs, paid)
		FreeMarketSim.stat(gs, "npc_taxes", paid)
		taxes_month += paid
		# Dividendos: lo que sobra del capital de trabajo va al dueño (y circula).
		var daily_cost := BusinessSim.period_value(b, "last_month", "salarios") + BusinessSim.period_value(b, "last_month", "insumos") + BusinessSim.period_value(b, "last_month", "mantenimiento")
		var working := daily_cost / 30.0 * float(npc_cfg.get("working_capital_days", 30))
		var excess := float(b["reserve"]) - working
		if excess > 0.0 and owner != null and profit > 0.0:
			var div := excess * float(npc_cfg.get("dividend_share", 0.6))
			b["reserve"] = float(b["reserve"]) - div
			var rest := div
			for pt in b.get("partners", []):
				var pc: Citizen = gs.citizens.get(int(pt["id"]))
				if pc != null:
					var part := div * float(pt["share"])
					pc.money += part
					rest -= part
			owner.money += rest
			b["dividends_total"] = float(b.get("dividends_total", 0.0)) + div
		# Personal: crece si vende todo y gana; se achica si pierde.
		var jobs := int(gs.level_def(b).get("jobs", 1))
		var emps := staff_of(b)
		var product := str(gs.building_def(b).get("product", ""))
		var stock := float(b["inventory"].get(product, 0.0))
		if profit >= 0.0:
			b["loss_months"] = 0
			# Contrata solo si vende casi todo lo que produce y la ganancia paga otro sueldo.
			var sold_units := BusinessSim.period_value(b, "last_month", "ventas") / maxf(0.01, float(b.get("price", 1.0)))
			var extra_wage: float = float(gs.building_def(b).get("base_wage", 2.0)) * gs.price_mult() * 30.0
			if emps.size() < jobs - (1 if owner_works(gs, b) else 0) and stock < sold_units / 30.0 * 3.0 and profit > extra_wage * 1.2:
				fill_jobs(gs, b, emps.size() + 1)
		else:
			b["loss_months"] = int(b.get("loss_months", 0)) + 1
			if int(b["loss_months"]) >= 2 and emps.size() > 1:
				release(gs, emps[emps.size() - 1])
		_owner_joins(gs, b)
		if emps.is_empty() and not owner_works(gs, b):
			fill_jobs(gs, b, 1)
		for c in staff_of(b):
			c.wage = maxf(c.wage, BusinessSim.asked_wage(gs, c, str(b["type"])) * 0.95)
		if float(b["reserve"]) < 0.0:
			b["negative_months"] = int(b.get("negative_months", 0)) + 1
		else:
			b["negative_months"] = 0
		if int(b.get("negative_months", 0)) >= bk_neg or (int(b.get("loss_months", 0)) >= bk_loss and float(b["reserve"]) < working * 0.25):
			bankrupt(gs, b)
	gs.market["npc_tax_last"] = taxes_month


static func bankrupt(gs, b: Dictionary) -> void:
	_owner_leaves(gs, b)
	for c in staff_of(b).duplicate():
		release(gs, c)
	b["status"] = "cerrado"
	b["loss_months"] = 0
	b["negative_months"] = 0
	var owner: Citizen = gs.citizens.get(int(b.get("owner_id", -1)))
	# Lo que quede en caja vuelve al dueño; si la caja está en rojo, la deuda la absorbe él.
	if owner != null:
		owner.money += float(b["reserve"])
	b["reserve"] = 0.0
	for g in b["inventory"]:
		b["inventory"][g] = 0.0
	_list_for_sale(gs, b, "quiebra")
	FreeMarketSim.stat(gs, "npc_bankrupt", 1.0)
	gs.count("npc_bankruptcies")
	gs.notify("QUIEBRA: %s (de %s) cerró. Queda en venta." % [gs.building_label(b), gs.person_name(int(b.get("owner_id", -1)))], "negocio")
	FreeMarketSim.log_event(gs, "Quebró %s." % gs.building_label(b))
	EventBus.building_changed.emit(int(b["id"]))


## Valor de referencia de la empresa: obra invertida, inventario y ganancias recientes.
static func valuation(gs, b: Dictionary) -> float:
	var v := EconomySim.property_value(gs, b)
	for g in b.get("inventory", {}):
		v += float(b["inventory"][g]) * EconomySim.market_price(gs, str(g))
	var profit := maxf(0.0, BusinessSim.period_profit(b, "last_month"))
	v += profit * 12.0 * 0.5
	return maxf(v, float(GameData.level_def(str(b["type"]), 1).get("cost", 300)) * gs.price_mult() * 0.4)


static func _list_for_sale(gs, b: Dictionary, reason: String) -> void:
	b["npc_state"] = STATE_FOR_SALE
	b["npc_sale_reason"] = reason
	b["npc_sale_price"] = snappedf(valuation(gs, b) * float(cfg().get("estate_price_factor", 0.8)), 1.0)
	b["npc_sale_since"] = gs.today()


# --- Herencia ------------------------------------------------------------------------------------------------

static func _check_owner(gs, b: Dictionary) -> void:
	var oid := int(b.get("owner_id", -1))
	if gs.is_player(oid):
		_transfer_to_player(gs, b, "heredaste")
		return
	if oid < 0 or gs.citizens.has(oid):
		return
	var heir := find_heir(gs, b)
	var dead_name := str(b.get("owner_name", gs.person_name(oid)))
	if heir == null:
		# Sin herederos: los bienes vacantes pasan al Estado, que vende la empresa.
		GovSim.add_treasury(gs, maxf(0.0, float(b["reserve"])))
		b["reserve"] = 0.0
		for c in staff_of(b).duplicate():
			release(gs, c)
		if str(b["status"]) == "activo":
			b["status"] = "cerrado"
		b["owner_id"] = -1
		_list_for_sale(gs, b, "sin herederos")
		gs.notify("%s murió sin herederos: el Estado vende %s por %s." % [dead_name, gs.building_label(b), Fmt.money(float(b["npc_sale_price"]))], "negocio")
		FreeMarketSim.log_event(gs, "%s quedó sin dueño (sin herederos)." % gs.building_label(b))
		EventBus.building_changed.emit(int(b["id"]))
		return
	if gs.is_player(heir.id):
		b["owner_id"] = heir.id
		_transfer_to_player(gs, b, "heredaste")
		return
	b["owner_id"] = heir.id
	b["owners"].append({"id": heir.id, "name": heir.full_name(), "how": "herencia", "day": gs.today()})
	_snapshot_family(gs, b, heir)
	if str(b["status"]) == "activo":
		_owner_joins(gs, b)
	gs.notify("%s heredó %s de %s." % [heir.full_name(), gs.building_label(b), dead_name], "negocio")
	FreeMarketSim.log_event(gs, "%s heredó %s." % [heir.full_name(), gs.building_label(b)])
	FreeMarketSim.stat(gs, "npc_inherited", 1.0)
	EventBus.building_changed.emit(int(b["id"]))


## Heredero: hijo(a) adulto(a) mayor, cónyuge, hijo(a) menor, nieto(a) o hermano(a).
static func find_heir(gs, b: Dictionary) -> Citizen:
	var oid := int(b.get("owner_id", -1))
	var today: int = gs.today()
	var adult := int(GameData.citizens.get("adult_age", 16))
	var kids := []
	var grandkids := []
	var siblings := []
	var parents: Array = b.get("owner_parents", [])
	for c in gs.citizens.values():
		if c.parent_ids.has(oid):
			kids.append(c)
		elif not parents.is_empty() and c.parent_ids.any(func(p): return parents.has(p)):
			siblings.append(c)
	for k in kids:
		for gid in k.children_ids:
			if gs.citizens.has(gid):
				grandkids.append(gs.citizens[gid])
	kids.sort_custom(func(a, bb): return a.birth_day < bb.birth_day)
	for k in kids:
		if k.age_years(today) >= adult:
			return k
	var sp := int(b.get("owner_spouse", -1))
	if sp >= 0 and gs.citizens.has(sp):
		return gs.citizens[sp]
	if not kids.is_empty():
		return kids[0]
	grandkids.sort_custom(func(a, bb): return a.birth_day < bb.birth_day)
	for g in grandkids:
		if g.age_years(today) >= adult:
			return g
	siblings.sort_custom(func(a, bb): return a.birth_day < bb.birth_day)
	for s in siblings:
		if s.age_years(today) >= adult:
			return s
	return null


# --- Ventas: Estado, quiebras y ofertas del jugador ---------------------------------------------------------

static func _estate_sales(gs) -> void:
	var months := int(cfg().get("estate_sale_months", 6))
	for b in npc_buildings(gs):
		if str(b.get("npc_state", "")) != STATE_FOR_SALE:
			continue
		var price := float(b.get("npc_sale_price", 0.0))
		# Otro ciudadano con capital puede comprarla y reabrirla.
		var buyer := _citizen_buyer(gs, b, price)
		if buyer != null:
			_pay_seller(gs, b, price, buyer)
			b["owner_id"] = buyer.id
			b["owners"].append({"id": buyer.id, "name": buyer.full_name(), "how": "compra", "day": gs.today()})
			_snapshot_family(gs, b, buyer)
			b["npc_state"] = STATE_OPEN
			b["status"] = "activo"
			b["reserve"] = 0.0
			var cap: Dictionary = capital_needed(gs, str(b["type"]))
			var seed_cash := minf(maxf(0.0, buyer.money), float(cap["reserve"]))
			buyer.money -= seed_cash
			b["reserve"] = seed_cash
			_owner_joins(gs, b)
			if not owner_works(gs, b):
				fill_jobs(gs, b, 1)
			gs.notify("%s compró %s y lo reabrió." % [buyer.full_name(), gs.building_label(b)], "negocio")
			FreeMarketSim.log_event(gs, "%s compró %s." % [buyer.full_name(), gs.building_label(b)])
			EventBus.building_changed.emit(int(b["id"]))
			continue
		if gs.today() - int(b.get("npc_sale_since", gs.today())) >= months * 30:
			_demolish(gs, b)


static func _citizen_buyer(gs, b: Dictionary, price: float) -> Citizen:
	var skill := str(gs.building_def(b).get("skill", ""))
	var today: int = gs.today()
	for c in gs.citizens.values():
		if gs.is_player(c.id) or _player_family(gs, c) or int(b.get("owner_id", -1)) == c.id:
			continue
		var age: int = c.age_years(today)
		if age < int(cfg().get("min_age", 22)) or age > int(cfg().get("max_age", 60)):
			continue
		if float(c.skills.get(skill, 0.0)) < float(cfg().get("min_skill", 15)) or _owns_npc(gs, c.id):
			continue
		if c.money >= price * 1.3 and FreeMarketSim.rf(gs) < 0.5:
			var product := str(gs.building_def(b).get("product", ""))
			if expected_revenue(gs, product) < float(cfg().get("min_expected_revenue", 40)) * gs.price_mult():
				return null   # Nadie compra un negocio sin clientes.
			return c
	return null


## Cobra la venta: al dueño vivo (quiebra) o al tesoro (Estado, sin herederos).
static func _pay_seller(gs, b: Dictionary, price: float, buyer: Citizen) -> void:
	if buyer != null:
		buyer.money -= price
	else:
		gs.add_money(-price)
	var owner: Citizen = gs.citizens.get(int(b.get("owner_id", -1)))
	if owner != null and not gs.is_player(owner.id):
		owner.money += price
	else:
		GovSim.add_treasury(gs, price)


static func _demolish(gs, b: Dictionary) -> void:
	for c in gs.citizens.values():
		if c.job_id == int(b["id"]):
			c.job_id = -1
			c.job_kind = ""
			c.wage = 0.0
	var owner: Citizen = gs.citizens.get(int(b.get("owner_id", -1)))
	if owner != null:
		owner.money += float(b.get("reserve", 0.0))
	else:
		GovSim.add_treasury(gs, float(b.get("reserve", 0.0)))
	b["reserve"] = 0.0
	gs.notify("Nadie compró %s: el edificio se demolió." % gs.building_label(b), "negocio")
	FreeMarketSim.log_event(gs, "Se demolió %s (nadie lo compró)." % gs.building_label(b))
	var id := int(b["id"])
	gs.remove_building(id)
	EventBus.building_removed.emit(id)


static func purchase_block_reason(gs, b: Dictionary, amount: float) -> String:
	if not is_npc(b):
		return "No es una empresa de un ciudadano."
	if str(b.get("npc_state", "")) == STATE_BUILDING:
		return "Todavía está en obra."
	if gs.money < amount:
		return "Necesitas %s." % Fmt.money(amount)
	if BusinessSim.counts_for_limit(gs.building_def(b)) and BusinessSim.business_count(gs) >= BusinessSim.max_businesses(gs):
		return "Límite de negocios (%d). Construye o mejora tu oficina." % BusinessSim.max_businesses(gs)
	for o in gs.market.get("purchase_offers", []):
		if int(o["bid"]) == int(b["id"]) and str(o["status"]) == "pendiente":
			return "Ya enviaste una oferta: espera la respuesta."
	return ""


## Precio de venta publicado (Estado o quiebra): compra inmediata.
static func buy_listed(gs, b: Dictionary) -> String:
	if str(b.get("npc_state", "")) != STATE_FOR_SALE:
		return "No está en venta."
	var price := float(b.get("npc_sale_price", 0.0))
	var why := purchase_block_reason(gs, b, price)
	if why != "":
		return why
	_pay_seller(gs, b, price, null)
	_transfer_to_player(gs, b, "compraste", price)
	return ""


## Oferta del jugador al dueño: responde en unos días (acepta si cubre lo que pide).
static func offer_purchase(gs, b: Dictionary, amount: float) -> String:
	if str(b.get("npc_state", "")) == STATE_FOR_SALE:
		return buy_listed(gs, b)
	var why := purchase_block_reason(gs, b, amount)
	if why != "":
		return why
	var days: Array = cfg().get("reply_days", [2, 5])
	var o := {"id": FreeMarketSim.next_id(gs), "bid": int(b["id"]), "amount": amount, "day": gs.today(),
		"reply_day": gs.today() + FreeMarketSim.ri(gs, int(days[0]), int(days[1])), "status": "pendiente",
		"label": gs.building_label(b)}
	gs.market["purchase_offers"].append(o)
	return ""


## Lo que pide el dueño (fijo por oferta para que la respuesta sea coherente).
static func asking_price(gs, b: Dictionary) -> float:
	if not b.has("npc_ask_mult"):
		b["npc_ask_mult"] = FreeMarketSim.range_of(gs, cfg().get("sale_ask_range", [1.15, 1.45]))
	return valuation(gs, b) * float(b["npc_ask_mult"])


static func _resolve_purchase_offers(gs) -> void:
	var list: Array = gs.market.get("purchase_offers", [])
	for o in list:
		if str(o["status"]) != "pendiente" or int(o["reply_day"]) > gs.today():
			continue
		var b: Dictionary = gs.get_building(int(o["bid"]))
		if b.is_empty() or not is_npc(b):
			o["status"] = "cancelada"
			continue
		var ask := asking_price(gs, b)
		var amount := float(o["amount"])
		var yes := amount >= ask
		if not yes and amount >= ask * float(cfg().get("sale_consider_ratio", 0.85)):
			yes = FreeMarketSim.rf(gs) < float(cfg().get("sale_consider_chance", 0.3))
		var owner_name: String = gs.person_name(int(b.get("owner_id", -1)))
		if yes and gs.money >= amount:
			o["status"] = "aceptada"
			_pay_seller(gs, b, amount, null)
			_transfer_to_player(gs, b, "compraste", amount)
			gs.notify("%s aceptó tu oferta de %s: %s ahora es tuyo." % [owner_name, Fmt.money(amount), o["label"]], "importante")
		else:
			o["status"] = "rechazada"
			o["ask"] = ask
			gs.notify("%s rechazó tu oferta de %s por %s (pide unos %s)." % [owner_name, Fmt.money(amount), o["label"], Fmt.money(snappedf(ask, 10.0))], "negocio")
	while list.size() > 20:
		list.pop_front()


## La empresa pasa al jugador (compra o herencia). La caja queda para el vendedor.
static func _transfer_to_player(gs, b: Dictionary, how: String, price := 0.0) -> void:
	_owner_leaves(gs, b)
	var owner: Citizen = gs.citizens.get(int(b.get("owner_id", -1)))
	var cash := float(b.get("reserve", 0.0))
	if how == "heredaste":
		gs.add_money(cash)
	elif owner != null and not gs.is_player(owner.id):
		owner.money += cash
	else:
		GovSim.add_treasury(gs, cash)
	b["reserve"] = 0.0
	b["owner"] = "jugador"
	b["owner_id"] = -1
	b["npc"] = false
	b["npc_state"] = ""
	b["legal"] = "sas"
	b["auto_price"] = true
	b["loss_months"] = 0
	if price > 0.0:
		BusinessSim.ledger_add(b, "obras", price)
	var owners: Array = b.get("owners", [])
	owners.append({"id": gs.player_id, "name": gs.player_name(), "how": how, "day": gs.today()})
	b["owners"] = owners
	FreeMarketSim.stat(gs, "npc_bought_by_player", 1.0)
	if how == "heredaste":
		gs.notify("Heredaste %s de tu familia." % gs.building_label(b), "familia")
	LogisticsSim.on_buildings_changed(gs)
	EventBus.building_changed.emit(int(b["id"]))


# --- Consultas para la interfaz ------------------------------------------------------------------------------

static func summary_rows(gs) -> Array:
	var rows := []
	for b in npc_buildings(gs):
		var product := str(gs.building_def(b).get("product", ""))
		rows.append({"id": int(b["id"]), "name": gs.building_label(b), "owner": gs.person_name(int(b.get("owner_id", -1))),
			"state": str(b.get("npc_state", "")), "status": str(b["status"]), "product": product,
			"staff": staff_count(gs, b), "jobs": int(gs.level_def(b).get("jobs", 0)),
			"profit": BusinessSim.period_profit(b, "last_month"), "cash": float(b.get("reserve", 0.0)),
			"price": float(b.get("price", 0.0))})
	return rows


static func staff_count(gs, b: Dictionary) -> int:
	var n := 0
	for c in gs.employees_of(int(b["id"])):
		if c.job_kind == "empleo":
			n += 1
	return n


static func owner_text(gs, b: Dictionary) -> String:
	var parts := []
	for o in b.get("owners", []):
		parts.append("%s (%s)" % [o.get("name", ""), o.get("how", "")])
	return " → ".join(parts)
