extends Node
## Captura de almacenes individuales: fábricas vinculadas en verde junto a su almacén, una sin
## almacén en rojo y el ghost verde de una fábrica que se está colocando al lado.
## xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 res://tests/screenshot_almacen.tscn -- <carpeta>


func _place(type_id: String, x: float, z: float, rot := 0.0, level := 1) -> Dictionary:
	var b: Dictionary = ConstructionSim.make_building(GameState, type_id, level, x, z, rot, "jugador")
	GameState.add_building(b)
	return b


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://"
	GameState.new_game({"map_type": "interior", "seed": 2024, "difficulty": "facil"})
	GameState.suppress_notifications = true
	GameState.money = 50000.0
	var alm := _place("almacen", 26, 22, 0.0, 2)
	_place("herreria", 26, 11)
	_place("rebano", 37, 23)
	_place("tejeduria", -26, 27, 0.4)
	_place("caballeriza", -22, -22, 0.6)
	WarehouseSim.relink_all(GameState)
	WarehouseSim.add_to(GameState, int(alm["id"]), "hierro", 240.0)
	WarehouseSim.add_to(GameState, int(alm["id"]), "carbon", 180.0)
	WarehouseSim.add_to(GameState, int(alm["id"]), "lana", 90.0)
	TimeManager.total_hours += 10 - TimeManager.hour()
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	# Ghost de un molino que se está colocando al lado del almacén (verde + flecha).
	var vis: LogisticsVisuals = LogisticsVisuals.instance
	var gpos := Vector3(15.5, 0, 25)
	gpos.y = world.terrain.height_at(gpos.x, gpos.z)
	var mat := vis.placement_feedback("molino", gpos, -1, true, MeshLib.ghost_mat(true))
	var ghost := MeshLib.build_model(GameData.level_def("molino", 1).get("model", []), 1.0, mat)
	ghost.position = gpos
	world.add_child(ghost)
	world.hud.set_placement_hint("Molino de piedra — ✔" + vis.placement_text())
	var rig: CameraRig = world.camera_rig
	rig.target_pos = Vector3(24, 3, 18)
	rig.position = rig.target_pos
	rig.distance = 40.0
	rig.target_distance = 40.0
	rig.yaw = 200.0
	rig.target_yaw = 200.0
	world.hud.open_building(int(alm["id"]))
	var tabs: TabContainer = world.hud.building_panel.tabs
	for i in range(tabs.get_tab_count()):
		if tabs.get_tab_title(i) == "Almacén":
			tabs.current_tab = i
	for i in range(40):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/almacen_verde.png" % out)
	print("captura guardada en %s/almacen_verde.png" % out)
	get_tree().quit()
