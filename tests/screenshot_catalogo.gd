extends Node
## Captura del catálogo de bienes:
## xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 res://tests/screenshot_catalogo.tscn -- <carpeta>

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://"
	GameState.new_game({"seed": 2024, "difficulty": "normal", "map_type": "costa"})
	GameState.suppress_notifications = true
	for t in ["revolucion_industrial", "maquina_vapor", "fabricas", "carbon", "ladrillo", "metodo_cientifico", "herbolaria", "imprenta", "telares"]:
		GameState.techs.append(t)
	WarehouseSim.add(GameState, "maquinaria", 12.0)
	WarehouseSim.add(GameState, "acero", 80.0)
	var ui := Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.theme = UIKit.make_theme()
	add_child(ui)
	var catalog := GoodsCatalog.new()
	ui.add_child(catalog)
	catalog.setup()
	var shots := [["catalogo", "automovil_bien", ""]]
	for s in shots:
		catalog.open(str(s[1]))
		if str(s[2]) != "":
			catalog._set_category(str(s[2]))
			catalog.select(str(s[1]))
		for i in range(50):
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, s[0]])
	# Vitrina: todos los bienes del catálogo en 3D (materias primas → intermedios → productos → energía).
	ui.visible = false
	_showcase()
	for i in range(20):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/bienes_3d.png" % out)
	get_tree().quit()


func _showcase() -> void:
	var root := Node3D.new()
	add_child(root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.1, 0.11, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.8, 0.85)
	e.ambient_light_energy = 0.6
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var ids := GoodsCatalog.good_ids()
	var cols := 10
	var step := 1.7
	var rows := int(ceil(float(ids.size()) / cols))
	for i in range(ids.size()):
		var g: String = ids[i]
		var m := GoodsCatalog.build_good_model(g)
		var ext := GoodsCatalog.model_extent(g)
		var s := minf(1.15 / ext.x, 1.0 / ext.y)
		m.scale = Vector3(s, s, s)
		m.rotation_degrees.y = -25
		var x := (i % cols - (cols - 1) / 2.0) * step
		var z := (int(i / cols) - (rows - 1) / 2.0) * step * 1.1
		m.position = Vector3(x, 0, z)
		root.add_child(m)
		var col: Color = GoodsCatalog.CAT_COLORS.get(GoodsCatalog.category_of(g), Color.WHITE)
		root.add_child(MeshLib.mesh_node(MeshLib.box(Vector3(1.45, 0.05, 1.45)), MeshLib.mat(col.darkened(0.45)), Vector3(x, -0.03, z)))
		var l := Label3D.new()
		l.text = GameData.good_label(g).substr(0, 18)
		l.font_size = 30
		l.pixel_size = 0.006
		l.outline_size = 6
		l.rotation_degrees.x = -60
		l.position = Vector3(x, 0.02, z + 0.62)
		root.add_child(l)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = rows * step * 1.1 + 1.2
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0, 14, 8.5), Vector3(0, 0, 0.2))
