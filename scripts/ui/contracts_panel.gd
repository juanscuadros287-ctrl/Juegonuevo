class_name ContractsPanel
extends VBoxContainer
## Panel "Contratos" (libre mercado). Pestañas:
##   Bandeja   — solicitudes de venta, ofertas de proveedores (Aceptar/Rechazar/Contraofertar)
##               y contraofertas a tus propuestas.
##   Proponer  — formulario de compra o venta recurrente a precio fijo (contraparte, bien, cantidad,
##               precio con referencia de mercado, frecuencia, entregas, inicio, automática, almacén).
##   Activos   — próxima entrega, entregas hechas/total, cumplimiento, entregar ahora y cancelar.
##   Historial — contratos cerrados, propuestas enviadas, reputación y fiabilidad de proveedores.

signal closed
signal message(text: String, category: String)

const TABS := [["bandeja", "Bandeja"], ["proponer", "Proponer"], ["activos", "Activos"], ["historial", "Historial"]]
const TAB_ICONS := {"bandeja": "bell", "proponer": "plus", "activos": "check", "historial": "list"}
const FREQ_OPTIONS := [0, 7, 15, 30, 60, 90, -1]   # 0 = entrega única, -1 = personalizada

var hud: Hud
var body: VBoxContainer
var tab_bar: HBoxContainer
var tab := "bandeja"
# Formulario "Proponer".
var client_opt: OptionButton
var good_opt: OptionButton
var qty_spin: SpinBox
var price_spin: SpinBox
var ref_label: Label
var total_label: Label
var _clients: Array = []
var _goods: Array = []
var _wids: Array = []
var sel_dir := ContractSim.DIR_SELL
var sel_client := ""
var sel_good := ""
var qty := 20.0
var price := 0.0
var freq_idx := 3          # mensual
var custom_period := 20
var installments := 4
var start_in := 7
var auto := true
var sel_wid := 0
var counter_prices: Dictionary = {}   # id de solicitud -> precio de contraoferta


func setup(p_hud: Hud) -> void:
	hud = p_hud
	add_theme_constant_override("separation", 8)
	UIKit.header(self, "contracts", "Contratos", func(): closed.emit(), [UIKit.icon_button("refresh", refresh, "Actualizar", "", 16)])
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


func _section(title: String) -> void:
	body.add_child(HSeparator.new())
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.add_child(UIKit.icon("contracts", 16, UIKit.ACCENT))
	h.add_child(UIKit.label(title, 16, UIKit.ACCENT))
	body.add_child(h)


func _note(text: String, parent: Node = null) -> void:
	var l := UIKit.label(text, 12, UIKit.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 380
	(parent if parent != null else body).add_child(l)


func _text(text: String, size := 13, color := Color(0.95, 0.95, 0.95)) -> Label:
	var l := UIKit.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 380
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _date(day: int) -> String:
	return TimeManager.date_from_day(day, TimeManager.start_year())


func _freq_text(inst: int, period: int) -> String:
	return "entrega única" if inst <= 1 else "%s × %d entregas" % [ContractSim.period_label(period), inst]


func refresh() -> void:
	if body == null:
		return
	UIKit.clear(tab_bar)
	for tdef in TABS:
		var id := str(tdef[0])
		var label := str(tdef[1])
		if id == "bandeja":
			var n := ContractSim.inbox(GameState).size() + ContractSim.sent(GameState).filter(func(o): return str(o["status"]) == "contraoferta").size()
			if n > 0:
				label += " (%d)" % n
		elif id == "activos" and not GameState.market.is_empty():
			label += " (%d)" % ContractSim.active_contracts(GameState).size()
		var b := UIKit.button(label, func(): set_tab(id))
		b.icon = UIIcons.tex(str(TAB_ICONS.get(id, "info")), 16)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggle_mode = true
		b.button_pressed = id == tab
		tab_bar.add_child(b)
	UIKit.clear(body)
	var gs := GameState
	if gs.market.is_empty():
		return
	match tab:
		"proponer":
			_propose_form(gs)
		"activos":
			_active(gs)
		"historial":
			_history(gs)
			_sent(gs)
			_purchases(gs)
			_reputation(gs)
		_:
			var mine := ContractSim.player_goods(gs)
			var s := "Produces: %s" % (", ".join(mine.keys().map(func(g): return TradeSim.good_label(str(g)))) if not mine.is_empty() else "nada todavía")
			body.add_child(_text(s, 13, UIKit.TEXT_DIM))
			_note("Te piden comprar solo bienes que produce alguno de tus negocios; los proveedores te ofrecen lo que tus negocios consumen. Lo que no cubres lo compran a otros (libre mercado).")
			_inbox(gs)
			_counters(gs)


# --- Bandeja ----------------------------------------------------------------------------------------

func _inbox(gs) -> void:
	_section("Bandeja de entrada (%d)" % ContractSim.inbox(gs).size())
	if ContractSim.inbox(gs).is_empty():
		_note("No hay solicitudes. Llegan de pueblos con ruta comercial, de empresas NPC y del gobierno.")
	for r in ContractSim.inbox(gs):
		var inst := int(r.get("installments", 1))
		var period := int(r.get("period", 30))
		var buy := ContractSim.is_buy(r)
		var when := "entrega única, plazo %d días" % int(r["deadline_days"]) if inst <= 1 else _freq_text(inst, period)
		var head := "[%s te vende]" % r["client_name"] if buy else "[%s te compra]" % r["client_name"]
		var t := "%s %d de %s a %s c/u (total %s) · %s · penalidad %s · vence %s · tienes %d" % [head, int(r["qty"]), TradeSim.good_label(str(r["good"])),
			Fmt.money2(float(r["unit_price"])), Fmt.money(float(r["unit_price"]) * float(r["qty"]) * inst), when, Fmt.money(float(r["penalty"])), _date(int(r["expires_day"])),
			int(ContractSim.available(gs, str(r["good"])))]
		body.add_child(_text(t))
		var row := HBoxContainer.new()
		var id := int(r["id"])
		row.add_child(UIKit.button("Aceptar", func(): _result("", ContractSim.accept_request(GameState, id))))
		row.add_child(UIKit.button("Rechazar", func(): _result("", ContractSim.reject_request(GameState, id))))
		if not counter_prices.has(id):
			counter_prices[id] = float(r["unit_price"]) * (0.92 if buy else 1.08)
		row.add_child(UIKit.spin(0.01, 100000, 0.01, float(counter_prices[id]), func(v): counter_prices[id] = v, 90))
		row.add_child(UIKit.button("Contraofertar", func():
			_result(ContractSim.counter_request(GameState, id, float(counter_prices[id])), "Contraoferta enviada: responderán en unos días.")))
		body.add_child(row)


func _counters(gs) -> void:
	var list: Array = ContractSim.sent(gs).filter(func(o): return str(o["status"]) == "contraoferta")
	if list.is_empty():
		return
	_section("Contraofertas a tus propuestas (%d)" % list.size())
	for o in list:
		var inst := int(o.get("installments", 1))
		body.add_child(_text("%s · %s de %d %s · pediste %s, proponen %s c/u · %s · vence %s" % [o["client_name"], ContractSim.dir_label(ContractSim.dir_of(o)).to_lower(),
			int(o["qty"]), TradeSim.good_label(str(o["good"])), Fmt.money2(float(o["unit_price"])), Fmt.money2(float(o["counter_price"])), _freq_text(inst, int(o.get("period", 30))),
			_date(int(o.get("counter_expires", 0)))]))
		var row := HBoxContainer.new()
		var id := int(o["id"])
		row.add_child(UIKit.button("Aceptar", func(): _result("", ContractSim.accept_counter(GameState, id))))
		row.add_child(UIKit.button("Rechazar", func(): _result("", ContractSim.reject_counter(GameState, id))))
		body.add_child(row)


# --- Proponer ---------------------------------------------------------------------------------------

func _period() -> int:
	var f := int(FREQ_OPTIONS[freq_idx])
	if f == 0:
		return 30
	return custom_period if f < 0 else f


func _inst() -> int:
	return 1 if int(FREQ_OPTIONS[freq_idx]) == 0 else maxi(1, installments)


func _row(label: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_child(UIKit.label(label, 13))
	body.add_child(row)
	return row


func _option(items: Array, selected: int, cb: Callable) -> OptionButton:
	var o := OptionButton.new()
	for i in range(items.size()):
		o.add_item(str(items[i]), i)
	o.selected = clampi(selected, 0, maxi(0, items.size() - 1))
	o.item_selected.connect(cb)
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return o


func _propose_form(gs) -> void:
	_section("Proponer contrato")
	_note("Precio FIJO por unidad durante todo el contrato. La contraparte responde en 2 a 5 días: acepta, rechaza o hace una contraoferta de precio.")
	var dirs := [ContractSim.DIR_SELL, ContractSim.DIR_BUY]
	var r0 := _row("Dirección:")
	r0.add_child(_option(["Yo vendo", "Yo compro"], dirs.find(sel_dir), func(i):
		sel_dir = str(dirs[i])
		sel_client = ""
		price = 0.0
		call_deferred("refresh")))
	# Bien.
	if sel_dir == ContractSim.DIR_SELL:
		var goods := ContractSim.player_goods(gs).duplicate()
		var st := WarehouseSim.all_stock(gs)
		for g in st:
			if float(st[g]) >= 1.0 and ContractSim.is_tradeable(str(g)):
				goods[str(g)] = true
		_goods = goods.keys()
		_goods.sort()
	else:
		var needs := ContractSim.player_needs(gs)
		var first: Array = needs.keys()
		first.sort()
		var rest: Array = ContractSim.tradeable_goods().filter(func(g): return not needs.has(g))
		_goods = first + rest
	if _goods.is_empty():
		_note("Necesitas producir algo o tener existencias para ofrecer.")
		return
	if not _goods.has(sel_good):
		sel_good = str(_goods[0])
		price = 0.0
	var needs2 := ContractSim.player_needs(gs)
	var labels := _goods.map(func(g): return "%s (tienes %d)%s" % [TradeSim.good_label(str(g)), int(ContractSim.available(gs, str(g))), " · insumo" if needs2.has(g) and sel_dir == ContractSim.DIR_BUY else ""])
	var r1 := _row("Bien:")
	good_opt = _option(labels, _goods.find(sel_good), func(i):
		sel_good = str(_goods[i])
		sel_client = ""
		price = 0.0
		call_deferred("refresh"))
	r1.add_child(good_opt)
	# Contraparte.
	_clients = ContractSim.client_keys(gs) if sel_dir == ContractSim.DIR_SELL else ContractSim.supplier_keys(gs, sel_good)
	if _clients.is_empty():
		_note("Nadie vende ese bien.")
		return
	if not _clients.has(sel_client):
		sel_client = str(_clients[0])
		price = 0.0
	var cl_labels := _clients.map(func(k): return _client_label(gs, str(k)))
	var r2 := _row("Contraparte:")
	client_opt = _option(cl_labels, _clients.find(sel_client), func(i):
		sel_client = str(_clients[i])
		price = 0.0
		call_deferred("refresh"))
	r2.add_child(client_opt)
	# Cantidad y precio.
	var r3 := _row("Cantidad por entrega:")
	qty_spin = UIKit.spin(1, 5000, 1, qty, func(v):
		qty = v
		_update_total(), 90)
	r3.add_child(qty_spin)
	r3.add_child(UIKit.label("Precio c/u:", 13))
	var ref := ContractSim.reference_price(gs, sel_client, sel_good, qty, sel_dir)
	if price <= 0.0:
		price = snappedf(ref, 0.01)
	price_spin = UIKit.spin(0.01, 100000, 0.01, price, func(v):
		price = v
		_update_total(), 100)
	r3.add_child(price_spin)
	ref_label = UIKit.label("", 12, UIKit.TEXT_DIM)
	ref_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ref_label.custom_minimum_size.x = 380
	body.add_child(ref_label)
	_update_ref()
	# Frecuencia y duración.
	var fl := FREQ_OPTIONS.map(func(f): return "Entrega única" if int(f) == 0 else ("Personalizada" if int(f) < 0 else "Cada %d días (%s)" % [int(f), ContractSim.period_label(int(f))]))
	var r4 := _row("Frecuencia:")
	r4.add_child(_option(fl, freq_idx, func(i):
		freq_idx = i
		call_deferred("refresh")))
	if int(FREQ_OPTIONS[freq_idx]) < 0:
		r4.add_child(UIKit.label("cada", 13))
		r4.add_child(UIKit.spin(1, 365, 1, custom_period, func(v):
			custom_period = int(v)
			_update_total(), 70))
		r4.add_child(UIKit.label("días", 13))
	var r5 := _row("Entregas:")
	var ins := UIKit.spin(1, 120, 1, _inst(), func(v):
		installments = int(v)
		_update_total(), 70)
	ins.editable = int(FREQ_OPTIONS[freq_idx]) != 0
	r5.add_child(ins)
	r5.add_child(UIKit.label("Primera en", 13))
	r5.add_child(UIKit.spin(0, 365, 1, start_in, func(v):
		start_in = int(v)
		_update_total(), 70))
	r5.add_child(UIKit.label("días", 13))
	var r6 := HBoxContainer.new()
	var chk := CheckBox.new()
	chk.text = "Entrega automática"
	chk.button_pressed = auto
	chk.toggled.connect(func(on): auto = on)
	r6.add_child(chk)
	body.add_child(r6)
	if sel_dir == ContractSim.DIR_BUY:
		_wids = WarehouseSim.ids(gs)
		if not _wids.has(sel_wid):
			sel_wid = WarehouseSim.PLAZA
		var wl := _wids.map(func(w): return "%s (libre %d)" % [WarehouseSim.label_of(gs, int(w)), int(WarehouseSim.free_in(gs, int(w)))])
		var r7 := _row("Llega a:")
		r7.add_child(_option(wl, _wids.find(sel_wid), func(i): sel_wid = int(_wids[i])))
	total_label = UIKit.label("", 13, UIKit.ACCENT)
	total_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	total_label.custom_minimum_size.x = 380
	body.add_child(total_label)
	_update_total()
	body.add_child(UIKit.button("Enviar propuesta", _send))


func _client_label(gs, key: String) -> String:
	var n := ContractSim.client_name(gs, key)
	if sel_dir == ContractSim.DIR_BUY:
		if ContractSim.client_kind(key) == ContractSim.IMPORT_KEY:
			return "%s (último recurso, más cara)" % n
		return "%s (stock %d · fiabilidad %d)" % [n, int(ContractSim.supplier_stock(gs, key, sel_good)), int(ContractSim.reliability(gs, key))]
	return n


func _opts() -> Dictionary:
	return {"period": _period(), "installments": _inst(), "start_in": start_in, "auto": auto, "wid": sel_wid}


func _send() -> void:
	var gs := GameState
	var err := ContractSim.propose(gs, sel_dir, sel_client, sel_good, qty, price, _opts())
	_result(err, "Propuesta enviada a %s: responderá en unos días." % ContractSim.client_name(gs, sel_client))


func _on_client(i: int) -> void:
	sel_client = str(_clients[i])
	_update_ref()


func _on_good(i: int) -> void:
	sel_good = str(_goods[i])
	_update_ref()


func _update_ref() -> void:
	if ref_label == null or sel_client == "":
		return
	var gs := GameState
	var ref := ContractSim.reference_price(gs, sel_client, sel_good, qty, sel_dir)
	var extra := ""
	if ContractSim.client_kind(sel_client) == "town" and not TradeSim.connection(gs, ContractSim.client_ref(sel_client)).is_empty():
		var tq := TradeSim.transport_quote(gs, ContractSim.client_ref(sel_client), qty)
		extra = " · flete ~%s por entrega (%d días)" % [Fmt.money(float(tq["cost"])), int(tq["days"])]
	elif ContractSim.client_kind(sel_client) == ContractSim.IMPORT_KEY:
		extra = " · llega en %d días" % int(ContractSim.cfg().get("import_days", 7))
	var rep := "reputación %d/100" % int(ContractSim.reputation(gs, sel_client))
	ref_label.text = "Referencia de mercado: %s c/u (precio local %s) · %s%s" % [Fmt.money2(ref), Fmt.money2(ContractSim.market_ref(gs, sel_good)), rep, extra]


func _update_total() -> void:
	if total_label == null or sel_client == "":
		return
	var gs := GameState
	var inst := _inst()
	var est := ContractSim.estimate_total(gs, sel_dir, sel_client, qty, price, inst)
	var start := gs.today() + start_in
	var end := start + _period() * (inst - 1)
	var what := "pagarías" if sel_dir == ContractSim.DIR_BUY else "cobrarías"
	var fr := "" if float(est["freight"]) <= 0.0 else " · flete %s" % Fmt.money(float(est["freight"]))
	total_label.text = "Estimado: %s %s por %d × %d = %s%s · del %s al %s · penalidad %s por entrega" % [what, Fmt.money(float(est["goods"])), int(qty), inst,
		Fmt.money(float(est["goods"])), fr, _date(start), _date(end), Fmt.money(price * qty * float(ContractSim.cfg().get("penalty_share", 0.2)))]


# --- Activos ----------------------------------------------------------------------------------------

func _active(gs) -> void:
	var list := ContractSim.active_contracts(gs)
	_section("Contratos activos (%d)" % list.size())
	if list.is_empty():
		_note("Sin contratos firmados. Acepta solicitudes en la Bandeja o propón uno en Proponer.")
	for k in list:
		var inst := int(k["installments"])
		var buy := ContractSim.is_buy(k)
		var done := int(k["done"])
		var cp := int(k.get("cp_failed", 0))
		var t := "%s · %s · %d de %s a %s c/u · %s" % [ContractSim.dir_label(ContractSim.dir_of(k)), k["client_name"], int(k["qty"]), TradeSim.good_label(str(k["good"])),
			Fmt.money2(float(k["unit_price"])), _freq_text(inst, int(k.get("period", 30)))]
		body.add_child(_text(t))
		var info := "Próxima entrega: %s · hechas %d/%d · cumplimiento %d%%%s · total %s · penalidad %s" % [_date(int(k["next_due"])), done, inst,
			int(round(ContractSim.compliance(k) * 100.0)), (" · el proveedor falló %d" % cp) if cp > 0 else "",
			Fmt.money(float(k["qty"]) * float(k["unit_price"]) * inst), Fmt.money(float(k["penalty"]))]
		if buy:
			info += " · llega a %s" % WarehouseSim.label_of(gs, ContractSim.dest_wid(gs, k))
			if float(k.get("debt", 0.0)) > 0.0:
				info += " · debes %s" % Fmt.money(float(k["debt"]))
		elif float(k.get("owed", 0.0)) > 0.0:
			info += " · te deben %s" % Fmt.money(float(k["owed"]))
		body.add_child(_text(info, 12, UIKit.TEXT_DIM))
		var row := HBoxContainer.new()
		var id := int(k["id"])
		var why := ContractSim.deliver_block_reason(gs, k)
		var b := UIKit.button("Recibir ahora" if buy else "Entregar ahora", func(): _result(ContractSim.deliver(GameState, id), "Entrega recibida." if buy else "Entrega despachada."))
		b.disabled = why != ""
		b.tooltip_text = why
		row.add_child(b)
		var auto_chk := CheckBox.new()
		auto_chk.text = "Automática"
		auto_chk.button_pressed = bool(k.get("auto", false))
		var kk: Dictionary = k
		auto_chk.toggled.connect(func(on): kk["auto"] = on)
		row.add_child(auto_chk)
		var c := UIKit.button("Cancelar (%s)" % Fmt.money(float(k["penalty"])), func(): _result(ContractSim.cancel(GameState, id), "Contrato cancelado: pagaste la penalidad."))
		c.tooltip_text = "Pagas la penalidad a la contraparte y baja un poco tu reputación."
		row.add_child(c)
		body.add_child(row)
		if why != "":
			_note(why)


# --- Historial ----------------------------------------------------------------------------------------

func _sent(gs) -> void:
	var list: Array = ContractSim.sent(gs)
	_section("Propuestas enviadas")
	if list.is_empty():
		_note("Aún no has enviado propuestas.")
	for i in range(list.size() - 1, maxi(-1, list.size() - 11), -1):
		var o: Dictionary = list[i]
		var st := ContractSim.status_label(str(o["status"]))
		if str(o.get("reason", "")) != "" and str(o["status"]) != "contraoferta":
			st += " (%s)" % o["reason"]
		elif str(o["status"]) == "contraoferta":
			st += " a %s c/u" % Fmt.money2(float(o["counter_price"]))
		body.add_child(_text("%s · %s · %d de %s a %s c/u · %s · %s" % [ContractSim.dir_label(ContractSim.dir_of(o)), o["client_name"], int(o["qty"]), TradeSim.good_label(str(o["good"])),
			Fmt.money2(float(o["unit_price"])), _freq_text(int(o.get("installments", 1)), int(o.get("period", 30))), st], 12))


func _purchases(gs) -> void:
	var list: Array = gs.market.get("purchase_offers", [])
	if list.is_empty():
		return
	_section("Ofertas de compra de empresas")
	for i in range(list.size() - 1, maxi(-1, list.size() - 6), -1):
		var o: Dictionary = list[i]
		body.add_child(_text("%s · ofreciste %s · %s" % [o.get("label", ""), Fmt.money(float(o["amount"])), ContractSim.status_label(str(o["status"])) if str(o["status"]) != "pendiente" else "esperando respuesta hasta el %s" % _date(int(o["reply_day"]))]))


func _reputation(gs) -> void:
	_section("Reputación por cliente")
	_note("Cumplir sube la reputación; incumplir la baja. Con buena reputación te piden más y pagan mejor.")
	for r in ContractSim.reputation_rows(gs):
		var v := float(r["rep"])
		var col := Color(0.5, 0.85, 0.5) if v >= 60.0 else (Color(0.95, 0.5, 0.45) if v < 40.0 else Color(0.9, 0.9, 0.9))
		body.add_child(UIKit.label("%s: %d/100" % [r["name"], int(v)], 13, col))
	var rel := ContractSim.reliability_rows(gs)
	if not rel.is_empty():
		_section("Fiabilidad de proveedores")
		for r in rel:
			body.add_child(UIKit.label("%s: %d/100" % [r["name"], int(float(r["rel"]))], 13))


func _history(gs) -> void:
	var closed: Array = ContractSim.contracts(gs).filter(func(k): return str(k["status"]) != "activo")
	_section("Contratos cerrados")
	if closed.is_empty():
		_note("Todavía no hay contratos cerrados.")
	for i in range(closed.size() - 1, maxi(-1, closed.size() - 11), -1):
		var k: Dictionary = closed[i]
		var who := ""
		if str(k.get("breached_by", "")) != "":
			who = " por %s" % ("ti" if str(k["breached_by"]) == "jugador" else "el proveedor")
		body.add_child(_text("%s · %s · %s · %d/%d entregas, %d incumplidas · %s%s · %s %s" % [ContractSim.dir_label(ContractSim.dir_of(k)), k["client_name"], TradeSim.good_label(str(k["good"])),
			int(k["done"]), int(k["installments"]), int(k["failed"]) + int(k.get("cp_failed", 0)), ContractSim.status_label(str(k["status"])), who,
			"pagado" if ContractSim.is_buy(k) else "cobrado", Fmt.money(float(k.get("paid", 0.0)))], 12, UIKit.TEXT_DIM))
