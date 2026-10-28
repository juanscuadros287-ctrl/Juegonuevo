extends Node
## Pruebas de docs/MIS_EMPRESAS.md: filas de cada empresa (utilidad = ingresos + producción al almacén − costos,
## margen, ROI), historial mensual con tope, orden y filtros, resumen del grupo (patrimonio, consolidado, más y menos
## rentable), compras y proveedores, ventas y canales, personal, vehículos, módulos, costo por unidad, ventana del
## HUD (lista, ficha, botones de mapa y panel, foto 3D), dinero intacto, guardar/cargar y partida vieja.
## godot --headless res://tests/test_mis_empresas.tscn

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func _ready() -> void:
	print("== Dinastía: Mis empresas ==")
	var ids := _setup()
	_test_rows(ids)
	_test_sort_filter()
	_test_summary()
	_test_detail(ids)
	_test_money()
	await _test_window(ids)
	await _test_hud()
	_test_save_load(ids)
	print("== %s (%d fallos) ==" % ["TODO OK" if failures == 0 else "CON FALLOS", failures])
	get_tree().quit(1 if failures > 0 else 0)


# --- Preparación -------------------------------------------------------------------------------------------

func _to_next_month() -> void:
	var n: int = GameState.history.size()
	var guard := 0
	while GameState.history.size() == n and guard < 40:
		TimeManager.advance_days(1)
		guard += 1


func _staff(b: Dictionary) -> void:
	var gs = GameState
	var cands := BusinessSim.candidates(gs, b)
	var jobs := int(gs.level_def(b).get("jobs", 1))
	for i in range(mini(jobs, cands.size())):
		BusinessSim.hire(gs, b, cands[i], maxf(BusinessSim.asked_wage(gs, cands[i], str(b["type"])), GovSim.min_wage(gs)))


func _make(type_id: String, x: float, z: float, invest := true) -> Dictionary:
	var gs = GameState
	var b := ConstructionSim.make_building(gs, type_id, 1, x, z, 0.0, "jugador")
	gs.add_building(b)
	if invest:
		BusinessSim.ledger_add(b, "obras", float(ConstructionSim.cost_for(gs, type_id, 1, false)["total"]))
	return b


func _setup() -> Dictionary:
	GameState.new_game({"map_type": "interior", "seed": 777, "difficulty": "facil"})
	var gs = GameState
	gs.money = 1e6
	gs.government["treasury"] = 1e6
	var pan := _make("panaderia", 26.0, -26.0)
	pan["auto_price"] = true
	var trig := _make("trigal", -40.0, 40.0)
	trig["modules"] = {"almacen": 5}   # Centro de distribución integrado: que no se llene en la prueba.
	WarehouseSim.invalidate()
	var mol := _make("molino", 40.0, 40.0)
	WarehouseSim.add_to(gs, int(mol["id"]), "trigo", 80.0)
	var st := _make("central_transporte", -40.0, -40.0)
	for b in [pan, trig, mol]:
		_staff(b)
	for m in range(3):
		_to_next_month()
	return {"pan": int(pan["id"]), "trig": int(trig["id"]), "mol": int(mol["id"]), "st": int(st["id"])}


func _row(id: int) -> Dictionary:
	for r in CompanyReportSim.rows(GameState):
		if int(r["id"]) == id:
			return r
	return {}


# --- Filas -------------------------------------------------------------------------------------------------

func _test_rows(ids: Dictionary) -> void:
	print("-- Filas por empresa --")
	var gs = GameState
	var rows := CompanyReportSim.rows(gs)
	check(rows.size() == gs.player_buildings().size() and rows.size() >= 4, "una fila por cada empresa tuya (%d)" % rows.size())
	var ok := true
	for r in rows:
		for k in ["name", "level", "status", "income", "transfer", "costs", "profit", "margin", "roi", "invested", "employees", "jobs", "group", "cls"]:
			if not r.has(k):
				ok = false
		if absf(float(r["profit"]) - (float(r["income"]) + float(r["transfer"]) - float(r["costs"]))) > 0.001:
			ok = false
		if float(r["revenue"]) > 0.0 and absf(float(r["margin"]) - float(r["profit"]) / float(r["revenue"])) > 1e-6:
			ok = false
		if float(r["invested"]) > 0.0 and bool(r["has_data"]) and absf(float(r["roi"]) - float(r["annual"]) / float(r["invested"])) > 1e-6:
			ok = false
	check(ok, "utilidad = ingresos + producción al almacén − costos; margen = utilidad ÷ ingresos; ROI = utilidad anual ÷ invertido")
	var pan := _row(ids["pan"])
	var b: Dictionary = gs.get_building(ids["pan"])
	check(absf(float(pan["income"]) - TransportDivSim.income(b)) < 0.001 and absf(float(pan["costs"]) - TransportDivSim.expenses(b)) < 0.001,
		"panadería: ingresos %s y costos %s del libro del mes anterior" % [Fmt.money(float(pan["income"])), Fmt.money(float(pan["costs"]))])
	check(float(pan["transfer"]) == 0.0 and str(pan["group"]) == "produccion", "la panadería vende en su local (sin transferencia) y es de producción")
	var tr := _row(ids["trig"])
	var tb: Dictionary = gs.get_building(ids["trig"])
	var c: Dictionary = tb.get("costing", {})
	check(CompanyReportSim.is_warehouse_output(gs, tb) and float(tr["transfer"]) > 0.0 and absf(float(tr["transfer"]) - float(c["units"]) * float(c["price"])) < 0.01,
		"trigal: producción entregada al almacén valorada a precio de mercado (%s = %s u. × %s)" % [Fmt.money(float(tr["transfer"])), Fmt.thousands(float(c.get("units", 0))), Fmt.money2(float(c.get("price", 0)))])
	check(float(tr["income"]) <= 0.01 and float(tr["profit"]) > float(tr["ledger_profit"]), "sin la transferencia el trigal se vería en pérdida (libro %s, gestión %s)" % [Fmt.money(float(tr["ledger_profit"])), Fmt.money(float(tr["profit"]))])
	check(str(_row(ids["st"])["group"]) == "transporte", "la central de transporte va en el grupo Transporte")
	check(int(pan["employees"]) > 0 and int(pan["employees"]) <= int(pan["jobs"]), "empleados %d/%d" % [int(pan["employees"]), int(pan["jobs"])])
	var h: Array = b.get("pnl_hist", [])
	check(h.size() == 3, "historial mensual: una muestra por cierre de mes (%d)" % h.size())
	b["pnl_hist"] = []
	for i in range(CompanyReportSim.HIST_MAX + 5):
		CompanyReportSim.monthly(gs)
	check((b["pnl_hist"] as Array).size() == CompanyReportSim.HIST_MAX, "historial con tope de %d meses" % CompanyReportSim.HIST_MAX)
	b["pnl_hist"] = h
	var hs := CompanyReportSim.history(gs, b)
	check((hs["income"] as Array).size() == 3 and absf(float(hs["profit"][-1]) - (float(hs["income"][-1]) - float(hs["costs"][-1]))) < 0.001, "series de ingresos, costos y utilidad para la gráfica")


# --- Orden y filtros ---------------------------------------------------------------------------------------

func _test_sort_filter() -> void:
	print("-- Orden y filtros --")
	var rows := CompanyReportSim.rows(GameState)
	for key in CompanyReportSim.SORTS:
		var s := CompanyReportSim.sort_rows(rows, key, true)
		var ok := s.size() == rows.size()
		for i in range(s.size() - 1):
			if key == "name":
				ok = ok and str(s[i]["name"]).naturalnocasecmp_to(str(s[i + 1]["name"])) >= 0
			else:
				ok = ok and CompanyReportSim._key(s[i], key) >= CompanyReportSim._key(s[i + 1], key)
		var a := CompanyReportSim.sort_rows(rows, key, false)
		var ok2 := true
		for i in range(a.size() - 1):
			if key != "name":
				ok2 = ok2 and CompanyReportSim._key(a[i], key) <= CompanyReportSim._key(a[i + 1], key)
		check(ok and ok2, "ordena por %s (desc y asc)" % CompanyReportSim.SORT_LABELS[key])
	var prod := CompanyReportSim.filter_rows(rows, "todas", "produccion")
	check(not prod.is_empty() and prod.all(func(r): return str(r["group"]) == "produccion"), "filtro por tipo: producción (%d)" % prod.size())
	var rent := CompanyReportSim.filter_rows(rows, "rentables")
	check(rent.all(func(r): return str(r["cls"]) == "rentable"), "filtro rentables (%d)" % rent.size())
	var loss := CompanyReportSim.filter_rows(rows, "perdidas")
	check(loss.all(func(r): return float(r["profit"]) < 0.0), "filtro con pérdidas (%d)" % loss.size())
	var txt := CompanyReportSim.filter_rows(rows, "todas", "", "molino")
	check(txt.size() == 1 and str(txt[0]["type"]) == "molino", "búsqueda por texto")
	var b: Dictionary = GameState.get_building(int(txt[0]["id"]))
	b["status"] = "cerrado"
	var closed := CompanyReportSim.filter_rows(CompanyReportSim.rows(GameState), "cerradas")
	check(closed.size() == 1 and int(closed[0]["id"]) == int(b["id"]), "filtro cerradas")
	b["status"] = "activo"


# --- Resumen ------------------------------------------------------------------------------------------------

func _test_summary() -> void:
	print("-- Resumen del grupo --")
	var gs = GameState
	var rows := CompanyReportSim.rows(gs)
	var s := CompanyReportSim.summary(gs, rows)
	check(absf(float(s["net_worth"]) - EconomySim.net_worth(gs)) < 0.01, "patrimonio neto %s" % Fmt.money(float(s["net_worth"])))
	check(absf(float(s["result"]) - float(TransportDivSim.consolidated(gs)["result"])) < 0.01, "utilidad total = consolidado contable (%s), sin contar transferencias" % Fmt.money(float(s["result"])))
	var best: Dictionary = s["best"]
	var worst: Dictionary = s["worst"]
	check(not best.is_empty() and not worst.is_empty() and int(best["id"]) != int(worst["id"]), "más rentable: %s (%s) · menos rentable: %s (%s)" % [
		str(best.get("name", "")), CompanyReportSim.rank_text(best), str(worst.get("name", "")), CompanyReportSim.rank_text(worst)])
	var ok := true
	for r in rows:
		if str(r["status"]) == "activo" and bool(r["has_data"]) and str(r["group"]) != "propiedades":
			ok = ok and CompanyReportSim._rank(r) <= CompanyReportSim._rank(best) and CompanyReportSim._rank(r) >= CompanyReportSim._rank(worst)
	check(ok, "ninguna empresa supera a la más rentable ni queda por debajo de la menos rentable")
	check(int(s["count"]) == rows.size() and int(s["active"]) >= 3, "%d empresas, %d activas" % [int(s["count"]), int(s["active"])])


# --- Ficha --------------------------------------------------------------------------------------------------

func _test_detail(ids: Dictionary) -> void:
	print("-- Ficha: compras, ventas, personal y costo por unidad --")
	var gs = GameState
	var mol: Dictionary = gs.get_building(ids["mol"])
	var buys := CompanyReportSim.purchases(gs, mol)
	var trigo := buys.filter(func(x): return str(x["good"]) == "trigo")
	check(trigo.size() == 1 and float(trigo[0]["unit_price"]) > 0.0, "el molino compra trigo a %s/u" % Fmt.money2(float(trigo[0]["unit_price"]) if not trigo.is_empty() else 0.0))
	var sup: Array = trigo[0]["suppliers"] if not trigo.is_empty() else []
	check(sup.any(func(t): return str(t).contains(gs.building_label(gs.get_building(ids["trig"])))), "proveedor: tu trigal (%s)" % " | ".join(sup))
	var sells := CompanyReportSim.sales(gs, gs.get_building(ids["trig"]))
	check(not sells.is_empty() and str(sells[0]["channel"]) == "Entrega al almacén", "el trigal vende entregando al almacén (%s)" % str(sells[0].get("detail", "") if not sells.is_empty() else ""))
	var ps := CompanyReportSim.sales(gs, gs.get_building(ids["pan"]))
	check(ps.any(func(x): return str(x["channel"]) == "Venta directa en el local"), "la panadería vende directo en su local")
	var pr := CompanyReportSim.prices(gs, gs.get_building(ids["pan"]))
	check(float(pr["sell"]) > 0.0 and float(pr["market"]) > 0.0, "precio de venta %s y de mercado %s" % [Fmt.money2(float(pr["sell"])), Fmt.money2(float(pr["market"]))])
	var stf := CompanyReportSim.staff(gs, gs.get_building(ids["pan"]))
	check(int(stf["employees"]) == (stf["people"] as Array).size() and float(stf["payroll"]) > 0.0, "personal: %d empleados, nómina %s" % [int(stf["employees"]), Fmt.money(float(stf["payroll"]))])
	var mods := CompanyReportSim.modules(gs, gs.get_building(ids["pan"]))
	check(mods.any(func(m): return str(m["id"]) == "almacen" and int(m["level"]) >= 1), "módulos: almacén integrado nivel %s" % str(mods.map(func(m): return "%s %d" % [m["id"], m["level"]])))
	var st: Dictionary = gs.get_building(ids["st"])
	var v := LogisticsSim.buy_vehicle(gs, st, "carreta") if LogisticsSim.buy_block_reason(gs, st, "carreta") == "" else {}
	var vs := CompanyReportSim.vehicles(gs, st)
	check(v.is_empty() or vs.size() >= 1, "vehículos con base en la central: %d" % vs.size())
	var uc := CompanyReportSim.unit_cost(gs, gs.get_building(ids["pan"]))
	check(str(uc["source"]) == "real" and float(uc["data"]["unit_cost"]) > 0.0, "costo por unidad real (CostSim): %s" % Fmt.money2(float(uc["data"].get("unit_cost", 0.0))))
	var fresh := _make("panaderia", 60.0, -60.0, false)
	var ue := CompanyReportSim.unit_cost(gs, fresh)
	check(str(ue["source"]) == "estimado" and float(ue["data"]["unit_cost"]) > 0.0, "sin cierre de mes: costo estimado con la calculadora")
	var fr := _row(int(fresh["id"]))
	check(not bool(fr["has_data"]) and is_nan(float(fr["roi"])) and str(fr["cls"]) == "sin datos", "empresa nueva: sin datos, sin ROI")
	gs.buildings.erase(fresh)


func _test_money() -> void:
	print("-- Economía cerrada --")
	var gs = GameState
	var sys0 := FlowSim.conserved_total(gs)
	var m0: float = gs.money
	for b in gs.player_buildings():
		CompanyReportSim.row(gs, b)
		CompanyReportSim.purchases(gs, b)
		CompanyReportSim.sales(gs, b)
		CompanyReportSim.staff(gs, b)
		CompanyReportSim.history(gs, b)
		CompanyReportSim.unit_cost(gs, b)
	CompanyReportSim.summary(gs)
	check(absf(FlowSim.conserved_total(gs) - sys0) < 0.0001 and gs.money == m0, "consultar Mis empresas no crea ni mueve dinero")
	sys0 = FlowSim.conserved_total(gs)
	for b in gs.player_buildings():
		b.erase("pnl_hist")
	CompanyReportSim.monthly(gs)
	check(absf(FlowSim.conserved_total(gs) - sys0) < 0.0001, "el registro mensual del historial tampoco")


# --- Ventana ------------------------------------------------------------------------------------------------

func _test_window(ids: Dictionary) -> void:
	print("-- Ventana Mis empresas --")
	var host := Control.new()
	host.size = Vector2(1600, 900)
	add_child(host)
	var w := MyCompaniesWindow.new()
	host.add_child(w)
	w.setup(null)
	w.open()
	await get_tree().process_frame
	check(w.visible and w._cards.size() == w.visible_rows().size() and w._cards.size() == GameState.player_buildings().size(), "lista con una tarjeta por empresa (%d)" % w._cards.size())
	check(w.summary_box.get_node_or_null("Best") != null and w.summary_box.get_node_or_null("Worst") != null and w.summary_box.get_child_count() >= 6, "resumen arriba: patrimonio, utilidad, mes, empresas, más y menos rentable")
	var thumbs := 0
	for id in w._cards:
		if (w._cards[id] as Node).find_child("Thumb", true, false) is TextureRect:
			thumbs += 1
	check(thumbs == w._cards.size() and w.get_node_or_null("BuildingThumbRenderer") != null, "cada tarjeta lleva su foto 3D (render en SubViewport con caché)")
	w.sort_key = "name"
	w.sort_desc = false
	w._rebuild_list()
	var first: Dictionary = w.visible_rows()[0]
	check(w.list_box.get_child(0).name == "Card%d" % int(first["id"]), "ordenar por nombre reordena las tarjetas")
	w.group = "transporte"
	w._rebuild_list()
	check(w._cards.size() == 1 and w._cards.has(ids["st"]), "filtrar por transporte deja solo la central")
	w.group = ""
	w.search.text = "molino"
	w._rebuild_list()
	check(w._cards.size() == 1 and w.selected == ids["mol"], "buscar «molino» la deja sola y la selecciona")
	w.search.text = ""
	w._rebuild_list()
	w.select(ids["pan"])
	await get_tree().process_frame
	check(w.live_thumb != null and w.live_thumb.b_id == ids["pan"] and w.detail_box.find_child("LiveThumb", true, false) != null, "ficha con visor 3D en vivo")
	check(w.chart != null and w.detail_box.find_child("PnlChart", true, false) != null and (w.chart.series as Array).size() == 3, "gráfica de ingresos, costos y utilidad")
	var labels := []
	for n in w.detail_box.find_children("*", "Label", true, false):
		labels.append((n as Label).text)
	for n in w.detail_box.find_children("*", "Button", true, false):
		labels.append((n as Button).text)
	var all := " ".join(labels)
	check(all.contains("Qué compra y a quién") and all.contains("Qué vende y por qué canal") and all.contains("Empleados, vehículos y módulos") and all.contains("Costo por unidad") and all.contains("Precios actuales"),
		"secciones: precios, compras, ventas, personal/vehículos/módulos y costo por unidad")
	var got := {"map": -1, "panel": -1}
	w.focus_building.connect(func(id): got["map"] = id)
	w.open_building.connect(func(id): got["panel"] = id)
	(w.detail_box.find_child("GoMap", true, false) as Button).pressed.emit()
	check(got["map"] == ids["pan"] and not w.visible, "«Ver en el mapa» cierra la ventana y lleva la cámara al edificio")
	w.open(ids["mol"])
	await get_tree().process_frame
	check(w.selected == ids["mol"], "open(id) abre directo en la ficha de esa empresa")
	(w.detail_box.find_child("OpenPanel", true, false) as Button).pressed.emit()
	check(got["panel"] == ids["mol"] and not w.visible, "«Abrir panel» abre el panel del edificio")
	host.queue_free()
	await get_tree().process_frame


func _test_hud() -> void:
	print("-- HUD: categoría Empresas → Mis empresas --")
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	var hud: Hud = world.hud
	hud._open_item("companies")
	await get_tree().process_frame
	check(hud.companies_window.visible and hud._item_active("companies"), "Empresas → Mis empresas abre la ventana")
	var id := int(GameState.player_buildings()[0]["id"])
	hud.companies_window.select(id)
	(hud.companies_window.detail_box.find_child("OpenPanel", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	check(not hud.companies_window.visible and hud.dock_mode == "building" and hud.building_panel.bid == id, "«Abrir panel» abre el panel del edificio en el HUD")
	hud._open_item("companies")
	(hud.companies_window.detail_box.find_child("GoMap", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	check(not hud.companies_window.visible, "«Ver en el mapa» desde el HUD enfoca el edificio")
	hud._open_item("companies")
	hud._open_item("companies")
	check(not hud.companies_window.visible, "el atajo vuelve a cerrar la ventana")
	world.queue_free()
	await get_tree().process_frame


# --- Guardar y cargar ---------------------------------------------------------------------------------------

func _test_save_load(ids: Dictionary) -> void:
	print("-- Guardar y cargar --")
	var gs = GameState
	var n := (gs.get_building(ids["pan"]).get("pnl_hist", []) as Array).size()
	check(SaveManager.save_game("test_mis_empresas"), "partida guardada")
	GameState.new_game({"map_type": "interior", "seed": 1})
	check(SaveManager.load_game("test_mis_empresas"), "partida cargada")
	gs = GameState
	check((gs.get_building(ids["pan"]).get("pnl_hist", []) as Array).size() == n and n >= 1, "historial de resultados conservado (%d meses)" % n)
	SaveManager.delete_save("test_mis_empresas")
	var d: Dictionary = gs.to_dict()
	for b in d["buildings"]:
		(b as Dictionary).erase("pnl_hist")
	GameState.load_dict(d)
	gs = GameState
	var b: Dictionary = gs.get_building(ids["pan"])
	var h := CompanyReportSim.history(gs, b)
	check(not b.has("pnl_hist") and (h["income"] as Array).size() == 1, "partida vieja: sin historial, la gráfica arranca con el mes anterior")
	check(CompanyReportSim.rows(gs).size() == gs.player_buildings().size(), "partida vieja: la lista se arma igual")
	_to_next_month()
	check((gs.get_building(ids["pan"]).get("pnl_hist", []) as Array).size() == 1 and GameState.running, "partida vieja: el historial empieza al cerrar el mes")
