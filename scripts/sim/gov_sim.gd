class_name GovSim
extends RefCounted
## Gobierno: régimen según la época (virreyes por decreto → elecciones), políticas
## (impuestos, salario mínimo, aranceles, ayuda a pobres, multas ambientales, subsidios),
## misiones con recompensa, licitaciones de obras públicas y tesoro público.


static func cfg() -> Dictionary:
	return GameData.government


static func init_state(gs) -> void:
	gs.government = {"treasury": float(cfg().get("initial_treasury", 4000)) * gs.price_mult(),
		"gov_id": "", "since_day": gs.today(), "next_change_day": 0, "election_day": -1,
		"candidates": [], "donations": {}, "missions_available": [], "missions_active": [],
		"missions_done": 0, "missions_failed": 0, "tenders": [], "exemptions": {}, "reputation": 50.0,
		"taxes_last": {}, "subsidies_last": 0.0, "regime_era": 1, "next_mission_day": gs.today() + 90}
	_set_government(gs, _random_gov(gs, 1, ""), false)
	_schedule_next(gs)


static func policy(gs) -> Dictionary:
	return cfg().get("governments", {}).get(str(gs.government.get("gov_id", "")), {})


static func regime(gs) -> Dictionary:
	return cfg().get("regimes", {}).get(str(gs.era()), {})


static func add_treasury(gs, amount: float) -> void:
	gs.government["treasury"] = float(gs.government.get("treasury", 0.0)) + amount


## Paga desde el tesoro lo que alcance. Devuelve lo pagado.
static func treasury_pay(gs, amount: float) -> float:
	var t := float(gs.government.get("treasury", 0.0))
	var paid := clampf(amount, 0.0, maxf(0.0, t))
	gs.government["treasury"] = t - paid
	return paid


static func min_wage(gs) -> float:
	return float(policy(gs).get("min_wage", 0.0)) * gs.price_level()


static func import_mult(gs) -> float:
	return float(policy(gs).get("import_tariff", 1.0)) * EventsSim.mult(gs, "import")


static func exempt(gs, tax: String) -> bool:
	return int(gs.government.get("exemptions", {}).get(tax, -1)) >= gs.today()


# --- Ciclo mensual ----------------------------------------------------------------------------------

static func monthly(gs) -> void:
	_collect_taxes(gs)
	_pay_subsidies(gs)
	_poor_relief(gs)
	_enforce_min_wage(gs)
	_check_missions(gs)
	if gs.today() >= int(gs.government.get("next_mission_day", 0)):
		_offer_missions(gs)
		gs.government["next_mission_day"] = gs.today() + 180
	_maybe_tender(gs)
	_expire_tenders(gs)
	_pay_debts(gs)
	_check_regime(gs)


## Deudas pendientes del gobierno por obras públicas.
static func _pay_debts(gs) -> void:
	for b in gs.buildings:
		if str(b.get("owner", "")) == "gobierno" and b["status"] == "activo" and float(b.get("contract", 0.0)) > 0.0:
			var paid := treasury_pay(gs, float(b["contract"]))
			if paid > 0.0:
				b["contract"] = float(b["contract"]) - paid
				gs.add_money(paid)
				gs.add_counter("subsidies", paid)


static func _collect_taxes(gs) -> void:
	var p := policy(gs)
	var totals := {"renta": 0.0, "propiedad": 0.0, "nomina": 0.0, "multas": 0.0}
	for b in gs.buildings:
		if not gs.owned_by_player(b):
			continue
		var nonprofit := BusinessSim.is_nonprofit(b)
		if BusinessSim.is_business(b) and not nonprofit and not exempt(gs, "profit_tax"):
			var profit := BusinessSim.period_profit(b, "last_month")
			if profit > 0.0:
				var t := profit * float(p.get("profit_tax", 0.0))
				BusinessSim.pay(gs, b, t, "impuestos")
				totals["renta"] += t
		if not nonprofit:
			var pt := EconomySim.property_value(gs, b) * float(p.get("property_tax", 0.0)) / 12.0
			if pt > 0.0:
				BusinessSim.pay(gs, b, pt, "impuestos")
				totals["propiedad"] += pt
		var wt := BusinessSim.period_value(b, "last_month", "salarios") * float(p.get("wage_tax", 0.0))
		if wt > 0.0:
			BusinessSim.pay(gs, b, wt, "impuestos")
			totals["nomina"] += wt
		var pol := float(gs.level_def(b).get("pollution", 0.0))
		if pol > 0.0 and b["status"] == "activo" and float(p.get("env_fine", 0.0)) > 0.0:
			var fine: float = pol * float(p.get("env_fine", 0.0)) * gs.price_level() * 10.0
			BusinessSim.pay(gs, b, fine, "multas")
			totals["multas"] += fine
	var total := 0.0
	for k in totals:
		total += float(totals[k])
	add_treasury(gs, total)
	gs.add_counter("taxes_paid", total)
	gs.government["taxes_last"] = totals


static func _pay_subsidies(gs) -> void:
	var p := policy(gs)
	var total := 0.0
	for b in gs.buildings:
		if not gs.owned_by_player(b) or b["status"] == "cerrado":
			continue
		var def: Dictionary = gs.building_def(b)
		var wages := BusinessSim.period_value(b, "last_month", "salarios")
		var amount := 0.0
		if str(def.get("service", "")) != "":
			amount += wages * float(p.get("public_service_subsidy", 0.0))
		elif str(def.get("product", "")) == "educacion":
			amount += wages * float(p.get("public_service_subsidy", 0.0)) * 0.7
		if BusinessSim.is_nonprofit(b) and bool(GameData.legal_types.get("sin_lucro", {}).get("subsidy_eligible", true)):
			amount += wages * 0.2
		if str(def.get("service", "")) == "carcel":
			amount += float(b.get("prisoner_days", 0.0)) * float(gs.level_def(b).get("contract_per_prisoner", 1.0)) * gs.price_level()
			b["prisoner_days"] = 0.0
		if amount <= 0.0:
			continue
		var paid := treasury_pay(gs, amount)
		if paid > 0.0:
			BusinessSim.earn(gs, b, paid, "subsidios")
			total += paid
	gs.add_counter("subsidies", total)
	gs.government["subsidies_last"] = total


## Ayuda a los pobres: el tesoro reparte dinero a quien no cubre sus necesidades.
static func _poor_relief(gs) -> void:
	var rate := float(policy(gs).get("poor_relief", 0.0))
	if rate <= 0.0:
		return
	var need_month := 0.0
	for n in GameData.citizens.get("needs", {}).values():
		need_month += float(n.get("cost", 0.1))
	need_month *= gs.price_mult() * 30.0
	for c in gs.citizens.values():
		if gs.is_player(c.id) or c.needs_met >= 0.75 or c.money > 5.0:
			continue
		var paid := treasury_pay(gs, need_month * rate)
		if paid <= 0.0:
			return
		c.money += paid


static func _enforce_min_wage(gs) -> void:
	var mw := min_wage(gs)
	if mw <= 0.0:
		return
	var raised := 0
	for c in gs.citizens.values():
		if c.job_kind == "empleo" and c.wage < mw:
			c.wage = mw
			raised += 1
	if raised > 0:
		gs.notify("Ley de salario mínimo (%s/día): subiste el sueldo a %d empleados." % [Fmt.money2(mw), raised], "negocio")


# --- Régimen, gobiernos y elecciones --------------------------------------------------------------

static func _random_gov(gs, era: int, exclude: String) -> String:
	var ids := []
	for id in cfg().get("governments", {}):
		var g: Dictionary = cfg()["governments"][id]
		if int(g.get("min_era", 1)) <= era and int(g.get("max_era", 9)) >= era and id != exclude:
			ids.append(id)
	if ids.is_empty():
		return exclude
	return ids[gs.rng.randi() % ids.size()]


static func _set_government(gs, id: String, announce := true) -> void:
	gs.government["gov_id"] = id
	gs.government["since_day"] = gs.today()
	if announce:
		gs.notify("Nuevo gobierno: %s. %s" % [policy(gs).get("label", id), policy(gs).get("description", "")], "importante")


static func _schedule_next(gs) -> void:
	var r := regime(gs)
	if str(r.get("type", "decree")) == "decree":
		var years: int = gs.rng.randi_range(int(r.get("min_years", 15)), int(r.get("max_years", 25)))
		gs.government["next_change_day"] = gs.today() + years * 365
		gs.government["election_day"] = -1
	else:
		gs.government["election_day"] = gs.today() + int(r.get("term_years", 4)) * 365
		gs.government["next_change_day"] = gs.government["election_day"]
		gs.government["candidates"] = []
		gs.government["donations"] = {}


static func _check_regime(gs) -> void:
	var today: int = gs.today()
	if int(gs.government.get("regime_era", 1)) != gs.era():
		# Cambio de época: cambia el régimen (p. ej. independencia → república).
		gs.government["regime_era"] = gs.era()
		gs.notify("Cambio de régimen: %s." % regime(gs).get("label", ""), "importante")
		_set_government(gs, _random_gov(gs, gs.era(), ""))
		_schedule_next(gs)
		return
	var r := regime(gs)
	if str(r.get("type", "decree")) == "decree":
		if today >= int(gs.government.get("next_change_day", 0)):
			_set_government(gs, _random_gov(gs, gs.era(), str(gs.government["gov_id"])))
			_schedule_next(gs)
		return
	var eday := int(gs.government.get("election_day", -1))
	if gs.government.get("candidates", []).is_empty() and today >= eday - 180:
		var cands := [str(gs.government["gov_id"])]
		for i in range(4):
			var g := _random_gov(gs, gs.era(), "")
			if not cands.has(g):
				cands.append(g)
			if cands.size() >= 3:
				break
		gs.government["candidates"] = cands
		gs.notify("Campaña electoral: elecciones el %s. Puedes financiar a un candidato en «Gobierno»." % TimeManager.date_from_day(eday, TimeManager.start_year()), "importante")
	if today >= eday:
		_hold_election(gs)


static func _hold_election(gs) -> void:
	var cands: Array = gs.government.get("candidates", [])
	if cands.is_empty():
		cands = [str(gs.government["gov_id"])]
	var votes := {}
	for g in cands:
		votes[g] = 0.0
	var money: Array = gs.citizens.values().map(func(c): return c.money)
	money.sort()
	var median: float = money[money.size() / 2] if not money.is_empty() else 0.0
	var today: int = gs.today()
	for c in gs.citizens.values():
		if c.age_years(today) < 18:
			continue
		var best := ""
		var best_s := -INF
		for g in cands:
			var social := float(cfg()["governments"][g].get("social", 0.5))
			var s: float = (social if c.money <= median else 1.0 - social) * 2.0 + gs.rng.randf() * 1.5
			if g == str(gs.government["gov_id"]):
				s += (c.happiness - 55.0) / 40.0
			if s > best_s:
				best_s = s
				best = g
		votes[best] += 1.0
	var per_vote: float = float(cfg().get("election", {}).get("donation_per_vote", 40)) * gs.price_level()
	for g in gs.government.get("donations", {}):
		if votes.has(g):
			votes[g] += float(gs.government["donations"][g]) / per_vote
	var winner: String = cands[0]
	for g in cands:
		if votes[g] > votes[winner]:
			winner = g
	var parts := []
	for g in cands:
		parts.append("%s %d" % [cfg()["governments"][g].get("label", g), int(votes[g])])
	gs.notify("Elecciones: %s." % ", ".join(parts), "importante")
	if winner != str(gs.government["gov_id"]):
		_set_government(gs, winner)
	else:
		gs.notify("%s fue reelegido." % policy(gs).get("label", winner), "importante")
	_schedule_next(gs)


static func donate(gs, gov_id: String, amount: float) -> String:
	if not gs.government.get("candidates", []).has(gov_id):
		return "No es candidato"
	if gs.money < amount:
		return "No tienes suficiente dinero"
	gs.add_money(-amount)
	var d: Dictionary = gs.government.get("donations", {})
	d[gov_id] = float(d.get(gov_id, 0.0)) + amount
	gs.government["donations"] = d
	return "Aportaste %s a la campaña de %s." % [Fmt.money(amount), cfg()["governments"][gov_id].get("label", gov_id)]


# --- Misiones ------------------------------------------------------------------------------------------

static func _mission_value(gs, m: Dictionary) -> float:
	match str(m["type"]):
		"jobs":
			return float(StatsSim.employment(gs)["employed"])
		"crime":
			return float(gs.problems.get("crime", 0.0))
		"service":
			for b in gs.buildings:
				if gs.owned_by_player(b) and b["status"] == "activo" and _service_of(b) == str(m.get("service", "")):
					return 1.0
			return 0.0
		"homeless":
			return float(StatsSim.housing(gs)["homeless"])
		"students":
			return float(gs.citizens.values().filter(func(c): return c.school_id >= 0).size())
		"pollution":
			return float(gs.problems.get("pollution", 0.0))
	return 0.0


static func _service_of(b: Dictionary) -> String:
	var def := GameData.building_def(str(b.get("type", "")))
	if def.has("service"):
		return str(def["service"])
	if str(def.get("product", "")) == "educacion":
		return "escuela"
	return ""


static func mission_done(gs, m: Dictionary) -> bool:
	var v := _mission_value(gs, m)
	match str(m["type"]):
		"crime", "pollution", "homeless":
			return v <= float(m["target"])
	return v >= float(m["target"])


static func _offer_missions(gs) -> void:
	var avail: Array = gs.government.get("missions_available", [])
	var active: Array = gs.government.get("missions_active", [])
	if avail.size() + active.size() >= 3:
		return
	var used := {}
	for m in avail + active:
		used[m["id"]] = true
	var pop: int = gs.citizens.size()
	var options := []
	for t in cfg().get("missions", []):
		if used.has(t["id"]):
			continue
		var m: Dictionary = t.duplicate()
		match str(t["type"]):
			"jobs":
				m["target"] = float(StatsSim.employment(gs)["employed"] + maxi(3, int(pop * 0.1)))
			"crime":
				var cr := float(gs.problems.get("crime", 0.0))
				if cr < 15.0:
					continue
				m["target"] = float(int(cr * 0.8))
			"service":
				if _mission_value(gs, m) > 0.0 or not _service_available(gs, str(t.get("service", ""))):
					continue
				m["target"] = 1.0
			"homeless":
				if StatsSim.housing(gs)["homeless"] == 0:
					continue
				m["target"] = 0.0
			"students":
				if not gs.has_tech("escuela_parroquial"):
					continue
				m["target"] = _mission_value(gs, m) + maxf(3.0, float(int(pop * 0.08)))
			"pollution":
				var pl := float(gs.problems.get("pollution", 0.0))
				if pl < 25.0:
					continue
				m["target"] = float(int(pl * 0.7))
		options.append(m)
	options.shuffle()
	while not options.is_empty() and avail.size() + active.size() < 3:
		var m: Dictionary = options.pop_front()
		m["label"] = str(m["label"]).replace("{n}", str(int(m["target"])))
		m["reward_money"] = float(m.get("reward_money", 0)) * gs.price_level()
		avail.append(m)
		gs.notify("El gobierno propone una misión: %s." % m["label"], "importante")
	gs.government["missions_available"] = avail


static func _service_available(gs, service: String) -> bool:
	for type_id in GameData.businesses:
		var def: Dictionary = GameData.businesses[type_id]
		var s: String = str(def.get("service", "escuela" if str(def.get("product", "")) == "educacion" else ""))
		if s == service and gs.has_tech(str(def.get("levels", [{}])[0].get("tech", ""))):
			return true
	return false


static func accept_mission(gs, idx: int) -> String:
	var avail: Array = gs.government.get("missions_available", [])
	if idx < 0 or idx >= avail.size():
		return "Misión no encontrada"
	var m: Dictionary = avail[idx]
	avail.remove_at(idx)
	m["deadline"] = gs.today() + int(m.get("months", 24)) * 30
	gs.government["missions_active"].append(m)
	return "Misión aceptada: %s" % m["label"]


static func _check_missions(gs) -> void:
	var active: Array = gs.government.get("missions_active", [])
	for m in active.duplicate():
		if mission_done(gs, m):
			var paid := treasury_pay(gs, float(m.get("reward_money", 0.0)))
			gs.add_money(paid)
			gs.add_counter("subsidies", paid)
			var ex := int(m.get("reward_exemption_months", 0))
			if ex > 0:
				gs.government["exemptions"]["profit_tax"] = maxi(int(gs.government["exemptions"].get("profit_tax", -1)), gs.today()) + ex * 30
			gs.government["missions_done"] = int(gs.government.get("missions_done", 0)) + 1
			gs.government["reputation"] = minf(100.0, float(gs.government.get("reputation", 50.0)) + 8.0)
			active.erase(m)
			gs.notify("¡Misión cumplida: %s! Recompensa: %s%s." % [m["label"], Fmt.money(paid), " y %d meses sin impuesto de renta" % ex if ex > 0 else ""], "importante")
		elif gs.today() > int(m["deadline"]):
			active.erase(m)
			gs.government["missions_failed"] = int(gs.government.get("missions_failed", 0)) + 1
			gs.government["reputation"] = maxf(0.0, float(gs.government.get("reputation", 50.0)) - 6.0)
			gs.notify("Misión fallida por tiempo: %s." % m["label"], "jugador")


static func mission_progress(gs, m: Dictionary) -> String:
	return "%d / meta %d" % [int(_mission_value(gs, m)), int(m["target"])]


# --- Licitaciones --------------------------------------------------------------------------------------

static func public_projects(gs) -> Array:
	var out := []
	for id in GameData.buildings:
		var def: Dictionary = GameData.buildings[id]
		if str(def.get("category", "")) != "publico":
			continue
		if ConstructionSim.level_block_reason(gs, id, 1) != "":
			continue
		out.append(id)
	return out


static func _maybe_tender(gs) -> void:
	var tc: Dictionary = cfg().get("tenders", {})
	for t in gs.government.get("tenders", []):
		if t["status"] in ["open", "won"]:
			return
	if gs.rng.randf() > float(tc.get("yearly_chance", 0.6)) / 12.0:
		return
	var built := {}
	for b in gs.buildings:
		built[str(b["type"])] = true
	var options := public_projects(gs).filter(func(id): return not built.has(id))
	if options.is_empty():
		return
	var type_id: String = options[gs.rng.randi() % options.size()]
	var value: float = float(GameData.level_def(type_id, 1).get("cost", 1000)) * gs.price_mult()
	var t := {"id": gs.today(), "type": type_id, "value": value, "status": "open", "deadline": gs.today() + 90, "bid": 0.0}
	gs.government["tenders"].append(t)
	gs.notify("Licitación pública: %s (valor de referencia %s). Oferta en «Gobierno»." % [GameData.level_def(type_id, 1).get("label", type_id), Fmt.money(value)], "importante")


static func open_tenders(gs) -> Array:
	return gs.government.get("tenders", []).filter(func(t): return t["status"] in ["open", "won"])


## Oferta: gana quien pida menos. La reputación da ventaja.
static func bid(gs, tender: Dictionary, amount: float) -> String:
	if tender["status"] != "open":
		return "La licitación ya cerró"
	var v := float(tender["value"])
	amount = clampf(amount, v * 0.5, v * 2.0)
	var tc: Dictionary = cfg().get("tenders", {})
	var rng_r: Array = tc.get("competitor_range", [0.85, 1.2])
	var best_comp := INF
	for i in range(int(tc.get("competitors", 2))):
		best_comp = minf(best_comp, v * gs.rng.randf_range(float(rng_r[0]), float(rng_r[1])))
	var effective: float = amount * (1.0 - (float(gs.government.get("reputation", 50.0)) - 50.0) / 500.0)
	if effective <= best_comp:
		tender["status"] = "won"
		tender["bid"] = amount
		tender["deadline"] = gs.today() + 180
		return "¡Ganaste la licitación por %s! Coloca la obra desde «Gobierno» (costos iniciales ~%s)." % [Fmt.money(amount), Fmt.money(v * float(tc.get("upfront_cost_ratio", 0.6)))]
	tender["status"] = "lost"
	return "Perdiste: un competidor ofreció %s." % Fmt.money(best_comp)


static func _expire_tenders(gs) -> void:
	for t in gs.government.get("tenders", []):
		if t["status"] in ["open", "won"] and gs.today() > int(t["deadline"]):
			if t["status"] == "won":
				gs.government["reputation"] = maxf(0.0, float(gs.government.get("reputation", 50.0)) - 10.0)
				gs.notify("No iniciaste la obra pública %s a tiempo: el contrato se canceló." % GameData.level_def(t["type"], 1).get("label", ""), "jugador")
			t["status"] = "expired"


## Inicia la obra pública ganada en la ubicación elegida.
static func start_public_project(gs, tender: Dictionary, x: float, z: float, rot: float) -> String:
	if tender["status"] != "won":
		return "No tienes esa licitación"
	var reason := ConstructionSim.placement_block_reason(gs, str(tender["type"]), x, z)
	if reason != "":
		return reason
	var upfront: float = float(tender["value"]) * float(cfg().get("tenders", {}).get("upfront_cost_ratio", 0.6))
	if gs.money < upfront:
		return "Necesitas %s para materiales" % Fmt.money(upfront)
	gs.add_money(-upfront)
	var b := ConstructionSim.make_building(gs, str(tender["type"]), 1, x, z, rot, "gobierno")
	var ld := GameData.level_def(str(tender["type"]), 1)
	b["status"] = "construccion"
	b["work_needed"] = float(int(ld.get("build_days", 30)) * int(ld.get("workers", 4)))
	b["contract"] = float(tender["bid"])
	b["contractor"] = "jugador"
	BusinessSim.ledger_add(b, "obras", upfront)
	gs.add_building(b)
	tender["status"] = "building"
	gs.notify("Obra pública iniciada: %s." % ld.get("label", ""), "construccion")
	EventBus.building_changed.emit(int(b["id"]))
	return ""


## Al terminar una obra pública, el gobierno paga el contrato.
static func on_project_complete(gs, b: Dictionary) -> void:
	var contract := float(b.get("contract", 0.0))
	if contract <= 0.0:
		return
	var paid := treasury_pay(gs, contract)
	var debt := contract - paid
	gs.add_money(paid)
	gs.add_counter("subsidies", paid)
	b["contract"] = debt
	gs.government["reputation"] = minf(100.0, float(gs.government.get("reputation", 50.0)) + 5.0)
	gs.notify("El gobierno te pagó %s por la obra pública%s." % [Fmt.money(paid), " (debe %s: pagará cuando tenga fondos)" % Fmt.money(debt) if debt > 0.0 else ""], "importante")


## Efectos de las obras públicas terminadas.
static func project_mult(gs, key: String) -> float:
	var m := 1.0
	for b in gs.buildings:
		if str(b.get("owner", "")) == "gobierno" and b["status"] == "activo":
			var e: Dictionary = gs.level_def(b).get("effects", {})
			if e.has(key) and key != "happiness":
				m *= float(e[key])
	return m


static func project_happiness(gs) -> float:
	var h := 0.0
	for b in gs.buildings:
		if str(b.get("owner", "")) == "gobierno" and b["status"] == "activo":
			h += float(gs.level_def(b).get("effects", {}).get("happiness", 0.0))
	return h
