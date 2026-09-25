class_name LandSim
extends RefCounted
## Fase 9B — Mercado de tierras. Cada territorio (chunk de 400 m = 25 parcelas de 80 m) tiene dueño:
## el Estado, un particular NPC o el jugador (que es dueño parcela a parcela: GameState.unlocked_zones).
## - Dueño por defecto determinista (semilla): cerca de tu pueblo, en los cascos urbanos y en el agua es del
##   Estado; el resto se reparte entre Estado y particulares. Los cambios se guardan en GameState.map.parcels
##   {"cx,cy": {owner: "estado"|"npc"|"jugador", name, citizen_id}}.
## - Precio: suelo base del municipio × bioma × yacimientos × cercanía a pueblos y carreteras × demanda ×
##   índice mensual del municipio (fluctúa) × nivel de precios.
## - Comprar al Estado: precio fijo (salvo regulación alta) o licitación contra otros postores.
## - Comprar a un particular: oferta que acepta o rechaza en unos días (el dinero queda en garantía).
## - Libre comercio: cada mes los NPC (y ciudadanos con ahorros) compran y venden territorios.
## - Una compra se une al instante al mapa del jugador (parcelas propias, revelado y malla rehecha).

const PARCELS := 25

static var _static := {}
static var _quick := {}
static var _static_key := ""


static func cfg() -> Dictionary:
	return MunicipalSim.cfg().get("land", {})


static func init_state(gs) -> void:
	var m: Dictionary = gs.map
	if not (m.get("parcels") is Dictionary):
		m["parcels"] = {}
	for k in ["land_offers", "land_tenders", "land_sales"]:
		if not (m.get(k) is Array):
			m[k] = []
	for k in ["land_index", "land_demand"]:
		if not (m.get(k) is Dictionary):
			m[k] = {}
	# Partidas 9A: map.parcels guardaba dueños por parcela (vacío en la práctica); se descarta lo inválido.
	for k in m["parcels"].keys():
		if not (m["parcels"][k] is Dictionary):
			m["parcels"].erase(k)


static func key(cx: int, cy: int) -> String:
	return "%d,%d" % [cx, cy]


static func _hash01(gs, cx: int, cy: int, salt: int) -> float:
	var h := hash("%d|%d|%d|%d" % [int(gs.settings.get("seed", 1)), cx, cy, salt])
	return float(absi(h) % 100000) / 100000.0


# --- Datos fijos por territorio (caché) ---------------------------------------------------------------

## {f: factor de bioma y yacimientos, land: fracción de tierra, biome: bioma dominante, town_d: m al pueblo más cercano}
static func static_info(gs, cx: int, cy: int) -> Dictionary:
	var g := MapSim.gen(gs)
	_check_cache(g)
	var c := Vector2i(cx, cy)
	if _static.has(c):
		return _static[c]
	var bf: Dictionary = cfg().get("biome_factor", {})
	var sum := 0.0
	var land := 0
	var hist := {}
	var r := MapSim.chunk_rect(cx, cy)
	for j in range(5):
		for i in range(5):
			var x := r.position.x + (i + 0.5) * 80.0
			var z := r.position.y + (j + 0.5) * 80.0
			var h := g.height(x, z)
			var b: String = CountryGen.BIOMES[g.biome_id(x, z, h)]
			sum += float(bf.get(b, 1.0))
			if h > g.water_level + 0.3:
				land += 1
			hist[b] = int(hist.get(b, 0)) + 1
	var dom := "llanura"
	var best := -1
	for b in hist:
		if int(hist[b]) > best:
			best = int(hist[b])
			dom = str(b)
	var f := sum / PARCELS
	# Yacimientos: la sierra y el desierto de un país minero valen más.
	var res: Dictionary = MapSim.country_def(MapSim.country_id(gs)).get("resources", {})
	var mineral := maxf(float(res.get("oro", 1.0)), maxf(float(res.get("hierro", 1.0)), float(res.get("plata", 1.0))))
	if dom in ["montana", "desierto"] and mineral > 1.0:
		f *= 1.0 + float(cfg().get("deposit_bonus", 0.45)) * (mineral - 1.0) * 1.5
	var info := {"f": f, "land": float(land) / PARCELS, "biome": dom, "town_d": float(quick_info(gs, cx, cy)["town_d"])}
	_static[c] = info
	return info


static func _check_cache(g: CountryGen) -> void:
	var gk := "%s|%d" % [MapSim._gen_key, g.get_instance_id()]
	if gk != _static_key:
		_static = {}
		_quick = {}
		_static_key = gk


## Datos rápidos (5 muestras): {land: fracción de tierra, town_d: m al pueblo más cercano}.
static func quick_info(gs, cx: int, cy: int) -> Dictionary:
	var g := MapSim.gen(gs)
	_check_cache(g)
	var c := Vector2i(cx, cy)
	if _quick.has(c):
		return _quick[c]
	var center := Vector2(cx, cy) * CountryGen.CHUNK
	var land := 0
	for o in [Vector2.ZERO, Vector2(-120, -120), Vector2(120, -120), Vector2(-120, 120), Vector2(120, 120)]:
		if g.height(center.x + o.x, center.y + o.y) > g.water_level + 0.3:
			land += 1
	var td := 1e9
	for z in g.zones:
		if bool(z["town"]):
			td = minf(td, center.distance_to(z["town_pos"]))
	var info := {"land": land / 5.0, "town_d": td}
	_quick[c] = info
	return info


# --- Dueños -------------------------------------------------------------------------------------------

## Dueño por defecto (sin compras): "estado" o "npc" con su nombre.
static func default_owner(gs, cx: int, cy: int) -> Dictionary:
	var g := MapSim.gen(gs)
	if not g.in_country_chunk(cx, cy):
		return {"owner": "", "name": ""}
	if maxi(absi(cx), absi(cy)) <= int(cfg().get("state_radius_chunks", 2)):
		return {"owner": "estado", "name": "Estado"}
	var zi := g.zone_index(cx, cy)
	if zi >= 0 and bool(g.zones[zi]["town"]) and g.zones[zi]["town_chunk"] == Vector2i(cx, cy):
		return {"owner": "estado", "name": "Estado (casco urbano)"}
	var si := quick_info(gs, cx, cy)
	if float(si["land"]) < 0.4:
		return {"owner": "estado", "name": "Estado"}
	var p := float(cfg().get("private_share", 0.45)) + float(cfg().get("private_near_town", 0.3)) * (1.0 - smoothstep(800.0, 4000.0, float(si["town_d"])))
	if _hash01(gs, cx, cy, 1) < p:
		return {"owner": "npc", "name": _npc_name(gs, cx, cy, 0)}
	return {"owner": "estado", "name": "Estado"}


static func _npc_name(gs, cx: int, cy: int, salt: int) -> String:
	var nd: Dictionary = GameData.extra("names")
	var male := _hash01(gs, cx, cy, 11 + salt) < 0.6
	var firsts: Array = nd.get("male" if male else "female", ["Juan"])
	var sur: Array = nd.get("surnames", ["Pérez"])
	var a := int(_hash01(gs, cx, cy, 12 + salt) * firsts.size()) % firsts.size()
	var b := int(_hash01(gs, cx, cy, 13 + salt) * sur.size()) % sur.size()
	var fam := ["Familia", "Hacienda", "Sucesión"]
	if _hash01(gs, cx, cy, 14 + salt) < 0.25:
		return "%s %s" % [fam[int(_hash01(gs, cx, cy, 15 + salt) * 3) % 3], str(sur[b])]
	return "%s %s" % [str(firsts[a]), str(sur[b])]


## Parcelas del jugador dentro de un territorio.
static func player_parcels(gs, cx: int, cy: int) -> int:
	var n := 0
	for z in gs.unlocked_zones:
		if floori(float(z[0]) / 5.0) == cx and floori(float(z[1]) / 5.0) == cy:
			n += 1
	return n


static func player_parcels_in(gs, zid: int) -> int:
	var g := MapSim.gen(gs)
	var n := 0
	for z in gs.unlocked_zones:
		if g.zone_index(floori(float(z[0]) / 5.0), floori(float(z[1]) / 5.0)) == zid:
			n += 1
	return n


## Dueño del territorio: {owner: "estado"|"npc"|"jugador", name, citizen_id, player_parcels}.
## "jugador" solo si tiene las 25 parcelas; si tiene algunas, el resto sigue siendo del dueño anterior.
static func owner_info(gs, cx: int, cy: int) -> Dictionary:
	var pp := player_parcels(gs, cx, cy)
	var out: Dictionary
	var ov: Dictionary = gs.map.get("parcels", {}).get(key(cx, cy), {})
	if not ov.is_empty() and str(ov.get("owner", "")) != "jugador":
		out = ov.duplicate()
	else:
		out = default_owner(gs, cx, cy)
	if pp >= PARCELS or str(ov.get("owner", "")) == "jugador" and pp > 0:
		out = {"owner": "jugador", "name": "Tú"}
	out["player_parcels"] = pp
	return out


## Rejilla de dueños del país para la capa de propiedad: un byte por chunk (fila por fila, desde c0):
## 0 Estado, 1 particular, 2 jugador (entero), 3 jugador en parte, 4 agua/Estado sin valor.
static func owner_grid(gs) -> PackedByteArray:
	var g := MapSim.gen(gs)
	var counts := {}
	for z in gs.unlocked_zones:
		var c := Vector2i(floori(float(z[0]) / 5.0), floori(float(z[1]) / 5.0))
		counts[c] = int(counts.get(c, 0)) + 1
	var parcels: Dictionary = gs.map.get("parcels", {})
	var out := PackedByteArray()
	out.resize(g.size * g.size)
	var k := 0
	for cy in range(g.c0, g.c1 + 1):
		for cx in range(g.c0, g.c1 + 1):
			var v := 0
			var pp := int(counts.get(Vector2i(cx, cy), 0))
			var ov: Dictionary = parcels.get(key(cx, cy), {})
			if pp >= PARCELS or (str(ov.get("owner", "")) == "jugador" and pp > 0):
				v = 2
			elif pp > 0:
				v = 3
			else:
				var own := str(ov.get("owner", "")) if not ov.is_empty() else str(default_owner(gs, cx, cy)["owner"])
				if own == "npc":
					v = 1
				elif float(quick_info(gs, cx, cy)["land"]) < 0.4:
					v = 4
			out[k] = v
			k += 1
	return out


static func owner_label(info: Dictionary) -> String:
	match str(info.get("owner", "")):
		"jugador":
			return "Tú"
		"npc":
			return "Particular: %s" % str(info.get("name", ""))
		"estado":
			return str(info.get("name", "Estado"))
	return "—"


# --- Precio ----------------------------------------------------------------------------------------------

static func _road_near(gs, center: Vector2) -> bool:
	var reach := float(cfg().get("road_reach_m", 500.0))
	for r in RoadSim.roads(gs):
		if RoadSim.dist_point_segment(center, RoadSim.seg_a(r), RoadSim.seg_b(r)) < reach:
			return true
	for c in gs.trade.get("connections", []):
		var tp := MapSim.trade_town_pos(gs, str(c.get("town_id", "")))
		if tp != Vector2.INF and RoadSim.dist_point_segment(center, Vector2.ZERO, tp) < reach:
			return true
	return false


static func index_of(gs, zid: int) -> float:
	return float(gs.map.get("land_index", {}).get(str(zid), 1.0))


static func demand_of(gs, zid: int) -> float:
	return float(gs.map.get("land_demand", {}).get(str(zid), 1.0))


## Precio de mercado de un territorio completo (25 parcelas). 0 fuera del país.
static func chunk_price(gs, cx: int, cy: int) -> float:
	var g := MapSim.gen(gs)
	if not g.in_country_chunk(cx, cy):
		return 0.0
	var zid := g.zone_index(cx, cy)
	var si := static_info(gs, cx, cy)
	var base := float(MunicipalSim.policy_of(gs, zid).get("land_price", 800.0))
	var f := maxf(0.08, float(si["f"]))
	f *= 1.0 + float(cfg().get("town_bonus", 1.6)) * exp(-float(si["town_d"]) / float(cfg().get("town_reach_m", 1400.0)))
	if _road_near(gs, Vector2(cx, cy) * CountryGen.CHUNK):
		f *= 1.0 + float(cfg().get("road_bonus", 0.3))
	f *= index_of(gs, zid) * demand_of(gs, zid)
	return snappedf(maxf(base * PARCELS * f * gs.price_mult(), 30.0 * PARCELS), 10.0)


## Precio de una parcela de 80 m del Estado en ese territorio.
static func parcel_price(gs, zx: int, zy: int) -> float:
	var c := MapSim.chunk_of_zone(zx, zy)
	return snappedf(chunk_price(gs, c.x, c.y) / PARCELS, 1.0)


## Precio por comprar lo que falta de un territorio (las parcelas que aún no son tuyas).
static func remaining_price(gs, cx: int, cy: int) -> float:
	var left := PARCELS - player_parcels(gs, cx, cy)
	return snappedf(chunk_price(gs, cx, cy) * left / PARCELS, 10.0)


# --- Compra ---------------------------------------------------------------------------------------------

static func _pending(gs, cx: int, cy: int) -> String:
	for o in gs.map.get("land_offers", []):
		if int(o["cx"]) == cx and int(o["cy"]) == cy:
			return "Ya hiciste una oferta: espera la respuesta"
	for t in gs.map.get("land_tenders", []):
		if int(t["cx"]) == cx and int(t["cy"]) == cy:
			return "Licitación en curso"
	return ""


## Motivo por el que no se puede comprar ("" si se puede). mode: "fijo" | "licitacion" | "oferta".
static func buy_block_reason(gs, cx: int, cy: int, mode: String, amount := -1.0) -> String:
	if not MapSim.in_country_chunk(gs, cx, cy):
		return "Fuera del país"
	if not MapSim.is_revealed(gs, cx, cy):
		return "Territorio sin explorar"
	var info := owner_info(gs, cx, cy)
	if str(info["owner"]) == "jugador":
		return "Ya es tuyo"
	var pend := _pending(gs, cx, cy)
	if pend != "":
		return pend
	var price := remaining_price(gs, cx, cy)
	var regulation := str(MunicipalSim.policy_of(gs, MapSim.gen(gs).zone_index(cx, cy)).get("regulation", "media"))
	match mode:
		"fijo":
			if str(info["owner"]) != "estado":
				return "Es de un particular: hazle una oferta"
			if regulation == "alta":
				return "Regulación alta: el municipio solo vende por licitación"
			if gs.money < price:
				return "Dinero insuficiente (%s)" % Fmt.money(price)
		"licitacion":
			if str(info["owner"]) != "estado":
				return "Es de un particular: hazle una oferta"
			if amount < price * 0.8:
				return "La puja mínima es %s" % Fmt.money(price * 0.8)
			if gs.money < amount:
				return "Dinero insuficiente (%s)" % Fmt.money(amount)
		"oferta":
			if str(info["owner"]) != "npc":
				return "Es del Estado: cómpralo a precio fijo o por licitación"
			if amount <= 0.0:
				return "Indica una oferta"
			if gs.money < amount:
				return "Dinero insuficiente (%s)" % Fmt.money(amount)
		_:
			return "Modo de compra desconocido"
	return ""


## Compra al Estado a precio fijo.
static func buy_from_state(gs, cx: int, cy: int) -> String:
	var reason := buy_block_reason(gs, cx, cy, "fijo")
	if reason != "":
		return reason
	var price := remaining_price(gs, cx, cy)
	gs.add_money(-price)
	GovSim.add_treasury(gs, price)
	_transfer_to_player(gs, cx, cy, price, "Estado")
	return ""


## Licitación: el dinero queda en garantía; a los `tender_days` gana la mejor puja (o se devuelve).
static func start_tender(gs, cx: int, cy: int, bid: float) -> String:
	var reason := buy_block_reason(gs, cx, cy, "licitacion", bid)
	if reason != "":
		return reason
	gs.add_money(-bid)
	var days := int(cfg().get("tender_days", 10))
	gs.map["land_tenders"].append({"cx": cx, "cy": cy, "bid": bid, "price": remaining_price(gs, cx, cy), "close_day": gs.today() + days})
	gs.notify("Te presentaste a la licitación del territorio (%d, %d) con %s. Se adjudica en %d días." % [cx, cy, Fmt.money(bid), days], "jugador")
	EventBus.map_changed.emit()
	return ""


## Oferta a un particular: responde en unos días. El dinero queda en garantía.
static func make_offer(gs, cx: int, cy: int, amount: float) -> String:
	var reason := buy_block_reason(gs, cx, cy, "oferta", amount)
	if reason != "":
		return reason
	var r: Array = cfg().get("offer_days", [2, 5])
	var days := int(r[0]) + int(_hash01(gs, cx, cy, gs.today()) * (int(r[1]) - int(r[0]) + 1))
	gs.add_money(-amount)
	var info := owner_info(gs, cx, cy)
	gs.map["land_offers"].append({"cx": cx, "cy": cy, "amount": amount, "price": remaining_price(gs, cx, cy), "reply_day": gs.today() + days,
			"seller": str(info.get("name", "")), "citizen_id": int(info.get("citizen_id", -1))})
	gs.notify("Ofreciste %s a %s por su territorio. Responderá en %d días." % [Fmt.money(amount), info.get("name", ""), days], "jugador")
	EventBus.map_changed.emit()
	return ""


## Probabilidad de que un particular acepte según oferta / precio de mercado.
static func accept_chance(ratio: float) -> float:
	var lo := float(cfg().get("min_accept_ratio", 0.85))
	var hi := float(cfg().get("sure_accept_ratio", 1.15))
	if ratio >= hi:
		return 1.0
	if ratio < lo:
		return 0.0
	return (ratio - lo) / (hi - lo)


static func _transfer_to_player(gs, cx: int, cy: int, price: float, seller: String) -> void:
	for zy in range(cy * 5, cy * 5 + 5):
		for zx in range(cx * 5, cx * 5 + 5):
			if not gs.is_zone_unlocked(zx, zy):
				gs.unlocked_zones.append([zx, zy])
	gs.map["parcels"][key(cx, cy)] = {"owner": "jugador", "name": "Tú"}
	_record_sale(gs, cx, cy, price, seller, "Tú")
	MapSim.reveal(gs, cx, cy)
	gs.notify("Compraste el territorio (%d, %d) en %s a %s por %s: 25 parcelas unidas a tu terreno." % [cx, cy,
			MunicipalSim.name_of(gs, MapSim.gen(gs).zone_index(cx, cy)), seller, Fmt.money(price)], "construccion")
	EventBus.zones_changed.emit()
	EventBus.map_changed.emit()


static func _record_sale(gs, cx: int, cy: int, price: float, seller: String, buyer: String) -> void:
	var sales: Array = gs.map.get("land_sales", [])
	sales.append({"day": gs.today(), "cx": cx, "cy": cy, "price": snappedf(price, 1.0), "seller": seller, "buyer": buyer})
	while sales.size() > int(cfg().get("history_max", 40)):
		sales.pop_front()
	gs.map["land_sales"] = sales
	var zid := MapSim.gen(gs).zone_index(cx, cy)
	var dm: Dictionary = gs.map["land_demand"]
	var rg: Array = cfg().get("index_range", [0.7, 1.5])
	dm[str(zid)] = clampf(demand_of(gs, zid) + float(cfg().get("demand_per_sale", 0.03)), float(rg[0]), float(rg[1]))


# --- Diario y mensual ----------------------------------------------------------------------------------------

static func daily(gs) -> void:
	var offers: Array = gs.map.get("land_offers", [])
	var tenders: Array = gs.map.get("land_tenders", [])
	if offers.is_empty() and tenders.is_empty():
		return
	for o in offers.duplicate():
		if gs.today() < int(o["reply_day"]):
			continue
		offers.erase(o)
		var ratio := float(o["amount"]) / maxf(1.0, float(o["price"]))
		var ok: bool = gs.rng.randf() < accept_chance(ratio) or ratio >= float(cfg().get("sure_accept_ratio", 1.15))
		var cx := int(o["cx"])
		var cy := int(o["cy"])
		if ok and str(owner_info(gs, cx, cy)["owner"]) == "npc":
			var cid := int(o.get("citizen_id", -1))
			if cid >= 0 and gs.citizens.has(cid):
				gs.citizens[cid].money += float(o["amount"])
			_transfer_to_player(gs, cx, cy, float(o["amount"]), str(o["seller"]))
		else:
			gs.add_money(float(o["amount"]))
			gs.notify("%s rechazó tu oferta de %s por su territorio (%d, %d). Te devolvieron el dinero." % [o["seller"], Fmt.money(float(o["amount"])), cx, cy], "jugador")
	for t in tenders.duplicate():
		if gs.today() < int(t["close_day"]):
			continue
		tenders.erase(t)
		var cx := int(t["cx"])
		var cy := int(t["cy"])
		var rr: Array = cfg().get("tender_rival", [0.85, 1.2])
		var rival := float(t["price"]) * lerpf(float(rr[0]), float(rr[1]), _hash01(gs, cx, cy, int(t["close_day"])))
		if float(t["bid"]) >= rival and str(owner_info(gs, cx, cy)["owner"]) == "estado":
			GovSim.add_treasury(gs, float(t["bid"]))
			_transfer_to_player(gs, cx, cy, float(t["bid"]), "Estado (licitación)")
		else:
			gs.add_money(float(t["bid"]))
			var buyer := _npc_name(gs, cx, cy, gs.today())
			if str(owner_info(gs, cx, cy)["owner"]) == "estado":
				gs.map["parcels"][key(cx, cy)] = {"owner": "npc", "name": buyer, "citizen_id": -1}
				_record_sale(gs, cx, cy, rival, "Estado (licitación)", buyer)
			gs.notify("Perdiste la licitación del territorio (%d, %d): %s pujó %s. Te devolvieron %s." % [cx, cy, buyer, Fmt.money(rival), Fmt.money(float(t["bid"]))], "jugador")
			EventBus.map_changed.emit()


static func monthly(gs) -> void:
	_fluctuate(gs)
	_npc_trades(gs)


## Índice de precio de cada municipio: paseo aleatorio con regreso a 1; la demanda se relaja.
static func _fluctuate(gs) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = int(gs.settings.get("seed", 1)) * 31 + gs.today()
	var amp := float(cfg().get("fluct_monthly", 0.06))
	var rg: Array = cfg().get("index_range", [0.7, 1.5])
	var idx: Dictionary = gs.map["land_index"]
	var dm: Dictionary = gs.map["land_demand"]
	for z in MapSim.gen(gs).zones:
		var k := str(int(z["id"]))
		var v := float(idx.get(k, 1.0))
		v = v + (1.0 - v) * 0.08 + r.randf_range(-amp, amp)
		idx[k] = snappedf(clampf(v, float(rg[0]), float(rg[1])), 0.001)
		if dm.has(k):
			dm[k] = snappedf(lerpf(float(dm[k]), 1.0, 0.1), 0.001)


## Libre comercio de tierras entre NPC: el Estado vende a particulares (o a ciudadanos con ahorros) y los
## particulares se venden entre ellos. No toca lo del jugador ni el entorno de su pueblo.
static func _npc_trades(gs) -> void:
	var g := MapSim.gen(gs)
	var r := RandomNumberGenerator.new()
	r.seed = int(gs.settings.get("seed", 1)) * 131 + gs.today()
	var rr: Array = cfg().get("npc_trades_per_month", [1, 4])
	var n := r.randi_range(int(rr[0]), int(rr[1]))
	var guard := int(cfg().get("state_radius_chunks", 2)) + 1
	var done := 0
	var tries := 0
	while done < n and tries < n * 12:
		tries += 1
		var cx := r.randi_range(g.c0, g.c1)
		var cy := r.randi_range(g.c0, g.c1)
		if maxi(absi(cx), absi(cy)) <= guard or player_parcels(gs, cx, cy) > 0 or _pending(gs, cx, cy) != "":
			continue
		if float(quick_info(gs, cx, cy)["land"]) < 0.4:
			continue
		var info := owner_info(gs, cx, cy)
		var price := chunk_price(gs, cx, cy) * r.randf_range(0.9, 1.12)
		var buyer := _npc_name(gs, cx, cy, gs.today() + tries)
		var cid := -1
		# Un ciudadano con ahorros suficientes también compra tierra.
		if str(info.get("name", "")).contains("casco"):
			continue
		for c in gs.citizens.values():
			if c.money >= price * 3.0 and c.id != gs.player_id:
				buyer = c.full_name()
				cid = c.id
				c.money -= price
				break
		# El dinero va al vendedor: al tesoro si vende el Estado a un ciudadano, o al ciudadano que vende.
		if str(info["owner"]) == "estado" and cid >= 0:
			GovSim.add_treasury(gs, price)
		var seller_id := int(info.get("citizen_id", -1))
		if seller_id >= 0 and gs.citizens.has(seller_id):
			gs.citizens[seller_id].money += price
		gs.map["parcels"][key(cx, cy)] = {"owner": "npc", "name": buyer, "citizen_id": cid}
		_record_sale(gs, cx, cy, price, str(info.get("name", "")), buyer)
		done += 1
	if done > 0:
		EventBus.map_changed.emit()
