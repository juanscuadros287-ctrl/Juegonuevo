class_name LoanDialog
extends RefCounted
## "Pedir crédito": el jugador elige banco (externo, NPC o su fundación bancaria), monto,
## plazo y tipo de pago (francés, alemán, bullet o con gracia), ve el contrato con la tabla de
## amortización y lo firma. También muestra la tabla restante de un crédito ya firmado.


static func open(hud, on_signed: Callable) -> void:
	var m := UIKit.modal(hud.root, "Pedir crédito", Vector2(640, 0))
	var body: VBoxContainer = m["body"]
	var st := {"lender": BankSim.EXTERNAL, "type": "frances", "months": 24, "grace": 3,
		"amount": minf(2000.0 * GameState.price_level(), maxf(100.0, BankSim.credit_limit(GameState)))}
	var grid := GridContainer.new()
	grid.columns = 2
	body.add_child(grid)
	grid.add_child(UIKit.label("Banco:"))
	var bank_opt := OptionButton.new()
	for ld in LoanContract.lenders(GameState):
		var txt := "%s · %.1f%%" % [ld["label"], float(ld["rate"]) * 100.0]
		if str(ld["reason"]) != "":
			txt += " — " + str(ld["reason"])
		bank_opt.add_item(txt)
		bank_opt.set_item_metadata(bank_opt.item_count - 1, str(ld["id"]))
		bank_opt.set_item_disabled(bank_opt.item_count - 1, str(ld["reason"]) != "")
	grid.add_child(bank_opt)
	grid.add_child(UIKit.label("Tipo de pago:"))
	var type_opt := OptionButton.new()
	for t in LoanContract.TYPES:
		type_opt.add_item(LoanContract.type_label(t))
		type_opt.set_item_metadata(type_opt.item_count - 1, t)
	grid.add_child(type_opt)
	grid.add_child(UIKit.label("Monto:"))
	var amount := UIKit.spin(50, 10000000, 50, float(st["amount"]), func(_v): pass, 150)
	grid.add_child(amount)
	grid.add_child(UIKit.label("Plazo:"))
	var term_opt := OptionButton.new()
	for mo in LoanContract.cfg().get("terms_months", [12, 24, 60, 120]):
		term_opt.add_item("%d meses" % int(mo))
		term_opt.set_item_metadata(term_opt.item_count - 1, int(mo))
		if int(mo) == 24:
			term_opt.select(term_opt.item_count - 1)
	grid.add_child(term_opt)
	var grace_lbl := UIKit.label("Meses de gracia:")
	grid.add_child(grace_lbl)
	var grace := UIKit.spin(1, 60, 1, 3, func(_v): pass, 90)
	grid.add_child(grace)
	var contract := UIKit.rich(Vector2(600, 0))
	var sb := UIKit.scroll_box(Vector2(600, 300))
	sb["box"].add_child(contract)
	body.add_child(sb["scroll"])
	var row := HBoxContainer.new()
	body.add_child(row)
	var sign := UIKit.button("Firmar", func(): pass, 140)
	row.add_child(sign)
	row.add_child(UIKit.button("Cancelar", func(): m["root"].queue_free(), 140))
	var update := func() -> void:
		st["lender"] = str(bank_opt.get_item_metadata(bank_opt.selected))
		st["type"] = str(type_opt.get_item_metadata(type_opt.selected))
		st["months"] = int(term_opt.get_item_metadata(term_opt.selected))
		st["amount"] = amount.value
		st["grace"] = int(grace.value)
		grace.visible = st["type"] == "gracia"
		grace_lbl.visible = grace.visible
		var q := LoanContract.quote(GameState, st["lender"], st["amount"], st["months"], st["type"], st["grace"])
		contract.text = contract_text(q)
		sign.disabled = str(q.get("error", "")) != ""
	bank_opt.item_selected.connect(func(_i): update.call())
	type_opt.item_selected.connect(func(_i): update.call())
	term_opt.item_selected.connect(func(_i): update.call())
	amount.value_changed.connect(func(_v): update.call())
	grace.value_changed.connect(func(_v): update.call())
	sign.pressed.connect(func():
		var r := LoanContract.sign_player_loan(GameState, st["lender"], st["amount"], st["months"], st["type"], st["grace"])
		hud.toast(str(r["error"]) if r.has("error") else "Crédito firmado.", "jugador" if r.has("error") else "importante")
		if not r.has("error"):
			m["root"].queue_free()
			on_signed.call())
	update.call()
	m["root"].visible = true


static func contract_text(q: Dictionary) -> String:
	if q.has("error") and not q.has("rows"):
		return "[color=#e66]%s[/color]" % q["error"]
	var t: Dictionary = q["totals"]
	var s := "[b]Contrato de crédito[/b]\n"
	s += "Banco: %s · Tasa: %.2f%% anual (%.3f%% mensual)\n" % [q["label"], float(q["rate"]) * 100.0, float(q["rate"]) * 100.0 / 12.0]
	s += "Monto: %s · Plazo: %d meses · %s%s\n" % [Fmt.money(float(q["amount"])), int(q["months"]), LoanContract.type_label(str(q["type"])),
		" (%d meses de gracia)" % int(q["grace"]) if str(q["type"]) == "gracia" else ""]
	s += "[color=#aaa]%s[/color]\n" % LoanContract.type_desc(str(q["type"]))
	s += "Primera cuota: %s · Cuota máxima: %s · Intereses totales: %s · Total a pagar: %s\n" % [Fmt.money2(float(t["first"])), Fmt.money2(float(t["max"])), Fmt.money(float(t["interest"])), Fmt.money(float(t["payment"]))]
	if str(q.get("error", "")) != "":
		s += "[color=#e66]%s[/color]\n" % q["error"]
	s += "Si no pagas una cuota hay recargo por mora; con 3 cuotas impagas, el banco embarga tus propiedades.\n\n"
	s += schedule_table(q["rows"])
	return s


static func schedule_table(rows: Array) -> String:
	var s := "[table=5][cell][b]Mes[/b][/cell][cell][b]Cuota[/b][/cell][cell][b]Interés[/b][/cell][cell][b]Capital[/b][/cell][cell][b]Saldo[/b][/cell]"
	var show := []
	if rows.size() <= 36:
		show = rows
	else:
		show = rows.slice(0, 24) + [{}] + rows.slice(rows.size() - 6)
	for row in show:
		if row.is_empty():
			s += "[cell]…[/cell][cell][/cell][cell][/cell][cell][/cell][cell][/cell]"
			continue
		s += "[cell]%d[/cell][cell]%s[/cell][cell]%s[/cell][cell]%s[/cell][cell]%s[/cell]" % [int(row["n"]), Fmt.money2(float(row["payment"])), Fmt.money2(float(row["interest"])), Fmt.money2(float(row["principal"])), Fmt.money(float(row["balance"]))]
	return s + "[/table]"


## Tabla restante de un crédito firmado.
static func show_schedule(hud, l: Dictionary) -> void:
	var m := UIKit.modal(hud.root, "Tabla de amortización", Vector2(620, 0))
	var rl := UIKit.rich(Vector2(580, 0))
	rl.text = "%s · %s · saldo %s al %.2f%%\n\n%s" % [LoanContract.lender_label(GameState, str(l["lender"])), LoanContract.type_label(str(l.get("type", ""))),
		Fmt.money(float(l["balance"])), float(l["rate"]) * 100.0, schedule_table(LoanContract.remaining_schedule(l))]
	var sb := UIKit.scroll_box(Vector2(600, 360))
	sb["box"].add_child(rl)
	m["body"].add_child(sb["scroll"])
	m["body"].add_child(UIKit.button("Cerrar", func(): m["root"].queue_free()))
	m["root"].visible = true
