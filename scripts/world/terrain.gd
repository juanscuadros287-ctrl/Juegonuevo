class_name Terrain
extends Node3D
## Terreno procedural low-poly del país (Fase 9A).
## - El chunk del pueblo (400 m, centrado en la plaza) se genera igual que antes: rejilla de 2,5 m
##   (`heights`, RES 160), mismas alturas, río y costa según map_type y semilla. Las zonas sin comprar
##   se ven oscurecidas.
## - El resto del país (CountryGen: chunks de 400 m, 56–80 por lado) se construye por streaming con
##   LOD: alta resolución cerca de la cámara, media más lejos y una capa lejana de teselas de 4×4 chunks
##   (80 m por celda) para todo el país. Normales suaves y colores interpolados por vértice lejos;
##   facetas low-poly solo de cerca (el shader mezcla según la distancia).
##   Las mallas se calculan en hilos (WorkerThreadPool) y se suben a la escena con un presupuesto
##   de milisegundos por frame. Lo no explorado se ve bajo un velo translúcido (relieve y biomas
##   atenuados) y las fronteras de municipio se dibujan en el shader (Fase 9B).
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
const LOD_RES := [80, 20, 20]     # alta (5 m), media (20 m), lejana: tesela de 4×4 chunks (80 m)
const TILE := 4                   # chunks por lado de una tesela lejana
const MAP_PX := 5                 # píxeles del minimapa por chunk (80 m por píxel)
const HIGH_DIST := 700.0
const MID_DIST := 2800.0
const MAX_HIGH := 9
const MAX_MID := 48
const FAR_BATCH := 2
const FRAME_BUDGET_MS := 5.0
const DIM_LOCKED := 0.32
const FOG_LIGHT := 0.22           # velo ligero: tu municipio sin explorar y los vecinos
const FOG_AMOUNT := 0.45          # velo de lo no explorado (translúcido: se ve el relieve)
const OUTSIDE_FOG := 0.8          # otros países: atenuados y desaturados

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
var tiles := {}                  # Vector2i -> {mi, busy, sig, dist}: capa lejana (TILE×TILE chunks)
var chunks_root: Node3D
var chunk_material: ShaderMaterial
var far_material: ShaderMaterial
var fog_material: ShaderMaterial        # (compatibilidad 9A: es el mismo material lejano)
var outside_material: ShaderMaterial
var fog_image: Image
var zone_image: Image
var detail_image: Image
var fog_tex: ImageTexture
var zone_tex: ImageTexture
var detail_tex: ImageTexture
var _detail_dirty := false
var _detail_pending := 0
var overlay: CountryOverlay
var water: MeshInstance3D
var map_image: Image             # MAP_PX px por chunk (80 m por píxel), incluye el anillo exterior
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
	_rebuild_owned_changes()


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
	for m in [material, chunk_material, far_material]:
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
	_ensure_materials()
	set_season(GameState.season)
	var w := (gen.size + ring * 2) * MAP_PX
	map_image = Image.create(w, w, false, Image.FORMAT_RGB8)
	map_image.fill(Color(0.72, 0.76, 0.8))
	map_texture = ImageTexture.create_from_image(map_image)
	_refresh_owned()
	for cy in range(gen.c0 - ring, gen.c1 + ring + 1):
		for cx in range(gen.c0 - ring, gen.c1 + ring + 1):
			var c := Vector2i(cx, cy)
			chunks[c] = {"lod": LOD_NONE, "far": null, "detail": null, "detail_lod": LOD_NONE, "trees": null,
					"tree_pos": PackedVector2Array(), "sig": "", "busy": false, "h": maxf(gen.height(cx * CHUNK, cy * CHUNK), water_level)}
	var nt := tiles_per_side()
	for ty in range(nt):
		for tx in range(nt):
			tiles[Vector2i(tx, ty)] = {"mi": null, "busy": false, "sig": "", "dist": 0.0}
	overlay = CountryOverlay.new()
	overlay.name = "CountryOverlay"
	add_child(overlay)
	overlay.setup(self)
	if not EventBus.map_changed.is_connected(_on_map_changed):
		EventBus.map_changed.connect(_on_map_changed)
	_lod_timer = 0.0


## Texturas del país que usa el shader: niebla (suave), municipios (bordes) y chunks con malla detallada
## (la capa lejana se recorta ahí). Una celda por chunk, incluido el anillo exterior.
func _ensure_materials() -> void:
	if chunk_material != null:
		return
	var w := gen.size + ring * 2
	fog_image = Image.create(w, w, false, Image.FORMAT_R8)
	zone_image = Image.create(w, w, false, Image.FORMAT_RG8)
	detail_image = Image.create(w, w, false, Image.FORMAT_R8)
	detail_image.fill(Color(0, 0, 0))
	_fill_zone_image()
	_fill_fog_image()
	fog_tex = ImageTexture.create_from_image(fog_image)
	zone_tex = ImageTexture.create_from_image(zone_image)
	detail_tex = ImageTexture.create_from_image(detail_image)
	chunk_material = _make_chunk_mat(false)
	far_material = _make_chunk_mat(true)
	fog_material = far_material
	outside_material = far_material


func _make_chunk_mat(is_far: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/terrain_chunk.gdshader")
	var w := gen.size + ring * 2
	m.set_shader_parameter("fog_tex", fog_tex)
	m.set_shader_parameter("zone_tex", zone_tex)
	m.set_shader_parameter("detail_tex", detail_tex)
	m.set_shader_parameter("map_origin", Vector2((gen.c0 - ring) * CHUNK - CHUNK * 0.5, (gen.c0 - ring) * CHUNK - CHUNK * 0.5))
	m.set_shader_parameter("map_texels", float(w))
	m.set_shader_parameter("chunk_size", CHUNK)
	m.set_shader_parameter("is_far", is_far)
	return m


## Niveles de niebla por chunk: 0 explorado, velo ligero en tu municipio y los vecinos, velo en lo sin
## explorar y bruma más densa fuera del país. El shader lo interpola: bordes suaves, nunca un corte.
func _fill_fog_image() -> void:
	var w := gen.size + ring * 2
	var vals := [0.0, FOG_LIGHT, FOG_AMOUNT, OUTSIDE_FOG]
	for j in range(w):
		for i in range(w):
			var lvl := MapSim.fog_level(GameState, gen.c0 - ring + i, gen.c0 - ring + j)
			fog_image.set_pixel(i, j, Color(float(vals[lvl]), 0, 0))


## Municipio de cada chunk (R = id, 255 fuera) y G = 1 en el municipio del jugador.
func _fill_zone_image() -> void:
	var w := gen.size + ring * 2
	for j in range(w):
		for i in range(w):
			var zi := gen.zone_index(gen.c0 - ring + i, gen.c0 - ring + j)
			zone_image.set_pixel(i, j, Color((zi % 255) / 255.0 if zi >= 0 else 1.0, 1.0 if zi == 0 else 0.0, 0))


func tiles_per_side() -> int:
	return ceili(float(gen.size + ring * 2) / TILE)


## Tesela lejana que contiene un chunk.
func tile_of(c: Vector2i) -> Vector2i:
	return Vector2i(floori(float(c.x - gen.c0 + ring) / TILE), floori(float(c.y - gen.c0 + ring) / TILE))


## Primer chunk (esquina) de una tesela.
func tile_origin_chunk(t: Vector2i) -> Vector2i:
	return Vector2i(gen.c0 - ring + t.x * TILE, gen.c0 - ring + t.y * TILE)


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
	if _detail_dirty:
		_detail_dirty = false
		detail_tex.update(detail_image)
	_update_borders()
	_map_timer -= delta
	if _map_dirty and _map_timer <= 0.0:
		_map_timer = 0.5
		_map_dirty = false
		map_texture.update(map_image)


## Fronteras de municipio en el shader: tenues, solo con la cámara alta; su ancho crece con la distancia
## para seguir viéndose (unos 2 px) desde el zoom máximo.
func _update_borders() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null or chunk_material == null:
		return
	var cp := cam.global_position
	var alt := cp.y - maxf(height_at(cp.x, cp.z), water_level)
	var k := smoothstep(500.0, 1800.0, alt)
	var width := clampf(alt * 0.0021, 6.0, 70.0)
	for m in [chunk_material, far_material]:
		m.set_shader_parameter("border_alpha", 0.42 * k)
		m.set_shader_parameter("border_width", width)


func _refresh_owned() -> void:
	_owned = {}
	for z in GameState.unlocked_zones:
		_owned["%d,%d" % [int(z[0]), int(z[1])]] = true


## Firma de las parcelas propias que tocan un chunk (para rehacerlo al comprar).
func _owned_sig(c: Vector2i) -> String:
	return _sig_from(c, _owned)


func is_revealed_chunk(c: Vector2i) -> bool:
	return MapSim.is_revealed(GameState, c.x, c.y)


func _on_map_changed() -> void:
	if fog_image != null:
		_fill_fog_image()
		fog_tex.update(fog_image)
	_lod_timer = 0.0
	if overlay:
		overlay.refresh()


## Elige el LOD de cada chunk explorado según la distancia a la cámara y encola las mallas que faltan.
## La capa lejana son teselas de 4×4 chunks (80 m por celda) que cubren todo el país.
func _update_lods() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	var cp := cam.global_position
	var want_high := []
	var want_mid := []
	var rev: Dictionary = GameState.map.get("chunks_revealed", {})
	var active := []
	for c in chunks:
		var d: Dictionary = chunks[c]
		var revealed := rev.has("%d,%d" % [c.x, c.y])
		if not revealed and d.get("detail") == null and int(d["lod"]) != LOD_HIGH:
			continue
		active.append(c)
		var r := CountryGen.chunk_rect(c.x, c.y)
		var q := Vector2(clampf(cp.x, r.position.x, r.end.x), clampf(cp.z, r.position.y, r.end.y))
		var dist := Vector3(q.x - cp.x, float(d["h"]) - cp.y, q.y - cp.z).length()
		d["dist"] = dist
		if revealed and gen.in_country_chunk(c.x, c.y):
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
	for c in active:
		var d: Dictionary = chunks[c]
		var want := int(wants.get(c, LOD_FAR))
		d["want"] = want
		if c == Vector2i.ZERO:
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
	var owned := _owned.duplicate()
	_detail_pending = queue.size()
	for item in queue:
		if _jobs.size() >= _max_jobs:
			break
		var c: Vector2i = item[0]
		chunks[c]["busy"] = true
		_start_job([c], int(item[1]), owned)
		_detail_pending -= 1
	# Teselas lejanas que faltan, las más cercanas primero.
	var need := []
	for t in tiles:
		var td: Dictionary = tiles[t]
		if td["mi"] == null and not bool(td["busy"]):
			var o := tile_origin_chunk(t)
			var center := (Vector2(o) + Vector2(TILE, TILE) * 0.5 - Vector2(0.5, 0.5)) * CHUNK
			td["dist"] = Vector2(cp.x, cp.z).distance_to(center)
			need.append(t)
	need.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return float(tiles[a]["dist"]) < float(tiles[b]["dist"]))
	_far_queue = need
	_feed_far_jobs()


## La capa lejana se reparte en tandas de teselas: se llenan los hilos libres en cada frame.
func _feed_far_jobs() -> void:
	# Si faltan mallas detalladas cerca de la cámara, la capa lejana usa un solo hilo.
	var limit := _max_jobs if _detail_pending <= 0 else 1
	var far_running := 0
	for j in _jobs:
		if int(j["req"]["lod"]) == LOD_FAR:
			far_running += 1
	while _jobs.size() < _max_jobs and far_running < limit and not _far_queue.is_empty():
		far_running += 1
		var batch: Array = []
		while batch.size() < FAR_BATCH and not _far_queue.is_empty():
			var t: Vector2i = _far_queue.pop_front()
			if tiles[t]["mi"] == null and not bool(tiles[t]["busy"]):
				batch.append(t)
		if batch.is_empty():
			break
		for t in batch:
			tiles[t]["busy"] = true
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
	if shown == LOD_NONE and d.get("far") != null:
		shown = LOD_FAR
	d["lod"] = shown
	_set_detail_mask(c, shown == LOD_HIGH or shown == LOD_MID)


## Marca los chunks con malla detallada visible: ahí el shader recorta la tesela lejana.
func _set_detail_mask(c: Vector2i, on: bool) -> void:
	if detail_image == null:
		return
	var i := c.x - gen.c0 + ring
	var j := c.y - gen.c0 + ring
	if i < 0 or j < 0 or i >= detail_image.get_width() or j >= detail_image.get_height():
		return
	var v := 1.0 if on else 0.0
	if detail_image.get_pixel(i, j).r != v:
		detail_image.set_pixel(i, j, Color(v, 0, 0))
		_detail_dirty = true


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
		if int(req["lod"]) == LOD_FAR:
			out.append(_tile_arrays(c, req["owned"]))
		else:
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
		if r.has("tile"):
			var t: Vector2i = r["tile"]
			if tiles.has(t):
				tiles[t]["busy"] = false
			_apply_result(r)
		else:
			var c: Vector2i = r["c"]
			if chunks.has(c):
				chunks[c]["busy"] = false
				# El pedido pudo quedar viejo (la cámara se alejó): no se sube una malla detallada inútil.
				if float(chunks[c].get("dist", 0.0)) < MID_DIST * 1.2:
					_apply_result(r)
		if (Time.get_ticks_usec() - t0) / 1000.0 > FRAME_BUDGET_MS:
			break
	stats["upload_ms"] = float(stats["upload_ms"]) + (Time.get_ticks_usec() - t0) / 1000.0


## Construye un chunk (o la tesela lejana que lo contiene) ya mismo en el hilo principal (pruebas y
## compras de terreno).
func build_chunk_now(c: Vector2i, lod: int) -> float:
	var t0 := Time.get_ticks_usec()
	if not chunks.has(c):
		chunks[c] = {"lod": LOD_NONE, "far": null, "detail": null, "detail_lod": LOD_NONE, "trees": null,
				"tree_pos": PackedVector2Array(), "sig": "", "busy": false, "h": gen.height(c.x * CHUNK, c.y * CHUNK)}
	if lod == LOD_FAR:
		var t := tile_of(c)
		if not tiles.has(t):
			tiles[t] = {"mi": null, "busy": false, "sig": "", "dist": 0.0}
		_apply_result(_tile_arrays(t, _owned.duplicate()))
	else:
		_apply_result(_chunk_arrays(c, lod, _owned.duplicate(), _cleared_near(c)))
	return (Time.get_ticks_usec() - t0) / 1000.0


func _mesh_from(r: Dictionary, res: int) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = r["verts"]
	arrays[Mesh.ARRAY_NORMAL] = r["normals"]
	arrays[Mesh.ARRAY_COLOR] = r["cols"]
	arrays[Mesh.ARRAY_INDEX] = _indices_for(res)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _apply_result(r: Dictionary) -> void:
	var lod := int(r["lod"])
	if chunks_root == null:
		chunks_root = Node3D.new()
		chunks_root.name = "CountryChunks"
		add_child(chunks_root)
	_ensure_materials()
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh_from(r, int(LOD_RES[lod]))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod == LOD_HIGH else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunks_root.add_child(mi)
	stats["uploads"] = int(stats["uploads"]) + 1
	if r.has("tile"):
		var t: Vector2i = r["tile"]
		mi.name = "T%d_%d" % [t.x, t.y]
		mi.material_override = far_material
		var td: Dictionary = tiles.get(t, {})
		if td.get("mi") != null:
			(td["mi"] as Node).queue_free()
		td["mi"] = mi
		td["sig"] = str(r["sig"])
		tiles[t] = td
		var o := tile_origin_chunk(t)
		for dy in range(TILE):
			for dx in range(TILE):
				var c := o + Vector2i(dx, dy)
				if chunks.has(c):
					chunks[c]["far"] = mi
					if int(chunks[c]["lod"]) == LOD_NONE:
						chunks[c]["lod"] = LOD_FAR
		if map_image != null and r.has("map"):
			var px := (o.x - gen.c0 + ring) * MAP_PX
			var py := (o.y - gen.c0 + ring) * MAP_PX
			var n := TILE * MAP_PX
			var img := Image.create_from_data(n, n, false, Image.FORMAT_RGB8, r["map"])
			map_image.blit_rect(img, Rect2i(0, 0, n, n), Vector2i(px, py))
			_map_dirty = true
		return
	var c: Vector2i = r["c"]
	var d: Dictionary = chunks[c]
	mi.name = "C%d_%d_L%d" % [c.x, c.y, lod]
	mi.material_override = chunk_material
	d["sig"] = str(r["sig"])
	_free_detail(d)
	d["detail"] = mi
	d["detail_lod"] = lod
	if int(r.get("tree_n", 0)) > 0:
		d["trees"] = _tree_node(r, lod)
		d["tree_pos"] = r["tree_pos"]
		chunks_root.add_child(d["trees"])
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


## Color del suelo en un punto (paleta del pueblo mezclada con la de biomas) con la marca de propiedad.
func _vertex_color(x: float, z: float, h: float, ny: float, biome: int, owned: Dictionary) -> Color:
	var col: Color
	var s := gen.blend_at(x, z)
	if s <= 0.0:
		col = gen.old_color(x, z, h, ny)
	else:
		col = gen.ground_color(x, z, h, 1.0 - ny, biome)
		if s < 1.0:
			col = gen.old_color(x, z, h, ny).lerp(col, s)
	# Propiedad: lo ajeno cerca del pueblo se oscurece (como siempre); lo propio lejos se entibia.
	var cheb := maxf(absf(x), absf(z))
	var zs := CHUNK / 5.0
	var a := col.a
	if owned.has("%d,%d" % [floori((x + 200.0) / zs), floori((z + 200.0) / zs)]):
		if cheb > 200.0:
			col = col.lerp(Color(0.95, 0.82, 0.5), 0.14)
	else:
		var dim := DIM_LOCKED * (1.0 - smoothstep(200.0, 600.0, cheb))
		if dim > 0.0:
			col = col.darkened(dim)
	col.a = a
	return col


## Muestra una rejilla (n+2)² (con un borde de una celda para normales y suavizado) de alturas y biomas.
func _sample(x0: float, z0: float, step: float, n: int) -> Array:
	var m := n + 2
	var hs := PackedFloat32Array()
	var bs := PackedByteArray()
	hs.resize(m * m)
	bs.resize(m * m)
	for j in range(m):
		var z := z0 + (j - 1) * step
		for i in range(m):
			var x := x0 + (i - 1) * step
			var h := gen.height(x, z)
			hs[j * m + i] = h
			bs[j * m + i] = gen.biome_id(x, z, h)
	return [hs, bs]


## Vértices, normales suaves (interpoladas por vértice) y colores de una rejilla muestreada con borde.
## blur = true suaviza los colores (3×3) para que la capa lejana no se vea en bloques.
func _grid_mesh(x0: float, z0: float, step: float, n: int, hs: PackedFloat32Array, bs: PackedByteArray, owned: Dictionary, blur: bool) -> Dictionary:
	var m := n + 2
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(n * n + 4 * n)
	normals.resize(n * n + 4 * n)
	cols.resize(n * n + 4 * n)
	var full := PackedColorArray()
	full.resize(m * m)
	var nys := PackedFloat32Array()
	nys.resize(m * m)
	for j in range(m):
		for i in range(m):
			if not blur and (i == 0 or j == 0 or i == m - 1 or j == m - 1):
				continue   # el borde solo hace falta para suavizar colores
			var ii := clampi(i, 1, m - 2)
			var jj := clampi(j, 1, m - 2)
			var dx := (hs[jj * m + ii + 1] - hs[jj * m + ii - 1]) / (2.0 * step)
			var dz := (hs[(jj + 1) * m + ii] - hs[(jj - 1) * m + ii]) / (2.0 * step)
			var ny := 1.0 / sqrt(1.0 + dx * dx + dz * dz)
			nys[j * m + i] = ny
			full[j * m + i] = _vertex_color(x0 + (i - 1) * step, z0 + (j - 1) * step, hs[j * m + i], ny, bs[j * m + i], owned)
	for j in range(n):
		var z := z0 + j * step
		for i in range(n):
			var x := x0 + i * step
			var k := (j + 1) * m + (i + 1)
			var h := hs[k]
			var dx := (hs[k + 1] - hs[k - 1]) / (2.0 * step)
			var dz := (hs[k + m] - hs[k - m]) / (2.0 * step)
			verts[j * n + i] = Vector3(x, h, z)
			normals[j * n + i] = Vector3(-dx, 1.0, -dz).normalized()
			var col := full[k]
			if blur:
				var acc := Color(0, 0, 0, 0)
				for oj in [-m, 0, m]:
					for oi in [-1, 0, 1]:
						acc += full[k + oj + oi]
				acc = acc / 9.0
				col = col.lerp(acc, 0.7)
			cols[j * n + i] = col
	# Faldones: copia de cada borde hundida (tapa grietas con chunks de otra resolución).
	var drop := 2.0 + step * 0.6
	var base := n * n
	for e in range(4):
		for t in range(n):
			var g := _edge_vertex(e, t, n)
			verts[base + e * n + t] = verts[g] - Vector3(0, drop, 0)
			normals[base + e * n + t] = normals[g]
			cols[base + e * n + t] = cols[g].darkened(0.1)
	return {"verts": verts, "normals": normals, "cols": cols}


## Arreglos de un chunk detallado (hilo-seguro): vértices, normales, colores, faldones y árboles.
## Con LOD_FAR devuelve la tesela lejana que contiene el chunk (compatibilidad).
func _chunk_arrays(c: Vector2i, lod: int, owned: Dictionary, cleared: Array) -> Dictionary:
	if lod == LOD_FAR:
		return _tile_arrays(tile_of(c), owned)
	var res: int = LOD_RES[lod]
	var n := res + 1
	var step := CHUNK / res
	var x0 := c.x * CHUNK - CHUNK * 0.5
	var z0 := c.y * CHUNK - CHUNK * 0.5
	var smp := _sample(x0, z0, step, n)
	var hsb: PackedFloat32Array = smp[0]
	var bsb: PackedByteArray = smp[1]
	var out := _grid_mesh(x0, z0, step, n, hsb, bsb, owned, false)
	out["c"] = c
	out["lod"] = lod
	out["sig"] = _sig_from(c, owned)
	out["tree_n"] = 0
	if not (c == Vector2i.ZERO):
		# Árboles: rejilla sin borde (n×n) para los índices de siempre.
		var hs := PackedFloat32Array()
		var bs := PackedByteArray()
		hs.resize(n * n)
		bs.resize(n * n)
		var m := n + 2
		for j in range(n):
			for i in range(n):
				hs[j * n + i] = hsb[(j + 1) * m + i + 1]
				bs[j * n + i] = bsb[(j + 1) * m + i + 1]
		_chunk_trees(c, lod, hs, bs, n, step, cleared, out)
	return out


## Tesela lejana de TILE×TILE chunks con celdas de CHUNK·TILE/FAR_RES m (80 m): normales suaves, colores
## suavizados y los píxeles del minimapa (MAP_PX por chunk).
func _tile_arrays(t: Vector2i, owned: Dictionary) -> Dictionary:
	var o := tile_origin_chunk(t)
	var res: int = LOD_RES[LOD_FAR]
	var n := res + 1
	var span := CHUNK * TILE
	var step := span / res
	var x0 := o.x * CHUNK - CHUNK * 0.5
	var z0 := o.y * CHUNK - CHUNK * 0.5
	var smp := _sample(x0, z0, step, n)
	var hs: PackedFloat32Array = smp[0]
	var bs: PackedByteArray = smp[1]
	var out := _grid_mesh(x0, z0, step, n, hs, bs, owned, true)
	out["tile"] = t
	out["lod"] = LOD_FAR
	out["sig"] = _tile_sig(t, owned)
	out["tree_n"] = 0
	out["map"] = _map_pixels(hs, bs, n + 2, step, res)
	return out


func _sig_from(c: Vector2i, owned: Dictionary) -> String:
	var parts := []
	for zy in range(c.y * 5, c.y * 5 + 6):
		for zx in range(c.x * 5, c.x * 5 + 6):
			if owned.has("%d,%d" % [zx, zy]):
				parts.append("%d,%d" % [zx, zy])
	return ";".join(parts)


func _tile_sig(t: Vector2i, owned: Dictionary) -> String:
	var o := tile_origin_chunk(t)
	var parts := []
	for k in owned:
		var p: PackedStringArray = str(k).split(",")
		var c := MapSim.chunk_of_zone(int(p[0]), int(p[1]))
		if c.x >= o.x and c.x < o.x + TILE and c.y >= o.y and c.y < o.y + TILE:
			parts.append(str(k))
	parts.sort()
	return ";".join(parts)


## Píxeles RGB del minimapa de una tesela (MAP_PX por chunk): color del bioma con sombreado del relieve.
## hs/bs son la rejilla con borde (lado m = res + 3).
func _map_pixels(hs: PackedFloat32Array, bs: PackedByteArray, m: int, step: float, res: int) -> PackedByteArray:
	var px := PackedByteArray()
	var np := TILE * MAP_PX
	px.resize(np * np * 3)
	var k := 0
	for j in range(np):
		for i in range(np):
			var gi := clampi(int((i + 0.5) * res / np), 0, res - 1) + 1
			var gj := clampi(int((j + 0.5) * res / np), 0, res - 1) + 1
			var q := gj * m + gi
			var h := hs[q]
			var sh := clampf(1.0 + ((hs[q + 1] - h) * -0.6 + (hs[q + m] - h) * -0.6) / step * 3.0, 0.7, 1.25)
			var col: Color = CountryGen.BIOME_MAP_COLORS[bs[q]]
			if bs[q] > CountryGen.B_RIO:
				col = col * sh
			elif bs[q] == CountryGen.B_MAR:
				col = col.darkened(clampf(-h / 30.0, 0.0, 0.35))
			px[k] = int(clampf(col.r, 0.0, 1.0) * 255.0)
			px[k + 1] = int(clampf(col.g, 0.0, 1.0) * 255.0)
			px[k + 2] = int(clampf(col.b, 0.0, 1.0) * 255.0)
			k += 3
	return px


## Rehace ya mismo las mallas (detalladas y teselas lejanas) cuya propiedad cambió.
func _rebuild_owned_changes() -> void:
	for c in chunks.keys():
		var d: Dictionary = chunks[c]
		if int(d.get("detail_lod", LOD_NONE)) == LOD_NONE:
			continue
		if _owned_sig(c) != str(d.get("sig", "")):
			_apply_result(_chunk_arrays(c, int(d["detail_lod"]), _owned.duplicate(), _cleared_near(c)))
	for t in tiles.keys():
		var td: Dictionary = tiles[t]
		if td.get("mi") == null:
			continue
		if _tile_sig(t, _owned) != str(td.get("sig", "")):
			_apply_result(_tile_arrays(t, _owned.duplicate()))


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


## Rectángulo (m) que ocupan los chunks del país (en los países reales, su frontera).
func country_frame_m() -> Rect2:
	var r := Rect2()
	var first := true
	for cy in range(gen.c0, gen.c1 + 1):
		for cx in range(gen.c0, gen.c1 + 1):
			if gen.in_country_chunk(cx, cy):
				var cr := CountryGen.chunk_rect(cx, cy)
				r = cr if first else r.merge(cr)
				first = false
	return r if not first else country_rect_m()


func country_rect_m() -> Rect2:
	return Rect2(gen.x_min, gen.x_min, gen.x_max - gen.x_min, gen.x_max - gen.x_min)
