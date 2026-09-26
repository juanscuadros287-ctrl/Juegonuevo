class_name CameraRig
extends Node3D
## Cámara cenital/isométrica estilo constructor de ciudades.
## Mover: WASD/flechas o arrastrar con botón derecho. Rotar: Q/E o botón central.
## Zoom: rueda, +/- o gesto de pellizco / dos dedos (trackpad Mac).
## Fase 9A: se aleja hasta ver el país completo (M = ver país / volver, H = volver al pueblo);
## a gran altura el paneo es más rápido, la niebla se aclara y el plano lejano se amplía.

const MIN_DIST := 6.0
const TOWN_MAX_DIST := 330.0      # zoom máximo de antes: por debajo, la cámara se comporta igual
const MAX_DIST := 330.0           # (compatibilidad) usa max_dist para el límite real
const TOWN_VIEW_DIST := 70.0
const BASE_FOG := 0.0003

var camera: Camera3D
var terrain: Terrain
var env: Environment
var yaw := 35.0
var target_yaw := 35.0
var distance := 70.0
var target_distance := 70.0
var target_pos := Vector3.ZERO
var follow: Node3D = null
var max_dist := 330.0
var bounds := Rect2(-200, -200, 400, 400)
var frame := Rect2(-200, -200, 400, 400)   # rectángulo que ocupa el país (vista de país)
var _dragging_pan := false
var _dragging_rot := false


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 50.0
	camera.near = 0.3
	camera.far = 2500.0
	add_child(camera)
	camera.current = true


func setup(t: Terrain, start: Vector3, p_env: Environment = null) -> void:
	terrain = t
	env = p_env
	target_pos = start
	position = start
	if t != null and t.gen != null:
		bounds = t.country_rect_m()
		# Fase 9B: encuadre del país real (su frontera, no el cuadrado de la rejilla) con margen.
		frame = t.country_frame_m()
		max_dist = maxf(TOWN_MAX_DIST, maxf(frame.size.y * 1.2, frame.size.x * 0.7))
	_update_camera()


func focus(pos: Vector3, zoom := -1.0) -> void:
	follow = null
	target_pos = pos
	if zoom > 0.0:
		target_distance = clampf(zoom, MIN_DIST, max_dist)


## Vista completa del país (zoom máximo sobre el centro).
func view_country() -> void:
	focus(Vector3(frame.get_center().x, 0, frame.get_center().y), max_dist)


## Vuelve a la plaza del pueblo con el zoom de siempre.
func view_town() -> void:
	focus(Vector3.ZERO, TOWN_VIEW_DIST)


func is_country_view() -> bool:
	return target_distance > 1500.0


func _typing() -> bool:
	return get_viewport().gui_get_focus_owner() is LineEdit


## Velocidad de paneo: proporcional a la altura y más rápida aún sobre el país.
func _pan_speed() -> float:
	return distance * 1.1 * (1.0 + smoothstep(400.0, 4000.0, distance) * 0.8)


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
			_pan(move.normalized() * _pan_speed() * delta)
		if Input.is_key_pressed(KEY_Q):
			target_yaw += 90.0 * delta
		if Input.is_key_pressed(KEY_E):
			target_yaw -= 90.0 * delta
		if Input.is_key_pressed(KEY_EQUAL) or Input.is_key_pressed(KEY_KP_ADD):
			target_distance = maxf(MIN_DIST, target_distance * (1.0 - 1.5 * delta))
		if Input.is_key_pressed(KEY_MINUS) or Input.is_key_pressed(KEY_KP_SUBTRACT):
			target_distance = minf(max_dist, target_distance * (1.0 + 1.5 * delta))
	if is_instance_valid(follow) and follow.is_inside_tree():
		target_pos = follow.global_position
	elif follow != null:
		follow = null
	target_pos.x = clampf(target_pos.x, bounds.position.x, bounds.end.x)
	target_pos.z = clampf(target_pos.z, bounds.position.y, bounds.end.y)
	if terrain:
		target_pos.y = maxf(terrain.height_at(target_pos.x, target_pos.z), terrain.water_level)
	var k := 1.0 - exp(-10.0 * delta)
	position = position.lerp(target_pos, k)
	# El zoom interpola en escala logarítmica: de 70 m a 12 km se ve suave.
	distance = exp(lerpf(log(distance), log(target_distance), k))
	yaw = lerpf(yaw, target_yaw, k)
	_update_camera()


## Inclinación: igual que antes hasta 330 m; más cenital al alejarse sobre el país.
func _pitch_deg(d: float) -> float:
	var t := inverse_lerp(MIN_DIST, TOWN_MAX_DIST, minf(d, TOWN_MAX_DIST))
	var p := lerpf(28.0, 68.0, sqrt(clampf(t, 0.0, 1.0)))
	if d > TOWN_MAX_DIST:
		p = lerpf(68.0, 86.0, smoothstep(TOWN_MAX_DIST, max_dist, d))
	return p


func _update_camera() -> void:
	rotation = Vector3(0, deg_to_rad(yaw), 0)
	# De cerca se ve en ángulo bajo (calles y personas); de lejos casi cenital.
	var pitch := deg_to_rad(_pitch_deg(distance))
	camera.position = Vector3(0, sin(pitch) * distance, cos(pitch) * distance)
	if terrain:
		var gp := camera.global_position
		var ground := maxf(terrain.height_at(gp.x, gp.z), terrain.water_level) + 1.5
		if gp.y < ground:
			camera.position.y += ground - gp.y
	camera.look_at(global_position + Vector3(0, 0.8, 0), Vector3.UP)
	# Plano lejano y cercano según la altura (evita parpadeo del agua a 10 km).
	camera.far = maxf(2500.0, distance * 4.0)
	camera.near = clampf(distance * 0.004, 0.3, 40.0)
	if env:
		# Igual que antes en el pueblo; sobre el país solo una bruma leve en el horizonte.
		env.fog_density = BASE_FOG * pow(minf(1.0, TOWN_MAX_DIST / maxf(distance, 1.0)), 1.6)


func _pan(v: Vector2) -> void:
	follow = null
	var b := Basis(Vector3.UP, deg_to_rad(yaw))
	var right := b * Vector3.RIGHT
	var fwd := b * Vector3.BACK
	target_pos += right * v.x + fwd * v.y


func _zoom(factor: float) -> void:
	# Sobre el país cada paso de rueda acerca/aleja más.
	if target_distance > TOWN_MAX_DIST:
		factor = pow(factor, 1.6)
	target_distance = clampf(target_distance * factor, MIN_DIST, max_dist)


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
	elif event is InputEventKey and event.pressed and not event.echo and not _typing():
		var key := (event as InputEventKey).keycode
		if key == KEY_M:
			if is_country_view():
				view_town()
			else:
				view_country()
			get_viewport().set_input_as_handled()
		elif key == KEY_H:
			view_town()
			get_viewport().set_input_as_handled()
