extends Node
## Capturas automáticas (requiere pantalla o Xvfb):
## godot res://tests/screenshot.tscn -- <map_type> <carpeta_salida>

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var map := args[0] if args.size() > 0 else "rio"
	var out := args[1] if args.size() > 1 else "user://"
	GameState.new_game({"map_type": map, "seed": 2024, "town_name": "San Rafael"})
	TimeManager.total_hours += 4  # 10:00, gente fuera de casa
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	TimeManager.set_speed(0)
	var rig: CameraRig = world.camera_rig
	var shots := [["lejos", 300.0, 35.0], ["medio", 85.0, 20.0], ["cerca", 16.0, 50.0]]
	for s in shots:
		rig.target_distance = s[1]
		rig.distance = s[1]
		rig.target_yaw = s[2]
		rig.yaw = s[2]
		if s[0] == "cerca":
			var ids: Array = world.agents.keys()
			for id in ids:
				if world.agents[id].visible:
					EventBus.citizen_selected.emit(id)
					rig.target_pos = world.agents[id].global_position
					rig.position = rig.target_pos
					break
		for i in range(40):
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [out, map, s[0]])
	get_tree().quit()
