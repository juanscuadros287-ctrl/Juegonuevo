class_name AdvertisingSim
extends RefCounted
## Fase 8 — publicidad: campañas (pregonero → periódico → radio → TV) que aumentan la demanda de tus
## negocios y atraen más turistas. Tus propios medios (periódico, radio, TV) dan descuento en tus
## campañas y venden espacios publicitarios a anunciantes de los pueblos conectados.
## Contrato: demand_mult(gs, b) >= 1 multiplica la disposición a comprarle a ese negocio.
## Las campañas viven en GameState.tourism["campaigns"]. Parámetros en data/advertising.json.


static func cfg() -> Dictionary:
	return GameData.extra("advertising")


static func channel(id: String) -> Dictionary:
	return cfg().get("channels", {}).get(id, {})


static func channel_ids() -> Array:
	return GameData.sorted_ids(cfg().get("channels", {}))


static func channel_label(id: String) -> String:
	return str(channel(id).get("label", id))


## "" si el canal está disponible; si no, el motivo.
static func channel_block_reason(gs, id: String) -> String:
	var ch := channel(id)
	if ch.is_empty():
		return "Medio desconocido"
	var tech := str(ch.get("tech", ""))
	if not gs.has_tech(tech):
		return "Requiere investigar: %s" % GameData.tech_label(tech)
	return ""


static func campaigns(gs) -> Array:
	if not gs.tourism.has("campaigns"):
		gs.tourism["campaigns"] = []
	return gs.tourism["campaigns"]


static func is_active(gs, c: Dictionary) -> bool:
	return gs.today() < int(c.get("end_day", 0))


## Tipo de objetivo: "todos", "turismo" o "negocio" (id de edificio).
static func target_kind(target: String) -> String:
	if target == "todos" or target == "turismo":
		return target
	return "negocio"


static func target_label(gs, target: String) -> String:
	var k := target_kind(target)
	if k != "negocio":
		return str(cfg().get("targets", {}).get(k, {}).get("label", k))
	var b: Dictionary = gs.get_building(int(target))
	return gs.building_label(b) if not b.is_empty() else "(negocio demolido)"


# --- Costos y efectos ------------------------------------------------------------------------

## Tamaño de la audiencia: población del pueblo (o pueblos conectados para la promoción turística).
static func audience(gs, target: String) -> float:
	var a: Dictionary = cfg().get("audience", {})
	var lo := float(a.get("min", 0.5))
	var hi := float(a.get("max", 5.0))
	if target_kind(target) == "turismo":
		return clampf(lo + float(a.get("per_connection", 0.35)) * TradeSim.connected_towns(gs).size(), lo, hi)
	return clampf(float(gs.citizens.size()) / float(a.get("per_citizens", 100.0)), lo, hi)


## Mayor descuento de tus medios activos que cubren ese canal (un canal de TV también publica en radio y prensa).
static func media_discount(gs, ch_id: String) -> float:
	var order := int(channel(ch_id).get("order", 0))
	if ch_id == "pregonero":
		return 0.0
	var best := 0.0
	for b in TourismSim.player_list(gs, "medio", true):
		var ld: Dictionary = gs.level_def(b)
		var own := str(ld.get("media_channel", ""))
		if int(channel(own).get("order", -1)) >= order:
			best = maxf(best, float(ld.get("ad_discount", 0.0)))
	return best


static func monthly_cost(gs, ch_id: String, target: String) -> float:
	var ch := channel(ch_id)
	var tk: Dictionary = cfg().get("targets", {}).get(target_kind(target), {})
	return float(ch.get("monthly_cost", 0.0)) * gs.price_mult() * audience(gs, target) * float(tk.get("cost_mult", 1.0)) * (1.0 - media_discount(gs, ch_id))


## Efecto bruto de una campaña: {"demand", "tourism"} (fracciones).
static func effects(gs, ch_id: String, target: String) -> Dictionary:
	var ch := channel(ch_id)
	var k := target_kind(target)
	var tk: Dictionary = cfg().get("targets", {}).get(k, {})
	var demand := float(ch.get("demand", 0.0)) * float(tk.get("demand_mult", 0.0))
	var tourism := float(ch.get("tourism", 0.0)) * float(tk.get("tourism_mult", 0.0))
	if k == "negocio":
		var b: Dictionary = gs.get_building(int(target))
		if not b.is_empty() and TourismSim.is_tourism_business(b):
			tourism = float(ch.get("tourism", 0.0)) * float(tk.get("tourism_if_tourist_business", 0.0))
	return {"demand": demand, "tourism": tourism}


## Rendimientos decrecientes: suma de efectos → bono efectivo (tope `cap`).
static func _saturate(total: float, cap: float) -> float:
	if total <= 0.0 or cap <= 0.0:
		return 0.0
	return cap * (1.0 - exp(-total / cap))


static func _demand_sum(gs, bid: int) -> float:
	var sum := 0.0
	var today: int = gs.today()
	var key := str(bid)
	for c in gs.tourism.get("campaigns", []):
		if today >= int(c["end_day"]):
			continue
		var t := str(c["target"])
		if t == "todos" or t == key:
			sum += float(c["demand"])
	return sum


static func _tourism_sum(gs) -> float:
	var sum := 0.0
	var today: int = gs.today()
	for c in gs.tourism.get("campaigns", []):
		if today < int(c["end_day"]):
			sum += float(c["tourism"])
	return sum


## Multiplicador de demanda (>= 1) de un negocio según las campañas activas.
static func demand_mult(gs, b: Dictionary) -> float:
	var list: Array = gs.tourism.get("campaigns", [])
	if list.is_empty():
		return 1.0
	return 1.0 + _saturate(_demand_sum(gs, int(b.get("id", -1))), float(cfg().get("max_demand", 0.8)))


## Multiplicador de turistas (>= 1) por campañas activas.
static func tourism_mult(gs) -> float:
	var list: Array = gs.tourism.get("campaigns", [])
	if list.is_empty():
		return 1.0
	return 1.0 + _saturate(_tourism_sum(gs), float(cfg().get("max_tourism", 1.2)))


## Ventas del mes anterior de los negocios a los que apunta la campaña.
static func _target_sales(gs, target: String) -> float:
	var k := target_kind(target)
	if k == "turismo":
		return 0.0
	var total := 0.0
	for b in gs.player_buildings("negocio"):
		if k == "todos" or str(int(b["id"])) == target:
			total += BusinessSim.period_value(b, "last_month", "ventas")
	return total


## Estimación para el panel: costo, efecto marginal y ventas/turistas extra aproximados.
static func estimate(gs, ch_id: String, target: String, months: int) -> Dictionary:
	var cost := monthly_cost(gs, ch_id, target)
	var eff := effects(gs, ch_id, target)
	var cap_d := float(cfg().get("max_demand", 0.8))
	var cap_t := float(cfg().get("max_tourism", 1.2))
	var k := target_kind(target)
	var cur_d := 0.0
	if k == "negocio":
		cur_d = _demand_sum(gs, int(target))
	elif k == "todos":
		cur_d = _demand_sum(gs, -1)
	var d_gain := _saturate(cur_d + float(eff["demand"]), cap_d) - _saturate(cur_d, cap_d)
	var cur_t := _tourism_sum(gs)
	var t_gain := (_saturate(cur_t + float(eff["tourism"]), cap_t) - _saturate(cur_t, cap_t)) / (1.0 + _saturate(cur_t, cap_t))
	var extra_sales := _target_sales(gs, target) * d_gain * float(cfg().get("estimate_elasticity", 0.5))
	var tourists_day := TourismSim.expected_tourists(gs) * t_gain
	var extra_tourism := tourists_day * 30.0 * TourismSim.budget_per_tourist(gs) * 0.6
	return {"cost_month": cost, "total": cost * months, "demand_pct": d_gain * 100.0, "tourism_pct": t_gain * 100.0,
		"extra_sales_month": extra_sales, "extra_tourists_day": tourists_day, "extra_tourism_month": extra_tourism,
		"discount": media_discount(gs, ch_id)}


# --- Acciones del jugador ------------------------------------------------------------------------

static func start_campaign(gs, ch_id: String, target: String, months: int) -> String:
	var r := channel_block_reason(gs, ch_id)
	if r != "":
		return r
	months = clampi(months, 1, int(cfg().get("max_months", 24)))
	var k := target_kind(target)
	if k == "negocio":
		var b: Dictionary = gs.get_building(int(target))
		if b.is_empty() or not gs.owned_by_player(b) or not BusinessSim.is_business(b):
			return "Elige uno de tus negocios"
	elif k == "turismo" and TradeSim.connected_towns(gs).is_empty():
		return "Sin conexiones con otros pueblos, la promoción turística no llega a nadie"
	var cost := monthly_cost(gs, ch_id, target)
	if gs.money < cost:
		return "Necesitas %s para el primer mes" % Fmt.money(cost)
	var eff := effects(gs, ch_id, target)
	var c := {"id": int(gs.tourism.get("next_campaign_id", 1)), "channel": ch_id, "target": target, "months": months,
		"paid": 0, "start_day": gs.today(), "end_day": gs.today() + 30 * months, "cost": cost,
		"demand": float(eff["demand"]), "tourism": float(eff["tourism"])}
	gs.tourism["next_campaign_id"] = int(c["id"]) + 1
	_charge(gs, c)
	campaigns(gs).append(c)
	gs.notify("Campaña lanzada: %s para %s (%d meses, %s/mes)." % [channel_label(ch_id), target_label(gs, target), months, Fmt.money(cost)], "negocio")
	return ""


static func cancel_campaign(gs, id: int) -> String:
	var list := campaigns(gs)
	for c in list:
		if int(c["id"]) == id:
			list.erase(c)
			gs.notify("Cancelaste la campaña %s para %s." % [channel_label(str(c["channel"])), target_label(gs, str(c["target"]))], "negocio")
			return ""
	return "Campaña no encontrada"


## Cobra un mes de campaña. El pregonero es un vecino (el dinero queda en el pueblo);
## los demás medios son de afuera (el dinero sale), salvo el descuento de tus propios medios.
static func _charge(gs, c: Dictionary) -> void:
	var cost := float(c["cost"])
	var target := str(c["target"])
	var b: Dictionary = gs.get_building(int(target)) if target_kind(target) == "negocio" else {}
	if not b.is_empty():
		BusinessSim.pay(gs, b, cost, "publicidad")
	else:
		gs.add_money(-cost)
	if bool(channel(str(c["channel"])).get("local_pay", false)):
		var crier := _town_crier(gs)
		if crier != null:
			crier.money += cost
	c["paid"] = int(c.get("paid", 0)) + 1
	var m: Dictionary = gs.tourism.get("month", {})
	m["ads_cost"] = float(m.get("ads_cost", 0.0)) + cost
	gs.tourism["month"] = m


## Un vecino adulto (preferiblemente sin empleo) hace de pregonero.
static func _town_crier(gs) -> Citizen:
	var adult := int(GameData.citizens.get("adult_age", 16))
	var best: Citizen = null
	for c in gs.citizens.values():
		if gs.is_player(c.id) or c.age_years(gs.today()) < adult:
			continue
		if best == null or (c.job_id < 0 and best.job_id >= 0):
			best = c
		if best.job_id < 0:
			break
	return best


# --- Ciclos ------------------------------------------------------------------------------------

static func monthly(gs) -> void:
	var list := campaigns(gs)
	for c in list.duplicate():
		if not is_active(gs, c):
			list.erase(c)
			gs.notify("Terminó la campaña %s para %s." % [channel_label(str(c["channel"])), target_label(gs, str(c["target"]))], "negocio")
			continue
		if target_kind(str(c["target"])) == "negocio" and gs.get_building(int(c["target"])).is_empty():
			list.erase(c)
			continue
		if int(c.get("paid", 0)) >= int(c["months"]):
			continue
		if gs.money < float(c["cost"]):
			list.erase(c)
			gs.notify("Campaña %s cancelada: no tienes dinero para pagar el mes." % channel_label(str(c["channel"])), "jugador")
			continue
		_charge(gs, c)


## Tus medios venden espacios publicitarios a anunciantes de los pueblos conectados (dinero de afuera).
static func daily_media(gs, rec: Dictionary) -> void:
	var conns: Array = TradeSim.connected_towns(gs)
	if conns.is_empty():
		return
	var ms: Dictionary = cfg().get("media_sales", {})
	var ref := EconomySim.market_price(gs, "publicidad")
	for b in TourismSim.player_list(gs, "medio", true):
		var inv: Dictionary = b["inventory"]
		var units := float(inv.get("publicidad", 0.0))
		var price := float(b["price"])
		if units <= 0.0 or price <= 0.0 or ref <= 0.0 or price > ref * float(ms.get("willing_markup", 1.6)):
			continue
		var own := str(gs.level_def(b).get("media_channel", "periodico"))
		var demand := float(ms.get("units_per_connection", 4.0)) * float(ms.get("reach", {}).get(own, 1.0)) * conns.size()
		demand *= clampf(ref / price, 0.3, 1.5)
		var sold := minf(units, demand * gs.rng.randf_range(0.8, 1.2))
		if sold <= 0.0:
			continue
		inv["publicidad"] = units - sold
		var pay := sold * price
		BusinessSim.earn(gs, b, pay, "ventas")
		rec["media"] = float(rec.get("media", 0.0)) + pay
