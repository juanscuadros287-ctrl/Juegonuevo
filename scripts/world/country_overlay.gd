class_name CountryOverlay
extends Node3D
## Fase 9A — Capa del país vista desde lejos: líneas tenues entre municipios (Voronoi de chunks) y
## marcadores de los pueblos (también los que siguen en la niebla). Se desvanece al acercarse.

const LINE_WIDTH := 22.0
const LINE_STEP := 50.0
const SHOW_FROM := 700.0      # altura de cámara desde la que se ven líneas y etiquetas
const FULL_AT := 2200.0

var terrain: Terrain
var lines: MeshInstance3D
var line_mat: StandardMaterial3D
var markers: Array = []        # [{node, dot, label, zone}]
var dot_mat_player: StandardMaterial3D
var dot_mat_town: StandardMaterial3D
var dot_mat_fog: StandardMaterial3D


func setup(t: Terrain) -> void:
	terrain = t
	line_mat = StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_mat.albedo_color = Color(1, 1, 1, 0.0)
	line_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	dot_mat_player = _dot_mat(Color(1.0, 0.8, 0.2))
	dot_mat_town = _dot_mat(Color(0.95, 0.95, 0.95))
	dot_mat_fog = _dot_mat(Color(0.62, 0.66, 0.72))
	_build_lines()
	_build_markers()
	refresh()


func _dot_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m


func _h(x: float, z: float) -> float:
	return maxf(terrain.gen.height(x, z), terrain.water_level) + 4.0


## Cintas horizontales sobre los bordes de chunk donde cambia el municipio (solo sobre tierra).
func _build_lines() -> void:
	var g := terrain.gen
	var verts := PackedVector3Array()
	for cy in range(g.c0, g.c1 + 1):
		for cx in range(g.c0, g.c1 + 1):
			var zi := g.zone_index(cx, cy)
			# Borde este (con cx + 1) y sur (con cy + 1).
			if cx < g.c1 and g.zone_index(cx + 1, cy) != zi:
				var x := cx * CountryGen.CHUNK + CountryGen.HALF_CHUNK
				_ribbon(verts, Vector2(x, cy * CountryGen.CHUNK - CountryGen.HALF_CHUNK), Vector2(x, cy * CountryGen.CHUNK + CountryGen.HALF_CHUNK))
			if cy < g.c1 and g.zone_index(cx, cy + 1) != zi:
				var z := cy * CountryGen.CHUNK + CountryGen.HALF_CHUNK
				_ribbon(verts, Vector2(cx * CountryGen.CHUNK - CountryGen.HALF_CHUNK, z), Vector2(cx * CountryGen.CHUNK + CountryGen.HALF_CHUNK, z))
	if lines:
		lines.queue_free()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	if verts.size() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	lines = MeshInstance3D.new()
	lines.name = "ZoneLines"
	lines.mesh = mesh
	lines.material_override = line_mat
	lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lines)


func _ribbon(verts: PackedVector3Array, a: Vector2, b: Vector2) -> void:
	var n := maxi(1, int(a.distance_to(b) / LINE_STEP))
	var dir := (b - a).normalized()
	var side := Vector2(-dir.y, dir.x) * LINE_WIDTH * 0.5
	for k in range(n):
		var p0 := a.lerp(b, float(k) / n)
		var p1 := a.lerp(b, float(k + 1) / n)
		var q0 := p0 - side
		var q1 := p0 + side
		var q2 := p1 + side
		var q3 := p1 - side
		# Solo sobre tierra: las fronteras no cruzan el mar abierto.
		if terrain.gen.height(p0.x, p0.y) < terrain.water_level - 3.0 and terrain.gen.height(p1.x, p1.y) < terrain.water_level - 3.0:
			continue
		var v0 := Vector3(q0.x, _h(q0.x, q0.y), q0.y)
		var v1 := Vector3(q1.x, _h(q1.x, q1.y), q1.y)
		var v2 := Vector3(q2.x, _h(q2.x, q2.y), q2.y)
		var v3 := Vector3(q3.x, _h(q3.x, q3.y), q3.y)
		verts.append_array(PackedVector3Array([v0, v1, v2, v0, v2, v3]))


func _build_markers() -> void:
	for m in markers:
		(m["node"] as Node).queue_free()
	markers = []
	var names: Array = GameData.extra("resources").get("place_names", []).duplicate()
	var town_name := str(GameState.settings.get("town_name", "Tu pueblo"))
	names.erase(town_name)
	for z in terrain.gen.zones:
		if not bool(z["town"]):
			continue
		var p: Vector2 = z["town_pos"]
		var node := Node3D.new()
		node.position = Vector3(p.x, maxf(terrain.gen.height(p.x, p.y), terrain.water_level), p.y)
		add_child(node)
		var player := bool(z["player"])
		if not player:
			node.add_child(_houses(int(z["id"])))
		var dot := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 8
		sm.rings = 4
		dot.mesh = sm
		dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(dot)
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.fixed_size = true
		label.pixel_size = 0.0005
		label.font_size = 30
		label.outline_size = 10
		label.no_depth_test = true
		label.render_priority = 2
		label.outline_modulate = Color(0, 0, 0, 0.85)
		label.offset = Vector2(0, 34)
		var nm := town_name if player else (str(names[int(z["id"]) % names.size()]) if not names.is_empty() else "Pueblo %d" % int(z["id"]))
		z["placeholder_name"] = nm
		label.text = nm
		node.add_child(label)
		markers.append({"node": node, "dot": dot, "label": label, "zone": z})


## Casco urbano low-poly de un pueblo vecino (unas casas alrededor de la plaza).
func _houses(zid: int) -> Node3D:
	var root := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = zid * 7717 + 3
	var wall := MeshLib.mat(Color(0.86, 0.8, 0.68))
	var roof := MeshLib.mat(Color(0.62, 0.3, 0.2))
	for i in range(14):
		var a := rng.randf() * TAU
		var r := rng.randf_range(10.0, 42.0)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		var w := rng.randf_range(4.0, 7.0)
		var h := rng.randf_range(3.0, 5.0)
		var body := MeshLib.mesh_node(MeshLib.box(Vector3(w, h, w * 0.8)), wall, p + Vector3(0, h * 0.5, 0))
		body.rotation.y = rng.randf() * TAU
		var top := MeshLib.mesh_node(MeshLib.box(Vector3(w * 1.1, 1.2, w * 0.9)), roof, Vector3(0, h * 0.5 + 0.6, 0))
		body.add_child(top)
		root.add_child(body)
	return root


## Actualiza colores según lo revelado (una ruta o expedición hace visible un pueblo).
func refresh() -> void:
	for m in markers:
		var z: Dictionary = m["zone"]
		var c: Vector2i = z["town_chunk"]
		var rev := MapSim.is_revealed(GameState, c.x, c.y)
		var player := bool(z["player"])
		(m["dot"] as MeshInstance3D).material_override = dot_mat_player if player else (dot_mat_town if rev else dot_mat_fog)
		var label: Label3D = m["label"]
		label.modulate = Color(1.0, 0.85, 0.3) if player else (Color(1, 1, 1) if rev else Color(0.8, 0.84, 0.9, 0.85))
		label.text = str(z.get("placeholder_name", "")) + ("" if rev or player else " (sin explorar)")


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	var alt := cp.y - maxf(terrain.height_at(cp.x, cp.z), terrain.water_level)
	var k := smoothstep(SHOW_FROM, FULL_AT, alt)
	line_mat.albedo_color = Color(1, 1, 1, 0.42 * k)
	lines.visible = k > 0.01
	for m in markers:
		var node: Node3D = m["node"]
		var d := cp.distance_to(node.global_position)
		var dot: MeshInstance3D = m["dot"]
		dot.scale = Vector3.ONE * clampf(d * 0.0045, 0.5, 90.0)
		dot.position.y = dot.scale.y
		var label: Label3D = m["label"]
		label.visible = k > 0.05 or (bool(m["zone"]["player"]) and alt > 250.0)
		dot.visible = alt > 250.0
