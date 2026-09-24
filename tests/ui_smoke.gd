extends Node
## Prueba de humo de la interfaz: abre todos los paneles, modo construcción, interior.
## godot --headless res://tests/ui_smoke.tscn

func _ready() -> void:
	GameState.new_game({"seed": 21, "difficulty": "facil"})
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	var hud: Hud = world.hud
	for mode in ["player", "build", "companies"]:
		hud._show_dock(mode)
		await get_tree().process_frame
	var r := ConstructionSim.start_construction(GameState, "granja", 30, -8, 0.0, "Granja Test", "sin_lucro")
	var farm: Dictionary = r["building"]
	TimeManager.advance_days(40)
	hud.open_building(int(farm["id"]))
	for i in range(hud.building_panel.tabs.get_tab_count()):
		hud.building_panel.tabs.current_tab = i
		await get_tree().process_frame
	hud.building_panel._open_hire()
	var some: Citizen = GameState.citizens.values()[3]
	EventBus.citizen_selected.emit(some.id)
	await get_tree().process_frame
	EventBus.build_mode_requested.emit("vivienda", "alta")
	await get_tree().process_frame
	world._update_placement()
	world.cancel_placement()
	EventBus.zone_mode_requested.emit()
	world.cancel_placement()
	EventBus.interior_requested.emit(PlayerSim.player_home(GameState)["id"])
	await get_tree().process_frame
	hud._open_invite()
	hud._close_interior()
	TimeManager.set_speed(1)
	for i in range(30):
		await get_tree().process_frame
	TimeManager.start_jump(2)
	while TimeManager.jumping:
		await get_tree().process_frame
	print("UI SMOKE OK · edificios %d · población %d · %s" % [GameState.buildings.size(), GameState.citizens.size(), TimeManager.date_string()])
	get_tree().quit()
