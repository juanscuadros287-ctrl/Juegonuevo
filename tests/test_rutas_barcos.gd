extends Node
## Pruebas de rutas punto X → punto Y, barcos, puertos, astilleros, trenes y garajes conectados.
## godot --headless res://tests/test_rutas_barcos.tscn   (docs/RUTAS_BARCOS.md)

var failures := 0
var gs = GameState


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func _ready() -> void:
	print("== Dinastía: rutas, barcos, trenes y garajes conectados ==")
	_test_validation()
	_test_colors()
	_test_garages_connected()
	_test_garage_levels()
	_test_trains()
	_test_national_ship()
	_test_international_ship()
	_test_migration()
	_test_save_load()
	await _test_ui()
	print("== %s (%d fallos) ==" % ["TODO OK" if failures == 0 else "CON FALLOS", failures])
	get_tree().quit(1 if failures > 0 else 0)


const TECHS := ["carretas", "caminos_empedrados", "navegacion", "revolucion_industrial", "maquina_vapor", "ferrocarril", "automovil", "aviacion"]


func _new(seed_value := 5, map_type := "costa") -> void:
	gs.new_game({"seed": seed_value, "difficulty": "facil", "map_type": map_type})
	gs.suppress_notifications = true
	gs.money = 2000000.0
	for t in TECHS:
		if not gs.techs.has(t):
			gs.techs.append(t)
	for zx in range(5):
		for zy in range(5):
			if not gs.is_zone_unlocked(zx, zy):
				gs.unlocked_zones.append([zx, zy])


func _place(type_id: String, x: float, z: float, level := 1) -> Dictionary:
	var b: Dictionary = ConstructionSim.make_building(gs, type_id, level, x, z, 0.0, "jugador")
	b["status"] = "activo"
	gs.add_building(b)
	WarehouseSim.relink_all(gs)
	return b


func _hire(b: Dictionary, n: int) -> int:
	var hired := 0
	for c in gs.citizens.values():
		if hired >= n:
			break
		if gs.is_player(c.id) or c.job_id >= 0 or c.age_years(gs.today()) < 18 or c.age_years(gs.today()) > 60:
			continue
		if BusinessSim.hire(gs, b, c, 3.0) == "":
			hired += 1
	return hired


func _pv(arr: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for a in arr:
		out.append(Vector2(float(a[0]), float(a[1])))
	return out


# --- Validación por modo --------------------------------------------------------------------------

func _test_validation() -> void:
	print("-- Validación con sentido por medio --")
	_new()
	var a := _place("almacen", 30, 25)
	var far := _place("almacen", 30, -280)
	check(RouteSim.validate(gs, "pie", int(a["id"]), LogisticsSim.PLAZA) == "", "a pie cerca: se puede")
	var e1 := RouteSim.validate(gs, "pie", int(a["id"]), int(far["id"]))
	check(e1.contains("distancia prudente"), "a pie lejos se rechaza: %s" % e1)
	var cp := LogisticsSim.create_route(gs, {"from": int(a["id"]), "to": int(far["id"]), "good": "madera", "qty": 10, "mode": "pie"})
	check(cp.has("error") and str(cp["error"]).contains("distancia prudente"), "y la ruta no se crea con cargadores")
	var e2 := RouteSim.validate(gs, "camion", int(a["id"]), LogisticsSim.PLAZA)
	check(e2.contains("carretera"), "camión sin carretera se rechaza: %s" % e2)
	var e3 := RouteSim.validate(gs, "mula", int(a["id"]), LogisticsSim.PLAZA)
	check(e3 == "", "la mula va por el monte a distancia moderada")
	# Tren: estaciones sin rieles.
	var s1 := _place("estacion_tren", 44, 25)
	var s2 := _place("estacion_tren", 30, -266)
	var e4 := RouteSim.validate(gs, "tren_vapor", int(a["id"]), int(far["id"]))
	check(e4.contains("vía férrea") or e4.contains("rieles"), "tren sin rieles se rechaza: %s" % e4)
	var e4b := RouteSim.validate(gs, "tren_vapor", LogisticsSim.PLAZA, int(far["id"]))
	check(e4b.contains("estación"), "el tren carga junto a una estación: %s" % e4b)
	# Barco: "puertos" tierra adentro (sin agua).
	var p1 := _place("puerto", -40, -40)
	var p2 := _place("puerto", -40, 40)
	var e5 := RouteSim.validate(gs, "velero", int(p1["id"]), int(p2["id"]))
	check(e5.contains("agua"), "barco sin agua se rechaza: %s" % e5)
	var e6 := RouteSim.validate(gs, "velero", int(a["id"]), int(p2["id"]))
	check(e6.contains("puerto"), "el barco carga en un puerto: %s" % e6)
	check(ShipSim.placement_block_reason(gs, "puerto", -40, -40) != "", "no se construye un puerto lejos del agua")
	var shore := ShipSim.find_shore(gs, Vector2(60, 0), 80.0, 4.0, "", 5.5)
	check(shore != Vector2.INF and ShipSim.placement_block_reason(gs, "puerto", shore.x, shore.y) == "", "en la costa sí (%s)" % str(shore))
	check(RouteSim.validate(gs, "avion", int(a["id"]), LogisticsSim.PLAZA).contains("aeropuerto"), "el avión vuela entre aeropuertos")
	# Paradas intermedias: cada tramo se valida.
	var mid := _place("almacen", -20, 30)
	check(RouteSim.validate(gs, "pie", int(a["id"]), LogisticsSim.PLAZA, [int(mid["id"])]) == "", "a pie con una parada intermedia cercana")
	check(RouteSim.validate(gs, "pie", int(a["id"]), LogisticsSim.PLAZA, [int(far["id"])]).begins_with("Tramo"), "una parada lejana hace fallar su tramo")


# --- Colores -------------------------------------------------------------------------------------

func _test_colors() -> void:
	print("-- Color y nombre únicos por ruta --")
	_new()
	var a := _place("almacen", 30, 25)
	var b := _place("almacen", -30, 25)
	var c := _place("central_transporte", 0, -30)
	_hire(c, 4)
	WarehouseSim.add_to(gs, int(a["id"]), "madera", 300.0)
	var keys := []
	for i in range(18):
		var r := LogisticsSim.create_route(gs, {"from": int(a["id"]), "to": int(b["id"]) if i % 2 == 0 else LogisticsSim.PLAZA, "good": "madera", "qty": 1, "mode": "pie", "auto": true, "every": 30})
		if r.has("route"):
			keys.append("L%d" % int(r["route"]["id"]))
	var colors := {}
	var named := true
	for u in RouteSim.all_routes(gs):
		colors[(u["color"] as Color).to_html(false)] = true
		named = named and str(u["name"]) != ""
	check(keys.size() == 18 and colors.size() == RouteSim.all_routes(gs).size(), "18 rutas con 18 colores distintos (más que la paleta)")
	check(named, "cada ruta tiene nombre")
	var used := (RouteSim.all_routes(gs)[1]["color"] as Color).to_html(false)
	var err := RouteSim.set_color(gs, keys[0], "#" + used)
	check(err.contains("ya lo usa"), "no se puede repetir el color de otra ruta: %s" % err)
	check(RouteSim.set_color(gs, keys[0], "#123456") == "" and RouteSim.color_of(gs, keys[0]).to_html(false) == "123456", "el color se puede editar")
	check(RouteSim.set_route_name(gs, keys[0], "Madera al almacén B") == "" and str(RouteSim.all_routes(gs)[0]["name"]) == "Madera al almacén B", "el nombre se puede editar")
	check(RouteSim.layer_visible(gs), "la capa de rutas se ve por defecto")
	RouteSim.set_layer_visible(gs, false)
	check(not RouteSim.layer_visible(gs), "y se puede ocultar")


# --- Garajes conectados --------------------------------------------------------------------------

func _test_garages_connected() -> void:
	print("-- Garajes conectados --")
	_new()
	var a := _place("almacen", 30, 25)
	var dep := _place("deposito_camiones", -25, -25, 2)
	_hire(dep, 3)
	var conn := GarageSim.connection(gs, "deposito_camiones", -25, -25, 2)
	check(not bool(conn["ok"]) and str(conn["reason"]).contains("carretera"), "depósito sin carretera: rojo (%s)" % str(conn["reason"]))
	var e := LogisticsSim.buy_vehicle(gs, dep, "camion")
	check(e.has("error") and str(e["error"]).contains("carretera"), "sin conexión no se compran vehículos: %s" % e.get("error", ""))
	check(GarageSim.status_text(gs, dep).contains("Sin conexión"), "el panel explica por qué")
	check(TransitSim.buy_block_reason(gs, _place("empresa_buses", -60, 60)).begins_with("Requiere"), "la terminal de buses revisa primero la tecnología")
	TransitSim.build_road(gs, _pv([[-20, -18], [6, 4], [27, 20]]), "empedrado")
	check(GarageSim.linked(gs, dep), "tocando la carretera: verde")
	var truck: Dictionary = LogisticsSim.buy_vehicle(gs, dep, "camion").get("vehicle", {})
	check(not truck.is_empty(), "conectado: compra un camión")
	WarehouseSim.add_to(gs, int(a["id"]), "piedra", 200.0)
	var r := LogisticsSim.create_route(gs, {"from": int(a["id"]), "to": LogisticsSim.PLAZA, "good": "piedra", "qty": 100, "vehicle": int(truck["id"]), "auto": true, "every": 1})
	check(r.has("route") and LogisticsSim.shipments(gs).size() == 1, "conectado: despacha el camión (%s)" % r.get("error", "ok"))
	# Se quita la carretera junto al depósito: queda desconectado y no despacha.
	TimeManager.advance_days(2)
	var dep_p := Vector2(-25, -25)
	for p in TransitSim.polys(gs).duplicate():
		TransitSim.remove_poly(gs, int(p["id"]))
	TransitSim.build_road(gs, _pv([[8, 6], [27, 20]]), "empedrado")
	RoadSim.build(gs, Vector2(0, 0), Vector2(8, 6), "empedrado")
	check(not GarageSim.linked(gs, dep) and dep_p.distance_to(Vector2(8, 6)) > 20.0, "sin la carretera el depósito queda desconectado")
	var n0 := LogisticsSim.shipments(gs).size()
	LogisticsSim.dispatch(gs, r["route"], float(gs.today()) + 0.3)
	check(LogisticsSim.shipments(gs).size() == n0 and str(r["route"]["status"]).contains("carretera"), "desconectado no despacha: %s" % str(r["route"]["status"]))
	# Hangar junto a la pista.
	check(not bool(GarageSim.connection(gs, "hangar", -60, -60)["ok"]), "hangar sin aeropuerto: desconectado")
	_place("aeropuerto", -60, -84)
	check(bool(GarageSim.connection(gs, "hangar", -60, -64)["ok"]), "hangar junto a la pista: conectado")
	# Astillero en el agua.
	var shore := ShipSim.find_shore(gs, Vector2(60, 40), 80.0, 4.0, "", 8.0)
	check(bool(GarageSim.connection(gs, "astillero", shore.x, shore.y)["ok"]) and not bool(GarageSim.connection(gs, "astillero", -40, 0)["ok"]), "astillero: conectado en la orilla, no tierra adentro")
	check(bool(GarageSim.connection(gs, "caballeriza", -40, 0)["ok"]), "caballeriza en tierra firme: conectada")


func _test_garage_levels() -> void:
	print("-- El nivel del garaje define los vehículos --")
	_new()
	gs.techs.append("industria_automotriz")
	gs.techs.append("era_moderna")
	gs.techs.append("electronica")
	var shore := ShipSim.find_shore(gs, Vector2(60, 40), 80.0, 4.0, "", 8.0)
	var y := _place("astillero", shore.x, shore.y, 1)
	_hire(y, 6)
	check(LogisticsSim.buy_vehicle(gs, y, "velero").has("vehicle"), "el varadero ofrece veleros")
	var e := LogisticsSim.buy_vehicle(gs, y, "vapor_barco")
	check(e.has("error") and str(e["error"]).contains("mejóralo"), "el varadero no ofrece vapores: %s" % e.get("error", ""))
	y["level"] = 2
	check(LogisticsSim.buy_vehicle(gs, y, "vapor_barco").has("vehicle"), "el astillero de vapor sí")
	check(LogisticsSim.buy_vehicle(gs, y, "carguero").has("error"), "pero aún no cargueros")
	y["level"] = 4
	check(LogisticsSim.buy_vehicle(gs, y, "portacontenedores").has("vehicle"), "el astillero de contenedores ofrece portacontenedores")
	TransitSim.build_road(gs, _pv([[-60, -40], [-60, 40]]), "cemento")
	gs.techs.append("ferrocarril")
	RailSim.build(gs, _pv([[-40, -40], [-40, 40]]))
	var ct := _place("cochera_tren", -34, 0, 1)
	check(GarageSim.linked(gs, ct), "cochera junto a la vía: conectada")
	var e2 := LogisticsSim.buy_vehicle(gs, ct, "tren_diesel")
	check(e2.has("error"), "la cochera de nivel 1 no ofrece trenes diésel: %s" % e2.get("error", ""))
	var t: Dictionary = LogisticsSim.buy_vehicle(gs, ct, "tren_vapor").get("vehicle", {})
	check(not t.is_empty() and int(t.get("wagons", 0)) == 4, "tren de vapor con 4 vagones")
	var cap0 := LogisticsSim.vehicle_capacity(gs, t)
	check(GarageSim.add_wagon(gs, int(t["id"])) == "" and LogisticsSim.vehicle_capacity(gs, t) > cap0, "se agregan vagones y sube la capacidad (%d → %d)" % [int(cap0), int(LogisticsSim.vehicle_capacity(gs, t))])
	ct["level"] = 2
	check(LogisticsSim.buy_vehicle(gs, ct, "tren_diesel").has("vehicle"), "el taller ferroviario ofrece trenes diésel")


# --- Trenes -----------------------------------------------------------------------------------------

func _test_trains() -> void:
	print("-- Trenes entre estaciones por rieles --")
	_new()
	var a := _place("almacen", 30, 60)
	var b := _place("almacen", -60, -60)
	var s1 := _place("estacion_tren", 44, 60)
	var s2 := _place("estacion_tren", -46, -60)
	var ct := _place("cochera_tren", 0, -30)
	_hire(ct, 4)
	check(LogisticsSim.buy_vehicle(gs, ct, "tren_vapor").has("error"), "cochera sin vía: no saca trenes")
	check(RailSim.build(gs, _pv([[44, 55], [20, 20], [0, -24], [-46, -55]])) == "", "vía férrea por puntos entre las estaciones")
	check(GarageSim.linked(gs, ct), "la cochera queda conectada a la vía")
	var train: Dictionary = LogisticsSim.buy_vehicle(gs, ct, "tren_vapor").get("vehicle", {})
	check(not train.is_empty(), "compra un tren en la cochera")
	check(RouteSim.validate(gs, "tren_vapor", int(a["id"]), int(b["id"])) == "", "almacenes junto a estaciones unidas por rieles: válido")
	WarehouseSim.add_to(gs, int(a["id"]), "hierro", 400.0)
	var r := RouteSim.create(gs, {"mode": "tren_vapor", "from": int(a["id"]), "to": int(b["id"]), "good": "hierro", "qty": 300, "vehicle": int(train["id"])})
	check(r.has("key") and str(r["key"]).begins_with("L"), "ruta de tren creada (%s)" % r.get("error", "ok"))
	var info := LogisticsSim.trip_info(gs, int(a["id"]), int(b["id"]), "tren_vapor", int(train["id"]))
	check(float(info["distance"]) >= a["x"] - b["x"], "la distancia sigue los rieles (%.0f m)" % float(info["distance"]))
	var path := RouteSim.path_for(gs, int(a["id"]), int(b["id"]), "tren_vapor")
	check(path.size() > 4, "el camino del tren sigue la vía (%d puntos)" % path.size())
	TimeManager.advance_days(3)
	check(WarehouseSim.stock_in(gs, int(b["id"]), "hierro") >= 299.0, "el tren llevó el hierro (%.0f)" % WarehouseSim.stock_in(gs, int(b["id"]), "hierro"))


# --- Barcos -----------------------------------------------------------------------------------------

func _coast_port(near: Vector2, level := 1) -> Dictionary:
	var p := ShipSim.find_shore(gs, near, 90.0, 4.0, "mar", GameData.footprint("puerto", level))
	return _place("puerto", p.x, p.y, level)


func _test_national_ship() -> void:
	print("-- Barco nacional entre dos puertos --")
	_new()
	var p1 := _coast_port(Vector2(60, -60))
	var p2 := _coast_port(Vector2(60, 90))
	check(ShipSim.port_water(gs, int(p1["id"])) == "mar" and ShipSim.ports_connected(gs, int(p1["id"]), int(p2["id"])), "dos puertos en la costa unidos por el mar")
	check(WarehouseSim.capacity_of(gs, int(p1["id"])) >= 800.0, "el puerto es un almacén (%.0f)" % WarehouseSim.capacity_of(gs, int(p1["id"])))
	# Almacén grande al lado del puerto (tierra adentro).
	var wh := _place("almacen", float(p1["x"]) - 14.0, float(p1["z"]))
	check(ShipSim.port_of(gs, int(wh["id"])) == int(p1["id"]), "el almacén al lado queda vinculado al puerto")
	var yard_p := ShipSim.find_shore(gs, Vector2(60, 20), 60.0, 4.0, "mar", 8.0)
	var yard := _place("astillero", yard_p.x, yard_p.y)
	_hire(yard, 4)
	var ship: Dictionary = LogisticsSim.buy_vehicle(gs, yard, "velero").get("vehicle", {})
	check(not ship.is_empty(), "compra un velero en el astillero")
	WarehouseSim.add_to(gs, int(wh["id"]), "madera", 200.0)
	var m0: float = gs.money
	var r := RouteSim.create(gs, {"mode": "velero", "from": int(wh["id"]), "to": int(p2["id"]), "good": "madera", "qty": 150, "vehicle": int(ship["id"]), "color": "#00aaff", "name": "Cabotaje"})
	check(r.has("key") and str(r["route"]["color"]) == "00aaff" and str(r["route"]["name"]) == "Cabotaje", "ruta de barco con color y nombre elegidos (%s)" % r.get("error", "ok"))
	var s: Dictionary = LogisticsSim.shipments(gs)[0] if not LogisticsSim.shipments(gs).is_empty() else {}
	check(float(s.get("qty", 0.0)) > 0.0 and float(s["qty"]) <= 150.0 * 4.0, "el velero zarpa con %s madera" % str(s.get("qty", 0)))
	check(is_equal_approx(gs.money, m0), "a vela no gasta combustible")
	TimeManager.advance_days(3)
	check(WarehouseSim.stock_in(gs, int(p2["id"]), "madera") >= 149.0, "la madera llegó al otro puerto (%.0f)" % WarehouseSim.stock_in(gs, int(p2["id"]), "madera"))
	check(RouteSim.last_month_qty(r["route"]) + RouteSim.month_qty(r["route"]) >= 149.0, "carga del mes de la ruta")


func _test_international_ship() -> void:
	print("-- Barco internacional con arancel y cambio --")
	gs.new_game({"seed": 31, "difficulty": "normal", "country_id": "COL", "map_type": "interior"})
	gs.suppress_notifications = true
	gs.money = 2000000.0
	for t in TECHS:
		if not gs.techs.has(t):
			gs.techs.append(t)
	CountriesSim.buy_license(gs, "PER")
	CountriesSim.buy_entry_land(gs, "PER")
	var col_shore := ShipSim.find_shore(gs, Vector2(-2950, -3700), 300.0, 25.0, "mar", 6.0)
	check(col_shore != Vector2.INF, "costa del mar en Colombia (%s)" % str(col_shore))
	var port := _place("puerto", col_shore.x, col_shore.y)
	var ys := ShipSim.find_shore(gs, col_shore + Vector2(40, 0), 300.0, 25.0, "mar", 8.0)
	var yard := _place("astillero", ys.x, ys.y)
	_hire(yard, 6)
	var ship: Dictionary = LogisticsSim.buy_vehicle(gs, yard, "velero").get("vehicle", {})
	check(not ship.is_empty(), "velero comprado en un astillero conectado")
	var per_port = CountriesSim.with_country(gs, "PER", func():
		var p := ShipSim.find_shore(gs, Vector2(-4900, 2100), 300.0, 25.0, "mar", 6.0)
		return _place("puerto", p.x, p.y))
	check(per_port is Dictionary and not (per_port as Dictionary).is_empty(), "puerto en la costa de Perú")
	WarehouseSim.add_to(gs, int(port["id"]), "madera", 300.0)
	var bad := ShipSim.ship_intl(gs, {"from_iso": "COL", "from": 0, "to_iso": "PER", "to": int(per_port["id"]), "good": "madera", "qty": 50.0, "mode": "barco"})
	check(bad.has("error") and str(bad["error"]).contains("puerto"), "el barco sale de un puerto: %s" % bad.get("error", ""))
	var total0 := CountriesSim.money_total(gs) + float(gs.countries["stats"]["outflow"])
	var res := RouteSim.create(gs, {"mode": "velero", "from_iso": "COL", "from": int(port["id"]), "to_iso": "PER", "to": int(per_port["id"]), "good": "madera", "qty": 150.0})
	check(res.has("flight"), "barco propio Colombia → Perú (%s)" % res.get("error", "ok"))
	if not res.has("flight"):
		return
	var f: Dictionary = res["flight"]
	var plane_days := AirSim.flight_days(float(f["km"]), true)
	check(int(f["arrive"]) - int(f["depart"]) > plane_days, "el barco es más lento que el avión (%d días vs %d)" % [int(f["arrive"]) - int(f["depart"]), plane_days])
	check(ShipSim.naviera_unit_fee(gs, float(f["km"])) < AirSim.commercial_unit_fee(gs, float(f["km"]), true), "y más barato por unidad (naviera %s vs avión %s)" % [
			Fmt.money2(ShipSim.naviera_unit_fee(gs, float(f["km"]))), Fmt.money2(AirSim.commercial_unit_fee(gs, float(f["km"]), true))])
	check(LogisticsSim.vehicle_busy(gs, int(ship["id"]), float(gs.today()) + 0.5), "el velero queda ocupado hasta volver")
	var rt := RouteSim.create(gs, {"mode": "naviera", "from_iso": "COL", "from": int(port["id"]), "to_iso": "PER", "to": int(per_port["id"]), "good": "madera", "qty": 20.0, "auto": true, "every": 10})
	check(rt.has("key") and str(rt["key"]).begins_with("A"), "ruta automática internacional en barco (naviera) (%s)" % rt.get("error", "ok"))
	var t1 = CountriesSim.with_country(gs, "PER", func(): return float(gs.government["treasury"]))
	f["arrive"] = gs.today()
	AirSim.daily(gs)
	var t2 = CountriesSim.with_country(gs, "PER", func(): return float(gs.government["treasury"]))
	check(bool(f["delivered"]) and float(f["tariff_money"]) > 0.0, "al llegar paga el arancel del destino (%s)" % Fmt.money2(float(f.get("tariff_money", 0.0))))
	check(is_equal_approx(float(f["fx"]), GlobalEconSim.fx(gs, "COL", "PER")) and is_equal_approx(float(f["tariff_local"]), float(f["value_local"]) * float(f["tariff_rate"])), "con el tipo de cambio como el avión")
	check(float(t2) - float(t1) >= float(f["tariff_money"]) - 0.01, "el arancel entra al tesoro de Perú")
	var stock = CountriesSim.with_country(gs, "PER", func(): return WarehouseSim.stock_in(gs, int(per_port["id"]), "madera"))
	check(float(stock) >= 149.0, "la madera está en el puerto de Perú (%.0f)" % float(stock))
	var total1 := CountriesSim.money_total(gs) + float(gs.countries["stats"]["outflow"])
	check(absf(total1 - total0) < 0.05, "dinero conservado: combustible y flete salen contados, el arancel va al tesoro (%.3f)" % (total1 - total0))
	var colors := {}
	for u in RouteSim.all_routes(gs):
		colors[(u["color"] as Color).to_html(false)] = true
	check(colors.size() == RouteSim.all_routes(gs).size(), "las rutas internacionales también tienen color único")


# --- Migración y guardado ---------------------------------------------------------------------------

func _test_migration() -> void:
	print("-- Migración de partidas y rutas viejas --")
	_new()
	var a := _place("almacen", 30, 25)
	var c := _place("central_transporte", 0, -30)
	_hire(c, 3)
	var dep := _place("deposito_camiones", -60, -60)
	WarehouseSim.add_to(gs, int(a["id"]), "madera", 100.0)
	LogisticsSim.create_route(gs, {"from": int(a["id"]), "to": LogisticsSim.PLAZA, "good": "madera", "qty": 5, "mode": "pie", "auto": true, "every": 3})
	LogisticsSim.create_route(gs, {"from": int(a["id"]), "to": LogisticsSim.PLAZA, "good": "madera", "qty": 5, "mode": "pie", "auto": true, "every": 5})
	var d = JSON.parse_string(JSON.stringify(gs.to_dict()))
	d["logistics"].erase("rutas")
	d["logistics"].erase("rails")
	for r in d["logistics"]["routes"]:
		r.erase("color")
		r.erase("name")
		r.erase("stops")
	gs.load_dict(d)
	var rs := LogisticsSim.routes(gs)
	check(rs.size() == 2 and str(rs[0].get("color", "")) != "" and str(rs[0]["color"]) != str(rs[1]["color"]), "las rutas viejas reciben color único al cargar")
	check(str(rs[0].get("name", "")) != "", "y un nombre")
	check(RouteSim.all_routes(gs).size() == 2 and str(RouteSim.all_routes(gs)[0]["kind"]) == "carga", "aparecen en el modelo común")
	var dep2: Dictionary = gs.get_building(int(dep["id"]))
	check(bool(dep2.get("conn_legacy", false)) and GarageSim.linked(gs, dep2), "garaje viejo sin carretera: conexión provisional (la partida sigue igual)")
	check(RailSim.rails(gs).is_empty() and RouteSim.layer_visible(gs), "valores por defecto: sin vías, capa visible")
	TimeManager.advance_days(4)
	check(int(rs[0].get("trips", 0)) >= 1, "las rutas viejas siguen funcionando")


func _test_save_load() -> void:
	print("-- Guardar y cargar --")
	_new()
	var ct := _place("cochera_tren", 0, -30)
	RailSim.build(gs, _pv([[-30, -24], [30, -24]]))
	_hire(ct, 3)
	var t: Dictionary = LogisticsSim.buy_vehicle(gs, ct, "tren_vapor").get("vehicle", {})
	GarageSim.add_wagon(gs, int(t.get("id", -1)))
	var a := _place("almacen", 30, 25)
	var c := _place("central_transporte", 0, 30)
	_hire(c, 2)
	var r := LogisticsSim.create_route(gs, {"from": int(a["id"]), "to": LogisticsSim.PLAZA, "good": "madera", "qty": 5, "mode": "pie", "auto": true, "every": 3, "color": "#abcdef", "name": "Mi ruta"})
	RouteSim.set_layer_visible(gs, false)
	var m0: float = gs.money
	var data = JSON.parse_string(JSON.stringify(gs.to_dict()))
	gs.load_dict(data)
	check(RailSim.rails(gs).size() == 1 and GarageSim.linked(gs, gs.get_building(int(ct["id"]))), "la vía férrea se guarda y la cochera sigue conectada")
	var t2 := LogisticsSim.get_vehicle(gs, int(t.get("id", -1)))
	check(int(t2.get("wagons", 0)) == 5, "el tren conserva sus vagones")
	var r2 := LogisticsSim.get_route(gs, int(r["route"]["id"]))
	check(str(r2.get("color", "")) == "abcdef" and str(r2.get("name", "")) == "Mi ruta", "color y nombre de la ruta se guardan")
	check(not RouteSim.layer_visible(gs), "la capa oculta se guarda")
	check(is_equal_approx(gs.money, m0), "el dinero no cambia al guardar y cargar")


# --- Interfaz ------------------------------------------------------------------------------------------

func _test_ui() -> void:
	print("-- Interfaz: panel Rutas --")
	_new()
	var a := _place("almacen", 30, 25)
	var c := _place("central_transporte", 0, -30)
	_hire(c, 2)
	LogisticsSim.create_route(gs, {"from": int(a["id"]), "to": LogisticsSim.PLAZA, "good": "madera", "qty": 5, "mode": "pie", "auto": true, "every": 3})
	var win := RoutesWindow.new()
	add_child(win)
	win.setup()
	win.open()
	await get_tree().process_frame
	check(win.visible and win.row_count() == 1, "el panel Rutas lista la ruta (%d)" % win.row_count())
	win.start_wizard()
	win.wizard_set("mode", "pie")
	win.wizard_set("from", int(a["id"]))
	win.wizard_set("to", LogisticsSim.PLAZA)
	check(win.wizard_reason() == "", "el asistente valida origen → destino")
	win.wizard_set("to", int(_place("almacen", 30, -290)["id"]))
	check(win.wizard_reason().contains("distancia prudente"), "y explica cuando no se puede: %s" % win.wizard_reason())
	win.queue_free()
