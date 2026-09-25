class_name Terrain
extends Node3D
## Terreno procedural low-poly del país (Fase 9A).
## - El chunk del pueblo (400 m, centrado en la plaza) se genera igual que antes: rejilla de 2,5 m
##   (`heights`, RES 160), mismas alturas, río y costa según map_type y semilla. Las zonas sin comprar
##   se ven oscurecidas.
## - El resto del país (CountryGen: chunks de 400 m, 24–40 por lado) se construye por streaming con
##   LOD: alta resolución cerca de la cámara, media más lejos y una capa lejana para todo el país.
##   Las mallas se calculan en hilos (WorkerThreadPool) y se suben a la escena con un presupuesto
##   de milisegundos por frame. Lo no revelado se ve como bruma con el relieve tenue.
## API pública estable: generate, height_at, is_land, zone_of, is_unlocked, build_mesh, set_season,
## scatter_nature, make_water, clear_trees, ray_ground, footprint_ok (+ heights/half/cell/RES/water_level).

const RES := 160
const TOWN_FLAT_RADIUS := 30.0
const TOWN_HEIGHT := 3.0
const SNOW_LINE := 34.0
const CHUNK := 400.0
const LOD_NONE := -1
const LOD_HIGH := 0
const LOD_MID := 1
const LOD_FAR := 2
const LOD_RES := [80, 20, 8]
const HIGH_DIST := 700.0
const MID_DIST := 2800.0
const MAX_HIGH := 9
const MAX_MID := 48
const FAR_BATCH := 24
const FRAME_BUDGET_MS := 5.0
const DIM_LOCKED := 0.32
const FOG_AMOUNT := 0.78
const OUTSIDE_FOG := 0.9

var size: float = 400.0
var half: float = 200.0
var cell: float = 2.5
var map_type := "interior"
var cfg: Dictionary = {}
var water_level := 0.0
var heights := PackedFloat32Array()
var material: ShaderMaterial
var mesh_instance: MeshInstance3D
var tree_positions: Array = []
var _tree_mms: Array = []
var _tree_xforms: Array = []
var nature_root: Node3D

# --- País (Fase 9A) ---
var gen: CountryGen
var streaming := false
var ring := 2
var chunks := {}                 # Vector2i -> {lod, far, detail, detail_lod, trees, tree_pos, sig, busy, h}
var chunks_root: Node3D
var chunk_material: ShaderMaterial
var fog_material: ShaderMaterial
var outside_material: ShaderMaterial
var overlay: CountryOverlay
var water: MeshInstance3D
var map_image: Image             # 8 px por chunk (50 m por píxel), incluye el anillo exterior
var map_texture: ImageTexture
var stats := {"jobs": 0, "uploads": 0, "upload_ms": 0.0, "job_ms": 0.0, "high": 0, "mid": 0, "far": 0}
var _jobs: Array = []            # [{task, req}]
var _far_queue: Array = []
var _ready_results: Array = []
var _max_jobs := 3
var _hcache := {}
var _cleared: Array = []         # [Vector3(x, z, r)] talas fuera del chunk del pueblo
var _cleared_keys := {}
var _owned := {}                 # "zx,zy" -> true
var _lod_timer := 0.0
var _map_dirty := false
var _map_timer := 0.0
var _town_want := LOD_HIGH
static var _index_cache := {}


func generate(p_type: String, p_seed: int) -> void:
	size = GameState.MAP_SIZE
	half = size * 0.5
	cell = size / RES
	map_type = p_type
	cfg = GameData.map_type(p_type)
	water_level = float(cfg.get("water_level", 0.0))
	gen = MapSim.gen_for(p_type, p_seed, MapSim.country_id(GameState))
	_hcache = {}
	heights.resize((RES + 1) * (RES + 1))
	for j in range(RES + 1):
		for i in range(RES + 1):
			heights[j * (RES + 1) + i] = gen.old_height(-half + i * cell, -half + j * cell)


## Altura del terreno en cualquier punto del país. Dentro del pueblo es la rejilla de siempre;
## fuera, la misma interpolación sobre la rejilla global de 2,5 m (continua en los bordes).
func height_at(x: float, z: float) -> float:
	if absf(x) > half or absf(z) > half:
		return _grid_height(x, z)
	var fx := clampf((x + half) / cell, 0.0, RES - 0.001)
	var fz := clampf((z + half) / cell, 0.0, RES - 0.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var w := RES + 1
	var h00 := heights[j * w + i]
	var h10 := heights[j * w + i + 1]
	var h01 := heights[(j + 1) * w + i]
	var h11 := heights[(j + 1) * w + i + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func _grid_height(x: float, z: float) -> float:
	var fx := (x + half) / cell
	var fz := (z + half) / cell
	var i := floori(fx)
	var j := floori(fz)
	var tx := fx - i
	var tz := fz - j
	return lerpf(lerpf(_gh(i, j), _gh(i + 1, j), tx), lerpf(_gh(i, j + 1), _gh(i + 1, j + 1), tx), tz)


func _gh(i: int, j: int) -> float:
	if i >= 0 and j >= 0 and i <= RES and j <= RES:
		return heights[j * (RES + 1) + i]
	var k := Vector2i(i, j)
	var v = _hcache.get(k)
	if v != null:
		return v
	if _hcache.size() > 300000:
		_hcache = {}
	var h := gen.height(-half + i * cell, -half + j * cell)
	_hcache[k] = h
	return h


func is_land(x: float, z: float, margin := 0.4) -> bool:
	return height_at(x, z) > water_level + margin


## Parcela de compra (80 m) en índices globales: el pueblo es 0..4 y el país sigue fuera de ese rango.
func zone_of(x: float, z: float) -> Vector2i:
	var zs := size / GameState.ZONE_GRID
	return Vector2i(floori((x + half) / zs), floori((z + half) / zs))


func is_unlocked(x: float, z: float) -> bool:
	var zc := zone_of(x, z)
	return GameState.is_zone_unlocked(zc.x, zc.y)


# --- Malla del pueblo (idéntica a la de siempre) -------------------------------------------

## Reconstruye la malla del pueblo y, al instante, los chunks del país cuya propiedad cambió
## (al comprar una parcela se une de inmediato al terreno del jugador).
func build_mesh() -> void:
	_refresh_owned()
	_build_town_mesh()
	for c in chunks.keys():
		var d: Dictionary = chunks[c]
		var sig := _owned_sig(c)
		if sig == str(d.get("sig", "")):
			continue
		if int(d.get("detail_lod", LOD_NONE)) != LOD_NONE:
			_apply_result(_chunk_arrays(c, int(d["detail_lod"]), _owned.duplicate(), _cleared_near(c)))
		if d.get("far") != null:
			_apply_result(_chunk_arrays(c, LOD_FAR, _owned.duplicate(), []))


func _build_town_mesh() -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var n_tris := RES * RES * 2
	verts.resize(n_tris * 3)
	normals.resize(n_tris * 3)
	colors.resize(n_tris * 3)
	var w := RES + 1
	var k := 0
	for j in range(RES):
		for i in range(RES):
			var x0 := -half + i * cell
			var z0 := -half + j * cell
			var v00 := Vector3(x0, heights[j * w + i], z0)
			var v10 := Vector3(x0 + cell, heights[j * w + i + 1], z0)
			var v01 := Vector3(x0, heights[(j + 1) * w + i], z0 + cell)
			var v11 := Vector3(x0 + cell, heights[(j + 1) * w + i + 1], z0 + cell)
			var locked := not is_unlocked(x0 + cell * 0.5, z0 + cell * 0.5)
			for tri in [[v00, v10, v01], [v10, v11, v01]]:
				var a: Vector3 = tri[0]
				var b: Vector3 = tri[1]
				var c: Vector3 = tri[2]
				var nrm := (c - a).cross(b - a).normalized()
				var center := (a + b + c) / 3.0
				var col := _color_for(center, nrm.y, locked)
				verts[k] = a
				verts[k + 1] = b
				verts[k + 2] = c
				for q in range(3):
					normals[k + q] = nrm
					colors[k + q] = col
				k += 3
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if material == null:
		material = ShaderMaterial.new()
		material.shader = load("res://shaders/terrain.gdshader")
	mesh.surface_set_material(0, material)
	if mesh_instance == null:
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "TownChunk"
		add_child(mesh_instance)
	mesh_instance.mesh = mesh


func _color_for(p: Vector3, ny: float, locked: bool) -> Color:
	var c := gen.old_color(p.x, p.z, p.y, ny)
	if locked:
		var a := c.a
		c = c.darkened(DIM_LOCKED)
		c.a = a
	return c


func set_season(season_id: String) -> void:
	var s: Dictionary = GameData.weather.get("seasons", {}).get(season_id, {})
	for m in [material, chunk_material, fog_material, outside_material]:
		if m != null:
			m.set_shader_parameter("season_tint", MeshLib.arr_color(s.get("tint"), Color.WHITE))
			m.set_shader_parameter("snow_amount", float(s.get("snow", 0.0)))


## Árboles y rocas del pueblo con MultiMesh. Evita agua, pendientes y la plaza.
func scatter_nature(p_seed: int) -> Node3D:
	if nature_root:
		nature_root.queue_free()
	var root := Node3D.new()
	root.name = "Nature"
	nature_root = root
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed + 99
	var density := float(cfg.get("forest_density", 0.3))
	var trees: Array[Transform3D] = []
	var tree_colors: Array[Color] = []
	var rocks: Array[Transform3D] = []
	var rock_colors: Array[Color] = []
	tree_positions.clear()
	var step := cell * 1.2
	var x := -half + step * 0.5
	while x < half:
		var z := -half + step * 0.5
		while z < half:
			var px := x + rng.randf_range(-step, step) * 0.45
			var pz := z + rng.randf_range(-step, step) * 0.45
			z += step
			var h := height_at(px, pz)
			if h < water_level + 0.9 or Vector2(px, pz).length() < TOWN_FLAT_RADIUS + 4.0:
				continue
			var slope := absf(height_at(px + 1.0, pz) - h) + absf(height_at(px, pz + 1.0) - h)
			var locked := not is_unlocked(px, pz)
			var dim := 0.68 if locked else 1.0
			var forest := gen._forest.get_noise_2d(px, pz)
			if h < 26.0 and slope < 1.2 and forest > 0.05 and rng.randf() < density + forest:
				var s := rng.randf_range(0.7, 1.4)
				var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.85, 1.25), s)), Vector3(px, h, pz))
				trees.append(t)
				var g := rng.randf_range(0.8, 1.15)
				tree_colors.append(Color(0.2 * g * dim, 0.42 * g * dim, 0.2 * g * dim))
				tree_positions.append(Vector2(px, pz))
			elif (slope > 1.5 or h > 20.0) and rng.randf() < 0.08:
				var rs := rng.randf_range(0.5, 1.6)
				rocks.append(Transform3D(Basis(Vector3(rng.randf(), 1, rng.randf()).normalized(), rng.randf() * TAU).scaled(Vector3(rs, rs * 0.7, rs)), Vector3(px, h - 0.1, pz)))
				var gr := rng.randf_range(0.42, 0.58) * dim
				rock_colors.append(Color(gr, gr, gr * 0.95))
		x += step
	var trunk_offset := Transform3D(Basis(), Vector3(0, 0.6, 0))
	var crown_offset := Transform3D(Basis(), Vector3(0, 2.2, 0))
	var trunk_colors: Array[Color] = []
	for tc in tree_colors:
		trunk_colors.append(Color(0.4, 0.27, 0.15) * (tc.g / 0.42))
	var trunk_mm := _multimesh(MeshLib.cylinder(0.14, 0.22, 1.2, 5), trees, trunk_colors, trunk_offset)
	var crown_mm := _multimesh(MeshLib.cylinder(0.0, 1.25, 2.8, 6), trees, tree_colors, crown_offset)
	root.add_child(trunk_mm)
	root.add_child(crown_mm)
	_tree_mms = [[trunk_mm.multimesh, trunk_offset], [crown_mm.multimesh, crown_offset]]
	_tree_xforms = trees
	root.add_child(_multimesh(MeshLib.sphere(0.8, 5, 3), rocks, rock_colors, Transform3D()))
	add_child(root)
	return root


func _multimesh(mesh: Mesh, xforms: Array[Transform3D], cols: Array[Color], offset: Transform3D) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for idx in range(xforms.size()):
		mm.set_instance_transform(idx, xforms[idx] * offset)
		mm.set_instance_color(idx, cols[idx])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = MeshLib.vertex_color_mat()
	return mmi


## Agua: un plano al nivel del mar que cubre todo el país (ríos, lagos y mar comparten nivel).
func make_water() -> MeshInstance3D:
	var plane := PlaneMesh.new()
	var extent := size * (3.0 if bool(cfg.get("has_sea", false)) else 1.0)
	var center := Vector3.ZERO
	if gen != null:
		extent = maxf(extent, (gen.x_max - gen.x_min) + CHUNK * (ring * 2 + 30))
		center = Vector3(gen.center.x, 0, gen.center.y)
	plane.size = Vector2(extent, extent)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.2, 0.45, 0.62, 0.82)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.15
	m.metallic = 0.1
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = m
	mi.position = Vector3(center.x, water_level, center.z)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	water = mi
	return mi


## Tala los árboles dentro de un radio (al construir), en el pueblo y en los chunks del país.
func clear_trees(x: float, z: float, radius: float) -> void:
	var p := Vector2(x, z)
	var hidden := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	for i in range(tree_positions.size()):
		if tree_positions[i].distance_to(p) < radius:
			for pair in _tree_mms:
				pair[0].set_instance_transform(i, hidden)
	if absf(x) + radius <= half and absf(z) + radius <= half:
		return
	var key := "%d,%d,%d" % [int(x), int(z), int(radius)]
	if not _cleared_keys.has(key):
		_cleared_keys[key] = true
		_cleared.append(Vector3(x, z, radius))
	var a := CountryGen.chunk_of(x - radius, z - radius)
	var b := CountryGen.chunk_of(x + radius, z + radius)
	for cy in range(a.y, b.y + 1):
		for cx in range(a.x, b.x + 1):
			var d: Dictionary = chunks.get(Vector2i(cx, cy), {})
			if d.get("trees") == null:
				continue
			var tp: PackedVector2Array = d["tree_pos"]
			for mmi in (d["trees"] as Node3D).get_children():
				var mm: MultiMesh = (mmi as MultiMeshInstance3D).multimesh
				for i in range(mini(tp.size(), mm.instance_count)):
					if tp[i].distance_to(p) < radius:
						mm.set_instance_transform(i, hidden)


## Posición del suelo bajo el cursor (rayo contra el terreno).
func ray_ground(origin: Vector3, dir: Vector3) -> Variant:
	var t := 0.0
	var prev := origin
	var lim := half * 1.5
	if gen != null:
		lim = maxf(absf(gen.x_min), absf(gen.x_max)) + CHUNK * ring
	while t < 80000.0:
		var p := origin + dir * t
		if absf(p.x) > lim or absf(p.z) > lim:
			if dir.y >= 0.0:
				return null
		var gh := maxf(height_at(p.x, p.z), water_level)
		if p.y <= gh:
			var lo := prev
			var hi := p
			for k in range(14):
				var mid := (lo + hi) * 0.5
				if mid.y <= maxf(height_at(mid.x, mid.z), water_level):
					hi = mid
				else:
					lo = mid
			return hi
		prev = p
		t += maxf(2.0, t * 0.008)
	return null


## Verifica agua y pendiente bajo una huella de construcción.
func footprint_ok(x: float, z: float, footprint: float) -> String:
	var r := footprint * 0.5
	var hs := []
	for dx in [-r, 0.0, r]:
		for dz in [-r, 0.0, r]:
			if not is_land(x + dx, z + dz, 0.4):
				return "No se puede construir sobre agua"
			hs.append(height_at(x + dx, z + dz))
	if hs.max() - hs.min() > 2.2:
		return "Terreno demasiado inclinado"
	return ""


# =============================================================================================
# País por chunks: streaming y LOD
# =============================================================================================

## Activa el país completo (lo llama el mundo 3D después de generate/build_mesh/make_water).
func start_country() -> void:
	if gen == null or streaming:
		return
	streaming = true
	_max_jobs = clampi(OS.get_processor_count() - 1, 1, 4)
	for r in LOD_RES:
		_indices_for(int(r))
	chunks_root = Node3D.new()
	chunks_root.name = "CountryChunks"
	add_child(chunks_root)
	chunk_material = _make_chunk_mat(0.0)
	fog_material = _make_chunk_mat(FOG_AMOUNT)
	outside_material = _make_chunk_mat(OUTSIDE_FOG)
	set_season(GameState.season)
	var w := (gen.size + ring * 2) * 8
	map_image = Image.create(w, w, false, Image.FORMAT_RGB8)
	map_image.fill(Color(0.72, 0.76, 0.8))
	map_texture = ImageTexture.create_from_image(map_image)
	_refresh_owned()
	for cy in range(gen.c0 - ring, gen.c1 + ring + 1):
		for cx in range(gen.c0 - ring, gen.c1 + ring + 1):
			var c := Vector2i(cx, cy)
			chunks[c] = {"lod": LOD_NONE, "far": null, "detail": null, "detail_lod": LOD_NONE, "trees": null,
					"tree_pos": PackedVector2Array(), "sig": "", "busy": false, "h": maxf(gen.height(cx * CHUNK, cy * CHUNK), water_level)}
	overlay = CountryOverlay.new()
	overlay.name = "CountryOverlay"
	add_child(overlay)
	overlay.setup(self)
	if not EventBus.map_changed.is_connected(_on_map_changed):
		EventBus.map_changed.connect(_on_map_changed)
	_lod_timer = 0.0


func _make_chunk_mat(fog: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/terrain_chunk.gdshader")
	m.set_shader_parameter("fog", fog)
	if fog >= OUTSIDE_FOG:
		m.set_shader_parameter("fog_color", Vector3(0.74, 0.78, 0.84))
	return m


func _exit_tree() -> void:
	for j in _jobs:
		WorkerThreadPool.wait_for_task_completion(int(j["task"]))
	_jobs.clear()


func _process(delta: float) -> void:
	if not streaming:
		return
	_collect_jobs()
	_feed_far_jobs()
	_lod_timer -= delta
	if _lod_timer <= 0.0:
		_lod_timer = 0.12
		_update_lods()
	_upload_results()
	_map_timer -= delta
	if _map_dirty and _map_timer <= 0.0:
		_map_timer = 0.5
		_map_dirty = false
		map_texture.update(map_image)


func _refresh_owned() -> void:
	_owned = {}
	for z in GameState.unlocked_zones:
		_owned["%d,%d" % [int(z[0]), int(z[1])]] = true


## Firma de las parcelas propias que tocan un chunk (para rehacerlo al comprar).
func _owned_sig(c: Vector2i) -> String:
	var parts := []
	for zy in range(c.y * 5, c.y * 5 + 6):
		for zx in range(c.x * 5, c.x * 5 + 6):
			if _owned.has("%d,%d" % [zx, zy]):
				parts.append("%d,%d" % [zx, zy])
	return ";".join(parts)


func is_revealed_chunk(c: Vector2i) -> bool:
	return MapSim.is_revealed(GameState, c.x, c.y)


func _chunk_material_for(c: Vector2i) -> ShaderMaterial:
	if not gen.in_country_chunk(c.x, c.y):
		return outside_material
	return chunk_material if is_revealed_chunk(c) else fog_material


func _on_map_changed() -> void:
	for c in chunks:
		var d: Dictionary = chunks[c]
		if d.get("far") != null:
			(d["far"] as MeshInstance3D).material_override = _chunk_material_for(c)
	_lod_timer = 0.0
	if overlay:
		overlay.refresh()


## Elige el LOD de cada chunk según la distancia a la cámara y encola las mallas que faltan.
func _update_lods() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	var cp := cam.global_position
	var want_high := []
	var want_mid := []
	var need_far := []
	for c in chunks:
		var d: Dictionary = chunks[c]
		var r := CountryGen.chunk_rect(c.x, c.y)
		var q := Vector2(clampf(cp.x, r.position.x, r.end.x), clampf(cp.z, r.position.y, r.end.y))
		var dist := Vector3(q.x - cp.x, float(d["h"]) - cp.y, q.y - cp.z).length()
		d["dist"] = dist
		if d.get("far") == null and not bool(d["busy"]):
			need_far.append(c)
		if gen.in_country_chunk(c.x, c.y) and is_revealed_chunk(c):
			if dist < HIGH_DIST:
				want_high.append(c)
			elif dist < MID_DIST:
				want_mid.append(c)
	var by_dist := func(a: Vector2i, b: Vector2i) -> bool: return float(chunks[a]["dist"]) < float(chunks[b]["dist"])
	want_high.sort_custom(by_dist)
	want_mid.sort_custom(by_dist)
	var wants := {}
	for i in range(want_high.size()):
		wants[want_high[i]] = LOD_HIGH if i < MAX_HIGH else LOD_MID
	for i in range(want_mid.size()):
		if i < MAX_MID:
			wants[want_mid[i]] = LOD_MID
	# Mostrar la mejor malla disponible y liberar las que ya no hacen falta.
	var queue := []
	var high_n := 0
	var mid_n := 0
	for c in chunks:
		var d: Dictionary = chunks[c]
		var want := int(wants.get(c, LOD_FAR))
		d["want"] = want
		if c == Vector2i.ZERO and want == LOD_HIGH:
			_town_want = LOD_HIGH
		elif c == Vector2i.ZERO:
			_town_want = want
		if want == LOD_FAR and d.get("detail") != null:
			_free_detail(d)
		if want != LOD_FAR and int(d["detail_lod"]) != want and not bool(d["busy"]):
			if not (c == Vector2i.ZERO and want == LOD_HIGH):
				queue.append([c, want])
		_show(c, d, want)
		if int(d["lod"]) == LOD_HIGH:
			high_n += 1
		elif int(d["lod"]) == LOD_MID:
			mid_n += 1
	stats["high"] = high_n
	stats["mid"] = mid_n
	queue.sort_custom(func(a, b): return int(a[1]) < int(b[1]) or (int(a[1]) == int(b[1]) and float(chunks[a[0]]["dist"]) < float(chunks[b[0]]["dist"])))
	need_far.sort_custom(by_dist)
	var owned := _owned.duplicate()
	for item in queue:
		if _jobs.size() >= _max_jobs:
			break
		var c: Vector2i = item[0]
		chunks[c]["busy"] = true
		_start_job([c], int(item[1]), owned)
	_far_queue = need_far
	_feed_far_jobs()


## La capa lejana se reparte en tandas: se llenan los hilos libres en cada frame.
func _feed_far_jobs() -> void:
	while _jobs.size() < _max_jobs and not _far_queue.is_empty():
		var batch: Array = []
		while batch.size() < FAR_BATCH and not _far_queue.is_empty():
			var c: Vector2i = _far_queue.pop_front()
			if chunks[c].get("far") == null and not bool(chunks[c]["busy"]):
				batch.append(c)
		if batch.is_empty():
			break
		for c in batch:
			chunks[c]["busy"] = true
		_start_job(batch, LOD_FAR, _owned.duplicate())


func _show(c: Vector2i, d: Dictionary, want: int) -> void:
	var shown := LOD_NONE
	if c == Vector2i.ZERO and want == LOD_HIGH and mesh_instance != null:
		mesh_instance.visible = true
		shown = LOD_HIGH
	elif c == Vector2i.ZERO and mesh_instance != null:
		mesh_instance.visible = false
	if shown == LOD_NONE and d.get("detail") != null:
		shown = int(d["detail_lod"])
	var det: MeshInstance3D = d.get("detail")
	if det != null:
		det.visible = shown == int(d["detail_lod"]) and not (c == Vector2i.ZERO and want == LOD_HIGH)
	var trees: Node3D = d.get("trees")
	if trees != null:
		trees.visible = det != null and det.visible
	var far: MeshInstance3D = d.get("far")
	if far != null:
		far.visible = shown == LOD_NONE
		if shown == LOD_NONE:
			shown = LOD_FAR
	d["lod"] = shown


func _free_detail(d: Dictionary) -> void:
	if d.get("detail") != null:
		(d["detail"] as Node).queue_free()
	if d.get("trees") != null:
		(d["trees"] as Node).queue_free()
	d["detail"] = null
	d["trees"] = null
	d["tree_pos"] = PackedVector2Array()
	d["detail_lod"] = LOD_NONE


func _cleared_near(c: Vector2i) -> Array:
	var r := CountryGen.chunk_rect(c.x, c.y).grow(30.0)
	var out := []
	for v in _cleared:
		if r.has_point(Vector2(v.x, v.y)):
			out.append(v)
	return out


func _start_job(cs: Array, lod: int, owned: Dictionary) -> void:
	var clr := []
	if lod != LOD_FAR:
		clr = _cleared_near(cs[0])
	var req := {"cs": cs, "lod": lod, "owned": owned, "cleared": clr, "out": [], "ms": 0.0}
	var task := WorkerThreadPool.add_task(_job.bind(req), false, "chunk")
	_jobs.append({"task": task, "req": req})
	stats["jobs"] = int(stats["jobs"]) + 1


## Tarea en hilo: solo lee `gen` (inmutable) y escribe en req["out"].
func _job(req: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	var out: Array = req["out"]
	for c in req["cs"]:
		out.append(_chunk_arrays(c, int(req["lod"]), req["owned"], req["cleared"]))
	req["ms"] = (Time.get_ticks_usec() - t0) / 1000.0


func _collect_jobs() -> void:
	var i := 0
	while i < _jobs.size():
		var j: Dictionary = _jobs[i]
		if WorkerThreadPool.is_task_completed(int(j["task"])):
			WorkerThreadPool.wait_for_task_completion(int(j["task"]))
			stats["job_ms"] = float(stats["job_ms"]) + float(j["req"]["ms"])
			for r in j["req"]["out"]:
				_ready_results.append(r)
			_jobs.remove_at(i)
		else:
			i += 1


func _upload_results() -> void:
	var t0 := Time.get_ticks_usec()
	while not _ready_results.is_empty():
		var r: Dictionary = _ready_results.pop_front()
		var c: Vector2i = r["c"]
		if chunks.has(c):
			chunks[c]["busy"] = false
			# El pedido pudo quedar viejo (la cámara se alejó): no se sube una malla detallada inútil.
			if int(r["lod"]) == LOD_FAR or float(chunks[c].get("dist", 0.0)) < MID_DIST * 1.2:
				_apply_result(r)
		if (Time.get_ticks_usec() - t0) / 1000.0 > FRAME_BUDGET_MS:
			break
	stats["upload_ms"] = float(stats["upload_ms"]) + (Time.get_ticks_usec() - t0) / 1000.0


## Construye un chunk ya mismo en el hilo principal (pruebas y compras de terreno).
func build_chunk_now(c: Vector2i, lod: int) -> float:
	var t0 := Time.get_ticks_usec()
	if not chunks.has(c):
		chunks[c] = {"lod": LOD_NONE, "far": null, "detail": null, "detail_lod": LOD_NONE, "trees": null,
				"tree_pos": PackedVector2Array(), "sig": "", "busy": false, "h": gen.height(c.x * CHUNK, c.y * CHUNK)}
	_apply_result(_chunk_arrays(c, lod, _owned.duplicate(), _cleared_near(c)))
	return (Time.get_ticks_usec() - t0) / 1000.0


func _apply_result(r: Dictionary) -> void:
	var c: Vector2i = r["c"]
	var lod := int(r["lod"])
	var d: Dictionary = chunks[c]
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = r["verts"]
	arrays[Mesh.ARRAY_COLOR] = r["cols"]
	arrays[Mesh.ARRAY_INDEX] = _indices_for(int(LOD_RES[lod]))
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "C%d_%d_L%d" % [c.x, c.y, lod]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod == LOD_HIGH else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if chunks_root == null:
		chunks_root = Node3D.new()
		chunks_root.name = "CountryChunks"
		add_child(chunks_root)
	if chunk_material == null:
		chunk_material = _make_chunk_mat(0.0)
		fog_material = _make_chunk_mat(FOG_AMOUNT)
		outside_material = _make_chunk_mat(OUTSIDE_FOG)
	chunks_root.add_child(mi)
	d["sig"] = str(r["sig"])
	if lod == LOD_FAR:
		mi.material_override = _chunk_material_for(c)
		if d.get("far") != null:
			(d["far"] as Node).queue_free()
		d["far"] = mi
		if map_image != null and r.has("map"):
			var px := (c.x - gen.c0 + ring) * 8
			var py := (c.y - gen.c0 + ring) * 8
			var img := Image.create_from_data(8, 8, false, Image.FORMAT_RGB8, r["map"])
			map_image.blit_rect(img, Rect2i(0, 0, 8, 8), Vector2i(px, py))
			_map_dirty = true
	else:
		mi.material_override = chunk_material
		_free_detail(d)
		d["detail"] = mi
		d["detail_lod"] = lod
		if int(r.get("tree_n", 0)) > 0:
			d["trees"] = _tree_node(r, lod)
			d["tree_pos"] = r["tree_pos"]
			chunks_root.add_child(d["trees"])
	stats["uploads"] = int(stats["uploads"]) + 1
	_show(c, d, int(d.get("want", lod)) if streaming else lod)


func _tree_node(r: Dictionary, lod: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Trees"
	var n := int(r["tree_n"])
	var parts := [[MeshLib.cylinder(0.0, 1.25, 2.8, 6 if lod == LOD_HIGH else 4), r["crown_buf"]]]
	if lod == LOD_HIGH:
		parts.append([MeshLib.cylinder(0.14, 0.22, 1.2, 5), r["trunk_buf"]])
	for p in parts:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = p[0]
		mm.instance_count = n
		mm.buffer = p[1]
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = MeshLib.vertex_color_mat()
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod == LOD_HIGH else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)
	return root


## Índices de una rejilla (res+1)² con faldones en los 4 bordes (tapan grietas entre LODs).
static func _indices_for(res: int) -> PackedInt32Array:
	if _index_cache.has(res):
		return _index_cache[res]
	var n := res + 1
	var idx := PackedInt32Array()
	idx.resize(res * res * 6 + 4 * res * 6)
	var k := 0
	for j in range(res):
		for i in range(res):
			var a := j * n + i
			idx[k] = a
			idx[k + 1] = a + 1
			idx[k + 2] = a + n
			idx[k + 3] = a + 1
			idx[k + 4] = a + n + 1
			idx[k + 5] = a + n
			k += 6
	var base := n * n
	for e in range(4):
		for t in range(res):
			var g0 := _edge_vertex(e, t, n)
			var g1 := _edge_vertex(e, t + 1, n)
			var s0 := base + e * n + t
			var s1 := s0 + 1
			idx[k] = g0
			idx[k + 1] = g1
			idx[k + 2] = s1
			idx[k + 3] = g0
			idx[k + 4] = s1
			idx[k + 5] = s0
			k += 6
	_index_cache[res] = idx
	return idx


static func _edge_vertex(e: int, t: int, n: int) -> int:
	match e:
		0: return t                   # borde norte (j = 0)
		1: return (n - 1) * n + t     # borde sur
		2: return t * n               # borde oeste (i = 0)
	return t * n + n - 1              # borde este


## Arreglos de un chunk (hilo-seguro): vértices, colores, faldones, árboles y píxeles del minimapa.
func _chunk_arrays(c: Vector2i, lod: int, owned: Dictionary, cleared: Array) -> Dictionary:
	var res: int = LOD_RES[lod]
	var n := res + 1
	var step := CHUNK / res
	var x0 := c.x * CHUNK - CHUNK * 0.5
	var z0 := c.y * CHUNK - CHUNK * 0.5
	var hs := PackedFloat32Array()
	var bs := PackedByteArray()
	hs.resize(n * n)
	bs.resize(n * n)
	for j in range(n):
		var z := z0 + j * step
		for i in range(n):
			var x := x0 + i * step
			var h := gen.height(x, z)
			hs[j * n + i] = h
			bs[j * n + i] = gen.biome_id(x, z, h)
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(n * n + 4 * n)
	cols.resize(n * n + 4 * n)
	var zs := CHUNK / 5.0
	for j in range(n):
		var z := z0 + j * step
		for i in range(n):
			var x := x0 + i * step
			var h := hs[j * n + i]
			var hx0 := hs[j * n + maxi(i - 1, 0)]
			var hx1 := hs[j * n + mini(i + 1, res)]
			var hz0 := hs[maxi(j - 1, 0) * n + i]
			var hz1 := hs[mini(j + 1, res) * n + i]
			var dx := (hx1 - hx0) / (step * float(mini(i + 1, res) - maxi(i - 1, 0)))
			var dz := (hz1 - hz0) / (step * float(mini(j + 1, res) - maxi(j - 1, 0)))
			var ny := 1.0 / sqrt(1.0 + dx * dx + dz * dz)
			var col: Color
			var s := gen.blend_at(x, z)
			if s <= 0.0:
				col = gen.old_color(x, z, h, ny)
			else:
				col = gen.ground_color(x, z, h, 1.0 - ny, bs[j * n + i])
				if s < 1.0:
					col = gen.old_color(x, z, h, ny).lerp(col, s)
			# Propiedad: lo ajeno cerca del pueblo se oscurece (como siempre); lo propio lejos se entibia.
			var cheb := maxf(absf(x), absf(z))
			var zk := "%d,%d" % [floori((x + 200.0) / zs), floori((z + 200.0) / zs)]
			var a := col.a
			if owned.has(zk):
				if cheb > 200.0:
					col = col.lerp(Color(0.95, 0.82, 0.5), 0.14)
			else:
				var dim := DIM_LOCKED * (1.0 - smoothstep(200.0, 600.0, cheb))
				if dim > 0.0:
					col = col.darkened(dim)
			col.a = a
			verts[j * n + i] = Vector3(x, h, z)
			cols[j * n + i] = col
	# Faldones: copia de cada borde hundida (tapa grietas con chunks de otra resolución).
	var drop := 2.0 + step * 0.6
	var base := n * n
	for e in range(4):
		for t in range(n):
			var g := _edge_vertex(e, t, n)
			verts[base + e * n + t] = verts[g] - Vector3(0, drop, 0)
			cols[base + e * n + t] = cols[g].darkened(0.1)
	var out := {"c": c, "lod": lod, "verts": verts, "cols": cols, "sig": _sig_from(c, owned), "tree_n": 0}
	if lod == LOD_FAR:
		out["map"] = _map_pixels(hs, bs, n, step)
	elif not (c == Vector2i.ZERO):
		_chunk_trees(c, lod, hs, bs, n, step, cleared, out)
	return out


func _sig_from(c: Vector2i, owned: Dictionary) -> String:
	var parts := []
	for zy in range(c.y * 5, c.y * 5 + 6):
		for zx in range(c.x * 5, c.x * 5 + 6):
			if owned.has("%d,%d" % [zx, zy]):
				parts.append("%d,%d" % [zx, zy])
	return ";".join(parts)


## 8×8 píxeles RGB del minimapa: color del bioma con sombreado del relieve.
func _map_pixels(hs: PackedFloat32Array, bs: PackedByteArray, n: int, step: float) -> PackedByteArray:
	var px := PackedByteArray()
	px.resize(8 * 8 * 3)
	var k := 0
	for j in range(8):
		for i in range(8):
			var h := hs[j * n + i]
			var sh := clampf(1.0 + ((hs[j * n + i + 1] - h) * -0.6 + (hs[(j + 1) * n + i] - h) * -0.6) / step * 3.0, 0.7, 1.25)
			var col: Color = CountryGen.BIOME_MAP_COLORS[bs[j * n + i]]
			if bs[j * n + i] > CountryGen.B_RIO:
				col = col * sh
			elif bs[j * n + i] == CountryGen.B_MAR:
				col = col.darkened(clampf(-h / 30.0, 0.0, 0.35))
			px[k] = int(clampf(col.r, 0.0, 1.0) * 255.0)
			px[k + 1] = int(clampf(col.g, 0.0, 1.0) * 255.0)
			px[k + 2] = int(clampf(col.b, 0.0, 1.0) * 255.0)
			k += 3
	return px


## Árboles de un chunk según su bioma: completos (tronco + copa) cerca, solo copas en el LOD medio.
func _chunk_trees(c: Vector2i, lod: int, hs: PackedFloat32Array, bs: PackedByteArray, n: int, step: float, cleared: Array, out: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = gen.seed_value * 1000003 + c.x * 7919 + c.y * 104729
	var tstep := 6.5 if lod == LOD_HIGH else 15.0
	var x0 := c.x * CHUNK - CHUNK * 0.5
	var z0 := c.y * CHUNK - CHUNK * 0.5
	var crown := PackedFloat32Array()
	var trunk := PackedFloat32Array()
	var pos := PackedVector2Array()
	var cnt := int(CHUNK / tstep)
	for gj in range(cnt):
		for gi in range(cnt):
			var px := x0 + (gi + 0.5 + rng.randf_range(-0.45, 0.45)) * tstep
			var pz := z0 + (gj + 0.5 + rng.randf_range(-0.45, 0.45)) * tstep
			var r1 := rng.randf()
			var r2 := rng.randf()
			var r3 := rng.randf()
			var i := clampi(int((px - x0) / step), 0, n - 2)
			var j := clampi(int((pz - z0) / step), 0, n - 2)
			var b := bs[j * n + i]
			var dens := CountryGen.tree_density(b)
			if dens <= 0.0:
				continue
			var fn := gen._forest.get_noise_2d(px * 0.6, pz * 0.6)
			dens *= clampf(0.55 + fn * 1.2, 0.0, 1.4)
			if lod == LOD_MID:
				dens *= 0.55
			if r1 > dens:
				continue
			var tx := (px - x0) / step - i
			var tz := (pz - z0) / step - j
			var h := lerpf(lerpf(hs[j * n + i], hs[j * n + i + 1], tx), lerpf(hs[(j + 1) * n + i], hs[(j + 1) * n + i + 1], tx), tz)
			if h < water_level + 0.9 or absf(hs[j * n + i + 1] - hs[j * n + i]) + absf(hs[(j + 1) * n + i] - hs[j * n + i]) > step * 0.9:
				continue
			var skip := false
			for v in cleared:
				if Vector2(v.x, v.y).distance_to(Vector2(px, pz)) < v.z:
					skip = true
					break
			if skip:
				continue
			var s := lerpf(0.7, 1.45, r2) * (1.3 if b == CountryGen.B_SELVA else 1.0) * (1.8 if lod == LOD_MID else 1.0)
			var hsc := lerpf(0.85, 1.3, r3) * (1.5 if b == CountryGen.B_NEVADO or b == CountryGen.B_MONTANA else 1.0)
			var basis := Basis(Vector3.UP, r2 * TAU).scaled(Vector3(s, s * hsc, s))
			var col := CountryGen.tree_color(b) * lerpf(0.82, 1.15, r3)
			col.a = 1.0
			_push_xform(crown, basis, Vector3(px, h, pz) + basis * Vector3(0, 2.2, 0), col)
			if lod == LOD_HIGH:
				_push_xform(trunk, basis, Vector3(px, h, pz) + basis * Vector3(0, 0.6, 0), Color(0.4, 0.27, 0.15))
			pos.append(Vector2(px, pz))
	out["tree_n"] = pos.size()
	out["tree_pos"] = pos
	out["crown_buf"] = crown
	out["trunk_buf"] = trunk


static func _push_xform(buf: PackedFloat32Array, b: Basis, o: Vector3, col: Color) -> void:
	buf.append_array(PackedFloat32Array([b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y, b.x.z, b.y.z, b.z.z, o.z, col.r, col.g, col.b, col.a]))


# --- Consultas para pruebas, cámara y minimapa -------------------------------------------------

func chunk_state(c: Vector2i) -> Dictionary:
	return chunks.get(c, {})


func country_rect_m() -> Rect2:
	return Rect2(gen.x_min, gen.x_min, gen.x_max - gen.x_min, gen.x_max - gen.x_min)
