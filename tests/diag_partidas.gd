extends Node
## Diagnóstico de partidas largas (no es una prueba: imprime métricas).
##   godot --headless res://tests/diag_partidas.tscn -- [años] [pasivo|activo|ambos] [semillas separadas por coma]
## Por partida: población, desempleo, felicidad, crimen, nivel de precios, tesoro, dinero del jugador y de
## los ciudadanos, empresas NPC abiertas, sin techo, hacinados, ms/día y si el jugador sigue vivo.

var years := 20
var modes := ["pasivo", "activo"]
var seeds := [7, 11, 3]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		years = int(args[0])
	if args.size() >= 2 and args[1] != "ambos":
		modes = [args[1]]
	if args.size() >= 3:
		seeds = Array(args[2].split(",")).map(func(x): return int(x))
	print("| Semilla | Modo | Años | Pobl. | Desempleo | Con empleo o negocio | Felic. | Crimen | Precios | Tesoro | Jugador | Ciudadanos | NPC abiertos | Sin techo | Hacinados | ms/día | Fin |")
	print("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
	for sd in seeds:
		for mode in modes:
			_run(int(sd), str(mode))
	get_tree().quit()


func _run(sd: int, mode: String) -> void:
	var gs = GameState
	var diff := "dificil" if sd == 11 else "normal"
	gs.new_game({"seed": sd, "difficulty": diff})
	var pop0: int = gs.citizens.size()
	var t0 := Time.get_ticks_usec()
	var days := 0
	var fin := "vivo"
	var unemp_series := []
	for m in range(years * 12):
		if not gs.running:
			fin = "murió %d" % TimeManager.year()
			break
		if mode == "activo":
			_bot(gs, m)
		TimeManager.advance_days(30)
		days += 30
		if m % 12 == 11:
			unemp_series.append(EconomySim.unemployment(gs))
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / maxf(1.0, days)
	var cit := 0.0
	var homeless := 0
	var wf := 0
	var working := 0
	for c in gs.citizens.values():
		var age: int = c.age_years(gs.today())
		if age >= 16 and age < 65 and not gs.is_player(c.id):
			wf += 1
			if c.job_id >= 0:
				working += 1
	for c in gs.citizens.values():
		cit += c.money
		if c.home_id < 0:
			homeless += 1
	var occ := PopulationSim.home_occupancy(gs)
	var crowded := 0
	for b in gs.buildings:
		if int(occ.get(int(b["id"]), 0)) > gs.building_capacity(b) and Housing.is_home(b):
			crowded += int(occ.get(int(b["id"]), 0))
	var st: Dictionary = gs.market.get("stats", {})
	var unemp_avg := 0.0
	for u in unemp_series:
		unemp_avg += float(u)
	unemp_avg /= maxf(1.0, unemp_series.size())
	print("| %d | %s | %d | %d→%d | %.0f %% (prom. %.0f %%) | %.0f %% | %.0f | %.0f | %.2f | %.0f | %.0f | %.0f | %d (quiebras %d) | %d | %d | %.1f | %s |" % [
		sd, mode, years, pop0, gs.citizens.size(), EconomySim.unemployment(gs) * 100.0, unemp_avg * 100.0, 100.0 * working / maxf(1.0, wf),
		gs.avg_happiness(), float(gs.problems.get("crime", 0.0)), gs.price_level(), float(gs.government.get("treasury", 0.0)),
		gs.money, cit, int(st.get("npc_opened", 0)), int(st.get("npc_bankrupt", 0)), homeless, crowded, ms, fin])


const BOT_BIZ := ["granja", "aguatero", "lenador", "taberna", "panaderia"]


func _bot(gs, m: int) -> void:
	if m == 0 or m == 14 or m == 30:
		for i in range(3 if m == 0 else 2):
			_build(gs, BOT_BIZ[i] if m == 0 else BOT_BIZ[3 + (m / 16 + i) % 2])
	if m == 2 or m == 20:
		_build(gs, "vivienda")
	if m == 5:
		BankSim.request_player_loan(gs, 1500.0, 24)
	for b in gs.buildings:
		if not gs.owned_by_player(b) or str(b["status"]) != "activo" or not BusinessSim.is_business(b):
			continue
		var jobs := MineSim.jobs(gs, b)
		var have := 0
		for c in gs.employees_of(int(b["id"])):
			if c.job_kind == "empleo":
				have += 1
		for c in BusinessSim.candidates(gs, b):
			if have >= jobs:
				break
			if BusinessSim.hire(gs, b, c, maxf(GovSim.min_wage(gs), BusinessSim.asked_wage(gs, c, str(b["type"])))) == "":
				have += 1


func _build(gs, type_id: String) -> void:
	var spot := NpcBusinessSim.find_spot(gs, type_id)
	if spot.is_empty():
		return
	ConstructionSim.start_construction(gs, type_id, float(spot["x"]), float(spot["z"]), float(spot["rot"]))
