extends Node
## Capturas Fase 3: godot res://tests/screenshot3.tscn -- <carpeta_salida>

func _shot(out: String, name: String) -> void:
	for i in range(30):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/f3_%s.png" % [out, name])


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://"
	GameState.new_game({"map_type": "costa", "seed": 77, "difficulty": "facil"})
	var farm: Dictionary = ConstructionSim.start_construction(GameState, "granja", 30, -8, 0.3, "Granja Cuadros")["building"]
	var bank: Dictionary = ConstructionSim.start_construction(GameState, "banco", -32, 10, 1.0, "Banco Cuadros")["building"]
	ConstructionSim.start_construction(GameState, "taberna", -10, 34, 2.0, "Taberna")
	BankSim.request_player_loan(GameState, 3000.0, 60)
	TimeManager.advance_days(60)
	for b in [farm, bank]:
		for c in BusinessSim.candidates(GameState, b).slice(0, 3):
			BusinessSim.hire(GameState, b, c, BusinessSim.asked_wage(GameState, c, b["type"]))
	BankSim.bank_settings(GameState, bank)
	bank["loan_rate"] = 0.06
	for m in range(30):
		TimeManager.advance_days(30)
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	world.hud._show_dock("finance")
	await _shot(out, "finanzas")
	world.hud.open_building(int(bank["id"]))
	world.hud.building_panel.tabs.current_tab = 2
	await _shot(out, "banco")
	get_tree().quit()
