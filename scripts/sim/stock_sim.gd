class_name StockSim
extends RefCounted
## Economía global — bolsa de valores mundial (ver docs/ECONOMIA_GLOBAL.md).
##
## - Se desbloquea en la Revolución industrial (época 2) y cuando el gobierno aprueba la Ley de Mercado
##   de Valores (la propone el jugador o la crea el propio gobierno; GovSim.monthly → review_law).
## - Tu empresa (todos tus negocios con fines de lucro) puede convertirse en S.A. con acciones. Emitir
##   acciones trae capital: lo pagan ciudadanos con ahorros y las cajas de los pueblos vecinos
##   (economía cerrada: el dinero cambia de manos, no aparece).
## - Empresas NPC grandes salen a bolsa (el fundador vende parte a los ahorradores) y hay empresas de
##   otros países, resumidas, que cotizan en su moneda (se muestran convertidas a la tuya).
## - Precio: se acerca al valor fundamental (ganancias × P/G del ciclo, con piso en el patrimonio) más
##   la presión de compras y ventas y un ruido moderado (tope ±15 %/mes).
## - Dividendos mensuales. Compra hostil: si otro acumula más del 50 % de tu S.A., pierdes el control
##   (reparte el 70 % de las ganancias y no puedes emitir). Defensa: recomprar acciones (se retiran).
## Titulares: "p" jugador, "c:<id>" ciudadano, "t:<id>" pueblo vecino, "g" Estado, "w" inversores del
## resto del mundo (solo empresas extranjeras). Estado: gs.world_econ["stock"].

const PLAYER := "p"
const WORLD := "w"
const STATE := "g"


static func cfg() -> Dictionary:
	return GlobalEconSim.cfg().get("stock", {})


static func init_state(gs) -> void:
	var w: Dictionary = gs.world_econ
	if not w.has("stock") or not (w["stock"] is Dictionary):
		w["stock"] = {}
	var s: Dictionary = w["stock"]
	if not s.has("law"):
		s["law"] = {"status": "none", "decide_day": -1, "retry_day": -1, "approved_day": -1, "by": ""}
	if not s.has("companies"):
		s["companies"] = {}
	if not s.has("next_id"):
		s["next_id"] = 1
	if not s.has("world_cash"):
		s["world_cash"] = float(cfg().get("world_cash", 1000000.0))
	if not s.has("log"):
		s["log"] = []


static func st(gs) -> Dictionary:
	return gs.world_econ.get("stock", {})


static func companies(gs) -> Dictionary:
	return st(gs).get("companies", {})


static func company(gs, cid: String) -> Dictionary:
	return companies(gs).get(cid, {})


static func world_cash(gs) -> float:
	return float(st(gs).get("world_cash", 0.0))


static func _log(gs, text: String) -> void:
	var l: Array = st(gs).get("log", [])
	l.append({"date": TimeManager.date_string(false), "text": text})
	while l.size() > 40:
		l.pop_front()
	st(gs)["log"] = l


# --- Ley y desbloqueo -------------------------------------------------------------------------------

static func law(gs) -> Dictionary:
	return st(gs).get("law", {})


static func law_approved(gs) -> bool:
	return str(law(gs).get("status", "none")) == "approved"


static func era_ok(gs) -> bool:
	return gs.era() >= int(cfg().get("unlock_era", 2))


static func unlocked(gs) -> bool:
	return GlobalEconSim.ready(gs) and era_ok(gs) and law_approved(gs)


static func block_reason(gs) -> String:
	if not GlobalEconSim.ready(gs):
		return "La economía global no está iniciada."
	if not era_ok(gs):
		return "La bolsa de valores llega con la Revolución industrial."
	match str(law(gs).get("status", "none")):
		"approved":
			return ""
		"study":
			return "El gobierno estudia la Ley de Mercado de Valores (decide hacia el %s)." % TimeManager.date_from_day(int(law(gs)["decide_day"]), TimeManager.start_year())
	return "El gobierno aún no autoriza la bolsa: propón la Ley de Mercado de Valores."


static func law_cost(gs) -> float:
	return float(cfg().get("law", {}).get("propose_cost", 350)) * gs.price_mult()


## Probabilidad de que el gobierno actual apruebe la ley (liberales sí, gobiernos sociales menos).
static func approval_chance(gs) -> float:
	var lc: Dictionary = cfg().get("law", {})
	var social := float(GovSim.policy(gs).get("social", 0.5))
	var ch := float(lc.get("base_chance", 0.5)) + (0.2 - social) * float(lc.get("social_weight", 0.5))
	ch += minf(0.3, PoliticsSim.influence(gs) * float(lc.get("influence_weight", 0.1)))
	return clampf(ch, float(lc.get("min_chance", 0.15)), float(lc.get("max_chance", 0.9)))


static func propose_block_reason(gs) -> String:
	if not era_ok(gs):
		return "Solo desde la Revolución industrial."
	var l := law(gs)
	match str(l.get("status", "none")):
		"approved":
			return "La ley ya está aprobada."
		"study":
			return "El gobierno ya la está estudiando."
	if gs.today() < int(l.get("retry_day", -1)):
		return "El gobierno la rechazó hace poco: podrás volver a proponerla el %s." % TimeManager.date_from_day(int(l["retry_day"]), TimeManager.start_year())
	if gs.money < law_cost(gs):
		return "Necesitas %s para los estudios y el trámite." % Fmt.money(law_cost(gs))
	return ""


## El jugador propone la Ley de Mercado de Valores: paga los estudios (al tesoro) y el gobierno decide.
static func propose_law(gs) -> String:
	var why := propose_block_reason(gs)
	if why != "":
		return why
	var cost := law_cost(gs)
	gs.add_money(-cost)
	GovSim.add_treasury(gs, cost)
	var days: Array = cfg().get("law", {}).get("review_days", [30, 60])
	var l := law(gs)
	l["status"] = "study"
	l["decide_day"] = gs.today() + GlobalEconSim.ri(gs, int(days[0]), int(days[1]))
	l["by"] = "jugador"
	gs.notify("Propusiste la Ley de Mercado de Valores. El gobierno (%s) la estudia; probabilidad de aprobarla: %d %%." % [str(GovSim.policy(gs).get("label", "")), int(approval_chance(gs) * 100.0)], "jugador")
	return ""


static func approve_law(gs, by := "gobierno") -> void:
	var l := law(gs)
	l["status"] = "approved"
	l["approved_day"] = gs.today()
	l["by"] = by
	_ensure_foreign(gs)
	gs.notify("El gobierno aprobó la Ley de Mercado de Valores: abre la BOLSA DE VALORES. Puedes convertir tu empresa en S.A., emitir acciones y comprar acciones de empresas del país y del mundo.", "importante")


## GovSim.monthly: decide la ley en estudio; en la época industrial el gobierno también puede crearla solo.
static func review_law(gs) -> void:
	var l := law(gs)
	var status := str(l.get("status", "none"))
	if status == "study" and gs.today() >= int(l.get("decide_day", 0)):
		if GlobalEconSim.rf(gs) < approval_chance(gs):
			approve_law(gs, "jugador")
		else:
			l["status"] = "rejected"
			l["retry_day"] = gs.today() + int(cfg().get("law", {}).get("retry_days", 180))
			gs.notify("El gobierno rechazó la Ley de Mercado de Valores. Podrás proponerla de nuevo más adelante (o esperar otro gobierno).", "jugador")
	elif status != "approved" and status != "study" and era_ok(gs):
		var ch := float(cfg().get("law", {}).get("gov_monthly_chance", {}).get(str(gs.era()), 0.0))
		if ch > 0.0 and GlobalEconSim.rf(gs) < ch:
			approve_law(gs, "gobierno")


# --- Titulares y dinero ------------------------------------------------------------------------------

static func holding(co: Dictionary, key: String) -> int:
	return int(co.get("holders", {}).get(key, 0))


static func stake(co: Dictionary, key: String) -> float:
	return float(holding(co, key)) / maxf(1.0, float(co.get("shares", 1)))


static func _add_holding(co: Dictionary, key: String, n: int) -> void:
	var h: Dictionary = co.get("holders", {})
	var v := int(h.get(key, 0)) + n
	if v <= 0:
		h.erase(key)
	else:
		h[key] = v
	co["holders"] = h


static func holder_label(gs, key: String) -> String:
	if key == PLAYER:
		return "Tú"
	if key == STATE:
		return "el Estado"
	if key == WORLD:
		return "inversores extranjeros"
	if key.begins_with("c:"):
		return gs.person_name(int(key.substr(2)))
	if key.begins_with("t:"):
		return "inversores de %s" % str(TradeSim.town(gs, key.substr(2)).get("name", "otro pueblo"))
	return key


## Cobra a un titular. Devuelve lo cobrado (lo que tenga).
static func _debit(gs, key: String, amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	if key == PLAYER:
		gs.add_money(-amount)
		return amount
	if key == WORLD:
		st(gs)["world_cash"] = world_cash(gs) - amount
		return amount
	if key == STATE:
		return GovSim.treasury_pay(gs, amount)
	if key.begins_with("c:"):
		var c: Citizen = gs.citizens.get(int(key.substr(2)))
		if c == null:
			return 0.0
		var take := minf(maxf(0.0, c.money), amount)
		c.money -= take
		return take
	if key.begins_with("t:"):
		var t := TradeSim.town(gs, key.substr(2))
		if t.is_empty():
			return 0.0
		var take := minf(maxf(0.0, float(t.get("cash", 0.0))), amount)
		t["cash"] = float(t.get("cash", 0.0)) - take
		return take
	return 0.0


static func _credit(gs, key: String, amount: float) -> void:
	if amount <= 0.0:
		return
	if key == PLAYER:
		gs.add_money(amount)
	elif key == WORLD:
		st(gs)["world_cash"] = world_cash(gs) + amount
	elif key.begins_with("c:") and gs.citizens.has(int(key.substr(2))):
		gs.citizens[int(key.substr(2))].money += amount
	elif key.begins_with("t:") and not TradeSim.town(gs, key.substr(2)).is_empty():
		var t := TradeSim.town(gs, key.substr(2))
		t["cash"] = float(t.get("cash", 0.0)) + amount
	else:
		GovSim.add_treasury(gs, amount)


## Ahorradores dispuestos a invertir: [{key, cap}] (ciudadanos con ahorros de sobra y pueblos vecinos).
static func investors(gs, exclude: Dictionary = {}) -> Array:
	var out := []
	var nd := ShopSim.need_day(gs)
	var buffer := nd * float(cfg().get("investor_buffer_days", 60))
	var share := float(cfg().get("investor_share", 0.25))
	var today: int = gs.today()
	var adult := int(GameData.citizens.get("adult_age", 16))
	var ids: Array = gs.citizens.keys()
	ids.sort()
	for id in ids:
		var c: Citizen = gs.citizens[id]
		var key := "c:%d" % c.id
		if exclude.has(key) or gs.is_player(c.id) or c.age_years(today) < adult or c.prison_until >= 0:
			continue
		if NpcBusinessSim._player_family(gs, c):
			continue
		var cap: float = (c.money - buffer) * share
		if cap > 1.0:
			out.append({"key": key, "cap": cap})
	for t in TradeSim.towns(gs):
		var key := "t:%s" % str(t["id"])
		if exclude.has(key):
			continue
		var cap := maxf(0.0, float(t.get("cash", 0.0))) * float(cfg().get("town_invest_share", 0.04))
		if cap > 1.0:
			out.append({"key": key, "cap": cap})
	return out


static func investor_capacity(gs, exclude: Dictionary = {}) -> float:
	var total := 0.0
	for inv in investors(gs, exclude):
		total += float(inv["cap"])
	return total


## Reparte hasta `qty` acciones entre los inversionistas al precio `unit`. Cobra a cada uno.
## Devuelve {shares, money, buyers: {key: n}}.
static func _place(gs, qty: int, unit: float, exclude: Dictionary) -> Dictionary:
	var invs := investors(gs, exclude)
	var total_cap := 0.0
	for inv in invs:
		total_cap += float(inv["cap"])
	var out := {"shares": 0, "money": 0.0, "buyers": {}}
	if qty <= 0 or unit <= 0.0 or total_cap < unit:
		return out
	var want := mini(qty, int(floorf(total_cap / unit)))
	invs.sort_custom(func(a, b): return float(a["cap"]) > float(b["cap"]))
	var left := want
	for inv in invs:
		if left <= 0:
			break
		var n := mini(left, int(floorf(float(inv["cap"]) / unit)))
		n = mini(n, maxi(1, int(ceilf(float(want) * float(inv["cap"]) / total_cap))))
		if n <= 0:
			continue
		var paid := _debit(gs, str(inv["key"]), n * unit)
		var got := int(floorf(paid / unit + 0.0001))
		if got < n:
			_credit(gs, str(inv["key"]), paid - got * unit)   # Devuelve lo que no alcanzó.
		if got <= 0:
			continue
		out["buyers"][str(inv["key"])] = got
		out["shares"] = int(out["shares"]) + got
		out["money"] = float(out["money"]) + got * unit
		left -= got
	return out


## Compra `qty` acciones a los titulares (salvo los excluidos), a prorrata. Paga `buyer_key`.
## Devuelve {shares, money, sellers: {key: n}}.
static func _take_from_holders(gs, co: Dictionary, qty: int, unit: float, exclude: Dictionary, buyer_key: String) -> Dictionary:
	var out := {"shares": 0, "money": 0.0, "sellers": {}}
	var h: Dictionary = co.get("holders", {})
	var keys := h.keys().filter(func(k): return not exclude.has(str(k)))
	keys.sort_custom(func(a, b): return int(h[a]) > int(h[b]) if int(h[a]) != int(h[b]) else str(a) < str(b))
	var avail := 0
	for k in keys:
		avail += int(h[k])
	qty = mini(qty, avail)
	if qty <= 0:
		return out
	var left := qty
	for k in keys:
		if left <= 0:
			break
		var n := mini(left, maxi(1, int(ceilf(float(qty) * float(h[k]) / float(avail)))))
		n = mini(n, int(h[k]))
		out["sellers"][str(k)] = n
		left -= n
	var total := 0
	for k in out["sellers"]:
		total += int(out["sellers"][k])
	var cost := total * unit
	var paid := _debit(gs, buyer_key, cost)
	if paid < cost - 0.01:
		_credit(gs, buyer_key, paid)
		return {"shares": 0, "money": 0.0, "sellers": {}}
	for k in out["sellers"]:
		var n := int(out["sellers"][k])
		_add_holding(co, str(k), -n)
		_credit(gs, str(k), n * unit)
	out["shares"] = total
	out["money"] = cost
	return out


# --- Valoración -------------------------------------------------------------------------------------

## Ganancia anual estimada (promedio de los últimos meses × 12), en la moneda de la empresa.
static func annual_profit(co: Dictionary) -> float:
	var p: Array = co.get("profits", [])
	if p.is_empty():
		return 0.0
	var s := 0.0
	for v in p:
		s += float(v)
	return s / float(p.size()) * 12.0


static func player_company_profit(gs) -> float:
	var total := 0.0
	for b in gs.player_buildings():
		if BusinessSim.is_business(b) and not BusinessSim.is_nonprofit(b):
			total += BusinessSim.period_profit(b, "last_month")
	return total


static func _book(gs, co: Dictionary) -> float:
	match str(co.get("kind", "")):
		"jugador":
			return maxf(0.0, EconomySim.player_assets(gs) + maxf(0.0, gs.money) * 0.5 - EconomySim.player_debt(gs))
		"npc":
			var b: Dictionary = gs.get_building(int(co.get("building", -1)))
			return NpcBusinessSim.valuation(gs, b) if not b.is_empty() else 0.0
	return float(co.get("eps", 1.0)) * float(co.get("shares", 1)) * 4.0


## Precio fundamental por acción: máx(patrimonio × piso, ganancia anual × P/G del ciclo) / acciones.
static func fundamental(gs, co: Dictionary) -> float:
	var shares := maxf(1.0, float(co.get("shares", 1)))
	var country := str(co.get("country", GlobalEconSim.home_id(gs)))
	var pe := GlobalEconSim.eff(gs, "pe", 10.0, country)
	if str(co.get("kind", "")) == "extranjera":
		return maxf(0.01, float(co.get("eps", 1.0)) * pe)
	var earn := annual_profit(co) * pe
	return maxf(0.01, maxf(_book(gs, co) * float(cfg().get("book_floor", 0.6)), earn) / shares)


static func market_cap(gs, co: Dictionary) -> float:
	return float(co.get("price", 0.0)) * float(co.get("shares", 0))


## Valor en TU moneda de las acciones de `key` en la empresa.
static func holding_value(gs, co: Dictionary, key := PLAYER) -> float:
	return GlobalEconSim.to_home(gs, float(holding(co, key)) * float(co.get("price", 0.0)), str(co.get("country", GlobalEconSim.home_id(gs))))


static func portfolio_value(gs) -> float:
	var v := 0.0
	for cid in companies(gs):
		var co: Dictionary = companies(gs)[cid]
		if str(co.get("kind", "")) != "jugador":
			v += holding_value(gs, co)
	return v


## Quien controla la empresa: el titular con más del 50 % (o el jugador si nadie lo tiene).
static func controller(co: Dictionary) -> String:
	var h: Dictionary = co.get("holders", {})
	var total := float(co.get("shares", 1))
	for k in h:
		if float(h[k]) > total * 0.5:
			return str(k)
	return PLAYER if str(co.get("kind", "")) == "jugador" else str(co.get("founder_key", ""))


static func player_in_control(gs) -> bool:
	var co := player_company(gs)
	return co.is_empty() or controller(co) == PLAYER


static func _update_control(gs, co: Dictionary) -> void:
	var now := controller(co)
	var before := str(co.get("controller", PLAYER))
	co["controller"] = now
	if str(co.get("kind", "")) != "jugador" or now == before:
		return
	if now != PLAYER:
		gs.notify("¡COMPRA HOSTIL! %s acumuló el %d %% de %s y tomó el control: reparte el %d %% de las ganancias y ya no puedes emitir acciones. Recompra acciones para recuperarla." % [
			holder_label(gs, now), int(stake(co, now) * 100.0), str(co["name"]), int(float(cfg().get("payout_raider", 0.7)) * 100.0)], "jugador")
		_log(gs, "%s tomó el control de %s." % [holder_label(gs, now), str(co["name"])])
	else:
		gs.notify("Recuperaste el control de %s." % str(co["name"]), "jugador")
		_log(gs, "Recuperaste el control de %s." % str(co["name"]))


# --- Tu empresa como S.A. ------------------------------------------------------------------------------

static func player_company(gs) -> Dictionary:
	return company(gs, PLAYER)


static func convert_block_reason(gs) -> String:
	var why := block_reason(gs)
	if why != "":
		return why
	if not player_company(gs).is_empty():
		return "Tu empresa ya es una S.A."
	var any := false
	for b in gs.player_buildings():
		if BusinessSim.is_business(b) and not BusinessSim.is_nonprofit(b):
			any = true
			break
	if not any:
		return "Necesitas al menos un negocio con fines de lucro."
	var fee: float = float(cfg().get("listing_fee", 250)) * gs.price_mult()
	if gs.money < fee:
		return "Necesitas %s para la inscripción en bolsa." % Fmt.money(fee)
	return ""


## Convierte tu empresa (todos tus negocios con fines de lucro) en S.A. con acciones. Todas son tuyas.
static func convert_to_sa(gs, company_name := "") -> String:
	var why := convert_block_reason(gs)
	if why != "":
		return why
	var fee: float = float(cfg().get("listing_fee", 250)) * gs.price_mult()
	gs.add_money(-fee)
	GovSim.add_treasury(gs, fee)
	var shares := int(cfg().get("company_shares", 1000))
	var name := company_name.strip_edges()
	if name == "":
		name = "%s S.A." % str(gs.settings.get("player_surname", "Mi empresa"))
	var co := {"id": PLAYER, "kind": "jugador", "name": name, "country": GlobalEconSim.home_id(gs), "shares": shares,
		"holders": {PLAYER: shares}, "price": 0.0, "profits": [player_company_profit(gs)], "payout": float(cfg().get("payout_default", 0.3)),
		"pressure": 0.0, "hist": [], "listed_day": gs.today(), "last_issue_day": -9999, "raider": -1, "controller": PLAYER, "div_last": 0.0}
	companies(gs)[PLAYER] = co
	co["price"] = snappedf(fundamental(gs, co), 0.01)
	gs.notify("%s ya es una sociedad anónima: %d acciones a %s cada una (todas tuyas)." % [name, shares, Fmt.money2(float(co["price"]))], "jugador")
	_log(gs, "%s salió a bolsa." % name)
	return ""


static func issue_block_reason(gs, qty: int) -> String:
	var co := player_company(gs)
	if co.is_empty():
		return "Primero convierte tu empresa en S.A."
	if not unlocked(gs):
		return block_reason(gs)
	if controller(co) != PLAYER:
		return "Perdiste el control de tu S.A.: el nuevo controlador no aprueba emisiones."
	if gs.today() < int(co.get("last_issue_day", -9999)) + int(cfg().get("issue_cooldown_days", 90)):
		return "Solo una emisión cada %d días." % int(cfg().get("issue_cooldown_days", 90))
	var max_q := int(float(co["shares"]) * float(cfg().get("max_issue_ratio", 0.35)))
	if qty <= 0 or qty > max_q:
		return "Puedes emitir entre 1 y %d acciones." % max_q
	return ""


## Emite `qty` acciones nuevas. Las compran ciudadanos con ahorros y pueblos vecinos; el capital entra a tu caja.
## Devuelve {error, sold, raised}.
static func issue(gs, qty: int) -> Dictionary:
	var why := issue_block_reason(gs, qty)
	if why != "":
		return {"error": why, "sold": 0, "raised": 0.0}
	var co := player_company(gs)
	var unit := float(co["price"]) * (1.0 - float(cfg().get("issue_discount", 0.05)))
	var placed := _place(gs, qty, unit, {})
	var sold := int(placed["shares"])
	if sold <= 0:
		return {"error": "No hay ahorradores con dinero suficiente para comprar acciones ahora.", "sold": 0, "raised": 0.0}
	co["shares"] = int(co["shares"]) + sold
	for k in placed["buyers"]:
		_add_holding(co, str(k), int(placed["buyers"][k]))
	var raised := float(placed["money"])
	gs.add_money(raised)
	gs.add_counter("stock_issue", raised)
	co["last_issue_day"] = gs.today()
	co["pressure"] = float(co.get("pressure", 0.0)) - float(cfg().get("impact", 0.15)) * float(sold) / float(co["shares"])
	gs.notify("Emitiste %d acciones de %s a %s: entraron %s de capital. Ahora tienes el %d %%." % [sold, str(co["name"]), Fmt.money2(unit), Fmt.money(raised), int(stake(co, PLAYER) * 100.0)], "jugador")
	if stake(co, PLAYER) < 0.5:
		gs.notify("Cuidado: tienes menos del 50 %% de %s. Un inversionista podría comprar acciones y quitarte el control." % str(co["name"]), "jugador")
	_log(gs, "Emisión: %d acciones de %s (%s)." % [sold, str(co["name"]), Fmt.money(raised)])
	_update_control(gs, co)
	return {"error": "" if sold >= qty else "Solo se colocaron %d de %d acciones (faltan ahorradores)." % [sold, qty], "sold": sold, "raised": raised}


## Recompra de acciones propias (se retiran): sube tu participación. Primero a los accionistas
## dispersos; si no alcanza, al que acumuló (compra hostil) con prima.
static func buyback(gs, qty: int) -> Dictionary:
	var co := player_company(gs)
	if co.is_empty():
		return {"error": "Tu empresa no es una S.A.", "bought": 0, "cost": 0.0}
	if qty <= 0:
		return {"error": "Cantidad inválida.", "bought": 0, "cost": 0.0}
	var raider_key := "c:%d" % int(co.get("raider", -1))
	var exclude := {PLAYER: true, raider_key: true}
	var float_n := int(co["shares"]) - holding(co, PLAYER) - holding(co, raider_key)
	var unit := float(co["price"]) * (1.0 + float(cfg().get("impact", 0.15)) * float(mini(qty, maxi(1, float_n))) / maxf(1.0, float(co["shares"])))
	var need_float := mini(qty, float_n)
	var need_raider := mini(qty - need_float, holding(co, raider_key))
	var premium := float(co["price"]) * (1.0 + float(cfg().get("greenmail_premium", 0.25)))
	var est := need_float * unit + need_raider * premium
	if gs.money < est:
		return {"error": "Necesitas %s." % Fmt.money(est), "bought": 0, "cost": 0.0}
	var got := 0
	var cost := 0.0
	if need_float > 0:
		var r := _take_from_holders(gs, co, need_float, unit, exclude, PLAYER)
		got += int(r["shares"])
		cost += float(r["money"])
	if need_raider > 0:
		var r2 := _take_from_holders(gs, co, need_raider, premium, {PLAYER: true}, PLAYER) if holding(co, raider_key) > 0 and _only_raider_left(co, raider_key) else {"shares": 0, "money": 0.0}
		got += int(r2["shares"])
		cost += float(r2["money"])
	if got <= 0:
		return {"error": "No hay acciones disponibles para recomprar.", "bought": 0, "cost": 0.0}
	co["shares"] = int(co["shares"]) - got   # Se retiran.
	co["pressure"] = float(co.get("pressure", 0.0)) + float(cfg().get("impact", 0.15)) * float(got) / maxf(1.0, float(co["shares"]))
	gs.add_counter("stock_buyback", cost)
	gs.notify("Recompraste %d acciones de %s por %s. Ahora tienes el %d %%." % [got, str(co["name"]), Fmt.money(cost), int(stake(co, PLAYER) * 100.0)], "jugador")
	_log(gs, "Recompra: %d acciones de %s." % [got, str(co["name"])])
	_update_control(gs, co)
	return {"error": "", "bought": got, "cost": cost}


static func _only_raider_left(co: Dictionary, raider_key: String) -> bool:
	for k in co.get("holders", {}):
		if str(k) != PLAYER and str(k) != raider_key:
			return false
	return true


static func set_payout(gs, ratio: float) -> String:
	var co := player_company(gs)
	if co.is_empty():
		return "Tu empresa no es una S.A."
	if controller(co) != PLAYER:
		return "El controlador decide los dividendos."
	co["payout"] = clampf(ratio, 0.0, float(cfg().get("payout_max", 0.8)))
	return ""


static func payout_of(co: Dictionary) -> float:
	if str(co.get("kind", "")) == "jugador":
		if controller(co) != PLAYER:
			return float(GlobalEconSim.cfg().get("stock", {}).get("payout_raider", 0.7))
		return float(co.get("payout", 0.3))
	if str(co.get("kind", "")) == "npc":
		return float(GlobalEconSim.cfg().get("stock", {}).get("npc_payout", 0.35))
	return float(GlobalEconSim.cfg().get("stock", {}).get("foreign_payout", 0.4))


# --- Comprar y vender acciones de otras empresas -----------------------------------------------------------

static func quote_buy(gs, cid: String, qty: int) -> Dictionary:
	var co := company(gs, cid)
	if co.is_empty() or qty <= 0:
		return {"unit": 0.0, "total": 0.0, "fee": 0.0, "available": 0}
	var fee_r := float(cfg().get("trade_fee", 0.01))
	if str(co["kind"]) == "extranjera":
		var unit_h := GlobalEconSim.to_home(gs, float(co["price"]), str(co["country"]))
		var avail := holding(co, WORLD)
		return {"unit": unit_h, "total": unit_h * qty * (1.0 + fee_r), "fee": unit_h * qty * fee_r, "available": avail, "unit_local": float(co["price"])}
	var avail2 := _float_for_player(co)
	var unit := float(co["price"]) * (1.0 + float(cfg().get("impact", 0.15)) * float(qty) / maxf(1.0, float(co["shares"])))
	return {"unit": unit, "total": unit * qty * (1.0 + fee_r), "fee": unit * qty * fee_r, "available": avail2, "unit_local": unit}


static func _float_for_player(co: Dictionary) -> int:
	var n := 0
	var founder := str(co.get("founder_key", ""))
	for k in co.get("holders", {}):
		if str(k) != PLAYER and str(k) != founder:
			n += int(co["holders"][k])
	return n


## Compra acciones de una empresa NPC o extranjera. Devuelve {error, bought, cost}.
static func buy(gs, cid: String, qty: int) -> Dictionary:
	if not unlocked(gs):
		return {"error": block_reason(gs), "bought": 0, "cost": 0.0}
	var co := company(gs, cid)
	if co.is_empty():
		return {"error": "Empresa no encontrada.", "bought": 0, "cost": 0.0}
	if str(co["kind"]) == "jugador":
		return {"error": "Para tu propia S.A. usa la recompra.", "bought": 0, "cost": 0.0}
	var q := quote_buy(gs, cid, qty)
	qty = mini(qty, int(q["available"]))
	if qty <= 0:
		return {"error": "No hay acciones a la venta.", "bought": 0, "cost": 0.0}
	q = quote_buy(gs, cid, qty)
	if gs.money < float(q["total"]):
		return {"error": "Necesitas %s." % Fmt.money(float(q["total"])), "bought": 0, "cost": 0.0}
	var fee: float = float(q["fee"])
	var cost := 0.0
	if str(co["kind"]) == "extranjera":
		cost = float(q["unit"]) * qty
		gs.add_money(-cost)
		st(gs)["world_cash"] = world_cash(gs) + cost   # El dinero sale del pueblo hacia el vendedor extranjero.
		_add_holding(co, WORLD, -qty)
		_add_holding(co, PLAYER, qty)
	else:
		var r := _take_from_holders(gs, co, qty, float(q["unit"]), {PLAYER: true, str(co.get("founder_key", "")): true}, PLAYER)
		qty = int(r["shares"])
		cost = float(r["money"])
		if qty <= 0:
			return {"error": "No se pudo completar la compra.", "bought": 0, "cost": 0.0}
		_add_holding(co, PLAYER, qty)
		fee = cost * float(cfg().get("trade_fee", 0.01))
	gs.add_money(-fee)
	GovSim.add_treasury(gs, fee)   # Comisión de bolsa.
	co["pressure"] = float(co.get("pressure", 0.0)) + float(cfg().get("impact", 0.15)) * float(qty) / maxf(1.0, float(co["shares"]))
	gs.add_counter("stock_bought", cost + fee)
	_log(gs, "Compraste %d acciones de %s por %s." % [qty, str(co["name"]), Fmt.money(cost + fee)])
	return {"error": "", "bought": qty, "cost": cost + fee}


## Vende acciones tuyas de una empresa NPC o extranjera. Devuelve {error, sold, received}.
static func sell(gs, cid: String, qty: int) -> Dictionary:
	var co := company(gs, cid)
	if co.is_empty():
		return {"error": "Empresa no encontrada.", "sold": 0, "received": 0.0}
	if str(co["kind"]) == "jugador":
		return {"error": "Para conseguir capital con tu S.A. emite acciones.", "sold": 0, "received": 0.0}
	qty = mini(qty, holding(co, PLAYER))
	if qty <= 0:
		return {"error": "No tienes acciones de esa empresa.", "sold": 0, "received": 0.0}
	var fee_r := float(cfg().get("trade_fee", 0.01))
	var got := 0.0
	if str(co["kind"]) == "extranjera":
		var unit_h := GlobalEconSim.to_home(gs, float(co["price"]), str(co["country"]))
		got = unit_h * qty
		st(gs)["world_cash"] = world_cash(gs) - got
		gs.add_money(got)
		_add_holding(co, PLAYER, -qty)
		_add_holding(co, WORLD, qty)
	else:
		var unit := float(co["price"]) * (1.0 - float(cfg().get("impact", 0.15)) * float(qty) / maxf(1.0, float(co["shares"])))
		var placed := _place(gs, qty, unit, {PLAYER: true})
		qty = int(placed["shares"])
		if qty <= 0:
			return {"error": "No hay compradores con ahorros suficientes ahora.", "sold": 0, "received": 0.0}
		got = float(placed["money"])
		gs.add_money(got)
		_add_holding(co, PLAYER, -qty)
		for k in placed["buyers"]:
			_add_holding(co, str(k), int(placed["buyers"][k]))
	var fee: float = got * fee_r
	gs.add_money(-fee)
	GovSim.add_treasury(gs, fee)
	co["pressure"] = float(co.get("pressure", 0.0)) - float(cfg().get("impact", 0.15)) * float(qty) / maxf(1.0, float(co["shares"]))
	gs.add_counter("stock_sold", got - fee)
	_log(gs, "Vendiste %d acciones de %s por %s." % [qty, str(co["name"]), Fmt.money(got - fee)])
	return {"error": "", "sold": qty, "received": got - fee}


# --- Empresas NPC y extranjeras ---------------------------------------------------------------------------

static func _ensure_foreign(gs) -> void:
	var home := GlobalEconSim.home_id(gs)
	var cos := companies(gs)
	var have := 0
	for cid in cos:
		if str(cos[cid].get("kind", "")) == "extranjera":
			have += 1
	var max_f := int(cfg().get("foreign_max", 8))
	if have >= max_f:
		return
	var names: Array = cfg().get("foreign_names", ["Industrias"])
	var i := 0
	for id in GlobalEconSim.country_ids():
		if str(id) == home:
			continue
		var cid := "f:%s" % str(id)
		if cos.has(cid):
			continue
		if have >= max_f:
			break
		var sector := str(names[(i + str(id).length()) % names.size()])
		var eps := snappedf(1.5 + GlobalEconSim.rf(gs) * 3.0, 0.01) * GlobalEconSim.rate(gs, str(id))
		var shares := 100000
		var co := {"id": cid, "kind": "extranjera", "name": "%s de %s" % [sector, GlobalEconSim.country_label(str(id))], "country": str(id),
			"sector": sector, "shares": shares, "holders": {WORLD: shares}, "eps": eps, "price": 0.0, "pressure": 0.0, "hist": [], "div_last": 0.0,
			"listed_day": gs.today()}
		co["price"] = snappedf(fundamental(gs, co), 0.01)
		cos[cid] = co
		have += 1
		i += 1


static func _npc_listings(gs) -> void:
	var cos := companies(gs)
	var listed := 0
	for cid in cos.keys():
		var co: Dictionary = cos[cid]
		if str(co.get("kind", "")) != "npc":
			continue
		var b: Dictionary = gs.get_building(int(co.get("building", -1)))
		if b.is_empty() or not NpcBusinessSim.is_npc(b) or str(b.get("status", "")) != "activo" or str(b.get("npc_state", "")) != NpcBusinessSim.STATE_OPEN:
			_delist(gs, co, "quebró, cerró o cambió de dueño")
			cos.erase(cid)
			continue
		listed += 1
	if listed >= int(cfg().get("npc_max_listed", 6)):
		return
	var min_value: float = float(cfg().get("npc_list_min_value", 1500)) * gs.price_mult()
	for b in NpcBusinessSim.npc_buildings(gs):
		if listed >= int(cfg().get("npc_max_listed", 6)):
			break
		var cid := "n:%d" % int(b["id"])
		if cos.has(cid) or str(b.get("status", "")) != "activo" or str(b.get("npc_state", "")) != NpcBusinessSim.STATE_OPEN:
			continue
		if gs.today() - int(b.get("founded_day", gs.today())) < int(cfg().get("npc_list_min_months", 6)) * 30:
			continue
		if NpcBusinessSim.valuation(gs, b) < min_value or GlobalEconSim.rf(gs) >= float(cfg().get("npc_list_chance", 0.12)):
			continue
		if list_npc(gs, b):
			listed += 1


## Salida a bolsa de una empresa NPC: el fundador vende parte a los ahorradores (el dinero va a él).
static func list_npc(gs, b: Dictionary) -> bool:
	var owner_id := int(b.get("owner_id", -1))
	if owner_id < 0 or not gs.citizens.has(owner_id):
		return false
	var cid := "n:%d" % int(b["id"])
	var shares := int(cfg().get("company_shares", 1000))
	var fkey := "c:%d" % owner_id
	var co := {"id": cid, "kind": "npc", "name": gs.building_label(b), "country": GlobalEconSim.home_id(gs), "building": int(b["id"]),
		"founder_key": fkey, "shares": shares, "holders": {fkey: shares}, "price": 0.0, "profits": [BusinessSim.period_profit(b, "last_month")],
		"pressure": 0.0, "hist": [], "div_last": 0.0, "listed_day": gs.today()}
	co["price"] = snappedf(fundamental(gs, co), 0.01)
	var float_n := int(float(shares) * float(cfg().get("npc_float", 0.4)))
	var placed := _place(gs, float_n, float(co["price"]), {fkey: true})
	if int(placed["shares"]) <= 0:
		return false
	_add_holding(co, fkey, -int(placed["shares"]))
	for k in placed["buyers"]:
		_add_holding(co, str(k), int(placed["buyers"][k]))
	_credit(gs, fkey, float(placed["money"]))
	companies(gs)[cid] = co
	gs.notify("%s (de %s) salió a la bolsa: vendió %d acciones a %s." % [str(co["name"]), gs.person_name(owner_id), int(placed["shares"]), Fmt.money2(float(co["price"]))], "negocio")
	_log(gs, "%s salió a bolsa." % str(co["name"]))
	return true


static func _delist(gs, co: Dictionary, why: String) -> void:
	var mine := holding(co, PLAYER)
	if mine > 0:
		gs.notify("%s salió de la bolsa (%s): tus %d acciones ya no cotizan." % [str(co.get("name", "")), why, mine], "jugador")
	_log(gs, "%s salió de la bolsa (%s)." % [str(co.get("name", "")), why])


## Titulares que murieron: sus acciones pasan al cónyuge o a un hijo; si no hay, al Estado.
## Si el titular es ahora el jugador (herencia de la dinastía), se suman a las del jugador.
static func _cleanup_holders(gs, co: Dictionary) -> void:
	var h: Dictionary = co.get("holders", {})
	for k in h.keys():
		var key := str(k)
		if not key.begins_with("c:"):
			continue
		var id := int(key.substr(2))
		if gs.is_player(id):
			_add_holding(co, PLAYER, int(h[k]))
			h.erase(k)
			continue
		if gs.citizens.has(id):
			continue
		var heir := _heir_key(gs, id)
		var n := int(h[k])
		h.erase(k)
		_add_holding(co, heir, n)
		if str(co.get("founder_key", "")) == key:
			co["founder_key"] = heir
		if int(co.get("raider", -1)) == id:
			co["raider"] = -1


static func _heir_key(gs, dead_id: int) -> String:
	for c in gs.citizens.values():
		if c.spouse_id == dead_id or c.parent_ids.has(dead_id):
			return PLAYER if gs.is_player(c.id) else "c:%d" % c.id
	return STATE


# --- Cierre mensual ----------------------------------------------------------------------------------------

static func monthly(gs) -> void:
	init_state(gs)
	if not unlocked(gs):
		return
	_ensure_foreign(gs)
	_npc_listings(gs)
	var sc := cfg()
	for cid in companies(gs).keys():
		var co: Dictionary = companies(gs)[cid]
		_cleanup_holders(gs, co)
		var kind := str(co.get("kind", ""))
		var profit_m := 0.0
		if kind == "jugador":
			profit_m = player_company_profit(gs)
		elif kind == "npc":
			var nb: Dictionary = gs.get_building(int(co.get("building", -1)))
			profit_m = BusinessSim.period_profit(nb, "last_month") if not nb.is_empty() else 0.0
		if kind != "extranjera":
			var p: Array = co.get("profits", [])
			p.append(profit_m)
			while p.size() > 12:
				p.pop_front()
			co["profits"] = p
		else:
			var country := str(co["country"])
			var cst := GlobalEconSim.country(gs, country)
			var g := float(cst.get("infl", 0.03)) + GlobalEconSim.eff(gs, "growth", 0.02, country)
			co["eps"] = maxf(0.01, float(co.get("eps", 1.0)) * (1.0 + g / 12.0 + GlobalEconSim.rn(gs, 0.02)))
		_update_price(gs, co)
		_pay_dividends(gs, co, profit_m)
		if kind == "jugador":
			_raider(gs, co)
			_update_control(gs, co)
		var h: Array = co.get("hist", [])
		h.append({"day": gs.today(), "price": float(co["price"])})
		while h.size() > int(sc.get("history", 36)):
			h.pop_front()
		co["hist"] = h


static func _update_price(gs, co: Dictionary) -> void:
	var sc := cfg()
	var old := maxf(0.01, float(co.get("price", 0.01)))
	var target := fundamental(gs, co)
	var p := old + (target - old) * float(sc.get("price_revert", 0.3))
	p *= 1.0 + GlobalEconSim.rn(gs, float(sc.get("price_vol", 0.03))) + float(co.get("pressure", 0.0))
	var mv := float(sc.get("max_move", 0.15))
	co["price"] = snappedf(clampf(p, old * (1.0 - mv), old * (1.0 + mv)), 0.01)
	co["price"] = maxf(0.01, float(co["price"]))
	co["pressure"] = float(co.get("pressure", 0.0)) * float(sc.get("pressure_decay", 0.5))


static func _pay_dividends(gs, co: Dictionary, profit_m: float) -> void:
	var kind := str(co.get("kind", ""))
	var shares := maxf(1.0, float(co.get("shares", 1)))
	co["div_last"] = 0.0
	if kind == "extranjera":
		var dps := float(co.get("eps", 0.0)) * payout_of(co) / 12.0
		co["div_last"] = dps
		var mine := holding(co, PLAYER)
		if mine > 0:
			var amount := GlobalEconSim.to_home(gs, dps * mine, str(co["country"]))
			st(gs)["world_cash"] = world_cash(gs) - amount
			gs.add_money(amount)
			gs.add_counter("dividends_in", amount)
		return
	if profit_m <= 0.0:
		return
	var total := profit_m * payout_of(co)
	if kind == "jugador":
		if gs.money <= 0.0:
			return   # Sin caja no hay reparto.
		total = minf(total, gs.money)
		var external := total * (1.0 - stake(co, PLAYER))
		if external <= 0.0:
			co["div_last"] = total / shares
			return
		gs.add_money(-external)
		gs.add_counter("dividends_out", external)
		for k in co["holders"]:
			if str(k) != PLAYER:
				_credit(gs, str(k), total * float(co["holders"][k]) / shares)
		co["div_last"] = total / shares
	elif kind == "npc":
		var b: Dictionary = gs.get_building(int(co.get("building", -1)))
		if b.is_empty():
			return
		# El fundador ya cobra sus dividendos de la caja (NpcBusinessSim); aquí cobran los demás.
		var founder := str(co.get("founder_key", ""))
		var minority := total * (1.0 - stake(co, founder))
		minority = minf(minority, maxf(0.0, float(b.get("reserve", 0.0))) * 0.5)
		if minority <= 0.0:
			return
		b["reserve"] = float(b["reserve"]) - minority
		var others := shares - float(holding(co, founder))
		for k in co["holders"]:
			if str(k) != founder:
				var part := minority * float(co["holders"][k]) / maxf(1.0, others)
				_credit(gs, str(k), part)
				if str(k) == PLAYER:
					gs.add_counter("dividends_in", part)
		co["div_last"] = minority / maxf(1.0, others)


## Compra hostil: con menos del 50 % en manos del jugador, un inversionista rico puede acumular acciones.
static func _raider(gs, co: Dictionary, force := false) -> void:
	var sc := cfg()
	if stake(co, PLAYER) >= 0.5:
		return
	var rid := int(co.get("raider", -1))
	if rid >= 0 and not gs.citizens.has(rid):
		rid = -1
		co["raider"] = -1
	if rid < 0:
		if not force and GlobalEconSim.rf(gs) >= float(sc.get("raider_start_chance", 0.3)):
			return
		var best: Citizen = null
		for c in gs.citizens.values():
			if gs.is_player(c.id) or NpcBusinessSim._player_family(gs, c) or c.prison_until >= 0:
				continue
			if best == null or c.money > best.money:
				best = c
		if best == null or best.money < float(sc.get("raider_min_money", 2000)) * gs.price_level():
			return
		rid = best.id
		co["raider"] = rid
		gs.notify("%s está comprando acciones de %s. Si llega al 50 %%, perderás el control." % [best.full_name(), str(co["name"])], "jugador")
	var raider: Citizen = gs.citizens[rid]
	var rkey := "c:%d" % rid
	var qty := int(ceilf(float(co["shares"]) * float(sc.get("raider_monthly_buy", 0.08))))
	var unit := float(co["price"]) * 1.05
	var budget: float = maxf(0.0, raider.money) * float(sc.get("raider_spend_share", 0.6))
	qty = mini(qty, int(floorf(budget / maxf(0.01, unit))))
	if qty <= 0:
		return
	var r := _take_from_holders(gs, co, qty, unit, {PLAYER: true, rkey: true}, rkey)
	if int(r["shares"]) > 0:
		_add_holding(co, rkey, int(r["shares"]))
		co["pressure"] = float(co.get("pressure", 0.0)) + float(sc.get("impact", 0.15)) * float(r["shares"]) / maxf(1.0, float(co["shares"]))
		_log(gs, "%s compró %d acciones de %s (ya tiene el %d %%)." % [raider.full_name(), int(r["shares"]), str(co["name"]), int(stake(co, rkey) * 100.0)])


## Una ronda del inversionista hostil (pruebas y escenarios).
static func raider_tick(gs, force := true) -> void:
	var co := player_company(gs)
	if co.is_empty():
		return
	_raider(gs, co, force)
	_update_control(gs, co)


# --- Interfaz ------------------------------------------------------------------------------------------------

## Filas para la tabla de la bolsa (precios en su moneda y convertidos a la tuya).
static func rows(gs) -> Array:
	var out := []
	for cid in companies(gs):
		var co: Dictionary = companies(gs)[cid]
		var h: Array = co.get("hist", [])
		var ch := 0.0
		if h.size() >= 2:
			ch = float(h[h.size() - 1]["price"]) / maxf(0.01, float(h[maxi(0, h.size() - 13)]["price"])) - 1.0
		out.append({"id": str(cid), "name": str(co["name"]), "kind": str(co["kind"]), "country": str(co.get("country", "")),
			"price": float(co["price"]), "price_home": GlobalEconSim.to_home(gs, float(co["price"]), str(co.get("country", GlobalEconSim.home_id(gs)))),
			"change": ch, "mine": holding(co, PLAYER), "stake": stake(co, PLAYER), "div": float(co.get("div_last", 0.0)),
			"controller": controller(co)})
	var order := {"jugador": 0, "npc": 1, "extranjera": 2}
	out.sort_custom(func(a, b): return int(order.get(a["kind"], 3)) < int(order.get(b["kind"], 3)) if a["kind"] != b["kind"] else str(a["name"]) < str(b["name"]))
	return out


## Principales accionistas de una empresa: [[etiqueta, %]].
static func top_holders(gs, co: Dictionary, n := 5) -> Array:
	var h: Dictionary = co.get("holders", {})
	var keys := h.keys()
	keys.sort_custom(func(a, b): return int(h[a]) > int(h[b]))
	var out := []
	for k in keys.slice(0, n):
		out.append([holder_label(gs, str(k)), stake(co, str(k))])
	return out
