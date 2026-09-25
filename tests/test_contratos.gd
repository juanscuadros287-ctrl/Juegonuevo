extends Node
## Pruebas de contratos recurrentes de compra y venta a precio fijo (libre mercado).
## godot --headless res://tests/test_contratos.tscn

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func _ready() -> void:
	print("== Dinastía: pruebas de contratos recurrentes ==")
	_test_recurring_purchase()
	_test_recurring_sale()
	_test_supplier_out_of_stock()
	_test_player_no_money_or_space()
	_test_counteroffers()
	_test_town_and_import_purchase()
	_test_supply_offers_from_npc()
	_test_cancel()
	_test_migration()
	_test_save_load()
	await _test_ui()
	print("== %s (%d fallos) ==" % ["TODO OK" if failures == 0 else "CON FALLOS", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _gs():
	return GameState


func _total() -> float:
	return float(FreeMarketSim.money_snapshot(_gs())["total"])


## Solo el mercado (aislado del resto de la economía): contratos, empresas NPC y planes.
func _market_days(n: int) -> void:
	for i in range(n):
		TimeManager.total_hours += 24
		FreeMarketSim.daily(_gs())


func _rich_citizen(skill: String) -> Citizen:
	var gs = _gs()
	var today: int = gs.today()
	for c in gs.citizens.values():
		if gs.is_player(c.id) or NpcBusinessSim._player_family(gs, c) or NpcBusinessSim._owns_npc(gs, c.id):
			continue
		var age: int = c.age_years(today)
		if age >= 25 and age <= 45:
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


## Partida con un leñador NPC abierto (proveedor de leña). Devuelve el edificio.
func _setup_supplier(seed: int) -> Dictionary:
	var gs = _gs()
	GameState.new_game({"seed": seed, "difficulty": "normal"})
	gs.money = 50000.0
	TimeManager.advance_days(40)
	var owner := _rich_citizen("agricultura")
	var b := NpcBusinessSim.open_business(gs, owner, "lenador", 25.0, -25.0, 0.0)
	_finish_construction(b)
	b["reserve"] = 400.0
	b["inventory"]["lena"] = 500.0
	return b


func _player_farm() -> Dictionary:
	var gs = _gs()
	var b := ConstructionSim.make_building(gs, "granja", 1, 40.0, -30.0, 0.0, "jugador")
	gs.add_building(b)
	b["inventory"]["comida"] = 400.0
	return b


func _connect_town(pred: Callable) -> String:
	var gs = _gs()
	for t in TradeSim.towns(gs):
		if pred.call(t):
			var tid := str(t["id"])
			var err := TradeSim.open_route(gs, tid)
			check(err == "", "abrir ruta con %s (%s)" % [t.get("name", ""), err])
			TimeManager.advance_days(int(TradeSim.project(gs, tid).get("total_days", 30)) + 1)
			return tid
	return ""


## Propone y avanza hasta la respuesta. Devuelve la propuesta.
func _propose_and_wait(d: String, key: String, good: String, qty: float, price: float, opts: Dictionary) -> Dictionary:
	var gs = _gs()
	var err := ContractSim.propose(gs, d, key, good, qty, price, opts)
	check(err == "", "propuesta de %s enviada (%s)" % [d, err])
	var o: Dictionary = ContractSim.sent(gs)[ContractSim.sent(gs).size() - 1]
	check(str(o["status"]) == "pendiente", "la contraparte todavía no responde")
	_market_days(6)
	return o


# --- Compra recurrente ---------------------------------------------------------------------------------

func _test_recurring_purchase() -> void:
	print("-- compra recurrente cada 15 días × 4 --")
	var gs = _gs()
	var b := _setup_supplier(41)
	var key := "npc:%d" % int(b["id"])
	check(ContractSim.supplier_keys(gs, "lena").has(key), "el leñador NPC es proveedor de leña")
	check(ContractSim.supplier_keys(gs, "lena").has(ContractSim.IMPORT_KEY), "la importación es el último recurso")
	var ref := ContractSim.reference_price(gs, key, "lena", 20, ContractSim.DIR_BUY)
	check(ref > 0.0, "precio de referencia de compra %s" % Fmt.money2(ref))
	var price := snappedf(ref * 1.05, 0.01)
	var o := _propose_and_wait(ContractSim.DIR_BUY, key, "lena", 20, price, {"period": 15, "installments": 4, "start_in": 10, "auto": true, "wid": 0})
	check(str(o["status"]) == "aceptada", "el proveedor acepta (%s)" % o.get("reason", ""))
	var k := ContractSim.find(ContractSim.contracts(gs), int(o.get("contract_id", -1)))
	check(not k.is_empty() and ContractSim.is_buy(k), "contrato de compra firmado")
	if k.is_empty():
		return
	check(int(k["period"]) == 15 and int(k["installments"]) == 4 and bool(k["auto"]), "frecuencia 15 días, 4 entregas, automática")
	check(int(k["end_day"]) == int(k["start_day"]) + 45, "fecha de fin = inicio + 3 × 15")
	var before := _total()
	var m0: float = gs.money
	var r0 := float(b["reserve"])
	var w0 := WarehouseSim.stock_in(gs, 0, "lena")
	var inv0 := float(b["inventory"]["lena"])
	var days_done: Array = []
	var fluct_changed := false
	for i in range(60):
		var d0 := int(k["done"])
		_market_days(1)
		if int(k["done"]) > d0:
			days_done.append(gs.today())
			if not fluct_changed:
				# El mercado cambia (la leña se duplica): el contrato mantiene el precio fijo.
				var eg: Dictionary = gs.economy.get("goods", {})
				if not eg.has("lena"):
					eg["lena"] = {}
				eg["lena"]["fluct"] = 2.0
				gs.economy["goods"] = eg
				fluct_changed = true
	check(int(k["done"]) == 4 and str(k["status"]) == "cumplido", "4 entregas y contrato cumplido (%d, %s)" % [int(k["done"]), k["status"]])
	check(days_done.size() == 4 and int(days_done[1]) - int(days_done[0]) == 15 and int(days_done[3]) - int(days_done[2]) == 15, "cada 15 días: %s" % str(days_done))
	check(absf(WarehouseSim.stock_in(gs, 0, "lena") - w0 - 80.0) < 0.01, "llegaron 80 de leña a la bodega de la plaza")
	check(absf(inv0 - float(b["inventory"]["lena"]) - 80.0) < 0.01, "el proveedor descontó su stock")
	var expected := 80.0 * price
	check(absf(m0 - gs.money - expected) < 0.01, "pagaste 80 × %s = %s (precio fijo aunque el mercado subió)" % [Fmt.money2(price), Fmt.money(expected)])
	check(absf(float(b["reserve"]) - r0 - expected) < 0.01, "el dinero llegó a la caja del proveedor")
	check(EconomySim.market_price(gs, "lena") > ref * 1.5, "el precio de mercado sí cambió")
	check(absf(_total() - before) < 0.01, "dinero conservado (Δ %.3f)" % (_total() - before))
	check(ContractSim.reliability(gs, key) > float(ContractSim.cfg().get("reliability_start", 80)), "la fiabilidad del proveedor sube al cumplir")


# --- Venta recurrente ----------------------------------------------------------------------------------

func _test_recurring_sale() -> void:
	print("-- venta recurrente con frecuencia --")
	var gs = _gs()
	GameState.new_game({"seed": 43, "difficulty": "normal"})
	gs.money = 50000.0
	var farm := _player_farm()
	TimeManager.advance_days(40)
	var owner := _rich_citizen("comercio")
	var npc := NpcBusinessSim.open_business(gs, owner, "tienda", 30.0, 20.0, 0.0)
	_finish_construction(npc)
	npc["reserve"] = 2000.0
	var key := "npc:%d" % int(npc["id"])
	# Solicitud entrante quincenal.
	var r := ContractSim.create_request(gs, key, "comida", 10, 0.4, 3, 30, -1, 15)
	check(not r.is_empty() and int(r["period"]) == 15, "solicitud recurrente quincenal")
	ContractSim.accept_request(gs, int(r["id"]))
	var k: Dictionary = ContractSim.active_contracts(gs)[0]
	check(int(k["period"]) == 15 and int(k["next_due"]) == gs.today() + 15, "primera entrega a los 15 días")
	farm["inventory"]["comida"] = 0.0
	WarehouseSim.add(gs, "comida", 60.0)
	var before := _total()
	var m0: float = gs.money
	var days: Array = []
	for i in range(50):
		var d0 := int(k["done"])
		_market_days(1)
		if int(k["done"]) > d0:
			days.append(gs.today())
	check(int(k["done"]) == 3 and str(k["status"]) == "cumplido", "3 entregas automáticas (%d)" % int(k["done"]))
	check(days.size() == 3 and int(days[1]) - int(days[0]) == 15, "cada 15 días: %s" % str(days))
	check(absf(gs.money - m0 - 12.0) < 0.01, "cobraste 3 × 10 × 0,40 = 12")
	check(absf(_total() - before) < 0.01, "dinero conservado en las ventas")
	# Propuesta de venta semanal del jugador.
	WarehouseSim.add(gs, "comida", 60.0)
	var ref := ContractSim.reference_price(gs, key, "comida", 8)
	var o := _propose_and_wait(ContractSim.DIR_SELL, key, "comida", 8, ref, {"period": 7, "installments": 2, "start_in": 7, "auto": true})
	check(str(o["status"]) == "aceptada", "la tienda acepta la venta semanal (%s)" % o.get("reason", ""))
	var k2 := ContractSim.find(ContractSim.contracts(gs), int(o.get("contract_id", -1)))
	_market_days(14)
	check(not k2.is_empty() and int(k2["done"]) == 2 and str(k2["status"]) == "cumplido", "2 entregas semanales")


# --- Proveedor sin stock --------------------------------------------------------------------------------

func _test_supplier_out_of_stock() -> void:
	print("-- proveedor sin stock --")
	var gs = _gs()
	var b := _setup_supplier(45)
	var key := "npc:%d" % int(b["id"])
	var ref := ContractSim.reference_price(gs, key, "lena", 20, ContractSim.DIR_BUY)
	var o := _propose_and_wait(ContractSim.DIR_BUY, key, "lena", 20, ref * 1.05, {"period": 15, "installments": 4, "start_in": 10})
	var k := ContractSim.find(ContractSim.contracts(gs), int(o.get("contract_id", -1)))
	check(not k.is_empty(), "contrato firmado")
	if k.is_empty():
		return
	b["inventory"]["lena"] = 0.0
	b["reserve"] = 500.0
	var rel0 := ContractSim.reliability(gs, key)
	var before := _total()
	var m0: float = gs.money
	var r0 := float(b["reserve"])
	var due := int(k["next_due"])
	while gs.today() < due:
		b["inventory"]["lena"] = 0.0
		_market_days(1)
	check(int(k["cp_failed"]) == 1 and int(k["done"]) == 0, "el proveedor incumple la entrega")
	var pen := float(k["cp_penalty"])
	check(pen > 0.0 and absf(gs.money - m0 - pen) < 0.01, "te pagó la penalidad (%s)" % Fmt.money(pen))
	check(absf(r0 - float(b["reserve"]) - pen) < 0.01, "salió de su caja")
	check(ContractSim.reliability(gs, key) < rel0, "baja su fiabilidad (%d → %d)" % [int(rel0), int(ContractSim.reliability(gs, key))])
	check(absf(_total() - before) < 0.01, "la penalidad solo cambia de manos")
	check(ContractSim.reputation(gs, key) >= float(ContractSim.cfg().get("rep_start", 50)), "tu reputación no baja por culpa del proveedor")
	for i in range(16):
		b["inventory"]["lena"] = 0.0
		_market_days(1)
	check(str(k["status"]) == "incumplido" and str(k.get("breached_by", "")) == "proveedor", "a la segunda falla el contrato termina por culpa del proveedor")


# --- Jugador sin dinero o sin espacio ---------------------------------------------------------------------

func _test_player_no_money_or_space() -> void:
	print("-- jugador sin dinero o sin espacio --")
	var gs = _gs()
	var b := _setup_supplier(47)
	var key := "npc:%d" % int(b["id"])
	var ref := ContractSim.reference_price(gs, key, "lena", 20, ContractSim.DIR_BUY)
	var o := _propose_and_wait(ContractSim.DIR_BUY, key, "lena", 20, ref * 1.05, {"period": 15, "installments": 4, "start_in": 10})
	var k := ContractSim.find(ContractSim.contracts(gs), int(o.get("contract_id", -1)))
	if k.is_empty():
		check(false, "contrato firmado")
		return
	# Sin dinero.
	gs.money = 1.0
	var rep0 := ContractSim.reputation(gs, key)
	var r0 := float(b["reserve"])
	var inv0 := float(b["inventory"]["lena"])
	var before := _total()
	var due := int(k["next_due"])
	while gs.today() < due:
		_market_days(1)
	check(int(k["failed"]) == 1 and int(k["done"]) == 0, "sin dinero: incumples tú")
	check(absf(float(b["reserve"]) - r0 - float(k["penalty"])) < 0.01, "el proveedor cobra tu penalidad")
	check(absf(float(b["inventory"]["lena"]) - inv0) < 0.01 or float(b["inventory"]["lena"]) >= inv0, "el proveedor conserva su stock")
	check(ContractSim.reputation(gs, key) < rep0, "baja tu reputación")
	check(absf(_total() - before) < 0.01, "dinero conservado")
	# Sin espacio: la bodega de la plaza está llena.
	gs.money = 50000.0
	var cap := WarehouseSim.free_in(gs, 0)
	WarehouseSim.add_to(gs, 0, "piedra", cap)
	check(WarehouseSim.free_in(gs, 0) < 1.0, "bodega de la plaza llena")
	check(ContractSim.player_buy_block(gs, k).contains("espacio"), "no puedes recibir: %s" % ContractSim.player_buy_block(gs, k))
	var due2 := int(k["next_due"])
	while gs.today() < due2:
		_market_days(1)
	check(int(k["failed"]) == 2 and str(k["status"]) == "incumplido" and str(k.get("breached_by", "")) == "jugador", "sin espacio: incumples otra vez y se cancela")


# --- Contraofertas ---------------------------------------------------------------------------------------

func _test_counteroffers() -> void:
	print("-- contraofertas --")
	var gs = _gs()
	var b := _setup_supplier(49)
	var key := "npc:%d" % int(b["id"])
	var ref := ContractSim.reference_price(gs, key, "lena", 20, ContractSim.DIR_BUY)
	# Un precio un poco bajo: el proveedor responde con contraoferta.
	var o := _propose_and_wait(ContractSim.DIR_BUY, key, "lena", 20, ref * 0.9, {"period": 30, "installments": 3, "start_in": 5})
	check(str(o["status"]) == "contraoferta" and float(o.get("counter_price", 0.0)) > ref * 0.9, "el proveedor contraoferta (%s)" % Fmt.money2(float(o.get("counter_price", 0.0))))
	var msg := ContractSim.accept_counter(gs, int(o["id"]))
	var k := ContractSim.find(ContractSim.contracts(gs), int(o.get("contract_id", -1)))
	check(not k.is_empty() and absf(float(k["unit_price"]) - float(o["counter_price"])) < 0.001, "aceptar la contraoferta firma al precio propuesto (%s)" % msg)
	# Precio ridículo: rechaza sin contraoferta.
	var o2 := _propose_and_wait(ContractSim.DIR_BUY, key, "lena", 10, ref * 0.3, {"period": 30, "installments": 2})
	check(str(o2["status"]) == "rechazada", "un precio abusivo se rechaza: %s" % o2.get("reason", ""))
	# Otra contraoferta que el jugador rechaza.
	var o3 := _propose_and_wait(ContractSim.DIR_BUY, key, "lena", 10, ref * 0.88, {"period": 15, "installments": 2})
	check(str(o3["status"]) == "contraoferta", "segunda contraoferta")
	ContractSim.reject_counter(gs, int(o3["id"]))
	check(str(o3["status"]) == "rechazada" and not o3.has("contract_id"), "rechazar la contraoferta no firma nada")
	# Venta: el cliente contraoferta un precio algo alto.
	_player_farm()
	var owner := _rich_citizen("comercio")
	var shop := NpcBusinessSim.open_business(gs, owner, "tienda", 30.0, 20.0, 0.0)
	_finish_construction(shop)
	shop["reserve"] = 3000.0
	var skey := "npc:%d" % int(shop["id"])
	var sref := ContractSim.reference_price(gs, skey, "comida", 10)
	var max_p := sref * 1.1 * ContractSim.rep_price_factor(gs, skey) * ContractSim._duration_factor(3)
	var o4 := _propose_and_wait(ContractSim.DIR_SELL, skey, "comida", 10, max_p * 1.1, {"period": 30, "installments": 3})
	check(str(o4["status"]) == "contraoferta" and float(o4.get("counter_price", 0.0)) < max_p * 1.1, "el cliente contraoferta un precio más bajo (%s)" % o4.get("reason", ""))
	# Contraofertar una solicitud de la bandeja.
	var r := ContractSim.create_request(gs, skey, "comida", 10, sref, 2, 20)
	check(not r.is_empty(), "solicitud en la bandeja")
	check(ContractSim.counter_request(gs, int(r["id"]), sref * 1.05) == "", "contraofertas la solicitud")
	check(ContractSim.inbox(gs).is_empty(), "sale de la bandeja")
	var o5: Dictionary = ContractSim.sent(gs)[ContractSim.sent(gs).size() - 1]
	_market_days(6)
	check(str(o5["status"]) in ["aceptada", "contraoferta"], "el cliente responde a tu contraoferta (%s)" % o5["status"])


# --- Otros proveedores: pueblo con ruta e importación ------------------------------------------------------

func _test_town_and_import_purchase() -> void:
	print("-- compra a un pueblo (flete y demora) y a la importación --")
	var gs = _gs()
	GameState.new_game({"seed": 51, "difficulty": "normal"})
	gs.money = 50000.0
	var good := ""
	var tid := _connect_town(func(t):
		for g in t.get("produces", []):
			if ContractSim.is_tradeable(str(g)) and float(t["goods"][g].get("supply", 0.0)) >= 40.0:
				return true
		return false)
	check(tid != "", "hay un pueblo con ruta que produce algo")
	if tid == "":
		return
	var t := TradeSim.town(gs, tid)
	for g in t.get("produces", []):
		if ContractSim.is_tradeable(str(g)) and float(t["goods"][g].get("supply", 0.0)) >= 40.0:
			good = str(g)
			break
	var key := "town:%s" % tid
	check(ContractSim.supplier_keys(gs, good).has(key), "%s vende %s" % [t["name"], TradeSim.good_label(good)])
	var ref := ContractSim.reference_price(gs, key, good, 10, ContractSim.DIR_BUY)
	var o := _propose_and_wait(ContractSim.DIR_BUY, key, good, 10, ref * 1.1, {"period": 30, "installments": 2, "start_in": 10})
	check(str(o["status"]) == "aceptada", "el pueblo acepta (%s)" % o.get("reason", ""))
	var k := ContractSim.find(ContractSim.contracts(gs), int(o.get("contract_id", -1)))
	if k.is_empty():
		return
	var tq := TradeSim.transport_quote(gs, tid, 10)
	var cash0 := float(t["cash"])
	var m0: float = gs.money
	var w0 := WarehouseSim.stock_in(gs, 0, good)
	var due := int(k["next_due"])
	while gs.today() < due:
		_market_days(1)
	check(int(k["done"]) == 1 and WarehouseSim.stock_in(gs, 0, good) == w0, "despachado; todavía en camino")
	check(absf(m0 - gs.money - float(tq["cost"])) < 0.01, "pagas el flete al despachar (%s)" % Fmt.money(float(tq["cost"])))
	_market_days(int(tq["days"]))
	check(absf(WarehouseSim.stock_in(gs, 0, good) - w0 - 10.0) < 0.01, "llegó tras %d días de viaje" % int(tq["days"]))
	check(absf(float(t["cash"]) - cash0 - 10.0 * float(k["unit_price"])) < 0.01, "se pagó al recibir, a la caja del pueblo")
	# Importación externa: siempre tiene, más cara, el dinero sale del pueblo.
	var ik := ContractSim.IMPORT_KEY
	var iref := ContractSim.reference_price(gs, ik, "hierro", 5, ContractSim.DIR_BUY)
	check(iref > ContractSim.market_ref(gs, "hierro"), "la importación es más cara que el mercado")
	var o2 := _propose_and_wait(ContractSim.DIR_BUY, ik, "hierro", 5, iref, {"period": 30, "installments": 1, "start_in": 10})
	check(str(o2["status"]) == "aceptada", "la importación acepta")
	var k2 := ContractSim.find(ContractSim.contracts(gs), int(o2.get("contract_id", -1)))
	var h0 := WarehouseSim.stock(gs, "hierro")
	_market_days(12 + int(ContractSim.cfg().get("import_days", 7)))
	check(not k2.is_empty() and str(k2["status"]) == "cumplido" and absf(WarehouseSim.stock(gs, "hierro") - h0 - 5.0) < 0.01, "llegó el hierro importado")


# --- Ofertas de proveedores NPC (insumos) ---------------------------------------------------------------------

func _test_supply_offers_from_npc() -> void:
	print("-- los NPC te ofrecen insumos --")
	var gs = _gs()
	var b := _setup_supplier(53)
	var key := "npc:%d" % int(b["id"])
	var r := ContractSim.create_supply_offer(gs, key, "lena", 15, 0.5, 3, 15)
	check(not r.is_empty() and ContractSim.is_buy(r), "oferta de venta del proveedor en tu bandeja")
	check(ContractSim.create_supply_offer(gs, key, "trigo", 15, 0.5, 3, 15).is_empty(), "no ofrece lo que no produce")
	ContractSim.accept_request(gs, int(r["id"]))
	var k: Dictionary = ContractSim.active_contracts(gs)[0]
	check(ContractSim.is_buy(k) and int(k["period"]) == 15 and bool(k["auto"]), "aceptar firma una compra quincenal automática")
	# Generación mensual: un negocio tuyo que consume leña.
	var found := "carboneria"   # Comercio que vende leña: la necesita como mercadería.
	var pb := ConstructionSim.make_building(gs, found, 1, -40.0, 30.0, 0.0, "jugador")
	gs.add_building(pb)
	check(ContractSim.player_needs(gs).has("lena"), "%s necesita leña" % gs.building_label(pb))
	ContractSim.inbox(gs).clear()
	var got := false
	for i in range(30):
		ContractSim._generate_supply_offers(gs)
		if ContractSim.inbox(gs).any(func(x): return ContractSim.is_buy(x) and str(x["good"]) == "lena"):
			got = true
			break
	check(got, "con el tiempo un proveedor te ofrece leña")


func _test_cancel() -> void:
	print("-- cancelar con penalidad --")
	var gs = _gs()
	var b := _setup_supplier(55)
	var key := "npc:%d" % int(b["id"])
	var r := ContractSim.create_supply_offer(gs, key, "lena", 15, 0.5, 3, 15)
	ContractSim.accept_request(gs, int(r["id"]))
	var k: Dictionary = ContractSim.active_contracts(gs)[0]
	var before := _total()
	var m0: float = gs.money
	check(ContractSim.cancel(gs, int(k["id"])) == "", "cancelar")
	check(str(k["status"]) == "cancelado" and absf(m0 - gs.money - float(k["penalty"])) < 0.01, "pagaste la penalidad al cancelar")
	check(absf(_total() - before) < 0.01, "dinero conservado")
	check(ContractSim.cancel(gs, int(k["id"])) != "", "no se cancela dos veces")


# --- Migración y guardado ------------------------------------------------------------------------------

func _test_migration() -> void:
	print("-- migración de contratos viejos --")
	var gs = _gs()
	GameState.new_game({"seed": 57, "difficulty": "normal"})
	gs.money = 50000.0
	_player_farm()
	var d: Dictionary = gs.to_dict()
	var today: int = gs.today()
	# Formato anterior: sin dirección, cuotas mensuales.
	d["market"]["contracts"] = [{"id": 900, "client": "gov", "client_name": "Gobierno del pueblo", "good": "comida",
		"qty": 10.0, "unit_price": 0.5, "installments": 3, "done": 0, "failed": 0, "next_due": today + 10, "period": 30,
		"penalty": 1.0, "auto": true, "status": "activo", "source": "solicitud", "signed_day": today - 20,
		"paid": 0.0, "owed": 0.0, "plan_id": -1, "delivered": 0.0}]
	d["market"]["inbox"] = [{"id": 901, "client": "gov", "client_name": "Gobierno del pueblo", "good": "comida", "qty": 5.0,
		"unit_price": 0.5, "installments": 2, "deadline_days": 30, "penalty": 0.5, "expires_day": today + 10, "day": today, "plan_id": -1, "total": 5.0}]
	d["market"]["sent"] = [{"id": 902, "client": "gov", "client_name": "Gobierno del pueblo", "good": "comida", "qty": 5.0,
		"unit_price": 0.1, "day": today, "reply_day": today - 1, "status": "rechazada", "reason": "x"}]
	d["market"].erase("reliability")
	var txt := JSON.stringify(d)
	gs.load_dict(JSON.parse_string(txt))
	var k: Dictionary = ContractSim.contracts(gs)[0]
	check(str(k["dir"]) == ContractSim.DIR_SELL and int(k["period"]) == 30, "contrato viejo: venta con frecuencia 30")
	check(int(k["start_day"]) == today - 20 and int(k["end_day"]) == today + 70, "fecha de inicio y fin calculadas")
	check(absf(float(k["cp_penalty"]) - 1.0) < 0.001 and int(k["cp_failed"]) == 0 and int(k["wid"]) == 0, "penalidad de la contraparte y almacén por defecto")
	check(str(ContractSim.inbox(gs)[0]["dir"]) == ContractSim.DIR_SELL and int(ContractSim.inbox(gs)[0]["period"]) == 30, "solicitud vieja migrada")
	check(str(ContractSim.sent(gs)[0]["dir"]) == ContractSim.DIR_SELL, "oferta vieja migrada")
	check(gs.market.has("reliability"), "fiabilidad creada")
	WarehouseSim.add(gs, "comida", 50.0)
	_market_days(12)
	check(int(k["done"]) == 1 and int(k["next_due"]) == today + 40, "el contrato migrado sigue entregando cada 30 días")


func _test_save_load() -> void:
	print("-- guardar y cargar --")
	var gs = _gs()
	var b := _setup_supplier(59)
	var key := "npc:%d" % int(b["id"])
	var ref := ContractSim.reference_price(gs, key, "lena", 20, ContractSim.DIR_BUY)
	_propose_and_wait(ContractSim.DIR_BUY, key, "lena", 20, ref * 1.05, {"period": 15, "installments": 6, "start_in": 10, "wid": 0})
	ContractSim.propose(gs, ContractSim.DIR_BUY, ContractSim.IMPORT_KEY, "hierro", 5, 0.01, {"period": 30, "installments": 2})
	TimeManager.advance_days(10)
	var snap := JSON.stringify(gs.market)
	check(SaveManager.save_game("test_contratos"), "guardar")
	TimeManager.advance_days(20)
	check(SaveManager.load_game("test_contratos"), "cargar")
	check(JSON.stringify(gs.market) == snap, "contratos restaurados igual")
	var k: Dictionary = ContractSim.contracts(gs).filter(func(x): return ContractSim.is_buy(x))[0]
	check(int(k["period"]) == 15 and int(k["installments"]) == 6, "compra recurrente restaurada")
	TimeManager.advance_days(30)
	var a := JSON.stringify(gs.market)
	SaveManager.load_game("test_contratos")
	TimeManager.advance_days(30)
	check(JSON.stringify(gs.market) == a, "determinista tras cargar")
	SaveManager.delete_save("test_contratos")


# --- Interfaz --------------------------------------------------------------------------------------------

func _test_ui() -> void:
	print("-- interfaz --")
	var gs = _gs()
	var b := _setup_supplier(61)
	_player_farm()
	var key := "npc:%d" % int(b["id"])
	ContractSim.create_supply_offer(gs, key, "lena", 15, 0.5, 3, 15)
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	var hud: Hud = world.hud
	hud._show_dock("contracts")
	await get_tree().process_frame
	var p: ContractsPanel = hud.contracts_panel
	check(p.visible and p.tab == "bandeja" and p.body.get_child_count() > 3, "panel abre en la Bandeja")
	check(p.tab_bar.get_child_count() == 4, "4 pestañas")
	p.set_tab("proponer")
	await get_tree().process_frame
	check(p.total_label != null and p.total_label.text.contains("Estimado"), "Proponer muestra el estimado")
	p.sel_dir = ContractSim.DIR_BUY
	p.sel_good = "lena"
	p.sel_client = ""
	p.freq_idx = 2
	p.installments = 4
	p.refresh()
	await get_tree().process_frame
	check(p._clients.has(key) and p._clients.has(ContractSim.IMPORT_KEY), "proveedores de leña en el formulario")
	check(p._period() == 15 and p._inst() == 4, "frecuencia quincenal × 4")
	var n0 := ContractSim.sent(gs).size()
	p._send()
	check(ContractSim.sent(gs).size() == n0 + 1 and ContractSim.is_buy(ContractSim.sent(gs)[n0]), "propuesta de compra enviada desde el panel")
	var r: Dictionary = ContractSim.inbox(gs)[0]
	p._result("", ContractSim.accept_request(gs, int(r["id"])))
	p.set_tab("activos")
	await get_tree().process_frame
	check(p.body.get_child_count() >= 4, "Activos lista el contrato")
	p.set_tab("historial")
	await get_tree().process_frame
	check(p.body.get_child_count() >= 3, "Historial")
	world.queue_free()
	await get_tree().process_frame
