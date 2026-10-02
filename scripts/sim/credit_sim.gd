class_name CreditSim
extends RefCounted
## Historial crediticio, mora, negociación de deudas y bancarrota personal.
##
## Puntaje (300–850, empieza en 650) para el jugador (gs.player["credit"]) y para cada ciudadano
## (gs.economy["credit"]["<id>"]). Lo usan los bancos (tasa y cupo: BankSim.player_rate/credit_limit,
## LoanContract) y los préstamos a ciudadanos:
##   - cuota pagada a tiempo: +4 (hasta 850); cuota impaga (mora): −35; incumplimiento: −120;
##   - reestructuración aceptada: −15; dación en pago: −25; embargo: −150; bancarrota: queda en 300.
## Mora: una cuota impaga pone el préstamo "en mora" (missed ≥ 1). Antes de embargar, las deudas
## SIEMPRE se pueden negociar (negotiate):
##   - "plazo":   alarga el plazo 12–24 meses (cuota menor, +1 % de tasa);
##   - "quita":   pagar hoy el 80–90 % del saldo y el banco perdona el resto;
##   - "dacion":  entregar un bien (negocio, casa) por el 85 % de su valor;
##   - "gracia":  3 meses pagando solo intereses (una vez por préstamo).
## El banco acepta según el puntaje, la mora y la situación (patrimonio frente a deuda).
## El embargo es el último recurso: mora prolongada (≥ default_missed cuotas) y sin acuerdo.
## Sobregiro (dinero del jugador < 0): cobra interés al banco cada mes, baja el puntaje y tiene un
## tope; tras `seizure_months` meses en rojo se embargan bienes por orden de liquidez (vehículos →
## negocios → propiedades; nunca la casa donde vive). Si no quedan bienes: bancarrota personal con
## rescate (préstamo de emergencia a tasa alta, o vender empresas); sin rescate en 2 meses, el banco
## castiga la deuda (el saldo vuelve a 0, el puntaje cae a 300 y no hay crédito por 5 años).

const START := 650.0
const MIN_SCORE := 300.0
const MAX_SCORE := 850.0
const OPTIONS := ["plazo", "quita", "dacion", "gracia"]


static func cfg() -> Dictionary:
	return GameData.economy.get("credit", {})


# --- Puntaje -------------------------------------------------------------------------------------

static func _rec(gs, who: String) -> Dictionary:
	if who == "jugador":
		if not (gs.player.get("credit") is Dictionary):
			gs.player["credit"] = {"score": START - 10.0 * float(gs.player.get("credit_marks", 0)), "log": []}
		return gs.player["credit"]
	if not (gs.economy.get("credit") is Dictionary):
		gs.economy["credit"] = {}
	var d: Dictionary = gs.economy["credit"]
	if not d.has(who):
		d[who] = {"score": START, "log": []}
	return d[who]


static func score(gs, who: String) -> float:
	return float(_rec(gs, who).get("score", START))


static func adjust(gs, who: String, delta: float, why: String) -> void:
	var r := _rec(gs, who)
	r["score"] = clampf(float(r.get("score", START)) + delta, MIN_SCORE, MAX_SCORE)
	if who == "jugador" and absf(delta) >= 10.0:
		var entries: Array = r.get("log", [])
		entries.append({"date": TimeManager.date_string(false), "delta": delta, "why": why})
		while entries.size() > 20:
			entries.pop_front()
		r["log"] = entries


static func label(s: float) -> String:
	if s >= 740.0:
		return "Excelente"
	if s >= 670.0:
		return "Bueno"
	if s >= 580.0:
		return "Regular"
	if s >= 450.0:
		return "Malo"
	return "Muy malo"


## Recargo de tasa por riesgo: 0 con 700+, hasta +8 % con 300.
static func rate_add(s: float) -> float:
	return clampf((700.0 - s) / 400.0, 0.0, 1.0) * float(cfg().get("max_rate_add", 0.08))


## Multiplicador del cupo: 1,2 con 800, 1 con 650, 0 con 400 o menos.
static func limit_mult(s: float) -> float:
	return clampf((s - 400.0) / 250.0, 0.0, 1.2)


static func in_bankruptcy(gs) -> bool:
	return int(gs.player.get("bankrupt_until", -1)) > gs.today()


## ¿El jugador tiene algún préstamo en mora (cuotas impagas)?
static func player_in_arrears(gs) -> bool:
	for l in gs.loans:
		if str(l["borrower"]) == "jugador" and int(l.get("missed", 0)) > 0:
			return true
	return false


# --- Negociación -----------------------------------------------------------------------------------

## Qué opciones acepta el banco para un préstamo: {opción: "" si acepta, o el motivo}.
static func options_for(gs, l: Dictionary) -> Dictionary:
	var who := str(l["borrower"])
	var s := score(gs, who)
	var missed := int(l.get("missed", 0))
	var bal := float(l["balance"])
	var out := {}
	# Plazo: con puntaje ≥ 420 y sin otra reestructuración en el último año.
	if int(l.get("restructured_day", -9999)) > gs.today() - 360:
		out["plazo"] = "Ya reestructurado hace menos de un año"
	elif s < 420.0:
		out["plazo"] = "Historial crediticio muy malo"
	else:
		out["plazo"] = ""
	# Quita: pagar hoy una parte; más descuento cuanto peor es la situación (el banco prefiere cobrar algo).
	var cash := _cash_of(gs, who)
	var q := quita_share(gs, l)
	if cash < bal * q:
		out["quita"] = "Necesitas %s en caja" % Fmt.money(bal * q)
	elif missed == 0 and s >= 600.0:
		out["quita"] = "El banco no rebaja deudas al día"
	else:
		out["quita"] = ""
	# Dación en pago: solo el jugador (bienes a su nombre).
	if who != "jugador":
		out["dacion"] = "Solo con bienes a tu nombre"
	elif seizable_assets(gs).is_empty():
		out["dacion"] = "No tienes bienes para entregar"
	else:
		out["dacion"] = ""
	# Gracia: una vez por préstamo, con mora ≤ 2 y puntaje ≥ 480.
	if bool(l.get("grace_used", false)):
		out["gracia"] = "Ya tuvo un periodo de gracia"
	elif missed > 2 or s < 480.0:
		out["gracia"] = "Mora demasiado larga o historial malo"
	else:
		out["gracia"] = ""
	return out


static func quita_share(gs, l: Dictionary) -> float:
	var missed := int(l.get("missed", 0))
	return clampf(0.92 - 0.04 * missed, 0.8, 0.92)


static func _cash_of(gs, who: String) -> float:
	if who == "jugador":
		return maxf(0.0, gs.money)
	var c: Citizen = gs.citizens.get(int(who)) if who.is_valid_int() else null
	return maxf(0.0, c.money) if c != null else 0.0


## Negocia un préstamo. Devuelve "" si el banco aceptó, o el motivo del rechazo.
static func negotiate(gs, loan_id: int, option: String, asset_id := -1) -> String:
	var l := LoanContract.find_loan(gs, loan_id)
	if l.is_empty():
		return "Préstamo no encontrado"
	if not OPTIONS.has(option):
		return "Opción desconocida"
	var why := str(options_for(gs, l).get(option, "No disponible"))
	if why != "":
		return why
	var who := str(l["borrower"])
	var bal := float(l["balance"])
	match option:
		"plazo":
			var extra := 12 if score(gs, who) < 600.0 else 24
			l["term_months"] = int(l.get("term_months", 12)) + extra
			l["rate"] = float(l["rate"]) + 0.01
			l["type"] = "frances"
			l["missed"] = 0
			l["restructured_day"] = gs.today()
			var r := float(l["rate"]) / 12.0
			LoanContract.due(l, bal, bal * r)
			adjust(gs, who, -15.0, "reestructuración del plazo")
			_note(gs, who, "Reestructuraste tu préstamo: %d meses más, nueva cuota %s." % [extra, Fmt.money(float(l["payment"]))])
		"quita":
			var pay := bal * quita_share(gs, l)
			_debit(gs, who, pay)
			BankSim.lender_receive(gs, l, pay, 0.0)
			BankSim.writeoff(gs, l, bal - pay)
			gs.loans.erase(l)
			adjust(gs, who, -30.0, "acuerdo de pago con rebaja")
			_note(gs, who, "Acuerdo con el banco: pagaste %s y te perdonaron %s." % [Fmt.money(pay), Fmt.money(bal - pay)])
		"dacion":
			var assets := seizable_assets(gs)
			var a: Dictionary = assets[0]
			for x in assets:
				if int(x.get("id", -1)) == asset_id:
					a = x
			var value := float(a["value"]) * float(cfg().get("dacion_value", 0.85))
			_hand_over(gs, a)
			var used := minf(value, bal)
			l["balance"] = bal - used
			BankSim.lender_receive(gs, l, used, 0.0, false)   # El banco recibe un bien, no dinero.
			if value > bal:
				gs.add_money(value - bal)   # El banco paga la diferencia.
				FlowSim.bank_move(gs, -(value - bal))
			l["missed"] = 0
			adjust(gs, who, -25.0, "dación en pago")
			_note(gs, who, "Entregaste %s al banco por %s." % [str(a["label"]), Fmt.money(value)])
			if float(l["balance"]) <= 0.01:
				gs.loans.erase(l)
		"gracia":
			l["grace_used"] = true
			l["grace_until"] = gs.today() + 90
			l["missed"] = 0
			adjust(gs, who, -10.0, "periodo de gracia")
			_note(gs, who, "El banco te dio 3 meses de gracia: solo pagas intereses.")
	return ""


static func _debit(gs, who: String, amount: float) -> void:
	if who == "jugador":
		gs.add_money(-amount)
	elif who.is_valid_int() and gs.citizens.has(int(who)):
		gs.citizens[int(who)].money -= amount


static func _note(gs, who: String, text: String) -> void:
	if who == "jugador":
		gs.notify(text, "jugador")


## Un ciudadano con cuotas impagas intenta negociar antes de caer en incumplimiento.
static func npc_try_negotiate(gs, l: Dictionary) -> bool:
	var opts := options_for(gs, l)
	for o in ["gracia", "plazo", "quita"]:
		if str(opts.get(o, "x")) == "":
			return negotiate(gs, int(l["id"]), o) == ""
	return false


# --- Bienes embargables (por orden de liquidez) ------------------------------------------------------

## [{kind, id, label, value}] ordenados del más líquido al menos líquido (sin la casa donde vives).
static func seizable_assets(gs) -> Array:
	var out := []
	var p: Citizen = gs.player_citizen()
	var home := p.home_id if p != null else -1
	for v in _vehicles(gs):
		out.append(v)
	var biz := []
	var props := []
	for b in gs.player_buildings():
		if int(b["id"]) == home or str(b.get("status", "")) == "construccion":
			continue
		var val := EconomySim.property_value(gs, b)
		if val <= 0.0:
			continue
		var e := {"kind": "edificio", "id": int(b["id"]), "label": gs.building_label(b), "value": val}
		if BusinessSim.is_business(b):
			biz.append(e)
		else:
			props.append(e)
	biz.sort_custom(func(a, c): return float(a["value"]) < float(c["value"]))
	props.sort_custom(func(a, c): return float(a["value"]) < float(c["value"]))
	out.append_array(biz)
	out.append_array(props)
	return out


static func _vehicles(gs) -> Array:
	var out := []
	var vs = gs.logistics.get("vehicles", [])
	if vs is Array:
		for v in vs:
			if v is Dictionary and v.has("id"):
				# Valor de reventa: 60 % del precio de un vehículo nuevo de su tipo.
				var val := LogisticsSim.vehicle_price(gs, str(v.get("mode", ""))) * 0.6
				if val > 0.0:
					out.append({"kind": "vehiculo", "id": int(v["id"]), "label": str(v.get("name", v.get("mode", "vehículo"))), "value": val})
	return out


## Entrega un bien al banco (embargo o dación). El bien sale del patrimonio del jugador.
static func _hand_over(gs, a: Dictionary) -> void:
	if str(a["kind"]) == "vehiculo":
		var vs: Array = gs.logistics.get("vehicles", [])
		for v in vs.duplicate():
			if int(v.get("id", -1)) == int(a["id"]):
				vs.erase(v)
		return
	var b: Dictionary = gs.get_building(int(a["id"]))
	if b.is_empty():
		return
	for c in gs.employees_of(int(b["id"])):
		if c.job_kind == "empleo":
			BusinessSim.fire(gs, c)
	b["owner"] = "pueblo"
	b["owner_id"] = -1
	b["for_sale"] = false
	b["seized"] = true
	if BusinessSim.is_business(b) or str(b["type"]) == "oficina":
		b["status"] = "cerrado"
	EventBus.building_changed.emit(int(b["id"]))


## Embargo por orden de liquidez hasta cubrir `amount`. Devuelve {recovered, labels}.
static func seize(gs, amount: float) -> Dictionary:
	var ratio := float(GameData.economy.get("bankruptcy", {}).get("seizure_value", 0.5))
	var recovered := 0.0
	var labels := []
	for a in seizable_assets(gs):
		if recovered >= amount:
			break
		recovered += float(a["value"]) * ratio
		labels.append(str(a["label"]))
		_hand_over(gs, a)
	if not labels.is_empty():
		adjust(gs, "jugador", -150.0, "embargo")
	return {"recovered": recovered, "labels": labels}


# --- Sobregiro y bancarrota personal ------------------------------------------------------------------

## Tope del sobregiro: lo que el banco tolera en rojo antes de exigir (min $500 × precios).
static func overdraft_limit(gs) -> float:
	var base: float = float(cfg().get("overdraft_min", 500.0)) * gs.price_mult()
	return maxf(base, EconomySim.net_worth(gs) * float(cfg().get("overdraft_networth", 0.1)))


## Cierre de mes del saldo del jugador (BankSim.monthly). Reemplaza el embargo "sin bienes" en bucle.
static func monthly_overdraft(gs) -> void:
	var bk: Dictionary = gs.player.get("bankruptcy", {}) if gs.player.get("bankruptcy") is Dictionary else {}
	if not bk.is_empty():
		_bankruptcy_month(gs, bk)
		return
	if gs.money >= 0.0:
		gs.player["negative_months"] = 0
		return
	# Interés del sobregiro: lo cobra el banco.
	var interest: float = -gs.money * float(cfg().get("overdraft_rate", 0.24)) / 12.0
	gs.add_money(-interest)
	FlowSim.bank_move(gs, interest)
	gs.add_counter("interest_paid", interest)
	gs.player["negative_months"] = int(gs.player.get("negative_months", 0)) + 1
	adjust(gs, "jugador", -20.0, "saldo en rojo")
	var limit := int(GameData.economy.get("bankruptcy", {}).get("seizure_months", 3))
	var over: bool = -gs.money > overdraft_limit(gs)
	if int(gs.player["negative_months"]) < limit and not (over and int(gs.player["negative_months"]) >= 2):
		gs.notify("Saldo en rojo (%s, tope %s). En %d mes(es) el banco embargará bienes: vende, cobra o negocia." % [Fmt.money(gs.money), Fmt.money(overdraft_limit(gs)), limit - int(gs.player["negative_months"])], "jugador")
		return
	var debt: float = -gs.money
	var r := seize(gs, debt)
	var got: float = minf(float(r["recovered"]), debt)
	if got > 0.0:
		gs.add_money(got)
		FlowSim.bank_move(gs, -got)
		gs.notify("EMBARGO: el banco se quedó con %s y cubrió %s de tu deuda." % [", ".join(r["labels"]), Fmt.money(got)], "jugador")
	gs.player["negative_months"] = 0
	if gs.money < -0.5:
		_declare_bankruptcy(gs)


static func _declare_bankruptcy(gs) -> void:
	gs.player["bankruptcy"] = {"since": gs.today(), "debt": -gs.money, "deadline": gs.today() + 60}
	adjust(gs, "jugador", -200.0, "bancarrota")
	gs.notify("BANCARROTA PERSONAL: debes %s y no quedan bienes. Opciones: préstamo de emergencia (tasa alta) o vender empresas. Sin rescate en 60 días, el banco castiga la deuda." % Fmt.money(-gs.money), "jugador")


## Rescate 1: el banco convierte el saldo en rojo en un préstamo de emergencia a tasa alta.
static func emergency_loan(gs) -> String:
	var need: float = -gs.money
	if need <= 0.0:
		return "No tienes saldo en rojo"
	if score(gs, "jugador") < float(cfg().get("emergency_min_score", 320.0)) and not gs.player.has("bankruptcy"):
		return "Historial demasiado malo"
	var rate := float(cfg().get("emergency_rate", 0.28))
	var l := BankSim._new_loan(gs, BankSim.EXTERNAL, "jugador", need, rate, int(cfg().get("emergency_months", 36)), "emergencia")
	l["type"] = "frances"
	gs.add_money(need)
	FlowSim.bank_move(gs, -need)
	gs.player.erase("bankruptcy")
	gs.player["negative_months"] = 0
	gs.notify("Préstamo de emergencia: %s al %.0f%% anual, cuota %s." % [Fmt.money(need), rate * 100.0, Fmt.money(float(l["payment"]))], "importante")
	return ""


## Rescate 2: vender una empresa a un empresario del pueblo (o al banco) por el 70 % de su valor.
static func sell_business(gs, bid: int) -> String:
	var b: Dictionary = gs.get_building(bid)
	if b.is_empty() or not gs.owned_by_player(b):
		return "No es tuyo"
	var price := EconomySim.property_value(gs, b) * float(cfg().get("distress_sale", 0.7))
	var buyer: Citizen = null
	for c in gs.citizens.values():
		if not gs.is_player(c.id) and c.money >= price and not NpcBusinessSim._player_family(gs, c):
			buyer = c
			break
	for c2 in gs.employees_of(bid):
		if c2.job_kind == "empleo":
			BusinessSim.fire(gs, c2)
	if buyer != null:
		buyer.money -= price
		b["owner"] = "ciudadano"
		b["owner_id"] = buyer.id
		b["npc"] = BusinessSim.is_business(b)
		b["npc_state"] = NpcBusinessSim.STATE_OPEN if BusinessSim.is_business(b) else ""
		b["owners"] = [{"id": buyer.id, "name": buyer.full_name(), "how": "compra", "day": gs.today()}]
		b["owner_name"] = buyer.full_name()
	else:
		FlowSim.bank_move(gs, -price)   # Lo compra el banco.
		b["owner"] = "pueblo"
		b["owner_id"] = -1
		b["seized"] = true
		if BusinessSim.is_business(b):
			b["status"] = "cerrado"
	gs.add_money(price)
	gs.notify("Vendiste %s por %s%s." % [gs.building_label(b), Fmt.money(price), " a " + buyer.full_name() if buyer != null else " al banco"], "jugador")
	EventBus.building_changed.emit(bid)
	if gs.money >= 0.0 and gs.player.has("bankruptcy"):
		gs.player.erase("bankruptcy")
	return ""


static func _bankruptcy_month(gs, bk: Dictionary) -> void:
	if gs.money >= 0.0:
		gs.player.erase("bankruptcy")
		gs.notify("Saliste de la bancarrota: tu saldo ya no está en rojo.", "importante")
		return
	if gs.today() < int(bk.get("deadline", 0)):
		gs.notify("Bancarrota: debes %s. Pide el préstamo de emergencia o vende una empresa (Finanzas)." % Fmt.money(-gs.money), "jugador")
		return
	# Sin rescate: el banco castiga la deuda (la pierde) y el jugador queda sin crédito 5 años.
	var lost: float = -gs.money
	gs.add_money(lost)
	FlowSim.bank_move(gs, -lost)
	gs.player.erase("bankruptcy")
	gs.player["negative_months"] = 0
	gs.player["bankrupt_until"] = gs.today() + 5 * 365
	_rec(gs, "jugador")["score"] = MIN_SCORE
	gs.count("personal_bankruptcies")
	gs.notify("Quiebra personal cerrada: el banco castigó %s de deuda. Sin crédito por 5 años." % Fmt.money(lost), "jugador")


## Texto corto para la barra superior ("" si todo está bien).
static func bar_warning(gs) -> String:
	if gs.player.get("bankruptcy") is Dictionary:
		return "BANCARROTA: debes %s" % Fmt.money(-gs.money)
	if gs.money < 0.0:
		var limit := int(GameData.economy.get("bankruptcy", {}).get("seizure_months", 3))
		var left := maxi(0, limit - int(gs.player.get("negative_months", 0)))
		return "En rojo %s · embargo en %d mes(es)" % [Fmt.money(gs.money), left]
	if player_in_arrears(gs):
		return "Préstamo en mora: negocia en Finanzas"
	return ""
