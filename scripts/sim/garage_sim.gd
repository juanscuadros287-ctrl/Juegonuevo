class_name GarageSim
extends RefCounted
## Garajes conectados a su red (docs/RUTAS_BARCOS.md). Un garaje solo compra y despacha vehículos si
## está CONECTADO:
##   caballeriza          → junto a un camino o terreno transitable (su puerta en tierra firme)
##   depósito de camiones → tocando una carretera
##   terminal de buses    → tocando una carretera
##   cochera de tren      → con salida junto a la vía férrea
##   hangar               → junto a la pista de un aeropuerto tuyo
##   astillero            → tocando el agua
## La Central de transporte (cargadores) no necesita conexión.
## Partidas anteriores: los garajes ya construidos que no quedan conectados reciben "conexión
## provisional" (b["conn_legacy"]) para que la partida siga igual; se avisa al jugador.

const KINDS := {"caballeriza": "terreno", "deposito_camiones": "carretera", "empresa_buses": "carretera", "hangar": "pista",
		"astillero": "agua", "cochera_tren": "riel"}
const KIND_LABELS := {"terreno": "un camino o terreno firme", "carretera": "una carretera", "pista": "la pista de un aeropuerto",
		"agua": "el agua", "riel": "la vía férrea"}

static var _cache := {}


static func cfg() -> Dictionary:
	return GameData.extra("rutas").get("garage", {})


## Tipo de conexión que exige un edificio ("" = ninguna).
static func kind_of(type_id: String) -> String:
	var def := GameData.building_def(type_id)
	return str(def.get("garage_kind", KINDS.get(type_id, "")))


static func is_garage_type(type_id: String) -> bool:
	return kind_of(type_id) != ""


static func is_garage(b: Dictionary) -> bool:
	return is_garage_type(str(b.get("type", "")))


## Conexión de un garaje colocado en (x, z): {ok, kind, point (salida hacia la red), reason, text}.
static func connection(gs, type_id: String, x: float, z: float, level := 1, ignore_id := -1) -> Dictionary:
	var kind := kind_of(type_id)
	var c := Vector2(x, z)
	var fp := GameData.footprint(type_id, level)
	var out := {"ok": true, "kind": kind, "point": c, "reason": "", "text": ""}
	match kind:
		"carretera":
			var reach := fp * 0.5 + float(cfg().get("road_reach", 6.0))
			var best := Vector2.INF
			var bd := INF
			for r in RoadSim.roads(gs):
				var a := RoadSim.seg_a(r)
				var b := RoadSim.seg_b(r)
				var ab := b - a
				var t := clampf((c - a).dot(ab) / maxf(0.0001, ab.length_squared()), 0.0, 1.0)
				var q := a + ab * t
				if c.distance_to(q) < bd:
					bd = c.distance_to(q)
					best = q
			if bd <= reach:
				out["point"] = best
			else:
				out["ok"] = false
		"riel":
			var q := RailSim.nearest_point(gs, c)
			if q != Vector2.INF and c.distance_to(q) <= fp * 0.5 + float(cfg().get("rail_reach", 6.0)):
				out["point"] = q
			else:
				out["ok"] = false
		"pista":
			var best_gap := INF
			for b in AirSim.airports(gs):
				if int(b["id"]) == ignore_id:
					continue
				var bp := Vector2(float(b["x"]), float(b["z"]))
				var gap := WarehouseSim.edge_gap(c, fp * 0.5, bp, gs.footprint_of(b) * 0.5)
				if gap < best_gap:
					best_gap = gap
					out["point"] = bp
			out["ok"] = best_gap <= float(cfg().get("runway_gap", 16.0))
		"agua":
			var s := ShipSim.shore_point(gs, x, z, fp)
			out["ok"] = s != Vector2.INF
			if s != Vector2.INF:
				out["point"] = s
		"terreno":
			var door := c + Vector2(0, fp * 0.5 + 2.0)
			out["point"] = door
			out["ok"] = not ShipSim.is_water(gs, door) or not ShipSim.is_water(gs, c + Vector2(0, -fp * 0.5 - 2.0))
	var what: String = KIND_LABELS.get(kind, "")
	if kind == "":
		out["text"] = ""
	elif bool(out["ok"]):
		out["text"] = "Conectado a %s: los vehículos salen por ahí" % what
	else:
		out["reason"] = _reason(type_id, kind)
		out["text"] = out["reason"]
	return out


static func _reason(type_id: String, kind: String) -> String:
	var label := str(GameData.building_def(type_id).get("label", type_id))
	match kind:
		"carretera":
			return "%s sin conexión: debe tocar una carretera (a menos de %d m de su borde) para sacar vehículos" % [label, int(cfg().get("road_reach", 6.0))]
		"riel":
			return "%s sin conexión: su salida debe quedar junto a una vía férrea (traza una vía por puntos)" % label
		"pista":
			return "%s sin conexión: debe estar junto a la pista de un aeropuerto tuyo (a menos de %d m)" % [label, int(cfg().get("runway_gap", 16.0))]
		"agua":
			return "%s sin conexión: debe tocar el agua (costa, río o lago)" % label
		"terreno":
			return "%s sin conexión: su puerta queda en el agua" % label
	return ""


static func _key(gs, b: Dictionary) -> String:
	return "%d|%.1f|%.1f|%d|%d|%d|%d|%s" % [int(b["id"]), float(b["x"]), float(b["z"]), int(b.get("level", 1)), int(gs.logistics.get("road_version", 0)) + RoadSim.roads(gs).size(),
			RailSim.version(gs), gs.buildings.size(), MapSim.country_id(gs)]


## Conexión de un garaje ya construido (con memo).
static func connection_of(gs, b: Dictionary) -> Dictionary:
	if kind_of(str(b.get("type", ""))) in ["pista", "terreno", ""]:   # baratas y dependen del estado de otros edificios
		return connection(gs, str(b.get("type", "")), float(b["x"]), float(b["z"]), int(b.get("level", 1)), int(b["id"]))
	var k := _key(gs, b)
	if _cache.has(k):
		return _cache[k]
	var c := connection(gs, str(b["type"]), float(b["x"]), float(b["z"]), int(b.get("level", 1)), int(b["id"]))
	if _cache.size() > 256:
		_cache.clear()
	_cache[k] = c
	return c


## ¿Puede sacar vehículos? (los edificios sin requisito siempre; conexión provisional de partidas viejas).
static func linked(gs, b: Dictionary) -> bool:
	if b.is_empty() or not is_garage(b):
		return true
	if bool(b.get("conn_legacy", false)):
		return true
	return bool(connection_of(gs, b)["ok"])


static func disconnected_reason(gs, b: Dictionary) -> String:
	if linked(gs, b):
		return ""
	return str(connection_of(gs, b)["reason"])


## Punto por donde salen los vehículos (puerta hacia la carretera, la vía, el agua o la pista).
static func exit_point(gs, b: Dictionary) -> Vector2:
	var p := Vector2(float(b.get("x", 0.0)), float(b.get("z", 0.0)))
	if not is_garage(b):
		return p
	var c := connection_of(gs, b)
	return c["point"] if bool(c["ok"]) else p


## Texto para el panel del edificio.
static func status_text(gs, b: Dictionary) -> String:
	if not is_garage(b):
		return ""
	var c := connection_of(gs, b)
	if bool(c["ok"]):
		return "[color=#6c6]%s[/color]" % str(c["text"])
	if bool(b.get("conn_legacy", false)):
		return "[color=#e9b949]Conexión provisional (partida anterior): %s[/color]" % str(c["reason"])
	return "[color=#e66]%s. Sin conexión no puede comprar ni despachar vehículos.[/color]" % str(c["reason"])


## Migración: partidas anteriores → los garajes que no quedan conectados siguen funcionando.
static func grandfather(gs) -> int:
	var n := 0
	for b in gs.buildings:
		if is_garage(b) and gs.owned_by_player(b) and not bool(connection_of(gs, b)["ok"]):
			b["conn_legacy"] = true
			n += 1
	return n


# --- Vagones de tren ----------------------------------------------------------------------------------

static func wagon_price(gs, mode: String) -> float:
	return float(LogisticsSim.mode_def(mode).get("wagon_price", 0.0)) * gs.price_mult()


static func add_wagon_block_reason(gs, vid: int) -> String:
	var v := LogisticsSim.get_vehicle(gs, vid)
	if v.is_empty():
		return "Ese tren no existe"
	var md := LogisticsSim.mode_def(str(v["mode"]))
	if not md.has("wagon_capacity"):
		return "Solo los trenes llevan vagones"
	if int(v.get("wagons", md.get("wagons_default", 0))) >= int(md.get("wagons_max", 0)):
		return "Máximo %d vagones por locomotora" % int(md.get("wagons_max", 0))
	if gs.money < wagon_price(gs, str(v["mode"])):
		return "Dinero insuficiente (%s)" % Fmt.money(wagon_price(gs, str(v["mode"])))
	return ""


static func add_wagon(gs, vid: int) -> String:
	var why := add_wagon_block_reason(gs, vid)
	if why != "":
		return why
	var v := LogisticsSim.get_vehicle(gs, vid)
	var md := LogisticsSim.mode_def(str(v["mode"]))
	var st: Dictionary = gs.get_building(int(v["base"]))
	if st.is_empty():
		gs.add_money(-wagon_price(gs, str(v["mode"])))
	else:
		BusinessSim.pay(gs, st, wagon_price(gs, str(v["mode"])), "obras")
	v["wagons"] = int(v.get("wagons", md.get("wagons_default", 0))) + 1
	return ""
