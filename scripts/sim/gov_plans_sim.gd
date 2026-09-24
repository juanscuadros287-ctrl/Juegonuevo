class_name GovPlansSim
extends RefCounted
## Libre mercado — plan de gobierno: con el tesoro (impuestos) el gobierno construye por sí mismo
## parques, centros de salud, comisarías, escuelas públicas y vivienda social según las
## necesidades medidas (felicidad, salud, crimen, déficit de vivienda, niños sin escuela).
## Tipos en data/buildings_gobierno.json (categoría "publico": también se licitan con GovSim).
## Estado: gs.market["gov_plans"] = [{id, type, label, need, status, bid, cost, day, ...}]
##   status: "materiales" (espera material del jugador) · "licitacion" · "en_obra" · "terminado" · "cancelado"
## Obras propias: owner "gobierno", contractor "gobierno" → sus jornales salen del tesoro (NpcBusinessSim.book).
## Personal y mantenimiento de TODAS las obras del gobierno con empleos se pagan del tesoro.


static func cfg() -> Dictionary:
	return FreeMarketSim.cfg().get("gov_plans", {})


static func plans(gs) -> Array:
	return gs.market.get("gov_plans", [])


static func plan(gs, id: int) -> Dictionary:
	for p in plans(gs):
		if int(p["id"]) == id:
			return p
	return {}


static func active_plan(gs) -> Dictionary:
	for p in plans(gs):
		if str(p["status"]) in ["materiales", "licitacion", "en_obra"]:
			return p
	return {}


static func is_gov_funded(b: Dictionary) -> bool:
	return str(b.get("owner", "")) == "gobierno" and str(b.get("contractor", "")) == "gobierno"


static func gov_buildings(gs) -> Array:
	return gs.buildings.filter(func(b): return str(b.get("owner", "")) == "gobierno")


static func status_label(s: String) -> String:
	return {"materiales": "esperando materiales", "licitacion": "en licitación", "en_obra": "en obra",
		"terminado": "terminado", "cancelado": "cancelado"}.get(s, s)


static func need_label(n: String) -> String:
	return {"felicidad": "felicidad baja", "salud": "poca atención médica", "crimen": "crimen alto",
		"vivienda": "familias sin hogar", "educacion": "niños sin escuela"}.get(n, n)


# --- Costos ------------------------------------------------------------------------------------------

## Costo para el gobierno: obra + materiales importados + jornales estimados.
static func cost_of(gs, type_id: String) -> Dictionary:
	var ld := GameData.level_def(type_id, 1)
	var pm: float = gs.price_mult()
	var mats := 0.0
	var mat_list: Dictionary = ld.get("materials", {})
	for g in mat_list:
		mats += float(mat_list[g]) * material_unit_price(gs, str(g))
	var wages := float(int(ld.get("build_days", 10)) * int(ld.get("workers", 2))) * float(GameData.game.get("construction_day_wage", 2.2)) * pm
	var build := float(ld.get("cost", 500)) * pm
	return {"build": build, "materials": mats, "wages": wages, "total": build + mats + wages}


static func material_unit_price(gs, good: String) -> float:
	return float(GameData.goods.get(good, {}).get("import_price", 5.0)) * gs.price_mult() * GovSim.import_mult(gs)


# --- Necesidades -------------------------------------------------------------------------------------

static func _count_type(gs, type_id: String) -> int:
	var n := 0
	for b in gs.buildings:
		if str(b["type"]) == type_id:
			n += 1
	return n


static func kids_without_school(gs) -> Array:
	var today: int = gs.today()
	return gs.citizens.values().filter(func(c): return c.age_years(today) >= 6 and c.age_years(today) <= 15 and c.education < 1 and c.school_id < 0 and not gs.is_player(c.id))


## Necesidades medidas: [{need, type, severity}] ordenadas de mayor a menor.
static func needs(gs) -> Array:
	var types: Dictionary = cfg().get("types", {})
	var pop: int = gs.citizens.size()
	var out := []
	for type_id in types:
		var t: Dictionary = types[type_id]
		if GameData.building_def(type_id).is_empty() or ConstructionSim.level_block_reason(gs, type_id, 1) != "":
			continue
		var th := float(t.get("threshold", 0.0))
		var sev := 0.0
		match str(t.get("need", "")):
			"felicidad":
				if _count_type(gs, type_id) < 1 + pop / 80:
					sev = (th - gs.avg_happiness()) / 10.0
			"salud":
				if _count_type(gs, type_id) < 1 + pop / 150:
					var sick: int = gs.citizens.values().filter(func(c): return c.sick).size()
					sev = (th - EventsSim.coverage(gs, "salud")) * 3.0 + sick * 0.1
			"crimen":
				if _count_type(gs, type_id) < 1 + pop / 150:
					sev = (float(gs.problems.get("crime", 0.0)) - th) / 10.0
			"vivienda":
				var homeless := int(StatsSim.housing(gs).get("homeless", 0))
				sev = (homeless - th + 1.0) / 2.0 if homeless >= int(th) else -1.0
			"educacion":
				if _count_type(gs, type_id) < 1 + pop / 150:
					sev = (kids_without_school(gs).size() - th) / 5.0
		if sev > 0.0:
			out.append({"need": str(t.get("need", "")), "type": str(type_id), "severity": sev})
	out.sort_custom(func(a, b): return float(a["severity"]) > float(b["severity"]))
	return out


# --- Ciclo mensual -----------------------------------------------------------------------------------

static func monthly(gs) -> void:
	_pay_upkeep(gs)
	_staff(gs)
	_schools(gs)
	_social_housing(gs)
	_advance_plans(gs)
	var every := maxi(1, int(cfg().get("check_months", 3)))
	if (gs.today() / 30) % every == 0 and active_plan(gs).is_empty():
		propose(gs)


## Decide una obra si hay necesidad y presupuesto. Devuelve el plan o {}.
static func propose(gs, forced_type := "") -> Dictionary:
	var list := needs(gs)
	if forced_type != "":
		list = [{"need": str(cfg().get("types", {}).get(forced_type, {}).get("need", "")), "type": forced_type, "severity": 1.0}]
	var treasury := float(gs.government.get("treasury", 0.0))
	var reserve: float = float(cfg().get("min_treasury", 1500)) * gs.price_mult()
	for n in list:
		var type_id := str(n["type"])
		var cost := cost_of(gs, type_id)
		if treasury < float(cost["total"]) + reserve:
			continue
		var p := {"id": FreeMarketSim.next_id(gs), "type": type_id, "label": str(GameData.level_def(type_id, 1).get("label", type_id)),
			"need": str(n["need"]), "status": "", "bid": -1, "cost": float(cost["total"]), "day": gs.today(),
			"materials_pending": {}, "materials_bought": {}}
		gs.market["gov_plans"].append(p)
		# ¿Licitar al jugador? Reutiliza las licitaciones de GovSim (una abierta a la vez).
		if FreeMarketSim.rf(gs) < float(cfg().get("tender_chance", 0.35)) and GovSim.open_tenders(gs).is_empty():
			var t := {"id": gs.today() * 10 + int(p["id"]) % 10, "type": type_id, "value": float(cost["build"]) + float(cost["materials"]),
				"status": "open", "deadline": gs.today() + 90, "bid": 0.0, "plan_id": int(p["id"])}
			gs.government["tenders"].append(t)
			p["status"] = "licitacion"
			gs.notify("Plan de gobierno: %s (%s). Se licita: oferta en «Gobierno»." % [p["label"], need_label(str(n["need"]))], "importante")
		else:
			_request_materials(gs, p)
			gs.notify("Plan de gobierno: el gobierno construirá %s por %s (%s)." % [p["label"], Fmt.money(float(cost["total"])), need_label(str(n["need"]))], "importante")
		FreeMarketSim.log_event(gs, "Plan de gobierno: %s (%s)." % [p["label"], need_label(str(n["need"]))])
		return p
	return {}


## Si el jugador produce los materiales, el gobierno se los pide por contrato antes de importarlos.
static func _request_materials(gs, p: Dictionary) -> void:
	p["status"] = "materiales"
	# Espera la respuesta (bandeja) y la entrega; si no llega, importa los materiales.
	p["materials_until"] = gs.today() + int(ContractSim.cfg().get("inbox_days", 15)) + int(cfg().get("materials_wait_days", 20)) + 2
	var mats: Dictionary = GameData.level_def(str(p["type"]), 1).get("materials", {})
	var produced := ContractSim.player_goods(gs)
	var asked := false
	for g in mats:
		if produced.has(str(g)):
			var price := material_unit_price(gs, str(g)) * float(ContractSim.cfg().get("gov_material_price", 0.9))
			var r := ContractSim.create_request(gs, "gov", str(g), float(mats[g]), price, 1, int(cfg().get("materials_wait_days", 20)), int(p["id"]))
			if not r.is_empty():
				p["materials_pending"][str(g)] = float(mats[g])
				asked = true
	if not asked:
		_start_build(gs, p)


## El contrato entregó material para la obra.
static func on_material_delivered(gs, plan_id: int, good: String, qty: float) -> void:
	var p := plan(gs, plan_id)
	if p.is_empty():
		return
	var bought: Dictionary = p.get("materials_bought", {})
	bought[good] = float(bought.get(good, 0.0)) + qty
	p["materials_bought"] = bought
	var pend: Dictionary = p.get("materials_pending", {})
	pend.erase(good)
	if pend.is_empty() and str(p["status"]) == "materiales":
		_start_build(gs, p)


static func _advance_plans(gs) -> void:
	for p in plans(gs):
		match str(p["status"]):
			"materiales":
				if gs.today() >= int(p.get("materials_until", 0)):
					_start_build(gs, p)
			"licitacion":
				var t := _tender_of(gs, int(p["id"]))
				var st := str(t.get("status", "expired"))
				if st == "building":
					var b := _unassigned_gov_building(gs, str(p["type"]))
					if not b.is_empty():
						b["gov_plan"] = int(p["id"])
						p["bid"] = int(b["id"])
						p["status"] = "en_obra"
						p["builder"] = "jugador"
				elif st in ["lost", "expired"]:
					# Ganó un competidor o nadie la hizo: el gobierno la construye por su cuenta.
					_request_materials(gs, p)


static func _tender_of(gs, plan_id: int) -> Dictionary:
	for t in gs.government.get("tenders", []):
		if int(t.get("plan_id", -1)) == plan_id:
			return t
	return {}


static func _unassigned_gov_building(gs, type_id: String) -> Dictionary:
	for b in gov_buildings(gs):
		if str(b["type"]) == type_id and not b.has("gov_plan"):
			return b
	return {}


## Coloca la obra y paga del tesoro la obra y los materiales que no compró al jugador.
static func _start_build(gs, p: Dictionary) -> void:
	var type_id := str(p["type"])
	var spot := NpcBusinessSim.find_spot(gs, type_id)
	if spot.is_empty():
		p["status"] = "cancelado"
		p["reason"] = "sin terreno libre"
		gs.notify("Plan de gobierno cancelado: no hay terreno libre para %s." % p["label"], "info")
		return
	var cost := cost_of(gs, type_id)
	var mats: Dictionary = GameData.level_def(type_id, 1).get("materials", {})
	var bought: Dictionary = p.get("materials_bought", {})
	var imported := 0.0
	for g in mats:
		imported += maxf(0.0, float(mats[g]) - float(bought.get(str(g), 0.0))) * material_unit_price(gs, str(g))
	var spend := float(cost["build"]) + imported
	var treasury := float(gs.government.get("treasury", 0.0))
	if treasury < spend + float(cost["wages"]):
		p["status"] = "cancelado"
		p["reason"] = "sin presupuesto"
		gs.notify("Plan de gobierno cancelado por falta de presupuesto: %s." % p["label"], "info")
		return
	GovSim.add_treasury(gs, -spend)   # Obra y materiales importados: el dinero sale del pueblo.
	var b := ConstructionSim.make_building(gs, type_id, 1, float(spot["x"]), float(spot["z"]), float(spot["rot"]), "gobierno")
	var ld := GameData.level_def(type_id, 1)
	b["status"] = "construccion"
	b["work_needed"] = float(int(ld.get("build_days", 10)) * int(ld.get("workers", 2)))
	b["contractor"] = "gobierno"
	b["gov_plan"] = int(p["id"])
	b["name"] = str(ld.get("label", ""))
	BusinessSim.ledger_add(b, "obras", spend)
	gs.add_building(b)
	p["bid"] = int(b["id"])
	p["status"] = "en_obra"
	p["builder"] = "gobierno"
	p["spent"] = spend
	FreeMarketSim.stat(gs, "gov_spent", spend)
	EventBus.building_changed.emit(int(b["id"]))


# --- Día: obras terminadas y sueldos ---------------------------------------------------------------------

static func daily(gs) -> void:
	for p in plans(gs):
		if str(p["status"]) != "en_obra":
			continue
		var b: Dictionary = gs.get_building(int(p.get("bid", -1)))
		if b.is_empty():
			p["status"] = "cancelado"
			continue
		if str(b["status"]) == "activo":
			p["status"] = "terminado"
			p["done_day"] = gs.today()
			var jobs := int(gs.level_def(b).get("jobs", 0))
			if jobs > 0:
				NpcBusinessSim.fill_jobs(gs, b, jobs)
			gs.notify("Plan de gobierno cumplido: %s ya funciona." % p["label"], "importante")
			FreeMarketSim.log_event(gs, "Terminado: %s." % p["label"])
	# Sueldos del personal público (del tesoro).
	for b in gov_buildings(gs):
		if str(b["status"]) != "activo" or int(gs.level_def(b).get("jobs", 0)) <= 0:
			continue
		var unpaid := false
		for c in NpcBusinessSim.staff_of(b):
			var paid := GovSim.treasury_pay(gs, c.wage)
			c.money += paid
			BusinessSim.ledger_add(b, "salarios", paid)
			if paid + 0.0001 < c.wage:
				unpaid = true
		b["unpaid_days"] = int(b.get("unpaid_days", 0)) + 1 if unpaid else 0
		if int(b["unpaid_days"]) >= 10:
			var emps: Array = NpcBusinessSim.staff_of(b).duplicate()
			if not emps.is_empty():
				NpcBusinessSim.release(gs, emps[emps.size() - 1])
			b["unpaid_days"] = 0


static func _pay_upkeep(gs) -> void:
	var pm: float = gs.price_mult()
	for b in gov_buildings(gs):
		if str(b["status"]) != "activo":
			continue
		var led: Dictionary = b["ledger"]
		led["last_month"] = led.get("month", {})
		led["month"] = {}
		var up := float(gs.level_def(b).get("upkeep", 0.0)) * pm * 30.0
		if up > 0.0:
			var paid := GovSim.treasury_pay(gs, up)
			BusinessSim.ledger_add(b, "mantenimiento", paid)


static func _staff(gs) -> void:
	for b in gov_buildings(gs):
		var jobs := int(gs.level_def(b).get("jobs", 0))
		if str(b["status"]) != "activo" or jobs <= 0:
			continue
		for c in NpcBusinessSim.staff_of(b):
			c.wage = maxf(c.wage, BusinessSim.asked_wage(gs, c, str(b["type"])) * 0.95)
		if float(gs.government.get("treasury", 0.0)) > 0.0:
			NpcBusinessSim.fill_jobs(gs, b, jobs)


## Capacidad de servicio del gobierno (se suma a la de tus servicios en EventsSim.daily).
static func service_capacity(gs, service: String) -> float:
	var cap := 0.0
	for b in gs.buildings:
		if str(b.get("owner", "")) != "gobierno" or str(b["status"]) != "activo":
			continue
		if str(gs.building_def(b).get("gov_service", "")) != service:
			continue
		var staff := 0
		for c in gs.employees_of(int(b["id"])):
			if c.job_kind == "empleo":
				staff += 1
		cap += staff * float(gs.level_def(b).get("prod_per_worker", 1.0))
	return cap


## Escuelas públicas: niños de 6 a 15 años sin estudios; tras N años obtienen educación básica.
static func _schools(gs) -> void:
	var school: Dictionary = gs.market.get("school", {})
	var cap := 0
	for b in gov_buildings(gs):
		if str(gs.building_def(b).get("gov_service", "")) == "escuela" and str(b["status"]) == "activo":
			cap += int(NpcBusinessSim.staff_of(b).size() * float(gs.level_def(b).get("prod_per_worker", 15)))
	var today: int = gs.today()
	var years := float(cfg().get("school_years_to_graduate", 4))
	for key in school.keys():
		var c: Citizen = gs.citizens.get(int(key))
		if c == null or c.age_years(today) > 15 or c.school_id >= 0:
			school.erase(key)
	for c in kids_without_school(gs):
		if school.size() >= cap:
			break
		if not school.has(str(c.id)):
			school[str(c.id)] = 0.0
	for key in school.keys():
		school[key] = float(school[key]) + 1.0 / 12.0
		if float(school[key]) >= years:
			var c: Citizen = gs.citizens.get(int(key))
			if c != null:
				c.education = maxi(c.education, 1)
				c.school_level = maxi(c.school_level, 1)
				c.skills["ciencia"] = minf(100.0, float(c.skills.get("ciencia", 0.0)) + 5.0)
			school.erase(key)
			FreeMarketSim.stat(gs, "public_graduates", 1.0)
	gs.market["school"] = school


static func students(gs) -> int:
	return gs.market.get("school", {}).size()


## Vivienda social: familias sin hogar reciben un cupo gratuito.
static func _social_housing(gs) -> void:
	var homes := gov_buildings(gs).filter(func(b): return str(gs.building_def(b).get("gov_service", "")) == "vivienda" and str(b["status"]) == "activo")
	if homes.is_empty():
		return
	var occ := PopulationSim.home_occupancy(gs)
	var moved := 0
	for members in MarketSim.households(gs):
		var head: Citizen = members[0]
		if head.home_id >= 0 or members.any(func(m): return gs.is_player(m.id)):
			continue
		for h in homes:
			var free: int = gs.building_capacity(h) - int(occ.get(int(h["id"]), 0))
			if free >= members.size():
				for m in members:
					m.home_id = int(h["id"])
				occ[int(h["id"])] = int(occ.get(int(h["id"]), 0)) + members.size()
				moved += members.size()
				break
	if moved > 0:
		gs.notify("%d personas sin hogar recibieron vivienda social del gobierno." % moved, "info")
		EventBus.citizens_moved.emit()
