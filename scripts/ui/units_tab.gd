class_name UnitsTab
extends RefCounted
## Pestaña "Unidades" del panel de edificio (bienes raíces): ficha del proyecto, estado de las
## etapas, crédito constructor, preventas y la tabla de unidades donde se fija precio/renta y se
## pone cada unidad (o todas) en venta o arriendo. También inicia un proyecto de mejora por etapas.


static func applies(gs, b: Dictionary) -> bool:
	if not gs.owned_by_player(b) or not Housing.is_home(b):
		return false
	return RealEstateSim.has_units(b) or b.has("re_project") or RealEstateSim.is_multi_level(int(b["level"]) + 1)


static func _note(text: String) -> Label:
	var l := UIKit.label(text, 12, UIKit.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 380
	return l


static func build(gs, b: Dictionary, hud, on_change: Callable) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	if b.has("re_project"):
		v.add_child(_project_box(gs, b, hud, on_change))
	elif gs.is_active(b) and RealEstateSim.is_multi_level(int(b["level"]) + 1) and int(b["level"]) < GameData.max_level("vivienda"):
		v.add_child(_upgrade_box(gs, b, hud, on_change))
	if RealEstateSim.has_units(b):
		var lvl := int(b.get("target_level", b["level"]))
		var ficha := UIKit.rich()
		ficha.text = RealEstateSim.feasibility_text(RealEstateSim.feasibility(gs, lvl, str(b.get("tier", "normal")), str(b.get("re_project", {}).get("kind", "")) == "mejora", b))
		v.add_child(ficha)
		v.add_child(_units_table(gs, b, hud, on_change))
	return v


# --- Proyecto en obra -------------------------------------------------------------------------------

static func _project_box(gs, b: Dictionary, hud, on_change: Callable) -> Control:
	var v := VBoxContainer.new()
	var p: Dictionary = b["re_project"]
	var s := "[b]Proyecto en obra[/b] (%s) · %d%% · faltan ~%d días\n" % ["obra nueva" if str(p["kind"]) == "nuevo" else "mejora", int(100.0 * float(b["work_done"]) / maxf(1.0, float(b["work_needed"]))), ConstructionSim.days_left(gs, b)]
	var cur := RealEstateSim.stage_index(b)
	var stages: Array = p["stages"]
	for i in range(stages.size()):
		var st: Dictionary = stages[i]
		var mark := "[color=#6c6]✔ pagada[/color]" if bool(st["paid"]) else ("[color=#e9b949]en espera de pago[/color]" if i == cur else "pendiente")
		s += "• %s: %s — %s\n" % [st["label"], Fmt.money(float(st["amount"])), mark]
	if bool(b.get("paused", false)):
		s += "[color=#e66]OBRA PAUSADA: necesitas %s para la etapa de %s (lo avanzado se conserva).[/color]\n" % [Fmt.money(RealEstateSim.own_share(gs, b, cur)), str(stages[cur]["label"]).to_lower()]
	var l := LoanContract.find_loan(gs, int(p.get("credit_id", -1)))
	if not l.is_empty():
		s += "Crédito constructor (%s): cupo %s · desembolsado %s · saldo %s al %.1f%%\n" % [LoanContract.lender_label(gs, str(l["lender"])), Fmt.money(float(l["limit"])), Fmt.money(float(l["disbursed"])), Fmt.money(float(l["balance"])), float(l["rate"]) * 100.0]
	s += "Recibido en preventas: %s\n" % Fmt.money(float(p["presale_received"]))
	var rl := UIKit.rich()
	rl.text = s
	v.add_child(rl)
	v.add_child(_note("Preventa: marca unidades «En venta» y las familias pueden separarlas sobre planos (cuota inicial, cuotas durante la obra y el saldo al entregar, con ahorros o hipoteca)."))
	var cancel := UIKit.button("Cancelar proyecto (devuelve preventas)", func():
		hud.toast(RealEstateSim.cancel_project(GameState, b), "jugador")
		on_change.call())
	cancel.tooltip_text = "Lo pagado en etapas se pierde y el crédito sigue debiéndose. Una obra nueva se demuele; una mejora vuelve al nivel anterior."
	v.add_child(cancel)
	return v


# --- Proyecto de mejora --------------------------------------------------------------------------------

static func _upgrade_box(gs, b: Dictionary, hud, on_change: Callable) -> Control:
	var v := VBoxContainer.new()
	var next := int(b["level"]) + 1
	var tier := str(b.get("tier", "normal"))
	var f := RealEstateSim.feasibility(gs, next, tier, true)
	var rl := UIKit.rich()
	rl.text = "[b]Mejorar a %s como proyecto por etapas[/b]\n" % f["label"] + RealEstateSim.feasibility_text(f)
	v.add_child(rl)
	var sel := credit_selector(gs, float(f["cost_total"]))
	v.add_child(sel["control"])
	var reason := ConstructionSim.level_block_reason(gs, "vivienda", next)
	if reason == "":
		reason = ConstructionSim.upgrade_space_reason(gs, b, next)
	var btn := UIKit.button("Iniciar proyecto por etapas" if reason == "" else reason, func():
		var err := RealEstateSim.start_project_upgrade(GameState, b, sel["get"].call())
		hud.toast(err if err != "" else "Proyecto iniciado.", "jugador" if err != "" else "construccion")
		on_change.call())
	btn.disabled = reason != ""
	v.add_child(btn)
	return v


## Selector de crédito constructor: {control, get: Callable → opts}.
static func credit_selector(gs, total: float) -> Dictionary:
	var box := VBoxContainer.new()
	var row := HBoxContainer.new()
	box.add_child(row)
	row.add_child(UIKit.label("Crédito constructor:", 13))
	var opt := OptionButton.new()
	opt.add_item("Sin crédito (todo con tu dinero)")
	opt.set_item_metadata(0, "")
	for ld in LoanContract.lenders(gs):
		if str(ld["reason"]) != "":
			continue
		opt.add_item("%s · %.1f%%" % [ld["label"], (float(ld["rate"]) + float(RealEstateSim.cfg().get("constructor_credit", {}).get("spread", 0.0))) * 100.0])
		opt.set_item_metadata(opt.item_count - 1, str(ld["id"]))
	opt.fit_to_longest_item = false
	opt.custom_minimum_size.x = 180
	row.add_child(opt)
	var max_ratio := float(RealEstateSim.cfg().get("constructor_credit", {}).get("max_ratio", 0.6))
	var row2 := HBoxContainer.new()
	box.add_child(row2)
	row2.add_child(UIKit.label("% financiado por el banco:", 13))
	var info := UIKit.label("", 12, UIKit.TEXT_DIM)
	var ratio := UIKit.spin(0, max_ratio * 100.0, 5, 50, func(val): info.text = "Cupo: %s (se desembolsa por etapas; intereses solo sobre lo desembolsado)" % Fmt.money(total * val / 100.0), 80)
	row2.add_child(ratio)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.x = 380
	info.text = "Cupo: %s (se desembolsa por etapas; intereses solo sobre lo desembolsado)" % Fmt.money(total * 0.5)
	box.add_child(info)
	var getter := func() -> Dictionary:
		return {"credit_lender": str(opt.get_item_metadata(opt.selected)), "credit_ratio": ratio.value / 100.0}
	return {"control": box, "get": getter}


# --- Tabla de unidades -----------------------------------------------------------------------------------

static func _units_table(gs, b: Dictionary, hud, on_change: Callable) -> Control:
	var v := VBoxContainer.new()
	var c := RealEstateSim.counts(b)
	v.add_child(UIKit.label("Unidades: %d · disponibles %d · arrendadas %d · vendidas %d · preventa %d%s" % [int(c["total"]), int(c["disponible"]), int(c["arrendada"]), int(c["vendida"]), int(c["preventa"]),
		" · embargadas %d" % int(c["embargada"]) if int(c["embargada"]) > 0 else ""], 14, UIKit.ACCENT))
	v.add_child(UIKit.label("Arriendo cobrado este mes: %s · mes anterior: %s · ventas totales: %s" % [Fmt.money(BusinessSim.period_value(b, "month", "alquileres")), Fmt.money(BusinessSim.period_value(b, "last_month", "alquileres")), Fmt.money(BusinessSim.period_value(b, "total", "ventas"))], 12, UIKit.TEXT_DIM))
	var bulk := HFlowContainer.new()
	bulk.add_theme_constant_override("h_separation", 4)
	bulk.add_theme_constant_override("v_separation", 4)
	v.add_child(bulk)
	bulk.add_child(UIKit.button("Todas en arriendo", func():
		RealEstateSim.set_all(b, "for_rent", true)
		on_change.call()))
	bulk.add_child(UIKit.button("Ninguna en arriendo", func():
		RealEstateSim.set_all(b, "for_rent", false)
		on_change.call()))
	bulk.add_child(UIKit.button("Todas en venta", func():
		RealEstateSim.set_all(b, "for_sale", true)
		on_change.call()))
	bulk.add_child(UIKit.button("Ninguna en venta", func():
		RealEstateSim.set_all(b, "for_sale", false)
		on_change.call()))
	bulk.add_child(UIKit.button("Precios automáticos", func():
		RealEstateSim.reset_prices(GameState, b)
		on_change.call()))
	v.add_child(_note("Precio y renta sugeridos según nivel, calidad, época, demanda del pueblo y piso (los pisos altos valen más). Si cambias un valor queda fijo; «Precios automáticos» los vuelve a calcular. Venta = de contado, con hipoteca o, en obra, sobre planos."))
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 4)
	v.add_child(grid)
	for h in ["Unidad", "Precio", "Renta/mes", "Venta", "Arr."]:
		grid.add_child(UIKit.label(h, 12, UIKit.ACCENT))
	var units: Array = b["units"]
	for i in range(units.size()):
		var u: Dictionary = units[i]
		var st := str(u["status"])
		var who := ""
		match st:
			"arrendada":
				who = GameState.person_name(int(u["tenant_id"])) if not gs.is_player(int(u["tenant_id"])) else "uso propio"
			"vendida":
				who = GameState.person_name(int(u["owner_id"]))
			"preventa":
				var ps: Dictionary = u["presale"]
				who = "%s · pagado %s" % [GameState.person_name(int(ps.get("buyer_id", -1))), Fmt.money(float(ps.get("paid", 0.0)))]
		var info := UIKit.label("%s %s %dm² (%d)\n%s%s" % [u["code"], RealEstateSim.type_label(str(u["type"])).get_slice(" ", 0), int(u["area"]), int(u["capacity"]), RealEstateSim.status_label(st), (": " + who) if who != "" else ""], 11)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.custom_minimum_size.x = 150
		info.clip_text = true
		info.tooltip_text = "%s · piso %d · %s" % [RealEstateSim.type_label(str(u["type"])), int(u["floor"]), who]
		grid.add_child(info)
		var editable := st == "disponible"
		var idx := i
		var price := UIKit.spin(0, 100000000, 10, float(u["price"]), func(val): RealEstateSim.set_unit_terms(b, idx, val, -1.0), 88)
		price.editable = editable
		grid.add_child(price)
		var rent := UIKit.spin(0, 1000000, 0.5, float(u["rent"]), func(val): RealEstateSim.set_unit_terms(b, idx, -1.0, val), 72)
		rent.editable = editable or st == "arrendada"
		grid.add_child(rent)
		var sale := CheckBox.new()
		sale.button_pressed = bool(u.get("for_sale", false))
		sale.disabled = not editable
		sale.toggled.connect(func(on): u["for_sale"] = on)
		grid.add_child(sale)
		var arr := CheckBox.new()
		arr.button_pressed = bool(u.get("for_rent", false))
		arr.disabled = not editable
		arr.toggled.connect(func(on): u["for_rent"] = on)
		grid.add_child(arr)
	return v
