extends Node
## Capturas de rutas y barcos (docs/RUTAS_BARCOS.md): rutas de colores en el mapa, puerto con barco y
## almacén, cochera de tren conectada con un tren saliendo, panel Rutas y garaje en rojo desconectado.
## xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 res://tests/screenshot_rutas.tscn -- docs/capturas/rutas

var gs = GameState
var world: Node3D
var out := "user://"


func _pv(arr: Array) -> PackedVector2Array:
	var o := PackedVector2Array()
	for a in arr:
		o.append(Vector2(float(a[0]), float(a[1])))
	return o


func _place(type_id: String, x: float, z: float, rot := 0.0, level := 1) -> Dictionary:
	var b: Dictionary = ConstructionSim.make_building(gs, type_id, level, x, z, rot, "jugador")
	b["status"] = "activo"
	gs.add_building(b)
	WarehouseSim.relink_all(gs)
	return b


func _hire(b: Dictionary, n: int) -> void:
	var hired := 0
	for c in gs.citizens.values():
		if hired >= n:
			break
		if gs.is_player(c.id) or c.job_id >= 0 or c.age_years(gs.today()) < 18 or c.age_years(gs.today()) > 60:
			continue
		if BusinessSim.hire(gs, b, c, 3.0) == "":
			hired += 1


func _shore(near: Vector2, fp: float) -> Vector2:
	return ShipSim.find_shore(gs, near, 90.0, 3.0, "mar", fp)


## Mueve el envío de una ruta a una fracción de su primer tramo (0 = sale del garaje).
func _set_phase(route_id: int, frac: float) -> void:
	var now := float(gs.today()) + TimeManager.hour_float() / 24.0
	for s in LogisticsSim.shipments(gs):
		if int(s["route"]) == route_id:
			s["depart"] = now - float(s["travel"]) * frac


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "user://"
	gs.new_game({"map_type": "costa", "seed": 5, "difficulty": "facil"})
	gs.suppress_notifications = true
	gs.money = 5000000.0
	gs.research["era"] = 3
	for t in ["carretas", "caminos_empedrados", "navegacion", "revolucion_industrial", "maquina_vapor", "ferrocarril", "automovil", "era_moderna"]:
		gs.techs.append(t)
	gs.unlocked_zones = []
	for x in range(gs.ZONE_GRID):
		for y in range(gs.ZONE_GRID):
			gs.unlocked_zones.append([x, y])
	# Puertos en la costa con su almacén al lado, astillero en el agua.
	var p1s := _shore(Vector2(62, -40), 7.0)
	var p1 := _place("puerto", p1s.x, p1s.y, 0.0, 2)
	var w1 := _place("almacen", p1s.x - 13.0, p1s.y + 2.0)
	var p2s := _shore(Vector2(62, 75), 7.0)
	var p2 := _place("puerto", p2s.x, p2s.y, 0.0, 2)
	var ys := _shore(Vector2(62, 18), 8.0)
	var yard := _place("astillero", ys.x, ys.y, 0.0, 2)
	_hire(yard, 8)
	var sail: Dictionary = LogisticsSim.buy_vehicle(gs, yard, "velero").get("vehicle", {})
	var steam: Dictionary = LogisticsSim.buy_vehicle(gs, yard, "vapor_barco").get("vehicle", {})
	# Carretera y camiones.
	TransitSim.build_road(gs, _pv([[6, 6], [24, -8], [40, -28], [p1s.x - 22, p1s.y + 2]]), "cemento")
	var dep := _place("deposito_camiones", 18, -22, 0.6, 2)
	_hire(dep, 4)
	var truck: Dictionary = LogisticsSim.buy_vehicle(gs, dep, "camion").get("vehicle", {})
	# Vía férrea, estaciones y cochera.
	RailSim.build(gs, _pv([[-40, 58], [-58, 20], [-56, -20], [-40, -62]]))
	var sa := _place("estacion_tren", -32, 60)
	var wa := _place("almacen", -20, 62)
	var sb := _place("estacion_tren", -32, -64)
	var wb := _place("almacen", -20, -66)
	var ct := _place("cochera_tren", -48, 2, PI * 0.5)
	_hire(ct, 4)
	var train: Dictionary = LogisticsSim.buy_vehicle(gs, ct, "tren_vapor").get("vehicle", {})
	GarageSim.add_wagon(gs, int(train.get("id", -1)))
	# Cargadores a pie.
	var cen := _place("central_transporte", -14, 26)
	_hire(cen, 4)
	var wp := _place("almacen", 16, 32)
	for w in [w1, wa, wp]:
		WarehouseSim.add_to(gs, int(w["id"]), "madera", 400.0)
	WarehouseSim.add_to(gs, 0, "herramientas", 200.0)
	TimeManager.total_hours += 10 - TimeManager.hour()
	var r_ship := LogisticsSim.create_route(gs, {"from": int(w1["id"]), "to": int(p2["id"]), "good": "madera", "qty": 150, "vehicle": int(sail["id"]), "auto": true, "every": 3, "name": "Cabotaje norte"})
	var r_train := LogisticsSim.create_route(gs, {"from": int(wa["id"]), "to": int(wb["id"]), "good": "madera", "qty": 300, "vehicle": int(train["id"]), "auto": true, "every": 2, "name": "Tren de la madera"})
	var r_truck := LogisticsSim.create_route(gs, {"from": 0, "to": int(w1["id"]), "good": "herramientas", "qty": 200, "vehicle": int(truck["id"]), "auto": true, "every": 2, "name": "Camión al puerto"})
	var r_pie := LogisticsSim.create_route(gs, {"from": int(wp["id"]), "to": 0, "good": "madera", "qty": 40, "mode": "pie", "auto": true, "every": 1, "name": "Cargadores a la plaza"})
	for r in [r_ship, r_train, r_truck, r_pie]:
		if r.has("error"):
			print("ERROR ruta: ", r["error"])
	_set_phase(int(r_ship["route"]["id"]), 0.45)
	_set_phase(int(r_train["route"]["id"]), 0.06)
	_set_phase(int(r_truck["route"]["id"]), 0.5)
	_set_phase(int(r_pie["route"]["id"]), 0.4)
	TimeManager.set_speed(0)
	world = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	for i in range(30):
		await get_tree().process_frame
	# 1) Rutas de colores en el mapa.
	await _shot("rutas_mapa.png", Vector3(4, 3, 0), 190.0, 20.0)
	# 2) Puerto con barco y almacén.
	var mid := Vector2(p1s.x, p1s.y)
	await _shot("puerto_barco.png", Vector3(mid.x + 4, 2, mid.y + 20), 70.0, 60.0)
	# 3) Cochera de tren conectada y un tren saliendo.
	await _shot("cochera_tren.png", Vector3(-50, 2, 2), 48.0, 250.0)
	# 4) Panel Rutas.
	var win := RoutesWindow.open_in(world.hud)
	win.start_wizard()
	win.wizard_set("mode", "tren_vapor")
	win.wizard_set("from", int(wa["id"]))
	win.wizard_set("to", int(wb["id"]))
	win.refresh()
	await _shot("panel_rutas.png", Vector3(4, 3, 0), 190.0, 20.0)
	win.close()
	# 5) Garaje en rojo desconectado (depósito de camiones lejos de la carretera).
	var gp := Vector3(-10, 0, -40)
	gp.y = world.terrain.height_at(gp.x, gp.z)
	var ghost := MeshLib.build_model(GameData.level_def("deposito_camiones", 1).get("model", []), 1.0, MeshLib.ghost_mat(true))
	world.add_child(ghost)
	ghost.position = gp
	var gm := LogisticsVisuals.instance.placement_feedback("deposito_camiones", gp, -1, true, MeshLib.ghost_mat(true))
	world._set_ghost_mat(ghost, gm)
	world.hud.set_placement_hint("Depósito de camiones —%s" % LogisticsVisuals.instance.placement_text())
	await _shot("garaje_rojo.png", Vector3(-4, 2, -34), 55.0, 20.0)
	get_tree().quit()


func _shot(file: String, target: Vector3, dist: float, yaw: float) -> void:
	var rig: CameraRig = world.camera_rig
	rig.target_pos = target
	rig.position = target
	rig.distance = dist
	rig.target_distance = dist
	rig.yaw = yaw
	rig.target_yaw = yaw
	for i in range(45):
		await get_tree().process_frame
	var path := "%s/%s" % [out, file]
	get_viewport().get_texture().get_image().save_png(path)
	print("captura guardada en ", path)
