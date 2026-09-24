class_name BuildingPanel
extends VBoxContainer
## Gestión de un edificio: resumen financiero, empleados (contratación manual),
## precio, vivienda (renta/venta/vivir aquí/interior) y mejora de nivel.

signal message(text: String, category: String)
signal closed

var hud: Hud
var bid := -1
var title: Label
var tabs: TabContainer
var summary: RichTextLabel
var hire_modal: Dictionary
var hire_box: VBoxContainer
var _name_edit: LineEdit


func setup(p_hud: Hud) -> void:
	hud = p_hud
	add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	add_child(head)
	title = UIKit.label("", 20, UIKit.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	head.add_child(title)
	head.add_child(UIKit.button("✕", func(): closed.emit(), 32))
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(tabs)
	hire_modal = UIKit.modal(hud.root, "Contratar personal", Vector2(720, 0))
	var sb := UIKit.scroll_box(Vector2(680, 440))
	hire_box = sb["box"]
	hire_modal["body"].add_child(sb["scroll"])
	hire_modal["body"].add_child(UIKit.button("Cerrar", func(): hire_modal["root"].visible = false))


func open(id: int) -> void:
	bid = id
	rebuild()


func _b() -> Dictionary:
	return GameState.get_building(bid)


func rebuild() -> void:
	UIKit.clear(tabs)
	var b := _b()
	if b.is_empty():
		closed.emit()
		return
	title.text = GameState.building_label(b)
	var def: Dictionary = GameState.building_def(b)
	var mine := GameState.owned_by_player(b)
	var cat := str(def.get("category", ""))
	_add_tab("Resumen", _summary_tab(b, mine))
	if mine and cat == "negocio":
		_add_tab("Empleados", _employees_tab(b))
		if str(def.get("product", "")) not in ["", "construccion", "credito"]:
			_add_tab("Precio", _price_tab(b))
		if BankSim.is_bank(b):
			_add_tab("Banco", _bank_tab(b))
	if cat == "vivienda":
		_add_tab("Vivienda", _home_tab(b, mine))
	if mine:
		_add_tab("Mejorar", _upgrade_tab(b))
	refresh()


func _add_tab(name: String, content: Control) -> void:
	var sc := ScrollContainer.new()
	sc.name = name
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(content)
	tabs.add_child(sc)


func _msg(text: String, cat := "info") -> void:
	if text != "":
		message.emit(text, cat)


# --- Resumen ------------------------------------------------------------------------------

func _summary_tab(b: Dictionary, mine: bool) -> Control:
	var v := VBoxContainer.new()
	summary = UIKit.rich()
	summary.meta_clicked.connect(hud.on_meta_clicked)
	v.add_child(summary)
	if mine:
		var row := HBoxContainer.new()
		_name_edit = LineEdit.new()
		_name_edit.placeholder_text = "Nombre"
		_name_edit.text = str(b.get("name", ""))
		_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(_name_edit)
		row.add_child(UIKit.button("Renombrar", func():
			_b()["name"] = _name_edit.text.strip_edges()
			rebuild()))
		v.add_child(row)
		var del := UIKit.button("Demoler", func():
			ConstructionSim.demolish(GameState, _b())
			closed.emit())
		del.tooltip_text = "Elimina el edificio sin reembolso."
		v.add_child(del)
		if b["status"] == "cerrado":
			v.add_child(UIKit.button("Reabrir (%s)" % Fmt.money(BusinessSim.reopen_cost(GameState, b)), func():
				_msg(BusinessSim.reopen(GameState, _b()), "jugador")
				rebuild()))
	if Housing.is_home(b) and b["status"] != "construccion":
		v.add_child(UIKit.button("Ver interior", func(): EventBus.interior_requested.emit(bid)))
	return v


func refresh() -> void:
	var b := _b()
	if b.is_empty() or summary == null:
		return
	summary.text = _summary_text(b)


func _summary_text(b: Dictionary) -> String:
	var def: Dictionary = GameState.building_def(b)
	var ld: Dictionary = GameState.level_def(b)
	var s := "[b]%s[/b] · nivel %d/%d" % [ld.get("label", ""), int(b["level"]), GameData.max_level(b["type"])]
	if Housing.is_home(b):
		s += " · calidad %s" % Housing.tier_label(str(b.get("tier", "normal")))
	s += "\n"
	var owner := str(b.get("owner", ""))
	var owner_txt := "Tú" if owner == "jugador" else ("El pueblo" if owner == "pueblo" else GameState.person_name(int(b.get("owner_id", -1))))
	s += "Propietario: %s\n" % owner_txt
	if def.get("category", "") == "negocio":
		s += "Sector: %s · Tipo legal: %s\n" % [def.get("sector", ""), GameData.legal_types.get(str(b.get("legal", "sas")), {}).get("label", "")]
	match str(b["status"]):
		"construccion":
			s += "[color=#e9b949]En construcción: %d%%[/color]\n" % int(100.0 * float(b["work_done"]) / maxf(1.0, float(b["work_needed"])))
		"mejorando":
			s += "[color=#e9b949]En obras de mejora: %d%% (no factura)[/color]\n" % int(100.0 * float(b["work_done"]) / maxf(1.0, float(b["work_needed"])))
		"cerrado":
			s += "[color=#e66]CERRADO (quiebra o embargo)[/color]\n"
		_:
			s += "Estado: [color=#6c6]activo[/color]\n"
	var site_crew := 0
	for c in GameState.employees_of(bid):
		if c.job_kind == "obra":
			site_crew += 1
	if site_crew > 0:
		s += "Trabajadores en obra: %d/%d\n" % [site_crew, int(GameData.level_def(b["type"], int(b["target_level"])).get("workers", 0))]
	if def.get("category", "") == "negocio":
		var emp := 0
		for c in GameState.employees_of(bid):
			if c.job_kind == "empleo":
				emp += 1
		s += "Empleados: %d/%d\n" % [emp, int(ld.get("jobs", 0))]
		var product := str(def.get("product", ""))
		if product == "construccion":
			s += "Capacidad de obra: %.1f trabajadores-día/día\n" % BusinessSim.expected_output(GameState, b)
		elif product != "":
			s += "Producción: %.1f %s/día · Inventario: %.1f\n" % [BusinessSim.expected_output(GameState, b), GameData.good_label(product), float(b["inventory"].get(product, 0.0))]
			s += "Precio: %s · Calidad: %.1f\n" % [Fmt.money2(float(b["price"])), float(ld.get("quality", 1.0))]
	if Housing.is_home(b):
		var res := GameState.residents_of(bid)
		s += "Ocupación: %d/%d · Renta: %s/persona/mes\n" % [res.size(), GameState.building_capacity(b), Fmt.money(float(b["rent"]))]
		s += "Interior: [color=#aaa]%s[/color]\n" % Housing.interior_summary(GameState, b)
	if GameState.owned_by_player(b):
		s += "\n[b]Finanzas[/b]\n"
		for period in [["month", "Este mes"], ["last_month", "Mes anterior"], ["total", "Total"]]:
			var inc := BusinessSim.period_value(b, period[0], "ventas") + BusinessSim.period_value(b, period[0], "alquileres")
			var profit := BusinessSim.period_profit(b, period[0])
			var col := "#6c6" if profit >= 0 else "#e66"
			s += "%s: ingresos %s · [color=%s]resultado %s[/color]\n" % [period[1], Fmt.money(inc), col, Fmt.money(profit)]
		var m: Dictionary = b["ledger"].get("last_month", {})
		if not m.is_empty():
			var parts := []
			for k in BusinessSim.LEDGER_KEYS:
				if m.has(k):
					parts.append("%s %s" % [k, Fmt.money(float(m[k]))])
			s += "[color=#aaa]Mes anterior: %s[/color]\n" % ", ".join(parts)
		s += "Inversión en obras: %s\n" % Fmt.money(BusinessSim.period_value(b, "total", "obras"))
		if BusinessSim.is_nonprofit(b):
			s += "Reserva de la fundación: %s\n" % Fmt.money(float(b["reserve"]))
		if BusinessSim.is_business(b):
			s += "Clasificación: [b]%s[/b]" % EconomySim.classify(b)
			if int(b.get("loss_months", 0)) > 0:
				s += " · [color=#e66]%d meses con pérdidas[/color]" % int(b["loss_months"])
			s += "\n"
	return s


# --- Empleados ------------------------------------------------------------------------------

func _employees_tab(b: Dictionary) -> Control:
	var v := VBoxContainer.new()
	var skill := str(GameState.building_def(b).get("skill", ""))
	v.add_child(UIKit.label("Habilidad clave: %s" % GameData.skill_label(skill), 14, UIKit.TEXT_DIM))
	for c in GameState.employees_of(bid):
		if c.job_kind != "empleo":
			continue
		var row := HBoxContainer.new()
		var info := UIKit.label("%s · %s %d · exp %.1f · %s/día" % [c.full_name(), GameData.skill_label(skill).substr(0, 4), int(c.skills.get(skill, 0)), c.experience, Fmt.money2(c.wage)], 13)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.tooltip_text = "Pide %s/día · Felicidad %d%%" % [Fmt.money2(BusinessSim.asked_wage(GameState, c, b["type"])), int(c.happiness)]
		row.add_child(info)
		var cid: int = c.id
		row.add_child(UIKit.button("−", func(): _change_wage(cid, -0.1), 28))
		row.add_child(UIKit.button("+", func(): _change_wage(cid, 0.1), 28))
		row.add_child(UIKit.button("Despedir", func():
			BusinessSim.fire(GameState, GameState.citizens[cid], "Despediste a %s." % GameState.citizens[cid].full_name())
			rebuild()))
		v.add_child(row)
	v.add_child(UIKit.button("Contratar…", _open_hire))
	return v


func _change_wage(cid: int, delta: float) -> void:
	if GameState.citizens.has(cid):
		var c: Citizen = GameState.citizens[cid]
		c.wage = maxf(0.1, snappedf(c.wage + delta, 0.05))
		rebuild()
		tabs.current_tab = 1


func _open_hire() -> void:
	UIKit.clear(hire_box)
	var b := _b()
	var skill := str(GameState.building_def(b).get("skill", ""))
	hire_box.add_child(UIKit.label("Candidatos (ordenados por %s + experiencia). Salario pedido por día:" % GameData.skill_label(skill), 14, UIKit.TEXT_DIM))
	var today := GameState.today()
	var shown := 0
	for c in BusinessSim.candidates(GameState, b):
		if shown >= 40:
			break
		shown += 1
		var asked := BusinessSim.asked_wage(GameState, c, b["type"])
		var row := HBoxContainer.new()
		var status := " · jornalero" if c.job_kind == "obra" else ""
		var info := UIKit.label("%s, %d años · %s %d · exp %.1f · %s · pide %s%s" % [c.full_name(), c.age_years(today), GameData.skill_label(skill), int(c.skills.get(skill, 0)), c.experience, GameData.education_label(c.education), Fmt.money2(asked), status], 13)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var cid: int = c.id
		row.add_child(UIKit.button("Contratar", func():
			var err := BusinessSim.hire(GameState, _b(), GameState.citizens[cid], asked)
			_msg(err, "jugador")
			hire_modal["root"].visible = false
			rebuild()
			tabs.current_tab = 1))
		hire_box.add_child(row)
	if shown == 0:
		hire_box.add_child(UIKit.label("No hay candidatos disponibles."))
	hire_modal["root"].visible = true


# --- Precio ------------------------------------------------------------------------------------

func _price_tab(b: Dictionary) -> Control:
	var v := VBoxContainer.new()
	var def: Dictionary = GameState.building_def(b)
	var g: Dictionary = GameData.goods.get(str(def.get("product", "")), {})
	var product := str(def.get("product", ""))
	var ref := EconomySim.market_price(GameState, product)
	var f := EconomySim.good_factor(GameState, product)
	v.add_child(UIKit.label("Mercado de %s: %s (%s)" % [GameData.good_label(product), Fmt.money2(ref), "escasez" if f > 1.08 else ("exceso de oferta" if f < 0.92 else "normal")], 14))
	var auto := CheckBox.new()
	auto.text = "Precio automático según el mercado"
	auto.button_pressed = bool(b.get("auto_price", false))
	auto.toggled.connect(func(on): _b()["auto_price"] = on)
	v.add_child(auto)
	var mk := HBoxContainer.new()
	mk.add_child(UIKit.label("Margen sobre mercado (%):"))
	mk.add_child(UIKit.spin(-50, 200, 1, float(b.get("markup", 0.0)) * 100.0, func(val): _b()["markup"] = val / 100.0))
	v.add_child(mk)
	var t := UIKit.label("Precio de referencia: %s. Los clientes pagan hasta %s; por encima del de referencia compran menos. Si no compran a ti, se autoabastecen o importan." % [Fmt.money2(ref), Fmt.money2(ref * float(GameData.citizens.get("willing_markup", 1.6)))], 13, UIKit.TEXT_DIM)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = 380
	v.add_child(t)
	var row := HBoxContainer.new()
	row.add_child(UIKit.label("Precio por unidad:"))
	row.add_child(UIKit.spin(0.01, BusinessSim.max_price(GameState, b), 0.01, float(b["price"]), func(val): BusinessSim.set_price(GameState, _b(), val)))
	v.add_child(row)
	if BusinessSim.is_nonprofit(b):
		v.add_child(UIKit.label("Fundación: precio máximo = precio base.", 13, UIKit.TEXT_DIM))
	return v


# --- Vivienda ----------------------------------------------------------------------------------

func _home_tab(b: Dictionary, mine: bool) -> Control:
	var v := VBoxContainer.new()
	var res := GameState.residents_of(bid)
	v.add_child(UIKit.label("Residentes (%d/%d):" % [res.size(), GameState.building_capacity(b)], 15))
	var rl := UIKit.rich()
	rl.meta_clicked.connect(hud.on_meta_clicked)
	var txt := ""
	for c in res:
		txt += "• %s (%d)\n" % [hud.link(c.id), c.age_years(GameState.today())]
	rl.text = txt if txt != "" else "Vacía\n"
	v.add_child(rl)
	v.add_child(UIKit.button("Ver interior", func(): EventBus.interior_requested.emit(bid)))
	if not mine:
		return v
	var rent_row := HBoxContainer.new()
	rent_row.add_child(UIKit.label("Renta por persona/mes:"))
	rent_row.add_child(UIKit.spin(0, 1000, 0.5, float(b["rent"]), func(val): _b()["rent"] = val))
	v.add_child(rent_row)
	var sale := CheckBox.new()
	sale.text = "En venta"
	sale.button_pressed = bool(b.get("for_sale", false))
	sale.toggled.connect(func(on): _b()["for_sale"] = on)
	var sale_row := HBoxContainer.new()
	sale_row.add_child(sale)
	sale_row.add_child(UIKit.label("Precio:"))
	sale_row.add_child(UIKit.spin(0, 1000000, 10, float(b["sale_price"]), func(val): _b()["sale_price"] = val, 130))
	v.add_child(sale_row)
	var note := UIKit.label("Las familias alquilan o compran cada mes según su dinero, calidad y precio. Renta y venta dependen del nivel y la calidad (normal/media/alta).", 12, UIKit.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 380
	v.add_child(note)
	var p := GameState.player_citizen()
	if p != null and p.home_id != bid:
		v.add_child(UIKit.button("Vivir aquí (mudarme con mi familia)", func():
			_msg(PlayerSim.move_home(GameState, _b()))
			rebuild()))
	return v


# --- Mejorar ------------------------------------------------------------------------------------

func _upgrade_tab(b: Dictionary) -> Control:
	var v := VBoxContainer.new()
	var next := int(b["level"]) + 1
	var nd := GameData.level_def(b["type"], next)
	if next > GameData.max_level(b["type"]):
		v.add_child(UIKit.label("Nivel máximo alcanzado."))
	else:
		var cost := ConstructionSim.cost_for(GameState, b["type"], next, true, str(b.get("tier", "normal")))
		var cur: Dictionary = GameState.level_def(b)
		var t := "[b]Siguiente nivel: %s[/b]\n" % nd.get("label", "")
		t += "Costo: %s (incluye %s de materiales importados)\n" % [Fmt.money(cost["total"]), Fmt.money(cost["import_cost"])]
		t += "Obra: %d días con %d trabajadores. [color=#e9b949]Durante la obra no factura.[/color]\n" % [cost["days"], cost["workers"]]
		if nd.has("jobs"):
			t += "Empleos: %d → %d · Producción/empleado: %.1f → %.1f · Calidad: %.1f → %.1f\n" % [int(cur.get("jobs", 0)), int(nd["jobs"]), float(cur.get("prod_per_worker", 0)), float(nd.get("prod_per_worker", 0)), float(cur.get("quality", 1)), float(nd.get("quality", 1))]
		if nd.has("capacity"):
			t += "Capacidad: %d → %d personas\n" % [int(cur.get("capacity", 0)), int(nd["capacity"])]
		if nd.has("business_slots"):
			t += "Límite de negocios: +%d → +%d\n" % [int(cur.get("business_slots", 0)), int(nd["business_slots"])]
		var reason := ConstructionSim.level_block_reason(GameState, b["type"], next)
		if reason != "":
			t += "[color=#e66]%s[/color]\n" % reason
		var rl := UIKit.rich()
		rl.text = t
		v.add_child(rl)
		var btn := UIKit.button("Mejorar", func():
			_msg(ConstructionSim.start_upgrade(GameState, _b()), "jugador")
			rebuild())
		btn.disabled = reason != "" or not GameState.is_active(b)
		v.add_child(btn)
	if Housing.is_home(b):
		v.add_child(HSeparator.new())
		var rc := ConstructionSim.renovation_cost(GameState, b)
		if rc.is_empty():
			v.add_child(UIKit.label("Calidad máxima (alta)."))
		else:
			v.add_child(UIKit.label("Remodelar a calidad %s: %s · %d días" % [Housing.tier_label(rc["tier"]), Fmt.money(rc["total"]), rc["days"]], 14))
			var rb := UIKit.button("Remodelar", func():
				_msg(ConstructionSim.start_renovation(GameState, _b()), "jugador")
				rebuild())
			rb.disabled = not GameState.is_active(b)
			v.add_child(rb)
	return v


# --- Banco ------------------------------------------------------------------------------------------

func _bank_tab(b: Dictionary) -> Control:
	BankSim.bank_settings(GameState, b)
	var v := VBoxContainer.new()
	var loans := BankSim.bank_loans(GameState, b)
	var outstanding := 0.0
	var late := 0
	for l in loans:
		outstanding += float(l["balance"])
		if int(l["missed"]) > 0:
			late += 1
	var t := "Préstamos activos: %d/%d (capacidad según empleados)\n" % [loans.size(), BankSim.bank_capacity(GameState, b)]
	t += "Cartera: %s · En mora: %d\n" % [Fmt.money(outstanding), late]
	t += "Intereses cobrados (total): %s · Incobrables: %s\n" % [Fmt.money(BusinessSim.period_value(b, "total", "intereses")), Fmt.money(BusinessSim.period_value(b, "total", "incobrables"))]
	var rl := UIKit.rich()
	rl.text = t
	v.add_child(rl)
	var lend := CheckBox.new()
	lend.text = "Otorgar préstamos a ciudadanos"
	lend.button_pressed = bool(b["lending"])
	lend.toggled.connect(func(on): _b()["lending"] = on)
	v.add_child(lend)
	var r1 := HBoxContainer.new()
	r1.add_child(UIKit.label("Tasa de interés anual (%):"))
	r1.add_child(UIKit.spin(0, 80, 0.5, float(b["loan_rate"]) * 100.0, func(val): _b()["loan_rate"] = val / 100.0))
	v.add_child(r1)
	var r2 := HBoxContainer.new()
	r2.add_child(UIKit.label("Préstamo máximo:"))
	r2.add_child(UIKit.spin(10, 1000000, 10, float(b["max_loan"]), func(val): _b()["max_loan"] = val, 130))
	v.add_child(r2)
	var note := UIKit.label("Tasas altas: más morosidad, pobreza y menos consumo. Tasas bajas: más préstamos y consumo (clientes para tus negocios) pero más riesgo de impago. El dinero prestado sale de tu capital.", 12, UIKit.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 380
	v.add_child(note)
	var list := ""
	for l in loans.slice(0, 20):
		list += "• %s: saldo %s, %s%s\n" % [hud.link(int(l["borrower"])), Fmt.money(float(l["balance"])), l["purpose"], " [color=#e66](mora %d)[/color]" % int(l["missed"]) if int(l["missed"]) > 0 else ""]
	var ll := UIKit.rich()
	ll.meta_clicked.connect(hud.on_meta_clicked)
	ll.text = list
	v.add_child(ll)
	return v
