extends Node
## Guardado de partidas: 5 ranuras (slots) con autoguardado, escritura atómica, copias de respaldo
## rotativas y migraciones entre versiones (ver docs/GUARDADO.md y save_migrations.gd).
##
## Archivos (en user://, que las actualizaciones del juego nunca tocan; en Mac:
## ~/Library/Application Support/Dinastía/):
##   slots/slot_N.sav          partida de la ranura N (1..5)
##   slots/slot_N.sav.bak1/2   copias anteriores (la .bak1 es la más reciente)
##   slots/slot_N.sav.tmp      escritura en curso (se renombra al terminar)
##   slots/slot_N.vV.backup    copia intacta antes de migrar una partida de la versión V
##   slots/slot_N.sav.damaged  partida principal que no se pudo leer (nunca se borra sola)
##   slots/slots.cfg           nombres de ranura, última partida y opciones de autoguardado
##   saves/*.sav|*.json        partidas del sistema anterior (nombres libres); se importan a ranuras
##
## Formato del archivo (v8): store_var(cabecera) + tamaño (u32) + cuerpo serializado.
##   cabecera = {magic, format_version, game_version, saved_at, meta:{...}, body_size, body_sha256}
##   cuerpo   = {state: GameState.to_dict(), time: TimeManager.to_dict()}
## Leer solo la cabecera basta para listar las ranuras (con su miniatura) sin cargar la partida.
## Los archivos antiguos (un solo store_var {version, summary, time, state} o JSON) también se leen.

signal saved(slot: int, ok: bool, reason: String)

const SLOT_COUNT := 5
const MAGIC := "DINASTIA"
const SAVE_DIR := "user://saves/"          # partidas con nombre libre (sistema anterior y pruebas)
const AUTOSAVE_SLOT := "autoguardado"
const BACKUPS := 2
const THUMB_SIZE := Vector2i(320, 180)
const MONTH_SAVE_MIN_GAP := 20.0          # s reales entre autoguardados por cambio de mes
const DEFAULT_AUTOSAVE_MIN := 3.0

var slots_dir := "user://slots/"
var legacy_dir := SAVE_DIR
## Ranura de la partida en curso (0 = sin ranura: pruebas o partida sin guardar).
var active_slot := 0
## Tiempo jugado (s reales) de la partida en curso; se guarda en la cabecera.
var play_seconds := 0.0
## Última miniatura capturada (PNG).
var thumbnail_png := PackedByteArray()
## Hora (unix) del último guardado correcto en esta sesión.
var last_saved_unix := 0.0
var last_error := ""
## Aviso para mostrar al entrar al juego (p. ej., "se cargó la copia de respaldo").
var pending_notice := ""

var _since_save := 0.0
var _month_pending := false
var _saving := false
var _save_soon := -1.0
var _cfg := ConfigFile.new()
var _cfg_loaded_from := ""


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	DirAccess.make_dir_recursive_absolute(slots_dir)
	get_tree().set_auto_accept_quit(false)
	EventBus.day_passed.connect(_on_day_passed)
	EventBus.jump_finished.connect(func(_r): _month_pending = true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game()


## Guarda (si hay partida en una ranura) y cierra el juego. Cerrar la ventana y Cmd+Q llegan aquí.
func quit_game() -> void:
	if active_slot > 0 and GameState.running and _in_game():
		save_slot(active_slot, "salir")
	get_tree().quit()


func _process(delta: float) -> void:
	if not _in_game():
		return
	play_seconds += delta
	autosave_tick(delta)


func _in_game() -> bool:
	var sc := get_tree().current_scene
	return sc != null and sc.scene_file_path == "res://scenes/main.tscn"


func _on_day_passed() -> void:
	if active_slot > 0 and not TimeManager.jumping and int(TimeManager.month_day()[1]) == 1:
		_month_pending = true


## Autoguardado: cada N minutos reales y al empezar cada mes (con un mínimo de separación).
## Lo llama _process durante la partida; las pruebas lo llaman directamente.
func autosave_tick(delta: float) -> void:
	_since_save += delta
	if active_slot <= 0 or not GameState.running or TimeManager.jumping or _saving:
		return
	if _save_soon >= 0.0:
		_save_soon -= delta
		if _save_soon < 0.0:
			request_save("inicio")
			return
	var every := autosave_minutes() * 60.0
	if (every > 0.0 and _since_save >= every) or (_month_pending and _since_save >= MONTH_SAVE_MIN_GAP):
		var reason := "mes" if _month_pending and not (every > 0.0 and _since_save >= every) else "auto"
		_month_pending = false
		request_save(reason)


## Programa un guardado dentro de unos segundos (partida nueva: así se guarda con miniatura).
func save_soon(seconds: float) -> void:
	_save_soon = seconds


## Guarda en la ranura activa capturando antes la miniatura del mundo (sin la interfaz).
func request_save(reason := "manual") -> bool:
	if active_slot <= 0 or _saving:
		return false
	_saving = true
	await capture_thumbnail()
	_saving = false
	return save_slot(active_slot, reason)


## Captura una miniatura del mundo ocultando la interfaz un fotograma. Sin pantalla no hace nada.
func capture_thumbnail() -> void:
	if DisplayServer.get_name() == "headless" or not _in_game():
		return
	var sc := get_tree().current_scene
	var hud = sc.get("hud") if sc != null else null
	var hid := false
	if hud is CanvasLayer and (hud as CanvasLayer).visible:
		(hud as CanvasLayer).visible = false
		hid = true
	await RenderingServer.frame_post_draw
	var tex := get_viewport().get_texture()
	var img: Image = tex.get_image() if tex != null else null
	if hid and is_instance_valid(hud):
		(hud as CanvasLayer).visible = true
	if img == null or img.is_empty():
		return
	var w := img.get_width()
	var h := img.get_height()
	var target := float(THUMB_SIZE.x) / float(THUMB_SIZE.y)
	if float(w) / float(h) > target:
		var cw := int(h * target)
		img = img.get_region(Rect2i((w - cw) / 2, 0, cw, h))
	else:
		var ch := int(w / target)
		img = img.get_region(Rect2i(0, (h - ch) / 2, w, ch))
	img.resize(THUMB_SIZE.x, THUMB_SIZE.y, Image.INTERPOLATE_LANCZOS)
	thumbnail_png = img.save_png_to_buffer()


# --- Configuración (slots.cfg) -------------------------------------------------------------

func _cfg_path() -> String:
	return slots_dir + "slots.cfg"


func _config() -> ConfigFile:
	if _cfg_loaded_from != _cfg_path():
		_cfg = ConfigFile.new()
		_cfg.load(_cfg_path())
		_cfg_loaded_from = _cfg_path()
	return _cfg


func _save_config() -> void:
	DirAccess.make_dir_recursive_absolute(slots_dir)
	_config().save(_cfg_path())


func autosave_minutes() -> float:
	return float(_config().get_value("options", "autosave_minutes", DEFAULT_AUTOSAVE_MIN))


## 0 = solo al cambiar de mes y al salir.
func set_autosave_minutes(m: float) -> void:
	_config().set_value("options", "autosave_minutes", maxf(0.0, m))
	_save_config()


func last_slot() -> int:
	var s := int(_config().get_value("slots", "last", 0))
	return s if s >= 1 and s <= SLOT_COUNT and slot_exists(s) else 0


func slot_name(slot: int) -> String:
	return str(_config().get_value("slots", "name_%d" % slot, ""))


func rename_slot(slot: int, new_name: String) -> void:
	_config().set_value("slots", "name_%d" % slot, new_name.strip_edges().left(48))
	_save_config()


## Cambia la carpeta de ranuras y de partidas antiguas (pruebas).
func use_dirs(slots: String, legacy: String) -> void:
	slots_dir = slots if slots.ends_with("/") else slots + "/"
	legacy_dir = legacy if legacy.ends_with("/") else legacy + "/"
	DirAccess.make_dir_recursive_absolute(slots_dir)
	DirAccess.make_dir_recursive_absolute(legacy_dir)
	_cfg_loaded_from = ""


# --- Ranuras ----------------------------------------------------------------------------------

func slot_file(slot: int) -> String:
	return slots_dir + "slot_%d.sav" % slot


func slot_exists(slot: int) -> bool:
	var p := slot_file(slot)
	return FileAccess.file_exists(p) or FileAccess.file_exists(p + ".bak1") or FileAccess.file_exists(p + ".tmp") or FileAccess.file_exists(p + ".damaged")


func first_empty_slot() -> int:
	for i in range(1, SLOT_COUNT + 1):
		if not slot_exists(i):
			return i
	return 0


## Archivos candidatos de una ranura, del más fiable al menos: principal, escritura sin terminar
## (solo si está completa), copias.
func _candidates(slot: int) -> Array:
	var p := slot_file(slot)
	return [p, p + ".tmp", p + ".bak1", p + ".bak2"]


## Información de una ranura para el menú: {slot, status: empty|ok|damaged, name, meta, saved_at,
## format_version, game_version, error, source, backups: [{file, saved_at}]}.
func slot_info(slot: int) -> Dictionary:
	var info := {"slot": slot, "status": "empty", "name": slot_name(slot), "meta": {}, "saved_at": "", "error": "", "backups": [], "source": ""}
	if not slot_exists(slot):
		return info
	var main := read_header(slot_file(slot))
	for f in [slot_file(slot) + ".bak1", slot_file(slot) + ".bak2"]:
		var h := read_header(f)
		if h["ok"]:
			(info["backups"] as Array).append({"file": f, "saved_at": str(h["data"].get("saved_at", ""))})
	if main["ok"]:
		info["status"] = "ok"
		_fill_info(info, main["data"])
		info["source"] = slot_file(slot)
		return info
	info["status"] = "damaged"
	info["error"] = str(main["error"]) if FileAccess.file_exists(slot_file(slot)) else "Falta el archivo principal"
	# Muestra los datos de la mejor copia para que se reconozca la partida.
	for f in _candidates(slot).slice(1):
		var h := read_header(f)
		if h["ok"]:
			_fill_info(info, h["data"])
			info["source"] = f
			break
	return info


func _fill_info(info: Dictionary, header: Dictionary) -> void:
	info["meta"] = header.get("meta", {}) if header.get("meta", {}) is Dictionary else {}
	info["saved_at"] = str(header.get("saved_at", ""))
	info["format_version"] = SaveMigrations.version_of(header)
	info["game_version"] = str(header.get("game_version", ""))


func list_slots() -> Array:
	var out := []
	for i in range(1, SLOT_COUNT + 1):
		out.append(slot_info(i))
	return out


## Empieza una partida nueva en una ranura (llamar antes de GameState.new_game).
func begin_slot(slot: int) -> void:
	active_slot = slot
	play_seconds = 0.0
	_since_save = 0.0
	_month_pending = false
	_save_soon = -1.0
	thumbnail_png = PackedByteArray()
	if slot > 0:
		_config().set_value("slots", "last", slot)
		_save_config()


## Guarda la partida en curso en la ranura (escritura atómica con copias rotativas).
func save_slot(slot: int, reason := "manual") -> bool:
	if slot < 1 or slot > SLOT_COUNT:
		return false
	active_slot = slot
	var ok := write_save(slot_file(slot), build_save(slot))
	if ok:
		_since_save = 0.0
		last_saved_unix = Time.get_unix_time_from_system()
		_config().set_value("slots", "last", slot)
		_save_config()
	saved.emit(slot, ok, reason)
	return ok


## Carga la ranura. Si la principal falla, prueba la escritura sin terminar y las copias.
## Devuelve {ok, error, source, used_backup, from_version}. Nunca borra ni modifica la partida
## (salvo la copia .vN.backup antes de migrar).
func load_slot(slot: int) -> Dictionary:
	var errors := []
	for f in _candidates(slot):
		if not FileAccess.file_exists(f):
			continue
		var r := load_file(f, slot)
		if r["ok"]:
			r["used_backup"] = f != slot_file(slot)
			if r["used_backup"]:
				r["error"] = "; ".join(errors)
			return r
		errors.append("%s: %s" % [f.get_file(), r["error"]])
	return {"ok": false, "error": "; ".join(errors) if not errors.is_empty() else "Ranura vacía", "source": "", "used_backup": false}


## Carga un archivo concreto (principal o copia) de una ranura.
func load_file(path: String, slot := 0) -> Dictionary:
	var r := read_file(path)
	if not r["ok"]:
		return {"ok": false, "error": r["error"], "source": path}
	var data: Dictionary = r["data"]
	var from := SaveMigrations.version_of(data)
	if from < SaveMigrations.CURRENT and slot > 0:
		_backup_before_migration(path, slot, from)
	var res := apply_save(data)
	res["source"] = path
	res["from_version"] = from
	if res["ok"] and slot > 0:
		active_slot = slot
		_config().set_value("slots", "last", slot)
		_save_config()
	return res


func _backup_before_migration(path: String, slot: int, from: int) -> void:
	var bk := slots_dir + "slot_%d.v%d.backup" % [slot, from]
	if not FileAccess.file_exists(bk):
		DirAccess.copy_absolute(path, bk)


## Migra y aplica una partida leída (cabecera + state + time) al juego.
func apply_save(data: Dictionary) -> Dictionary:
	var m := SaveMigrations.migrate(data)
	if not m["ok"]:
		return {"ok": false, "error": m["error"]}
	var d: Dictionary = m["data"]
	if not (d.get("state") is Dictionary) or (d["state"] as Dictionary).is_empty():
		return {"ok": false, "error": "La partida no tiene estado"}
	GameState.load_dict(d["state"])
	TimeManager.load_dict(d.get("time", {}) if d.get("time", {}) is Dictionary else {})
	var meta: Dictionary = d.get("meta", {}) if d.get("meta", {}) is Dictionary else {}
	play_seconds = float(meta.get("play_seconds", 0.0))
	var th = meta.get("thumbnail", PackedByteArray())
	thumbnail_png = th if th is PackedByteArray else PackedByteArray()
	_since_save = 0.0
	_month_pending = false
	return {"ok": true, "error": "", "future": SaveMigrations.version_of(data) > SaveMigrations.CURRENT}


## Borra una ranura (principal, copias y respaldos de migración).
func delete_slot(slot: int) -> void:
	var p := slot_file(slot)
	for f in [p, p + ".bak1", p + ".bak2", p + ".tmp", p + ".damaged"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	for f in DirAccess.get_files_at(slots_dir):
		if f.begins_with("slot_%d.v" % slot) and f.ends_with(".backup"):
			DirAccess.remove_absolute(slots_dir + f)
	var cfg := _config()
	if cfg.has_section_key("slots", "name_%d" % slot):
		cfg.erase_section_key("slots", "name_%d" % slot)
	if int(cfg.get_value("slots", "last", 0)) == slot:
		cfg.set_value("slots", "last", 0)
	_save_config()
	if active_slot == slot:
		active_slot = 0


# --- Construcción, escritura y lectura ------------------------------------------------------

func game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0"))


func build_meta() -> Dictionary:
	var gs := GameState
	var cid := str(gs.settings.get("country_id", ""))
	var country := ""
	if cid != "":
		country = str(MapSim.country_def(cid).get("label", cid))
	return {
		"town": str(gs.settings.get("town_name", "")),
		"player": gs.player_name(),
		"country_id": cid,
		"country": country,
		"date": TimeManager.date_string(false),
		"year": TimeManager.year(),
		"money": gs.money,
		"population": gs.citizens.size(),
		"play_seconds": play_seconds,
		"difficulty": str(gs.settings.get("difficulty", "")),
		"thumbnail": thumbnail_png,
	}


## Partida completa en memoria: cabecera + estado + tiempo.
func build_save(slot := 0) -> Dictionary:
	var meta := build_meta()
	if slot > 0:
		meta["title"] = slot_name(slot)
	return {
		"magic": MAGIC,
		"format_version": SaveMigrations.CURRENT,
		"game_version": game_version(),
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"meta": meta,
		"state": GameState.to_dict(),
		"time": TimeManager.to_dict(),
	}


## Escritura atómica: .tmp → verificación → rotación de copias → renombrar a la principal.
func write_save(path: String, data: Dictionary, rotate := true) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var header := {}
	for k in data:
		if k != "state" and k != "time":
			header[k] = data[k]
	var body := var_to_bytes({"state": data.get("state", {}), "time": data.get("time", {})})
	header["magic"] = MAGIC
	if not header.has("format_version"):
		header["format_version"] = SaveMigrations.CURRENT
	header["body_size"] = body.size()
	header["body_sha256"] = _sha256(body)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		last_error = "No se pudo escribir %s: %s" % [tmp, error_string(FileAccess.get_open_error())]
		push_error(last_error)
		return false
	f.store_var(header)
	f.store_32(body.size())
	f.store_buffer(body)
	f.flush()
	var err := f.get_error()
	f.close()
	if err != OK and err != ERR_FILE_EOF:
		last_error = "Error al escribir: %s" % error_string(err)
		return false
	var check := read_header(tmp)
	if not check["ok"]:
		last_error = "La verificación del guardado falló"
		DirAccess.remove_absolute(tmp)
		return false
	if rotate and FileAccess.file_exists(path):
		if read_header(path)["ok"]:
			for i in range(BACKUPS, 1, -1):
				var older := "%s.bak%d" % [path, i - 1]
				var newer := "%s.bak%d" % [path, i]
				if FileAccess.file_exists(older):
					if FileAccess.file_exists(newer):
						DirAccess.remove_absolute(newer)
					DirAccess.rename_absolute(older, newer)
			if FileAccess.file_exists(path + ".bak1"):
				DirAccess.remove_absolute(path + ".bak1")
			DirAccess.rename_absolute(path, path + ".bak1")
		else:
			# La principal está dañada: se aparta intacta (no desplaza las copias buenas).
			if FileAccess.file_exists(path + ".damaged"):
				DirAccess.remove_absolute(path + ".damaged")
			DirAccess.rename_absolute(path, path + ".damaged")
	elif FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var rn := DirAccess.rename_absolute(tmp, path)
	if rn != OK:
		last_error = "No se pudo renombrar el guardado: %s" % error_string(rn)
		return false
	last_error = ""
	return true


func _sha256(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


## get_var con comprobación de longitud (un archivo dañado no provoca reservas enormes).
func _safe_get_var(f: FileAccess):
	var pos := f.get_position()
	if f.get_length() - pos < 8:
		return null
	var n := f.get_32()
	if n == 0 or n > f.get_length() - pos - 4:
		return null
	f.seek(pos)
	return f.get_var(false)


## Lee solo la cabecera (menú de ranuras). {ok, data, error}.
func read_header(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "data": {}, "error": "No existe"}
	if path.ends_with(".json"):
		return _read_json(path)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "data": {}, "error": error_string(FileAccess.get_open_error())}
	var v = _safe_get_var(f)
	if not (v is Dictionary):
		return {"ok": false, "data": {}, "error": "Archivo dañado o de otro formato"}
	var d: Dictionary = v
	if d.has("state"):
		# Formato antiguo: todo en un solo diccionario.
		return {"ok": true, "data": _legacy_header(d), "error": ""}
	if str(d.get("magic", "")) != MAGIC or not d.has("format_version"):
		return {"ok": false, "data": {}, "error": "Cabecera no reconocida"}
	var remaining := f.get_length() - f.get_position()
	if remaining < 4 + int(d.get("body_size", 0)):
		return {"ok": false, "data": {}, "error": "Archivo incompleto (guardado interrumpido)"}
	return {"ok": true, "data": d, "error": ""}


func _legacy_header(d: Dictionary) -> Dictionary:
	var h := {}
	for k in d:
		if k != "state" and k != "time":
			h[k] = d[k]
	if not h.has("meta"):
		var sm: Dictionary = d.get("summary", {}) if d.get("summary", {}) is Dictionary else {}
		var st: Dictionary = d.get("state", {}) if d.get("state") is Dictionary else {}
		var se: Dictionary = st.get("settings", {}) if st.get("settings") is Dictionary else {}
		h["meta"] = {"town": sm.get("town", se.get("town_name", "")), "date": sm.get("date", ""),
			"population": sm.get("population", 0), "money": sm.get("money", 0.0),
			"player": ("%s %s" % [se.get("player_name", ""), se.get("player_surname", "")]).strip_edges(),
			"country_id": str(se.get("country_id", ""))}
	return h


func _read_json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary) or not (parsed as Dictionary).has("state"):
		return {"ok": false, "data": {}, "error": "JSON no válido"}
	return {"ok": true, "data": parsed, "error": "", "legacy": true}


## Lee la partida completa (cabecera + state + time). {ok, data, error}.
func read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "data": {}, "error": "No existe"}
	if path.ends_with(".json"):
		return _read_json(path)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "data": {}, "error": error_string(FileAccess.get_open_error())}
	var v = _safe_get_var(f)
	if not (v is Dictionary):
		return {"ok": false, "data": {}, "error": "Archivo dañado o de otro formato"}
	var d: Dictionary = v
	if d.has("state"):
		return {"ok": true, "data": d, "error": ""}
	if str(d.get("magic", "")) != MAGIC:
		return {"ok": false, "data": {}, "error": "Cabecera no reconocida"}
	if f.get_length() - f.get_position() < 4:
		return {"ok": false, "data": {}, "error": "Archivo incompleto"}
	var n := f.get_32()
	if n != int(d.get("body_size", -1)) or n > f.get_length() - f.get_position():
		return {"ok": false, "data": {}, "error": "Archivo incompleto (guardado interrumpido)"}
	var body := f.get_buffer(n)
	if d.has("body_sha256") and _sha256(body) != str(d["body_sha256"]):
		return {"ok": false, "data": {}, "error": "Datos dañados (la suma de verificación no coincide)"}
	var b = bytes_to_var(body)
	if not (b is Dictionary) or not (b as Dictionary).has("state"):
		return {"ok": false, "data": {}, "error": "Cuerpo de la partida no válido"}
	var out := d.duplicate()
	out["state"] = b["state"]
	out["time"] = b.get("time", {})
	return {"ok": true, "data": out, "error": ""}


# --- Partidas con nombre libre (sistema anterior; lo usan las pruebas) ----------------------

func sanitize(slot: String) -> String:
	var out := ""
	for ch in slot.strip_edges().to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_" or ch == "-":
			out += ch
		elif ch == " ":
			out += "_"
	return out if out != "" else "partida"


func slot_path(slot: String) -> String:
	return legacy_dir + sanitize(slot) + ".sav"


func _legacy_path(slot: String) -> String:
	return legacy_dir + sanitize(slot) + ".json"


## Guarda con nombre libre en saves/ (mismo formato que las ranuras, sin copias rotativas).
func save_game(slot: String) -> bool:
	return write_save(slot_path(slot), build_save(), false)


func _read(slot: String) -> Dictionary:
	for p in [slot_path(slot), _legacy_path(slot)]:
		if FileAccess.file_exists(p):
			var r := read_file(p)
			return r["data"] if r["ok"] else {}
	return {}


func load_game(slot: String) -> bool:
	var data := _read(slot)
	if data.is_empty():
		return false
	return bool(apply_save(data)["ok"])


## Lista de partidas con nombre libre: [{slot, saved_at, summary, path}] (más reciente primero).
func list_saves(dir := "") -> Array:
	if dir == "":
		dir = legacy_dir
	var out := []
	var seen := {}
	for file in DirAccess.get_files_at(dir):
		if not (file.ends_with(".sav") or file.ends_with(".json")):
			continue
		var name := file.get_basename()
		if seen.has(name):
			continue
		seen[name] = true
		var h := read_header(dir + file)
		if not h["ok"]:
			continue
		var hd: Dictionary = h["data"]
		var meta: Dictionary = hd.get("meta", {}) if hd.get("meta", {}) is Dictionary else {}
		var summary: Dictionary = hd.get("summary", {}) if hd.get("summary", {}) is Dictionary else {}
		if summary.is_empty():
			summary = {"town": meta.get("town", ""), "date": meta.get("date", ""), "population": meta.get("population", 0), "money": meta.get("money", 0.0)}
		out.append({"slot": name, "saved_at": str(hd.get("saved_at", "")), "summary": summary, "meta": meta, "path": dir + file})
	out.sort_custom(func(a, b): return a["saved_at"] > b["saved_at"])
	return out


func delete_save(slot: String) -> void:
	for path in [slot_path(slot), _legacy_path(slot)]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


# --- Importar partidas antiguas a ranuras ---------------------------------------------------

## Carpetas con partidas del sistema anterior: user://saves/ y, si existe, la carpeta que usaban
## las versiones sin nombre de carpeta propio (<datos del sistema>/Godot/app_userdata/Dinastía/saves).
func legacy_dirs() -> Array:
	var dirs := [legacy_dir]
	if legacy_dir == SAVE_DIR:
		var old := OS.get_data_dir().path_join("Godot/app_userdata").path_join(str(ProjectSettings.get_setting("application/config/name", "Dinastía"))).path_join("saves") + "/"
		if DirAccess.dir_exists_absolute(old) and ProjectSettings.globalize_path(SAVE_DIR) != old:
			dirs.append(old)
	return dirs


## Partidas del sistema anterior (saves/*.sav|*.json, incluido "autoguardado"), sin las de pruebas,
## que aún no se han importado. Más recientes primero.
func list_legacy() -> Array:
	var imported: Array = _config().get_value("import", "done", [])
	var out := []
	var seen := {}
	for dir in legacy_dirs():
		for s in list_saves(dir):
			var n := str(s["slot"])
			if n.begins_with("test_") or n.begins_with("prueba_") or imported.has(n) or seen.has(n):
				continue
			seen[n] = true
			out.append(s)
	out.sort_custom(func(a, b): return a["saved_at"] > b["saved_at"])
	return out


## Copia una partida antigua a una ranura (el archivo original queda intacto en saves/).
func import_legacy(name: String, slot: int) -> bool:
	var src := ""
	for dir in legacy_dirs():
		for ext in [".sav", ".json"]:
			var p: String = dir + sanitize(name) + ext
			if src == "" and FileAccess.file_exists(p):
				src = p
	if src == "" or slot < 1 or slot > SLOT_COUNT:
		return false
	var r := read_file(src)
	if not r["ok"]:
		last_error = str(r["error"])
		return false
	var from := SaveMigrations.version_of(r["data"])
	var m := SaveMigrations.migrate(r["data"])
	if not m["ok"]:
		last_error = str(m["error"])
		return false
	var data: Dictionary = m["data"]
	if FileAccess.file_exists(slot_file(slot)):
		return false   # nunca sobrescribe una ranura ocupada
	var bk := slots_dir + "slot_%d.v%d.backup" % [slot, from]
	if from < SaveMigrations.CURRENT and not FileAccess.file_exists(bk):
		DirAccess.copy_absolute(src, bk)
	if not write_save(slot_file(slot), data, false):
		return false
	var cfg := _config()
	var imported: Array = cfg.get_value("import", "done", [])
	if not imported.has(name):
		imported.append(name)
	cfg.set_value("import", "done", imported)
	cfg.set_value("slots", "name_%d" % slot, name.replace("_", " ").capitalize())
	_save_config()
	return true


## Primera vez: importa hasta 5 partidas antiguas (las más recientes) a las ranuras libres.
## Devuelve cuántas importó. Las demás quedan en list_legacy() para importarlas a mano.
func auto_import_legacy() -> int:
	var cfg := _config()
	if bool(cfg.get_value("import", "auto_done", false)):
		return 0
	var n := 0
	for s in list_legacy():
		var slot := first_empty_slot()
		if slot == 0:
			break
		if import_legacy(str(s["slot"]), slot):
			n += 1
	cfg.set_value("import", "auto_done", true)
	_save_config()
	return n
