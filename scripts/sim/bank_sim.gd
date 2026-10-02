class_name BankSim
extends RefCounted
## Banca: el banco externo presta al jugador con intereses; tu banco presta a los
## ciudadanos con la tasa que decidas. Cuotas mensuales (amortización francesa),
## mora, impago, embargos. Parámetros en data/economy.json.

const EXTERNAL := "externo"


static func ext_cfg() -> Dictionary:
	return GameData.economy.get("external_bank", {})


static func cit_cfg() -> Dictionary:
	return GameData.economy.get("citizen_credit", {})


## Cuota mensual fija.
static func payment(principal: float, rate_annual: float, months: int) -> float:
	var r := rate_annual / 12.0
	if r <= 0.0:
		return principal / maxf(1.0, months)
	return principal * r / (1.0 - pow(1.0 + r, -months))


static func _new_loan(gs, lender: String, borrower: String, amount: float, rate: float, months: int, purpose: String) -> Dictionary:
	var l := {"id": gs.next_loan_id, "lender": lender, "borrower": borrower, "principal": amount,
		"balance": amount, "rate": rate, "term_months": months, "payment": payment(amount, rate, months),
		"months_paid": 0, "missed": 0, "start_day": gs.today(), "purpose": purpose}
	gs.next_loan_id += 1
	gs.loans.append(l)
	return l


# --- Préstamos al jugador ------------------------------------------------------------------

static func player_rate(gs) -> float:
	var base := float(gs.diff().get("bank_interest", 0.07))
	var nw := maxf(1.0, EconomySim.net_worth(gs) + EconomySim.player_debt(gs))
	var leverage := clampf(EconomySim.player_debt(gs) / nw, 0.0, 1.0)
	var bad := CreditSim.rate_add(CreditSim.score(gs, "jugador"))   # Historial crediticio (mora, acuerdos, embargos).
	return base + float(ext_cfg().get("risk_premium_max", 0.08)) * leverage + bad


static func credit_limit(gs) -> float:
	var nw := EconomySim.net_worth(gs)
	var lim := maxf(float(ext_cfg().get("min_limit", 1000)) * gs.price_level(), nw * float(ext_cfg().get("limit_networth_ratio", 0.5))) * GlobalEconSim.credit_limit_mult(gs)   # Ciclo económico.
	if CreditSim.in_bankruptcy(gs) or gs.player.get("bankruptcy") is Dictionary:
		return 0.0
	lim *= CreditSim.limit_mult(CreditSim.score(gs, "jugador"))
	return maxf(0.0, lim - EconomySim.player_debt(gs))


static func request_player_loan(gs, amount: float, months: int) -> String:
	amount = snappedf(amount, 1.0)
	if amount <= 0.0:
		return "Monto inválido"
	var lim := credit_limit(gs)
	if amount > lim:
		return "El banco solo te presta hasta %s" % Fmt.money(lim)
	var rate := player_rate(gs)
	var l := _new_loan(gs, EXTERNAL, "jugador", amount, rate, months, "empresario")
	gs.add_money(amount)
	FlowSim.bank_move(gs, -amount)   # Sale de la caja del banco.
	gs.notify("%s te prestó %s al %.1f%% anual a %d meses (cuota %s)." % [ext_cfg().get("label", "El banco"), Fmt.money(amount), rate * 100.0, months, Fmt.money(float(l["payment"]))], "importante")
	return ""


static func repay_loan(gs, loan_id: int) -> String:
	for l in gs.loans:
		if int(l["id"]) == loan_id and str(l["borrower"]) == "jugador":
			var bal := float(l["balance"])
			if gs.money < bal:
				return "Necesitas %s" % Fmt.money(bal)
			gs.add_money(-bal)
			LoanContract.on_player_paid(gs, l, bal, 0.0)
			gs.loans.erase(l)
			gs.notify("Pagaste por completo tu préstamo de %s." % Fmt.money(float(l["principal"])), "importante")
			return ""
	return "Préstamo no encontrado"


static func player_loans(gs) -> Array:
	return gs.loans.filter(func(l): return str(l["borrower"]) == "jugador")


# --- Tu banco ----------------------------------------------------------------------------------

static func is_bank(b: Dictionary) -> bool:
	return str(GameData.building_def(str(b.get("type", ""))).get("product", "")) == "credito"


static func bank_settings(gs, b: Dictionary) -> void:
	if not b.has("loan_rate"):
		b["loan_rate"] = 0.10
		b["lending"] = true
		b["max_loan"] = 300.0 * gs.price_level()


static func bank_capacity(gs, b: Dictionary) -> int:
	var n := 0
	for c in gs.employees_of(int(b["id"])):
		if c.job_kind == "empleo":
			n += 1
	return n * int(gs.level_def(b).get("loans_per_worker", 10))


static func bank_loans(gs, b: Dictionary) -> Array:
	var id := str(int(b["id"]))
	return gs.loans.filter(func(l): return str(l["lender"]) == id)


static func citizen_loan(gs, cid: int) -> Dictionary:
	for l in gs.loans:
		if str(l["borrower"]) == str(cid):
			return l
	return {}


static func _daily_need_cost(gs) -> float:
	var total := 0.0
	for n in GameData.citizens.get("needs", {}).values():
		total += float(n.get("cost", 0.1))
	return total * gs.price_mult()


## Solicitudes de crédito de los ciudadanos a tus bancos (mensual).
static func _citizen_requests(gs) -> void:
	var banks := []
	for b in gs.buildings:
		if gs.owned_by_player(b) and is_bank(b) and b["status"] == "activo":
			bank_settings(gs, b)
			if bool(b["lending"]) and bank_loans(gs, b).size() < bank_capacity(gs, b):
				banks.append(b)
	if banks.is_empty():
		return
	banks.sort_custom(func(a, c): return float(a["loan_rate"]) < float(c["loan_rate"]))
	var cc := cit_cfg()
	var today: int = gs.today()
	var adult := int(GameData.citizens.get("adult_age", 16))
	var bans: Dictionary = gs.economy.get("credit_bans", {})
	var need_day := _daily_need_cost(gs)
	var granted := 0
	var granted_amount := 0.0
	var ids: Array = gs.citizens.keys()
	for id in ids:
		var c: Citizen = gs.citizens[id]
		if gs.is_player(c.id) or c.age_years(today) < adult or not citizen_loan(gs, c.id).is_empty():
			continue
		if int(bans.get(str(c.id), -1)) > today or CreditSim.score(gs, str(c.id)) < 450.0:
			continue   # Historial crediticio malo: tu banco no le presta.
		var bank: Dictionary = {}
		for b in banks:
			if bank_loans(gs, b).size() < bank_capacity(gs, b):
				bank = b
				break
		if bank.is_empty():
			break
		var rate := float(bank["loan_rate"])
		var p := float(cc.get("monthly_request_chance", 0.25)) * clampf(1.0 - (rate - float(cc.get("base_rate_reference", 0.08))) / float(cc.get("rate_sensitivity", 0.25)), 0.05, 1.5)
		var amount := 0.0
		var months := int(cc.get("consumer_term", 12))
		var purpose := ""
		# Vivienda en venta que casi puede pagar.
		for h in gs.buildings:
			if bool(h.get("for_sale", false)) and gs.owned_by_player(h):
				var price := float(h["sale_price"])
				if c.money >= price * 0.2 and c.money < price * 1.1:
					amount = price * 1.1 - c.money
					months = int(cc.get("housing_term", 60))
					purpose = "vivienda"
					break
		if purpose == "" and c.money < need_day * float(cc.get("consumer_days", 30)):
			amount = need_day * float(cc.get("consumer_days", 30))
			purpose = "consumo"
		if purpose == "" or gs.rng.randf() > p:
			continue
		amount = minf(amount, float(bank["max_loan"]))
		# Solo quien tiene salario puede pagar un préstamo.
		var income: float = c.wage if c.job_kind == "empleo" else 0.0
		if income <= 0.0:
			continue
		var pay := payment(amount, rate, months)
		if pay > income * 30.0 * float(cc.get("max_payment_income_ratio", 0.5)):
			continue
		if gs.money < amount:
			break  # Tu banco no tiene capital.
		var l := _new_loan(gs, str(int(bank["id"])), str(c.id), amount, rate, months, purpose)
		gs.add_money(-amount)
		BusinessSim.ledger_add(bank, "prestado", amount)
		c.money += amount
		c.debt = float(l["balance"])
		granted += 1
		granted_amount += amount
	if granted > 0:
		gs.notify("Tu banco otorgó %d préstamo(s) por %s." % [granted, Fmt.money(granted_amount)], "negocio")


# --- Ciclo mensual ----------------------------------------------------------------------------

static func monthly(gs) -> void:
	var penalty_rate := float(ext_cfg().get("late_penalty", 0.05))
	var player_default := int(ext_cfg().get("default_missed", 3))
	var cit_default := int(cit_cfg().get("default_missed", 3))
	for l in gs.loans.duplicate():
		var bal := float(l["balance"])
		var r := float(l["rate"]) / 12.0
		var interest := bal * r
		var due := LoanContract.due(l, bal, interest)   # Bienes raíces: tipo de pago firmado.
		if int(l.get("grace_until", -1)) > gs.today():
			due = interest   # Periodo de gracia negociado: solo intereses.
		var borrower := str(l["borrower"])
		var paid := false
		if borrower == "jugador":
			if gs.money >= due:
				gs.add_money(-due)
				gs.add_counter("interest_paid", interest)
				LoanContract.on_player_paid(gs, l, due, interest)
				paid = true
		else:
			var c: Citizen = gs.citizens.get(int(borrower))
			if c == null:
				_default(gs, l, "")  # murió o emigró
				continue
			var payers: Array = [c]
			if c.spouse_id >= 0 and gs.citizens.has(c.spouse_id):
				payers.append(gs.citizens[c.spouse_id])
			if PopulationSim.pay_with(gs, payers, due):
				paid = true
				var bank: Dictionary = gs.get_building(int(l["lender"]))
				if not bank.is_empty():
					BusinessSim.earn(gs, bank, interest, "intereses")
					gs.add_counter("interest_earned", interest)
					var principal_back := due - interest
					if BusinessSim.is_nonprofit(bank):
						bank["reserve"] = float(bank["reserve"]) + principal_back
					else:
						gs.add_money(principal_back)   # Capital devuelto: queda registrado en tus finanzas.
				else:
					FlowSim.bank_move(gs, due)   # Hipoteca o crédito de un banco externo/NPC.
		var who := borrower
		if paid:
			l["balance"] = maxf(0.0, bal + interest - due)
			l["months_paid"] = int(l["months_paid"]) + 1
			l["missed"] = 0
			CreditSim.adjust(gs, who, 4.0, "cuota al día")
		else:
			l["missed"] = int(l["missed"]) + 1
			l["balance"] = bal + interest + due * penalty_rate
			CreditSim.adjust(gs, who, -35.0, "cuota impaga (mora)")
			if borrower == "jugador":
				gs.player["credit_marks"] = int(gs.player.get("credit_marks", 0)) + 1
				gs.notify("MORA: no pudiste pagar la cuota de tu préstamo (%d/%d). Recargo aplicado. Puedes negociar (plazo, rebaja, dación o gracia) en Finanzas." % [int(l["missed"]), player_default], "jugador")
				if int(l["missed"]) >= player_default:
					_player_default(gs, l)
					continue
			else:
				if int(l["missed"]) >= cit_default - 1 and CreditSim.npc_try_negotiate(gs, l):
					continue   # El vecino negoció con el banco antes de caer en incumplimiento.
				if int(l["missed"]) >= cit_default:
					CreditSim.adjust(gs, who, -120.0, "incumplimiento")
					_default(gs, l, borrower)
					continue
		if float(l["balance"]) <= 0.01 and not LoanContract.keep_open(l):
			gs.loans.erase(l)
			if borrower == "jugador":
				gs.notify("Terminaste de pagar tu préstamo de %s." % Fmt.money(float(l["principal"])), "importante")
	# Deuda de cada ciudadano.
	for c in gs.citizens.values():
		c.debt = 0.0
	for l in gs.loans:
		if str(l["borrower"]) != "jugador" and gs.citizens.has(int(l["borrower"])):
			gs.citizens[int(l["borrower"])].debt += float(l["balance"])
	CreditSim.monthly_overdraft(gs)   # Sobregiro: interés, aviso, embargo por liquidez y bancarrota.
	_citizen_requests(gs)


static func _default(gs, l: Dictionary, borrower: String) -> void:
	RealEstateSim.on_loan_default(gs, l, borrower)   # Hipoteca: embargo de la unidad.
	var bank: Dictionary = gs.get_building(int(l["lender"]))
	if not bank.is_empty():
		BusinessSim.ledger_add(bank, "incobrables", float(l["balance"]))
	gs.loans.erase(l)
	gs.count("loan_defaults")
	if borrower != "" and gs.citizens.has(int(borrower)):
		var c: Citizen = gs.citizens[int(borrower)]
		c.happiness = maxf(0.0, c.happiness - float(cit_cfg().get("default_happiness_penalty", 15)))
		var bans: Dictionary = gs.economy.get("credit_bans", {})
		bans[str(c.id)] = gs.today() + int(cit_cfg().get("default_ban_months", 24)) * 30
		gs.economy["credit_bans"] = bans
		gs.notify("%s no pagó su préstamo: pérdida de %s para tu banco." % [c.full_name(), Fmt.money(float(l["balance"]))], "negocio")


## Incumplimiento del jugador (mora prolongada sin acuerdo): último recurso. Embargo por orden de
## liquidez hasta cubrir el saldo; lo que falte pasa a su saldo en rojo (sobregiro con el banco),
## que sigue el camino de CreditSim (bancarrota con rescate si no quedan bienes).
static func _player_default(gs, l: Dictionary) -> void:
	var bal := float(l["balance"])
	CreditSim.adjust(gs, "jugador", -120.0, "incumplimiento")
	var r := CreditSim.seize(gs, bal)
	var covered: float = minf(float(r["recovered"]), bal)
	var rest := bal - covered
	gs.loans.erase(l)
	if rest > 0.0:
		gs.add_money(-rest)
		lender_receive(gs, l, rest, 0.0)
	gs.notify("EMBARGO por incumplimiento: el banco se quedó con %s%s." % [", ".join(r["labels"]) if not r["labels"].is_empty() else "ningún bien",
		" y el resto (%s) pasa a tu saldo en rojo" % Fmt.money(rest) if rest > 0.0 else ""], "jugador")


## El prestamista recibe un pago: tu banco (reserva o tu dinero) o la caja de los bancos externos/NPC.
## money=false: pago en especie (dación): solo se registra, no se mueve dinero.
static func lender_receive(gs, l: Dictionary, amount: float, interest: float, money := true) -> void:
	var bank := LoanContract._own_bank(gs, str(l.get("lender", "")))
	if bank.is_empty():
		if money:
			FlowSim.bank_move(gs, amount)
		return
	if interest > 0.0:
		BusinessSim.ledger_add(bank, "intereses", interest)
	if not money:
		return
	if BusinessSim.is_nonprofit(bank):
		bank["reserve"] = float(bank.get("reserve", 0.0)) + amount
	elif str(l["borrower"]) != "jugador":
		gs.add_money(amount)


## Deuda perdonada o incobrable (rebaja negociada, castigo): el banco la pierde; no hay dinero.
static func writeoff(gs, l: Dictionary, amount: float) -> void:
	if amount <= 0.0:
		return
	var bank := LoanContract._own_bank(gs, str(l.get("lender", "")))
	if not bank.is_empty():
		BusinessSim.ledger_add(bank, "incobrables", amount)


## Herencia: las deudas del difunto se pagan primero con su dinero. Devuelve lo pagado.
static func settle_estate(gs, c: Citizen, available: float) -> float:
	var paid_total := 0.0
	for l in gs.loans.duplicate():
		if str(l["borrower"]) != str(c.id):
			continue
		var bal := float(l["balance"])
		var pay := minf(bal, available - paid_total)
		if pay > 0.0:
			lender_receive(gs, l, pay, 0.0)
			paid_total += pay
		writeoff(gs, l, bal - maxf(0.0, pay))
		gs.loans.erase(l)
	return paid_total
