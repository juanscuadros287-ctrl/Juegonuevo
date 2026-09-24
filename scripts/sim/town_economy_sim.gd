class_name TownEconomySim
extends RefCounted
## Libre mercado — los pueblos vecinos (TradeSim) crecen solos y comercian entre ellos.
## Campos nuevos en cada pueblo de gs.trade["towns"] (se crean al cargar partidas viejas):
##   cash       — caja del pueblo (con ella paga tus contratos; economía cerrada)
##   sectors    — empresarios NPC resumidos: {bien: número de negocios}
##   gov_aid    — 0..1, cuánto invierte su gobierno (acelera el crecimiento)
##   pop_f      — población con decimales (population es el entero que ya usaba la Fase 7)
##   trade_month — {"exports", "imports"} comercio con otros pueblos el último mes


static func cfg() -> Dictionary:
	return FreeMarketSim.cfg().get("towns", {})


static func ensure(gs) -> void:
	var pm: float = gs.price_mult()
	for t in TradeSim.towns(gs):
		var pop := float(t.get("population", 500))
		if not t.has("pop_f"):
			t["pop_f"] = pop
		if not t.has("cash"):
			t["cash"] = pop * float(cfg().get("cash_initial_per_pop", 4.0)) * pm
		if not t.has("gov_aid"):
			t["gov_aid"] = FreeMarketSim.rf(gs)
		if not t.has("sectors"):
			t["sectors"] = _initial_sectors(t)
		if not t.has("trade_month"):
			t["trade_month"] = {"exports": 0.0, "imports": 0.0}


static func _initial_sectors(t: Dictionary) -> Dictionary:
	var produces: Array = t.get("produces", [])
	var total := maxi(produces.size(), int(float(t.get("population", 500)) * float(cfg().get("business_per_pop", 0.012))))
	var out := {}
	for g in produces:
		out[str(g)] = maxi(1, int(round(float(total) / maxf(1.0, produces.size()))))
	return out


static func total_businesses(t: Dictionary) -> int:
	var n := 0
	var s: Dictionary = t.get("sectors", {})
	for g in s:
		n += int(s[g])
	return n


static func growth_rate(gs, t: Dictionary) -> float:
	return float(cfg().get("growth_by_era", {}).get(str(gs.era()), 0.01)) + float(t.get("gov_aid", 0.5)) * float(cfg().get("gov_aid_growth", 0.01))


static func monthly(gs) -> void:
	if TradeSim.towns(gs).is_empty():
		return
	ensure(gs)
	var pc: Dictionary = TradeSim.cfg().get("prices", {})
	var pm: float = gs.price_mult()
	var year_start: bool = (int(gs.today()) / 30) % 12 == 0
	for t in TradeSim.towns(gs):
		# Crecimiento según la época y la ayuda de su gobierno.
		if FreeMarketSim.rf(gs) < float(cfg().get("gov_aid_change_chance", 0.05)):
			t["gov_aid"] = clampf(float(t.get("gov_aid", 0.5)) + FreeMarketSim.rr(gs, -0.4, 0.4), 0.0, 1.0)
		var old := float(t.get("pop_f", t.get("population", 500)))
		var pop := minf(float(cfg().get("max_population", 250000)), old * (1.0 + growth_rate(gs, t) / 12.0))
		t["pop_f"] = pop
		t["population"] = int(pop)
		var ratio := pop / maxf(1.0, old)
		# Empresarios resumidos: los sectores crecen con la población y la oferta con ellos.
		var sectors: Dictionary = t.get("sectors", {})
		var target := maxi(sectors.size(), int(pop * float(cfg().get("business_per_pop", 0.012))))
		var goods: Dictionary = t.get("goods", {})
		for g in goods:
			var row: Dictionary = goods[g]
			row["demand"] = float(row.get("demand", 0.0)) * ratio
			if row.has("supply"):
				row["supply"] = float(row.get("supply", 0.0)) * ratio
		if total_businesses(t) < target and not sectors.is_empty():
			var g2: String = str(FreeMarketSim.pick(gs, sectors.keys()))
			sectors[g2] = int(sectors[g2]) + 1
			if goods.has(g2) and goods[g2].has("supply"):
				goods[g2]["supply"] = float(goods[g2]["supply"]) * (1.0 + 1.0 / maxf(1.0, float(sectors[g2])))
		# Nuevos sectores: a veces sus empresarios empiezan a producir algo que antes importaban.
		if year_start and FreeMarketSim.rf(gs) < float(cfg().get("new_sector_chance_year", 0.08)) * (0.5 + float(t.get("gov_aid", 0.5))):
			_new_sector(gs, t, pc)
		# Caja: ingresos de su economía menos gasto.
		var cash := float(t.get("cash", 0.0))
		cash += pop * float(cfg().get("income_per_pop_month", 0.9)) * pm * (1.0 - float(cfg().get("spending_share", 0.85)))
		t["cash"] = clampf(cash, 0.0, pop * float(cfg().get("cash_max_per_pop", 30.0)) * pm)
		t["trade_month"] = {"exports": 0.0, "imports": 0.0}
	_inter_town_trade(gs)


static func _new_sector(gs, t: Dictionary, pc: Dictionary) -> void:
	var options: Array = t.get("demands", []).filter(func(g): return not t.get("produces", []).has(g))
	if options.is_empty():
		return
	var g: String = str(FreeMarketSim.pick(gs, options))
	t["produces"].append(g)
	t["demands"].erase(g)
	var row: Dictionary = t["goods"].get(g, {})
	var pop := float(t.get("population", 500))
	row["sells"] = true
	row["sell_mult"] = FreeMarketSim.range_of(gs, pc.get("produced_sell", [0.75, 0.95]))
	row["buy_mult"] = FreeMarketSim.range_of(gs, pc.get("produced_buy", [0.45, 0.6]))
	row["demand"] = pop * float(pc.get("other_demand_per_pop", 0.02))
	row["supply"] = pop * float(pc.get("supply_per_pop", 0.08)) * 0.5
	t["goods"][g] = row
	t["sectors"][g] = 1
	FreeMarketSim.log_event(gs, "En %s abrieron negocios de %s." % [t["name"], TradeSim.good_label(g).to_lower()])
	if not TradeSim.connection(gs, str(t["id"])).is_empty():
		gs.notify("En %s abrieron negocios de %s: ahora lo venden y lo piden menos." % [t["name"], TradeSim.good_label(g).to_lower()], "negocio")


## Comercio resumido entre pueblos: quien produce vende a quien lo pide (se mueve su dinero).
## Satisface parte de la demanda del comprador (tus precios de exportación allá bajan un poco).
static func _inter_town_trade(gs) -> void:
	var list: Array = TradeSim.towns(gs)
	var share := float(cfg().get("inter_town_share", 0.25))
	var pm: float = gs.price_mult()
	for buyer in list:
		for g in buyer.get("demands", []):
			var brow: Dictionary = buyer["goods"].get(g, {})
			if brow.is_empty():
				continue
			var best: Dictionary = {}
			var best_d := INF
			for seller in list:
				if seller == buyer or not seller.get("produces", []).has(g):
					continue
				var d := absf(float(seller.get("distance", 50.0)) - float(buyer.get("distance", 50.0))) + 20.0
				if d < best_d:
					best_d = d
					best = seller
			if best.is_empty():
				continue
			var srow: Dictionary = best["goods"].get(g, {})
			var vol := minf(float(brow.get("demand", 0.0)), float(srow.get("supply", 0.0))) * share
			var price := TradeSim.base_price(str(g)) * pm * float(srow.get("sell_mult", 0.85))
			var value := minf(vol * price, float(buyer.get("cash", 0.0)) * 0.1)
			if value <= 0.0:
				continue
			buyer["cash"] = float(buyer["cash"]) - value
			best["cash"] = float(best.get("cash", 0.0)) + value
			buyer["trade_month"]["imports"] = float(buyer["trade_month"].get("imports", 0.0)) + value
			best["trade_month"]["exports"] = float(best["trade_month"].get("exports", 0.0)) + value
			brow["sat"] = float(brow.get("sat", 0.0)) + value / maxf(0.01, price) * 0.2


static func town_cash(gs, town_id: String) -> float:
	return float(TradeSim.town(gs, town_id).get("cash", 0.0))
