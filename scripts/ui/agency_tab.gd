class_name AgencyTab
extends RefCounted
## Pestaña "Inmobiliaria" (sección H): comprar terrenos a nombre de la empresa, opciones de proyectos con
## presupuesto y venta o renta aproximada, y recompra negociada de apartamentos vendidos. Lógica en AgencySim.


static func applies(gs, b: Dictionary) -> bool:
	return gs.owned_by_player(b) and str(b.get("type", "")) == AgencySim.type_id()


static func build(gs, b: Dictionary, hud, on_change: Callable) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	var bid := int(b["id"])
	if not gs.is_active(b):
		v.add_child(UIKit.label("En obra: cuando abra podrás hacer proyectos inmobiliarios.", 12, UIKit.TEXT_DIM))
	# Proyectos
	v.add_child(UIKit.label("Proyectos (presupuesto y venta o renta aproximada)", 14, UIKit.ACCENT))
	var rows := []
	for p in AgencySim.project_options(gs):
		rows.append({"label": "%s (%s)" % [p["label"], p["kind"]], "units": int(p["units"]), "budget": float(p["budget"]), "price": float(p["unit_price"]),
			"rent": float(p["unit_rent"]), "margin": float(p["margin"]), "yield": float(p["yield"]),
			"_color": UIKit.TEXT_DIM if str(p["blocked"]) != "" else UIKit.TEXT})
	var dt := DataTable.new()
	dt.set_data([{"title": "Proyecto", "key": "label", "w": 1.8}, {"title": "Unid.", "key": "units", "w": 0.5, "fmt": "int"},
		{"title": "Presupuesto", "key": "budget", "w": 1.0, "fmt": "money"}, {"title": "Venta/u", "key": "price", "w": 0.9, "fmt": "money"},
		{"title": "Renta/u mes", "key": "rent", "w": 0.9, "fmt": "money2"}, {"title": "Margen venta", "key": "margin", "w": 0.9, "fmt": "trend"},
		{"title": "Renta anual", "key": "yield", "w": 0.8, "fmt": "pct"}], rows, 8)
	v.add_child(dt)
	v.add_child(_note("Los apartamentos y edificios se colocan desde Construir → Proyectos inmobiliarios o el panel Bienes raíces (con crédito). Se venden 1 a 1 según la demanda y cada unidad vendida pasa a ser del comprador."))
	# Terrenos a nombre de la empresa
	v.add_child(UIKit.label("Comprar terreno a nombre de la compañía", 14, UIKit.ACCENT))
	var opts := AgencySim.land_options(gs, 6)
	if opts.is_empty():
		v.add_child(_note("No hay territorios del Estado a la venta cerca de tus terrenos (explora el mapa o compra con licitación desde el minimapa)."))
	for o in opts:
		var row := HBoxContainer.new()
		var l := UIKit.label("Territorio (%d, %d) en %s · %s" % [int(o["cx"]), int(o["cy"]), o["municipio"], Fmt.money(float(o["price"]))], 12)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var cx := int(o["cx"])
		var cy := int(o["cy"])
		var btn := UIKit.button("Comprar", func():
			var err := AgencySim.buy_land(GameState, GameState.get_building(bid), cx, cy)
			if hud:
				hud.toast(err if err != "" else "Terreno comprado a nombre de la inmobiliaria.", "jugador" if err != "" else "negocio")
			on_change.call(), 90)
		btn.disabled = str(o["reason"]) != ""
		btn.tooltip_text = str(o["reason"])
		row.add_child(btn)
		v.add_child(row)
	# Recompra negociada
	var sold := []
	for hb in gs.buildings:
		if gs.owned_by_player(hb) and RealEstateSim.has_units(hb):
			for u in hb["units"]:
				if str(u.get("status", "")) == "vendida":
					sold.append([hb, u])
	if not sold.is_empty():
		v.add_child(UIKit.label("Recomprar apartamentos vendidos (negociación con el dueño)", 14, UIKit.ACCENT))
		for pair in sold.slice(0, 8):
			var hb: Dictionary = pair[0]
			var u: Dictionary = pair[1]
			var hid := int(hb["id"])
			var uid := int(u["id"])
			var row := HBoxContainer.new()
			var val := AgencySim.unit_value(gs, hb, u)
			var l := UIKit.label("%s %s · dueño %s · vale %s" % [gs.building_label(hb), u.get("code", ""), gs.person_name(int(u.get("owner_id", -1))), Fmt.money(val)], 12)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(l)
			var sp := UIKit.spin(1, 1e9, 10, snappedf(val * 1.1, 10.0), func(_v): pass, 110)
			row.add_child(sp)
			row.add_child(UIKit.button("Preguntar", func():
				var B: Dictionary = GameState.get_building(hid)
				var p := AgencySim.ask_unit(GameState, B, _unit(B, uid))
				if hud and not p.is_empty():
					hud.toast("El dueño: %s (pide unos %s)." % [str(p["label"]).to_lower(), Fmt.money(float(p["ask"]))] if str(p["kind"]) != "se_niega" else "El dueño no quiere vender.", "negocio"), 80))
			row.add_child(UIKit.button("Ofertar", func():
				var B: Dictionary = GameState.get_building(hid)
				var r := AgencySim.rebuy_unit(GameState, B, _unit(B, uid), sp.value)
				if hud:
					hud.toast(str(r["text"]), "negocio" if bool(r.get("ok", false)) else "jugador")
				on_change.call(), 80))
			v.add_child(row)
	return v


static func _unit(b: Dictionary, uid: int) -> Dictionary:
	for u in b.get("units", []):
		if int(u["id"]) == uid:
			return u
	return {}


static func _note(t: String) -> Label:
	var l := UIKit.label(t, 12, UIKit.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 320
	return l
