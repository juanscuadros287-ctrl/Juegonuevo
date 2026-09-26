extends Node
## Capturas de Contrataciones: panel (Vacantes, Postulantes, Personal) y pestaña Empleados de un edificio.
## xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 \
##     res://tests/screenshot_contrataciones.tscn -- docs/capturas/contrataciones


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _save(out: String, name: String) -> void:
	get_viewport().get_texture().get_image().save_png("%s/%s" % [out, name])
	print("captura: ", name)


func _biz(gs, type_id: String, level: int, x: float, z: float, staff: int) -> Dictionary:
	var b := ConstructionSim.make_building(gs, type_id, level, x, z, 0.0, "jugador")
	gs.add_building(b)
	for c in gs.citizens.values():
		if staff <= 0:
			break
		if not gs.is_player(c.id) and c.job_id < 0 and c.school_id < 0 and c.age_years(gs.today()) >= 18 and c.age_years(gs.today()) < 60:
			if BusinessSim.hire(gs, b, c, maxf(GovSim.min_wage(gs), BusinessSim.asked_wage(gs, c, type_id) * (0.7 if staff % 3 == 0 else 1.05))) == "":
				staff -= 1
	HiringSim.on_building_ready(gs, b)
	return b


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://"
	DirAccess.make_dir_recursive_absolute(out)
	var gs = GameState
	gs.new_game({"map_type": "interior", "seed": 2024, "difficulty": "facil", "town_name": "San Rafael"})
	gs.money = 90000.0
	gs.weather["type"] = "despejado"
	var granja := _biz(gs, "granja", 2, 24.0, -22.0, 3)
	_biz(gs, "panaderia", 1, -24.0, 22.0, 1)
	var cab := _biz(gs, "caballeriza", 1, 30.0, 26.0, 1)
	_biz(gs, "central_transporte", 1, -30.0, -26.0, 2)
	LogisticsSim.buy_vehicle(gs, cab, "mula")
	LogisticsSim.buy_vehicle(gs, cab, "mula")
	LogisticsSim.buy_vehicle(gs, cab, "mula")
	HiringSim.set_wage(gs, granja, HiringSim.market_wage(gs, granja) * 1.2)
	HiringSim.set_auto(gs, cab, true, HiringSim.market_wage(gs, cab) * 1.1)
	gs.suppress_notifications = true
	TimeManager.advance_days(4)
	gs.suppress_notifications = false
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	await _frames(20)
	var hud: Hud = world.hud
	if "minimap" in world and world.minimap != null:
		world.minimap.visible = false
	for i in 3:
		hud.hiring_panel.open(i)
		await _frames(25)
		_save(out, "panel_%d_%s.png" % [i + 1, ["vacantes", "postulantes", "personal"][i]])
	hud.hiring_panel.close()
	# Otra tanda de postulantes para la ficha del edificio.
	gs.suppress_notifications = true
	TimeManager.advance_days(3)
	gs.suppress_notifications = false
	hud.open_building(int(granja["id"]))
	hud.building_panel.tabs.current_tab = 1
	await _frames(25)
	_save(out, "edificio_empleados.png")
	hud.open_building(int(cab["id"]))
	hud.building_panel.tabs.current_tab = 1
	await _frames(25)
	_save(out, "edificio_caballeriza.png")
	get_tree().quit()
