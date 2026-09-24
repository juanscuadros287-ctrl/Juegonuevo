extends Node
## Guardado y carga de partidas en user://saves/*.sav (formato binario de Godot:
## conserva los números exactos, así una partida cargada continúa idéntica).
## Lee también partidas antiguas en .json.

const SAVE_DIR := "user://saves/"
const AUTOSAVE_SLOT := "autoguardado"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	EventBus.year_passed.connect(func(_y): autosave())
	EventBus.jump_finished.connect(func(_r): autosave())


func autosave() -> void:
	if GameState.running and bool(GameData.game.get("autosave_yearly", true)):
		save_game(AUTOSAVE_SLOT)


func sanitize(slot: String) -> String:
	var out := ""
	for ch in slot.strip_edges().to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_" or ch == "-":
			out += ch
		elif ch == " ":
			out += "_"
	return out if out != "" else "partida"


func slot_path(slot: String) -> String:
	return SAVE_DIR + sanitize(slot) + ".sav"


func _legacy_path(slot: String) -> String:
	return SAVE_DIR + sanitize(slot) + ".json"


func save_game(slot: String) -> bool:
	var data := {
		"version": GameState.SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"summary": {
			"town": GameState.settings.get("town_name", ""),
			"date": TimeManager.date_string(false),
			"population": GameState.citizens.size(),
			"money": GameState.money,
		},
		"time": TimeManager.to_dict(),
		"state": GameState.to_dict(),
	}
	var f := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if f == null:
		push_error("No se pudo guardar: %s" % error_string(FileAccess.get_open_error()))
		return false
	f.store_var(data)
	f.close()
	return true


func _read(slot: String) -> Dictionary:
	var path := slot_path(slot)
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			return {}
		var v = f.get_var()
		return v if v is Dictionary else {}
	if FileAccess.file_exists(_legacy_path(slot)):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(_legacy_path(slot)))
		return parsed if parsed is Dictionary else {}
	return {}


func load_game(slot: String) -> bool:
	var data := _read(slot)
	if data.is_empty() or not data.has("state"):
		return false
	GameState.load_dict(data["state"])
	TimeManager.load_dict(data.get("time", {}))
	return true


## Lista de partidas: [{slot, saved_at, summary}] ordenadas de más reciente a más antigua.
func list_saves() -> Array:
	var out := []
	var seen := {}
	for file in DirAccess.get_files_at(SAVE_DIR):
		if not (file.ends_with(".sav") or file.ends_with(".json")):
			continue
		var slot := file.get_basename()
		if seen.has(slot):
			continue
		seen[slot] = true
		var data := _read(slot)
		if data.is_empty():
			continue
		out.append({"slot": slot, "saved_at": str(data.get("saved_at", "")), "summary": data.get("summary", {})})
	out.sort_custom(func(a, b): return a["saved_at"] > b["saved_at"])
	return out


func delete_save(slot: String) -> void:
	for path in [slot_path(slot), _legacy_path(slot)]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
