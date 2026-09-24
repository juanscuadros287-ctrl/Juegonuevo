extends Node
## Pruebas de la Fase 6 (recursos por región, almacén, recetas, transporte y carreteras).
## godot --headless res://tests/test_fase6.tscn

var failures := 0
var ui_done := false
var gs = GameState


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func _ready() -> void:
	print("== Dinastía: pruebas Fase 6 ==")
	_test_regions()
	_test_deposit_rule()
	_test_region_bonus()
	_test_warehouse_construction()
	_test_chain_diagnostic()
	_test_recipe_limits()
	_test_routes_on_foot()
	_test_roads_and_carts()
	_test_shop_sales()
	_test_save_load()
	await _test_ui()
	check(ui_done, "la prueba de interfaz terminó sin errores de script")
	print("== %s (%d fallos) ==" % ["TODO OK" if failures == 0 else "CON FALLOS", failures])
	get_tree().quit(1 if failures > 0 else 0)


# --- Utilidades -----------------------------------------------------------------------------

## Coloca un edificio del jugador ya terminado (sin obra ni costo).
func _place(type_id: String, x: float, z: float, level := 1) -> Dictionary:
	var b: Dictionary = ConstructionSim.make_building(gs, type_id, level, x, z, 0.0, "jugador")
	gs.add_building(b)
	return b


func _hire(b: Dictionary, n: int) -> int:
	var hired := 0
	for c in BusinessSim.candidates(gs, b):
		if hired >= n:
			break
		if c.job_kind == "obra":
			continue
		if BusinessSim.hire(gs, b, c, BusinessSim.asked_wage(gs, c, str(b["type"])) * 1.1) == "":
			hired += 1
	return hired


func _new(seed_value := 11, map := "interior", region := "") -> void:
	gs.new_game({"seed": seed_value, "difficulty": "facil", "map_type": map, "region": region})
	gs.suppress_notifications = true
	gs.money = 200000.0


func _set_deposits(list: Array) -> void:
	var out := []
	for d in list:
		out.append({"id": out.size() + 1, "type": d[0], "x": float(d[1]), "z": float(d[2]), "amount": float(d[3]), "initial": float(d[3])})
	gs.logistics["deposits"] = out


# --- Pruebas ------------------------------------------------------------------------------------

func _test_regions() -> void:
	for map in GameData.map_types:
		var cands := RegionSim.candidates(map, 1234)
		var ids := {}
		for c in cands:
			ids[str(c["id"])] = true
		check(cands.size() >= 3 and cands.size() <= 4 and ids.size() == cands.size(), "%s: %d lugares distintos para fundar" % [map, cands.size()])
		check(str(RegionSim.candidates(map, 1234)[0]["name"]) == str(cands[0]["name"]), "%s: candidatos deterministas por semilla" % map)
	var t0 := Time.get_ticks_msec()
	var pick: Dictionary = RegionSim.candidates("montana", 77)[1]
	_new(77, "montana", str(pick["id"]))
	print("    nueva partida con región en %d ms · %s · %s" % [Time.get_ticks_msec() - t0, pick["name"], RegionSim.strengths_text(pick)])
	check(str(gs.settings.get("region", "")) == str(pick["id"]) and str(gs.logistics["region"]["id"]) == str(pick["id"]), "la región elegida queda en settings y logistics")
	var deps: Array = RegionSim.deposits(gs)
	var expected := 0
	for t in pick.get("deposits", {}):
		expected += int(pick["deposits"][t])
	check(deps.size() >= expected, "yacimientos generados (%d, esperados ≥ %d)" % [deps.size(), expected])
	var near := 0
	for d in deps:
		var p := Vector2(float(d["x"]), float(d["z"]))
		if absf(p.x) < 40.0 and absf(p.y) < 40.0:
			near += 1
		check(float(d["amount"]) > 0.0 and RegionSim.deposit_types().has(str(d["type"])), "yacimiento de %s en (%d, %d) con %d unidades" % [d["type"], int(p.x), int(p.y), int(d["amount"])])
	check(expected == 0 or near >= 1, "al menos un yacimiento en el terreno inicial (%d)" % near)
	# Partidas sin región (antiguas o de pruebas) reciben la primera candidata.
	gs.new_game({"seed": 5})
	check(not gs.logistics.get("region", {}).is_empty() and str(gs.settings.get("region", "")) != "", "partida sin región elegida recibe una por defecto")


func _test_deposit_rule() -> void:
	_new(21)
	_set_deposits([["oro", 25, 20, 1000]])
	var far := ConstructionSim.placement_block_reason(gs, "mina_oro", -25.0, -22.0)
	check(far.find("yacimiento") >= 0, "no se puede poner una mina de oro sin oro: '%s'" % far)
	check(RegionSim.deposit_block_reason(gs, "mina_oro", 27.0, 24.0) == "", "sí se puede junto al yacimiento de oro")
	check(RegionSim.deposit_block_reason(gs, "mina_plata", 27.0, 24.0) != "", "una mina de plata exige plata, no oro")
	check(RegionSim.deposit_block_reason(gs, "granja", 27.0, 24.0) == "", "los negocios sin requires_deposit no cambian")
	# Extracción agota lentamente el yacimiento.
	var mine := _place("mina_oro", 26, 21)
	_hire(mine, 6)
	TimeManager.advance_days(30)
	var dep: Dictionary = RegionSim.deposits(gs)[0]
	var extracted := 1000.0 - float(dep["amount"])
	check(extracted > 1.0 and extracted < 200.0, "la mina extrae oro y el yacimiento baja lentamente (%.1f en 30 días)" % extracted)
	dep["amount"] = 0.5
	TimeManager.advance_days(3)
	check(float(dep["amount"]) <= 0.0 and str(mine.get("chain_status", "")) == "sin yacimiento", "yacimiento agotado: la mina deja de producir")


func _test_region_bonus() -> void:
	var cands := RegionSim.candidates("interior", 3)
	var fert := {}
	var poor := {}
	for c in cands:
		if float(c.get("strengths", {}).get("tierra_fertil", 1.0)) > 1.2:
			fert = c
		elif float(c.get("strengths", {}).get("tierra_fertil", 1.0)) <= 1.0:
			poor = c
	if fert.is_empty() or poor.is_empty():
		print("    (sin par de regiones fértil/pobre en esta semilla)")
		return
	var outs := []
	for reg in [fert, poor]:
		_new(3, "interior", str(reg["id"]))
		var farm := _place("trigal", 20, -20)
		_hire(farm, 4)
		outs.append(BusinessSim.expected_output(gs, farm))
	check(outs[0] > outs[1] * 1.15, "la tierra fértil rinde más trigo (%.1f vs %.1f por día)" % [outs[0], outs[1]])


func _test_warehouse_construction() -> void:
	_new(31)
	WarehouseSim.add(gs, "madera", 100.0)
	var cost: Dictionary = ConstructionSim.cost_for(gs, "granja", 1, false)
	check(float(cost["from_stock"]["madera"]) >= 20.0 and float(cost["import"]["madera"]) == 0.0, "la madera del almacén sirve para construir")
	var r := ConstructionSim.start_construction(gs, "granja", 30, -20, 0.0, "Granja Test", "sas")
	check(r.has("building") and is_equal_approx(WarehouseSim.stock(gs, "madera"), 80.0), "construir consume madera del almacén (quedan %.0f)" % WarehouseSim.stock(gs, "madera"))
	var cap0 := WarehouseSim.capacity(gs)
	var alm := _place("almacen", -25, 25)
	check(WarehouseSim.capacity(gs) > cap0 + 400.0, "el edificio Almacén amplía la capacidad (%d → %d)" % [int(cap0), int(WarehouseSim.capacity(gs))])
	alm["level"] = 2
	check(WarehouseSim.capacity(gs) >= cap0 + 1500.0, "mejorar el almacén da más capacidad (%d)" % int(WarehouseSim.capacity(gs)))


## Diagnóstico: hierro + carbón → herramientas, con precios razonables y rentable.
func _test_chain_diagnostic() -> void:
	_new(41)
	_set_deposits([["hierro", 22, 16, 12000], ["carbon", -22, 16, 12000]])
	var office := _place("oficina", 0, -22)
	var iron := _place("mina_hierro", 22, 17)
	var coal := _place("mina_carbon", -22, 17)
	var smith := _place("herreria", 16, -16)
	var shop := _place("tienda", -16, -16)
	_place("almacen", 0, 22)
	for pair in [[iron, 2], [coal, 2], [smith, 4], [shop, 2]]:
		_hire(pair[0], pair[1])
	check(LogisticsSim.in_reach(gs, iron) and LogisticsSim.in_reach(gs, coal), "minas a menos de 30 m de la bodega: descargan directo al almacén")
	var t0: int = gs.today()
	TimeManager.advance_days(60)
	for b in [iron, coal, smith]:
		print("    %s: %d empleados · %.2f/día esperado · estado '%s'" % [gs.building_label(b), gs.employees_of(int(b["id"])).size(), BusinessSim.expected_output(gs, b), str(b.get("chain_status", ""))])
	var tools := WarehouseSim.stock(gs, "herramientas")
	var sold := BusinessSim.period_value(shop, "total", "ventas")
	print("    almacén tras 60 días: %s · vendido en la tienda %s" % [str(WarehouseSim.all_stock(gs)), Fmt.money(sold)])
	check(BusinessSim.period_value(smith, "total", "salarios") > 0.0 and (tools > 0.0 or sold > 0.0), "la herrería produce herramientas con hierro y carbón del almacén")
	# Economía de la cadena: costos (salarios + mantenimiento) vs valor de mercado de lo producido.
	var pm: float = gs.price_mult()
	var costs := 0.0
	for b in [iron, coal, smith]:
		costs += BusinessSim.period_value(b, "total", "salarios") + BusinessSim.period_value(b, "total", "mantenimiento")
	var value := WarehouseSim.value(gs) + sold
	print("    60 días: costos %s · valor producido %s (precio herramientas %s, hierro %s, carbón %s) · margen %.0f%%" % [
		Fmt.money(costs), Fmt.money(value), Fmt.money2(EconomySim.market_price(gs, "herramientas")),
		Fmt.money2(EconomySim.market_price(gs, "hierro")), Fmt.money2(EconomySim.market_price(gs, "carbon")), (value / maxf(1.0, costs) - 1.0) * 100.0])
	check(value > costs, "la cadena hierro+carbón → herramientas es rentable a precios de mercado")
	var unit_value_added: float = (GameData.goods["herramientas"]["base_price"] - GameData.goods["hierro"]["base_price"] - GameData.goods["carbon"]["base_price"]) * pm
	check(unit_value_added > 0.0, "el producto elaborado vale más que sus materias primas (+%s por unidad)" % Fmt.money2(unit_value_added))
	check(gs.today() - t0 == 60 and office["status"] == "activo", "simulación estable")


func _test_recipe_limits() -> void:
	_new(51)
	var smith := _place("herreria", 16, -16)
	_hire(smith, 4)
	WarehouseSim.add(gs, "hierro", 1.0)
	WarehouseSim.add(gs, "carbon", 0.5)
	BusinessSim.produce(gs)
	var made := WarehouseSim.stock(gs, "herramientas")
	check(made > 0.4 and made <= 0.5001 and WarehouseSim.stock(gs, "carbon") < 0.001, "faltan insumos: produce proporcionalmente (%.2f herramientas con 0,5 carbón)" % made)
	check(str(smith.get("chain_status", "")).begins_with("faltan insumos"), "el negocio indica qué insumo falta")
	# Almacén lleno: se limita la producción y se avisa.
	WarehouseSim.add(gs, "piedra", WarehouseSim.free_space(gs))
	var farm := _place("trigal", 20, 20)
	_hire(farm, 4)
	BusinessSim.produce(gs)
	check(WarehouseSim.stock(gs, "trigo") <= 0.001 and str(farm.get("chain_status", "")) == "almacén lleno", "almacén lleno: no se guarda más producción")


func _test_routes_on_foot() -> void:
	_new(61)
	gs.unlocked_zones.append([3, 2])
	_set_deposits([["hierro", 70, 5, 12000]])
	var mine := _place("mina_hierro", 70, 6)
	_hire(mine, 5)
	check(not LogisticsSim.in_reach(gs, mine), "mina lejos del almacén: su producción queda en el sitio")
	TimeManager.advance_days(10)
	var at_site := float(mine["inventory"].get("hierro", 0.0))
	check(at_site > 5.0 and WarehouseSim.stock(gs, "hierro") <= 0.001, "hierro acumulado en la mina (%.1f), no en el almacén" % at_site)
	var bad := LogisticsSim.create_route(gs, {"from": int(mine["id"]), "to": LogisticsSim.PLAZA, "good": "hierro", "qty": 20, "mode": "pie"})
	check(bad.has("error") and str(bad["error"]).find("central") >= 0, "sin central de transporte no hay rutas: %s" % bad.get("error", ""))
	var central := _place("central_transporte", -20, 20)
	check(_hire(central, 3) == 3, "contratas 3 cargadores (sin estudios)")
	var wage_before := BusinessSim.period_value(central, "total", "salarios")
	var r := LogisticsSim.create_route(gs, {"from": int(mine["id"]), "to": LogisticsSim.PLAZA, "good": "hierro", "qty": 20, "mode": "pie"})
	check(r.has("route"), "ruta manual a pie creada: %s" % r.get("error", "ok"))
	check(LogisticsSim.shipments(gs).size() == 1, "el primer envío sale de inmediato")
	var s: Dictionary = LogisticsSim.shipments(gs)[0]
	print("    envío a pie: %.1f hierro, %d cargadores, %d viajes, llega en %.2f días" % [float(s["qty"]), int(s["carriers"]), int(s["trips"]), float(s["arrive"]) - float(s["depart"])])
	TimeManager.advance_days(4)
	check(WarehouseSim.stock(gs, "hierro") >= 19.9, "el hierro llegó al almacén (%.1f)" % WarehouseSim.stock(gs, "hierro"))
	check(LogisticsSim.routes(gs).is_empty(), "la ruta manual se completa y desaparece")
	check(BusinessSim.period_value(central, "total", "salarios") > wage_before, "los cargadores cobran salario")
	# Ruta automática: cada 2 días lleva 15.
	var auto := LogisticsSim.create_route(gs, {"from": int(mine["id"]), "to": LogisticsSim.PLAZA, "good": "hierro", "qty": 15, "mode": "pie", "auto": true, "every": 2})
	var wh0 := WarehouseSim.stock(gs, "hierro")
	TimeManager.advance_days(12)
	var moved := WarehouseSim.stock(gs, "hierro") - wh0
	check(auto.has("route") and moved >= 15.0 * 5.0 - 0.1, "ruta automática cada 2 días movió %.0f hierro en 12 días" % moved)
	check(int(auto["route"]["trips"]) >= 5, "la ruta automática hizo %d viajes" % int(auto["route"]["trips"]))
	# Un almacén cerca de la mina evita el transporte.
	_place("almacen", 70, 22)
	check(LogisticsSim.in_reach(gs, mine), "construir un almacén junto a la mina la deja al alcance")


func _test_roads_and_carts() -> void:
	_new(71)
	gs.unlocked_zones.append([3, 2])
	_set_deposits([["carbon", 70, 5, 12000]])
	var mine := _place("mina_carbon", 70, 6)
	mine["inventory"]["carbon"] = 150.0
	var central := _place("central_transporte", -20, 20)
	_hire(central, 3)
	var opts := {"from": int(mine["id"]), "to": LogisticsSim.PLAZA, "good": "carbon", "qty": 100, "mode": "carreta"}
	var r1 := LogisticsSim.create_route(gs, opts)
	check(r1.has("error") and str(r1["error"]).find("Requiere") >= 0, "las carretas requieren la tecnología carretas: %s" % r1.get("error", ""))
	gs.techs.append("carretas")
	r1 = LogisticsSim.create_route(gs, opts)
	check(r1.has("error"), "la central de cargadores no tiene carretas: %s" % r1.get("error", ""))
	central["level"] = 2
	r1 = LogisticsSim.create_route(gs, opts)
	check(r1.has("error") and str(r1["error"]).find("carretera") >= 0, "sin carretera no hay ruta con carretas: %s" % r1.get("error", ""))
	var money0: float = gs.money
	check(RoadSim.build(gs, Vector2(4, 0), Vector2(40, 2), "barro") == "", "tramo de barro 1 construido")
	check(RoadSim.build(gs, Vector2(40.5, 2.5), Vector2(64, 6), "barro") == "", "tramo de barro 2 construido (se une al 1)")
	check(gs.money < money0, "las carreteras cuestan dinero (%s)" % Fmt.money(money0 - gs.money))
	check(RoadSim.build(gs, Vector2(64, 6), Vector2(90, 30), "empedrado").find("Requiere") >= 0, "el empedrado requiere investigación")
	check(RoadSim.build(gs, Vector2(-80, 0), Vector2(-50, 0), "barro").find("gobierno") >= 0, "no se construye carretera en terreno del gobierno")
	check(RoadSim.connected(gs, Vector2.ZERO, Vector2(70, 6)), "la plaza y la mina quedan conectadas por la red")
	check(not RoadSim.connected(gs, Vector2.ZERO, Vector2(-30, -30)), "un punto lejos de la red no está conectado")
	r1 = LogisticsSim.create_route(gs, opts)
	check(r1.has("route"), "con carretera la ruta en carreta funciona")
	var s: Dictionary = LogisticsSim.shipments(gs)[0]
	check(float(s["qty"]) >= 99.9, "una carreta lleva mucha más carga que un cargador (%.0f)" % float(s["qty"]))
	var fee0 := BusinessSim.period_value(central, "total", "mantenimiento")
	TimeManager.advance_days(3)
	check(WarehouseSim.stock(gs, "carbon") >= 99.9, "el carbón llegó en carreta")
	check(BusinessSim.period_value(central, "total", "mantenimiento") > fee0, "los caballos tienen mantenimiento diario")
	gs.techs.append("caminos_empedrados")
	var up := RoadSim.upgrade_all(gs)
	check(up == "" and RoadSim.total_length(gs, "barro") <= 0.0, "empedrar todos los caminos: %s" % (up if up != "" else "ok"))
	check(RoadSim.speed_mult(gs, Vector2.ZERO, Vector2(70, 6)) > 1.2, "el empedrado es más rápido")


func _test_shop_sales() -> void:
	_new(81)
	var shop := _place("tienda", -16, -16)
	_hire(shop, 2)
	WarehouseSim.add(gs, "ropa", 60.0)
	for c in gs.citizens.values():
		if not gs.is_player(c.id):
			c.money += 300.0
	MarketSim.begin_day(gs)
	MarketSim.discretionary(gs)
	var sold := 60.0 - WarehouseSim.stock(gs, "ropa")
	check(sold > 0.5, "la tienda vende ropa del almacén a los ciudadanos (%.1f unidades)" % sold)
	check(BusinessSim.period_value(shop, "total", "ventas") > 0.0, "el dinero de la venta entra a la tienda (%s)" % Fmt.money(BusinessSim.period_value(shop, "total", "ventas")))


func _test_save_load() -> void:
	_new(91)
	gs.unlocked_zones.append([3, 2])
	_set_deposits([["hierro", 70, 5, 12000]])
	var mine := _place("mina_hierro", 70, 6)
	mine["inventory"]["hierro"] = 50.0
	var central := _place("central_transporte", -20, 20)
	_hire(central, 2)
	RoadSim.build(gs, Vector2(4, 0), Vector2(60, 5), "barro")
	LogisticsSim.create_route(gs, {"from": int(mine["id"]), "to": LogisticsSim.PLAZA, "good": "hierro", "qty": 10, "mode": "pie", "auto": true, "every": 3})
	WarehouseSim.add(gs, "oro", 5.0)
	var data = JSON.parse_string(JSON.stringify(gs.to_dict()))
	gs.load_dict(data)
	check(RegionSim.deposits(gs).size() == 1 and LogisticsSim.routes(gs).size() == 1 and RoadSim.roads(gs).size() == 1, "yacimientos, rutas y carreteras se guardan")
	check(is_equal_approx(WarehouseSim.stock(gs, "oro"), 5.0), "el almacén se guarda")
	TimeManager.advance_days(8)
	check(WarehouseSim.stock(gs, "hierro") > 9.0, "tras cargar, la ruta automática sigue funcionando (%.1f hierro)" % WarehouseSim.stock(gs, "hierro"))


## Menú (elegir lugar), panel de Logística, marcadores 3D, modo carretera y agentes de transporte.
func _test_ui() -> void:
	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	menu._show_new()
	menu.map_opt.select(2)
	menu._refresh_regions()
	check(menu.region_opt.item_count >= 3, "el menú ofrece %d lugares para fundar" % menu.region_opt.item_count)
	menu.region_opt.select(1)
	menu._update_desc()
	check(menu.desc_lbl.text.find("Recursos:") >= 0 and not menu.region_preview._deposits.is_empty() or menu.region_list[1].get("deposits", {}).is_empty(), "descripción y mini-mapa del lugar elegido")
	var chosen := str(menu.region_list[1]["id"])
	var seed_value := int(menu.seed_edit.value)
	menu.queue_free()
	await get_tree().process_frame
	gs.new_game({"seed": seed_value, "map_type": "montana", "region": chosen, "difficulty": "facil"})
	check(str(gs.settings["region"]) == chosen, "la partida empieza en el lugar elegido")
	gs.money = 50000.0
	gs.unlocked_zones.append([3, 2])
	_set_deposits([["hierro", 70, 5, 12000], ["oro", 25, 25, 900]])
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	var vis: LogisticsVisuals = LogisticsVisuals.instance
	check(vis != null and vis._deposit_nodes.size() == 2, "marcadores 3D de los yacimientos")
	var mine := _place("mina_hierro", 70, 6)
	_hire(mine, 4)
	mine["inventory"]["hierro"] = 80.0
	var central := _place("central_transporte", -20, 20)
	_hire(central, 3)
	RoadSim.build(gs, Vector2(4, 0), Vector2(62, 5), "barro")
	vis.rebuild_roads()
	check(vis._roads_root.get_child_count() == 1, "carretera dibujada sobre el terreno")
	var hud: Hud = world.hud
	hud._show_dock("logistics")
	var panel: LogisticsPanel = hud.logistics_panel
	for i in range(panel.tabs.get_tab_count()):
		panel.tabs.current_tab = i
		await get_tree().process_frame
	panel._f_from = int(mine["id"])
	panel._f_to = LogisticsSim.PLAZA
	panel._f_good = "hierro"
	panel._f_qty = 40
	panel._create_route()
	check(LogisticsSim.shipments(gs).size() == 1, "crear ruta desde el panel despacha un envío")
	panel.refresh()
	await get_tree().process_frame
	vis._sync_agents()
	vis._process(0.1)
	check(vis._agents.size() == 1, "agentes de transporte visibles en la ruta")
	vis.start_road_mode("barro")
	vis._update_road_ghost()
	vis._hover = Vector2(62, 5)
	vis._confirm_road_point()
	vis._hover = Vector2(62, 30)
	vis._update_road_ghost()
	vis.cancel_road_mode()
	check(not vis.road_mode, "modo carretera se activa y se cancela")
	TimeManager.advance_days(3)
	await get_tree().process_frame
	check(WarehouseSim.stock(gs, "hierro") >= 39.9, "el envío del panel llegó al almacén")
	world.queue_free()
	await get_tree().process_frame
	ui_done = true
