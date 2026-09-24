class_name LogisticsPanel
extends VBoxContainer
## Panel "Logística" (Fase 6): región y yacimientos, almacén de la compañía, cadenas de
## producción (recetas), transporte interno con rutas y carreteras.

signal closed
signal message(text: String, category: String)

var hud: Hud
var tabs: TabContainer
var _pages := {}          # nombre -> VBoxContainer
var _live := {}           # nombre -> RichTextLabel que se refresca solo
var _timer := 0.0
# Formulario de nueva ruta (se conserva al refrescar).
var _f_from := -1
var _f_to := 0
var _f_good := ""
var _f_qty := 20.0
var _f_mode := "pie"
var _f_auto := false
var _f_every := 7


func setup(p_hud: Hud) -> void:
	hud = p_hud
	add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	add_child(head)
	var t := UIKit.label("Logística", 20, UIKit.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UIKit.button("✕", func(): closed.emit(), 32))
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(tabs)
	for name in ["Región", "Almacén", "Producción", "Transporte", "Carreteras"]:
		var sc := ScrollContainer.new()
		sc.name = name
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 6)
		sc.add_child(v)
		tabs.add_child(sc)
		_pages[name] = v


func _gs():
	return GameState


func _world() -> Node:
	return hud.get_parent() if hud else null


func _msg(text: String, cat := "jugador") -> void:
	if text != "":
		message.emit(text, cat)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_timer += delta
	if _timer >= 1.0:
		_timer = 0.0
		_update_live()


func refresh() -> void:
	if tabs == null:
		return
	_build_region()
	_build_warehouse()
	_build_production()
	_build_transport()
	_build_roads()
	_update_live()


func _page(name: String) -> VBoxContainer:
	var v: VBoxContainer = _pages[name]
	UIKit.clear(v)
	return v


func _section(v: Control, text: String) -> void:
	v.add_child(UIKit.label(text, 16, UIKit.ACCENT))


func _note(v: Control, text: String) -> void:
	var l := UIKit.label(text, 12, UIKit.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)


func _live_label(v: Control, key: String) -> RichTextLabel:
	var r := UIKit.rich()
	v.add_child(r)
	_live[key] = r
	return r


func _focus(x: float, z: float) -> void:
	var w := _world()
	if w and w.get("camera_rig") != null and w.get("terrain") != null:
		w.camera_rig.focus(Vector3(x, w.terrain.height_at(x, z), z), 45.0)


# --- Región -----------------------------------------------------------------------------------

func _build_region() -> void:
	var v := _page("Región")
	var gs = _gs()
	var reg: Dictionary = RegionSim.region(gs)
	_section(v, str(reg.get("name", reg.get("label", "Región"))))
	_note(v, str(reg.get("description", "")))
	v.add_child(UIKit.label(RegionSim.strengths_text(reg), 13))
	_note(v, "Lo que tu región no tiene (o se agota) se compra a otros pueblos por caminos comerciales (Comercio exterior).")
	_section(v, "Yacimientos")
	var deps: Array = RegionSim.deposits(gs)
	if deps.is_empty():
		_note(v, "Esta región no tiene yacimientos minerales.")
	for d in deps:
		var row := HBoxContainer.new()
		var dx := float(d["x"])
		var dz := float(d["z"])
		var zs: float = gs.MAP_SIZE / gs.ZONE_GRID
		var half: float = gs.MAP_SIZE * 0.5
		var owned: bool = gs.is_zone_unlocked(clampi(int((dx + half) / zs), 0, 4), clampi(int((dz + half) / zs), 0, 4))
		var pct := float(d["amount"]) / maxf(1.0, float(d.get("initial", d["amount"])))
		var l := UIKit.label("%s · %s u. (%d%%)%s" % [RegionSim.resource_label(str(d["type"])), Fmt.thousands(float(d["amount"])), int(pct * 100.0),
				"" if owned else " · terreno del gobierno"], 13, RegionSim.resource_color(str(d["type"])).lightened(0.3))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(UIKit.button("Ver", func(): _focus(dx, dz), 50))
		v.add_child(row)
	_note(v, "Las minas solo se construyen junto a un yacimiento de su tipo (a menos de %d m del marcador). La extracción lo agota lentamente." % int(RegionSim.cfg().get("deposit_radius", 11.0)))


# --- Almacén -----------------------------------------------------------------------------------

func _build_warehouse() -> void:
	var v := _page("Almacén")
	_section(v, "Almacén de la compañía")
	_live_label(v, "warehouse")
	v.add_child(UIKit.button("Construir un almacén", func(): EventBus.build_mode_requested.emit("almacen", "normal")))
	_note(v, "Cada unidad ocupa 1 espacio. La bodega de la plaza da %d espacios; cada almacén suma más y se mejora de nivel. Las minas y campos a menos de %d m de un almacén (o de la plaza) descargan directo; más lejos, su producción espera en el sitio hasta que una ruta la traiga. La madera y piedra del almacén sirven para construir, y tu Tienda vende ropa, herramientas y joyas del almacén." % [int(WarehouseSim.BASE_CAPACITY), int(LogisticsSim.wcfg().get("walk_reach", 30.0))])


func _warehouse_text() -> String:
	var gs = _gs()
	var cap := WarehouseSim.capacity(gs)
	var used := WarehouseSim.used(gs)
	var s := "Ocupado: [b]%s / %s[/b] (%d%%) · valor %s\n" % [Fmt.thousands(used), Fmt.thousands(cap), int(used / maxf(1.0, cap) * 100.0), Fmt.money(WarehouseSim.value(gs))]
	var st := WarehouseSim.all_stock(gs)
	if st.is_empty():
		s += "[color=#aaa]Vacío.[/color]\n"
	var keys := st.keys()
	keys.sort_custom(func(a, b): return float(st[a]) > float(st[b]))
	for g in keys:
		s += "• %s: %s  [color=#aaa](%s c/u)[/color]\n" % [GameData.good_label(str(g)), Fmt.thousands(float(st[g])), Fmt.money2(EconomySim.market_price(gs, str(g)))]
	var pend := LogisticsSim.pending_at_sites(gs)
	if not pend.is_empty():
		s += "\n[b]Esperando transporte en el sitio[/b]\n"
		for id in pend:
			var b: Dictionary = gs.get_building(id)
			s += "• %s: %s %s\n" % [gs.building_label(b), Fmt.thousands(float(pend[id])), GameData.good_label(str(gs.building_def(b).get("product", ""))).to_lower()]
	var pts := LogisticsSim.warehouse_points(gs)
	s += "\n[b]Puntos de descarga[/b]: " + ", ".join(pts.map(func(p): return LogisticsSim.endpoint_label(gs, int(p["id"])).replace(" (almacén)", "")))
	return s


# --- Producción -------------------------------------------------------------------------------

func _build_production() -> void:
	var v := _page("Producción")
	var gs = _gs()
	_section(v, "Tus extracciones y talleres")
	var chain := LogisticsSim.chain_buildings(gs)
	if chain.is_empty():
		_note(v, "Aún no tienes minas, campos ni talleres. Primero extrae materias primas (van al almacén) y luego fabrica productos más caros con recetas.")
	for b in chain:
		var id := int(b["id"])
		var row := HBoxContainer.new()
		var l := UIKit.label("", 13)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.text = "%s — %s\n%s" % [gs.building_label(b), LogisticsSim.recipe_text(str(b["type"]), int(b["level"])), _chain_status(b)]
		row.add_child(l)
		row.add_child(UIKit.button("Abrir", func(): hud.open_building(id), 60))
		v.add_child(row)
	_section(v, "Recetas disponibles")
	for type_id in GameData.sorted_ids(GameData.businesses):
		var def := GameData.building_def(type_id)
		var ld := GameData.level_def(type_id, 1)
		if not LogisticsSim.uses_chain(def, ld):
			continue
		var row := HBoxContainer.new()
		var l := UIKit.label("%s: %s" % [str(def.get("label", type_id)), LogisticsSim.recipe_text(type_id, 1)], 13)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.tooltip_text = str(def.get("description", ""))
		row.add_child(l)
		var reason := ConstructionSim.build_block_reason(gs, type_id)
		var btn := UIKit.button("Construir", func(): EventBus.build_mode_requested.emit(type_id, "normal"), 90)
		btn.disabled = reason != ""
		btn.tooltip_text = reason
		row.add_child(btn)
		v.add_child(row)


func _chain_status(b: Dictionary) -> String:
	var gs = _gs()
	if b["status"] != "activo":
		return "En obra"
	var parts := ["Producción hoy: %.1f" % float(b.get("produced_today", 0.0))]
	if LogisticsSim.output_target(gs, b) == "local":
		var product := str(gs.building_def(b).get("product", ""))
		parts.append("lejos del almacén: %s esperan transporte" % Fmt.thousands(float(b["inventory"].get(product, 0.0))))
	else:
		parts.append("descarga directo al almacén")
	var dep: Dictionary = RegionSim.deposit_for(gs, b)
	if not dep.is_empty():
		parts.append("yacimiento: %s u." % Fmt.thousands(float(dep["amount"])))
	var st := str(b.get("chain_status", ""))
	if st != "":
		parts.append("⚠ " + st)
	return " · ".join(parts)


# --- Transporte -------------------------------------------------------------------------------

func _build_transport() -> void:
	var v := _page("Transporte")
	var gs = _gs()
	_section(v, "Cargadores y vehículos")
	_live_label(v, "carriers")
	if LogisticsSim.centrals(gs).is_empty():
		v.add_child(UIKit.button("Construir una central de transporte", func(): EventBus.build_mode_requested.emit("central_transporte", "normal")))
	_note(v, "A pie: poca carga y lentos, sin carretera. Caballos y carretas (tecnología Carretas de tiro, central mejorada a caballerizas): mucha más carga y velocidad, pero exigen carretera entre origen y destino. Los cargadores y arrieros se contratan en la central (no requieren estudios) y cobran salario; los caballos tienen mantenimiento.")

	_section(v, "Nueva ruta")
	var eps := LogisticsSim.endpoints(gs)
	if _f_from < 0 or not eps.has(_f_from):
		_f_from = _default_origin(eps)
	if not eps.has(_f_to):
		_f_to = LogisticsSim.PLAZA
	var grid := GridContainer.new()
	grid.columns = 2
	v.add_child(grid)
	grid.add_child(UIKit.label("Origen", 13))
	grid.add_child(_endpoint_opt(eps, _f_from, func(id):
		_f_from = id
		_suggest_good()
		refresh.call_deferred()))
	grid.add_child(UIKit.label("Destino", 13))
	grid.add_child(_endpoint_opt(eps, _f_to, func(id):
		_f_to = id))
	grid.add_child(UIKit.label("Bien", 13))
	var goods := LogisticsSim.transportable_goods()
	if _f_good == "" or not goods.has(_f_good):
		_suggest_good()
	var gopt := OptionButton.new()
	for g in goods:
		gopt.add_item("%s (%s en origen)" % [GameData.good_label(g), Fmt.thousands(LogisticsSim.endpoint_stock(gs, _f_from, g))])
		if g == _f_good:
			gopt.select(gopt.item_count - 1)
	gopt.item_selected.connect(func(i): _f_good = goods[i])
	grid.add_child(gopt)
	grid.add_child(UIKit.label("Cantidad", 13))
	grid.add_child(UIKit.spin(1, 5000, 1, _f_qty, func(val): _f_qty = val))
	grid.add_child(UIKit.label("Medio", 13))
	var mopt := OptionButton.new()
	var mids := GameData.sorted_ids(LogisticsSim.modes())
	for m in mids:
		var md := LogisticsSim.mode_def(m)
		var locked: bool = not gs.has_tech(str(md.get("tech", "")))
		mopt.add_item("%s · %d por viaje%s" % [LogisticsSim.mode_label(m), int(md.get("capacity", 0)), " (requiere investigación)" if locked else ""])
		if m == _f_mode:
			mopt.select(mopt.item_count - 1)
	mopt.item_selected.connect(func(i): _f_mode = mids[i])
	grid.add_child(mopt)
	grid.add_child(UIKit.label("Modo", 13))
	var arow := HBoxContainer.new()
	var auto_cb := CheckBox.new()
	auto_cb.text = "Automática, cada"
	auto_cb.button_pressed = _f_auto
	auto_cb.toggled.connect(func(on): _f_auto = on)
	arow.add_child(auto_cb)
	arow.add_child(UIKit.spin(1, 120, 1, _f_every, func(val): _f_every = int(val), 70))
	arow.add_child(UIKit.label("días", 13))
	grid.add_child(arow)
	v.add_child(UIKit.button("Crear ruta", _create_route))
	_note(v, "Manual: un solo envío de esa cantidad (en varios viajes si hace falta). Automática: cada X días lleva hasta esa cantidad.")

	_section(v, "Rutas")
	var rs: Array = LogisticsSim.routes(gs)
	if rs.is_empty():
		_note(v, "No hay rutas.")
	for r in rs:
		var rid := int(r["id"])
		var box := VBoxContainer.new()
		var info := UIKit.label("", 13)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.text = _route_text(r)
		box.add_child(info)
		var row := HBoxContainer.new()
		var active := bool(r.get("active", true))
		row.add_child(UIKit.button("Pausar" if active else "Reanudar", func():
			LogisticsSim.set_route_active(GameState, rid, not active)
			refresh()))
		if bool(r.get("auto", false)):
			row.add_child(UIKit.button("Enviar ahora", func():
				var rr := LogisticsSim.get_route(GameState, rid)
				var moved := LogisticsSim.dispatch(GameState, rr, float(GameState.today()) + TimeManager.hour_float() / 24.0)
				_msg("Envío despachado: %s unidades." % Fmt.thousands(moved) if moved > 0.0 else str(rr.get("status", "")), "negocio")
				refresh()))
		row.add_child(UIKit.button("Eliminar", func():
			LogisticsSim.remove_route(GameState, rid)
			refresh()))
		box.add_child(row)
		box.add_child(HSeparator.new())
		v.add_child(box)
	_section(v, "Envíos en camino")
	_live_label(v, "shipments")


func _default_origin(eps: Array) -> int:
	var pend := LogisticsSim.pending_at_sites(_gs())
	for id in pend:
		if eps.has(id):
			return id
	return eps[1] if eps.size() > 1 else LogisticsSim.PLAZA


func _suggest_good() -> void:
	var gs = _gs()
	if _f_from != LogisticsSim.PLAZA and not LogisticsSim.is_warehouse_endpoint(gs, _f_from):
		var b: Dictionary = gs.get_building(_f_from)
		if not b.is_empty():
			var product := str(gs.building_def(b).get("product", ""))
			if LogisticsSim.transportable_goods().has(product):
				_f_good = product
				return
	var goods := LogisticsSim.transportable_goods()
	var best := ""
	var best_q := 0.0
	for g in goods:
		var q := LogisticsSim.endpoint_stock(gs, _f_from, g)
		if q > best_q:
			best_q = q
			best = g
	_f_good = best if best != "" else (goods[0] if not goods.is_empty() else "")


func _endpoint_opt(eps: Array, selected: int, cb: Callable) -> OptionButton:
	var opt := OptionButton.new()
	opt.custom_minimum_size.x = 230
	opt.clip_text = true
	for id in eps:
		opt.add_item(LogisticsSim.endpoint_label(_gs(), id))
		if id == selected:
			opt.select(opt.item_count - 1)
	opt.item_selected.connect(func(i): cb.call(eps[i]))
	return opt


func _create_route() -> void:
	var r := LogisticsSim.create_route(GameState, {"from": _f_from, "to": _f_to, "good": _f_good, "qty": _f_qty,
		"mode": _f_mode, "auto": _f_auto, "every": _f_every})
	if r.has("error"):
		_msg(r["error"])
		return
	_msg("Ruta creada: %s → %s." % [LogisticsSim.endpoint_label(GameState, _f_from), LogisticsSim.endpoint_label(GameState, _f_to)], "negocio")
	refresh()


func _route_text(r: Dictionary) -> String:
	var gs = _gs()
	var info := LogisticsSim.trip_info(gs, int(r["from"]), int(r["to"]), str(r["mode"]))
	var kind := "cada %d días lleva %s" % [int(r["every"]), Fmt.thousands(float(r["qty"]))] if bool(r.get("auto", false)) else "manual: faltan %s de %s" % [Fmt.thousands(float(r.get("remaining", 0.0))), Fmt.thousands(float(r["qty"]))]
	return "%s → %s\n%s · %s · %s · %d m (%.1f h de ida) · movido %s%s\n%s" % [
		LogisticsSim.endpoint_label(gs, int(r["from"])), LogisticsSim.endpoint_label(gs, int(r["to"])),
		GameData.good_label(str(r["good"])), LogisticsSim.mode_label(str(r["mode"])), kind,
		int(info["distance"]), float(info["travel"]) * 24.0, Fmt.thousands(float(r.get("moved", 0.0))),
		"" if bool(r.get("active", true)) else " · PAUSADA", str(r.get("status", ""))]


func _carriers_text() -> String:
	var gs = _gs()
	var s := ""
	for m in GameData.sorted_ids(LogisticsSim.modes()):
		var c := LogisticsSim.carriers(gs, m)
		if int(c["total"]) > 0 or gs.has_tech(str(LogisticsSim.mode_def(m).get("tech", ""))):
			s += "• %s: %d libres de %d\n" % [LogisticsSim.mode_label(m), int(c["free"]), int(c["total"])]
	for b in LogisticsSim.centrals(gs):
		s += "[color=#aaa]%s (%s): %d empleados[/color]\n" % [gs.building_label(b), str(gs.level_def(b).get("label", "")), LogisticsSim.crew_size(gs, b)]
	if LogisticsSim.centrals(gs).is_empty():
		s += "[color=#e88]No tienes central de transporte: las rutas no pueden operar.[/color]\n"
	var st: Dictionary = gs.logistics.get("stats", {})
	s += "Movido este mes: %s · mes anterior: %s" % [Fmt.thousands(float(st.get("month_moved", 0.0))), Fmt.thousands(float(st.get("last_month_moved", 0.0)))]
	return s


func _shipments_text() -> String:
	var gs = _gs()
	var sh: Array = LogisticsSim.shipments(gs)
	var now: float = float(gs.today()) + TimeManager.hour_float() / 24.0
	var s := ""
	for x in sh:
		var state := "entregado, regresando" if bool(x["delivered"]) else ("llega en %.1f h" % maxf(0.0, (float(x["arrive"]) - now) * 24.0))
		s += "• %s %s: %s → %s · %d %s · %s\n" % [Fmt.thousands(float(x["qty"])), GameData.good_label(str(x["good"])).to_lower(),
			LogisticsSim.endpoint_label(gs, int(x["from"])), LogisticsSim.endpoint_label(gs, int(x["to"])),
			int(x["carriers"]), "cargadores" if str(x["mode"]) == "pie" else "vehículos", state]
	return s if s != "" else "[color=#aaa]Nada en camino.[/color]"


# --- Carreteras -------------------------------------------------------------------------------

func _build_roads() -> void:
	var v := _page("Carreteras")
	var gs = _gs()
	_section(v, "Red de carreteras")
	_live_label(v, "roads")
	for kind in GameData.sorted_ids(RoadSim.cfg().get("kinds", {})):
		var kd := RoadSim.kind_def(kind)
		var tech := str(kd.get("tech", ""))
		var ok: bool = gs.has_tech(tech)
		var btn := UIKit.button("Construir %s (%s/m)" % [RoadSim.kind_label(kind).to_lower(), Fmt.money2(float(kd.get("cost_per_unit", 1.0)) * gs.price_mult())], func():
			if LogisticsVisuals.instance:
				LogisticsVisuals.instance.start_road_mode(kind)
				_msg("Modo carretera: clic en el inicio y clic en el final de cada tramo. Clic derecho o Esc para terminar.", "info"))
		btn.disabled = not ok
		btn.tooltip_text = "" if ok else "Requiere investigar: %s" % GameData.tech_label(tech)
		v.add_child(btn)
	var up := RoadSim.upgrade_all_cost(gs)
	if float(up["length"]) > 0.0:
		var b := UIKit.button("Empedrar todos los caminos de barro (%s)" % Fmt.money(float(up["total"])), func():
			_msg(RoadSim.upgrade_all(GameState))
			if LogisticsVisuals.instance:
				LogisticsVisuals.instance.rebuild_roads()
			refresh())
		b.disabled = not gs.has_tech(str(RoadSim.kind_def("empedrado").get("tech", "")))
		v.add_child(b)
	v.add_child(UIKit.button("Mostrar u ocultar yacimientos", func():
		if LogisticsVisuals.instance:
			LogisticsVisuals.instance.toggle_deposits()))
	_note(v, "Solo los caballos, carretas y vehículos necesitan carretera: las casas y negocios no, la gente camina. Una ruta con carretas exige que origen y destino estén a menos de %d m de la misma red. El empedrado (tecnología Caminos empedrados) usa piedra y es más rápido." % int(RoadSim.cfg().get("reach", 12.0)))


func _roads_text() -> String:
	var gs = _gs()
	var s := ""
	for kind in GameData.sorted_ids(RoadSim.cfg().get("kinds", {})):
		s += "• %s: %s m\n" % [RoadSim.kind_label(kind), Fmt.thousands(RoadSim.total_length(gs, kind))]
	var n := {}
	for c in RoadSim.components(gs):
		n[c] = true
	s += "Tramos: %d · redes separadas: %d" % [RoadSim.roads(gs).size(), n.size()]
	return s


func _update_live() -> void:
	var map := {"warehouse": _warehouse_text, "carriers": _carriers_text, "shipments": _shipments_text, "roads": _roads_text}
	for k in _live.keys():
		var r = _live[k]
		if not is_instance_valid(r):
			_live.erase(k)
			continue
		(r as RichTextLabel).text = map[k].call()
