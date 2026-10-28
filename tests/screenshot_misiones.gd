extends Node
## Capturas de misiones guía, escenarios y logros (docs/MISIONES_ESCENARIOS.md):
## xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 \
##     res://tests/screenshot_misiones.tscn -- docs/capturas/misiones

var out := "user://"


func _shot(name: String, frames := 30) -> void:
	for i in range(frames):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("captura: ", name)


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "user://"
	DirAccess.make_dir_recursive_absolute(out)
	ProgressSim.use_profile("user://screenshot_logros.cfg", false)
	# Menú principal: nueva partida con escenarios y dificultad.
	var mm: MainMenu = load("res://scenes/main_menu.tscn").instantiate()
	add_child(mm)
	await get_tree().process_frame
	mm._show_new()
	mm._select_scen(ScenarioSim.ids().find("quebrada"), false)
	await _shot("menu_escenario_quebrada", 40)
	mm._select_scen(ScenarioSim.ids().find("industrial"), false)
	mm._select_diff(mm.diff_ids.find("dificil"))
	await _shot("menu_escenario_industrial_dificil", 20)
	mm.queue_free()
	await get_tree().process_frame
	# Partida: escenario de empresa quebrada, con algunas misiones hechas.
	var gs = GameState
	gs.new_game({"map_type": "interior", "seed": 77, "difficulty": "normal", "scenario": "quebrada", "town_name": "San Rafael"})
	gs.government["treasury"] = 3000.0
	gs.trade["totals"]["exports"] = 120.0
	ProgressSim._check_missions(gs)
	TimeManager.total_hours += 10 - TimeManager.hour()
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	TimeManager.set_speed(0)
	var hud: Hud = world.hud
	ProgressSim.pop_pending()
	await _shot("hud_misiones", 60)
	hud.guide_panel.toggle_collapsed()
	await _shot("hud_misiones_plegado", 10)
	hud.guide_panel.toggle_collapsed()
	gs.money = 2000000.0
	ProgressSim.check_achievements(gs)
	hud.guide_panel._t = 1.0
	await _shot("aviso_logro", 20)
	hud.guide_panel.open_achievements()
	await _shot("logros", 20)
	hud.guide_panel.close_achievements()
	hud._show_dock("finance")
	await _shot("finanzas_deuda_heredada", 30)
	get_tree().quit()
