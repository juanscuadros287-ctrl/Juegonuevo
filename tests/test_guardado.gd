extends Node
## Pruebas del guardado: 5 ranuras, autoguardado, escritura atómica y copias, migraciones,
## tolerancia a claves del futuro, importación de partidas antiguas e ida y vuelta.
## godot --headless res://tests/test_guardado.tscn
## Usa una carpeta propia en user:// (no toca las ranuras reales ni user://saves).

var failures := 0
var base := ""
var _saved_reasons: Array = []


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func _ready() -> void:
	print("== Dinastía: pruebas de guardado ==")
	base = "user://test_guardado_%d/" % OS.get_process_id()
	SaveManager.use_dirs(base + "slots", base + "saves")
	SaveManager.saved.connect(func(_s, ok, reason): if ok: _saved_reasons.append(reason))
	check(GameState.SAVE_VERSION == SaveMigrations.CURRENT, "GameState.SAVE_VERSION = SaveMigrations.CURRENT (%d)" % SaveMigrations.CURRENT)
	_test_slots()
	_test_autosave()
	_test_atomic_and_recovery()
	_test_old_format_migration()
	_test_future_keys()
	_test_legacy_import()
	_test_round_trip()
	await _test_ui()
	_cleanup()
	SaveManager.use_dirs("user://slots", SaveManager.SAVE_DIR)
	SaveManager.active_slot = 0
	print("== %s (%d fallos) ==" % ["TODO OK" if failures == 0 else "CON FALLOS", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _new(seed := 5, town := "Pueblo Prueba") -> void:
	GameState.new_game({"seed": seed, "difficulty": "normal", "town_name": town, "player_name": "Ana", "player_surname": "Ruiz"})


func _clear_slots() -> void:
	for i in range(1, SaveManager.SLOT_COUNT + 1):
		SaveManager.delete_slot(i)


func _rm_tree(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + f)
	for d in DirAccess.get_directories_at(dir):
		_rm_tree(dir + d + "/")
	DirAccess.remove_absolute(dir)


func _cleanup() -> void:
	_rm_tree(base)


func _write_var(path: String, v) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_var(v)
	f.close()


# --- 5 ranuras: crear, listar, renombrar, borrar ------------------------------------------------

func _test_slots() -> void:
	_clear_slots()
	var ls := SaveManager.list_slots()
	check(ls.size() == 5 and ls.all(func(s): return s["status"] == "empty"), "5 ranuras vacías al empezar")
	check(SaveManager.first_empty_slot() == 1, "la primera ranura libre es la 1")
	SaveManager.begin_slot(1)
	_new(7, "Villa Uno")
	TimeManager.advance_days(40)
	SaveManager.play_seconds = 125.0
	check(SaveManager.save_slot(1), "crear partida en la ranura 1")
	var info := SaveManager.slot_info(1)
	var meta: Dictionary = info["meta"]
	check(info["status"] == "ok", "la ranura 1 aparece ocupada")
	check(str(meta.get("town", "")) == "Villa Uno" and str(meta.get("player", "")).begins_with("Ana"), "muestra pueblo y personaje (%s, %s)" % [meta.get("town"), meta.get("player")])
	check(str(meta.get("date", "")) != "" and int(meta.get("population", 0)) == GameState.citizens.size(), "muestra fecha y población")
	check(is_equal_approx(float(meta.get("money", 0.0)), GameState.money) and is_equal_approx(float(meta.get("play_seconds", 0)), 125.0), "muestra dinero y tiempo jugado")
	check(str(info["saved_at"]) != "" and meta.has("country") and meta.has("thumbnail"), "fecha del último guardado, país y miniatura en la cabecera")
	check(SaveManager.last_slot() == 1, "la ranura 1 es la última partida")
	check(SaveManager.first_empty_slot() == 2, "la siguiente libre es la 2")
	SaveManager.rename_slot(1, "Mi dinastía")
	check(SaveManager.slot_info(1)["name"] == "Mi dinastía", "renombrar la ranura")
	for i in range(2, 6):
		SaveManager.begin_slot(i)
		_new(10 + i, "Villa %d" % i)
		SaveManager.save_slot(i)
	check(SaveManager.list_slots().all(func(s): return s["status"] == "ok"), "las 5 ranuras llenas")
	check(SaveManager.first_empty_slot() == 0, "sin ranuras libres")
	var r := SaveManager.load_slot(1)
	check(r["ok"] and str(GameState.settings["town_name"]) == "Villa Uno" and SaveManager.active_slot == 1, "continuar la ranura 1")
	check(is_equal_approx(SaveManager.play_seconds, 125.0), "el tiempo jugado se restaura")
	SaveManager.delete_slot(3)
	check(SaveManager.slot_info(3)["status"] == "empty" and SaveManager.first_empty_slot() == 3, "borrar la ranura 3 la deja vacía")
	check(not FileAccess.file_exists(SaveManager.slot_file(3) + ".bak1"), "borrar quita también las copias")
	SaveManager.delete_slot(1)
	check(SaveManager.slot_name(1) == "" and SaveManager.last_slot() == 0, "borrar olvida el nombre y la última partida")
	_clear_slots()


# --- Autoguardado --------------------------------------------------------------------------------

func _test_autosave() -> void:
	_clear_slots()
	SaveManager.begin_slot(2)
	_new(21)
	SaveManager.set_autosave_minutes(3.0)
	_saved_reasons.clear()
	SaveManager.autosave_tick(60.0)
	check(not SaveManager.slot_exists(2), "sin autoguardado antes de 3 minutos")
	SaveManager.autosave_tick(125.0)
	check(SaveManager.slot_info(2)["status"] == "ok" and _saved_reasons.has("auto"), "autoguardado a los 3 minutos reales")
	# Cambio de mes: se guarda (con un mínimo de separación entre guardados).
	_saved_reasons.clear()
	var guard := 0
	TimeManager.advance_days(1)
	while int(TimeManager.month_day()[1]) != 1 and guard < 40:
		TimeManager.advance_days(1)
		guard += 1
	SaveManager.autosave_tick(1.0)
	check(_saved_reasons.is_empty(), "el autoguardado de mes espera unos segundos tras el último guardado")
	SaveManager.autosave_tick(SaveManager.MONTH_SAVE_MIN_GAP)
	check(_saved_reasons.has("mes"), "autoguardado al cambiar de mes")
	var h: Dictionary = SaveManager.read_header(SaveManager.slot_file(2))["data"]
	check(str(h["meta"]["date"]) == TimeManager.date_string(false), "el autoguardado tiene la fecha del juego actual")
	SaveManager.set_autosave_minutes(0.0)
	_saved_reasons.clear()
	SaveManager.autosave_tick(1000.0)
	check(_saved_reasons.is_empty(), "autoguardado por tiempo desactivable (0 min)")
	SaveManager.set_autosave_minutes(3.0)
	SaveManager.active_slot = 0
	_saved_reasons.clear()
	SaveManager.autosave_tick(1000.0)
	check(_saved_reasons.is_empty(), "sin ranura activa no se autoguarda")
	_clear_slots()


# --- Escritura atómica y recuperación ------------------------------------------------------------

func _test_atomic_and_recovery() -> void:
	_clear_slots()
	var p := SaveManager.slot_file(3)
	SaveManager.begin_slot(3)
	_new(33)
	SaveManager.save_slot(3)
	var money1 := GameState.money
	GameState.money += 1000.0
	SaveManager.save_slot(3)
	GameState.money += 1000.0
	SaveManager.save_slot(3)
	check(FileAccess.file_exists(p) and FileAccess.file_exists(p + ".bak1") and FileAccess.file_exists(p + ".bak2"), "principal + 2 copias rotativas")
	check(not FileAccess.file_exists(p + ".tmp"), "no queda el .tmp tras guardar")
	check(is_equal_approx(float(SaveManager.read_header(p + ".bak2")["data"]["meta"]["money"]), money1), "la .bak2 es la más antigua")
	GameState.money += 1000.0
	SaveManager.save_slot(3)
	check(not FileAccess.file_exists(p + ".bak3"), "solo se guardan 2 copias")
	var good_money := GameState.money
	# Archivo principal corrupto (bytes al azar): se carga la copia y la principal queda intacta.
	var junk := PackedByteArray()
	for i in range(4000):
		junk.append((i * 37 + 11) % 256)
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_buffer(junk)
	f.close()
	var info := SaveManager.slot_info(3)
	check(info["status"] == "damaged" and not (info["backups"] as Array).is_empty(), "la ranura se marca dañada y ofrece copias")
	GameState.money = 0.0
	var r := SaveManager.load_slot(3)
	check(r["ok"] and r["used_backup"], "con la principal corrupta se carga la copia (.bak1)")
	check(is_equal_approx(GameState.money, good_money - 1000.0), "la copia tiene el guardado anterior")
	check(FileAccess.get_file_as_bytes(p) == junk, "la partida dañada no se borra ni se modifica")
	SaveManager.save_slot(3)
	check(SaveManager.slot_info(3)["status"] == "ok" and FileAccess.get_file_as_bytes(p + ".damaged") == junk, "al guardar, la dañada se aparta intacta (.damaged)")
	check(SaveManager.read_header(p + ".bak1")["ok"], "las copias buenas no se desplazan con la dañada")
	# Archivo truncado (corte de luz a mitad): se detecta y se usa la copia.
	var full := FileAccess.get_file_as_bytes(p)
	f = FileAccess.open(p, FileAccess.WRITE)
	f.store_buffer(full.slice(0, full.size() / 2))
	f.close()
	check(not SaveManager.read_file(p)["ok"], "un archivo truncado se detecta")
	check(SaveManager.load_slot(3)["ok"], "y se recupera desde la copia")
	# Un byte cambiado dentro del cuerpo: la suma de verificación lo detecta.
	var flipped := full.duplicate()
	flipped[flipped.size() - 20] = (flipped[flipped.size() - 20] + 1) % 256
	f = FileAccess.open(p, FileAccess.WRITE)
	f.store_buffer(flipped)
	f.close()
	check(not SaveManager.read_file(p)["ok"], "un byte dañado se detecta (SHA-256)")
	# Corte entre renombrados: no hay principal pero el .tmp está completo.
	DirAccess.remove_absolute(p)
	f = FileAccess.open(p + ".tmp", FileAccess.WRITE)
	f.store_buffer(full)
	f.close()
	r = SaveManager.load_slot(3)
	check(r["ok"] and str(r["source"]).ends_with(".tmp"), "si el corte fue al renombrar, se usa el .tmp completo")
	# .tmp a medias + copias: se ignora el .tmp y se usa la copia.
	f = FileAccess.open(p + ".tmp", FileAccess.WRITE)
	f.store_buffer(full.slice(0, 300))
	f.close()
	r = SaveManager.load_slot(3)
	check(r["ok"] and str(r["source"]).ends_with(".bak1"), "un .tmp a medias se ignora y se usa la copia")
	# Todo dañado: error claro, nada se borra.
	for s in ["", ".bak1", ".bak2", ".tmp"]:
		f = FileAccess.open(p + s, FileAccess.WRITE)
		f.store_buffer(junk)
		f.close()
	r = SaveManager.load_slot(3)
	check(not r["ok"] and str(r["error"]) != "" and FileAccess.file_exists(p) and FileAccess.file_exists(p + ".bak1"), "si nada carga, muestra el error y no borra nada")
	_clear_slots()


# --- Migración de formato viejo -------------------------------------------------------------------

func _old_v3_dict() -> Dictionary:
	return {
		"version": 3,
		"saved_at": "2024-05-01T10:00:00",
		"summary": {"town": "Villa Vieja", "date": "1 de marzo de 1703", "population": 0, "money": 4321.0},
		"time": {"total_hours": 2 * 365 * 24 + 1500},
		"state": {
			"settings": {"town_name": "Villa Vieja", "seed": 12, "difficulty": "normal", "player_name": "Tomás"},
			"money": 4321.0,
			"buildings": [],
			"citizens": [],
		},
	}


func _test_old_format_migration() -> void:
	_clear_slots()
	var p := SaveManager.slot_file(4)
	_write_var(p, _old_v3_dict())
	var info := SaveManager.slot_info(4)
	check(info["status"] == "ok" and str(info["meta"].get("town", "")) == "Villa Vieja", "una partida v3 se lista con su pueblo")
	var r := SaveManager.load_slot(4)
	check(r["ok"] and int(r.get("from_version", 0)) == 3, "cargar una partida del formato v3 (mínima)")
	check(FileAccess.file_exists(SaveManager.slots_dir + "slot_4.v3.backup"), "antes de migrar se crea slot_4.v3.backup")
	check(str(GameState.settings["town_name"]) == "Villa Vieja" and is_equal_approx(GameState.money, 4321.0), "pueblo y dinero se conservan")
	check(GameState.player_citizen() != null and not GameState.map.is_empty() and not GameState.countries.is_empty(), "los sistemas nuevos se completan (jugador, mapa, países)")
	TimeManager.advance_days(45)
	check(GameState.running, "la partida migrada se puede jugar (45 días)")
	SaveManager.save_slot(4)
	var h: Dictionary = SaveManager.read_header(p)["data"]
	check(int(h.get("format_version", 0)) == SaveMigrations.CURRENT and h.has("game_version") and h.has("meta"), "al guardar queda en el formato actual con cabecera")
	check(SaveManager.read_file(SaveManager.slots_dir + "slot_4.v3.backup")["ok"] and SaveMigrations.version_of(SaveManager.read_file(SaveManager.slots_dir + "slot_4.v3.backup")["data"]) == 3, "el respaldo v3 queda intacto")
	# Formato sin versión (fase 1) y migración paso a paso.
	var m := SaveMigrations.migrate({"state": {"money": 50.0}})
	check(m["ok"] and int(m["from"]) == 1 and int(m["data"]["format_version"]) == SaveMigrations.CURRENT and m["data"].has("meta"), "migración v1 → v%d encadenada" % SaveMigrations.CURRENT)
	var r2 := SaveManager.apply_save({"state": {"money": 50.0, "settings": {"seed": 3}}})
	check(r2["ok"] and is_equal_approx(GameState.money, 50.0), "una partida casi vacía (sin versión) también carga")
	TimeManager.advance_days(10)
	check(GameState.running, "y se puede jugar")
	# Un .json del sistema viejo.
	var js := _old_v3_dict()
	js["state"]["settings"]["town_name"] = "Villa JSON"
	var f := FileAccess.open(SaveManager.legacy_dir + "vieja_json.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(js))
	f.close()
	check(SaveManager.load_game("vieja_json") and str(GameState.settings["town_name"]) == "Villa JSON", "cargar un .json antiguo")
	DirAccess.remove_absolute(SaveManager.legacy_dir + "vieja_json.json")
	_clear_slots()


# --- Claves del futuro -------------------------------------------------------------------------

func _test_future_keys() -> void:
	_clear_slots()
	SaveManager.begin_slot(5)
	_new(55, "Villa Futura")
	TimeManager.advance_days(20)
	var d := SaveManager.build_save(5)
	d["format_version"] = SaveMigrations.CURRENT + 7
	d["game_version"] = "9.9.9"
	d["sistema_nuevo_raiz"] = {"x": 1}
	d["meta"]["dato_nuevo"] = [1, 2, 3]
	var st: Dictionary = d["state"]
	st["sistema_del_futuro"] = {"naves": 3, "lista": [1, 2]}
	st["settings"]["opcion_futura"] = true
	st["economy"]["indicador_futuro"] = 0.5
	st["government"]["ley_futura"] = "sí"
	if not (st["citizens"] as Array).is_empty():
		st["citizens"][0]["campo_nuevo"] = {"a": 1}
	if not (st["buildings"] as Array).is_empty():
		st["buildings"][0]["campo_nuevo"] = 7
	d["time"]["zona_horaria"] = "futura"
	check(SaveManager.write_save(SaveManager.slot_file(5), d), "escribir una partida \"del futuro\"")
	var pop := GameState.citizens.size()
	var r := SaveManager.load_slot(5)
	check(r["ok"] and bool(r.get("future", false)), "una partida con versión mayor y claves extra carga sin fallar")
	check(GameState.citizens.size() == pop and str(GameState.settings["town_name"]) == "Villa Futura", "sus datos conocidos se conservan")
	TimeManager.advance_days(30)
	check(GameState.running, "y se puede jugar (30 días)")
	# Tipos inesperados en claves conocidas → valores por defecto.
	var weird := SaveManager.build_save(5)
	weird["state"]["logistics"] = "texto raro"
	weird["state"]["loans"] = {"no": "es lista"}
	weird["state"]["history"] = 5
	weird["state"]["settings"]["difficulty"] = "imposible"
	check(SaveManager.apply_save(weird)["ok"], "tipos inesperados no rompen la carga")
	TimeManager.advance_days(5)
	check(GameState.running and str(GameState.settings["difficulty"]) == "normal", "se usan valores por defecto")
	_clear_slots()


# --- Importar partidas antiguas ----------------------------------------------------------------

func _test_legacy_import() -> void:
	_clear_slots()
	var ld := SaveManager.legacy_dir
	var names := ["autoguardado", "finca_1702", "costa", "montes", "villa_a", "villa_b", "villa_c"]
	for i in range(names.size()):
		var od := _old_v3_dict()
		od["version"] = 7
		od["saved_at"] = "2025-0%d-10T12:00:00" % (i + 1)
		od["summary"]["town"] = "Pueblo %s" % names[i]
		od["state"]["settings"]["town_name"] = "Pueblo %s" % names[i]
		_write_var(ld + names[i] + ".sav", od)
	_write_var(ld + "test_basura.sav", _old_v3_dict())
	var bytes_before := FileAccess.get_file_as_bytes(ld + "autoguardado.sav")
	var legacy := SaveManager.list_legacy()
	check(legacy.size() == 7, "7 partidas antiguas encontradas (sin las de prueba)")
	var n := SaveManager.auto_import_legacy()
	check(n == 5, "se importan 5 a las ranuras")
	var towns := SaveManager.list_slots().map(func(s): return str(s["meta"].get("town", "")))
	check(towns.has("Pueblo villa_c") and towns.has("Pueblo montes") and not towns.has("Pueblo autoguardado"), "las 5 más recientes van a las ranuras")
	var rest := SaveManager.list_legacy()
	check(rest.size() == 2 and rest.any(func(s): return s["slot"] == "autoguardado"), "las demás quedan como \"partidas antiguas\" para importar (incluido autoguardado)")
	check(SaveManager.auto_import_legacy() == 0, "la importación automática solo ocurre una vez")
	check(FileAccess.get_file_as_bytes(ld + "autoguardado.sav") == bytes_before and FileAccess.file_exists(ld + "villa_c.sav"), "los archivos antiguos quedan intactos")
	check(not SaveManager.import_legacy("autoguardado", 1), "importar no sobrescribe una ranura ocupada")
	SaveManager.delete_slot(2)
	check(SaveManager.import_legacy("autoguardado", 2), "importar a mano el autoguardado a la ranura 2")
	check(SaveManager.slot_info(2)["name"] == "Autoguardado" and FileAccess.file_exists(SaveManager.slots_dir + "slot_2.v7.backup"), "con nombre y respaldo de la versión 7")
	var r := SaveManager.load_slot(2)
	check(r["ok"] and str(GameState.settings["town_name"]) == "Pueblo autoguardado", "la partida importada se carga")
	TimeManager.advance_days(15)
	check(GameState.running, "y se juega")
	for nm in names + ["test_basura"]:
		DirAccess.remove_absolute(ld + nm + ".sav")
	_clear_slots()


# --- Ida y vuelta ---------------------------------------------------------------------------------

func _test_round_trip() -> void:
	_clear_slots()
	SaveManager.begin_slot(1)
	var gs := GameState
	_new(88, "Villa Completa")
	gs.money += 40000.0
	var farm: Dictionary = ConstructionSim.start_construction(gs, "granja", 30, -8, 0.3, "Granja RT")["building"]
	var bank: Dictionary = ConstructionSim.start_construction(gs, "banco", -32, 10, 1.0, "Banco RT")["building"]
	ConstructionSim.start_construction(gs, "taberna", -10, 34, 2.0, "Taberna RT")
	BankSim.request_player_loan(gs, 800.0, 12)
	TimeManager.advance_days(60)
	for b in [farm, bank]:
		for c in BusinessSim.candidates(gs, b).slice(0, 2):
			BusinessSim.hire(gs, b, c, BusinessSim.asked_wage(gs, c, b["type"]))
	TimeManager.advance_days(400)
	var staff := 0
	for b in [farm, bank]:
		staff += gs.employees_of(int(b["id"])).size()
	check(gs.buildings.size() > 3 and staff > 0 and gs.history.size() > 10, "partida con edificios, empleados e historial (%d edificios, %d empleados, %d préstamos)" % [gs.buildings.size(), staff, gs.loans.size()])
	var before := JSON.stringify(gs.to_dict())
	var hours := TimeManager.total_hours
	check(SaveManager.save_slot(1), "guardar")
	check(SaveManager.load_slot(1)["ok"], "cargar")
	var a := JSON.stringify(gs.to_dict())
	check(TimeManager.total_hours == hours and a.length() > before.length() * 0.99, "fecha y estado restaurados")
	check(SaveManager.save_slot(1), "guardar otra vez")
	check(SaveManager.load_slot(1)["ok"], "cargar otra vez")
	var b2 := JSON.stringify(gs.to_dict())
	check(a == b2, "guardar → cargar → guardar produce estados equivalentes")
	var h1: Dictionary = SaveManager.read_file(SaveManager.slot_file(1))["data"]
	check(JSON.stringify(h1["state"]) == b2, "el archivo guardado tiene exactamente ese estado")
	TimeManager.advance_days(200)
	var fut := JSON.stringify(gs.to_dict())
	SaveManager.load_slot(1)
	TimeManager.advance_days(200)
	check(JSON.stringify(gs.to_dict()) == fut, "la simulación sigue igual tras cargar (determinista)")
	_clear_slots()


# --- Interfaz: pantalla principal con ranuras, menú de pausa y barra superior ---------------------

func _bar_fits(hud: Hud) -> bool:
	return hud._top_row.get_combined_minimum_size().x <= hud.root.size.x - 20.0


func _test_ui() -> void:
	_clear_slots()
	SaveManager.begin_slot(1)
	_new(61, "Villa Menú")
	SaveManager.save_slot(1)
	SaveManager.begin_slot(3)
	_new(63, "Villa Tres")
	SaveManager.save_slot(3)
	var menu: MainMenu = load("res://scenes/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	check(menu.slots_box.get_child_count() == 5, "la pantalla principal muestra 5 ranuras")
	check(menu.slots_box.get_child(1) is Button and (menu.slots_box.get_child(1) as Button).text.contains("Vacío — Nueva partida"), "las vacías dicen «Vacío — Nueva partida»")
	check(not menu.continue_btn.disabled, "«Continuar última partida» disponible")
	menu._new_in(1)
	check(menu._confirm["root"].visible and not menu.new_panel.visible, "nueva partida en una ranura ocupada pide confirmación")
	menu._confirm["root"].visible = false
	menu._new_in(2)
	check(menu.new_panel.visible and menu._pending_slot == 2, "nueva partida en la ranura vacía 2")
	menu._show_main()
	menu._open_rename(1)
	menu._rename_edit.text = "Los Ruiz"
	menu._do_rename()
	check(SaveManager.slot_name(1) == "Los Ruiz", "renombrar desde el menú")
	menu._ask_delete(3)
	check(menu._confirm["root"].visible, "borrar pide confirmación")
	menu._confirm["root"].visible = false
	check(SaveManager.slot_exists(3), "cancelar no borra")
	var junk := PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])
	for sfx in ["", ".bak1"]:
		var f := FileAccess.open(SaveManager.slot_file(3) + sfx, FileAccess.WRITE)
		f.store_buffer(junk)
		f.close()
	menu.refresh_slots()
	menu.continue_slot(3)
	check(menu._error["root"].visible and FileAccess.get_file_as_bytes(SaveManager.slot_file(3)) == junk, "si no carga: muestra el error y deja la partida intacta")
	menu.queue_free()
	await get_tree().process_frame
	# En el juego: menú de pausa con guardar.
	SaveManager.begin_slot(1)
	GameState.new_game({"seed": 64, "difficulty": "normal", "country_id": "COL", "town_name": "Villa Pausa con un nombre bastante largo"})
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	var hud: Hud = world.hud
	hud._open_pause()
	check(hud._save_now_btn.text.contains("ranura 1"), "el menú de pausa ofrece «Guardar ahora» en su ranura")
	await hud._save_now()
	check(SaveManager.slot_info(1)["status"] == "ok" and hud._save_toast.visible and hud._save_toast_lbl.text.begins_with("Guardado ✓"), "guardar ahora muestra «Guardado ✓»")
	check(hud._save_status.text.begins_with("Último guardado"), "indicador de último guardado")
	hud._close(hud.pause_modal)
	hud._open_save()
	check(hud.save_slots_box.get_child_count() == 5, "elegir ranura: las 5")
	hud._close(hud.save_modal)
	hud._open_load()
	check(hud.load_list.item_count >= 1, "cargar desde el juego lista las ranuras")
	hud._close(hud.load_modal)
	# Barra superior adaptable.
	for sz in [Vector2i(1600, 900), Vector2i(1280, 720)]:
		get_window().size = sz
		for i in range(12):
			await get_tree().process_frame
		hud._update_top_bar()
		check(_bar_fits(hud), "la barra superior cabe a %d px (nivel %d, necesita %d de %d)" % [sz.x, hud._bar_level, int(hud._top_row.get_combined_minimum_size().x), int(hud.root.size.x)])
	get_window().size = Vector2i(1600, 900)
	world.queue_free()
	await get_tree().process_frame
	_clear_slots()
