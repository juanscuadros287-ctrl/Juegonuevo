class_name FreeMarketSim
extends RefCounted
## Libre mercado (ver docs/MERCADO_LIBRE.md): orquesta los sistemas nuevos y guarda su estado
## en GameState.market (se guarda automáticamente; las partidas viejas lo crean al cargar).
##   NpcBusinessSim   — empresarios NPC del pueblo del jugador (abren, contratan, heredan, quiebran).
##   TownEconomySim   — pueblos vecinos que crecen y comercian entre ellos.
##   ContractSim      — contratos de compraventa (solicitudes entrantes y ofertas salientes).
##   GovPlansSim      — el gobierno construye parques, salud, policía, escuelas y vivienda social.
## Generador aleatorio propio (no altera la secuencia de gs.rng del resto de la simulación).


static func cfg() -> Dictionary:
	return GameData.extra("mercado")


static func init_state(gs) -> void:
	var m: Dictionary = gs.market
	for key in ["inbox", "sent", "contracts", "shipments", "purchase_offers", "gov_plans", "log"]:
		if not m.has(key):
			m[key] = []
	for key in ["reputation", "npc", "stats", "school"]:
		if not m.has(key):
			m[key] = {}
	if not m.has("next_id"):
		m["next_id"] = 1
	if not m.has("rng_state"):
		var r := RandomNumberGenerator.new()
		r.seed = int(gs.settings.get("seed", 0)) * 6007 + 31337
		m["rng_state"] = str(r.state)
	TownEconomySim.ensure(gs)


static func next_id(gs) -> int:
	var n := int(gs.market.get("next_id", 1))
	gs.market["next_id"] = n + 1
	return n


# --- Aleatoriedad propia (determinista y guardada) ------------------------------------------

static func _r(gs) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.state = int(str(gs.market.get("rng_state", "1")))
	return r


static func rf(gs) -> float:
	var r := _r(gs)
	var v := r.randf()
	gs.market["rng_state"] = str(r.state)
	return v


static func rr(gs, a: float, b: float) -> float:
	return a + (b - a) * rf(gs)


static func ri(gs, a: int, b: int) -> int:
	return mini(b, a + int(floorf(rf(gs) * float(b - a + 1))))


static func pick(gs, arr: Array):
	if arr.is_empty():
		return null
	return arr[mini(arr.size() - 1, int(floorf(rf(gs) * arr.size())))]


static func range_of(gs, arr: Array) -> float:
	if arr.size() < 2:
		return float(arr[0]) if arr.size() == 1 else 1.0
	return rr(gs, float(arr[0]), float(arr[1]))


# --- Registro breve para la interfaz ----------------------------------------------------------

static func log_event(gs, text: String) -> void:
	var l: Array = gs.market.get("log", [])
	l.append({"date": TimeManager.date_string(false), "text": text})
	while l.size() > 60:
		l.pop_front()
	gs.market["log"] = l


static func stat(gs, key: String, amount: float) -> void:
	var s: Dictionary = gs.market.get("stats", {})
	s[key] = float(s.get(key, 0.0)) + amount
	gs.market["stats"] = s


# --- Ciclo -------------------------------------------------------------------------------------

## Tras BusinessSim.produce: las empresas NPC producen y pagan sueldos.
static func produce(gs) -> void:
	if gs.market.is_empty():
		init_state(gs)
	NpcBusinessSim.produce(gs)


## Fin del día: herencias, obras y personal NPC, entregas de contratos, planes del gobierno.
static func daily(gs) -> void:
	NpcBusinessSim.daily(gs)
	GovPlansSim.daily(gs)
	ContractSim.daily(gs)


static func monthly(gs) -> void:
	NpcBusinessSim.monthly(gs)
	GovPlansSim.monthly(gs)
	TownEconomySim.monthly(gs)
	ContractSim.monthly(gs)


## Suma de todo el dinero que existe dentro del sistema (jugador, ciudadanos, cajas de negocios,
## tesoro y cajas de los pueblos vecinos). Útil para verificar la economía cerrada.
static func money_snapshot(gs) -> Dictionary:
	var cit := 0.0
	for c in gs.citizens.values():
		cit += c.money
	var reserves := 0.0
	for b in gs.buildings:
		reserves += float(b.get("reserve", 0.0))
	var towns := 0.0
	for t in TradeSim.towns(gs):
		towns += float(t.get("cash", 0.0))
	var treasury := float(gs.government.get("treasury", 0.0))
	return {"player": gs.money, "citizens": cit, "reserves": reserves, "treasury": treasury, "towns": towns,
		"total": gs.money + cit + reserves + treasury + towns}
