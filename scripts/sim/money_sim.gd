class_name MoneySim
extends RefCounted
## Sección E — impuesto a la venta (alcabala / impuesto a las ventas / IVA según la época),
## dinero del jugador en EFECTIVO y en BANCO, ventas sin declarar con gente de confianza,
## sueldos en negro, negocios ocultos del mercado negro, riesgo, inspecciones, hallazgos y soborno.
## Ver docs/EFECTIVO_MERCADO_NEGRO.md. Parámetros en data/mercado_negro.json.
##
## Modelo del dinero: gs.money sigue siendo el TOTAL del jugador (nada existente cambia).
## gs.cash es la parte en efectivo; el banco es gs.money - gs.cash. Todo lo que ya existía
## (impuestos, créditos, empresas formales, gobierno) se mueve por el banco a través de
## gs.add_money(). El efectivo solo entra por ventas no declaradas, retiros y negocios ocultos,
## y sale por pagos a quien acepta efectivo (sueldos en negro, jornaleros y proveedores
## informales, sobornos) o por depósitos. Si el banco queda en rojo, el efectivo lo cubre
## (cuenta como depósito).
## Economía cerrada: IVA, multas y decomisos van al tesoro; sobornos a un funcionario; sueldos,
## insumos informales y montaje de negocios ocultos a ciudadanos; solo la mercancía de
## contrabando se paga afuera (como una importación).
## Estado en GameState.informal (ver init_state) y GameState.cash.

const MAX_LOG := 40


static func cfg() -> Dictionary:
	return GameData.extra("mercado_negro")


static func init_state(gs) -> void:
	var s: Dictionary = gs.informal
	var defaults := {"risk": 0.0, "log": [], "hidden": [], "next_hidden_id": 1, "iva_due": 0.0,
		"deposited_month": 0.0, "case": {}, "offenses": 0, "month": {}, "last_month": {}, "totals": {},
		"trusted": 0, "trusted_day": -1, "rng_state": "", "idle_warned": {}}
	for k in defaults:
		if not s.has(k):
			s[k] = defaults[k]
	if str(s["rng_state"]) == "":
		s["rng_state"] = str(int(gs.settings.get("seed", 1)) * 7919 + 17)
	gs.informal = s
	gs.cash = maxf(0.0, float(gs.cash))


static func st(gs) -> Dictionary:
	if gs.informal.is_empty():
		init_state(gs)
	return gs.informal


# --- Aleatoriedad propia (no altera la secuencia de gs.rng) ----------------------------------------

static func rf(gs) -> float:
	var r := RandomNumberGenerator.new()
	r.state = int(str(st(gs).get("rng_state", "1")))
	var v := r.randf()
	st(gs)["rng_state"] = str(r.state)
	return v


static func _roll(gs, roll: float) -> float:
	return roll if roll >= 0.0 else rf(gs)


# --- Registro y estadísticas -----------------------------------------------------------------------

static func _log(gs, text: String, category := "jugador") -> void:
	var l: Array = st(gs)["log"]
	l.append({"day": gs.today(), "date": TimeManager.date_string(false), "text": text})
	while l.size() > MAX_LOG:
		l.pop_front()
	if category != "":
		gs.notify(text, category)


static func _stat(gs, key: String, amount: float) -> void:
	var m: Dictionary = st(gs)["month"]
	m[key] = float(m.get(key, 0.0)) + amount
	var t: Dictionary = st(gs)["totals"]
	t[key] = float(t.get(key, 0.0)) + amount


static func stat(gs, period: String, key: String) -> float:
	return float(st(gs).get(period, {}).get(key, 0.0))


# --- Efectivo y banco --------------------------------------------------------------------------------

static func cash(gs) -> float:
	return float(gs.cash)


static func bank(gs) -> float:
	return float(gs.money) - float(gs.cash)


## Ingreso en efectivo (sube el total y el efectivo).
static func _earn_cash(gs, amount: float) -> void:
	if amount <= 0.0:
		return
	gs.add_money(amount)
	gs.cash = float(gs.cash) + amount


## Paga en efectivo a quien lo acepta. false si no alcanza (no paga nada).
static func pay_cash(gs, amount: float) -> bool:
	if amount <= 0.0:
		return true
	if float(gs.cash) + 0.0001 < amount:
		return false
	gs.cash = maxf(0.0, float(gs.cash) - amount)
	gs.add_money(-amount)
	return true


## Paga lo que alcance del total (>= 0), primero de la fuente preferida. Devuelve lo pagado.
static func _take(gs, amount: float, cash_first: bool) -> float:
	var paid := clampf(amount, 0.0, maxf(0.0, float(gs.money)))
	if paid <= 0.0:
		return 0.0
	var from_cash: float
	if cash_first:
		from_cash = minf(paid, float(gs.cash))
	else:
		from_cash = clampf(paid - maxf(0.0, bank(gs)), 0.0, float(gs.cash))
	gs.cash = maxf(0.0, float(gs.cash) - from_cash)
	gs.add_money(-paid)
	return paid


## Margen de depósito del mes sin levantar sospechas: libre + parte de las ventas de tus negocios legales.
static func deposit_allowance(gs) -> float:
	var dc: Dictionary = cfg().get("deposit", {})
	var share := float(dc.get("launder_share", 0.25))
	if gs.has_tech(str(dc.get("launder_tech", "contabilidad_paralela"))):
		share = float(dc.get("launder_share_tech", 0.5))
	var legal := 0.0
	for b in gs.buildings:
		if gs.owned_by_player(b) and BusinessSim.is_business(b) and not BusinessSim.is_nonprofit(b):
			legal += BusinessSim.period_value(b, "last_month", "ventas")
	var total: float = float(dc.get("free_monthly", 200)) * gs.price_mult() + legal * share
	return maxf(0.0, total - float(st(gs).get("deposited_month", 0.0)))


static func deposit(gs, amount: float) -> String:
	amount = minf(amount, float(gs.cash))
	if amount <= 0.0:
		return "No tienes efectivo para depositar."
	var allowance := deposit_allowance(gs)
	gs.cash = maxf(0.0, float(gs.cash) - amount)
	_register_deposit(gs, amount, allowance, "Depositaste %s en el banco." % Fmt.money(amount))
	return ""


static func _register_deposit(gs, amount: float, allowance: float, text: String) -> void:
	st(gs)["deposited_month"] = float(st(gs).get("deposited_month", 0.0)) + amount
	_stat(gs, "deposits", amount)
	var excess := maxf(0.0, amount - allowance)
	if excess > 0.0:
		var r: float = excess / (1000.0 * gs.price_mult()) * float(cfg().get("deposit", {}).get("risk_per_1000_excess", 10.0))
		add_risk(gs, r)
		_log(gs, "%s El banco reporta un depósito grande en efectivo (%s sin justificar): sube el riesgo (+%.1f)." % [text, Fmt.money(excess), r])
	else:
		_log(gs, text, "")


static func withdraw(gs, amount: float) -> String:
	if amount <= 0.0:
		return "Monto inválido."
	if bank(gs) + 0.0001 < amount:
		return "Saldo en banco insuficiente (%s)." % Fmt.money(maxf(0.0, bank(gs)))
	gs.cash = float(gs.cash) + amount
	_stat(gs, "withdrawals", amount)
	_log(gs, "Retiraste %s del banco en efectivo." % Fmt.money(amount), "")
	return ""


# --- Impuesto a la venta ---------------------------------------------------------------------------------

static func sales_tax_rate(gs) -> float:
	var sc: Dictionary = cfg().get("sales_tax", {})
	var era := str(gs.era())
	var p := GovSim.policy(gs)
	var r: float
	if p.has("sales_tax"):
		r = float(p["sales_tax"])
	else:
		r = float(sc.get("by_gov", {}).get(str(gs.government.get("gov_id", "")), sc.get("by_era", {}).get(era, 0.02)))
	return maxf(0.0, r * float(sc.get("era_mult", {}).get(era, 1.0)))


static func sales_tax_label(gs) -> String:
	return str(cfg().get("sales_tax", {}).get("labels", {}).get(str(gs.era()), "IVA"))


## Llamado por BusinessSim.earn en cada venta de un negocio tuyo. Separa la parte no declarada
## (se cobra en efectivo, sin IVA) y causa el IVA de la parte declarada. Devuelve lo declarado.
static func on_sale(gs, b: Dictionary, amount: float) -> float:
	if amount <= 0.0 or not gs.owned_by_player(b) or not BusinessSim.is_business(b) or BusinessSim.is_nonprofit(b):
		return amount
	var undeclared := 0.0
	if bool(b.get("undeclared", false)):
		undeclared = amount * undeclared_share(gs)
		if undeclared > 0.0:
			_earn_cash(gs, undeclared)
			_cash_ledger(b, "ventas_efectivo", undeclared)
			_stat(gs, "undeclared", undeclared)
			add_risk(gs, undeclared / (1000.0 * gs.price_mult()) * float(cfg().get("undeclared", {}).get("risk_per_1000", 4.0)))
	var declared := amount - undeclared
	var rate := sales_tax_rate(gs)
	if declared > 0.0 and rate > 0.0:
		b["iva_due"] = float(b.get("iva_due", 0.0)) + declared * rate
	return declared


## Cobro de un contrato de venta (ContractSim._collect, el dinero ya entró al total).
static func on_contract_income(gs, k: Dictionary, paid: float) -> void:
	if paid <= 0.0:
		return
	if bool(k.get("undeclared", false)):
		gs.cash = float(gs.cash) + paid
		_stat(gs, "undeclared", paid)
		add_risk(gs, paid / (1000.0 * gs.price_mult()) * float(cfg().get("undeclared", {}).get("risk_per_1000", 4.0)))
		return
	st(gs)["iva_due"] = float(st(gs).get("iva_due", 0.0)) + paid * sales_tax_rate(gs)


## Paga al tesoro el IVA causado del mes (llamado desde GovSim._collect_taxes).
static func collect_sales_tax(gs, totals: Dictionary) -> void:
	var total := 0.0
	for b in gs.buildings:
		var due := float(b.get("iva_due", 0.0))
		if due <= 0.0:
			continue
		b["iva_due"] = 0.0
		if gs.owned_by_player(b):
			BusinessSim.pay(gs, b, due, "iva")
			total += due
	var cdue := float(st(gs).get("iva_due", 0.0))
	if cdue > 0.0:
		st(gs)["iva_due"] = 0.0
		gs.add_money(-cdue)
		total += cdue
	totals["iva"] = total
	_stat(gs, "iva", total)


static func iva_pending(gs) -> float:
	var t := float(st(gs).get("iva_due", 0.0))
	for b in gs.buildings:
		t += float(b.get("iva_due", 0.0))
	return t


static func _cash_ledger(b: Dictionary, key: String, amount: float) -> void:
	var cl: Dictionary = b.get("cash_ledger", {})
	for period in ["month", "total"]:
		var p: Dictionary = cl.get(period, {})
		p[key] = float(p.get(key, 0.0)) + amount
		cl[period] = p
	b["cash_ledger"] = cl


# --- Confianza, ventas sin declarar y sueldos en negro -----------------------------------------------------

## Personas de confianza: familiares adultos y conocidos con relación alta.
static func trusted_count(gs) -> int:
	var s := st(gs)
	if int(s.get("trusted_day", -1)) == gs.today():
		return int(s.get("trusted", 0))
	var min_aff := float(cfg().get("undeclared", {}).get("trust_affinity", 55))
	var n := 0
	for k in gs.player.get("relations", {}):
		if float(gs.player["relations"][k]) >= min_aff and gs.citizens.has(int(k)):
			n += 1
	var adult := int(GameData.citizens.get("adult_age", 16))
	for c in HeirsSim.family_members(gs):
		if c.age_years(gs.today()) >= adult and PlayerSim.affinity(gs, c.id) < min_aff:
			n += 1
	s["trusted"] = n
	s["trusted_day"] = gs.today()
	return n


## Fracción de las ventas al público que se puede cobrar sin declarar.
static func undeclared_share(gs) -> float:
	var uc: Dictionary = cfg().get("undeclared", {})
	return minf(float(uc.get("max_share", 0.5)), trusted_count(gs) * float(uc.get("share_per_trusted", 0.05)))


static func set_undeclared(gs, b: Dictionary, on: bool) -> String:
	if not gs.owned_by_player(b) or not BusinessSim.is_business(b):
		return "Solo en tus negocios."
	if BusinessSim.is_nonprofit(b):
		return "Una fundación no puede vender sin declarar."
	if on and undeclared_share(gs) <= 0.0:
		return "No tienes personas de confianza (familia o relación ≥ %d): nadie te compra sin factura." % int(cfg().get("undeclared", {}).get("trust_affinity", 55))
	b["undeclared"] = on
	return ""


static func set_black_wages(gs, b: Dictionary, on: bool) -> String:
	if not gs.owned_by_player(b) or not BusinessSim.is_business(b):
		return "Solo en tus negocios."
	b["black_wages"] = on
	return ""


## Sueldo en negro: se paga en efectivo, con descuento y sin impuesto de nómina. false si no aplica
## (negocio sin la opción o sin efectivo): entonces se paga normal por el banco.
static func pay_wage_black(gs, b: Dictionary, c) -> bool:
	if not bool(b.get("black_wages", false)):
		return false
	var uc: Dictionary = cfg().get("undeclared", {})
	var w := float(c.wage) * (1.0 - float(uc.get("black_wage_discount", 0.15)))
	if not pay_cash(gs, w):
		return false
	c.money += w
	BusinessSim.ledger_add(b, "salarios_negro", w)
	_cash_ledger(b, "salarios_negro", w)
	_stat(gs, "black_wages", w)
	add_risk(gs, w / (1000.0 * gs.price_mult()) * float(uc.get("black_wage_risk_per_1000", 5.0)))
	return true


## "" si la contraparte acepta cobrar el contrato sin declarar.
static func contract_undeclared_block(gs, k: Dictionary) -> String:
	var key := str(k.get("client", ""))
	var kind := ContractSim.client_kind(key)
	if kind != "npc" and kind != "town":
		return "El gobierno y la importación solo operan con factura."
	if ContractSim.dir_of(k) != ContractSim.DIR_SELL:
		return "Solo en contratos de venta."
	var need := float(cfg().get("undeclared", {}).get("contract_min_reputation", 70))
	if ContractSim.reputation(gs, key) < need:
		return "%s no confía lo bastante en ti (reputación %d/%d)." % [ContractSim.client_name(gs, key), int(ContractSim.reputation(gs, key)), int(need)]
	return ""


static func set_contract_undeclared(gs, k: Dictionary, on: bool) -> String:
	if on:
		var why := contract_undeclared_block(gs, k)
		if why != "":
			return why
	k["undeclared"] = on
	return ""


# --- Riesgo ------------------------------------------------------------------------------------------------

static func risk(gs) -> float:
	return float(st(gs).get("risk", 0.0))


static func add_risk(gs, amount: float) -> void:
	st(gs)["risk"] = clampf(risk(gs) + amount, 0.0, float(cfg().get("risk", {}).get("max", 100)))


static func risk_label(gs) -> String:
	var r := risk(gs)
	if r < 10.0:
		return "bajo"
	if r < 30.0:
		return "moderado"
	if r < 60.0:
		return "alto"
	return "muy alto"


static func _gov_mult(gs) -> float:
	return float(cfg().get("inspection", {}).get("gov_mult", {}).get(str(gs.government.get("gov_id", "")), 1.0))


static func inspection_chance(gs) -> float:
	var ic: Dictionary = cfg().get("inspection", {})
	if risk(gs) < float(ic.get("min_risk", 5)):
		return 0.0
	var police := EventsSim.coverage(gs, "policia")
	var p := risk(gs) / 100.0 * (float(ic.get("base", 0.35)) + float(ic.get("police_weight", 0.5)) * police) * _gov_mult(gs)
	return clampf(p, 0.0, float(ic.get("max_chance", 0.7)))


static func find_chance(gs) -> float:
	var ic: Dictionary = cfg().get("inspection", {})
	var police := EventsSim.coverage(gs, "policia")
	return clampf(float(ic.get("find_base", 0.3)) + float(ic.get("find_risk", 0.5)) * risk(gs) / 100.0 + float(ic.get("find_police", 0.25)) * police, 0.0, 0.95)


## ¿Hay algo que encontrar? (efectivo, negocios ocultos u operaciones en curso)
static func has_exposure(gs) -> bool:
	if float(gs.cash) > 1.0 or not active_hidden(gs).is_empty():
		return true
	for b in gs.buildings:
		if gs.owned_by_player(b) and (bool(b.get("undeclared", false)) or bool(b.get("black_wages", false))):
			return true
	return false


## Inspección de la autoridad. roll_* < 0 = aleatorio. Devuelve el texto del resultado.
static func inspect(gs, roll_find := -1.0) -> String:
	if not case_of(gs).is_empty():
		return ""
	_stat(gs, "inspections", 1.0)
	if not has_exposure(gs) or _roll(gs, roll_find) >= find_chance(gs):
		st(gs)["risk"] = risk(gs) * float(cfg().get("inspection", {}).get("clean_risk_mult", 0.7))
		var t := "Inspección de la autoridad en tus negocios: no encontraron irregularidades."
		_log(gs, t)
		return t
	return _open_case(gs)


static func case_of(gs) -> Dictionary:
	return st(gs).get("case", {})


static func _open_case(gs) -> String:
	var cc: Dictionary = cfg().get("case", {})
	var pm: float = gs.price_mult()
	var r := risk(gs)
	var fine := (float(cc.get("fine_base", 150)) + float(cc.get("fine_per_risk", 10)) * r) * pm + stat(gs, "last_month", "undeclared") * float(cc.get("fine_undeclared_share", 0.3))
	var grave := r >= float(cc.get("grave_risk", 70)) or int(st(gs).get("offenses", 0)) + 1 >= int(cc.get("grave_repeat", 3))
	var found := []
	if float(gs.cash) > 1.0:
		found.append("efectivo sin declarar (%s)" % Fmt.money(gs.cash))
	var hidden := active_hidden(gs)
	if not hidden.is_empty():
		found.append("%d negocio(s) oculto(s)" % hidden.size())
	for b in gs.buildings:
		if gs.owned_by_player(b) and (bool(b.get("undeclared", false)) or bool(b.get("black_wages", false))):
			found.append("ventas o sueldos sin declarar en %s" % gs.building_label(b))
			break
	var c := {"day": gs.today(), "due": gs.today() + int(cc.get("bribe_days", 10)), "fine": snappedf(fine, 0.01),
		"grave": grave, "found": ", ".join(found), "bribe_tried": false}
	st(gs)["case"] = c
	var t := "¡Hallazgo en una inspección! Encontraron %s. Multa prevista %s%s. Tienes %d días para responder (pagar o intentar un soborno)." % [c["found"], Fmt.money(fine), " y posible cárcel (caso grave)" if grave else "", int(cc.get("bribe_days", 10))]
	_log(gs, t)
	return t


static func bribe_chance(gs, amount: float) -> float:
	var c := case_of(gs)
	if c.is_empty():
		return 0.0
	var bc: Dictionary = cfg().get("bribe", {})
	var ratio := amount / maxf(1.0, float(c.get("fine", 1.0)))
	var p := float(bc.get("base", 0.2)) + float(bc.get("per_fine_ratio", 0.45)) * ratio + float(bc.get("corruption_weight", 0.003)) * PoliticsSim.corruption(gs) - float(bc.get("police_penalty", 0.2)) * EventsSim.coverage(gs, "policia")
	p *= 1.0 / maxf(0.5, _gov_mult(gs))
	return clampf(p, float(bc.get("min", 0.05)), float(bc.get("max", 0.9)))


## Soborno al ser descubierto: se paga (efectivo primero). Aceptado: se archiva el caso.
## Rechazado: no se cobra, la multa sube y el caso se resuelve ya.
static func bribe(gs, amount: float, roll := -1.0) -> String:
	var c := case_of(gs)
	if c.is_empty():
		return "No hay ningún caso abierto."
	if amount <= 0.0:
		return "Monto inválido."
	if float(gs.money) < amount:
		return "No tienes %s." % Fmt.money(amount)
	var bc: Dictionary = cfg().get("bribe", {})
	var p := bribe_chance(gs, amount)
	var ps: Dictionary = PoliticsSim.state(gs)
	if _roll(gs, roll) < p:
		var paid := _take(gs, amount, true)
		PoliticsSim._pay_official(gs, paid)
		ps["corruption"] = minf(100.0, PoliticsSim.corruption(gs) + float(bc.get("corruption_add", 15)))
		PoliticsSim._log(gs, "Soborno a un inspector (%s)." % Fmt.money(paid))
		_stat(gs, "bribes", paid)
		st(gs)["case"] = {}
		st(gs)["risk"] = risk(gs) * 0.6
		var t := "Soborno ACEPTADO: el inspector archivó el caso a cambio de %s. Sube la corrupción de la familia (%d)." % [Fmt.money(paid), int(PoliticsSim.corruption(gs))]
		_log(gs, t)
		return t
	ps["corruption"] = minf(100.0, PoliticsSim.corruption(gs) + float(bc.get("corruption_add_rejected", 5)))
	var t2 := "Soborno RECHAZADO: el inspector no aceptó %s y agrava el caso." % Fmt.money(amount)
	_log(gs, t2)
	resolve_case(gs, float(bc.get("rejected_fine_mult", 1.5)))
	return t2


## Aplica las consecuencias del hallazgo: multa, decomiso, cierre de negocios ocultos, reputación y cárcel.
static func resolve_case(gs, fine_mult := 1.0) -> String:
	var c := case_of(gs)
	if c.is_empty():
		return ""
	var cc: Dictionary = cfg().get("case", {})
	var grave := bool(c.get("grave", false))
	var treasury := 0.0
	# Decomiso de efectivo.
	var seized := float(gs.cash) * float(cc.get("seize_cash_share_grave" if grave else "seize_cash_share", 0.5))
	if seized > 0.0:
		pay_cash(gs, seized)
		treasury += seized
	# Multa (banco primero).
	var fine := _take(gs, float(c.get("fine", 0.0)) * fine_mult, false)
	treasury += fine
	GovSim.add_treasury(gs, treasury)
	gs.add_counter("taxes_paid", treasury)
	# Cierre de los negocios ocultos y decomiso de su mercancía.
	var goods := 0.0
	var closed := []
	for h in active_hidden(gs):
		goods += float(h.get("stock", 0.0))
		closed.append(str(hidden_type(str(h["type"])).get("label", h["type"])))
	st(gs)["hidden"] = []
	# Tus negocios vuelven a declarar todo.
	for b in gs.buildings:
		if gs.owned_by_player(b):
			b["undeclared"] = false
			b["black_wages"] = false
	PoliticsSim.add_reputation(gs, -float(cc.get("reputation_loss", 8)) * (2.0 if grave else 1.0))
	_stat(gs, "fines", fine)
	_stat(gs, "seized", seized)
	st(gs)["offenses"] = int(st(gs).get("offenses", 0)) + 1
	st(gs)["case"] = {}
	st(gs)["risk"] = risk(gs) * float(cc.get("risk_after", 0.3))
	var t := "Sanción: multa de %s y decomiso de %s en efectivo" % [Fmt.money(fine), Fmt.money(seized)]
	if not closed.is_empty():
		t += "; cierran tus negocios ocultos (%s) y decomisan %d unidades" % [", ".join(closed), int(goods)]
	t += ". Baja tu reputación."
	if grave:
		var who := _jail(gs)
		if who != "":
			t += " " + who
	_log(gs, t)
	return t


## Caso grave: cárcel para el jefe o un familiar adulto que asume la culpa.
static func _jail(gs) -> String:
	var days: Array = cfg().get("case", {}).get("prison_days", [60, 180])
	var adult := 18
	var pool := HeirsSim.family_members(gs).filter(func(x): return x.age_years(gs.today()) >= adult and x.prison_until < 0)
	var target: Citizen = gs.player_citizen()
	if not pool.is_empty() and rf(gs) < 0.5:
		target = pool[int(rf(gs) * pool.size()) % pool.size()]
	if target == null:
		return ""
	var n := int(days[0]) + int(rf(gs) * float(int(days[1]) - int(days[0]) + 1))
	target.prison_until = gs.today() + n
	target.prison_id = -1
	if not gs.is_player(target.id) and target.job_id >= 0:
		target.job_id = -1
		target.job_kind = ""
		target.wage = 0.0
	return "%s va a la cárcel por %d días." % ["Tu personaje" if gs.is_player(target.id) else target.full_name(), n]


# --- Negocios ocultos ---------------------------------------------------------------------------------------

static func hidden_types() -> Dictionary:
	return cfg().get("hidden_types", {})


static func hidden_type(id: String) -> Dictionary:
	return hidden_types().get(id, {})


static func hidden_ids() -> Array:
	var d := hidden_types()
	var ids := d.keys()
	ids.sort_custom(func(a, b): return int(d[a].get("order", 0)) < int(d[b].get("order", 0)))
	return ids


static func active_hidden(gs) -> Array:
	return st(gs).get("hidden", []).filter(func(h): return str(h.get("status", "activo")) == "activo")


static func hidden_price(gs, type_id: String) -> float:
	return float(hidden_type(type_id).get("price", 1.0)) * gs.price_mult()


static func setup_cost(gs, type_id: String) -> float:
	return float(hidden_type(type_id).get("setup_cost", 0.0)) * gs.price_mult()


static func hidden_block_reason(gs, type_id: String) -> String:
	var t := hidden_type(type_id)
	if t.is_empty():
		return "Tipo desconocido."
	var tech := str(t.get("tech", ""))
	if not gs.has_tech(tech):
		return "Requiere investigar %s." % GameData.tech_label(tech)
	if not case_of(gs).is_empty():
		return "Tienes un caso abierto con la autoridad."
	var p: Citizen = gs.player_citizen()
	if p != null and p.prison_until >= 0:
		return "Estás en la cárcel."
	if float(gs.cash) < setup_cost(gs, type_id):
		return "El montaje se paga en efectivo: necesitas %s (tienes %s)." % [Fmt.money(setup_cost(gs, type_id)), Fmt.money(gs.cash)]
	return ""


static func open_hidden(gs, type_id: String) -> String:
	var why := hidden_block_reason(gs, type_id)
	if why != "":
		return why
	var cost := setup_cost(gs, type_id)
	pay_cash(gs, cost)
	PoliticsSim.spread_to_citizens(gs, cost, 6)   # Jornaleros y proveedores informales.
	var s := st(gs)
	var h := {"id": int(s["next_hidden_id"]), "type": type_id, "status": "activo", "stock": 0.0,
		"opened_day": gs.today(), "sold_month": 0.0, "sold_total": 0.0, "units_total": 0.0, "idle": false}
	s["next_hidden_id"] = int(s["next_hidden_id"]) + 1
	s["hidden"].append(h)
	add_risk(gs, 2.0)
	_log(gs, "Montaste un negocio oculto: %s (%s en efectivo). Produce %s y vende solo en efectivo." % [hidden_type(type_id).get("label", type_id), Fmt.money(cost), str(hidden_type(type_id).get("product", "")).to_lower()], "negocio")
	return ""


## Desmontar voluntariamente un negocio oculto (se pierde la mercancía).
static func close_hidden(gs, hid: int) -> String:
	for h in st(gs)["hidden"]:
		if int(h["id"]) == hid:
			st(gs)["hidden"].erase(h)
			_log(gs, "Desmontaste %s." % hidden_type(str(h["type"])).get("label", h["type"]), "negocio")
			return ""
	return "No existe."


static func _hidden_daily(gs) -> void:
	var pm: float = gs.price_mult()
	for h in active_hidden(gs):
		var t := hidden_type(str(h["type"]))
		var out := minf(float(t.get("daily_output", 0.0)), maxf(0.0, float(t.get("max_stock", 100)) - float(h["stock"])))
		var wages := float(t.get("daily_wages", 0.0)) * pm
		var inputs := out * float(t.get("unit_cost", 0.0)) * pm
		if not pay_cash(gs, wages + inputs):
			if not bool(h.get("idle", false)):
				_log(gs, "%s está parado: no hay efectivo para jornaleros e insumos." % t.get("label", h["type"]), "negocio")
			h["idle"] = true
			continue
		h["idle"] = false
		PoliticsSim.spread_to_citizens(gs, wages, maxi(1, int(t.get("workers", 2))))
		if str(t.get("cost_to", "citizens")) == "outside":
			gs.add_counter("imports", inputs)   # Mercancía sin arancel: el pago sale del pueblo.
		else:
			PoliticsSim.spread_to_citizens(gs, inputs, 4)
		h["stock"] = float(h["stock"]) + out
		_stat(gs, "hidden_costs", wages + inputs)
		add_risk(gs, float(t.get("risk_per_day", 0.1)))


## Venta semanal de los negocios ocultos: demanda propia, solo en efectivo.
static func _hidden_sales(gs) -> void:
	var hidden := active_hidden(gs)
	if hidden.is_empty():
		return
	var hc: Dictionary = cfg().get("hidden_demand", {})
	var need_day := 0.0
	for n in GameData.citizens.get("needs", {}).values():
		need_day += float(n.get("cost", 0.1))
	need_day *= gs.price_mult()
	var buffer := need_day * float(hc.get("buffer_days", 30))
	var adult := int(GameData.citizens.get("adult_age", 16))
	var today: int = gs.today()
	var buyers := []
	var adults := 0
	for c in gs.citizens.values():
		if gs.is_player(c.id) or c.age_years(today) < adult or c.prison_until >= 0:
			continue
		adults += 1
		if c.money > buffer:
			buyers.append(c)
	buyers.sort_custom(func(a, b): return a.id < b.id)
	for h in hidden:
		var t := hidden_type(str(h["type"]))
		var price := hidden_price(gs, str(h["type"]))
		var want := adults * float(t.get("demand", 0.1))
		var sold := 0.0
		var income := 0.0
		for c in buyers:
			if sold >= want - 0.01 or float(h["stock"]) <= 0.01:
				break
			if rf(gs) > float(hc.get("buy_chance", 0.5)):
				continue
			var budget: float = (c.money - buffer) * float(hc.get("max_share", 0.08))
			var qty := minf(minf(float(h["stock"]), want - sold), minf(3.0, budget / price))
			if qty < 0.2:
				continue
			var cost := qty * price
			c.money -= cost
			h["stock"] = float(h["stock"]) - qty
			sold += qty
			income += cost
		if income > 0.0:
			_earn_cash(gs, income)
			h["sold_month"] = float(h.get("sold_month", 0.0)) + income
			h["sold_total"] = float(h.get("sold_total", 0.0)) + income
			h["units_total"] = float(h.get("units_total", 0.0)) + sold
			_stat(gs, "hidden_sales", income)


# --- Ciclos ---------------------------------------------------------------------------------------------------

static func daily(gs) -> void:
	if gs.informal.is_empty():
		init_state(gs)
	_hidden_daily(gs)
	if gs.today() % 7 == 0:
		_hidden_sales(gs)
	# Banco en rojo: el efectivo lo cubre (cuenta como depósito).
	var b := bank(gs)
	if b < 0.0 and float(gs.cash) > 0.0:
		var cover := minf(float(gs.cash), -b)
		var allowance := deposit_allowance(gs)
		gs.cash = maxf(0.0, float(gs.cash) - cover)
		_register_deposit(gs, cover, allowance, "Tu cuenta quedó en rojo: cubriste %s con efectivo." % Fmt.money(cover))
	# Plazo del caso vencido: se aplica la sanción.
	var c := case_of(gs)
	if not c.is_empty() and gs.today() >= int(c.get("due", 0)):
		resolve_case(gs)


static func monthly(gs) -> void:
	var s := st(gs)
	var rc: Dictionary = cfg().get("risk", {})
	# Inspección según el riesgo acumulado, la policía y el gobierno.
	if case_of(gs).is_empty() and rf(gs) < inspection_chance(gs):
		inspect(gs)
	s["risk"] = maxf(0.0, risk(gs) * (1.0 - float(rc.get("monthly_decay_share", 0.08))) - float(rc.get("monthly_decay", 3.0)))
	s["last_month"] = s["month"]
	s["month"] = {}
	s["deposited_month"] = 0.0
	for h in s["hidden"]:
		h["sold_month"] = 0.0
	for b in gs.buildings:
		if b.has("cash_ledger"):
			var cl: Dictionary = b["cash_ledger"]
			cl["last_month"] = cl.get("month", {})
			cl["month"] = {}
