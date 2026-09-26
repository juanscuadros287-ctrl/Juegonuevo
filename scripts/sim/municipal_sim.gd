class_name MunicipalSim
extends RefCounted
## Fase 9B — Municipios y departamentos del país con nombre, alcalde/gobernador NPC y política local.
## Estado en GameState.map:
##   regions       {"<id municipio>": {id, name, department, town, player, population, policy{local_tax, min_wage,
##                  regulation, land_price}, mayor{name, stance, since_day, term_end_day}, treasury, tax_exempt_until,
##                  trade_town_id}}
##   departments   {"d<k>": {id, name, governor{name, stance}, municipalities[]}}
##   region_missions {available[], active[], done, failed, next_day}
## Reglas aplicadas a lo que construyes en un municipio (GovSim): impuesto local (±) sobre la ganancia
## del negocio y salario mínimo local. La regulación alta encarece la obra y obliga a licitar la tierra.


static func cfg() -> Dictionary:
	return GameData.extra("municipios")


static func key(zid: int) -> String:
	return str(zid)


# --- Creación y migración -----------------------------------------------------------------------------

## Crea (o completa en partidas 9A) los municipios, departamentos y misiones regionales.
static func init_state(gs) -> void:
	var m: Dictionary = gs.map
	var g := MapSim.gen(gs)
	var regs: Dictionary = m.get("regions", {})
	if regs.size() != g.zones.size() or not regs.has("0") or not (regs["0"] is Dictionary) or not regs["0"].has("policy"):
		regs = _generate(gs, g)
	m["regions"] = regs
	if not m.has("departments") or not (m["departments"] is Dictionary) or m["departments"].is_empty():
		m["departments"] = _departments(gs, g, regs)
	if not m.has("region_missions") or not (m["region_missions"] is Dictionary):
		m["region_missions"] = {"available": [], "active": [], "done": 0, "failed": 0, "next_day": gs.today() + 60}
	# El nombre del municipio del jugador sigue al de su pueblo.
	regs["0"]["name"] = str(gs.settings.get("town_name", regs["0"].get("name", "Tu pueblo")))


static func _rng(gs, salt: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = int(gs.settings.get("seed", 1)) * 7919 + MapSim.country_id(gs).hash() % 100000 + salt
	return r


static func _generate(gs, g: CountryGen) -> Dictionary:
	var c := cfg()
	var r := _rng(gs, 31)
	var names: Array = c.get("names", []).duplicate()
	names.erase(str(gs.settings.get("town_name", "")))
	for t in gs.trade.get("towns", []):
		names.erase(str(t.get("name", "")))
	var pre: Dictionary = c.get("prefix_by_biome", {})
	var pol: Dictionary = c.get("policy", {})
	var stances: Array = c.get("stances", {}).keys()
	var regs := {}
	var used := {}
	for z in g.zones:
		var zid := int(z["id"])
		var player := bool(z["player"])
		var nm := str(gs.settings.get("town_name", "Tu pueblo"))
		if not player and str(z.get("real_name", "")) != "" and not used.has(str(z["real_name"])):
			nm = str(z["real_name"])   # país real: el municipio lleva el nombre de su lugar poblado real
		elif not player and g.real and not _real_name_in(g, zid, used).is_empty():
			var rp := _real_name_in(g, zid, used)
			nm = str(rp["name"])
		elif not player:
			nm = _unique_name(r, names, used, zid)
			var cp: Vector2 = z["town_pos"] if bool(z["town"]) else z["centroid"]
			var biome := g.biome_at(cp.x, cp.y)
			var opts: Array = pre.get(biome, [])
			if not opts.is_empty() and r.randf() < float(c.get("prefix_chance", 0.35)):
				nm = "%s %s" % [str(opts[r.randi() % opts.size()]), nm]
		used[nm] = true
		var stance := str(stances[r.randi() % stances.size()]) if not stances.is_empty() else "conservador"
		var policy := {"local_tax": 0.0, "min_wage": 0.0, "regulation": "media", "land_price": 800.0}
		if not player:
			policy = _random_policy(r, pol, stance)
		var pop := int(r.randf_range(300, 3200)) if bool(z["town"]) else int(r.randf_range(20, 220))
		if int(z.get("real_pop", 0)) > 0:
			pop = clampi(int(z["real_pop"]) / 60, 400, 12000)   # a escala del juego
		regs[key(zid)] = {"id": zid, "name": nm, "department": "", "town": bool(z["town"]), "player": player,
				"population": pop, "policy": policy, "mayor": _new_mayor(gs, r, stance), "treasury": 0.0,
				"tax_exempt_until": -1, "trade_town_id": ""}
	return regs


## País real: el lugar poblado real más grande dentro del municipio que aún no da nombre a otro.
static func _real_name_in(g: CountryGen, zid: int, used: Dictionary) -> Dictionary:
	for pl in g.places:
		var c := CountryGen.chunk_of(float(pl["x"]), float(pl["z"]))
		if g.zone_index(c.x, c.y) == zid and not used.has(str(pl["name"])):
			return pl
	return {}


static func _unique_name(r: RandomNumberGenerator, names: Array, used: Dictionary, zid: int) -> String:
	for i in range(8):
		if names.is_empty():
			break
		var idx := r.randi() % names.size()
		var nm := str(names[idx])
		names.remove_at(idx)
		if not used.has(nm):
			return nm
	return "Municipio %d" % zid


static func _random_policy(r: RandomNumberGenerator, pol: Dictionary, stance: String) -> Dictionary:
	var sd: Dictionary = cfg().get("stances", {}).get(stance, {})
	var lt: Array = pol.get("local_tax", [-0.05, 0.09])
	var tax := clampf(r.randf_range(float(lt[0]), float(lt[1])) + float(sd.get("tax_bias", 0.0)), float(lt[0]), float(lt[1]))
	var mwr: Array = pol.get("min_wage", [0.0, 3.2])
	var mw := 0.0
	if r.randf() < float(pol.get("min_wage_chance", 0.45)) + float(sd.get("wage_bias", 0.0)) * 0.3:
		mw = clampf(r.randf_range(float(mwr[0]) + 1.0, float(mwr[1])) + float(sd.get("wage_bias", 0.0)), 0.0, float(mwr[1]))
	var regs: Array = pol.get("regulation", ["baja", "media", "alta"])
	var ri := clampi(r.randi_range(0, regs.size() - 1) + int(sd.get("reg_bias", 0)), 0, regs.size() - 1)
	var lp: Array = pol.get("land_price", [380, 1100])
	return {"local_tax": snappedf(tax, 0.005), "min_wage": snappedf(mw, 0.1), "regulation": str(regs[ri]),
			"land_price": snappedf(r.randf_range(float(lp[0]), float(lp[1])), 10.0)}


static func _new_mayor(gs, r: RandomNumberGenerator, stance: String) -> Dictionary:
	var nd: Dictionary = GameData.extra("names")
	var male := r.randf() < 0.6
	var firsts: Array = nd.get("male" if male else "female", ["Juan"])
	var sur: Array = nd.get("surnames", ["Pérez"])
	var nm := "%s %s %s" % [str(firsts[r.randi() % firsts.size()]), str(sur[r.randi() % sur.size()]), str(sur[r.randi() % sur.size()])]
	var term := int(cfg().get("term_months", 48)) * 30
	var start: int = gs.today() - r.randi_range(0, term - 30)
	return {"name": nm, "title": "Alcalde" if male else "Alcaldesa", "stance": stance, "since_day": start, "term_end_day": start + term}


## Departamentos: agrupación de municipios cercanos, cada uno con su gobernador.
static func _departments(gs, g: CountryGen, regs: Dictionary) -> Dictionary:
	var dc: Dictionary = cfg().get("departments", {})
	var k := clampi(int(dc.get("count", 5)), 1, g.zones.size())
	var r := _rng(gs, 97)
	var centers: Array[Vector2] = [g.zones[0]["centroid"]]
	while centers.size() < k:
		# El centro más lejano de los ya elegidos (reparto parejo).
		var best := Vector2.ZERO
		var bd := -1.0
		for z in g.zones:
			var p: Vector2 = z["centroid"]
			var dmin := 1e18
			for c in centers:
				dmin = minf(dmin, p.distance_squared_to(c))
			if dmin > bd:
				bd = dmin
				best = p
		centers.append(best)
	var names: Array = dc.get("names", []).duplicate()
	var deps := {}
	var stances: Array = cfg().get("stances", {}).keys()
	for i in range(k):
		var nm := str(names[i]) if i < names.size() else "Departamento %d" % (i + 1)
		var gov := _new_mayor(gs, r, str(stances[r.randi() % stances.size()]) if not stances.is_empty() else "conservador")
		gov["title"] = "Gobernador" if str(gov["title"]) == "Alcalde" else "Gobernadora"
		deps["d%d" % i] = {"id": "d%d" % i, "name": nm, "governor": gov, "municipalities": []}
	for z in g.zones:
		var p: Vector2 = z["centroid"]
		var bi := 0
		var bd2 := 1e18
		for i in range(centers.size()):
			var dd := p.distance_squared_to(centers[i])
			if dd < bd2:
				bd2 = dd
				bi = i
		var dk := "d%d" % bi
		(deps[dk]["municipalities"] as Array).append(int(z["id"]))
		regs[key(int(z["id"]))]["department"] = dk
	return deps


# --- Consultas ------------------------------------------------------------------------------------------

static func region(gs, zid: int) -> Dictionary:
	return gs.map.get("regions", {}).get(key(zid), {})


static func zone_id_at(gs, x: float, z: float) -> int:
	var g := MapSim.gen(gs)
	var c := MapSim.chunk_of(x, z)
	return g.zone_index(c.x, c.y)


## Región real en un punto: municipio con su política, alcalde y departamento. {} fuera del país.
static func region_at(gs, x: float, z: float) -> Dictionary:
	var zid := zone_id_at(gs, x, z)
	if zid < 0:
		return {}
	var reg := region(gs, zid)
	if reg.is_empty():
		return {}
	var dep: Dictionary = gs.map.get("departments", {}).get(str(reg.get("department", "")), {})
	var out: Dictionary = reg.duplicate(true)
	out["id"] = "m%d" % zid
	out["municipality_id"] = zid
	out["department_name"] = str(dep.get("name", ""))
	out["governor"] = dep.get("governor", {})
	out["country_id"] = MapSim.country_id(gs)
	return out


static func name_of(gs, zid: int) -> String:
	return str(region(gs, zid).get("name", "Municipio %d" % zid))


static func policy_of(gs, zid: int) -> Dictionary:
	return region(gs, zid).get("policy", {})


static func stance_label(stance: String) -> String:
	return str(cfg().get("stances", {}).get(stance, {}).get("label", stance.capitalize()))


static func regulation_label(r: String) -> String:
	return {"baja": "baja", "media": "media", "alta": "alta (solo licitación)"}.get(r, r)


## Municipio de un edificio (-1 fuera del país).
static func zone_of_building(gs, b: Dictionary) -> int:
	return zone_id_at(gs, float(b.get("x", 0.0)), float(b.get("z", 0.0)))


## Tasa del impuesto local para un edificio (0 si está exento por una misión).
static func local_tax_rate(gs, b: Dictionary) -> float:
	var zid := zone_of_building(gs, b)
	if zid < 0:
		return 0.0
	var reg := region(gs, zid)
	if int(reg.get("tax_exempt_until", -1)) >= gs.today() and float(reg.get("policy", {}).get("local_tax", 0.0)) > 0.0:
		return 0.0
	return float(reg.get("policy", {}).get("local_tax", 0.0))


## Salario mínimo local diario (0 = solo el nacional) de un edificio.
static func min_wage_for(gs, b: Dictionary) -> float:
	var zid := zone_of_building(gs, b)
	if zid < 0:
		return 0.0
	return float(policy_of(gs, zid).get("min_wage", 0.0)) * gs.price_level()


## Multiplicador del costo de obra por la regulación del municipio.
static func build_mult(gs, x: float, z: float) -> float:
	var zid := zone_id_at(gs, x, z)
	if zid < 0:
		return 1.0
	var r := str(policy_of(gs, zid).get("regulation", "media"))
	return float(cfg().get("policy", {}).get("regulation_build_mult", {}).get(r, 1.0))


## Impuesto local de un negocio (lo llama GovSim al cobrar impuestos). Positivo: se paga al municipio;
## negativo: rebaja (el municipio devuelve parte de la ganancia). Devuelve lo cobrado (neto).
static func collect_local_tax(gs, b: Dictionary, profit: float) -> float:
	if profit <= 0.0:
		return 0.0
	var rate := local_tax_rate(gs, b)
	if absf(rate) < 0.0001:
		return 0.0
	var t := profit * rate
	var reg := region(gs, zone_of_building(gs, b))
	if t > 0.0:
		BusinessSim.pay(gs, b, t, "impuestos")
		reg["treasury"] = float(reg.get("treasury", 0.0)) + t
	else:
		BusinessSim.earn(gs, b, -t, "subsidios")
		reg["treasury"] = float(reg.get("treasury", 0.0)) + t
	return t


# --- Mensual: alcaldes, misiones ------------------------------------------------------------------------

static func monthly(gs) -> void:
	_elections(gs)
	_check_missions(gs)
	var rm: Dictionary = gs.map.get("region_missions", {})
	if gs.today() >= int(rm.get("next_day", 0)):
		_offer_missions(gs)
		rm["next_day"] = gs.today() + int(cfg().get("missions_every_months", 4)) * 30


## Fin del mandato: nuevo alcalde y la política se mueve un poco según su postura.
static func _elections(gs) -> void:
	var r := _rng(gs, gs.today())
	var stances: Array = cfg().get("stances", {}).keys()
	for k in gs.map.get("regions", {}):
		var reg: Dictionary = gs.map["regions"][k]
		var mayor: Dictionary = reg.get("mayor", {})
		if gs.today() < int(mayor.get("term_end_day", 1 << 30)):
			continue
		var stance := str(stances[r.randi() % stances.size()])
		reg["mayor"] = _new_mayor(gs, r, stance)
		reg["mayor"]["since_day"] = gs.today()
		reg["mayor"]["term_end_day"] = gs.today() + int(cfg().get("term_months", 48)) * 30
		if bool(reg.get("player", false)):
			continue   # el municipio del jugador conserva la política neutra (la nacional manda)
		var np := _random_policy(r, cfg().get("policy", {}), stance)
		var p: Dictionary = reg["policy"]
		p["local_tax"] = snappedf(lerpf(float(p["local_tax"]), float(np["local_tax"]), 0.5), 0.005)
		p["min_wage"] = snappedf(lerpf(float(p["min_wage"]), float(np["min_wage"]), 0.5), 0.1)
		p["regulation"] = np["regulation"]
		if MapSim.zone_revealed_any(gs, int(reg["id"])):
			gs.notify("%s tiene nuevo %s: %s (%s). Impuesto local %+.1f%%." % [reg["name"], str(reg["mayor"]["title"]).to_lower(), reg["mayor"]["name"], stance_label(stance), float(p["local_tax"]) * 100.0], "info")


static func _mission_value(gs, m: Dictionary) -> float:
	var zid := int(m.get("zone", -1))
	match str(m.get("type", "")):
		"buildings_in":
			var n := 0
			for b in gs.buildings:
				if gs.owned_by_player(b) and BusinessSim.is_business(b) and str(b.get("status", "")) == "activo" and zone_of_building(gs, b) == zid:
					n += 1
			return float(n)
		"land_in":
			return float(LandSim.player_parcels_in(gs, zid))
		"route_to":
			var tid := str(region(gs, zid).get("trade_town_id", ""))
			return 1.0 if tid != "" and not TradeSim.connection(gs, tid).is_empty() else 0.0
		"jobs_in":
			var ids := {}
			for b in gs.buildings:
				if gs.owned_by_player(b) and zone_of_building(gs, b) == zid:
					ids[int(b["id"])] = true
			var n2 := 0
			for c in gs.citizens.values():
				if c.job_kind == "empleo" and ids.has(c.job_id):
					n2 += 1
			return float(n2)
		"road_in":
			var total := 0.0
			for rd in RoadSim.roads(gs):
				var a := RoadSim.seg_a(rd)
				var b2 := RoadSim.seg_b(rd)
				var mid := (a + b2) * 0.5
				if zone_id_at(gs, mid.x, mid.y) == zid:
					total += a.distance_to(b2)
			return total
	return 0.0


static func mission_done(gs, m: Dictionary) -> bool:
	return _mission_value(gs, m) >= float(m.get("target", 1.0))


static func mission_progress(gs, m: Dictionary) -> String:
	return "%d / meta %d" % [int(_mission_value(gs, m)), int(m.get("target", 1.0))]


## Los alcaldes de municipios explorados (no el tuyo) proponen misiones con recompensa.
static func _offer_missions(gs) -> void:
	var rm: Dictionary = gs.map["region_missions"]
	var avail: Array = rm.get("available", [])
	var active: Array = rm.get("active", [])
	var maxn := int(cfg().get("missions_max", 3))
	if avail.size() + active.size() >= maxn:
		return
	var r := _rng(gs, gs.today() * 3 + 1)
	var busy := {}
	for m in avail + active:
		busy[int(m["zone"])] = true
	var zones := []
	for k in gs.map.get("regions", {}):
		var reg: Dictionary = gs.map["regions"][k]
		if bool(reg.get("player", false)) or busy.has(int(reg["id"])):
			continue
		if MapSim.zone_revealed_any(gs, int(reg["id"])):
			zones.append(int(reg["id"]))
	zones.sort()
	var templates: Array = cfg().get("missions", [])
	while not zones.is_empty() and avail.size() + active.size() < maxn and not templates.is_empty():
		var zid: int = zones[r.randi() % zones.size()]
		zones.erase(zid)
		var reg := region(gs, zid)
		var opts := []
		for t in templates:
			if str(t["type"]) == "route_to" and (str(reg.get("trade_town_id", "")) == "" or not TradeSim.connection(gs, str(reg["trade_town_id"])).is_empty()):
				continue
			opts.append(t)
		if opts.is_empty():
			continue
		var m: Dictionary = (opts[r.randi() % opts.size()] as Dictionary).duplicate(true)
		m["zone"] = zid
		match str(m["type"]):
			"buildings_in":
				m["target"] = _mission_value(gs, m) + 1.0
			"land_in":
				m["target"] = _mission_value(gs, m) + 10.0
			"route_to":
				m["target"] = 1.0
			"jobs_in":
				m["target"] = _mission_value(gs, m) + 5.0
			"road_in":
				m["target"] = floorf(_mission_value(gs, m)) + 300.0
		m["label"] = str(m["label"]).replace("{n}", str(int(m["target"]) if str(m["type"]) != "land_in" else 10)).replace("{m}", str(reg.get("name", "")))
		m["reward_money"] = float(m.get("reward_money", 0.0)) * gs.price_level()
		m["mayor"] = str(reg.get("mayor", {}).get("name", ""))
		avail.append(m)
		gs.notify("%s %s (%s) propone: %s." % [str(reg.get("mayor", {}).get("title", "Alcalde")), m["mayor"], reg.get("name", ""), m["label"]], "importante")
	rm["available"] = avail


static func accept_mission(gs, idx: int) -> String:
	var rm: Dictionary = gs.map["region_missions"]
	var avail: Array = rm.get("available", [])
	if idx < 0 or idx >= avail.size():
		return "Misión no encontrada"
	var m: Dictionary = avail[idx]
	avail.remove_at(idx)
	m["deadline"] = gs.today() + int(m.get("months", 24)) * 30
	(rm["active"] as Array).append(m)
	return ""


static func _check_missions(gs) -> void:
	var rm: Dictionary = gs.map.get("region_missions", {})
	var active: Array = rm.get("active", [])
	for m in active.duplicate():
		var reg := region(gs, int(m["zone"]))
		if mission_done(gs, m):
			var paid := float(m.get("reward_money", 0.0))
			gs.add_money(paid)
			gs.add_counter("subsidies", paid)
			reg["treasury"] = float(reg.get("treasury", 0.0)) - paid
			var months := int(m.get("reward_tax_months", 0))
			if months > 0:
				reg["tax_exempt_until"] = maxi(int(reg.get("tax_exempt_until", -1)), gs.today()) + months * 30
			rm["done"] = int(rm.get("done", 0)) + 1
			active.erase(m)
			gs.notify("¡Misión regional cumplida en %s: %s! Recompensa: %s%s." % [reg.get("name", ""), m["label"], Fmt.money(paid),
					" y %d meses sin impuesto local" % months if months > 0 else ""], "importante")
		elif gs.today() > int(m.get("deadline", 0)):
			active.erase(m)
			rm["failed"] = int(rm.get("failed", 0)) + 1
			gs.notify("Misión regional fallida por tiempo: %s." % m["label"], "jugador")


## Texto de la política de un municipio (para la interfaz).
static func policy_text(gs, zid: int) -> String:
	var p := policy_of(gs, zid)
	var tax := float(p.get("local_tax", 0.0))
	var mw := float(p.get("min_wage", 0.0))
	return "Impuesto local %s · Salario mínimo %s · Regulación %s · Suelo base %s/parcela" % [
		"ninguno" if absf(tax) < 0.001 else ("%+.1f%% de la ganancia" % (tax * 100.0)),
		"el nacional" if mw <= 0.0 else "%s/día" % Fmt.money2(mw * gs.price_level()),
		regulation_label(str(p.get("regulation", "media"))),
		Fmt.money(float(p.get("land_price", 800.0)) * gs.price_mult())]
