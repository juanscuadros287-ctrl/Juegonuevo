extends Node
## Capturas de la Fase 10: mapa mundial con presencia (viaje y carga aérea en vuelo), panel Aviación,
## avión de carga en ruta entre dos aeropuertos (3D) y vista remota de otro país.
## xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 res://tests/screenshot_fase10.tscn -- <carpeta>


func _set_cam(rig: CameraRig, pos: Vector3, dist: float, yaw: float) -> void:
	rig.target_pos = pos
	rig.position = pos
	rig.distance = dist
	rig.target_distance = dist
	rig.yaw = yaw
	rig.target_yaw = yaw


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _biz(gs, type_id: String, x: float, z: float, staff: int) -> Dictionary:
	var b := ConstructionSim.make_building(gs, type_id, 1, x, z, 0.0, "jugador")
	b["status"] = "activo"
	gs.add_building(b)
	for c in gs.citizens.values():
		if staff <= 0:
			break
		if not gs.is_player(c.id) and c.job_id < 0 and c.age_years(gs.today()) >= 18 and c.age_years(gs.today()) < 60:
			BusinessSim.hire(gs, b, c, 3.0)
			staff -= 1
	return b


func _plane(out: String, world: Node3D, a: Dictionary, a2: Dictionary, travel: float) -> void:
	var rig: CameraRig = world.camera_rig
	var pa := Vector2(float(a["x"]), float(a["z"]))
	var pb := Vector2(float(a2["x"]), float(a2["z"]))
	var mid := pa.lerp(pb, 0.45)
	var lv: LogisticsVisuals = null
	for ch in world.get_children():
		if ch is LogisticsVisuals:
			lv = ch
	await _frames(40)
	print("aeropuertos en 3D: %s %s · agentes de transporte: %d · envíos: %d" % [world.building_nodes.has(int(a["id"])), world.building_nodes.has(int(a2["id"])),
			lv._agents.size() if lv != null else -1, LogisticsSim.shipments(GameState).size()])
	_set_cam(rig, Vector3(mid.x, 20.0, mid.y), 170.0, 225.0)
	await _frames(90)
	_save(out, "avion_en_ruta.png")


func _save(out: String, name: String) -> void:
	get_viewport().get_texture().get_image().save_png("%s/%s" % [out, name])
	print("captura: ", name)


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://"
	var only := args[1] if args.size() > 1 else ""
	var gs = GameState
	gs.new_game({"map_type": "interior", "seed": 2024, "difficulty": "facil", "country_id": "COL", "town_name": "San Rafael"})
	gs.suppress_notifications = true
	gs.money = 3000000.0
	gs.weather["type"] = "despejado"
	for t in ["aviacion", "aeronautica", "automovil"]:
		gs.techs.append(t)
	TechSim._recompute_mods(gs)
	# Presencia en Perú y México, licencia en Chile.
	for iso in ["PER", "MEX"]:
		CountriesSim.buy_license(gs, iso)
		CountriesSim.buy_entry_land(gs, iso)
		ManagerSim.hire(gs, iso, int(ManagerSim.candidates(gs, iso)[0]["citizen_id"]))
	CountriesSim.buy_license(gs, "CHL")
	ManagerSim.hire(gs, "COL", int(ManagerSim.candidates(gs, "COL")[0]["citizen_id"]))
	# Aeropuertos, hangar y aviones.
	gs.unlocked_zones.append([4, 4])
	gs.unlocked_zones.append([0, 0])
	var a := _biz(gs, "aeropuerto", 150.0, 150.0, 3)
	var a2 := _biz(gs, "aeropuerto", -150.0, -150.0, 3)
	var h := _biz(gs, "hangar", 150.0, 118.0, 4)
	for i in range(3):
		LogisticsSim.buy_vehicle(gs, h, "avion")
	var per_ap = CountriesSim.with_country(gs, "PER", func(): return int(_biz(gs, "aeropuerto", 60.0, 60.0, 3)["id"]))
	var mex_ap = CountriesSim.with_country(gs, "MEX", func(): return int(_biz(gs, "aeropuerto", 60.0, 60.0, 3)["id"]))
	WarehouseSim.add_to(gs, int(a["id"]), "madera", 900.0)
	WarehouseSim.add_to(gs, 0, "madera", 150.0)
	AirSim.ship(gs, {"from_iso": "COL", "from": int(a["id"]), "to_iso": "PER", "to": per_ap, "good": "madera", "qty": 300.0, "mode": "avion"})
	AirSim.ship(gs, {"from_iso": "COL", "from": int(a["id"]), "to_iso": "MEX", "to": mex_ap, "good": "madera", "qty": 300.0, "mode": "avion"})
	AirSim.ship(gs, {"from_iso": "COL", "from": 0, "to_iso": "MEX", "to": mex_ap, "good": "madera", "qty": 120.0, "mode": "comercial"})
	AirSim.create_route(gs, {"from_iso": "COL", "from": int(a["id"]), "to_iso": "PER", "to": per_ap, "good": "madera", "qty": 200.0, "mode": "avion", "every": 10})
	TravelSim.start(gs, "PER")
	TimeManager.advance_days(2)
	# Avión propio entre dos aeropuertos de Colombia, a mitad de vuelo.
	var free := -1
	for v in LogisticsSim.vehicles(gs):
		if not LogisticsSim.vehicle_busy(gs, int(v["id"]), float(gs.today()) + 0.3):
			free = int(v["id"])
	WarehouseSim.add_to(gs, int(a["id"]), "madera", 300.0)
	TimeManager.total_hours = gs.today() * 24 + 7
	TimeManager.hour_fraction = 0.0
	# Carga aérea en vuelo hacia México (se ve en el mapa mundial).
	WarehouseSim.add_to(gs, 0, "madera", 100.0)
	AirSim.ship(gs, {"from_iso": "COL", "from": 0, "to_iso": "MEX", "to": mex_ap, "good": "madera", "qty": 100.0, "mode": "comercial"})
	for f in AirSim.st(gs)["flights"]:
		if not bool(f["delivered"]):
			f["depart"] = gs.today() - 1   # que se vea a mitad del trayecto
			f["arrive"] = gs.today() + 2
	var r := LogisticsSim.create_route(gs, {"from": int(a["id"]), "to": int(a2["id"]), "good": "madera", "qty": 300.0, "mode": "avion", "vehicle": free})
	print("ruta interna: ", r.get("error", "ok"))
	var travel := float(LogisticsSim.trip_info(gs, int(a["id"]), int(a2["id"]), "avion")["travel"])
	TimeManager.hour_fraction = travel * 24.0 * 0.45
	TimeManager.speed = 0

	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	await _frames(10)
	var hud: Hud = world.hud
	world.minimap.visible = false
	if only == "avion":
		await _plane(out, world, a, a2, travel)
		get_tree().quit()
		return
	# 1) Mapa mundial con presencia.
	hud.countries_window.open(0)
	hud.countries_window.map_view.select("PER")
	await _frames(30)
	_save(out, "mapa_mundial_presencia.png")
	hud.countries_window.open(1)
	await _frames(20)
	_save(out, "mis_paises.png")
	hud.countries_window.close()
	# 2) Panel Aviación.
	hud.aviation_window.open()
	await _frames(20)
	_save(out, "aviacion.png")
	hud.aviation_window.close()
	# 3) Avión en ruta (3D) entre los dos aeropuertos.
	await _plane(out, world, a, a2, travel)
	# 4) Vista remota de Perú (el mundo 3D solo dibuja el país activo).
	world.queue_free()
	await _frames(2)
	CountriesSim.set_active(gs, "PER")
	var w2: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(w2)
	await _frames(120)
	_save(out, "vista_remota_peru.png")
	get_tree().quit()
