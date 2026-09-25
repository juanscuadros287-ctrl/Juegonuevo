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
	UIKit.header(self, "finance", "Finanzas", func(): closed.emit(), [])
	var sb := UIKit.scroll_box(Vector2(0, 200))
	sb["scroll"].size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(sb["scroll"])
	body = sb["box"]


func refresh() -> void:
	UIKit.clear(body)
	charts.clear()
	var gs := GameState
	var last: Dictionary = gs.history[-1] if not gs.history.is_empty() else {}
	var hist: Array = gs.history.slice(maxi(0, gs.history.size() - 24))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	body.add_child(g)
	var net := EconomySim.net_worth(gs)
	var debt := EconomySim.player_debt(gs)
	var res := float(last.get("income", 0)) - float(last.get("expenses", 0))
	var cards := [
		["money", "Dinero", Fmt.money(gs.money), hist.map(func(e): return float(e.get("money", 0.0))), UIKit.ACCENT, "Dinero en caja"],
		["treasury", "Patrimonio neto", Fmt.money(net), hist.map(func(e): return float(e.get("net_worth", 0.0))), UIKit.GOOD if net >= 0 else UIKit.BAD,
			"Dinero + propiedades %s + cartera %s − deudas" % [Fmt.money(EconomySim.player_assets(gs)), Fmt.money(EconomySim.loans_granted(gs))]],
		["finance", "Deudas", Fmt.money(debt), hist.map(func(e): return float(e.get("debt", 0.0))), UIKit.BAD if debt > 0 else UIKit.NEUTRAL, "Saldo de tus créditos"],
		["trend_up" if res >= 0 else "trend_down", "Resultado mes ant.", Fmt.money(res), hist.map(func(e): return float(e.get("income", 0.0)) - float(e.get("expenses", 0.0))), UIKit.sign_color(res),
			"Ingresos %s − gastos %s" % [Fmt.money(float(last.get("income", 0))), Fmt.money(float(last.get("expenses", 0)))]],
	]
	for c in cards:
		var arr: Array = c[3]
		var tr := UIKit.trend_bbcode((float(arr[-1]) - float(arr[-2])) / maxf(1.0, absf(float(arr[-2]))), c[1] == "Deudas") if arr.size() >= 2 else ""
		var k := UIKit.kpi_card(c[0], c[1], c[2], tr, arr, c[4], c[5], 0.0)
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(k)
	var chips := UIKit.flow(5, 5)
	body.add_child(chips)
	chips.add_child(UIKit.chip("Intereses: pagados %s · cobrados %s" % [Fmt.money(float(last.get("interest_paid", 0))), Fmt.money(float(last.get("interest_earned", 0)))], UIKit.TEXT_DIM, "finance", 11))
	chips.add_child(UIKit.chip("Impuestos %s" % Fmt.money(float(last.get("taxes_paid", 0))), UIKit.WARN, "government", 11))
	chips.add_child(UIKit.chip("Subsidios %s" % Fmt.money(float(last.get("subsidies", 0))), UIKit.GOOD, "money", 11))
	var eco := UIKit.section(body, "Economía del pueblo", "economy", true, "fin_eco")
	var ef := UIKit.flow(5, 5)
	eco.add_child(ef)
	ef.add_child(UIKit.chip("Nivel de precios %s" % String.num(gs.price_level(), 2), UIKit.TEXT_DIM, "inflation", 11))
	ef.add_child(UIKit.chip("Inflación %s" % _pct(EconomySim.annual_inflation(gs)), UIKit.WARN, "trend_up", 11))
	ef.add_child(UIKit.chip("Desempleo %s" % Fmt.pct(EconomySim.unemployment(gs) * 100.0), UIKit.BAD if EconomySim.unemployment(gs) > 0.2 else UIKit.TEXT_DIM, "employment", 11))
	ef.add_child(UIKit.chip("Circulante %s" % Fmt.money_compact(EconomySim.total_money(gs)), UIKit.TEXT_DIM, "money", 11))
	var rows := []
	for gid in GameData.sorted_ids(GameData.goods):
		if GameData.goods[gid].get("internal", false):
			continue
		var f := EconomySim.good_factor(gs, gid)
		var tag := "escasez" if f > 1.08 else ("exceso" if f < 0.92 else "normal")
		rows.append({"label": GameData.good_label(gid), "price": EconomySim.market_price(gs, gid), "factor": f - 1.0, "tag": tag,
			"tag_col": UIKit.BAD if tag == "escasez" else (UIKit.INFO if tag == "exceso" else UIKit.TEXT_DIM)})
	var pt := DataTable.new()
	pt.set_data([{"title": "Bien", "key": "label", "w": 1.6}, {"title": "Precio", "key": "price", "w": 1.0, "fmt": "money2"},
		{"title": "vs normal", "key": "factor", "w": 0.9, "fmt": "trend", "invert": true}, {"title": "Mercado", "key": "tag", "w": 0.9, "color_key": "tag_col"}], rows, 8)
	eco.add_child(pt)
	_loans_section()
	_investment_section()
	_charts_section()


func _col(v: float) -> String:
	return "[color=%s]%s[/color]" % ["#6c6" if v >= 0 else "#e66", Fmt.money(v)]


func _pct(v: float) -> String:
	return "%.1f%%" % (v * 100.0)


func _loans_section() -> void:
	body.add_child(UIKit.label("Créditos", 16, UIKit.ACCENT))
	# Bienes raíces: crédito con banco, tipo de pago, plazo y tabla antes de firmar.
	body.add_child(UIKit.button("Pedir crédito (banco, tipo, plazo y tabla)…", func(): LoanDialog.open(hud, refresh)))
	for l in BankSim.player_loans(GameState):
		var row := HBoxContainer.new()
		var kind := LoanContract.type_label(str(l.get("type", "")))
		var extra := " · cupo %s, desembolsado %s" % [Fmt.money(float(l.get("limit", 0.0))), Fmt.money(float(l.get("disbursed", 0.0)))] if str(l.get("type", "")) == "constructor" else ""
		var info := UIKit.label("%s · %s\n%s al %.1f%% · saldo %s · cuota %s · %d/%d meses%s%s" % [LoanContract.lender_label(GameState, str(l["lender"])), kind, Fmt.money(float(l["principal"])), float(l["rate"]) * 100.0, Fmt.money(float(l["balance"])), Fmt.money(float(l["payment"])), int(l["months_paid"]), int(l["term_months"]), extra, " · MORA %d" % int(l["missed"]) if int(l["missed"]) > 0 else ""], 13)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(info)
		var lid := int(l["id"])
		var ll: Dictionary = l
		var pre := UIKit.spin(0, maxf(1.0, float(l["balance"])), 10, minf(float(l["balance"]), 100.0 * GameState.price_level()), func(_v): pass, 90)
		pre.tooltip_text = "Monto del pago anticipado (abono a capital)"
		row.add_child(pre)
		row.add_child(UIKit.button("Abonar", func():
			message.emit(LoanContract.prepay(GameState, lid, pre.value), "jugador")
			refresh()))
		row.add_child(UIKit.button("Tabla", func(): LoanDialog.show_schedule(hud, ll)))
		row.add_child(UIKit.button("Pagar todo", func():
			message.emit(BankSim.repay_loan(GameState, lid), "jugador")
			refresh()))
		body.add_child(row)
	body.add_child(UIKit.label("Préstamo rápido · %s (cuota fija)" % BankSim.ext_cfg().get("label", "Banco"), 14, UIKit.ACCENT))
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
