extends Node
## Pruebas de la sección E (impuestos, efectivo y mercado negro): IVA, efectivo/banco, ventas no
## declaradas con gente de confianza, sueldos en negro, negocios ocultos con investigación,
## inspecciones, decomiso, soborno, guardado y panel "Efectivo y riesgo".
## godot --headless res://tests/test_efectivo.tscn

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func _ready() -> void:
	print("== Sección E: efectivo, IVA y mercado negro ==")
	_test_sales_tax()
	_test_cash_bank()
	_test_undeclared_trust()
	_test_contract_undeclared()
	_test_black_wages()
	_test_hidden_blocked()
	_test_hidden_production_sales()
	_test_inspection_seizure()
	_test_bribe()
	_test_save_load()
	await _test_ui()
	print("== %s (%d fallos) ==" % ["TODO OK" if failures == 0 else "CON FALLOS", failures])
	get_tree().quit(1 if failures > 0 else 0)


# --- Utilidades ----------------------------------------------------------------------------------

func _new_town(seed_v: int) -> void:
	GameState.new_game({"seed": seed_v, "difficulty": "normal"})
	GameState.money = 20000.0


func _total() -> float:
	var gs := GameState
	var m := gs.money + float(gs.government.get("treasury", 0.0))
	for c in gs.citizens.values():
		m += c.money
	for b in gs.buildings:
		m += float(b.get("reserve", 0.0))
	return m


func _farm() -> Dictionary:
	var b := ConstructionSim.make_building(GameState, "granja", 1, 40.0, -30.0, 0.0, "jugador")
	GameState.add_building(b)
	return b


func _befriend(n: int) -> void:
	var added := 0
	for c in GameState.citizens.values():
		if added >= n:
			break
		if GameState.is_player(c.id):
			continue
		PlayerSim._add_affinity(GameState, c.id, 80.0)
		added += 1
	GameState.informal["trusted_day"] = -1


# --- 1. Impuesto a la venta ------------------------------------------------------------------------

func _test_sales_tax() -> void:
	_new_town(501)
	var gs := GameState
	var b := _farm()
	var rate := MoneySim.sales_tax_rate(gs)
	check(rate > 0.0 and rate < 0.1, "tasa de %s de la época y el gobierno: %.1f%%" % [MoneySim.sales_tax_label(gs), rate * 100.0])
	var m0 := gs.money
	BusinessSim.earn(gs, b, 1000.0, "ventas")
	check(is_equal_approx(gs.money, m0 + 1000.0), "la venta declarada entra completa al banco")
	check(is_equal_approx(float(b.get("iva_due", 0.0)), 1000.0 * rate), "IVA causado por la venta: %s" % Fmt.money2(float(b.get("iva_due", 0.0))))
	BusinessSim.earn(gs, b, 100.0, "alquileres")
	check(is_equal_approx(float(b.get("iva_due", 0.0)), 1000.0 * rate), "los alquileres no causan IVA")
	var t0 := float(gs.government["treasury"])
	var totals := {}
	MoneySim.collect_sales_tax(gs, totals)
	GovSim.add_treasury(gs, float(totals["iva"]))
	t0 += float(totals["iva"])
	check(is_equal_approx(float(totals["iva"]), 1000.0 * rate) and is_equal_approx(float(gs.government["treasury"]) - t0, 0.0), "collect_sales_tax devuelve el total (GovSim lo suma al tesoro)")
	check(is_equal_approx(BusinessSim.period_value(b, "month", "iva"), 1000.0 * rate), "el IVA aparece en el libro contable del negocio")
	# Ciclo completo por el gobierno.
	BusinessSim.earn(gs, b, 500.0, "ventas")
	var total0 := _total()
	var tr0 := float(gs.government["treasury"])
	GovSim._collect_taxes(gs)
	check(float(gs.government["taxes_last"].get("iva", 0.0)) > 0.0 and float(gs.government["treasury"]) > tr0, "el gobierno cobra el IVA con los demás impuestos (%s)" % Fmt.money2(float(gs.government["taxes_last"].get("iva", 0.0))))
	check(absf(_total() - total0) < 0.05, "IVA: dinero conservado (va al tesoro)")


# --- 2. Efectivo y banco -----------------------------------------------------------------------------

func _test_cash_bank() -> void:
	_new_town(502)
	var gs := GameState
	var total0 := _total()
	check(is_equal_approx(MoneySim.cash(gs), 0.0) and is_equal_approx(MoneySim.bank(gs), gs.money), "al empezar todo está en el banco")
	check(MoneySim.withdraw(gs, 1000.0) == "" and is_equal_approx(MoneySim.cash(gs), 1000.0) and is_equal_approx(gs.money, 20000.0), "retiro: pasa al efectivo, el total no cambia")
	check(MoneySim.withdraw(gs, 999999.0) != "", "no se retira más de lo que hay en el banco")
	var r0 := MoneySim.risk(gs)
	check(MoneySim.deposit(gs, 100.0) == "" and is_equal_approx(MoneySim.risk(gs), r0), "depósito pequeño: sin sospecha")
	MoneySim.withdraw(gs, 8000.0)
	check(MoneySim.deposit(gs, 8000.0) == "" and MoneySim.risk(gs) > r0, "depositar mucho efectivo levanta sospechas (riesgo %.1f)" % MoneySim.risk(gs))
	# Pagos en efectivo (proveedores informales, sueldos en negro).
	var c0 := MoneySim.cash(gs)
	check(MoneySim.pay_cash(gs, 50.0) and is_equal_approx(MoneySim.cash(gs), c0 - 50.0), "efectivo usado para pagar")
	check(not MoneySim.pay_cash(gs, 1e9), "sin efectivo suficiente no se paga en efectivo")
	PoliticsSim.spread_to_citizens(gs, 50.0)
	check(absf(_total() - total0) < 0.01, "dinero total conservado entre efectivo y banco")
	# Banco en rojo: el efectivo lo cubre.
	gs.add_money(-(MoneySim.bank(gs) + 100.0))
	MoneySim.daily(gs)
	check(MoneySim.bank(gs) >= -0.01 and MoneySim.cash(gs) >= 0.0, "si el banco queda en rojo, el efectivo lo cubre")


# --- 3. Ventas no declaradas: solo con confianza ----------------------------------------------------------

func _test_undeclared_trust() -> void:
	_new_town(503)
	var gs := GameState
	var b := _farm()
	gs.player["relations"] = {}
	gs.informal["trusted_day"] = -1
	var fam := HeirsSim.family_members(gs).size()
	if fam == 0:
		check(MoneySim.set_undeclared(gs, b, true) != "" and not bool(b.get("undeclared", false)), "sin personas de confianza no se puede vender sin declarar")
	_befriend(4)
	check(MoneySim.undeclared_share(gs) > 0.0, "con 4 amigos de confianza hay ventas sin factura (%d%%)" % int(MoneySim.undeclared_share(gs) * 100.0))
	check(MoneySim.set_undeclared(gs, b, true) == "" and bool(b["undeclared"]), "casilla 'no declarar' activada")
	var total0 := _total()
	var share := MoneySim.undeclared_share(gs)
	var cash0 := MoneySim.cash(gs)
	var r0 := MoneySim.risk(gs)
	BusinessSim.earn(gs, b, 1000.0, "ventas")
	check(is_equal_approx(MoneySim.cash(gs) - cash0, 1000.0 * share), "la parte no declarada entra en efectivo (%s)" % Fmt.money(MoneySim.cash(gs) - cash0))
	check(is_equal_approx(float(b.get("iva_due", 0.0)), 1000.0 * (1.0 - share) * MoneySim.sales_tax_rate(gs)), "sin IVA sobre lo no declarado")
	check(is_equal_approx(BusinessSim.period_value(b, "month", "ventas"), 1000.0 * (1.0 - share)), "el libro oficial solo muestra lo declarado (sin impuesto a la ganancia sobre el resto)")
	check(MoneySim.risk(gs) > r0, "cada venta no declarada suma riesgo")
	check(absf(_total() - total0 - 1000.0) < 0.01, "venta no declarada: el total del jugador sube exactamente lo vendido")


func _test_contract_undeclared() -> void:
	_new_town(504)
	var gs := GameState
	var npc := ConstructionSim.make_building(gs, "lenador", 1, -40.0, 30.0, 0.0, "ciudadano")
	npc["npc"] = true
	npc["reserve"] = 5000.0
	gs.add_building(npc)
	var key := "npc:%d" % int(npc["id"])
	var k := {"id": 999, "dir": "venta", "client": key, "client_name": "Leñador", "paid": 0.0, "owed": 0.0}
	gs.market["reputation"][key] = 40.0
	check(MoneySim.set_contract_undeclared(gs, k, true) != "" and not bool(k.get("undeclared", false)), "contrato: con reputación baja la contraparte exige factura")
	check(MoneySim.set_contract_undeclared(gs, {"client": "gov", "dir": "venta"}, true) != "", "el gobierno nunca acepta sin factura")
	gs.market["reputation"][key] = 85.0
	check(MoneySim.set_contract_undeclared(gs, k, true) == "", "contrato: con reputación alta acepta no declarar")
	var total0 := _total()
	var cash0 := MoneySim.cash(gs)
	var iva0 := MoneySim.iva_pending(gs)
	ContractSim._collect(gs, k, 300.0)
	check(is_equal_approx(MoneySim.cash(gs) - cash0, 300.0) and is_equal_approx(MoneySim.iva_pending(gs), iva0), "cobro del contrato en efectivo y sin IVA")
	check(absf(_total() - total0) < 0.01, "contrato no declarado: dinero conservado")
	k["undeclared"] = false
	ContractSim._collect(gs, k, 300.0)
	check(MoneySim.iva_pending(gs) > iva0, "contrato declarado: causa IVA")


func _test_black_wages() -> void:
	_new_town(505)
	var gs := GameState
	var b := _farm()
	b["status"] = "activo"
	var c: Citizen = null
	for x in gs.citizens.values():
		if not gs.is_player(x.id) and x.age_years(gs.today()) >= 18 and x.job_id < 0:
			c = x
			break
	c.job_id = int(b["id"])
	c.job_kind = "empleo"
	c.wage = 10.0
	MoneySim.withdraw(gs, 500.0)
	MoneySim.set_black_wages(gs, b, true)
	var money0 := c.money
	var cash0 := MoneySim.cash(gs)
	BusinessSim.produce(gs)
	check(MoneySim.cash(gs) < cash0 and c.money - money0 < 10.0 and c.money - money0 > 0.0, "sueldo en negro pagado en efectivo y con descuento (%s)" % Fmt.money2(c.money - money0))
	check(is_equal_approx(BusinessSim.period_value(b, "month", "salarios"), 0.0), "no entra en la nómina (sin impuesto de nómina)")


# --- 4. Mercado negro ------------------------------------------------------------------------------------

func _test_hidden_blocked() -> void:
	_new_town(506)
	var gs := GameState
	MoneySim.withdraw(gs, 5000.0)
	var why := MoneySim.open_hidden(gs, "destileria_clandestina")
	check(why != "" and MoneySim.active_hidden(gs).is_empty(), "negocio oculto bloqueado sin tecnología (%s)" % why)
	check(GameData.technologies.has("destileria_clandestina") and str(GameData.technologies["destileria_clandestina"].get("branch", "")) == "informal", "tecnologías del mercado negro en su propia rama del árbol")
	var branches: Array = GameData.eras.get("branches", []).map(func(x): return str(x[0]))
	var ok := true
	for id in GameData.extra("technologies_negro"):
		if str(id).begins_with("_"):
			continue
		var t: Dictionary = GameData.technologies.get(id, {})
		ok = ok and branches.has(str(t.get("branch", "")))
		for r in t.get("requires", []):
			ok = ok and GameData.technologies.has(r) and int(GameData.technologies[r].get("era", 1)) <= int(t.get("era", 1))
	check(ok, "tecnologías del mercado negro con prerrequisitos válidos")
	for tid in MoneySim.hidden_ids():
		check(GameData.technologies.has(str(MoneySim.hidden_type(tid).get("tech", ""))), "%s requiere una tecnología existente" % tid)


func _test_hidden_production_sales() -> void:
	_new_town(507)
	var gs := GameState
	gs.techs.append("economia_informal")
	gs.techs.append("destileria_clandestina")
	for c in gs.citizens.values():
		if not gs.is_player(c.id):
			c.money += 300.0   # Vecinos con ahorros de sobra: demanda.
	check(MoneySim.open_hidden(gs, "destileria_clandestina") != "", "el montaje exige efectivo")
	MoneySim.withdraw(gs, 3000.0)
	var total0 := _total()
	check(MoneySim.open_hidden(gs, "destileria_clandestina") == "" and MoneySim.active_hidden(gs).size() == 1, "con la tecnología y efectivo se monta la destilería clandestina")
	var h: Dictionary = MoneySim.active_hidden(gs)[0]
	var cash_after_setup := MoneySim.cash(gs)
	for i in range(6):
		MoneySim._hidden_daily(gs)
	check(float(h["stock"]) > 0.0 and MoneySim.cash(gs) < cash_after_setup, "produce aguardiente clandestino pagando jornaleros e insumos en efectivo (%d u.)" % int(h["stock"]))
	var cash0 := MoneySim.cash(gs)
	var bank0 := MoneySim.bank(gs)
	MoneySim._hidden_sales(gs)
	check(float(h["sold_total"]) > 0.0 and MoneySim.cash(gs) > cash0, "vende solo en efectivo con demanda propia (%s)" % Fmt.money(float(h["sold_total"])))
	check(is_equal_approx(MoneySim.bank(gs), bank0), "la venta oculta no pasa por el banco")
	check(MoneySim.hidden_price(gs, "destileria_clandestina") > float(GameData.goods.get("comida", {}).get("base_price", 1.0)) * gs.price_mult(), "precios altos")
	check(absf(_total() - total0) < 0.01, "negocio oculto: dinero total conservado (montaje, sueldos, insumos y ventas quedan en el pueblo)")
	check(MoneySim.risk(gs) > 0.0, "el negocio oculto suma riesgo (%.1f)" % MoneySim.risk(gs))
	# En la simulación diaria.
	TimeManager.advance_days(14)
	check(float(h["sold_total"]) > 0.0 and gs.running, "la simulación diaria mueve el negocio oculto")


# --- 5. Riesgo, inspección, hallazgo y soborno -------------------------------------------------------------

func _setup_offense(seed_v: int) -> Dictionary:
	_new_town(seed_v)
	var gs := GameState
	gs.techs.append("economia_informal")
	gs.techs.append("cultivo_ilicito")
	MoneySim.withdraw(gs, 2000.0)
	MoneySim.open_hidden(gs, "cultivo_ilicito")
	var h: Dictionary = MoneySim.active_hidden(gs)[0]
	h["stock"] = 50.0
	MoneySim.add_risk(gs, 40.0)
	return h


func _test_inspection_seizure() -> void:
	_setup_offense(508)
	var gs := GameState
	check(MoneySim.inspection_chance(gs) > 0.0, "el riesgo acumulado da probabilidad de inspección (%.0f%%/mes)" % (MoneySim.inspection_chance(gs) * 100.0))
	var t := MoneySim.inspect(gs, 0.99)
	check(MoneySim.case_of(gs).is_empty() and t.contains("no encontraron"), "inspección sin hallazgo")
	var total0 := _total()
	var cash0 := MoneySim.cash(gs)
	var treasury0 := float(gs.government["treasury"])
	var rep0 := PoliticsSim.reputation(gs)
	MoneySim.inspect(gs, 0.0)
	var c := MoneySim.case_of(gs)
	check(not c.is_empty() and float(c["fine"]) > 0.0, "la inspección descubre: caso abierto con multa %s" % Fmt.money(float(c.get("fine", 0.0))))
	check(MoneySim.hidden_block_reason(gs, "cultivo_ilicito") != "", "con un caso abierto no se montan negocios ocultos")
	var logs: Array = gs.notifications_log.map(func(e): return str(e["text"]))
	check(logs.any(func(x): return x.contains("Hallazgo")), "notificación del hallazgo")
	TimeManager.advance_days(12)
	check(MoneySim.case_of(gs).is_empty(), "al vencer el plazo se aplica la sanción")
	check(MoneySim.cash(gs) < cash0 * 0.6 and MoneySim.active_hidden(gs).is_empty(), "decomiso de efectivo y cierre del negocio oculto")
	check(float(gs.government["treasury"]) > treasury0 and PoliticsSim.reputation(gs) < rep0, "multa al tesoro y baja de reputación")
	logs = gs.notifications_log.map(func(e): return str(e["text"]))
	check(logs.any(func(x): return x.contains("Sanción") and x.contains("decomis")), "notificación de multa y decomiso")
	# Caso grave: cárcel.
	_setup_offense(509)
	MoneySim.add_risk(gs, 60.0)
	MoneySim.inspect(gs, 0.0)
	check(bool(MoneySim.case_of(gs).get("grave", false)), "riesgo muy alto: caso grave")
	MoneySim.resolve_case(gs)
	var jailed := gs.citizens.values().filter(func(x): return x.prison_until > gs.today())
	check(not jailed.is_empty(), "caso grave: el personaje o un familiar va a la cárcel (%d)" % jailed.size())


func _test_bribe() -> void:
	_setup_offense(510)
	var gs := GameState
	MoneySim.inspect(gs, 0.0)
	var fine := float(MoneySim.case_of(gs)["fine"])
	check(MoneySim.bribe_chance(gs, fine) > MoneySim.bribe_chance(gs, fine * 0.1), "más dinero, más probabilidad de soborno")
	PoliticsSim.state(gs)["corruption"] = 50.0
	var hi := MoneySim.bribe_chance(gs, fine * 0.5)
	PoliticsSim.state(gs)["corruption"] = 0.0
	check(hi > MoneySim.bribe_chance(gs, fine * 0.5), "la corrupción (contactos) sube la probabilidad")
	var total0 := _total()
	var corr0 := PoliticsSim.corruption(gs)
	var hidden_n := MoneySim.active_hidden(gs).size()
	var t := MoneySim.bribe(gs, fine * 0.5, 0.0)
	check(t.contains("ACEPTADO") and MoneySim.case_of(gs).is_empty(), "soborno aceptado: se archiva el caso")
	check(MoneySim.active_hidden(gs).size() == hidden_n, "sin decomiso ni cierre")
	check(PoliticsSim.corruption(gs) > corr0, "el soborno suma corrupción en la política de la familia")
	check(absf(_total() - total0) < 0.01, "el soborno queda en el pueblo (un funcionario)")
	# Rechazado.
	MoneySim.add_risk(gs, 40.0)
	MoneySim.inspect(gs, 0.0)
	fine = float(MoneySim.case_of(gs)["fine"])
	var money0 := gs.money
	var tr0 := float(gs.government["treasury"])
	t = MoneySim.bribe(gs, fine * 0.2, 0.999)
	check(t.contains("RECHAZADO") and MoneySim.case_of(gs).is_empty(), "soborno rechazado: el caso se resuelve ya")
	check(float(gs.government["treasury"]) - tr0 >= fine * 1.5 - 0.01 or gs.money <= 0.01, "rechazado: multa agravada (%s)" % Fmt.money(float(gs.government["treasury"]) - tr0))
	check(MoneySim.active_hidden(gs).is_empty(), "rechazado: cierre del negocio oculto")
	var logs: Array = gs.notifications_log.map(func(e): return str(e["text"]))
	check(logs.any(func(x): return x.contains("Soborno ACEPTADO")) and logs.any(func(x): return x.contains("Soborno RECHAZADO")), "notificaciones de soborno aceptado y rechazado")
	check(gs.money < money0, "la sanción se paga")


# --- 6. Guardado ----------------------------------------------------------------------------------------------

func _test_save_load() -> void:
	_new_town(511)
	var gs := GameState
	gs.techs.append("economia_informal")
	gs.techs.append("destileria_clandestina")
	MoneySim.withdraw(gs, 2500.0)
	MoneySim.open_hidden(gs, "destileria_clandestina")
	MoneySim.add_risk(gs, 12.0)
	var b := _farm()
	_befriend(3)
	MoneySim.set_undeclared(gs, b, true)
	var cash0 := MoneySim.cash(gs)
	var risk0 := MoneySim.risk(gs)
	gs.load_dict(JSON.parse_string(JSON.stringify(gs.to_dict())))
	check(is_equal_approx(MoneySim.cash(gs), cash0) and is_equal_approx(MoneySim.risk(gs), risk0), "efectivo y riesgo se guardan (JSON)")
	check(MoneySim.active_hidden(gs).size() == 1 and bool(gs.get_building(int(b["id"])).get("undeclared", false)), "negocios ocultos y casillas 'no declarar' se guardan")
	SaveManager.save_game("test_efectivo")
	gs.cash = 0.0
	SaveManager.load_game("test_efectivo")
	check(is_equal_approx(MoneySim.cash(gs), cash0), "guardar y cargar (binario)")
	SaveManager.delete_save("test_efectivo")
	var d := gs.to_dict()
	d.erase("cash")
	d.erase("informal")
	gs.load_dict(d)
	check(is_equal_approx(MoneySim.cash(gs), 0.0) and MoneySim.active_hidden(gs).is_empty() and MoneySim.risk(gs) == 0.0, "partidas antiguas cargan con valores por defecto")
	TimeManager.advance_days(35)
	check(gs.running, "la simulación sigue tras cargar")


# --- 7. Interfaz ----------------------------------------------------------------------------------------------

func _test_ui() -> void:
	_setup_offense(512)
	var gs := GameState
	_farm()
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	var hud: Hud = world.hud
	MoneySim.inspect(gs, 0.0)
	hud._show_dock("cash")
	await get_tree().process_frame
	var panel: CashPanel = hud.cash_panel
	check(panel.visible, "panel 'Efectivo y riesgo' abierto desde el HUD")
	var texts := []
	for n in panel.find_children("*", "Button", true, false):
		texts.append((n as Button).text)
	var checks := panel.find_children("*", "CheckBox", true, false).size()
	check(texts.any(func(x): return x.begins_with("Depositar")) and texts.any(func(x): return x.begins_with("Retirar")), "panel: depósito y retiro")
	check(texts.any(func(x): return x.begins_with("Sobornar")), "panel: opción de soborno con el caso abierto")
	check(checks >= 1, "panel: casillas 'no declarar' / sueldos en negro (%d)" % checks)
	check(texts.any(func(x): return x.begins_with("Montar")), "panel: negocios ocultos")
	hud.close_dock()
