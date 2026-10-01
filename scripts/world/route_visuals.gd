class_name RouteVisuals
extends Node3D
## Visuales de rutas y barcos (docs/RUTAS_BARCOS.md):
## - Capa de rutas: cada ruta del país activo se dibuja con SU COLOR siguiendo su camino real (carretera,
##   riel, agua o línea aérea en arco) con flechas de sentido. Una malla por ruta (barato). Se oculta con
##   el panel Rutas.
## - Vías férreas internas (RailSim) con balasto, durmientes y rieles (RoadMesh.rail).
## - Barcos de viajes internacionales: zarpan del puerto hacia el mar abierto y llegan desde él.
## - Modelos 3D de trenes (locomotora + vagones) y barcos: cada modelo con su diseño propio en
##   VehicleModels (docs/VEHICULOS.md), que usa LogisticsVisuals para los envíos.
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
	return VehicleModels.node(mode if VehicleModels.has_model(mode) else "vapor_barco")


## Locomotora (el frente apunta a +Z).
static func locomotive_model(mode: String) -> Node3D:
	return VehicleModels.node(mode)

const WAGON_COLORS := {"granelero": Color(0.4, 0.3, 0.22), "cisterna": Color(0.75, 0.75, 0.78), "cerrado": Color(0.5, 0.25, 0.2),
		"frigorifico": Color(0.92, 0.92, 0.95), "plataforma": Color(0.35, 0.35, 0.38), "pasajeros": Color(0.2, 0.45, 0.35)}


static func wagon_model(wt: String) -> Node3D:
	return VehicleModels.node(wt)


## Tren completo: [locomotora, vagones...] como nodos separados (cada uno sigue la vía por su cuenta).
static func train_parts(mode: String, comp: Dictionary) -> Array:
	var out := [locomotive_model(mode)]
	for wt in comp:
		for i in range(int(comp[wt])):
			if out.size() > 8:
				return out
			out.append(wagon_model(str(wt)))
	return out
