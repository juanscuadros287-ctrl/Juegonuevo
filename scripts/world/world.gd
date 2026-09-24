extends Node3D
## Escena principal de juego: arma el mundo 3D a partir de GameState
## y sincroniza lo visual (ciudadanos, edificios, clima, día/noche).

const MAX_AGENTS := 400
const PICK_RADIUS_PX := 22.0

var terrain: Terrain
var camera_rig: CameraRig
var hud: Hud
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var weather_fx: WeatherFX
var agents := {}            # id -> CitizenAgent
var building_nodes := {}    # id -> Node3D
var agents_root: Node3D
var buildings_root: Node3D
var selection_ring: MeshInstance3D
var selected_id := -1
var _refresh_timer := 0.0


func _ready() -> void:
	if not GameState.running and GameState.citizens.is_empty():
		GameState.new_game({})  # Permite ejecutar esta escena directamente desde el editor.
	var seed_value := int(GameState.settings.get("seed", 1))
	_build_environment()
	terrain = Terrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.generate(str(GameState.settings.get("map_type", "interior")), seed_value)
	terrain.build_mesh()
	terrain.make_water()
	terrain.scatter_nature(seed_value)
	terrain.set_season(GameState.season)

	buildings_root = Node3D.new()
	buildings_root.name = "Buildings"
	add_child(buildings_root)
	_build_settlement()

	agents_root = Node3D.new()
	agents_root.name = "Citizens"
	add_child(agents_root)
	for id in GameState.citizens:
		_spawn_agent(id)

	selection_ring = MeshLib.mesh_node(_ring_mesh(), MeshLib.mat(Color(1.0, 0.85, 0.2)))
	selection_ring.visible = false
	add_child(selection_ring)

	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)
	camera_rig.setup(terrain, Vector3(0, terrain.height_at(0, 0), 0))

	weather_fx = WeatherFX.new()
	camera_rig.add_child(weather_fx)

	hud = Hud.new()
	hud.name = "HUD"
	add_child(hud)

	EventBus.citizen_born.connect(_spawn_agent)
	EventBus.citizen_removed.connect(_on_citizen_removed)
	EventBus.citizens_moved.connect(_sync_homes)
	EventBus.season_changed.connect(terrain.set_season)
	EventBus.weather_changed.connect(_apply_weather)
	EventBus.citizen_selected.connect(_on_citizen_selected)
	EventBus.jump_finished.connect(func(_r): _full_resync())
	hud.follow_requested.connect(_follow_selected)
	_apply_weather()
	_update_daylight()


func _build_environment() -> void:
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.55, 0.85)
	sky_mat.sky_horizon_color = Color(0.72, 0.82, 0.9)
	sky_mat.ground_horizon_color = Color(0.6, 0.65, 0.6)
	sky_mat.ground_bottom_color = Color(0.3, 0.32, 0.3)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.85
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.78, 0.86)
	env.fog_density = 0.0015
	env.fog_sky_affect = 0.3
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 250.0
	add_child(sun)


func _build_settlement() -> void:
	var y0 := terrain.height_at(0, 0)
	var square := MeshLib.mesh_node(MeshLib.cylinder(8.0, 8.0, 0.12, 12), MeshLib.mat(Color(0.6, 0.52, 0.38)), Vector3(0, y0 + 0.02, 0))
	buildings_root.add_child(square)
	var well := MeshLib.make_well()
	well.position = Vector3(0, y0, 0)
	buildings_root.add_child(well)
	var path_mat := MeshLib.mat(Color(0.58, 0.5, 0.36))
	for b in GameState.buildings:
		var id := int(b["id"])
		var pos := Vector3(float(b["x"]), 0, float(b["z"]))
		pos.y = terrain.height_at(pos.x, pos.z)
		var node := MeshLib.make_hut(id)
		node.position = pos
		node.rotation.y = float(b.get("rot", 0.0))
		buildings_root.add_child(node)
		building_nodes[id] = node
		# Camino de tierra desde la plaza hasta la vivienda.
		var flat := Vector2(pos.x, pos.z)
		var length := flat.length()
		if length > 8.0:
			var mid := flat * (0.5 + 4.0 / length)
			var path := MeshLib.mesh_node(MeshLib.box(Vector3(1.3, 0.06, length - 8.0)), path_mat,
					Vector3(mid.x, terrain.height_at(mid.x, mid.y) + 0.02, mid.y))
			path.rotation.y = atan2(flat.x, flat.y)
			buildings_root.add_child(path)


func _home_position(c: Citizen) -> Vector3:
	var b: Dictionary = GameState.get_building(c.home_id)
	if b.is_empty():
		return Vector3(0, terrain.height_at(0, 0), 0)
	var x := float(b["x"])
	var z := float(b["z"])
	var rot := float(b.get("rot", 0.0))
	# Puerta: frente de la choza (orientada hacia la plaza).
	var door := Vector3(x, 0, z) + Vector3(sin(rot), 0, cos(rot)) * 1.2
	door.y = terrain.height_at(door.x, door.z)
	return door


func _spawn_agent(id: int) -> void:
	if agents.has(id) or agents.size() >= MAX_AGENTS or not GameState.citizens.has(id):
		return
	var c: Citizen = GameState.citizens[id]
	var agent := CitizenAgent.new()
	agents_root.add_child(agent)
	agent.setup(c, terrain, _home_position(c))
	agents[id] = agent


func _on_citizen_removed(id: int, _reason: String) -> void:
	if agents.has(id):
		agents[id].queue_free()
		agents.erase(id)
	if id == selected_id:
		EventBus.citizen_selected.emit(-1)


func _sync_homes() -> void:
	for id in agents:
		if GameState.citizens.has(id):
			agents[id].set_home(_home_position(GameState.citizens[id]))


func _full_resync() -> void:
	for id in agents.keys():
		if not GameState.citizens.has(id):
			agents[id].queue_free()
			agents.erase(id)
	for id in GameState.citizens:
		_spawn_agent(id)
	_sync_homes()
	terrain.set_season(GameState.season)


func _apply_weather() -> void:
	var w := WeatherSim.weather_data(GameState)
	weather_fx.set_fx(str(w.get("fx", "")))
	_update_daylight()


func _process(delta: float) -> void:
	_update_daylight()
	if selected_id >= 0 and agents.has(selected_id):
		var a: CitizenAgent = agents[selected_id]
		selection_ring.visible = a.visible
		selection_ring.position = a.position + Vector3(0, 0.05, 0)
	else:
		selection_ring.visible = false
	_refresh_timer += delta
	if _refresh_timer > 2.0:
		_refresh_timer = 0.0
		for id in agents:
			if GameState.citizens.has(id):
				agents[id].refresh(GameState.citizens[id])


func _update_daylight() -> void:
	if sun == null:
		return
	# A velocidades altas se fija la luz de mediodía para evitar parpadeo día/noche.
	var h := 12.0 if (TimeManager.speed >= 2 or TimeManager.jumping) else TimeManager.hour_float()
	var t := (h - 6.0) / 12.0
	var elev := sin(t * PI)
	var w := WeatherSim.weather_data(GameState)
	var dim := float(w.get("sky_dim", 0.0))
	var day := clampf(elev * 1.6, 0.0, 1.0)
	sun.rotation = Vector3(-deg_to_rad(maxf(elev, 0.08) * 70.0), deg_to_rad(-30.0 + t * 120.0), 0)
	sun.light_energy = lerpf(0.08, 0.95, day) * (1.0 - dim * 0.6)
	sun.light_color = Color(1.0, 0.82, 0.62).lerp(Color(1.0, 0.97, 0.92), clampf(elev * 2.0, 0.0, 1.0))
	var gray := Color(0.55, 0.58, 0.62)
	var night_top := Color(0.03, 0.05, 0.12)
	var top := night_top.lerp(Color(0.32, 0.55, 0.85).lerp(gray, dim), day)
	var horizon := Color(0.08, 0.1, 0.18).lerp(Color(0.72, 0.82, 0.9).lerp(gray, dim), day)
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = horizon
	env.ambient_light_energy = lerpf(0.2, 0.45, day)
	env.fog_light_color = horizon


func _ring_mesh() -> Mesh:
	var t := TorusMesh.new()
	t.inner_radius = 0.45
	t.outer_radius = 0.6
	t.rings = 12
	t.ring_segments = 4
	return t


# --- Selección con el ratón --------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_pick(event.position)


func _pick(screen_pos: Vector2) -> void:
	var cam := camera_rig.camera
	var best_id := -1
	var best_d := PICK_RADIUS_PX
	for id in agents:
		var a: CitizenAgent = agents[id]
		if not a.visible:
			continue
		var wp := a.global_position + Vector3(0, 0.6, 0)
		if cam.is_position_behind(wp):
			continue
		var d := cam.unproject_position(wp).distance_to(screen_pos)
		if d < best_d:
			best_d = d
			best_id = id
	if best_id >= 0:
		EventBus.citizen_selected.emit(best_id)
		return
	var best_b := -1
	var best_bd := 45.0
	for id in building_nodes:
		var wp: Vector3 = building_nodes[id].global_position + Vector3(0, 1.5, 0)
		if cam.is_position_behind(wp):
			continue
		var d := cam.unproject_position(wp).distance_to(screen_pos)
		if d < best_bd:
			best_bd = d
			best_b = id
	if best_b >= 0:
		EventBus.building_selected.emit(best_b)
	else:
		EventBus.citizen_selected.emit(-1)


func _on_citizen_selected(id: int) -> void:
	selected_id = id


func _follow_selected() -> void:
	if agents.has(selected_id):
		camera_rig.follow = agents[selected_id]
		camera_rig.target_distance = 14.0


func focus_citizen(id: int) -> void:
	if agents.has(id):
		camera_rig.focus(agents[id].global_position, 18.0)
