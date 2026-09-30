class_name RouteVisuals
extends Node3D
## Visuales de rutas y barcos (docs/RUTAS_BARCOS.md):
## - Capa de rutas: cada ruta del país activo se dibuja con SU COLOR siguiendo su camino real (carretera,
##   riel, agua o línea aérea en arco) con flechas de sentido. Una malla por ruta (barato). Se oculta con
##   el panel Rutas.
## - Vías férreas internas (RailSim) con balasto, durmientes y rieles (RoadMesh.rail).
## - Barcos de viajes internacionales: zarpan del puerto hacia el mar abierto y llegan desde él.
## - Modelos 3D de trenes (locomotora + vagones) y barcos (bote, velero, vapor, carguero,
##   portacontenedores) que usa LogisticsVisuals para los envíos.
## LogisticsVisuals.setup lo crea como hijo (sin tocar world.gd).

static var instance: RouteVisuals
static var _mats := {}

var world: Node3D
var _layer_root: Node3D
var _rails_root: Node3D
var _ships_root: Node3D
var _layer_sig := ""
var _rail_sig := ""
var _timer := 0.0
var _voyage_nodes := {}   # id de viaje -> Node3D


func setup(p_world: Node3D) -> void:
	world = p_world
	instance = self
	name = "RouteVisuals"
	for n in ["RouteLayer", "Rails", "Voyages"]:
		var node := Node3D.new()
		node.name = n
		add_child(node)
	_layer_root = get_node("RouteLayer")
	_rails_root = get_node("Rails")
	_ships_root = get_node("Voyages")
	refresh()


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _terrain() -> Terrain:
	return world.terrain if world and world.get("terrain") else null


func _h(x: float, z: float) -> float:
	var t := _terrain()
	return maxf(t.height_at(x, z), t.water_level) if t else 0.0


static func flat_mat(col: Color, alpha := 0.92) -> StandardMaterial3D:
	var key := "%s_%.2f" % [col.to_html(false), alpha]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m


func refresh() -> void:
	_layer_sig = ""
	_rail_sig = ""
	_sync()


func _sync() -> void:
	var gs = GameState
	var rs := "%d|%d" % [RailSim.version(gs), RailSim.rails(gs).size()]
	if rs != _rail_sig:
		_rail_sig = rs
		_rebuild_rails()
	var ls := "%d|%s|%d|%d|%d|%d" % [RouteSim.version(gs), str(RouteSim.layer_visible(gs)), LogisticsSim.routes(gs).size(), int(gs.logistics.get("road_version", 0)),
			RailSim.version(gs), gs.buildings.size()]
	if ls != _layer_sig:
		_layer_sig = ls
		_rebuild_layer()


# --- Vías férreas -------------------------------------------------------------------------------

func _rebuild_rails() -> void:
	for ch in _rails_root.get_children():
		ch.queue_free()
	var t := _terrain()
	for r in RailSim.rails(GameState):
		var pts := RailSim.points_of(r)
		if pts.size() >= 2:
			_rails_root.add_child(RoadMesh.rail(t, pts))
			if float(r.get("bridge", 0.0)) > 0.5:
				_rails_root.add_child(RoadMesh.bridge(t, pts, 3.0))


func rail_count() -> int:
	return _rails_root.get_child_count() if _rails_root else 0


# --- Capa de rutas --------------------------------------------------------------------------------

func layer_count() -> int:
	return _layer_root.get_child_count() if _layer_root else 0


func _rebuild_layer() -> void:
	for ch in _layer_root.get_children():
		ch.queue_free()
	var gs = GameState
	_layer_root.visible = RouteSim.layer_visible(gs)
	if not _layer_root.visible:
		return
	var i := 0
	for u in RouteSim.all_routes(gs):
		if not bool(u["local"]):
			continue
		var pts := RouteSim.route_points(gs, u)
		if pts.size() < 2:
			continue
		var node := MeshInstance3D.new()
		node.name = "route_%s" % str(u["key"])
		node.mesh = _ribbon(pts, (i % 4 - 1.5) * 0.9, str(u["family"]) == "aire")
		node.material_override = flat_mat(u["color"])
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_layer_root.add_child(node)
		# Etiqueta con el nombre en el punto medio.
		var mid := TransitSim.poly_point(pts, TransitSim.poly_cum(pts), TransitSim.poly_length(pts) * 0.5)
		var lab := Label3D.new()
		lab.text = str(u["name"])
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.font_size = 34
		lab.pixel_size = 0.02
		MeshLib.style_label(lab, 260.0, 2.0)
		lab.outline_size = 8
		lab.modulate = (u["color"] as Color).lightened(0.2)
		lab.position = Vector3(mid.x, _h(mid.x, mid.y) + (30.0 if str(u["family"]) == "aire" else 3.2), mid.y)
		node.add_child(lab)
		i += 1


## Cinta de color sobre el camino (a 0,5 m del suelo) con chevrones de sentido cada 14 m.
func _ribbon(pts: PackedVector2Array, offset: float, air: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cum := TransitSim.poly_cum(pts)
	var total := cum[cum.size() - 1]
	var step := 2.0
	var n := maxi(2, int(total / step) + 1)
	var width := 0.9
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	var y_of := func(p: Vector2, d: float) -> float:
		var base := _h(p.x, p.y) + 0.55
		if air:
			base += 4.0 + 26.0 * sin(PI * clampf(d / maxf(1.0, total), 0.0, 1.0))
		return base
	for k in range(n):
		var d := minf(total, k * total / (n - 1))
		var p := TransitSim.poly_point(pts, cum, d)
		var q := TransitSim.poly_point(pts, cum, minf(total, d + 0.8))
		if q.distance_to(p) < 0.01:
			q = p + (p - TransitSim.poly_point(pts, cum, maxf(0.0, d - 0.8)))
		var dir := (q - p).normalized()
		var side := Vector2(-dir.y, dir.x)
		var c := p + side * offset
		var y: float = y_of.call(c, d)
		var l := Vector3(c.x - side.x * width * 0.5, y, c.y - side.y * width * 0.5)
		var r := Vector3(c.x + side.x * width * 0.5, y, c.y + side.y * width * 0.5)
		if k > 0:
			st.add_vertex(prev_l)
			st.add_vertex(prev_r)
			st.add_vertex(r)
			st.add_vertex(prev_l)
			st.add_vertex(r)
			st.add_vertex(l)
		prev_l = l
		prev_r = r
	# Flechas de sentido.
	var ad := 7.0
	while ad < total - 3.0:
		var p := TransitSim.poly_point(pts, cum, ad)
		var q := TransitSim.poly_point(pts, cum, minf(total, ad + 1.0))
		var dir := (q - p).normalized()
		var side := Vector2(-dir.y, dir.x)
		var c := p + side * offset
		var y: float = y_of.call(c, ad) + 0.05
		var tip := c + dir * 1.6
		var bl := c - dir * 0.6 + side * 1.2
		var br := c - dir * 0.6 - side * 1.2
		st.add_vertex(Vector3(tip.x, y, tip.y))
		st.add_vertex(Vector3(bl.x, y, bl.y))
		st.add_vertex(Vector3(br.x, y, br.y))
		ad += 14.0
	return st.commit()


# --- Viajes internacionales en barco ----------------------------------------------------------------

func _sync_voyages() -> void:
	var gs = GameState
	var live := {}
	for v in ShipSim.voyages_here(gs):
		var f: Dictionary = v["flight"]
		var port: Dictionary = gs.get_building(int(v["port"]))
		if port.is_empty():
			continue
		var id := int(f["id"])
		live[id] = true
		var node: Node3D = _voyage_nodes.get(id)
		if node == null:
			node = ship_model(str(f.get("ship_mode", "vapor_barco")))
			_ships_root.add_child(node)
			_voyage_nodes[id] = node
		# Sale del muelle hacia el mar abierto (o llega desde él) durante el primer / último día.
		var dock := ShipSim.dock_point(gs, port)
		if dock == Vector2.INF:
			node.visible = false
			continue
		var away := (dock - Vector2(float(port["x"]), float(port["z"]))).normalized()
		var days := maxf(1.0, float(int(f["arrive"]) - int(f["depart"])))
		var u := float(v["t"]) * days   # días desde la salida
		var k := clampf(u, 0.0, 1.0) if bool(v["outgoing"]) else clampf(days - u, 0.0, 1.0)
		var visible_now := (bool(v["outgoing"]) and u < 1.0) or (not bool(v["outgoing"]) and days - u < 1.0)
		node.visible = visible_now
		if not visible_now:
			continue
		var p := dock + away * 260.0 * k
		node.position = Vector3(p.x, _water_y(), p.y)
		node.rotation.y = atan2(away.x, away.y) if bool(v["outgoing"]) else atan2(-away.x, -away.y)
	for id in _voyage_nodes.keys():
		if not live.has(id):
			(_voyage_nodes[id] as Node3D).queue_free()
			_voyage_nodes.erase(id)


func _water_y() -> float:
	var t := _terrain()
	return (t.water_level if t else 0.0) + 0.15


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= 0.5:
		_timer = 0.0
		_sync()
		_sync_voyages()


# --- Modelos -----------------------------------------------------------------------------------------

static func _m(col: Color, rough := 0.8) -> StandardMaterial3D:
	return MeshLib.mat(col, rough)


static func _box(key: String, size: Vector3, col: Color, pos: Vector3) -> MeshInstance3D:
	return MeshLib.mesh_node(MeshLib.cached(key, func(): return MeshLib.box(size)), _m(col), pos)


## Barco según el medio (el casco apunta a +Z).
static func ship_model(mode: String) -> Node3D:
	var root := Node3D.new()
	match mode:
		"balsa":
			root.add_child(_box("sh_raft", Vector3(1.6, 0.35, 3.2), Color(0.5, 0.36, 0.2), Vector3(0, 0.15, 0)))
			root.add_child(_box("sh_raft_load", Vector3(1.0, 0.5, 1.4), Color(0.62, 0.5, 0.32), Vector3(0, 0.55, -0.3)))
			var p := MeshLib.make_person(Color(0.5, 0.42, 0.3), Color(0.8, 0.6, 0.45), Color(0.15, 0.1, 0.08), false)
			p.position = Vector3(0, 0.3, 1.0)
			root.add_child(p)
		"velero":
			root.add_child(_box("sh_sail_hull", Vector3(2.6, 1.2, 8.0), Color(0.42, 0.28, 0.16), Vector3(0, 0.4, 0)))
			root.add_child(_box("sh_sail_deck", Vector3(2.4, 0.15, 7.6), Color(0.62, 0.48, 0.3), Vector3(0, 1.05, 0)))
			root.add_child(_box("sh_sail_mast", Vector3(0.18, 7.0, 0.18), Color(0.35, 0.25, 0.15), Vector3(0, 4.5, 0.5)))
			root.add_child(_box("sh_sail_cloth", Vector3(0.08, 4.6, 3.4), Color(0.95, 0.93, 0.85), Vector3(0.2, 4.6, 0.3)))
			root.add_child(_box("sh_sail_cargo", Vector3(1.6, 0.8, 2.0), Color(0.62, 0.5, 0.32), Vector3(0, 1.5, -2.2)))
		"carguero":
			root.add_child(_box("sh_cargo_hull", Vector3(4.2, 2.4, 18.0), Color(0.55, 0.12, 0.1), Vector3(0, 0.6, 0)))
			root.add_child(_box("sh_cargo_deck", Vector3(4.0, 0.2, 17.6), Color(0.3, 0.32, 0.35), Vector3(0, 1.9, 0)))
			root.add_child(_box("sh_cargo_bridge", Vector3(3.6, 3.0, 3.0), Color(0.92, 0.92, 0.9), Vector3(0, 3.4, -7.0)))
			root.add_child(_box("sh_cargo_hold", Vector3(3.4, 1.2, 10.0), Color(0.25, 0.4, 0.3), Vector3(0, 2.6, 1.5)))
			root.add_child(_box("sh_cargo_crane", Vector3(0.3, 4.0, 0.3), Color(0.95, 0.75, 0.1), Vector3(1.2, 4.0, 3.5)))
		"portacontenedores":
			root.add_child(_box("sh_box_hull", Vector3(5.0, 2.8, 24.0), Color(0.12, 0.2, 0.35), Vector3(0, 0.7, 0)))
			root.add_child(_box("sh_box_bridge", Vector3(4.6, 4.0, 3.0), Color(0.95, 0.95, 0.93), Vector3(0, 4.2, -10.0)))
			var cols := [Color(0.8, 0.25, 0.2), Color(0.2, 0.45, 0.7), Color(0.25, 0.6, 0.3), Color(0.9, 0.7, 0.2)]
			for zi in range(6):
				for yi in range(2):
					root.add_child(MeshLib.mesh_node(MeshLib.cached("sh_container", func(): return MeshLib.box(Vector3(4.4, 1.2, 2.6))), _m(cols[(zi + yi) % 4]), Vector3(0, 2.8 + yi * 1.25, -6.0 + zi * 3.0)))
		_:   # vapor
			root.add_child(_box("sh_steam_hull", Vector3(3.2, 1.6, 12.0), Color(0.15, 0.15, 0.17), Vector3(0, 0.5, 0)))
			root.add_child(_box("sh_steam_deck", Vector3(3.0, 0.2, 11.6), Color(0.6, 0.5, 0.36), Vector3(0, 1.35, 0)))
			root.add_child(_box("sh_steam_cabin", Vector3(2.4, 1.6, 4.0), Color(0.92, 0.9, 0.85), Vector3(0, 2.2, -1.0)))
			root.add_child(MeshLib.mesh_node(MeshLib.cached("sh_steam_stack", func(): return MeshLib.cylinder(0.45, 0.45, 2.6, 10)), _m(Color(0.75, 0.15, 0.1)), Vector3(0, 4.0, 0.3)))
			root.add_child(_box("sh_steam_cargo", Vector3(2.2, 0.9, 3.0), Color(0.62, 0.5, 0.32), Vector3(0, 1.9, 3.6)))
	return root


## Locomotora (el frente apunta a +Z).
static func locomotive_model(mode: String) -> Node3D:
	var root := Node3D.new()
	if mode in ["tren_diesel", "tren_electrico"]:
		root.add_child(_box("tr_diesel_body", Vector3(2.2, 2.4, 6.0), Color(0.85, 0.55, 0.1), Vector3(0, 1.7, 0)))
		root.add_child(_box("tr_diesel_cab", Vector3(2.2, 0.8, 1.6), Color(0.2, 0.3, 0.4), Vector3(0, 2.6, 2.1)))
		root.add_child(_box("tr_diesel_band", Vector3(2.24, 0.25, 6.04), Color(0.9, 0.9, 0.88), Vector3(0, 1.3, 0)))
	else:
		var boiler := MeshLib.mesh_node(MeshLib.cached("tr_boiler", func(): return MeshLib.cylinder(0.85, 0.85, 4.2, 12)), _m(Color(0.12, 0.12, 0.13), 0.5), Vector3(0, 1.8, 0.6))
		boiler.rotation.x = PI * 0.5
		root.add_child(boiler)
		root.add_child(_box("tr_cab", Vector3(2.0, 2.2, 1.8), Color(0.45, 0.12, 0.1), Vector3(0, 2.1, -2.2)))
		root.add_child(MeshLib.mesh_node(MeshLib.cached("tr_stack", func(): return MeshLib.cylinder(0.3, 0.22, 1.2, 8)), _m(Color(0.1, 0.1, 0.1)), Vector3(0, 3.1, 2.2)))
		root.add_child(_box("tr_chassis", Vector3(2.0, 0.5, 6.0), Color(0.2, 0.2, 0.22), Vector3(0, 0.75, 0)))
	for z in [-2.0, 0.0, 2.0]:
		for x in [-0.9, 0.9]:
			var wl := MeshLib.mesh_node(MeshLib.cached("tr_wheel", func(): return MeshLib.wheel(0.5, 0.15)), _m(Color(0.3, 0.1, 0.08)), Vector3(x, 0.5, z))
			wl.rotation.z = PI * 0.5
			root.add_child(wl)
	return root


const WAGON_COLORS := {"granelero": Color(0.4, 0.3, 0.22), "cisterna": Color(0.75, 0.75, 0.78), "cerrado": Color(0.5, 0.25, 0.2),
		"frigorifico": Color(0.92, 0.92, 0.95), "plataforma": Color(0.35, 0.35, 0.38), "pasajeros": Color(0.2, 0.45, 0.35)}


static func wagon_model(wt: String) -> Node3D:
	var root := Node3D.new()
	var col: Color = WAGON_COLORS.get(wt, Color(0.5, 0.25, 0.2))
	root.add_child(_box("tr_wagon_bed", Vector3(2.0, 0.4, 5.0), Color(0.2, 0.2, 0.22), Vector3(0, 0.8, 0)))
	match wt:
		"cisterna":
			var tank := MeshLib.mesh_node(MeshLib.cached("tr_tank", func(): return MeshLib.cylinder(0.9, 0.9, 4.6, 12)), _m(col, 0.4), Vector3(0, 1.9, 0))
			tank.rotation.x = PI * 0.5
			root.add_child(tank)
		"plataforma":
			root.add_child(_box("tr_flat_load", Vector3(1.6, 0.6, 3.6), Color(0.55, 0.55, 0.6), Vector3(0, 1.3, 0)))
		"granelero":
			root.add_child(MeshLib.mesh_node(MeshLib.cached("tr_hopper", func(): return MeshLib.box(Vector3(2.0, 1.3, 4.8))), _m(col), Vector3(0, 1.65, 0)))
			root.add_child(_box("tr_hopper_load", Vector3(1.8, 0.3, 4.4), Color(0.15, 0.13, 0.12), Vector3(0, 2.4, 0)))
		_:
			root.add_child(MeshLib.mesh_node(MeshLib.cached("tr_wagon_box", func(): return MeshLib.box(Vector3(2.0, 1.8, 4.8))), _m(col), Vector3(0, 1.9, 0)))
	for z in [-1.8, 1.8]:
		for x in [-0.9, 0.9]:
			var wl := MeshLib.mesh_node(MeshLib.cached("tr_wheel_s", func(): return MeshLib.wheel(0.4, 0.12)), _m(Color(0.15, 0.15, 0.15)), Vector3(x, 0.4, z))
			wl.rotation.z = PI * 0.5
			root.add_child(wl)
	return root


## Tren completo: [locomotora, vagones...] como nodos separados (cada uno sigue la vía por su cuenta).
static func train_parts(mode: String, comp: Dictionary) -> Array:
	var out := [locomotive_model(mode)]
	for wt in comp:
		for i in range(int(comp[wt])):
			if out.size() > 8:
				return out
			out.append(wagon_model(str(wt)))
	return out
