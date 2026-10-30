class_name DistributionPanel
extends VBoxContainer
## Panel "Ventas y distribución" (Empresas → Ventas y distribución). Pestañas:
##   Productos     por producto: unidades, precio medio, ingreso y margen por canal, stock por almacén y
##                 configuración (prioridad de canales, canales activos y precio mínimo mayorista)
##   Sucursales    comercios propios en otros pueblos: abrir, mejorar, margen y resultados
##   Distribuidora flota, bodega, margen y ventas de tus distribuidoras
##   Clientes      tiendas NPC (lo que piden), pueblos (si llega la carga) y vehículos disponibles
## Ver docs/DISTRIBUCION.md.

signal closed
signal message(text: String, category: String)

const TABS := [["productos", "Productos", "catalog"], ["sucursales", "Sucursales", "town"], ["distribuidora", "Distribuidora", "logistics"], ["clientes", "Clientes", "trade"]]

var hud
var body: VBoxContainer
var tab_bar: HBoxContainer
var tab := "productos"
var sel_good := ""
var period := "last_month"


func setup(p_hud) -> void:
	hud = p_hud
	add_theme_constant_override("separation", 8)
	UIKit.header(self, "trade", "Ventas y distribución", func(): closed.emit(), [UIKit.icon_button("refresh", refresh, "Actualizar", "", 16)])
	tab_bar = HBoxContainer.new()
	add_child(tab_bar)
	var sb := UIKit.scroll_box(Vector2(0, 200))
	sb["scroll"].size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(sb["scroll"])
	body = sb["box"]


func set_tab(id: String) -> void:
	tab = id
	refresh()


func _result(err: String, ok_text: String) -> void:
	if err == "":
		if ok_text != "":
			message.emit(ok_text, "negocio")
	else:
		message.emit(err, "jugador")
	refresh()


func _text(text: String, size := 13, color := UIKit.TEXT) -> Label:
	var l := UIKit.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 360
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _note(text: String, parent: Node = null) -> void:
	(parent if parent != null else body).add_child(_text(text, 12, UIKit.TEXT_DIM))


func refresh() -> void:
	if body == null:
		return
	UIKit.clear(tab_bar)
	for tdef in TABS:
		var id := str(tdef[0])
		var b := UIKit.button(str(tdef[1]), func(): set_tab(id))
		b.icon = UIIcons.tex(str(tdef[2]), 16)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 13)
		b.tooltip_text = str(tdef[1])
		b.toggle_mode = true
		b.button_pressed = id == tab
		tab_bar.add_child(b)
	UIKit.clear(body)
	var gs = GameState
	if gs.market.is_empty():
		FreeMarketSim.init_state(gs)
	match tab:
		"sucursales":
			_branches(gs)
		"distribuidora":
			_distributors(gs)
		"clientes":
			_clients(gs)
		_:
			_products(gs)


# --- Productos ------------------------------------------------------------------------------------

func _period_bar() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for p in [["last_month", "Mes pasado"], ["month", "Este mes"], ["totals", "Total"]]:
		var pid := str(p[0])
		var b := UIKit.button(str(p[1]), func():
			period = pid
			refresh())
		b.toggle_mode = true
		b.button_pressed = period == pid
		b.add_theme_font_size_override("font_size", 12)
		row.add_child(b)
	body.add_child(row)


func _products(gs) -> void:
	_period_bar()
	var tot := DistributionSim.channel_totals(gs, period)
	var flow := UIKit.flow(6, 6)
	body.add_child(flow)
	for ch in DistributionSim.CHANNELS:
		var r: Dictionary = tot.get(ch, {})
		var c := UIKit.chip("%s %s" % [DistributionSim.channel_label(ch, true), Fmt.money(float(r.get("revenue", 0.0)))],
			UIKit.GOOD if float(r.get("revenue", 0.0)) > 0.0 else UIKit.NEUTRAL, str(DistributionSim.cfg().get("channels", {}).get(ch, {}).get("icon", "trade")))
		c.tooltip_text = "%s: %s unidades · fletes %s" % [DistributionSim.channel_label(ch), Fmt.thousands(float(r.get("qty", 0.0))), Fmt.money(float(r.get("freight", 0.0)))]
		flow.add_child(c)
	var goods: Array = DistributionSim.products(gs)
	if goods.is_empty():
		_note("Todavía no fabricas ni tienes productos en tus almacenes. Cuando tus fábricas produzcan, aquí verás por dónde se vende cada uno.")
		return
	if sel_good == "" or not goods.has(sel_good):
		sel_good = str(goods[0])
	var rows := []
	for g in goods:
		var rep := DistributionSim.product_report(gs, str(g), period)
		var row := {"good": g, "name": str(rep["label"]), "stock": float(rep["stock"]), "revenue": float(rep["revenue"])}
		for ch in DistributionSim.CHANNELS:
			row[ch] = float(rep["channels"][ch]["qty"])
		var uc := float(rep["unit_cost"])
		row["margin"] = (float(rep["revenue"]) - uc * float(rep["qty"])) / float(rep["revenue"]) if uc > 0.0 and float(rep["revenue"]) > 0.0 else "—"
		if g == sel_good:
			row["_color"] = UIKit.ACCENT
		rows.append(row)
	var dt := DataTable.new()
	var cols := [{"title": "Producto", "key": "name", "w": 1.5}, {"title": "Stock", "key": "stock", "w": 0.7, "fmt": "int"}]
	for ch in DistributionSim.CHANNELS:
		cols.append({"title": DistributionSim.channel_label(ch, true), "key": ch, "w": 0.8, "fmt": "int"})
	cols.append({"title": "Ingreso", "key": "revenue", "w": 0.9, "fmt": "money"})
	cols.append({"title": "Margen", "key": "margin", "w": 0.7, "fmt": "pct"})
	dt.set_data(cols, rows, 8)
	dt.row_clicked.connect(func(r: Dictionary):
		sel_good = str(r.get("good", ""))
		refresh())
	body.add_child(dt)
	_note("Unidades vendidas por canal. Clic en un producto para ver precios, márgenes, stock por almacén y su configuración.")
	_product_detail(gs, sel_good)


func _product_detail(gs, good: String) -> void:
	var rep := DistributionSim.product_report(gs, good, period)
	var sec := UIKit.section(body, "%s" % str(rep["label"]), "catalog", true, "dist_detail")
	var uc := float(rep["unit_cost"])
	sec.add_child(_text("Mercado %s · mayorista %s · mínimo mayorista %s%s · costo de producción %s" % [Fmt.money2(float(rep["market"])),
		Fmt.money2(float(rep["wholesale"])), Fmt.money2(float(rep["min_wholesale"])),
		" (automático)" if float(rep["cfg"]["min_wholesale"]) <= 0.0 else "", Fmt.money2(uc) if uc > 0.0 else "sin costeo aún"], 12, UIKit.TEXT_DIM))
	var rows := []
	for ch in DistributionSim.CHANNELS:
		var c: Dictionary = rep["channels"][ch]
		var m = c["margin"]
		rows.append({"canal": DistributionSim.channel_label(ch, true), "qty": float(c["qty"]), "price": float(c["price"]) if float(c["qty"]) > 0.0 else "—",
			"revenue": float(c["revenue"]), "freight": float(c["freight"]), "margin": "—" if is_nan(float(m)) else float(m)})
	var dt := DataTable.new()
	dt.set_data([{"title": "Canal", "key": "canal", "w": 1.2}, {"title": "Unidades", "key": "qty", "w": 0.8, "fmt": "int"},
		{"title": "Precio medio", "key": "price", "w": 0.9, "fmt": "money2"}, {"title": "Ingreso", "key": "revenue", "w": 0.9, "fmt": "money"},
		{"title": "Fletes", "key": "freight", "w": 0.8, "fmt": "money"}, {"title": "Margen", "key": "margin", "w": 0.7, "fmt": "pct"}], rows, 6)
	sec.add_child(dt)
	# Stock por almacén.
	var srows: Array = rep["rows"]
	var st := "Stock: " + (", ".join(srows.map(func(r): return "%s %s" % [str(r["name"]), Fmt.thousands(float(r["qty"]))])) if not srows.is_empty() else "sin existencias")
	sec.add_child(_text(st, 12, UIKit.TEXT))
	sec.add_child(_text("Reserva para tus tiendas: %s unidades · disponible para mayorista: %s" % [Fmt.thousands(DistributionSim.shop_reserve(gs, good)),
		Fmt.thousands(DistributionSim.sellable(gs, good, "mayorista"))], 11, UIKit.TEXT_FAINT))
	# Prioridad y canales activos.
	sec.add_child(UIKit.label("Prioridad de canales (el primero toma el stock primero)", 13, UIKit.ACCENT))
	var pc: Dictionary = rep["cfg"]
	var pr: Array = pc["priority"]
	for i in range(pr.size()):
		var ch := str(pr[i])
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		var cb := CheckBox.new()
		cb.button_pressed = bool(pc["enabled"].get(ch, true))
		cb.text = "%d. %s" % [i + 1, DistributionSim.channel_label(ch)]
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cb.add_theme_font_size_override("font_size", 13)
		cb.toggled.connect(func(on: bool):
			DistributionSim.set_enabled(GameState, good, ch, on)
			refresh())
		h.add_child(cb)
		var up := UIKit.icon_button("chevron_up", func():
			DistributionSim.move_channel(GameState, good, ch, -1)
			refresh(), "Subir prioridad", "", 14)
		up.disabled = i == 0
		h.add_child(up)
		var dn := UIKit.icon_button("chevron_down", func():
			DistributionSim.move_channel(GameState, good, ch, 1)
			refresh(), "Bajar prioridad", "", 14)
		dn.disabled = i == pr.size() - 1
		h.add_child(dn)
		sec.add_child(h)
	var mr := HBoxContainer.new()
	mr.add_theme_constant_override("separation", 6)
	mr.add_child(UIKit.label("Precio mínimo mayorista", 13, UIKit.TEXT))
	var cur := float(pc["min_wholesale"])
	var sp := UIKit.spin(0.0, 1000000.0, 0.01, cur if cur > 0.0 else float(rep["min_wholesale"]), func(v): DistributionSim.set_min_wholesale(GameState, good, float(v)), 100)
	mr.add_child(sp)
	mr.add_child(UIKit.button("Automático", func():
		DistributionSim.set_min_wholesale(GameState, good, 0.0)
		refresh()))
	sec.add_child(mr)
	_note("El precio mínimo vale para mayorista, distribuidora y exportación. Automático: tu costo de producción + 5 % (o 45 % del mercado si aún no hay costeo).", sec)


# --- Sucursales -------------------------------------------------------------------------------------

func _branches(gs) -> void:
	var list: Array = DistributionSim.branches(gs)
	var sec := UIKit.section(body, "Tus sucursales (%d)" % list.size(), "town", true, "dist_branches")
	if list.is_empty():
		_note("Abre un comercio propio en un pueblo con ruta: vende al detalle allá (precio del pueblo) y se abastece desde tus almacenes por la ruta, con tus vehículos.", sec)
	for br in list:
		var card := UIKit.card(UIKit.ACCENT_2, 8)
		sec.add_child(card["panel"])
		var cv: VBoxContainer = card["box"]
		var ld := DistributionSim.branch_level_def(int(br.get("level", 1)))
		var res := DistributionSim.branch_result(br)
		var h := HBoxContainer.new()
		h.add_child(UIKit.label("%s · %s" % [str(br["name"]), str(ld.get("label", ""))], 14, UIKit.TEXT))
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(sp)
		h.add_child(UIKit.money_label(res, 14, true))
		cv.add_child(h)
		var led: Dictionary = br.get("ledger", {}).get("last_month", {})
		cv.add_child(_text("Mes pasado: ventas %s · arriendo y personal %s · fletes %s · stock %s / %s · %s" % [Fmt.money(float(led.get("ventas", 0.0))),
			Fmt.money(float(led.get("costos", 0.0))), Fmt.money(float(led.get("fletes", 0.0))), Fmt.thousands(DistributionSim.branch_used(br)),
			Fmt.thousands(DistributionSim.branch_capacity(br)), str(br.get("status", "esperando mercancía"))], 12, UIKit.TEXT_DIM))
		var stock: Dictionary = br.get("stock", {})
		if not stock.is_empty():
			cv.add_child(_text("En venta: " + ", ".join(stock.keys().map(func(g): return "%s %s" % [GameData.good_label(str(g)), Fmt.thousands(float(stock[g]))])), 12, UIKit.TEXT))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(UIKit.label("Margen", 12, UIKit.TEXT_DIM))
		var id := int(br["id"])
		row.add_child(UIKit.spin(-30, 80, 1, roundf(float(br.get("markup", 0.1)) * 100.0), func(v): DistributionSim.set_branch_markup(DistributionSim.branch(GameState, id), float(v) / 100.0), 70))
		var up := UIKit.button("Mejorar (%s)" % Fmt.money(DistributionSim.branch_open_cost(gs, int(br.get("level", 1)) + 1)), func(): _result(DistributionSim.upgrade_branch(GameState, id), "Sucursal mejorada."))
		up.disabled = DistributionSim.upgrade_branch_block(gs, br) != ""
		up.tooltip_text = DistributionSim.upgrade_branch_block(gs, br)
		row.add_child(up)
		row.add_child(UIKit.danger(UIKit.button("Cerrar", func(): _result(DistributionSim.close_branch(GameState, id), ""))))
		cv.add_child(row)
	var sec2 := UIKit.section(body, "Abrir una sucursal", "plus", true, "dist_open")
	sec2.add_child(_text("Costo de apertura %s (lo cobran constructores del pueblo) · arriendo y personal %s/mes." % [Fmt.money(DistributionSim.branch_open_cost(gs)),
		Fmt.money(DistributionSim.branch_monthly_cost(gs, {"level": 1}))], 12, UIKit.TEXT_DIM))
	for t in TradeSim.towns(gs):
		var tid := str(t["id"])
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		var l := UIKit.label("%s (%d hab., %d km)" % [str(t.get("name", "")), int(t.get("population", 0)), int(t.get("distance", 0))], 13, UIKit.TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		var why := DistributionSim.open_branch_block(gs, tid)
		var b := UIKit.button("Abrir", func(): _result(DistributionSim.open_branch(GameState, tid), "Sucursal abierta."))
		b.disabled = why != ""
		b.tooltip_text = why
		h.add_child(b)
		sec2.add_child(h)
		if why != "":
			sec2.add_child(_text(why, 11, UIKit.TEXT_FAINT))


# --- Distribuidora -----------------------------------------------------------------------------------

func _distributors(gs) -> void:
	var list: Array = DistributionSim.distributors(gs, false)
	if list.is_empty():
		_note("No tienes distribuidora. Constrúyela en Construir → Comercio → Distribuidora: compra a tus fábricas y a empresas NPC y revende a las tiendas NPC y a los pueblos con ruta, con su propia flota.")
		return
	var ctx_carriers := DistributionSim.carriers(gs)
	for d in list:
		var ld: Dictionary = gs.level_def(d)
		var card := UIKit.card(UIKit.ACCENT, 8)
		body.add_child(card["panel"])
		var cv: VBoxContainer = card["box"]
		cv.add_child(UIKit.label("%s · %s" % [gs.building_label(d), str(ld.get("label", ""))], 15, UIKit.ACCENT))
		var cap := 0.0
		for c in ctx_carriers:
			if int(c["id"]) == int(d["id"]):
				cap = float(c["cap"])
		var staff := DistributionSim.dist_staff(gs, d)
		cv.add_child(_text("Flota: %s · %d empleados · capacidad %s unidades/semana (usadas %s) · alcance %s" % [str(ld.get("fleet_label", "")), staff,
			Fmt.thousands(cap), Fmt.thousands(DistributionSim.carrier_used(gs, int(d["id"]))),
			"todo el país" if float(ld.get("reach_km", 90)) >= 9000.0 else "%d km" % int(ld.get("reach_km", 90))], 12, UIKit.TEXT_DIM))
		if staff <= 0:
			cv.add_child(_text("Sin empleados no reparte: contrata en el panel del edificio.", 12, UIKit.WARN))
		cv.add_child(_text("Bodega %s / %s · ventas del mes pasado %s · compras %s · resultado %s" % [Fmt.thousands(DistributionSim.dist_used(d)),
			Fmt.thousands(DistributionSim.dist_capacity(gs, d)), Fmt.money(BusinessSim.period_value(d, "last_month", "ventas")),
			Fmt.money(BusinessSim.period_value(d, "last_month", "mercaderia")), Fmt.money(BusinessSim.period_profit(d, "last_month"))], 12, UIKit.TEXT))
		var st := DistributionSim.dist_stock(d)
		if not st.is_empty():
			cv.add_child(_text("En bodega: " + ", ".join(st.keys().map(func(g): return "%s %s" % [GameData.good_label(str(g)), Fmt.thousands(float(st[g]))])), 12, UIKit.TEXT))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(UIKit.label("Margen sobre el costo", 12, UIKit.TEXT_DIM))
		var bid := int(d["id"])
		row.add_child(UIKit.spin(0, 60, 1, roundf(DistributionSim.dist_margin(d) * 100.0), func(v): DistributionSim.set_dist_margin(GameState.get_building(bid), float(v) / 100.0), 70))
		cv.add_child(row)
	_note("Tus productos pasan a la distribuidora como traspaso interno al precio mayorista (la fábrica registra la venta, la distribuidora la compra; el dinero no sale del grupo). A las empresas NPC les compra su excedente y les paga de verdad.")


# --- Clientes y vehículos ------------------------------------------------------------------------------

func _clients(gs) -> void:
	var rep := DistributionSim.clients_report(gs)
	var sec := UIKit.section(body, "Tiendas NPC del pueblo (%d)" % rep["stores"].size(), "companies", true, "dist_stores")
	if rep["stores"].is_empty():
		_note("No hay tiendas NPC. Cuando vendes al por mayor algo que los vecinos buscan y nadie lo revende, un vecino puede abrir una tienda.", sec)
	for s in rep["stores"]:
		var wants: Array = s["wants"]
		var parts := wants.map(func(w): return "%s: pide %s, tiene %s" % [GameData.good_label(str(w["good"])), Fmt.thousands(float(w["need"])), Fmt.thousands(float(w["stock"]))])
		sec.add_child(_text("%s · caja %s · %s" % [str(s["name"]), Fmt.money(float(s["cash"])), "; ".join(parts) if not parts.is_empty() else "no pide nada ahora"], 12, UIKit.TEXT))
	var sec2 := UIKit.section(body, "Pueblos", "town", true, "dist_towns")
	for t in rep["towns"]:
		var ok := str(t["block"]) == ""
		var status := "la carga llega" if ok else str(t["block"])
		sec2.add_child(_text("%s · %d km · caja %s · %s%s · piden: %s" % [str(t["name"]), int(t["distance"]), Fmt.money(float(t["cash"])), status,
			" · sucursal" if bool(t["branch"]) else "", ", ".join((t["demands"] as Array).map(func(g): return TradeSim.good_label(str(g)).to_lower()))], 12, UIKit.GOOD if ok else UIKit.TEXT_DIM))
	var sec3 := UIKit.section(body, "Vehículos para distribuir", "logistics", true, "dist_carriers")
	if rep["carriers"].is_empty():
		_note("Sin vehículos: sin una estación de transporte con personal o una distribuidora, tus productos no salen del pueblo.", sec3)
	for c in rep["carriers"]:
		sec3.add_child(_text("%s (%s) · %s unidades/semana · usadas %s · alcance %s" % [str(c["label"]), "división de transporte" if str(c["kind"]) == "div" else "distribuidora",
			Fmt.thousands(float(c["cap"])), Fmt.thousands(DistributionSim.carrier_used(gs, int(c["id"]))),
			"todo el país" if float(c["reach"]) >= 9000.0 else "%d km" % int(c["reach"])], 12, UIKit.TEXT))
	var notes: Dictionary = DistributionSim.notes(gs)
	if not notes.is_empty():
		var sec4 := UIKit.section(body, "Avisos de este mes", "bell", true, "dist_notes")
		for k in notes:
			sec4.add_child(_text(str(notes[k]), 12, UIKit.WARN))
