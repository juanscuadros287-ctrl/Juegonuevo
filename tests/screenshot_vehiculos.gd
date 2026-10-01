extends Node
## Capturas de la variedad de vehículos (docs/VEHICULOS.md): galería de todos los modelos y vagones con su
## diseño propio, y la ficha comparativa del panel de compra.
## xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 res://tests/screenshot_vehiculos.tscn -- <ruta absoluta>/docs/capturas/vehiculos

var gs = GameState
var out := "user://"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "user://"
	gs.new_game({"map_type": "costa", "seed": 5, "difficulty": "facil"})
	gs.suppress_notifications = true
	gs.money = 5000000.0
	var land := []
	var rail := []
	var water_air := []
	for g in VehicleCatalog.gear_ids():
		land.append(["pie_" + str(g), "Cargador: " + str(VehicleCatalog.gear_def(str(g)).get("label", g))])
	for tipo in ["animal", "carreta", "camion"]:
		for m in VehicleCatalog.models(null, tipo, true):
			land.append([str(m["id"]), str(m["label"])])
	for m in VehicleCatalog.models(null, "tren", true):
		rail.append([str(m["id"]), str(m["label"])])
	for wt in VehicleCatalog.wagon_ids(null, true):
		rail.append([str(wt), "Vagón " + VehicleCatalog.wagon_label(str(wt)).to_lower()])
	for tipo in ["barco", "avion"]:
		for m in VehicleCatalog.models(null, tipo, true):
			water_air.append([str(m["id"]), str(m["label"])])
	await _gallery("galeria_terrestres.png", land, 6, 7.5, 6.5)
	await _gallery("galeria_trenes_vagones.png", rail, 6, 8.0, 10.0)
	await _gallery("galeria_barcos_aviones.png", water_air, 4, 30.0, 30.0)
	await _panel()
	get_tree().quit()


func _gallery(file: String, items: Array, cols: int, dx: float, dz: float) -> void:
	var root := Node3D.new()
	add_child(root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.36, 0.42, 0.5)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.82, 0.9)
	e.ambient_light_energy = 0.35
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 40, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.0
	root.add_child(sun)
	var rows := int(ceil(float(items.size()) / cols))
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(cols * dx + 40.0, rows * dz + 40.0)
	ground.mesh = pm
	ground.material_override = MeshLib.mat(Color(0.42, 0.5, 0.34))
	ground.position = Vector3((cols - 1) * dx * 0.5, 0, (rows - 1) * dz * 0.5)
	root.add_child(ground)
	for i in range(items.size()):
		var it: Array = items[i]
		var n := VehicleModels.node(str(it[0]))
		var p := Vector3((i % cols) * dx, 0.0, (i / cols) * dz)
		n.position = p
		n.rotation.y = deg_to_rad(-60.0)
		(n.get_node("Detail") as GeometryInstance3D).visibility_range_end = 0.0   # galería: siempre el detalle
		n.get_node("Proxy").visible = false
		root.add_child(n)
		var lab := Label3D.new()
		lab.text = str(it[1])
		lab.font_size = 50
		lab.pixel_size = dx / 900.0
		lab.outline_size = 12
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.no_depth_test = true
		lab.position = p + Vector3(0, -0.2, dz * 0.36)
		root.add_child(lab)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	root.add_child(cam)
	var center := Vector3((cols - 1) * dx * 0.5, 0, (rows - 1) * dz * 0.5 + dz * 0.02)
	cam.size = maxf(cols * dx * 0.6, rows * dz * 0.86)
	cam.far = 2000.0
	var eye := center + Vector3(0, 400.0, 330.0)
	cam.transform = Transform3D(Basis.looking_at(center - eye, Vector3.UP), eye)
	cam.make_current()
	for i in range(20):
		await get_tree().process_frame
	var path := "%s/%s" % [out, file]
	get_viewport().get_texture().get_image().save_png(path)
	print("captura guardada en ", path)
	root.queue_free()
	await get_tree().process_frame


func _panel() -> void:
	for t in ["carretas", "caminos_empedrados", "revolucion_industrial", "maquina_vapor", "ferrocarril", "automovil", "industria_automotriz", "refrigeracion",
			"acero_estructural", "era_moderna"]:
		if not gs.techs.has(t):
			gs.techs.append(t)
	var dep: Dictionary = ConstructionSim.make_building(gs, "deposito_camiones", 2, 27, -22, 0.6, "jugador")
	dep["status"] = "activo"
	gs.add_building(dep)
	TransitSim.build_road(gs, PackedVector2Array([Vector2(6, 6), Vector2(24, -8), Vector2(40, -28)]), "cemento")
	TimeManager.set_speed(0)
	var world: Node = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	for i in range(30):
		await get_tree().process_frame
	var win := RoutesWindow.open_in(world.hud, "vehicles")
	win.b_tipo = "camion"
	win.b_mode = "camion_frigorifico"
	win.b_company = int(dep["id"])
	win.show_tab("vehicles")
	for i in range(40):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/ficha_compra.png" % out)
	win.b_tipo = "tren"
	win.b_mode = "vapor_expreso"
	win.b_comp = {"tolva_acero": 2, "frigorifico": 1, "furgon_acero": 1}
	win.show_tab("vehicles")
	for i in range(40):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/ficha_tren.png" % out)
	print("capturas del panel guardadas")
