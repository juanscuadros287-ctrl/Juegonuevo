class_name LoanContract
extends RefCounted
## Crédito bancario completo (extiende BankSim sin cambiar su API):
## - Bancos: el externo (Banco del Reino), bancos NPC de data/realestate.json y tus bancos
##   (solo fundaciones con reserva: un banco S.A.S. no puede prestarle a su dueño).
## - Tasa = tasa base de la dificultad + ajuste de la época + margen del banco + riesgo del cliente.
## - Tipos de pago: francés (cuota fija), alemán (abono constante a capital), bullet (solo
##   intereses y capital al final) y con período de gracia de N meses.
## - Tabla de amortización antes de firmar, cobro mensual de lo firmado (BankSim.monthly llama
##   a `due`), pagos anticipados y crédito constructor (desembolsos por etapas).
## Los préstamos viejos (sin "type") siguen con la cuota fija guardada, como antes.

const TYPES := ["frances", "aleman", "bullet", "gracia"]


static func cfg() -> Dictionary:
	return GameData.extra("realestate")


static func type_label(t: String) -> String:
	if t == "constructor":
		return "Crédito constructor"
	return str(cfg().get("loan_types", {}).get(t, {}).get("label", "Cuota fija (francés)"))


static func type_desc(t: String) -> String:
	return str(cfg().get("loan_types", {}).get(t, {}).get("desc", ""))


static func era_rate_add(gs) -> float:
	return float(cfg().get("era_rate_add", {}).get(str(gs.era()), 0.0)) + GlobalEconSim.credit_rate_add(gs)   # Ciclo económico.


# --- Tabla de amortización ------------------------------------------------------------------

## Filas: {n, payment, interest, principal, balance}. La suma de capital = monto.
static func schedule(amount: float, rate: float, months: int, type: String, grace := 0) -> Array:
	var rows := []
	months = maxi(1, months)
	grace = clampi(grace, 0, months - 1) if type == "gracia" else 0
	var r := rate / 12.0
	var bal := amount
	var fixed := BankSim.payment(amount, rate, months)
	var german := amount / months
	for n in range(1, months + 1):
		var interest := bal * r
		var principal := 0.0
		match type:
			"aleman":
				principal = german
			"bullet":
				principal = 0.0
			"gracia":
				if n <= grace:
					principal = 0.0
				else:
					principal = BankSim.payment(bal, rate, months - n + 1) - interest
			_:
				principal = fixed - interest
		if n == months:
			principal = bal
		principal = clampf(principal, 0.0, bal)
		bal -= principal
		rows.append({"n": n, "payment": principal + interest, "interest": interest, "principal": principal, "balance": maxf(0.0, bal)})
	return rows


static func schedule_totals(rows: Array) -> Dictionary:
	var t := {"payment": 0.0, "interest": 0.0, "principal": 0.0, "first": 0.0, "max": 0.0}
	for row in rows:
		t["payment"] += float(row["payment"])
		t["interest"] += float(row["interest"])
		t["principal"] += float(row["principal"])
		t["max"] = maxf(float(t["max"]), float(row["payment"]))
	if not rows.is_empty():
		t["first"] = float(rows[0]["payment"])
	return t


## Cuota que corresponde este mes a un préstamo (la usa BankSim.monthly).
static func due(l: Dictionary, bal: float, interest: float) -> float:
	var t := str(l.get("type", ""))
	var n := int(l.get("months_paid", 0))
	var term := maxi(1, int(l.get("term_months", 12)))
	var rate := float(l.get("rate", 0.0))
	var out := 0.0
	match t:
		"":
			return minf(float(l["payment"]), bal + interest)   # Préstamos anteriores: igual que antes.
		"aleman":
			out = interest + float(l["principal"]) / term
		"bullet":
			out = interest
		"constructor":
			out = interest
			if GameState.today() >= int(l.get("maturity_day", 0)):
				out = bal + interest
		"gracia":
			if n < int(l.get("grace", 0)):
				out = interest
			else:
				out = BankSim.payment(bal, rate, maxi(1, term - n))
		_:
			out = BankSim.payment(bal, rate, maxi(1, term - n))
	if n >= term - 1 and t != "constructor":
		out = bal + interest   # Última cuota: cancela el saldo.
	out = minf(out, bal + interest)
	l["payment"] = out
	return out


## Préstamo abierto aunque su saldo sea 0 (crédito constructor con cupo por desembolsar).
static func keep_open(l: Dictionary) -> bool:
	return str(l.get("type", "")) == "constructor" and not bool(l.get("closed", false))


# --- Bancos y tasas -------------------------------------------------------------------------

## Opciones de banco para el jugador: [{id, label, rate, limit, reason, desc}].
static func lenders(gs) -> Array:
	var out := []
	var base := BankSim.player_rate(gs) + era_rate_add(gs)
	var lim := BankSim.credit_limit(gs)
	out.append({"id": BankSim.EXTERNAL, "label": str(BankSim.ext_cfg().get("label", "Banco del Reino")),
		"rate": base, "limit": lim, "reason": "" if lim > 0.0 else "Sin cupo de crédito", "desc": "Banco externo del reino."})
	for bk in cfg().get("banks", []):
		var d: Dictionary = bk
		var reason := ""
		if gs.era() < int(d.get("min_era", 1)):
			reason = "Aún no existe en esta época"
		var l2 := lim * float(d.get("limit_mult", 1.0))
		if l2 <= 0.0 and reason == "":
			reason = "Sin cupo de crédito"
		out.append({"id": str(d["id"]), "label": str(d.get("label", d["id"])), "rate": maxf(0.005, base + float(d.get("spread", 0.0))),
			"limit": l2, "reason": reason, "desc": str(d.get("desc", ""))})
	for b in gs.buildings:
		if gs.owned_by_player(b) and BankSim.is_bank(b) and b["status"] == "activo":
			BankSim.bank_settings(gs, b)
			var reason := ""
			var cap := 0.0
			if not BusinessSim.is_nonprofit(b):
				reason = "Autopréstamo prohibido: un banco S.A.S. no presta a su dueño"
			else:
				cap = float(b.get("reserve", 0.0))
				if cap <= 0.0:
					reason = "La reserva de la fundación está vacía"
			out.append({"id": str(int(b["id"])), "label": "Tu banco: " + gs.building_label(b), "rate": float(b["loan_rate"]),
				"limit": cap, "reason": reason, "desc": "Presta desde la reserva de tu fundación; los intereses vuelven a ella."})
	return out


static func lender(gs, id: String) -> Dictionary:
	for l in lenders(gs):
		if str(l["id"]) == id:
			return l
	return {}


static func lender_label(gs, id: String) -> String:
	if id == BankSim.EXTERNAL:
		return str(BankSim.ext_cfg().get("label", "Banco del Reino"))
	for bk in cfg().get("banks", []):
		if str(bk["id"]) == id:
			return str(bk.get("label", id))
	if id.is_valid_int():
		var b: Dictionary = gs.get_building(int(id))
		if not b.is_empty():
			return gs.building_label(b)
	return id


static func _own_bank(gs, lender_id: String) -> Dictionary:
	if not lender_id.is_valid_int():
		return {}
	var b: Dictionary = gs.get_building(int(lender_id))
	if b.is_empty() or not gs.owned_by_player(b) or not BankSim.is_bank(b):
		return {}
	return b


# --- Contratos del jugador ------------------------------------------------------------------

## Contrato sin firmar: tasa, tabla y totales (para mostrar antes de "Firmar").
static func quote(gs, lender_id: String, amount: float, months: int, type: String, grace := 0) -> Dictionary:
	var ld := lender(gs, lender_id)
	if ld.is_empty():
		return {"error": "Banco no disponible"}
	var rows := schedule(amount, float(ld["rate"]), months, type, grace)
	var err := str(ld["reason"])
	if err == "" and amount > float(ld["limit"]):
		err = "%s solo te presta hasta %s" % [ld["label"], Fmt.money(float(ld["limit"]))]
	if err == "" and amount <= 0.0:
		err = "Monto inválido"
	return {"lender": lender_id, "label": ld["label"], "rate": float(ld["rate"]), "amount": amount, "months": months,
		"type": type, "grace": grace, "rows": rows, "totals": schedule_totals(rows), "error": err}


## Firma el contrato: el dinero entra hoy y cada mes se cobra la cuota según el tipo.
static func sign_player_loan(gs, lender_id: String, amount: float, months: int, type: String, grace := 0, purpose := "empresario") -> Dictionary:
	amount = snappedf(amount, 1.0)
	var q := quote(gs, lender_id, amount, months, type, grace)
	if str(q.get("error", "")) != "":
		return {"error": q["error"]}
	var l := BankSim._new_loan(gs, lender_id, "jugador", amount, float(q["rate"]), months, purpose)
	l["type"] = type if TYPES.has(type) else "frances"
	l["grace"] = grace if type == "gracia" else 0
	l["payment"] = float(q["rows"][0]["payment"])
	var own := _own_bank(gs, lender_id)
	if not own.is_empty():
		own["reserve"] = float(own["reserve"]) - amount
		BusinessSim.ledger_add(own, "prestado", amount)
	gs.add_money(amount)
	gs.notify("Firmaste con %s: %s al %.1f%% anual a %d meses, %s (primera cuota %s)." % [q["label"], Fmt.money(amount), float(q["rate"]) * 100.0, months, type_label(type).to_lower(), Fmt.money(float(l["payment"]))], "importante")
	return {"loan": l}


## Pago anticipado: abona a capital (la cuota se recalcula con el plazo restante).
static func prepay(gs, loan_id: int, amount: float) -> String:
	for l in gs.loans:
		if int(l["id"]) != loan_id or str(l["borrower"]) != "jugador":
			continue
		var bal := float(l["balance"])
		amount = minf(snappedf(amount, 0.01), bal)
		if amount <= 0.0:
			return "Monto inválido"
		if gs.money < amount:
			return "Necesitas %s" % Fmt.money(amount)
		gs.add_money(-amount)
		l["balance"] = bal - amount
		on_player_paid(gs, l, amount, 0.0)
		if float(l["balance"]) <= 0.01 and not keep_open(l):
			gs.loans.erase(l)
			gs.notify("Pagaste por completo tu crédito de %s." % Fmt.money(float(l["principal"])), "importante")
		else:
			var r := float(l["rate"]) / 12.0
			due(l, float(l["balance"]), float(l["balance"]) * r)
			gs.notify("Abono anticipado de %s. Nuevo saldo: %s." % [Fmt.money(amount), Fmt.money(float(l["balance"]))], "importante")
		return ""
	return "Préstamo no encontrado"


## Tabla restante de un préstamo ya firmado (desde el saldo actual).
static func remaining_schedule(l: Dictionary) -> Array:
	var t := str(l.get("type", ""))
	var left := maxi(1, int(l.get("term_months", 12)) - int(l.get("months_paid", 0)))
	if t == "" or t == "constructor":
		t = "frances" if t == "" else "bullet"
	var grace := maxi(0, int(l.get("grace", 0)) - int(l.get("months_paid", 0)))
	return schedule(float(l["balance"]), float(l["rate"]), left, t, grace)


## Si el prestamista es tu banco (fundación), lo pagado vuelve a su reserva y los intereses son ingreso.
static func on_player_paid(gs, l: Dictionary, paid: float, interest: float) -> void:
	var own := _own_bank(gs, str(l.get("lender", "")))
	if own.is_empty():
		return
	own["reserve"] = float(own["reserve"]) + paid
	if interest > 0.0:
		BusinessSim.ledger_add(own, "intereses", interest)


# --- Crédito constructor --------------------------------------------------------------------

static func open_constructor_credit(gs, lender_id: String, limit: float, months: int, project_id: int) -> Dictionary:
	var ld := lender(gs, lender_id)
	if ld.is_empty():
		return {"error": "Banco no disponible"}
	if str(ld["reason"]) != "":
		return {"error": ld["reason"]}
	if limit > float(ld["limit"]):
		return {"error": "%s solo aprueba hasta %s" % [ld["label"], Fmt.money(float(ld["limit"]))]}
	var rate := maxf(0.005, float(ld["rate"]) + float(cfg().get("constructor_credit", {}).get("spread", 0.0)))
	var l := BankSim._new_loan(gs, lender_id, "jugador", 0.0, rate, months, "constructor")
	l["principal"] = 0.0
	l["balance"] = 0.0
	l["payment"] = 0.0
	l["type"] = "constructor"
	l["limit"] = limit
	l["disbursed"] = 0.0
	l["project_id"] = project_id
	l["maturity_day"] = gs.today() + months * 30
	gs.notify("%s aprobó un crédito constructor de hasta %s al %.1f%% (intereses solo sobre lo desembolsado)." % [ld["label"], Fmt.money(limit), rate * 100.0], "importante")
	return {"loan": l}


static func find_loan(gs, loan_id: int) -> Dictionary:
	for l in gs.loans:
		if int(l["id"]) == loan_id:
			return l
	return {}


## Desembolsa hasta `amount` del cupo; devuelve lo desembolsado.
static func disburse(gs, l: Dictionary, amount: float) -> float:
	if l.is_empty() or bool(l.get("closed", false)):
		return 0.0
	var avail := maxf(0.0, float(l["limit"]) - float(l["disbursed"]))
	var take := minf(avail, amount)
	if take <= 0.0:
		return 0.0
	var own := _own_bank(gs, str(l["lender"]))
	if not own.is_empty():
		if float(own.get("reserve", 0.0)) < take:
			return 0.0
		own["reserve"] = float(own["reserve"]) - take
	l["disbursed"] = float(l["disbursed"]) + take
	l["principal"] = float(l["principal"]) + take
	l["balance"] = float(l["balance"]) + take
	gs.add_money(take)
	return take


## Abono al crédito constructor con el dinero de una venta.
static func sweep(gs, l: Dictionary, amount: float) -> float:
	if l.is_empty():
		return 0.0
	var pay := minf(amount, float(l["balance"]))
	if pay <= 0.0:
		return 0.0
	gs.add_money(-pay)
	l["balance"] = float(l["balance"]) - pay
	on_player_paid(gs, l, pay, 0.0)
	return pay


## Cierra el cupo (obra terminada o cancelada): ya no desembolsa y se borra al quedar en 0.
static func close_credit(gs, l: Dictionary) -> void:
	if l.is_empty():
		return
	l["closed"] = true
	if float(l["balance"]) <= 0.01:
		gs.loans.erase(l)


# --- Hipotecas para ciudadanos --------------------------------------------------------------

static func mortgage_cfg() -> Dictionary:
	return cfg().get("mortgage", {})


static func mortgage_term(gs) -> int:
	return int(mortgage_cfg().get("term_months_by_era", {}).get(str(gs.era()), 180))


static func external_citizen_rate(gs) -> float:
	return float(gs.diff().get("bank_interest", 0.07)) + era_rate_add(gs) + float(mortgage_cfg().get("external_spread", 0.03))


## Mejor oferta de hipoteca: primero tus bancos (si otorgan hipotecas, tienen cupo y capital),
## si no el banco externo. Devuelve {lender, rate, months, payment} o {} si no califica.
static func mortgage_offer(gs, amount: float, monthly_income: float) -> Dictionary:
	var months := mortgage_term(gs)
	var max_ratio := float(mortgage_cfg().get("max_payment_income_ratio", 0.35))
	var best := {}
	for b in gs.buildings:
		if not gs.owned_by_player(b) or not BankSim.is_bank(b) or b["status"] != "activo":
			continue
		BankSim.bank_settings(gs, b)
		if not bool(b.get("mortgages", true)) or not bool(b.get("lending", true)):
			continue
		if BankSim.bank_loans(gs, b).size() >= BankSim.bank_capacity(gs, b):
			continue
		var capital: float = float(b.get("reserve", 0.0)) if BusinessSim.is_nonprofit(b) else gs.money
		if capital < amount:
			continue
		var rate := float(b.get("mortgage_rate", b["loan_rate"]))
		var pay := BankSim.payment(amount, rate, months)
		if pay > monthly_income * max_ratio:
			continue
		if best.is_empty() or rate < float(best["rate"]):
			best = {"lender": str(int(b["id"])), "rate": rate, "months": months, "payment": pay}
	if not best.is_empty():
		return best
	var er := external_citizen_rate(gs)
	var ep := BankSim.payment(amount, er, months)
	if ep > monthly_income * max_ratio:
		return {}
	return {"lender": BankSim.EXTERNAL, "rate": er, "months": months, "payment": ep}


## Otorga la hipoteca: el dinero va del banco al comprador (que paga de inmediato al vendedor).
static func grant_mortgage(gs, offer: Dictionary, borrower: Citizen, amount: float, unit_ref: String) -> Dictionary:
	var lender_id := str(offer["lender"])
	var l := BankSim._new_loan(gs, lender_id, str(borrower.id), amount, float(offer["rate"]), int(offer["months"]), "hipoteca")
	l["type"] = "frances"
	l["unit_ref"] = unit_ref
	var bank := _own_bank(gs, lender_id)
	if not bank.is_empty():
		if BusinessSim.is_nonprofit(bank):
			bank["reserve"] = float(bank["reserve"]) - amount
		else:
			gs.add_money(-amount)
		BusinessSim.ledger_add(bank, "prestado", amount)
	borrower.money += amount
	borrower.debt += amount
	return l
