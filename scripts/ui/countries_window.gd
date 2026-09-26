class_name CountriesWindow
extends Control
## Fase 10: pantalla completa con dos pestañas.
## - Mapa mundial: países reales (o los de respaldo), tu presencia, dónde estás, viajes y aviones en ruta.
##   Al elegir un país: comprar licencia, comprar el terreno de entrada, viajar y verlo (vista remota).
## - Mis países: presencia, gerente (contratar, despedir, aumentos) y resultados de cada país.
## Uso desde el HUD:  var w := CountriesWindow.new(); root.add_child(w); w.setup(); … w.open(0)

signal message(text: String, category: String)
signal view_requested(iso: String)

var tabs: TabContainer
var map_view: GameWorldMap
var side_info: RichTextLabel
var side_actions: VBoxContainer
var picker: OptionButton
var mine_box: VBoxContainer
var _built := false
var _picker_ids: Array = []


func setup() -> void:
	if _built:
		return
	_built = true
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.float_style(UIKit.BG, 14, 16))
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 50
	panel.offset_right = -50
	panel.offset_top = 60
	panel.offset_bottom = -26
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	UIKit.header(v, "globe", "Países: mapa mundial y presencia", close)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tabs)
	# Pestaña 1: mapa mundial + lateral.
	var h := HBoxContainer.new()
	h.name = "Mapa mundial"
	h.add_theme_constant_override("separation", 12)
	tabs.add_child(h)
	map_view = GameWorldMap.new()
	h.add_child(map_view)
	map_view.selected_changed.connect(_on_select)
	var side_sc := ScrollContainer.new()
	side_sc.custom_minimum_size.x = 340
	side_sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	h.add_child(side_sc)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 8)
	side_sc.add_child(side)
	side.add_child(UIKit.label("País", 13, UIKit.TEXT_DIM))
	picker = OptionButton.new()
	picker.item_selected.connect(func(i): if i >= 0 and i < _picker_ids.size(): map_view.select(str(_picker_ids[i])))
	side.add_child(picker)
	side_info = UIKit.rich()
	side.add_child(side_info)
	side_actions = VBoxContainer.new()
	side_actions.add_theme_constant_override("separation", 6)
	side.add_child(side_actions)
	var note := UIKit.label("Dorado: presencia · gris: solo licencia · verde: dónde estás · azul: carga aérea en vuelo.", 12, UIKit.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(note)
	# Pestaña 2: Mis países.
	var sc := ScrollContainer.new()
	sc.name = "Mis países"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(sc)
	mine_box = VBoxContainer.new()
	mine_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mine_box.add_theme_constant_override("separation", 10)
	sc.add_child(mine_box)
	tabs.set_tab_icon(0, UIIcons.tex("globe", 16))
	tabs.set_tab_icon(1, UIIcons.tex("dynasty", 16))
	tabs.tab_changed.connect(func(_i): refresh())
	EventBus.day_passed.connect(func(): if visible and tabs.current_tab == 1: refresh())


func open(tab := -1) -> void:
	setup()
	var was := visible
	visible = true
	if not was:
		UIKit.animate_in(self, Vector2.ZERO, 0.16)
	if tab >= 0 and tab < tabs.get_tab_count():
		tabs.current_tab = tab
	refresh()


func close() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func refresh() -> void:
	if not visible or not CountriesSim.ready(GameState):
		return
	if tabs.current_tab == 0:
		_fill_picker()
		map_view.select(map_view.selected if map_view.selected != "" else CountriesSim.active_id(GameState))
	else:
		_build_mine()


func _fill_picker() -> void:
	var gs := GameState
	var ids: Array = CountriesSim.enterable_ids(gs)
	if ids == _picker_ids:
		return
	_picker_ids = ids.duplicate()
	picker.clear()
	for iso in _picker_ids:
		var mark := " ●" if CountriesSim.has_presence(gs, iso) else (" ○" if CountriesSim.has_context(gs, iso) else "")
		picker.add_item(CountriesSim.country_label(iso) + mark)


# --- Mapa mundial: país elegido ---------------------------------------------------------------------

func _on_select(iso: String) -> void:
	var gs := GameState
	if not CountriesSim.ready(gs):
		return
	var idx := _picker_ids.find(iso)
	if idx >= 0 and picker.selected != idx:
		picker.select(idx)
	UIKit.clear(side_actions)
	if iso == "":
		side_info.text = "Haz clic en un país."
		return
	side_info.text = info_text(gs, iso)
	if not CountriesSim.enterable_ids(gs).has(iso):
		return
	var home := CountriesSim.home_id(gs)
	if iso != home and not CountriesSim.has_context(gs, iso):
		_action("Comprar licencia de inversión (%s)" % Fmt.money(CountriesSim.license_cost(gs, iso)), CountriesSim.license_block_reason(gs, iso),
				func(): return CountriesSim.buy_license(gs, iso), true)
	elif iso != home and not CountriesSim.has_presence(gs, iso):
		_action("Comprar terreno de entrada (%s)" % Fmt.money(CountriesSim.entry_land_cost(gs, iso)), CountriesSim.entry_land_block_reason(gs, iso),
				func(): return CountriesSim.buy_entry_land(gs, iso), true)
	if CountriesSim.has_context(gs, iso) and CountriesSim.location(gs) != iso and not TravelSim.traveling(gs):
		var q := TravelSim.quote(gs, CountriesSim.location(gs), iso)
		_action("Viajar: %s, %d días, %s" % [str(q["label"]).to_lower(), int(q["days"]), Fmt.money(float(q["cost"]))], TravelSim.block_reason(gs, iso),
				func(): return TravelSim.start(gs, iso), false)
	if CountriesSim.has_context(gs, iso) and iso != CountriesSim.active_id(gs):
		var remote := CountriesSim.location(gs) != iso and not ManagerSim.has_manager(gs, iso)
		_action("Ver %s%s" % [CountriesSim.country_label(iso), " (vista remota, sin control)" if remote else ""], "",
				_view_cb(iso), false)


func _action(text: String, reason: String, cb: Callable, primary: bool) -> void:
	var b := UIKit.button(text, func():
		var r = cb.call()
		if str(r) != "":
			message.emit(str(r), "info")
		refresh()
		_on_select(map_view.selected))
	b.disabled = reason != ""
	b.tooltip_text = reason
	b.clip_text = true
	if primary:
		UIKit.primary(b)
	side_actions.add_child(b)
	if reason != "":
		var l := UIKit.label(reason, 12, UIKit.BAD)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		side_actions.add_child(l)


## Ficha del país (estática: también sirve sin interfaz).
static func info_text(gs, iso: String) -> String:
	var home := CountriesSim.home_id(gs)
	var s := "[b][color=#f2c65a]%s[/color][/b]\n" % CountriesSim.country_label(iso)
	var cd := MapSim.country_def(iso)
	var cur: Dictionary = cd.get("currency", {})
	s += "Moneda: %s (%s) · 1 %s = %s %s\n" % [str(cur.get("name", "")), str(cur.get("symbol", "")), GlobalEconSim.currency_symbol(home),
			_n(GlobalEconSim.fx(gs, home, iso)), str(cur.get("symbol", ""))]
	var md := CountriesSim.mods(iso)
	s += "Impuestos ×%.2f · arancel a la carga %d %% · estabilidad %d %%\n" % [float(md["tax_mult"]), int(float(md["tariff"]) * 100.0), int(float(md.get("stability", 0.6)) * 100.0)]
	if iso != home:
		var q := TravelSim.quote(gs, CountriesSim.location(gs) if CountriesSim.location(gs) != "" else home, iso)
		s += "Distancia: %d km · viaje: %s, %d días, %s\n" % [int(q["km"]), str(q["label"]).to_lower(), int(q["days"]), Fmt.money(float(q["cost"]))]
	if iso == home:
		s += "[color=#8fd18f]Tu país de origen.[/color]\n"
	elif CountriesSim.has_presence(gs, iso):
		s += "[color=#8fd18f]Tienes presencia.[/color]\n"
	elif CountriesSim.has_context(gs, iso):
		s += "[color=#e9b949]Licencia comprada: falta el terreno de entrada.[/color]\n"
	else:
		s += "Licencia de inversión: %s (luego, el terreno de entrada).\n" % Fmt.money(CountriesSim.license_cost(gs, iso))
	if CountriesSim.has_context(gs, iso):
		s += "Gerente: %s\n" % ManagerSim.label(gs, iso)
	if CountriesSim.location(gs) == iso:
		s += "[color=#8fd18f]Tu personaje está aquí.[/color]\n"
	return s


static func _n(v: float) -> String:
	if v >= 100.0:
		return Fmt.thousands(v)
	return ("%.4f" % v).replace(".", ",")


# --- Mis países ----------------------------------------------------------------------------------

func _build_mine() -> void:
	var gs := GameState
	UIKit.clear(mine_box)
	var intro := UIKit.label("Una sola cuenta para todos tus países; los montos de cada país se muestran también en su moneda. Donde no está tu personaje hace falta un gerente: sin él las obras no avanzan y los negocios rinden menos.", 13, UIKit.TEXT_DIM)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mine_box.add_child(intro)
	for iso in CountriesSim.licensed_ids(gs):
		_country_card(gs, iso)
	var stats: Dictionary = gs.countries.get("stats", {})
	var foot := UIKit.rich()
	foot.text = "[color=#aab]Pagado en licencias: %s · en pasajes: %s · aranceles de la carga aérea: %s[/color]" % [Fmt.money(float(stats.get("licenses", 0.0))),
			Fmt.money(float(stats.get("travel_spent", 0.0))), Fmt.money(float(AirSim.st(gs).get("stats", {}).get("tariffs", 0.0)))]
	mine_box.add_child(foot)


func _country_card(gs, iso: String) -> void:
	var home := CountriesSim.home_id(gs)
	var here := CountriesSim.location(gs) == iso
	var stripe := UIKit.GOOD if here or ManagerSim.has_manager(gs, iso) else UIKit.BAD
	var c := UIKit.card(stripe, 10)
	mine_box.add_child(c["panel"])
	var box: VBoxContainer = c["box"]
	var title := UIKit.label("%s%s" % [CountriesSim.country_label(iso), "  (origen)" if iso == home else ""], 17, UIKit.ACCENT)
	box.add_child(title)
	var sm := CountriesSim.summary(gs, iso)
	var p := CountriesSim.presence(gs, iso)
	var lm: Dictionary = p.get("last_month", {})
	var t := UIKit.rich()
	var s := "Estado: [b]%s[/b]\n" % ("tu personaje está aquí" if here else ("con gerente" if ManagerSim.has_manager(gs, iso) else "sin gerente ni presencia")) if bool(p.get("entered", false)) \
			else "Estado: [b]solo licencia[/b] (compra el terreno de entrada en el mapa mundial)\n"
	s += "Pueblo: %s · población %d · tus edificios %d (%d negocios, %d obras) · tesoro del país %s\n" % [str(sm.get("town", "")), int(sm.get("population", 0)),
			int(sm.get("buildings", 0)), int(sm.get("businesses", 0)), int(sm.get("works", 0)), GlobalEconSim.fmt_foreign(gs, float(sm.get("treasury", 0.0)) * GlobalEconSim.fx(gs, home, iso), iso)]
	if not lm.is_empty():
		var profit := float(lm.get("profit", 0.0))
		s += "Último mes: ingresos %s · gastos %s · resultado [color=%s]%s[/color]\n" % [Fmt.money(float(lm.get("income", 0.0))), Fmt.money(float(lm.get("expenses", 0.0))),
				"#8fd18f" if profit >= 0.0 else "#e57373", GlobalEconSim.fmt_foreign(gs, profit * GlobalEconSim.fx(gs, home, iso), iso)]
	s += "Rendimiento de tus negocios ×%.2f · obras %s\n" % [ManagerSim.output_mult(gs, iso), "avanzan" if CountriesSim.can_control(gs, iso) else "[color=#e57373]detenidas[/color]"]
	var perf: Dictionary = CountriesSim.perf().get(iso, {})
	if not perf.is_empty():
		s += "[color=#aab]Simulación: %.1f ms por día[/color]\n" % float(perf.get("avg", 0.0))
	t.text = s
	box.add_child(t)
	if not bool(p.get("entered", false)):
		return
	# Gerente.
	var m := ManagerSim.manager(gs, iso)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	box.add_child(row)
	if m.is_empty():
		row.add_child(UIKit.label("Contratar gerente:", 13, UIKit.TEXT_DIM))
		for o in ManagerSim.candidates(gs, iso).slice(0, 3):
			var cid := int(o["citizen_id"])
			var b := UIKit.button("%s · %s · %s/mes · %d %%" % [o["name"], o["level_label"], Fmt.money(float(o["salary"])), int(float(o["eff"]) * 100.0)],
					func(): _do(ManagerSim.hire(gs, iso, cid)))
			row.add_child(b)
	else:
		row.add_child(UIKit.label("Gerente: %s" % ManagerSim.label(gs, iso), 13))
		var rq: Dictionary = m.get("raise", {})
		if not rq.is_empty():
			row.add_child(UIKit.primary(UIKit.button("Aceptar aumento a %s" % Fmt.money(float(rq["amount"])), func(): _do(ManagerSim.accept_raise(gs, iso)))))
			row.add_child(UIKit.button("Rechazar", func(): _do(ManagerSim.reject_raise(gs, iso))))
		row.add_child(UIKit.danger(UIKit.button("Despedir", _dismiss.bind(iso))))
		if float(m.get("stolen", 0.0)) > 0.0:
			row.add_child(UIKit.label("Faltantes detectados: %s" % Fmt.money(float(m["stolen"])), 12, UIKit.BAD))
	if iso != CountriesSim.active_id(gs):
		row.add_child(UIKit.button("Ver país", func(): view_requested.emit(iso)))


func _view_cb(iso: String) -> Callable:
	return func():
		view_requested.emit(iso)
		return ""


func _dismiss(iso: String) -> void:
	ManagerSim.dismiss(GameState, iso, "despedido")
	_do("")


func _do(r: String) -> void:
	if r != "":
		message.emit(r, "info")
	refresh()
