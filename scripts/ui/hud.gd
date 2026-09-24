class_name Hud
extends CanvasLayer
## Interfaz de juego: barra superior y velocidades, menú lateral, notificaciones,
## panel lateral (ciudadano, edificio, construir, empresas, personaje), vista interior y menús.

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
var hint_lbl: Label
var side_menu: VBoxContainer

# Panel lateral derecho (uno a la vez)
var dock: PanelContainer
var dock_mode := ""       # citizen | building | build | companies | player
var citizen_box: VBoxContainer
var citizen_text: RichTextLabel
var citizen_actions: HFlowContainer
var citizen_id := -1
var building_panel: BuildingPanel
var build_menu: BuildMenu
var companies_panel: CompaniesPanel
var player_panel: PlayerPanel
var finance_panel: FinancePanel
var stats_panel: StatsPanel
var research_screen: ResearchScreen
var era_lbl: Label

# Interior
var interior_panel: PanelContainer
var interior_text: RichTextLabel
var interior_actions: VBoxContainer
var interior_bid := -1

var pause_modal: Dictionary
var save_modal: Dictionary
var load_modal: Dictionary
var jump_modal: Dictionary
var progress_modal: Dictionary
var report_modal: Dictionary
var population_modal: Dictionary
var log_modal: Dictionary
var gameover_modal: Dictionary
var details_modal: Dictionary
var invite_modal: Dictionary
var save_name: LineEdit
var load_list: ItemList
var pop_list: ItemList
var pop_ids: Array = []
var log_text: RichTextLabel
var progress_bar: ProgressBar
var report_text: RichTextLabel
var details_name: LineEdit
var details_legal: OptionButton
var details_desc: Label
var details_cb: Callable
var invite_box: VBoxContainer
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
	_build_dock()
	_build_interior_panel()
	_build_modals()
	research_screen = ResearchScreen.new()
	root.add_child(research_screen)
	research_screen.setup()
	hint_lbl = UIKit.label("", 15, UIKit.ACCENT)
	hint_lbl.anchor_left = 0.5
	hint_lbl.anchor_right = 0.5
	hint_lbl.anchor_top = 1.0
	hint_lbl.anchor_bottom = 1.0
	hint_lbl.offset_left = -500
	hint_lbl.offset_right = 500
	hint_lbl.offset_top = -44
	hint_lbl.offset_bottom = -16
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	hint_lbl.add_theme_constant_override("outline_size", 6)
	hint_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hint_lbl)
	EventBus.notification_posted.connect(_on_notification)
	EventBus.speed_changed.connect(_on_speed_changed)
	EventBus.citizen_selected.connect(_on_citizen_selected)
	EventBus.building_selected.connect(open_building)
	EventBus.jump_started.connect(_on_jump_started)
	EventBus.jump_progress.connect(func(r): progress_bar.value = r * 100.0)
	EventBus.jump_finished.connect(_on_jump_finished)
	EventBus.player_died.connect(_on_player_died)
	EventBus.building_changed.connect(func(id): if dock_mode == "building" and id == building_panel.bid: building_panel.rebuild())
	EventBus.building_removed.connect(func(id): if dock_mode == "building" and id == building_panel.bid: close_dock())
	_on_speed_changed(TimeManager.speed)
	_update_top_bar()
	if not GameState.running:
		_on_player_died()


# --- Utilidades públicas -------------------------------------------------------------------

func toast(text: String, category := "info") -> void:
	if text != "":
		_on_notification({"text": text, "category": category})


func set_placement_hint(text: String) -> void:
	hint_lbl.text = text


func link(id: int) -> String:
	if GameState.citizens.has(id):
		return "[url=%d]%s[/url]" % [id, GameState.citizens[id].full_name()]
	return "[color=#999]%s[/color]" % GameState.person_name(id)


func bar(v: float) -> String:
	var col := "#6c6" if v >= 60 else ("#dc4" if v >= 35 else "#e55")
	return "[color=%s]%s[/color]" % [col, Fmt.pct(v)]


func on_meta_clicked(meta) -> void:
	var id := int(str(meta))
	if GameState.citizens.has(id):
		EventBus.citizen_selected.emit(id)
		var world := get_parent()
		if world.has_method("focus_citizen") and interior_bid < 0:
			world.focus_citizen(id)


# --- Barra superior -----------------------------------------------------------

func _build_top_bar() -> void:
	var bar_panel := PanelContainer.new()
	bar_panel.add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.BG, 0, 8))
	bar_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	root.add_child(bar_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	bar_panel.add_child(row)
	era_lbl = UIKit.label("", 17, UIKit.ACCENT)
	row.add_child(era_lbl)
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
	date_lbl.custom_minimum_size.x = 225
	date_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var speeds := HBoxContainer.new()
	speeds.add_theme_constant_override("separation", 4)
	row.add_child(speeds)
	var labels := ["II", "Real", "x1", "x2", "x3", "x4"]
	var tips := ["Pausa (Espacio)", "Tiempo real: 1 seg = 1 seg (1)", "1 seg = 1 hora (2)", "1 seg = 1 día (3)", "1 seg = 1 semana (4)", "Saltar 2, 5 o 10 años (5)"]
	for i in range(labels.size()):
		var idx := i
		var b := UIKit.button(labels[i], func(): _on_speed_button(idx), 42)
		b.tooltip_text = tips[i]
		b.toggle_mode = i <= TimeManager.MAX_SPEED
		speeds.add_child(b)
		speed_buttons.append(b)


func _stat(parent: Control) -> Label:
	var l := UIKit.label("", 15)
	parent.add_child(l)
	return l


func _update_top_bar() -> void:
	money_lbl.text = "Dinero: " + Fmt.money(GameState.money)
	money_lbl.add_theme_color_override("font_color", Color(0.95, 0.4, 0.4) if GameState.money < 0 else Color(0.95, 0.95, 0.95))
	pop_lbl.text = "Población: %d" % GameState.citizens.size()
	happy_lbl.text = "Felicidad: " + Fmt.pct(GameState.avg_happiness())
	health_lbl.text = "Salud: " + Fmt.pct(GameState.avg_health())
	var p := GameState.player_citizen()
	player_lbl.text = "%s, %d años%s" % [p.first_name, p.age_years(GameState.today()), " (enfermo/a)" if p.sick else ""] if p != null else ""
	var season_label := str(WeatherSim.season_data(GameState).get("label", ""))
	var w := WeatherSim.weather_data(GameState)
	weather_lbl.text = "%s · %s %d°C" % [season_label, w.get("label", ""), int(GameState.weather.get("temp", 0))]
	date_lbl.text = TimeManager.date_string(true)
	era_lbl.text = "%s · %s" % [GameState.settings.get("town_name", ""), _era_short()]
	if research_screen.visible and Engine.get_process_frames() % 20 == 0:
		research_screen.refresh()


func _on_speed_button(i: int) -> void:
	if i > TimeManager.MAX_SPEED:
		_open_jump()
	else:
		TimeManager.set_speed(i)


func _on_speed_changed(s: int) -> void:
	for i in range(TimeManager.MAX_SPEED + 1):
		speed_buttons[i].set_pressed_no_signal(i == s)


# --- Menú lateral -------------------------------------------------------------------

func _build_side_menu() -> void:
	var box := VBoxContainer.new()
	side_menu = box
	box.position = Vector2(12, 60)
	box.add_theme_constant_override("separation", 6)
	root.add_child(box)
	box.add_child(UIKit.button("Mi Personaje", func(): _show_dock("player"), 160))
	box.add_child(UIKit.button("Construir", func(): _show_dock("build"), 160))
	box.add_child(UIKit.button("Mis Empresas", func(): _show_dock("companies"), 160))
	box.add_child(UIKit.button("Finanzas", func(): _show_dock("finance"), 160))
	box.add_child(UIKit.button("Estadísticas", func(): _show_dock("stats"), 160))
	box.add_child(UIKit.button("Población", _open_population, 160))
	box.add_child(UIKit.button("Notificaciones", _open_log, 160))
	box.add_child(UIKit.button("Menú (Esc)", _open_pause, 160))
	box.add_child(HSeparator.new())
	box.add_child(UIKit.button("Investigación", _open_research, 160))
	for entry in [["Gobierno", 5]]:
		var b := UIKit.button(entry[0], func(): pass, 160)
		b.disabled = true
		b.tooltip_text = "Disponible en la Fase %d" % entry[1]
		box.add_child(b)


# --- Notificaciones -----------------------------------------------------------------

func _build_toasts() -> void:
	toasts = VBoxContainer.new()
	toasts.anchor_left = 0.5
	toasts.anchor_right = 0.5
	toasts.offset_left = -230
	toasts.offset_right = 230
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
	l.custom_minimum_size.x = 440
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


# --- Panel lateral ------------------------------------------------------------------

func _build_dock() -> void:
	dock = UIKit.right_panel(430)
	root.add_child(dock)
	var stack := Control.new()
	dock.add_child(stack)
	# Ciudadano
	citizen_box = VBoxContainer.new()
	citizen_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sb := UIKit.scroll_box(Vector2(0, 100))
	sb["scroll"].size_flags_vertical = Control.SIZE_EXPAND_FILL
	citizen_box.add_child(sb["scroll"])
	citizen_text = UIKit.rich()
	citizen_text.meta_clicked.connect(on_meta_clicked)
	sb["box"].add_child(citizen_text)
	citizen_actions = HFlowContainer.new()
	citizen_actions.add_theme_constant_override("h_separation", 6)
	citizen_actions.add_theme_constant_override("v_separation", 6)
	citizen_box.add_child(citizen_actions)
	stack.add_child(citizen_box)
	# Edificio, construir, empresas, personaje
	building_panel = BuildingPanel.new()
	building_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(building_panel)
	building_panel.setup(self)
	building_panel.message.connect(toast)
	building_panel.closed.connect(close_dock)
	build_menu = BuildMenu.new()
	build_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(build_menu)
	build_menu.setup()
	build_menu.closed.connect(close_dock)
	companies_panel = CompaniesPanel.new()
	companies_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(companies_panel)
	companies_panel.setup()
	companies_panel.closed.connect(close_dock)
	companies_panel.open_building.connect(func(id):
		open_building(id)
		var world := get_parent()
		if world.has_method("focus_building"):
			world.focus_building(id))
	player_panel = PlayerPanel.new()
	player_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(player_panel)
	player_panel.setup(self)
	player_panel.closed.connect(close_dock)
	player_panel.message.connect(toast)
	finance_panel = FinancePanel.new()
	finance_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(finance_panel)
	finance_panel.setup(self)
	finance_panel.closed.connect(close_dock)
	finance_panel.message.connect(toast)
	stats_panel = StatsPanel.new()
	stats_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(stats_panel)
	stats_panel.setup()
	stats_panel.closed.connect(close_dock)


func _show_dock(mode: String) -> void:
	if dock.visible and dock_mode == mode and mode != "citizen" and mode != "building":
		close_dock()
		return
	dock_mode = mode
	dock.visible = true
	citizen_box.visible = mode == "citizen"
	building_panel.visible = mode == "building"
	build_menu.visible = mode == "build"
	companies_panel.visible = mode == "companies"
	player_panel.visible = mode == "player"
	finance_panel.visible = mode == "finance"
	stats_panel.visible = mode == "stats"
	match mode:
		"stats":
			stats_panel.refresh()
		"finance":
			finance_panel.refresh()
		"build":
			build_menu.refresh()
		"companies":
			companies_panel.refresh()
		"player":
			player_panel.refresh()


func close_dock() -> void:
	dock.visible = false
	dock_mode = ""
	citizen_id = -1


func open_building(id: int) -> void:
	_show_dock("building")
	building_panel.open(id)


func _on_citizen_selected(id: int) -> void:
	if id < 0:
		if dock_mode == "citizen":
			close_dock()
		return
	citizen_id = id
	_show_dock("citizen")
	_refresh_citizen(true)


func _refresh_citizen(rebuild_actions: bool) -> void:
	if not GameState.citizens.has(citizen_id):
		close_dock()
		return
	var c: Citizen = GameState.citizens[citizen_id]
	citizen_text.text = _citizen_text(c)
	if rebuild_actions:
		_citizen_action_buttons(c)


func _citizen_text(c: Citizen) -> String:
	var today := GameState.today()
	var me := GameState.is_player(c.id)
	var s := "[font_size=20][color=#edc259]%s[/color][/font_size]%s\n" % [c.full_name(), "  [color=#edc259](tú)[/color]" if me else ""]
	s += "%s · %d años" % ["Mujer" if c.gender == "F" else "Hombre", c.age_years(today)]
	if not me:
		s += " · [color=#9cf]%s[/color]" % PlayerSim.relation_label(GameState, c)
	s += "\n\nSalud: %s%s\n" % [bar(c.health), "  [color=#e88](enfermo/a)[/color]" if c.sick else ""]
	s += "Felicidad: %s · Necesidades: %s\n" % [bar(c.happiness), bar(c.needs_met * 100.0)]
	s += "Dinero: %s   Deudas: %s\n" % [Fmt.money(GameState.money if me else c.money), Fmt.money(EconomySim.player_debt(GameState) if me else c.debt)]
	s += "Trabajo: %s\n" % ("Empresario(a)" if me else BusinessSim.job_label(GameState, c))
	if c.school_id >= 0:
		s += "Estudia en: %s (%.1f años cursados)\n" % [GameState.building_label(GameState.get_building(c.school_id)), c.school_years + c.uni_years]
	s += "Educación: %s · Experiencia: %.1f años\n\n" % [GameData.education_label(c.education), c.experience]
	s += "[b]Habilidades[/b]\n"
	var keys := c.skills.keys()
	keys.sort_custom(func(a, b): return float(c.skills[a]) > float(c.skills[b]))
	var sk := []
	for k in keys:
		sk.append("%s %d" % [GameData.skill_label(k), int(c.skills[k])])
	s += ", ".join(sk) + "\n\n[b]Familia[/b]\n"
	s += "Cónyuge: %s\n" % (link(c.spouse_id) if c.spouse_id >= 0 else "—")
	if not c.parent_ids.is_empty():
		s += "Padres: %s\n" % ", ".join(c.parent_ids.map(func(p): return link(p)))
	if not c.children_ids.is_empty():
		s += "Hijos: %s\n" % ", ".join(c.children_ids.map(func(ch): return link(ch)))
	var home := GameState.get_building(c.home_id)
	s += "\nVivienda: %s" % ("Sin hogar" if home.is_empty() else "%s (%s)" % [GameState.building_label(home), Housing.tier_label(str(home.get("tier", "normal")))])
	return s


func _citizen_action_buttons(c: Citizen) -> void:
	UIKit.clear(citizen_actions)
	var cid := c.id
	var add := func(text: String, cb: Callable, enabled := true, tip := ""):
		var b := UIKit.button(text, cb)
		b.disabled = not enabled
		b.tooltip_text = tip
		citizen_actions.add_child(b)
	if GameState.is_player(cid):
		add.call("Mi Personaje", func(): _show_dock("player"))
	else:
		var talk_r := PlayerSim.can_talk(GameState, c)
		add.call("Conversar", func(): _act(PlayerSim.talk(GameState, GameState.citizens[cid])), talk_r == "", talk_r)
		var court_r := PlayerSim.can_court(GameState, c)
		if court_r == "":
			add.call("Invitar a una cita", func(): _act(PlayerSim.date(GameState, GameState.citizens[cid])))
			add.call("Proponer matrimonio", func(): _act(PlayerSim.propose(GameState, GameState.citizens[cid])))
		var p := GameState.player_citizen()
		if p != null and c.home_id == p.home_id:
			add.call("Pedir que se vaya", func(): _act(PlayerSim.ask_to_leave(GameState, GameState.citizens[cid])))
		else:
			add.call("Invitar a vivir conmigo", func(): _act(PlayerSim.invite_to_live(GameState, GameState.citizens[cid])))
		if PlayerSim.can_adopt_orphan(GameState, c) == "":
			add.call("Adoptar", func(): _act(PlayerSim.adopt_orphan(GameState, GameState.citizens[cid])))
	if c.home_id >= 0 and interior_bid != c.home_id:
		add.call("Ver su casa por dentro", func(): EventBus.interior_requested.emit(GameState.citizens[cid].home_id))
	if interior_bid < 0:
		add.call("Seguir con cámara", func(): follow_requested.emit())
	add.call("Cerrar", func(): EventBus.citizen_selected.emit(-1))


func _act(text: String) -> void:
	toast(text, "familia")
	_refresh_citizen(true)
	if interior_bid >= 0:
		_refresh_interior()


# --- Interior ------------------------------------------------------------------------------

func _build_interior_panel() -> void:
	interior_panel = PanelContainer.new()
	interior_panel.position = Vector2(12, 60)
	interior_panel.custom_minimum_size = Vector2(360, 0)
	interior_panel.visible = false
	root.add_child(interior_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	interior_panel.add_child(v)
	interior_text = UIKit.rich(Vector2(340, 0))
	interior_text.meta_clicked.connect(on_meta_clicked)
	v.add_child(interior_text)
	interior_actions = VBoxContainer.new()
	v.add_child(interior_actions)


func show_interior(bid: int) -> void:
	interior_bid = bid
	interior_panel.visible = true
	side_menu.visible = false
	close_dock()
	_refresh_interior()


func _refresh_interior() -> void:
	var b := GameState.get_building(interior_bid)
	if b.is_empty():
		_close_interior()
		return
	var s := "[font_size=19][color=#edc259]%s[/color][/font_size]\n" % GameState.building_label(b)
	s += "%s · calidad %s\n" % [GameState.level_def(b).get("label", ""), Housing.tier_label(str(b.get("tier", "normal")))]
	s += "[color=#aaa]Objetos: %s[/color]\n\n[b]Aquí viven[/b]\n" % Housing.interior_summary(GameState, b)
	var res := GameState.residents_of(interior_bid)
	for c in res:
		s += "• %s (%d)%s\n" % [link(c.id), c.age_years(GameState.today()), " — " + PlayerSim.relation_label(GameState, c) if not GameState.is_player(c.id) else " — tú"]
	if res.is_empty():
		s += "Nadie.\n"
	s += "\n[color=#999]Haz clic en una persona para interactuar. Q/E rota, rueda acerca.[/color]"
	interior_text.text = s
	UIKit.clear(interior_actions)
	var p := GameState.player_citizen()
	if p != null and p.home_id == interior_bid:
		if p.spouse_id >= 0:
			interior_actions.add_child(UIKit.button("Buscar un bebé con mi pareja", func(): _act(PlayerSim.try_child(GameState))))
		interior_actions.add_child(UIKit.button("Invitar a alguien a vivir aquí…", _open_invite))
	interior_actions.add_child(UIKit.button("Salir de la casa (Esc)", _close_interior))


func _close_interior() -> void:
	interior_bid = -1
	interior_panel.visible = false
	side_menu.visible = true
	var world := get_parent()
	if world.has_method("close_interior"):
		world.close_interior()


func _open_invite() -> void:
	UIKit.clear(invite_box)
	var rel: Dictionary = GameState.player.get("relations", {})
	var p := GameState.player_citizen()
	var n := 0
	for c in GameState.citizens.values():
		if GameState.is_player(c.id) or c.home_id == p.home_id:
			continue
		var family: bool = p.spouse_id == c.id or p.children_ids.has(c.id) or p.parent_ids.has(c.id)
		if not family and float(rel.get(str(c.id), 0.0)) <= 0.0:
			continue
		var row := HBoxContainer.new()
		var l := UIKit.label("%s — %s" % [c.full_name(), PlayerSim.relation_label(GameState, c)], 14)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var cid: int = c.id
		row.add_child(UIKit.button("Invitar", func():
			invite_modal["root"].visible = false
			_act(PlayerSim.invite_to_live(GameState, GameState.citizens[cid]))))
		invite_box.add_child(row)
		n += 1
	if n == 0:
		invite_box.add_child(UIKit.label("Aún no conoces a nadie. Conversa con la gente del pueblo."))
	invite_modal["root"].visible = true


# --- Modales ------------------------------------------------------------------------------

func _build_modals() -> void:
	pause_modal = UIKit.modal(root, "Menú")
	var pb: VBoxContainer = pause_modal["body"]
	pb.add_child(UIKit.button("Continuar", _close_pause))
	pb.add_child(UIKit.button("Guardar partida", func(): _close(pause_modal); _open_save()))
	pb.add_child(UIKit.button("Cargar partida", func(): _close(pause_modal); _open_load()))
	pb.add_child(UIKit.button("Menú principal", _to_main_menu))
	pb.add_child(UIKit.button("Salir del juego", func(): get_tree().quit()))
	var controls := UIKit.label("Cámara: WASD/flechas o clic derecho para mover · Q/E o botón central para rotar · rueda o pellizco para zoom · Espacio pausa · 1-4 velocidades · 5 salto de años · R rota al construir", 13, UIKit.TEXT_DIM)
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.custom_minimum_size.x = 420
	pb.add_child(controls)

	save_modal = UIKit.modal(root, "Guardar partida")
	var sb: VBoxContainer = save_modal["body"]
	sb.add_child(UIKit.label("Nombre de la partida:"))
	save_name = LineEdit.new()
	sb.add_child(save_name)
	var srow := HBoxContainer.new()
	sb.add_child(srow)
	srow.add_child(UIKit.button("Guardar", _do_save, 120))
	srow.add_child(UIKit.button("Cancelar", func(): _close(save_modal), 120))

	load_modal = UIKit.modal(root, "Cargar partida", Vector2(560, 0))
	var lb: VBoxContainer = load_modal["body"]
	load_list = ItemList.new()
	load_list.custom_minimum_size = Vector2(520, 260)
	lb.add_child(load_list)
	var lrow := HBoxContainer.new()
	lb.add_child(lrow)
	lrow.add_child(UIKit.button("Cargar", _do_load, 120))
	lrow.add_child(UIKit.button("Borrar", _do_delete, 120))
	lrow.add_child(UIKit.button("Cancelar", func(): _close(load_modal), 120))

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

	progress_modal = UIKit.modal(root, "Simulando…")
	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(420, 26)
	progress_modal["body"].add_child(progress_bar)

	report_modal = UIKit.modal(root, "Reporte del periodo", Vector2(560, 0))
	report_text = RichTextLabel.new()
	report_text.bbcode_enabled = true
	report_text.custom_minimum_size = Vector2(520, 380)
	report_modal["body"].add_child(report_text)
	report_modal["body"].add_child(UIKit.button("Continuar", func(): _close(report_modal)))

	population_modal = UIKit.modal(root, "Población", Vector2(640, 0))
	pop_list = ItemList.new()
	pop_list.custom_minimum_size = Vector2(600, 420)
	pop_list.item_selected.connect(_on_pop_activated)
	population_modal["body"].add_child(pop_list)
	population_modal["body"].add_child(UIKit.button("Cerrar", func(): _close(population_modal)))

	log_modal = UIKit.modal(root, "Notificaciones", Vector2(640, 0))
	log_text = RichTextLabel.new()
	log_text.bbcode_enabled = true
	log_text.custom_minimum_size = Vector2(600, 420)
	log_text.scroll_following = true
	log_modal["body"].add_child(log_text)
	log_modal["body"].add_child(UIKit.button("Cerrar", func(): _close(log_modal)))

	gameover_modal = UIKit.modal(root, "Fin de la dinastía")
	var gl := UIKit.label("Tu personaje murió sin hijos que hereden. Ten o adopta hijos y elige un heredero para continuar tu dinastía.", 15)
	gl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gl.custom_minimum_size.x = 420
	gameover_modal["body"].add_child(gl)
	gameover_modal["body"].add_child(UIKit.button("Cargar partida", func(): _close(gameover_modal); _open_load()))
	gameover_modal["body"].add_child(UIKit.button("Menú principal", _to_main_menu))

	details_modal = UIKit.modal(root, "Nuevo negocio")
	var db: VBoxContainer = details_modal["body"]
	db.add_child(UIKit.label("Nombre del negocio:"))
	details_name = LineEdit.new()
	db.add_child(details_name)
	db.add_child(UIKit.label("Tipo legal:"))
	details_legal = OptionButton.new()
	for id in GameData.sorted_ids(GameData.legal_types):
		details_legal.add_item(str(GameData.legal_types[id].get("label", id)))
		details_legal.set_item_metadata(details_legal.item_count - 1, id)
	details_legal.item_selected.connect(func(_i): _update_legal_desc())
	db.add_child(details_legal)
	details_desc = UIKit.label("", 13, UIKit.TEXT_DIM)
	details_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details_desc.custom_minimum_size.x = 420
	db.add_child(details_desc)
	var drow := HBoxContainer.new()
	db.add_child(drow)
	drow.add_child(UIKit.button("Construir", func():
		_close(details_modal)
		details_cb.call(details_name.text.strip_edges(), str(details_legal.get_item_metadata(details_legal.selected)))))
	drow.add_child(UIKit.button("Cancelar", func(): _close(details_modal)))

	invite_modal = UIKit.modal(root, "Invitar a vivir contigo", Vector2(560, 0))
	var isb := UIKit.scroll_box(Vector2(520, 360))
	invite_box = isb["box"]
	invite_modal["body"].add_child(isb["scroll"])
	invite_modal["body"].add_child(UIKit.button("Cerrar", func(): _close(invite_modal)))


func ask_business_details(type_id: String, cb: Callable) -> void:
	details_cb = cb
	var def := GameData.building_def(type_id)
	details_modal["title"].text = "Nuevo negocio: %s" % def.get("label", type_id)
	details_name.text = "%s %s" % [def.get("label", ""), GameState.player_citizen().last_name if GameState.player_citizen() else ""]
	details_legal.select(0)
	_update_legal_desc()
	_open(details_modal)
	details_name.grab_focus()


func _update_legal_desc() -> void:
	var id := str(details_legal.get_item_metadata(details_legal.selected))
	details_desc.text = str(GameData.legal_types.get(id, {}).get("description", ""))


func _open(m: Dictionary) -> void:
	m["root"].visible = true


func _close(m: Dictionary) -> void:
	m["root"].visible = false


func _any_modal_open() -> bool:
	for m in [pause_modal, save_modal, load_modal, jump_modal, progress_modal, report_modal, population_modal, log_modal, gameover_modal, details_modal, invite_modal, building_panel.hire_modal]:
		if m["root"].visible:
			return true
	return false


func _era_short() -> String:
	for e in GameData.eras.get("eras", []):
		if int(e["id"]) == GameState.era():
			return str(e.get("short", e["label"]))
	return ""


func _open_research() -> void:
	close_dock()
	research_screen.open()


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
	toast("Partida guardada." if ok else "Error al guardar la partida.", "info" if ok else "jugador")


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
	s += "Tu dinero: %s → %s (ingresos %s, gastos %s)\n" % [Fmt.money(r["start_money"]), Fmt.money(r["end_money"]), Fmt.money(float(c.get("income", 0))), Fmt.money(float(c.get("expenses", 0)))]
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
		var rel := "" if GameState.is_player(c.id) else " · " + PlayerSim.relation_label(GameState, c)
		pop_list.add_item("%s%s · %d años · salud %s · %s%s%s" % [c.full_name(), " (TÚ)" if GameState.is_player(c.id) else "", c.age_years(today),
				Fmt.pct(c.health), BusinessSim.job_label(GameState, c), rel, " · ENFERMO" if c.sick else ""])
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
		if research_screen.visible:
			research_screen.close()
		elif pause_modal["root"].visible:
			_close_pause()
		elif _any_modal_open():
			for m in [save_modal, load_modal, jump_modal, report_modal, population_modal, log_modal, details_modal, invite_modal, building_panel.hire_modal]:
				_close(m)
		elif interior_bid >= 0:
			_close_interior()
		elif dock.visible:
			close_dock()
		else:
			_open_pause()
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
			TimeManager.set_speed(4)
		KEY_5:
			_open_jump()
		_:
			return
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_refresh += delta
	if _refresh >= 0.25:
		_refresh = 0.0
		_update_top_bar()
		if dock.visible:
			match dock_mode:
				"citizen":
					_refresh_citizen(false)
				"building":
					building_panel.refresh()
