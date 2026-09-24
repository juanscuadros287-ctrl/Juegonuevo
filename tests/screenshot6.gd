extends Node
## Captura del panel de Gobierno: godot res://tests/screenshot6.tscn -- <carpeta>

func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://"
	GameState.new_game({"seed": 13, "difficulty": "normal"})
	TechSim.complete(GameState, "herbolaria")
	TimeManager.advance_days(200)
	GameState.government["next_mission_day"] = 0
	GovSim.monthly(GameState)
	GameState.government["tenders"] = [{"id": 1, "type": "iglesia", "value": 3000.0, "status": "open", "deadline": GameState.today() + 90, "bid": 0.0}]
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	world.hud._show_dock("government")
	for i in range(30):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/f5_gobierno.png" % out)
	get_tree().quit()
