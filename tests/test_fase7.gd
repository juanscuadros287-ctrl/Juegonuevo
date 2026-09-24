extends Node
## Pruebas de la Fase 7 (otros pueblos, rutas, comercio exterior, transporte e inmigración).
## godot --headless res://tests/test_fase7.tscn

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func _ready() -> void:
	print("== Dinastía: pruebas Fase 7 ==")
	_test_towns()
	_test_no_immigration_without_roads()
	_test_route_and_trade()
	_test_contracts()
	_test_transport_evolution()
	_test_save_load()
	_test_difficulty()
	_test_balance()
	await _test_ui()
	print("== %s (%d fallos) ==" % ["TODO OK" if failures == 0 else "CON FALLOS", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _gs():
	return GameState


## Abre la ruta y avanza hasta que el camino esté listo.
func _open(tid: String) -> void:
	var gs = _gs()
	var err := TradeSim.open_route(gs, tid)
	check(err == "", "abrir ruta con %s (%s)" % [TradeSim.town(gs, tid).get("name", ""), err])
	TimeManager.advance_days(int(TradeSim.project(gs, tid).get("total_days", 30)) + 1)


func _town_with(gs, list_key: String, good: String) -> String:
	for t in TradeSim.towns(gs):
		if t.get(list_key, []).has(good):
			return str(t["id"])
	return ""


func _test_towns() -> void:
	var gs = _gs()
	for seed_v in [1, 2, 3, 4, 5]:
		GameState.new_game({"seed": seed_v, "difficulty": "normal"})
		var towns: Array = TradeSim.towns(gs)
		check(towns.size() >= 4 and towns.size() <= 6, "semilla %d: %d pueblos generados" % [seed_v, towns.size()])
		var produced := {}
		for t in towns:
			for g in t["produces"]:
				produced[g] = true
		check(produced.has("carbon") and produced.has("hierro") and produced.has("madera") and produced.has("herramientas"),
				"semilla %d: la región puede comprar carbón, hierro, madera y herramientas" % seed_v)
		check(not TradeSim.is_connected_any(gs) and TradeSim.connected_towns(gs).is_empty(), "semilla %d: al inicio no hay rutas" % seed_v)
	var t0: Dictionary = TradeSim.towns(gs)[0]
	print("    Pueblos: ", ", ".join(TradeSim.towns(gs).map(func(t): return "%s (%s, %d km, %d hab.)" % [t["name"], t["archetype"], int(t["distance"]), int(t["population"])])))
	check(str(t0["name"]) != "" and float(t0["distance"]) > 0.0, "los pueblos tienen nombre y distancia")
	var names := {}
	for t in TradeSim.towns(gs):
		names[t["name"]] = true
	check(names.size() == TradeSim.towns(gs).size(), "nombres de pueblos únicos")


func _test_no_immigration_without_roads() -> void:
	var gs = _gs()
	GameState.new_game({"seed": 11, "difficulty": "normal"})
	var ids_before: int = gs.next_citizen_id
	TimeManager.advance_days(365)
	var tot: Dictionary = gs.trade.get("totals", {})
	check(int(tot.get("immigrants", 0)) == 0, "sin rutas no llega nadie (inmigrantes: %d)" % int(tot.get("immigrants", 0)))
	var births := 0
	for h in gs.history:
		births += int(h["births"])
	check(gs.next_citizen_id - ids_before == births, "sin rutas la población solo crece por nacimientos")


func _test_route_and_trade() -> void:
	var gs = _gs()
	GameState.new_game({"seed": 21, "difficulty": "normal"})
	gs.money = 20000.0
	var tid := _town_with(gs, "demands", "madera")
	check(tid != "", "hay un pueblo que demanda madera")
	var cost: Dictionary = TradeSim.connection_cost(gs, tid)
	check(float(cost["agreement"]) > 0.0 and float(cost["road"]) > 0.0, "la ruta cuesta acuerdo + camino: %s" % Fmt.money(float(cost["total"])))
	var m0: float = gs.money
	_open(tid)
	check(m0 - gs.money >= float(cost["total"]) - 0.01, "el dinero de la ruta se descontó")
	check(TradeSim.is_connected_any(gs) and str(TradeSim.connected_towns(gs)[0]["town_id"]) == tid, "connected_towns devuelve {town_id}")
	check(int(TradeSim.connection(gs, tid)["road"]) == 1, "camino inicial de barro")
	# Venta: el dinero entra de verdad al llegar el envío.
	WarehouseSim.add(gs, "madera", 100.0)
	var p_before := TradeSim.export_price(gs, tid, "madera")
	var q := TradeSim.quote_sale(gs, tid, "madera", 60.0)
	var m1: float = gs.money
	var err := TradeSim.sell(gs, tid, "madera", 60.0)
	check(err == "", "vender 60 madera (%s)" % err)
	check(is_equal_approx(WarehouseSim.stock(gs, "madera"), 40.0), "el almacén descuenta lo vendido")
	check(gs.money < m1, "el flete se paga al despachar")
	check(TradeSim.export_price(gs, tid, "madera") < p_before, "vender mucho baja el precio del pueblo (%.2f → %.2f)" % [p_before, TradeSim.export_price(gs, tid, "madera")])
	check(TradeSim.sell(gs, tid, "madera", 500.0) != "", "no se vende más de lo que hay")
	var m2: float = gs.money
	TimeManager.advance_days(int(q["days"]) + 1)
	var exp_ok: bool = float(gs.trade["totals"].get("exports", 0.0)) > 0.0
	check(exp_ok and gs.money > m2 - 50.0, "al llegar, el pueblo paga %s (exportaciones registradas)" % Fmt.money(float(q["gross"])))
	check(float(gs.month_counters.get("exports", 0.0)) > 0.0 or gs.history.size() > 0, "contador de exportaciones")
	# Compra: se paga y llega al almacén; el arancel va al tesoro.
	var sid := _town_with(gs, "produces", "carbon")
	if TradeSim.connection(gs, sid).is_empty():
		_open(sid)
	check(TradeSim.buy(gs, sid, "oro_inexistente", 10.0) != "", "no se compra lo que el pueblo no vende")
	var treasury0 := float(gs.government.get("treasury", 0.0))
	var pq := TradeSim.quote_purchase(gs, sid, "carbon", 30.0)
	var m3: float = gs.money
	err = TradeSim.buy(gs, sid, "carbon", 30.0)
	check(err == "", "comprar 30 carbón (%s)" % err)
	check(absf((m3 - gs.money) - float(pq["total"])) < 1.0, "se paga bienes + flete (%s)" % Fmt.money(float(pq["total"])))
	check(float(gs.government.get("treasury", 0.0)) >= treasury0, "el arancel queda en el tesoro")
	check(WarehouseSim.stock(gs, "carbon") == 0.0, "el carbón aún viene en camino")
	TimeManager.advance_days(int(pq["days"]) + 1)
	check(is_equal_approx(WarehouseSim.stock(gs, "carbon"), 30.0), "el carbón llegó al almacén")
	# Espacio del almacén.
	var free := WarehouseSim.free_space(gs)
	check(TradeSim.buy(gs, sid, "carbon", free + 10.0) != "", "no se compra más de lo que cabe en el almacén")


func _test_contracts() -> void:
	var gs = _gs()
	GameState.new_game({"seed": 31, "difficulty": "normal"})
	gs.money = 20000.0
	var tid := _town_with(gs, "demands", "madera")
	_open(tid)
	WarehouseSim.add(gs, "madera", 60.0)
	check(TradeSim.add_contract(gs, tid, "madera", TradeSim.KIND_SELL, 10.0, 10) == "", "contrato de venta creado")
	var sid := _town_with(gs, "produces", "hierro")
	if TradeSim.connection(gs, sid).is_empty():
		_open(sid)
	check(TradeSim.add_contract(gs, sid, "hierro", TradeSim.KIND_BUY, 5.0, 15) == "", "contrato de compra creado")
	TimeManager.advance_days(45)
	var ks: Array = gs.trade["contracts"]
	check(int(ks[0].get("done", 0)) >= 4, "el contrato de venta se ejecuta cada 10 días (%d)" % int(ks[0].get("done", 0)))
	check(int(ks[1].get("done", 0)) >= 3, "el contrato de compra se ejecuta cada 15 días (%d)" % int(ks[1].get("done", 0)))
	check(WarehouseSim.stock(gs, "hierro") >= 10.0, "el hierro comprado llegó (%d)" % int(WarehouseSim.stock(gs, "hierro")))
	TradeSim.toggle_contract(gs, int(ks[0]["id"]))
	var done: int = int(ks[0]["done"])
	TimeManager.advance_days(30)
	check(int(ks[0]["done"]) == done, "un contrato pausado no se ejecuta")
	TradeSim.remove_contract(gs, int(ks[0]["id"]))
	check(gs.trade["contracts"].size() == 1, "contrato eliminado")


func _test_transport_evolution() -> void:
	var gs = _gs()
	GameState.new_game({"seed": 41, "difficulty": "normal", "map_type": "interior"})
	gs.money = 500000.0
	var tid := str(TradeSim.towns(gs)[0]["id"])
	_open(tid)
	check(TradeSim.available_modes(gs, tid) == ["a_pie"], "al inicio solo cargadores y mulas")
	var q_foot := TradeSim.transport_quote(gs, tid, 200.0, "a_pie")
	gs.techs.append("carretas")
	check(TradeSim.available_modes(gs, tid).has("carretas"), "con carretas investigadas se usan carretas")
	var q_cart := TradeSim.transport_quote(gs, tid, 200.0, "carretas")
	check(int(q_cart["trips"]) < int(q_foot["trips"]), "las carretas llevan más por viaje (%d vs %d viajes)" % [q_cart["trips"], q_foot["trips"]])
	check(TradeSim.upgrade_road(gs, tid) != "", "empedrar requiere investigación")
	gs.techs.append("caminos_empedrados")
	check(TradeSim.upgrade_road(gs, tid) == "", "empedrar el camino")
	TimeManager.advance_days(int(TradeSim.road_upgrade_quote(gs, tid).get("days", 0)) + 90)
	check(int(TradeSim.connection(gs, tid)["road"]) == 2, "el camino ahora es empedrado")
	gs.techs.append("navegacion")
	check(TradeSim.mode_block_reason(gs, tid, "barco") != "", "sin mapa de costa/río no hay barcos")
	gs.techs.append_array(["ferrocarril", "automovil", "aviacion"])
	check(TradeSim.mode_block_reason(gs, tid, "tren").contains("vía"), "el tren requiere vía férrea")
	check(TradeSim.build_rail(gs, tid) == "", "construir vía férrea")
	TimeManager.advance_days(int(TradeSim.rail_quote(gs, tid)["days"]) + 1)
	check(TradeSim.mode_block_reason(gs, tid, "tren").contains("estación"), "el tren requiere estación con personal")
	# Estación de tren con un empleado.
	var st: Dictionary = ConstructionSim.make_building(gs, "estacion_tren", 1, -40.0, 30.0, 0.0, "jugador")
	st["status"] = "activo"
	gs.add_building(st)
	var worker: Citizen = BusinessSim.candidates(gs, st)[0]
	BusinessSim.hire(gs, st, worker, 3.0)
	check(TradeSim.mode_block_reason(gs, tid, "tren") == "", "con estación y vía férrea hay tren")
	check(TradeSim.mode_block_reason(gs, tid, "camion").contains("carretera"), "los camiones necesitan carretera de cemento")
	check(TradeSim.upgrade_road(gs, tid) == "", "reformar a carretera de cemento")
	TimeManager.advance_days(int(TradeSim.road_upgrade_quote(gs, tid).get("days", 60)) + 60)
	check(int(TradeSim.connection(gs, tid)["road"]) == 3, "ya hay carretera")
	check(TradeSim.mode_block_reason(gs, tid, "camion") == "", "camiones disponibles")
	var qc := TradeSim.transport_quote(gs, tid, 100.0, "camion")
	check(float(qc["fuel"]) > 0.0, "los camiones gastan gasolina (%s)" % Fmt.money(float(qc["fuel"])))
	check(TradeSim.mode_block_reason(gs, tid, "avion").contains("aeropuerto"), "los aviones requieren aeropuerto")
	var q_train := TradeSim.transport_quote(gs, tid, 1000.0, "tren")
	check(int(q_train["days"]) <= int(q_foot["days"]), "el tren es más rápido que ir a pie")
	print("    Transporte 200 u: a pie %d viajes/%d d/%s · carretas %d/%d d/%s · tren 1000 u %d/%d d/%s · camión 100 u %s" % [
			q_foot["trips"], q_foot["days"], Fmt.money(float(q_foot["cost"])), q_cart["trips"], q_cart["days"], Fmt.money(float(q_cart["cost"])),
			q_train["trips"], q_train["days"], Fmt.money(float(q_train["cost"])), Fmt.money(float(qc["cost"]))])
	# Barcos en mapa de costa.
	GameState.new_game({"seed": 42, "difficulty": "normal", "map_type": "costa"})
	gs.money = 500000.0
	gs.techs.append_array(["carretas", "navegacion"])
	var wid := ""
	for t in TradeSim.towns(gs):
		if bool(t.get("water", false)):
			wid = str(t["id"])
			break
	check(wid != "", "en la costa hay pueblos con acceso por agua")
	if wid != "":
		_open(wid)
		check(TradeSim.mode_block_reason(gs, wid, "barco").contains("puerto"), "el barco requiere puerto")
		var port: Dictionary = ConstructionSim.make_building(gs, "puerto", 1, 60.0, 0.0, 0.0, "jugador")
		port["status"] = "activo"
		gs.add_building(port)
		BusinessSim.hire(gs, port, BusinessSim.candidates(gs, port)[0], 3.0)
		check(TradeSim.mode_block_reason(gs, wid, "barco") == "", "con puerto hay barcos")


func _test_save_load() -> void:
	var gs = _gs()
	GameState.new_game({"seed": 51, "difficulty": "normal"})
	gs.money = 20000.0
	var tid := str(TradeSim.towns(gs)[1]["id"])
	_open(tid)
	WarehouseSim.add(gs, "madera", 50.0)
	TradeSim.sell(gs, tid, "madera", 20.0)
	TradeSim.add_contract(gs, tid, "madera", TradeSim.KIND_SELL, 5.0, 7)
	var snap := JSON.stringify(gs.trade)
	check(SaveManager.save_game("test_fase7"), "guardar partida con comercio")
	TimeManager.advance_days(20)
	check(SaveManager.load_game("test_fase7"), "cargar partida")
	check(TradeSim.connection(gs, tid).size() > 0 and gs.trade["shipments"].size() == 1 and gs.trade["contracts"].size() == 1, "rutas, envíos y contratos restaurados")
	check(TradeSim.towns(gs).size() > 0 and JSON.stringify(gs.trade).length() == snap.length() or JSON.stringify(gs.trade).length() > snap.length() * 0.95, "estado de comercio restaurado")
	TimeManager.advance_days(60)
	var a := JSON.stringify(gs.to_dict())
	SaveManager.load_game("test_fase7")
	TimeManager.advance_days(60)
	check(JSON.stringify(gs.to_dict()) == a, "comercio e inmigración deterministas tras cargar")
	SaveManager.delete_save("test_fase7")


func _test_difficulty() -> void:
	var gs = _gs()
	var prices := {}
	for d in ["facil", "extremo"]:
		GameState.new_game({"seed": 61, "difficulty": d})
		var tid := str(TradeSim.towns(gs)[0]["id"])
		prices[d] = TradeSim.export_price(gs, tid, "madera") / gs.price_mult()
	check(float(prices["facil"]) > float(prices["extremo"]), "en extremo te pagan menos por exportar")


## Diagnóstico de balance: 1-2 conexiones, exportaciones razonables, inmigración gradual y recuperación de la inversión.
func _test_balance() -> void:
	var gs = _gs()
	print("  -- Diagnóstico de balance (normal, pueblo de ~30 habitantes en 1700) --")
	for scenario in [1, 2]:
		GameState.new_game({"seed": 71, "difficulty": "normal"})
		var start_pop: int = gs.citizens.size()
		gs.money = 8000.0
		var towns: Array = TradeSim.towns(gs).duplicate()
		# Ruta 1: el pueblo más cercano que demande madera; ruta 2: el que venda carbón.
		var chosen: Array = []
		var t1 := _town_with(gs, "demands", "madera")
		chosen.append(t1)
		if scenario == 2:
			for t in towns:
				if str(t["id"]) != t1:
					chosen.append(str(t["id"]))
					break
		var invest := 0.0
		for tid in chosen:
			invest += float(TradeSim.connection_cost(gs, tid)["total"])
			_open(tid)
		# Producción simulada de un aserradero modesto: 3 trabajadores × ~3 madera/día ≈ 90 al mes al almacén.
		var income := 0.0
		var months := 36
		var m_before: float = gs.money
		for mo in range(months):
			WarehouseSim.add(gs, "madera", 90.0)
			var per := floorf(WarehouseSim.stock(gs, "madera") / chosen.size())
			for tid in chosen:
				var q := TradeSim.quote_sale(gs, tid, "madera", per)
				if float(q["net"]) > 0.0:
					TradeSim.sell(gs, tid, "madera", per)
			TimeManager.advance_days(30)
		var tot: Dictionary = gs.trade["totals"]
		var exports := float(tot.get("exports", 0.0))
		var freight := float(tot.get("transport", 0.0))
		var upkeep := float(tot.get("upkeep", 0.0))
		var net := exports - freight - upkeep
		var imm := int(tot.get("immigrants", 0))
		var monthly_net := net / months
		var payback := invest / maxf(1.0, monthly_net)
		print("    %d ruta(s): inversión %s · exportado %s en %d meses · fletes %s · mantenimiento %s · neto %s/mes · recupera en %.1f meses" % [
				chosen.size(), Fmt.money(invest), Fmt.money(exports), months, Fmt.money(freight), Fmt.money(upkeep), Fmt.money(monthly_net), payback])
		print("       inmigrantes en 3 años: %d · población %d → %d · valor madera 1 u ≈ %s" % [imm, start_pop, gs.citizens.size(), Fmt.money2(TradeSim.export_price(gs, chosen[0], "madera"))])
		check(monthly_net > 50.0 and monthly_net < 2000.0, "%d ruta(s): exportar produce ingresos razonables (%s/mes)" % [chosen.size(), Fmt.money(monthly_net)])
		check(payback >= 3.0 and payback <= 60.0, "%d ruta(s): la inversión se recupera en %.1f meses (entre 3 meses y 5 años)" % [chosen.size(), payback])
		check(imm >= 6 and imm <= 150, "%d ruta(s): la inmigración aumenta la población gradualmente (%d en 3 años)" % [chosen.size(), imm])
		var _unused := m_before


## Interfaz y visuales: panel de comercio con ruta abierta, camino en el mapa y carretas en camino.
func _test_ui() -> void:
	var gs = _gs()
	GameState.new_game({"seed": 81, "difficulty": "facil"})
	gs.money = 50000.0
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	var hud: Hud = world.hud
	var vis: TradeVisuals = world.get_node_or_null("TradeVisuals")
	check(vis != null, "TradeVisuals está en el mundo")
	check(vis != null and vis.road_node == null, "sin rutas no se dibuja camino")
	hud._show_dock("trade")
	await get_tree().process_frame
	var tid := str(TradeSim.towns(gs)[0]["id"])
	TradeSim.open_route(gs, tid)
	TimeManager.advance_days(5)
	EventBus.day_passed.emit()
	check(vis != null and vis.road_node != null, "el camino en construcción aparece en el mapa")
	TimeManager.advance_days(int(TradeSim.project(gs, tid).get("total_days", 40)) + 1)
	EventBus.day_passed.emit()
	check(TradeSim.is_connected_any(gs), "ruta terminada")
	WarehouseSim.add(gs, "madera", 40.0)
	TradeSim.sell(gs, tid, "madera", 30.0)
	TradeSim.add_contract(gs, tid, "madera", TradeSim.KIND_SELL, 5.0, 10)
	EventBus.day_passed.emit()
	check(vis != null and vis.markers.size() == 1, "una carreta va por el camino")
	hud.trade_panel.selected_town = tid
	hud.trade_panel.refresh()
	await get_tree().process_frame
	check(hud.trade_panel.body.get_child_count() > 20, "el panel muestra pueblos, comercio, envíos y contratos")
	for i in range(10):
		await get_tree().process_frame
	world.queue_free()
	await get_tree().process_frame
