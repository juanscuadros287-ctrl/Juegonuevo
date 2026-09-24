extends Node
## Pruebas de las redes de servicios públicos: cables (aéreo/subterráneo), reparto por red, industria
## que exige electricidad, casas altas, facturas, pozos, toma de río, tubería y guardado.
## godot --headless res://tests/test_redes.tscn

var failures := 0
var gs = GameState


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func _ready() -> void:
	print("== Dinastía: redes eléctricas y de agua ==")
	_test_connectivity()
	_test_two_networks()
	_test_requires_power()
	_test_underground_and_storms()
	_test_high_home()
	_test_power_bills()
	_test_wells()
	_test_river()
	_test_pipes()
	_test_save_load()
	_test_migration()
	print("== %s (%d fallos) ==" % ["TODO OK" if failures == 0 else "CON FALLOS", failures])
	get_tree().quit(1 if failures > 0 else 0)


# --- Utilidades ---------------------------------------------------------------------------------

func _new(seed_value := 801, opts := {}) -> void:
	var o := {"seed": seed_value, "difficulty": "facil", "map_type": "interior"}
	o.merge(opts, true)
	gs.new_game(o)
	gs.suppress_notifications = true
	gs.money = 500000.0


func _techs(list: Array) -> void:
	gs.research["era"] = 3
	for t in list:
		if not gs.techs.has(t):
			gs.techs.append(t)


func _place(type_id: String, x: float, z: float, level := 1, owner := "jugador") -> Dictionary:
	var b: Dictionary = ConstructionSim.make_building(gs, type_id, level, x, z, 0.0, owner)
	gs.add_building(b)
	WarehouseSim.relink_all(gs)
	return b


func _hire(b: Dictionary, n: int) -> int:
	var ld: Dictionary = gs.level_def(b)
	var prof := str(ld.get("required_profession", ""))
	var hired := 0
	for c in BusinessSim.candidates(gs, b):
		if hired >= n:
			break
		if c.job_kind == "obra":
			continue
		c.education = maxi(c.education, int(ld.get("min_education", 0)))
		if prof != "":
			c.profession = prof
		if BusinessSim.hire(gs, b, c, BusinessSim.asked_wage(gs, c, str(b["type"])) * 1.1) == "":
			hired += 1
	return hired


func _seg(ax: float, az: float, bx: float, bz: float, kind := "aereo") -> Dictionary:
	return GridSim.add_segment(gs, Vector2(ax, az), Vector2(bx, bz), kind)


func _energy_day() -> void:
	EnergySim.state(gs)["day"] = -1
	EnergySim.daily(gs)


func _give_money(amount: float) -> void:
	for c in gs.citizens.values():
		if not gs.is_player(c.id):
			c.money += amount


func _stock_inputs(b: Dictionary, qty := 60.0) -> void:
	var inputs := LogisticsSim.recipe_inputs(gs.building_def(b), gs.level_def(b))
	for g in inputs:
		WarehouseSim.add_to(gs, WarehouseSim.PLAZA, str(g), qty)
		b["inventory"][str(g)] = float(b["inventory"].get(str(g), 0.0)) + qty
	if EnergySim.is_plant(gs.building_def(b)):
		for g in ["carbon"]:
			b["inventory"][g] = float(b["inventory"].get(g, 0.0)) + qty


func _total_money() -> float:
	var t: float = gs.money
	for c in gs.citizens.values():
		if not gs.is_player(c.id):
			t += c.money
	for b in gs.buildings:
		t += float(b.get("reserve", 0.0))
	return t


# --- Conectividad --------------------------------------------------------------------------------

func _test_connectivity() -> void:
	print("  -- Conectividad por tramos --")
	_new(801)
	_techs(["dinamo"])
	var plant := _place("central_carbon", -30, 50)
	var tex := _place("textil", 30, 50, 3)
	var far := _place("textil", 30, 110, 3)
	var s1 := _seg(-30, 50, 0, 50)
	_seg(0, 50, 30, 50)
	var np := GridSim.net_of(gs, plant, GridSim.POWER)
	check(np >= 0 and np == GridSim.net_of(gs, tex, GridSim.POWER), "la central y la fábrica quedan en la misma red por dos tramos unidos (red %d)" % np)
	check(GridSim.net_of(gs, far, GridSim.POWER) < 0, "una fábrica lejos del cable no está conectada")
	check(GridSim.edge_distance(gs, 30, 50 + 14, 6.0, GridSim.POWER) <= GridSim.reach(GridSim.POWER), "a %d m del borde cuenta como cerca" % int(GridSim.reach(GridSim.POWER)))
	GridSim.remove(gs, int(s1["id"]))
	check(GridSim.net_of(gs, plant, GridSim.POWER) < 0 and GridSim.net_of(gs, tex, GridSim.POWER) >= 0, "al quitar el tramo la central queda aislada")
	# Un tramo que cruza otro también los une.
	_seg(-30, 50, 10, 50)
	_seg(5, 30, 5, 70)
	var comps := GridSim.components(gs, GridSim.POWER)
	check((comps["info"] as Dictionary).size() == 1, "tramos que se tocan o cruzan forman una sola red")
	check(GridSim.block_reason(gs, Vector2(0, 0), Vector2(0, 90), "aereo").begins_with("Tramo demasiado largo"), "tramos de máximo %d m" % int(GridSim.grid_cfg().get("max_length", 60)))
	var m0: float = gs.money
	var err := GridSim.build(gs, Vector2(-20, -20), Vector2(-20, 10), "aereo")
	check(err == "" and gs.money < m0 and absf((m0 - gs.money) - 30.0 * GridSim.cost_per_m(gs, "aereo")) < 0.01, "tender 30 m de cable aéreo cuesta %s (%s/m)" % [Fmt.money(m0 - gs.money), Fmt.money2(GridSim.cost_per_m(gs, "aereo"))])
	gs.techs.erase("dinamo")
	check(GridSim.block_reason(gs, Vector2(-20, -20), Vector2(-20, 0), "aereo").begins_with("Requiere investigar"), "sin el dínamo no hay tendido eléctrico")


func _test_two_networks() -> void:
	print("  -- Dos redes separadas --")
	_new(802)
	_techs(["dinamo"])
	var plant := _place("central_carbon", -35, 60)
	_hire(plant, 8)
	_stock_inputs(plant)
	var a := _place("textil", -5, 60, 3)
	_hire(a, 8)
	var b := _place("textil", 40, 60, 3)
	_hire(b, 8)
	WarehouseSim.add_to(gs, WarehouseSim.PLAZA, "carbon", 200.0)
	_seg(-35, 60, -5, 60)
	_seg(30, 60, 50, 60)
	for x in [a, b]:
		for g in LogisticsSim.recipe_inputs(gs.building_def(x), gs.level_def(x)):
			x["inventory"][str(g)] = 300.0
	GridSim.daily(gs)   # acometidas
	check(GridSim.connected(gs, a, GridSim.POWER) and GridSim.connected(gs, b, GridSim.POWER), "las dos fábricas pagaron su acometida y quedan conectadas")
	check(GridSim.net_of(gs, a, GridSim.POWER) != GridSim.net_of(gs, b, GridSim.POWER), "son dos redes distintas")
	BusinessSim.produce(gs)
	var e := float(plant["inventory"].get("electricidad", 0.0))
	_energy_day()
	check(e > 0.0 and is_equal_approx(EnergySim.supply_ratio(gs, a), 1.0), "la red con central abastece a su fábrica (cobertura %d%%)" % int(EnergySim.supply_ratio(gs, a) * 100))
	check(EnergySim.supply_ratio(gs, b) < 0.01, "la red sin central no recibe nada de la otra (cobertura %d%%)" % int(EnergySim.supply_ratio(gs, b) * 100))
	var nets: Array = GridSim.state(gs)["nets"][GridSim.POWER]
	check(nets.size() == 2, "el panel ve 2 redes con su generación y demanda")
	# Una red conectada a la plaza con ruta comercial compra a la red regional.
	_techs(["electricidad"])
	var conns: Array = gs.trade.get("connections", [])
	conns.append({"town_id": "x", "distance": 60.0, "transport": "carreta"})
	gs.trade["connections"] = conns
	_seg(30, 60, 20, 10)
	_seg(20, 10, 0, 0)
	BusinessSim.produce(gs)
	_energy_day()
	check(is_equal_approx(EnergySim.supply_ratio(gs, b), 1.0), "al tocar la plaza (entrada regional) la red compra lo que falta a la red regional")


func _test_requires_power() -> void:
	print("  -- Industria que exige electricidad --")
	_new(803)
	_techs(["dinamo", "electricidad"])
	var f := _place("fabrica_electronica", 60, 0)
	check(EnergySim.requires_power(gs.level_def(f)), "el taller eléctrico tiene requires_power")
	var nh := _hire(f, 8)
	_stock_inputs(f)
	var tex := _place("textil", -22, 0, 3)
	_hire(tex, 8)
	_stock_inputs(tex)
	BusinessSim.produce(gs)
	var made := float(f.get("produced_today", 0.0))
	var made_t := float(tex.get("produced_today", 0.0))
	_energy_day()
	check(made > 0.0 and float(f.get("produced_today", 0.0)) < 0.001, "sin cable la industria eléctrica NO produce (%.2f → %.2f; %d empleados, %s)" % [made, float(f.get("produced_today", 0.0)), nh, str(f.get("chain_status", ""))])
	check(absf(float(tex.get("produced_today", 0.0)) - made_t * 0.5) < 0.05 * made_t + 0.01, "la textil moderna (sin requires_power) rinde la mitad")
	check(is_equal_approx(EnergySim.factor(gs, f), 0.0), "factor 0 para la industria eléctrica sin cobertura")
	check(GridSim.panel_lines(gs, f).contains("sin conexión") and GridSim.panel_lines(gs, f).contains("NO produce"), "el panel avisa: %s" % GridSim.panel_lines(gs, f).strip_edges())
	var plant := _place("central_carbon", 60, 40)
	_hire(plant, 8)
	_stock_inputs(plant)
	WarehouseSim.add_to(gs, WarehouseSim.PLAZA, "carbon", 200.0)
	_seg(60, 40, 60, 5)
	GridSim.daily(gs)
	BusinessSim.produce(gs)
	made = float(f.get("produced_today", 0.0))
	_energy_day()
	check(made > 0.0 and is_equal_approx(float(f.get("produced_today", 0.0)), made), "con cable a una central produce completo")
	check(GridSim.panel_lines(gs, f).contains("conectado"), "panel: %s" % GridSim.panel_lines(gs, f).strip_edges())


func _test_underground_and_storms() -> void:
	print("  -- Cable subterráneo y tormentas --")
	_new(804)
	_techs(["dinamo"])
	check(GridSim.block_reason(gs, Vector2(-20, 20), Vector2(20, 20), "subterraneo").begins_with("Requiere investigar"), "el cable subterráneo está bloqueado sin Redes eléctricas")
	check(GridSim.build(gs, Vector2(-20, 20), Vector2(20, 20), "subterraneo") != "" and GridSim.segments(gs).is_empty(), "no se puede tender sin la tecnología")
	_techs(["redes_electricas"])
	check(GridSim.block_reason(gs, Vector2(-20, 20), Vector2(20, 20), "subterraneo") == "", "con Redes eléctricas sí")
	check(GridSim.cost_per_m(gs, "subterraneo") > GridSim.cost_per_m(gs, "aereo") * 2.0, "el subterráneo cuesta más (%s vs %s por m)" % [Fmt.money2(GridSim.cost_per_m(gs, "subterraneo")), Fmt.money2(GridSim.cost_per_m(gs, "aereo"))])
	var loss_air := float(GridSim.kind_def("aereo").get("loss_per_100m", 0.0))
	var loss_under := float(GridSim.kind_def("subterraneo").get("loss_per_100m", 0.0))
	check(loss_under < loss_air, "y pierde menos energía por metro")
	for i in range(5):
		_seg(-60 + i * 25, -80, -60 + i * 25 + 24, -80, "aereo")
		_seg(-60 + i * 25, -110, -60 + i * 25 + 24, -110, "subterraneo")
	var broke_air := false
	var broke_under := false
	for d in range(90):
		gs.weather["type"] = "tormenta"
		GridSim._storms(gs, GridSim.state(gs), 1000 + d)
		for s in GridSim.segments(gs):
			if GridSim.is_broken(s):
				if str(s["kind"]) == "aereo":
					broke_air = true
				else:
					broke_under = true
		if broke_air:
			break
	check(broke_air and not broke_under, "las tormentas tumban el tendido aéreo pero no el subterráneo")
	var m0: float = gs.money
	GridSim._repairs(gs, GridSim.state(gs), 999999)
	check(GridSim.segments(gs).filter(func(s): return GridSim.is_broken(s)).is_empty() and gs.money < m0, "los tramos caídos se reparan y la reparación se paga")


# --- Casas altas ---------------------------------------------------------------------------------

func _test_high_home() -> void:
	print("  -- Vivienda de nivel alto --")
	_new(805)
	_techs(["dinamo", "electricidad", "arquitectura_urbana", "adobe", "ladrillo"])
	var h := _place("vivienda", 30, -30, 4)
	var rent_full := float(h["rent"]) / 30.0
	var q_full := float(gs.level_def(h).get("quality", 1.0))
	check(GridSim.home_missing(gs, h).has(GridSim.POWER), "un edificio de apartamentos sin cable exige electricidad")
	check(MarketSim.daily_rent(gs, h) < rent_full * 0.99, "sin cable la renta baja (%s → %s por día)" % [Fmt.money2(rent_full), Fmt.money2(MarketSim.daily_rent(gs, h))])
	check(MarketSim.home_quality(gs, h) < q_full, "y la calidad de la vivienda baja (%.2f < %.2f)" % [MarketSim.home_quality(gs, h), q_full])
	var low := _place("vivienda", -30, -30, 3)
	var r := ConstructionSim.start_upgrade(gs, low)
	check(r.contains("conexión eléctrica"), "no se puede subir a apartamentos sin cable cerca: %s" % r)
	# Inquilinos se van.
	var fam := []
	for c in gs.citizens.values():
		if not gs.is_player(c.id) and fam.size() < 4:
			c.home_id = int(h["id"])
			fam.append(c)
	var miss: Dictionary = GridSim.grid_cfg()["missing"]
	var old_chance := float(miss["leave_chance"])
	miss["leave_chance"] = 1.0
	GridSim._tenants_leave(gs, GridSim.state(gs))
	miss["leave_chance"] = old_chance
	check(fam.all(func(c): return c.home_id == -1), "los inquilinos de la casa alta sin luz se van")
	# Con cable (y central) se arregla.
	var plant := _place("central_carbon", 30, 10)
	_seg(30, 10, 30, -30)
	_seg(30, -30, -30, -30)
	GridSim.daily(gs)
	check(GridSim.is_hooked(gs, h, GridSim.POWER), "la acometida de la casa del jugador se cobra al dueño")
	check(GridSim.home_missing(gs, h).is_empty() and is_equal_approx(MarketSim.daily_rent(gs, h), rent_full), "con cable conectado a una central la renta vuelve a ser completa")
	check(ConstructionSim.start_upgrade(gs, low) == "", "con cable cerca ya se puede mejorar a apartamentos")
	check(not plant.is_empty(), "central de la red")


# --- Facturas ------------------------------------------------------------------------------------

func _power_town() -> Dictionary:
	_techs(["dinamo", "electricidad"])
	var plant := _place("central_carbon", -20, -30)
	_hire(plant, 8)
	_stock_inputs(plant, 300.0)
	WarehouseSim.add_to(gs, WarehouseSim.PLAZA, "carbon", 400.0)
	# Cable por el pueblo (las chozas iniciales rodean la plaza).
	_seg(-20, -30, -20, 0)
	_seg(-20, 0, -20, 22)
	_seg(-20, 22, 20, 22)
	_seg(20, 22, 20, -22)
	_seg(20, -22, -20, -22)
	_seg(-20, -22, -20, -30)
	_give_money(100.0)
	GridSim.daily(gs)
	return plant


func _test_power_bills() -> void:
	print("  -- Facturas eléctricas --")
	_new(806)
	var plant := _power_town()
	var hooked := 0
	for b in gs.buildings:
		if Housing.is_home(b) and GridSim.is_hooked(gs, b, GridSim.POWER):
			hooked += 1
	check(hooked > 0, "%d casas pagaron su acometida (la paga el residente)" % hooked)
	var v0 := BusinessSim.period_value(plant, "total", "ventas")
	for d in range(5):
		BusinessSim.produce(gs)
		_energy_day()
		BusinessSim.end_day(gs)
	var st: Dictionary = EnergySim.state(gs).get("today", {})
	check(int(st.get("homes", {}).get("powered", 0)) > 0, "los hogares conectados tienen luz (%d con luz, %d sin)" % [int(st.get("homes", {}).get("powered", 0)), int(st.get("homes", {}).get("unpowered", 0))])
	var bills: Dictionary = GridSim.state(gs)["bills"][GridSim.POWER]
	check(not bills.is_empty(), "el consumo se acumula en la factura del mes (%d clientes, %s pendientes)" % [bills.size(), Fmt.money(GridSim._pending(GridSim.state(gs), GridSim.POWER))])
	var pending := GridSim._pending(GridSim.state(gs), GridSim.POWER)
	var total0 := _total_money()
	var v1 := BusinessSim.period_value(plant, "total", "ventas")
	GridSim._bill(gs, GridSim.state(gs), GridSim.POWER)
	var total1 := _total_money()
	check(absf(total1 - total0) < 0.01, "la factura no crea ni destruye dinero (%.4f → %.4f)" % [total0, total1])
	check(BusinessSim.period_value(plant, "total", "ventas") - v1 > pending * 0.9 and v1 >= v0, "la central cobra las facturas (%s)" % Fmt.money(BusinessSim.period_value(plant, "total", "ventas") - v1))
	check(GridSim.state(gs)["bills"][GridSim.POWER].is_empty(), "la factura se reinicia cada mes")
	# Tarifa configurable y corte por impago.
	GridSim.set_tariff(gs, GridSim.POWER, 9.0)
	check(is_equal_approx(GridSim.tariff(gs, GridSim.POWER), float(GridSim.grid_cfg()["tariff_max"])), "la tarifa se limita a %.1f × precio" % float(GridSim.grid_cfg()["tariff_max"]))
	GridSim.set_tariff(gs, GridSim.POWER, 1.5)
	var poor: Citizen = null
	for k in GridSim.state(gs)["cut"][GridSim.POWER]:
		poor = gs.citizens.get(int(k))
	if poor == null:
		for c in gs.citizens.values():
			var home: Dictionary = gs.get_building(c.home_id)
			if not gs.is_player(c.id) and c.age_years(gs.today()) >= 16 and GridSim.connected(gs, home, GridSim.POWER):
				poor = c
				break
		poor.money = 0.0
		BusinessSim.produce(gs)
		_energy_day()
		GridSim._bill(gs, GridSim.state(gs), GridSim.POWER)
	check(poor != null and GridSim.state(gs)["cut"][GridSim.POWER].has(str(poor.id)), "quien no paga queda cortado el mes siguiente")
	# Balance: las facturas no quiebran al jugador (él no paga luz de su casa ni de sus fábricas a sí mismo).
	var m0: float = gs.money
	GridSim._upkeep(gs, GridSim.state(gs))
	check(m0 - gs.money < 20.0, "mantenimiento mensual del tendido moderado (%s por %d m)" % [Fmt.money(m0 - gs.money), int(GridSim.total_length(gs))])


# --- Agua ----------------------------------------------------------------------------------------

func _test_wells() -> void:
	print("  -- Pozos comunitarios --")
	_new(807)
	check(is_equal_approx(WaterSim.well_factor(gs), 1.0) and WaterSim.well_count(gs) == 1, "al inicio hay un pozo en la plaza y alcanza")
	var m0: float = gs.money
	TimeManager.advance_days(3)
	var w: Dictionary = GridSim.state(gs)["well"]
	check(float(w.get("users_prev", 0.0)) > 0.0, "los vecinos sacan agua gratis del pozo (%.0f personas-día)" % float(w.get("users_prev", 0.0)))
	check(EconomySim.market_price(gs, "agua") > 0.0 and gs.money <= m0 + 1.0, "el pozo no cuesta dinero a nadie")
	WaterSim.record_well_use(gs, 400.0)
	GridSim.state(gs)["well"]["day"] = -1
	WaterSim.daily(gs)
	check(WaterSim.well_factor(gs) < 0.5 and WaterSim.well_mult(gs) < 0.8, "con más gente que pozos el agua escasea (abasto %d%%, calidad ×%.2f)" % [int(WaterSim.well_factor(gs) * 100), WaterSim.well_mult(gs)])
	var some: Citizen = gs.citizens.values()[2]
	check(WaterSim.disease_mult(gs, some) > 1.0, "y hay más enfermedades (×%.2f)" % WaterSim.disease_mult(gs, some))
	var cap0 := WaterSim.well_capacity(gs)
	_place("pozo_comunitario", 14, 14)
	check(WaterSim.well_capacity(gs) > cap0 and WaterSim.well_count(gs) == 2, "un pozo comunitario nuevo amplía el abasto (%d → %d personas)" % [int(cap0), int(WaterSim.well_capacity(gs))])


func _river_spot() -> Vector2:
	for z in [0.0, 20.0, -20.0, 40.0]:
		for i in range(60):
			var x := 20.0 + i * 2.0
			if WaterSim.height_at(gs, x, z) > float(GameData.map_type("rio").get("water_level", 0.0)) + 0.8 and WaterSim.fresh_water_near(gs, x, z):
				return Vector2(x, z)
	return Vector2(INF, INF)


func _test_river() -> void:
	print("  -- Toma de río --")
	_new(808, {"map_type": "costa"})
	check(WaterSim.placement_block_reason(gs, "toma_rio", 30, 0).begins_with("Solo en mapas"), "en la costa no hay agua dulce para la toma")
	_new(808, {"map_type": "rio"})
	check(WaterSim.placement_block_reason(gs, "toma_rio", -60, 0) != "", "lejos del río no se puede: %s" % WaterSim.placement_block_reason(gs, "toma_rio", -60, 0))
	var p := _river_spot()
	check(p.x < INF and WaterSim.placement_block_reason(gs, "toma_rio", p.x, p.y) == "", "junto al río sí (%.0f, %.0f)" % [p.x, p.y])
	check(WaterSim.placement_block_reason(gs, "aguatero", -60, 0) == "", "el aguatero se construye en cualquier parte")
	var toma := _place("toma_rio", p.x, p.y)
	_hire(toma, 3)
	gs.money = 500000.0
	_give_money(30.0)
	TimeManager.advance_days(4)
	check(BusinessSim.period_value(toma, "total", "ventas") > 0.0, "la toma de río vende agua a los vecinos (%s)" % Fmt.money(BusinessSim.period_value(toma, "total", "ventas")))


func _test_pipes() -> void:
	print("  -- Planta de agua y tubería --")
	_new(809)
	check(GridSim.block_reason(gs, Vector2(0, 30), Vector2(20, 30), "tuberia").begins_with("Requiere investigar"), "la tubería exige Potabilización")
	_techs(["acueductos", "potabilizacion"])
	var plant := _place("planta_agua", 32, 32)
	_hire(plant, 4)
	_seg(32, 32, 20, 20, "tuberia")
	_seg(20, 20, 20, -22, "tuberia")
	_seg(20, -22, -20, -22, "tuberia")
	_seg(-20, -22, -20, 22, "tuberia")
	_seg(-20, 22, 20, 20, "tuberia")
	_give_money(60.0)
	GridSim.daily(gs)
	var piped := []
	for b in gs.buildings:
		if Housing.is_home(b) and WaterSim.home_piped(gs, b):
			piped.append(b)
	check(not piped.is_empty(), "%d casas conectadas a la tubería de la planta" % piped.size())
	var h: Dictionary = piped[0] if not piped.is_empty() else {}
	var base_q := float(gs.level_def(h).get("quality", 1.0)) + float(Housing.tier_def(h).get("quality_add", 0.0))
	check(MarketSim.home_quality(gs, h) > base_q, "el agua por tubería mejora la calidad de la vivienda")
	var resident: Citizen = null
	for c in gs.residents_of(int(h["id"])):
		resident = c
	check(resident != null and WaterSim.disease_mult(gs, resident) < 1.0, "y reduce las enfermedades (×%.2f)" % (WaterSim.disease_mult(gs, resident) if resident != null else 1.0))
	TimeManager.advance_days(4)
	var bills: Dictionary = GridSim.state(gs)["bills"][GridSim.WATER]
	check(not bills.is_empty() and float(GridSim.state(gs)["month"].get("piped_units", 0.0)) > 0.0, "las casas conectadas toman agua de la planta (%d clientes, %.0f u.)" % [bills.size(), float(GridSim.state(gs)["month"].get("piped_units", 0.0))])
	var total0 := _total_money()
	var v0 := BusinessSim.period_value(plant, "total", "ventas")
	GridSim._bill(gs, GridSim.state(gs), GridSim.WATER)
	check(absf(_total_money() - total0) < 0.01 and BusinessSim.period_value(plant, "total", "ventas") > v0, "la factura de agua la cobra tu planta sin crear dinero (%s)" % Fmt.money(BusinessSim.period_value(plant, "total", "ventas") - v0))
	# Casas altas exigen tubería.
	_techs(["arquitectura_urbana"])
	var tower := _place("vivienda", -34, 34, 4)
	check(GridSim.home_missing(gs, tower).has(GridSim.WATER), "un edificio de apartamentos sin tubería la exige")
	check(WaterSim.status_text(gs, tower).contains("exige tubería"), "el panel lo avisa: %s" % WaterSim.status_text(gs, tower))


# --- Guardado ------------------------------------------------------------------------------------

func _test_save_load() -> void:
	print("  -- Guardar y cargar --")
	_new(810)
	var plant := _power_town()
	_techs(["potabilizacion", "redes_electricas"])
	_seg(-30, 30, -10, 30, "tuberia")
	_seg(10, -35, 30, -35, "subterraneo")
	GridSim.set_tariff(gs, GridSim.POWER, 1.3)
	BusinessSim.produce(gs)
	_energy_day()
	var st: Dictionary = GridSim.state(gs)
	var nseg: int = (st["segments"] as Array).size()
	var nh: int = (st["hooked"][GridSim.POWER] as Dictionary).size()
	var nb: int = (st["bills"][GridSim.POWER] as Dictionary).size()
	var net_p := GridSim.net_of(gs, plant, GridSim.POWER)
	var text := JSON.stringify(gs.to_dict())
	gs.load_dict(JSON.parse_string(text))
	st = GridSim.state(gs)
	check((st["segments"] as Array).size() == nseg and (st["hooked"][GridSim.POWER] as Dictionary).size() == nh, "se guardan los tramos (%d) y las acometidas (%d)" % [nseg, nh])
	check((st["bills"][GridSim.POWER] as Dictionary).size() == nb and is_equal_approx(GridSim.tariff(gs, GridSim.POWER), 1.3), "se guardan las facturas pendientes y la tarifa")
	var plant2: Dictionary = gs.get_building(int(plant["id"]))
	check(GridSim.net_of(gs, plant2, GridSim.POWER) == net_p and not GridSim.legacy_active(gs), "la red se reconstruye igual al cargar (sin período de gracia)")
	TimeManager.advance_days(35)
	check(gs.running and not GridSim.state(gs).get("last_month", {}).is_empty(), "la simulación sigue y cierra el mes de las redes")
	var sm := GridSim.summary(gs)
	check(int(sm["customers_power"]) > 0, "se cobraron facturas al cerrar el mes (%d clientes, %s)" % [int(sm["customers_power"]), Fmt.money(float(sm["income_power"]))])


func _test_migration() -> void:
	print("  -- Partida vieja sin redes --")
	_new(811)
	_techs(["dinamo"])
	var plant := _place("central_carbon", -30, 0)
	_hire(plant, 8)
	_stock_inputs(plant, 200.0)
	var tex := _place("textil", 30, 0, 3)
	_hire(tex, 8)
	_stock_inputs(tex)
	WarehouseSim.add_to(gs, WarehouseSim.PLAZA, "carbon", 200.0)
	var d: Dictionary = gs.to_dict()
	d.erase("utilities")
	gs.load_dict(JSON.parse_string(JSON.stringify(d)))
	check(GridSim.legacy_active(gs), "una partida con centrales y sin redes recibe un período de gracia")
	GridSim.daily(gs)
	var lu := int(GridSim.state(gs)["legacy_until"])
	check(lu > gs.today(), "el período de gracia dura %d días" % (lu - gs.today()))
	tex = gs.get_building(int(tex["id"]))
	BusinessSim.produce(gs)
	_energy_day()
	check(is_equal_approx(EnergySim.supply_ratio(gs, tex), 1.0), "durante la gracia la red funciona como antes (global)")
	check(GridSim.panel_lines(gs, tex).contains("gracia"), "el panel avisa del período de gracia")
	GridSim.state(gs)["legacy_until"] = gs.today()
	BusinessSim.produce(gs)
	_energy_day()
	check(EnergySim.supply_ratio(gs, tex) < 0.01, "al terminar la gracia sin cables la fábrica queda sin electricidad")
