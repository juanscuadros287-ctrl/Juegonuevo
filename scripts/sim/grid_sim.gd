class_name GridSim
extends RefCounted
## Redes de servicios públicos por tramos (docs/REDES.md): electricidad (tendido aéreo con postes
## desde el Dínamo, cable subterráneo desde Redes eléctricas) y agua (tubería subterránea desde
## Potabilización, ver WaterSim). Los tramos se trazan como las carreteras (RoadSim) y se unen en
## redes (componentes conexas: tramos que comparten extremo, se tocan o se cruzan).
##
## - Un edificio está CONECTADO a una red si un tramo pasa a menos de `reach` m de su borde, y
##   (salvo las centrales/plantas) pagó su acometida única. La acometida la paga el dueño (tú, el
##   vecino propietario o, en las chozas del pueblo, el residente con más ahorros): es cable y
##   medidor que se compran fuera (el dinero sale del pueblo). El tendido lo paga quien lo construye.
## - Electricidad: cada red reparte la generación de SUS centrales entre SUS consumidores (menos las
##   pérdidas por metro de cable). Si falta, solo compra a la red regional la red que toca la entrada
##   regional (la plaza o el camino de la ruta comercial) y si hay una ruta comercial terminada.
## - Hogares conectados: consumen cada día y pagan una FACTURA MENSUAL (tarifa configurable × precio
##   de mercado) a tus centrales de esa red, o a la red regional si la energía vino de fuera.
##   Quien no paga queda cortado el mes siguiente. Economía cerrada: el dinero sale de los vecinos.
## - Viviendas de nivel alto (≥ home_min_level, desde home_tech) sin conexión: menos calidad y
##   felicidad, renta y precio de venta × value_mult, los inquilinos se van, y no se pueden mejorar
##   a esos niveles sin un tramo cerca.
## - Tormentas: pueden cortar el tendido aéreo (se repara solo en unos días y se paga).
## - Partidas viejas: si ya había centrales o casas altas, período de gracia (red virtual global).
## Estado: gs.utilities (se guarda). Configuración: data/utilities.json.

const POWER := "power"
const WATER := "water"
const LEGACY := 1000000       # id de la red virtual del período de gracia (todo conectado)
const PRODUCT := "electricidad"

static var _comp_cache := {}   # clave -> {segs, net (id de red por tramo), info {id: {...}}}
static var _memo_fast := ""
static var _memo_slow := ""
static var _memo := {}         # {power: {bid: net}, water: {bid: net}, sources: {power: {net: true}, water: {...}}}


# --- Configuración -------------------------------------------------------------------------------

static func cfg() -> Dictionary:
	return GameData.extra("utilities")


static func grid_cfg() -> Dictionary:
	return cfg().get("grid", {})


static func water_cfg() -> Dictionary:
	return cfg().get("water", {})


static func layer_cfg(layer: String) -> Dictionary:
	return grid_cfg() if layer == POWER else water_cfg()


static func kind_def(kind: String) -> Dictionary:
	return cfg().get("kinds", {}).get(kind, {})


static func kind_label(kind: String) -> String:
	return str(kind_def(kind).get("label", kind))


static func kind_layer(kind: String) -> String:
	return str(kind_def(kind).get("layer", POWER))


static func kinds_of(layer: String) -> Array:
	var out := []
	for k in GameData.sorted_ids(cfg().get("kinds", {})):
		if kind_layer(str(k)) == layer:
			out.append(str(k))
	return out


static func reach(layer: String) -> float:
	return float(layer_cfg(layer).get("reach", 12.0))


static func layer_label(layer: String) -> String:
	return "Electricidad" if layer == POWER else "Agua"


# --- Estado --------------------------------------------------------------------------------------

static func init_state(gs) -> void:
	var st: Dictionary = gs.utilities
	var defaults := {
		"segments": [], "next_id": 1, "version": 0, "legacy_until": -1,
		"tariff": {POWER: float(grid_cfg().get("tariff_default", 1.0)), WATER: float(water_cfg().get("tariff_default", 1.2))},
		"hooked": {}, "bills": {}, "plant_units": {}, "cut": {}, "nets": {},
		"month": {}, "last_month": {}, "well": {},
	}
	for k in defaults:
		if not st.has(k):
			st[k] = defaults[k]
	for sub in ["hooked", "bills", "plant_units", "cut", "nets"]:
		var d: Dictionary = st[sub]
		for layer in [POWER, WATER]:
			if not d.has(layer):
				d[layer] = [] if sub == "nets" else {}


static func state(gs) -> Dictionary:
	if not gs.utilities.has("segments"):
		init_state(gs)
	return gs.utilities


## Partida guardada antes de las redes: si ya había centrales (con el dínamo) o casas altas, se da un
## período de gracia (la red funciona como antes, global) para tender los cables sin apagones.
static func migrate(gs) -> void:
	init_state(gs)
	var needs := false
	for b in gs.buildings:
		if gs.owned_by_player(b) and EnergySim.is_plant(gs.building_def(b)) and EnergySim.grid_active(gs):
			needs = true
		elif Housing.is_home(b) and int(b.get("level", 1)) >= int(grid_cfg().get("home_min_level", 4)):
			needs = true
	if needs:
		state(gs)["legacy_until"] = -2   # Se fija al primer día (TimeManager se carga después).


static func legacy_active(gs) -> bool:
	var lu := int(state(gs).get("legacy_until", -1))
	return lu == -2 or (lu >= 0 and gs.today() < lu)


static func tariff(gs, layer: String) -> float:
	return float(state(gs).get("tariff", {}).get(layer, 1.0))


static func set_tariff(gs, layer: String, value: float) -> void:
	var c := layer_cfg(layer)
	state(gs)["tariff"][layer] = clampf(value, float(c.get("tariff_min", 0.5)), float(c.get("tariff_max", 2.5)))


static func layer_active(gs, layer: String) -> bool:
	if layer == POWER:
		return EnergySim.grid_active(gs)
	return WaterSim.pipes_active(gs)


# --- Tramos --------------------------------------------------------------------------------------

static func segments(gs, layer := "") -> Array:
	var all: Array = state(gs)["segments"]
	if layer == "":
		return all
	return all.filter(func(s): return kind_layer(str(s["kind"])) == layer)


static func seg_a(s: Dictionary) -> Vector2:
	return Vector2(float(s["ax"]), float(s["az"]))


static func seg_b(s: Dictionary) -> Vector2:
	return Vector2(float(s["bx"]), float(s["bz"]))


static func seg_len(s: Dictionary) -> float:
	return seg_a(s).distance_to(seg_b(s))


static func is_broken(s: Dictionary) -> bool:
	return bool(s.get("broken", false))


static func total_length(gs, kind := "", layer := "") -> float:
	var total := 0.0
	for s in segments(gs, layer):
		if kind == "" or str(s["kind"]) == kind:
			total += seg_len(s)
	return total


static func cost_per_m(gs, kind: String) -> float:
	return float(kind_def(kind).get("cost_per_m", 2.0)) * gs.price_mult()


static func segment_cost(gs, a: Vector2, b: Vector2, kind: String) -> float:
	return a.distance_to(b) * cost_per_m(gs, kind)


## Motivo por el que no se puede tender el tramo ("" si se puede). El agua la verifica el mundo 3D.
static func block_reason(gs, a: Vector2, b: Vector2, kind: String) -> String:
	var kd := kind_def(kind)
	if kd.is_empty():
		return "Tipo de red desconocido"
	if not gs.has_tech(str(kd.get("tech", ""))):
		return "Requiere investigar: %s" % GameData.tech_label(str(kd.get("tech", "")))
	var length := a.distance_to(b)
	if length < float(grid_cfg().get("min_length", 2.0)):
		return "Tramo demasiado corto"
	if length > float(grid_cfg().get("max_length", 60.0)):
		return "Tramo demasiado largo (máx. %d m): haz varios tramos" % int(grid_cfg().get("max_length", 60.0))
	for t in [0.0, 0.25, 0.5, 0.75, 1.0]:
		if not RoadSim._zone_unlocked(gs, a.lerp(b, t)):
			return "Pasa por terreno del gobierno: cómpralo primero"
	var c := segment_cost(gs, a, b, kind)
	if gs.money < c:
		return "Dinero insuficiente (%s)" % Fmt.money(c)
	return ""


## Ajusta un punto al extremo más cercano de un tramo de la misma capa (para unir tramos).
static func snap(gs, p: Vector2, layer: String) -> Vector2:
	var best := p
	var best_d := float(grid_cfg().get("snap", 3.0))
	for s in segments(gs, layer):
		for q in [seg_a(s), seg_b(s)]:
			var d := p.distance_to(q)
			if d < best_d:
				best_d = d
				best = q
	return best


## Tiende un tramo pagando su costo. Devuelve "" o el motivo.
static func build(gs, a: Vector2, b: Vector2, kind: String) -> String:
	var layer := kind_layer(kind)
	a = snap(gs, a, layer)
	b = snap(gs, b, layer)
	var reason := block_reason(gs, a, b, kind)
	if reason != "":
		return reason
	var c := segment_cost(gs, a, b, kind)
	gs.add_money(-c)
	var st := state(gs)
	st["month"]["build_" + layer] = float(st["month"].get("build_" + layer, 0.0)) + c
	add_segment(gs, a, b, kind)
	return ""


## Agrega un tramo sin cobrar (pruebas y herramientas). Devuelve el tramo.
static func add_segment(gs, a: Vector2, b: Vector2, kind: String) -> Dictionary:
	var st := state(gs)
	var id := int(st.get("next_id", 1))
	st["next_id"] = id + 1
	var s := {"id": id, "kind": kind, "ax": a.x, "az": a.y, "bx": b.x, "bz": b.y, "broken": false, "repair_day": -1}
	st["segments"].append(s)
	bump(gs)
	return s


static func remove(gs, id: int) -> void:
	var segs: Array = state(gs)["segments"]
	for i in range(segs.size()):
		if int(segs[i]["id"]) == id:
			segs.remove_at(i)
			bump(gs)
			return


## Quita el último tramo tendido de una capa (sin reembolso).
static func remove_last(gs, layer: String) -> bool:
	var segs := segments(gs, layer)
	if segs.is_empty():
		return false
	remove(gs, int(segs[segs.size() - 1]["id"]))
	return true


static func bump(gs) -> void:
	var st := state(gs)
	st["version"] = int(st.get("version", 0)) + 1


# --- Redes (componentes conexas) -----------------------------------------------------------------

## {segs: tramos sanos de la capa, net: id de red por tramo (el menor id de tramo del grupo),
##  info: {net: {tie, loss, length, lengths{kind}, segs}}}
static func components(gs, layer: String) -> Dictionary:
	var st := state(gs)
	var key := "%s|%d|%d|%d" % [layer, int(st.get("version", 0)), (st["segments"] as Array).size(), int(gs.settings.get("seed", 0))]
	if _comp_cache.has(key):
		return _comp_cache[key]
	var segs := segments(gs, layer).filter(func(s): return not is_broken(s))
	var parent := []
	for i in range(segs.size()):
		parent.append(i)
	var touch := float(grid_cfg().get("touch", 1.5))
	for i in range(segs.size()):
		var a1 := seg_a(segs[i])
		var b1 := seg_b(segs[i])
		for j in range(i + 1, segs.size()):
			var a2 := seg_a(segs[j])
			var b2 := seg_b(segs[j])
			if RoadSim.dist_point_segment(a1, a2, b2) < touch or RoadSim.dist_point_segment(b1, a2, b2) < touch \
					or RoadSim.dist_point_segment(a2, a1, b1) < touch or RoadSim.dist_point_segment(b2, a1, b1) < touch \
					or RoadSim._cross(a1, b1, a2, b2):
				var ri := RoadSim._root(parent, i)
				var rj := RoadSim._root(parent, j)
				if ri != rj:
					parent[ri] = rj
	var root_id := {}
	for i in range(segs.size()):
		var r := RoadSim._root(parent, i)
		root_id[r] = mini(int(root_id.get(r, 1 << 30)), int(segs[i]["id"]))
	var net := []
	var info := {}
	for i in range(segs.size()):
		var n: int = int(root_id[RoadSim._root(parent, i)])
		net.append(n)
		if not info.has(n):
			info[n] = {"tie": false, "loss": 0.0, "length": 0.0, "lengths": {}, "segs": 0}
		var inf: Dictionary = info[n]
		var s: Dictionary = segs[i]
		var l := seg_len(s)
		var kd := kind_def(str(s["kind"]))
		inf["length"] = float(inf["length"]) + l
		inf["segs"] = int(inf["segs"]) + 1
		inf["lengths"][str(s["kind"])] = float(inf["lengths"].get(str(s["kind"]), 0.0)) + l
		inf["loss"] = minf(float(grid_cfg().get("max_loss", 0.25)), float(inf["loss"]) + l / 100.0 * float(kd.get("loss_per_100m", 0.0)))
		if layer == POWER and not bool(inf["tie"]) and _touches_regional(gs, seg_a(s), seg_b(s)):
			inf["tie"] = true
	var out := {"segs": segs, "net": net, "info": info}
	if _comp_cache.size() > 24:
		_comp_cache.clear()
	_comp_cache[key] = out
	return out


## Trazado del camino de la ruta comercial (igual que TradeVisuals): sale de la plaza hacia el oeste.
static func trade_path_z(gs, x: float) -> float:
	var seed_v := float(int(gs.settings.get("seed", 1)) % 1000)
	var t: float = (-x - 8.5) / (gs.MAP_SIZE * 0.5)
	return sin(x * 0.021 + seed_v) * 9.0 * t + sin(x * 0.053 + seed_v * 0.3) * 3.0 * t


## ¿El tramo toca la entrada de la red regional? (la plaza o el camino de la ruta comercial)
static func _touches_regional(gs, a: Vector2, b: Vector2) -> bool:
	var r := float(grid_cfg().get("tie_reach", 14.0))
	if RoadSim.dist_point_segment(Vector2.ZERO, a, b) <= r + 8.5:
		return true
	var n := maxi(1, int(a.distance_to(b) / 3.0))
	for i in range(n + 1):
		var p := a.lerp(b, float(i) / n)
		if TransitSim.near_trade_path(gs, p, r):   # Transporte: camino automático o trazado a mano.
			return true
	return false


## Red (id) de cada edificio por capa, con memo por día/versión/edificios.
static func _nets(gs) -> Dictionary:
	var st := state(gs)
	var fast := "%d|%d|%d|%d|%d|%d" % [gs.today(), int(st.get("version", 0)), gs.buildings.size(), int(gs.next_building_id), Engine.get_process_frames(), int(gs.settings.get("seed", 0))]
	if fast == _memo_fast and not _memo.is_empty():
		return _memo
	var sig := 0.0
	for b in gs.buildings:
		sig += float(b["x"]) * 3.1 + float(b["z"]) * 7.3 + int(b.get("level", 1)) * 11.0 + (1.0 if b["status"] == "activo" else 0.0)
	var slow := "%d|%d|%d|%d|%.3f" % [int(st.get("version", 0)), gs.buildings.size(), int(gs.next_building_id), int(gs.settings.get("seed", 0)), sig]
	_memo_fast = fast
	if slow == _memo_slow and not _memo.is_empty():
		return _memo
	_memo_slow = slow
	var out := {POWER: {}, WATER: {}, "sources": {POWER: {}, WATER: {}}}
	for layer in [POWER, WATER]:
		var comp := components(gs, layer)
		var segs: Array = comp["segs"]
		var r := reach(layer)
		var map: Dictionary = out[layer]
		var src: Dictionary = out["sources"][layer]
		for n in comp["info"]:
			if layer == POWER and bool(comp["info"][n]["tie"]):
				src[n] = "regional"
		if segs.is_empty():
			continue
		for b in gs.buildings:
			var p := Vector2(float(b["x"]), float(b["z"]))
			var half: float = gs.footprint_of(b) * 0.5
			var lim := half + r
			for i in range(segs.size()):
				var s: Dictionary = segs[i]
				var a := seg_a(s)
				var e := seg_b(s)
				if p.x < minf(a.x, e.x) - lim or p.x > maxf(a.x, e.x) + lim or p.y < minf(a.y, e.y) - lim or p.y > maxf(a.y, e.y) + lim:
					continue
				if RoadSim.dist_point_segment(p, a, e) - half <= r:
					var n: int = int(comp["net"][i])
					map[int(b["id"])] = n
					if b["status"] == "activo" and gs.owned_by_player(b):
						var def: Dictionary = gs.building_def(b)
						if (layer == POWER and EnergySim.is_plant(def)) or (layer == WATER and WaterSim.is_water_plant(def)):
							src[n] = "planta"
					break
	_memo = out
	return out


## Red de un edificio en una capa (-1 = ningún tramo cerca). En el período de gracia, todo está en
## la red virtual LEGACY (electricidad).
static func net_of(gs, b: Dictionary, layer: String) -> int:
	if b.is_empty():
		return -1
	if layer == POWER and legacy_active(gs):
		return LEGACY
	return int(_nets(gs)[layer].get(int(b["id"]), -1))


## ¿La red tiene de dónde sacar (central/planta propia o entrada regional)?
static func has_source(gs, layer: String, net: int) -> bool:
	if net == LEGACY:
		return true
	if net < 0:
		return false
	var s := str(_nets(gs)["sources"][layer].get(net, ""))
	if s == "regional":
		return EnergySim.grid_available(gs)
	return s != ""


## Distancia al tramo más cercano de la capa (INF si no hay) medida desde el borde.
static func edge_distance(gs, x: float, z: float, fp: float, layer: String) -> float:
	var p := Vector2(x, z)
	var best := INF
	for s in segments(gs, layer):
		if is_broken(s):
			continue
		best = minf(best, RoadSim.dist_point_segment(p, seg_a(s), seg_b(s)) - fp * 0.5)
	return best


static func is_source(gs, b: Dictionary, layer: String) -> bool:
	var def: Dictionary = gs.building_def(b)
	return EnergySim.is_plant(def) if layer == POWER else WaterSim.is_water_plant(def)


## ¿Necesita acometida? Casas (electricidad desde home_tech) y negocios que consumen electricidad;
## en agua solo las casas.
static func needs_hookup(gs, b: Dictionary, layer: String) -> bool:
	if is_source(gs, b, layer):
		return false
	if Housing.is_home(b):
		return layer == WATER or EnergySim.homes_active(gs)
	if layer == WATER:
		return false
	return BusinessSim.is_business(b) and EnergySim.level_demand_kw(gs.building_def(b), gs.level_def(b)) > 0.0


static func is_hooked(gs, b: Dictionary, layer: String) -> bool:
	return state(gs)["hooked"][layer].has(str(int(b["id"])))


static func hookup_cost(gs, b: Dictionary, layer: String) -> float:
	var h: Dictionary = layer_cfg(layer).get("hookup", {})
	return float(h.get("vivienda" if Housing.is_home(b) else "negocio", 20.0)) * gs.price_mult()


## Conectado = en una red y (fuente o acometida pagada). Período de gracia: todo conectado.
static func connected(gs, b: Dictionary, layer: String) -> bool:
	if b.is_empty():
		return false
	if layer == POWER and legacy_active(gs):
		return true
	if net_of(gs, b, layer) < 0:
		return false
	return is_source(gs, b, layer) or is_hooked(gs, b, layer)


# --- Simulación diaria ---------------------------------------------------------------------------

static func daily(gs) -> void:
	var st := state(gs)
	var today: int = gs.today()
	var lu := int(st.get("legacy_until", -1))
	if lu == -2:
		st["legacy_until"] = today + int(grid_cfg().get("grace_days", 120))
		gs.notify("Llegan las redes eléctricas y de agua: tienes %d días de gracia para tender cables (Servicios públicos) hasta tus centrales, fábricas y casas altas; después solo recibirá electricidad lo conectado." % int(grid_cfg().get("grace_days", 120)), "importante")
	elif lu >= 0 and today == lu:
		gs.notify("Terminó el período de gracia de la red eléctrica: ahora solo reciben electricidad los edificios conectados por cable.", "importante")
	_storms(gs, st, today)
	_repairs(gs, st, today)
	_hookups(gs, st)
	_home_penalties(gs)


static func _storms(gs, st: Dictionary, today: int) -> void:
	if str(gs.weather.get("type", "")) != str(grid_cfg().get("storm_weather", "tormenta")):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(gs.settings.get("seed", 0)), today, "tormenta"])
	var n := 0
	for s in segments(gs, POWER):
		var p := float(kind_def(str(s["kind"])).get("storm_break_per_100m", 0.0)) * seg_len(s) / 100.0
		if is_broken(s) or p <= 0.0:
			continue
		if rng.randf() < p:
			s["broken"] = true
			s["repair_day"] = today + int(grid_cfg().get("repair_days", 2))
			n += 1
	if n > 0:
		bump(gs)
		gs.notify("La tormenta tumbó %d tramo(s) del tendido aéreo: hay cortes de luz hasta que se reparen (%d días). El cable subterráneo no se cae." % [n, int(grid_cfg().get("repair_days", 2))], "clima")


static func _repairs(gs, st: Dictionary, today: int) -> void:
	var fixed := false
	for s in segments(gs, POWER):
		if is_broken(s) and today >= int(s.get("repair_day", 0)):
			var c := segment_cost(gs, seg_a(s), seg_b(s), str(s["kind"])) * float(grid_cfg().get("repair_cost_share", 0.15))
			gs.add_money(-c)
			st["month"]["repairs"] = float(st["month"].get("repairs", 0.0)) + c
			s["broken"] = false
			s["repair_day"] = -1
			fixed = true
	if fixed:
		bump(gs)


## Acometidas: cada edificio que necesita servicio y ya tiene un tramo cerca paga la suya una vez.
static func _hookups(gs, st: Dictionary) -> void:
	var paid := {POWER: 0, WATER: 0}
	var player_cost := 0.0
	for layer in [POWER, WATER]:
		if not layer_active(gs, layer) or segments(gs, layer).is_empty():
			continue
		var hooked: Dictionary = st["hooked"][layer]
		for b in gs.buildings:
			if b["status"] != "activo" or hooked.has(str(int(b["id"]))):
				continue
			if int(_nets(gs)[layer].get(int(b["id"]), -1)) < 0 or not needs_hookup(gs, b, layer):
				continue
			var cost := hookup_cost(gs, b, layer)
			var who := _hookup_payer(gs, b, cost)
			if who == "":
				continue
			hooked[str(int(b["id"]))] = true
			paid[layer] = int(paid[layer]) + 1
			st["month"]["hookups_" + layer] = float(st["month"].get("hookups_" + layer, 0.0)) + cost
			if who == "jugador":
				player_cost += cost
	if int(paid[POWER]) + int(paid[WATER]) > 0:
		gs.notify("Acometidas nuevas: %d a la red eléctrica y %d a la de agua%s." % [int(paid[POWER]), int(paid[WATER]),
				(" (pagaste %s por tus edificios)" % Fmt.money(player_cost)) if player_cost > 0.0 else ""], "negocio")


## Paga la acometida el dueño. Devuelve quién pagó ("jugador", "ciudadano") o "" si nadie pudo.
static func _hookup_payer(gs, b: Dictionary, cost: float) -> String:
	var owner := str(b.get("owner", "pueblo"))
	if owner == "jugador":
		if gs.money >= cost * 3.0:
			gs.add_money(-cost)
			BusinessSim.ledger_add(b, "obras", cost)
			return "jugador"
		return ""
	var payer: Citizen = null
	if owner == "ciudadano" and gs.citizens.has(int(b.get("owner_id", -1))):
		payer = gs.citizens[int(b.get("owner_id", -1))]
	else:
		for c in gs.residents_of(int(b["id"])):
			if gs.is_player(c.id):
				continue
			if payer == null or c.money > payer.money:
				payer = c
	if payer == null or gs.is_player(payer.id) or payer.money < cost * 1.5:
		return ""
	payer.money -= cost
	return "ciudadano"


## Faltas de servicio de una vivienda (capas requeridas y no conectadas).
static func home_missing(gs, b: Dictionary) -> Array:
	var out := []
	if b.is_empty() or not Housing.is_home(b) or legacy_active(gs):
		return out
	var lvl := int(b.get("level", 1))
	for layer in [POWER, WATER]:
		var c := layer_cfg(layer)
		if lvl < int(c.get("home_min_level", 4)) or not gs.has_tech(str(c.get("home_tech", ""))):
			continue
		if not (connected(gs, b, layer) and has_source(gs, layer, net_of(gs, b, layer))):
			out.append(layer)
	return out


## Suma a la calidad de la vivienda (MarketSim.home_quality): faltas y agua por tubería.
static func home_quality_delta(gs, b: Dictionary) -> float:
	if b.is_empty() or not Housing.is_home(b):
		return 0.0
	var d := 0.0
	for layer in home_missing(gs, b):
		d += float(layer_cfg(layer).get("missing", {}).get("quality", -0.6))
	if WaterSim.home_piped(gs, b):
		d += float(water_cfg().get("piped_quality_add", 0.2))
	return d


## Multiplicador de renta y precio de venta por servicios que faltan.
static func home_value_mult(gs, b: Dictionary) -> float:
	var m := 1.0
	for layer in home_missing(gs, b):
		m *= float(layer_cfg(layer).get("missing", {}).get("value_mult", 0.7))
	return m


## Mejorar una vivienda a un nivel que exige red: debe haber un tramo cerca.
static func upgrade_block_reason(gs, b: Dictionary, next: int) -> String:
	if not Housing.is_home(b) or legacy_active(gs):
		return ""
	for layer in [POWER, WATER]:
		var c := layer_cfg(layer)
		if next < int(c.get("home_min_level", 4)) or not gs.has_tech(str(c.get("home_tech", ""))):
			continue
		var fp := GameData.footprint(str(b["type"]), next)
		if edge_distance(gs, float(b["x"]), float(b["z"]), fp, layer) > reach(layer):
			return "Ese nivel exige %s: tiende %s a menos de %d m (Servicios públicos)" % [
				"conexión eléctrica" if layer == POWER else "agua por tubería",
				"un cable" if layer == POWER else "una tubería", int(reach(layer))]
	return ""


static func _home_penalties(gs) -> void:
	if legacy_active(gs):
		return
	var pen := {}
	for b in gs.buildings:
		if Housing.is_home(b) and int(b.get("level", 1)) >= mini(int(grid_cfg().get("home_min_level", 4)), int(water_cfg().get("home_min_level", 4))):
			var miss := home_missing(gs, b)
			if not miss.is_empty():
				var h := 0.0
				for layer in miss:
					h += float(layer_cfg(layer).get("missing", {}).get("happiness_day", -0.3))
				pen[int(b["id"])] = h
	if pen.is_empty():
		return
	for c in gs.citizens.values():
		if pen.has(c.home_id):
			c.happiness = clampf(c.happiness + float(pen[c.home_id]), 0.0, 100.0)


# --- Reparto eléctrico por red (llamado desde EnergySim.daily) -----------------------------------

static func _net_entry(nets: Dictionary, n: int) -> Dictionary:
	if not nets.has(n):
		nets[n] = {"plants": [], "supply": 0.0, "eff": 0.0, "users": [], "demand": 0.0, "homes": 0, "home_own": 0.0, "home_grid": 0.0, "grid_units": 0.0, "own_business": 0.0, "surplus": 0.0}
	return nets[n]


static func power_daily(gs, est: Dictionary) -> void:
	var st := state(gs)
	var nets := {}
	var off_users := []
	var supply_all := 0.0
	var demand_all := 0.0
	var stranded := 0.0
	for b in gs.buildings:
		if b["status"] != "activo":
			continue
		var def: Dictionary = gs.building_def(b)
		if EnergySim.is_plant(def):
			if not gs.owned_by_player(b):
				continue
			var e := float(b["inventory"].get(PRODUCT, 0.0))
			if e <= 0.0:
				continue
			supply_all += e
			var pn := net_of(gs, b, POWER)
			if pn < 0:
				stranded += e   # Central sin cables: su electricidad se pierde.
				continue
			var ne := _net_entry(nets, pn)
			ne["plants"].append([b, e])
			ne["supply"] = float(ne["supply"]) + e
			continue
		var d := EnergySim.demand_of(gs, b)
		if d <= 0.0:
			continue
		demand_all += d
		var n := net_of(gs, b, POWER) if connected(gs, b, POWER) else -1
		if n < 0:
			off_users.append([b, d])
		else:
			var ne := _net_entry(nets, n)
			ne["users"].append([b, d])
			ne["demand"] = float(ne["demand"]) + d
	var p := EnergySim.price(gs)
	var gp := EnergySim.grid_price(gs)
	var grid_ok := EnergySim.grid_available(gs)
	var comp := components(gs, POWER)
	var cov := {}
	var lost_value := 0.0
	var grid_units := 0.0
	var own_business_all := 0.0
	var eff_all := 0.0
	for n in nets:
		var ne: Dictionary = nets[n]
		var inf: Dictionary = comp["info"].get(n, {})
		var tie := int(n) == LEGACY or bool(inf.get("tie", false))
		ne["tie"] = tie
		var loss := 0.0 if int(n) == LEGACY else float(inf.get("loss", 0.0))
		var eff := float(ne["supply"]) * (1.0 - loss)
		ne["eff"] = eff
		eff_all += eff
		var demand := float(ne["demand"])
		var own_to_business := minf(eff, demand)
		var ratio_own := own_to_business / demand if demand > 0.0 else 1.0
		for pair in ne["users"]:
			var b: Dictionary = pair[0]
			var need: float = pair[1]
			var own := need * ratio_own
			var from_grid := 0.0
			if own < need and tie and grid_ok:
				from_grid = need - own
			if own > 0.0:
				BusinessSim.pay(gs, b, own * p, "insumos")   # Traspaso interno: lo cobra tu central.
			if from_grid > 0.0:
				BusinessSim.pay(gs, b, from_grid * gp, "insumos")   # Red regional: sale del pueblo.
				grid_units += from_grid
				ne["grid_units"] = float(ne["grid_units"]) + from_grid
			var c := clampf((own + from_grid) / need, 0.0, 1.0)
			cov[str(int(b["id"]))] = c
			if c < 0.999:
				lost_value += EnergySim._apply_shortfall(gs, b, (1.0 - c) * (1.0 - EnergySim.unpowered_output(gs.level_def(b))))
		EnergySim._bill_plants(gs, ne["plants"], own_to_business * p)
		ne["own_business"] = own_to_business
		own_business_all += own_to_business
		ne["surplus"] = eff - own_to_business
	for pair in off_users:
		var b: Dictionary = pair[0]
		cov[str(int(b["id"]))] = 0.0
		lost_value += EnergySim._apply_shortfall(gs, b, 1.0 - EnergySim.unpowered_output(gs.level_def(b)))
	# Hogares conectados.
	var home := {"units": 0.0, "own_units": 0.0, "grid_units": 0.0, "powered": 0, "unpowered": 0, "revenue": 0.0}
	if EnergySim.homes_active(gs):
		home = _homes_power(gs, st, nets, p, gp, grid_ok)
	est["coverage"] = cov
	var wasted := stranded
	for n in nets:
		wasted += maxf(0.0, float(nets[n]["surplus"]) - float(nets[n]["home_own"]))
	var m: Dictionary = est.get("month", {})
	for kv in [["supply", supply_all], ["demand", demand_all], ["own_business", own_business_all], ["grid_units", grid_units + float(home["grid_units"])],
			["homes_units", float(home["units"])], ["homes_powered", float(home["powered"])], ["homes_unpowered", float(home["unpowered"])],
			["lost_value", lost_value], ["wasted", wasted], ["days", 1.0]]:
		m[kv[0]] = float(m.get(kv[0], 0.0)) + float(kv[1])
	est["month"] = m
	est["today"] = {"supply": supply_all, "demand": demand_all, "grid": grid_ok, "homes": home, "stranded": stranded}
	# Resumen por red para el panel.
	var summary := []
	for n in nets:
		var ne: Dictionary = nets[n]
		var inf: Dictionary = comp["info"].get(n, {})
		var served := float(ne["own_business"]) + float(ne["grid_units"])
		summary.append({"id": int(n), "supply": float(ne["supply"]), "eff": float(ne["eff"]), "demand": float(ne["demand"]),
			"coverage": served / float(ne["demand"]) if float(ne["demand"]) > 0.0 else 1.0, "tie": bool(ne["tie"]),
			"loss": 0.0 if int(n) == LEGACY else float(inf.get("loss", 0.0)), "length": float(inf.get("length", 0.0)),
			"plants": (ne["plants"] as Array).size(), "users": (ne["users"] as Array).size(), "homes": int(ne["homes"]),
			"home_units": float(ne["home_own"]) + float(ne["home_grid"]), "grid_units": float(ne["grid_units"]) + float(ne["home_grid"])})
	summary.sort_custom(func(a, b): return int(a["id"]) < int(b["id"]))
	st["nets"][POWER] = summary


static func _homes_power(gs, st: Dictionary, nets: Dictionary, p: float, gp: float, grid_ok: bool) -> Dictionary:
	var ecfg := EnergySim.cfg()
	var per := float(ecfg.get("home_units_per_person_day", 0.3)) * 1.5
	var own_price := p * tariff(gs, POWER)
	var out := {"units": 0.0, "own_units": 0.0, "grid_units": 0.0, "powered": 0, "unpowered": 0, "revenue": 0.0}
	var today: int = gs.today()
	var adult := int(GameData.citizens.get("adult_age", 16))
	var hp := float(ecfg.get("home_powered_happiness", 1.5)) / 7.0
	var hu := float(ecfg.get("home_unpowered_happiness", -3.0)) / 7.0
	# Tarifa cara: menos alegría por tener luz.
	hp *= clampf(2.0 - tariff(gs, POWER), 0.0, 1.0)
	var bills: Dictionary = st["bills"][POWER]
	var cut: Dictionary = st["cut"][POWER]
	for c in gs.citizens.values():
		if c.age_years(today) < adult or c.home_id < 0 or gs.is_player(c.id):
			continue
		var home: Dictionary = gs.get_building(c.home_id)
		var n := -1
		if not home.is_empty() and connected(gs, home, POWER):
			n = net_of(gs, home, POWER)
		if n < 0 or cut.has(str(c.id)):
			out["unpowered"] = int(out["unpowered"]) + 1
			c.happiness = clampf(c.happiness + hu, 0.0, 100.0)
			continue
		var ne := _net_entry(nets, n)
		if not ne.has("tie"):
			var inf: Dictionary = components(gs, POWER)["info"].get(n, {})
			ne["tie"] = n == LEGACY or bool(inf.get("tie", false))
		var from_own := minf(per, maxf(0.0, float(ne["surplus"]) - float(ne["home_own"])))
		var from_grid := (per - from_own) if (bool(ne["tie"]) and grid_ok) else 0.0
		if from_own + from_grid < per * 0.999:
			out["unpowered"] = int(out["unpowered"]) + 1
			c.happiness = clampf(c.happiness + hu, 0.0, 100.0)
			continue
		ne["home_own"] = float(ne["home_own"]) + from_own
		ne["home_grid"] = float(ne["home_grid"]) + from_grid
		ne["homes"] = int(ne["homes"]) + 1
		var key := str(c.id)
		var bill: Dictionary = bills.get(key, {"own": 0.0, "grid": 0.0, "units": 0.0})
		bill["own"] = float(bill["own"]) + from_own * own_price
		bill["grid"] = float(bill["grid"]) + from_grid * gp
		bill["units"] = float(bill["units"]) + from_own
		bills[key] = bill
		out["units"] = float(out["units"]) + per
		out["own_units"] = float(out["own_units"]) + from_own
		out["grid_units"] = float(out["grid_units"]) + from_grid
		out["revenue"] = float(out["revenue"]) + from_own * own_price
		out["powered"] = int(out["powered"]) + 1
		c.happiness = clampf(c.happiness + hp, 0.0, 100.0)
	# La energía vendida a los hogares se atribuye a las centrales de cada red según lo que generaron.
	var units: Dictionary = st["plant_units"][POWER]
	for n in nets:
		var ne: Dictionary = nets[n]
		var own_units := float(ne["home_own"])
		if own_units <= 0.0 or float(ne["supply"]) <= 0.0:
			continue
		for pr in ne["plants"]:
			var k := str(int(pr[0]["id"]))
			units[k] = float(units.get(k, 0.0)) + own_units * float(pr[1]) / float(ne["supply"])
	return out


# --- Cierre mensual ------------------------------------------------------------------------------

static func monthly(gs) -> void:
	var st := state(gs)
	_bill(gs, st, POWER)
	_bill(gs, st, WATER)
	_upkeep(gs, st)
	_tenants_leave(gs, st)
	st["last_month"] = st["month"]
	st["month"] = {}


## Cobra las facturas del mes: lo propio a tus centrales/plantas (según lo que aportó cada una), lo
## regional sale del pueblo. Quien no puede pagar paga lo que tiene y queda cortado el mes siguiente.
static func _bill(gs, st: Dictionary, layer: String) -> void:
	var bills: Dictionary = st["bills"][layer]
	var units: Dictionary = st["plant_units"][layer]
	var plants := []
	for pid in units:
		var b: Dictionary = gs.get_building(int(pid))
		if not b.is_empty() and gs.owned_by_player(b) and float(units[pid]) > 0.0:
			plants.append([b, float(units[pid])])
	var cut := {}
	var own_total := 0.0
	var grid_total := 0.0
	var unpaid := 0.0
	var customers := 0
	var own_units := 0.0
	for key in bills:
		var c: Citizen = gs.citizens.get(int(key))
		if c == null:
			continue
		var bill: Dictionary = bills[key]
		var own := float(bill.get("own", 0.0)) if not plants.is_empty() else 0.0
		var grid := float(bill.get("grid", 0.0))
		var total := own + grid
		if total <= 0.0:
			continue
		customers += 1
		own_units += float(bill.get("units", 0.0))
		var pay := clampf(c.money, 0.0, total)
		c.money -= pay
		var f := pay / total
		own_total += own * f
		grid_total += grid * f
		if pay < total - 0.001:
			cut[key] = true
			unpaid += total - pay
	if own_total > 0.0:
		EnergySim._bill_plants(gs, plants, own_total)
		EconomySim.record_discretionary(gs, PRODUCT if layer == POWER else WaterSim.GOOD, own_units, own_total)
	var m: Dictionary = st["month"]
	m["income_" + layer] = own_total
	m["regional_" + layer] = grid_total
	m["unpaid_" + layer] = unpaid
	m["customers_" + layer] = customers
	m["cut_" + layer] = cut.size()
	st["cut"][layer] = cut
	st["bills"][layer] = {}
	st["plant_units"][layer] = {}
	if customers > 0:
		gs.notify("Facturas de %s: %d cliente(s) pagaron %s a tus empresas%s%s." % [
			"electricidad" if layer == POWER else "agua", customers, Fmt.money(own_total),
			(" y %s a la red regional" % Fmt.money(grid_total)) if grid_total > 0.005 else "",
			(" · %d quedan cortados por no pagar" % cut.size()) if not cut.is_empty() else ""], "negocio")


static func _upkeep(gs, st: Dictionary) -> void:
	var total := 0.0
	for s in segments(gs):
		total += seg_len(s) * float(kind_def(str(s["kind"])).get("upkeep_per_m", 0.0))
	total *= gs.price_mult()
	if total > 0.0:
		gs.add_money(-total)
		st["month"]["upkeep"] = total


## Los inquilinos de tus viviendas altas sin los servicios que exigen se van.
static func _tenants_leave(gs, st: Dictionary) -> void:
	if legacy_active(gs):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(gs.settings.get("seed", 0)), gs.today(), "inquilinos"])
	var p: Citizen = gs.player_citizen()
	var left := 0
	for b in gs.buildings:
		if not Housing.is_home(b) or not gs.owned_by_player(b) or (p != null and int(b["id"]) == p.home_id):
			continue
		var miss := home_missing(gs, b)
		if miss.is_empty():
			continue
		var chance := 0.0
		for layer in miss:
			chance = maxf(chance, float(layer_cfg(layer).get("missing", {}).get("leave_chance", 0.3)))
		if rng.randf() >= chance:
			continue
		var res: Array = gs.residents_of(int(b["id"]))
		for c in res:
			if not gs.is_player(c.id):
				c.home_id = -1
				left += 1
		if not res.is_empty():
			gs.notify("Los inquilinos de %s se fueron: falta %s." % [gs.building_label(b), " y ".join(miss.map(func(l): return "electricidad" if l == POWER else "agua por tubería"))], "negocio")
	if left > 0:
		EventBus.citizens_moved.emit()


# --- Interfaz ------------------------------------------------------------------------------------

## Líneas para el panel de edificio: "Electricidad: conectado / sin conexión" y "Agua: …".
static func panel_lines(gs, b: Dictionary) -> String:
	var s := ""
	var def: Dictionary = gs.building_def(b)
	var uses_power := Housing.is_home(b) or EnergySim.is_plant(def) or EnergySim.level_demand_kw(def, gs.level_def(b)) > 0.0
	if uses_power and EnergySim.grid_active(gs):
		s += "Electricidad: " + _power_status(gs, b) + "\n"
	if Housing.is_home(b) or WaterSim.is_water_plant(def):
		s += "Agua: " + WaterSim.status_text(gs, b) + "\n"
	return s


static func _power_status(gs, b: Dictionary) -> String:
	if legacy_active(gs):
		return "[color=#e9b949]período de gracia (red global) hasta el %s[/color]" % TimeManager.date_from_day(int(state(gs)["legacy_until"]), TimeManager.start_year())
	var n := net_of(gs, b, POWER)
	var ld: Dictionary = gs.level_def(b)
	var req := EnergySim.requires_power(ld)
	if n < 0:
		var t := "[color=#e66]sin conexión[/color] — tiende un cable a menos de %d m" % int(reach(POWER))
		if req:
			t += " · [color=#e66]este nivel NO produce sin electricidad[/color]"
		elif Housing.is_home(b) and int(b.get("level", 1)) >= int(grid_cfg().get("home_min_level", 4)) and gs.has_tech(str(grid_cfg().get("home_tech", ""))):
			t += " · [color=#e66]la vivienda pierde calidad, renta y precio[/color]"
		return t
	if not connected(gs, b, POWER):
		return "[color=#e9b949]red cerca, falta la acometida (%s, la paga el dueño)[/color]" % Fmt.money(hookup_cost(gs, b, POWER))
	var t := "[color=#6c6]conectado[/color] (red %d" % n
	if EnergySim.is_plant(gs.building_def(b)):
		t += ", central)"
	elif BusinessSim.is_business(b):
		t += ", cobertura %d%%)" % int(round(EnergySim.supply_ratio(gs, b) * 100.0))
	else:
		t += ")"
	if not has_source(gs, POWER, n):
		t += " [color=#e9b949]pero la red no tiene central ni entrada regional[/color]"
	if req:
		t += " · exige electricidad"
	return t


## Resumen para el panel de servicios públicos.
static func summary(gs) -> Dictionary:
	var st := state(gs)
	var lm: Dictionary = st.get("last_month", {})
	var m: Dictionary = st.get("month", {})
	var pw_clients := 0
	var wt_clients := 0
	var hooked_p: Dictionary = st["hooked"][POWER]
	var hooked_w: Dictionary = st["hooked"][WATER]
	for b in gs.buildings:
		if Housing.is_home(b):
			if hooked_p.has(str(int(b["id"]))) and connected(gs, b, POWER):
				pw_clients += 1
			if hooked_w.has(str(int(b["id"])) ) and connected(gs, b, WATER):
				wt_clients += 1
	return {
		"legacy": legacy_active(gs), "legacy_until": int(st.get("legacy_until", -1)),
		"power_nets": st["nets"][POWER], "water_nets": st["nets"][WATER],
		"power_homes": pw_clients, "water_homes": wt_clients,
		"tariff_power": tariff(gs, POWER), "tariff_water": tariff(gs, WATER),
		"income_power": float(lm.get("income_" + POWER, 0.0)), "income_water": float(lm.get("income_" + WATER, 0.0)),
		"regional_power": float(lm.get("regional_" + POWER, 0.0)),
		"customers_power": int(lm.get("customers_" + POWER, 0)), "customers_water": int(lm.get("customers_" + WATER, 0)),
		"cut_power": int(lm.get("cut_" + POWER, 0)), "cut_water": int(lm.get("cut_" + WATER, 0)),
		"upkeep": float(lm.get("upkeep", 0.0)), "repairs": float(lm.get("repairs", 0.0)) + float(m.get("repairs", 0.0)),
		"pending_power": _pending(st, POWER), "pending_water": _pending(st, WATER),
		"broken": segments(gs, POWER).filter(func(s): return is_broken(s)).size(),
	}


static func _pending(st: Dictionary, layer: String) -> float:
	var t := 0.0
	for k in st["bills"][layer]:
		t += float(st["bills"][layer][k].get("own", 0.0))
	return t
