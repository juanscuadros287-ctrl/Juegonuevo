class_name CameraRig
extends Node3D
## Cámara cenital/isométrica estilo constructor de ciudades.
## Mover: WASD/flechas o arrastrar con botón derecho. Rotar: Q/E o botón central.
## Zoom: rueda, +/- o gesto de pellizco / dos dedos (trackpad Mac).

const MIN_DIST := 6.0
const MAX_DIST := 330.0

var camera: Camera3D
var terrain: Terrain
var yaw := 35.0
var target_yaw := 35.0
var distance := 70.0
var target_distance := 70.0
var target_pos := Vector3.ZERO
var follow: Node3D = null
var _dragging_pan := false
var _dragging_rot := false


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 50.0
	camera.near = 0.3
	camera.far = 2500.0
	add_child(camera)
	camera.current = true


func setup(t: Terrain, start: Vector3) -> void:
	terrain = t
	target_pos = start
	position = start
	_update_camera()


func focus(pos: Vector3, zoom := -1.0) -> void:
	follow = null
	target_pos = pos
	if zoom > 0.0:
		target_distance = zoom


func _typing() -> bool:
	return get_viewport().gui_get_focus_owner() is LineEdit


func _process(delta: float) -> void:
	if not _typing():
		var move := Vector2.ZERO
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			move.y -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			move.y += 1
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			move.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			move.x += 1
		if move != Vector2.ZERO:
			_pan(move.normalized() * distance * 1.1 * delta)
		if Input.is_key_pressed(KEY_Q):
			target_yaw += 90.0 * delta
		if Input.is_key_pressed(KEY_E):
			target_yaw -= 90.0 * delta
		if Input.is_key_pressed(KEY_EQUAL) or Input.is_key_pressed(KEY_KP_ADD):
			target_distance = maxf(MIN_DIST, target_distance * (1.0 - 1.5 * delta))
		if Input.is_key_pressed(KEY_MINUS) or Input.is_key_pressed(KEY_KP_SUBTRACT):
			target_distance = minf(MAX_DIST, target_distance * (1.0 + 1.5 * delta))
	if is_instance_valid(follow) and follow.is_inside_tree():
		target_pos = follow.global_position
	elif follow != null:
		follow = null
	var lim := GameState.MAP_SIZE * 0.5
	target_pos.x = clampf(target_pos.x, -lim, lim)
	target_pos.z = clampf(target_pos.z, -lim, lim)
	if terrain:
		target_pos.y = maxf(terrain.height_at(target_pos.x, target_pos.z), terrain.water_level)
	var k := 1.0 - exp(-10.0 * delta)
	position = position.lerp(target_pos, k)
	distance = lerpf(distance, target_distance, k)
	yaw = lerpf(yaw, target_yaw, k)
	_update_camera()


func _update_camera() -> void:
	rotation = Vector3(0, deg_to_rad(yaw), 0)
	# De cerca se ve en ángulo bajo (calles y personas); de lejos casi cenital.
	var t := inverse_lerp(MIN_DIST, MAX_DIST, distance)
	var pitch := deg_to_rad(lerpf(28.0, 68.0, sqrt(clampf(t, 0.0, 1.0))))
	camera.position = Vector3(0, sin(pitch) * distance, cos(pitch) * distance)
	if terrain:
		var gp := camera.global_position
		var ground := maxf(terrain.height_at(gp.x, gp.z), terrain.water_level) + 1.5
		if gp.y < ground:
			camera.position.y += ground - gp.y
	camera.look_at(global_position + Vector3(0, 0.8, 0), Vector3.UP)


func _pan(v: Vector2) -> void:
	follow = null
	var b := Basis(Vector3.UP, deg_to_rad(yaw))
	var right := b * Vector3.RIGHT
	var fwd := b * Vector3.BACK
	target_pos += right * v.x + fwd * v.y


func _zoom(factor: float) -> void:
	target_distance = clampf(target_distance * factor, MIN_DIST, MAX_DIST)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed and not mb.shift_pressed:
					_zoom(0.88)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed and not mb.shift_pressed:
					_zoom(1.13)
			MOUSE_BUTTON_RIGHT:
				_dragging_pan = mb.pressed
			MOUSE_BUTTON_MIDDLE:
				_dragging_rot = mb.pressed
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging_pan:
			_pan(-mm.relative * distance * 0.0022)
		elif _dragging_rot:
			target_yaw -= mm.relative.x * 0.3
	elif event is InputEventMagnifyGesture:
		_zoom(1.0 / (event as InputEventMagnifyGesture).factor)
	elif event is InputEventPanGesture:
		var pg := event as InputEventPanGesture
		if Input.is_key_pressed(KEY_SHIFT):
			target_yaw -= pg.delta.x * 3.0
		else:
			_zoom(1.0 + pg.delta.y * 0.05)
