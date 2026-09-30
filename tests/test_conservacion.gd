extends Node
## Conservación del dinero por bolsillos (FlowSim.pockets): jugador (banco + efectivo), ciudadanos,
## empresas NPC, reservas (fundaciones), tesoro, tesoros municipales, pueblos vecinos, bancos, bolsa,
## aseguradoras y la cuenta externa gs.economy["external"].
## Cada mes: total de bolsillos + saldo externo = constante (tolerancia por redondeo).
##   godot --headless res://tests/test_conservacion.tscn
##   godot --headless res://tests/test_conservacion.tscn -- --pasos   (atribuye cada fuga al sistema del día)

var failures := 0
var step_mode := false
var leaks := {}          # sistema -> dinero creado (+) o destruido (−) sin registro


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func _ready() -> void:
	step_mode = OS.get_cmdline_user_args().has("--pasos")
	print("== Dinastía: conservación del dinero por bolsillos ==")
	_test_flow_accounts()
	_run_game(7, "normal", 5, true)
	_run_game(11, "dificil", 2, false)
	print("== %s (%d fallos) ==" % ["TODO OK" if failures == 0 else "CON FALLOS", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _test_flow_accounts() -> void:
	var gs = GameState
	gs.new_game({"seed": 3, "difficulty": "normal"})
	var t0 := FlowSim.conserved_total(gs)
	gs.money -= 100.0
	FlowSim.external_out(gs, 100.0, "importación")
	check(absf(FlowSim.conserved_total(gs) - t0) < 0.001, "una importación registrada no cambia el total conservado")
	gs.money -= 50.0
	FlowSim.spend(gs, 50.0, "mantenimiento")
	check(absf(FlowSim.conserved_total(gs) - t0) < 0.001, "un gasto con destino (proveedores + importación) no cambia el total")
	check(float(gs.economy["external"]["out"].get("importación", 0.0)) >= 100.0, "la cuenta externa guarda el motivo")


# --- Partida larga con jugador activo -----------------------------------------------------------

func _run_game(seed_value: int, difficulty: String, years: int, active: bool) -> void:
	var gs = GameState
	gs.new_game({"seed": seed_value, "difficulty": difficulty})
	leaks = {}
	var start := FlowSim.conserved_total(gs)
	var worst := 0.0
	var worst_month := ""
	var months := years * 12
	var ext_start: float = FlowSim.external_balance(gs)
	for m in range(months):
		if not gs.running:
			break
		if active:
			_bot(gs, m)
		var before := FlowSim.conserved_total(gs)
		for d in range(30):
			if not gs.running:
				break
			if step_mode:
				_step_day(gs)
			else:
				TimeManager.advance_days(1)
		var after := FlowSim.conserved_total(gs)
		var scale := maxf(1000.0, absf(float(FlowSim.pockets(gs)["total"])))
		var diff := after - before
		if absf(diff) > absf(worst):
			worst = diff
			worst_month = "%d/%d" % [m % 12 + 1, TimeManager.year()]
		if absf(diff) > scale * 0.0005 + 1.0 and not step_mode:
			print("    mes %d: el total cambió %.2f sin flujo registrado" % [m, diff])
	var p: Dictionary = FlowSim.pockets(gs)
	var drift := FlowSim.conserved_total(gs) - start
	print("    semilla %d (%s, %s): %d meses · bolsillos %s · externo %+.0f · deriva %.2f (peor mes %s: %.2f)" % [
		seed_value, difficulty, "activo" if active else "pasivo", months, _fmt_pockets(p),
		FlowSim.external_balance(gs) - ext_start, drift, worst_month, worst])
	if step_mode:
		var keys := leaks.keys()
		keys.sort_custom(func(a, b): return absf(float(leaks[a])) > absf(float(leaks[b])))
		for k in keys:
			if absf(float(leaks[k])) > 0.01:
				print("      fuga %-28s %+.2f" % [k, float(leaks[k])])
	var tol := 5.0   # Solo redondeo: una fuga real de cualquier sistema supera esto en pocos meses.
	check(absf(drift) <= tol, "semilla %d: el total (bolsillos + externo) se conserva en %d años (deriva %.2f, tolerancia %.2f)" % [seed_value, years, drift, tol])
	check(gs.economy.has("external"), "semilla %d: existe la cuenta externa con motivos" % seed_value)


func _fmt_pockets(p: Dictionary) -> String:
	var parts := []
	for k in ["player", "citizens", "npc_firms", "reserves", "treasury", "municipal", "towns", "banks", "stock", "insurers"]:
		if absf(float(p.get(k, 0.0))) >= 1.0:
			parts.append("%s %.0f" % [k, float(p[k])])
	return ", ".join(parts)


# --- Bot: construye, contrata, pide crédito, investiga y demuele ---------------------------------

const BOT_BIZ := ["granja", "aguatero", "lenador", "taberna", "panaderia"]


func _bot(gs, m: int) -> void:
	if m == 0 or m == 14 or m == 30:
		for t in BOT_BIZ.slice(0, 3 if m == 0 else 2):
			_build(gs, t if m == 0 else BOT_BIZ[3 + (m / 16) % 2])
	if m == 2 or m == 20:
		_build(gs, "vivienda")
	if m == 5:
		BankSim.request_player_loan(gs, 1500.0, 24)
	if m == 8:
		for id in GameData.technologies:
			if GameData.technologies[id] is Dictionary and TechSim.set_current(gs, str(id)) == "":
				break
	if m == 40:
		for b in gs.buildings.duplicate():
			if gs.owned_by_player(b) and str(b["type"]) == "vivienda" and gs.residents_of(int(b["id"])).is_empty():
				ConstructionSim.demolish(gs, b)
				break
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


# --- Modo --pasos: día sistema por sistema (mismo orden que GameState.simulate_country_day) ------

func _step_day(gs) -> void:
	TimeManager.total_hours += 24
	var new_month: bool = TimeManager.month_day()[1] == 1
	CountriesSim.day_begin(gs)
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
	if new_month:
		steps.append_array([
			["m:RealEstateSim", func(): RealEstateSim.monthly(gs)], ["m:GridSim", func(): GridSim.monthly(gs)],
			["m:MarketSim.housing", func(): MarketSim.monthly_housing(gs)], ["m:BankSim", func(): BankSim.monthly(gs)],
			["m:EducationSim", func(): EducationSim.monthly(gs)], ["m:BusinessSim", func(): BusinessSim.monthly(gs)],
			["m:GovSim", func(): GovSim.monthly(gs)], ["m:MapSim", func(): MapSim.monthly(gs)],
			["m:FreeMarketSim", func(): FreeMarketSim.monthly(gs)], ["m:LaborSim", func(): LaborSim.monthly(gs)],
			["m:HiringSim", func(): HiringSim.monthly(gs)], ["m:PollutionSim", func(): PollutionSim.monthly(gs)],
			["m:EventsSim", func(): EventsSim.monthly(gs)], ["m:ClimateSim", func(): ClimateSim.monthly(gs)],
			["m:WarSim", func(): WarSim.monthly(gs)], ["m:LogisticsSim", func(): LogisticsSim.monthly(gs)],
			["m:TradeSim", func(): TradeSim.monthly(gs)], ["m:TransitSim", func(): TransitSim.monthly(gs)],
			["m:TourismSim", func(): TourismSim.monthly(gs)], ["m:AdvertisingSim", func(): AdvertisingSim.monthly(gs)],
			["m:EconomySim", func(): EconomySim.monthly(gs)], ["m:GlobalEconSim", func(): GlobalEconSim.monthly(gs)],
			["m:PlayerSim", func(): PlayerSim.monthly(gs)], ["m:MoneySim", func(): MoneySim.monthly(gs)],
			["m:record", func(): gs._record_month()],
		])
	for st in steps:
		if not gs.running:
			break
		var t0 := FlowSim.conserved_total(gs)
		st[1].call()
		var d := FlowSim.conserved_total(gs) - t0
		if absf(d) > 0.0001:
			leaks[st[0]] = float(leaks.get(st[0], 0.0)) + d
	var t1 := FlowSim.conserved_total(gs)
	CountriesSim.day_end(gs, new_month)
	var d2 := FlowSim.conserved_total(gs) - t1
	if absf(d2) > 0.0001:
		leaks["CountriesSim.day_end"] = float(leaks.get("CountriesSim.day_end", 0.0)) + d2
