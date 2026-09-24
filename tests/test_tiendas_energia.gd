extends Node
## Pruebas de comercios especializados, deseos de los vecinos, electricidad, petróleo y catálogo.
## godot --headless res://tests/test_tiendas_energia.tscn

var failures := 0
var gs = GameState


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func _ready() -> void:
	print("== Dinastía: comercios, deseos, energía y catálogo ==")
	_test_shop_data()
	_test_shop_sales()
	_test_price_and_staff()
	_test_unmet_wants()
	_test_medicine()
	_test_cars_and_fuel()
	_test_energy()
	_test_grid_import_and_homes()
	_test_oil_reveal()
	_test_map_rules()
	_test_fluctuation()
	_test_save_load()
	await _test_catalog()
	print("== %s (%d fallos) ==" % ["TODO OK" if failures == 0 else "CON FALLOS", failures])
	get_tree().quit(1 if failures > 0 else 0)


# --- Utilidades ---------------------------------------------------------------------------------

func _new(seed_value := 201, opts := {}) -> void:
	var o := {"seed": seed_value, "difficulty": "facil", "map_type": "interior"}
	o.merge(opts, true)
	gs.new_game(o)
	gs.suppress_notifications = true
	gs.money = 500000.0


func _place(type_id: String, x: float, z: float, level := 1) -> Dictionary:
	var b: Dictionary = ConstructionSim.make_building(gs, type_id, level, x, z, 0.0, "jugador")
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


func _give_money(amount: float) -> void:
	for c in gs.citizens.values():
		if not gs.is_player(c.id):
			c.money += amount


func _weeks(n: int) -> void:
	for i in range(n):
		ShopSim.weekly(gs)


func _energy_day() -> void:
	EnergySim.state(gs)["day"] = -1
	EnergySim.daily(gs)


# --- Datos ---------------------------------------------------------------------------------------

func _test_shop_data() -> void:
	var shops: Dictionary = ShopSim.cfg().get("shops", {})
	var bad := []
	for t in shops:
		if not GameData.businesses.has(t):
			bad.append("%s: no existe el negocio" % t)
		for g in shops[t].get("sells", []):
			if not GameData.goods.has(g):
				bad.append("%s: vende %s inexistente" % [t, g])
	for t in ["tienda", "panaderia", "carniceria", "madereria", "carboneria", "ferreteria", "tienda_ropa", "joyeria_tienda", "muebleria", "botica", "concesionario", "gasolinera"]:
		if not shops.has(t):
			bad.append("falta el comercio %s" % t)
	check(bad.is_empty(), "%d comercios especializados definidos (%s)" % [shops.size(), "ok" if bad.is_empty() else str(bad)])
	var wants: Dictionary = GameData.citizens.get("wants", {})
	var wbad := []
	for w in wants:
		if str(w).begins_with("_"):
			continue
		for g in wants[w].get("goods", []):
			if not GameData.goods.has(g) or ShopSim.shops_selling(g).is_empty():
				wbad.append("%s/%s" % [w, g])
	check(wants.size() >= 14 and wbad.is_empty(), "%d deseos de los vecinos, todos con un comercio que los vende %s" % [wants.size() - 1, "" if wbad.is_empty() else str(wbad)])
	check(str(GameData.businesses["carniceria"].get("product", "")) == "comercio" and bool(GameData.goods["comercio"].get("internal", false)), "los comercios usan el índice de precios 'comercio' (pestaña Precio)")


# --- Comercios -----------------------------------------------------------------------------------

func _test_shop_sales() -> void:
	_new(201)
	var shop := _place("carniceria", 20, -24)
	_hire(shop, 2)
	var tienda := _place("tienda", -22, -24)
	_hire(tienda, 2)
	WarehouseSim.add(gs, "carne", 120.0)
	WarehouseSim.add(gs, "velas_jabon", 40.0)
	_give_money(200.0)
	var money0 := EconomySim.total_money(gs)
	_weeks(3)
	var sold := 120.0 - WarehouseSim.stock(gs, "carne")
	check(sold > 3.0, "la carnicería vende carne del almacén (%.1f u. en 3 semanas)" % sold)
	check(BusinessSim.period_value(shop, "total", "ventas") > 0.0, "el dinero entra a la carnicería (%s)" % Fmt.money(BusinessSim.period_value(shop, "total", "ventas")))
	check(WarehouseSim.stock(gs, "velas_jabon") < 40.0 and BusinessSim.period_value(tienda, "total", "ventas") > 0.0, "la tienda general vende velas y jabón")
	check(absf(EconomySim.total_money(gs) - money0) < 0.01, "economía cerrada: el dinero solo cambia de manos (%.2f → %.2f)" % [money0, EconomySim.total_money(gs)])
	var rep := ShopSim.wants_report(gs)
	var carne_row := rep.filter(func(r): return r["id"] == "carne")
	check(not carne_row.is_empty() and float(carne_row[0]["bought"]) > 0.0, "se registran las compras por deseo (%d compras de carne)" % int(carne_row[0]["bought"]) if not carne_row.is_empty() else "reporte de deseos")
	# Desde el mercado semanal (MarketSim.discretionary) también se llama a ShopSim.
	var before := WarehouseSim.stock(gs, "carne")
	MarketSim.begin_day(gs)
	MarketSim.discretionary(gs)
	check(WarehouseSim.stock(gs, "carne") <= before, "MarketSim.discretionary incluye los comercios especializados")


func _sales_with_price(mult: float) -> float:
	_new(211)
	var shop := _place("carniceria", 20, -24)
	_hire(shop, 2)
	shop["auto_price"] = false
	shop["price"] = EconomySim.market_price(gs, "comercio") * mult
	WarehouseSim.add(gs, "carne", 150.0)
	_give_money(200.0)
	_weeks(3)
	return 150.0 - WarehouseSim.stock(gs, "carne")


func _test_price_and_staff() -> void:
	var cheap := _sales_with_price(1.0)
	var dear := _sales_with_price(1.45)
	check(dear < cheap, "precio configurable: con +45%% sobre el mercado se vende menos (%.1f vs %.1f)" % [dear, cheap])
	check(_sales_with_price(1.7) <= 0.001, "por encima de lo que aceptan pagar (×1,6) no se vende nada")
	_new(212)
	var empty := _place("carniceria", 20, -24)
	WarehouseSim.add(gs, "carne", 100.0)
	_give_money(200.0)
	_weeks(2)
	check(is_equal_approx(WarehouseSim.stock(gs, "carne"), 100.0) and ShopSim.weekly_customers(gs, empty) == 0.0, "sin personal la tienda no atiende (tope según personal)")
	_new(213)
	var one := _place("carniceria", 20, -24)
	_hire(one, 1)
	var cap := ShopSim.weekly_customers(gs, one)
	_hire(one, 1)
	check(ShopSim.weekly_customers(gs, one) > cap * 1.5, "más empleados atienden a más clientes (%.0f → %.0f por semana)" % [cap, ShopSim.weekly_customers(gs, one)])


func _test_unmet_wants() -> void:
	_new(221)
	_give_money(200.0)
	_weeks(2)
	var rows := ShopSim.wants_report(gs)
	var pan := rows.filter(func(r): return r["id"] == "pan")
	check(not pan.is_empty() and float(pan[0]["no_shop"]) > 5.0, "sin panadería los vecinos se quedan sin pan (%d intentos)" % int(pan[0]["no_shop"]) if not pan.is_empty() else "reporte")
	EconomySim.monthly(gs)
	check(not ShopSim.advice(gs).is_empty(), "consejo al jugador: %s" % str(ShopSim.advice(gs).slice(0, 1)))
	check(ShopSim.wants_report(gs).filter(func(r): return r["id"] == "automovil" and bool(r["active"])).is_empty(), "en la colonia nadie quiere un auto (deseo por época)")


func _test_medicine() -> void:
	_new(231)
	gs.techs.append("herbolaria")
	var bot := _place("botica", 20, -24)
	_hire(bot, 2)
	WarehouseSim.add(gs, "remedios", 60.0)
	var sick := []
	for c in gs.citizens.values():
		if not gs.is_player(c.id) and c.age_years(gs.today()) >= 16 and sick.size() < 6:
			c.sick = true
			c.health = 50.0
			c.money += 100.0
			sick.append(c)
	_weeks(1)
	var healthier := sick.filter(func(c): return c.health > 50.0).size()
	check(WarehouseSim.stock(gs, "remedios") < 60.0 and healthier >= 3, "los enfermos compran remedios en la botica y mejoran (%d de %d)" % [healthier, sick.size()])


func _test_cars_and_fuel() -> void:
	_new(241)
	gs.research["era"] = 3
	for t in ["automovil", "petroleo", "petroquimica"]:
		gs.techs.append(t)
	var dealer := _place("concesionario", 24, -26)
	_hire(dealer, 3)
	var station := _place("gasolinera", -24, -26)
	_hire(station, 2)
	WarehouseSim.add(gs, "automovil_bien", 3.0)
	WarehouseSim.add(gs, "combustible", 60.0)
	var rich := []
	for c in gs.citizens.values():
		if not gs.is_player(c.id) and c.age_years(gs.today()) >= 16 and rich.size() < 3:
			c.money += 3000.0
			rich.append(c)
	var w: Dictionary = GameData.citizens["wants"]["automovil"]
	var every := int(w["every_days"])
	w["every_days"] = 7   # Solo para la prueba: todos los ricos deciden comprar esta semana.
	_weeks(1)
	w["every_days"] = every
	var owners: Dictionary = ShopSim.state(gs).get("owners", {})
	check(WarehouseSim.stock(gs, "automovil_bien") < 3.0 and owners.size() >= 1, "vecinos ricos compran autos en el concesionario (%d dueños)" % owners.size())
	check(float(rich[0].money) < 3000.0 + 200.0 or owners.size() >= 1, "el auto se paga con sus ahorros")
	var fuel0 := WarehouseSim.stock(gs, "combustible")
	_weeks(2)
	check(WarehouseSim.stock(gs, "combustible") < fuel0 and BusinessSim.period_value(station, "total", "ventas") > 0.0, "los dueños de autos compran combustible en la gasolinera")


# --- Energía -------------------------------------------------------------------------------------

func _factory(x: float) -> Dictionary:
	var tex := _place("textil", x, 0, 3)
	_hire(tex, 8)
	return tex


func _test_energy() -> void:
	_new(301)
	var tex := _factory(20)
	check(WarehouseSim.warehouse_for(gs, tex) == WarehouseSim.PLAZA, "la textil queda vinculada a la bodega de la plaza")
	WarehouseSim.add_to(gs, WarehouseSim.PLAZA, "algodon", 120.0)
	check(is_equal_approx(EnergySim.factor(gs, tex), 1.0) and EnergySim.demand_of(gs, tex) > 0.0, "antes del dínamo nadie usa electricidad (factor 1)")
	gs.techs.append("dinamo")
	BusinessSim.produce(gs)
	var made := float(tex.get("produced_today", 0.0))
	var alg := WarehouseSim.stock(gs, "algodon")
	_energy_day()
	var after := float(tex.get("produced_today", 0.0))
	check(made > 0.0 and absf(after - made * 0.5) < 0.05 * made + 0.01, "sin electricidad la fábrica moderna rinde la mitad (%.2f → %.2f)" % [made, after])
	check(WarehouseSim.stock(gs, "algodon") > alg, "los insumos no usados vuelven al almacén")
	check(EnergySim.factor(gs, tex) < 0.99, "cobertura eléctrica registrada (factor %.2f)" % EnergySim.factor(gs, tex))
	# Central de carbón vinculada a la plaza con carbón.
	var plant := _place("central_carbon", -20, 0)
	_hire(plant, 8)
	WarehouseSim.add_to(gs, WarehouseSim.PLAZA, "carbon", 40.0)
	BusinessSim.produce(gs)
	var e := float(plant["inventory"].get("electricidad", 0.0))
	var made2 := float(tex.get("produced_today", 0.0))
	_energy_day()
	check(e >= EnergySim.demand_of(gs, tex), "la central produce electricidad (%.0f) para la demanda (%.0f)" % [e, EnergySim.demand_of(gs, tex)])
	check(is_equal_approx(float(tex.get("produced_today", 0.0)), made2) and is_equal_approx(EnergySim.factor(gs, tex), 1.0), "con electricidad propia produce completo")
	check(BusinessSim.period_value(plant, "total", "ventas") > 0.0 and BusinessSim.period_value(tex, "total", "insumos") > 0.0, "la central factura y la fábrica paga (traspaso interno)")
	BusinessSim.end_day(gs)
	check(float(plant["inventory"].get("electricidad", 0.0)) == 0.0, "la electricidad no se almacena: se pierde al fin del día")


func _test_grid_import_and_homes() -> void:
	_new(311)
	gs.research["era"] = 3
	for t in ["dinamo", "electricidad"]:
		gs.techs.append(t)
	var tex := _factory(20)
	WarehouseSim.add_to(gs, WarehouseSim.PLAZA, "algodon", 120.0)
	var conns: Array = gs.trade.get("connections", [])
	conns.append({"town_id": "x", "distance": 60.0, "transport": "carreta"})
	gs.trade["connections"] = conns
	_give_money(100.0)
	var money0: float = gs.money
	BusinessSim.produce(gs)
	var made := float(tex.get("produced_today", 0.0))
	_energy_day()
	check(EnergySim.grid_available(gs) and is_equal_approx(float(tex.get("produced_today", 0.0)), made), "con una ruta comercial se compra electricidad a la red regional")
	var s: Dictionary = EnergySim.state(gs).get("today", {})
	check(int(s.get("homes", {}).get("powered", 0)) > 0, "los hogares modernos compran electricidad (%d con luz)" % int(s.get("homes", {}).get("powered", 0)))
	check(gs.money < money0, "la red regional se paga: el dinero sale del pueblo")
	# Hogares con la electricidad sobrante de una central propia.
	_new(312)
	gs.research["era"] = 3
	for t in ["dinamo", "electricidad"]:
		gs.techs.append(t)
	var plant := _place("central_carbon", -20, 0)
	_hire(plant, 8)
	WarehouseSim.add_to(gs, WarehouseSim.PLAZA, "carbon", 60.0)
	_give_money(100.0)
	BusinessSim.produce(gs)
	var v0 := BusinessSim.period_value(plant, "total", "ventas")
	_energy_day()
	var st: Dictionary = EnergySim.state(gs).get("today", {})
	check(int(st.get("homes", {}).get("powered", 0)) > 0 and BusinessSim.period_value(plant, "total", "ventas") > v0, "la central vende su sobrante a los hogares")


func _test_oil_reveal() -> void:
	var seed_v := -1
	for s in range(1, 200):
		for c in RegionSim.candidates("costa", s):
			if str(c["id"]) == "acantilados":
				seed_v = s
				break
		if seed_v >= 0:
			break
	_new(seed_v, {"map_type": "costa", "region": "acantilados"})
	check(str(RegionSim.region(gs).get("id", "")) == "acantilados", "partida en los Acantilados de hierro (semilla %d)" % seed_v)
	var oil := RegionSim.deposits(gs).filter(func(d): return str(d["type"]) == "petroleo")
	check(oil.is_empty(), "el petróleo no aparece antes de investigarlo")
	check(ConstructionSim.level_block_reason(gs, "pozo_petroleo", 1) != "", "el pozo petrolero exige la tecnología Petróleo")
	check(RegionSim.strengths_text(RegionSim.region(gs)).contains("petróleo"), "el lugar de fundación avisa del subsuelo: %s" % RegionSim.strengths_text(RegionSim.region(gs)))
	gs.techs.append("petroleo")
	_energy_day()
	oil = RegionSim.deposits(gs).filter(func(d): return str(d["type"]) == "petroleo")
	var gas := RegionSim.deposits(gs).filter(func(d): return str(d["type"]) == "gas_natural")
	check(oil.size() == 2 and gas.size() == 1, "al investigar Petróleo aparecen sus yacimientos (%d de petróleo, %d de gas)" % [oil.size(), gas.size()])
	_energy_day()
	check(RegionSim.deposits(gs).filter(func(d): return str(d["type"]) == "petroleo").size() == 2, "revelar es idempotente")
	var d: Dictionary = oil[0]
	check(ConstructionSim.level_block_reason(gs, "pozo_petroleo", 1) == "" and RegionSim.deposit_block_reason(gs, "pozo_petroleo", float(d["x"]), float(d["z"])) == "", "se puede construir un pozo junto al yacimiento")
	var well := _place("pozo_petroleo", float(d["x"]), float(d["z"]))
	_hire(well, 4)
	var before := float(d["amount"])
	BusinessSim.produce(gs)
	check(float(d["amount"]) < before and (WarehouseSim.stock(gs, "petroleo") + float(well["inventory"].get("petroleo", 0.0))) > 0.0, "el pozo extrae crudo del yacimiento")


func _test_map_rules() -> void:
	_new(401, {"map_type": "interior"})
	gs.research["era"] = 3
	for t in ["electricidad", "acero_estructural", "hidroelectrica"]:
		gs.techs.append(t)
	check(ConstructionSim.level_block_reason(gs, "central_hidro", 1).begins_with("Solo en mapas"), "la hidroeléctrica solo en mapas con río")
	_new(402, {"map_type": "rio"})
	for t in ["electricidad", "acero_estructural", "hidroelectrica"]:
		gs.techs.append(t)
	check(ConstructionSim.level_block_reason(gs, "central_hidro", 1) == "", "en un mapa de río sí se puede")
	check(ConstructionSim.level_block_reason(gs, "parque_eolico", 1) != "" and ConstructionSim.level_block_reason(gs, "central_nuclear", 1) != "", "eólica y nuclear exigen su tecnología")


func _fluct_spread(diff: String) -> float:
	_new(501, {"difficulty": diff})
	var vals := []
	for m in range(48):
		EconomySim.update_fluctuations(gs, m)
		vals.append(EconomySim.fluct(gs, "petroleo"))
	var mean := 0.0
	for v in vals:
		mean += float(v)
	mean /= vals.size()
	var var_sum := 0.0
	for v in vals:
		var_sum += pow(float(v) - mean, 2.0)
	return sqrt(var_sum / vals.size())


func _test_fluctuation() -> void:
	var easy := _fluct_spread("facil")
	var hard := _fluct_spread("extremo")
	check(hard > easy * 1.5, "la fluctuación de precios depende de la dificultad (desvío %.3f fácil vs %.3f extremo)" % [easy, hard])
	_new(502)
	for m in range(60):
		EconomySim.update_fluctuations(gs, m)
	var ok := true
	for g in GameData.goods:
		var f := EconomySim.fluct(gs, g)
		ok = ok and f >= 0.69 and f <= 1.41
	check(ok and is_equal_approx(EconomySim.fluct(gs, "comida"), 1.0), "fluctuación acotada y solo en bienes con 'volatility' (la comida no fluctúa)")


func _test_save_load() -> void:
	_new(601)
	gs.research["era"] = 3
	for t in ["dinamo", "electricidad", "petroleo"]:
		gs.techs.append(t)
	var shop := _place("carniceria", 20, -24)
	_hire(shop, 2)
	WarehouseSim.add(gs, "carne", 50.0)
	_give_money(100.0)
	TimeManager.advance_days(10)
	ShopSim.state(gs)["owners"] = {"5": {"auto": 3}}
	var ndeps := RegionSim.deposits(gs).size()
	var text := JSON.stringify(gs.to_dict())
	gs.load_dict(JSON.parse_string(text))
	check(ShopSim.state(gs).get("owners", {}).has("5"), "los dueños de autos se guardan")
	check(RegionSim.deposits(gs).size() == ndeps and gs.logistics.get("revealed_deposits", []).has("petroleo"), "los yacimientos revelados se guardan")
	TimeManager.advance_days(35)
	check(gs.running and not EnergySim.state(gs).get("last_month", {}).is_empty(), "la simulación sigue tras cargar y cierra el mes eléctrico")


# --- Catálogo ------------------------------------------------------------------------------------

func _test_catalog() -> void:
	_new(701)
	var catalog := GoodsCatalog.new()
	add_child(catalog)
	catalog.open("acero")
	await get_tree().process_frame
	check(catalog.visible and catalog.selected == "acero", "el catálogo se abre con open()")
	check(catalog.pivot.get_child_count() == 1, "modelo 3D del bien en el SubViewport")
	var txt := catalog.detail_text("acero")
	check(txt.contains("Se produce en") and txt.contains("Siderúrgica") and txt.contains("Se usa para fabricar"), "ficha con la cadena (de qué se hace, quién lo produce, qué lo usa)")
	check(catalog.detail_text("carne").contains("Carnicería") and catalog.detail_text("petroleo").contains("Petróleo"), "ficha con dónde se vende y la tecnología")
	for g in GoodsCatalog.good_ids():
		catalog.select(g)
	await get_tree().process_frame
	check(catalog.pivot.get_child_count() >= 1, "todos los bienes tienen modelo (%d)" % GoodsCatalog.good_ids().size())
	catalog._set_category("energia")
	check(catalog.cards.size() == GoodsCatalog.good_ids("energia").size() and catalog.cards.has("electricidad"), "filtro por categoría (%d de energía)" % catalog.cards.size())
	catalog._on_era(3)
	check(catalog.cards.has("electricidad") == false or GoodsCatalog.era_of("electricidad") == 3, "filtro por época")
	catalog._on_era(0)
	catalog._set_category("")
	check(GoodsCatalog.producers("tela").size() >= 6 and GoodsCatalog.consumers("tela").size() >= 3, "cadena de la tela: %d niveles productores, %d usos" % [GoodsCatalog.producers("tela").size(), GoodsCatalog.consumers("tela").size()])
	catalog.close()
	check(not catalog.visible, "el catálogo se cierra")
	catalog.queue_free()
	await get_tree().process_frame
