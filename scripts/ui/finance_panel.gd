class_name FinancePanel
extends VBoxContainer
## Finanzas del jugador: balance, patrimonio, préstamos, inversión por empresa,
## indicadores de la economía y gráficas históricas.

signal closed
signal message(text: String, category: String)

var hud: Hud
var body: VBoxContainer
var loan_amount: SpinBox
var loan_term: OptionButton
var loan_preview: Label
var charts: Array[LineChart] = []


func setup(p_hud: Hud) -> void:
	hud = p_hud
	add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	add_child(head)
	var t := UIKit.label("Finanzas", 20, UIKit.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UIKit.button("✕", func(): closed.emit(), 32))
	var sb := UIKit.scroll_box(Vector2(0, 200))
	sb["scroll"].size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(sb["scroll"])
	body = sb["box"]


func refresh() -> void:
	UIKit.clear(body)
	charts.clear()
	var gs := GameState
	var last: Dictionary = gs.history[-1] if not gs.history.is_empty() else {}
	var s := "[b]Balance[/b]\n"
	s += "Dinero: %s\n" % _col(gs.money)
	s += "Propiedades (valor): %s\n" % Fmt.money(EconomySim.player_assets(gs))
	s += "Préstamos otorgados (cartera): %s\n" % Fmt.money(EconomySim.loans_granted(gs))
	s += "Deudas: [color=#e88]%s[/color]\n" % Fmt.money(EconomySim.player_debt(gs))
	s += "[b]Patrimonio neto: %s[/b]\n\n" % _col(EconomySim.net_worth(gs))
	s += "[b]Mes anterior[/b]\n"
	s += "Ingresos: %s · Gastos: %s\n" % [Fmt.money(float(last.get("income", 0))), Fmt.money(float(last.get("expenses", 0)))]
	s += "Intereses pagados: %s · cobrados: %s\n" % [Fmt.money(float(last.get("interest_paid", 0))), Fmt.money(float(last.get("interest_earned", 0)))]
	s += "Impuestos pagados: %s · Subsidios: %s [color=#999](Fase 5)[/color]\n\n" % [Fmt.money(0), Fmt.money(0)]
	s += "[b]Economía del pueblo[/b]\n"
	s += "Nivel de precios: %.2f · Inflación anual: %s\n" % [gs.price_level(), _pct(EconomySim.annual_inflation(gs))]
	s += "Desempleo: %s · Dinero en circulación: %s\n" % [Fmt.pct(EconomySim.unemployment(gs) * 100.0), Fmt.money(EconomySim.total_money(gs))]
	var prices := []
	for g in GameData.sorted_ids(GameData.goods):
		if GameData.goods[g].get("internal", false):
			continue
		var f := EconomySim.good_factor(gs, g)
		var tag := "escasez" if f > 1.08 else ("exceso" if f < 0.92 else "normal")
		prices.append("%s %s (%s)" % [GameData.good_label(g), Fmt.money2(EconomySim.market_price(gs, g)), tag])
	s += "Precios de mercado: %s\n" % ", ".join(prices)
	var rl := UIKit.rich()
	rl.text = s
	body.add_child(rl)
	_loans_section()
	_investment_section()
	_charts_section()


func _col(v: float) -> String:
	return "[color=%s]%s[/color]" % ["#6c6" if v >= 0 else "#e66", Fmt.money(v)]


func _pct(v: float) -> String:
	return "%.1f%%" % (v * 100.0)


func _loans_section() -> void:
	body.add_child(UIKit.label("Préstamos · %s" % BankSim.ext_cfg().get("label", "Banco"), 16, UIKit.ACCENT))
	for l in BankSim.player_loans(GameState):
		var row := HBoxContainer.new()
		var info := UIKit.label("%s al %.1f%% · saldo %s · cuota %s · %d/%d meses%s" % [Fmt.money(float(l["principal"])), float(l["rate"]) * 100.0, Fmt.money(float(l["balance"])), Fmt.money(float(l["payment"])), int(l["months_paid"]), int(l["term_months"]), " · MORA %d" % int(l["missed"]) if int(l["missed"]) > 0 else ""], 13)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(info)
		var lid := int(l["id"])
		row.add_child(UIKit.button("Pagar todo", func():
			message.emit(BankSim.repay_loan(GameState, lid), "jugador")
			refresh()))
		body.add_child(row)
	var lim := BankSim.credit_limit(GameState)
	body.add_child(UIKit.label("Tasa ofrecida: %.1f%% anual · Límite disponible: %s" % [BankSim.player_rate(GameState) * 100.0, Fmt.money(lim)], 13, UIKit.TEXT_DIM))
	var row2 := HBoxContainer.new()
	loan_amount = UIKit.spin(0, maxf(0.0, lim), 50, minf(lim, 1000.0 * GameState.price_level()), func(_v): _update_preview(), 120)
	row2.add_child(loan_amount)
	loan_term = OptionButton.new()
	for m in BankSim.ext_cfg().get("terms_months", [12, 24, 60, 120]):
		loan_term.add_item("%d meses" % int(m))
		loan_term.set_item_metadata(loan_term.item_count - 1, int(m))
	loan_term.item_selected.connect(func(_i): _update_preview())
	row2.add_child(loan_term)
	row2.add_child(UIKit.button("Pedir préstamo", func():
		var err := BankSim.request_player_loan(GameState, loan_amount.value, int(loan_term.get_item_metadata(loan_term.selected)))
		message.emit(err if err != "" else "Préstamo aprobado.", "jugador" if err != "" else "importante")
		refresh()))
	body.add_child(row2)
	loan_preview = UIKit.label("", 12, UIKit.TEXT_DIM)
	loan_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	loan_preview.custom_minimum_size.x = 380
	body.add_child(loan_preview)
	_update_preview()


func _update_preview() -> void:
	if loan_preview == null:
		return
	var months := int(loan_term.get_item_metadata(loan_term.selected))
	var pay := BankSim.payment(loan_amount.value, BankSim.player_rate(GameState), months)
	loan_preview.text = "Cuota mensual: %s · Total a pagar: %s. Si no pagas 3 cuotas, embargan tus propiedades." % [Fmt.money(pay), Fmt.money(pay * months)]


func _investment_section() -> void:
	body.add_child(UIKit.label("Inversión y rentabilidad por empresa", 16, UIKit.ACCENT))
	var t := ""
	for b in GameState.player_buildings():
		var inv := BusinessSim.period_value(b, "total", "obras")
		var profit := BusinessSim.period_profit(b, "total")
		var roi := "—" if inv <= 0.0 else _pct(profit / inv)
		t += "• %s: invertido %s · resultado %s · ROI %s · [i]%s[/i]\n" % [GameState.building_label(b), Fmt.money(inv), _col(profit), roi, EconomySim.classify(b)]
	var rl := UIKit.rich()
	rl.text = t if t != "" else "[color=#999]Sin empresas todavía.[/color]"
	body.add_child(rl)


func _charts_section() -> void:
	body.add_child(UIKit.label("Historial (mensual)", 16, UIKit.ACCENT))
	var h: Array = GameState.history.slice(maxi(0, GameState.history.size() - 240))
	var col := func(key: String) -> Array: return h.map(func(e): return float(e.get(key, 0.0)))
	_chart("Dinero y patrimonio", [
		{"label": "Dinero", "color": Color(0.95, 0.8, 0.3), "values": col.call("money")},
		{"label": "Patrimonio", "color": Color(0.4, 0.8, 0.5), "values": col.call("net_worth")},
		{"label": "Deuda", "color": Color(0.9, 0.4, 0.4), "values": col.call("debt")}])
	_chart("Ingresos vs gastos", [
		{"label": "Ingresos", "color": Color(0.4, 0.8, 0.5), "values": col.call("income")},
		{"label": "Gastos", "color": Color(0.9, 0.4, 0.4), "values": col.call("expenses")}])
	_chart("Población", [{"label": "Habitantes", "color": Color(0.5, 0.7, 0.95), "values": col.call("population")}], false)
	_chart("Precios e inflación", [
		{"label": "Nivel de precios", "color": Color(0.95, 0.6, 0.3), "values": col.call("price_level")},
		{"label": "Inflación anual", "color": Color(0.8, 0.5, 0.9), "values": col.call("inflation")},
		{"label": "Desempleo", "color": Color(0.6, 0.6, 0.6), "values": col.call("unemployment")}], false)


func _chart(title: String, series: Array, money := true) -> void:
	var c := LineChart.new()
	c.custom_minimum_size = Vector2(390, 160)
	c.set_data(title, series, money)
	body.add_child(c)
	charts.append(c)
