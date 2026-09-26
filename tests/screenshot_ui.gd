extends Node
## Capturas de la interfaz (HUD, menú desplegado, paneles, fichas y menú principal):
## xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 tests/screenshot_ui.tscn -- <carpeta> [sufijo]
## Funciona con la interfaz antigua y la nueva (usa has_method para lo que solo existe en la nueva).

var out := "user://"
var suffix := ""


func _shot(name: String, frames := 30) -> void:
	for i in range(frames):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/%s%s.png" % [out, name, suffix])
	print("captura: ", name)


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "user://"
	suffix = args[1] if args.size() > 1 else ""
	DirAccess.make_dir_recursive_absolute(out)
	GameState.new_game({"map_type": "interior", "seed": 77, "difficulty": "facil", "town_name": "San Rafael"})
	GameState.money += 30000.0
	var farm: Dictionary = ConstructionSim.start_construction(GameState, "granja", 30, -8, 0.3, "Granja Cuadros")["building"]
	var bank: Dictionary = ConstructionSim.start_construction(GameState, "banco", -32, 10, 1.0, "Banco Cuadros")["building"]
	ConstructionSim.start_construction(GameState, "taberna", -10, 34, 2.0, "Taberna del Río")
	TimeManager.advance_days(60)
	for b in [farm, bank]:
		for c in BusinessSim.candidates(GameState, b).slice(0, 3):
			BusinessSim.hire(GameState, b, c, BusinessSim.asked_wage(GameState, c, b["type"]))
	for m in range(14):
		TimeManager.advance_days(30)
	TimeManager.total_hours += 10 - TimeManager.hour()
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	TimeManager.set_speed(0)
	var hud: Hud = world.hud
	await get_tree().process_frame
	TimeManager.advance_days(25)   # la interfaz muestrea ingresos diarios para las mini-gráficas
	TimeManager.total_hours += 10 - TimeManager.hour()
	# Contratos: ofertas de proveedores NPC para que la bandeja tenga contenido.
	for b in NpcBusinessSim.npc_buildings(GameState).slice(0, 3):
		var product := str(GameState.building_def(b).get("product", ""))
		if product != "" and GameData.goods.has(product):
			ContractSim.create_supply_offer(GameState, "npc:%d" % int(b["id"]), product, 15, EconomySim.market_price(GameState, product) * 0.9, 3, 15)
	for t in ["La cosecha de trigo fue excelente este año.", "Nació Ana Cuadros, hija de Pedro y Lucía.", "Tu taberna tuvo pérdidas el mes pasado."]:
		hud.toast(t, ["negocio", "nacimiento", "jugador"][["La cosecha de trigo fue excelente este año.", "Nació Ana Cuadros, hija de Pedro y Lucía.", "Tu taberna tuvo pérdidas el mes pasado."].find(t)])
	await _shot("hud", 45)
	if hud.has_method("open_category"):
		hud.open_category("economia")
	await _shot("dock_desplegado")
	if hud.has_method("close_category"):
		hud.close_category()
	hud.open_building(int(farm["id"]))
	await _shot("edificio")
	hud._show_dock("stats")
	await _shot("estadisticas")
	if hud.stats_panel.has_method("show_tab"):
		hud.stats_panel.show_tab("poblacion")
		await _shot("estadisticas_poblacion")
		hud.stats_panel.show_tab("mercado")
		await _shot("estadisticas_mercado")
		hud.stats_panel.show_tab("comercio")
		await _shot("estadisticas_comercio")
	if hud.stats_panel.has_method("show_tab"):
		hud.stats_panel.show_tab("pueblos")
		await _shot("pueblos_vecinos")
	else:
		hud._show_dock("trade")
		await _shot("pueblos_vecinos")
	hud._show_dock("companies")
	await _shot("empresas")
	var p := GameState.player_citizen()
	var target: Citizen = null
	for c in GameState.citizens.values():
		if not GameState.is_player(c.id) and not c.children_ids.is_empty() and c.spouse_id >= 0:
			target = c
			break
	if target == null:
		target = GameState.citizens.values()[3]
	EventBus.citizen_selected.emit(target.id)
	await _shot("ficha_persona")
	EventBus.citizen_selected.emit(p.id)
	await _shot("ficha_jugador")
	EventBus.citizen_selected.emit(-1)
	hud._show_dock("contracts")
	await _shot("contratos")
	hud._show_dock("finance")
	await _shot("finanzas")
	hud.close_dock()
	hud._open_population()
	await _shot("poblacion")
	hud._close(hud.population_modal)
	if hud.has_method("_open_options"):
		hud._open_options()
		await _shot("opciones")
		hud._close(hud.options_modal)
	if hud.has_method("open_notifications"):
		hud.open_notifications()
	else:
		hud._open_log()
	await _shot("notificaciones")
	world.queue_free()
	await get_tree().process_frame
	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	add_child(menu)
	await _shot("menu_principal")
	menu._show_new()
	await _shot("menu_nueva_partida")
	get_tree().quit()
