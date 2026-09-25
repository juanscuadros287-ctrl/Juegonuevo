class_name DynastySim
extends RefCounted
## Fase 8 — herencia y dinastía: registro de jefes de familia (años de gobierno y patrimonio),
## impuesto a la herencia según el gobierno, deudas heredadas y avisos de sucesión.
## Estado en GameState.player["dynasty"] y ["inheritance_debt"]. Parámetros en data/dynasty.json.


static func cfg() -> Dictionary:
	return GameData.extra("dynasty")


## Crea el registro de la dinastía si no existe (partidas nuevas y antiguas).
static func ensure(gs) -> void:
	if gs.player.has("dynasty"):
		return
	var p: Citizen = gs.player_citizen()
	gs.player["dynasty"] = []
	if p != null:
		_open_head(gs, p, "fundador")


static func heads(gs) -> Array:
	ensure(gs)
	return gs.player["dynasty"]


static func generation(gs) -> int:
	return heads(gs).size()


static func _open_head(gs, c: Citizen, how: String) -> void:
	gs.player["dynasty"].append({"id": c.id, "name": c.full_name(), "gender": c.gender, "how": how,
		"start_day": gs.today(), "start_year": TimeManager.year(), "start_age": c.age_years(gs.today()),
		"net_worth_start": EconomySim.net_worth(gs), "end_day": -1, "end_year": -1, "net_worth_end": 0.0,
		"end_reason": "", "tax_paid": 0.0, "debts_inherited": 0.0})


static func _close_head(gs, reason: String) -> Dictionary:
	var list := heads(gs)
	if list.is_empty():
		return {}
	var h: Dictionary = list[list.size() - 1]
	if int(h.get("end_day", -1)) < 0:
		h["end_day"] = gs.today()
		h["end_year"] = TimeManager.year()
		h["net_worth_end"] = EconomySim.net_worth(gs)
		h["end_reason"] = reason
	return h


# --- Impuesto a la herencia -------------------------------------------------------------------

## Tasa según el gobierno: su campo "inheritance_tax" o, si no existe, según qué tan social es.
static func tax_rate(gs) -> float:
	var pol: Dictionary = GovSim.policy(gs)
	var c := cfg()
	if pol.has("inheritance_tax"):
		return clampf(float(pol["inheritance_tax"]), 0.0, 0.9)
	if pol.has("social"):
		return lerpf(float(c.get("inheritance_tax_min", 0.05)), float(c.get("inheritance_tax_max", 0.3)), clampf(float(pol["social"]), 0.0, 1.0))
	return float(c.get("inheritance_tax_default", 0.1))


static func exempt_amount(gs) -> float:
	return float(cfg().get("exempt_amount", 3000)) * gs.price_mult()


## Estimación del impuesto si el jefe de familia muriera hoy.
static func estimate_tax(gs) -> Dictionary:
	var nw := EconomySim.net_worth(gs)
	var base := maxf(0.0, nw - exempt_amount(gs))
	var rate := tax_rate(gs)
	return {"net_worth": nw, "exempt": exempt_amount(gs), "base": base, "rate": rate, "tax": base * rate,
		"debt": EconomySim.player_debt(gs), "pending": pending_debt(gs)}


static func pending_debt(gs) -> float:
	return float(gs.player.get("inheritance_debt", 0.0))


## Sucesión: cierra el registro del fallecido, abre el del heredero, cobra el impuesto
## (en efectivo lo que alcance; el resto queda en cuotas con el tesoro) y resume las deudas heredadas.
static func on_succession(gs, dead: Citizen, heir: Citizen) -> String:
	ensure(gs)
	var h := _close_head(gs, "murió a los %d años" % dead.age_years(gs.today()))
	var est := estimate_tax(gs)
	var tax := float(est["tax"])
	var cash := clampf(tax, 0.0, maxf(0.0, gs.money))
	if cash > 0.0:
		gs.add_money(-cash)
		GovSim.add_treasury(gs, cash)
		gs.add_counter("taxes_paid", cash)
	var owed := tax - cash
	if owed > 0.01:
		var months := maxi(1, int(cfg().get("installment_months", 12)))
		gs.player["inheritance_debt"] = pending_debt(gs) + owed
		gs.player["inheritance_installment"] = pending_debt(gs) / months
	if not h.is_empty():
		h["tax_paid"] = tax
	_open_head(gs, heir, "heredero(a)")
	var list := heads(gs)
	var cur: Dictionary = list[list.size() - 1]
	cur["debts_inherited"] = float(est["debt"])
	var loans := BankSim.player_loans(gs).size()
	var text := "Impuesto a la herencia (%s): %s" % [Fmt.pct(float(est["rate"]) * 100.0), Fmt.money(tax)]
	if owed > 0.01:
		text += " (%s en cuotas al tesoro)" % Fmt.money(owed)
	if loans > 0:
		text += ". Hereda también %d préstamo(s) por %s" % [loans, Fmt.money(float(est["debt"]))]
	return text + "."


static func on_dynasty_end(gs, dead: Citizen) -> void:
	ensure(gs)
	_close_head(gs, "murió a los %d años sin herederos" % dead.age_years(gs.today()))


# --- Ciclo mensual ------------------------------------------------------------------------------

static func monthly(gs) -> void:
	ensure(gs)
	_pay_installment(gs)
	_old_age_warning(gs)
	HeirsSim.monthly(gs)      # Sección C: educación y talentos de herederos.
	PoliticsSim.monthly(gs)   # Sección C: cargos, campañas, lobby y escándalos.


static func _pay_installment(gs) -> void:
	var debt := pending_debt(gs)
	if debt <= 0.0:
		return
	var due := minf(debt, maxf(float(gs.player.get("inheritance_installment", debt)), 1.0))
	if gs.money >= due:
		gs.add_money(-due)
		GovSim.add_treasury(gs, due)
		gs.add_counter("taxes_paid", due)
		debt -= due
		if debt <= 0.01:
			debt = 0.0
			gs.notify("Terminaste de pagar el impuesto a la herencia.", "jugador")
	else:
		debt *= 1.0 + float(cfg().get("installment_surcharge", 0.02))
		gs.notify("No pudiste pagar la cuota del impuesto a la herencia: recargo aplicado.", "jugador")
	gs.player["inheritance_debt"] = debt


## Aviso cuando el jefe de familia envejece sin heredero.
static func _old_age_warning(gs) -> void:
	var p: Citizen = gs.player_citizen()
	if p == null:
		return
	var age: int = p.age_years(gs.today())
	if age < int(cfg().get("old_age_warning", 60)) or has_heir(gs):
		return
	var year: int = TimeManager.year()
	var last := int(gs.player.get("heir_warn_year", -100))
	if year - last < int(cfg().get("warning_every_years", 2)):
		return
	gs.player["heir_warn_year"] = year
	gs.notify("Tienes %d años y no tienes heredero: si mueres, termina la dinastía. Ten hijos o adopta." % age, "jugador")


static func has_heir(gs) -> bool:
	return not PlayerSim.heir_candidates(gs).is_empty() or HeirsSim.has_listed_heir(gs)


static func years_of(gs, h: Dictionary) -> int:
	var end := int(h.get("end_day", -1))
	if end < 0:
		end = gs.today()
	return int(float(end - int(h.get("start_day", 0))) / 365.0)
