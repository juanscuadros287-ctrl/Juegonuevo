extends Node
## Prueba de humo de la interfaz: abre todos los paneles, modo construcción, interior.
## godot --headless res://tests/ui_smoke.tscn

func _ready() -> void:
	GameState.new_game({"seed": 21, "difficulty": "facil"})
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	var hud: Hud = world.hud
	for mode in ["player", "build", "companies", "finance", "stats", "government", "logistics", "trade", "tourism", "realestate", "utilities", "transit"]:
		hud._show_dock(mode)
		await get_tree().process_frame
	BankSim.request_player_loan(GameState, 500.0, 12)
	var bank: Dictionary = ConstructionSim.start_construction(GameState, "banco", -32, 10, 0.0, "Banco Test", "sas")["building"]
	var r := ConstructionSim.start_construction(GameState, "granja", 30, -8, 0.0, "Granja Test", "sin_lucro")
	var farm: Dictionary = r["building"]
	TimeManager.advance_days(40)
	hud.open_building(int(farm["id"]))
	for i in range(hud.building_panel.tabs.get_tab_count()):
		hud.building_panel.tabs.current_tab = i
		await get_tree().process_frame
	hud.building_panel._open_hire()
	hud.open_building(int(bank["id"]))
	for i in range(hud.building_panel.tabs.get_tab_count()):
		hud.building_panel.tabs.current_tab = i
		await get_tree().process_frame
	# Bienes raíces: proyecto por etapas, pestaña Unidades, panel y diálogo de crédito.
	for t in ["adobe", "ladrillo", "arquitectura_urbana"]:
		if not GameState.techs.has(t):
			GameState.techs.append(t)
	GameState.money += 20000.0
	var pr := RealEstateSim.start_project(GameState, 4, "media", 34, 24, 0.0, "Torres Test", {"credit_lender": "externo", "credit_ratio": 0.5})
	print("PROYECTO: ", pr.get("error", "iniciado"))
	if pr.has("building"):
		hud.open_building(int(pr["building"]["id"]))
		for i in range(hud.building_panel.tabs.get_tab_count()):
			hud.building_panel.tabs.current_tab = i
			await get_tree().process_frame
	var apt := ConstructionSim.make_building(GameState, "vivienda", 4, -34, 26, 0.0, "jugador")
	GameState.add_building(apt)
	RealEstateSim.ensure_units(GameState, apt)
	hud.open_building(int(apt["id"]))
	for i in range(hud.building_panel.tabs.get_tab_count()):
		hud.building_panel.tabs.current_tab = i
		await get_tree().process_frame
	hud._show_dock("realestate")
	for i in range(hud.realestate_panel.tabs.get_tab_count()):
		hud.realestate_panel.tabs.current_tab = i
		await get_tree().process_frame
	hud.realestate_panel._place()
	await get_tree().process_frame
	world._update_placement()
	world.cancel_placement()
	hud.close_dock()
	LoanDialog.open(hud, func(): pass)
	await get_tree().process_frame
	hud._show_dock("build")
	await get_tree().process_frame
	hud._show_dock("finance")
	await get_tree().process_frame
	if not BankSim.player_loans(GameState).is_empty():
		LoanDialog.show_schedule(hud, BankSim.player_loans(GameState)[0])
	await get_tree().process_frame
	hud._show_dock("stats")
	await get_tree().process_frame
	print("RECOMENDACIONES: ", StatsSim.advice(GameState))
	hud._open_research()
	await get_tree().process_frame
	hud.research_screen._select("adobe")
	hud.research_screen._enqueue_with_prereqs("acueductos")
	hud.research_screen.refresh()
	await get_tree().process_frame
	hud.research_screen.close()
	var some: Citizen = GameState.citizens.values()[3]
	EventBus.citizen_selected.emit(some.id)
	await get_tree().process_frame
	EventBus.build_mode_requested.emit("vivienda", "alta")
	await get_tree().process_frame
	world._update_placement()
	world.cancel_placement()
	world.start_move(int(farm["id"]))
	world._update_placement()
	world.cancel_placement()
	EventBus.zone_mode_requested.emit()
	world.cancel_placement()
	# Redes: trazado de cable, vista de capa y panel de servicios públicos.
	GameState.techs.append("dinamo")
	var uv: UtilitiesVisuals = UtilitiesVisuals.instance
	uv.start_trace("aereo")
	uv.set_hover(Vector2(-20, 20))
	uv.confirm_point()
	uv.set_hover(Vector2(20, 20))
	uv.confirm_point()
	uv.cancel_trace()
	uv.toggle_layer("power")
	hud._show_dock("utilities")
	await get_tree().process_frame
	hud.utilities_panel._update_live()
	uv.toggle_layer("water")
	uv.toggle_layer("water")
	print("REDES: %d tramos · %s" % [GridSim.segments(GameState).size(), GridSim.panel_lines(GameState, farm).strip_edges()])
	# Transporte: carretera por puntos, paradero, borrar y panel Transporte público.
	var tv: TransitVisuals = TransitVisuals.instance
	tv.start_trace("road", "barro")
	for p in [Vector2(-20, -18), Vector2(0, -26), Vector2(20, -18)]:
		tv.set_hover(p)
		tv.add_point()
	tv.finish()
	tv.start_trace("erase")
	tv.set_hover(Vector2(0, -26))
	tv.cancel_trace()
	hud._show_dock("transit")
	await get_tree().process_frame
	hud.transit_panel._update_live()
	print("TRANSPORTE: %d trazados · %s" % [TransitSim.polys(GameState).size(), TransitSim.panel_lines(GameState, farm).strip_edges().get_slice("\n", 0)])
	EventBus.interior_requested.emit(PlayerSim.player_home(GameState)["id"])
	await get_tree().process_frame
	hud._open_invite()
	hud._close_interior()
	# Interfaz nueva: categorías con menú desplegable, pestañas de estadísticas, tablas, centro de
	# notificaciones, opciones, atajos de teclado, toasts agrupados y menú principal.
	for cat in Hud.CATEGORIES:
		hud.open_category(str(cat["id"]))
		await get_tree().process_frame
		for it in cat["items"]:
			hud._open_item(str(it[0]))
			await get_tree().process_frame
	hud.close_category()
	hud.global_econ.close()
	if hud.goods_catalog.visible:
		hud.goods_catalog.close()
	if hud.research_screen.visible:
		hud.research_screen.close()
	hud._close(hud.population_modal)
	hud._show_dock("stats")
	for t in StatsPanel.TABS:
		hud.stats_panel.show_tab(str(t[0]))
		await get_tree().process_frame
	hud._open_population()
	hud.pop_search.text = "a"
	hud._filter_population()
	hud.pop_table.sort_col = 1
	hud.pop_table._apply_sort()
	await get_tree().process_frame
	hud._close(hud.population_modal)
	for i in range(8):
		hud.toast("Aviso de prueba %d" % (i % 3), ["negocio", "familia", "jugador"][i % 3])
	await get_tree().process_frame
	assert(hud.toasts.get_child_count() <= Hud.MAX_TOASTS + 1)
	hud.open_notifications()
	hud._log_filter["negocio"] = true
	hud._rebuild_log()
	await get_tree().process_frame
	hud._close(hud.log_modal)
	hud._open_options()
	await get_tree().process_frame
	hud._close(hud.options_modal)
	var ev := InputEventKey.new()
	ev.pressed = true
	for k in [KEY_P, KEY_F, KEY_Y, KEY_C, KEY_K]:
		ev.keycode = k
		hud._unhandled_input(ev)
		await get_tree().process_frame
	hud.close_dock()
	hud.player_panel.refresh()
	for w in [LineChart.new(), BarChart.new(), DonutChart.new(), Gauge.new(), PyramidChart.new(), Sparkline.new(), Portrait.new(), DataTable.new()]:
		hud.root.add_child(w)
		w.queue_free()
	for n in UIIcons.names():
		assert(UIIcons.tex(n, 18) != null)
	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	menu._show_new()
	menu._select_diff(3)
	menu.country_opt.select(1)
	menu._refresh_regions()
	await get_tree().process_frame
	menu._show_load()
	menu._show_main()
	menu.queue_free()
	TimeManager.set_speed(1)
	for i in range(30):
		await get_tree().process_frame
	TimeManager.start_jump(2)
	while TimeManager.jumping:
		await get_tree().process_frame
	print("UI SMOKE OK · edificios %d · población %d · %s" % [GameState.buildings.size(), GameState.citizens.size(), TimeManager.date_string()])
	get_tree().quit()
