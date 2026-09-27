class_name RoutesWindow
extends Control
## Panel «Rutas» (docs/RUTAS_BARCOS.md): todas las rutas en el modelo común (carga, internacionales, buses
## y caminos a otros pueblos) con su color, nombre, medio, origen → destino, vehículo, frecuencia, estado y
## carga del mes; leyenda de colores, mostrar u ocultar la capa del mapa, trazar vías férreas y el
## asistente «Nueva ruta» (medio → origen → destino → validación → vehículo → frecuencia).
## Se abre desde Logística y transporte → Rutas (Hud.CATEGORIES).

signal message(text: String, category: String)

var body: VBoxContainer
var _built := false
var _rows := 0
var _wizard_open := false
# Asistente
var w := {}


## Abre (o crea) el panel colgado de la raíz del HUD.
static func open_in(hud) -> RoutesWindow:
	var win: RoutesWindow = hud.root.get_node_or_null("RoutesWindow")
	if win == null:
		win = RoutesWindow.new()
		win.name = "RoutesWindow"
		hud.root.add_child(win)
		win.setup()
		win.message.connect(hud.toast)
	win.open()
	return win


static func is_open(hud) -> bool:
	var win = hud.root.get_node_or_null("RoutesWindow") if hud.root else null
	return win != null and win.visible


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
	UIKit.header(v, "logistics", "Rutas: punto X → punto Y", close, [UIKit.icon_button("refresh", refresh, "Actualizar")])
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
