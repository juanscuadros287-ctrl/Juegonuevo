class_name CountriesSim
extends RefCounted
## Fase 10 — Varios países con presencia del jugador (docs/FASE10.md).
##
## Enfoque: "contexto por país". GameState conserva en sus campos de siempre (citizens, buildings, map,
## government, logistics, trade…) los datos del país que está CARGADO en ese momento. Los demás países con
## presencia del jugador guardan exactamente esos mismos campos en `countries.stash[iso]`. Para simular o
## tocar otro país se intercambian las referencias (sin copiar datos) con `swap_to` / `with_country`.
## Así cada país con presencia corre la simulación COMPLETA de siempre (población, negocios, obras,
## mercado, gobierno con su tesoro e impuestos, logística…) sin reescribir los sistemas.
##
## Lo global (no se intercambia): dinero y efectivo del jugador (una sola cuenta), jugador y familia
## (viven en el país de origen), tecnologías, investigación, préstamos, economía mundial (ciclos y monedas),
## historial y registro de avisos, ids de ciudadanos y edificios (únicos en toda la partida).
##
## Día: 1) pase principal en el país de ORIGEN (incluye jugador, banco, bolsa, investigación…);
## 2) un pase por cada otro país con presencia (solo los sistemas de país); 3) se vuelve a cargar el país
## ACTIVO (el que muestra el mundo 3D). Mientras se simula un país que no se ve, EventBus queda bloqueado
## (el mundo 3D no reacciona) y sus avisos se muestran al final con el nombre del país.
##
## Estado (GameState.countries, se guarda):
##   home        país de origen (donde vive la familia; pase principal)
##   active      país cargado en los campos de GameState y dibujado por el mundo 3D
##   location    país donde está físicamente el personaje ("" = de viaje)
##   presence    {iso: {licensed_day, license_paid, entered, land_paid, manager {}, month {}, last_month {}}}
##   stash       {iso: campos del país (citizens, buildings, map, government…)} de los países no cargados
##   travel      viaje en curso (TravelSim) · trips: viajes hechos
##   air         vuelos, rutas internacionales y vuelos comerciales (AirSim)
##   stats       {outflow, licenses, perf {iso: ms/día}}
##   pending_view  país que la interfaz debe mostrar al llegar de un viaje

const PER_COUNTRY := ["citizens", "buildings", "government", "problems", "logistics", "trade", "tourism",
		"market", "realestate", "economy", "map", "transit", "utilities", "labor", "world_events", "weather",
		"season", "unlocked_zones"]
const SETTINGS_KEYS := ["town_name", "region", "country_id"]

static var _current := ""          # país cargado ahora en los campos de GameState
static var _op_mult := 1.0         # rendimiento de los negocios del país que se simula (gerente/presencia)
static var _work_mult := 1.0       # velocidad de las obras del jugador
static var _works := true          # ¿avanzan las obras del jugador en este país?
static var _saved_check: Callable = Callable()
static var _blocked_by_us := false
static var _perf := {}             # ms por día de cada país (medición; no se guarda: no es determinista)
static var _fx_mult := 1.0          # precios del país cargado según el cambio real (GameState.price_mult)


static func cfg() -> Dictionary:
	return GameData.extra("fase10")


static func ready(gs) -> bool:
	return gs.countries is Dictionary and gs.countries.has("home")


static func st(gs) -> Dictionary:
	return gs.countries


# --- Estado ---------------------------------------------------------------------------------------

## Crea o completa el estado (partidas viejas: un solo país, el de su mapa).
static func init_state(gs) -> void:
	var s: Dictionary = gs.countries if gs.countries is Dictionary else {}
	var cur := MapSim.country_id(gs)
	if not s.has("home"):
		s["home"] = cur
	if not s.has("active"):
		s["active"] = cur
	if not s.has("location"):
		s["location"] = str(s["home"])
	for k in ["presence", "stash", "travel", "stats", "air"]:
		if not (s.get(k) is Dictionary):
			s[k] = {}
	if not (s.get("trips") is Array):
		s["trips"] = []
	s["pending_view"] = str(s.get("pending_view", ""))
	var pres: Dictionary = s["presence"]
	var home := str(s["home"])
	if not pres.has(home):
		pres[home] = {"licensed_day": 0, "license_paid": 0.0, "entered": true, "land_paid": 0.0, "home": true,
				"manager": {}, "month": {}, "last_month": {}}
	for iso in pres:
		_fix_presence(pres[iso])
	var stats: Dictionary = s["stats"]
	for k in ["outflow", "licenses", "travel_spent"]:
		stats[k] = float(stats.get(k, 0.0))
	stats.erase("perf")
	if not s.has("rng_state"):
		var r := RandomNumberGenerator.new()
		r.seed = int(gs.settings.get("seed", 1)) * 6007 + 101
		s["rng_state"] = str(r.state)
	gs.countries = s
	_current = str(s["active"])
	_perf = {}
	_fx_mult = fx_price_mult(gs, _current)
	_op_mult = 1.0
	_work_mult = 1.0
	_works = true
	stamp(gs, _current)
	AirSim.init_state(gs)


static func _fix_presence(p: Dictionary) -> void:
	for k in ["manager", "month", "last_month"]:
		if not (p.get(k) is Dictionary):
			p[k] = {}
	p["entered"] = bool(p.get("entered", false))


static func home_id(gs) -> String:
	return str(gs.countries.get("home", MapSim.country_id(gs))) if ready(gs) else MapSim.country_id(gs)


static func active_id(gs) -> String:
	return str(gs.countries.get("active", "")) if ready(gs) else MapSim.country_id(gs)


static func location(gs) -> String:
	return str(gs.countries.get("location", "")) if ready(gs) else MapSim.country_id(gs)


## Ciudadano del país de origen cuando hay otro país cargado (el jugador y su familia viven allá).
static func home_citizen(gs, id: int) -> Citizen:
	if not ready(gs) or _current == home_id(gs):
		return null
	var d: Dictionary = gs.countries["stash"].get(home_id(gs), {})
	return d.get("citizens", {}).get(id)


## País cargado ahora en GameState (durante los pases del día puede no ser el activo).
static func current_id() -> String:
	return _current


static func presence(gs, iso: String) -> Dictionary:
	if not ready(gs):
		return {}
	return gs.countries["presence"].get(iso, {})


static func has_context(gs, iso: String) -> bool:
	return ready(gs) and (iso == _current or gs.countries["stash"].has(iso))


## ¿Tiene el jugador presencia (licencia + terreno) en el país?
static func has_presence(gs, iso: String) -> bool:
	return bool(presence(gs, iso).get("entered", false)) and has_context(gs, iso)


## Países con presencia (el de origen primero).
static func presence_ids(gs) -> Array:
	if not ready(gs):
		return []
	var home := home_id(gs)
	var out := [home]
	var others := []
	for iso in gs.countries["presence"]:
		if str(iso) != home and has_presence(gs, str(iso)):
			others.append(str(iso))
	others.sort()
	out.append_array(others)
	return out


## Países con licencia (con o sin terreno).
static func licensed_ids(gs) -> Array:
	var out := []
	if not ready(gs):
		return out
	for iso in gs.countries["presence"]:
		if has_context(gs, str(iso)):
			out.append(str(iso))
	out.sort()
	return out


## Marca con su país los edificios y ciudadanos que aún no lo tienen.
static func stamp(gs, iso: String) -> void:
	if iso == "":
		return
	for b in gs.buildings:
		if str(b.get("country_id", "")) == "":
			b["country_id"] = iso
	for c in gs.citizens.values():
		if c.country_id == "":
			c.country_id = iso


# --- Países del mapa ------------------------------------------------------------------------------

static func is_real_game(gs) -> bool:
	return WorldData.is_real(home_id(gs))


## Países a los que se puede entrar: reales si la partida es real, los de respaldo si no.
static func enterable_ids(gs) -> Array:
	if is_real_game(gs):
		return WorldData.playable_ids()
	return MapSim.country_ids()


static func country_label(iso: String) -> String:
	if WorldData.is_real(iso):
		return WorldData.country_name(iso)
	return str(MapSim.country_def(iso).get("label", iso))


static func mods(iso: String) -> Dictionary:
	var all: Dictionary = cfg().get("countries", {})
	var d: Dictionary = all.get("default", {}).duplicate()
	d.merge(all.get(iso, {}), true)
	return d


static func town_name_for(iso: String) -> String:
	if WorldData.is_real(iso):
		var n := str(WorldData.country_meta(iso).get("start_name", ""))
		if n != "":
			return n
	return "Puerto %s" % country_label(iso)


# --- Licencia y entrada ---------------------------------------------------------------------------

static func license_cost(gs, iso: String) -> float:
	var l: Dictionary = cfg().get("license", {})
	return snappedf(float(l.get("base_cost", 6000.0)) * float(mods(iso).get("license_mult", 1.0)) * gs.price_mult(), 1.0)


static func license_block_reason(gs, iso: String) -> String:
	if not ready(gs):
		return "Sin estado de países"
	if iso == home_id(gs):
		return "Es tu país de origen"
	if not enterable_ids(gs).has(iso):
		return "País no jugable en esta partida"
	if has_context(gs, iso):
		return "Ya tienes licencia en %s" % country_label(iso)
	var cost := license_cost(gs, iso)
	if gs.money < cost:
		return "Dinero insuficiente (%s)" % Fmt.money(cost)
	return ""


## Compra la licencia de inversión: genera el país (mapa, municipios, pueblo, gobierno) y el pago va al
## tesoro de ese país.
static func buy_license(gs, iso: String) -> String:
	var reason := license_block_reason(gs, iso)
	if reason != "":
		return reason
	var cost := license_cost(gs, iso)
	var ctx := _create_context(gs, iso)
	ctx["government"]["treasury"] = float(ctx["government"].get("treasury", 0.0)) + cost
	gs.add_money(-cost)
	gs.countries["stash"][iso] = ctx
	var p := {"licensed_day": gs.today(), "license_paid": cost, "entered": false, "land_paid": 0.0,
			"manager": {}, "month": {}, "last_month": {}}
	gs.countries["presence"][iso] = p
	gs.countries["stats"]["licenses"] = float(gs.countries["stats"].get("licenses", 0.0)) + cost
	gs.notify("Licencia de inversión en %s aprobada por %s. Ahora compra un terreno allá para tener presencia." % [country_label(iso), Fmt.money(cost)], "importante")
	return ""


## Precio del primer terreno (la parcela central del pueblo de ese país), al Estado de ese país.
static func entry_land_cost(gs, iso: String) -> float:
	if not has_context(gs, iso):
		return 0.0
	var l: Dictionary = cfg().get("license", {})
	var pm: float = with_country(gs, iso, func(): return gs.price_mult())
	return snappedf(float(GameData.game.get("zone_expansion_cost", 2500)) * float(l.get("land_mult", 1.0)) * pm, 1.0)


static func entry_land_block_reason(gs, iso: String) -> String:
	if not has_context(gs, iso):
		return "Primero compra la licencia de inversión"
	if bool(presence(gs, iso).get("entered", false)):
		return "Ya tienes terreno en %s" % country_label(iso)
	var cost := entry_land_cost(gs, iso)
	if gs.money < cost:
		return "Dinero insuficiente (%s)" % Fmt.money(cost)
	return ""


static func buy_entry_land(gs, iso: String) -> String:
	var reason := entry_land_block_reason(gs, iso)
	if reason != "":
		return reason
	var cost := entry_land_cost(gs, iso)
	with_country(gs, iso, func():
		gs.add_money(-cost)
		GovSim.add_treasury(gs, cost)   # Se compra al Estado de ese país.
		var z: Array = gs.START_ZONE.duplicate()
		if not gs.is_zone_unlocked(int(z[0]), int(z[1])):
			gs.unlocked_zones.append(z)
			MapSim.on_zone_bought(gs, int(z[0]), int(z[1]))
		return null)
	var p := presence(gs, iso)
	p["entered"] = true
	p["land_paid"] = cost
	p["since"] = gs.today()
	gs.notify("Compraste tu primer terreno en %s por %s: ya tienes presencia. Contrata un gerente para operar allá sin viajar." % [country_label(iso), Fmt.money(cost)], "importante")
	return ""


## Genera el contexto de un país nuevo con los mismos inicializadores de una partida (sin jugador).
static func _create_context(gs, iso: String) -> Dictionary:
	var was := EventBus.is_blocking_signals()
	EventBus.set_block_signals(true)
	var prev := _current
	stamp(gs, prev)
	var saved := _pack(gs)
	for k in PER_COUNTRY:
		match k:
			"citizens":
				gs.citizens = {}
			"buildings":
				gs.buildings = []
			"unlocked_zones":
				gs.unlocked_zones = []
			"season":
				gs.season = ""
			_:
				gs.set(k, {})
	gs.settings["country_id"] = iso
	gs.settings["town_name"] = town_name_for(iso)
	gs.settings.erase("region")
	gs.map = {"country_id": iso}
	_current = iso
	_fx_mult = 1.0
	gs._reindex()
	_invalidate_caches()
	var old_check := NpcBusinessSim._terrain_check
	NpcBusinessSim.set_terrain_check(Callable())
	EconomySim.init_state(gs)
	EventsSim.init_state(gs)
	WeatherSim.init_weather(gs)
	PopulationSim.generate_initial(gs, int(cfg().get("license", {}).get("start_citizens", 26)))
	GovSim.init_state(gs)
	gs.government["tax_mult"] = float(mods(iso).get("tax_mult", 1.0))
	gs.government["country_id"] = iso
	gs.init_country_systems()
	stamp(gs, iso)
	var ctx := _pack(gs)
	_unpack(gs, saved)
	_current = prev
	_fx_mult = fx_price_mult(gs, prev)
	NpcBusinessSim.set_terrain_check(old_check)
	EventBus.set_block_signals(was)
	return ctx


# --- Intercambio de contexto ----------------------------------------------------------------------

static func _pack(gs) -> Dictionary:
	var d := {}
	for k in PER_COUNTRY:
		d[k] = gs.get(k)
	var s := {}
	for k in SETTINGS_KEYS:
		if gs.settings.has(k):
			s[k] = gs.settings[k]
	d["_settings"] = s
	return d


static func _unpack(gs, d: Dictionary) -> void:
	for k in PER_COUNTRY:
		if d.has(k):
			gs.set(k, d[k])
	var s: Dictionary = d.get("_settings", {})
	for k in SETTINGS_KEYS:
		if s.has(k):
			gs.settings[k] = s[k]
		else:
			gs.settings.erase(k)
	gs._reindex()
	_invalidate_caches()


## Cachés estáticas de los sistemas que no llevan el país en su clave.
static func _invalidate_caches() -> void:
	RealEstateSim._idx_dirty = true
	GridSim._memo_fast = ""
	GridSim._memo_slow = ""
	GridSim._memo = {}
	WarehouseSim._ids_key = ""
	WaterSim._plants_key = ""
	TransitSim._route_status = {}
	MarketSim._offers = {}


## Carga en GameState los datos del país `iso` (y guarda los del actual). No emite señales.
static func swap_to(gs, iso: String) -> void:
	if iso == _current or not ready(gs):
		return
	var stash: Dictionary = gs.countries["stash"]
	if not stash.has(iso):
		push_warning("CountriesSim: no hay datos del país %s" % iso)
		return
	stamp(gs, _current)
	stash[_current] = _pack(gs)
	var d: Dictionary = stash[iso]
	stash.erase(iso)
	_unpack(gs, d)
	_current = iso
	_fx_mult = fx_price_mult(gs, iso)


## Precios de un país extranjero vistos desde tu cuenta: si su moneda está débil en términos reales
## (desvío > 1), todo allá te sale más barato, y al revés. 1 en tu país de origen.
static func fx_price_mult(gs, iso: String) -> float:
	if not ready(gs) or iso == home_id(gs) or not GlobalEconSim.ready(gs):
		return 1.0
	var h := GlobalEconSim.real_index(gs, home_id(gs))
	var f := GlobalEconSim.real_index(gs, iso)
	return clampf(h / maxf(0.01, f), 0.8, 1.25)


## Ejecuta `fn` con el país `iso` cargado y vuelve al anterior. Si no es el país que se ve, bloquea las
## señales (el mundo 3D no se entera) y muestra después sus avisos.
static func with_country(gs, iso: String, fn: Callable) -> Variant:
	if iso == _current or not has_context(gs, iso):
		return fn.call() if iso == _current else null
	var prev := _current
	var was := EventBus.is_blocking_signals()
	var hide: bool = iso != active_id(gs)
	if hide:
		EventBus.set_block_signals(true)
	swap_to(gs, iso)
	var r = fn.call()
	swap_to(gs, prev)
	if hide and not was:
		EventBus.set_block_signals(false)
		gs.flush_deferred_notes()
	return r


## Cambia el país que se ve (y que queda cargado en GameState). La interfaz recarga la escena.
static func set_active(gs, iso: String) -> String:
	if not has_context(gs, iso):
		return "No tienes presencia en %s" % country_label(iso)
	swap_to(gs, iso)
	gs.countries["active"] = iso
	gs.countries["pending_view"] = ""
	return ""


## Prefijo de los avisos del país que se simula cuando no es el que se ve.
static func note_prefix(gs) -> String:
	if not ready(gs) or _current == "" or _current == active_id(gs):
		return ""
	return "[%s] " % country_label(_current)


# --- Control y rendimiento por país ---------------------------------------------------------------

## ¿Puede el jugador dar órdenes directas en el país (está ahí o tiene gerente)?
static func can_control(gs, iso: String) -> bool:
	if not ready(gs):
		return true
	return location(gs) == iso or ManagerSim.has_manager(gs, iso)


## "" si se puede construir/comprar en el país cargado; si no, el motivo (vista remota sin gerente).
static func control_block_reason(gs) -> String:
	if not ready(gs) or _current == "" or can_control(gs, _current):
		return ""
	var loc := location(gs)
	return "Vista remota de %s: %s. Contrata un gerente local o viaja allá." % [country_label(_current),
			"estás de viaje" if loc == "" else "estás en %s" % country_label(loc)]


## Rendimiento de los negocios del país que se simula (BusinessSim.expected_output).
static func op_mult() -> float:
	return _op_mult


## ¿Avanzan las obras del jugador en el país que se simula? (ConstructionSim.daily)
static func works_advance() -> bool:
	return _works


static func work_mult() -> float:
	return _work_mult


static func _set_pass_mods(gs, iso: String) -> void:
	_op_mult = ManagerSim.output_mult(gs, iso)
	_works = can_control(gs, iso)
	_work_mult = ManagerSim.work_mult(gs, iso)
	if iso != active_id(gs):
		if NpcBusinessSim._terrain_check.is_valid():
			_saved_check = NpcBusinessSim._terrain_check
		NpcBusinessSim.set_terrain_check(Callable())   # El terreno 3D cargado es el del país que se ve.
	elif _saved_check.is_valid():
		NpcBusinessSim.set_terrain_check(_saved_check)
		_saved_check = Callable()


static func _reset_mods() -> void:
	_op_mult = 1.0
	_work_mult = 1.0
	_works = true
	if _saved_check.is_valid():
		NpcBusinessSim.set_terrain_check(_saved_check)
		_saved_check = Callable()


# --- Día ------------------------------------------------------------------------------------------

## Antes del pase principal: carga el país de origen.
static func day_begin(gs) -> void:
	if not ready(gs):
		return
	var home := home_id(gs)
	if _current != home and has_context(gs, home):
		if not EventBus.is_blocking_signals():
			EventBus.set_block_signals(true)
			_blocked_by_us = true
		swap_to(gs, home)
	elif home != active_id(gs) and not EventBus.is_blocking_signals():
		EventBus.set_block_signals(true)
		_blocked_by_us = true
	_set_pass_mods(gs, home)
	gs.set_meta("f10_t0", Time.get_ticks_usec())


## Después del pase principal: un pase por cada otro país con presencia y vuelta al país activo.
static func day_end(gs, new_month: bool) -> void:
	if not ready(gs):
		return
	var home := home_id(gs)
	var active := active_id(gs)
	var perf: Dictionary = _perf
	var t_home := float(Time.get_ticks_usec() - int(gs.get_meta("f10_t0", Time.get_ticks_usec()))) / 1000.0
	_perf_add(perf, home, t_home)
	ManagerSim.country_day(gs, home, new_month)
	if new_month:
		_close_month(gs, home)
	for iso in presence_ids(gs):
		if iso == home or not gs.running:
			continue
		var hide: bool = iso != active
		if hide and not EventBus.is_blocking_signals():
			EventBus.set_block_signals(true)
			_blocked_by_us = true
		elif not hide and _blocked_by_us:
			EventBus.set_block_signals(false)
			_blocked_by_us = false
		var t0 := Time.get_ticks_usec()
		swap_to(gs, iso)
		_set_pass_mods(gs, iso)
		gs.simulate_country_day(new_month, false)
		ManagerSim.country_day(gs, iso, new_month)
		if new_month:
			_close_month(gs, iso)
		_perf_add(perf, iso, float(Time.get_ticks_usec() - t0) / 1000.0)
	if _current != active:
		if not EventBus.is_blocking_signals():
			EventBus.set_block_signals(true)
			_blocked_by_us = true
		swap_to(gs, active)
	_reset_mods()
	if _blocked_by_us:
		EventBus.set_block_signals(false)
		_blocked_by_us = false
	gs.flush_deferred_notes()
	stamp(gs, _current)
	TravelSim.daily(gs)
	AirSim.daily(gs)
	if not gs.running:
		EventBus.player_died.emit()   # Pudo emitirse con las señales bloqueadas (pase de origen oculto).


## Tiempo de simulación por país: {iso: {avg, last, n}} (ms por día).
static func perf() -> Dictionary:
	return _perf


static func _perf_add(perf: Dictionary, iso: String, ms: float) -> void:
	var p: Dictionary = perf.get(iso, {"avg": ms, "n": 0})
	p["avg"] = float(p["avg"]) * 0.9 + ms * 0.1 if int(p["n"]) > 0 else ms
	p["n"] = int(p["n"]) + 1
	p["last"] = ms
	perf[iso] = p


## Resultados del mes del país cargado (para el panel Mis países).
static func _close_month(gs, iso: String) -> void:
	var p := presence(gs, iso)
	if p.is_empty():
		return
	var inc := 0.0
	var exp := 0.0
	var n := 0
	var biz := 0
	for b in gs.buildings:
		if not gs.owned_by_player(b):
			continue
		n += 1
		if BusinessSim.is_business(b):
			biz += 1
		var led: Dictionary = b.get("ledger", {}).get("last_month", {})
		for k in led:
			if k in BusinessSim.INCOME_KEYS:
				inc += float(led[k])
			elif not k in BusinessSim.NON_PNL_KEYS:
				exp += float(led[k])
	p["last_month"] = {"income": inc, "expenses": exp, "profit": inc - exp, "buildings": n, "businesses": biz,
			"population": gs.citizens.size(), "treasury": float(gs.government.get("treasury", 0.0)),
			"price_level": gs.price_level(), "day": gs.today()}


# --- Resumen por país (interfaz y pruebas) --------------------------------------------------------

## {population, buildings, businesses, works (obras propias), treasury, money_total} del país.
static func summary(gs, iso: String) -> Dictionary:
	var r = with_country(gs, iso, func():
		var own := 0
		var biz := 0
		var works := 0
		for b in gs.buildings:
			if gs.owned_by_player(b):
				own += 1
				if BusinessSim.is_business(b):
					biz += 1
				if str(b.get("status", "")) in ["construccion", "mejorando"]:
					works += 1
		var snap := FreeMarketSim.money_snapshot(gs)
		return {"population": gs.citizens.size(), "buildings": own, "businesses": biz, "works": works,
				"treasury": float(gs.government.get("treasury", 0.0)), "money_local": float(snap["total"]) - gs.money,
				"town": str(gs.settings.get("town_name", "")), "price_level": gs.price_level(),
				"municipalities": MapSim.municipalities(gs).size()})
	return r if r is Dictionary else {}


## Dinero total de todas las economías simuladas + el que ya salió (pasajes, combustible, fletes)
## + el de fuera de los pueblos (bolsa, aseguradora). Sirve para comprobar que nada aparece de la nada.
static func money_total(gs) -> float:
	var total: float = gs.money
	for iso in licensed_ids(gs):
		var v = with_country(gs, iso, func(): return float(FreeMarketSim.money_snapshot(gs)["total"]) - gs.money)
		total += float(v)
	return total + GlobalEconSim.outside_money(gs)


static func add_outflow(gs, amount: float) -> void:
	if ready(gs):
		gs.countries["stats"]["outflow"] = float(gs.countries["stats"].get("outflow", 0.0)) + amount


# --- Aleatoriedad propia (no altera la del pueblo) -------------------------------------------------

static func rf(gs) -> float:
	var r := RandomNumberGenerator.new()
	r.state = int(str(gs.countries.get("rng_state", "1")))
	var v := r.randf()
	gs.countries["rng_state"] = str(r.state)
	return v


# --- Guardado -------------------------------------------------------------------------------------

## Copia serializable (los ciudadanos de los países guardados pasan a diccionarios).
static func to_save(gs) -> Dictionary:
	if not ready(gs):
		return {}
	var s: Dictionary = gs.countries.duplicate()
	var stash := {}
	for iso in gs.countries["stash"]:
		var d: Dictionary = gs.countries["stash"][iso]
		var o := d.duplicate()
		var cit := []
		for c in d.get("citizens", {}).values():
			cit.append(c.to_dict())
		o["citizens"] = cit
		stash[iso] = o
	s["stash"] = stash
	return s


static func from_save(d: Dictionary) -> Dictionary:
	if d.is_empty():
		return {}
	var s := d.duplicate()
	var stash := {}
	for iso in d.get("stash", {}):
		var o: Dictionary = d["stash"][iso].duplicate()
		var cit := {}
		for cd in o.get("citizens", []):
			var c := Citizen.from_dict(cd)
			cit[c.id] = c
		o["citizens"] = cit
		var bl := []
		for b in o.get("buildings", []):
			bl.append(ConstructionSim.normalize_building(b))
		o["buildings"] = bl
		stash[iso] = o
	s["stash"] = stash
	return s
