class_name EventsSim
extends RefCounted
## Problemas y eventos: crimen (pobreza, desempleo, infelicidad vs. policía), arrestos y cárcel,
## incendios (bomberos), contaminación (industria) y eventos aleatorios (epidemias, sequías,
## crisis, auges…). Parámetros en data/events.json.


static func cfg() -> Dictionary:
	return GameData.events


static func init_state(gs) -> void:
	gs.problems = {"crime": 0.0, "pollution": 0.0, "events": [], "coverage": {},
		"incidents_last": 0, "arrests_last": 0, "fires_year": 0, "stolen_last": 0.0}


## Multiplicador de los eventos activos para una clave (farming, disease, discretionary, import, fire).
static func mult(gs, key: String) -> float:
	var m := 1.0
	for e in gs.problems.get("events", []):
		m *= float(cfg().get("events", {}).get(e["id"], {}).get("effects", {}).get(key, 1.0))
	return m


# --- Cobertura de servicios públicos (se recalcula cada día) ----------------------------------------

static func daily(gs) -> void:
	var cap := {"policia": 0.0, "bomberos": 0.0, "salud": 0.0, "carcel": 0.0}
	for b in gs.buildings:
		if not gs.owned_by_player(b) or b["status"] != "activo":
			continue
		var s := str(gs.building_def(b).get("service", ""))
		if not cap.has(s):
			continue
		var staff := 0
		for c in gs.employees_of(int(b["id"])):
			if c.job_kind == "empleo":
				staff += 1
		cap[s] += staff * float(gs.level_def(b).get("prod_per_worker", 1.0))
	var pop := maxf(1.0, gs.citizens.size())
	gs.problems["coverage"] = {
		"policia": clampf(cap["policia"] / pop, 0.0, 1.0),
		"bomberos": clampf(cap["bomberos"] / maxf(1.0, gs.buildings.size()), 0.0, 1.0),
		"salud": clampf(cap["salud"] / maxf(1.0, pop * 0.15), 0.0, 1.0),
		"carcel_capacity": cap["carcel"],
	}
	# Presos: días de contrato para las cárceles.
	var today: int = gs.today()
	for c in gs.citizens.values():
		if c.prison_until >= 0:
			if today >= c.prison_until:
				c.prison_until = -1
				c.prison_id = -1
				gs.notify("%s cumplió su condena y salió de la cárcel." % c.full_name(), "info")
			else:
				var j: Dictionary = gs.get_building(c.prison_id)
				if not j.is_empty():
					j["prisoner_days"] = float(j.get("prisoner_days", 0.0)) + 1.0


static func coverage(gs, key: String) -> float:
	return float(gs.problems.get("coverage", {}).get(key, 0.0))


# --- Ciclo mensual -------------------------------------------------------------------------------------

static func monthly(gs) -> void:
	_update_events(gs)
	_pollution(gs)
	_crime(gs)
	_fires(gs)


static func _update_events(gs) -> void:
	var today: int = gs.today()
	var active: Array = gs.problems.get("events", [])
	for e in active.duplicate():
		if today >= int(e["until"]):
			active.erase(e)
			gs.notify("Terminó: %s." % cfg()["events"][e["id"]].get("label", e["id"]), "info")
	var freq := float(gs.diff().get("event_freq_mult", 1.0))
	for id in cfg().get("events", {}):
		var ev: Dictionary = cfg()["events"][id]
		if active.any(func(a): return a["id"] == id):
			continue
		var seasons: Array = ev.get("seasons", [])
		if not seasons.is_empty() and not seasons.has(gs.season):
			continue
		if gs.rng.randf() < float(ev.get("chance_monthly", 0.01)) * freq:
			var months: Array = ev.get("months", [1, 3])
			active.append({"id": id, "until": today + gs.rng.randi_range(int(months[0]), int(months[1])) * 30})
			gs.notify(str(ev.get("text", ev.get("label", id))), "importante")
			gs.count("events")
	gs.problems["events"] = active


static func _pollution(gs) -> void:
	var total := 0.0
	for b in gs.buildings:
		if b["status"] == "activo":
			total += float(gs.level_def(b).get("pollution", 0.0))
	var norm := maxf(3.0, gs.citizens.size() * float(cfg().get("pollution", {}).get("normalizer", 0.3)))
	gs.problems["pollution"] = clampf(total / norm * 25.0, 0.0, 100.0)


static func pollution_disease_mult(gs) -> float:
	return 1.0 + float(gs.problems.get("pollution", 0.0)) * float(cfg().get("pollution", {}).get("disease_per_point", 0.004))


static func pollution_happiness(gs) -> float:
	return -float(gs.problems.get("pollution", 0.0)) * float(cfg().get("pollution", {}).get("happiness_per_point", 0.08))


static func _crime(gs) -> void:
	var cc: Dictionary = cfg().get("crime", {})
	var today: int = gs.today()
	var adults := 0
	var poor := 0
	var unhappy := 0
	for c in gs.citizens.values():
		if c.age_years(today) < 16 or gs.is_player(c.id):
			continue
		adults += 1
		if c.needs_met < 0.6 or (c.home_id < 0 and c.money < 2.0):
			poor += 1
		if c.happiness < 35.0:
			unhappy += 1
	if adults == 0:
		return
	var unemp := EconomySim.unemployment(gs)
	var raw := float(cc.get("poverty_weight", 60)) * poor / adults + float(cc.get("unemployment_weight", 20)) * unemp + float(cc.get("unhappy_weight", 40)) * unhappy / adults
	var sec := coverage(gs, "policia")
	var crime := clampf(raw * (1.0 - float(cc.get("police_reduction", 0.7)) * sec) * float(gs.diff().get("event_freq_mult", 1.0)), 0.0, 100.0)
	gs.problems["crime"] = crime
	var n := int(round(crime / 100.0 * gs.citizens.size() * float(cc.get("incidents_per_100", 5)) / 100.0 * 10.0 * gs.rng.randf_range(0.5, 1.5)))
	var arrests := 0
	var stolen := 0.0
	var candidates: Array = gs.citizens.values().filter(func(c): return not gs.is_player(c.id) and c.age_years(today) >= 16 and c.prison_until < 0 and (c.money < 5.0 or c.happiness < 40.0))
	for i in range(n):
		if candidates.is_empty():
			break
		var thief: Citizen = candidates[gs.rng.randi() % candidates.size()]
		# Víctima: uno de tus negocios o un ciudadano.
		var biz: Array = gs.player_buildings("negocio").filter(func(b): return b["status"] == "activo")
		if not biz.is_empty() and gs.rng.randf() < 0.6:
			var b: Dictionary = biz[gs.rng.randi() % biz.size()]
			var loss := minf(maxf(0.0, gs.money), gs.rng.randf_range(5.0, 30.0) * gs.price_level())
			for g in b["inventory"]:
				b["inventory"][g] = float(b["inventory"][g]) * 0.85
			BusinessSim.pay(gs, b, loss, "robos")
			thief.money += loss
			stolen += loss
		else:
			var victims: Array = gs.citizens.values().filter(func(c): return c.money > 10.0 and c != thief and not gs.is_player(c.id))
			if not victims.is_empty():
				var v: Citizen = victims[gs.rng.randi() % victims.size()]
				var take: float = v.money * gs.rng.randf_range(0.05, 0.2)
				v.money -= take
				thief.money += take
				v.happiness = maxf(0.0, v.happiness - 5.0)
		if gs.rng.randf() < float(cc.get("arrest_base", 0.2)) + float(cc.get("arrest_security", 0.7)) * sec:
			if _imprison(gs, thief):
				arrests += 1
				candidates.erase(thief)
	gs.problems["incidents_last"] = n
	gs.problems["arrests_last"] = arrests
	gs.problems["stolen_last"] = stolen
	if n > 0:
		gs.notify("Crimen este mes: %d robos (%s de tus negocios), %d arrestos." % [n, Fmt.money(stolen), arrests], "jugador" if stolen > 0.0 else "info")


static func _imprison(gs, c: Citizen) -> bool:
	var cap := float(coverage(gs, "carcel_capacity"))
	var prisoners: int = gs.citizens.values().filter(func(x): return x.prison_until >= 0).size()
	if prisoners >= cap:
		return false
	var jails: Array = gs.player_buildings("negocio").filter(func(b): return str(gs.building_def(b).get("service", "")) == "carcel" and b["status"] == "activo")
	if jails.is_empty():
		return false
	var days: Array = cfg().get("crime", {}).get("prison_days", [60, 300])
	c.prison_until = gs.today() + gs.rng.randi_range(int(days[0]), int(days[1]))
	c.prison_id = int(jails[0]["id"])
	if c.job_id >= 0:
		c.job_id = -1
		c.job_kind = ""
		c.wage = 0.0
	c.money *= 0.5
	gs.count("arrests")
	return true


static func _fires(gs) -> void:
	var fc: Dictionary = cfg().get("fire", {})
	var cov := coverage(gs, "bomberos")
	var base := float(fc.get("base_monthly", 0.004)) * mult(gs, "fire")
	if gs.season == "verano":
		base *= float(fc.get("summer_mult", 1.6))
	for b in gs.buildings.duplicate():
		if b["status"] == "construccion" or str(b.get("owner", "")) == "gobierno":
			continue
		var p := base * (float(fc.get("thatch_mult", 1.5)) if int(b.get("level", 1)) == 1 else 1.0)
		if gs.rng.randf() >= p:
			continue
		gs.problems["fires_year"] = int(gs.problems.get("fires_year", 0)) + 1
		gs.count("fires")
		var contained: bool = gs.rng.randf() < float(fc.get("coverage_reduction", 0.8)) * cov
		var dmg: Array = fc.get("damage_ratio", [0.1, 0.3])
		var ratio: float = 0.05 if contained else gs.rng.randf_range(float(dmg[0]), float(dmg[1]))
		var label: String = gs.building_label(b)
		if gs.owned_by_player(b):
			var cost: float = float(gs.level_def(b).get("cost", 300)) * gs.price_mult() * ratio
			BusinessSim.pay(gs, b, cost, "reparaciones")
			for g in b["inventory"]:
				b["inventory"][g] = float(b["inventory"][g]) * (0.9 if contained else 0.4)
			gs.notify("Incendio en %s: %s. Reparación: %s." % [label, "controlado por los bomberos" if contained else "daños graves", Fmt.money(cost)], "jugador")
		elif not contained and gs.rng.randf() < float(fc.get("destroy_chance_uncovered", 0.25)):
			for c in gs.residents_of(int(b["id"])):
				c.home_id = -1
			gs.remove_building(int(b["id"]))
			EventBus.building_removed.emit(int(b["id"]))
			EventBus.citizens_moved.emit()
			gs.notify("Un incendio destruyó %s. Sus habitantes quedaron sin hogar." % label, "importante")
		else:
			gs.notify("Incendio en %s (%s)." % [label, "controlado" if contained else "daños menores"], "info")
	if TimeManager.month() == 1:
		gs.problems["fires_year"] = 0
