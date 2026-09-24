class_name InteriorView
extends Node3D
## Vista del interior de una vivienda (estilo Los Sims: paredes traseras y frente recortado).
## Los objetos salen automáticamente de data/interiors.json según nivel, calidad y época.

const ORIGIN := Vector3(0, -600, 0)

var camera: Camera3D
var building_id := -1
var active := false
var _content: Node3D
var _figures := {}          # id -> Node3D
var _yaw := 45.0
var _dist := 11.0
var _center := Vector3.ZERO


func _ready() -> void:
	position = ORIGIN
	camera = Camera3D.new()
	camera.fov = 45.0
	add_child(camera)
	visible = false


func open(bid: int) -> void:
	building_id = bid
	active = true
	visible = true
	_build()
	camera.current = true


func close() -> void:
	active = false
	visible = false
	building_id = -1
	if _content:
		_content.queue_free()
		_content = null


func refresh() -> void:
	if active:
		_build()


func _build() -> void:
	if _content:
		_content.queue_free()
	_figures = {}
	_content = Node3D.new()
	add_child(_content)
	var b: Dictionary = GameState.get_building(building_id)
	if b.is_empty():
		return
	var room := Housing.room_def(b)
	var w := float(room["size"][0])
	var d := float(room["size"][1])
	var wh := float(room.get("wall_h", 2.8))
	_dist = maxf(w, d) * 1.2
	var wall := MeshLib.arr_color(room.get("wall"), Color(0.8, 0.7, 0.5)) * float(Housing.tier_def(b).get("tint", 1.0))
	wall.a = 1.0
	var floor_c := MeshLib.arr_color(GameData.interiors.get("floors", {}).get(str(b.get("tier", "normal"))), Color(0.5, 0.4, 0.3))
	_content.add_child(MeshLib.mesh_node(MeshLib.box(Vector3(w + 0.3, 0.1, d + 0.3)), MeshLib.mat(floor_c), Vector3(0, -0.05, 0)))
	# Paredes traseras completas y frente recortado (para ver dentro).
	_content.add_child(MeshLib.mesh_node(MeshLib.box(Vector3(w + 0.3, wh, 0.15)), MeshLib.mat(wall), Vector3(0, wh * 0.5, -d * 0.5 - 0.075)))
	_content.add_child(MeshLib.mesh_node(MeshLib.box(Vector3(0.15, wh, d + 0.3)), MeshLib.mat(wall), Vector3(-w * 0.5 - 0.075, wh * 0.5, 0)))
	_content.add_child(MeshLib.mesh_node(MeshLib.box(Vector3(w + 0.3, 0.45, 0.15)), MeshLib.mat(wall), Vector3(0, 0.22, d * 0.5 + 0.075)))
	_content.add_child(MeshLib.mesh_node(MeshLib.box(Vector3(0.15, 0.45, d + 0.3)), MeshLib.mat(wall), Vector3(w * 0.5 + 0.075, 0.22, 0)))
	_content.add_child(MeshLib.mesh_node(MeshLib.box(Vector3(1.4, 1.0, 0.05)), MeshLib.mat(Color(0.55, 0.75, 0.9), 0.2), Vector3(w * 0.2, wh * 0.6, -d * 0.5)))
	# Objetos.
	var beds := []
	var light_energy := 0.6
	for it in Housing.interior_items(GameState, b):
		var item: Dictionary = it["item"]
		var node := MeshLib.build_model(item.get("parts", []))
		var p: Vector2 = it["pos"]
		node.position = Vector3(p.x * w, 0.84 if item.get("on_table", false) else 0.0, p.y * d)
		node.rotation_degrees.y = float(it["rot"])
		_content.add_child(node)
		if it["slot"] == "cama":
			beds.append(node.position)
		if item.has("light"):
			light_energy = float(item["light"])
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, wh - 0.3, 0)
	lamp.omni_range = maxf(w, d) * 1.2
	lamp.light_energy = light_energy
	lamp.light_color = Color(1.0, 0.85, 0.65)
	_content.add_child(lamp)
	# Residentes: de noche en la cama, de día en la casa.
	var h := TimeManager.hour()
	var night := h < 6 or h >= 21
	var i := 0
	for c in GameState.residents_of(building_id):
		var fig := Node3D.new()
		var model := CitizenAgent.make_model(c)
		fig.add_child(model)
		var r := RandomNumberGenerator.new()
		r.seed = c.visual_seed + TimeManager.day_index()
		if night and i < beds.size() * 2:
			var bp: Vector3 = beds[i % beds.size()]
			fig.position = bp + Vector3(0.25 if i >= beds.size() else -0.1, 0.6, 0.2)
			model.rotation_degrees.x = -90.0
		else:
			fig.position = Vector3(r.randf_range(-0.3, 0.3) * w, 0, r.randf_range(-0.05, 0.4) * d)
			fig.rotation.y = r.randf() * TAU
		var tag := Label3D.new()
		tag.text = c.first_name + (" (tú)" if GameState.is_player(c.id) else "")
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.pixel_size = 0.006
		tag.font_size = 40
		tag.outline_size = 8
		tag.position = Vector3(0, 1.45, 0)
		tag.modulate = Color(1, 0.85, 0.3) if GameState.is_player(c.id) else Color.WHITE
		fig.add_child(tag)
		_content.add_child(fig)
		_figures[c.id] = fig
		i += 1
	_update_camera()


func _process(delta: float) -> void:
	if not active:
		return
	if Input.is_key_pressed(KEY_Q):
		_yaw = clampf(_yaw + 60.0 * delta, 5.0, 85.0)
	if Input.is_key_pressed(KEY_E):
		_yaw = clampf(_yaw - 60.0 * delta, 5.0, 85.0)
	_update_camera()


func _update_camera() -> void:
	var y := deg_to_rad(_yaw)
	camera.position = _center + Vector3(sin(y) * _dist, _dist * 0.85, cos(y) * _dist)
	camera.look_at(global_position + _center + Vector3(0, 0.8, 0), Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_dist = maxf(4.0, _dist * 0.9)
			MOUSE_BUTTON_WHEEL_DOWN:
				_dist = minf(30.0, _dist * 1.1)
			MOUSE_BUTTON_LEFT:
				_pick(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMagnifyGesture:
		_dist = clampf(_dist / event.factor, 4.0, 30.0)
		get_viewport().set_input_as_handled()


func _pick(screen: Vector2) -> void:
	var best := -1
	var best_d := 40.0
	for id in _figures:
		var wp: Vector3 = _figures[id].global_position + Vector3(0, 0.7, 0)
		if camera.is_position_behind(wp):
			continue
		var dd := camera.unproject_position(wp).distance_to(screen)
		if dd < best_d:
			best_d = dd
			best = id
	if best >= 0:
		EventBus.citizen_selected.emit(best)
