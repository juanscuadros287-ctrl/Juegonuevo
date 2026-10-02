class_name PriceHistorySim
extends RefCounted
## Historial de precios (pedido: "saber si hay una tabla para ver cómo fluctúan los valores").
## Cada mes guarda el precio de mercado de todos los bienes, el índice de precios (IPC = nivel de precios), el
## salario promedio de los empleados y el índice del suelo (promedio de índice × demanda de los municipios × nivel
## de precios, base 100). Estado en GameState.economy["price_hist"] = {m: [mensual], y: [anual]}: hasta 240 meses
## (20 años); lo más viejo se comprime en promedios anuales. Entradas: {d: día, p: {bien: precio}, ipc, w, land}.


static func cfg() -> Dictionary:
	return GameData.extra("terrenos_costos").get("prices", {})


static func st(gs) -> Dictionary:
	var h = gs.economy.get("price_hist")
	if not (h is Dictionary):
		h = {}
	for k in ["m", "y"]:
		if not (h.get(k) is Array):
			h[k] = []
	gs.economy["price_hist"] = h
	return h


static func goods_list() -> Array:
	var out := []
	for g in GameData.sorted_ids(GameData.goods):
		if str(g).begins_with("_") or bool(GameData.goods[g].get("internal", false)):
			continue
		out.append(str(g))
	return out


static func avg_wage(gs) -> float:
	var t := 0.0
	var n := 0
	for c in gs.citizens.values():
		if c.job_kind == "empleo" and c.wage > 0.0:
			t += c.wage
			n += 1
	return t / n if n > 0 else 0.0


static func land_index(gs) -> float:
	var t := 0.0
	var n := 0
	for k in gs.map.get("land_index", {}):
		t += float(gs.map["land_index"][k]) * LandSim.demand_of(gs, int(k))
		n += 1
	return (t / n if n > 0 else 1.0) * gs.price_level() * 100.0


static func snapshot(gs) -> Dictionary:
	var p := {}
	for g in goods_list():
		p[g] = snappedf(EconomySim.market_price(gs, g), 0.0001)
	return {"d": gs.today(), "p": p, "ipc": snappedf(gs.price_level(), 0.0001), "w": snappedf(avg_wage(gs), 0.001), "land": snappedf(land_index(gs), 0.01)}


static func record(gs) -> void:
	var h := st(gs)
	var m: Array = h["m"]
	m.append(snapshot(gs))
	var mmax := int(cfg().get("monthly_max", 240))
	while m.size() > mmax:
		var chunk := m.slice(0, 12)
		m = m.slice(12)
		h["y"].append(_average(chunk))
	h["m"] = m
	var y: Array = h["y"]
	while y.size() > int(cfg().get("annual_max", 200)):
		y.pop_front()


static func _average(entries: Array) -> Dictionary:
	var out := {"d": int(entries[-1]["d"]), "p": {}, "ipc": 0.0, "w": 0.0, "land": 0.0, "annual": true}
	var n := float(entries.size())
	for e in entries:
		for k in ["ipc", "w", "land"]:
			out[k] = float(out[k]) + float(e.get(k, 0.0)) / n
		for g in e.get("p", {}):
			out["p"][g] = float(out["p"].get(g, 0.0)) + float(e["p"][g]) / n
	return out


## Todas las entradas en orden (anuales primero y luego mensuales).
static func entries(gs) -> Array:
	var h := st(gs)
	return (h["y"] as Array) + (h["m"] as Array)


static func value_of(e: Dictionary, what: String) -> float:
	if what in ["ipc", "w", "land"]:
		return float(e.get(what, 0.0))
	return float(e.get("p", {}).get(what, 0.0))


## Serie de un bien ("ipc", "w" o "land" para los índices) en los últimos `months` meses (0 = todo).
## Devuelve {values: Array[float], days: Array[int]}.
static func series(gs, what: String, months := 0) -> Dictionary:
	var vals := []
	var days := []
	var since: int = gs.today() - months * 30 if months > 0 else -1000000000
	for e in entries(gs):
		if int(e["d"]) < since:
			continue
		vals.append(value_of(e, what))
		days.append(int(e["d"]))
	return {"values": vals, "days": days}


## Valor hace `months` meses (la entrada más cercana a esa fecha; -1 si no hay datos tan viejos).
static func value_ago(gs, what: String, months: int) -> float:
	var target: int = gs.today() - months * 30
	var all := entries(gs)
	if all.is_empty() or int(all[0]["d"]) > target + 3:
		return -1.0
	var best: Dictionary = all[0]
	for e in all:
		if int(e["d"]) <= target + 3:
			best = e
	return value_of(best, what)


## Variación relativa contra hace `months` meses (NAN si no hay datos).
static func change(gs, what: String, months: int, now := -1.0) -> float:
	var past := value_ago(gs, what, months)
	if now < 0.0:
		now = EconomySim.market_price(gs, what) if not what in ["ipc", "w", "land"] else (gs.price_level() if what == "ipc" else (avg_wage(gs) if what == "w" else land_index(gs)))
	if past <= 0.0:
		return NAN
	return now / past - 1.0


static func min_max(gs, what: String) -> Vector2:
	var lo := INF
	var hi := -INF
	for e in entries(gs):
		var v := value_of(e, what)
		if v <= 0.0:
			continue
		lo = minf(lo, v)
		hi = maxf(hi, v)
	if lo == INF:
		var p := EconomySim.market_price(gs, what)
		return Vector2(p, p)
	return Vector2(lo, hi)


## Causas actuales de la fluctuación de un bien (textos cortos).
static func causes(gs, good: String) -> Array:
	var out := []
	var f := float(EconomySim.good_state(gs, good).get("factor", 1.0))
	if f > 1.05:
		out.append("escasez")
	elif f < 0.95:
		out.append("exceso de oferta")
	if ClimateSim.price_mult(gs, good) > 1.02:
		out.append("clima")
	if WarSim.price_mult(gs, good) > 1.02:
		out.append("guerra")
	var fl := EconomySim.fluct(gs, good)
	if absf(fl - 1.0) > 0.05:
		out.append("ciclo del mercado %s" % ("al alza" if fl > 1.0 else "a la baja"))
	if EconomySim.annual_inflation(gs) > 0.03:
		out.append("inflación")
	if absf(CountriesSim._fx_mult - 1.0) > 0.03:
		out.append("tipo de cambio")
	var ph := str(GlobalEconSim.home(gs).get("phase", "normal"))
	if ph != "normal" and ph != "":
		out.append("ciclo económico: %s" % GlobalEconSim.phase_label(ph).to_lower())
	return out


static func monthly(gs) -> void:
	record(gs)
