class_name TourismPanel
extends VBoxContainer
## Panel "Turismo y publicidad" (Fase 8): estado del turismo, atracciones y hoteles con su
## precio de entrada/noche, y campañas de publicidad (crear, estimar y cancelar).

signal closed
signal message(text: String, category: String)

var hud: Hud
var tabs: TabContainer
var summary_box: VBoxContainer
var places_box: VBoxContainer
var ads_box: VBoxContainer
var _ch_opt: OptionButton
var _target_opt: OptionButton
var _months: SpinBox
var _estimate: RichTextLabel


func setup(p_hud: Hud) -> void:
	hud = p_hud
	add_theme_constant_override("separation", 8)
	UIKit.header(self, "tourism", "Turismo y publicidad", func(): closed.emit(), [UIKit.icon_button("refresh", func(): refresh(), "Actualizar", "", 16)])
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(tabs)
	summary_box = _tab("Turismo")
	places_box = _tab("Atracciones")
	ads_box = _tab("Publicidad")


func _tab(tab_name: String) -> VBoxContainer:
	var sb := UIKit.scroll_box(Vector2(0, 200))
	sb["scroll"].name = tab_name
	sb["scroll"].size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(sb["scroll"])
	return sb["box"]


func refresh() -> void:
	if tabs == null:
		return
	_refresh_summary()
	_refresh_places()
	_refresh_ads()


func _msg(text: String, cat := "negocio") -> void:
	if text != "":
		message.emit(text, cat)


func _note(parent: Control, text: String, size := 12) -> void:
	var l := UIKit.label(text, size, UIKit.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 360
	parent.add_child(l)


# --- Resumen -------------------------------------------------------------------------------------

func _refresh_summary() -> void:
	UIKit.clear(summary_box)
	var gs := GameState
	TourismSim.init_state(gs)
	var conns: Array = TradeSim.connected_towns(gs)
	var bd := TourismSim.breakdown(gs)
	var s := ""
	if conns.is_empty():
		s += "[color=#e88]Sin conexiones con otros pueblos no llegan turistas.[/color] Abre rutas comerciales con otros pueblos (panel de Comercio): por ellas llegan los visitantes.\n\n"
	else:
		s += "[b]Conexiones[/b] (%d)\n" % conns.size()
		for c in conns:
			if c is Dictionary:
				s += "• %s — %s, %d km · aporte %.2f\n" % [str(c.get("name", c.get("town_id", "?"))), str(c.get("transport", "camino")),
					int(TourismSim.connection_distance(c)), TourismSim.connection_factor(c)]
		s += "\n"
	s += "[b]Atractivo turístico: %.0f[/b]\n" % float(bd["total"])
	s += "Atracciones %.0f · hospedaje %.0f · obras públicas %.0f · variedad ×%.2f\n" % [float(bd["attractions"]), float(bd["hotels"]), float(bd["public"]), float(bd["diversity"])]
	s += "Felicidad ×%.2f · seguridad ×%.2f · limpieza ×%.2f · publicidad ×%.2f · temporada ×%.2f · clima ×%.2f\n\n" % [
		float(bd["happiness"]), float(bd["safety"]), float(bd["pollution"]), float(bd["ads"]), float(bd["season"]), float(bd["weather"])]
	s += "Turistas nuevos esperados: [b]%.1f por día[/b] · pasan la noche: %s\n" % [TourismSim.expected_tourists(gs), Fmt.pct(TourismSim.overnight_share(gs) * 100.0)]
	s += "Presupuesto de cada turista: %s/día (%s en tus comercios)\n" % [Fmt.money2(TourismSim.budget_per_tourist(gs)), Fmt.pct(float(TourismSim.cfg().get("shop_share", 0.35)) * 100.0)]
	var today: Dictionary = gs.tourism.get("today", {})
	s += "Hoy: %d llegaron · %d en el pueblo · %d huéspedes nuevos\n\n" % [int(today.get("visitors", 0)), int(today.get("present", 0)), int(today.get("overnight", 0))]
	for pair in [["Este mes", gs.tourism.get("month", {})], ["Mes anterior", gs.tourism.get("last_month", {})]]:
		var m: Dictionary = pair[1]
		var inc := float(m.get("tickets", 0.0)) + float(m.get("lodging", 0.0)) + float(m.get("shops", 0.0)) + float(m.get("media", 0.0))
		s += "[b]%s[/b]: %d visitantes · %d sin cama (no vinieron)\n" % [pair[0], int(m.get("visitors", 0)), int(m.get("lost_no_bed", 0))]
		s += "Entradas %s · alojamiento %s · comercio %s · medios %s → [color=#6c6]%s[/color] · publicidad −%s\n" % [
			Fmt.money(float(m.get("tickets", 0.0))), Fmt.money(float(m.get("lodging", 0.0))), Fmt.money(float(m.get("shops", 0.0))),
			Fmt.money(float(m.get("media", 0.0))), Fmt.money(inc), Fmt.money(float(m.get("ads_cost", 0.0)))]
	s += "\nTotal histórico: %d visitantes, %s traídos de afuera.\n" % [int(gs.tourism.get("total_visitors", 0)), Fmt.money(float(gs.tourism.get("total_income", 0.0)))]
	var rl := UIKit.rich()
	rl.text = s
	summary_box.add_child(rl)
	_note(summary_box, "Los turistas llegan solo por las conexiones con otros pueblos, más cuanto mejor sea el transporte y más cerca esté el pueblo. Vienen por tus atracciones (y las obras públicas), se quedan si hay camas, y prefieren pueblos felices, seguros y limpios. Pagan entradas, alojamiento y compran en tus tabernas y tiendas: es dinero nuevo para la economía del pueblo.")


# --- Atracciones y hoteles ------------------------------------------------------------------------

func _refresh_places() -> void:
	UIKit.clear(places_box)
	var gs := GameState
	var any := false
	for k in ["atraccion", "hotel", "medio"]:
		var list := TourismSim.player_list(gs, k)
		if list.is_empty():
			continue
		any = true
		places_box.add_child(UIKit.label({"atraccion": "Tus atracciones", "hotel": "Tu hospedaje", "medio": "Tus medios"}[k], 16, UIKit.ACCENT))
		for b in list:
			places_box.add_child(_place_card(b, k))
	if not any:
		_note(places_box, "Aún no tienes atracciones ni hoteles. Constrúyelos abajo o desde Construir (sector Turismo).", 13)
	places_box.add_child(UIKit.label("Construir", 16, UIKit.ACCENT))
	for type_id in GameData.sorted_ids(GameData.businesses):
		var def := GameData.building_def(type_id)
		if str(def.get("tourism", "")) == "":
			continue
		var ld := GameData.level_def(type_id, 1)
		var reason := ConstructionSim.build_block_reason(gs, type_id)
		var row := HBoxContainer.new()
		var lbl := UIKit.label("%s — %s" % [str(ld.get("label", type_id)), Fmt.money(float(ConstructionSim.cost_for(gs, type_id, 1, false)["total"]))], 13)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.tooltip_text = str(def.get("description", ""))
		row.add_child(lbl)
		var btn := UIKit.button("Colocar" if reason == "" else reason, func(): EventBus.build_mode_requested.emit(type_id, "normal"))
		btn.disabled = reason != ""
		btn.clip_text = true
		btn.custom_minimum_size.x = 150
		row.add_child(btn)
		places_box.add_child(row)


func _place_card(b: Dictionary, k: String) -> Control:
	var gs := GameState
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.BG_LIGHT, 6, 8))
	var v := VBoxContainer.new()
	panel.add_child(v)
	var ld: Dictionary = gs.level_def(b)
	var bid := int(b["id"])
	var status := str(b["status"])
	var staff := TourismSim.staff(gs, b)
	var unit: String = {"atraccion": "visitas/día", "hotel": "camas", "medio": "avisos/día"}[k]
	v.add_child(UIKit.label("%s (%s)" % [gs.building_label(b), str(ld.get("label", ""))], 15))
	var info := "Personal %d/%d · capacidad ≈ %d %s · ventas mes anterior %s" % [staff, int(ld.get("jobs", 0)),
		int(TourismSim.daily_capacity(gs, b)), unit, Fmt.money(BusinessSim.period_value(b, "last_month", "ventas"))]
	if k != "medio":
		info += " · atractivo %.0f" % TourismSim.attraction_points(gs, b)
	if k == "hotel":
		info += " · huéspedes %d" % TourismSim.guests_in(gs, bid)
	if k == "medio":
		info += " · descuento en tus campañas %s" % Fmt.pct(float(ld.get("ad_discount", 0.0)) * 100.0)
	if status != "activo":
		info += " · [%s]" % status
	elif staff == 0:
		info += " · SIN PERSONAL (cerrado)"
	_note(v, info)
	var row := HBoxContainer.new()
	row.add_child(UIKit.label({"atraccion": "Entrada:", "hotel": "Noche:", "medio": "Aviso:"}[k], 14))
	var auto := CheckBox.new()
	var spin := UIKit.spin(0.01, BusinessSim.max_price(gs, b), 0.01, float(b["price"]), func(val):
		var bb: Dictionary = GameState.get_building(bid)
		if bb.is_empty() or is_equal_approx(float(bb["price"]), val):
			return
		bb["auto_price"] = false
		auto.set_pressed_no_signal(false)
		BusinessSim.set_price(GameState, bb, val))
	row.add_child(spin)
	auto.text = "automático"
	auto.button_pressed = bool(b.get("auto_price", false))
	auto.toggled.connect(func(on):
		var bb: Dictionary = GameState.get_building(bid)
		if not bb.is_empty():
			bb["auto_price"] = on)
	row.add_child(auto)
	row.add_child(UIKit.button("Ficha", func(): hud.open_building(bid)))
	v.add_child(row)
	var ref := TourismSim.ticket_ref(gs, b) if k != "medio" else EconomySim.market_price(gs, "publicidad")
	_note(v, "Referencia %s · pagan hasta %s; por encima de la referencia van menos." % [Fmt.money2(ref), Fmt.money2(ref * float(TourismSim.cfg().get("willing_markup", 1.6)))])
	return panel


# --- Publicidad -----------------------------------------------------------------------------------

func _refresh_ads() -> void:
	UIKit.clear(ads_box)
	var gs := GameState
	ads_box.add_child(UIKit.label("Nueva campaña", 16, UIKit.ACCENT))
	var locked := []
	_ch_opt = OptionButton.new()
	for ch in AdvertisingSim.channel_ids():
		var r := AdvertisingSim.channel_block_reason(gs, ch)
		if r == "":
			_ch_opt.add_item(AdvertisingSim.channel_label(ch))
			_ch_opt.set_item_metadata(_ch_opt.item_count - 1, ch)
		else:
			locked.append("%s (%s)" % [AdvertisingSim.channel_label(ch), r.to_lower()])
	_ch_opt.select(_ch_opt.item_count - 1)
	_ch_opt.item_selected.connect(func(_i): _update_estimate())
	var r1 := HBoxContainer.new()
	r1.add_child(UIKit.label("Medio:"))
	r1.add_child(_ch_opt)
	ads_box.add_child(r1)
	_target_opt = OptionButton.new()
	for t in ["todos", "turismo"]:
		_target_opt.add_item(AdvertisingSim.target_label(gs, t))
		_target_opt.set_item_metadata(_target_opt.item_count - 1, t)
	for b in gs.player_buildings("negocio"):
		if gs.building_def(b).has("service") or str(gs.building_def(b).get("product", "")) in ["construccion", "investigacion", "educacion", "credito"]:
			continue
		_target_opt.add_item(gs.building_label(b))
		_target_opt.set_item_metadata(_target_opt.item_count - 1, str(int(b["id"])))
	_target_opt.item_selected.connect(func(_i): _update_estimate())
	var r2 := HBoxContainer.new()
	r2.add_child(UIKit.label("Anunciar:"))
	r2.add_child(_target_opt)
	ads_box.add_child(r2)
	var r3 := HBoxContainer.new()
	r3.add_child(UIKit.label("Duración (meses):"))
	_months = UIKit.spin(1, float(AdvertisingSim.cfg().get("max_months", 24)), 1, 3, func(_v): _update_estimate(), 80)
	r3.add_child(_months)
	ads_box.add_child(r3)
	_estimate = UIKit.rich()
	ads_box.add_child(_estimate)
	ads_box.add_child(UIKit.button("Lanzar campaña", func():
		if _ch_opt.item_count == 0:
			return
		var ch := str(_ch_opt.get_item_metadata(_ch_opt.selected))
		var target := str(_target_opt.get_item_metadata(_target_opt.selected))
		var err := AdvertisingSim.start_campaign(GameState, ch, target, int(_months.value))
		_msg(err if err != "" else "Campaña lanzada.", "jugador" if err != "" else "negocio")
		refresh()))
	if not locked.is_empty():
		_note(ads_box, "Bloqueados: " + ", ".join(locked))
	_update_estimate()
	ads_box.add_child(HSeparator.new())
	ads_box.add_child(UIKit.label("Campañas activas", 16, UIKit.ACCENT))
	var list := AdvertisingSim.campaigns(gs)
	if list.is_empty():
		_note(ads_box, "No tienes campañas activas.", 13)
	for c in list:
		var row := HBoxContainer.new()
		var days_left := int(c["end_day"]) - gs.today()
		var lbl := UIKit.label("%s → %s · %s/mes · +%s demanda · +%s turismo · quedan %d días" % [AdvertisingSim.channel_label(str(c["channel"])),
			AdvertisingSim.target_label(gs, str(c["target"])), Fmt.money(float(c["cost"])), Fmt.pct(float(c["demand"]) * 100.0),
			Fmt.pct(float(c["tourism"]) * 100.0), maxi(0, days_left)], 13)
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var cid := int(c["id"])
		row.add_child(UIKit.button("Cancelar", func():
			_msg(AdvertisingSim.cancel_campaign(GameState, cid))
			refresh()))
		ads_box.add_child(row)
	var media := TourismSim.player_list(gs, "medio")
	_note(ads_box, "Efectos combinados (con rendimientos decrecientes): demanda de todos tus negocios ×%.2f · turistas ×%.2f." % [
		AdvertisingSim.demand_mult(gs, {"id": -1}), AdvertisingSim.tourism_mult(gs)])
	if media.is_empty():
		_note(ads_box, "Con tu propio periódico, emisora o canal de TV (sector Medios) tus campañas cuestan menos y vendes espacios publicitarios a los pueblos conectados.")


func _update_estimate() -> void:
	if _estimate == null:
		return
	if _ch_opt.item_count == 0 or _target_opt.item_count == 0:
		_estimate.text = ""
		return
	var ch := str(_ch_opt.get_item_metadata(_ch_opt.selected))
	var target := str(_target_opt.get_item_metadata(_target_opt.selected))
	var months := int(_months.value)
	var e := AdvertisingSim.estimate(GameState, ch, target, months)
	var s := "Costo: [b]%s/mes[/b] (total %s)%s\n" % [Fmt.money(float(e["cost_month"])), Fmt.money(float(e["total"])),
		" · descuento de tu medio %s" % Fmt.pct(float(e["discount"]) * 100.0) if float(e["discount"]) > 0.0 else ""]
	s += "Efecto estimado: +%s demanda · +%s turistas" % [Fmt.pct(float(e["demand_pct"])), Fmt.pct(float(e["tourism_pct"]))]
	if float(e["extra_sales_month"]) > 0.0:
		s += " · ≈ %s/mes en ventas extra" % Fmt.money(float(e["extra_sales_month"]))
	if float(e["extra_tourists_day"]) > 0.0:
		s += " · ≈ %.1f turistas/día más (≈ %s/mes)" % [float(e["extra_tourists_day"]), Fmt.money(float(e["extra_tourism_month"]))]
	s += "\n[color=#aaa]%s[/color]" % str(AdvertisingSim.channel(ch).get("description", ""))
	_estimate.text = s
