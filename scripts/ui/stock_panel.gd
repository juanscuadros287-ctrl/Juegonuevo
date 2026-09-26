class_name StockPanel
extends VBoxContainer
## Bolsa de valores mundial (StockSim): ley, tu S.A. (convertir, emitir, recomprar, dividendos),
## tabla de empresas del país y del mundo con precios en su moneda y convertidos, comprar y vender.

signal message(text: String, category: String)

var head: RichTextLabel
var own_box: VBoxContainer
var list: VBoxContainer
var log_text: RichTextLabel
var _qty := 10


func setup() -> void:
	add_theme_constant_override("separation", 8)
	head = UIKit.rich()
	add_child(head)
	own_box = VBoxContainer.new()
	own_box.add_theme_constant_override("separation", 6)
	add_child(own_box)
	add_child(HSeparator.new())
	var row := HBoxContainer.new()
	row.add_child(UIKit.label("Acciones por operación:", 14, UIKit.TEXT_DIM))
	row.add_child(UIKit.spin(1, 100000, 1, _qty, func(v): _qty = int(v), 100))
	add_child(row)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	add_child(list)
	add_child(HSeparator.new())
	add_child(UIKit.label("Movimientos", 15, UIKit.ACCENT))
	log_text = UIKit.rich()
	add_child(log_text)


func _msg(err: String, ok: String) -> void:
	message.emit(err if err != "" else ok, "jugador" if err != "" else "negocio")
	refresh()


func refresh() -> void:
	var gs := GameState
	if head == null:
		return
	UIKit.clear(own_box)
	UIKit.clear(list)
	var why := StockSim.block_reason(gs)
	var l := StockSim.law(gs)
	var s := "[b]Bolsa de valores mundial[/b]\n"
	if why != "":
		s += "[color=#e9b949]%s[/color]\n" % why
		if StockSim.era_ok(gs):
			s += "Probabilidad de que el gobierno actual (%s) la apruebe: %d %%.\n" % [str(GovSim.policy(gs).get("label", "")), int(StockSim.approval_chance(gs) * 100.0)]
			var pw := StockSim.propose_block_reason(gs)
			var b := UIKit.button("Proponer la Ley de Mercado de Valores (%s)" % Fmt.money(StockSim.law_cost(gs)), func():
				_msg(StockSim.propose_law(GameState), "Propuesta enviada al gobierno."))
			b.disabled = pw != ""
			b.tooltip_text = pw
			own_box.add_child(b)
		head.text = s
		log_text.text = _log_text(gs)
		return
	s += "Aprobada el %s (%s). Índice de %s: %d · P/G del ciclo: %.1f\n" % [TimeManager.date_from_day(int(l.get("approved_day", 0)), TimeManager.start_year()),
		"a propuesta tuya" if str(l.get("by", "")) == "jugador" else "por iniciativa del gobierno", GlobalEconSim.country_label(GlobalEconSim.home_id(gs)),
		int(float(GlobalEconSim.home(gs).get("ind", {}).get("bolsa", 100.0))), GlobalEconSim.eff(gs, "pe", 10.0)]
	s += "Tu cartera (otras empresas): [b]%s[/b]\n" % Fmt.money(StockSim.portfolio_value(gs))
	head.text = s
	_own_section(gs)
	for r in StockSim.rows(gs):
		if str(r["kind"]) != "jugador":
			list.add_child(_company_row(gs, r))
	log_text.text = _log_text(gs)


func _own_section(gs) -> void:
	var co := StockSim.player_company(gs)
	if co.is_empty():
		var why := StockSim.convert_block_reason(gs)
		var b := UIKit.button("Convertir tu empresa en S.A. (inscripción %s)" % Fmt.money(float(StockSim.cfg().get("listing_fee", 250)) * gs.price_mult()), func():
			_msg(StockSim.convert_to_sa(GameState), "Tu empresa ya es una S.A."))
		b.disabled = why != ""
		b.tooltip_text = why if why != "" else "Todas tus empresas con fines de lucro pasan a ser una sociedad anónima con %d acciones (todas tuyas)." % int(StockSim.cfg().get("company_shares", 1000))
		own_box.add_child(b)
		return
	var ctrl := StockSim.controller(co)
	var t := UIKit.rich()
	var txt := "[b]%s[/b] · %d acciones a %s · valor de mercado %s\n" % [str(co["name"]), int(co["shares"]), Fmt.money2(float(co["price"])), Fmt.money(StockSim.market_cap(gs, co))]
	txt += "Tu participación: [b]%d %%[/b] · Ganancia anual estimada %s · Precio fundamental %s\n" % [int(StockSim.stake(co, StockSim.PLAYER) * 100.0), Fmt.money(StockSim.annual_profit(co)), Fmt.money2(StockSim.fundamental(gs, co))]
	txt += "Dividendos: reparte el %d %% de la ganancia (último: %s por acción)\n" % [int(StockSim.payout_of(co) * 100.0), Fmt.money2(float(co.get("div_last", 0.0)))]
	if ctrl != StockSim.PLAYER:
		txt += "[color=#e55]Perdiste el control: %s tiene el %d %%. Recompra acciones para recuperarlo.[/color]\n" % [StockSim.holder_label(gs, ctrl), int(StockSim.stake(co, ctrl) * 100.0)]
	elif StockSim.stake(co, StockSim.PLAYER) < 0.5:
		txt += "[color=#e9b949]Tienes menos del 50 %: riesgo de compra hostil.[/color]\n"
	var tops := []
	for h in StockSim.top_holders(gs, co, 4):
		tops.append("%s %d %%" % [h[0], int(float(h[1]) * 100.0)])
	txt += "[color=#aaa]Accionistas: %s[/color]\n" % ", ".join(tops)
	txt += "[color=#aaa]Ahorradores dispuestos a invertir: %s[/color]" % Fmt.money(StockSim.investor_capacity(gs))
	t.text = txt
	own_box.add_child(t)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var max_q := int(float(co["shares"]) * float(StockSim.cfg().get("max_issue_ratio", 0.35)))
	var issue_spin := UIKit.spin(1, maxi(1, max_q), 1, maxi(1, max_q / 3), func(_v): pass, 90)
	row.add_child(issue_spin)
	var ib := UIKit.button("Emitir acciones", func():
		var r := StockSim.issue(GameState, int(issue_spin.value))
		_msg(str(r["error"]), "Capital obtenido: %s." % Fmt.money(float(r["raised"]))))
	ib.tooltip_text = StockSim.issue_block_reason(gs, int(issue_spin.value))
	row.add_child(ib)
	var bb_spin := UIKit.spin(1, maxi(1, int(co["shares"])), 1, 50, func(_v): pass, 90)
	row.add_child(bb_spin)
	row.add_child(UIKit.button("Recomprar", func():
		var r := StockSim.buyback(GameState, int(bb_spin.value))
		_msg(str(r["error"]), "Recompraste %d acciones." % int(r["bought"]))))
	own_box.add_child(row)
	var row2 := HBoxContainer.new()
	row2.add_child(UIKit.label("Reparto de dividendos (%):", 14, UIKit.TEXT_DIM))
	var on_payout := func(v):
		var err := StockSim.set_payout(GameState, float(v) / 100.0)
		if err != "":
			message.emit(err, "jugador")
	var ps := UIKit.spin(0, float(StockSim.cfg().get("payout_max", 0.8)) * 100.0, 5, float(co.get("payout", 0.3)) * 100.0, on_payout, 80)
	ps.editable = ctrl == StockSim.PLAYER
	row2.add_child(ps)
	own_box.add_child(row2)


func _company_row(gs, r: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.BG_LIGHT, 6, 6))
	var v := VBoxContainer.new()
	panel.add_child(v)
	var co := StockSim.company(gs, str(r["id"]))
	var foreign := str(r["kind"]) == "extranjera"
	var price_txt := GlobalEconSim.fmt_foreign(gs, float(r["price"]), str(r["country"])) if foreign else Fmt.money2(float(r["price"]))
	var col := "#6c6" if float(r["change"]) >= 0.0 else "#e66"
	var t := UIKit.rich()
	var where := GlobalEconSim.country_label(str(r["country"])) if foreign else "tu país (empresa NPC)"
	t.text = "[b]%s[/b] · %s\nPrecio %s · [color=%s]%+d %% en 12 meses[/color] · dividendo %s\nTienes %d (%s)" % [
		str(r["name"]), where, price_txt, col, int(round(float(r["change"]) * 100.0)),
		GlobalEconSim.fmt_foreign(gs, float(r["div"]), str(r["country"])) if foreign else Fmt.money2(float(r["div"])),
		int(r["mine"]), Fmt.money(StockSim.holding_value(gs, co))]
	v.add_child(t)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var cid := str(r["id"])
	var q := StockSim.quote_buy(gs, cid, _qty)
	var b := UIKit.button("Comprar (%s)" % Fmt.money(float(q["total"])), func():
		var res := StockSim.buy(GameState, cid, _qty)
		_msg(str(res["error"]), "Compraste %d acciones por %s." % [int(res["bought"]), Fmt.money(float(res["cost"]))]))
	b.disabled = int(q["available"]) <= 0
	row.add_child(b)
	var s := UIKit.button("Vender", func():
		var res := StockSim.sell(GameState, cid, _qty)
		_msg(str(res["error"]), "Vendiste %d acciones por %s." % [int(res["sold"]), Fmt.money(float(res["received"]))]))
	s.disabled = int(r["mine"]) <= 0
	row.add_child(s)
	v.add_child(row)
	return panel


func _log_text(gs) -> String:
	var l: Array = StockSim.st(gs).get("log", [])
	var out := ""
	for i in range(l.size() - 1, maxi(-1, l.size() - 11), -1):
		out += "[color=#aaa]%s[/color] %s\n" % [l[i]["date"], l[i]["text"]]
	return out if out != "" else "[color=#aaa]Sin movimientos.[/color]"
