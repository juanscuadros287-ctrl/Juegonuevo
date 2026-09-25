class_name LaborSim
extends RefCounted
## Trabajo (sección B de docs/PENDIENTES.md, ver docs/TRABAJO_MUNDO.md). Todo moderado.
##
## - Experiencia por oficio: cada empleado acumula años en el sector (la habilidad del negocio) en
##   Citizen.trade_exp. Rinde hasta +20 % (veterano, 10 años) y pide algo más de sueldo. Si se va o
##   lo despiden, la experiencia se va con él (la competencia NPC puede contratarlo).
## - Sindicatos y huelgas (desde la época industrial): con sueldos bajo el mercado, poca felicidad o
##   falta de personal, los empleados de un negocio piden un aumento. El jugador acepta, hace una
##   contraoferta o rechaza; si rechaza (o no responde a tiempo) hay una huelga corta de 3–10 días
##   con producción al 0–30 %, que termina con un acuerdo (la mitad del aumento pedido).
## - Competencia NPC: las empresas NPC bajan precios temporalmente cuando compiten con un negocio
##   tuyo (nunca por debajo de su costo) y ofrecen más sueldo a tus mejores empleados (puedes igualar).
## Estado: GameState.labor. RNG propio y determinista (semilla + día + sal): no altera el resto.

const U_DEMAND := "demanda"
const U_STRIKE := "huelga"


static func cfg() -> Dictionary:
	return GameData.extra("trabajo_mundo")


static func ecfg() -> Dictionary:
	return cfg().get("experience", {})


static func ucfg() -> Dictionary:
	return cfg().get("unions", {})


static func ncfg() -> Dictionary:
	return cfg().get("npc", {})


static func init_state(gs) -> void:
	var l: Dictionary = gs.labor
	for k in ["unions", "price_wars", "cooldown"]:
		if not l.has(k) or not (l[k] is Dictionary):
			l[k] = {}
	if not l.has("offers") or not (l["offers"] is Array):
		l["offers"] = []
	l["next_id"] = int(l.get("next_id", 1))
	gs.labor = l
	if not bool(l.get("seeded", false)):
		seed_experience(gs)
		l["seeded"] = true


# --- RNG propio ---------------------------------------------------------------------------------------

static func rf(gs, salt: String) -> float:
	var r := RandomNumberGenerator.new()
	r.seed = hash("%d|%d|%s" % [int(gs.settings.get("seed", 0)), int(gs.today()), salt])
	return r.randf()


static func rr(gs, salt: String, arr: Array) -> float:
	if arr.size() < 2:
		return float(arr[0]) if not arr.is_empty() else 0.0
	return lerpf(float(arr[0]), float(arr[1]), rf(gs, salt))


static func ri(gs, salt: String, arr: Array) -> int:
	return int(round(rr(gs, salt, arr)))


static func _next_id(gs) -> int:
	var id := int(gs.labor.get("next_id", 1))
	gs.labor["next_id"] = id + 1
	return id


# --- Experiencia por oficio ------------------------------------------------------------------------------

## Años de experiencia de un ciudadano en un oficio (habilidad del sector).
static func years(c: Citizen, skill: String) -> float:
	return float(c.trade_exp.get(skill, 0.0)) if skill != "" else 0.0


static func veteran_share(c: Citizen, skill: String) -> float:
	return clampf(years(c, skill) / maxf(0.1, float(ecfg().get("veteran_years", 10.0))), 0.0, 1.0)


## Multiplicador de rendimiento por experiencia en el oficio (1 … 1,2).
static func exp_mult(c: Citizen, skill: String) -> float:
	return 1.0 + float(ecfg().get("max_bonus", 0.2)) * veteran_share(c, skill)


## Multiplicador del sueldo que pide por su experiencia (1 … 1,1).
static func wage_mult(c: Citizen, skill: String) -> float:
	return 1.0 + float(ecfg().get("wage_bonus", 0.1)) * veteran_share(c, skill)


## Texto corto para la interfaz: "oficio 4,2 a (+8 %)".
static func exp_text(c: Citizen, skill: String) -> String:
	var y := years(c, skill)
	return "oficio %.1f a (+%d %%)" % [y, int(round((exp_mult(c, skill) - 1.0) * 100.0))]


## Ficha del ciudadano: "Agricultura 4,2 a (+8 %), Minería 1,0 a (+2 %)".
static func trades_text(c: Citizen) -> String:
	var keys := c.trade_exp.keys().filter(func(k): return float(c.trade_exp[k]) >= 0.1)
	if keys.is_empty():
		return "sin experiencia de oficio"
	keys.sort_custom(func(a, b): return float(c.trade_exp[a]) > float(c.trade_exp[b]))
	var parts := []
	for k in keys:
		parts.append("%s %.1f a (+%d %%)" % [GameData.skill_label(str(k)), float(c.trade_exp[k]), int(round((exp_mult(c, str(k)) - 1.0) * 100.0))])
	return ", ".join(parts)


## Partidas nuevas o viejas: los adultos que ya trabajaron traen parte de su experiencia en su mejor habilidad.
static func seed_experience(gs) -> void:
	var share := float(ecfg().get("initial_share", 0.5))
	for c in gs.citizens.values():
		if c.trade_exp.is_empty() and c.experience > 0.0:
			var sk: String = c.best_skill()
			if sk != "":
				c.trade_exp[sk] = snappedf(c.experience * share, 0.01)


static func _accumulate(gs) -> void:
	var step := 1.0 / 365.0
	for c in gs.citizens.values():
		if c.job_id < 0 or (c.job_kind != "empleo" and c.job_kind != "dueño"):
			continue
		var b: Dictionary = gs.get_building(c.job_id)
		if b.is_empty():
			continue
		var skill := str(gs.building_def(b).get("skill", ""))
		if skill == "":
			continue
		c.trade_exp[skill] = float(c.trade_exp.get(skill, 0.0)) + step


# --- Ciclos ------------------------------------------------------------------------------------------------

static func daily(gs) -> void:
	_accumulate(gs)
	_unions_daily(gs)
	_price_wars_daily(gs)
	_offers_daily(gs)


static func monthly(gs) -> void:
	_unions_monthly(gs)
	_price_wars_monthly(gs)
	_poach_monthly(gs)


# --- Sindicatos y huelgas -----------------------------------------------------------------------------------

static func staff(gs, b: Dictionary) -> Array:
	return gs.employees_of(int(b["id"])).filter(func(c): return c.job_kind == "empleo")


static func union_of(gs, b: Dictionary) -> Dictionary:
	return gs.labor.get("unions", {}).get(str(int(b["id"])), {})


static func on_strike(gs, b: Dictionary) -> bool:
	return str(union_of(gs, b).get("state", "")) == U_STRIKE


## Multiplicador de producción por huelga (1 sin huelga; 0–0,3 durante el paro).
static func strike_mult(gs, b: Dictionary) -> float:
	var unions: Dictionary = gs.labor.get("unions", {})
	if unions.is_empty():
		return 1.0
	var u: Dictionary = unions.get(str(int(b.get("id", -1))), {})
	if str(u.get("state", "")) != U_STRIKE:
		return 1.0
	return float(u.get("factor", 0.0))


## Condiciones del personal: {"ratio" sueldo/pedido, "happiness", "overwork", "staff", "score"}.
static func grievance(gs, b: Dictionary) -> Dictionary:
	var uc := ucfg()
	var emps := staff(gs, b)
	var wages := 0.0
	var asked := 0.0
	var hap := 0.0
	for c in emps:
		wages += c.wage
		asked += BusinessSim.asked_wage(gs, c, str(b["type"]))
		hap += c.happiness
	var n := emps.size()
	var ratio := wages / maxf(0.01, asked) if n > 0 else 1.0
	hap = hap / n if n > 0 else 60.0
	var jobs := int(gs.level_def(b).get("jobs", 1))
	var overwork := jobs >= 4 and n < int(ceil(jobs * float(uc.get("overwork_ratio", 0.5))))
	var w := clampf((float(uc.get("wage_ratio_ok", 0.97)) - ratio) / 0.3, 0.0, 1.0)
	var h := clampf((float(uc.get("happiness_ok", 50.0)) - hap) / 30.0, 0.0, 1.0)
	var score := w + h * 0.7 + (0.4 if overwork else 0.0)
	return {"ratio": ratio, "happiness": hap, "overwork": overwork, "staff": n, "score": score}


static func _unions_monthly(gs) -> void:
	var uc := ucfg()
	if gs.era() < int(uc.get("min_era", 2)):
		return
	var unions: Dictionary = gs.labor["unions"]
	var cool: Dictionary = gs.labor["cooldown"]
	var today: int = gs.today()
	var freq := float(gs.diff().get("event_freq_mult", 1.0))
	for b in gs.buildings:
		if not gs.owned_by_player(b) or str(b["status"]) != "activo" or not BusinessSim.is_business(b):
			continue
		var key := str(int(b["id"]))
		if unions.has(key) or int(cool.get("u" + key, -1)) > today:
			continue
		var g := grievance(gs, b)
		if int(g["staff"]) < int(uc.get("min_staff", 3)) or float(g["score"]) <= 0.0:
			continue
		var chance := minf(float(uc.get("max_chance", 0.1)), float(uc.get("base_chance", 0.12)) * float(g["score"])) * freq
		if rf(gs, "union" + key) >= chance:
			continue
		start_demand(gs, b, g)


## Los empleados se organizan y piden un aumento (también lo usan las pruebas).
static func start_demand(gs, b: Dictionary, g := {}) -> Dictionary:
	var uc := ucfg()
	if g.is_empty():
		g = grievance(gs, b)
	var rr_: Array = uc.get("raise_range", [0.06, 0.18])
	var ratio := float(g.get("ratio", 1.0))
	var pct := clampf((1.0 / maxf(0.3, ratio) - 1.0) + 0.04, float(rr_[0]), float(rr_[1]))
	pct = snappedf(pct, 0.01)
	var why := []
	if ratio < float(uc.get("wage_ratio_ok", 0.97)):
		why.append("sueldos bajo el mercado")
	if float(g.get("happiness", 60.0)) < float(uc.get("happiness_ok", 50.0)):
		why.append("malas condiciones")
	if bool(g.get("overwork", false)):
		why.append("demasiadas horas por falta de personal")
	if why.is_empty():
		why.append("mejores condiciones")
	var u := {"state": U_DEMAND, "pct": pct, "day": gs.today(), "deadline": gs.today() + int(uc.get("reply_days", 14)),
		"reason": ", ".join(why), "label": gs.building_label(b)}
	gs.labor["unions"][str(int(b["id"]))] = u
	gs.count("union_demands")
	gs.notify("SINDICATO en %s: los %d empleados piden +%d %% de sueldo (%s). Responde en la pestaña Empleados antes de %d días o harán huelga." % [
		gs.building_label(b), int(g.get("staff", 0)), int(round(pct * 100.0)), u["reason"], int(uc.get("reply_days", 14))], "importante")
	return u


static func _raise_wages(gs, b: Dictionary, pct: float, happy: float) -> int:
	var n := 0
	for c in staff(gs, b):
		c.wage = snappedf(c.wage * (1.0 + pct), 0.01)
		c.happiness = clampf(c.happiness + happy, 0.0, 100.0)
		n += 1
	return n


static func _close_union(gs, b: Dictionary) -> void:
	var key := str(int(b["id"]))
	gs.labor["unions"].erase(key)
	gs.labor["cooldown"]["u" + key] = gs.today() + int(ucfg().get("cooldown_days", 360))


## Aceptar el aumento pedido.
static func accept_demand(gs, b: Dictionary) -> String:
	var u := union_of(gs, b)
	if str(u.get("state", "")) != U_DEMAND:
		return "No hay un pedido pendiente."
	var pct := float(u["pct"])
	var n := _raise_wages(gs, b, pct, float(ucfg().get("accept_happiness", 5.0)))
	_close_union(gs, b)
	gs.notify("Aceptaste el pedido del sindicato de %s: +%d %% de sueldo a %d empleados." % [gs.building_label(b), int(round(pct * 100.0)), n], "negocio")
	return ""


## Contraoferta: si es al menos la mitad de lo pedido, la aceptan con una probabilidad que crece con
## el monto; si no, van a la huelga. Devuelve "" si aceptaron, o el motivo.
static func counter_offer(gs, b: Dictionary, pct2: float) -> String:
	var u := union_of(gs, b)
	if str(u.get("state", "")) != U_DEMAND:
		return "No hay un pedido pendiente."
	var pct := float(u["pct"])
	pct2 = maxf(0.0, pct2)
	if pct2 >= pct - 0.0001:
		return accept_demand(gs, b)
	var min_r := float(ucfg().get("counter_min_ratio", 0.5))
	var r := pct2 / maxf(0.001, pct)
	var p := 0.0 if r < min_r else 0.4 + 0.6 * (r - min_r) / maxf(0.01, 1.0 - min_r)
	if rf(gs, "counter%d" % int(b["id"])) < p:
		var n := _raise_wages(gs, b, pct2, float(ucfg().get("accept_happiness", 5.0)) * 0.6)
		_close_union(gs, b)
		gs.notify("El sindicato de %s aceptó tu contraoferta: +%d %% de sueldo a %d empleados." % [gs.building_label(b), int(round(pct2 * 100.0)), n], "negocio")
		return ""
	start_strike(gs, b, "rechazó tu contraoferta")
	return "El sindicato rechazó la contraoferta: huelga."


## Rechazar el pedido: huelga corta.
static func reject_demand(gs, b: Dictionary) -> String:
	var u := union_of(gs, b)
	if str(u.get("state", "")) != U_DEMAND:
		return "No hay un pedido pendiente."
	start_strike(gs, b, "rechazaste el pedido")
	return ""


static func start_strike(gs, b: Dictionary, why: String) -> void:
	var uc := ucfg()
	var key := str(int(b["id"]))
	var u: Dictionary = gs.labor["unions"].get(key, {"pct": float(uc.get("raise_range", [0.06, 0.18])[0])})
	var days := ri(gs, "strike_days" + key, uc.get("strike_days", [3, 10]))
	u["state"] = U_STRIKE
	u["start"] = gs.today()
	u["until"] = gs.today() + maxi(1, days)
	u["factor"] = snappedf(rr(gs, "strike_out" + key, uc.get("strike_output", [0.0, 0.3])), 0.01)
	u["label"] = gs.building_label(b)
	gs.labor["unions"][key] = u
	for c in staff(gs, b):
		c.happiness = clampf(c.happiness + float(uc.get("strike_happiness", -4.0)), 0.0, 100.0)
	gs.count("strikes")
	gs.notify("HUELGA en %s (%s): producción al %d %% durante unos %d días." % [gs.building_label(b), why, int(round(float(u["factor"]) * 100.0)), days], "importante")
	EventBus.building_changed.emit(int(b["id"]))


static func _unions_daily(gs) -> void:
	var unions: Dictionary = gs.labor.get("unions", {})
	if unions.is_empty():
		return
	var today: int = gs.today()
	for key in unions.keys():
		var u: Dictionary = unions[key]
		var b: Dictionary = gs.get_building(int(key))
		if b.is_empty() or not gs.owned_by_player(b) or str(b["status"]) == "cerrado":
			unions.erase(key)
			continue
		if str(u.get("state", "")) == U_DEMAND and today >= int(u.get("deadline", today)):
			start_strike(gs, b, "no respondiste al pedido")
		elif str(u.get("state", "")) == U_STRIKE and today >= int(u.get("until", today)):
			var pct := snappedf(float(u.get("pct", 0.06)) * float(ucfg().get("settlement_ratio", 0.5)), 0.01)
			var n := _raise_wages(gs, b, pct, 2.0)
			_close_union(gs, b)
			gs.notify("Terminó la huelga en %s: acuerdo de +%d %% de sueldo para %d empleados. La producción vuelve a la normalidad." % [gs.building_label(b), int(round(pct * 100.0)), n], "negocio")
			EventBus.building_changed.emit(int(b["id"]))


# --- Competencia NPC: guerras de precio -------------------------------------------------------------------

static func price_war_of(gs, b: Dictionary) -> Dictionary:
	return gs.labor.get("price_wars", {}).get(str(int(b["id"])), {})


static func _player_rival(gs, product: String) -> Dictionary:
	for b in gs.buildings:
		if gs.owned_by_player(b) and str(b["status"]) == "activo" and str(gs.building_def(b).get("product", "")) == product:
			return b
	return {}


static func _price_wars_monthly(gs) -> void:
	var nc := ncfg()
	var wars: Dictionary = gs.labor["price_wars"]
	var cool: Dictionary = gs.labor["cooldown"]
	var today: int = gs.today()
	for b in NpcBusinessSim.npc_buildings(gs):
		var key := str(int(b["id"]))
		if wars.has(key) or str(b["status"]) != "activo" or str(b.get("npc_state", "")) != NpcBusinessSim.STATE_OPEN:
			continue
		if int(cool.get("w" + key, -1)) > today:
			continue
		var product := str(gs.building_def(b).get("product", ""))
		var rival := _player_rival(gs, product)
		if rival.is_empty():
			continue
		if rf(gs, "pwar" + key) >= float(nc.get("price_war_chance", 0.1)):
			continue
		start_price_war(gs, b, rival)


## La empresa NPC baja su margen sin vender a pérdida: el recorte sale de su margen de ganancia.
## Devuelve el recorte aplicado (0 si no puede bajar sin perder).
static func start_price_war(gs, b: Dictionary, rival: Dictionary) -> float:
	var nc := ncfg()
	var sales := BusinessSim.period_value(b, "last_month", "ventas")
	var profit := BusinessSim.period_profit(b, "last_month")
	var margin := profit / sales if sales > 0.0 else 0.0
	if margin <= 0.02:
		return 0.0
	var markup := float(b.get("markup", 0.08))
	var cut := minf(float(nc.get("price_war_max_cut", 0.12)), margin * float(nc.get("price_war_margin_share", 0.7)) * (1.0 + markup))
	cut = snappedf(cut, 0.005)
	if cut <= 0.0:
		return 0.0
	var key := str(int(b["id"]))
	var days := ri(gs, "pwar_days" + key, nc.get("price_war_days", [30, 75]))
	gs.labor["price_wars"][key] = {"until": gs.today() + days, "base_markup": markup, "cut": cut,
		"rival": int(rival.get("id", -1)), "label": gs.building_label(b)}
	b["markup"] = markup - cut
	var product := str(gs.building_def(b).get("product", ""))
	b["price"] = clampf(snappedf(EconomySim.market_price(gs, product) * (1.0 + float(b["markup"])), 0.01), 0.01, BusinessSim.max_price(gs, b))
	gs.notify("Competencia: %s bajó sus precios un %d %% para quitarle clientes a tu %s (por unos %d días, sin vender a pérdida)." % [
		gs.building_label(b), int(round(cut / (1.0 + markup) * 100.0)), gs.building_label(rival) if not rival.is_empty() else "negocio", days], "negocio")
	return cut


static func end_price_war(gs, key: String) -> void:
	var w: Dictionary = gs.labor["price_wars"].get(key, {})
	gs.labor["price_wars"].erase(key)
	gs.labor["cooldown"]["w" + key] = gs.today() + int(ncfg().get("price_war_cooldown_days", 240))
	var b: Dictionary = gs.get_building(int(key))
	if b.is_empty() or not NpcBusinessSim.is_npc(b):
		return
	b["markup"] = float(w.get("base_markup", b.get("markup", 0.08)))
	gs.notify("%s volvió a sus precios normales." % gs.building_label(b), "negocio")


static func _price_wars_daily(gs) -> void:
	var wars: Dictionary = gs.labor.get("price_wars", {})
	if wars.is_empty():
		return
	for key in wars.keys():
		var b: Dictionary = gs.get_building(int(key))
		if b.is_empty() or not NpcBusinessSim.is_npc(b) or gs.today() >= int(wars[key].get("until", 0)):
			end_price_war(gs, key)


# --- Competencia NPC: ofertas a tus empleados ------------------------------------------------------------

static func pending_offers(gs, b := {}) -> Array:
	return gs.labor.get("offers", []).filter(func(o): return str(o.get("status", "")) == "pendiente" and (b.is_empty() or int(o["from"]) == int(b["id"])))


static func _poach_monthly(gs) -> void:
	var nc := ncfg()
	var cool: Dictionary = gs.labor["cooldown"]
	var today: int = gs.today()
	var freq := float(gs.diff().get("event_freq_mult", 1.0))
	for npc in NpcBusinessSim.npc_buildings(gs):
		if str(npc["status"]) != "activo" or str(npc.get("npc_state", "")) != NpcBusinessSim.STATE_OPEN:
			continue
		var key := str(int(npc["id"]))
		if int(cool.get("p" + key, -1)) > today:
			continue
		if NpcBusinessSim.staff_count(gs, npc) >= int(gs.level_def(npc).get("jobs", 1)):
			continue
		if rf(gs, "poach" + key) >= float(nc.get("poach_chance", 0.06)) * freq:
			continue
		make_offer(gs, npc)


## La empresa NPC ofrece más sueldo a tu empleado más experimentado del mismo oficio. Devuelve la oferta o {}.
static func make_offer(gs, npc: Dictionary, target: Citizen = null) -> Dictionary:
	var nc := ncfg()
	var skill := str(gs.building_def(npc).get("skill", ""))
	var today: int = gs.today()
	var cool: Dictionary = gs.labor["cooldown"]
	if target == null:
		var best_y := float(nc.get("poach_min_years", 1.5))
		for c in gs.citizens.values():
			if c.job_kind != "empleo" or c.job_id < 0 or int(cool.get("c%d" % c.id, -1)) > today:
				continue
			var y := years(c, skill)
			if y < best_y:
				continue
			var from: Dictionary = gs.get_building(c.job_id)
			if from.is_empty() or not gs.owned_by_player(from) or str(gs.building_def(from).get("skill", "")) != skill:
				continue
			if pending_offers(gs).any(func(o): return int(o["cid"]) == c.id):
				continue
			best_y = y
			target = c
	if target == null:
		return {}
	var from_b: Dictionary = gs.get_building(target.job_id)
	if from_b.is_empty():
		return {}
	var wage := snappedf(maxf(target.wage * (1.0 + rr(gs, "poach_raise%d" % target.id, nc.get("poach_raise", [0.12, 0.22]))),
			BusinessSim.asked_wage(gs, target, str(npc["type"])) * 1.05), 0.05)
	if float(npc.get("reserve", 0.0)) < wage * float(nc.get("poach_reserve_days", 45)):
		return {}
	var o := {"id": _next_id(gs), "cid": target.id, "name": target.full_name(), "npc": int(npc["id"]), "npc_label": gs.building_label(npc),
		"from": int(from_b["id"]), "from_label": gs.building_label(from_b), "wage": wage, "old_wage": target.wage,
		"years": snappedf(years(target, skill), 0.1), "day": today, "deadline": today + int(nc.get("poach_reply_days", 7)), "status": "pendiente"}
	gs.labor["offers"].append(o)
	while gs.labor["offers"].size() > 30:
		gs.labor["offers"].pop_front()
	gs.labor["cooldown"]["p%d" % int(npc["id"])] = today + int(nc.get("poach_cooldown_days", 180))
	gs.labor["cooldown"]["c%d" % target.id] = today + int(nc.get("poach_cooldown_days", 180))
	gs.notify("%s (%.1f años de oficio) recibió una oferta de %s: %s/día (hoy gana %s en tu %s). Iguálala en la pestaña Empleados o se irá." % [
		target.full_name(), float(o["years"]), o["npc_label"], Fmt.money2(wage), Fmt.money2(target.wage), o["from_label"]], "importante")
	return o


static func _offer(gs, id: int) -> Dictionary:
	for o in gs.labor.get("offers", []):
		if int(o["id"]) == id:
			return o
	return {}


## Igualar la oferta: el empleado se queda con el nuevo sueldo.
static func match_offer(gs, id: int) -> String:
	var o := _offer(gs, id)
	if o.is_empty() or str(o["status"]) != "pendiente":
		return "La oferta ya no está vigente."
	var c: Citizen = gs.citizens.get(int(o["cid"]))
	if c == null or c.job_id != int(o["from"]):
		o["status"] = "vencida"
		return "Ya no trabaja contigo."
	c.wage = float(o["wage"])
	c.happiness = clampf(c.happiness + 3.0, 0.0, 100.0)
	o["status"] = "igualada"
	gs.notify("Igualaste la oferta: %s se queda en %s por %s/día." % [c.full_name(), o["from_label"], Fmt.money2(c.wage)], "negocio")
	return ""


## No igualar: el empleado se va a la empresa NPC con su experiencia.
static func decline_offer(gs, id: int) -> String:
	var o := _offer(gs, id)
	if o.is_empty() or str(o["status"]) != "pendiente":
		return "La oferta ya no está vigente."
	_leave_to_npc(gs, o)
	return ""


static func _leave_to_npc(gs, o: Dictionary) -> void:
	var c: Citizen = gs.citizens.get(int(o["cid"]))
	var npc: Dictionary = gs.get_building(int(o["npc"]))
	o["status"] = "se_fue"
	if c == null or c.job_id != int(o["from"]) or npc.is_empty() or not NpcBusinessSim.is_npc(npc) or str(npc["status"]) != "activo":
		o["status"] = "vencida"
		return
	c.job_id = -1
	c.job_kind = ""
	c.wage = 0.0
	NpcBusinessSim.staff_index(gs)
	NpcBusinessSim.hire_silent(gs, npc, c)
	c.wage = float(o["wage"])
	gs.notify("%s dejó tu %s y se fue a %s por %s/día: su experiencia (%.1f años) se va con él/ella." % [
		c.full_name(), o["from_label"], o["npc_label"], Fmt.money2(c.wage), float(o["years"])], "negocio")
	EventBus.citizens_moved.emit()


static func _offers_daily(gs) -> void:
	var nc := ncfg()
	for o in gs.labor.get("offers", []):
		if str(o.get("status", "")) != "pendiente" or gs.today() < int(o.get("deadline", 0)):
			continue
		if rf(gs, "leave%d" % int(o["id"])) < float(nc.get("poach_leave_chance", 0.7)):
			_leave_to_npc(gs, o)
		else:
			o["status"] = "rechazada"
			gs.notify("%s decidió quedarse en tu %s pese a la oferta de %s." % [o["name"], o["from_label"], o["npc_label"]], "negocio")


# --- Interfaz ------------------------------------------------------------------------------------------------

## Línea de estado laboral de un negocio para el panel (vacío si no hay nada).
static func status_text(gs, b: Dictionary) -> String:
	var u := union_of(gs, b)
	var parts := []
	if str(u.get("state", "")) == U_DEMAND:
		parts.append("Sindicato: piden +%d %% de sueldo (%s). Plazo: %d días." % [int(round(float(u["pct"]) * 100.0)), u.get("reason", ""), maxi(0, int(u["deadline"]) - gs.today())])
	elif str(u.get("state", "")) == U_STRIKE:
		parts.append("HUELGA: producción al %d %% por %d días más." % [int(round(float(u["factor"]) * 100.0)), maxi(0, int(u["until"]) - gs.today())])
	for o in pending_offers(gs, b):
		parts.append("%s tiene una oferta de %s: %s/día (gana %s)." % [o["name"], o["npc_label"], Fmt.money2(float(o["wage"])), Fmt.money2(float(o["old_wage"]))])
	return "\n".join(parts)
