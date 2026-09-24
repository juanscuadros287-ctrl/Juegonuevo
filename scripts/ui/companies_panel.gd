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
	var head := HBoxContainer.new()
	add_child(head)
	var t := UIKit.label("Mis Empresas y Propiedades", 20, UIKit.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UIKit.button("✕", func(): closed.emit(), 32))
	totals = UIKit.label("", 13, UIKit.TEXT_DIM)
	totals.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(totals)
	var sb := UIKit.scroll_box(Vector2(0, 200))
	sb["scroll"].size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(sb["scroll"])
	list = sb["box"]


func refresh() -> void:
	UIKit.clear(list)
	var total_profit := 0.0
	var owned := GameState.player_buildings()
	owned.sort_custom(func(a, b): return str(GameState.building_def(a).get("category", "")) < str(GameState.building_def(b).get("category", "")))
	for b in owned:
		var def: Dictionary = GameState.building_def(b)
		var profit := BusinessSim.period_profit(b, "last_month")
		total_profit += profit
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.BG_LIGHT, 6, 8))
		var row := HBoxContainer.new()
		panel.add_child(row)
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(10, 40)
		var parts: Array = GameState.level_def(b).get("model", [])
		swatch.color = MeshLib.arr_color(parts[0].get("c") if not parts.is_empty() else null, Color.GRAY)
		row.add_child(swatch)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(v)
		v.add_child(UIKit.label("%s  · Nv %d" % [GameState.building_label(b), int(b["level"])], 15))
		var status: String = {"activo": "activo", "construccion": "en construcción", "mejorando": "mejorando (no factura)", "cerrado": "CERRADO"}.get(str(b["status"]), "")
		if BusinessSim.is_business(b) and b["status"] == "activo":
			status += " · " + EconomySim.classify(b)
		var legal := str(GameData.legal_types.get(str(b.get("legal", "sas")), {}).get("label", "")) if def.get("category", "") == "negocio" else str(def.get("label", ""))
		var col := Color(0.5, 0.85, 0.5) if profit >= 0 else Color(0.95, 0.45, 0.45)
		v.add_child(UIKit.label("%s · %s" % [legal, status], 12, UIKit.TEXT_DIM))
		v.add_child(UIKit.label("Resultado mes anterior: %s · este mes: %s" % [Fmt.money(profit), Fmt.money(BusinessSim.period_profit(b, "month"))], 12, col))
		var id := int(b["id"])
		row.add_child(UIKit.button("Abrir", func(): open_building.emit(id)))
		list.add_child(panel)
	if owned.is_empty():
		list.add_child(UIKit.label("Aún no tienes propiedades. Usa «Construir»."))
	totals.text = "Negocios: %d/%d · Propiedades: %d · Resultado total mes anterior: %s" % [BusinessSim.business_count(GameState), BusinessSim.max_businesses(GameState), owned.size(), Fmt.money(total_profit)]
