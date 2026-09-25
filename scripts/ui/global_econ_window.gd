class_name GlobalEconWindow
extends Control
## Economía mundial: pantalla completa con pestañas Ciclos y monedas, Bolsa (StockPanel) y Seguros
## (InsurancePanel). Se cierra con Esc o con ✕.
## Uso desde el HUD:  var w := GlobalEconWindow.new(); root.add_child(w); w.setup(); … w.open()

signal message(text: String, category: String)

var tabs: TabContainer
var cycle_text: RichTextLabel
var stock_panel: StockPanel
var insurance_panel: InsurancePanel
var _built := false


func setup() -> void:
	if _built:
		return
	_built = true
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.BG, 10, 14))
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 60
	panel.offset_right = -60
	panel.offset_top = 64
	panel.offset_bottom = -30
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var head := HBoxContainer.new()
	var t := UIKit.label("Economía mundial", 22, UIKit.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UIKit.button("✕", close, 32))
	v.add_child(head)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tabs)
	cycle_text = UIKit.rich()
	_add_tab("Ciclos y monedas", cycle_text)
	stock_panel = StockPanel.new()
	stock_panel.setup()
	stock_panel.message.connect(func(a, b): message.emit(a, b))
	_add_tab("Bolsa de valores", stock_panel)
	insurance_panel = InsurancePanel.new()
	insurance_panel.setup()
	insurance_panel.message.connect(func(a, b): message.emit(a, b))
	_add_tab("Seguros", insurance_panel)
	tabs.tab_changed.connect(func(_i): refresh())


func _add_tab(name: String, content: Control) -> void:
	var sc := ScrollContainer.new()
	sc.name = name
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(content)
	tabs.add_child(sc)


func open(tab := -1) -> void:
	setup()
	visible = true
	if tab >= 0 and tab < tabs.get_tab_count():
		tabs.current_tab = tab
	refresh()


func close() -> void:
	visible = false


func refresh() -> void:
	if not visible:
		return
	match tabs.current_tab:
		0:
			cycle_text.text = cycles_text(GameState)
		1:
			stock_panel.refresh()
		2:
			insurance_panel.refresh()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


## Texto de la pestaña de ciclos y monedas (estático: también sirve sin interfaz).
static func cycles_text(gs) -> String:
	if not GlobalEconSim.ready(gs):
		return ""
	var home := GlobalEconSim.home_id(gs)
	var st := GlobalEconSim.home(gs)
	var ind: Dictionary = st.get("ind", {})
	var s := "[b]%s[/b] — moneda: %s (%s) · fase: [b]%s[/b]%s\n" % [GlobalEconSim.country_label(home), GlobalEconSim.currency_name(home), GlobalEconSim.currency_symbol(home),
		GlobalEconSim.phase_label(str(st["phase"])), " (%s)" % GlobalEconSim.kind_label(str(st.get("kind", ""))) if str(st.get("kind", "")) != "" else ""]
	s += "Indicadores adelantados: confianza %d/100 · crédito %+.1f %%/año · vivienda %+.1f %%/año · bolsa %d · desempleo %.1f %%\n" % [
		int(float(ind.get("confianza", 55.0))), float(ind.get("credito", 0.0)), float(ind.get("vivienda", 0.0)), int(float(ind.get("bolsa", 100.0))), float(ind.get("desempleo", 0.0))]
	s += "Riesgo de recesión o crisis según los indicadores: [b]%d/100[/b]\n" % int(GlobalEconSim.risk(gs, home))
	var sig := GlobalEconSim.signals(gs, home)
	for x in sig:
		s += "[color=#e9b949]• Señal: %s[/color]\n" % str(x)
	if sig.is_empty():
		s += "[color=#aaa]Sin señales de alarma.[/color]\n"
	s += "Efectos hoy: consumo ×%.2f · tasa de crédito %+.1f pts · cupo de crédito ×%.2f · propiedades ×%.2f · P/G de la bolsa %.1f\n" % [
		GlobalEconSim.demand_mult(gs), GlobalEconSim.credit_rate_add(gs) * 100.0, GlobalEconSim.credit_limit_mult(gs), GlobalEconSim.property_mult(gs), GlobalEconSim.eff(gs, "pe", 10.0)]
	s += "Tu moneda: desvío real ×%.3f → importar ×%.3f y exportar ×%.3f (comercio con pueblos de tu país). Inflación anual %.1f %%.\n\n" % [
		GlobalEconSim.real_index(gs), GlobalEconSim.import_fx_mult(gs), GlobalEconSim.import_fx_mult(gs), float(st.get("infl", 0.0)) * 100.0]
	s += "[b]Países[/b] (tipo de cambio = unidades por 1 %s)\n" % GlobalEconSim.currency_symbol(home)
	for id in GlobalEconSim.country_ids():
		var c := GlobalEconSim.country(gs, str(id))
		if c.is_empty():
			continue
		var ph := str(c["phase"])
		var col: Array = GlobalEconSim.phase_def(ph).get("color", [0.8, 0.8, 0.8])
		s += "• %s%s — %s: [color=#%s]%s[/color] · 1 %s = %.3f %s (%+.1f %% en 12 meses) · inflación %.1f %%\n" % [
			GlobalEconSim.country_label(str(id)), " (tu país)" if str(id) == home else "", GlobalEconSim.currency_name(str(id)),
			Color(float(col[0]), float(col[1]), float(col[2])).to_html(false), GlobalEconSim.phase_label(ph),
			GlobalEconSim.currency_symbol(home), GlobalEconSim.fx(gs, home, str(id)), GlobalEconSim.currency_symbol(str(id)),
			GlobalEconSim.rate_change(gs, str(id)) * 100.0, float(c.get("infl", 0.0)) * 100.0]
	return s
