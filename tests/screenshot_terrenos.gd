extends Node
## Capturas de docs/TERRENOS_COSTOS.md: Mis terrenos (cartera, gráfica y ofertas), pestaña Costos de una fábrica,
## calculadora en Construir, Precios en Estadísticas, transporte y consolidado en Finanzas e Inmobiliaria.
## xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 res://tests/screenshot_terrenos.tscn -- docs/capturas/terrenos_costos


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _save(out: String, name: String) -> void:
	get_viewport().get_texture().get_image().save_png("%s/%s" % [out, name])
	print("captura: ", name)


func _staff(gs, b: Dictionary, n: int) -> void:
	var cands := BusinessSim.candidates(gs, b)
	for i in range(mini(n, cands.size())):
		BusinessSim.hire(gs, b, cands[i], maxf(BusinessSim.asked_wage(gs, cands[i], str(b["type"])), GovSim.min_wage(gs)))


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://"
	DirAccess.make_dir_recursive_absolute(out)
	var gs = GameState
	gs.new_game({"map_type": "interior", "seed": 2024, "difficulty": "facil", "town_name": "San Rafael"})
	gs.money = 400000.0
	gs.government["treasury"] = 200000.0
	for t in ["adobe", "ladrillo", "arquitectura_urbana"]:
		gs.techs.append(t)
	TechSim._recompute_mods(gs)
	# Terrenos: tres territorios del Estado en municipios distintos.
	var g := MapSim.gen(gs)
	for z in g.zones:
		MapSim.reveal_zone_quiet(gs, int(z["id"]))
	var bought := 0
	var zids := {}
	for cy in range(g.c0, g.c1 + 1):
		for cx in range(g.c0, g.c1 + 1):
			if bought >= 3 or maxi(absi(cx), absi(cy)) < 3 or not g.in_country_chunk(cx, cy):
				continue
			var zid := g.zone_index(cx, cy)
			if zids.has(zid) or str(LandSim.owner_info(gs, cx, cy)["owner"]) != "estado" or float(LandSim.quick_info(gs, cx, cy)["land"]) < 1.0:
				continue
			MunicipalSim.region(gs, zid)["policy"]["regulation"] = "media"
			if LandSim.buy_from_state(gs, cx, cy) == "":
				zids[zid] = true
				bought += 1
	# Negocios: panadería, cantera y central de transporte (empresa aparte), inmobiliaria.
	var pan := ConstructionSim.make_building(gs, "panaderia", 1, 26.0, -26.0, 0.0, "jugador")
	gs.add_building(pan)
	BusinessSim.ledger_add(pan, "obras", 400.0 * gs.price_mult())
	pan["auto_price"] = true
	_staff(gs, pan, 3)
	var can := ConstructionSim.make_building(gs, "cantera", 1, -26.0, -26.0, 0.0, "jugador")
	gs.add_building(can)
	BusinessSim.ledger_add(can, "obras", 500.0 * gs.price_mult())
	_staff(gs, can, 4)
	var cen := ConstructionSim.make_building(gs, "central_transporte", 1, -26.0, 26.0, 0.0, "jugador")
	gs.add_building(cen)
	_staff(gs, cen, 2)
	TransportDivSim.set_org(gs, cen, "empresa", "Transportes Cuadros")
	var ag := ConstructionSim.make_building(gs, "inmobiliaria", 1, 26.0, 26.0, 0.0, "jugador")
	gs.add_building(ag)
	LogisticsSim.create_route(gs, {"from": 0, "to": int(pan["id"]), "mode": "pie", "good": "trigo", "qty": 20.0, "auto": true, "every": 3, "buy": true})
	# Dos años de historia (precios, valor de los terrenos, costeo).
	gs.suppress_notifications = true
	TimeManager.advance_days(24 * 30)
	gs.suppress_notifications = false
	for c in gs.citizens.values():
		if not gs.is_player(c.id):
			c.money = maxf(c.money, 60000.0)
			break
	for k in LandPortfolioSim.st(gs)["lots"]:
		if not LandPortfolioSim.is_town(k):
			LandPortfolioSim.make_incoming_offer(gs, k)
			break
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	await _frames(30)
	var hud: Hud = world.hud
	world.minimap.visible = false
	hud.lands_window.open()
	await _frames(40)
	_save(out, "mis_terrenos.png")
	hud.lands_window.close()
	hud.open_building(int(pan["id"]))
	await _frames(5)
	for i in range(hud.building_panel.tabs.get_tab_count()):
		if hud.building_panel.tabs.get_tab_title(i) == "Costos":
			hud.building_panel.tabs.current_tab = i
	await _frames(40)
	_save(out, "costos_fabrica.png")
	hud.open_building(int(cen["id"]))
	await _frames(5)
	for i in range(hud.building_panel.tabs.get_tab_count()):
		if hud.building_panel.tabs.get_tab_title(i) == "Organización":
			hud.building_panel.tabs.current_tab = i
	await _frames(30)
	_save(out, "transporte_empresa.png")
	hud.open_building(int(ag["id"]))
	await _frames(5)
	for i in range(hud.building_panel.tabs.get_tab_count()):
		if hud.building_panel.tabs.get_tab_title(i) == "Inmobiliaria":
			hud.building_panel.tabs.current_tab = i
	await _frames(30)
	_save(out, "inmobiliaria.png")
	hud._show_dock("finance")
	await _frames(10)
	for sc in hud.finance_panel.find_children("*", "ScrollContainer", true, false):
		(sc as ScrollContainer).scroll_vertical = 430
		break
	await _frames(30)
	_save(out, "finanzas_transporte.png")
	hud._show_dock("stats", true)
	hud.stats_panel.show_tab("precios")
	await _frames(40)
	_save(out, "precios.png")
	hud._show_dock("build", true)
	await _frames(10)
	var calc: Button = null
	for btn in hud.build_menu.list.find_children("*", "Button", true, false):
		if (btn as Button).text.begins_with("Calculadora"):
			calc = btn
			calc.pressed.emit()
			break
	await _frames(10)
	if calc != null:
		var n: Node = calc.get_parent()
		while n != null and not (n is ScrollContainer):
			n = n.get_parent()
		if n != null:
			var sc := n as ScrollContainer
			sc.scroll_vertical += int(calc.global_position.y - sc.global_position.y) - 90
	await _frames(30)
	_save(out, "calculadora.png")
	get_tree().quit()
