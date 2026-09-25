extends Node
## Capturas de la Fase 9A: país completo con zoom máximo (varias zonas reveladas y el resto en niebla),
## vista media de varios biomas y el minimapa ampliado.
## xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 res://tests/screenshot_mapa.tscn -- <carpeta>


func _wait_streaming(t: Terrain, frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame
		var pending := false
		for c in t.chunks:
			if t.chunks[c].get("far") == null or bool(t.chunks[c]["busy"]):
				pending = true
				break
		if not pending and i > 30:
			break


func _set_cam(rig: CameraRig, pos: Vector3, dist: float, yaw: float) -> void:
	rig.target_pos = pos
	rig.position = pos
	rig.distance = dist
	rig.target_distance = dist
	rig.yaw = yaw
	rig.target_yaw = yaw


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://"
	var gs = GameState
	gs.new_game({"map_type": "rio", "seed": 2024, "difficulty": "facil", "country_id": "andoria", "town_name": "San Rafael"})
	gs.suppress_notifications = true
	gs.money = 500000.0
	gs.weather["type"] = "despejado"
	# Varias zonas reveladas: expediciones al norte y al sur, y una ruta comercial abierta.
	for p in [Vector2(-1600, -1200), Vector2(1200, 2000), Vector2(-3200, 1600), Vector2(2800, -2400)]:
		MapSim.reveal_around(gs, p, 700.0)
	var towns: Array = gs.trade.get("towns", [])
	if not towns.is_empty():
		gs.trade["connections"] = [{"town_id": str(towns[0]["id"])}]
		MapSim.daily(gs)
	for zx in [5, 6]:
		ConstructionSim.unlock_zone(gs, zx, 2)
	TimeManager.total_hours += 10 - TimeManager.hour()
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	var rig: CameraRig = world.camera_rig
	var t: Terrain = world.terrain
	# 1) País completo con zoom máximo.
	rig.view_country()
	_set_cam(rig, rig.target_pos, rig.max_dist, 0.0)
	await _wait_streaming(t, 900)
	for i in range(20):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/pais_zoom_maximo.png" % out)
	print("captura: pais_zoom_maximo.png (cámara a %.0f m, %d chunks)" % [rig.distance, t.chunks.size()])
	# 2) Vista media de varios biomas (cordillera, valle con río, bosque).
	_set_cam(rig, Vector3(-1100, 0, -900), 1500.0, 20.0)
	for i in range(240):
		await get_tree().process_frame
		if t.stats["high"] + t.stats["mid"] >= 12 and i > 60:
			break
	for i in range(30):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/pais_biomas.png" % out)
	print("captura: pais_biomas.png (alta %d, media %d)" % [t.stats["high"], t.stats["mid"]])
	# 3) Minimapa ampliado sobre la vista del pueblo.
	_set_cam(rig, Vector3.ZERO, 120.0, 35.0)
	world.minimap.set_expanded(true)
	world.minimap._select(Vector2i(2, -1))   # territorio sin explorar: costo y días de la expedición
	for i in range(60):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/minimapa.png" % out)
	print("captura: minimapa.png")
	get_tree().quit()
