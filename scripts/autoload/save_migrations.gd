class_name SaveMigrations
extends RefCounted
## Migraciones de partidas guardadas entre versiones del formato.
##
## Cada vez que cambia el formato de guardado (nuevas claves obligatorias, claves renombradas,
## estructuras que cambian de forma):
##   1. Sube CURRENT en 1 (y GameState.SAVE_VERSION al mismo número).
##   2. Escribe aquí `static func migrate_vN_to_vN+1(d: Dictionary) -> Dictionary` que reciba la
##      partida completa (cabecera + "state" + "time") en la versión N y la devuelva en la N+1.
##   3. Añade un caso a tests/test_guardado.gd con un diccionario mínimo de la versión N.
## Ver docs/GUARDADO.md. Las migraciones NUNCA borran datos del jugador: si una clave deja de
## usarse, se deja (load_dict ignora lo que no conoce).
##
## Las claves que solo necesitan un valor por defecto NO requieren migración: GameState.load_dict
## y los init_state(...) de cada sistema rellenan lo que falte. La migración es para cambios de
## forma o de significado.

## Versión actual del formato de archivo (cabecera + estado). Igual a GameState.SAVE_VERSION.
const CURRENT := 8


## Versión de una partida leída (cabecera nueva "format_version", antigua "version"; sin nada = 1).
static func version_of(d: Dictionary) -> int:
	if d.has("format_version"):
		return int(d["format_version"])
	if d.has("version"):
		return int(d["version"])
	return 1


## Lleva la partida a CURRENT aplicando las migraciones en orden. Devuelve {ok, data, from, error}.
## Una partida "del futuro" (versión mayor) se deja igual: load_dict ignora lo que no conoce.
static func migrate(d: Dictionary) -> Dictionary:
	var from := version_of(d)
	var data := d
	var v := from
	var runner := SaveMigrations.new()
	while v < CURRENT:
		var fn := "migrate_v%d_to_v%d" % [v, v + 1]
		if not runner.has_method(fn):
			return {"ok": false, "data": data, "from": from, "error": "Falta la migración %s" % fn}
		var out = runner.call(fn, data)
		if not (out is Dictionary):
			return {"ok": false, "data": data, "from": from, "error": "La migración %s falló" % fn}
		data = out
		v += 1
		data["format_version"] = v
	return {"ok": true, "data": data, "from": from, "error": ""}


# --- Migraciones (en orden) -------------------------------------------------------------------
# v1-v6: partidas de las fases 1 a 9 (JSON y luego binario). Su forma es la misma que la v7
# ({version, saved_at, summary, time, state}); lo que les falta (jugador ciudadano, redes, mapa,
# países...) lo completa GameState.load_dict con valores por defecto, así que solo suben el número.

static func migrate_v1_to_v2(d: Dictionary) -> Dictionary:
	# Fase 1 → 2: el jugador pasa a ser un ciudadano (PlayerSim.migrate_v1_player en load_dict).
	return d


static func migrate_v2_to_v3(d: Dictionary) -> Dictionary:
	return d


static func migrate_v3_to_v4(d: Dictionary) -> Dictionary:
	return d


static func migrate_v4_to_v5(d: Dictionary) -> Dictionary:
	return d


static func migrate_v5_to_v6(d: Dictionary) -> Dictionary:
	return d


static func migrate_v6_to_v7(d: Dictionary) -> Dictionary:
	return d


## v7 → v8: cabecera nueva {format_version, game_version, saved_at, meta, state, time}.
## "summary" pasa a "meta" (con personaje, país y tiempo jugado); el estado no cambia.
static func migrate_v7_to_v8(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		if k != "version" and k != "summary":
			out[k] = d[k]
	var state: Dictionary = d.get("state", {}) if d.get("state", {}) is Dictionary else {}
	var settings: Dictionary = state.get("settings", {}) if state.get("settings", {}) is Dictionary else {}
	var sm: Dictionary = d.get("summary", {}) if d.get("summary", {}) is Dictionary else {}
	var meta: Dictionary = d.get("meta", {}) if d.get("meta", {}) is Dictionary else {}
	meta["town"] = str(meta.get("town", sm.get("town", settings.get("town_name", ""))))
	meta["player"] = str(meta.get("player", "%s %s" % [settings.get("player_name", ""), settings.get("player_surname", "")])).strip_edges()
	meta["country_id"] = str(meta.get("country_id", settings.get("country_id", "")))
	meta["date"] = str(meta.get("date", sm.get("date", "")))
	meta["money"] = float(meta.get("money", sm.get("money", state.get("money", 0.0))))
	meta["population"] = int(meta.get("population", sm.get("population", (state.get("citizens", []) as Array).size() if state.get("citizens", []) is Array else 0)))
	meta["play_seconds"] = float(meta.get("play_seconds", 0.0))
	out["meta"] = meta
	out["game_version"] = str(d.get("game_version", "anterior a 0.2"))
	out["saved_at"] = str(d.get("saved_at", ""))
	if not out.has("state"):
		out["state"] = {}
	if not out.has("time"):
		out["time"] = {}
	return out
