extends Node
## Pruebas de la Fase 8 (turismo, publicidad, industria avanzada, herencia y dinastía).
## godot --headless res://tests/test_fase8.tscn

## Materias primas que define la Fase 6 (pueden no existir aún en goods).
const RAW := ["hierro", "carbon", "madera", "piedra", "lana", "algodon", "oro", "plata", "trigo"]

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func _ready() -> void:
	print("== Dinastía: pruebas de la Fase 8 ==")
	_test_industry_data()
	_test_tourism_data()
	_test_no_connections()
	_test_tourists_with_connections()
	_test_tourism_factors()
	_test_advertising()
	_test_media()
	_test_dynasty()
	_test_save_load()
	_test_balance()
	print("== %s (%d fallos) ==" % ["TODO OK" if failures == 0 else "CON FALLOS", failures])
	get_tree().quit(1 if failures > 0 else 0)


# --- Utilidades ----------------------------------------------------------------------------------

func _build_now(type_id: String, x: float, z: float) -> Dictionary:
	var r := ConstructionSim.start_construction(GameState, type_id, x, z, 0.0, "", "sas")
	if r.has("error"):
		print("    error construcción %s: %s" % [type_id, r["error"]])
		return {}
	var b: Dictionary = r["building"]
	var guard := 0
	while b["status"] != "activo" and guard < 400:
		TimeManager.advance_days(1)
		guard += 1
	return b


func _staff_up(b: Dictionary) -> int:
	var jobs := int(GameState.level_def(b).get("jobs", 1))
	var hired := 0
	for c in BusinessSim.candidates(GameState, b):
		if hired >= jobs:
			break
		c.education = maxi(c.education, int(GameState.level_def(b).get("min_education", 0)))
		if BusinessSim.hire(GameState, b, c, BusinessSim.asked_wage(GameState, c, str(b["type"])) * 1.1) == "":
			hired += 1
	return hired


func _new_town(seed_v: int) -> void:
	GameState.new_game({"seed": seed_v, "difficulty": "facil"})
	GameState.money = 60000.0
	_build_now("oficina", -12, -32)


func _connect(distance := 60.0, transport := "carreta", town := "x") -> void:
	var conns: Array = GameState.trade.get("connections", [])
	conns.append({"town_id": town, "distance": distance, "transport": transport})
	GameState.trade["connections"] = conns


# --- Datos --------------------------------------------------------------------------------------

func _good_exists(g: String) -> bool:
	return GameData.goods.has(g) or RAW.has(g)


func _test_industry_data() -> void:
	var ids := GameData.businesses.keys().filter(func(k): return bool(GameData.businesses[k].get("industrial", false)))
	check(ids.size() >= 8, "industria avanzada definida (%d fábricas)" % ids.size())
	for req in ["textil", "siderurgica", "industria_automotriz", "aeronautica", "fabrica_electronica"]:
		check(ids.has(req), "existe la fábrica '%s'" % req)
	var bad := []
	var engineer := false
	for id in ids:
		var def: Dictionary = GameData.businesses[id]
		if str(def.get("category", "")) != "negocio" or not GameData.goods.has(str(def.get("product", ""))):
			bad.append("%s: categoría/producto" % id)
		for ld in def.get("levels", []):
			var lab := "%s/%s" % [id, ld.get("label", "?")]
			var inputs: Dictionary = ld.get("inputs", {})
			if inputs.is_empty():
				bad.append(lab + ": sin inputs")
			for g in inputs:
				if not _good_exists(str(g)) or float(inputs[g]) <= 0.0:
					bad.append("%s: insumo inválido %s" % [lab, g])
			if str(ld.get("output", "")) != "warehouse":
				bad.append(lab + ": output != warehouse")
			if str(ld.get("product", "")) != str(def["product"]) or not GameData.goods.has(str(ld.get("product", ""))):
				bad.append(lab + ": product")
			if not GameData.skills.get("skills", {}).has(str(ld.get("skill", ""))):
				bad.append(lab + ": skill")
			if int(ld.get("jobs", 0)) <= 0 or float(ld.get("prod_per_worker", 0)) <= 0.0:
				bad.append(lab + ": jobs/prod_per_worker")
			var tech := str(ld.get("tech", ""))
			if tech != "" and not GameData.technologies.has(tech):
				bad.append(lab + ": tech inexistente " + tech)
			if not ld.has("pollution") or float(ld.get("cost", 0)) <= 0.0 or ld.get("model", []).is_empty():
				bad.append(lab + ": pollution/costo/modelo")
			for g in ld.get("materials", {}):
				if not GameData.goods.has(str(g)):
					bad.append(lab + ": material " + str(g))
			var prof := str(ld.get("required_profession", ""))
			if prof != "":
				engineer = engineer or prof == "ingeniero"
				if not GameData.professions.get("professions", {}).has(prof):
					bad.append(lab + ": profesión " + prof)
			# Valor agregado: el producto vale más que los insumos con precio conocido.
			var inputs_value := 0.0
			for g in inputs:
				inputs_value += float(inputs[g]) * float(GameData.goods.get(g, {}).get("base_price", 0.0))
			if float(GameData.goods.get(str(def["product"]), {}).get("base_price", 0.0)) <= inputs_value:
				bad.append("%s: sin valor agregado (%.1f <= %.1f)" % [lab, float(GameData.goods[def["product"]]["base_price"]), inputs_value])
	check(bad.is_empty(), "esquema de fábricas acordado con la Fase 6 %s" % ("" if bad.is_empty() else str(bad)))
	check(engineer, "niveles altos exigen ingenieros")
	check(float(GameData.goods["avion_bien"]["base_price"]) > float(GameData.goods["automovil_bien"]["base_price"]) and float(GameData.goods["automovil_bien"]["base_price"]) > float(GameData.goods["maquinaria"]["base_price"]), "productos caros escalonados (avión > auto > maquinaria)")
	var t: Dictionary = GameData.technologies.get("electronica", {})
	var branches: Array = GameData.eras.get("branches", []).map(func(b): return str(b[0]))
	var reqs_ok := true
	for r in t.get("requires", []):
		reqs_ok = reqs_ok and GameData.technologies.has(r) and int(GameData.technologies[r].get("era", 1)) <= int(t.get("era", 1))
	check(not t.is_empty() and branches.has(str(t.get("branch", ""))) and reqs_ok, "tecnología nueva 'electronica' encaja en épocas/ramas con prerrequisitos existentes")
	GameState.new_game({"seed": 3})
	check(ConstructionSim.level_block_reason(GameState, "industria_automotriz", 1) != "", "la automotriz requiere investigación")
	check(ConstructionSim.level_block_reason(GameState, "joyeria", 1) == "", "la orfebrería está disponible en la colonia")


func _test_tourism_data() -> void:
	var bad := []
	var n := 0
	for id in GameData.businesses:
		var def: Dictionary = GameData.businesses[id]
		var k := str(def.get("tourism", ""))
		if k == "":
			continue
		n += 1
		if not GameData.goods.has(str(def.get("product", ""))):
			bad.append(id + ": producto")
		for ld in def.get("levels", []):
			var tech := str(ld.get("tech", ""))
			if tech != "" and not GameData.technologies.has(tech):
				bad.append("%s: tech %s" % [id, tech])
			if k != "medio" and (float(ld.get("attraction", 0)) <= 0.0 or float(ld.get("ticket_value", 0)) <= 0.0):
				bad.append(id + ": atractivo/entrada")
			if ld.get("model", []).is_empty():
				bad.append(id + ": modelo")
	check(n >= 8, "atracciones, hoteles y medios definidos (%d)" % n)
	check(bad.is_empty(), "datos de turismo válidos %s" % ("" if bad.is_empty() else str(bad)))
	check(not GameData.goods.get("entrada", {}).get("storable", true) and not GameData.goods.get("alojamiento", {}).get("storable", true), "entradas y noches no se almacenan")


# --- Turismo ------------------------------------------------------------------------------------

func _test_no_connections() -> void:
	_new_town(81)
	var m := _build_now("mirador", 30, -8)
	var h := _build_now("hospedaje", -30, 10)
	check(not m.is_empty() and not h.is_empty(), "mirador y mesón construidos")
	_staff_up(m)
	_staff_up(h)
	TimeManager.advance_days(45)
	check(TourismSim.expected_tourists(GameState) == 0.0, "sin conexiones: 0 turistas esperados")
	check(int(GameState.tourism.get("total_visitors", 0)) == 0 and float(GameState.tourism.get("total_income", 0.0)) == 0.0, "sin conexiones no llega ningún turista")


func _test_tourists_with_connections() -> void:
	_new_town(82)
	var m := _build_now("mirador", 30, -8)
	var h := _build_now("hospedaje", -30, 10)
	var tav := _build_now("taberna", 10, 30)
	_staff_up(m)
	_staff_up(h)
	_staff_up(tav)
	_connect(60.0, "carreta")
	check(TourismSim.expected_tourists(GameState) > 1.0, "con conexión se esperan turistas (%.1f/día)" % TourismSim.expected_tourists(GameState))
	TimeManager.advance_days(20)
	# Un día aislado: todo lo que gastan los turistas es dinero nuevo en el pueblo.
	BusinessSim.produce(GameState)
	MarketSim.begin_day(GameState)
	var before := EconomySim.total_money(GameState)
	TourismSim.daily(GameState)
	var rec: Dictionary = GameState.tourism["today"]
	var income := float(rec["tickets"]) + float(rec["lodging"]) + float(rec["shops"]) + float(rec["media"])
	var after := EconomySim.total_money(GameState)
	check(income > 0.0 and absf((after - before) - income) < 0.01, "el gasto turístico entra de afuera (+%s en un día)" % Fmt.money2(income))
	TimeManager.advance_days(60)
	var lm: Dictionary = GameState.tourism.get("last_month", {})
	print("    mes con 1 conexión: visitantes %d · entradas %s · alojamiento %s · comercio %s · sin cama %d" % [int(lm.get("visitors", 0)),
		Fmt.money(float(lm.get("tickets", 0))), Fmt.money(float(lm.get("lodging", 0))), Fmt.money(float(lm.get("shops", 0))), int(lm.get("lost_no_bed", 0))])
	check(int(lm.get("visitors", 0)) > 30, "llegan turistas por la conexión")
	check(float(lm.get("tickets", 0.0)) > 0.0, "pagan entradas en el mirador")
	check(float(lm.get("lodging", 0.0)) > 0.0, "pagan alojamiento en el mesón")
	check(float(lm.get("shops", 0.0)) > 0.0, "gastan en tus negocios (taberna)")
	check(BusinessSim.period_value(m, "last_month", "ventas") > 0.0, "el mirador factura")
	# Precio de entrada configurable: muy caro → nadie entra.
	m["auto_price"] = false
	BusinessSim.set_price(GameState, m, TourismSim.willing_price(GameState, m) * 1.5)
	var t0 := float(GameState.tourism["month"].get("tickets", 0.0))
	TimeManager.advance_days(5)
	check(is_equal_approx(float(GameState.tourism["month"].get("tickets", 0.0)), t0) or float(GameState.tourism["month"].get("tickets", 0.0)) < t0 + 0.01, "con entrada demasiado cara no entra nadie")
	# Sin camas: los turistas de pueblos lejanos no vienen.
	ConstructionSim.demolish(GameState, h)
	GameState.trade["connections"] = [{"town_id": "lejos", "distance": 200, "transport": "carreta"}]
	var lost := 0.0
	for i in range(15):
		TimeManager.advance_days(1)
		lost += float(GameState.tourism["today"].get("lost_no_bed", 0.0))
	check(lost > 0.0, "sin hospedaje se pierden turistas que querían pasar la noche")


func _test_tourism_factors() -> void:
	_new_town(83)
	var m := _build_now("mirador", 30, -8)
	_staff_up(m)
	_connect(60.0, "carreta")
	var base := TourismSim.expected_tourists(GameState)
	GameState.trade["connections"] = [{"town_id": "x", "distance": 60, "transport": "tren"}]
	var train := TourismSim.expected_tourists(GameState)
	check(train > base, "mejor transporte → más turistas (%.1f → %.1f)" % [base, train])
	_connect(60.0, "carreta", "y")
	check(TourismSim.expected_tourists(GameState) > train, "más conexiones → más turistas")
	GameState.problems["crime"] = 80.0
	var crime := TourismSim.expected_tourists(GameState)
	GameState.problems["crime"] = 0.0
	check(crime < TourismSim.expected_tourists(GameState), "el crimen espanta turistas")
	var f := _build_now("feria", -25, 20)
	_staff_up(f)
	check(float(TourismSim.breakdown(GameState)["diversity"]) > 1.0, "variedad de atracciones suma atractivo")


# --- Publicidad ----------------------------------------------------------------------------------

func _test_advertising() -> void:
	_new_town(84)
	var tav := _build_now("taberna", 30, -8)
	_staff_up(tav)
	check(AdvertisingSim.demand_mult(GameState, tav) == 1.0, "sin campañas demand_mult = 1")
	check(AdvertisingSim.start_campaign(GameState, "periodico", "todos", 3) != "", "el periódico requiere investigar 'periodico'")
	var money0 := GameState.money
	var total0 := EconomySim.total_money(GameState)
	var est := AdvertisingSim.estimate(GameState, "pregonero", str(int(tav["id"])), 2)
	check(float(est["cost_month"]) > 0.0 and float(est["demand_pct"]) > 0.0, "estimación de costo y efecto (%s/mes, +%.0f%%)" % [Fmt.money(float(est["cost_month"])), float(est["demand_pct"])])
	check(AdvertisingSim.start_campaign(GameState, "pregonero", str(int(tav["id"])), 2) == "", "campaña de pregonero para la taberna")
	check(GameState.money < money0, "la campaña cuesta dinero")
	check(absf(EconomySim.total_money(GameState) - total0) < 0.01, "el pregonero es un vecino: el dinero queda en el pueblo")
	var dm := AdvertisingSim.demand_mult(GameState, tav)
	check(dm > 1.0, "la campaña aumenta la demanda del negocio (×%.2f)" % dm)
	check(BusinessSim.period_value(tav, "month", "publicidad") > 0.0, "el gasto aparece en la contabilidad del negocio")
	TechSim.complete(GameState, "revolucion_industrial")
	for id in ["imprenta", "periodico"]:
		TechSim.complete(GameState, id)
	check(AdvertisingSim.channel_block_reason(GameState, "periodico") == "", "con la tecnología se habilita el periódico")
	check(AdvertisingSim.start_campaign(GameState, "periodico", "todos", 1) == "", "campaña en el periódico para todos los negocios")
	check(AdvertisingSim.demand_mult(GameState, tav) > dm, "las campañas se suman")
	check(AdvertisingSim.demand_mult(GameState, tav) <= 1.0 + float(AdvertisingSim.cfg().get("max_demand", 0.8)) + 0.001, "con tope de efecto")
	check(AdvertisingSim.start_campaign(GameState, "periodico", "turismo", 1) != "", "sin conexiones no se puede promocionar el turismo")
	_connect()
	var t0 := AdvertisingSim.tourism_mult(GameState)
	check(AdvertisingSim.start_campaign(GameState, "periodico", "turismo", 1) == "" and AdvertisingSim.tourism_mult(GameState) > t0, "promoción turística atrae más turistas")
	var first: Dictionary = AdvertisingSim.campaigns(GameState)[0]
	check(AdvertisingSim.cancel_campaign(GameState, int(first["id"])) == "" and AdvertisingSim.campaigns(GameState).size() == 2, "cancelar campaña")
	TimeManager.advance_days(70)
	check(AdvertisingSim.campaigns(GameState).is_empty(), "las campañas terminan al cumplir su duración")
	check(AdvertisingSim.demand_mult(GameState, tav) == 1.0, "sin campañas activas la demanda vuelve a la normalidad")


func _test_media() -> void:
	_new_town(85)
	TechSim.complete(GameState, "revolucion_industrial")
	for id in ["imprenta", "periodico"]:
		TechSim.complete(GameState, id)
	var full := AdvertisingSim.monthly_cost(GameState, "periodico", "todos")
	var p := _build_now("medios", 30, -8)
	check(not p.is_empty(), "periódico propio construido")
	check(_staff_up(p) > 0, "periódico con personal")
	var own := AdvertisingSim.monthly_cost(GameState, "periodico", "todos")
	check(own < full * 0.6, "tu periódico abarata tus campañas (%s → %s)" % [Fmt.money(full), Fmt.money(own)])
	check(AdvertisingSim.monthly_cost(GameState, "pregonero", "todos") > 0.0, "el pregonero no tiene descuento de medios")
	var s0 := BusinessSim.period_value(p, "month", "ventas")
	TimeManager.advance_days(10)
	check(is_equal_approx(BusinessSim.period_value(p, "month", "ventas"), s0) or BusinessSim.period_value(p, "month", "ventas") == 0.0, "sin conexiones el periódico no vende avisos afuera")
	_connect()
	TimeManager.advance_days(10)
	check(float(GameState.tourism["month"].get("media", 0.0)) > 0.0, "con conexiones vende espacios publicitarios a otros pueblos")


# --- Dinastía -----------------------------------------------------------------------------------

func _test_dynasty() -> void:
	GameState.new_game({"seed": 86, "difficulty": "normal"})
	check(DynastySim.heads(GameState).size() == 1, "registro de la dinastía con el fundador")
	var rate := DynastySim.tax_rate(GameState)
	check(rate > 0.0 and rate < 0.5, "impuesto a la herencia según el gobierno (%s)" % Fmt.pct(rate * 100.0))
	# Aviso de vejez sin heredero.
	var p := GameState.player_citizen()
	p.birth_day = GameState.today() - 365 * 61
	DynastySim.monthly(GameState)
	var warned := GameState.notifications_log.any(func(e): return str(e["text"]).contains("no tienes heredero"))
	check(warned, "aviso a los 60+ sin heredero")
	# Sucesión con deudas y patrimonio.
	GameState.money = 50000.0
	PlayerSim.adopt_baby(GameState)
	var heir: Citizen = PlayerSim.heir_candidates(GameState)[0]
	heir.birth_day = GameState.today() - 365 * 30
	heir.money = 100.0
	BankSim.request_player_loan(GameState, 1000.0, 24)
	var debt := EconomySim.player_debt(GameState)
	var treasury0 := float(GameState.government.get("treasury", 0.0))
	var est := DynastySim.estimate_tax(GameState)
	check(float(est["tax"]) > 0.0, "impuesto estimado %s sobre patrimonio %s" % [Fmt.money(float(est["tax"])), Fmt.money(float(est["net_worth"]))])
	var old_name := p.full_name()
	PopulationSim.die(GameState, p, "vejez")
	check(GameState.running and GameState.player_id == heir.id, "el heredero toma el control")
	var heads := DynastySim.heads(GameState)
	check(heads.size() == 2 and str(heads[0]["name"]) == old_name and int(heads[0]["end_year"]) > 0, "el fundador queda registrado con sus años de gobierno")
	check(float(heads[0]["net_worth_end"]) > 0.0 and float(heads[0]["tax_paid"]) > 0.0, "registro con patrimonio e impuesto pagado")
	check(float(GameState.government.get("treasury", 0.0)) > treasury0, "el impuesto va al tesoro público")
	check(absf(EconomySim.player_debt(GameState) - debt) < 0.01 and not BankSim.player_loans(GameState).is_empty(), "las deudas se heredan")
	check(float(heads[1].get("debts_inherited", 0.0)) > 0.0, "el registro anota las deudas heredadas")
	# Impuesto no pagado en efectivo → cuotas.
	GameState.player["inheritance_debt"] = 100.0
	GameState.player["inheritance_installment"] = 10.0
	var t1 := float(GameState.government.get("treasury", 0.0))
	DynastySim.monthly(GameState)
	check(is_equal_approx(DynastySim.pending_debt(GameState), 90.0) and float(GameState.government.get("treasury", 0.0)) > t1, "cuotas del impuesto pendiente al tesoro")
	# Sin herederos: fin de la dinastía, registro cerrado.
	GameState.player["inheritance_debt"] = 0.0
	var p2 := GameState.player_citizen()
	PopulationSim.die(GameState, p2, "vejez")
	check(not GameState.running and int(DynastySim.heads(GameState)[1]["end_year"]) > 0, "sin herederos termina la dinastía y se cierra el registro")


func _test_save_load() -> void:
	_new_town(87)
	var tav := _build_now("taberna", 30, -8)
	_staff_up(tav)
	_connect()
	AdvertisingSim.start_campaign(GameState, "pregonero", "todos", 3)
	TimeManager.advance_days(40)
	var d := GameState.to_dict()
	var text := JSON.stringify(d)
	GameState.load_dict(JSON.parse_string(text))
	check(AdvertisingSim.campaigns(GameState).size() == 1, "las campañas se guardan")
	check(DynastySim.heads(GameState).size() == 1, "el registro de la dinastía se guarda")
	check(AdvertisingSim.demand_mult(GameState, tav) > 1.0, "tras cargar la campaña sigue activa")
	TimeManager.advance_days(5)
	check(GameState.running, "la simulación sigue tras cargar")


# --- Balance ------------------------------------------------------------------------------------

func _test_balance() -> void:
	_new_town(88)
	var m := _build_now("mirador", 30, -8)
	var h := _build_now("hospedaje", -30, 10)
	var tav := _build_now("taberna", 10, 30)
	for b in [m, h, tav]:
		_staff_up(b)
	_connect(60.0, "carreta")
	var profit_m := 0.0
	var profit_h := 0.0
	var visitors := 0
	var income := 0.0
	for month in range(12):
		TimeManager.advance_days(30)
		profit_m += BusinessSim.period_profit(m, "last_month")
		profit_h += BusinessSim.period_profit(h, "last_month")
		visitors += int(GameState.tourism["last_month"].get("visitors", 0))
		income += TourismSim.last_month_income(GameState)
	print("    1 año con 1 conexión (carreta, 60 km): %d visitantes · %s traídos de afuera · utilidad mirador %s · mesón %s" % [visitors, Fmt.money(income), Fmt.money(profit_m), Fmt.money(profit_h)])
	check(profit_m > 0.0, "el mirador es rentable con una conexión")
	check(income < 20000.0, "el turismo temprano no rompe la economía")
