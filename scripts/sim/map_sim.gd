class_name MapSim
extends RefCounted
## Fase 9A — Mapa del país: chunks de 400 m, revelado (ver) ≠ propiedad (comprar).
## Estado en GameState.map:
##   country_id        país (data/countries.json)
##   chunks_revealed   {"cx,cy": true}  chunk (0,0) = pueblo del jugador (plaza en 0,0)
##   expeditions       [{cx, cy, days_left, cost}] expediciones pagadas en curso
##   parcels           Fase 9B: dueños de territorios que cambiaron {"cx,cy": {owner, name, citizen_id}} (LandSim)
##   regions, departments, region_missions   Fase 9B: municipios con política y alcalde (MunicipalSim)
##   town_assign       Fase 9B: {town_id de TradeSim: id de municipio} (posición real de los pueblos)
##   land_offers, land_tenders, land_sales, land_index, land_demand   Fase 9B: mercado de tierras
## API pública:
##   chunk_of(x, z) · is_revealed(gs, cx, cy) · reveal_around(gs, pos, radius) · biome_at(x, z)
##   owner_of(gs, x, z) · region_at(gs, x, z) · zone_at(gs, x, z) · in_country(gs, x, z)
##   fog_level(gs, cx, cy) · reveal_zone(gs, zid) · trade_town_pos(gs, town_id) · town_zone(gs, town_id)

const CHUNK := 400.0

static var _gen: CountryGen = null
static var _gen_key := ""
static var _gens := {}   # Fase 10: un generador por país con presencia (clave -> CountryGen)


static func cfg() -> Dictionary:
	return GameData.extra("countries")


static func country_ids() -> Array:
	var all: Dictionary = cfg().get("countries", {})
	var ids := all.keys()
	ids.sort_custom(func(a, b): return int(all[a].get("order", 0)) < int(all[b].get("order", 0)))
	return ids


## Países reales jugables del mapa mundial (los de data/countries.json quedan como respaldo de pruebas).
static func real_country_ids() -> Array:
	return WorldData.playable_ids()


const DEFAULT_REAL := "COL"


static func country_def(id: String) -> Dictionary:
	return CountryGen.country_def(id)


static func default_country(map_type: String) -> String:
	var d: Dictionary = cfg().get("default_by_map_type", {})
	var id := str(d.get(map_type, ""))
	if id == "" or not cfg().get("countries", {}).has(id):
		var ids := country_ids()
		id = str(ids[0]) if not ids.is_empty() else ""
	return id


static func country_id(gs) -> String:
	var id := str(gs.map.get("country_id", "")) if gs.map is Dictionary else ""
	if id == "":
		id = str(gs.settings.get("country_id", ""))
	if id == "":
		id = default_country(str(gs.settings.get("map_type", "interior")))
	return id


## Generador del país de la partida (cacheado por tipo de mapa, semilla y país).
static func gen(gs = null) -> CountryGen:
	if gs == null:
		gs = GameState
	var mt := str(gs.settings.get("map_type", "interior"))
	var sd := int(gs.settings.get("seed", 1))
	var cid := country_id(gs)
	var key := "%s|%d|%s" % [mt, sd, cid]
	if _gen == null or key != _gen_key:
		_use_gen(key, mt, sd, cid)
	return _gen


## Fase 10: guarda hasta 4 generadores (uno por país con presencia) para no rehacerlos al cambiar de país.
static func _use_gen(key: String, mt: String, sd: int, cid: String) -> void:
	if not _gens.has(key):
		if _gens.size() >= 4:
			_gens.clear()
		_gens[key] = CountryGen.new().init(mt, sd, cid)
	_gen = _gens[key]
	_gen_key = key


# --- Estado ------------------------------------------------------------------------------------

## Crea o completa GameState.map. Una partida vieja (sin mapa) queda como país con su terreno en el
## chunk central y con el pueblo y sus 8 vecinos revelados.
static func init_state(gs) -> void:
	var m: Dictionary = gs.map
	if not gs.settings.has("country_id"):
		gs.settings["country_id"] = str(m.get("country_id", default_country(str(gs.settings.get("map_type", "interior")))))
	if not m.has("country_id"):
		m["country_id"] = str(gs.settings["country_id"])
	if not m.has("chunks_revealed") or not (m["chunks_revealed"] is Dictionary):
		m["chunks_revealed"] = {}
	for k in ["expeditions"]:
		if not m.has(k):
			m[k] = []
	for k in ["parcels", "regions"]:
		if not m.has(k):
			m[k] = {}
	m["expeditions_done"] = int(m.get("expeditions_done", 0))
	if not (m.get("town_assign") is Dictionary):
		m["town_assign"] = {}
	var r := int(cfg().get("start_reveal_radius", 1))
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			_reveal(gs, dx, dy)
	# Fase 9B: al inicio se revela TODO el municipio del jugador (también en partidas 9A migradas).
	for c in gen(gs).zone_chunks(0):
		_reveal(gs, c.x, c.y)
	# Zonas compradas: su chunk siempre está revelado.
	for z in gs.unlocked_zones:
		var c := chunk_of_zone(int(z[0]), int(z[1]))
		_reveal(gs, c.x, c.y)
	gs.map = m
	MunicipalSim.init_state(gs)   # Fase 9B: municipios, departamentos, alcaldes y política.
	LandSim.init_state(gs)        # Fase 9B: mercado de tierras.


## Fase 9B: se llama al final de la carga/creación (ya existen los pueblos de TradeSim): los ubica en
## municipios reales del país.
static func post_init(gs) -> void:
	assign_towns(gs)


static func key(cx: int, cy: int) -> String:
	return "%d,%d" % [cx, cy]


static func chunk_of(x: float, z: float) -> Vector2i:
	return CountryGen.chunk_of(x, z)


static func chunk_rect(cx: int, cy: int) -> Rect2:
	return CountryGen.chunk_rect(cx, cy)


## Rango de chunks del país: Rect2i(c0, c0, size, size).
static func country_rect(gs = null) -> Rect2i:
	var g := gen(gs)
	return Rect2i(g.c0, g.c0, g.size, g.size)


static func country_bounds_m(gs = null) -> Rect2:
	var g := gen(gs)
	return Rect2(g.x_min, g.x_min, g.x_max - g.x_min, g.x_max - g.x_min)


static func in_country_chunk(gs, cx: int, cy: int) -> bool:
	return gen(gs).in_country_chunk(cx, cy)


static func in_country(gs, x: float, z: float) -> bool:
	return gen(gs).in_country(x, z)


## Número de territorios (chunks) dentro del país (en los reales, dentro de la frontera).
static func country_chunk_count(gs = null) -> int:
	var g := gen(gs)
	var n := 0
	for cy in range(g.c0, g.c1 + 1):
		for cx in range(g.c0, g.c1 + 1):
			if g.in_country_chunk(cx, cy):
				n += 1
	return n


static func is_revealed(gs, cx: int, cy: int) -> bool:
	return gs.map.get("chunks_revealed", {}).has(key(cx, cy))


static func is_revealed_at(gs, x: float, z: float) -> bool:
	var c := chunk_of(x, z)
	return is_revealed(gs, c.x, c.y)


static func revealed_count(gs) -> int:
	return gs.map.get("chunks_revealed", {}).size()


static func revealed_chunks(gs) -> Array:
	var out := []
	for k in gs.map.get("chunks_revealed", {}):
		var p: PackedStringArray = str(k).split(",")
		out.append(Vector2i(int(p[0]), int(p[1])))
	return out


static func _reveal(gs, cx: int, cy: int) -> bool:
	if not gen(gs).in_country_chunk(cx, cy):
		return false
	var rev: Dictionary = gs.map.get("chunks_revealed", {})
	var k := key(cx, cy)
	if rev.has(k):
		return false
	rev[k] = true
	gs.map["chunks_revealed"] = rev
	return true


## Revela un chunk. Devuelve true si era nuevo.
static func reveal(gs, cx: int, cy: int) -> bool:
	var changed := _reveal(gs, cx, cy)
	if changed:
		EventBus.map_changed.emit()
	return changed


## Revela los chunks que toca un círculo de `radius` metros alrededor de `pos` (Vector2 x,z o Vector3).
## Gancho para TradeSim (abrir rutas) y la Fase 9B. Devuelve cuántos chunks nuevos se revelaron.
static func reveal_around(gs, pos, radius: float) -> int:
	var p := Vector2(pos.x, pos.z) if pos is Vector3 else Vector2(pos)
	var n := reveal_around_quiet(gs, p, radius)
	if n > 0:
		EventBus.map_changed.emit()
	return n


# --- Consultas ------------------------------------------------------------------------------

static func biome_at(x: float, z: float, gs = null) -> String:
	return gen(gs).biome_at(x, z)


static func biome_label(id: String) -> String:
	return str(CountryGen.BIOME_LABELS.get(id, id))


static func height_at(x: float, z: float, gs = null) -> float:
	return gen(gs).height(x, z)


## Parcela (zona de compra de 80 m) que contiene un punto, en índices globales (el pueblo es 0..4).
static func zone_at(gs, x: float, z: float) -> Vector2i:
	var zs: float = gs.MAP_SIZE / gs.ZONE_GRID
	var half: float = gs.MAP_SIZE * 0.5
	return Vector2i(floori((x + half) / zs), floori((z + half) / zs))


static func chunk_of_zone(zx: int, zy: int) -> Vector2i:
	var per := 5   # ZONE_GRID (MAP_SIZE / 80 m)
	return Vector2i(floori(float(zx) / per), floori(float(zy) / per))


## Dueño de un punto: "jugador" (parcela comprada), "npc:<nombre>" (particular, Fase 9B), "estado" (resto
## del país) o "" fuera del país.
static func owner_of(gs, x: float, z: float) -> String:
	if not in_country(gs, x, z):
		return ""
	var zc := zone_at(gs, x, z)
	if gs.is_zone_unlocked(zc.x, zc.y):
		return "jugador"
	# Fase 9B: dueño del territorio (Estado o particular NPC) según el mercado de tierras.
	var c := chunk_of_zone(zc.x, zc.y)
	var info := LandSim.owner_info(gs, c.x, c.y)
	if str(info.get("owner", "")) == "npc":
		return "npc:%s" % str(info.get("name", ""))
	return "estado"


## Municipio (Voronoi de chunks) de un punto: {id, town, player, town_pos, town_chunk}; {} fuera del país.
static func municipality_at(gs, x: float, z: float) -> Dictionary:
	var g := gen(gs)
	var c := chunk_of(x, z)
	var i := g.zone_index(c.x, c.y)
	return g.zones[i] if i >= 0 else {}


static func municipalities(gs = null) -> Array:
	return gen(gs).zones


## Región real (Fase 9B): el municipio del punto con su nombre, política, alcalde y departamento.
## {} fuera del país. Campos: id ("m<n>"), municipality_id, name, department, department_name, governor,
## mayor, policy{local_tax, min_wage, regulation, land_price}, town, population, treasury, country_id.
static func region_at(gs, x: float, z: float) -> Dictionary:
	if not in_country(gs, x, z):
		return {}
	return MunicipalSim.region_at(gs, x, z)


## Nivel de niebla de un chunk: 0 explorado, 1 velo ligero (tu municipio y sus vecinos), 2 sin explorar,
## 3 fuera del país.
static func fog_level(gs, cx: int, cy: int) -> int:
	var g := gen(gs)
	if not g.in_country_chunk(cx, cy):
		return 3
	if is_revealed(gs, cx, cy):
		return 0
	var zi := g.zone_index(cx, cy)
	if zi == 0 or (g.zones[0]["neighbors"] as Array).has(zi):
		return 1
	return 2


## ¿Tiene el municipio algún chunk explorado?
static func zone_revealed_any(gs, zid: int) -> bool:
	var g := gen(gs)
	if zid < 0 or zid >= g.zones.size():
		return false
	var tc: Vector2i = g.zones[zid]["town_chunk"]
	if is_revealed(gs, tc.x, tc.y):
		return true
	for c in g.zone_chunks(zid):
		if is_revealed(gs, c.x, c.y):
			return true
	return false


## Revela todo un municipio (sin emitir la señal). Devuelve cuántos chunks eran nuevos.
static func reveal_zone_quiet(gs, zid: int) -> int:
	var n := 0
	for c in gen(gs).zone_chunks(zid):
		if _reveal(gs, c.x, c.y):
			n += 1
	return n


static func reveal_zone(gs, zid: int) -> int:
	var n := reveal_zone_quiet(gs, zid)
	if n > 0:
		EventBus.map_changed.emit()
	return n


# --- Compra de parcelas (se une al instante al terreno del jugador) ---------------------------

## Motivo para no poder comprar una parcela fuera de lo que ya había (país y revelado).
static func zone_map_block_reason(gs, zx: int, zy: int) -> String:
	var c := chunk_of_zone(zx, zy)
	if not in_country_chunk(gs, c.x, c.y):
		return "Fuera del país"
	if not is_revealed(gs, c.x, c.y):
		return "Territorio sin explorar: envía una expedición (minimapa → Ampliar)"
	# Fase 9B: la tierra de un particular se compra con una oferta, no al gobierno.
	if not gs.is_zone_unlocked(zx, zy):
		var info := LandSim.owner_info(gs, c.x, c.y)
		if str(info.get("owner", "")) == "npc":
			return "Terreno privado de %s: hazle una oferta (minimapa → Ampliar)" % str(info.get("name", ""))
	return ""


## Fase 9B: ¿se puede trazar una vía pública (carretera, línea) por este punto sin ser dueño? Sí en tierra
## del Estado explorada fuera del chunk del pueblo; no por tierra de particulares ni en la niebla.
static func public_way_ok(gs, x: float, z: float) -> bool:
	if absf(x) <= gs.MAP_SIZE * 0.5 and absf(z) <= gs.MAP_SIZE * 0.5:
		return false
	if not in_country(gs, x, z):
		return false
	var c := chunk_of(x, z)
	if not is_revealed(gs, c.x, c.y):
		return false
	return str(LandSim.owner_info(gs, c.x, c.y).get("owner", "")) in ["estado", "jugador"]


## Se llama al comprar una parcela: su chunk queda revelado y es del jugador.
static func on_zone_bought(gs, zx: int, zy: int) -> void:
	var c := chunk_of_zone(zx, zy)
	reveal(gs, c.x, c.y)


# --- Expediciones -------------------------------------------------------------------------------

static func exp_cfg() -> Dictionary:
	return cfg().get("expedition", {})


static func _chunk_dist(cx: int, cy: int) -> int:
	return maxi(absi(cx), absi(cy))


static func expedition_cost(gs, cx: int, cy: int) -> float:
	var e := exp_cfg()
	var d := _chunk_dist(cx, cy)
	var n := int(gs.map.get("expeditions_done", 0))
	return snappedf(float(e.get("base_cost", 1200.0)) * (1.0 + float(e.get("cost_growth_per_chunk", 0.22)) * d) * (1.0 + 0.04 * n) * gs.price_mult(), 1.0)


static func expedition_days(_gs, cx: int, cy: int) -> int:
	var e := exp_cfg()
	return int(e.get("base_days", 6)) + int(e.get("days_per_chunk", 2)) * _chunk_dist(cx, cy)


## "" si se puede enviar una expedición a ese chunk.
static func expedition_block_reason(gs, cx: int, cy: int) -> String:
	if not in_country_chunk(gs, cx, cy):
		return "Fuera del país"
	if is_revealed(gs, cx, cy):
		return "Ya está explorado"
	for ex in gs.map.get("expeditions", []):
		if int(ex["cx"]) == cx and int(ex["cy"]) == cy:
			return "Ya hay una expedición en camino"
	if gs.map.get("expeditions", []).size() >= int(exp_cfg().get("max_active", 2)):
		return "Máximo %d expediciones a la vez" % int(exp_cfg().get("max_active", 2))
	var near := false
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if is_revealed(gs, cx + dx, cy + dy):
				near = true
	if not near:
		return "Debe estar junto a territorio explorado"
	var cost := expedition_cost(gs, cx, cy)
	if gs.money < cost:
		return "Dinero insuficiente (%s)" % Fmt.money(cost)
	return ""


static func start_expedition(gs, cx: int, cy: int) -> String:
	var reason := expedition_block_reason(gs, cx, cy)
	if reason != "":
		return reason
	var cost := expedition_cost(gs, cx, cy)
	gs.add_money(-cost)
	var days := expedition_days(gs, cx, cy)
	gs.map["expeditions"].append({"cx": cx, "cy": cy, "days_left": days, "cost": cost})
	gs.notify("Expedición enviada a explorar el territorio (%d, %d): %s, %d días." % [cx, cy, Fmt.money(cost), days], "jugador")
	EventBus.map_changed.emit()
	return ""


## Fase 9B: ubica los pueblos de comercio (TradeSim / TownEconomySim) en municipios reales con pueblo.
## El i-ésimo pueblo (ordenados por distancia) va a un municipio repartido entre la mitad más cercana del
## país. Su distancia (km) se ajusta con la real, con límites (×0,85–×1,15) para no romper el balance.
static func assign_towns(gs) -> void:
	var towns: Array = gs.trade.get("towns", [])
	if not (gs.map.get("town_assign") is Dictionary):
		gs.map["town_assign"] = {}
	var asg: Dictionary = gs.map["town_assign"]
	if towns.is_empty():
		return
	var all_done := true
	for t in towns:
		if not asg.has(str(t.get("id", ""))) or not t.has("distance_base"):
			all_done = false
	if all_done:
		return
	var used := {}
	for k in asg:
		used[int(asg[k])] = true
	var spots := []
	for z in municipalities(gs):
		if bool(z["town"]) and not bool(z["player"]) and not used.has(int(z["id"])):
			spots.append(z)
	spots.sort_custom(func(a, b) -> bool: return (a["town_pos"] as Vector2).length() < (b["town_pos"] as Vector2).length())
	var pending := []
	for t in towns:
		if not asg.has(str(t.get("id", ""))):
			pending.append(t)
	var n := pending.size()
	var span := maxi(n, int(spots.size() * 0.5))
	var taken := {}
	for i in range(n):
		var idx := mini(int(float(i) * span / maxi(1, n)), spots.size() - 1)
		while idx < spots.size() and taken.has(idx):
			idx += 1
		if idx < 0 or idx >= spots.size():
			break
		taken[idx] = true
		var z: Dictionary = spots[idx]
		var t: Dictionary = pending[i]
		asg[str(t["id"])] = int(z["id"])
	# Nombres, población y distancia real.
	var reals := []
	for t in towns:
		var zid := int(asg.get(str(t.get("id", "")), -1))
		if zid >= 0:
			reals.append((municipalities(gs)[zid]["town_pos"] as Vector2).length() / 1000.0)
	reals.sort()
	var ref: float = float(reals[reals.size() / 2]) if not reals.is_empty() else 1.0
	for t in towns:
		var zid := int(asg.get(str(t.get("id", "")), -1))
		if zid < 0:
			continue
		var reg := MunicipalSim.region(gs, zid)
		if not reg.is_empty() and str(reg.get("trade_town_id", "")) != str(t["id"]):
			var nm := str(t.get("name", reg.get("name", "")))
			if gen(gs).real and str(reg.get("name", "")) != "":
				nm = str(reg["name"])          # país real: el pueblo de comercio toma el nombre real del municipio
				t["name"] = nm
			for k in gs.map.get("regions", {}):
				var other: Dictionary = gs.map["regions"][k]
				if int(other["id"]) != zid and str(other.get("name", "")) == nm:
					other["name"] = "%s del %s" % [nm, "Norte" if int(other["id"]) % 2 == 0 else "Sur"]
			reg["name"] = nm
			reg["trade_town_id"] = str(t["id"])
			reg["population"] = int(t.get("population", reg.get("population", 500)))
		if not t.has("distance_base"):
			var real := (municipalities(gs)[zid]["town_pos"] as Vector2).length() / 1000.0
			t["distance_base"] = float(t.get("distance", 50.0))
			# Solo en países reales (los de respaldo conservan las distancias de la Fase 7 para las pruebas).
			var f := clampf(real / maxf(0.1, ref), 0.85, 1.15) if gen(gs).real else 1.0
			t["distance"] = roundf(float(t["distance_base"]) * f)
			t["real_km"] = snappedf(real, 0.1)


## Municipio de un pueblo de comercio (-1 si no tiene).
static func town_zone(gs, town_id: String) -> int:
	if not gs.map.get("town_assign", {}).has(town_id):
		assign_towns(gs)
	return int(gs.map.get("town_assign", {}).get(town_id, -1))


## Posición real en el país de un pueblo de comercio exterior (Fase 7 → 9B). Vector2.INF si no tiene.
static func trade_town_pos(gs, town_id: String) -> Vector2:
	var zid := town_zone(gs, town_id)
	if zid < 0 or zid >= municipalities(gs).size():
		return Vector2.INF
	return municipalities(gs)[zid]["town_pos"]


## Rutas comerciales abiertas: revelan el municipio del pueblo destino y el corredor del camino (una vez).
static func _reveal_trade_routes(gs) -> void:
	var done: Dictionary = gs.map.get("routes_revealed", {})
	var n := 0
	for c in gs.trade.get("connections", []):
		var tid := str(c.get("town_id", ""))
		if tid == "" or done.has(tid):
			continue
		done[tid] = true
		var p := trade_town_pos(gs, tid)
		if p == Vector2.INF:
			continue
		var steps := maxi(1, int(p.length() / 300.0))
		for i in range(steps + 1):
			var q := p * (float(i) / steps)
			n += reveal_around_quiet(gs, q, 150.0)
		n += reveal_around_quiet(gs, p, 500.0)
		var zid := town_zone(gs, tid)
		if zid >= 0:
			n += reveal_zone_quiet(gs, zid)
			gs.notify("La ruta comercial reveló el municipio de %s." % MunicipalSim.name_of(gs, zid), "info")
	gs.map["routes_revealed"] = done
	if n > 0:
		EventBus.map_changed.emit()


static func reveal_around_quiet(gs, p: Vector2, radius: float) -> int:
	var a := chunk_of(p.x - radius, p.y - radius)
	var b := chunk_of(p.x + radius, p.y + radius)
	var n := 0
	for cy in range(a.y, b.y + 1):
		for cx in range(a.x, b.x + 1):
			var r := chunk_rect(cx, cy)
			var q := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
			if q.distance_to(p) <= radius and _reveal(gs, cx, cy):
				n += 1
	return n


static func daily(gs) -> void:
	if gs.trade.get("connections", []).size() != gs.map.get("routes_revealed", {}).size():
		_reveal_trade_routes(gs)
	LandSim.daily(gs)   # Fase 9B: respuestas a ofertas y licitaciones de tierra.
	var exps: Array = gs.map.get("expeditions", [])
	if exps.is_empty():
		return
	var keep := []
	var done := false
	for ex in exps:
		ex["days_left"] = int(ex["days_left"]) - 1
		if int(ex["days_left"]) > 0:
			keep.append(ex)
			continue
		var r := int(exp_cfg().get("reveal_radius", 1))
		var n := 0
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if _reveal(gs, int(ex["cx"]) + dx, int(ex["cy"]) + dy):
					n += 1
		gs.map["expeditions_done"] = int(gs.map.get("expeditions_done", 0)) + 1
		var c := Vector2(int(ex["cx"]), int(ex["cy"])) * CHUNK
		gs.notify("La expedición volvió: exploró %.2f km² nuevos (%s)." % [n * 0.16, biome_label(biome_at(c.x, c.y, gs))], "importante")
		done = true
	gs.map["expeditions"] = keep
	if done:
		EventBus.map_changed.emit()


## Fase 9B: mercado de tierras (precios, comercio NPC) y municipios (alcaldes, misiones regionales).
static func monthly(gs) -> void:
	LandSim.monthly(gs)
	MunicipalSim.monthly(gs)


# --- País y recursos ------------------------------------------------------------------------------

## Aplica la abundancia de recursos del país a una región candidata (yacimientos y fortalezas).
static func apply_country_resources(region: Dictionary, cid: String) -> void:
	var res: Dictionary = country_def(cid).get("resources", {})
	if res.is_empty():
		return
	var deps: Dictionary = region.get("deposits", {})
	for t in deps.keys():
		var mult := float(res.get(t, 1.0))
		var n := int(deps[t])
		if mult >= 1.4 and n >= 1:
			deps[t] = n + 1
		elif mult <= 0.65 and n >= 2:
			deps[t] = n - 1
	var st: Dictionary = region.get("strengths", {})
	for r in st.keys():
		st[r] = snappedf(float(st[r]) * sqrt(float(res.get(r, 1.0))), 0.01)
	region["country_id"] = cid


## Moneda e inflación base del país (para la Fase 10; hoy solo informativo).
static func currency(gs = null) -> Dictionary:
	var cd := country_def(country_id(gs if gs != null else GameState))
	return {"name": str(cd.get("currency", {}).get("name", "Peso")), "symbol": str(cd.get("currency", {}).get("symbol", "$")),
			"base_inflation": float(cd.get("base_inflation", 0.03)), "exchange_rate_to_ref": float(cd.get("exchange_rate_to_ref", 1.0))}


# --- Relieve, clima y costo de obras --------------------------------------------------------------

## Generador para un tipo de mapa, semilla y país concretos (mismo caché que gen()).
static func gen_for(map_type: String, seed_value: int, cid: String) -> CountryGen:
	var k := "%s|%d|%s" % [map_type, seed_value, cid]
	if _gen == null or k != _gen_key:
		_use_gen(k, map_type, seed_value, cid)
	return _gen


## Pendiente del terreno (m de subida por m horizontal) en un punto.
static func slope_at(x: float, z: float, gs = null) -> float:
	var g := gen(gs)
	var d := 2.5
	var dx := (g.height(x + d, z) - g.height(x - d, z)) / (2.0 * d)
	var dz := (g.height(x, z + d) - g.height(x, z - d)) / (2.0 * d)
	return Vector2(dx, dz).length()


## Clima local (para WeatherSim u otros): temperatura y humedad relativas (-1..1), altura, bioma y
## una diferencia aproximada en °C respecto a la plaza del pueblo.
static func climate_at(x: float, z: float, gs = null) -> Dictionary:
	var g := gen(gs)
	var h := g.height(x, z)
	var c := g.climate(x, z, h)
	var cz := g.climate(0.0, 0.0, g.height(0.0, 0.0))
	return {"temperature": c.x, "humidity": c.y, "altitude": h, "biome": CountryGen.BIOMES[g.biome_id(x, z, h)],
			"temp_offset_c": snappedf((c.x - cz.x) * 16.0, 0.1)}


## Multiplicador del costo de una vía (carretera, riel, tubería, cable) entre a y b según el terreno:
## pendiente (excavar), subidas grandes (túnel), agua (puente), cañones y altura. 1.0 en terreno llano.
## Enganchado en RoadSim.segment_cost; TransitSim o GridSim pueden usarlo igual.
## Multiplicador medio (ponderado por largo) de una polilínea; include_water = false cuando quien
## llama ya cobra los puentes aparte (TransitSim).
static func terrain_cost_mult_path(points: PackedVector2Array, gs = null, include_water := true) -> float:
	var total := 0.0
	var acc := 0.0
	var i := 0
	while i < points.size() - 1:
		var j := mini(i + 5, points.size() - 1)   # tramos de ~20 m (TransitSim muestrea cada 4 m)
		var l := points[i].distance_to(points[j])
		acc += terrain_cost_mult(points[i], points[j], gs, include_water) * l
		total += l
		i = j
	return snappedf(acc / total, 0.01) if total > 0.0 else 1.0


static func terrain_cost_mult(a: Vector2, b: Vector2, gs = null, include_water := true) -> float:
	var g := gen(gs)
	var tc: Dictionary = cfg().get("terrain_cost", {})
	var length := a.distance_to(b)
	if length < 0.5:
		return 1.0
	var n := clampi(int(length / 5.0), 2, 400)
	var step := length / n
	var slope_sum := 0.0
	var wet := 0
	var h_first := g.height(a.x, a.y)
	var h_last := g.height(b.x, b.y)
	var hmin := h_first
	var hmax := h_first
	var prev := h_first
	for i in range(1, n + 1):
		var p := a.lerp(b, float(i) / n)
		var h := h_last if i == n else g.height(p.x, p.y)
		slope_sum += absf(h - prev) / step
		if h < g.water_level - 0.2:
			wet += 1
		hmin = minf(hmin, h)
		hmax = maxf(hmax, h)
		prev = h
	var mult := 1.0
	var slope := slope_sum / n
	mult += minf(maxf(0.0, slope - float(tc.get("slope_free", 0.08))) * float(tc.get("slope_mult", 7.0)), float(tc.get("max_slope_extra", 4.0)))
	if include_water:
		mult += float(wet) / n * float(tc.get("bridge_mult", 3.0))
	# Túnel: una cresta alta entre los dos extremos.
	if hmax - maxf(h_first, h_last) > float(tc.get("tunnel_rise", 22.0)):
		mult += float(tc.get("tunnel_mult", 2.5))
	# Cañón: una hondonada profunda por debajo de ambos extremos (puente alto).
	if minf(h_first, h_last) - hmin > float(tc.get("canyon_depth", 18.0)):
		mult += float(tc.get("canyon_mult", 1.5))
	var alt0 := float(tc.get("altitude_start", 60.0))
	if hmax > alt0:
		mult += (hmax - alt0) / 100.0 * float(tc.get("altitude_mult_per_100m", 0.35))
	return snappedf(mult, 0.01)
