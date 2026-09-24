extends Control
## Menú principal: nueva partida (dificultad, tipo de mapa), cargar y salir.

var main_box: VBoxContainer
var new_panel: PanelContainer
var load_panel: PanelContainer
var town_edit: LineEdit
var player_edit: LineEdit
var seed_edit: SpinBox
var diff_opt: OptionButton
var map_opt: OptionButton
var desc_lbl: Label
var load_list: ItemList
var diff_ids: Array = []
var map_ids: Array = []


func _ready() -> void:
	theme = UIKit.make_theme()
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.12, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	center.add_child(col)
	var title := UIKit.label(str(GameData.game.get("name", "Dinastía")), 64, UIKit.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sub := UIKit.label(str(GameData.game.get("subtitle", "")), 18, UIKit.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)

	main_box = VBoxContainer.new()
	main_box.add_theme_constant_override("separation", 8)
	col.add_child(main_box)
	main_box.add_child(UIKit.button("Nueva partida", _show_new, 320))
	main_box.add_child(UIKit.button("Cargar partida", _show_load, 320))
	main_box.add_child(UIKit.button("Salir", func(): get_tree().quit(), 320))
	var ver := UIKit.label("v" + str(GameData.game.get("version", "")), 12, UIKit.TEXT_DIM)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_box.add_child(ver)

	_build_new_panel(col)
	_build_load_panel(col)


func _build_new_panel(parent: Control) -> void:
	new_panel = PanelContainer.new()
	new_panel.visible = false
	parent.add_child(new_panel)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 10)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	new_panel.add_child(v)
	v.add_child(grid)
	var defaults := GameState.default_settings()

	grid.add_child(UIKit.label("Nombre del pueblo"))
	town_edit = LineEdit.new()
	town_edit.text = defaults["town_name"]
	town_edit.custom_minimum_size.x = 300
	grid.add_child(town_edit)

	grid.add_child(UIKit.label("Tu nombre"))
	player_edit = LineEdit.new()
	player_edit.text = defaults["player_name"]
	grid.add_child(player_edit)

	grid.add_child(UIKit.label("Dificultad"))
	diff_opt = OptionButton.new()
	diff_ids = GameData.sorted_ids(GameData.difficulties)
	for id in diff_ids:
		diff_opt.add_item(str(GameData.difficulties[id].get("label", id)))
	diff_opt.select(maxi(0, diff_ids.find("normal")))
	diff_opt.item_selected.connect(func(_i): _update_desc())
	grid.add_child(diff_opt)

	grid.add_child(UIKit.label("Tipo de mapa"))
	map_opt = OptionButton.new()
	map_ids = GameData.sorted_ids(GameData.map_types)
	for id in map_ids:
		map_opt.add_item(str(GameData.map_types[id].get("label", id)))
	map_opt.item_selected.connect(func(_i): _update_desc())
	grid.add_child(map_opt)

	grid.add_child(UIKit.label("Semilla"))
	seed_edit = SpinBox.new()
	seed_edit.max_value = 999999
	seed_edit.value = defaults["seed"]
	grid.add_child(seed_edit)

	desc_lbl = UIKit.label("", 14, UIKit.TEXT_DIM)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.custom_minimum_size = Vector2(480, 90)
	v.add_child(desc_lbl)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	row.add_child(UIKit.button("Comenzar", _start, 160))
	row.add_child(UIKit.button("Volver", _show_main, 120))
	_update_desc()


func _update_desc() -> void:
	var d: Dictionary = GameData.difficulties[diff_ids[diff_opt.selected]]
	var m: Dictionary = GameData.map_types[map_ids[map_opt.selected]]
	desc_lbl.text = "%s: %s\nDinero inicial %s · %d ciudadanos · enfermedades x%.1f · precios x%.2f · eventos x%.1f\n\n%s: %s" % [
		d.get("label", ""), d.get("description", ""), Fmt.money(float(d.get("start_money", 0))),
		int(d.get("start_citizens", 0)), float(d.get("disease_mult", 1)), float(d.get("price_mult", 1)),
		float(d.get("event_freq_mult", 1)), m.get("label", ""), m.get("description", "")]


func _build_load_panel(parent: Control) -> void:
	load_panel = PanelContainer.new()
	load_panel.visible = false
	parent.add_child(load_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	load_panel.add_child(v)
	load_list = ItemList.new()
	load_list.custom_minimum_size = Vector2(560, 300)
	load_list.item_activated.connect(func(_i): _load_selected())
	v.add_child(load_list)
	var row := HBoxContainer.new()
	v.add_child(row)
	row.add_child(UIKit.button("Cargar", _load_selected, 140))
	row.add_child(UIKit.button("Volver", _show_main, 120))


func _show_main() -> void:
	main_box.visible = true
	new_panel.visible = false
	load_panel.visible = false


func _show_new() -> void:
	main_box.visible = false
	new_panel.visible = true


func _show_load() -> void:
	main_box.visible = false
	load_panel.visible = true
	load_list.clear()
	for s in SaveManager.list_saves():
		var sm: Dictionary = s["summary"]
		var idx := load_list.add_item("%s — %s — %s · pobl. %d" % [s["slot"], sm.get("town", ""), sm.get("date", ""), int(sm.get("population", 0))])
		load_list.set_item_metadata(idx, s["slot"])
	if load_list.item_count == 0:
		load_list.add_item("No hay partidas guardadas", null, false)


func _load_selected() -> void:
	var sel := load_list.get_selected_items()
	if sel.is_empty() or load_list.get_item_metadata(sel[0]) == null:
		return
	if SaveManager.load_game(str(load_list.get_item_metadata(sel[0]))):
		get_tree().change_scene_to_file("res://scenes/main.tscn")


func _start() -> void:
	GameState.new_game({
		"town_name": town_edit.text.strip_edges() if town_edit.text.strip_edges() != "" else "San Rafael",
		"player_name": player_edit.text.strip_edges() if player_edit.text.strip_edges() != "" else "Sebastián",
		"difficulty": diff_ids[diff_opt.selected],
		"map_type": map_ids[map_opt.selected],
		"seed": int(seed_edit.value),
	})
	get_tree().change_scene_to_file("res://scenes/main.tscn")
