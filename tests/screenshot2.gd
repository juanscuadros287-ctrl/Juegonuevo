extends Node
## Capturas Fase 2: godot res://tests/screenshot2.tscn -- <carpeta_salida>

func _shot(out: String, name: String, frames := 30) -> void:
	for i in range(frames):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/f2_%s.png" % [out, name])


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://"
	GameState.new_game({"map_type": "rio", "seed": 2024, "difficulty": "facil"})
	GameState.money = 50000.0
	var farm: Dictionary = ConstructionSim.start_construction(GameState, "granja", 34, -6, 0.3, "Granja Cuadros", "sas")["building"]
	ConstructionSim.start_construction(GameState, "taberna", -30, 14, 1.2, "Taberna El Roble", "sas")
	ConstructionSim.start_construction(GameState, "oficina", 14, 32, 3.1, "", "sas")
	var alta: Dictionary = ConstructionSim.start_construction(GameState, "vivienda", -20, -30, 0.6, "", "sas", "alta")["building"]
	ConstructionSim.start_construction(GameState, "vivienda", -34, -14, 1.0, "", "sas", "media")
	for i in range(60):
		GameState.money = 50000.0
		TimeManager.advance_days(1)
	ConstructionSim.start_construction(GameState, "vivienda", 30, 20, 2.0, "", "sas", "normal")
	TimeManager.advance_days(4)
	var cands := BusinessSim.candidates(GameState, farm)
	for i in range(3):
		BusinessSim.hire(GameState, farm, cands[i], BusinessSim.asked_wage(GameState, cands[i], "granja"))
	TimeManager.advance_days(20)
	TimeManager.total_hours += 10 - TimeManager.hour()
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	var rig: CameraRig = world.camera_rig
	rig.target_pos = Vector3(0, 3, 0)
	rig.position = rig.target_pos
	rig.distance = 95.0
	rig.target_distance = 95.0
	await _shot(out, "pueblo")
	world.hud.open_building(int(farm["id"]))
	rig.target_pos = Vector3(34, 3, -6)
	rig.position = rig.target_pos
	rig.distance = 30.0
	rig.target_distance = 30.0
	await _shot(out, "negocio")
	world.hud.close_dock()
	EventBus.interior_requested.emit(int(PlayerSim.player_home(GameState)["id"]))
	await _shot(out, "interior_normal")
	world.hud._close_interior()
	for c in GameState.citizens.values().slice(0, 3):
		c.home_id = int(alta["id"])
	EventBus.interior_requested.emit(int(alta["id"]))
	await _shot(out, "interior_alta")
	get_tree().quit()
