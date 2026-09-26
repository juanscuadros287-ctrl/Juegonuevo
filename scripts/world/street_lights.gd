class_name StreetLights
extends Node3D
## Faroles en la plaza y a lo largo de las carreteras (docs/GRAFICOS.md). Postes y faroles van en
## MultiMesh (dos llamadas de dibujo para todo el pueblo); la pantalla del farol es emisiva y se
## enciende de noche (MeshLib.glow_mat + MeshLib.set_night). En calidad Alta con Forward+ se
## añaden luces reales (OmniLight3D) en los faroles más cercanos a la plaza.
## Se reconstruye solo cuando cambian las carreteras.

const SPACING := 18.0
const MAX_REAL_LIGHTS := 10

var world: Node3D
var _sig := ""
var _timer := 0.0
var _posts: MultiMeshInstance3D
var _heads: MultiMeshInstance3D
var _lights: Node3D
var _pools: MultiMeshInstance3D
var _pool_mat: ShaderMaterial
var _spots: Array[Vector3] = []
var _real := false


func _ready() -> void:
	add_to_group(GraphicsSettings.GROUP)


func setup(p_world: Node3D) -> void:
	world = p_world
	name = "StreetLights"
	_posts = MultiMeshInstance3D.new()
	_posts.material_override = MeshLib.mat(Color(0.16, 0.16, 0.17), 0.6)
	add_child(_posts)
	_heads = MultiMeshInstance3D.new()
	_heads.material_override = MeshLib.glow_mat(Color(1.0, 0.78, 0.45), 0.05, 3.2)
	_heads.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_heads)
	_pool_mat = ShaderMaterial.new()
	_pool_mat.shader = load("res://shaders/light_pool.gdshader")
	_pools = MultiMeshInstance3D.new()
	_pools.material_override = _pool_mat
	_pools.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pools.visible = false
	add_child(_pools)
	_lights = Node3D.new()
	add_child(_lights)
	_real = bool(GraphicsSettings.profile().get("lamp_lights", false))
	rebuild()


func _signature() -> String:
	return "%d|%d|%d" % [int(GameState.logistics.get("road_version", 0)), RoadSim.roads(GameState).size(), TransitSim.polys(GameState).size()]


static func _post_mesh() -> Mesh:
	return MeshLib.cached("__lamp_post", func():
		var b := MeshLib.Buf.new()
		var id := Transform3D()
		b.add(MeshLib.cylinder(0.14, 0.18, 0.3, 6), Transform3D(Basis(), Vector3(0, 0.15, 0)), Color.WHITE, 0)
		b.add(MeshLib.cylinder(0.05, 0.07, 3.2, 6), Transform3D(Basis(), Vector3(0, 1.9, 0)), Color.WHITE, 0)
		b.box(Vector3(0.25, 3.45, 0), Vector3(0.6, 0.06, 0.06), id, Color.WHITE, 0)
		b.add(MeshLib.cylinder(0.02, 0.2, 0.18, 6), Transform3D(Basis(), Vector3(0.5, 3.52, 0)), Color.WHITE, 0)
		var m := b.commit()
		m.surface_set_material(0, null)
		return m)


static func _head_mesh() -> Mesh:
	return MeshLib.cached("__lamp_head", func(): return MeshLib.cylinder(0.12, 0.09, 0.26, 6))


func rebuild() -> void:
	_sig = _signature()
	_spots.clear()
	var xs: Array[Transform3D] = []
	var t: Terrain = world.terrain
	# Plaza: seis faroles alrededor.
	for k in range(6):
		var a := TAU * k / 6.0 + 0.26
		var p := Vector2(sin(a), cos(a)) * 8.6
		xs.append(Transform3D(Basis(Vector3.UP, a + PI * 0.5), Vector3(p.x, t.height_at(p.x, p.y), p.y)))
	# Carreteras trazadas por puntos.
	for poly in TransitSim.polys(GameState):
		var segs := TransitSim.poly_segments(GameState, int(poly["id"]))
		if segs.is_empty():
			continue
		var pts := PackedVector2Array([RoadSim.seg_a(segs[0])])
		for s in segs:
			pts.append(RoadSim.seg_b(s))
		var width := float(RoadSim.kind_def(str(segs[0]["kind"])).get("width", 2.4))
		_along(t, pts, width, xs)
	# Caminos automáticos (casa → plaza): un farol por tramo largo.
	for r in RoadSim.roads(GameState):
		if r.has("poly"):
			continue
		var pts2 := PackedVector2Array([RoadSim.seg_a(r), RoadSim.seg_b(r)])
		_along(t, pts2, float(RoadSim.kind_def(str(r["kind"])).get("width", 2.2)), xs)
	_posts.multimesh = _mm(_post_mesh(), xs, Transform3D())
	_heads.multimesh = _mm(_head_mesh(), xs, Transform3D(Basis(), Vector3(0.5, 3.33, 0)))
	var pool_x: Array[Transform3D] = []
	for x in xs:
		_spots.append(x * Vector3(0.5, 3.2, 0))
		var g := x * Vector3(0.5, 0, 0)
		pool_x.append(Transform3D(Basis(), Vector3(g.x, t.height_at(g.x, g.z) + 0.05, g.z)))
	_pools.multimesh = _mm(MeshLib.cached("__pool", func():
		var pm := PlaneMesh.new()
		pm.size = Vector2(9.0, 9.0)
		return pm), pool_x, Transform3D())
	_rebuild_real()


func _along(t: Terrain, pts: PackedVector2Array, width: float, xs: Array[Transform3D]) -> void:
	var cum := TransitSim.poly_cum(pts)
	var total := cum[cum.size() - 1] if cum.size() > 0 else 0.0
	if total < 8.0:
		return
	var d := SPACING * 0.5
	var side := 1.0
	while d < total - 3.0:
		var a := TransitSim.poly_point(pts, cum, maxf(0.0, d - 0.5))
		var b := TransitSim.poly_point(pts, cum, minf(total, d + 0.5))
		var dir := (b - a).normalized() if (b - a).length() > 0.001 else Vector2(1, 0)
		var perp := Vector2(-dir.y, dir.x) * side
		var p := TransitSim.poly_point(pts, cum, d) + perp * (width * 0.5 + 0.7)
		var h := t.height_at(p.x, p.y)
		if h > t.water_level + 0.3 and p.length() > 10.0:
			# El brazo del farol apunta hacia la calzada.
			var arm := -perp
			xs.append(Transform3D(Basis(Vector3.UP, atan2(-arm.y, arm.x)), Vector3(p.x, h - 0.05, p.y)))
		d += SPACING
		side = -side


static func _mm(mesh: Mesh, xs: Array[Transform3D], offset: Transform3D) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xs.size()
	for i in range(xs.size()):
		mm.set_instance_transform(i, xs[i] * offset)
	return mm


func _rebuild_real() -> void:
	for ch in _lights.get_children():
		ch.queue_free()
	if not _real:
		return
	var spots := _spots.duplicate()
	spots.sort_custom(func(a: Vector3, b: Vector3): return Vector2(a.x, a.z).length() < Vector2(b.x, b.z).length())
	for i in range(mini(MAX_REAL_LIGHTS, spots.size())):
		var l := OmniLight3D.new()
		l.position = spots[i] - Vector3(0, 0.3, 0)
		l.omni_range = 9.0
		l.light_color = Color(1.0, 0.78, 0.5)
		l.shadow_enabled = false
		l.light_energy = 0.0
		_lights.add_child(l)


func apply_graphics(p: Dictionary) -> void:
	var r := bool(p.get("lamp_lights", false))
	if r != _real:
		_real = r
		_rebuild_real()


func _process(delta: float) -> void:
	_timer += delta
	if _timer < 1.0:
		return
	_timer = 0.0
	if _signature() != _sig:
		rebuild()
	var e := MeshLib.night() * 1.6
	_pool_mat.set_shader_parameter("night", MeshLib.night())
	_pools.visible = MeshLib.night() > 0.02
	for l in _lights.get_children():
		(l as OmniLight3D).light_energy = e
		(l as OmniLight3D).visible = e > 0.02
