extends Node
## Pruebas de Ventas y distribución (docs/DISTRIBUCION.md): canales de venta, tiendas NPC que reponen,
## pueblos con ruta y vehículo, sucursales, distribuidora, exportación, conservación, guardado e interfaz.
##   godot --headless res://tests/test_distribucion.tscn

var failures := 0
const GOOD := "velas_jabon"


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func _ready() -> void:
	print("== Dinastía: ventas y distribución ==")
	_test_config()
	_test_local_wholesale()
	_test_towns_need_route_and_vehicle()
	_test_branch()
	_test_distributor()
	_test_export()
	_test_priority_and_min_price()
	_test_payments_with_destination()
	_test_save_and_old_save()
	_test_long_run()
	await _test_ui()
	print("== %s (%d fallos) ==" % ["TODO OK" if failures == 0 else "CON FALLOS", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _gs():
	return GameState


func _total() -> float:
	return FlowSim.conserved_total(_gs())


func _rich_citizen(skill: String) -> Citizen:
	var gs = _gs()
	var today: int = gs.today()
	for c in gs.citizens.values():
		if gs.is_player(c.id) or NpcBusinessSim._player_family(gs, c) or NpcBusinessSim._owns_npc(gs, c.id) or c.job_id >= 0:
			continue
		var age: int = c.age_years(today)
		if age >= 25 and age <= 50:
			c.skills[skill] = 60.0
			c.money = 3000.0
			return c
	return null


func _finish_construction(b: Dictionary, max_days := 200) -> void:
	for i in range(max_days):
		if str(b["status"]) == "activo":
			break
		TimeManager.advance_days(1)
	TimeManager.advance_days(1)


## Edificio del jugador ya construido.
func _player_building(type_id: String, x: float, z: float, level := 1) -> Dictionary:
	var gs = _gs()
	var b := ConstructionSim.make_building(gs, type_id, level, x, z, 0.0, "jugador")
	b["status"] = "activo"
	gs.add_building(b)
	WarehouseSim.relink_all(gs)
	return b


func _hire(b: Dictionary, n: int) -> int:
	var gs = _gs()
	var hired := 0
	for c in BusinessSim.candidates(gs, b):
		if hired >= n:
			break
		if BusinessSim.hire(gs, b, c, maxf(GovSim.min_wage(gs), BusinessSim.asked_wage(gs, c, str(b["type"])))) == "":
			hired += 1
	return hired


## Partida con una tienda NPC abierta y una fábrica de velas tuya con stock en el almacén.
func _setup(seed: int) -> Dictionary:
	var gs = _gs()
	gs.new_game({"seed": seed, "difficulty": "normal"})
	gs.money = 60000.0
	TimeManager.advance_days(40)
	var owner := _rich_citizen("comercio")
	var store := NpcBusinessSim.open_business(gs, owner, "tienda", 26.0, -26.0, 0.0)
	_finish_construction(store)
	store["reserve"] = 600.0
	var factory := _player_building("veleria", 40.0, 30.0)
	WarehouseSim.add(gs, GOOD, 150.0)
	# Los vecinos buscaron velas y no encontraron (el mes pasado).
	ShopSim.state(gs)["last_month"] = {"velas_jabon": {"wanted": 40.0, "bought": 0.0, "units": 0.0, "revenue": 0.0, "no_shop": 30.0, "no_stock": 0.0, "too_poor": 0.0}}
	return {"store": store, "factory": factory}


func _connect_town() -> String:
	var gs = _gs()
	var best := ""
	var best_d := INF
	for t in TradeSim.towns(gs):
		if float(t["distance"]) < best_d:
			best_d = float(t["distance"])
			best = str(t["id"])
	var err := TradeSim.open_route(gs, best)
	check(err == "", "abrir ruta con el pueblo más cercano (%s)" % err)
	TimeManager.advance_days(int(TradeSim.project(gs, best).get("total_days", 30)) + 1)
	return best


# --- Configuración ----------------------------------------------------------------------------------

func _test_config() -> void:
	print("-- configuración por producto --")
	var gs = _gs()
	gs.new_game({"seed": 3, "difficulty": "normal"})
	var pc := DistributionSim.product_cfg(gs, GOOD)
	check(pc["priority"].size() == DistributionSim.CONFIG_CHANNELS.size() and str(pc["priority"][0]) == "tienda", "prioridad por defecto: %s" % str(pc["priority"]))
	check(bool(pc["enabled"]["mayorista"]) and not bool(pc["enabled"]["exportacion"]), "mayorista activo y exportación apagada por defecto")
	DistributionSim.move_channel(gs, GOOD, "mayorista", -1)
	check(DistributionSim.before(gs, GOOD, "mayorista", "sucursal"), "subir el mayorista lo pone antes de las sucursales")
	DistributionSim.set_min_wholesale(gs, GOOD, 3.5)
	check(is_equal_approx(DistributionSim.min_wholesale(gs, GOOD), 3.5), "precio mínimo mayorista configurable")
	DistributionSim.set_min_wholesale(gs, GOOD, 0.0)
	check(DistributionSim.min_wholesale(gs, GOOD) > 0.0 and DistributionSim.min_wholesale(gs, GOOD) < DistributionSim.market_ref(gs, GOOD), "0 = mínimo automático (%s)" % Fmt.money2(DistributionSim.min_wholesale(gs, GOOD)))
	var wp := DistributionSim.wholesale_price(gs, GOOD)
	check(wp < DistributionSim.market_ref(gs, GOOD) and wp <= DistributionSim.local_buyer_max(gs, GOOD), "precio mayorista (%s) menor al minorista (%s)" % [Fmt.money2(wp), Fmt.money2(DistributionSim.market_ref(gs, GOOD))])


# --- Mayorista local: las tiendas NPC reponen ----------------------------------------------------------

func _test_local_wholesale() -> void:
	print("-- mayorista local: tiendas NPC reponen según su demanda --")
	var gs = _gs()
	var s := _setup(11)
	var store: Dictionary = s["store"]
	var factory: Dictionary = s["factory"]
	check(DistributionSim.is_reseller(gs, store), "la tienda NPC es revendedora (%s)" % gs.building_label(store))
	check(DistributionSim.reseller_goods(gs, store).has(GOOD), "la tienda NPC puede revender velas y jabón")
	var t0 := _total()
	var cash0 := float(store["reserve"])
	var money0: float = gs.money
	var stock0 := DistributionSim.available(gs, GOOD)
	DistributionSim.weekly(gs)
	var bought := DistributionSim.resale_stock(store, GOOD)
	check(bought > 0.0, "la tienda NPC compró %s velas al por mayor" % Fmt.thousands(bought))
	var price := DistributionSim.wholesale_price(gs, GOOD)
	check(absf((cash0 - float(store["reserve"])) - bought * price) < 0.05, "la tienda pagó de su caja al precio mayorista")
	check(gs.money > money0 + bought * price * 0.5, "el dinero entró al jugador (+%s)" % Fmt.money(gs.money - money0))
	check(BusinessSim.period_value(factory, "month", "ventas") > 0.0, "la venta queda en el libro de la fábrica")
	check(absf(DistributionSim.available(gs, GOOD) - (stock0 - bought)) < 0.01, "salió del almacén")
	check(DistributionSim.sold(gs, GOOD, "mayorista", "month") > 0.0, "estadística del canal mayorista")
	check(absf(_total() - t0) < 0.01, "conservación: la venta mayorista no crea ni destruye dinero")
	# Sin demanda no compra más: ya cubre sus días.
	var again := DistributionSim.resale_stock(store, GOOD)
	DistributionSim.weekly(gs)
	check(DistributionSim.resale_stock(store, GOOD) <= again + 0.5, "con el stock cubierto no vuelve a pedir")
	# Los vecinos le compran a la tienda NPC (deseos de ShopSim).
	for c in gs.citizens.values():
		if not gs.is_player(c.id):
			c.money = maxf(c.money, 200.0)
	var t1 := _total()
	var r0 := float(store["reserve"])
	for w in range(4):
		ShopSim.weekly(gs)
	var sold_npc := float(store.get("resale_sold", {}).get(GOOD, 0.0))
	check(sold_npc > 0.0, "los vecinos compraron %s velas en la tienda NPC" % Fmt.thousands(sold_npc))
	check(float(store["reserve"]) > r0, "la tienda NPC cobró de los vecinos (su caja sube)")
	check(DistributionSim.resale_price(gs, store, GOOD) > price, "revende más caro de lo que compró (margen de la tienda)")
	check(absf(_total() - t1) < 0.01, "conservación: la reventa a los vecinos es entre bolsillos del pueblo")


# --- Pueblos: sin ruta ni vehículo no llega ----------------------------------------------------------

func _test_towns_need_route_and_vehicle() -> void:
	print("-- pueblos: hace falta ruta y vehículo --")
	var gs = _gs()
	_setup(13)
	WarehouseSim.add(gs, GOOD, 150.0)
	var ctx := DistributionSim._context(gs)
	var tid := str(TradeSim.towns(gs)[0]["id"])
	check(DistributionSim.reach_block(gs, ctx, tid) == "sin ruta", "sin ruta el producto no llega")
	DistributionSim.weekly(gs)
	check(DistributionSim.state(gs)["trips"].is_empty(), "sin ruta no sale ningún envío")
	tid = _connect_town()
	ctx = DistributionSim._context(gs)
	check(DistributionSim.reach_block(gs, ctx, tid) == "sin vehículo", "con ruta pero sin vehículo tampoco llega")
	DistributionSim.weekly(gs)
	check(DistributionSim.state(gs)["trips"].filter(func(t): return str(t["kind"]) == "mayorista").is_empty(), "sin vehículo no sale ningún envío")
	# Central de transporte con cargadores (división interna).
	var central := _player_building("central_transporte", -40.0, 40.0)
	check(_hire(central, 4) > 0, "contratar cargadores en la central de transporte")
	ctx = DistributionSim._context(gs)
	check(not ctx["carriers"].is_empty(), "la central es un vehículo disponible (%s u/semana)" % Fmt.thousands(float(ctx["carriers"][0]["cap"])))
	var town := TradeSim.town(gs, tid)
	town["cash"] = 5000.0
	var t0 := _total()
	var cash0 := float(town["cash"])
	DistributionSim.weekly(gs)
	var trips: Array = DistributionSim.state(gs)["trips"].filter(func(t): return str(t["kind"]) == "mayorista")
	check(not trips.is_empty(), "con ruta y vehículo sale el envío a %s" % str(town.get("name", "")))
	if trips.is_empty():
		return
	var trip: Dictionary = trips[0]
	check(float(trip["freight"]) > 0.0, "el transporte cuesta (%s)" % Fmt.money(float(trip["freight"])))
	check(BusinessSim.period_value(central, "month", "insumos") >= float(trip["freight"]) - 0.01, "lo paga la central (combustible y forraje)")
	var tkm: Dictionary = TransportDivSim.st(gs)["month"]["tkm"]
	check(tkm.has(str(int(central["id"]))), "el viaje queda en la división de transporte (TransportDivSim)")
	check(absf(_total() - t0) < 0.01, "conservación al despachar (el flete va a proveedores y a la cuenta externa)")
	var money0: float = gs.money
	for i in range(int(trip["arrive"]) - int(gs.today())):
		TimeManager.total_hours += 24
		DistributionSim._arrivals(gs)
	DistributionSim._arrivals(gs)
	check(float(town["cash"]) < cash0, "el pueblo pagó desde su caja al llegar (%s)" % Fmt.money(cash0 - float(town["cash"])))
	check(gs.money > money0, "el dinero entró al jugador")
	check(DistributionSim.sold(gs, GOOD, "mayorista", "month") > 0.0, "venta mayorista a otro pueblo registrada")
	check(absf(_total() - t0) < 0.01, "conservación: el pago del pueblo es entre bolsillos")
	# Empresa de transporte: factura el flete al negocio (traspaso dentro del grupo).
	TransportDivSim.set_org(gs, central, "empresa", "Transportes Prueba")
	var fee := TransportDivSim.record_trip(gs, central, int(_gs().buildings.filter(func(b): return str(b["type"]) == "veleria")[0]["id"]), 10.0, 40.0)
	check(fee > 0.0, "como empresa aparte, la transportadora factura el flete (%s)" % Fmt.money(fee))


# --- Sucursales ---------------------------------------------------------------------------------------

func _test_branch() -> void:
	print("-- sucursal en otro pueblo --")
	var gs = _gs()
	_setup(17)
	WarehouseSim.add(gs, GOOD, 150.0)
	var tid0 := str(TradeSim.towns(gs)[0]["id"])
	check(DistributionSim.open_branch(gs, tid0) != "", "sin ruta no se puede abrir sucursal")
	var tid := _connect_town()
	var town := TradeSim.town(gs, tid)
	town["cash"] = 8000.0
	var t0 := _total()
	var money0: float = gs.money
	var tc0 := float(town["cash"])
	check(DistributionSim.open_branch(gs, tid) == "", "abrir sucursal en %s" % str(town.get("name", "")))
	var cost := DistributionSim.branch_open_cost(gs)
	check(absf(money0 - gs.money - cost) < 0.01 and absf(float(town["cash"]) - tc0 - cost) < 0.01, "la apertura (%s) la cobran constructores de ese pueblo" % Fmt.money(cost))
	check(DistributionSim.open_branch(gs, tid) != "", "no se abren dos sucursales en el mismo pueblo")
	var central := _player_building("central_transporte", -40.0, 40.0)
	_hire(central, 4)
	DistributionSim.weekly(gs)
	var trips: Array = DistributionSim.state(gs)["trips"].filter(func(t): return str(t["kind"]) == "sucursal")
	check(not trips.is_empty(), "la sucursal se abastece por la ruta")
	var br: Dictionary = DistributionSim.branch_in(gs, tid)
	for i in range(12):
		TimeManager.total_hours += 24
		DistributionSim._arrivals(gs)
		DistributionSim._branch_sales(gs)
	check(float(br["ledger"]["month"].get("ventas", 0.0)) > 0.0, "la sucursal vende al detalle allá (%s)" % Fmt.money(float(br["ledger"]["month"].get("ventas", 0.0))))
	check(DistributionSim.sold(gs, GOOD, "sucursal", "month") > 0.0, "canal sucursal registrado")
	var unit := DistributionSim.revenue(gs, GOOD, "sucursal", "month") / maxf(0.001, DistributionSim.sold(gs, GOOD, "sucursal", "month"))
	check(unit > DistributionSim.town_wholesale_price(gs, tid, GOOD, 1.0), "al detalle vende más caro que al por mayor (%s)" % Fmt.money2(unit))
	var m1: float = gs.money
	DistributionSim.monthly(gs)
	check(gs.money < m1 and float(br["ledger"]["month"].get("costos", 0.0)) > 0.0, "arriendo y personal mensual (%s, a la caja del pueblo)" % Fmt.money(m1 - gs.money))
	check(absf(_total() - t0) < 0.05, "conservación de la sucursal (apertura, ventas y costos)")
	var id := int(br["id"])
	check(DistributionSim.close_branch(gs, id) == "" and DistributionSim.branches(gs).is_empty(), "cerrar la sucursal devuelve el stock")


# --- Distribuidora ------------------------------------------------------------------------------------

func _test_distributor() -> void:
	print("-- distribuidora --")
	var gs = _gs()
	var s := _setup(19)
	var store: Dictionary = s["store"]
	var factory: Dictionary = s["factory"]
	var d := _player_building("distribuidora", -30.0, -45.0)
	check(DistributionSim.is_distributor(gs, d), "la distribuidora es un negocio de distribución")
	check(BusinessSim.is_business(d), "cuenta como negocio (contrata y lleva libro)")
	check(_hire(d, 3) > 0, "contratar personal de la distribuidora")
	DistributionSim.move_channel(gs, GOOD, "distribuidora", -1)
	DistributionSim.move_channel(gs, GOOD, "distribuidora", -1)
	check(DistributionSim.before(gs, GOOD, "distribuidora", "mayorista"), "prioridad: la distribuidora antes que la venta directa")
	var t0 := _total()
	var m0: float = gs.money
	DistributionSim.weekly(gs)
	var sold_dist := DistributionSim.sold(gs, GOOD, "distribuidora", "month")
	check(sold_dist > 0.0, "la distribuidora vendió %s velas a la tienda NPC" % Fmt.thousands(sold_dist))
	check(DistributionSim.sold(gs, GOOD, "mayorista", "month") <= 0.0, "la venta directa no tomó esa demanda (va después)")
	check(BusinessSim.period_value(d, "month", "mercaderia") > 0.0 and BusinessSim.period_value(factory, "month", "ventas") > 0.0, "traspaso interno: la fábrica vende y la distribuidora compra en el libro")
	check(BusinessSim.period_value(d, "month", "ventas") > BusinessSim.period_value(d, "month", "mercaderia") * 0.99 or DistributionSim.dist_used(d) > 0.0, "la distribuidora gana su margen")
	check(DistributionSim.resale_stock(store, GOOD) > 0.0, "la tienda NPC recibió la mercancía")
	check(gs.money > m0, "entró dinero de la tienda NPC al grupo")
	check(absf(_total() - t0) < 0.01, "conservación: el traspaso interno no mueve dinero")
	# Compra a empresas NPC: un leñador con excedente; un pueblo con ruta pide leña.
	var owner := _rich_citizen("agricultura")
	var lena := NpcBusinessSim.open_business(gs, owner, "lenador", -26.0, 26.0, 0.0)
	_finish_construction(lena)
	lena["inventory"]["lena"] = 300.0
	var tid := _connect_town()
	var town := TradeSim.town(gs, tid)
	town["cash"] = 6000.0
	var row: Dictionary = town["goods"].get("lena", {})
	if not row.is_empty():
		row["demand"] = maxf(float(row.get("demand", 0.0)), 200.0)
		row["sat"] = 0.0
	var lr0 := float(lena["reserve"])
	var t1 := _total()
	DistributionSim.state(gs)["fleet"] = {}
	DistributionSim.weekly(gs)
	check(float(lena["reserve"]) > lr0, "la distribuidora le compró leña a la empresa NPC (su caja +%s)" % Fmt.money(float(lena["reserve"]) - lr0))
	var trips: Array = DistributionSim.state(gs)["trips"].filter(func(t): return str(t["kind"]) == "distribuidora")
	check(not trips.is_empty(), "y la lleva con su flota al pueblo con ruta")
	check(absf(_total() - t1) < 0.01, "conservación al comprarle a la empresa NPC")
	for i in range(20):
		TimeManager.total_hours += 24
		DistributionSim._arrivals(gs)
	check(DistributionSim.sold(gs, "lena", "distribuidora", "month") > 0.0, "el pueblo pagó la leña a la distribuidora")
	check(absf(_total() - t1) < 0.05, "conservación en la entrega al pueblo")


# --- Exportación ------------------------------------------------------------------------------------

func _test_export() -> void:
	print("-- exportación --")
	var gs = _gs()
	_setup(23)
	DistributionSim.set_enabled(gs, GOOD, "exportacion", true)
	WarehouseSim.add(gs, GOOD, 50.0)
	DistributionSim.weekly(gs)
	check(DistributionSim.state(gs)["trips"].filter(func(t): return str(t["kind"]) == "exportacion").is_empty(), "sin ruta ni puerto no se exporta")
	_connect_town()
	var central := _player_building("central_transporte", -40.0, 40.0)
	_hire(central, 5)
	var t0 := _total()
	var ext_in0 := float(gs.economy["external"]["in"].get("exportación (distribución)", 0.0))
	DistributionSim.state(gs)["fleet"] = {}
	DistributionSim.weekly(gs)
	var trips: Array = DistributionSim.state(gs)["trips"].filter(func(t): return str(t["kind"]) == "exportacion")
	check(not trips.is_empty(), "con ruta y vehículo se exporta el excedente")
	for i in range(20):
		TimeManager.total_hours += 24
		DistributionSim._arrivals(gs)
	var ext_in := float(gs.economy["external"]["in"].get("exportación (distribución)", 0.0)) - ext_in0
	check(ext_in > 0.0, "el dinero de la exportación entra del exterior con su motivo (%s)" % Fmt.money(ext_in))
	check(DistributionSim.sold(gs, GOOD, "exportacion", "month") > 0.0, "canal exportación registrado")
	check(absf(_total() - t0) < 0.05, "conservación: la exportación queda en la cuenta externa")


# --- Prioridad y precio mínimo ---------------------------------------------------------------------

func _test_priority_and_min_price() -> void:
	print("-- prioridad de canal y precio mínimo --")
	var gs = _gs()
	var s := _setup(29)
	var store: Dictionary = s["store"]
	DistributionSim.set_min_wholesale(gs, GOOD, DistributionSim.market_ref(gs, GOOD) * 2.0)
	DistributionSim.weekly(gs)
	check(DistributionSim.resale_stock(store, GOOD) <= 0.0, "con el precio mínimo sobre lo que pagan, no vende al por mayor")
	check(not DistributionSim.notes(gs).is_empty(), "y lo avisa en el panel")
	DistributionSim.set_min_wholesale(gs, GOOD, 0.0)
	# Tus tiendas van primero: el mayorista deja la reserva de ellas.
	_player_building("tienda", 50.0, -10.0)
	DistributionSim.record(gs, "tienda", GOOD, 60.0, 60.0 * DistributionSim.market_ref(gs, GOOD))
	var reserve := DistributionSim.shop_reserve(gs, GOOD)
	check(reserve > 0.0, "reserva para tus tiendas: %s unidades" % Fmt.thousands(reserve))
	check(absf(DistributionSim.sellable(gs, GOOD, "mayorista") - maxf(0.0, DistributionSim.available(gs, GOOD) - reserve)) < 0.01, "el mayorista solo toma lo que pasa de la reserva")
	DistributionSim.move_channel(gs, GOOD, "tienda", 1)
	DistributionSim.move_channel(gs, GOOD, "tienda", 1)
	DistributionSim.move_channel(gs, GOOD, "tienda", 1)
	check(is_equal_approx(DistributionSim.sellable(gs, GOOD, "mayorista"), DistributionSim.available(gs, GOOD)), "si las tiendas van después, el mayorista puede tomarlo todo")
	DistributionSim.set_enabled(gs, GOOD, "mayorista", false)
	var before := DistributionSim.resale_stock(store, GOOD)
	DistributionSim.weekly(gs)
	check(is_equal_approx(DistributionSim.resale_stock(store, GOOD), before), "un canal apagado no vende")


# --- Pagos con destino (logística, transporte público y comercio exterior) -------------------------

func _test_payments_with_destination() -> void:
	print("-- pagos de logística, buses y rutas con destino (FlowSim) --")
	var gs = _gs()
	gs.new_game({"seed": 31, "difficulty": "normal"})
	gs.money = 50000.0
	var tid := str(TradeSim.towns(gs)[0]["id"])
	var t0 := _total()
	check(TradeSim.open_route(gs, tid) == "", "abrir ruta (acuerdo y camino)")
	check(absf(_total() - t0) < 0.01, "la obra de la ruta la cobran contratistas (FlowSim, motivo obras)")
	TimeManager.advance_days(int(TradeSim.project(gs, tid).get("total_days", 30)) + 1)
	var t1 := _total()
	WarehouseSim.add(gs, "madera", 40.0)
	check(TradeSim.sell(gs, tid, "madera", 20.0) == "", "vender madera a un pueblo (comercio exterior)")
	for i in range(30):
		TimeManager.total_hours += 24
		TradeSim._deliver(gs, gs.today())
	check(absf(_total() - t1) < 0.05, "flete y cobro de la venta al pueblo conservan el dinero")
	check(DistributionSim.sold(gs, "madera", "exportacion", "month") > 0.0, "la venta del comercio exterior cuenta en el canal exportación")
	var t2 := _total()
	TradeSim._upkeep(gs)
	check(absf(_total() - t2) < 0.01, "el mantenimiento de caminos va a proveedores")
	# Vehículos de logística: alimento y mantenimiento con destino.
	var central := _player_building("central_transporte", -40.0, 40.0, 2)
	_hire(central, 3)
	var t3 := _total()
	LogisticsSim._vehicle_upkeep(gs)
	check(absf(_total() - t3) < 0.01, "alimento y mantenimiento de la flota de logística con destino")
	# Buses: mantenimiento con destino.
	var t4 := _total()
	TransitSim._bus_costs(gs)
	check(absf(_total() - t4) < 0.01, "mantenimiento y combustible de buses con destino")


# --- Guardado ------------------------------------------------------------------------------------------

func _test_save_and_old_save() -> void:
	print("-- guardado y partidas viejas --")
	var gs = _gs()
	var s := _setup(37)
	DistributionSim.set_min_wholesale(gs, GOOD, 2.25)
	DistributionSim.move_channel(gs, GOOD, "exportacion", -1)
	DistributionSim.weekly(gs)
	var stock := DistributionSim.resale_stock(s["store"], GOOD)
	var d: Dictionary = gs.to_dict()
	gs.load_dict(JSON.parse_string(JSON.stringify(d)))
	check(is_equal_approx(DistributionSim.min_wholesale(gs, GOOD), 2.25), "el precio mínimo se guarda")
	check(DistributionSim.before(gs, GOOD, "exportacion", "distribuidora"), "la prioridad se guarda")
	var st2: Dictionary = gs.get_building(int(s["store"]["id"]))
	check(absf(DistributionSim.resale_stock(st2, GOOD) - stock) < 0.01, "el stock de reventa de la tienda NPC se guarda")
	# Partida vieja: sin estado de distribución ni campos nuevos en los edificios.
	var old: Dictionary = gs.to_dict()
	old["market"].erase("distribution")
	for b in old["buildings"]:
		for k in ["resale", "resale_cost", "resale_sold", "resale_sold_last", "dist_stock", "dist_cost", "dist_margin"]:
			b.erase(k)
	gs.load_dict(JSON.parse_string(JSON.stringify(old)))
	check(gs.market.has("distribution"), "partida vieja: se crea el estado de distribución")
	var pc := DistributionSim.product_cfg(gs, GOOD)
	check(str(pc["priority"][0]) == "tienda" and float(pc["min_wholesale"]) == 0.0, "partida vieja: valores por defecto")
	TimeManager.advance_days(10)
	check(gs.running, "la partida vieja sigue corriendo con distribución")


# --- Partida larga: conservación, población y ganancias ---------------------------------------------

func _test_long_run() -> void:
	print("-- 3 años con todos los canales --")
	var gs = _gs()
	var s := _setup(41)
	var tid := _connect_town()
	var central := _player_building("central_transporte", -40.0, 40.0)
	_hire(central, 4)
	var d := _player_building("distribuidora", -30.0, -45.0)
	_hire(d, 3)
	_hire(s["factory"], 3)
	DistributionSim.open_branch(gs, tid)
	DistributionSim.set_enabled(gs, GOOD, "exportacion", true)
	WarehouseSim.add(gs, GOOD, 200.0)
	var pop0: int = gs.citizens.size()
	var worst := 0.0
	var revenue := 0.0
	var freight := 0.0
	for m in range(36):
		if not gs.running:
			break
		gs.money = maxf(gs.money, 20000.0)   # El bot no quiebra; lo que se mide es la distribución.
		var tb := _total()
		for day in range(30):
			TimeManager.advance_days(1)
		worst = maxf(worst, absf(_total() - tb))
		var tot := DistributionSim.channel_totals(gs, "last_month")
		for ch in tot:
			if ch != "tienda" and ch != "contratos":
				revenue += float(tot[ch]["revenue"])
				freight += float(tot[ch]["freight"])
		WarehouseSim.add(gs, GOOD, 60.0)   # Lo que produjo la velería en el mes (sin depender de sus insumos).
	var branch_costs := 0.0
	for br in DistributionSim.branches(gs):
		branch_costs += float(br["ledger"]["total"].get("costos", 0.0))
	print("    ingresos por canales de distribución %s · fletes %s · costos de sucursal %s · población %d → %d" % [Fmt.money(revenue), Fmt.money(freight), Fmt.money(branch_costs), pop0, gs.citizens.size()])
	check(gs.running, "la partida sigue después de 3 años")
	check(worst < 2.0, "conservación mes a mes con distribución (peor mes %.3f)" % worst)
	check(revenue > freight + branch_costs, "vender por los canales deja ganancia (%s contra %s de fletes y sucursales)" % [Fmt.money(revenue), Fmt.money(freight + branch_costs)])
	check(gs.citizens.size() >= pop0, "la población no cae (%d → %d)" % [pop0, gs.citizens.size()])


# --- Interfaz ------------------------------------------------------------------------------------------

func _test_ui() -> void:
	print("-- interfaz --")
	var gs = _gs()
	var s := _setup(43)
	_connect_town()
	_player_building("distribuidora", -30.0, -45.0)
	DistributionSim.weekly(gs)
	var p := DistributionPanel.new()
	p.custom_minimum_size = Vector2(440, 700)
	add_child(p)
	p.setup(null)
	for t in ["productos", "sucursales", "distribuidora", "clientes"]:
		p.set_tab(t)
		await get_tree().process_frame
	p.sel_good = GOOD
	p.set_tab("productos")
	await get_tree().process_frame
	check(p.body.get_child_count() > 2, "el panel muestra los productos y su detalle")
	p.period = "month"
	p.refresh()
	await get_tree().process_frame
	check(true, "el panel Ventas y distribución abre todas sus pestañas")
	p.queue_free()
