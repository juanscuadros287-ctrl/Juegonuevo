extends Node
## Capturas de docs/MIS_EMPRESAS.md: lista con resumen del grupo, ficha de una fábrica (gráfica, compras, ventas),
## ficha más abajo (personal, módulos y costo por unidad), filtro por tipo y ficha del transporte.
## xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 res://tests/screenshot_mis_empresas.tscn -- docs/capturas/empresas


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


func _make(gs, type_id: String, x: float, z: float, staff: int) -> Dictionary:
	var b := ConstructionSim.make_building(gs, type_id, 1, x, z, 0.0, "jugador")
	gs.add_building(b)
	BusinessSim.ledger_add(b, "obras", float(ConstructionSim.cost_for(gs, type_id, 1, false)["total"]))
	_staff(gs, b, staff)
	return b


func _scroll_to(w: MyCompaniesWindow, title: String) -> void:
	var sc := w.detail_box.get_parent() as ScrollContainer
	for btn in w.detail_box.find_children("*", "Button", true, false):
		if (btn as Button).text == title:
			sc.scroll_vertical = int((btn as Button).global_position.y - w.detail_box.global_position.y) - 10
			return


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://"
	DirAccess.make_dir_recursive_absolute(out)
	var gs = GameState
	gs.new_game({"map_type": "interior", "seed": 2024, "difficulty": "facil", "town_name": "San Rafael"})
	gs.money = 400000.0
	gs.government["treasury"] = 200000.0
	var pan := _make(gs, "panaderia", 26.0, -26.0, 3)
	pan["auto_price"] = true
	var trig := _make(gs, "trigal", -40.0, 40.0, 4)
	trig["modules"] = {"almacen": 4}
	var mol := _make(gs, "molino", 40.0, 40.0, 3)
	mol["modules"] = {"almacen": 3, "parqueadero": 2}
	WarehouseSim.invalidate()
	var can := _make(gs, "cantera", -26.0, -26.0, 4)
	var cen := _make(gs, "central_transporte", -60.0, 10.0, 2)
	TransportDivSim.set_org(gs, cen, "empresa", "Transportes Cuadros")
	LogisticsSim.create_route(gs, {"from": int(trig["id"]), "to": int(mol["id"]), "mode": "pie", "good": "trigo", "qty": 40.0, "auto": true, "every": 2})
	LogisticsSim.create_route(gs, {"from": 0, "to": int(pan["id"]), "mode": "pie", "good": "trigo", "qty": 20.0, "auto": true, "every": 3, "buy": true})
	gs.suppress_notifications = true
	TimeManager.advance_days(14 * 30)
	gs.suppress_notifications = false
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	await _frames(30)
	var hud: Hud = world.hud
	world.minimap.visible = false
	var w: MyCompaniesWindow = hud.companies_window
	hud._open_item("companies")
	w.select(int(mol["id"]))
	await _frames(60)
	_save(out, "lista_y_ficha.png")
	_scroll_to(w, "Qué compra y a quién")
	await _frames(30)
	_save(out, "ficha_compras_ventas.png")
	_scroll_to(w, "Empleados, vehículos y módulos")
	await _frames(30)
	_save(out, "ficha_personal_costos.png")
	w.sort_key = "roi"
	w.group = "produccion"
	w.group_opt.select(1)
	w.sort_opt.select(CompanyReportSim.SORTS.find("roi"))
	w._rebuild_list()
	w.select(int(pan["id"]))
	await _frames(40)
	_save(out, "filtro_produccion_roi.png")
	w.group = ""
	w.group_opt.select(0)
	w._rebuild_list()
	w.select(int(cen["id"]))
	await _frames(40)
	_save(out, "ficha_transporte.png")
	print("empresas: ", can["id"])
	get_tree().quit()
