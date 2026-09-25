extends Node
## Pruebas de las minas por partes (docs/MINAS.md): yacimientos como áreas, centro de
## excavación dentro del área, frentes que suman capacidad, agotamiento, migración y guardado.
## godot --headless res://tests/test_minas.tscn

var failures := 0
var ui_done := false
var gs = GameState


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func _ready() -> void:
	print("== Dinastía: pruebas de minas por partes ==")
	_test_areas()
	_test_generated()
	_test_block_outside()
	_test_faces()
	_test_depletion()
	_test_migration()
	_test_save_load()
	await _test_ui()
	check(ui_done, "la prueba de interfaz terminó sin errores de script")
	print("== %s (%d fallos) ==" % ["TODO OK" if failures == 0 else "CON FALLOS", failures])
	get_tree().quit(1 if failures > 0 else 0)


# --- Utilidades -----------------------------------------------------------------------------

func _new(seed_value := 11) -> void:
	gs.new_game({"seed": seed_value, "difficulty": "facil", "map_type": "interior"})
	gs.suppress_notifications = true
	gs.money = 200000.0
	gs.unlocked_zones.append([3, 2])
	gs.unlocked_zones.append([2, 3])


## Yacimientos en el formato viejo (puntos): la migración les da área al leerlos.
func _set_deposits(list: Array) -> void:
	var out := []
	for d in list:
		out.append({"id": out.size() + 1, "type": d[0], "x": float(d[1]), "z": float(d[2]), "amount": float(d[3]), "initial": float(d[3])})
	gs.logistics["deposits"] = out


func _place(type_id: String, x: float, z: float, level := 1) -> Dictionary:
	var b: Dictionary = ConstructionSim.make_building(gs, type_id, level, x, z, 0.0, "jugador")
	gs.add_building(b)
	return b


## Mina construida como el jugador (sin frentes), terminada al instante.
func _build_mine(type_id: String, x: float, z: float) -> Dictionary:
	var r := ConstructionSim.start_construction(gs, type_id, x, z, 0.0, "Mina prueba", "sas")
	if r.has("error"):
		print("    error al construir: ", r["error"])
		return {}
	var b: Dictionary = r["building"]
	b["status"] = "activo"
	b["work_done"] = 0.0
	for c in gs.citizens.values():
		if c.job_id == int(b["id"]) and c.job_kind == "obra":
			c.job_id = -1
			c.job_kind = ""
	return b


func _hire(b: Dictionary, n: int) -> int:
	var hired := 0
	for c in BusinessSim.candidates(gs, b):
		if hired >= n:
			break
		if c.job_kind == "obra":
			continue
		if BusinessSim.hire(gs, b, c, BusinessSim.asked_wage(gs, c, str(b["type"])) * 1.1) == "":
			hired += 1
	return hired


func _staff(b: Dictionary) -> int:
	return gs.employees_of(int(b["id"])).filter(func(c): return c.job_kind == "empleo").size()


## Punto dentro del área a una fracción del radio en un ángulo.
func _inside(d: Dictionary, ang: float, frac: float) -> Vector2:
	return Vector2(float(d["x"]), float(d["z"])) + Vector2.from_angle(ang) * MineSim.radius_at(d, ang) * frac


# --- Pruebas ------------------------------------------------------------------------------------

func _test_areas() -> void:
	_new(21)
	_set_deposits([["hierro", 70, 10, 14000], ["oro", 70, -40, 1500]])
	var deps := RegionSim.deposits(gs)
	var iron: Dictionary = deps[0]
	var gold: Dictionary = deps[1]
	check(iron.has("radius") and iron.has("shape") and (iron["shape"] as Array).size() == 12, "un yacimiento puntual se migra a un área (radio %.1f m)" % float(iron["radius"]))
	check(float(iron["x"]) == 70.0 and float(iron["z"]) == 10.0 and is_equal_approx(float(iron["grade"]), 1.0), "el área queda centrada en el mismo punto y con ley 1 (no cambia la producción)")
	check(float(iron["radius"]) >= 26.0 * 0.95 and float(iron["radius"]) <= 36.0 * 1.05, "hierro: área grande (%.1f m)" % float(iron["radius"]))
	check(float(gold["radius"]) >= 16.0 and float(gold["radius"]) <= 23.0 * 1.05 and float(gold["radius"]) < float(iron["radius"]), "oro: veta pequeña (%.1f m)" % float(gold["radius"]))
	var rs := []
	for i in range(12):
		rs.append(MineSim.radius_at(iron, TAU * i / 12.0))
	check(rs.max() - rs.min() > 1.5, "el área es irregular (radios de %.1f a %.1f m)" % [rs.min(), rs.max()])
	check(MineSim.contains(iron, 70 + float(rs[0]) * 0.9, 10) and not MineSim.contains(iron, 70 + float(iron["radius"]) * 1.3, 10), "contains respeta el borde irregular")
	var again := {"id": 1, "type": "hierro", "x": 70.0, "z": 10.0, "amount": 14000.0, "initial": 14000.0}
	MineSim.ensure_area(again)
	check(float(again["radius"]) == float(iron["radius"]) and str(again["shape"]) == str(iron["shape"]), "la migración es determinista")
	var near := {"id": 3, "type": "carbon", "x": 35.0, "z": 0.0, "amount": 18000.0, "initial": 18000.0}
	MineSim.ensure_area(near)
	check(float(near["radius"]) <= 35.0 - 14.0 + 0.01 or float(near["radius"]) <= 16.0, "un yacimiento junto al pueblo no cubre la plaza (%.1f m)" % float(near["radius"]))


func _test_generated() -> void:
	for seed_value in [5, 77]:
		for map in ["interior", "montana"]:
			var reg: Dictionary = RegionSim.candidates(map, seed_value)[0]
			var deps := RegionSim.generate_deposits(map, seed_value, reg)
			var ok := true
			for d in deps:
				if not d.has("radius") or not d.has("grade") or float(d["radius"]) < 16.0:
					ok = false
			check(ok, "%s/%d: %d yacimientos generados como áreas con ley" % [map, seed_value, deps.size()])


func _test_block_outside() -> void:
	_new(31)
	_set_deposits([["hierro", 70, 10, 14000]])
	var d: Dictionary = RegionSim.deposits(gs)[0]
	var out := Vector2(70, 10) + Vector2(float(d["radius"]) * 1.35, 0)
	var reason := ConstructionSim.placement_block_reason(gs, "mina_hierro", out.x, out.y)
	check(reason.find("DENTRO") >= 0 and reason.find("yacimiento") >= 0, "fuera del área se bloquea con mensaje claro: '%s'" % reason)
	var r := ConstructionSim.start_construction(gs, "mina_hierro", out.x, out.y, 0.0)
	check(r.has("error"), "start_construction también lo rechaza")
	var inside := _inside(d, 0.4, 0.6)
	check(ConstructionSim.placement_block_reason(gs, "mina_hierro", inside.x, inside.y) == "", "dentro del área (a 60 % del borde) sí se puede")
	check(ConstructionSim.placement_block_reason(gs, "mina_carbon", inside.x, inside.y) != "", "una mina de carbón no va en un área de hierro")
	check(GameData.footprint("mina_hierro", 1) >= 9.0 and GameData.footprint("mina_hierro", 3) > GameData.footprint("mina_hierro", 1), "el centro de excavación es más grande (%.1f → %.1f m)" % [GameData.footprint("mina_hierro", 1), GameData.footprint("mina_hierro", 3)])
	check((GameData.level_def("mina_hierro", 1).get("model", []) as Array).size() > 30, "modelo nuevo del centro (galpón, castillete, malacate y carretillas)")


func _test_faces() -> void:
	_new(41)
	_set_deposits([["hierro", 70, 10, 14000]])
	var d: Dictionary = RegionSim.deposits(gs)[0]
	var c := _inside(d, PI, 0.35)
	var mine := _build_mine("mina_hierro", c.x, c.y)
	check(not mine.is_empty() and int(MineSim.state(mine)["implicit"]) == 0 and MineSim.face_count(mine) == 0, "una mina nueva empieza solo con el centro de excavación")
	var jobs_l := int(gs.level_def(mine).get("jobs", 0))
	var hired := _hire(mine, jobs_l)
	check(hired == MineSim.center_capacity(gs, mine) and hired < jobs_l, "sin frentes solo hay %d empleos de %d" % [hired, jobs_l])
	var e0 := BusinessSim.expected_output(gs, mine)
	# Frente fuera del área → bloqueado.
	var outp := Vector2(float(d["x"]), float(d["z"])) + Vector2(float(d["radius"]) * 1.3, 0)
	check(MineSim.part_block_reason(gs, mine, "tajo", outp.x, outp.y).find("DENTRO") >= 0, "un frente fuera del área se bloquea")
	check(MineSim.part_block_reason(gs, mine, "tajo", c.x + 1.0, c.y).find("superpone") >= 0, "un frente no puede ir encima del centro")
	check(MineSim.kind_reason(gs, mine, "socavon").find("nivel 2") >= 0, "el socavón exige la mina con pólvora")
	check(MineSim.kind_reason(gs, mine, "torre_extraccion").find("investigar") >= 0, "la torre de extracción exige la máquina de vapor")
	var fp := _inside(d, 0.0, 0.45)
	var money0: float = gs.money
	var err := MineSim.add_part(gs, mine, "tajo", fp.x, fp.y)
	check(err == "" and gs.money < money0, "frente a cielo abierto construido dentro del área (%s)" % (err if err != "" else Fmt.money(money0 - gs.money)))
	check(MineSim.capacity(gs, mine) == MineSim.center_capacity(gs, mine), "en obra el frente aún no suma capacidad")
	check(ConstructionSim.placement_block_reason(gs, "almacen", fp.x, fp.y).find("frente") >= 0, "no se puede construir otro edificio encima del frente")
	TimeManager.advance_days(9)
	check(str(MineSim.faces(mine)[0]["status"]) == "activo", "el frente se termina tras su tiempo de obra")
	check(MineSim.capacity(gs, mine) == jobs_l, "con un frente básico la mina tiene los %d empleos del nivel" % jobs_l)
	_hire(mine, jobs_l)
	var e1 := BusinessSim.expected_output(gs, mine)
	check(_staff(mine) == jobs_l and e1 > e0 * 2.0, "un frente aumenta la producción (%.2f → %.2f/día)" % [e0, e1])
	var ext0 := float(d["amount"])
	TimeManager.advance_days(10)
	check(float(d["amount"]) < ext0, "la mina extrae del yacimiento (%.0f unidades en 10 días)" % (ext0 - float(d["amount"])))
	# Segundo frente: más empleos; el tope por nivel impide un tercero.
	var fp2 := _inside(d, -1.3, 0.55)
	err = MineSim.add_part(gs, mine, "tajo", fp2.x, fp2.y)
	TimeManager.advance_days(9)
	check(err == "" and MineSim.jobs(gs, mine) > jobs_l, "un segundo frente suma empleos (%d)" % MineSim.jobs(gs, mine))
	check(MineSim.kind_reason(gs, mine, "tajo").find("Máximo") >= 0, "máximo de frentes por nivel")
	# Escombrera: pequeño bono.
	var y0 := MineSim.yield_mult(gs, mine)
	var sp := _inside(d, 2.2, 0.5)
	err = MineSim.add_part(gs, mine, "escombrera", sp.x, sp.y)
	TimeManager.advance_days(5)
	check(err == "" and MineSim.yield_mult(gs, mine) > y0, "la escombrera da un pequeño bono (%.2f → %.2f)" % [y0, MineSim.yield_mult(gs, mine)])
	var upkeep0 := BusinessSim.period_value(mine, "total", "mantenimiento")
	TimeManager.advance_days(1)
	check(BusinessSim.period_value(mine, "total", "mantenimiento") > upkeep0, "los frentes tienen mantenimiento diario")


func _test_depletion() -> void:
	_new(51)
	_set_deposits([["carbon", 70, 10, 15000]])
	var d: Dictionary = RegionSim.deposits(gs)[0]
	var mine := _place("mina_carbon", 72, 12)
	_hire(mine, 6)
	var full := BusinessSim.expected_output(gs, mine)
	d["amount"] = float(d["initial"]) * 0.15
	var low := BusinessSim.expected_output(gs, mine)
	check(low < full * 0.9 and low > full * 0.4, "con poca reserva rinde menos (%.1f → %.1f/día)" % [full, low])
	gs.notifications_log.clear()
	d["amount"] = float(d["initial"]) * 0.2 + 1.0
	TimeManager.advance_days(1)
	check(gs.notifications_log.any(func(n): return str(n["text"]).find("20 %") >= 0), "aviso cuando la reserva baja del 20 %")
	d["amount"] = 3.0
	TimeManager.advance_days(3)
	check(float(d["amount"]) <= 0.0, "la reserva total es finita y se agota")
	check(str(mine["status"]) == "cerrado" and _staff(mine) == 0, "al agotarse la mina cierra y despide al personal")
	check(gs.notifications_log.any(func(n): return str(n["text"]).find("cerró") >= 0), "aviso de cierre por agotamiento")


func _test_migration() -> void:
	# Partida vieja: yacimiento puntual y mina sin datos de frentes, a 8 m del punto.
	_new(61)
	_set_deposits([["hierro", 70, 10, 14000]])
	var old := _place("mina_hierro", 76, 15)
	old.erase("mine")
	var data = JSON.parse_string(JSON.stringify(gs.to_dict()))
	for dd in data["logistics"]["deposits"]:
		for k in ["radius", "shape", "grade"]:
			dd.erase(k)
	for bd in data["buildings"]:
		bd.erase("mine")
	gs.load_dict(data)
	var mine: Dictionary = gs.get_building(int(old["id"]))
	var d: Dictionary = RegionSim.deposits(gs)[0]
	check(d.has("radius") and float(d["x"]) == 70.0, "al cargar, el yacimiento viejo pasa a área en el mismo punto")
	check(int(MineSim.state(mine)["implicit"]) == 1 and MineSim.capacity(gs, mine) == int(gs.level_def(mine).get("jobs", 0)), "la mina vieja queda con 1 frente implícito y todos sus empleos")
	check(not RegionSim.deposit_for(gs, mine).is_empty(), "la mina vieja sigue sobre su yacimiento")
	check(_hire(mine, 6) == 6, "se contratan sus 6 mineros como antes")
	var legacy := 0.0
	for c in gs.employees_of(int(mine["id"])):
		legacy += BusinessSim.productivity(c, "mineria")
	legacy *= float(gs.level_def(mine)["prod_per_worker"]) * RegionSim.region_mult(gs, mine) * TechSim.mult(gs, "production", "hierro")
	check(is_equal_approx(BusinessSim.expected_output(gs, mine), legacy), "produce lo mismo que antes de las minas por partes (%.2f/día)" % legacy)
	# Una mina colocada con la regla vieja (a menos de 11 m del punto) sigue funcionando aunque quede en el borde.
	_set_deposits([["oro", 70, -40, 900]])
	var edge := _place("mina_oro", 80.5, -40)
	check(not RegionSim.deposit_for(gs, edge).is_empty(), "tolerancia: minas viejas a ≤ 11 m del punto conservan su yacimiento")


func _test_save_load() -> void:
	_new(71)
	_set_deposits([["hierro", 70, 10, 14000]])
	var d: Dictionary = RegionSim.deposits(gs)[0]
	var c := _inside(d, PI, 0.35)
	var mine := _build_mine("mina_hierro", c.x, c.y)
	var fp := _inside(d, 0.0, 0.45)
	MineSim.add_part(gs, mine, "tajo", fp.x, fp.y)
	TimeManager.advance_days(9)
	var sp := _inside(d, 2.2, 0.5)
	MineSim.add_part(gs, mine, "escombrera", sp.x, sp.y)
	var cap := MineSim.capacity(gs, mine)
	var radius := float(d["radius"])
	var data = JSON.parse_string(JSON.stringify(gs.to_dict()))
	gs.load_dict(data)
	var m2: Dictionary = gs.get_building(int(mine["id"]))
	var d2: Dictionary = RegionSim.deposits(gs)[0]
	check(MineSim.parts(m2).size() == 2 and MineSim.capacity(gs, m2) == cap, "frentes y escombrera se guardan (capacidad %d)" % cap)
	check(is_equal_approx(float(d2["radius"]), radius) and (d2["shape"] as Array).size() == 12, "el área del yacimiento se guarda")
	check(str(MineSim.extras(m2)[0]["status"]) == "obra" and int(MineSim.state(m2)["implicit"]) == 0, "la obra en curso y la mina sin frentes implícitos se conservan")
	TimeManager.advance_days(5)
	check(str(MineSim.extras(m2)[0]["status"]) == "activo", "tras cargar, la obra de la escombrera termina")
	var err := MineSim.add_part(gs, m2, "tajo", _inside(d2, -1.3, 0.55).x, _inside(d2, -1.3, 0.55).y)
	check(err == "" and int(MineSim.state(m2)["next_part"]) == 4, "tras cargar se pueden agregar frentes (ids continúan)")


## Pestaña "Mina", áreas 3D y fantasma verde/rojo del modo de colocación.
func _test_ui() -> void:
	_new(81)
	_set_deposits([["hierro", 70, 10, 14000], ["petroleo", -70, 60, 25000]])
	var d: Dictionary = RegionSim.deposits(gs)[0]
	var c := _inside(d, PI, 0.35)
	var mine := _build_mine("mina_hierro", c.x, c.y)
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	var vis: MiningVisuals = MiningVisuals.instance
	check(vis != null and vis._areas.size() == 2, "áreas 3D de los yacimientos (%d)" % (vis._areas.size() if vis else 0))
	check(vis._deco_root.get_child_count() > 5, "rocas y afloramientos sobre el área (%d)" % vis._deco_root.get_child_count())
	check(str(vis._areas[1]["label"].text).find("Reserva") >= 0, "cartel con nombre y reserva: %s" % str(vis._areas[1]["label"].text).replace("\n", " / "))
	var hud: Hud = world.hud
	hud.open_building(int(mine["id"]))
	await get_tree().process_frame
	var tabs: TabContainer = hud.building_panel.tabs
	var found := -1
	for i in range(tabs.get_tab_count()):
		if tabs.get_tab_title(i) == "Mina":
			found = i
	check(found >= 0, "el panel de la mina tiene la pestaña Mina")
	if found >= 0:
		tabs.current_tab = found
		await get_tree().process_frame
		var txt := MineTab.text(gs, mine)
		check(txt.find("Reserva") >= 0 and txt.find("Ley") >= 0 and txt.find("Frentes") >= 0 and txt.find("Producción") >= 0, "la pestaña muestra reserva, ley, frentes y producción")
	vis.start_part_placement(int(mine["id"]), "tajo")
	check(vis.part_mode and vis._ghost != null, "botón Agregar frente → modo de colocación")
	var ins := _inside(d, 0.0, 0.45)
	vis.set_ghost_at(ins.x, ins.y)
	check(vis.ghost_ok() and (vis._ghost.get_child(0) as MeshInstance3D).material_override == MeshLib.ghost_mat(true), "fantasma verde dentro del área")
	vis._process(0.0)
	check(float((vis._areas[1]["mat"] as ShaderMaterial).get_shader_parameter("highlight")) > 0.5, "el área del yacimiento se resalta al colocar")
	var outp := Vector2(float(d["x"]), float(d["z"])) + Vector2(float(d["radius"]) * 1.3, 0)
	vis.set_ghost_at(outp.x, outp.y)
	check(not vis.ghost_ok() and (vis._ghost.get_child(0) as MeshInstance3D).material_override == MeshLib.ghost_mat(false), "fantasma rojo fuera del área")
	vis.set_ghost_at(ins.x, ins.y)
	check(vis.confirm_part() == "" and MineSim.faces(mine).size() == 1, "clic confirma el frente")
	vis.cancel_part_placement()
	vis.rebuild_parts()
	check(vis._parts_root.get_child_count() >= 2, "frente dibujado y unido al centro")
	check(vis.placement_text("mina_hierro", Vector3(c.x, 0, c.y)).find("reserva") >= 0, "pista de colocación del centro con la reserva")
	world.queue_free()
	await get_tree().process_frame
	ui_done = true
