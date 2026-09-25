extends Node
## Captura del transporte: carretera curva trazada por puntos, camino y vía férrea hacia otro pueblo
## trazados a mano (durmientes y rieles), empresa de buses con paraderos y buses, y un parqueadero.
## xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 res://tests/screenshot_transporte.tscn -- <carpeta>


func _pv(arr: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for a in arr:
		out.append(Vector2(float(a[0]), float(a[1])))
	return out


func _place(type_id: String, x: float, z: float, rot := 0.0, level := 1) -> Dictionary:
	var b: Dictionary = ConstructionSim.make_building(GameState, type_id, level, x, z, rot, "jugador")
	GameState.add_building(b)
	return b


func _hire(b: Dictionary, n: int) -> void:
	var hired := 0
	for c in BusinessSim.candidates(GameState, b):
		if hired >= n or c.job_kind == "obra":
			continue
		if BusinessSim.hire(GameState, b, c, BusinessSim.asked_wage(GameState, c, str(b["type"])) * 1.2) == "":
			hired += 1


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://"
	var gs = GameState
	gs.new_game({"map_type": "interior", "seed": 2024, "difficulty": "facil"})
	gs.suppress_notifications = true
	gs.money = 900000.0
	gs.research["era"] = 3
	for t in ["carretas", "caminos_empedrados", "maquina_vapor", "ferrocarril", "automovil", "transporte_publico"]:
		gs.techs.append(t)
	gs.unlocked_zones = []
	for x in range(gs.ZONE_GRID):
		for y in range(gs.ZONE_GRID):
			gs.unlocked_zones.append([x, y])
	var tid := str(TradeSim.towns(gs)[0]["id"])
	TransitSim.set_trade_path(gs, tid, _pv([[-9, 4], [-40, 26], [-80, 20], [-130, 48], [-199, 40]]))
	TimeManager.advance_days(int(TradeSim.project(gs, tid).get("total_days", 40)) + 1)
	_place("estacion_tren", -22, -16, 0.4)
	TransitSim.set_trade_path(gs, tid, _pv([[-24, -26], [-44, -34], [-90, -18], [-150, -40], [-199, -30]]), true)
	TimeManager.advance_days(int(TradeSim.connection(gs, tid)["work"]["rail"]["done_day"]) - gs.today() + 1)
	# Carretera curva de cemento por el pueblo y una rama empedrada.
	TransitSim.build_road(gs, _pv([[-34, 10], [-18, -2], [0, 12], [18, 24], [34, 14], [46, -8]]), "cemento")
	TransitSim.build_road(gs, _pv([[18, 24], [10, 42], [-8, 54]]), "empedrado")
	var depot := _place("empresa_buses", -42, 3, 1.2)
	_hire(depot, 3)
	TransitSim.buy_bus(gs, depot)
	TransitSim.buy_bus(gs, depot)
	TransitSim.add_stop(gs, Vector2(-16, -6))
	TransitSim.add_stop(gs, Vector2(44, -4))
	TransitSim.add_stop(gs, Vector2(-6, 50))
	TransitSim.create_route(gs, int(depot["id"]), [], true)
	var pk := _place("parqueadero", 10, 2, 0.5)
	gs.transit["parking_use"] = {str(pk["id"]): 7}
	_place("aserradero", 52, 18, 1.2)
	TimeManager.total_hours += 10 - TimeManager.hour()
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	TransitVisuals.instance.rebuild()
	var tv: TransitVisuals = TransitVisuals.instance
	# Ghost de una carretera que se está trazando.
	tv.start_trace("road", "empedrado")
	for p in [Vector2(-34, 10), Vector2(-52, 22)]:
		tv.set_hover(p)
		tv.add_point()
	var rig: CameraRig = world.camera_rig
	rig.target_pos = Vector3(-6, 3, 4)
	rig.position = rig.target_pos
	rig.distance = 80.0
	rig.target_distance = 80.0
	rig.yaw = 15.0
	rig.target_yaw = 15.0
	world.hud._show_dock("transit")
	for i in range(40):
		await get_tree().process_frame
	tv.set_hover(Vector2(-62, 40))
	# Un bus saliendo del depósito y otro en la curva del pueblo.
	var k := 0
	for e in tv._bus_nodes:
		e["phase"] = [0.07, 0.3][k % 2]
		k += 1
	tv._place_buses()
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/transporte.png" % out)
	print("captura guardada en %s/transporte.png" % out)
	get_tree().quit()
