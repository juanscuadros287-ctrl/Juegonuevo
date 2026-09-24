class_name MeshLib
extends RefCounted
## Fábrica de mallas y materiales low-poly compartidos (con caché).

static var _materials := {}
static var _meshes := {}


static func mat(color: Color, roughness := 0.9) -> StandardMaterial3D:
	var key := "%s_%.2f" % [color.to_html(), roughness]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	_materials[key] = m
	return m


static func vertex_color_mat() -> StandardMaterial3D:
	if _materials.has("__vc"):
		return _materials["__vc"]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	_materials["__vc"] = m
	return m


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


static func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func cylinder(top: float, bottom: float, height: float, segments := 6) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = segments
	c.rings = 1
	return c


static func sphere(radius: float, segments := 6, rings := 4) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = segments
	s.rings = rings
	return s


static func prism(size: Vector3) -> PrismMesh:
	var p := PrismMesh.new()
	p.size = size
	return p


static func arr_color(a, fallback: Color) -> Color:
	if a is Array and a.size() >= 3:
		return Color(float(a[0]), float(a[1]), float(a[2]))
	return fallback


## Choza: paredes de madera, techo de paja a dos aguas y puerta.
static func make_hut(variant: int) -> Node3D:
	var cfg: Dictionary = GameData.buildings.get("choza", {})
	var size := Vector3(3.0, 2.0, 3.0)
	var s: Array = cfg.get("size", [3.0, 2.0, 3.0])
	size = Vector3(float(s[0]), float(s[1]), float(s[2]))
	var wall := arr_color(cfg.get("wall_color"), Color(0.55, 0.4, 0.26))
	var roof := arr_color(cfg.get("roof_color"), Color(0.78, 0.66, 0.36))
	var shade := 0.88 + float(variant % 5) * 0.05
	var root := Node3D.new()
	root.add_child(mesh_node(cached("hut_walls", func(): return box(size)), mat(wall * shade), Vector3(0, size.y * 0.5, 0)))
	var roof_node := mesh_node(cached("hut_roof", func(): return prism(Vector3(size.x + 0.7, 1.5, size.z + 0.5))),
			mat(roof * shade), Vector3(0, size.y + 0.75, 0))
	roof_node.rotation_degrees.y = 90
	root.add_child(roof_node)
	root.add_child(mesh_node(cached("hut_door", func(): return box(Vector3(0.8, 1.3, 0.1))),
			mat(Color(0.28, 0.18, 0.1)), Vector3(0, 0.65, size.z * 0.5 + 0.03)))
	return root


static func make_well() -> Node3D:
	var root := Node3D.new()
	root.add_child(mesh_node(cylinder(0.9, 1.0, 0.9, 8), mat(Color(0.55, 0.55, 0.55)), Vector3(0, 0.45, 0)))
	root.add_child(mesh_node(cylinder(0.7, 0.7, 0.05, 8), mat(Color(0.15, 0.3, 0.45), 0.2), Vector3(0, 0.88, 0)))
	for x in [-0.8, 0.8]:
		root.add_child(mesh_node(box(Vector3(0.12, 1.6, 0.12)), mat(Color(0.4, 0.28, 0.16)), Vector3(x, 1.3, 0)))
	var roof := mesh_node(prism(Vector3(2.2, 0.6, 1.4)), mat(Color(0.5, 0.32, 0.2)), Vector3(0, 2.35, 0))
	root.add_child(roof)
	return root


## Persona low-poly: cuerpo (ropa), cabeza y cabello.
static func make_person(cloth: Color, skin: Color, hair: Color, female: bool) -> Node3D:
	var root := Node3D.new()
	var bottom := 0.3 if female else 0.2
	var body_mesh: Mesh = cached("person_body_f" if female else "person_body_m", func(): return cylinder(0.13, bottom, 0.75, 6))
	root.add_child(mesh_node(body_mesh, mat(cloth), Vector3(0, 0.45, 0)))
	root.add_child(mesh_node(cached("person_legs", func(): return box(Vector3(0.22, 0.12, 0.14))),
			mat(Color(0.2, 0.16, 0.12)), Vector3(0, 0.06, 0)))
	root.add_child(mesh_node(cached("person_head", func(): return sphere(0.13, 6, 4)), mat(skin), Vector3(0, 0.95, 0)))
	root.add_child(mesh_node(cached("person_hair", func(): return sphere(0.14, 6, 3)), mat(hair), Vector3(0, 1.0, -0.02)))
	return root
