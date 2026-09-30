extends Node
## Audio (docs/AUDIO.md): buses, opciones guardadas, música por época, efectos por evento,
## límite de voces y funcionamiento en modo headless (driver de audio Dummy).
## godot --headless res://tests/test_audio.tscn

var failures := 0
var gs = GameState
var am: Node


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func _ready() -> void:
	print("== Dinastía: audio ==")
	am = get_node("/root/AudioManager")
	print("  (servidor de pantalla: %s · buses: %d)" % [DisplayServer.get_name(), AudioServer.bus_count])
	# Copia de seguridad de las opciones reales del jugador: la prueba las toca.
	var backup := FileAccess.get_file_as_bytes(AudioSettings.PATH) if FileAccess.file_exists(AudioSettings.PATH) else PackedByteArray()
	_test_buses()
	_test_files()
	_test_settings()
	gs.new_game({"seed": 5, "difficulty": "facil", "map_type": "interior"})
	await _test_music()
	await _test_events()
	_test_voices()
	await _test_headless_frames()
	# Restaurar las opciones del jugador.
	if backup.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AudioSettings.PATH))
	else:
		var f := FileAccess.open(AudioSettings.PATH, FileAccess.WRITE)
		f.store_buffer(backup)
		f.close()
	AudioSettings.reload()
	AudioSettings.apply()
	am.context_override = ""
	print("== %s (%d fallos) ==" % ["TODO OK" if failures == 0 else "CON FALLOS", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _test_buses() -> void:
	for b in ["Master", "Music", "SFX", "Ambience", "UI"]:
		check(AudioServer.get_bus_index(b) >= 0, "existe el bus %s" % b)
	var mi := AudioServer.get_bus_index("Music")
	check(AudioServer.get_bus_effect_count(mi) > 0 and AudioServer.get_bus_effect(mi, 0) is AudioEffectLowPassFilter, "el bus Music tiene el filtro de noche/crisis")
	for b in ["Music", "SFX", "Ambience", "UI"]:
		check(AudioServer.get_bus_send(AudioServer.get_bus_index(b)) == "Master", "%s envía a Master" % b)
	check(ResourceLoader.exists("res://default_bus_layout.tres"), "default_bus_layout.tres existe")


func _test_files() -> void:
	var missing: Array = []
	for id in am.TRACKS:
		if am.stream(id) == null:
			missing.append(id)
	for s in am.UI_SFX + am.AMB_LAYERS + ["construction_loop", "cart_loop", "truck_loop", "steam_loop", "bus_loop",
			"train_loop", "train_whistle", "ship_horn", "plane_pass", "church_bell", "thunder_1", "thunder_2"]:
		if am.stream(s) == null:
			missing.append(s)
	check(missing.is_empty(), "todas las pistas y efectos cargan (%d faltan: %s)" % [missing.size(), ", ".join(missing)])
	var per_era := {}
	for id in am.TRACKS:
		var e := int(am.TRACKS[id]["era"])
		per_era[e] = int(per_era.get(e, 0)) + 1
	check(int(per_era.get(1, 0)) >= 2 and int(per_era.get(2, 0)) >= 2 and int(per_era.get(3, 0)) >= 2 and int(per_era.get(0, 0)) >= 1,
		"al menos 2 piezas por época y una del menú (%s)" % str(per_era))
	var total := _dir_size("res://assets/audio")
	check(total > 0 and total < 25 * 1024 * 1024, "el audio ocupa menos de 25 MB (%.1f MB)" % (total / 1048576.0))
	var st: AudioStream = am.stream("amb_rain")
	check(st is AudioStreamOggVorbis and (st as AudioStreamOggVorbis).loop, "los ambientes se reproducen en bucle")


func _dir_size(path: String) -> int:
	var total := 0
	var d := DirAccess.open(path)
	if d == null:
		return 0
	for f in d.get_files():
		if f.ends_with(".ogg") or f.ends_with(".wav"):
			total += FileAccess.get_file_as_bytes(path + "/" + f).size()
	for sub in d.get_directories():
		total += _dir_size(path + "/" + sub)
	return total


func _test_settings() -> void:
	AudioSettings.set_value("music", 0.33)
	AudioSettings.set_value("ui", 0.0)
	AudioSettings.set_value("muted", true)
	AudioSettings.set_value("music_by_era", false)
	AudioSettings.set_value("track", "colonial_2")
	check(FileAccess.file_exists(AudioSettings.PATH), "las opciones se guardan en %s" % AudioSettings.PATH)
	AudioSettings.reset_defaults()
	check(is_equal_approx(float(AudioSettings.get_value("music")), 0.6), "(valores por defecto en memoria)")
	AudioSettings.reload()
	check(is_equal_approx(float(AudioSettings.get_value("music")), 0.33), "el volumen de música se carga (%s)" % str(AudioSettings.get_value("music")))
	check(bool(AudioSettings.get_value("muted")) and not bool(AudioSettings.get_value("music_by_era")) and str(AudioSettings.get_value("track")) == "colonial_2",
		"silencio, música según época y pista se cargan")
	AudioSettings.apply()
	var mi := AudioServer.get_bus_index("Music")
	check(absf(AudioServer.get_bus_volume_db(mi) - linear_to_db(0.33)) < 0.01, "el volumen se aplica al bus Music (%.1f dB)" % AudioServer.get_bus_volume_db(mi))
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("UI")), "volumen 0 silencia el bus UI")
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "«Silenciar todo» silencia Master")
	check(not am.play_ui("ui_click"), "silenciado no dispara efectos")
	# Deja todo como por defecto para el resto de la prueba.
	for k in AudioSettings.DEFAULTS:
		AudioSettings.set_value(k, AudioSettings.DEFAULTS[k])
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "quitar el silencio reactiva Master")


func _test_music() -> void:
	am.context_override = "menu"
	am._update_context()
	am._update_music(0.1)
	check(am.current_track == "menu", "en el menú suena la pieza del menú (%s)" % am.current_track)
	am.context_override = "game"
	gs.money = 1000.0
	gs.research["era"] = 1
	am._update_context()
	am._update_music(0.1)
	check(int(am.TRACKS[am.current_track]["era"]) == 1, "época colonial → música colonial (%s)" % am.current_track)
	var first: String = am.current_track
	am.next_track()
	check(am.current_track != first and int(am.TRACKS[am.current_track]["era"]) == 1, "la siguiente pieza varía dentro de la época (%s → %s)" % [first, am.current_track])
	gs.research["era"] = 2
	am._update_music(0.1)
	check(int(am.TRACKS[am.current_track]["era"]) == 2, "época industrial → música industrial (%s)" % am.current_track)
	gs.research["era"] = 3
	am._update_music(0.1)
	check(int(am.TRACKS[am.current_track]["era"]) == 3, "época moderna → música moderna (%s)" % am.current_track)
	await get_tree().create_timer(0.3).timeout
	var playing := 0
	for p in am._music:
		if p.playing:
			playing += 1
	check(playing >= 1, "hay un reproductor de música activo durante el fundido (%d)" % playing)
	# Crisis: dinero negativo → la pieza de crisis entra al conjunto.
	gs.money = -500.0
	am._update_context()
	check(am.crisis and am.track_pool().has("crisis"), "en crisis suena «Tiempos difíciles»")
	gs.money = 1000.0
	am._update_context()
	# Sin música por época: todas las piezas del juego; pista fija: solo esa.
	AudioSettings.set_value("music_by_era", false)
	check(am.track_pool().size() == 9, "sin «música según época» se usan las 9 piezas del juego (%d)" % am.track_pool().size())
	AudioSettings.set_value("track", "industrial_3")
	check(am.current_track == "industrial_3" and am.track_pool() == ["industrial_3"], "el selector de pista fija la pieza")
	AudioSettings.set_value("track", "")
	AudioSettings.set_value("music_by_era", true)
	am._update_music(0.1)
	check(int(am.TRACKS[am.current_track]["era"]) == 3, "al volver a automática sigue la época (%s)" % am.current_track)


func _test_events() -> void:
	am._last_sfx_ms.clear()
	TimeManager.speed = 1
	EventBus.notification_posted.emit({"text": "Nació Ana.", "category": "nacimiento"})
	check(am.last_event_sfx == "notif_good", "un nacimiento suena como buena noticia (%s)" % am.last_event_sfx)
	var ui_playing := 0
	for p in am._pool_ui:
		if p.playing:
			ui_playing += 1
	check(ui_playing >= 1, "el efecto de interfaz se está reproduciendo")
	await get_tree().create_timer(0.4).timeout
	EventBus.notification_posted.emit({"text": "Murió Pedro.", "category": "muerte"})
	check(am.last_event_sfx == "notif_bad", "una muerte suena como mala noticia (%s)" % am.last_event_sfx)
	await get_tree().create_timer(0.4).timeout
	gs.notify("Crédito firmado.", "importante")
	check(am.last_event_sfx == "notif_important", "GameState.notify(importante) → notif_important (%s)" % am.last_event_sfx)
	am.on_toast("Dinero insuficiente", "jugador")
	check(am.last_event_sfx == "error", "un aviso de error del HUD suena como error")
	am.last_event_sfx = ""
	EventBus.hour_passed.emit(12)
	check(am.last_event_sfx == "church_bell", "a mediodía suena la campana de la iglesia")
	am.last_event_sfx = ""
	EventBus.hour_passed.emit(13)
	check(am.last_event_sfx == "", "a otras horas no suena la campana")
	# Un botón nuevo en el árbol suena al pulsarlo.
	var b := Button.new()
	add_child(b)
	am._last_sfx_ms.clear()
	b.pressed.emit()
	check(Time.get_ticks_msec() - am._last_input_ms < 500, "los botones quedan conectados al clic de interfaz")
	b.queue_free()
	# Ambiente: lluvia y noche.
	gs.weather["type"] = "lluvia"
	am._ambience_targets(70.0, false)
	check(am.ambience_level("amb_rain") > 0.5 and am.ambience_level("amb_birds") == 0.0, "con lluvia suena la lluvia y callan los pájaros")
	gs.weather["type"] = "despejado"
	am.night = 1.0
	am._ambience_targets(70.0, false)
	check(am.ambience_level("amb_crickets") > 0.5, "de noche se oyen grillos")
	am._ambience_targets(600.0, false)
	check(am.ambience_level("amb_general") > 0.5 and am.ambience_level("amb_crickets") < 0.1, "con zoom muy alejado domina el ambiente general")
	am.night = 0.0
	TimeManager.speed = 0


func _test_voices() -> void:
	for i in range(40):
		am.play_3d("construction_loop" if i % 2 == 0 else "church_bell", Vector3(i, 0, 0))
	check(am.voices_in_use() <= am.MAX_VOICES_3D, "40 efectos a la vez no superan el límite de %d voces (%d)" % [am.MAX_VOICES_3D, am.voices_in_use()])
	check(am.voices_in_use() >= am.MAX_VOICES_3D - 1, "el pool se reutiliza (%d voces activas)" % am.voices_in_use())
	var ui_ok := 0
	for i in range(20):
		am._last_sfx_ms.clear()
		if am.play_ui("ui_tab"):
			ui_ok += 1
	var ui_playing := 0
	for p in am._pool_ui:
		if p.playing:
			ui_playing += 1
	check(ui_playing <= am.MAX_VOICES_UI, "la interfaz no supera %d voces (%d)" % [am.MAX_VOICES_UI, ui_playing])
	for p in am._pool_3d:
		p.stop()


func _test_headless_frames() -> void:
	# Unos segundos de _process con el juego "en marcha" (sin escena 3D): no debe fallar nada.
	am.context_override = "game"
	TimeManager.speed = 2
	gs.weather["type"] = "tormenta"
	am._thunder_t = 0.0
	for i in range(30):
		await get_tree().process_frame
	await get_tree().create_timer(1.2).timeout
	check(am.context == "game" and am.current_track != "", "en headless el audio sigue funcionando (%s, contexto %s)" % [am.current_track, am.context])
	check(am.ambience_level("amb_storm") > 0.5, "la tormenta activa su ambiente")
	TimeManager.speed = 0
	gs.weather["type"] = "despejado"
	am.stop_music(0.1)
