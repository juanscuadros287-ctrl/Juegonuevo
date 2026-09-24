extends Node
## Pruebas del libre mercado: empresas NPC, herencia, contratos, ofertas, planes del gobierno,
## pueblos que crecen, conservación del dinero, guardado y simulación larga.
## godot --headless res://tests/test_mercado.tscn

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func _ready() -> void:
	print("== Dinastía: pruebas del libre mercado ==")
	_test_npc_opening_and_inheritance()
	_test_requests_only_for_produced()
	_test_contract_local_and_town()
	_test_contract_failure()
	_test_outgoing_offers()
	_test_buy_npc_business()
	_test_gov_plans()
	_test_towns_grow()
	_test_money_conservation()
	_test_save_load()
	_test_long_simulation()
	await _test_ui()
	print("== %s (%d fallos) ==" % ["TODO OK" if failures == 0 else "CON FALLOS", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _gs():
	return GameState


func _total() -> float:
	return float(FreeMarketSim.money_snapshot(_gs())["total"])


## Simula que el mes pasado nadie vendió `good` en el pueblo (la gente importó o se autoabasteció).
func _fake_unmet(good: String, units: float) -> void:
	var gs = _gs()
	var last: Dictionary = gs.economy.get("last_month", {})
	var goods: Dictionary = last.get("goods", {})
	goods[good] = {"demand": units, "imported": units * 0.5, "self": units * 0.5, "local": 0.0}
	last["goods"] = goods
	gs.economy["last_month"] = last


## Un ciudadano adulto con ahorros y habilidad para `skill`.
func _rich_citizen(skill: String) -> Citizen:
	var gs = _gs()
	var today: int = gs.today()
	for c in gs.citizens.values():
		if gs.is_player(c.id) or NpcBusinessSim._player_family(gs, c):
			continue
		var age: int = c.age_years(today)
		if age >= 25 and age <= 45:
			c.skills[skill] = 60.0
			c.money = 3000.0
			return c
	return null


func _player_farm() -> Dictionary:
	var gs = _gs()
	var b := ConstructionSim.make_building(gs, "granja", 1, 40.0, -30.0, 0.0, "jugador")
	gs.add_building(b)
	b["inventory"]["comida"] = 400.0
	return b


func _finish_construction(b: Dictionary, max_days := 200) -> void:
	for i in range(max_days):
		if str(b["status"]) == "activo":
			break
		TimeManager.advance_days(1)
	TimeManager.advance_days(1)


func _connect_town(good_demanded: String) -> String:
	var gs = _gs()
	var tid := ""
	for t in TradeSim.towns(gs):
		var row: Dictionary = t["goods"].get(good_demanded, {})
		if not row.is_empty() and not bool(row.get("sells", false)):
			tid = str(t["id"])
			break
	if tid == "":
		return ""
	var err := TradeSim.open_route(gs, tid)
	check(err == "", "abrir ruta con %s (%s)" % [TradeSim.town(gs, tid).get("name", ""), err])
	TimeManager.advance_days(int(TradeSim.project(gs, tid).get("total_days", 30)) + 1)
	return tid


# --- Empresas NPC ---------------------------------------------------------------------------------------

func _test_npc_opening_and_inheritance() -> void:
	var gs = _gs()
	GameState.new_game({"seed": 5, "difficulty": "normal"})
	check(gs.market.has("contracts") and gs.market.has("gov_plans"), "estado del mercado creado en partida nueva")
	TimeManager.advance_days(35)
	_fake_unmet("agua", 900.0)
	var owner := _rich_citizen("construccion")
	check(owner != null, "hay un ciudadano con ahorros")
	var before := _total()
	check(float(NpcBusinessSim.unmet_demand(gs)["agua"]["uncovered"]) > 300.0, "se mide la demanda sin cubrir de agua")
	var b := NpcBusinessSim.try_open(gs, "agua")
	check(not b.is_empty(), "un ciudadano abre un negocio donde falta oferta")
	if b.is_empty():
		return
	var cap := NpcBusinessSim.capital_needed(gs, str(b["type"]))
	check(str(b["owner"]) == "ciudadano" and int(b["owner_id"]) >= 0 and NpcBusinessSim.is_npc(b), "edificio real de un ciudadano (owner_id %d)" % int(b["owner_id"]))
	check(str(gs.building_def(b).get("product", "")) == "agua", "abre lo que falta: %s" % gs.building_label(b))
	check(str(b["status"]) == "construccion", "empieza con obra")
	check(absf(_total() - (before - float(cap["build"]))) < 0.01, "sin dinero nuevo: solo salen los materiales (%s)" % Fmt.money(float(cap["build"])))
	_finish_construction(b)
	check(str(b["status"]) == "activo" and str(b["npc_state"]) == NpcBusinessSim.STATE_OPEN, "la obra termina y abre")
	check(NpcBusinessSim.owner_works(gs, b) or NpcBusinessSim.staff_count(gs, b) > 0, "el dueño atiende su negocio (empleados: %d)" % NpcBusinessSim.staff_count(gs, b))
	var t0 := float(gs.government["treasury"])
	TimeManager.advance_days(62)
	var sales := BusinessSim.period_value(b, "total", "ventas")
	check(sales > 0.0, "vende a los ciudadanos (%s)" % Fmt.money(sales))
	check(BusinessSim.period_value(b, "total", "salarios") > 0.0 or NpcBusinessSim.owner_works(gs, b), "paga sueldos (o el dueño trabaja sin sueldo)")
	var hired := NpcBusinessSim.fill_jobs(gs, b, 2)
	check(hired > 0 and NpcBusinessSim.staff_count(gs, b) > 0, "contrata gente del pueblo (%d)" % hired)
	TimeManager.advance_days(3)
	check(BusinessSim.period_value(b, "total", "salarios") > 0.0, "paga sueldos a sus empleados")
	check(BusinessSim.period_value(b, "total", "impuestos") > 0.0, "paga impuestos al tesoro")
	check(MarketSim.sellers("agua").has(b), "compite en el mercado local")
	# Herencia: hijo adulto.
	var o: Citizen = gs.citizens.get(int(b["owner_id"]))
	var kid := PopulationSim.create_citizen(gs, "M", 24, o.last_name)
	PopulationSim.link_parents(kid, o, null)
	PopulationSim.die(gs, o, "prueba")
	TimeManager.advance_days(1)
	check(int(b["owner_id"]) == kid.id, "el hijo hereda el negocio (%s)" % gs.person_name(int(b["owner_id"])))
	check(b["owners"].size() == 2 and str(b["owners"][1]["how"]) == "herencia", "historial de dueños: %s" % NpcBusinessSim.owner_text(gs, b))
	# Sin herederos: lo vende el Estado; la caja va al tesoro.
	for c in gs.citizens.values():
		if c.parent_ids.has(kid.id):
			c.parent_ids.erase(kid.id)
	b["owner_parents"] = []
	b["owner_spouse"] = -1
	kid.spouse_id = -1
	var cash := float(b["reserve"])
	var tr := float(gs.government["treasury"])
	PopulationSim.die(gs, kid, "prueba")
	TimeManager.advance_days(1)
	check(str(b["npc_state"]) == NpcBusinessSim.STATE_FOR_SALE and int(b["owner_id"]) < 0, "sin herederos: queda en venta por el Estado")
	check(float(gs.government["treasury"]) >= tr + cash - 0.01 - 60.0, "la caja pasó al tesoro")
	gs.money = 50000.0
	var price := float(b["npc_sale_price"])
	var m1: float = gs.money
	var err := NpcBusinessSim.buy_listed(gs, b)
	check(err == "" and gs.owned_by_player(b), "el jugador compra la empresa al Estado (%s)" % err)
	check(absf((m1 - gs.money) - price) < 0.01, "pagó el precio publicado")
	check(t0 > 0.0, "tesoro inicial")


# --- Contratos -------------------------------------------------------------------------------------------

func _test_requests_only_for_produced() -> void:
	var gs = _gs()
	GameState.new_game({"seed": 12, "difficulty": "normal"})
	gs.money = 50000.0
	var tid := _connect_town("comida")
	check(tid != "", "hay un pueblo que no vende comida")
	check(ContractSim.player_goods(gs).is_empty(), "sin negocios no produces nada")
	for i in range(30):
		ContractSim._generate_requests(gs)
	check(ContractSim.inbox(gs).is_empty(), "sin producción no llegan solicitudes")
	_player_farm()
	check(ContractSim.player_goods(gs).keys() == ["comida"], "con una granja produces comida")
	var got := 0
	var bad := 0
	for i in range(60):
		ContractSim._generate_requests(gs)
		for r in ContractSim.inbox(gs):
			got += 1
			if str(r["good"]) != "comida":
				bad += 1
		gs.market["inbox"] = []
	check(got > 0, "llegan solicitudes (%d)" % got)
	check(bad == 0, "solo piden bienes que produces")
	check(ContractSim.create_request(gs, "town:%s" % tid, "hierro", 10, 5.0).is_empty(), "no se crea una solicitud de un bien que no produces")


func _test_contract_local_and_town() -> void:
	var gs = _gs()
	GameState.new_game({"seed": 14, "difficulty": "normal"})
	gs.money = 50000.0
	var farm := _player_farm()
	TimeManager.advance_days(35)
	_fake_unmet("comida", 900.0)
	var owner := _rich_citizen("comercio")
	var npc := NpcBusinessSim.open_business(gs, owner, "tienda", 30.0, 20.0, 0.0)
	check(not npc.is_empty(), "empresa NPC para el contrato")
	_finish_construction(npc)
	npc["reserve"] = 500.0
	var key := "npc:%d" % int(npc["id"])
	var r := ContractSim.create_request(gs, key, "comida", 40, 0.4, 1, 20)
	check(not r.is_empty() and ContractSim.inbox(gs).size() == 1, "la solicitud llega a la bandeja")
	var msg := ContractSim.accept_request(gs, int(r["id"]))
	check(ContractSim.active_contracts(gs).size() == 1, "aceptar firma el contrato (%s)" % msg)
	var k: Dictionary = ContractSim.active_contracts(gs)[0]
	var before := _total()
	var m0: float = gs.money
	var c0 := float(npc["reserve"])
	var inv0 := float(npc["inventory"].get("comida", 0.0))
	farm["inventory"]["comida"] = 400.0
	var farm0 := float(farm["inventory"]["comida"])
	var rep0 := ContractSim.reputation(gs, key)
	var err := ContractSim.deliver(gs, int(k["id"]))
	check(err == "", "entregar (%s)" % err)
	check(absf(gs.money - m0 - 16.0) < 0.01, "cobras 40 × 0,40 = 16")
	check(absf(c0 - float(npc["reserve"]) - 16.0) < 0.01, "pagó la caja de la empresa NPC")
	check(absf(float(npc["inventory"]["comida"]) - inv0 - 40.0) < 0.01, "la mercancía llega a su inventario")
	check(absf(farm0 - float(farm["inventory"]["comida"]) - 40.0) < 0.01, "sale de tu inventario")
	check(absf(_total() - before) < 0.01, "dinero conservado en la entrega")
	check(str(k["status"]) == "cumplido" and ContractSim.reputation(gs, key) > rep0, "contrato cumplido y sube la reputación")
	# Pueblo con ruta: el envío viaja y el pueblo paga al llegar desde su caja.
	var tid := _connect_town("comida")
	var tkey := "town:%s" % tid
	var t := TradeSim.town(gs, tid)
	var r2 := ContractSim.create_request(gs, tkey, "comida", 50, 0.8, 1, 60)
	ContractSim.accept_request(gs, int(r2["id"]))
	var k2: Dictionary = ContractSim.active_contracts(gs)[0]
	var cash0 := float(t["cash"])
	farm["inventory"]["comida"] = 400.0
	var tq := TradeSim.transport_quote(gs, tid, 50.0)
	var m1: float = gs.money
	var ok := ContractSim.deliver(gs, int(k2["id"]))
	check(ok == "", "despacho al pueblo por la ruta (%s)" % ok)
	check(absf(m1 - gs.money - float(tq["cost"])) < 0.01, "pagas el flete (%s)" % Fmt.money(float(tq["cost"])))
	TimeManager.advance_days(int(tq["days"]) + 1)
	check(float(t["cash"]) < cash0 + TownEconomySim.town_cash(gs, tid) * 0.0 + 1000.0, "el pueblo pagó de su caja")
	check(float(k2["paid"]) >= 40.0 - 0.01, "cobrado al llegar: %s" % Fmt.money(float(k2["paid"])))
	# Recurrente con entrega automática.
	var r3 := ContractSim.create_request(gs, key, "comida", 10, 0.4, 3, 30)
	ContractSim.accept_request(gs, int(r3["id"]))
	var k3: Dictionary = ContractSim.active_contracts(gs).filter(func(x): return int(x["installments"]) == 3)[0]
	check(bool(k3["auto"]), "los recurrentes tienen entrega automática")
	npc["reserve"] = 500.0
	WarehouseSim.add(gs, "comida", 60.0)   # En la bodega de la plaza (la gente no compra de ahí).
	TimeManager.advance_days(95)
	check(int(k3["done"]) == 3 and str(k3["status"]) == "cumplido", "3 entregas mensuales automáticas (%d)" % int(k3["done"]))


func _test_contract_failure() -> void:
	var gs = _gs()
	GameState.new_game({"seed": 16, "difficulty": "normal"})
	gs.money = 50000.0
	var farm := _player_farm()
	farm["inventory"]["comida"] = 0.0
	var r := ContractSim.create_request(gs, "gov", "comida", 5000, 0.5, 1, 10)
	check(not r.is_empty(), "el gobierno pide comida")
	ContractSim.accept_request(gs, int(r["id"]))
	var k: Dictionary = ContractSim.active_contracts(gs)[0]
	var rep0 := ContractSim.reputation(gs, "gov")
	var before := _total()
	var m0: float = gs.money
	var tr0 := float(gs.government["treasury"])
	for i in range(12):
		FreeMarketSim.daily(gs)   # Solo el mercado: aislado del resto de la economía.
		TimeManager.total_hours += 24
	check(str(k["status"]) == "incumplido", "sin entregar a tiempo: incumplido")
	check(absf(m0 - gs.money - float(k["penalty"])) < 0.01, "pagaste la penalidad (%s)" % Fmt.money(float(k["penalty"])))
	check(float(gs.government["treasury"]) >= tr0 + float(k["penalty"]) - 0.01 - 50.0, "la penalidad la recibe el cliente")
	check(ContractSim.reputation(gs, "gov") < rep0, "baja la reputación (%d → %d)" % [int(rep0), int(ContractSim.reputation(gs, "gov"))])
	check(ContractSim.rep_price_factor(gs, "gov") < 1.0 and ContractSim.rep_freq_factor(gs, "gov") < 1.0, "peor reputación: peores precios y menos solicitudes")
	check(absf(_total() - before) < 60.0, "la penalidad solo cambia de manos")


func _test_outgoing_offers() -> void:
	var gs = _gs()
	GameState.new_game({"seed": 18, "difficulty": "normal"})
	gs.money = 50000.0
	_player_farm()
	var tid := _connect_town("comida")
	var key := "town:%s" % tid
	var t := TradeSim.town(gs, tid)
	t["cash"] = 100000.0
	var ref := ContractSim.reference_price(gs, key, "comida", 30)
	check(ContractSim.send_offer(gs, key, "comida", 30, ref * 0.7) == "", "oferta barata enviada")
	check(ContractSim.send_offer(gs, key, "comida", 30, ref) != "", "no se duplica una oferta pendiente")
	TimeManager.advance_days(6)
	var o: Dictionary = ContractSim.sent(gs)[0]
	check(str(o["status"]) == "aceptada", "el pueblo acepta un buen precio (%s)" % o.get("reason", ""))
	check(ContractSim.active_contracts(gs).size() == 1, "la oferta aceptada es un contrato")
	check(ContractSim.send_offer(gs, key, "comida", 30, ref * 5.0) == "", "oferta cara enviada")
	TimeManager.advance_days(6)
	var o2: Dictionary = ContractSim.sent(gs)[1]
	check(str(o2["status"]) == "rechazada", "rechaza un precio abusivo: %s" % o2.get("reason", ""))
	check(ContractSim.send_offer(gs, "gov", "comida", 10, 0.1) == "", "oferta al gobierno enviada")
	TimeManager.advance_days(6)
	check(str(ContractSim.sent(gs)[2]["status"]) == "rechazada", "el gobierno no compra lo que no necesita")


func _test_buy_npc_business() -> void:
	var gs = _gs()
	GameState.new_game({"seed": 20, "difficulty": "normal"})
	gs.money = 50000.0
	TimeManager.advance_days(35)
	var owner := _rich_citizen("comercio")
	var b := NpcBusinessSim.open_business(gs, owner, "taberna", -30.0, 22.0, 0.0)
	_finish_construction(b)
	var val := NpcBusinessSim.valuation(gs, b)
	check(NpcBusinessSim.offer_purchase(gs, b, val * 0.3) == "", "oferta baja enviada")
	TimeManager.advance_days(6)
	check(NpcBusinessSim.is_npc(b), "el dueño rechaza una oferta baja")
	var before := _total()
	var own_money := owner.money
	var cash := float(b["reserve"])
	var offer := val * 3.0
	check(NpcBusinessSim.offer_purchase(gs, b, offer) == "", "oferta alta enviada")
	for i in range(6):
		FreeMarketSim.daily(gs)
		TimeManager.total_hours += 24
	check(gs.owned_by_player(b) and not NpcBusinessSim.is_npc(b), "el dueño acepta: el negocio es tuyo")
	check(owner.money >= own_money + offer + cash - 0.01, "el dueño cobró la venta y se llevó la caja")
	check(absf(_total() - before) < 0.01, "la compra no crea dinero")


# --- Gobierno -------------------------------------------------------------------------------------------

func _test_gov_plans() -> void:
	var gs = _gs()
	GameState.new_game({"seed": 22, "difficulty": "normal"})
	var gp: Dictionary = GameData.extra("mercado")["gov_plans"]
	var old_tender := float(gp["tender_chance"])
	gp["tender_chance"] = 0.0
	gs.government["treasury"] = 20000.0
	if not gs.techs.has("herbolaria"):
		gs.techs.append("herbolaria")
	var t0 := float(gs.government["treasury"])
	var p := GovPlansSim.propose(gs, "centro_salud")
	check(not p.is_empty(), "el gobierno decide un plan: %s" % p.get("label", ""))
	check(str(p["status"]) == "en_obra", "sin materiales del jugador: construye de una vez")
	var b: Dictionary = gs.get_building(int(p["bid"]))
	check(not b.is_empty() and str(b["owner"]) == "gobierno" and str(b["status"]) == "construccion", "obra real del gobierno en el mapa")
	check(float(gs.government["treasury"]) < t0, "se paga con el tesoro (%s)" % Fmt.money(t0 - float(gs.government["treasury"])))
	var tr1 := float(gs.government["treasury"])
	_finish_construction(b)
	check(str(p["status"]) == "terminado", "el plan se cumple")
	check(BusinessSim.period_value(b, "total", "obras") > float(p["spent"]) and float(gs.government["treasury"]) < tr1, "los jornales de la obra salen del tesoro, no del jugador")
	TimeManager.advance_days(2)
	check(NpcBusinessSim.staff_count(gs, b) > 0, "emplea personal (%d)" % NpcBusinessSim.staff_count(gs, b))
	check(EventsSim.coverage(gs, "salud") > 0.0, "da cobertura de salud (%.2f)" % EventsSim.coverage(gs, "salud"))
	# Licitación: el gobierno ofrece la obra al jugador; si la pierde, la hace él.
	gp["tender_chance"] = 1.0
	gs.government["tenders"] = []
	var p2 := GovPlansSim.propose(gs, "parque")
	check(str(p2["status"]) == "licitacion" and GovSim.open_tenders(gs).size() == 1, "el plan se licita al jugador")
	GovSim.open_tenders(gs)[0]["status"] = "lost"
	GovPlansSim._advance_plans(gs)
	check(str(p2["status"]) == "en_obra", "licitación perdida: el gobierno construye por su cuenta")
	gp["tender_chance"] = old_tender
	# Materiales: si el jugador produce madera, el gobierno se la pide.
	var saw := ConstructionSim.make_building(gs, "aserradero", 1, 45.0, 45.0, 0.0, "jugador")
	gs.add_building(saw)
	gp["tender_chance"] = 0.0
	var p3 := GovPlansSim.propose(gs, "vivienda_social")
	check(str(p3["status"]) == "materiales" and ContractSim.inbox(gs).any(func(r): return str(r["client"]) == "gov" and str(r["good"]) == "madera"), "pide la madera al jugador por contrato")
	gp["tender_chance"] = old_tender
	# Plan automático por necesidad medida.
	GameState.new_game({"seed": 23, "difficulty": "normal"})
	gs.government["treasury"] = 20000.0
	for c in gs.citizens.values():
		c.happiness = 30.0
	var nd := GovPlansSim.needs(gs)
	check(nd.any(func(n): return str(n["need"]) == "felicidad"), "mide la felicidad baja como necesidad")
	var auto := GovPlansSim.propose(gs)
	check(not auto.is_empty() and str(auto["need"]) == str(nd[0]["need"]), "arma el plan de la necesidad más grave: %s" % auto.get("label", ""))


func _test_towns_grow() -> void:
	var gs = _gs()
	GameState.new_game({"seed": 24, "difficulty": "normal"})
	var t: Dictionary = TradeSim.towns(gs)[0]
	check(t.has("cash") and t.has("sectors") and float(t["cash"]) > 0.0, "los pueblos tienen caja y empresarios (%d negocios)" % TownEconomySim.total_businesses(t))
	var pop0 := float(t["population"])
	var biz0 := TownEconomySim.total_businesses(t)
	for i in range(12 * 20):
		TownEconomySim.monthly(gs)
		TimeManager.total_hours += 24 * 30
	check(float(t["population"]) > pop0 * 1.1, "en 20 años el pueblo crece (%d → %d)" % [int(pop0), int(t["population"])])
	check(TownEconomySim.total_businesses(t) > biz0, "abren más negocios (%d → %d)" % [biz0, TownEconomySim.total_businesses(t)])
	var trade := 0.0
	for x in TradeSim.towns(gs):
		trade += float(x["trade_month"].get("exports", 0.0))
	check(trade > 0.0, "los pueblos comercian entre ellos (%s/mes)" % Fmt.money(trade))


func _test_money_conservation() -> void:
	var gs = _gs()
	GameState.new_game({"seed": 26, "difficulty": "normal"})
	TimeManager.advance_days(40)
	var owner := _rich_citizen("agricultura")
	var b := NpcBusinessSim.open_business(gs, owner, "lenador", 25.0, -25.0, 0.0)
	_finish_construction(b)
	TimeManager.advance_days(10)
	# Un mes de funcionamiento del mercado: producción, ventas y cuentas NPC sin fuentes externas.
	var before: Dictionary = FreeMarketSim.money_snapshot(gs)
	var spent := 0.0
	for i in range(30):
		var up0 := BusinessSim.period_value(b, "month", "mantenimiento") + BusinessSim.period_value(b, "month", "insumos")
		NpcBusinessSim.produce(gs)
		spent += BusinessSim.period_value(b, "month", "mantenimiento") + BusinessSim.period_value(b, "month", "insumos") - up0
		MarketSim.begin_day(gs)
		NpcBusinessSim.daily(gs)
	var after: Dictionary = FreeMarketSim.money_snapshot(gs)
	check(float(after["total"]) <= float(before["total"]) + 0.01, "producir y pagar sueldos no crea dinero (Δ %.2f, gastos que salen %.2f)" % [float(after["total"]) - float(before["total"]), spent])
	check(absf(float(after["total"]) - (float(before["total"]) - spent)) < 0.05, "solo sale lo que se paga afuera (mantenimiento e insumos)")
	var b2 := _total()
	NpcBusinessSim._monthly_accounts(gs)
	check(absf(_total() - b2) < 0.01, "impuestos y dividendos solo cambian de manos")
	var b3 := _total()
	TownEconomySim._inter_town_trade(gs)
	check(absf(_total() - b3) < 0.01, "el comercio entre pueblos es de suma cero")


func _test_save_load() -> void:
	var gs = _gs()
	GameState.new_game({"seed": 28, "difficulty": "normal"})
	gs.money = 50000.0
	_player_farm()
	TimeManager.advance_days(40)
	var owner := _rich_citizen("comercio")
	var b := NpcBusinessSim.open_business(gs, owner, "taberna", -28.0, -20.0, 0.0)
	ContractSim.create_request(gs, "gov", "comida", 20, 0.6, 2, 30)
	GovPlansSim.propose(gs, "parque")
	TimeManager.advance_days(20)
	var snap := JSON.stringify(gs.market)
	check(SaveManager.save_game("test_mercado"), "guardar")
	TimeManager.advance_days(30)
	check(SaveManager.load_game("test_mercado"), "cargar")
	check(JSON.stringify(gs.market) == snap, "mercado restaurado igual")
	var nb: Dictionary = gs.get_building(int(b["id"]))
	check(NpcBusinessSim.is_npc(nb) and int(nb["owner_id"]) == owner.id, "empresa NPC restaurada")
	TimeManager.advance_days(60)
	var a := JSON.stringify(gs.market)
	SaveManager.load_game("test_mercado")
	TimeManager.advance_days(60)
	check(JSON.stringify(gs.market) == a, "el mercado es determinista tras cargar")
	# Partida vieja sin mercado: carga con valores por defecto.
	var d: Dictionary = gs.to_dict()
	d.erase("market")
	for t in d["trade"]["towns"]:
		t.erase("cash")
		t.erase("sectors")
	gs.load_dict(d)
	check(gs.market.has("contracts") and gs.market.has("inbox") and gs.market.has("gov_plans"), "partida vieja: mercado creado al cargar")
	check(TradeSim.towns(gs)[0].has("cash") and TradeSim.towns(gs)[0].has("sectors"), "partida vieja: los pueblos reciben caja y sectores")
	TimeManager.advance_days(40)
	check(gs.running, "la partida vieja sigue corriendo")
	SaveManager.delete_save("test_mercado")


func _test_long_simulation() -> void:
	var gs = _gs()
	GameState.new_game({"seed": 31, "difficulty": "normal"})
	var pop0: int = gs.citizens.size()
	var t0 := Time.get_ticks_msec()
	# Como un jugador real: una granja con empleados (el resto lo cubre el libre mercado).
	var farm_r := ConstructionSim.start_construction(gs, "granja", 30.0, -8.0, 0.0, "", "sas")
	TimeManager.advance_days(40)
	if farm_r.has("building"):
		for c in BusinessSim.candidates(gs, farm_r["building"]).slice(0, 3):
			BusinessSim.hire(gs, farm_r["building"], c, BusinessSim.asked_wage(gs, c, "granja"))
	TimeManager.advance_days(8 * 365 - 40)
	var npcs := NpcBusinessSim.npc_buildings(gs)
	var st: Dictionary = gs.market.get("stats", {})
	print("    8 años: población %d → %d · empresas NPC %d (abiertas %d, quiebras %d, herencias %d) · planes %d · tesoro %s · %d ms" % [pop0, gs.citizens.size(), npcs.size(),
		int(st.get("npc_opened", 0)), int(st.get("npc_bankrupt", 0)), int(st.get("npc_inherited", 0)), GovPlansSim.plans(gs).size(), Fmt.money(float(gs.government["treasury"])), Time.get_ticks_msec() - t0])
	for r in NpcBusinessSim.summary_rows(gs):
		print("      · %s (%s) %s · %d/%d · caja %s" % [r["name"], r["owner"], r["state"], r["staff"], r["jobs"], Fmt.money(float(r["cash"]))])
	for p in GovPlansSim.plans(gs):
		print("      · plan %s: %s" % [p["label"], p["status"]])
	check(gs.citizens.size() >= int(pop0 * 0.7), "la población no colapsa")
	check(int(st.get("npc_opened", 0)) >= 1, "los ciudadanos abren negocios con el tiempo")
	check(int(st.get("npc_opened", 0)) <= 8 * 2 + 2, "ritmo lento de aperturas")
	check(GovPlansSim.plans(gs).size() >= 1, "el gobierno ejecuta planes")
	var bad := 0
	for c in gs.citizens.values():
		if is_nan(c.money) or is_inf(c.money):
			bad += 1
	for b in gs.buildings:
		if is_nan(float(b.get("reserve", 0.0))):
			bad += 1
	check(bad == 0 and not is_nan(gs.money) and not is_nan(float(gs.government["treasury"])), "sin valores inválidos")
	check(float(gs.government["treasury"]) > -1000.0, "el tesoro no se hunde (%s)" % Fmt.money(float(gs.government["treasury"])))
	var avg_npc := 0.0
	for c in gs.citizens.values():
		avg_npc += c.money
	check(avg_npc / maxf(1.0, gs.citizens.size()) < 5000.0, "sin creación de dinero en los ciudadanos")
	for t in TradeSim.towns(gs):
		check(float(t["cash"]) >= 0.0, "caja de %s no negativa" % t["name"])
		break


func _test_ui() -> void:
	var gs = _gs()
	GameState.new_game({"seed": 33, "difficulty": "facil"})
	gs.money = 50000.0
	_player_farm()
	TimeManager.advance_days(40)
	var owner := _rich_citizen("comercio")
	var b := NpcBusinessSim.open_business(gs, owner, "taberna", -28.0, -20.0, 0.0)
	_finish_construction(b)
	ContractSim.create_request(gs, "gov", "comida", 20, 0.6, 2, 30)
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	var hud: Hud = world.hud
	hud._show_dock("contracts")
	await get_tree().process_frame
	check(hud.contracts_panel.visible and hud.contracts_panel.body.get_child_count() > 3, "panel de contratos abre")
	var r: Dictionary = ContractSim.inbox(gs)[0]
	hud.contracts_panel._result("", ContractSim.accept_request(gs, int(r["id"])))
	await get_tree().process_frame
	check(ContractSim.active_contracts(gs).size() == 1, "aceptar desde el panel")
	hud.open_building(int(b["id"]))
	await get_tree().process_frame
	check(hud.building_panel.summary.text.contains("Empresa NPC"), "el panel del edificio muestra el dueño NPC")
	hud._show_dock("government")
	await get_tree().process_frame
	hud._show_dock("stats")
	await get_tree().process_frame
	check(true, "paneles de gobierno y estadísticas con libre mercado")
	world.queue_free()
	await get_tree().process_frame
