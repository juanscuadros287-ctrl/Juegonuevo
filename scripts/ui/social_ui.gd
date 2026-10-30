class_name SocialUI
extends Control
## Interfaz de la vida social (docs/SOCIAL.md): el dispositivo de la época abajo a la derecha
## (carta → telégrafo → teléfono → celular) con contactos, buzón y chat; la ventana de
## conversación con emociones y varias respuestas; ofrecer trabajo; proponer sociedad; y la sección
## «Ánimo y relación» de la ficha de persona. Solo lee el estado y llama a SocialSim/PartnersSim.

const EMO_COLORS := {"alegria": Color(0.97, 0.8, 0.3), "enojo": Color(0.95, 0.42, 0.38), "tristeza": Color(0.45, 0.62, 0.95), "confianza": Color(0.45, 0.83, 0.55)}
const EMO_ICONS := {"alegria": "happiness", "enojo": "alert", "tristeza": "rain", "confianza": "shield"}
const MOOD_COLORS := {"alegria": Color(0.97, 0.8, 0.3), "enojo": Color(0.95, 0.42, 0.38), "tristeza": Color(0.45, 0.62, 0.95), "calma": Color(0.7, 0.75, 0.82)}

var hud
var device_btn: Button
var _badge: PanelContainer
var _badge_lbl: Label
var device_panel: PanelContainer
var _dev_title: Label
var _dev_note: Label
var _dev_tabs: TabContainer
var _contacts_box: VBoxContainer
var _inbox_box: VBoxContainer
var _chat_box: VBoxContainer
var _chat_with := -1
var convo_modal: Dictionary
var _convo_cid := -1
var _convo_log: RichTextLabel
var _convo_opts: VBoxContainer
var _convo_head: VBoxContainer
var _convo_emos: VBoxContainer
var job_modal: Dictionary
var partner_modal: Dictionary
var pick_modal: Dictionary
var _pp := {}          # estado del formulario de sociedad
var _tick := 0.0
var _held_agent: Node = null


func setup(p_hud) -> void:
	hud = p_hud
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_device()
	_build_convo()
	job_modal = UIKit.modal(self, "Ofrecer trabajo", Vector2(520, 0), "employment")
	partner_modal = UIKit.modal(self, "Proponer sociedad", Vector2(540, 0), "handshake")
	pick_modal = UIKit.modal(self, "Traer un socio", Vector2(520, 0), "handshake")
	refresh_device_button()


func modals() -> Array:
	return [convo_modal, job_modal, partner_modal, pick_modal]


## Esc: cierra lo último que esté abierto. Devuelve true si cerró algo.
func close_top() -> bool:
	for m in [pick_modal, partner_modal, job_modal, convo_modal]:
		if m["root"].visible:
			if m == convo_modal:
				close_conversation()
			else:
				m["root"].visible = false
			return true
	if device_panel.visible:
		device_panel.visible = false
		return true
	return false


# --- Dispositivo ---------------------------------------------------------------------------------

func _build_device() -> void:
	device_btn = Button.new()
	device_btn.name = "DeviceButton"
	device_btn.custom_minimum_size = Vector2(54, 54)
	device_btn.add_theme_constant_override("icon_max_width", 28)
	device_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	device_btn.add_theme_stylebox_override("normal", UIKit._flat(Color(0.09, 0.1, 0.13, 0.92), 27, 8, 8, Color(UIKit.ACCENT, 0.55), 2))
	device_btn.add_theme_stylebox_override("hover", UIKit._flat(Color(0.14, 0.15, 0.19, 0.96), 27, 8, 8, UIKit.ACCENT, 2))
	device_btn.add_theme_stylebox_override("pressed", UIKit._flat(Color(0.2, 0.17, 0.1, 0.96), 27, 8, 8, UIKit.ACCENT, 2))
	device_btn.pressed.connect(toggle_device)
	add_child(device_btn)
	device_btn.anchor_left = 1.0
	device_btn.anchor_right = 1.0
	device_btn.anchor_top = 1.0
	device_btn.anchor_bottom = 1.0
	_place_button(false)
	_badge = PanelContainer.new()
	_badge.add_theme_stylebox_override("panel", UIKit._flat(UIKit.BAD, 9, 5, 1))
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.position = Vector2(34, -4)
	_badge_lbl = UIKit.label("0", 11, Color.WHITE)
	_badge_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.add_child(_badge_lbl)
	device_btn.add_child(_badge)
	_badge.visible = false

	device_panel = PanelContainer.new()
	device_panel.name = "DevicePanel"
	device_panel.add_theme_stylebox_override("panel", UIKit.float_style(UIKit.BG, 14, 12))
	device_panel.anchor_left = 1.0
	device_panel.anchor_right = 1.0
	device_panel.anchor_top = 1.0
	device_panel.anchor_bottom = 1.0
	device_panel.visible = false
	add_child(device_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	device_panel.add_child(v)
	_dev_title = UIKit.header(v, "letter", "Mis cartas", func(): device_panel.visible = false, [])
	_dev_note = UIKit.label("", 12, UIKit.TEXT_DIM)
	_dev_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dev_note.custom_minimum_size.x = 360
	v.add_child(_dev_note)
	_dev_tabs = TabContainer.new()
	_dev_tabs.custom_minimum_size = Vector2(380, 380)
	_dev_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_dev_tabs)
	_contacts_box = _tab_box("Contactos")
	_inbox_box = _tab_box("Buzón")
	_chat_box = _tab_box("Chat")
	_dev_tabs.tab_changed.connect(func(_i): _rebuild_tab())
	_place_panel(false)


func _tab_box(name: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = name
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var b := VBoxContainer.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_constant_override("separation", 6)
	sc.add_child(b)
	_dev_tabs.add_child(sc)
	return b


func _dock_open() -> bool:
	return hud != null and hud.dock != null and hud.dock.visible and hud.dock_mode != ""


func _place_button(dock_open: bool) -> void:
	var right := -16.0 - (Hud.DOCK_W + 10.0 if dock_open else 0.0)
	device_btn.offset_left = right - 54.0
	device_btn.offset_right = right
	device_btn.offset_top = -70.0
	device_btn.offset_bottom = -16.0


func _place_panel(dock_open: bool) -> void:
	var right := -16.0 - (Hud.DOCK_W + 10.0 if dock_open else 0.0)
	device_panel.offset_right = right
	device_panel.offset_left = right - 410.0
	device_panel.offset_bottom = -78.0
	device_panel.offset_top = -78.0 - 520.0


func toggle_device() -> void:
	if device_panel.visible:
		device_panel.visible = false
		return
	open_device()


func open_device(tab := 0) -> void:
	device_panel.visible = true
	_place_panel(_dock_open())
	device_panel.move_to_front()
	device_btn.move_to_front()
	_dev_tabs.current_tab = clampi(tab, 0, _dev_tabs.get_tab_count() - 1)
	_rebuild_tab()
	UIKit.pop_in(device_panel)


func refresh_device_button() -> void:
	if not GameState.running and GameState.citizens.is_empty():
		return
	var d := SocialSim.device(GameState)
	device_btn.icon = UIIcons.tex(str(d.get("icon", "letter")), 28)
	device_btn.tooltip_text = "%s (vida social): contactos, mensajes e invitaciones. %s" % [str(d.get("label", "")), _delay_text(d)]
	var n := SocialSim.unread_count(GameState) if GameState.player.has("social") else 0
	_badge.visible = n > 0
	_badge_lbl.text = str(mini(n, 99))


func _delay_text(d: Dictionary) -> String:
	var r: Array = d.get("delay", [0, 0])
	if int(r[1]) <= 0:
		return "Llega al instante."
	return "Tarda %d–%d días en llegar y lo mismo en volver." % [int(r[0]), int(r[1])] if int(r[0]) != int(r[1]) else "Tarda %d día en llegar." % int(r[0])


func _rebuild_tab() -> void:
	if not device_panel.visible:
		return
	var d := SocialSim.device(GameState)
	_dev_title.text = "Mi %s" % str(d.get("label", "Carta")).to_lower()
	var title_head: Node = _dev_title.get_parent()
	if title_head != null and title_head.get_child_count() > 0:
		var badge: Node = title_head.get_child(0)
		if badge.get_child_count() > 0 and badge.get_child(0) is TextureRect:
			(badge.get_child(0) as TextureRect).texture = UIIcons.tex(str(d.get("icon", "letter")), 20)
	_dev_note.text = "%s Cada envío cuesta %s.%s" % [_delay_text(d), Fmt.money2(SocialSim.send_cost(GameState)),
		"" if SocialSim.pending_outbox(GameState).is_empty() else " En camino: %d." % SocialSim.pending_outbox(GameState).size()]
	_dev_tabs.set_tab_title(1, "Buzón (%d)" % SocialSim.unread_count(GameState) if SocialSim.unread_count(GameState) > 0 else "Buzón")
	_dev_tabs.set_tab_hidden(2, not bool(d.get("chat", false)))
	match _dev_tabs.current_tab:
		0:
			_fill_contacts()
		1:
			_fill_inbox()
		2:
			_fill_chat()


func _fill_contacts() -> void:
	UIKit.clear(_contacts_box)
	var d := SocialSim.device(GameState)
	var list := SocialSim.contacts(GameState)
	if list.is_empty():
		var l := UIKit.label("Aún no tienes contactos. Haz clic en alguien que camine por el pueblo y salúdale.", 13, UIKit.TEXT_DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 350
		_contacts_box.add_child(l)
		return
	for e in list.slice(0, 40):
		var c: Citizen = e["citizen"]
		var cid := c.id
		var card := UIKit.card(UIKit.ACCENT if e["family"] else Color(0.72, 0.62, 0.98), 6)
		_contacts_box.add_child(card["panel"])
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 6)
		card["box"].add_child(top)
		var nm := UIKit.label(c.full_name(), 14, UIKit.TEXT)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.clip_text = true
		top.add_child(nm)
		var m := SocialSim.mood(GameState, c)
		top.add_child(UIKit.chip(str(m["label"]), MOOD_COLORS.get(str(m["id"]), UIKit.TEXT_DIM)))
		top.add_child(UIKit.chip(("Familia · " if e["family"] else "") + "%d" % int(e["affinity"]), Color(0.95, 0.62, 0.85), "heart"))
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 4)
		card["box"].add_child(row)
		if bool(d.get("call", false)):
			_small(row, "Llamar", "phone", SocialSim.can_send(GameState, c, "llamada"), func(): _do(SocialSim.send(GameState, GameState.citizens[cid], "llamada")))
		else:
			_small(row, "Escribir", str(d.get("icon", "letter")), SocialSim.can_send(GameState, c, "carta"), func(): _do(SocialSim.send(GameState, GameState.citizens[cid], "carta")))
		var inv_r := SocialSim.can_send(GameState, c, "invitacion")
		if inv_r == "":
			inv_r = SocialSim.can_visit(GameState, c)
		_small(row, "Invitar a casa", "realestate", inv_r, func(): _do(SocialSim.send(GameState, GameState.citizens[cid], "invitacion")))
		if bool(d.get("chat", false)):
			_small(row, "Chat", "chat", "", func():
				_chat_with = cid
				_dev_tabs.current_tab = 2)
		_small(row, "Ficha", "eye", "", func(): EventBus.citizen_selected.emit(cid))


func _small(parent: Control, text: String, icon_name: String, reason: String, cb: Callable) -> Button:
	var b := UIKit.button(text, cb)
	b.icon = UIIcons.tex(icon_name, 14)
	b.add_theme_font_size_override("font_size", 12)
	b.disabled = reason != ""
	b.tooltip_text = reason
	parent.add_child(b)
	return b


func _fill_inbox() -> void:
	UIKit.clear(_inbox_box)
	var msgs := SocialSim.inbox(GameState)
	if msgs.is_empty():
		_inbox_box.add_child(UIKit.label("No tienes mensajes.", 13, UIKit.TEXT_DIM))
	for i in range(msgs.size() - 1, -1, -1):
		var m: Dictionary = msgs[i]
		var card := UIKit.card(UIKit.INFO if not bool(m.get("read", false)) else Color(0, 0, 0, 0), 6)
		_inbox_box.add_child(card["panel"])
		var who := GameState.person_name(int(m.get("from", -1)))
		card["box"].add_child(UIKit.label("%s · %s" % [who, TimeManager.date_from_day(int(m.get("day", 0)), TimeManager.start_year())], 12, UIKit.ACCENT))
		var t := UIKit.label(str(m.get("text", "")), 13, UIKit.TEXT)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.custom_minimum_size.x = 340
		card["box"].add_child(t)
		var offer: Dictionary = m.get("offer", {})
		if not offer.is_empty() and not bool(offer.get("done", false)):
			var row := HBoxContainer.new()
			card["box"].add_child(row)
			var mid := int(m["id"])
			row.add_child(UIKit.primary(UIKit.button("Aceptar", func(): _do(SocialSim.answer_offer(GameState, mid, true)))))
			row.add_child(UIKit.button("Rechazar", func(): _do(SocialSim.answer_offer(GameState, mid, false))))
	SocialSim.mark_all_read(GameState)
	refresh_device_button()


func _fill_chat() -> void:
	UIKit.clear(_chat_box)
	var c: Citizen = GameState.citizens.get(_chat_with)
	if c == null:
		_chat_box.add_child(UIKit.label("Elige un contacto en «Contactos» → Chat.", 13, UIKit.TEXT_DIM))
		return
	_chat_box.add_child(UIKit.label("Chat con %s" % c.full_name(), 15, UIKit.ACCENT))
	for line in SocialSim.chat_of(GameState, c):
		var me := bool(line.get("me", false))
		var l := UIKit.label(("Tú: " if me else c.first_name + ": ") + str(line.get("t", "")), 13, UIKit.ACCENT_2 if me else UIKit.TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 340
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if me else HORIZONTAL_ALIGNMENT_LEFT
		_chat_box.add_child(l)
	var reason := SocialSim.can_send(GameState, c, "chat")
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 4)
	_chat_box.add_child(flow)
	var cid := c.id
	for preset in SocialSim.CHAT_PRESETS:
		var txt: String = preset
		_small(flow, txt, "chat", reason, func(): _do(SocialSim.send(GameState, GameState.citizens[cid], "chat", txt)))


func _do(text: String) -> void:
	if text != "" and hud != null:
		hud.toast(text, "social")
	_rebuild_tab()
	refresh_device_button()
	if hud != null and hud.dock_mode == "citizen":
		hud._refresh_citizen(true)


# --- Ficha de persona -----------------------------------------------------------------------------

## Sección «Ánimo y relación» de la ficha (también para tu personaje).
func fill_sheet(parent: VBoxContainer, c: Citizen) -> void:
	var me := GameState.is_player(c.id)
	var sec := UIKit.section(parent, "Mi ánimo" if me else "Ánimo y relación", "happiness", true, "cit_social")
	var m := SocialSim.mood(GameState, c)
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 4)
	sec.add_child(chips)
	chips.add_child(UIKit.chip("Ánimo: %s" % str(m["label"]), MOOD_COLORS.get(str(m["id"]), UIKit.TEXT_DIM), "happiness"))
	var tr := SocialSim.main_trait(c)
	chips.add_child(UIKit.chip(SocialSim.trait_label(tr), Color(0.72, 0.62, 0.98), "character"))
	var e := SocialSim.emotions(GameState, c)
	for k in SocialSim.EMOTIONS:
		if me and k == "confianza":
			continue
		sec.add_child(UIKit.meter_row(str(EMO_ICONS[k]), SocialSim.emotion_label(k), float(e[k]) / 100.0, str(int(e[k])), false, EMO_COLORS[k]))
	if me:
		var d := SocialSim.device(GameState)
		var n := SocialSim.contacts(GameState).size()
		var l := UIKit.label("%d contactos · %s: %s" % [n, str(d.get("label", "")), _delay_text(d)], 12, UIKit.TEXT_DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sec.add_child(l)
		return
	var likes := SocialSim.trait_likes(tr)
	if likes != "":
		var lk := UIKit.label("Le gusta: %s." % likes, 12, UIKit.TEXT_DIM)
		lk.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sec.add_child(lk)
	var ct := SocialSim.contact(GameState, c.id, false)
	if int(ct.get("owed", 0)) > 0:
		sec.add_child(UIKit.label("Te debe %d favor(es)." % int(ct["owed"]), 12, UIKit.GOOD))
	var mem := SocialSim.memory_lines(GameState, c, 3)
	if not mem.is_empty():
		sec.add_child(UIKit.label("Recuerda:", 12, UIKit.ACCENT))
		for line in mem:
			var ml := UIKit.label("• " + str(line), 12, UIKit.TEXT_DIM)
			ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			sec.add_child(ml)
	for p in PartnersSim.of_citizen(GameState, c.id):
		var b := GameState.get_building(int(p["bid"]))
		sec.add_child(UIKit.label("Socio(a) de %s: %d %% · satisfacción %d%s" % [GameState.building_label(b), int(round(float(p["share"]) * 100.0)), int(p["sat"]),
			" · " + PartnersSim.dispute_text(GameState, p) if not (p["dispute"] as Dictionary).is_empty() else ""], 12, UIKit.WARN if not (p["dispute"] as Dictionary).is_empty() else UIKit.ACCENT_2))


## Botones sociales de la ficha. `add` = el ayudante de la ficha (texto, callback, habilitado, tip, icono).
func add_actions(c: Citizen, add: Callable) -> void:
	var cid := c.id
	if GameState.is_player(cid):
		var d := SocialSim.device(GameState)
		add.call("Mi %s" % str(d.get("label", "")).to_lower(), func(): open_device(0), true, "Contactos, buzón e invitaciones", str(d.get("icon", "letter")))
		return
	var gr := SocialSim.can_greet(GameState, c)
	add.call("Saludar", func(): _do(SocialSim.greet(GameState, GameState.citizens[cid])), gr == "", gr, "happiness")
	var talk_r := PlayerSim.can_talk(GameState, c)
	if talk_r == "" and c.prison_until >= 0:
		talk_r = "Está en la cárcel"
	add.call("Conversar…", func(): open_conversation(cid), talk_r == "", talk_r, "chat")
	if c.age_years(GameState.today()) >= int(GameData.citizens.get("adult_age", 16)):
		var vac := SocialSim.vacancies(GameState)
		add.call("Ofrecer trabajo…", func(): open_job_offer(cid), not vac.is_empty() and c.job_kind != "dueño",
			"No tienes vacantes en tus negocios" if vac.is_empty() else ("Atiende su propio negocio" if c.job_kind == "dueño" else ""), "employment")
	var vr := SocialSim.can_visit(GameState, c)
	add.call("Invitar a cenar", func(): _do(SocialSim.invite_home(GameState, GameState.citizens[cid])), vr == "", vr if vr != "" else "Cuesta %s (la comida se compra en el pueblo)" % Fmt.money(SocialSim.visit_cost(GameState)), "realestate")
	var gf := SocialSim.can_gift(GameState, c)
	add.call("Regalo", func(): _do(SocialSim.give_gift(GameState, GameState.citizens[cid])), gf == "", gf if gf != "" else "Cuesta %s; te quedará debiendo un favor" % Fmt.money(SocialSim.gift_cost(GameState)), "star")
	if c.age_years(GameState.today()) >= 18 and not PartnersSim.eligible_businesses(GameState).is_empty():
		add.call("Proponer sociedad…", func(): open_partner_proposal(cid), true, "Que sea socio(a) de una de tus empresas", "handshake")


# --- Conversación ---------------------------------------------------------------------------------

func _build_convo() -> void:
	convo_modal = UIKit.modal(self, "Conversación", Vector2(600, 0), "chat")
	var body: VBoxContainer = convo_modal["body"]
	_convo_head = VBoxContainer.new()
	body.add_child(_convo_head)
	_convo_emos = VBoxContainer.new()
	_convo_emos.add_theme_constant_override("separation", 2)
	body.add_child(_convo_emos)
	var sb := UIKit.scroll_box(Vector2(560, 190))
	body.add_child(sb["scroll"])
	_convo_log = UIKit.rich(Vector2(540, 0))
	sb["box"].add_child(_convo_log)
	_convo_opts = VBoxContainer.new()
	_convo_opts.add_theme_constant_override("separation", 5)
	body.add_child(_convo_opts)


func open_conversation(cid: int) -> void:
	var c: Citizen = GameState.citizens.get(cid)
	if c == null:
		return
	var r := SocialSim.start_conversation(GameState, c)
	if not bool(r.get("ok", false)):
		hud.toast(str(r.get("error", "")), "social")
		return
	_convo_cid = cid
	_hold_agent(cid, true)
	_convo_log.text = ""
	_convo_head_fill(c)
	_say(c, str(r["line"]))
	_set_options(c, r.get("options", []))
	convo_modal["root"].visible = true


func close_conversation() -> void:
	convo_modal["root"].visible = false
	if _convo_cid >= 0:
		var c: Citizen = GameState.citizens.get(_convo_cid)
		if c != null and not SocialSim._convo(GameState, c).is_empty():
			SocialSim.state(GameState)["convo"] = {}
	_hold_agent(_convo_cid, false)
	_convo_cid = -1
	if hud != null and hud.dock_mode == "citizen":
		hud._refresh_citizen(true)


func _hold_agent(cid: int, on: bool) -> void:
	var world: Node = hud.get_parent() if hud != null else null
	if world == null or not ("agents" in world):
		return
	if not on:
		if _held_agent != null and is_instance_valid(_held_agent):
			_held_agent.set("hold", false)
		_held_agent = null
		return
	var a = world.agents.get(cid)
	if a != null and is_instance_valid(a):
		a.set("hold", true)   # Se detiene a conversar contigo.
		_held_agent = a


func _convo_head_fill(c: Citizen) -> void:
	UIKit.clear(_convo_head)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	_convo_head.add_child(h)
	var pt := Portrait.new()
	pt.custom_minimum_size = Vector2(64, 64)
	pt.set_citizen(c, false)
	h.add_child(pt)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(UIKit.label(c.full_name(), 18, UIKit.ACCENT))
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 4)
	v.add_child(chips)
	var m := SocialSim.mood(GameState, c)
	chips.add_child(UIKit.chip(str(m["label"]), MOOD_COLORS.get(str(m["id"]), UIKit.TEXT_DIM), "happiness"))
	chips.add_child(UIKit.chip(SocialSim.trait_label(SocialSim.main_trait(c)), Color(0.72, 0.62, 0.98), "character"))
	chips.add_child(UIKit.chip(PlayerSim.relation_label(GameState, c), Color(0.95, 0.62, 0.85), "heart"))
	UIKit.clear(_convo_emos)
	var e := SocialSim.emotions(GameState, c)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	_convo_emos.add_child(grid)
	for k in SocialSim.EMOTIONS:
		var row := UIKit.meter_row(str(EMO_ICONS[k]), SocialSim.emotion_label(k), float(e[k]) / 100.0, str(int(e[k])), false, EMO_COLORS[k])
		row.custom_minimum_size.x = 270
		grid.add_child(row)


func _say(c: Citizen, line: String) -> void:
	if line != "":
		_convo_log.append_text("[color=#edc259][b]%s:[/b][/color] %s\n" % [c.first_name, line])


func _set_options(c: Citizen, opts: Array) -> void:
	UIKit.clear(_convo_opts)
	var cid := c.id
	for o in opts:
		var oid := str(o["id"])
		var lbl := str(o["label"])
		var b := UIKit.button("» " + lbl, func(): _pick_option(cid, oid, lbl))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if oid in ["ofrecer_trabajo", "proponer_sociedad"]:
			UIKit.primary(b)
		_convo_opts.add_child(b)
	if opts.is_empty():
		_convo_opts.add_child(UIKit.primary(UIKit.button("Terminar la conversación", close_conversation)))


func _pick_option(cid: int, oid: String, lbl: String) -> void:
	var c: Citizen = GameState.citizens.get(cid)
	if c == null:
		close_conversation()
		return
	_convo_log.append_text("[color=#7fb0f0][b]Tú:[/b][/color] %s\n" % lbl)
	var r := SocialSim.choose(GameState, c, oid)
	_say(c, str(r.get("line", "")))
	if str(r.get("effect", "")) != "":
		_convo_log.append_text("[color=#9aa0aa][i]%s[/i][/color]\n" % str(r["effect"]))
	_convo_head_fill(c)
	_set_options(c, r.get("options", []))
	match str(r.get("action", "")):
		"job":
			close_conversation()
			open_job_offer(cid)
		"partner":
			close_conversation()
			open_partner_proposal(cid)


# --- Ofrecer trabajo -------------------------------------------------------------------------------

func open_job_offer(cid: int) -> void:
	var c: Citizen = GameState.citizens.get(cid)
	if c == null:
		return
	var body: VBoxContainer = job_modal["body"]
	while body.get_child_count() > 2:
		var ch := body.get_child(2)
		body.remove_child(ch)
		ch.queue_free()
	var info := UIKit.label("%s · %s · %s" % [c.full_name(), BusinessSim.job_label(GameState, c), GameData.education_label(c.education)], 13, UIKit.TEXT_DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(info)
	var vac := SocialSim.vacancies(GameState)
	if vac.is_empty():
		body.add_child(UIKit.label("No tienes vacantes en tus negocios.", 13, UIKit.WARN))
	for v in vac.slice(0, 8):
		var b: Dictionary = v["building"]
		var bid := int(b["id"])
		var asked := BusinessSim.asked_wage(GameState, c, str(b["type"]))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		body.add_child(row)
		var nl := UIKit.label("%s (%d libres)" % [GameState.building_label(b), int(v["free"])], 13)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.clip_text = true
		row.add_child(nl)
		var chance_l := UIKit.label("", 12, UIKit.TEXT_DIM)
		chance_l.custom_minimum_size.x = 92
		var sp := UIKit.spin(maxf(0.05, GovSim.min_wage(GameState)), asked * 3.0, 0.05, asked, func(w): chance_l.text = "acepta ≈%d %%" % int(SocialSim.job_chance(GameState, GameState.citizens[cid], GameState.get_building(bid), w) * 100.0), 96)
		sp.suffix = "/día"
		row.add_child(sp)
		chance_l.text = "acepta ≈%d %%" % int(SocialSim.job_chance(GameState, c, b, asked) * 100.0)
		row.add_child(chance_l)
		var block := SocialSim._hire_block(GameState, b, c, asked)
		var ob := UIKit.primary(UIKit.button("Ofrecer", func():
			job_modal["root"].visible = false
			_do(SocialSim.offer_job(GameState, GameState.citizens[cid], GameState.get_building(bid), sp.value))))
		ob.disabled = block != "" and not block.begins_with("El salario")
		ob.tooltip_text = block
		row.add_child(ob)
	body.add_child(UIKit.button("Cancelar", func(): job_modal["root"].visible = false))
	job_modal["root"].visible = true


# --- Sociedad ----------------------------------------------------------------------------------------

## Formulario para proponer una sociedad a `cid` (en el negocio `bid`, o el primero que admita socios).
func open_partner_proposal(cid: int, bid := -1) -> void:
	var c: Citizen = GameState.citizens.get(cid)
	if c == null:
		return
	pick_modal["root"].visible = false
	var biz := PartnersSim.eligible_businesses(GameState)
	if biz.is_empty():
		hud.toast("Ninguna de tus empresas admite más socios.", "social")
		return
	var sel := 0
	for i in range(biz.size()):
		if int(biz[i]["id"]) == bid:
			sel = i
	_pp = {"cid": cid, "biz": biz, "sel": sel, "kind": "capital" if c.money > 1.0 else "habilidad"}
	var b: Dictionary = biz[sel]
	_pp["capital"] = snappedf(minf(c.money * 0.5, PartnersSim.valuation(GameState, b) * 0.3), 1.0)
	_pp["share"] = _suggest_share()
	_fill_partner_form()
	partner_modal["root"].visible = true


func _suggest_share() -> float:
	var c: Citizen = GameState.citizens.get(int(_pp["cid"]))
	var b: Dictionary = _pp["biz"][int(_pp["sel"])]
	var s := PartnersSim.fair_share(GameState, b, float(_pp["capital"])) if str(_pp["kind"]) == "capital" else PartnersSim.fair_skill_share(GameState, c, b)
	return clampf(snappedf(s, 0.01), PartnersSim.min_share(), maxf(PartnersSim.min_share(), PartnersSim.room(GameState, b)))


func _fill_partner_form() -> void:
	var body: VBoxContainer = partner_modal["body"]
	while body.get_child_count() > 2:
		var ch := body.get_child(2)
		body.remove_child(ch)
		ch.queue_free()
	var c: Citizen = GameState.citizens.get(int(_pp["cid"]))
	var biz: Array = _pp["biz"]
	var b: Dictionary = biz[int(_pp["sel"])]
	var intro := UIKit.label("%s · dinero %s · habilidad útil %d · relación %d" % [c.full_name(), Fmt.money(c.money), int(PartnersSim.skill_of(GameState, c, b)), int(PlayerSim.affinity(GameState, c.id))], 13, UIKit.TEXT_DIM)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(intro)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	body.add_child(grid)
	grid.add_child(UIKit.label("Empresa", 13))
	var ob := OptionButton.new()
	for x in biz:
		ob.add_item(GameState.building_label(x))
	ob.selected = int(_pp["sel"])
	ob.item_selected.connect(func(i):
		_pp["sel"] = i
		_pp["share"] = _suggest_share()
		_fill_partner_form())
	grid.add_child(ob)
	grid.add_child(UIKit.label("Aporta", 13))
	var kb := OptionButton.new()
	kb.add_item("Capital (dinero)")
	kb.add_item("Habilidades (+producción)")
	kb.selected = 0 if str(_pp["kind"]) == "capital" else 1
	kb.item_selected.connect(func(i):
		_pp["kind"] = "capital" if i == 0 else "habilidad"
		_pp["share"] = _suggest_share()
		_fill_partner_form())
	grid.add_child(kb)
	if str(_pp["kind"]) == "capital":
		grid.add_child(UIKit.label("Capital", 13))
		var cs := UIKit.spin(0.0, maxf(1.0, floorf(c.money)), 1.0, float(_pp["capital"]), func(v):
			_pp["capital"] = v
			_update_partner_info(), 140)
		grid.add_child(cs)
	grid.add_child(UIKit.label("Su parte de utilidades", 13))
	var ss := UIKit.spin(PartnersSim.min_share() * 100.0, maxf(PartnersSim.min_share(), PartnersSim.room(GameState, b)) * 100.0, 1.0, float(_pp["share"]) * 100.0, func(v):
		_pp["share"] = v / 100.0
		_update_partner_info(), 140)
	ss.suffix = "%"
	grid.add_child(ss)
	var info := UIKit.label("", 12, UIKit.TEXT_DIM)
	info.name = "Info"
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.x = 500
	body.add_child(info)
	var row := HBoxContainer.new()
	body.add_child(row)
	var pb := UIKit.primary(UIKit.button("Proponer", func():
		var r := PartnersSim.propose(GameState, _pp["biz"][int(_pp["sel"])], GameState.citizens[int(_pp["cid"])], str(_pp["kind"]), float(_pp.get("capital", 0.0)), float(_pp["share"]))
		partner_modal["root"].visible = false
		_do(str(r.get("msg", "")))))
	row.add_child(pb)
	row.add_child(UIKit.button("Cancelar", func(): partner_modal["root"].visible = false))
	_update_partner_info()


func _update_partner_info() -> void:
	var info: Label = partner_modal["body"].find_child("Info", true, false)
	if info == null:
		return
	var c: Citizen = GameState.citizens.get(int(_pp["cid"]))
	var b: Dictionary = _pp["biz"][int(_pp["sel"])]
	var kind := str(_pp["kind"])
	var cap := float(_pp.get("capital", 0.0)) if kind == "capital" else 0.0
	var fair := PartnersSim.fair_share(GameState, b, cap) if kind == "capital" else PartnersSim.fair_skill_share(GameState, c, b)
	var why := PartnersSim.can_be_partner(GameState, b, c, kind)
	var s := "Valor del negocio: %s · parte justa ≈%d %% · tú conservas %d %% · utilidad del mes pasado %s." % [Fmt.money(PartnersSim.valuation(GameState, b)), int(round(fair * 100.0)),
		int(round((1.0 - PartnersSim.total_share(GameState, b) - float(_pp["share"])) * 100.0)), Fmt.money(BusinessSim.period_profit(b, "last_month"))]
	if kind == "habilidad":
		s += " Su experiencia sube la producción +%d %%." % int(PartnersSim.skill_bonus(GameState, c, b) * 100.0)
	s += "\nProbabilidad de que acepte: ≈%d %%." % int(PartnersSim.accept_chance(GameState, b, c, kind, cap, float(_pp["share"])) * 100.0)
	if why != "":
		s += "\n" + why
	info.text = s


## Lista de candidatos a socio para un negocio (desde la pestaña Socios).
func open_partner_picker(bid: int) -> void:
	var b := GameState.get_building(bid)
	var body: VBoxContainer = pick_modal["body"]
	while body.get_child_count() > 2:
		var ch := body.get_child(2)
		body.remove_child(ch)
		ch.queue_free()
	body.add_child(UIKit.label("Candidatos para %s: con dinero para invertir o con experiencia en el oficio." % GameState.building_label(b), 13, UIKit.TEXT_DIM))
	var cands := []
	for c in GameState.citizens.values():
		if PartnersSim.can_be_partner(GameState, b, c, "capital") != "":
			continue
		var sk := PartnersSim.skill_of(GameState, c, b)
		if c.money < 20.0 * GameState.price_mult() and sk < float(PartnersSim.cfg().get("skill_min", 35)):
			continue
		cands.append({"c": c, "score": c.money + sk * 10.0 + PlayerSim.affinity(GameState, c.id) * 20.0})
	cands.sort_custom(func(x, y): return float(x["score"]) > float(y["score"]))
	var sb := UIKit.scroll_box(Vector2(480, 300))
	body.add_child(sb["scroll"])
	if cands.is_empty():
		sb["box"].add_child(UIKit.label("Nadie en el pueblo puede ser socio ahora.", 13, UIKit.WARN))
	for x in cands.slice(0, 20):
		var c: Citizen = x["c"]
		var cid := c.id
		var row := HBoxContainer.new()
		sb["box"].add_child(row)
		var l := UIKit.label("%s · %s · habilidad %d · relación %d" % [c.full_name(), Fmt.money(c.money), int(PartnersSim.skill_of(GameState, c, b)), int(PlayerSim.affinity(GameState, c.id))], 13)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		row.add_child(l)
		row.add_child(UIKit.button("Proponer…", func(): open_partner_proposal(cid, bid)))
	body.add_child(UIKit.button("Cerrar", func(): pick_modal["root"].visible = false))
	pick_modal["root"].visible = true


# --- Refresco ---------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.5
	var dock_open := _dock_open()
	_place_button(dock_open)
	if device_panel.visible:
		_place_panel(dock_open)
	refresh_device_button()
