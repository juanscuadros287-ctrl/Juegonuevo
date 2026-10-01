class_name VehicleThumb
extends SubViewportContainer
## Miniatura 3D de un modelo de vehículo o vagón (ficha de compra, docs/VEHICULOS.md): un SubViewport con
## mundo propio, luz, la malla compartida de VehicleModels y una cámara que la encuadra según su tamaño.
## Gira despacio. Barato: un solo visor a la vez, se actualiza solo mientras está visible.

var model_id := ""
var spin := true
var _vp: SubViewport
var _pivot: Node3D
var _cam: Camera3D


static func make(id: String, size := Vector2i(240, 150), rotate := true) -> VehicleThumb:
	var t := VehicleThumb.new()
	t.model_id = id
	t.spin = rotate
	t.custom_minimum_size = Vector2(size)
	t.stretch = true
	t._build(size)
	return t


func _build(size: Vector2i) -> void:
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.size = size
	_vp.msaa_3d = Viewport.MSAA_2X
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.85)
	e.ambient_light_energy = 0.7
	env.environment = e
	_vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.2
	_vp.add_child(sun)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	_cam = Camera3D.new()
	_cam.fov = 32.0
	_vp.add_child(_cam)
	set_model(model_id)


func set_model(id: String) -> void:
	model_id = id
	if _pivot == null:
		return
	for c in _pivot.get_children():
		c.queue_free()
	if id == "":
		return
	var n := VehicleModels.node(id)
	for c in n.get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).visibility_range_end = 0.0   # en la miniatura siempre el detalle
			(c as GeometryInstance3D).visibility_range_begin = 0.0
	n.get_node("Proxy").visible = false
	_pivot.add_child(n)
	var mesh: Mesh = VehicleModels.meshes(id)[0]
	var ab := mesh.get_aabb() if mesh else AABB(Vector3(-1, 0, -1), Vector3(2, 2, 2))
	n.position = -ab.get_center()
	var r := maxf(ab.size.length() * 0.5, 0.5)
	var dist := r / sin(deg_to_rad(_cam.fov * 0.5)) * 0.95
	var eye := Vector3(0, r * 0.55, dist)
	_cam.transform = Transform3D(Basis.looking_at(-eye, Vector3.UP), eye)
	_pivot.rotation.y = deg_to_rad(-35.0)


func _process(delta: float) -> void:
	if spin and _pivot and is_visible_in_tree():
		_pivot.rotation.y += delta * 0.6
