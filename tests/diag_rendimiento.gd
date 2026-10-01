extends Node
## Diagnóstico de rendimiento con un pueblo grande (~600 hab., ~275 edificios):
##   godot --headless res://tests/diag_rendimiento.tscn
## Mide el costo de PopulationSim.daily y del día completo (ms). No es una prueba: solo imprime.

const BIZ := ["granja", "aguatero", "lenador", "panaderia", "tienda", "taberna", "aserradero", "cantera", "pescaderia"]


func _ready() -> void:
	var gs = GameState
	_build_town(gs)
	TimeManager.advance_days(3)   # calienta cachés
	var reps := 5
	var t0 := Time.get_ticks_usec()
	for i in range(reps):
		MarketSim.begin_day(gs)
		PopulationSim.daily(gs)
	var pop_ms := (Time.get_ticks_usec() - t0) / 1000.0 / reps
	t0 = Time.get_ticks_usec()
	var days := 10
	TimeManager.advance_days(days)
	var day_ms := (Time.get_ticks_usec() - t0) / 1000.0 / days
	print("PopulationSim.daily: %.1f ms · día completo: %.1f ms (promedio de %d días, %d hab.)" % [pop_ms, day_ms, days, gs.citizens.size()])
	_per_system(gs)
	get_tree().quit()


## Pueblo grande: 600 habitantes y 275 edificios (negocios del jugador con 2 empleados y obras públicas).
func _build_town(gs) -> void:
	gs.new_game({"seed": 13, "difficulty": "normal"})
	gs.money = 500000.0
	PopulationSim.generate_initial(gs, 600)
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	var n_biz := 0
	var n_gov := 0
	# Mismo pueblo en cualquier versión: 84 negocios del jugador y 12 obras públicas (+ chozas y talleres NPC).
	while n_biz < 84 or n_gov < 12:
		var ang := rng.randf() * TAU
		var r := rng.randf_range(20.0, 120.0)
		var owner := "jugador"
		var t: String = BIZ[rng.randi() % BIZ.size()]
		if n_gov < 12 and (rng.randf() < 0.1 or n_biz >= 84):
			t = ["plaza_empedrada", "iglesia", "acueducto_publico"][n_gov % 3]
			owner = "gobierno"
			n_gov += 1
		else:
			n_biz += 1
		var b: Dictionary = ConstructionSim.make_building(gs, t, 1, cos(ang) * r, sin(ang) * r, 0.0, owner)
		gs.add_building(b)
	# Emplea a parte de la población en los negocios.
	var free: Array = []
	for c in gs.citizens.values():
		if c.age_years(gs.today()) >= 16 and not gs.is_player(c.id):
			free.append(c)
	for b in gs.buildings:
		if str(b["owner"]) != "jugador":
			continue
		for i in range(2):
			if free.is_empty():
				break
			var c: Citizen = free.pop_back()
			c.job_id = int(b["id"])
			c.job_kind = "empleo"
			c.wage = 2.0
	print("pueblo: %d hab., %d edificios (%d negocios, %d obras públicas)" % [gs.citizens.size(), gs.buildings.size(), n_biz, n_gov])


## Tiempo por sistema del día (mismo orden que GameState.simulate_country_day, sin lo mensual).
func _per_system(gs) -> void:
	var steps := [
		["WeatherSim", func(): WeatherSim.daily(gs)], ["EventsSim", func(): EventsSim.daily(gs)],
		["MapSim", func(): MapSim.daily(gs)], ["BusinessSim.produce", func(): BusinessSim.produce(gs)],
		["FreeMarketSim.produce", func(): FreeMarketSim.produce(gs)], ["LogisticsSim", func(): LogisticsSim.daily(gs)],
		["TradeSim", func(): TradeSim.daily(gs)], ["GlobalEconSim", func(): GlobalEconSim.daily(gs)],
		["TransitSim", func(): TransitSim.daily(gs)], ["TourismSim", func(): TourismSim.daily(gs)],
		["RealEstateSim", func(): RealEstateSim.daily(gs)], ["ConstructionSim", func(): ConstructionSim.daily(gs)],
		["MineSim", func(): MineSim.daily(gs)], ["GridSim", func(): GridSim.daily(gs)],
		["MarketSim.begin_day", func(): MarketSim.begin_day(gs)], ["WaterSim", func(): WaterSim.daily(gs)],
		["PopulationSim", func(): PopulationSim.daily(gs)], ["BusinessSim.end_day", func(): BusinessSim.end_day(gs)],
		["FreeMarketSim.daily", func(): FreeMarketSim.daily(gs)], ["TechSim.end_day", func(): TechSim.end_day(gs)],
		["LaborSim", func(): LaborSim.daily(gs)], ["HiringSim", func(): HiringSim.daily(gs)],
		["ClimateSim", func(): ClimateSim.daily(gs)], ["WarSim", func(): WarSim.daily(gs)],
		["PlayerSim", func(): PlayerSim.daily(gs)], ["MoneySim", func(): MoneySim.daily(gs)],
	]
	var t := {}
	var reps := 7
	for i in range(reps):
		for st in steps:
			var t0 := Time.get_ticks_usec()
			st[1].call()
			t[st[0]] = float(t.get(st[0], 0.0)) + (Time.get_ticks_usec() - t0) / 1000.0
	var line := "por sistema (ms/día, %d días):" % reps
	for st in steps:
		var ms: float = t[st[0]] / reps
		if ms >= 0.5:
			line += "\n  %-22s %6.1f" % [st[0], ms]
	print(line)
