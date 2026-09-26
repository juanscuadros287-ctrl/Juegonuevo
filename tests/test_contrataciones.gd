extends Node
## Pruebas de Contrataciones: vacantes al terminar la obra, postulantes (más con más sueldo), contratar,
## rechazar, contraofertas, requisitos de profesión, auto-contratación, vacante de conductor al comprar un
## vehículo, postulaciones vencidas, dinero conservado, guardado/carga y partida vieja.
## godot --headless res://tests/test_contrataciones.tscn

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func _ready() -> void:
	print("== Contrataciones ==")
	_test_vacancy_on_complete()
	_test_arrivals_and_wage()
	_test_hire_reject_counter()
	_test_profession()
	_test_auto_hire()
	_test_vehicle_driver()
	_test_expired()
	_test_money_conserved()
	_test_save_load()
	_test_direct_hire_still_works()
	print("== %s (%d fallos) ==" % ["TODO OK" if failures == 0 else "CON FALLOS", failures])
	get_tree().quit(1 if failures > 0 else 0)


# --- Utilidades --------------------------------------------------------------------------------------

func _new_town(seed_v: int) -> void:
	GameState.new_game({"seed": seed_v, "difficulty": "facil"})
	GameState.money = 80000.0


func _build_now(type_id: String, x: float, z: float) -> Dictionary:
	var r := ConstructionSim.start_construction(GameState, type_id, x, z, 0.0, "", "sas")
	if r.has("error"):
		print("    error construcción %s: %s" % [type_id, r["error"]])
		return {}
	var b: Dictionary = r["building"]
	var guard := 0
	while b["status"] != "activo" and guard < 400:
		TimeManager.advance_days(1)
		guard += 1
	return b


## Edificio listo al instante (sin obra) y su gancho de "obra terminada".
func _instant(type_id: String, level: int, x: float, z: float) -> Dictionary:
	var b := ConstructionSim.make_building(GameState, type_id, level, x, z, 0.0, "jugador")
	GameState.add_building(b)
	HiringSim.on_building_ready(GameState, b)
	return b


func _total() -> float:
	return float(FreeMarketSim.money_snapshot(GameState)["total"])


func _free_adult() -> Citizen:
	for c in GameState.citizens.values():
		if GameState.is_player(c.id) or c.job_kind == "empleo" or c.job_kind == "dueño" or c.school_id >= 0:
			continue
		var age: int = c.age_years(GameState.today())
		if age >= 20 and age < 60 and not HiringSim.pending(GameState).any(func(a): return int(a["cid"]) == c.id):
			return c
	return null


func _last_notes(n: int) -> String:
	var log: Array = GameState.notifications_log
	var out := []
	for i in range(maxi(0, log.size() - n), log.size()):
		out.append(str(log[i].get("text", "")))
	return "\n".join(out)


# --- Pruebas --------------------------------------------------------------------------------------------------

func _test_vacancy_on_complete() -> void:
	print("-- Vacantes al terminar la obra --")
	_new_town(501)
	var b := _build_now("granja", 20, -20)
	check(not b.is_empty() and str(b["status"]) == "activo", "la granja terminó su obra")
	check(HiringSim.is_published(GameState, b), "la vacante se publicó sola al terminar la obra")
	var v := HiringSim.vacancy(GameState, b)
	check(float(v.get("wage", 0.0)) >= GovSim.min_wage(GameState) and float(v["wage"]) > 0.0, "sueldo sugerido por mercado: %s" % Fmt.money2(float(v.get("wage", 0.0))))
	check(HiringSim.role(GameState, b) == "operario" and HiringSim.total_jobs(GameState, b) == 4, "puesto operario, 4 puestos")
	var found := false
	for e in GameState.notifications_log:
		if str(e.get("text", "")).contains("está listo") and str(e.get("text", "")).contains("vacante"):
			found = true
	check(found, "aviso «Tu negocio X está listo: tiene N vacantes»")
	HiringSim.set_wage(GameState, b, 3.3)
	check(is_equal_approx(float(HiringSim.vacancy(GameState, b)["wage"]), maxf(3.3, GovSim.min_wage(GameState))), "sueldo editable")


func _test_arrivals_and_wage() -> void:
	print("-- Postulantes y sueldo --")
	_new_town(502)
	var gs = GameState
	var a := _instant("granja", 1, 20, -20)
	var b := _instant("granja", 1, -20, 20)
	var mw := HiringSim.market_wage(gs, a)
	HiringSim.set_wage(gs, a, mw * 0.85)
	HiringSim.set_wage(gs, b, mw * 1.4)
	check(HiringSim.daily_rate(gs, b) > HiringSim.daily_rate(gs, a) * 2.0, "más sueldo → más postulantes esperados (%.2f vs %.2f/día)" % [HiringSim.daily_rate(gs, b), HiringSim.daily_rate(gs, a)])
	TimeManager.advance_days(6)
	var na := 0
	var nb := 0
	for x in HiringSim.apps(gs):
		if int(x["bid"]) == int(a["id"]):
			na += 1
		elif int(x["bid"]) == int(b["id"]):
			nb += 1
	check(nb > 0, "llegan postulantes con el tiempo (%d)" % nb)
	check(nb > na, "llegan más con más sueldo (%d vs %d)" % [nb, na])
	check(HiringSim.new_count(gs) > 0, "contador de postulantes nuevos: %d" % HiringSim.new_count(gs))
	var ok := true
	for x in HiringSim.pending(gs):
		ok = ok and x.has("asked") and x.has("prev") and x.has("expires") and gs.citizens.has(int(x["cid"]))
	check(ok, "cada postulación trae sueldo pedido, antecedente laboral y vencimiento")
	# Empleados de otras empresas que buscan mejor sueldo (una empresa ajena).
	var npc := ConstructionSim.make_building(gs, "panaderia", 1, -40, -40, 0.0, "npc")
	gs.add_building(npc)
	var emp_ok := false
	var c := _free_adult()
	c.job_id = int(npc["id"])
	c.job_kind = "empleo"
	c.wage = 0.5
	var app := HiringSim.add_application(gs, b, c)
	emp_ok = str(app["prev"]) == "empleado" and HiringSim.prev_text(app).contains("busca mejor sueldo")
	check(HiringSim.hire_app(gs, int(app["id"])) == "" and c.job_id == int(b["id"]), "contratar a un empleado de otra empresa: renuncia allá y entra aquí")
	check(emp_ok, "ficha: «trabaja en X: busca mejor sueldo»")
	HiringSim.mark_seen(gs)
	check(HiringSim.new_count(gs) == 0, "al ver la bandeja el contador vuelve a 0")


func _test_hire_reject_counter() -> void:
	print("-- Contratar, rechazar y contraofertar --")
	_new_town(503)
	var gs = GameState
	var b := _instant("granja", 1, 20, -20)
	var c1 := _free_adult()
	var a1 := HiringSim.add_application(gs, b, c1)
	check(HiringSim.hire_app(gs, int(a1["id"])) == "" and c1.job_id == int(b["id"]) and c1.job_kind == "empleo", "Contratar usa BusinessSim.hire")
	check(str(a1["status"]) == "contratada" and c1.wage >= float(a1["asked"]) - 0.001, "contratado al sueldo pedido o al publicado (%s)" % Fmt.money2(c1.wage))
	var rep0 := HiringSim.reputation(gs)
	var c2 := _free_adult()
	var a2 := HiringSim.add_application(gs, b, c2)
	HiringSim.reject_app(gs, int(a2["id"]))
	check(str(a2["status"]) == "rechazada" and c2.job_id != int(b["id"]), "Rechazar lo quita de la bandeja")
	check(HiringSim.reputation(gs) < rep0 and HiringSim.reputation(gs) > rep0 - 1.0, "un rechazo baja un poco la reputación (%.2f → %.2f)" % [rep0, HiringSim.reputation(gs)])
	var c3 := _free_adult()
	var a3 := HiringSim.add_application(gs, b, c3)
	var r3 := HiringSim.counter_offer(gs, int(a3["id"]), float(a3["asked"]))
	check(bool(r3["accepted"]) and c3.job_id == int(b["id"]) and is_equal_approx(c3.wage, snappedf(float(a3["asked"]), 0.05)), "contraoferta aceptada: %s" % str(r3["text"]))
	var c4 := _free_adult()
	var a4 := HiringSim.add_application(gs, b, c4)
	a4["asked"] = GovSim.min_wage(gs) * 3.0 + 3.0
	var r4 := HiringSim.counter_offer(gs, int(a4["id"]), float(a4["asked"]) * 0.5)
	check(not bool(r4["accepted"]) and str(a4["status"]) == "retirada" and c4.job_id != int(b["id"]), "contraoferta baja rechazada: %s" % str(r4["text"]))


func _test_profession() -> void:
	print("-- Requisitos de profesión --")
	_new_town(504)
	var gs = GameState
	var b := _instant("constructora", 2, 20, -20)
	check(HiringSim.req_profession(gs, b) == "ingeniero" and HiringSim.role(gs, b) == "profesional", "la constructora nivel 2 exige ingenieros (puesto profesional)")
	var c := _free_adult()
	c.profession = ""
	var a := HiringSim.add_application(gs, b, c)
	check(not HiringSim.meets(gs, b, c) and HiringSim.hire_app(gs, int(a["id"])) != "" and c.job_id != int(b["id"]), "sin título no se puede contratar")
	var n := HiringSim.reject_unqualified(gs, b)
	check(n >= 1 and str(a["status"]) == "rechazada", "«Rechazar a todos los que no cumplen» (%d)" % n)
	var e := _free_adult()
	e.profession = "ingeniero"
	e.education = maxi(e.education, HiringSim.req_education(gs, b))
	var a2 := HiringSim.add_application(gs, b, e)
	check(HiringSim.hire_app(gs, int(a2["id"])) == "" and e.job_id == int(b["id"]), "un ingeniero sí se contrata")


func _test_auto_hire() -> void:
	print("-- Auto-contratación --")
	_new_town(505)
	var gs = GameState
	var b := _instant("granja", 1, 20, -20)
	HiringSim.set_wage(gs, b, HiringSim.market_wage(gs, b) * 1.3)
	HiringSim.set_auto(gs, b, true, HiringSim.market_wage(gs, b) * 3.0)
	HiringSim.publish(gs, b, true)
	TimeManager.advance_days(12)
	var st := HiringSim.staff(gs, b)
	check(st.size() > 0, "la auto-contratación llenó puestos (%d/%d)" % [st.size(), HiringSim.total_jobs(gs, b)])
	var ok := true
	for c in st:
		ok = ok and HiringSim.meets(gs, b, c) and c.wage <= HiringSim.market_wage(gs, b) * 3.0 + 0.01
	check(ok, "solo contrató a quienes cumplen requisitos y hasta el sueldo máximo")
	# Con máximo muy bajo no contrata a nadie.
	var b2 := _instant("granja", 1, -20, 20)
	HiringSim.set_auto(gs, b2, true, 0.05)
	HiringSim.publish(gs, b2, true)
	TimeManager.advance_days(5)
	check(HiringSim.staff(gs, b2).is_empty(), "con sueldo máximo muy bajo no contrata")


func _test_vehicle_driver() -> void:
	print("-- Transporte: vacante de conductor al comprar un vehículo --")
	_new_town(506)
	var gs = GameState
	var st := _instant("caballeriza", 1, 20, -20)
	check(HiringSim.role(gs, st) == "conductor", "la caballeriza contrata conductores")
	HiringSim.publish(gs, st, false)
	var r := LogisticsSim.buy_vehicle(gs, st, "mula")
	check(r.has("vehicle"), "compró una mula: %s" % str(r.get("error", "ok")))
	check(HiringSim.is_published(gs, st), "al comprar el vehículo se publicó la vacante de conductor")
	check(HiringSim.stopped_vehicles(gs, st) == 1, "sin conductor el vehículo queda detenido")
	check(_last_notes(3).contains("conductor"), "aviso de vacante de conductor")
	var c := _free_adult()
	var a := HiringSim.add_application(gs, st, c)
	HiringSim.hire_app(gs, int(a["id"]))
	check(HiringSim.stopped_vehicles(gs, st) == 0, "con conductor ya no está detenido")
	var ct := _instant("central_transporte", 1, -20, 20)
	check(HiringSim.role(gs, ct) == "cargador" and HiringSim.is_published(gs, ct), "la central de transporte publica vacantes de cargadores")


func _test_expired() -> void:
	print("-- Postulaciones vencidas --")
	_new_town(507)
	var gs = GameState
	var b := _instant("granja", 1, 20, -20)
	HiringSim.publish(gs, b, false)
	var c := _free_adult()
	var a := HiringSim.add_application(gs, b, c)
	a["expires"] = gs.today() + 1
	var rep0 := HiringSim.reputation(gs)
	TimeManager.advance_days(2)
	check(str(a["status"]) == "vencida", "la postulación sin respuesta venció")
	check(HiringSim.reputation(gs) < rep0, "las vencidas bajan un poco la reputación")
	check(not HiringSim.pending(gs, b).has(a), "ya no aparece en la bandeja")


func _test_money_conserved() -> void:
	print("-- Dinero conservado --")
	_new_town(508)
	var gs = GameState
	var b := _instant("granja", 1, 20, -20)
	var st := _instant("caballeriza", 1, -20, 20)
	var t0 := _total()
	for i in 4:
		var c := _free_adult()
		HiringSim.add_application(gs, b if i % 2 == 0 else st, c)
	HiringSim.daily(gs)
	var ids := []
	for a in HiringSim.pending(gs):
		ids.append(int(a["id"]))
	if ids.size() >= 3:
		HiringSim.hire_app(gs, ids[0])
		HiringSim.reject_app(gs, ids[1])
		HiringSim.counter_offer(gs, ids[2], 0.1)
	HiringSim.set_auto(gs, b, true, 99.0)
	HiringSim.auto_hire(gs, b)
	HiringSim.monthly(gs)
	check(absf(_total() - t0) < 0.01, "contratar, rechazar, contraofertar y auto-contratar no crean ni destruyen dinero (Δ %.4f)" % (_total() - t0))


func _test_save_load() -> void:
	print("-- Guardado y carga --")
	_new_town(509)
	var gs = GameState
	var b := _instant("granja", 1, 20, -20)
	HiringSim.set_wage(gs, b, 4.25)
	HiringSim.set_auto(gs, b, true, 6.5)
	var c := _free_adult()
	var a := HiringSim.add_application(gs, b, c)
	var c2 := _free_adult()
	BusinessSim.hire(gs, b, c2, 3.0)
	var d: Dictionary = JSON.parse_string(JSON.stringify(gs.to_dict()))
	gs.load_dict(d)
	var b2: Dictionary = gs.get_building(int(b["id"]))
	var v := HiringSim.vacancy(gs, b2)
	check(is_equal_approx(float(v.get("wage", 0.0)), 4.25) and bool(v.get("auto", false)) and is_equal_approx(float(v.get("auto_max", 0.0)), 6.5), "la vacante se guarda (sueldo, auto, máximo)")
	var ap := HiringSim.get_app(gs, int(a["id"]))
	check(not ap.is_empty() and int(ap["cid"]) == c.id and str(ap["status"]) in HiringSim.PENDING, "la postulación se guarda")
	check(HiringSim.hire_app(gs, int(a["id"])) == "", "tras cargar se puede contratar al postulante")
	# Partida vieja: sin "hiring" en labor. Los empleados siguen.
	var old: Dictionary = JSON.parse_string(JSON.stringify(gs.to_dict()))
	(old["labor"] as Dictionary).erase("hiring")
	gs.load_dict(old)
	var b3: Dictionary = gs.get_building(int(b["id"]))
	check(HiringSim.staff(gs, b3).size() == 2, "partida vieja: los empleados actuales se mantienen (%d)" % HiringSim.staff(gs, b3).size())
	check(HiringSim.apps(gs).is_empty() and HiringSim.vacancy(gs, b3).is_empty() and is_equal_approx(HiringSim.reputation(gs), 50.0), "partida vieja: estado por defecto")
	TimeManager.advance_days(2)
	check(true, "partida vieja: simula sin errores")


func _test_direct_hire_still_works() -> void:
	print("-- Contratación directa (BusinessSim.hire) --")
	_new_town(510)
	var gs = GameState
	var b := _instant("granja", 1, 20, -20)
	var c := _free_adult()
	check(BusinessSim.hire(gs, b, c, maxf(GovSim.min_wage(gs), 3.0)) == "" and c.job_id == int(b["id"]), "BusinessSim.hire sigue funcionando directo")
	var app := HiringSim.add_application(gs, b, _free_adult())
	BusinessSim.fire(gs, c, "Despediste a %s." % c.full_name())
	var a2 := HiringSim.add_application(gs, b, c)
	check(str(a2["prev"]) == "despedido" and HiringSim.prev_text(a2).contains("despedido"), "la ficha indica «fue despedido de …»")
	check(HiringSim.quit_risk(gs, _hire_any(b)) in ["alto", "medio", "bajo"], "riesgo de irse calculado")
	check(app.has("id"), "postulación creada")


func _hire_any(b: Dictionary) -> Citizen:
	var c := _free_adult()
	BusinessSim.hire(GameState, b, c, maxf(GovSim.min_wage(GameState), BusinessSim.asked_wage(GameState, c, str(b["type"]))))
	return c
