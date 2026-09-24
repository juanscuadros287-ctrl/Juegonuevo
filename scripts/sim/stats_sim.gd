class_name StatsSim
extends RefCounted
## Estadísticas del pueblo para decidir qué negocio abrir, qué vivienda construir y a quién contratar.


static func _month(gs) -> Dictionary:
	var last: Dictionary = gs.economy.get("last_month", {})
	return last if last.has("goods") else gs.economy.get("month", {})


## Comercio por bien (último mes cerrado).
static func goods_table(gs) -> Array:
	var m := _month(gs)
	var gm: Dictionary = m.get("goods", {})
	var hist: Array = gs.economy.get("stats_hist", [])
	var prev_prices: Dictionary = hist[-2].get("prices", {}) if hist.size() >= 2 else {}
	var prev_goods: Dictionary = hist[-2].get("goods", {}) if hist.size() >= 2 else {}
	var rows := []
	for g in GameData.sorted_ids(GameData.goods):
		if GameData.goods[g].get("internal", false):
			continue
		var r: Dictionary = gm.get(g, {})
		var price := EconomySim.market_price(gs, g)
		var prev := float(prev_prices.get(g, price))
		var demand := float(r.get("demand", 0.0)) + float(r.get("extra", 0.0))
		var prev_demand := float(prev_goods.get(g, {}).get("demand", 0.0)) + float(prev_goods.get(g, {}).get("extra", 0.0))
		var stock := 0.0
		var sellers := 0
		for b in gs.buildings:
			if gs.owned_by_player(b) and str(gs.building_def(b).get("product", "")) == g and b["status"] == "activo":
				sellers += 1
				stock += float(b["inventory"].get(g, 0.0))
		var local := float(r.get("local", 0.0)) + float(r.get("extra", 0.0))
		var uncovered := float(r.get("self", 0.0)) + float(r.get("imported", 0.0))
		rows.append({
			"good": g, "label": GameData.good_label(g), "price": price,
			"price_change": (price - prev) / maxf(0.0001, prev),
			"demand": demand, "demand_change": (demand - prev_demand) / maxf(1.0, prev_demand),
			"local": local, "imported": float(r.get("imported", 0.0)), "self": float(r.get("self", 0.0)),
			"shortage": float(r.get("shortage", 0.0)), "revenue": float(r.get("revenue", 0.0)),
			"local_share": local / maxf(1.0, demand), "uncovered": uncovered,
			"sellers": sellers, "stock": stock, "factor": EconomySim.good_factor(gs, g),
		})
	return rows


## Cobertura de necesidades (personas-día).
static func needs_table(gs) -> Array:
	var nm: Dictionary = _month(gs).get("needs", {})
	var rows := []
	for need in GameData.citizens.get("needs_priority", []):
		if not GameData.citizens.get("needs", {}).has(need):
			continue
		var r: Dictionary = nm.get(need, {})
		var total := float(r.get("met", 0)) + float(r.get("partial", 0)) + float(r.get("unmet", 0))
		rows.append({"need": need, "label": str(GameData.citizens["needs"][need].get("label", need)),
			"met": float(r.get("met", 0)) / maxf(1.0, total), "partial": float(r.get("partial", 0)) / maxf(1.0, total),
			"unmet": float(r.get("unmet", 0)) / maxf(1.0, total)})
	return rows


static func employment(gs) -> Dictionary:
	var today: int = gs.today()
	var adult := int(GameData.citizens.get("adult_age", 16))
	var retire := int(GameData.citizens.get("retirement_age", 65))
	var out := {"workforce": 0, "employed": 0, "day_laborers": 0, "unemployed": 0, "vacancies": 0, "by_skill": {}, "avg_wage": 0.0, "professions": {}, "education": {}}
	var wages := 0.0
	for c in gs.citizens.values():
		var age: int = c.age_years(today)
		if age < adult or age >= retire or gs.is_player(c.id):
			continue
		out["workforce"] += 1
		if c.profession != "":
			out["professions"][c.profession] = int(out["professions"].get(c.profession, 0)) + 1
		out["education"][c.education] = int(out["education"].get(c.education, 0)) + 1
		if c.job_kind == "empleo":
			out["employed"] += 1
			wages += c.wage
		elif c.job_kind == "obra":
			out["day_laborers"] += 1
		else:
			out["unemployed"] += 1
			var sk: String = c.best_skill()
			out["by_skill"][sk] = int(out["by_skill"].get(sk, 0)) + 1
	out["avg_wage"] = wages / maxf(1.0, out["employed"])
	for b in gs.buildings:
		if gs.owned_by_player(b) and BusinessSim.is_business(b) and b["status"] == "activo":
			var n := 0
			for c in gs.employees_of(int(b["id"])):
				if c.job_kind == "empleo":
					n += 1
			out["vacancies"] += maxi(0, int(gs.level_def(b).get("jobs", 0)) - n)
	return out


## Demanda de vivienda: situación de las familias y cuántas pueden pagar cada calidad.
static func housing(gs) -> Dictionary:
	var occ := PopulationSim.home_occupancy(gs)
	var out := {"households": 0, "homeless": 0, "crowded": 0, "in_town_huts": 0, "renting": 0, "owners": 0,
		"can_afford": {}, "vacant": {}, "wants_move": 0}
	var ld := GameData.level_def("vivienda", 1)
	for members in MarketSim.households(gs):
		var head: Citizen = members[0]
		if gs.is_player(head.id) or members.any(func(m): return gs.is_player(m.id)):
			continue
		out["households"] += 1
		var money := 0.0
		var income := 0.0
		for m in members:
			money += maxf(0.0, m.money)
			if m.job_kind == "empleo":
				income += m.wage * 30.0
		var b: Dictionary = gs.get_building(head.home_id)
		var moving := false
		if b.is_empty():
			out["homeless"] += 1
			moving = true
		else:
			if int(occ.get(head.home_id, 0)) > gs.building_capacity(b):
				out["crowded"] += 1
				moving = true
			match str(b.get("owner", "")):
				"pueblo":
					out["in_town_huts"] += 1
				"jugador":
					out["renting"] += 1
				_:
					out["owners"] += 1
		if moving:
			out["wants_move"] += 1
		for tier in Housing.TIERS:
			var rent: float = float(ld.get("rent", 5)) * float(Housing.tier_def_by_id(tier).get("rent_mult", 1.0)) * gs.price_level() * members.size()
			if money >= rent * 2.0 and (income * 0.4 >= rent or money >= rent * 12.0):
				out["can_afford"][tier] = int(out["can_afford"].get(tier, 0)) + 1
	for b in gs.buildings:
		if gs.owned_by_player(b) and Housing.is_home(b) and b["status"] == "activo":
			var t := str(b.get("tier", "normal"))
			var p: Citizen = gs.player_citizen()
			if p != null and p.home_id == int(b["id"]):
				continue
			out["vacant"][t] = int(out["vacant"].get(t, 0)) + maxi(0, gs.building_capacity(b) - int(occ.get(int(b["id"]), 0)))
	return out


static func population(gs) -> Dictionary:
	var today: int = gs.today()
	var out := {"children": 0, "adults": 0, "elderly": 0, "births_year": 0, "deaths_year": 0}
	for c in gs.citizens.values():
		var a: int = c.age_years(today)
		if a < 16:
			out["children"] += 1
		elif a < 60:
			out["adults"] += 1
		else:
			out["elderly"] += 1
	for h in gs.history.slice(maxi(0, gs.history.size() - 12)):
		out["births_year"] += int(h.get("births", 0))
		out["deaths_year"] += int(h.get("deaths", 0))
	return out


## Recomendaciones automáticas a partir de los datos.
static func advice(gs) -> Array:
	var out := []
	for r in goods_table(gs):
		if r["demand"] <= 0.0:
			continue
		if r["sellers"] == 0 and r["demand"] > 20.0:
			out.append("Nadie vende %s en el pueblo: se piden %d unidades/mes (se autoabastecen o importan). Oportunidad de negocio." % [r["label"], int(r["demand"])])
		elif r["factor"] > 1.08:
			out.append("%s escasea: el precio sube. Contrata más personal o abre otro negocio." % r["label"])
		elif r["factor"] < 0.92:
			out.append("Sobra %s: el precio baja. Reduce producción o personal." % r["label"])
	var e := employment(gs)
	if e["workforce"] > 0 and float(e["unemployed"]) / e["workforce"] > 0.5:
		out.append("%d personas buscan empleo: hay mano de obra disponible (y más clientes si les das trabajo)." % e["unemployed"])
	if e["vacancies"] > 0:
		out.append("Tienes %d vacantes sin cubrir en tus negocios." % e["vacancies"])
	var h := housing(gs)
	if h["homeless"] > 0:
		out.append("%d familias sin hogar: construye viviendas de calidad normal (baratas)." % h["homeless"])
	if h["crowded"] > 0:
		out.append("%d familias viven hacinadas: buscan casa." % h["crowded"])
	for tier in ["alta", "media"]:
		var n := int(h["can_afford"].get(tier, 0))
		if n > int(h["vacant"].get(tier, 0)) + 1:
			out.append("%d familias pueden pagar vivienda de calidad %s." % [n, Housing.tier_label(tier)])
			break
	if out.is_empty():
		out.append("Sin alertas. Los datos se actualizan al cerrar cada mes.")
	return out
