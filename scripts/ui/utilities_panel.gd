class_name UtilitiesPanel
extends VBoxContainer
## Panel "Servicios públicos" (docs/REDES.md): trazar tendido aéreo, cable subterráneo y tubería;
## vista de capa (conectados en verde, sin servicio en rojo); generación vs. demanda por red,
## cobertura, clientes, tarifas e ingresos mensuales de electricidad y agua; pozos comunitarios.

signal closed
signal message(text: String, category: String)

var hud: Hud
var tabs: TabContainer
var _pages := {}
var _live := {}
var _timer := 0.0


func setup(p_hud: Hud) -> void:
	hud = p_hud
	add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	add_child(head)
	var t := UIKit.label("Servicios públicos", 20, UIKit.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UIKit.button("✕", func(): closed.emit(), 32))
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(tabs)
	for name in ["Electricidad", "Agua"]:
		var sc := ScrollContainer.new()
		sc.name = name
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 6)
		sc.add_child(v)
		tabs.add_child(sc)
		_pages[name] = v


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
	_build_power()
	_build_water()
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


func _vis() -> UtilitiesVisuals:
	return UtilitiesVisuals.instance


func _trace_button(v: Control, kind: String) -> void:
	var gs = GameState
	var tech := str(GridSim.kind_def(kind).get("tech", ""))
	var ok: bool = gs.has_tech(tech)
	var btn := UIKit.button("%s (%s/m)" % [str(GridSim.kind_def(kind).get("action", kind)), Fmt.money2(GridSim.cost_per_m(gs, kind))], func():
		if _vis():
			_vis().start_trace(kind)
			_msg("Trazado: clic en el inicio y clic en el final de cada tramo (sigue desde el último punto). Clic derecho o Esc para terminar.", "info"))
	btn.disabled = not ok
	btn.tooltip_text = "Conecta los edificios a menos de %d m de su borde." % int(GridSim.reach(GridSim.kind_layer(kind))) if ok else "Requiere investigar: %s" % GameData.tech_label(tech)
	v.add_child(btn)


func _layer_button(v: Control, lay: String) -> void:
	var b := UIKit.button("Ver / ocultar capa de %s" % ("electricidad" if lay == GridSim.POWER else "agua"), func():
		if _vis():
			_vis().toggle_layer(lay))
	b.tooltip_text = "Verde: conectado · rojo: lo necesita y no lo tiene · amarillo/azul: centrales y plantas."
	v.add_child(b)


func _tariff_row(v: Control, lay: String) -> void:
	var c := GridSim.layer_cfg(lay)
	var row := HBoxContainer.new()
	row.add_child(UIKit.label("Tarifa (× precio de mercado):", 13))
	row.add_child(UIKit.spin(float(c.get("tariff_min", 0.5)), float(c.get("tariff_max", 2.5)), 0.05, GridSim.tariff(GameState, lay), func(val):
		GridSim.set_tariff(GameState, lay, val)
		_update_live(), 90))
	v.add_child(row)


# --- Electricidad --------------------------------------------------------------------------------

func _build_power() -> void:
	var v := _page("Electricidad")
	var gs = GameState
	_section(v, "Red eléctrica")
	_live_label(v, "power")
	for kind in GridSim.kinds_of(GridSim.POWER):
		_trace_button(v, kind)
	_layer_button(v, GridSim.POWER)
	var undo := UIKit.button("Quitar último tramo (sin reembolso)", func():
		if GridSim.remove_last(GameState, GridSim.POWER):
			_update_live())
	v.add_child(undo)
	_tariff_row(v, GridSim.POWER)
	_section(v, "Redes")
	_live_label(v, "power_nets")
	_note(v, "Tiende postes y cable (desde el Dínamo) o cable subterráneo (Redes eléctricas: más caro, casi sin pérdidas y no lo tumban las tormentas) desde tus centrales hasta fábricas y casas. Un edificio queda conectado si un tramo pasa a menos de %d m de su borde; paga una acometida única (la paga el dueño). Cada red reparte solo la energía de SUS centrales; si falta, compra a la red regional únicamente la red que toca la plaza o el camino de la ruta comercial (con una ruta comercial terminada). Las industrias eléctricas y automatizadas NO producen sin electricidad; desde %s los apartamentos, edificios y rascacielos exigen conexión (si no, pierden renta, valor e inquilinos). Los hogares conectados pagan su factura cada mes a tus centrales." % [int(GridSim.reach(GridSim.POWER)), GameData.tech_label(str(GridSim.grid_cfg().get("home_tech", "electricidad")))])
	if not EnergySim.grid_active(gs):
		_note(v, "Aún no hay red: investiga %s." % GameData.tech_label(str(EnergySim.cfg().get("grid_tech", "dinamo"))))


func _power_text() -> String:
	var gs = GameState
	var sm := GridSim.summary(gs)
	var es := EnergySim.summary(gs)
	var s := ""
	if bool(sm["legacy"]):
		s += "[color=#e9b949]Período de gracia hasta el %s: la red funciona como antes (global). Tiende los cables antes.[/color]\n" % TimeManager.date_from_day(int(sm["legacy_until"]), TimeManager.start_year())
	for kind in GridSim.kinds_of(GridSim.POWER):
		s += "• %s: %s m\n" % [GridSim.kind_label(kind), Fmt.thousands(GridSim.total_length(gs, kind))]
	if int(sm["broken"]) > 0:
		s += "[color=#e66]%d tramo(s) caídos por tormenta (en reparación)[/color]\n" % int(sm["broken"])
	s += "Generación: %.0f kW/día · demanda de negocios: %.0f · red regional: %.0f · desperdicio: %.0f\n" % [float(es["supply_day"]), float(es["demand_day"]), float(es["grid_day"]), float(es["wasted_day"])]
	s += "Hogares con luz: %.0f · sin luz: %.0f · casas conectadas: %d\n" % [float(es["homes_powered"]), float(es["homes_unpowered"]), int(sm["power_homes"])]
	s += "Precio: %s/u · tarifa ×%.2f = [b]%s/u[/b] · red regional %s/u\n" % [Fmt.money2(float(es["price"])), float(sm["tariff_power"]), Fmt.money2(float(es["price"]) * float(sm["tariff_power"])), Fmt.money2(float(es["grid_price"]))]
	s += "Mes anterior: facturas cobradas [color=#6c6]%s[/color] (%d clientes, %d cortados) · a la red regional %s · mantenimiento %s · reparaciones %s\n" % [
		Fmt.money(float(sm["income_power"])), int(sm["customers_power"]), int(sm["cut_power"]), Fmt.money(float(sm["regional_power"])), Fmt.money(float(sm["upkeep"])), Fmt.money(float(sm["repairs"]))]
	s += "Facturado este mes (pendiente de cobro): %s" % Fmt.money(float(sm["pending_power"]))
	return s


func _power_nets_text() -> String:
	var nets: Array = GridSim.summary(GameState)["power_nets"]
	if nets.is_empty():
		return "[color=#aaa]Ninguna red con consumo o generación todavía.[/color]"
	var s := ""
	for n in nets:
		var cov := float(n["coverage"])
		var col := "#6c6" if cov >= 0.99 else ("#e9b949" if cov >= 0.5 else "#e66")
		var name := "Red global (gracia)" if int(n["id"]) == GridSim.LEGACY else "Red %d" % int(n["id"])
		s += "[b]%s[/b]%s · %d m\n" % [name, " · [color=#9cf]entrada regional[/color]" if bool(n["tie"]) else "", int(n["length"])]
		s += "   Generación %.0f (%.0f tras %.1f%% de pérdidas) · demanda %.0f · [color=%s]cobertura %d%%[/color]\n" % [float(n["supply"]), float(n["eff"]), float(n["loss"]) * 100.0, float(n["demand"]), col, int(round(cov * 100.0))]
		s += "   %d central(es) · %d negocio(s) · %d hogares (%.0f u./día) · regional %.0f u.\n" % [int(n["plants"]), int(n["users"]), int(n["homes"]), float(n["home_units"]), float(n["grid_units"])]
	return s


# --- Agua ----------------------------------------------------------------------------------------

func _build_water() -> void:
	var v := _page("Agua")
	var gs = GameState
	_section(v, "Agua del pueblo")
	_live_label(v, "water")
	for t in ["pozo_comunitario", "toma_rio", "planta_agua"]:
		var type_id: String = t
		var reason := ConstructionSim.build_block_reason(gs, type_id, "normal")
		var btn := UIKit.button("Construir %s (%s)" % [str(GameData.building_def(type_id).get("label", type_id)).to_lower(), Fmt.money(float(ConstructionSim.cost_for(gs, type_id, 1, false)["total"]))], func():
			EventBus.build_mode_requested.emit(type_id, "normal"))
		btn.disabled = reason != ""
		btn.tooltip_text = reason if reason != "" else str(GameData.building_def(type_id).get("description", ""))
		v.add_child(btn)
	for kind in GridSim.kinds_of(GridSim.WATER):
		_trace_button(v, kind)
	_layer_button(v, GridSim.WATER)
	v.add_child(UIKit.button("Quitar último tramo (sin reembolso)", func():
		if GridSim.remove_last(GameState, GridSim.WATER):
			_update_live()))
	_tariff_row(v, GridSim.WATER)
	_section(v, "Redes de tubería")
	_live_label(v, "water_nets")
	_note(v, "Al principio el pueblo bebe de pozos comunitarios gratis (cada pozo alcanza para ~%d personas; con más gente escasea el agua: peor calidad y más enfermedades). Con un río o lago cerca, la Toma de río vende agua repartida a pie o en carreta. Con %s, la Planta de agua manda agua por tuberías subterráneas: las casas conectadas (acometida única) pagan su factura mensual a tu planta, se enferman menos y la vivienda vale más. Desde entonces los apartamentos y edificios altos exigen tubería." % [int(GridSim.water_cfg().get("people_per_well", 80)), GameData.tech_label(str(GridSim.kind_def("tuberia").get("tech", "potabilizacion")))])


func _water_text() -> String:
	var gs = GameState
	var ws := WaterSim.summary(gs)
	var sm := GridSim.summary(gs)
	var f := float(ws["well_factor"])
	var col := "#6c6" if f >= 0.99 else ("#e9b949" if f >= 0.6 else "#e66")
	var s := "Pozos comunitarios: %d (para ~%d personas) · uso: %.0f · [color=%s]abasto %d%%[/color]\n" % [int(ws["wells"]), int(ws["well_capacity"]), float(ws["well_users"]), col, int(round(f * 100.0))]
	s += "Vendedores de agua (aguatero/toma de río): %d%s\n" % [int(ws["sellers"]), "" if bool(ws["fresh_water"]) else " · [color=#aaa]este mapa no tiene río para la toma[/color]"]
	s += "Tubería: %s m · plantas de agua: %d · casas conectadas: %d\n" % [Fmt.thousands(GridSim.total_length(gs, "", GridSim.WATER)), int(ws["plants"]), int(sm["water_homes"])]
	s += "Precio por tubería: [b]%s/u[/b] (tarifa ×%.2f) · agua servida el mes pasado: %.0f u.\n" % [Fmt.money2(float(ws["price"])), float(sm["tariff_water"]), float(ws["piped_units"])]
	s += "Mes anterior: facturas cobradas [color=#6c6]%s[/color] (%d clientes, %d cortados) · pendiente este mes: %s" % [Fmt.money(float(sm["income_water"])), int(sm["customers_water"]), int(sm["cut_water"]), Fmt.money(float(sm["pending_water"]))]
	return s


func _water_nets_text() -> String:
	var ws := WaterSim.summary(GameState)
	var nets: Dictionary = ws["nets"]
	if nets.is_empty():
		return "[color=#aaa]Ninguna planta de agua conectada a tubería.[/color]"
	var s := ""
	for n in nets:
		var d: Dictionary = nets[n]
		s += "[b]Red %d[/b] · %d planta(s) · produce %.0f u./día · %d casas conectadas\n" % [int(n), int(d["plants"]), float(d["production"]), int(d["homes"])]
	return s


func _update_live() -> void:
	var map := {"power": _power_text, "power_nets": _power_nets_text, "water": _water_text, "water_nets": _water_nets_text}
	for k in _live.keys():
		var r = _live[k]
		if not is_instance_valid(r):
			_live.erase(k)
			continue
		(r as RichTextLabel).text = map[k].call()
