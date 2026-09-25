class_name BuildMenu
extends VBoxContainer
## Catálogo de construcción: viviendas (con calidad normal/media/alta), oficina,
## negocios y expansión de terreno. Todo sale de data/*.json.

signal closed

var tier_opt: OptionButton
var list: VBoxContainer


func setup() -> void:
	add_theme_constant_override("separation", 8)
	UIKit.header(self, "build", "Construir", func(): closed.emit(), [])
	var row := HBoxContainer.new()
	row.add_child(UIKit.label("Calidad de vivienda:"))
	tier_opt = OptionButton.new()
	for tier in Housing.TIERS:
		tier_opt.add_item(Housing.tier_label(tier))
	tier_opt.item_selected.connect(func(_i): refresh())
	row.add_child(tier_opt)
	add_child(row)
	var sb := UIKit.scroll_box(Vector2(0, 200))
	sb["scroll"].size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(sb["scroll"])
	list = sb["box"]
	refresh()


func refresh() -> void:
	UIKit.clear(list)
	var tier: String = Housing.TIERS[tier_opt.selected]
	var last_cat := ""
	for type_id in GameData.buildable_ids():
		var def := GameData.building_def(type_id)
		var cat := str(def.get("category", ""))
		if cat != last_cat:
			last_cat = cat
			list.add_child(UIKit.label({"vivienda": "Viviendas", "oficina": "Oficina", "negocio": "Negocios"}.get(cat, cat), 16, UIKit.ACCENT))
		var ld := GameData.level_def(type_id, 1)
		var cost := ConstructionSim.cost_for(GameState, type_id, 1, false, tier if type_id == "vivienda" else "normal")
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.BG_LIGHT, 6, 8))
		var v := VBoxContainer.new()
		panel.add_child(v)
		var name := str(ld.get("label", type_id))
		if type_id == "vivienda":
			name += " (%s)" % Housing.tier_label(tier)
		v.add_child(UIKit.label(name, 15))
		var mats := []
		for g in cost["materials"]:
			var need := float(cost["from_stock"][g]) + float(cost["import"][g])
			mats.append("%s %d%s" % [GameData.good_label(g), int(need), " (importa %d)" % int(cost["import"][g]) if float(cost["import"][g]) > 0 else ""])
		var extra := ""
		if ld.has("jobs"):
			extra = " · %d empleos · produce %s" % [int(ld["jobs"]), GameData.good_label(str(def.get("product", "")))]
		elif ld.has("capacity"):
			extra = " · %d personas · renta %s" % [GameData.capacity(type_id, 1, tier), Fmt.money(float(ld.get("rent", 0)) * float(Housing.tier_def_by_id(tier).get("rent_mult", 1.0)))]
		var info := UIKit.label("%s · %d días · %d trabajadores%s\n%s" % [Fmt.money(cost["total"]), int(cost["days"]), int(cost["workers"]), extra, ", ".join(mats)], 12, UIKit.TEXT_DIM)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.tooltip_text = str(def.get("description", ""))
		v.add_child(info)
		var reason := ConstructionSim.build_block_reason(GameState, type_id, tier)
		var b := UIKit.button("Colocar" if reason == "" else reason, func(): EventBus.build_mode_requested.emit(type_id, tier))
		b.disabled = reason != ""
		v.add_child(b)
		list.add_child(panel)
	TransitPanel.build_menu_section(list, null)   # Transporte: trazado por puntos.
	_projects_section(tier)   # Bienes raíces: multifamiliares con su ficha de factibilidad.
	list.add_child(UIKit.label("Terreno", 16, UIKit.ACCENT))
	var note := UIKit.label("Las zonas oscuras son terreno del gobierno. Para construir ahí, primero cómpralo (debe ser vecino de un terreno tuyo).", 12, UIKit.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(note)
	list.add_child(UIKit.button("Comprar terreno al gobierno (%s)" % Fmt.money(ConstructionSim.zone_cost(GameState)), func(): EventBus.zone_mode_requested.emit()))


## Bienes raíces: apartamentos, edificios y rascacielos como obra nueva pagada por etapas.
func _projects_section(tier: String) -> void:
	list.add_child(UIKit.label("Proyectos inmobiliarios (por unidades)", 16, UIKit.ACCENT))
	for lvl in range(1, GameData.max_level("vivienda") + 1):
		if not RealEstateSim.is_multi_level(lvl):
			continue
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.BG_LIGHT, 6, 8))
		var v := VBoxContainer.new()
		panel.add_child(v)
		var f := RealEstateSim.feasibility(GameState, lvl, tier)
		var ficha := UIKit.rich()
		ficha.text = RealEstateSim.feasibility_text(f)
		v.add_child(ficha)
		var reason := RealEstateSim.project_block_reason(GameState, lvl, tier)
		var level := lvl
		var b := UIKit.button("Colocar proyecto (sin crédito)" if reason == "" else reason, func(): EventBus.project_mode_requested.emit(level, tier, {}))
		b.disabled = reason != ""
		b.tooltip_text = "Con crédito constructor: panel «Bienes raíces» → Nuevo proyecto."
		v.add_child(b)
		list.add_child(panel)
