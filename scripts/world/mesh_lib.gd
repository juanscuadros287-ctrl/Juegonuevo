class_name MeshLib
extends RefCounted
## Fábrica de mallas y materiales low-poly compartidos (con caché). docs/GRAFICOS.md
##
## - Primitivas con sombreado plano (normales por cara): caja, caja biselada, cilindro con tapas,
##   esfera, prisma, tejado a cuatro aguas, arco, escalera y toro (ruedas).
## - build_model() une todas las piezas de un modelo JSON en UNA malla (una llamada de dibujo) con
##   un único material compartido (shaders/building.gdshader): el color va por vértice y el tipo
##   de material (adobe, ladrillo, madera, piedra, teja, paja, concreto, metal, vidrio) por UV2.
##   Añade detalles automáticos (marcos y alféizares de ventanas, marcos y escalón de puertas,
##   cumbrera y aleros en techos, zócalo y cornisa) en una segunda malla con distancia de dibujo
##   corta, y varía levemente el tono de cada edificio (parámetro variant) para que no se vean clonados.
## - set_night(f) enciende ventanas y faroles (emisivos) de noche.

static var _materials := {}
static var _meshes := {}
static var _models := {}
static var _building_mat: ShaderMaterial
static var _emissive: Array = []      # [StandardMaterial3D, color base, energía de día, energía de noche]
static var _night := 0.0

const K_PLAIN := 0
const K_PLASTER := 1
const K_BRICK := 2
const K_WOOD := 3
const K_STONE := 4
const K_TILE := 5
const K_THATCH := 6
const K_CONCRETE := 7
const K_METAL := 8
const K_GLASS := 9
const K_GLOW := 10
const K_SHUTTER := 11     # postigo de madera: de noche deja ver luz cálida
const KIND_NAMES := {"liso": 0, "estuco": 1, "adobe": 1, "ladrillo": 2, "madera": 3, "piedra": 4, "teja": 5,
		"paja": 6, "concreto": 7, "metal": 8, "vidrio": 9, "luz": 10}


# --- Materiales -----------------------------------------------------------------------------

static func mat(color: Color, roughness := 0.9) -> StandardMaterial3D:
	var key := "%s_%.2f" % [color.to_html(), roughness]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	_materials[key] = m
	return m


## Material de vegetación y rocas con color por instancia (MultiMesh): sombreado plano y balanceo
## leve con el viento en las piezas verdes (shaders/foliage.gdshader).
static func vertex_color_mat() -> Material:
	if _materials.has("__vc"):
		return _materials["__vc"]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/foliage.gdshader")
	_materials["__vc"] = m
	return m


## Material único de los modelos unidos (color por vértice + tipo de material por UV2).
static func building_mat() -> ShaderMaterial:
	if _building_mat == null:
		_building_mat = ShaderMaterial.new()
		_building_mat.shader = load("res://shaders/building.gdshader")
		_building_mat.set_shader_parameter("night", _night)
	return _building_mat


## Material emisivo que se enciende de noche (faroles, luces de vehículos).
static func glow_mat(color: Color, day_energy := 0.15, night_energy := 2.2) -> StandardMaterial3D:
	var key := "__glow_%s_%.2f_%.2f" % [color.to_html(), day_energy, night_energy]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = lerpf(day_energy, night_energy, _night)
	m.roughness = 0.5
	_materials[key] = m
	_emissive.append([m, day_energy, night_energy])
	return m


## 0 = día, 1 = noche. Lo llama SkyRig cuando cambia la luz.
static func set_night(f: float) -> void:
	_night = clampf(f, 0.0, 1.0)
	if _building_mat:
		_building_mat.set_shader_parameter("night", _night)
	for e in _emissive:
		(e[0] as StandardMaterial3D).emission_energy_multiplier = lerpf(float(e[1]), float(e[2]), _night)


static func night() -> float:
	return _night


static func cached(key: String, builder: Callable) -> Mesh:
	if not _meshes.has(key):
		_meshes[key] = builder.call()
	return _meshes[key]


static func mesh_node(mesh: Mesh, material: Material, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	return mi


# --- Primitivas con sombreado plano -----------------------------------------------------------

static func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func prism(size: Vector3) -> PrismMesh:
	var p := PrismMesh.new()
	p.size = size
	return p


## Acumulador de triángulos con normal plana orientada hacia fuera (según un punto interior).
static func _tri(v: PackedVector3Array, n: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, inside: Vector3) -> void:
	var nrm := (c - a).cross(b - a)
	if nrm.length_squared() < 1e-12:
		return
	nrm = nrm.normalized()
	if nrm.dot((a + b + c) / 3.0 - inside) < 0.0:
		var t := b
		b = c
		c = t
		nrm = -nrm
	v.append_array(PackedVector3Array([a, b, c]))
	n.append_array(PackedVector3Array([nrm, nrm, nrm]))


static func _quad(v: PackedVector3Array, n: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, inside: Vector3) -> void:
	_tri(v, n, a, b, c, inside)
	_tri(v, n, a, c, d, inside)


static func _commit(v: PackedVector3Array, n: PackedVector3Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	var m := ArrayMesh.new()
	if not v.is_empty():
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_flat_cache[m.get_instance_id()] = [v, n]   # sin leer de la GPU al unir modelos
	return m


## Cilindro (o cono si top = 0) con tapas y caras planas. Centrado en el origen.
static func cylinder(top: float, bottom: float, height: float, segments := 6) -> Mesh:
	var key := "__cyl_%.3f_%.3f_%.3f_%d" % [top, bottom, height, segments]
	if _meshes.has(key):
		return _meshes[key]
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var hh := height * 0.5
	var inside := Vector3.ZERO
	for i in range(segments):
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var d0 := Vector3(sin(a0), 0, cos(a0))
		var d1 := Vector3(sin(a1), 0, cos(a1))
		var b0 := d0 * bottom + Vector3(0, -hh, 0)
		var b1 := d1 * bottom + Vector3(0, -hh, 0)
		var t0 := d0 * top + Vector3(0, hh, 0)
		var t1 := d1 * top + Vector3(0, hh, 0)
		if top <= 0.0001:
			_tri(v, n, b0, b1, t0, inside)
		elif bottom <= 0.0001:
			_tri(v, n, t0, t1, b0, inside)
		else:
			_quad(v, n, b0, b1, t1, t0, inside)
		if top > 0.0001:
			_tri(v, n, Vector3(0, hh, 0), t0, t1, Vector3(0, hh - 1.0, 0))
		if bottom > 0.0001:
			_tri(v, n, Vector3(0, -hh, 0), b1, b0, Vector3(0, -hh + 1.0, 0))
	var m := _commit(v, n)
	_meshes[key] = m
	return m


## Esfera low-poly con caras planas.
static func sphere(radius: float, segments := 6, rings := 4) -> Mesh:
	var key := "__sph_%.3f_%d_%d" % [radius, segments, rings]
	if _meshes.has(key):
		return _meshes[key]
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	for r in range(rings):
		var p0 := PI * r / rings
		var p1 := PI * (r + 1) / rings
		for s in range(segments):
			var a0 := TAU * s / segments + (0.5 * TAU / segments if r % 2 == 1 else 0.0)
			var a1 := a0 + TAU / segments
			var q00 := Vector3(sin(p0) * sin(a0), cos(p0), sin(p0) * cos(a0)) * radius
			var q01 := Vector3(sin(p0) * sin(a1), cos(p0), sin(p0) * cos(a1)) * radius
			var q10 := Vector3(sin(p1) * sin(a0), cos(p1), sin(p1) * cos(a0)) * radius
			var q11 := Vector3(sin(p1) * sin(a1), cos(p1), sin(p1) * cos(a1)) * radius
			if r == 0:
				_tri(v, n, q00, q10, q11, Vector3.ZERO)
			elif r == rings - 1:
				_tri(v, n, q00, q01, q10, Vector3.ZERO)
			else:
				_quad(v, n, q00, q01, q11, q10, Vector3.ZERO)
	var m := _commit(v, n)
	_meshes[key] = m
	return m


## Caja con chaflán en las aristas (bevel = tamaño del chaflán).
static func bevel_box(size: Vector3, bevel := 0.06) -> Mesh:
	var key := "__bev_%s_%.3f" % [str(size), bevel]
	if _meshes.has(key):
		return _meshes[key]
	var h := size * 0.5
	var b := minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.9)
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	# 24 vértices: cada esquina se recorta en 3 puntos.
	var pts := {}
	for sx: int in [-1, 1]:
		for sy: int in [-1, 1]:
			for sz: int in [-1, 1]:
				var c := Vector3(h.x * sx, h.y * sy, h.z * sz)
				pts[Vector3i(sx, sy, sz)] = [c - Vector3(b * sx, 0, 0), c - Vector3(0, b * sy, 0), c - Vector3(0, 0, b * sz)]
	var o := Vector3.ZERO
	# Caras principales (reducidas).
	for axis in range(3):
		for s: int in [-1, 1]:
			var quad := []
			for u: int in [-1, 1]:
				for w: int in [-1, 1]:
					var k := Vector3i.ZERO
					k[axis] = s
					k[(axis + 1) % 3] = u
					k[(axis + 2) % 3] = w
					quad.append((pts[k] as Array)[axis])
			_quad(v, n, quad[0], quad[1], quad[3], quad[2], o)
	# Chaflanes de las aristas.
	for axis in range(3):
		var a1 := (axis + 1) % 3
		var a2 := (axis + 2) % 3
		for s1: int in [-1, 1]:
			for s2: int in [-1, 1]:
				var k0 := Vector3i.ZERO
				k0[axis] = -1
				k0[a1] = s1
				k0[a2] = s2
				var k1 := k0
				k1[axis] = 1
				_quad(v, n, (pts[k0] as Array)[a1], (pts[k1] as Array)[a1], (pts[k1] as Array)[a2], (pts[k0] as Array)[a2], o)
	# Esquinas.
	for k in pts:
		var p: Array = pts[k]
		_tri(v, n, p[0], p[1], p[2], o)
	var m := _commit(v, n)
	_meshes[key] = m
	return m


## Tejado a cuatro aguas: base size.x × size.z, alto size.y, cumbrera a lo largo del lado mayor.
static func hip_roof(size: Vector3) -> Mesh:
	var key := "__hip_%s" % str(size)
	if _meshes.has(key):
		return _meshes[key]
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var y0 := -size.y * 0.5
	var y1 := size.y * 0.5
	var inside := Vector3(0, -size.y * 0.25, 0)
	var r0: Vector3
	var r1: Vector3
	if size.x >= size.z:
		r0 = Vector3(-(hx - hz), y1, 0)
		r1 = Vector3(hx - hz, y1, 0)
	else:
		r0 = Vector3(0, y1, -(hz - hx))
		r1 = Vector3(0, y1, hz - hx)
	var c00 := Vector3(-hx, y0, -hz)
	var c10 := Vector3(hx, y0, -hz)
	var c11 := Vector3(hx, y0, hz)
	var c01 := Vector3(-hx, y0, hz)
	if size.x >= size.z:
		_quad(v, n, c00, c10, r1, r0, inside)
		_quad(v, n, c01, c11, r1, r0, inside)
		_tri(v, n, c00, c01, r0, inside)
		_tri(v, n, c10, c11, r1, inside)
	else:
		_quad(v, n, c00, c01, r1, r0, inside)
		_quad(v, n, c10, c11, r1, r0, inside)
		_tri(v, n, c00, c10, r0, inside)
		_tri(v, n, c01, c11, r1, inside)
	_quad(v, n, c00, c10, c11, c01, Vector3(0, 1.0, 0))
	var m := _commit(v, n)
	_meshes[key] = m
	return m


## Arco (portal): ancho size.x, alto size.y, fondo size.z; grosor del marco = thick.
static func arch(size: Vector3, thick := 0.3, segments := 8) -> Mesh:
	var key := "__arch_%s_%.2f_%d" % [str(size), thick, segments]
	if _meshes.has(key):
		return _meshes[key]
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var hw := size.x * 0.5
	var r := hw - thick
	var spring := size.y - hw          # altura donde empieza la curva
	var hz := size.z * 0.5
	# Pilares.
	for s: float in [-1.0, 1.0]:
		var cx := s * (hw - thick * 0.5)
		_box_into(v, n, Vector3(cx, spring * 0.5, 0), Vector3(thick, spring, size.z))
	# Dovelas.
	for i in range(segments):
		var a0 := PI * i / segments
		var a1 := PI * (i + 1) / segments
		var i0 := Vector3(cos(a0) * r, spring + sin(a0) * r, 0)
		var i1 := Vector3(cos(a1) * r, spring + sin(a1) * r, 0)
		var o0 := Vector3(cos(a0) * hw, spring + sin(a0) * hw, 0)
		var o1 := Vector3(cos(a1) * hw, spring + sin(a1) * hw, 0)
		var mid := (i0 + i1 + o0 + o1) * 0.25
		var f := Vector3(0, 0, hz)
		_quad(v, n, i0 + f, o0 + f, o1 + f, i1 + f, mid)
		_quad(v, n, i0 - f, o0 - f, o1 - f, i1 - f, mid)
		_quad(v, n, o0 - f, o1 - f, o1 + f, o0 + f, mid)
		_quad(v, n, i0 - f, i1 - f, i1 + f, i0 + f, mid + (mid - Vector3(0, spring, 0)))
	var m := _commit(v, n)
	_meshes[key] = m
	return m


## Escalera: size = ancho × alto × fondo, con `steps` peldaños que suben hacia -z.
static func stairs(size: Vector3, steps := 4) -> Mesh:
	var key := "__stairs_%s_%d" % [str(size), steps]
	if _meshes.has(key):
		return _meshes[key]
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var sh := size.y / steps
	var sd := size.z / steps
	for i in range(steps):
		var hgt := sh * (i + 1)
		_box_into(v, n, Vector3(0, hgt * 0.5, size.z * 0.5 - sd * (i + 0.5)), Vector3(size.x, hgt, sd))
	var m := _commit(v, n)
	_meshes[key] = m
	return m


## Toro (rueda) en el plano YZ: eje de giro X. radius = radio medio, tube = grosor.
static func torus(radius: float, tube: float, segments := 10, sides := 4) -> Mesh:
	var key := "__tor_%.3f_%.3f_%d_%d" % [radius, tube, segments, sides]
	if _meshes.has(key):
		return _meshes[key]
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	for i in range(segments):
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var c0 := Vector3(0, sin(a0), cos(a0)) * radius
		var c1 := Vector3(0, sin(a1), cos(a1)) * radius
		for j in range(sides):
			var b0 := TAU * j / sides + PI / sides
			var b1 := TAU * (j + 1) / sides + PI / sides
			var p00 := c0 + (c0.normalized() * cos(b0) + Vector3.RIGHT * sin(b0)) * tube
			var p01 := c0 + (c0.normalized() * cos(b1) + Vector3.RIGHT * sin(b1)) * tube
			var p10 := c1 + (c1.normalized() * cos(b0) + Vector3.RIGHT * sin(b0)) * tube
			var p11 := c1 + (c1.normalized() * cos(b1) + Vector3.RIGHT * sin(b1)) * tube
			_quad(v, n, p00, p10, p11, p01, (c0 + c1) * 0.5)
	var m := _commit(v, n)
	_meshes[key] = m
	return m


## Rueda completa (llanta de toro + disco central), eje Y como cylinder(). Cacheada.
static func wheel(radius: float, width: float) -> Mesh:
	var key := "__wheel_%.2f_%.2f" % [radius, width]
	if _meshes.has(key):
		return _meshes[key]
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var disc := cylinder(radius * 0.72, radius * 0.72, width * 0.8, 8)
	var tor := torus(radius * 0.84, maxf(width * 0.5, radius * 0.16), 12, 4)
	var rot := Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3.ZERO)
	for pair in [[disc, Transform3D()], [tor, rot]]:
		var arr: Array = _flat_arrays(pair[0])
		v.append_array((pair[1] as Transform3D) * (arr[0] as PackedVector3Array))
		n.append_array(Transform3D((pair[1] as Transform3D).basis, Vector3.ZERO) * (arr[1] as PackedVector3Array))
	var m := _commit(v, n)
	_meshes[key] = m
	return m


static func _box_into(v: PackedVector3Array, n: PackedVector3Array, c: Vector3, s: Vector3) -> void:
	var h := s * 0.5
	var p := []
	for i in range(8):
		p.append(c + Vector3(h.x * (1 if i & 1 else -1), h.y * (1 if i & 2 else -1), h.z * (1 if i & 4 else -1)))
	_quad(v, n, p[0], p[1], p[3], p[2], c)
	_quad(v, n, p[4], p[5], p[7], p[6], c)
	_quad(v, n, p[0], p[1], p[5], p[4], c)
	_quad(v, n, p[2], p[3], p[7], p[6], c)
	_quad(v, n, p[0], p[2], p[6], p[4], c)
	_quad(v, n, p[1], p[3], p[7], p[5], c)


static func arr_color(a, fallback: Color) -> Color:
	if a is Array and a.size() >= 3:
		return Color(float(a[0]), float(a[1]), float(a[2]))
	return fallback


# --- Modelos unidos ------------------------------------------------------------------------------

## Buffer de una malla unida: vértices, normales, colores y UV2 (tipo de material, azar).
class Buf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var u := PackedVector2Array()

	func add(mesh: Mesh, xf: Transform3D, col: Color, kind: int, rnd := 0.0) -> void:
		var arr: Array = MeshLib._flat_arrays(mesh)
		var verts: PackedVector3Array = arr[0]
		var cnt := verts.size()
		v.append_array(xf * verts)
		n.append_array(Transform3D(xf.basis.inverse().transposed(), Vector3.ZERO) * (arr[1] as PackedVector3Array))
		var cc := PackedColorArray()
		cc.resize(cnt)
		cc.fill(col)
		c.append_array(cc)
		var uu := PackedVector2Array()
		uu.resize(cnt)
		uu.fill(Vector2(kind, rnd))
		u.append_array(uu)

	func box(center: Vector3, size: Vector3, xf: Transform3D, col: Color, kind: int, rnd := 0.0) -> void:
		add(MeshLib.cached("__ubox", func(): return MeshLib.box(Vector3.ONE)), xf * Transform3D(Basis.from_scale(size), center), col, kind, rnd)

	func commit() -> ArrayMesh:
		var m := ArrayMesh.new()
		if v.is_empty():
			return m
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_COLOR] = c
		arrays[Mesh.ARRAY_TEX_UV2] = u
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		m.surface_set_material(0, MeshLib.building_mat())
		return m


## Vértices y normales de la primera superficie, sin índices (cacheado por malla).
static var _flat_cache := {}


static func _flat_arrays(mesh: Mesh) -> Array:
	var id := mesh.get_instance_id()
	if _flat_cache.has(id):
		return _flat_cache[id]
	if mesh.get_surface_count() == 0:
		return [PackedVector3Array(), PackedVector3Array()]
	var arr: Array = mesh.surface_get_arrays(0)
	if arr.size() < Mesh.ARRAY_MAX or arr[Mesh.ARRAY_VERTEX] == null:
		return [PackedVector3Array(), PackedVector3Array()]
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx = arr[Mesh.ARRAY_INDEX]
	if idx is PackedInt32Array and not (idx as PackedInt32Array).is_empty():
		var fv := PackedVector3Array()
		var fn := PackedVector3Array()
		fv.resize(idx.size())
		fn.resize(idx.size())
		for i in range(idx.size()):
			fv[i] = verts[idx[i]]
			fn[i] = norms[idx[i]]
		verts = fv
		norms = fn
	var out := [verts, norms]
	_flat_cache[id] = out
	return out


## Tipo de material de una pieza: explícito ("m": "ladrillo") o deducido del color y la forma.
static func classify(part: Dictionary, s: String, size: Vector3, col: Color) -> int:
	if part.has("m"):
		return int(KIND_NAMES.get(str(part["m"]), K_PLAIN))
	var lum := col.r * 0.3 + col.g * 0.59 + col.b * 0.11
	if col.b > col.r + 0.06 and col.b >= col.g - 0.04 and lum < 0.7:
		return K_GLASS
	var small := minf(size.x, minf(size.y, size.z)) < 0.25 and maxf(size.x, maxf(size.y, size.z)) < 1.4
	if small or s == "sphere":
		return K_PLAIN
	var gray := absf(col.r - col.g) < 0.06 and absf(col.g - col.b) < 0.07
	if s == "prism" or s == "hip":
		if col.r > 0.55 and col.g > 0.45 and col.b < 0.45 and col.r - col.b > 0.25:
			return K_THATCH
		if col.r > col.g * 1.45 and col.r > 0.3:
			return K_TILE
		if gray:
			return K_METAL if lum < 0.5 else K_CONCRETE
		return K_WOOD if lum < 0.42 else K_PLAIN
	if gray:
		return K_STONE if lum < 0.56 else K_CONCRETE
	if col.r > 0.45 and col.g < 0.4 and col.r > col.g * 1.5 and col.b < col.g * 1.1:
		return K_BRICK
	if lum < 0.42 and col.r > col.b and col.g > col.b * 0.9:
		return K_WOOD
	if lum > 0.6 and col.r >= col.b:
		return K_PLASTER
	return K_PLAIN


## Variación leve de tono por edificio (variant >= 0) y armonía de la paleta (saturación acotada).
static func vary(col: Color, kind: int, variant: int) -> Color:
	var h := col.h
	var s := minf(col.s, 0.72)
	var val := col.v
	if variant >= 0 and kind != K_GLASS and kind != K_GLOW and kind != K_METAL:
		var r := fposmod(sin(float(variant) * 12.9898 + float(kind) * 3.1) * 43758.5453, 1.0)
		h = fposmod(h + (r - 0.5) * 0.035, 1.0)
		s = clampf(s * (0.9 + r * 0.2), 0.0, 1.0)
		val = clampf(val * (0.93 + r * 0.12), 0.0, 1.0)
	return Color.from_hsv(h, s, val)


## Construye un modelo a partir de piezas definidas en JSON:
## {"s": box|bevel|prism|hip|cyl|sphere|floors|arch|stairs|torus|win|door|chimney|fence,
##  "size": [...], "pos": [...], "c": [r,g,b], "rot": grados Y, "rx"/"rz": grados, "m": material}
## Devuelve un Node3D con una o dos MeshInstance3D (cuerpo y detalles) que comparten material.
static func build_model(parts: Array, tint := 1.0, override: Material = null, variant := -1) -> Node3D:
	var key := "%d|%.3f|%d" % [str(parts).hash(), tint, variant]
	var pair: Array
	if _models.has(key):
		pair = _models[key]
	else:
		pair = _merge(parts, tint, variant)
		_models[key] = pair
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = pair[0]
	body.add_to_group("gfx_main")
	_set_range(body, "gfx_main")
	if override:
		body.material_override = override
	root.add_child(body)
	if (pair[1] as ArrayMesh).get_surface_count() > 0:
		var det := MeshInstance3D.new()
		det.name = "Detail"
		det.mesh = pair[1]
		det.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		det.add_to_group("gfx_detail")
		_set_range(det, "gfx_detail")
		if override:
			det.material_override = override
		root.add_child(det)
	return root


## Distancia de dibujo según la calidad (GraphicsSettings); SkyRig la actualiza al cambiarla.
static func _set_range(mi: GeometryInstance3D, group: String) -> void:
	var p := GraphicsSettings.profile()
	var end := float(p["detail_range"]) if group == "gfx_detail" else float(p["building_range"])
	mi.visibility_range_end = end
	mi.visibility_range_end_margin = end * 0.1
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


static func apply_ranges(tree: SceneTree, p: Dictionary) -> void:
	for g in [["gfx_main", "building_range"], ["gfx_detail", "detail_range"], ["gfx_tree", "tree_range"]]:
		var end := float(p[g[1]])
		tree.set_group(g[0], "visibility_range_end", end)
		tree.set_group(g[0], "visibility_range_end_margin", end * 0.1)


static func _merge(parts: Array, tint: float, variant: int) -> Array:
	var main := Buf.new()
	var det := Buf.new()
	var body_idx := -1
	var body_vol := 0.0
	var infos := []
	for i in range(parts.size()):
		var part: Dictionary = parts[i]
		var s := str(part.get("s", "box"))
		var size := _vec(part.get("size", [1, 1, 1]), Vector3.ONE)
		var pos := _vec(part.get("pos", [0, 0, 0]), Vector3.ZERO)
		infos.append([s, size, pos])
		var flat := absf(float(part.get("rx", 0))) < 0.1 and absf(float(part.get("rz", 0))) < 0.1
		if s == "box" and flat and pos.y - size.y * 0.5 < 0.15 and size.y >= 1.5 and size.x * size.y * size.z > body_vol:
			body_vol = size.x * size.y * size.z
			body_idx = i
	for i in range(parts.size()):
		var part: Dictionary = parts[i]
		var s: String = infos[i][0]
		var size: Vector3 = infos[i][1]
		var pos: Vector3 = infos[i][2]
		var raw := arr_color(part.get("c"), Color(0.7, 0.7, 0.7)) * tint
		raw.a = 1.0
		var basis := Basis.from_euler(Vector3(deg_to_rad(float(part.get("rx", 0))), deg_to_rad(float(part.get("rot", 0))), deg_to_rad(float(part.get("rz", 0)))))
		var xf := Transform3D(basis, pos)
		var kind := classify(part, s, size, raw)
		var col := vary(raw, kind, variant)
		var rnd := fposmod(float(i) * 0.618 + float(variant) * 0.31, 1.0)
		match s:
			"floors":
				_floors_into(main, det, part, size, pos, col, tint, variant)
			"prism":
				main.add(prism(size), xf, col, kind, rnd)
				_roof_details(det, size, xf, col)
			"hip":
				main.add(hip_roof(size), xf, col, kind, rnd)
			"cyl":
				main.add(cylinder(size.x, size.z, size.y, int(part.get("seg", 8))), xf, col, kind, rnd)
			"sphere":
				main.add(sphere(0.5, 7, 4), xf * Transform3D(Basis.from_scale(size), Vector3.ZERO), col, kind, rnd)
			"bevel":
				main.add(bevel_box(size, float(part.get("bevel", 0.08))), xf, col, kind, rnd)
			"arch":
				main.add(arch(size, float(part.get("thick", 0.3))), xf, col, kind, rnd)
			"stairs":
				main.add(stairs(size, int(part.get("steps", 4))), xf, col, kind, rnd)
			"torus":
				main.add(torus(size.x, size.z, 12, 4), xf, col, kind, rnd)
			"win":
				_window(main, det, size, xf, col, pos, true)
			"door":
				_door(main, det, size, xf, col, pos)
			"chimney":
				main.box(Vector3(0, size.y * 0.5, 0), size, xf, col, K_BRICK if kind == K_PLAIN else kind, rnd)
				det.box(Vector3(0, size.y + 0.06, 0), Vector3(size.x + 0.12, 0.12, size.z + 0.12), xf, col.darkened(0.2), K_PLAIN)
			"fence":
				_fence(det, size, xf, col)
			_:
				var thin := _thin_axis(size)
				if thin >= 0 and thin != 1:
					var w := size.z if thin == 0 else size.x
					var dark := raw.get_luminance() < 0.36
					if kind == K_GLASS and size.y <= 2.6 and w <= 4.5:
						_window(main, det, size, xf, col, pos, false)
						continue
					if dark and size.y >= 1.2 and size.y <= 2.8 and w <= 1.8 and pos.y - size.y * 0.5 < 0.15:
						_door(main, det, size, xf, col, pos)
						continue
					if dark and size.y < 1.2 and w <= 1.6:
						main.add(box(size), xf, col, K_SHUTTER, rnd)
						_sill(det, size, xf, col.darkened(0.15), pos)
						continue
				main.add(cached("__box_" + str(size), func(): return box(size)), xf, col, kind, rnd)
				if i == body_idx:
					_body_trims(det, main, parts, infos, i, size, xf, col, kind)
	return [main.commit(), det.commit()]


static func _vec(a, fallback: Vector3) -> Vector3:
	if a is Array and a.size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return fallback


## Eje delgado (0 = x, 1 = y, 2 = z) de una caja plana (ventanas, puertas, letreros) o -1.
static func _thin_axis(size: Vector3) -> int:
	var m := minf(size.x, minf(size.y, size.z))
	if m > 0.16:
		return -1
	if size.y == m:
		return 1
	# Una pieza de fachada es ancha y alta respecto a su grosor (no un poste ni un listón).
	var w := size.z if size.x == m else size.x
	if w < 0.3 or size.y < 0.3 or w < m * 3.0:
		return -1
	return 0 if size.x == m else 2


## Dirección hacia fuera de una pieza pegada a la fachada (según su posición respecto al centro).
static func _outward(size: Vector3, pos: Vector3, xf: Transform3D) -> Vector3:
	var thin := _thin_axis(size)
	var axis := Vector3.RIGHT if thin == 0 else Vector3.BACK
	var local := xf.basis.inverse() * pos
	var sgn := 1.0 if local.dot(axis) >= 0.0 else -1.0
	if absf(pos.x) < 0.01 and absf(pos.z) < 0.01:
		sgn = 1.0
	return axis * sgn


## Ventana: vidrio con marco, travesaño (si es ancha) y alféizar.
static func _window(main: Buf, det: Buf, size: Vector3, xf: Transform3D, glass: Color, pos: Vector3, explicit: bool) -> void:
	var thin := _thin_axis(size)
	if thin < 0:
		thin = 2
	var w := size.z if thin == 0 else size.x
	var h := size.y
	var d := size.x if thin == 0 else size.z
	var out := _outward(size, pos, xf)
	var along := Vector3.BACK if thin == 0 else Vector3.RIGHT
	var fcol := Color(0.9, 0.87, 0.8) if glass.get_luminance() < 0.5 else Color(0.3, 0.3, 0.32)
	var rnd := fposmod(pos.x * 0.37 + pos.y * 0.91 + pos.z * 0.53, 1.0)
	main.add(box(size), xf, glass, K_GLASS, rnd)
	var fw := clampf(minf(w, h) * 0.08, 0.05, 0.1)
	var fd := d + 0.05
	var depth := Vector3(absf(out.x), 0, absf(out.z)) * fd
	# Marco: dos jambas y dos travesaños.
	for sgn: float in [-1.0, 1.0]:
		det.box(along * sgn * (w * 0.5 + fw * 0.5) + out * 0.015, along.abs() * fw + Vector3(0, h + fw * 2.0, 0) + depth, xf, fcol, K_PLAIN)
		det.box(Vector3(0, sgn * (h * 0.5 + fw * 0.5), 0) + out * 0.015, along.abs() * (w + fw * 2.0) + Vector3(0, fw, 0) + depth, xf, fcol, K_PLAIN)
	# Cruz central en ventanas grandes.
	if w > 0.5:
		det.box(out * 0.02, along.abs() * fw * 0.6 + Vector3(0, h, 0) + depth, xf, fcol, K_PLAIN)
	if h > 0.5 and w <= 3.0:
		det.box(out * 0.02, along.abs() * w + Vector3(0, fw * 0.6, 0) + depth, xf, fcol, K_PLAIN)
	if explicit or w <= 3.0:
		_sill(det, size, xf, fcol.darkened(0.1), pos)


static func _sill(det: Buf, size: Vector3, xf: Transform3D, col: Color, pos: Vector3) -> void:
	var thin := _thin_axis(size)
	if thin < 0:
		return
	var w := size.z if thin == 0 else size.x
	var out := _outward(size, pos, xf)
	var along := Vector3.BACK if thin == 0 else Vector3.RIGHT
	det.box(Vector3(0, -size.y * 0.5 - 0.05, 0) + out * 0.08, along.abs() * (w + 0.18) + Vector3(0, 0.07, 0) + Vector3(absf(out.x), 0, absf(out.z)) * 0.2, xf, col, K_STONE)


## Puerta: hoja de madera con marco, dintel y escalón de piedra.
static func _door(main: Buf, det: Buf, size: Vector3, xf: Transform3D, col: Color, pos: Vector3) -> void:
	var thin := _thin_axis(size)
	if thin < 0:
		thin = 2
	var w := size.z if thin == 0 else size.x
	var h := size.y
	var out := _outward(size, pos, xf)
	var along := Vector3.BACK if thin == 0 else Vector3.RIGHT
	var rnd := fposmod(pos.x * 0.37 + pos.z * 0.53, 1.0)
	main.add(box(size), xf, col, K_WOOD, rnd)
	var fcol := col.darkened(0.35)
	var depth := Vector3(absf(out.x), 0, absf(out.z)) * (minf(size.x, size.z) + 0.06)
	for sgn: float in [-1.0, 1.0]:
		det.box(along * sgn * (w * 0.5 + 0.05), along.abs() * 0.1 + Vector3(0, h + 0.1, 0) + depth, xf, fcol, K_WOOD)
	det.box(Vector3(0, h * 0.5 + 0.07, 0), along.abs() * (w + 0.3) + Vector3(0, 0.14, 0) + depth, xf, fcol, K_WOOD)
	# Escalón de piedra.
	det.box(Vector3(0, -h * 0.5 + 0.06, 0) + out * 0.28, along.abs() * (w + 0.4) + Vector3(0, 0.12, 0) + Vector3(absf(out.x), 0, absf(out.z)) * 0.5, xf, Color(0.55, 0.53, 0.5), K_STONE)
	# Pomo.
	det.box(along * w * 0.3 + out * 0.06, Vector3(0.06, 0.06, 0.06), xf, Color(0.75, 0.6, 0.25), K_METAL)


## Cumbrera y aleros de un techo a dos aguas (PrismMesh: triángulo en XY, extruido en Z).
static func _roof_details(det: Buf, size: Vector3, xf: Transform3D, col: Color) -> void:
	var dark := col.darkened(0.3)
	det.box(Vector3(0, size.y * 0.5 - 0.02, 0), Vector3(0.16, 0.12, size.z + 0.06), xf, dark, K_PLAIN)
	for sgn: float in [-1.0, 1.0]:
		det.box(Vector3(sgn * (size.x * 0.5 - 0.03), -size.y * 0.5 + 0.02, 0), Vector3(0.1, 0.1, size.z + 0.02), xf, dark, K_WOOD)


## Zócalo y cornisa del volumen principal (si el modelo no los trae ya).
static func _body_trims(det: Buf, main: Buf, parts: Array, infos: Array, bi: int, size: Vector3, xf: Transform3D, col: Color, kind: int) -> void:
	var top := xf.origin.y + size.y * 0.5
	var has_base := false
	var has_roof := false
	for j in range(infos.size()):
		if j == bi:
			continue
		var s: String = infos[j][0]
		var sz: Vector3 = infos[j][1]
		var p: Vector3 = infos[j][2]
		var bottom := p.y - (0.0 if s == "floors" else sz.y * 0.5)
		if bottom < 0.1 and sz.y < 1.0 and sz.x >= size.x * 0.8 and sz.z >= size.z * 0.8:
			has_base = true
		if absf(bottom - top) < 0.45 and (s == "prism" or s == "hip" or (sz.x >= size.x - 0.05 and sz.z >= size.z - 0.05)):
			has_roof = true
	var base_kind := K_STONE if kind != K_CONCRETE else K_CONCRETE
	if not has_base:
		main.box(Vector3(0, -size.y * 0.5 + 0.17, 0), Vector3(size.x + 0.08, 0.34, size.z + 0.08), xf, col.darkened(0.28), base_kind)
	if not has_roof:
		det.box(Vector3(0, size.y * 0.5 - 0.04, 0), Vector3(size.x + 0.18, 0.16, size.z + 0.18), xf, col.lightened(0.12), K_PLAIN)
	# Esquineras en muros de estuco/adobe/ladrillo.
	if kind == K_PLASTER or kind == K_BRICK:
		for sx: float in [-1.0, 1.0]:
			for sz2: float in [-1.0, 1.0]:
				det.box(Vector3(sx * size.x * 0.5, 0.0, sz2 * size.z * 0.5), Vector3(0.14, size.y - 0.3, 0.14), xf, col.lightened(0.1) if kind == K_BRICK else col.darkened(0.12), K_PLAIN)


## Cerca de madera: postes y dos travesaños a lo largo de X (size.x = largo, size.y = alto).
static func _fence(det: Buf, size: Vector3, xf: Transform3D, col: Color) -> void:
	var n := maxi(2, int(size.x / 1.2) + 1)
	for k in range(n):
		var x := -size.x * 0.5 + size.x * k / (n - 1)
		det.box(Vector3(x, size.y * 0.5, 0), Vector3(0.1, size.y, 0.1), xf, col, K_WOOD)
	for y: float in [size.y * 0.4, size.y * 0.8]:
		det.box(Vector3(0, y, 0), Vector3(size.x, 0.07, 0.05), xf, col.lightened(0.05), K_WOOD)


## Edificio de varios pisos: franjas de muro y ventanas alternadas, parteluces, zócalo y cornisa.
static func _floors_into(main: Buf, det: Buf, part: Dictionary, size: Vector3, pos: Vector3, wall: Color, tint: float, variant: int) -> void:
	var n := maxi(1, int(part.get("floors", 1)))
	var fh := size.y / n
	var glass := arr_color(part.get("c2"), Color(0.3, 0.4, 0.5)) * tint
	glass.a = 1.0
	glass = vary(glass, K_GLASS, variant)
	var wk := classify(part, "box", size, wall)
	if wk == K_GLASS:
		wk = K_CONCRETE
	var xf := Transform3D(Basis(), pos)
	for i in range(n):
		var y0 := i * fh
		main.box(Vector3(0, y0 + fh * 0.175, 0), Vector3(size.x, fh * 0.35, size.z), xf, wall, wk)
		main.box(Vector3(0, y0 + fh * 0.675, 0), Vector3(size.x - 0.12, fh * 0.65, size.z - 0.12), xf, glass, K_GLASS, fposmod(i * 0.37 + variant * 0.11, 1.0))
	# Parteluces verticales en las cuatro fachadas (una sola pieza alta por columna).
	var mul := wall.darkened(0.12)
	for axis: int in [0, 1]:
		var span := size.x if axis == 0 else size.z
		var cols := maxi(1, int(span / 1.4))
		for k in range(1, cols):
			var t := -span * 0.5 + span * k / cols
			for sgn: float in [-1.0, 1.0]:
				var c := Vector3(t, size.y * 0.5, sgn * (size.z * 0.5 - 0.02)) if axis == 0 else Vector3(sgn * (size.x * 0.5 - 0.02), size.y * 0.5, t)
				var sz := Vector3(0.1, size.y, 0.1)
				det.box(c, sz, xf, mul, K_PLAIN)
	# Esquinas, zócalo y cornisa.
	for sx: float in [-1.0, 1.0]:
		for sz2: float in [-1.0, 1.0]:
			main.box(Vector3(sx * (size.x * 0.5 - 0.1), size.y * 0.5, sz2 * (size.z * 0.5 - 0.1)), Vector3(0.24, size.y, 0.24), xf, wall.darkened(0.08), wk)
	main.box(Vector3(0, 0.3, 0), Vector3(size.x + 0.1, 0.6, size.z + 0.1), xf, wall.darkened(0.3), K_STONE)
	det.box(Vector3(0, size.y - 0.08, 0), Vector3(size.x + 0.22, 0.2, size.z + 0.22), xf, wall.lightened(0.1), K_PLAIN)


static func model_height(parts: Array) -> float:
	var h := 2.0
	for part in parts:
		var size := _vec(part.get("size", [1, 1, 1]), Vector3.ONE)
		var pos := _vec(part.get("pos", [0, 0, 0]), Vector3.ZERO)
		var s := str(part.get("s", ""))
		var top := pos.y + (size.y if s == "floors" or s == "chimney" or s == "fence" else size.y * 0.5)
		h = maxf(h, top)
	return h


# --- Modelos sueltos -------------------------------------------------------------------------------

## Choza: paredes de madera, techo de paja a dos aguas y puerta.
static func make_hut(variant: int) -> Node3D:
	var cfg: Dictionary = GameData.buildings.get("choza", {})
	var s: Array = cfg.get("size", [3.0, 2.0, 3.0])
	var size := Vector3(float(s[0]), float(s[1]), float(s[2]))
	var wall := arr_color(cfg.get("wall_color"), Color(0.55, 0.4, 0.26))
	var roof := arr_color(cfg.get("roof_color"), Color(0.78, 0.66, 0.36))
	var parts := [
		{"s": "box", "size": [size.x, size.y, size.z], "pos": [0, size.y * 0.5, 0], "c": [wall.r, wall.g, wall.b], "m": "madera"},
		{"s": "prism", "size": [size.x + 0.7, 1.5, size.z + 0.5], "pos": [0, size.y + 0.75, 0], "c": [roof.r, roof.g, roof.b], "rot": 90, "m": "paja"},
		{"s": "box", "size": [0.8, 1.3, 0.1], "pos": [0, 0.65, size.z * 0.5 + 0.03], "c": [0.28, 0.18, 0.1]},
	]
	return build_model(parts, 1.0, null, variant % 5)


static func make_well() -> Node3D:
	var parts := [
		{"s": "cyl", "size": [0.9, 0.9, 1.0], "pos": [0, 0.45, 0], "c": [0.58, 0.56, 0.52], "m": "piedra", "seg": 10},
		{"s": "cyl", "size": [1.0, 0.1, 1.0], "pos": [0, 0.92, 0], "c": [0.5, 0.48, 0.45], "seg": 10},
		{"s": "cyl", "size": [0.72, 0.05, 0.72], "pos": [0, 0.88, 0], "c": [0.12, 0.26, 0.4], "m": "vidrio", "seg": 10},
		{"s": "box", "size": [0.12, 1.6, 0.12], "pos": [-0.8, 1.3, 0], "c": [0.4, 0.28, 0.16], "m": "madera"},
		{"s": "box", "size": [0.12, 1.6, 0.12], "pos": [0.8, 1.3, 0], "c": [0.4, 0.28, 0.16], "m": "madera"},
		{"s": "cyl", "size": [0.08, 1.7, 0.08], "pos": [0, 1.75, 0], "c": [0.35, 0.24, 0.14], "rz": 90},
		{"s": "prism", "size": [2.2, 0.6, 1.4], "pos": [0, 2.35, 0], "c": [0.62, 0.3, 0.2], "m": "teja"},
		{"s": "box", "size": [0.3, 0.3, 0.3], "pos": [0, 1.45, 0], "c": [0.4, 0.3, 0.2], "m": "madera"},
	]
	return build_model(parts)


## Persona low-poly (una malla unida por colores) con piernas y brazos aparte para animar el paso.
## Nodos: "Body", "LegL", "LegR", "ArmL", "ArmR" (pivotes en cadera y hombro).
static func make_person(cloth: Color, skin: Color, hair: Color, female: bool) -> Node3D:
	var key := "__person_%s_%s_%s_%s" % [cloth.to_html(), skin.to_html(), hair.to_html(), female]
	var meshes: Array
	if _models.has(key):
		meshes = _models[key]
	else:
		var pants := cloth.darkened(0.45) if not female else cloth.darkened(0.1)
		var shoes := Color(0.16, 0.12, 0.09)
		var body := Buf.new()
		var id := Transform3D()
		# Torso con cintura, cuello y cabeza.
		body.add(cylinder(0.12, 0.15, 0.4, 6), Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.72)), Vector3(0, 0.78, 0)), cloth, K_PLAIN)
		if female:
			body.add(cylinder(0.15, 0.25, 0.34, 7), Transform3D(Basis(), Vector3(0, 0.5, 0)), cloth.darkened(0.08), K_PLAIN)
		else:
			body.add(cylinder(0.15, 0.15, 0.1, 6), Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.75)), Vector3(0, 0.56, 0)), pants.darkened(0.2), K_PLAIN)
		body.add(cylinder(0.045, 0.05, 0.08, 5), Transform3D(Basis(), Vector3(0, 1.01, 0)), skin, K_PLAIN)
		body.add(sphere(0.115, 7, 5), Transform3D(Basis.from_scale(Vector3(1.0, 1.08, 1.0)), Vector3(0, 1.14, 0)), skin, K_PLAIN)
		body.add(sphere(0.122, 7, 3), Transform3D(Basis.from_scale(Vector3(1.0, 0.9, 1.0)), Vector3(0, 1.19, -0.02)), hair, K_PLAIN)
		if female:
			body.box(Vector3(0, 1.08, -0.1), Vector3(0.2, 0.22, 0.06), id, hair, K_PLAIN)
		var leg := Buf.new()
		leg.box(Vector3(0, -0.24, 0), Vector3(0.1, 0.46, 0.11), id, pants, K_PLAIN)
		leg.box(Vector3(0, -0.46, 0.03), Vector3(0.11, 0.06, 0.17), id, shoes, K_PLAIN)
		var arm := Buf.new()
		arm.box(Vector3(0, -0.17, 0), Vector3(0.075, 0.34, 0.08), id, cloth.darkened(0.06), K_PLAIN)
		arm.box(Vector3(0, -0.37, 0), Vector3(0.07, 0.07, 0.07), id, skin, K_PLAIN)
		meshes = [body.commit(), leg.commit(), arm.commit()]
		_models[key] = meshes
	var root := Node3D.new()
	var b := MeshInstance3D.new()
	b.name = "Body"
	b.mesh = meshes[0]
	root.add_child(b)
	for side in [["LegL", -0.065, 1], ["LegR", 0.065, 1], ["ArmL", -0.19, 2], ["ArmR", 0.19, 2]]:
		var mi := MeshInstance3D.new()
		mi.name = side[0]
		mi.mesh = meshes[side[2]]
		mi.position = Vector3(float(side[1]), 0.5 if side[2] == 1 else 0.95, 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if side[2] == 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(mi)
	return root


## Animación de paso: phase avanza con la distancia recorrida; amount 0 = quieto, 1 = caminando.
static func animate_person(model: Node3D, phase: float, amount: float) -> void:
	var sw := sin(phase) * 0.55 * amount
	var n := model.get_node_or_null("LegL") as Node3D
	if n == null:
		return
	n.rotation.x = sw
	(model.get_node("LegR") as Node3D).rotation.x = -sw
	(model.get_node("ArmL") as Node3D).rotation.x = -sw * 0.8
	(model.get_node("ArmR") as Node3D).rotation.x = sw * 0.8


## Etiqueta 3D legible: tamaño fijo en pantalla (no se vuelve gigante ni diminuta con el zoom),
## se desvanece a partir de max_dist (evita que se amontonen al alejarse) y va sobre la geometría
## cercana con prioridad de dibujo alta.
## Mapa v2: `prio` ordena las etiquetas al resolver choques en pantalla (LabelDeclutter: la de menor
## prioridad se desplaza o se oculta) y `scale` achica o agranda el texto.
static func style_label(lab: Label3D, max_dist := 180.0, prio := 1.0, scale := 1.0) -> void:
	lab.fixed_size = true
	lab.pixel_size = 0.00042 * 40.0 * scale / maxf(float(lab.font_size), 1.0)
	LabelDeclutter.register(lab, prio)
	lab.visibility_range_end = max_dist
	lab.visibility_range_end_margin = max_dist * 0.15
	lab.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	lab.outline_modulate = Color(0.05, 0.05, 0.07, 0.85)
	lab.render_priority = 2
	lab.outline_render_priority = 1


static func ghost_mat(ok: bool) -> StandardMaterial3D:
	var key := "__ghost_%s" % ok
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.9, 0.4, 0.45) if ok else Color(0.95, 0.25, 0.2, 0.45)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_materials[key] = m
	return m


static func construction_mat() -> StandardMaterial3D:
	if _materials.has("__site"):
		return _materials["__site"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.72, 0.5, 0.7)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_materials["__site"] = m
	return m


## Andamio de obra alrededor de un edificio (una sola malla unida).
static func scaffold(footprint: float, height: float) -> Node3D:
	var key := "__scaffold_%.2f_%.2f" % [footprint, height]
	var mesh: ArrayMesh
	if _models.has(key):
		mesh = _models[key]
	else:
		var buf := Buf.new()
		var id := Transform3D()
		var w := footprint * 0.5 + 0.3
		var wood := Color(0.6, 0.45, 0.25)
		for x: float in [-w, w]:
			for z: float in [-w, w]:
				buf.box(Vector3(x, height * 0.5, z), Vector3(0.12, height, 0.12), id, wood, K_WOOD)
		var lv := maxi(2, int(height / 1.6))
		for k in range(1, lv + 1):
			var y := height * k / (lv + 0.5)
			for z: float in [-w, w]:
				buf.box(Vector3(0, y, z), Vector3(w * 2.0, 0.08, 0.12), id, wood, K_WOOD)
				buf.box(Vector3(0, y - 0.05, z * 0.93), Vector3(w * 2.0, 0.05, 0.45), id, wood.darkened(0.15), K_WOOD)
		# Diagonales.
		for z: float in [-w, w]:
			var ang := atan2(height * 0.66, w * 2.0)
			buf.box(Vector3(0, height * 0.4, z), Vector3(sqrt(w * w * 4.0 + height * height * 0.44), 0.07, 0.07), Transform3D(Basis(Vector3.BACK, ang), Vector3.ZERO), wood.darkened(0.1), K_WOOD)
		buf.box(Vector3(0, 0.02, 0), Vector3(footprint + 1.0, 0.05, footprint + 1.0), id, Color(0.5, 0.4, 0.28), K_PLAIN)
		mesh = buf.commit()
		_models[key] = mesh
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	root.add_child(mi)
	return root
