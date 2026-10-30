extends Node
## Capturas de Ventas y distribución: panel (Productos, Sucursales, Distribuidora, Clientes) y la Distribuidora en 3D.
## xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 \
##     res://tests/screenshot_distribucion.tscn -- docs/capturas/distribucion

const GOOD := "velas_jabon"


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _save(out: String, name: String) -> void:
	get_viewport().get_texture().get_image().save_png("%s/%s" % [out, name])
	print("captura: ", name)


func _biz(gs, type_id: String, level: int, x: float, z: float, staff: int) -> Dictionary:
	var b := ConstructionSim.make_building(gs, type_id, level, x, z, 0.0, "jugador")
	b["status"] = "activo"
	gs.add_building(b)
	for c in BusinessSim.candidates(gs, b):
		if staff <= 0:
			break
		if BusinessSim.hire(gs, b, c, maxf(GovSim.min_wage(gs), BusinessSim.asked_wage(gs, c, type_id))) == "":
			staff -= 1
	return b


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://"
	DirAccess.make_dir_recursive_absolute(out)
	var gs = GameState
	gs.new_game({"map_type": "interior", "seed": 2024, "difficulty": "facil", "town_name": "San Rafael"})
	gs.money = 90000.0
	gs.weather["type"] = "despejado"
	gs.suppress_notifications = true
	TimeManager.advance_days(40)
	# Una tienda NPC del pueblo.
	for c in gs.citizens.values():
		if not gs.is_player(c.id) and c.job_id < 0 and c.age_years(gs.today()) >= 25 and c.age_years(gs.today()) <= 50 and not NpcBusinessSim._player_family(gs, c):
			c.skills["comercio"] = 60.0
			c.money = 3000.0
			var st := NpcBusinessSim.open_business(gs, c, "tienda", 26.0, -26.0, 0.0)
			for i in range(40):
				if str(st.get("status", "")) == "activo":
					break
				TimeManager.advance_days(1)
			st["reserve"] = 600.0
			break
	_biz(gs, "veleria", 1, 40.0, 30.0, 2)
	_biz(gs, "carpinteria", 1, 46.0, 14.0, 2)
	var dist := _biz(gs, "distribuidora", 1, -22.0, -30.0, 3)
	_biz(gs, "central_transporte", 1, -40.0, 40.0, 4)
	WarehouseSim.relink_all(gs)
	WarehouseSim.add(gs, GOOD, 180.0)
	WarehouseSim.add(gs, "muebles", 25.0)
	var best := ""
	var best_d := INF
	for t in TradeSim.towns(gs):
		if float(t["distance"]) < best_d:
			best_d = float(t["distance"])
			best = str(t["id"])
	TradeSim.open_route(gs, best)
	TimeManager.advance_days(int(TradeSim.project(gs, best).get("total_days", 30)) + 1)
	DistributionSim.open_branch(gs, best)
	DistributionSim.set_enabled(gs, GOOD, "exportacion", true)
	for m in range(2):
		WarehouseSim.add(gs, GOOD, 90.0)
		TimeManager.advance_days(30)
	WarehouseSim.add(gs, GOOD, 60.0)
	TimeManager.advance_days(12)
	TimeManager.total_hours += 10 - TimeManager.hour()
	gs.suppress_notifications = false
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	await _frames(20)
	var hud: Hud = world.hud
	if "minimap" in world and world.minimap != null:
		world.minimap.visible = false
	hud._show_dock("distribution")
	var p: DistributionPanel = hud.distribution_panel
	p.sel_good = GOOD
	var names := {"productos": "panel_1_productos.png", "sucursales": "panel_2_sucursales.png", "distribuidora": "panel_3_distribuidora.png", "clientes": "panel_4_clientes.png"}
	for t in names:
		p.set_tab(t)
		await _frames(25)
		_save(out, names[t])
	hud.close_dock()
	var rig: CameraRig = world.camera_rig
	rig.target_pos = Vector3(float(dist["x"]), 2, float(dist["z"]))
	rig.position = rig.target_pos
	rig.distance = 22.0
	rig.target_distance = 22.0
	rig.yaw = 200.0
	rig.target_yaw = 200.0
	await _frames(40)
	_save(out, "distribuidora_3d.png")
	get_tree().quit()
