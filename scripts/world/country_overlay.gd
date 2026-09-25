class_name CountryOverlay
extends Node3D
## Fase 9A/9B — Capa del país vista desde lejos:
## - Nombres grandes de los municipios (legibles a gran altura; el tuyo en dorado).
## - Pueblos NPC: punto y casco urbano low-poly proporcional a su población (dos MultiMesh para todo el
##   país: paredes y techos, instancias baratas).
## Las fronteras entre municipios se dibujan en el shader del terreno (terrain_chunk.gdshader).

const SHOW_FROM := 600.0      # altura de cámara desde la que se ven las etiquetas
const FULL_AT := 1800.0

var terrain: Terrain
var markers: Array = []        # [{node, dot, label, zone}]
var labels: Array = []         # [{label, zone}] nombres de municipios sin pueblo
var houses_walls: MultiMeshInstance3D
var houses_roofs: MultiMeshInstance3D
var dot_mat_player: StandardMaterial3D
var dot_mat_town: StandardMaterial3D
var dot_mat_fog: StandardMaterial3D


func setup(t: Terrain) -> void:
	terrain = t
	dot_mat_player = _dot_mat(Color(1.0, 0.8, 0.2))
	dot_mat_town = _dot_mat(Color(0.97, 0.95, 0.9))
	dot_mat_fog = _dot_mat(Color(0.72, 0.74, 0.78))
	_build_markers()
	_build_houses()
	refresh()


func _dot_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m


func _ground(p: Vector2) -> float:
	return maxf(terrain.gen.height(p.x, p.y), terrain.water_level)


func _name_of(z: Dictionary) -> String:
	if bool(z["player"]):
		return str(GameState.settings.get("town_name", "Tu pueblo"))
	return MunicipalSim.name_of(GameState, int(z["id"]))


func _make_label(text: String, size: int) -> Label3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.pixel_size = 0.0006
	label.font_size = size
	label.outline_size = maxi(8, size / 4)
	label.no_depth_test = true
	label.render_priority = 2
	label.outline_modulate = Color(0.05, 0.06, 0.08, 0.9)
	label.text = text
	return label


func _build_markers() -> void:
	for m in markers:
		(m["node"] as Node).queue_free()
	for l in labels:
		(l["label"] as Node).queue_free()
	markers = []
	labels = []
	for z in terrain.gen.zones:
		var nm := _name_of(z)
		z["placeholder_name"] = nm
		if not bool(z["town"]):
			# Municipio sin pueblo: solo su nombre en el centro (más pequeño).
			var c: Vector2 = z["centroid"]
			var lb := _make_label(nm, 30)
			lb.position = Vector3(c.x, _ground(c) + 30.0, c.y)
			add_child(lb)
			labels.append({"label": lb, "zone": z})
			continue
		var p: Vector2 = z["town_pos"]
		var node := Node3D.new()
		node.position = Vector3(p.x, _ground(p), p.y)
		add_child(node)
		var dot := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 8
		sm.rings = 4
		dot.mesh = sm
		dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(dot)
		var player := bool(z["player"])
		var label := _make_label(nm, 44 if player else 38)
		label.offset = Vector2(0, 40)
		node.add_child(label)
		markers.append({"node": node, "dot": dot, "label": label, "zone": z})


## Cascos urbanos de los pueblos NPC: casas low-poly alrededor de la plaza, más casas cuanto más población.
func _build_houses() -> void:
	var walls: Array[Transform3D] = []
	var roofs: Array[Transform3D] = []
	var wall_cols: Array[Color] = []
	var roof_cols: Array[Color] = []
	for z in terrain.gen.zones:
		if not bool(z["town"]) or bool(z["player"]):
			continue
		var pop := int(MunicipalSim.region(GameState, int(z["id"])).get("population", 600))
		var n := clampi(pop / 12, 10, 240)
		var rng := RandomNumberGenerator.new()
		rng.seed = int(z["id"]) * 7717 + 3
		var center: Vector2 = z["town_pos"]
		var radius := 14.0 + sqrt(float(n)) * 9.0
		var placed := 0
		var tries := 0
		while placed < n and tries < n * 4:
			tries += 1
			# Calles en cuadrícula girada, más densas cerca de la plaza.
			var a := rng.randf() * TAU
			var r := radius * sqrt(rng.randf()) + 12.0
			var p := center + Vector2(cos(a), sin(a)) * r
			p = p.snapped(Vector2(11.0, 11.0))
			var h := terrain.gen.height(p.x, p.y)
			if h < terrain.water_level + 0.6:
				continue
			var w := rng.randf_range(5.0, 8.0) * (1.25 if r < radius * 0.4 else 1.0)
			var hh := rng.randf_range(3.5, 6.0) * (1.6 if r < radius * 0.3 and rng.randf() < 0.4 else 1.0)
			var rot := Basis(Vector3.UP, float(int(z["id"]) % 4) * 0.4 + (PI * 0.5 if rng.randf() < 0.5 else 0.0))
			walls.append(Transform3D(rot.scaled(Vector3(w, hh, w * 0.8)), Vector3(p.x, h + hh * 0.5 - 0.3, p.y)))
			roofs.append(Transform3D(rot.scaled(Vector3(w * 1.12, 1.4, w * 0.92)), Vector3(p.x, h + hh + 0.4, p.y)))
			var g := rng.randf_range(0.85, 1.0)
			wall_cols.append(Color(0.88 * g, 0.82 * g, 0.7 * g))
			roof_cols.append(Color(0.62, 0.3, 0.2) * rng.randf_range(0.85, 1.1) if rng.randf() < 0.8 else Color(0.45, 0.42, 0.4))
			placed += 1
	houses_walls = _multimesh(MeshLib.box(Vector3.ONE), walls, wall_cols)
	houses_roofs = _multimesh(MeshLib.box(Vector3.ONE), roofs, roof_cols)
	add_child(houses_walls)
	add_child(houses_roofs)


func _multimesh(mesh: Mesh, xf: Array[Transform3D], cols: Array[Color]) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for i in range(xf.size()):
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = MeshLib.vertex_color_mat()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


## Número de casas de los cascos urbanos (pruebas).
func house_count() -> int:
	return houses_walls.multimesh.instance_count if houses_walls != null else 0


## Actualiza colores y nombres según lo explorado (una ruta o expedición hace visible un pueblo).
func refresh() -> void:
	for m in markers:
		var z: Dictionary = m["zone"]
		var zid := int(z["id"])
		var rev := MapSim.zone_revealed_any(GameState, zid)
		var player := bool(z["player"])
		(m["dot"] as MeshInstance3D).material_override = dot_mat_player if player else (dot_mat_town if rev else dot_mat_fog)
		var label: Label3D = m["label"]
		label.text = _name_of(z)
		label.modulate = Color(1.0, 0.86, 0.35) if player else (Color(1, 1, 1) if rev else Color(0.86, 0.88, 0.92, 0.88))
	for l in labels:
		var z: Dictionary = l["zone"]
		var rev := MapSim.zone_revealed_any(GameState, int(z["id"]))
		var lb: Label3D = l["label"]
		lb.text = _name_of(z)
		lb.modulate = Color(0.95, 0.96, 0.9, 0.95) if rev else Color(0.84, 0.86, 0.9, 0.8)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	var alt := cp.y - maxf(terrain.height_at(cp.x, cp.z), terrain.water_level)
	var k := smoothstep(SHOW_FROM, FULL_AT, alt)
	for m in markers:
		var node: Node3D = m["node"]
		var d := cp.distance_to(node.global_position)
		var dot: MeshInstance3D = m["dot"]
		dot.scale = Vector3.ONE * clampf(d * 0.0042, 0.5, 110.0)
		dot.position.y = dot.scale.y
		var label: Label3D = m["label"]
		label.visible = k > 0.05 or (bool(m["zone"]["player"]) and alt > 250.0)
		dot.visible = alt > 250.0
	for l in labels:
		(l["label"] as Label3D).visible = k > 0.3
