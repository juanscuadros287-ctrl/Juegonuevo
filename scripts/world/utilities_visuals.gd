class_name UtilitiesVisuals
extends Node3D
## Visuales 3D de las redes de servicios (GridSim/WaterSim, docs/REDES.md):
## - Tendido aéreo: postes de madera con cruceta y aisladores cada POLE_SPACING m y cables colgando.
##   Los tramos tumbados por una tormenta se ven sin cable y con el poste inclinado.
## - Cable subterráneo y tubería: no se ven, salvo en la VISTA DE CAPA (franja naranja o azul en el
##   suelo con registros/válvulas) o mientras se trazan.
## - Vista de capa ("power"/"water"): anillo y banderín VERDE en los edificios conectados, ROJO en los
##   que lo necesitan y no lo están, amarillo/azul en centrales y plantas; etiqueta "Red N" por red.
## - Modo de trazado por tramos (como las carreteras): clic inicio, clic fin y sigue; Esc/clic
##   derecho termina. world.gd llama setup(world).

const POLE_SPACING := 12.0
const WIRE_H := 5.1
const GREEN := Color(0.25, 0.95, 0.35)
const RED := Color(0.95, 0.3, 0.22)
const YELLOW := Color(1.0, 0.85, 0.2)
const BLUE := Color(0.3, 0.65, 1.0)

static var instance: UtilitiesVisuals
static var _mats := {}

var world: Node3D
var layer := ""                 # vista de capa: "", "power", "water"
var _lines_root: Node3D
var _layer_root: Node3D
var _ver := -1
var _dirty := true
var _timer := 0.0
# Trazado
var trace_mode := false
var trace_kind := "aereo"
var _start = null               # Vector2 o null
var _ghost: Node3D
var _hover := Vector2.ZERO
var _hover_ok := false
var _hover_reason := ""


func setup(p_world: Node3D) -> void:
	world = p_world
	instance = self
	name = "UtilitiesVisuals"
	_lines_root = Node3D.new()
	_lines_root.name = "Lines"
	add_child(_lines_root)
	_layer_root = Node3D.new()
	_layer_root.name = "Layer"
	add_child(_layer_root)
	rebuild()
	EventBus.building_changed.connect(func(_id): _dirty = true)
	EventBus.building_removed.connect(func(_id): _dirty = true)
	EventBus.day_passed.connect(func(): if layer != "": _dirty = true)
	EventBus.jump_finished.connect(func(_r): rebuild())


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _terrain() -> Terrain:
	return world.terrain if world else null


func _h(x: float, z: float) -> float:
	var t := _terrain()
	return maxf(t.height_at(x, z), t.water_level) if t else 0.0


static func _flat(key: String, col: Color, alpha := 1.0) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m


# --- Construcción de la escena -------------------------------------------------------------------

func rebuild() -> void:
	_dirty = false
	_ver = int(GridSim.state(GameState).get("version", 0))
	for root in [_lines_root, _layer_root]:
		for ch in root.get_children():
			root.remove_child(ch)
			ch.queue_free()
	var show_layer := layer
	if trace_mode:
		show_layer = GridSim.kind_layer(trace_kind)
	for s in GridSim.segments(GameState):
		var kind := str(s["kind"])
		if bool(GridSim.kind_def(kind).get("visible", false)):
			_lines_root.add_child(_aerial_node(GridSim.seg_a(s), GridSim.seg_b(s), GridSim.is_broken(s)))
		elif GridSim.kind_layer(kind) == show_layer:
			_lines_root.add_child(_buried_node(GridSim.seg_a(s), GridSim.seg_b(s), kind))
	if show_layer != "":
		_build_layer(show_layer)


## Tramo aéreo: postes cada POLE_SPACING m y cables (3 hilos) con comba.
func _aerial_node(a: Vector2, b: Vector2, broken: bool, material: Material = null) -> Node3D:
	var root := Node3D.new()
	var length := a.distance_to(b)
	var n := maxi(1, int(ceil(length / POLE_SPACING)))
	var dir := (b - a) / maxf(0.001, length)
	var pole_parts: Array = GridSim.cfg().get("models", {}).get("pole", [])
	var tops := []
	for i in range(n + 1):
		var p := a + dir * (length * i / n)
		var pole := MeshLib.build_model(pole_parts, 1.0, material)
		pole.position = Vector3(p.x, _h(p.x, p.y), p.y)
		pole.rotation.y = atan2(dir.x, dir.y) + PI * 0.5
		if broken and i == n / 2:
			pole.rotation.z = 0.5
		root.add_child(pole)
		tops.append(Vector3(p.x, _h(p.x, p.y) + WIRE_H, p.y))
	if broken:
		return root
	var side := Vector3(-dir.y, 0, dir.x)
	var wire_mat: Material = material if material else MeshLib.mat(Color(0.12, 0.12, 0.12))
	for off in [-0.75, 0.0, 0.75]:
		for i in range(tops.size() - 1):
			var p0: Vector3 = tops[i] + side * float(off)
			var p1: Vector3 = tops[i + 1] + side * float(off)
			var mid := (p0 + p1) * 0.5 + Vector3(0, -0.45, 0)
			root.add_child(_wire(p0, mid, wire_mat))
			root.add_child(_wire(mid, p1, wire_mat))
	return root


func _wire(p0: Vector3, p1: Vector3, mat: Material) -> MeshInstance3D:
	var unit := MeshLib.cached("wire_unit", func(): return MeshLib.box(Vector3.ONE))
	var mi := MeshLib.mesh_node(unit, mat)
	var d := p1 - p0
	var dl := d.length()
	if dl < 0.01:
		return mi
	mi.transform = Transform3D(Basis.looking_at(d / dl, Vector3.UP) * Basis.from_scale(Vector3(0.05, 0.05, dl)), (p0 + p1) * 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Tramo enterrado (vista de capa): franja de color en el suelo y registros en los extremos.
func _buried_node(a: Vector2, b: Vector2, kind: String, material: Material = null) -> Node3D:
	var root := Node3D.new()
	var col := MeshLib.arr_color(GridSim.kind_def(kind).get("color"), Color(1, 0.5, 0.1))
	var mat: Material = material if material else _flat("buried_" + kind, col, 0.85)
	var unit := MeshLib.cached("buried_unit", func(): return MeshLib.box(Vector3.ONE))
	var length := a.distance_to(b)
	var n := maxi(1, int(ceil(length / 4.0)))
	var dir := (b - a) / maxf(0.001, length)
	for i in range(n):
		var p0 := a + dir * (length * i / n)
		var p1 := a + dir * (length * (i + 1) / n)
		var h0 := _h(p0.x, p0.y)
		var h1 := _h(p1.x, p1.y)
		var mid := (p0 + p1) * 0.5
		var seg := p0.distance_to(p1)
		var piece := MeshLib.mesh_node(unit, mat, Vector3(mid.x, maxf((h0 + h1) * 0.5, _h(mid.x, mid.y)) + 0.12, mid.y))
		piece.rotation = Vector3(-atan2(h1 - h0, seg), atan2(dir.x, dir.y), 0)
		piece.scale = Vector3(0.6, 0.08, seg * 0.8 if i % 2 == 0 else seg * 0.55)
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(piece)
	var model: Array = GridSim.cfg().get("models", {}).get("valve" if GridSim.kind_layer(kind) == GridSim.WATER else "manhole", [])
	for p in [a, b]:
		var m := MeshLib.build_model(model, 1.0, material)
		m.position = Vector3(p.x, _h(p.x, p.y), p.y)
		root.add_child(m)
	return root


func _ring(radius: float, mat: Material) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = radius
	t.outer_radius = radius + 0.6
	t.rings = 24
	t.ring_segments = 4
	var m := MeshLib.mesh_node(t, mat)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


## Estado de un edificio en la capa: "" (no aplica), "ok", "falta", "fuente".
static func building_state(gs, b: Dictionary, lay: String) -> String:
	var def: Dictionary = gs.building_def(b)
	if lay == GridSim.POWER:
		if EnergySim.is_plant(def):
			return "fuente" if gs.owned_by_player(b) else ""
		var uses := (Housing.is_home(b) and EnergySim.homes_active(gs)) or (BusinessSim.is_business(b) and EnergySim.level_demand_kw(def, gs.level_def(b)) > 0.0)
		if not uses and not (Housing.is_home(b) and GridSim.home_missing(gs, b).has(GridSim.POWER)):
			return ""
		var n := GridSim.net_of(gs, b, GridSim.POWER)
		return "ok" if GridSim.connected(gs, b, GridSim.POWER) and GridSim.has_source(gs, GridSim.POWER, n) else "falta"
	if WaterSim.is_water_plant(def):
		return "fuente" if gs.owned_by_player(b) else ""
	if not Housing.is_home(b):
		return ""
	return "ok" if WaterSim.home_piped(gs, b) else "falta"


func _build_layer(lay: String) -> void:
	var gs = GameState
	for b in gs.buildings:
		var state := building_state(gs, b, lay)
		if state == "":
			continue
		var col := GREEN if state == "ok" else (RED if state == "falta" else (YELLOW if lay == GridSim.POWER else BLUE))
		var mat := _flat("layer_" + state + lay, col)
		var fp: float = gs.footprint_of(b)
		var node := Node3D.new()
		node.name = "net_%d" % int(b["id"])
		node.set_meta("state", state)
		var x := float(b["x"])
		var z := float(b["z"])
		node.position = Vector3(x, _h(x, z) + 0.12, z)
		node.add_child(_ring(fp * 0.6, mat))
		var pole := MeshLib.mesh_node(MeshLib.cached("layer_pole", func(): return MeshLib.box(Vector3(0.12, 3.6, 0.12))), MeshLib.mat(Color(0.3, 0.22, 0.12)), Vector3(fp * 0.5, 1.8, -fp * 0.5))
		node.add_child(pole)
		var flag := MeshLib.mesh_node(MeshLib.cached("layer_flag", func(): return MeshLib.box(Vector3(0.9, 0.55, 0.06))), mat, Vector3(fp * 0.5 + 0.5, 3.3, -fp * 0.5))
		node.add_child(flag)
		_layer_root.add_child(node)
	# Etiqueta de cada red (mismo número que el panel).
	var comp := GridSim.components(gs, lay)
	var seen := {}
	var segs: Array = comp["segs"]
	for i in range(segs.size()):
		var n := int(comp["net"][i])
		if seen.has(n):
			continue
		seen[n] = true
		var s: Dictionary = segs[i]
		var mid := (GridSim.seg_a(s) + GridSim.seg_b(s)) * 0.5
		var lab := Label3D.new()
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.font_size = 44
		lab.pixel_size = 0.02
		MeshLib.style_label(lab, 200.0)
		lab.outline_size = 8
		var tie := lay == GridSim.POWER and bool(comp["info"].get(n, {}).get("tie", false))
		lab.text = "Red %d%s" % [n, " · entrada regional" if tie else ""]
		lab.modulate = YELLOW.lightened(0.3) if lay == GridSim.POWER else BLUE.lightened(0.3)
		lab.position = Vector3(mid.x, _h(mid.x, mid.y) + 7.0, mid.y)
		_layer_root.add_child(lab)


## Muestra/oculta la vista de capa ("power" o "water"; la misma otra vez la apaga).
func toggle_layer(lay: String) -> void:
	layer = "" if layer == lay else lay
	rebuild()


func set_layer(lay: String) -> void:
	layer = lay
	rebuild()


# --- Trazado por tramos --------------------------------------------------------------------------

func start_trace(kind: String) -> void:
	if world and world.has_method("cancel_placement"):
		world.cancel_placement()
	if LogisticsVisuals.instance and LogisticsVisuals.instance.road_mode:
		LogisticsVisuals.instance.cancel_road_mode()
	cancel_trace()
	trace_mode = true
	trace_kind = kind
	_start = null
	rebuild()


func cancel_trace() -> void:
	var was := trace_mode
	trace_mode = false
	_start = null
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	if world and world.get("hud"):
		world.hud.set_placement_hint("")
	if was:
		rebuild()


func _mouse_ground() -> Variant:
	var cam: Camera3D = world.camera_rig.camera
	var mp := get_viewport().get_mouse_position()
	return _terrain().ray_ground(cam.project_ray_origin(mp), cam.project_ray_normal(mp))


func _update_trace_ghost() -> void:
	var g = _mouse_ground()
	if g == null:
		return
	var p: Vector3 = g
	set_hover(Vector2(snappedf(p.x, 0.5), snappedf(p.z, 0.5)))


## Actualiza el ghost del tramo hacia `pos` (también lo usan las capturas).
func set_hover(pos: Vector2) -> void:
	var lay := GridSim.kind_layer(trace_kind)
	_hover = GridSim.snap(GameState, pos, lay)
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	var label := GridSim.kind_label(trace_kind)
	if _start == null:
		_hover_ok = false
		world.hud.set_placement_hint("%s: clic en el punto de inicio del tramo (conecta lo que quede a menos de %d m)   (clic derecho o Esc termina)" % [label, int(GridSim.reach(lay))])
		return
	var a: Vector2 = _start
	_hover_reason = GridSim.block_reason(GameState, a, _hover, trace_kind)
	if _hover_reason == "" and GridSim.kind_layer(trace_kind) == GridSim.POWER and trace_kind == "aereo":
		_hover_reason = _water_reason(a, _hover)
	_hover_ok = _hover_reason == ""
	var gm := MeshLib.ghost_mat(_hover_ok)
	_ghost = _aerial_node(a, _hover, false, gm) if bool(GridSim.kind_def(trace_kind).get("visible", false)) else _buried_node(a, _hover, trace_kind, gm)
	add_child(_ghost)
	var near := 0
	for b in GameState.buildings:
		var bp := Vector2(float(b["x"]), float(b["z"]))
		if RoadSim.dist_point_segment(bp, a, _hover) - GameState.footprint_of(b) * 0.5 <= GridSim.reach(lay) and building_state(GameState, b, lay) != "":
			near += 1
	world.hud.set_placement_hint("%s — %d m · %s · alcanza %d edificio(s)   %s   (clic tiende y sigue · clic derecho/Esc termina)" % [
		label, int(a.distance_to(_hover)), Fmt.money(GridSim.segment_cost(GameState, a, _hover, trace_kind)), near, "✔" if _hover_ok else _hover_reason])


func _water_reason(a: Vector2, b: Vector2) -> String:
	var t := _terrain()
	var n := maxi(2, int(a.distance_to(b) / 2.0))
	var wet := 0
	for i in range(n + 1):
		var p := a.lerp(b, float(i) / n)
		if not t.is_land(p.x, p.y, 0.2):
			wet += 1
	# Los postes cruzan ríos angostos, pero no se plantan en el agua.
	return "Los postes no pueden quedar en el agua (usa tramos más cortos)" if wet > n / 2 else ""


func confirm_point() -> void:
	if _start == null:
		_start = _hover
		return
	if not _hover_ok:
		if world.get("hud"):
			world.hud.toast(_hover_reason, "jugador")
		return
	var err := GridSim.build(GameState, _start, _hover, trace_kind)
	if err != "":
		world.hud.toast(err, "jugador")
		return
	rebuild()
	_start = _hover


func _unhandled_input(event: InputEvent) -> void:
	if not trace_mode:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			confirm_point()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cancel_trace()
			get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if trace_mode and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel_trace()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if trace_mode:
		_update_trace_ghost()
	_timer += delta
	if _timer >= 0.5:
		_timer = 0.0
		if _dirty or int(GridSim.state(GameState).get("version", 0)) != _ver:
			rebuild()
