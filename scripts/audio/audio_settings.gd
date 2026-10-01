class_name AudioSettings
extends RefCounted
## Opciones de sonido, guardadas en user://audio.cfg junto a ui_settings.cfg y graficos.cfg
## (docs/AUDIO.md). Se aplican al iniciar (AudioManager._ready) y al mover cualquier control.
##
## API:
##   AudioSettings.get_value(clave)          valor actual (ver DEFAULTS)
##   AudioSettings.set_value(clave, valor)   guarda, aplica a los buses y avisa a AudioManager
##   AudioSettings.apply()                   vuelca volúmenes y silencio a AudioServer
##   AudioSettings.build_ui(caja)            sección «Sonido y música» para un menú de opciones

const PATH := "user://audio.cfg"
const SECTION := "audio"
## Volúmenes lineales 0..1 por bus (el deslizador muestra 0–100 %).
const VOLUME_KEYS := {"master": "Master", "music": "Music", "sfx": "SFX", "ambience": "Ambience", "ui": "UI"}
const VOLUME_LABELS := {"master": "General", "music": "Música", "sfx": "Efectos", "ambience": "Ambiente", "ui": "Interfaz"}
const DEFAULTS := {
	"master": 0.8, "music": 0.6, "sfx": 0.8, "ambience": 0.7, "ui": 0.7,
	"muted": false,
	"music_by_era": true,
	"track": "",          # "" = automática; si no, id de pista fija (AudioManager.TRACKS)
}

static var _values: Dictionary = {}
static var _loaded := false


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	_values = DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for k in DEFAULTS:
			var v: Variant = cfg.get_value(SECTION, k, DEFAULTS[k])
			if typeof(v) == typeof(DEFAULTS[k]) or (typeof(DEFAULTS[k]) == TYPE_FLOAT and typeof(v) == TYPE_INT):
				_values[k] = v
		for k in VOLUME_KEYS:
			_values[k] = clampf(float(_values[k]), 0.0, 1.0)


static func get_value(key: String) -> Variant:
	_ensure()
	return _values.get(key, DEFAULTS.get(key))


static func set_value(key: String, value: Variant) -> void:
	_ensure()
	if VOLUME_KEYS.has(key):
		value = clampf(float(value), 0.0, 1.0)
	_values[key] = value
	save()
	apply()
	var am := _manager()
	if am and am.has_method("on_settings_changed"):
		am.on_settings_changed(key)


static func save() -> void:
	_ensure()
	var cfg := ConfigFile.new()
	for k in _values:
		cfg.set_value(SECTION, k, _values[k])
	cfg.save(PATH)


## Vuelve a leer el archivo (pruebas o tras borrar user://).
static func reload() -> void:
	_loaded = false
	_ensure()


static func reset_defaults() -> void:
	_values = DEFAULTS.duplicate()
	_loaded = true


## Aplica volúmenes y silencio a los buses. Si falta algún bus lo crea (AudioManager.ensure_buses).
static func apply() -> void:
	_ensure()
	for k in VOLUME_KEYS:
		var idx := AudioServer.get_bus_index(VOLUME_KEYS[k])
		if idx < 0:
			continue
		var v := float(_values[k])
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)) if v > 0.001 else -80.0)
		AudioServer.set_bus_mute(idx, v <= 0.001)
	var m := AudioServer.get_bus_index("Master")
	if m >= 0 and bool(_values["muted"]):
		AudioServer.set_bus_mute(m, true)


static func _manager() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("AudioManager")


## Sección de opciones: deslizadores, silenciar, música según época y selector de pista.
static func build_ui(box: VBoxContainer) -> void:
	_ensure()
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 8)
	title.add_child(UIKit.icon("bell", 18, UIKit.ACCENT))
	title.add_child(UIKit.label("Sonido y música", 16, UIKit.ACCENT))
	box.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 4)
	box.add_child(grid)
	for k in VOLUME_KEYS:
		var lab := UIKit.label(VOLUME_LABELS[k], 13, UIKit.TEXT)
		lab.custom_minimum_size.x = 80
		grid.add_child(lab)
		var sl := HSlider.new()
		sl.name = "Vol_" + k
		sl.min_value = 0.0
		sl.max_value = 100.0
		sl.step = 1.0
		sl.value = float(_values[k]) * 100.0
		sl.custom_minimum_size = Vector2(260, 22)
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(sl)
		var pct := UIKit.label("%d %%" % int(sl.value), 12, UIKit.TEXT_DIM)
		pct.custom_minimum_size.x = 44
		pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(pct)
		var key: String = k
		sl.value_changed.connect(func(v: float):
			pct.text = "%d %%" % int(v)
			set_value(key, v / 100.0))
		if key == "ui" or key == "sfx":
			sl.drag_ended.connect(func(_c: bool):
				var am := _manager()
				if am:
					am.play_ui("notif_info" if key == "ui" else "money_in"))
	var mute := CheckBox.new()
	mute.name = "Mute"
	mute.text = "Silenciar todo"
	mute.button_pressed = bool(_values["muted"])
	mute.toggled.connect(func(on: bool): set_value("muted", on))
	box.add_child(mute)
	var era := CheckBox.new()
	era.name = "MusicByEra"
	era.text = "Música según la época (colonial, industrial, moderna)"
	era.button_pressed = bool(_values["music_by_era"])
	era.toggled.connect(func(on: bool): set_value("music_by_era", on))
	box.add_child(era)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var tl := UIKit.label("Pista", 13, UIKit.TEXT)
	tl.custom_minimum_size.x = 80
	row.add_child(tl)
	var ob := OptionButton.new()
	ob.name = "Track"
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.add_item("Automática (varía sola)")
	ob.set_item_metadata(0, "")
	var am := _manager()
	var tracks: Dictionary = am.TRACKS if am else {}
	var i := 1
	for id in tracks:
		ob.add_item(str(tracks[id]["title"]))
		ob.set_item_metadata(i, id)
		if str(_values["track"]) == id:
			ob.select(i)
		i += 1
	ob.tooltip_text = "Automática: cambia de pieza con fundido y según la época.\nUna pista fija se repite en bucle."
	ob.item_selected.connect(func(idx: int): set_value("track", str(ob.get_item_metadata(idx))))
	row.add_child(ob)
	var now := UIKit.label("", 12, UIKit.TEXT_FAINT)
	now.name = "NowPlaying"
	box.add_child(now)
	var upd := func():
		var m := _manager()
		if m and is_instance_valid(now):
			now.text = "Sonando: %s" % m.now_playing_title()
	upd.call()
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(upd)
	now.add_child(timer)
