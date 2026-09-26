extends Node
## Capturas del mapa v2 (docs/capturas/mapa_v2/): Colombia con zoom máximo, región a altura media,
## municipio completo, montañas, costa, pueblo de cerca, etiquetas sin solaparse y minimapa. Imprime y
## guarda (rendimiento.txt) el tiempo de frame, llamadas de dibujo, primitivas y chunks por LOD.
## xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 \
##     res://tests/screenshot_mapa_v2.tscn -- docs/capturas/mapa_v2 [solo_una]

var out := "user://"
var only := ""
var perf_lines: Array = []


func _set_cam(rig: CameraRig, pos: Vector3, dist: float, yaw: float) -> void:
	rig.target_pos = pos
	rig.position = pos
	rig.distance = dist
	rig.target_distance = dist
	rig.yaw = yaw
	rig.target_yaw = yaw


## Espera a que no queden mallas pendientes (o se acabe el tiempo).
func _settle(t: Terrain, max_ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	var calm := 0
	while Time.get_ticks_msec() - t0 < max_ms:
		await get_tree().process_frame
		var busy := not t._jobs.is_empty() or not t._ready_results.is_empty() or t._detail_pending > 0
		for k in t.tiles:
			if t.tiles[k]["mi"] == null:
				busy = true
				break
		calm = 0 if busy else calm + 1
		if calm > 25:
			break


func _shot(world: Node, t: Terrain, name: String, max_ms := 90000) -> void:
	if only != "" and only != name:
		return
	await _settle(t, max_ms)
	# Rendimiento: 12 frames medidos.
	var t0 := Time.get_ticks_usec()
	for i in range(12):
		await get_tree().process_frame
	var ms := (Time.get_ticks_usec() - t0) / 12000.0
	var dc := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var prim := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var rig: CameraRig = world.camera_rig
	var line := "%-16s cámara %6.0f m | %5.0f ms/frame | %5d draw calls | %6.2f M prim | alta %d, media %d, media-baja %d | cálculo en hilos acumulado %.0f ms" % [
		name, rig.distance, ms, dc, prim / 1e6, t.stats["high"], t.stats["mid"], t.stats.get("low", 0), t.stats["job_ms"]]
	print(line)
	perf_lines.append(line)
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("captura: %s.png" % name)


func _zone_named(g: CountryGen, part: String) -> Dictionary:
	for z in g.zones:
		if bool(z["town"]) and MunicipalSim.name_of(GameState, int(z["id"])).contains(part):
			return z
	return {}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "user://"
	only = args[1] if args.size() > 1 else ""
	DirAccess.make_dir_recursive_absolute(out)
	var gs = GameState
	gs.new_game({"map_type": "interior", "seed": 2024, "difficulty": "facil", "country_id": "COL", "town_name": "San Rafael"})
	gs.suppress_notifications = true
	gs.money = 2000000.0
	gs.weather["type"] = "despejado"
	var g := MapSim.gen(gs)
	var nb: Array = g.zones[0]["neighbors"]
	for i in range(mini(3, nb.size())):
		MapSim.reveal_zone(gs, int(nb[i]))
	var towns: Array = gs.trade.get("towns", [])
	if not towns.is_empty():
		gs.trade["connections"] = [{"town_id": str(towns[0]["id"])}]
		MapSim.daily(gs)
	TimeManager.total_hours += 10 - TimeManager.hour()
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	var rig: CameraRig = world.camera_rig
	var t: Terrain = world.terrain
	world.minimap.visible = false
	var rl := "textura de ríos reconstruida en %.0f ms" % float(t.get("river_ms") if t.get("river_ms") != null else 0.0)
	print(rl)
	perf_lines.append(rl)
	# 1) Colombia completa con zoom máximo.
	var b := rig.frame
	_set_cam(rig, Vector3(b.get_center().x, 0, b.get_center().y), rig.max_dist, 0.0)
	await _shot(world, t, "colombia_completa", 240000)
	# 2) Región a altura media (2,5 km) sobre tu municipio.
	var z0: Dictionary = g.zones[0]
	var c0: Vector2 = z0["centroid"]
	_set_cam(rig, Vector3(c0.x * 0.5, 0, c0.y * 0.5 + 900.0), 2500.0, 25.0)
	await _shot(world, t, "region_media")
	# 3) Municipio completo (≈ 6 km).
	_set_cam(rig, Vector3(c0.x, 0, c0.y), 6000.0, 10.0)
	await _shot(world, t, "zona_completa")
	# 4) Montañas y nieve (Andes) y costa con arena y agua por profundidad.
	var zm := _zone_named(g, "Manizales")
	if zm.is_empty():
		zm = _zone_named(g, "Pereira")
	if not zm.is_empty():
		var pm: Vector2 = zm["town_pos"]
		_set_cam(rig, Vector3(pm.x, 0, pm.y), 7000.0, 0.0)
		await _shot(world, t, "montanas")
	var zc := _zone_named(g, "Barranquilla")
	if not zc.is_empty():
		var pc: Vector2 = zc["town_pos"]
		_set_cam(rig, Vector3(pc.x, 0, pc.y + 1500.0), 9000.0, 0.0)
		await _shot(world, t, "costa")
	# 5) Etiquetas de pueblos que antes se encimaban (San Vicente del Caguán / San José del Guaviare).
	var zl := _zone_named(g, "Caguán")
	if not zl.is_empty():
		var pl: Vector2 = zl["town_pos"]
		_set_cam(rig, Vector3(pl.x + 1500.0, 0, pl.y), 16000.0, 0.0)
		await _shot(world, t, "etiquetas_pais")
	# 6) Pueblo de cerca y etiquetas del pueblo (bodega, yacimientos).
	_set_cam(rig, Vector3(0, 0, 0), 150.0, 35.0)
	await _shot(world, t, "pueblo_cerca")
	_set_cam(rig, Vector3(20, 0, 20), 300.0, 35.0)
	await _shot(world, t, "etiquetas_pueblo")
	# 7) Minimapa con el HUD.
	world.minimap.visible = true
	_set_cam(rig, Vector3(0, 0, 0), 110.0, 35.0)
	await _shot(world, t, "minimapa")
	if only == "":
		var f := FileAccess.open("%s/rendimiento.txt" % out, FileAccess.WRITE)
		if f:
			f.store_string("\n".join(perf_lines) + "\n")
	get_tree().quit()
