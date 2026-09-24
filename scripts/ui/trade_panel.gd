class_name TradePanel
extends VBoxContainer
## Panel "Comercio exterior": otros pueblos, rutas comerciales, transporte, compra/venta,
## contratos automáticos, envíos en camino e inmigración.

signal closed
signal message(text: String, category: String)

var hud: Hud
var body: VBoxContainer
var selected_town := ""
var qty := 20.0
var every := 15
var limit := 0.0


func setup(p_hud: Hud) -> void:
	hud = p_hud
	add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	add_child(head)
	var t := UIKit.label("Comercio exterior", 20, UIKit.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UIKit.button("↻", refresh, 32))
	head.add_child(UIKit.button("✕", func(): closed.emit(), 32))
	var sb := UIKit.scroll_box(Vector2(0, 200))
	sb["scroll"].size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(sb["scroll"])
	body = sb["box"]


func _result(err: String, ok_text: String) -> void:
	if err == "":
		message.emit(ok_text, "negocio")
	else:
		message.emit(err, "jugador")
	refresh()


func _section(title: String) -> void:
	body.add_child(HSeparator.new())
	body.add_child(UIKit.label(title, 16, UIKit.ACCENT))


func _rich(text: String) -> RichTextLabel:
	var rl := UIKit.rich()
	rl.text = text
	body.add_child(rl)
	return rl


func _note(text: String, parent: Node = null) -> void:
	var l := UIKit.label(text, 12, UIKit.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 380
	(parent if parent != null else body).add_child(l)


func _goods_list(list: Array) -> String:
	return ", ".join(list.map(func(g): return TradeSim.good_label(str(g))))


func refresh() -> void:
	if body == null:
		return
	UIKit.clear(body)
	var gs := GameState
	if TradeSim.towns(gs).is_empty():
		body.add_child(UIKit.label("No se conocen otros pueblos.", 14, UIKit.TEXT_DIM))
		return
	_summary(gs)
	_section("Pueblos de la región")
	_note("Cada ruta se paga por separado (acuerdo de paso + camino). En el mapa se ve un solo camino que sale del pueblo.")
	for t in TradeSim.towns(gs):
		_town_card(gs, t)
	if selected_town != "" and not TradeSim.connection(gs, selected_town).is_empty():
		_trade_section(gs, selected_town)
	_shipments(gs)
	_contracts(gs)


func _summary(gs) -> void:
	var m: Dictionary = gs.trade.get("last_month", {})
	var cur: Dictionary = gs.trade.get("month", {})
	var tot: Dictionary = gs.trade.get("totals", {})
	var s := "Rutas abiertas: [b]%d[/b] de %d · Almacén: %d/%d\n" % [TradeSim.connected_towns(gs).size(), TradeSim.towns(gs).size(),
			int(WarehouseSim.used(gs)), int(WarehouseSim.capacity(gs))]
	s += "Mes pasado: exportaciones [color=#8f8]%s[/color] · importaciones [color=#f99]%s[/color] · fletes %s · mantenimiento %s\n" % [
			Fmt.money(float(m.get("exports", 0.0))), Fmt.money(float(m.get("imports", 0.0))), Fmt.money(float(m.get("transport", 0.0))), Fmt.money(float(m.get("upkeep", 0.0)))]
	s += "Este mes: exportado %s · importado %s · inmigrantes %d\n" % [Fmt.money(float(cur.get("exports", 0.0))), Fmt.money(float(cur.get("imports", 0.0))), int(cur.get("immigrants", 0.0))]
	s += "Total histórico: exportado %s · invertido en rutas %s · inmigrantes %d\n" % [Fmt.money(float(tot.get("exports", 0.0))), Fmt.money(float(tot.get("investment", 0.0))), int(tot.get("immigrants", 0.0))]
	s += "Mantenimiento mensual estimado de rutas y flota: %s" % Fmt.money(TradeSim.monthly_upkeep_estimate(gs))
	_rich(s)
	_section("Inmigración")
	if not TradeSim.is_connected_any(gs):
		_note("Sin rutas nadie llega al pueblo: la gente solo viene por los caminos. Abre una ruta con otro pueblo.")
	else:
		var a := TradeSim.attractiveness(gs)
		var f := func(v: float) -> String:
			return "[color=#8f8]bueno[/color]" if v > 0.25 else ("[color=#f99]malo[/color]" if v < -0.25 else "regular")
		var t := "Llegan unas [b]%.1f familias al mes[/b] (atractivo %.2f × conexiones %.2f).\n" % [float(a["families_month"]), float(a["score"]), float(a["connections"])]
		t += "Empleo: %s (%d vacantes) · Vivienda: %s (%d plazas libres, %d sin hogar)\n" % [f.call(float(a["jobs"])), int(a["vacancies"]), f.call(float(a["housing"])), int(a["free_housing"]), int(a["homeless"])]
		t += "Felicidad: %s · Salarios: %s" % [f.call(float(a["happiness"])), f.call(float(a["wages"]))]
		_rich(t)
		_note("Mejores caminos y transporte traen más gente. Si no hay vivienda, llegan igual y quedan sin hogar.")


func _town_card(gs, t: Dictionary) -> void:
	var tid := str(t["id"])
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.BG_LIGHT, 6, 8))
	body.add_child(card)
	var v := VBoxContainer.new()
	card.add_child(v)
	var water := " · acceso por agua" if bool(t.get("water", false)) else ""
	v.add_child(UIKit.label("%s — %s" % [t["name"], TradeSim.archetype_label(t)], 15, UIKit.ACCENT))
	var info := UIKit.rich()
	info.text = "%d km · %s habitantes%s\n[color=#9c9]Produce:[/color] %s\n[color=#fc8]Demanda:[/color] %s" % [
			int(t["distance"]), Fmt.thousands(float(t["population"])), water, _goods_list(t.get("produces", [])), _goods_list(t.get("demands", []))]
	v.add_child(info)
	var conn := TradeSim.connection(gs, tid)
	var proj := TradeSim.project(gs, tid)
	if not proj.is_empty():
		var left: int = int(proj["done_day"]) - gs.today()
		v.add_child(UIKit.label("Construyendo el camino: faltan %d días." % maxi(0, left), 13, UIKit.TEXT_DIM))
		return
	if conn.is_empty():
		var q := TradeSim.connection_cost(gs, tid)
		_note("Acuerdo de paso %s + camino de barro %s · %d días de obra" % [Fmt.money(float(q["agreement"])), Fmt.money(float(q["road"])), int(q["days"])], v)
		var b := UIKit.button("Abrir ruta (%s)" % Fmt.money(float(q["total"])), func():
			_result(TradeSim.open_route(GameState, tid), "Ruta con %s en construcción." % t["name"]))
		b.disabled = TradeSim.open_block_reason(gs, tid) != ""
		b.tooltip_text = TradeSim.open_block_reason(gs, tid)
		v.add_child(b)
		return
	# Ruta abierta.
	var work: Dictionary = conn.get("work", {})
	var st := "%s%s · exportado %s · importado %s · llegaron %d personas" % [TradeSim.road_label(int(conn.get("road", 1))),
			" + vía férrea" if bool(conn.get("rail", false)) else "", Fmt.money(float(conn.get("exported", 0.0))),
			Fmt.money(float(conn.get("imported", 0.0))), int(conn.get("immigrants", 0))]
	if work.has("road"):
		st += "\nReforma en curso: %s (faltan %d días)" % [TradeSim.road_label(int(work["road"]["level"])), maxi(0, int(work["road"]["done_day"]) - gs.today())]
	if work.has("rail"):
		st += "\nVía férrea en construcción (faltan %d días)" % maxi(0, int(work["rail"]["done_day"]) - gs.today())
	var stl := UIKit.rich()
	stl.text = st
	v.add_child(stl)
	# Medio de transporte.
	var row := HBoxContainer.new()
	row.add_child(UIKit.label("Transporte:", 13))
	var opt := OptionButton.new()
	var ids := TradeSim.mode_ids()
	var cur_mode := TradeSim.active_mode(gs, tid)
	for i in range(ids.size()):
		var mid := str(ids[i])
		var why := TradeSim.mode_block_reason(gs, tid, mid)
		opt.add_item(TradeSim.mode_def(mid).get("label", mid) + ("" if why == "" else " (no disponible)"), i)
		opt.set_item_disabled(i, why != "")
		opt.set_item_tooltip(i, why if why != "" else str(TradeSim.mode_def(mid).get("description", "")))
		if mid == cur_mode:
			opt.select(i)
	opt.item_selected.connect(func(idx: int):
		_result(TradeSim.set_mode(GameState, tid, str(ids[idx])), "Transporte a %s: %s." % [t["name"], TradeSim.mode_def(str(ids[idx])).get("label", "")]))
	row.add_child(opt)
	v.add_child(row)
	var md := TradeSim.mode_def(cur_mode)
	var tq := TradeSim.transport_quote(gs, tid, TradeSim.mode_capacity(gs, cur_mode), cur_mode)
	_note("%s: %d unidades por viaje · %d días de viaje · %s por viaje lleno · mantenimiento %s/mes" % [md.get("label", ""),
			int(TradeSim.mode_capacity(gs, cur_mode)), int(tq["days"]), Fmt.money(float(tq["cost"])), Fmt.money(float(md.get("monthly_upkeep", 0.0)) * gs.price_mult())], v)
	var btns := HBoxContainer.new()
	v.add_child(btns)
	btns.add_child(UIKit.button("Comerciar" if selected_town != tid else "Ocultar", func():
		selected_town = tid if selected_town != tid else ""
		refresh()))
	var uq := TradeSim.road_upgrade_quote(gs, tid)
	if not uq.is_empty():
		var why := TradeSim.road_upgrade_block_reason(gs, tid)
		var ub := UIKit.button("Mejorar camino (%s)" % Fmt.money(float(uq["cost"])), func():
			_result(TradeSim.upgrade_road(GameState, tid), "Reforma del camino iniciada."))
		ub.disabled = why != ""
		ub.tooltip_text = why if why != "" else "Mejorar a %s: más rápido y atrae más gente (%d días)." % [uq["label"], int(uq["days"])]
		btns.add_child(ub)
	if not bool(conn.get("rail", false)) and gs.has_tech("ferrocarril"):
		var rq := TradeSim.rail_quote(gs, tid)
		var rwhy := TradeSim.rail_block_reason(gs, tid)
		var rb := UIKit.button("Vía férrea (%s)" % Fmt.money(float(rq["cost"])), func():
			_result(TradeSim.build_rail(GameState, tid), "Construcción de la vía férrea iniciada."))
		rb.disabled = rwhy != ""
		rb.tooltip_text = rwhy
		btns.add_child(rb)


func _trade_section(gs, tid: String) -> void:
	var t := TradeSim.town(gs, tid)
	_section("Comercio con %s" % t["name"])
	var row := HBoxContainer.new()
	row.add_child(UIKit.label("Cantidad:", 13))
	row.add_child(UIKit.spin(1, 5000, 1, qty, func(val): qty = val, 90))
	row.add_child(UIKit.label(" Cada (días):", 13))
	row.add_child(UIKit.spin(1, 365, 1, every, func(val): every = int(val), 70))
	body.add_child(row)
	var row2 := HBoxContainer.new()
	row2.add_child(UIKit.label("Precio límite del contrato (0 = sin límite):", 12, UIKit.TEXT_DIM))
	row2.add_child(UIKit.spin(0, 100000, 0.1, limit, func(val): limit = val, 90))
	body.add_child(row2)
	var tq := TradeSim.transport_quote(gs, tid, qty)
	_note("Flete de %d unidades: %d viaje(s), %d días, %s (%s por unidad)." % [int(qty), int(tq["trips"]), int(tq["days"]),
			Fmt.money(float(tq["cost"])), Fmt.money2(float(tq["cost"]) / maxf(1.0, qty))])
	var goods: Array = TradeSim.trade_goods()
	goods.sort_custom(func(a, b):
		var sa := WarehouseSim.stock(gs, a) > 0.0 or TradeSim.sells_good(gs, tid, a)
		var sb := WarehouseSim.stock(gs, b) > 0.0 or TradeSim.sells_good(gs, tid, b)
		return sa and not sb)
	for g in goods:
		var gid := str(g)
		var stock := WarehouseSim.stock(gs, gid)
		var sells := TradeSim.sells_good(gs, tid, gid)
		var demanded: bool = t.get("demands", []).has(gid)
		var line := HBoxContainer.new()
		var name_l := UIKit.label(TradeSim.good_label(gid) + (" ★" if demanded else ""), 13, UIKit.ACCENT if demanded else Color(0.95, 0.95, 0.95))
		name_l.custom_minimum_size.x = 100
		name_l.tooltip_text = "Este pueblo lo demanda: paga más." if demanded else ""
		line.add_child(name_l)
		var p_l := UIKit.label("Tienes %d · Pagan %s%s" % [int(stock), Fmt.money2(TradeSim.export_price(gs, tid, gid)),
				(" · Venden " + Fmt.money2(TradeSim.import_price(gs, tid, gid))) if sells else ""], 12, UIKit.TEXT_DIM)
		p_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(p_l)
		body.add_child(line)
		var acts := HBoxContainer.new()
		acts.add_child(Control.new())
		acts.get_child(0).custom_minimum_size.x = 100
		var sq := TradeSim.quote_sale(gs, tid, gid, qty)
		var sb := UIKit.button("Vender", func():
			_result(TradeSim.sell(GameState, tid, gid, qty), "Enviados %d de %s a %s." % [int(qty), TradeSim.good_label(gid), t["name"]]))
		sb.disabled = stock < 1.0
		sb.tooltip_text = "Neto estimado: %s (bruto %s − flete %s)" % [Fmt.money(float(sq["net"])), Fmt.money(float(sq["gross"])), Fmt.money(float(sq["transport"]))]
		acts.add_child(sb)
		acts.add_child(UIKit.button("Contrato venta", func():
			_result(TradeSim.add_contract(GameState, tid, gid, TradeSim.KIND_SELL, qty, every, limit), "Contrato: vender %d de %s cada %d días." % [int(qty), TradeSim.good_label(gid), every])))
		if sells:
			var pq := TradeSim.quote_purchase(gs, tid, gid, qty)
			var bb := UIKit.button("Comprar", func():
				_result(TradeSim.buy(GameState, tid, gid, qty), "Compra de %d de %s en camino." % [int(qty), TradeSim.good_label(gid)]))
			bb.tooltip_text = "Total: %s (bienes %s + flete %s)" % [Fmt.money(float(pq["total"])), Fmt.money(float(pq["goods"])), Fmt.money(float(pq["transport"]))]
			acts.add_child(bb)
			acts.add_child(UIKit.button("Contrato compra", func():
				_result(TradeSim.add_contract(GameState, tid, gid, TradeSim.KIND_BUY, qty, every, limit), "Contrato: comprar %d de %s cada %d días." % [int(qty), TradeSim.good_label(gid), every])))
		body.add_child(acts)
	_note("Si les vendes mucho de algo, su precio baja; se recupera con el tiempo. Los precios fluctúan cada mes. Las compras pagan arancel.")


func _shipments(gs) -> void:
	var list: Array = gs.trade.get("shipments", [])
	if list.is_empty():
		return
	_section("Envíos en camino")
	var s := ""
	for sh in list:
		var tname := str(TradeSim.town(gs, str(sh["town_id"])).get("name", ""))
		var left: int = maxi(0, int(sh["arrive_day"]) - gs.today())
		if str(sh["kind"]) == TradeSim.KIND_SELL:
			s += "→ %d %s a %s · cobras %s en %d días\n" % [int(sh["qty"]), TradeSim.good_label(str(sh["good"])), tname, Fmt.money(float(sh["value"])), left]
		else:
			s += "← %d %s desde %s · llega en %d días%s\n" % [int(sh["qty"]), TradeSim.good_label(str(sh["good"])), tname, left, " (esperando espacio)" if bool(sh.get("waiting", false)) else ""]
	_rich(s.strip_edges())


func _contracts(gs) -> void:
	var list: Array = gs.trade.get("contracts", [])
	_section("Contratos automáticos")
	if list.is_empty():
		_note("Sin contratos. En «Comerciar» puedes crear contratos que venden o compran cada X días.")
		return
	for k in list:
		var kid := int(k["id"])
		var row := HBoxContainer.new()
		var tname := str(TradeSim.town(gs, str(k["town_id"])).get("name", ""))
		var txt := "%s %d %s · %s · cada %d días%s" % ["Vender" if str(k["kind"]) == TradeSim.KIND_SELL else "Comprar", int(k["qty"]),
				TradeSim.good_label(str(k["good"])), tname, int(k["every"]), "" if bool(k.get("active", true)) else " (pausado)"]
		if float(k.get("limit", 0.0)) > 0.0:
			txt += " · límite %s" % Fmt.money2(float(k["limit"]))
		var l := UIKit.label(txt, 12)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.tooltip_text = "Cumplido %d veces. %s" % [int(k.get("done", 0)), str(k.get("last_error", "")) if int(k.get("fails", 0)) > 0 else ""]
		row.add_child(l)
		row.add_child(UIKit.button("Reanudar" if not bool(k.get("active", true)) else "Pausar", func():
			TradeSim.toggle_contract(GameState, kid)
			refresh()))
		row.add_child(UIKit.button("✕", func():
			TradeSim.remove_contract(GameState, kid)
			refresh(), 30))
		body.add_child(row)
