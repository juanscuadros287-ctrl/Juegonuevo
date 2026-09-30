class_name HiringPanel
extends Control
## Contrataciones (Empresas → Contrataciones): ventana con tres pestañas.
##   Vacantes: por empresa (negocios, transporte con conductores y cargadores, servicios públicos): puesto,
##             ocupados/total, sueldo, estado, publicar/pausar y auto-contratación.
##   Postulantes: bandeja con fichas (retrato, edad, educación, profesión, oficio, habilidad, sueldo pedido,
##             empleo anterior), filtros y Contratar / Rechazar / Contraofertar.
##   Personal: todos tus empleados por empresa: sueldo, experiencia, felicidad, riesgo de irse, subir
##             sueldo y despedir.
## `building_section()` arma la misma gestión para la pestaña Empleados de un edificio.
## Solo interfaz: la lógica está en HiringSim.

signal message(text: String, category: String)

const TABS := ["Vacantes", "Postulantes", "Personal"]
const RISK_COLORS := {"alto": Color(1.0, 0.45, 0.4), "medio": Color(1.0, 0.78, 0.35), "bajo": Color(0.55, 0.85, 0.55)}

var hud: Node
var tabs: TabContainer
var _boxes: Array = []
var _built := false
var _badge: Label
var _badge_t := 0.0
# Filtros de la bandeja
var f_bid := -1
var f_only_ok := false
var f_sort := 0


func setup(p_hud: Node = null) -> void:
	if _built:
		return
	_built = true
	hud = p_hud
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: close())
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
	UIKit.header(v, "employment", "Contrataciones: vacantes, postulantes y personal", close, [UIKit.icon_button("refresh", refresh, "Actualizar")])
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tabs)
	for t in TABS:
		var sc := ScrollContainer.new()
		sc.name = t
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", 8)
		sc.add_child(box)
		tabs.add_child(sc)
		_boxes.append(box)
	tabs.tab_changed.connect(func(_i): refresh())
	EventBus.day_passed.connect(func(): if visible and not _editing(): refresh())
	_attach_badge()


## Contador de postulantes nuevos sobre el botón de la categoría Empresas.
func _attach_badge() -> void:
	if hud == null or not ("_cat_buttons" in hud):
		return
	var btn: Button = hud._cat_buttons.get("empresas")
	if btn == null:
		return
	_badge = UIKit.label("", 10, Color(1, 1, 1))
	_badge.add_theme_stylebox_override("normal", UIKit._flat(Color(0.85, 0.3, 0.25), 7, 4, 0))
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.position = Vector2(24, 0)
	_badge.visible = false
	btn.add_child(_badge)


## Sufijo para el menú desplegable: " (3)".
static func badge_suffix() -> String:
	if not GameState.running:
		return ""
	var n := HiringSim.new_count(GameState)
	return " (%d)" % n if n > 0 else ""


func _process(delta: float) -> void:
	_badge_t -= delta
	if _badge == null or _badge_t > 0.0:
		return
	_badge_t = 0.5
	var n := HiringSim.new_count(GameState) if GameState.running else 0
	_badge.visible = n > 0
	_badge.text = str(n) if n < 100 else "99+"


func open(tab := 0) -> void:
	setup(hud)
	var was := visible
	visible = true
	tabs.current_tab = clampi(tab, 0, TABS.size() - 1)
	if not was:
		UIKit.animate_in(self, Vector2.ZERO, 0.16)
	refresh()


func close() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _editing() -> bool:
	var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	return f != null and (f is LineEdit or f is SpinBox) and is_ancestor_of(f)


func _msg(text: String, cat := "info") -> void:
	if text != "":
		message.emit(text, cat)


func refresh() -> void:
	if not visible or tabs == null:
		return
	var i := tabs.current_tab
	var box: VBoxContainer = _boxes[i]
	UIKit.clear(box)
	match i:
		0:
			_vacancies_tab(box)
		1:
			_apps_tab(box)
			HiringSim.mark_seen(GameState)
		2:
			_staff_tab(box)


# --- Resumen -------------------------------------------------------------------------------------

func _kpis(box: VBoxContainer) -> void:
	var gs := GameState
	var open := 0
	var stopped := 0
	for b in HiringSim.employers(gs):
		open += HiringSim.open_slots(gs, b)
		stopped += HiringSim.stopped_vehicles(gs, b)
	var row := UIKit.flow()
	row.add_child(UIKit.kpi_card("employment", "Puestos libres", str(open), "", [], UIKit.ACCENT, "Puestos sin cubrir en tus negocios", 170))
	row.add_child(UIKit.kpi_card("population", "Postulantes", str(HiringSim.pending(gs).size()), "%d nuevos" % HiringSim.new_count(gs), [], UIKit.ACCENT_2, "Postulaciones pendientes de respuesta", 170))
	row.add_child(UIKit.kpi_card("star", "Reputación empleador", "%d/100" % int(round(HiringSim.reputation(gs))), HiringSim.reputation_label(gs), [], UIKit.level_color(HiringSim.reputation(gs) / 100.0),
		"Sube con buenos sueldos, contrataciones y empleados contentos; baja un poco con rechazos, postulaciones vencidas y contraofertas bajas.", 190))
	row.add_child(UIKit.kpi_card("logistics", "Vehículos detenidos", str(stopped), "sin conductor" if stopped > 0 else "todos con conductor", [], UIKit.BAD if stopped > 0 else UIKit.GOOD,
		"Cada vehículo necesita un conductor (empleado de su estación). Sin conductor queda detenido.", 190))
	row.add_child(UIKit.kpi_card("trend_up", "Publicidad", "×%.2f" % HiringSim.ad_mult(gs), "más postulantes" if HiringSim.ad_mult(gs) > 1.0 else "sin campaña ni medio propio", [], UIKit.INFO,
		"Una campaña activa o tu propio periódico/radio atraen más postulantes.", 190))
	box.add_child(row)


# --- Vacantes --------------------------------------------------------------------------------------

static func _group_of(gs, b: Dictionary) -> String:
	if HiringSim.is_station(gs, b):
		return "Transporte (conductores y cargadores)"
	if str(gs.building_def(b).get("service", "")) != "" or str(gs.building_def(b).get("product", "")) in ["agua", "electricidad"]:
		return "Servicios públicos"
	return "Negocios"


func _vacancies_tab(box: VBoxContainer) -> void:
	var gs := GameState
	_kpis(box)
	var emp := HiringSim.employers(gs)
	if emp.is_empty():
		box.add_child(UIKit.label("Aún no tienes negocios con puestos de trabajo. Cuando termine la obra de uno, sus vacantes aparecerán aquí.", 14, UIKit.TEXT_DIM))
		return
	var groups := {}
	for b in emp:
		var g := _group_of(gs, b)
		if not groups.has(g):
			groups[g] = []
		groups[g].append(b)
	for g in ["Negocios", "Transporte (conductores y cargadores)", "Servicios públicos"]:
		if not groups.has(g):
			continue
		var sec := UIKit.section(box, "%s · %d" % [g, groups[g].size()], "companies" if g == "Negocios" else ("logistics" if g.begins_with("Transporte") else "utilities"), true, "hire_" + g)
		var fl := UIKit.flow(8, 8)
		sec.add_child(fl)
		for b in groups[g]:
			fl.add_child(_vacancy_card(gs, b, refresh, _msg))


## Tarjeta de vacante de un edificio (también la usa la pestaña Empleados).
static func _vacancy_card(gs, b: Dictionary, on_change: Callable, msg: Callable, width := 380.0) -> PanelContainer:
	var bid := int(b["id"])
	var open := HiringSim.open_slots(gs, b)
	var total := HiringSim.total_jobs(gs, b)
	var occ := HiringSim.occupied(gs, b)
	var st := HiringSim.status_label(gs, b)
	var stripe := UIKit.GOOD if open == 0 else (UIKit.ACCENT if HiringSim.is_published(gs, b) else UIKit.NEUTRAL)
	var card := UIKit.card(stripe, 8, width)
	var v: VBoxContainer = card["box"]
	var head := HBoxContainer.new()
	var t := UIKit.label(gs.building_label(b), 15, UIKit.TEXT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.clip_text = true
	head.add_child(t)
	head.add_child(UIKit.chip(st, stripe))
	v.add_child(head)
	v.add_child(_wrap(UIKit.label("%s · %d/%d ocupados · %d pendientes · requisitos: %s" % [HiringSim.role_label(HiringSim.role(gs, b)), occ, total,
		HiringSim.pending(gs, b).size(), HiringSim.requirements_text(gs, b)], 12, UIKit.TEXT_DIM)))
	v.add_child(UIKit.progress(float(occ) / maxf(1.0, float(total)), UIKit.GOOD if open == 0 else UIKit.ACCENT, 6))
	var stopped := HiringSim.stopped_vehicles(gs, b)
	if HiringSim.is_station(gs, b):
		var vl := UIKit.label("Vehículos: %d · %s" % [HiringSim.vehicle_count(gs, b), "%d DETENIDOS por falta de conductor" % stopped if stopped > 0 else "todos con conductor"], 12,
			UIKit.BAD if stopped > 0 else UIKit.TEXT_DIM)
		v.add_child(_wrap(vl))
	var vac := HiringSim.vacancy(gs, b)
	var mw := HiringSim.market_wage(gs, b)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(UIKit.label("Sueldo/día", 12, UIKit.TEXT_DIM))
	var sp := UIKit.spin(0.05, 9999.0, 0.05, float(vac.get("wage", mw)), func(val): HiringSim.set_wage(GameState, GameState.get_building(bid), float(val)), 90)
	sp.name = "Wage"
	row.add_child(sp)
	var ratio := float(vac.get("wage", mw)) / maxf(0.01, mw)
	row.add_child(UIKit.label("mercado %s (%s)" % [Fmt.money2(mw), "%+d %%" % int(round((ratio - 1.0) * 100.0))], 12, UIKit.GOOD if ratio >= 1.0 else UIKit.WARN))
	v.add_child(row)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 6)
	var pub := HiringSim.is_published(gs, b)
	var pb := UIKit.button("Pausar" if pub else "Publicar", func():
		HiringSim.publish(GameState, GameState.get_building(bid), not pub)
		on_change.call(), 84)
	pb.name = "Publish"
	if not pub:
		UIKit.primary(pb)
	pb.disabled = open == 0 and not pub
	row2.add_child(pb)
	var auto := CheckBox.new()
	auto.name = "Auto"
	auto.text = "Auto-contratar hasta"
	auto.button_pressed = bool(vac.get("auto", false))
	auto.tooltip_text = "Contrata solo al mejor postulante que cumpla requisitos y pida hasta este sueldo."
	auto.toggled.connect(func(on):
		HiringSim.set_auto(GameState, GameState.get_building(bid), on)
		if on:
			HiringSim.publish(GameState, GameState.get_building(bid), true)
		on_change.call())
	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 6)
	row3.add_child(auto)
	v.add_child(row2)
	row3.add_child(UIKit.spin(0.05, 9999.0, 0.05, float(vac.get("auto_max", snappedf(mw * 1.15, 0.05))), func(val):
		HiringSim.set_auto(GameState, GameState.get_building(bid), bool(HiringSim.vacancy(GameState, GameState.get_building(bid)).get("auto", false)), float(val)), 84))
	v.add_child(row3)
	if pub and open > 0:
		v.add_child(_wrap(UIKit.label("≈ %.1f postulantes/día (sueldo ×%.2f · reputación %s)" % [HiringSim.daily_rate(gs, b), HiringSim.wage_factor(gs, b), HiringSim.reputation_label(gs)], 11, UIKit.TEXT_FAINT)))
	return card["panel"]


static func _wrap(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 200
	return l


# --- Postulantes ------------------------------------------------------------------------------------

func _apps_tab(box: VBoxContainer) -> void:
	var gs := GameState
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	var ob := OptionButton.new()
	ob.name = "FilterBusiness"
	ob.add_item("Todas las empresas", 0)
	ob.set_item_metadata(0, -1)
	var sel := 0
	for b in HiringSim.employers(gs):
		ob.add_item("%s (%d)" % [gs.building_label(b), HiringSim.pending(gs, b).size()])
		ob.set_item_metadata(ob.item_count - 1, int(b["id"]))
		if int(b["id"]) == f_bid:
			sel = ob.item_count - 1
	ob.select(sel)
	ob.item_selected.connect(func(i):
		f_bid = int(ob.get_item_metadata(i))
		refresh())
	bar.add_child(ob)
	var ok := CheckBox.new()
	ok.text = "Solo quienes cumplen requisitos"
	ok.button_pressed = f_only_ok
	ok.toggled.connect(func(on):
		f_only_ok = on
		refresh())
	bar.add_child(ok)
	var so := OptionButton.new()
	for s in ["Mejor habilidad", "Menor sueldo pedido", "Más recientes"]:
		so.add_item(s)
	so.select(f_sort)
	so.item_selected.connect(func(i):
		f_sort = i
		refresh())
	bar.add_child(so)
	var fb: Dictionary = gs.get_building(f_bid) if f_bid >= 0 else {}
	bar.add_child(UIKit.danger(UIKit.button("Rechazar a los que no cumplen", func():
		var n := HiringSim.reject_unqualified(GameState, GameState.get_building(f_bid) if f_bid >= 0 else {})
		_msg("Rechazaste %d postulación(es) que no cumplían requisitos." % n if n > 0 else "Todos los postulantes cumplen los requisitos.", "jugador")
		refresh())))
	box.add_child(bar)
	var list := HiringSim.pending(gs, fb)
	if f_only_ok:
		list = list.filter(func(a):
			var c: Citizen = GameState.citizens.get(int(a["cid"]))
			var bb: Dictionary = GameState.get_building(int(a["bid"]))
			return c != null and not bb.is_empty() and HiringSim.meets(GameState, bb, c))
	match f_sort:
		0:
			list.sort_custom(func(x, y): return int(x["skill"]) > int(y["skill"]))
		1:
			list.sort_custom(func(x, y): return float(x["asked"]) < float(y["asked"]))
		2:
			list.sort_custom(func(x, y): return int(x["day"]) > int(y["day"]))
	if list.is_empty():
		box.add_child(UIKit.label("No hay postulantes pendientes. Publica tus vacantes (pestaña Vacantes); subir el sueldo o hacer publicidad atrae más.", 14, UIKit.TEXT_DIM))
		return
	box.add_child(UIKit.label("%d postulante(s). Vencen a los %d días sin respuesta." % [list.size(), int(HiringSim.cfg().get("expire_days", 14))], 12, UIKit.TEXT_FAINT))
	var fl := UIKit.flow(8, 8)
	box.add_child(fl)
	var shown := 0
	for a in list:
		if shown >= 60:
			break
		var c: Citizen = gs.citizens.get(int(a["cid"]))
		if c == null:
			continue
		fl.add_child(app_card(gs, a, c, refresh, _msg, 360.0))
		shown += 1


## Ficha de un postulante con Contratar / Rechazar / Contraofertar.
static func app_card(gs, a: Dictionary, c: Citizen, on_change: Callable, msg: Callable, width := 360.0) -> PanelContainer:
	var b: Dictionary = gs.get_building(int(a["bid"]))
	var skill := str(gs.building_def(b).get("skill", ""))
	var why := HiringSim.unmet(gs, b, c)
	var card := UIKit.card(UIKit.ACCENT_2 if str(a["status"]) == HiringSim.ST_NEW else Color(0, 0, 0, 0), 8, width)
	var v: VBoxContainer = card["box"]
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	var p := Portrait.new()
	p.custom_minimum_size = Vector2(52, 52)
	p.set_citizen(c)
	top.add_child(p)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	var nm := HBoxContainer.new()
	var n := UIKit.label("%s, %d años" % [c.full_name(), c.age_years(gs.today())], 14, UIKit.TEXT)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.clip_text = true
	nm.add_child(n)
	if str(a["status"]) == HiringSim.ST_NEW:
		nm.add_child(UIKit.chip("nuevo", UIKit.ACCENT_2))
	info.add_child(nm)
	info.add_child(UIKit.label("→ %s · %s" % [gs.building_label(b), HiringSim.role_label(HiringSim.role(gs, b)).to_lower()], 12, UIKit.ACCENT))
	info.add_child(_wrap(UIKit.label("%s%s · %s %d · %s" % [GameData.education_label(c.education), " · " + GameData.profession_label(c.profession) if c.profession != "" else "",
		GameData.skill_label(skill), int(c.skills.get(skill, 0)), LaborSim.exp_text(c, skill)], 12, UIKit.TEXT_DIM)))
	var pt := HiringSim.prev_text(a)
	info.add_child(_wrap(UIKit.label(pt.substr(0, 1).to_upper() + pt.substr(1), 12, UIKit.TEXT_DIM)))
	var left: int = int(a["expires"]) - int(gs.today())
	info.add_child(UIKit.label("Pide %s/día · vence en %d día%s" % [Fmt.money2(float(a["asked"])), left, "" if left == 1 else "s"], 12, UIKit.TEXT))
	if why != "":
		info.add_child(UIKit.label("✗ No cumple: %s" % why, 12, UIKit.BAD))
	else:
		info.add_child(UIKit.label("✓ Cumple los requisitos", 12, UIKit.GOOD))
	top.add_child(info)
	v.add_child(top)
	var id := int(a["id"])
	var row := UIKit.flow(6, 6)
	var hb := UIKit.primary(UIKit.button("Contratar %s" % Fmt.money2(HiringSim.hire_wage(gs, a)), func():
		var err := HiringSim.hire_app(GameState, id)
		msg.call(err, "jugador")
		on_change.call()))
	hb.name = "Hire"
	hb.disabled = why != "" or HiringSim.open_slots(gs, b) <= 0
	if HiringSim.open_slots(gs, b) <= 0:
		hb.tooltip_text = "No hay puestos libres: mejora el negocio o despide a alguien."
	row.add_child(hb)
	var rb := UIKit.button("Rechazar", func():
		HiringSim.reject_app(GameState, id)
		on_change.call())
	rb.name = "Reject"
	row.add_child(rb)
	var sp := UIKit.spin(0.05, 9999.0, 0.05, snappedf(float(a["asked"]) * 0.95, 0.05), func(_v): pass, 80)
	sp.name = "Counter"
	row.add_child(sp)
	var cb := UIKit.button("Contraofertar", func():
		var r := HiringSim.counter_offer(GameState, id, sp.value)
		msg.call(str(r["text"]), "jugador")
		on_change.call())
	cb.name = "CounterBtn"
	cb.disabled = why != "" or HiringSim.open_slots(gs, b) <= 0
	row.add_child(cb)
	v.add_child(row)
	return card["panel"]


# --- Personal --------------------------------------------------------------------------------------------

func _staff_tab(box: VBoxContainer) -> void:
	var gs := GameState
	var emp := HiringSim.employers(gs)
	var total := 0
	var wages := 0.0
	var high := 0
	for b in emp:
		for c in HiringSim.staff(gs, b):
			total += 1
			wages += c.wage
			if HiringSim.quit_risk(gs, c) == "alto":
				high += 1
	var row := UIKit.flow()
	row.add_child(UIKit.kpi_card("population", "Empleados", str(total), "", [], UIKit.ACCENT, "", 170))
	row.add_child(UIKit.kpi_card("money", "Nómina diaria", Fmt.money2(wages), "", [], UIKit.ACCENT_2, "", 170))
	row.add_child(UIKit.kpi_card("alert", "Riesgo alto de irse", str(high), "sueldo bajo u oferta NPC" if high > 0 else "", [], UIKit.BAD if high > 0 else UIKit.GOOD, "", 190))
	box.add_child(row)
	if emp.is_empty():
		box.add_child(UIKit.label("Aún no tienes empleados.", 14, UIKit.TEXT_DIM))
		return
	for b in emp:
		var st := HiringSim.staff(gs, b)
		var sec := UIKit.section(box, "%s · %d/%d" % [gs.building_label(b), st.size(), HiringSim.total_jobs(gs, b)], "companies", st.size() <= 12, "staff_%d" % int(b["id"]))
		if st.is_empty():
			sec.add_child(UIKit.label("Sin empleados. %s" % ("Hay %d postulante(s) esperando." % HiringSim.pending(gs, b).size() if not HiringSim.pending(gs, b).is_empty() else "Publica la vacante."), 12, UIKit.TEXT_DIM))
			continue
		var skill := str(gs.building_def(b).get("skill", ""))
		var shown := 0
		for c in st:
			if shown >= 60:
				sec.add_child(UIKit.label("… y %d más" % (st.size() - shown), 12, UIKit.TEXT_FAINT))
				break
			shown += 1
			sec.add_child(staff_row(gs, b, c, skill, refresh, _msg))


static func staff_row(gs, b: Dictionary, c: Citizen, skill: String, on_change: Callable, msg: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var risk := HiringSim.quit_risk(gs, c)
	var info := UIKit.label("%s · %s/día · %s · felicidad %d%%" % [c.full_name(), Fmt.money2(c.wage), LaborSim.exp_text(c, skill), int(c.happiness)], 13)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.clip_text = true
	info.tooltip_text = "Pide %s/día" % Fmt.money2(BusinessSim.asked_wage(gs, c, str(b["type"])))
	row.add_child(info)
	row.add_child(UIKit.chip("riesgo %s" % risk, RISK_COLORS.get(risk, UIKit.NEUTRAL)))
	var cid: int = c.id
	row.add_child(UIKit.button("−", func():
		HiringSim.change_wage(GameState, GameState.citizens[cid], -0.1)
		on_change.call(), 28))
	row.add_child(UIKit.button("+", func():
		HiringSim.change_wage(GameState, GameState.citizens[cid], 0.1)
		on_change.call(), 28))
	row.add_child(UIKit.danger(UIKit.button("Despedir", func():
		HiringSim.fire(GameState, GameState.citizens[cid])
		on_change.call())))
	return row


# --- Pestaña Empleados del edificio ---------------------------------------------------------------------------

## Sección "Vacantes y postulantes" de un edificio (pestaña Empleados de BuildingPanel).
static func building_section(gs, b: Dictionary, on_change: Callable, msg: Callable) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.name = "HiringSection"
	v.add_theme_constant_override("separation", 6)
	if not HiringSim.applies(gs, b):
		return v
	var t := UIKit.label("Vacantes y postulantes", 15, UIKit.ACCENT)
	v.add_child(t)
	v.add_child(_vacancy_card(gs, b, on_change, msg, 0.0))
	var list := HiringSim.pending(gs, b)
	list.sort_custom(func(x, y): return int(x["skill"]) > int(y["skill"]))
	if list.is_empty():
		v.add_child(UIKit.label("Sin postulantes pendientes%s." % (": publica la vacante" if not HiringSim.is_published(gs, b) and HiringSim.open_slots(gs, b) > 0 else ""), 12, UIKit.TEXT_DIM))
	else:
		var head := HBoxContainer.new()
		var l := UIKit.label("%d postulante(s)" % list.size(), 13, UIKit.TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(l)
		var bid := int(b["id"])
		head.add_child(UIKit.button("Rechazar a los que no cumplen", func():
			var n := HiringSim.reject_unqualified(GameState, GameState.get_building(bid))
			msg.call("Rechazaste %d postulación(es) que no cumplían requisitos." % n if n > 0 else "Todos los postulantes cumplen los requisitos.", "jugador")
			on_change.call()))
		v.add_child(head)
		var shown := 0
		for a in list:
			if shown >= 12:
				v.add_child(UIKit.label("… y %d más en Empresas → Contrataciones" % (list.size() - shown), 12, UIKit.TEXT_FAINT))
				break
			var c: Citizen = gs.citizens.get(int(a["cid"]))
			if c == null:
				continue
			v.add_child(app_card(gs, a, c, on_change, msg, 0.0))
			shown += 1
		HiringSim.mark_seen(gs, b)
	v.add_child(HSeparator.new())
	return v
