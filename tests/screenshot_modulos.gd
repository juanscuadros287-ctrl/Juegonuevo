extends Node
## Capturas de los módulos por edificio (docs/MODULOS.md):
##   modulos_3d.png     — fábricas con almacén integrado (anexo), patio con su flota y andén de carga;
##   modulos_mejorar.png — pestaña Mejorar con las secciones Edificio, Almacén y Parqueadero y flota.
## xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 res://tests/screenshot_modulos.tscn -- docs/capturas/modulos


func _place(type_id: String, x: float, z: float, rot := 0.0, level := 1, mods := {}) -> Dictionary:
	var b: Dictionary = ConstructionSim.make_building(GameState, type_id, level, x, z, rot, "jugador")
	if not mods.is_empty():
		b["modules"] = mods
	GameState.add_building(b)
	return b


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://"
	GameState.new_game({"map_type": "interior", "seed": 2024, "difficulty": "facil"})
	GameState.suppress_notifications = true
	GameState.money = 90000.0
	for t in ["ladrillo", "bodegas_anexas", "carretas", "maquina_vapor", "fabricas", "almacenes_industriales", "automovil", "bahias_de_carga"]:
		GameState.techs.append(t)
	var main := _place("fabrica_herramientas", 28, 20, 0.0, 3, {"almacen": 4, "parqueadero": 5})
	_place("herreria", -26, 24, 0.5, 2, {"almacen": 2, "parqueadero": 3})
	_place("tejeduria", 30, -26, 0.0, 2, {"almacen": 3, "parqueadero": 4})
	WarehouseSim.relink_all(GameState)
	WarehouseSim.add_to(GameState, int(main["id"]), "hierro", 420.0)
	WarehouseSim.add_to(GameState, int(main["id"]), "carbon", 300.0)
	WarehouseSim.add_to(GameState, int(main["id"]), "herramientas", 160.0)
	TimeManager.total_hours += 10 - TimeManager.hour()
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	var rig: CameraRig = world.camera_rig
	rig.target_pos = Vector3(26, 2, 18)
	rig.position = rig.target_pos
	rig.distance = 30.0
	rig.target_distance = 30.0
	rig.yaw = 215.0
	rig.target_yaw = 215.0
	for i in range(40):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/modulos_3d.png" % out)
	print("captura guardada en %s/modulos_3d.png" % out)
	world.hud.open_building(int(main["id"]))
	await get_tree().process_frame
	var tabs: TabContainer = world.hud.building_panel.tabs
	for i in range(tabs.get_tab_count()):
		if tabs.get_tab_title(i) == "Mejorar":
			tabs.current_tab = i
	for i in range(30):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/modulos_mejorar.png" % out)
	print("captura guardada en %s/modulos_mejorar.png" % out)
	var sc: ScrollContainer = tabs.get_current_tab_control()
	sc.scroll_vertical = 100000
	for i in range(20):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/modulos_parqueadero.png" % out)
	print("captura guardada en %s/modulos_parqueadero.png" % out)
	get_tree().quit()
