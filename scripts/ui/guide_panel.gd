class_name GuidePanel
extends Control
## Misiones guía y logros en la interfaz (docs/MISIONES_ESCENARIOS.md). Solo lee GameState.progress y
## llama a ProgressSim; no hay lógica de juego aquí.
##   - Panel pequeño arriba a la derecha (bajo la barra superior): título con avance «Misiones guía 2/7»,
##     botón plegar/desplegar y botón ocultar. Oculto del todo no ocupa nada; se vuelve a mostrar desde
##     Mi dinastía → Misiones guía. Sin pop-ups: cada misión muestra su pista al pasar el ratón.
##   - Aviso discreto abajo a la derecha (encima del «Guardado ✓») al cumplir una misión o un logro.
##   - Ventana de logros (Mi dinastía → Logros): los de esta partida y los del perfil global.

const W := 268.0
const NOTE_SECONDS := 4.5

var hud
var panel: PanelContainer
var _title: Label
var _list: VBoxContainer
var _collapse_btn: Button
var _sig := ""
var _t := 0.0
var _note: PanelContainer
var _note_icon: TextureRect
var _note_lbl: Label
var _note_t := 0.0
var _queue: Array = []
var ach_modal: Dictionary = {}
var _ach_box: VBoxContainer
var _ach_head: Label


func setup(h) -> void:
	hud = h
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.float_style(Color(0.075, 0.082, 0.1, 0.86), 10, 8))
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_top = 46.0 + 10.0
	panel.custom_minimum_size.x = W
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	v.add_child(head)
	head.add_child(UIKit.icon("check", 16, UIKit.ACCENT))
	_title = UIKit.label("Misiones guía", 13, UIKit.ACCENT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_collapse_btn = UIKit.icon_button("chevron_up", toggle_collapsed, "Plegar / desplegar", "", 14)
	head.add_child(_collapse_btn)
	head.add_child(UIKit.icon_button("close", hide_guide, "Ocultar las misiones (vuelven desde Mi dinastía → Misiones guía)", "", 14))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	v.add_child(_list)
	_build_note()
	_build_achievements()
	refresh(true)


# --- Panel de misiones ---------------------------------------------------------------------------

func toggle_collapsed() -> void:
	ProgressSim.set_collapsed(GameState, not bool(ProgressSim.st(GameState).get("collapsed", false)))
	refresh(true)


func hide_guide() -> void:
	ProgressSim.set_hidden(GameState, true)
	refresh(true)


func show_guide() -> void:
	ProgressSim.set_hidden(GameState, false)
	ProgressSim.set_collapsed(GameState, false)
	refresh(true)


func is_guide_visible() -> bool:
	return panel.visible


func _signature() -> String:
	var p := ProgressSim.st(GameState)
	var s := "%s|%s|%d|%s" % [p.get("hidden", false), p.get("collapsed", false), ProgressSim.done_count(GameState), ProgressSim.mission_progress(GameState, "contratar")]
	return s


func refresh(force := false) -> void:
	if not GameState.running and GameState.progress.is_empty():
		panel.visible = false
		return
	var sig := _signature()
	if sig == _sig and not force:
		return
	_sig = sig
	var p := ProgressSim.st(GameState)
	var total := ProgressSim.missions().size()
	var done := ProgressSim.done_count(GameState)
	panel.visible = not bool(p.get("hidden", false))
	_title.text = "Misiones guía %d/%d" % [done, total]
	var collapsed := bool(p.get("collapsed", false))
	_collapse_btn.icon = UIIcons.tex("chevron_down" if collapsed else "chevron_up", 14)
	UIKit.clear(_list)
	_list.visible = not collapsed
	if collapsed:
		return
	if done >= total:
		var l := UIKit.label("¡Guía completa! Ya conoces lo básico. Puedes ocultar este panel.", 12, UIKit.GOOD)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = W - 20
		_list.add_child(l)
		return
	var shown := 0
	for m in ProgressSim.missions():
		var id := str(m["id"])
		var is_done := ProgressSim.is_done(GameState, id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		row.tooltip_text = str(m.get("hint", ""))
		row.add_child(UIKit.icon("check" if is_done else str(m.get("icon", "star")), 14, UIKit.GOOD if is_done else UIKit.TEXT_DIM))
		var extra := ProgressSim.mission_progress(GameState, id)
		var lab := UIKit.label(str(m.get("label", id)) + ("  " + extra if extra != "" and not is_done else ""), 12, UIKit.TEXT_FAINT if is_done else UIKit.TEXT)
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lab.mouse_filter = Control.MOUSE_FILTER_PASS
		lab.tooltip_text = row.tooltip_text
		row.add_child(lab)
		if not is_done:
			row.add_child(UIKit.label("+" + Fmt.money(float(m.get("reward", 0)) * GameState.price_mult()), 11, UIKit.TEXT_FAINT))
		_list.add_child(row)
		shown += 1
	var tip := UIKit.label("Pasa el ratón por una misión para ver cómo hacerla.", 10, UIKit.TEXT_FAINT)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size.x = W - 20
	_list.add_child(tip)


func _process(delta: float) -> void:
	_t += delta
	if _t >= 0.5:
		_t = 0.0
		refresh()
		for e in ProgressSim.pop_pending():
			_queue.append(e)
		# No tapar el panel lateral (ficha, edificio…): el panel se corre a su izquierda.
		var right := -8.0
		if hud != null and hud.dock != null and hud.dock.visible:
			right = -(Hud.DOCK_W + 16.0)
		panel.offset_right = right
		panel.offset_left = right - W
	_tick_note(delta)


# --- Aviso discreto -------------------------------------------------------------------------------

func _build_note() -> void:
	_note = PanelContainer.new()
	_note.add_theme_stylebox_override("panel", UIKit._flat(Color(0.06, 0.07, 0.085, 0.86), 8, 12, 6, Color(UIKit.ACCENT, 0.45), 1))
	_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_note)
	_note.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	_note.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_note.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_note.offset_bottom = -52
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	_note.add_child(h)
	_note_icon = UIKit.icon("trophy", 18, UIKit.ACCENT)
	h.add_child(_note_icon)
	_note_lbl = UIKit.label("", 13, UIKit.ACCENT)
	_note_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(_note_lbl)
	_note.visible = false


func _tick_note(delta: float) -> void:
	if _note.visible:
		_note_t -= delta
		if _note_t < 0.6:
			_note.modulate.a = clampf(_note_t / 0.6, 0.0, 1.0)
		if _note_t <= 0.0:
			_note.visible = false
	if not _note.visible and not _queue.is_empty():
		var e: Dictionary = _queue.pop_front()
		var more := 0
		# Muchos a la vez (p. ej. al cargar una partida vieja): se funden en un solo aviso.
		while not _queue.is_empty() and str((_queue[0] as Dictionary).get("kind", "")) == str(e.get("kind", "")) and more < 50:
			_queue.pop_front()
			more += 1
		show_note(e, more)


func show_note(e: Dictionary, more := 0) -> void:
	var logro := str(e.get("kind", "")) == "logro"
	_note_icon.texture = UIIcons.tex("trophy" if logro else "check", 18)
	var t := ("Logro desbloqueado: %s" if logro else "Misión cumplida: %s") % str(e.get("label", ""))
	if more > 0:
		t += "  (+%d más)" % more
	_note_lbl.text = t
	_note.reset_size()
	var ms := _note.get_combined_minimum_size()
	_note.offset_right = -16.0
	_note.offset_left = -16.0 - ms.x
	_note.offset_bottom = -52.0
	_note.offset_top = -52.0 - ms.y
	_note.visible = true
	_note.modulate.a = 1.0
	_note.move_to_front()
	_note_t = NOTE_SECONDS
	AudioManager.on_toast(t, "importante")


func note_text() -> String:
	return _note_lbl.text if _note.visible else ""


# --- Ventana de logros -------------------------------------------------------------------------

func _build_achievements() -> void:
	ach_modal = UIKit.modal(self, "Logros", Vector2(760, 0), "trophy")
	var body: VBoxContainer = ach_modal["body"]
	_ach_head = UIKit.label("", 12, UIKit.TEXT_DIM)
	body.add_child(_ach_head)
	var sb := UIKit.scroll_box(Vector2(740, 520))
	body.add_child(sb["scroll"])
	_ach_box = sb["box"]
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	body.add_child(row)
	row.add_child(UIKit.button("Cerrar", close_achievements, 120))


func open_achievements() -> void:
	_fill_achievements()
	ach_modal["root"].visible = true


func close_achievements() -> void:
	ach_modal["root"].visible = false


func achievements_open() -> bool:
	return ach_modal["root"].visible


func _fill_achievements() -> void:
	UIKit.clear(_ach_box)
	var got: Dictionary = ProgressSim.st(GameState)["achievements"]
	var all := ProgressSim.achievements()
	_ach_head.text = "%d de %d en esta partida · %d en tu perfil (todas las partidas). Se guardan con la partida y en user://logros.cfg." % [got.size(), all.size(), ProgressSim.profile_count()]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_ach_box.add_child(grid)
	for a in all:
		var id := str(a["id"])
		var have := got.has(id)
		var in_profile := ProgressSim.profile_has(id)
		var c := UIKit.card(UIKit.ACCENT if have else Color(1, 1, 1, 0.08), 8, 360)
		grid.add_child(c["panel"])
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		c["box"].add_child(h)
		h.add_child(UIKit.icon(str(a.get("icon", "star")), 22, UIKit.ACCENT if have else UIKit.TEXT_FAINT))
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		v.add_child(UIKit.label(str(a.get("label", id)), 14, UIKit.ACCENT if have else UIKit.TEXT_DIM))
		var d := UIKit.label(str(a.get("description", "")), 11, UIKit.TEXT_DIM if have else UIKit.TEXT_FAINT)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size.x = 290
		v.add_child(d)
		var status := ""
		if have:
			status = "Desbloqueado el %s" % str(got[id].get("date", ""))
		elif in_profile:
			status = "Conseguido en otra partida"
		else:
			status = "Bloqueado"
		v.add_child(UIKit.label(status, 10, UIKit.GOOD if have else (UIKit.INFO if in_profile else UIKit.TEXT_FAINT)))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and achievements_open():
		close_achievements()
		get_viewport().set_input_as_handled()
