class_name CitizenAgent
extends Node3D
## Representación visual de un ciudadano. Sigue una rutina según la hora:
## noche en casa, día trabajando (campo/bosque) o jugando (niños), tarde en la plaza.

const SPEED_MULT := [0.0, 0.6, 1.0, 4.0, 10.0]
const CLOTH := [Color(0.55, 0.2, 0.18), Color(0.25, 0.35, 0.55), Color(0.35, 0.45, 0.25),
		Color(0.6, 0.5, 0.3), Color(0.45, 0.3, 0.45), Color(0.7, 0.65, 0.55), Color(0.3, 0.3, 0.3)]
const SKIN := [Color(0.95, 0.8, 0.65), Color(0.85, 0.65, 0.48), Color(0.68, 0.48, 0.34), Color(0.5, 0.35, 0.25)]
const HAIR := [Color(0.1, 0.08, 0.06), Color(0.35, 0.22, 0.1), Color(0.6, 0.45, 0.25), Color(0.2, 0.15, 0.1)]

var citizen_id := -1
var terrain: Terrain
var home_pos := Vector3.ZERO
var target := Vector3.ZERO
var at_home := true
var walk_speed := 2.2
var _rng := RandomNumberGenerator.new()
var _plan_hour := -1
var _work_spot := Vector3.ZERO
var _work_day := -1
var _wake_hour := 6
var _sleep_hour := 21
var _model: Node3D
var _bob := 0.0
var _stage := ""


func setup(c: Citizen, t: Terrain, home: Vector3) -> void:
	citizen_id = c.id
	terrain = t
	_rng.seed = c.visual_seed
	home_pos = home
	_wake_hour = 5 + _rng.randi_range(0, 2)
	_sleep_hour = 20 + _rng.randi_range(0, 2)
	walk_speed = _rng.randf_range(1.8, 2.6)
	_model = make_model(c)
	add_child(_model)
	position = home + Vector3(_rng.randf_range(-1.5, 1.5), 0, _rng.randf_range(-1.5, 1.5))
	target = position
	refresh(c)


## Modelo 3D de un ciudadano (mismos colores en el mundo y en el interior de las casas).
static func make_model(c: Citizen) -> Node3D:
	var r := RandomNumberGenerator.new()
	r.seed = c.visual_seed
	r.randi_range(0, 2)
	r.randi_range(0, 2)
	r.randf_range(1.8, 2.6)
	var hair: Color = HAIR[r.randi() % HAIR.size()]
	var cloth: Color = CLOTH[r.randi() % CLOTH.size()]
	var skin: Color = SKIN[r.randi() % SKIN.size()]
	if GameState.is_player(c.id):
		cloth = Color(0.85, 0.65, 0.2)
	var m := MeshLib.make_person(cloth, skin, hair, c.gender == "F")
	var age := c.age_years(GameState.today())
	if age < 16:
		m.scale = Vector3.ONE * lerpf(0.45, 0.95, age / 16.0)
	return m


var _marker: MeshInstance3D


func set_player_marker(on: bool) -> void:
	if on and _marker == null:
		var t := TorusMesh.new()
		t.inner_radius = 0.35
		t.outer_radius = 0.45
		t.rings = 10
		t.ring_segments = 4
		_marker = MeshLib.mesh_node(t, MeshLib.mat(Color(1.0, 0.8, 0.15)), Vector3(0, 1.45, 0))
		add_child(_marker)
	elif not on and _marker != null:
		_marker.queue_free()
		_marker = null


## Actualiza tamaño según edad (niños más pequeños) y vivienda.
func refresh(c: Citizen) -> void:
	var age := c.age_years(GameState.today())
	var s := 1.0
	if age < 16:
		s = lerpf(0.45, 0.95, age / 16.0)
	_stage = "child" if age < 12 else ("elder" if age >= 60 else "adult")
	_model.scale = Vector3.ONE * s
	if _stage == "elder":
		walk_speed = minf(walk_speed, 1.4)


func set_home(pos: Vector3) -> void:
	home_pos = pos


func _process(delta: float) -> void:
	var s := TimeManager.speed
	if s == 0 or TimeManager.jumping or not GameState.running:
		return
	var h := TimeManager.hour()
	if h != _plan_hour:
		_plan_hour = h
		_plan(h)
	var to := target - position
	to.y = 0.0
	var dist := to.length()
	var step: float = walk_speed * SPEED_MULT[s] * delta
	if dist > 0.05:
		var dir := to / dist
		position += dir * minf(step, dist)
		rotation.y = atan2(dir.x, dir.z)
		_bob += delta * 10.0 * SPEED_MULT[s]
		_model.position.y = absf(sin(_bob)) * 0.06
	else:
		_model.position.y = 0.0
	position.y = terrain.height_at(position.x, position.z) if terrain else 0.0
	# Dentro de casa: invisible.
	var going_home := target.distance_to(home_pos) < 0.5
	visible = not (going_home and dist < 0.6)


func _plan(h: int) -> void:
	var c: Citizen = GameState.citizens.get(citizen_id)
	if c == null:
		return
	if h < _wake_hour or h >= _sleep_hour or c.sick:
		target = home_pos
		return
	var day := GameState.today()
	if h >= 17:
		# Tarde: plaza del pueblo.
		target = _random_point(Vector3.ZERO, 2.5, 7.5)
		return
	if c.school_id >= 0 and h < 14:
		var sb: Dictionary = GameState.get_building(c.school_id)
		if not sb.is_empty():
			target = _random_point(Vector3(float(sb["x"]), 0, float(sb["z"])), 3.0, 5.0)
			return
	match _stage:
		"child":
			if _rng.randf() < 0.6:
				target = _random_point(Vector3.ZERO, 2.0, 12.0)
			else:
				target = _random_point(home_pos, 1.0, 4.0)
		"elder":
			target = _random_point(home_pos, 1.5, 3.5)
		_:
			if GameState.is_player(c.id):
				var offices := GameState.player_buildings("oficina")
				var spots := offices if not offices.is_empty() else GameState.player_buildings("negocio")
				if not spots.is_empty():
					var ob: Dictionary = spots[h % spots.size()]
					target = _random_point(Vector3(float(ob["x"]), 0, float(ob["z"])), 2.5, 4.0)
					return
			if c.job_id >= 0:
				var b: Dictionary = GameState.get_building(c.job_id)
				if not b.is_empty():
					target = _random_point(Vector3(float(b["x"]), 0, float(b["z"])), 2.5, 4.0)
					return
			if _work_day != day:
				_work_day = day
				_work_spot = _pick_work_spot()
			target = _random_point(_work_spot, 0.0, 3.0)


func _pick_work_spot() -> Vector3:
	for i in range(10):
		var p := _random_point(Vector3.ZERO, 28.0, 60.0)
		if terrain == null or (terrain.is_land(p.x, p.z, 0.6) and terrain.height_at(p.x, p.z) < 20.0):
			return p
	return _random_point(home_pos, 2.0, 6.0)


func _random_point(center: Vector3, rmin: float, rmax: float) -> Vector3:
	var a := _rng.randf() * TAU
	var r := _rng.randf_range(rmin, rmax)
	return center + Vector3(cos(a) * r, 0.0, sin(a) * r)
