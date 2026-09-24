extends Node
## Capturas de viviendas por calidad: godot res://tests/screenshot4.tscn -- <carpeta>

func _shot(out: String, name: String) -> void:
	for i in range(30):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/casas_%s.png" % [out, name])


func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://"
	GameState.new_game({"seed": 5, "difficulty": "facil", "map_type": "interior"})
	GameState.money = 90000.0
	var ids := []
	var x := -10.0
	for tier in ["normal", "media", "alta"]:
		var r := {}
		for dz in range(0, 60, 3):
			r = ConstructionSim.start_construction(GameState, "vivienda", x, -37.0 + dz, 0.0, "", "sas", tier)
			if r.has("building"):
				break
		if not r.has("building"):
			print("ERR ", r)
			get_tree().quit()
			return
		ids.append(r["building"])
		x += 9.0
	TimeManager.advance_days(80)
	TimeManager.total_hours += 10 - TimeManager.hour()
	for c in GameState.citizens.values().slice(1, 4):
		c.home_id = int(ids[2]["id"])
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	var rig: CameraRig = world.camera_rig
	rig.target_pos = Vector3(float(ids[1]["x"]), 3, float(ids[1]["z"]))
	rig.position = rig.target_pos
	rig.distance = 24.0
	rig.target_distance = 24.0
	rig.yaw = 20.0
	rig.target_yaw = 20.0
	await _shot(out, "exterior")
	EventBus.interior_requested.emit(int(ids[2]["id"]))
	await _shot(out, "interior_alta")
	world.hud._close_interior()
	world.hud._show_dock("stats")
	await _shot(out, "estadisticas")
	get_tree().quit()
