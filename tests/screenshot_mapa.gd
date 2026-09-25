extends Node
## Capturas de la Fase 9A/9B: país completo con zoom máximo (municipio del jugador y algunos vecinos
## explorados, el resto bajo el velo translúcido, nombres visibles), un municipio desde altura media y el
## mapa ampliado con la capa de propiedad.
## xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 res://tests/screenshot_mapa.tscn -- <carpeta>


func _wait_streaming(t: Terrain, frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame
		var pending := false
		for k in t.tiles:
			if t.tiles[k]["mi"] == null or bool(t.tiles[k]["busy"]):
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
	var only := args[1] if args.size() > 1 else ""
	var gs = GameState
	gs.new_game({"map_type": "rio", "seed": 2024, "difficulty": "facil", "country_id": "andoria", "town_name": "San Rafael"})
	gs.suppress_notifications = true
	gs.money = 2000000.0
	gs.weather["type"] = "despejado"
	# Dos municipios vecinos explorados y una ruta comercial abierta (revela el municipio del pueblo).
	var g := MapSim.gen(gs)
	var nb: Array = g.zones[0]["neighbors"]
	for i in range(mini(2, nb.size())):
		MapSim.reveal_zone(gs, int(nb[i]))
	var towns: Array = gs.trade.get("towns", [])
	if not towns.is_empty():
		gs.trade["connections"] = [{"town_id": str(towns[0]["id"])}]
		MapSim.daily(gs)
	for zx in [5, 6]:
		ConstructionSim.unlock_zone(gs, zx, 2)
	# Un territorio comprado al Estado cerca del pueblo (capa de propiedad).
	LandSim.buy_from_state(gs, 2, 1)
	TimeManager.total_hours += 10 - TimeManager.hour()
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	var rig: CameraRig = world.camera_rig
	var t: Terrain = world.terrain
	world.minimap.visible = false
	if only == "nowater":
		t.water.visible = false
		only = "pais"
	# 1) País completo con zoom máximo, encuadrado.
	var b := t.country_rect_m()
	_set_cam(rig, Vector3(b.get_center().x, 0, b.get_center().y), rig.max_dist, 0.0)
	var t0 := Time.get_ticks_msec()
	await _wait_streaming(t, 1500)
	print("capa lejana completa en %d ms (%d teselas)" % [Time.get_ticks_msec() - t0, t.tiles.size()])
	for i in range(20):
		await get_tree().process_frame
	if only == "" or only == "pais":
		get_viewport().get_texture().get_image().save_png("%s/pais_completo.png" % out)
		print("captura: pais_completo.png (cámara a %.0f m, %d chunks)" % [rig.distance, t.chunks.size()])
	# 2) Un municipio completo desde altura media (el pueblo es un punto dentro de una región grande).
	var z: Dictionary = g.zones[int(gs.map["town_assign"].get(str(towns[0]["id"]), 0))] if not towns.is_empty() else g.zones[0]
	var c: Vector2 = z["centroid"]
	_set_cam(rig, Vector3(c.x, 0, c.y), 5200.0, 15.0)
	for i in range(200):
		await get_tree().process_frame
	if only == "" or only == "municipio":
		get_viewport().get_texture().get_image().save_png("%s/municipio.png" % out)
		print("captura: municipio.png (%s)" % MunicipalSim.name_of(gs, int(z["id"])))
	# 3) Mapa ampliado con la capa de propiedad.
	world.minimap.visible = true
	_set_cam(rig, Vector3.ZERO, 120.0, 35.0)
	world.minimap.set_expanded(true)
	world.minimap.set_owner_layer(true)
	world.minimap._select(Vector2i(4, 1))
	for i in range(60):
		await get_tree().process_frame
	if only == "" or only == "propiedad":
		get_viewport().get_texture().get_image().save_png("%s/propiedad.png" % out)
		print("captura: propiedad.png")
	get_tree().quit()
