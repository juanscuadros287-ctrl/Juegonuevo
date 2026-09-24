extends Node
## Pruebas sin interfaz: godot --headless res://tests/test_runner.tscn

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func _ready() -> void:
	print("== Dinastía: pruebas ==")
	_test_new_game()
	_test_simulation()
	_test_save_load()
	_test_terrain()
	_test_jump()
	_test_phase2_business()
	_test_phase2_housing()
	_test_phase2_player()
	_test_interiors()
	_test_time_speeds()
	_test_phase3_prices()
	_test_phase3_player_loans()
	_test_phase3_bank()
	_test_phase3_bankruptcy()
	print("== %s (%d fallos) ==" % ["TODO OK" if failures == 0 else "CON FALLOS", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _test_new_game() -> void:
	for d in GameData.difficulties:
		GameState.new_game({"difficulty": d, "seed": 42})
		var expected := int(GameData.difficulty(d)["start_citizens"]) + 1
		check(GameState.citizens.size() == expected, "%s: %d ciudadanos iniciales (incluye al jugador)" % [d, expected])
		check(is_equal_approx(GameState.money, float(GameData.difficulty(d)["start_money"])), "%s: dinero inicial" % d)
	var homeless := 0
	for c in GameState.citizens.values():
		if c.home_id < 0:
			homeless += 1
	check(homeless == 0, "todos los ciudadanos iniciales tienen vivienda")
	check(TimeManager.year() == 1700 and TimeManager.month() == 3, "fecha inicial 1 de marzo de 1700: " + TimeManager.date_string())


func _test_simulation() -> void:
	GameState.new_game({"difficulty": "normal", "seed": 7})
	var start_pop := GameState.citizens.size()
	TimeManager.advance_days(365 * 30)
	var births := 0
	var deaths := 0
	for h in GameState.history:
		births += int(h["births"])
		deaths += int(h["deaths"])
	print("    30 años: población %d -> %d, nacimientos %d, muertes %d, felicidad %.1f, salud %.1f, año %d" % [
			start_pop, GameState.citizens.size(), births, deaths, GameState.avg_happiness(), GameState.avg_health(), TimeManager.year()])
	if GameState.running:
		check(TimeManager.year() >= 1729, "el tiempo avanza 30 años")
		check(GameState.history.size() >= 359, "historial mensual registrado")
	else:
		print("    (tu personaje murió sin herederos en %d: la partida terminó)" % TimeManager.year())
		check(GameState.history.size() >= 12, "historial mensual registrado")
	check(births > 0, "hay nacimientos")
	check(deaths > 0, "hay muertes")
	var bad := 0
	for c in GameState.citizens.values():
		if c.health < 0 or c.health > 100 or c.happiness < 0 or c.happiness > 100 or is_nan(c.money):
			bad += 1
	check(bad == 0, "valores de ciudadanos dentro de rango")


func _test_save_load() -> void:
	GameState.new_game({"difficulty": "normal", "seed": 99, "town_name": "Prueba"})
	TimeManager.advance_days(400)
	var pop := GameState.citizens.size()
	var money := GameState.money
	var hours := TimeManager.total_hours
	var snapshot := JSON.stringify(GameState.to_dict())
	check(SaveManager.save_game("test_fase1"), "guardar partida")
	TimeManager.advance_days(200)
	check(SaveManager.load_game("test_fase1"), "cargar partida")
	check(GameState.citizens.size() == pop, "población restaurada")
	check(is_equal_approx(GameState.money, money), "dinero restaurado")
	check(TimeManager.total_hours == hours, "fecha restaurada")
	check(JSON.stringify(GameState.to_dict()) == snapshot, "estado idéntico tras cargar")
	# Determinismo: la misma semilla y estado producen el mismo futuro.
	TimeManager.advance_days(365)
	var a := JSON.stringify(GameState.to_dict())
	SaveManager.load_game("test_fase1")
	TimeManager.advance_days(365)
	check(JSON.stringify(GameState.to_dict()) == a, "simulación determinista tras cargar")
	check(SaveManager.list_saves().any(func(s): return s["slot"] == "test_fase1"), "partida listada")
	SaveManager.delete_save("test_fase1")


func _test_terrain() -> void:
	for m in GameData.map_types:
		GameState.new_game({"map_type": m, "seed": 1234})
		var t := Terrain.new()
		add_child(t)
		t.generate(m, 1234)
		t.build_mesh()
		t.scatter_nature(1234)
		var town_ok := t.is_land(0, 0, 1.0)
		for b in GameState.buildings:
			town_ok = town_ok and t.is_land(float(b["x"]), float(b["z"]), 1.0)
		var water := 0
		var total := 0
		for j in range(0, 400, 8):
			for i in range(0, 400, 8):
				total += 1
				if not t.is_land(i - 200.0, j - 200.0, 0.0):
					water += 1
		print("    mapa %s: agua %d%%, árboles %d" % [m, 100 * water / total, t.tree_positions.size()])
		check(town_ok, "mapa %s: pueblo y viviendas sobre tierra" % m)
		if m in ["costa", "rio"]:
			check(water > 0, "mapa %s tiene agua" % m)
		t.queue_free()


func _test_jump() -> void:
	GameState.new_game({"seed": 5})
	var reports := []
	EventBus.jump_finished.connect(func(r): reports.append(r))
	TimeManager.start_jump(2)
	check(TimeManager.jumping, "salto iniciado")
	var guard := 0
	while TimeManager.jumping and guard < 10000:
		TimeManager._process_jump()
		guard += 1
	check(reports.size() == 1, "reporte del salto generado")
	if reports.size() == 1:
		check(reports[0]["start_date"] != reports[0]["end_date"], "reporte con fechas: %s -> %s" % [reports[0]["start_date"], reports[0]["end_date"]])
	check(TimeManager.year() >= 1702, "salto de 2 años aplicado")
	GameState.running = false


func _build_now(type_id: String, x: float, z: float, tier := "normal") -> Dictionary:
	var r := ConstructionSim.start_construction(GameState, type_id, x, z, 0.0, "", "sas", tier)
	if r.has("error"):
		print("    error construcción: ", r["error"])
		return {}
	var b: Dictionary = r["building"]
	var guard := 0
	while b["status"] != "activo" and guard < 400:
		TimeManager.advance_days(1)
		guard += 1
	return b


func _test_phase2_business() -> void:
	GameState.new_game({"seed": 11, "difficulty": "facil"})
	var money0 := GameState.money
	check(ConstructionSim.placement_block_reason(GameState, "granja", 0, 0) != "", "no se construye sobre la plaza")
	check(ConstructionSim.placement_block_reason(GameState, "granja", 150, 150) != "", "no se construye en zona bloqueada")
	var farm := _build_now("granja", 30, -8)
	check(not farm.is_empty() and farm["status"] == "activo", "granja construida con jornaleros")
	check(GameState.money < money0, "la construcción cuesta dinero")
	var free_workers := 0
	for c in GameState.citizens.values():
		if c.job_kind == "obra":
			free_workers += 1
	check(free_workers == 0, "jornaleros liberados al terminar la obra")
	var cands := BusinessSim.candidates(GameState, farm)
	check(cands.size() > 0, "hay candidatos para contratar")
	for i in range(4):
		var c: Citizen = cands[i]
		BusinessSim.hire(GameState, farm, c, BusinessSim.asked_wage(GameState, c, "granja"))
	check(GameState.employees_of(int(farm["id"])).size() == 4, "4 empleados contratados")
	check(BusinessSim.hire(GameState, farm, cands[4], 2.0) != "", "no se contrata sobre la capacidad")
	TimeManager.advance_days(30)
	var sales := BusinessSim.period_value(farm, "month", "ventas") + BusinessSim.period_value(farm, "last_month", "ventas")
	var wages := BusinessSim.period_value(farm, "month", "salarios") + BusinessSim.period_value(farm, "last_month", "salarios")
	print("    granja 30 días: ventas %.1f salarios %.1f inventario %.1f" % [sales, wages, float(farm["inventory"].get("comida", 0))])
	check(sales > 0.0, "la granja vende comida a los ciudadanos")
	check(wages > 0.0, "la granja paga salarios")
	# Mejora: no factura durante la obra.
	GameState.techs.append("rotacion_cultivos")
	check(ConstructionSim.start_upgrade(GameState, farm) == "", "mejora iniciada")
	var before := BusinessSim.period_value(farm, "month", "ventas")
	TimeManager.advance_days(5)
	check(farm["status"] == "mejorando" and is_equal_approx(BusinessSim.period_value(farm, "month", "ventas"), before) or BusinessSim.period_value(farm, "month", "ventas") == 0.0, "sin ventas durante la mejora")
	var guard := 0
	while farm["status"] != "activo" and guard < 400:
		TimeManager.advance_days(1)
		guard += 1
	check(int(farm["level"]) == 2, "granja sube a nivel 2")
	# Límite de negocios sin oficina y con oficina.
	var slots := BusinessSim.max_businesses(GameState)
	_build_now("aguatero", -30, 10)
	check(ConstructionSim.build_block_reason(GameState, "taberna") != "", "límite de %d negocios sin oficina" % slots)
	_build_now("oficina", 12, 30)
	check(BusinessSim.max_businesses(GameState) > slots, "la oficina amplía el límite de negocios")
	check(ConstructionSim.build_block_reason(GameState, "pescaderia") != "", "pescadería bloqueada en mapa interior")
	check(ConstructionSim.build_block_reason(GameState, "vivienda") == "" and ConstructionSim.level_block_reason(GameState, "vivienda", 3) != "", "casa de ladrillo requiere investigación")
	# Expansión de zona.
	check(ConstructionSim.unlock_zone(GameState, 3, 2) == "", "zona vecina comprada")
	check(ConstructionSim.unlock_zone(GameState, 0, 0) != "", "zona no vecina rechazada")


func _test_phase2_housing() -> void:
	GameState.new_game({"seed": 12, "difficulty": "facil"})
	var normal := ConstructionSim.cost_for(GameState, "vivienda", 1, false, "normal")
	var alta := ConstructionSim.cost_for(GameState, "vivienda", 1, false, "alta")
	check(float(alta["total"]) > float(normal["total"]) * 2.0, "calidad alta cuesta más")
	var house := _build_now("vivienda", -30, -10, "media")
	check(house.get("tier", "") == "media" and float(house["rent"]) > 5.0, "vivienda media con renta mayor")
	# Forzar necesidad de vivienda: una familia sin hogar.
	var fam := []
	for c in GameState.citizens.values():
		if not GameState.is_player(c.id) and c.spouse_id >= 0:
			fam = [c, GameState.citizens[c.spouse_id]]
			break
	for c in fam:
		c.home_id = -1
		c.money += 200
	TimeManager.advance_days(40)
	var tenants := GameState.residents_of(int(house["id"])).size()
	check(tenants > 0, "familias alquilan tu vivienda (%d inquilinos)" % tenants)
	TimeManager.advance_days(30)
	check(BusinessSim.period_value(house, "last_month", "alquileres") > 0.0, "cobras alquiler")
	house["for_sale"] = true
	for c in GameState.residents_of(int(house["id"])):
		c.money += 5000
	var sold := false
	for i in range(8):
		TimeManager.advance_days(31)
		if house["owner"] == "ciudadano":
			sold = true
			break
	check(sold, "vivienda vendida a un ciudadano")
	var rc := ConstructionSim.renovation_cost(GameState, _build_now("vivienda", 34, 14))
	check(rc.get("tier", "") == "media", "remodelación a calidad media disponible")


func _test_phase2_player() -> void:
	GameState.new_game({"seed": 13, "player_name": "Ana", "player_surname": "Ríos", "player_gender": "F", "player_age": 30})
	var p := GameState.player_citizen()
	check(p != null and p.full_name() == "Ana Ríos" and p.gender == "F" and p.age_years(GameState.today()) == 30, "personaje creado con nombre, sexo y edad")
	check(GameState.owned_by_player(PlayerSim.player_home(GameState)), "el jugador tiene casa propia")
	var target: Citizen = null
	for c in GameState.citizens.values():
		if PlayerSim.can_court(GameState, c) == "":
			target = c
			break
	check(target != null, "hay alguien soltero para conocer")
	if target == null:
		return
	PlayerSim.talk(GameState, target)
	check(PlayerSim.talk(GameState, target) != "" and PlayerSim.affinity(GameState, target.id) > 0, "conversar sube la relación (una vez por día)")
	for i in range(40):
		TimeManager.advance_days(1)
		if PlayerSim.affinity(GameState, target.id) < 25:
			PlayerSim.talk(GameState, target)
		else:
			PlayerSim.date(GameState, target)
	var tries := 0
	while p.spouse_id < 0 and tries < 20:
		PlayerSim.propose(GameState, target)
		TimeManager.advance_days(1)
		PlayerSim.date(GameState, target)
		tries += 1
	check(p.spouse_id == target.id and target.home_id == p.home_id, "matrimonio: la pareja vive contigo")
	check(PlayerSim.try_child(GameState) == "Están buscando un bebé. Más probabilidad durante 30 días.", "buscar un bebé")
	var kids0 := p.children_ids.size()
	PlayerSim.adopt_baby(GameState)
	check(p.children_ids.size() == kids0 + 1, "adopción de bebé")
	var baby: Citizen = GameState.citizens[p.children_ids[-1]]
	check(baby.home_id == p.home_id and baby.last_name == p.last_name, "el bebé adoptado vive contigo y lleva tu apellido")
	# Herencia
	GameState.player["heir_id"] = baby.id
	PopulationSim.die(GameState, p, "prueba")
	check(GameState.running and GameState.player_id == baby.id, "el heredero toma el control")


func _test_interiors() -> void:
	GameState.new_game({"seed": 14})
	var h := {"type": "vivienda", "level": 1, "tier": "normal"}
	var items_n := Housing.interior_items(GameState, h)
	h["tier"] = "alta"
	var items_a := Housing.interior_items(GameState, h)
	var labels_n := items_n.map(func(i): return i["item"]["id"])
	var labels_a := items_a.map(func(i): return i["item"]["id"])
	check(labels_n.has("jergon") and labels_n.has("bacinilla") and labels_n.has("fogon"), "casa normal 1700: jergón, bacinilla y fogón")
	check(labels_a.has("cama_lana") and not labels_a.has("cama_dosel") and not labels_a.has("banera_hierro"), "choza alta: cama de lana, sin lujos de otra época")
	var ladrillo_alta := Housing.interior_items(GameState, {"type": "vivienda", "level": 3, "tier": "alta"}).map(func(i): return i["item"]["id"])
	check(ladrillo_alta.has("cama_dosel") and ladrillo_alta.has("banera_hierro"), "casa de ladrillo alta: cama con dosel y bañera")
	check(ConstructionSim.level_block_reason(GameState, "vivienda", 2) != "", "la casa de adobe requiere investigación")
	GameState.techs.append_array(["saneamiento", "electricidad"])
	var labels_e := Housing.interior_items(GameState, {"type": "vivienda", "level": 1, "tier": "normal"}).map(func(i): return i["item"]["id"])
	check(labels_e.has("inodoro") and labels_e.has("bombilla"), "otra época: inodoro y bombilla")


func _test_time_speeds() -> void:
	GameState.new_game({"seed": 15})
	TimeManager.set_speed(TimeManager.SPEED_REALTIME)
	var h0 := TimeManager.total_hours
	TimeManager._process(10.0)
	check(TimeManager.total_hours == h0 and TimeManager.hour_fraction > 0.0027 and TimeManager.hour_fraction < 0.0029, "tiempo real: 10 s reales = 10 s de juego")
	TimeManager.set_speed(2)
	TimeManager._process(2.0)
	check(TimeManager.total_hours == h0 + 2, "x1: 2 s = 2 horas")
	TimeManager.set_speed(0)



func _hire_n(b: Dictionary, n: int) -> void:
	for c in BusinessSim.candidates(GameState, b).slice(0, n):
		BusinessSim.hire(GameState, b, c, BusinessSim.asked_wage(GameState, c, b["type"]))


func _test_phase3_prices() -> void:
	GameState.new_game({"seed": 41, "difficulty": "facil"})
	var farm := _build_now("granja", 30, -8)
	var well := _build_now("aguatero", -30, 8)
	_hire_n(farm, 4)
	_hire_n(well, 3)
	for m in range(18):
		TimeManager.advance_days(30)
	var fw := EconomySim.good_factor(GameState, "agua")
	print("    18 meses: agua x%.2f comida x%.2f · nivel precios %.3f · inflación %.1f%%" % [fw, EconomySim.good_factor(GameState, "comida"), GameState.price_level(), EconomySim.annual_inflation(GameState) * 100.0])
	check(fw < 1.0, "exceso de agua: el precio de mercado baja")
	var lvl := GameState.price_level()
	check(lvl > 0.9 and lvl < 1.3, "inflación moderada (nivel %.3f)" % lvl)
	# Escasez: una granja sin empleados que tenía clientes.
	for c in GameState.employees_of(int(farm["id"])):
		BusinessSim.fire(GameState, c)
	farm["inventory"]["comida"] = 0.0
	var before := EconomySim.good_factor(GameState, "comida")
	TimeManager.advance_days(95)
	check(EconomySim.good_factor(GameState, "comida") > before, "escasez de comida: el precio sube")
	check(float(farm["price"]) > 0.0 and bool(farm.get("auto_price", false)), "precio automático activo")


func _test_phase3_player_loans() -> void:
	GameState.new_game({"seed": 42, "difficulty": "normal"})
	var lim := BankSim.credit_limit(GameState)
	check(lim > 0.0, "el banco externo ofrece crédito (%.0f)" % lim)
	check(BankSim.request_player_loan(GameState, lim * 10.0, 12) != "", "no presta sobre el límite")
	var m0 := GameState.money
	check(BankSim.request_player_loan(GameState, 1000.0, 12) == "" and is_equal_approx(GameState.money, m0 + 1000.0), "préstamo de 1000 recibido")
	var l: Dictionary = BankSim.player_loans(GameState)[0]
	check(float(l["payment"]) > 1000.0 / 12.0, "cuota con intereses (%.2f)" % float(l["payment"]))
	TimeManager.advance_days(95)
	check(int(l["months_paid"]) >= 3 and float(l["balance"]) < 1000.0, "cuotas pagadas mes a mes")
	check(BankSim.repay_loan(GameState, int(l["id"])) == "" and BankSim.player_loans(GameState).is_empty(), "pago anticipado")
	# Impago → embargo
	var shop := _build_now("tienda", 30, -8)
	BankSim.request_player_loan(GameState, 800.0, 12)
	GameState.money = -50000.0
	TimeManager.advance_days(125)
	check(shop["owner"] == "pueblo", "impago: el banco embarga tus propiedades")


func _test_phase3_bank() -> void:
	var results := {}
	for rate in [0.05, 0.40]:
		GameState.new_game({"seed": 43, "difficulty": "facil"})
		GameState.money = 30000.0
		var bank := _build_now("banco", 32, -6)
		_hire_n(bank, 3)
		BankSim.bank_settings(GameState, bank)
		bank["loan_rate"] = rate
		for c in GameState.citizens.values():
			if not GameState.is_player(c.id):
				c.money = minf(c.money, 5.0)
		for m in range(12):
			GameState.money = maxf(GameState.money, 30000.0)
			TimeManager.advance_days(30)
		results[rate] = {"loans": BankSim.bank_loans(GameState, bank).size() + BusinessSim.period_value(bank, "total", "prestado") / 100.0,
			"interest": BusinessSim.period_value(bank, "total", "intereses")}
	print("    banco tasa 5%%: %s · tasa 40%%: %s" % [str(results[0.05]), str(results[0.40])])
	check(float(results[0.05]["loans"]) > 0.0, "tu banco presta a ciudadanos")
	check(float(results[0.05]["interest"]) > 0.0, "cobra intereses")
	check(float(results[0.05]["loans"]) > float(results[0.40]["loans"]), "tasas altas reducen la demanda de crédito")
	# Guardar y cargar con préstamos y economía.
	SaveManager.save_game("test_f3")
	var n := GameState.loans.size()
	var lvl := GameState.price_level()
	SaveManager.load_game("test_f3")
	check(GameState.loans.size() == n and is_equal_approx(GameState.price_level(), lvl), "préstamos y economía se guardan")
	SaveManager.delete_save("test_f3")


func _test_phase3_bankruptcy() -> void:
	GameState.new_game({"seed": 44, "difficulty": "normal"})
	var tav := _build_now("taberna", 30, -8)
	_hire_n(tav, 3)
	for c in GameState.employees_of(int(tav["id"])):
		c.wage = 50.0  # salarios imposibles
	var closed := false
	for m in range(9):
		TimeManager.advance_days(30)
		GameState.money = minf(GameState.money, -10.0)
		GameState.player["negative_months"] = 0
		if tav["status"] == "cerrado":
			closed = true
			break
	check(closed, "negocio con pérdidas constantes quiebra")
	check(GameState.employees_of(int(tav["id"])).is_empty(), "la quiebra despide al personal")
	GameState.money = 5000.0
	check(BusinessSim.reopen(GameState, tav) == "" and tav["status"] == "activo", "se puede reabrir")
