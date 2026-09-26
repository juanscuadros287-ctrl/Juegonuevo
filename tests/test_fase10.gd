extends Node
## Pruebas de la Fase 10: países, viajes, gerentes y aviación.
## godot --headless res://tests/test_fase10.tscn

var failures := 0
var perf_note := ""


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func _ready() -> void:
	print("== Dinastía: pruebas de la Fase 10 (países, viajes, gerentes y aviación) ==")
	_test_old_save_single_country()
	_test_license_and_entry()
	_test_travel()
	_test_manager_and_works()
	_test_domestic_plane()
	_test_international_cargo()
	_test_commercial_flight()
	_test_money_conserved()
	_test_save_load()
	_test_performance()
	await _test_ui()
	print(perf_note)
	print("== %s (%d fallos) ==" % ["TODO OK" if failures == 0 else "CON FALLOS", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _gs():
	return GameState


func _new(seed := 31) -> void:
	GameState.new_game({"seed": seed, "difficulty": "normal", "country_id": "COL", "map_type": "interior"})
	GameState.money = 400000.0
	for t in ["aviacion", "aeronautica", "carretas", "automovil"]:
		if not GameState.techs.has(t):
			GameState.techs.append(t)
	TechSim._recompute_mods(GameState)


## Licencia + terreno en Perú.
func _enter_peru() -> void:
	var gs = _gs()
	CountriesSim.buy_license(gs, "PER")
	CountriesSim.buy_entry_land(gs, "PER")


func _biz(type_id: String, x: float, z: float, level := 1) -> Dictionary:
	var gs = _gs()
	var b := ConstructionSim.make_building(gs, type_id, level, x, z, 0.0, "jugador")
	b["status"] = "activo"
	gs.add_building(b)
	return b


func _staff(b: Dictionary, n: int) -> void:
	var gs = _gs()
	for c in gs.citizens.values():
		if n <= 0:
			break
		if gs.is_player(c.id) or c.job_id >= 0 or c.age_years(gs.today()) < 18 or c.age_years(gs.today()) > 60:
			continue
		BusinessSim.hire(gs, b, c, 3.0)
		n -= 1


func _test_old_save_single_country() -> void:
	print("-- Partida vieja: un solo país --")
	_new()
	var gs = _gs()
	var d: Dictionary = gs.to_dict()
	d.erase("countries")
	for b in d["buildings"]:
		b.erase("country_id")
	gs.load_dict(d)
	check(CountriesSim.ready(gs), "se crea el estado de países al cargar")
	check(CountriesSim.presence_ids(gs) == ["COL"], "partida vieja: un solo país (%s)" % str(CountriesSim.presence_ids(gs)))
	check(CountriesSim.location(gs) == "COL" and CountriesSim.active_id(gs) == "COL", "el personaje está en su país")
	var all_marked := true
	for b in gs.buildings:
		if str(b.get("country_id", "")) != "COL":
			all_marked = false
	for c in gs.citizens.values():
		if c.country_id != "COL":
			all_marked = false
	check(all_marked, "edificios y ciudadanos ganan country_id")


func _test_license_and_entry() -> void:
	print("-- Licencia y entrada a un segundo país --")
	_new()
	var gs = _gs()
	var cost := CountriesSim.license_cost(gs, "PER")
	check(cost > 0.0 and cost != CountriesSim.license_cost(gs, "USA"), "la licencia cuesta según el país (Perú %.0f, EE. UU. %.0f)" % [cost, CountriesSim.license_cost(gs, "USA")])
	check(CountriesSim.license_block_reason(gs, "COL") != "", "no se compra licencia en el país de origen")
	gs.money = 10.0
	check(CountriesSim.license_block_reason(gs, "PER").begins_with("Dinero"), "sin dinero no hay licencia")
	gs.money = 400000.0
	check(CountriesSim.entry_land_block_reason(gs, "PER") != "", "sin licencia no se compra terreno allá")
	var m0: float = gs.money
	var r := CountriesSim.buy_license(gs, "PER")
	check(r == "", "compra la licencia de Perú (%s)" % r)
	check(is_equal_approx(gs.money, m0 - cost), "se paga la licencia")
	check(CountriesSim.has_context(gs, "PER") and not CountriesSim.has_presence(gs, "PER"), "con licencia pero sin terreno aún no hay presencia")
	var treas := float(gs.countries["stash"]["PER"]["government"]["treasury"])
	check(treas >= cost, "el pago va al tesoro de Perú")
	var info := CountriesSim.summary(gs, "PER")
	check(int(info.get("population", 0)) >= 20 and int(info.get("municipalities", 0)) > 3, "Perú tiene su mapa, municipios y pueblo (%d hab., %d municipios)" % [int(info.get("population", 0)), int(info.get("municipalities", 0))])
	check(gs.map.get("country_id", "") == "COL", "el país activo sigue siendo Colombia")
	var land := CountriesSim.entry_land_cost(gs, "PER")
	var m1: float = gs.money
	r = CountriesSim.buy_entry_land(gs, "PER")
	check(r == "", "compra el primer terreno en Perú (%s)" % r)
	check(is_equal_approx(gs.money, m1 - land), "se paga el terreno (%.0f)" % land)
	check(CountriesSim.has_presence(gs, "PER"), "ya hay presencia en Perú")
	check(CountriesSim.presence_ids(gs) == ["COL", "PER"], "países con presencia: %s" % str(CountriesSim.presence_ids(gs)))
	var owned = CountriesSim.with_country(gs, "PER", func(): return gs.is_zone_unlocked(2, 2) and MapSim.country_id(gs) == "PER")
	check(bool(owned), "el terreno es tuyo en el mapa de Perú")
	var tax = CountriesSim.with_country(gs, "PER", func(): return float(gs.government.get("tax_mult", 1.0)))
	check(is_equal_approx(float(tax), float(CountriesSim.mods("PER")["tax_mult"])), "Perú tiene su capa de impuestos (×%.2f)" % float(tax))
	# El mundo solo ve el país activo; al activar Perú se cargan sus datos.
	CountriesSim.set_active(gs, "PER")
	var ok := MapSim.country_id(gs) == "PER"
	for b in gs.buildings:
		if str(b.get("country_id", "")) != "PER":
			ok = false
	check(ok, "al activar Perú, GameState tiene solo edificios de Perú")
	CountriesSim.set_active(gs, "COL")
	check(MapSim.country_id(gs) == "COL" and gs.player_citizen() != null, "de vuelta a Colombia con el personaje y su familia")


func _test_travel() -> void:
	print("-- Viaje --")
	_new()
	var gs = _gs()
	_enter_peru()
	check(TravelSim.block_reason(gs, "ARG") != "", "no se viaja a un país sin licencia")
	var q := TravelSim.quote(gs, "COL", "PER")
	check(float(q["km"]) > 1000.0 and float(q["km"]) < 3000.0, "distancia real Colombia–Perú ≈ %d km" % int(q["km"]))
	check(int(q["days"]) >= 3, "en la época colonial toma %d días (%s)" % [int(q["days"]), q["label"]])
	var far := TravelSim.quote(gs, "COL", "JPN")
	check(float(far["cost"]) > float(q["cost"]) and int(far["days"]) > int(q["days"]), "más lejos, más caro y más largo (Japón: %d días)" % int(far["days"]))
	var out0 := float(gs.countries["stats"]["outflow"])
	var m0: float = gs.money
	var r := TravelSim.start(gs, "PER")
	check(r == "", "empieza el viaje (%s)" % r)
	check(is_equal_approx(gs.money, m0 - float(q["cost"])) and is_equal_approx(float(gs.countries["stats"]["outflow"]), out0 + float(q["cost"])), "se paga el pasaje (sale de la economía)")
	check(CountriesSim.location(gs) == "" and TravelSim.traveling(gs), "de viaje: en ningún país")
	TimeManager.advance_days(int(q["days"]) - 1)
	check(TravelSim.traveling(gs), "un día antes sigue viajando")
	TimeManager.advance_days(1)
	check(CountriesSim.location(gs) == "PER" and not TravelSim.traveling(gs), "llega a Perú después de %d días" % int(q["days"]))
	check(str(gs.countries["pending_view"]) == "PER", "la cámara debe pasar a Perú")
	check(CountriesSim.set_active(gs, "PER") == "" and MapSim.country_id(gs) == "PER", "se muestra Perú")
	# Con la tecnología de aviación el viaje es en avión y más corto.
	var old_era: int = gs.research["era"]
	gs.research["era"] = 3
	var q2 := TravelSim.quote(gs, "PER", "COL")
	check(str(q2["mode"]) == "avion" and int(q2["days"]) < int(q["days"]), "en la época moderna se viaja en avión (%d día)" % int(q2["days"]))
	gs.research["era"] = old_era


func _test_manager_and_works() -> void:
	print("-- Gerentes y obras --")
	_new()
	var gs = _gs()
	_enter_peru()
	# El personaje viaja a Perú: Colombia queda sin nadie a cargo.
	gs.countries["location"] = "PER"
	check(CountriesSim.control_block_reason(gs) != "", "vista remota de Colombia sin gerente: no se puede construir")
	check(ConstructionSim.build_block_reason(gs, "vivienda").begins_with("Vista remota"), "Construir queda bloqueado")
	var site := ConstructionSim.make_building(gs, "vivienda", 1, 60.0, 40.0, 0.0, "jugador")
	site["status"] = "construccion"
	site["work_needed"] = 200.0
	gs.add_building(site)
	TimeManager.advance_days(6)
	check(float(site["work_done"]) == 0.0, "sin gerente ni presencia la obra no avanza")
	check(is_equal_approx(ManagerSim.output_mult(gs, "COL"), float(ManagerSim.cfg()["no_manager_output"])), "los negocios rinden menos sin gerente (×%.2f)" % ManagerSim.output_mult(gs, "COL"))
	var cands := ManagerSim.candidates(gs, "COL")
	check(cands.size() >= 2, "hay candidatos a gerente (%d)" % cands.size())
	var best: Dictionary = cands[0]
	check(float(best["salary"]) > 0.0 and float(best["eff"]) > 0.6, "sueldo según el nivel (%s: %s/mes, eficiencia %d %%)" % [best["level_label"], Fmt.money(float(best["salary"])), int(float(best["eff"]) * 100)])
	check(ManagerSim.hire(gs, "COL", int(best["citizen_id"])) == "", "contrata al gerente")
	check(CountriesSim.control_block_reason(gs) == "", "con gerente se puede operar a distancia")
	TimeManager.advance_days(6)
	check(float(site["work_done"]) > 0.0, "con gerente la obra avanza (%.1f)" % float(site["work_done"]))
	check(is_equal_approx(ManagerSim.output_mult(gs, "COL"), float(best["eff"])), "su habilidad da la eficiencia")
	# Obras en Perú: allá está el personaje (avanzan); sin él ni gerente, no.
	var peru_site = CountriesSim.with_country(gs, "PER", func():
		var b := ConstructionSim.make_building(gs, "vivienda", 1, 50.0, 50.0, 0.0, "jugador")
		b["status"] = "construccion"
		b["work_needed"] = 200.0
		gs.add_building(b)
		return b)
	TimeManager.advance_days(5)
	check(float(peru_site["work_done"]) > 0.0, "en Perú, donde está el personaje, la obra avanza")
	# Sueldo mensual al bolsillo del gerente, y los eventos de lealtad.
	var m := ManagerSim.manager(gs, "COL")
	var c: Citizen = gs.citizens[int(m["citizen_id"])]
	var cm := c.money
	var pm: float = gs.money
	ManagerSim._monthly(gs, "COL", m, c)
	check(is_equal_approx(c.money - cm, float(m["salary"])) or float(m.get("stolen", 0.0)) > 0.0, "el sueldo pasa de tu cuenta al gerente")
	check(gs.money < pm, "el sueldo sale de tu cuenta")
	m["loyalty"] = 5.0
	var events := {"robo": false, "renuncia": false, "aumento": false}
	for i in range(80):
		if not ManagerSim.has_manager(gs, "COL"):
			events["renuncia"] = true
			ManagerSim.hire(gs, "COL", int(ManagerSim.candidates(gs, "COL")[0]["citizen_id"]))
		m = ManagerSim.manager(gs, "COL")
		m["loyalty"] = 5.0 if i % 2 == 0 else 60.0
		var s0 := float(m.get("stolen", 0.0))
		c = gs.citizens[int(m["citizen_id"])]
		ManagerSim._monthly(gs, "COL", m, c)
		if float(ManagerSim.manager(gs, "COL").get("stolen", 0.0)) > s0:
			events["robo"] = true
		if not (ManagerSim.manager(gs, "COL").get("raise", {}) as Dictionary).is_empty():
			events["aumento"] = true
			ManagerSim.accept_raise(gs, "COL")
	check(events["robo"] and events["renuncia"] and events["aumento"], "el gerente puede robar, renunciar y pedir aumento (%s)" % str(events))


func _test_domestic_plane() -> void:
	print("-- Avión dentro del país --")
	_new()
	var gs = _gs()
	gs.unlocked_zones.append([4, 4])
	gs.unlocked_zones.append([0, 0])
	var a := _biz("aeropuerto", 150.0, 150.0)
	var b := _biz("aeropuerto", -150.0, -150.0)
	var h := _biz("hangar", 150.0, 110.0)
	_staff(a, 2)
	_staff(b, 2)
	_staff(h, 3)
	check(WarehouseSim.capacity_of(gs, int(a["id"])) >= 3000.0, "el aeropuerto es un almacén grande (%.0f)" % WarehouseSim.capacity_of(gs, int(a["id"])))
	var res := LogisticsSim.buy_vehicle(gs, h, "avion")
	check(not res.has("error"), "compra un avión de carga en el hangar (%s)" % str(res.get("error", "")))
	var vid := int(res.get("vehicle", {}).get("id", -1))
	WarehouseSim.add_to(gs, int(a["id"]), "madera", 120.0)
	var bad := LogisticsSim.create_route(gs, {"from": int(a["id"]), "to": 0, "good": "madera", "qty": 50.0, "mode": "avion", "vehicle": vid})
	check(bad.has("error") and str(bad["error"]).contains("aeropuerto"), "el avión solo vuela entre aeropuertos")
	var r := LogisticsSim.create_route(gs, {"from": int(a["id"]), "to": int(b["id"]), "good": "madera", "qty": 120.0, "mode": "avion", "vehicle": vid})
	check(not r.has("error"), "ruta de avión entre dos aeropuertos del país: ya no hay rechazo de 'fase posterior' (%s)" % str(r.get("error", "")))
	var truck := LogisticsSim.trip_info(gs, int(a["id"]), int(b["id"]), "camion")
	var plane := LogisticsSim.trip_info(gs, int(a["id"]), int(b["id"]), "avion")
	check(float(plane["travel"]) < float(truck["travel"]), "el avión es más rápido que el camión")
	TimeManager.advance_days(2)
	check(WarehouseSim.stock_in(gs, int(b["id"]), "madera") >= 119.9, "la carga llegó en avión al otro aeropuerto (%.1f)" % WarehouseSim.stock_in(gs, int(b["id"]), "madera"))
	var auto := LogisticsSim.create_route(gs, {"from": int(b["id"]), "to": int(a["id"]), "good": "madera", "qty": 30.0, "mode": "avion", "auto": true, "every": 2})
	check(not auto.has("error"), "ruta automática de avión (%s)" % str(auto.get("error", "")))


## Colombia con aeropuerto y hangar con avión; Perú con aeropuerto. Devuelve ids.
func _setup_air() -> Dictionary:
	var gs = _gs()
	_enter_peru()
	gs.unlocked_zones.append([4, 4])
	var a := _biz("aeropuerto", 150.0, 150.0)
	var h := _biz("hangar", 150.0, 110.0)
	_staff(a, 2)
	_staff(h, 3)
	var v := LogisticsSim.buy_vehicle(gs, h, "avion")
	var p = CountriesSim.with_country(gs, "PER", func():
		var b := _biz("aeropuerto", 60.0, 60.0)
		_staff(b, 2)
		return b)
	return {"col_airport": int(a["id"]), "hangar": int(h["id"]), "plane": int(v.get("vehicle", {}).get("id", -1)), "per_airport": int(p["id"])}


func _test_international_cargo() -> void:
	print("-- Carga entre países: solo por avión, con arancel y cambio --")
	_new()
	var gs = _gs()
	var ids := _setup_air()
	WarehouseSim.add_to(gs, int(ids["col_airport"]), "madera", 300.0)
	var bad := AirSim.ship(gs, {"from_iso": "COL", "from": ids["col_airport"], "to_iso": "PER", "to": ids["per_airport"], "good": "madera", "qty": 50.0, "mode": "camion"})
	check(bad.has("error") and str(bad["error"]).contains("solo va por avión"), "entre países no va en camión")
	var bad2 := AirSim.create_route(gs, {"from_iso": "COL", "from": ids["col_airport"], "to_iso": "PER", "to": ids["per_airport"], "good": "madera", "qty": 50.0, "mode": "carreta"})
	check(bad2.has("error"), "ni por ruta automática en carreta")
	var m0: float = gs.money
	var out0 := float(gs.countries["stats"]["outflow"])
	var res := AirSim.ship(gs, {"from_iso": "COL", "from": ids["col_airport"], "to_iso": "PER", "to": ids["per_airport"], "good": "madera", "qty": 300.0, "mode": "avion"})
	check(not res.has("error"), "vuelo propio Colombia → Perú (%s)" % str(res.get("error", "")))
	if res.has("error"):
		return
	var f: Dictionary = res["flight"]
	check(float(f["qty"]) == 300.0 and WarehouseSim.stock_in(gs, int(ids["col_airport"]), "madera") < 0.01, "la carga sale del aeropuerto de origen")
	check(float(f["fuel"]) > 0.0 and is_equal_approx(gs.money, m0 - float(f["fuel"])) and is_equal_approx(float(gs.countries["stats"]["outflow"]), out0 + float(f["fuel"])), "se paga el combustible (%s)" % Fmt.money(float(f["fuel"])))
	var busy := LogisticsSim.vehicle_busy(gs, int(ids["plane"]), float(gs.today()) + 0.5)
	check(busy, "el avión queda ocupado hasta volver")
	var again := AirSim.ship(gs, {"from_iso": "COL", "from": ids["col_airport"], "to_iso": "PER", "to": ids["per_airport"], "good": "madera", "qty": 10.0, "mode": "avion"})
	check(again.has("error"), "sin aviones libres no hay otro vuelo")
	# Llegada con aduana: se mide sin simular el resto del día.
	TimeManager.advance_days(int(f["arrive"]) - gs.today() - 1)
	var m1: float = gs.money
	var t1 = CountriesSim.with_country(gs, "PER", func(): return float(gs.government["treasury"]))
	TimeManager.total_hours += 24
	AirSim.daily(gs)
	var t2 = CountriesSim.with_country(gs, "PER", func(): return float(gs.government["treasury"]))
	check(bool(f["delivered"]), "el vuelo llegó en %d días" % (int(f["arrive"]) - int(f["depart"])))
	var stock = CountriesSim.with_country(gs, "PER", func(): return WarehouseSim.stock_in(gs, int(ids["per_airport"]), "madera"))
	check(float(stock) >= 299.9, "la carga está en el aeropuerto de Perú (%.1f)" % float(stock))
	var rate := AirSim.tariff_rate(gs, "PER")
	check(rate > 0.0 and is_equal_approx(float(f["tariff_rate"]), rate), "arancel del destino %.1f %%" % (rate * 100.0))
	var fx := GlobalEconSim.fx(gs, "COL", "PER")
	check(not is_equal_approx(fx, 1.0) and is_equal_approx(float(f["fx"]), fx), "tipo de cambio COP → PEN = %.6f" % fx)
	check(is_equal_approx(float(f["value_local"]), float(f["value_dest"]) * fx), "el valor se convierte a soles (%.2f S/)" % float(f["value_local"]))
	check(is_equal_approx(float(f["tariff_local"]), float(f["value_local"]) * rate), "arancel en moneda local = valor × tasa")
	check(is_equal_approx(float(f["tariff_money"]), float(f["tariff_local"]) / fx), "y se paga convertido a tu moneda (%s)" % Fmt.money2(float(f["tariff_money"])))
	check(is_equal_approx(gs.money, m1 - float(f["tariff_money"])), "el arancel sale de tu cuenta")
	check(is_equal_approx(float(t2) - float(t1), float(f["tariff_money"])), "y entra al tesoro de Perú")
	# Ruta automática internacional.
	CountriesSim.with_country(gs, "PER", func(): WarehouseSim.add_to(gs, int(ids["per_airport"]), "madera", 50.0); return null)
	var rt := AirSim.create_route(gs, {"from_iso": "PER", "from": ids["per_airport"], "to_iso": "COL", "to": 0, "good": "madera", "qty": 40.0, "mode": "comercial", "every": 5})
	check(not rt.has("error"), "ruta automática Perú → Colombia en vuelo comercial")


func _test_commercial_flight() -> void:
	print("-- Vuelo comercial --")
	_new()
	var gs = _gs()
	_enter_peru()
	WarehouseSim.add_to(gs, 0, "madera", 190.0)
	var cap := float(AirSim.cfg()["commercial"]["capacity"])
	var km := TravelSim.distance_km("COL", "PER")
	var unit := AirSim.commercial_unit_fee(gs, km, true)
	var m0: float = gs.money
	var out0 := float(gs.countries["stats"]["outflow"])
	var res := AirSim.ship(gs, {"from_iso": "COL", "from": 0, "to_iso": "PER", "to": 0, "good": "madera", "qty": 190.0, "mode": "comercial"})
	check(not res.has("error"), "vuelo comercial sin aviones propios (%s)" % str(res.get("error", "")))
	if res.has("error"):
		return
	var f: Dictionary = res["flight"]
	check(is_equal_approx(float(f["qty"]), minf(190.0, cap)), "capacidad limitada por salida (%.0f de 190)" % float(f["qty"]))
	check(is_equal_approx(float(f["fee"]), snappedf(unit * float(f["qty"]), 0.01)) and is_equal_approx(gs.money, m0 - float(f["fee"])), "se paga por unidad (%s c/u)" % Fmt.money2(unit))
	check(is_equal_approx(float(gs.countries["stats"]["outflow"]), out0 + float(f["fee"])), "el flete sale de la economía (aerolínea)")
	var res2 := AirSim.ship(gs, {"from_iso": "COL", "from": 0, "to_iso": "PER", "to": 0, "good": "madera", "qty": 40.0, "mode": "comercial"})
	check(not res2.has("error") and int(res2["flight"]["depart"]) > int(f["depart"]), "lo que no cabe va en la siguiente salida")
	gs.unlocked_zones.append([4, 4])
	var ap := _biz("aeropuerto", 150.0, 150.0)
	WarehouseSim.add_to(gs, 0, "madera", 5.0)
	var dom := AirSim.ship(gs, {"from_iso": "COL", "from": 0, "to_iso": "COL", "to": int(ap["id"]), "good": "madera", "qty": 5.0, "mode": "comercial"})
	check(not dom.has("error") and float(dom["flight"]["fee"]) > 0.0 and float(dom["flight"]["fee"]) < float(f["fee"]), "vuelo comercial dentro del país, más barato (%s)" % str(dom.get("error", Fmt.money2(float(dom.get("flight", {}).get("fee", 0.0))))))
	var dom_arrive := int(dom.get("flight", {}).get("arrive", gs.today()))
	TimeManager.advance_days(int(res2["flight"]["arrive"]) - gs.today() + 1)
	var got = CountriesSim.with_country(gs, "PER", func(): return WarehouseSim.stock_in(gs, 0, "madera"))
	check(float(got) >= float(f["qty"]) + float(res2["flight"]["qty"]) - 0.1, "la carga llegó a la bodega de Perú (%.0f)" % float(got))
	check(float(f["tariff_money"]) > 0.0, "también paga arancel al entrar")
	check(gs.today() >= dom_arrive and WarehouseSim.stock_in(gs, int(ap["id"]), "madera") >= 4.9, "el vuelo interno llegó al aeropuerto sin arancel")


func _test_money_conserved() -> void:
	print("-- Dinero conservado --")
	_new()
	var gs = _gs()
	CountriesSim.buy_license(gs, "PER")
	var total0 := CountriesSim.money_total(gs) + float(gs.countries["stats"]["outflow"])
	CountriesSim.buy_entry_land(gs, "PER")
	var t1 := CountriesSim.money_total(gs) + float(gs.countries["stats"]["outflow"])
	check(absf(t1 - total0) < 0.01, "la compra de terreno solo mueve dinero al tesoro de Perú (%.2f)" % (t1 - total0))
	ManagerSim.hire(gs, "PER", int(ManagerSim.candidates(gs, "PER")[0]["citizen_id"]))
	CountriesSim.with_country(gs, "PER", func():
		var m := ManagerSim.manager(gs, "PER")
		ManagerSim._monthly(gs, "PER", m, gs.citizens[int(m["citizen_id"])])
		return null)
	var t2 := CountriesSim.money_total(gs) + float(gs.countries["stats"]["outflow"])
	check(absf(t2 - total0) < 0.01, "el sueldo del gerente pasa a un ciudadano de Perú (%.2f)" % (t2 - total0))
	WarehouseSim.add_to(gs, 0, "madera", 50.0)
	var res := AirSim.ship(gs, {"from_iso": "COL", "from": 0, "to_iso": "PER", "to": 0, "good": "madera", "qty": 50.0, "mode": "comercial"})
	var f: Dictionary = res.get("flight", {})
	f["arrive"] = gs.today()
	AirSim.daily(gs)
	var t3 := CountriesSim.money_total(gs) + float(gs.countries["stats"]["outflow"])
	check(bool(f.get("delivered", false)) and absf(t3 - total0) < 0.01, "flete y arancel: el flete sale (contado) y el arancel entra al tesoro (%.2f)" % (t3 - total0))
	TravelSim.start(gs, "PER")
	var t4 := CountriesSim.money_total(gs) + float(gs.countries["stats"]["outflow"])
	check(absf(t4 - total0) < 0.01, "el pasaje sale de la economía y queda contado (%.2f)" % (t4 - total0))
	check(CountriesSim.money_total(gs) > 0.0 and gs.money == gs.money, "una sola cuenta para todos los países")
	var shown := GlobalEconSim.fmt_foreign(gs, 1000.0 * GlobalEconSim.fx(gs, "COL", "PER"), "PER")
	check(shown.contains("S/") or shown.contains("≈"), "los montos de Perú se muestran convertidos: %s" % shown)


func _test_save_load() -> void:
	print("-- Guardar y cargar --")
	_new()
	var gs = _gs()
	var ids := _setup_air()
	ManagerSim.hire(gs, "PER", int(ManagerSim.candidates(gs, "PER")[0]["citizen_id"]))
	WarehouseSim.add_to(gs, int(ids["col_airport"]), "madera", 100.0)
	var sh := AirSim.ship(gs, {"from_iso": "COL", "from": ids["col_airport"], "to_iso": "PER", "to": ids["per_airport"], "good": "madera", "qty": 100.0, "mode": "avion"})
	check(not sh.has("error"), "vuelo en curso antes de guardar (%s)" % str(sh.get("error", "")))
	TravelSim.start(gs, "PER")
	check(AirSim.ship(gs, {"from_iso": "COL", "from": 0, "to_iso": "PER", "to": 0, "good": "madera", "qty": 1.0, "mode": "comercial"}).has("error"), "de viaje y sin gerente en Colombia, nadie despacha allá")
	TimeManager.advance_days(2)
	var per_pop := int(CountriesSim.summary(gs, "PER")["population"])
	var money: float = gs.money
	check(SaveManager.save_game("prueba_fase10"), "guarda la partida")
	gs.new_game({"seed": 1})
	check(SaveManager.load_game("prueba_fase10"), "carga la partida")
	gs = _gs()
	check(CountriesSim.presence_ids(gs) == ["COL", "PER"], "conserva los países con presencia")
	check(TravelSim.traveling(gs) and str(gs.countries["travel"]["to"]) == "PER", "conserva el viaje en curso")
	check(ManagerSim.has_manager(gs, "PER"), "conserva el gerente")
	check(int(CountriesSim.summary(gs, "PER")["population"]) == per_pop, "conserva la población de Perú (%d)" % per_pop)
	var cit_ok = CountriesSim.with_country(gs, "PER", func():
		for c in gs.citizens.values():
			if not (c is Citizen) or c.country_id != "PER":
				return false
		return MapSim.country_id(gs) == "PER")
	check(bool(cit_ok), "los ciudadanos de Perú se cargan como ciudadanos de Perú")
	check(is_equal_approx(gs.money, money), "la cuenta única se conserva")
	check(AirSim.st(gs)["flights"].size() >= 1, "conserva los vuelos")
	TimeManager.advance_days(10)
	check(CountriesSim.location(gs) == "PER", "tras cargar, el viaje termina en Perú")
	SaveManager.delete_save("prueba_fase10")


func _test_performance() -> void:
	print("-- Rendimiento --")
	_new(47)
	var gs = _gs()
	TimeManager.advance_days(3)
	var t0 := Time.get_ticks_usec()
	TimeManager.advance_days(30)
	var one := float(Time.get_ticks_usec() - t0) / 30000.0
	_enter_peru()
	ManagerSim.hire(gs, "PER", int(ManagerSim.candidates(gs, "PER")[0]["citizen_id"]))
	TimeManager.advance_days(3)
	t0 = Time.get_ticks_usec()
	TimeManager.advance_days(30)
	var two := float(Time.get_ticks_usec() - t0) / 30000.0
	CountriesSim.buy_license(gs, "CHL")
	CountriesSim.buy_entry_land(gs, "CHL")
	TimeManager.advance_days(3)
	t0 = Time.get_ticks_usec()
	TimeManager.advance_days(30)
	var three := float(Time.get_ticks_usec() - t0) / 30000.0
	var perf: Dictionary = CountriesSim.perf()
	perf_note = "Rendimiento (ms por día simulado): 1 país %.1f · 2 países %.1f · 3 países %.1f · por país: %s" % [one, two, three,
			", ".join(perf.keys().map(func(k): return "%s %.1f" % [k, float(perf[k]["avg"])]))]
	print("  ", perf_note)
	check(two < one * 2.5 + 5.0, "con 2 países el día no se vuelve lento (%.1f ms frente a %.1f ms)" % [two, one])
	check(three < one * 3.5 + 8.0, "con 3 países tampoco (%.1f ms)" % three)
	check(gs.running and CountriesSim.presence_ids(gs).size() == 3, "la partida sigue con 3 países")


func _test_ui() -> void:
	print("-- Interfaz --")
	_new()
	var gs = _gs()
	_enter_peru()
	var cw := CountriesWindow.new()
	add_child(cw)
	cw.setup()
	cw.open(0)
	await get_tree().process_frame
	cw.open(1)
	await get_tree().process_frame
	check(cw.visible, "ventana Mapa mundial / Mis países")
	cw.map_view.select("PER")
	check(cw.side_info.text.contains("Perú"), "el mapa mundial muestra el país elegido con presencia")
	var aw := AviationWindow.new()
	add_child(aw)
	aw.setup()
	aw.open()
	await get_tree().process_frame
	check(aw.visible and aw.body.get_child_count() > 0, "panel Aviación")
	var ind := CountryIndicator.new()
	add_child(ind)
	ind.refresh()
	check(ind.text.contains("Colombia"), "indicador del país donde está el personaje: %s" % ind.text)
	cw.queue_free()
	aw.queue_free()
	ind.queue_free()
