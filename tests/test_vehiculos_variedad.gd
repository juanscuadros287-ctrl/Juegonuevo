extends Node
## Pruebas de la variedad de vehículos y vagones (docs/VEHICULOS.md): catálogo por tipo y época con
## tradeoffs, especialidades con efecto en la simulación (capacidad, merma, caminos malos, viajes extra,
## locomotora pesada), desgaste y revisión, equipo de los cargadores, vagones por modelo, niveles del
## Parqueadero y flota, diseño 3D único por modelo, guardado de partidas viejas, determinismo y ficha de compra.
## godot --headless res://tests/test_vehiculos_variedad.tscn

var failures := 0
var gs = GameState

const TECHS := ["carretas", "caminos_empedrados", "navegacion", "revolucion_industrial", "maquina_vapor", "ferrocarril", "automovil",
		"aviacion", "industria_automotriz", "refrigeracion", "conservas", "arado_hierro"]


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func _ready() -> void:
	print("== Dinastía: variedad de vehículos y vagones ==")
	_test_catalog()
	_test_models_3d()
	_test_specialties()
	_test_roads_and_trips()
	_test_loss()
	_test_trains()
	_test_wear()
	_test_gear()
	_test_parking()
	_test_old_save()
	_test_determinism()
	await _test_ui()
	print("== %s (%d fallos) ==" % ["TODO OK" if failures == 0 else "CON FALLOS", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _new(seed_value := 5) -> void:
	gs.new_game({"seed": seed_value, "difficulty": "facil", "map_type": "costa"})
	gs.suppress_notifications = true
	gs.money = 3000000.0
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


# --- Catálogo -------------------------------------------------------------------------------------------

func _test_catalog() -> void:
	print("-- Catálogo: varios modelos por tipo y época, con tradeoffs --")
	_new()
	for tipo in ["animal", "carreta", "camion", "tren", "barco", "avion"]:
		var ms := VehicleCatalog.models(gs, tipo, true)
		var techs := {}
		var specs := {}
		for m in ms:
			techs[str(m["tech"])] = true
			specs[str(m["spec"])] = true
		check(ms.size() >= 4 and techs.size() >= 2 and specs.size() >= 2, "%s: %d modelos, %d tecnologías, %d especialidades" % [tipo, ms.size(), techs.size(), specs.size()])
		# Tradeoff: el más rápido no es el que más carga.
		var fast: Dictionary = ms[0]
		var big: Dictionary = ms[0]
		for m in ms:
			if float(m["speed_full"]) > float(fast["speed_full"]):
				fast = m
			if float(m["capacity"]) > float(big["capacity"]):
				big = m
		check(str(fast["id"]) != str(big["id"]), "%s: el más rápido (%s) no es el de más carga (%s)" % [tipo, fast["id"], big["id"]])
	check(VehicleCatalog.gear_ids().size() >= 4, "a pie: %d equipos de cargador" % VehicleCatalog.gear_ids().size())
	var classes := {}
	for wt in VehicleCatalog.wagon_ids(null, true):
		var c := str(VehicleCatalog.wagon_def(str(wt)).get("clase", ""))
		classes[c] = int(classes.get(c, 0)) + 1
	check(int(classes.get("granelero", 0)) >= 3 and int(classes.get("cerrado", 0)) >= 3 and int(classes.get("cisterna", 0)) >= 2 and int(classes.get("frigorifico", 0)) >= 2
			and int(classes.get("plataforma", 0)) >= 2 and int(classes.get("pasajeros", 0)) >= 2, "vagones: varios modelos por tipo %s" % str(classes))
	# Desbloqueo por investigación.
	var names := VehicleCatalog.models(gs, "camion").map(func(x): return str(x["id"]))
	check(names.has("camion_frigorifico") and not names.has("camion_blindado"), "camiones según la investigación (%s)" % str(names))
	check(not VehicleCatalog.wagon_unlocked(gs, "tolva_autodescarga") and VehicleCatalog.wagon_unlocked(gs, "granelero"), "vagones según la investigación")
	# Cada modelo con sus propiedades.
	var ok := true
	for id in LogisticsSim.modes():
		var md := LogisticsSim.mode_def(str(id))
		if bool(md.get("vehicle", false)) and (not md.has("spec") or float(md.get("durability", 0.0)) <= 0.0 or float(md.get("price", 0.0)) <= 0.0):
			ok = false
			print("     sin spec/durabilidad/precio: ", id)
	check(ok, "todo modelo comprable tiene especialidad, durabilidad y precio")


# --- Diseño 3D ------------------------------------------------------------------------------------------

func _test_models_3d() -> void:
	print("-- Diseño 3D: una receta por modelo y vagón, mallas compartidas, LOD --")
	var ids := []
	for id in LogisticsSim.modes():
		if bool(LogisticsSim.mode_def(str(id)).get("vehicle", false)):
			ids.append(str(id))
	ids.append_array(VehicleCatalog.wagon_ids(null, true))
	var missing := ids.filter(func(i): return not VehicleModels.has_model(str(i)))
	check(missing.is_empty(), "%d modelos y vagones con diseño propio (faltan %s)" % [ids.size(), str(missing)])
	for g in VehicleCatalog.gear_ids():
		check(VehicleModels.new().has_method("_r_pie_" + str(g)), "cargador con %s tiene su modelo" % g)
	# Siluetas distintas: ningún par comparte cantidad de vértices y tamaño.
	var sig := {}
	var dup := []
	var max_tris := 0
	for id in ids:
		var m: Mesh = VehicleModels.meshes(str(id))[0]
		var ab := m.get_aabb()
		var key := "%d|%.1f|%.1f|%.1f" % [m.surface_get_array_len(0), ab.size.x, ab.size.y, ab.size.z]
		if sig.has(key):
			dup.append("%s=%s" % [id, sig[key]])
		sig[key] = id
		max_tris = maxi(max_tris, VehicleModels.triangles(str(id)))
	check(dup.is_empty(), "siluetas únicas (repetidas: %s)" % str(dup))
	check(max_tris < 2500, "low-poly: el modelo más pesado tiene %d triángulos" % max_tris)
	var a := VehicleModels.node("camion_cisterna")
	var b := VehicleModels.node("camion_cisterna")
	var da: MeshInstance3D = a.get_node("Detail")
	var db: MeshInstance3D = b.get_node("Detail")
	var pa: MeshInstance3D = a.get_node("Proxy")
	check(da.mesh == db.mesh and da.mesh.surface_get_material(0) == VehicleModels.meshes("trailer")[0].surface_get_material(0), "malla compartida por modelo y un solo material para toda la flota")
	check(da.visibility_range_end > 0.0 and pa.visibility_range_begin == da.visibility_range_end and pa.mesh.get_surface_count() > 0, "LOD: proxy de cajas desde %d m" % int(da.visibility_range_end))
	a.free()
	b.free()


# --- Especialidades -------------------------------------------------------------------------------------

func _test_specialties() -> void:
	print("-- Especialidades: capacidad según la carga --")
	_new()
	var cis := {"mode": "camion_cisterna"}
	check(is_equal_approx(VehicleCatalog.capacity_of(cis, "petroleo"), 280.0 * 1.3) and VehicleCatalog.capacity_of(cis, "madera") == 0.0, "cisterna: +30 %% líquidos (%.0f), no lleva madera" % VehicleCatalog.capacity_of(cis, "petroleo"))
	var vol := {"mode": "camion_volteo"}
	check(VehicleCatalog.capacity_of(vol, "hierro") > VehicleCatalog.capacity_of(vol, "ropa") * 2.0, "volqueta: granel %.0f contra carga suelta %.0f" % [VehicleCatalog.capacity_of(vol, "hierro"), VehicleCatalog.capacity_of(vol, "ropa")])
	var fr := {"mode": "camion_frigorifico"}
	check(VehicleCatalog.capacity_of(fr, "carne") == 200.0 and VehicleCatalog.capacity_of(fr, "madera") < 200.0, "frigorífico: perecederos completos, el resto cabe menos")
	var pes := {"mode": "camion_pesado"}
	check(VehicleCatalog.capacity_of(pes, "acero") > VehicleCatalog.capacity_of(pes, "ropa"), "camión pesado: +30 % acero")
	check(VehicleCatalog.capacity_of({"mode": "camion"}, "petroleo") == 250.0, "los generales no cambian (economía intacta)")
	# Ruta con un bien que el modelo no lleva: error sin cobrar.
	var dep := _place("deposito_camiones", -25, -25, 2)
	_hire(dep, 4)
	TransitSim.build_road(gs, _pv([[-20, -18], [6, 4], [27, 20]]), "empedrado")
	var a := _place("almacen", 30, 25)
	var t: Dictionary = FleetSim.buy(gs, dep, "camion_cisterna").get("vehicle", {})
	check(not t.is_empty(), "compra un camión cisterna")
	WarehouseSim.add_to(gs, int(a["id"]), "madera", 100.0)
	var r := LogisticsSim.create_route(gs, {"from": int(a["id"]), "to": LogisticsSim.PLAZA, "good": "madera", "qty": 50, "vehicle": int(t.get("id", -1))})
	check(r.has("error") and str(r["error"]).contains("líquidos"), "la cisterna no acepta madera: %s" % r.get("error", ""))


func _test_roads_and_trips() -> void:
	print("-- Todoterreno y express --")
	_new()
	var a := _place("almacen", -30, 0)
	var b := _place("almacen", 40, 0)
	TransitSim.build_road(gs, _pv([[-30, 6], [40, 6]]), "barro")
	var normal := RouteSim.validate(gs, "camion", int(a["id"]), int(b["id"]))
	var tt := RouteSim.validate(gs, "camion_4x4", int(a["id"]), int(b["id"]))
	check(normal != "" and tt == "", "camino de barro: el camión no pasa (%s), el 4x4 sí" % normal)
	var i4 := LogisticsSim.trip_info(gs, int(a["id"]), int(b["id"]), "camion_4x4", -1, [], "madera")
	var dist := float(i4["distance"])
	check(is_equal_approx(dist / float(i4["travel"]), 1050.0 * 1.35), "4x4 en barro va como en empedrado (%.0f m/día)" % (dist / float(i4["travel"])))
	check(VehicleCatalog.offroad_range_mult("mula") > 1.0 and VehicleCatalog.offroad_range_mult("burro") == 1.0, "la mula llega más lejos por el monte que el burro")
	var ic := LogisticsSim.trip_info(gs, int(a["id"]), int(b["id"]), "caballo", -1, [], "madera")
	var im := LogisticsSim.trip_info(gs, int(a["id"]), int(b["id"]), "mula", -1, [], "madera")
	check(VehicleCatalog.extra_trips("caballo") == 1 and int(ic["trips"]) >= int(im["trips"]), "express: un viaje más al día (caballo %d, mula %d)" % [int(ic["trips"]), int(im["trips"])])


func _test_loss() -> void:
	print("-- Merma: perecederos sin frío, valiosos sin vehículo de valores --")
	check(VehicleCatalog.loss_frac("camion", "carne", 4.0) > 0.1 and VehicleCatalog.loss_frac("camion_frigorifico", "carne", 4.0) == 0.0, "carne 4 días: camión %.0f %%, frigorífico 0 %%" % (VehicleCatalog.loss_frac("camion", "carne", 4.0) * 100.0))
	check(is_equal_approx(VehicleCatalog.loss_frac("furgoneta", "carne", 4.0), VehicleCatalog.loss_frac("camion", "carne", 4.0) * 0.5), "express: media merma")
	check(VehicleCatalog.loss_frac("camion", "carne", 1.0) == 0.0, "viajes cortos sin merma (gracia)")
	check(VehicleCatalog.loss_frac("camion", "joyas", 5.0) > 0.0 and VehicleCatalog.loss_frac("camion_blindado", "joyas", 5.0) == 0.0, "joyas: el blindado las protege")
	check(VehicleCatalog.loss_frac("camion", "madera", 20.0) == 0.0, "la madera no se daña")
	# La merma se aplica al entregar (determinista) y se cuenta.
	_new()
	var a := _place("almacen", 30, 25)
	LogisticsSim.shipments(gs).append({"route": -1, "good": "carne", "qty": 100.0, "from": LogisticsSim.PLAZA, "to": int(a["id"]), "mode": "camion",
			"crew": [], "vehicles": [], "carriers": 1, "depart": 0.0, "travel": 1.0, "trips": 1, "arrive": 0.0, "back": 0.0,
			"ax": 0.0, "az": 0.0, "bx": 30.0, "bz": 25.0, "delivered": false, "fuel": 0.0, "bought": 0.0, "stops": [], "rail_sections": [], "loss": 0.2})
	var before := WarehouseSim.stock_in(gs, int(a["id"]), "carne")
	LogisticsSim._complete_shipments(gs, float(gs.today()) + 1.0)
	check(is_equal_approx(WarehouseSim.stock_in(gs, int(a["id"]), "carne") - before, 80.0) and is_equal_approx(float(gs.logistics["stats"].get("month_lost", 0.0)), 20.0), "llegan 80 de 100 y se registran 20 de merma")


func _test_trains() -> void:
	print("-- Trenes: vagones por modelo y locomotora pesada --")
	_new()
	check(VehicleCatalog.wagon_accepts("tolva_acero", "hierro") and not VehicleCatalog.wagon_accepts("tolva_acero", "petroleo"), "la tolva de acero hereda la carga del granelero")
	check(VehicleCatalog.wagon_accepts("furgon_valores", "joyas") and not VehicleCatalog.wagon_accepts("furgon_valores", "trigo"), "furgón de valores: solo valiosos")
	check(VehicleCatalog.train_capacity({"tolva_acero": 2}, "carbon") == 280.0, "capacidad por modelo de vagón")
	var plain := VehicleCatalog.loss_frac("tren_vapor", "joyas", 6.0, {"mode": "tren_vapor", "comp": {"cerrado": 2}})
	var safe := VehicleCatalog.loss_frac("tren_vapor", "joyas", 6.0, {"mode": "tren_vapor", "comp": {"furgon_valores": 2}})
	check(plain > 0.0 and safe == 0.0, "joyas en furgón cerrado se mermán (%.0f %%), en furgón de valores no" % (plain * 100.0))
	var heavy := {"tolva_acero": 20}
	var full := VehicleCatalog.train_capacity(heavy)
	check(VehicleCatalog.train_speed("diesel_pesada", heavy, full) >= 2800.0 * 0.5 - 0.1, "la diésel pesada no baja de la mitad de su velocidad a tope")
	check(VehicleCatalog.train_speed("vapor_expreso", {"cerrado": 3}, 0.0) > VehicleCatalog.train_speed("tren_vapor", {"cerrado": 3}, 0.0), "el expreso de vapor es más rápido con pocos vagones")
	var ct := _place("cochera_tren", 0, -30)
	RailSim.build(gs, _pv([[-30, -24], [30, -24]]))
	_hire(ct, 3)
	gs.techs.erase("automatizacion")
	var e := FleetSim.buy(gs, ct, "tren_vapor", {"tolva_autodescarga": 2})
	check(e.has("error") and str(e["error"]).contains("requiere"), "un vagón sin investigar no se compra: %s" % e.get("error", ""))
	var t: Dictionary = FleetSim.buy(gs, ct, "tren_vapor", {"granelero": 1}).get("vehicle", {})
	check(FleetSim.add_wagons(gs, int(t.get("id", -1)), "tolva_autodescarga", 1) != "", "ni se agrega después")


func _test_wear() -> void:
	print("-- Desgaste y revisión --")
	_new()
	var dep := _place("deposito_camiones", -25, -25, 2)
	_hire(dep, 4)
	TransitSim.build_road(gs, _pv([[-20, -18], [6, 4], [27, 20]]), "empedrado")
	var t: Dictionary = FleetSim.buy(gs, dep, "camion").get("vehicle", {})
	check(VehicleCatalog.wear_of(t) == 0.0 and VehicleCatalog.wear_upkeep_mult(t) == 1.0, "nuevo: sin desgaste")
	t["km"] = VehicleCatalog.durability_of("camion") * 1.5
	check(VehicleCatalog.wear_upkeep_mult(t) > 1.2 and VehicleCatalog.wear_speed_mult(t) < 1.0, "pasada su durabilidad: mantenimiento ×%.2f y velocidad ×%.2f" % [VehicleCatalog.wear_upkeep_mult(t), VehicleCatalog.wear_speed_mult(t)])
	var m0: float = gs.money
	check(FleetSim.overhaul(gs, int(t["id"])) == "" and VehicleCatalog.wear_of(t) == 0.0 and gs.money < m0, "revisión: queda como nuevo y cuesta %s" % Fmt.money(m0 - gs.money))
	check(FleetSim.overhaul(gs, int(t["id"])) != "", "no se revisa un vehículo como nuevo")


func _test_gear() -> void:
	print("-- A pie: equipo de los cargadores --")
	_new()
	gs.techs.erase("automovil")
	var c := _place("central_transporte", 0, 30)
	_hire(c, 4)
	var a := _place("almacen", 30, 25)
	var i0 := LogisticsSim.trip_info(gs, int(a["id"]), LogisticsSim.PLAZA, "pie", -1, [], "madera")
	check(FleetSim.buy_gear(gs, "motocarro").contains("Requiere"), "el motocarro pide investigar Automóvil")
	var m0: float = gs.money
	check(FleetSim.buy_gear(gs, "carretilla") == "" and gs.money < m0 and VehicleCatalog.gear_id(gs) == "carretilla", "equipa carretillas (%s)" % Fmt.money(m0 - gs.money))
	var i1 := LogisticsSim.trip_info(gs, int(a["id"]), LogisticsSim.PLAZA, "pie", -1, [], "madera")
	check(float(i1["capacity"]) > float(i0["capacity"]) * 1.5 and float(i1["travel"]) > float(i0["travel"]), "carretilla: más carga (%d) pero más lenta" % int(float(i1["capacity"])))
	check(VehicleCatalog.stats(gs, "pie")["label"].contains("Carretilla"), "la ficha muestra el equipo")


func _test_parking() -> void:
	print("-- Niveles del Parqueadero y flota --")
	_new()
	gs.techs.append("automatizacion")
	var saw := _place("aserradero" if GameData.building_def("aserradero").size() > 0 else "carpinteria", -40, -40)
	saw["modules"] = {"parqueadero": 5}
	TransitSim.build_road(gs, _pv([[-40, -36], [0, -10], [20, 10]]), "cemento")
	check(FleetSim.buy(gs, saw, "camion_frigorifico").has("vehicle"), "nivel 5: camiones especializados")
	var e := FleetSim.buy(gs, saw, "trailer")
	check(e.has("error") and str(e["error"]).contains("nivel 6"), "el tráiler pide nivel 6: %s" % e.get("error", ""))
	saw["modules"] = {"parqueadero": 6}
	check(FleetSim.buy(gs, saw, "trailer").has("vehicle"), "nivel 6: tráileres")
	saw["modules"] = {"parqueadero": 3}
	check(FleetSim.parking_reason(gs, saw, "diligencia") == "" and FleetSim.parking_reason(gs, saw, "carro_vapor") != "", "nivel 3: carretas sí, carro de vapor no")


# --- Partidas viejas ------------------------------------------------------------------------------------

func _test_old_save() -> void:
	print("-- Partidas viejas --")
	_new()
	var ct := _place("cochera_tren", 0, -30)
	RailSim.build(gs, _pv([[-30, -24], [30, -24]]))
	var yard_s := ShipSim.find_shore(gs, Vector2(60, 40), 80.0, 4.0, "", 8.0)
	var yard := _place("astillero", yard_s.x, yard_s.y, 2)
	var data = JSON.parse_string(JSON.stringify(gs.to_dict()))
	var vs: Array = data["logistics"].get("vehicles", [])
	vs.append({"id": 900, "mode": "barco", "base": int(yard["id"]), "name": "Barco viejo", "bought": 0})
	vs.append({"id": 901, "mode": "tren_vapor", "base": int(ct["id"]), "name": "Tren viejo", "bought": 0, "comp": {"tanque_viejo": 3, "granelero": 1}})
	vs.append({"id": 902, "mode": "tren_diesel", "base": int(ct["id"]), "name": "Tren primera versión", "bought": 0, "wagons": 4})
	data["logistics"]["vehicles"] = vs
	data["logistics"].erase("porter_gear")
	gs.load_dict(data)
	var v0 := LogisticsSim.get_vehicle(gs, 900)
	var v1 := LogisticsSim.get_vehicle(gs, 901)
	var v2 := LogisticsSim.get_vehicle(gs, 902)
	check(str(v0.get("mode", "")) == "vapor_barco" and float(v0.get("serviced_km", -1.0)) == 0.0 and int(v0.get("trips", -1)) == 0, "un modelo que ya no existe se mapea al actual con valores por defecto")
	check(int(VehicleCatalog.comp_of(v1).get("cerrado", 0)) == 3 and int(VehicleCatalog.comp_of(v1).get("granelero", 0)) == 1, "vagones desconocidos → cerrados")
	check(int(VehicleCatalog.comp_of(v2).get("cerrado", 0)) == 4, "vagones sin tipo → cerrados")
	check(VehicleCatalog.gear_id(gs) == "mecapal", "sin equipo guardado: mecapal")
	var m0: float = gs.money
	var again = JSON.parse_string(JSON.stringify(gs.to_dict()))
	gs.load_dict(again)
	check(str(LogisticsSim.get_vehicle(gs, 900).get("mode", "")) == "vapor_barco" and is_equal_approx(gs.money, m0), "guardar y cargar de nuevo no cambia nada")


# --- Determinismo ---------------------------------------------------------------------------------------

func _run_once() -> Array:
	_new(11)
	var dep := _place("deposito_camiones", -25, -25, 2)
	_hire(dep, 4)
	TransitSim.build_road(gs, _pv([[-20, -18], [6, 4], [27, 20]]), "empedrado")
	var a := _place("almacen", 30, 25)
	WarehouseSim.add_to(gs, int(a["id"]), "carne", 400.0)
	var t: Dictionary = FleetSim.buy(gs, dep, "camion").get("vehicle", {})
	LogisticsSim.create_route(gs, {"from": int(a["id"]), "to": LogisticsSim.PLAZA, "good": "carne", "qty": 100, "vehicle": int(t.get("id", -1)), "auto": true, "every": 2})
	TimeManager.advance_days(12)
	return [snappedf(WarehouseSim.stock_in(gs, WarehouseSim.PLAZA, "carne"), 0.001), snappedf(float(gs.logistics["stats"].get("total_lost", 0.0)), 0.001), int(t.get("trips", 0))]


func _test_determinism() -> void:
	print("-- Determinismo --")
	var r1 := _run_once()
	var r2 := _run_once()
	check(r1 == r2 and int(r1[2]) > 0, "dos corridas iguales dan lo mismo %s" % str(r1))


# --- Interfaz -------------------------------------------------------------------------------------------

func _find(n: Node, nm: String) -> Node:
	if n.name == nm:
		return n
	for c in n.get_children():
		var f := _find(c, nm)
		if f:
			return f
	return null


func _test_ui() -> void:
	print("-- Ficha de compra --")
	_new()
	var win := RoutesWindow.new()
	add_child(win)
	win.setup()
	win.b_tipo = "camion"
	win.b_mode = "camion_frigorifico"
	win.tab = "vehicles"
	win.open()
	await get_tree().process_frame
	var card := _find(win, "ModelCard")
	check(card != null and _find(card, "Thumb") is VehicleThumb, "la ficha del modelo tiene miniatura 3D")
	var tbl: GridContainer = _find(card, "Compare") if card else null
	check(tbl != null and tbl.get_child_count() == 9 * (1 + VehicleCatalog.models(gs, "camion", true).size()), "tabla comparativa con todos los camiones")
	win.b_tipo = "pie"
	win.refresh()
	await get_tree().process_frame
	check(_find(win, "GearCard") != null, "a pie: tarjeta del equipo de los cargadores")
	win.queue_free()
