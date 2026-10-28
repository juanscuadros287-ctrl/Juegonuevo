extends Node
## Misiones guía, escenarios de inicio, dificultad y logros (docs/MISIONES_ESCENARIOS.md).
##   godot --headless res://tests/test_misiones_escenarios.tscn

const PROFILE := "user://test_logros_tmp.cfg"

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func _ready() -> void:
	print("== Dinastía: misiones guía, escenarios, dificultad y logros ==")
	if FileAccess.file_exists(PROFILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE))
	ProgressSim.use_profile(PROFILE, true)
	_test_data()
	_test_normal_unchanged()
	_test_missions()
	_test_reward_external()
	_test_hide_and_save()
	_test_scenarios()
	_test_quebrada()
	_test_difficulty()
	_test_achievements()
	_test_old_saves()
	_test_simulation()
	await _test_ui()
	ProgressSim.use_profile("user://logros.cfg", false)
	if FileAccess.file_exists(PROFILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE))
	print("== %s (%d fallos) ==" % ["TODO OK" if failures == 0 else "CON FALLOS", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _biz(gs, type_id: String, x: float, z: float) -> Dictionary:
	var b: Dictionary = ConstructionSim.make_building(gs, type_id, 1, x, z, 0.0, "jugador")
	gs.add_building(b)
	return b


func _test_data() -> void:
	var n := ProgressSim.missions().size()
	check(n >= 5 and n <= 8, "entre 5 y 8 misiones guía (%d)" % n)
	check(ProgressSim.achievements().size() >= 20, "unos 20 logros (%d)" % ProgressSim.achievements().size())
	for id in ["normal", "pobre", "quebrada", "otro_pais", "industrial", "moderna"]:
		check(ScenarioSim.defs().has(id) and str(ScenarioSim.def(id).get("description", "")) != "", "escenario %s con descripción" % id)
	for id in ["facil", "normal", "dificil"]:
		check(GameData.difficulties.has(id) and GameData.difficulties[id].has("npc_aggression"), "dificultad %s con agresividad de NPC" % id)


## El escenario normal no cambia la partida: misma semilla → mismo estado que sin escenario.
func _test_normal_unchanged() -> void:
	var gs = GameState
	gs.new_game({"seed": 42, "difficulty": "normal"})
	var a := JSON.stringify(gs.citizens.size()) + str(gs.money) + str(gs.buildings.size()) + str(gs.rng.state)
	gs.new_game({"seed": 42, "difficulty": "normal", "scenario": "normal"})
	var b := JSON.stringify(gs.citizens.size()) + str(gs.money) + str(gs.buildings.size()) + str(gs.rng.state)
	check(a == b, "escenario normal = partida de siempre (mismo dinero, edificios y semilla)")
	check(str(gs.settings["scenario"]) == "normal", "settings.scenario = normal")
	check(ProgressSim.done_count(gs) == 0, "partida nueva: ninguna misión hecha")
	check(TimeManager.year() == int(GameData.game.get("start_year", 1700)), "año de inicio de siempre")


func _test_missions() -> void:
	var gs = GameState
	gs.new_game({"seed": 7, "difficulty": "normal"})
	gs.government["treasury"] = 5000.0
	var t0 := FlowSim.conserved_total(gs)
	var m0: float = gs.money
	var tr0 := float(gs.government["treasury"])
	_biz(gs, "granja", 30.0, -10.0)
	ProgressSim._check_missions(gs)
	check(ProgressSim.is_done(gs, "primera_fabrica"), "misión «primera fábrica» cumplida con un negocio activo")
	var rec: Dictionary = gs.progress["missions"]["primera_fabrica"]
	var reward := float(rec.get("reward", 0.0))
	check(reward > 0.0 and reward <= 500.0, "recompensa pequeña (%s)" % Fmt.money(reward))
	check(absf(gs.money - m0 - reward) < 0.01, "el premio llega al jugador")
	check(absf(tr0 - float(gs.government["treasury"]) - reward) < 0.01, "el premio sale del tesoro (fondo de fomento)")
	check(absf(FlowSim.conserved_total(gs) - t0) < 0.01, "conservación: el premio no crea dinero")
	check(not (gs.progress["rewards_log"] as Array).is_empty(), "la recompensa queda registrada con su origen")
	var pend := ProgressSim.pop_pending()
	check(pend.size() >= 1 and str(pend[0]["kind"]) == "mision", "aviso discreto en cola (sin toast del HUD)")
	# Otras misiones
	gs.techs.append("__prueba__")
	check(ProgressSim.mission_met(gs, "investigar"), "misión investigar: una tecnología más que al empezar")
	gs.techs.erase("__prueba__")
	check(not ProgressSim.mission_met(gs, "heredero"), "sin hijos no hay heredero")
	check(not ProgressSim.mission_met(gs, "vehiculo_ruta"), "sin vehículo ni ruta la misión sigue pendiente")
	check(not ProgressSim.mission_met(gs, "venta_mayorista"), "sin ventas mayoristas la misión sigue pendiente")
	gs.trade["totals"]["exports"] = 50.0
	check(ProgressSim.mission_met(gs, "venta_mayorista"), "un envío a un pueblo vecino cuenta como venta mayorista")
	# Una misión ya cumplida no paga dos veces.
	var m1: float = gs.money
	ProgressSim._check_missions(gs)
	var paid_again: float = gs.money - m1
	check(ProgressSim.is_done(gs, "venta_mayorista") and paid_again <= float(ProgressSim.mission_def("venta_mayorista")["reward"]) * gs.price_mult() + 0.01, "cada misión paga una sola vez")


func _test_reward_external() -> void:
	var gs = GameState
	gs.new_game({"seed": 8, "difficulty": "normal"})
	gs.government["treasury"] = 0.0
	var t0 := FlowSim.conserved_total(gs)
	_biz(gs, "granja", 30.0, -10.0)
	ProgressSim._check_missions(gs)
	var rec: Dictionary = gs.progress["missions"]["primera_fabrica"]
	check(float(rec.get("from_external", 0.0)) > 0.0, "tesoro vacío: el premio lo paga la cámara de comercio exterior")
	var ext_in: Dictionary = gs.economy["external"]["in"]
	check(float(ext_in.get("premio_mision_guia", 0.0)) > 0.0, "la cuenta externa registra el motivo «premio_mision_guia»")
	check(absf(FlowSim.conserved_total(gs) - t0) < 0.01, "conservación con premio desde el exterior")


func _test_hide_and_save() -> void:
	var gs = GameState
	gs.new_game({"seed": 9})
	ProgressSim.set_hidden(gs, true)
	ProgressSim.set_collapsed(gs, true)
	var d: Dictionary = gs.to_dict()
	gs.load_dict(JSON.parse_string(JSON.stringify(d)))
	check(bool(gs.progress["hidden"]) and bool(gs.progress["collapsed"]), "panel oculto/plegado se guarda con la partida")


func _test_scenarios() -> void:
	var gs = GameState
	var base := float(GameData.difficulty("normal")["start_money"])
	gs.new_game({"seed": 11, "scenario": "pobre"})
	check(absf(gs.money - snappedf(base * 0.15, 1.0)) < 1.0, "pobre: 15 %% del capital (%s)" % Fmt.money(gs.money))
	check(int(CreditSim.score(gs, "jugador")) == 590, "pobre: sin historial (puntaje 590)")
	var cids := MapSim.real_country_ids()
	var iso := str(cids[min(3, cids.size() - 1)]) if not cids.is_empty() else ""
	gs.new_game({"seed": 12, "scenario": "otro_pais", "country_id": iso})
	check(MapSim.country_id(gs) == iso or iso == "", "otro país: se juega en el país elegido (%s)" % iso)
	check(absf(gs.money - snappedf(base * 0.7, 1.0)) < 1.0, "otro país: 70 % de los ahorros")
	gs.new_game({"seed": 13, "scenario": "industrial"})
	check(gs.era() == 2 and TimeManager.year() == 1830, "época industrial: era 2 y año 1830 (%d, %d)" % [gs.era(), TimeManager.year()])
	var all1 := true
	for id in GameData.technologies:
		if GameData.technologies[id] is Dictionary and int(GameData.technologies[id].get("era", 1)) == 1 and not gs.techs.has(id):
			all1 = false
	check(all1, "época industrial: todas las tecnologías coloniales conocidas")
	check(TechSim.block_reason(gs, _first_tech_of_era(2)) == "" or _first_tech_of_era(2) == "", "época industrial: se puede investigar lo de la época 2")
	check(not ProgressSim.mission_met(gs, "investigar"), "las tecnologías base no cuentan para la misión investigar")
	gs.new_game({"seed": 14, "scenario": "moderna"})
	check(gs.era() == 3 and TimeManager.year() == 1950, "época moderna: era 3 y año 1950")
	var n2 := 0
	for id in GameData.technologies:
		if GameData.technologies[id] is Dictionary and int(GameData.technologies[id].get("era", 1)) == 2 and gs.techs.has(id):
			n2 += 1
	check(n2 >= 20, "época moderna: tecnologías industriales conocidas (%d)" % n2)
	var d: Dictionary = JSON.parse_string(JSON.stringify(gs.to_dict()))
	gs.load_dict(d)
	check(TimeManager.year() == 1950 and str(gs.settings["scenario"]) == "moderna", "el escenario y su año se guardan")


func _first_tech_of_era(e: int) -> String:
	for id in GameData.technologies:
		if not (GameData.technologies[id] is Dictionary):
			continue
		var t: Dictionary = GameData.technologies[id]
		if int(t.get("era", 1)) == e and (t.get("requires", []) as Array).all(func(r): return GameState.techs.has(r)):
			return str(id)
	return ""


func _test_quebrada() -> void:
	var gs = GameState
	gs.new_game({"seed": 15, "scenario": "quebrada"})
	var biz := []
	for b in gs.player_buildings():
		if bool(b.get("inherited", false)):
			biz.append(b)
	check(biz.size() == 1 and BusinessSim.is_business(biz[0]), "quebrada: hereda una empresa (%s)" % (gs.building_label(biz[0]) if not biz.is_empty() else "ninguna"))
	var l := ScenarioSim.inherited_loan(gs)
	check(not l.is_empty() and int(l["missed"]) == 2, "quebrada: deuda heredada en mora (2 cuotas)")
	check(CreditSim.player_in_arrears(gs), "CreditSim ve la mora")
	check(CreditSim.bar_warning(gs) != "", "la barra superior avisa de la mora")
	var opts := CreditSim.options_for(gs, l)
	check(str(opts.get("plazo", "x")) == "" and str(opts.get("gracia", "x")) == "" and str(opts.get("dacion", "x")) == "", "se puede negociar: plazo, gracia y dación (%s)" % str(opts))
	check(ProgressSim.is_done(gs, "primera_fabrica") and float(gs.progress["missions"]["primera_fabrica"].get("reward", -1)) == 0.0, "la empresa heredada cumple la misión sin premio")
	var t0 := FlowSim.conserved_total(gs)
	check(CreditSim.negotiate(gs, int(l["id"]), "gracia") == "", "negociar periodo de gracia con CreditSim")
	check(int(l["missed"]) == 0, "tras el acuerdo, el préstamo sale de la mora")
	for i in range(3):
		TimeManager.advance_days(30)
	var drift := absf(FlowSim.conserved_total(gs) - t0)
	check(drift < 1.0 + 0.0005 * absf(float(FlowSim.pockets(gs)["total"])), "conservación en el escenario quebrada (deriva %.3f)" % drift)


func _test_difficulty() -> void:
	var gs = GameState
	var vals := {}
	for d in ["facil", "normal", "dificil"]:
		gs.new_game({"seed": 21, "difficulty": d})
		vals[d] = {"money": gs.money, "rate": BankSim.player_rate(gs), "ev": float(gs.diff()["event_freq_mult"]), "ag": LaborSim.npc_aggression(gs)}
	check(vals["facil"]["money"] > vals["normal"]["money"] and vals["normal"]["money"] > vals["dificil"]["money"], "capital: fácil > normal > difícil")
	check(vals["facil"]["rate"] < vals["normal"]["rate"] and vals["normal"]["rate"] < vals["dificil"]["rate"], "tasas del banco: fácil < normal < difícil")
	check(vals["facil"]["ev"] < vals["normal"]["ev"] and vals["normal"]["ev"] < vals["dificil"]["ev"], "eventos negativos: fácil < normal < difícil")
	check(vals["facil"]["ag"] < 1.0 and is_equal_approx(vals["normal"]["ag"], 1.0) and vals["dificil"]["ag"] > 1.0, "agresividad de los NPC: fácil < normal (1) < difícil")


func _test_achievements() -> void:
	var gs = GameState
	gs.new_game({"seed": 31, "difficulty": "dificil"})
	ProgressSim.pop_pending()
	ProgressSim.check_achievements(gs)
	check(gs.progress["achievements"].is_empty(), "partida nueva: sin logros")
	gs.money = 2000000.0
	ProgressSim.check_achievements(gs)
	check(ProgressSim.has_achievement(gs, "primer_millon"), "logro «Primer millón» con patrimonio de 2 M")
	check(ProgressSim.has_achievement(gs, "a_pulso"), "logro «A pulso» en difícil")
	check(not ProgressSim.has_achievement(gs, "desde_abajo"), "«Desde abajo» solo en el escenario pobre")
	var pend := ProgressSim.pop_pending()
	check(pend.size() >= 3 and str(pend[0]["kind"]) == "logro", "aviso discreto por cada logro (%d)" % pend.size())
	var cf := ConfigFile.new()
	check(cf.load(PROFILE) == OK and cf.has_section_key("logros", "primer_millon"), "el logro se guarda en el perfil global")
	check(ProgressSim.profile_has("cien_mil"), "perfil: otros logros también")
	# Monopolio: 2 granjas propias y ningún productor NPC de comida.
	for b in gs.buildings:
		if NpcBusinessSim.is_npc(b) and str(gs.building_def(b).get("product", "")) == "comida":
			b["status"] = "cerrado"
	_biz(gs, "granja", 30.0, -10.0)
	_biz(gs, "granja", -30.0, 12.0)
	check(ProgressSim.monopoly_good(gs) == "comida", "monopolio de la comida detectado")
	# Diez años sin deudas.
	gs.progress["debt_free_months"] = 119
	ProgressSim._month_counters(gs, gs.progress)
	ProgressSim.check_achievements(gs)
	check(ProgressSim.has_achievement(gs, "sin_deudas"), "logro «Sin deudas» tras 120 meses")
	# Se guardan en la partida.
	var d: Dictionary = JSON.parse_string(JSON.stringify(gs.to_dict()))
	gs.load_dict(d)
	check(ProgressSim.has_achievement(gs, "primer_millon") and ProgressSim.has_achievement(gs, "monopolio"), "los logros se guardan con la partida")
	# Partida nueva: los logros de la partida empiezan en cero, el perfil los conserva.
	gs.new_game({"seed": 32})
	check(not ProgressSim.has_achievement(gs, "primer_millon") and ProgressSim.profile_has("primer_millon"), "partida nueva sin logros; el perfil global los recuerda")
	# Con el perfil desactivado (pruebas, por defecto) no se escribe.
	ProgressSim.use_profile("user://test_logros_off.cfg", false)
	gs.money = 2000000.0
	ProgressSim.check_achievements(gs)
	check(not FileAccess.file_exists("user://test_logros_off.cfg"), "sin profile_enabled no se escribe el perfil")
	ProgressSim.use_profile(PROFILE, true)
	ProgressSim.pop_pending()


func _test_old_saves() -> void:
	var gs = GameState
	gs.new_game({"seed": 41, "difficulty": "facil", "scenario": "pobre"})
	_biz(gs, "granja", 30.0, -10.0)
	var d: Dictionary = JSON.parse_string(JSON.stringify(gs.to_dict()))
	d.erase("progress")
	(d["settings"] as Dictionary).erase("scenario")
	(d["settings"] as Dictionary).erase("difficulty")
	var m0 := float(d["money"])
	gs.load_dict(d)
	check(str(gs.settings["scenario"]) == "normal" and str(gs.settings["difficulty"]) == "normal", "partida vieja: escenario y dificultad normales")
	check(ProgressSim.is_done(gs, "primera_fabrica") and absf(gs.money - m0) < 0.01, "partida vieja: lo ya cumplido cuenta sin pagar premio")
	check(ProgressSim.missions().size() == (gs.progress["missions"] as Dictionary).size(), "partida vieja: estado de misiones completo")
	# Escenario desconocido (de una versión futura) → normal.
	d["settings"]["scenario"] = "marte"
	gs.load_dict(d)
	check(str(gs.settings["scenario"]) == "normal", "escenario desconocido → normal")
	# Por el guardado real (ranura): carga y conserva el progreso.
	var dir := "user://test_misiones_slots/"
	SaveManager.use_dirs(dir, "user://test_misiones_legacy/")
	gs.new_game({"seed": 42, "scenario": "quebrada", "difficulty": "dificil"})
	SaveManager.begin_slot(1)
	check(SaveManager.save_slot(1, "prueba"), "guardar en ranura")
	var info := SaveManager.slot_info(1)
	check(str(info.get("meta", {}).get("scenario", "")) == "quebrada", "la cabecera de la ranura lleva el escenario")
	var r := SaveManager.load_slot(1)
	check(bool(r["ok"]) and str(gs.settings["scenario"]) == "quebrada" and ProgressSim.is_done(gs, "primera_fabrica"), "cargar la ranura: escenario y misiones")
	SaveManager.delete_slot(1)


func _test_simulation() -> void:
	var gs = GameState
	gs.new_game({"seed": 51, "difficulty": "normal"})
	var t0 := FlowSim.conserved_total(gs)
	_biz(gs, "granja", 30.0, -10.0)
	for i in range(4):
		TimeManager.advance_days(30)
	check(ProgressSim.is_done(gs, "primera_fabrica"), "la simulación revisa las misiones sola (cada 7 días)")
	check(gs.progress["achievements"].has("primer_negocio"), "la simulación revisa los logros cada mes")
	var drift := absf(FlowSim.conserved_total(gs) - t0)
	check(drift < 1.0 + 0.0005 * absf(float(FlowSim.pockets(gs)["total"])), "conservación con misiones y logros activos (deriva %.3f)" % drift)


func _test_ui() -> void:
	var gs = GameState
	gs.new_game({"seed": 61})
	var gp := GuidePanel.new()
	add_child(gp)
	gp.setup(null)
	check(gp.is_guide_visible(), "panel de misiones visible en partida nueva")
	gp.toggle_collapsed()
	check(not gp._list.visible, "el panel se pliega")
	gp.toggle_collapsed()
	check(gp._list.visible and gp._list.get_child_count() >= ProgressSim.missions().size(), "el panel se despliega con las misiones")
	gp.hide_guide()
	check(not gp.is_guide_visible(), "el panel se oculta del todo")
	gp.show_guide()
	check(gp.is_guide_visible(), "se vuelve a mostrar")
	gp.open_achievements()
	check(gp.achievements_open() and gp._ach_box.get_child_count() > 0, "ventana de logros")
	gp.close_achievements()
	gp.show_note({"kind": "logro", "label": "Prueba"}, 2)
	check(gp.note_text().contains("Prueba") and gp.note_text().contains("+2"), "aviso discreto agrupado")
	gp.queue_free()
	# Menú principal: escenarios con descripción y dificultad.
	var mm: MainMenu = MainMenu.new()
	mm.size = Vector2(1600, 900)
	add_child(mm)
	await get_tree().process_frame
	check(mm._scen_buttons.size() == ScenarioSim.ids().size(), "menú: un botón por escenario (%d)" % mm._scen_buttons.size())
	mm._select_scen(ScenarioSim.ids().find("quebrada"), false)
	check(mm._scen_desc.text.contains("deuda"), "menú: descripción del escenario elegido")
	mm._select_scen(ScenarioSim.ids().find("otro_pais"), true)
	check(mm.world_map != null and mm.world_map.visible, "menú: «Otro país» abre el mapa mundial para elegir el país")
	check(mm._diff_desc.text.contains("agresividad"), "menú: la dificultad describe la agresividad de los rivales")
	mm.queue_free()
	await get_tree().process_frame
