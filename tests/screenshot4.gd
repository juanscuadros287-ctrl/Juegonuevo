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
	var x := 28.0
	for tier in ["normal", "media", "alta"]:
		ids.append(ConstructionSim.start_construction(GameState, "vivienda", x, -30, 0.0, "", "sas", tier)["building"])
		x += 9.0
	TimeManager.advance_days(80)
	TimeManager.total_hours += 10 - TimeManager.hour()
	for c in GameState.citizens.values().slice(1, 4):
		c.home_id = int(ids[2]["id"])
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	var rig: CameraRig = world.camera_rig
	rig.target_pos = Vector3(37, 3, -30)
	rig.position = rig.target_pos
	rig.distance = 24.0
	rig.target_distance = 24.0
	rig.yaw = 20.0
	rig.target_yaw = 20.0
	await _shot(out, "exterior")
	EventBus.interior_requested.emit(int(ids[2]["id"]))
	await _shot(out, "interior_alta")
	get_tree().quit()
