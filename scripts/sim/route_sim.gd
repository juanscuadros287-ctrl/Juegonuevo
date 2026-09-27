class_name RouteSim
extends RefCounted
## Sistema unificado de rutas punto X → punto Y (docs/RUTAS_BARCOS.md).
##
## Es un ADAPTADOR sobre los sistemas que ya existían, sin romperlos:
##   L<id>  rutas de carga de la Fase 6 (LogisticsSim: a pie, mulas, carretas, camiones, trenes, barcos
##          y aviones dentro del país)
##   A<id>  rutas automáticas entre países (AirSim: avión, vuelo comercial, barco propio, naviera)
##   B<id>  rutas de bus (TransitSim)
##   T<id>  caminos y vías a otros pueblos (TradeSim)
## Cada ruta tiene NOMBRE y COLOR únicos (paleta automática, editable), se dibuja en el mapa siguiendo su
## camino real (carretera, riel, agua o línea aérea) con flechas de sentido y tiene su carga del mes.
##
## Validación "con sentido" por medio (`validate`, `geo_block_reason`):
##   a pie      distancia máxima prudente (walk_max, 250 m)
##   mula       terreno transitable (sin cruzar agua ancha) y distancia moderada, o carretera
##   carretas y vehículos  carretera del tipo requerido que una ambos puntos (RoadSim.connected con kinds)
##   tren       ambos puntos junto a estaciones de tren unidas por rieles (RailSim)
##   barco      ambos puntos en un puerto (o almacén al lado) unidos por agua navegable (ShipSim)
##   avión      aeropuertos
##
## Estado en GameState.logistics["rutas"] (por país; se guarda solo): {layer, trade: {tid: {color, name}},
## version}. Colores y nombres de las demás rutas viven en su propio diccionario ("color", "name").

const FAMILY_LABELS := {"pie": "A pie", "animal": "Mulas", "carretera": "Carretera", "riel": "Tren", "agua": "Barco", "aire": "Avión"}

static var _path_cache := {}


static func cfg() -> Dictionary:
	return GameData.extra("rutas")


static func state(gs) -> Dictionary:
	if not (gs.logistics.get("rutas") is Dictionary):
		gs.logistics["rutas"] = {}
	var s: Dictionary = gs.logistics["rutas"]
	if not s.has("layer"):
		s["layer"] = true
	if not (s.get("trade") is Dictionary):
		s["trade"] = {}
	s["version"] = int(s.get("version", 1))
	return s


## Se llama desde LogisticsSim.init_state (partida nueva, carga o país nuevo).
## Partidas anteriores (sin "rutas"): garajes con conexión provisional y colores para las rutas viejas.
static func init_state(gs) -> void:
	var old: bool = not gs.logistics.has("rutas")
	state(gs)
	if old and not gs.buildings.is_empty():
		var n := GarageSim.grandfather(gs)
		if n > 0:
			gs.notify("Rutas y garajes: %d garaje(s) de tu partida no quedan conectados a su red; siguen funcionando con conexión provisional. Conéctalos (carretera, vía, agua o pista) para no depender de ella." % n, "negocio")
	ensure_colors(gs)


static func layer_visible(gs) -> bool:
	return bool(state(gs).get("layer", true))


static func set_layer_visible(gs, v: bool) -> void:
	state(gs)["layer"] = v


# --- Colores y nombres ---------------------------------------------------------------------------

static func palette() -> Array:
	return cfg().get("palette", ["#e6194b", "#3cb44b", "#4363d8", "#f58231"])


static func _norm(hex: String) -> String:
	return Color.html(hex).to_html(false).to_lower() if Color.html_is_valid(hex) else ""


## Todos los diccionarios de ruta con color: [[clave, dict]]. Las de comercio usan state.trade.
static func _route_dicts(gs) -> Array:
	var out := []
	for r in LogisticsSim.routes(gs):
		out.append(["L%d" % int(r["id"]), r])
	if CountriesSim.ready(gs) or gs.countries.has("air"):
		for r in AirSim.st(gs).get("routes", []):
			out.append(["A%d" % int(r["id"]), r])
	if not gs.transit.is_empty():
		for r in TransitSim.routes(gs):
			out.append(["B%d" % int(r["id"]), r])
	var tr: Dictionary = state(gs)["trade"]
	for c in TradeSim.connected_towns(gs):
		var tid := str(c["town_id"])
		if not tr.has(tid):
			tr[tid] = {}
		out.append(["T%s" % tid, tr[tid]])
	return out


static func used_colors(gs, except_key := "") -> Array:
	var used := []
	for pair in _route_dicts(gs):
		if str(pair[0]) != except_key and str((pair[1] as Dictionary).get("color", "")) != "":
			used.append(_norm(str(pair[1]["color"])))
	return used


## Siguiente color libre: primero la paleta; después tonos repartidos con la razón áurea.
static func next_color(gs, used: Array = []) -> String:
	if used.is_empty():
		used = used_colors(gs)
	for h in palette():
		var n := _norm(str(h))
		if not used.has(n):
			return n
	var i := used.size()
	while true:
		var c := Color.from_hsv(fmod(0.11 + i * 0.618034, 1.0), 0.75 - 0.2 * float(i % 3) / 2.0, 0.95 - 0.15 * float(i % 2))
		var n := c.to_html(false).to_lower()
		if not used.has(n):
			return n
		i += 1
	return "ffffff"


## Da color y nombre a las rutas que no los tienen y corrige colores repetidos (migración incluida).
static func ensure_colors(gs) -> void:
	var used := []
	for pair in _route_dicts(gs):
		var key := str(pair[0])
		var r: Dictionary = pair[1]
		var c := _norm(str(r.get("color", "")))
		if c == "" or used.has(c):
			c = next_color(gs, used)
			r["color"] = c
		used.append(c)
		if str(r.get("name", "")) == "":
			r["name"] = default_name(gs, key, r)


static func default_name(gs, key: String, r: Dictionary) -> String:
	match key.substr(0, 1):
		"L":
			return "%s: %s → %s" % [FAMILY_LABELS.get(family(str(r.get("mode", "pie"))), "Ruta"), _short(LogisticsSim.endpoint_label(gs, int(r.get("from", 0)))),
					_short(LogisticsSim.endpoint_label(gs, int(r.get("to", 0))))]
		"A":
			return "%s: %s → %s" % [_intl_mode_label(str(r.get("mode", ""))), CountriesSim.country_label(str(r.get("from_iso", ""))), CountriesSim.country_label(str(r.get("to_iso", "")))]
		"B":
			return str(r.get("name", "Bus %d" % int(r.get("id", 0))))
		"T":
			return "Camino a %s" % str(TradeSim.town(gs, key.substr(1)).get("name", key.substr(1)))
	return "Ruta"


static func _short(label: String) -> String:
	return label.get_slice(" (", 0)


static func _intl_mode_label(mode: String) -> String:
	return {"avion": "Avión", "comercial": "Vuelo comercial", "barco": "Barco", "naviera": "Naviera"}.get(mode, mode)


static func _find(gs, key: String) -> Dictionary:
	for pair in _route_dicts(gs):
		if str(pair[0]) == key:
			return pair[1]
	return {}


## Cambia el color de una ruta. Devuelve "" o el motivo (el color debe ser único).
static func set_color(gs, key: String, hex: String) -> String:
	var r := _find(gs, key)
	if r.is_empty():
		return "Esa ruta no existe"
	var n := _norm(hex)
	if n == "":
		return "Color inválido"
	for pair in _route_dicts(gs):
		if str(pair[0]) != key and _norm(str(pair[1].get("color", ""))) == n:
			return "Ese color ya lo usa «%s»: elige otro" % str(pair[1].get("name", pair[0]))
	r["color"] = n
	_bump(gs)
	return ""


static func set_route_name(gs, key: String, name: String) -> String:
	var r := _find(gs, key)
	if r.is_empty():
		return "Esa ruta no existe"
	if name.strip_edges() == "":
		return "El nombre no puede quedar vacío"
	r["name"] = name.strip_edges().left(48)
	_bump(gs)
	return ""


static func color_of(gs, key: String) -> Color:
	var r := _find(gs, key)
	var n := _norm(str(r.get("color", "")))
	return Color.html(n) if n != "" else Color.WHITE


static func _bump(gs) -> void:
	var s := state(gs)
	s["version"] = int(s.get("version", 1)) + 1


static func version(gs) -> int:
	return int(state(gs).get("version", 1))


## Asigna nombre y color a una ruta recién creada (opts: color, name).
static func decorate(gs, key: String, r: Dictionary, opts: Dictionary = {}) -> void:
	var used := used_colors(gs, key)
	var want := _norm(str(opts.get("color", "")))
	r["color"] = want if want != "" and not used.has(want) else next_color(gs, used)
	r["name"] = str(opts.get("name", "")).strip_edges().left(48) if str(opts.get("name", "")).strip_edges() != "" else default_name(gs, key, r)
	_bump(gs)


# --- Carga del mes (contador con mes sellado: no necesita cierre mensual) --------------------------

static func _month_id() -> int:
	return TimeManager.year() * 12 + TimeManager.month()


static func note_moved(r: Dictionary, qty: float) -> void:
	_roll(r)
	r["mq_cur"] = float(r.get("mq_cur", 0.0)) + qty


static func _roll(r: Dictionary) -> void:
	var m := _month_id()
	var was := int(r.get("mq_m", m))
	if was != m:
		r["mq_last"] = float(r.get("mq_cur", 0.0)) if was == m - 1 else 0.0
		r["mq_cur"] = 0.0
	r["mq_m"] = m


static func month_qty(r: Dictionary) -> float:
	_roll(r)
	return float(r.get("mq_cur", 0.0))


static func last_month_qty(r: Dictionary) -> float:
	_roll(r)
	return float(r.get("mq_last", 0.0))


# --- Familias y validación por medio ----------------------------------------------------------------

## "pie" | "animal" | "carretera" | "riel" | "agua" | "aire".
static func family(mode: String) -> String:
	var md := LogisticsSim.mode_def(mode)
	if bool(md.get("rail", false)):
		return "riel"
	if bool(md.get("water", false)) or mode in ["barco", "naviera"]:
		return "agua"
	if mode in ["avion", "comercial"]:
		return "aire"
	if bool(md.get("road", false)):
		return "carretera"
	if mode == "pie":
		return "pie"
	return "animal"


static func is_train_station(b: Dictionary) -> bool:
	return str(b.get("type", "")) == "estacion_tren"


## Estación de tren que sirve a un punto de ruta (la propia estación o una al lado). -1 si ninguna.
static func station_for(gs, id: int) -> int:
	var p := LogisticsSim.endpoint_pos(gs, id)
	var h: float = WarehouseSim.half_of(gs, id) if WarehouseSim.exists(gs, id) else (gs.footprint_of(gs.get_building(id)) * 0.5 if id != LogisticsSim.PLAZA else 9.0)
	var own: Dictionary = gs.get_building(id) if id != LogisticsSim.PLAZA else {}
	if is_train_station(own) and gs.owned_by_player(own) and gs.is_active(own):
		return id
	var best := -1
	var bd := INF
	for b in gs.buildings:
		if not is_train_station(b) or not gs.owned_by_player(b) or not gs.is_active(b):
			continue
		var gap := WarehouseSim.edge_gap(p, h, Vector2(float(b["x"]), float(b["z"])), gs.footprint_of(b) * 0.5)
		if gap <= float(cfg().get("station_reach", 14.0)) and gap < bd:
			bd = gap
			best = int(b["id"])
	return best


static func station_components(gs, sid: int) -> Array:
	var b: Dictionary = gs.get_building(sid)
	if b.is_empty():
		return []
	return RailSim.near_components(gs, Vector2(float(b["x"]), float(b["z"])), gs.footprint_of(b) * 0.5 + float(cfg().get("rail_reach", 10.0)))


static func _dist(gs, a: int, b: int) -> float:
	return LogisticsSim.endpoint_pos(gs, a).distance_to(LogisticsSim.endpoint_pos(gs, b))


## Carretera del tipo que exige el medio entre dos puntos ("" si hay).
static func road_reason(gs, from_id: int, to_id: int, mode: String) -> String:
	var md := LogisticsSim.mode_def(mode)
	if bool(md.get("road", false)) and not RoadSim.connected(gs, LogisticsSim.endpoint_pos(gs, from_id), LogisticsSim.endpoint_pos(gs, to_id), LogisticsSim.road_kinds(mode)):
		var kinds := LogisticsSim.road_kinds(mode)
		if kinds.is_empty():
			return "%s necesitan carretera que una origen y destino" % LogisticsSim.mode_label(mode)
		return "%s necesitan carretera de %s que una origen y destino" % [LogisticsSim.mode_label(mode), " o ".join(kinds.map(func(k): return RoadSim.kind_label(k).to_lower()))]
	return ""


## Motivo geográfico de un tramo ("" si tiene sentido).
static func leg_reason(gs, from_id: int, to_id: int, mode: String) -> String:
	var d := _dist(gs, from_id, to_id)
	match family(mode):
		"pie":
			var mx := float(cfg().get("walk_max", 250.0))
			if d > mx:
				return "A pie solo se lleva carga a una distancia prudente (máx. %d m; este tramo mide %d m): usa mulas, carretas, camiones o tren" % [int(mx), int(d)]
		"animal":
			var a := LogisticsSim.endpoint_pos(gs, from_id)
			var b := LogisticsSim.endpoint_pos(gs, to_id)
			if RoadSim.connected(gs, a, b, []):
				return ""
			var mx := float(cfg().get("mule_max", 1500.0))
			if d > mx:
				return "Demasiado lejos para mulas por el monte (máx. %d m sin carretera; este tramo mide %d m): traza una carretera" % [int(mx), int(d)]
			var wp := TransitSim.water_profile(gs, PackedVector2Array([a, b]))
			if float(wp["longest"]) > float(cfg().get("mule_bridge_max", 36.0)):
				return "Las mulas no cruzan tanta agua (%d m): traza una carretera con puente" % int(float(wp["longest"]))
		"carretera":
			return road_reason(gs, from_id, to_id, mode)
		"riel":
			var sa := station_for(gs, from_id)
			var sb := station_for(gs, to_id)
			if sa < 0:
				return "El tren carga junto a una estación: el origen debe ser una estación de tren tuya o un almacén al lado de una"
			if sb < 0:
				return "El tren descarga junto a una estación: el destino debe ser una estación de tren tuya o un almacén al lado de una"
			var ca := station_components(gs, sa)
			var cb := station_components(gs, sb)
			if ca.is_empty():
				return "%s no está junto a una vía férrea (traza una vía por puntos)" % gs.building_label(gs.get_building(sa))
			if cb.is_empty():
				return "%s no está junto a una vía férrea (traza una vía por puntos)" % gs.building_label(gs.get_building(sb))
			for c in ca:
				if cb.has(c):
					return ""
			return "Las estaciones no están unidas por rieles: traza una vía férrea entre ellas"
		"agua":
			var pa := ShipSim.port_of(gs, from_id)
			var pb := ShipSim.port_of(gs, to_id)
			if pa < 0:
				return "El barco carga en un puerto: el origen debe ser un puerto tuyo o un almacén al lado de un puerto"
			if pb < 0:
				return "El barco descarga en un puerto: el destino debe ser un puerto tuyo o un almacén al lado de un puerto"
			if not ShipSim.ports_connected(gs, pa, pb):
				return "Los puertos no están unidos por agua navegable"
			if mode == "balsa" or LogisticsSim.mode_def(mode).is_empty():
				return ""
			return ""
		"aire":
			return AirSim.domestic_block_reason(gs, from_id, to_id)
	return ""


## Motivo geográfico de toda la ruta (con paradas intermedias).
static func geo_block_reason(gs, from_id: int, to_id: int, mode: String, stops: Array = []) -> String:
	var pts := [from_id]
	for s in stops:
		pts.append(int(s))
	pts.append(to_id)
	for i in range(pts.size() - 1):
		if int(pts[i]) == int(pts[i + 1]):
			return "Dos puntos seguidos de la ruta son el mismo lugar"
		if not LogisticsSim.endpoint_valid(gs, int(pts[i + 1])):
			return "Una parada ya no existe"
		var r := leg_reason(gs, int(pts[i]), int(pts[i + 1]), mode)
		if r != "":
			if stops.is_empty():
				return r
			return "Tramo %s → %s: %s" % [_short(LogisticsSim.endpoint_label(gs, int(pts[i]))), _short(LogisticsSim.endpoint_label(gs, int(pts[i + 1]))), r]
	return ""


## Validación del asistente (sin mirar vehículos): puntos válidos, tecnología y geografía.
static func validate(gs, mode: String, from_id: int, to_id: int, stops: Array = []) -> String:
	if from_id == to_id:
		return "Origen y destino son el mismo lugar"
	if not LogisticsSim.endpoint_valid(gs, from_id) or not LogisticsSim.endpoint_valid(gs, to_id):
		return "Origen o destino ya no existe"
	var md := LogisticsSim.mode_def(mode)
	if md.is_empty():
		return "Medio de transporte desconocido"
	if not gs.has_tech(str(md.get("tech", ""))):
		return "Requiere investigar: %s" % GameData.tech_label(str(md.get("tech", "")))
	return geo_block_reason(gs, from_id, to_id, mode, stops)


# --- Distancias y caminos reales --------------------------------------------------------------------

static func leg_distance(gs, from_id: int, to_id: int, mode: String) -> float:
	match family(mode):
		"riel", "agua":
			return maxf(_dist(gs, from_id, to_id), TransitSim.poly_length(leg_path(gs, from_id, to_id, mode)))
	return _dist(gs, from_id, to_id) * float(LogisticsSim.tcfg().get("route_factor", 1.25))


static func route_distance(gs, from_id: int, to_id: int, mode: String, stops: Array = []) -> float:
	var pts := [from_id]
	for s in stops:
		pts.append(int(s))
	pts.append(to_id)
	var total := 0.0
	for i in range(pts.size() - 1):
		total += leg_distance(gs, int(pts[i]), int(pts[i + 1]), mode)
	return total


static func _net_key(gs) -> String:
	return "%d|%d|%d|%d" % [int(gs.logistics.get("road_version", 0)), RoadSim.roads(gs).size(), RailSim.version(gs), gs.buildings.size()]


## Camino real de un tramo (carretera, riel, agua, línea aérea o recto).
static func leg_path(gs, from_id: int, to_id: int, mode: String) -> PackedVector2Array:
	var key := "%s|%d|%d|%s|%s" % [family(mode), from_id, to_id, ",".join(LogisticsSim.road_kinds(mode)), _net_key(gs)]
	if _path_cache.has(key):
		return _path_cache[key]
	var a := LogisticsSim.endpoint_pos(gs, from_id)
	var b := LogisticsSim.endpoint_pos(gs, to_id)
	var out := PackedVector2Array([a, b])
	match family(mode):
		"carretera", "animal":
			if RoadSim.connected(gs, a, b, LogisticsSim.road_kinds(mode)):
				out = road_path(gs, a, b, LogisticsSim.road_kinds(mode))
		"riel":
			var sa: Dictionary = gs.get_building(station_for(gs, from_id))
			var sb: Dictionary = gs.get_building(station_for(gs, to_id))
			if not sa.is_empty() and not sb.is_empty():
				var pa := RailSim.nearest_point(gs, Vector2(float(sa["x"]), float(sa["z"])))
				var pb := RailSim.nearest_point(gs, Vector2(float(sb["x"]), float(sb["z"])))
				if pa != Vector2.INF and pb != Vector2.INF:
					out = PackedVector2Array([a])
					out.append_array(RailSim.path(gs, pa, pb))
					out.append(b)
		"agua":
			var pa2: Dictionary = gs.get_building(ShipSim.port_of(gs, from_id))
			var pb2: Dictionary = gs.get_building(ShipSim.port_of(gs, to_id))
			if not pa2.is_empty() and not pb2.is_empty():
				out = PackedVector2Array([a])
				out.append_array(ShipSim.water_path(gs, pa2, pb2))
				out.append(b)
	if _path_cache.size() > 200:
		_path_cache.clear()
	_path_cache[key] = out
	return out


## Camino completo de una ruta con paradas (para dibujarla y animarla).
static func path_for(gs, from_id: int, to_id: int, mode: String, stops: Array = []) -> PackedVector2Array:
	var pts := [from_id]
	for s in stops:
		pts.append(int(s))
	pts.append(to_id)
	var out := PackedVector2Array()
	for i in range(pts.size() - 1):
		var leg := leg_path(gs, int(pts[i]), int(pts[i + 1]), mode)
		for j in range(leg.size()):
			if out.is_empty() or out[out.size() - 1].distance_to(leg[j]) > 0.05:
				out.append(leg[j])
	return out


## Camino por la red de carreteras (de esos tipos) entre dos puntos.
static func road_path(gs, a: Vector2, b: Vector2, kinds: Array = []) -> PackedVector2Array:
	var segs := []
	for r in RoadSim.roads(gs):
		if RoadSim._kind_ok(r, kinds):
			segs.append([RoadSim.seg_a(r), RoadSim.seg_b(r)])
	var p := graph_path(segs, a, b)
	return p


## Camino más corto sobre un grafo de segmentos [[Vector2, Vector2]] entre dos puntos (Dijkstra).
static func graph_path(segs: Array, a: Vector2, b: Vector2) -> PackedVector2Array:
	if segs.is_empty():
		return PackedVector2Array([a, b])
	var nodes := {}
	var adj := {}
	var kf := func(p: Vector2) -> String: return "%d_%d" % [int(round(p.x * 2.0)), int(round(p.y * 2.0))]
	var add_edge := func(k1: String, k2: String, d: float) -> void:
		if not adj.has(k1):
			adj[k1] = []
		if not adj.has(k2):
			adj[k2] = []
		adj[k1].append([k2, d])
		adj[k2].append([k1, d])
	for s in segs:
		var pa: Vector2 = s[0]
		var pb: Vector2 = s[1]
		var ka: String = kf.call(pa)
		var kb: String = kf.call(pb)
		nodes[ka] = pa
		nodes[kb] = pb
		add_edge.call(ka, kb, pa.distance_to(pb))
	# Uniones en T: extremo sobre el interior de otro tramo.
	if segs.size() < 1500:
		for s in segs:
			var pa: Vector2 = s[0]
			var pb: Vector2 = s[1]
			var lo := Vector2(minf(pa.x, pb.x), minf(pa.y, pb.y)) - Vector2(1.5, 1.5)
			var hi := Vector2(maxf(pa.x, pb.x), maxf(pa.y, pb.y)) + Vector2(1.5, 1.5)
			for k in nodes:
				var q: Vector2 = nodes[k]
				if q.x < lo.x or q.y < lo.y or q.x > hi.x or q.y > hi.y:
					continue
				if q.distance_to(pa) > 0.6 and q.distance_to(pb) > 0.6 and RoadSim.dist_point_segment(q, pa, pb) < 1.5:
					add_edge.call(k, kf.call(pa), q.distance_to(pa))
					add_edge.call(k, kf.call(pb), q.distance_to(pb))
	var start := ""
	var goal := ""
	var bs := INF
	var bg := INF
	for k in nodes:
		var p: Vector2 = nodes[k]
		if p.distance_to(a) < bs:
			bs = p.distance_to(a)
			start = k
		if p.distance_to(b) < bg:
			bg = p.distance_to(b)
			goal = k
	# Dijkstra con montículo binario sencillo.
	var dist := {start: 0.0}
	var prev := {}
	var heap := [[0.0, start]]
	var done := {}
	while not heap.is_empty():
		var top: Array = _heap_pop(heap)
		var cur: String = top[1]
		if done.has(cur):
			continue
		done[cur] = true
		if cur == goal:
			break
		for e in adj.get(cur, []):
			var nk: String = e[0]
			var nd := float(dist[cur]) + float(e[1])
			if not dist.has(nk) or nd < float(dist[nk]):
				dist[nk] = nd
				prev[nk] = cur
				_heap_push(heap, [nd, nk])
	if not dist.has(goal):
		return PackedVector2Array([a, b])
	var out := PackedVector2Array([b])
	var k2 := goal
	while true:
		out.append(nodes[k2])
		if k2 == start or not prev.has(k2):
			break
		k2 = prev[k2]
	out.append(a)
	out.reverse()
	return out


static func _heap_push(h: Array, item: Array) -> void:
	h.append(item)
	var i := h.size() - 1
	while i > 0:
		var p := (i - 1) / 2
		if float(h[p][0]) <= float(h[i][0]):
			break
		var t = h[p]
		h[p] = h[i]
		h[i] = t
		i = p


static func _heap_pop(h: Array) -> Array:
	var top: Array = h[0]
	var last: Array = h.pop_back()
	if not h.is_empty():
		h[0] = last
		var i := 0
		while true:
			var l := 2 * i + 1
			var r := l + 1
			var m := i
			if l < h.size() and float(h[l][0]) < float(h[m][0]):
				m = l
			if r < h.size() and float(h[r][0]) < float(h[m][0]):
				m = r
			if m == i:
				break
			var t = h[m]
			h[m] = h[i]
			h[i] = t
			i = m
	return top


# --- Vista unificada ------------------------------------------------------------------------------

## Todas las rutas en el modelo común: [{key, kind, id, name, color, mode, mode_label, family, from_label,
## to_label, stops, vehicle_label, freq, status, month_qty, last_month_qty, active, local, intl}].
static func all_routes(gs) -> Array:
	ensure_colors(gs)
	var out := []
	for r in LogisticsSim.routes(gs):
		var mode := str(r.get("mode", "pie"))
		var vid := int(r.get("vehicle", -1))
		var stops_l := []
		for s in r.get("stops", []):
			stops_l.append(_short(LogisticsSim.endpoint_label(gs, int(s))))
		out.append({"key": "L%d" % int(r["id"]), "kind": "carga", "id": int(r["id"]), "name": str(r.get("name", "")), "color": Color.html(str(r["color"])),
				"mode": mode, "mode_label": LogisticsSim.mode_label(mode), "family": family(mode),
				"from": int(r["from"]), "to": int(r["to"]), "stops": r.get("stops", []),
				"from_label": _short(LogisticsSim.endpoint_label(gs, int(r["from"]))), "to_label": _short(LogisticsSim.endpoint_label(gs, int(r["to"]))), "stops_labels": stops_l,
				"vehicle_label": str(LogisticsSim.get_vehicle(gs, vid).get("name", "")) if vid >= 0 else "cualquiera libre",
				"good": str(r.get("good", "")), "freq": ("cada %d días" % int(r.get("every", 7))) if bool(r.get("auto", false)) else "manual (un envío)",
				"status": str(r.get("status", "")), "month_qty": month_qty(r), "last_month_qty": last_month_qty(r),
				"active": bool(r.get("active", true)), "local": true, "intl": false, "editable": true})
	for r in AirSim.st(gs).get("routes", []):
		var mode := str(r.get("mode", ""))
		out.append({"key": "A%d" % int(r["id"]), "kind": "internacional", "id": int(r["id"]), "name": str(r.get("name", "")), "color": Color.html(str(r["color"])),
				"mode": mode, "mode_label": _intl_mode_label(mode), "family": "agua" if mode in ["barco", "naviera"] else "aire",
				"from_label": "%s (%s)" % [CountriesSim.country_label(str(r["from_iso"])), _intl_endpoint(gs, str(r["from_iso"]), int(r["from"]))],
				"to_label": "%s (%s)" % [CountriesSim.country_label(str(r["to_iso"])), _intl_endpoint(gs, str(r["to_iso"]), int(r["to"]))], "stops_labels": [],
				"vehicle_label": "naviera" if mode == "naviera" else ("vuelo comercial" if mode == "comercial" else "propio"),
				"good": str(r.get("good", "")), "freq": "cada %d días" % int(r.get("every", 7)), "status": str(r.get("status", "")),
				"month_qty": month_qty(r), "last_month_qty": last_month_qty(r), "active": bool(r.get("active", true)),
				"local": false, "intl": true, "editable": true, "from_iso": str(r["from_iso"]), "to_iso": str(r["to_iso"]), "from": int(r["from"]), "to": int(r["to"])})
	if not gs.transit.is_empty():
		for r in TransitSim.routes(gs):
			var st := TransitSim.route_status(gs, r)
			out.append({"key": "B%d" % int(r["id"]), "kind": "bus", "id": int(r["id"]), "name": str(r.get("name", "")), "color": Color.html(str(r["color"])),
					"mode": "bus", "mode_label": "Bus", "family": "carretera",
					"from_label": _short(gs.building_label(gs.get_building(int(r["depot"])))), "to_label": "%d paraderos" % (r.get("stops", []) as Array).size(), "stops_labels": [],
					"vehicle_label": "%d buses" % int(st.get("operating", 0)), "good": "pasajeros", "freq": "diaria (5:30–21:00)",
					"status": str(st.get("reason", "")) if str(st.get("reason", "")) != "" else "en servicio", "month_qty": float(r.get("month_riders", 0.0)), "last_month_qty": float(r.get("last_riders", 0.0)),
					"active": true, "local": true, "intl": false, "editable": true})
	for c in TradeSim.connected_towns(gs):
		var tid := str(c["town_id"])
		var meta: Dictionary = state(gs)["trade"].get(tid, {})
		out.append({"key": "T%s" % tid, "kind": "comercio", "id": -1, "name": str(meta.get("name", "")), "color": Color.html(str(meta.get("color", "ffffff"))),
				"mode": TradeSim.active_mode(gs, tid), "mode_label": str(TradeSim.mode_def(TradeSim.active_mode(gs, tid)).get("label", "")), "family": "riel" if bool(c.get("rail", false)) else "carretera",
				"from_label": "Salida del pueblo", "to_label": str(TradeSim.town(gs, tid).get("name", tid)), "stops_labels": [],
				"vehicle_label": "flota de comercio", "good": "comercio exterior", "freq": "según contratos", "status": TradeSim.road_label(int(c.get("road", 1))),
				"month_qty": 0.0, "last_month_qty": 0.0, "active": true, "local": true, "intl": false, "editable": true, "town": tid})
	return out


static func _intl_endpoint(gs, iso: String, id: int) -> String:
	var r = CountriesSim.with_country(gs, iso, func(): return _short(LogisticsSim.endpoint_label(gs, id)))
	return str(r) if r != null else "?"


## Camino a dibujar de una ruta del modelo común (solo rutas locales del país cargado).
static func route_points(gs, u: Dictionary) -> PackedVector2Array:
	match str(u.get("kind", "")):
		"carga":
			if not LogisticsSim.endpoint_valid(gs, int(u["from"])) or not LogisticsSim.endpoint_valid(gs, int(u["to"])):
				return PackedVector2Array()
			return path_for(gs, int(u["from"]), int(u["to"]), str(u["mode"]), u.get("stops", []))
		"bus":
			var r := TransitSim.get_route(gs, int(u["id"]))
			var d: Dictionary = gs.get_building(int(r.get("depot", -1)))
			if d.is_empty():
				return PackedVector2Array()
			var pts := PackedVector2Array([Vector2(float(d["x"]), float(d["z"]))])
			for sid in r.get("stops", []):
				var s := TransitSim.get_stop(gs, int(sid))
				if not s.is_empty():
					var leg := road_path(gs, pts[pts.size() - 1], TransitSim.stop_pos(s), TransitSim.bus_kinds())
					for i in range(1, leg.size()):
						pts.append(leg[i])
			return pts
		"comercio":
			var tid := str(u.get("town", ""))
			var p := TransitSim.trade_path_of(gs, tid, str(u.get("family", "")) == "riel")
			if p.is_empty():
				p = TransitSim.trade_path_of(gs, tid)
			return p if not p.is_empty() else TransitSim.auto_trade_path(gs)
	return PackedVector2Array()


# --- Creación unificada ---------------------------------------------------------------------------

## Crea una ruta desde el asistente. opts: mode, from, to, stops, good, qty, auto, every, vehicle, color,
## name, from_iso/to_iso (entre países: mode barco | naviera | avion | comercial).
## Devuelve {"error"} o {"key", "route"}.
static func create(gs, opts: Dictionary) -> Dictionary:
	var here := CountriesSim.current_id() if CountriesSim.ready(gs) else ""
	var from_iso := str(opts.get("from_iso", here))
	var to_iso := str(opts.get("to_iso", from_iso))
	var mode := str(opts.get("mode", "pie"))
	if from_iso != to_iso:
		if ShipSim.is_ship_mode(mode):
			mode = "barco"
		if not ["barco", "naviera", "avion", "comercial"].has(mode):
			return {"error": "Entre países la carga va solo por avión o barco"}
		var o := opts.duplicate()
		o["mode"] = mode
		o["from_iso"] = from_iso
		o["to_iso"] = to_iso
		if bool(opts.get("auto", false)):
			var r := AirSim.create_route(gs, o)
			if r.has("error"):
				return r
			decorate(gs, "A%d" % int(r["route"]["id"]), r["route"], opts)
			return {"key": "A%d" % int(r["route"]["id"]), "route": r["route"]}
		var res := ShipSim.ship_intl(gs, o) if mode in ["barco", "naviera"] else AirSim.ship(gs, o)
		if res.has("error"):
			return res
		return {"key": "", "route": {}, "flight": res["flight"]}
	var res2 := LogisticsSim.create_route(gs, opts)
	if res2.has("error"):
		return res2
	return {"key": "L%d" % int(res2["route"]["id"]), "route": res2["route"]}


static func remove(gs, key: String) -> void:
	var id := int(key.substr(1)) if key.substr(1).is_valid_int() else -1
	match key.substr(0, 1):
		"L":
			LogisticsSim.remove_route(gs, id)
		"A":
			AirSim.remove_route(gs, id)
		"B":
			TransitSim.remove_route(gs, id)
	_bump(gs)


## Vehículos que sirven para el medio (para el asistente): [{id, name, busy, base}].
static func vehicles_for(gs, mode: String) -> Array:
	var out := []
	var now := float(gs.today()) + TimeManager.hour_float() / 24.0
	for v in LogisticsSim.vehicles(gs):
		if str(v.get("mode", "")) == mode or (mode == "barco" and ShipSim.is_ship_mode(str(v.get("mode", ""))) and bool(LogisticsSim.mode_def(str(v["mode"])).get("intl", false))):
			var st: Dictionary = gs.get_building(int(v["base"]))
			out.append({"id": int(v["id"]), "name": str(v.get("name", "")), "busy": LogisticsSim.vehicle_busy(gs, int(v["id"]), now),
					"base": gs.building_label(st) if not st.is_empty() else "", "connected": GarageSim.linked(gs, st),
					"capacity": LogisticsSim.vehicle_capacity(gs, v)})
	return out


## Medios para el asistente dentro del país: [{mode, label, family, locked}].
static func wizard_modes(gs) -> Array:
	var out := []
	for m in GameData.sorted_ids(LogisticsSim.modes()):
		var md := LogisticsSim.mode_def(str(m))
		out.append({"mode": str(m), "label": LogisticsSim.mode_label(str(m)), "family": family(str(m)), "locked": not gs.has_tech(str(md.get("tech", ""))),
				"capacity": int(md.get("capacity", 0))})
	return out


## Resumen para el panel: {routes, local, intl, month}.
static func summary(gs) -> Dictionary:
	var rs := all_routes(gs)
	var month := 0.0
	var intl := 0
	for u in rs:
		if u["kind"] in ["carga", "internacional"]:
			month += float(u["month_qty"])
		if bool(u["intl"]):
			intl += 1
	return {"routes": rs.size(), "intl": intl, "local": rs.size() - intl, "month": month}
