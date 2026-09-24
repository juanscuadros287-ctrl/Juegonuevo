extends Node
## Niveles de almacenes y fábricas: crecen de tamaño y producción, la mejora exige
## tecnología, dinero y espacio, y el tiempo de obra sube con el nivel.
## godot --headless res://tests/test_niveles.tscn

var failures := 0
var gs = GameState


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func _ready() -> void:
	print("== Dinastía: niveles de almacenes y fábricas ==")
	gs.new_game({"seed": 77, "difficulty": "facil", "map_type": "interior"})
	for t in ["almacen", "herreria", "siderurgica"]:
		var prev_fp := 0.0
		var prev_days := 0
		var grows := true
		for lvl in range(1, GameData.max_level(t) + 1):
			var fp := GameData.footprint(t, lvl)
			var days := int(GameData.level_def(t, lvl).get("build_days", 0))
			if lvl > 1 and (fp < prev_fp or days <= prev_days):
				grows = false
			prev_fp = fp
			prev_days = days
		check(grows, "%s: tamaño y tiempo de obra crecen con el nivel (%d niveles)" % [t, GameData.max_level(t)])
	check(GameData.footprint("almacen", 4) > GameData.footprint("almacen", 1), "el almacén nivel 4 es más grande que el nivel 1")
	check(float(GameData.level_def("almacen", 2).get("warehouse_capacity", 0)) > float(GameData.level_def("almacen", 1).get("warehouse_capacity", 0)), "mejorar el almacén da más capacidad")
	check(float(GameData.level_def("herreria", 2).get("jobs", 0)) * float(GameData.level_def("herreria", 2).get("prod_per_worker", 0)) > float(GameData.level_def("herreria", 1).get("jobs", 0)) * float(GameData.level_def("herreria", 1).get("prod_per_worker", 0)), "mejorar la herrería da más producción")

	# Sin tecnología no se puede mejorar.
	var w: Dictionary = ConstructionSim.make_building(gs, "almacen", 1, 60.0, 60.0, 0.0, "jugador")
	gs.add_building(w)
	gs.money = 1e6
	var r := ConstructionSim.start_upgrade(gs, w)
	check(r != "", "sin la tecnología del nivel 2 la mejora se bloquea (%s)" % r)
	# Con tecnología: bloqueo por falta de espacio si hay un vecino pegado.
	var tech := str(GameData.level_def("almacen", 2).get("tech", ""))
	if tech != "":
		gs.techs.append(tech)
	check(ConstructionSim.level_block_reason(gs, "almacen", 2) == "", "con la tecnología el nivel 2 queda disponible")
	var fp2 := GameData.footprint("almacen", 2)
	var n: Dictionary = ConstructionSim.make_building(gs, "almacen", 1, 60.0 + (fp2 + GameData.footprint("almacen", 1)) * 0.5 + 0.5, 60.0, 0.0, "jugador")
	gs.add_building(n)
	r = ConstructionSim.start_upgrade(gs, w)
	check(r.begins_with("No hay espacio"), "un vecino pegado impide ampliar (%s)" % r)
	gs.buildings.erase(n)
	var money_before: float = gs.money
	r = ConstructionSim.start_upgrade(gs, w)
	check(r == "", "con espacio y dinero la mejora arranca (%s)" % r)
	check(gs.money < money_before, "la mejora se paga")
	check(w["status"] == "mejorando", "el edificio queda en obras")
	var d2 := ConstructionSim.days_left(gs, w)
	check(d2 > 0, "estimación de días restantes: %d" % d2)
	var days := 0
	while w["status"] == "mejorando" and days < 400:
		TimeManager.advance_days(1)
		days += 1
	check(int(w["level"]) == 2, "la mejora termina en %d días y el almacén queda en nivel 2" % days)
	check(WarehouseSim.capacity_of(gs, int(w["id"])) == float(GameData.level_def("almacen", 2)["warehouse_capacity"]), "la capacidad nueva ya cuenta")
	print("== %s (%d fallos) ==" % ["TODO OK" if failures == 0 else "CON FALLOS", failures])
	get_tree().quit(1 if failures > 0 else 0)
