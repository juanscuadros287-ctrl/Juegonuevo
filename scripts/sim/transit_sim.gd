class_name TransitSim
extends RefCounted
## Transporte (docs/TRANSPORTE.md): carreteras trazadas por puntos con curvas (Catmull-Rom
## muestreada en tramos de RoadSim) y puentes, caminos y vías férreas a otros pueblos trazados a
## mano, empresa de buses con paraderos y rutas, parqueaderos y el trayecto diario al trabajo.
##
## Las carreteras son OPCIONALES: la gente camina por el terreno. Sirven para vehículos: carretas y
## camiones que entran al almacén (LogisticsSim ya lo exige), autos de trabajadores que van a un
## parqueadero y buses. Un negocio sin carretera sigue funcionando con cargadores o mulas.
##
## Estado en GameState.transit (se guarda; todo con valores por defecto):
##   polys        [{id, kind, ctrl:[[x,z]], pts:[[x,z]], length, bridge}]   (tramos en logistics.roads con "poly")
##   stops        [{id, x, z, name}]
##   routes       [{id, name, depot, stops:[ids], auto, month_riders, month_income, last_riders, last_income}]
##   buses        [{id, depot, route, name, bought}]
##   trade_paths  {town_id: {path, path_len, ctrl, rail_path, rail_len, rail_ctrl}} (pendientes hasta abrir la ruta)
##   commute      {cid: {m: "bus"|"auto"|"lejos", d: metros}}   (solo quien vive a más de walk_ok)
##   no_access    {bid: true}   negocios modernos sin parqueadero ni paradero (penalización)
##   parking_use  {bid: autos hoy}
##   fare, parking_fee, next_id, month, last_month, totals

const MODE_BUS := "bus"
const MODE_CAR := "auto"
const MODE_FAR := "lejos"

static var _auto_cache := {}      # semilla -> PackedVector2Array (camino automático a otros pueblos)
static var _route_status := {}    # memo del día: rid -> estado


static func cfg() -> Dictionary:
	return GameData.extra("transit")


static func sub(key: String) -> Dictionary:
	return cfg().get(key, {})


static func state(gs) -> Dictionary:
	if gs.transit.is_empty():
		init_state(gs)
	return gs.transit


static func init_state(gs) -> void:
	var T: Dictionary = gs.transit
	for k in ["polys", "stops", "routes", "buses"]:
		if not T.has(k):
			T[k] = []
	for k in ["trade_paths", "commute", "no_access", "parking_use", "month", "last_month", "totals"]:
		if not T.has(k):
			T[k] = {}
	T["next_id"] = int(T.get("next_id", 1))
	T["fare"] = float(T.get("fare", cfg().get("fare_default", 0.1)))
	T["parking_fee"] = float(T.get("parking_fee", sub("parking").get("fee_default", 0.05)))
	gs.transit = T


static func _next_id(gs) -> int:
	var T := state(gs)
	var n := int(T.get("next_id", 1))
	T["next_id"] = n + 1
	return n


static func _stat(gs, key: String, amount: float) -> void:
	var T := state(gs)
	for p in ["month", "totals"]:
		var d: Dictionary = T[p]
		d[key] = float(d.get(key, 0.0)) + amount


static func _v2(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


static func _to_arr(pts: PackedVector2Array) -> Array:
	var out := []
	for p in pts:
		out.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01)])
	return out


static func _from_arr(arr) -> PackedVector2Array:
	var out := PackedVector2Array()
	if arr is Array:
		for a in arr:
			out.append(_v2(a))
	return out


# --- Geometría de polilíneas --------------------------------------------------------------------

## Curva Catmull-Rom (uniforme) por los puntos de control, muestreada cada `step` metros.
## Pasa exactamente por cada punto de control; los tramos resultantes miden entre 0,6 y 1,2 × step.
static func smooth(ctrl: PackedVector2Array, step: float) -> PackedVector2Array:
	var n := ctrl.size()
	var raw := PackedVector2Array()
	if n < 2:
		return ctrl
	for i in range(n - 1):
		var p0: Vector2 = ctrl[maxi(i - 1, 0)]
		var p1: Vector2 = ctrl[i]
		var p2: Vector2 = ctrl[i + 1]
		var p3: Vector2 = ctrl[mini(i + 2, n - 1)]
		var m := maxi(1, int(ceil(p1.distance_to(p2) / (step * 0.25))))
		for k in range(m):
			raw.append(p1.cubic_interpolate(p2, p0, p3, float(k) / m))
	raw.append(ctrl[n - 1])
	# Remuestreo a pasos parejos (tramos de RoadSim de ~step metros).
	var out := PackedVector2Array()
	out.append(raw[0])
	var acc := 0.0
	for i in range(1, raw.size()):
		acc += raw[i - 1].distance_to(raw[i])
		if acc >= step:
			out.append(raw[i])
			acc = 0.0
	var last: Vector2 = raw[raw.size() - 1]
	if out[out.size() - 1].distance_to(last) > 0.01:
		if out.size() >= 2 and out[out.size() - 1].distance_to(last) < step * 0.6:
			out[out.size() - 1] = last
		else:
			out.append(last)
	return out


static func poly_length(pts: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(pts.size() - 1):
		total += pts[i].distance_to(pts[i + 1])
	return total


## Distancias acumuladas de una polilínea (para ubicar puntos a lo largo).
static func poly_cum(pts: PackedVector2Array) -> PackedFloat32Array:
	var cum := PackedFloat32Array()
	var acc := 0.0
	for i in range(pts.size()):
		if i > 0:
			acc += pts[i - 1].distance_to(pts[i])
		cum.append(acc)
	return cum


static func poly_point(pts: PackedVector2Array, cum: PackedFloat32Array, d: float) -> Vector2:
	if pts.is_empty():
		return Vector2.ZERO
	if pts.size() == 1 or d <= 0.0:
		return pts[0]
	var total := cum[cum.size() - 1]
	if d >= total:
		return pts[pts.size() - 1]
	var lo := 0
	var hi := cum.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if cum[mid] <= d:
			lo = mid
		else:
			hi = mid
	var seg := maxf(0.0001, cum[hi] - cum[lo])
	return pts[lo].lerp(pts[hi], (d - cum[lo]) / seg)


static func dist_to_poly(p: Vector2, pts: PackedVector2Array) -> float:
	var best := INF
	for i in range(pts.size() - 1):
		best = minf(best, RoadSim.dist_point_segment(p, pts[i], pts[i + 1]))
	return best


# --- Terreno (sin malla: WaterSim guarda la cuadrícula de alturas) -------------------------------

static func is_water(gs, p: Vector2) -> bool:
	var h := WaterSim.height_at(gs, p.x, p.y)
	return h < WaterSim._water_level + 0.2


## Fase 9B: dentro del país (antes: dentro de los 400 m del pueblo).
static func _inside_map(gs, p: Vector2, margin := 0.5) -> bool:
	var b := MapSim.country_bounds_m(gs).grow(-margin)
	return b.has_point(p)


## Tramos de agua a lo largo de la polilínea: {wet (m), longest (m), wet_segments: [bool]}.
static func water_profile(gs, pts: PackedVector2Array) -> Dictionary:
	var wet := 0.0
	var run := 0.0
	var longest := 0.0
	var segs := []
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var l := a.distance_to(b)
		var n := maxi(1, int(ceil(l)))
		var seg_wet := 0
		for k in range(n):
			var p := a.lerp(b, (k + 0.5) / n)
			if is_water(gs, p):
				wet += l / n
				run += l / n
				seg_wet += 1
				longest = maxf(longest, run)
			else:
				run = 0.0
		segs.append(seg_wet * 2 >= n)
	return {"wet": wet, "longest": longest, "wet_segments": segs}


# --- Carreteras por puntos ------------------------------------------------------------------------

static func polys(gs) -> Array:
	return state(gs)["polys"]


## Punto pegado a la red: extremo de un tramo o punto más cercano sobre un tramo (a menos de `snap`).
static func snap_to_road(gs, p: Vector2) -> Vector2:
	var reach := float(sub("road_trace").get("snap", 4.0))
	var best := p
	var best_d := reach
	for r in RoadSim.roads(gs):
		for q in [RoadSim.seg_a(r), RoadSim.seg_b(r)]:
			var d: float = p.distance_to(q)
			if d < best_d:
				best_d = d
				best = q
	if best != p:
		return best
	for r in RoadSim.roads(gs):
		var a := RoadSim.seg_a(r)
		var b := RoadSim.seg_b(r)
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(0.0001, ab.length_squared()), 0.0, 1.0)
		var q := a + ab * t
		var d := p.distance_to(q)
		if d < best_d:
			best_d = d
			best = q
	return best


## Presupuesto de una carretera por puntos: {points, length, bridge, cost, reason}.
## `ctrl` son los clics del jugador; el primero y el último se pegan a la red existente.
static func road_plan(gs, ctrl: PackedVector2Array, kind: String, check_money := true) -> Dictionary:
	var out := {"points": PackedVector2Array(), "length": 0.0, "bridge": 0.0, "cost": {"total": 0.0, "stone": 0.0}, "reason": ""}
	var kd := RoadSim.kind_def(kind)
	if kd.is_empty():
		out["reason"] = "Tipo de camino desconocido"
		return out
	if not gs.has_tech(str(kd.get("tech", ""))):
		out["reason"] = "Requiere investigar: %s" % GameData.tech_label(str(kd.get("tech", "")))
		return out
	if ctrl.size() < 2:
		out["reason"] = "Pon al menos dos puntos"
		return out
	var c2 := ctrl.duplicate()
	c2[0] = snap_to_road(gs, c2[0])
	c2[c2.size() - 1] = snap_to_road(gs, c2[c2.size() - 1])
	var tc := sub("road_trace")
	var pts := smooth(c2, float(tc.get("sample_step", 4.0)))
	out["points"] = pts
	var length := poly_length(pts)
	out["length"] = length
	if length < float(RoadSim.cfg().get("min_length", 3.0)):
		out["reason"] = "Tramo demasiado corto"
		return out
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		for t in [0.0, 0.5, 1.0]:
			var q: Vector2 = a.lerp(b, t)
			if not _inside_map(gs, q, 1.0):
				out["reason"] = "Se sale del mapa"
				return out
			if not RoadSim._zone_unlocked(gs, q):
				out["reason"] = "Pasa por terreno del gobierno: cómpralo primero"
				return out
	var wp := water_profile(gs, pts)
	out["bridge"] = float(wp["wet"])
	out["wet_segments"] = wp["wet_segments"]
	if float(wp["longest"]) > float(tc.get("bridge_max", 36.0)):
		out["reason"] = "El agua es muy ancha: un puente cubre como máximo %d m" % int(tc.get("bridge_max", 36.0))
		return out
	out["terrain_mult"] = MapSim.terrain_cost_mult_path(pts, gs, false)   # Fase 9A: pendiente, túnel, cañón, altura (el puente va aparte).
	var cost := RoadSim._cost_for_length(gs, length * float(out["terrain_mult"]), kind)
	var bridge_extra: float = float(wp["wet"]) * float(kd.get("cost_per_unit", 1.0)) * (float(tc.get("bridge_cost_mult", 5.0)) - 1.0) * gs.price_mult()
	cost["bridge"] = bridge_extra
	cost["total"] = float(cost["total"]) + bridge_extra
	out["cost"] = cost
	if check_money and gs.money < float(cost["total"]):
		out["reason"] = "Dinero insuficiente (%s)" % Fmt.money(float(cost["total"]))
	return out


## Construye la carretera por puntos. Devuelve "" o el motivo.
static func build_road(gs, ctrl: PackedVector2Array, kind: String) -> String:
	var plan := road_plan(gs, ctrl, kind)
	if str(plan["reason"]) != "":
		return str(plan["reason"])
	var c: Dictionary = plan["cost"]
	if float(c.get("stone_stock", 0.0)) > 0.0:
		ConstructionSim._consume_stock(gs, "piedra", float(c["stone_stock"]))
	gs.add_money(-float(c["total"]))
	_stat(gs, "roads_cost", float(c["total"]))
	var pid := _next_id(gs)
	var pts: PackedVector2Array = plan["points"]
	var wet: Array = plan.get("wet_segments", [])
	for i in range(pts.size() - 1):
		var id := int(gs.logistics.get("next_road_id", 1))
		gs.logistics["next_road_id"] = id + 1
		var seg := {"id": id, "ax": pts[i].x, "az": pts[i].y, "bx": pts[i + 1].x, "bz": pts[i + 1].y, "kind": kind, "poly": pid}
		if i < wet.size() and bool(wet[i]):
			seg["bridge"] = true
		RoadSim.roads(gs).append(seg)
	polys(gs).append({"id": pid, "kind": kind, "ctrl": _to_arr(ctrl), "pts": _to_arr(pts), "length": float(plan["length"]),
		"bridge": float(plan["bridge"])})
	RoadSim._bump(gs)
	return ""


static func poly_segments(gs, pid: int) -> Array:
	var out := []
	for r in RoadSim.roads(gs):
		if int(r.get("poly", -1)) == pid:
			out.append(r)
	return out


static func remove_poly(gs, pid: int) -> void:
	var rs := RoadSim.roads(gs)
	for i in range(rs.size() - 1, -1, -1):
		if int(rs[i].get("poly", -1)) == pid:
			rs.remove_at(i)
	var ps := polys(gs)
	for i in range(ps.size() - 1, -1, -1):
		if int(ps[i]["id"]) == pid:
			ps.remove_at(i)
	RoadSim._bump(gs)


## Borrar: el paradero o la carretera (todo el trazado por puntos, o el tramo recto) bajo el clic.
static func erase_at(gs, p: Vector2) -> String:
	for s in stops(gs):
		if p.distance_to(stop_pos(s)) <= 3.5:
			remove_stop(gs, int(s["id"]))
			return "Paradero quitado."
	var best: Dictionary = {}
	var best_d := 4.0
	for r in RoadSim.roads(gs):
		var d := RoadSim.dist_point_segment(p, RoadSim.seg_a(r), RoadSim.seg_b(r))
		if d < best_d:
			best_d = d
			best = r
	if best.is_empty():
		return ""
	if best.has("poly"):
		var pid := int(best["poly"])
		var m := 0.0
		for r in poly_segments(gs, pid):
			m += RoadSim.seg_a(r).distance_to(RoadSim.seg_b(r))
		remove_poly(gs, pid)
		return "Carretera quitada (%d m)." % int(m)
	RoadSim.remove(gs, int(best["id"]))
	return "Tramo quitado."


# --- Acceso por carretera -------------------------------------------------------------------------

## {ok, kinds_ok (camiones), best (tipo más rápido cerca)} de un edificio.
static func road_access(gs, b: Dictionary) -> Dictionary:
	var p := Vector2(float(b["x"]), float(b["z"]))
	var reach: float = float(RoadSim.cfg().get("reach", 12.0)) + gs.footprint_of(b) * 0.25
	var best := ""
	var best_speed := -1.0
	for r in RoadSim.roads(gs):
		if RoadSim.dist_point_segment(p, RoadSim.seg_a(r), RoadSim.seg_b(r)) <= reach:
			var sp := float(RoadSim.kind_def(str(r["kind"])).get("speed", 1.0))
			if sp > best_speed:
				best_speed = sp
				best = str(r["kind"])
	return {"ok": best != "", "best": best, "trucks": best in ["empedrado", "cemento"]}


# --- Rutas a otros pueblos trazadas a mano -------------------------------------------------------

## Camino automático (el de siempre) de la plaza al borde oeste.
static func auto_trade_path(gs) -> PackedVector2Array:
	var seed_v := float(int(gs.settings.get("seed", 1)) % 1000)
	var key := "%d" % int(seed_v)
	if _auto_cache.has(key):
		return _auto_cache[key]
	var path := PackedVector2Array()
	var half: float = gs.MAP_SIZE * 0.5
	var x := -8.5
	while x > -half + 0.5:
		var t := (-x - 8.5) / half
		path.append(Vector2(x, sin(x * 0.021 + seed_v) * 9.0 * t + sin(x * 0.053 + seed_v * 0.3) * 3.0 * t))
		x -= 2.0
	path.append(Vector2(-half + 0.3, path[path.size() - 1].y))
	_auto_cache[key] = path
	return path


static func auto_trade_len(gs) -> float:
	return poly_length(auto_trade_path(gs))


static func _pending(gs, tid: String) -> Dictionary:
	var tp: Dictionary = state(gs)["trade_paths"]
	if not tp.has(tid):
		tp[tid] = {}
	return tp[tid]


## Polilínea manual del camino (rail=false) o de la vía férrea (rail=true); vacía = automática.
static func trade_path_of(gs, tid: String, rail := false) -> PackedVector2Array:
	var key := "rail_path" if rail else "path"
	var c := TradeSim.connection(gs, tid)
	if not c.is_empty() and c.has(key):
		return _from_arr(c[key])
	var p: Dictionary = state(gs)["trade_paths"].get(tid, {})
	if p.has(key):
		return _from_arr(p[key])
	return PackedVector2Array()


static func has_manual_path(gs, tid: String, rail := false) -> bool:
	return not trade_path_of(gs, tid, rail).is_empty()


## Factor de distancia por el trazado: largo real / largo automático (acotado).
static func path_factor(gs, length: float) -> float:
	var tp := sub("trade_path")
	return clampf(length / maxf(1.0, auto_trade_len(gs)), float(tp.get("factor_min", 0.9)), float(tp.get("factor_max", 1.25)))


## Presupuesto de un trazado hacia otro pueblo: {points, length, factor, fee, extra, reason, mode}.
## mode: "open" (abre la ruta con este trazado), "rail" (construye la vía con este trazado),
## "reroute" (cambia el trazado de algo ya abierto o en obra: cuesta el tramo local).
static func trade_plan(gs, tid: String, ctrl: PackedVector2Array, rail := false) -> Dictionary:
	var tp := sub("trade_path")
	var out := {"points": PackedVector2Array(), "length": 0.0, "factor": 1.0, "fee": 0.0, "extra": 0.0, "reason": "", "mode": "reroute", "days": 0}
	var t := TradeSim.town(gs, tid)
	if t.is_empty():
		out["reason"] = "Ese pueblo no existe"
		return out
	if ctrl.size() < 2:
		out["reason"] = "Pon al menos dos puntos: desde la salida del pueblo hasta el borde del mapa"
		return out
	var c2 := ctrl.duplicate()
	var first: Vector2 = c2[0]
	var start_ok := first.length() <= float(tp.get("start_reach", 32.0))
	if not start_ok and not RoadSim.roads(gs).is_empty():
		var sp := snap_to_road(gs, first)
		if sp.distance_to(first) <= float(tp.get("road_start_reach", 8.0)):
			start_ok = true
			c2[0] = sp
	if not start_ok and rail:
		for b in gs.buildings:
			if str(b.get("type", "")) == "estacion_tren" and Vector2(float(b["x"]), float(b["z"])).distance_to(first) <= float(tp.get("station_reach", 16.0)):
				start_ok = true
	if not start_ok:
		out["reason"] = "Empieza en la salida del pueblo (a menos de %d m de la plaza%s)" % [int(tp.get("start_reach", 32.0)), ", de una carretera o de la estación de tren" if rail else " o de una carretera"]
		return out
	var half: float = gs.MAP_SIZE * 0.5
	var last: Vector2 = c2[c2.size() - 1]
	var edge_d := half - maxf(absf(last.x), absf(last.y))
	if edge_d > float(tp.get("edge_margin", 12.0)):
		out["reason"] = "Termina en el borde del mapa (faltan %d m)" % int(edge_d)
		return out
	# Pegar el último punto al borde más cercano.
	if absf(last.x) >= absf(last.y):
		last.x = signf(last.x) * (half - 0.3)
	else:
		last.y = signf(last.y) * (half - 0.3)
	c2[c2.size() - 1] = last
	var pts := smooth(c2, float(tp.get("sample_step", 5.0)))
	out["points"] = pts
	out["ctrl"] = c2
	var length := poly_length(pts)
	out["length"] = length
	for p in pts:
		if not _inside_map(gs, p, 0.0):
			out["reason"] = "Se sale del mapa"
			return out
	var wp := water_profile(gs, pts)
	if float(wp["longest"]) > float(tp.get("bridge_max", 50.0)):
		out["reason"] = "El agua es muy ancha: el puente cubre como máximo %d m" % int(tp.get("bridge_max", 50.0))
		return out
	out["bridge"] = float(wp["wet"])
	var f := path_factor(gs, length)
	out["factor"] = f
	var pm: float = gs.price_mult()
	var conn := TradeSim.connection(gs, tid)
	var proj := TradeSim.project(gs, tid)
	if rail:
		if conn.is_empty():
			out["reason"] = "Primero abre la ruta con ese pueblo"
			return out
		if not bool(conn.get("rail", false)) and not conn.get("work", {}).has("rail"):
			out["mode"] = "rail"
			var why := TradeSim.rail_block_reason(gs, tid)
			if why != "":
				out["reason"] = why
				return out
			var q := TradeSim.rail_quote(gs, tid)
			out["extra"] = float(q["cost"]) * (f - 1.0)
			out["days"] = int(round(float(q["days"]) * (f - 1.0)))
			out["fee"] = float(q["cost"]) + float(out["extra"])
		else:
			out["fee"] = length * float(tp.get("rail_per_m", 5.0)) * pm
	else:
		if conn.is_empty() and proj.is_empty():
			out["mode"] = "open"
			var why := TradeSim.open_block_reason(gs, tid)
			if why != "" and not why.begins_with("Necesitas"):
				out["reason"] = why
				return out
			var q := TradeSim.connection_cost(gs, tid)
			out["extra"] = float(q["road"]) * (f - 1.0)
			out["days"] = int(round(float(q["days"]) * (f - 1.0)))
			out["fee"] = float(q["total"]) + float(out["extra"])
		else:
			var lvl := int(conn.get("road", 1)) if not conn.is_empty() else 1
			var per: Array = tp.get("reroute_per_m", [0.0, 1.2, 2.5, 6.0])
			out["fee"] = length * float(per[clampi(lvl, 0, per.size() - 1)]) * pm
	if gs.money < float(out["fee"]):
		out["reason"] = "Dinero insuficiente (%s)" % Fmt.money(float(out["fee"]))
	return out


## Aplica un trazado manual: abre la ruta, construye la vía o cambia el trazado. "" o motivo.
static func set_trade_path(gs, tid: String, ctrl: PackedVector2Array, rail := false) -> String:
	var plan := trade_plan(gs, tid, ctrl, rail)
	if str(plan["reason"]) != "":
		return str(plan["reason"])
	var pts: PackedVector2Array = plan["points"]
	var key := "rail_path" if rail else "path"
	match str(plan["mode"]):
		"open":
			var err := TradeSim.open_route(gs, tid)
			if err != "":
				return err
			_charge_trade(gs, float(plan["extra"]))
			var p := TradeSim.project(gs, tid)
			if not p.is_empty():
				p["done_day"] = int(p["done_day"]) + int(plan["days"])
				p["total_days"] = maxi(1, int(p["total_days"]) + int(plan["days"]))
				p["cost"] = float(p.get("cost", 0.0)) + float(plan["extra"])
		"rail":
			var err := TradeSim.build_rail(gs, tid)
			if err != "":
				return err
			_charge_trade(gs, float(plan["extra"]))
			var w: Dictionary = TradeSim.connection(gs, tid).get("work", {}).get("rail", {})
			if not w.is_empty():
				w["done_day"] = maxi(gs.today() + 1, int(w["done_day"]) + int(plan["days"]))
		_:
			_charge_trade(gs, float(plan["fee"]))
			gs.notify("Nuevo trazado %s a %s (%d m dentro del mapa)." % ["de la vía férrea" if rail else "del camino", str(TradeSim.town(gs, tid).get("name", "")), int(plan["length"])], "construccion")
	var rec := {key: _to_arr(pts), key + "_len": float(plan["length"]), key + "_ctrl": _to_arr(plan["ctrl"])}
	var pend := _pending(gs, tid)
	pend.merge(rec, true)
	_apply_paths(gs)
	var us: Dictionary = GridSim.state(gs)   # La entrada regional de la red eléctrica sigue el trazado.
	us["version"] = int(us.get("version", 0)) + 1
	state(gs)["path_version"] = int(state(gs).get("path_version", 0)) + 1
	return ""


static func _charge_trade(gs, amount: float) -> void:
	if absf(amount) < 0.001:
		return
	gs.add_money(-amount)
	if amount > 0.0:
		gs.add_counter("trade_investment", amount)
	_stat(gs, "trade_paths_cost", amount)


## Copia los trazados pendientes a sus conexiones (al abrirse la ruta) y ajusta la distancia.
static func _apply_paths(gs) -> void:
	var tp: Dictionary = state(gs)["trade_paths"]
	for tid in tp.keys():
		var c := TradeSim.connection(gs, str(tid))
		if c.is_empty():
			continue
		var rec: Dictionary = tp[tid]
		for k in rec:
			c[k] = rec[k]
		tp.erase(tid)
		_update_distance(gs, c)


static func _update_distance(gs, c: Dictionary) -> void:
	if not c.has("path"):
		return
	if not c.has("base_distance"):
		c["base_distance"] = float(c.get("distance", 50.0))
	c["distance"] = snappedf(float(c["base_distance"]) * path_factor(gs, float(c.get("path_len", auto_trade_len(gs)))), 0.1)


## Líneas a dibujar hacia otros pueblos: [{tid, points, level, rail, rail_points, progress}].
## Las rutas sin trazado manual comparten el camino automático (como antes).
static func trade_lines(gs) -> Array:
	var out := []
	var auto := {"tid": "", "points": auto_trade_path(gs), "level": 0, "rail": false, "rail_points": PackedVector2Array(), "progress": 0.0, "manual": false}
	var has_auto := false
	for c in TradeSim.connected_towns(gs):
		var tid := str(c["town_id"])
		var mp := trade_path_of(gs, tid)
		var rp := trade_path_of(gs, tid, true)
		if mp.is_empty():
			has_auto = true
			auto["level"] = maxi(int(auto["level"]), int(c.get("road", 1)))
			if bool(c.get("rail", false)):
				if rp.is_empty():
					auto["rail"] = true
				else:
					out.append({"tid": tid, "points": PackedVector2Array(), "level": 0, "rail": true, "rail_points": rp, "progress": 1.0, "manual": true})
			continue
		out.append({"tid": tid, "points": mp, "level": int(c.get("road", 1)), "rail": bool(c.get("rail", false)), "rail_points": rp, "progress": 1.0, "manual": true})
	for p in gs.trade.get("projects", []):
		var tid := str(p["town_id"])
		var total := maxf(1.0, float(p.get("total_days", 1)))
		var prog := clampf(1.0 - float(int(p["done_day"]) - gs.today()) / total, 0.05, 1.0)
		var mp := trade_path_of(gs, tid)
		if mp.is_empty():
			has_auto = true
			auto["progress"] = maxf(float(auto["progress"]), prog)
		else:
			out.append({"tid": tid, "points": mp, "level": 0, "rail": false, "rail_points": PackedVector2Array(), "progress": prog, "manual": true})
	if has_auto:
		if int(auto["level"]) > 0:
			auto["progress"] = 1.0
		out.push_front(auto)
	return out


## ¿Está el punto cerca de algún camino o vía a otros pueblos? (entrada de la red regional, GridSim)
static func near_trade_path(gs, p: Vector2, r: float) -> bool:
	var any_auto: bool = TradeSim.connected_towns(gs).is_empty() and gs.trade.get("projects", []).is_empty()
	for c in TradeSim.connected_towns(gs):
		if not c.has("path"):
			any_auto = true
		for k in ["path", "rail_path"]:
			if c.has(k) and dist_to_poly(p, _from_arr(c[k])) <= r:
				return true
	for pr in gs.trade.get("projects", []):
		if not has_manual_path(gs, str(pr["town_id"])):
			any_auto = true
	if any_auto and p.x <= -8.5 and absf(p.y - GridSim.trade_path_z(gs, p.x)) <= r:
		return true
	return false


# --- Paraderos ---------------------------------------------------------------------------------

static func stops(gs) -> Array:
	return state(gs)["stops"]


static func stop_pos(s: Dictionary) -> Vector2:
	return Vector2(float(s["x"]), float(s["z"]))


static func get_stop(gs, sid: int) -> Dictionary:
	for s in stops(gs):
		if int(s["id"]) == sid:
			return s
	return {}


static func bus_kinds() -> Array:
	return sub("bus").get("road_kinds", [])


static func stop_cost(gs) -> float:
	return float(sub("stops").get("cost", 40)) * gs.price_mult()


static func stop_block_reason(gs, p: Vector2) -> String:
	if not gs.has_tech(str(sub("bus").get("tech", ""))):
		return "Requiere investigar: %s" % GameData.tech_label(str(sub("bus").get("tech", "")))
	if not RoadSim._zone_unlocked(gs, p):
		return "Terreno del gobierno: cómpralo primero"
	var near := false
	for r in RoadSim.roads(gs):
		if bus_kinds().has(str(r["kind"])) and RoadSim.dist_point_segment(p, RoadSim.seg_a(r), RoadSim.seg_b(r)) <= float(sub("stops").get("road_reach", 6.0)):
			near = true
			break
	if not near:
		return "El paradero va junto a una carretera empedrada o de cemento"
	for s in stops(gs):
		if stop_pos(s).distance_to(p) < float(sub("stops").get("min_spacing", 12.0)):
			return "Muy cerca de otro paradero"
	if gs.money < stop_cost(gs):
		return "Dinero insuficiente (%s)" % Fmt.money(stop_cost(gs))
	return ""


static func add_stop(gs, p: Vector2) -> Dictionary:
	var why := stop_block_reason(gs, p)
	if why != "":
		return {"error": why}
	gs.add_money(-stop_cost(gs))
	_stat(gs, "stops_cost", stop_cost(gs))
	var id := _next_id(gs)
	var s := {"id": id, "x": snappedf(p.x, 0.01), "z": snappedf(p.y, 0.01), "name": "Paradero %d" % (stops(gs).size() + 1)}
	stops(gs).append(s)
	for r in routes(gs):
		if bool(r.get("auto", false)):
			_refresh_auto_route(gs, r)
	return {"stop": s}


static func remove_stop(gs, sid: int) -> void:
	var ss := stops(gs)
	for i in range(ss.size() - 1, -1, -1):
		if int(ss[i]["id"]) == sid:
			ss.remove_at(i)
	for r in routes(gs):
		var arr: Array = r["stops"]
		for i in range(arr.size() - 1, -1, -1):
			if int(arr[i]) == sid:
				arr.remove_at(i)


# --- Empresa de buses y buses -------------------------------------------------------------------

static func is_depot_type(def: Dictionary) -> bool:
	return bool(def.get("bus_company", false))


static func depots(gs) -> Array:
	var out := []
	for b in gs.buildings:
		if gs.owned_by_player(b) and is_depot_type(gs.building_def(b)):
			out.append(b)
	return out


static func bus_garage(gs, b: Dictionary) -> int:
	return int(gs.level_def(b).get("bus_garage", 0))


static func bus_capacity(gs, depot: Dictionary) -> int:
	return int(round(float(sub("bus").get("capacity", 40)) * float(gs.level_def(depot).get("bus_capacity_mult", 1.0))))


static func buses(gs) -> Array:
	return state(gs)["buses"]


static func buses_of(gs, depot_id: int) -> Array:
	var out := []
	for v in buses(gs):
		if int(v["depot"]) == depot_id:
			out.append(v)
	return out


static func bus_price(gs) -> float:
	return float(sub("bus").get("price", 4500)) * gs.price_mult()


static func buy_block_reason(gs, depot: Dictionary) -> String:
	var tech := str(sub("bus").get("tech", "transporte_publico"))
	if not gs.has_tech(tech):
		return "Requiere investigar: %s" % GameData.tech_label(tech)
	if depot.is_empty() or not is_depot_type(gs.building_def(depot)):
		return "Los buses se compran en la Empresa de buses"
	if str(depot.get("status", "")) != "activo":
		return "El edificio no está activo"
	if buses_of(gs, int(depot["id"])).size() >= bus_garage(gs, depot):
		return "No caben más buses (%d): mejora el edificio" % bus_garage(gs, depot)
	if gs.money < bus_price(gs):
		return "Dinero insuficiente (%s)" % Fmt.money(bus_price(gs))
	return ""


static func buy_bus(gs, depot: Dictionary) -> Dictionary:
	var why := buy_block_reason(gs, depot)
	if why != "":
		return {"error": why}
	BusinessSim.pay(gs, depot, bus_price(gs), "obras")
	var id := _next_id(gs)
	var rid := -1
	for r in routes(gs):
		if int(r["depot"]) == int(depot["id"]):
			rid = int(r["id"])
			break
	var v := {"id": id, "depot": int(depot["id"]), "route": rid, "name": "%s %d" % [str(sub("bus").get("unit", "Bus")), buses(gs).size() + 1], "bought": gs.today()}
	buses(gs).append(v)
	return {"bus": v}


static func sell_bus(gs, bus_id: int) -> String:
	for v in buses(gs):
		if int(v["id"]) == bus_id:
			var refund := bus_price(gs) * float(sub("bus").get("sell_ratio", 0.4))
			var d: Dictionary = gs.get_building(int(v["depot"]))
			buses(gs).erase(v)
			if d.is_empty():
				gs.add_money(refund)
			else:
				BusinessSim.earn(gs, d, refund, "ventas")
			return ""
	return "Ese bus no existe"


static func assign_bus(gs, bus_id: int, route_id: int) -> void:
	for v in buses(gs):
		if int(v["id"]) == bus_id:
			v["route"] = route_id


# --- Rutas de bus -------------------------------------------------------------------------------

static func routes(gs) -> Array:
	return state(gs)["routes"]


static func get_route(gs, rid: int) -> Dictionary:
	for r in routes(gs):
		if int(r["id"]) == rid:
			return r
	return {}


static func _depot_pos(gs, depot_id: int) -> Vector2:
	var d: Dictionary = gs.get_building(depot_id)
	return Vector2(float(d.get("x", 0.0)), float(d.get("z", 0.0)))


## Paraderos unidos por carretera (para bus) al depósito, en orden de vecino más cercano.
static func auto_route_stops(gs, depot_id: int) -> Array:
	var dp := _depot_pos(gs, depot_id)
	var left := []
	for s in stops(gs):
		if RoadSim.connected(gs, dp, stop_pos(s), bus_kinds()):
			left.append(s)
	var out := []
	var cur := dp
	while not left.is_empty():
		var bi := 0
		for i in range(left.size()):
			if cur.distance_to(stop_pos(left[i])) < cur.distance_to(stop_pos(left[bi])):
				bi = i
		out.append(int(left[bi]["id"]))
		cur = stop_pos(left[bi])
		left.remove_at(bi)
	return out


static func route_block_reason(gs, depot_id: int, stop_ids: Array) -> String:
	var tech := str(sub("bus").get("tech", "transporte_publico"))
	if not gs.has_tech(tech):
		return "Requiere investigar: %s" % GameData.tech_label(tech)
	var d: Dictionary = gs.get_building(depot_id)
	if d.is_empty() or not is_depot_type(gs.building_def(d)):
		return "Elige una empresa de buses"
	if stop_ids.size() < 2:
		return "Una ruta necesita al menos dos paraderos unidos por carretera"
	var prev := _depot_pos(gs, depot_id)
	for sid in stop_ids:
		var s := get_stop(gs, int(sid))
		if s.is_empty():
			return "Un paradero ya no existe"
		if not RoadSim.connected(gs, prev, stop_pos(s), bus_kinds()):
			return "«%s» no está unido por carretera empedrada o de cemento al anterior%s" % [str(s["name"]), " (o al depósito)" if prev == _depot_pos(gs, depot_id) else ""]
		prev = stop_pos(s)
	return ""


static func create_route(gs, depot_id: int, stop_ids: Array, auto := false) -> Dictionary:
	if auto:
		stop_ids = auto_route_stops(gs, depot_id)
	var why := route_block_reason(gs, depot_id, stop_ids)
	if why != "":
		return {"error": why}
	var id := _next_id(gs)
	var ids := []
	for s in stop_ids:
		ids.append(int(s))
	var r := {"id": id, "name": "Ruta %d" % (routes(gs).size() + 1), "depot": depot_id, "stops": ids, "auto": auto,
		"month_riders": 0, "month_income": 0.0, "last_riders": 0, "last_income": 0.0}
	routes(gs).append(r)
	for v in buses_of(gs, depot_id):
		if int(v.get("route", -1)) < 0 or get_route(gs, int(v["route"])).is_empty():
			v["route"] = id
	return {"route": r}


static func remove_route(gs, rid: int) -> void:
	var rs := routes(gs)
	for i in range(rs.size() - 1, -1, -1):
		if int(rs[i]["id"]) == rid:
			rs.remove_at(i)
	for v in buses(gs):
		if int(v.get("route", -1)) == rid:
			v["route"] = -1


static func _refresh_auto_route(gs, r: Dictionary) -> void:
	var ids := auto_route_stops(gs, int(r["depot"]))
	if ids.size() >= 2:
		r["stops"] = ids


static func route_length(gs, r: Dictionary) -> float:
	var prev := _depot_pos(gs, int(r["depot"]))
	var total := 0.0
	for sid in r["stops"]:
		var s := get_stop(gs, int(sid))
		if s.is_empty():
			continue
		total += prev.distance_to(stop_pos(s))
		prev = stop_pos(s)
	return total * float(sub("bus").get("route_factor", 1.25))


## Estado de una ruta: {ok, reason, buses, operating, capacity (pasajeros por día), loops, length}.
static func route_status(gs, r: Dictionary, drivers_left := -1) -> Dictionary:
	var bc := sub("bus")
	var assigned := 0
	for v in buses(gs):
		if int(v.get("route", -1)) == int(r["id"]):
			assigned += 1
	var depot: Dictionary = gs.get_building(int(r["depot"]))
	var st := {"ok": false, "reason": "", "buses": assigned, "operating": 0, "capacity": 0, "loops": 0, "length": route_length(gs, r)}
	if depot.is_empty() or str(depot.get("status", "")) != "activo":
		st["reason"] = "La empresa de buses no está activa"
		return st
	var why := route_block_reason(gs, int(r["depot"]), r["stops"])
	if why != "":
		st["reason"] = why
		return st
	var drivers := drivers_left
	if drivers < 0:
		drivers = LogisticsSim.crew_size(gs, depot)
	var op := mini(assigned, drivers)
	st["operating"] = op
	if assigned <= 0:
		st["reason"] = "Sin buses asignados"
		return st
	if op <= 0:
		st["reason"] = "Contrata conductores en %s" % gs.building_label(depot)
		return st
	var one_way := float(st["length"]) / maxf(1.0, float(bc.get("speed", 1200.0)))
	var loops := clampi(int(float(bc.get("peak_window", 0.25)) / maxf(0.001, one_way * 2.0)), 1, int(bc.get("max_loops", 6)))
	st["loops"] = loops
	st["capacity"] = op * bus_capacity(gs, depot) * loops
	st["ok"] = true
	return st


## Estado de todas las rutas repartiendo los conductores de cada depósito.
static func all_route_status(gs) -> Dictionary:
	var out := {}
	var drivers := {}
	for r in routes(gs):
		var did := int(r["depot"])
		if not drivers.has(did):
			var d: Dictionary = gs.get_building(did)
			drivers[did] = LogisticsSim.crew_size(gs, d) if not d.is_empty() else 0
		var st := route_status(gs, r, int(drivers[did]))
		drivers[did] = maxi(0, int(drivers[did]) - int(st["operating"]))
		out[int(r["id"])] = st
	return out


# --- Parqueaderos ------------------------------------------------------------------------------

static func parkings(gs) -> Array:
	var out := []
	for b in gs.buildings:
		if gs.owned_by_player(b) and str(b.get("status", "")) == "activo" and int(gs.level_def(b).get("parking_capacity", 0)) > 0:
			out.append(b)
	return out


static func parking_capacity(gs, b: Dictionary) -> int:
	return int(gs.level_def(b).get("parking_capacity", 0))


static func parking_fee(gs) -> float:
	return float(state(gs).get("parking_fee", 0.05)) * gs.price_mult()


static func fare(gs) -> float:
	return float(state(gs).get("fare", 0.1)) * gs.price_mult()


static func set_fare(gs, v: float) -> void:
	state(gs)["fare"] = clampf(snappedf(v, 0.01), 0.0, float(cfg().get("fare_max", 1.0)))


static func set_parking_fee(gs, v: float) -> void:
	state(gs)["parking_fee"] = clampf(snappedf(v, 0.01), 0.0, float(sub("parking").get("fee_max", 0.5)))


static func _near_parking(gs, p: Vector2, left: Dictionary) -> int:
	var reach := float(sub("parking").get("reach", 40.0))
	var best := -1
	var best_d := INF
	for b in parkings(gs):
		var bid := int(b["id"])
		if int(left.get(bid, parking_capacity(gs, b))) <= 0:
			continue
		var d := p.distance_to(Vector2(float(b["x"]), float(b["z"])))
		if d <= reach and d < best_d:
			best_d = d
			best = bid
	return best


# --- Trayecto al trabajo -----------------------------------------------------------------------

static func _pos(b: Dictionary) -> Vector2:
	return Vector2(float(b["x"]), float(b["z"]))


static func cars_available(gs) -> bool:
	return gs.has_tech(str(sub("commute").get("car_tech", "automovil")))


static func has_car(gs, c) -> bool:
	return cars_available(gs) and c.money >= float(sub("commute").get("car_wealth", 300.0)) * gs.price_level()


## Paraderos a menos de `reach` de un punto.
static func _stops_near(gs, p: Vector2) -> Array:
	var reach := float(sub("stops").get("reach", 45.0))
	var out := []
	for s in stops(gs):
		if stop_pos(s).distance_to(p) <= reach:
			out.append(int(s["id"]))
	return out


## Calcula cómo llega cada trabajador, cobra pasajes y parqueo (dinero del vecino → tus negocios).
static func commute_daily(gs) -> void:
	var T := state(gs)
	var cc := sub("commute")
	var walk_ok := float(cc.get("walk_ok", 110.0))
	var status := all_route_status(gs)
	var cap := {}
	for rid in status:
		if bool(status[rid]["ok"]):
			cap[rid] = int(status[rid]["capacity"])
	var left := {}
	var use := {}
	var commute := {}
	var fare2 := fare(gs) * 2.0
	var pfee := parking_fee(gs)
	var share := float(cc.get("fare_share_max", 0.25))
	for c in gs.citizens.values():
		if c.job_kind != "empleo" or c.job_id < 0 or gs.is_player(c.id):
			continue
		var home: Dictionary = gs.get_building(c.home_id)
		var job: Dictionary = gs.get_building(c.job_id)
		if home.is_empty() or job.is_empty():
			continue
		var hp := _pos(home)
		var jp := _pos(job)
		var d := hp.distance_to(jp)
		if d <= walk_ok:
			continue
		var mode := MODE_FAR
		if has_car(gs, c):
			var pk := _near_parking(gs, jp, left)
			if pk >= 0 and RoadSim.connected(gs, hp, jp):
				var pb: Dictionary = gs.get_building(pk)
				left[pk] = int(left.get(pk, parking_capacity(gs, pb))) - 1
				use[str(pk)] = int(use.get(str(pk), 0)) + 1
				if pfee > 0.0 and c.money >= pfee:
					c.money -= pfee
					BusinessSim.earn(gs, pb, pfee, "ventas")
					_stat(gs, "parking_income", pfee)
				mode = MODE_CAR
		if mode == MODE_FAR and not cap.is_empty() and c.money >= fare2 and fare2 <= maxf(0.01, c.wage) * share:
			var a := _stops_near(gs, hp)
			var b := _stops_near(gs, jp)
			if not a.is_empty() and not b.is_empty():
				for r in routes(gs):
					var rid := int(r["id"])
					if int(cap.get(rid, 0)) <= 0:
						continue
					if _route_serves(r, a, b):
						cap[rid] = int(cap[rid]) - 1
						if fare2 > 0.0:
							c.money -= fare2
							var dep: Dictionary = gs.get_building(int(r["depot"]))
							BusinessSim.earn(gs, dep, fare2, "ventas")
						r["month_riders"] = int(r.get("month_riders", 0)) + 1
						r["month_income"] = float(r.get("month_income", 0.0)) + fare2
						_stat(gs, "riders", 1.0)
						_stat(gs, "fares", fare2)
						mode = MODE_BUS
						break
		commute[str(c.id)] = {"m": mode, "d": snappedf(d, 0.1)}
	T["commute"] = commute
	T["parking_use"] = use


static func _route_serves(r: Dictionary, a: Array, b: Array) -> bool:
	var has_a := false
	var has_b := false
	var arr: Array = r["stops"]
	for sid in arr:
		if a.has(int(sid)):
			has_a = true
		if b.has(int(sid)):
			has_b = true
	if not has_a or not has_b:
		return false
	# Deben ser paraderos distintos (si el único cercano a ambos es el mismo, se camina).
	for x in a:
		for y in b:
			if int(x) != int(y) and arr.has(int(x)) and arr.has(int(y)):
				return true
	return false


## Modo de llegada guardado del trabajador ("" = vive cerca y camina).
static func commute_of(gs, c) -> Dictionary:
	return state(gs)["commute"].get(str(c.id), {})


## Multiplicador de productividad por el trayecto (cansancio al caminar lejos; descanso en bus/auto).
static func commute_mult(gs, c) -> float:
	var e: Dictionary = gs.transit.get("commute", {}).get(str(c.id), {}) if not gs.transit.is_empty() else {}
	if e.is_empty():
		return 1.0
	var cc := sub("commute")
	match str(e.get("m", "")):
		MODE_BUS:
			return float(cc.get("bus_productivity", 1.02))
		MODE_CAR:
			return float(cc.get("car_productivity", 1.04))
		_:
			var walk_ok := float(cc.get("walk_ok", 110.0))
			var over := clampf((float(e.get("d", 0.0)) - walk_ok) / walk_ok, 0.0, 1.0)
			return 1.0 - float(cc.get("walk_penalty_max", 0.1)) * over


## Felicidad objetivo por el trayecto (PopulationSim._happiness).
static func happiness_delta(gs, c) -> float:
	var e: Dictionary = gs.transit.get("commute", {}).get(str(c.id), {}) if not gs.transit.is_empty() else {}
	if e.is_empty():
		return 0.0
	var cc := sub("commute")
	match str(e.get("m", "")):
		MODE_BUS:
			return float(cc.get("bus_happiness", 1.5))
		MODE_CAR:
			return float(cc.get("car_happiness", 2.5))
		_:
			var walk_ok := float(cc.get("walk_ok", 110.0))
			return float(cc.get("walk_happiness", -3.0)) * clampf((float(e.get("d", 0.0)) - walk_ok) / walk_ok, 0.25, 1.0)


# --- Acceso de los negocios modernos (parqueadero o bus) ----------------------------------------

static func access_active(gs) -> bool:
	return gs.has_tech(str(sub("access").get("tech", "automovil")))


static func _served_stops(gs, status: Dictionary) -> Array:
	var out := []
	for r in routes(gs):
		if bool(status.get(int(r["id"]), {}).get("ok", false)):
			for sid in r["stops"]:
				if not out.has(int(sid)):
					out.append(int(sid))
	return out


## ¿Tiene el negocio parqueadero o paradero con bus cerca? {parking, stop}
static func access_of(gs, b: Dictionary, served: Array = []) -> Dictionary:
	var p := _pos(b)
	var reach := float(sub("access").get("reach", 40.0))
	var has_parking := false
	for pk in parkings(gs):
		if int(pk["id"]) != int(b["id"]) and p.distance_to(_pos(pk)) <= reach:
			has_parking = true
			break
	var has_stop := false
	for s in stops(gs):
		if served.has(int(s["id"])) and p.distance_to(stop_pos(s)) <= float(sub("stops").get("reach", 45.0)):
			has_stop = true
			break
	return {"parking": has_parking, "stop": has_stop}


static func _access_daily(gs) -> void:
	var out := {}
	if access_active(gs):
		var served := _served_stops(gs, all_route_status(gs))
		for b in gs.buildings:
			if not gs.owned_by_player(b) or not BusinessSim.is_business(b) or int(gs.level_def(b).get("jobs", 0)) <= 0:
				continue
			var a := access_of(gs, b, served)
			if not bool(a["parking"]) and not bool(a["stop"]):
				out[str(b["id"])] = true
	state(gs)["no_access"] = out


## Penalización de productividad de un negocio moderno sin parqueadero ni bus.
static func access_mult(gs, b: Dictionary) -> float:
	if gs.transit.is_empty() or not gs.transit.get("no_access", {}).has(str(b["id"])):
		return 1.0
	return float(sub("access").get("penalty", 0.95))


# --- Simulación ---------------------------------------------------------------------------------

static func daily(gs) -> void:
	state(gs)
	_apply_paths(gs)
	_prune(gs)
	for r in routes(gs):
		if bool(r.get("auto", false)):
			_refresh_auto_route(gs, r)
	commute_daily(gs)
	_bus_costs(gs)
	_access_daily(gs)


static func monthly(gs) -> void:
	var T := state(gs)
	T["last_month"] = T["month"]
	T["month"] = {}
	for r in routes(gs):
		r["last_riders"] = int(r.get("month_riders", 0))
		r["last_income"] = float(r.get("month_income", 0.0))
		r["month_riders"] = 0
		r["month_income"] = 0.0


## Empresas de buses demolidas: sus buses se venden (40 %); paraderos que ya no existen salen de las rutas.
static func _prune(gs) -> void:
	for v in buses(gs).duplicate():
		if gs.get_building(int(v["depot"])).is_empty():
			var refund := bus_price(gs) * float(sub("bus").get("sell_ratio", 0.4))
			buses(gs).erase(v)
			gs.add_money(refund)
			gs.notify("Se vendió %s de una empresa de buses demolida por %s." % [str(v["name"]), Fmt.money(refund)], "negocio")
	for r in routes(gs).duplicate():
		if gs.get_building(int(r["depot"])).is_empty():
			remove_route(gs, int(r["id"]))


## Mantenimiento de cada bus y combustible de los que circulan (paga la empresa de buses).
static func _bus_costs(gs) -> void:
	var bc := sub("bus")
	var pm: float = gs.price_mult()
	var status := all_route_status(gs)
	var fuel_price := float(GameData.extra("trade").get("fuel_price", 1.0))
	for d in depots(gs):
		var n := buses_of(gs, int(d["id"])).size()
		if n <= 0:
			continue
		var upkeep := float(bc.get("upkeep", 1.0)) * n * pm
		BusinessSim.pay(gs, d, upkeep, "mantenimiento")
		_stat(gs, "bus_upkeep", upkeep)
		var fuel := 0.0
		for r in routes(gs):
			if int(r["depot"]) != int(d["id"]):
				continue
			var st: Dictionary = status.get(int(r["id"]), {})
			if not bool(st.get("ok", false)):
				continue
			# Mañana y tarde: `loops` vueltas de ida y regreso por bus.
			var km := float(st["length"]) * 2.0 * 2.0 * int(st["loops"]) / 1000.0
			fuel += float(bc.get("fuel_per_km", 3.0)) * km * fuel_price * pm * int(st["operating"])
		if fuel > 0.0:
			BusinessSim.pay(gs, d, fuel, "insumos")
			_stat(gs, "bus_fuel", fuel)


# --- Resumen e interfaz --------------------------------------------------------------------------

static func commute_counts(gs, job_id := -1) -> Dictionary:
	var out := {"pie": 0, MODE_FAR: 0, MODE_BUS: 0, MODE_CAR: 0}
	var cm: Dictionary = state(gs)["commute"]
	for c in gs.citizens.values():
		if c.job_kind != "empleo" or c.job_id < 0 or gs.is_player(c.id):
			continue
		if job_id >= 0 and c.job_id != job_id:
			continue
		var m := str(cm.get(str(c.id), {}).get("m", "pie"))
		out[m] = int(out.get(m, 0)) + 1
	return out


## Líneas del panel de edificio: acceso por carretera, llegada de los trabajadores y parqueadero/bus.
static func panel_lines(gs, b: Dictionary) -> String:
	if Housing.is_home(b) or str(b.get("status", "")) == "construccion":
		return ""
	var s := ""
	var ra := road_access(gs, b)
	if bool(ra["ok"]):
		var who := "carretas"
		if bool(ra["trucks"]):
			who = "carretas, carros de vapor y camiones"
		s += "Carretera: [color=#6c6]con acceso[/color] (%s) · entran %s\n" % [RoadSim.kind_label(str(ra["best"])).to_lower(), who]
	else:
		s += "Carretera: [color=#aaa]sin acceso[/color] — funciona igual; la carga va a pie o en mula (carretas y camiones necesitan un camino a menos de %d m)\n" % int(RoadSim.cfg().get("reach", 12.0))
	if int(gs.level_def(b).get("parking_capacity", 0)) > 0:
		s += "Parqueadero: %d / %d autos hoy · tarifa %s por día\n" % [int(state(gs)["parking_use"].get(str(b["id"]), 0)), parking_capacity(gs, b), Fmt.money2(parking_fee(gs))]
	if gs.owned_by_player(b) and BusinessSim.is_business(b) and int(gs.level_def(b).get("jobs", 0)) > 0:
		var cc := commute_counts(gs, int(b["id"]))
		var total := int(cc["pie"]) + int(cc[MODE_FAR]) + int(cc[MODE_BUS]) + int(cc[MODE_CAR])
		if total > 0:
			s += "Llegan: %d a pie, %d en bus, %d en auto" % [int(cc["pie"]), int(cc[MODE_BUS]), int(cc[MODE_CAR])]
			if int(cc[MODE_FAR]) > 0:
				s += " · [color=#e9b949]%d caminan más de %d m (cansados, rinden menos)[/color]" % [int(cc[MODE_FAR]), int(sub("commute").get("walk_ok", 110.0))]
			s += "\n"
		if access_active(gs):
			var a := access_of(gs, b, _served_stops(gs, all_route_status(gs)))
			if bool(a["parking"]) or bool(a["stop"]):
				s += "Acceso moderno: [color=#6c6]%s[/color]\n" % " y ".join(([] if not bool(a["parking"]) else ["parqueadero"]) + ([] if not bool(a["stop"]) else ["paradero de bus"]))
			else:
				s += "Acceso moderno: [color=#e9b949]sin parqueadero ni paradero de bus cerca (−%d%% productividad)[/color]\n" % int(round((1.0 - float(sub("access").get("penalty", 0.95))) * 100.0))
	return s


static func summary(gs) -> Dictionary:
	var T := state(gs)
	var status := all_route_status(gs)
	var op := 0
	for rid in status:
		op += int(status[rid]["operating"])
	return {"buses": buses(gs).size(), "operating": op, "routes": routes(gs).size(), "stops": stops(gs).size(),
		"riders_month": int(float(T["month"].get("riders", 0.0))), "riders_last": int(float(T["last_month"].get("riders", 0.0))),
		"fares_month": float(T["month"].get("fares", 0.0)), "fares_last": float(T["last_month"].get("fares", 0.0)),
		"costs_last": float(T["last_month"].get("bus_upkeep", 0.0)) + float(T["last_month"].get("bus_fuel", 0.0)),
		"parking_last": float(T["last_month"].get("parking_income", 0.0)), "commute": commute_counts(gs)}
