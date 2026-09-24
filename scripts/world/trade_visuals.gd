class_name TradeVisuals
extends Node3D
## Visuales 3D del comercio exterior: UN solo camino que sale de la plaza hasta el borde del mapa
## (aunque haya varias rutas pagadas), con su nivel (barro → empedrado → carretera), la vía férrea
## y carretas/cargas que van y vienen según los envíos en camino. world.gd llama setup(world).

const START_RADIUS := 8.5
const STEP := 2.0
const MAX_MARKERS := 8

var world: Node3D
var terrain: Terrain
var path: PackedVector2Array = PackedVector2Array()
var road_node: MeshInstance3D
var rail_node: MeshInstance3D
var markers: Array = []
var _signature := ""
var _cleared_len := 0.0


func setup(p_world: Node3D) -> void:
	world = p_world
	name = "TradeVisuals"
	terrain = world.get("terrain")
	_build_path()
	EventBus.day_passed.connect(_update)
	EventBus.jump_finished.connect(func(_r): _update())
	_update()


## Trazado fijo hacia el oeste con curvas suaves (el este suele tener mar o río).
func _build_path() -> void:
	path = PackedVector2Array()
	var seed_v := float(int(GameState.settings.get("seed", 1)) % 1000)
	var half := GameState.MAP_SIZE * 0.5
	var x := -START_RADIUS
	while x > -half + 0.5:
		var t := (-x - START_RADIUS) / half
		var z := sin(x * 0.021 + seed_v) * 9.0 * t + sin(x * 0.053 + seed_v * 0.3) * 3.0 * t
		path.append(Vector2(x, z))
		x -= STEP
	path.append(Vector2(-half + 0.3, path[path.size() - 1].y))


func _length() -> float:
	return float(path.size() - 1) * STEP


func _point_at(dist: float) -> Vector3:
	var f := clampf(dist / STEP, 0.0, float(path.size() - 1))
	var i := mini(int(f), path.size() - 2)
	var p := path[i].lerp(path[i + 1], f - i)
	return Vector3(p.x, _h(p.x, p.y), p.y)


func _h(x: float, z: float) -> float:
	return terrain.height_at(x, z) if terrain != null else 0.0


## Estado visible: nivel máximo de camino, vía férrea, obras en curso.
func _state() -> Dictionary:
	var gs := GameState
	var best := 0
	var rail := false
	for c in TradeSim.connected_towns(gs):
		best = maxi(best, int(c.get("road", 1)))
		rail = rail or bool(c.get("rail", false))
	var progress := 0.0
	for p in gs.trade.get("projects", []):
		var total := maxf(1.0, float(p.get("total_days", 1)))
		progress = maxf(progress, clampf(1.0 - float(int(p["done_day"]) - gs.today()) / total, 0.05, 1.0))
	return {"road": best, "rail": rail, "progress": progress}


func _update() -> void:
	if terrain == null or path.size() < 2:
		return
	var st := _state()
	var sig := "%d|%s|%d" % [int(st["road"]), str(st["rail"]), int(float(st["progress"]) * 10.0)]
	if sig != _signature:
		_signature = sig
		_rebuild(st)
	_update_markers()


func _rebuild(st: Dictionary) -> void:
	if road_node != null:
		road_node.queue_free()
		road_node = null
	if rail_node != null:
		rail_node.queue_free()
		rail_node = null
	var level := int(st["road"])
	var length := _length()
	var color := Color(0.45, 0.34, 0.22)
	var width := 2.6
	if level <= 0:
		if float(st["progress"]) <= 0.0:
			return
		# Camino en construcción: se abre paso desde el pueblo.
		length *= float(st["progress"])
		color = Color(0.55, 0.45, 0.3)
		width = 2.0
	else:
		match level:
			2:
				color = Color(0.55, 0.53, 0.5)
				width = 3.2
			3:
				color = Color(0.23, 0.23, 0.25)
				width = 4.4
	road_node = MeshLib.mesh_node(_strip(length, 0.0, width, 0.07), MeshLib.mat(color))
	road_node.name = "CaminoExterior"
	add_child(road_node)
	if level >= 3:
		# Línea central de la carretera.
		var line := MeshLib.mesh_node(_strip(length, 0.0, 0.18, 0.09), MeshLib.mat(Color(0.95, 0.85, 0.35)))
		road_node.add_child(line)
	if bool(st["rail"]):
		rail_node = MeshLib.mesh_node(_strip(length, width * 0.5 + 2.2, 2.0, 0.08), MeshLib.mat(Color(0.42, 0.4, 0.38)))
		rail_node.name = "ViaFerrea"
		add_child(rail_node)
		for off in [width * 0.5 + 1.6, width * 0.5 + 2.8]:
			rail_node.add_child(MeshLib.mesh_node(_strip(length, off, 0.14, 0.2), MeshLib.mat(Color(0.2, 0.2, 0.22), 0.4)))
	if length > _cleared_len + 1.0:
		var d := _cleared_len
		while d <= length:
			var p := _point_at(d)
			terrain.clear_trees(p.x, p.z, width * 0.5 + (4.0 if bool(st["rail"]) else 1.8))
			d += STEP * 2.0
		_cleared_len = length


## Franja sobre el terreno a lo largo del trazado (desplazada `offset` hacia un lado).
func _strip(length: float, offset: float, width: float, lift: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := int(floorf(length / STEP))
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	for i in range(n + 1):
		var d := minf(length, i * STEP)
		var a := _point_at(d)
		var b := _point_at(minf(length, d + 0.5))
		var dir := Vector2(b.x - a.x, b.z - a.z)
		if dir.length() < 0.001:
			dir = Vector2(-1, 0)
		dir = dir.normalized()
		var perp := Vector2(-dir.y, dir.x)
		var c := Vector2(a.x, a.z) + perp * offset
		var l2 := c + perp * width * 0.5
		var r2 := c - perp * width * 0.5
		var l := Vector3(l2.x, _h(l2.x, l2.y) + lift, l2.y)
		var r := Vector3(r2.x, _h(r2.x, r2.y) + lift, r2.y)
		if i > 0:
			for v in [prev_l, prev_r, l, prev_r, r, l]:
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
		prev_l = l
		prev_r = r
	st.generate_normals()
	return st.commit()


# --- Cargas en camino ---------------------------------------------------------------------------

func _update_markers() -> void:
	var gs := GameState
	var list: Array = gs.trade.get("shipments", [])
	while markers.size() > mini(list.size(), MAX_MARKERS):
		var m: Node3D = markers.pop_back()
		m.queue_free()
	while markers.size() < mini(list.size(), MAX_MARKERS):
		var node := _make_cart()
		add_child(node)
		markers.append(node)
	_place_markers()


func _make_cart() -> Node3D:
	var n := Node3D.new()
	n.add_child(MeshLib.mesh_node(MeshLib.box(Vector3(1.4, 0.7, 0.9)), MeshLib.mat(Color(0.5, 0.35, 0.2)), Vector3(0, 0.75, 0)))
	n.add_child(MeshLib.mesh_node(MeshLib.box(Vector3(1.1, 0.5, 0.8)), MeshLib.mat(Color(0.85, 0.78, 0.6)), Vector3(0, 1.3, 0)))
	for x in [-0.45, 0.45]:
		for z in [-0.5, 0.5]:
			n.add_child(MeshLib.mesh_node(MeshLib.box(Vector3(0.5, 0.5, 0.12)), MeshLib.mat(Color(0.3, 0.22, 0.14)), Vector3(x, 0.3, z)))
	return n


func _place_markers() -> void:
	var gs := GameState
	var list: Array = gs.trade.get("shipments", [])
	var today := float(gs.today()) + TimeManager.hour_float() / 24.0
	var length := _length()
	for i in range(markers.size()):
		var s: Dictionary = list[i]
		var depart := float(s.get("depart_day", float(s["arrive_day"]) - 1.0))
		var total := maxf(1.0, float(s["arrive_day"]) - depart)
		var prog := clampf((today - depart) / total, 0.0, 1.0)
		# Visualmente el viaje completo recorre el camino visible (ida hasta el borde o regreso al pueblo).
		var d := prog * length if str(s["kind"]) == TradeSim.KIND_SELL else (1.0 - prog) * length
		var node: Node3D = markers[i]
		var p := _point_at(d)
		var q := _point_at(minf(length, d + 1.0))
		node.position = p + Vector3(0, 0.05, 0)
		node.visible = not bool(s.get("waiting", false))
		if p.distance_to(q) > 0.01:
			node.look_at(Vector3(q.x, p.y, q.z), Vector3.UP)
			node.rotate_object_local(Vector3.UP, PI * 0.5)


func _process(_delta: float) -> void:
	if not markers.is_empty() and Engine.get_process_frames() % 6 == 0:
		_place_markers()
