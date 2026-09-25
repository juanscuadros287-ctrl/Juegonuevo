extends Node
## Pruebas de la sección C (Dinastía y poder): talentos y educación de herederos, orden de herederos,
## matrimonio con unión de fortunas, propuestas rechazadas, cargos políticos, lobby, escándalos y guardado.
## godot --headless res://tests/test_dinastia.tscn

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func _ready() -> void:
	print("== Dinastía: sección C (herederos, política y matrimonio) ==")
	_test_talents_education()
	_test_heir_order()
	_test_marriage_merge()
	_test_proposal_rejected()
	_test_strategic_marriage()
	_test_office_bonus()
	_test_lobby_and_scandal()
	_test_factions()
	_test_save_load()
	await _test_ui()
	print("== %s (%d fallos) ==" % ["TODO OK" if failures == 0 else "CON FALLOS", failures])
	get_tree().quit(1 if failures > 0 else 0)


# --- Utilidades ----------------------------------------------------------------------------------

func _new_town(seed_v: int) -> void:
	GameState.new_game({"seed": seed_v, "difficulty": "facil"})
	GameState.money = 60000.0


func _kid(age: int) -> Citizen:
	PlayerSim.adopt_baby(GameState)
	var p := GameState.player_citizen()
	var k: Citizen = GameState.citizens[p.children_ids[-1]]
	k.birth_day = GameState.today() - age * 365 - 10
	return k


func _single_npc(gender: String) -> Citizen:
	var c := PopulationSim.create_citizen(GameState, gender, 28, PopulationSim.random_surname(GameState))
	c.home_id = -1
	return c


func _total_money() -> float:
	return EconomySim.total_money(GameState) + float(GameState.government.get("treasury", 0.0))


# --- 9. Talentos y educación ---------------------------------------------------------------------

func _test_talents_education() -> void:
	_new_town(301)
	var k := _kid(8)
	var t0 := HeirsSim.ensure_talents(GameState, k).duplicate()
	for key in HeirsSim.TALENTS:
		check(float(t0[key]) >= 0.0 and float(t0[key]) <= 100.0, "talento inicial de %s en rango (%d)" % [key, int(t0[key])])
	check(HeirsSim.set_plan(GameState, k, "universidad", "ciencia") != "" and HeirsSim.edu_of(GameState, k)["plan"] == "ninguna", "un niño de 8 años no puede ir a la universidad")
	var msg := HeirsSim.set_plan(GameState, k, "tutor", "negocios")
	check(HeirsSim.edu_of(GameState, k)["plan"] == "tutor", "tutor privado contratado: %s" % msg)
	var money0 := GameState.money
	var total0 := _total_money()
	for i in range(12):
		HeirsSim.monthly(GameState)
	var t1 := HeirsSim.talents(GameState, k)
	check(float(t1["negocios"]) > float(t0["negocios"]) + 10.0, "el tutor sube el talento elegido (negocios %d → %d)" % [int(t0["negocios"]), int(t1["negocios"])])
	check(float(t1["ciencia"]) > float(t0["ciencia"]), "y un poco los demás (ciencia %d → %d)" % [int(t0["ciencia"]), int(t1["ciencia"])])
	check(GameState.money < money0, "la educación se paga (%s)" % Fmt.money(money0 - GameState.money))
	check(absf(_total_money() - total0) < 0.01, "la cuota del tutor queda en el pueblo (economía cerrada)")
	# Universidad y extranjero según edad, estudios y época.
	var y := _kid(19)
	y.education = 1
	check(HeirsSim.set_plan(GameState, y, "extranjero", "ciencia") != "" and HeirsSim.edu_of(GameState, y)["plan"] == "ninguna", "carrera en el extranjero solo en épocas posteriores")
	HeirsSim.set_plan(GameState, y, "universidad", "ciencia")
	var s0 := HeirsSim.talent(GameState, y, "ciencia")
	for i in range(6):
		HeirsSim.monthly(GameState)
	check(HeirsSim.talent(GameState, y, "ciencia") > s0 + 5.0, "la universidad sube ciencia (%d → %d)" % [int(s0), int(HeirsSim.talent(GameState, y, "ciencia"))])
	GameState.research["era"] = 2
	check(HeirsSim.plan_block_reason(GameState, y, "extranjero") == "", "en la época industrial se puede estudiar en el extranjero")
	# Bonos moderados del jefe de familia según sus talentos.
	var p := GameState.player_citizen()
	var pt := HeirsSim.ensure_talents(GameState, p)
	pt["ciencia"] = 100.0
	pt["negocios"] = 100.0
	pt["politica"] = 100.0
	check(is_equal_approx(HeirsSim.research_mult(GameState), 1.1), "ciencia 100: +10%% de investigación (moderado)")
	check(HeirsSim.upkeep_discount(GameState) > 0.05 and HeirsSim.upkeep_discount(GameState) <= 0.1, "negocios: descuento moderado de mantenimiento")
	check(TechSim.mult(GameState, "research") >= 1.1, "el bono de ciencia llega a la investigación")
	pt["ciencia"] = 20.0
	check(is_equal_approx(HeirsSim.research_mult(GameState), 1.0), "con talento bajo no hay bono")


# --- 11. Orden de herederos ----------------------------------------------------------------------

func _test_heir_order() -> void:
	_new_town(302)
	var a := _kid(30)
	var b := _kid(25)
	var c := _kid(20)
	check(HeirsSim.add_heir(GameState, c.id).contains("n.º 1"), "el menor es el heredero n.º 1")
	HeirsSim.add_heir(GameState, a.id)
	HeirsSim.add_heir(GameState, b.id)
	HeirsSim.move_heir(GameState, b.id, -1)
	check(HeirsSim.heir_order(GameState) == [c.id, b.id, a.id], "subir y bajar en la lista")
	check(HeirsSim.add_heir(GameState, _single_npc("M").id) != "" and HeirsSim.heir_order(GameState).size() == 3, "un extraño no puede ser heredero")
	# El primero de la lista muere antes: hereda el segundo (no el mayor).
	PopulationSim.die(GameState, c, "prueba")
	PopulationSim.die(GameState, GameState.player_citizen(), "prueba")
	check(GameState.running and GameState.player_id == b.id, "muerto el n.º 1, hereda el n.º 2 (no el hijo mayor)")
	check(HeirsSim.heir_order(GameState) == [a.id], "la lista queda con los hermanos del nuevo jefe")
	# Lista con el cónyuge.
	_new_town(303)
	var p := GameState.player_citizen()
	var sp := _single_npc("F" if p.gender == "M" else "M")
	PopulationSim.marry(p, sp)
	var kid := _kid(10)
	HeirsSim.add_heir(GameState, sp.id)
	HeirsSim.add_heir(GameState, kid.id)
	PopulationSim.die(GameState, p, "prueba")
	check(GameState.player_id == sp.id, "el cónyuge puede heredar si el jugador lo pone primero")
	# Lista vacía: regla anterior (hijo mayor).
	_new_town(304)
	var old := _kid(30)
	_kid(10)
	PopulationSim.die(GameState, GameState.player_citizen(), "prueba")
	check(GameState.player_id == old.id, "sin lista, hereda el hijo mayor como antes")


# --- 11. Matrimonio y fortuna --------------------------------------------------------------------

func _test_marriage_merge() -> void:
	_new_town(305)
	var p := GameState.player_citizen()
	var c := _single_npc("F" if p.gender == "M" else "M")
	c.money = 777.0
	# Le damos una casa y una empresa NPC propias.
	var hut := PopulationSim.create_hut(GameState)
	hut["owner"] = "ciudadano"
	hut["owner_id"] = c.id
	var r := ConstructionSim.start_construction(GameState, "granja", 30, -8, 0.0, "Granja de la novia", "sas")
	var biz: Dictionary = r.get("building", {})
	check(not biz.is_empty(), "empresa de prueba creada")
	biz["owner"] = "ciudadano"
	biz["npc"] = true
	biz["owner_id"] = c.id
	biz["reserve"] = 200.0
	biz["owners"] = []
	var sheet := MarriageSim.sheet(GameState, c)
	check(float(sheet["wealth"]["money"]) == 777.0 and sheet["wealth"]["homes"].size() == 1 and sheet["wealth"]["businesses"].size() == 1, "la ficha muestra dinero, casas y empresas antes de proponer")
	check(MarriageSim.sheet_text(GameState, c).contains("Talentos"), "la ficha muestra talentos")
	PlayerSim._add_affinity(GameState, c.id, 100.0)
	var money0 := GameState.money
	var total0 := _total_money()
	var msg := MarriageSim.propose(GameState, c, 0.0)
	check(p.spouse_id == c.id, "aceptó: %s" % msg)
	check(is_equal_approx(GameState.money, money0 + 777.0 + 200.0), "el dinero del cónyuge (y la caja de su empresa) pasa a la familia")
	check(is_equal_approx(c.money, 0.0), "no se duplica el dinero")
	check(absf(_total_money() - total0) < 0.01, "el dinero total se conserva")
	check(GameState.owned_by_player(hut) and GameState.owned_by_player(biz), "la casa y la empresa ahora son de la familia")


func _test_proposal_rejected() -> void:
	_new_town(306)
	var p := GameState.player_citizen()
	var c := _single_npc("F" if p.gender == "M" else "M")
	check(MarriageSim.propose(GameState, c).contains("apenas te conoce") and p.spouse_id < 0, "sin relación ni siquiera hay propuesta")
	PlayerSim._add_affinity(GameState, c.id, 30.0)
	GameState.money = 0.0
	c.money = 90000.0
	var ch := MarriageSim.proposal_chance(GameState, c)
	check(ch < 0.5, "probabilidad baja si eres pobre y apenas se conocen (%d%%)" % int(ch * 100.0))
	var a0 := PlayerSim.affinity(GameState, c.id)
	var msg := MarriageSim.propose(GameState, c, 0.99)
	check(p.spouse_id < 0 and c.spouse_id < 0, "rechazó la propuesta: %s" % msg)
	check(PlayerSim.affinity(GameState, c.id) < a0, "el rechazo baja la relación")
	check(GameState.notifications_log.any(func(e): return str(e["text"]).contains("rechazó")), "el rechazo llega a las notificaciones")
	PlayerSim._add_affinity(GameState, c.id, 100.0)
	GameState.money = 90000.0
	check(MarriageSim.proposal_chance(GameState, c) > ch, "más relación y fortuna → más probabilidad")


func _test_strategic_marriage() -> void:
	_new_town(307)
	var son := _kid(24)
	son.gender = "M"
	var rich := _single_npc("F")
	rich.money = 3000.0
	var cands := MarriageSim.strategic_candidates(GameState, son)
	check(not cands.is_empty(), "hay candidatas para un matrimonio estratégico")
	if cands.is_empty():
		return
	var t: Citizen = cands[0]
	check(MarriageSim.arrange_chance(GameState, son, t, true, false) < MarriageSim.arrange_chance(GameState, son, t, false, false), "pedir dote baja la probabilidad")
	var total0 := _total_money()
	var msg := MarriageSim.arrange(GameState, son, t, false, false, 0.99)
	check(son.spouse_id < 0, "la otra familia puede rechazar: %s" % msg)
	var m0 := GameState.money
	msg = MarriageSim.arrange(GameState, son, t, true, false, 0.0)
	check(son.spouse_id == t.id, "la otra familia acepta: %s" % msg)
	check(GameState.money >= m0 and absf(_total_money() - total0) < 0.01, "la dote sale de la otra familia (dinero conservado)")
	# Pueblo conectado.
	var daughter := _kid(22)
	check(MarriageSim.arrange_foreign(GameState, daughter, 0.0).contains("conexión"), "casarse con alguien de otro pueblo requiere conexión")
	GameState.trade["connections"] = [{"town_id": "x", "town_name": "Villa Norte", "distance": 60.0, "transport": "carreta"}]
	msg = MarriageSim.arrange_foreign(GameState, daughter, 0.0)
	check(daughter.spouse_id >= 0 and GameState.citizens[daughter.spouse_id].gender != daughter.gender, "boda con alguien de otro pueblo: %s" % msg)


# --- 10. Política ----------------------------------------------------------------------------------

func _test_office_bonus() -> void:
	_new_town(308)
	var p := GameState.player_citizen()
	var kid := _kid(30)
	var t := HeirsSim.ensure_talents(GameState, kid)
	t["politica"] = 10.0
	check(PoliticsSim.can_run(GameState, kid, "concejal").contains("Talento"), "sin talento político no puede postularse")
	check(PoliticsSim.can_run(GameState, kid, "alcalde").contains("Disponible"), "alcalde solo desde la época industrial")
	t["politica"] = 70.0
	var farm_r := ConstructionSim.start_construction(GameState, "granja", 30, -8, 0.0, "Granja", "sas")
	var farm: Dictionary = farm_r["building"]
	var base_mult := PoliticsSim.profit_tax_mult(GameState, farm)
	var total0 := _total_money()
	var msg := PoliticsSim.run_for_office(GameState, kid, "concejal")
	check(not PoliticsSim.campaign_of(GameState, kid.id).is_empty(), "campaña iniciada: %s" % msg)
	check(absf(_total_money() - total0) < 0.01, "el dinero de la campaña queda en el pueblo")
	check(PoliticsSim.resolve_campaign(GameState, PoliticsSim.campaign_of(GameState, kid.id), 0.0), "gana la elección")
	check(PoliticsSim.office_of(GameState, kid.id).get("office", "") == "concejal", "ahora es concejal")
	check(PoliticsSim.profit_tax_mult(GameState, farm) < base_mult, "el cargo baja el impuesto a tus ganancias (%.2f → %.2f)" % [base_mult, PoliticsSim.profit_tax_mult(GameState, farm)])
	check(PoliticsSim.influence(GameState) > 0.0 and PoliticsSim.lobby_chance(GameState, false) > float(PoliticsSim.lobby_cfg()["legal_chance"]), "el cargo da influencia para el lobby")
	var km := kid.money
	var tr0 := float(GameState.government["treasury"])
	PoliticsSim.monthly(GameState)
	check(kid.money > km and float(GameState.government["treasury"]) < tr0, "sueldo del cargo pagado por el tesoro")
	check(kid.job_id < 0, "obligación: deja su empleo")
	# Destitución por mala reputación.
	GameState.government["reputation"] = 5.0
	PoliticsSim.monthly(GameState)
	check(PoliticsSim.office_of(GameState, kid.id).is_empty(), "con la reputación por el piso cae del cargo")
	check(p != null, "el jugador sigue")


func _test_lobby_and_scandal() -> void:
	_new_town(309)
	var farm_r := ConstructionSim.start_construction(GameState, "granja", 30, -8, 0.0, "Granja", "sas")
	var farm: Dictionary = farm_r["building"]
	var sector := str(GameState.building_def(farm).get("sector", ""))
	check(PoliticsSim.player_sectors(GameState).has(sector), "tus sectores: %s" % ", ".join(PoliticsSim.player_sectors(GameState)))
	var m0 := PoliticsSim.profit_tax_mult(GameState, farm)
	var total0 := _total_money()
	var msg := PoliticsSim.lobby(GameState, "impuesto", sector, false, 0.0)
	check(PoliticsSim.profit_tax_mult(GameState, farm) < m0, "lobby legal: rebaja de impuesto al sector (%s)" % msg)
	check(PoliticsSim.corruption(GameState) == 0.0, "el lobby legal no suma corrupción")
	msg = PoliticsSim.lobby(GameState, "licencia", "ambiental", true, 0.0)
	check(PoliticsSim.has_license(GameState, "ambiental") and PoliticsSim.corruption(GameState) > 0.0, "soborno: licencia ambiental pero suma corrupción")
	check(absf(_total_money() - total0) < 0.01, "lobby y soborno no crean ni destruyen dinero")
	check(PoliticsSim.profit_tax_mult(GameState, farm) >= 1.0 - float(PoliticsSim.cfg()["max_tax_cut"]) - 0.0001, "rebaja con tope moderado")
	# Un familiar concejal y un escándalo.
	var kid := _kid(30)
	HeirsSim.ensure_talents(GameState, kid)["politica"] = 70.0
	PoliticsSim.take_office(GameState, kid, "concejal")
	var rep0 := PoliticsSim.reputation(GameState)
	var money0 := GameState.money
	var tr0 := float(GameState.government["treasury"])
	var text := PoliticsSim.scandal(GameState)
	check(GameState.money < money0 and float(GameState.government["treasury"]) > tr0, "escándalo: multa al tesoro")
	check(PoliticsSim.reputation(GameState) < rep0, "escándalo: pérdida de reputación")
	check(PoliticsSim.office_of(GameState, kid.id).is_empty(), "escándalo: cae del cargo")
	check(not PoliticsSim.has_license(GameState, "ambiental") and not PoliticsSim.active_lobby(GameState, "impuesto", sector).is_empty(), "se anula lo obtenido con soborno, no lo legal")
	check(GameState.notifications_log.any(func(e): return str(e["text"]).contains("Escándalo")), "el escándalo llega a las notificaciones: %s" % text)
	# Riesgo mensual proporcional a la corrupción.
	PoliticsSim.state(GameState)["corruption"] = 0.0
	check(PoliticsSim.scandal_chance(GameState) == 0.0, "sin corrupción no hay riesgo de escándalo")
	PoliticsSim.state(GameState)["corruption"] = 50.0
	check(PoliticsSim.scandal_chance(GameState) > 0.0 and PoliticsSim.scandal_chance(GameState) < 0.1, "riesgo mensual moderado (%.1f%%)" % (PoliticsSim.scandal_chance(GameState) * 100.0))


func _test_factions() -> void:
	_new_town(310)
	var sup := PoliticsSim.supportable(GameState)
	check(sup.size() >= 2, "facciones de la época para apoyar")
	var cur := str(GameState.government["gov_id"])
	var fav := ""
	for g in sup:
		if g != cur:
			fav = g
	var total0 := _total_money()
	PoliticsSim.fund(GameState, fav, 50000.0)
	check(absf(_total_money() - total0) < 0.01, "el apoyo a la facción queda en el pueblo")
	check(float(PoliticsSim.faction_chance(GameState)["chance"]) > 0.9, "mucho apoyo → alta probabilidad")
	GameState.government["next_change_day"] = GameState.today()
	GovSim.monthly(GameState)
	check(str(GameState.government["gov_id"]) == fav, "la facción financiada llega al poder (GovSim)")


# --- Guardado ------------------------------------------------------------------------------------

func _test_save_load() -> void:
	_new_town(311)
	var a := _kid(12)
	var b := _kid(28)
	HeirsSim.set_plan(GameState, a, "tutor", "artes")
	HeirsSim.monthly(GameState)
	HeirsSim.add_heir(GameState, a.id)
	HeirsSim.add_heir(GameState, b.id)
	HeirsSim.ensure_talents(GameState, b)["politica"] = 80.0
	PoliticsSim.take_office(GameState, b, "concejal")
	PoliticsSim.state(GameState)["corruption"] = 12.0
	var art := HeirsSim.talent(GameState, a, "artes")
	# JSON (partidas antiguas) y binario.
	GameState.load_dict(JSON.parse_string(JSON.stringify(GameState.to_dict())))
	check(HeirsSim.heir_order(GameState) == [a.id, b.id], "el orden de herederos se guarda (JSON)")
	HeirsSim.move_heir(GameState, b.id, -1)
	check(HeirsSim.heir_order(GameState) == [b.id, a.id], "tras cargar se puede reordenar")
	check(is_equal_approx(HeirsSim.talent(GameState, GameState.citizens[a.id], "artes"), art), "los talentos se guardan")
	check(HeirsSim.edu_of(GameState, GameState.citizens[a.id])["plan"] == "tutor", "el plan de educación se guarda")
	check(PoliticsSim.office_of(GameState, b.id).get("office", "") == "concejal" and is_equal_approx(PoliticsSim.corruption(GameState), 12.0), "cargos y corrupción se guardan")
	SaveManager.save_game("test_dinastia")
	SaveManager.load_game("test_dinastia")
	check(HeirsSim.heir_order(GameState) == [b.id, a.id] and PoliticsSim.office_of(GameState, b.id).size() > 0, "guardar y cargar (binario)")
	SaveManager.delete_save("test_dinastia")
	# Partida sin datos de la sección C: valores por defecto.
	var d := GameState.to_dict()
	d["player"].erase("familia")
	d["player"].erase("politica")
	GameState.load_dict(d)
	check(HeirsSim.heir_order(GameState).is_empty() and PoliticsSim.state(GameState)["offices"].is_empty(), "partidas antiguas cargan con valores por defecto")
	TimeManager.advance_days(65)
	check(GameState.running, "la simulación sigue tras cargar")


# --- Interfaz: el panel del personaje con familia, herederos, matrimonio y política ------------------------

func _test_ui() -> void:
	_new_town(312)
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	var hud: Hud = world.hud
	var p := GameState.player_citizen()
	var kid := _kid(24)
	var small := _kid(9)
	HeirsSim.set_plan(GameState, small, "tutor", "ciencia")
	HeirsSim.add_heir(GameState, kid.id)
	HeirsSim.add_heir(GameState, small.id)
	HeirsSim.ensure_talents(GameState, kid)["politica"] = 70.0
	PlayerSim._add_affinity(GameState, _single_npc("F" if p.gender == "M" else "M").id, 60.0)
	_single_npc("F" if kid.gender == "M" else "M")
	GameState.trade["connections"] = [{"town_id": "x", "town_name": "Villa Norte", "distance": 60.0, "transport": "carreta"}]
	ConstructionSim.start_construction(GameState, "granja", 30, -8, 0.0, "Granja", "sas")
	PoliticsSim.take_office(GameState, kid, "concejal")
	hud._show_dock("player")
	await get_tree().process_frame
	var pp: PlayerPanel = hud.player_panel
	var texts := []
	for n in pp.actions.find_children("*", "Button", true, false):
		texts.append((n as Button).text)
	check(texts.any(func(t): return t == "▲") and texts.any(func(t): return t == "Añadir a la lista" or t == "▼"), "panel: orden de herederos con subir y bajar")
	check(texts.any(func(t): return t.begins_with("Proponerle matrimonio")), "panel: propuesta de matrimonio con ficha")
	check(texts.any(func(t): return t.begins_with("Buscar pareja en otro pueblo")), "panel: matrimonio con otro pueblo")
	check(texts.any(func(t): return t.begins_with("Legal ")) and texts.any(func(t): return t.begins_with("Soborno ")), "panel: lobby legal y soborno")
	# Pulsar ▲ reordena.
	for n in pp.actions.find_children("*", "Button", true, false):
		if (n as Button).text == "▲":
			(n as Button).pressed.emit()
			break
	await get_tree().process_frame
	check(HeirsSim.heir_order(GameState).size() == 2, "panel: el botón subir funciona")
	world.queue_free()
	await get_tree().process_frame
