class_name CompaniesPanel
extends VBoxContainer
## "Mis Empresas": todos tus negocios y propiedades con nivel, tipo legal,
## estado y rentabilidad del último mes.

signal closed
signal open_building(id: int)

var list: VBoxContainer
var totals: Label


func setup() -> void:
	add_theme_constant_override("separation", 8)
	UIKit.header(self, "companies", "Mis Empresas y Propiedades", func(): closed.emit(), [])
	totals = UIKit.label("", 13, UIKit.TEXT_DIM)
	totals.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(totals)
	totals.visible = false   # el resumen se muestra en tarjetas
	var sb := UIKit.scroll_box(Vector2(0, 200))
	sb["scroll"].size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(sb["scroll"])
	list = sb["box"]


func refresh() -> void:
	UIKit.clear(list)
	var gs := GameState
	var total_profit := 0.0
	var total_income := 0.0
	var owned := gs.player_buildings()
	owned.sort_custom(func(a, b): return str(gs.building_def(a).get("category", "")) < str(gs.building_def(b).get("category", "")))
	var counts := {"ok": 0, "warn": 0, "bad": 0}
	var cards := []
	for b in owned:
		var profit := BusinessSim.period_profit(b, "last_month")
		var inc := BusinessSim.period_value(b, "last_month", "ventas") + BusinessSim.period_value(b, "last_month", "alquileres") + BusinessSim.period_value(b, "last_month", "intereses")
		total_profit += profit
		total_income += inc
		cards.append(_card(b, profit, inc, counts))
	# Resumen en tarjetas
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	list.add_child(g)
	for spec in [["companies", "Negocios", "%d/%d" % [BusinessSim.business_count(gs), BusinessSim.max_businesses(gs)], UIKit.ACCENT_2],
			["money", "Ingresos", Fmt.money_compact(total_income), UIKit.ACCENT],
			["trend_up" if total_profit >= 0.0 else "trend_down", "Resultado", Fmt.money_compact(total_profit), UIKit.sign_color(total_profit)]]:
		var k := UIKit.kpi_card(spec[0], spec[1], spec[2], "", [], spec[3], "", 0.0)
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(k)
	var chips := UIKit.flow(6, 6)
	list.add_child(chips)
	chips.add_child(UIKit.chip("%d rentables" % counts["ok"], UIKit.GOOD, "check"))
	chips.add_child(UIKit.chip("%d en equilibrio o en obra" % counts["warn"], UIKit.WARN, "alert"))
	chips.add_child(UIKit.chip("%d con pérdidas o cerradas" % counts["bad"], UIKit.BAD, "trend_down"))
	for c in cards:
		list.add_child(c)
	if owned.is_empty():
		list.add_child(UIKit.label("Aún no tienes propiedades. Usa «Construir» (B).", 14, UIKit.TEXT_DIM))
	totals.text = "Negocios: %d/%d · Propiedades: %d · Resultado total mes anterior: %s" % [BusinessSim.business_count(gs), BusinessSim.max_businesses(gs), owned.size(), Fmt.money(total_profit)]


## Tarjeta por negocio: franja de color por estado, margen, empleados y alertas.
func _card(b: Dictionary, profit: float, inc: float, counts: Dictionary) -> Control:
	var gs := GameState
	var def: Dictionary = gs.building_def(b)
	var status := str(b["status"])
	var is_biz := BusinessSim.is_business(b)
	var cls := EconomySim.classify(b) if is_biz and status == "activo" else ""
	var col := UIKit.GOOD
	if status == "cerrado" or cls == "deficitaria":
		col = UIKit.BAD
		counts["bad"] += 1
	elif status != "activo" or cls == "equilibrio":
		col = UIKit.WARN
		counts["warn"] += 1
	elif cls == "sin datos":
		col = UIKit.NEUTRAL
		counts["ok"] += 1
	else:
		counts["ok"] += 1
	var c := UIKit.card(col, 8)
	var p: PanelContainer = c["panel"]
	var v: VBoxContainer = c["box"]
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	v.add_child(head)
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(12, 12)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var parts: Array = gs.level_def(b).get("model", [])
	swatch.color = MeshLib.arr_color(parts[0].get("c") if not parts.is_empty() else null, Color.GRAY)
	head.add_child(swatch)
	var name_l := UIKit.label(gs.building_label(b), 15, UIKit.TEXT)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.clip_text = true
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(name_l)
	head.add_child(UIKit.chip("Nv %d" % int(b["level"]), UIKit.ACCENT))
	var st_txt: String = {"activo": "activo", "construccion": "en obra", "mejorando": "mejorando", "cerrado": "CERRADO"}.get(status, status)
	head.add_child(UIKit.chip(cls if cls != "" else st_txt, col))
	var id := int(b["id"])
	var open_b := UIKit.icon_button("chevron_right", func(): open_building.emit(id), "Abrir el panel del edificio", "", 16)
	head.add_child(open_b)
	var legal := str(GameData.legal_types.get(str(b.get("legal", "sas")), {}).get("label", "")) if def.get("category", "") == "negocio" else str(def.get("label", ""))
	v.add_child(UIKit.label(legal, 11, UIKit.TEXT_FAINT))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	row.add_child(_stat("Resultado", Fmt.money(profit), UIKit.sign_color(profit)))
	if inc >= 10.0 and absf(profit / inc) < 5.0:
		var margin := profit / inc
		row.add_child(_stat("Margen", Fmt.pct(margin * 100.0), UIKit.sign_color(margin)))
	row.add_child(_stat("Este mes", Fmt.money(BusinessSim.period_profit(b, "month")), UIKit.sign_color(BusinessSim.period_profit(b, "month"))))
	if def.get("category", "") == "negocio":
		var emp := 0
		for e in gs.employees_of(id):
			if e.job_kind == "empleo":
				emp += 1
		var jobs := MineSim.jobs(gs, b)
		if jobs > 0:
			v.add_child(UIKit.meter_row("population", "Empleados", float(emp) / float(jobs), "%d/%d" % [emp, jobs]))
		# Alertas
		var alerts := []
		if emp < jobs and status == "activo":
			alerts.append("%d vacantes" % (jobs - emp))
		if int(b.get("loss_months", 0)) > 0:
			alerts.append("%d meses con pérdidas" % int(b["loss_months"]))
		if status == "activo" and gs.owned_by_player(b) and WarehouseTab.summary_line(gs, b).contains("ninguno"):
			alerts.append("sin almacén")
		if not alerts.is_empty():
			var af := UIKit.flow(4, 4)
			v.add_child(af)
			for a in alerts:
				af.add_child(UIKit.chip(a, UIKit.WARN, "alert", 11))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed and e.double_click: open_building.emit(id))
	p.tooltip_text = "Doble clic para abrir"
	return p


func _stat(title: String, value: String, color: Color) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.add_child(UIKit.label(title, 10, UIKit.TEXT_FAINT))
	v.add_child(UIKit.label(value, 14, color))
	return v
