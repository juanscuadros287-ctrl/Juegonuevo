class_name ShopSim
extends RefCounted
## Economía real — comercios especializados y deseos de los vecinos.
##
## - Comercios (data/shops.json → shops): tipo de negocio → bienes que vende (sells). Venden desde el
##   almacén de la compañía (WarehouseSim) o desde su propio inventario. Incluye la Tienda y la
##   Panadería originales y los comercios nuevos (carnicería, ferretería, concesionario…).
## - Precio de venta = precio de mercado del bien × (precio de la tienda / precio de mercado de su
##   producto). Es decir, reusa la pestaña Precio: margen sobre mercado o precio automático.
## - Tope por personal: clientes por semana = producción esperada (clientes/día) × 7 × customers_mult
##   (× cobertura eléctrica en los niveles modernos).
## - Deseos (data/citizens.json → wants): cada semana cada adulto decide, según la época, sus ahorros
##   (en días de necesidades básicas) y la frecuencia del deseo, si compra ropa, carne, muebles,
##   medicinas, un auto… Solo compra en tus comercios con existencias: el dinero circula (economía
##   cerrada). Si nadie vende, el deseo queda insatisfecho y se registra (oportunidad de negocio).
## Estado: gs.economy["shops"] = {month, last_month, owners}. Llamado desde MarketSim.discretionary.


static func cfg() -> Dictionary:
	return GameData.extra("shops")


static func wants_cfg() -> Dictionary:
	return GameData.citizens.get("wants", {})


static func state(gs) -> Dictionary:
	if not gs.economy.has("shops"):
		gs.economy["shops"] = {"month": {}, "last_month": {}, "owners": {}}
	return gs.economy["shops"]


## Definición de comercio para un tipo de negocio ({} si no es comercio).
static func shop_def_of(type_id: String) -> Dictionary:
	return cfg().get("shops", {}).get(type_id, {})


static func is_shop(gs, b: Dictionary) -> bool:
	return not shop_def_of(str(b.get("type", ""))).is_empty() and gs.owned_by_player(b) and b["status"] == "activo"


## Margen de la tienda sobre el mercado (del precio que fijó el jugador en la pestaña Precio).
static func markup(gs, b: Dictionary) -> float:
	var product := str(gs.building_def(b).get("product", ""))
	var mp := EconomySim.market_price(gs, product)
	if mp <= 0.0:
		return float(b.get("markup", 0.1))
	return clampf(float(b.get("price", mp)) / mp - 1.0, float(cfg().get("min_markup", -0.5)), float(cfg().get("max_markup", 1.0)))


static func price_for(gs, b: Dictionary, good: String) -> float:
	return EconomySim.market_price(gs, good) * (1.0 + markup(gs, b))


## Clientes que atiende por semana con el personal actual.
static func weekly_customers(gs, b: Dictionary) -> float:
	var sd := shop_def_of(str(b.get("type", "")))
	return BusinessSim.expected_output(gs, b) * 7.0 * float(sd.get("customers_mult", 1.0)) * EnergySim.factor(gs, b)


## Existencias de un bien para una tienda: almacén de la compañía + su propio inventario.
static func stock_for(gs, b: Dictionary, good: String) -> float:
	return WarehouseSim.stock(gs, good) + float(b["inventory"].get(good, 0.0))


static func _take(gs, b: Dictionary, good: String, qty: float) -> void:
	var inv: Dictionary = b["inventory"]
	var local := minf(float(inv.get(good, 0.0)), qty)
	if local > 0.0:
		inv[good] = float(inv[good]) - local
	if qty - local > 0.0:
		WarehouseSim.remove(gs, good, qty - local)


## Contexto semanal: {shops: [...], cap: {id: clientes}, by_good: {bien: [tiendas]}}.
static func context(gs) -> Dictionary:
	var shops := []
	var cap := {}
	var by_good := {}
	for b in gs.buildings:
		if not is_shop(gs, b):
			continue
		shops.append(b)
		cap[int(b["id"])] = weekly_customers(gs, b)
		for g in shop_def_of(str(b["type"])).get("sells", []):
			if not GameData.goods.has(str(g)):
				continue
			if not by_good.has(g):
				by_good[g] = []
			by_good[g].append(b)
	return {"shops": shops, "cap": cap, "by_good": by_good}


## ¿El deseo existe en esta época/tecnología?
static func want_active(gs, w: Dictionary) -> bool:
	if gs.era() < int(w.get("era", 1)):
		return false
	var tech := str(w.get("tech", ""))
	if tech != "" and not gs.has_tech(tech):
		return false
	var until := str(w.get("until_tech", ""))
	return until == "" or not gs.has_tech(until)


static func need_day(gs) -> float:
	var nd := 0.0
	for n in GameData.citizens.get("needs", {}).values():
		nd += float(n.get("cost", 0.1))
	return maxf(0.01, nd * gs.price_mult())


# --- Compras semanales ---------------------------------------------------------------------------

static func weekly(gs) -> void:
	var wants := wants_cfg()
	if wants.is_empty():
		return
	var ctx := context(gs)
	var st := state(gs)
	var month: Dictionary = st.get("month", {})
	var dcfg: Dictionary = GameData.citizens.get("discretionary", {})
	var nd := need_day(gs)
	var today: int = gs.today()
	var adult := int(GameData.citizens.get("adult_age", 16))
	var owners: Dictionary = st.get("owners", {})
	var rng := RandomNumberGenerator.new()
	rng.seed = int(gs.settings.get("seed", 0)) * 7919 + today
	var active := []
	for wid in wants:
		if not str(wid).begins_with("_") and want_active(gs, wants[wid]):
			active.append(wid)
	if active.is_empty():
		return
	var willing := float(GameData.citizens.get("willing_markup", 1.6))
	for c in gs.citizens.values():
		if gs.is_player(c.id) or c.age_years(today) < adult or c.prison_until >= 0:
			continue
		var small_budget := maxf(0.0, c.money - nd * float(dcfg.get("wants_buffer_days", 6))) * float(dcfg.get("wants_max_weekly_share", 0.5))
		var happy := 0.0
		for wid in active:
			var w: Dictionary = wants[wid]
			if bool(w.get("employed", false)) and c.job_id < 0:
				continue
			var owned := str(w.get("requires_owned", ""))
			if owned != "" and not owners.get(str(c.id), {}).has(owned):
				continue
			var every := maxf(1.0, float(w.get("every_days", 30)))
			var sick_now: bool = bool(w.get("when_sick", false)) and c.sick
			var qty := float(w.get("qty", 1))
			if every < 7.0:
				qty *= 7.0 / every
			elif not sick_now and rng.randf() >= 7.0 / every:
				continue
			var row: Dictionary = month.get(wid, {"wanted": 0.0, "bought": 0.0, "units": 0.0, "revenue": 0.0, "no_shop": 0.0, "no_stock": 0.0, "too_poor": 0.0})
			row["wanted"] = float(row["wanted"]) + 1.0
			var r := _buy(gs, c, w, qty, ctx, nd, small_budget, willing, rng)
			match str(r["result"]):
				"ok":
					row["bought"] = float(row["bought"]) + 1.0
					row["units"] = float(row["units"]) + float(r["units"])
					row["revenue"] = float(row["revenue"]) + float(r["cost"])
					if every < 60.0:
						small_budget -= float(r["cost"])
					happy += float(w.get("happiness", 0.3))
					_effects(gs, c, w, str(r["good"]), rng)
					var own := str(w.get("owns", ""))
					if own != "":
						var o: Dictionary = owners.get(str(c.id), {})
						o[own] = today
						owners[str(c.id)] = o
				"no_shop":
					row["no_shop"] = float(row["no_shop"]) + 1.0
				"no_stock":
					row["no_stock"] = float(row["no_stock"]) + 1.0
				_:
					row["too_poor"] = float(row["too_poor"]) + 1.0
			month[wid] = row
		if happy > 0.0:
			c.happiness = minf(100.0, c.happiness + minf(float(dcfg.get("wants_max_bonus", 6)), happy))
	st["month"] = month
	st["owners"] = owners


## Intenta comprar un deseo. Devuelve {result: ok|no_shop|no_stock|too_poor|price, good, units, cost}.
static func _buy(gs, c, w: Dictionary, qty: float, ctx: Dictionary, nd: float, small_budget: float, willing: float, rng: RandomNumberGenerator) -> Dictionary:
	var by_good: Dictionary = ctx["by_good"]
	var caps: Dictionary = ctx["cap"]
	var goods: Array = w.get("goods", [])
	var any_shop := false
	var any_stock := false
	var options := []   # [bien, tienda, precio]
	var whole := float(cfg().get("whole_unit_price", 20.0))
	for g in goods:
		if not by_good.has(g):
			continue
		any_shop = true
		var q := qty
		if float(GameData.goods.get(g, {}).get("base_price", 0.0)) >= whole:
			q = maxf(1.0, roundf(qty))
		for b in by_good[g]:
			if float(caps.get(int(b["id"]), 0.0)) < 1.0:
				continue
			var have := stock_for(gs, b, g)
			if have < minf(q, 1.0) * 0.999 or (q >= 1.0 and float(GameData.goods.get(g, {}).get("base_price", 0.0)) >= whole and have < q):
				continue
			any_stock = true
			options.append([g, b, price_for(gs, b, g), minf(q, have)])
	if not any_shop:
		return {"result": "no_shop"}
	if options.is_empty():
		return {"result": "no_stock"}
	var wealth_days: float = c.money / nd
	var rich := wealth_days >= float(w.get("rich_days", 1e9))
	# Los ricos eligen lo más caro (mejor calidad); los demás, lo más barato.
	options.sort_custom(func(a, b): return float(a[2]) > float(b[2]) if rich else float(a[2]) < float(b[2]))
	var min_keep := nd * float(w.get("min_wealth_days", 10))
	var every := float(w.get("every_days", 30))
	for opt in options:
		var g: String = opt[0]
		var b: Dictionary = opt[1]
		var price: float = opt[2]
		var q: float = opt[3]
		var mkt := EconomySim.market_price(gs, g)
		if mkt <= 0.0 or price > mkt * willing:
			continue
		# Demanda elástica: por encima del mercado compran menos (la publicidad ayuda).
		if price > mkt and rng.randf() < (price / mkt - 1.0) / (willing - 1.0) / AdvertisingSim.demand_mult(gs, b):
			continue
		var cost := q * price
		if c.money - cost < min_keep:
			# Los bienes baratos y frecuentes se compran en menor cantidad si no alcanza.
			if every < 60.0 and c.money - min_keep > price * 0.5:
				q = minf(q, floorf((c.money - min_keep) / price * 10.0) / 10.0)
				cost = q * price
			else:
				continue
		if every < 60.0 and cost > small_budget:
			if small_budget < price * 0.5:
				continue
			q = minf(q, small_budget / price)
			cost = q * price
		if q <= 0.001:
			continue
		_take(gs, b, g, q)
		c.money -= cost
		BusinessSim.earn(gs, b, cost, "ventas")
		EconomySim.record_discretionary(gs, g, q, cost)
		ctx["cap"][int(b["id"])] = float(ctx["cap"][int(b["id"])]) - 1.0
		return {"result": "ok", "good": g, "units": q, "cost": cost}
	return {"result": "too_poor"}


## Efectos especiales (medicinas: salud y curación).
static func _effects(gs, c, w: Dictionary, good: String, rng: RandomNumberGenerator) -> void:
	var eff: Dictionary = w.get("effects", {}).get(good, {})
	if eff.is_empty():
		return
	c.health = minf(100.0, c.health + float(eff.get("health", 0.0)))
	if c.sick and rng.randf() < float(eff.get("cure", 0.0)):
		c.sick = false


static func monthly(gs) -> void:
	var st := state(gs)
	st["last_month"] = st.get("month", {})
	st["month"] = {}
	# Limpia dueños de autos que ya no viven en el pueblo.
	var owners: Dictionary = st.get("owners", {})
	for k in owners.keys():
		if not gs.citizens.has(int(k)):
			owners.erase(k)


# --- Consultas para la interfaz ------------------------------------------------------------------

## Filas de demanda de deseos del último mes (o del actual si aún no cierra).
static func wants_report(gs) -> Array:
	var st := state(gs)
	var m: Dictionary = st.get("last_month", {})
	if m.is_empty():
		m = st.get("month", {})
	var rows := []
	var wants := wants_cfg()
	for wid in wants:
		if str(wid).begins_with("_"):
			continue
		var r: Dictionary = m.get(wid, {})
		rows.append({"id": wid, "label": str(wants[wid].get("label", wid)), "goods": wants[wid].get("goods", []), "active": want_active(gs, wants[wid]),
			"wanted": float(r.get("wanted", 0.0)), "bought": float(r.get("bought", 0.0)), "units": float(r.get("units", 0.0)),
			"revenue": float(r.get("revenue", 0.0)), "no_shop": float(r.get("no_shop", 0.0)), "no_stock": float(r.get("no_stock", 0.0))})
	return rows


## Tipos de comercio que venden un bien.
static func shops_selling(good: String) -> Array:
	var out := []
	var shops: Dictionary = cfg().get("shops", {})
	for t in shops:
		if shops[t].get("sells", []).has(good):
			out.append(t)
	return out


## Deseos que incluyen un bien.
static func wants_for(good: String) -> Array:
	var out := []
	var wants := wants_cfg()
	for wid in wants:
		if not str(wid).begins_with("_") and wants[wid].get("goods", []).has(good):
			out.append(wid)
	return out


## Consejos: deseos con demanda insatisfecha (para el jugador).
static func advice(gs) -> Array:
	var out := []
	for r in wants_report(gs):
		if not bool(r["active"]):
			continue
		if float(r["no_shop"]) >= 5.0:
			out.append("Los vecinos quieren %s (%d intentos el último mes) pero ningún comercio lo vende." % [str(r["label"]).to_lower(), int(r["no_shop"])])
		elif float(r["no_stock"]) >= 5.0:
			out.append("Tus comercios no tienen existencias de %s (%d clientes se fueron sin comprar)." % [str(r["label"]).to_lower(), int(r["no_stock"])])
	return out
