class_name MainMenu
extends Control
## Menú principal: fondo ilustrado (cielo, colinas y pueblo dibujados con código), título, nueva
## partida (personaje, pueblo, dificultad con iconos, país con descripción y ventajas, tipo de mapa y
## lugar de fundación con mini-mapa), 5 ranuras de partida (continuar, nueva, renombrar, borrar),
## partidas antiguas para importar y salir.

const DIFF_ICONS := {"facil": "sprout", "normal": "shield", "dificil": "alert", "extremo": "skull"}
const DIFF_COLORS := {"facil": Color(0.4, 0.83, 0.5), "normal": Color(0.45, 0.66, 0.96), "dificil": Color(0.97, 0.72, 0.28), "extremo": Color(0.95, 0.4, 0.38)}
const RES_LABELS := {"oro": "Oro", "plata": "Plata", "carbon": "Carbón", "hierro": "Hierro", "madera": "Madera", "piedra": "Piedra",
	"tierra_fertil": "Tierra fértil", "pastos": "Pastos", "pesca": "Pesca"}

var main_box: VBoxContainer
var new_panel: PanelContainer
var load_panel: PanelContainer
var town_edit: LineEdit
var player_edit: LineEdit
var surname_edit: LineEdit
var gender_opt: OptionButton
var age_spin: SpinBox
var seed_edit: SpinBox
var map_opt: OptionButton
var desc_lbl: Label
var load_list: ItemList
var diff_ids: Array = []
var diff_idx := 1
var _diff_buttons: Array = []
var _diff_desc: Label
var map_ids: Array = []
var region_opt: OptionButton          # Fase 6: dónde fundar el pueblo
var country_opt: OptionButton         # Fase 9A: país (perfil de biomas y recursos)
var country_ids: Array = []
var world_map: WorldMap
var region_list: Array = []
var region_preview: RegionPreview
var _country_card: VBoxContainer
var _title_box: VBoxContainer
var _subtitle: Label
# Ranuras de partida
var slots_box: VBoxContainer
var continue_btn: Button
var legacy_btn: Button
var legacy_slot_opt: OptionButton
var _pending_slot := 0              # ranura donde se creará la partida nueva
var _confirm: Dictionary
var _confirm_text: Label
var _confirm_ok: Button
var _confirm_cb: Callable
var _rename: Dictionary
var _rename_edit: LineEdit
var _rename_slot := 0
var _error: Dictionary
var _error_text: Label
var _error_box: VBoxContainer


func _ready() -> void:
	theme = UIKit.make_theme()
	UIKit.hook_scale(self)
	var bg := MenuBackground.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	center.add_child(col)
	_title_box = VBoxContainer.new()
	_title_box.add_theme_constant_override("separation", 2)
	col.add_child(_title_box)
	var crown := UIKit.icon("dynasty", 46, UIKit.ACCENT)
	crown.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_title_box.add_child(crown)
	var title := UIKit.label(str(GameData.game.get("name", "Dinastía")), 68, UIKit.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_outline_color", Color(0.1, 0.07, 0.02, 0.9))
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	title.add_theme_constant_override("shadow_offset_y", 4)
	_title_box.add_child(title)
	var sub := UIKit.label(str(GameData.game.get("subtitle", "")), 18, Color(0.95, 0.92, 0.85))
	_subtitle = sub
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	sub.add_theme_constant_override("outline_size", 5)
	_title_box.add_child(sub)

	var mp := PanelContainer.new()
	mp.add_theme_stylebox_override("panel", UIKit.float_style(Color(0.07, 0.078, 0.095, 0.88), 16, 18))
	mp.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(mp)
	main_box = VBoxContainer.new()
	main_box.add_theme_constant_override("separation", 10)
	mp.add_child(main_box)
	main_box.set_meta("panel", mp)
	# Pantalla principal: 5 ranuras de partida (guardado automático en la ranura elegida).
	if DisplayServer.get_name() != "headless":
		SaveManager.auto_import_legacy()   # primera vez: partidas del sistema anterior → ranuras
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(UIKit.icon("save", 18, UIKit.ACCENT))
	var ht := UIKit.label("Tus partidas", 17, UIKit.ACCENT)
	ht.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(ht)
	head.add_child(UIKit.label("Se guardan solas en su ranura", 12, UIKit.TEXT_FAINT))
	main_box.add_child(head)
	slots_box = VBoxContainer.new()
	slots_box.add_theme_constant_override("separation", 6)
	main_box.add_child(slots_box)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	main_box.add_child(bottom)
	continue_btn = _big_button("Continuar última partida", "play", _continue_last, true)
	continue_btn.custom_minimum_size.x = 300
	bottom.add_child(continue_btn)
	legacy_btn = _big_button("Partidas antiguas", "folder", _show_load)
	legacy_btn.custom_minimum_size.x = 230
	bottom.add_child(legacy_btn)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(sp)
	var quit_b := _big_button("Salir", "exit", func(): get_tree().quit())
	quit_b.custom_minimum_size.x = 130
	bottom.add_child(quit_b)
	var ver := UIKit.label("v%s · partidas en %s" % [SaveManager.game_version(), ProjectSettings.globalize_path(SaveManager.slots_dir)], 11, UIKit.TEXT_FAINT)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ver.clip_text = true
	ver.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	ver.custom_minimum_size.x = 860
	main_box.add_child(ver)

	_build_new_panel(col)
	_build_load_panel(col)
	_build_dialogs()
	refresh_slots()
	_fit_height()
	get_viewport().size_changed.connect(_fit_height)
	UIKit.animate_in(mp, Vector2.ZERO, 0.4)


func _big_button(text: String, icon_name: String, cb: Callable, primary := false) -> Button:
	var b := UIKit.button(text, cb, 320)
	b.icon = UIIcons.tex(icon_name, 20)
	b.custom_minimum_size.y = 46
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_constant_override("h_separation", 12)
	return UIKit.primary(b) if primary else b


func _field(grid: GridContainer, text: String, icon_name: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.add_child(UIKit.icon(icon_name, 16, UIKit.TEXT_DIM))
	h.add_child(UIKit.label(text, 14, UIKit.TEXT_DIM))
	grid.add_child(h)


func _group_title(parent: Control, text: String, icon_name: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.add_child(UIKit.icon(icon_name, 18, UIKit.ACCENT))
	h.add_child(UIKit.label(text, 16, UIKit.ACCENT))
	parent.add_child(h)


func _build_new_panel(parent: Control) -> void:
	new_panel = PanelContainer.new()
	new_panel.add_theme_stylebox_override("panel", UIKit.float_style(Color(0.07, 0.078, 0.095, 0.93), 16, 18))
	new_panel.visible = false
	parent.add_child(new_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	new_panel.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 22)
	v.add_child(top)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	top.add_child(left)
	var defaults := GameState.default_settings()
	# Personaje
	_group_title(left, "Tu personaje", "character")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	left.add_child(grid)
	_field(grid, "Nombre", "character")
	player_edit = LineEdit.new()
	player_edit.text = defaults["player_name"]
	player_edit.custom_minimum_size.x = 260
	grid.add_child(player_edit)
	_field(grid, "Apellido", "family")
	surname_edit = LineEdit.new()
	surname_edit.text = defaults["player_surname"]
	grid.add_child(surname_edit)
	_field(grid, "Sexo", "population")
	gender_opt = OptionButton.new()
	gender_opt.add_item("Hombre")
	gender_opt.add_item("Mujer")
	grid.add_child(gender_opt)
	_field(grid, "Edad inicial", "calendar")
	var pc: Dictionary = GameData.game.get("player", {})
	age_spin = SpinBox.new()
	age_spin.min_value = int(pc.get("min_age", 18))
	age_spin.max_value = int(pc.get("max_age", 40))
	age_spin.value = int(defaults["player_age"])
	grid.add_child(age_spin)
	# Pueblo
	_group_title(left, "El pueblo", "town")
	var g2 := GridContainer.new()
	g2.columns = 2
	g2.add_theme_constant_override("h_separation", 12)
	g2.add_theme_constant_override("v_separation", 8)
	left.add_child(g2)
	_field(g2, "Nombre", "town")
	town_edit = LineEdit.new()
	town_edit.text = defaults["town_name"]
	town_edit.custom_minimum_size.x = 260
	g2.add_child(town_edit)
	_field(g2, "Tipo de mapa", "map")
	map_opt = OptionButton.new()
	map_ids = GameData.sorted_ids(GameData.map_types)
	for id in map_ids:
		map_opt.add_item(str(GameData.map_types[id].get("label", id)))
	map_opt.item_selected.connect(func(_i): _on_map_changed())
	g2.add_child(map_opt)
	_field(g2, "País", "globe")
	# Mapa mundial con países reales (los ficticios de la Fase 9A quedan solo para las pruebas).
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 6)
	country_opt = OptionButton.new()
	country_ids = MapSim.real_country_ids()
	if country_ids.is_empty():
		country_ids = MapSim.country_ids()
	for id in country_ids:
		var cd := MapSim.country_def(str(id))
		country_opt.add_item(str(cd.get("label", id)))
	country_opt.item_selected.connect(func(_i): _refresh_regions())
	crow.add_child(country_opt)
	crow.add_child(UIKit.button("Mapa mundial…", _open_world_map, 150))
	g2.add_child(crow)
	_field(g2, "Semilla", "star")
	seed_edit = SpinBox.new()
	seed_edit.max_value = 999999
	seed_edit.value = defaults["seed"]
	seed_edit.value_changed.connect(func(_v): _refresh_regions())
	g2.add_child(seed_edit)
	_field(g2, "Fundar en", "mountain")
	region_opt = OptionButton.new()
	region_opt.item_selected.connect(func(_i): _update_desc())
	g2.add_child(region_opt)
	# Dificultad con iconos
	_group_title(left, "Dificultad", "shield")
	var drow := HBoxContainer.new()
	drow.add_theme_constant_override("separation", 6)
	left.add_child(drow)
	diff_ids = GameData.sorted_ids(GameData.difficulties)
	diff_idx = maxi(0, diff_ids.find("normal"))
	for i in range(diff_ids.size()):
		var id := str(diff_ids[i])
		var col: Color = DIFF_COLORS.get(id, UIKit.ACCENT)
		var b := Button.new()
		b.text = str(GameData.difficulties[id].get("label", id))
		b.icon = UIIcons.tex(str(DIFF_ICONS.get(id, "shield")), 22)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(88, 64)
		b.add_theme_color_override("icon_normal_color", col)
		b.add_theme_color_override("icon_pressed_color", col.lightened(0.2))
		b.add_theme_color_override("icon_hover_color", col.lightened(0.2))
		b.add_theme_stylebox_override("pressed", UIKit._flat(Color(col, 0.2), 8, 8, 6, col, 2))
		b.add_theme_stylebox_override("hover_pressed", UIKit._flat(Color(col, 0.26), 8, 8, 6, col, 2))
		b.tooltip_text = str(GameData.difficulties[id].get("description", ""))
		var idx := i
		b.pressed.connect(func(): _select_diff(idx))
		drow.add_child(b)
		_diff_buttons.append(b)
	_diff_desc = UIKit.label("", 12, UIKit.TEXT_DIM)
	_diff_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_diff_desc.custom_minimum_size.x = 380
	left.add_child(_diff_desc)
	# Columna derecha: país y lugar
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 8)
	side.custom_minimum_size.x = 400
	top.add_child(side)
	_country_card = VBoxContainer.new()
	_country_card.add_theme_constant_override("separation", 6)
	side.add_child(_country_card)
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", 12)
	side.add_child(ph)
	region_preview = RegionPreview.new()
	ph.add_child(region_preview)
	var legend := VBoxContainer.new()
	legend.add_child(UIKit.label("Lugar de fundación", 14, UIKit.ACCENT))
	var ll := UIKit.label("● pueblo\n○ alcance a pie de la bodega\n● yacimientos", 11, UIKit.TEXT_DIM)
	legend.add_child(ll)
	ph.add_child(legend)
	desc_lbl = UIKit.label("", 12, UIKit.TEXT_DIM)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.custom_minimum_size = Vector2(400, 60)
	side.add_child(desc_lbl)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(row)
	row.add_child(_big_button("Volver", "chevron_left", _show_main))
	row.get_child(0).custom_minimum_size.x = 140
	var start := _big_button("Comenzar", "play", _start, true)
	start.custom_minimum_size.x = 200
	row.add_child(start)
	_select_diff(diff_idx)
	_on_map_changed()


func _select_diff(i: int) -> void:
	diff_idx = i
	for k in range(_diff_buttons.size()):
		(_diff_buttons[k] as Button).set_pressed_no_signal(k == i)
	_update_desc()


## Fase 9A: al cambiar el tipo de mapa se propone el país que mejor le va.
func _on_map_changed() -> void:
	if country_opt.selected < 0 or _country() == "":
		country_opt.select(maxi(0, country_ids.find(MapSim.DEFAULT_REAL)))
	_refresh_regions()


## Mapa mundial: elegir el país de inicio con clic sobre el mapa real.
func _open_world_map() -> void:
	if world_map == null:
		world_map = WorldMap.new()
		world_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		world_map.selected = _country()
		add_child(world_map)
		world_map.chosen.connect(func(iso: String):
			var i := country_ids.find(iso)
			if i >= 0:
				country_opt.select(i)
				_refresh_regions()
			world_map.visible = false)
	world_map.visible = true
	world_map.select(_country())


func _country() -> String:
	return str(country_ids[country_opt.selected]) if not country_ids.is_empty() and country_opt.selected >= 0 else ""


## Lugares candidatos para fundar según tipo de mapa y semilla (Fase 6).
func _refresh_regions() -> void:
	var prev := region_opt.selected
	region_list = RegionSim.candidates(str(map_ids[map_opt.selected]), int(seed_edit.value), _country())
	region_opt.clear()
	for r in region_list:
		region_opt.add_item(str(r.get("name", r.get("label", ""))))
	region_opt.select(clampi(prev, 0, region_list.size() - 1))
	_update_desc()


func _update_desc() -> void:
	if map_opt == null or _diff_desc == null:
		return
	var d: Dictionary = GameData.difficulties[diff_ids[diff_idx]]
	var m: Dictionary = GameData.map_types[map_ids[map_opt.selected]]
	_diff_desc.text = "%s · Dinero inicial %s · %d ciudadanos · enfermedades ×%s · precios ×%s · eventos ×%s" % [
		d.get("description", ""), Fmt.money(float(d.get("start_money", 0))), int(d.get("start_citizens", 0)),
		String.num(float(d.get("disease_mult", 1)), 1), String.num(float(d.get("price_mult", 1)), 2), String.num(float(d.get("event_freq_mult", 1)), 1)]
	desc_lbl.text = "%s: %s" % [m.get("label", ""), m.get("description", "")]
	if not region_list.is_empty() and region_opt.selected >= 0:
		var r: Dictionary = region_list[region_opt.selected]
		desc_lbl.text += "\n\n%s: %s\nRecursos: %s" % [r.get("name", ""), r.get("description", ""), RegionSim.strengths_text(r)]
		var cd := MapSim.country_def(_country())
		desc_lbl.text += "\n\nPaís %s: %s" % [cd.get("label", ""), cd.get("description", "")]
		region_preview.show_region(str(map_ids[map_opt.selected]), int(seed_edit.value), r)
	_update_country_card()


## Tarjeta del país: nombre, inspiración, descripción y ventajas/desventajas en recursos.
func _update_country_card() -> void:
	UIKit.clear(_country_card)
	var cd := MapSim.country_def(_country())
	if cd.is_empty():
		return
	var c := UIKit.card(UIKit.ACCENT, 10)
	_country_card.add_child(c["panel"])
	var v: VBoxContainer = c["box"]
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	v.add_child(h)
	h.add_child(UIKit.icon("globe", 22, UIKit.ACCENT))
	var n := UIKit.label(str(cd.get("label", "")), 20, UIKit.ACCENT)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(n)
	var cur: Dictionary = cd.get("currency", {})
	if not cur.is_empty():
		h.add_child(UIKit.chip("%s (%s)" % [cur.get("name", ""), cur.get("symbol", "")], UIKit.TEXT_DIM, "money"))
	v.add_child(UIKit.label(str(cd.get("inspiration", "")), 11, UIKit.TEXT_FAINT))
	var dl := UIKit.label(str(cd.get("description", "")), 13, UIKit.TEXT)
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl.custom_minimum_size.x = 370
	v.add_child(dl)
	var res: Dictionary = cd.get("resources", {})
	var plus := UIKit.flow(4, 4)
	var minus := UIKit.flow(4, 4)
	for k in res:
		var mult := float(res[k])
		var lab := "%s ×%s" % [RES_LABELS.get(k, str(k).capitalize()), String.num(mult, 1).replace(".", ",")]
		if mult >= 1.15:
			plus.add_child(UIKit.chip(lab, UIKit.GOOD, "trend_up", 11))
		elif mult <= 0.85:
			minus.add_child(UIKit.chip(lab, UIKit.BAD, "trend_down", 11))
	if plus.get_child_count() > 0:
		v.add_child(UIKit.label("Ventajas", 11, UIKit.GOOD))
		v.add_child(plus)
	if minus.get_child_count() > 0:
		v.add_child(UIKit.label("Desventajas", 11, UIKit.BAD))
		v.add_child(minus)
	var infl := float(cd.get("base_inflation", 0.0))
	if infl > 0.0:
		v.add_child(UIKit.chip("Inflación base %s/año" % Fmt.pct_1(infl * 100.0), UIKit.WARN if infl > 0.045 else UIKit.TEXT_DIM, "inflation", 11))


## Panel "Partidas antiguas": partidas del sistema anterior (saves/, nombres libres) para importar a
## una ranura libre. Los archivos originales no se tocan.
func _build_load_panel(parent: Control) -> void:
	load_panel = PanelContainer.new()
	load_panel.add_theme_stylebox_override("panel", UIKit.float_style(Color(0.07, 0.078, 0.095, 0.93), 16, 18))
	load_panel.visible = false
	parent.add_child(load_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	load_panel.add_child(v)
	_group_title(v, "Partidas antiguas", "folder")
	var note := UIKit.label("Partidas guardadas con versiones anteriores del juego. Al importarlas se copian a una ranura (el archivo original se conserva).", 12, UIKit.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 560
	v.add_child(note)
	load_list = ItemList.new()
	load_list.custom_minimum_size = Vector2(560, 280)
	load_list.item_activated.connect(func(_i): _load_selected())
	v.add_child(load_list)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	row.add_child(_big_button("Volver", "chevron_left", _show_main))
	row.add_child(UIKit.label("Importar a:", 14, UIKit.TEXT_DIM))
	legacy_slot_opt = OptionButton.new()
	legacy_slot_opt.custom_minimum_size.x = 150
	row.add_child(legacy_slot_opt)
	row.add_child(_big_button("Importar", "save", _load_selected, true))


func _build_dialogs() -> void:
	_confirm = UIKit.modal(self, "Confirmar", Vector2(440, 0), "alert")
	_confirm_text = UIKit.label("", 14)
	_confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_text.custom_minimum_size.x = 400
	_confirm["body"].add_child(_confirm_text)
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 8)
	crow.alignment = BoxContainer.ALIGNMENT_END
	_confirm["body"].add_child(crow)
	crow.add_child(UIKit.button("Cancelar", func(): _confirm["root"].visible = false, 120))
	_confirm_ok = UIKit.button("Aceptar", func():
		_confirm["root"].visible = false
		_confirm_cb.call(), 150)
	crow.add_child(_confirm_ok)

	_rename = UIKit.modal(self, "Renombrar partida", Vector2(420, 0), "save")
	_rename_edit = LineEdit.new()
	_rename_edit.max_length = 48
	_rename_edit.placeholder_text = "Nombre de la partida (vacío = pueblo y personaje)"
	_rename_edit.text_submitted.connect(func(_t): _do_rename())
	_rename["body"].add_child(_rename_edit)
	var rrow := HBoxContainer.new()
	rrow.add_theme_constant_override("separation", 8)
	rrow.alignment = BoxContainer.ALIGNMENT_END
	_rename["body"].add_child(rrow)
	rrow.add_child(UIKit.button("Cancelar", func(): _rename["root"].visible = false, 120))
	rrow.add_child(UIKit.primary(UIKit.button("Guardar nombre", _do_rename, 150)))

	_error = UIKit.modal(self, "No se pudo cargar la partida", Vector2(500, 0), "alert")
	_error_text = UIKit.label("", 13)
	_error_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_text.custom_minimum_size.x = 460
	_error["body"].add_child(_error_text)
	_error_box = VBoxContainer.new()
	_error_box.add_theme_constant_override("separation", 6)
	_error["body"].add_child(_error_box)


## Con poca altura (1280×720) se ocultan el subtítulo y la corona para que quepan las 5 ranuras.
func _fit_height() -> void:
	if _title_box == null:
		return
	var h := get_viewport_rect().size.y
	_subtitle.visible = h >= 820.0
	_title_box.get_child(0).visible = h >= 860.0


# --- Ranuras ---------------------------------------------------------------------------------------

func refresh_slots() -> void:
	if slots_box == null:
		return
	UIKit.clear(slots_box)
	for info in SaveManager.list_slots():
		slots_box.add_child(_slot_row(info))
	continue_btn.disabled = SaveManager.last_slot() == 0
	var n := SaveManager.list_legacy().size()
	legacy_btn.text = "Partidas antiguas (%d)" % n
	legacy_btn.visible = n > 0


static func play_time_text(sec: float) -> String:
	var m := int(sec / 60.0)
	if m < 60:
		return "%d min" % m
	return "%d h %02d min" % [m / 60, m % 60]


## "2026-09-26T14:03:10" → "26/09/2026 14:03".
static func saved_at_text(iso: String) -> String:
	if iso.length() < 16:
		return iso
	return "%s/%s/%s %s" % [iso.substr(8, 2), iso.substr(5, 2), iso.substr(0, 4), iso.substr(11, 5)]


static func slot_title(info: Dictionary) -> String:
	var meta: Dictionary = info.get("meta", {})
	if str(info.get("name", "")) != "":
		return str(info["name"])
	var t := str(meta.get("town", ""))
	var p := str(meta.get("player", ""))
	return "%s — %s" % [t, p] if p != "" else (t if t != "" else "Partida")


static func thumb_texture(meta: Dictionary) -> Texture2D:
	var png = meta.get("thumbnail", PackedByteArray())
	if not (png is PackedByteArray) or (png as PackedByteArray).is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(png) != OK:
		return null
	return ImageTexture.create_from_image(img)


func _slot_row(info: Dictionary) -> Control:
	var slot := int(info["slot"])
	var status := str(info["status"])
	if status == "empty":
		var b := Button.new()
		b.text = "Ranura %d   ·   Vacío — Nueva partida" % slot
		b.icon = UIIcons.tex("plus", 20)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(880, 58)
		b.add_theme_font_size_override("font_size", 16)
		b.add_theme_color_override("font_color", UIKit.TEXT_DIM)
		b.add_theme_constant_override("h_separation", 14)
		b.add_theme_stylebox_override("normal", UIKit._flat(Color(1, 1, 1, 0.025), 10, 16, 6, Color(1, 1, 1, 0.12), 1))
		b.add_theme_stylebox_override("hover", UIKit._flat(Color(UIKit.ACCENT, 0.1), 10, 16, 6, Color(UIKit.ACCENT, 0.5), 1))
		b.pressed.connect(func(): _new_in(slot))
		return b
	var meta: Dictionary = info.get("meta", {})
	var damaged := status == "damaged"
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIKit._flat(Color(0.12, 0.13, 0.16, 0.92), 10, 10, 8, Color(UIKit.BAD, 0.6) if damaged else Color(UIKit.ACCENT, 0.22), 1))
	p.custom_minimum_size.x = 880
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	p.add_child(h)
	# Miniatura
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UIKit._flat(Color(0.05, 0.06, 0.08), 6, 0, 0, UIKit.BORDER, 1))
	frame.custom_minimum_size = Vector2(144, 81)
	h.add_child(frame)
	var tex := thumb_texture(meta)
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.custom_minimum_size = Vector2(144, 81)
		frame.add_child(tr)
	else:
		var ic := UIKit.icon("dynasty", 34, Color(UIKit.ACCENT, 0.45))
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		frame.add_child(ic)
	# Datos
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var t1 := HBoxContainer.new()
	t1.add_theme_constant_override("separation", 8)
	v.add_child(t1)
	t1.add_child(UIKit.chip("Ranura %d" % slot, UIKit.TEXT_DIM, "", 11))
	var title := UIKit.label(slot_title(info), 18, UIKit.ACCENT)
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t1.add_child(title)
	var line2 := []
	if str(info.get("name", "")) != "":
		line2.append("%s · %s" % [meta.get("town", ""), meta.get("player", "")])
	elif str(meta.get("player", "")) == "":
		line2.append(str(meta.get("town", "")))
	if str(meta.get("country", "")) != "":
		line2.append(str(meta["country"]))
	line2.append(str(meta.get("date", "")))
	v.add_child(UIKit.label("  ·  ".join(line2.filter(func(x): return str(x) != "")), 13, UIKit.TEXT))
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 6)
	v.add_child(chips)
	chips.add_child(UIKit.chip(Fmt.money(float(meta.get("money", 0.0))), UIKit.ACCENT, "money", 11))
	chips.add_child(UIKit.chip("%s hab." % Fmt.thousands(int(meta.get("population", 0))), UIKit.ACCENT_2, "population", 11))
	chips.add_child(UIKit.chip("Jugado %s" % play_time_text(float(meta.get("play_seconds", 0.0))), UIKit.TEXT_DIM, "realtime", 11))
	chips.add_child(UIKit.chip("Guardado %s" % saved_at_text(str(info.get("saved_at", ""))), UIKit.TEXT_DIM, "save", 11))
	if damaged:
		var el := UIKit.label("Partida dañada (%s). No se ha borrado. %s" % [info.get("error", ""), "Hay copias de respaldo." if not (info["backups"] as Array).is_empty() or str(info.get("source", "")) != "" else "No hay copias legibles."], 11, UIKit.BAD)
		el.clip_text = true
		el.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		el.custom_minimum_size.x = 420
		v.add_child(el)
	elif SaveMigrations.version_of(info) < SaveMigrations.CURRENT:
		v.add_child(UIKit.label("Guardada con una versión anterior: se actualizará al cargarla (con copia de respaldo).", 11, UIKit.INFO))
	# Botones
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	h.add_child(g)
	var cont := UIKit.primary(UIKit.button("Cargar respaldo" if damaged else "Continuar", func(): continue_slot(slot), 124))
	cont.icon = UIIcons.tex("play", 16)
	g.add_child(cont)
	var nb := UIKit.button("Nueva", func(): _new_in(slot), 104)
	nb.icon = UIIcons.tex("plus", 16)
	g.add_child(nb)
	var rb := UIKit.button("Renombrar", func(): _open_rename(slot), 124)
	rb.icon = UIIcons.tex("edit", 16)
	g.add_child(rb)
	var db := UIKit.danger(UIKit.button("Borrar", func(): _ask_delete(slot), 104))
	db.icon = UIIcons.tex("trash", 16)
	g.add_child(db)
	return p


func _ask(title: String, text: String, ok_text: String, cb: Callable, danger := false) -> void:
	_confirm["title"].text = title
	_confirm_text.text = text
	_confirm_ok.text = ok_text
	_confirm_ok.remove_theme_stylebox_override("normal")
	if danger:
		UIKit.danger(_confirm_ok)
	else:
		UIKit.primary(_confirm_ok)
	_confirm_cb = cb
	_confirm["root"].visible = true


func _new_in(slot: int) -> void:
	var info := SaveManager.slot_info(slot)
	if info["status"] == "empty":
		_pending_slot = slot
		_show_new()
		return
	_ask("Nueva partida en la ranura %d" % slot,
		"La ranura %d tiene «%s». Si empiezas una partida nueva aquí, la anterior se reemplazará (quedará solo como copia de respaldo hasta los siguientes guardados).\n\n¿Seguro?" % [slot, slot_title(info)],
		"Empezar de nuevo", func():
			_pending_slot = slot
			_show_new(), true)


func _ask_delete(slot: int) -> void:
	var info := SaveManager.slot_info(slot)
	_ask("Borrar partida", "¿Borrar «%s» de la ranura %d? Se borran también sus copias de respaldo. No se puede deshacer." % [slot_title(info), slot],
		"Borrar", func():
			SaveManager.delete_slot(slot)
			refresh_slots(), true)


func _open_rename(slot: int) -> void:
	_rename_slot = slot
	var info := SaveManager.slot_info(slot)
	_rename_edit.text = str(info.get("name", ""))
	if _rename_edit.text == "":
		_rename_edit.text = slot_title(info)
	_rename["root"].visible = true
	_rename_edit.grab_focus()
	_rename_edit.select_all()


func _do_rename() -> void:
	SaveManager.rename_slot(_rename_slot, _rename_edit.text)
	_rename["root"].visible = false
	refresh_slots()


func _continue_last() -> void:
	var s := SaveManager.last_slot()
	if s > 0:
		continue_slot(s)


## Carga una ranura (con respaldo automático si la principal está dañada) y entra al juego.
func continue_slot(slot: int) -> void:
	var r := SaveManager.load_slot(slot)
	if r["ok"]:
		if bool(r.get("used_backup", false)):
			SaveManager.pending_notice = "La partida principal estaba dañada: se cargó la copia de respaldo (%s). El archivo dañado se conserva." % str(r["source"]).get_file()
		elif int(r.get("from_version", SaveMigrations.CURRENT)) < SaveMigrations.CURRENT:
			SaveManager.pending_notice = "Partida actualizada al formato nuevo. Copia de la versión anterior en slot_%d.v%d.backup." % [slot, int(r["from_version"])]
		_enter_game()
		return
	_show_load_error(slot, str(r["error"]))


func _show_load_error(slot: int, err: String) -> void:
	_error_text.text = "La partida de la ranura %d no se pudo cargar. No se ha borrado ni modificado.\n\nDetalle: %s" % [slot, err]
	UIKit.clear(_error_box)
	for f in SaveManager._candidates(slot).slice(1):
		if not FileAccess.file_exists(f):
			continue
		var h := SaveManager.read_header(f)
		var path: String = f
		var b := UIKit.button("Cargar copia %s (%s)" % [f.get_extension(), saved_at_text(str(h["data"].get("saved_at", ""))) if h["ok"] else "ilegible"], func():
			var r := SaveManager.load_file(path, slot)
			if r["ok"]:
				_error["root"].visible = false
				_enter_game()
			else:
				_error_text.text += "\n%s: %s" % [path.get_file(), r["error"]])
		b.disabled = not h["ok"]
		_error_box.add_child(b)
	_error_box.add_child(UIKit.button("Cerrar", func(): _error["root"].visible = false))
	_error["root"].visible = true


func _enter_game() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _show_main() -> void:
	_pending_slot = 0
	main_box.get_meta("panel").visible = true
	_title_box.visible = true
	new_panel.visible = false
	load_panel.visible = false
	refresh_slots()


func _show_new() -> void:
	if _pending_slot == 0:
		_pending_slot = SaveManager.first_empty_slot()
	main_box.get_meta("panel").visible = false
	_title_box.visible = false
	new_panel.visible = true
	UIKit.pop_in(new_panel)


## Partidas antiguas (sistema anterior) para importar a una ranura libre.
func _show_load() -> void:
	main_box.get_meta("panel").visible = false
	load_panel.visible = true
	UIKit.pop_in(load_panel)
	load_list.clear()
	for s in SaveManager.list_legacy():
		var sm: Dictionary = s["summary"]
		var idx := load_list.add_item("%s — %s — %s · pobl. %d   [%s]" % [s["slot"], sm.get("town", ""), sm.get("date", ""), int(sm.get("population", 0)), saved_at_text(str(s["saved_at"]))], UIIcons.tex("save", 16))
		load_list.set_item_metadata(idx, s["slot"])
	if load_list.item_count == 0:
		load_list.add_item("No hay partidas antiguas por importar", null, false)
	legacy_slot_opt.clear()
	for i in range(1, SaveManager.SLOT_COUNT + 1):
		if not SaveManager.slot_exists(i):
			legacy_slot_opt.add_item("Ranura %d" % i, i)
	if legacy_slot_opt.item_count == 0:
		legacy_slot_opt.add_item("Sin ranuras libres", 0)
		legacy_slot_opt.disabled = true
	else:
		legacy_slot_opt.disabled = false


func _load_selected() -> void:
	var sel := load_list.get_selected_items()
	if sel.is_empty() or load_list.get_item_metadata(sel[0]) == null:
		return
	var slot := legacy_slot_opt.get_selected_id()
	if slot <= 0:
		return
	if SaveManager.import_legacy(str(load_list.get_item_metadata(sel[0])), slot):
		_show_main()
	else:
		_show_load_error(slot, SaveManager.last_error)


func _start() -> void:
	if _pending_slot == 0:
		_pending_slot = SaveManager.first_empty_slot()
	SaveManager.begin_slot(_pending_slot)
	GameState.new_game({
		"town_name": town_edit.text.strip_edges() if town_edit.text.strip_edges() != "" else "San Rafael",
		"player_name": player_edit.text.strip_edges() if player_edit.text.strip_edges() != "" else "Sebastián",
		"player_surname": surname_edit.text.strip_edges() if surname_edit.text.strip_edges() != "" else "Cuadros",
		"player_gender": "F" if gender_opt.selected == 1 else "M",
		"player_age": int(age_spin.value),
		"difficulty": diff_ids[diff_idx],
		"map_type": map_ids[map_opt.selected],
		"seed": int(seed_edit.value),
		"country_id": _country(),
		"region": str(region_list[region_opt.selected].get("id", "")) if not region_list.is_empty() else "",
	})
	if _pending_slot > 0:
		SaveManager.rename_slot(_pending_slot, "")
		SaveManager.save_slot(_pending_slot, "nueva")
		SaveManager.save_soon(3.0)   # con la miniatura del mundo, ya dentro del juego
	_enter_game()
