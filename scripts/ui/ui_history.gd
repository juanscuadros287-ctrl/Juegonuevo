class_name UIHistory
extends RefCounted
## Muestras que solo usa la interfaz (no se guardan en la partida): ingresos diarios y producción
## por edificio (mini-gráficas del panel de edificio) y tesoro del gobierno por mes.
## Se toma una muestra por día (EventBus.day_passed); con la partida recién cargada las series
## empiezan vacías y se van llenando.

const MAX_DAYS := 60
const MAX_MONTHS := 36

static var buildings := {}    # id -> {income: [], output: [], last_total: float}
static var treasury: Array = []
static var _last_day := -1
static var _last_month := -1


static func sample(gs) -> void:
	var day: int = gs.today()
	if day == _last_day:
		return
	if day < _last_day:
		reset()
	_last_day = day
	for b in gs.buildings:
		if not gs.owned_by_player(b) or str(b.get("status", "")) == "construccion":
			continue
		var id := int(b["id"])
		var h: Dictionary = buildings.get(id, {"income": [], "output": [], "last_total": -1.0})
		var tot := BusinessSim.period_value(b, "total", "ventas") + BusinessSim.period_value(b, "total", "alquileres")
		if float(h["last_total"]) >= 0.0:
			_push(h["income"], maxf(0.0, tot - float(h["last_total"])), MAX_DAYS)
			var product := str(gs.building_def(b).get("product", ""))
			_push(h["output"], float(b.get("inventory", {}).get(product, 0.0)) if product != "" else 0.0, MAX_DAYS)
		h["last_total"] = tot
		buildings[id] = h
	var m := TimeManager.month()
	if m != _last_month:
		_last_month = m
		_push(treasury, float(gs.government.get("treasury", 0.0)), MAX_MONTHS)


static func reset() -> void:
	buildings.clear()
	treasury.clear()
	_last_day = -1
	_last_month = -1


static func _push(arr: Array, v: float, cap: int) -> void:
	arr.append(v)
	while arr.size() > cap:
		arr.pop_front()


static func building(id: int) -> Dictionary:
	return buildings.get(id, {"income": [], "output": []})
