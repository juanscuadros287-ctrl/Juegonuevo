extends Node
## Capturas del sistema gráfico (docs/GRAFICOS.md): pueblo de día, atardecer y noche, interior de
## una casa, zona industrial (carreteras, rieles y mina) y una vista media con río y vegetación.
## También mide el tiempo de frame promedio en cada vista (orientativo con xvfb).
## xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 res://tests/screenshot_graficos.tscn -- <carpeta> <prefijo> [calidad]

var out := "user://"
var prefix := "g"
var world: Node3D
var rig: CameraRig
var perf := []


func _pv(arr: Array) -> PackedVector2Array:
	var o := PackedVector2Array()
	for a in arr:
		o.append(Vector2(float(a[0]), float(a[1])))
	return o


func _place(type_id: String, x: float, z: float, rot := 0.0, level := 1, tier := "normal") -> Dictionary:
	var b: Dictionary = ConstructionSim.make_building(GameState, type_id, level, x, z, rot, "jugador")
	if tier != "normal":
		b["tier"] = tier
	GameState.add_building(b)
	return b


func _set_hour(h: float) -> void:
	TimeManager.total_hours += int(floor(h)) - TimeManager.hour()
	TimeManager.hour_fraction = h - floor(h)


func _cam(pos: Vector3, dist: float, yaw: float) -> void:
	rig.follow = null
	rig.target_pos = pos
	rig.position = pos
	rig.distance = dist
	rig.target_distance = dist
	rig.yaw = yaw
	rig.target_yaw = yaw


func _shot(name: String, frames := 45) -> void:
	for i in range(frames):
		await get_tree().process_frame
	# Tiempo de frame promedio (20 frames) y carga de la escena (llamadas de dibujo, objetos, primitivas).
	var t0 := Time.get_ticks_usec()
	for i in range(20):
		await get_tree().process_frame
	var ms := float(Time.get_ticks_usec() - t0) / 20000.0
	var calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var objs := int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var prims := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	perf.append("%s: %.1f ms/frame (~%.0f FPS) · %d draw calls · %d objetos · %d primitivas · %d nodos" % [name, ms, 1000.0 / maxf(ms, 0.01), calls, objs, prims, nodes])
	get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [out, prefix, name])
	print("captura: %s_%s.png  %.1f ms/frame" % [prefix, name, ms])


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "user://"
	prefix = args[1] if args.size() > 1 else "g"
	var gs = GameState
	gs.new_game({"map_type": "rio", "seed": 2024, "difficulty": "facil"})
	gs.suppress_notifications = true
	gs.money = 900000.0
	gs.weather["type"] = "despejado"
	gs.research["era"] = 3
	for t in ["carretas", "caminos_empedrados", "maquina_vapor", "ferrocarril", "automovil", "transporte_publico", "polvora"]:
		if not gs.techs.has(t):
			gs.techs.append(t)
	gs.unlocked_zones = []
	for x in range(gs.ZONE_GRID):
		for y in range(gs.ZONE_GRID):
			gs.unlocked_zones.append([x, y])
	# Viviendas de varias épocas y calidades alrededor de la plaza.
	var homes := [[1, "normal", -18, 12, 0.3], [1, "media", -12, 20, 0.8], [2, "normal", 16, 14, 2.6], [2, "alta", 22, 4, 2.0],
			[3, "normal", -20, -8, 1.3], [3, "media", 12, -18, 3.4], [4, "normal", -30, 24, 0.5], [2, "media", 4, 24, 3.1],
			[1, "alta", -6, -22, 0.2], [5, "normal", 36, -26, 0.9]]
	var alta := {}
	for h in homes:
		var b := _place("vivienda", h[2], h[3], h[4], h[0], h[1])
		if h[0] == 2 and h[1] == "alta":
			alta = b
	_place("taberna", -26, -2, 1.4)
	_place("tienda", 24, -8, 4.0)
	_place("panaderia", 8, 16, 3.3)
	_place("iglesia", 0, -16, 0.0)
	_place("banco", -10, 30, 3.0, 2)
	_place("oficina", 30, 18, 2.4, 2)
	# Zona industrial al oeste: almacén, fábricas, central y depósito de camiones.
	_place("almacen", -54, -10, 0.0, 2)
	_place("siderurgica", -66, 8, 1.57)
	_place("aserradero", -46, 12, 0.2)
	_place("central_carbon", -74, -24, 0.0)
	_place("deposito_camiones", -44, -28, 0.4)
	# Carreteras: cemento por el pueblo hacia la zona industrial y una rama empedrada.
	TransitSim.build_road(gs, _pv([[-8, 0], [-30, 6], [-48, 0], [-62, -6], [-80, -8]]), "cemento")
	TransitSim.build_road(gs, _pv([[8, 2], [26, 10], [40, 28]]), "empedrado")
	TransitSim.build_road(gs, _pv([[-48, 0], [-50, -18], [-44, -34]]), "barro")
	var tid := str(TradeSim.towns(gs)[0]["id"])
	TransitSim.set_trade_path(gs, tid, _pv([[-9, 4], [-40, 26], [-80, 20], [-130, 48], [-199, 40]]))
	TimeManager.advance_days(int(TradeSim.project(gs, tid).get("total_days", 40)) + 1)
	_place("estacion_tren", -30, -40, 0.3)
	TransitSim.set_trade_path(gs, tid, _pv([[-32, -48], [-60, -52], [-100, -40], [-150, -44], [-199, -30]]), true)
	TimeManager.advance_days(int(TradeSim.connection(gs, tid)["work"]["rail"]["done_day"]) - gs.today() + 1)
	for i in range(8):
		gs.money = 900000.0
		TimeManager.advance_days(1)
	gs.weather["type"] = "despejado"
	gs.season = "primavera"
	world = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	rig = world.camera_rig
	var terrain: Terrain = world.terrain
	TransitVisuals.instance.rebuild()
	# Mina de hierro sobre un yacimiento en terreno seco cerca de la zona industrial.
	var spot := Vector2(-90, 30)
	var best := INF
	for x in range(-130, -60, 4):
		for z in range(-10, 60, 4):
			if terrain.footprint_ok(x, z, 24.0) == "" and terrain.is_land(x, z, 1.0) and Vector2(x + 90, z - 30).length() < best:
				best = Vector2(x + 90, z - 30).length()
				spot = Vector2(x, z)
	gs.logistics["deposits"] = [{"id": 1, "type": "hierro", "x": spot.x, "z": spot.y, "amount": 14000.0, "initial": 14000.0, "grade": 1.1}]
	MineSim.ensure_area(gs.logistics["deposits"][0])
	var d: Dictionary = gs.logistics["deposits"][0]
	var c := spot + Vector2(-6, 4)
	var r := ConstructionSim.start_construction(gs, "mina_hierro", c.x, c.y, 0.3, "Mina La Colorada", "sas")
	var mine: Dictionary = r.get("building", {})
	if not mine.is_empty():
		mine["status"] = "activo"
		mine["level"] = 2
		mine["target_level"] = 2
		for p in [["tajo", 0.2, 0.62, 0.0], ["socavon", -1.9, 0.62, 2.6], ["torre_extraccion", 1.9, 0.6, -0.5]]:
			var ang := float(p[1])
			var pos := Vector2(float(d["x"]), float(d["z"])) + Vector2.from_angle(ang) * MineSim.radius_at(d, ang) * float(p[2])
			MineSim.add_part(gs, mine, str(p[0]), pos.x, pos.y, float(p[3]))
		for part in MineSim.parts(mine):
			part["status"] = "activo"
		EventBus.building_changed.emit(int(mine["id"]))
		MiningVisuals.instance.rebuild_all()
	world.hud.visible = true
	TimeManager.set_speed(0)
	var plaza := Vector3(0, terrain.height_at(0, 0), 0)
	var rapido := args.size() > 2 and args[2] == "rapido"
	# 1) Pueblo de día.
	_set_hour(10.0)
	_cam(plaza, 62.0, 35.0)
	await _shot("pueblo_dia")
	# 2) Atardecer y noche.
	_set_hour(17.35)
	_cam(plaza, 62.0, 200.0)
	await _shot("pueblo_atardecer")
	_set_hour(21.5)
	_cam(plaza, 55.0, 35.0)
	await _shot("pueblo_noche")
	if rapido:
		print("RENDIMIENTO rapido (%s):" % prefix)
		for l in perf:
			print("  " + l)
		get_tree().quit()
		return
	# 3) Zona industrial con carreteras, rieles y mina.
	_set_hour(11.0)
	_cam(Vector3(-62, terrain.height_at(-62, -10), -10), 85.0, 20.0)
	await _shot("industrial")
	if not mine.is_empty():
		_cam(Vector3(float(d["x"]), terrain.height_at(float(d["x"]), float(d["z"])), float(d["z"])), 45.0, 205.0)
		await _shot("mina")
	# 4) Vista media con río y vegetación: busca agua cerca del pueblo.
	var river := Vector3(90, 0, 0)
	var rbest := INF
	for x in range(-180, 180, 6):
		for z in range(-180, 180, 6):
			if terrain.height_at(x, z) < terrain.water_level - 0.3:
				var dd := Vector2(x, z).length()
				if dd < rbest and dd > 50.0:
					rbest = dd
					river = Vector3(x, 0, z)
	river.y = terrain.water_level
	_cam(river, 48.0, 120.0)
	await _shot("rio_vegetacion")
	_cam(river + Vector3(-10, 0, 10), 22.0, 300.0)
	await _shot("rio_cerca")
	# 5) Interior de una casa.
	_set_hour(10.0)
	if not alta.is_empty():
		for cz in gs.citizens.values().slice(0, 3):
			cz.home_id = int(alta["id"])
		EventBus.interior_requested.emit(int(alta["id"]))
		await _shot("interior")
	print("RENDIMIENTO (%s, %s):" % [prefix, RenderingServer.get_video_adapter_name()])
	for l in perf:
		print("  " + l)
	var f := FileAccess.open("%s/%s_rendimiento.txt" % [out, prefix], FileAccess.WRITE)
	if f:
		f.store_string("\n".join(perf) + "\n")
	get_tree().quit()
