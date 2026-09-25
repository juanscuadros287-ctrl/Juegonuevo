class_name WarSim
extends RefCounted
## Guerras entre países sin combate (sección D.15, docs/TRABAJO_MUNDO.md). Moderadas y raras.
##
## Un conflicto entre países ficticios (data/countries.json, sin contar el tuyo) o potencias externas:
##   - encarece o corta la importación de algunos bienes (MarketSim.purchase: import_mult);
##   - sube la demanda (precio de mercado, EconomySim.good_factor) de otros: acero, alimentos, carbón…;
##   - los pueblos conectados piden bienes de guerra (evento del pueblo en GameState.trade: tus
##     exportaciones de ese bien se pagan mejor mientras dure);
##   - aviso en notificaciones y termina solo al cabo de unos meses.
## Estado: GameState.world_events["war"]. RNG propio (LaborSim.rf).


static func cfg() -> Dictionary:
	return LaborSim.cfg().get("wars", {})


static func st(gs) -> Dictionary:
	if not gs.world_events.has("war"):
		gs.world_events["war"] = {}
	return gs.world_events["war"]


static func init_state(gs) -> void:
	var s := st(gs)
	if not s.has("active") or not (s["active"] is Dictionary):
		s["active"] = {}
	s["last_end"] = int(s.get("last_end", -100000))
	s["count"] = int(s.get("count", 0))


static func active(gs) -> Dictionary:
	return gs.world_events.get("war", {}).get("active", {})


static func is_active(gs) -> bool:
	return not active(gs).is_empty()


## Posibles bandos: países de countries.json (menos el tuyo) y potencias externas.
static func parties(gs) -> Array:
	var out := []
	var mine := MapSim.country_id(gs)
	for id in MapSim.country_ids():
		if str(id) != mine:
			out.append(str(MapSim.country_def(str(id)).get("label", id)))
	for p in cfg().get("powers", []):
		out.append(str(p))
	return out


static func monthly(gs) -> void:
	var s := st(gs)
	if is_active(gs):
		return
	var today: int = gs.today()
	if today < int(cfg().get("min_months", 24)) * 30 or today < int(s.get("last_end", -100000)) + int(cfg().get("cooldown_days", 1800)):
		return
	if LaborSim.rf(gs, "guerra") < float(cfg().get("chance_monthly", 0.006)) * float(gs.diff().get("event_freq_mult", 1.0)):
		start_war(gs)


static func _pick(gs, list: Array, n: int, salt: String) -> Array:
	var pool := list.filter(func(g): return GameData.goods.has(str(g)))
	var out := []
	var i := 0
	while out.size() < n and not pool.is_empty():
		var k := int(floor(LaborSim.rf(gs, "%s%d" % [salt, i]) * pool.size())) % pool.size()
		out.append(str(pool[k]))
		pool.remove_at(k)
		i += 1
	return out


## Empieza una guerra (las pruebas pueden forzar la duración en meses).
static func start_war(gs, months := -1) -> Dictionary:
	var c := cfg()
	var ps := parties(gs)
	if ps.size() < 2:
		return {}
	var ia := int(floor(LaborSim.rf(gs, "bando_a") * ps.size())) % ps.size()
	var ib := (ia + 1 + int(floor(LaborSim.rf(gs, "bando_b") * (ps.size() - 1)))) % ps.size()
	if months < 0:
		months = LaborSim.ri(gs, "guerra_meses", c.get("months", [4, 12]))
	var demand := {}
	for g in _pick(gs, c.get("demand_goods", []), LaborSim.ri(gs, "n_dem", c.get("demand_count", [3, 5])), "dem"):
		demand[g] = snappedf(LaborSim.rr(gs, "dm" + g, c.get("demand_mult", [1.1, 1.25])), 0.01)
	var imports := {}
	var cut := []
	for g in _pick(gs, c.get("import_goods", []), LaborSim.ri(gs, "n_imp", c.get("import_count", [2, 4])), "imp"):
		if LaborSim.rf(gs, "cut" + g) < float(c.get("cut_chance", 0.35)):
			imports[g] = float(c.get("cut_mult", 2.0))
			cut.append(g)
		else:
			imports[g] = snappedf(LaborSim.rr(gs, "im" + g, c.get("import_mult", [1.3, 1.6])), 0.01)
	var w := {"a": ps[ia], "b": ps[ib], "start": gs.today(), "until": gs.today() + maxi(1, months) * 30,
		"demand": demand, "imports": imports, "cut": cut, "towns": []}
	# Los pueblos conectados piden bienes de guerra (evento del pueblo, sin pisar uno vigente).
	for conn in gs.trade.get("connections", []):
		var t := TradeSim.town(gs, str(conn.get("town_id", "")))
		if t.is_empty() or not t.get("event", {}).is_empty():
			continue
		for g in demand:
			if t.get("goods", {}).has(g):
				t["event"] = {"good": g, "mult": float(c.get("town_event_mult", 1.3)), "until_day": int(w["until"]), "war": true}
				w["towns"].append(str(conn["town_id"]))
				break
	st(gs)["active"] = w
	st(gs)["count"] = int(st(gs).get("count", 0)) + 1
	gs.count("wars")
	var dem_txt := ", ".join(demand.keys().map(func(g): return GameData.good_label(str(g)).to_lower()))
	var imp_txt := ", ".join(imports.keys().map(func(g): return GameData.good_label(str(g)).to_lower() + (" (cortado)" if cut.has(g) else "")))
	gs.notify("GUERRA entre %s y %s (sin combates aquí). Por unos %d meses sube la demanda de %s y se encarece la importación de %s." % [w["a"], w["b"], months, dem_txt, imp_txt], "importante")
	return w


static func daily(gs) -> void:
	var w := active(gs)
	if w.is_empty() or gs.today() < int(w.get("until", 0)):
		return
	end_war(gs)


static func end_war(gs) -> void:
	var w := active(gs)
	if w.is_empty():
		return
	for tid in w.get("towns", []):
		var t := TradeSim.town(gs, str(tid))
		if not t.is_empty() and bool(t.get("event", {}).get("war", false)):
			t["event"] = {}
	st(gs)["active"] = {}
	st(gs)["last_end"] = gs.today()
	gs.notify("Terminó la guerra entre %s y %s: el comercio y los precios vuelven a la normalidad." % [w.get("a", "?"), w.get("b", "?")], "importante")


## Alza de demanda (precio de mercado) de un bien por la guerra (1 = normal).
static func price_mult(gs, good: String) -> float:
	var w: Dictionary = gs.world_events.get("war", {}).get("active", {})
	if w.is_empty():
		return 1.0
	return float(w.get("demand", {}).get(good, 1.0))


## Encarecimiento de la importación de un bien (2 = cortado: solo contrabando carísimo).
static func import_mult(gs, good: String) -> float:
	var w: Dictionary = gs.world_events.get("war", {}).get("active", {})
	if w.is_empty():
		return 1.0
	return float(w.get("imports", {}).get(good, 1.0))


static func summary(gs) -> String:
	var w := active(gs)
	if w.is_empty():
		return ""
	return "Guerra entre %s y %s (%d días más)" % [w.get("a", "?"), w.get("b", "?"), maxi(0, int(w.get("until", 0)) - gs.today())]
