class_name RoutesWindow
extends Control
## Panel «Rutas» (docs/RUTAS_BARCOS.md): todas las rutas en el modelo común (carga, internacionales, buses
## y caminos a otros pueblos) con su color, nombre, medio, origen → destino, vehículo, frecuencia, estado y
## carga del mes; leyenda de colores, mostrar u ocultar la capa del mapa, trazar vías férreas y el
## asistente «Nueva ruta» (medio → origen → destino → validación → vehículo → frecuencia).
## Pestaña «Vehículos»: compra central (modelo del catálogo según la investigación → compañía donde queda su
## parqueadero), con velocidad vacío / a tope y capacidad antes de comprar; trenes por composición; vender y
## asignar a rutas. Pestaña «Vías»: tramos de vía férrea con su ocupación (bloqueo por tramos) y vía doble.
## Se abre desde Logística y transporte → Rutas / Vehículos (Hud.CATEGORIES).

signal message(text: String, category: String)

var body: VBoxContainer
var _built := false
var _rows := 0
var _wizard_open := false
# Asistente
var w := {}
var tab := "routes"            # routes | vehicles | rails
# Compra de vehículos
var b_tipo := "camion"
var b_mode := ""
var b_company := -1
var b_comp := {"cerrado": 4}


## Abre (o crea) el panel colgado de la raíz del HUD.
static func open_in(hud, which := "routes") -> RoutesWindow:
	var win: RoutesWindow = hud.root.get_node_or_null("RoutesWindow")
	if win == null:
		win = RoutesWindow.new()
		win.name = "RoutesWindow"
		hud.root.add_child(win)
		win.setup()
		win.message.connect(hud.toast)
	win.tab = which
	win.open()
	return win


static func is_open(hud, which := "") -> bool:
	var win = hud.root.get_node_or_null("RoutesWindow") if hud.root else null
	return win != null and win.visible and (which == "" or str(win.tab) == which)


func show_tab(which: String) -> void:
	tab = which
	refresh()


func setup() -> void:
	if _built:
		return
	_built = true
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.5)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.float_style(UIKit.BG, 14, 16))
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 70
	panel.offset_right = -70
	panel.offset_top = 60
	panel.offset_bottom = -26
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	UIKit.header(v, "logistics", "Rutas y vehículos", close, [UIKit.icon_button("refresh", refresh, "Actualizar")])
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	sc.add_child(body)
	EventBus.day_passed.connect(func(): if visible and not _wizard_open: refresh())
	_reset_wizard()


func open() -> void:
	setup()
	var was := visible
	visible = true
	if not was:
		UIKit.animate_in(self, Vector2.ZERO, 0.16)
	refresh()


func close() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func row_count() -> int:
	return _rows


func _say(text: String, cat := "info") -> void:
	if text != "":
		message.emit(text, cat)


func refresh() -> void:
	if body == null:
		return
	var gs := GameState
	UIKit.clear(body)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	body.add_child(tabs)
	for t in [["routes", "Rutas"], ["vehicles", "Vehículos"], ["rails", "Vías férreas"]]:
		var tb := UIKit.button(str(t[1]), show_tab.bind(str(t[0])), 120)
		tb.toggle_mode = true
		tb.button_pressed = tab == str(t[0])
		tabs.add_child(tb)
	if tab == "vehicles":
		_build_vehicles(gs)
		return
	if tab == "rails":
		_build_rails(gs)
		return
	var sm := RouteSim.summary(gs)
	var tools := HFlowContainer.new()
	tools.add_theme_constant_override("h_separation", 8)
	body.add_child(tools)
	tools.add_child(UIKit.chip("%d rutas · %d internacionales · %s u. este mes" % [int(sm["routes"]), int(sm["intl"]), Fmt.thousands(float(sm["month"]))], UIKit.INFO, "logistics"))
	tools.add_child(UIKit.primary(UIKit.button("Nueva ruta", start_wizard)))
	var layer := CheckBox.new()
	layer.text = "Mostrar rutas en el mapa"
	layer.button_pressed = RouteSim.layer_visible(gs)
	layer.toggled.connect(func(on):
		RouteSim.set_layer_visible(GameState, on)
		if RouteVisuals.instance:
			RouteVisuals.instance.refresh())
	tools.add_child(layer)
	var rail := UIKit.button("Vía férrea por puntos", func(): _trace("rail"))
	rail.disabled = not gs.has_tech(str(RailSim.cfg().get("tech", "ferrocarril")))
	rail.tooltip_text = "Traza rieles para trenes (%s/m)" % Fmt.money2(float(RailSim.cfg().get("cost_per_m", 5.0)) * gs.price_mult())
	tools.add_child(rail)
	tools.add_child(UIKit.button("Borrar vía", func(): _trace("rail_erase")))
	if _wizard_open:
		_build_wizard(gs)
	_build_list(gs)
	_build_help()


func _trace(kind: String) -> void:
	if TransitVisuals.instance == null:
		_say("Abre el mundo para trazar")
		return
	close()
	TransitVisuals.instance.start_trace(kind)


# --- Lista y leyenda ------------------------------------------------------------------------------

func _build_list(gs) -> void:
	var sec := UIKit.section(body, "Rutas y leyenda de colores", "logistics", true, "routes_list")
	var rs := RouteSim.all_routes(gs)
	_rows = rs.size()
	if rs.is_empty():
		sec.add_child(UIKit.label("Sin rutas todavía. Pulsa «Nueva ruta».", 13, UIKit.TEXT_DIM))
		return
	var grid := GridContainer.new()
	grid.columns = 9
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 4)
	sec.add_child(grid)
	for h in ["Color", "Nombre", "Medio", "Origen → destino", "Vehículo", "Frecuencia", "Estado", "Carga del mes", ""]:
		grid.add_child(UIKit.label(h, 12, UIKit.TEXT_FAINT))
	for u in rs:
		var key := str(u["key"])
		var cp := ColorPickerButton.new()
		cp.color = u["color"]
		cp.edit_alpha = false
		cp.custom_minimum_size = Vector2(34, 22)
		cp.popup_closed.connect(func():
			var err := RouteSim.set_color(GameState, key, "#" + cp.color.to_html(false))
			_say(err if err != "" else "Color actualizado", "jugador" if err != "" else "info")
			if RouteVisuals.instance:
				RouteVisuals.instance.refresh()
			refresh())
		grid.add_child(cp)
		var name_edit := LineEdit.new()
		name_edit.text = str(u["name"])
		name_edit.custom_minimum_size.x = 190
		name_edit.text_submitted.connect(func(t):
			_say(RouteSim.set_route_name(GameState, key, t))
			refresh())
		grid.add_child(name_edit)
		grid.add_child(UIKit.label(str(u["mode_label"]), 13))
		var via := str(u["from_label"])
		for s in u.get("stops_labels", []):
			via += " → " + str(s)
		var od := UIKit.label("%s → %s" % [via, str(u["to_label"])], 13)
		od.custom_minimum_size.x = 220
		od.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		grid.add_child(od)
		grid.add_child(UIKit.label(str(u["vehicle_label"]), 13, UIKit.TEXT_DIM))
		grid.add_child(UIKit.label(str(u["freq"]), 13, UIKit.TEXT_DIM))
		var stl := UIKit.label(str(u["status"]).left(70), 12, UIKit.GOOD if bool(u["active"]) else UIKit.TEXT_FAINT)
		stl.custom_minimum_size.x = 200
		stl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		grid.add_child(stl)
		grid.add_child(UIKit.label("%s %s" % [Fmt.thousands(float(u["month_qty"])), GameData.good_label(str(u["good"])).to_lower() if GameData.goods.has(str(u["good"])) else str(u["good"])], 13))
		if str(u["kind"]) in ["carga", "internacional"]:
			grid.add_child(UIKit.danger(UIKit.button("Quitar", func():
				RouteSim.remove(GameState, key)
				if RouteVisuals.instance:
					RouteVisuals.instance.refresh()
				refresh())))
		else:
			grid.add_child(UIKit.label("", 12))


func _build_help() -> void:
	var t := UIKit.label("Medios: a pie hasta %d m · mulas por el monte hasta %d m (o por carretera) · carretas y camiones por carretera de su tipo · trenes entre estaciones unidas por rieles (cochera de tren conectada a la vía) · barcos entre puertos unidos por agua (astillero en el agua) · aviones entre aeropuertos. Entre países la carga va solo por avión o barco: el barco es más barato y más lento; al llegar se paga el arancel del destino con el tipo de cambio." % [
			int(RouteSim.cfg().get("walk_max", 250)), int(RouteSim.cfg().get("mule_max", 1500))], 12, UIKit.TEXT_DIM)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(t)


# --- Asistente -------------------------------------------------------------------------------------

func _reset_wizard() -> void:
	var here := CountriesSim.current_id() if CountriesSim.ready(GameState) else ""
	w = {"mode": "pie", "from_iso": here, "to_iso": here, "from": LogisticsSim.PLAZA, "to": -1, "stops": [], "good": "madera", "qty": 50.0,
			"vehicle": -1, "auto": false, "every": 7, "color": "", "name": "", "stop_pick": -1}


func start_wizard() -> void:
	_reset_wizard()
	w["color"] = RouteSim.next_color(GameState)
	_wizard_open = true
	if visible:
		refresh()


func wizard_set(key: String, value) -> void:
	w[key] = value
	if key == "mode":
		w["vehicle"] = -1


func _intl() -> bool:
	return str(w["from_iso"]) != str(w["to_iso"])


## Motivo por el que la ruta del asistente no tiene sentido ("" si se puede).
func wizard_reason() -> String:
	var gs := GameState
	if int(w["to"]) < 0:
		return "Elige el destino"
	if _intl():
		var fam := RouteSim.family(str(w["mode"]))
		if fam != "agua" and fam != "aire":
			return "Entre países la carga va solo por avión o barco"
		return ""
	return RouteSim.validate(gs, str(w["mode"]), int(w["from"]), int(w["to"]), w["stops"])


func _endpoints(iso: String) -> Array:
	var gs := GameState
	var fam := RouteSim.family(str(w["mode"]))
	var r = CountriesSim.with_country(gs, iso, func() -> Array:
		var out := []
		for id in LogisticsSim.endpoints(gs):
			var ok := true
			match fam:
				"agua":
					ok = ShipSim.port_of(gs, int(id)) >= 0
				"riel":
					ok = RouteSim.station_for(gs, int(id)) >= 0
				"aire":
					ok = AirSim.is_airport(gs, int(id)) or (_intl() and LogisticsSim.is_warehouse_endpoint(gs, int(id)))
			if ok:
				out.append({"id": int(id), "label": LogisticsSim.endpoint_label(gs, int(id))})
		return out) if CountriesSim.ready(gs) else null
	if r == null:
		var out2 := []
		for id in LogisticsSim.endpoints(gs):
			out2.append({"id": int(id), "label": LogisticsSim.endpoint_label(gs, int(id))})
		return out2
	return r


func _build_wizard(gs) -> void:
	var sec := UIKit.section(body, "Nueva ruta (asistente)", "plus", true, "routes_wizard")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	sec.add_child(grid)
	# 1. Medio
	grid.add_child(UIKit.label("1. Medio", 13, UIKit.ACCENT))
	var modes := RouteSim.wizard_modes(gs)
	var ml := []
	var sel := 0
	for i in range(modes.size()):
		ml.append("%s · %d u.%s" % [modes[i]["label"], int(modes[i]["capacity"]), " (requiere investigación)" if bool(modes[i]["locked"]) else ""])
		if str(modes[i]["mode"]) == str(w["mode"]):
			sel = i
	grid.add_child(_opt(ml, sel, func(i):
		wizard_set("mode", str(modes[i]["mode"]))
		refresh()))
	# 2-3. Origen y destino (con país)
	var ids: Array = CountriesSim.presence_ids(gs) if CountriesSim.ready(gs) else []
	for side in ["from", "to"]:
		grid.add_child(UIKit.label("2. Origen" if side == "from" else "3. Destino", 13, UIKit.ACCENT))
		var h := HBoxContainer.new()
		if ids.size() > 1:
			var iso_key: String = side + "_iso"
			h.add_child(_opt(ids.map(func(i): return CountriesSim.country_label(str(i))), ids.find(str(w[iso_key])), func(i):
				w[iso_key] = str(ids[i])
				w[side] = -1 if side == "to" else LogisticsSim.PLAZA
				refresh()))
		var eps := _endpoints(str(w[side + "_iso"]))
		var labels := ["(elige)"]
		var idx := 0
		for i in range(eps.size()):
			labels.append(str(eps[i]["label"]))
			if int(eps[i]["id"]) == int(w[side]):
				idx = i + 1
		h.add_child(_opt(labels, idx, func(i):
			w[side] = int(eps[i - 1]["id"]) if i > 0 else -1
			refresh()))
		grid.add_child(h)
	# Paradas intermedias (solo dentro del país)
	if not _intl():
		grid.add_child(UIKit.label("Paradas", 13, UIKit.TEXT_DIM))
		var hs := HBoxContainer.new()
		var eps2 := _endpoints(str(w["from_iso"]))
		var names := []
		for s in w["stops"]:
			names.append(RouteSim._short(LogisticsSim.endpoint_label(gs, int(s))))
		hs.add_child(UIKit.label(" → ".join(names) if not names.is_empty() else "ninguna", 13))
		hs.add_child(_opt(["+ agregar parada"] + eps2.map(func(e): return str(e["label"])), 0, func(i):
			if i > 0:
				(w["stops"] as Array).append(int(eps2[i - 1]["id"]))
			refresh()))
		if not names.is_empty():
			hs.add_child(UIKit.button("Quitar paradas", func():
				w["stops"] = []
				refresh()))
		grid.add_child(hs)
	# 4. Validación
	grid.add_child(UIKit.label("4. Validación", 13, UIKit.ACCENT))
	var why := wizard_reason()
	var vl := UIKit.label("✔ La ruta tiene sentido" if why == "" else "✖ " + why, 13, UIKit.GOOD if why == "" else UIKit.BAD)
	vl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vl.custom_minimum_size.x = 520
	grid.add_child(vl)
	# 5. Vehículo
	grid.add_child(UIKit.label("5. Vehículo", 13, UIKit.ACCENT))
	var vmode := str(w["mode"])
	var vs: Array = CountriesSim.with_country(gs, str(w["from_iso"]), func(): return RouteSim.vehicles_for(gs, vmode)) if CountriesSim.ready(gs) else RouteSim.vehicles_for(gs, vmode)
	var vlab := ["Cualquiera libre"]
	var vidx := 0
	for i in range(vs.size()):
		vlab.append("%s · %d u. · %s%s%s" % [vs[i]["name"], int(vs[i]["capacity"]), vs[i]["base"], " · de viaje" if bool(vs[i]["busy"]) else "", "" if bool(vs[i]["connected"]) else " · SIN CONEXIÓN"])
		if int(vs[i]["id"]) == int(w["vehicle"]):
			vidx = i + 1
	var vh := HBoxContainer.new()
	vh.add_child(_opt(vlab, vidx, func(i): w["vehicle"] = int(vs[i - 1]["id"]) if i > 0 else -1))
	if _intl() and RouteSim.family(vmode) == "agua":
		var nav := CheckBox.new()
		nav.text = "Naviera (flete por unidad, sin barco propio)"
		nav.button_pressed = bool(w.get("naviera", false))
		nav.toggled.connect(func(on): w["naviera"] = on)
		vh.add_child(nav)
	grid.add_child(vh)
	# Carga
	grid.add_child(UIKit.label("Carga", 13, UIKit.TEXT_DIM))
	var ch := HBoxContainer.new()
	var goods: Array = LogisticsSim.transportable_goods()
	ch.add_child(_opt(goods.map(func(g): return GameData.good_label(str(g))), goods.find(str(w["good"])), func(i): w["good"] = str(goods[i])))
	ch.add_child(UIKit.spin(1, 20000, 1, float(w["qty"]), func(v): w["qty"] = v))
	grid.add_child(ch)
	# 6. Frecuencia
	grid.add_child(UIKit.label("6. Frecuencia", 13, UIKit.ACCENT))
	var fh := HBoxContainer.new()
	var auto := CheckBox.new()
	auto.text = "Automática cada"
	auto.button_pressed = bool(w["auto"])
	auto.toggled.connect(func(on): w["auto"] = on)
	fh.add_child(auto)
	fh.add_child(UIKit.spin(1, 120, 1, float(w["every"]), func(v): w["every"] = int(v)))
	fh.add_child(UIKit.label("días (sin marcar: un viaje)", 12, UIKit.TEXT_DIM))
	grid.add_child(fh)
	# Nombre y color
	grid.add_child(UIKit.label("Nombre y color", 13, UIKit.TEXT_DIM))
	var nh := HBoxContainer.new()
	var ne := LineEdit.new()
	ne.placeholder_text = "Nombre (opcional)"
	ne.text = str(w["name"])
	ne.custom_minimum_size.x = 220
	ne.text_changed.connect(func(t): w["name"] = t)
	nh.add_child(ne)
	var cp := ColorPickerButton.new()
	cp.color = Color.html(str(w["color"])) if Color.html_is_valid(str(w["color"])) else Color.WHITE
	cp.edit_alpha = false
	cp.custom_minimum_size = Vector2(40, 24)
	cp.color_changed.connect(func(c): w["color"] = c.to_html(false))
	nh.add_child(cp)
	grid.add_child(nh)
	var bh := HBoxContainer.new()
	var ok := UIKit.primary(UIKit.button("Crear ruta", _submit))
	ok.disabled = why != ""
	bh.add_child(ok)
	bh.add_child(UIKit.button("Cancelar", func():
		_wizard_open = false
		refresh()))
	sec.add_child(bh)


func _submit() -> void:
	var gs := GameState
	var opts := {"mode": w["mode"], "from": int(w["from"]), "to": int(w["to"]), "stops": w["stops"], "good": w["good"], "qty": float(w["qty"]),
			"vehicle": int(w["vehicle"]), "auto": bool(w["auto"]), "every": int(w["every"]), "color": "#" + str(w["color"]), "name": str(w["name"]),
			"from_iso": w["from_iso"], "to_iso": w["to_iso"]}
	if _intl():
		if RouteSim.family(str(w["mode"])) == "agua":
			opts["mode"] = "naviera" if bool(w.get("naviera", false)) else "barco"
		else:
			opts["mode"] = "avion" if int(w["vehicle"]) >= 0 or str(w["mode"]) == "avion" else "comercial"
	var res := RouteSim.create(gs, opts)
	if res.has("error"):
		_say(str(res["error"]), "jugador")
		refresh()
		return
	_say("Ruta creada: %s" % str(res.get("route", {}).get("name", "envío despachado")), "negocio")
	_wizard_open = false
	if RouteVisuals.instance:
		RouteVisuals.instance.refresh()
	refresh()


func _opt(items: Array, sel: int, cb: Callable) -> OptionButton:
	var o := OptionButton.new()
	o.custom_minimum_size.x = 200
	o.clip_text = true
	for it in items:
		o.add_item(str(it))
	if sel >= 0 and sel < items.size():
		o.select(sel)
	o.item_selected.connect(cb)
	return o


# --- Vehículos: compra central, venta y asignación ------------------------------------------------------

func vehicle_count() -> int:
	return LogisticsSim.vehicles(GameState).size()


func _build_vehicles(gs) -> void:
	var sec := UIKit.section(body, "Comprar un vehículo", "plus", true, "veh_buy")
	var intro := UIKit.label("Elige el tipo, el modelo (según tu investigación) y la COMPAÑÍA donde quedará su parqueadero: de ahí sale y ahí vuelve. Si la compañía no toca la carretera, la vía o el agua que pide el vehículo, o llegó a su cupo (módulo Flota), no se compra y no se cobra nada.", 12, UIKit.TEXT_DIM)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sec.add_child(intro)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	sec.add_child(grid)
	var tipos: Array = VehicleCatalog.TIPOS
	grid.add_child(UIKit.label("Tipo", 13, UIKit.ACCENT))
	grid.add_child(_opt(tipos.map(func(t): return VehicleCatalog.tipo_label(str(t))), tipos.find(b_tipo), func(i):
		b_tipo = str(tipos[i])
		b_mode = ""
		refresh()))
	if b_tipo == "pie":
		var cs := []
		for b in LogisticsSim.stations(gs):
			if str(b.get("type", "")) == "central_transporte":
				cs.append(b)
		var note := UIKit.label("A pie (flota nivel 1) no se compra nada: se abre la vacante de cargador en la central de transporte.", 13)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sec.add_child(note)
		for b in cs:
			var bid := int(b["id"])
			sec.add_child(UIKit.button("Abrir vacante de cargador en %s" % gs.building_label(b), func(): _say(_or_ok(FleetSim.open_porter(GameState, GameState.get_building(bid)), "Vacante de cargador publicada."))))
		if cs.is_empty():
			sec.add_child(UIKit.button("Construir una central de transporte", func(): EventBus.build_mode_requested.emit("central_transporte", "normal")))
		_vehicle_list(gs)
		return
	var ms := VehicleCatalog.models(gs, b_tipo, true)
	if b_mode == "" or not ms.any(func(x): return str(x["id"]) == b_mode):
		b_mode = ""
		for x in ms:
			if bool(x["unlocked"]):
				b_mode = str(x["id"])
		if b_mode == "" and not ms.is_empty():
			b_mode = str(ms[0]["id"])
	var idx := 0
	for i in range(ms.size()):
		if str(ms[i]["id"]) == b_mode:
			idx = i
	grid.add_child(UIKit.label("Modelo", 13, UIKit.ACCENT))
	grid.add_child(_opt(ms.map(func(x): return VehicleCatalog.stats_text(x)), idx, func(i):
		b_mode = str(ms[i]["id"])
		refresh()))
	if b_mode == "":
		return
	if VehicleCatalog.is_train(b_mode):
		grid.add_child(UIKit.label("Vagones", 13, UIKit.ACCENT))
		var wv := VBoxContainer.new()
		for wt in VehicleCatalog.wagon_types():
			var wh := HBoxContainer.new()
			var d: Dictionary = VehicleCatalog.wagon_types()[wt]
			var wl := UIKit.label("%s (%s u., %s)" % [str(d.get("label", wt)), Fmt.thousands(float(d.get("capacity", 0))) if float(d.get("capacity", 0)) > 0 else "%d pasajeros" % int(d.get("passengers", 0)),
					Fmt.money(float(d.get("price", 0)) * gs.price_mult())], 12)
			wl.custom_minimum_size.x = 240
			wh.add_child(wl)
			var key := str(wt)
			wh.add_child(UIKit.spin(0, 30, 1, float(b_comp.get(key, 0)), func(val):
				b_comp[key] = int(val)
				if int(val) <= 0:
					b_comp.erase(key)))
			wv.add_child(wh)
		wv.add_child(UIKit.button("Recalcular estimación", refresh))
		grid.add_child(wv)
	var st := VehicleCatalog.stats(gs, b_mode, b_comp)
	grid.add_child(UIKit.label("Estimación", 13, UIKit.ACCENT))
	var est := "Capacidad %s u. · velocidad vacío %s m/día, a tope %s m/día · mantenimiento %s/día%s · precio %s" % [
		Fmt.thousands(float(st["capacity"])), Fmt.thousands(float(st["speed_empty"])), Fmt.thousands(float(st["speed_full"])), Fmt.money2(float(st["upkeep"])),
		(" · combustible %s/km" % Fmt.money2(float(st["fuel_per_km"]))) if float(st["fuel_per_km"]) > 0.0 else "", Fmt.money(FleetSim.total_price(gs, b_mode, b_comp))]
	if st.has("capacity_by_type"):
		var parts := []
		for wt in st["capacity_by_type"]:
			parts.append("%s %s" % [VehicleCatalog.wagon_label(str(wt)).to_lower(), Fmt.thousands(float(st["capacity_by_type"][wt]))])
		est += "\nPor tipo de carga: " + (", ".join(parts) if not parts.is_empty() else "sin vagones de carga")
	var el := UIKit.label(est, 12)
	el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	el.custom_minimum_size.x = 560
	grid.add_child(el)
	grid.add_child(UIKit.label("Compañía", 13, UIKit.ACCENT))
	var cs2 := FleetSim.companies(gs, b_mode)
	var labels := ["(elige la compañía)"]
	var ci := 0
	for i in range(cs2.size()):
		var c: Dictionary = cs2[i]
		labels.append("%s · %d/%d%s" % [c["label"], int(c["used"]), int(c["limit"]), "" if str(c["reason"]) == "" else " · ✖ " + str(c["reason"]).left(60)])
		if int(c["id"]) == b_company:
			ci = i + 1
	grid.add_child(_opt(labels, ci, func(i):
		b_company = int(cs2[i - 1]["id"]) if i > 0 else -1
		refresh()))
	var comp: Dictionary = gs.get_building(b_company) if b_company >= 0 else {}
	var why := "Elige la compañía donde quedará el vehículo" if comp.is_empty() else FleetSim.buy_block_reason(gs, comp, b_mode, b_comp)
	var wl2 := UIKit.label("✔ Se puede comprar" if why == "" else "✖ " + why, 13, UIKit.GOOD if why == "" else UIKit.BAD)
	wl2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sec.add_child(wl2)
	var buy := UIKit.primary(UIKit.button("Comprar", func():
		var r := FleetSim.buy(GameState, GameState.get_building(b_company), b_mode, b_comp)
		_say(str(r["error"]) if r.has("error") else "Compraste %s: aparece en %s." % [str(r["vehicle"]["name"]), GameState.building_label(GameState.get_building(b_company))])
		refresh()))
	buy.disabled = why != ""
	sec.add_child(buy)
	_vehicle_list(gs)


func _or_ok(err: String, ok: String) -> String:
	return err if err != "" else ok


func _vehicle_list(gs) -> void:
	var sec := UIKit.section(body, "Mis vehículos (%d)" % LogisticsSim.vehicles(gs).size(), "logistics", true, "veh_list")
	if LogisticsSim.vehicles(gs).is_empty():
		sec.add_child(UIKit.label("Aún no tienes vehículos.", 13, UIKit.TEXT_DIM))
		return
	var now := float(gs.today()) + TimeManager.hour_float() / 24.0
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 10)
	sec.add_child(grid)
	for h in ["Vehículo", "Compañía (parqueadero)", "Capacidad", "Estado", "Ruta asignada", ""]:
		grid.add_child(UIKit.label(h, 12, UIKit.TEXT_FAINT))
	for v in LogisticsSim.vehicles(gs):
		var vid := int(v["id"])
		var mode := str(v["mode"])
		var base: Dictionary = gs.get_building(int(v["base"]))
		var nm := "%s · %s" % [str(v["name"]), LogisticsSim.mode_label(mode)]
		if VehicleCatalog.is_train(mode):
			nm += " (%s)" % VehicleCatalog.comp_text(VehicleCatalog.comp_of(v))
		var nl := UIKit.label(nm, 13)
		nl.custom_minimum_size.x = 240
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		grid.add_child(nl)
		grid.add_child(UIKit.label(gs.building_label(base) if not base.is_empty() else "—", 13, UIKit.TEXT_DIM))
		grid.add_child(UIKit.label("%s u." % Fmt.thousands(LogisticsSim.vehicle_capacity(gs, v)), 13))
		var why := FleetSim.base_reason(gs, base, mode) if not base.is_empty() else "sin compañía"
		var state := "de viaje" if LogisticsSim.vehicle_busy(gs, vid, now) else "libre"
		if why != "":
			state = why.left(50)
		elif not base.is_empty() and LogisticsSim.crew_size(gs, base) < LogisticsSim.crew_per(mode):
			state = "sin conductor (vacante abierta)"
		grid.add_child(UIKit.label(state, 12, UIKit.BAD if why != "" else UIKit.TEXT_DIM))
		var rs := []
		var cur := 0
		for r in LogisticsSim.routes(gs):
			if RouteSim.family(str(r["mode"])) == RouteSim.family(mode):
				rs.append(r)
				if int(r.get("vehicle", -1)) == vid:
					cur = rs.size()
		grid.add_child(_opt(["(ninguna)"] + rs.map(func(r): return str(r.get("name", "Ruta"))), cur, func(i):
			_say(_or_ok(FleetSim.assign(GameState, vid, int(rs[i - 1]["id"]) if i > 0 else -1), "Asignación actualizada."))
			refresh()))
		var h := HBoxContainer.new()
		if VehicleCatalog.is_train(mode):
			var wts: Array = VehicleCatalog.wagon_types().keys()
			var add := _opt(["+ vagón…"] + wts.map(func(x): return VehicleCatalog.wagon_label(str(x))), 0, func(i):
				if i > 0:
					_say(_or_ok(FleetSim.add_wagons(GameState, vid, str(wts[i - 1]), 1), "Vagón agregado."))
					refresh())
			add.custom_minimum_size.x = 120
			h.add_child(add)
		h.add_child(UIKit.danger(UIKit.button("Vender", func():
			_say(_or_ok(FleetSim.sell(GameState, vid), "Vehículo vendido (40 % de su precio)."))
			refresh())))
		grid.add_child(h)


# --- Vías férreas: tramos y ocupación ----------------------------------------------------------------------

func _build_rails(gs) -> void:
	var sec := UIKit.section(body, "Tramos de vía férrea (un tren por tramo; dos en vía doble)", "logistics", true, "rails_list")
	var tools := HBoxContainer.new()
	tools.add_child(UIKit.button("Vía férrea por puntos", func(): _trace("rail")))
	tools.add_child(UIKit.button("Borrar vía", func(): _trace("rail_erase")))
	sec.add_child(tools)
	var occ := RailSim.occupancy(gs)
	var rails: Array = RailSim.rails(gs)
	if rails.is_empty():
		sec.add_child(UIKit.label("Sin vías internas. Traza una vía por puntos entre tus estaciones y la cochera.", 13, UIKit.TEXT_DIM))
	for r in rails:
		var key := "r:%d" % int(r["id"])
		var h := HBoxContainer.new()
		var n := int(occ.get(key, 0))
		var cap := RailSim.capacity_of(gs, key)
		var l := UIKit.label("%s · %d m · ocupación %d/%d%s" % [RailSim.line_label(gs, key), int(float(r.get("length", 0.0))), n, cap, " · LLENO" if n >= cap else ""], 13,
				UIKit.BAD if n >= cap else UIKit.GOOD)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		if not bool(r.get("double", false)):
			var rid := int(r["id"])
			h.add_child(UIKit.button("Hacer vía doble", func():
				_say(_or_ok(RailSim.make_double(GameState, rid), "Vía doble lista: caben dos trenes en el tramo."))
				refresh()))
		sec.add_child(h)
