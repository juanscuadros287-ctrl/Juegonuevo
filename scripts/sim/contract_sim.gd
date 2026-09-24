class_name ContractSim
extends RefCounted
## Libre mercado — contratos de compraventa firmados entre el jugador y sus clientes.
## Clientes (clave): "town:<id>" (pueblo vecino con ruta), "npc:<id edificio>" (empresa NPC del
## pueblo) y "gov" (gobierno del pueblo).
##   - Solicitudes entrantes (inbox): llegan SOLO para bienes que produce alguno de tus negocios.
##     Aceptar firma el contrato; rechazar o dejar vencer: el cliente compra a otro proveedor.
##   - Ofertas salientes (sent): tú propones bien, cantidad y precio; el cliente responde en
##     unos días según su necesidad, el precio de mercado, la distancia y la relación.
##   - Contratos (contracts): entrega única o mensual por N meses, con penalidad por incumplir.
##     Entregar descuenta del almacén (primero la bodega de la plaza, salida del pueblo) y del
##     inventario de tus negocios; a otros pueblos va por la ruta comercial (pagas el flete) y
##     te pagan al llegar. El pago sale de la caja real del comprador (economía cerrada).
##   - Reputación por cliente (0-100): sube al cumplir y baja al incumplir; cambia el precio y
##     la frecuencia de futuras solicitudes.

const NON_GOODS := ["", "construccion", "credito", "servicio", "investigacion", "educacion", "transporte", "entrada", "alojamiento", "publicidad"]


static func cfg() -> Dictionary:
	return FreeMarketSim.cfg().get("contracts", {})


static func inbox(gs) -> Array:
	return gs.market.get("inbox", [])


static func sent(gs) -> Array:
	return gs.market.get("sent", [])


static func contracts(gs) -> Array:
	return gs.market.get("contracts", [])


static func active_contracts(gs) -> Array:
	return contracts(gs).filter(func(k): return str(k["status"]) == "activo")


static func find(list: Array, id: int) -> Dictionary:
	for x in list:
		if int(x["id"]) == id:
			return x
	return {}


# --- Bienes del jugador -------------------------------------------------------------------------

## Bienes que produce alguno de tus negocios activos (o en mejora).
static func player_goods(gs) -> Dictionary:
	var out := {}
	for b in gs.buildings:
		if not gs.owned_by_player(b) or str(b["status"]) in ["construccion", "cerrado"]:
			continue
		var p := str(gs.building_def(b).get("product", ""))
		if p in NON_GOODS or not (GameData.goods.has(p) or TradeSim.trade_goods().has(p)):
			continue
		if not bool(GameData.goods.get(p, {}).get("storable", true)):
			continue
		out[p] = true
	return out


## Existencias disponibles para entregar: almacenes + inventario de tus negocios.
static func available(gs, good: String) -> float:
	return ConstructionSim.stock_of(gs, good)


static func _take_goods(gs, good: String, qty: float) -> float:
	var got := WarehouseSim.remove(gs, good, qty)   # La bodega de la plaza primero (salida del pueblo).
	var left := qty - got
	for b in gs.buildings:
		if left <= 0.0001:
			break
		if not gs.owned_by_player(b):
			continue
		var inv: Dictionary = b.get("inventory", {})
		var have := float(inv.get(good, 0.0))
		if have > 0.0:
			var take := minf(have, left)
			inv[good] = have - take
			left -= take
	return qty - maxf(0.0, left)


# --- Clientes -------------------------------------------------------------------------------------

static func client_kind(key: String) -> String:
	return key.get_slice(":", 0)


static func client_ref(key: String) -> String:
	return key.get_slice(":", 1) if key.contains(":") else ""


static func client_name(gs, key: String) -> String:
	match client_kind(key):
		"town":
			return str(TradeSim.town(gs, client_ref(key)).get("name", "Pueblo"))
		"npc":
			var b: Dictionary = gs.get_building(int(client_ref(key)))
			return gs.building_label(b) if not b.is_empty() else "Empresa cerrada"
		"gov":
			return "Gobierno del pueblo"
	return key


static func client_exists(gs, key: String) -> bool:
	match client_kind(key):
		"town":
			return not TradeSim.town(gs, client_ref(key)).is_empty()
		"npc":
			var b: Dictionary = gs.get_building(int(client_ref(key)))
			return not b.is_empty() and NpcBusinessSim.is_npc(b)
		"gov":
			return true
	return false


static func client_cash(gs, key: String) -> float:
	match client_kind(key):
		"town":
			return float(TradeSim.town(gs, client_ref(key)).get("cash", 0.0))
		"npc":
			return maxf(0.0, float(gs.get_building(int(client_ref(key))).get("reserve", 0.0)))
		"gov":
			return maxf(0.0, float(gs.government.get("treasury", 0.0)))
	return 0.0


## El cliente paga (lo que tenga). Devuelve lo pagado.
static func _client_pay(gs, key: String, amount: float) -> float:
	var paid := minf(amount, client_cash(gs, key))
	if paid <= 0.0:
		return 0.0
	match client_kind(key):
		"town":
			var t := TradeSim.town(gs, client_ref(key))
			t["cash"] = float(t["cash"]) - paid
		"npc":
			var b: Dictionary = gs.get_building(int(client_ref(key)))
			b["reserve"] = float(b["reserve"]) - paid
			BusinessSim.ledger_add(b, "insumos", paid)
		"gov":
			GovSim.add_treasury(gs, -paid)
	return paid


## El cliente recibe dinero (penalidades).
static func _client_receive(gs, key: String, amount: float) -> void:
	match client_kind(key):
		"town":
			var t := TradeSim.town(gs, client_ref(key))
			if not t.is_empty():
				t["cash"] = float(t.get("cash", 0.0)) + amount
		"npc":
			var b: Dictionary = gs.get_building(int(client_ref(key)))
			if not b.is_empty():
				b["reserve"] = float(b.get("reserve", 0.0)) + amount
			else:
				GovSim.add_treasury(gs, amount)
		_:
			GovSim.add_treasury(gs, amount)


static func reputation(gs, key: String) -> float:
	return float(gs.market.get("reputation", {}).get(key, cfg().get("rep_start", 50)))


static func _rep_add(gs, key: String, delta: float) -> void:
	var r: Dictionary = gs.market.get("reputation", {})
	r[key] = clampf(reputation(gs, key) + delta, 0.0, 100.0)
	gs.market["reputation"] = r


static func rep_price_factor(gs, key: String) -> float:
	return 0.9 + reputation(gs, key) / 500.0


static func rep_freq_factor(gs, key: String) -> float:
	return clampf(reputation(gs, key) / 50.0, 0.2, 2.0)


## Clientes a los que puedes ofrecer: pueblos con ruta, empresas NPC abiertas y el gobierno.
static func client_keys(gs) -> Array:
	var out := []
	for c in TradeSim.connected_towns(gs):
		out.append("town:%s" % str(c["town_id"]))
	for b in NpcBusinessSim.npc_buildings(gs):
		if str(b.get("npc_state", "")) == NpcBusinessSim.STATE_OPEN:
			out.append("npc:%d" % int(b["id"]))
	out.append("gov")
	return out


## Precio de referencia por unidad para un cliente (lo que pagaría hoy por el bien).
static func reference_price(gs, key: String, good: String, qty := 1.0) -> float:
	match client_kind(key):
		"town":
			var p := TradeSim.export_price(gs, client_ref(key), good, qty * 0.5)
			return p if p > 0.0 else EconomySim.market_price(gs, good)
		"npc":
			return EconomySim.market_price(gs, good) * float(cfg().get("local_wholesale", 0.75))
		"gov":
			return GovPlansSim.material_unit_price(gs, good) * float(cfg().get("gov_material_price", 0.9))
	return EconomySim.market_price(gs, good)


# --- Solicitudes entrantes -----------------------------------------------------------------------------

## Crea una solicitud en la bandeja (solo si el jugador produce el bien). Devuelve la solicitud o {}.
static func create_request(gs, key: String, good: String, qty: float, unit_price: float, installments := 1, deadline_days := 30, plan_id := -1) -> Dictionary:
	if not player_goods(gs).has(good) or qty < 1.0 or unit_price <= 0.0:
		return {}
	if inbox(gs).size() >= int(cfg().get("max_inbox", 6)):
		return {}
	var total := unit_price * qty * installments
	var r := {"id": FreeMarketSim.next_id(gs), "client": key, "client_name": client_name(gs, key), "good": good,
		"qty": floorf(qty), "unit_price": snappedf(unit_price, 0.01), "installments": maxi(1, installments),
		"deadline_days": deadline_days, "penalty": snappedf(unit_price * floorf(qty) * float(cfg().get("penalty_share", 0.2)), 0.01),
		"expires_day": gs.today() + int(cfg().get("inbox_days", 15)), "day": gs.today(), "plan_id": plan_id, "total": total}
	gs.market["inbox"].append(r)
	var when := "entrega única en %d días" % deadline_days if installments <= 1 else "entrega mensual por %d meses" % installments
	gs.notify("Solicitud de %s: %d de %s a %s c/u (%s). Acepta o rechaza en «Contratos»." % [r["client_name"], int(r["qty"]), TradeSim.good_label(good), Fmt.money2(float(r["unit_price"])), when], "negocio")
	return r


static func accept_request(gs, id: int) -> String:
	var r := find(inbox(gs), id)
	if r.is_empty():
		return "La solicitud ya no está."
	if not client_exists(gs, str(r["client"])):
		inbox(gs).erase(r)
		return "El cliente ya no existe."
	inbox(gs).erase(r)
	var k := _sign(gs, r, "solicitud")
	return "Contrato firmado con %s: %d de %s%s." % [k["client_name"], int(k["qty"]), TradeSim.good_label(str(k["good"])), "" if int(k["installments"]) <= 1 else " cada mes por %d meses" % int(k["installments"])]


static func reject_request(gs, id: int, silent := false) -> String:
	var r := find(inbox(gs), id)
	if r.is_empty():
		return "La solicitud ya no está."
	inbox(gs).erase(r)
	_rep_add(gs, str(r["client"]), -float(cfg().get("rep_reject", 1)))
	_covered_by_others(gs, r)
	if int(r.get("plan_id", -1)) >= 0:
		var p := GovPlansSim.plan(gs, int(r["plan_id"]))
		if not p.is_empty():
			p.get("materials_pending", {}).erase(str(r["good"]))
			if p.get("materials_pending", {}).is_empty() and str(p["status"]) == "materiales":
				GovPlansSim._start_build(gs, p)
	return "" if silent else "Rechazaste la solicitud de %s." % r["client_name"]


## La demanda que no cubres la cubren otros proveedores (otros pueblos o importación).
static func _covered_by_others(gs, r: Dictionary) -> void:
	FreeMarketSim.stat(gs, "covered_by_others", float(r["qty"]) * float(r.get("installments", 1)))
	FreeMarketSim.log_event(gs, "%s compró %d de %s a otro proveedor." % [r["client_name"], int(r["qty"]), TradeSim.good_label(str(r["good"]))])


static func _sign(gs, r: Dictionary, source: String) -> Dictionary:
	var inst := maxi(1, int(r.get("installments", 1)))
	var k := {"id": FreeMarketSim.next_id(gs), "client": str(r["client"]), "client_name": str(r["client_name"]), "good": str(r["good"]),
		"qty": float(r["qty"]), "unit_price": float(r["unit_price"]), "installments": inst, "done": 0, "failed": 0,
		"next_due": gs.today() + (int(r.get("deadline_days", 30)) if inst <= 1 else 30), "period": 30,
		"penalty": float(r.get("penalty", 0.0)), "auto": inst > 1, "status": "activo", "source": source,
		"signed_day": gs.today(), "paid": 0.0, "owed": 0.0, "plan_id": int(r.get("plan_id", -1)), "delivered": 0.0}
	gs.market["contracts"].append(k)
	FreeMarketSim.stat(gs, "contracts_signed", 1.0)
	return k


# --- Ofertas salientes ----------------------------------------------------------------------------------

static func offer_block_reason(gs, key: String, good: String, qty: float, unit_price: float) -> String:
	if not client_exists(gs, key):
		return "Ese cliente no existe."
	if client_kind(key) == "town" and TradeSim.connection(gs, client_ref(key)).is_empty():
		return "Necesitas una ruta comercial con ese pueblo."
	if qty < 1.0 or unit_price <= 0.0:
		return "Cantidad o precio inválido."
	if not player_goods(gs).has(good) and available(gs, good) < qty:
		return "No produces %s ni tienes %d en existencias." % [TradeSim.good_label(good), int(qty)]
	for o in sent(gs):
		if str(o["status"]) == "pendiente" and str(o["client"]) == key and str(o["good"]) == good:
			return "Ya tienes una oferta pendiente de ese bien a ese cliente."
	return ""


static func send_offer(gs, key: String, good: String, qty: float, unit_price: float) -> String:
	qty = floorf(qty)
	var why := offer_block_reason(gs, key, good, qty, unit_price)
	if why != "":
		return why
	var days: Array = cfg().get("offer_reply_days", [2, 5])
	var o := {"id": FreeMarketSim.next_id(gs), "client": key, "client_name": client_name(gs, key), "good": good, "qty": qty,
		"unit_price": snappedf(unit_price, 0.01), "day": gs.today(), "reply_day": gs.today() + FreeMarketSim.ri(gs, int(days[0]), int(days[1])),
		"status": "pendiente", "reason": ""}
	gs.market["sent"].append(o)
	return ""


## Decisión del cliente: {"yes": bool, "reason": String, "max": precio máximo que pagaría}.
static func evaluate_offer(gs, o: Dictionary) -> Dictionary:
	var key := str(o["client"])
	var good := str(o["good"])
	var qty := float(o["qty"])
	var price := float(o["unit_price"])
	if not client_exists(gs, key):
		return {"yes": false, "reason": "el cliente ya no existe", "max": 0.0}
	var need := 1.0
	var ref := reference_price(gs, key, good, qty)
	match client_kind(key):
		"town":
			var t := TradeSim.town(gs, client_ref(key))
			var row: Dictionary = t.get("goods", {}).get(good, {})
			if row.is_empty():
				return {"yes": false, "reason": "allá no se usa ese bien", "max": 0.0}
			var room := float(row.get("demand", 0.0)) * 2.0 - float(row.get("sat", 0.0))
			if room < qty * 0.5:
				return {"yes": false, "reason": "ya están abastecidos", "max": 0.0}
			need = 1.1 if t.get("demands", []).has(good) else (0.8 if bool(row.get("sells", false)) else 0.95)
			# Lejos, la entrega tarda más: pagan un poco menos.
			need *= clampf(1.05 - float(t.get("distance", 50.0)) / 1000.0, 0.85, 1.05)
		"npc":
			var b: Dictionary = gs.get_building(int(client_ref(key)))
			var wants: Array = NpcBusinessSim.cfg().get("input_wants", {}).get(str(b["type"]), [])
			var product := str(gs.building_def(b).get("product", ""))
			if not wants.has(good) and good != product:
				return {"yes": false, "reason": "no lo necesita", "max": 0.0}
			need = 1.1
		"gov":
			var wanted := false
			for p in GovPlansSim.plans(gs):
				if str(p["status"]) in ["materiales", "en_obra", "licitacion"] and GameData.level_def(str(p["type"]), 1).get("materials", {}).has(good):
					wanted = true
			if not wanted:
				return {"yes": false, "reason": "el gobierno no necesita ese bien ahora", "max": 0.0}
			need = 1.05
	var max_price := ref * need * rep_price_factor(gs, key)
	if price > max_price:
		return {"yes": false, "reason": "el precio es alto (pagarían hasta %s)" % Fmt.money2(max_price), "max": max_price}
	if client_cash(gs, key) < price * qty:
		return {"yes": false, "reason": "no tiene con qué pagar", "max": max_price}
	return {"yes": true, "reason": "", "max": max_price}


static func _resolve_offers(gs) -> void:
	for o in sent(gs):
		if str(o["status"]) != "pendiente" or int(o["reply_day"]) > gs.today():
			continue
		var ev := evaluate_offer(gs, o)
		if bool(ev["yes"]):
			o["status"] = "aceptada"
			var days := 30
			if client_kind(str(o["client"])) == "town":
				days = int(TradeSim.transport_quote(gs, client_ref(str(o["client"])), float(o["qty"]))["days"]) + 20
			var k := _sign(gs, {"client": o["client"], "client_name": o["client_name"], "good": o["good"], "qty": o["qty"],
				"unit_price": o["unit_price"], "installments": 1, "deadline_days": days,
				"penalty": float(o["unit_price"]) * float(o["qty"]) * float(cfg().get("penalty_share", 0.2))}, "oferta")
			o["contract_id"] = int(k["id"])
			gs.notify("%s aceptó tu oferta: %d de %s a %s c/u. Entrega antes del %s." % [o["client_name"], int(o["qty"]), TradeSim.good_label(str(o["good"])), Fmt.money2(float(o["unit_price"])), TimeManager.date_from_day(int(k["next_due"]), TimeManager.start_year())], "negocio")
		else:
			o["status"] = "rechazada"
			o["reason"] = str(ev["reason"])
			gs.notify("%s rechazó tu oferta de %s: %s." % [o["client_name"], TradeSim.good_label(str(o["good"])), o["reason"]], "negocio")
	var list := sent(gs)
	while list.size() > 30:
		list.pop_front()


# --- Entregas --------------------------------------------------------------------------------------------

static func deliver_block_reason(gs, k: Dictionary) -> String:
	if str(k["status"]) != "activo":
		return "El contrato no está activo."
	if int(k["installments"]) > 1 and gs.today() < int(k["next_due"]) - 15:
		return "Aún no toca la entrega (desde el %s)." % TimeManager.date_from_day(int(k["next_due"]) - 15, TimeManager.start_year())
	var key := str(k["client"])
	if not client_exists(gs, key):
		return "El cliente ya no existe."
	var qty := float(k["qty"])
	if available(gs, str(k["good"])) < qty:
		return "Solo tienes %d de %s (almacén + negocios)." % [int(available(gs, str(k["good"]))), TradeSim.good_label(str(k["good"]))]
	if client_kind(key) == "town":
		var tid := client_ref(key)
		if TradeSim.connection(gs, tid).is_empty():
			return "Necesitas la ruta comercial con %s." % k["client_name"]
		var tq := TradeSim.transport_quote(gs, tid, qty)
		if gs.money < float(tq["cost"]):
			return "Necesitas %s para el flete." % Fmt.money(float(tq["cost"]))
	return ""


## Entrega una cuota del contrato. Devuelve "" si salió bien.
static func deliver(gs, id: int) -> String:
	var k := find(contracts(gs), id)
	if k.is_empty():
		return "Contrato no encontrado."
	var why := deliver_block_reason(gs, k)
	if why != "":
		return why
	var key := str(k["client"])
	var good := str(k["good"])
	var qty := float(k["qty"])
	var value := qty * float(k["unit_price"])
	_take_goods(gs, good, qty)
	match client_kind(key):
		"town":
			var tid := client_ref(key)
			var tq := TradeSim.transport_quote(gs, tid, qty)
			TradeSim._pay_transport(gs, tid, {"transport": float(tq["cost"]), "mode": str(tq["mode"]), "days": int(tq["days"]), "trips": int(tq["trips"])})
			var row: Dictionary = TradeSim.town(gs, tid).get("goods", {}).get(good, {})
			if not row.is_empty():
				row["sat"] = float(row.get("sat", 0.0)) + qty
			gs.market["shipments"].append({"id": FreeMarketSim.next_id(gs), "contract_id": int(k["id"]), "client": key,
				"good": good, "qty": qty, "value": value, "arrive_day": gs.today() + int(tq["days"])})
		"npc":
			_collect(gs, k, value)
			var b: Dictionary = gs.get_building(int(client_ref(key)))
			b["inventory"][good] = float(b["inventory"].get(good, 0.0)) + qty
		"gov":
			_collect(gs, k, value)
			if int(k.get("plan_id", -1)) >= 0:
				GovPlansSim.on_material_delivered(gs, int(k["plan_id"]), good, qty)
	k["delivered"] = float(k.get("delivered", 0.0)) + qty
	k["done"] = int(k["done"]) + 1
	k["next_due"] = int(k["next_due"]) + int(k.get("period", 30))
	_rep_add(gs, key, float(cfg().get("rep_success", 4)))
	FreeMarketSim.stat(gs, "delivered_value", value)
	if int(k["done"]) + int(k["failed"]) >= int(k["installments"]):
		k["status"] = "cumplido"
	return ""


## Cobro al cliente (lo que no pueda pagar queda como deuda y se cobra cada mes).
static func _collect(gs, k: Dictionary, value: float) -> void:
	var paid := _client_pay(gs, str(k["client"]), value)
	if paid > 0.0:
		gs.add_money(paid)
		gs.add_counter("contract_sales", paid)
	k["paid"] = float(k.get("paid", 0.0)) + paid
	k["owed"] = float(k.get("owed", 0.0)) + value - paid


static func _arrivals(gs) -> void:
	var list: Array = gs.market.get("shipments", [])
	for s in list.duplicate():
		if int(s["arrive_day"]) > gs.today():
			continue
		list.erase(s)
		var k := find(contracts(gs), int(s["contract_id"]))
		if k.is_empty():
			k = {"client": s["client"], "paid": 0.0, "owed": 0.0}
		_collect(gs, k, float(s["value"]))
		gs.add_counter("exports", float(s["value"]))
		EconomySim.record_value(gs, "exports", float(s["value"]))


## Incumplimiento de una cuota: penalidad al cliente y baja la reputación.
static func _fail(gs, k: Dictionary) -> void:
	var key := str(k["client"])
	var pen := float(k.get("penalty", 0.0))
	if pen > 0.0:
		gs.add_money(-pen)
		_client_receive(gs, key, pen)
	_rep_add(gs, key, -float(cfg().get("rep_fail", 12)))
	k["failed"] = int(k["failed"]) + 1
	k["next_due"] = int(k["next_due"]) + int(k.get("period", 30))
	FreeMarketSim.stat(gs, "penalties", pen)
	var single := int(k["installments"]) <= 1
	if single or int(k["failed"]) >= 2:
		k["status"] = "incumplido"
	elif int(k["done"]) + int(k["failed"]) >= int(k["installments"]):
		k["status"] = "cumplido"
	gs.notify("Incumpliste %s con %s: pagaste %s de penalidad y bajó tu reputación (%d/100).%s" % ["el contrato" if single else "una entrega", k["client_name"], Fmt.money(pen), int(reputation(gs, key)), " Contrato cancelado." if str(k["status"]) == "incumplido" and not single else ""], "jugador")
	if int(k.get("plan_id", -1)) >= 0:
		var p := GovPlansSim.plan(gs, int(k["plan_id"]))
		if not p.is_empty():
			p.get("materials_pending", {}).erase(str(k["good"]))
			if p.get("materials_pending", {}).is_empty() and str(p["status"]) == "materiales":
				GovPlansSim._start_build(gs, p)


# --- Ciclo -----------------------------------------------------------------------------------------------

static func daily(gs) -> void:
	var today: int = gs.today()
	for r in inbox(gs).duplicate():
		if int(r["expires_day"]) < today:
			reject_request(gs, int(r["id"]), true)
	_resolve_offers(gs)
	_arrivals(gs)
	for k in contracts(gs):
		if str(k["status"]) != "activo":
			continue
		if not client_exists(gs, str(k["client"])):
			k["status"] = "cancelado"
			continue
		var due := int(k["next_due"])
		if bool(k.get("auto", false)) and today >= due - 3 and deliver_block_reason(gs, k) == "":
			deliver(gs, int(k["id"]))
			continue
		if today > due:
			_fail(gs, k)
	var list := contracts(gs)
	var closed := list.filter(func(k): return str(k["status"]) != "activo")
	while closed.size() > 30:
		list.erase(closed.pop_front())


static func monthly(gs) -> void:
	# Deudas pendientes de clientes.
	for k in contracts(gs):
		if float(k.get("owed", 0.0)) > 0.0 and client_exists(gs, str(k["client"])):
			var owed := float(k["owed"])
			k["owed"] = 0.0
			_collect(gs, k, owed)
	_generate_requests(gs)


static func _generate_requests(gs) -> void:
	var mine := player_goods(gs)
	if mine.is_empty():
		return
	var c := cfg()
	var qs: Array = c.get("qty_share", [0.08, 0.25])
	# Pueblos con ruta: piden lo que demandan (o lo que usan) si tú lo produces.
	for conn in TradeSim.connected_towns(gs):
		var tid := str(conn["town_id"])
		var key := "town:%s" % tid
		var t := TradeSim.town(gs, tid)
		var pop_f := clampf(pow(float(t.get("population", 1000)) / 1000.0, 0.3), 0.5, 2.0)
		if FreeMarketSim.rf(gs) > float(c.get("request_chance_month", 0.35)) * rep_freq_factor(gs, key) * pop_f:
			continue
		var options := []
		for g in t.get("goods", {}):
			if mine.has(str(g)) and not bool(t["goods"][g].get("sells", false)):
				options.append(str(g))
		if options.is_empty():
			continue
		var demanded := options.filter(func(g): return t.get("demands", []).has(g))
		var good: String = str(FreeMarketSim.pick(gs, demanded if not demanded.is_empty() else options))
		var row: Dictionary = t["goods"][good]
		var qty := clampf(roundf(float(row.get("demand", 20.0)) * FreeMarketSim.range_of(gs, qs)), float(c.get("min_qty", 5)), float(c.get("max_qty", 300)))
		var unit := TradeSim.export_price(gs, tid, good, qty * 0.5) * FreeMarketSim.range_of(gs, c.get("price_premium", [0.95, 1.12])) * rep_price_factor(gs, key)
		var recurring := FreeMarketSim.rf(gs) < float(c.get("recurring_chance", 0.4))
		var inst := FreeMarketSim.ri(gs, int(c.get("recurring_months", [3, 6])[0]), int(c.get("recurring_months", [3, 6])[1])) if recurring else 1
		if float(t.get("cash", 0.0)) < unit * qty * mini(inst, 2):
			continue
		var dl := int(TradeSim.transport_quote(gs, tid, qty)["days"]) + FreeMarketSim.ri(gs, int(c.get("single_deadline_days", [25, 50])[0]), int(c.get("single_deadline_days", [25, 50])[1]))
		create_request(gs, key, good, qty, unit, inst, dl)
	# Empresas NPC del pueblo: piden insumos o mercancía que tú produces.
	for b in NpcBusinessSim.npc_buildings(gs):
		if str(b.get("npc_state", "")) != NpcBusinessSim.STATE_OPEN or str(b["status"]) != "activo":
			continue
		var key := "npc:%d" % int(b["id"])
		var wants: Array = NpcBusinessSim.cfg().get("input_wants", {}).get(str(b["type"]), [])
		var options := wants.filter(func(g): return mine.has(str(g)))
		if options.is_empty() or FreeMarketSim.rf(gs) > float(c.get("local_request_chance_month", 0.25)) * rep_freq_factor(gs, key):
			continue
		var good: String = str(FreeMarketSim.pick(gs, options))
		var unit := reference_price(gs, key, good) * rep_price_factor(gs, key)
		var qty := clampf(roundf(BusinessSim.storage_cap(gs, b) * 0.25), float(c.get("min_qty", 5)), float(c.get("max_qty", 300)))
		var cash := maxf(0.0, float(b.get("reserve", 0.0)))
		qty = minf(qty, floorf(cash * 0.5 / maxf(0.01, unit)))
		if qty < float(c.get("min_qty", 5)):
			continue
		var recurring := FreeMarketSim.rf(gs) < float(c.get("recurring_chance", 0.4)) * 0.5
		create_request(gs, key, good, qty, unit, FreeMarketSim.ri(gs, 2, 4) if recurring else 1, FreeMarketSim.ri(gs, 10, 25))


# --- Consultas para la interfaz --------------------------------------------------------------------------

static func reputation_rows(gs) -> Array:
	var rows := []
	var keys: Dictionary = {}
	for k in gs.market.get("reputation", {}):
		keys[str(k)] = true
	for k in client_keys(gs):
		keys[str(k)] = true
	for key in keys:
		rows.append({"key": key, "name": client_name(gs, key), "rep": reputation(gs, key)})
	rows.sort_custom(func(a, b): return float(a["rep"]) > float(b["rep"]))
	return rows


static func status_label(s: String) -> String:
	return {"activo": "activo", "cumplido": "cumplido", "incumplido": "incumplido", "cancelado": "cancelado",
		"pendiente": "esperando respuesta", "aceptada": "aceptada", "rechazada": "rechazada"}.get(s, s)
