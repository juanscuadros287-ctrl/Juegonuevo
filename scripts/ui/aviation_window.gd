class_name AviationWindow
extends Control
## Fase 10: panel Aviación (pantalla completa). Aeropuertos (almacenes grandes) y hangares de cada país,
## flota de aviones de carga (comprar), vuelos en curso, rutas entre países y un formulario de envío
## (avión propio o vuelo comercial, manual o automático). Las rutas de avión DENTRO del país se crean en
## Logística → Transporte (entre dos aeropuertos).

signal message(text: String, category: String)

var body: VBoxContainer
var _built := false
# Formulario
var f_from_iso := ""
var f_to_iso := ""
var f_from := 0
var f_to := 0
var f_good := "madera"
var f_qty := 100.0
var f_mode := "comercial"
var f_auto := false
var f_every := 7


func setup() -> void:
	if _built:
		return
	_built = true
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
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
	UIKit.header(v, "logistics", "Aviación: aeropuertos, flota, vuelos y rutas", close, [UIKit.icon_button("refresh", refresh, "Actualizar")])
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	sc.add_child(body)
	EventBus.day_passed.connect(func(): if visible: refresh())


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


func refresh() -> void:
	if not visible or body == null:
		return
	var gs := GameState
	UIKit.clear(body)
	if not CountriesSim.ready(gs):
		return
	var ids: Array = CountriesSim.presence_ids(gs)
	if f_from_iso == "" or not ids.has(f_from_iso):
		f_from_iso = CountriesSim.active_id(gs) if ids.has(CountriesSim.active_id(gs)) else str(ids[0])
	if f_to_iso == "" or not ids.has(f_to_iso):
		f_to_iso = str(ids[1]) if ids.size() > 1 else f_from_iso
	var intro := UIKit.label("Entre países la mercancía solo va por avión: propio (hangar) o vuelo comercial. Al llegar se paga el arancel del destino, convertido con el tipo de cambio. Dentro del país, los aviones vuelan entre aeropuertos con las rutas de Logística → Transporte (más rápidas que los camiones y más caras). El aeropuerto es un almacén grande: los camiones distribuyen desde ahí.", 13, UIKit.TEXT_DIM)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(intro)
	if not gs.has_tech("aviacion"):
		body.add_child(UIKit.label("Requiere investigar: %s" % GameData.tech_label("aviacion"), 14, UIKit.BAD))
	_airports_and_fleet(gs, ids)
	_flights(gs)
	_routes(gs)
	_form(gs, ids)


func _airports_and_fleet(gs, ids: Array) -> void:
	var sec := UIKit.section(body, "Aeropuertos y flota por país", "logistics", true, "air_fleet")
	for iso in ids:
		var t := UIKit.rich()
		var s := "[b]%s[/b]\n" % CountriesSim.country_label(iso)
		var aps := AirSim.airports_in(gs, iso)
		if aps.is_empty():
			s += "  Sin aeropuerto propio (constrúyelo: Construir → Transporte → Aeropuerto).\n"
		for a in aps:
			s += "  Aeropuerto: %s%s · almacén %s / %s\n" % [a["label"], " (%s)" % a["municipio"] if str(a["municipio"]) != "" else "",
					Fmt.thousands(float(a["stock"])), Fmt.thousands(float(a["capacity"]))]
		var hs := AirSim.hangars_in(gs, iso)
		for h in hs:
			s += "  Hangar: %s · %d/%d aviones · %d tripulantes\n" % [h["label"], int(h["planes"]), int(h["garage"]), int(h["crew"])]
		for p in AirSim.planes_in(gs, iso):
			s += "    %s — %s · %s km · %d viajes\n" % [p["name"], "en vuelo" if bool(p["busy"]) else "libre", Fmt.thousands(float(p["km"])), int(p["trips"])]
		t.text = s
		sec.add_child(t)
		for h in hs:
			var hid := int(h["id"])
			var b := UIKit.button("Comprar avión de carga en %s (%s)" % [h["label"], Fmt.money(LogisticsSim.vehicle_price(gs, "avion"))], func(): _say(AirSim.buy_plane(gs, iso, hid)))
			sec.add_child(b)


func _flights(gs) -> void:
	var sec := UIKit.section(body, "Vuelos", "globe", true, "air_flights")
	var t := UIKit.rich()
	var s := ""
	var fl: Array = AirSim.st(gs).get("flights", [])
	for i in range(fl.size() - 1, -1, -1):
		var f: Dictionary = fl[i]
		var extra := ""
		if bool(f.get("delivered", false)):
			if float(f.get("tariff_money", 0.0)) > 0.0:
				extra = " · arancel %s" % Fmt.money2(float(f["tariff_money"]))
		else:
			extra = " · llega en %d días" % maxi(0, int(f["arrive"]) - gs.today())
		s += "#%d %s → %s · %s %s · %s · %s%s\n" % [int(f["id"]), CountriesSim.country_label(str(f["from_iso"])), CountriesSim.country_label(str(f["to_iso"])),
				Fmt.thousands(float(f["qty"])), GameData.good_label(str(f["good"])).to_lower(), "avión propio" if str(f["mode"]) == "avion" else "comercial",
				str(f.get("status", "")), extra]
	var stt: Dictionary = AirSim.st(gs).get("stats", {})
	s += "[color=#aab]Totales: %d vuelos, %s unidades · combustible %s · fletes %s · aranceles %s[/color]" % [int(float(stt.get("flights", 0.0))), Fmt.thousands(float(stt.get("units", 0.0))),
			Fmt.money(float(stt.get("fuel", 0.0))), Fmt.money(float(stt.get("fees", 0.0))), Fmt.money(float(stt.get("tariffs", 0.0)))]
	t.text = s if fl.size() > 0 else "Sin vuelos todavía.\n" + s
	sec.add_child(t)


func _routes(gs) -> void:
	var sec := UIKit.section(body, "Rutas automáticas entre países", "trade", true, "air_routes")
	var rs: Array = AirSim.st(gs).get("routes", [])
	if rs.is_empty():
		sec.add_child(UIKit.label("Sin rutas. Crea una abajo marcando «Automática».", 13, UIKit.TEXT_DIM))
	for r in rs:
		var h := HBoxContainer.new()
		var l := UIKit.label("%s → %s · %s %s cada %d días · %s · %s" % [CountriesSim.country_label(str(r["from_iso"])), CountriesSim.country_label(str(r["to_iso"])),
				Fmt.thousands(float(r["qty"])), GameData.good_label(str(r["good"])).to_lower(), int(r["every"]), "avión propio" if str(r["mode"]) == "avion" else "comercial", str(r.get("status", ""))], 13)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		h.add_child(l)
		var rid := int(r["id"])
		h.add_child(UIKit.danger(UIKit.button("Quitar", _remove_route.bind(rid))))
		sec.add_child(h)


func _form(gs, ids: Array) -> void:
	var sec := UIKit.section(body, "Enviar carga por avión", "plus", true, "air_form")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	sec.add_child(grid)
	grid.add_child(UIKit.label("Desde", 13, UIKit.TEXT_DIM))
	grid.add_child(_opt(ids.map(func(i): return CountriesSim.country_label(i)), ids.find(f_from_iso), _pick_from_iso.bind(ids)))
	var wf := AirSim.warehouses_in(gs, f_from_iso)
	grid.add_child(UIKit.label("almacén", 13, UIKit.TEXT_DIM))
	grid.add_child(_opt(wf.map(func(w): return str(w["label"])), _idx(wf, f_from), func(i): f_from = int(wf[i]["id"])))
	grid.add_child(UIKit.label("Hacia", 13, UIKit.TEXT_DIM))
	grid.add_child(_opt(ids.map(func(i): return CountriesSim.country_label(i)), ids.find(f_to_iso), _pick_to_iso.bind(ids)))
	var wt := AirSim.warehouses_in(gs, f_to_iso)
	grid.add_child(UIKit.label("almacén", 13, UIKit.TEXT_DIM))
	grid.add_child(_opt(wt.map(func(w): return str(w["label"])), _idx(wt, f_to), func(i): f_to = int(wt[i]["id"])))
	var goods: Array = LogisticsSim.transportable_goods()
	grid.add_child(UIKit.label("Bien", 13, UIKit.TEXT_DIM))
	grid.add_child(_opt(goods.map(func(g): return GameData.good_label(str(g))), goods.find(f_good), func(i): f_good = str(goods[i])))
	grid.add_child(UIKit.label("Cantidad", 13, UIKit.TEXT_DIM))
	grid.add_child(UIKit.spin(1, 5000, 1, f_qty, func(v): f_qty = v))
	var modes := ["comercial", "avion"]
	grid.add_child(UIKit.label("Medio", 13, UIKit.TEXT_DIM))
	grid.add_child(_opt(["Vuelo comercial (por unidad)", "Avión propio (hangar)"], modes.find(f_mode), func(i): f_mode = str(modes[i])))
	var auto := CheckBox.new()
	auto.text = "Automática cada"
	auto.button_pressed = f_auto
	auto.toggled.connect(func(on): f_auto = on)
	grid.add_child(auto)
	grid.add_child(UIKit.spin(1, 90, 1, f_every, func(v): f_every = int(v)))
	var km := AirSim.distance(gs, f_from_iso, f_from, f_to_iso, f_to)
	var intl := f_from_iso != f_to_iso
	var q := "Distancia %s km · " % Fmt.thousands(km)
	if f_mode == "comercial":
		var slot := AirSim.commercial_slot(gs, f_from_iso, f_to_iso)
		q += "flete %s por unidad · próxima salida en %d días con %s de espacio" % [Fmt.money2(AirSim.commercial_unit_fee(gs, km, intl)), int(slot["day"]) - gs.today(), Fmt.thousands(float(slot["free"]))]
	else:
		q += "combustible ida y vuelta %s · %d días de vuelo" % [Fmt.money(AirSim.plane_fuel(gs, km * 2.0)), AirSim.flight_days(km, intl)]
	if intl:
		q += " · arancel de %s %d %%" % [CountriesSim.country_label(f_to_iso), int(AirSim.tariff_rate(gs, f_to_iso) * 100.0)]
	var ql := UIKit.label(q, 13, UIKit.TEXT_DIM)
	ql.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sec.add_child(ql)
	sec.add_child(UIKit.primary(UIKit.button("Enviar / crear ruta", _submit)))


func _submit() -> void:
	var gs := GameState
	var opts := {"from_iso": f_from_iso, "from": f_from, "to_iso": f_to_iso, "to": f_to, "good": f_good, "qty": f_qty, "mode": f_mode, "every": f_every}
	var res := AirSim.create_route(gs, opts) if f_auto else AirSim.ship(gs, opts)
	if res.has("error"):
		_say(str(res["error"]))
	else:
		_say("Ruta creada" if f_auto else "Carga despachada")


func _pick_from_iso(i: int, ids: Array) -> void:
	f_from_iso = str(ids[i])
	f_from = 0
	refresh()


func _pick_to_iso(i: int, ids: Array) -> void:
	f_to_iso = str(ids[i])
	f_to = 0
	refresh()


func _remove_route(rid: int) -> void:
	AirSim.remove_route(GameState, rid)
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


func _idx(list: Array, id: int) -> int:
	for i in range(list.size()):
		if int(list[i]["id"]) == id:
			return i
	return 0


func _say(r: String) -> void:
	if r != "":
		message.emit(r, "info")
	refresh()
