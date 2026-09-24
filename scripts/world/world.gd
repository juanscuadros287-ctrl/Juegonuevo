extends Node3D
## Escena principal: arma el mundo 3D desde GameState y sincroniza lo visual
## (ciudadanos, edificios, obras, clima, día/noche), el modo construcción y la vista interior.

const MAX_AGENTS := 400
const PICK_RADIUS_PX := 22.0

var terrain: Terrain
var camera_rig: CameraRig
var hud: Hud
var interior: InteriorView
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

# Modo construcción / expansión
var place_type := ""
var place_tier := "normal"
var place_rot := 0.0
var place_pos := Vector3.ZERO
var place_ok := false
var place_reason := ""
var move_id := -1
var place_tender: Dictionary = {}
var place_project: Dictionary = {}   # Bienes raíces: {level, opts} al colocar un multifamiliar
var _ghost: Node3D
var zone_mode := false
var _zone_marker: MeshInstance3D
var _zone_hover := Vector2i(-1, -1)


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

	var plaza_y := terrain.height_at(0, 0)
	var square := MeshLib.mesh_node(MeshLib.cylinder(8.0, 8.0, 0.12, 12), MeshLib.mat(Color(0.6, 0.52, 0.38)), Vector3(0, plaza_y + 0.02, 0))
	add_child(square)
	var well := MeshLib.make_well()
	well.position = Vector3(0, plaza_y, 0)
	add_child(well)

	buildings_root = Node3D.new()
	buildings_root.name = "Buildings"
	add_child(buildings_root)
	for b in GameState.buildings:
		_rebuild_building(int(b["id"]))

	agents_root = Node3D.new()
	agents_root.name = "Citizens"
	add_child(agents_root)
	for id in GameState.citizens:
		_spawn_agent(id)
	_update_player_marker()

	selection_ring = MeshLib.mesh_node(_ring_mesh(), MeshLib.mat(Color(1.0, 0.85, 0.2)))
	selection_ring.visible = false
	add_child(selection_ring)

	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)
	var start := Vector3(0, plaza_y, 0)
	var ph := PlayerSim.player_home(GameState)
	if not ph.is_empty():
		start = Vector3(float(ph["x"]), plaza_y, float(ph["z"])) * 0.5
	camera_rig.setup(terrain, start)

	weather_fx = WeatherFX.new()
	camera_rig.add_child(weather_fx)

	interior = InteriorView.new()
	interior.name = "Interior"
	add_child(interior)

	for vis in [LogisticsVisuals.new(), TradeVisuals.new(), TourismVisuals.new(), UtilitiesVisuals.new(), TransitVisuals.new()]:
		add_child(vis)
		vis.setup(self)

	hud = Hud.new()
	hud.name = "HUD"
	add_child(hud)

	EventBus.citizen_born.connect(_spawn_agent)
	EventBus.citizen_removed.connect(_on_citizen_removed)
	EventBus.citizens_moved.connect(_on_citizens_moved)
	EventBus.season_changed.connect(terrain.set_season)
	EventBus.weather_changed.connect(_apply_weather)
	EventBus.citizen_selected.connect(_on_citizen_selected)
	EventBus.building_changed.connect(_rebuild_building)
	EventBus.building_removed.connect(_remove_building_node)
	EventBus.zones_changed.connect(_on_zones_changed)
	EventBus.player_changed.connect(_on_player_changed)
	EventBus.build_mode_requested.connect(start_placement)
	EventBus.project_mode_requested.connect(start_project_placement)
	EventBus.zone_mode_requested.connect(start_zone_mode)
	EventBus.interior_requested.connect(open_interior)
	EventBus.day_passed.connect(_on_day)
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
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.85
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.78, 0.86)
	env.fog_density = 0.0003
	env.fog_sky_affect = 0.3
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 250.0
	add_child(sun)


# --- Edificios ---------------------------------------------------------------------------

func _rebuild_building(id: int) -> void:
	_remove_building_node(id)
	var b: Dictionary = GameState.get_building(id)
	if b.is_empty():
		return
	var ld: Dictionary = GameState.level_def(b)
	var def: Dictionary = GameState.building_def(b)
	var fp := float(def.get("footprint", 4.0))
	var root := Node3D.new()
	var pos := Vector3(float(b["x"]), 0, float(b["z"]))
	pos.y = _ground(pos.x, pos.z, fp)
	root.position = pos
	var holder := Node3D.new()
	holder.rotation.y = float(b.get("rot", 0.0))
	root.add_child(holder)
	var parts: Array = Housing.exterior_parts(b) if Housing.is_home(b) else ld.get("model", [])
	var height := MeshLib.model_height(parts)
	var tint := float(Housing.tier_def(b).get("tint", 1.0)) if Housing.is_home(b) else 1.0
	match str(b.get("status", "activo")):
		"construccion":
			var progress := clampf(float(b["work_done"]) / maxf(1.0, float(b["work_needed"])), 0.0, 1.0)
			var model := MeshLib.build_model(parts, 1.0, MeshLib.construction_mat())
			model.scale = Vector3(1, 0.1 + 0.9 * progress, 1)
			model.name = "Model"
			holder.add_child(model)
			holder.add_child(MeshLib.scaffold(fp, height))
		"mejorando":
			holder.add_child(MeshLib.build_model(parts, tint))
			holder.add_child(MeshLib.scaffold(fp, height + 0.5))
		_:
			holder.add_child(MeshLib.build_model(parts, tint))
	# Los edificios del jugador llevan una bandera dorada.
	if GameState.owned_by_player(b):
		var flag := MeshLib.mesh_node(MeshLib.box(Vector3(0.05, 1.2, 0.05)), MeshLib.mat(Color(0.3, 0.2, 0.1)), Vector3(fp * 0.5, 0.6, fp * 0.5))
		flag.add_child(MeshLib.mesh_node(MeshLib.box(Vector3(0.5, 0.3, 0.03)), MeshLib.mat(Color(0.95, 0.75, 0.2)), Vector3(0.25, 0.45, 0)))
		holder.add_child(flag)
	buildings_root.add_child(root)
	building_nodes[id] = root
	terrain.clear_trees(pos.x, pos.z, fp * 0.8 + 1.0)


func _ground(x: float, z: float, fp: float) -> float:
	var r := fp * 0.4
	var h := terrain.height_at(x, z)
	for d in [Vector2(r, r), Vector2(-r, r), Vector2(r, -r), Vector2(-r, -r)]:
		h = minf(h, terrain.height_at(x + d.x, z + d.y))
	return h


func _remove_building_node(id: int) -> void:
	if building_nodes.has(id):
		building_nodes[id].queue_free()
		building_nodes.erase(id)


func _on_day() -> void:
	# Avance visual de las obras.
	for b in GameState.buildings:
		if b["status"] == "construccion" and building_nodes.has(int(b["id"])):
			var m: Node3D = building_nodes[int(b["id"])].get_node_or_null("Model")
			if m:
				var progress := clampf(float(b["work_done"]) / maxf(1.0, float(b["work_needed"])), 0.0, 1.0)
				m.scale = Vector3(1, 0.1 + 0.9 * progress, 1)
	if interior.active and TimeManager.speed <= 2:
		interior.refresh()


func _on_zones_changed() -> void:
	terrain.build_mesh()
	terrain.scatter_nature(int(GameState.settings.get("seed", 1)))
	for id in building_nodes:
		var b: Dictionary = GameState.get_building(id)
		terrain.clear_trees(float(b["x"]), float(b["z"]), GameState.footprint_of(b) * 0.8 + 1.0)


# --- Ciudadanos ---------------------------------------------------------------------------

func _home_position(c: Citizen) -> Vector3:
	var b: Dictionary = GameState.get_building(c.home_id)
	if b.is_empty():
		return Vector3(0, terrain.height_at(0, 0), 0)
	var x := float(b["x"])
	var z := float(b["z"])
	var rot := float(b.get("rot", 0.0))
	var fp := GameState.footprint_of(b)
	var door := Vector3(x, 0, z) + Vector3(sin(rot), 0, cos(rot)) * (fp * 0.4)
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
	if interior.active:
		interior.refresh()


func _on_citizens_moved() -> void:
	for id in agents:
		if GameState.citizens.has(id):
			agents[id].set_home(_home_position(GameState.citizens[id]))
	if interior.active:
		interior.refresh()


func _on_player_changed() -> void:
	# El heredero cambia de ropa: se regenera su agente.
	for id in agents.keys():
		agents[id].queue_free()
	agents.clear()
	for id in GameState.citizens:
		_spawn_agent(id)
	_update_player_marker()


func _update_player_marker() -> void:
	for id in agents:
		agents[id].set_player_marker(GameState.is_player(id))


func _full_resync() -> void:
	for id in agents.keys():
		if not GameState.citizens.has(id):
			agents[id].queue_free()
			agents.erase(id)
	for id in GameState.citizens:
		_spawn_agent(id)
	for b in GameState.buildings:
		_rebuild_building(int(b["id"]))
	for id in building_nodes.keys():
		if GameState.get_building(id).is_empty():
			_remove_building_node(id)
	_on_citizens_moved()
	_update_player_marker()
	terrain.set_season(GameState.season)


func _apply_weather() -> void:
	var w := WeatherSim.weather_data(GameState)
	weather_fx.set_fx(str(w.get("fx", "")))
	_update_daylight()


func _process(delta: float) -> void:
	_update_daylight()
	if selected_id >= 0 and agents.has(selected_id):
		var a: CitizenAgent = agents[selected_id]
		selection_ring.visible = a.visible and not interior.active
		selection_ring.position = a.position + Vector3(0, 0.05, 0)
	else:
		selection_ring.visible = false
	_refresh_timer += delta
	if _refresh_timer > 2.0:
		_refresh_timer = 0.0
		for id in agents:
			if GameState.citizens.has(id):
				agents[id].refresh(GameState.citizens[id])
	if place_type != "" or zone_mode:
		_update_placement()


func _update_daylight() -> void:
	if sun == null:
		return
	# A velocidades altas se fija la luz de mediodía para evitar parpadeo día/noche.
	var h := 12.0 if (TimeManager.speed >= 3 or TimeManager.jumping) else TimeManager.hour_float()
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


# --- Modo construcción -------------------------------------------------------------------

func start_placement(type_id: String, tier: String) -> void:
	cancel_placement()
	if UtilitiesVisuals.instance and UtilitiesVisuals.instance.trace_mode:
		UtilitiesVisuals.instance.cancel_trace()
	place_type = type_id
	place_tier = tier
	var parts: Array = Housing.exterior_parts({"type": type_id, "level": 1, "tier": tier}) if type_id == "vivienda" else GameData.level_def(type_id, 1).get("model", [])
	_ghost = MeshLib.build_model(parts, 1.0, MeshLib.ghost_mat(true))
	add_child(_ghost)
	EventBus.citizen_selected.emit(-1)


## Bienes raíces: colocar un proyecto multifamiliar (obra nueva por etapas).
func start_project_placement(level: int, tier: String, opts: Dictionary) -> void:
	start_placement("vivienda", tier)
	place_project = {"level": level, "opts": opts}
	_ghost.queue_free()
	_ghost = MeshLib.build_model(Housing.exterior_parts({"type": "vivienda", "level": level, "tier": tier}), 1.0, MeshLib.ghost_mat(true))
	add_child(_ghost)


## Colocar una obra pública ganada en licitación.
func start_public_placement(tender: Dictionary) -> void:
	start_placement(str(tender["type"]), "normal")
	place_tender = tender


## Modo mover/girar un edificio existente.
func start_move(bid: int) -> void:
	var b: Dictionary = GameState.get_building(bid)
	if b.is_empty():
		return
	cancel_placement()
	move_id = bid
	place_type = str(b["type"])
	place_tier = str(b.get("tier", "normal"))
	place_rot = float(b.get("rot", 0.0))
	var parts: Array = Housing.exterior_parts(b) if Housing.is_home(b) else GameState.level_def(b).get("model", [])
	_ghost = MeshLib.build_model(parts, 1.0, MeshLib.ghost_mat(true))
	add_child(_ghost)
	if building_nodes.has(bid):
		building_nodes[bid].visible = false


func start_zone_mode() -> void:
	cancel_placement()
	zone_mode = true
	var zs := GameState.MAP_SIZE / GameState.ZONE_GRID
	_zone_marker = MeshLib.mesh_node(MeshLib.box(Vector3(zs, 40, zs)), MeshLib.ghost_mat(true))
	add_child(_zone_marker)


func cancel_placement() -> void:
	if move_id >= 0 and building_nodes.has(move_id):
		building_nodes[move_id].visible = true
	move_id = -1
	place_tender = {}
	place_project = {}
	place_type = ""
	zone_mode = false
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	if _zone_marker:
		_zone_marker.queue_free()
		_zone_marker = null
	if LogisticsVisuals.instance:
		LogisticsVisuals.instance.clear_placement_feedback()
	if hud:
		hud.set_placement_hint("")


func _mouse_ground() -> Variant:
	var cam := camera_rig.camera
	var mp := get_viewport().get_mouse_position()
	return terrain.ray_ground(cam.project_ray_origin(mp), cam.project_ray_normal(mp))


func _update_placement() -> void:
	var g = _mouse_ground()
	if g == null:
		return
	var p: Vector3 = g
	if zone_mode:
		var zc := terrain.zone_of(p.x, p.z)
		_zone_hover = zc
		var zs := GameState.MAP_SIZE / GameState.ZONE_GRID
		var half := GameState.MAP_SIZE * 0.5
		_zone_marker.position = Vector3(-half + (zc.x + 0.5) * zs, 10, -half + (zc.y + 0.5) * zs)
		var reason := ConstructionSim.zone_block_reason(GameState, zc.x, zc.y)
		_zone_marker.material_override = MeshLib.ghost_mat(reason == "")
		hud.set_placement_hint("Comprar terreno al gobierno: %s · %s   (clic para comprar, clic derecho/Esc cancela)" % [Fmt.money(ConstructionSim.zone_cost(GameState)), reason if reason != "" else "disponible"])
		return
	p.x = snappedf(p.x, 0.25)
	p.z = snappedf(p.z, 0.25)
	var place_level := int(GameState.get_building(move_id).get("level", 1)) if move_id >= 0 else int(place_project.get("level", 1))
	var fp := GameData.footprint(place_type, place_level)
	place_pos = Vector3(p.x, _ground(p.x, p.z, fp), p.z)
	place_reason = ConstructionSim.placement_block_reason(GameState, place_type, p.x, p.z, move_id, place_level)
	if place_reason == "":
		place_reason = terrain.footprint_ok(p.x, p.z, fp)
	if place_reason == "" and move_id < 0 and not place_project.is_empty():
		place_reason = RealEstateSim.project_block_reason(GameState, place_level, place_tier, float(place_project["opts"].get("credit_ratio", 0.0)))
	elif place_reason == "" and move_id < 0 and place_tender.is_empty():
		place_reason = ConstructionSim.build_block_reason(GameState, place_type, place_tier)
	place_ok = place_reason == ""
	_ghost.position = place_pos
	_ghost.rotation.y = place_rot
	# Almacenes individuales: ghost verde brillante + flecha si queda al lado de un almacén.
	var gm: Material = MeshLib.ghost_mat(place_ok)
	var link_hint := ""
	if LogisticsVisuals.instance:
		gm = LogisticsVisuals.instance.placement_feedback(place_type, place_pos, move_id, place_ok, gm)
		link_hint = LogisticsVisuals.instance.placement_text()
	_set_ghost_mat(_ghost, gm)
	var deg := int(round(fposmod(rad_to_deg(place_rot), 360.0)))
	if move_id >= 0:
		var mb: Dictionary = GameState.get_building(move_id)
		hud.set_placement_hint("Mover %s — %s · %d°   %s   (R/T gira 15° · Shift+rueda gira libre · clic confirma · Esc cancela)" % [
			GameState.building_label(mb), "gratis" if ConstructionSim.move_cost(GameState, mb, p.x, p.z) <= 0.0 else Fmt.money(ConstructionSim.move_cost(GameState, mb, p.x, p.z)), deg, "✔" if place_ok else place_reason] + link_hint)
		return
	if not place_project.is_empty():
		var pc := ConstructionSim.cost_for(GameState, "vivienda", place_level, false, place_tier)
		hud.set_placement_hint("Proyecto %s — %s en 3 etapas · %d días · %d°   %s   (R/T gira 15° · clic construye · Esc cancela)" % [
			GameData.level_def("vivienda", place_level).get("label", ""), Fmt.money(pc["total"]), int(pc["days"]), deg, "✔" if place_ok else place_reason] + link_hint)
		return
	var cost := ConstructionSim.cost_for(GameState, place_type, 1, false, place_tier)
	hud.set_placement_hint("%s — %s · %d días · %d°   %s   (R/T gira 15° · Shift+rueda gira libre · clic construye · Esc cancela)" % [
		GameData.level_def(place_type, 1).get("label", place_type), Fmt.money(cost["total"]), int(cost["days"]), deg,
		"✔" if place_ok else place_reason] + link_hint)


func _set_ghost_mat(node: Node, m: Material) -> void:
	if node is MeshInstance3D:
		node.material_override = m
	for ch in node.get_children():
		_set_ghost_mat(ch, m)


func _confirm_placement() -> void:
	if zone_mode:
		var err := ConstructionSim.unlock_zone(GameState, _zone_hover.x, _zone_hover.y)
		if err != "":
			hud.toast(err, "jugador")
		cancel_placement()
		return
	if not place_ok:
		hud.toast(place_reason, "jugador")
		return
	if not place_tender.is_empty():
		var perr := GovSim.start_public_project(GameState, place_tender, place_pos.x, place_pos.z, place_rot)
		if perr != "":
			hud.toast(perr, "jugador")
			return
		cancel_placement()
		return
	if not place_project.is_empty():
		var pr := RealEstateSim.start_project(GameState, int(place_project["level"]), place_tier, place_pos.x, place_pos.z, place_rot, "", place_project["opts"])
		if pr.has("error"):
			hud.toast(pr["error"], "jugador")
			return
		cancel_placement()
		return
	if move_id >= 0:
		var err := ConstructionSim.move_building(GameState, GameState.get_building(move_id), place_pos.x, place_pos.z, place_rot)
		if err != "":
			hud.toast(err, "jugador")
			return
		cancel_placement()
		return
	var def := GameData.building_def(place_type)
	var type_id := place_type
	var tier := place_tier
	var pos := place_pos
	var rot := place_rot
	if str(def.get("category", "")) == "negocio":
		# Nombre y tipo legal antes de construir.
		hud.ask_business_details(type_id, _build_business.bind(type_id, pos, rot, tier))
	else:
		var r := ConstructionSim.start_construction(GameState, type_id, pos.x, pos.z, rot, "", "sas", tier)
		if r.has("error"):
			hud.toast(r["error"], "jugador")
	if not Input.is_key_pressed(KEY_SHIFT):
		cancel_placement()


func _build_business(bname: String, legal: String, type_id: String, pos: Vector3, rot: float, tier: String) -> void:
	var r := ConstructionSim.start_construction(GameState, type_id, pos.x, pos.z, rot, bname, legal, tier)
	if r.has("error"):
		hud.toast(r["error"], "jugador")


# --- Interior ------------------------------------------------------------------------------

func open_interior(bid: int) -> void:
	cancel_placement()
	if interior.active:
		interior.close()
	interior.open(bid)
	hud.show_interior(bid)


func close_interior() -> void:
	interior.close()
	camera_rig.camera.current = true
	EventBus.interior_closed.emit()


# --- Entrada ----------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if interior.active:
		return
	if place_type != "" or zone_mode:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				_confirm_placement()
				get_viewport().set_input_as_handled()
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				cancel_placement()
				get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.pressed and event.shift_pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			place_rot += deg_to_rad(5.0) * (1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0)
			get_viewport().set_input_as_handled()
		elif event is InputEventKey and event.pressed:
			if event.keycode == KEY_R:
				place_rot += deg_to_rad(15.0)
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_T:
				place_rot -= deg_to_rad(15.0)
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_ESCAPE:
				cancel_placement()
				get_viewport().set_input_as_handled()
		return
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
	var best_bd := 50.0
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


func focus_building(id: int) -> void:
	if building_nodes.has(id):
		camera_rig.focus(building_nodes[id].global_position, 28.0)
