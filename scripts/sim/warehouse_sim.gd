class_name WarehouseSim
extends RefCounted
## Almacén de la compañía del jugador: materias primas y productos elaborados.
## Capacidad limitada: 1 unidad de cualquier bien = 1 espacio.
## API estable usada por logística (Fase 6), comercio exterior (Fase 7) e industria (Fase 8):
##   capacity(gs), used(gs), free_space(gs), stock(gs, good), add(gs, good, qty) -> aceptado,
##   remove(gs, good, qty) -> retirado, all_stock(gs)

const BASE_CAPACITY := 200.0


static func _store(gs) -> Dictionary:
	if not gs.logistics.has("warehouse"):
		gs.logistics["warehouse"] = {}
	return gs.logistics["warehouse"]


## Capacidad base + edificios con "warehouse_capacity" en su nivel (almacenes de la Fase 6).
static func capacity(gs) -> float:
	var cap := BASE_CAPACITY
	for b in gs.buildings:
		if gs.owned_by_player(b) and b["status"] == "activo":
			cap += float(gs.level_def(b).get("warehouse_capacity", 0.0))
	return cap


static func used(gs) -> float:
	var total := 0.0
	var st := _store(gs)
	for g in st:
		total += float(st[g])
	return total


static func free_space(gs) -> float:
	return maxf(0.0, capacity(gs) - used(gs))


static func stock(gs, good: String) -> float:
	return float(_store(gs).get(good, 0.0))


static func all_stock(gs) -> Dictionary:
	return _store(gs).duplicate()


## Guarda hasta llenar el almacén. Devuelve las unidades aceptadas.
static func add(gs, good: String, qty: float) -> float:
	var accepted := minf(maxf(0.0, qty), free_space(gs))
	if accepted > 0.0:
		var st := _store(gs)
		st[good] = float(st.get(good, 0.0)) + accepted
	return accepted


## Retira hasta `qty`. Devuelve las unidades retiradas.
static func remove(gs, good: String, qty: float) -> float:
	var st := _store(gs)
	var taken := minf(maxf(0.0, qty), float(st.get(good, 0.0)))
	if taken > 0.0:
		st[good] = float(st[good]) - taken
		if float(st[good]) <= 0.0001:
			st.erase(good)
	return taken


# --- Ampliaciones de la Fase 6 (no cambian la API estable) ------------------------------

## Valor de mercado del inventario del almacén.
static func value(gs) -> float:
	var total := 0.0
	var st := _store(gs)
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
