class_name MarketSim
extends RefCounted
## Mercado local: los ciudadanos compran a tus negocios (el dinero circula),
## o se autoabastecen/importan si no hay oferta. Mercado de vivienda mensual.

static var _offers := {}   # bien -> Array de edificios vendedores ordenados
static var _memo := {}     # memo del día (se vacía en begin_day): precio de importación por bien
static var _q_memo := {}   # id de negocio -> calidad (memo del día)
static var _hq_memo := {}  # id de vivienda -> calidad de la casa (memo del día)
static var _memo_of = null  # lista de edificios a la que pertenecen los memos (otro país u otra partida: se vacían)


static var _sm_memo := {}  # id de negocio -> [aceptación por calidad, demanda por publicidad] (memo del día)


static func _seller_mult(gs, b: Dictionary, idx: int) -> float:
	_check_memo(gs)
	var k := int(b.get("id", -1))
	if not _sm_memo.has(k):
		_sm_memo[k] = [QualitySim.accept_mult(gs, b), AdvertisingSim.demand_mult(gs, b)]
	return float(_sm_memo[k][idx])


# --- Acumulación del día (rendimiento) -------------------------------------------------------
## Mientras PopulationSim recorre a los ciudadanos, las ventas a empresas NPC y el registro de
## compras se acumulan y se vuelcan una vez al final (flush_day): mismo resultado, menos trabajo.
static var _acc_on := false
static var _rev_acc := {}   # id -> [edificio, monto]
static var _pur_acc := {}   # bien -> [qty, local, imported, self, shortage, revenue]


static func begin_accumulate() -> void:
	_acc_on = true
	_rev_acc = {}
	_pur_acc = {}


static func flush_day(gs) -> void:
	_acc_on = false
	for k in _rev_acc:
		BusinessSim.earn(gs, _rev_acc[k][0], float(_rev_acc[k][1]), "ventas")
	for g in _pur_acc:
		var r: Array = _pur_acc[g]
		EconomySim.record_purchase(gs, g, r[0], r[1], r[2], r[3], r[4], r[5])
	_rev_acc = {}
	_pur_acc = {}


static func _earn(gs, b: Dictionary, amount: float) -> void:
	if _acc_on and NpcBusinessSim.is_npc(b):
		var k := int(b["id"])
		if _rev_acc.has(k):
			_rev_acc[k][1] = float(_rev_acc[k][1]) + amount
		else:
			_rev_acc[k] = [b, amount]
		return
	BusinessSim.earn(gs, b, amount, "ventas")


static func _record_purchase(gs, good: String, qty: float, local: float, imported: float, self_q: float, shortage: float, revenue: float) -> void:
	if not _acc_on:
		EconomySim.record_purchase(gs, good, qty, local, imported, self_q, shortage, revenue)
		return
	if not _pur_acc.has(good):
		_pur_acc[good] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var r: Array = _pur_acc[good]
	r[0] += qty
	r[1] += local
	r[2] += imported
	r[3] += self_q
	r[4] += shortage
	r[5] += revenue


static func _check_memo(gs) -> void:
	if not is_same(_memo_of, gs.buildings):
		_memo_of = gs.buildings
		_q_memo = {}
		_hq_memo = {}
		_sm_memo = {}


static func begin_day(gs) -> void:
	_offers = {}
	_memo = {}
	_q_memo = {}
	_hq_memo = {}
	_sm_memo = {}
	for b in gs.buildings:
		# Libre mercado: las empresas NPC compiten con las tuyas por los mismos clientes.
		if not (gs.owned_by_player(b) or NpcBusinessSim.is_npc(b)) or b["status"] != "activo":
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
	EnergySim.daily(gs)   # Economía real: electricidad del día (tras producir, antes de cerrar el día).


static func _quality(gs, b: Dictionary) -> float:
	_check_memo(gs)
	var k := int(b.get("id", -1))
	if _q_memo.has(k):
		return float(_q_memo[k])
	var q := maxf(0.1, float(gs.level_def(b).get("quality", 1.0)))
	_q_memo[k] = q
	return q


## Precio de importación de un bien (memo del día: depende de precios, aranceles, cambio y guerras).
static func import_price(gs, good: String) -> float:
	var k := "imp|%d|%s" % [gs.today(), good]
	if _memo.has(k):
		return float(_memo[k])
	var g: Dictionary = GameData.goods.get(good, {})
	var imp: float = float(g.get("import_price", 0.0)) * gs.price_mult() * GovSim.import_mult(gs) * GlobalEconSim.import_fx_mult(gs) * WarSim.import_mult(gs, good)   # Tipo de cambio · Mundo: guerra.
	_memo[k] = imp
	return imp


static func sellers(good: String) -> Array:
	return _offers.get(good, [])


## Compra `qty` unidades de un bien. ref_price = precio de referencia por unidad.
## Orden: tus negocios → importación (si trabaja y puede pagarla) → autoabastecimiento en especie.
## Devuelve {"ok", "quality" (0-1, fracción de la necesidad cubierta), "bonus" (felicidad por calidad)}.
static func purchase(gs, payers: Array, good: String, qty: float, ref_price: float, employed: bool) -> Dictionary:
	if good == WaterSim.GOOD:
		var piped := WaterSim.piped_purchase(gs, payers, qty)   # Redes: agua por tubería (factura mensual).
		if not piped.is_empty():
			return piped
	var left := qty
	var bonus := 0.0
	var revenue := 0.0
	var willing := ref_price * float(GameData.citizens.get("willing_markup", 1.6))
	var total_stock := 0.0
	for b in sellers(good):
		total_stock += float(b["inventory"].get(good, 0.0))
	for b in sellers(good):
		if left <= 0.0001:
			break
		var inv: Dictionary = b["inventory"]
		var stock := float(inv.get(good, 0.0))
		if stock <= 0.0:
			continue   # Sin existencias: se salta antes de calcular calidad y publicidad (rendimiento).
		var price := float(b["price"])
		var am := _seller_mult(gs, b, 0)   # Economía global: calidad y marca suben el precio aceptado.
		if price > willing * am:
			continue
		# Demanda elástica: por encima del precio de referencia compran menos (la publicidad ayuda).
		var ad := _seller_mult(gs, b, 1)
		if price > ref_price * am and gs.rng.randf() < (price / (ref_price * am) - 1.0) / (willing / ref_price - 1.0) / ad:
			continue
		var take := minf(stock, left)
		var cost := take * price
		if not PopulationSim.pay_with(gs, payers, cost):
			break
		inv[good] = stock - take
		_earn(gs, b, cost)
		revenue += cost
		left -= take
		bonus += (_quality(gs, b) - 1.0) * 2.0 * (take / qty)
		bonus += float(GameData.legal_types.get(str(b.get("legal", "")), {}).get("happiness_bonus", 0)) * (take / qty)
	var local := qty - maxf(0.0, left)
	var imported := 0.0
	var self_q := 0.0
	var quality := 1.0
	var g: Dictionary = GameData.goods.get(good, {})
	if left > 0.0001:
		var imp: float = import_price(gs, good)
		var well := good == WaterSim.GOOD   # Redes: el agua del pozo comunitario es gratis (no se importa).
		if employed and imp > 0.0 and not well and PopulationSim.pay_with(gs, payers, left * imp):
			imported = left  # El dinero sale del pueblo.
			FlowSim.external_out(gs, left * imp, "importación de bienes")
		else:
			# Autoabastecimiento en especie: cultivar, buscar agua, cortar leña… sin dinero, peor calidad.
			var ss := float(g.get("self_supply", 0.0))
			if well:
				ss *= WaterSim.well_mult(gs)   # Con más gente que pozos, el agua escasea.
				WaterSim.record_well_use(gs, left)
			elif employed:
				ss *= float(GameData.citizens.get("employed_self_supply_factor", 0.7))
			self_q = left
			quality = (local + ss * left) / qty
	_record_purchase(gs, good, qty, local, imported, self_q, maxf(0.0, qty - total_stock), revenue)
	return {"ok": quality > 0.0, "quality": quality, "bonus": bonus}


## Consumo discrecional semanal: quien tiene ahorros de sobra gasta parte en tus
## negocios (taberna, panadería, tienda…). Así el dinero vuelve a circular.
static func discretionary(gs) -> void:
	ShopSim.weekly(gs)   # Economía real: deseos de los vecinos en tus comercios especializados.
	var cfg: Dictionary = GameData.citizens.get("discretionary", {})
	var buffer_days := float(cfg.get("buffer_days", 45))
	var share := float(cfg.get("weekly_share", 0.06)) * EventsSim.mult(gs, "discretionary") * GlobalEconSim.demand_mult(gs)   # Ciclo económico.
	var need_day := 0.0
	for n in GameData.citizens.get("needs", {}).values():
		need_day += float(n.get("cost", 0.1))
	need_day *= gs.price_mult()
	var goods := []
	for gid in GameData.goods:
		if GameData.goods[gid].get("discretionary", false) and not sellers(gid).is_empty():
			goods.append(gid)
	var shop := WarehouseSim.shop_context(gs)   # Fase 6: productos del almacén en la Tienda.
	if goods.is_empty() and shop.is_empty():
		return
	var today: int = gs.today()
	var adult := int(GameData.citizens.get("adult_age", 16))
	for c in gs.citizens.values():
		if gs.is_player(c.id) or c.age_years(today) < adult:
			continue
		var excess: float = c.money - need_day * buffer_days
		if excess <= 0.0:
			continue
		var budget := excess * share
		var spent := 0.0
		var units := 0.0
		if not shop.is_empty():
			var sold: Dictionary = WarehouseSim.shop_sell(gs, c, budget * float(shop["share"]), shop)
			spent += float(sold["spent"])
			units += float(sold["units"])
		for gid in goods:
			for b in sellers(gid):
				var inv: Dictionary = b["inventory"]
				var price := float(b["price"])
				var stock := float(inv.get(gid, 0.0))
				if stock <= 0.0 or price <= 0.0:
					continue
				var take := minf(stock, (budget - spent) / price * AdvertisingSim.demand_mult(gs, b))
				if take <= 0.01:
					break
				inv[gid] = stock - take
				c.money -= take * price
				spent += take * price
				units += take
				BusinessSim.earn(gs, b, take * price, "ventas")
				EconomySim.record_discretionary(gs, gid, take, take * price)
		if units > 0.0:
			c.happiness = minf(100.0, c.happiness + minf(float(cfg.get("max_bonus", 6)), units * float(cfg.get("happiness_per_unit", 0.4))))


# --- Vivienda ------------------------------------------------------------------------------

## Alquiler diario por persona que cobra una vivienda (0 si no cobra).
static func daily_rent(gs, b: Dictionary) -> float:
	if not gs.owned_by_player(b) or b["status"] == "mejorando":
		return 0.0
	return float(b.get("rent", 0.0)) / 30.0 * GridSim.home_value_mult(gs, b)   # Redes: sin luz/agua exigidas, renta menor.


static func home_quality(gs, b: Dictionary) -> float:
	if b.is_empty():
		return 0.0
	_check_memo(gs)
	var k := int(b.get("id", -1))
	if _hq_memo.has(k):
		return float(_hq_memo[k])
	var q := float(gs.level_def(b).get("quality", 1.0)) + float(Housing.tier_def(b).get("quality_add", 0.0)) + GridSim.home_quality_delta(gs, b)
	_hq_memo[k] = q
	return q


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
		# Renta real de la familia: por persona, los niños pagan la fracción de niño (como _pay_housing).
		var rent_units := 0.0
		var employed := false
		for m in members:
			rent_units += 1.0 if m.age_years(gs.today()) >= int(GameData.citizens.get("adult_age", 16)) else float(GameData.citizens.get("child_cost_factor", 0.4))
			if m.job_kind == "empleo":
				employed = true
		# Sin techo con sueldo: basta con un mes ahorrado (el sueldo paga lo demás); si no, dos.
		var months_needed := 1.0 if (homeless or crowded) and employed else 2.0
		# 0) Choza del pueblo con espacio (gratis): primero lo que ya existe.
		if homeless or crowded:
			var free_hut := _free_town_hut(gs, occ, size, head.home_id)
			if not free_hut.is_empty():
				for m in members:
					m.home_id = int(free_hut["id"])
				occ[int(free_hut["id"])] = int(occ.get(int(free_hut["id"]), 0)) + size
				if not homeless:
					occ[int(cur["id"])] = int(occ.get(int(cur["id"]), 0)) - size
				moved = true
				continue
		var best: Dictionary = {}
		var best_score := -INF
		for b in gs.buildings:
			if b["status"] != "activo" or not gs.owned_by_player(b) or gs.building_def(b).get("category", "") != "vivienda":
				continue
			if int(b["id"]) == head.home_id or bool(b.get("for_sale", false)) or int(b.get("owner_id", -1)) >= 0:
				continue
			if RealEstateSim.has_units(b):
				continue   # Bienes raíces: los multifamiliares se arriendan por unidad (RealEstateSim).
			if gs.building_capacity(b) - int(occ.get(int(b["id"]), 0)) < size:
				continue
			var q := home_quality(gs, b)
			if not homeless and not crowded and q <= cur_q:
				continue
			var monthly_cost := float(b["rent"]) * rent_units * GridSim.home_value_mult(gs, b)
			if money < monthly_cost * months_needed:
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
			var roll: float = gs.rng.randf()
			var by_hand: bool = money < cost and roll < float(GameData.citizens.get("self_build_in_kind_chance", 0.08))
			if (money >= cost and roll < float(GameData.citizens.get("self_build_monthly_chance", 0.25))) or by_hand:
				if not by_hand:
					PopulationSim.pay_with(gs, members, cost)
					FlowSim.spend(gs, cost, "vivienda autoconstruida")   # Barro, paja y ayuda de vecinos: el dinero queda en el pueblo.
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


## Choza del pueblo (sin dueño) con camas libres para `size` personas (o {}).
static func _free_town_hut(gs, occ: Dictionary, size: int, exclude: int) -> Dictionary:
	for b in gs.buildings:
		if str(b.get("type", "")) != "vivienda" or str(b.get("owner", "")) != "pueblo" or str(b["status"]) != "activo":
			continue
		if int(b["id"]) == exclude:
			continue
		if gs.building_capacity(b) - int(occ.get(int(b["id"]), 0)) >= size:
			return b
	return {}


static func _try_buy_home(gs, members: Array, money: float, occ: Dictionary) -> bool:
	for b in gs.buildings:
		if not bool(b.get("for_sale", false)) or not gs.owned_by_player(b) or b["status"] != "activo" or RealEstateSim.has_units(b):
			continue
		var price := float(b["sale_price"]) * GridSim.home_value_mult(gs, b)   # Redes: sin servicios exigidos vale menos.
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
