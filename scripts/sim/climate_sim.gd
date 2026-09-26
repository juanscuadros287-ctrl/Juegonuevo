class_name ClimateSim
extends RefCounted
## Clima y estaciones que afectan la producción (sección D.12, docs/TRABAJO_MUNDO.md).
##
## Eventos de varios días (sequía, helada, inundación, ola de calor, mala cosecha) según la estación y el
## clima de la zona (MapSim.climate_at en la plaza; cada edificio se compara con la plaza). Afectan sobre
## todo al agro (granja, trigal, algodonal, rebaño, estancia…); la inundación también a los edificios junto
## al río (menos producción y una reparación). Mientras duran suben los precios de los bienes agrícolas por
## escasez (EconomySim.good_factor). Con pronóstico (aviso previo) cuando se puede. Mitigación con
## tecnología: efectos "clima" de data/technologies_clima.json (riego, diques, invernaderos).
## Estado: GameState.world_events["climate"]. RNG propio (LaborSim.rf): no altera el resto.

static var _clim_cache: Dictionary = {}     # "id|x|z|clave" -> clima local del edificio
static var _river_cache: Dictionary = {}    # "x|z|clave" -> bool
static var _town_key := ""
static var _town_clim: Dictionary = {}


static func cfg() -> Dictionary:
	return LaborSim.cfg().get("climate", {})


static func ev_def(id: String) -> Dictionary:
	return cfg().get("events", {}).get(id, {})


static func st(gs) -> Dictionary:
	if not gs.world_events.has("climate"):
		gs.world_events["climate"] = {}
	return gs.world_events["climate"]


static func init_state(gs) -> void:
	var s := st(gs)
	if not s.has("events") or not (s["events"] is Array):
		s["events"] = []
	for k in ["price", "bmult"]:
		if not s.has(k) or not (s[k] is Dictionary):
			s[k] = {}
	s["cool_until"] = int(s.get("cool_until", 0))


# --- Clima local ----------------------------------------------------------------------------------------

static func _gen_key(gs) -> String:
	return "%s|%d|%s" % [str(gs.settings.get("map_type", "")), int(gs.settings.get("seed", 0)), MapSim.country_id(gs)]


static func town_climate(gs) -> Dictionary:
	var k := _gen_key(gs)
	if k != _town_key or _town_clim.is_empty():
		_town_key = k
		_town_clim = MapSim.climate_at(0.0, 0.0, gs)
		_clim_cache = {}
		_river_cache = {}
	return _town_clim


static func building_climate(gs, b: Dictionary) -> Dictionary:
	town_climate(gs)
	var key := "%d|%d|%d" % [int(b["id"]), int(float(b.get("x", 0.0))), int(float(b.get("z", 0.0)))]
	if not _clim_cache.has(key):
		_clim_cache[key] = MapSim.climate_at(float(b.get("x", 0.0)), float(b.get("z", 0.0)), gs)
	return _clim_cache[key]


## ¿Hay río o lago a menos de river_radius metros?
static func near_river(gs, b: Dictionary) -> bool:
	town_climate(gs)
	var x := float(b.get("x", 0.0))
	var z := float(b.get("z", 0.0))
	var key := "%d|%d" % [int(x), int(z)]
	if _river_cache.has(key):
		return bool(_river_cache[key])
	var r := float(cfg().get("river_radius", 14.0))
	var found := false
	for p in [Vector2.ZERO, Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r), Vector2(r, r) * 0.7, Vector2(-r, r) * 0.7, Vector2(r, -r) * 0.7, Vector2(-r, -r) * 0.7]:
		if MapSim.biome_at(x + p.x, z + p.y, gs) == "rio":
			found = true
			break
	_river_cache[key] = found
	return found


static func is_agro(def_type: String) -> bool:
	return cfg().get("agro_types", []).has(def_type)


# --- Eventos ------------------------------------------------------------------------------------------------

static func active_events(gs) -> Array:
	return st(gs).get("events", []).filter(func(e): return int(e["start"]) <= gs.today())


static func forecasts(gs) -> Array:
	return st(gs).get("events", []).filter(func(e): return int(e["start"]) > gs.today())


## Probabilidad mensual de un evento según la estación, el clima de la plaza y la dificultad.
static func chance(gs, id: String) -> float:
	var d := ev_def(id)
	var seasons: Array = d.get("seasons", [])
	if not seasons.is_empty() and not seasons.has(gs.season):
		return 0.0
	var c := town_climate(gs)
	var t := float(c.get("temperature", 0.0))
	var h := float(c.get("humidity", 0.0))
	var f := 1.0
	f += float(d.get("dry", 0.0)) * maxf(0.0, -h)
	f += float(d.get("wet", 0.0)) * maxf(0.0, h)
	f += float(d.get("hot", 0.0)) * maxf(0.0, t)
	f += float(d.get("cold", 0.0)) * maxf(0.0, -t)
	f += float(d.get("altitude", 0.0)) * maxf(0.0, float(c.get("altitude", 0.0)))
	if id == "inundacion":
		if str(gs.settings.get("map_type", "")) == "rio":
			f *= float(d.get("rain_boost", 1.5))
		if str(gs.weather.get("type", "")) in ["lluvia", "tormenta"]:
			f *= float(d.get("rain_boost", 1.5))
	return float(d.get("chance", 0.02)) * f * float(gs.diff().get("event_freq_mult", 1.0))


static func monthly(gs) -> void:
	var s := st(gs)
	if not s["events"].is_empty() or gs.today() < int(s.get("cool_until", 0)):
		return
	if gs.problems.get("events", []).any(func(e): return str(e.get("id", "")) == "sequia"):
		return   # Ya hay una sequía general (EventsSim): no se suma otra.
	for id in cfg().get("events", {}):
		if LaborSim.rf(gs, "clima_" + str(id)) < chance(gs, str(id)):
			schedule(gs, str(id))
			return


## Programa un evento: con pronóstico si se puede (empieza en unos días) o de inmediato.
static func schedule(gs, id: String, lead := -1, days := -1, sev := -1.0) -> Dictionary:
	var d := ev_def(id)
	if d.is_empty():
		return {}
	if lead < 0:
		lead = int(d.get("forecast_days", 0))
		var ft := str(d.get("forecast_tech", ""))
		if lead <= 0 and ft != "" and gs.has_tech(ft):
			lead = int(d.get("forecast_tech_days", 3))
	if days < 0:
		days = LaborSim.ri(gs, "clima_dias_" + id, d.get("days", [10, 30]))
	if sev < 0.0:
		sev = snappedf(LaborSim.rr(gs, "clima_sev_" + id, [0.8, 1.2]), 0.01)
	var e := {"id": id, "start": gs.today() + lead, "until": gs.today() + lead + maxi(1, days), "sev": sev, "started": false}
	st(gs)["events"].append(e)
	if lead > 0:
		gs.notify("Pronóstico del tiempo: probable %s en unos %d días (%d días de duración). Prepara tus campos y existencias." % [str(d.get("label", id)).to_lower(), lead, days], "clima")
	else:
		_start(gs, e)
	_refresh(gs)
	return e


static func _start(gs, e: Dictionary) -> void:
	e["started"] = true
	var d := ev_def(str(e["id"]))
	var mit := mitigation(gs, str(e["id"]))
	var extra := "" if mit >= 0.99 else " (tu tecnología reduce el daño un %d %%)" % int(round((1.0 - mit) * 100.0))
	gs.notify("%s%s" % [str(d.get("text", d.get("label", e["id"]))), extra], "importante")
	gs.count("climate_events")
	if str(e["id"]) == "inundacion":
		_flood_damage(gs, e)


## Inundación: reparación de los edificios del jugador junto al río (el dinero sale del pueblo: materiales).
static func _flood_damage(gs, e: Dictionary) -> void:
	var d := ev_def("inundacion")
	var ratio := float(d.get("river_damage", 0.04)) * float(e.get("sev", 1.0)) * mitigation(gs, "inundacion")
	var total := 0.0
	var n := 0
	for b in gs.buildings:
		if not gs.owned_by_player(b) or str(b["status"]) == "construccion" or not near_river(gs, b):
			continue
		var cost: float = float(gs.level_def(b).get("cost", 0.0)) * gs.price_mult() * ratio
		if cost <= 0.0:
			continue
		BusinessSim.pay(gs, b, cost, "reparaciones")
		total += cost
		n += 1
	if n > 0:
		gs.notify("La inundación dañó %d edificios tuyos junto al río: reparaciones por %s." % [n, Fmt.money(total)], "jugador")


static func daily(gs) -> void:
	var s := st(gs)
	var list: Array = s.get("events", [])
	if list.is_empty():
		if not s["price"].is_empty() or not s["bmult"].is_empty():
			s["price"] = {}
			s["bmult"] = {}
		return
	var today: int = gs.today()
	var changed := false
	for e in list.duplicate():
		if not bool(e.get("started", false)) and today >= int(e["start"]):
			_start(gs, e)
			changed = true
		if today >= int(e["until"]):
			list.erase(e)
			s["cool_until"] = today + int(cfg().get("cooldown_days", 60))
			gs.notify("Terminó: %s. El campo se recupera y los precios vuelven a la normalidad." % str(ev_def(str(e["id"])).get("label", e["id"])), "clima")
			changed = true
	if changed or today % 7 == 0:
		_refresh(gs)


# --- Efectos --------------------------------------------------------------------------------------------------

## Multiplicador del daño por la tecnología (1 = sin mitigación).
static func mitigation(gs, id: String) -> float:
	return clampf(TechSim.mult(gs, "clima", id), 0.0, 1.0)


## Sensibilidad local (0,6–1,4) de un edificio según su clima comparado con la plaza.
static func local_sens(gs, b: Dictionary, id: String) -> float:
	var tc := town_climate(gs)
	var bc := building_climate(gs, b)
	var dt := float(bc.get("temperature", 0.0)) - float(tc.get("temperature", 0.0))
	var dh := float(bc.get("humidity", 0.0)) - float(tc.get("humidity", 0.0))
	var s := 1.0
	match id:
		"sequia":
			s = 1.0 - dh * 0.6 + dt * 0.3
		"helada":
			s = 1.0 - dt * 0.8 + maxf(0.0, float(bc.get("altitude", 0.0)) - float(tc.get("altitude", 0.0))) * 0.01
		"ola_calor":
			s = 1.0 + dt * 0.8
		"inundacion":
			s = 1.3 if near_river(gs, b) else 0.8
		_:
			s = 1.0 + dh * 0.3
	return clampf(s, 0.6, 1.4)


## Rendimiento de un edificio por los eventos activos (1 = normal).
static func compute_mult(gs, b: Dictionary) -> float:
	var m := 1.0
	var agro := is_agro(str(b.get("type", "")))
	for e in active_events(gs):
		var id := str(e["id"])
		var d := ev_def(id)
		var mit := mitigation(gs, id)
		if agro:
			var dmg := (1.0 - float(d.get("farming", 1.0))) * float(e.get("sev", 1.0)) * local_sens(gs, b, id) * mit
			m *= clampf(1.0 - dmg, 0.2, 1.0)
		elif id == "inundacion" and str(b.get("status", "")) == "activo" and near_river(gs, b):
			var dmg2 := (1.0 - float(d.get("river_output", 0.6))) * float(e.get("sev", 1.0)) * mit
			m *= clampf(1.0 - dmg2, 0.3, 1.0)
	return m


static func _refresh(gs) -> void:
	var s := st(gs)
	var bm := {}
	var price := {}
	var act := active_events(gs)
	if not act.is_empty():
		for b in gs.buildings:
			if str(b.get("status", "")) != "activo":
				continue
			if not is_agro(str(b.get("type", ""))) and not act.any(func(e): return str(e["id"]) == "inundacion"):
				continue
			var m := compute_mult(gs, b)
			if m < 0.999:
				bm[str(int(b["id"]))] = m
		var share := float(cfg().get("processed_share", 0.5))
		var processed: Array = cfg().get("processed_goods", [])
		for e in act:
			var id := str(e["id"])
			var up := float(ev_def(id).get("price", 0.0)) * float(e.get("sev", 1.0)) * mitigation(gs, id)
			for g in cfg().get("agro_goods", []):
				var k := up * (share if processed.has(g) else 1.0)
				price[g] = float(price.get(g, 1.0)) * (1.0 + k)
	s["bmult"] = bm
	s["price"] = price


## Multiplicador de producción de un edificio (consulta rápida para BusinessSim/NpcBusinessSim).
static func output_mult(gs, b: Dictionary) -> float:
	var bm: Dictionary = gs.world_events.get("climate", {}).get("bmult", {})
	if bm.is_empty():
		return 1.0
	return float(bm.get(str(int(b.get("id", -1))), 1.0))


## Alza de precio por escasez de un bien (1 = normal).
static func price_mult(gs, good: String) -> float:
	var p: Dictionary = gs.world_events.get("climate", {}).get("price", {})
	if p.is_empty() or not p.has(good):
		return 1.0
	if MarketSim.sellers(good).is_empty():
		return 1.0   # Sin productores locales el pueblo se autoabastece o importa: no hay escasez local que encarezca.
	return float(p[good])


## Texto para paneles: eventos activos y pronósticos.
static func summary(gs) -> String:
	var parts := []
	for e in active_events(gs):
		parts.append("%s (%d días más)" % [str(ev_def(str(e["id"])).get("label", e["id"])), maxi(0, int(e["until"]) - gs.today())])
	for e in forecasts(gs):
		parts.append("Pronóstico: %s en %d días" % [str(ev_def(str(e["id"])).get("label", e["id"])).to_lower(), int(e["start"]) - gs.today()])
	return ", ".join(parts)
