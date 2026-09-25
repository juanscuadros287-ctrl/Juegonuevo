class_name PoliticsSim
extends RefCounted
## Sección C — política de la familia: financiar facciones y campañas, cargos públicos para
## familiares con talento político, lobby (rebaja de impuesto a un sector o licencia ambiental)
## y escándalos por corrupción.
## Estado en GameState.player["politica"] = {offices, campaigns, lobbies, factions, corruption, scandals, log}.
## Parámetros en data/dynasty.json → "politics". Economía cerrada: campañas y lobby legal se reparten
## entre ciudadanos, los sobornos van a un funcionario, sueldos y multas pasan por el tesoro.


static func cfg() -> Dictionary:
	return GameData.extra("dynasty").get("politics", {})


static func state(gs) -> Dictionary:
	var s: Dictionary = gs.player.get("politica", {})
	for k in ["offices", "campaigns", "lobbies", "log"]:
		if not s.has(k) or typeof(s[k]) != TYPE_ARRAY:
			s[k] = []
	if not s.has("factions") or typeof(s["factions"]) != TYPE_DICTIONARY:
		s["factions"] = {}
	s["corruption"] = float(s.get("corruption", 0.0))
	s["scandals"] = int(s.get("scandals", 0))
	gs.player["politica"] = s
	return s


static func _log(gs, text: String) -> void:
	var l: Array = state(gs)["log"]
	l.append({"day": gs.today(), "text": text})
	while l.size() > 30:
		l.pop_front()


static func reputation(gs) -> float:
	return float(gs.government.get("reputation", 50.0))


static func add_reputation(gs, amount: float) -> void:
	gs.government["reputation"] = clampf(reputation(gs) + amount, 0.0, 100.0)


static func corruption(gs) -> float:
	return float(state(gs)["corruption"])


## Reparte dinero entre los adultos más pobres (trabajadores de campaña, asesores…).
static func spread_to_citizens(gs, amount: float, max_people := 10) -> void:
	if amount <= 0.0:
		return
	var adults := []
	var adult := int(GameData.citizens.get("adult_age", 16))
	for c in gs.citizens.values():
		if not gs.is_player(c.id) and c.age_years(gs.today()) >= adult:
			adults.append(c)
	if adults.is_empty():
		GovSim.add_treasury(gs, amount)
		return
	adults.sort_custom(func(a, b): return a.money < b.money if a.money != b.money else a.id < b.id)
	var n := mini(max_people, adults.size())
	for i in range(n):
		adults[i].money += amount / n


# --- Facciones y campañas del gobierno ---------------------------------------------------------------

static func is_election(gs) -> bool:
	return str(GovSim.regime(gs).get("type", "decree")) == "election"


## Gobiernos a los que se puede apoyar ahora (candidatos en elecciones; facciones en virreinato).
static func supportable(gs) -> Array:
	if is_election(gs):
		return gs.government.get("candidates", []).duplicate()
	var out := []
	for id in GovSim.cfg().get("governments", {}):
		var g: Dictionary = GovSim.cfg()["governments"][id]
		if int(g.get("min_era", 1)) <= gs.era() and int(g.get("max_era", 9)) >= gs.era():
			out.append(id)
	return out


## Financia una facción (virreinato) o una campaña (elecciones, usa GovSim.donate).
static func fund(gs, gov_id: String, amount: float) -> String:
	if amount <= 0.0:
		return "Monto inválido"
	if is_election(gs):
		return GovSim.donate(gs, gov_id, amount)
	if not supportable(gs).has(gov_id):
		return "Esa facción no existe en esta época"
	if gs.money < amount:
		return "No tienes suficiente dinero"
	gs.add_money(-amount)
	spread_to_citizens(gs, amount)
	var f: Dictionary = state(gs)["factions"]
	f[gov_id] = float(f.get(gov_id, 0.0)) + amount
	var label := str(GovSim.cfg()["governments"][gov_id].get("label", gov_id))
	_log(gs, "Apoyo de %s a la facción %s." % [Fmt.money(amount), label])
	return "Apoyaste a la facción «%s» con %s: más probable que la Corona la elija en el próximo cambio." % [label, Fmt.money(amount)]


## Probabilidad de que la facción más apoyada gane el próximo cambio de virrey.
static func faction_chance(gs) -> Dictionary:
	var f: Dictionary = state(gs)["factions"]
	var best := ""
	var total := 0.0
	for id in f:
		if not supportable(gs).has(id):
			continue
		total += float(f[id])
		if best == "" or float(f[id]) > float(f[best]):
			best = id
	var base: float = float(cfg().get("faction_base_support", 600)) * gs.price_mult()
	return {"gov": best, "chance": total / (total + base) if total > 0.0 else 0.0}


## Llamado por GovSim al cambiar de virrey: devuelve la facción apoyada si gana, o "".
static func pick_decree_gov(gs, exclude: String) -> String:
	var fc := faction_chance(gs)
	state(gs)["factions"] = {}
	if str(fc["gov"]) == "" or str(fc["gov"]) == exclude:
		return ""
	if gs.rng.randf() < float(fc["chance"]):
		_log(gs, "La facción que apoyaste llegó al poder.")
		return str(fc["gov"])
	return ""


# --- Cargos públicos ---------------------------------------------------------------------------------

static func office_def(office: String) -> Dictionary:
	return cfg().get("offices", {}).get(office, {})


static func offices_available(gs) -> Array:
	var out := []
	for id in cfg().get("offices", {}):
		if gs.era() >= int(office_def(id).get("min_era", 1)):
			out.append(id)
	return out


static func office_of(gs, cid: int) -> Dictionary:
	for o in state(gs)["offices"]:
		if int(o["cid"]) == cid:
			return o
	return {}


static func campaign_of(gs, cid: int) -> Dictionary:
	for c in state(gs)["campaigns"]:
		if int(c["cid"]) == cid:
			return c
	return {}


static func campaign_cost(gs, office: String) -> float:
	return float(office_def(office).get("campaign_cost", 100)) * gs.price_mult()


## Quién puede postularse: tú o un familiar adulto con talento político.
static func can_run(gs, c: Citizen, office: String) -> String:
	var d := office_def(office)
	if d.is_empty():
		return "Cargo desconocido"
	if gs.era() < int(d.get("min_era", 1)):
		return "Disponible desde la %s" % GameData.era_label(int(d.get("min_era", 1)))
	if not gs.is_player(c.id) and not HeirsSim.family_members(gs).has(c):
		return "Solo tu familia"
	if c.age_years(gs.today()) < 21:
		return "Debe tener 21 años o más"
	if c.prison_until >= 0:
		return "Está en la cárcel"
	if not office_of(gs, c.id).is_empty() or not campaign_of(gs, c.id).is_empty():
		return "Ya tiene un cargo o una campaña"
	for o in state(gs)["offices"]:
		if str(o["office"]) == office:
			return "Tu familia ya ocupa ese cargo"
	var t := HeirsSim.talent(gs, c, "politica")
	if t < float(d.get("min_talent", 30)):
		return "Talento político %d/%d" % [int(t), int(d.get("min_talent", 30))]
	if reputation(gs) < float(cfg().get("office_min_reputation", 20)):
		return "Tu reputación es muy baja"
	return ""


static func win_chance(gs, c: Citizen, office: String, spent: float) -> float:
	var d := office_def(office)
	var t := HeirsSim.talent(gs, c, "politica")
	var ch := float(cfg().get("win_base", 0.2)) + (t - float(d.get("min_talent", 30))) / 100.0 * 0.8
	ch += (reputation(gs) - 50.0) / 150.0
	ch += clampf(spent / maxf(1.0, campaign_cost(gs, office)) - 1.0, 0.0, 2.0) * 0.1
	ch += HeirsSim.head_bonus(gs, "politica")
	return clampf(ch, 0.1, 0.85)


## Se postula: paga la campaña (se reparte entre ciudadanos) y las elecciones son en unos meses.
static func run_for_office(gs, c: Citizen, office: String, extra := 0.0) -> String:
	var r := can_run(gs, c, office)
	if r != "":
		return r
	var cost := campaign_cost(gs, office) + maxf(0.0, extra)
	if gs.money < cost:
		return "La campaña cuesta %s" % Fmt.money(cost)
	gs.add_money(-cost)
	spread_to_citizens(gs, cost)
	var d := office_def(office)
	state(gs)["campaigns"].append({"cid": c.id, "office": office, "spent": cost,
		"resolve_day": gs.today() + int(d.get("campaign_months", 3)) * 30})
	_log(gs, "%s se postuló a %s." % [c.full_name(), d.get("label", office)])
	return "%s se postuló a %s (campaña %s, probabilidad ≈ %d%%)." % [c.first_name, d.get("label", office), Fmt.money(cost), int(win_chance(gs, c, office, cost) * 100.0)]


## Resuelve una campaña. roll < 0 → aleatorio (para pruebas se puede forzar).
static func resolve_campaign(gs, camp: Dictionary, roll := -1.0) -> bool:
	state(gs)["campaigns"].erase(camp)
	var c: Citizen = gs.citizens.get(int(camp["cid"]))
	var office := str(camp["office"])
	var d := office_def(office)
	if c == null:
		return false
	if roll < 0.0:
		roll = gs.rng.randf()
	if roll >= win_chance(gs, c, office, float(camp.get("spent", 0.0))):
		gs.notify("%s perdió la elección a %s." % [c.full_name(), d.get("label", office)], "jugador")
		_log(gs, "%s perdió la elección a %s." % [c.full_name(), d.get("label", office)])
		return false
	take_office(gs, c, office)
	return true


static func take_office(gs, c: Citizen, office: String) -> void:
	var d := office_def(office)
	_leave_job(gs, c)
	state(gs)["offices"].append({"cid": c.id, "office": office, "since": gs.today(),
		"until": gs.today() + int(d.get("term_years", 4)) * 365})
	add_reputation(gs, float(d.get("reputation", 3)))
	gs.notify("¡%s ganó y ahora es %s! Sueldo público, menos impuestos e influencia; deja su empleo y debe cuidar la reputación." % [c.full_name(), str(d.get("label", office)).to_lower()], "jugador")
	_log(gs, "%s asumió como %s." % [c.full_name(), d.get("label", office)])


## Obligación del cargo: deja su empleo.
static func _leave_job(gs, c: Citizen) -> void:
	if c.job_id < 0 or gs.is_player(c.id):
		return
	var b: Dictionary = gs.get_building(c.job_id)
	if not b.is_empty() and gs.owned_by_player(b):
		BusinessSim.fire(gs, c)
	elif not b.is_empty() and NpcBusinessSim.is_npc(b):
		NpcBusinessSim.release(gs, c)
	else:
		c.job_id = -1
		c.job_kind = ""
		c.wage = 0.0


static func _end_office(gs, o: Dictionary, reason: String) -> void:
	state(gs)["offices"].erase(o)
	var label := str(office_def(str(o["office"])).get("label", o["office"]))
	gs.notify("%s dejó el cargo de %s (%s)." % [gs.person_name(int(o["cid"])), label.to_lower(), reason], "jugador")
	_log(gs, "%s dejó el cargo de %s (%s)." % [gs.person_name(int(o["cid"])), label, reason])


static func influence(gs) -> float:
	var v := 0.0
	for o in state(gs)["offices"]:
		v += float(office_def(str(o["office"])).get("influence", 0.0))
	return v


# --- Lobby --------------------------------------------------------------------------------------------

static func lobby_cfg() -> Dictionary:
	return cfg().get("lobby", {})


## Sectores de tus negocios (campo "sector" de cada tipo).
static func player_sectors(gs) -> Array:
	var out := []
	for b in gs.player_buildings():
		var s := str(gs.building_def(b).get("sector", ""))
		if s != "" and not out.has(s):
			out.append(s)
	out.sort()
	return out


static func lobby_cost(gs, kind: String, bribe: bool) -> float:
	var base: float = float(lobby_cfg().get("tax_cost" if kind == "impuesto" else "license_cost", 300)) * gs.price_mult()
	return base * (float(lobby_cfg().get("bribe_cost_factor", 0.6)) if bribe else 1.0)


static func lobby_chance(gs, bribe: bool) -> float:
	var ch := float(lobby_cfg().get("bribe_chance" if bribe else "legal_chance", 0.5))
	ch += influence(gs) * 0.5 + HeirsSim.head_bonus(gs, "politica")
	return clampf(ch, 0.05, 0.95)


static func active_lobby(gs, kind: String, target: String) -> Dictionary:
	for l in state(gs)["lobbies"]:
		if str(l["kind"]) == kind and str(l["target"]) == target and int(l["until"]) >= gs.today():
			return l
	return {}


static func has_license(gs, target := "ambiental") -> bool:
	return not active_lobby(gs, "licencia", target).is_empty()


## kind "impuesto" (target = sector) o "licencia" (target "ambiental": sin multas ambientales).
## bribe = soborno: más barato y probable, pero suma corrupción (riesgo de escándalo).
static func lobby(gs, kind: String, target: String, bribe: bool, roll := -1.0) -> String:
	if kind == "impuesto" and not player_sectors(gs).has(target):
		return "No tienes negocios en ese sector"
	if kind != "impuesto" and kind != "licencia":
		return "Tipo de lobby desconocido"
	if not active_lobby(gs, kind, target).is_empty():
		return "Ya lo tienes vigente"
	var cost := lobby_cost(gs, kind, bribe)
	if gs.money < cost:
		return "Necesitas %s" % Fmt.money(cost)
	gs.add_money(-cost)
	var what := "rebaja de impuesto al sector %s" % target if kind == "impuesto" else "licencia %s" % target
	if bribe:
		_pay_official(gs, cost)
		state(gs)["corruption"] = minf(100.0, corruption(gs) + float(lobby_cfg().get("bribe_corruption", 22)))
	else:
		spread_to_citizens(gs, cost, 5)
	if roll < 0.0:
		roll = gs.rng.randf()
	if roll >= lobby_chance(gs, bribe):
		add_reputation(gs, float(lobby_cfg().get("fail_reputation", -2)))
		_log(gs, "Lobby fallido: %s." % what)
		return "El lobby no funcionó: no conseguiste la %s." % what
	var years := int(lobby_cfg().get("years", 3))
	state(gs)["lobbies"].append({"kind": kind, "target": target, "until": gs.today() + years * 365, "bribe": bribe, "since": gs.today()})
	_log(gs, "Conseguiste %s (%d años)%s." % [what, years, " con soborno" if bribe else ""])
	gs.notify("Lobby: conseguiste %s por %d años." % [what, years], "negocio")
	return "¡Conseguiste %s por %d años!" % [what, years]


## El soborno va a un funcionario del pueblo (empleado público o el adulto más rico que no es tu familia).
static func _pay_official(gs, amount: float) -> void:
	var fam := HeirsSim.family_members(gs)
	var best: Citizen = null
	for c in gs.citizens.values():
		if gs.is_player(c.id) or fam.has(c) or c.age_years(gs.today()) < 21:
			continue
		var b: Dictionary = gs.get_building(c.job_id) if c.job_id >= 0 else {}
		var public: bool = not b.is_empty() and str(b.get("owner", "")) == "gobierno"
		if best == null or (public and not _is_public(gs, best)) or (public == _is_public(gs, best) and c.money > best.money):
			best = c
	if best != null:
		best.money += amount
	else:
		GovSim.add_treasury(gs, amount)


static func _is_public(gs, c: Citizen) -> bool:
	var b: Dictionary = gs.get_building(c.job_id) if c.job_id >= 0 else {}
	return not b.is_empty() and str(b.get("owner", "")) == "gobierno"


# --- Efectos en impuestos -----------------------------------------------------------------------------

## Multiplicador del impuesto a las ganancias de un negocio tuyo: talento político del jefe,
## cargos de la familia y lobby de su sector (con tope moderado).
static func profit_tax_mult(gs, b: Dictionary) -> float:
	var cut := HeirsSim.head_bonus(gs, "politica")
	for o in state(gs)["offices"]:
		cut += float(office_def(str(o["office"])).get("tax_cut", 0.0))
	var sector := str(gs.building_def(b).get("sector", ""))
	if sector != "" and not active_lobby(gs, "impuesto", sector).is_empty():
		cut += float(lobby_cfg().get("sector_tax_cut", 0.25))
	return 1.0 - clampf(cut, 0.0, float(cfg().get("max_tax_cut", 0.35)))


# --- Escándalos ----------------------------------------------------------------------------------------

static func scandal_chance(gs) -> float:
	return corruption(gs) * float(cfg().get("scandal_monthly_per_point", 0.0008))


## Escándalo: multa al tesoro, pérdida de reputación, caída de los cargos y de lo conseguido con sobornos.
static func scandal(gs) -> String:
	var s := state(gs)
	var fine: float = (float(cfg().get("scandal_fine_min", 200)) + corruption(gs) * float(cfg().get("scandal_fine_per_point", 8))) * gs.price_mult()
	var paid := clampf(fine, 0.0, maxf(0.0, gs.money))
	if paid > 0.0:
		gs.add_money(-paid)
		GovSim.add_treasury(gs, paid)
		gs.add_counter("taxes_paid", paid)
	add_reputation(gs, float(cfg().get("scandal_reputation", -15)))
	var fallen := []
	for o in s["offices"].duplicate():
		fallen.append("%s (%s)" % [gs.person_name(int(o["cid"])), str(office_def(str(o["office"])).get("label", o["office"])).to_lower()])
		s["offices"].erase(o)
	var revoked := 0
	for l in s["lobbies"].duplicate():
		if bool(l.get("bribe", false)):
			s["lobbies"].erase(l)
			revoked += 1
	s["corruption"] = corruption(gs) * 0.3
	s["scandals"] = int(s["scandals"]) + 1
	var text := "¡Escándalo de corrupción! La familia paga una multa de %s y pierde reputación." % Fmt.money(paid)
	if not fallen.is_empty():
		text += " Cae del cargo: %s." % ", ".join(fallen)
	if revoked > 0:
		text += " Se anulan %d beneficio(s) obtenidos con sobornos." % revoked
	gs.notify(text, "jugador")
	_log(gs, text)
	return text


# --- Ciclo mensual -------------------------------------------------------------------------------------

static func monthly(gs) -> void:
	var s := state(gs)
	var today: int = gs.today()
	# Campañas que llegan a elecciones.
	for camp in s["campaigns"].duplicate():
		if today >= int(camp["resolve_day"]):
			resolve_campaign(gs, camp)
	# Cargos: sueldo desde el tesoro, fin del período, destitución por reputación.
	for o in s["offices"].duplicate():
		var c: Citizen = gs.citizens.get(int(o["cid"]))
		if c == null:
			_end_office(gs, o, "falleció")
			continue
		if c.prison_until >= 0:
			_end_office(gs, o, "fue a la cárcel")
			continue
		if today >= int(o["until"]):
			_end_office(gs, o, "terminó su período")
			continue
		if reputation(gs) < float(cfg().get("office_min_reputation", 20)):
			_end_office(gs, o, "destituido por la mala reputación de la familia")
			continue
		var salary := GovSim.treasury_pay(gs, float(office_def(str(o["office"])).get("salary", 0.0)) * gs.price_mult())
		if salary > 0.0:
			if gs.is_player(c.id):
				gs.add_money(salary)
			else:
				c.money += salary
		if c.job_id >= 0:
			_leave_job(gs, c)
	# Lobby vencido.
	for l in s["lobbies"].duplicate():
		if int(l["until"]) < today:
			s["lobbies"].erase(l)
	# Artes del jefe de familia: prestigio.
	var art := HeirsSim.head_bonus(gs, "artes")
	if art > 0.0:
		add_reputation(gs, art)
	# Corrupción: riesgo de escándalo y olvido lento.
	if corruption(gs) > 0.0:
		if gs.rng.randf() < scandal_chance(gs):
			scandal(gs)
		s["corruption"] = maxf(0.0, corruption(gs) - float(cfg().get("corruption_decay", 1.5)))
