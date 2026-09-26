class_name TradeVisuals
extends Node3D
## Visuales 3D del comercio exterior: caminos que salen del pueblo hasta el borde del mapa, con su
## nivel (barro → empedrado → carretera), vías férreas (balasto, durmientes y rieles) y carretas que
## van y vienen según los envíos en camino. Cada ruta con trazado manual (TransitSim, dibujado por
## el jugador) se dibuja por su polilínea; las rutas sin trazado (partidas viejas o si el jugador
## aceptó el automático) comparten el camino automático hacia el oeste. world.gd llama setup(world).

const MAX_MARKERS := 8

var world: Node3D
var terrain: Terrain
var path: PackedVector2Array = PackedVector2Array()   # camino automático
var road_node: MeshInstance3D     # primera franja de camino dibujada (compatibilidad con pruebas)
var rail_node: Node3D
var markers: Array = []
var lines: Array = []             # [{tid, points, cum, level, rail, rail_points, progress, manual}]
var _root: Node3D
var _signature := ""
var _cleared := {}


func setup(p_world: Node3D) -> void:
	world = p_world
	name = "TradeVisuals"
	terrain = world.get("terrain")
	path = TransitSim.auto_trade_path(GameState)
	_root = Node3D.new()
	add_child(_root)
	EventBus.day_passed.connect(_update)
	EventBus.jump_finished.connect(func(_r): _update())
	_update()


func refresh() -> void:
	_update()


func _update() -> void:
	if terrain == null:
		return
	var ls := TransitSim.trade_lines(GameState)
	var sig := ""
	for l in ls:
		sig += "%s:%d:%s:%d:%d:%d;" % [str(l["tid"]), int(l["level"]), str(l["rail"]), int(float(l["progress"]) * 10.0),
			(l["points"] as PackedVector2Array).size(), (l["rail_points"] as PackedVector2Array).size()]
	sig += str(int(TransitSim.state(GameState).get("path_version", 0)))
	if sig != _signature:
		_signature = sig
		lines = ls
		for l in lines:
			l["cum"] = TransitSim.poly_cum(l["points"])
		_rebuild()
	_update_markers()


func _rebuild() -> void:
	for ch in _root.get_children():
		ch.queue_free()
	road_node = null
	rail_node = null
	for l in lines:
		var pts: PackedVector2Array = l["points"]
		var level := int(l["level"])
		var width := 2.6
		var length := TransitSim.poly_length(pts)
		if pts.size() >= 2 and (level > 0 or float(l["progress"]) > 0.0):
			var kind := "barro"
			var color := Color(-1, 0, 0)
			if level <= 0:
				# Camino en construcción: se abre paso desde el pueblo (tierra más clara).
				length *= float(l["progress"])
				color = Color(0.58, 0.47, 0.32)
				width = 2.0
			elif level == 2:
				kind = "empedrado"
				width = 3.2
			elif level >= 3:
				kind = "cemento"
				width = 4.4
			var node := MeshLib.mesh_node(RoadMesh.strip(terrain, pts, 0.0, width, 0.07, length), RoadMesh.material(kind, color))
			node.name = "CaminoExterior"
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_root.add_child(node)
			if road_node == null:
				road_node = node
			node.add_child(RoadMesh.bridge(terrain, pts, width, length))
			_clear_trees(str(l["tid"]) + "r", pts, length, width * 0.5 + 1.8)
		if bool(l["rail"]):
			var rp: PackedVector2Array = l["rail_points"]
			var rn: Node3D
			if rp.size() >= 2:
				rn = TransitVisuals.rail_node(terrain, rp)
				_clear_trees(str(l["tid"]) + "t", rp, TransitSim.poly_length(rp), 2.5)
			elif pts.size() >= 2:
				rn = TransitVisuals.rail_node(terrain, pts, width * 0.5 + 2.2)
				_clear_trees(str(l["tid"]) + "t", pts, TransitSim.poly_length(pts), width * 0.5 + 4.0)
			if rn != null:
				_root.add_child(rn)
				if rail_node == null:
					rail_node = rn


func _clear_trees(key: String, pts: PackedVector2Array, length: float, radius: float) -> void:
	if float(_cleared.get(key, 0.0)) >= length - 1.0:
		return
	var cum := TransitSim.poly_cum(pts)
	var d := float(_cleared.get(key, 0.0))
	while d <= length:
		var p := TransitSim.poly_point(pts, cum, d)
		terrain.clear_trees(p.x, p.y, radius)
		d += 4.0
	_cleared[key] = length


func _h(x: float, z: float) -> float:
	return TransitVisuals.ground(terrain, x, z)


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


## Línea por la que viaja un envío: la de su pueblo, o el camino automático.
func _line_for(tid: String) -> Dictionary:
	var fallback: Dictionary = {}
	for l in lines:
		if (l["points"] as PackedVector2Array).size() < 2:
			continue
		if str(l["tid"]) == tid:
			return l
		if fallback.is_empty() and not bool(l["manual"]):
			fallback = l
	if fallback.is_empty():
		for l in lines:
			if (l["points"] as PackedVector2Array).size() >= 2:
				return l
	return fallback


func _place_markers() -> void:
	var gs := GameState
	var list: Array = gs.trade.get("shipments", [])
	var today := float(gs.today()) + TimeManager.hour_float() / 24.0
	for i in range(markers.size()):
		var s: Dictionary = list[i]
		var node: Node3D = markers[i]
		var l := _line_for(str(s.get("town_id", "")))
		if l.is_empty():
			node.visible = false
			continue
		var pts: PackedVector2Array = l["points"]
		var cum: PackedFloat32Array = l["cum"]
		var length := cum[cum.size() - 1]
		var depart := float(s.get("depart_day", float(s["arrive_day"]) - 1.0))
		var total := maxf(1.0, float(s["arrive_day"]) - depart)
		var prog := clampf((today - depart) / total, 0.0, 1.0)
		# Visualmente el viaje completo recorre el camino visible (ida hasta el borde o regreso al pueblo).
		var d := prog * length if str(s["kind"]) == TradeSim.KIND_SELL else (1.0 - prog) * length
		var p2 := TransitSim.poly_point(pts, cum, d)
		var q2 := TransitSim.poly_point(pts, cum, minf(length, d + 1.0))
		var p := Vector3(p2.x, _h(p2.x, p2.y), p2.y)
		var q := Vector3(q2.x, p.y, q2.y)
		node.position = p + Vector3(0, 0.05, 0)
		node.visible = not bool(s.get("waiting", false))
		if p.distance_to(q) > 0.01:
			node.look_at(q, Vector3.UP)
			node.rotate_object_local(Vector3.UP, PI * 0.5)


func _process(_delta: float) -> void:
	if not markers.is_empty() and Engine.get_process_frames() % 6 == 0:
		_place_markers()
