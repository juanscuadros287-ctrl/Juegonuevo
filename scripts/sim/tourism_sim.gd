class_name TourismSim
extends RefCounted
## Fase 8 — turismo: atracciones con entrada pagada, hospedaje y turistas que llegan
## SOLO por las conexiones con otros pueblos (TradeSim.connected_towns). Su gasto en
## entradas, alojamiento y en tus negocios es dinero que entra de afuera.
## Estado en GameState.tourism (se guarda automáticamente). Parámetros en data/tourism.json.

const MONTH_KEYS := ["visitors", "overnight", "lost_no_bed", "visits", "tickets", "lodging", "shops", "media", "ads_cost"]


static func cfg() -> Dictionary:
	return GameData.extra("tourism")


static func init_state(gs) -> void:
	var t: Dictionary = gs.tourism
	var defaults := {"campaigns": [], "next_campaign_id": 1, "guests": [], "month": {}, "last_month": {},
		"history": [], "today": {}, "total_visitors": 0, "total_income": 0.0, "first_tourists": false, "warned_no_conn": false}
	for k in defaults:
		if not t.has(k):
			t[k] = defaults[k]
	gs.tourism = t


# --- Consultas ---------------------------------------------------------------------------------

static func kind(b: Dictionary) -> String:
	return str(GameData.building_def(str(b.get("type", ""))).get("tourism", ""))


static func is_attraction(b: Dictionary) -> bool:
	return kind(b) == "atraccion"


static func is_hotel(b: Dictionary) -> bool:
	return kind(b) == "hotel"


static func is_media(b: Dictionary) -> bool:
	return kind(b) == "medio"


static func is_tourism_business(b: Dictionary) -> bool:
	return kind(b) != ""


## Empleados presentes (no enfermos).
static func staff(gs, b: Dictionary) -> int:
	var n := 0
	for c in gs.employees_of(int(b["id"])):
		if c.job_kind == "empleo" and not c.sick:
			n += 1
	return n


## Negocios turísticos del jugador (atraccion | hotel | medio). Con only_open, solo activos y con personal.
static func player_list(gs, k: String, only_open := false) -> Array:
	var out := []
	for b in gs.buildings:
		if not gs.owned_by_player(b) or kind(b) != k:
			continue
		if only_open and (str(b["status"]) != "activo" or staff(gs, b) <= 0):
			continue
		out.append(b)
	return out


## Puntos de atractivo de un edificio turístico (según personal y tipo de mapa).
static func attraction_points(gs, b: Dictionary) -> float:
	if not gs.owned_by_player(b) or str(b["status"]) != "activo":
		return 0.0
	var ld: Dictionary = gs.level_def(b)
	var base := float(ld.get("attraction", 0.0))
	if base <= 0.0:
		return 0.0
	var n := staff(gs, b)
	if n <= 0:
		return 0.0
	var ratio := clampf(float(n) / maxf(1.0, float(ld.get("jobs", 1))), 0.0, 1.0)
	var floor_v := float(cfg().get("understaffed_floor", 0.4))
	var mb := float(gs.building_def(b).get("map_bonus", {}).get(str(gs.settings.get("map_type", "")), 1.0))
	return base * (floor_v + (1.0 - floor_v) * ratio) * mb


## Precio de referencia por entrada o por noche de un edificio turístico.
static func ticket_ref(gs, b: Dictionary) -> float:
	var product := str(gs.building_def(b).get("product", ""))
	return EconomySim.market_price(gs, product) * float(gs.level_def(b).get("ticket_value", 1.0))


static func willing_price(gs, b: Dictionary) -> float:
	return ticket_ref(gs, b) * float(cfg().get("willing_markup", 1.6))


## Capacidad diaria estimada (visitas o camas) con el personal actual.
static func daily_capacity(gs, b: Dictionary) -> float:
	return BusinessSim.expected_output(gs, b)


## Desglose del atractivo turístico del pueblo.
static func breakdown(gs) -> Dictionary:
	var c := cfg()
	var attractions := 0.0
	var hotels := 0.0
	var public := 0.0
	var types := {}
	for b in gs.buildings:
		var k := kind(b)
		if k == "atraccion":
			var p := attraction_points(gs, b)
			if p > 0.0:
				attractions += p
				types[str(b["type"])] = true
		elif k == "hotel":
			hotels += attraction_points(gs, b)
		elif str(gs.building_def(b).get("category", "")) == "publico" and str(b.get("status", "")) == "activo":
			public += float(c.get("public_attractions", {}).get(str(b["type"]), 0.0))
	var diversity := 1.0 + float(c.get("diversity_bonus", 0.1)) * maxf(0.0, types.size() - 1.0)
	var base := (attractions + hotels + public) * diversity
	var hc: Dictionary = c.get("happiness", {})
	var min_m := float(c.get("min_mult", 0.2))
	var happy: float = float(hc.get("base", 0.6)) + gs.avg_happiness() * float(hc.get("per_point", 0.008))
	var safety := maxf(min_m, 1.0 - float(gs.problems.get("crime", 0.0)) / 100.0 * float(c.get("crime_penalty", 0.8)))
	var clean := maxf(min_m, 1.0 - float(gs.problems.get("pollution", 0.0)) / 100.0 * float(c.get("pollution_penalty", 0.5)))
	var ads := AdvertisingSim.tourism_mult(gs)
	var season := float(c.get("season", {}).get(str(gs.season), 1.0))
	var weather := float(c.get("weather", {}).get(str(gs.weather.get("type", "")), 1.0))
	var total := base * happy * safety * clean * ads * season * weather
	return {"attractions": attractions, "hotels": hotels, "public": public, "diversity": diversity, "base": base,
		"happiness": happy, "safety": safety, "pollution": clean, "ads": ads, "season": season, "weather": weather,
		"total": total, "types": types.size()}


static func transport_quality(conn: Dictionary) -> float:
	if conn.has("quality"):
		return maxf(0.05, float(conn["quality"]))
	var c := cfg()
	var key := str(conn.get("transport", ""))
	return float(c.get("transport_quality", {}).get(key, c.get("default_transport_quality", 0.6)))


static func connection_distance(conn: Dictionary) -> float:
	return maxf(0.0, float(conn.get("distance", cfg().get("default_distance", 60.0))))


## Cuántos turistas potenciales aporta una conexión (transporte × distancia × tamaño del pueblo).
static func connection_factor(conn: Dictionary) -> float:
	var c := cfg()
	var dist := connection_distance(conn)
	var f := transport_quality(conn) / (1.0 + dist / float(c.get("distance_scale", 100.0)))
	if conn.has("population"):
		f *= clampf(sqrt(float(conn["population"]) / float(c.get("town_size_ref", 500.0))), 0.5, 2.5)
	return f


static func connections_factor(gs) -> float:
	var total := 0.0
	for conn in TradeSim.connected_towns(gs):
		if conn is Dictionary:
			total += connection_factor(conn)
	return total


## Turistas nuevos esperados por día (sin azar). 0 si no hay conexiones.
static func expected_tourists(gs) -> float:
	var conns: Array = TradeSim.connected_towns(gs)
	if conns.is_empty():
		return 0.0
	var raw := float(cfg().get("tourists_per_point", 2.0)) * float(breakdown(gs)["total"]) * connections_factor(gs)
	var cap := float(cfg().get("saturation_per_connection", 350.0)) * conns.size()
	return raw / (1.0 + raw / maxf(1.0, cap))


## Fracción de turistas que pasa la noche (más cuanto más lejos está su pueblo).
static func overnight_share(gs) -> float:
	var oc: Dictionary = cfg().get("overnight", {})
	var num := 0.0
	var den := 0.0
	for conn in TradeSim.connected_towns(gs):
		if not conn is Dictionary:
			continue
		var w := connection_factor(conn)
		var s := clampf(float(oc.get("base", 0.25)) + float(oc.get("per_distance", 0.004)) * connection_distance(conn), float(oc.get("min", 0.1)), float(oc.get("max", 0.85)))
		num += s * w
		den += w
	return num / den if den > 0.0 else 0.0


static func budget_per_tourist(gs) -> float:
	return float(cfg().get("budget_per_day", {}).get(str(gs.era()), 3.0)) * gs.price_mult()


static func guests_in(gs, hotel_id: int) -> int:
	var n := 0
	for g in gs.tourism.get("guests", []):
		if int(g["h"]) == hotel_id:
			n += int(g["k"])
	return n


# --- Simulación diaria ------------------------------------------------------------------------

static func daily(gs) -> void:
	init_state(gs)
	var rec := {}
	for k in MONTH_KEYS:
		rec[k] = 0.0
	_apply_auto_prices(gs)
	AdvertisingSim.daily_media(gs, rec)
	var staying := _update_guests(gs, rec)
	var conns: Array = TradeSim.connected_towns(gs)
	var arrivals := 0
	var lodged := 0
	var day_trippers := 0
	if not conns.is_empty():
		var noise: Array = cfg().get("noise", [0.8, 1.2])
		var n: float = expected_tourists(gs) * gs.rng.randf_range(float(noise[0]), float(noise[1]))
		arrivals = int(floor(n + gs.rng.randf()))
	elif not gs.tourism.get("warned_no_conn", false) and not player_list(gs, "atraccion", true).is_empty():
		gs.tourism["warned_no_conn"] = true
		gs.notify("Tus atracciones no reciben turistas: no hay conexiones con otros pueblos. Abre una ruta comercial.", "negocio")
	if arrivals > 0:
		var overnight := int(round(arrivals * overnight_share(gs)))
		day_trippers = arrivals - overnight
		lodged = _lodge(gs, overnight, rec)
		var unlodged := overnight - lodged
		var cancel := int(round(unlodged * float(cfg().get("overnight", {}).get("no_bed_cancel", 0.5))))
		day_trippers += unlodged - cancel
		rec["lost_no_bed"] = float(cancel)
		rec["overnight"] = float(lodged)
		rec["visitors"] = float(arrivals - cancel)
		if not gs.tourism.get("first_tourists", false) and arrivals - cancel > 0:
			gs.tourism["first_tourists"] = true
			gs.notify("¡Llegaron los primeros turistas a %s! Pagan entradas, alojamiento y compran en tus negocios." % str(gs.settings.get("town_name", "tu pueblo")), "importante")
	var present := day_trippers + lodged + staying
	if present > 0:
		_visit_attractions(gs, present, rec)
		_shop(gs, present, rec)
	rec["present"] = float(present)
	gs.tourism["today"] = rec
	var m: Dictionary = gs.tourism["month"]
	for k in MONTH_KEYS:
		m[k] = float(m.get(k, 0.0)) + float(rec[k])
	var income := float(rec["tickets"]) + float(rec["lodging"]) + float(rec["shops"]) + float(rec["media"])
	gs.tourism["total_visitors"] = int(gs.tourism.get("total_visitors", 0)) + int(rec["visitors"])
	gs.tourism["total_income"] = float(gs.tourism.get("total_income", 0.0)) + income


## Precio automático de entradas/noches: mercado × valor del nivel × (1 + margen).
static func _apply_auto_prices(gs) -> void:
	for b in gs.buildings:
		if not gs.owned_by_player(b) or not is_tourism_business(b) or not bool(b.get("auto_price", false)):
			continue
		b["price"] = clampf(snappedf(ticket_ref(gs, b) * (1.0 + float(b.get("markup", 0.0))), 0.01), 0.01, BusinessSim.max_price(gs, b))


## Los huéspedes que siguen en el pueblo pagan otra noche. Devuelve cuántos turistas se quedan hoy.
static func _update_guests(gs, rec: Dictionary) -> int:
	var guests: Array = gs.tourism.get("guests", [])
	var keep := []
	var present := 0
	for g in guests:
		if int(g["n"]) <= 0:
			continue
		var h: Dictionary = gs.get_building(int(g["h"]))
		if h.is_empty() or str(h["status"]) != "activo":
			continue
		var inv: Dictionary = h["inventory"]
		var beds := mini(int(g["k"]), int(float(inv.get("alojamiento", 0.0))))
		if beds <= 0:
			continue
		inv["alojamiento"] = float(inv.get("alojamiento", 0.0)) - beds
		var pay := beds * float(h["price"])
		BusinessSim.earn(gs, h, pay, "ventas")
		EconomySim.record_discretionary(gs, "alojamiento", beds, pay)
		rec["lodging"] = float(rec["lodging"]) + pay
		present += beds
		g["k"] = beds
		g["n"] = int(g["n"]) - 1
		if int(g["n"]) > 0:
			keep.append(g)
	gs.tourism["guests"] = keep
	return present


## Aloja a los turistas que llegan para pasar la noche. Devuelve cuántos consiguieron cama.
static func _lodge(gs, overnight: int, rec: Dictionary) -> int:
	if overnight <= 0:
		return 0
	var hotels := player_list(gs, "hotel", true)
	hotels.sort_custom(func(a, b): return float(a["price"]) / maxf(0.1, float(gs.level_def(a).get("quality", 1.0))) < float(b["price"]) / maxf(0.1, float(gs.level_def(b).get("quality", 1.0))))
	var nights: Array = cfg().get("overnight", {}).get("nights", [1, 3])
	var left := overnight
	var lodged := 0
	for h in hotels:
		if left <= 0:
			break
		var price := float(h["price"])
		var ref := ticket_ref(gs, h)
		if price > willing_price(gs, h):
			continue
		var inv: Dictionary = h["inventory"]
		var free := int(float(inv.get("alojamiento", 0.0)))
		if free <= 0:
			continue
		var take := mini(free, left)
		if price > ref and ref > 0.0:
			# Por encima del precio de referencia, parte de los turistas busca otra opción.
			var reject := clampf((price / ref - 1.0) / (float(cfg().get("willing_markup", 1.6)) - 1.0) / AdvertisingSim.demand_mult(gs, h), 0.0, 1.0)
			take = int(round(take * (1.0 - reject)))
			if take <= 0:
				continue
		inv["alojamiento"] = float(free - take)
		var pay := take * price
		BusinessSim.earn(gs, h, pay, "ventas")
		EconomySim.record_discretionary(gs, "alojamiento", take, pay)
		rec["lodging"] = float(rec["lodging"]) + pay
		var stay: int = gs.rng.randi_range(int(nights[0]), int(nights[1]))
		if stay > 1:
			gs.tourism["guests"].append({"h": int(h["id"]), "n": stay - 1, "k": take})
		left -= take
		lodged += take
	return lodged


## Los turistas presentes visitan atracciones (las más atractivas, a buen precio) y pagan la entrada.
static func _visit_attractions(gs, present: int, rec: Dictionary) -> void:
	var list := player_list(gs, "atraccion", true)
	if list.is_empty():
		return
	var weights := []
	for b in list:
		weights.append(attraction_points(gs, b) * maxf(0.1, float(gs.level_def(b).get("quality", 1.0))))
	var visits := mini(int(cfg().get("visits_per_tourist", 2)), list.size())
	var groups := mini(present, int(cfg().get("max_groups", 40)))
	var markup := float(cfg().get("willing_markup", 1.6))
	var remaining := present
	for gi in range(groups):
		var k := int(ceil(float(remaining) / float(groups - gi)))
		remaining -= k
		var visited := {}
		for v in range(visits):
			var b := _pick_weighted(gs, list, weights, visited)
			if b.is_empty():
				break
			visited[int(b["id"])] = true
			var price := float(b["price"])
			var ref := ticket_ref(gs, b)
			if price > ref * markup:
				continue
			if price > ref and ref > 0.0 and gs.rng.randf() < (price / ref - 1.0) / (markup - 1.0) / AdvertisingSim.demand_mult(gs, b):
				continue
			var inv: Dictionary = b["inventory"]
			var take := minf(float(k), float(inv.get("entrada", 0.0)))
			if take < 1.0:
				continue
			take = floorf(take)
			inv["entrada"] = float(inv.get("entrada", 0.0)) - take
			var pay := take * price
			BusinessSim.earn(gs, b, pay, "ventas")
			EconomySim.record_discretionary(gs, "entrada", take, pay)
			rec["tickets"] = float(rec["tickets"]) + pay
			rec["visits"] = float(rec["visits"]) + take


static func _pick_weighted(gs, list: Array, weights: Array, exclude: Dictionary) -> Dictionary:
	var total := 0.0
	for i in range(list.size()):
		if not exclude.has(int(list[i]["id"])):
			total += float(weights[i])
	if total <= 0.0:
		return {}
	var r: float = gs.rng.randf() * total
	for i in range(list.size()):
		if exclude.has(int(list[i]["id"])):
			continue
		r -= float(weights[i])
		if r <= 0.0:
			return list[i]
	for i in range(list.size() - 1, -1, -1):
		if not exclude.has(int(list[i]["id"])):
			return list[i]
	return {}


## Gasto de los turistas en tus negocios del pueblo (tabernas, tiendas, panaderías…).
static func _shop(gs, present: int, rec: Dictionary) -> void:
	var goods: Array = cfg().get("shop_goods", ["ocio", "comida"])
	if goods.is_empty():
		return
	var markup := float(cfg().get("willing_markup", 1.6))
	var per_good := float(present) * budget_per_tourist(gs) * float(cfg().get("shop_share", 0.35)) / goods.size()
	for gid in goods:
		var good := str(gid)
		var left := per_good
		var max_price := EconomySim.market_price(gs, good) * markup
		for b in MarketSim.sellers(good):
			if left <= 0.01:
				break
			if gs.get_building(int(b["id"])).is_empty() or str(b["status"]) != "activo":
				continue
			var price := float(b["price"])
			var inv: Dictionary = b["inventory"]
			var stock := float(inv.get(good, 0.0))
			if price <= 0.0 or stock <= 0.0 or price > max_price:
				continue
			var take := minf(stock, left / price * AdvertisingSim.demand_mult(gs, b))
			take = minf(take, left / price)
			if take <= 0.001:
				continue
			inv[good] = stock - take
			var pay := take * price
			BusinessSim.earn(gs, b, pay, "ventas")
			EconomySim.record_discretionary(gs, good, take, pay)
			rec["shops"] = float(rec["shops"]) + pay
			left -= pay


# --- Cierre mensual ---------------------------------------------------------------------------

static func monthly(gs) -> void:
	init_state(gs)
	var m: Dictionary = gs.tourism["month"]
	var income := float(m.get("tickets", 0.0)) + float(m.get("lodging", 0.0)) + float(m.get("shops", 0.0)) + float(m.get("media", 0.0))
	m["income"] = income
	gs.tourism["last_month"] = m
	var hist: Array = gs.tourism["history"]
	hist.append({"day": gs.today(), "visitors": int(m.get("visitors", 0.0)), "income": income, "ads_cost": float(m.get("ads_cost", 0.0))})
	while hist.size() > 36:
		hist.pop_front()
	gs.tourism["month"] = {}
	if int(m.get("visitors", 0.0)) > 0:
		var lost := int(m.get("lost_no_bed", 0.0))
		gs.notify("Turismo del mes: %d visitantes dejaron %s en el pueblo%s." % [int(m.get("visitors", 0.0)), Fmt.money(income),
			" (%d no vinieron por falta de camas)" % lost if lost > 0 else ""], "negocio")


## Ingreso turístico del mes anterior (entradas + alojamiento + comercio + medios).
static func last_month_income(gs) -> float:
	return float(gs.tourism.get("last_month", {}).get("income", 0.0))
