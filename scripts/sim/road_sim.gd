class_name RoadSim
extends RefCounted
## Fase 6 — Carreteras. Solo las necesitan caballos, carretas y vehículos: casas y negocios
## no requieren carretera (la gente camina). Tramos rectos de barro, empedrado o cemento, con costo
## por metro; se unen en una red (tramos que comparten extremo o se tocan). Una ruta con carretas
## exige que origen y destino estén a menos de roads.reach de la misma red; los carros de vapor y
## camiones exigen una red de empedrado o cemento, y los tráileres de cemento (road_kinds del medio).

static var _comp_cache := {}   # clave (hash de tramos | tipos) -> componentes


static func cfg() -> Dictionary:
	return GameData.extra("resources").get("roads", {})


static func kind_def(kind: String) -> Dictionary:
	return cfg().get("kinds", {}).get(kind, {})


static func kind_label(kind: String) -> String:
	return str(kind_def(kind).get("label", kind))


static func roads(gs) -> Array:
	if not gs.logistics.has("roads"):
		gs.logistics["roads"] = []
	return gs.logistics["roads"]


static func seg_a(r: Dictionary) -> Vector2:
	return Vector2(float(r["ax"]), float(r["az"]))


static func seg_b(r: Dictionary) -> Vector2:
	return Vector2(float(r["bx"]), float(r["bz"]))


static func total_length(gs, kind := "") -> float:
	var total := 0.0
	for r in roads(gs):
		if kind == "" or str(r["kind"]) == kind:
			total += seg_a(r).distance_to(seg_b(r))
	return total


# --- Costos y construcción -----------------------------------------------------------------

## Costo de un tramo: {money, stone, stone_stock, stone_import, import_cost, total}.
static func segment_cost(gs, a: Vector2, b: Vector2, kind: String) -> Dictionary:
	return _cost_for_length(gs, a.distance_to(b), kind)


static func _cost_for_length(gs, length: float, kind: String) -> Dictionary:
	var kd := kind_def(kind)
	var pm: float = gs.price_mult()
	var money := length * float(kd.get("cost_per_unit", 1.0)) * pm
	var stone := ceilf(length * float(kd.get("stone_per_unit", 0.0)))
	var have: float = ConstructionSim.stock_of(gs, "piedra")
	var from_stock := minf(have, stone)
	var imp := stone - from_stock
	var import_cost: float = imp * float(GameData.goods.get("piedra", {}).get("import_price", 7.0)) * pm * GovSim.import_mult(gs)
	return {"money": money, "stone": stone, "stone_stock": from_stock, "stone_import": imp,
		"import_cost": import_cost, "total": money + import_cost}


static func _zone_unlocked(gs, p: Vector2) -> bool:
	var zs: float = gs.MAP_SIZE / gs.ZONE_GRID
	var half: float = gs.MAP_SIZE * 0.5
	return gs.is_zone_unlocked(clampi(int((p.x + half) / zs), 0, gs.ZONE_GRID - 1), clampi(int((p.y + half) / zs), 0, gs.ZONE_GRID - 1))


## Motivo por el que no se puede construir el tramo ("" si se puede). El agua la verifica el mundo 3D.
static func block_reason(gs, a: Vector2, b: Vector2, kind: String) -> String:
	var kd := kind_def(kind)
	if kd.is_empty():
		return "Tipo de camino desconocido"
	if not gs.has_tech(str(kd.get("tech", ""))):
		return "Requiere investigar: %s" % GameData.tech_label(str(kd.get("tech", "")))
	var length := a.distance_to(b)
	if length < float(cfg().get("min_length", 3.0)):
		return "Tramo demasiado corto"
	if length > float(cfg().get("max_length", 80.0)):
		return "Tramo demasiado largo (máx. %d m): haz varios tramos" % int(cfg().get("max_length", 80.0))
	for t in [0.0, 0.25, 0.5, 0.75, 1.0]:
		if not _zone_unlocked(gs, a.lerp(b, t)):
			return "Pasa por terreno del gobierno: cómpralo primero"
	var c := segment_cost(gs, a, b, kind)
	if gs.money < float(c["total"]):
		return "Dinero insuficiente (%s)" % Fmt.money(c["total"])
	return ""


## Ajusta un punto al extremo de carretera más cercano (para unir tramos).
static func snap(gs, p: Vector2) -> Vector2:
	var best := p
	var best_d := float(cfg().get("snap", 3.0))
	for r in roads(gs):
		for q in [seg_a(r), seg_b(r)]:
			var d := p.distance_to(q)
			if d < best_d:
				best_d = d
				best = q
	return best


static func build(gs, a: Vector2, b: Vector2, kind: String) -> String:
	a = snap(gs, a)
	b = snap(gs, b)
	var reason := block_reason(gs, a, b, kind)
	if reason != "":
		return reason
	var c := segment_cost(gs, a, b, kind)
	if float(c["stone_stock"]) > 0.0:
		ConstructionSim._consume_stock(gs, "piedra", float(c["stone_stock"]))
	gs.add_money(-float(c["total"]))
	var id := int(gs.logistics.get("next_road_id", 1))
	gs.logistics["next_road_id"] = id + 1
	roads(gs).append({"id": id, "ax": a.x, "az": a.y, "bx": b.x, "bz": b.y, "kind": kind})
	_bump(gs)
	return ""


static func remove(gs, id: int) -> void:
	var rs := roads(gs)
	for i in range(rs.size()):
		if int(rs[i]["id"]) == id:
			rs.remove_at(i)
			_bump(gs)
			return


## Mejorar todos los tramos más lentos que `to_kind` (barro → empedrado, o todo → cemento).
## Se descuenta la mitad de lo ya invertido en los tramos que se mejoran.
static func upgrade_all_cost(gs, to_kind := "empedrado") -> Dictionary:
	var target_speed := float(kind_def(to_kind).get("speed", 1.0))
	var length := 0.0
	var paid := 0.0
	for r in roads(gs):
		var kd := kind_def(str(r["kind"]))
		if float(kd.get("speed", 1.0)) < target_speed:
			var l := seg_a(r).distance_to(seg_b(r))
			length += l
			paid += l * float(kd.get("cost_per_unit", 1.0)) * gs.price_mult() * 0.5
	var c := _cost_for_length(gs, length, to_kind)
	c["money"] = maxf(0.0, float(c["money"]) - paid)
	c["total"] = float(c["money"]) + float(c["import_cost"])
	c["length"] = length
	return c


static func upgrade_all(gs, to_kind := "empedrado") -> String:
	var tech := str(kind_def(to_kind).get("tech", ""))
	if not gs.has_tech(tech):
		return "Requiere investigar: %s" % GameData.tech_label(tech)
	var c := upgrade_all_cost(gs, to_kind)
	if float(c["length"]) <= 0.0:
		return "No hay caminos que mejorar a %s" % kind_label(to_kind).to_lower()
	if gs.money < float(c["total"]):
		return "Dinero insuficiente (%s)" % Fmt.money(c["total"])
	if float(c["stone_stock"]) > 0.0:
		ConstructionSim._consume_stock(gs, "piedra", float(c["stone_stock"]))
	gs.add_money(-float(c["total"]))
	var target_speed := float(kind_def(to_kind).get("speed", 1.0))
	for r in roads(gs):
		if float(kind_def(str(r["kind"])).get("speed", 1.0)) < target_speed:
			r["kind"] = to_kind
	_bump(gs)
	gs.notify("Mejoraste %d m de caminos a %s por %s." % [int(c["length"]), kind_label(to_kind).to_lower(), Fmt.money(c["total"])], "construccion")
	return ""


static func _bump(gs) -> void:
	gs.logistics["road_version"] = int(gs.logistics.get("road_version", 0)) + 1


# --- Red y conexiones ------------------------------------------------------------------------

static func dist_point_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## ¿El tramo sirve para esos tipos de camino? (lista vacía = cualquiera).
static func _kind_ok(r: Dictionary, kinds: Array) -> bool:
	return kinds.is_empty() or kinds.has(str(r["kind"]))


## Componente conexa de cada tramo (unión de tramos que se tocan). Con `kinds` solo cuentan
## los tramos de esos tipos (los demás quedan en -1): los camiones exigen empedrado o cemento.
static func components(gs, kinds: Array = []) -> Array:
	var rs := roads(gs)
	var key := "%d|%s" % [rs.hash(), ",".join(kinds)]
	if _comp_cache.has(key):
		return _comp_cache[key]
	var parent := []
	for i in range(rs.size()):
		parent.append(i)
	var touch := 1.5
	for i in range(rs.size()):
		if not _kind_ok(rs[i], kinds):
			continue
		for j in range(i + 1, rs.size()):
			if not _kind_ok(rs[j], kinds):
				continue
			var a1 := seg_a(rs[i])
			var b1 := seg_b(rs[i])
			var a2 := seg_a(rs[j])
			var b2 := seg_b(rs[j])
			if dist_point_segment(a1, a2, b2) < touch or dist_point_segment(b1, a2, b2) < touch \
					or dist_point_segment(a2, a1, b1) < touch or dist_point_segment(b2, a1, b1) < touch or _cross(a1, b1, a2, b2):
				var ri := _root(parent, i)
				var rj := _root(parent, j)
				if ri != rj:
					parent[ri] = rj
	var comp := []
	for i in range(rs.size()):
		comp.append(_root(parent, i) if _kind_ok(rs[i], kinds) else -1)
	if _comp_cache.size() > 16:
		_comp_cache.clear()
	_comp_cache[key] = comp
	return comp


static func _root(parent: Array, i: int) -> int:
	while int(parent[i]) != i:
		parent[i] = parent[int(parent[i])]
		i = int(parent[i])
	return i


static func _cross(a1: Vector2, b1: Vector2, a2: Vector2, b2: Vector2) -> bool:
	return Geometry2D.segment_intersects_segment(a1, b1, a2, b2) != null


## Componentes de la red a menos de `reach` de un punto.
static func near_components(gs, p: Vector2, reach := -1.0, kinds: Array = []) -> Array:
	if reach < 0.0:
		reach = float(cfg().get("reach", 12.0))
	var rs := roads(gs)
	var comp := components(gs, kinds)
	var out := []
	for i in range(rs.size()):
		if int(comp[i]) >= 0 and dist_point_segment(p, seg_a(rs[i]), seg_b(rs[i])) <= reach and not out.has(comp[i]):
			out.append(comp[i])
	return out


static func near_road(gs, p: Vector2, kinds: Array = []) -> bool:
	return not near_components(gs, p, -1.0, kinds).is_empty()


## ¿Están dos puntos unidos por la misma red de carreteras (de esos tipos)?
static func connected(gs, p1: Vector2, p2: Vector2, kinds: Array = []) -> bool:
	var c1 := near_components(gs, p1, -1.0, kinds)
	if c1.is_empty():
		return false
	for c in near_components(gs, p2, -1.0, kinds):
		if c1.has(c):
			return true
	return false


## Multiplicador de velocidad de la red que une dos puntos (empedrado y cemento son más rápidos).
static func speed_mult(gs, p1: Vector2, p2: Vector2, kinds: Array = []) -> float:
	var c1 := near_components(gs, p1, -1.0, kinds)
	var c2 := near_components(gs, p2, -1.0, kinds)
	var rs := roads(gs)
	var comp := components(gs, kinds)
	var best := 1.0
	for c in c1:
		if not c2.has(c):
			continue
		var total := 0.0
		var weighted := 0.0
		for i in range(rs.size()):
			if comp[i] == c:
				var l := seg_a(rs[i]).distance_to(seg_b(rs[i]))
				total += l
				weighted += l * float(kind_def(str(rs[i]["kind"])).get("speed", 1.0))
		if total > 0.0:
			best = maxf(best, weighted / total)
	return best
