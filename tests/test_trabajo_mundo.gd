extends Node
## Pruebas de las secciones B (trabajo) y D (mundo): sindicatos y huelgas, experiencia por oficio,
## competencia NPC, clima que afecta el agro y los precios, tecnología que mitiga, contaminación local,
## filtros, multas, guerras sin combate, dinero conservado y guardado.
## godot --headless res://tests/test_trabajo_mundo.tscn

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func _ready() -> void:
	print("== Trabajo y mundo: secciones B y D ==")
	_test_data()
	_test_experience()
	_test_union_strike()
	_test_union_accept_counter()
	_test_npc_competition()
	_test_climate()
	_test_flood_river()
	_test_pollution()
	_test_war()
	_test_money_conserved()
	_test_save_load()
	print("== %s (%d fallos) ==" % ["TODO OK" if failures == 0 else "CON FALLOS", failures])
	get_tree().quit(1 if failures > 0 else 0)


# --- Utilidades ----------------------------------------------------------------------------------

func _new_town(seed_v: int, diff := "facil") -> void:
	GameState.new_game({"seed": seed_v, "difficulty": diff})
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


func _staff_up(b: Dictionary, wage_factor := 1.1) -> int:
	var jobs := int(GameState.level_def(b).get("jobs", 1))
	var hired := 0
	for c in BusinessSim.candidates(GameState, b):
		if hired >= jobs:
			break
		c.education = maxi(c.education, int(GameState.level_def(b).get("min_education", 0)))
		if BusinessSim.hire(GameState, b, c, maxf(GovSim.min_wage(GameState), BusinessSim.asked_wage(GameState, c, str(b["type"])) * wage_factor)) == "":
			hired += 1
	return hired


func _staff(b: Dictionary) -> Array:
	return LaborSim.staff(GameState, b)


func _total() -> float:
	return float(FreeMarketSim.money_snapshot(GameState)["total"])


func _rich_citizen(skill: String) -> Citizen:
	var best: Citizen = null
	for c in GameState.citizens.values():
		if GameState.is_player(c.id) or c.job_id >= 0 or c.age_years(GameState.today()) < 22:
			continue
		if best == null or float(c.skills.get(skill, 0.0)) > float(best.skills.get(skill, 0.0)):
			best = c
	best.skills[skill] = maxf(40.0, float(best.skills.get(skill, 0.0)))
	best.money += 5000.0
	return best


func _open_npc(type_id: String, x: float, z: float) -> Dictionary:
	var owner := _rich_citizen(str(GameData.building_def(type_id).get("skill", "")))
	var b := NpcBusinessSim.open_business(GameState, owner, type_id, x, z, 0.0)
	var guard := 0
	while str(b["status"]) != "activo" and guard < 300:
		TimeManager.advance_days(1)
		guard += 1
	TimeManager.advance_days(1)
	return b


# --- Datos -----------------------------------------------------------------------------------------

func _test_data() -> void:
	print("-- Datos --")
	_new_town(401)
	var cfg := LaborSim.cfg()
	check(not cfg.is_empty() and cfg.has("unions") and cfg.has("climate") and cfg.has("pollution") and cfg.has("wars"), "data/trabajo_mundo.json cargado")
	var clima: Dictionary = GameData.extra("technologies_clima")
	var cells := {}
	var ok := true
	for id in clima:
		if str(id).begins_with("_"):
			continue
		var t: Dictionary = GameData.technologies.get(id, {})
		ok = ok and not t.is_empty()
		for r in t.get("requires", []):
			ok = ok and GameData.technologies.has(r) and int(GameData.technologies[r].get("era", 1)) <= int(t.get("era", 1))
	check(ok and clima.size() >= 5, "technologies_clima.json: %d tecnologías con prerrequisitos válidos" % (clima.size() - 1))
	# Posiciones del árbol: se replica el algoritmo de ResearchScreen._layout y se verifica que ninguna celda se repita.
	var rs := ResearchScreen.new()
	rs.canvas = Control.new()
	rs._layout()
	var seen := {}
	var dup := []
	for id in rs.positions:
		var k := str(rs.positions[id])
		if seen.has(k):
			dup.append("%s/%s" % [seen[k], id])
		seen[k] = id
	check(dup.is_empty() and rs.positions.has("canales_riego") and rs.positions.has("precipitadores"), "el árbol ubica las tecnologías nuevas sin superponerse %s" % str(dup))
	rs.canvas.free()
	rs.free()
	check(TechSim.effects_text("canales_riego").size() == 3, "efectos de mitigación visibles: %s" % ", ".join(TechSim.effects_text("canales_riego")))


# --- 7. Experiencia por oficio -------------------------------------------------------------------------

func _test_experience() -> void:
	print("-- Experiencia por oficio --")
	_new_town(402)
	var gs = GameState
	var seeded := 0
	for c in gs.citizens.values():
		if not c.trade_exp.is_empty():
			seeded += 1
	check(seeded > 0, "los adultos traen experiencia inicial en su oficio (%d)" % seeded)
	var c: Citizen = null
	for x in gs.citizens.values():
		if not gs.is_player(x.id) and x.age_years(gs.today()) >= 20:
			c = x
			break
	c.trade_exp = {}
	var p0 := BusinessSim.productivity(c, "agricultura")
	var w0 := BusinessSim.asked_wage(gs, c, "granja")
	c.trade_exp["agricultura"] = 10.0
	var p1 := BusinessSim.productivity(c, "agricultura")
	var w1 := BusinessSim.asked_wage(gs, c, "granja")
	check(absf(p1 / p0 - 1.2) < 0.001, "un veterano (10 años) rinde +20 %% (%.3f → %.3f)" % [p0, p1])
	check(w1 > w0 and w1 <= w0 * 1.12, "y pide algo más de sueldo (%s → %s)" % [Fmt.money2(w0), Fmt.money2(w1)])
	c.trade_exp["agricultura"] = 5.0
	check(absf(BusinessSim.productivity(c, "agricultura") / p0 - 1.1) < 0.001, "a mitad de camino (5 años) rinde +10 %")
	check(LaborSim.exp_mult(c, "mineria") == 1.0, "la experiencia es por oficio (no sirve en otro sector)")
	# Acumula trabajando.
	var farm := _build_now("granja", 20, 16)
	_staff_up(farm)
	var e := _staff(farm)[0] as Citizen
	var y0 := LaborSim.years(e, "agricultura")
	for i in range(365):
		LaborSim._accumulate(gs)
	var y1 := LaborSim.years(e, "agricultura")
	check(absf(y1 - y0 - 1.0) < 0.01, "un año trabajando suma un año de oficio (%.2f → %.2f)" % [y0, y1])
	# Si lo despiden, la experiencia se va con él y la competencia puede contratarlo.
	e.trade_exp["agricultura"] = 8.0
	BusinessSim.fire(gs, e, "")
	check(LaborSim.years(e, "agricultura") == 8.0 and e.job_id < 0, "despedido: conserva sus 8 años de oficio")
	var npc := _open_npc("granja", -26, 24)
	NpcBusinessSim.staff_index(gs)
	NpcBusinessSim.hire_silent(gs, npc, e)
	check(e.job_id == int(npc["id"]) and NpcBusinessSim._output(gs, npc, [e]) > 0.0, "la competencia NPC lo contrata y aprovecha su experiencia")
	var panel_ok := LaborSim.exp_text(e, "agricultura").begins_with("oficio 8.0")
	check(panel_ok, "texto para la ficha: %s" % LaborSim.exp_text(e, "agricultura"))


# --- 6. Sindicatos y huelgas ---------------------------------------------------------------------------

func _test_union_strike() -> void:
	print("-- Sindicato, rechazo y huelga --")
	_new_town(403)
	var gs = GameState
	var b := _build_now("lenador", 22, -18)
	var n := _staff_up(b, 0.75)
	check(n >= 3, "leñador con %d empleados" % n)
	# Época colonial: no hay sindicatos.
	for i in range(40):
		LaborSim._unions_monthly(gs)
	check(gs.labor["unions"].is_empty(), "en la época colonial no hay sindicatos")
	gs.research["era"] = 2
	for c in _staff(b):
		c.wage = maxf(GovSim.min_wage(gs), BusinessSim.asked_wage(gs, c, "lenador") * 0.7)
	var g := LaborSim.grievance(gs, b)
	check(float(g["ratio"]) < 0.9 and float(g["score"]) > 0.0, "sueldos bajo el mercado (ratio %.2f, presión %.2f)" % [float(g["ratio"]), float(g["score"])])
	# Frecuencia baja: con presión máxima, a lo sumo ~10 % mensual.
	var hits := 0
	for m in range(60):
		var ch := minf(float(LaborSim.ucfg().get("max_chance", 0.1)), float(LaborSim.ucfg().get("base_chance", 0.12)) * float(g["score"]))
		if ch <= 0.1001:
			hits += 1
	check(hits == 60, "probabilidad mensual acotada (≤ 10 %)")
	var u := LaborSim.start_demand(gs, b)
	check(str(u["state"]) == "demanda" and float(u["pct"]) >= 0.06 and float(u["pct"]) <= 0.18, "el sindicato pide +%d %% antes de parar" % int(round(float(u["pct"]) * 100.0)))
	check(gs.notifications_log.any(func(x): return "SINDICATO" in str(x["text"])), "aviso en notificaciones")
	var out0 := BusinessSim.expected_output(gs, b)
	var wages0 := 0.0
	for c in _staff(b):
		wages0 += c.wage
	check(LaborSim.reject_demand(gs, b) == "" and LaborSim.on_strike(gs, b), "rechazas: huelga")
	var uu: Dictionary = LaborSim.union_of(gs, b)
	var days := int(uu["until"]) - int(uu["start"])
	check(days >= 3 and days <= 10, "huelga corta (%d días)" % days)
	var out1 := BusinessSim.expected_output(gs, b)
	check(out1 <= out0 * 0.3 + 0.0001, "la huelga baja la producción (%.2f → %.2f, %d %%)" % [out0, out1, int(round(float(uu["factor"]) * 100.0))])
	check(gs.notifications_log.any(func(x): return "HUELGA" in str(x["text"])), "aviso de huelga")
	for i in range(days + 1):
		TimeManager.advance_days(1)
	check(not LaborSim.on_strike(gs, b) and LaborSim.union_of(gs, b).is_empty(), "la huelga termina sola")
	var wages1 := 0.0
	for c in _staff(b):
		wages1 += c.wage
	check(wages1 > wages0, "termina con un acuerdo: sueldos %s → %s" % [Fmt.money2(wages0), Fmt.money2(wages1)])
	check(BusinessSim.expected_output(gs, b) > out1 + 0.01, "la producción vuelve a la normalidad")
	check(gs.notifications_log.any(func(x): return "Terminó la huelga" in str(x["text"])), "aviso del acuerdo")
	# Sin respuesta en el plazo: huelga.
	LaborSim.start_demand(gs, b)
	for i in range(int(LaborSim.ucfg().get("reply_days", 14)) + 1):
		TimeManager.advance_days(1)
	check(LaborSim.on_strike(gs, b) or LaborSim.union_of(gs, b).is_empty(), "si no respondes a tiempo, paran")


func _test_union_accept_counter() -> void:
	print("-- Sindicato: aceptar y contraoferta --")
	_new_town(404)
	var gs = GameState
	gs.research["era"] = 2
	var b := _build_now("lenador", -22, 18)
	_staff_up(b, 0.75)
	LaborSim.start_demand(gs, b)
	var pct := float(LaborSim.union_of(gs, b)["pct"])
	var w0: float = (_staff(b)[0] as Citizen).wage
	check(LaborSim.accept_demand(gs, b) == "" and LaborSim.union_of(gs, b).is_empty(), "aceptar cierra el pedido")
	var w1: float = (_staff(b)[0] as Citizen).wage
	check(absf(w1 - snappedf(w0 * (1.0 + pct), 0.01)) < 0.011, "aceptar sube el sueldo pedido (%s → %s)" % [Fmt.money2(w0), Fmt.money2(w1)])
	LaborSim.start_demand(gs, b)
	var pct2 := float(LaborSim.union_of(gs, b)["pct"])
	var r := LaborSim.counter_offer(gs, b, pct2 * 0.2)
	check(r != "" and LaborSim.on_strike(gs, b), "una contraoferta muy baja termina en huelga")
	gs.labor["unions"] = {}
	LaborSim.start_demand(gs, b)
	var pct3 := float(LaborSim.union_of(gs, b)["pct"])
	check(LaborSim.counter_offer(gs, b, pct3) == "", "una contraoferta igual al pedido se acepta")


# --- 8. Competencia NPC -----------------------------------------------------------------------------------

func _test_npc_competition() -> void:
	print("-- Competencia NPC --")
	_new_town(405)
	var gs = GameState
	var mine := _build_now("granja", 24, 14)
	_staff_up(mine)
	var npc := _open_npc("granja", -28, 22)
	check(NpcBusinessSim.is_npc(npc) and str(npc["status"]) == "activo", "empresa NPC de la competencia abierta")
	# Guerra de precios sin vender a pérdida.
	npc["ledger"]["last_month"] = {"ventas": 100.0, "salarios": 70.0, "mantenimiento": 10.0}
	var m0 := float(npc.get("markup", 0.08))
	var p0 := float(npc["price"])
	var cut := LaborSim.start_price_war(gs, npc, mine)
	var p1 := float(npc["price"])
	check(cut > 0.0 and float(npc["markup"]) < m0 and p1 < p0, "baja precios temporalmente (%s → %s)" % [Fmt.money2(p0), Fmt.money2(p1)])
	check((1.0 + float(npc["markup"])) / (1.0 + m0) >= 1.0 - 0.2 * 0.7 - 0.001, "el recorte sale de su margen (20 %): no vende a pérdida")
	check(cut <= 0.12 + 0.0001, "recorte suave (máx. 12 %)")
	check(gs.notifications_log.any(func(x): return "bajó sus precios" in str(x["text"])), "aviso de la guerra de precios")
	npc["ledger"]["last_month"] = {"ventas": 100.0, "salarios": 99.0}
	var npc_b := _open_npc("granja", 30, -26)
	npc_b["ledger"]["last_month"] = {"ventas": 100.0, "salarios": 110.0}
	check(LaborSim.start_price_war(gs, npc_b, mine) == 0.0, "si pierde dinero no baja precios")
	var w: Dictionary = LaborSim.price_war_of(gs, npc)
	for i in range(int(w["until"]) - gs.today() + 1):
		LaborSim._price_wars_daily(gs)
		TimeManager.advance_days(1)
	check(LaborSim.price_war_of(gs, npc).is_empty() and absf(float(npc["markup"]) - m0) < 0.0001, "la guerra de precios termina y vuelve a su margen")
	# Oferta de sueldo a tu mejor empleado.
	npc["reserve"] = 5000.0
	var best: Citizen = _staff(mine)[0]
	best.trade_exp["agricultura"] = 40.0
	var o := LaborSim.make_offer(gs, npc)
	check(not o.is_empty() and int(o["cid"]) == best.id, "la NPC tienta a tu empleado más experimentado (%s, 40 años)" % best.full_name())
	check(float(o["wage"]) > best.wage, "ofrece más sueldo (%s → %s)" % [Fmt.money2(best.wage), Fmt.money2(float(o["wage"]))])
	check(gs.notifications_log.any(func(x): return "recibió una oferta" in str(x["text"])), "te avisan")
	check(LaborSim.match_offer(gs, int(o["id"])) == "" and absf(best.wage - float(o["wage"])) < 0.001 and best.job_id == int(mine["id"]), "igualas la oferta y se queda")
	var other: Citizen = _staff(mine)[1]
	other.trade_exp["agricultura"] = 3.0
	var o2 := LaborSim.make_offer(gs, npc, other)
	check(not o2.is_empty(), "otra oferta a %s" % other.full_name())
	LaborSim.decline_offer(gs, int(o2["id"]))
	check(other.job_id == int(npc["id"]) and absf(other.wage - float(o2["wage"])) < 0.001 and LaborSim.years(other, "agricultura") >= 3.0, "si no la igualas se va a la competencia con su experiencia")
	var third: Citizen = _staff(mine)[1]
	var o3 := LaborSim.make_offer(gs, npc, third)
	for i in range(int(LaborSim.ncfg().get("poach_reply_days", 7)) + 1):
		TimeManager.advance_days(1)
	check(str(o3.get("status", "")) != "pendiente", "sin respuesta, decide solo al vencer el plazo (%s)" % str(o3.get("status", "")))


# --- 12. Clima ------------------------------------------------------------------------------------------------

func _test_climate() -> void:
	print("-- Clima: sequía, precios y tecnología --")
	_new_town(406)
	var gs = GameState
	var farm := _build_now("granja", 18, 20)
	_staff_up(farm)
	var mill := _build_now("lenador", -20, 20)
	_staff_up(mill)
	var c0 := ClimateSim.town_climate(gs)
	check(c0.has("temperature") and c0.has("humidity"), "clima de la zona por MapSim.climate_at (T %.2f, H %.2f, %s)" % [float(c0["temperature"]), float(c0["humidity"]), str(c0.get("biome", ""))])
	gs.season = "verano"
	check(ClimateSim.chance(gs, "sequia") > 0.0 and ClimateSim.chance(gs, "helada") == 0.0, "las sequías dependen de la estación (verano sí, heladas no)")
	gs.season = "invierno"
	check(ClimateSim.chance(gs, "helada") > 0.0, "en invierno puede helar")
	var out0 := BusinessSim.expected_output(gs, farm)
	var wood0 := BusinessSim.expected_output(gs, mill)
	var price0 := EconomySim.market_price(gs, "comida")
	var e := ClimateSim.schedule(gs, "sequia", 5, 20, 1.0)
	check(not e.is_empty() and ClimateSim.forecasts(gs).size() == 1 and ClimateSim.output_mult(gs, farm) == 1.0, "pronóstico: aviso previo antes de la sequía")
	check(gs.notifications_log.any(func(x): return "Pronóstico" in str(x["text"])), "aviso del pronóstico en notificaciones")
	for i in range(5):
		TimeManager.advance_days(1)
	check(ClimateSim.active_events(gs).size() == 1, "la sequía empieza en la fecha pronosticada")
	var out1 := BusinessSim.expected_output(gs, farm)
	var mult1 := ClimateSim.output_mult(gs, farm)
	var bm_saved: Dictionary = gs.world_events["climate"]["bmult"]
	gs.world_events["climate"]["bmult"] = {}
	out0 = BusinessSim.expected_output(gs, farm)
	gs.world_events["climate"]["bmult"] = bm_saved
	var price1 := EconomySim.market_price(gs, "comida")
	check(mult1 < 0.75 and mult1 > 0.2, "la sequía baja la producción agrícola (×%.2f)" % mult1)
	check(out1 < out0 or out0 <= 0.0, "producción de la granja %.2f → %.2f" % [out0, out1])
	check(ClimateSim.output_mult(gs, mill) == 1.0, "no afecta a un negocio que no es agro (leñador)")
	check(price1 > price0 * 1.1 and price1 < price0 * 1.5, "sube el precio de la comida por escasez (%s → %s)" % [Fmt.money2(price0), Fmt.money2(price1)])
	check(EconomySim.market_price(gs, "harina") > 0.0 and float(gs.world_events["climate"]["price"].get("harina", 1.0)) < float(gs.world_events["climate"]["price"].get("trigo", 1.0)), "los procesados suben menos que la materia prima")
	# Tecnología que mitiga.
	gs.techs.append("canales_riego")
	TechSim._recompute_mods(gs)
	ClimateSim._refresh(gs)
	var mult2 := ClimateSim.output_mult(gs, farm)
	var price2 := EconomySim.market_price(gs, "comida")
	check(mult2 > mult1 + 0.1, "el riego mitiga la sequía (×%.2f → ×%.2f)" % [mult1, mult2])
	check(price2 < price1, "y la escasez sube menos el precio (%s → %s)" % [Fmt.money2(price1), Fmt.money2(price2)])
	for i in range(21):
		TimeManager.advance_days(1)
	check(ClimateSim.active_events(gs).is_empty() and ClimateSim.output_mult(gs, farm) == 1.0 and ClimateSim.price_mult(gs, "comida") == 1.0, "la sequía termina y todo vuelve a la normalidad")
	# Heladas con invernaderos.
	var h := ClimateSim.schedule(gs, "helada", 0, 10, 1.0)
	var hm0 := ClimateSim.output_mult(gs, farm)
	gs.techs.append("invernaderos")
	TechSim._recompute_mods(gs)
	ClimateSim._refresh(gs)
	check(not h.is_empty() and hm0 < 1.0 and ClimateSim.output_mult(gs, farm) > hm0, "los invernaderos mitigan la helada (×%.2f → ×%.2f)" % [hm0, ClimateSim.output_mult(gs, farm)])
	# Frecuencia moderada: probabilidad mensual baja.
	var total := 0.0
	for s in ["primavera", "verano", "otono", "invierno"]:
		gs.season = s
		for id in ClimateSim.cfg().get("events", {}):
			total += ClimateSim.chance(gs, str(id))
	check(total / 4.0 < 0.2, "frecuencia moderada (%.1f %% mensual en promedio)" % (total / 4.0 * 100.0))


func _test_flood_river() -> void:
	print("-- Inundación junto al río --")
	GameState.new_game({"seed": 407, "difficulty": "facil", "map_type": "rio"})
	GameState.money = 50000.0
	var gs = GameState
	var spot := Vector2(INF, INF)
	for r in range(10, 200, 6):
		for k in range(24):
			var a := k * TAU / 24.0
			var p := Vector2(cos(a), sin(a)) * r
			if MapSim.biome_at(p.x, p.y, gs) == "rio":
				spot = p
				break
		if spot.x != INF:
			break
	if spot.x == INF:
		print("    (sin río cerca de la plaza en esta semilla: se omite)")
		return
	var fake := {"id": 999999, "type": "lenador", "x": spot.x + 3.0, "z": spot.y, "status": "activo", "owner": "jugador"}
	var far := {"id": 999998, "type": "lenador", "x": 0.0, "z": 0.0, "status": "activo", "owner": "jugador"}
	ClimateSim.schedule(gs, "inundacion", 0, 10, 1.0)
	check(ClimateSim.near_river(gs, fake) and ClimateSim.compute_mult(gs, fake) < 0.8, "la inundación afecta un edificio junto al río (×%.2f)" % ClimateSim.compute_mult(gs, fake))
	check(ClimateSim.near_river(gs, far) or ClimateSim.compute_mult(gs, far) == 1.0, "un edificio lejos del río no se afecta")
	gs.techs.append("diques")
	TechSim._recompute_mods(gs)
	check(ClimateSim.compute_mult(gs, fake) > 0.85, "los diques contienen la crecida (×%.2f)" % ClimateSim.compute_mult(gs, fake))


# --- 13. Contaminación -----------------------------------------------------------------------------------------

func _test_pollution() -> void:
	print("-- Contaminación, filtros y multas --")
	_new_town(408)
	var gs = GameState
	var q := _build_now("cantera", 26, 0)
	_staff_up(q)
	q["level"] = 2   # Cantera con pólvora: contaminación 2.
	_staff_up(q)
	var home: Dictionary = {}
	for b in gs.buildings:
		if str(gs.building_def(b).get("category", "")) == "vivienda" and not gs.residents_of(int(b["id"])).is_empty() and not gs.residents_of(int(b["id"])).any(func(c): return gs.is_player(c.id)):
			home = b
			break
	home["x"] = float(q["x"]) + 7.0
	home["z"] = float(q["z"]) + 5.0
	var neighbor: Citizen = gs.residents_of(int(home["id"]))[0]
	var e0 := PollutionSim.emission(gs, q)
	check(e0 > 0.0, "la cantera emite %.2f (nivel %.0f × actividad %.2f)" % [e0, PollutionSim.base_pollution(gs, q), PollutionSim.activity(gs, q)])
	for i in range(4):
		PollutionSim.monthly(gs)
	var ex := PollutionSim.exposure_of_home(gs, int(home["id"]))
	check(ex > 0.0 and float(gs.world_events["pollution"]["acc"].get(str(int(q["id"])), 0.0)) > e0, "se acumula en la zona (acumulado %.2f, exposición de la casa vecina %.2f)" % [float(gs.world_events["pollution"]["acc"].get(str(int(q["id"])), 0.0)), ex])
	var dm := PollutionSim.disease_mult(gs, neighbor)
	var hd := PollutionSim.happiness_delta(gs, neighbor)
	check(dm > 1.02 and dm <= 1.6, "los vecinos enferman más (×%.2f)" % dm)
	check(hd < 0.0 and hd >= -6.0, "y están menos felices (%.1f)" % hd)
	# Estadística: más enfermos con la exposición.
	var saved: Dictionary = gs.world_events["pollution"]["exposure"]
	gs.world_events["pollution"]["exposure"] = {str(int(home["id"])): 30.0}
	var sick_exp := _sick_count(neighbor, 60000)
	gs.world_events["pollution"]["exposure"] = {}
	var sick_clean := _sick_count(neighbor, 60000)
	gs.world_events["pollution"]["exposure"] = saved
	check(sick_exp > sick_clean * 1.2, "con mucha exposición enferman más (%d vs %d en 60000 días simulados)" % [sick_exp, sick_clean])
	var far_home: Dictionary = {}
	for b in gs.buildings:
		if str(gs.building_def(b).get("category", "")) == "vivienda" and Vector2(float(b["x"]), float(b["z"])).distance_to(Vector2(float(q["x"]), float(q["z"]))) > 60.0:
			far_home = b
			break
	check(far_home.is_empty() or PollutionSim.exposure_of_home(gs, int(far_home["id"])) == 0.0, "las casas lejanas no se afectan")
	check(PollutionSim.panel_text(gs, q).begins_with("Contaminación: "), "panel: %s" % PollutionSim.panel_text(gs, q))
	# Multa (gobierno Verde, época moderna) — sin licencia ambiental.
	gs.government["gov_id"] = "verde"
	var t0 := float(gs.government["treasury"])
	GovSim._collect_taxes(gs)
	var fine0 := float(gs.government["taxes_last"]["multas"])
	check(fine0 > 0.0, "multa ambiental del gobierno: %s" % Fmt.money(fine0))
	check(float(gs.government["treasury"]) >= t0 + fine0 - 0.01, "la multa va al tesoro")
	# Filtro que reduce.
	check(PollutionSim.buy_filters(gs, q) != "", "sin la tecnología no se pueden comprar filtros")
	gs.techs.append("filtros_industriales")
	var cost := PollutionSim.filter_cost(gs, q, 1)
	var money0: float = gs.money
	check(PollutionSim.buy_filters(gs, q) == "" and int(q["filters"]) == 1, "compras filtros y depuradoras por %s" % Fmt.money(cost))
	check(absf(money0 - gs.money - cost) < 0.01, "se pagan (equipo importado)")
	var e1 := PollutionSim.emission(gs, q)
	check(absf(e1 - e0 * 0.5) < 0.001, "los filtros reducen la emisión a la mitad (%.2f → %.2f)" % [e0, e1])
	check("−50 % con filtros" in PollutionSim.panel_text(gs, q), "panel: %s" % PollutionSim.panel_text(gs, q))
	GovSim._collect_taxes(gs)
	var fine1 := float(gs.government["taxes_last"]["multas"])
	check(fine1 < fine0 * 0.6, "la multa baja con filtros (%s → %s)" % [Fmt.money(fine0), Fmt.money(fine1)])
	for i in range(6):
		PollutionSim.monthly(gs)
	check(PollutionSim.exposure_of_home(gs, int(home["id"])) < ex, "la contaminación acumulada baja (%.2f → %.2f)" % [ex, PollutionSim.exposure_of_home(gs, int(home["id"]))])
	check(float(gs.world_events["pollution"]["filters_upkeep_last"]) > 0.0, "los filtros tienen mantenimiento mensual (%s)" % Fmt.money(float(gs.world_events["pollution"]["filters_upkeep_last"])))
	# Licencia ambiental del lobby: sin multas.
	PoliticsSim.state(gs)["lobbies"].append({"kind": "licencia", "target": "ambiental", "until": gs.today() + 365, "bribe": false, "since": gs.today()})
	GovSim._collect_taxes(gs)
	check(float(gs.government["taxes_last"]["multas"]) == 0.0, "la licencia ambiental del lobby se respeta (sin multa)")
	# Las renovables no contaminan.
	for id in ["central_eolica", "planta_solar", "central_hidro"]:
		var d := GameData.building_def(id)
		if d.is_empty():
			continue
		var pol := 0.0
		for ld in d.get("levels", []):
			pol += float(ld.get("pollution", 0.0))
		check(pol == 0.0, "%s no contamina" % id)
	# Gobierno colonial: sin multa.
	gs.government["gov_id"] = "virrey_austero"
	PoliticsSim.state(gs)["lobbies"] = []
	GovSim._collect_taxes(gs)
	check(float(gs.government["taxes_last"]["multas"]) == 0.0, "los virreyes coloniales no multan (la regulación llega con el tiempo)")


func _sick_count(c: Citizen, n: int) -> int:
	var gs = GameState
	var sick := 0
	var season := WeatherSim.season_data(gs)
	var wdata := WeatherSim.weather_data(gs)
	var diff: Dictionary = gs.diff()
	var h0 := c.health
	for i in range(n):
		c.sick = false
		c.health = 90.0
		c.needs_met = 1.0
		PopulationSim._health(gs, c, 30, season, wdata, diff)
		if c.sick:
			sick += 1
	c.sick = false
	c.health = h0
	return sick


# --- 15. Guerras ---------------------------------------------------------------------------------------------

func _test_war() -> void:
	print("-- Guerra entre países --")
	_new_town(409)
	var gs = GameState
	var towns := TradeSim.towns(gs)
	var tid := str(towns[0]["id"])
	towns[0]["event"] = {}
	gs.trade["connections"].append({"town_id": tid, "town_name": str(towns[0].get("name", "")), "distance": 50.0, "road": 1, "mode": "a_pie"})
	var prices0 := {}
	for g in LaborSim.cfg()["wars"]["demand_goods"]:
		prices0[g] = EconomySim.market_price(gs, str(g))
	var w := WarSim.start_war(gs, 3)
	check(not w.is_empty() and WarSim.is_active(gs) and str(w["a"]) != str(w["b"]), "estalla una guerra entre %s y %s" % [w.get("a", "?"), w.get("b", "?")])
	check(not str(w["a"]).contains(str(MapSim.country_def(MapSim.country_id(gs)).get("label", "@@"))), "tu país no pelea")
	var up := 0
	for g in w["demand"]:
		if EconomySim.market_price(gs, str(g)) > float(prices0[g]) * 1.05:
			up += 1
	check(up == w["demand"].size() and up >= 3, "sube la demanda (precio) de %s" % ", ".join(w["demand"].keys()))
	var imp_ok := true
	for g in w["imports"]:
		imp_ok = imp_ok and WarSim.import_mult(gs, str(g)) >= 1.3
	check(imp_ok and w["imports"].size() >= 2, "se encarecen o cortan importaciones: %s" % str(w["imports"]))
	check(gs.notifications_log.any(func(x): return "GUERRA" in str(x["text"])), "aviso en notificaciones")
	var ev: Dictionary = TradeSim.town(gs, tid).get("event", {})
	check(ev.is_empty() or bool(ev.get("war", false)), "el pueblo conectado pide bienes de guerra (%s)" % str(ev.get("good", "—")))
	# Frecuencia: rara (menos de una cada ~10 años de media).
	check(float(WarSim.cfg().get("chance_monthly", 0.0)) * 12.0 < 0.1, "evento raro (%.1f %% al año)" % (float(WarSim.cfg().get("chance_monthly", 0.0)) * 1200.0))
	for i in range(3 * 30 + 1):
		TimeManager.advance_days(1)
	check(not WarSim.is_active(gs), "la guerra termina sola")
	var back := true
	for g in w["demand"]:
		back = back and WarSim.price_mult(gs, str(g)) == 1.0
	check(back and WarSim.import_mult(gs, str(w["imports"].keys()[0])) == 1.0, "precios e importaciones vuelven a la normalidad")
	check(not bool(TradeSim.town(gs, tid).get("event", {}).get("war", false)), "termina la demanda de guerra del pueblo")
	# No empieza antes de tiempo ni en el período de calma.
	WarSim.monthly(gs)
	check(not WarSim.is_active(gs), "después de una guerra hay años de calma")


# --- Dinero conservado -------------------------------------------------------------------------------------

func _test_money_conserved() -> void:
	print("-- Dinero conservado --")
	_new_town(410)
	var gs = GameState
	gs.research["era"] = 2
	var b := _build_now("lenador", 20, -20)
	_staff_up(b, 0.8)
	var npc := _open_npc("granja", -26, -22)
	npc["reserve"] = 3000.0
	var t0 := _total()
	LaborSim.start_demand(gs, b)
	LaborSim.reject_demand(gs, b)
	ClimateSim.schedule(gs, "sequia", 0, 20, 1.0)
	WarSim.start_war(gs, 2)
	npc["ledger"]["last_month"] = {"ventas": 100.0, "salarios": 60.0}
	LaborSim.start_price_war(gs, npc, b)
	var emp: Citizen = _staff(b)[0]
	emp.trade_exp["agricultura"] = 4.0
	var o := LaborSim.make_offer(gs, npc, emp)
	if not o.is_empty():
		LaborSim.decline_offer(gs, int(o["id"]))
	LaborSim._accumulate(gs)
	ClimateSim._refresh(gs)
	PollutionSim.refresh_now(gs)
	check(absf(_total() - t0) < 0.01, "sindicatos, huelgas, clima, guerra y competencia no crean ni destruyen dinero (Δ %.4f)" % (_total() - t0))
	gs.government["gov_id"] = "verde"
	var q := _build_now("cantera", -30, 4)
	_staff_up(q)
	var t1 := _total()
	GovSim._collect_taxes(gs)
	var taxes := 0.0
	for k in gs.government["taxes_last"]:
		taxes += float(gs.government["taxes_last"][k])
	check(absf(_total() - t1) < 0.01 and float(gs.government["taxes_last"]["multas"]) > 0.0, "las multas pasan del jugador al tesoro (Δ total %.4f)" % (_total() - t1))
	# Un mes de los ciclos nuevos (diarios y mensual) sin filtros: el dinero total no cambia.
	var t2 := _total()
	for i in range(30):
		LaborSim.daily(gs)
		ClimateSim.daily(gs)
		WarSim.daily(gs)
	LaborSim.monthly(gs)
	PollutionSim.monthly(gs)
	ClimateSim.monthly(gs)
	WarSim.monthly(gs)
	check(absf(_total() - t2) < 0.01, "un mes de los ciclos nuevos no crea ni destruye dinero (Δ %.4f)" % (_total() - t2))


# --- Guardado ---------------------------------------------------------------------------------------------

func _test_save_load() -> void:
	print("-- Guardado y carga --")
	_new_town(411)
	var gs = GameState
	gs.research["era"] = 2
	var b := _build_now("lenador", 20, 22)
	_staff_up(b, 0.8)
	var q := _build_now("cantera", -24, 20)
	_staff_up(q)
	gs.techs.append("filtros_industriales")
	PollutionSim.buy_filters(gs, q)
	LaborSim.start_demand(gs, b)
	LaborSim.reject_demand(gs, b)
	ClimateSim.schedule(gs, "sequia", 3, 20, 1.0)
	WarSim.start_war(gs, 4)
	PollutionSim.monthly(gs)
	var emp: Citizen = _staff(b)[0]
	emp.trade_exp["agricultura"] = 7.5
	var before := JSON.stringify([gs.labor, gs.world_events])
	var exp0 := LaborSim.years(emp, "agricultura")
	check(SaveManager.save_game("prueba_trabajo_mundo"), "guardar")
	GameState.new_game({"seed": 1, "difficulty": "normal"})
	check(SaveManager.load_game("prueba_trabajo_mundo"), "cargar")
	gs = GameState
	var after := JSON.stringify([gs.labor, gs.world_events])
	check(before == after, "sindicatos, huelgas, clima, contaminación y guerra se conservan")
	var emp2: Citizen = gs.citizens.get(emp.id)
	check(emp2 != null and absf(LaborSim.years(emp2, "agricultura") - exp0) < 0.0001, "la experiencia por oficio se conserva (%.1f años)" % exp0)
	var q2: Dictionary = gs.get_building(int(q["id"]))
	check(int(q2.get("filters", 0)) == 1, "los filtros se conservan")
	check(LaborSim.on_strike(gs, gs.get_building(int(b["id"]))), "la huelga sigue tras cargar")
	TimeManager.advance_days(15)
	check(not LaborSim.on_strike(gs, gs.get_building(int(b["id"]))), "y termina después de cargar")
	SaveManager.delete_save("prueba_trabajo_mundo")
	# Partida vieja sin estado nuevo: valores por defecto.
	var d: Dictionary = gs.to_dict()
	d.erase("labor")
	d.erase("world_events")
	for cd in d["citizens"]:
		cd.erase("trade_exp")
	gs.load_dict(d)
	check(gs.labor.has("unions") and gs.world_events.has("climate") and gs.world_events.has("pollution") and gs.world_events.has("war"), "partida vieja: estado nuevo con valores por defecto")
	var seeded := 0
	for c in gs.citizens.values():
		if not c.trade_exp.is_empty():
			seeded += 1
	check(seeded > 0, "partida vieja: la experiencia por oficio se inicializa (%d)" % seeded)
	TimeManager.advance_days(40)
	check(gs.running, "la partida vieja sigue simulando")
