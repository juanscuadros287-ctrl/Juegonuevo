class_name LogisticsVisuals
extends Node3D
## Visuales 3D de la Fase 6: marcadores de yacimientos, carreteras sobre el terreno,
## modo de construcción de carreteras, agentes de transporte (cargadores con bulto, carretas
## con caballo, carros de vapor, camiones y tráileres) recorriendo las rutas y el vínculo
## fábrica ↔ almacén: anillo y banderín VERDE en los negocios con almacén al lado (rojo si no
## tienen), flecha verde hacia su almacén y etiqueta en cada almacén con su ocupación.
## En modo construir/mover, world.gd llama placement_feedback() para pintar el ghost de verde
## brillante (queda al lado de un almacén) o ámbar (sin almacén) y dibujar la flecha.
## world.gd llama setup(world).

const PIECE := 4.0          # largo máximo de cada tablón de carretera
const MAX_AGENTS_PER_SHIPMENT := 3

static var instance: LogisticsVisuals
static var _link_mats := {}

var world: Node3D
var _deposits_root: Node3D
var _roads_root: Node3D
var _agents_root: Node3D
var _links_root: Node3D
var _links_dirty := false
var _show_links := true
var _wh_labels := {}        # id de almacén -> Label3D
var _place_root: Node3D     # flechas del modo construir/mover
var _place_text := ""
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
	_links_root = Node3D.new()
	_links_root.name = "WarehouseLinks"
	add_child(_links_root)
	rebuild_deposits()
	rebuild_roads()
	rebuild_links()
	EventBus.day_passed.connect(_on_day)
	EventBus.building_changed.connect(func(_id):
		_update_deposit_visibility()
		_links_dirty = true)
	EventBus.building_removed.connect(func(_id):
		_update_deposit_visibility()
		_links_dirty = true)
	EventBus.jump_finished.connect(func(_r):
		rebuild_deposits()
		rebuild_roads()
		rebuild_links())


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
	MeshLib.style_label(label, 110.0, 0.5, 0.8)   # Mapa v2: yacimientos más pequeños y solo de cerca
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
		if r.has("poly"):
			continue   # Las carreteras por puntos las dibuja TransitVisuals (franja continua).
		_roads_root.add_child(_road_node(RoadSim.seg_a(r), RoadSim.seg_b(r), str(r["kind"])))


## Tramo de carretera siguiendo el terreno: franja continua con tapas redondas (RoadMesh).
func _road_node(a: Vector2, b: Vector2, kind: String, material: Material = null) -> Node3D:
	var kd := RoadSim.kind_def(kind)
	return RoadMesh.road_node(_terrain(), PackedVector2Array([a, b]), kind, float(kd.get("width", 2.2)), material)


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


# --- Vínculos fábrica ↔ almacén (indicador verde) ----------------------------------------------

const LINK_GREEN := Color(0.25, 0.95, 0.35)
const LINK_RED := Color(0.95, 0.3, 0.22)


## Material sin sombreado (se ve igual de día y de noche).
static func _flat_mat(key: String, col: Color, alpha := 1.0) -> StandardMaterial3D:
	var k := "__link_%s" % key
	if _link_mats.has(k):
		return _link_mats[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = false
	_link_mats[k] = m
	return m


## Ghost verde brillante: la fábrica queda al lado de un almacén.
static func link_ghost_mat() -> StandardMaterial3D:
	return _flat_mat("ghost_ok", Color(0.1, 1.0, 0.25), 0.62)


## Ghost ámbar: posición válida pero SIN almacén al lado.
static func nolink_ghost_mat() -> StandardMaterial3D:
	return _flat_mat("ghost_nolink", Color(1.0, 0.72, 0.15), 0.5)


func _ring(radius: float, col_key: String, col: Color) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = radius
	t.outer_radius = radius + 0.7
	t.rings = 24
	t.ring_segments = 4
	var m := MeshLib.mesh_node(t, _flat_mat(col_key, col))
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


## Línea (tablones finos siguiendo el terreno) con una flecha en el extremo `b`.
func _link_line(a: Vector2, b: Vector2, mat: Material, arrow := true) -> Node3D:
	var root := Node3D.new()
	var unit := MeshLib.cached("link_unit", func(): return MeshLib.box(Vector3.ONE))
	var length := a.distance_to(b)
	if length < 0.5:
		return root
	var dir := (b - a) / length
	var n := maxi(1, int(ceil(length / 3.0)))
	for i in range(n):
		var p0 := a + dir * (length * i / n)
		var p1 := a + dir * (length * (i + 1) / n)
		var h0 := _h(p0.x, p0.y)
		var h1 := _h(p1.x, p1.y)
		var mid := (p0 + p1) * 0.5
		var seg := p0.distance_to(p1)
		var piece := MeshLib.mesh_node(unit, mat, Vector3(mid.x, maxf((h0 + h1) * 0.5, _h(mid.x, mid.y)) + 0.35, mid.y))
		piece.rotation = Vector3(-atan2(h1 - h0, seg), atan2(dir.x, dir.y), 0)
		piece.scale = Vector3(0.5, 0.15, seg * 0.7)
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(piece)
	if arrow:
		var tip := MeshLib.mesh_node(MeshLib.cached("link_arrow", func(): return MeshLib.cylinder(0.0, 1.0, 1.8, 6)), mat,
				Vector3(b.x, _h(b.x, b.y) + 0.45, b.y))
		# El cono apunta en +Y: se acuesta hacia la dirección del almacén.
		tip.rotation = Vector3(PI * 0.5, atan2(dir.x, dir.y), 0)
		tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(tip)
	return root


## Punto del borde de la huella de un almacén hacia `from` (para que la flecha no quede adentro).
func _edge_point(wid: int, from: Vector2) -> Vector2:
	var c := WarehouseSim.pos_of(GameState, wid)
	var h := WarehouseSim.half_of(GameState, wid)
	var d := from - c
	if d.length() < 0.01:
		return c
	var k := h / maxf(absf(d.x), absf(d.y))
	return c + d * minf(1.0, k)


## Banderín verde (o rojo) sobre el negocio.
func _pennant(col_key: String, col: Color, fp: float) -> Node3D:
	var root := Node3D.new()
	root.add_child(MeshLib.mesh_node(MeshLib.cached("link_pole", func(): return MeshLib.box(Vector3(0.14, 4.4, 0.14))), MeshLib.mat(Color(0.3, 0.22, 0.12)), Vector3(-fp * 0.5, 2.2, fp * 0.5)))
	root.add_child(MeshLib.mesh_node(MeshLib.cached("link_flag", func(): return MeshLib.prism(Vector3(1.1, 1.6, 0.08))), _flat_mat(col_key, col), Vector3(-fp * 0.5 + 0.8, 3.9, fp * 0.5)))
	(root.get_child(1) as Node3D).rotation.z = -PI * 0.5
	return root


func rebuild_links() -> void:
	_links_dirty = false
	if _links_root == null:
		return
	for ch in _links_root.get_children():
		_links_root.remove_child(ch)   # Libera el nombre (link_<id>) para los nodos nuevos.
		ch.queue_free()
	_wh_labels.clear()
	if not _show_links:
		return
	var gs = GameState
	var green := _flat_mat("green", LINK_GREEN)
	for b in gs.buildings:
		if not WarehouseSim.is_linkable(gs, b):
			continue
		var p := Vector2(float(b["x"]), float(b["z"]))
		var fp := float(gs.building_def(b).get("footprint", 4.0))
		var wid := WarehouseSim.warehouse_for(gs, b)
		var node := Node3D.new()
		node.position = Vector3(p.x, _h(p.x, p.y) + 0.12, p.y)
		node.name = "link_%d" % int(b["id"])
		node.set_meta("warehouse", wid)
		node.add_child(_ring(fp * 0.62, "green" if wid >= 0 else "red", LINK_GREEN if wid >= 0 else LINK_RED))
		node.add_child(_pennant("green" if wid >= 0 else "red", LINK_GREEN if wid >= 0 else LINK_RED, fp))
		_links_root.add_child(node)
		if wid >= 0:
			var line := _link_line(p, _edge_point(wid, p), green)
			line.name = "line_%d" % int(b["id"])
			_links_root.add_child(line)
	# Etiqueta sobre cada almacén: ocupación y cuántos negocios abastece.
	for wid in WarehouseSim.ids(gs):
		var wp := WarehouseSim.pos_of(gs, wid)
		var lab := Label3D.new()
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.font_size = 40
		lab.pixel_size = 0.02
		MeshLib.style_label(lab, 200.0, 2.0)
		lab.outline_size = 8
		lab.modulate = Color(0.75, 1.0, 0.75)
		lab.position = Vector3(wp.x, _h(wp.x, wp.y) + (5.5 if wid == WarehouseSim.PLAZA else 8.5), wp.y)
		_links_root.add_child(lab)
		_wh_labels[wid] = lab
	_update_wh_labels()


func _update_wh_labels() -> void:
	var gs = GameState
	for wid in _wh_labels:
		var lab: Label3D = _wh_labels[wid]
		if not is_instance_valid(lab):
			continue
		var n := WarehouseSim.linked_to(gs, wid).size()
		lab.text = "%s\n%s / %s%s" % [WarehouseSim.label_of(gs, wid), Fmt.thousands(WarehouseSim.used_in(gs, wid)), Fmt.thousands(WarehouseSim.capacity_of(gs, wid)),
				"\nabastece %d" % n if n > 0 else ""]


func toggle_links() -> void:
	_show_links = not _show_links
	rebuild_links()


## Modo construir/mover: devuelve el material del ghost según el vínculo con un almacén
## (verde brillante = queda al lado de un almacén, ámbar = sin almacén al lado) y dibuja la
## flecha hacia ese almacén; si se coloca un almacén, flechas hacia los negocios que abastecería.
## Llamado desde world.gd (_update_placement). Devuelve `fallback` si no aplica.
func placement_feedback(type_id: String, pos: Vector3, ignore_id: int, ok: bool, fallback: Material) -> Material:
	clear_placement_feedback()
	_place_text = ""
	var gs = GameState
	var p := Vector2(pos.x, pos.z)
	_place_root = Node3D.new()
	add_child(_place_root)
	if WarehouseSim.type_linkable(type_id):
		var n := WarehouseSim.nearest_for(gs, type_id, pos.x, pos.z, ignore_id)
		if not n.is_empty():
			var wid := int(n["id"])
			_place_root.add_child(_link_line(p, _edge_point(wid, p), _flat_mat("green", LINK_GREEN)))
			_place_text = "   ✔ Al lado de «%s»: guardará y tomará insumos de ahí (%s libres)" % [WarehouseSim.label_of(gs, wid), Fmt.thousands(WarehouseSim.free_in(gs, wid))]
			return link_ghost_mat() if ok else fallback
		_place_text = "   ⚠ Sin almacén al lado (a menos de %d m): la producción quedará en el sitio" % int(WarehouseSim.link_distance())
		return nolink_ghost_mat() if ok else fallback
	if WarehouseSim.type_is_warehouse(type_id):
		var near := WarehouseSim.linkable_near(gs, type_id, pos.x, pos.z, ignore_id)
		for b in near:
			var bp := Vector2(float(b["x"]), float(b["z"]))
			_place_root.add_child(_link_line(bp, p, _flat_mat("green", LINK_GREEN)))
		_place_text = "   ✔ Abastecerá a %d negocio(s) al lado" % near.size() if not near.is_empty() else "   Pon fábricas, minas o campos a menos de %d m" % int(WarehouseSim.link_distance())
		return link_ghost_mat() if ok and not near.is_empty() else fallback
	return fallback


## Texto extra para la pista de colocación (vínculo con almacén).
func placement_text() -> String:
	return _place_text


func clear_placement_feedback() -> void:
	if _place_root:
		_place_root.queue_free()
		_place_root = null


# --- Agentes de transporte -------------------------------------------------------------------

func _on_day() -> void:
	_sync_agents()
	if TimeManager.speed <= 2:
		_update_deposit_visibility()
		_update_wh_labels()


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
		"mula":
			# Mula con alforjas y un arriero al lado.
			var mule := MeshLib.mat(Color(0.45, 0.36, 0.28))
			root.add_child(MeshLib.mesh_node(MeshLib.cached("mule_body", func(): return MeshLib.box(Vector3(0.4, 0.45, 1.1))), mule, Vector3(0, 0.85, 0)))
			root.add_child(MeshLib.mesh_node(MeshLib.cached("mule_head", func(): return MeshLib.box(Vector3(0.24, 0.45, 0.28))), mule, Vector3(0, 1.2, 0.6)))
			for lx in [-0.13, 0.13]:
				for lz in [-0.4, 0.4]:
					root.add_child(MeshLib.mesh_node(MeshLib.cached("mule_leg", func(): return MeshLib.box(Vector3(0.09, 0.65, 0.09))), mule, Vector3(lx, 0.32, lz)))
			for px in [-0.32, 0.32]:
				root.add_child(MeshLib.mesh_node(MeshLib.cached("mule_pack", func(): return MeshLib.box(Vector3(0.25, 0.4, 0.55))), MeshLib.mat(Color(0.62, 0.5, 0.32)), Vector3(px, 0.9, -0.05)))
			var driver := MeshLib.make_person(Color(0.5, 0.42, 0.3), Color(0.8, 0.6, 0.45), Color(0.15, 0.1, 0.08), false)
			driver.position = Vector3(0.7, 0, 0.5)
			root.add_child(driver)
		"carro_vapor":
			# Locomóvil: caldera negra con chimenea y plataforma de carga.
			root.add_child(MeshLib.mesh_node(MeshLib.cached("steam_bed", func(): return MeshLib.box(Vector3(1.4, 0.3, 2.2))), MeshLib.mat(Color(0.4, 0.3, 0.2)), Vector3(0, 0.75, -0.5)))
			root.add_child(MeshLib.mesh_node(MeshLib.cached("steam_load", func(): return MeshLib.box(Vector3(1.2, 0.6, 1.6))), MeshLib.mat(Color(0.6, 0.5, 0.32)), Vector3(0, 1.2, -0.6)))
			var boiler := MeshLib.mesh_node(MeshLib.cached("steam_boiler", func(): return MeshLib.cylinder(0.5, 0.5, 1.4, 10)), MeshLib.mat(Color(0.15, 0.15, 0.16), 0.5), Vector3(0, 1.1, 1.2))
			boiler.rotation.x = PI * 0.5
			root.add_child(boiler)
			root.add_child(MeshLib.mesh_node(MeshLib.cached("steam_stack", func(): return MeshLib.cylinder(0.14, 0.14, 1.0, 6)), MeshLib.mat(Color(0.1, 0.1, 0.1)), Vector3(0, 2.0, 1.6)))
			for w in [Vector3(-0.75, 0.45, 1.2), Vector3(0.75, 0.45, 1.2), Vector3(-0.75, 0.45, -0.9), Vector3(0.75, 0.45, -0.9)]:
				var wheel := MeshLib.mesh_node(MeshLib.cached("wheel_v", func(): return MeshLib.wheel(0.45, 0.14)), MeshLib.mat(Color(0.35, 0.1, 0.08)), w)
				wheel.rotation.z = PI * 0.5
				root.add_child(wheel)
		"trailer":
			root.add_child(MeshLib.mesh_node(MeshLib.cached("trailer_box", func(): return MeshLib.box(Vector3(1.6, 1.6, 4.4))), MeshLib.mat(Color(0.85, 0.85, 0.82)), Vector3(0, 1.35, -1.4)))
			root.add_child(MeshLib.mesh_node(MeshLib.cached("trailer_cab", func(): return MeshLib.box(Vector3(1.5, 1.3, 1.3))), MeshLib.mat(Color(0.15, 0.3, 0.65)), Vector3(0, 1.1, 1.6)))
			for z in [1.5, -0.2, -2.6]:
				for x in [-0.8, 0.8]:
					var wheel := MeshLib.mesh_node(MeshLib.cached("wheel_s", func(): return MeshLib.wheel(0.35, 0.2)), MeshLib.mat(Color(0.1, 0.1, 0.1)), Vector3(x, 0.35, z))
					wheel.rotation.z = PI * 0.5
					root.add_child(wheel)
		"avion":
			# Fase 10: avión de carga low-poly (fuselaje, alas, cola y motores).
			var hull := MeshLib.mat(Color(0.88, 0.89, 0.9))
			root.add_child(MeshLib.mesh_node(MeshLib.cached("plane_body", func(): return MeshLib.box(Vector3(2.2, 2.2, 14.0))), hull, Vector3(0, 0, 0)))
			root.add_child(MeshLib.mesh_node(MeshLib.cached("plane_nose", func(): return MeshLib.box(Vector3(1.6, 1.5, 2.0))), MeshLib.mat(Color(0.2, 0.3, 0.5)), Vector3(0, 0.2, 7.6)))
			root.add_child(MeshLib.mesh_node(MeshLib.cached("plane_wing", func(): return MeshLib.box(Vector3(18.0, 0.35, 3.2))), hull, Vector3(0, 0.3, 0.6)))
			root.add_child(MeshLib.mesh_node(MeshLib.cached("plane_tail_h", func(): return MeshLib.box(Vector3(6.5, 0.3, 1.8))), hull, Vector3(0, 0.8, -6.2)))
			root.add_child(MeshLib.mesh_node(MeshLib.cached("plane_tail_v", func(): return MeshLib.box(Vector3(0.3, 3.2, 2.2))), MeshLib.mat(Color(0.75, 0.2, 0.15)), Vector3(0, 2.4, -6.0)))
			for ex in [-4.5, 4.5]:
				root.add_child(MeshLib.mesh_node(MeshLib.cached("plane_engine", func(): return MeshLib.box(Vector3(0.9, 0.9, 2.2))), MeshLib.mat(Color(0.3, 0.32, 0.35)), Vector3(ex, -0.4, 1.2)))
		"camion":
			root.add_child(MeshLib.mesh_node(MeshLib.cached("truck_cargo", func(): return MeshLib.box(Vector3(1.4, 1.2, 2.4))), MeshLib.mat(Color(0.3, 0.4, 0.3)), Vector3(0, 1.0, -0.4)))
			root.add_child(MeshLib.mesh_node(MeshLib.cached("truck_cab", func(): return MeshLib.box(Vector3(1.3, 1.0, 1.0))), MeshLib.mat(Color(0.7, 0.2, 0.15)), Vector3(0, 0.9, 1.4)))
			for w in [Vector3(-0.7, 0.35, 1.2), Vector3(0.7, 0.35, 1.2), Vector3(-0.7, 0.35, -1.0), Vector3(0.7, 0.35, -1.0)]:
				var wheel := MeshLib.mesh_node(MeshLib.cached("wheel_s", func(): return MeshLib.wheel(0.35, 0.2)), MeshLib.mat(Color(0.1, 0.1, 0.1)), w)
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
				var wheel := MeshLib.mesh_node(MeshLib.cached("wheel_c", func(): return MeshLib.wheel(0.45, 0.1)), MeshLib.mat(Color(0.3, 0.2, 0.12)), Vector3(wx, 0.45, -0.4))
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
		if _links_dirty:
			rebuild_links()
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
			if str(s["mode"]) == "avion":   # Fase 10: sube, cruza y aterriza.
				m.position.y += 4.0 + 36.0 * sin(PI * clampf(frac, 0.0, 1.0))
			m.rotation.y = atan2(dir.x, dir.y)
			m.visible = true
