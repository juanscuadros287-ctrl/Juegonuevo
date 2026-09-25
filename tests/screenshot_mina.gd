extends Node
## Captura de una mina completa sobre su yacimiento: centro de excavación, tres frentes
## (tajo, socavón con malacate y torre de extracción) y escombrera, con el área teñida.
## xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 res://tests/screenshot_mina.tscn -- <carpeta>


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://"
	var gs = GameState
	gs.new_game({"map_type": "interior", "seed": 2024, "difficulty": "facil"})
	gs.suppress_notifications = true
	gs.money = 500000.0
	gs.unlocked_zones.append([3, 2])
	for t in ["polvora", "maquina_vapor"]:
		if not gs.techs.has(t):
			gs.techs.append(t)
	TimeManager.total_hours += 10 - TimeManager.hour()
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	# Busca terreno llano y seco en la zona vecina para el yacimiento.
	var terrain: Terrain = world.terrain
	var spot := Vector2(62, 10)
	var best := INF
	for x in range(52, 100, 4):
		for z in range(-26, 30, 4):
			if terrain.footprint_ok(x, z, 24.0) == "" and terrain.is_land(x, z, 1.0) and Vector2(x - 62, z - 6).length() < best:
				best = Vector2(x - 62, z - 6).length()
				spot = Vector2(x, z)
	gs.logistics["deposits"] = [{"id": 1, "type": "hierro", "x": spot.x, "z": spot.y, "amount": 14000.0, "initial": 14000.0, "grade": 1.1}]
	MineSim.ensure_area(gs.logistics["deposits"][0])
	var d: Dictionary = gs.logistics["deposits"][0]
	var c := spot + Vector2(-6, 4)
	var r := ConstructionSim.start_construction(gs, "mina_hierro", c.x, c.y, 0.3, "Mina La Colorada", "sas")
	var mine: Dictionary = r.get("building", {})
	if mine.is_empty():
		print("no se pudo construir la mina: ", r.get("error", ""))
		get_tree().quit(1)
		return
	mine["status"] = "activo"
	mine["level"] = 2
	mine["target_level"] = 2
	var plan := [["tajo", 0.2, 0.62, 0.0], ["socavon", -1.9, 0.62, 2.6], ["torre_extraccion", 1.9, 0.6, -0.5], ["escombrera", 3.0, 0.55, 0.8]]
	for p in plan:
		var ang := float(p[1])
		var pos := Vector2(float(d["x"]), float(d["z"])) + Vector2.from_angle(ang) * MineSim.radius_at(d, ang) * float(p[2])
		var err := MineSim.add_part(gs, mine, str(p[0]), pos.x, pos.y, float(p[3]))
		if err != "":
			print("  %s: %s" % [p[0], err])
	for part in MineSim.parts(mine):
		part["status"] = "activo"
	var hired := 0
	for cz in BusinessSim.candidates(gs, mine):
		if hired >= 10:
			break
		if BusinessSim.hire(gs, mine, cz, BusinessSim.asked_wage(gs, cz, "mina_hierro") * 1.1) == "":
			hired += 1
	EventBus.building_changed.emit(int(mine["id"]))
	MiningVisuals.instance.rebuild_all()
	var rig: CameraRig = world.camera_rig
	var cy := terrain.height_at(float(d["x"]), float(d["z"]))
	rig.target_pos = Vector3(float(d["x"]) - 2.0, cy, float(d["z"]) + 2.0)
	rig.position = rig.target_pos
	rig.distance = 50.0
	rig.target_distance = 50.0
	rig.yaw = 205.0
	rig.target_yaw = 205.0
	await get_tree().process_frame
	# El panel ocupa la derecha: corre la vista para que la mina quede a la izquierda.
	var right: Vector3 = rig.camera.global_transform.basis.x
	right.y = 0.0
	rig.target_pos += right.normalized() * 11.0
	rig.position = rig.target_pos
	world.hud.open_building(int(mine["id"]))
	var tabs: TabContainer = world.hud.building_panel.tabs
	for i in range(tabs.get_tab_count()):
		if tabs.get_tab_title(i) == "Mina":
			tabs.current_tab = i
	for i in range(40):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/mina.png" % out)
	print("captura guardada en %s/mina.png (frentes: %d)" % [out, MineSim.faces(mine).size()])
	get_tree().quit()
