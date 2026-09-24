class_name WarehouseSim
extends RefCounted
## Almacenes de la compañía del jugador. Cada almacén tiene su PROPIO stock y su capacidad
## máxima (1 unidad de cualquier bien = 1 espacio):
##   - la bodega de la plaza (id 0, virtual): almacén principal y salida del pueblo
##     (ahí empieza el camino comercial de la Fase 7), capacidad warehouse.plaza_capacity;
##   - cada edificio del jugador con "warehouse_capacity" en su nivel (Almacén de la Fase 6).
## Estado: gs.logistics["warehouses"] = {"<id>": {bien: cantidad}} (claves String: sobreviven a JSON).
##
## Vinculación por adyacencia: una fábrica, taller, mina o campo (negocio con recetas/almacén)
## queda VINCULADO al almacén cuyo borde esté a menos de warehouse.link_distance metros del suyo
## (distancia entre las huellas cuadradas, sin considerar la rotación). Toma sus insumos y
## guarda su producción SOLO en ese almacén (ver LogisticsSim.produce_chain).
##
## API agregada estable (Fase 6/7/8: suma de todos los almacenes):
##   capacity(gs), used(gs), free_space(gs), stock(gs, good), add(gs, good, qty) -> aceptado,
##   remove(gs, good, qty) -> retirado, all_stock(gs)
## API por almacén:
##   ids(gs), stock_in(gs, wid, good), add_to(gs, wid, good, qty), remove_from(gs, wid, good, qty),
##   capacity_of(gs, wid), used_in(gs, wid), free_in(gs, wid), stock_all_in(gs, wid),
##   warehouse_for(gs, b) -> id del almacén vinculado o -1, linked_to(gs, wid)

const PLAZA := 0
const NONE := -1
const BASE_CAPACITY := 200.0

static var _ids_key := ""
static var _ids_cache: Array = []
static var _gen := 0


static func cfg() -> Dictionary:
	return GameData.extra("resources").get("warehouse", {})


static func link_distance() -> float:
	return float(cfg().get("link_distance", 12.0))


# --- Estado y migración ----------------------------------------------------------------------

static func _stores(gs) -> Dictionary:
	var L: Dictionary = gs.logistics
	if not L.has("warehouses"):
		L["warehouses"] = {}
		_migrate(gs)
	return L["warehouses"]


## Partidas anteriores guardaban un único almacén global en logistics["warehouse"]:
## se reparte entre los almacenes con espacio (primero la bodega de la plaza). Lo que no
## quepa (no debería) queda en la bodega de la plaza aunque la exceda.
static func _migrate(gs) -> void:
	var L: Dictionary = gs.logistics
	var old: Dictionary = L.get("warehouse", {})
	L.erase("warehouse")
	for g in old:
		var q := float(old[g])
		var acc := add(gs, str(g), q)
		if q - acc > 0.0001:
			var st := _store(gs, PLAZA)
			st[str(g)] = float(st.get(str(g), 0.0)) + (q - acc)


static func _store(gs, wid: int) -> Dictionary:
	var all := _stores(gs)
	var k := str(wid)
	if not all.has(k):
		all[k] = {}
	return all[k]


# --- Qué es un almacén ------------------------------------------------------------------------

static func is_warehouse_building(gs, b: Dictionary) -> bool:
	return not b.is_empty() and gs.owned_by_player(b) and str(b.get("status", "")) != "construccion" \
			and float(gs.level_def(b).get("warehouse_capacity", 0.0)) > 0.0


static func exists(gs, wid: int) -> bool:
	return wid == PLAZA or is_warehouse_building(gs, gs.get_building(wid))


## Ids de todos los almacenes: la bodega de la plaza primero y luego por cercanía a la plaza
## (la salida del pueblo). Es el orden de preferencia de add/remove agregados.
static func ids(gs) -> Array:
	var key := "%d|%d|%d|%d" % [gs.buildings.size(), gs.next_building_id, gs.today(), _gen]
	if key == _ids_key:
		return _ids_cache
	_ids_key = key
	_ids_cache = _compute_ids(gs)
	return _ids_cache


## Invalida la caché de ids (un almacén terminó su obra, se movió o se demolió).
static func invalidate() -> void:
	_gen += 1


static func _compute_ids(gs) -> Array:
	var others := []
	for b in gs.buildings:
		if is_warehouse_building(gs, b):
			others.append(b)
	others.sort_custom(func(a, c): return Vector2(float(a["x"]), float(a["z"])).length() < Vector2(float(c["x"]), float(c["z"])).length())
	var out := [PLAZA]
	for b in others:
		out.append(int(b["id"]))
	return out


static func capacity_of(gs, wid: int) -> float:
	if wid == PLAZA:
		return float(cfg().get("plaza_capacity", BASE_CAPACITY))
	var b: Dictionary = gs.get_building(wid)
	if not is_warehouse_building(gs, b):
		return 0.0
	return float(gs.level_def(b).get("warehouse_capacity", 0.0))


static func used_in(gs, wid: int) -> float:
	var st: Dictionary = _stores(gs).get(str(wid), {})
	var total := 0.0
	for g in st:
		total += float(st[g])
	return total


static func free_in(gs, wid: int) -> float:
	return maxf(0.0, capacity_of(gs, wid) - used_in(gs, wid))


static func stock_in(gs, wid: int, good: String) -> float:
	return float(_stores(gs).get(str(wid), {}).get(good, 0.0))


static func stock_all_in(gs, wid: int) -> Dictionary:
	return (_stores(gs).get(str(wid), {}) as Dictionary).duplicate()


## Guarda en un almacén hasta llenarlo. Devuelve las unidades aceptadas.
static func add_to(gs, wid: int, good: String, qty: float) -> float:
	if not exists(gs, wid):
		return 0.0
	var accepted := minf(maxf(0.0, qty), free_in(gs, wid))
	if accepted > 0.0:
		var st := _store(gs, wid)
		st[good] = float(st.get(good, 0.0)) + accepted
	return accepted


## Retira de un almacén hasta `qty`. Devuelve las unidades retiradas.
static func remove_from(gs, wid: int, good: String, qty: float) -> float:
	var st: Dictionary = _stores(gs).get(str(wid), {})
	var taken := minf(maxf(0.0, qty), float(st.get(good, 0.0)))
	if taken > 0.0:
		st[good] = float(st[good]) - taken
		if float(st[good]) <= 0.0001:
			st.erase(good)
	return taken


static func label_of(gs, wid: int) -> String:
	if wid == PLAZA:
		return str(cfg().get("plaza_label", "Bodega de la plaza"))
	var b: Dictionary = gs.get_building(wid)
	return gs.building_label(b) if not b.is_empty() else "(demolido)"


static func pos_of(gs, wid: int) -> Vector2:
	if wid == PLAZA:
		return Vector2.ZERO
	var b: Dictionary = gs.get_building(wid)
	return Vector2(float(b.get("x", 0.0)), float(b.get("z", 0.0)))


static func half_of(gs, wid: int) -> float:
	if wid == PLAZA:
		return float(cfg().get("plaza_half", 9.0))
	return float(gs.footprint_of(gs.get_building(wid))) * 0.5


# --- API agregada (compatibilidad Fase 6/7/8) --------------------------------------------------

static func capacity(gs) -> float:
	var cap := 0.0
	for wid in ids(gs):
		cap += capacity_of(gs, wid)
	return cap


static func used(gs) -> float:
	var total := 0.0
	for wid in ids(gs):
		total += used_in(gs, wid)
	return total


static func free_space(gs) -> float:
	var total := 0.0
	for wid in ids(gs):
		total += free_in(gs, wid)
	return total


static func stock(gs, good: String) -> float:
	var total := 0.0
	for wid in ids(gs):
		total += stock_in(gs, wid, good)
	return total


static func all_stock(gs) -> Dictionary:
	var out := {}
	for wid in ids(gs):
		var st: Dictionary = _stores(gs).get(str(wid), {})
		for g in st:
			out[g] = float(out.get(g, 0.0)) + float(st[g])
	return out


## Reparte en los almacenes con espacio, prefiriendo la bodega de la plaza (salida del pueblo)
## y luego los más cercanos a ella. Devuelve las unidades aceptadas.
static func add(gs, good: String, qty: float) -> float:
	var left := maxf(0.0, qty)
	var accepted := 0.0
	for wid in ids(gs):
		if left <= 0.0001:
			break
		var a := add_to(gs, wid, good, left)
		accepted += a
		left -= a
	return accepted


## Retira de donde haya (en el mismo orden de preferencia). Devuelve las unidades retiradas.
static func remove(gs, good: String, qty: float) -> float:
	var left := maxf(0.0, qty)
	var taken := 0.0
	for wid in ids(gs):
		if left <= 0.0001:
			break
		var t := remove_from(gs, wid, good, left)
		taken += t
		left -= t
	return taken


## Stock de almacenes demolidos: se reparte en los demás; lo que no cabe se pierde (con aviso).
static func prune(gs) -> void:
	var all := _stores(gs)
	for k in all.keys():
		var wid := int(k)
		if exists(gs, wid):
			continue
		var st: Dictionary = all[k]
		all.erase(k)
		var lost := 0.0
		for g in st:
			var q := float(st[g])
			lost += q - add(gs, str(g), q)
		if lost > 0.5:
			gs.notify("Se perdieron %s unidades del almacén demolido: no cabían en tus otros almacenes." % Fmt.thousands(lost), "negocio")


# --- Vinculación por adyacencia ------------------------------------------------------------------

static func half_size(type_id: String) -> float:
	return float(GameData.building_def(type_id).get("footprint", 4.0)) * 0.5


## Distancia entre bordes de dos huellas cuadradas (centro y medio lado), 0 si se tocan.
static func edge_gap(p1: Vector2, h1: float, p2: Vector2, h2: float) -> float:
	var gx := maxf(0.0, absf(p1.x - p2.x) - (h1 + h2))
	var gz := maxf(0.0, absf(p1.y - p2.y) - (h1 + h2))
	return Vector2(gx, gz).length()


## ¿Este negocio se vincula a un almacén? (fábricas, talleres, minas y campos de la cadena).
static func is_linkable(gs, b: Dictionary) -> bool:
	if b.is_empty() or not gs.owned_by_player(b):
		return false
	return type_linkable(str(b.get("type", "")), int(b.get("level", 1)))


static func type_linkable(type_id: String, level := 1) -> bool:
	var def := GameData.building_def(type_id)
	if str(def.get("category", "")) != "negocio":
		return false
	return LogisticsSim.uses_chain(def, GameData.level_def(type_id, level))


static func type_is_warehouse(type_id: String) -> bool:
	return float(GameData.level_def(type_id, 1).get("warehouse_capacity", 0.0)) > 0.0


## Almacén más cercano "al lado" de una huella hipotética: {"id", "gap"} o {} si no hay.
static func nearest_for(gs, type_id: String, x: float, z: float, ignore_id := -1, level := 1) -> Dictionary:
	var p := Vector2(x, z)
	var h := GameData.footprint(type_id, level) * 0.5
	var best := {}
	var best_gap := link_distance() + 0.001
	for wid in ids(gs):
		if wid == ignore_id and wid != PLAZA:
			continue
		var g := edge_gap(p, h, pos_of(gs, wid), half_of(gs, wid))
		if g < best_gap:
			best_gap = g
			best = {"id": wid, "gap": g}
	return best


## Id del almacén vinculado a un negocio (o -1). Se recalcula y queda en b["warehouse_id"].
static func warehouse_for(gs, b: Dictionary) -> int:
	if not is_linkable(gs, b):
		return NONE
	var n := nearest_for(gs, str(b["type"]), float(b["x"]), float(b["z"]), int(b["id"]), int(b.get("level", 1)))
	var wid := int(n.get("id", NONE))
	b["warehouse_id"] = wid
	return wid


## Negocios vinculados a un almacén.
static func linked_to(gs, wid: int) -> Array:
	var out := []
	for b in gs.buildings:
		if is_linkable(gs, b) and warehouse_for(gs, b) == wid:
			out.append(b)
	return out


## Negocios de la cadena que quedarían vinculados a un almacén puesto en (x, z).
static func linkable_near(gs, type_id: String, x: float, z: float, ignore_id := -1) -> Array:
	var out := []
	var p := Vector2(x, z)
	var h := half_size(type_id)
	for b in gs.buildings:
		if int(b["id"]) == ignore_id or not is_linkable(gs, b):
			continue
		if edge_gap(p, h, Vector2(float(b["x"]), float(b["z"])), float(gs.footprint_of(b)) * 0.5) <= link_distance():
			out.append(b)
	return out


## Recalcula b["warehouse_id"] de todos tus negocios (al construir, mover o demoler).
static func relink_all(gs) -> void:
	invalidate()
	for b in gs.buildings:
		if is_linkable(gs, b):
			warehouse_for(gs, b)
		elif b.has("warehouse_id"):
			b.erase("warehouse_id")


# --- Ampliaciones de la Fase 6 (no cambian la API estable) ------------------------------

## Valor de mercado del inventario de todos los almacenes.
static func value(gs) -> float:
	var total := 0.0
	var st := all_stock(gs)
	for g in st:
		total += float(st[g]) * EconomySim.market_price(gs, str(g))
	return total


static func value_in(gs, wid: int) -> float:
	var total := 0.0
	var st := stock_all_in(gs, wid)
	for g in st:
		total += float(st[g]) * EconomySim.market_price(gs, str(g))
	return total


## Tiendas del jugador que pueden vender productos del almacén (la Tienda o "warehouse_shop").
static func _is_shop(gs, b: Dictionary) -> bool:
	return str(b.get("type", "")) == "tienda" or bool(gs.building_def(b).get("warehouse_shop", false))


## Contexto semanal de venta en tiendas: {} si no hay tienda o productos "shop_sale" en el almacén.
static func shop_context(gs) -> Dictionary:
	var goods := []
	for g in GameData.sorted_ids(GameData.goods):
		if bool(GameData.goods[g].get("shop_sale", false)) and stock(gs, g) > 0.01:
			goods.append(g)
	if goods.is_empty():
		return {}
	var wc: Dictionary = GameData.extra("resources").get("warehouse", {})
	var shops := []
	var cap := {}
	for b in gs.buildings:
		if gs.owned_by_player(b) and b["status"] == "activo" and _is_shop(gs, b):
			shops.append(b)
			# Lo que el personal de la tienda alcanza a vender en la semana.
			cap[int(b["id"])] = BusinessSim.expected_output(gs, b) * 7.0 * float(wc.get("shop_units_per_output", 0.4))
	if shops.is_empty():
		return {}
	return {"goods": goods, "shops": shops, "cap": cap, "share": float(wc.get("shop_share", 0.35))}


## Un ciudadano gasta hasta `budget` en productos del almacén a través de tus tiendas.
## El dinero entra a la tienda (ventas). Devuelve {"spent", "units"}.
static func shop_sell(gs, c, budget: float, ctx: Dictionary) -> Dictionary:
	var spent := 0.0
	var units := 0.0
	var goods: Array = ctx.get("goods", [])
	if goods.is_empty() or budget <= 0.0:
		return {"spent": 0.0, "units": 0.0}
	var per_good := budget / goods.size()
	var caps: Dictionary = ctx["cap"]
	for g in goods:
		var have := stock(gs, g)
		if have <= 0.001:
			continue
		for b in ctx["shops"]:
			var left_cap := float(caps.get(int(b["id"]), 0.0))
			if left_cap <= 0.001:
				continue
			var price: float = EconomySim.market_price(gs, g) * (1.0 + float(b.get("markup", 0.1)))
			if price <= 0.0:
				continue
			var take := minf(minf(have, left_cap), per_good / price * AdvertisingSim.demand_mult(gs, b))
			if take <= 0.001:
				break
			var cost := take * price
			remove(gs, g, take)
			caps[int(b["id"])] = left_cap - take
			c.money -= cost
			spent += cost
			units += take
			BusinessSim.earn(gs, b, cost, "ventas")
			EconomySim.record_discretionary(gs, g, take, cost)
			break
	return {"spent": spent, "units": units}
