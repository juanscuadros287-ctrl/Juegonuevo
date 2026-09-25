class_name CashPanel
extends VBoxContainer
## Sección E — panel "Efectivo y riesgo": efectivo y banco (depósito y retiro), impuesto a la venta,
## riesgo e inspecciones, caso abierto con soborno, casillas "no declarar" y "sueldos en negro" de
## tus negocios y contratos, negocios ocultos del mercado negro e historial. Lógica en MoneySim.

signal closed
signal message(text: String, category: String)

var hud: Hud
var body: VBoxContainer
var amount_spin: SpinBox
var bribe_spin: SpinBox


func setup(p_hud: Hud) -> void:
	hud = p_hud
	add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	add_child(head)
	var t := UIKit.label("Efectivo y riesgo", 20, UIKit.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UIKit.button("✕", func(): closed.emit(), 32))
	var sb := UIKit.scroll_box(Vector2(0, 200))
	sb["scroll"].size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(sb["scroll"])
	body = sb["box"]


func _act(text: String, ok_text := "") -> void:
	if text != "":
		message.emit(text, "jugador")
	elif ok_text != "":
		message.emit(ok_text, "negocio")
	refresh()


func _title(text: String) -> void:
	body.add_child(UIKit.label(text, 16, UIKit.ACCENT))


func _note(text: String) -> Label:
	var l := UIKit.label(text, 12, UIKit.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(l)
	return l


func refresh() -> void:
	if body == null:
		return
	UIKit.clear(body)
	var gs := GameState
	var s := "[b]Dinero[/b]\n"
	s += "Efectivo: %s · Banco: %s · Total: %s\n" % [Fmt.money(MoneySim.cash(gs)), _col(MoneySim.bank(gs)), Fmt.money(gs.money)]
	s += "%s: %.1f%% de cada venta declarada · causado este mes: %s\n" % [MoneySim.sales_tax_label(gs), MoneySim.sales_tax_rate(gs) * 100.0, Fmt.money(MoneySim.iva_pending(gs))]
	s += "Depósito sin sospechas este mes: %s\n" % Fmt.money(MoneySim.deposit_allowance(gs))
	s += "\n[b]Riesgo[/b]: %.0f/100 (%s) · inspección: %d%%/mes · hallazgo si inspeccionan: %d%%\n" % [MoneySim.risk(gs), MoneySim.risk_label(gs), int(MoneySim.inspection_chance(gs) * 100.0), int(MoneySim.find_chance(gs) * 100.0)]
	s += "Personas de confianza: %d → hasta %d%% de las ventas sin declarar\n" % [MoneySim.trusted_count(gs), int(MoneySim.undeclared_share(gs) * 100.0)]
	s += "Mes anterior: sin declarar %s · sueldos en negro %s · ventas ocultas %s · sobornos %s · multas %s" % [Fmt.money(MoneySim.stat(gs, "last_month", "undeclared")), Fmt.money(MoneySim.stat(gs, "last_month", "black_wages")), Fmt.money(MoneySim.stat(gs, "last_month", "hidden_sales")), Fmt.money(MoneySim.stat(gs, "last_month", "bribes")), Fmt.money(MoneySim.stat(gs, "last_month", "fines"))]
	var rl := UIKit.rich()
	rl.text = s
	body.add_child(rl)
	_money_section()
	_case_section()
	_business_section()
	_contract_section()
	_hidden_section()
	_log_section()


func _col(v: float) -> String:
	return "[color=%s]%s[/color]" % ["#6c6" if v >= 0 else "#e66", Fmt.money(v)]


func _money_section() -> void:
	_title("Depositar o retirar")
	var row := HBoxContainer.new()
	var gs := GameState
	amount_spin = UIKit.spin(0, 1000000, 10, snappedf(maxf(10.0, minf(MoneySim.cash(gs), 500.0)), 10.0), func(_v): pass, 120)
	row.add_child(amount_spin)
	row.add_child(UIKit.button("Depositar", func(): _act(MoneySim.deposit(GameState, amount_spin.value), "Depósito hecho.")))
	row.add_child(UIKit.button("Retirar", func(): _act(MoneySim.withdraw(GameState, amount_spin.value), "Retiro hecho.")))
	body.add_child(row)
	_note("El efectivo paga a quien lo acepta: jornaleros, proveedores informales, sueldos en negro y sobornos. El gobierno, los créditos y las empresas formales cobran por el banco. Depositar más de lo que justifican tus negocios legales levanta sospechas.")


func _case_section() -> void:
	var gs := GameState
	var c := MoneySim.case_of(gs)
	if c.is_empty():
		return
	_title("Caso abierto con la autoridad")
	var l := UIKit.label("Encontraron: %s.\nMulta prevista: %s%s. Plazo: %d días." % [str(c.get("found", "")), Fmt.money(float(c.get("fine", 0.0))), " · CASO GRAVE (cárcel)" if bool(c.get("grave", false)) else "", maxi(0, int(c.get("due", 0)) - gs.today())], 13, Color(1.0, 0.6, 0.55))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(l)
	var row := HBoxContainer.new()
	bribe_spin = UIKit.spin(0, 1000000, 10, snappedf(float(c.get("fine", 0.0)) * 0.5, 10.0), func(_v): pass, 120)
	row.add_child(bribe_spin)
	var chance := MoneySim.bribe_chance(gs, bribe_spin.value)
	row.add_child(UIKit.button("Sobornar (%d%%)" % int(chance * 100.0), func(): _act(MoneySim.bribe(GameState, bribe_spin.value))))
	row.add_child(UIKit.button("Aceptar la sanción", func(): _act(MoneySim.resolve_case(GameState))))
	body.add_child(row)
	_note("Si el inspector rechaza el soborno, la multa sube. Si lo acepta, el caso se archiva pero sube la corrupción de la familia (riesgo de escándalo).")


func _business_section() -> void:
	var gs := GameState
	var biz := gs.player_buildings("negocio").filter(func(b): return not BusinessSim.is_nonprofit(b) and str(gs.building_def(b).get("service", "")) == "")
	if biz.is_empty():
		return
	_title("Tus negocios")
	for b in biz:
		var row := HBoxContainer.new()
		var name_l := UIKit.label(gs.building_label(b), 13)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.clip_text = true
		row.add_child(name_l)
		var und := CheckBox.new()
		und.text = "No declarar"
		und.button_pressed = bool(b.get("undeclared", false))
		und.tooltip_text = "Parte de las ventas (la de tus personas de confianza) se cobra en efectivo, sin %s ni impuesto a la ganancia. Suma riesgo." % MoneySim.sales_tax_label(gs)
		var bid := int(b["id"])
		und.toggled.connect(func(on): _act(MoneySim.set_undeclared(GameState, GameState.get_building(bid), on)))
		row.add_child(und)
		var bw := CheckBox.new()
		bw.text = "Sueldos en negro"
		bw.button_pressed = bool(b.get("black_wages", false))
		bw.tooltip_text = "Paga los sueldos en efectivo, con descuento y sin impuesto de nómina. Si falta efectivo, se paga por el banco. Suma riesgo."
		bw.toggled.connect(func(on): _act(MoneySim.set_black_wages(GameState, GameState.get_building(bid), on)))
		row.add_child(bw)
		body.add_child(row)


func _contract_section() -> void:
	var gs := GameState
	var sales := ContractSim.active_contracts(gs).filter(func(k): return ContractSim.dir_of(k) == ContractSim.DIR_SELL)
	if sales.is_empty():
		return
	_title("Contratos de venta")
	for k in sales:
		var cb := CheckBox.new()
		cb.text = "No declarar: %s · %s" % [str(k.get("client_name", "")), TradeSim.good_label(str(k.get("good", "")))]
		cb.button_pressed = bool(k.get("undeclared", false))
		var why := MoneySim.contract_undeclared_block(gs, k)
		cb.disabled = why != "" and not cb.button_pressed
		cb.tooltip_text = why if why != "" else "La contraparte acepta pagar en efectivo sin factura."
		var kid := int(k["id"])
		cb.toggled.connect(func(on): _act(MoneySim.set_contract_undeclared(GameState, ContractSim.find(ContractSim.contracts(GameState), kid), on)))
		body.add_child(cb)


func _hidden_section() -> void:
	var gs := GameState
	_title("Negocios ocultos")
	var list := MoneySim.active_hidden(gs)
	if list.is_empty():
		_note("No tienes negocios ocultos.")
	for h in list:
		var t := MoneySim.hidden_type(str(h["type"]))
		var row := HBoxContainer.new()
		var l := UIKit.label("%s · %s: %d u. · precio %s · vendido %s%s" % [t.get("label", h["type"]), t.get("product", ""), int(float(h.get("stock", 0.0))), Fmt.money2(MoneySim.hidden_price(gs, str(h["type"]))), Fmt.money(float(h.get("sold_total", 0.0))), " · PARADO (sin efectivo)" if bool(h.get("idle", false)) else ""], 13)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var hid := int(h["id"])
		row.add_child(UIKit.button("Desmontar", func(): _act(MoneySim.close_hidden(GameState, hid))))
		body.add_child(row)
	for tid in MoneySim.hidden_ids():
		var t := MoneySim.hidden_type(tid)
		var why := MoneySim.hidden_block_reason(gs, tid)
		var btn := UIKit.button("Montar %s (%s en efectivo)" % [str(t.get("label", tid)).to_lower(), Fmt.money(MoneySim.setup_cost(gs, tid))], func(): _act(MoneySim.open_hidden(GameState, tid)))
		btn.disabled = why != ""
		btn.tooltip_text = why if why != "" else str(t.get("description", ""))
		body.add_child(btn)
		if why.begins_with("Requiere"):
			_note(why)
	_note("Producen y venden solo en efectivo, con demanda propia y precios altos. Pagan jornaleros e insumos en efectivo; si falta, se paran. Cada día suman riesgo de inspección.")


func _log_section() -> void:
	var l: Array = MoneySim.st(GameState).get("log", [])
	if l.is_empty():
		return
	_title("Historial")
	var s := ""
	for i in range(l.size() - 1, maxi(-1, l.size() - 16), -1):
		s += "[color=#aaa]%s[/color] %s\n" % [str(l[i].get("date", "")), str(l[i].get("text", ""))]
	var rl := UIKit.rich()
	rl.text = s
	body.add_child(rl)
