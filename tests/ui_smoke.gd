extends Node
## Prueba de humo de la interfaz: abre todos los paneles, modo construcción, interior.
## godot --headless res://tests/ui_smoke.tscn

func _ready() -> void:
	GameState.new_game({"seed": 21, "difficulty": "facil"})
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	var hud: Hud = world.hud
	for mode in ["player", "build", "companies", "finance", "stats", "government", "logistics", "trade", "tourism", "realestate"]:
		hud._show_dock(mode)
		await get_tree().process_frame
	BankSim.request_player_loan(GameState, 500.0, 12)
	var bank: Dictionary = ConstructionSim.start_construction(GameState, "banco", -32, 10, 0.0, "Banco Test", "sas")["building"]
	var r := ConstructionSim.start_construction(GameState, "granja", 30, -8, 0.0, "Granja Test", "sin_lucro")
	var farm: Dictionary = r["building"]
	TimeManager.advance_days(40)
	hud.open_building(int(farm["id"]))
	for i in range(hud.building_panel.tabs.get_tab_count()):
		hud.building_panel.tabs.current_tab = i
		await get_tree().process_frame
	hud.building_panel._open_hire()
	hud.open_building(int(bank["id"]))
	for i in range(hud.building_panel.tabs.get_tab_count()):
		hud.building_panel.tabs.current_tab = i
		await get_tree().process_frame
	# Bienes raíces: proyecto por etapas, pestaña Unidades, panel y diálogo de crédito.
	for t in ["adobe", "ladrillo", "arquitectura_urbana"]:
		if not GameState.techs.has(t):
			GameState.techs.append(t)
	GameState.money += 20000.0
	var pr := RealEstateSim.start_project(GameState, 4, "media", 34, 24, 0.0, "Torres Test", {"credit_lender": "externo", "credit_ratio": 0.5})
	print("PROYECTO: ", pr.get("error", "iniciado"))
	if pr.has("building"):
		hud.open_building(int(pr["building"]["id"]))
		for i in range(hud.building_panel.tabs.get_tab_count()):
			hud.building_panel.tabs.current_tab = i
			await get_tree().process_frame
	var apt := ConstructionSim.make_building(GameState, "vivienda", 4, -34, 26, 0.0, "jugador")
	GameState.add_building(apt)
	RealEstateSim.ensure_units(GameState, apt)
	hud.open_building(int(apt["id"]))
	for i in range(hud.building_panel.tabs.get_tab_count()):
		hud.building_panel.tabs.current_tab = i
		await get_tree().process_frame
	hud._show_dock("realestate")
	for i in range(hud.realestate_panel.tabs.get_tab_count()):
		hud.realestate_panel.tabs.current_tab = i
		await get_tree().process_frame
	hud.realestate_panel._place()
	await get_tree().process_frame
	world._update_placement()
	world.cancel_placement()
	hud.close_dock()
	LoanDialog.open(hud, func(): pass)
	await get_tree().process_frame
	hud._show_dock("build")
	await get_tree().process_frame
	hud._show_dock("finance")
	await get_tree().process_frame
	if not BankSim.player_loans(GameState).is_empty():
		LoanDialog.show_schedule(hud, BankSim.player_loans(GameState)[0])
	await get_tree().process_frame
	hud._show_dock("stats")
	await get_tree().process_frame
	print("RECOMENDACIONES: ", StatsSim.advice(GameState))
	hud._open_research()
	await get_tree().process_frame
	hud.research_screen._select("adobe")
	hud.research_screen._enqueue_with_prereqs("acueductos")
	hud.research_screen.refresh()
	await get_tree().process_frame
	hud.research_screen.close()
	var some: Citizen = GameState.citizens.values()[3]
	EventBus.citizen_selected.emit(some.id)
	await get_tree().process_frame
	EventBus.build_mode_requested.emit("vivienda", "alta")
	await get_tree().process_frame
	world._update_placement()
	world.cancel_placement()
	world.start_move(int(farm["id"]))
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
