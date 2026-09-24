class_name Terrain
extends Node3D
## Terreno procedural low-poly (sombreado plano) según tipo de mapa.
## El mapa se divide en zonas; las bloqueadas se ven oscurecidas hasta expandirse.

const RES := 160
const TOWN_FLAT_RADIUS := 30.0
const TOWN_HEIGHT := 3.0
const SNOW_LINE := 34.0

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

var _noise := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _ridge := FastNoiseLite.new()
var _forest := FastNoiseLite.new()


func generate(p_type: String, p_seed: int) -> void:
	size = GameState.MAP_SIZE
	half = size * 0.5
	cell = size / RES
	map_type = p_type
	cfg = GameData.map_type(p_type)
	water_level = float(cfg.get("water_level", 0.0))
	_setup_noise(_noise, p_seed, 0.006, 4)
	_setup_noise(_detail, p_seed + 11, 0.035, 2)
	_setup_noise(_ridge, p_seed + 23, 0.009, 3)
	_setup_noise(_forest, p_seed + 37, 0.012, 2)
	heights.resize((RES + 1) * (RES + 1))
	for j in range(RES + 1):
		for i in range(RES + 1):
			heights[j * (RES + 1) + i] = _height_fn(-half + i * cell, -half + j * cell)


func _setup_noise(n: FastNoiseLite, s: int, freq: float, octaves: int) -> void:
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = octaves


func _height_fn(x: float, z: float) -> float:
	var h := float(cfg.get("base_height", 4.5)) + _noise.get_noise_2d(x, z) * float(cfg.get("hill_amp", 7.0))
	h += _detail.get_noise_2d(x, z) * 1.2
	if map_type == "montana":
		var r := 1.0 - absf(_ridge.get_noise_2d(x, z))
		r *= r
		var mask := smoothstep(-20.0, -170.0, z)
		h += r * 55.0 * mask + r * 3.0
	# Zona central plana para el pueblo.
	var dist := Vector2(x, z).length()
	h = lerpf(TOWN_HEIGHT, h, smoothstep(TOWN_FLAT_RADIUS, TOWN_FLAT_RADIUS + 22.0, dist))
	match map_type:
		"costa":
			var coast := 85.0 + _ridge.get_noise_1d(z) * 15.0
			h = lerpf(h, -9.0, smoothstep(coast - 30.0, coast + 25.0, x))
		"rio":
			var rx := 62.0 + sin(z * 0.012) * 30.0 + _ridge.get_noise_1d(z * 0.5) * 12.0
			h = lerpf(water_level - 2.5, h, smoothstep(5.0, 18.0, absf(x - rx)))
	return h


func height_at(x: float, z: float) -> float:
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


func is_land(x: float, z: float, margin := 0.4) -> bool:
	return height_at(x, z) > water_level + margin


func zone_of(x: float, z: float) -> Vector2i:
	var zs := size / GameState.ZONE_GRID
	return Vector2i(clampi(int((x + half) / zs), 0, GameState.ZONE_GRID - 1),
			clampi(int((z + half) / zs), 0, GameState.ZONE_GRID - 1))


func is_unlocked(x: float, z: float) -> bool:
	var zc := zone_of(x, z)
	return GameState.is_zone_unlocked(zc.x, zc.y)


func build_mesh() -> void:
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
		add_child(mesh_instance)
	mesh_instance.mesh = mesh


func _color_for(p: Vector3, ny: float, locked: bool) -> Color:
	var h := p.y
	var grass := 0.0
	var c: Color
	var v := _detail.get_noise_2d(p.x * 3.0, p.z * 3.0) * 0.06
	if h < water_level - 0.2:
		c = Color(0.62, 0.58, 0.44)
	elif h < water_level + 0.8:
		c = Color(0.86, 0.8, 0.58)
	elif ny < 0.72:
		c = Color(0.5 + v, 0.47 + v, 0.44 + v)
	elif h > SNOW_LINE:
		c = Color(0.94, 0.95, 0.98)
	elif h > 22.0:
		c = Color(0.52 + v, 0.49 + v, 0.4 + v)
	else:
		c = Color(0.35 + v, 0.58 + v * 1.5, 0.27 + v)
		grass = 1.0
		if Vector2(p.x, p.z).length() < TOWN_FLAT_RADIUS - 4.0:
			c = c.lerp(Color(0.55, 0.52, 0.34), 0.25)
	if locked:
		c = c.darkened(0.32)
	c.a = grass
	return c


func set_season(season_id: String) -> void:
	if material == null:
		return
	var s: Dictionary = GameData.weather.get("seasons", {}).get(season_id, {})
	material.set_shader_parameter("season_tint", MeshLib.arr_color(s.get("tint"), Color.WHITE))
	material.set_shader_parameter("snow_amount", float(s.get("snow", 0.0)))


## Árboles y rocas con MultiMesh. Evita agua, pendientes y el pueblo.
func scatter_nature(p_seed: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Nature"
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
			var forest := _forest.get_noise_2d(px, pz)
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
	root.add_child(_multimesh(MeshLib.cylinder(0.14, 0.22, 1.2, 5), trees, trunk_colors, trunk_offset))
	root.add_child(_multimesh(MeshLib.cylinder(0.0, 1.25, 2.8, 6), trees, tree_colors, crown_offset))
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


func make_water() -> MeshInstance3D:
	var plane := PlaneMesh.new()
	var extent := size * (3.0 if bool(cfg.get("has_sea", false)) else 1.0)
	plane.size = Vector2(extent, extent)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.2, 0.45, 0.62, 0.82)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.15
	m.metallic = 0.1
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = m
	mi.position = Vector3(0, water_level, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi
