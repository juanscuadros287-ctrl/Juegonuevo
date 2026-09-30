class_name RailSim
extends RefCounted
## Vías férreas internas trazadas por puntos (docs/RUTAS_BARCOS.md). Sirven a los TRENES: una ruta de
## tren va entre dos puntos junto a estaciones de tren unidas por rieles, y la cochera de tren debe
## tener su salida junto a la vía. Van aparte de las carreteras (RoadSim) para que carretas y camiones
## no anden por los rieles. La vía a otro pueblo (TransitSim, rail_path) también cuenta como vía.
##
## Estado en GameState.logistics["rails"] = [{id, ctrl:[[x,z]], pts:[[x,z]], length, bridge}],
## "next_rail_id" y "rail_version" (valores por defecto: sin vías).

static var _comp_cache := {}


static func cfg() -> Dictionary:
	return GameData.extra("rutas").get("rail", {})


static func rails(gs) -> Array:
	if not (gs.logistics.get("rails") is Array):
		gs.logistics["rails"] = []
	return gs.logistics["rails"]


static func version(gs) -> int:
	return int(gs.logistics.get("rail_version", 0))


static func _bump(gs) -> void:
	gs.logistics["rail_version"] = version(gs) + 1
	_comp_cache.clear()


static func points_of(r: Dictionary) -> PackedVector2Array:
	return TransitSim._from_arr(r.get("pts", []))


static func total_length(gs) -> float:
	var t := 0.0
	for r in rails(gs):
		t += float(r.get("length", 0.0))
	return t


## Punto pegado a una vía existente (extremo o punto de la vía a menos de `snap`).
static func snap(gs, p: Vector2) -> Vector2:
	var reach := float(cfg().get("snap", 5.0))
	var best := p
	var best_d := reach
	for r in rails(gs):
		var pts := points_of(r)
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var ab := b - a
			var t := clampf((p - a).dot(ab) / maxf(0.0001, ab.length_squared()), 0.0, 1.0)
			var q := a + ab * t
			var d := p.distance_to(q)
			if d < best_d:
				best_d = d
				best = q
	return best


## Presupuesto de una vía por puntos: {points, length, bridge, cost, reason}.
static func plan(gs, ctrl: PackedVector2Array, check_money := true) -> Dictionary:
	var out := {"points": PackedVector2Array(), "length": 0.0, "bridge": 0.0, "cost": 0.0, "reason": ""}
	var tech := str(cfg().get("tech", "ferrocarril"))
	if not gs.has_tech(tech):
		out["reason"] = "Requiere investigar: %s" % GameData.tech_label(tech)
		return out
	if ctrl.size() < 2:
		out["reason"] = "Pon al menos dos puntos"
		return out
	var c2 := ctrl.duplicate()
	c2[0] = snap(gs, c2[0])
	c2[c2.size() - 1] = snap(gs, c2[c2.size() - 1])
	var pts := TransitSim.smooth(c2, float(cfg().get("sample_step", 4.0)))
	out["points"] = pts
	var length := TransitSim.poly_length(pts)
	out["length"] = length
	if length < 3.0:
		out["reason"] = "Vía demasiado corta"
		return out
	for i in range(pts.size() - 1):
		for t in [0.0, 0.5, 1.0]:
			var q: Vector2 = pts[i].lerp(pts[i + 1], t)
			if not TransitSim._inside_map(gs, q, 1.0):
				out["reason"] = "Se sale del mapa"
				return out
			if not RoadSim._zone_unlocked(gs, q):
				out["reason"] = "Pasa por terreno del gobierno: cómpralo primero"
				return out
	var wp := TransitSim.water_profile(gs, pts)
	out["bridge"] = float(wp["wet"])
	if float(wp["longest"]) > float(cfg().get("bridge_max", 40.0)):
		out["reason"] = "El agua es muy ancha: un puente de tren cubre como máximo %d m" % int(cfg().get("bridge_max", 40.0))
		return out
	var pm: float = gs.price_mult()
	var per_m := float(cfg().get("cost_per_m", 5.0)) * pm
	var cost := length * MapSim.terrain_cost_mult_path(pts, gs, false) * per_m + float(wp["wet"]) * per_m * (float(cfg().get("bridge_cost_mult", 4.0)) - 1.0)
	out["cost"] = snappedf(cost, 0.01)
	if check_money and gs.money < cost:
		out["reason"] = "Dinero insuficiente (%s)" % Fmt.money(cost)
	return out


## Construye la vía. Devuelve "" o el motivo.
static func build(gs, ctrl: PackedVector2Array) -> String:
	var p := plan(gs, ctrl)
	if str(p["reason"]) != "":
		return str(p["reason"])
	gs.add_money(-float(p["cost"]))
	var id := int(gs.logistics.get("next_rail_id", 1))
	gs.logistics["next_rail_id"] = id + 1
	rails(gs).append({"id": id, "ctrl": TransitSim._to_arr(ctrl), "pts": TransitSim._to_arr(p["points"]), "length": float(p["length"]),
			"bridge": float(p["bridge"])})
	_bump(gs)
	return ""


static func remove(gs, id: int) -> void:
	var rs := rails(gs)
	for i in range(rs.size() - 1, -1, -1):
		if int(rs[i]["id"]) == id:
			rs.remove_at(i)
	_bump(gs)


## Quita la vía bajo el punto (a menos de 4 m). Devuelve el texto o "".
static func erase_at(gs, p: Vector2) -> String:
	for r in rails(gs):
		if TransitSim.dist_to_poly(p, points_of(r)) <= 4.0:
			var m := float(r.get("length", 0.0))
			remove(gs, int(r["id"]))
			return "Vía férrea quitada (%d m)." % int(m)
	return ""


# --- Red ----------------------------------------------------------------------------------------

## Polilíneas que forman la red: vías internas + vías a otros pueblos (clave "t:<pueblo>").
static func lines(gs) -> Array:
	var out := []
	for r in rails(gs):
		out.append({"key": "r:%d" % int(r["id"]), "pts": points_of(r)})
	for c in TradeSim.connected_towns(gs):
		if bool(c.get("rail", false)):
			var rp := TransitSim.trade_path_of(gs, str(c["town_id"]), true)
			if rp.size() >= 2:
				out.append({"key": "t:%s" % str(c["town_id"]), "pts": rp})
	return out


static func _touch(a: PackedVector2Array, b: PackedVector2Array, d: float) -> bool:
	for p in [a[0], a[a.size() - 1]]:
		if TransitSim.dist_to_poly(p, b) <= d:
			return true
	for p in [b[0], b[b.size() - 1]]:
		if TransitSim.dist_to_poly(p, a) <= d:
			return true
	return false


## Componente conexa de cada línea (índice paralelo a lines()).
static func components(gs) -> Array:
	var ls := lines(gs)
	var key := "%d|%d|%d" % [version(gs), ls.size(), int(gs.logistics.get("road_version", 0)) + TradeSim.connected_towns(gs).size()]
	if _comp_cache.has(key):
		return _comp_cache[key]
	var parent := []
	for i in range(ls.size()):
		parent.append(i)
	var touch := float(cfg().get("touch", 2.0))
	for i in range(ls.size()):
		for j in range(i + 1, ls.size()):
			if _touch(ls[i]["pts"], ls[j]["pts"], touch):
				var ri := RoadSim._root(parent, i)
				var rj := RoadSim._root(parent, j)
				if ri != rj:
					parent[ri] = rj
	var comp := []
	for i in range(ls.size()):
		comp.append(RoadSim._root(parent, i))
	_comp_cache.clear()
	_comp_cache[key] = comp
	return comp


## Componentes de vía a menos de `reach` de un punto.
static func near_components(gs, p: Vector2, reach: float) -> Array:
	var ls := lines(gs)
	var comp := components(gs)
	var out := []
	for i in range(ls.size()):
		if not out.has(comp[i]) and TransitSim.dist_to_poly(p, ls[i]["pts"]) <= reach:
			out.append(comp[i])
	return out


static func near_rail(gs, p: Vector2, reach: float) -> bool:
	return not near_components(gs, p, reach).is_empty()


## Punto de la vía más cercano (Vector2.INF si no hay vías).
static func nearest_point(gs, p: Vector2) -> Vector2:
	var best := Vector2.INF
	var bd := INF
	for l in lines(gs):
		var pts: PackedVector2Array = l["pts"]
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var ab := b - a
			var t := clampf((p - a).dot(ab) / maxf(0.0001, ab.length_squared()), 0.0, 1.0)
			var q := a + ab * t
			if p.distance_to(q) < bd:
				bd = p.distance_to(q)
				best = q
	return best


## Camino sobre los rieles entre dos puntos (para el tren en 3D y su distancia).
static func path(gs, a: Vector2, b: Vector2) -> PackedVector2Array:
	var segs := []
	for l in lines(gs):
		var pts: PackedVector2Array = l["pts"]
		for i in range(pts.size() - 1):
			segs.append([pts[i], pts[i + 1]])
	return RouteSim.graph_path(segs, a, b)


# --- Bloqueo por tramos ----------------------------------------------------------------------------
# Cada vía trazada (y cada vía a otro pueblo) es un TRAMO. Un tren ocupa los tramos de su camino desde que
# sale hasta que vuelve; en un tramo cabe un tren (dos si es vía doble). Si un tramo está ocupado, el
# despacho espera ("Esperando vía libre"). Para más tráfico: vía doble o un desvío (otra vía paralela).

static func line_label(gs, key: String) -> String:
	if key.begins_with("t:"):
		return "vía a %s" % str(TradeSim.town(gs, key.substr(2)).get("name", key.substr(2)))
	var n := 0
	for r in rails(gs):
		n += 1
		if "r:%d" % int(r["id"]) == key:
			return "tramo %d%s" % [n, " (vía doble)" if bool(r.get("double", false)) else ""]
	return key


static func capacity_of(gs, key: String) -> int:
	for r in rails(gs):
		if "r:%d" % int(r["id"]) == key:
			return 2 if bool(r.get("double", false)) else 1
	return 1


## Tramos que recorre un camino.
static func sections_for(gs, path: PackedVector2Array) -> Array:
	var out := []
	for l in lines(gs):
		var pts: PackedVector2Array = l["pts"]
		for i in range(path.size() - 1):
			if TransitSim.dist_to_poly(path[i].lerp(path[i + 1], 0.5), pts) <= 1.5:
				out.append(str(l["key"]))
				break
	return out


## Trenes en cada tramo en un instante (desde que salen hasta que vuelven): {clave: n}.
static func occupancy(gs, t := -1.0) -> Dictionary:
	if t < 0.0:
		t = float(gs.today()) + TimeManager.hour_float() / 24.0
	var occ := {}
	for s in LogisticsSim.shipments(gs):
		if float(s.get("back", 0.0)) <= t:
			continue
		for k in s.get("rail_sections", []):
			occ[str(k)] = int(occ.get(str(k), 0)) + 1
	return occ


## Primer tramo lleno (su etiqueta) o "".
static func blocked_section(gs, sections: Array, t: float) -> String:
	if sections.is_empty():
		return ""
	var occ := occupancy(gs, t)
	for k in sections:
		if int(occ.get(str(k), 0)) >= capacity_of(gs, str(k)):
			return line_label(gs, str(k))
	return ""


## Convierte una vía en vía doble (60 % del costo por metro). Devuelve "" o el motivo.
static func make_double(gs, id: int) -> String:
	for r in rails(gs):
		if int(r["id"]) == id:
			if bool(r.get("double", false)):
				return "Ya es vía doble"
			var cost: float = float(r.get("length", 0.0)) * float(cfg().get("cost_per_m", 5.0)) * gs.price_mult() * 0.6
			if gs.money < cost:
				return "Dinero insuficiente (%s)" % Fmt.money(cost)
			gs.add_money(-cost)
			r["double"] = true
			_bump(gs)
			return ""
	return "Esa vía no existe"
