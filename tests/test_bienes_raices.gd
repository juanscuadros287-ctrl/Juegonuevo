extends Node
## Pruebas de bienes raíces: unidades, precios por piso, arriendo/venta, ficha de factibilidad,
## pago por etapas, preventa, crédito constructor, tipos de crédito, hipotecas, guardado y 10 años.
## godot --headless res://tests/test_bienes_raices.tscn

const TECHS := ["adobe", "ladrillo", "arquitectura_urbana", "acero_estructural", "rascacielos"]

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func _ready() -> void:
	print("== Dinastía: pruebas de bienes raíces ==")
	_test_units_created()
	_test_migration()
	_test_prices()
	_test_feasibility()
	_test_rent_and_sale()
	_test_stage_payment()
	_test_presale()
	_test_constructor_credit()
	_test_loan_types()
	_test_player_loans()
	_test_mortgage_player_bank()
	_test_save_load()
	_test_ten_years()
	print("== %s (%d fallos) ==" % ["TODO OK" if failures == 0 else "CON FALLOS", failures])
	get_tree().quit(1 if failures > 0 else 0)


# --- Utilidades ----------------------------------------------------------------------------------

func _town(seed_v: int, money := 300000.0) -> void:
	GameState.new_game({"seed": seed_v, "difficulty": "normal"})
	for t in TECHS:
		if not GameState.techs.has(t):
			GameState.techs.append(t)
	GameState.money = money


func _finish(b: Dictionary, max_days := 600) -> void:
	var guard := 0
	while b["status"] != "activo" and guard < max_days:
		TimeManager.advance_days(1)
		guard += 1


func _project(level: int, x: float, z: float, opts := {}) -> Dictionary:
	var r := RealEstateSim.start_project(GameState, level, "normal", x, z, 0.0, "", opts)
	if r.has("error"):
		print("    error proyecto: ", r["error"])
		return {}
	return r["building"]


## Dinero total dentro del pueblo (jugador + ciudadanos + reservas + tesoro).
func _money_in_town() -> float:
	var m := GameState.money
	for c in GameState.citizens.values():
		m += c.money
	for b in GameState.buildings:
		m += float(b.get("reserve", 0.0))
	return m + float(GameState.government.get("treasury", 0.0))


## Una familia adulta que no vive con el jugador.
func _family() -> Array:
	for members in MarketSim.households(GameState):
		if members.any(func(m): return GameState.is_player(m.id)):
			continue
		if members.size() <= 4:
			return members
	return []


func _staff_up(b: Dictionary) -> void:
	var jobs := int(GameState.level_def(b).get("jobs", 1))
	var hired := 0
	for c in BusinessSim.candidates(GameState, b):
		if hired >= jobs:
			break
		if BusinessSim.hire(GameState, b, c, BusinessSim.asked_wage(GameState, c, str(b["type"])) * 1.1) == "":
			hired += 1


# --- 1. Unidades ---------------------------------------------------------------------------------

func _test_units_created() -> void:
	print("-- unidades al terminar un edificio de apartamentos")
	_town(501)
	var b := _project(4, 30, -12)
	check(not b.is_empty(), "se inicia un proyecto de apartamentos")
	if b.is_empty():
		return
	_finish(b)
	check(b["status"] == "activo", "la obra termina (%d/%d trabajo)" % [int(b["work_done"]), int(b["work_needed"])])
	var units: Array = b.get("units", [])
	check(units.size() == RealEstateSim.layout(4).size() and units.size() == 9, "9 unidades creadas (%d)" % units.size())
	var cap := 0
	var ids := {}
	for u in units:
		cap += int(u["capacity"])
		ids[int(u["id"])] = true
	check(cap == GameState.building_capacity(b), "la suma de capacidades = capacidad del edificio (%d)" % cap)
	check(ids.size() == units.size(), "cada unidad tiene id propio")
	check(units.all(func(u): return str(u["status"]) in ["disponible", "arrendada", "vendida"] and u.has("floor") and u.has("price") and u.has("rent")), "unidades con piso, estado, precio y renta")
	check(not b.has("re_project") and b.has("re_done"), "el proyecto se cierra al terminar")
	# Mejora normal (sin proyecto) a apartamentos también crea unidades.
	var h := ConstructionSim.make_building(GameState, "vivienda", 3, -30, 20, 0.0, "jugador")
	GameState.add_building(h)
	check(ConstructionSim.start_upgrade(GameState, h) == "", "mejora normal de casa de ladrillo a apartamentos")
	_finish(h)
	check((h.get("units", []) as Array).size() == 9, "la mejora normal también crea unidades")


func _test_migration() -> void:
	print("-- migración de edificios existentes sin romper inquilinos")
	_town(502)
	var b := ConstructionSim.make_building(GameState, "vivienda", 4, 30, 14, 0.0, "jugador")
	GameState.add_building(b)
	var fam := _family()
	for m in fam:
		m.home_id = int(b["id"])
	var d := GameState.to_dict()
	for bd in d["buildings"]:
		bd.erase("units")   # Como una partida vieja.
	GameState.load_dict(JSON.parse_string(JSON.stringify(d)))
	var nb: Dictionary = GameState.get_building(int(b["id"]))
	check((nb.get("units", []) as Array).size() == 9, "al cargar una partida vieja se crean las unidades")
	var still := GameState.residents_of(int(nb["id"])).size()
	check(still == fam.size(), "los inquilinos siguen viviendo ahí (%d/%d)" % [still, fam.size()])
	var rented: Array = (nb["units"] as Array).filter(func(u): return str(u["status"]) == "arrendada")
	check(rented.size() == 1 and int(rented[0]["tenant_id"]) == fam[0].id, "la familia quedó como inquilina de una unidad")


# --- 2. Precios ------------------------------------------------------------------------------------

func _test_prices() -> void:
	print("-- precio y renta por unidad")
	_town(503)
	GameState.realestate["demand"] = 1.0
	for level in [4, 5, 6]:
		var lay := RealEstateSim.layout(level)
		var pr := RealEstateSim.unit_prices(GameState, level, "normal")
		var total := 0.0
		var rent := 0.0
		for p in pr:
			total += float(p["price"])
			rent += float(p["rent"])
		var repl := RealEstateSim.replacement_cost(GameState, level, "normal")
		var margin := total / repl - 1.0
		var yld := rent * 12.0 / total
		check(margin >= 0.15 and margin <= 0.30, "nivel %d: margen de promotor %.1f%% (15–30%%)" % [level, margin * 100.0])
		check(yld >= 0.05 and yld <= 0.09, "nivel %d: arriendo %.1f%% anual del valor (5–9%%)" % [level, yld * 100.0])
		# Mismo tipo, piso más alto → más caro.
		var low := -1
		var high := -1
		for i in range(lay.size()):
			if str(lay[i]["type"]) == str(lay[0]["type"]):
				if low < 0:
					low = i
				high = i
		check(float(pr[high]["price"]) > float(pr[low]["price"]) and float(pr[high]["rent"]) > float(pr[low]["rent"]), "nivel %d: piso %d vale más que piso %d" % [level, int(lay[high]["floor"]), int(lay[low]["floor"])])
	var alta := RealEstateSim.value_total(GameState, 4, "alta")
	check(alta > RealEstateSim.value_total(GameState, 4, "normal") * 2.0, "la calidad alta vale más")
	var v1 := RealEstateSim.value_total(GameState, 4, "normal")
	GameState.realestate["demand"] = 1.15
	check(RealEstateSim.value_total(GameState, 4, "normal") > v1 * 1.1, "con más demanda suben los precios")
	GameState.realestate["demand"] = 1.0
	GameState.research["era"] = 3
	check(RealEstateSim.cap_rate(GameState) < 0.07, "en la época moderna el arriendo rinde menos (%.3f)" % RealEstateSim.cap_rate(GameState))


func _test_feasibility() -> void:
	print("-- ficha de factibilidad")
	_town(504)
	for level in [4, 5, 6]:
		var f := RealEstateSim.feasibility(GameState, level, "media")
		var cost := ConstructionSim.cost_for(GameState, "vivienda", level, false, "media")
		check(is_equal_approx(float(f["cost_total"]), float(cost["total"])), "nivel %d: costo total = cost_for (%s)" % [level, Fmt.money(float(cost["total"]))])
		check(is_equal_approx(float(f["cost_per_unit"]) * int(f["units"]), float(f["cost_total"])), "nivel %d: costo por unidad × unidades = total" % level)
		check(int(f["days"]) == int(cost["days"]), "nivel %d: días de obra = cost_for" % level)
		var st := 0.0
		for s in f["stages"]:
			st += float(s["amount"])
		check(is_equal_approx(st, float(f["cost_total"])), "nivel %d: las etapas suman el costo" % level)
		check(float(f["payback_months"]) > 60.0 and float(f["payback_months"]) < 600.0, "nivel %d: recuperación en %d meses" % [level, int(f["payback_months"])])
		print("    ", RealEstateSim.feasibility_text(f).replace("\n", " | ").left(400))
	var up := RealEstateSim.feasibility(GameState, 4, "normal", true)
	check(is_equal_approx(float(up["cost_total"]), float(ConstructionSim.cost_for(GameState, "vivienda", 4, true, "normal")["total"])), "ficha de mejora = cost_for de mejora")


# --- 3. Arriendo y venta ------------------------------------------------------------------------------

func _test_rent_and_sale() -> void:
	print("-- arriendo y venta de unidades con el dinero conservado")
	_town(505)
	var b := ConstructionSim.make_building(GameState, "vivienda", 4, 30, -14, 0.0, "jugador")
	GameState.add_building(b)
	RealEstateSim.ensure_units(GameState, b)
	for c in GameState.citizens.values():
		c.money = 0.0
	var fam := _family()
	var head: Citizen = fam[0]
	for m in fam:
		m.home_id = -1
	var u0: Dictionary = b["units"][0]
	head.money = float(u0["rent"]) * 30.0
	RealEstateSim.set_all(b, "for_sale", false)
	var before := _money_in_town()
	RealEstateSim._market(GameState)
	var rented: Array = (b["units"] as Array).filter(func(u): return str(u["status"]) == "arrendada")
	check(rented.size() == 1 and int(rented[0]["tenant_id"]) == head.id and head.home_id == int(b["id"]), "una familia sin techo arrienda una unidad")
	check(is_equal_approx(_money_in_town(), before), "arrendar no crea ni destruye dinero")
	var pm := GameState.money
	var hm := head.money
	TimeManager.advance_days(1)
	var unit: Dictionary = rented[0] if not rented.is_empty() else {}
	var paid := hm - head.money
	check(not unit.is_empty() and absf(paid - float(unit["rent"]) / 30.0) < 0.2, "el inquilino paga la renta diaria de su unidad (%.2f)" % paid)
	check(BusinessSim.period_value(b, "month", "alquileres") > 0.0, "el edificio registra ingresos por arriendo")
	# Venta de contado.
	var fam2: Array = []
	for members in MarketSim.households(GameState):
		if not members.any(func(m): return GameState.is_player(m.id) or m.id == head.id) and members.size() <= 4:
			fam2 = members
			break
	for c in GameState.citizens.values():
		c.money = 0.0
	RealEstateSim.set_all(b, "for_rent", false)
	RealEstateSim.set_all(b, "for_sale", true)
	var buyer: Citizen = fam2[0]
	for m in fam2:
		m.home_id = -1
	buyer.money = 50000.0
	buyer.job_kind = "empleo"
	buyer.wage = 3.0
	var t0 := _money_in_town()
	var sold := false
	for i in range(30):
		RealEstateSim._market(GameState)
		if (b["units"] as Array).any(func(u): return str(u["status"]) == "vendida"):
			sold = true
			break
	check(sold, "una familia compra una unidad de contado")
	check(absf(_money_in_town() - t0) < 0.01, "vender no crea ni destruye dinero (%.2f)" % (_money_in_town() - t0))
	var sold_u: Array = (b["units"] as Array).filter(func(u): return str(u["status"]) == "vendida")
	check(not sold_u.is_empty() and int(sold_u[0]["owner_id"]) == buyer.id and buyer.home_id == int(b["id"]), "el comprador queda como dueño y se muda")
	var hm2 := buyer.money
	TimeManager.advance_days(1)
	check(buyer.money >= hm2 - 5.0, "el dueño no paga arriendo")
	check(EconomySim.property_value(GameState, b) < RealEstateSim.value_total(GameState, 4, "normal") * 1.2, "el patrimonio solo cuenta las unidades que aún son tuyas")


# --- 4. Etapas -------------------------------------------------------------------------------------

func _test_stage_payment() -> void:
	print("-- pago por etapas que pausa la obra sin dinero")
	_town(506)
	var cost := ConstructionSim.cost_for(GameState, "vivienda", 4, false, "normal")
	var first := float(cost["total"]) * 0.2
	GameState.money = first + 10.0
	var b := _project(4, -30, -14)
	check(not b.is_empty(), "alcanza para la cimentación")
	if b.is_empty():
		return
	check(absf(GameState.money - 10.0) < 1.0, "solo se cobró la cimentación (%s)" % Fmt.money(GameState.money))
	var guard := 0
	while not bool(b.get("paused", false)) and guard < 200:
		TimeManager.advance_days(1)
		guard += 1
	check(bool(b.get("paused", false)), "sin dinero para la estructura la obra se pausa (día %d)" % guard)
	var wn := float(b["work_needed"])
	check(absf(float(b["work_done"]) - wn * 0.2) < 0.01, "se conserva lo avanzado (%.0f/%.0f)" % [float(b["work_done"]), wn])
	var crew := GameState.employees_of(int(b["id"])).filter(func(c): return c.job_kind == "obra").size()
	TimeManager.advance_days(10)
	check(absf(float(b["work_done"]) - wn * 0.2) < 0.01 and crew == 0, "en pausa no avanza ni retiene jornaleros")
	GameState.money = 100000.0
	TimeManager.advance_days(3)
	check(not bool(b.get("paused", false)) and float(b["work_done"]) > wn * 0.2, "con dinero la obra se reanuda")
	check(bool(b["re_project"]["stages"][1]["paid"]), "la etapa de estructura quedó pagada")
	_finish(b)
	check(b["status"] == "activo", "la obra termina tras pagar las 3 etapas")
	check(absf(float(b["re_done"]["paid_total"]) - float(cost["total"])) < 1.0, "lo pagado en etapas = costo total")


# --- 5. Preventa ---------------------------------------------------------------------------------------

func _test_presale() -> void:
	print("-- preventa con cuotas y entrega")
	_town(507)
	var b := _project(4, 30, 14)
	if b.is_empty():
		check(false, "proyecto para preventa")
		return
	RealEstateSim.set_all(b, "for_sale", true)
	for c in GameState.citizens.values():
		c.money = 0.0
	var fam := _family()
	var buyer: Citizen = fam[0]
	buyer.money = 100000.0
	buyer.job_kind = "empleo"
	buyer.wage = 3.0
	var t0 := _money_in_town()
	var pre := {}
	for i in range(40):
		RealEstateSim._market(GameState)
		for u in b["units"]:
			if str(u["status"]) == "preventa":
				pre = u
		if not pre.is_empty():
			break
	check(not pre.is_empty(), "una familia compra sobre planos")
	if pre.is_empty():
		return
	var ps: Dictionary = pre["presale"]
	check(absf(float(ps["paid"]) - float(pre["price"]) * 0.1) < 0.5, "paga la cuota inicial del 10%%")
	check(absf(_money_in_town() - t0) < 0.01, "la preventa conserva el dinero")
	var paid0 := float(ps["paid"])
	RealEstateSim._presale_installments(GameState)
	check(float(ps["paid"]) > paid0, "paga cuotas mensuales durante la obra")
	var price := float(pre["price"])
	var bm := buyer.money
	_finish(b)
	check(str(pre["status"]) == "vendida" and int(pre["owner_id"]) == buyer.id, "al terminar se entrega la unidad al comprador")
	check(buyer.home_id == int(b["id"]), "el comprador se muda a su apartamento")
	check(BusinessSim.period_value(b, "total", "ventas") >= price - 0.5, "la venta completa queda en el libro del edificio")
	check(bm > buyer.money, "el saldo se pagó al entregar")
	# Cancelación: se devuelve lo pagado.
	RealEstateSim.set_all(b, "for_sale", false)
	var b2 := _project(4, -30, 14)
	RealEstateSim.set_all(b2, "for_sale", true)
	var fam2: Array = []
	for members in MarketSim.households(GameState):
		if not members.any(func(m): return GameState.is_player(m.id) or m.id == buyer.id) and members.size() <= 4:
			fam2 = members
			break
	var b2uy: Citizen = fam2[0]
	b2uy.money = 100000.0
	b2uy.job_kind = "empleo"
	b2uy.wage = 3.0
	for i in range(40):
		RealEstateSim._market(GameState)
		if (b2["units"] as Array).any(func(u): return str(u["status"]) == "preventa"):
			break
	var before := b2uy.money
	var paid_total := 0.0
	for u in b2["units"]:
		if str(u["status"]) == "preventa":
			paid_total += float(u["presale"]["paid"])
	check(paid_total > 0.0, "segunda preventa firmada")
	var t1 := _money_in_town()
	check(RealEstateSim.cancel_project(GameState, b2) == "", "se cancela el proyecto")
	check(absf(b2uy.money - before - paid_total) < 0.01, "al cancelar se devuelve lo pagado (%s)" % Fmt.money(paid_total))
	check(absf(_money_in_town() - t1) < 0.01, "la devolución conserva el dinero")
	check(GameState.get_building(int(b2["id"])).is_empty(), "la obra nueva cancelada se demuele")


# --- 6. Crédito constructor ---------------------------------------------------------------------------

func _test_constructor_credit() -> void:
	print("-- crédito constructor por desembolsos")
	_town(508, 200000.0)
	var b := _project(5, 32, -14, {"credit_lender": "externo", "credit_ratio": 0.5})
	if b.is_empty():
		check(false, "proyecto con crédito constructor")
		return
	var l := LoanContract.find_loan(GameState, int(b["re_project"]["credit_id"]))
	check(not l.is_empty() and str(l["type"]) == "constructor", "se abre un crédito constructor")
	var total := float(b["re_project"]["total"])
	check(absf(float(l["limit"]) - total * 0.5) < 1.0, "cupo = 50%% del costo (%s)" % Fmt.money(float(l["limit"])))
	check(absf(float(l["disbursed"]) - total * 0.2 * 0.5) < 1.0, "solo se desembolsó la parte de la cimentación")
	var bal := float(l["balance"])
	var m0 := GameState.money
	var r := float(l["rate"]) / 12.0
	LoanContract.due(l, bal, bal * r)
	check(absf(float(l["payment"]) - bal * r) < 0.01, "la cuota mensual es solo intereses sobre lo desembolsado")
	var guard := 0
	while not bool(b["re_project"]["stages"][1]["paid"]) and guard < 400:
		TimeManager.advance_days(1)
		guard += 1
	check(absf(float(l["disbursed"]) - total * 0.65 * 0.5) < 1.0, "al empezar la estructura desembolsa su parte")
	check(GameState.money < m0, "el jugador pone el resto y paga intereses")
	_finish(b, 900)
	check(b["status"] == "activo" and bool(l.get("closed", false)), "al terminar la obra el cupo se cierra")
	check(absf(float(l["disbursed"]) - total * 0.5) < 1.0, "se desembolsó el 50%% del costo en total")
	# Una venta abona al crédito.
	var bal2 := float(l["balance"])
	var u: Dictionary = b["units"][0]
	var fam := _family()
	fam[0].money = 1000000.0
	RealEstateSim._sell_unit(GameState, b, u, fam, float(u["price"]), {})
	check(float(l["balance"]) < bal2 or not GameState.loans.has(l), "cada venta abona al crédito constructor")


# --- 7. Tipos de crédito --------------------------------------------------------------------------------

func _test_loan_types() -> void:
	print("-- los 4 tipos de crédito con tablas correctas")
	var amount := 10000.0
	var rate := 0.12
	var months := 24
	for t in LoanContract.TYPES:
		var rows := LoanContract.schedule(amount, rate, months, t, 6)
		var tot := LoanContract.schedule_totals(rows)
		check(rows.size() == months, "%s: %d cuotas" % [t, rows.size()])
		check(absf(float(tot["principal"]) - amount) < 0.01, "%s: la suma de capital = monto" % t)
		check(float(rows[-1]["balance"]) < 0.01, "%s: saldo final 0" % t)
		var ok := true
		for row in rows:
			if absf(float(row["payment"]) - float(row["interest"]) - float(row["principal"])) > 0.001:
				ok = false
		check(ok, "%s: cuota = interés + capital en cada fila" % t)
	var fr := LoanContract.schedule(amount, rate, months, "frances")
	var pmt := BankSim.payment(amount, rate, months)
	check(fr.all(func(row): return absf(float(row["payment"]) - pmt) < 0.01), "francés: todas las cuotas = BankSim.payment() (%.2f)" % pmt)
	var al := LoanContract.schedule(amount, rate, months, "aleman")
	check(al.all(func(row): return absf(float(row["principal"]) - amount / months) < 0.01) and float(al[0]["payment"]) > float(al[-1]["payment"]), "alemán: abono constante y cuota decreciente")
	var bu := LoanContract.schedule(amount, rate, months, "bullet")
	check(absf(float(bu[0]["payment"]) - amount * rate / 12.0) < 0.01 and absf(float(bu[-1]["principal"]) - amount) < 0.01, "bullet: solo intereses y capital al final")
	var gr := LoanContract.schedule(amount, rate, months, "gracia", 6)
	check(float(gr[5]["principal"]) == 0.0 and float(gr[6]["principal"]) > 0.0, "gracia: 6 meses solo intereses y luego amortiza")
	var g_after := BankSim.payment(amount, rate, months - 6)
	check(absf(float(gr[10]["payment"]) - g_after) < 0.01, "gracia: después, cuota fija sobre el plazo restante")
	check(float(LoanContract.schedule_totals(bu)["interest"]) > float(LoanContract.schedule_totals(al)["interest"]), "bullet paga más intereses que alemán")


func _test_player_loans() -> void:
	print("-- contrato firmado, cobro mensual, anticipos y bancos")
	_town(509, 20000.0)
	var lenders := LoanContract.lenders(GameState)
	check(lenders.size() >= 3, "hay varios bancos para elegir (%d)" % lenders.size())
	var ext := LoanContract.lender(GameState, "externo")
	var com := LoanContract.lender(GameState, "comercial")
	check(float(com["rate"]) < float(ext["rate"]), "cada banco tiene su tasa (comercial %.1f%% < externo %.1f%%)" % [float(com["rate"]) * 100.0, float(ext["rate"]) * 100.0])
	var hip := LoanContract.lender(GameState, "hipotecario")
	check(str(hip["reason"]) != "", "el banco hipotecario no existe en la colonia")
	var q := LoanContract.quote(GameState, "comercial", 3000.0, 24, "aleman")
	check(q["error"] == "" and (q["rows"] as Array).size() == 24, "cotización con tabla antes de firmar")
	for t in LoanContract.TYPES:
		var r := LoanContract.sign_player_loan(GameState, "externo", 1000.0, 12, t, 3)
		check(r.has("loan"), "se firma un crédito %s" % t)
	var loans := BankSim.player_loans(GameState)
	var expected := 0.0
	for l in loans:
		var rows := LoanContract.schedule(float(l["principal"]), float(l["rate"]), int(l["term_months"]), str(l["type"]), int(l.get("grace", 0)))
		expected += float(rows[0]["payment"])
	var m0 := GameState.money
	BankSim.monthly(GameState)
	var charged := m0 - GameState.money
	check(absf(charged - expected) < 0.05, "cada mes se cobra la primera fila de cada tabla (%.2f vs %.2f)" % [charged, expected])
	var fr: Dictionary = loans.filter(func(l): return str(l["type"]) == "frances")[0]
	var bal := float(fr["balance"])
	check(LoanContract.prepay(GameState, int(fr["id"]), 300.0) == "" and absf(float(fr["balance"]) - (bal - 300.0)) < 0.01, "pago anticipado abona a capital")
	check(float(fr["payment"]) < BankSim.payment(1000.0, float(fr["rate"]), 12), "tras el abono la cuota baja")
	check(EconomySim.loans_granted(GameState) == 0.0, "las deudas del jugador con bancos NPC no cuentan como cartera propia")
	# Mora → embargo sigue funcionando.
	GameState.money = -10.0
	var bu: Dictionary = loans.filter(func(l): return str(l["type"]) == "bullet")[0]
	BankSim.monthly(GameState)
	check(int(bu["missed"]) >= 1, "si no paga entra en mora")


# --- 8. Hipoteca con tu banco ------------------------------------------------------------------------------

func _test_mortgage_player_bank() -> void:
	print("-- hipoteca de un ciudadano con el banco del jugador")
	_town(510)
	var r := ConstructionSim.start_construction(GameState, "banco", -32, 10, 0.0, "Banco Test", "sas")
	var bank: Dictionary = r["building"]
	_finish(bank)
	_staff_up(bank)
	BankSim.bank_settings(GameState, bank)
	bank["mortgage_rate"] = 0.09
	bank["lending"] = true
	check(BankSim.bank_capacity(GameState, bank) > 0, "el banco tiene capacidad de préstamo")
	var b := ConstructionSim.make_building(GameState, "vivienda", 4, 30, -14, 0.0, "jugador")
	GameState.add_building(b)
	RealEstateSim.ensure_units(GameState, b)
	RealEstateSim.set_all(b, "for_rent", false)
	for c in GameState.citizens.values():
		c.money = 0.0
	var fam := _family()
	var buyer: Citizen = fam[0]
	var u: Dictionary = b["units"][0]
	buyer.money = float(u["price"]) * 0.3
	buyer.job_kind = "empleo"
	buyer.wage = 8.0
	u["for_sale"] = true
	for m in fam:
		m.home_id = -1
	var pm := GameState.money
	var sold := false
	for i in range(40):
		RealEstateSim._market(GameState)
		if str(u["status"]) == "vendida":
			sold = true
			break
	check(sold, "la familia compra con hipoteca")
	var mort := {}
	for l in GameState.loans:
		if str(l.get("purpose", "")) == "hipoteca" and str(l["borrower"]) == str(buyer.id):
			mort = l
	check(not mort.is_empty() and str(mort["lender"]) == str(int(bank["id"])), "la hipoteca la otorga tu banco")
	check(not mort.is_empty() and is_equal_approx(float(mort["rate"]), 0.09), "con la tasa de tu banco")
	var price := float(u["price"])
	check(not mort.is_empty() and absf(GameState.money - pm - (price - float(mort["principal"]))) < 0.5, "recibes el precio menos lo que prestó tu banco")
	var i0 := BusinessSim.period_value(bank, "total", "intereses")
	buyer.money += 1000.0
	BankSim.monthly(GameState)
	check(BusinessSim.period_value(bank, "total", "intereses") > i0, "tu banco gana intereses de la hipoteca")
	check(EconomySim.loans_granted(GameState) > 0.0, "la hipoteca cuenta en tu cartera")
	# Sin tu banco: externo.
	bank["mortgages"] = false
	var off := LoanContract.mortgage_offer(GameState, 500.0, 300.0)
	check(str(off.get("lender", "")) == "externo", "si tu banco no otorga, lo hace el banco externo")
	# Impago → embargo de la unidad (vuelve a tu banco/edificio).
	BankSim._default(GameState, mort, str(buyer.id))
	check(str(u["status"]) == "disponible" and buyer.home_id != int(b["id"]), "si no paga, la unidad se embarga")


# --- 9. Guardado ---------------------------------------------------------------------------------------------

func _test_save_load() -> void:
	print("-- guardar y cargar")
	_town(511)
	var b := _project(4, 30, 14, {"credit_lender": "comercial", "credit_ratio": 0.4})
	RealEstateSim.set_all(b, "for_sale", true)
	RealEstateSim.set_unit_terms(b, 3, 9999.0, 77.0)
	LoanContract.sign_player_loan(GameState, "externo", 800.0, 24, "gracia", 4)
	TimeManager.advance_days(20)
	var d := GameState.to_dict()
	GameState.load_dict(JSON.parse_string(JSON.stringify(d)))
	var nb: Dictionary = GameState.get_building(int(b["id"]))
	check(nb.has("re_project") and (nb["units"] as Array).size() == 9, "el proyecto y sus unidades se guardan")
	check(float(nb["units"][3]["price"]) == 9999.0 and bool(nb["units"][3]["manual"]), "los precios fijados se guardan")
	var types := BankSim.player_loans(GameState).map(func(l): return str(l.get("type", "")))
	check(types.has("constructor") and types.has("gracia"), "los contratos se guardan con su tipo")
	check(GameState.realestate.has("demand"), "el estado de bienes raíces se guarda")
	TimeManager.advance_days(40)
	check(GameState.running, "la simulación sigue tras cargar")
	# Partida vieja sin realestate.
	d.erase("realestate")
	GameState.load_dict(JSON.parse_string(JSON.stringify(d)))
	check(is_equal_approx(RealEstateSim.demand(GameState), 1.0), "una partida vieja carga con valores por defecto")


# --- 10. 10 años ----------------------------------------------------------------------------------------------

func _test_ten_years() -> void:
	print("-- 10 años sin colapso")
	_town(512, 60000.0)
	var b := _project(4, 30, -14, {"credit_lender": "externo", "credit_ratio": 0.5})
	var b2 := ConstructionSim.make_building(GameState, "vivienda", 5, -34, -14, 0.0, "jugador")
	GameState.add_building(b2)
	RealEstateSim.ensure_units(GameState, b2)
	if not b.is_empty():
		for i in range(5):
			b["units"][i]["for_sale"] = true
	for i in range(12):
		b2["units"][i]["for_sale"] = true
	var pop0 := GameState.citizens.size()
	var t0 := Time.get_ticks_msec()
	var peak := 0
	for y in range(20):
		TimeManager.advance_days(182)
		if not GameState.running:
			break
		var occ := 0
		for bb in [b, b2]:
			if not bb.is_empty():
				var cc := RealEstateSim.counts(bb)
				occ += int(cc["arrendada"]) + int(cc["vendida"]) + int(cc["preventa"])
		peak = maxi(peak, occ)
	var ms := Time.get_ticks_msec() - t0
	var c := RealEstateSim.counts(b2)
	var c1 := RealEstateSim.counts(b) if not b.is_empty() else {}
	print("    10 años en %d ms · población %d→%d · dinero %s · demanda %.2f · edificio 5: %s · proyecto: %s" % [ms, pop0, GameState.citizens.size(), Fmt.money(GameState.money), RealEstateSim.demand(GameState), c, c1])
	print("    totales: ", GameState.realestate.get("total", {}))
	check(GameState.citizens.size() > 0, "el pueblo sigue vivo")
	check(is_finite(GameState.money), "el dinero es finito")
	check(b.is_empty() or b["status"] == "activo", "el proyecto terminó")
	check(peak > 0 and float(GameState.realestate.get("total", {}).get("rent", 0.0)) > 0.0, "las familias arriendan unidades (máximo %d ocupadas)" % peak)
	var bad := 0
	for bb in GameState.buildings:
		for u in bb.get("units", []):
			if not str(u["status"]) in RealEstateSim.STATUS_LABELS:
				bad += 1
			if str(u["status"]) == "arrendada" and not GameState.citizens.has(int(u["tenant_id"])):
				bad += 1
	check(bad == 0, "todas las unidades tienen un estado válido")
	var d := RealEstateSim.demand(GameState)
	check(d >= 0.89 and d <= 1.16, "la demanda se mantiene en su rango")
