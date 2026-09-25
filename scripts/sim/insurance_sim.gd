class_name InsuranceSim
extends RefCounted
## Economía global — seguros (ver docs/ECONOMIA_GLOBAL.md).
##
## Pólizas del jugador con la aseguradora externa (La Previsora): incendio y robo por edificio, cosecha
## por campo y pérdida de carga (global, comercio exterior). Prima mensual = pérdida esperada × recargo
## (riesgo real: techo de paja, bomberos, crimen del pueblo, valor del comercio). Deducible por tipo.
## Pagan cuando ocurre el evento: EventsSim._fires → on_fire, EventsSim._crime → on_theft, envíos de
## TradeSim que se pierden en el camino (daily) y malas cosechas por sequía o mal clima (monthly).
## La aseguradora externa tiene su propia caja (dinero fuera del pueblo, contado en outside_money):
## las primas entran a ella y los siniestros salen de ella. Nada aparece de la nada.
##
## Tu propia aseguradora (negocio "aseguradora"): cobra primas a empresas NPC, a dueños de casas y a
## negocios de los pueblos conectados, y paga sus siniestros (incendios reales del pueblo, robos y
## siniestros estadísticos en los pueblos). Tú fijas la tarifa: más cara = menos clientes.
## Estado: gs.world_econ["insurance"].

const TYPES := ["incendio", "robo", "cosecha", "carga"]


static func cfg() -> Dictionary:
	return GlobalEconSim.cfg().get("insurance", {})


static func type_def(t: String) -> Dictionary:
	return cfg().get("types", {}).get(t, {})


static func type_label(t: String) -> String:
	return str(type_def(t).get("label", t))


static func init_state(gs) -> void:
	var w: Dictionary = gs.world_econ
	if not w.has("insurance") or not (w["insurance"] is Dictionary):
		w["insurance"] = {}
	var s: Dictionary = w["insurance"]
	for k in ["policies", "own", "month", "last_month"]:
		if not s.has(k) or not (s[k] is Dictionary):
			s[k] = {}
	if not s.has("cargo"):
		s["cargo"] = false
	if not s.has("ext_cash"):
		s["ext_cash"] = float(cfg().get("external", {}).get("capital", 20000)) * gs.price_mult()
	if not s.has("log"):
		s["log"] = []


static func st(gs) -> Dictionary:
	return gs.world_econ.get("insurance", {}) if gs.world_econ is Dictionary else {}


static func external_cash(gs) -> float:
	return float(st(gs).get("ext_cash", 0.0))


static func external_label() -> String:
	return str(cfg().get("external", {}).get("label", "La aseguradora"))


static func _log(gs, text: String) -> void:
	var l: Array = st(gs).get("log", [])
	l.append({"date": TimeManager.date_string(false), "text": text})
	while l.size() > 40:
		l.pop_front()
	st(gs)["log"] = l


static func _stat(gs, key: String, amount: float) -> void:
	var m: Dictionary = st(gs).get("month", {})
	m[key] = float(m.get(key, 0.0)) + amount
	st(gs)["month"] = m


# --- Pólizas del jugador --------------------------------------------------------------------------------

static func policies_of(gs, b: Dictionary) -> Array:
	return st(gs).get("policies", {}).get(str(int(b.get("id", -1))), [])


static func has_policy(gs, b: Dictionary, t: String) -> bool:
	return policies_of(gs, b).has(t)


static func eligible(gs, b: Dictionary, t: String) -> bool:
	if not gs.owned_by_player(b) or str(b.get("status", "")) == "construccion":
		return false
	var def: Dictionary = gs.building_def(b)
	match t:
		"incendio":
			return true
		"robo":
			return str(def.get("category", "")) == "negocio"
		"cosecha":
			return bool(def.get("seasonal", false))
	return false


static func building_value(gs, b: Dictionary) -> float:
	return float(gs.level_def(b).get("cost", 300)) * gs.price_mult()


static func inventory_value(gs, b: Dictionary) -> float:
	var v := 0.0
	for g in b.get("inventory", {}):
		v += maxf(0.0, float(b["inventory"][g])) * EconomySim.market_price(gs, str(g))
	return v


## Prima mensual de una póliza del jugador (pérdida esperada × recargo, con el riesgo real de hoy).
static func premium(gs, b: Dictionary, t: String) -> float:
	var td := type_def(t)
	var loading := float(cfg().get("loading", 1.45))
	var p := 0.0
	match t:
		"incendio":
			var risk := float(td.get("rate", 0.0011)) * (1.5 if int(b.get("level", 1)) == 1 else 1.0)
			risk *= 1.0 - 0.6 * EventsSim.coverage(gs, "bomberos")
			p = (building_value(gs, b) + inventory_value(gs, b) * 0.5) * risk
		"robo":
			p = float(td.get("base", 1.2)) * gs.price_level() * (0.4 + float(gs.problems.get("crime", 0.0)) / 40.0)
		"cosecha":
			var def: Dictionary = gs.building_def(b)
			var monthly := BusinessSim.expected_output(gs, b) * 30.0 * EconomySim.market_price(gs, str(def.get("product", "")))
			p = maxf(monthly, float(gs.level_def(b).get("jobs", 1)) * gs.price_mult() * 10.0) * float(td.get("rate", 0.035))
	return maxf(float(cfg().get("min_premium", 0.5)) * gs.price_level(), p * loading)


## Prima mensual del seguro de carga (según el comercio exterior del mes anterior).
static func cargo_premium(gs) -> float:
	var td := type_def("carga")
	var lm: Dictionary = gs.trade.get("last_month", {}) if gs.trade is Dictionary else {}
	var value := float(lm.get("exports", 0.0)) + float(lm.get("imports", 0.0))
	return maxf(float(td.get("min", 1.0)) * gs.price_level(), value * float(td.get("rate", 0.02)) * float(cfg().get("loading", 1.45)))


static func set_policy(gs, b: Dictionary, t: String, on: bool) -> String:
	if on and not eligible(gs, b, t):
		return "Esa póliza no aplica a %s." % gs.building_label(b)
	var pol: Dictionary = st(gs)["policies"]
	var key := str(int(b["id"]))
	var arr: Array = pol.get(key, [])
	if on and not arr.has(t):
		arr.append(t)
	elif not on:
		arr.erase(t)
	if arr.is_empty():
		pol.erase(key)
	else:
		pol[key] = arr
	return ""


static func set_cargo(gs, on: bool) -> void:
	st(gs)["cargo"] = on


static func total_premiums(gs) -> float:
	var total := 0.0
	for key in st(gs).get("policies", {}):
		var b: Dictionary = gs.get_building(int(key))
		if b.is_empty():
			continue
		for t in st(gs)["policies"][key]:
			total += premium(gs, b, str(t))
	if bool(st(gs).get("cargo", false)):
		total += cargo_premium(gs)
	return total


## Paga un siniestro desde la caja de la aseguradora externa. Devuelve lo pagado.
static func _external_pay(gs, amount: float) -> float:
	var cash := external_cash(gs)
	var paid := clampf(amount, 0.0, maxf(0.0, cash))
	st(gs)["ext_cash"] = cash - paid
	if paid < amount - 0.01:
		gs.notify("%s no tiene fondos para pagar todo el siniestro (pagó %s de %s)." % [external_label(), Fmt.money(paid), Fmt.money(amount)], "jugador")
	return paid


## Indemnización a un edificio del jugador: compensa el gasto registrado (la pérdida neta es el deducible).
static func _indemnify_player(gs, b: Dictionary, amount: float, ledger_key: String) -> void:
	if amount <= 0.0:
		return
	if BusinessSim.is_nonprofit(b):
		b["reserve"] = float(b.get("reserve", 0.0)) + amount
	else:
		gs.add_money(amount)
	if not b.is_empty() and b.has("ledger"):
		BusinessSim.ledger_add(b, ledger_key, -amount)
	gs.add_counter("insurance_claims", amount)
	_stat(gs, "claims", amount)


# --- Siniestros (ganchos) -----------------------------------------------------------------------------------

## EventsSim._fires: después del incendio de cualquier edificio. `ratio` = daño; si el edificio ya no existe,
## se destruyó (pérdida total).
static func on_fire(gs, b: Dictionary, ratio: float, contained: bool) -> void:
	if not GlobalEconSim.ready(gs):
		return
	var destroyed: bool = gs.get_building(int(b.get("id", -1))).is_empty()
	var value := building_value(gs, b)
	var keep := 0.9 if contained else 0.4
	var inv_lost := inventory_value(gs, b) * (1.0 / keep - 1.0) if not destroyed else 0.0
	var loss := value * (1.0 if destroyed else ratio) + inv_lost
	if loss <= 0.0:
		return
	var ded := float(type_def("incendio").get("deductible", 0.1))
	if gs.owned_by_player(b) and has_policy(gs, b, "incendio"):
		var paid := _external_pay(gs, loss * (1.0 - ded))
		_indemnify_player(gs, b, paid, "reparaciones")
		gs.notify("Seguro de incendio: %s te pagó %s por %s (deducible %d %%)." % [external_label(), Fmt.money(paid), gs.building_label(b), int(ded * 100.0)], "jugador")
		_log(gs, "Incendio en %s: cobraste %s." % [gs.building_label(b), Fmt.money(paid)])
		return
	var ins := insurer_of(gs, b)
	if not ins.is_empty():
		_own_claim(gs, ins, b, loss * (1.0 - ded), "incendio")


## EventsSim._crime: robo en un negocio del jugador.
static func on_theft(gs, b: Dictionary, loss: float) -> void:
	if not GlobalEconSim.ready(gs) or loss <= 0.0:
		return
	if gs.owned_by_player(b) and has_policy(gs, b, "robo"):
		var ded := float(type_def("robo").get("deductible", 0.15))
		var inv_lost := inventory_value(gs, b) * (1.0 / 0.85 - 1.0)
		var paid := _external_pay(gs, (loss + inv_lost) * (1.0 - ded))
		_indemnify_player(gs, b, paid, "robos")
		_log(gs, "Robo en %s: cobraste %s." % [gs.building_label(b), Fmt.money(paid)])


## Envíos de comercio exterior: cada envío corre el riesgo una vez (bandidos, naufragio, accidente).
static func daily(gs) -> void:
	if not (gs.trade is Dictionary) or gs.trade.get("shipments", []).is_empty():
		return
	var chance := float(cfg().get("cargo_loss_chance", 0.025))
	var list: Array = gs.trade["shipments"]
	for s in list.duplicate():
		if bool(s.get("ins_roll", false)):
			continue
		s["ins_roll"] = true
		if GlobalEconSim.rf(gs) >= chance:
			continue
		list.erase(s)
		var value := float(s.get("value", 0.0))
		var good := TradeSim.good_label(str(s.get("good", "")))
		var tname := str(TradeSim.town(gs, str(s.get("town_id", ""))).get("name", "otro pueblo"))
		var what := "Se perdió en el camino un envío de %d %s %s %s (%s)." % [int(s.get("qty", 0)), good.to_lower(), "hacia" if str(s.get("kind", "")) == TradeSim.KIND_SELL else "desde", tname, Fmt.money(value)]
		if bool(st(gs).get("cargo", false)):
			var ded := float(type_def("carga").get("deductible", 0.1))
			var paid := _external_pay(gs, value * (1.0 - ded))
			gs.add_money(paid)
			gs.add_counter("insurance_claims", paid)
			_stat(gs, "claims", paid)
			gs.notify(what + " El seguro de carga te pagó %s." % Fmt.money(paid), "jugador")
			_log(gs, "Carga perdida (%s): cobraste %s." % [good, Fmt.money(paid)])
		else:
			gs.notify(what + " No tenías seguro de carga.", "jugador")
			_log(gs, "Carga perdida sin seguro (%s, %s)." % [good, Fmt.money(value)])


# --- Cierre mensual --------------------------------------------------------------------------------------

static func monthly(gs) -> void:
	init_state(gs)
	var s := st(gs)
	s["last_month"] = s.get("month", {})
	s["month"] = {}
	_collect_player_premiums(gs)
	_crop_claims(gs)
	for b in gs.buildings:
		if is_insurer(gs, b) and gs.owned_by_player(b) and str(b.get("status", "")) == "activo":
			_run_own(gs, b)


static func _collect_player_premiums(gs) -> void:
	var s := st(gs)
	var pol: Dictionary = s["policies"]
	for key in pol.keys():
		var b: Dictionary = gs.get_building(int(key))
		if b.is_empty() or not gs.owned_by_player(b):
			pol.erase(key)
			continue
		for t in (pol[key] as Array).duplicate():
			if not eligible(gs, b, str(t)):
				continue
			var p := premium(gs, b, str(t))
			BusinessSim.pay(gs, b, p, "seguros")
			s["ext_cash"] = external_cash(gs) + p
			_stat(gs, "premiums", p)
	if bool(s.get("cargo", false)):
		var cp := cargo_premium(gs)
		gs.add_money(-cp)
		s["ext_cash"] = external_cash(gs) + cp
		_stat(gs, "premiums", cp)


## Seguro de cosecha: paga lo perdido por sequía o mal clima (no el invierno normal) en campos asegurados.
static func _crop_claims(gs) -> void:
	var trig := float(type_def("cosecha").get("trigger", 0.85))
	var ev := EventsSim.mult(gs, "farming") * float(WeatherSim.weather_data(gs).get("farming", 1.0))
	if ev >= trig:
		return
	var ded := float(type_def("cosecha").get("deductible", 0.2))
	for key in st(gs).get("policies", {}):
		var b: Dictionary = gs.get_building(int(key))
		if b.is_empty() or not has_policy(gs, b, "cosecha") or not eligible(gs, b, "cosecha"):
			continue
		var product := str(gs.building_def(b).get("product", ""))
		var out := BusinessSim.expected_output(gs, b)
		var lost := out * (1.0 / maxf(0.1, ev) - 1.0) * 30.0 * EconomySim.market_price(gs, product)
		if lost <= 0.0:
			continue
		var paid := _external_pay(gs, lost * (1.0 - ded))
		_indemnify_player(gs, b, paid, "insumos")
		gs.notify("Seguro de cosecha: %s te pagó %s por la mala cosecha de %s." % [external_label(), Fmt.money(paid), gs.building_label(b)], "jugador")
		_log(gs, "Mala cosecha en %s: cobraste %s." % [gs.building_label(b), Fmt.money(paid)])


# --- Tu aseguradora ------------------------------------------------------------------------------------------

static func own_cfg() -> Dictionary:
	return cfg().get("own", {})


static func is_insurer(gs, b: Dictionary) -> bool:
	return bool(gs.building_def(b).get("insurer", false))


static func own_state(gs, b: Dictionary) -> Dictionary:
	var own: Dictionary = st(gs).get("own", {})
	var key := str(int(b["id"]))
	if not own.has(key):
		own[key] = {"rate": 1.2, "clients": [], "towns": {}, "month": {}, "last": {}, "total": {}}
		st(gs)["own"] = own
	return own[key]


static func set_rate(gs, b: Dictionary, rate: float) -> void:
	own_state(gs, b)["rate"] = clampf(rate, float(own_cfg().get("min_rate", 0.5)), float(own_cfg().get("max_rate", 2.5)))


static func capacity(gs, b: Dictionary) -> int:
	var n := 0
	for c in gs.employees_of(int(b["id"])):
		if c.job_kind == "empleo":
			n += 1
	return n * int(gs.level_def(b).get("clients_per_worker", 20))


## Fracción de los posibles clientes que compran según tu tarifa (1 = prima justa × recargo normal).
static func demand_share(rate: float) -> float:
	var oc := own_cfg()
	return clampf(float(oc.get("demand_base", 1.4)) - float(oc.get("demand_slope", 0.6)) * rate, 0.05, 0.9)


## Posibles clientes locales: empresas NPC abiertas y casas de ciudadanos.
static func _local_candidates(gs) -> Array:
	var out := []
	for b in gs.buildings:
		if str(b.get("status", "")) != "activo":
			continue
		if NpcBusinessSim.is_npc(b) and str(b.get("npc_state", "")) == NpcBusinessSim.STATE_OPEN:
			out.append(b)
		elif str(b.get("owner", "")) == "ciudadano" and int(b.get("owner_id", -1)) >= 0 and str(gs.building_def(b).get("category", "")) == "vivienda":
			out.append(b)
	return out


## Tu aseguradora que cubre a este edificio ({} si ninguna).
static func insurer_of(gs, b: Dictionary) -> Dictionary:
	var id := int(b.get("id", -1))
	for key in st(gs).get("own", {}):
		var o: Dictionary = st(gs)["own"][key]
		if (o.get("clients", []) as Array).has(id):
			var ins: Dictionary = gs.get_building(int(key))
			if not ins.is_empty() and gs.owned_by_player(ins) and str(ins.get("status", "")) == "activo":
				return ins
	return {}


## Prima justa mensual de un cliente local (antes de tu tarifa).
static func fair_local(gs, b: Dictionary) -> float:
	var risk := float(type_def("incendio").get("rate", 0.0011)) * (1.5 if int(b.get("level", 1)) == 1 else 1.0) * float(cfg().get("loading", 1.45))
	var p := building_value(gs, b) * risk
	if NpcBusinessSim.is_npc(b):
		p += float(type_def("robo").get("base", 1.2)) * gs.price_level() * 0.5
	return maxf(0.2 * gs.price_level(), p)


static func fair_town(gs) -> float:
	var v: float = float(own_cfg().get("town_business_value", 900)) * gs.price_mult()
	return v * float(type_def("incendio").get("rate", 0.0011)) * 1.2 * float(cfg().get("loading", 1.45)) + float(type_def("robo").get("base", 1.2)) * gs.price_level() * 0.5


static func _own_stat(o: Dictionary, key: String, amount: float) -> void:
	var m: Dictionary = o.get("month", {})
	m[key] = float(m.get(key, 0.0)) + amount
	o["month"] = m
	var t: Dictionary = o.get("total", {})
	t[key] = float(t.get(key, 0.0)) + amount
	o["total"] = t


## Tu aseguradora paga un siniestro (sale de tu dinero, como gasto "siniestros" del negocio).
static func _own_claim(gs, ins: Dictionary, b: Dictionary, amount: float, what: String) -> void:
	if amount <= 0.0:
		return
	BusinessSim.pay(gs, ins, amount, "siniestros")
	var o := own_state(gs, ins)
	_own_stat(o, "claims", amount)
	if NpcBusinessSim.is_npc(b):
		b["reserve"] = float(b.get("reserve", 0.0)) + amount
	else:
		var owner: Citizen = gs.citizens.get(int(b.get("owner_id", -1)))
		if owner != null:
			owner.money += amount
		else:
			GovSim.add_treasury(gs, amount)
	gs.notify("Tu aseguradora %s pagó %s por %s en %s." % [gs.building_label(ins), Fmt.money(amount), what, gs.building_label(b)], "negocio")


static func _run_own(gs, ins: Dictionary) -> void:
	var o := own_state(gs, ins)
	o["last"] = o.get("month", {})
	o["month"] = {}
	var oc := own_cfg()
	var rate := float(o.get("rate", 1.2))
	var share := demand_share(rate)
	var cap := capacity(gs, ins)
	# Clientes locales: se mantienen los actuales que sigan siendo candidatos y se suman nuevos.
	var cands := _local_candidates(gs)
	var taken := {}
	for key in st(gs).get("own", {}):
		if key != str(int(ins["id"])):
			for id in st(gs)["own"][key].get("clients", []):
				taken[int(id)] = true
	var cand_ids := {}
	for b in cands:
		if not taken.has(int(b["id"])):
			cand_ids[int(b["id"])] = b
	var want := mini(cap, int(round(float(cand_ids.size()) * share)))
	var clients: Array = []
	for id in o.get("clients", []):
		if cand_ids.has(int(id)) and clients.size() < want:
			clients.append(int(id))
	var ids := cand_ids.keys()
	ids.sort()
	for id in ids:
		if clients.size() >= want:
			break
		if not clients.has(int(id)):
			clients.append(int(id))
	# Primas locales: cada cliente paga (si no puede, cancela la póliza).
	var income := 0.0
	var kept: Array = []
	for id in clients:
		var b: Dictionary = cand_ids[int(id)]
		var p := fair_local(gs, b) * rate
		var paid := 0.0
		if NpcBusinessSim.is_npc(b):
			paid = NpcBusinessSim._spend(gs, b, p, "seguros", false)
		else:
			var owner: Citizen = gs.citizens.get(int(b.get("owner_id", -1)))
			if owner != null and owner.money >= p:
				owner.money -= p
				paid = p
		if paid >= p - 0.01:
			kept.append(int(id))
			income += paid
		elif paid > 0.0:
			income += paid
	o["clients"] = kept
	# Negocios de los pueblos conectados (resumidos).
	var left := maxi(0, cap - kept.size())
	var towns := {}
	var fair_t := fair_town(gs) * rate
	for c in TradeSim.connected_towns(gs):
		if left <= 0:
			break
		var tid := str(c.get("town_id", c.get("id", "")))
		var t := TradeSim.town(gs, tid)
		if t.is_empty():
			continue
		var n := mini(left, int(round(float(TownEconomySim.total_businesses(t)) * share * float(oc.get("town_share", 0.5)))))
		n = mini(n, int(floorf(maxf(0.0, float(t.get("cash", 0.0))) * 0.05 / maxf(0.01, fair_t))))
		if n <= 0:
			continue
		var p := n * fair_t
		t["cash"] = float(t.get("cash", 0.0)) - p
		income += p
		towns[tid] = n
		left -= n
	o["towns"] = towns
	if income > 0.0:
		BusinessSim.earn(gs, ins, income, "ventas")
		_own_stat(o, "premiums", income)
	# Siniestros estadísticos: robos en empresas NPC clientes y siniestros en los pueblos.
	var crime := float(gs.problems.get("crime", 0.0))
	var ded := float(type_def("robo").get("deductible", 0.15))
	for id in kept:
		var b: Dictionary = gs.get_building(int(id))
		if b.is_empty() or not NpcBusinessSim.is_npc(b):
			continue
		if GlobalEconSim.rf(gs) < float(oc.get("npc_theft_chance", 0.08)) * (0.3 + crime / 40.0):
			var loss: float = (5.0 + GlobalEconSim.rf(gs) * 25.0) * gs.price_level()
			_own_claim(gs, ins, b, loss * (1.0 - ded), "un robo")
	var fire_p := float(GameData.events.get("fire", {}).get("base_monthly", 0.004)) * 1.2
	var value_t: float = float(oc.get("town_business_value", 900)) * gs.price_mult()
	for tid in towns:
		var t := TradeSim.town(gs, str(tid))
		var claims := 0.0
		for i in range(mini(int(towns[tid]), 400)):
			if GlobalEconSim.rf(gs) >= fire_p:
				continue
			var ratio := 1.0 if GlobalEconSim.rf(gs) < float(oc.get("total_loss_chance", 0.2)) else 0.1 + GlobalEconSim.rf(gs) * 0.2
			claims += value_t * ratio * (1.0 - float(type_def("incendio").get("deductible", 0.1)))
		if claims > 0.0:
			BusinessSim.pay(gs, ins, claims, "siniestros")
			_own_stat(o, "claims", claims)
			t["cash"] = float(t.get("cash", 0.0)) + claims
			gs.notify("Tu aseguradora pagó %s por incendios en %s." % [Fmt.money(claims), str(t.get("name", ""))], "negocio")


static func own_clients(gs, b: Dictionary) -> int:
	var o := own_state(gs, b)
	var n: int = (o.get("clients", []) as Array).size()
	for t in o.get("towns", {}):
		n += int(o["towns"][t])
	return n


# --- Interfaz --------------------------------------------------------------------------------------------

static func panel_lines(gs, b: Dictionary) -> String:
	if not gs.owned_by_player(b):
		var ins := insurer_of(gs, b)
		return "Asegurado por tu aseguradora %s\n" % gs.building_label(ins) if not ins.is_empty() else ""
	var s := ""
	if is_insurer(gs, b):
		var o := own_state(gs, b)
		var last: Dictionary = o.get("last", {})
		s += "Aseguradora: %d clientes (cupo %d) · tarifa ×%.2f · mes anterior: primas %s, siniestros %s\n" % [own_clients(gs, b), capacity(gs, b), float(o.get("rate", 1.2)),
			Fmt.money(float(last.get("premiums", 0.0))), Fmt.money(float(last.get("claims", 0.0)))]
	var pol := policies_of(gs, b)
	if not pol.is_empty():
		var parts := []
		var total := 0.0
		for t in pol:
			parts.append(type_label(str(t)).to_lower())
			total += premium(gs, b, str(t))
		s += "Seguros: %s (prima %s/mes)\n" % [", ".join(parts), Fmt.money2(total)]
	elif eligible(gs, b, "incendio"):
		s += "[color=#aaa]Sin seguro (ver Economía mundial → Seguros)[/color]\n"
	return s
