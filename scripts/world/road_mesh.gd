class_name RoadMesh
extends RefCounted
## Mallas continuas para carreteras, caminos y vías férreas (docs/GRAFICOS.md).
## - strip(): franja pegada al terreno con varios vértices a lo ancho (sigue el relieve sin flotar ni
##   hundirse), faldones laterales que tapan huecos, tapas redondas en los extremos (intersecciones
##   limpias) y UV para el shader (UV.x a lo ancho, UV.y en metros).
## - rail(): balasto trapezoidal, durmientes y rieles a una misma altura suavizada (alineados en curvas).
## - bridge(): vigas, barandas y pilares donde la polilínea cruza agua.
## Material: shaders/road.gdshader (tierra, empedrado, asfalto, balasto, acero y madera).

const KIND_DIRT := 0
const KIND_COBBLE := 1
const KIND_ASPHALT := 2
const KIND_BALLAST := 3
const KIND_STEEL := 4
const KIND_PLANKS := 5

static var _mats := {}


## Material compartido para un tipo de camino ("barro", "empedrado", "cemento", "balasto"…).
static func material(kind: String, color := Color(-1, 0, 0)) -> ShaderMaterial:
	var k := KIND_DIRT
	var c := Color(0.5, 0.4, 0.28)
	match kind:
		"barro", "tierra":
			k = KIND_DIRT
			c = Color(0.5, 0.39, 0.26)
		"empedrado":
			k = KIND_COBBLE
			c = Color(0.56, 0.54, 0.5)
		"cemento", "asfalto":
			k = KIND_ASPHALT
			c = Color(0.27, 0.27, 0.28)
		"balasto":
			k = KIND_BALLAST
			c = Color(0.46, 0.43, 0.4)
		"acero":
			k = KIND_STEEL
			c = Color(0.55, 0.55, 0.58)
		"madera":
			k = KIND_PLANKS
			c = Color(0.45, 0.32, 0.2)
	if color.r >= 0.0:
		c = color
	var key := "%d_%s" % [k, c.to_html()]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/road.gdshader")
	m.set_shader_parameter("kind", k)
	m.set_shader_parameter("base_color", c)
	_mats[key] = m
	return m


static func _ground(t: Terrain, x: float, z: float) -> float:
	return TransitVisuals.ground(t, x, z)


## Muestras a lo largo de la polilínea: [{p: Vector2, dir: Vector2, d: float}].
static func _samples(pts: PackedVector2Array, total: float, step: float, offset: float) -> Array:
	var cum := TransitSim.poly_cum(pts)
	var out := []
	var n := maxi(1, int(ceil(total / step)))
	for i in range(n + 1):
		var d := minf(total, i * step)
		var a := TransitSim.poly_point(pts, cum, maxf(0.0, d - 0.6))
		var b := TransitSim.poly_point(pts, cum, minf(total, d + 0.6))
		var dir := b - a
		dir = dir.normalized() if dir.length() > 0.001 else Vector2(1, 0)
		var perp := Vector2(-dir.y, dir.x)
		out.append({"p": TransitSim.poly_point(pts, cum, d) + perp * offset, "dir": dir, "perp": perp, "d": d})
	return out


static func total_length(pts: PackedVector2Array, max_len := -1.0) -> float:
	var cum := TransitSim.poly_cum(pts)
	var total := cum[cum.size() - 1] if cum.size() > 0 else 0.0
	return minf(total, max_len) if max_len >= 0.0 else total


## Franja continua a lo largo de una polilínea (desplazada `offset` hacia un lado).
static func strip(t: Terrain, pts: PackedVector2Array, offset: float, width: float, lift: float, max_len := -1.0, caps := true) -> ArrayMesh:
	var total := total_length(pts, max_len)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if pts.size() < 2 or total < 0.05:
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3.ZERO)
		return st.commit()
	var across := 4 if width > 1.0 else 1        # segmentos a lo ancho
	var samples := _samples(pts, total, 1.0 if width > 1.0 else 1.5, offset)
	var rows := []
	for s in samples:
		var c: Vector2 = s["p"]
		var perp: Vector2 = s["perp"]
		var hc := _ground(t, c.x, c.y)
		var row := []
		for k in range(across + 1):
			var f := float(k) / across
			var q := c + perp * (0.5 - f) * width
			# Altura = el terreno bajo el vértice y a medio camino hacia sus vecinos (no se hunde).
			var h := _ground(t, q.x, q.y)
			if width > 1.0:
				var q2 := q + perp * (width / across) * 0.5
				h = maxf(h, _ground(t, q2.x, q2.y))
			h = maxf(h, hc - 0.35)
			row.append(Vector3(q.x, h + lift, q.y))
		rows.append(row)
	for i in range(rows.size() - 1):
		var r0: Array = rows[i]
		var r1: Array = rows[i + 1]
		var v0 := float(samples[i]["d"])
		var v1 := float(samples[i + 1]["d"])
		for k in range(across):
			var u0 := float(k) / across
			var u1 := float(k + 1) / across
			_tri(st, r0[k], Vector2(u0, v0), r0[k + 1], Vector2(u1, v0), r1[k], Vector2(u0, v1))
			_tri(st, r0[k + 1], Vector2(u1, v0), r1[k + 1], Vector2(u1, v1), r1[k], Vector2(u0, v1))
		# Faldones bajo los bordes (ocultan huecos contra el terreno).
		if width > 1.0:
			for e in [[0, 0.0], [across, 1.0]]:
				var a: Vector3 = r0[e[0]]
				var b: Vector3 = r1[e[0]]
				var drop := Vector3(0, -0.4, 0)
				_tri(st, a, Vector2(e[1], v0), b, Vector2(e[1], v1), a + drop, Vector2(e[1], v0))
				_tri(st, b, Vector2(e[1], v1), b + drop, Vector2(e[1], v1), a + drop, Vector2(e[1], v0))
	# Tapas semicirculares en los extremos: los cruces y empalmes se ven continuos.
	if caps and width > 1.0:
		for end in [0, samples.size() - 1]:
			var s: Dictionary = samples[end]
			var c: Vector2 = s["p"]
			var dir: Vector2 = s["dir"] * (-1.0 if end == 0 else 1.0)
			var perp: Vector2 = s["perp"]
			var hc := _ground(t, c.x, c.y) + lift
			var center := Vector3(c.x, hc, c.y)
			var seg := 6
			var prev := Vector3.ZERO
			for k in range(seg + 1):
				var ang := PI * k / seg
				var q := c + (perp * cos(ang) + dir * sin(ang)) * width * 0.5
				var h := maxf(_ground(t, q.x, q.y), hc - lift - 0.35) + lift
				var pv := Vector3(q.x, h, q.y)
				if k > 0:
					var vv := float(s["d"])
					_tri(st, center, Vector2(0.5, vv), prev, Vector2(0.5 + 0.5 * cos(PI * (k - 1) / seg), vv), pv, Vector2(0.5 + 0.5 * cos(ang), vv))
				prev = pv
	st.generate_normals()
	return st.commit()


static func _tri(st: SurfaceTool, a: Vector3, ua: Vector2, b: Vector3, ub: Vector2, c: Vector3, uc: Vector2) -> void:
	# Cara hacia arriba (el shader no recorta caras, pero la normal debe mirar al cielo).
	if (c - a).cross(b - a).y < 0.0:
		var tv := b
		b = c
		c = tv
		var tu := ub
		ub = uc
		uc = tu
	st.set_uv(ua)
	st.add_vertex(a)
	st.set_uv(ub)
	st.add_vertex(b)
	st.set_uv(uc)
	st.add_vertex(c)


## Nodo de camino completo (franja con su material y puente donde cruza agua).
static func road_node(t: Terrain, pts: PackedVector2Array, kind: String, width: float, ghost: Material = null, max_len := -1.0, color := Color(-1, 0, 0)) -> Node3D:
	var root := Node3D.new()
	var body := MeshLib.mesh_node(strip(t, pts, 0.0, width, 0.06, max_len), ghost if ghost else material(kind, color))
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.name = "Superficie"
	root.add_child(body)
	if ghost == null:
		root.add_child(bridge(t, pts, width, max_len))
	return root


## Altura del lecho de la vía: el terreno suavizado a lo largo (sin baches) y nunca bajo el suelo.
static func _bed_heights(t: Terrain, samples: Array) -> PackedFloat32Array:
	var raw := PackedFloat32Array()
	for s in samples:
		var p: Vector2 = s["p"]
		var perp: Vector2 = s["perp"]
		var h := _ground(t, p.x, p.y)
		h = maxf(h, maxf(_ground(t, p.x + perp.x * 0.8, p.y + perp.y * 0.8), _ground(t, p.x - perp.x * 0.8, p.y - perp.y * 0.8)) - 0.1)
		raw.append(h)
	var out := PackedFloat32Array()
	out.resize(raw.size())
	for i in range(raw.size()):
		var acc := 0.0
		var wsum := 0.0
		for k in range(-2, 3):
			var j := clampi(i + k, 0, raw.size() - 1)
			var wk := 1.0 / (1.0 + absf(k))
			acc += raw[j] * wk
			wsum += wk
		out[i] = maxf(acc / wsum, raw[i] - 0.05)
	return out


## Vía férrea: balasto trapezoidal, durmientes y dos rieles de acero a la misma altura.
static func rail(t: Terrain, pts: PackedVector2Array, offset := 0.0, max_len := -1.0, ghost: Material = null) -> Node3D:
	var root := Node3D.new()
	root.name = "ViaFerrea"
	var total := total_length(pts, max_len)
	if pts.size() < 2 or total < 0.5:
		return root
	var samples := _samples(pts, total, 1.0, offset)
	var bed := _bed_heights(t, samples)
	# Balasto: perfil trapezoidal (base pegada al terreno, corona plana).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prof := [[-1.55, 0.0, true], [-1.05, 0.2, false], [1.05, 0.2, false], [1.55, 0.0, true]]
	var rows := []
	for i in range(samples.size()):
		var p: Vector2 = samples[i]["p"]
		var perp: Vector2 = samples[i]["perp"]
		var row := []
		for pr in prof:
			var q := p + perp * float(pr[0])
			var y := (_ground(t, q.x, q.y) - 0.12) if bool(pr[2]) else bed[i] + float(pr[1])
			row.append(Vector3(q.x, y, q.y))
		rows.append(row)
	for i in range(rows.size() - 1):
		var v0 := float(samples[i]["d"])
		var v1 := float(samples[i + 1]["d"])
		for k in range(prof.size() - 1):
			var u0 := float(k) / (prof.size() - 1)
			var u1 := float(k + 1) / (prof.size() - 1)
			_tri(st, rows[i][k], Vector2(u0, v0), rows[i][k + 1], Vector2(u1, v0), rows[i + 1][k], Vector2(u0, v1))
			_tri(st, rows[i][k + 1], Vector2(u1, v0), rows[i + 1][k + 1], Vector2(u1, v1), rows[i + 1][k], Vector2(u0, v1))
	st.generate_normals()
	var ballast := MeshLib.mesh_node(st.commit(), ghost if ghost else material("balasto"))
	ballast.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ballast)
	# Durmientes (MultiMesh) cada 0,65 m, apoyados en la corona del balasto.
	var xf: Array[Transform3D] = []
	var cum := TransitSim.poly_cum(pts)
	var d := 0.3
	while d < total:
		var i := clampi(int(round(d)), 0, samples.size() - 1)
		var a := TransitSim.poly_point(pts, cum, maxf(0.0, d - 0.6))
		var b := TransitSim.poly_point(pts, cum, minf(total, d + 0.6))
		var dir := (b - a).normalized() if (b - a).length() > 0.001 else Vector2(1, 0)
		var perp := Vector2(-dir.y, dir.x)
		var c := TransitSim.poly_point(pts, cum, d) + perp * offset
		var hb := lerpf(bed[clampi(int(floor(d)), 0, bed.size() - 1)], bed[clampi(int(ceil(d)), 0, bed.size() - 1)], fposmod(d, 1.0))
		xf.append(Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.y)), Vector3(c.x, hb + 0.24, c.y)))
		d += 0.65
		if i < 0:
			break
	if not xf.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = MeshLib.cached("rail_tie2", func(): return MeshLib.box(Vector3(2.0, 0.1, 0.24)))
		mm.instance_count = xf.size()
		for k in range(xf.size()):
			mm.set_instance_transform(k, xf[k])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = ghost if ghost else MeshLib.mat(Color(0.3, 0.21, 0.14))
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)
	# Rieles: perfil rectangular extruido a la altura de la corona + durmiente.
	for side: float in [-0.55, 0.55]:
		var rs := SurfaceTool.new()
		rs.begin(Mesh.PRIMITIVE_TRIANGLES)
		var rrows := []
		for i in range(samples.size()):
			var p: Vector2 = samples[i]["p"] + samples[i]["perp"] * side
			var perp: Vector2 = samples[i]["perp"]
			var y := bed[i] + 0.29
			rrows.append([Vector3(p.x + perp.x * 0.045, y, p.y + perp.y * 0.045), Vector3(p.x + perp.x * 0.045, y + 0.1, p.y + perp.y * 0.045),
					Vector3(p.x - perp.x * 0.045, y + 0.1, p.y - perp.y * 0.045), Vector3(p.x - perp.x * 0.045, y, p.y - perp.y * 0.045)])
		for i in range(rrows.size() - 1):
			var v0 := float(samples[i]["d"])
			var v1 := float(samples[i + 1]["d"])
			for k in range(3):
				var a0: Vector3 = rrows[i][k]
				var a1: Vector3 = rrows[i][k + 1]
				var b0: Vector3 = rrows[i + 1][k]
				var b1: Vector3 = rrows[i + 1][k + 1]
				rs.set_uv(Vector2(0, v0))
				rs.add_vertex(a0)
				rs.set_uv(Vector2(1, v0))
				rs.add_vertex(a1)
				rs.set_uv(Vector2(0, v1))
				rs.add_vertex(b0)
				rs.set_uv(Vector2(1, v0))
				rs.add_vertex(a1)
				rs.set_uv(Vector2(1, v1))
				rs.add_vertex(b1)
				rs.set_uv(Vector2(0, v1))
				rs.add_vertex(b0)
		rs.generate_normals()
		var rmi := MeshLib.mesh_node(rs.commit(), ghost if ghost else material("acero"))
		rmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(rmi)
	if ghost == null:
		root.add_child(bridge(t, pts, 3.2, max_len, offset))
	return root


## Puente donde la polilínea cruza agua: tablero con vigas laterales, barandas y pilares.
static func bridge(t: Terrain, pts: PackedVector2Array, width: float, max_len := -1.0, offset := 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Puente"
	if t == null:
		return root
	var total := total_length(pts, max_len)
	var samples := _samples(pts, total, 2.0, offset)
	var stone := MeshLib.mat(Color(0.52, 0.5, 0.47))
	var wood := MeshLib.mat(Color(0.36, 0.26, 0.17))
	var top := t.water_level + 1.0
	var unit := MeshLib.cached("__bridge_unit", func(): return MeshLib.box(Vector3.ONE))
	var prev_over := false
	var prev_p := Vector2.ZERO
	for i in range(samples.size()):
		var p: Vector2 = samples[i]["p"]
		var dir: Vector2 = samples[i]["dir"]
		var perp: Vector2 = samples[i]["perp"]
		var over := t.height_at(p.x, p.y) < t.water_level + 0.2
		if over:
			var yaw := atan2(dir.x, dir.y)
			if i % 2 == 0:
				var bottom := t.height_at(p.x, p.y) - 0.3
				var hgt := maxf(0.5, top - bottom - 0.15)
				var pil := MeshLib.mesh_node(unit, stone, Vector3(p.x, bottom + hgt * 0.5, p.y))
				pil.scale = Vector3(width * 0.8, hgt, 0.7)
				pil.rotation.y = yaw
				root.add_child(pil)
			if prev_over:
				var mid := (p + prev_p) * 0.5
				var seg := p.distance_to(prev_p) + 0.1
				for s: float in [-1.0, 1.0]:
					var q := mid + perp * s * (width * 0.5 + 0.05)
					var beam := MeshLib.mesh_node(unit, wood, Vector3(q.x, top - 0.12, q.y))
					beam.scale = Vector3(0.18, 0.35, seg)
					beam.rotation.y = yaw
					root.add_child(beam)
					var rail := MeshLib.mesh_node(unit, wood, Vector3(q.x, top + 0.75, q.y))
					rail.scale = Vector3(0.08, 0.08, seg)
					rail.rotation.y = yaw
					root.add_child(rail)
					var q2 := p + perp * s * (width * 0.5 + 0.05)
					var post := MeshLib.mesh_node(unit, wood, Vector3(q2.x, top + 0.38, q2.y))
					post.scale = Vector3(0.1, 0.8, 0.1)
					root.add_child(post)
		prev_over = over
		prev_p = p
	return root
