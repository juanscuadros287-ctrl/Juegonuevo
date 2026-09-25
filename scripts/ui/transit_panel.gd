class_name TransitPanel
extends VBoxContainer
## Panel "Transporte público" (docs/TRANSPORTE.md): trazado por puntos (carreteras, caminos y vías
## férreas a otros pueblos, paraderos, borrar), pasaje y tarifa de parqueo, empresas de buses con su
## flota, rutas de bus (automáticas o manuales), pasajeros e ingresos del mes, y cómo llegan los
## trabajadores. También arma la sección de Construir y la pestaña "Buses" del edificio.

signal closed
signal message(text: String, category: String)

var hud: Hud
var body: VBoxContainer
var _live: RichTextLabel
var _timer := 0.0
var _new_stops: Array = []    # ruta manual en armado: ids de paraderos en orden
var _new_depot := -1


func setup(p_hud: Hud) -> void:
	hud = p_hud
	add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	add_child(head)
	var t := UIKit.label("Transporte público", 20, UIKit.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UIKit.button("✕", func(): closed.emit(), 32))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(sc)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	sc.add_child(body)


func _msg(text: String, cat := "jugador") -> void:
	if text != "":
		message.emit(text, cat)


func _section(text: String) -> void:
	body.add_child(UIKit.label(text, 16, UIKit.ACCENT))


static func _note_in(v: Control, text: String) -> void:
	var l := UIKit.label(text, 12, UIKit.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)


static func _vis() -> TransitVisuals:
	return TransitVisuals.instance


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_timer += delta
	if _timer >= 1.0:
		_timer = 0.0
		_update_live()


func _update_live() -> void:
	if _live == null or not is_instance_valid(_live):
		return
	var gs = GameState
	var s := TransitSim.summary(gs)
	var cc: Dictionary = s["commute"]
	var t := "Buses: [b]%d[/b] (%d circulando) · rutas %d · paraderos %d\n" % [int(s["buses"]), int(s["operating"]), int(s["routes"]), int(s["stops"])]
	t += "Pasajeros este mes: [b]%d[/b] (mes anterior %d) · pasajes %s (anterior %s)\n" % [int(s["riders_month"]), int(s["riders_last"]), Fmt.money(float(s["fares_month"])), Fmt.money(float(s["fares_last"]))]
	t += "Costos de buses el mes anterior: %s · parqueo cobrado: %s\n" % [Fmt.money(float(s["costs_last"])), Fmt.money(float(s["parking_last"]))]
	t += "Trabajadores hoy: %d a pie cerca · [color=#e9b949]%d caminan lejos[/color] · [color=#8cf]%d en bus[/color] · [color=#9e9]%d en auto[/color]" % [int(cc["pie"]), int(cc[TransitSim.MODE_FAR]), int(cc[TransitSim.MODE_BUS]), int(cc[TransitSim.MODE_CAR])]
	_live.text = t


## Botones de trazado (los usa también el menú Construir).
static func trace_buttons(v: Control, gs, on_msg: Callable) -> void:
	v.add_child(UIKit.label("Carretera por puntos (curva suave por tus clics):", 13))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	v.add_child(flow)
	for kind in GameData.sorted_ids(RoadSim.cfg().get("kinds", {})):
		var kd := RoadSim.kind_def(kind)
		var tech := str(kd.get("tech", ""))
		var k: String = kind
		var short := RoadSim.kind_label(kind).replace("Camino de ", "").replace("Camino ", "").replace("Carretera de ", "").capitalize()
		var b := UIKit.button("%s · %s/m" % [short, Fmt.money2(float(kd.get("cost_per_unit", 1.0)) * gs.price_mult())], func():
			if _vis():
				_vis().start_trace("road", k)
				on_msg.call("Clic, clic, clic: la carretera sigue una curva suave por tus puntos. Clic derecho, Enter o Esc construye; Retroceso quita el último punto.", "info"))
		b.disabled = not gs.has_tech(tech)
		b.tooltip_text = RoadSim.kind_label(kind) if not b.disabled else "Requiere investigar: %s" % GameData.tech_label(tech)
		flow.add_child(b)
	var flow2 := HFlowContainer.new()
	flow2.add_theme_constant_override("h_separation", 6)
	v.add_child(flow2)
	var sb := UIKit.button("Paradero de bus · %s" % Fmt.money(TransitSim.stop_cost(gs)), func():
		if _vis():
			_vis().start_trace("stop")
			on_msg.call("Clic junto a una carretera empedrada o de cemento para poner un paradero.", "info"))
	var bt := str(TransitSim.sub("bus").get("tech", "transporte_publico"))
	sb.disabled = not gs.has_tech(bt)
	sb.tooltip_text = "Junto a una carretera empedrada o de cemento." if not sb.disabled else "Requiere investigar: %s" % GameData.tech_label(bt)
	flow2.add_child(sb)
	flow2.add_child(UIKit.button("Borrar carretera o paradero", func():
		if _vis():
			_vis().start_trace("erase")))


## Botones para trazar a mano el camino o la vía férrea hacia un pueblo (panel de comercio).
static func trade_buttons(parent: Control, gs, tid: String, on_msg: Callable) -> void:
	var conn := TradeSim.connection(gs, tid)
	var proj := TradeSim.project(gs, tid)
	var manual := TransitSim.has_manual_path(gs, tid)
	var label := "Trazar camino y abrir" if conn.is_empty() and proj.is_empty() else ("Nuevo trazado del camino" if manual else "Trazar camino")
	var b := UIKit.button(label, func():
		if _vis():
			_vis().start_trace("trade_road", tid)
			on_msg.call("Pon puntos desde la salida del pueblo (cerca de la plaza) hasta el borde del mapa. Clic derecho, Enter o Esc termina.", "info"))
	b.tooltip_text = "Dibuja por dónde va el camino. Si no lo trazas, se usa el trazado automático hacia el oeste. Un trazado más largo cuesta más y tarda más (máx. ×%.2f); uno más directo, algo menos." % float(TransitSim.sub("trade_path").get("factor_max", 1.25))
	parent.add_child(b)
	if not conn.is_empty() and gs.has_tech("ferrocarril"):
		var has_rail: bool = bool(conn.get("rail", false)) or conn.get("work", {}).has("rail")
		var rb := UIKit.button("Nuevo trazado de la vía" if has_rail else "Vía férrea por puntos", func():
			if _vis():
				_vis().start_trace("trade_rail", tid)
				on_msg.call("Pon puntos desde la estación de tren o la salida del pueblo hasta el borde del mapa.", "info"))
		rb.disabled = not has_rail and TradeSim.rail_block_reason(gs, tid) != ""
		rb.tooltip_text = TradeSim.rail_block_reason(gs, tid) if rb.disabled else "Durmientes y rieles por el trazado que dibujes."
		parent.add_child(rb)


## Sección del menú Construir.
static func build_menu_section(list: Control, hud_node) -> void:
	var gs = GameState
	if hud_node == null and _vis() and _vis().world:
		hud_node = _vis().world.get("hud")
	list.add_child(UIKit.label("Transporte (trazado por puntos)", 16, UIKit.ACCENT))
	_note_in(list, "Las carreteras son opcionales: la gente camina. Sirven para carretas y camiones que entran al almacén, autos que van al parqueadero y buses.")
	trace_buttons(list, gs, func(t, c): if hud_node: hud_node.toast(t, c))
	list.add_child(UIKit.button("Vías férreas y rutas de bus… (Transporte público)", func():
		if hud_node:
			hud_node._show_dock("transit")))


func refresh() -> void:
	if body == null:
		return
	UIKit.clear(body)
	var gs = GameState
	_live = UIKit.rich()
	body.add_child(_live)
	_update_live()
	_section("Trazar")
	trace_buttons(body, gs, _msg)
	var towns := TradeSim.towns(gs)
	if not towns.is_empty():
		_section("Caminos y vías férreas a otros pueblos")
		for t in towns:
			var tid := str(t["id"])
			var row := HBoxContainer.new()
			var conn := TradeSim.connection(gs, tid)
			var st := "sin ruta"
			if not conn.is_empty():
				st = "%s%s · %.0f km%s" % [TradeSim.road_label(int(conn.get("road", 1))), " + vía" if bool(conn.get("rail", false)) else "",
					float(conn.get("distance", 0.0)), " · trazado a mano" if TransitSim.has_manual_path(gs, tid) else " · trazado automático"]
			elif not TradeSim.project(gs, tid).is_empty():
				st = "camino en obra"
			var l := UIKit.label("%s — %s" % [str(t["name"]), st], 13)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			row.add_child(l)
			body.add_child(row)
			var btns := HBoxContainer.new()
			trade_buttons(btns, gs, tid, _msg)
			body.add_child(btns)
	_section("Pasaje y parqueo")
	var fr := HBoxContainer.new()
	fr.add_child(UIKit.label("Pasaje por viaje:", 13))
	fr.add_child(UIKit.spin(0.0, float(TransitSim.cfg().get("fare_max", 1.0)), 0.01, float(TransitSim.state(gs)["fare"]), func(val):
		TransitSim.set_fare(GameState, val)
		_update_live(), 90))
	body.add_child(fr)
	var pr := HBoxContainer.new()
	pr.add_child(UIKit.label("Parqueo por día:", 13))
	pr.add_child(UIKit.spin(0.0, float(TransitSim.sub("parking").get("fee_max", 0.5)), 0.01, float(TransitSim.state(gs)["parking_fee"]), func(val):
		TransitSim.set_parking_fee(GameState, val), 90))
	body.add_child(pr)
	_note_in(body, "Cada pasajero paga ida y vuelta (%s hoy) a tu empresa de buses; solo lo toma si no supera %d%% de su salario. × dificultad e inflación." % [Fmt.money2(TransitSim.fare(gs) * 2.0), int(float(TransitSim.sub("commute").get("fare_share_max", 0.25)) * 100.0)])
	_depots_section(gs)
	_routes_section(gs)
	_parking_section(gs)
	_section("Cómo funciona")
	_note_in(body, "Quien vive a más de %d m de su trabajo camina cansado (hasta −%d%% de productividad y menos felicidad). Si hay un paradero cerca de su casa y otro cerca del trabajo (a menos de %d m) en la misma ruta, toma el bus: rinde y está más contento, y tus negocios pueden contratar gente de lejos. Los ricos (desde el Automóvil, con ahorros de %s o más) van en auto si hay carretera entre la casa y el trabajo y un parqueadero a menos de %d m del trabajo. En la época moderna, un negocio sin parqueadero ni paradero de bus cerca rinde %d%% menos." % [
		int(TransitSim.sub("commute").get("walk_ok", 110)), int(float(TransitSim.sub("commute").get("walk_penalty_max", 0.1)) * 100.0), int(TransitSim.sub("stops").get("reach", 45)),
		Fmt.money(float(TransitSim.sub("commute").get("car_wealth", 300)) * gs.price_level()), int(TransitSim.sub("parking").get("reach", 40)),
		int(round((1.0 - float(TransitSim.sub("access").get("penalty", 0.95))) * 100.0))])


func _depots_section(gs) -> void:
	_section("Empresas de buses")
	var ds := TransitSim.depots(gs)
	var tech := str(TransitSim.sub("bus").get("tech", "transporte_publico"))
	if ds.is_empty():
		_note_in(body, "Construye una «Empresa de buses» (Construir → Negocios)%s." % ("" if gs.has_tech(tech) else "; antes investiga %s" % GameData.tech_label(tech)))
		return
	for d in ds:
		body.add_child(depot_box(gs, d, hud, refresh))


## Flota de una empresa de buses (también pestaña "Buses" del panel de edificio).
static func depot_box(gs, d: Dictionary, hud_node, on_change: Callable) -> Control:
	var v := VBoxContainer.new()
	var did := int(d["id"])
	var bs := TransitSim.buses_of(gs, did)
	var head := UIKit.label("%s — %d conductores · %d/%d buses · %d pasajeros por bus" % [gs.building_label(d), LogisticsSim.crew_size(gs, d), bs.size(), TransitSim.bus_garage(gs, d), TransitSim.bus_capacity(gs, d)], 14)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(head)
	var row := HBoxContainer.new()
	var why := TransitSim.buy_block_reason(gs, d)
	var buy := UIKit.button("Comprar bus (%s)" % Fmt.money(TransitSim.bus_price(gs)), func():
		var r := TransitSim.buy_bus(GameState, GameState.get_building(did))
		if hud_node:
			hud_node.toast(str(r["error"]) if r.has("error") else "Compraste %s." % str(r["bus"]["name"]), "jugador" if r.has("error") else "negocio")
		on_change.call())
	buy.disabled = why != ""
	buy.tooltip_text = why
	row.add_child(buy)
	var auto := UIKit.button("Ruta automática", func():
		var r := TransitSim.create_route(GameState, did, [], true)
		if hud_node:
			hud_node.toast(str(r["error"]) if r.has("error") else "%s creada." % str(r["route"]["name"]), "jugador" if r.has("error") else "negocio")
		on_change.call())
	auto.tooltip_text = "Recorre todos los paraderos unidos por carretera al depósito, del más cercano al más lejano (se actualiza sola)."
	row.add_child(auto)
	v.add_child(row)
	var pm: float = gs.price_mult()
	_note_in(v, "Cada bus: mantenimiento %s/día + combustible %s/km; un conductor por bus (contrátalos en el edificio)." % [Fmt.money2(float(TransitSim.sub("bus").get("upkeep", 1.0)) * pm), Fmt.money2(float(TransitSim.sub("bus").get("fuel_per_km", 3.0)) * pm)])
	var rts := []
	for r in TransitSim.routes(gs):
		if int(r["depot"]) == did:
			rts.append(r)
	for bus in bs:
		var bid := int(bus["id"])
		var br := HBoxContainer.new()
		var l := UIKit.label("• %s" % str(bus["name"]), 13)
		l.clip_text = true
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		br.add_child(l)
		var opt := OptionButton.new()
		opt.add_item("Sin ruta", 0)
		var sel := 0
		for i in range(rts.size()):
			opt.add_item(str(rts[i]["name"]), i + 1)
			if int(rts[i]["id"]) == int(bus.get("route", -1)):
				sel = i + 1
		opt.select(sel)
		opt.item_selected.connect(func(idx: int):
			TransitSim.assign_bus(GameState, bid, -1 if idx == 0 else int(rts[idx - 1]["id"]))
			on_change.call())
		br.add_child(opt)
		br.add_child(UIKit.button("Vender", func():
			var err := TransitSim.sell_bus(GameState, bid)
			if hud_node and err != "":
				hud_node.toast(err, "jugador")
			on_change.call(), 70))
		v.add_child(br)
	return v


func _routes_section(gs) -> void:
	_section("Rutas de bus")
	var status := TransitSim.all_route_status(gs)
	for r in TransitSim.routes(gs):
		var rid := int(r["id"])
		var st: Dictionary = status.get(rid, {})
		var names := []
		for sid in r["stops"]:
			names.append(str(TransitSim.get_stop(gs, int(sid)).get("name", "?")))
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.BG_LIGHT, 6, 8))
		var v := VBoxContainer.new()
		card.add_child(v)
		var info := UIKit.rich()
		var state_txt := "[color=#6c6]en servicio[/color] · %d buses · %d pasajeros/día · %d m" % [int(st.get("operating", 0)), int(st.get("capacity", 0)), int(st.get("length", 0.0))] if bool(st.get("ok", false)) else "[color=#e66]%s[/color]" % str(st.get("reason", ""))
		info.text = "[b]%s[/b]%s — %s\n%s\nEste mes: %d pasajeros, %s · mes anterior: %d, %s" % [str(r["name"]), " (automática)" if bool(r.get("auto", false)) else "",
			str(gs.get_building(int(r["depot"])).get("name", "")), " → ".join(names) + "\n" + state_txt,
			int(r.get("month_riders", 0)), Fmt.money(float(r.get("month_income", 0.0))), int(r.get("last_riders", 0)), Fmt.money(float(r.get("last_income", 0.0)))]
		v.add_child(info)
		v.add_child(UIKit.button("Quitar ruta", func():
			TransitSim.remove_route(GameState, rid)
			refresh()))
		body.add_child(card)
	# Ruta manual: elegir paraderos en orden.
	var ds := TransitSim.depots(gs)
	if ds.is_empty() or TransitSim.stops(gs).size() < 2:
		_note_in(body, "Pon al menos dos paraderos junto a carreteras empedradas o de cemento unidas a tu empresa de buses.")
		return
	if _new_depot < 0 or gs.get_building(_new_depot).is_empty():
		_new_depot = int(ds[0]["id"])
	_note_in(body, "Nueva ruta manual: clic en los paraderos en orden.")
	var grid := HFlowContainer.new()
	for s in TransitSim.stops(gs):
		var sid := int(s["id"])
		var idx := _new_stops.find(sid)
		var b := UIKit.button("%s%s" % ["%d. " % (idx + 1) if idx >= 0 else "", str(s["name"])], func():
			if _new_stops.has(sid):
				_new_stops.erase(sid)
			else:
				_new_stops.append(sid)
			refresh())
		grid.add_child(b)
	body.add_child(grid)
	var row := HBoxContainer.new()
	var create := UIKit.button("Crear ruta (%d paraderos)" % _new_stops.size(), func():
		var r := TransitSim.create_route(GameState, _new_depot, _new_stops.duplicate(), false)
		if r.has("error"):
			_msg(str(r["error"]))
		else:
			_msg("%s creada." % str(r["route"]["name"]), "negocio")
			_new_stops.clear()
		refresh())
	var why := TransitSim.route_block_reason(gs, _new_depot, _new_stops)
	create.disabled = why != ""
	create.tooltip_text = why
	row.add_child(create)
	row.add_child(UIKit.button("Limpiar", func():
		_new_stops.clear()
		refresh()))
	body.add_child(row)


func _parking_section(gs) -> void:
	_section("Parqueaderos")
	var ps := TransitSim.parkings(gs)
	if ps.is_empty():
		_note_in(body, "Construye un «Parqueadero» (Construir → Transporte, desde el Automóvil) a menos de %d m de tus negocios." % int(TransitSim.sub("parking").get("reach", 40)))
		return
	var use: Dictionary = TransitSim.state(gs)["parking_use"]
	for p in ps:
		var pl := UIKit.label("• %s — %d/%d autos hoy · %s este mes" % [gs.building_label(p), int(use.get(str(p["id"]), 0)), TransitSim.parking_capacity(gs, p), Fmt.money(BusinessSim.period_value(p, "month", "ventas"))], 13)
		pl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(pl)
