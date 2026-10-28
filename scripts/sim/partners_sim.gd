class_name PartnersSim
extends RefCounted
## Socios de tus empresas (docs/SOCIAL.md). Un ciudadano entra como socio aportando capital (dinero
## que pasa de su bolsillo al tuyo) o habilidades (mejora la producción) y recibe un % de las
## utilidades de cada mes. Puedes comprarle su parte, venderle más o resolver un desacuerdo.
## Tú conservas siempre el control: los socios suman como máximo `max_total_share` (49 %).
##
## Estado en GameState.player["socios"] = {list: [{id, bid, cid, share, kind, capital, skill, since,
##   sat, paid, last_pay, last_month, dispute{reason, since, months}}], next, log[]}.
## Todos los pagos van entre tu dinero (gs.money) y el del ciudadano (c.money): bolsillos de
## FlowSim.pockets, así que la conservación del dinero no cambia (tests/test_conservacion).

const KIND_LABELS := {"capital": "Capital", "habilidad": "Habilidades"}
const REASONS := {"perdidas": "las pérdidas del negocio", "reparto": "el reparto de utilidades", "precio": "tu política de precios",
	"sueldos": "lo que pagas a los empleados"}


static func cfg() -> Dictionary:
	return SocialSim.cfg().get("partners", {})


static func state(gs) -> Dictionary:
	var s: Dictionary = gs.player.get("socios", {}) if gs.player.get("socios", {}) is Dictionary else {}
	if not (s.get("list") is Array):
		s["list"] = []
	if not (s.get("log") is Array):
		s["log"] = []
	s["next"] = int(s.get("next", 1))
	for p in s["list"]:
		for k in ["id", "bid", "cid", "since", "last_month"]:
			p[k] = int(p.get(k, -1))
		for k in ["share", "capital", "skill", "sat", "paid", "last_pay"]:
			p[k] = float(p.get(k, 60.0 if k == "sat" else 0.0))
		if not (p.get("dispute") is Dictionary):
			p["dispute"] = {}
	gs.player["socios"] = s
	return s


static func _log(gs, text: String) -> void:
	var lg: Array = state(gs)["log"]
	lg.append("%s: %s" % [TimeManager.date_from_day(gs.today(), TimeManager.start_year()), text])
	while lg.size() > 30:
		lg.pop_front()


static func min_share() -> float:
	return float(cfg().get("min_share", 0.03))


# --- Consultas ------------------------------------------------------------------------------------

static func business_ok(gs, b: Dictionary) -> bool:
	return not b.is_empty() and gs.owned_by_player(b) and BusinessSim.is_business(b) and not BusinessSim.is_nonprofit(b) \
		and str(b.get("status", "")) != "construccion"


static func partners_of(gs, b: Dictionary) -> Array:
	if b.is_empty() or not gs.player.has("socios"):
		return []
	var bid := int(b["id"])
	return state(gs)["list"].filter(func(p): return int(p["bid"]) == bid)


static func get_partner(gs, pid: int) -> Dictionary:
	for p in state(gs)["list"]:
		if int(p["id"]) == pid:
			return p
	return {}


static func of_citizen(gs, cid: int) -> Array:
	if not gs.player.has("socios"):
		return []
	return state(gs)["list"].filter(func(p): return int(p["cid"]) == cid)


static func total_share(gs, b: Dictionary) -> float:
	var t := 0.0
	for p in partners_of(gs, b):
		t += float(p["share"])
	return t


## Lo que aún se puede repartir a socios en este negocio.
static func room(gs, b: Dictionary) -> float:
	return maxf(0.0, float(cfg().get("max_total_share", 0.49)) - total_share(gs, b))


static func eligible_businesses(gs) -> Array:
	var out := []
	for b in gs.buildings:
		if business_ok(gs, b) and room(gs, b) >= min_share() and partners_of(gs, b).size() < int(cfg().get("max_per_business", 3)):
			out.append(b)
	return out


## Valor del negocio: lo invertido (EconomySim.property_value) + utilidad del mes × meses.
static func valuation(gs, b: Dictionary) -> float:
	var v := maxf(0.0, EconomySim.property_value(gs, b))
	v += maxf(0.0, BusinessSim.period_profit(b, "last_month")) * float(cfg().get("valuation_profit_months", 18))
	return maxf(v, 50.0 * gs.price_mult())


## Parte justa por un aporte de capital.
static func fair_share(gs, b: Dictionary, capital: float) -> float:
	if capital <= 0.0:
		return 0.0
	return capital / (valuation(gs, b) + capital)


## Habilidad útil para el negocio: su oficio en el sector o su talento para los negocios.
static func skill_of(gs, c: Citizen, b: Dictionary) -> float:
	var skill := str(gs.building_def(b).get("skill", ""))
	return maxf(float(c.skills.get(skill, 0.0)), HeirsSim.talent(gs, c, "negocios"))


static func skill_bonus(gs, c: Citizen, b: Dictionary) -> float:
	return minf(float(cfg().get("skill_bonus_max", 0.12)), skill_of(gs, c, b) * float(cfg().get("skill_bonus_per_point", 0.0015)))


## Parte justa por habilidades: lo que la mejora de producción aporta (entre 3 % y 15 %).
static func fair_skill_share(gs, c: Citizen, b: Dictionary) -> float:
	return snappedf(clampf(skill_bonus(gs, c, b) * 1.2, min_share(), 0.15), 0.01)


## Multiplicador de producción: socios con habilidades suben; un desacuerdo abierto baja.
static func output_mult(gs, b: Dictionary) -> float:
	if not gs.player.has("socios"):
		return 1.0
	var m := 1.0
	for p in partners_of(gs, b):
		var c: Citizen = gs.citizens.get(int(p["cid"]))
		if c == null:
			continue
		if str(p.get("kind", "")) == "habilidad":
			m += skill_bonus(gs, c, b)
		if not (p["dispute"] as Dictionary).is_empty():
			m -= float(cfg().get("dispute_penalty", 0.08))
	return clampf(m, 0.5, 1.5)


static func can_be_partner(gs, b: Dictionary, c: Citizen, kind: String) -> String:
	if not business_ok(gs, b):
		return "Solo en tus empresas con fines de lucro (no en obra)"
	if c == null or gs.is_player(c.id):
		return "No puedes ser tu propio socio"
	if c.age_years(gs.today()) < 18:
		return "Es menor de edad"
	if c.prison_until >= 0:
		return "Está en la cárcel"
	for p in partners_of(gs, b):
		if int(p["cid"]) == c.id:
			return "Ya es socio(a) de este negocio"
	if partners_of(gs, b).size() >= int(cfg().get("max_per_business", 3)):
		return "Este negocio ya tiene el máximo de socios"
	if room(gs, b) < min_share():
		return "No queda participación para repartir (tú conservas el control)"
	if kind == "habilidad" and skill_of(gs, c, b) < float(cfg().get("skill_min", 35)):
		return "No tiene habilidades útiles para este negocio (%d/%d)" % [int(skill_of(gs, c, b)), int(cfg().get("skill_min", 35))]
	return ""


static func accept_chance(gs, b: Dictionary, c: Citizen, kind: String, capital: float, share: float) -> float:
	var fair := fair_share(gs, b, capital) if kind == "capital" else fair_skill_share(gs, c, b)
	var p := 0.35 + PlayerSim.affinity(gs, c.id) * 0.005
	p += clampf((share - fair) / maxf(0.01, fair), -1.0, 1.0) * 0.3   # Le ofreces más (o menos) de lo justo.
	if BusinessSim.period_profit(b, "last_month") > 0.0:
		p += 0.15
	elif int(b.get("loss_months", 0)) >= 2:
		p -= 0.2
	p += (float(SocialSim.traits(c)["ambicioso"]) - 0.5) * 0.3
	p += (float(SocialSim.emotions(gs, c)["confianza"]) - 50.0) * 0.003
	return clampf(p, 0.03, 0.95)


## Propone una sociedad. kind = "capital" (aporta `capital`) o "habilidad". share = su % de utilidades.
## roll = 0 fuerza el sí (oferta que él/ella mismo(a) hizo). Devuelve {ok, msg, chance}.
static func propose(gs, b: Dictionary, c: Citizen, kind: String, capital: float, share: float, roll := -1.0) -> Dictionary:
	var r := can_be_partner(gs, b, c, kind)
	if r != "":
		return {"ok": false, "msg": r}
	share = snappedf(share, 0.001)
	if share < min_share() - 0.0001 or share > room(gs, b) + 0.0001:
		return {"ok": false, "msg": "La participación debe ir de %d %% a %d %%" % [int(round(min_share() * 100.0)), int(room(gs, b) * 100.0)]}
	if kind == "capital":
		if capital <= 0.0:
			return {"ok": false, "msg": "Indica cuánto capital aporta"}
		if c.money < capital:
			return {"ok": false, "msg": "%s no tiene %s (tiene %s)" % [c.first_name, Fmt.money(capital), Fmt.money(c.money)]}
	else:
		capital = 0.0
	var chance := accept_chance(gs, b, c, kind, capital, share)
	if roll < 0.0:
		roll = gs.rng.randf()
	if roll >= chance:
		PlayerSim._add_affinity(gs, c.id, -1.0)
		SocialSim.remember(gs, c, "sociedad", 0, "Rechazó ser socio(a) de %s" % gs.building_label(b))
		return {"ok": false, "msg": "%s no aceptó: le parece que %d %% no compensa (probabilidad %d %%)." % [c.first_name, int(round(share * 100.0)), int(chance * 100.0)], "chance": chance}
	if capital > 0.0:
		c.money -= capital
		gs.add_money(capital)   # Aporte de capital: de su bolsillo al tuyo.
	var st := state(gs)
	var p := {"id": int(st["next"]), "bid": int(b["id"]), "cid": c.id, "share": share, "kind": kind, "capital": capital,
		"skill": skill_of(gs, c, b), "since": gs.today(), "sat": 65.0, "paid": 0.0, "last_pay": 0.0, "last_month": -1, "dispute": {}}
	st["next"] = int(st["next"]) + 1
	st["list"].append(p)
	PlayerSim._add_affinity(gs, c.id, 5.0)
	SocialSim.remember(gs, c, "sociedad", 1, "Se hizo socio(a) de %s" % gs.building_label(b))
	var txt := "%s es ahora socio(a) de %s con el %d %% de las utilidades%s." % [c.full_name(), gs.building_label(b), int(round(share * 100.0)),
		" (aportó %s)" % Fmt.money(capital) if capital > 0.0 else " (aporta su experiencia: +%d %% de producción)" % int(skill_bonus(gs, c, b) * 100.0)]
	_log(gs, txt)
	gs.notify(txt, "negocio")
	return {"ok": true, "msg": txt, "chance": chance}


# --- Comprar y vender participación ---------------------------------------------------------------

## Lo que pide por su parte: participación × valor del negocio (+ prima si está descontento).
static func buyout_price(gs, p: Dictionary) -> float:
	var b: Dictionary = gs.get_building(int(p["bid"]))
	if b.is_empty():
		return 0.0
	var prem := float(cfg().get("buyout_premium_unhappy" if float(p["sat"]) < 40.0 else "buyout_premium", 0.05))
	return snappedf(float(p["share"]) * valuation(gs, b) * (1.0 + prem), 0.01)


## Comprarle su parte. offer_mult < 1: ofreces menos de lo que pide (puede rechazar).
static func buy_out(gs, pid: int, offer_mult := 1.0, roll := -1.0) -> String:
	var p := get_partner(gs, pid)
	if p.is_empty():
		return "Ese socio ya no existe"
	var c: Citizen = gs.citizens.get(int(p["cid"]))
	var price := buyout_price(gs, p) * offer_mult
	if gs.money < price:
		return "Necesitas %s para comprarle su parte" % Fmt.money(price)
	if offer_mult < 1.0:
		var chance := clampf(0.15 + (offer_mult - 0.7) * 1.5 + PlayerSim.affinity(gs, c.id) * 0.004 if c != null else 0.0, 0.0, 0.9)
		if roll < 0.0:
			roll = gs.rng.randf()
		if roll >= chance:
			p["sat"] = maxf(0.0, float(p["sat"]) - 5.0)
			return "%s rechazó %s por su parte (pide %s)." % [c.first_name if c != null else "El socio", Fmt.money(price), Fmt.money(buyout_price(gs, p))]
	gs.add_money(-price)
	if c != null:
		c.money += price
		SocialSim.remember(gs, c, "sociedad", 0, "Te vendió su parte de %s" % gs.building_label(gs.get_building(int(p["bid"]))))
	_remove(gs, p)
	var txt := "Compraste la parte de %s en %s por %s." % [c.full_name() if c != null else "tu socio", gs.building_label(gs.get_building(int(p["bid"]))), Fmt.money(price)]
	_log(gs, txt)
	return txt


static func sell_price(gs, p: Dictionary, extra: float) -> float:
	return snappedf(extra * valuation(gs, gs.get_building(int(p["bid"]))), 0.01)


## Venderle más participación a un socio: paga participación × valor del negocio.
static func sell_more(gs, pid: int, extra: float, roll := -1.0) -> String:
	var p := get_partner(gs, pid)
	if p.is_empty():
		return "Ese socio ya no existe"
	var b: Dictionary = gs.get_building(int(p["bid"]))
	var c: Citizen = gs.citizens.get(int(p["cid"]))
	if c == null or b.is_empty():
		return "—"
	if extra > room(gs, b) + 0.0001:
		return "Solo puedes vender hasta el %d %% más (tú conservas el control)" % int(room(gs, b) * 100.0)
	var price := sell_price(gs, p, extra)
	if c.money < price:
		return "%s no tiene %s para comprar el %d %% más" % [c.first_name, Fmt.money(price), int(round(extra * 100.0))]
	var chance := clampf(0.3 + float(p["sat"]) * 0.006 + (0.2 if BusinessSim.period_profit(b, "last_month") > 0.0 else -0.1), 0.05, 0.95)
	if roll < 0.0:
		roll = gs.rng.randf()
	if roll >= chance:
		return "%s no quiere aumentar su parte ahora." % c.first_name
	c.money -= price
	gs.add_money(price)
	p["share"] = float(p["share"]) + extra
	p["capital"] = float(p["capital"]) + price
	var txt := "%s compró el %d %% más de %s por %s (ahora tiene el %d %%)." % [c.first_name, int(round(extra * 100.0)), gs.building_label(b), Fmt.money(price), int(round(float(p["share"]) * 100.0))]
	_log(gs, txt)
	return txt


static func _remove(gs, p: Dictionary) -> void:
	var lst: Array = state(gs)["list"]
	lst.erase(p)


# --- Desacuerdos -----------------------------------------------------------------------------------

static func dispute_text(gs, p: Dictionary) -> String:
	var d: Dictionary = p.get("dispute", {})
	if d.is_empty():
		return ""
	return "En desacuerdo por %s (hace %d mes(es))" % [str(REASONS.get(str(d.get("reason", "")), "la gestión")), int(d.get("months", 0))]


static func compensation(gs, p: Dictionary) -> float:
	var base := maxf(float(p.get("last_pay", 0.0)), 0.01 * valuation(gs, gs.get_building(int(p["bid"]))))
	return snappedf(maxf(5.0 * gs.price_mult(), base * float(cfg().get("compensation_months", 2))), 0.01)


static func negotiate_chance(gs, p: Dictionary) -> float:
	var c: Citizen = gs.citizens.get(int(p["cid"]))
	var head: Citizen = gs.player_citizen()
	var t := HeirsSim.talent(gs, head, "negocios") if head != null else 20.0
	return clampf(0.3 + (PlayerSim.affinity(gs, c.id) if c != null else 0.0) * 0.004 + t * 0.004 + float(p["sat"]) * 0.002, 0.05, 0.9)


## Resolver un desacuerdo: "negociar" (conversar: puede salir mal), "compensar" (le pagas),
## "ceder" (le das un poco más de participación, sin dinero), "comprar" (compras su parte) o
## "ignorar" (empeora; a los `dispute_force_months` meses exige que le compres).
static func resolve(gs, pid: int, how: String, roll := -1.0) -> String:
	var p := get_partner(gs, pid)
	if p.is_empty() or (p["dispute"] as Dictionary).is_empty():
		return "No hay desacuerdo que resolver"
	var c: Citizen = gs.citizens.get(int(p["cid"]))
	var who: String = c.first_name if c != null else "Tu socio"
	if roll < 0.0:
		roll = gs.rng.randf()
	match how:
		"negociar":
			if roll < negotiate_chance(gs, p):
				p["sat"] = minf(100.0, float(p["sat"]) + 25.0)
				p["dispute"] = {}
				if c != null:
					SocialSim.remember(gs, c, "sociedad", 1, "Resolvieron un desacuerdo conversando")
				return "Conversaste con %s y llegaron a un acuerdo." % who
			p["sat"] = maxf(0.0, float(p["sat"]) - 5.0)
			if c != null:
				PlayerSim._add_affinity(gs, c.id, -3.0)
				SocialSim.remember(gs, c, "sociedad", -1, "Discutieron sobre el negocio")
			return "La conversación con %s no salió bien; sigue molesto(a)." % who
		"compensar":
			var amt := compensation(gs, p)
			if gs.money < amt:
				return "Necesitas %s para compensarle" % Fmt.money(amt)
			gs.add_money(-amt)
			if c != null:
				c.money += amt
			p["paid"] = float(p["paid"]) + amt
			p["sat"] = minf(100.0, float(p["sat"]) + 30.0)
			p["dispute"] = {}
			return "Le pagaste %s a %s como compensación; quedó conforme." % [Fmt.money(amt), who]
		"ceder":
			var b: Dictionary = gs.get_building(int(p["bid"]))
			var extra := minf(float(cfg().get("cede_share", 0.03)), room(gs, b))
			if extra <= 0.0:
				return "No queda participación para ceder"
			p["share"] = float(p["share"]) + extra
			p["sat"] = minf(100.0, float(p["sat"]) + 35.0)
			p["dispute"] = {}
			return "Le cediste el %d %% más a %s (ahora %d %%); quedó conforme." % [int(round(extra * 100.0)), who, int(round(float(p["share"]) * 100.0))]
		"comprar":
			var r := buy_out(gs, pid, 1.0)
			return r
		"ignorar":
			p["sat"] = maxf(0.0, float(p["sat"]) - 8.0)
			if c != null:
				PlayerSim._add_affinity(gs, c.id, -6.0)
				SocialSim.remember(gs, c, "sociedad", -1, "Ignoraste su reclamo")
			return "Ignoraste el reclamo de %s. Si sigue así, te exigirá que le compres su parte." % who
	return "—"


# --- Ciclos ----------------------------------------------------------------------------------------

## Mes cerrado (después de BusinessSim.monthly): reparte utilidades, ajusta la satisfacción y abre
## o fuerza desacuerdos. Un aviso por evento importante; nada cada mes.
static func monthly(gs) -> void:
	if not gs.player.has("socios"):
		return
	var st := state(gs)
	var month_id: int = TimeManager.year() * 12 + TimeManager.month()
	for p in st["list"].duplicate():
		var b: Dictionary = gs.get_building(int(p["bid"]))
		var c: Citizen = gs.citizens.get(int(p["cid"]))
		if c == null or gs.is_player(c.id):
			_remove(gs, p)   # Ya no está, o es ahora el jefe de familia (su parte vuelve a la familia).
			continue
		if not business_ok(gs, b):
			# El negocio ya no es tuyo (vendido, demolido o en quiebra): la sociedad se disuelve.
			_remove(gs, p)
			PlayerSim._add_affinity(gs, c.id, -5.0)
			var t := "La sociedad con %s terminó: %s ya no opera como tu empresa." % [c.full_name(), "el negocio" if b.is_empty() else gs.building_label(b)]
			_log(gs, t)
			gs.notify(t, "negocio")
			continue
		if int(p["last_month"]) == month_id:
			continue
		p["last_month"] = month_id
		var profit := BusinessSim.period_profit(b, "last_month")
		var pay := 0.0
		if profit > 0.0:
			pay = snappedf(profit * float(p["share"]), 0.01)
			gs.add_money(-pay)
			c.money += pay   # Utilidades del socio: de tu bolsillo al suyo.
			p["paid"] = float(p["paid"]) + pay
			gs.add_counter("partner_payouts", pay)
		p["last_pay"] = pay
		var val := valuation(gs, b)
		var delta := clampf(profit / maxf(1.0, val) * 100.0, -8.0, 6.0)
		if int(b.get("loss_months", 0)) >= 3:
			delta -= 6.0
		var sat := float(p["sat"]) + delta + (60.0 - float(p["sat"])) * 0.05
		p["sat"] = clampf(sat, 0.0, 100.0)
		var d: Dictionary = p["dispute"]
		if d.is_empty():
			if float(p["sat"]) < float(cfg().get("dispute_threshold", 30)) and gs.rng.randf() < float(cfg().get("dispute_chance", 0.35)):
				var reason := "perdidas" if profit < 0.0 else "reparto"
				if profit >= 0.0 and float(b.get("price", 0.0)) > 0.0 and float(b.get("price", 0.0)) < BusinessSim.default_price(gs, gs.building_def(b)) * 0.7:
					reason = "precio"
				p["dispute"] = {"reason": reason, "since": gs.today(), "months": 0}
				var t2 := "Tu socio(a) %s está en desacuerdo con %s en %s. Resuélvelo en la pestaña Socios del negocio." % [c.full_name(), str(REASONS[reason]), gs.building_label(b)]
				_log(gs, t2)
				gs.notify(t2, "negocio")
		else:
			d["months"] = int(d.get("months", 0)) + 1
			if int(d["months"]) >= int(cfg().get("dispute_force_months", 4)):
				var price := buyout_price(gs, p)
				if gs.money >= price:
					var t3 := "%s se cansó del desacuerdo y te exigió comprarle su parte: %s" % [c.full_name(), buy_out(gs, int(p["id"]))]
					gs.notify(t3, "negocio")
				elif int(d["months"]) == int(cfg().get("dispute_force_months", 4)):
					gs.notify("%s quiere que le compres su parte de %s (%s), pero no tienes el dinero. El desacuerdo sigue afectando la producción." % [c.full_name(), gs.building_label(b), Fmt.money(price)], "negocio")


## Un socio muere o se va: su parte pasa a su heredero (si queda en el pueblo) o vuelve a ti.
static func on_citizen_removed(gs, c: Citizen, reason: String) -> void:
	if not gs.player.has("socios"):
		return
	for p in of_citizen(gs, c.id):
		var b: Dictionary = gs.get_building(int(p["bid"]))
		var heir: Citizen = null
		if reason == "murió":
			for h in PopulationSim.heirs_of(gs, c):
				if not gs.is_player(h.id) and h.age_years(gs.today()) >= 18:
					heir = h
					break
		var lbl: String = gs.building_label(b) if not b.is_empty() else "tu negocio"
		if heir != null:
			p["cid"] = heir.id
			p["dispute"] = {}
			p["sat"] = 55.0
			_log(gs, "%s heredó la parte de %s en %s." % [heir.full_name(), c.full_name(), lbl])
			gs.notify("%s heredó el %d %% de %s que tenía %s." % [heir.full_name(), int(round(float(p["share"]) * 100.0)), lbl, c.full_name()], "negocio")
		else:
			_remove(gs, p)
			_log(gs, "La parte de %s en %s volvió a ti (%s)." % [c.full_name(), lbl, reason])
			gs.notify("La parte de %s en %s volvió a ti (%s sin herederos en el pueblo)." % [c.full_name(), lbl, reason], "negocio")
