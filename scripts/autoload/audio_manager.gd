extends Node
## Audio del juego (docs/AUDIO.md): música por época y contexto con fundido cruzado, efectos de
## interfaz, ambiente por bioma/clima/hora y sonidos 3D del mundo (obras, vehículos, campana).
##
## Solo LEE el estado del juego (GameState, TimeManager, mundo 3D); nunca usa GameState.rng, así
## que no altera la simulación ni su determinismo. Todo el audio es procedimental (tools/make_audio.py).
##
## API:
##   play_ui(nombre)                 efecto de interfaz (bus UI). Ver UI_SFX.
##   play_3d(nombre, posición, dB)   efecto posicional (bus SFX), respeta MAX_VOICES_3D.
##   on_notification(entrada)        sonido de un aviso según su categoría (conectado a EventBus).
##   on_toast(texto, categoría)      igual, para los avisos directos del HUD (errores = "error").
##   play_track(id) / next_track()   música (normalmente automática; ver TRACKS).
##   voices_in_use()                 voces de efectos sonando (para pruebas y depuración).

const DIR := "res://assets/audio/"
const MAX_VOICES_3D := 10          # efectos 3D simultáneos (incluye bucles de obras y vehículos)
const MAX_VOICES_UI := 4
const MAX_LOOP_BUILD := 2          # obras con martillos audibles a la vez
const MAX_LOOP_VEHICLES := 3
const HEAR_RADIUS := 170.0         # más lejos que esto no se asignan emisores
const FAR_ZOOM := 190.0            # distancia de cámara a partir de la cual domina el ambiente general
const CROSSFADE := 3.0
const MUSIC_GAP := Vector2(4.0, 14.0)   # silencio entre piezas (s), para que no canse

## Pistas: título visible, época (0 menú, 1 colonial, 2 industrial, 3 moderna, -1 crisis).
const TRACKS := {
	"menu": {"title": "Dinastía (menú)", "era": 0},
	"colonial_1": {"title": "Colonial · Plaza de la Colonia", "era": 1},
	"colonial_2": {"title": "Colonial · Caminos de herradura", "era": 1},
	"colonial_3": {"title": "Colonial · Atardecer en la hacienda", "era": 1},
	"industrial_1": {"title": "Industrial · Vapor y progreso", "era": 2},
	"industrial_2": {"title": "Industrial · Talleres del río", "era": 2},
	"industrial_3": {"title": "Industrial · La gran estación", "era": 2},
	"moderna_1": {"title": "Moderna · Luces de ciudad", "era": 3},
	"moderna_2": {"title": "Moderna · Café digital", "era": 3},
	"moderna_3": {"title": "Moderna · Horizonte", "era": 3},
	"crisis": {"title": "Tiempos difíciles", "era": -1},
}
const UI_SFX := ["ui_click", "ui_tab", "ui_open", "ui_close", "notif_info", "notif_good", "notif_bad",
		"notif_important", "money_in", "money_out", "error"]
## Categoría de aviso (GameState.notify) → efecto. Las que no están no suenan.
const NOTIF_SFX := {
	"info": "notif_info", "nacimiento": "notif_good", "boda": "notif_good", "negocio": "notif_good",
	"construccion": "notif_good", "familia": "notif_important", "importante": "notif_important",
	"muerte": "notif_bad", "salud": "notif_bad", "emigracion": "notif_bad", "jugador": "notif_bad",
	"clima": "notif_info",
}
const AMB_LAYERS := ["amb_birds", "amb_crickets", "amb_wind", "amb_general", "amb_river", "amb_sea",
		"amb_rain", "amb_storm", "amb_town_1", "amb_town_2", "amb_town_3"]
## Modo de transporte (LogisticsSim) → bucle del vehículo.
const VEHICLE_LOOPS := {"mula": "cart_loop", "carreta": "cart_loop", "carro_vapor": "steam_loop",
		"camion": "truck_loop", "trailer": "truck_loop", "bus": "bus_loop", "tren": "train_loop"}

var enabled := true                # false: no hace nada (lo usan pruebas que quieran silencio total)
var context := ""                  # "menu", "game" o "" (otra escena, p. ej. pruebas)
var context_override := ""         # pruebas: fuerza el contexto sin cargar la escena
var current_track := ""
var last_event_sfx := ""           # último efecto disparado por un evento (pruebas)
var night := 0.0                   # 0 día · 1 noche (suavizado)
var crisis := false

var _rng := RandomNumberGenerator.new()
var _streams := {}
var _music: Array[AudioStreamPlayer] = []
var _music_idx := 0
var _music_tween: Tween
var _gap_left := -1.0
var _pool_ui: Array[AudioStreamPlayer] = []
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _voice_owner := {}             # AudioStreamPlayer3D -> clave del bucle ("" = efecto suelto)
var _amb := {}                     # capa -> AudioStreamPlayer
var _amb_vol := {}                 # capa -> volumen lineal actual
var _amb_target := {}
var _last_sfx_ms := {}
var _last_input_ms := -100000
var _last_money := NAN
var _last_hours := -1
var _scan_t := 0.0
var _ctx_t := 0.0
var _thunder_t := 10.0
var _event_t := {"train": 40.0, "ship": 60.0, "plane": 90.0}
var _loops := {}                   # clave -> {player, node (opcional), pos}
var _water := 0.0
var _sea := false
var _town := 0.0
var _mount := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 7117
	ensure_buses()
	AudioSettings.apply()
	for i in range(2):
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = -80.0
		p.finished.connect(_on_music_finished.bind(p))
		add_child(p)
		_music.append(p)
	for i in range(MAX_VOICES_UI):
		var u := AudioStreamPlayer.new()
		u.bus = "UI"
		add_child(u)
		_pool_ui.append(u)
	for i in range(MAX_VOICES_3D):
		var s := AudioStreamPlayer3D.new()
		s.bus = "SFX"
		s.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		s.unit_size = 18.0
		s.max_distance = 260.0
		s.panning_strength = 0.8
		s.attenuation_filter_cutoff_hz = 9000.0
		s.attenuation_filter_db = -12.0
		add_child(s)
		_pool_3d.append(s)
		_voice_owner[s] = ""
	for layer in AMB_LAYERS:
		_amb_vol[layer] = 0.0
		_amb_target[layer] = 0.0
	get_tree().node_added.connect(_on_node_added)
	EventBus.notification_posted.connect(on_notification)
	EventBus.hour_passed.connect(_on_hour)
	EventBus.weather_changed.connect(func(): _scan_t = 0.0)


## Crea los buses Master/Music/SFX/Ambience/UI si el proyecto no los trae (default_bus_layout.tres).
static func ensure_buses() -> void:
	for b in ["Music", "SFX", "Ambience", "UI"]:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")
	var mi := AudioServer.get_bus_index("Music")
	var has_lp := false
	for e in range(AudioServer.get_bus_effect_count(mi)):
		if AudioServer.get_bus_effect(mi, e) is AudioEffectLowPassFilter:
			has_lp = true
	if not has_lp:
		var lpf := AudioEffectLowPassFilter.new()
		lpf.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(mi, lpf, 0)
		AudioServer.set_bus_effect_enabled(mi, 0, false)


func stream(sfx_name: String) -> AudioStream:
	if _streams.has(sfx_name):
		return _streams[sfx_name]
	var st: AudioStream = null
	for sub in ["sfx/", "amb/", "music/"]:
		for ext in [".ogg", ".wav"]:
			var p: String = DIR + sub + sfx_name + ext
			if ResourceLoader.exists(p):
				st = load(p)
				break
		if st != null:
			break
	if st is AudioStreamOggVorbis and (sfx_name.ends_with("_loop") or sfx_name.begins_with("amb_")):
		(st as AudioStreamOggVorbis).loop = true
	_streams[sfx_name] = st
	return st


# --- Interfaz -------------------------------------------------------------------------------------

func play_ui(sfx_name: String, volume_db := 0.0) -> bool:
	if not enabled or _muted():
		return false
	var now := Time.get_ticks_msec()
	if now - int(_last_sfx_ms.get(sfx_name, -1000)) < 60:
		return false
	var st := stream(sfx_name)
	if st == null:
		return false
	_last_sfx_ms[sfx_name] = now
	var best: AudioStreamPlayer = null
	for p in _pool_ui:
		if not p.playing:
			best = p
			break
	if best == null:
		best = _pool_ui[0]           # roba la voz más antigua
		_pool_ui.push_back(_pool_ui.pop_front())
	best.stream = st
	best.volume_db = volume_db
	best.pitch_scale = _rng.randf_range(0.97, 1.03) if sfx_name == "ui_click" else 1.0
	best.play()
	return true


func on_notification(entry: Dictionary) -> void:
	if TimeManager.jumping or TimeManager.speed >= 4:
		return
	var cat := str(entry.get("category", "info"))
	var sfx: String = NOTIF_SFX.get(cat, "")
	if sfx == "":
		return
	if cat == "construccion" and not str(entry.get("text", "")).contains("terminad"):
		sfx = "notif_info"
	if _notif_recent():
		return
	last_event_sfx = sfx
	play_ui(sfx, -2.0)


## Avisos directos del HUD (Hud.toast): en la categoría "jugador" suelen ser errores de una acción.
func on_toast(text: String, category: String) -> void:
	if category == "jugador":
		last_event_sfx = "error"
		play_ui("error")
	else:
		on_notification({"text": text, "category": category})


func _notif_recent() -> bool:
	var now := Time.get_ticks_msec()
	if now - int(_last_sfx_ms.get("_notif", -10000)) < 350:
		return true
	_last_sfx_ms["_notif"] = now
	return false


func _on_node_added(n: Node) -> void:
	if n is BaseButton:
		var b := n as BaseButton
		if not b.pressed.is_connected(_on_button):
			b.pressed.connect(_on_button)
	elif n is TabBar or n is TabContainer:
		var sig: Signal = n.tab_changed
		if not sig.is_connected(_on_tab):
			sig.connect(_on_tab)


func _on_tab(_i: int) -> void:
	play_ui("ui_tab", -2.0)


## Clics en el mundo (construir, comprar terreno…) también cuentan como acción del jugador.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_last_input_ms = Time.get_ticks_msec()


func _on_button() -> void:
	_last_input_ms = Time.get_ticks_msec()
	play_ui("ui_click")


## Llamado por el HUD al abrir/cerrar paneles y ventanas.
func panel(opening: bool) -> void:
	play_ui("ui_open" if opening else "ui_close", -3.0)


# --- Efectos 3D -----------------------------------------------------------------------------------

func voices_in_use() -> int:
	var n := 0
	for p in _pool_3d:
		if p.playing:
			n += 1
	return n


func play_3d(sfx_name: String, pos: Vector3, volume_db := 0.0, unit_size := 18.0) -> AudioStreamPlayer3D:
	if not enabled or _muted():
		return null
	var cam := _camera()
	if cam != null and cam.global_position.distance_to(pos) > HEAR_RADIUS * 1.8:
		return null
	var st := stream(sfx_name)
	if st == null:
		return null
	var p := _free_voice(pos)
	if p == null:
		return null
	p.stream = st
	p.global_position = pos
	p.volume_db = volume_db
	p.unit_size = unit_size
	p.pitch_scale = _rng.randf_range(0.96, 1.04)
	_voice_owner[p] = ""
	p.play()
	return p


## Voz libre; si no hay, roba el efecto suelto más lejano (nunca un bucle más cercano).
func _free_voice(pos: Vector3) -> AudioStreamPlayer3D:
	for p in _pool_3d:
		if not p.playing:
			return p
	var cam := _camera()
	var worst: AudioStreamPlayer3D = null
	var worst_d := -1.0
	for p in _pool_3d:
		if str(_voice_owner[p]) != "":
			continue
		var d := cam.global_position.distance_to(p.global_position) if cam else 0.0
		if d > worst_d:
			worst_d = d
			worst = p
	if worst == null:
		return null
	if cam and cam.global_position.distance_to(pos) > worst_d:
		return null
	worst.stop()
	return worst


func _set_loop(key: String, sfx_name: String, pos: Vector3, node: Node3D = null, volume_db := 0.0) -> void:
	var e: Dictionary = _loops.get(key, {})
	var p: AudioStreamPlayer3D = e.get("player")
	if p == null or not is_instance_valid(p) or str(_voice_owner.get(p, "")) != key or not p.playing:
		p = _free_voice(pos)
		if p == null:
			return
		_voice_owner[p] = key
		p.stream = stream(sfx_name)
		p.unit_size = 16.0
		p.volume_db = volume_db
		p.pitch_scale = _rng.randf_range(0.95, 1.05)
		p.global_position = pos
		p.play(_rng.randf_range(0.0, 2.0))
	elif e.get("sfx", "") != sfx_name:
		p.stream = stream(sfx_name)
		p.play()
	_loops[key] = {"player": p, "node": node, "sfx": sfx_name}
	p.global_position = pos


func _stop_loop(key: String) -> void:
	var e: Dictionary = _loops.get(key, {})
	var p: AudioStreamPlayer3D = e.get("player")
	if p != null and is_instance_valid(p) and str(_voice_owner.get(p, "")) == key:
		p.stop()
		_voice_owner[p] = ""
	_loops.erase(key)


func _stop_all_loops() -> void:
	for k in _loops.keys():
		_stop_loop(k)


# --- Música ---------------------------------------------------------------------------------------

func now_playing_title() -> String:
	if current_track == "":
		return "—"
	return str(TRACKS.get(current_track, {}).get("title", current_track))


## Pistas que pueden sonar ahora según contexto, época, crisis y opciones.
func track_pool() -> Array:
	var fixed := str(AudioSettings.get_value("track"))
	if fixed != "" and TRACKS.has(fixed) and context == "game":
		return [fixed]
	if context == "menu":
		return ["menu"]
	if context != "game":
		return []
	var out: Array = []
	if bool(AudioSettings.get_value("music_by_era")):
		var era := current_era()
		for id in TRACKS:
			if int(TRACKS[id]["era"]) == era:
				out.append(id)
		if crisis:
			out.push_front("crisis")
	else:
		for id in TRACKS:
			if int(TRACKS[id]["era"]) > 0:
				out.append(id)
	return out


func current_era() -> int:
	return clampi(TechSim.era(GameState), 1, 3)


func play_track(id: String, fade := CROSSFADE) -> void:
	var st := stream(id)
	current_track = id
	_gap_left = -1.0
	var old := _music[_music_idx]
	_music_idx = 1 - _music_idx
	var nw := _music[_music_idx]
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	nw.stream = st
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = str(AudioSettings.get_value("track")) == id
	nw.volume_db = -60.0
	if st != null and enabled:
		nw.play()
	_music_tween = create_tween().set_parallel(true)
	_music_tween.tween_property(nw, "volume_db", 0.0, fade).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if old.playing:
		_music_tween.tween_property(old, "volume_db", -60.0, fade).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_music_tween.chain().tween_callback(old.stop)


func stop_music(fade := CROSSFADE) -> void:
	current_track = ""
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween().set_parallel(true)
	for p in _music:
		if p.playing:
			_music_tween.tween_property(p, "volume_db", -60.0, fade)
	_music_tween.chain().tween_callback(func():
		for p in _music:
			if current_track == "":
				p.stop())


func next_track() -> void:
	var pool := track_pool()
	if pool.is_empty():
		stop_music()
		return
	var choices := pool.filter(func(t): return t != current_track)
	if choices.is_empty():
		choices = pool
	var pick: String = choices[_rng.randi_range(0, choices.size() - 1)]
	if crisis and pool.has("crisis") and current_track != "crisis" and _rng.randf() < 0.6:
		pick = "crisis"
	play_track(pick)


func _on_music_finished(p: AudioStreamPlayer) -> void:
	if p != _music[_music_idx] or current_track == "":
		return
	# Pista fija: se repite; automática: silencio corto y otra pieza del conjunto.
	if str(AudioSettings.get_value("track")) == current_track:
		p.play()
	else:
		_gap_left = _rng.randf_range(MUSIC_GAP.x, MUSIC_GAP.y)


func _update_music(delta: float) -> void:
	var pool := track_pool()
	if pool.is_empty():
		if current_track != "":
			stop_music()
		return
	if current_track == "" or not pool.has(current_track):
		if crisis and pool.has("crisis"):
			play_track("crisis")
		else:
			next_track()
		return
	if _gap_left >= 0.0:
		_gap_left -= delta
		if _gap_left < 0.0:
			next_track()
	# Variación sutil: de noche o en crisis la música se oscurece (filtro paso bajo del bus Music).
	var mi := AudioServer.get_bus_index("Music")
	if mi >= 0 and AudioServer.get_bus_effect_count(mi) > 0:
		var lpf := AudioServer.get_bus_effect(mi, 0) as AudioEffectLowPassFilter
		if lpf:
			var dark := maxf(night * 0.8, 0.5 if crisis else 0.0) if context == "game" else 0.0
			var target := lerpf(20000.0, 2600.0, dark)
			lpf.cutoff_hz = lerpf(lpf.cutoff_hz, target, clampf(delta * 0.6, 0.0, 1.0))
			AudioServer.set_bus_effect_enabled(mi, 0, lpf.cutoff_hz < 19000.0)


## Opciones cambiadas desde la interfaz (AudioSettings.set_value).
func on_settings_changed(key: String) -> void:
	if key in ["track", "music_by_era"]:
		var fixed := str(AudioSettings.get_value("track"))
		if fixed != "" and context == "game":
			if current_track != fixed:
				play_track(fixed, 1.5)
			elif _music[_music_idx].stream is AudioStreamOggVorbis:
				(_music[_music_idx].stream as AudioStreamOggVorbis).loop = true
		elif not track_pool().has(current_track):
			next_track()
	if key == "muted" and _muted():
		_stop_all_loops()


# --- Contexto, ambiente y mundo -------------------------------------------------------------------

func _process(delta: float) -> void:
	if not enabled:
		return
	_ctx_t -= delta
	if _ctx_t <= 0.0:
		_ctx_t = 0.5
		_update_context()
	_update_music(delta)
	if context != "game":
		_fade_ambience(delta, true)
		return
	_update_money()
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 1.0
		_scan_world()
	_fade_ambience(delta, false)
	_follow_loops()
	_random_events(delta)


func _update_context() -> void:
	var scene := get_tree().current_scene
	var c := context_override
	if c != "":
		pass
	elif scene != null and scene.get("camera_rig") != null and GameState.running:
		c = "game"
	elif scene != null and scene.get("slots_box") != null:
		c = "menu"
	if c != context:
		context = c
		if c != "game":
			_stop_all_loops()
			_last_money = NAN
	if context == "game":
		var h := 12.0 if TimeManager.speed >= 3 or TimeManager.jumping else TimeManager.hour_float()
		var target := 1.0 if (h < 5.5 or h > 19.5) else (0.0 if (h > 7.0 and h < 18.5) else 0.5)
		night = lerpf(night, target, 0.35)
		var was := crisis
		crisis = GameState.money < 0.0
		if not crisis and GlobalEconSim.ready(GameState):
			crisis = str(GlobalEconSim.home(GameState).get("phase", "")) == "crisis"
		if crisis != was and bool(AudioSettings.get_value("music_by_era")) and str(AudioSettings.get_value("track")) == "":
			next_track()


## Sonido de monedas cuando el dinero cambia justo después de una acción del jugador.
func _update_money() -> void:
	var m := float(GameState.money)
	if is_nan(_last_money):
		_last_money = m
		return
	var d := m - _last_money
	_last_money = m
	# Los cambios que llegan con el paso del tiempo (sueldos, ventas diarias) no suenan.
	var h := TimeManager.total_hours
	if h != _last_hours:
		_last_hours = h
		return
	if absf(d) < 1.0 or Time.get_ticks_msec() - _last_input_ms > 900:
		return
	last_event_sfx = "money_in" if d > 0.0 else "money_out"
	play_ui(last_event_sfx, -2.0)


func _world() -> Node:
	var s := get_tree().current_scene
	return s if s != null and s.get("camera_rig") != null else null


func _camera() -> Camera3D:
	var vp := get_viewport()
	return vp.get_camera_3d() if vp else null


## Punto que mira la cámara y su distancia (zoom).
func _focus() -> Array:
	var w := _world()
	if w != null:
		var rig: Node3D = w.get("camera_rig")
		if rig != null:
			return [rig.global_position, float(rig.get("distance"))]
	var cam := _camera()
	return [cam.global_position if cam else Vector3.ZERO, 70.0]


func _scan_world() -> void:
	var w := _world()
	if w == null:
		_ambience_targets(70.0, false)   # sin mundo 3D: solo clima y hora
		return
	var f := _focus()
	var focus: Vector3 = f[0]
	var dist: float = f[1]
	var interior: Node = w.get("interior")
	var inside: bool = interior != null and bool(interior.get("active"))
	var paused := TimeManager.speed == 0
	_sample_terrain(w, focus, dist)
	# Obras cercanas: martillos y serrucho en bucle en las más próximas.
	var sites: Array = []
	if not paused and not inside and dist < FAR_ZOOM:
		for b in GameState.buildings:
			var stt := str(b.get("status", ""))
			if stt != "construccion" and stt != "mejorando":
				continue
			var p := Vector3(float(b["x"]), focus.y, float(b["z"]))
			var dd := p.distance_to(focus)
			if dd < HEAR_RADIUS:
				sites.append([dd, p])
		sites.sort_custom(func(a, c): return a[0] < c[0])
	for i in range(MAX_LOOP_BUILD):
		if i < sites.size():
			var p3: Vector3 = sites[i][1]
			var node: Node = (w.get("terrain") as Node)
			if node and node.has_method("height_at"):
				p3.y = float(node.call("height_at", p3.x, p3.z)) + 2.0
			_set_loop("build%d" % i, "construction_loop", p3, null, -2.0)
		else:
			_stop_loop("build%d" % i)
	# Vehículos visibles más cercanos.
	var veh: Array = []
	if not paused and not inside and dist < FAR_ZOOM:
		veh = _collect_vehicles(w, focus)
		veh.sort_custom(func(a, c): return a[0] < c[0])
	for i in range(MAX_LOOP_VEHICLES):
		if i < veh.size():
			var node3: Node3D = veh[i][2]
			_set_loop("veh%d" % i, str(veh[i][1]), node3.global_position, node3, -4.0)
		else:
			_stop_loop("veh%d" % i)
	_ambience_targets(dist, inside)


## [distancia, bucle, nodo] de los vehículos que dibujan los visuales del mundo (solo lectura).
func _collect_vehicles(w: Node, focus: Vector3) -> Array:
	var out: Array = []
	var era := current_era()
	for vis in w.get_children():
		if vis is LogisticsVisuals:
			var agents: Variant = vis.get("_agents")
			var live: Dictionary = vis.get_meta("live", {})
			if agents is Dictionary:
				for k in agents:
					var mode := str((live.get(k, {}) as Dictionary).get("mode", ""))
					var sfx: String = VEHICLE_LOOPS.get(mode, "")
					if mode == "avion":
						sfx = ""
					for m in agents[k]:
						if sfx != "" and m is Node3D and (m as Node3D).visible:
							_add_vehicle(out, m, sfx, focus)
							break
		elif vis is TransitVisuals:
			var buses: Variant = vis.get("_bus_nodes")
			if buses is Array:
				for e in buses:
					var n: Variant = (e as Dictionary).get("node")
					if n is Node3D and (n as Node3D).visible:
						_add_vehicle(out, n, "bus_loop", focus)
		elif vis is TradeVisuals:
			var markers: Variant = vis.get("markers")
			if markers is Array:
				for n in markers:
					if n is Node3D and (n as Node3D).visible:
						_add_vehicle(out, n, "cart_loop" if era == 1 else "truck_loop", focus)
	return out


func _add_vehicle(out: Array, n: Node3D, sfx: String, focus: Vector3) -> void:
	var d := n.global_position.distance_to(focus)
	if d < HEAR_RADIUS * 0.7:
		out.append([d, sfx, n])


func _follow_loops() -> void:
	for k in _loops:
		var e: Dictionary = _loops[k]
		var n: Variant = e.get("node")
		var p: AudioStreamPlayer3D = e.get("player")
		if n is Node3D and is_instance_valid(n) and p != null and is_instance_valid(p):
			p.global_position = (n as Node3D).global_position + Vector3(0, 1.0, 0)


## Agua, montaña y pueblo alrededor del punto enfocado.
func _sample_terrain(w: Node, focus: Vector3, dist: float) -> void:
	var t: Node = w.get("terrain")
	_water = 0.0
	_mount = 0.0
	if t != null and t.has_method("is_land"):
		var r := clampf(30.0 + dist * 0.35, 30.0, 120.0)
		var wet := 0
		var total := 0
		for i in range(12):
			var a := TAU * i / 12.0
			for rr: float in [r * 0.5, r]:
				var x := focus.x + cos(a) * rr
				var z := focus.z + sin(a) * rr
				total += 1
				if not bool(t.call("is_land", x, z, 0.0)):
					wet += 1
		_water = float(wet) / maxf(1.0, total)
		_sea = str(t.get("map_type")) == "costa" and _water > 0.0
		_mount = clampf((float(t.call("height_at", focus.x, focus.z)) - 30.0) / 40.0, 0.0, 1.0)
	var near := 0
	var r2 := 75.0 * 75.0
	for b in GameState.buildings:
		var dx := float(b["x"]) - focus.x
		var dz := float(b["z"]) - focus.z
		if dx * dx + dz * dz < r2:
			near += 1
			if near >= 30:
				break
	_town = clampf(near / 25.0, 0.0, 1.0)


func _ambience_targets(dist: float, inside: bool) -> void:
	for l in AMB_LAYERS:
		_amb_target[l] = 0.0
	var wt := str(GameState.weather.get("type", "despejado"))
	var rain := wt == "lluvia"
	var storm := wt == "tormenta"
	var cold := wt == "nieve" or wt == "helada"
	var far := clampf((dist - FAR_ZOOM * 0.7) / (FAR_ZOOM * 0.8), 0.0, 1.0)
	var local := (1.0 - far) * (0.35 if inside else 1.0)
	var day := 1.0 - night
	var era := current_era()
	var winter := GameState.season == "invierno"
	_amb_target["amb_general"] = far * 0.9
	_amb_target["amb_birds"] = local * day * (0.0 if rain or storm or cold else 1.0) * (0.35 if winter else 1.0) * (1.0 - _town * (0.3 + 0.2 * era))
	_amb_target["amb_crickets"] = local * night * (0.0 if rain or storm or cold or winter else 1.0)
	_amb_target["amb_wind"] = clampf(0.2 + _mount * 0.6 + (0.5 if cold else 0.0) + (0.3 if storm else 0.0) + far * 0.3, 0.0, 1.0) * (0.3 if inside else 1.0)
	_amb_target["amb_sea" if _sea else "amb_river"] = local * clampf(_water * 2.5, 0.0, 1.0)
	_amb_target["amb_town_%d" % era] = local * _town * (1.0 if day > 0.5 else 0.35)
	_amb_target["amb_rain"] = (1.0 if rain else 0.0) * (0.5 if inside else 1.0) * (1.0 - far * 0.4)
	_amb_target["amb_storm"] = (1.0 if storm else 0.0) * (0.5 if inside else 1.0) * (1.0 - far * 0.4)


func _fade_ambience(delta: float, silence: bool) -> void:
	for l in AMB_LAYERS:
		var target: float = 0.0 if silence or _muted() else float(_amb_target[l])
		var v: float = float(_amb_vol[l])
		v = move_toward(v, target, delta * 0.35)
		_amb_vol[l] = v
		var p: AudioStreamPlayer = _amb.get(l)
		if v > 0.001:
			if p == null:
				p = AudioStreamPlayer.new()
				p.bus = "Ambience"
				p.stream = stream(l)
				add_child(p)
				_amb[l] = p
			p.volume_db = linear_to_db(v)
			if not p.playing and p.stream != null:
				p.play(_rng.randf_range(0.0, 10.0))
		elif p != null and p.playing:
			p.stop()


func ambience_level(layer: String) -> float:
	return float(_amb_target.get(layer, 0.0))


func _random_events(delta: float) -> void:
	if TimeManager.speed == 0 or TimeManager.jumping:
		return
	var f := _focus()
	var focus: Vector3 = f[0]
	var dist: float = f[1]
	# Truenos durante la tormenta (2D en el bus de ambiente).
	if str(GameState.weather.get("type", "")) == "tormenta":
		_thunder_t -= delta
		if _thunder_t <= 0.0:
			_thunder_t = _rng.randf_range(7.0, 22.0)
			_play_amb_oneshot("thunder_%d" % _rng.randi_range(1, 2), _rng.randf_range(-6.0, 0.0))
	if dist > FAR_ZOOM:
		return
	var era := current_era()
	for k in _event_t:
		_event_t[k] = float(_event_t[k]) - delta
	# Tren con silbato si hay una vía férrea cerca.
	if float(_event_t["train"]) <= 0.0:
		_event_t["train"] = _rng.randf_range(45.0, 110.0)
		var rp: Variant = _near_rail(focus)
		if rp is Vector3:
			play_3d("train_whistle", rp, -2.0, 40.0)
			play_3d("train_loop", rp, -6.0, 20.0)
	# Barco con sirena en la costa (desde la era industrial).
	if float(_event_t["ship"]) <= 0.0:
		_event_t["ship"] = _rng.randf_range(60.0, 150.0)
		if _sea and era >= 2:
			play_3d("ship_horn", focus + Vector3(_rng.randf_range(-90, 90), 2.0, _rng.randf_range(-90, 90)), -3.0, 60.0)
	# Avión que pasa (época moderna).
	if float(_event_t["plane"]) <= 0.0:
		_event_t["plane"] = _rng.randf_range(80.0, 200.0)
		if era >= 3:
			play_3d("plane_pass", focus + Vector3(_rng.randf_range(-60, 60), 80.0, _rng.randf_range(-60, 60)), -4.0, 80.0)


func _near_rail(focus: Vector3) -> Variant:
	var w := _world()
	if w == null:
		return null
	for vis in w.get_children():
		if vis is TradeVisuals:
			var lines: Variant = vis.get("lines")
			if lines is Array:
				for l in lines:
					var d: Dictionary = l
					if not bool(d.get("rail", false)):
						continue
					var pts: PackedVector2Array = d.get("rail_points", PackedVector2Array())
					if pts.is_empty():
						pts = d.get("points", PackedVector2Array())
					for p in pts:
						var v := Vector3(p.x, focus.y, p.y)
						if v.distance_to(focus) < HEAR_RADIUS:
							return v
	return null


func _play_amb_oneshot(sfx_name: String, volume_db: float) -> void:
	var p := AudioStreamPlayer.new()
	p.bus = "Ambience"
	p.stream = stream(sfx_name)
	p.volume_db = volume_db
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## Campana de la iglesia a las 6, 12 y 18 h (solo a velocidades bajas).
func _on_hour(hour: int) -> void:
	if context != "game" or TimeManager.speed > 2 or TimeManager.jumping or not enabled:
		return
	var strokes := {6: 2, 12: 3, 18: 2}
	if not strokes.has(hour):
		return
	var pos := Vector3.ZERO
	var found := false
	for b in GameState.buildings:
		if str(b.get("type", "")) == "iglesia":
			pos = Vector3(float(b["x"]), 0.0, float(b["z"]))
			found = true
			break
	var w := _world()
	if w != null:
		var t: Node = w.get("terrain")
		if t != null and t.has_method("height_at"):
			pos.y = float(t.call("height_at", pos.x, pos.z)) + (10.0 if found else 4.0)
	for i in range(int(strokes[hour])):
		get_tree().create_timer(i * 2.2).timeout.connect(func(): play_3d("church_bell", pos, 0.0, 45.0))
	last_event_sfx = "church_bell"


func _muted() -> bool:
	return bool(AudioSettings.get_value("muted"))
