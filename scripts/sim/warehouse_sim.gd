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
