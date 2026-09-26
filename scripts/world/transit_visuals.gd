class_name TransitVisuals
extends Node3D
## Visuales del transporte (docs/TRANSPORTE.md): carreteras trazadas por puntos dibujadas como
## franjas continuas (con puentes), paraderos, buses que circulan por sus rutas, autos en los
## parqueaderos y el modo de trazado por puntos (carretera, camino o vía férrea a otro pueblo,
## paradero y borrar). Clic = punto · Retroceso = quita el último · clic derecho/Esc/Enter termina
## (con menos de dos puntos, cancela). world.gd llama setup(world).

const BUS_COLOR := Color(0.93, 0.62, 0.12)
const MAX_BUSES := 24

static var instance: TransitVisuals

var world: Node3D
var _roads_root: Node3D
var _stops_root: Node3D
var _buses_root: Node3D
var _cars_root: Node3D
var _ghost: Node3D
var _road_sig := ""
var _stops_sig := ""
var _timer := 0.0
var _bus_nodes: Array = []     # [{node, path, cum, phase}]
var _road_count := 0

# Modo trazado
var trace_mode := false
var trace_kind := ""           # road | trade_road | trade_rail | stop | erase
var trace_arg := ""            # tipo de carretera o id del pueblo
var _points := PackedVector2Array()
var _hover := Vector2.ZERO
var _hint := ""
var _hover_ok := false


func setup(p_world: Node3D) -> void:
	world = p_world
	instance = self
	name = "TransitVisuals"
	for n in ["Roads", "Stops", "Buses", "Cars"]:
		var node := Node3D.new()
		node.name = n
		add_child(node)
	_roads_root = get_node("Roads")
	_stops_root = get_node("Stops")
	_buses_root = get_node("Buses")
	_cars_root = get_node("Cars")
	rebuild()
	EventBus.day_passed.connect(_on_day)
	EventBus.jump_finished.connect(func(_r): rebuild())


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _terrain() -> Terrain:
	return world.terrain if world else null


static func ground(t: Terrain, x: float, z: float) -> float:
	if t == null:
		return 0.0
	var h := t.height_at(x, z)
	if h < t.water_level + 0.2:
		return t.water_level + 1.0   # Puente: tablero sobre el agua.
	return h


func _h(x: float, z: float) -> float:
	return ground(_terrain(), x, z)


# --- Mallas ------------------------------------------------------------------------------------

## Franja continua a lo largo de una polilínea (desplazada `offset` hacia un lado).
## Implementación en RoadMesh (sigue el relieve, faldones, tapas en los extremos y UV para el shader).
static func strip_mesh(t: Terrain, pts: PackedVector2Array, offset: float, width: float, lift: float, max_len := -1.0) -> ArrayMesh:
	return RoadMesh.strip(t, pts, offset, width, lift, max_len)


## Vía férrea: balasto, durmientes y dos rieles de acero (RoadMesh.rail).
static func rail_node(t: Terrain, pts: PackedVector2Array, offset := 0.0, max_len := -1.0, ghost: Material = null) -> Node3D:
	return RoadMesh.rail(t, pts, offset, max_len, ghost)


## Puente (vigas, barandas y pilares) donde la polilínea cruza agua.
static func bridge_pillars(t: Terrain, pts: PackedVector2Array, width := 3.0) -> Node3D:
	return RoadMesh.bridge(t, pts, width)


# --- Carreteras por puntos ---------------------------------------------------------------------

func _signature() -> String:
	return "%d|%d" % [int(GameState.logistics.get("road_version", 0)), RoadSim.roads(GameState).size()]


func rebuild() -> void:
	_rebuild_roads()
	_rebuild_stops()
	_sync_buses()
	_sync_cars()


func road_count() -> int:
	return _road_count


func _rebuild_roads() -> void:
	_road_sig = _signature()
	for ch in _roads_root.get_children():
		ch.queue_free()
	_road_count = 0
	var t := _terrain()
	for p in TransitSim.polys(GameState):
		var segs := TransitSim.poly_segments(GameState, int(p["id"]))
		if segs.is_empty():
			continue
		# Tramos consecutivos del mismo tipo (una mejora puede cambiar el tipo de todos).
		var run := PackedVector2Array()
		var kind := str(segs[0]["kind"])
		for i in range(segs.size()):
			var s: Dictionary = segs[i]
			if str(s["kind"]) != kind and run.size() >= 2:
				_roads_root.add_child(_road_strip(t, run, kind))
				run = PackedVector2Array([run[run.size() - 1]])
				kind = str(s["kind"])
			if run.is_empty():
				run.append(RoadSim.seg_a(s))
			run.append(RoadSim.seg_b(s))
		if run.size() >= 2:
			_roads_root.add_child(_road_strip(t, run, kind))
		_road_count += 1


func _road_strip(t: Terrain, pts: PackedVector2Array, kind: String, ghost: Material = null) -> Node3D:
	var kd := RoadSim.kind_def(kind)
	return RoadMesh.road_node(t, pts, kind, float(kd.get("width", 2.2)), ghost)


# --- Paraderos, buses y autos ------------------------------------------------------------------

func _rebuild_stops() -> void:
	var gs = GameState
	_stops_sig = "%d|%d" % [TransitSim.stops(gs).size(), TransitSim.routes(gs).size()]
	for ch in _stops_root.get_children():
		ch.queue_free()
	for s in TransitSim.stops(gs):
		var p := TransitSim.stop_pos(s)
		var node := _stop_model()
		node.position = Vector3(p.x, _h(p.x, p.y), p.y)
		var lab := Label3D.new()
		lab.text = str(s["name"])
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.font_size = 36
		lab.pixel_size = 0.02
		MeshLib.style_label(lab, 160.0)
		lab.outline_size = 8
		lab.modulate = Color(1.0, 0.85, 0.45)
		lab.position = Vector3(0, 3.6, 0)
		node.add_child(lab)
		_stops_root.add_child(node)


static func _stop_model() -> Node3D:
	var root := Node3D.new()
	var metal := MeshLib.mat(Color(0.3, 0.32, 0.35), 0.5)
	root.add_child(MeshLib.mesh_node(MeshLib.cached("stop_pole", func(): return MeshLib.box(Vector3(0.1, 2.6, 0.1))), metal, Vector3(-1.2, 1.3, 0)))
	root.add_child(MeshLib.mesh_node(MeshLib.cached("stop_sign", func(): return MeshLib.box(Vector3(0.6, 0.6, 0.06))), MeshLib.mat(Color(0.15, 0.4, 0.8)), Vector3(-1.2, 2.5, 0)))
	root.add_child(MeshLib.mesh_node(MeshLib.cached("stop_roof", func(): return MeshLib.box(Vector3(2.0, 0.08, 1.1))), MeshLib.mat(BUS_COLOR), Vector3(0.2, 2.2, -0.3)))
	for x in [-0.7, 1.1]:
		root.add_child(MeshLib.mesh_node(MeshLib.cached("stop_post", func(): return MeshLib.box(Vector3(0.08, 2.2, 0.08))), metal, Vector3(x, 1.1, -0.75)))
	root.add_child(MeshLib.mesh_node(MeshLib.cached("stop_bench", func(): return MeshLib.box(Vector3(1.6, 0.1, 0.4))), MeshLib.mat(Color(0.45, 0.3, 0.18)), Vector3(0.2, 0.5, -0.5)))
	return root


static func bus_model() -> Node3D:
	var root := Node3D.new()
	root.add_child(MeshLib.mesh_node(MeshLib.cached("bus_body", func(): return MeshLib.box(Vector3(1.6, 1.5, 4.6))), MeshLib.mat(BUS_COLOR), Vector3(0, 1.15, 0)))
	root.add_child(MeshLib.mesh_node(MeshLib.cached("bus_windows", func(): return MeshLib.box(Vector3(1.64, 0.55, 3.9))), MeshLib.mat(Color(0.2, 0.3, 0.4), 0.3), Vector3(0, 1.45, -0.2)))
	root.add_child(MeshLib.mesh_node(MeshLib.cached("bus_front", func(): return MeshLib.box(Vector3(1.4, 0.6, 0.05))), MeshLib.mat(Color(0.2, 0.3, 0.4), 0.3), Vector3(0, 1.45, 2.31)))
	root.add_child(MeshLib.mesh_node(MeshLib.cached("bus_roof", func(): return MeshLib.box(Vector3(1.5, 0.12, 4.4))), MeshLib.mat(Color(0.95, 0.95, 0.92)), Vector3(0, 1.96, 0)))
	# Faros (se encienden de noche), parachoques y franja lateral.
	for x in [-0.55, 0.55]:
		root.add_child(MeshLib.mesh_node(MeshLib.cached("bus_light", func(): return MeshLib.box(Vector3(0.28, 0.16, 0.05))), MeshLib.glow_mat(Color(1.0, 0.92, 0.7), 0.1, 2.5), Vector3(x, 0.72, 2.31)))
	root.add_child(MeshLib.mesh_node(MeshLib.cached("bus_bumper", func(): return MeshLib.box(Vector3(1.64, 0.18, 4.72))), MeshLib.mat(Color(0.18, 0.18, 0.2), 0.5), Vector3(0, 0.5, 0)))
	root.add_child(MeshLib.mesh_node(MeshLib.cached("bus_stripe", func(): return MeshLib.box(Vector3(1.63, 0.1, 4.0))), MeshLib.mat(Color(0.95, 0.95, 0.92)), Vector3(0, 1.08, 0)))
	for z in [1.5, -1.5]:
		for x in [-0.8, 0.8]:
			var w := MeshLib.mesh_node(MeshLib.cached("wheel_s", func(): return MeshLib.wheel(0.35, 0.2)), MeshLib.mat(Color(0.1, 0.1, 0.1)), Vector3(x, 0.35, z))
			w.rotation.z = PI * 0.5
			root.add_child(w)
	return root


static func car_model(col: Color) -> Node3D:
	var root := Node3D.new()
	root.add_child(MeshLib.mesh_node(MeshLib.cached("car_body", func(): return MeshLib.box(Vector3(1.0, 0.45, 2.0))), MeshLib.mat(col), Vector3(0, 0.45, 0)))
	root.add_child(MeshLib.mesh_node(MeshLib.cached("car_top", func(): return MeshLib.box(Vector3(0.9, 0.35, 1.0))), MeshLib.mat(Color(0.2, 0.28, 0.35), 0.3), Vector3(0, 0.83, -0.1)))
	return root


## Recorrido de una ruta: depósito → paraderos siguiendo las carreteras (ida y vuelta).
func _route_path(r: Dictionary) -> PackedVector2Array:
	var gs = GameState
	var pts := PackedVector2Array()
	var d: Dictionary = gs.get_building(int(r["depot"]))
	if d.is_empty():
		return pts
	pts.append(Vector2(float(d["x"]), float(d["z"])))
	for sid in r["stops"]:
		var s := TransitSim.get_stop(gs, int(sid))
		if not s.is_empty():
			var leg := road_path(gs, pts[pts.size() - 1], TransitSim.stop_pos(s))
			for i in range(1, leg.size()):
				pts.append(leg[i])
	var back := pts.duplicate()
	back.reverse()
	for i in range(1, back.size()):
		pts.append(back[i])
	return pts


## Camino por la red de carreteras entre dos puntos (Dijkstra sobre extremos de tramos).
static func road_path(gs, a: Vector2, b: Vector2) -> PackedVector2Array:
	var rs := RoadSim.roads(gs)
	var nodes := {}      # clave -> Vector2
	var adj := {}        # clave -> [[clave, dist]]
	var key := func(p: Vector2) -> String: return "%d_%d" % [int(round(p.x * 2.0)), int(round(p.y * 2.0))]
	for r in rs:
		var pa := RoadSim.seg_a(r)
		var pb := RoadSim.seg_b(r)
		var ka: String = key.call(pa)
		var kb: String = key.call(pb)
		nodes[ka] = pa
		nodes[kb] = pb
		if not adj.has(ka):
			adj[ka] = []
		if not adj.has(kb):
			adj[kb] = []
		adj[ka].append([kb, pa.distance_to(pb)])
		adj[kb].append([ka, pa.distance_to(pb)])
	# Uniones en T: un extremo sobre el interior de otro tramo.
	for r in rs:
		var pa := RoadSim.seg_a(r)
		var pb := RoadSim.seg_b(r)
		for k in nodes:
			var q: Vector2 = nodes[k]
			if q.distance_to(pa) > 0.6 and q.distance_to(pb) > 0.6 and RoadSim.dist_point_segment(q, pa, pb) < 1.5:
				for e in [pa, pb]:
					var ke: String = key.call(e)
					adj[k].append([ke, q.distance_to(e)])
					adj[ke].append([k, q.distance_to(e)])
	if nodes.is_empty():
		return PackedVector2Array([a, b])
	var start := ""
	var goal := ""
	var bs := INF
	var bg := INF
	for k in nodes:
		var p: Vector2 = nodes[k]
		if p.distance_to(a) < bs:
			bs = p.distance_to(a)
			start = k
		if p.distance_to(b) < bg:
			bg = p.distance_to(b)
			goal = k
	var dist := {start: 0.0}
	var prev := {}
	var open := [start]
	var done := {}
	while not open.is_empty():
		var bi := 0
		for i in range(open.size()):
			if float(dist[open[i]]) < float(dist[open[bi]]):
				bi = i
		var cur: String = open[bi]
		open.remove_at(bi)
		if done.has(cur):
			continue
		done[cur] = true
		if cur == goal:
			break
		for e in adj.get(cur, []):
			var nk: String = e[0]
			var nd := float(dist[cur]) + float(e[1])
			if not dist.has(nk) or nd < float(dist[nk]):
				dist[nk] = nd
				prev[nk] = cur
				open.append(nk)
	var out := PackedVector2Array([b])
	if not dist.has(goal):
		return PackedVector2Array([a, b])
	var k2 := goal
	while true:
		out.append(nodes[k2])
		if k2 == start or not prev.has(k2):
			break
		k2 = prev[k2]
	out.append(a)
	out.reverse()
	return out


func _sync_buses() -> void:
	for e in _bus_nodes:
		(e["node"] as Node3D).queue_free()
	_bus_nodes.clear()
	var gs = GameState
	var status := TransitSim.all_route_status(gs)
	for r in TransitSim.routes(gs):
		var st: Dictionary = status.get(int(r["id"]), {})
		var n := int(st.get("operating", 0))
		if n <= 0:
			continue
		var path := _route_path(r)
		if path.size() < 2:
			continue
		var cum := TransitSim.poly_cum(path)
		for i in range(n):
			if _bus_nodes.size() >= MAX_BUSES:
				return
			var node := bus_model()
			_buses_root.add_child(node)
			_bus_nodes.append({"node": node, "path": path, "cum": cum, "phase": float(i) / n})
	_place_buses()


func _place_buses() -> void:
	var hour := TimeManager.hour_float()
	var service := hour >= 5.5 and hour <= 21.0
	for e in _bus_nodes:
		var node: Node3D = e["node"]
		var path: PackedVector2Array = e["path"]
		var cum: PackedFloat32Array = e["cum"]
		var total := cum[cum.size() - 1]
		if not service or total < 1.0:
			var p0 := path[0]
			node.position = Vector3(p0.x + 2.0 * float(e["phase"]) * 4.0, _h(p0.x, p0.y), p0.y + 3.0)
			node.rotation.y = 0.0
			continue
		# ~1 vuelta completa cada 2 horas de juego.
		var d := fposmod((hour / 2.0 + float(e["phase"])) * total, total)
		var p := TransitSim.poly_point(path, cum, d)
		var q := TransitSim.poly_point(path, cum, minf(total, d + 1.0))
		var dir := q - p
		if dir.length() < 0.01:
			dir = p - TransitSim.poly_point(path, cum, maxf(0.0, d - 1.0))
		var side := Vector2(-dir.y, dir.x).normalized() * 0.7 if dir.length() > 0.01 else Vector2.ZERO
		node.position = Vector3(p.x - side.x, _h(p.x, p.y) + 0.1, p.y - side.y)
		if dir.length() > 0.01:
			node.rotation.y = atan2(dir.x, dir.y)


func _sync_cars() -> void:
	for ch in _cars_root.get_children():
		ch.queue_free()
	var gs = GameState
	var use: Dictionary = TransitSim.state(gs).get("parking_use", {})
	var cols := [Color(0.7, 0.12, 0.1), Color(0.15, 0.3, 0.6), Color(0.85, 0.85, 0.82), Color(0.2, 0.2, 0.22), Color(0.3, 0.5, 0.3)]
	for b in TransitSim.parkings(gs):
		if int(b.get("level", 1)) > 1:
			continue
		var n := mini(int(use.get(str(b["id"]), 0)), 10)
		var rot := float(b.get("rot", 0.0))
		var basis := Basis(Vector3.UP, rot)
		for i in range(n):
			var row := i / 5
			var col := i % 5
			var local := Vector3(-2.8 + col * 1.4, 0.05, -1.6 if row == 0 else 1.6)
			var car := car_model(cols[(i + int(b["id"])) % cols.size()])
			var pos := Vector3(float(b["x"]), 0, float(b["z"])) + basis * local
			pos.y = _h(pos.x, pos.z) + 0.05
			car.position = pos
			car.rotation.y = rot
			_cars_root.add_child(car)


func _on_day() -> void:
	_sync_buses()
	_sync_cars()


# --- Modo trazado ------------------------------------------------------------------------------

## kind: "road" (arg = tipo de carretera), "trade_road"/"trade_rail" (arg = id del pueblo), "stop", "erase".
func start_trace(kind: String, arg := "") -> void:
	if world and world.has_method("cancel_placement"):
		world.cancel_placement()
	if LogisticsVisuals.instance and LogisticsVisuals.instance.road_mode:
		LogisticsVisuals.instance.cancel_road_mode()
	if UtilitiesVisuals.instance and UtilitiesVisuals.instance.trace_mode:
		UtilitiesVisuals.instance.cancel_trace()
	cancel_trace()
	trace_mode = true
	trace_kind = kind
	trace_arg = arg
	_points = PackedVector2Array()


func cancel_trace() -> void:
	trace_mode = false
	_points = PackedVector2Array()
	_hint = ""
	_clear_ghost()
	if world and world.get("hud"):
		world.hud.set_placement_hint("")


func _clear_ghost() -> void:
	if _ghost:
		_ghost.queue_free()
		_ghost = null


func hint_text() -> String:
	return _hint


func _mouse_ground() -> Variant:
	var cam: Camera3D = world.camera_rig.camera
	var mp := get_viewport().get_mouse_position()
	return _terrain().ray_ground(cam.project_ray_origin(mp), cam.project_ray_normal(mp))


func _pending_points() -> PackedVector2Array:
	var pts := _points.duplicate()
	pts.append(_hover)
	return pts


func _label() -> String:
	match trace_kind:
		"road":
			return RoadSim.kind_label(trace_arg)
		"trade_road":
			return "Camino a %s" % str(TradeSim.town(GameState, trace_arg).get("name", ""))
		"trade_rail":
			return "Vía férrea a %s" % str(TradeSim.town(GameState, trace_arg).get("name", ""))
		"stop":
			return "Paradero de bus"
		_:
			return "Borrar carretera o paradero"


## Actualiza el cursor y la vista previa (también lo usan las pruebas y capturas).
func set_hover(pos: Vector2) -> void:
	var gs = GameState
	_hover = Vector2(snappedf(pos.x, 0.5), snappedf(pos.y, 0.5))
	_clear_ghost()
	var t := _terrain()
	var keys := "clic agrega punto · Retroceso quita el último · clic derecho/Esc/Enter termina"
	match trace_kind:
		"stop":
			var why := TransitSim.stop_block_reason(gs, _hover)
			_hover_ok = why == ""
			_ghost = _stop_model()
			_set_mat(_ghost, MeshLib.ghost_mat(_hover_ok))
			_ghost.position = Vector3(_hover.x, _h(_hover.x, _hover.y), _hover.y)
			add_child(_ghost)
			_hint = "Paradero de bus — %s   %s   (clic coloca · clic derecho/Esc termina)" % [Fmt.money(TransitSim.stop_cost(gs)), "✔" if _hover_ok else why]
		"erase":
			_hover_ok = true
			_ghost = MeshLib.mesh_node(MeshLib.cylinder(3.5, 3.5, 0.2, 16), MeshLib.ghost_mat(false), Vector3(_hover.x, _h(_hover.x, _hover.y) + 0.2, _hover.y))
			add_child(_ghost)
			_hint = "Borrar: clic sobre una carretera (se quita todo su trazado, sin reembolso) o un paradero   (clic derecho/Esc termina)"
		_:
			if _points.is_empty():
				_hover_ok = false
				_hint = "%s: clic en el primer punto%s   (%s)" % [_label(), " (salida del pueblo, cerca de la plaza)" if trace_kind.begins_with("trade") else "", keys]
			else:
				var pts := _pending_points()
				var plan: Dictionary
				if trace_kind == "road":
					plan = TransitSim.road_plan(gs, pts, trace_arg)
				else:
					plan = TransitSim.trade_plan(gs, trace_arg, pts, trace_kind == "trade_rail")
				var reason := str(plan["reason"])
				_hover_ok = reason == ""
				var line: PackedVector2Array = plan["points"]
				if line.size() < 2:
					line = pts
				var gm := MeshLib.ghost_mat(_hover_ok)
				if trace_kind == "trade_rail":
					_ghost = rail_node(t, line, 0.0, -1.0, gm)
				else:
					_ghost = _road_strip(t, line, trace_arg if trace_kind == "road" else "barro", gm)
				for p in _points:
					_ghost.add_child(MeshLib.mesh_node(MeshLib.cached("trace_dot", func(): return MeshLib.cylinder(0.5, 0.5, 0.6, 8)), MeshLib.ghost_mat(true), Vector3(p.x, _h(p.x, p.y) + 0.3, p.y)))
				add_child(_ghost)
				var info := ""
				if trace_kind == "road":
					var c: Dictionary = plan["cost"]
					info = "%d m · %s%s%s" % [int(float(plan["length"])), Fmt.money(float(c.get("total", 0.0))),
						" (%d piedra)" % int(c.get("stone", 0.0)) if float(c.get("stone", 0.0)) > 0.0 else "",
						" · puente %d m" % int(float(plan["bridge"])) if float(plan["bridge"]) > 0.5 else ""]
				else:
					info = "%d m en el mapa · distancia ×%.2f · %s%s" % [int(float(plan["length"])), float(plan["factor"]),
						{"open": "abrir ruta ", "rail": "construir vía ", "reroute": "nuevo trazado "}.get(str(plan["mode"]), ""), Fmt.money(float(plan["fee"]))]
				_hint = "%s — %d puntos · %s   %s   (%s)" % [_label(), _points.size(), info, "✔" if _hover_ok else reason, keys]
	if world and world.get("hud"):
		world.hud.set_placement_hint(_hint)


func _set_mat(node: Node, m: Material) -> void:
	if node is MeshInstance3D:
		node.material_override = m
	for ch in node.get_children():
		_set_mat(ch, m)


func _toast(text: String, cat := "jugador") -> void:
	if text != "" and world and world.get("hud"):
		world.hud.toast(text, cat)


## Clic: agrega un punto (o coloca el paradero / borra).
func add_point() -> void:
	var gs = GameState
	match trace_kind:
		"stop":
			var r := TransitSim.add_stop(gs, _hover)
			if r.has("error"):
				_toast(str(r["error"]))
			else:
				_rebuild_stops()
				_sync_buses()
			return
		"erase":
			var msg := TransitSim.erase_at(gs, _hover)
			_toast(msg if msg != "" else "No hay carretera ni paradero ahí.", "construccion" if msg != "" else "jugador")
			rebuild()
			if LogisticsVisuals.instance:
				LogisticsVisuals.instance.rebuild_roads()
			return
	if _points.size() >= int(TransitSim.sub("road_trace").get("max_points", 60)):
		_toast("Demasiados puntos: termina el trazado")
		return
	if not _points.is_empty() and _points[_points.size() - 1].distance_to(_hover) < 1.0:
		return
	_points.append(_hover)


func remove_last_point() -> void:
	if not _points.is_empty():
		_points.remove_at(_points.size() - 1)


## Termina el trazado: construye con los puntos puestos (si hay menos de dos, cancela).
func finish() -> void:
	if trace_kind in ["stop", "erase"] or _points.size() < 2:
		cancel_trace()
		return
	var gs = GameState
	var err := ""
	match trace_kind:
		"road":
			err = TransitSim.build_road(gs, _points, trace_arg)
			if err == "":
				_toast("Carretera construida.", "construccion")
				_rebuild_roads()
				if LogisticsVisuals.instance:
					LogisticsVisuals.instance.rebuild_roads()
		"trade_road", "trade_rail":
			err = TransitSim.set_trade_path(gs, trace_arg, _points, trace_kind == "trade_rail")
			if err == "":
				_toast("Trazado guardado.", "construccion")
				var tv = world.get_node_or_null("TradeVisuals") if world else null
				if tv and tv.has_method("refresh"):
					tv.refresh()
	if err != "":
		_toast(err)
		return
	cancel_trace()


func _unhandled_input(event: InputEvent) -> void:
	if not trace_mode:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			add_point()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			finish()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_BACKSPACE:
			remove_last_point()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			finish()
			get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	# Esc se atiende antes que el HUD (que abriría el menú de pausa).
	if trace_mode and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		finish()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if trace_mode:
		if world and str(world.get("place_type")) != "":
			cancel_trace()
		else:
			var g = _mouse_ground()
			if g != null:
				var p: Vector3 = g
				set_hover(Vector2(p.x, p.z))
	_timer += delta
	if _timer >= 0.5:
		_timer = 0.0
		if _signature() != _road_sig:
			_rebuild_roads()
			_sync_buses()
		var gs = GameState
		if "%d|%d" % [TransitSim.stops(gs).size(), TransitSim.routes(gs).size()] != _stops_sig:
			_rebuild_stops()
			_sync_buses()
	if not _bus_nodes.is_empty() and Engine.get_process_frames() % 3 == 0:
		_place_buses()
