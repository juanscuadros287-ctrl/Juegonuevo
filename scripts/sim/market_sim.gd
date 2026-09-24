class_name MarketSim
extends RefCounted
## Mercado local: los ciudadanos compran a tus negocios (el dinero circula),
## o se autoabastecen/importan si no hay oferta. Mercado de vivienda mensual.

static var _offers := {}   # bien -> Array de edificios vendedores ordenados


static func begin_day(gs) -> void:
	_offers = {}
	for b in gs.buildings:
		if not gs.owned_by_player(b) or b["status"] != "activo":
			continue
		var product := str(gs.building_def(b).get("product", ""))
		if product == "" or product == "construccion":
			continue
		if not _offers.has(product):
			_offers[product] = []
		_offers[product].append(b)
	for g in _offers:
		# Mejor relación calidad/precio primero.
		_offers[g].sort_custom(func(a, b): return float(a["price"]) / _quality(gs, a) < float(b["price"]) / _quality(gs, b))


static func _quality(gs, b: Dictionary) -> float:
	return maxf(0.1, float(gs.level_def(b).get("quality", 1.0)))


static func sellers(good: String) -> Array:
	return _offers.get(good, [])


## Compra `qty` unidades de un bien. ref_price = precio de referencia por unidad.
## Devuelve {"ok": bool, "bonus": felicidad extra por calidad}.
static func purchase(gs, payers: Array, good: String, qty: float, ref_price: float, employed: bool) -> Dictionary:
	var left := qty
	var bonus := 0.0
	var willing := ref_price * float(GameData.citizens.get("willing_markup", 1.6))
	var total_stock := 0.0
	for b in sellers(good):
		total_stock += float(b["inventory"].get(good, 0.0))
	for b in sellers(good):
		if left <= 0.0001:
			break
		var price := float(b["price"])
		if price > willing:
			continue
		# Demanda elástica: por encima del precio de referencia compran menos.
		if price > ref_price and gs.rng.randf() < (price / ref_price - 1.0) / (willing / ref_price - 1.0):
			continue
		var inv: Dictionary = b["inventory"]
		var stock := float(inv.get(good, 0.0))
		if stock <= 0.0:
			continue
		var take := minf(stock, left)
		var cost := take * price
		if not PopulationSim.pay_with(gs, payers, cost):
			break
		inv[good] = stock - take
		BusinessSim.earn(gs, b, cost, "ventas")
		left -= take
		bonus += (_quality(gs, b) - 1.0) * 2.0 * (take / qty)
		bonus += float(GameData.legal_types.get(str(b.get("legal", "")), {}).get("happiness_bonus", 0)) * (take / qty)
	EconomySim.record_purchase(gs, good, qty, qty - maxf(0.0, left), maxf(0.0, qty - total_stock))
	if left <= 0.0001:
		return {"ok": true, "bonus": bonus}
	# Sin oferta local: autoabastecimiento (desempleados, a costo base) o importación (empleados, más cara).
	var g: Dictionary = GameData.goods.get(good, {})
	var unit := ref_price / maxf(0.01, EconomySim.good_factor(gs, good))
	if employed and float(g.get("import_price", 0.0)) > 0.0:
		unit *= float(GameData.citizens.get("import_markup_employed", 1.4))
	var ok := PopulationSim.pay_with(gs, payers, left * unit)
	return {"ok": ok, "bonus": bonus}


# --- Vivienda ------------------------------------------------------------------------------

## Alquiler diario por persona que cobra una vivienda (0 si no cobra).
static func daily_rent(gs, b: Dictionary) -> float:
	if not gs.owned_by_player(b) or b["status"] == "mejorando":
		return 0.0
	return float(b.get("rent", 0.0)) / 30.0


static func home_quality(gs, b: Dictionary) -> float:
	if b.is_empty():
		return 0.0
	return float(gs.level_def(b).get("quality", 1.0)) + float(Housing.tier_def(b).get("quality_add", 0.0))


## Familias: adulto responsable + cónyuge + hijos menores en la misma casa.
static func households(gs) -> Array:
	var today: int = gs.today()
	var adult := int(GameData.citizens.get("adult_age", 16))
	var seen := {}
	var out := []
	for c in gs.citizens.values():
		if seen.has(c.id) or c.age_years(today) < adult:
			continue
		var members: Array = [c]
		seen[c.id] = true
		if c.spouse_id >= 0 and gs.citizens.has(c.spouse_id) and not seen.has(c.spouse_id):
			members.append(gs.citizens[c.spouse_id])
			seen[c.spouse_id] = true
		for m in members.duplicate():
			for kid_id in m.children_ids:
				if gs.citizens.has(kid_id) and not seen.has(kid_id):
					var kid: Citizen = gs.citizens[kid_id]
					if kid.age_years(today) < adult and kid.home_id == m.home_id:
						members.append(kid)
						seen[kid_id] = true
		out.append(members)
	return out


static func _household_player(gs, members: Array) -> bool:
	for m in members:
		if gs.is_player(m.id):
			return true
	return false


static func monthly_housing(gs) -> void:
	var occ := PopulationSim.home_occupancy(gs)
	var evict_days := int(GameData.citizens.get("eviction_unpaid_days", 30))
	# Desalojos por no pagar.
	for c in gs.citizens.values():
		if c.unpaid_days >= evict_days and c.home_id >= 0:
			var b: Dictionary = gs.get_building(c.home_id)
			if not b.is_empty() and gs.owned_by_player(b) and not gs.is_player(c.id):
				gs.notify("%s fue desalojado(a) de %s por no pagar el alquiler." % [c.full_name(), gs.building_label(b)], "negocio")
				c.home_id = -1
			c.unpaid_days = 0
	occ = PopulationSim.home_occupancy(gs)
	var moved := false
	for members in households(gs):
		if _household_player(gs, members):
			continue
		var head: Citizen = members[0]
		var cur: Dictionary = gs.get_building(head.home_id)
		var size: int = members.size()
		var homeless := cur.is_empty()
		var crowded: bool = not homeless and int(occ.get(head.home_id, 0)) > gs.building_capacity(cur)
		var money := 0.0
		for m in members:
			money += maxf(0.0, m.money)
		# 1) Compra de viviendas en venta.
		var bought := _try_buy_home(gs, members, money, occ)
		if bought:
			moved = true
			continue
		# 2) Alquiler en tus viviendas.
		var cur_q := home_quality(gs, cur)
		var wants_move: bool = homeless or crowded or gs.rng.randf() < 0.25
		if not wants_move:
			continue
		var best: Dictionary = {}
		var best_score := -INF
		for b in gs.buildings:
			if b["status"] != "activo" or not gs.owned_by_player(b) or gs.building_def(b).get("category", "") != "vivienda":
				continue
			if int(b["id"]) == head.home_id or bool(b.get("for_sale", false)) or int(b.get("owner_id", -1)) >= 0:
				continue
			if gs.building_capacity(b) - int(occ.get(int(b["id"]), 0)) < size:
				continue
			var q := home_quality(gs, b)
			if not homeless and not crowded and q <= cur_q:
				continue
			var monthly_cost := float(b["rent"]) * size
			if money < monthly_cost * 2.0:
				continue
			var score := q * 10.0 - monthly_cost / maxf(1.0, money) * 20.0
			if score > best_score:
				best_score = score
				best = b
		if not best.is_empty():
			for m in members:
				m.home_id = int(best["id"])
				m.unpaid_days = 0
			occ[int(best["id"])] = int(occ.get(int(best["id"]), 0)) + size
			moved = true
			gs.notify("La familia %s alquiló en %s." % [head.last_name, gs.building_label(best)], "negocio")
		elif homeless or crowded:
			# 3) Autoconstrucción de una choza con sus ahorros.
			var cost: float = float(GameData.citizens.get("self_build_cost", 150)) * gs.price_mult()
			if money >= cost and gs.rng.randf() < float(GameData.citizens.get("self_build_monthly_chance", 0.25)):
				PopulationSim.pay_with(gs, members, cost)
				var hut := PopulationSim.create_hut(gs)
				hut["owner"] = "ciudadano"
				hut["owner_id"] = head.id
				for m in members:
					m.home_id = int(hut["id"])
				occ[int(hut["id"])] = size
				moved = true
				gs.notify("La familia %s construyó su propia choza." % head.last_name, "construccion")
				EventBus.building_changed.emit(int(hut["id"]))
	if moved:
		EventBus.citizens_moved.emit()


static func _try_buy_home(gs, members: Array, money: float, occ: Dictionary) -> bool:
	for b in gs.buildings:
		if not bool(b.get("for_sale", false)) or not gs.owned_by_player(b) or b["status"] != "activo":
			continue
		var price := float(b["sale_price"])
		if money < price * 1.1 or gs.rng.randf() > 0.35:
			continue
		var others := int(occ.get(int(b["id"]), 0))
		for m in members:
			if m.home_id == int(b["id"]):
				others -= 1
		if gs.building_capacity(b) - others < members.size():
			continue
		PopulationSim.pay_with(gs, members, price)
		BusinessSim.earn(gs, b, price, "ventas")
		b["owner"] = "ciudadano"
		b["owner_id"] = members[0].id
		b["for_sale"] = false
		for m in members:
			m.home_id = int(b["id"])
		gs.notify("Vendiste %s a la familia %s por %s." % [gs.building_label(b), members[0].last_name, Fmt.money(price)], "negocio")
		EventBus.building_changed.emit(int(b["id"]))
		return true
	return false
