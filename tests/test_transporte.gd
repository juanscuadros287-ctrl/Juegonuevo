extends Node
## Pruebas del transporte (docs/TRANSPORTE.md): carreteras por puntos con curvas y puentes, trazado
## manual de rutas a otros pueblos y vías férreas, buses con paraderos y pasajes, parqueaderos,
## penalización de acceso moderno y guardado.
## godot --headless res://tests/test_transporte.tscn

var failures := 0
var gs = GameState


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func _ready() -> void:
	print("== Dinastía: transporte ==")
	_test_polyline_cost()
	_test_blocked()
	_test_bridge()
	_test_trade_manual()
	_test_bus_locked()
	_test_passengers()
	_test_parking()
	_test_save_load()
	await _test_ui()
	print("== %s (%d fallos) ==" % ["TODO OK" if failures == 0 else "CON FALLOS", failures])
	get_tree().quit(1 if failures > 0 else 0)


# --- Utilidades ---------------------------------------------------------------------------------

func _new(seed_value := 901, opts := {}) -> void:
	var o := {"seed": seed_value, "difficulty": "facil", "map_type": "interior"}
	o.merge(opts, true)
	gs.new_game(o)
	gs.suppress_notifications = true
	gs.money = 500000.0


func _techs(list: Array) -> void:
	gs.research["era"] = 3
	for t in list:
		if not gs.techs.has(t):
			gs.techs.append(t)


func _unlock_all() -> void:
	gs.unlocked_zones = []
	for x in range(gs.ZONE_GRID):
		for y in range(gs.ZONE_GRID):
			gs.unlocked_zones.append([x, y])


func _place(type_id: String, x: float, z: float, level := 1) -> Dictionary:
	var b: Dictionary = ConstructionSim.make_building(gs, type_id, level, x, z, 0.0, "jugador")
	gs.add_building(b)
	WarehouseSim.relink_all(gs)
	return b


func _pv(arr: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for a in arr:
		out.append(Vector2(float(a[0]), float(a[1])))
	return out


func _hire(b: Dictionary, n: int) -> Array:
	var out := []
	for c in BusinessSim.candidates(gs, b):
		if out.size() >= n:
			break
		if c.job_kind == "obra":
			continue
		c.education = maxi(c.education, int(gs.level_def(b).get("min_education", 0)))
		if BusinessSim.hire(gs, b, c, BusinessSim.asked_wage(gs, c, str(b["type"])) * 1.2) == "":
			out.append(c)
	return out


func _town_money() -> float:
	var total: float = gs.money
	for c in gs.citizens.values():
		if not gs.is_player(c.id):
			total += c.money
	return total


# --- Pruebas ------------------------------------------------------------------------------------

func _test_polyline_cost() -> void:
	print("-- Carretera por puntos: curva y costo")
	_new()
	_techs(["caminos_empedrados"])
	var ctrl := _pv([[-30, -20], [-10, -30], [12, -22], [30, -4]])
	var plan := TransitSim.road_plan(gs, ctrl, "barro")
	check(str(plan["reason"]) == "", "la carretera curva se puede construir (%s)" % str(plan["reason"]))
	var pts: PackedVector2Array = plan["points"]
	check(pts[0].distance_to(ctrl[0]) < 0.01 and pts[pts.size() - 1].distance_to(ctrl[ctrl.size() - 1]) < 0.01, "la curva empieza y termina en los clics")
	var through := true
	for p in ctrl:
		if TransitSim.dist_to_poly(p, pts) > 0.6:
			through = false
	check(through, "la curva pasa por cada punto intermedio")
	var chord := TransitSim.poly_length(ctrl)
	var length := float(plan["length"])
	check(length >= chord * 0.98 and length <= chord * 1.3, "largo coherente: %.1f m (puntos: %.1f m)" % [length, chord])
	var expect := float(RoadSim._cost_for_length(gs, length, "barro")["total"])
	check(absf(float(plan["cost"]["total"]) - expect) < 0.01, "costo = metros × costo por metro (%s)" % Fmt.money(expect))
	var seg_ok := true
	for i in range(pts.size() - 1):
		var l := pts[i].distance_to(pts[i + 1])
		if l < 2.0 or l > 6.5:
			seg_ok = false
	check(seg_ok and pts.size() >= 8, "muestreada en %d tramos de 2–6 m" % (pts.size() - 1))
	var m0: float = gs.money
	check(TransitSim.build_road(gs, ctrl, "barro") == "", "se construye")
	check(absf((m0 - gs.money) - expect) < 0.01, "se cobra lo presupuestado")
	check(RoadSim.roads(gs).size() == pts.size() - 1 and TransitSim.polys(gs).size() == 1, "los tramos quedan en RoadSim con su trazado")
	check(RoadSim.connected(gs, ctrl[0], ctrl[ctrl.size() - 1]), "la red une el inicio y el final")
	# Otra carretera que empieza cerca del extremo se pega a la red.
	check(TransitSim.build_road(gs, _pv([[31, -2], [34, 20]]), "empedrado") == "", "segunda carretera (empedrada)")
	check(RoadSim.components(gs).max() == RoadSim.components(gs).min(), "la segunda carretera queda unida a la primera")
	var n := RoadSim.roads(gs).size()
	check(TransitSim.erase_at(gs, Vector2(34, 18)) != "" and RoadSim.roads(gs).size() < n and TransitSim.polys(gs).size() == 1, "borrar quita el trazado bajo el clic")


func _test_blocked() -> void:
	print("-- Bloqueos: terreno no comprado y dinero")
	_new()
	var m0: float = gs.money
	var plan := TransitSim.road_plan(gs, _pv([[10, 0], [60, 10], [90, 0]]), "barro")
	check(str(plan["reason"]).contains("terreno"), "bloqueada en terreno del gobierno: %s" % str(plan["reason"]))
	check(TransitSim.build_road(gs, _pv([[10, 0], [60, 10], [90, 0]]), "barro") != "" and gs.money == m0 and RoadSim.roads(gs).is_empty(), "no cobra ni construye")
	check(str(TransitSim.road_plan(gs, _pv([[0, 0], [10, 10]]), "cemento")["reason"]).begins_with("Requiere"), "el cemento exige su tecnología")
	gs.money = 1.0
	check(str(TransitSim.road_plan(gs, _pv([[-20, 0], [20, 10]]), "barro")["reason"]).begins_with("Dinero"), "sin dinero no se construye")


func _test_bridge() -> void:
	print("-- Puentes y agua")
	_new(902, {"map_type": "costa"})
	_unlock_all()
	var sea := TransitSim.road_plan(gs, _pv([[70, 0], [140, 5], [190, 0]]), "barro")
	check(str(sea["reason"]).contains("agua"), "no se construye mar adentro: %s" % str(sea["reason"]))
	_new(903, {"map_type": "rio"})
	_unlock_all()
	# Buscar el río en z = 0.
	var rx := 0.0
	for x in range(20, 120):
		if TransitSim.is_water(gs, Vector2(x, 0)):
			rx = float(x)
			break
	check(rx > 0.0, "hay río en el mapa (x ≈ %d)" % int(rx))
	var plan := TransitSim.road_plan(gs, _pv([[rx - 30, 0], [rx + 45, 4]]), "barro")
	check(str(plan["reason"]) == "" and float(plan["bridge"]) > 3.0, "cruza el río con un puente de %.0f m" % float(plan["bridge"]))
	var dry := float(RoadSim._cost_for_length(gs, float(plan["length"]), "barro")["total"])
	check(float(plan["cost"]["total"]) > dry * 1.2, "el puente encarece la obra (%s vs %s)" % [Fmt.money(float(plan["cost"]["total"])), Fmt.money(dry)])
	check(TransitSim.build_road(gs, _pv([[rx - 30, 0], [rx + 45, 4]]), "barro") == "", "se construye con puente")
	var bridges := 0
	for r in RoadSim.roads(gs):
		if bool(r.get("bridge", false)):
			bridges += 1
	check(bridges > 0, "los tramos sobre el agua quedan marcados como puente (%d)" % bridges)


func _test_trade_manual() -> void:
	print("-- Ruta comercial y vía férrea trazadas a mano")
	_new(904)
	var tid := str(TradeSim.towns(gs)[0]["id"])
	var base := float(TradeSim.town(gs, tid)["distance"])
	var bad := TransitSim.trade_plan(gs, tid, _pv([[-5, 0], [-80, 30]]))
	check(str(bad["reason"]).contains("borde"), "debe terminar en el borde del mapa: %s" % str(bad["reason"]))
	var far := TransitSim.trade_plan(gs, tid, _pv([[-80, 60], [-199, 60]]))
	check(str(far["reason"]).contains("salida"), "debe empezar en la salida del pueblo")
	var ctrl := _pv([[-12, 6], [-60, 50], [-120, 90], [-160, 60], [-195, 70]])
	var plan := TransitSim.trade_plan(gs, tid, ctrl)
	check(str(plan["reason"]) == "" and str(plan["mode"]) == "open", "el trazado abre la ruta")
	var f := float(plan["factor"])
	check(f > 1.0 and f <= 1.25, "un trazado más largo que el automático cuesta más (factor %.2f)" % f)
	var q := TradeSim.connection_cost(gs, tid)
	var m0: float = gs.money
	check(TransitSim.set_trade_path(gs, tid, ctrl) == "", "ruta abierta con el trazado manual")
	check(absf((m0 - gs.money) - (float(q["total"]) + float(q["road"]) * (f - 1.0))) < 0.05, "cobra acuerdo + camino × largo real")
	check(TransitSim.has_manual_path(gs, tid), "el trazado queda guardado mientras se construye")
	var lines := TransitSim.trade_lines(gs)
	check(lines.size() == 1 and bool(lines[0]["manual"]), "se dibuja el trazado manual, no el automático")
	TimeManager.advance_days(int(TradeSim.project(gs, tid).get("total_days", 60)) + 2)
	var c := TradeSim.connection(gs, tid)
	check(not c.is_empty() and c.has("path"), "la conexión guarda la polilínea")
	check(absf(float(c["distance"]) - snappedf(base * f, 0.1)) < 0.2, "distancia efectiva %.1f km (base %.0f km)" % [float(c.get("distance", 0)), base])
	var q2 := TradeSim.transport_quote(gs, tid, 10.0)
	check(int(q2["days"]) >= int(ceilf(base / 25.0 * 0.8)), "el tiempo de viaje usa la distancia real")
	_techs(["ferrocarril"])
	var rctrl := _pv([[-15, -8], [-80, -40], [-150, -30], [-196, -40]])
	var rp := TransitSim.trade_plan(gs, tid, rctrl, true)
	check(str(rp["reason"]) == "" and str(rp["mode"]) == "rail", "la vía férrea se traza por puntos")
	check(TransitSim.set_trade_path(gs, tid, rctrl, true) == "", "vía férrea en construcción con su trazado")
	check(c.has("rail_path") and c.get("work", {}).has("rail"), "la conexión guarda el trazado de la vía")
	# Partida vieja: conexión sin trazado → camino automático.
	var tid2 := str(TradeSim.towns(gs)[1]["id"])
	TradeSim.open_route(gs, tid2)
	var auto_found := false
	for l in TransitSim.trade_lines(gs):
		if not bool(l["manual"]):
			auto_found = true
	check(auto_found, "una ruta sin trazado usa el camino automático")


func _test_bus_locked() -> void:
	print("-- Buses bloqueados sin tecnología")
	_new(905)
	_techs(["automovil"])
	check(ConstructionSim.build_block_reason(gs, "empresa_buses") != "", "la empresa de buses exige Transporte público")
	var d := _place("empresa_buses", 20, 20)
	check(TransitSim.buy_block_reason(gs, d).begins_with("Requiere"), "no se compran buses sin la tecnología")
	check(TransitSim.stop_block_reason(gs, Vector2(10, 10)).begins_with("Requiere"), "no hay paraderos sin la tecnología")
	check(GameData.technologies.has("transporte_publico") and (GameData.technologies["transporte_publico"]["requires"] as Array).has("automovil"), "Transporte público viene después del automóvil")
	_techs(["transporte_publico"])
	check(ConstructionSim.level_block_reason(gs, "empresa_buses", 1) == "", "con la tecnología se puede construir")
	check(ConstructionSim.level_block_reason(gs, "empresa_buses", 2) != "", "el nivel 2 exige Industria automotriz")


## Escenario: casas al suroeste, negocio al noreste (más de 110 m), carretera empedrada entre ambos.
func _scenario(with_bus: bool) -> Dictionary:
	_new(906)
	_techs(["caminos_empedrados", "automovil", "transporte_publico"])
	_unlock_all()
	var home := _place("vivienda", -62, -62)
	var job := _place("aserradero", 52, 48) if GameData.building_def("aserradero").size() > 0 else _place("carpinteria", 52, 48)
	var workers := _hire(job, 3)
	for c in workers:
		c.home_id = int(home["id"])
		c.money = 40.0
	var road := _pv([[-58, -56], [-20, -30], [10, 5], [30, 30], [48, 42]])
	TransitSim.build_road(gs, road, "empedrado")
	var out := {"home": home, "job": job, "workers": workers}
	if with_bus:
		var depot := _place("empresa_buses", 20, 30)
		_hire(depot, 2)
		TransitSim.add_stop(gs, Vector2(-56, -54))
		TransitSim.add_stop(gs, Vector2(46, 40))
		TransitSim.buy_bus(gs, depot)
		out["depot"] = depot
		out["route"] = TransitSim.create_route(gs, int(depot["id"]), [], true)
	return out


func _test_passengers() -> void:
	print("-- Pasajeros: pasaje, dinero conservado, felicidad y productividad")
	var s := _scenario(false)
	var workers: Array = s["workers"]
	check(workers.size() >= 2, "hay trabajadores que viven lejos (%d)" % workers.size())
	TransitSim.commute_daily(gs)
	var c0 = workers[0]
	check(str(TransitSim.commute_of(gs, c0).get("m", "")) == TransitSim.MODE_FAR, "sin bus caminan lejos")
	var walk_prod := TransitSim.commute_mult(gs, c0)
	var walk_happy := TransitSim.happiness_delta(gs, c0)
	var out_walk := BusinessSim.expected_output(gs, s["job"])
	check(walk_prod < 1.0 and walk_happy < 0.0, "caminar lejos cansa (×%.3f, felicidad %.1f)" % [walk_prod, walk_happy])
	s = _scenario(true)
	workers = s["workers"]
	c0 = workers[0]
	check(s["route"].has("route"), "ruta de bus automática creada (%s)" % str(s["route"].get("error", "")))
	var st := TransitSim.route_status(gs, s["route"].get("route", {"id": -1, "depot": -1, "stops": []}))
	check(bool(st.get("ok", false)) and int(st["capacity"]) > 0, "la ruta opera (capacidad %d/día)" % int(st.get("capacity", 0)))
	var before := _town_money()
	var led0 := BusinessSim.period_value(s["depot"], "month", "ventas")
	var cm0: float = c0.money
	TransitSim.commute_daily(gs)
	var after := _town_money()
	var riders := 0
	for c in workers:
		if str(TransitSim.commute_of(gs, c).get("m", "")) == TransitSim.MODE_BUS:
			riders += 1
	check(riders == workers.size(), "los %d trabajadores lejanos toman el bus" % riders)
	var fare2 := TransitSim.fare(gs) * 2.0
	check(absf((cm0 - c0.money) - fare2) < 0.001 and fare2 > 0.0, "cada pasajero paga ida y vuelta (%s)" % Fmt.money2(fare2))
	check(absf(BusinessSim.period_value(s["depot"], "month", "ventas") - led0 - fare2 * riders) < 0.001, "la empresa de buses cobra los pasajes")
	check(absf(after - before) < 0.0001, "el dinero se conserva (vecinos → empresa)")
	check(TransitSim.commute_mult(gs, c0) > walk_prod and TransitSim.happiness_delta(gs, c0) > walk_happy, "en bus rinden más y están más felices")
	check(BusinessSim.expected_output(gs, s["job"]) > out_walk, "el negocio produce más con el bus")
	var m0: float = gs.money
	TransitSim._bus_costs(gs)
	check(gs.money < m0, "el bus paga mantenimiento y combustible")
	TransitSim.monthly(gs)
	check(int(TransitSim.get_route(gs, int(s["route"]["route"]["id"])).get("last_riders", 0)) == riders, "pasajeros del mes en la ruta")
	check(int(TransitSim.summary(gs)["riders_last"]) == riders, "resumen: pasajeros del mes anterior")
	check(TransitSim.panel_lines(gs, s["job"]).contains("en bus"), "el panel del negocio dice cómo llegan")


func _test_parking() -> void:
	print("-- Parqueadero y acceso moderno")
	var s := _scenario(false)
	var workers: Array = s["workers"]
	var rich = workers[0]
	rich.money = 2000.0
	TransitSim._access_daily(gs)
	check(TransitSim.access_mult(gs, s["job"]) < 1.0, "negocio moderno sin parqueadero ni bus rinde menos (×%.2f)" % TransitSim.access_mult(gs, s["job"]))
	check(TransitSim.panel_lines(gs, s["job"]).contains("Carretera: [color=#6c6]con acceso"), "el panel muestra el acceso por carretera")
	var pk := _place("parqueadero", 60, 60)
	var before := _town_money()
	TransitSim.commute_daily(gs)
	check(str(TransitSim.commute_of(gs, rich).get("m", "")) == TransitSim.MODE_CAR, "el trabajador rico llega en auto")
	check(str(TransitSim.commute_of(gs, workers[1]).get("m", "")) == TransitSim.MODE_FAR, "el pobre sigue a pie")
	check(int(gs.transit["parking_use"].get(str(pk["id"]), 0)) == 1, "ocupa un puesto del parqueadero")
	check(absf(_town_money() - before) < 0.0001 and BusinessSim.period_value(pk, "month", "ventas") > 0.0, "paga el parqueo (dinero conservado)")
	TransitSim._access_daily(gs)
	check(TransitSim.access_mult(gs, s["job"]) == 1.0, "con parqueadero cerca no hay penalización")
	check(TransitSim.commute_mult(gs, rich) > 1.0, "llegar en auto rinde más")
	# Sin carretera entre casa y trabajo no hay auto.
	for p in TransitSim.polys(gs).duplicate():
		TransitSim.remove_poly(gs, int(p["id"]))
	TransitSim.commute_daily(gs)
	check(str(TransitSim.commute_of(gs, rich).get("m", "")) == TransitSim.MODE_FAR, "sin carretera, a pie")
	var home: Dictionary = s["home"]
	check(TransitSim.panel_lines(gs, s["job"]).contains("sin acceso") and TransitSim.panel_lines(gs, home) == "", "sin carretera el negocio funciona igual (panel)")


func _test_save_load() -> void:
	print("-- Guardar y cargar")
	var s := _scenario(true)
	var tid := str(TradeSim.towns(gs)[0]["id"])
	TransitSim.set_trade_path(gs, tid, _pv([[-12, 6], [-100, 40], [-195, 50]]))
	TimeManager.advance_days(3)
	var d: Dictionary = JSON.parse_string(JSON.stringify(gs.to_dict()))
	var n_polys := TransitSim.polys(gs).size()
	var n_roads := RoadSim.roads(gs).size()
	var commute := JSON.stringify(gs.transit["commute"], "", true)
	var money: float = gs.money
	gs.load_dict(d)
	check(TransitSim.polys(gs).size() == n_polys and RoadSim.roads(gs).size() == n_roads, "carreteras por puntos guardadas")
	check(TransitSim.stops(gs).size() == 2 and TransitSim.routes(gs).size() == 1 and TransitSim.buses(gs).size() == 1, "paraderos, rutas y buses guardados")
	check(JSON.stringify(gs.transit["commute"], "", true) == commute, "trayectos guardados")
	check(TransitSim.has_manual_path(gs, tid), "trazado de la ruta comercial guardado")
	check(absf(gs.money - money) < 0.001, "dinero igual")
	TimeManager.advance_days(2)
	check(TransitSim.summary(gs)["riders_month"] > 0, "los buses siguen llevando pasajeros tras cargar")
	# Partida vieja sin "transit".
	d.erase("transit")
	gs.load_dict(d)
	check(TransitSim.stops(gs).is_empty() and float(gs.transit["fare"]) > 0.0, "partida vieja: valores por defecto")
	TimeManager.advance_days(1)
	check(gs.running, "la partida vieja sigue corriendo")
	var _u := s


func _test_ui() -> void:
	print("-- Interfaz y visuales")
	_new(907)
	_techs(["caminos_empedrados", "ferrocarril", "automovil", "transporte_publico"])
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	var tv: TransitVisuals = TransitVisuals.instance
	check(tv != null, "TransitVisuals está en el mundo")
	tv.start_trace("road", "empedrado")
	for p in [Vector2(-25, -10), Vector2(0, -25), Vector2(25, -10)]:
		tv.set_hover(p)
		tv.add_point()
	tv.set_hover(Vector2(30, 10))
	check(tv.hint_text().contains("m"), "vista previa con costo: %s" % tv.hint_text().get_slice("(", 0))
	tv.finish()
	check(TransitSim.polys(gs).size() == 1, "la carretera trazada en el mundo se construyó")
	await get_tree().process_frame
	check(tv.road_count() >= 1, "la carretera curva se dibuja")
	tv.start_trace("stop")
	tv.set_hover(Vector2(0, -25))
	tv.add_point()
	check(TransitSim.stops(gs).size() == 1, "paradero colocado sobre la carretera")
	tv.cancel_trace()
	world.hud._show_dock("transit")
	await get_tree().process_frame
	check(world.hud.transit_panel.visible, "panel Transporte público visible")
	world.hud.close_dock()
	world.hud._show_dock("build")
	await get_tree().process_frame
	for i in range(5):
		await get_tree().process_frame
	world.queue_free()
	await get_tree().process_frame
