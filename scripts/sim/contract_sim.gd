class_name ContractSim
extends RefCounted
## Libre mercado — contratos de compraventa (únicos o recurrentes, a precio FIJO) entre el jugador
## y sus contrapartes. Ver docs/MERCADO_LIBRE.md.
## Contrapartes (clave): "town:<id>" (pueblo vecino con ruta), "npc:<id edificio>" (empresa NPC del
## pueblo), "gov" (gobierno del pueblo) e "import" (importación externa, solo para comprar).
## Dirección de cada contrato ("dir"):
##   - "venta":  el jugador vende. Entrega desde sus almacenes (primero la bodega de la plaza) y del
##               inventario de sus negocios; el comprador paga de su caja real.
##   - "compra": el jugador compra. El proveedor (empresa NPC con su stock, pueblo con ruta o la
##               importación) despacha cada N días; el bien llega al almacén elegido (WarehouseSim.add_to,
##               respetando la capacidad) y se paga al recibir.
## Modelo común: bien, cantidad por entrega, precio unitario fijo, frecuencia en días ("period"),
## número de entregas ("installments"), fecha de inicio ("start_day"), fin ("end_day"),
## penalidad del jugador ("penalty") y de la contraparte ("cp_penalty"), entrega automática ("auto").
##   - Bandeja (inbox): solicitudes de NPC. De venta, SOLO de bienes que produces; de compra,
##     proveedores que te ofrecen insumos que consumen tus negocios. Aceptar, rechazar o contraofertar.
##   - Propuestas (sent): el jugador propone compra o venta; la contraparte responde en 2–5 días
##     (sí, no o contraoferta de precio que el jugador acepta o rechaza).
##   - Reputación del jugador por cliente (0-100) y fiabilidad de cada proveedor (0-100).

const NON_GOODS := ["", "construccion", "credito", "servicio", "investigacion", "educacion", "transporte", "entrada", "alojamiento", "publicidad"]
const DIR_SELL := "venta"
const DIR_BUY := "compra"
const IMPORT_KEY := "import"
const PERIODS := [7, 15, 30, 60, 90]
const MODEL_VERSION := 2


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


static func dir_of(x: Dictionary) -> String:
	return str(x.get("dir", DIR_SELL))


static func is_buy(x: Dictionary) -> bool:
	return dir_of(x) == DIR_BUY


static func dir_label(d: String) -> String:
	return "Compra" if d == DIR_BUY else "Venta"


static func period_label(days: int) -> String:
	match days:
		7:
			return "semanal"
		15:
			return "quincenal"
		30:
			return "mensual"
		60:
			return "bimestral"
		90:
			return "trimestral"
	return "cada %d días" % days


# --- Migración (partidas anteriores: cuotas mensuales → frecuencia 30) ------------------------------

## Completa el modelo general en contratos, solicitudes y ofertas guardados antes. Idempotente.
static func migrate(gs) -> void:
	for k in contracts(gs):
		if int(k.get("v", 1)) >= MODEL_VERSION:
			continue
		var inst := maxi(1, int(k.get("installments", 1)))
		var period := maxi(1, int(k.get("period", 30)))
		k["dir"] = str(k.get("dir", DIR_SELL))
		k["period"] = period
		k["installments"] = inst
		if not k.has("start_day"):
			k["start_day"] = int(k.get("signed_day", k.get("next_due", 0)))
		if not k.has("end_day"):
			var left := maxi(0, inst - int(k.get("done", 0)) - int(k.get("failed", 0)) - 1)
			k["end_day"] = int(k.get("next_due", 0)) + period * left
		if not k.has("cp_penalty"):
			k["cp_penalty"] = float(k.get("penalty", 0.0))
		for key in ["cp_failed"]:
			if not k.has(key):
				k[key] = 0
		for key in ["debt", "cp_paid"]:
			if not k.has(key):
				k[key] = 0.0
		if not k.has("wid"):
			k["wid"] = WarehouseSim.PLAZA
		if not k.has("auto"):
			k["auto"] = inst > 1
		k["v"] = MODEL_VERSION
	for r in inbox(gs):
		if not r.has("dir"):
			r["dir"] = DIR_SELL
		if not r.has("period"):
			r["period"] = 30
		if not r.has("cp_penalty"):
			r["cp_penalty"] = float(r.get("penalty", 0.0))
	for o in sent(gs):
		if not o.has("dir"):
			o["dir"] = DIR_SELL
		if not o.has("period"):
			o["period"] = 30
		if not o.has("installments"):
			o["installments"] = 1


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


## Insumos que consumen tus negocios (recetas) con una estimación de lo que usan al mes.
static func player_needs(gs) -> Dictionary:
	var out := {}
	for b in gs.buildings:
		if not gs.owned_by_player(b) or str(b["status"]) in ["construccion", "cerrado"]:
			continue
		var def: Dictionary = gs.building_def(b)
		var ld: Dictionary = gs.level_def(b)
		# Comercios: la mercadería que venden y no producen ellos.
		var sd: Dictionary = ShopSim.shop_def_of(str(b.get("type", "")))
		for g in sd.get("sells", []):
			var sg := str(g)
			if is_tradeable(sg) and sg != str(def.get("product", "")):
				out[sg] = float(out.get(sg, 0.0)) + float(cfg().get("shop_need_month", 40))
		var ins: Dictionary = LogisticsSim.recipe_inputs(def, ld)
		if ins.is_empty():
			continue
		var per_day := float(ld.get("prod_per_worker", 1.0)) * float(maxi(1, int(ld.get("jobs", 1))))
		for g in ins:
			var good := str(g)
			if not is_tradeable(good):
				continue
			out[good] = float(out.get(good, 0.0)) + float(ins[g]) * per_day * 30.0 * 0.5
	return out


## Bienes almacenables que se pueden comprar o vender por contrato.
static func is_tradeable(good: String) -> bool:
	if good in NON_GOODS:
		return false
	if not (GameData.goods.has(good) or TradeSim.trade_goods().has(good)):
		return false
	return bool(GameData.goods.get(good, {}).get("storable", true))


static func tradeable_goods() -> Array:
	var d := {}
	for g in GameData.goods:
		if is_tradeable(str(g)):
			d[str(g)] = true
	for g in TradeSim.trade_goods():
		if is_tradeable(str(g)):
			d[str(g)] = true
	var out: Array = d.keys()
	out.sort()
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


## Precio de mercado de referencia de un bien (local o, si no se vende aquí, el del comercio).
static func market_ref(gs, good: String) -> float:
	var p := EconomySim.market_price(gs, good)
	if p <= 0.0:
		p = TradeSim.base_price(good) * float(gs.price_mult())
	return p


# --- Contrapartes ---------------------------------------------------------------------------------

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
		IMPORT_KEY:
			return "Importación externa"
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
		IMPORT_KEY:
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
static func _client_pay(gs, key: String, amount: float, ledger_key := "insumos") -> float:
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
			BusinessSim.ledger_add(b, ledger_key, paid)
		"gov":
			GovSim.add_treasury(gs, -paid)
	return paid


## La contraparte recibe dinero (penalidades o el pago de una compra).
## Lo que se paga a la importación externa sale del pueblo (salvo el arancel, que va al tesoro).
static func _client_receive(gs, key: String, amount: float, ledger_key := "") -> void:
	if amount <= 0.0:
		return
	match client_kind(key):
		"town":
			var t := TradeSim.town(gs, client_ref(key))
			if not t.is_empty():
				t["cash"] = float(t.get("cash", 0.0)) + amount
		"npc":
			var b: Dictionary = gs.get_building(int(client_ref(key)))
			if not b.is_empty():
				b["reserve"] = float(b.get("reserve", 0.0)) + amount
				if ledger_key != "":
					BusinessSim.ledger_add(b, ledger_key, amount)
			else:
				GovSim.add_treasury(gs, amount)
		IMPORT_KEY:
			var tariff := amount - amount / maxf(0.01, GovSim.import_mult(gs))
			if tariff > 0.0:
				GovSim.add_treasury(gs, tariff)
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


## Fiabilidad de un proveedor (0-100): baja cuando no entrega, sube al cumplir.
static func reliability(gs, key: String) -> float:
	return float(gs.market.get("reliability", {}).get(key, cfg().get("reliability_start", 80)))


static func _reliability_add(gs, key: String, delta: float) -> void:
	if not gs.market.has("reliability"):
		gs.market["reliability"] = {}
	var r: Dictionary = gs.market["reliability"]
	r[key] = clampf(reliability(gs, key) + delta, 0.0, 100.0)


## Clientes a los que puedes vender: pueblos con ruta, empresas NPC abiertas y el gobierno.
static func client_keys(gs) -> Array:
	var out := []
	for c in TradeSim.connected_towns(gs):
		out.append("town:%s" % str(c["town_id"]))
	for b in NpcBusinessSim.npc_buildings(gs):
		if str(b.get("npc_state", "")) == NpcBusinessSim.STATE_OPEN:
			out.append("npc:%d" % int(b["id"]))
	out.append("gov")
	return out


## Proveedores de un bien: empresas NPC que lo producen, pueblos con ruta que lo venden y,
## como último recurso, la importación externa.
static func supplier_keys(gs, good: String) -> Array:
	var out := []
	for b in NpcBusinessSim.npc_buildings(gs):
		if str(b.get("npc_state", "")) == NpcBusinessSim.STATE_OPEN and str(gs.building_def(b).get("product", "")) == good:
			out.append("npc:%d" % int(b["id"]))
	for c in TradeSim.connected_towns(gs):
		if TradeSim.sells_good(gs, str(c["town_id"]), good):
			out.append("town:%s" % str(c["town_id"]))
	if is_tradeable(good):
		out.append(IMPORT_KEY)
	return out


## Todas las contrapartes posibles para una dirección (sin filtrar por bien).
static func counterparty_keys(gs, d: String) -> Array:
	if d == DIR_SELL:
		return client_keys(gs)
	var out := []
	for b in NpcBusinessSim.npc_buildings(gs):
		if str(b.get("npc_state", "")) == NpcBusinessSim.STATE_OPEN:
			out.append("npc:%d" % int(b["id"]))
	for c in TradeSim.connected_towns(gs):
		out.append("town:%s" % str(c["town_id"]))
	out.append(IMPORT_KEY)
	return out


## ¿Puede este proveedor vender ese bien?
static func supplier_sells(gs, key: String, good: String) -> bool:
	match client_kind(key):
		"npc":
			var b: Dictionary = gs.get_building(int(client_ref(key)))
			return not b.is_empty() and NpcBusinessSim.is_npc(b) and str(gs.building_def(b).get("product", "")) == good
		"town":
			return not TradeSim.connection(gs, client_ref(key)).is_empty() and TradeSim.sells_good(gs, client_ref(key), good)
		IMPORT_KEY:
			return is_tradeable(good)
	return false


## Existencias reales del proveedor para despachar hoy.
static func supplier_stock(gs, key: String, good: String) -> float:
	match client_kind(key):
		"npc":
			return float(gs.get_building(int(client_ref(key))).get("inventory", {}).get(good, 0.0))
		"town":
			var row: Dictionary = TradeSim.town(gs, client_ref(key)).get("goods", {}).get(good, {})
			if not bool(row.get("sells", false)):
				return 0.0
			return maxf(0.0, float(row.get("supply", 0.0)) - float(row.get("scar", 0.0)))
		IMPORT_KEY:
			return 1.0e9
	return 0.0


## Cuánto puede comprometerse a entregar por período (stock + producción estimada).
static func supplier_capacity(gs, key: String, good: String, period: int) -> float:
	match client_kind(key):
		"npc":
			var b: Dictionary = gs.get_building(int(client_ref(key)))
			var per_day := BusinessSim.storage_cap(gs, b) / 20.0
			return supplier_stock(gs, key, good) + per_day * float(period) * 0.5
		"town":
			var row: Dictionary = TradeSim.town(gs, client_ref(key)).get("goods", {}).get(good, {})
			return float(row.get("supply", 0.0)) * float(period) / 30.0 * 0.5
		IMPORT_KEY:
			return 1.0e9
	return 0.0


## Precio de referencia por unidad. Venta: lo que el cliente pagaría hoy. Compra: lo que cobra el proveedor.
static func reference_price(gs, key: String, good: String, qty := 1.0, d := DIR_SELL) -> float:
	if d == DIR_BUY:
		return buy_reference_price(gs, key, good, qty)
	match client_kind(key):
		"town":
			var p := TradeSim.export_price(gs, client_ref(key), good, qty * 0.5)
			return p if p > 0.0 else EconomySim.market_price(gs, good)
		"npc":
			return EconomySim.market_price(gs, good) * float(cfg().get("local_wholesale", 0.75))
		"gov":
			return GovPlansSim.material_unit_price(gs, good) * float(cfg().get("gov_material_price", 0.9))
	return EconomySim.market_price(gs, good)


static func buy_reference_price(gs, key: String, good: String, qty := 1.0) -> float:
	match client_kind(key):
		"npc":
			var b: Dictionary = gs.get_building(int(client_ref(key)))
			var p := maxf(market_ref(gs, good), float(b.get("price", 0.0)))
			return p * float(cfg().get("npc_supply_wholesale", 0.9))
		"town":
			var p2 := TradeSim.import_price(gs, client_ref(key), good, qty * 0.5)
			return p2 if p2 > 0.0 else market_ref(gs, good) * 1.2
		IMPORT_KEY:
			return market_ref(gs, good) * float(cfg().get("import_premium", 1.4)) * GovSim.import_mult(gs)
	return market_ref(gs, good)


## Flete por entrega de una compra (lo paga el jugador al despachar; solo desde otro pueblo).
static func freight_of(gs, key: String, qty: float) -> Dictionary:
	if client_kind(key) == "town":
		return TradeSim.transport_quote(gs, client_ref(key), qty)
	if client_kind(key) == IMPORT_KEY:
		return {"cost": 0.0, "days": int(cfg().get("import_days", 7)), "mode": "", "trips": 0}
	return {"cost": 0.0, "days": 0, "mode": "", "trips": 0}


## Estimado del total del contrato: {goods, freight, total}.
static func estimate_total(gs, d: String, key: String, qty: float, unit_price: float, installments: int) -> Dictionary:
	var inst := maxi(1, installments)
	var goods := qty * unit_price * inst
	var freight := 0.0
	if client_kind(key) == "town" and not TradeSim.connection(gs, client_ref(key)).is_empty():
		freight = float(TradeSim.transport_quote(gs, client_ref(key), qty)["cost"]) * inst
	return {"goods": goods, "freight": freight, "total": goods + freight if d == DIR_BUY else goods - freight}


static func installments_until(start_day: int, end_day: int, period: int) -> int:
	return maxi(1, int(floorf(float(end_day - start_day) / float(maxi(1, period)))) + 1)


# --- Solicitudes entrantes (bandeja) -------------------------------------------------------------------

## Solicitud de VENTA (un cliente te pide un bien que produces). Devuelve la solicitud o {}.
static func create_request(gs, key: String, good: String, qty: float, unit_price: float, installments := 1, deadline_days := 30, plan_id := -1, period := 30) -> Dictionary:
	if not player_goods(gs).has(good) or qty < 1.0 or unit_price <= 0.0:
		return {}
	if inbox(gs).size() >= int(cfg().get("max_inbox", 6)):
		return {}
	var total := unit_price * qty * installments
	var pen := snappedf(unit_price * floorf(qty) * float(cfg().get("penalty_share", 0.2)), 0.01)
	var r := {"id": FreeMarketSim.next_id(gs), "dir": DIR_SELL, "client": key, "client_name": client_name(gs, key), "good": good,
		"qty": floorf(qty), "unit_price": snappedf(unit_price, 0.01), "installments": maxi(1, installments), "period": maxi(1, period),
		"deadline_days": deadline_days, "penalty": pen, "cp_penalty": pen,
		"expires_day": gs.today() + int(cfg().get("inbox_days", 15)), "day": gs.today(), "plan_id": plan_id, "total": total}
	gs.market["inbox"].append(r)
	var when := "entrega única en %d días" % deadline_days if installments <= 1 else "entrega %s por %d entregas" % [period_label(period), installments]
	gs.notify("Solicitud de %s: %d de %s a %s c/u (%s). Acepta, rechaza o contraoferta en «Contratos»." % [r["client_name"], int(r["qty"]), TradeSim.good_label(good), Fmt.money2(float(r["unit_price"])), when], "negocio")
	return r


## Oferta de un proveedor NPC para VENDERTE un bien (insumo de tus negocios). Devuelve la oferta o {}.
static func create_supply_offer(gs, key: String, good: String, qty: float, unit_price: float, installments := 4, period := 30) -> Dictionary:
	if not supplier_sells(gs, key, good) or qty < 1.0 or unit_price <= 0.0:
		return {}
	if inbox(gs).size() >= int(cfg().get("max_inbox", 6)):
		return {}
	var pen := snappedf(unit_price * floorf(qty) * float(cfg().get("penalty_share", 0.2)), 0.01)
	var r := {"id": FreeMarketSim.next_id(gs), "dir": DIR_BUY, "client": key, "client_name": client_name(gs, key), "good": good,
		"qty": floorf(qty), "unit_price": snappedf(unit_price, 0.01), "installments": maxi(1, installments), "period": maxi(1, period),
		"deadline_days": period, "penalty": pen, "cp_penalty": pen, "wid": WarehouseSim.PLAZA,
		"expires_day": gs.today() + int(cfg().get("inbox_days", 15)), "day": gs.today(), "plan_id": -1,
		"total": unit_price * floorf(qty) * maxi(1, installments)}
	gs.market["inbox"].append(r)
	gs.notify("%s te ofrece venderte %d de %s a %s c/u, %s por %d entregas. Revísalo en «Contratos»." % [r["client_name"], int(r["qty"]), TradeSim.good_label(good), Fmt.money2(float(r["unit_price"])), period_label(period), int(r["installments"])], "negocio")
	return r


static func accept_request(gs, id: int, wid := -1) -> String:
	var r := find(inbox(gs), id)
	if r.is_empty():
		return "La solicitud ya no está."
	if not client_exists(gs, str(r["client"])):
		inbox(gs).erase(r)
		return "El cliente ya no existe."
	inbox(gs).erase(r)
	if wid >= 0:
		r["wid"] = wid
	var k := _sign(gs, r, "solicitud")
	var rec := "" if int(k["installments"]) <= 1 else " %s por %d entregas" % [period_label(int(k["period"])), int(k["installments"])]
	if is_buy(k):
		return "Contrato de compra firmado con %s: %d de %s%s." % [k["client_name"], int(k["qty"]), TradeSim.good_label(str(k["good"])), rec]
	return "Contrato firmado con %s: %d de %s%s." % [k["client_name"], int(k["qty"]), TradeSim.good_label(str(k["good"])), rec]


static func reject_request(gs, id: int, silent := false) -> String:
	var r := find(inbox(gs), id)
	if r.is_empty():
		return "La solicitud ya no está."
	inbox(gs).erase(r)
	if is_buy(r):
		return "" if silent else "Rechazaste la oferta de %s." % r["client_name"]
	_rep_add(gs, str(r["client"]), -float(cfg().get("rep_reject", 1)))
	_covered_by_others(gs, r)
	_release_plan(gs, int(r.get("plan_id", -1)), str(r["good"]))
	return "" if silent else "Rechazaste la solicitud de %s." % r["client_name"]


## Contraofertar una solicitud de la bandeja: se vuelve una propuesta tuya con otro precio y el
## cliente (o proveedor) responde en unos días.
static func counter_request(gs, id: int, unit_price: float) -> String:
	var r := find(inbox(gs), id)
	if r.is_empty():
		return "La solicitud ya no está."
	if unit_price <= 0.0:
		return "Precio inválido."
	if not client_exists(gs, str(r["client"])):
		inbox(gs).erase(r)
		return "El cliente ya no existe."
	inbox(gs).erase(r)
	var days: Array = cfg().get("offer_reply_days", [2, 5])
	var o := {"id": FreeMarketSim.next_id(gs), "dir": dir_of(r), "client": str(r["client"]), "client_name": str(r["client_name"]),
		"good": str(r["good"]), "qty": float(r["qty"]), "unit_price": snappedf(unit_price, 0.01), "period": int(r.get("period", 30)),
		"installments": int(r.get("installments", 1)), "deadline_days": int(r.get("deadline_days", 30)), "auto": true,
		"wid": int(r.get("wid", WarehouseSim.PLAZA)), "start_in": int(r.get("period", 30)) if int(r.get("installments", 1)) > 1 else int(r.get("deadline_days", 30)),
		"plan_id": int(r.get("plan_id", -1)), "orig_price": float(r["unit_price"]), "from_request": true,
		"day": gs.today(), "reply_day": gs.today() + FreeMarketSim.ri(gs, int(days[0]), int(days[1])), "status": "pendiente", "reason": ""}
	gs.market["sent"].append(o)
	return ""


## La demanda que no cubres la cubren otros proveedores (otros pueblos o importación).
static func _covered_by_others(gs, r: Dictionary) -> void:
	FreeMarketSim.stat(gs, "covered_by_others", float(r["qty"]) * float(r.get("installments", 1)))
	FreeMarketSim.log_event(gs, "%s compró %d de %s a otro proveedor." % [r["client_name"], int(r["qty"]), TradeSim.good_label(str(r["good"]))])


static func _release_plan(gs, plan_id: int, good: String) -> void:
	if plan_id < 0:
		return
	var p := GovPlansSim.plan(gs, plan_id)
	if not p.is_empty():
		p.get("materials_pending", {}).erase(good)
		if p.get("materials_pending", {}).is_empty() and str(p["status"]) == "materiales":
			GovPlansSim._start_build(gs, p)


## Firma un contrato con el modelo general.
static func _sign(gs, r: Dictionary, source: String) -> Dictionary:
	var inst := maxi(1, int(r.get("installments", 1)))
	var period := maxi(1, int(r.get("period", 30)))
	var today: int = gs.today()
	var first: int
	if r.has("start_in"):
		first = today + maxi(0, int(r["start_in"]))
	elif inst <= 1:
		first = today + int(r.get("deadline_days", 30))
	else:
		first = today + period
	var pen := float(r.get("penalty", float(r["unit_price"]) * float(r["qty"]) * float(cfg().get("penalty_share", 0.2))))
	var k := {"id": FreeMarketSim.next_id(gs), "v": MODEL_VERSION, "dir": str(r.get("dir", DIR_SELL)),
		"client": str(r["client"]), "client_name": str(r["client_name"]), "good": str(r["good"]),
		"qty": float(r["qty"]), "unit_price": float(r["unit_price"]), "installments": inst, "period": period,
		"start_day": first, "end_day": first + period * (inst - 1), "done": 0, "failed": 0, "cp_failed": 0,
		"next_due": first, "penalty": pen, "cp_penalty": float(r.get("cp_penalty", pen)),
		"auto": bool(r.get("auto", inst > 1 or str(r.get("dir", DIR_SELL)) == DIR_BUY)), "status": "activo", "source": source,
		"signed_day": today, "paid": 0.0, "owed": 0.0, "debt": 0.0, "cp_paid": 0.0, "plan_id": int(r.get("plan_id", -1)),
		"delivered": 0.0, "wid": int(r.get("wid", WarehouseSim.PLAZA))}
	gs.market["contracts"].append(k)
	FreeMarketSim.stat(gs, "contracts_signed", 1.0)
	return k


# --- Propuestas del jugador (compra o venta, única o recurrente) ----------------------------------------------

## opts: period (días), installments (entregas), end_day (alternativa a installments),
## start_in (días hasta la primera entrega), auto (bool), wid (almacén destino de una compra).
static func proposal_block_reason(gs, d: String, key: String, good: String, qty: float, unit_price: float, opts := {}) -> String:
	if not client_exists(gs, key):
		return "Esa contraparte no existe."
	if client_kind(key) == "town" and TradeSim.connection(gs, client_ref(key)).is_empty():
		return "Necesitas una ruta comercial con ese pueblo."
	if qty < 1.0 or unit_price <= 0.0:
		return "Cantidad o precio inválido."
	if int(opts.get("period", 30)) < 1 or int(opts.get("installments", 1)) < 1:
		return "Frecuencia o número de entregas inválido."
	if d == DIR_BUY:
		if not supplier_sells(gs, key, good):
			return "%s no vende %s." % [client_name(gs, key), TradeSim.good_label(good)]
		var wid := int(opts.get("wid", WarehouseSim.PLAZA))
		if not WarehouseSim.exists(gs, wid):
			return "Ese almacén no existe."
		if WarehouseSim.capacity_of(gs, wid) < qty:
			return "%s no tiene capacidad para %d por entrega." % [WarehouseSim.label_of(gs, wid), int(qty)]
	else:
		if client_kind(key) == IMPORT_KEY:
			return "A la importación externa no se le vende."
		if not player_goods(gs).has(good) and available(gs, good) < qty:
			return "No produces %s ni tienes %d en existencias." % [TradeSim.good_label(good), int(qty)]
	for o in sent(gs):
		if str(o["status"]) in ["pendiente", "contraoferta"] and str(o["client"]) == key and str(o["good"]) == good and dir_of(o) == d:
			return "Ya tienes una propuesta pendiente de ese bien con esa contraparte."
	return ""


static func propose(gs, d: String, key: String, good: String, qty: float, unit_price: float, opts := {}) -> String:
	qty = floorf(qty)
	var why := proposal_block_reason(gs, d, key, good, qty, unit_price, opts)
	if why != "":
		return why
	var period := maxi(1, int(opts.get("period", 30)))
	var start_in := maxi(0, int(opts.get("start_in", period)))
	var inst := maxi(1, int(opts.get("installments", 1)))
	if opts.has("end_day"):
		inst = installments_until(gs.today() + start_in, int(opts["end_day"]), period)
	var days: Array = cfg().get("offer_reply_days", [2, 5])
	var o := {"id": FreeMarketSim.next_id(gs), "dir": d, "client": key, "client_name": client_name(gs, key), "good": good, "qty": qty,
		"unit_price": snappedf(unit_price, 0.01), "period": period, "installments": inst, "start_in": start_in,
		"auto": bool(opts.get("auto", true)), "wid": int(opts.get("wid", WarehouseSim.PLAZA)), "plan_id": -1,
		"day": gs.today(), "reply_day": gs.today() + FreeMarketSim.ri(gs, int(days[0]), int(days[1])),
		"status": "pendiente", "reason": ""}
	gs.market["sent"].append(o)
	return ""


# Compatibilidad: oferta de venta única (API anterior).
static func offer_block_reason(gs, key: String, good: String, qty: float, unit_price: float) -> String:
	return proposal_block_reason(gs, DIR_SELL, key, good, qty, unit_price, {})


static func send_offer(gs, key: String, good: String, qty: float, unit_price: float) -> String:
	qty = floorf(qty)
	var why := offer_block_reason(gs, key, good, qty, unit_price)
	if why != "":
		return why
	var days: Array = cfg().get("offer_reply_days", [2, 5])
	var o := {"id": FreeMarketSim.next_id(gs), "dir": DIR_SELL, "client": key, "client_name": client_name(gs, key), "good": good, "qty": qty,
		"unit_price": snappedf(unit_price, 0.01), "period": 30, "installments": 1, "plan_id": -1,
		"day": gs.today(), "reply_day": gs.today() + FreeMarketSim.ri(gs, int(days[0]), int(days[1])),
		"status": "pendiente", "reason": ""}
	gs.market["sent"].append(o)
	return ""


## Descuento que pide la contraparte por un compromiso largo (volumen asegurado).
static func _duration_factor(inst: int) -> float:
	return 1.0 - float(cfg().get("duration_discount", 0.01)) * float(mini(maxi(0, inst - 1), 10))


## Decisión de la contraparte: {"yes": bool, "reason": String, "max"/"min": límite de precio, "counter": precio o 0}.
static func evaluate_offer(gs, o: Dictionary) -> Dictionary:
	if is_buy(o):
		return _evaluate_supply(gs, o)
	var key := str(o["client"])
	var good := str(o["good"])
	var qty := float(o["qty"])
	var price := float(o["unit_price"])
	var inst := maxi(1, int(o.get("installments", 1)))
	if not client_exists(gs, key):
		return {"yes": false, "reason": "el cliente ya no existe", "max": 0.0, "counter": 0.0}
	var need := 1.0
	var ref := reference_price(gs, key, good, qty)
	match client_kind(key):
		"town":
			var t := TradeSim.town(gs, client_ref(key))
			var row: Dictionary = t.get("goods", {}).get(good, {})
			if row.is_empty():
				return {"yes": false, "reason": "allá no se usa ese bien", "max": 0.0, "counter": 0.0}
			var room := float(row.get("demand", 0.0)) * 2.0 - float(row.get("sat", 0.0))
			if inst > 1:
				room = float(row.get("demand", 0.0)) * float(o.get("period", 30)) / 30.0 * 1.5
			if room < qty * 0.5:
				return {"yes": false, "reason": "ya están abastecidos", "max": 0.0, "counter": 0.0}
			need = 1.1 if t.get("demands", []).has(good) else (0.8 if bool(row.get("sells", false)) else 0.95)
			# Lejos, la entrega tarda más: pagan un poco menos.
			need *= clampf(1.05 - float(t.get("distance", 50.0)) / 1000.0, 0.85, 1.05)
		"npc":
			var b: Dictionary = gs.get_building(int(client_ref(key)))
			var wants: Array = NpcBusinessSim.cfg().get("input_wants", {}).get(str(b["type"]), [])
			var product := str(gs.building_def(b).get("product", ""))
			if not wants.has(good) and good != product:
				return {"yes": false, "reason": "no lo necesita", "max": 0.0, "counter": 0.0}
			need = 1.1
		"gov":
			var wanted := int(o.get("plan_id", -1)) >= 0
			for p in GovPlansSim.plans(gs):
				if str(p["status"]) in ["materiales", "en_obra", "licitacion"] and GameData.level_def(str(p["type"]), 1).get("materials", {}).has(good):
					wanted = true
			if not wanted:
				return {"yes": false, "reason": "el gobierno no necesita ese bien ahora", "max": 0.0, "counter": 0.0}
			need = 1.05
		_:
			return {"yes": false, "reason": "no compra", "max": 0.0, "counter": 0.0}
	var max_price := ref * need * rep_price_factor(gs, key) * _duration_factor(inst)
	if int(o.get("plan_id", -1)) >= 0 or bool(o.get("from_request", false)):
		max_price = maxf(max_price, float(o.get("orig_price", 0.0)))
	if client_cash(gs, key) < price * qty * mini(inst, 2):
		if client_cash(gs, key) >= minf(price, max_price) * qty * mini(inst, 2) and price > max_price:
			pass
		else:
			return {"yes": false, "reason": "no tiene con qué pagar", "max": max_price, "counter": 0.0}
	if price > max_price:
		if price <= max_price / float(cfg().get("counter_ratio", 0.85)):
			return {"yes": false, "reason": "contraoferta", "max": max_price, "counter": snappedf(max_price, 0.01)}
		return {"yes": false, "reason": "el precio es alto (pagarían hasta %s)" % Fmt.money2(max_price), "max": max_price, "counter": 0.0}
	return {"yes": true, "reason": "", "max": max_price, "counter": 0.0}


## Decisión de un proveedor ante una propuesta de COMPRA del jugador.
static func _evaluate_supply(gs, o: Dictionary) -> Dictionary:
	var key := str(o["client"])
	var good := str(o["good"])
	var qty := float(o["qty"])
	var price := float(o["unit_price"])
	var inst := maxi(1, int(o.get("installments", 1)))
	var period := maxi(1, int(o.get("period", 30)))
	if not client_exists(gs, key) or not supplier_sells(gs, key, good):
		return {"yes": false, "reason": "ya no vende ese bien", "min": 0.0, "counter": 0.0}
	var cap := supplier_capacity(gs, key, good, period)
	if cap < qty:
		return {"yes": false, "reason": "no produce tanto (hasta %d %s)" % [int(cap), period_label(period)], "min": 0.0, "counter": 0.0}
	var ref := buy_reference_price(gs, key, good, qty)
	var min_price := ref * _duration_factor(inst)
	if client_kind(key) != IMPORT_KEY:
		min_price *= 2.0 - rep_price_factor(gs, key)
	if client_kind(key) == "npc":
		var b: Dictionary = gs.get_building(int(client_ref(key)))
		if float(b.get("reserve", 0.0)) < 60.0 * float(gs.price_mult()):
			min_price *= 0.95   # Con la caja apretada vende más barato para asegurar ventas.
	if bool(o.get("from_request", false)):
		min_price = minf(min_price, float(o.get("orig_price", min_price)))
	if gs.money < price * qty:
		return {"yes": false, "reason": "dudan de que puedas pagar", "min": min_price, "counter": 0.0}
	if price < min_price:
		if price >= min_price * float(cfg().get("counter_ratio", 0.85)):
			return {"yes": false, "reason": "contraoferta", "min": min_price, "counter": snappedf(min_price, 0.01)}
		return {"yes": false, "reason": "el precio es bajo (venden desde %s)" % Fmt.money2(min_price), "min": min_price, "counter": 0.0}
	return {"yes": true, "reason": "", "min": min_price, "counter": 0.0}


static func _sign_offer(gs, o: Dictionary, price: float) -> Dictionary:
	var inst := maxi(1, int(o.get("installments", 1)))
	var r := {"dir": dir_of(o), "client": o["client"], "client_name": o["client_name"], "good": o["good"], "qty": o["qty"],
		"unit_price": price, "installments": inst, "period": int(o.get("period", 30)), "auto": bool(o.get("auto", inst > 1)),
		"wid": int(o.get("wid", WarehouseSim.PLAZA)), "plan_id": int(o.get("plan_id", -1)),
		"penalty": price * float(o["qty"]) * float(cfg().get("penalty_share", 0.2))}
	if o.has("start_in"):
		r["start_in"] = int(o["start_in"])
	elif inst <= 1:
		var days := 30
		if client_kind(str(o["client"])) == "town":
			days = int(TradeSim.transport_quote(gs, client_ref(str(o["client"])), float(o["qty"]))["days"]) + 20
		r["deadline_days"] = days
	if not is_buy(o) and inst <= 1 and not o.has("start_in"):
		r["auto"] = false
	var k := _sign(gs, r, "oferta")
	o["contract_id"] = int(k["id"])
	return k


static func _resolve_offers(gs) -> void:
	for o in sent(gs):
		if str(o["status"]) == "contraoferta" and int(o.get("counter_expires", 0)) < gs.today():
			o["status"] = "vencida"
			_release_plan(gs, int(o.get("plan_id", -1)), str(o["good"]))
			continue
		if str(o["status"]) != "pendiente" or int(o["reply_day"]) > gs.today():
			continue
		var ev := evaluate_offer(gs, o)
		if bool(ev["yes"]):
			o["status"] = "aceptada"
			var k := _sign_offer(gs, o, float(o["unit_price"]))
			gs.notify("%s aceptó tu propuesta de %s: %d de %s a %s c/u%s. Primera entrega el %s." % [o["client_name"], dir_label(dir_of(o)).to_lower(), int(o["qty"]), TradeSim.good_label(str(o["good"])), Fmt.money2(float(o["unit_price"])), "" if int(k["installments"]) <= 1 else ", %s por %d entregas" % [period_label(int(k["period"])), int(k["installments"])], TimeManager.date_from_day(int(k["next_due"]), TimeManager.start_year())], "negocio")
		elif float(ev.get("counter", 0.0)) > 0.0:
			o["status"] = "contraoferta"
			o["counter_price"] = float(ev["counter"])
			o["counter_expires"] = gs.today() + int(cfg().get("inbox_days", 15))
			o["reason"] = "contraoferta a %s c/u" % Fmt.money2(float(ev["counter"]))
			gs.notify("%s responde a tu propuesta de %s con una contraoferta: %s c/u. Acéptala o recházala en «Contratos»." % [o["client_name"], TradeSim.good_label(str(o["good"])), Fmt.money2(float(ev["counter"]))], "negocio")
		else:
			o["status"] = "rechazada"
			o["reason"] = str(ev["reason"])
			_release_plan(gs, int(o.get("plan_id", -1)), str(o["good"]))
			gs.notify("%s rechazó tu propuesta de %s: %s." % [o["client_name"], TradeSim.good_label(str(o["good"])), o["reason"]], "negocio")
	var list := sent(gs)
	while list.size() > 30:
		var drop := -1
		for i in range(list.size()):
			if not str(list[i]["status"]) in ["pendiente", "contraoferta"]:
				drop = i
				break
		if drop < 0:
			break
		list.remove_at(drop)


static func accept_counter(gs, id: int) -> String:
	var o := find(sent(gs), id)
	if o.is_empty() or str(o["status"]) != "contraoferta":
		return "No hay contraoferta pendiente."
	if not client_exists(gs, str(o["client"])):
		o["status"] = "rechazada"
		return "La contraparte ya no existe."
	o["status"] = "aceptada"
	o["unit_price"] = float(o["counter_price"])
	var k := _sign_offer(gs, o, float(o["counter_price"]))
	return "Contrato firmado con %s a %s c/u (%d entregas)." % [k["client_name"], Fmt.money2(float(k["unit_price"])), int(k["installments"])]


static func reject_counter(gs, id: int) -> String:
	var o := find(sent(gs), id)
	if o.is_empty() or str(o["status"]) != "contraoferta":
		return "No hay contraoferta pendiente."
	o["status"] = "rechazada"
	o["reason"] = "rechazaste la contraoferta"
	_release_plan(gs, int(o.get("plan_id", -1)), str(o["good"]))
	if bool(o.get("from_request", false)) and not is_buy(o):
		_covered_by_others(gs, o)
	return "Rechazaste la contraoferta de %s." % o["client_name"]


# --- Entregas --------------------------------------------------------------------------------------------

static func delivery_window(k: Dictionary) -> int:
	return clampi(int(k.get("period", 30)) / 2, 1, 15)


static func dest_wid(gs, k: Dictionary) -> int:
	var wid := int(k.get("wid", WarehouseSim.PLAZA))
	return wid if WarehouseSim.exists(gs, wid) else WarehouseSim.PLAZA


## Unidades de compras por contrato en camino hacia un almacén (reservan espacio).
static func incoming_to(gs, wid: int) -> float:
	var n := 0.0
	for s in gs.market.get("shipments", []):
		if str(s.get("dir", DIR_SELL)) == DIR_BUY and int(s.get("wid", 0)) == wid:
			n += float(s["qty"])
	return n


## ¿Puede el jugador recibir y pagar una entrega de compra? "" = sí.
static func player_buy_block(gs, k: Dictionary) -> String:
	var qty := float(k["qty"])
	var value := qty * float(k["unit_price"])
	var freight := float(freight_of(gs, str(k["client"]), qty)["cost"])
	if client_kind(str(k["client"])) == "town" and TradeSim.connection(gs, client_ref(str(k["client"]))).is_empty():
		return "Necesitas la ruta comercial con %s." % k["client_name"]
	if gs.money < value + freight:
		return "No tienes %s para pagar la entrega%s." % [Fmt.money(value + freight), " y el flete" if freight > 0.0 else ""]
	var wid := dest_wid(gs, k)
	var room := WarehouseSim.free_in(gs, wid) - incoming_to(gs, wid)
	if room < qty:
		return "No hay espacio en %s (libre %d, llegan %d)." % [WarehouseSim.label_of(gs, wid), int(maxf(0.0, room)), int(qty)]
	return ""


static func deliver_block_reason(gs, k: Dictionary) -> String:
	if str(k["status"]) != "activo":
		return "El contrato no está activo."
	if int(k["installments"]) > 1 and gs.today() < int(k["next_due"]) - delivery_window(k):
		return "Aún no toca la entrega (desde el %s)." % TimeManager.date_from_day(int(k["next_due"]) - delivery_window(k), TimeManager.start_year())
	var key := str(k["client"])
	if not client_exists(gs, key):
		return "La contraparte ya no existe."
	var qty := float(k["qty"])
	if is_buy(k):
		var pwhy := player_buy_block(gs, k)
		if pwhy != "":
			return pwhy
		var st := supplier_stock(gs, key, str(k["good"]))
		if st < qty:
			return "%s solo tiene %d de %s ahora." % [k["client_name"], int(st), TradeSim.good_label(str(k["good"]))]
		return ""
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


## Entrega (venta) o recibe (compra) una cuota del contrato ahora. Devuelve "" si salió bien.
static func deliver(gs, id: int) -> String:
	var k := find(contracts(gs), id)
	if k.is_empty():
		return "Contrato no encontrado."
	var why := deliver_block_reason(gs, k)
	if why != "":
		return why
	if is_buy(k):
		_dispatch_purchase(gs, k)
		return ""
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
	_advance(k)
	_rep_add(gs, key, float(cfg().get("rep_success", 4)))
	FreeMarketSim.stat(gs, "delivered_value", value)
	return ""


static func _advance(k: Dictionary) -> void:
	k["next_due"] = int(k["next_due"]) + int(k.get("period", 30))
	if str(k["status"]) == "activo" and int(k["done"]) + int(k["failed"]) + int(k.get("cp_failed", 0)) >= int(k["installments"]):
		k["status"] = "cumplido"


## El proveedor despacha una entrega de compra (ya verificado: stock, dinero y espacio).
static func _dispatch_purchase(gs, k: Dictionary) -> void:
	var key := str(k["client"])
	var good := str(k["good"])
	var qty := float(k["qty"])
	var value := qty * float(k["unit_price"])
	var wid := dest_wid(gs, k)
	match client_kind(key):
		"npc":
			var b: Dictionary = gs.get_building(int(client_ref(key)))
			var inv: Dictionary = b["inventory"]
			inv[good] = float(inv.get(good, 0.0)) - qty
			var acc := WarehouseSim.add_to(gs, wid, good, qty)
			_pay_supplier(gs, k, acc * float(k["unit_price"]))
			k["delivered"] = float(k.get("delivered", 0.0)) + acc
		"town":
			var tid := client_ref(key)
			var tq := TradeSim.transport_quote(gs, tid, qty)
			TradeSim._pay_transport(gs, tid, {"transport": float(tq["cost"]), "mode": str(tq["mode"]), "days": int(tq["days"]), "trips": int(tq["trips"])})
			var row: Dictionary = TradeSim.town(gs, tid).get("goods", {}).get(good, {})
			if not row.is_empty():
				row["scar"] = float(row.get("scar", 0.0)) + qty
			gs.market["shipments"].append({"id": FreeMarketSim.next_id(gs), "dir": DIR_BUY, "contract_id": int(k["id"]), "client": key,
				"good": good, "qty": qty, "value": value, "wid": wid, "arrive_day": gs.today() + int(tq["days"])})
		IMPORT_KEY:
			gs.market["shipments"].append({"id": FreeMarketSim.next_id(gs), "dir": DIR_BUY, "contract_id": int(k["id"]), "client": key,
				"good": good, "qty": qty, "value": value, "wid": wid, "arrive_day": gs.today() + int(cfg().get("import_days", 7))})
	k["done"] = int(k["done"]) + 1
	_advance(k)
	_reliability_add(gs, key, float(cfg().get("reliability_success", 2)))
	FreeMarketSim.stat(gs, "purchased_value", value)


## El jugador paga una entrega recibida. Lo que no alcance queda como deuda (se paga cada mes).
static func _pay_supplier(gs, k: Dictionary, value: float) -> void:
	if value <= 0.0:
		return
	var paid := minf(value, maxf(0.0, gs.money))
	if paid > 0.0:
		gs.add_money(-paid)
		gs.add_counter("contract_purchases", paid)
		_client_receive(gs, str(k["client"]), paid, "ventas")
		if client_kind(str(k["client"])) != "npc":
			gs.add_counter("imports", paid)
			EconomySim.record_value(gs, "imports", paid)
	k["paid"] = float(k.get("paid", 0.0)) + paid
	k["debt"] = float(k.get("debt", 0.0)) + value - paid


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
		if str(s.get("dir", DIR_SELL)) == DIR_BUY:
			if k.is_empty():
				k = {"client": s["client"], "paid": 0.0, "debt": 0.0, "unit_price": float(s["value"]) / maxf(1.0, float(s["qty"]))}
			var good := str(s["good"])
			var qty := float(s["qty"])
			var acc := WarehouseSim.add_to(gs, int(s.get("wid", 0)), good, qty)
			if acc < qty:
				acc += WarehouseSim.add(gs, good, qty - acc)
			if qty - acc > 0.5:
				gs.notify("Llegó la compra de %s pero no cabía todo: %d de %s regresaron al proveedor (no se pagan)." % [TradeSim.good_label(good), int(qty - acc), client_name(gs, str(s["client"]))], "negocio")
			_pay_supplier(gs, k, acc * float(k["unit_price"]))
			k["delivered"] = float(k.get("delivered", 0.0)) + acc
			continue
		if k.is_empty():
			k = {"client": s["client"], "paid": 0.0, "owed": 0.0}
		_collect(gs, k, float(s["value"]))
		gs.add_counter("exports", float(s["value"]))
		EconomySim.record_value(gs, "exports", float(s["value"]))


## Incumplimiento del JUGADOR en una cuota: paga la penalidad a la contraparte y baja la reputación.
static func _fail(gs, k: Dictionary, why := "") -> void:
	var key := str(k["client"])
	var pen := float(k.get("penalty", 0.0))
	if pen > 0.0:
		gs.add_money(-pen)
		_client_receive(gs, key, pen)
	_rep_add(gs, key, -float(cfg().get("rep_fail", 12)))
	k["failed"] = int(k["failed"]) + 1
	FreeMarketSim.stat(gs, "penalties", pen)
	var single := int(k["installments"]) <= 1
	k["next_due"] = int(k["next_due"]) + int(k.get("period", 30))
	if single or int(k["failed"]) >= 2:
		k["status"] = "incumplido"
		k["breached_by"] = "jugador"
	elif int(k["done"]) + int(k["failed"]) + int(k.get("cp_failed", 0)) >= int(k["installments"]):
		k["status"] = "cumplido"
	gs.notify("Incumpliste %s con %s%s: pagaste %s de penalidad y bajó tu reputación (%d/100).%s" % ["el contrato" if single else "una entrega", k["client_name"], " (%s)" % why.trim_suffix(".") if why != "" else "", Fmt.money(pen), int(reputation(gs, key)), " Contrato cancelado." if str(k["status"]) == "incumplido" and not single else ""], "jugador")
	_release_plan(gs, int(k.get("plan_id", -1)), str(k["good"]))


## Incumplimiento del PROVEEDOR (sin stock): te paga su penalidad y baja su fiabilidad.
static func _supplier_fail(gs, k: Dictionary) -> void:
	var key := str(k["client"])
	var pen := float(k.get("cp_penalty", k.get("penalty", 0.0)))
	var paid := 0.0
	if client_kind(key) == "npc":
		var b: Dictionary = gs.get_building(int(client_ref(key)))
		paid = NpcBusinessSim._spend(gs, b, pen, "penalidades")
	else:
		paid = _client_pay(gs, key, pen, "penalidades")
	if paid > 0.0:
		gs.add_money(paid)
		gs.add_counter("contract_penalties_in", paid)
	k["cp_paid"] = float(k.get("cp_paid", 0.0)) + paid
	k["cp_failed"] = int(k.get("cp_failed", 0)) + 1
	_reliability_add(gs, key, -float(cfg().get("reliability_fail", 15)))
	FreeMarketSim.stat(gs, "supplier_penalties", paid)
	k["next_due"] = int(k["next_due"]) + int(k.get("period", 30))
	if int(k["cp_failed"]) >= 2 or int(k["installments"]) <= 1:
		k["status"] = "incumplido"
		k["breached_by"] = "proveedor"
	elif int(k["done"]) + int(k["failed"]) + int(k["cp_failed"]) >= int(k["installments"]):
		k["status"] = "cumplido"
	gs.notify("%s no tuvo %s para tu entrega: te pagó %s de penalidad (fiabilidad %d/100).%s" % [k["client_name"], TradeSim.good_label(str(k["good"])), Fmt.money(paid), int(reliability(gs, key)), " Contrato terminado." if str(k["status"]) == "incumplido" else ""], "negocio")


## Cancelar un contrato activo: pagas una penalidad a la contraparte y baja un poco tu reputación.
static func cancel(gs, id: int) -> String:
	var k := find(contracts(gs), id)
	if k.is_empty() or str(k["status"]) != "activo":
		return "El contrato no está activo."
	var key := str(k["client"])
	var pen := float(k.get("penalty", 0.0))
	if pen > 0.0:
		gs.add_money(-pen)
		_client_receive(gs, key, pen)
	_rep_add(gs, key, -float(cfg().get("rep_fail", 12)) * 0.5)
	k["status"] = "cancelado"
	k["breached_by"] = "jugador"
	FreeMarketSim.stat(gs, "penalties", pen)
	_release_plan(gs, int(k.get("plan_id", -1)), str(k["good"]))
	return ""


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
		if is_buy(k):
			_daily_purchase(gs, k, today, due)
			continue
		if bool(k.get("auto", false)) and today >= due - 3 and deliver_block_reason(gs, k) == "":
			deliver(gs, int(k["id"]))
			continue
		if today > due:
			_fail(gs, k)
	var list := contracts(gs)
	var closed := list.filter(func(k): return str(k["status"]) != "activo")
	while closed.size() > 30:
		list.erase(closed.pop_front())


## Compra: con entrega automática el proveedor despacha el día acordado; si no, esperas a que
## pidas la entrega ("Entregar ahora") hasta 3 días después de la fecha.
static func _daily_purchase(gs, k: Dictionary, today: int, due: int) -> void:
	var auto := bool(k.get("auto", true))
	if (auto and today >= due) or (not auto and today > due + 3):
		if supplier_stock(gs, str(k["client"]), str(k["good"])) < float(k["qty"]):
			_supplier_fail(gs, k)
			return
		var pwhy := player_buy_block(gs, k) if auto else "no pediste la entrega a tiempo"
		if pwhy != "":
			_fail(gs, k, pwhy)
			return
		_dispatch_purchase(gs, k)


static func monthly(gs) -> void:
	for k in contracts(gs):
		# Deudas pendientes de clientes (ventas).
		if float(k.get("owed", 0.0)) > 0.0 and client_exists(gs, str(k["client"])):
			var owed := float(k["owed"])
			k["owed"] = 0.0
			_collect(gs, k, owed)
		# Tus deudas con proveedores (compras recibidas sin dinero suficiente).
		if float(k.get("debt", 0.0)) > 0.0 and gs.money > 0.0:
			var debt := float(k["debt"])
			k["debt"] = 0.0
			_pay_supplier(gs, k, debt)
	_generate_requests(gs)
	_generate_supply_offers(gs)


static func _pick_period(gs) -> int:
	var opts: Array = cfg().get("request_periods", [15, 30, 30, 60])
	return int(FreeMarketSim.pick(gs, opts))


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
		var period := 30
		if recurring:
			period = _pick_period(gs)
			inst = maxi(2, int(roundf(float(inst) * 30.0 / float(period))))
			qty = maxf(float(c.get("min_qty", 5)), roundf(qty * float(period) / 30.0))
		if float(t.get("cash", 0.0)) < unit * qty * mini(inst, 2):
			continue
		var dl := int(TradeSim.transport_quote(gs, tid, qty)["days"]) + FreeMarketSim.ri(gs, int(c.get("single_deadline_days", [25, 50])[0]), int(c.get("single_deadline_days", [25, 50])[1]))
		create_request(gs, key, good, qty, unit, inst, dl, -1, period)
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


## Proveedores NPC que te ofrecen venderte lo que tus negocios consumen y te falta.
static func _generate_supply_offers(gs) -> void:
	var needs := player_needs(gs)
	if needs.is_empty():
		return
	var c := cfg()
	var made := 0
	for good in needs:
		if made >= int(c.get("supply_offers_per_month", 1)):
			break
		var g := str(good)
		var need := float(needs[good])
		if available(gs, g) >= need or FreeMarketSim.rf(gs) > float(c.get("supply_offer_chance_month", 0.3)):
			continue
		var options := supplier_keys(gs, g).filter(func(k): return k != IMPORT_KEY)
		for x in inbox(gs):
			if is_buy(x) and str(x["good"]) == g:
				options = []
		if options.is_empty():
			continue
		var key := str(FreeMarketSim.pick(gs, options))
		var period := _pick_period(gs)
		var qty := clampf(roundf(need * float(period) / 30.0 * FreeMarketSim.rr(gs, 0.3, 0.7)), float(c.get("min_qty", 5)), float(c.get("max_qty", 300)))
		qty = minf(qty, floorf(supplier_capacity(gs, key, g, period)))
		qty = minf(qty, floorf(WarehouseSim.capacity_of(gs, WarehouseSim.PLAZA) * 0.5))
		if qty < float(c.get("min_qty", 5)):
			continue
		var unit := buy_reference_price(gs, key, g, qty) * FreeMarketSim.range_of(gs, c.get("supply_price_premium", [0.95, 1.08])) * (2.0 - rep_price_factor(gs, key))
		var inst := FreeMarketSim.ri(gs, int(c.get("supply_installments", [3, 6])[0]), int(c.get("supply_installments", [3, 6])[1]))
		if not create_supply_offer(gs, key, g, qty, unit, inst, period).is_empty():
			made += 1


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


static func reliability_rows(gs) -> Array:
	var rows := []
	for key in gs.market.get("reliability", {}):
		rows.append({"key": str(key), "name": client_name(gs, str(key)), "rel": reliability(gs, str(key))})
	rows.sort_custom(func(a, b): return float(a["rel"]) > float(b["rel"]))
	return rows


## Porcentaje de cumplimiento de las entregas vencidas (propias y de la contraparte).
static func compliance(k: Dictionary) -> float:
	var n := int(k["done"]) + int(k["failed"]) + int(k.get("cp_failed", 0))
	return 1.0 if n <= 0 else float(k["done"]) / float(n)


static func status_label(s: String) -> String:
	return {"activo": "activo", "cumplido": "cumplido", "incumplido": "incumplido", "cancelado": "cancelado",
		"pendiente": "esperando respuesta", "aceptada": "aceptada", "rechazada": "rechazada",
		"contraoferta": "contraoferta", "vencida": "vencida"}.get(s, s)
