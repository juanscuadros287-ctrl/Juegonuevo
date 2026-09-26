class_name Vegetation
extends Node3D
## Vegetación del pueblo (docs/GRAFICOS.md): reemplaza los conos de Terrain.scatter_nature por
## árboles low-poly con variantes por clima y bioma (coníferas, frondosos, palmeras, arbustos y
## cactus), en MultiMesh por celdas de 100 m (se recortan fuera de cámara y tienen distancia de
## dibujo). Balanceo con el viento en shaders/foliage.gdshader. Además dispersa pasto y flores
## cerca de la cámara (calidad Media y Alta).
##
## No modifica terrain.gd: lee sus posiciones de árboles (tree_positions, _tree_xforms), oculta sus
## MultiMesh de conos del pueblo y registra un "ocultador" en terrain._tree_mms para que
## Terrain.clear_trees() también tale estos árboles al construir o trazar caminos.

const CELL := 100.0
const V_CONIFER := 0
const V_BROAD := 1
const V_PALM := 2
const V_BUSH := 3
const V_CACTUS := 4
const GRASS_COUNT := 1400

var terrain: Terrain
var world: Node3D
var _root: Node3D
var _map := {}                # índice del árbol -> [MultiMesh, índice local]
var _grass: MultiMeshInstance3D
var _grass_center := Vector2(INF, INF)
var _grass_on := true
var _grass_range := 70.0
var _block_sig := ""
var _blocked := {}            # celdas de 3 m ocupadas por caminos o edificios
var _timer := 0.0


class TreeHider:
	extends RefCounted
	var owner_ref: WeakRef

	func set_instance_transform(i: int, xf: Transform3D) -> void:
		var v: Vegetation = owner_ref.get_ref()
		if v != null and v._map.has(i):
			var e: Array = v._map[i]
			(e[0] as MultiMesh).set_instance_transform(int(e[1]), xf)


func _ready() -> void:
	add_to_group(GraphicsSettings.GROUP)


func setup(p_world: Node3D, t: Terrain) -> void:
	world = p_world
	terrain = t
	name = "Vegetation"
	rebuild()
	apply_graphics(GraphicsSettings.profile())


# --- Modelos --------------------------------------------------------------------------------

static func _mesh(v: int) -> Mesh:
	return MeshLib.cached("__veg_%d" % v, func(): return _build_mesh(v))


static func _build_mesh(v: int) -> Mesh:
	var b := MeshLib.Buf.new()
	var trunk := Color(0.42, 0.3, 0.2)
	var id := Transform3D()
	match v:
		V_CONIFER:
			var g := Color(0.16, 0.36, 0.22)
			b.add(MeshLib.cylinder(0.1, 0.17, 1.2, 5), Transform3D(Basis(), Vector3(0, 0.6, 0)), trunk, 0)
			b.add(MeshLib.cylinder(0.0, 1.35, 1.7, 7), Transform3D(Basis(), Vector3(0, 1.75, 0)), g, 0)
			b.add(MeshLib.cylinder(0.0, 1.05, 1.5, 7), Transform3D(Basis(Vector3.UP, 0.4), Vector3(0, 2.6, 0)), g.lightened(0.05), 0)
			b.add(MeshLib.cylinder(0.0, 0.7, 1.3, 7), Transform3D(Basis(Vector3.UP, 0.8), Vector3(0, 3.4, 0)), g.lightened(0.1), 0)
		V_BROAD:
			var g := Color(0.3, 0.5, 0.22)
			b.add(MeshLib.cylinder(0.13, 0.2, 1.8, 6), Transform3D(Basis(), Vector3(0, 0.9, 0)), trunk, 0)
			b.add(MeshLib.cylinder(0.05, 0.08, 0.9, 5), Transform3D(Basis(Vector3.BACK, -0.7), Vector3(0.3, 1.9, 0)), trunk, 0)
			b.add(MeshLib.sphere(1.0, 7, 5), Transform3D(Basis.from_scale(Vector3(1.15, 0.9, 1.1)), Vector3(0, 2.6, 0)), g, 0)
			b.add(MeshLib.sphere(0.75, 6, 4), Transform3D(Basis(), Vector3(0.75, 2.2, 0.3)), g.lightened(0.07), 0)
			b.add(MeshLib.sphere(0.7, 6, 4), Transform3D(Basis(), Vector3(-0.6, 2.3, -0.4)), g.darkened(0.08), 0)
		V_PALM:
			var g := Color(0.32, 0.52, 0.2)
			var p := Vector3.ZERO
			for k in range(5):
				var seg_b := Basis(Vector3.BACK, -0.06 * k)
				b.add(MeshLib.cylinder(0.11 - k * 0.01, 0.14 - k * 0.01, 0.85, 6), Transform3D(seg_b, p + Vector3(0, 0.42, 0)), trunk.lightened(0.1 if k % 2 == 0 else 0.0), 0)
				p += seg_b * Vector3(0, 0.82, 0)
			for k in range(7):
				var yaw := TAU * k / 7.0
				var leaf := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, 0.45)
				b.box(Vector3(0, 0, 0.9), Vector3(0.45, 0.05, 1.8), Transform3D(leaf, p + Vector3(0, 0.05, 0)), g if k % 2 == 0 else g.darkened(0.1), 0)
			b.add(MeshLib.sphere(0.16, 5, 3), Transform3D(Basis(), p), Color(0.4, 0.3, 0.15), 0)
		V_BUSH:
			var g := Color(0.26, 0.44, 0.2)
			b.add(MeshLib.sphere(0.6, 6, 4), Transform3D(Basis.from_scale(Vector3(1.2, 0.8, 1.1)), Vector3(0, 0.4, 0)), g, 0)
			b.add(MeshLib.sphere(0.45, 6, 4), Transform3D(Basis(), Vector3(0.55, 0.32, 0.2)), g.lightened(0.08), 0)
			b.add(MeshLib.sphere(0.4, 6, 4), Transform3D(Basis(), Vector3(-0.4, 0.3, -0.35)), g.darkened(0.06), 0)
		V_CACTUS:
			var g := Color(0.3, 0.5, 0.3)
			b.add(MeshLib.cylinder(0.2, 0.24, 2.4, 7), Transform3D(Basis(), Vector3(0, 1.2, 0)), g, 0)
			b.add(MeshLib.sphere(0.2, 7, 3), Transform3D(Basis(), Vector3(0, 2.4, 0)), g, 0)
			for s: float in [-1.0, 1.0]:
				b.add(MeshLib.cylinder(0.12, 0.12, 0.5, 6), Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(s * 0.4, 1.1 + s * 0.2, 0)), g, 0)
				b.add(MeshLib.cylinder(0.13, 0.13, 0.9, 6), Transform3D(Basis(), Vector3(s * 0.62, 1.5 + s * 0.2, 0)), g.lightened(0.05), 0)
	var m := b.commit()
	m.surface_set_material(0, null)
	return m


static func _grass_mesh() -> Mesh:
	return MeshLib.cached("__grass", func():
		var b := MeshLib.Buf.new()
		var g := Color(0.34, 0.56, 0.24)
		for k in range(4):
			var yaw := TAU * k / 4.0 + 0.3
			b.add(MeshLib.cylinder(0.0, 0.07, 0.45, 3), Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, 0.25), Vector3(sin(yaw) * 0.08, 0.2, cos(yaw) * 0.08)), g.lightened(k * 0.04), 0)
		var m := b.commit()
		m.surface_set_material(0, null)
		return m)


static func _flower_mesh() -> Mesh:
	return MeshLib.cached("__flower", func():
		var b := MeshLib.Buf.new()
		b.add(MeshLib.cylinder(0.015, 0.015, 0.35, 3), Transform3D(Basis(), Vector3(0, 0.17, 0)), Color(0.3, 0.5, 0.2), 0)
		b.add(MeshLib.sphere(0.07, 5, 3), Transform3D(Basis(), Vector3(0, 0.37, 0)), Color(1, 1, 1), 0)
		var m := b.commit()
		m.surface_set_material(0, null)
		return m)


# --- Árboles ---------------------------------------------------------------------------------

func _variant_for(p: Vector2, h: float, r: float) -> int:
	var gen: CountryGen = terrain.gen
	var temp := 0.0
	var biome := CountryGen.B_LLANURA
	if gen != null:
		temp = gen.climate(p.x, p.y, h).x
		biome = gen.biome_id(p.x, p.y, h)
	if biome == CountryGen.B_DESIERTO:
		return V_CACTUS if r < 0.6 else V_BUSH
	if h > 18.0 or temp < -0.2 or biome == CountryGen.B_MONTANA or biome == CountryGen.B_NEVADO:
		return V_CONIFER if r < 0.82 else V_BUSH
	if biome == CountryGen.B_SELVA or (temp > 0.55 and h < terrain.water_level + 4.0):
		return V_PALM if r < 0.35 else (V_BROAD if r < 0.85 else V_BUSH)
	if h < terrain.water_level + 2.0:
		return V_BROAD if r < 0.6 else V_BUSH
	return V_BROAD if r < 0.45 else (V_CONIFER if r < 0.8 else V_BUSH)


func rebuild() -> void:
	if _root:
		_root.queue_free()
	_root = Node3D.new()
	_root.name = "Trees"
	add_child(_root)
	_map.clear()
	if terrain == null or terrain.nature_root == null:
		return
	var xforms: Array = terrain._tree_xforms
	var positions: Array = terrain.tree_positions
	# Oculta los conos del pueblo (tronco y copa) y registra el ocultador para clear_trees().
	var kids := terrain.nature_root.get_children()
	for k in range(mini(2, kids.size())):
		(kids[k] as Node3D).visible = false
	var hider := TreeHider.new()
	hider.owner_ref = weakref(self)
	terrain._tree_mms.append([hider, Transform3D()])
	# Agrupa por celda y variante.
	var groups := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = int(GameState.settings.get("seed", 1)) + 7
	for i in range(mini(xforms.size(), positions.size())):
		var xf: Transform3D = xforms[i]
		var p: Vector2 = positions[i]
		var r := rng.randf()
		var tint_v := rng.randf_range(0.82, 1.15)
		var v := _variant_for(p, xf.origin.y, r)
		var cell := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
		var key := Vector3i(cell.x, cell.y, v)
		if not groups.has(key):
			groups[key] = []
		var dim := 1.0 if terrain.is_unlocked(p.x, p.y) else 0.68
		var s := xf.basis.get_scale()
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s.x, s.y, s.x) * (0.8 if v == V_BUSH else 1.0))
		var tint := Color(tint_v * dim, tint_v * dim * rng.randf_range(0.95, 1.05), tint_v * dim * 0.95)
		(groups[key] as Array).append([i, Transform3D(basis, xf.origin - Vector3(0, 0.05, 0)), tint])
	var p := GraphicsSettings.profile()
	for key in groups:
		var list: Array = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _mesh(key.z)
		mm.instance_count = list.size()
		for j in range(list.size()):
			mm.set_instance_transform(j, list[j][1])
			mm.set_instance_color(j, list[j][2])
			_map[int(list[j][0])] = [mm, j]
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = MeshLib.vertex_color_mat()
		mmi.add_to_group("gfx_tree")
		mmi.visibility_range_end = float(p["tree_range"])
		mmi.visibility_range_end_margin = float(p["tree_range"]) * 0.1
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		_root.add_child(mmi)
	# Árboles ya talados antes de esta reconstrucción.
	var hidden := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	var trunk_mm: MultiMesh = (kids[0] as MultiMeshInstance3D).multimesh if kids.size() > 0 and kids[0] is MultiMeshInstance3D else null
	if trunk_mm:
		for i in range(mini(trunk_mm.instance_count, positions.size())):
			if trunk_mm.get_instance_transform(i).basis.get_scale().length() < 0.001 and _map.has(i):
				(_map[i][0] as MultiMesh).set_instance_transform(int(_map[i][1]), hidden)
	_grass_center = Vector2(INF, INF)


func apply_graphics(p: Dictionary) -> void:
	_grass_on = bool(p.get("grass", true))
	_grass_range = float(p.get("grass_range", 70.0))
	_grass_center = Vector2(INF, INF)
	if _grass:
		_grass.visible = _grass_on


# --- Pasto y flores cerca de la cámara ---------------------------------------------------------

func _block_signature() -> String:
	return "%d|%d|%d" % [int(GameState.logistics.get("road_version", 0)), RoadSim.roads(GameState).size(), GameState.buildings.size()]


func _rebuild_blocked() -> void:
	_block_sig = _block_signature()
	_blocked.clear()
	for r in RoadSim.roads(GameState):
		var a := RoadSim.seg_a(r)
		var b := RoadSim.seg_b(r)
		var n := maxi(1, int(a.distance_to(b) / 1.5))
		for k in range(n + 1):
			var q := a.lerp(b, float(k) / n)
			for dx: int in [-1, 0, 1]:
				for dz: int in [-1, 0, 1]:
					_blocked[Vector2i(floori(q.x / 3.0) + dx, floori(q.y / 3.0) + dz)] = true
	for bld in GameState.buildings:
		var fp := GameState.footprint_of(bld) * 0.6 + 1.0
		var c := Vector2(float(bld["x"]), float(bld["z"]))
		for gx in range(floori((c.x - fp) / 3.0), floori((c.x + fp) / 3.0) + 1):
			for gz in range(floori((c.y - fp) / 3.0), floori((c.y + fp) / 3.0) + 1):
				_blocked[Vector2i(gx, gz)] = true


func _process(delta: float) -> void:
	if terrain == null or world == null or not _grass_on:
		return
	var rig: CameraRig = world.get("camera_rig")
	if rig == null or rig.camera == null or not rig.camera.current:
		return
	_timer += delta
	if _timer < 0.25:
		return
	_timer = 0.0
	var cp := Vector2(rig.position.x, rig.position.z)
	var far := rig.distance > 160.0
	if _grass:
		_grass.visible = not far
	if far:
		return
	if _block_signature() != _block_sig:
		_rebuild_blocked()
		_grass_center = Vector2(INF, INF)
	if cp.distance_to(_grass_center) < _grass_range * 0.3:
		return
	_grass_center = cp
	_scatter_grass(cp)


func _scatter_grass(c: Vector2) -> void:
	if _grass == null:
		_grass = MultiMeshInstance3D.new()
		_grass.name = "Grass"
		_grass.material_override = MeshLib.vertex_color_mat()
		_grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_grass)
		var fl := MultiMeshInstance3D.new()
		fl.name = "Flowers"
		fl.material_override = MeshLib.vertex_color_mat()
		fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_grass.add_child(fl)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(c.x / 10.0) * 7919 + int(c.y / 10.0)
	var gx: Array[Transform3D] = []
	var gc: Array[Color] = []
	var fx: Array[Transform3D] = []
	var fc: Array[Color] = []
	var flower_cols := [Color(0.95, 0.85, 0.3), Color(0.95, 0.95, 0.95), Color(0.85, 0.4, 0.55), Color(0.6, 0.5, 0.9)]
	var r := _grass_range
	for k in range(GRASS_COUNT):
		var q := c + Vector2(rng.randf_range(-r, r), rng.randf_range(-r, r))
		if q.distance_to(Vector2.ZERO) < 9.0 or _blocked.has(Vector2i(floori(q.x / 3.0), floori(q.y / 3.0))):
			continue
		var h := terrain.height_at(q.x, q.y)
		if h < terrain.water_level + 0.8 or h > 22.0:
			continue
		var slope := absf(terrain.height_at(q.x + 1.0, q.y) - h) + absf(terrain.height_at(q.x, q.y + 1.0) - h)
		if slope > 0.8:
			continue
		var s := rng.randf_range(0.7, 1.4)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s)), Vector3(q.x, h - 0.03, q.y))
		if rng.randf() < 0.1:
			fx.append(xf)
			fc.append(flower_cols[rng.randi() % flower_cols.size()])
		else:
			gx.append(xf)
			var g := rng.randf_range(0.85, 1.15)
			gc.append(Color(g, g, g * 0.9))
	_grass.multimesh = _fill(_grass_mesh(), gx, gc)
	(_grass.get_child(0) as MultiMeshInstance3D).multimesh = _fill(_flower_mesh(), fx, fc)
	_grass.visible = _grass_on


static func _fill(mesh: Mesh, xs: Array[Transform3D], cs: Array[Color]) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xs.size()
	for i in range(xs.size()):
		mm.set_instance_transform(i, xs[i])
		mm.set_instance_color(i, cs[i])
	return mm
