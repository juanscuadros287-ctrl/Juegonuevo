class_name MiningVisuals
extends Node3D
## Visuales 3D de las minas por partes (docs/MINAS.md):
## - Área de cada yacimiento: malla propia pegada al terreno (misma rejilla que Terrain) con el
##   shader deposit_area (vetas rojizas de hierro, negras de carbón, doradas de oro; manchas de
##   petróleo/gas), rocas y afloramientos, y un cartel con el nombre y la reserva estimada.
## - Frentes y escombreras de cada mina (modelos de data/mining.json) unidos al centro con un
##   camino, rieles o tubería; en obra se ven como andamio.
## - Modo de colocación de frentes: fantasma verde dentro del área, rojo fuera.
## - Al colocar un centro de excavación (modo construir de world.gd) se resaltan las áreas
##   del mineral que necesita.
## No toca terrain.gd: todo son nodos propios encima del terreno. world.gd llama setup(world).

static var instance: MiningVisuals

var world: Node3D
var _areas_root: Node3D
var _deco_root: Node3D
var _parts_root: Node3D
var _areas := {}            # id de yacimiento -> {mat, label}
var _dirty := false
var _deposit_count := -1
var _hl_key := ""
# Modo colocar frente
var part_mode := false
var _part_bid := -1
var _part_kind := ""
var _part_rot := 0.0
var _ghost: Node3D
var _ghost_pos := Vector3.ZERO
var _ghost_ok := false
var _ghost_reason := ""


func setup(p_world: Node3D) -> void:
	world = p_world
	instance = self
	name = "MiningVisuals"
	_areas_root = Node3D.new()
	_areas_root.name = "DepositAreas"
	add_child(_areas_root)
	_deco_root = Node3D.new()
	add_child(_deco_root)
	_parts_root = Node3D.new()
	_parts_root.name = "MineParts"
	add_child(_parts_root)
	rebuild_all()
	EventBus.building_changed.connect(func(_id): _dirty = true)
	EventBus.building_removed.connect(func(_id): _dirty = true)
	EventBus.day_passed.connect(_on_day)
	EventBus.jump_finished.connect(func(_r): rebuild_all())


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _terrain() -> Terrain:
	return world.terrain if world else null


func _h(x: float, z: float) -> float:
	var t := _terrain()
	return t.height_at(x, z) if t else 0.0


func _ground(x: float, z: float, fp: float) -> float:
	var r := fp * 0.4
	var h := _h(x, z)
	for d in [Vector2(r, r), Vector2(-r, r), Vector2(r, -r), Vector2(-r, -r)]:
		h = minf(h, _h(x + d.x, z + d.y))
	return h


func rebuild_all() -> void:
	for ch in _areas_root.get_children():
		ch.queue_free()
	_areas.clear()
	_hl_key = ""
	var deps := RegionSim.deposits(GameState)
	_deposit_count = deps.size()
	for d in deps:
		_build_area(d)
	rebuild_parts()


# --- Áreas de yacimiento -----------------------------------------------------------------------

func _build_area(d: Dictionary) -> void:
	var t := _terrain()
	if t == null:
		return
	var cell := 2.5
	var cv = t.get("cell")
	if cv != null:
		cell = float(cv)
	var half: float = GameState.MAP_SIZE * 0.5
	var cx := float(d["x"])
	var cz := float(d["z"])
	var reach := float(d["radius"]) * 1.25 + cell
	var i0 := int(floor((cx - reach + half) / cell))
	var i1 := int(ceil((cx + reach + half) / cell))
	var j0 := int(floor((cz - reach + half) / cell))
	var j1 := int(ceil((cz + reach + half) / cell))
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var water: float = t.water_level
	for j in range(j0, j1):
		for i in range(i0, i1):
			var x0 := -half + i * cell
			var z0 := -half + j * cell
			if Vector2(x0 + cell * 0.5 - cx, z0 + cell * 0.5 - cz).length() > reach:
				continue
			var v00 := Vector3(x0, _h(x0, z0) + 0.07, z0)
			var v10 := Vector3(x0 + cell, _h(x0 + cell, z0) + 0.07, z0)
			var v01 := Vector3(x0, _h(x0, z0 + cell) + 0.07, z0 + cell)
			var v11 := Vector3(x0 + cell, _h(x0 + cell, z0 + cell) + 0.07, z0 + cell)
			if minf(minf(v00.y, v10.y), minf(v01.y, v11.y)) < water + 0.1:
				continue
			for tri in [[v00, v10, v01], [v10, v11, v01]]:
				var a: Vector3 = tri[0]
				var b: Vector3 = tri[1]
				var c: Vector3 = tri[2]
				var nrm := (c - a).cross(b - a).normalized()
				verts.append_array([a, b, c])
				normals.append_array([nrm, nrm, nrm])
	var root := Node3D.new()
	_areas_root.add_child(root)
	var type := str(d["type"])
	var col := RegionSim.resource_color(type)
	var pattern := str(MineSim.cfg().get("deposits", {}).get(type, {}).get("pattern", "vetas"))
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/deposit_area.gdshader")
	var ore := col
	if type == "hierro":
		ore = Color(0.5, 0.2, 0.13)   # Vetas rojizas.
	elif type == "carbon":
		ore = Color(0.06, 0.06, 0.07)
	mat.set_shader_parameter("ore_color", Vector3(ore.r, ore.g, ore.b))
	var soil := Color(0.44, 0.37, 0.28).lerp(col, 0.12)
	mat.set_shader_parameter("soil_color", Vector3(soil.r, soil.g, soil.b))
	mat.set_shader_parameter("center", Vector2(cx, cz))
	mat.set_shader_parameter("radius", float(d["radius"]))
	mat.set_shader_parameter("shape", PackedFloat32Array(d["shape"]))
	mat.set_shader_parameter("pattern", 1 if pattern == "manchas" else 0)
	mat.set_shader_parameter("seed", float(int(d["id"]) % 17))
	mat.set_shader_parameter("depleted", 1.0 - MineSim.reserve_frac(d))
	if not verts.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	# Cartel con el nombre y la reserva, en el borde del área que mira al pueblo.
	var to_town := Vector2(-cx, -cz).angle()
	var sr := MineSim.radius_at(d, to_town) * 0.82
	var sp := Vector2(cx, cz) + Vector2.from_angle(to_town) * sr
	var board := Node3D.new()
	board.position = Vector3(sp.x, _h(sp.x, sp.y), sp.y)
	board.rotation.y = atan2(-sp.x, -sp.y)
	var post_mat := MeshLib.mat(Color(0.35, 0.24, 0.14))
	for px in [-0.8, 0.8]:
		board.add_child(MeshLib.mesh_node(MeshLib.cached("mine_sign_post", func(): return MeshLib.box(Vector3(0.14, 2.6, 0.14))), post_mat, Vector3(px, 1.3, 0)))
	board.add_child(MeshLib.mesh_node(MeshLib.cached("mine_sign_board", func(): return MeshLib.box(Vector3(2.2, 1.0, 0.1))), MeshLib.mat(Color(0.62, 0.48, 0.3)), Vector3(0, 2.1, 0)))
	board.add_child(MeshLib.mesh_node(MeshLib.cached("mine_sign_band", func(): return MeshLib.box(Vector3(2.2, 0.22, 0.12))), MeshLib.mat(col), Vector3(0, 2.72, 0)))
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.pixel_size = 0.022
	label.outline_size = 10
	label.modulate = col.lightened(0.45)
	label.position = Vector3(0, 4.1, 0)
	label.no_depth_test = false
	board.add_child(label)
	root.add_child(board)
	t.clear_trees(cx, cz, float(d["radius"]) * 0.9)   # Suelo pelado y rocoso sobre el yacimiento.
	_areas[int(d["id"])] = {"mat": mat, "label": label, "deco": [], "d": d}
	_update_label(d)


func _update_label(d: Dictionary) -> void:
	var a: Dictionary = _areas.get(int(d["id"]), {})
	if a.is_empty():
		return
	var frac := MineSim.reserve_frac(d)
	var lbl: Label3D = a["label"]
	if float(d["amount"]) <= 0.0:
		lbl.text = "Yacimiento de %s\nAGOTADO" % RegionSim.resource_label(str(d["type"])).to_lower()
	else:
		lbl.text = "Yacimiento de %s\nReserva ≈ %s (%d %%) · ley %s" % [RegionSim.resource_label(str(d["type"])).to_lower(),
			Fmt.thousands(snappedf(float(d["amount"]), 10.0)), int(round(frac * 100.0)), MineSim.grade_text(float(d.get("grade", 1.0))).split(" ")[0]]
	(a["mat"] as ShaderMaterial).set_shader_parameter("depleted", 1.0 - frac)


## Rocas y afloramientos (se recalculan cuando cambian los edificios para no atravesarlos).
func _rebuild_deco() -> void:
	for ch in _deco_root.get_children():
		ch.queue_free()
	var blockers := []
	for b in GameState.buildings:
		blockers.append([Vector2(float(b["x"]), float(b["z"])), GameState.footprint_of(b) * 0.5 + 1.0])
		if b.has("mine") and b["mine"] is Dictionary:
			for p in (b["mine"] as Dictionary).get("parts", []):
				blockers.append([Vector2(float(p["x"]), float(p["z"])), MineSim.part_footprint(str(p["kind"])) * 0.5 + 0.8])
	var rock_mat := MeshLib.mat(Color(0.47, 0.45, 0.42))
	var rock2_mat := MeshLib.mat(Color(0.38, 0.36, 0.34))
	var rock_mesh := MeshLib.cached("mine_rock", func(): return MeshLib.sphere(0.9, 6, 3))
	var crystal := MeshLib.cached("mine_crystal", func(): return MeshLib.cylinder(0.0, 0.3, 1.0, 5))
	var puddle := MeshLib.cached("mine_puddle", func(): return MeshLib.cylinder(1.0, 1.0, 0.06, 10))
	for d in RegionSim.deposits(GameState):
		var type := str(d["type"])
		var pattern := str(MineSim.cfg().get("deposits", {}).get(type, {}).get("pattern", "vetas"))
		var ore := MeshLib.mat(RegionSim.resource_color(type), 0.35)
		var rng := RandomNumberGenerator.new()
		rng.seed = int(d["id"]) * 7919 + type.hash()
		var n := int(float(d["radius"]) / 2.2)
		var t := _terrain()
		for k in range(n):
			var ang := rng.randf() * TAU
			var dist := sqrt(rng.randf()) * MineSim.radius_at(d, ang) * 0.85
			var p := Vector2(float(d["x"]), float(d["z"])) + Vector2.from_angle(ang) * dist
			var s := rng.randf_range(0.6, 1.5)
			var rot := rng.randf() * TAU
			var blocked := false
			for bl in blockers:
				if p.distance_to(bl[0]) < float(bl[1]) + s:
					blocked = true
					break
			if blocked or (t and not t.is_land(p.x, p.y, 0.3)):
				continue
			var node := Node3D.new()
			node.position = Vector3(p.x, _h(p.x, p.y), p.y)
			node.rotation.y = rot
			if pattern == "manchas" and k % 2 == 0:
				var pd := MeshLib.mesh_node(puddle, MeshLib.mat(Color(0.03, 0.03, 0.03), 0.1), Vector3(0, 0.08, 0))
				pd.scale = Vector3(s * 1.4, 1.0, s)
				node.add_child(pd)
			else:
				var r := MeshLib.mesh_node(rock_mesh, rock_mat if k % 3 else rock2_mat, Vector3(0, 0.15 * s, 0))
				r.scale = Vector3(s * 1.2, s * 0.65, s)
				node.add_child(r)
				if pattern == "vetas":
					for c in range(1 + k % 3):
						var cr := MeshLib.mesh_node(crystal, ore, Vector3(rng.randf_range(-0.5, 0.5) * s, 0.55 * s, rng.randf_range(-0.4, 0.4) * s))
						cr.rotation = Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5))
						cr.scale = Vector3.ONE * s * 0.8
						node.add_child(cr)
			_deco_root.add_child(node)


# --- Frentes y escombreras ---------------------------------------------------------------------

func rebuild_parts() -> void:
	for ch in _parts_root.get_children():
		ch.queue_free()
	for b in GameState.buildings:
		if not b.has("mine") or not (b["mine"] is Dictionary):
			continue
		var col: Array = [0.6, 0.6, 0.6]
		var need := str(GameState.level_def(b).get("requires_deposit", ""))
		if need != "":
			col = RegionSim.resource_def(need).get("color", col)
		var center := Vector2(float(b["x"]), float(b["z"]))
		for p in (b["mine"] as Dictionary).get("parts", []):
			var kind := str(p["kind"])
			var kd := MineSim.kind_def(kind)
			var fp := MineSim.part_footprint(kind)
			var px := float(p["x"])
			var pz := float(p["z"])
			var root := Node3D.new()
			root.position = Vector3(px, _ground(px, pz, fp), pz)
			var holder := Node3D.new()
			holder.rotation.y = float(p.get("rot", 0.0))
			root.add_child(holder)
			var parts: Array = MineSim.tint_parts(kd.get("model", []), col)
			if str(p.get("status", "")) == "obra":
				var total := maxf(1.0, float(kd.get("build_days", 8)))
				var progress := clampf(1.0 - float(p.get("days_left", 0)) / total, 0.0, 1.0)
				var model := MeshLib.build_model(parts, 1.0, MeshLib.construction_mat())
				model.scale = Vector3(1, 0.15 + 0.85 * progress, 1)
				holder.add_child(model)
				holder.add_child(MeshLib.scaffold(fp * 0.6, 3.0))
			else:
				holder.add_child(MeshLib.build_model(parts))
			_parts_root.add_child(root)
			_parts_root.add_child(_link_node(center, Vector2(px, pz), kind, GameState.footprint_of(b) * 0.45, fp * 0.45))
			if _terrain():
				_terrain().clear_trees(px, pz, fp * 0.8 + 1.0)
	_rebuild_deco()


## Conexión centro → frente: camino de tierra (tajo, escombrera), rieles (socavón, torre) o
## tubería (pozos), siguiendo el terreno.
func _link_node(a: Vector2, b: Vector2, kind: String, skip_a: float, skip_b: float) -> Node3D:
	var root := Node3D.new()
	var dir := b - a
	var length := dir.length()
	if length < skip_a + skip_b + 0.5:
		return root
	var u := dir / length
	var start := a + u * skip_a
	var end := b - u * skip_b
	var seg := end - start
	var n := maxi(1, int(ceil(seg.length() / 2.0)))
	var yaw := atan2(u.x, u.y)
	var style := "camino"
	if kind in ["socavon", "torre_extraccion"]:
		style = "rieles"
	elif MineSim.kind_def(kind).get("set", "mina") == "pozo":
		style = "tubo"
	var dirt := MeshLib.mat(Color(0.5, 0.4, 0.28))
	var iron := MeshLib.mat(Color(0.22, 0.22, 0.24), 0.5)
	var wood := MeshLib.mat(Color(0.36, 0.25, 0.15))
	var side := Vector2(-u.y, u.x)
	for i in range(n):
		var p0 := start + seg * (float(i) / n)
		var p1 := start + seg * (float(i + 1) / n)
		var m := (p0 + p1) * 0.5
		var l := p0.distance_to(p1)
		var h0 := _h(p0.x, p0.y)
		var h1 := _h(p1.x, p1.y)
		var pitch := atan2(h1 - h0, l)
		match style:
			"camino":
				var piece := MeshLib.mesh_node(MeshLib.cached("mine_path_%.2f" % l, func(): return MeshLib.box(Vector3(1.8, 0.06, l + 0.1))), dirt, Vector3(m.x, (h0 + h1) * 0.5 + 0.06, m.y))
				piece.rotation = Vector3(-pitch, yaw, 0)
				root.add_child(piece)
			"rieles":
				for s in [-0.4, 0.4]:
					var q: Vector2 = m + side * s
					var rail := MeshLib.mesh_node(MeshLib.cached("mine_rail_%.2f" % l, func(): return MeshLib.box(Vector3(0.08, 0.1, l + 0.05))), iron, Vector3(q.x, (h0 + h1) * 0.5 + 0.16, q.y))
					rail.rotation = Vector3(-pitch, yaw, 0)
					root.add_child(rail)
				var sl := MeshLib.mesh_node(MeshLib.cached("mine_sleeper", func(): return MeshLib.box(Vector3(1.2, 0.08, 0.25))), wood, Vector3(m.x, (h0 + h1) * 0.5 + 0.06, m.y))
				sl.rotation.y = yaw
				root.add_child(sl)
			_:
				var pipe := MeshLib.mesh_node(MeshLib.cached("mine_pipe_%.2f" % l, func(): return MeshLib.cylinder(0.14, 0.14, l + 0.05, 6)), iron, Vector3(m.x, (h0 + h1) * 0.5 + 0.35, m.y))
				pipe.rotation = Vector3(PI * 0.5 - pitch, yaw, 0)
				root.add_child(pipe)
	return root


# --- Actualización -----------------------------------------------------------------------------

func _on_day() -> void:
	var deps := RegionSim.deposits(GameState)
	if deps.size() != _deposit_count:
		rebuild_all()   # La investigación reveló yacimientos nuevos.
		return
	if TimeManager.speed <= 2:
		for d in deps:
			_update_label(d)
		# Avance de las obras de frentes.
		for b in GameState.buildings:
			if b.has("mine") and (b["mine"] as Dictionary).get("parts", []).any(func(p): return str(p.get("status", "")) == "obra"):
				_dirty = true
				break


func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		rebuild_parts()
	if part_mode:
		_update_part_ghost()
	_update_highlight()


## Resalta (contorno verde) las áreas donde se puede poner lo que se está colocando.
func _update_highlight() -> void:
	var want_type := ""
	var want_id := -1
	if part_mode:
		var b: Dictionary = GameState.get_building(_part_bid)
		var dep := RegionSim.deposit_for(GameState, b) if not b.is_empty() else {}
		want_id = int(dep.get("id", -1))
	elif world and str(world.get("place_type")) != "" and MineSim.is_mine_type(str(world.get("place_type"))):
		want_type = str(GameData.level_def(str(world.get("place_type")), 1).get("requires_deposit", ""))
	var key := "%s_%d" % [want_type, want_id]
	if key == _hl_key:
		return
	_hl_key = key
	for id in _areas:
		var a: Dictionary = _areas[id]
		var d: Dictionary = a["d"]
		var on := int(id) == want_id or (want_type != "" and str(d["type"]) == want_type and float(d["amount"]) > 0.0)
		(a["mat"] as ShaderMaterial).set_shader_parameter("highlight", 1.0 if on else 0.0)


## Texto extra para la pista de colocación de world.gd (centro de excavación).
func placement_text(type_id: String, pos: Vector3) -> String:
	if not MineSim.is_mine_type(type_id):
		return ""
	var need := str(GameData.level_def(type_id, 1).get("requires_deposit", ""))
	var dep := RegionSim.nearest_deposit(GameState, need, pos.x, pos.z)
	if dep.is_empty():
		return "   ⛏ Pon el centro de excavación DENTRO de un área de %s (contorno verde)" % RegionSim.resource_label(need).to_lower()
	return "   ⛏ Yacimiento de %s: reserva ≈ %s · ley %s. Después agrega frentes (pestaña Mina)" % [
		RegionSim.resource_label(need).to_lower(), Fmt.thousands(float(dep["amount"])), MineSim.grade_text(float(dep.get("grade", 1.0)))]


# --- Modo colocar frente -----------------------------------------------------------------------

func start_part_placement(bid: int, kind: String) -> void:
	cancel_part_placement()
	if world and world.has_method("cancel_placement"):
		world.cancel_placement()
	var b: Dictionary = GameState.get_building(bid)
	if b.is_empty():
		return
	part_mode = true
	_part_bid = bid
	_part_kind = kind
	var need := str(GameState.level_def(b).get("requires_deposit", ""))
	var col: Array = RegionSim.resource_def(need).get("color", [0.6, 0.6, 0.6])
	_ghost = MeshLib.build_model(MineSim.tint_parts(MineSim.kind_def(kind).get("model", []), col), 1.0, MeshLib.ghost_mat(true))
	add_child(_ghost)
	_hl_key = ""


func cancel_part_placement() -> void:
	part_mode = false
	_part_bid = -1
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	_hl_key = ""
	if world and world.hud:
		world.hud.set_placement_hint("")


## Coloca el fantasma en (x, z) (desde el mouse o desde pruebas) y valida.
func set_ghost_at(x: float, z: float) -> void:
	var b: Dictionary = GameState.get_building(_part_bid)
	if b.is_empty():
		cancel_part_placement()
		return
	x = snappedf(x, 0.25)
	z = snappedf(z, 0.25)
	var fp := MineSim.part_footprint(_part_kind)
	_ghost_pos = Vector3(x, _ground(x, z, fp), z)
	_ghost_reason = MineSim.part_block_reason(GameState, b, _part_kind, x, z)
	var t := _terrain()
	if _ghost_reason == "" and t and not t.is_land(x, z, 0.3):
		_ghost_reason = "No se puede en el agua"
	_ghost_ok = _ghost_reason == ""
	if _ghost:
		_ghost.position = _ghost_pos
		_ghost.rotation.y = _part_rot
		_set_mat(_ghost, MeshLib.ghost_mat(_ghost_ok))
	if world and world.hud:
		var kd := MineSim.kind_def(_part_kind)
		world.hud.set_placement_hint("%s para %s — %s · %d días   %s   (R/T gira · clic construye · Shift mantiene · Esc cancela)" % [
			MineSim.kind_label(_part_kind), GameState.building_label(b), Fmt.money(MineSim.part_cost(GameState, b, _part_kind)),
			int(kd.get("build_days", 8)), "✔ dentro del yacimiento" if _ghost_ok else _ghost_reason])


func ghost_ok() -> bool:
	return _ghost_ok


func _update_part_ghost() -> void:
	if world == null or not world.has_method("_mouse_ground"):
		return
	var g = world._mouse_ground()
	if g == null:
		return
	var p: Vector3 = g
	set_ghost_at(p.x, p.z)


func _set_mat(node: Node, m: Material) -> void:
	if node is MeshInstance3D:
		node.material_override = m
	for ch in node.get_children():
		_set_mat(ch, m)


func confirm_part() -> String:
	var b: Dictionary = GameState.get_building(_part_bid)
	if b.is_empty():
		cancel_part_placement()
		return "La mina ya no existe"
	if not _ghost_ok:
		return _ghost_reason
	var err := MineSim.add_part(GameState, b, _part_kind, _ghost_pos.x, _ghost_pos.z, _part_rot)
	if err == "":
		rebuild_parts()
	return err


func _unhandled_input(event: InputEvent) -> void:
	if not part_mode:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var err := confirm_part()
			if err != "" and world and world.hud:
				world.hud.toast(err, "jugador")
			elif not event.shift_pressed:
				cancel_part_placement()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cancel_part_placement()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_R:
			_part_rot += deg_to_rad(15.0)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_T:
			_part_rot -= deg_to_rad(15.0)
			get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	# Esc se atiende antes que el HUD (que abriría el menú de pausa).
	if part_mode and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel_part_placement()
		get_viewport().set_input_as_handled()
