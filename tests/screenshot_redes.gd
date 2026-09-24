extends Node
## Captura de las redes: central de carbón con postes y cables hasta fábricas y casas, vista de capa
## eléctrica (verde conectado, rojo sin servicio), una planta de agua y el panel Servicios públicos.
## xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 res://tests/screenshot_redes.tscn -- <carpeta>


func _place(type_id: String, x: float, z: float, rot := 0.0, level := 1) -> Dictionary:
	var b: Dictionary = ConstructionSim.make_building(GameState, type_id, level, x, z, rot, "jugador")
	GameState.add_building(b)
	return b


func _seg(ax: float, az: float, bx: float, bz: float, kind := "aereo") -> void:
	GridSim.add_segment(GameState, Vector2(ax, az), Vector2(bx, bz), kind)


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://"
	var gs = GameState
	gs.new_game({"map_type": "interior", "seed": 2024, "difficulty": "facil"})
	gs.suppress_notifications = true
	gs.money = 80000.0
	gs.research["era"] = 3
	for t in ["dinamo", "electricidad", "arquitectura_urbana", "adobe", "ladrillo", "acueductos", "potabilizacion"]:
		gs.techs.append(t)
	_place("central_carbon", 30, 30, 0.0)
	_place("textil", 34, 8, 1.57, 3)
	_place("fabrica_electronica", -32, 30, 0.3)   # sin cable: roja
	_place("vivienda", 14, 30, 0.0, 4)
	_place("vivienda", 12, -30, 0.0, 4)          # apartamentos sin cable: rojo
	_place("planta_agua", -30, -24, 0.4)
	WarehouseSim.relink_all(gs)
	_seg(30, 30, 30, 8)
	_seg(30, 30, 14, 22)
	_seg(14, 22, -6, 20)
	_seg(-6, 20, -20, 12)
	_seg(-30, -24, -14, -14, "tuberia")
	for c in gs.citizens.values():
		c.money += 80.0
	GridSim.daily(gs)
	for b in gs.buildings:
		if gs.owned_by_player(b) and BusinessSim.is_business(b):
			var hired := 0
			for c in BusinessSim.candidates(gs, b):
				if hired >= int(gs.level_def(b).get("jobs", 0)) or c.job_kind == "obra":
					continue
				c.education = maxi(c.education, int(gs.level_def(b).get("min_education", 0)))
				if BusinessSim.hire(gs, b, c, BusinessSim.asked_wage(gs, c, str(b["type"])) * 1.1) == "":
					hired += 1
			for g in LogisticsSim.recipe_inputs(gs.building_def(b), gs.level_def(b)):
				b["inventory"][str(g)] = 200.0
	BusinessSim.produce(gs)
	EnergySim.daily(gs)
	TimeManager.total_hours += 10 - TimeManager.hour()
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	var uv: UtilitiesVisuals = UtilitiesVisuals.instance
	uv.set_layer("power")
	# Ghost de un tramo que se está trazando hacia los apartamentos sin luz.
	uv.start_trace("aereo")
	uv.set_hover(Vector2(-6, 20))
	uv.confirm_point()
	uv.set_hover(Vector2(4, -22))
	var rig: CameraRig = world.camera_rig
	rig.target_pos = Vector3(4, 3, 6)
	rig.position = rig.target_pos
	rig.distance = 78.0
	rig.target_distance = 78.0
	rig.yaw = 205.0
	rig.target_yaw = 205.0
	world.hud._show_dock("utilities")
	for i in range(40):
		await get_tree().process_frame
	uv.set_hover(Vector2(4, -22))
	world.hud.utilities_panel._update_live()
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/redes.png" % out)
	print("captura guardada en %s/redes.png" % out)
	get_tree().quit()
