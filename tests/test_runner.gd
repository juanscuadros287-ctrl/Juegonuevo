extends Node
## Pruebas sin interfaz: godot --headless res://tests/test_runner.tscn

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func _ready() -> void:
	print("== Dinastía: pruebas Fase 1 ==")
	_test_new_game()
	_test_simulation()
	_test_save_load()
	_test_terrain()
	_test_jump()
	print("== %s (%d fallos) ==" % ["TODO OK" if failures == 0 else "CON FALLOS", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _test_new_game() -> void:
	for d in GameData.difficulties:
		GameState.new_game({"difficulty": d, "seed": 42})
		var expected := int(GameData.difficulty(d)["start_citizens"])
		check(GameState.citizens.size() == expected, "%s: %d ciudadanos iniciales" % [d, expected])
		check(is_equal_approx(GameState.money, float(GameData.difficulty(d)["start_money"])), "%s: dinero inicial" % d)
	var homeless := 0
	for c in GameState.citizens.values():
		if c.home_id < 0:
			homeless += 1
	check(homeless == 0, "todos los ciudadanos iniciales tienen vivienda")
	check(TimeManager.year() == 1700 and TimeManager.month() == 3, "fecha inicial 1 de marzo de 1700: " + TimeManager.date_string())


func _test_simulation() -> void:
	GameState.new_game({"difficulty": "normal", "seed": 7})
	var start_pop := GameState.citizens.size()
	TimeManager.advance_days(365 * 30)
	var births := 0
	var deaths := 0
	for h in GameState.history:
		births += int(h["births"])
		deaths += int(h["deaths"])
	print("    30 años: población %d -> %d, nacimientos %d, muertes %d, felicidad %.1f, salud %.1f, año %d" % [
			start_pop, GameState.citizens.size(), births, deaths, GameState.avg_happiness(), GameState.avg_health(), TimeManager.year()])
	check(TimeManager.year() >= 1729, "el tiempo avanza 30 años")
	check(births > 0, "hay nacimientos")
	check(deaths > 0, "hay muertes")
	check(GameState.history.size() >= 359, "historial mensual registrado")
	var bad := 0
	for c in GameState.citizens.values():
		if c.health < 0 or c.health > 100 or c.happiness < 0 or c.happiness > 100 or is_nan(c.money):
			bad += 1
	check(bad == 0, "valores de ciudadanos dentro de rango")


func _test_save_load() -> void:
	GameState.new_game({"difficulty": "normal", "seed": 99, "town_name": "Prueba"})
	TimeManager.advance_days(400)
	var pop := GameState.citizens.size()
	var money := GameState.money
	var hours := TimeManager.total_hours
	var snapshot := JSON.stringify(GameState.to_dict())
	check(SaveManager.save_game("test_fase1"), "guardar partida")
	TimeManager.advance_days(200)
	check(SaveManager.load_game("test_fase1"), "cargar partida")
	check(GameState.citizens.size() == pop, "población restaurada")
	check(is_equal_approx(GameState.money, money), "dinero restaurado")
	check(TimeManager.total_hours == hours, "fecha restaurada")
	check(JSON.stringify(GameState.to_dict()) == snapshot, "estado idéntico tras cargar")
	# Determinismo: la misma semilla y estado producen el mismo futuro.
	TimeManager.advance_days(365)
	var a := JSON.stringify(GameState.to_dict())
	SaveManager.load_game("test_fase1")
	TimeManager.advance_days(365)
	check(JSON.stringify(GameState.to_dict()) == a, "simulación determinista tras cargar")
	check(SaveManager.list_saves().any(func(s): return s["slot"] == "test_fase1"), "partida listada")
	SaveManager.delete_save("test_fase1")


func _test_terrain() -> void:
	for m in GameData.map_types:
		GameState.new_game({"map_type": m, "seed": 1234})
		var t := Terrain.new()
		add_child(t)
		t.generate(m, 1234)
		t.build_mesh()
		t.scatter_nature(1234)
		var town_ok := t.is_land(0, 0, 1.0)
		for b in GameState.buildings:
			town_ok = town_ok and t.is_land(float(b["x"]), float(b["z"]), 1.0)
		var water := 0
		var total := 0
		for j in range(0, 400, 8):
			for i in range(0, 400, 8):
				total += 1
				if not t.is_land(i - 200.0, j - 200.0, 0.0):
					water += 1
		print("    mapa %s: agua %d%%, árboles %d" % [m, 100 * water / total, t.tree_positions.size()])
		check(town_ok, "mapa %s: pueblo y viviendas sobre tierra" % m)
		if m in ["costa", "rio"]:
			check(water > 0, "mapa %s tiene agua" % m)
		t.queue_free()


func _test_jump() -> void:
	GameState.new_game({"seed": 5})
	var reports := []
	EventBus.jump_finished.connect(func(r): reports.append(r))
	TimeManager.start_jump(2)
	check(TimeManager.jumping, "salto iniciado")
	var guard := 0
	while TimeManager.jumping and guard < 10000:
		TimeManager._process_jump()
		guard += 1
	check(reports.size() == 1, "reporte del salto generado")
	if reports.size() == 1:
		check(reports[0]["start_date"] != reports[0]["end_date"], "reporte con fechas: %s -> %s" % [reports[0]["start_date"], reports[0]["end_date"]])
	check(TimeManager.year() >= 1702, "salto de 2 años aplicado")
	GameState.running = false
