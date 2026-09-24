class_name Hud
extends CanvasLayer
## Interfaz de juego: barra superior, controles de tiempo, notificaciones,
## paneles de ciudadano/edificio, listas y menús (pausa, guardar, cargar, salto x4).

signal follow_requested

const TOAST_SECONDS := 6.0
const MAX_TOASTS := 5

var root: Control
var money_lbl: Label
var pop_lbl: Label
var happy_lbl: Label
var health_lbl: Label
var date_lbl: Label
var weather_lbl: Label
var player_lbl: Label
var speed_buttons: Array[Button] = []
var toasts: VBoxContainer
var info_panel: PanelContainer
var info_text: RichTextLabel
var info_follow_btn: Button
var info_mode := ""       # "citizen" | "building"
var info_id := -1

var pause_modal: Dictionary
var save_modal: Dictionary
var load_modal: Dictionary
var jump_modal: Dictionary
var progress_modal: Dictionary
var report_modal: Dictionary
var population_modal: Dictionary
var log_modal: Dictionary
var gameover_modal: Dictionary
var save_name: LineEdit
var load_list: ItemList
var pop_list: ItemList
var pop_ids: Array = []
var log_text: RichTextLabel
var progress_bar: ProgressBar
var report_text: RichTextLabel
var _speed_before_menu := 0
var _refresh := 0.0


func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIKit.make_theme()
	add_child(root)
	_build_top_bar()
	_build_side_menu()
	_build_toasts()
	_build_info_panel()
	_build_modals()
	EventBus.notification_posted.connect(_on_notification)
	EventBus.speed_changed.connect(_on_speed_changed)
	EventBus.citizen_selected.connect(_on_citizen_selected)
	EventBus.building_selected.connect(_on_building_selected)
	EventBus.jump_started.connect(_on_jump_started)
	EventBus.jump_progress.connect(func(r): progress_bar.value = r * 100.0)
	EventBus.jump_finished.connect(_on_jump_finished)
	EventBus.player_died.connect(_on_player_died)
	_on_speed_changed(TimeManager.speed)
	_update_top_bar()
	if not GameState.running and not GameState.player.get("alive", true):
		_on_player_died()


# --- Barra superior -----------------------------------------------------------

func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.BG, 0, 8))
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	root.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	bar.add_child(row)
	row.add_child(UIKit.label(str(GameState.settings.get("town_name", "")), 18, UIKit.ACCENT))
	money_lbl = _stat(row)
	pop_lbl = _stat(row)
	happy_lbl = _stat(row)
	health_lbl = _stat(row)
	player_lbl = _stat(row)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	weather_lbl = _stat(row)
	date_lbl = _stat(row)
	date_lbl.custom_minimum_size.x = 250
	date_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var speeds := HBoxContainer.new()
	speeds.add_theme_constant_override("separation", 4)
	row.add_child(speeds)
	var labels := ["II", "x1", "x2", "x3", "x4"]
	var tips := ["Pausa (Espacio)", "1 seg = 1 hora (1)", "1 seg = 1 día (2)", "1 seg = 1 semana (3)", "Saltar 2, 5 o 10 años (4)"]
	for i in range(labels.size()):
		var idx := i
		var b := UIKit.button(labels[i], func(): _on_speed_button(idx), 42)
		b.tooltip_text = tips[i]
		b.toggle_mode = i < 4
		speeds.add_child(b)
		speed_buttons.append(b)


func _stat(parent: Control) -> Label:
	var l := UIKit.label("", 15)
	parent.add_child(l)
	return l


func _update_top_bar() -> void:
	money_lbl.text = "Dinero: " + Fmt.money(GameState.money)
	pop_lbl.text = "Población: %d" % GameState.citizens.size()
	happy_lbl.text = "Felicidad: " + Fmt.pct(GameState.avg_happiness())
	health_lbl.text = "Salud: " + Fmt.pct(GameState.avg_health())
	var p := GameState.player
	player_lbl.text = "%s, %d años" % [p.get("name", ""), GameState.player_age()]
	var season_label := str(WeatherSim.season_data(GameState).get("label", ""))
	var w := WeatherSim.weather_data(GameState)
	weather_lbl.text = "%s · %s %d°C" % [season_label, w.get("label", ""), int(GameState.weather.get("temp", 0))]
	date_lbl.text = TimeManager.date_string(true)


func _on_speed_button(i: int) -> void:
	if i == 4:
		_open_jump()
	else:
		TimeManager.set_speed(i)


func _on_speed_changed(s: int) -> void:
	for i in range(4):
		speed_buttons[i].set_pressed_no_signal(i == s)


# --- Menú lateral -------------------------------------------------------------------

func _build_side_menu() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(12, 60)
	box.add_theme_constant_override("separation", 6)
	root.add_child(box)
	box.add_child(UIKit.button("Población", _open_population, 150))
	box.add_child(UIKit.button("Notificaciones", _open_log, 150))
	box.add_child(UIKit.button("Menú (Esc)", _open_pause, 150))
	box.add_child(HSeparator.new())
	for entry in [["Mis Empresas", 2], ["Gobierno", 5], ["Investigación", 4], ["Finanzas", 3]]:
		var b := UIKit.button(entry[0], func(): pass, 150)
		b.disabled = true
		b.tooltip_text = "Disponible en la Fase %d" % entry[1]
		box.add_child(b)


# --- Notificaciones -----------------------------------------------------------------

func _build_toasts() -> void:
	toasts = VBoxContainer.new()
	toasts.anchor_left = 1.0
	toasts.anchor_right = 1.0
	toasts.offset_left = -372
	toasts.offset_right = -12
	toasts.offset_top = 58
	toasts.add_theme_constant_override("separation", 6)
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toasts)


func _on_notification(entry: Dictionary) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.1, 0.11, 0.13, 0.88), 6, 8))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UIKit.label(str(entry["text"]), 14, UIKit.CATEGORY_COLORS.get(entry["category"], Color.WHITE))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 340
	p.add_child(l)
	toasts.add_child(p)
	while toasts.get_child_count() > MAX_TOASTS:
		var old := toasts.get_child(0)
		toasts.remove_child(old)
		old.queue_free()
	var tw := p.create_tween()
	tw.tween_interval(TOAST_SECONDS)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)


# --- Panel de información (ciudadano / edificio) -----------------------------

func _build_info_panel() -> void:
	info_panel = PanelContainer.new()
	info_panel.anchor_left = 1.0
	info_panel.anchor_right = 1.0
	info_panel.anchor_top = 1.0
	info_panel.anchor_bottom = 1.0
	info_panel.offset_left = -392
	info_panel.offset_right = -12
	info_panel.offset_top = -452
	info_panel.offset_bottom = -12
	info_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	info_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	info_panel.visible = false
	root.add_child(info_panel)
	var v := VBoxContainer.new()
	info_panel.add_child(v)
	info_text = RichTextLabel.new()
	info_text.bbcode_enabled = true
	info_text.fit_content = false
	info_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_text.custom_minimum_size = Vector2(360, 360)
	info_text.meta_clicked.connect(_on_meta_clicked)
	v.add_child(info_text)
	var row := HBoxContainer.new()
	v.add_child(row)
	info_follow_btn = UIKit.button("Seguir con cámara", func(): follow_requested.emit())
	row.add_child(info_follow_btn)
	row.add_child(UIKit.button("Cerrar", func(): EventBus.citizen_selected.emit(-1)))


func _on_citizen_selected(id: int) -> void:
	if id < 0:
		if info_mode == "citizen" or info_mode == "building":
			info_panel.visible = false
			info_mode = ""
		return
	info_mode = "citizen"
	info_id = id
	info_panel.visible = true
	info_follow_btn.visible = true
	_refresh_info()


func _on_building_selected(id: int) -> void:
	info_mode = "building"
	info_id = id
	info_panel.visible = true
	info_follow_btn.visible = false
	_refresh_info()


func _on_meta_clicked(meta) -> void:
	var id := int(str(meta))
	if GameState.citizens.has(id):
		EventBus.citizen_selected.emit(id)
		var world := get_parent()
		if world.has_method("focus_citizen"):
			world.focus_citizen(id)


func _link(id: int) -> String:
	if GameState.citizens.has(id):
		return "[url=%d]%s[/url]" % [id, GameState.citizens[id].full_name()]
	return "[color=#999]%s[/color]" % GameState.person_name(id)


func _bar(v: float) -> String:
	var col := "#6c6" if v >= 60 else ("#dc4" if v >= 35 else "#e55")
	return "[color=%s]%s[/color]" % [col, Fmt.pct(v)]


func _refresh_info() -> void:
	if info_mode == "citizen":
		if not GameState.citizens.has(info_id):
			info_panel.visible = false
			return
		info_text.text = _citizen_text(GameState.citizens[info_id])
	elif info_mode == "building":
		info_text.text = _building_text(info_id)


func _citizen_text(c: Citizen) -> String:
	var today := GameState.today()
	var s := "[font_size=20][color=#edc259]%s[/color][/font_size]\n" % c.full_name()
	s += "%s · %d años\n\n" % ["Mujer" if c.gender == "F" else "Hombre", c.age_years(today)]
	s += "Salud: %s%s\n" % [_bar(c.health), "  [color=#e88](enfermo)[/color]" if c.sick else ""]
	s += "Felicidad: %s\n" % _bar(c.happiness)
	s += "Necesidades cubiertas: %s\n" % _bar(c.needs_met * 100.0)
	s += "Dinero: %s   Deudas: %s\n" % [Fmt.money(c.money), Fmt.money(c.debt)]
	s += "Trabajo: %s\n" % (c.job if c.job != "" else "Subsistencia (sin empleo)")
	s += "Educación: %s   Experiencia: %.1f años\n\n" % [GameData.education_label(c.education), c.experience]
	s += "[b]Habilidades[/b]\n"
	var keys := c.skills.keys()
	keys.sort_custom(func(a, b): return float(c.skills[a]) > float(c.skills[b]))
	for k in keys:
		s += "  %s: %d\n" % [GameData.skill_label(k), int(c.skills[k])]
	s += "\n[b]Familia[/b]\n"
	s += "  Cónyuge: %s\n" % (_link(c.spouse_id) if c.spouse_id >= 0 else "—")
	if not c.parent_ids.is_empty():
		s += "  Padres: %s\n" % ", ".join(c.parent_ids.map(func(p): return _link(p)))
	if not c.children_ids.is_empty():
		s += "  Hijos: %s\n" % ", ".join(c.children_ids.map(func(ch): return _link(ch)))
	var home := GameState.get_building(c.home_id)
	s += "\nVivienda: %s" % ("Sin hogar" if home.is_empty() else "Choza #%d" % c.home_id)
	return s


func _building_text(id: int) -> String:
	var b := GameState.get_building(id)
	if b.is_empty():
		return ""
	var label := str(GameData.buildings.get(b["type"], {}).get("label", b["type"]))
	var res := GameState.residents_of(id)
	var s := "[font_size=20][color=#edc259]%s #%d[/color][/font_size]\n" % [label, id]
	s += "Propietario: %s\n" % ("El pueblo" if b.get("owner") == "pueblo" else str(b.get("owner")))
	s += "Ocupación: %d / %d\n\n[b]Residentes[/b]\n" % [res.size(), int(b.get("capacity", 6))]
	for c in res:
		s += "  %s (%d)\n" % [_link(c.id), c.age_years(GameState.today())]
	if res.is_empty():
		s += "  Vacía\n"
	s += "\n[color=#999]Gestión de edificios y construcción: Fase 2.[/color]"
	return s


# --- Modales ------------------------------------------------------------------------------

func _build_modals() -> void:
	# Pausa
	pause_modal = UIKit.modal(root, "Menú")
	var pb: VBoxContainer = pause_modal["body"]
	pb.add_child(UIKit.button("Continuar", _close_pause))
	pb.add_child(UIKit.button("Guardar partida", func(): _close(pause_modal); _open_save()))
	pb.add_child(UIKit.button("Cargar partida", func(): _close(pause_modal); _open_load()))
	pb.add_child(UIKit.button("Menú principal", _to_main_menu))
	pb.add_child(UIKit.button("Salir del juego", func(): get_tree().quit()))
	var controls := UIKit.label("Cámara: WASD/flechas o clic derecho para mover · Q/E o botón central para rotar · rueda o pellizco para zoom · Espacio pausa · 1-4 velocidades", 13, UIKit.TEXT_DIM)
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.custom_minimum_size.x = 420
	pb.add_child(controls)

	# Guardar
	save_modal = UIKit.modal(root, "Guardar partida")
	var sb: VBoxContainer = save_modal["body"]
	sb.add_child(UIKit.label("Nombre de la partida:"))
	save_name = LineEdit.new()
	sb.add_child(save_name)
	var srow := HBoxContainer.new()
	sb.add_child(srow)
	srow.add_child(UIKit.button("Guardar", _do_save, 120))
	srow.add_child(UIKit.button("Cancelar", func(): _close(save_modal), 120))

	# Cargar
	load_modal = UIKit.modal(root, "Cargar partida", Vector2(520, 0))
	var lb: VBoxContainer = load_modal["body"]
	load_list = ItemList.new()
	load_list.custom_minimum_size = Vector2(480, 260)
	lb.add_child(load_list)
	var lrow := HBoxContainer.new()
	lb.add_child(lrow)
	lrow.add_child(UIKit.button("Cargar", _do_load, 120))
	lrow.add_child(UIKit.button("Borrar", _do_delete, 120))
	lrow.add_child(UIKit.button("Cancelar", func(): _close(load_modal), 120))

	# Salto x4
	jump_modal = UIKit.modal(root, "Avance rápido (x4)")
	var jb: VBoxContainer = jump_modal["body"]
	var jl := UIKit.label("Se simulará el periodo de forma resumida y al final verás un reporte.", 14, UIKit.TEXT_DIM)
	jl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	jb.add_child(jl)
	var jrow := HBoxContainer.new()
	jrow.add_theme_constant_override("separation", 8)
	jb.add_child(jrow)
	for y in GameData.game.get("jump_options_years", [2, 5, 10]):
		var years := int(y)
		jrow.add_child(UIKit.button("%d años" % years, func(): _close(jump_modal); TimeManager.start_jump(years), 110))
	jb.add_child(UIKit.button("Cancelar", func(): _close(jump_modal)))

	# Progreso
	progress_modal = UIKit.modal(root, "Simulando…")
	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(420, 26)
	progress_modal["body"].add_child(progress_bar)

	# Reporte
	report_modal = UIKit.modal(root, "Reporte del periodo", Vector2(560, 0))
	report_text = RichTextLabel.new()
	report_text.bbcode_enabled = true
	report_text.custom_minimum_size = Vector2(520, 380)
	report_modal["body"].add_child(report_text)
	report_modal["body"].add_child(UIKit.button("Continuar", func(): _close(report_modal)))

	# Población
	population_modal = UIKit.modal(root, "Población", Vector2(620, 0))
	pop_list = ItemList.new()
	pop_list.custom_minimum_size = Vector2(580, 420)
	pop_list.item_activated.connect(_on_pop_activated)
	pop_list.item_selected.connect(_on_pop_activated)
	population_modal["body"].add_child(pop_list)
	population_modal["body"].add_child(UIKit.button("Cerrar", func(): _close(population_modal)))

	# Registro de notificaciones
	log_modal = UIKit.modal(root, "Notificaciones", Vector2(620, 0))
	log_text = RichTextLabel.new()
	log_text.bbcode_enabled = true
	log_text.custom_minimum_size = Vector2(580, 420)
	log_text.scroll_following = true
	log_modal["body"].add_child(log_text)
	log_modal["body"].add_child(UIKit.button("Cerrar", func(): _close(log_modal)))

	# Fin de partida
	gameover_modal = UIKit.modal(root, "Fin de la partida")
	var gl := UIKit.label("Tu personaje ha muerto. (El sistema de herederos y dinastía llega en la Fase 7.)", 15)
	gl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gl.custom_minimum_size.x = 420
	gameover_modal["body"].add_child(gl)
	gameover_modal["body"].add_child(UIKit.button("Cargar partida", func(): _close(gameover_modal); _open_load()))
	gameover_modal["body"].add_child(UIKit.button("Menú principal", _to_main_menu))


func _open(m: Dictionary) -> void:
	m["root"].visible = true


func _close(m: Dictionary) -> void:
	m["root"].visible = false


func _any_modal_open() -> bool:
	for m in [pause_modal, save_modal, load_modal, jump_modal, progress_modal, report_modal, population_modal, log_modal, gameover_modal]:
		if m["root"].visible:
			return true
	return false


func _open_pause() -> void:
	_speed_before_menu = TimeManager.speed
	TimeManager.set_speed(0)
	_open(pause_modal)


func _close_pause() -> void:
	_close(pause_modal)
	if _speed_before_menu > 0:
		TimeManager.set_speed(_speed_before_menu)


func _open_save() -> void:
	save_name.text = "%s_%d" % [SaveManager.sanitize(str(GameState.settings.get("town_name", "partida"))), TimeManager.year()]
	_open(save_modal)
	save_name.grab_focus()


func _do_save() -> void:
	var ok := SaveManager.save_game(save_name.text)
	_close(save_modal)
	_on_notification({"text": "Partida guardada." if ok else "Error al guardar la partida.", "category": "info" if ok else "jugador"})


func _open_load() -> void:
	load_list.clear()
	for s in SaveManager.list_saves():
		var sm: Dictionary = s["summary"]
		var idx := load_list.add_item("%s — %s — %s · pobl. %d   [%s]" % [s["slot"], sm.get("town", ""), sm.get("date", ""), int(sm.get("population", 0)), s["saved_at"]])
		load_list.set_item_metadata(idx, s["slot"])
	_open(load_modal)


func _selected_slot() -> String:
	var sel := load_list.get_selected_items()
	return str(load_list.get_item_metadata(sel[0])) if sel.size() > 0 else ""


func _do_load() -> void:
	var slot := _selected_slot()
	if slot != "" and SaveManager.load_game(slot):
		get_tree().change_scene_to_file("res://scenes/main.tscn")


func _do_delete() -> void:
	var slot := _selected_slot()
	if slot != "":
		SaveManager.delete_save(slot)
		_open_load()


func _to_main_menu() -> void:
	GameState.running = false
	TimeManager.set_speed(0)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _open_jump() -> void:
	if GameState.running:
		TimeManager.set_speed(0)
		_open(jump_modal)


func _on_jump_started(_years: int) -> void:
	progress_bar.value = 0.0
	_open(progress_modal)


func _on_jump_finished(r: Dictionary) -> void:
	_close(progress_modal)
	var c: Dictionary = r.get("counters", {})
	var s := "[b]%s → %s[/b]\n\n" % [r["start_date"], r["end_date"]]
	s += "Población: %d → %d\n" % [r["start_population"], r["end_population"]]
	s += "Nacimientos: %d   Muertes: %d   Bodas: %d\n" % [int(c.get("births", 0)), int(c.get("deaths", 0)), int(c.get("marriages", 0))]
	s += "Emigrantes: %d   Enfermedades: %d\n" % [int(c.get("emigrated", 0)), int(c.get("illnesses", 0))]
	s += "Tu dinero: %s → %s\n" % [Fmt.money(r["start_money"]), Fmt.money(r["end_money"])]
	s += "Felicidad promedio: %s → %s\n" % [Fmt.pct(r["start_happiness"]), Fmt.pct(r["end_happiness"])]
	var notes: Array = r.get("notes", [])
	if not notes.is_empty():
		s += "\n[b]Eventos destacados[/b]\n"
		for n in notes:
			s += "• [color=#aaa]%s[/color] %s\n" % [n["date"], n["text"]]
	report_text.text = s
	_open(report_modal)


func _on_player_died() -> void:
	_open(gameover_modal)


func _open_population() -> void:
	pop_list.clear()
	pop_ids.clear()
	var list := GameState.citizens.values()
	list.sort_custom(func(a, b): return a.full_name() < b.full_name())
	var today := GameState.today()
	for c in list:
		pop_list.add_item("%s · %d años · salud %s · felicidad %s%s" % [c.full_name(), c.age_years(today),
				Fmt.pct(c.health), Fmt.pct(c.happiness), " · ENFERMO" if c.sick else ""])
		pop_ids.append(c.id)
	population_modal["title"].text = "Población (%d)" % list.size()
	_open(population_modal)


func _on_pop_activated(index: int) -> void:
	var id: int = pop_ids[index]
	_close(population_modal)
	EventBus.citizen_selected.emit(id)
	var world := get_parent()
	if world.has_method("focus_citizen"):
		world.focus_citizen(id)


func _open_log() -> void:
	var s := ""
	for e in GameState.notifications_log:
		var col: Color = UIKit.CATEGORY_COLORS.get(e["category"], Color.WHITE)
		s += "[color=#999]%s[/color]  [color=#%s]%s[/color]\n" % [e["date"], col.to_html(false), e["text"]]
	log_text.text = s
	_open(log_modal)


# --- Entrada y refresco ----------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key: Key = event.keycode
	if key == KEY_ESCAPE:
		if pause_modal["root"].visible:
			_close_pause()
		elif not _any_modal_open():
			_open_pause()
		else:
			for m in [save_modal, load_modal, jump_modal, report_modal, population_modal, log_modal]:
				_close(m)
		get_viewport().set_input_as_handled()
		return
	if _any_modal_open() or TimeManager.jumping:
		return
	match key:
		KEY_SPACE:
			TimeManager.toggle_pause()
		KEY_1:
			TimeManager.set_speed(1)
		KEY_2:
			TimeManager.set_speed(2)
		KEY_3:
			TimeManager.set_speed(3)
		KEY_4:
			_open_jump()
		_:
			return
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_refresh += delta
	if _refresh >= 0.2:
		_refresh = 0.0
		_update_top_bar()
		if info_panel.visible:
			_refresh_info()
