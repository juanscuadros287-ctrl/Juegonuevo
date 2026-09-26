class_name ManagerSim
extends RefCounted
## Fase 10 — Gerentes locales (docs/FASE10.md).
## Para operar en un país donde el personaje no está se contrata un gerente: un ciudadano de ese país.
## Sueldo mensual según su nivel (va a su bolsillo: el dinero no sale de la economía); su habilidad da la
## eficiencia (producción de los negocios y velocidad de las obras). Sin gerente ni presencia del
## jugador, las obras no avanzan y los negocios rinden `no_manager_output`.
## Lealtad 0-100: sube con buen sueldo y aumentos aceptados, baja si se niega un aumento o el sueldo
## queda por debajo de su nivel. Con lealtad baja puede renunciar o robar (moderado, con aviso).
## Estado: countries.presence[iso].manager = {citizen_id, name, level, skill, eff, salary, loyalty,
##   hired_day, raise {amount, until}, stolen, paid}

static func cfg() -> Dictionary:
	return CountriesSim.cfg().get("manager", {})


static func levels() -> Array:
	return cfg().get("levels", [])


static func manager(gs, iso: String) -> Dictionary:
	return CountriesSim.presence(gs, iso).get("manager", {})


static func has_manager(gs, iso: String) -> bool:
	return not manager(gs, iso).is_empty()


## Rendimiento de los negocios del jugador en el país.
static func output_mult(gs, iso: String) -> float:
	if not CountriesSim.ready(gs) or CountriesSim.location(gs) == iso:
		return 1.0
	var m := manager(gs, iso)
	if m.is_empty():
		return float(cfg().get("no_manager_output", 0.55))
	return float(m.get("eff", 0.8))


## Velocidad de las obras del jugador (0 si no avanzan: lo decide CountriesSim.works_advance).
static func work_mult(gs, iso: String) -> float:
	if not CountriesSim.ready(gs) or CountriesSim.location(gs) == iso:
		return 1.0
	var m := manager(gs, iso)
	return minf(1.0, float(m.get("eff", 0.0))) if not m.is_empty() else 0.0


# --- Contratación ---------------------------------------------------------------------------------

static func _score(gs, c: Citizen) -> float:
	var best := 0.0
	for k in c.skills:
		best = maxf(best, float(c.skills[k]))
	return float(c.education) * 18.0 + best * 0.6 + minf(c.experience, 25.0) * 1.2 + (15.0 if c.profession != "" else 0.0)


## Candidatos a gerente en el país (ciudadanos adultos de allá, los mejores primero).
static func candidates(gs, iso: String) -> Array:
	var r = CountriesSim.with_country(gs, iso, func() -> Array:
		var today: int = gs.today()
		var pool := []
		var current := int(manager(gs, iso).get("citizen_id", -1))
		for c in gs.citizens.values():
			var age: int = c.age_years(today)
			if gs.is_player(c.id) or c.id == current or age < 22 or age > 62 or c.prison_until >= 0:
				continue
			pool.append([_score(gs, c), c])
		pool.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
		var out := []
		for pair in pool.slice(0, int(cfg().get("candidates", 4))):
			out.append(_offer(gs, pair[1], float(pair[0])))
		return out)
	return r if r is Array else []


static func _offer(gs, c: Citizen, score: float) -> Dictionary:
	var lv := 0
	if score >= 70.0:
		lv = 2
	elif score >= 42.0:
		lv = 1
	lv = mini(lv, levels().size() - 1)
	var ld: Dictionary = levels()[lv]
	var skill := clampf(score / 100.0, 0.0, 1.0)
	var eff := lerpf(float(ld.get("eff_min", 0.7)), float(ld.get("eff_max", 0.9)), skill)
	var salary := snappedf(float(ld.get("salary", 60.0)) * (0.9 + skill * 0.25) * gs.price_mult(), 1.0)
	return {"citizen_id": c.id, "name": c.full_name(), "level": lv, "level_label": str(ld.get("label", "")),
			"skill": roundf(skill * 100.0), "eff": snappedf(eff, 0.01), "salary": salary}


static func hire_block_reason(gs, iso: String, citizen_id: int) -> String:
	if not CountriesSim.has_presence(gs, iso):
		return "No tienes presencia en ese país"
	var ok := false
	for o in candidates(gs, iso):
		if int(o["citizen_id"]) == citizen_id:
			ok = true
	if not ok:
		return "Ese candidato ya no está disponible"
	return ""


## Contrata como gerente a un candidato (reemplaza al anterior).
static func hire(gs, iso: String, citizen_id: int) -> String:
	var reason := hire_block_reason(gs, iso, citizen_id)
	if reason != "":
		return reason
	var offer := {}
	for o in candidates(gs, iso):
		if int(o["citizen_id"]) == citizen_id:
			offer = o
	var m := offer.duplicate()
	m["loyalty"] = 55.0 + CountriesSim.rf(gs) * 20.0
	m["hired_day"] = gs.today()
	m["raise"] = {}
	m["stolen"] = 0.0
	m["paid"] = 0.0
	m["months"] = 0
	CountriesSim.presence(gs, iso)["manager"] = m
	gs.notify("Contrataste a %s como %s en %s (sueldo %s/mes, eficiencia %d %%)." % [m["name"], str(m["level_label"]).to_lower(),
			CountriesSim.country_label(iso), Fmt.money(float(m["salary"])), int(float(m["eff"]) * 100.0)], "jugador")
	return ""


static func dismiss(gs, iso: String, reason := "") -> void:
	var m := manager(gs, iso)
	if m.is_empty():
		return
	CountriesSim.presence(gs, iso)["manager"] = {}
	gs.notify("%s dejó de ser tu gerente en %s%s." % [str(m.get("name", "")), CountriesSim.country_label(iso), (": " + reason) if reason != "" else ""], "importante")


## Acepta el aumento pedido (sube la lealtad).
static func accept_raise(gs, iso: String) -> String:
	var m := manager(gs, iso)
	var rq: Dictionary = m.get("raise", {})
	if rq.is_empty():
		return "No hay un aumento pendiente"
	m["salary"] = float(rq["amount"])
	m["loyalty"] = minf(100.0, float(m.get("loyalty", 50.0)) + 12.0)
	m["raise"] = {}
	gs.notify("Aumento aceptado: %s gana ahora %s/mes." % [m["name"], Fmt.money(float(m["salary"]))], "jugador")
	return ""


static func reject_raise(gs, iso: String) -> String:
	var m := manager(gs, iso)
	if (m.get("raise", {}) as Dictionary).is_empty():
		return "No hay un aumento pendiente"
	m["raise"] = {}
	m["loyalty"] = maxf(0.0, float(m.get("loyalty", 50.0)) - 15.0)
	return ""


# --- Ciclo --------------------------------------------------------------------------------------

## Se llama con el país `iso` cargado (pase del día de ese país).
static func country_day(gs, iso: String, new_month: bool) -> void:
	var m := manager(gs, iso)
	if m.is_empty():
		return
	var c: Citizen = gs.citizens.get(int(m.get("citizen_id", -1)))
	if c == null:
		dismiss(gs, iso, "ya no vive en el país")
		return
	var rq: Dictionary = m.get("raise", {})
	if not rq.is_empty() and gs.today() > int(rq.get("until", 0)):
		m["raise"] = {}
		m["loyalty"] = maxf(0.0, float(m.get("loyalty", 50.0)) - 15.0)
		gs.notify("%s se molestó: no respondiste a su pedido de aumento." % m["name"], "importante")
	if new_month:
		_monthly(gs, iso, m, c)


static func _monthly(gs, iso: String, m: Dictionary, c: Citizen) -> void:
	var mc := cfg()
	# Sueldo: de tu cuenta al bolsillo del gerente.
	var salary := float(m.get("salary", 0.0))
	gs.add_money(-salary)
	c.money += salary
	m["paid"] = float(m.get("paid", 0.0)) + salary
	m["months"] = int(m.get("months", 0)) + 1
	# Lealtad: sueldo frente a lo que vale hoy su nivel (inflación) y deriva hacia 60.
	var ld: Dictionary = levels()[clampi(int(m.get("level", 0)), 0, levels().size() - 1)]
	var fair: float = float(ld.get("salary", 60.0)) * gs.price_mult()
	var loyalty := float(m.get("loyalty", 50.0))
	loyalty += clampf((salary / maxf(1.0, fair) - 1.0) * 20.0, -6.0, 4.0)
	loyalty += (60.0 - loyalty) * 0.03
	m["loyalty"] = clampf(loyalty, 0.0, 100.0)
	# Pide aumento.
	if (m.get("raise", {}) as Dictionary).is_empty() and CountriesSim.rf(gs) < float(mc.get("raise_chance", 0.05)) + (0.03 if int(m["months"]) > 12 else 0.0):
		var pr: Array = mc.get("raise_pct", [0.08, 0.2])
		var pct := lerpf(float(pr[0]), float(pr[1]), CountriesSim.rf(gs))
		m["raise"] = {"amount": snappedf(salary * (1.0 + pct), 1.0), "until": gs.today() + int(mc.get("raise_days", 30))}
		gs.notify("%s, tu gerente en %s, pide un aumento a %s/mes (responde en %d días: panel Mis países)." % [m["name"], CountriesSim.country_label(iso),
				Fmt.money(float(m["raise"]["amount"])), int(mc.get("raise_days", 30))], "importante")
	# Renuncia.
	if float(m["loyalty"]) < float(mc.get("resign_loyalty", 25.0)) and CountriesSim.rf(gs) < float(mc.get("resign_chance", 0.25)):
		dismiss(gs, iso, "renunció por baja lealtad")
		return
	# Robo moderado: parte de un sueldo, con tope en % de tu dinero; el dinero pasa a su bolsillo.
	if float(m["loyalty"]) < float(mc.get("theft_loyalty", 40.0)) and CountriesSim.rf(gs) < float(mc.get("theft_chance", 0.15)):
		var tr: Array = mc.get("theft_salary_mult", [0.4, 1.2])
		var amount := salary * lerpf(float(tr[0]), float(tr[1]), CountriesSim.rf(gs))
		amount = snappedf(minf(amount, maxf(0.0, gs.money) * float(mc.get("theft_money_cap", 0.02))), 0.01)
		if amount > 0.0:
			gs.add_money(-amount)
			c.money += amount
			m["stolen"] = float(m.get("stolen", 0.0)) + amount
			gs.notify("Faltan %s en las cuentas de %s: tu gerente %s es sospechoso (lealtad %d)." % [Fmt.money(amount), CountriesSim.country_label(iso),
					m["name"], int(float(m["loyalty"]))], "importante")


## Texto corto del gerente para la interfaz.
static func label(gs, iso: String) -> String:
	if CountriesSim.location(gs) == iso:
		return "Estás aquí"
	var m := manager(gs, iso)
	if m.is_empty():
		return "Sin gerente: obras detenidas, negocios al %d %%" % int(float(cfg().get("no_manager_output", 0.55)) * 100.0)
	return "%s (%s) · eficiencia %d %% · lealtad %d · %s/mes" % [m["name"], m.get("level_label", ""), int(float(m["eff"]) * 100.0),
			int(float(m.get("loyalty", 0.0))), Fmt.money(float(m["salary"]))]
