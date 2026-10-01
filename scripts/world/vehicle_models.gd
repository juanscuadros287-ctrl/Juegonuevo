class_name VehicleModels
extends RefCounted
## Modelos 3D low-poly de CADA modelo de vehículo y de vagón (docs/VEHICULOS.md).
## - Cada modelo tiene su receta (_r_<id>): silueta propia (no solo otro color) y su librea: colores,
##   franjas, logo en rombo y detalles (faros, chimeneas, domos, grúas, contenedores).
## - Todas las piezas de un modelo se unen en UNA malla con color por vértice y el material compartido de
##   MeshLib (building_mat): una llamada de dibujo por vehículo y un solo material para toda la flota.
## - Las mallas se generan una vez por modelo y se comparten entre todos los vehículos de ese modelo.
## - LOD simple: a más de LOD_DIST metros la malla detallada se cambia por un proxy de 1 a 3 cajas
##   (visibility_range), sin sombra.
## API: VehicleModels.node(id) → Node3D listo para colgar (el frente mira a +Z, el suelo en y = 0).
##      VehicleModels.porter_node(gear) → cargador con su equipo (mecapal, carretilla, bicicleta, motocarro).
##      VehicleModels.has_model(id), VehicleModels.ids() para la galería y las pruebas.

const LOD_DIST := 150.0
const K := 0         # liso
const KL := 10       # emisivo (faros y ventanillas encendidas de noche)

static var _cache := {}     # id -> [malla detallada, proxy, triángulos]


## Kit de construcción: acumula piezas en un buffer (y las marcadas `p` también en el proxy).
class Kit:
	var buf := MeshLib.Buf.new()
	var proxy := MeshLib.Buf.new()
	var tris := 0

	func box(c: Vector3, s: Vector3, col: Color, p := false, rot := Vector3.ZERO, kind := 0) -> void:
		var xf := Transform3D(Basis.from_euler(rot), c)
		buf.box(Vector3.ZERO, s, xf, col, kind)
		tris += 12
		if p:
			proxy.box(Vector3.ZERO, s, xf, col, 0)

	func cyl(c: Vector3, rt: float, rb: float, h: float, col: Color, axis := "y", seg := 8, p := false) -> void:
		var b := Basis()
		if axis == "x":
			b = Basis(Vector3(0, 0, 1), -PI * 0.5)
		elif axis == "z":
			b = Basis(Vector3(1, 0, 0), PI * 0.5)
		buf.add(MeshLib.cylinder(rt, rb, h, seg), Transform3D(b, c), col, 0)
		tris += seg * 4
		if p:
			var r := maxf(rt, rb) * 2.0
			var s := Vector3(r, h, r)
			if axis == "x":
				s = Vector3(h, r, r)
			elif axis == "z":
				s = Vector3(r, r, h)
			proxy.box(Vector3.ZERO, s, Transform3D(Basis(), c), col, 0)

	func wheel(c: Vector3, r: float, w: float, col := Color(0.1, 0.1, 0.1), hub := Color(0.6, 0.6, 0.62)) -> void:
		cyl(c, r, r, w, col, "x", 8)
		cyl(c + Vector3(signf(c.x) * w * 0.5, 0, 0), r * 0.45, r * 0.45, 0.04, hub, "x", 6)

	func wheels(xs: Array, zs: Array, y: float, r: float, w: float, col := Color(0.1, 0.1, 0.1), hub := Color(0.6, 0.6, 0.62)) -> void:
		for z in zs:
			for x in xs:
				wheel(Vector3(float(x), y, float(z)), r, w, col, hub)

	func wedge(c: Vector3, s: Vector3, col: Color, rot := Vector3.ZERO) -> void:
		buf.add(MeshLib.prism(s), Transform3D(Basis.from_euler(rot), c), col, 0)
		tris += 8

	func ball(c: Vector3, s: Vector3, col: Color) -> void:
		buf.add(MeshLib.sphere(0.5, 6, 4), Transform3D(Basis.from_scale(s), c), col, 0)
		tris += 48

	func light(c: Vector3, s: Vector3, col := Color(1.0, 0.92, 0.7)) -> void:
		box(c, s, col, false, Vector3.ZERO, 10)

	## Logo en rombo a ambos lados (x = ±x) con un punto central de otro color.
	func logo(x: float, y: float, z: float, size: float, col: Color, dot: Color) -> void:
		for sx in [-1.0, 1.0]:
			box(Vector3(x * sx, y, z), Vector3(0.03, size, size), col, false, Vector3(PI * 0.25, 0, 0))
			box(Vector3((x + 0.02) * sx, y, z), Vector3(0.03, size * 0.35, size * 0.35), dot, false, Vector3(PI * 0.25, 0, 0))

	## Franja horizontal a ambos lados de una caja de ancho w.
	func stripe(w: float, y: float, z: float, length: float, h: float, col: Color) -> void:
		for sx in [-1.0, 1.0]:
			box(Vector3((w * 0.5 + 0.015) * sx, y, z), Vector3(0.03, h, length), col)

	## Persona simple (1,6 m) unida a la malla: piernas, torso, brazos, cabeza y sombrero opcional.
	func person(c: Vector3, cloth: Color, hat := Color(0, 0, 0, 0), seated := false, arms_fwd := false) -> void:
		var skin := Color(0.78, 0.58, 0.42)
		var pants := cloth.darkened(0.45)
		if seated:
			box(c + Vector3(0, 0.12, 0.12), Vector3(0.3, 0.14, 0.4), pants)
		else:
			box(c + Vector3(-0.08, 0.4, 0), Vector3(0.12, 0.8, 0.14), pants)
			box(c + Vector3(0.08, 0.4, 0), Vector3(0.12, 0.8, 0.14), pants)
		var t := c + Vector3(0, 0.0 if seated else 0.8, 0)
		box(t + Vector3(0, 0.3, 0), Vector3(0.36, 0.55, 0.22), cloth)
		if arms_fwd:
			box(t + Vector3(-0.22, 0.38, 0.22), Vector3(0.1, 0.1, 0.45), cloth.darkened(0.1))
			box(t + Vector3(0.22, 0.38, 0.22), Vector3(0.1, 0.1, 0.45), cloth.darkened(0.1))
		else:
			box(t + Vector3(-0.23, 0.27, 0), Vector3(0.1, 0.5, 0.12), cloth.darkened(0.1))
			box(t + Vector3(0.23, 0.27, 0), Vector3(0.1, 0.5, 0.12), cloth.darkened(0.1))
		box(t + Vector3(0, 0.72, 0), Vector3(0.22, 0.24, 0.22), skin)
		if hat.a > 0.0:
			box(t + Vector3(0, 0.86, 0), Vector3(0.42, 0.04, 0.42), hat)
			box(t + Vector3(0, 0.93, 0), Vector3(0.24, 0.12, 0.24), hat)

	## Cuadrúpedo (caballo, mula, burro, buey). s = escala, head_up = cuello alto (caballo).
	func animal(c: Vector3, s: float, col: Color, head_up := false, ears := 0.0, horns := false) -> void:
		var legh := 0.7 * s
		box(c + Vector3(0, legh + 0.28 * s, 0), Vector3(0.46 * s, 0.56 * s, 1.3 * s), col, true)
		for lx in [-0.15, 0.15]:
			for lz in [-0.45, 0.45]:
				box(c + Vector3(lx * s, legh * 0.5, lz * s), Vector3(0.11 * s, legh, 0.11 * s), col.darkened(0.15))
		var neck := c + Vector3(0, legh + 0.55 * s, 0.7 * s)
		if head_up:
			box(neck, Vector3(0.2 * s, 0.6 * s, 0.26 * s), col, false, Vector3(-0.5, 0, 0))
			box(neck + Vector3(0, 0.32 * s, 0.22 * s), Vector3(0.2 * s, 0.22 * s, 0.46 * s), col)
			box(neck + Vector3(0, 0.1 * s, -0.12 * s), Vector3(0.06 * s, 0.5 * s, 0.12 * s), col.darkened(0.5), false, Vector3(-0.5, 0, 0))
		else:
			box(neck + Vector3(0, -0.05 * s, 0.1 * s), Vector3(0.24 * s, 0.4 * s, 0.4 * s), col)
		if ears > 0.0:
			var hy := 0.62 if head_up else 0.2
			for ex in [-0.07, 0.07]:
				box(neck + Vector3(ex * s, hy * s + ears * 0.5, 0.2 * s), Vector3(0.05 * s, ears, 0.08 * s), col.darkened(0.2))
		if horns:
			for hx in [-1.0, 1.0]:
				cyl(neck + Vector3(hx * 0.2 * s, 0.2 * s, 0.1 * s), 0.02 * s, 0.05 * s, 0.3 * s, Color(0.9, 0.86, 0.72), "x")
		box(c + Vector3(0, legh + 0.3 * s, -0.7 * s), Vector3(0.06 * s, 0.4 * s, 0.06 * s), col.darkened(0.4))

	func commit() -> Array:
		return [buf.commit(), proxy.commit(), tris]


static func _c(hex: String) -> Color:
	return Color(hex)


# --- API ------------------------------------------------------------------------------------------------

static func has_model(id: String) -> bool:
	return VehicleModels.new().has_method("_r_" + id)


## Modelos con receta (vehículos y vagones, sin los equipos de cargador).
static func ids() -> Array:
	var out := []
	for m in VehicleModels.new().get_method_list():
		var n := str(m.get("name", ""))
		if n.begins_with("_r_") and not n.begins_with("_r_pie_"):
			out.append(n.substr(3))
	return out


static func meshes(id: String) -> Array:
	if _cache.has(id):
		return _cache[id]
	var vm := VehicleModels.new()
	var k := Kit.new()
	var fn := "_r_" + id
	if not vm.has_method(fn):
		fn = "_r_" + _fallback(id)
	vm.call(fn, k)
	var out := k.commit()
	_cache[id] = out
	return out


## Modelo de reserva según el tipo (modelos de datos sin receta).
static func _fallback(id: String) -> String:
	if VehicleCatalog.wagon_types().has(id):
		return str(VehicleCatalog.wagon_def(id).get("clase", "cerrado"))
	var f: String = {"animal": "mula", "carreta": "carreta", "camion": "camion", "tren": "tren_diesel", "barco": "vapor_barco",
			"avion": "avion", "pie": "pie_mecapal"}.get(VehicleCatalog.tipo_of(id), "carreta")
	return f


## Nodo con LOD: malla detallada cerca, proxy de cajas lejos.
static func node(id: String) -> Node3D:
	var m := meshes(id)
	var root := Node3D.new()
	root.name = "Veh_" + id
	root.set_meta("model_id", id)
	var d := MeshInstance3D.new()
	d.name = "Detail"
	d.mesh = m[0]
	d.visibility_range_end = LOD_DIST
	d.visibility_range_end_margin = 8.0
	root.add_child(d)
	var p := MeshInstance3D.new()
	p.name = "Proxy"
	p.mesh = m[1]
	p.visibility_range_begin = LOD_DIST
	p.visibility_range_begin_margin = 8.0
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)
	return root


static func porter_node(gear: String) -> Node3D:
	var id := "pie_" + gear
	if not VehicleModels.new().has_method("_r_" + id):
		id = "pie_mecapal"
	return node(id)


static func triangles(id: String) -> int:
	return int(meshes(id)[2])


# === Recetas ===========================================================================================
# El frente mira a +Z. Unidades en metros del juego.

# --- A pie (equipo de los cargadores) -------------------------------------------------------------------

func _r_pie_mecapal(k: Kit) -> void:
	k.person(Vector3.ZERO, _c("#8a6a45"), Color(0, 0, 0, 0))
	k.box(Vector3(0, 1.2, -0.25), Vector3(0.45, 0.5, 0.32), _c("#a2824f"), true)
	k.box(Vector3(0, 1.62, -0.05), Vector3(0.3, 0.04, 0.3), _c("#6b4f2e"))   # banda del mecapal


func _r_pie_carretilla(k: Kit) -> void:
	k.person(Vector3(0, 0, -0.6), _c("#4f6d8a"), _c("#c9b27a"), false, true)
	k.box(Vector3(0, 0.55, 0.35), Vector3(0.6, 0.35, 0.8), _c("#b43c2a"), true, Vector3(0.12, 0, 0))
	k.box(Vector3(0, 0.78, 0.35), Vector3(0.5, 0.15, 0.6), _c("#8c7a5a"))
	k.wheel(Vector3(0, 0.22, 0.85), 0.22, 0.1)
	for x in [-0.22, 0.22]:
		k.box(Vector3(x, 0.55, -0.15), Vector3(0.05, 0.05, 0.9), _c("#5a3d22"))


func _r_pie_bicicleta(k: Kit) -> void:
	k.wheel(Vector3(0, 0.35, 0.7), 0.35, 0.06)
	k.wheel(Vector3(0, 0.35, -0.55), 0.35, 0.06)
	k.box(Vector3(0, 0.6, 0.05), Vector3(0.06, 0.06, 1.2), _c("#1f8a5a"), false, Vector3(0.25, 0, 0))
	k.box(Vector3(0, 0.75, 1.0), Vector3(0.7, 0.45, 0.55), _c("#e0a93a"), true)   # canasta delantera
	k.stripe(0.7, 0.75, 1.0, 0.55, 0.08, _c("#1f8a5a"))
	k.person(Vector3(0, 0.35, -0.2), _c("#3a6ea5"), _c("#1f8a5a"), true, true)


func _r_pie_motocarro(k: Kit) -> void:
	k.wheel(Vector3(0, 0.3, 1.0), 0.3, 0.12)
	k.wheels([-0.6, 0.6], [-0.7], 0.3, 0.3, 0.14)
	k.box(Vector3(0, 0.75, -0.6), Vector3(1.3, 0.7, 1.2), _c("#2f5fa8"), true)
	k.stripe(1.3, 0.9, -0.6, 1.2, 0.12, _c("#f2f2f2"))
	k.box(Vector3(0, 0.55, 0.4), Vector3(0.4, 0.2, 1.0), _c("#c0392b"))
	k.person(Vector3(0, 0.45, 0.35), _c("#c0392b"), _c("#222222"), true, true)
	k.light(Vector3(0, 0.8, 1.2), Vector3(0.18, 0.12, 0.05))


# --- Animales ---------------------------------------------------------------------------------------------

func _r_burro(k: Kit) -> void:
	k.animal(Vector3.ZERO, 0.8, _c("#8d8a86"), false, 0.28)
	for px in [-0.28, 0.28]:
		k.box(Vector3(px, 0.75, 0), Vector3(0.18, 0.3, 0.45), _c("#b08850"))
	k.person(Vector3(0.65, 0, 0.45), _c("#7a6a50"), _c("#d8c48a"))


func _r_mula(k: Kit) -> void:
	k.animal(Vector3.ZERO, 1.0, _c("#6e5438"), false, 0.2)
	k.box(Vector3(0, 1.3, 0), Vector3(0.62, 0.08, 0.7), _c("#b0302a"))   # manta roja
	for px in [-0.34, 0.34]:
		k.box(Vector3(px, 0.95, -0.05), Vector3(0.24, 0.42, 0.56), _c("#9c7a48"), true)
		k.box(Vector3(px, 1.0, -0.05), Vector3(0.26, 0.06, 0.58), _c("#3d2b1a"))
	k.person(Vector3(0.75, 0, 0.5), _c("#5a4a34"), _c("#3a2a1a"))


func _r_caballo(k: Kit) -> void:
	k.animal(Vector3.ZERO, 1.15, _c("#4a2a16"), true, 0.12)
	k.box(Vector3(0, 1.48, 0.05), Vector3(0.5, 0.08, 0.5), _c("#2b1a10"))   # silla
	for px in [-0.3, 0.3]:
		k.box(Vector3(px, 1.2, -0.35), Vector3(0.14, 0.32, 0.4), _c("#c8a060"))
	k.person(Vector3(0, 1.1, 0.05), _c("#2e4a7a"), _c("#1a1a1a"), true)


func _r_buey(k: Kit) -> void:
	for x in [-0.45, 0.45]:
		k.animal(Vector3(x, 0, 0.9), 1.05, _c("#3b2d24"), false, 0.0, true)
	k.box(Vector3(0, 1.25, 1.65), Vector3(1.5, 0.12, 0.14), _c("#6b4a2a"))   # yugo
	k.box(Vector3(0, 0.3, -1.1), Vector3(1.2, 0.2, 1.8), _c("#6b4a2a"), true)   # rastra
	for i in range(3):
		k.cyl(Vector3(0, 0.55 + i * 0.12, -1.1 + (i - 1) * 0.1), 0.14, 0.14, 1.6, _c("#8a6036"), "z")
	k.person(Vector3(1.1, 0, 1.2), _c("#6a5a3a"), _c("#d8c48a"))


# --- Carretas ---------------------------------------------------------------------------------------------

func _cart_horse(k: Kit, z: float, col := Color("#5a3820"), x := 0.0) -> void:
	k.animal(Vector3(x, 0, z), 1.0, col, true)
	k.box(Vector3(x * 0.5, 0.95, z - 0.95), Vector3(0.06, 0.06, 0.9), _c("#3d2b1a"))


func _r_carreta(k: Kit) -> void:
	_cart_horse(k, 1.4)
	k.box(Vector3(0, 0.75, -0.5), Vector3(1.3, 0.3, 1.7), _c("#7a5230"), true)
	k.box(Vector3(0, 1.1, -0.5), Vector3(1.05, 0.45, 1.3), _c("#b89a62"))
	k.wheels([-0.72, 0.72], [-0.5], 0.5, 0.5, 0.1, _c("#5a3d22"), _c("#3d2b1a"))
	k.person(Vector3(0.35, 0.9, 0.25), _c("#6a5a3a"), _c("#d8c48a"), true)


func _r_carreta_grande(k: Kit) -> void:
	_cart_horse(k, 2.1, _c("#5a3820"), -0.4)
	_cart_horse(k, 2.1, _c("#2a1e14"), 0.4)
	k.box(Vector3(0, 0.95, -0.4), Vector3(1.7, 0.25, 3.0), _c("#6b4527"), true)
	for sx in [-1.0, 1.0]:
		k.box(Vector3(0.85 * sx, 1.35, -0.4), Vector3(0.08, 0.6, 3.0), _c("#8a5c34"))
	k.box(Vector3(0, 1.45, -0.4), Vector3(1.5, 0.7, 2.6), _c("#a88a5a"))
	k.stripe(1.72, 1.2, -0.4, 3.0, 0.1, _c("#2c5aa0"))
	k.wheels([-0.9, 0.9], [0.6, -1.4], 0.55, 0.55, 0.12, _c("#5a3d22"), _c("#2c5aa0"))


func _r_diligencia(k: Kit) -> void:
	_cart_horse(k, 2.0, _c("#f0ece0"), -0.35)
	_cart_horse(k, 2.0, _c("#e8e2d0"), 0.35)
	k.box(Vector3(0, 1.45, -0.6), Vector3(1.4, 1.2, 2.2), _c("#9e1b1b"), true)
	k.box(Vector3(0, 2.1, -0.6), Vector3(1.5, 0.1, 2.3), _c("#2a1a10"))
	k.box(Vector3(0, 2.3, -0.8), Vector3(1.1, 0.35, 1.4), _c("#b89a62"))   # equipaje en el techo
	for sx in [-1.0, 1.0]:
		k.box(Vector3(0.71 * sx, 1.6, -0.6), Vector3(0.03, 0.45, 0.8), _c("#1c2a3a"))
	k.stripe(1.4, 1.0, -0.6, 2.2, 0.08, _c("#e6b422"))
	k.logo(0.72, 1.25, -1.35, 0.25, _c("#e6b422"), _c("#9e1b1b"))
	k.wheels([-0.78, 0.78], [0.3, -1.5], 0.55, 0.55, 0.1, _c("#e6b422"), _c("#2a1a10"))
	k.person(Vector3(0, 1.9, 0.6), _c("#2a1a10"), _c("#2a1a10"), true)


func _r_carreta_barriles(k: Kit) -> void:
	_cart_horse(k, 1.5, _c("#7a4a26"))
	k.box(Vector3(0, 0.75, -0.5), Vector3(1.4, 0.25, 1.9), _c("#5e3f24"), true)
	for i in range(3):
		k.cyl(Vector3((i - 1) * 0.45, 1.1, -0.5), 0.26, 0.26, 1.5, _c("#8c5a2e"), "z", 8)
		k.cyl(Vector3((i - 1) * 0.45, 1.1, -0.5), 0.27, 0.27, 0.08, _c("#2a2a2a"), "z", 8)
	k.wheels([-0.78, 0.78], [-0.5], 0.5, 0.5, 0.1, _c("#5a3d22"), _c("#8c5a2e"))


func _r_carreta_hielo(k: Kit) -> void:
	_cart_horse(k, 1.8, _c("#8a8078"))
	k.box(Vector3(0, 1.3, -0.5), Vector3(1.35, 1.1, 2.1), _c("#eef3f6"), true)
	k.box(Vector3(0, 1.9, -0.5), Vector3(1.45, 0.1, 2.2), _c("#2e6fa8"))
	k.stripe(1.35, 1.1, -0.5, 2.1, 0.14, _c("#2e6fa8"))
	k.logo(0.68, 1.45, -0.5, 0.35, _c("#6fc3ff"), _c("#ffffff"))
	k.wheels([-0.72, 0.72], [0.2, -1.2], 0.42, 0.42, 0.1, _c("#2e6fa8"), _c("#eef3f6"))


# --- Camiones ---------------------------------------------------------------------------------------------

func _cab(k: Kit, z: float, col: Color, w := 1.3, h := 1.0, y := 0.9) -> void:
	k.box(Vector3(0, y, z), Vector3(w, h, 1.0), col, true)
	k.box(Vector3(0, y + h * 0.2, z + 0.51), Vector3(w * 0.85, h * 0.4, 0.03), _c("#22313f"))
	for sx in [-1.0, 1.0]:
		k.light(Vector3(w * 0.35 * sx, y - h * 0.3, z + 0.52), Vector3(0.18, 0.12, 0.03))


func _r_carro_vapor(k: Kit) -> void:
	k.box(Vector3(0, 0.75, -0.5), Vector3(1.4, 0.3, 2.2), _c("#5a4028"), true)
	k.box(Vector3(0, 1.2, -0.6), Vector3(1.2, 0.6, 1.6), _c("#a88a5a"))
	k.cyl(Vector3(0, 1.1, 1.2), 0.5, 0.5, 1.4, _c("#1e1e20"), "z", 10, true)
	k.cyl(Vector3(0, 2.0, 1.6), 0.14, 0.18, 1.0, _c("#111111"))
	k.cyl(Vector3(0, 1.1, 1.92), 0.52, 0.52, 0.06, _c("#b8962e"), "z", 10)
	k.wheels([-0.75, 0.75], [1.2, -0.9], 0.45, 0.45, 0.14, _c("#5a1a12"), _c("#b8962e"))


func _r_furgoneta(k: Kit) -> void:
	k.box(Vector3(0, 1.05, -0.3), Vector3(1.3, 1.3, 2.3), _c("#d9d9d9"), true)
	k.box(Vector3(0, 0.6, 1.1), Vector3(1.3, 0.4, 0.8), _c("#c23b22"))
	k.box(Vector3(0, 1.25, 0.86), Vector3(1.1, 0.4, 0.04), _c("#22313f"), false, Vector3(-0.5, 0, 0))
	k.stripe(1.3, 0.8, -0.3, 2.3, 0.18, _c("#c23b22"))
	k.logo(0.66, 1.25, -0.4, 0.4, _c("#c23b22"), _c("#ffd23f"))
	k.light(Vector3(-0.45, 0.65, 1.52), Vector3(0.2, 0.12, 0.03))
	k.light(Vector3(0.45, 0.65, 1.52), Vector3(0.2, 0.12, 0.03))
	k.wheels([-0.65, 0.65], [0.9, -1.0], 0.32, 0.32, 0.2)


func _r_camion(k: Kit) -> void:
	_cab(k, 1.4, _c("#b02a1e"))
	k.box(Vector3(0, 0.55, -0.3), Vector3(1.4, 0.2, 3.2), _c("#2a2a2a"))
	k.box(Vector3(0, 1.1, -0.5), Vector3(1.4, 0.9, 2.4), _c("#3f5a3a"), true)
	k.box(Vector3(0, 1.62, -0.5), Vector3(1.44, 0.14, 2.44), _c("#566f4e"))   # lona
	k.logo(0.71, 1.1, -0.5, 0.45, _c("#f2f2f2"), _c("#b02a1e"))
	k.wheels([-0.7, 0.7], [1.2, -1.0], 0.35, 0.35, 0.2)


func _r_camion_4x4(k: Kit) -> void:
	k.box(Vector3(0, 1.25, 1.1), Vector3(1.5, 1.0, 1.2), _c("#5d6b2f"), true)
	k.box(Vector3(0, 1.45, 1.71), Vector3(1.3, 0.4, 0.03), _c("#22313f"))
	k.box(Vector3(0, 0.95, -0.7), Vector3(1.6, 0.35, 2.4), _c("#4a5526"), true)
	for sx in [-1.0, 1.0]:
		k.box(Vector3(0.78 * sx, 1.35, -0.7), Vector3(0.05, 0.5, 2.4), _c("#4a5526"))
		k.box(Vector3(0.7 * sx, 1.9, 0.2), Vector3(0.08, 0.7, 0.08), _c("#222222"))   # arco antivuelco
	k.box(Vector3(0, 2.25, 0.2), Vector3(1.48, 0.08, 0.08), _c("#222222"))
	k.stripe(1.5, 1.05, 1.1, 1.2, 0.14, _c("#d9b44a"))
	k.cyl(Vector3(0, 1.3, -1.95), 0.45, 0.45, 0.25, _c("#151515"), "z")   # llanta de repuesto
	k.box(Vector3(0, 0.75, 1.75), Vector3(1.5, 0.2, 0.12), _c("#222222"))   # parachoques
	k.light(Vector3(-0.5, 1.95, 1.2), Vector3(0.2, 0.15, 0.05))
	k.light(Vector3(0.5, 1.95, 1.2), Vector3(0.2, 0.15, 0.05))
	k.wheels([-0.82, 0.82], [1.1, -1.2], 0.55, 0.55, 0.35, _c("#151515"), _c("#d9b44a"))


func _r_camion_volteo(k: Kit) -> void:
	_cab(k, 1.6, _c("#e07b1a"), 1.4, 1.1, 1.0)
	k.box(Vector3(0, 0.6, -0.4), Vector3(1.5, 0.2, 3.2), _c("#2a2a2a"))
	k.box(Vector3(0, 1.3, -0.6), Vector3(1.7, 1.0, 2.8), _c("#e0a81a"), true, Vector3(0.1, 0, 0))
	k.wedge(Vector3(0, 1.95, -0.6), Vector3(1.4, 0.5, 2.2), _c("#6a5a4a"), Vector3(0.1, 0, 0))   # montón
	for i in range(4):
		k.box(Vector3(0, 1.3, -1.8 + i * 0.8), Vector3(1.74, 0.9, 0.08), _c("#b8860b"), false, Vector3(0.1, 0, 0))
	k.wheels([-0.72, 0.72], [1.4, -0.6, -1.4], 0.42, 0.42, 0.25)


func _r_camion_cisterna(k: Kit) -> void:
	_cab(k, 1.6, _c("#1d4e89"))
	k.box(Vector3(0, 0.55, -0.4), Vector3(1.3, 0.2, 3.4), _c("#2a2a2a"))
	k.cyl(Vector3(0, 1.3, -0.5), 0.72, 0.72, 3.0, _c("#c8ccd2"), "z", 10, true)
	for z in [-1.9, 0.9]:
		k.cyl(Vector3(0, 1.3, z), 0.75, 0.75, 0.1, _c("#1d4e89"), "z", 10)
	k.stripe(1.46, 1.3, -0.5, 2.6, 0.14, _c("#e8491d"))
	k.cyl(Vector3(0, 2.05, -0.5), 0.2, 0.2, 0.15, _c("#8a9098"))   # domo
	k.wheels([-0.7, 0.7], [1.4, -1.0, -1.7], 0.38, 0.38, 0.22)


func _r_camion_frigorifico(k: Kit) -> void:
	_cab(k, 1.7, _c("#1b6fb5"), 1.4, 1.1)
	k.box(Vector3(0, 0.55, -0.3), Vector3(1.4, 0.2, 3.6), _c("#2a2a2a"))
	k.box(Vector3(0, 1.45, -0.6), Vector3(1.55, 1.6, 3.0), _c("#f4f7fa"), true)
	k.box(Vector3(0, 1.9, 1.0), Vector3(1.0, 0.6, 0.25), _c("#9aa4ad"))   # equipo de frío
	k.stripe(1.55, 0.85, -0.6, 3.0, 0.2, _c("#1b6fb5"))
	k.stripe(1.55, 1.08, -0.6, 3.0, 0.06, _c("#6fc3ff"))
	k.logo(0.78, 1.6, -0.6, 0.55, _c("#6fc3ff"), _c("#ffffff"))
	k.wheels([-0.72, 0.72], [1.5, -1.3, -1.9], 0.38, 0.38, 0.22)


func _r_camion_pesado(k: Kit) -> void:
	_cab(k, 2.0, _c("#8e1f2f"), 1.5, 1.3, 1.15)
	k.box(Vector3(0, 0.7, -0.6), Vector3(1.6, 0.25, 4.4), _c("#333333"), true)
	for i in range(3):
		k.box(Vector3((i - 1) * 0.45, 1.05, -0.8), Vector3(0.3, 0.4, 3.6), _c("#6d7a86"))   # vigas de acero
	for z in [-2.2, 0.6]:
		k.box(Vector3(0, 1.1, z), Vector3(1.62, 0.5, 0.08), _c("#e8b90f"))   # cadenas amarillas
	k.box(Vector3(0, 2.0, 2.0), Vector3(1.5, 0.15, 0.9), _c("#e8b90f"))   # visera
	k.wheels([-0.75, 0.75], [2.0, -1.2, -2.0, -2.8], 0.42, 0.42, 0.28)


func _r_camion_blindado(k: Kit) -> void:
	k.box(Vector3(0, 1.2, -0.2), Vector3(1.5, 1.5, 3.6), _c("#3c4148"), true)
	k.wedge(Vector3(0, 2.1, -0.2), Vector3(1.5, 0.3, 3.4), _c("#3c4148"))
	k.box(Vector3(0, 1.5, 1.61), Vector3(1.2, 0.35, 0.03), _c("#1a2530"))
	for sx in [-1.0, 1.0]:
		k.box(Vector3(0.76 * sx, 1.55, 0.9), Vector3(0.03, 0.2, 0.4), _c("#1a2530"))
	k.stripe(1.5, 0.9, -0.2, 3.6, 0.12, _c("#d4af37"))
	k.logo(0.76, 1.35, -0.6, 0.45, _c("#d4af37"), _c("#3c4148"))
	k.light(Vector3(0, 2.3, 0.6), Vector3(0.3, 0.1, 0.1), _c("#ff9a2a"))   # baliza
	k.light(Vector3(-0.5, 0.75, 1.61), Vector3(0.2, 0.12, 0.03))
	k.light(Vector3(0.5, 0.75, 1.61), Vector3(0.2, 0.12, 0.03))
	k.wheels([-0.76, 0.76], [1.1, -1.3], 0.42, 0.42, 0.26)


func _r_trailer(k: Kit) -> void:
	_cab(k, 1.9, _c("#1f4e9c"), 1.5, 1.3, 1.1)
	k.box(Vector3(0, 2.0, 1.75), Vector3(1.4, 0.5, 0.6), _c("#1f4e9c"))   # deflector
	k.box(Vector3(0, 1.45, -1.4), Vector3(1.65, 1.8, 4.6), _c("#f0f0ec"), true)
	k.stripe(1.65, 1.0, -1.4, 4.6, 0.25, _c("#1f4e9c"))
	k.stripe(1.65, 1.3, -1.4, 4.6, 0.08, _c("#f2a900"))
	k.logo(0.83, 1.8, -1.0, 0.7, _c("#1f4e9c"), _c("#f2a900"))
	k.wheels([-0.8, 0.8], [1.6, 0.9, -2.4, -3.2], 0.36, 0.36, 0.22)


# --- Locomotoras ------------------------------------------------------------------------------------------

func _bogies(k: Kit, zs: Array, r := 0.5) -> void:
	k.wheels([-0.9, 0.9], zs, r, r, 0.15, _c("#2a2a2a"), _c("#8a1a12"))


func _r_tren_vapor(k: Kit) -> void:
	k.cyl(Vector3(0, 1.8, 0.6), 0.85, 0.85, 4.2, _c("#1c1c1e"), "z", 12, true)
	k.cyl(Vector3(0, 1.8, 2.72), 0.87, 0.87, 0.08, _c("#b8962e"), "z", 12)
	k.box(Vector3(0, 2.1, -2.2), Vector3(2.0, 2.2, 1.8), _c("#7a1a12"), true)
	k.box(Vector3(0, 3.25, -2.2), Vector3(2.2, 0.12, 2.0), _c("#1c1c1e"))
	k.cyl(Vector3(0, 3.1, 2.2), 0.3, 0.22, 1.2, _c("#111111"))
	k.cyl(Vector3(0, 2.75, 0.6), 0.25, 0.3, 0.4, _c("#b8962e"))   # domo
	k.box(Vector3(0, 0.75, 0), Vector3(2.0, 0.5, 6.0), _c("#2a2a2a"))
	k.wedge(Vector3(0, 0.6, 3.1), Vector3(1.8, 0.6, 0.5), _c("#8a1a12"), Vector3(PI * 0.5, 0, 0))   # quitapiedras
	k.light(Vector3(0, 2.5, 2.8), Vector3(0.3, 0.3, 0.1))
	_bogies(k, [-2.0, 0.0, 2.0], 0.55)


func _r_vapor_expreso(k: Kit) -> void:
	k.cyl(Vector3(0, 1.8, 0.2), 0.95, 0.95, 4.4, _c("#1f5a3a"), "z", 12, true)
	k.cyl(Vector3(0, 1.8, 2.8), 0.0, 0.95, 0.9, _c("#1f5a3a"), "z", 12)   # frente aerodinámico
	k.box(Vector3(0, 2.0, -2.5), Vector3(2.1, 2.2, 1.6), _c("#1f5a3a"), true)
	k.stripe(2.0, 1.4, 0.0, 6.2, 0.14, _c("#d4af37"))
	k.stripe(1.95, 1.8, 0.2, 4.4, 0.06, _c("#d4af37"))
	k.box(Vector3(0, 0.8, 0), Vector3(2.0, 0.6, 6.4), _c("#1a1a1a"))
	k.logo(1.0, 2.1, -2.5, 0.5, _c("#d4af37"), _c("#1f5a3a"))
	k.light(Vector3(0, 1.8, 3.3), Vector3(0.3, 0.3, 0.1))
	k.wheels([-0.95, 0.95], [-1.4, 0.6], 0.8, 0.8, 0.15, _c("#d4af37"), _c("#1a1a1a"))
	_bogies(k, [2.4], 0.4)


func _r_tren_diesel(k: Kit) -> void:
	k.box(Vector3(0, 1.7, -0.3), Vector3(2.0, 2.0, 5.4), _c("#d98a14"), true)
	k.box(Vector3(0, 2.3, 2.3), Vector3(2.2, 1.4, 1.4), _c("#d98a14"), true)
	k.box(Vector3(0, 2.6, 3.01), Vector3(1.8, 0.5, 0.03), _c("#22313f"))
	k.stripe(2.2, 1.3, 0.0, 6.2, 0.25, _c("#f2f2f2"))
	k.box(Vector3(0, 2.8, -1.5), Vector3(0.8, 0.2, 1.2), _c("#555555"))   # escape
	k.box(Vector3(0, 0.8, 0), Vector3(2.1, 0.5, 6.2), _c("#2a2a2a"))
	k.light(Vector3(0, 1.8, 3.05), Vector3(0.3, 0.25, 0.05))
	_bogies(k, [-2.1, -1.2, 1.2, 2.1], 0.45)


func _r_diesel_pesada(k: Kit) -> void:
	k.box(Vector3(0, 1.85, -0.5), Vector3(2.2, 2.3, 6.6), _c("#f2c200"), true)
	k.box(Vector3(0, 2.6, 3.0), Vector3(2.4, 1.6, 1.6), _c("#f2c200"), true)
	k.box(Vector3(0, 2.9, 3.81), Vector3(2.0, 0.5, 0.03), _c("#22313f"))
	for i in range(5):   # galones negros
		k.box(Vector3(0, 1.35, 3.82), Vector3(0.18, 0.9, 0.03), _c("#111111"), false, Vector3(0, 0, 0.7 if i % 2 == 0 else -0.7))
	k.stripe(2.2, 1.0, -0.5, 6.6, 0.18, _c("#111111"))
	for i in range(3):
		k.cyl(Vector3(0, 3.1, -2.5 + i * 1.2), 0.35, 0.35, 0.2, _c("#444444"))   # ventiladores
	k.box(Vector3(0, 0.85, 0), Vector3(2.3, 0.6, 8.0), _c("#1c1c1c"))
	k.light(Vector3(-0.6, 2.0, 3.85), Vector3(0.25, 0.25, 0.05))
	k.light(Vector3(0.6, 2.0, 3.85), Vector3(0.25, 0.25, 0.05))
	_bogies(k, [-3.2, -2.4, -1.6, 1.6, 2.4, 3.2], 0.45)


func _r_tren_electrico(k: Kit) -> void:
	k.box(Vector3(0, 1.9, 0), Vector3(2.2, 2.4, 6.4), _c("#1e56a0"), true)
	k.box(Vector3(0, 2.3, 3.3), Vector3(2.2, 1.6, 0.4), _c("#1e56a0"), false, Vector3(0.3, 0, 0))
	k.box(Vector3(0, 2.6, 3.21), Vector3(1.9, 0.6, 0.03), _c("#22313f"))
	k.stripe(2.2, 1.4, 0.0, 6.4, 0.35, _c("#f4f4f4"))
	k.stripe(2.2, 1.18, 0.0, 6.4, 0.08, _c("#e63946"))
	k.box(Vector3(0, 3.3, -1.5), Vector3(0.1, 0.8, 0.1), _c("#333333"), false, Vector3(0.6, 0, 0))   # pantógrafo
	k.box(Vector3(0, 3.65, -1.3), Vector3(1.2, 0.05, 0.1), _c("#333333"))
	k.box(Vector3(0, 0.75, 0), Vector3(2.2, 0.4, 6.4), _c("#2a2a2a"))
	k.logo(1.11, 2.1, -1.0, 0.5, _c("#f4f4f4"), _c("#e63946"))
	k.light(Vector3(0, 1.4, 3.3), Vector3(0.8, 0.15, 0.05))
	_bogies(k, [-2.2, -1.4, 1.4, 2.2], 0.42)


func _r_alta_velocidad(k: Kit) -> void:
	k.box(Vector3(0, 1.55, -0.6), Vector3(2.2, 2.0, 6.0), _c("#f5f5f5"), true)
	k.box(Vector3(0, 1.25, 3.1), Vector3(2.1, 1.1, 2.2), _c("#f5f5f5"), true, Vector3(0.42, 0, 0))
	k.box(Vector3(0, 1.95, 2.55), Vector3(1.6, 0.06, 1.0), _c("#1a2530"), false, Vector3(0.42, 0, 0))
	k.wedge(Vector3(0, 1.0, 4.15), Vector3(2.0, 0.6, 0.7), _c("#f5f5f5"), Vector3(PI * 0.5, 0, 0))
	k.stripe(2.2, 1.2, -0.6, 6.0, 0.22, _c("#d62828"))
	k.stripe(2.2, 1.95, -0.6, 6.0, 0.3, _c("#1a2530"))   # ventanas corridas
	k.box(Vector3(0, 2.7, -2.0), Vector3(0.9, 0.12, 1.4), _c("#9aa4ad"))
	k.box(Vector3(0, 0.55, -0.3), Vector3(2.0, 0.3, 6.6), _c("#2a2a2a"))
	k.light(Vector3(-0.6, 1.0, 4.05), Vector3(0.3, 0.1, 0.05))
	k.light(Vector3(0.6, 1.0, 4.05), Vector3(0.3, 0.1, 0.05))
	k.wheels([-0.9, 0.9], [-2.5, -1.7, 1.2, 2.0], 0.36, 0.36, 0.15, _c("#2a2a2a"), _c("#9aa4ad"))


# --- Vagones ----------------------------------------------------------------------------------------------

func _chassis(k: Kit, ln := 5.0, col := Color("#262628")) -> void:
	k.box(Vector3(0, 0.8, 0), Vector3(2.0, 0.35, ln), col)
	k.wheels([-0.9, 0.9], [-ln * 0.36, -ln * 0.36 + 0.8, ln * 0.36 - 0.8, ln * 0.36], 0.4, 0.4, 0.12, _c("#1a1a1a"), _c("#555555"))
	k.box(Vector3(0, 0.8, ln * 0.5 + 0.15), Vector3(0.3, 0.2, 0.3), _c("#111111"))   # enganche


func _r_granelero(k: Kit) -> void:
	_chassis(k, 5.0, _c("#3a2a1e"))
	k.box(Vector3(0, 1.6, 0), Vector3(2.0, 1.2, 4.8), _c("#6b4a30"), true)
	for i in range(6):
		k.box(Vector3(0, 1.6, -2.0 + i * 0.8), Vector3(2.04, 1.22, 0.06), _c("#4a3220"))   # tablones
	k.box(Vector3(0, 2.25, 0), Vector3(1.8, 0.2, 4.4), _c("#1d1a18"))


func _r_tolva_acero(k: Kit) -> void:
	_chassis(k, 5.2)
	k.wedge(Vector3(0, 1.25, -1.2), Vector3(2.0, 0.8, 2.2), _c("#7a2e22"), Vector3(PI, 0, 0))
	k.wedge(Vector3(0, 1.25, 1.2), Vector3(2.0, 0.8, 2.2), _c("#7a2e22"), Vector3(PI, 0, 0))
	k.box(Vector3(0, 2.1, 0), Vector3(2.1, 0.9, 5.0), _c("#8f3a2c"), true)
	k.stripe(2.1, 2.3, 0, 5.0, 0.1, _c("#f2f2f2"))
	k.box(Vector3(0, 2.6, 0), Vector3(1.9, 0.15, 4.6), _c("#2a2522"))


func _r_tolva_autodescarga(k: Kit) -> void:
	_chassis(k, 5.6)
	k.box(Vector3(0, 2.1, 0), Vector3(2.2, 1.7, 5.4), _c("#6a7f3a"), true)
	for z in [-1.6, 0.0, 1.6]:
		k.wedge(Vector3(0, 1.0, z), Vector3(1.2, 0.6, 1.0), _c("#4e5e2a"), Vector3(PI, 0, 0))   # compuertas
	k.box(Vector3(0, 3.0, 0), Vector3(2.2, 0.1, 5.4), _c("#4e5e2a"))   # techo corredizo
	k.stripe(2.2, 1.6, 0, 5.4, 0.12, _c("#f2c200"))
	k.logo(1.11, 2.3, 1.6, 0.5, _c("#f2c200"), _c("#6a7f3a"))


func _r_cisterna(k: Kit) -> void:
	_chassis(k)
	k.cyl(Vector3(0, 1.9, 0), 0.9, 0.9, 4.6, _c("#bfc3c8"), "z", 12, true)
	k.cyl(Vector3(0, 2.85, 0), 0.25, 0.3, 0.3, _c("#8a8f96"))
	k.stripe(1.82, 1.9, 0, 4.0, 0.1, _c("#222222"))


func _r_cisterna_presion(k: Kit) -> void:
	_chassis(k, 5.8)
	k.cyl(Vector3(0, 2.05, 0), 1.05, 1.05, 5.0, _c("#f0f0f0"), "z", 12, true)
	for z in [-2.55, 2.55]:
		k.ball(Vector3(0, 2.05, z), Vector3(2.0, 2.0, 0.5), _c("#f0f0f0"))
	k.stripe(2.12, 2.05, 0, 4.6, 0.3, _c("#8a7bd8"))
	k.box(Vector3(0, 3.15, 0), Vector3(0.8, 0.15, 1.2), _c("#555555"))   # pasarela
	k.logo(1.07, 2.05, 1.6, 0.4, _c("#e63946"), _c("#f0f0f0"))


func _r_cerrado(k: Kit) -> void:
	_chassis(k)
	k.box(Vector3(0, 1.9, 0), Vector3(2.0, 1.8, 4.8), _c("#7a2f22"), true)
	k.wedge(Vector3(0, 2.95, 0), Vector3(2.1, 0.3, 4.8), _c("#5a2016"))
	k.box(Vector3(1.01, 1.8, 0), Vector3(0.03, 1.4, 1.2), _c("#5a2016"))
	k.box(Vector3(-1.01, 1.8, 0), Vector3(0.03, 1.4, 1.2), _c("#5a2016"))


func _r_furgon_acero(k: Kit) -> void:
	_chassis(k, 5.4)
	k.box(Vector3(0, 2.0, 0), Vector3(2.1, 2.0, 5.2), _c("#2f5a7a"), true)
	for i in range(9):
		k.box(Vector3(0, 2.0, -2.4 + i * 0.6), Vector3(2.14, 2.0, 0.06), _c("#274a64"))   # costillas
	k.box(Vector3(0, 3.02, 0), Vector3(2.1, 0.06, 5.2), _c("#9aa4ad"))
	k.stripe(2.14, 2.7, 0, 5.2, 0.1, _c("#f2f2f2"))
	k.logo(1.08, 2.0, 0, 0.6, _c("#f2f2f2"), _c("#2f5a7a"))


func _r_contenedor_doble(k: Kit) -> void:
	k.box(Vector3(0, 0.55, 0), Vector3(2.0, 0.3, 6.2), _c("#262628"))
	k.wheels([-0.9, 0.9], [-2.4, -1.7, 1.7, 2.4], 0.36, 0.36, 0.12)
	k.box(Vector3(0, 1.55, 0), Vector3(2.1, 1.7, 6.0), _c("#c0392b"), true)
	k.box(Vector3(0, 3.25, 0), Vector3(2.1, 1.7, 6.0), _c("#1f6f9c"), true)
	for i in range(10):
		k.box(Vector3(0, 1.55, -2.7 + i * 0.6), Vector3(2.14, 1.7, 0.05), _c("#a02f23"))
		k.box(Vector3(0, 3.25, -2.7 + i * 0.6), Vector3(2.14, 1.7, 0.05), _c("#185a80"))
	k.stripe(2.14, 3.6, 0, 6.0, 0.18, _c("#f2f2f2"))


func _r_frigorifico(k: Kit) -> void:
	_chassis(k)
	k.box(Vector3(0, 1.9, 0), Vector3(2.0, 1.8, 4.8), _c("#f4f1e8"), true)
	for z in [-1.8, 1.8]:
		k.box(Vector3(0, 2.9, z), Vector3(0.6, 0.2, 0.6), _c("#8a8074"))   # escotillas de hielo
	k.stripe(2.0, 2.6, 0, 4.8, 0.12, _c("#a0522d"))
	k.box(Vector3(1.01, 1.8, 0), Vector3(0.03, 1.3, 1.0), _c("#d9d3c4"))
	k.box(Vector3(-1.01, 1.8, 0), Vector3(0.03, 1.3, 1.0), _c("#d9d3c4"))


func _r_frigorifico_mecanico(k: Kit) -> void:
	_chassis(k, 5.4)
	k.box(Vector3(0, 2.0, -0.2), Vector3(2.1, 2.0, 4.8), _c("#ffffff"), true)
	k.box(Vector3(0, 2.0, 2.45), Vector3(1.9, 1.6, 0.5), _c("#6b7580"))   # equipo de frío
	for i in range(4):
		k.box(Vector3(0, 1.6 + i * 0.25, 2.71), Vector3(1.4, 0.06, 0.03), _c("#2a2a2a"))
	k.stripe(2.1, 1.3, -0.2, 4.8, 0.25, _c("#1b6fb5"))
	k.logo(1.06, 2.2, -0.4, 0.6, _c("#6fc3ff"), _c("#1b6fb5"))


func _r_plataforma(k: Kit) -> void:
	_chassis(k)
	k.box(Vector3(0, 1.02, 0), Vector3(2.1, 0.1, 5.0), _c("#5a4028"), true)
	for x in [-0.55, 0.0, 0.55]:
		k.cyl(Vector3(x, 1.35, 0), 0.25, 0.25, 4.4, _c("#7a7f86"), "z", 8)   # tubos
	for sx in [-1.0, 1.0]:
		for z in [-2.0, 0.0, 2.0]:
			k.box(Vector3(1.0 * sx, 1.4, z), Vector3(0.08, 0.7, 0.08), _c("#3a2a1e"))   # estacas


func _r_plataforma_pesada(k: Kit) -> void:
	k.box(Vector3(0, 0.9, 0), Vector3(2.2, 0.35, 6.0), _c("#2b2b2b"))
	k.wedge(Vector3(0, 0.55, 0), Vector3(1.4, 0.5, 4.0), _c("#2b2b2b"), Vector3(PI, 0, 0))   # vientre de pez
	k.wheels([-0.9, 0.9], [-2.6, -2.0, -1.4, 1.4, 2.0, 2.6], 0.38, 0.38, 0.12)
	k.box(Vector3(0, 1.6, 0.4), Vector3(1.8, 1.1, 2.6), _c("#e07b1a"), true)   # máquina
	k.cyl(Vector3(0, 2.3, 0.4), 0.45, 0.45, 1.9, _c("#555555"), "z", 8)
	k.box(Vector3(0, 1.25, -2.0), Vector3(1.6, 0.4, 1.2), _c("#6d7a86"))
	for z in [-0.9, 1.7]:
		k.box(Vector3(0, 1.6, z), Vector3(2.22, 0.08, 0.08), _c("#f2c200"))   # cadenas


func _r_pasajeros(k: Kit) -> void:
	_chassis(k, 5.6)
	k.box(Vector3(0, 2.0, 0), Vector3(2.0, 1.9, 5.6), _c("#2a6a52"), true)
	k.cyl(Vector3(0, 2.95, 0), 1.0, 1.0, 5.6, _c("#1e4a3a"), "z", 10)
	for i in range(6):
		k.box(Vector3(0, 2.25, -2.25 + i * 0.9), Vector3(2.04, 0.6, 0.55), _c("#f2e6b8"), false, Vector3.ZERO, KL)
	k.stripe(2.0, 1.6, 0, 5.6, 0.1, _c("#d4af37"))


func _r_coche_salon(k: Kit) -> void:
	_chassis(k, 6.0, _c("#1a1a1a"))
	k.box(Vector3(0, 2.05, 0), Vector3(2.1, 2.0, 6.0), _c("#5a1a2a"), true)
	k.box(Vector3(0, 3.1, -0.8), Vector3(1.8, 0.35, 4.0), _c("#5a1a2a"))   # claraboya
	for i in range(4):
		k.box(Vector3(0, 2.3, -2.1 + i * 1.4), Vector3(2.14, 0.8, 1.0), _c("#ffe7a8"), false, Vector3.ZERO, KL)
	k.stripe(2.1, 1.55, 0, 6.0, 0.12, _c("#d4af37"))
	k.stripe(2.1, 2.9, 0, 6.0, 0.08, _c("#d4af37"))
	k.box(Vector3(0, 1.6, -3.1), Vector3(2.2, 0.08, 0.3), _c("#d4af37"))   # balcón trasero
	k.logo(1.06, 1.75, 2.2, 0.4, _c("#d4af37"), _c("#5a1a2a"))


func _r_furgon_valores(k: Kit) -> void:
	_chassis(k, 5.0, _c("#111111"))
	k.box(Vector3(0, 1.9, 0), Vector3(2.0, 1.8, 4.8), _c("#454b52"), true)
	k.wedge(Vector3(0, 2.95, 0), Vector3(2.0, 0.3, 4.8), _c("#353a40"))
	for i in range(8):
		k.box(Vector3(1.01, 1.9, -2.1 + i * 0.6), Vector3(0.04, 1.7, 0.05), _c("#2a2e33"))
		k.box(Vector3(-1.01, 1.9, -2.1 + i * 0.6), Vector3(0.04, 1.7, 0.05), _c("#2a2e33"))
	k.stripe(2.0, 2.5, 0, 4.8, 0.1, _c("#d4af37"))
	k.logo(1.03, 1.8, 0, 0.55, _c("#d4af37"), _c("#454b52"))


# --- Barcos -----------------------------------------------------------------------------------------------

func _hull(k: Kit, w: float, h: float, ln: float, col: Color, deck: Color, bow := 0.25) -> void:
	k.box(Vector3(0, h * 0.35, -ln * bow * 0.5), Vector3(w, h, ln * (1.0 - bow)), col, true)
	k.wedge(Vector3(0, h * 0.35, ln * (0.5 - bow * 0.5)), Vector3(w, ln * bow, h), col, Vector3(PI * 0.5, 0, 0))
	k.box(Vector3(0, h * 0.85 + 0.05, -ln * bow * 0.5), Vector3(w * 0.96, 0.1, ln * (1.0 - bow) - 0.1), deck)


func _r_balsa(k: Kit) -> void:
	for i in range(5):
		k.cyl(Vector3((i - 2) * 0.34, 0.15, 0), 0.17, 0.17, 3.2, _c("#8a5a32"), "z", 6, i == 2)
	k.box(Vector3(0, 0.55, -0.3), Vector3(1.0, 0.5, 1.4), _c("#b89a62"))
	k.box(Vector3(0.5, 1.0, 1.2), Vector3(0.05, 1.6, 0.05), _c("#5a3d22"), false, Vector3(0.4, 0, 0))   # pértiga
	k.person(Vector3(0, 0.3, 1.0), _c("#7a6a50"), _c("#d8c48a"))


func _r_barcaza(k: Kit) -> void:
	k.box(Vector3(0, 0.35, 0), Vector3(2.6, 0.8, 6.0), _c("#3a3f44"), true)
	k.wedge(Vector3(0, 0.35, 3.3), Vector3(2.6, 0.8, 0.6), _c("#3a3f44"), Vector3(PI * 0.5, 0, 0))
	k.box(Vector3(0, 0.9, -0.3), Vector3(2.2, 0.4, 4.6), _c("#2a2522"))
	k.wedge(Vector3(0, 1.3, -0.3), Vector3(2.0, 0.6, 4.2), _c("#5a4a3a"))   # montón de carga
	k.stripe(2.6, 0.55, 0, 6.0, 0.1, _c("#c9a45c"))
	k.box(Vector3(0, 1.1, -2.8), Vector3(1.2, 0.8, 0.6), _c("#c9a45c"))
	k.person(Vector3(0.3, 0.75, -2.5), _c("#3a5a8a"), _c("#222222"))


func _r_goleta(k: Kit) -> void:
	_hull(k, 2.2, 1.0, 8.0, _c("#f0ece0"), _c("#b89a62"), 0.3)
	k.stripe(2.2, 0.55, -1.2, 5.6, 0.14, _c("#1f4e9c"))
	for z in [1.4, -1.6]:
		k.box(Vector3(0, 4.4, z), Vector3(0.14, 7.0, 0.14), _c("#5a3d22"))
		k.wedge(Vector3(0.15, 4.5, z - 0.9), Vector3(2.2, 5.0, 0.06), _c("#fbf8ef"), Vector3(0, PI * 0.5, 0))
	k.box(Vector3(0, 1.3, 4.3), Vector3(0.08, 0.08, 2.4), _c("#5a3d22"), false, Vector3(-0.3, 0, 0))   # bauprés
	k.logo(1.11, 0.55, 2.0, 0.35, _c("#1f4e9c"), _c("#f0ece0"))


func _r_velero(k: Kit) -> void:
	_hull(k, 2.6, 1.2, 8.0, _c("#5a3a20"), _c("#9e7a4c"), 0.22)
	k.box(Vector3(0, 4.5, 0.5), Vector3(0.18, 7.0, 0.18), _c("#4a3220"))
	k.box(Vector3(0, 4.6, 0.6), Vector3(3.6, 4.2, 0.08), _c("#efe8d4"))   # vela cuadra
	k.box(Vector3(0, 6.6, 0.6), Vector3(3.8, 0.1, 0.12), _c("#4a3220"))
	k.box(Vector3(0, 1.5, -2.2), Vector3(1.6, 0.8, 2.0), _c("#b89a62"))
	k.box(Vector3(0, 1.3, -3.4), Vector3(2.2, 0.8, 1.0), _c("#6b4527"))   # castillo de popa
	k.stripe(2.6, 0.8, -0.9, 6.2, 0.12, _c("#b8962e"))


func _r_vapor_barco(k: Kit) -> void:
	_hull(k, 3.2, 1.6, 12.0, _c("#1c1c1e"), _c("#9e7a4c"), 0.2)
	k.stripe(3.2, 0.3, -1.2, 9.6, 0.2, _c("#8a1a12"))
	k.box(Vector3(0, 2.2, -1.0), Vector3(2.4, 1.6, 4.0), _c("#efeae0"), true)
	k.cyl(Vector3(0, 4.0, 0.3), 0.45, 0.45, 2.6, _c("#b8261a"))
	k.cyl(Vector3(0, 5.35, 0.3), 0.47, 0.47, 0.3, _c("#111111"))
	for sx in [-1.0, 1.0]:
		k.cyl(Vector3(1.65 * sx, 1.1, -1.0), 1.1, 1.1, 0.4, _c("#6b4527"), "x", 10)   # ruedas de paletas
	k.box(Vector3(0, 1.9, 3.6), Vector3(2.2, 0.9, 3.0), _c("#b89a62"))


func _r_lancha(k: Kit) -> void:
	_hull(k, 1.8, 0.8, 5.0, _c("#f4f4f4"), _c("#c8a878"), 0.4)
	k.stripe(1.8, 0.5, -0.5, 3.0, 0.14, _c("#e63946"))
	k.box(Vector3(0, 1.1, -0.2), Vector3(1.4, 0.6, 1.2), _c("#1a2530"), false, Vector3(-0.3, 0, 0))   # parabrisas
	k.box(Vector3(0, 0.95, -1.7), Vector3(1.2, 0.5, 1.2), _c("#9aa4ad"))   # carga
	k.box(Vector3(0, 0.6, -2.6), Vector3(0.5, 0.8, 0.4), _c("#222222"))   # fuera de borda
	k.person(Vector3(0, 0.45, 0.4), _c("#e63946"), _c("#222222"), true)


func _r_carguero(k: Kit) -> void:
	_hull(k, 4.2, 2.4, 18.0, _c("#8a1c14"), _c("#4a4f55"), 0.15)
	k.box(Vector3(0, 3.4, -7.0), Vector3(3.6, 3.0, 3.0), _c("#f2f2ee"), true)
	k.box(Vector3(0, 4.5, -5.49), Vector3(3.2, 0.5, 0.03), _c("#1a2530"))
	k.box(Vector3(0, 2.7, 1.0), Vector3(3.4, 1.2, 9.0), _c("#2f5a45"))   # bodegas
	for z in [-2.0, 3.5]:
		k.box(Vector3(1.2, 4.0, z), Vector3(0.3, 4.0, 0.3), _c("#f2c200"))   # grúas
		k.box(Vector3(0.4, 5.9, z), Vector3(1.8, 0.2, 0.2), _c("#f2c200"))
	k.cyl(Vector3(0, 5.4, -7.8), 0.5, 0.5, 1.6, _c("#222222"))
	k.stripe(4.2, 0.5, -1.4, 15.0, 0.3, _c("#f2f2f2"))


func _r_granelero_mar(k: Kit) -> void:
	_hull(k, 4.6, 2.6, 20.0, _c("#2c4a6e"), _c("#6a4a2a"), 0.12)
	k.stripe(4.6, 0.6, -1.2, 17.0, 0.35, _c("#c9302c"))
	for i in range(5):
		k.box(Vector3(0, 2.75, -4.0 + i * 3.0), Vector3(3.6, 0.6, 2.2), _c("#7a7f86"))   # escotillas
	k.box(Vector3(0, 3.7, -8.2), Vector3(4.0, 3.0, 2.6), _c("#f2f2ee"), true)
	k.cyl(Vector3(0, 5.8, -8.8), 0.55, 0.55, 1.4, _c("#c9a45c"))
	k.logo(2.32, 1.7, 6.0, 1.1, _c("#c9a45c"), _c("#2c4a6e"))


func _r_petrolero(k: Kit) -> void:
	_hull(k, 4.6, 2.2, 22.0, _c("#1d1d1f"), _c("#8a2a1e"), 0.12)
	k.stripe(4.6, 0.3, -1.3, 19.0, 0.4, _c("#8a2a1e"))
	k.box(Vector3(0, 2.6, 1.0), Vector3(0.6, 0.6, 16.0), _c("#8a8f96"))   # tubería central
	for i in range(4):
		k.cyl(Vector3(1.2, 2.5, -4.0 + i * 3.6), 0.35, 0.35, 0.5, _c("#c8ccd2"))
	k.box(Vector3(0, 3.8, -9.3), Vector3(4.2, 3.2, 2.6), _c("#f2f2ee"), true)
	k.cyl(Vector3(0, 6.0, -10.0), 0.5, 0.5, 1.4, _c("#8a7bd8"))
	k.logo(2.32, 1.5, 6.5, 1.0, _c("#8a7bd8"), _c("#f2f2ee"))


func _r_buque_frigorifico(k: Kit) -> void:
	_hull(k, 4.0, 2.4, 17.0, _c("#f4f7fa"), _c("#9aa4ad"), 0.18)
	k.stripe(4.0, 0.9, -1.2, 13.0, 0.35, _c("#1b6fb5"))
	k.box(Vector3(0, 3.0, 0.5), Vector3(3.6, 2.2, 8.0), _c("#f4f7fa"), true)   # bodega aislada
	k.box(Vector3(0, 4.2, -6.2), Vector3(3.6, 3.4, 2.6), _c("#f4f7fa"))
	k.box(Vector3(0, 5.0, -4.89), Vector3(3.2, 0.5, 0.03), _c("#1a2530"))
	for z in [-1.5, 2.5]:
		k.box(Vector3(-1.4, 4.4, z), Vector3(0.25, 2.8, 0.25), _c("#6fc3ff"))
	k.logo(1.82, 3.0, 0.5, 1.0, _c("#6fc3ff"), _c("#1b6fb5"))


func _r_portacontenedores(k: Kit) -> void:
	_hull(k, 5.0, 2.8, 24.0, _c("#1f3355"), _c("#555a60"), 0.12)
	k.stripe(5.0, 0.4, -1.4, 21.0, 0.4, _c("#c0392b"))
	k.box(Vector3(0, 4.2, -10.0), Vector3(4.6, 4.0, 3.0), _c("#f2f2ee"), true)
	var cols := [_c("#c0392b"), _c("#1f6f9c"), _c("#2e8b57"), _c("#e0a81a"), _c("#7a4a8a")]
	for zi in range(6):
		for yi in range(2):
			k.box(Vector3(0, 2.8 + yi * 1.25, -6.0 + zi * 3.0), Vector3(4.4, 1.2, 2.6), cols[(zi * 2 + yi) % cols.size()], zi == 2 and yi == 0)


# --- Aviones ----------------------------------------------------------------------------------------------

func _r_biplano_correo(k: Kit) -> void:
	k.box(Vector3(0, 0.3, 0), Vector3(1.1, 1.1, 6.0), _c("#c8102e"), true)
	k.cyl(Vector3(0, 0.3, 3.2), 0.5, 0.55, 0.5, _c("#333333"), "z")
	k.box(Vector3(0, 0.3, 3.5), Vector3(0.12, 2.2, 0.08), _c("#5a3d22"))   # hélice
	for y in [-0.3, 1.2]:
		k.box(Vector3(0, y, 1.0), Vector3(9.0, 0.12, 1.4), _c("#f2e6b8"), y < 0.0)
	for sx in [-1.0, 1.0]:
		k.box(Vector3(2.8 * sx, 0.45, 1.0), Vector3(0.06, 1.5, 0.06), _c("#5a3d22"))
	k.box(Vector3(0, 0.6, -2.7), Vector3(3.2, 0.1, 0.9), _c("#f2e6b8"))
	k.box(Vector3(0, 1.1, -2.8), Vector3(0.1, 1.2, 0.9), _c("#c8102e"))
	k.logo(0.56, 0.3, -0.8, 0.6, _c("#f2e6b8"), _c("#1f4e9c"))
	k.wheels([-0.6, 0.6], [1.6], -0.6, 0.3, 0.12)


func _r_avion(k: Kit) -> void:
	k.box(Vector3(0, 0, 0), Vector3(2.2, 2.2, 14.0), _c("#e0e2e4"), true)
	k.box(Vector3(0, 0.2, 7.6), Vector3(1.6, 1.5, 2.0), _c("#2a3e60"))
	k.box(Vector3(0, 0.3, 0.6), Vector3(18.0, 0.35, 3.2), _c("#e0e2e4"), true)
	k.box(Vector3(0, 0.8, -6.2), Vector3(6.5, 0.3, 1.8), _c("#e0e2e4"))
	k.box(Vector3(0, 2.4, -6.0), Vector3(0.3, 3.2, 2.2), _c("#b8261a"))
	for ex in [-4.5, 4.5]:
		k.cyl(Vector3(ex, -0.2, 1.8), 0.45, 0.45, 1.8, _c("#50555c"), "z", 8)
		k.box(Vector3(ex, -0.2, 2.8), Vector3(0.1, 2.4, 0.1), _c("#222222"))   # hélices
	k.stripe(2.2, 0.4, 0, 14.0, 0.25, _c("#b8261a"))


func _r_jet_carga(k: Kit) -> void:
	k.cyl(Vector3(0, 0, 0), 1.4, 1.4, 16.0, _c("#f4f4f4"), "z", 10, true)
	k.cyl(Vector3(0, 0, 8.8), 0.0, 1.4, 1.8, _c("#f4f4f4"), "z", 10)
	k.box(Vector3(0, 0.45, 8.3), Vector3(1.6, 0.35, 0.6), _c("#1a2530"))
	k.box(Vector3(0, -0.3, 0.5), Vector3(20.0, 0.3, 3.4), _c("#dcdcdc"), true, Vector3(0, 0, 0))
	for ex in [-4.5, -7.0, 4.5, 7.0]:
		k.cyl(Vector3(ex, -0.9, 1.4), 0.5, 0.5, 2.2, _c("#8a8f96"), "z", 8)
	k.box(Vector3(0, 0.6, -7.4), Vector3(7.0, 0.25, 1.8), _c("#dcdcdc"))
	k.box(Vector3(0, 2.4, -7.4), Vector3(0.3, 3.4, 2.4), _c("#1f4e9c"))
	k.stripe(2.8, 0.2, 0, 15.0, 0.3, _c("#1f4e9c"))


func _r_jet_express(k: Kit) -> void:
	k.cyl(Vector3(0, 0, 0), 0.9, 0.9, 11.0, _c("#6a1b9a"), "z", 10, true)
	k.cyl(Vector3(0, 0, 6.3), 0.0, 0.9, 1.6, _c("#6a1b9a"), "z", 10)
	k.box(Vector3(0, 0.35, 5.9), Vector3(1.0, 0.3, 0.6), _c("#1a2530"))
	k.wedge(Vector3(0, -0.2, 0.0), Vector3(12.0, 4.0, 0.25), _c("#ff8f00"), Vector3(PI * 0.5, 0, 0))   # ala en flecha
	for ex in [-1.3, 1.3]:
		k.cyl(Vector3(ex, 0.5, -3.8), 0.45, 0.45, 2.0, _c("#8a8f96"), "z", 8)   # motores traseros
	k.box(Vector3(0, 1.7, -4.8), Vector3(0.25, 2.6, 1.6), _c("#ff8f00"), false, Vector3(-0.35, 0, 0))
	k.box(Vector3(0, 2.9, -5.3), Vector3(4.2, 0.2, 1.1), _c("#6a1b9a"))   # cola en T
	k.stripe(1.8, 0.0, 0, 10.0, 0.18, _c("#ff8f00"))
	k.logo(0.92, 0.2, 2.5, 0.8, _c("#ff8f00"), _c("#ffffff"))


func _r_carguero_aereo(k: Kit) -> void:
	k.box(Vector3(0, 0.2, 0), Vector3(3.6, 3.4, 20.0), _c("#5b6770"), true)
	k.wedge(Vector3(0, 0.2, 11.0), Vector3(3.6, 2.0, 3.4), _c("#5b6770"), Vector3(PI * 0.5, 0, 0))
	k.box(Vector3(0, 1.4, 10.2), Vector3(2.4, 0.5, 0.6), _c("#1a2530"))
	k.box(Vector3(0, 2.0, 1.0), Vector3(28.0, 0.4, 4.4), _c("#4e5961"), true)   # ala alta
	for ex in [-5.0, -9.0, 5.0, 9.0]:
		k.cyl(Vector3(ex, 1.2, 2.2), 0.7, 0.7, 2.6, _c("#3a4046"), "z", 8)
	k.box(Vector3(0, 4.4, -9.0), Vector3(0.4, 5.0, 3.0), _c("#5b6770"))
	k.box(Vector3(0, 6.8, -9.4), Vector3(10.0, 0.3, 2.2), _c("#4e5961"))   # cola en T
	k.box(Vector3(0, -1.6, 0.0), Vector3(4.2, 0.4, 4.0), _c("#3a4046"))   # carenado del tren
	k.stripe(3.6, -0.6, 0, 20.0, 0.4, _c("#d0703c"))
	k.logo(1.82, 0.8, -4.0, 1.4, _c("#d0703c"), _c("#5b6770"))
