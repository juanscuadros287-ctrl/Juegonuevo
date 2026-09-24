class_name ContractsPanel
extends VBoxContainer
## Panel "Contratos" (libre mercado): bandeja de solicitudes entrantes (Aceptar/Rechazar),
## ofertas que envías a pueblos, empresas NPC o al gobierno, contratos activos con entrega
## manual o automática, reputación por cliente y ofertas de compra de empresas NPC.

signal closed
signal message(text: String, category: String)

var hud: Hud
var body: VBoxContainer
var client_opt: OptionButton
var good_opt: OptionButton
var qty_spin: SpinBox
var price_spin: SpinBox
var ref_label: Label
var _clients: Array = []
var _goods: Array = []
var sel_client := ""
var sel_good := ""
var qty := 20.0
var price := 0.0


func setup(p_hud: Hud) -> void:
	hud = p_hud
	add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	add_child(head)
	var t := UIKit.label("Contratos", 20, UIKit.ACCENT)
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
		if ok_text != "":
			message.emit(ok_text, "negocio")
	else:
		message.emit(err, "jugador")
	refresh()


func _section(title: String) -> void:
	body.add_child(HSeparator.new())
	body.add_child(UIKit.label(title, 16, UIKit.ACCENT))


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


func refresh() -> void:
	if body == null:
		return
	UIKit.clear(body)
	var gs := GameState
	if gs.market.is_empty():
		return
	var mine := ContractSim.player_goods(gs)
	var s := "Produces: %s" % (", ".join(mine.keys().map(func(g): return TradeSim.good_label(str(g)))) if not mine.is_empty() else "nada todavía")
	body.add_child(_text(s, 13, UIKit.TEXT_DIM))
	_note("Solo te llegan solicitudes de bienes que produce alguno de tus negocios. Lo que no cubres lo compran a otros (libre mercado).")
	_inbox(gs)
	_active(gs)
	_offer_form(gs)
	_sent(gs)
	_purchases(gs)
	_reputation(gs)
	_history(gs)


func _inbox(gs) -> void:
	_section("Bandeja de entrada (%d)" % ContractSim.inbox(gs).size())
	if ContractSim.inbox(gs).is_empty():
		_note("No hay solicitudes. Llegan de pueblos con ruta comercial, de empresas NPC y del gobierno.")
	for r in ContractSim.inbox(gs):
		var inst := int(r.get("installments", 1))
		var when := "entrega única, plazo %d días" % int(r["deadline_days"]) if inst <= 1 else "cada mes por %d meses" % inst
		var t := "[%s] %d de %s a %s c/u (total %s) · %s · penalidad %s · vence %s · tienes %d" % [r["client_name"], int(r["qty"]), TradeSim.good_label(str(r["good"])),
			Fmt.money2(float(r["unit_price"])), Fmt.money(float(r["unit_price"]) * float(r["qty"]) * inst), when, Fmt.money(float(r["penalty"])), _date(int(r["expires_day"])),
			int(ContractSim.available(gs, str(r["good"])))]
		body.add_child(_text(t))
		var row := HBoxContainer.new()
		var id := int(r["id"])
		row.add_child(UIKit.button("Aceptar", func(): _result("", ContractSim.accept_request(GameState, id))))
		row.add_child(UIKit.button("Rechazar", func(): _result("", ContractSim.reject_request(GameState, id))))
		body.add_child(row)


func _active(gs) -> void:
	var list := ContractSim.active_contracts(gs)
	_section("Contratos activos (%d)" % list.size())
	if list.is_empty():
		_note("Sin contratos firmados.")
	for k in list:
		var inst := int(k["installments"])
		var t := "%s · %d de %s a %s c/u · %s · próxima entrega antes del %s · penalidad %s" % [k["client_name"], int(k["qty"]), TradeSim.good_label(str(k["good"])),
			Fmt.money2(float(k["unit_price"])), "entrega única" if inst <= 1 else "cuota %d/%d" % [int(k["done"]) + int(k["failed"]) + 1, inst],
			_date(int(k["next_due"])), Fmt.money(float(k["penalty"]))]
		body.add_child(_text(t))
		var row := HBoxContainer.new()
		var id := int(k["id"])
		var why := ContractSim.deliver_block_reason(gs, k)
		var b := UIKit.button("Entregar", func(): _result(ContractSim.deliver(GameState, id), "Entrega despachada."))
		b.disabled = why != ""
		b.tooltip_text = why
		row.add_child(b)
		var auto := CheckBox.new()
		auto.text = "Entrega automática"
		auto.button_pressed = bool(k.get("auto", false))
		var kk: Dictionary = k
		auto.toggled.connect(func(on): kk["auto"] = on)
		row.add_child(auto)
		body.add_child(row)
		if why != "":
			_note(why)


func _offer_form(gs) -> void:
	_section("Ofrecer venta")
	_clients = ContractSim.client_keys(gs)
	var goods := ContractSim.player_goods(gs).duplicate()
	for g in WarehouseSim.all_stock(gs):
		if float(WarehouseSim.all_stock(gs)[g]) >= 1.0:
			goods[str(g)] = true
	_goods = goods.keys()
	_goods.sort()
	if _goods.is_empty():
		_note("Necesitas producir algo o tener existencias para ofrecer.")
		return
	if not _clients.has(sel_client):
		sel_client = str(_clients[0])
	if not _goods.has(sel_good):
		sel_good = str(_goods[0])
	var row := HBoxContainer.new()
	row.add_child(UIKit.label("Cliente:", 13))
	client_opt = OptionButton.new()
	for i in range(_clients.size()):
		client_opt.add_item(ContractSim.client_name(gs, str(_clients[i])), i)
	client_opt.selected = _clients.find(sel_client)
	client_opt.item_selected.connect(_on_client)
	client_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(client_opt)
	body.add_child(row)
	var row2 := HBoxContainer.new()
	row2.add_child(UIKit.label("Bien:", 13))
	good_opt = OptionButton.new()
	for i in range(_goods.size()):
		good_opt.add_item("%s (tienes %d)" % [TradeSim.good_label(str(_goods[i])), int(ContractSim.available(gs, str(_goods[i])))], i)
	good_opt.selected = _goods.find(sel_good)
	good_opt.item_selected.connect(_on_good)
	good_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(good_opt)
	body.add_child(row2)
	var row3 := HBoxContainer.new()
	row3.add_child(UIKit.label("Cantidad:", 13))
	qty_spin = UIKit.spin(1, 5000, 1, qty, func(v): qty = v, 90)
	row3.add_child(qty_spin)
	row3.add_child(UIKit.label("Precio c/u:", 13))
	if price <= 0.0:
		price = snappedf(ContractSim.reference_price(gs, sel_client, sel_good, qty), 0.01)
	price_spin = UIKit.spin(0.01, 100000, 0.01, price, func(v): price = v, 100)
	row3.add_child(price_spin)
	body.add_child(row3)
	ref_label = UIKit.label("", 12, UIKit.TEXT_DIM)
	body.add_child(ref_label)
	_update_ref()
	body.add_child(UIKit.button("Enviar oferta", func():
		_result(ContractSim.send_offer(GameState, sel_client, sel_good, qty, price), "Oferta enviada a %s: responderá en unos días." % ContractSim.client_name(GameState, sel_client))))


func _on_client(i: int) -> void:
	sel_client = str(_clients[i])
	_update_ref()


func _on_good(i: int) -> void:
	sel_good = str(_goods[i])
	_update_ref()


func _update_ref() -> void:
	if ref_label == null:
		return
	var gs := GameState
	var ref := ContractSim.reference_price(gs, sel_client, sel_good, qty)
	var extra := ""
	if ContractSim.client_kind(sel_client) == "town":
		var tq := TradeSim.transport_quote(gs, ContractSim.client_ref(sel_client), qty)
		extra = " · flete ~%s (%d días)" % [Fmt.money(float(tq["cost"])), int(tq["days"])]
	ref_label.text = "Precio de referencia: %s c/u · reputación %d/100%s" % [Fmt.money2(ref), int(ContractSim.reputation(gs, sel_client)), extra]
	if price_spin != null:
		price = snappedf(ref, 0.01)
		price_spin.set_value_no_signal(price)


func _sent(gs) -> void:
	var list: Array = ContractSim.sent(gs)
	_section("Ofertas enviadas")
	if list.is_empty():
		_note("Aún no has enviado ofertas.")
	for i in range(list.size() - 1, maxi(-1, list.size() - 9), -1):
		var o: Dictionary = list[i]
		var st := ContractSim.status_label(str(o["status"]))
		if str(o.get("reason", "")) != "":
			st += " (%s)" % o["reason"]
		body.add_child(_text("%s · %d de %s a %s c/u · %s" % [o["client_name"], int(o["qty"]), TradeSim.good_label(str(o["good"])), Fmt.money2(float(o["unit_price"])), st]))


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


func _history(gs) -> void:
	var closed: Array = ContractSim.contracts(gs).filter(func(k): return str(k["status"]) != "activo")
	if closed.is_empty():
		return
	_section("Historial")
	for i in range(closed.size() - 1, maxi(-1, closed.size() - 9), -1):
		var k: Dictionary = closed[i]
		body.add_child(_text("%s · %s · %d entregas, %d incumplidas · %s · cobrado %s" % [k["client_name"], TradeSim.good_label(str(k["good"])), int(k["done"]), int(k["failed"]), ContractSim.status_label(str(k["status"])), Fmt.money(float(k.get("paid", 0.0)))], 12, UIKit.TEXT_DIM))
