class_name Hud
extends CanvasLayer
## Interfaz de juego: barra superior con indicadores y tendencias, barra de iconos agrupada por
## categorías con menús desplegables, notificaciones (toasts + centro de notificaciones), panel
## lateral (ficha de persona, edificio, construir, empresas, personaje…), vista interior y menús.
## Ver docs/UI.md.

signal follow_requested

const TOAST_SECONDS := 6.0
const MAX_TOASTS := 4
const DOCK_W := 440.0
const BAR_H := 46.0

## Barra de iconos: categorías y sus entradas [id, etiqueta, icono, atajo].
const CATEGORIES := [
	{"id": "dinastia", "label": "Mi dinastía", "icon": "dynasty", "key": "F1", "items": [
		["player", "Mi personaje", "character", "P"], ["family", "Familia y herederos", "family", ""],
		["countries", "Mis países y mapa mundial", "globe", ""]]},   # Fase 10
	{"id": "construir", "label": "Construir", "icon": "build", "key": "B", "items": [["build", "Construir", "build", "B"]]},
	{"id": "empresas", "label": "Empresas", "icon": "companies", "key": "F2", "items": [
		["companies", "Mis empresas", "companies", "C"], ["realestate", "Bienes raíces", "realestate", "V"], ["contracts", "Contratos", "contracts", "K"]]},
	{"id": "economia", "label": "Economía", "icon": "economy", "key": "F3", "items": [
		["finance", "Finanzas", "finance", "F"], ["cash", "Efectivo y riesgo", "money", ""], ["stats", "Estadísticas", "stats", "Y"],
		["world_econ", "Economía mundial", "globe", ""], ["stocks", "Bolsa de valores", "trend_up", ""], ["insurance", "Seguros", "shield", ""],
		["catalog", "Catálogo de bienes", "catalog", "O"]]},
	{"id": "logistica", "label": "Logística y transporte", "icon": "logistics", "key": "F4", "items": [
		["logistics", "Logística", "logistics", "L"], ["transit", "Transporte público", "transit", "J"],
		["utilities", "Servicios públicos", "utilities", "U"], ["trade", "Comercio exterior", "trade", "X"],
		["aviation", "Aviación", "logistics", ""]]},   # Fase 10
	{"id": "sociedad", "label": "Sociedad", "icon": "society", "key": "F5", "items": [
		["population", "Población", "population", "Z"], ["towns", "Pueblos vecinos", "town", ""],
		["government", "Gobierno", "government", "G"], ["tourism", "Turismo y publicidad", "tourism", ""]]},
	{"id": "ciencia", "label": "Ciencia", "icon": "research", "key": "I", "items": [["research", "Investigación", "research", "I"]]},
]
const SHORTCUTS := {KEY_P: "player", KEY_B: "build", KEY_C: "companies", KEY_V: "realestate", KEY_K: "contracts",
	KEY_F: "finance", KEY_Y: "stats", KEY_O: "catalog", KEY_L: "logistics", KEY_J: "transit", KEY_U: "utilities",
	KEY_X: "trade", KEY_Z: "population", KEY_G: "government", KEY_I: "research", KEY_N: "notifications"}
const WEATHER_ICONS := {"despejado": "sun", "nublado": "cloud", "lluvia": "rain", "tormenta": "storm", "calor": "sun", "nieve": "snow", "helada": "snow"}

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
var hint_panel: PanelContainer
var side_menu: PanelContainer         # barra de iconos por categorías
var era_lbl: Label

# Barra superior
var _chips := {}                      # id -> {panel, value, trend, icon}
var _weather_icon: TextureRect
var _player_portrait: Portrait
var _player_chip: PanelContainer
var bell_btn: Button
var _bell_badge: PanelContainer
var _bell_count: Label
var unread := 0
# Barra de iconos y menú desplegable
var _cat_buttons := {}                # id -> Button
var flyout: PanelContainer
var _flyout_box: VBoxContainer
var _flyout_cat := ""
var _catcher: Control

# Panel lateral derecho (uno a la vez)
var dock: PanelContainer
var dock_mode := ""       # citizen | building | build | companies | player | …
var _dock_stack: Control
var _dock_tween: Tween
var citizen_box: VBoxContainer
var citizen_text: RichTextLabel
var citizen_actions: HFlowContainer
var citizen_id := -1
var _cit_head: VBoxContainer
var _cit_meters: VBoxContainer
var building_panel: BuildingPanel
var build_menu: BuildMenu
var companies_panel: CompaniesPanel
var player_panel: PlayerPanel
var finance_panel: FinancePanel
var stats_panel: StatsPanel
var research_screen: ResearchScreen
var goods_catalog: GoodsCatalog
var government_panel: GovernmentPanel
var logistics_panel: LogisticsPanel
var trade_panel: TradePanel
var contracts_panel: ContractsPanel
var tourism_panel: TourismPanel
var realestate_panel: RealEstatePanel   # Bienes raíces
var utilities_panel: UtilitiesPanel
var transit_panel: TransitPanel
var cash_panel: CashPanel   # Sección E: efectivo y riesgo
var global_econ: GlobalEconWindow   # Economía global: ciclos, monedas, bolsa y seguros.
var cycle_indicator: CycleIndicator
var countries_window: CountriesWindow   # Fase 10: mapa mundial y Mis países
var aviation_window: AviationWindow     # Fase 10: aeropuertos, flota, vuelos y rutas
var country_indicator: CountryIndicator # Fase 10: país donde está el personaje

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
var options_modal: Dictionary
var save_name: LineEdit
var load_list: ItemList
var pop_table: DataTable
var pop_search: LineEdit
var _pop_rows: Array = []
var log_box: VBoxContainer
var log_filters: HFlowContainer
var _log_filter := {}              # categoría -> bool (vacío = todas)
var progress_bar: ProgressBar
var report_text: RichTextLabel
var details_name: LineEdit
var details_legal: OptionButton
var details_desc: Label
var details_cb: Callable
var invite_box: VBoxContainer
var _scale_lbl: Label
var _speed_before_menu := 0
var _refresh := 0.0
var _slow_refresh := 0.0


func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIKit.make_theme()
	add_child(root)
	UIKit.hook_scale(root)
	_build_top_bar()
	_build_side_menu()
	_build_toasts()
	_build_dock()
	_build_interior_panel()
	_build_modals()
	research_screen = ResearchScreen.new()
	root.add_child(research_screen)
	research_screen.setup()
	goods_catalog = GoodsCatalog.new()
	root.add_child(goods_catalog)
	goods_catalog.setup()
	global_econ = GlobalEconWindow.new()
	root.add_child(global_econ)
	global_econ.setup()
	global_econ.message.connect(toast)
	countries_window = CountriesWindow.new()   # Fase 10
	root.add_child(countries_window)
	countries_window.setup()
	countries_window.message.connect(toast)
	countries_window.view_requested.connect(switch_country)
	aviation_window = AviationWindow.new()
	root.add_child(aviation_window)
	aviation_window.setup()
	aviation_window.message.connect(toast)
	_build_hint()
	_build_flyout()
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
	EventBus.day_passed.connect(func(): UIHistory.sample(GameState))
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
	if hint_panel != null:
		hint_panel.visible = text != ""


func link(id: int) -> String:
	if GameState.citizens.has(id):
		return "[url=%d]%s[/url]" % [id, GameState.citizens[id].full_name()]
	return "[color=#999]%s[/color]" % GameState.person_name(id)


func bar(v: float) -> String:
	var col := UIKit.level_color(v / 100.0)
	return "[color=#%s]%s[/color]" % [col.to_html(false), Fmt.pct(v)]


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
	var st := UIKit._flat(Color(0.06, 0.066, 0.082, 0.93), 0, 10, 4)
	st.border_color = Color(UIKit.ACCENT, 0.18)
	st.border_width_bottom = 1
	st.shadow_color = Color(0, 0, 0, 0.3)
	st.shadow_size = 6
	bar_panel.add_theme_stylebox_override("panel", st)
	bar_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar_panel.custom_minimum_size.y = BAR_H
	root.add_child(bar_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	bar_panel.add_child(row)
	# Pueblo y época
	var town := HBoxContainer.new()
	town.add_theme_constant_override("separation", 6)
	town.add_child(UIKit.icon("dynasty", 20, UIKit.ACCENT))
	era_lbl = UIKit.label("", 15, UIKit.ACCENT)
	era_lbl.clip_text = true
	era_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	era_lbl.custom_minimum_size.x = 150
	town.add_child(era_lbl)
	row.add_child(town)
	row.add_child(_vsep())
	# Indicadores
	for spec in [["money", "money", UIKit.ACCENT, 84], ["pop", "population", UIKit.ACCENT_2, 30], ["happy", "happiness", UIKit.GOOD, 38], ["health", "health", UIKit.BAD, 38]]:
		_chips[spec[0]] = _chip(row, spec[1], spec[2], spec[3])
	money_lbl = _chips["money"]["value"]
	pop_lbl = _chips["pop"]["value"]
	happy_lbl = _chips["happy"]["value"]
	health_lbl = _chips["health"]["value"]
	row.add_child(_vsep())
	# Personaje (mini retrato + nombre + aviso de heredero)
	_player_chip = PanelContainer.new()
	_player_chip.add_theme_stylebox_override("panel", UIKit._flat(Color(1, 1, 1, 0.0), 8, 4, 0))
	_player_chip.mouse_filter = Control.MOUSE_FILTER_STOP
	_player_chip.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: _show_dock("player"))
	_player_chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", 6)
	_player_chip.add_child(ph)
	_player_portrait = Portrait.new()
	_player_portrait.custom_minimum_size = Vector2(30, 30)
	_player_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ph.add_child(_player_portrait)
	player_lbl = UIKit.label("", 14)
	player_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ph.add_child(player_lbl)
	row.add_child(_player_chip)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	country_indicator = CountryIndicator.new()   # Fase 10: país del personaje (clic: mapa mundial).
	row.add_child(country_indicator)
	country_indicator.pressed.connect(func(): countries_window.open(0))
	country_indicator.view_change.connect(switch_country)
	cycle_indicator = CycleIndicator.new()   # Economía global: fase del ciclo y señales.
	cycle_indicator.icon = UIIcons.tex("economy", 16)
	cycle_indicator.clip_text = true
	cycle_indicator.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	cycle_indicator.custom_minimum_size.x = 140
	row.add_child(cycle_indicator)
	cycle_indicator.pressed.connect(func(): global_econ.open(0))
	# Clima y fecha
	var wbox := HBoxContainer.new()
	wbox.add_theme_constant_override("separation", 4)
	_weather_icon = UIKit.icon("sun", 18, Color(0.98, 0.82, 0.45))
	wbox.add_child(_weather_icon)
	weather_lbl = UIKit.label("", 13, UIKit.TEXT_DIM)
	weather_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	wbox.add_child(weather_lbl)
	row.add_child(wbox)
	var dbox := HBoxContainer.new()
	dbox.add_theme_constant_override("separation", 4)
	dbox.add_child(UIKit.icon("calendar", 16, UIKit.TEXT_DIM))
	date_lbl = UIKit.label("", 14)
	date_lbl.custom_minimum_size.x = 128
	date_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	dbox.add_child(date_lbl)
	row.add_child(dbox)
	# Controles de tiempo: grupo segmentado con iconos
	var speeds := PanelContainer.new()
	speeds.add_theme_stylebox_override("panel", UIKit._flat(Color(0, 0, 0, 0.3), 9, 3, 3, UIKit.BORDER, 1))
	row.add_child(speeds)
	var sh := HBoxContainer.new()
	sh.add_theme_constant_override("separation", 2)
	speeds.add_child(sh)
	var icons := ["pause", "realtime", "play", "speed2", "speed3", "jump"]
	var tips := ["Pausa (Espacio)", "Tiempo real: 1 seg = 1 seg (1)", "Normal: 1 seg = 1 hora (2)", "Rápido: 1 seg = 1 día (3)", "Muy rápido: 1 seg = 1 semana (4)", "Saltar 2, 5 o 10 años (5)"]
	for i in range(icons.size()):
		var idx := i
		var b := UIKit.icon_button(icons[i], func(): _on_speed_button(idx), tips[i], "", 16)
		b.custom_minimum_size = Vector2(32, 30)
		b.toggle_mode = i <= TimeManager.MAX_SPEED
		b.add_theme_stylebox_override("normal", UIKit._flat(Color(0, 0, 0, 0), 6, 4, 3))
		b.add_theme_stylebox_override("hover", UIKit._flat(Color(1, 1, 1, 0.08), 6, 4, 3))
		b.add_theme_stylebox_override("pressed", UIKit._flat(Color(UIKit.ACCENT, 0.28), 6, 4, 3))
		b.add_theme_stylebox_override("hover_pressed", UIKit._flat(Color(UIKit.ACCENT, 0.35), 6, 4, 3))
		b.add_theme_color_override("icon_pressed_color", Color(1.0, 0.88, 0.55))
		b.add_theme_color_override("icon_hover_pressed_color", Color(1.0, 0.9, 0.6))
		sh.add_child(b)
		speed_buttons.append(b)
	# Campana de notificaciones con contador
	bell_btn = UIKit.icon_button("bell", open_notifications, "Centro de notificaciones (N)", "", 18)
	bell_btn.custom_minimum_size = Vector2(36, 34)
	row.add_child(bell_btn)
	_bell_badge = PanelContainer.new()
	_bell_badge.add_theme_stylebox_override("panel", UIKit._flat(UIKit.BAD, 8, 4, 0))
	_bell_badge.position = Vector2(19, -2)
	_bell_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bell_count = UIKit.label("0", 10, Color.WHITE)
	_bell_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bell_badge.add_child(_bell_count)
	_bell_badge.visible = false
	bell_btn.add_child(_bell_badge)
	var menu_btn := UIKit.icon_button("menu", _open_pause, "Menú: guardar, cargar, opciones (Esc)", "", 18)
	menu_btn.custom_minimum_size = Vector2(36, 34)
	row.add_child(menu_btn)


func _vsep() -> VSeparator:
	var s := VSeparator.new()
	s.add_theme_constant_override("separation", 8)
	return s


func _chip(parent: Control, icon_name: String, color: Color, min_w: int) -> Dictionary:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIKit._flat(Color(1, 1, 1, 0.0), 8, 5, 2))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 5)
	p.add_child(h)
	var ic := UIKit.icon(icon_name, 18, color)
	h.add_child(ic)
	var v := UIKit.label("", 15)
	v.custom_minimum_size.x = min_w
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var t := UIKit.label("", 11, UIKit.NEUTRAL)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(t)
	parent.add_child(p)
	p.mouse_entered.connect(func(): p.add_theme_stylebox_override("panel", UIKit._flat(Color(1, 1, 1, 0.06), 8, 5, 2)))
	p.mouse_exited.connect(func(): p.add_theme_stylebox_override("panel", UIKit._flat(Color(1, 1, 1, 0.0), 8, 5, 2)))
	return {"panel": p, "value": v, "trend": t, "icon": ic}


## ▲▼ con color respecto al registro del mes anterior.
func _set_trend(id: String, now: float, prev: float, has_prev: bool, pct_points := false) -> void:
	var t: Label = _chips[id]["trend"]
	if not has_prev:
		t.text = ""
		return
	var d := now - prev
	var rel := d if pct_points else d / maxf(1.0, absf(prev))
	if absf(rel) < (0.5 if pct_points else 0.005):
		t.text = ""
		return
	t.text = ("▲" if d > 0.0 else "▼") + (("%d" % int(roundf(absf(d)))) if pct_points else Fmt.pct_1(absf(rel) * 100.0))
	t.add_theme_color_override("font_color", UIKit.GOOD if d > 0.0 else UIKit.BAD)


func _update_top_bar() -> void:
	var gs := GameState
	var last: Dictionary = gs.history[-1] if not gs.history.is_empty() else {}
	var has_prev := not last.is_empty()
	money_lbl.text = Fmt.money(gs.money)
	money_lbl.add_theme_color_override("font_color", UIKit.BAD if gs.money < 0 else UIKit.TEXT)
	_set_trend("money", gs.money, float(last.get("money", 0.0)), has_prev)
	pop_lbl.text = Fmt.thousands(gs.citizens.size())
	_set_trend("pop", gs.citizens.size(), float(last.get("population", 0)), has_prev)
	var hap := gs.avg_happiness()
	happy_lbl.text = Fmt.pct(hap)
	happy_lbl.add_theme_color_override("font_color", UIKit.level_color(hap / 100.0).lerp(UIKit.TEXT, 0.4))
	_set_trend("happy", hap, float(last.get("happiness", 0.0)), has_prev, true)
	var hea := gs.avg_health()
	health_lbl.text = Fmt.pct(hea)
	health_lbl.add_theme_color_override("font_color", UIKit.level_color(hea / 100.0).lerp(UIKit.TEXT, 0.4))
	_set_trend("health", hea, float(last.get("health", 0.0)), has_prev, true)
	var p := gs.player_citizen()
	var no_heir := p != null and not DynastySim.has_heir(gs)
	if p != null:
		player_lbl.text = "%s, %d%s" % [p.first_name, p.age_years(gs.today()), " · enfermo/a" if p.sick else ""]
		if no_heir:
			player_lbl.text += "  ⚠ SIN HEREDERO"
	else:
		player_lbl.text = ""
	player_lbl.add_theme_color_override("font_color", UIKit.BAD if no_heir and (p.sick or p.health < 50.0) else (UIKit.WARN if no_heir else UIKit.TEXT))
	var season_label := str(WeatherSim.season_data(gs).get("label", ""))
	var w := WeatherSim.weather_data(gs)
	weather_lbl.text = "%d°C" % int(gs.weather.get("temp", 0))
	date_lbl.text = _short_date()
	date_lbl.tooltip_text = TimeManager.date_string(true)
	_adapt_top_bar()
	era_lbl.text = "%s · %s" % [gs.settings.get("town_name", ""), _era_short()]
	if research_screen.visible and Engine.get_process_frames() % 20 == 0:
		research_screen.refresh()
	# Lo que cambia poco (tooltips, retrato, icono del clima): cada ~2 s.
	if _slow_refresh <= 0.0:
		_slow_refresh = 2.0
		_weather_icon.texture = UIIcons.tex(str(WEATHER_ICONS.get(str(gs.weather.get("type", "despejado")), "sun")), 18)
		_weather_icon.tooltip_text = "%s · %s %d°C" % [season_label, w.get("label", ""), int(gs.weather.get("temp", 0))]
		weather_lbl.tooltip_text = _weather_icon.tooltip_text
		_weather_icon.mouse_filter = Control.MOUSE_FILTER_PASS
		if p != null:
			_player_portrait.set_citizen(p, true)
		_player_chip.tooltip_text = ("Si mueres sin heredero, termina la dinastía. Ten hijos, adopta o define tu orden de herederos (Mi personaje)." if no_heir else "Mi personaje (P)")
		var inc := float(last.get("income", 0.0))
		var exp_m := float(last.get("expenses", 0.0))
		_chips["money"]["panel"].tooltip_text = "Dinero: %s\nPatrimonio neto: %s · Deudas: %s\nMes anterior: ingresos %s · gastos %s\n▲▼ = cambio desde el cierre del mes anterior" % [
			Fmt.money(gs.money), Fmt.money(EconomySim.net_worth(gs)), Fmt.money(EconomySim.player_debt(gs)), Fmt.money(inc), Fmt.money(exp_m)]
		var pop := StatsSim.population(gs)
		_chips["pop"]["panel"].tooltip_text = "Población: %d\nNiños %d · Adultos %d · Mayores %d\nÚltimos 12 meses: %d nacimientos, %d muertes\nClic: tabla de población (Z)" % [
			gs.citizens.size(), int(pop["children"]), int(pop["adults"]), int(pop["elderly"]), int(pop["births_year"]), int(pop["deaths_year"])]
		_chips["happy"]["panel"].tooltip_text = "Felicidad promedio: %s\nDepende de necesidades cubiertas, vivienda, empleo, clima y servicios." % Fmt.pct(hap)
		_chips["health"]["panel"].tooltip_text = "Salud promedio: %s\nEnfermos ahora: %d" % [Fmt.pct(hea), gs.citizens.values().filter(func(c): return c.sick).size()]
		if not _chips["pop"].has("hooked"):
			_chips["pop"]["hooked"] = true
			_chips["pop"]["panel"].gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: _open_population())
			_chips["money"]["panel"].gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: _show_dock("finance"))
			_chips["happy"]["panel"].gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: _show_dock("stats"))
			_chips["health"]["panel"].gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: _show_dock("stats"))


## Fecha compacta para la barra: "19 jul 1701 · 10:00".
func _short_date() -> String:
	var md := TimeManager.month_day()
	var full := TimeManager.date_string(true)
	var hour_part := full.get_slice("  ", 1) if full.contains("  ") else ""
	return "%d %s %d%s" % [md[1], str(TimeManager.MONTH_NAMES[md[0] - 1]).substr(0, 3), TimeManager.year(), " · " + hour_part if hour_part != "" else ""]


## En ventanas estrechas (1280 px lógicos) se ocultan textos secundarios: quedan iconos y tooltips.
func _adapt_top_bar() -> void:
	var w := root.size.x
	var compact := w < 1560.0
	var tight := w < 1380.0
	player_lbl.visible = not tight
	cycle_indicator.custom_minimum_size.x = 34.0 if compact else 140.0
	country_indicator.custom_minimum_size.x = 34.0 if compact else 150.0   # Fase 10
	country_indicator.size.x = 0.0
	cycle_indicator.size.x = 0.0
	weather_lbl.visible = not tight
	era_lbl.custom_minimum_size.x = 110.0 if tight else 150.0
	for id in ["money", "pop", "happy", "health"]:
		(_chips[id]["trend"] as Label).visible = not tight or id == "money"


func _on_speed_button(i: int) -> void:
	if i > TimeManager.MAX_SPEED:
		_open_jump()
	else:
		TimeManager.set_speed(i)


func _on_speed_changed(s: int) -> void:
	for i in range(TimeManager.MAX_SPEED + 1):
		speed_buttons[i].set_pressed_no_signal(i == s)


# --- Barra de iconos por categorías con menús desplegables ---------------------------------------

func _build_side_menu() -> void:
	side_menu = PanelContainer.new()
	side_menu.add_theme_stylebox_override("panel", UIKit.float_style(Color(0.075, 0.082, 0.1, 0.9), 12, 5))
	side_menu.position = Vector2(8, BAR_H + 10)
	root.add_child(side_menu)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	side_menu.add_child(box)
	for cat in CATEGORIES:
		var cid := str(cat["id"])
		var b := UIKit.icon_button(str(cat["icon"]), func(): _on_category(cid), "", "", 22)
		b.custom_minimum_size = Vector2(44, 42)
		b.toggle_mode = true
		b.tooltip_text = _category_tip(cat)
		b.add_theme_stylebox_override("normal", UIKit._flat(Color(0, 0, 0, 0), 9, 4, 4))
		b.add_theme_stylebox_override("hover", UIKit._flat(Color(1, 1, 1, 0.07), 9, 4, 4))
		b.add_theme_stylebox_override("pressed", UIKit._flat(Color(UIKit.ACCENT, 0.22), 9, 4, 4, Color(UIKit.ACCENT, 0.5), 1))
		b.add_theme_stylebox_override("hover_pressed", UIKit._flat(Color(UIKit.ACCENT, 0.3), 9, 4, 4, UIKit.ACCENT, 1))
		b.add_theme_color_override("icon_normal_color", Color(0.8, 0.82, 0.86))
		b.mouse_entered.connect(func(): if flyout.visible and _flyout_cat != cid and cat["items"].size() > 1: open_category(cid))
		box.add_child(b)
		_cat_buttons[cid] = b
		if cid == "construir" or cid == "sociedad":
			var s := HSeparator.new()
			s.add_theme_constant_override("separation", 4)
			box.add_child(s)


func _category_tip(cat: Dictionary) -> String:
	var items: Array = cat["items"]
	if items.size() == 1:
		return "%s (%s)" % [cat["label"], items[0][3]]
	var lines := ["%s (%s)" % [cat["label"], cat["key"]]]
	for it in items:
		lines.append("  • %s%s" % [it[1], "  [%s]" % it[3] if str(it[3]) != "" else ""])
	return "\n".join(lines)


func _build_flyout() -> void:
	_catcher = Control.new()
	_catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_catcher.visible = false
	_catcher.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: close_category())
	root.add_child(_catcher)
	root.move_child(_catcher, side_menu.get_index())
	flyout = PanelContainer.new()
	flyout.add_theme_stylebox_override("panel", UIKit.float_style(Color(0.085, 0.092, 0.112, 0.97), 10, 8))
	flyout.visible = false
	root.add_child(flyout)
	_flyout_box = VBoxContainer.new()
	_flyout_box.add_theme_constant_override("separation", 2)
	flyout.add_child(_flyout_box)


func _on_category(cid: String) -> void:
	var cat := _category(cid)
	var items: Array = cat["items"]
	if items.size() == 1:
		close_category()
		_open_item(str(items[0][0]))
		return
	if flyout.visible and _flyout_cat == cid:
		close_category()
	else:
		open_category(cid)


func _category(cid: String) -> Dictionary:
	for c in CATEGORIES:
		if c["id"] == cid:
			return c
	return {}


## Abre el menú desplegable de una categoría junto a su icono.
func open_category(cid: String) -> void:
	var cat := _category(cid)
	if cat.is_empty():
		return
	_flyout_cat = cid
	UIKit.clear(_flyout_box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	head.add_child(UIKit.icon(str(cat["icon"]), 16, UIKit.ACCENT))
	head.add_child(UIKit.label(str(cat["label"]).to_upper(), 11, UIKit.ACCENT))
	_flyout_box.add_child(head)
	_flyout_box.add_child(HSeparator.new())
	for it in cat["items"]:
		var item_id := str(it[0])
		var b := Button.new()
		b.text = str(it[1])
		b.icon = UIIcons.tex(str(it[2]), 18)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(230, 34)
		b.add_theme_stylebox_override("normal", UIKit._flat(Color(0, 0, 0, 0), 7, 8, 4))
		b.add_theme_stylebox_override("hover", UIKit._flat(Color(UIKit.ACCENT, 0.14), 7, 8, 4))
		b.add_theme_stylebox_override("pressed", UIKit._flat(Color(UIKit.ACCENT, 0.24), 7, 8, 4))
		b.add_theme_constant_override("h_separation", 10)
		if _item_active(item_id):
			b.add_theme_color_override("font_color", UIKit.ACCENT)
			b.add_theme_color_override("icon_normal_color", UIKit.ACCENT)
		b.pressed.connect(func():
			close_category()
			_open_item(item_id))
		if str(it[3]) != "":
			var k := UIKit.label(str(it[3]), 11, UIKit.TEXT_FAINT)
			var kp := PanelContainer.new()
			kp.add_theme_stylebox_override("panel", UIKit._flat(Color(1, 1, 1, 0.06), 4, 5, 0, Color(1, 1, 1, 0.12), 1))
			kp.add_child(k)
			kp.anchor_left = 1.0
			kp.anchor_right = 1.0
			kp.anchor_top = 0.5
			kp.anchor_bottom = 0.5
			kp.offset_left = -30
			kp.offset_right = -8
			kp.offset_top = -10
			kp.offset_bottom = 10
			k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			kp.mouse_filter = Control.MOUSE_FILTER_IGNORE
			k.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(kp)
		b.tooltip_text = str(it[1]) + (" (%s)" % it[3] if str(it[3]) != "" else "")
		_flyout_box.add_child(b)
	flyout.visible = true
	_catcher.visible = true
	flyout.reset_size()
	var cb: Button = _cat_buttons[cid]
	var y := cb.get_global_rect().position.y - root.get_global_rect().position.y - 6.0
	flyout.position = Vector2(side_menu.position.x + side_menu.size.x + 6.0, y)
	_sync_category_buttons()
	cb.set_pressed_no_signal(true)
	UIKit.animate_in(flyout, Vector2(-10, 0), 0.14)


func close_category() -> void:
	if flyout == null:
		return
	flyout.visible = false
	_catcher.visible = false
	_flyout_cat = ""
	_sync_category_buttons()


func _item_active(item_id: String) -> bool:
	match item_id:
		"family":
			return dock.visible and dock_mode == "player"
		"catalog":
			return goods_catalog != null and goods_catalog.visible
		"world_econ", "stocks", "insurance":
			return global_econ != null and global_econ.visible and global_econ.tabs.current_tab == {"world_econ": 0, "stocks": 1, "insurance": 2}[item_id]
		"research":
			return research_screen != null and research_screen.visible
		"countries":
			return countries_window != null and countries_window.visible
		"aviation":
			return aviation_window != null and aviation_window.visible
		"population":
			return population_modal.has("root") and population_modal["root"].visible
		"towns":
			return dock.visible and dock_mode == "stats" and stats_panel.current_tab == "pueblos"
	return dock.visible and dock_mode == item_id


## Resalta la categoría del panel abierto.
func _sync_category_buttons() -> void:
	for cat in CATEGORIES:
		var active := false
		for it in cat["items"]:
			if _item_active(str(it[0])):
				active = true
		(_cat_buttons[cat["id"]] as Button).set_pressed_no_signal(active or _flyout_cat == cat["id"])


func _open_item(item_id: String) -> void:
	match item_id:
		"catalog":
			goods_catalog.open()
		"world_econ":
			close_dock()
			global_econ.open(0)
		"countries":
			close_dock()
			countries_window.open(0)
		"aviation":
			close_dock()
			aviation_window.open()
		"stocks":
			close_dock()
			global_econ.open(1)
		"insurance":
			close_dock()
			global_econ.open(2)
		"research":
			_open_research()
		"population":
			_open_population()
		"notifications":
			open_notifications()
		"family":
			_show_dock("player", true)
			player_panel.scroll_to_family()
		"towns":
			_show_dock("stats", true)
			stats_panel.show_tab("pueblos")
		_:
			_show_dock(item_id)
	_sync_category_buttons()


## Fase 10: muestra otro país (al llegar de un viaje o en vista remota): carga sus datos y rehace el mundo 3D.
func switch_country(iso: String) -> void:
	var r := CountriesSim.set_active(GameState, iso)
	if r != "":
		toast(r)
		return
	get_tree().change_scene_to_file("res://scenes/main.tscn")


# --- Notificaciones -----------------------------------------------------------------

func _build_toasts() -> void:
	toasts = VBoxContainer.new()
	toasts.anchor_left = 0.5
	toasts.anchor_right = 0.5
	toasts.offset_left = -220
	toasts.offset_right = 220
	toasts.offset_top = BAR_H + 8
	toasts.add_theme_constant_override("separation", 6)
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toasts)


func _on_notification(entry: Dictionary) -> void:
	var cat := str(entry.get("category", "info"))
	var text := str(entry["text"])
	unread += 1
	_update_bell()
	var now := Time.get_ticks_msec()
	# Agrupar: mismo texto → ×N; misma categoría reciente o demasiados avisos → "+N más".
	var visible_toasts := toasts.get_children().filter(func(t): return not t.get_meta("dying", false))
	for t in visible_toasts:
		if t.get_meta("cat") == cat and (t.get_meta("text") == text or now - int(t.get_meta("born")) < 2500 or visible_toasts.size() >= MAX_TOASTS):
			_group_toast(t, text)
			return
	var col: Color = UIKit.CATEGORY_COLORS.get(cat, UIKit.TEXT)
	var p := PanelContainer.new()
	var st := UIKit.card_style(col, 8, Color(0.07, 0.078, 0.095, 0.94))
	st.shadow_color = Color(0, 0, 0, 0.35)
	st.shadow_size = 6
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.set_meta("cat", cat)
	p.set_meta("text", text)
	p.set_meta("born", now)
	p.set_meta("left", TOAST_SECONDS)
	p.set_meta("count", 1)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", UIKit._flat(Color(col, 0.18), 7, 4, 4))
	badge.add_child(UIKit.icon(str(UIKit.CATEGORY_ICONS.get(cat, "info")), 18, col))
	badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(badge)
	var l := UIKit.label(text, 14, UIKit.TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.name = "Text"
	h.add_child(l)
	var more := UIKit.label("", 11, col)
	more.name = "More"
	more.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(more)
	toasts.add_child(p)
	while toasts.get_child_count() > MAX_TOASTS + 1:
		var old := toasts.get_child(0)
		toasts.remove_child(old)
		old.queue_free()
	var alive := toasts.get_children().filter(func(t): return not t.get_meta("dying", false))
	if alive.size() > MAX_TOASTS:
		_kill_toast(alive[0])
	# Entrada: aparece y "cae" levemente (escala vertical desde arriba)
	p.modulate.a = 0.0
	p.pivot_offset = Vector2(220, 0)
	p.scale = Vector2(0.96, 0.7)
	var tw := p.create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(p, "modulate:a", 1.0, 0.2)
	tw.tween_property(p, "scale", Vector2.ONE, 0.25)


func _group_toast(t: Control, text: String) -> void:
	var n := int(t.get_meta("count")) + 1
	t.set_meta("count", n)
	t.set_meta("left", TOAST_SECONDS)
	t.set_meta("born", Time.get_ticks_msec())
	var l: Label = t.find_child("Text", true, false)
	var m: Label = t.find_child("More", true, false)
	if t.get_meta("text") == text:
		m.text = "×%d" % n
	else:
		l.text = text
		t.set_meta("text", text)
		m.text = "+%d más" % (n - 1)
	t.pivot_offset = Vector2(220, 16)
	var tw := t.create_tween()
	tw.tween_property(t, "scale", Vector2(1.03, 1.03), 0.08)
	tw.tween_property(t, "scale", Vector2.ONE, 0.12)


func _kill_toast(t: Control) -> void:
	if t.get_meta("dying", false):
		return
	t.set_meta("dying", true)
	var tw := t.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(t, "modulate:a", 0.0, 0.35)
	tw.tween_property(t, "scale", Vector2(0.96, 0.85), 0.35)
	tw.chain().tween_callback(t.queue_free)


func _tick_toasts(delta: float) -> void:
	for t in toasts.get_children():
		if t.get_meta("dying", false):
			continue
		var left := float(t.get_meta("left")) - delta
		t.set_meta("left", left)
		if left <= 0.0:
			_kill_toast(t)


func _update_bell() -> void:
	if _bell_badge == null:
		return
	_bell_badge.visible = unread > 0
	_bell_count.text = str(unread) if unread < 100 else "99+"


# --- Panel lateral ------------------------------------------------------------------

func _build_dock() -> void:
	dock = UIKit.right_panel(DOCK_W)
	dock.offset_top = BAR_H + 8
	root.add_child(dock)
	var stack := Control.new()
	_dock_stack = stack
	dock.add_child(stack)
	# Ciudadano
	citizen_box = VBoxContainer.new()
	citizen_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	citizen_box.add_theme_constant_override("separation", 8)
	_cit_head = VBoxContainer.new()
	_cit_head.add_theme_constant_override("separation", 6)
	citizen_box.add_child(_cit_head)
	var sb := UIKit.scroll_box(Vector2(0, 100))
	sb["scroll"].size_flags_vertical = Control.SIZE_EXPAND_FILL
	citizen_box.add_child(sb["scroll"])
	_cit_meters = VBoxContainer.new()
	_cit_meters.add_theme_constant_override("separation", 6)
	sb["box"].add_child(_cit_meters)
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
	government_panel = GovernmentPanel.new()
	government_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(government_panel)
	government_panel.setup(self)
	government_panel.closed.connect(close_dock)
	government_panel.message.connect(toast)
	logistics_panel = LogisticsPanel.new()
	trade_panel = TradePanel.new()
	tourism_panel = TourismPanel.new()
	realestate_panel = RealEstatePanel.new()
	utilities_panel = UtilitiesPanel.new()
	contracts_panel = ContractsPanel.new()
	transit_panel = TransitPanel.new()
	cash_panel = CashPanel.new()
	for panel in [logistics_panel, trade_panel, tourism_panel, realestate_panel, utilities_panel, contracts_panel, transit_panel, cash_panel]:
		panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		stack.add_child(panel)
		panel.setup(self)
		panel.closed.connect(close_dock)
		panel.message.connect(toast)


func _show_dock(mode: String, keep_open := false) -> void:
	if dock.visible and dock_mode == mode and mode != "citizen" and mode != "building" and not keep_open:
		close_dock()
		return
	var was_open := dock.visible and dock_mode != ""
	var changed := dock_mode != mode
	dock_mode = mode
	dock.visible = true
	citizen_box.visible = mode == "citizen"
	building_panel.visible = mode == "building"
	build_menu.visible = mode == "build"
	companies_panel.visible = mode == "companies"
	player_panel.visible = mode == "player"
	finance_panel.visible = mode == "finance"
	stats_panel.visible = mode == "stats"
	government_panel.visible = mode == "government"
	logistics_panel.visible = mode == "logistics"
	trade_panel.visible = mode == "trade"
	tourism_panel.visible = mode == "tourism"
	contracts_panel.visible = mode == "contracts"
	realestate_panel.visible = mode == "realestate"
	utilities_panel.visible = mode == "utilities"
	transit_panel.visible = mode == "transit"
	cash_panel.visible = mode == "cash"
	match mode:
		"cash":
			cash_panel.refresh()
		"transit":
			transit_panel.refresh()
		"realestate":
			realestate_panel.refresh()
		"utilities":
			utilities_panel.refresh()
		"logistics":
			logistics_panel.refresh()
		"trade":
			trade_panel.refresh()
		"tourism":
			tourism_panel.refresh()
		"contracts":
			contracts_panel.refresh()
		"government":
			government_panel.refresh()
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
	if not was_open:
		_animate_dock(true)
	elif changed:
		_dock_stack.modulate.a = 0.0
		_dock_stack.create_tween().tween_property(_dock_stack, "modulate:a", 1.0, 0.14)
	_sync_category_buttons()


## Apertura/cierre del panel lateral: deslizamiento + opacidad (tween de los márgenes).
func _animate_dock(opening: bool) -> void:
	if _dock_tween != null and _dock_tween.is_valid():
		_dock_tween.kill()
	var base_l := -DOCK_W - 10.0
	var base_r := -10.0
	var shift := 28.0
	_dock_tween = dock.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC)
	if opening:
		dock.modulate.a = 0.0
		dock.offset_left = base_l + shift
		dock.offset_right = base_r + shift
		_dock_tween.set_ease(Tween.EASE_OUT)
		_dock_tween.tween_property(dock, "modulate:a", 1.0, 0.18)
		_dock_tween.tween_property(dock, "offset_left", base_l, 0.2)
		_dock_tween.tween_property(dock, "offset_right", base_r, 0.2)
	else:
		_dock_tween.set_ease(Tween.EASE_IN)
		_dock_tween.tween_property(dock, "modulate:a", 0.0, 0.14)
		_dock_tween.tween_property(dock, "offset_left", base_l + shift, 0.14)
		_dock_tween.tween_property(dock, "offset_right", base_r + shift, 0.14)
		_dock_tween.chain().tween_callback(func():
			if dock_mode == "":
				dock.visible = false
			dock.offset_left = base_l
			dock.offset_right = base_r
			dock.modulate.a = 1.0)


func close_dock() -> void:
	var was := dock.visible and dock_mode != ""
	dock_mode = ""
	citizen_id = -1
	if was and is_inside_tree():
		_animate_dock(false)
	else:
		dock.visible = false
	_sync_category_buttons()


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


## Ficha de persona: se reconstruye al seleccionar o tras una acción; el refresco periódico solo
## actualiza los indicadores.
func _refresh_citizen(rebuild: bool) -> void:
	if not GameState.citizens.has(citizen_id):
		close_dock()
		return
	var c: Citizen = GameState.citizens[citizen_id]
	if rebuild:
		_build_citizen_sheet(c)
		_citizen_action_buttons(c)
	else:
		_update_citizen_meters(c)


func _build_citizen_sheet(c: Citizen) -> void:
	var today := GameState.today()
	var me := GameState.is_player(c.id)
	UIKit.clear(_cit_head)
	# Cabecera: retrato + nombre + etiquetas + cerrar
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_cit_head.add_child(head)
	var portrait := Portrait.new()
	portrait.custom_minimum_size = Vector2(68, 68)
	portrait.set_citizen(c, me)
	head.add_child(portrait)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 3)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(nv)
	var name_l := UIKit.label(c.full_name() + ("  (tú)" if me else ""), 19, UIKit.ACCENT)
	name_l.clip_text = true
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nv.add_child(name_l)
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 4)
	chips.add_theme_constant_override("v_separation", 4)
	nv.add_child(chips)
	chips.add_child(UIKit.chip("%s · %d años" % ["Mujer" if c.gender == "F" else "Hombre", c.age_years(today)], UIKit.TEXT_DIM, "character"))
	var job := "Empresario(a)" if me else BusinessSim.job_label(GameState, c)
	chips.add_child(UIKit.chip(job, UIKit.ACCENT_2, "employment"))
	if not me:
		chips.add_child(UIKit.chip(PlayerSim.relation_label(GameState, c), Color(0.95, 0.62, 0.85), "heart"))
	if c.sick:
		chips.add_child(UIKit.chip("Enfermo/a", UIKit.BAD, "health"))
	if c.prison_until >= 0:
		chips.add_child(UIKit.chip("En la cárcel", UIKit.BAD, "crime"))
	var x := UIKit.icon_button("close", func(): EventBus.citizen_selected.emit(-1), "Cerrar (Esc)", "", 16)
	x.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(x)
	# Cuerpo desplazable
	UIKit.clear(_cit_meters)
	var meters := VBoxContainer.new()
	meters.name = "Meters"
	meters.add_theme_constant_override("separation", 4)
	_cit_meters.add_child(meters)
	_fill_meters(meters, c)
	# Patrimonio
	var money_row := HBoxContainer.new()
	money_row.add_theme_constant_override("separation", 6)
	_cit_meters.add_child(money_row)
	var cash := GameState.money if me else c.money
	var debt := EconomySim.player_debt(GameState) if me else c.debt
	money_row.add_child(_mini_stat("money", "Dinero", Fmt.money(cash), UIKit.sign_color(cash) if cash < 0 else UIKit.ACCENT))
	money_row.add_child(_mini_stat("finance", "Deudas", Fmt.money(debt), UIKit.BAD if debt > 0 else UIKit.NEUTRAL))
	if me:
		money_row.add_child(_mini_stat("treasury", "Patrimonio", Fmt.money_compact(EconomySim.net_worth(GameState)), UIKit.GOOD))
	else:
		money_row.add_child(_mini_stat("employment", "Salario/día", Fmt.money2(c.wage) if c.job_kind == "empleo" else "—", UIKit.ACCENT_2))
	# Educación y habilidades
	var sk := UIKit.section(_cit_meters, "Educación y habilidades", "education", true, "cit_skills")
	var edu := "%s%s · %.1f años de experiencia" % [GameData.education_label(c.education), " · %s" % GameData.profession_label(c.profession) if c.profession != "" else "", c.experience]
	sk.add_child(UIKit.label(edu, 12, UIKit.TEXT_DIM))
	var trades := LaborSim.trades_text(c)   # Trabajo: experiencia por oficio.
	if trades != "":
		var tl := UIKit.label("Oficios: " + trades, 12, UIKit.TEXT_DIM)
		tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sk.add_child(tl)
	if c.school_id >= 0:
		sk.add_child(UIKit.label("Estudia en %s (%.1f años)%s" % [GameState.building_label(GameState.get_building(c.school_id)), c.school_years + c.uni_years, " · " + GameData.career_label(c.career) if c.career != "" else ""], 12, UIKit.ACCENT_2))
	var keys := c.skills.keys()
	keys.sort_custom(func(a, b): return float(c.skills[a]) > float(c.skills[b]))
	for k in keys.slice(0, 4):
		sk.add_child(UIKit.meter_row("star", GameData.skill_label(k), float(c.skills[k]) / 100.0, str(int(c.skills[k])), false, UIKit.ACCENT_2))
	# Talentos (dinastía)
	var tal := HeirsSim.talents(GameState, c)
	if not tal.is_empty():
		var ts := UIKit.section(_cit_meters, "Talentos", "dynasty", true, "cit_talents")
		for k in HeirsSim.TALENTS:
			if tal.has(k):
				ts.add_child(UIKit.meter_row("dynasty", HeirsSim.talent_label(k), float(tal[k]) / 100.0, str(int(tal[k])), false, UIKit.ACCENT))
	# Familia en árbol
	var fs := UIKit.section(_cit_meters, "Familia", "family", true, "cit_family")
	var tree := FamilyTree.new()
	tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fs.add_child(tree)
	tree.set_person(c)
	tree.person_clicked.connect(func(pid): on_meta_clicked(pid))
	# Texto con vivienda, cárcel, ficha de matrimonio (enlaces clicables)
	var s := ""
	var home := GameState.get_building(c.home_id)
	s += "[color=#a7abb5]Vivienda:[/color] %s\n" % ("Sin hogar" if home.is_empty() else "%s (%s)" % [GameState.building_label(home), Housing.tier_label(str(home.get("tier", "normal")))])
	if c.prison_until >= 0:
		s += "[color=#f06a64]En la cárcel hasta el %s[/color]\n" % TimeManager.date_from_day(c.prison_until, TimeManager.start_year())
	if not me and PlayerSim.can_court(GameState, c) == "":
		s += MarriageSim.sheet_text(GameState, c) + "Aceptaría casarse contigo: ≈%d%%\n" % int(MarriageSim.proposal_chance(GameState, c) * 100.0)
	citizen_text.text = s.strip_edges()
	UIKit.animate_in(citizen_box, Vector2.ZERO, 0.15)


func _fill_meters(meters: VBoxContainer, c: Citizen) -> void:
	UIKit.clear(meters)
	meters.add_child(UIKit.meter_row("health", "Salud", c.health / 100.0))
	meters.add_child(UIKit.meter_row("happiness", "Felicidad", c.happiness / 100.0))
	meters.add_child(UIKit.meter_row("sprout", "Necesidades", c.needs_met))


func _update_citizen_meters(c: Citizen) -> void:
	var meters: Node = _cit_meters.get_node_or_null("Meters")
	if meters == null:
		return
	var vals := [c.health / 100.0, c.happiness / 100.0, c.needs_met]
	for i in range(mini(3, meters.get_child_count())):
		var row: HBoxContainer = meters.get_child(i)
		var pb: ProgressBar = row.get_child(2)
		if not is_equal_approx(pb.value, clampf(vals[i], 0.0, 1.0)):
			_fill_meters(meters, c)
			return


func _mini_stat(icon_name: String, title: String, value: String, color: Color) -> PanelContainer:
	var c := UIKit.card(Color(0, 0, 0, 0), 6)
	var p: PanelContainer = c["panel"]
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	h.add_child(UIKit.icon(icon_name, 14, color))
	h.add_child(UIKit.label(title, 11, UIKit.TEXT_DIM))
	c["box"].add_child(h)
	var v := UIKit.label(value, 15, color.lerp(UIKit.TEXT, 0.3))
	v.clip_text = true
	c["box"].add_child(v)
	return p


func _citizen_action_buttons(c: Citizen) -> void:
	UIKit.clear(citizen_actions)
	var cid := c.id
	var add := func(text: String, cb: Callable, enabled := true, tip := "", icon_name := ""):
		var b := UIKit.button(text, cb)
		if icon_name != "":
			b.icon = UIIcons.tex(icon_name, 16)
		b.disabled = not enabled
		b.tooltip_text = tip
		citizen_actions.add_child(b)
	if GameState.is_player(cid):
		add.call("Mi Personaje", func(): _show_dock("player"), true, "", "character")
	else:
		var talk_r := PlayerSim.can_talk(GameState, c)
		add.call("Conversar", func(): _act(PlayerSim.talk(GameState, GameState.citizens[cid])), talk_r == "", talk_r, "society")
		var court_r := PlayerSim.can_court(GameState, c)
		if court_r == "":
			add.call("Invitar a una cita", func(): _act(PlayerSim.date(GameState, GameState.citizens[cid])), true, "", "heart")
			add.call("Proponer matrimonio", func(): _act(PlayerSim.propose(GameState, GameState.citizens[cid])), true, "", "ring")
		var p := GameState.player_citizen()
		if p != null and c.home_id == p.home_id:
			add.call("Pedir que se vaya", func(): _act(PlayerSim.ask_to_leave(GameState, GameState.citizens[cid])), true, "", "exit")
		else:
			add.call("Invitar a vivir conmigo", func(): _act(PlayerSim.invite_to_live(GameState, GameState.citizens[cid])), true, "", "realestate")
		if PlayerSim.can_adopt_orphan(GameState, c) == "":
			add.call("Adoptar", func(): _act(PlayerSim.adopt_orphan(GameState, GameState.citizens[cid])), true, "", "baby")
	if c.home_id >= 0 and interior_bid != c.home_id:
		add.call("Ver su casa por dentro", func(): EventBus.interior_requested.emit(GameState.citizens[cid].home_id), true, "", "eye")
	if interior_bid < 0:
		add.call("Seguir con cámara", func(): follow_requested.emit(), true, "", "camera")
	add.call("Cerrar", func(): EventBus.citizen_selected.emit(-1), true, "", "close")


func _act(text: String) -> void:
	toast(text, "familia")
	_refresh_citizen(true)
	if interior_bid >= 0:
		_refresh_interior()


# --- Interior ------------------------------------------------------------------------------

func _build_interior_panel() -> void:
	interior_panel = PanelContainer.new()
	interior_panel.position = Vector2(10, BAR_H + 10)
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
	close_category()
	close_dock()
	_refresh_interior()
	UIKit.animate_in(interior_panel, Vector2(-18, 0))


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


func _build_hint() -> void:
	hint_panel = PanelContainer.new()
	var st := UIKit._flat(Color(0.05, 0.055, 0.07, 0.85), 16, 14, 6, Color(UIKit.ACCENT, 0.35), 1)
	hint_panel.add_theme_stylebox_override("panel", st)
	hint_panel.anchor_left = 0.5
	hint_panel.anchor_right = 0.5
	hint_panel.anchor_top = 1.0
	hint_panel.anchor_bottom = 1.0
	hint_panel.offset_left = -470
	hint_panel.offset_right = 470
	hint_panel.offset_top = -54
	hint_panel.offset_bottom = -14
	hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_panel.visible = false
	root.add_child(hint_panel)
	hint_lbl = UIKit.label("", 14, UIKit.ACCENT)
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_panel.add_child(hint_lbl)


# --- Modales ------------------------------------------------------------------------------

func _menu_button(text: String, icon_name: String, cb: Callable) -> Button:
	var b := UIKit.button(text, cb)
	b.icon = UIIcons.tex(icon_name, 18)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.y = 38
	b.add_theme_constant_override("h_separation", 10)
	return b


func _build_modals() -> void:
	pause_modal = UIKit.modal(root, "Menú", Vector2(420, 0), "menu")
	var pb: VBoxContainer = pause_modal["body"]
	pb.add_child(UIKit.primary(_menu_button("Continuar", "play", _close_pause)))
	pb.add_child(_menu_button("Guardar partida", "save", func(): _close(pause_modal); _open_save()))
	pb.add_child(_menu_button("Cargar partida", "folder", func(): _close(pause_modal); _open_load()))
	pb.add_child(_menu_button("Opciones", "settings", func(): _close(pause_modal); _open_options()))
	pb.add_child(_menu_button("Menú principal", "town", _to_main_menu))
	pb.add_child(UIKit.danger(_menu_button("Salir del juego", "exit", func(): get_tree().quit())))
	var controls := UIKit.label("Cámara: WASD/flechas o clic derecho para mover · Q/E o botón central para rotar · rueda o pellizco para zoom · Espacio pausa · 1-4 velocidades · 5 salto de años · R/T gira 15° y Shift+rueda gira libre al construir o mover.\nPaneles: P personaje · B construir · C empresas · V bienes raíces · K contratos · F finanzas · Y estadísticas · O catálogo · L logística · J transporte · U servicios · X comercio · Z población · G gobierno · I investigación · N notificaciones · F1-F5 categorías", 12, UIKit.TEXT_DIM)
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.custom_minimum_size.x = 400
	pb.add_child(controls)

	options_modal = UIKit.modal(root, "Opciones", Vector2(500, 0), "settings")
	_build_options(options_modal["body"])

	save_modal = UIKit.modal(root, "Guardar partida", Vector2(460, 0), "save")
	var sb: VBoxContainer = save_modal["body"]
	sb.add_child(UIKit.label("Nombre de la partida:"))
	save_name = LineEdit.new()
	sb.add_child(save_name)
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 8)
	sb.add_child(srow)
	srow.add_child(UIKit.primary(UIKit.button("Guardar", _do_save, 120)))
	srow.add_child(UIKit.button("Cancelar", func(): _close(save_modal), 120))

	load_modal = UIKit.modal(root, "Cargar partida", Vector2(560, 0), "folder")
	var lb: VBoxContainer = load_modal["body"]
	load_list = ItemList.new()
	load_list.custom_minimum_size = Vector2(520, 260)
	lb.add_child(load_list)
	var lrow := HBoxContainer.new()
	lrow.add_theme_constant_override("separation", 8)
	lb.add_child(lrow)
	lrow.add_child(UIKit.primary(UIKit.button("Cargar", _do_load, 120)))
	lrow.add_child(UIKit.danger(UIKit.button("Borrar", _do_delete, 120)))
	lrow.add_child(UIKit.button("Cancelar", func(): _close(load_modal), 120))

	jump_modal = UIKit.modal(root, "Avance rápido", Vector2(460, 0), "jump")
	var jb: VBoxContainer = jump_modal["body"]
	var jl := UIKit.label("Se simulará el periodo de forma resumida y al final verás un reporte.", 14, UIKit.TEXT_DIM)
	jl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	jb.add_child(jl)
	var jrow := HBoxContainer.new()
	jrow.add_theme_constant_override("separation", 8)
	jb.add_child(jrow)
	for y in GameData.game.get("jump_options_years", [2, 5, 10]):
		var years := int(y)
		var b := UIKit.button("%d años" % years, func(): _close(jump_modal); TimeManager.start_jump(years), 110)
		b.icon = UIIcons.tex("jump", 16)
		jrow.add_child(b)
	jb.add_child(UIKit.button("Cancelar", func(): _close(jump_modal)))

	progress_modal = UIKit.modal(root, "Simulando…", Vector2(460, 0), "realtime")
	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(420, 22)
	progress_bar.add_theme_stylebox_override("fill", UIKit._flat(UIKit.ACCENT, 6, 0, 0))
	progress_modal["body"].add_child(progress_bar)

	report_modal = UIKit.modal(root, "Reporte del periodo", Vector2(560, 0), "stats")
	report_text = RichTextLabel.new()
	report_text.bbcode_enabled = true
	report_text.custom_minimum_size = Vector2(520, 380)
	report_modal["body"].add_child(report_text)
	report_modal["body"].add_child(UIKit.primary(UIKit.button("Continuar", func(): _close(report_modal))))

	population_modal = UIKit.modal(root, "Población", Vector2(760, 0), "population")
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 8)
	population_modal["body"].add_child(prow)
	prow.add_child(UIKit.icon("filter", 16))
	pop_search = LineEdit.new()
	pop_search.placeholder_text = "Buscar por nombre o trabajo…"
	pop_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pop_search.text_changed.connect(func(_t): _filter_population())
	prow.add_child(pop_search)
	prow.add_child(UIKit.label("Clic en el encabezado para ordenar · clic en una fila para ver la ficha", 11, UIKit.TEXT_FAINT))
	pop_table = DataTable.new()
	pop_table.custom_minimum_size = Vector2(720, 420)
	pop_table.row_clicked.connect(func(r): _on_pop_activated(int(r["id"])))
	population_modal["body"].add_child(pop_table)
	population_modal["body"].add_child(UIKit.button("Cerrar", func(): _close(population_modal)))

	log_modal = UIKit.modal(root, "Centro de notificaciones", Vector2(700, 0), "bell")
	log_filters = UIKit.flow(4, 4)
	log_modal["body"].add_child(log_filters)
	var lsb := UIKit.scroll_box(Vector2(660, 420))
	log_box = lsb["box"]
	log_box.add_theme_constant_override("separation", 2)
	log_modal["body"].add_child(lsb["scroll"])
	var lrow2 := HBoxContainer.new()
	lrow2.add_theme_constant_override("separation", 8)
	log_modal["body"].add_child(lrow2)
	lrow2.add_child(UIKit.button("Cerrar", func(): _close(log_modal)))

	gameover_modal = UIKit.modal(root, "Fin de la dinastía", Vector2(460, 0), "tomb")
	var gl := UIKit.label("Tu personaje murió sin hijos que hereden. Ten o adopta hijos y elige un heredero para continuar tu dinastía.", 15)
	gl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gl.custom_minimum_size.x = 420
	gameover_modal["body"].add_child(gl)
	gameover_modal["body"].add_child(UIKit.button("Cargar partida", func(): _close(gameover_modal); _open_load()))
	gameover_modal["body"].add_child(UIKit.button("Menú principal", _to_main_menu))

	details_modal = UIKit.modal(root, "Nuevo negocio", Vector2(460, 0), "companies")
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
	drow.add_theme_constant_override("separation", 8)
	db.add_child(drow)
	drow.add_child(UIKit.primary(UIKit.button("Construir", func():
		_close(details_modal)
		details_cb.call(details_name.text.strip_edges(), str(details_legal.get_item_metadata(details_legal.selected))))))
	drow.add_child(UIKit.button("Cancelar", func(): _close(details_modal)))

	invite_modal = UIKit.modal(root, "Invitar a vivir contigo", Vector2(560, 0), "realestate")
	var isb := UIKit.scroll_box(Vector2(520, 360))
	invite_box = isb["box"]
	invite_modal["body"].add_child(isb["scroll"])
	invite_modal["body"].add_child(UIKit.button("Cerrar", func(): _close(invite_modal)))


## Opciones: tamaño de la interfaz (se guarda en user://ui_settings.cfg) y, si el agente de gráficos
## lo expone, la calidad gráfica (autoload GraphicsSettings: build_options_ui(caja) o set_quality(i)).
func _build_options(body: VBoxContainer) -> void:
	body.add_child(UIKit.label("Tamaño de la interfaz", 16, UIKit.ACCENT))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	body.add_child(row)
	row.add_child(UIKit.label("A", 12, UIKit.TEXT_DIM))
	var sl := HSlider.new()
	sl.min_value = 0.7
	sl.max_value = 1.6
	sl.step = 0.05
	sl.value = UIKit.user_scale()
	sl.custom_minimum_size = Vector2(300, 24)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sl)
	row.add_child(UIKit.label("A", 20, UIKit.TEXT_DIM))
	_scale_lbl = UIKit.label("", 13, UIKit.TEXT)
	body.add_child(_scale_lbl)
	sl.value_changed.connect(func(v: float): _scale_lbl.text = "Ajuste: %d%% (se aplica al soltar)" % int(roundf(v * 100.0)))
	sl.drag_ended.connect(func(_c: bool):
		UIKit.set_user_scale(sl.value, get_window())
		_update_scale_label())
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 8)
	body.add_child(brow)
	for preset in [[0.85, "Compacta"], [1.0, "Normal"], [1.2, "Grande"], [1.4, "Muy grande"]]:
		var v: float = preset[0]
		brow.add_child(UIKit.button(preset[1], func():
			sl.set_value_no_signal(v)
			UIKit.set_user_scale(v, get_window())
			_update_scale_label()))
	var note := UIKit.label("La escala se ajusta sola a pantallas Retina/HiDPI y ventanas grandes; este ajuste la multiplica.", 12, UIKit.TEXT_FAINT)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 440
	body.add_child(note)
	# Calidad gráfica (Baja/Media/Alta): GraphicsSettings (scripts/world/graphics_settings.gd).
	body.add_child(HSeparator.new())
	body.add_child(UIKit.label("Gráficos", 16, UIKit.ACCENT))
	body.add_child(GraphicsSettings.make_selector())
	body.add_child(HSeparator.new())
	body.add_child(UIKit.primary(UIKit.button("Listo", func(): _close(options_modal))))


func _update_scale_label() -> void:
	if _scale_lbl == null:
		return
	var win := get_window()
	_scale_lbl.text = "Ajuste: %d%% · escala efectiva ×%s (ventana %d×%d)" % [int(roundf(UIKit.user_scale() * 100.0)), String.num(win.content_scale_factor, 2), win.size.x, win.size.y]


func _open_options() -> void:
	_update_scale_label()
	_open(options_modal)


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
	close_category()
	m["root"].visible = true


func _close(m: Dictionary) -> void:
	m["root"].visible = false


func _all_modals() -> Array:
	return [pause_modal, save_modal, load_modal, jump_modal, progress_modal, report_modal, population_modal, log_modal, gameover_modal, details_modal, invite_modal, options_modal, building_panel.hire_modal]


func _any_modal_open() -> bool:
	for m in _all_modals():
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
	close_category()
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
		var idx := load_list.add_item("%s — %s — %s · pobl. %d   [%s]" % [s["slot"], sm.get("town", ""), sm.get("date", ""), int(sm.get("population", 0)), s["saved_at"]], UIIcons.tex("save", 16))
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
	var dm := float(r["end_money"]) - float(r["start_money"])
	var s := "[font_size=16][b]%s → %s[/b][/font_size]\n\n" % [r["start_date"], r["end_date"]]
	s += "[table=2][cell][color=#a7abb5]Población[/color]  [/cell][cell]%d → [b]%d[/b][/cell]" % [r["start_population"], r["end_population"]]
	s += "[cell][color=#a7abb5]Nacimientos / muertes[/color]  [/cell][cell][color=#66d480]%d[/color] / [color=#f06a64]%d[/color] · bodas %d[/cell]" % [int(c.get("births", 0)), int(c.get("deaths", 0)), int(c.get("marriages", 0))]
	s += "[cell][color=#a7abb5]Emigrantes / enfermedades[/color]  [/cell][cell]%d / %d[/cell]" % [int(c.get("emigrated", 0)), int(c.get("illnesses", 0))]
	s += "[cell][color=#a7abb5]Tu dinero[/color]  [/cell][cell]%s → [b]%s[/b] [color=#%s](%s%s)[/color][/cell]" % [Fmt.money(r["start_money"]), Fmt.money(r["end_money"]), UIKit.sign_color(dm).to_html(false), "+" if dm >= 0 else "", Fmt.money(dm)]
	s += "[cell][color=#a7abb5]Ingresos / gastos[/color]  [/cell][cell][color=#66d480]%s[/color] / [color=#f06a64]%s[/color][/cell]" % [Fmt.money(float(c.get("income", 0))), Fmt.money(float(c.get("expenses", 0)))]
	s += "[cell][color=#a7abb5]Felicidad promedio[/color]  [/cell][cell]%s → %s[/cell][/table]\n" % [Fmt.pct(r["start_happiness"]), Fmt.pct(r["end_happiness"])]
	var notes: Array = r.get("notes", [])
	if not notes.is_empty():
		s += "\n[b]Eventos destacados[/b]\n"
		for n in notes:
			var col: Color = UIKit.CATEGORY_COLORS.get(str(n.get("category", "info")), UIKit.TEXT)
			s += "[color=#%s]●[/color] [color=#8a8f99]%s[/color] %s\n" % [col.to_html(false), n["date"], n["text"]]
	report_text.text = s
	_open(report_modal)


func _on_player_died() -> void:
	_open(gameover_modal)


# --- Población (tabla ordenable) -----------------------------------------------------------------

func _open_population() -> void:
	_pop_rows.clear()
	var today := GameState.today()
	for c in GameState.citizens.values():
		var me := GameState.is_player(c.id)
		_pop_rows.append({"id": c.id, "name": c.full_name() + (" (tú)" if me else ""), "age": c.age_years(today),
			"sex": "M" if c.gender == "F" else "H", "health": c.health / 100.0, "happy": c.happiness / 100.0,
			"job": BusinessSim.job_label(GameState, c) + (" · enfermo" if c.sick else ""),
			"rel": "tú" if me else PlayerSim.relation_label(GameState, c), "money": GameState.money if me else c.money,
			"_color": UIKit.ACCENT if me else (UIKit.BAD if c.sick else UIKit.TEXT)})
	population_modal["title"].text = "Población (%d)" % _pop_rows.size()
	pop_search.text = ""
	_filter_population()
	_open(population_modal)
	_sync_category_buttons()


func _filter_population() -> void:
	var q := pop_search.text.strip_edges().to_lower()
	var rows := _pop_rows if q == "" else _pop_rows.filter(func(r): return str(r["name"]).to_lower().contains(q) or str(r["job"]).to_lower().contains(q) or str(r["rel"]).to_lower().contains(q))
	if pop_table.sort_col < 0:
		pop_table.sort_col = 0
		pop_table.sort_desc = false
	pop_table.set_data([
		{"title": "Nombre", "key": "name", "w": 2.4},
		{"title": "Edad", "key": "age", "w": 0.6, "fmt": "int"},
		{"title": "Sexo", "key": "sex", "w": 0.5, "align": "center"},
		{"title": "Salud", "key": "health", "w": 1.3, "fmt": "bar"},
		{"title": "Felicidad", "key": "happy", "w": 1.3, "fmt": "bar"},
		{"title": "Trabajo", "key": "job", "w": 1.9},
		{"title": "Relación", "key": "rel", "w": 1.2},
		{"title": "Dinero", "key": "money", "w": 1.0, "fmt": "money"},
	], rows, 17)
	pop_table.custom_minimum_size = Vector2(720, 440)


func _on_pop_activated(id: int) -> void:
	_close(population_modal)
	EventBus.citizen_selected.emit(id)
	var world := get_parent()
	if world.has_method("focus_citizen"):
		world.focus_citizen(id)


# --- Centro de notificaciones ---------------------------------------------------------------------

func open_notifications() -> void:
	unread = 0
	_update_bell()
	_rebuild_log()
	_open(log_modal)


func _open_log() -> void:
	open_notifications()


func _rebuild_log() -> void:
	var counts := {}
	for e in GameState.notifications_log:
		var cat := str(e["category"])
		counts[cat] = int(counts.get(cat, 0)) + 1
	UIKit.clear(log_filters)
	var all_b := _filter_chip("Todas", "list", UIKit.TEXT, GameState.notifications_log.size(), _log_filter.is_empty())
	all_b.pressed.connect(func():
		_log_filter.clear()
		_rebuild_log())
	log_filters.add_child(all_b)
	var cats := counts.keys()
	cats.sort_custom(func(a, b): return int(counts[a]) > int(counts[b]))
	for cat in cats:
		var cs := str(cat)
		var b := _filter_chip(str(UIKit.CATEGORY_LABELS.get(cs, cs.capitalize())), str(UIKit.CATEGORY_ICONS.get(cs, "info")), UIKit.CATEGORY_COLORS.get(cs, UIKit.TEXT), int(counts[cat]), bool(_log_filter.get(cs, false)))
		b.pressed.connect(func():
			if _log_filter.get(cs, false):
				_log_filter.erase(cs)
			else:
				_log_filter[cs] = true
			_rebuild_log())
		log_filters.add_child(b)
	UIKit.clear(log_box)
	var shown := 0
	var list: Array = GameState.notifications_log
	for i in range(list.size() - 1, -1, -1):
		var e: Dictionary = list[i]
		var cat := str(e["category"])
		if not _log_filter.is_empty() and not _log_filter.has(cat):
			continue
		var col: Color = UIKit.CATEGORY_COLORS.get(cat, UIKit.TEXT)
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UIKit.card_style(col, 6, Color(1, 1, 1, 0.03) if shown % 2 == 0 else Color(0, 0, 0, 0)))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		row.add_child(h)
		h.add_child(UIKit.icon(str(UIKit.CATEGORY_ICONS.get(cat, "info")), 16, col))
		var d := UIKit.label(str(e["date"]), 11, UIKit.TEXT_FAINT)
		d.custom_minimum_size.x = 118
		h.add_child(d)
		var t := UIKit.label(str(e["text"]), 13, UIKit.TEXT)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(t)
		log_box.add_child(row)
		shown += 1
		if shown >= 150:
			break
	if shown == 0:
		log_box.add_child(UIKit.label("No hay notificaciones con este filtro.", 13, UIKit.TEXT_DIM))


func _filter_chip(text: String, icon_name: String, color: Color, count: int, on: bool) -> Button:
	var b := Button.new()
	b.text = "%s  %d" % [text, count]
	b.icon = UIIcons.tex(icon_name, 14)
	b.toggle_mode = true
	b.set_pressed_no_signal(on)
	b.add_theme_font_size_override("font_size", 12)
	b.add_theme_stylebox_override("normal", UIKit._flat(Color(color, 0.08), 12, 9, 3, Color(color, 0.3), 1))
	b.add_theme_stylebox_override("hover", UIKit._flat(Color(color, 0.16), 12, 9, 3, Color(color, 0.6), 1))
	b.add_theme_stylebox_override("pressed", UIKit._flat(Color(color, 0.3), 12, 9, 3, color, 1))
	b.add_theme_stylebox_override("hover_pressed", UIKit._flat(Color(color, 0.36), 12, 9, 3, color, 1))
	b.add_theme_color_override("icon_normal_color", color)
	b.add_theme_color_override("icon_pressed_color", color.lightened(0.3))
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	return b


# --- Entrada y refresco ----------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key: Key = event.keycode
	if key == KEY_ESCAPE:
		if flyout != null and flyout.visible:
			close_category()
		elif goods_catalog.visible:
			goods_catalog.close()
		elif global_econ.visible:
			global_econ.close()
		elif research_screen.visible:
			research_screen.close()
		elif pause_modal["root"].visible:
			_close_pause()
		elif _any_modal_open():
			for m in [save_modal, load_modal, jump_modal, report_modal, population_modal, log_modal, details_modal, invite_modal, options_modal, building_panel.hire_modal]:
				_close(m)
		elif interior_bid >= 0:
			_close_interior()
		elif dock.visible and dock_mode != "":
			close_dock()
		else:
			_open_pause()
		get_viewport().set_input_as_handled()
		return
	if _any_modal_open() or TimeManager.jumping:
		return
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
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
		KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5:
			if interior_bid < 0:
				var cid: String = ["dinastia", "empresas", "economia", "logistica", "sociedad"][key - KEY_F1]
				_on_category(cid)
		_:
			if SHORTCUTS.has(key) and interior_bid < 0:
				close_category()
				_open_item(str(SHORTCUTS[key]))
			else:
				return
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_tick_toasts(delta)
	_refresh += delta
	_slow_refresh -= delta
	if _refresh >= 0.25:
		_refresh = 0.0
		_update_top_bar()
		if dock.visible:
			match dock_mode:
				"citizen":
					_refresh_citizen(false)
				"building":
					building_panel.refresh()
