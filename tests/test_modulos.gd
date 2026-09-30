extends Node
## Pruebas de los módulos por edificio (docs/MODULOS.md): almacén integrado (siempre desde el nivel 1),
## prioridad frente al almacén separado, parqueadero y flota (fleet_limit / fleet_types), requisitos de
## tecnología y nivel, niveles independientes del nivel de fábrica, obra sin dejar de producir,
## mantenimiento mensual, dinero conservado, reserva de espacio al colocar, modelo 3D, interfaz y
## guardado/carga (incluida una partida vieja sin módulos).
## godot --headless res://tests/test_modulos.tscn

var failures := 0
var gs = GameState


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func _ready() -> void:
	print("== Módulos por edificio ==")
	_test_integrated_warehouse()
	_test_priority()
	_test_upgrade_while_producing()
	_test_fleet()
	_test_requirements()
	_test_independent_levels()
	_test_upkeep_and_money()
	_test_transit_unchanged()
	_test_reserve_space()
	_test_visual_parts()
	_test_save_load()
	await _test_ui()
	print("== %s (%d fallos) ==" % ["TODO OK" if failures == 0 else "CON FALLOS", failures])
	get_tree().quit(1 if failures > 0 else 0)


# --- Utilidades -----------------------------------------------------------------------------------

func _new(seed_value := 611) -> void:
	gs.new_game({"seed": seed_value, "difficulty": "facil", "map_type": "interior"})
	gs.suppress_notifications = true
	gs.money = 500000.0


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


func _total() -> float:
	return float(FreeMarketSim.money_snapshot(gs)["total"])


## Termina la obra del módulo en curso sin avanzar el resto del mundo.
func _finish_work(b: Dictionary) -> void:
	var guard := 0
	while not ModulesSim.work(b).is_empty() and guard < 200:
		ModulesSim.daily(gs)
		guard += 1


func _grant(techs: Array) -> void:
	for t in techs:
		if not gs.techs.has(t):
			gs.techs.append(t)


# --- Pruebas ------------------------------------------------------------------------------------

func _test_integrated_warehouse() -> void:
	print("-- Almacén integrado --")
	_new()
	var smith := _place("herreria", -40, 30, 2)
	var id := int(smith["id"])
	check(ModulesSim.level(smith, "almacen") == 1 and is_equal_approx(ModulesSim.warehouse_capacity(smith), 100.0), "todo negocio productor trae el almacén integrado nivel 1 (100 espacios)")
	check(WarehouseSim.is_warehouse_building(gs, smith) and WarehouseSim.ids(gs).has(id), "el almacén integrado es un almacén más de WarehouseSim")
	check(WarehouseSim.warehouse_for(gs, smith) == -1 and WarehouseSim.chain_ids(gs, smith) == [id], "sin almacén separado al lado usa solo su integrado")
	check(LogisticsSim.output_target(gs, smith) == "warehouse" and LogisticsSim.in_reach(gs, smith), "queda «en verde»: guarda en un almacén")
	check(LogisticsSim.endpoints(gs).has(id) and LogisticsSim.is_warehouse_endpoint(gs, id), "rutas y distribución lo ven como almacén")
	var tienda := _place("tienda", -60, -40)
	check(ModulesSim.warehouse_capacity(tienda) > 0.0, "los comercios también lo tienen")
	var casa := _place("vivienda", 60, 60)
	var banco := _place("banco", 60, -60)
	check(not ModulesSim.applies_any(gs, casa) and not ModulesSim.applies_any(gs, banco), "viviendas y servicios no tienen módulos")
	_hire(smith, 4)
	WarehouseSim.add_to(gs, id, "hierro", 20.0)
	WarehouseSim.add_to(gs, id, "carbon", 20.0)
	BusinessSim.produce(gs)
	var made := WarehouseSim.stock_in(gs, id, "herramientas")
	check(made > 0.5 and float(smith["inventory"].get("herramientas", 0.0)) <= 0.001, "toma insumos y guarda la producción en su almacén integrado (%.1f)" % made)
	check(WarehouseSim.stock_in(gs, id, "hierro") < 20.0, "los insumos salen del almacén integrado")


func _test_priority() -> void:
	print("-- Prioridad integrado → separado --")
	_new()
	var a := _place("almacen", 30, 25)
	var smith := _place("herreria", 30, 15, 2)
	var id := int(smith["id"])
	var wid := int(a["id"])
	check(WarehouseSim.chain_ids(gs, smith) == [id, wid], "orden: primero el integrado, luego el almacén de al lado")
	_hire(smith, 6)
	WarehouseSim.add_to(gs, wid, "hierro", 30.0)
	WarehouseSim.add_to(gs, wid, "carbon", 30.0)
	WarehouseSim.add_to(gs, id, "hierro", 2.0)
	BusinessSim.produce(gs)
	check(WarehouseSim.stock_in(gs, id, "hierro") <= 0.001 and WarehouseSim.stock_in(gs, wid, "hierro") < 30.0, "consume primero el hierro del integrado y luego el del separado")
	check(WarehouseSim.stock_in(gs, id, "herramientas") > 0.1 and WarehouseSim.stock_in(gs, wid, "herramientas") <= 0.001, "guarda primero en el integrado")
	WarehouseSim.add_to(gs, id, "piedra", WarehouseSim.free_in(gs, id))
	BusinessSim.produce(gs)
	check(WarehouseSim.stock_in(gs, wid, "herramientas") > 0.1, "con el integrado lleno, lo producido pasa al almacén separado")
	var other := _place("tejeduria", 40, 15, 2)
	check(WarehouseSim.warehouse_for(gs, other) == wid, "el integrado de la herrería no se presta a sus vecinos (el vecino usa el almacén separado)")


func _test_upgrade_while_producing() -> void:
	print("-- Obra del módulo sin dejar de producir --")
	_new()
	_grant(["ladrillo", "bodegas_anexas"])
	var smith := _place("herreria", -40, 30, 2)
	var id := int(smith["id"])
	_hire(smith, 4)
	WarehouseSim.add_to(gs, id, "hierro", 40.0)
	WarehouseSim.add_to(gs, id, "carbon", 40.0)
	check(ModulesSim.start(gs, smith, "almacen") == "", "se inicia la ampliación del almacén a nivel 2")
	check(str(smith["status"]) == "activo" and not ModulesSim.work(smith).is_empty(), "el edificio sigue activo durante la obra del módulo")
	BusinessSim.produce(gs)
	check(float(smith.get("produced_today", 0.0)) > 0.1, "sigue produciendo y facturando durante la obra (decisión documentada)")
	check(ModulesSim.start(gs, smith, "parqueadero").find("obra de módulo en curso") >= 0, "una sola obra de módulo a la vez")
	var days := ModulesSim.days_left(gs, smith)
	check(days == int(ModulesSim.mlevel("almacen", 2)["days"]), "el tiempo depende del nivel del módulo (%d días)" % days)
	_finish_work(smith)
	check(ModulesSim.level(smith, "almacen") == 2 and is_equal_approx(WarehouseSim.capacity_of(gs, id), 300.0), "al terminar: nivel 2 con 300 espacios")
	check(GameState.footprint_of(smith) > GameData.footprint("herreria", 2), "la huella crece un poco con el anexo")


func _test_fleet() -> void:
	print("-- Parqueadero y flota --")
	_new()
	var smith := _place("herreria", -40, 30, 3)
	check(ModulesSim.fleet_limit(gs, smith, "pie") == 0 and ModulesSim.fleet_types(gs, smith).is_empty(), "sin el módulo no puede tener vehículos asignados")
	check(ModulesSim.start(gs, smith, "parqueadero") == "", "nivel 1 (a pie) sin investigación")
	_finish_work(smith)
	check(ModulesSim.fleet_types(gs, smith) == ["pie"] and ModulesSim.fleet_limit(gs, smith, "pie") == 4, "nivel 1 = cargadores a pie (4)")
	check(ModulesSim.fleet_limit(gs, smith, "camion") == 0, "aún no admite camiones")
	ModulesSim.start(gs, smith, "parqueadero")
	_finish_work(smith)
	check(ModulesSim.fleet_types(gs, smith) == ["pie", "mula"] and ModulesSim.fleet_limit(gs, smith, "mula") == 3, "nivel 2 = mulas (3)")
	check(ModulesSim.block_reason(gs, smith, "parqueadero").find("Carretas") >= 0, "nivel 3 exige investigar Carretas de tiro")
	_grant(["carretas", "maquina_vapor"])
	ModulesSim.start(gs, smith, "parqueadero")
	_finish_work(smith)
	ModulesSim.start(gs, smith, "parqueadero")
	_finish_work(smith)
	check(ModulesSim.fleet_limit(gs, smith, "carreta") == 4 and ModulesSim.fleet_limit(gs, smith, "carro_vapor") == 2, "nivel 4 = carretas y carros de vapor")
	check(ModulesSim.block_reason(gs, smith, "parqueadero").find("Bahías de carga") >= 0, "los camiones exigen Bahías de carga")
	_grant(["automovil", "bahias_de_carga"])
	ModulesSim.start(gs, smith, "parqueadero")
	_finish_work(smith)
	var types := ModulesSim.fleet_types(gs, smith)
	check(types.has("camion") and ModulesSim.fleet_limit(gs, smith, "camion") == 3 and not types.has("trailer"), "nivel 5 = camiones (3) con bahía de carga: %s" % str(types))
	check(ModulesSim.fleet_limit(gs, smith, "avion") == 0, "tipos no incluidos → 0")
	var dep := _place("deposito_camiones", 60, 60)
	check(not ModulesSim.applies(gs, dep, "parqueadero"), "las estaciones de transporte no tienen este módulo (tienen su garaje)")


func _test_requirements() -> void:
	print("-- Requisitos de tecnología y nivel --")
	_new()
	var smith := _place("herreria", -40, 30, 1)
	check(ModulesSim.block_reason(gs, smith, "almacen").find("Bodegas anexas") >= 0, "el almacén nivel 2 exige investigar Bodegas anexas")
	_grant(["ladrillo", "bodegas_anexas", "fabricas", "almacenes_industriales"])
	check(ModulesSim.start(gs, smith, "almacen") == "", "con la tecnología, nivel 2 desde el edificio nivel 1")
	_finish_work(smith)
	var r := ModulesSim.block_reason(gs, smith, "almacen")
	check(r.find("nivel 2") >= 0, "el almacén nivel 3 exige el edificio en nivel 2: %s" % r)
	smith["level"] = 2
	check(ModulesSim.block_reason(gs, smith, "almacen") == "", "con el edificio en nivel 2 ya se puede")
	check(ModulesSim.min_building_level({"type": "caballeriza"}, "almacen", 5) <= GameData.max_level("caballeriza"), "el nivel mínimo se acota al máximo del tipo")
	gs.money = 10.0
	check(ModulesSim.block_reason(gs, smith, "almacen").begins_with("Dinero insuficiente"), "sin dinero no se puede")


func _test_independent_levels() -> void:
	print("-- Niveles independientes --")
	_new()
	_grant(["ladrillo", "bodegas_anexas", "carbon", "energia_hidraulica", "revolucion_industrial", "metodo_cientifico", "escuela_parroquial"])
	var smith := _place("herreria", -40, 30, 1)
	ModulesSim.start(gs, smith, "almacen")
	_finish_work(smith)
	check(int(smith["level"]) == 1 and ModulesSim.level(smith, "almacen") == 2, "mejorar el almacén no cambia el nivel del edificio")
	var err := ConstructionSim.start_upgrade(gs, smith)
	check(err == "" and str(smith["status"]) == "mejorando", "la mejora de fábrica sigue su camino: %s" % (err if err != "" else "ok"))
	smith["work_done"] = float(smith["work_needed"])
	ConstructionSim._complete(gs, smith, [])
	check(int(smith["level"]) == 2 and ModulesSim.level(smith, "almacen") == 2 and ModulesSim.level(smith, "parqueadero") == 0, "subir el nivel del edificio no toca los módulos")


func _test_upkeep_and_money() -> void:
	print("-- Mantenimiento y dinero conservado --")
	_new()
	_grant(["ladrillo", "bodegas_anexas"])
	var smith := _place("herreria", -40, 30, 2)
	var t0 := _total()
	var m0: float = gs.money
	check(ModulesSim.start(gs, smith, "almacen") == "", "obra de módulo pagada")
	check(gs.money < m0, "cuesta dinero (%s)" % Fmt.money(m0 - gs.money))
	check(absf(_total() - t0) < 0.01, "el pago de la obra queda en el pueblo (Δ %.4f)" % (_total() - t0))
	_finish_work(smith)
	var up := ModulesSim.monthly_upkeep(gs, smith)
	check(is_equal_approx(up, float(ModulesSim.mlevel("almacen", 2)["upkeep"]) * gs.price_mult()), "mantenimiento mensual del nivel 2 (%s)" % Fmt.money(up))
	var led0 := BusinessSim.period_value(smith, "month", "mantenimiento")
	var t1 := _total()
	ModulesSim.monthly(gs)
	check(absf(BusinessSim.period_value(smith, "month", "mantenimiento") - led0 - up) < 0.001, "se cobra al cerrar el mes en el rubro mantenimiento")
	check(absf(_total() - t1) < 0.01, "el mantenimiento conserva el dinero (Δ %.4f)" % (_total() - t1))
	var bare := _place("tejeduria", 60, -30)
	check(ModulesSim.monthly_upkeep(gs, bare) <= 0.0, "el almacén base (nivel 1) no tiene mantenimiento")


func _test_transit_unchanged() -> void:
	print("-- El parqueadero es de vehículos, no de empleados --")
	_new()
	var smith := _place("herreria", -40, 30, 2)
	ModulesSim.start(gs, smith, "parqueadero")
	_finish_work(smith)
	check(TransitSim.parking_capacity(gs, smith) == 0 and not TransitSim.parkings(gs).has(smith), "no cuenta como parqueadero de empleados (la penalización moderna sigue igual)")


func _test_reserve_space() -> void:
	print("-- Espacio para crecer --")
	_new()
	var smith := _place("herreria", -40, 30)
	var grow := ModulesSim.reserve_footprint("herreria")
	check(grow > GameData.footprint("herreria", 1) + 1.0, "la huella de reserva supera la inicial (%.1f m)" % grow)
	var x := -40.0 + (GameData.footprint("herreria", 1) + GameData.footprint("molino", 1)) * 0.5 + 1.5
	check(ConstructionSim.placement_block_reason(gs, "molino", x, 30.0) == "", "sin reserva cabría al lado")
	check(ConstructionSim.placement_block_reason(gs, "molino", x, 30.0, -1, 1, true).find("crezcan") >= 0, "al colocar se reserva espacio para crecer")
	var far := -40.0 + (grow + ModulesSim.reserve_footprint("molino")) * 0.5 + 1.0
	check(ConstructionSim.placement_block_reason(gs, "molino", far, 30.0, -1, 1, true) == "", "más lejos sí se puede")
	check(ModulesSim.reserve_footprint("almacen") == GameData.footprint("almacen", 1), "un almacén separado no reserva crecimiento de módulos")
	smith["modules"] = {"almacen": 5, "parqueadero": 6}
	check(GameState.footprint_of(smith) <= grow + 0.01, "la huella al máximo cabe en la reserva")


func _test_visual_parts() -> void:
	print("-- Modelo 3D --")
	var parts: Array = GameData.level_def("herreria", 2).get("model", [])
	check(MeshLib.module_parts(parts, {"almacen": 1, "parqueadero": 0}).is_empty(), "almacén base: sin piezas extra")
	var p := MeshLib.module_parts(parts, {"almacen": 3, "parqueadero": 5})
	check(p.size() > 20, "anexo de bodega, patio con la flota y andén de carga (%d piezas)" % p.size())
	var node := MeshLib.build_model(parts + p, 1.0)
	check(node.get_child_count() >= 1, "el modelo con módulos se construye en una malla")
	node.free()


func _test_save_load() -> void:
	print("-- Guardado y carga --")
	_new()
	_grant(["ladrillo", "bodegas_anexas"])
	var smith := _place("herreria", -40, 30, 2)
	var id := int(smith["id"])
	ModulesSim.start(gs, smith, "parqueadero")
	_finish_work(smith)
	ModulesSim.start(gs, smith, "almacen")
	ModulesSim.daily(gs)
	WarehouseSim.add_to(gs, id, "hierro", 50.0)
	var d: Dictionary = JSON.parse_string(JSON.stringify(gs.to_dict()))
	gs.load_dict(d)
	var b2: Dictionary = gs.get_building(id)
	check(ModulesSim.level(b2, "parqueadero") == 1 and ModulesSim.fleet_limit(gs, b2, "pie") == 4, "los niveles de módulo se guardan")
	check(str(ModulesSim.work(b2).get("module", "")) == "almacen" and ModulesSim.days_left(gs, b2) > 0, "la obra del módulo en curso se guarda")
	check(is_equal_approx(WarehouseSim.stock_in(gs, id, "hierro"), 50.0), "el stock del almacén integrado se guarda")
	_finish_work(b2)
	check(ModulesSim.level(b2, "almacen") == 2, "tras cargar la obra termina")
	# Partida vieja: sin "modules" → almacén base (nivel 1) y sin flota; todo lo demás igual.
	var old: Dictionary = JSON.parse_string(JSON.stringify(gs.to_dict()))
	for bd in old.get("buildings", []):
		bd.erase("modules")
		bd.erase("module_work")
	gs.load_dict(old)
	var b3: Dictionary = gs.get_building(id)
	check(ModulesSim.level(b3, "almacen") == 1 and ModulesSim.level(b3, "parqueadero") == 0 and ModulesSim.footprint_extra(b3) == 0.0, "partida vieja: almacén integrado base y flota en 0")


func _test_ui() -> void:
	print("-- Interfaz --")
	_new(612)
	_grant(["ladrillo", "bodegas_anexas"])
	var smith := _place("herreria", -40, 30, 2)
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	var hud: Hud = world.hud
	hud.open_building(int(smith["id"]))
	await get_tree().process_frame
	var bp = hud.building_panel
	var idx := -1
	for i in range(bp.tabs.get_tab_count()):
		if bp.tabs.get_tab_title(i) == "Mejorar":
			idx = i
	check(idx >= 0, "pestaña Mejorar")
	var tab: Node = bp.tabs.get_child(idx)
	check(tab.find_child("Modulo_almacen", true, false) != null and tab.find_child("Modulo_parqueadero", true, false) != null, "secciones Almacén y Parqueadero y flota")
	var btn: Button = tab.find_child("Mejorar_almacen", true, false)
	check(btn != null and not btn.disabled, "botón Mejorar del almacén habilitado")
	if btn:
		btn.pressed.emit()
		await get_tree().process_frame
	check(not ModulesSim.work(smith).is_empty(), "el botón inicia la obra del módulo")
	world.queue_free()
	await get_tree().process_frame
