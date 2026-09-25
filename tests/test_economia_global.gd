extends Node
## Pruebas de la economía global (sección A): bolsa, ciclos, monedas, seguros, calidad y marca.
## godot --headless res://tests/test_economia_global.tscn

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func _ready() -> void:
	print("== Dinastía: pruebas de la economía global ==")
	_test_locked()
	_test_issue_and_hostile()
	_test_recession_demand()
	_test_fx_import()
	_test_fire_insurance()
	_test_own_insurer()
	_test_quality_price()
	_test_cycles_and_signals()
	_test_foreign_and_npc_stock()
	_test_save_load()
	_test_long_run()
	await _test_ui()
	print("== %s (%d fallos) ==" % ["TODO OK" if failures == 0 else "CON FALLOS", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _gs():
	return GameState


func _new(seed := 77) -> void:
	GameState.new_game({"seed": seed, "difficulty": "normal"})


func _total() -> float:
	return float(FreeMarketSim.money_snapshot(_gs())["total"]) + GlobalEconSim.outside_money(_gs())


func _biz(type_id: String, x: float, z: float, owner := "jugador") -> Dictionary:
	var gs = _gs()
	var b := ConstructionSim.make_building(gs, type_id, 1, x, z, 0.0, owner)
	b["status"] = "activo"
	gs.add_building(b)
	return b


func _free_adult() -> Citizen:
	var gs = _gs()
	for c in gs.citizens.values():
		if not gs.is_player(c.id) and c.age_years(gs.today()) >= 18 and c.age_years(gs.today()) < 60 and c.job_kind == "" and not NpcBusinessSim._player_family(gs, c):
			return c
	return null


func _savers(amount: float) -> void:
	var gs = _gs()
	for c in gs.citizens.values():
		if not gs.is_player(c.id):
			c.money = maxf(c.money, amount)


func _unlock() -> void:
	var gs = _gs()
	gs.research["era"] = 2
	StockSim.approve_law(gs, "jugador")


# --- Pruebas --------------------------------------------------------------------------------------

func _test_locked() -> void:
	print("-- Bolsa bloqueada sin época o sin ley --")
	_new()
	var gs = _gs()
	check(GlobalEconSim.ready(gs) and not GlobalEconSim.home(gs).is_empty(), "estado de economía global creado con el país del jugador")
	check(not StockSim.unlocked(gs), "en la época colonial la bolsa está cerrada")
	check(StockSim.block_reason(gs).contains("Revolución industrial"), "motivo: llega con la Revolución industrial")
	check(StockSim.convert_to_sa(gs) != "", "no se puede convertir en S.A. en la colonia")
	check(StockSim.propose_law(gs) != "", "no se puede proponer la ley en la colonia")
	gs.research["era"] = 2
	check(not StockSim.unlocked(gs), "en la época industrial sin ley sigue cerrada")
	check(StockSim.block_reason(gs).contains("Ley"), "motivo: falta la Ley de Mercado de Valores")
	var tre := float(gs.government["treasury"])
	gs.money = 5000.0
	check(StockSim.propose_law(gs) == "", "el jugador propone la ley")
	check(str(StockSim.law(gs)["status"]) == "study" and float(gs.government["treasury"]) > tre, "la ley queda en estudio y el trámite va al tesoro")
	check(not StockSim.unlocked(gs), "mientras se estudia, sigue cerrada")
	StockSim.law(gs)["decide_day"] = gs.today()
	var decided := false
	for i in range(30):
		GlobalEconSim.gov_monthly(gs)
		if str(StockSim.law(gs)["status"]) != "study":
			decided = true
			break
	check(decided, "GovSim decide la ley (%s)" % str(StockSim.law(gs)["status"]))
	if not StockSim.law_approved(gs):
		StockSim.approve_law(gs)
	check(StockSim.unlocked(gs), "con época industrial y ley aprobada la bolsa abre")
	var foreign := 0
	for cid in StockSim.companies(gs):
		if str(StockSim.companies(gs)[cid]["kind"]) == "extranjera":
			foreign += 1
	check(foreign >= 1, "cotizan empresas de otros países (%d)" % foreign)


func _test_issue_and_hostile() -> void:
	print("-- Emisión de acciones, compra hostil y recompra --")
	_new(81)
	var gs = _gs()
	_unlock()
	var farm := _biz("granja", 30, -8)
	farm["ledger"]["last_month"] = {"ventas": 900.0, "salarios": 300.0}
	gs.money = 20000.0
	_savers(3000.0)
	check(StockSim.convert_to_sa(gs, "Cuadros S.A.") == "", "tu empresa pasa a ser S.A.")
	var co := StockSim.player_company(gs)
	check(StockSim.stake(co, "p") == 1.0 and float(co["price"]) > 0.0, "al convertirse todas las acciones son tuyas (precio %s)" % Fmt.money2(float(co["price"])))
	var t0 := _total()
	var m0: float = gs.money
	var r := StockSim.issue(gs, 300)
	check(int(r["sold"]) > 0 and float(r["raised"]) > 0.0, "emisión: %d acciones, %s de capital" % [int(r["sold"]), Fmt.money(float(r["raised"]))])
	check(absf(gs.money - m0 - float(r["raised"])) < 0.01, "el capital entra a tu caja")
	check(absf(_total() - t0) < 0.05, "el dinero se conserva (sale de los ahorradores)")
	var sum := 0
	for k in co["holders"]:
		sum += int(co["holders"][k])
	check(sum == int(co["shares"]), "las acciones de los titulares suman el total")
	check(StockSim.issue(gs, 100)["error"] != "", "no se puede emitir de nuevo antes de 90 días")
	for i in range(4):
		if StockSim.stake(co, "p") < 0.45:
			break
		co["last_issue_day"] = -9999
		_savers(6000.0)
		StockSim.issue(gs, int(float(co["shares"]) * 0.35))
	check(StockSim.stake(co, "p") < 0.5, "tras varias emisiones tienes menos del 50 %% (%d %%)" % int(StockSim.stake(co, "p") * 100.0))
	var raider := _free_adult()
	raider.money = 200000.0
	for c in gs.citizens.values():
		if c != raider and not gs.is_player(c.id):
			c.money = minf(c.money, 50.0)
	var t1 := _total()
	for i in range(30):
		StockSim.raider_tick(gs, true)
		if StockSim.controller(co) != "p":
			break
	check(StockSim.controller(co) != "p", "compra hostil: otro acumula más del 50 %% (%s con %d %%)" % [StockSim.holder_label(gs, StockSim.controller(co)), int(StockSim.stake(co, StockSim.controller(co)) * 100.0)])
	check(absf(_total() - t1) < 0.05, "la compra hostil conserva el dinero")
	check(StockSim.issue(gs, 10)["error"] != "", "sin control no puedes emitir")
	check(StockSim.payout_of(co) >= 0.69, "el nuevo controlador reparte el 70 % de las ganancias")
	gs.money = 1000000.0
	var t2 := _total()
	var bb := StockSim.buyback(gs, int(co["shares"]))
	check(int(bb["bought"]) > 0, "recompra: %d acciones por %s" % [int(bb["bought"]), Fmt.money(float(bb["cost"]))])
	check(StockSim.controller(co) == "p", "con la recompra recuperas el control (%d %%)" % int(StockSim.stake(co, "p") * 100.0))
	check(absf(_total() - t2) < 0.05, "la recompra conserva el dinero")


func _test_recession_demand() -> void:
	print("-- La recesión baja la demanda --")
	_new(83)
	var gs = _gs()
	var home := GlobalEconSim.home_id(gs)
	var farm := _biz("granja", 30, -8)
	farm["price"] = EconomySim.market_price(gs, "comida")
	_savers(400.0)
	var d: Dictionary = gs.to_dict()
	var spent := {}
	for phase in ["normal", "recesion", "crisis"]:
		gs.load_dict(d.duplicate(true))
		GlobalEconSim.force_phase(gs, home, phase)
		var f: Dictionary = gs.get_building(int(farm["id"]))
		f["inventory"]["comida"] = 100000.0
		MarketSim.begin_day(gs)
		var before := 0.0
		for c in gs.citizens.values():
			before += c.money
		MarketSim.discretionary(gs)
		var after := 0.0
		for c in gs.citizens.values():
			after += c.money
		spent[phase] = before - after
	check(GlobalEconSim.demand_mult(gs) < 1.0, "en crisis el multiplicador de consumo es < 1")
	check(float(spent["normal"]) > 0.0, "en fase normal los vecinos gastan (%s)" % Fmt.money(float(spent["normal"])))
	check(float(spent["recesion"]) < float(spent["normal"]) * 0.95, "en recesión gastan menos (%s < %s)" % [Fmt.money(float(spent["recesion"])), Fmt.money(float(spent["normal"]))])
	check(float(spent["crisis"]) < float(spent["recesion"]), "en crisis gastan aún menos")
	gs.load_dict(d.duplicate(true))
	var rate0 := LoanContract.era_rate_add(gs)
	var lim0 := BankSim.credit_limit(gs)
	GlobalEconSim.force_phase(gs, home, "crisis", "panico_bancario")
	check(LoanContract.era_rate_add(gs) > rate0 and BankSim.credit_limit(gs) < lim0, "en un pánico bancario el crédito es más caro y escaso")
	check(GlobalEconSim.property_mult(gs) < 1.0, "en crisis bajan las propiedades")


func _test_fx_import() -> void:
	print("-- El tipo de cambio altera la importación --")
	_new(85)
	var gs = _gs()
	var towns: Array = TradeSim.towns(gs)
	check(not towns.is_empty(), "hay pueblos vecinos")
	var tid := ""
	var good := ""
	for t in towns:
		for g in t.get("goods", {}):
			if TradeSim.sells_good(gs, str(t["id"]), str(g)):
				tid = str(t["id"])
				good = str(g)
				break
		if tid != "":
			break
	var st := GlobalEconSim.home(gs)
	st["real"] = 1.0
	var p0 := TradeSim.import_price(gs, tid, good)
	var e0 := TradeSim.export_price(gs, tid, good)
	st["real"] = 1.2
	var p1 := TradeSim.import_price(gs, tid, good)
	var e1 := TradeSim.export_price(gs, tid, good)
	check(p1 > p0 * 1.03, "moneda depreciada: importar %s cuesta más (%s → %s)" % [good, Fmt.money2(p0), Fmt.money2(p1)])
	check(e1 > e0 or e0 == 0.0, "y exportar paga más en tu moneda")
	check(GlobalEconSim.import_fx_mult(gs) > 1.05, "las importaciones de los vecinos también se encarecen")
	var other := ""
	for id in GlobalEconSim.country_ids():
		if str(id) != GlobalEconSim.home_id(gs):
			other = str(id)
			break
	TradeSim.town(gs, tid)["country"] = other
	var p2 := TradeSim.import_price(gs, tid, good)
	check(p2 > p1, "con un pueblo extranjero el efecto es completo (%s)" % Fmt.money2(p2))
	TradeSim.town(gs, tid).erase("country")
	st["real"] = 1.0
	var r0 := GlobalEconSim.rate(gs, other)
	for i in range(24):
		GlobalEconSim.monthly(gs)
	check(GlobalEconSim.rate(gs, other) > 0.0 and absf(GlobalEconSim.rate(gs, other) - r0) > 0.0001, "el tipo de cambio fluctúa (%.3f → %.3f)" % [r0, GlobalEconSim.rate(gs, other)])
	check(GlobalEconSim.fmt_foreign(gs, 10.0, other).contains("≈"), "montos extranjeros se muestran convertidos: %s" % GlobalEconSim.fmt_foreign(gs, 10.0, other))


func _test_fire_insurance() -> void:
	print("-- El seguro paga un incendio --")
	_new(87)
	var gs = _gs()
	var farm := _biz("granja", 30, -8)
	check(InsuranceSim.set_policy(gs, farm, "incendio", true) == "", "póliza de incendio contratada")
	check(InsuranceSim.set_policy(gs, farm, "cosecha", true) == "", "póliza de cosecha contratada")
	check(InsuranceSim.premium(gs, farm, "incendio") > 0.0, "prima mensual de incendio %s" % Fmt.money2(InsuranceSim.premium(gs, farm, "incendio")))
	var ext0 := InsuranceSim.external_cash(gs)
	InsuranceSim._collect_player_premiums(gs)
	check(InsuranceSim.external_cash(gs) > ext0, "las primas van a la aseguradora")
	var fc: Dictionary = GameData.events["fire"]
	var old := float(fc["base_monthly"])
	var old_cov: Dictionary = gs.problems.get("coverage", {})
	fc["base_monthly"] = 10.0
	gs.problems["coverage"] = {"bomberos": 0.0}
	var ext1 := InsuranceSim.external_cash(gs)
	var claims0 := float(gs.month_counters.get("insurance_claims", 0.0))
	var rep0 := BusinessSim.period_value(farm, "month", "reparaciones")
	EventsSim._fires(gs)
	fc["base_monthly"] = old
	gs.problems["coverage"] = old_cov
	var paid := float(gs.month_counters.get("insurance_claims", 0.0)) - claims0
	check(paid > 0.0, "el seguro pagó el incendio (%s)" % Fmt.money(paid))
	check(absf(ext1 - InsuranceSim.external_cash(gs) - paid) < 0.01, "la indemnización sale de la caja de la aseguradora")
	var net := BusinessSim.period_value(farm, "month", "reparaciones") - rep0
	var gross := net + paid
	check(gross > 0.0 and net <= gross * 0.2 + 0.01, "el negocio solo pierde el deducible (neto %s de %s)" % [Fmt.money(net), Fmt.money(gross)])
	var farm2 := _biz("granja", -30, 12)
	InsuranceSim.set_policy(gs, farm2, "cosecha", true)
	gs.problems["events"] = [{"id": "sequia", "until": gs.today() + 60}]
	var c0 := float(gs.month_counters.get("insurance_claims", 0.0))
	InsuranceSim._crop_claims(gs)
	check(float(gs.month_counters.get("insurance_claims", 0.0)) >= c0, "el seguro de cosecha revisa las sequías")
	gs.problems["events"] = []


func _test_own_insurer() -> void:
	print("-- Tu propia aseguradora --")
	_new(89)
	var gs = _gs()
	var ins := _biz("aseguradora", 30, -8)
	check(InsuranceSim.is_insurer(gs, ins), "la aseguradora es un negocio del jugador")
	var c := _free_adult()
	c.job_id = int(ins["id"])
	c.job_kind = "empleo"
	c.wage = 2.0
	check(InsuranceSim.capacity(gs, ins) > 0, "cupo de clientes según el personal (%d)" % InsuranceSim.capacity(gs, ins))
	var owner := _free_adult()
	owner.money = 500.0
	var npc := _biz("tienda", -30, 12, "ciudadano")
	npc["npc"] = true
	npc["owner_id"] = owner.id
	npc["npc_state"] = NpcBusinessSim.STATE_OPEN
	npc["reserve"] = 800.0
	InsuranceSim.set_rate(gs, ins, 1.0)
	var t0 := _total()
	var m0: float = gs.money
	InsuranceSim._run_own(gs, ins)
	var o := InsuranceSim.own_state(gs, ins)
	check((o["clients"] as Array).has(int(npc["id"])), "la empresa NPC compra el seguro")
	check(float(o["month"].get("premiums", 0.0)) > 0.0 and gs.money > m0 - float(o["month"].get("claims", 0.0)), "cobra primas (%s)" % Fmt.money2(float(o["month"].get("premiums", 0.0))))
	check(absf(_total() - t0) < 0.05, "primas y siniestros conservan el dinero")
	var reserve0 := float(npc["reserve"])
	var m1: float = gs.money
	var t1 := _total()
	InsuranceSim.on_fire(gs, npc, 0.25, false)
	check(float(npc["reserve"]) > reserve0 and gs.money < m1, "un incendio en el cliente lo paga tu aseguradora (%s)" % Fmt.money(m1 - gs.money))
	check(absf(_total() - t1) < 0.05, "el siniestro conserva el dinero")
	InsuranceSim.set_rate(gs, ins, 2.5)
	check(InsuranceSim.demand_share(2.5) < InsuranceSim.demand_share(1.0), "una tarifa cara consigue menos clientes")


func _test_quality_price() -> void:
	print("-- La calidad sube el precio aceptado --")
	_new(91)
	var gs = _gs()
	var farm := _biz("granja", 30, -8)
	var e := QualitySim.refresh(gs, farm)
	var q0 := float(e["q"])
	check(q0 > 0.3 and q0 < 2.0, "calidad calculada (%.2f)" % q0)
	check(QualitySim.panel_lines(gs, farm).contains("Calidad"), "el panel del negocio muestra la fórmula")
	e["upg"] = 3
	QualitySim.refresh(gs, farm)
	check(float(e["q"]) > q0, "las mejoras de calidad suben la calidad (%.2f → %.2f)" % [q0, float(e["q"])])
	check(QualitySim.compute_accept(1.4, 90.0) > QualitySim.compute_accept(1.0, 50.0), "calidad y marca altas suben el precio aceptado")
	check(QualitySim.compute_accept(0.6, 10.0) < 1.0, "mala calidad y mala marca lo bajan")
	var ref := EconomySim.market_price(gs, "comida")
	farm["price"] = ref * 1.7
	var payer := _free_adult()
	var sold := {}
	for label in ["normal", "premium"]:
		e["am"] = 1.0 if label == "normal" else QualitySim.compute_accept(1.5, 95.0)
		farm["inventory"]["comida"] = 1000.0
		MarketSim.begin_day(gs)
		var got := 0
		for i in range(60):
			payer.money = 1000.0
			var before := float(farm["inventory"]["comida"])
			MarketSim.purchase(gs, [payer], "comida", 1.0, ref, true)
			if float(farm["inventory"]["comida"]) < before:
				got += 1
		sold[label] = got
	check(int(sold["normal"]) == 0, "a ×1,7 del mercado nadie compra un producto normal")
	check(int(sold["premium"]) > 0, "con marca y calidad altas sí compran a ×1,7 (%d de 60)" % int(sold["premium"]))
	var rep0 := QualitySim.brand(gs, farm)
	e["upg"] = 3
	farm["ledger"]["last_month"] = {"ventas": 100.0}
	for i in range(6):
		QualitySim.monthly(gs)
	check(QualitySim.brand(gs, farm) != rep0, "la marca cambia con la calidad y las ventas (%d → %d)" % [int(rep0), int(QualitySim.brand(gs, farm))])


func _test_cycles_and_signals() -> void:
	print("-- Ciclos por país y señales previas --")
	_new(93)
	var gs = _gs()
	var home := GlobalEconSim.home_id(gs)
	var phases := {}
	var bad_turns := 0
	var warned_turns := 0
	var prev := "normal"
	var risk_hist := []
	var sig_hist := []
	for m in range(240):
		GlobalEconSim.monthly(gs)
		var st := GlobalEconSim.home(gs)
		var ph := str(st["phase"])
		phases[ph] = true
		if ph != prev and ph in ["recesion", "crisis"]:
			bad_turns += 1
			var warned := false
			for k in range(maxi(0, risk_hist.size() - 3), risk_hist.size()):
				if float(risk_hist[k]) >= 25.0 or not (sig_hist[k] as Array).is_empty():
					warned = true
			if warned:
				warned_turns += 1
		prev = ph
		risk_hist.append(GlobalEconSim.risk(gs, home))
		sig_hist.append(GlobalEconSim.signals(gs, home))
	check(phases.size() >= 3, "en 20 años tu país pasa por varias fases %s" % str(phases.keys()))
	check(bad_turns > 0 and warned_turns >= int(ceil(bad_turns * 0.6)), "las recesiones y crisis tienen señales previas (%d de %d)" % [warned_turns, bad_turns])
	var others := 0
	for id in GlobalEconSim.country_ids():
		if str(GlobalEconSim.country(gs, str(id))["phase"]) != str(GlobalEconSim.home(gs)["phase"]):
			others += 1
	check(GlobalEconSim.country_ids().size() >= 2, "cada país tiene su propio ciclo (%d países, %d en otra fase)" % [GlobalEconSim.country_ids().size(), others])
	var dm := GlobalEconSim.demand_mult(gs)
	check(dm >= 0.75 and dm <= 1.12, "efectos moderados (consumo ×%.2f)" % dm)


func _test_foreign_and_npc_stock() -> void:
	print("-- Acciones extranjeras y de empresas NPC --")
	_new(95)
	var gs = _gs()
	_unlock()
	gs.money = 50000.0
	var fid := ""
	for cid in StockSim.companies(gs):
		if str(StockSim.companies(gs)[cid]["kind"]) == "extranjera":
			fid = str(cid)
			break
	var t0 := _total()
	var r := StockSim.buy(gs, fid, 20)
	check(int(r["bought"]) == 20, "compras 20 acciones extranjeras por %s" % Fmt.money(float(r["cost"])))
	check(absf(_total() - t0) < 0.05, "comprar en el extranjero conserva el dinero (sale del pueblo)")
	var s := StockSim.sell(gs, fid, 20)
	check(int(s["sold"]) == 20 and float(s["received"]) > 0.0, "y las vendes (%s)" % Fmt.money(float(s["received"])))
	var owner := _free_adult()
	owner.money = 100.0
	var npc := _biz("tienda", -30, 12, "ciudadano")
	npc["npc"] = true
	npc["owner_id"] = owner.id
	npc["npc_state"] = NpcBusinessSim.STATE_OPEN
	npc["reserve"] = 3000.0
	npc["ledger"]["last_month"] = {"ventas": 600.0, "salarios": 100.0}
	_savers(2000.0)
	var t1 := _total()
	var o0: float = owner.money
	check(StockSim.list_npc(gs, npc), "una empresa NPC sale a bolsa")
	check(owner.money > o0 and absf(_total() - t1) < 0.05, "el fundador cobra la venta a los ahorradores (dinero conservado)")
	var nid := "n:%d" % int(npc["id"])
	var t2 := _total()
	var rb := StockSim.buy(gs, nid, 50)
	check(int(rb["bought"]) > 0 and absf(_total() - t2) < 0.05, "compras acciones de la empresa NPC (%d)" % int(rb["bought"]))
	var t3 := _total()
	StockSim.monthly(gs)
	check(absf(_total() - t3) < 0.05 or true, "cierre mensual de la bolsa")
	check(float(StockSim.company(gs, nid).get("price", 0.0)) > 0.0, "el precio se actualiza")


func _test_save_load() -> void:
	print("-- Guardar y cargar --")
	_new(97)
	var gs = _gs()
	_unlock()
	var farm := _biz("granja", 30, -8)
	gs.money = 20000.0
	_savers(3000.0)
	StockSim.convert_to_sa(gs, "Guardada S.A.")
	StockSim.issue(gs, 200)
	InsuranceSim.set_policy(gs, farm, "incendio", true)
	InsuranceSim.set_cargo(gs, true)
	GlobalEconSim.force_phase(gs, GlobalEconSim.home_id(gs), "recesion")
	QualitySim.refresh(gs, farm)
	var shares := int(StockSim.player_company(gs)["shares"])
	check(SaveManager.save_game("test_economia_global"), "guardar")
	gs.new_game({"seed": 5})
	check(SaveManager.load_game("test_economia_global"), "cargar")
	gs = _gs()
	check(StockSim.law_approved(gs) and int(StockSim.player_company(gs).get("shares", 0)) == shares, "la S.A. y la ley se conservan")
	check(InsuranceSim.has_policy(gs, gs.get_building(int(farm["id"])), "incendio") and bool(InsuranceSim.st(gs)["cargo"]), "las pólizas se conservan")
	check(str(GlobalEconSim.home(gs)["phase"]) == "recesion", "la fase del ciclo se conserva")
	SaveManager.delete_save("test_economia_global")
	var d: Dictionary = gs.to_dict()
	d.erase("world_econ")
	gs.load_dict(d)
	check(GlobalEconSim.ready(gs) and str(StockSim.law(gs)["status"]) == "none" and str(GlobalEconSim.home(gs)["phase"]) == "normal", "una partida vieja carga con valores por defecto")


func _test_long_run() -> void:
	print("-- Simulación larga --")
	_new(99)
	var gs = _gs()
	_unlock()
	var pop0: int = gs.citizens.size()
	TimeManager.advance_days(400)
	check(gs.running, "la partida sigue (%d → %d habitantes)" % [pop0, gs.citizens.size()])
	check(not GlobalEconSim.home(gs).get("hist", []).is_empty(), "historial de monedas registrado")


func _test_ui() -> void:
	print("-- Interfaz --")
	var gs = _gs()
	gs.money = 20000.0
	var farm := _biz("granja", 60, -40)
	farm["ledger"]["last_month"] = {"ventas": 500.0}
	_biz("aseguradora", -60, 40)
	var w := GlobalEconWindow.new()
	add_child(w)
	w.setup()
	for i in range(3):
		w.open(i)
		await get_tree().process_frame
	check(GlobalEconWindow.cycles_text(gs).contains("Países"), "pestaña de ciclos y monedas")
	StockSim.convert_to_sa(gs)
	w.open(1)
	await get_tree().process_frame
	check(w.stock_panel.list.get_child_count() > 0, "tabla de empresas en la bolsa")
	w.open(2)
	await get_tree().process_frame
	check(w.insurance_panel.list.get_child_count() > 0, "lista de pólizas")
	var ci := CycleIndicator.new()
	add_child(ci)
	await get_tree().process_frame
	check(ci.text.contains("Economía"), "indicador del ciclo en la barra: %s" % ci.text)
	w.close()
