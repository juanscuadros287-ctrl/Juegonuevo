class_name LandPortfolioSim
extends RefCounted
## Cartera de terrenos del jugador (pedido de Sebastián: "que pueda manejar mis terrenos: venderlos o que
## los empresarios me hagan ofertas"). Un TERRENO = tus parcelas de 80 m dentro de un territorio
## (chunk de 400 m) de LandSim. Estado en GameState.map["land_pf"] (se guarda):
##   lots   {"cx,cy": {basis, parcels, since, hist [[día, valor, índice]], listing {ask, since}, lease {...}, company}}
##   offers [{id, key, buyer, cid, npc_bid, reason, amount, max, day, expires, status}]
##   next_id, predial_last, predial_total, sales [{day, key, price, buyer, gain}]
## Reglas:
##   - Valor de mercado = LandSim.chunk_price / 25 × parcelas tuyas (fluctúa con el índice mensual del
##     municipio, la demanda, carreteras y nivel de precios). Plusvalía = valor − precio de compra.
##   - Impuesto predial mensual (moderado, según el municipio) → tesoro del municipio.
##   - Vender al Estado (precio fijo = valor × 0,9, sale del tesoro nacional) o poner en venta con precio
##     pedido (un ciudadano o empresario con ahorros lo compra si le parece justo).
##   - Ofertas entrantes de empresarios NPC y ciudadanos ricos: Aceptar, Rechazar o Contraofertar.
##   - Arrendar: renta mensual de un ciudadano o empresa NPC (no se construye mientras está arrendado).
##   - Un terreno con edificios tuyos NO se vende suelto: solo "Vender todo" (terreno + negocios) a un
##     empresario, y el edificio pasa a ser su empresa. El terreno del pueblo (chunk 0,0) no se vende.
##   - Economía cerrada: todo pago sale de un ciudadano, de la caja de una empresa NPC o del tesoro.


static func cfg() -> Dictionary:
	return GameData.extra("terrenos_costos").get("land", {})


static func init_state(gs) -> void:
	if not (gs.map is Dictionary):
		return
	var pf = gs.map.get("land_pf")
	if not (pf is Dictionary):
		pf = {}
	for k in ["lots"]:
		if not (pf.get(k) is Dictionary):
			pf[k] = {}
	for k in ["offers", "sales"]:
		if not (pf.get(k) is Array):
			pf[k] = []
	pf["next_id"] = int(pf.get("next_id", 1))
	pf["predial_last"] = float(pf.get("predial_last", 0.0))
	pf["predial_total"] = float(pf.get("predial_total", 0.0))
	gs.map["land_pf"] = pf


static func st(gs) -> Dictionary:
	if not (gs.map.get("land_pf") is Dictionary):
		init_state(gs)
	return gs.map["land_pf"]


static func key(cx: int, cy: int) -> String:
	return "%d,%d" % [cx, cy]


static func parse(k: String) -> Vector2i:
	var p := k.split(",")
	return Vector2i(int(p[0]), int(p[1])) if p.size() == 2 else Vector2i.ZERO


# --- Sincronización con las parcelas (GameState.unlocked_zones) ---------------------------------------

static func _counts(gs) -> Dictionary:
	var out := {}
	for z in gs.unlocked_zones:
		var c := MapSim.chunk_of_zone(int(z[0]), int(z[1]))
		var k := key(c.x, c.y)
		out[k] = int(out.get(k, 0)) + 1
	return out


## Crea/actualiza los terrenos según tus parcelas. Las parcelas sin compra registrada toman el valor de hoy.
static func sync(gs) -> void:
	var lots: Dictionary = st(gs)["lots"]
	var counts := _counts(gs)
	for k in counts:
		var c := parse(k)
		var n := int(counts[k])
		if not lots.has(k):
			lots[k] = {"basis": parcel_value(gs, c.x, c.y) * n, "parcels": n, "since": gs.today(), "hist": [], "listing": {}, "lease": {}, "company": -1}
		else:
			var lot: Dictionary = lots[k]
			var old := int(lot.get("parcels", 0))
			if n > old:
				lot["basis"] = float(lot.get("basis", 0.0)) + parcel_value(gs, c.x, c.y) * (n - old)
			elif n < old and old > 0:
				lot["basis"] = float(lot.get("basis", 0.0)) * float(n) / float(old)
			lot["parcels"] = n
	for k in lots.keys():
		if not counts.has(k):
			lots.erase(k)


## Compra registrada (LandSim o ConstructionSim): suma lo pagado al precio de compra del terreno.
static func on_bought(gs, cx: int, cy: int, price: float, parcels: int) -> void:
	var lots: Dictionary = st(gs)["lots"]
	var k := key(cx, cy)
	if not lots.has(k):
		lots[k] = {"basis": 0.0, "parcels": 0, "since": gs.today(), "hist": [], "listing": {}, "lease": {}, "company": -1}
	var lot: Dictionary = lots[k]
	lot["basis"] = float(lot.get("basis", 0.0)) + maxf(0.0, price)
	lot["parcels"] = int(lot.get("parcels", 0)) + parcels


## Gancho de MapSim.on_zone_bought: parcela suelta comprada al gobierno (precio = el que se acaba de pagar).
static func on_zone_bought(gs, zx: int, zy: int) -> void:
	var c := MapSim.chunk_of_zone(zx, zy)
	var price := 0.0
	if zx >= 0 and zx < gs.ZONE_GRID and zy >= 0 and zy < gs.ZONE_GRID:
		var n: int = gs.unlocked_zones.size() - 2
		price = float(GameData.game.get("zone_expansion_cost", 2500)) * pow(float(GameData.game.get("zone_expansion_growth", 1.5)), n) * gs.price_mult()
	else:
		price = LandSim.parcel_price(gs, zx, zy)
	on_bought(gs, c.x, c.y, price, 1)


# --- Valor, uso e impuesto ------------------------------------------------------------------------------

static func parcel_value(gs, cx: int, cy: int) -> float:
	return LandSim.chunk_price(gs, cx, cy) / float(LandSim.PARCELS)


static func value_of(gs, k: String) -> float:
	var lot: Dictionary = st(gs)["lots"].get(k, {})
	var c := parse(k)
	return snappedf(parcel_value(gs, c.x, c.y) * int(lot.get("parcels", 0)), 1.0)


static func zid_of(gs, k: String) -> int:
	var c := parse(k)
	return MapSim.gen(gs).zone_index(c.x, c.y)


static func is_town(k: String) -> bool:
	return k == "0,0"


## Edificios del jugador sobre ese terreno.
static func buildings_on(gs, k: String) -> Array:
	var c := parse(k)
	var out := []
	for b in gs.buildings:
		if not gs.owned_by_player(b):
			continue
		if MapSim.chunk_of(float(b["x"]), float(b["z"])) == c:
			var zc := MapSim.zone_at(gs, float(b["x"]), float(b["z"]))
			if gs.is_zone_unlocked(zc.x, zc.y):
				out.append(b)
	return out


static func has_deposit(gs, k: String) -> bool:
	var r := MapSim.chunk_rect(parse(k).x, parse(k).y)
	for d in gs.logistics.get("deposits", []):
		if float(d.get("amount", 0.0)) > 0.0 and r.has_point(Vector2(float(d["x"]), float(d["z"]))):
			return true
	return false


## "vacío", "con edificio (N)", "con yacimiento" o "arrendado".
static func use_of(gs, k: String) -> String:
	var lot: Dictionary = st(gs)["lots"].get(k, {})
	if not (lot.get("lease", {}) as Dictionary).is_empty():
		return "arrendado"
	var n := buildings_on(gs, k).size()
	if n > 0:
		return "con edificio%s" % ("" if n == 1 else "s (%d)" % n)
	if has_deposit(gs, k):
		return "con yacimiento"
	return "vacío"


static func predial_rate(gs, zid: int) -> float:
	var pol := MunicipalSim.policy_of(gs, zid)
	var r := float(cfg().get("predial_rate", 0.006))
	r *= float(cfg().get("predial_regulation", {}).get(str(pol.get("regulation", "media")), 1.0))
	r *= 1.0 + maxf(0.0, float(pol.get("local_tax", 0.0))) * float(cfg().get("predial_local_weight", 3.0))
	return r


static func predial_month(gs, k: String) -> float:
	return value_of(gs, k) * predial_rate(gs, zid_of(gs, k)) / 12.0


## Filas para la interfaz y los informes.
static func rows(gs) -> Array:
	sync(gs)
	var out := []
	for k in st(gs)["lots"]:
		var lot: Dictionary = st(gs)["lots"][k]
		var zid := zid_of(gs, k)
		var v := value_of(gs, k)
		var basis := float(lot.get("basis", 0.0))
		var comp := int(lot.get("company", -1))
		out.append({"key": k, "zid": zid, "municipio": MunicipalSim.name_of(gs, zid), "parcels": int(lot.get("parcels", 0)),
			"basis": basis, "value": v, "gain": v - basis, "gain_pct": (v - basis) / maxf(1.0, basis),
			"use": use_of(gs, k), "predial": predial_month(gs, k), "index": LandSim.index_of(gs, zid) * LandSim.demand_of(gs, zid),
			"status": "en venta" if not (lot.get("listing", {}) as Dictionary).is_empty() else ("arrendado" if not (lot.get("lease", {}) as Dictionary).is_empty() else "—"),
			"company": comp, "owner_label": gs.building_label(gs.get_building(comp)) if comp >= 0 and not gs.get_building(comp).is_empty() else "Tú"})
	return out


static func totals(gs) -> Dictionary:
	var t := {"basis": 0.0, "value": 0.0, "predial": 0.0, "parcels": 0, "lots": 0}
	for r in rows(gs):
		t["basis"] += float(r["basis"])
		t["value"] += float(r["value"])
		t["predial"] += float(r["predial"])
		t["parcels"] += int(r["parcels"])
		t["lots"] += 1
	t["gain"] = float(t["value"]) - float(t["basis"])
	return t


# --- Vender ---------------------------------------------------------------------------------------------

## Motivo por el que no se puede vender ("" si se puede). mode: "estado" | "lista" | "npc" | "arriendo" | "todo".
static func sell_block_reason(gs, k: String, mode: String) -> String:
	var lot: Dictionary = st(gs)["lots"].get(k, {})
	if lot.is_empty() or int(lot.get("parcels", 0)) <= 0:
		return "No es tuyo"
	if is_town(k):
		return "Es el terreno de tu pueblo (la plaza): no se vende"
	if mode != "todo" and not buildings_on(gs, k).is_empty():
		return "Tiene edificios tuyos: solo se vende todo junto (terreno + negocios)"
	if mode != "arriendo" and not (lot.get("lease", {}) as Dictionary).is_empty():
		return "Está arrendado: termina el arriendo primero"
	if mode == "arriendo" and not (lot.get("lease", {}) as Dictionary).is_empty():
		return "Ya está arrendado"
	if mode == "estado":
		var price := state_price(gs, k)
		if float(gs.government.get("treasury", 0.0)) < price:
			return "El Estado no tiene fondos (%s en el tesoro)" % Fmt.money(float(gs.government.get("treasury", 0.0)))
	if mode == "todo":
		var bs := buildings_on(gs, k)
		if bs.is_empty():
			return "No tiene edificios: véndelo normal"
		for b in bs:
			var why := _sell_all_building_reason(gs, b)
			if why != "":
				return why
	return ""


static func state_price(gs, k: String) -> float:
	return snappedf(value_of(gs, k) * float(cfg().get("state_buy_ratio", 0.9)), 1.0)


static func suggested_ask(gs, k: String) -> float:
	return snappedf(value_of(gs, k) * 1.05, 10.0)


## Vende al Estado a precio fijo (el dinero sale del tesoro nacional).
static func sell_to_state(gs, k: String) -> String:
	var why := sell_block_reason(gs, k, "estado")
	if why != "":
		return why
	var price := GovSim.treasury_pay(gs, state_price(gs, k))
	_transfer_out(gs, k, price, {"owner": "estado", "name": "Estado"}, "Estado")
	return ""


static func list_for_sale(gs, k: String, ask: float) -> String:
	var why := sell_block_reason(gs, k, "lista")
	if why != "":
		return why
	if ask <= 0.0:
		return "Indica un precio"
	st(gs)["lots"][k]["listing"] = {"ask": snappedf(ask, 1.0), "since": gs.today()}
	gs.notify("Pusiste en venta tu terreno en %s por %s." % [MunicipalSim.name_of(gs, zid_of(gs, k)), Fmt.money(ask)], "jugador")
	return ""


static func unlist(gs, k: String) -> void:
	var lot: Dictionary = st(gs)["lots"].get(k, {})
	if not lot.is_empty():
		lot["listing"] = {}


## Compradores posibles (ciudadanos o empresas NPC con dinero para pagar `price`):
## [{cid, npc_bid, name, reason, wallet}]. Primero empresarios (quieren expandirse), luego ciudadanos ricos.
static func buyers(gs, price: float) -> Array:
	var out := []
	var share := float(cfg().get("buyer_reserve_share", 0.35))
	var seen := {}
	for b in NpcBusinessSim.npc_buildings(gs):
		if str(b.get("npc_state", "")) != NpcBusinessSim.STATE_OPEN:
			continue
		var owner: Citizen = gs.citizens.get(int(b.get("owner_id", -1)))
		if owner == null or seen.has(owner.id):
			continue
		var wallet := maxf(0.0, owner.money) + maxf(0.0, float(b.get("reserve", 0.0))) * share
		if wallet >= price:
			seen[owner.id] = true
			out.append({"cid": owner.id, "npc_bid": int(b["id"]), "name": owner.full_name(), "wallet": wallet,
				"reason": "quiere expandir %s" % gs.building_label(b)})
	var rich := []
	for c in gs.citizens.values():
		if gs.is_player(c.id) or seen.has(c.id) or c.money < price:
			continue
		rich.append(c)
	rich.sort_custom(func(a, bb): return a.money > bb.money)
	for c in rich.slice(0, 6):
		out.append({"cid": c.id, "npc_bid": -1, "name": c.full_name(), "wallet": c.money, "reason": "quiere construir ahí"})
	return out


## Cobra al comprador: primero sus ahorros, luego la caja de su empresa. Devuelve lo cobrado.
static func _charge_buyer(gs, buyer: Dictionary, price: float) -> float:
	var c: Citizen = gs.citizens.get(int(buyer.get("cid", -1)))
	var got := 0.0
	if c != null:
		var take := minf(maxf(0.0, c.money), price)
		c.money -= take
		got += take
	var nb: Dictionary = gs.get_building(int(buyer.get("npc_bid", -1)))
	if got < price and not nb.is_empty():
		var take2 := minf(maxf(0.0, float(nb.get("reserve", 0.0))), price - got)
		nb["reserve"] = float(nb.get("reserve", 0.0)) - take2
		got += take2
	return got


## Pasa tus parcelas del territorio al nuevo dueño. `owner` = override de map.parcels.
static func _transfer_out(gs, k: String, price: float, owner: Dictionary, buyer_label: String) -> void:
	var c := parse(k)
	var lot: Dictionary = st(gs)["lots"].get(k, {})
	var basis := float(lot.get("basis", 0.0))
	var keep := []
	for z in gs.unlocked_zones:
		if MapSim.chunk_of_zone(int(z[0]), int(z[1])) != c:
			keep.append(z)
	gs.unlocked_zones = keep
	gs.map["parcels"][k] = owner
	gs.add_money(price)
	LandSim._record_sale(gs, c.x, c.y, price, "Tú", buyer_label)
	var sales: Array = st(gs)["sales"]
	sales.append({"day": gs.today(), "key": k, "price": snappedf(price, 1.0), "buyer": buyer_label, "gain": snappedf(price - basis, 1.0)})
	while sales.size() > 40:
		sales.pop_front()
	st(gs)["lots"].erase(k)
	for o in st(gs)["offers"]:
		if str(o["key"]) == k and str(o["status"]) == "pendiente":
			o["status"] = "cancelada"
	gs.notify("Vendiste tu terreno en %s a %s por %s (%s %s)." % [MunicipalSim.name_of(gs, MapSim.gen(gs).zone_index(c.x, c.y)), buyer_label, Fmt.money(price),
		"plusvalía" if price >= basis else "minusvalía", Fmt.money(absf(price - basis))], "importante")
	EventBus.zones_changed.emit()
	EventBus.map_changed.emit()


static func _sell_to_buyer(gs, k: String, buyer: Dictionary, price: float) -> void:
	var got := _charge_buyer(gs, buyer, price)
	_transfer_out(gs, k, got, {"owner": "npc", "name": str(buyer.get("name", "")), "citizen_id": int(buyer.get("cid", -1)), "since": gs.today()}, str(buyer.get("name", "")))


# --- Vender todo (terreno + negocios) ----------------------------------------------------------------------

static func _sell_all_building_reason(gs, b: Dictionary) -> String:
	if not BusinessSim.is_business(b):
		return "%s no es un negocio (viviendas y oficinas no se venden con el terreno)" % gs.building_label(b)
	if str(b.get("status", "")) == "construccion":
		return "%s está en obra" % gs.building_label(b)
	if (WarehouseSim.is_warehouse_building(gs, b) and WarehouseSim.used_in(gs, int(b["id"])) > 0.5) or not LogisticsSim.vehicles_of(gs, int(b["id"])).is_empty():
		return "%s guarda mercancía o vehículos: vacíalo primero" % gs.building_label(b)
	if not CostSim.is_producer_def(gs.building_def(b)) and float(gs.level_def(b).get("warehouse_capacity", 0.0)) > 0.0:
		return "%s es un almacén: no se vende con el terreno" % gs.building_label(b)
	if BankSim.is_bank(b):
		return "Un banco no se vende con el terreno"
	return ""


static func sell_all_price(gs, k: String) -> float:
	var p := value_of(gs, k)
	for b in buildings_on(gs, k):
		p += EconomySim.property_value(gs, b)
	return snappedf(p, 10.0)


## Vende el terreno con sus negocios a un empresario: los edificios pasan a ser su empresa (NPC).
static func sell_all(gs, k: String) -> String:
	var why := sell_block_reason(gs, k, "todo")
	if why != "":
		return why
	var price := sell_all_price(gs, k)
	var bl := buyers(gs, price)
	if bl.is_empty():
		return "Nadie en el pueblo tiene %s para comprarlo todo" % Fmt.money(price)
	var buyer: Dictionary = bl[0]
	var owner: Citizen = gs.citizens.get(int(buyer["cid"]))
	var bs := buildings_on(gs, k)
	var got := _charge_buyer(gs, buyer, price)
	for b in bs:
		b["owner"] = "ciudadano"
		b["owner_id"] = owner.id
		b["npc"] = true
		b["npc_state"] = NpcBusinessSim.STATE_OPEN
		b["reserve"] = 0.0
		b["auto_price"] = true
		b["markup"] = float(b.get("markup", 0.08))
		b["loss_months"] = 0
		b["founded_day"] = int(b.get("founded_day", gs.today()))
		b["founder"] = str(b.get("founder", gs.player_name()))
		b["partners"] = []
		var owners: Array = b.get("owners", [])
		owners.append({"id": owner.id, "name": owner.full_name(), "how": "compró", "day": gs.today()})
		b["owners"] = owners
		NpcBusinessSim._snapshot_family(gs, b, owner)
		EventBus.building_changed.emit(int(b["id"]))
	# Capital de trabajo: el comprador pone una parte de lo que le queda.
	if not bs.is_empty():
		var wc := maxf(0.0, owner.money) * 0.3
		owner.money -= wc
		bs[0]["reserve"] = wc
	_transfer_out(gs, k, got, {"owner": "npc", "name": owner.full_name(), "citizen_id": owner.id, "since": gs.today()}, owner.full_name())
	WarehouseSim.invalidate()
	LogisticsSim.on_buildings_changed(gs)   # Sus almacenes integrados dejan de ser tuyos.
	return ""


# --- Ofertas entrantes ------------------------------------------------------------------------------------

static func pending_offers(gs) -> Array:
	return st(gs)["offers"].filter(func(o): return str(o["status"]) == "pendiente")


static func get_offer(gs, oid: int) -> Dictionary:
	for o in st(gs)["offers"]:
		if int(o["id"]) == oid:
			return o
	return {}


## Crea una oferta por un terreno (la usan monthly y las pruebas). Devuelve la oferta o {}.
static func make_incoming_offer(gs, k: String, r: RandomNumberGenerator = null) -> Dictionary:
	if sell_block_reason(gs, k, "npc") != "":
		return {}
	for o in pending_offers(gs):
		if str(o["key"]) == k:
			return {}
	if r == null:
		r = RandomNumberGenerator.new()
		r.seed = int(gs.settings.get("seed", 1)) * 977 + gs.today() + k.hash()
	var v := value_of(gs, k)
	var rg: Array = cfg().get("offer_range", [0.85, 1.2])
	var amount := snappedf(v * r.randf_range(float(rg[0]), float(rg[1])), 10.0)
	var bl := buyers(gs, amount)
	if bl.is_empty():
		return {}
	var buyer: Dictionary = bl[r.randi_range(0, mini(bl.size(), 3) - 1)]
	var wr: Array = cfg().get("offer_walk_range", [1.0, 1.22])
	var mx := minf(float(buyer["wallet"]), snappedf(amount * r.randf_range(float(wr[0]), float(wr[1])), 10.0))
	var o := {"id": int(st(gs)["next_id"]), "key": k, "buyer": str(buyer["name"]), "cid": int(buyer["cid"]), "npc_bid": int(buyer["npc_bid"]),
		"reason": str(buyer["reason"]), "amount": amount, "max": maxf(amount, mx), "day": gs.today(),
		"expires": gs.today() + int(cfg().get("offer_days", 20)), "status": "pendiente", "value": v}
	st(gs)["next_id"] = int(o["id"]) + 1
	st(gs)["offers"].append(o)
	gs.notify("Oferta por tu terreno en %s: %s (%s) ofrece %s (vale %s). Revísala en «Mis terrenos»." % [MunicipalSim.name_of(gs, zid_of(gs, k)), o["buyer"], o["reason"],
		Fmt.money(amount), Fmt.money(v)], "importante")
	return o


static func accept_offer(gs, oid: int) -> String:
	var o := get_offer(gs, oid)
	if o.is_empty() or str(o["status"]) != "pendiente":
		return "La oferta ya no está vigente"
	var why := sell_block_reason(gs, str(o["key"]), "npc")
	if why != "":
		return why
	var buyer := {"cid": int(o["cid"]), "npc_bid": int(o["npc_bid"]), "name": str(o["buyer"])}
	if _wallet(gs, buyer) < float(o["amount"]):
		o["status"] = "retirada"
		return "%s ya no tiene el dinero: retiró la oferta" % str(o["buyer"])
	o["status"] = "aceptada"
	_sell_to_buyer(gs, str(o["key"]), buyer, float(o["amount"]))
	return ""


static func reject_offer(gs, oid: int) -> void:
	var o := get_offer(gs, oid)
	if not o.is_empty() and str(o["status"]) == "pendiente":
		o["status"] = "rechazada"


## Contraoferta: si cabe en lo que el comprador está dispuesto a pagar, la acepta y se cierra la venta;
## si no, responde con su último precio (una vez) o se retira.
static func counter_offer(gs, oid: int, amount: float) -> String:
	var o := get_offer(gs, oid)
	if o.is_empty() or str(o["status"]) != "pendiente":
		return "La oferta ya no está vigente"
	var buyer := {"cid": int(o["cid"]), "npc_bid": int(o["npc_bid"]), "name": str(o["buyer"])}
	var mx := minf(float(o["max"]), _wallet(gs, buyer))
	if amount <= mx:
		o["amount"] = snappedf(amount, 1.0)
		var why := accept_offer(gs, oid)
		return why if why != "" else "%s aceptó tu contraoferta de %s." % [o["buyer"], Fmt.money(amount)]
	if bool(o.get("countered", false)) or mx <= float(o["amount"]) + 1.0:
		o["status"] = "retirada"
		return "%s no puede pagar %s y se retiró." % [o["buyer"], Fmt.money(amount)]
	o["countered"] = true
	o["amount"] = snappedf(mx, 10.0)
	return "%s no llega a %s; su última oferta es %s." % [o["buyer"], Fmt.money(amount), Fmt.money(float(o["amount"]))]


static func _wallet(gs, buyer: Dictionary) -> float:
	var w := 0.0
	var c: Citizen = gs.citizens.get(int(buyer.get("cid", -1)))
	if c != null:
		w += maxf(0.0, c.money)
	var nb: Dictionary = gs.get_building(int(buyer.get("npc_bid", -1)))
	if not nb.is_empty():
		w += maxf(0.0, float(nb.get("reserve", 0.0)))
	return w


# --- Arriendo ---------------------------------------------------------------------------------------------

static func lease_rent(gs, k: String) -> float:
	return snappedf(value_of(gs, k) * float(cfg().get("lease_rate_month", 0.005)), 0.1)


static func lease(gs, k: String) -> String:
	var why := sell_block_reason(gs, k, "arriendo")
	if why != "":
		return why
	var rent := lease_rent(gs, k)
	var bl := buyers(gs, rent * 6.0)
	if bl.is_empty():
		return "Nadie quiere arrendarlo ahora (necesitan ahorros de %s)" % Fmt.money(rent * 6.0)
	var t: Dictionary = bl[0]
	st(gs)["lots"][k]["lease"] = {"tenant": str(t["name"]), "cid": int(t["cid"]), "npc_bid": int(t["npc_bid"]), "rent": rent,
		"since": gs.today(), "until": gs.today() + 30 * int(cfg().get("lease_months", 12))}
	gs.notify("Arrendaste tu terreno en %s a %s por %s al mes." % [MunicipalSim.name_of(gs, zid_of(gs, k)), t["name"], Fmt.money2(rent)], "negocio")
	return ""


static func end_lease(gs, k: String) -> void:
	var lot: Dictionary = st(gs)["lots"].get(k, {})
	if not lot.is_empty():
		lot["lease"] = {}


# --- Diario y mensual -------------------------------------------------------------------------------------

static func daily(gs) -> void:
	var s := st(gs)
	for o in s["offers"]:
		if str(o["status"]) == "pendiente" and gs.today() > int(o["expires"]):
			o["status"] = "vencida"
	# Terrenos en venta: algún comprador aparece si el precio pedido le parece justo.
	for k in s["lots"].keys():
		var lot: Dictionary = s["lots"].get(k, {})
		var lst: Dictionary = lot.get("listing", {})
		if lst.is_empty():
			continue
		var r := RandomNumberGenerator.new()
		r.seed = int(gs.settings.get("seed", 1)) * 613 + gs.today() * 7 + k.hash()
		if r.randf() >= float(cfg().get("listing_daily_chance", 0.05)):
			continue
		var ask := float(lst["ask"])
		var rg: Array = cfg().get("listing_buyer_range", [0.92, 1.18])
		var will := value_of(gs, k) * r.randf_range(float(rg[0]), float(rg[1])) * LandSim.demand_of(gs, zid_of(gs, k))
		if will < ask or sell_block_reason(gs, k, "lista") != "":
			continue
		var bl := buyers(gs, ask)
		if bl.is_empty():
			continue
		_sell_to_buyer(gs, k, bl[0], ask)


static func monthly(gs) -> void:
	sync(gs)
	var s := st(gs)
	var predial := 0.0
	var hmax := int(cfg().get("hist_max", 240))
	var r := RandomNumberGenerator.new()
	r.seed = int(gs.settings.get("seed", 1)) * 389 + gs.today()
	var new_offers := 0
	for k in s["lots"].keys():
		var lot: Dictionary = s["lots"][k]
		var zid := zid_of(gs, k)
		var v := value_of(gs, k)
		var hist: Array = lot.get("hist", [])
		hist.append([gs.today(), v, snappedf(LandSim.index_of(gs, zid) * LandSim.demand_of(gs, zid), 0.001)])
		while hist.size() > hmax:
			hist.pop_front()
		lot["hist"] = hist
		# Impuesto predial → tesoro del municipio.
		var t := snappedf(predial_month(gs, k), 0.01)
		if t > 0.0:
			var comp: Dictionary = gs.get_building(int(lot.get("company", -1)))
			if not comp.is_empty() and gs.owned_by_player(comp):
				BusinessSim.pay(gs, comp, t, "impuestos")
			else:
				gs.add_money(-t)
			var reg := MunicipalSim.region(gs, zid)
			if reg.is_empty():
				GovSim.add_treasury(gs, t)
			else:
				reg["treasury"] = float(reg.get("treasury", 0.0)) + t
			predial += t
		# Arriendo.
		var ls: Dictionary = lot.get("lease", {})
		if not ls.is_empty():
			var tenant := {"cid": int(ls.get("cid", -1)), "npc_bid": int(ls.get("npc_bid", -1))}
			if gs.today() > int(ls.get("until", 0)) or _wallet(gs, tenant) < float(ls["rent"]):
				lot["lease"] = {}
				gs.notify("Terminó el arriendo de tu terreno en %s." % MunicipalSim.name_of(gs, zid), "negocio")
			else:
				gs.add_money(_charge_buyer(gs, tenant, float(ls["rent"])))
				ls["paid"] = float(ls.get("paid", 0.0)) + float(ls["rent"])
		# Ofertas entrantes: más frecuentes en zonas valorizadas.
		if new_offers < int(cfg().get("offer_max_per_month", 2)) and not is_town(k):
			var idx := LandSim.index_of(gs, zid) * LandSim.demand_of(gs, zid)
			var chance := minf(float(cfg().get("offer_max_chance", 0.4)), float(cfg().get("offer_monthly_chance", 0.07)) * idx * idx)
			if r.randf() < chance and not make_incoming_offer(gs, k, r).is_empty():
				new_offers += 1
	s["predial_last"] = predial
	s["predial_total"] = float(s.get("predial_total", 0.0)) + predial
	if predial > 0.0:
		gs.add_counter("taxes_paid", predial)
	var offers: Array = s["offers"]
	while offers.size() > 30:
		offers.pop_front()
