class_name MyCompaniesWindow
extends Control
## "Mis empresas" (Empresas → Mis empresas, atajo C; docs/MIS_EMPRESAS.md). Ventana a pantalla completa:
##   - arriba, el resumen del grupo: patrimonio, utilidad total (consolidado), mes en curso, empresas activas y la
##     empresa más y menos rentable;
##   - a la izquierda, la lista de todas tus empresas con foto 3D (BuildingThumb), nivel, estado, utilidad del mes,
##     margen y ROI; se ordena (utilidad, margen, ROI, ingresos, nivel, nombre) y se filtra (estado, tipo, texto);
##   - a la derecha, la ficha de la empresa elegida: visor 3D, gráfica de ingresos/costos/utilidad, precios de venta y
##     de compra, qué compra y a quién, qué vende y por qué canal, personal, vehículos, módulos y costo por unidad
##     (CostsTab/CostSim), con botones «Ver en el mapa» y «Abrir panel».
## Solo lee (CompanyReportSim); no mueve dinero.

signal message(text: String, category: String)
signal open_building(id: int)
signal focus_building(id: int)

const THUMB := Vector2i(132, 88)

var hud: Node
var summary_box: HFlowContainer
var list_box: VBoxContainer
var detail_box: VBoxContainer
var count_label: Label
var search: LineEdit
var filter_opt: OptionButton
var group_opt: OptionButton
var sort_opt: OptionButton
var dir_btn: Button
var selected := -1
var sort_key := "profit"
var sort_desc := true
var filter := "todas"
var group := ""
var _rows: Array = []
var _cards := {}          # id -> PanelContainer
var _built := false
var live_thumb: BuildingThumb
var chart: LineChart


func setup(p_hud: Node = null) -> void:
	hud = p_hud
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
	panel.add_theme_stylebox_override("panel", UIKit.float_style(UIKit.BG, 14, 14))
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 60
	panel.offset_right = -60
	panel.offset_top = 56
	panel.offset_bottom = -20
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	UIKit.header(v, "companies", "Mis empresas", close, [UIKit.icon_button("refresh", refresh, "Actualizar")])
	summary_box = UIKit.flow(8, 8)
	v.add_child(summary_box)
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 12)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(split)
	# Lista
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.custom_minimum_size.x = 470
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.9
	split.add_child(left)
	var tools := HFlowContainer.new()
	tools.add_theme_constant_override("h_separation", 6)
	tools.add_theme_constant_override("v_separation", 6)
	left.add_child(tools)
	search = LineEdit.new()
	search.placeholder_text = "Buscar empresa…"
	search.custom_minimum_size.x = 150
	search.clear_button_enabled = true
	search.text_changed.connect(func(_t): _rebuild_list())
	tools.add_child(search)
	filter_opt = _option(CompanyReportSim.FILTERS, CompanyReportSim.FILTER_LABELS, func(id): filter = id; _rebuild_list())
	filter_opt.tooltip_text = "Filtrar por estado"
	tools.add_child(filter_opt)
	group_opt = _option([""] + CompanyReportSim.GROUPS, CompanyReportSim.GROUP_LABELS.merged({"": "Todos los tipos"}), func(id): group = id; _rebuild_list())
	group_opt.tooltip_text = "Filtrar por tipo de empresa"
	tools.add_child(group_opt)
	sort_opt = _option(CompanyReportSim.SORTS, CompanyReportSim.SORT_LABELS, func(id): sort_key = id; sort_desc = id != "name"; _sync_dir(); _rebuild_list())
	sort_opt.tooltip_text = "Ordenar por"
	tools.add_child(sort_opt)
	dir_btn = UIKit.icon_button("updown", func(): sort_desc = not sort_desc; _sync_dir(); _rebuild_list(), "Invertir el orden")
	tools.add_child(dir_btn)
	_sync_dir()
	count_label = UIKit.label("", UIKit.FS_TINY, UIKit.TEXT_FAINT)
	left.add_child(count_label)
	var ls := ScrollContainer.new()
	ls.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ls.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(ls)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 6)
	ls.add_child(list_box)
	# Ficha
	var rs := ScrollContainer.new()
	rs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(rs)
	detail_box = VBoxContainer.new()
	detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_box.add_theme_constant_override("separation", 8)
	rs.add_child(detail_box)


func _option(ids: Array, labels: Dictionary, cb: Callable) -> OptionButton:
	var o := OptionButton.new()
	for id in ids:
		o.add_item(str(labels.get(id, id)))
		o.set_item_metadata(o.item_count - 1, id)
	o.item_selected.connect(func(i): cb.call(str(o.get_item_metadata(i))))
	return o


func _sync_dir() -> void:
	if dir_btn != null:
		dir_btn.text = " ↓" if sort_desc else " ↑"
		dir_btn.tooltip_text = "Orden %s (clic para invertir)" % ("descendente" if sort_desc else "ascendente")


func open(id := -1) -> void:
	setup(hud)
	if id >= 0:
		selected = id
	var was := visible
	visible = true
	if not was:
		UIKit.animate_in(self, Vector2.ZERO, 0.16)
	refresh()


func close() -> void:
	visible = false
	live_thumb = null


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


## Reconstruye todo (resumen, lista y ficha). Se llama al abrir, con ↻ y tras cambiar de orden o filtro.
func refresh() -> void:
	if not visible or list_box == null:
		return
	_rows = CompanyReportSim.rows(GameState)
	_build_summary()
	_rebuild_list()


# --- Resumen del grupo --------------------------------------------------------------------------------

func _build_summary() -> void:
	UIKit.clear(summary_box)
	var gs := GameState
	var s := CompanyReportSim.summary(gs, _rows)
	var hist: Array = gs.history.slice(maxi(0, gs.history.size() - 24))
	var nw_spark: Array = hist.map(func(e): return float(e.get("net_worth", 0.0)))
	var res_spark: Array = hist.map(func(e): return float(e.get("income", 0.0)) - float(e.get("expenses", 0.0)))
	var specs := [
		["treasury", "Patrimonio neto", Fmt.money_compact(float(s["net_worth"])), nw_spark, UIKit.GOOD if float(s["net_worth"]) >= 0.0 else UIKit.BAD,
			"Dinero %s + propiedades %s − deudas %s" % [Fmt.money(float(s["money"])), Fmt.money(float(s["assets"])), Fmt.money(float(s["debt"]))]],
		["trend_up" if float(s["result"]) >= 0.0 else "trend_down", "Utilidad del grupo (mes ant.)", Fmt.money_compact(float(s["result"])), res_spark, UIKit.sign_color(float(s["result"])),
			"Consolidado contable de todas tus empresas: ingresos %s − costos %s (sin fletes internos %s ni producción entregada al almacén, para no contar dos veces)" % [
				Fmt.money(float(s["income"])), Fmt.money(float(s["expenses"])), Fmt.money(float(s["internal"]))]],
		["calendar", "Mes en curso", Fmt.money_compact(float(s["result_month"])), [], UIKit.sign_color(float(s["result_month"])), "Resultado contable acumulado este mes"],
		["companies", "Empresas", "%d activas / %d" % [int(s["active"]), int(s["count"])], [], UIKit.ACCENT_2,
			"Negocios que cuentan para la oficina: %d de %d" % [BusinessSim.business_count(gs), BusinessSim.max_businesses(gs)]],
	]
	for sp in specs:
		var k := UIKit.kpi_card(sp[0], sp[1], sp[2], "", sp[3], sp[4], sp[5], 190.0)
		summary_box.add_child(k)
	summary_box.add_child(_rank_card("star", "Más rentable", s["best"], UIKit.GOOD))
	summary_box.add_child(_rank_card("alert", "Menos rentable", s["worst"], UIKit.BAD))


func _rank_card(icon_name: String, title: String, r: Dictionary, col: Color) -> Control:
	var txt := "—" if r.is_empty() else str(r["name"])
	var tip := "Sin datos del mes anterior" if r.is_empty() else "%s · utilidad %s · %s. Clic para ver la ficha." % [str(r["name"]), Fmt.money(float(r["profit"])), CompanyReportSim.rank_text(r)]
	var k := UIKit.kpi_card(icon_name, title, txt, "" if r.is_empty() else CompanyReportSim.rank_text(r), [], col, tip, 210.0)
	k.name = "Best" if title == "Más rentable" else "Worst"
	if not r.is_empty():
		var id := int(r["id"])
		k.mouse_filter = Control.MOUSE_FILTER_STOP
		k.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		k.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: select(id))
	return k


# --- Lista --------------------------------------------------------------------------------------------

func visible_rows() -> Array:
	var f := CompanyReportSim.filter_rows(_rows, filter, group, search.text if search else "")
	return CompanyReportSim.sort_rows(f, sort_key, sort_desc)


func _rebuild_list() -> void:
	if list_box == null:
		return
	UIKit.clear(list_box)
	_cards.clear()
	var vr := visible_rows()
	count_label.text = "%d de %d empresas · utilidad de gestión del mes anterior (incluye la producción entregada al almacén a precio de mercado)" % [vr.size(), _rows.size()]
	for r in vr:
		var c := _card(r)
		list_box.add_child(c)
		_cards[int(r["id"])] = c
	if _rows.is_empty():
		list_box.add_child(UIKit.label("Aún no tienes empresas. Usa «Construir» (B).", UIKit.FS_BODY, UIKit.TEXT_DIM))
	elif vr.is_empty():
		list_box.add_child(UIKit.label("Ninguna empresa cumple el filtro.", UIKit.FS_BODY, UIKit.TEXT_DIM))
	var ids := vr.map(func(x): return int(x["id"]))
	if not ids.has(selected):
		selected = int(ids[0]) if not ids.is_empty() else -1
	_highlight()
	_build_detail()


static func cls_color(cls: String) -> Color:
	match cls:
		"rentable":
			return UIKit.GOOD
		"perdidas", "cerrada":
			return UIKit.BAD
		"equilibrio", "obra":
			return UIKit.WARN
	return UIKit.NEUTRAL


static func cls_label(cls: String) -> String:
	return {"rentable": "rentable", "perdidas": "con pérdidas", "cerrada": "cerrada", "equilibrio": "equilibrio", "obra": "en obra", "sin datos": "sin datos"}.get(cls, cls)


func _card(r: Dictionary) -> PanelContainer:
	var gs := GameState
	var b: Dictionary = gs.get_building(int(r["id"]))
	var col := cls_color(str(r["cls"]))
	var c := UIKit.card(col, 6)
	var p: PanelContainer = c["panel"]
	p.name = "Card%d" % int(r["id"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	(c["box"] as VBoxContainer).add_child(row)
	# Foto 3D
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UIKit.card_style(Color(0, 0, 0, 0), 0, UIKit.BG_DEEP))
	frame.custom_minimum_size = Vector2(THUMB)
	row.add_child(frame)
	var sw := ColorRect.new()
	sw.color = BuildingThumb.swatch_color(b).darkened(0.35)
	sw.custom_minimum_size = Vector2(THUMB)
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(sw)
	var tr := TextureRect.new()
	tr.name = "Thumb"
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(THUMB)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(tr)
	BuildingThumb.request(self, b, THUMB, tr)
	# Datos
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 5)
	v.add_child(head)
	var nl := UIKit.label(str(r["name"]), UIKit.FS_BODY + 1, UIKit.TEXT)
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nl.clip_text = true
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(nl)
	head.add_child(UIKit.chip("Nv %d" % int(r["level"]) + ("/%d" % int(r["max_level"]) if int(r["max_level"]) > 1 else ""), UIKit.ACCENT, "", UIKit.FS_TINY))
	head.add_child(UIKit.chip(cls_label(str(r["cls"])) if str(r["status"]) == "activo" else str(r["status_label"]), col, "", UIKit.FS_TINY))
	v.add_child(UIKit.label("%s · %s" % [str(r["type_label"]), CompanyReportSim.GROUP_LABELS.get(r["group"], "")], UIKit.FS_TINY, UIKit.TEXT_FAINT))
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 14)
	v.add_child(stats)
	stats.add_child(_stat("Utilidad mes", Fmt.money(float(r["profit"])) if bool(r["has_data"]) else "—", UIKit.sign_color(float(r["profit"]))))
	stats.add_child(_stat("Margen", _pct(float(r["margin"])), UIKit.sign_color(float(r["margin"])) if not is_nan(float(r["margin"])) else UIKit.TEXT_DIM))
	stats.add_child(_stat("ROI anual", _pct(float(r["roi"])), UIKit.sign_color(float(r["roi"])) if not is_nan(float(r["roi"])) else UIKit.TEXT_DIM))
	stats.add_child(_stat("Este mes", Fmt.money(float(r["month_profit"])), UIKit.sign_color(float(r["month_profit"]))))
	if not (r["alerts"] as Array).is_empty():
		var af := UIKit.flow(4, 4)
		v.add_child(af)
		for a in r["alerts"]:
			af.add_child(UIKit.chip(str(a), UIKit.WARN, "alert", UIKit.FS_TINY))
	var id := int(r["id"])
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	p.tooltip_text = "Clic: ver la ficha · doble clic: abrir el panel del edificio"
	p.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			if e.double_click:
				_open_panel(id)
			else:
				select(id))
	return p


func _stat(title: String, value: String, color: Color) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.add_child(UIKit.label(title, 10, UIKit.TEXT_FAINT))
	v.add_child(UIKit.label(value, 13, color))
	return v


static func _pct(x: float) -> String:
	return "—" if is_nan(x) or is_inf(x) else Fmt.pct_1(x * 100.0)


func select(id: int) -> void:
	selected = id
	_highlight()
	_build_detail()


func _highlight() -> void:
	for id in _cards:
		var p: PanelContainer = _cards[id]
		if not is_instance_valid(p):
			continue
		var r := _row_of(int(id))
		var st := UIKit.card_style(cls_color(str(r.get("cls", ""))), 6, UIKit.BG_RAISED if int(id) == selected else UIKit.BG_LIGHT)
		if int(id) == selected:
			st.border_color = UIKit.ACCENT
			st.border_width_top = 1
			st.border_width_bottom = 1
			st.border_width_right = 1
		p.add_theme_stylebox_override("panel", st)


func _row_of(id: int) -> Dictionary:
	for r in _rows:
		if int(r["id"]) == id:
			return r
	return {}


# --- Ficha --------------------------------------------------------------------------------------------

func _go_map(id: int) -> void:
	close()
	focus_building.emit(id)


func _open_panel(id: int) -> void:
	close()
	open_building.emit(id)


func _build_detail() -> void:
	UIKit.clear(detail_box)
	live_thumb = null
	chart = null
	var gs := GameState
	var b: Dictionary = gs.get_building(selected)
	var r := _row_of(selected)
	if b.is_empty() or r.is_empty():
		detail_box.add_child(UIKit.label("Elige una empresa de la lista para ver su ficha.", UIKit.FS_BODY, UIKit.TEXT_DIM))
		return
	var def: Dictionary = gs.building_def(b)
	# Cabecera: visor 3D, nombre, chips y botones.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	detail_box.add_child(top)
	var tf := PanelContainer.new()
	tf.add_theme_stylebox_override("panel", UIKit.card_style(Color(0, 0, 0, 0), 0, UIKit.BG_DEEP))
	top.add_child(tf)
	live_thumb = BuildingThumb.make(b, Vector2i(300, 190), true)
	live_thumb.name = "LiveThumb"
	tf.add_child(live_thumb)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 5)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(info)
	var title := UIKit.label(str(r["name"]), UIKit.FS_TITLE, UIKit.ACCENT)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(title)
	var legal := str(GameData.legal_types.get(str(b.get("legal", "sas")), {}).get("label", "")) if BusinessSim.is_business(b) else ""
	var sub := UIKit.label("%s%s · %s" % [str(r["type_label"]), (" · " + legal) if legal != "" else "", CompanyReportSim.GROUP_LABELS.get(r["group"], "")], UIKit.FS_SMALL, UIKit.TEXT_DIM)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(sub)
	var chips := UIKit.flow(5, 5)
	info.add_child(chips)
	chips.add_child(UIKit.chip("Nivel %d de %d" % [int(r["level"]), maxi(1, int(r["max_level"]))], UIKit.ACCENT, "build", UIKit.FS_TINY))
	chips.add_child(UIKit.chip(str(r["status_label"]), cls_color(str(r["cls"])) if str(r["status"]) == "activo" else UIKit.WARN, "info", UIKit.FS_TINY))
	if str(r["status"]) == "activo":
		chips.add_child(UIKit.chip(cls_label(str(r["cls"])), cls_color(str(r["cls"])), "", UIKit.FS_TINY))
	if TransportDivSim.is_transport_def(def):
		chips.add_child(UIKit.chip(TransportDivSim.company_name(gs, b) if TransportDivSim.org(b) == "empresa" else "División interna", UIKit.INFO, "logistics", UIKit.FS_TINY))
	info.add_child(UIKit.label("Invertido %s · valor en libros %s" % [Fmt.money(float(r["invested"])), Fmt.money(float(r["value"]))], UIKit.FS_SMALL, UIKit.TEXT_DIM))
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 6)
	info.add_child(btns)
	var id := selected
	var go := UIKit.icon_button("map", func(): _go_map(id), "Cerrar esta ventana y llevar la cámara al edificio", "Ver en el mapa", 16)
	go.name = "GoMap"
	btns.add_child(go)
	var op := UIKit.primary(UIKit.icon_button("chevron_right", func(): _open_panel(id), "Abrir el panel del edificio (precios, personal, mejoras…)", "Abrir panel", 16))
	op.name = "OpenPanel"
	btns.add_child(op)
	# Indicadores del mes anterior.
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	detail_box.add_child(g)
	var inc_tip := "Libro: %s" % Fmt.money(float(r["income"]))
	if float(r["transfer"]) > 0.0:
		inc_tip += " + producción entregada al almacén %s (a precio de mercado)" % Fmt.money(float(r["transfer"]))
	for sp in [["money", "Ingresos", Fmt.money(float(r["revenue"])), UIKit.ACCENT, inc_tip],
			["finance", "Costos", Fmt.money(float(r["costs"])), UIKit.BAD, "Sueldos, insumos, mantenimiento, fletes, impuestos… (sin inversión)"],
			["trend_up" if float(r["profit"]) >= 0.0 else "trend_down", "Utilidad", Fmt.money(float(r["profit"])), UIKit.sign_color(float(r["profit"])), "Ingresos − costos del mes anterior"],
			["stats", "Margen", _pct(float(r["margin"])), UIKit.sign_color(float(r["margin"])) if not is_nan(float(r["margin"])) else UIKit.NEUTRAL, "Utilidad ÷ ingresos"],
			["trophy", "ROI anual", _pct(float(r["roi"])), UIKit.sign_color(float(r["roi"])) if not is_nan(float(r["roi"])) else UIKit.NEUTRAL,
				"Utilidad de 12 meses (%s) ÷ lo invertido (%s)" % [Fmt.money(float(r["annual"])), Fmt.money(float(r["invested"]))]],
			["calendar", "Este mes", Fmt.money(float(r["month_profit"])), UIKit.sign_color(float(r["month_profit"])), "Resultado acumulado del mes en curso"]]:
		var k := UIKit.kpi_card(sp[0], sp[1], sp[2], "", [], sp[3], sp[4], 0.0)
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(k)
	# Gráfica.
	var h := CompanyReportSim.history(gs, b)
	chart = LineChart.new()
	chart.name = "PnlChart"
	chart.custom_minimum_size = Vector2(360, 190)
	chart.set_data("Ingresos, costos y utilidad (mensual)", [
		{"label": "Ingresos", "color": UIKit.GOOD, "values": h["income"]},
		{"label": "Costos", "color": UIKit.BAD, "values": h["costs"]},
		{"label": "Utilidad", "color": UIKit.ACCENT, "values": h["profit"]}], true, (h["days"] as Array).map(func(d): return Fmt.short_date(int(d))))
	detail_box.add_child(chart)
	if (h["days"] as Array).size() < 2:
		detail_box.add_child(_note("La gráfica se completa cada cierre de mes (hasta %d meses)." % CompanyReportSim.HIST_MAX))
	_prices_section(b)
	_buys_section(b)
	_sells_section(b)
	_staff_section(b)
	if CostsTab.applies(gs, b):
		var cs := UIKit.section(detail_box, "Costo por unidad", "finance", true, "emp_cost")
		cs.add_child(CostsTab.build(gs, b))


func _note(t: String) -> Label:
	var l := UIKit.label(t, UIKit.FS_SMALL, UIKit.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 300
	return l


func _grid(parent: Control, headers: Array, widths: Array) -> GridContainer:
	var g := GridContainer.new()
	g.columns = headers.size()
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 4)
	parent.add_child(g)
	for i in range(headers.size()):
		var l := UIKit.label(str(headers[i]), UIKit.FS_TINY, UIKit.TEXT_FAINT)
		l.custom_minimum_size.x = float(widths[i])
		g.add_child(l)
	return g


func _cell(g: GridContainer, text: String, width: float, color := UIKit.TEXT, wrap := false) -> void:
	var l := UIKit.label(text, UIKit.FS_SMALL, color)
	l.custom_minimum_size.x = width
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_child(l)


func _prices_section(b: Dictionary) -> void:
	var gs := GameState
	var p := CompanyReportSim.prices(gs, b)
	var buys := CompanyReportSim.purchases(gs, b).filter(func(x): return str(x["kind"]) == "insumo")
	if str(p["product"]) == "" and buys.is_empty():
		return
	var s := UIKit.section(detail_box, "Precios actuales", "inflation", true, "emp_prices")
	var f := UIKit.flow(6, 6)
	s.add_child(f)
	if str(p["product"]) != "":
		var diff := float(p["sell"]) / maxf(0.0001, float(p["market"])) - 1.0
		f.add_child(UIKit.chip("Venta de %s: %s/u%s" % [GameData.good_label(str(p["product"])).to_lower(), Fmt.money2(float(p["sell"])), " (automático)" if bool(p["auto"]) else ""], UIKit.GOOD, "money", UIKit.FS_SMALL))
		f.add_child(UIKit.chip("Mercado %s/u (%s)" % [Fmt.money2(float(p["market"])), ("%+.0f %%" % (diff * 100.0)).replace(".", ",")], UIKit.TEXT_DIM, "stats", UIKit.FS_SMALL))
	for x in buys:
		f.add_child(UIKit.chip("Compra de %s: %s/u (mercado %s%s)" % [str(x["label"]).to_lower(), Fmt.money2(float(x["unit_price"])), Fmt.money2(float(x["market"])),
			(", importado %s" % Fmt.money2(float(x["import"]))) if float(x["import"]) > 0.0 else ""], UIKit.WARN, "trade", UIKit.FS_SMALL))


func _buys_section(b: Dictionary) -> void:
	var rows := CompanyReportSim.purchases(GameState, b)
	var s := UIKit.section(detail_box, "Qué compra y a quién", "trade", true, "emp_buys")
	if rows.is_empty():
		s.add_child(_note("No compra insumos: solo paga sueldos, mantenimiento e impuestos."))
		return
	var g := _grid(s, ["Concepto", "Cant./mes", "Precio", "Total/mes", "Proveedor"], [130, 70, 70, 80, 200])
	for x in rows:
		_cell(g, str(x["label"]), 130)
		_cell(g, Fmt.thousands(float(x["qty"])) if float(x["qty"]) > 0.0 else "—", 70, UIKit.TEXT_DIM)
		_cell(g, Fmt.money2(float(x["unit_price"])) if float(x["unit_price"]) > 0.0 else "—", 70, UIKit.TEXT_DIM)
		_cell(g, Fmt.money(float(x["total"])), 80, UIKit.BAD)
		_cell(g, "\n".join(x["suppliers"]), 200, UIKit.TEXT_DIM, true)


func _sells_section(b: Dictionary) -> void:
	var rows := CompanyReportSim.sales(GameState, b)
	var s := UIKit.section(detail_box, "Qué vende y por qué canal", "money", true, "emp_sells")
	if rows.is_empty():
		s.add_child(_note("No vende nada todavía."))
		return
	var g := _grid(s, ["Qué", "Canal", "A quién / detalle", "Mes ant."], [110, 150, 200, 80])
	for x in rows:
		_cell(g, str(x["label"]), 110)
		_cell(g, str(x["channel"]), 150, UIKit.ACCENT_2, true)
		_cell(g, str(x["detail"]) if str(x["detail"]) != "" else "—", 200, UIKit.TEXT_DIM, true)
		_cell(g, Fmt.money(float(x["amount"])) if float(x["amount"]) >= 0.0 else "—", 80, UIKit.GOOD)


func _staff_section(b: Dictionary) -> void:
	var gs := GameState
	var st := CompanyReportSim.staff(gs, b)
	var vs := CompanyReportSim.vehicles(gs, b)
	var ms := CompanyReportSim.modules(gs, b)
	var s := UIKit.section(detail_box, "Empleados, vehículos y módulos", "population", true, "emp_staff")
	if int(st["jobs"]) > 0:
		s.add_child(UIKit.meter_row("population", "Empleados", float(st["employees"]) / maxf(1.0, float(st["jobs"])), "%d/%d" % [int(st["employees"]), int(st["jobs"])]))
		s.add_child(UIKit.label("Nómina del mes anterior %s · sueldo promedio %s/día" % [Fmt.money(float(st["payroll"])), Fmt.money2(float(st["avg_wage"]))], UIKit.FS_SMALL, UIKit.TEXT_DIM))
		var people: Array = st["people"]
		if not people.is_empty():
			var pf := UIKit.flow(4, 4)
			s.add_child(pf)
			for i in range(mini(8, people.size())):
				var pp: Dictionary = people[i]
				pf.add_child(UIKit.chip("%s · %s/día · ×%s" % [str(pp["name"]), Fmt.money2(float(pp["wage"])), String.num(float(pp["prod"]), 2).replace(".", ",")], UIKit.TEXT_DIM, "character", UIKit.FS_TINY))
			if people.size() > 8:
				pf.add_child(UIKit.chip("+%d más" % (people.size() - 8), UIKit.TEXT_FAINT, "", UIKit.FS_TINY))
	else:
		s.add_child(_note("Sin puestos de trabajo."))
	if vs.is_empty():
		s.add_child(_note("Vehículos: ninguno con base aquí."))
	else:
		var vf := UIKit.flow(4, 4)
		s.add_child(vf)
		vf.add_child(UIKit.label("Vehículos (%d):" % vs.size(), UIKit.FS_SMALL, UIKit.TEXT_DIM))
		for v in vs:
			vf.add_child(UIKit.chip(str(v["label"]), UIKit.INFO, "logistics", UIKit.FS_TINY))
	for m in ms:
		s.add_child(UIKit.meter_row("build", "%s: %s" % [str(m["label"]), str(m["name"]) if str(m["name"]) != "" else "—"], float(m["level"]) / maxf(1.0, float(m["max"])),
			"Nv %d/%d" % [int(m["level"]), int(m["max"])], false, UIKit.ACCENT_2))
