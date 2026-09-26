class_name TourismVisuals
extends Node3D
## Visuales 3D del turismo (Fase 8): turistas low-poly (ropa de colores, sombrero y mochila)
## que entran al pueblo por el lado de cada conexión, recorren tus atracciones, la plaza y el
## hospedaje, y se van. La cantidad sigue a los turistas presentes (con un tope).
## world.gd llama setup(world) al iniciar.

const SPEED_MULT := [0.0, 0.6, 1.0, 4.0, 10.0]
const CLOTH := [Color(0.95, 0.45, 0.2), Color(0.2, 0.7, 0.85), Color(0.9, 0.85, 0.3), Color(0.85, 0.35, 0.6),
		Color(0.4, 0.8, 0.4), Color(0.95, 0.95, 0.95)]
const SKIN := [Color(0.95, 0.8, 0.65), Color(0.85, 0.65, 0.48), Color(0.68, 0.48, 0.34)]
const ENTRY_RADIUS := 38.0

var world: Node3D
var terrain: Terrain
var _rng := RandomNumberGenerator.new()
var _tourists: Array = []     # Array de Dictionary {node, path: Array[Vector3], wait}
var _timer := 0.0


func setup(p_world: Node3D) -> void:
	world = p_world
	name = "TourismVisuals"
	terrain = world.get("terrain")
	_rng.seed = 8088


func _process(delta: float) -> void:
	if world == null or not GameState.running:
		return
	var s := TimeManager.speed
	if TimeManager.jumping:
		_clear()
		return
	_timer += delta
	if _timer >= 0.5:
		_timer = 0.0
		_sync_count()
	if s == 0:
		return
	var step_mult: float = SPEED_MULT[clampi(s, 0, SPEED_MULT.size() - 1)]
	for t in _tourists.duplicate():
		_move(t, delta, step_mult)


## Cuántos turistas mostrar: los presentes hoy (tope en tourism.json), solo de día.
func _desired() -> int:
	if TradeSim.connected_towns(GameState).is_empty():
		return 0
	var h := TimeManager.hour()
	if h < 7 or h >= 21:
		return 0
	var present := int(GameState.tourism.get("today", {}).get("present", 0))
	return mini(present, int(TourismSim.cfg().get("max_visuals", 24)))


func _sync_count() -> void:
	var want := _desired()
	var alive := 0
	for t in _tourists:
		if not bool(t.get("leaving", false)):
			alive += 1
	if alive < want:
		for i in range(mini(3, want - alive)):
			_spawn()
	elif alive > want:
		for t in _tourists:
			if alive <= want:
				break
			if not bool(t.get("leaving", false)):
				_send_home(t)
				alive -= 1


func _entry_point() -> Vector3:
	var conns: Array = TradeSim.connected_towns(GameState)
	var angle := _rng.randf() * TAU
	if not conns.is_empty():
		var c = conns[_rng.randi() % conns.size()]
		var tid := str(c.get("town_id", "")) if c is Dictionary else str(c)
		angle = float(absi(tid.hash()) % 3600) / 3600.0 * TAU + _rng.randf_range(-0.12, 0.12)
	return Vector3(cos(angle) * ENTRY_RADIUS, 0.0, sin(angle) * ENTRY_RADIUS)


func _spots() -> Array:
	var out := []
	for b in GameState.buildings:
		if GameState.owned_by_player(b) and str(b.get("status", "")) == "activo" and TourismSim.is_tourism_business(b) and not TourismSim.is_media(b):
			out.append(Vector3(float(b["x"]), 0.0, float(b["z"])))
	return out


func _spawn() -> void:
	var entry := _entry_point()
	var node := _make_model()
	node.position = entry
	add_child(node)
	var path: Array = []
	var spots := _spots()
	spots.shuffle()
	for i in range(mini(2, spots.size())):
		path.append(_around(spots[i], 2.5, 4.5))
	path.append(_around(Vector3.ZERO, 2.5, 7.0))
	path.append(entry)
	_tourists.append({"node": node, "path": path, "wait": 0.0, "speed": _rng.randf_range(1.6, 2.3), "leaving": false, "bob": 0.0})


func _send_home(t: Dictionary) -> void:
	var path: Array = t["path"]
	var exit_p: Vector3 = path[path.size() - 1] if not path.is_empty() else _entry_point()
	t["path"] = [exit_p]
	t["leaving"] = true


func _around(center: Vector3, rmin: float, rmax: float) -> Vector3:
	var a := _rng.randf() * TAU
	var r := _rng.randf_range(rmin, rmax)
	return center + Vector3(cos(a) * r, 0.0, sin(a) * r)


func _move(t: Dictionary, delta: float, mult: float) -> void:
	var node: Node3D = t["node"]
	var path: Array = t["path"]
	if path.is_empty():
		_remove(t)
		return
	if float(t["wait"]) > 0.0:
		t["wait"] = float(t["wait"]) - delta * mult
		return
	var target: Vector3 = path[0]
	var to := target - node.position
	to.y = 0.0
	var dist := to.length()
	var step := float(t["speed"]) * mult * delta
	if dist > 0.1:
		var dir := to / dist
		node.position += dir * minf(step, dist)
		node.rotation.y = atan2(dir.x, dir.z)
		t["bob"] = float(t["bob"]) + delta * 10.0 * mult
		var model: Node3D = node.get_child(0)
		model.position.y = absf(sin(float(t["bob"]))) * 0.035
		MeshLib.animate_person(model.get_child(0), float(t["bob"]) * 0.6, 1.0)
	else:
		path.pop_front()
		if path.is_empty():
			_remove(t)
			return
		t["wait"] = 0.0 if bool(t["leaving"]) else _rng.randf_range(4.0, 12.0)
	node.position.y = terrain.height_at(node.position.x, node.position.z) if terrain != null else 0.0


func _remove(t: Dictionary) -> void:
	var node: Node3D = t["node"]
	if is_instance_valid(node):
		node.queue_free()
	_tourists.erase(t)


func _clear() -> void:
	for t in _tourists:
		var node: Node3D = t["node"]
		if is_instance_valid(node):
			node.queue_free()
	_tourists.clear()


## Turista: persona low-poly con ropa llamativa, sombrero y mochila.
func _make_model() -> Node3D:
	var root := Node3D.new()
	var cloth: Color = CLOTH[_rng.randi() % CLOTH.size()]
	var skin: Color = SKIN[_rng.randi() % SKIN.size()]
	var person := MeshLib.make_person(cloth, skin, Color(0.2, 0.15, 0.1), _rng.randf() < 0.5)
	root.add_child(person)
	var hat_col := Color(0.85, 0.78, 0.55) if _rng.randf() < 0.6 else Color(0.25, 0.25, 0.3)
	person.add_child(MeshLib.mesh_node(MeshLib.cached("tourist_brim", func(): return MeshLib.cylinder(0.24, 0.24, 0.03, 8)), MeshLib.mat(hat_col), Vector3(0, 1.27, 0)))
	person.add_child(MeshLib.mesh_node(MeshLib.cached("tourist_hat", func(): return MeshLib.cylinder(0.12, 0.14, 0.14, 8)), MeshLib.mat(hat_col), Vector3(0, 1.34, 0)))
	person.add_child(MeshLib.mesh_node(MeshLib.cached("tourist_pack", func(): return MeshLib.box(Vector3(0.24, 0.3, 0.12))), MeshLib.mat(Color(0.35, 0.3, 0.2)), Vector3(0, 0.8, -0.16)))
	return root
