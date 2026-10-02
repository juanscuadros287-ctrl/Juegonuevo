class_name LandsWindow
extends Control
## "Mis terrenos" (pantalla completa): cartera de terrenos con valor de mercado, plusvalía, uso e impuesto
## predial; gráfica del valor y del índice del municipio; vender al Estado, poner en venta, arrendar o vender
## todo (terreno + negocios); bandeja de ofertas de empresarios y ciudadanos (Aceptar / Rechazar / Contraofertar).
## Lógica en LandPortfolioSim (docs/TERRENOS_COSTOS.md).

signal message(text: String, category: String)

var body: VBoxContainer
var selected := ""
var _built := false


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
	panel.offset_left = 70
	panel.offset_right = -70
	panel.offset_top = 60
	panel.offset_bottom = -26
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	UIKit.header(v, "map", "Mis terrenos: valor, plusvalía, ventas y ofertas", close, [UIKit.icon_button("refresh", refresh, "Actualizar")])
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	sc.add_child(body)


func open(k := "") -> void:
	setup()
	if k != "":
		selected = k
	var was := visible
	visible = true
	if not was:
		UIKit.animate_in(self, Vector2.ZERO, 0.16)
	refresh()


func close() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _say(text: String, ok_cat := "negocio") -> void:
	message.emit(text, ok_cat)
	refresh()


func refresh() -> void:
	if not visible or body == null:
		return
	var gs := GameState
	UIKit.clear(body)
	var rows := LandPortfolioSim.rows(gs)
	var t := LandPortfolioSim.totals(gs)
	# Indicadores
	var g := UIKit.flow(8, 8)
	body.add_child(g)
	var gain := float(t["gain"])
	g.add_child(UIKit.kpi_card("map", "Terrenos", "%d (%d parcelas)" % [int(t["lots"]), int(t["parcels"])], "", [], UIKit.ACCENT, "Tus parcelas de 80 m agrupadas por territorio de 400 m", 210))
	g.add_child(UIKit.kpi_card("money", "Valor de mercado", Fmt.money(float(t["value"])), "", [], UIKit.ACCENT_2, "Precio de hoy según el mercado de tierras de cada municipio", 210))
	g.add_child(UIKit.kpi_card("finance", "Precio de compra", Fmt.money(float(t["basis"])), "", [], UIKit.TEXT_DIM, "Lo que pagaste (las parcelas iniciales se valoran al empezar)", 210))
	g.add_child(UIKit.kpi_card("trend_up" if gain >= 0.0 else "trend_down", "Plusvalía" if gain >= 0.0 else "Minusvalía", Fmt.money(gain),
		UIKit.trend_bbcode(gain / maxf(1.0, float(t["basis"]))), [], UIKit.sign_color(gain), "Valor de mercado − precio de compra", 210))
	g.add_child(UIKit.kpi_card("government", "Predial / mes", Fmt.money2(float(t["predial"])), "", [], UIKit.WARN,
		"Impuesto predial del mes (va al tesoro del municipio). Pagado el mes pasado: %s" % Fmt.money2(float(LandPortfolioSim.st(gs).get("predial_last", 0.0))), 210))
	# Ofertas
	_offers_section()
	# Tabla
	var sec := UIKit.section(body, "Cartera de terrenos (clic en una fila para ver y vender)", "map", true, "lands_table")
	var tbl_rows := []
	for r in rows:
		var row: Dictionary = r.duplicate()
		row["gain_col"] = UIKit.sign_color(float(r["gain"]))
		row["_color"] = UIKit.ACCENT if str(r["key"]) == selected else UIKit.TEXT
		tbl_rows.append(row)
	var dt := DataTable.new()
	dt.set_data([{"title": "Municipio", "key": "municipio", "w": 1.4}, {"title": "Parc.", "key": "parcels", "w": 0.5, "fmt": "int"},
		{"title": "Compra", "key": "basis", "w": 0.9, "fmt": "money"}, {"title": "Valor hoy", "key": "value", "w": 0.9, "fmt": "money"},
		{"title": "Plusvalía", "key": "gain", "w": 0.9, "fmt": "money", "color_key": "gain_col"}, {"title": "%", "key": "gain_pct", "w": 0.6, "fmt": "trend"},
		{"title": "Uso", "key": "use", "w": 1.0}, {"title": "Predial/mes", "key": "predial", "w": 0.8, "fmt": "money2"},
		{"title": "Estado", "key": "status", "w": 0.7}, {"title": "A nombre de", "key": "owner_label", "w": 1.0}], tbl_rows, 10)
	dt.row_clicked.connect(func(row): selected = str(row["key"]); refresh())
	sec.add_child(dt)
	if rows.is_empty():
		sec.add_child(UIKit.label("No tienes terrenos.", 13, UIKit.TEXT_DIM))
		return
	if selected == "" or not LandPortfolioSim.st(gs)["lots"].has(selected):
		selected = str(rows[0]["key"]) if rows.size() == 1 else ""
		for r in rows:
			if not LandPortfolioSim.is_town(str(r["key"])):
				selected = str(r["key"])
				break
		if selected == "":
			selected = str(rows[0]["key"])
	_detail(selected)
	_sales_section()


func _detail(k: String) -> void:
	var gs := GameState
	var row := {}
	for r in LandPortfolioSim.rows(gs):
		if str(r["key"]) == k:
			row = r
	if row.is_empty():
		return
	var lot: Dictionary = LandPortfolioSim.st(gs)["lots"][k]
	var sec := UIKit.section(body, "Terreno en %s (territorio %s)" % [row["municipio"], k], "realestate", true, "lands_detail")
	var info := UIKit.rich()
	var gain := float(row["gain"])
	info.text = "%d parcelas · uso: %s · compra %s · valor hoy [b]%s[/b] · %s [color=%s]%s (%s)[/color]\nÍndice del municipio %s · predial %s/mes (%s anual del valor)%s" % [
		int(row["parcels"]), row["use"], Fmt.money(float(row["basis"])), Fmt.money(float(row["value"])),
		"plusvalía" if gain >= 0.0 else "minusvalía", "#6c6" if gain >= 0.0 else "#e66", Fmt.money(gain), Fmt.pct_1(float(row["gain_pct"]) * 100.0),
		String.num(float(row["index"]), 2), Fmt.money2(float(row["predial"])), Fmt.pct_1(LandPortfolioSim.predial_rate(gs, int(row["zid"])) * 100.0),
		"\nArrendado a %s por %s/mes." % [lot["lease"]["tenant"], Fmt.money2(float(lot["lease"]["rent"]))] if not (lot.get("lease", {}) as Dictionary).is_empty() else ""]
	sec.add_child(info)
	var hist: Array = lot.get("hist", [])
	if hist.size() >= 2:
		var charts := HBoxContainer.new()
		charts.add_theme_constant_override("separation", 8)
		sec.add_child(charts)
		var lc := LineChart.new()
		lc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lc.custom_minimum_size.y = 170
		lc.set_data("Valor del terreno", [{"label": "Valor", "color": UIKit.ACCENT, "values": hist.map(func(h): return float(h[1]))},
			{"label": "Precio de compra", "color": UIKit.TEXT_DIM, "values": hist.map(func(_h): return float(row["basis"]))}], true, hist.map(func(h): return Fmt.short_date(int(h[0]))))
		charts.add_child(lc)
		var ic := LineChart.new()
		ic.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ic.custom_minimum_size.y = 170
		ic.set_data("Índice del municipio (1 = normal)", [{"label": "Índice × demanda", "color": UIKit.ACCENT_2, "values": hist.map(func(h): return float(h[2]))}], false, hist.map(func(h): return Fmt.short_date(int(h[0]))))
		charts.add_child(ic)
	else:
		sec.add_child(UIKit.label("La gráfica aparece al cerrar el primer mes con este terreno.", 12, UIKit.TEXT_FAINT))
	# Acciones
	var acts := UIKit.flow(6, 6)
	sec.add_child(acts)
	var r_state := LandPortfolioSim.sell_block_reason(gs, k, "estado")
	var b1 := UIKit.button("Vender al Estado (%s)" % Fmt.money(LandPortfolioSim.state_price(gs, k)), func(): _say(_or_ok(LandPortfolioSim.sell_to_state(GameState, k), "Vendido al Estado.")))
	b1.disabled = r_state != ""
	b1.tooltip_text = r_state if r_state != "" else "Precio fijo: %d %% del valor de mercado, pagado por el tesoro" % int(float(LandPortfolioSim.cfg().get("state_buy_ratio", 0.9)) * 100.0)
	acts.add_child(b1)
	var listing: Dictionary = lot.get("listing", {})
	if listing.is_empty():
		var ask := UIKit.spin(1, 1e9, 10, LandPortfolioSim.suggested_ask(gs, k), func(_v): pass, 120)
		ask.tooltip_text = "Precio pedido (sugerido: valor de mercado + 5 %)"
		acts.add_child(ask)
		var r_list := LandPortfolioSim.sell_block_reason(gs, k, "lista")
		var b2 := UIKit.primary(UIKit.button("Poner en venta", func(): _say(_or_ok(LandPortfolioSim.list_for_sale(GameState, k, ask.value), "Terreno en venta."))))
		b2.disabled = r_list != ""
		b2.tooltip_text = r_list
		acts.add_child(b2)
	else:
		acts.add_child(UIKit.chip("En venta por %s desde %s" % [Fmt.money(float(listing["ask"])), Fmt.short_date(int(listing["since"]))], UIKit.WARN, "money", 11))
		acts.add_child(UIKit.button("Retirar de la venta", func():
			LandPortfolioSim.unlist(GameState, k)
			refresh()))
	if (lot.get("lease", {}) as Dictionary).is_empty():
		var r_lease := LandPortfolioSim.sell_block_reason(gs, k, "arriendo")
		var b3 := UIKit.button("Arrendar (%s/mes)" % Fmt.money2(LandPortfolioSim.lease_rent(gs, k)), func(): _say(_or_ok(LandPortfolioSim.lease(GameState, k), "Terreno arrendado.")))
		b3.disabled = r_lease != ""
		b3.tooltip_text = r_lease
		acts.add_child(b3)
	else:
		acts.add_child(UIKit.button("Terminar arriendo", func():
			LandPortfolioSim.end_lease(GameState, k)
			refresh()))
	if not LandPortfolioSim.buildings_on(gs, k).is_empty():
		var r_all := LandPortfolioSim.sell_block_reason(gs, k, "todo")
		var b4 := UIKit.danger(UIKit.button("Vender todo: terreno + negocios (%s)" % Fmt.money(LandPortfolioSim.sell_all_price(gs, k)), func(): _say(_or_ok(LandPortfolioSim.sell_all(GameState, k), "Vendiste todo."))))
		b4.disabled = r_all != ""
		b4.tooltip_text = r_all if r_all != "" else "Un empresario compra el terreno con sus negocios (pasan a ser su empresa)"
		acts.add_child(b4)
		sec.add_child(UIKit.label("Con edificios tuyos el terreno no se vende suelto: solo todo junto.", 12, UIKit.TEXT_FAINT))


func _or_ok(err: String, ok: String) -> String:
	return err if err != "" else ok


func _offers_section() -> void:
	var gs := GameState
	var pend := LandPortfolioSim.pending_offers(gs)
	var sec := UIKit.section(body, "Ofertas por tus terrenos (%d pendientes)" % pend.size(), "bell", true, "lands_offers")
	if pend.is_empty():
		sec.add_child(UIKit.label("Sin ofertas pendientes. Los empresarios y ciudadanos ricos ofertan más en los municipios que se valorizan.", 12, UIKit.TEXT_DIM))
	for o in pend:
		var oid := int(o["id"])
		var c := UIKit.card(UIKit.WARN, 8)
		sec.add_child(c["panel"])
		var v := float(LandPortfolioSim.value_of(gs, str(o["key"])))
		var l := UIKit.rich()
		l.text = "[b]%s[/b] (%s) ofrece [b]%s[/b] por tu terreno en %s · vale %s (%s) · vence %s" % [o["buyer"], o["reason"], Fmt.money(float(o["amount"])),
			MunicipalSim.name_of(gs, LandPortfolioSim.zid_of(gs, str(o["key"]))), Fmt.money(v), Fmt.pct_1((float(o["amount"]) / maxf(1.0, v) - 1.0) * 100.0), Fmt.short_date(int(o["expires"]))]
		c["box"].add_child(l)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		c["box"].add_child(row)
		var why := LandPortfolioSim.sell_block_reason(gs, str(o["key"]), "npc")
		var acc := UIKit.primary(UIKit.button("Aceptar", func(): _say(_or_ok(LandPortfolioSim.accept_offer(GameState, oid), "Oferta aceptada."), "importante")))
		acc.disabled = why != ""
		acc.tooltip_text = why
		row.add_child(acc)
		row.add_child(UIKit.button("Rechazar", func():
			LandPortfolioSim.reject_offer(GameState, oid)
			refresh()))
		var sp := UIKit.spin(1, 1e9, 10, snappedf(float(o["amount"]) * 1.12, 10.0), func(_v): pass, 120)
		row.add_child(sp)
		var cnt := UIKit.button("Contraofertar", func(): _say(LandPortfolioSim.counter_offer(GameState, oid, sp.value)))
		cnt.disabled = why != ""
		row.add_child(cnt)


func _sales_section() -> void:
	var gs := GameState
	var sales: Array = LandPortfolioSim.st(gs).get("sales", [])
	if sales.is_empty():
		return
	var sec := UIKit.section(body, "Terrenos vendidos", "finance", false, "lands_sales")
	for s in sales.slice(maxi(0, sales.size() - 8)):
		var gain := float(s["gain"])
		sec.add_child(UIKit.label("%s · %s a %s por %s (%s %s)" % [Fmt.short_date(int(s["day"])), s["key"], s["buyer"], Fmt.money(float(s["price"])),
			"plusvalía" if gain >= 0.0 else "minusvalía", Fmt.money(absf(gain))], 12, UIKit.sign_color(gain)))
