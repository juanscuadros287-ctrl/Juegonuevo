extends Node
## Pruebas de almacenes individuales, vínculo fábrica ↔ almacén por adyacencia, flota de
## vehículos (caballeriza, depósito de camiones, hangar), rutas por vehículo y compra
## automática de insumos. godot --headless res://tests/test_almacenes.tscn

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
	print("== Dinastía: pruebas de almacenes y flota ==")
	_test_migration()
	_test_individual_stock()
	_test_adjacency()
	_test_production_rules()
	_test_move_and_demolish()
	_test_routes_between_warehouses()
	_test_stable_and_mules()
	_test_trucks_roads_fuel()
	_test_auto_buy()
	_test_planned_air()
	_test_save_load()
	await _test_ui()
	check(ui_done, "la prueba de interfaz terminó sin errores de script")
	print("== %s (%d fallos) ==" % ["TODO OK" if failures == 0 else "CON FALLOS", failures])
	get_tree().quit(1 if failures > 0 else 0)


# --- Utilidades -----------------------------------------------------------------------------

func _place(type_id: String, x: float, z: float, level := 1) -> Dictionary:
	var b: Dictionary = ConstructionSim.make_building(gs, type_id, level, x, z, 0.0, "jugador")
	gs.add_building(b)
	WarehouseSim.relink_all(gs)
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


func _new(seed_value := 101) -> void:
	gs.new_game({"seed": seed_value, "difficulty": "facil", "map_type": "interior"})
	gs.suppress_notifications = true
	gs.money = 500000.0


# --- Pruebas ------------------------------------------------------------------------------------

func _test_migration() -> void:
	_new()
	var alm := _place("almacen", 30, 25)
	gs.logistics.erase("warehouses")
	gs.logistics["warehouse"] = {"madera": 150.0, "hierro": 100.0}
	LogisticsSim.init_state(gs)
	check(not gs.logistics.has("warehouse") and gs.logistics.has("warehouses"), "partida antigua: el almacén global se migra a almacenes individuales")
	check(is_equal_approx(WarehouseSim.stock(gs, "madera"), 150.0) and is_equal_approx(WarehouseSim.stock(gs, "hierro"), 100.0), "el stock total se conserva tras migrar")
	check(is_equal_approx(WarehouseSim.used_in(gs, WarehouseSim.PLAZA), 200.0) and WarehouseSim.used_in(gs, int(alm["id"])) > 49.0,
			"se llena primero la bodega principal (plaza %d) y el resto va al otro almacén (%d)" % [int(WarehouseSim.used_in(gs, 0)), int(WarehouseSim.used_in(gs, int(alm["id"])))])


func _test_individual_stock() -> void:
	_new()
	var a := _place("almacen", 30, 25)
	var wid := int(a["id"])
	check(is_equal_approx(WarehouseSim.capacity_of(gs, WarehouseSim.PLAZA), 200.0) and is_equal_approx(WarehouseSim.capacity_of(gs, wid), 500.0), "cada almacén tiene su capacidad (plaza 200, bodega 500)")
	check(is_equal_approx(WarehouseSim.capacity(gs), 700.0), "la capacidad total es la suma (700)")
	var acc := WarehouseSim.add_to(gs, wid, "piedra", 800.0)
	check(is_equal_approx(acc, 500.0) and is_equal_approx(WarehouseSim.free_in(gs, wid), 0.0), "un almacén no acepta más que su capacidad (aceptó %d)" % int(acc))
	check(is_equal_approx(WarehouseSim.stock_in(gs, WarehouseSim.PLAZA, "piedra"), 0.0), "el stock de un almacén no aparece en otro")
	var acc2 := WarehouseSim.add(gs, "madera", 250.0)
	check(is_equal_approx(acc2, 200.0) and is_equal_approx(WarehouseSim.stock_in(gs, WarehouseSim.PLAZA, "madera"), 200.0), "add() agregado reparte donde hay espacio (plaza primero): %d" % int(acc2))
	var taken := WarehouseSim.remove(gs, "piedra", 120.0)
	check(is_equal_approx(taken, 120.0) and is_equal_approx(WarehouseSim.stock_in(gs, wid, "piedra"), 380.0), "remove() agregado toma de donde haya")
	check(is_equal_approx(WarehouseSim.remove_from(gs, WarehouseSim.PLAZA, "piedra", 10.0), 0.0), "remove_from() solo toma de ese almacén")


func _test_adjacency() -> void:
	_new()
	var a := _place("almacen", 30, 25)
	var smith := _place("herreria", 30, 15)
	var far := _place("tejeduria", -30, 30)
	check(WarehouseSim.warehouse_for(gs, smith) == int(a["id"]) and int(smith.get("warehouse_id", -9)) == int(a["id"]), "la herrería al lado del almacén queda vinculada (warehouse_id guardado)")
	check(WarehouseSim.warehouse_for(gs, far) == -1 and LogisticsSim.output_target(gs, far) == "local", "una fábrica lejos de todo almacén no queda vinculada")
	check(WarehouseSim.linked_to(gs, int(a["id"])).size() == 1, "el almacén sabe a qué negocios abastece")
	var gap := WarehouseSim.edge_gap(Vector2(30, 15), 2.5, Vector2(30, 25), 3.0)
	check(gap > 4.0 and gap < 5.0, "distancia entre bordes calculada (%.1f m)" % gap)
	var n := WarehouseSim.nearest_for(gs, "herreria", 30, 35 + 3.0 + 2.5 + WarehouseSim.link_distance() + 1.0)
	check(n.is_empty(), "a más de %d m entre bordes no hay vínculo" % int(WarehouseSim.link_distance()))
	check(WarehouseSim.warehouse_for(gs, a) == -1, "un almacén no se vincula a otro almacén")
	var near_plaza := _place("molino", 16, -14)
	check(WarehouseSim.warehouse_for(gs, near_plaza) == WarehouseSim.PLAZA, "un taller junto a la plaza usa la bodega de la plaza")


func _test_production_rules() -> void:
	_new()
	var a := _place("almacen", 30, 25)
	var wid := int(a["id"])
	var smith := _place("herreria", 30, 15)
	_hire(smith, 4)
	# Insumos en la plaza: la herrería NO los ve (solo su almacén vinculado).
	WarehouseSim.add_to(gs, WarehouseSim.PLAZA, "hierro", 50.0)
	WarehouseSim.add_to(gs, WarehouseSim.PLAZA, "carbon", 50.0)
	BusinessSim.produce(gs)
	check(WarehouseSim.stock(gs, "herramientas") <= 0.001 and str(smith.get("chain_status", "")).begins_with("faltan insumos"),
			"los insumos en otro almacén no sirven: '%s'" % str(smith.get("chain_status", "")))
	WarehouseSim.add_to(gs, wid, "hierro", 20.0)
	WarehouseSim.add_to(gs, wid, "carbon", 20.0)
	BusinessSim.produce(gs)
	var made := WarehouseSim.stock_in(gs, wid, "herramientas")
	check(made > 0.5 and WarehouseSim.stock_in(gs, WarehouseSim.PLAZA, "herramientas") <= 0.001, "produce con insumos de SU almacén y guarda ahí (%.1f herramientas)" % made)
	check(WarehouseSim.stock_in(gs, WarehouseSim.PLAZA, "hierro") >= 49.99, "no tocó los insumos de la plaza")
	# Almacén lleno: se detiene con aviso claro.
	WarehouseSim.remove_from(gs, wid, "hierro", 100.0)   # Sin insumos la herrería no libera espacio.
	WarehouseSim.remove_from(gs, wid, "carbon", 100.0)
	WarehouseSim.add_to(gs, wid, "piedra", WarehouseSim.free_in(gs, wid))
	var farm := _place("rebano", 38, 25)   # Sin temporada: produce todo el año.
	_hire(farm, 4)
	check(WarehouseSim.warehouse_for(gs, farm) == wid, "el campo al lado del almacén queda vinculado")
	gs.suppress_notifications = false
	var n0: int = gs.notifications_log.size()
	BusinessSim.produce(gs)
	gs.suppress_notifications = true
	check(str(farm.get("chain_status", "")) == "almacén lleno" and float(farm.get("produced_today", 1.0)) <= 0.001, "almacén vinculado lleno: producción detenida")
	var warned := false
	for e in gs.notifications_log.slice(n0):
		if str(e["text"]).find("está lleno") >= 0 and str(e["text"]).find(WarehouseSim.label_of(gs, wid)) >= 0:
			warned = true
	check(warned, "aviso claro con el nombre del almacén lleno")
	# Sin almacén: la producción queda en el sitio.
	var far_farm := _place("trigal", -30, 30)
	_hire(far_farm, 2)
	BusinessSim.produce(gs)
	check(float(far_farm["inventory"].get("trigo", 0.0)) > 1.0 and LogisticsSim.pending_at_sites(gs).has(int(far_farm["id"])), "sin almacén al lado la cosecha queda en el sitio y espera transporte")


func _test_move_and_demolish() -> void:
	_new()
	var a := _place("almacen", 30, 25)
	var b2 := _place("almacen", -30, -25)
	var smith := _place("herreria", 30, 15)
	check(WarehouseSim.warehouse_for(gs, smith) == int(a["id"]), "vinculada al almacén A")
	var moved := ""
	for dx in [0.0, 3.0, -3.0, 6.0]:
		moved = ConstructionSim.move_building(gs, smith, -30.0 + dx, -15.0, 0.0)
		if moved == "":
			break
	check(moved == "" and int(smith.get("warehouse_id", -9)) == int(b2["id"]), "al mover la fábrica junto al almacén B se revincula (%s)" % (moved if moved != "" else "ok"))
	WarehouseSim.add_to(gs, int(b2["id"]), "lana", 40.0)
	ConstructionSim.demolish(gs, b2)
	check(int(smith.get("warehouse_id", -9)) == -1, "al demoler su almacén la fábrica queda sin vínculo")
	check(WarehouseSim.stock(gs, "lana") >= 39.9, "el stock del almacén demolido pasa a los otros almacenes")


func _test_routes_between_warehouses() -> void:
	_new()
	var a := _place("almacen", 30, 25)
	var c := _place("central_transporte", -20, 20)
	_hire(c, 3)
	WarehouseSim.add_to(gs, WarehouseSim.PLAZA, "hierro", 25.0)
	var r := LogisticsSim.create_route(gs, {"from": LogisticsSim.PLAZA, "to": int(a["id"]), "good": "hierro", "qty": 25, "mode": "pie"})
	check(r.has("route"), "ruta entre almacenes (plaza → almacén): %s" % r.get("error", "ok"))
	TimeManager.advance_days(3)
	check(WarehouseSim.stock_in(gs, int(a["id"]), "hierro") >= 24.9 and WarehouseSim.stock_in(gs, WarehouseSim.PLAZA, "hierro") <= 0.01, "el hierro pasó de la bodega de la plaza al almacén")


func _test_stable_and_mules() -> void:
	_new()
	var a := _place("almacen", 30, 25)
	var st := _place("caballeriza", -20, 20)
	var bad := LogisticsSim.buy_vehicle(gs, _place("central_transporte", -20, -20), "mula")
	check(bad.has("error") and str(bad["error"]).find("Caballeriza") >= 0, "las mulas solo se compran en la caballeriza: %s" % bad.get("error", ""))
	var money0: float = gs.money
	var r1 := LogisticsSim.buy_vehicle(gs, st, "mula")
	check(r1.has("vehicle") and gs.money < money0, "compras una mula (%s)" % Fmt.money(money0 - gs.money))
	var r2 := LogisticsSim.buy_vehicle(gs, st, "carreta")
	check(r2.has("error") and str(r2["error"]).find("Requiere") >= 0, "las carretas requieren la tecnología Carretas de tiro")
	var mule: Dictionary = r1["vehicle"]
	WarehouseSim.add_to(gs, int(a["id"]), "lana", 100.0)
	var e := LogisticsSim.create_route(gs, {"from": int(a["id"]), "to": LogisticsSim.PLAZA, "good": "lana", "qty": 100, "vehicle": int(mule["id"])})
	check(e.has("error") and str(e["error"]).find("arrieros") >= 0, "sin arriero la mula no sale: %s" % e.get("error", ""))
	_hire(st, 2)
	var r := LogisticsSim.create_route(gs, {"from": int(a["id"]), "to": LogisticsSim.PLAZA, "good": "lana", "qty": 100, "vehicle": int(mule["id"])})
	check(r.has("route") and str(r["route"]["mode"]) == "mula", "ruta asignada a la mula (el medio sale del vehículo)")
	var s: Dictionary = LogisticsSim.shipments(gs)[0]
	check(float(s["qty"]) <= float(LogisticsSim.mode_def("mula")["capacity"]) * 4.0 + 0.01 and (s["vehicles"] as Array).has(int(mule["id"])),
			"manual con vehículo = un viaje hasta su capacidad (%.0f lana)" % float(s["qty"]))
	var r_b := LogisticsSim.create_route(gs, {"from": int(a["id"]), "to": LogisticsSim.PLAZA, "good": "lana", "qty": 10, "vehicle": int(mule["id"]), "auto": true, "every": 1})
	check(LogisticsSim.shipments(gs).size() == 1 and str(r_b["route"]["status"]).find("ocupad") >= 0, "un vehículo de viaje no puede hacer otra ruta a la vez: %s" % str(r_b["route"]["status"]))
	var pool := LogisticsSim.create_route(gs, {"from": int(a["id"]), "to": LogisticsSim.PLAZA, "good": "lana", "qty": 10, "mode": "mula"})
	check(str(pool.get("route", {}).get("status", "")).find("Sin mulas libres") >= 0, "el número de vehículos limita los viajes simultáneos")
	var feed0 := BusinessSim.period_value(st, "total", "insumos")
	TimeManager.advance_days(2)
	check(BusinessSim.period_value(st, "total", "insumos") > feed0, "los animales consumen alimento cada día")
	check(WarehouseSim.stock_in(gs, WarehouseSim.PLAZA, "lana") > 20.0, "la mula llevó la lana a la plaza (%.0f)" % WarehouseSim.stock_in(gs, WarehouseSim.PLAZA, "lana"))
	check(int(mule.get("trips", 0)) >= 2 and float(mule.get("km", 0.0)) > 0.0, "el vehículo acumula viajes y km (%d viajes)" % int(mule.get("trips", 0)))
	var sold := LogisticsSim.sell_vehicle(gs, int(mule["id"]))
	check(sold == "" or sold.find("de viaje") >= 0, "vender una mula: %s" % (sold if sold != "" else "ok"))


func _test_trucks_roads_fuel() -> void:
	_new()
	var a := _place("almacen", 30, 25)
	var dep := _place("deposito_camiones", -25, -25, 2)
	var r0 := LogisticsSim.buy_vehicle(gs, dep, "camion")
	check(r0.has("error") and str(r0["error"]).find("Requiere") >= 0, "los camiones requieren la tecnología Automóvil")
	for t in ["carretas", "caminos_empedrados", "maquina_vapor", "automovil"]:
		gs.techs.append(t)
	var truck: Dictionary = LogisticsSim.buy_vehicle(gs, dep, "camion").get("vehicle", {})
	check(not truck.is_empty() and int(truck["base"]) == int(dep["id"]), "camión comprado en el depósito de camiones")
	_hire(dep, 2)
	WarehouseSim.add_to(gs, int(a["id"]), "piedra", 300.0)
	check(RoadSim.build(gs, Vector2(6, 4), Vector2(27, 20), "barro") == "", "camino de barro entre la plaza y el almacén")
	var opts := {"from": int(a["id"]), "to": LogisticsSim.PLAZA, "good": "piedra", "qty": 150, "vehicle": int(truck["id"]), "auto": true, "every": 3}
	var e := LogisticsSim.create_route(gs, opts)
	check(e.has("error") and str(e["error"]).find("empedrado") >= 0, "el camión no anda por barro: %s" % e.get("error", ""))
	check(RoadSim.upgrade_all(gs, "empedrado") == "", "se empiedra el camino")
	var money0: float = gs.money
	var r := LogisticsSim.create_route(gs, opts)
	check(r.has("route"), "con camino empedrado el camión sale: %s" % r.get("error", "ok"))
	var s: Dictionary = LogisticsSim.shipments(gs)[0]
	check(float(s["qty"]) > 100.0, "un camión lleva mucha carga (%.0f; capacidad %d)" % [float(s["qty"]), int(LogisticsSim.mode_def("camion")["capacity"])])
	check(float(s["fuel"]) > 0.0 and gs.money < money0, "el camión gasta combustible por km (%s)" % Fmt.money2(float(s["fuel"])))
	var fuel_no_pump := float(s["fuel"])
	check(LogisticsSim.buy_fuel_pump(gs, dep) == "" and LogisticsSim.fuel_discount(gs, dep) > 0.2, "surtidor de combustible instalado en el depósito")
	TimeManager.advance_days(3)
	var last: Dictionary = LogisticsSim.shipments(gs)[LogisticsSim.shipments(gs).size() - 1]
	check(float(last["fuel"]) < fuel_no_pump - 0.001, "con surtidor el combustible es más barato (%s < %s)" % [Fmt.money2(float(last["fuel"])), Fmt.money2(fuel_no_pump)])
	check(WarehouseSim.stock_in(gs, WarehouseSim.PLAZA, "piedra") > 100.0, "la piedra llegó en camión a la salida del pueblo")
	var tr := LogisticsSim.buy_vehicle(gs, dep, "trailer")
	check(tr.has("error"), "el tráiler exige un nivel mayor y la tecnología Industria automotriz: %s" % tr.get("error", ""))


func _test_auto_buy() -> void:
	_new()
	var a := _place("almacen", 30, 25)
	var smith := _place("herreria", 30, 15)
	var c := _place("central_transporte", -20, 20)
	_hire(c, 3)
	var money0: float = gs.money
	var r := LogisticsSim.create_route(gs, {"from": LogisticsSim.PLAZA, "to": int(a["id"]), "good": "hierro", "qty": 30, "mode": "pie",
		"auto": true, "every": 1, "buy": true, "max_stock": 45})
	check(r.has("route") and float(LogisticsSim.shipments(gs)[0].get("bought", 0.0)) > 0.0, "compra automática de insumos: el envío sale comprando en la salida del pueblo")
	check(gs.money < money0, "la compra cuesta dinero (%s)" % Fmt.money(money0 - gs.money))
	TimeManager.advance_days(5)
	var have := WarehouseSim.stock_in(gs, int(a["id"]), "hierro")
	check(have > 20.0 and have <= 45.01, "el almacén de la fábrica recibe hierro sin pasar el tope (%.0f ≤ 45)" % have)
	check(LogisticsSim.create_route(gs, {"from": int(a["id"]), "to": LogisticsSim.PLAZA, "good": "hierro", "qty": 5, "buy": true}).has("error"), "la compra solo sale de la plaza")
	check(WarehouseSim.warehouse_for(gs, smith) == int(a["id"]), "la herrería consume de ese almacén")


func _test_planned_air() -> void:
	_new()
	gs.techs.append("aviacion")
	var h := _place("hangar", -30, -25)
	var r := LogisticsSim.buy_vehicle(gs, h, "avion")
	check(r.has("vehicle"), "el hangar permite comprar aviones de carga (previsto)")
	var e := LogisticsSim.create_route(gs, {"from": LogisticsSim.PLAZA, "to": int(_place("almacen", 30, 25)["id"]), "good": "madera", "qty": 5, "vehicle": int(r.get("vehicle", {}).get("id", -1))})
	check(e.has("error") and str(e["error"]).find("fase posterior") >= 0, "el transporte aéreo queda para una fase posterior: %s" % e.get("error", ""))


func _test_save_load() -> void:
	_new()
	var a := _place("almacen", 30, 25)
	var st := _place("caballeriza", -20, 20)
	_hire(st, 2)
	var mule: Dictionary = LogisticsSim.buy_vehicle(gs, st, "mula")["vehicle"]
	WarehouseSim.add_to(gs, int(a["id"]), "lana", 80.0)
	LogisticsSim.create_route(gs, {"from": int(a["id"]), "to": LogisticsSim.PLAZA, "good": "lana", "qty": 20, "vehicle": int(mule["id"]), "auto": true, "every": 2})
	var data = JSON.parse_string(JSON.stringify(gs.to_dict()))
	gs.load_dict(data)
	check(is_equal_approx(WarehouseSim.stock_in(gs, int(a["id"]), "lana"), 60.0) and gs.logistics["warehouses"].has(str(a["id"])), "el stock de cada almacén se guarda (60 lana; 20 van en camino)")
	check(LogisticsSim.vehicles(gs).size() == 1 and int(LogisticsSim.routes(gs)[0]["vehicle"]) == int(mule["id"]), "vehículos y rutas asignadas se guardan")
	TimeManager.advance_days(6)
	check(WarehouseSim.stock_in(gs, WarehouseSim.PLAZA, "lana") >= 39.9, "tras cargar, la mula sigue su ruta automática (%.0f lana)" % WarehouseSim.stock_in(gs, WarehouseSim.PLAZA, "lana"))


## Mundo 3D: indicador verde, ghost verde/ámbar, pestañas Almacén y Vehículos.
func _test_ui() -> void:
	_new(202)
	var a := _place("almacen", 30, 25)
	var smith := _place("herreria", 30, 15)
	var far := _place("tejeduria", -30, 30)
	var st := _place("caballeriza", -22, -24)
	_hire(st, 1)
	LogisticsSim.buy_vehicle(gs, st, "mula")
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	var vis: LogisticsVisuals = LogisticsVisuals.instance
	var ring: Node3D = vis._links_root.get_node_or_null("link_%d" % int(smith["id"]))
	check(ring != null and int(ring.get_meta("warehouse")) == int(a["id"]), "la herrería vinculada muestra el indicador verde")
	check(vis._links_root.get_node_or_null("line_%d" % int(smith["id"])) != null, "flecha verde de la fábrica a su almacén")
	var ring2: Node3D = vis._links_root.get_node_or_null("link_%d" % int(far["id"]))
	check(ring2 != null and int(ring2.get_meta("warehouse")) == -1, "la fábrica sin almacén muestra indicador rojo")
	check(vis._wh_labels.has(int(a["id"])) and str((vis._wh_labels[int(a["id"])] as Label3D).text).find("abastece 1") >= 0, "el almacén muestra cuántos negocios abastece")
	var fallback := MeshLib.ghost_mat(true)
	var m1 := vis.placement_feedback("molino", Vector3(38, 0, 16), -1, true, fallback)
	check(m1 == LogisticsVisuals.link_ghost_mat() and vis.placement_text().find("Al lado") >= 0, "ghost verde brillante junto a un almacén: '%s'" % vis.placement_text().strip_edges())
	check(vis._place_root != null and vis._place_root.get_child_count() > 0, "se dibuja la flecha hacia el almacén durante la colocación")
	var m2 := vis.placement_feedback("molino", Vector3(-30, 0, -5), -1, true, fallback)
	check(m2 == LogisticsVisuals.nolink_ghost_mat() and vis.placement_text().find("Sin almacén") >= 0, "ghost ámbar si no queda al lado de un almacén")
	var m3 := vis.placement_feedback("molino", Vector3(-30, 0, -5), -1, false, fallback)
	check(m3 == fallback, "si no se puede construir, sigue en rojo")
	var m4 := vis.placement_feedback("almacen", Vector3(-30, 0, 20), -1, true, fallback)
	check(m4 == LogisticsVisuals.link_ghost_mat() and vis.placement_text().find("Abastecerá a 1") >= 0, "al colocar un almacén se ven los negocios que abastecerá")
	world.start_placement("herreria", "normal")
	world.cancel_placement()
	check(vis._place_root == null, "cancelar la colocación borra las flechas")
	var hud: Hud = world.hud
	hud.open_building(int(a["id"]))
	await get_tree().process_frame
	var names := []
	for i in range(hud.building_panel.tabs.get_tab_count()):
		names.append(hud.building_panel.tabs.get_tab_title(i))
	check(names.has("Almacén"), "pestaña Almacén en el panel del almacén (%s)" % ", ".join(names))
	check(hud.building_panel.summary.text.find("abastece") >= 0, "el resumen del almacén muestra a quién abastece")
	hud.open_building(int(smith["id"]))
	await get_tree().process_frame
	check(hud.building_panel.summary.text.find("Almacén vinculado") >= 0 and hud.building_panel.summary.text.find("5fd35f") >= 0, "la fábrica muestra 'Almacén vinculado' en verde")
	hud.open_building(int(far["id"]))
	await get_tree().process_frame
	check(hud.building_panel.summary.text.find("ninguno") >= 0, "la fábrica sin almacén muestra 'ninguno' en rojo")
	hud.open_building(int(st["id"]))
	await get_tree().process_frame
	names.clear()
	for i in range(hud.building_panel.tabs.get_tab_count()):
		names.append(hud.building_panel.tabs.get_tab_title(i))
	check(names.has("Vehículos"), "pestaña Vehículos en la caballeriza")
	hud._show_dock("logistics")
	var panel: LogisticsPanel = hud.logistics_panel
	for i in range(panel.tabs.get_tab_count()):
		panel.tabs.current_tab = i
		await get_tree().process_frame
	panel.refresh()
	await get_tree().process_frame
	check(panel._warehouse_text().find(WarehouseSim.label_of(gs, int(a["id"]))) >= 0, "el panel de Logística lista cada almacén")
	# Mover la herrería lejos: el indicador cambia a rojo.
	smith["x"] = -34.0
	smith["z"] = -2.0
	WarehouseSim.relink_all(gs)
	vis.rebuild_links()
	await get_tree().process_frame
	var ring3: Node3D = vis._links_root.get_node_or_null("link_%d" % int(smith["id"]))
	check(ring3 != null and int(ring3.get_meta("warehouse")) == -1, "al alejarla del almacén su indicador pasa a rojo")
	world.queue_free()
	await get_tree().process_frame
	ui_done = true
