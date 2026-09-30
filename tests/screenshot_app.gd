extends Node
## Capturas de la app: pantalla principal con ranuras, menú de pausa con guardar y barra superior.
## xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 tests/screenshot_app.tscn -- docs/capturas/app
## Usa una carpeta de ranuras propia (no toca las partidas reales).

var out := "user://"
var base := ""


func _shot(name: String, frames := 30) -> void:
	for i in range(frames):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("captura: ", name)


func _thumb(hud: CanvasLayer) -> void:
	hud.visible = false
	for i in range(3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	hud.visible = true
	img.resize(SaveManager.THUMB_SIZE.x, SaveManager.THUMB_SIZE.y, Image.INTERPOLATE_LANCZOS)
	SaveManager.thumbnail_png = img.save_png_to_buffer()


func _make_slot(slot: int, opts: Dictionary, days: int, cam_yaw: float, play_min: float, name := "") -> void:
	SaveManager.begin_slot(slot)
	GameState.new_game(opts)
	GameState.money += 20000.0
	ConstructionSim.start_construction(GameState, "granja", 30, -8, 0.3, "Granja")
	ConstructionSim.start_construction(GameState, "taberna", -10, 34, 2.0, "Taberna")
	TimeManager.advance_days(days)
	TimeManager.total_hours += 11 - TimeManager.hour()
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	TimeManager.set_speed(0)
	await get_tree().process_frame
	var cam: CameraRig = world.camera_rig
	cam.yaw += rad_to_deg(cam_yaw)
	cam.target_yaw = cam.yaw
	for i in range(40):
		await get_tree().process_frame
	await _thumb(world.hud)
	SaveManager.play_seconds = play_min * 60.0
	SaveManager.save_slot(slot)
	if name != "":
		SaveManager.rename_slot(slot, name)
	world.queue_free()
	await get_tree().process_frame


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "user://"
	DirAccess.make_dir_recursive_absolute(out)
	base = "user://capturas_app_%d/" % OS.get_process_id()
	SaveManager.use_dirs(base + "slots", base + "saves")
	get_window().size = Vector2i(1600, 900)
	await _make_slot(1, {"seed": 77, "difficulty": "facil", "town_name": "San Rafael", "player_name": "Sebastián", "player_surname": "Cuadros", "country_id": "COL"}, 420, 0.0, 754.0, "Mi dinastía")
	await _make_slot(3, {"seed": 12, "difficulty": "normal", "town_name": "Villa del Río", "player_name": "Lucía", "player_surname": "Gómez", "player_gender": "F", "country_id": "COL", "map_type": "costa"}, 200, 1.2, 95.0)
	await _make_slot(4, {"seed": 5, "difficulty": "dificil", "town_name": "Peñas Altas", "player_name": "Mateo", "player_surname": "Rojas", "country_id": "COL", "map_type": "montana"}, 90, -0.8, 31.0)
	SaveManager.active_slot = 0
	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	add_child(menu)
	await _shot("pantalla_principal", 60)
	menu._new_in(1)
	await _shot("confirmar_nueva", 20)
	menu.queue_free()
	await get_tree().process_frame
	# En el juego: menú de pausa y barra superior (con Fase 10: país visible).
	SaveManager.load_slot(1)
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	TimeManager.set_speed(0)
	var hud: Hud = world.hud
	await _shot("barra_1600", 45)
	hud._open_pause()
	await hud._save_now()
	await _shot("menu_pausa", 20)
	hud._close_pause()
	get_window().size = Vector2i(1280, 720)
	await _shot("barra_1280", 45)
	print("nivel de la barra a 1280: ", hud._bar_level)
	get_window().size = Vector2i(1600, 900)
	await get_tree().process_frame
	world.queue_free()
	await get_tree().process_frame
	for i in range(1, 6):
		SaveManager.delete_slot(i)
	for f in DirAccess.get_files_at(base + "slots/"):
		DirAccess.remove_absolute(base + "slots/" + f)
	DirAccess.remove_absolute(base + "slots")
	DirAccess.remove_absolute(base + "saves")
	DirAccess.remove_absolute(base)
	get_tree().quit()
