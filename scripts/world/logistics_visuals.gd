class_name LogisticsVisuals
extends Node3D
## Visuales 3D de la Fase 6: marcadores de yacimientos, carreteras sobre el terreno,
## modo de construcción de carreteras y agentes de transporte (cargadores con bulto,
## carretas con caballo y camiones) recorriendo las rutas. world.gd llama setup(world).

const PIECE := 4.0          # largo máximo de cada tablón de carretera
const MAX_AGENTS_PER_SHIPMENT := 3

static var instance: LogisticsVisuals

var world: Node3D
var _deposits_root: Node3D
var _roads_root: Node3D
var _agents_root: Node3D
var _deposit_nodes := {}    # id -> Node3D
var _agents := {}           # clave de envío -> Array[Node3D]
var _show_deposits := true
var _timer := 0.0
# Modo carretera
var road_mode := false
var road_kind := "barro"
var _road_start = null      # Vector2 o null
var _ghost: Node3D
var _hover := Vector2.ZERO
var _hover_ok := false
var _hover_reason := ""


func setup(p_world: Node3D) -> void:
	world = p_world
	instance = self
	name = "LogisticsVisuals"
	_deposits_root = Node3D.new()
	add_child(_deposits_root)
	_roads_root = Node3D.new()
	add_child(_roads_root)
	_agents_root = Node3D.new()
	add_child(_agents_root)
	rebuild_deposits()
	rebuild_roads()
	EventBus.day_passed.connect(_on_day)
	EventBus.building_changed.connect(func(_id): _update_deposit_visibility())
	EventBus.building_removed.connect(func(_id): _update_deposit_visibility())
	EventBus.jump_finished.connect(func(_r):
		rebuild_deposits()
		rebuild_roads())


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _terrain() -> Terrain:
	return world.terrain if world else null


func _h(x: float, z: float) -> float:
	var t := _terrain()
	return maxf(t.height_at(x, z), t.water_level) if t else 0.0


# --- Yacimientos ------------------------------------------------------------------------------

func rebuild_deposits() -> void:
	for ch in _deposits_root.get_children():
		ch.queue_free()
	_deposit_nodes.clear()
	for d in RegionSim.deposits(GameState):
		var node := _deposit_marker(str(d["type"]))
		var x := float(d["x"])
		var z := float(d["z"])
		node.position = Vector3(x, _h(x, z), z)
		_deposits_root.add_child(node)
		_deposit_nodes[int(d["id"])] = node
	_update_deposit_visibility()


## Montón de rocas con vetas del color del mineral y un poste con banderín (visible de lejos).
func _deposit_marker(type: String) -> Node3D:
	var root := Node3D.new()
	var col := RegionSim.resource_color(type)
	var ore := MeshLib.mat(col, 0.4)
	var rock := MeshLib.mat(Color(0.45, 0.43, 0.4))
	var rock_mesh := MeshLib.cached("dep_rock", func(): return MeshLib.sphere(0.8, 6, 3))
	var crystal := MeshLib.cached("dep_crystal", func(): return MeshLib.cylinder(0.0, 0.35, 1.1, 5))
	for p in [Vector3(0, 0.2, 0), Vector3(1.1, 0.1, 0.5), Vector3(-0.9, 0.1, 0.7), Vector3(0.3, 0.1, -1.0)]:
		var r := MeshLib.mesh_node(rock_mesh, rock, p)
		r.scale = Vector3(1.0, 0.6, 1.0)
		root.add_child(r)
	for p in [Vector3(0.2, 0.9, 0.1), Vector3(-0.5, 0.7, 0.5), Vector3(0.9, 0.6, 0.3), Vector3(0.5, 0.6, -0.7)]:
		var c := MeshLib.mesh_node(crystal, ore, p)
		c.rotation = Vector3(randf_range(-0.4, 0.4), randf() * TAU, randf_range(-0.4, 0.4))
		root.add_child(c)
	root.add_child(MeshLib.mesh_node(MeshLib.cached("dep_pole", func(): return MeshLib.box(Vector3(0.12, 4.0, 0.12))), MeshLib.mat(Color(0.35, 0.24, 0.14)), Vector3(-1.6, 2.0, -0.4)))
	root.add_child(MeshLib.mesh_node(MeshLib.cached("dep_flag", func(): return MeshLib.box(Vector3(1.1, 0.7, 0.05))), MeshLib.mat(col), Vector3(-1.0, 3.6, -0.4)))
	var label := Label3D.new()
	label.text = RegionSim.resource_label(type)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 48
	label.pixel_size = 0.02
	label.outline_size = 8
	label.modulate = col.lightened(0.35)
	label.position = Vector3(-1.6, 4.8, -0.4)
	root.add_child(label)
	return root


func _update_deposit_visibility() -> void:
	for d in RegionSim.deposits(GameState):
		var node: Node3D = _deposit_nodes.get(int(d["id"]))
		if node == null:
			continue
		var covered := false
		for b in GameState.buildings:
			if Vector2(float(b["x"]), float(b["z"])).distance_to(Vector2(float(d["x"]), float(d["z"]))) < 3.5:
				covered = true
				break
		node.visible = _show_deposits and float(d["amount"]) > 0.0 and not covered


func toggle_deposits() -> void:
	_show_deposits = not _show_deposits
	_update_deposit_visibility()


# --- Carreteras ------------------------------------------------------------------------------

func rebuild_roads() -> void:
	for ch in _roads_root.get_children():
		ch.queue_free()
	for r in RoadSim.roads(GameState):
		_roads_root.add_child(_road_node(RoadSim.seg_a(r), RoadSim.seg_b(r), str(r["kind"])))


## Tramo de carretera siguiendo el terreno: tablones cortos inclinados según la pendiente.
func _road_node(a: Vector2, b: Vector2, kind: String, material: Material = null) -> Node3D:
	var root := Node3D.new()
	var kd := RoadSim.kind_def(kind)
	var width := float(kd.get("width", 2.2))
	var mat: Material = material if material else MeshLib.mat(MeshLib.arr_color(kd.get("color"), Color(0.5, 0.4, 0.3)))
	var unit := MeshLib.cached("road_unit", func(): return MeshLib.box(Vector3.ONE))
	var length := a.distance_to(b)
	var n := maxi(1, int(ceil(length / PIECE)))
	var dir := (b - a) / maxf(0.001, length)
	for i in range(n):
		var p0 := a + dir * (length * i / n)
		var p1 := a + dir * (length * (i + 1) / n)
		var h0 := _h(p0.x, p0.y)
		var h1 := _h(p1.x, p1.y)
		var mid := (p0 + p1) * 0.5
		var seg_len := p0.distance_to(p1)
		var piece := MeshLib.mesh_node(unit, mat, Vector3(mid.x, maxf((h0 + h1) * 0.5, _h(mid.x, mid.y)) + 0.07, mid.y))
		piece.rotation = Vector3(-atan2(h1 - h0, seg_len), atan2(dir.x, dir.y), 0)
		piece.scale = Vector3(width, 0.1, seg_len + 0.35)
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(piece)
	return root


func start_road_mode(kind: String) -> void:
	if world and world.has_method("cancel_placement"):
		world.cancel_placement()
	cancel_road_mode()
	road_mode = true
	road_kind = kind
	_road_start = null


func cancel_road_mode() -> void:
	road_mode = false
	_road_start = null
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	if world and world.get("hud"):
		world.hud.set_placement_hint("")


func _mouse_ground() -> Variant:
	var cam: Camera3D = world.camera_rig.camera
	var mp := get_viewport().get_mouse_position()
	return _terrain().ray_ground(cam.project_ray_origin(mp), cam.project_ray_normal(mp))


func _update_road_ghost() -> void:
	var g = _mouse_ground()
	if g == null:
		return
	var p: Vector3 = g
	_hover = RoadSim.snap(GameState, Vector2(snappedf(p.x, 0.5), snappedf(p.z, 0.5)))
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	if _road_start == null:
		_hover_ok = false
		_hover_reason = ""
		world.hud.set_placement_hint("%s: clic en el punto de inicio del tramo   (clic derecho o Esc termina)" % RoadSim.kind_label(road_kind))
		return
	var a: Vector2 = _road_start
	_hover_reason = RoadSim.block_reason(GameState, a, _hover, road_kind)
	if _hover_reason == "":
		_hover_reason = _water_reason(a, _hover)
	_hover_ok = _hover_reason == ""
	_ghost = _road_node(a, _hover, road_kind, MeshLib.ghost_mat(_hover_ok))
	add_child(_ghost)
	var cost := RoadSim.segment_cost(GameState, a, _hover, road_kind)
	world.hud.set_placement_hint("%s — %d m · %s%s   %s   (clic construye y sigue · clic derecho/Esc termina)" % [
		RoadSim.kind_label(road_kind), int(a.distance_to(_hover)), Fmt.money(float(cost["total"])),
		" (%d piedra)" % int(cost["stone"]) if float(cost["stone"]) > 0.0 else "", "✔" if _hover_ok else _hover_reason])


func _water_reason(a: Vector2, b: Vector2) -> String:
	var t := _terrain()
	var n := maxi(2, int(a.distance_to(b) / 2.0))
	for i in range(n + 1):
		var p := a.lerp(b, float(i) / n)
		if not t.is_land(p.x, p.y, 0.2):
			return "No se puede construir sobre agua (usa un puente)"
	return ""


func _confirm_road_point() -> void:
	if _road_start == null:
		_road_start = _hover
		return
	if not _hover_ok:
		if world.get("hud"):
			world.hud.toast(_hover_reason, "jugador")
		return
	var err := RoadSim.build(GameState, _road_start, _hover, road_kind)
	if err != "":
		world.hud.toast(err, "jugador")
		return
	rebuild_roads()
	_road_start = _hover   # Continúa el camino desde el final del tramo.


func _unhandled_input(event: InputEvent) -> void:
	if not road_mode:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_confirm_road_point()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cancel_road_mode()
			get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	# Esc se atiende antes que el HUD (que abriría el menú de pausa).
	if road_mode and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel_road_mode()
		get_viewport().set_input_as_handled()


# --- Agentes de transporte -------------------------------------------------------------------

func _on_day() -> void:
	_sync_agents()
	if TimeManager.speed <= 2:
		_update_deposit_visibility()


func _ship_key(s: Dictionary) -> String:
	return "%d_%.4f" % [int(s["route"]), float(s["depart"])]


func _sync_agents() -> void:
	var live := {}
	for s in LogisticsSim.shipments(GameState):
		var k := _ship_key(s)
		live[k] = s
		if not _agents.has(k):
			var arr := []
			for i in range(mini(int(s["carriers"]), MAX_AGENTS_PER_SHIPMENT)):
				var m := _carrier_model(str(s["mode"]))
				m.visible = false
				_agents_root.add_child(m)
				arr.append(m)
			_agents[k] = arr
	for k in _agents.keys():
		if not live.has(k):
			for m in _agents[k]:
				m.queue_free()
			_agents.erase(k)
	set_meta("live", live)


func _carrier_model(mode: String) -> Node3D:
	var root := Node3D.new()
	match mode:
		"pie":
			var p := MeshLib.make_person(Color(0.55, 0.45, 0.3), Color(0.8, 0.6, 0.45), Color(0.15, 0.1, 0.08), false)
			root.add_child(p)
			# Bulto a la espalda.
			root.add_child(MeshLib.mesh_node(MeshLib.cached("bundle", func(): return MeshLib.box(Vector3(0.4, 0.45, 0.3))), MeshLib.mat(Color(0.62, 0.5, 0.32)), Vector3(0, 0.75, -0.22)))
		"camion":
			root.add_child(MeshLib.mesh_node(MeshLib.cached("truck_cargo", func(): return MeshLib.box(Vector3(1.4, 1.2, 2.4))), MeshLib.mat(Color(0.3, 0.4, 0.3)), Vector3(0, 1.0, -0.4)))
			root.add_child(MeshLib.mesh_node(MeshLib.cached("truck_cab", func(): return MeshLib.box(Vector3(1.3, 1.0, 1.0))), MeshLib.mat(Color(0.7, 0.2, 0.15)), Vector3(0, 0.9, 1.4)))
			for w in [Vector3(-0.7, 0.35, 1.2), Vector3(0.7, 0.35, 1.2), Vector3(-0.7, 0.35, -1.0), Vector3(0.7, 0.35, -1.0)]:
				var wheel := MeshLib.mesh_node(MeshLib.cached("wheel_s", func(): return MeshLib.cylinder(0.35, 0.35, 0.2, 8)), MeshLib.mat(Color(0.1, 0.1, 0.1)), w)
				wheel.rotation.z = PI * 0.5
				root.add_child(wheel)
		_:
			# Caballo + carreta con carga.
			var horse := MeshLib.mat(Color(0.42, 0.27, 0.15))
			root.add_child(MeshLib.mesh_node(MeshLib.cached("horse_body", func(): return MeshLib.box(Vector3(0.45, 0.55, 1.3))), horse, Vector3(0, 1.0, 1.3)))
			root.add_child(MeshLib.mesh_node(MeshLib.cached("horse_head", func(): return MeshLib.box(Vector3(0.28, 0.55, 0.3))), horse, Vector3(0, 1.45, 2.0)))
			for lx in [-0.15, 0.15]:
				for lz in [0.8, 1.8]:
					root.add_child(MeshLib.mesh_node(MeshLib.cached("horse_leg", func(): return MeshLib.box(Vector3(0.1, 0.75, 0.1))), horse, Vector3(lx, 0.37, lz)))
			root.add_child(MeshLib.mesh_node(MeshLib.cached("cart_bed", func(): return MeshLib.box(Vector3(1.3, 0.35, 1.6))), MeshLib.mat(Color(0.5, 0.36, 0.2)), Vector3(0, 0.75, -0.4)))
			root.add_child(MeshLib.mesh_node(MeshLib.cached("cart_load", func(): return MeshLib.box(Vector3(1.0, 0.5, 1.2))), MeshLib.mat(Color(0.62, 0.52, 0.34)), Vector3(0, 1.15, -0.4)))
			for wx in [-0.72, 0.72]:
				var wheel := MeshLib.mesh_node(MeshLib.cached("wheel_c", func(): return MeshLib.cylinder(0.45, 0.45, 0.1, 8)), MeshLib.mat(Color(0.3, 0.2, 0.12)), Vector3(wx, 0.45, -0.4))
				wheel.rotation.z = PI * 0.5
				root.add_child(wheel)
	return root


func _process(delta: float) -> void:
	if road_mode:
		_update_road_ghost()
	_timer += delta
	if _timer >= 0.5:
		_timer = 0.0
		_sync_agents()
	if _agents.is_empty() or not has_meta("live"):
		return
	var live: Dictionary = get_meta("live")
	var now: float = float(GameState.today()) + TimeManager.hour_float() / 24.0
	for k in _agents:
		var s: Dictionary = live.get(k, {})
		if s.is_empty():
			continue
		var travel := maxf(0.001, float(s["travel"]))
		var t := now - float(s["depart"])
		var leg := int(floor(t / travel))
		var models: Array = _agents[k]
		if t < 0.0 or leg >= 2 * int(s["trips"]):
			for m in models:
				m.visible = false
			continue
		var frac := fposmod(t, travel) / travel
		var a := Vector2(float(s["ax"]), float(s["az"]))
		var b := Vector2(float(s["bx"]), float(s["bz"]))
		var going := leg % 2 == 0
		var p := a.lerp(b, frac) if going else b.lerp(a, frac)
		var dir := (b - a) if going else (a - b)
		var side := Vector2(-dir.y, dir.x).normalized()
		for i in range(models.size()):
			var m: Node3D = models[i]
			var q := p + side * (i - (models.size() - 1) * 0.5) * 1.6 - dir.normalized() * i * 1.2
			m.position = Vector3(q.x, _h(q.x, q.y), q.y)
			m.rotation.y = atan2(dir.x, dir.y)
			m.visible = true
