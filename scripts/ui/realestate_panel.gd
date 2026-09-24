class_name RealEstatePanel
extends VBoxContainer
## Panel "Bienes raíces": tus proyectos y edificios por unidades (estado de cada unidad,
## arriendos, ventas y preventas), nuevo proyecto multifamiliar con su ficha de factibilidad y
## crédito constructor, e hipotecas que otorgan tus bancos a los ciudadanos.

signal closed
signal message(text: String, category: String)

var hud: Hud
var tabs: TabContainer
var summary_box: VBoxContainer
var projects_box: VBoxContainer
var new_box: VBoxContainer
var mortgage_box: VBoxContainer
var _level_opt: OptionButton
var _tier_opt: OptionButton
var _ficha: RichTextLabel
var _credit: Dictionary = {}


func setup(p_hud: Hud) -> void:
	hud = p_hud
	add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	add_child(head)
	var t := UIKit.label("Bienes raíces", 20, UIKit.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UIKit.button("↻", func(): refresh(), 32))
	head.add_child(UIKit.button("✕", func(): closed.emit(), 32))
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(tabs)
	summary_box = _tab("Resumen")
	projects_box = _tab("Proyectos")
	new_box = _tab("Nuevo proyecto")
	mortgage_box = _tab("Hipotecas")


func _tab(tab_name: String) -> VBoxContainer:
	var sb := UIKit.scroll_box(Vector2(0, 200))
	sb["scroll"].name = tab_name
	sb["scroll"].size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(sb["scroll"])
	return sb["box"]


func _note(text: String) -> Label:
	var l := UIKit.label(text, 12, UIKit.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 380
	return l


func refresh() -> void:
	RealEstateSim.init_state(GameState)
	_summary()
	_projects()
	_new_project()
	_mortgages()


# --- Resumen ------------------------------------------------------------------------------------

func _summary() -> void:
	UIKit.clear(summary_box)
	var gs := GameState
	var tot := {"total": 0, "disponible": 0, "arrendada": 0, "vendida": 0, "preventa": 0, "embargada": 0}
	var rent_month := 0.0
	var in_works := 0
	for b in RealEstateSim.player_projects(gs):
		var c := RealEstateSim.counts(b)
		for k in tot:
			tot[k] += int(c.get(k, 0))
		rent_month += float(c["rent_month"])
		if b.has("re_project"):
			in_works += 1
	var d := RealEstateSim.demand(gs)
	var s := "[b]Demanda de vivienda del pueblo: ×%.2f[/b] (%s)\n" % [d, "alta: precios al alza" if d > 1.05 else ("baja: sobran unidades" if d < 0.95 else "normal")]
	s += "Tasa de capitalización de la época: %s anual del valor · Hipoteca del banco externo a ciudadanos: %.1f%% a %d meses\n\n" % [Fmt.pct(RealEstateSim.cap_rate(gs) * 100.0), LoanContract.external_citizen_rate(gs) * 100.0, LoanContract.mortgage_term(gs)]
	s += "[b]Tus unidades[/b]: %d en total · %d disponibles · %d arrendadas · %d vendidas · %d en preventa%s · %d proyecto(s) en obra\n" % [tot["total"], tot["disponible"], tot["arrendada"], tot["vendida"], tot["preventa"], " · %d embargadas" % tot["embargada"] if tot["embargada"] > 0 else "", in_works]
	s += "Arriendos contratados: %s/mes\n\n" % Fmt.money(rent_month)
	var labels := [["rent", "Arriendos cobrados"], ["sales", "Ventas de unidades"], ["presales", "Recibido en preventas"], ["fees", "Cuotas de administración"],
		["mortgages_player", "Hipotecas de tus bancos"], ["mortgages_external", "Hipotecas del banco externo"], ["rentals", "Contratos de arriendo nuevos"], ["evictions", "Desalojos"]]
	s += "[table=4][cell][b]Concepto[/b][/cell][cell][b]Este mes[/b][/cell][cell][b]Mes anterior[/b][/cell][cell][b]Total[/b][/cell]"
	for pair in labels:
		var k: String = pair[0]
		var is_count: bool = k in ["rentals", "evictions"]
		var vals := []
		for period in ["month", "last_month", "total"]:
			var v := float(gs.realestate.get(period, {}).get(k, 0.0))
			vals.append(str(int(v)) if is_count else Fmt.money(v))
		s += "[cell]%s[/cell][cell]%s[/cell][cell]%s[/cell][cell]%s[/cell]" % [pair[1], vals[0], vals[1], vals[2]]
	s += "[/table]\n"
	var rl := UIKit.rich()
	rl.text = s
	summary_box.add_child(rl)
	summary_box.add_child(_note("Los apartamentos, edificios residenciales y rascacielos se dividen en unidades que se arriendan o venden por separado. Las familias arriendan si les alcanza (renta ≤ 40% del ingreso), compran de contado, con hipoteca (cuota ≤ 35% del ingreso) o sobre planos. Si no pagan, se desalojan o se embarga la unidad."))


# --- Proyectos ----------------------------------------------------------------------------------

func _projects() -> void:
	UIKit.clear(projects_box)
	var list := RealEstateSim.player_projects(GameState)
	if list.is_empty():
		projects_box.add_child(_note("Aún no tienes edificios por unidades. Crea uno en «Nuevo proyecto» o mejora una casa de ladrillo a apartamentos."))
	for b in list:
		var c := RealEstateSim.counts(b)
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.BG_LIGHT, 6, 8))
		var row := HBoxContainer.new()
		panel.add_child(row)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(v)
		v.add_child(UIKit.label("%s · %s" % [GameState.building_label(b), Housing.tier_label(str(b.get("tier", "normal")))], 15))
		var status := "activo"
		if b.has("re_project"):
			var p: Dictionary = b["re_project"]
			var i := RealEstateSim.stage_index(b)
			status = "en obra %d%% · etapa: %s%s · preventas %s" % [int(100.0 * float(b["work_done"]) / maxf(1.0, float(b["work_needed"]))), str(p["stages"][i]["label"]).to_lower(), " · PAUSADA" if bool(b.get("paused", false)) else "", Fmt.money(float(p["presale_received"]))]
		elif not GameState.is_active(b):
			status = "en obra"
		v.add_child(UIKit.label(status, 12, UIKit.TEXT_DIM if not bool(b.get("paused", false)) else Color(0.95, 0.45, 0.45)))
		v.add_child(UIKit.label("%d unidades: %d disp. · %d arrend. · %d vend. · %d preventa" % [int(c["total"]), int(c["disponible"]), int(c["arrendada"]), int(c["vendida"]), int(c["preventa"])], 12, UIKit.TEXT_DIM))
		v.add_child(UIKit.label("Arriendo mes anterior %s · ventas totales %s · valor tuyo %s" % [Fmt.money(BusinessSim.period_value(b, "last_month", "alquileres")), Fmt.money(BusinessSim.period_value(b, "total", "ventas")), Fmt.money(EconomySim.property_value(GameState, b))], 12, Color(0.5, 0.85, 0.5)))
		var id := int(b["id"])
		row.add_child(UIKit.button("Abrir", func():
			hud.open_building(id)
			var world := hud.get_parent()
			if world.has_method("focus_building"):
				world.focus_building(id)))
		projects_box.add_child(panel)


# --- Nuevo proyecto ------------------------------------------------------------------------------

func _new_project() -> void:
	UIKit.clear(new_box)
	var row := HBoxContainer.new()
	new_box.add_child(row)
	_level_opt = OptionButton.new()
	for lvl in range(1, GameData.max_level("vivienda") + 1):
		if RealEstateSim.is_multi_level(lvl):
			_level_opt.add_item(str(GameData.level_def("vivienda", lvl).get("label", lvl)))
			_level_opt.set_item_metadata(_level_opt.item_count - 1, lvl)
	row.add_child(_level_opt)
	_tier_opt = OptionButton.new()
	for tier in Housing.TIERS:
		_tier_opt.add_item(Housing.tier_label(tier))
	row.add_child(_tier_opt)
	_ficha = UIKit.rich()
	new_box.add_child(_ficha)
	var credit_holder := VBoxContainer.new()
	new_box.add_child(credit_holder)
	var place := UIKit.button("Colocar proyecto en el mapa", _place)
	new_box.add_child(place)
	new_box.add_child(_note("La obra se paga por etapas (cimentación → estructura → acabados): cada etapa se cobra al empezarla y, si no tienes dinero, la obra se pausa sin perder lo avanzado. Con crédito constructor el banco pone su parte de cada etapa."))
	var upd := func() -> void:
		var lvl := _sel_level()
		var tier: String = Housing.TIERS[_tier_opt.selected]
		var f := RealEstateSim.feasibility(GameState, lvl, tier)
		var reason := ConstructionSim.level_block_reason(GameState, "vivienda", lvl)
		_ficha.text = RealEstateSim.feasibility_text(f) + ("[color=#e66]%s[/color]\n" % reason if reason != "" else "")
		UIKit.clear(credit_holder)
		_credit = UnitsTab.credit_selector(GameState, float(f["cost_total"]))
		credit_holder.add_child(_credit["control"])
		place.disabled = reason != ""
		place.text = "Colocar proyecto en el mapa" if reason == "" else reason
	_level_opt.item_selected.connect(func(_i): upd.call())
	_tier_opt.item_selected.connect(func(_i): upd.call())
	upd.call()


func _sel_level() -> int:
	if _level_opt == null or _level_opt.item_count == 0:
		return 4
	return int(_level_opt.get_item_metadata(_level_opt.selected))


func _place() -> void:
	var opts: Dictionary = _credit["get"].call() if not _credit.is_empty() else {}
	var tier: String = Housing.TIERS[_tier_opt.selected]
	var reason := RealEstateSim.project_block_reason(GameState, _sel_level(), tier, float(opts.get("credit_ratio", 0.0)) if str(opts.get("credit_lender", "")) != "" else 0.0)
	if reason != "":
		message.emit(reason, "jugador")
		return
	EventBus.project_mode_requested.emit(_sel_level(), tier, opts)
	closed.emit()


# --- Hipotecas -----------------------------------------------------------------------------------

func _mortgages() -> void:
	UIKit.clear(mortgage_box)
	var gs := GameState
	mortgage_box.add_child(_note("Cuando una familia compra una unidad o casa y no le alcanza, pide hipoteca (cuota inicial %s, cuota ≤ %s del ingreso, plazo %d meses en esta época). Primero a tus bancos con hipotecas activas, cupo (empleados) y capital; si no, al banco externo al %.1f%%." % [Fmt.pct(float(LoanContract.mortgage_cfg().get("down_share", 0.2)) * 100.0), Fmt.pct(float(LoanContract.mortgage_cfg().get("max_payment_income_ratio", 0.35)) * 100.0), LoanContract.mortgage_term(gs), LoanContract.external_citizen_rate(gs) * 100.0]))
	var any := false
	for b in gs.buildings:
		if not gs.owned_by_player(b) or not BankSim.is_bank(b):
			continue
		any = true
		BankSim.bank_settings(gs, b)
		var bank: Dictionary = b
		mortgage_box.add_child(UIKit.label(gs.building_label(b), 15, UIKit.ACCENT))
		var n := 0
		var bal := 0.0
		for l in BankSim.bank_loans(gs, b):
			if str(l.get("purpose", "")) == "hipoteca":
				n += 1
				bal += float(l["balance"])
		mortgage_box.add_child(UIKit.label("Hipotecas vigentes: %d · cartera %s · cupo %d/%d préstamos" % [n, Fmt.money(bal), BankSim.bank_loans(gs, b).size(), BankSim.bank_capacity(gs, b)], 12, UIKit.TEXT_DIM))
		var cb := CheckBox.new()
		cb.text = "Otorgar hipotecas"
		cb.button_pressed = bool(b.get("mortgages", true))
		cb.toggled.connect(func(on): bank["mortgages"] = on)
		mortgage_box.add_child(cb)
		var r := HBoxContainer.new()
		r.add_child(UIKit.label("Tasa hipotecaria anual (%):"))
		r.add_child(UIKit.spin(0, 60, 0.25, float(b.get("mortgage_rate", b["loan_rate"])) * 100.0, func(val): bank["mortgage_rate"] = val / 100.0))
		mortgage_box.add_child(r)
	if not any:
		mortgage_box.add_child(_note("No tienes bancos. Construye una Casa de préstamos para otorgar hipotecas y ganar intereses."))
	var ext := 0
	var ext_bal := 0.0
	for l in gs.loans:
		if str(l.get("purpose", "")) == "hipoteca" and not str(l["lender"]).is_valid_int():
			ext += 1
			ext_bal += float(l["balance"])
	mortgage_box.add_child(UIKit.label("Hipotecas con bancos externos: %d · saldo %s" % [ext, Fmt.money(ext_bal)], 12, UIKit.TEXT_DIM))
