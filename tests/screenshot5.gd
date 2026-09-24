extends Node
## Captura del árbol de investigación: godot res://tests/screenshot5.tscn -- <carpeta>

func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://"
	GameState.new_game({"seed": 9, "difficulty": "facil"})
	for id in ["adobe", "herbolaria", "rotacion_cultivos", "escuela_parroquial", "contabilidad"]:
		TechSim.complete(GameState, id)
	TechSim.set_current(GameState, "ladrillo")
	GameState.research["progress"] = 200.0
	TechSim.enqueue(GameState, "saneamiento")
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	world.hud._open_research()
	world.hud.research_screen._select("ladrillo")
	for i in range(30):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/f4_investigacion.png" % out)
	get_tree().quit()
