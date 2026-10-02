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
	_test_rules()
	_test_debt_and_bankruptcy()
	_test_negotiation()
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


# --- Reglas: herencia NPC, hacinamiento inicial, contratar en cerrados, dinastía ---------------

func _test_rules() -> void:
	var gs = GameState
	gs.new_game({"seed": 5, "difficulty": "normal"})
	var occ := PopulationSim.home_occupancy(gs)
	var crowded := 0
	for b in gs.buildings:
		if Housing.is_home(b) and int(occ.get(int(b["id"]), 0)) > gs.building_capacity(b):
			crowded += 1
	check(crowded == 0, "sin hacinamiento el día 1 (casas sobre su capacidad: %d)" % crowded)
	check(NpcBusinessSim.npc_buildings(gs).size() >= 2, "el pueblo empieza con artesanos NPC (%d talleres)" % NpcBusinessSim.npc_buildings(gs).size())
	# Herencia NPC: el dinero va al cónyuge y el total no cambia.
	var dead: Citizen = null
	for c in gs.citizens.values():
		if not gs.is_player(c.id) and c.spouse_id >= 0 and gs.citizens.has(c.spouse_id) and not gs.is_player(c.spouse_id) and BankSim.citizen_loan(gs, c.id).is_empty():
			dead = c
			break
	var spouse: Citizen = gs.citizens[dead.spouse_id]
	dead.money = 123.0
	var before: float = spouse.money
	var t0 := FlowSim.conserved_total(gs)
	PopulationSim.die(gs, dead, "prueba")
	check(absf(spouse.money - before - 123.0) < 0.01, "el dinero del NPC muerto pasa a su cónyuge")
	check(absf(FlowSim.conserved_total(gs) - t0) < 0.01, "la herencia NPC no crea ni destruye dinero")
	# Sin herederos: al tesoro.
	var lone: Citizen = PopulationSim.create_citizen(gs, "M", 40, "Solo")
	lone.money = 50.0
	var tr := float(gs.government["treasury"])
	PopulationSim.die(gs, lone, "prueba")
	check(absf(float(gs.government["treasury"]) - tr - 50.0) < 0.01, "sin herederos, el dinero va al tesoro")
	# Contratar en un negocio cerrado.
	var farm: Dictionary = ConstructionSim.make_building(gs, "granja", 1, 60.0, 60.0, 0.0, "jugador")
	gs.add_building(farm)
	farm["status"] = "cerrado"
	var cand: Array = BusinessSim.candidates(gs, farm)
	check(not cand.is_empty() and BusinessSim.hire(gs, farm, cand[0], 3.0) != "", "no se puede contratar en un negocio cerrado")
	# Dinastía: sin hijos, sigue el cónyuge.
	var p: Citizen = gs.player_citizen()
	var wife: Citizen = PopulationSim.create_citizen(gs, "F" if p.gender == "M" else "M", 24, "Prueba")
	PopulationSim.marry(p, wife)
	p.children_ids = []
	PopulationSim.die(gs, p, "prueba")
	check(gs.running and gs.player_id == wife.id, "sin hijos, la dinastía continúa con el cónyuge")
	var ext := PlayerSim.extended_heir(gs, PopulationSim.create_citizen(gs, "M", 30, "Nadie"))
	check(ext.get("citizen") != null, "sin familia, la dinastía continúa con un adoptado (%s)" % str(ext.get("how", "")))


# --- Deuda: sobregiro, embargo por liquidez y bancarrota con cierre ---------------------------

func _test_debt_and_bankruptcy() -> void:
	var gs = GameState
	gs.new_game({"seed": 9, "difficulty": "normal"})
	var shop: Dictionary = ConstructionSim.make_building(gs, "granja", 1, 70.0, -70.0, 0.0, "jugador")
	BusinessSim.ledger_add(shop, "obras", 500.0)   # Lo invertido le da valor.
	gs.add_building(shop)
	var house: Dictionary = ConstructionSim.make_building(gs, "vivienda", 1, -70.0, 70.0, 0.0, "jugador")
	gs.add_building(house)
	var assets := CreditSim.seizable_assets(gs)
	check(assets.size() >= 2 and int(assets[0]["id"]) == int(shop["id"]), "embargo por liquidez: el negocio va antes que la vivienda")
	gs.money = -20000.0
	check(CreditSim.bar_warning(gs) != "", "aviso visible en la barra con saldo en rojo: '%s'" % CreditSim.bar_warning(gs))
	var seized := false
	var bankrupt := false
	var min_after := INF
	for m in range(12):
		TimeManager.advance_days(30)
		if str(shop.get("owner", "")) != "jugador":
			seized = true
		if gs.player.get("bankruptcy") is Dictionary:
			bankrupt = true
		elif CreditSim.in_bankruptcy(gs):
			min_after = minf(min_after, gs.money)
	check(seized, "tras la mora, el banco embargó bienes reales")
	check(bankrupt, "sin bienes suficientes, se declaró la bancarrota personal (con opción de rescate)")
	check(CreditSim.in_bankruptcy(gs), "sin rescate, el banco castigó la deuda y cerró la quiebra")
	check(min_after >= -CreditSim.overdraft_limit(gs) - 1.0, "después, el saldo nunca pasa del tope de sobregiro (mínimo %.0f, tope %.0f)" % [min_after, CreditSim.overdraft_limit(gs)])
	check(CreditSim.score(gs, "jugador") < 500.0, "el historial crediticio refleja la bancarrota (%d)" % int(CreditSim.score(gs, "jugador")))
	check(BankSim.credit_limit(gs) <= 0.0, "tras la quiebra personal no hay crédito")
	var notes: Array = gs.notifications_log.filter(func(e): return "nada (no tienes bienes)" in str(e["text"]))
	check(notes.is_empty(), "no hay embargos 'sin bienes' en bucle")
	# Rescate: préstamo de emergencia.
	gs.new_game({"seed": 9, "difficulty": "normal"})
	gs.money = -800.0
	check(CreditSim.emergency_loan(gs) == "" and gs.money >= 0.0, "el préstamo de emergencia cubre el saldo en rojo")


func _test_negotiation() -> void:
	var gs = GameState
	gs.new_game({"seed": 4, "difficulty": "normal"})
	var t0 := FlowSim.conserved_total(gs)
	check(BankSim.request_player_loan(gs, 1000.0, 24) == "", "préstamo del banco externo")
	check(absf(FlowSim.conserved_total(gs) - t0) < 0.01, "el préstamo sale de la caja de los bancos (no crea dinero)")
	var l: Dictionary = BankSim.player_loans(gs)[0]
	l["missed"] = 1
	var term := int(l["term_months"])
	check(str(CreditSim.options_for(gs, l)["plazo"]) == "", "en mora se puede negociar el plazo")
	check(CreditSim.negotiate(gs, int(l["id"]), "plazo") == "" and int(l["term_months"]) > term and int(l["missed"]) == 0, "el banco reestructura el plazo y saca de la mora")
	check(CreditSim.negotiate(gs, int(l["id"]), "plazo") != "", "no se reestructura dos veces seguidas")
	l["missed"] = 2
	var t1 := FlowSim.conserved_total(gs)
	check(CreditSim.negotiate(gs, int(l["id"]), "quita") == "" and BankSim.player_loans(gs).is_empty(), "rebaja por pago inmediato: se cancela la deuda")
	check(absf(FlowSim.conserved_total(gs) - t1) < 0.01, "la rebaja la pierde el banco, sin crear dinero")


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
			var tb := FlowSim.conserved_total(gs)
			_bot(gs, m)
			if absf(FlowSim.conserved_total(gs) - tb) > 0.01:
				leaks["bot mes %d" % m] = FlowSim.conserved_total(gs) - tb
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
	if step_mode or not leaks.is_empty():
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
