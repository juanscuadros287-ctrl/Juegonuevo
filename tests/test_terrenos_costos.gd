extends Node
## Pruebas de docs/TERRENOS_COSTOS.md: cartera de terrenos (plusvalía, predial, venta al Estado y a NPC, ofertas,
## contraoferta, arriendo, recompra negociada), costeo por fábrica (total = desglose, calculadora ±20 % tras
## 3 meses), división de transporte (interna repartida y empresa aparte sin duplicar en el consolidado),
## historial de precios, inmobiliaria (sección H), dinero conservado y guardar/cargar.
## godot --headless res://tests/test_terrenos_costos.tscn

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func _ready() -> void:
	print("== Dinastía: terrenos, costos por fábrica, transporte en finanzas, precios e inmobiliaria ==")
	_test_lands()
	_test_negotiation()
	_test_costing()
	_test_transport()
	_test_prices()
	_test_agency()
	_test_save_load()
	print("== %s (%d fallos) ==" % ["TODO OK" if failures == 0 else "CON FALLOS", failures])
	get_tree().quit(1 if failures > 0 else 0)


# --- Utilidades -------------------------------------------------------------------------------------------

func _new(seed_v := 1234) -> void:
	GameState.new_game({"map_type": "interior", "seed": seed_v, "difficulty": "facil"})
	GameState.money = 1e7
	GameState.government["treasury"] = 1e7


## Dinero del sistema (FlowSim): jugador, ciudadanos, empresas, tesoros, bancos y cuenta externa.
func _system_money() -> float:
	return FlowSim.conserved_total(GameState)   # Auditoría: bolsillos + cuenta externa.


## Territorios del Estado con tierra, lejos del pueblo (para comprarlos y venderlos).
func _state_chunks(n: int) -> Array:
	var gs = GameState
	var g := MapSim.gen(gs)
	for z in g.zones:
		MapSim.reveal_zone_quiet(gs, int(z["id"]))
	var out := []
	for cy in range(g.c0, g.c1 + 1):
		for cx in range(g.c0, g.c1 + 1):
			if out.size() >= n:
				return out
			if maxi(absi(cx), absi(cy)) < 3 or not g.in_country_chunk(cx, cy):
				continue
			if str(LandSim.owner_info(gs, cx, cy)["owner"]) == "estado" and float(LandSim.quick_info(gs, cx, cy)["land"]) >= 1.0:
				MunicipalSim.region(gs, g.zone_index(cx, cy))["policy"]["regulation"] = "media"
				out.append(Vector2i(cx, cy))
	return out


func _rich_citizen(amount: float) -> Citizen:
	var gs = GameState
	for c in gs.citizens.values():
		if not gs.is_player(c.id) and c.age_years(gs.today()) >= 25:
			c.money = amount
			return c
	return null


# --- Terrenos ---------------------------------------------------------------------------------------------

func _test_lands() -> void:
	print("-- Cartera de terrenos --")
	_new()
	var gs = GameState
	var cs := _state_chunks(5)
	check(cs.size() == 5, "hay territorios del Estado para comprar (%d)" % cs.size())
	var a: Vector2i = cs[0]
	var price := LandSim.remaining_price(gs, a.x, a.y)
	check(LandSim.buy_from_state(gs, a.x, a.y) == "", "compra un territorio al Estado por %s" % Fmt.money(price))
	var k := LandPortfolioSim.key(a.x, a.y)
	LandPortfolioSim.sync(gs)
	var lot: Dictionary = LandPortfolioSim.st(gs)["lots"].get(k, {})
	check(not lot.is_empty() and int(lot["parcels"]) == 25 and absf(float(lot["basis"]) - price) < 1.0, "el terreno aparece con 25 parcelas y su precio de compra (%s)" % Fmt.money(float(lot.get("basis", 0))))
	check(LandPortfolioSim.st(gs)["lots"].has("0,0") and LandPortfolioSim.sell_block_reason(gs, "0,0", "estado") != "", "el terreno del pueblo está en la cartera pero no se vende")
	# Se valoriza y se desvaloriza.
	var zid := MapSim.gen(gs).zone_index(a.x, a.y)
	gs.map["land_index"][str(zid)] = 1.3
	var row := _row(k)
	check(float(row["value"]) > price * 1.15 and absf(float(row["gain"]) - (float(row["value"]) - price)) < 1.0 and absf(float(row["gain_pct"]) - float(row["gain"]) / price) < 0.001,
		"sube el índice: valor %s, plusvalía %s (%s)" % [Fmt.money(float(row["value"])), Fmt.money(float(row["gain"])), Fmt.pct_1(float(row["gain_pct"]) * 100.0)])
	gs.map["land_index"][str(zid)] = 0.75
	row = _row(k)
	check(float(row["gain"]) < 0.0 and float(row["value"]) < price, "baja el índice: minusvalía %s" % Fmt.money(float(row["gain"])))
	check(str(row["use"]) == "vacío", "uso: %s" % row["use"])
	# Predial.
	var pred := LandPortfolioSim.predial_month(gs, k)
	var reg := MunicipalSim.region(gs, zid)
	var mt0 := float(reg.get("treasury", 0.0))
	var m0: float = gs.money
	var sys0 := _system_money()
	LandPortfolioSim.monthly(gs)
	var paid := float(LandPortfolioSim.st(gs)["predial_last"])
	check(pred > 0.0 and absf(float(reg.get("treasury", 0.0)) - mt0 - pred) < 0.02, "predial %s/mes al tesoro del municipio" % Fmt.money2(pred))
	check(absf(m0 - gs.money - paid) < 0.05 and paid >= pred, "el jugador paga el predial de todos sus terrenos (%s)" % Fmt.money2(paid))
	check(absf(_system_money() - sys0) < 0.05, "predial: el dinero se conserva")
	var tax_lo := LandPortfolioSim.predial_rate(gs, zid)
	reg["policy"]["regulation"] = "alta"
	check(LandPortfolioSim.predial_rate(gs, zid) > tax_lo, "más predial con regulación alta (%s → %s anual)" % [Fmt.pct_1(tax_lo * 100.0), Fmt.pct_1(LandPortfolioSim.predial_rate(gs, zid) * 100.0)])
	reg["policy"]["regulation"] = "media"
	check(not (lot["hist"] as Array).is_empty(), "historial de valor del terreno")
	# Venta al Estado.
	var sp := LandPortfolioSim.state_price(gs, k)
	var tr0 := float(gs.government["treasury"])
	m0 = gs.money
	sys0 = _system_money()
	check(LandPortfolioSim.sell_to_state(gs, k) == "", "vende al Estado por %s (precio fijo)" % Fmt.money(sp))
	check(absf(gs.money - m0 - sp) < 1.0 and absf(tr0 - float(gs.government["treasury"]) - sp) < 1.0, "el tesoro paga y el jugador cobra")
	check(not LandPortfolioSim.st(gs)["lots"].has(k) and LandSim.player_parcels(gs, a.x, a.y) == 0 and str(LandSim.owner_info(gs, a.x, a.y)["owner"]) == "estado", "el territorio vuelve al Estado")
	check(absf(_system_money() - sys0) < 1.0, "venta al Estado: el dinero se conserva")
	# Oferta entrante: rechazada y aceptada.
	var b: Vector2i = cs[1]
	LandSim.buy_from_state(gs, b.x, b.y)
	var kb := LandPortfolioSim.key(b.x, b.y)
	var rich := _rich_citizen(LandPortfolioSim.value_of(gs, kb) * 3.0)
	var o := LandPortfolioSim.make_incoming_offer(gs, kb)
	check(not o.is_empty() and str(o["status"]) == "pendiente", "un empresario o ciudadano rico oferta %s por tu terreno" % Fmt.money(float(o.get("amount", 0))))
	check(gs.notifications_log[-1]["text"].contains("Oferta por tu terreno"), "llega como notificación")
	LandPortfolioSim.reject_offer(gs, int(o["id"]))
	check(str(LandPortfolioSim.get_offer(gs, int(o["id"]))["status"]) == "rechazada" and LandPortfolioSim.st(gs)["lots"].has(kb), "oferta rechazada: el terreno sigue siendo tuyo")
	var o2 := LandPortfolioSim.make_incoming_offer(gs, kb)
	var r_hi := LandPortfolioSim.counter_offer(gs, int(o2["id"]), float(o2["amount"]) * 5.0)
	check(LandPortfolioSim.st(gs)["lots"].has(kb) and (str(o2["status"]) == "retirada" or bool(o2.get("countered", false))), "contraoferta exagerada: %s" % r_hi)
	var o3 := LandPortfolioSim.make_incoming_offer(gs, kb) if str(o2["status"]) != "pendiente" else o2
	var buyer: Citizen = gs.citizens.get(int(o3["cid"]))
	var bm0: float = buyer.money if buyer != null else 0.0
	m0 = gs.money
	sys0 = _system_money()
	var amt := float(o3["amount"])
	check(LandPortfolioSim.accept_offer(gs, int(o3["id"])) == "", "acepta la oferta de %s por %s" % [o3["buyer"], Fmt.money(amt)])
	check(absf(gs.money - m0 - amt) < 1.0 and buyer != null and bm0 - buyer.money > 0.0, "el comprador paga (de sus ahorros o su empresa) y el jugador cobra")
	var ov: Dictionary = gs.map["parcels"].get(kb, {})
	check(str(ov.get("owner", "")) == "npc" and int(ov.get("citizen_id", -1)) == int(o3["cid"]) and LandSim.player_parcels(gs, b.x, b.y) == 0, "el territorio queda a nombre del comprador")
	check(absf(_system_money() - sys0) < 1.0, "venta a un NPC: el dinero se conserva")
	# Recomprarlo exige negociar con su nuevo dueño.
	var neg := LandSim.negotiation(gs, b.x, b.y, 1.0)
	check(not neg.is_empty() and not bool(neg["ok"]), "recomprarle a %s exige negociar (%s)" % [o3["buyer"], str(neg.get("profile", {}).get("label", ""))])
	# Venta con precio pedido.
	var c: Vector2i = cs[2]
	LandSim.buy_from_state(gs, c.x, c.y)
	var kc := LandPortfolioSim.key(c.x, c.y)
	_rich_citizen(LandPortfolioSim.value_of(gs, kc) * 4.0)
	check(LandPortfolioSim.list_for_sale(gs, kc, LandPortfolioSim.value_of(gs, kc) * 0.8) == "", "lo pone en venta por debajo del mercado")
	var days := 0
	while LandPortfolioSim.st(gs)["lots"].has(kc) and days < 200:
		TimeManager.advance_days(1)
		days += 1
	check(not LandPortfolioSim.st(gs)["lots"].has(kc), "un comprador lo compra al precio pedido (%d días)" % days)
	# Arriendo.
	var d: Vector2i = cs[3]
	LandSim.buy_from_state(gs, d.x, d.y)
	var kd := LandPortfolioSim.key(d.x, d.y)
	_rich_citizen(LandPortfolioSim.value_of(gs, kd))
	check(LandPortfolioSim.lease(gs, kd) == "", "arrienda el terreno a %s/mes" % Fmt.money2(LandPortfolioSim.lease_rent(gs, kd)))
	check(LandPortfolioSim.sell_block_reason(gs, kd, "estado") != "", "arrendado no se vende")
	m0 = gs.money
	var pr_d := LandPortfolioSim.predial_month(gs, kd)
	LandPortfolioSim.monthly(gs)
	check(float(LandPortfolioSim.st(gs)["lots"][kd]["lease"].get("paid", 0.0)) > 0.0, "el arrendatario paga la renta")
	# Con edificios: solo se vende todo.
	var e: Vector2i = cs[4]
	LandSim.buy_from_state(gs, e.x, e.y)
	var ke := LandPortfolioSim.key(e.x, e.y)
	var shop := ConstructionSim.make_building(gs, "panaderia", 1, e.x * 400.0 + 20.0, e.y * 400.0 + 20.0, 0.0, "jugador")
	gs.add_building(shop)
	BusinessSim.ledger_add(shop, "obras", 400.0)
	check(LandPortfolioSim.sell_block_reason(gs, ke, "estado").begins_with("Tiene edificios"), "con un negocio tuyo no se vende suelto")
	var big := _rich_citizen(LandPortfolioSim.sell_all_price(gs, ke) * 2.0)
	sys0 = _system_money()
	var err_all := LandPortfolioSim.sell_all(gs, ke)
	check(err_all == "", "%s: vende todo (terreno + negocio) por %s" % [err_all, Fmt.money(LandPortfolioSim.sell_all_price(gs, ke))])
	check(NpcBusinessSim.is_npc(shop) and int(shop["owner_id"]) == big.id, "el negocio pasa a ser empresa del comprador")
	check(absf(_system_money() - sys0) < 1.0, "vender todo: el dinero se conserva")


func _row(k: String) -> Dictionary:
	for r in LandPortfolioSim.rows(GameState):
		if str(r["key"]) == k:
			return r
	return {}


func _test_negotiation() -> void:
	print("-- Negociación (recomprar a su dueño) --")
	_new(99)
	var gs = GameState
	var kinds := {}
	for i in range(60):
		var p := NegotiationSim.profile(gs, "land:%d,0" % i, 1000.0, i % 7)
		kinds[str(p["kind"])] = int(kinds.get(str(p["kind"]), 0)) + 1
	check(kinds.size() >= 3, "unos piden alto, otros bajo y otros se niegan: %s" % str(kinds))
	var p2 := NegotiationSim.profile(gs, "land:3,0", 1000.0, 3)
	check(str(NegotiationSim.profile(gs, "land:3,0", 1000.0, 3)["kind"]) == str(p2["kind"]), "el mismo dueño responde igual (determinista)")
	var ok := NegotiationSim.respond(gs, "land:3,0", 1000.0, 3, float(p2["ask"]) + 1.0)
	check(bool(ok["ok"]), "pagando lo que pide, acepta (%s)" % ok["text"])
	var lo := NegotiationSim.respond(gs, "land:3,0", 1000.0, 3, float(p2["ask"]) * 0.5)
	check(not bool(lo["ok"]), "con la mitad de lo que pide, no (%s)" % lo["text"])
	var old := NegotiationSim.profile(gs, "x", 1000.0, 3, gs.today() - 3650)
	var fresh := NegotiationSim.profile(gs, "x", 1000.0, 3, gs.today())
	check(float(old["ask"]) > float(fresh["ask"]), "el apego (años como dueño) sube lo que pide")


# --- Costeo ------------------------------------------------------------------------------------------------

func _test_costing() -> void:
	print("-- Costeo por fábrica y calculadora --")
	_new(4242)
	var gs = GameState
	var est := CostSim.estimate(gs, "panaderia", 1)
	check(float(est["unit_cost"]) > 0.0 and float(est["price"]) > 0.0, "calculadora antes de construir: %s/u, mercado %s, margen %s" % [Fmt.money2(float(est["unit_cost"])), Fmt.money2(float(est["price"])), Fmt.pct(float(est["margin_pct"]) * 100.0)])
	print("     ", CostSim.estimate_text(est).replace("\n", "\n      "))
	var b := ConstructionSim.make_building(gs, "panaderia", 1, 26.0, -26.0, 0.0, "jugador")
	gs.add_building(b)
	BusinessSim.ledger_add(b, "obras", float(est["build_cost"]))
	b["auto_price"] = true
	var cands := BusinessSim.candidates(gs, b)
	var jobs := int(gs.level_def(b).get("jobs", 1))
	for i in range(mini(jobs, cands.size())):
		BusinessSim.hire(gs, b, cands[i], maxf(BusinessSim.asked_wage(gs, cands[i], "panaderia"), GovSim.min_wage(gs)))
	for m in range(3):
		_to_next_month()
	var c: Dictionary = b.get("costing", {})
	check(not c.is_empty() and float(c["units"]) > 0.0, "costeo del mes: %s unidades" % Fmt.thousands(float(c.get("units", 0))))
	var sum := 0.0
	for k in CostSim.PARTS:
		sum += float(c["parts"][k])
	check(absf(sum - float(c["total"])) < 0.001 and absf(float(c["unit_cost"]) * float(c["units"]) - float(c["total"])) < 0.01, "total = suma del desglose (%s)" % Fmt.money(float(c["total"])))
	var real := float(c["unit_cost"])
	var e := float(est["unit_cost"])
	check(absf(real - e) / e <= 0.2, "calculadora coherente con la realidad tras 3 meses: estimado %s, real %s (%s)" % [Fmt.money2(e), Fmt.money2(real), Fmt.pct_1((real / e - 1.0) * 100.0)])
	check(float(c["parts"]["sueldos"]) > 0.0 and float(c["parts"]["depreciacion"]) > 0.0, "incluye sueldos y depreciación")
	check(float(c["price"]) > 0.0 and absf(float(c["margin"]) - (float(c["price"]) - real)) < 0.0001, "precio de venta promedio %s y margen %s/u" % [Fmt.money2(float(c["price"])), Fmt.money2(float(c["margin"]))])
	check(float(c["break_even"]) > 0.0, "punto de equilibrio: %s u./mes" % ("∞" if float(c["break_even"]) == INF else Fmt.thousands(float(c["break_even"]))))
	check((b.get("cost_hist", []) as Array).size() >= 2, "historial de costo por unidad")


func _to_next_month() -> void:
	var n: int = GameState.history.size()
	var guard := 0
	while GameState.history.size() == n and guard < 40:
		TimeManager.advance_days(1)
		guard += 1


# --- Transporte ------------------------------------------------------------------------------------------------

func _shipment(st_id: int, to_id: int, qty: float, dist_m: float) -> Dictionary:
	var s := {"route": -1, "good": "trigo", "qty": qty, "from": 0, "to": to_id, "mode": "pie", "crew": [[st_id, 1]], "vehicles": [],
		"carriers": 1, "depart": GameState.today() + 0.3, "travel": 0.1, "trips": 1, "arrive": GameState.today() + 900.0, "back": GameState.today() + 901.0,
		"ax": 0.0, "az": 0.0, "bx": dist_m, "bz": 0.0, "delivered": false, "fuel": 0.0, "bought": 0.0}
	LogisticsSim.shipments(GameState).append(s)
	return s


func _test_transport() -> void:
	print("-- Transporte: división interna y empresa aparte --")
	_new(31)
	var gs = GameState
	var st := ConstructionSim.make_building(gs, "central_transporte", 1, -30.0, 30.0, 0.0, "jugador")
	gs.add_building(st)
	var f1 := ConstructionSim.make_building(gs, "panaderia", 1, 30.0, 30.0, 0.0, "jugador")
	var f2 := ConstructionSim.make_building(gs, "cantera", 1, 30.0, -30.0, 0.0, "jugador")
	gs.add_building(f1)
	gs.add_building(f2)
	check(TransportDivSim.is_transport(gs, st) and TransportDivSim.org(st) == "interna", "la central de transporte es división interna por defecto")
	# Interna: 300 u·km para f1 y 100 u·km para f2; costo 40 → 30 y 10.
	_shipment(int(st["id"]), int(f1["id"]), 300.0, 800.0)
	_shipment(int(st["id"]), int(f2["id"]), 100.0, 800.0)
	TransportDivSim.daily(gs)
	st["ledger"]["month"] = {"salarios": 30.0, "mantenimiento": 10.0}
	for b in [st, f1, f2]:
		b["ledger"]["last_month"] = b["ledger"]["month"]
		b["ledger"]["month"] = {}
	var m0: float = gs.money
	TransportDivSim.monthly(gs)
	var a1 := TransportDivSim.allocated_to(gs, f1)
	var a2 := TransportDivSim.allocated_to(gs, f2)
	check(absf(a1 - 30.0) < 0.01 and absf(a2 - 10.0) < 0.01, "costo interno repartido por unidades·km: %s y %s" % [Fmt.money2(a1), Fmt.money2(a2)])
	check(gs.money == m0, "el reparto interno no mueve dinero")
	var bd := CostSim.breakdown(gs, f1, 100.0, 1.0)
	check(absf(float(bd["parts"]["transporte"]) - 30.0) < 0.01, "aparece como transporte asignado en el costeo de la fábrica")
	# Empresa aparte.
	check(TransportDivSim.set_org(gs, st, "empresa", "Transportes Cuadros", "sas") == "", "se convierte en empresa aparte (Transportes Cuadros)")
	var sys0 := _system_money()
	m0 = gs.money
	_shipment(int(st["id"]), int(f1["id"]), 200.0, 1000.0)
	TransportDivSim.daily(gs)
	var fee := float(f1["ledger"]["month"].get("fletes", 0.0))
	var expect := TransportDivSim.freight(gs, st, 200.0, 1.0 * float(LogisticsSim.tcfg().get("route_factor", 1.25)))
	check(fee > 0.0 and absf(fee - expect) < 0.02 and absf(float(st["ledger"]["month"].get("ventas", 0.0)) - fee) < 0.001, "factura un flete de %s (venta de la transportadora, gasto de la fábrica)" % Fmt.money2(fee))
	check(gs.money == m0 and absf(_system_money() - sys0) < 0.001, "el flete interno no mueve dinero (dinero conservado)")
	st["ledger"]["month"]["salarios"] = 20.0
	f1["ledger"]["month"]["ventas"] = 100.0
	for b in [st, f1, f2]:
		b["ledger"]["last_month"] = b["ledger"]["month"]
		b["ledger"]["month"] = {}
	TransportDivSim.monthly(gs)
	var cons := TransportDivSim.consolidated(gs)
	var profit := 0.0
	for b in [st, f1, f2]:
		profit += BusinessSim.period_profit(b, "last_month")
	check(absf(float(cons["internal"]) - fee) < 0.001 and absf(float(cons["income"]) - 100.0) < 0.001, "consolidado: ingresos %s sin el flete interno (%s eliminado)" % [Fmt.money(float(cons["income"])), Fmt.money2(fee)])
	check(absf(float(cons["result"]) - profit) < 0.001 and absf(float(cons["result"]) - (100.0 - 20.0)) < 0.001, "resultado del grupo = %s (sin contar dos veces)" % Fmt.money(float(cons["result"])))
	var rows := TransportDivSim.finance_rows(gs)
	check(rows.size() == 1 and str(rows[0]["org"]) == "empresa" and absf(float(rows[0]["result"]) - (fee - 20.0)) < 0.001, "Finanzas: la transportadora como línea propia (resultado %s)" % Fmt.money2(float(rows[0]["result"]) if not rows.is_empty() else 0.0))
	# Clientes NPC (dinero real de su caja).
	var owner := _rich_citizen(500.0)
	var npc := ConstructionSim.make_building(gs, "cantera", 1, -30.0, -30.0, 0.0, "ciudadano")
	npc["npc"] = true
	npc["npc_state"] = NpcBusinessSim.STATE_OPEN
	npc["owner_id"] = owner.id
	npc["reserve"] = 2000.0
	gs.add_building(npc)
	var hired := BusinessSim.candidates(gs, st)
	BusinessSim.hire(gs, st, hired[0], 3.0)
	sys0 = _system_money()
	TransportDivSim.monthly(gs)
	var npc_fee := 0.0
	for nb in NpcBusinessSim.npc_buildings(gs):
		npc_fee += float(nb["ledger"]["month"].get("fletes", 0.0))
	check(npc_fee > 0.0, "cobra fletes a una empresa NPC (%s de su caja)" % Fmt.money2(npc_fee))
	check(absf(_system_money() - sys0) < 0.01 + float(gs.informal.get("iva_pending", 0.0)) + 1.0, "cliente NPC: el dinero pasa de su caja a la tuya")


# --- Precios ----------------------------------------------------------------------------------------------------

func _test_prices() -> void:
	print("-- Historial y tabla de precios --")
	_new(55)
	var gs = GameState
	for i in range(14):
		_to_next_month()
	var h := PriceHistorySim.st(gs)
	check((h["m"] as Array).size() >= 13, "historial mensual guardado (%d meses)" % (h["m"] as Array).size())
	var e0: Dictionary = h["m"][0]
	check((e0["p"] as Dictionary).size() >= 50 and float(e0["ipc"]) > 0.0 and e0.has("w") and e0.has("land"), "cada mes: %d bienes, IPC, salario promedio y valor del suelo" % (e0["p"] as Dictionary).size())
	var c12 := PriceHistorySim.change(gs, "trigo", 12)
	check(not is_nan(c12), "variación del trigo en 12 meses: %s" % Fmt.pct_1(c12 * 100.0))
	check(is_nan(PriceHistorySim.change(gs, "trigo", 60)), "sin datos de hace 5 años todavía (se muestra «—»)")
	var mm := PriceHistorySim.min_max(gs, "trigo")
	check(mm.x > 0.0 and mm.y >= mm.x, "mínimo %s y máximo %s" % [Fmt.money2(mm.x), Fmt.money2(mm.y)])
	EconomySim.good_state(gs, "madera")["factor"] = 1.3
	check(PriceHistorySim.causes(gs, "madera").has("escasez"), "causa de la fluctuación: %s" % ", ".join(PriceHistorySim.causes(gs, "madera")))
	var n0 := (h["m"] as Array).size()
	for i in range(260 - n0):
		PriceHistorySim.record(gs)
	check((h["m"] as Array).size() <= 240 and (h["y"] as Array).size() >= 1, "tope: %d meses + %d promedios anuales" % [(h["m"] as Array).size(), (h["y"] as Array).size()])
	var s := PriceHistorySim.series(gs, "ipc", 0)
	check((s["values"] as Array).size() == (h["m"] as Array).size() + (h["y"] as Array).size(), "serie del IPC completa (anual + mensual)")


# --- Inmobiliaria (sección H) ----------------------------------------------------------------------------------------

func _test_agency() -> void:
	print("-- Inmobiliaria (sección H) --")
	_new(808)
	var gs = GameState
	for t in ["adobe", "ladrillo", "arquitectura_urbana"]:
		if not gs.techs.has(t):
			gs.techs.append(t)
	check(RealEstateSim.project_block_reason(gs, 4, "normal").contains("inmobiliaria"), "sin inmobiliaria no hay proyectos inmobiliarios")
	var ag := ConstructionSim.make_building(gs, "inmobiliaria", 1, -70.0, -70.0, 0.0, "jugador")
	gs.add_building(ag)
	check(not RealEstateSim.project_block_reason(gs, 4, "normal").contains("inmobiliaria"), "con la inmobiliaria se habilitan (%s)" % RealEstateSim.project_block_reason(gs, 4, "normal"))
	var opts := AgencySim.project_options(gs)
	var multi := opts.filter(func(o): return str(o["kind"]) == "apartamentos")
	check(opts.size() >= 4 and not multi.is_empty() and float(multi[0]["budget"]) > 0.0 and float(multi[0]["unit_price"]) > 0.0 and float(multi[0]["unit_rent"]) > 0.0,
		"proyectos con presupuesto, venta y renta por unidad (%s: %s, %s/u, renta %s/u)" % [multi[0]["label"], Fmt.money(float(multi[0]["budget"])), Fmt.money(float(multi[0]["unit_price"])), Fmt.money2(float(multi[0]["unit_rent"]))])
	var cs := _state_chunks(1)
	check(AgencySim.buy_land(gs, ag, cs[0].x, cs[0].y) == "", "compra un terreno a nombre de la inmobiliaria")
	var lot: Dictionary = LandPortfolioSim.st(gs)["lots"].get(LandPortfolioSim.key(cs[0].x, cs[0].y), {})
	check(int(lot.get("company", -1)) == int(ag["id"]) and BusinessSim.period_value(ag, "total", "obras") > 0.0, "queda en el libro de la empresa")
	var r := RealEstateSim.start_project(gs, 4, "normal", 30.0, 26.0, 0.0, "Torres Test")
	check(r.has("building") and int(r["building"].get("agency_id", -1)) == int(ag["id"]), "el proyecto queda a nombre de la inmobiliaria")
	# Recompra negociada de un apartamento vendido.
	var apt := ConstructionSim.make_building(gs, "vivienda", 4, -30.0, 30.0, 0.0, "jugador")
	gs.add_building(apt)
	RealEstateSim.ensure_units(gs, apt)
	var owner := _rich_citizen(100.0)
	var u: Dictionary = apt["units"][0]
	u["status"] = "vendida"
	u["owner_id"] = owner.id
	u["household"] = [owner.id]
	var ask := AgencySim.ask_unit(gs, apt, u)
	check(not ask.is_empty(), "el dueño dice su postura: %s (pide %s)" % [ask.get("label", ""), Fmt.money(float(ask.get("ask", 0)))])
	var low := AgencySim.rebuy_unit(gs, apt, u, 1.0)
	check(not bool(low["ok"]) and str(u["status"]) == "vendida", "una oferta ridícula no basta: %s" % low["text"])
	if str(ask["kind"]) != "se_niega":
		var sys0 := _system_money()
		var ok := AgencySim.rebuy_unit(gs, apt, u, float(ask["ask"]) + 1.0)
		check(bool(ok["ok"]) and str(u["status"]) == "arrendada" and int(u["tenant_id"]) == owner.id, "pagando lo que pide se recompra y la familia queda de inquilina")
		check(absf(_system_money() - sys0) < 1.0, "recompra: el dinero se conserva")
	else:
		check(not bool(AgencySim.rebuy_unit(gs, apt, u, float(ask["ask"]) * 0.9)["ok"]), "este dueño no quiere vender")


# --- Guardar y cargar ------------------------------------------------------------------------------------------------

func _test_save_load() -> void:
	print("-- Guardar y cargar --")
	_new(2024)
	var gs = GameState
	var cs := _state_chunks(1)
	LandSim.buy_from_state(gs, cs[0].x, cs[0].y)
	var k := LandPortfolioSim.key(cs[0].x, cs[0].y)
	_rich_citizen(LandPortfolioSim.value_of(gs, k) * 3.0)
	var o := LandPortfolioSim.make_incoming_offer(gs, k)
	var st := ConstructionSim.make_building(gs, "caballeriza", 1, -30.0, 30.0, 0.0, "jugador")
	gs.add_building(st)
	TransportDivSim.set_org(gs, st, "empresa", "Arrieros Cuadros")
	var f := ConstructionSim.make_building(gs, "panaderia", 1, 30.0, 30.0, 0.0, "jugador")
	gs.add_building(f)
	_to_next_month()
	_to_next_month()
	var basis := float(LandPortfolioSim.st(gs)["lots"][k]["basis"])
	var nh := (PriceHistorySim.st(gs)["m"] as Array).size()
	check(SaveManager.save_game("test_terrenos"), "partida guardada")
	GameState.new_game({"map_type": "interior", "seed": 1})
	check(SaveManager.load_game("test_terrenos"), "partida cargada")
	gs = GameState
	check(absf(float(LandPortfolioSim.st(gs)["lots"].get(k, {}).get("basis", -1.0)) - basis) < 0.01, "terreno y precio de compra conservados")
	check(o.is_empty() or LandPortfolioSim.get_offer(gs, int(o["id"])).size() > 0, "ofertas conservadas")
	check((PriceHistorySim.st(gs)["m"] as Array).size() == nh and nh >= 2, "historial de precios conservado (%d meses)" % nh)
	check(TransportDivSim.org(gs.get_building(int(st["id"]))) == "empresa" and str(gs.get_building(int(st["id"])).get("company_name", "")) == "Arrieros Cuadros", "empresa de transporte conservada")
	check(gs.get_building(int(f["id"])).has("costing"), "costeo conservado")
	SaveManager.delete_save("test_terrenos")
	# Partida vieja: sin el estado nuevo → valores por defecto.
	var d: Dictionary = gs.to_dict()
	(d["map"] as Dictionary).erase("land_pf")
	for key in ["transport", "price_hist", "costing_goods"]:
		(d["economy"] as Dictionary).erase(key)
	GameState.load_dict(d)
	check(GameState.map.get("land_pf") is Dictionary and GameState.economy.get("price_hist") is Dictionary and GameState.economy.get("transport") is Dictionary, "partida vieja: se crean los valores por defecto")
	LandPortfolioSim.sync(GameState)
	check(LandPortfolioSim.st(GameState)["lots"].has(k), "partida vieja: los terrenos se reconstruyen desde las parcelas")
	TimeManager.advance_days(31)
	check(GameState.running, "la partida migrada sigue corriendo")
