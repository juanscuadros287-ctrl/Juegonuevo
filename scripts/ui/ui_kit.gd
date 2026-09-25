class_name UIKit
extends RefCounted
## Sistema de diseño de la interfaz: paleta, tipografía, espaciados, tema de Godot, escala
## (Retina y ajuste del jugador), animaciones y constructores de controles reutilizables.
## Ver docs/UI.md.

# --- Paleta ---------------------------------------------------------------------------------------
const BG := Color(0.075, 0.082, 0.1, 0.94)          # paneles
const BG_LIGHT := Color(0.125, 0.137, 0.165, 0.97)  # tarjetas dentro de un panel
const BG_RAISED := Color(0.17, 0.184, 0.22, 1.0)     # botones y campos
const BG_HOVER := Color(0.23, 0.245, 0.29, 1.0)
const BG_DEEP := Color(0.05, 0.055, 0.068, 0.96)     # fondos de gráficas y tablas
const BORDER := Color(1, 1, 1, 0.07)
const BORDER_STRONG := Color(1, 1, 1, 0.14)
const ACCENT := Color(0.93, 0.76, 0.35)              # dorado de la dinastía
const ACCENT_DIM := Color(0.55, 0.43, 0.18)
const ACCENT_2 := Color(0.38, 0.72, 0.86)            # azul secundario (datos, enlaces)
const TEXT := Color(0.94, 0.94, 0.95)
const TEXT_DIM := Color(0.7, 0.72, 0.77)
const TEXT_FAINT := Color(0.5, 0.52, 0.57)
# Semánticos
const GOOD := Color(0.4, 0.83, 0.5)       # ganancia, bien
const BAD := Color(0.95, 0.4, 0.38)       # pérdida, peligro
const WARN := Color(0.97, 0.72, 0.28)     # aviso
const INFO := Color(0.45, 0.66, 0.96)     # información
const NEUTRAL := Color(0.62, 0.64, 0.7)
# Serie de colores para gráficas (distinguibles entre sí y sobre fondo oscuro).
const SERIES := [Color(0.93, 0.76, 0.35), Color(0.38, 0.72, 0.86), Color(0.45, 0.8, 0.5), Color(0.9, 0.45, 0.55),
	Color(0.68, 0.55, 0.92), Color(0.95, 0.58, 0.3), Color(0.35, 0.8, 0.75), Color(0.75, 0.75, 0.8)]

# --- Tipografía (px lógicos) --------------------------------------------------------------------
const FS_TITLE := 20
const FS_H2 := 16
const FS_BODY := 14
const FS_SMALL := 12
const FS_TINY := 11
# --- Espaciados -------------------------------------------------------------------------------------
const SP_XS := 4
const SP_S := 6
const SP_M := 10
const SP_L := 16
const RADIUS := 8

## Color e icono por categoría de notificación.
const CATEGORY_COLORS := {
	"info": Color(0.62, 0.72, 0.9), "nacimiento": Color(0.5, 0.85, 0.55),
	"muerte": Color(0.72, 0.6, 0.66), "salud": Color(0.95, 0.55, 0.5),
	"boda": Color(0.95, 0.62, 0.85), "emigracion": Color(0.95, 0.55, 0.35),
	"clima": Color(0.55, 0.8, 0.95), "importante": Color(1.0, 0.82, 0.3),
	"jugador": Color(1.0, 0.45, 0.4), "negocio": Color(0.45, 0.85, 0.65),
	"construccion": Color(0.92, 0.72, 0.45), "familia": Color(1.0, 0.68, 0.85),
}
const CATEGORY_ICONS := {
	"info": "info", "nacimiento": "baby", "muerte": "tomb", "salud": "health", "boda": "ring",
	"emigracion": "exit", "clima": "cloud", "importante": "star", "jugador": "alert", "negocio": "companies",
	"construccion": "build", "familia": "family",
}
const CATEGORY_LABELS := {
	"info": "General", "nacimiento": "Nacimientos", "muerte": "Muertes", "salud": "Salud", "boda": "Bodas",
	"emigracion": "Emigración", "clima": "Clima", "importante": "Importante", "jugador": "Avisos",
	"negocio": "Negocios", "construccion": "Obras", "familia": "Familia",
}

const SETTINGS_PATH := "user://ui_settings.cfg"
static var _user_scale := -1.0
static var _theme: Theme = null


# --- Estilos ------------------------------------------------------------------------------------------

static func panel_style(color := BG, radius := RADIUS, pad := 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(pad)
	sb.border_color = BORDER
	sb.set_border_width_all(1)
	sb.anti_aliasing = true
	return sb


## Panel flotante con sombra suave.
static func float_style(color := BG, radius := 12, pad := 12) -> StyleBoxFlat:
	var sb := panel_style(color, radius, pad)
	sb.shadow_color = Color(0, 0, 0, 0.38)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 3)
	return sb


## Tarjeta con franja de color a la izquierda (estado, categoría).
static func card_style(stripe := Color(0, 0, 0, 0), pad := 8, bg := BG_LIGHT) -> StyleBoxFlat:
	var sb := panel_style(bg, 8, pad)
	if stripe.a > 0.0:
		sb.border_color = stripe
		sb.border_width_left = 3
		sb.border_width_top = 0
		sb.border_width_right = 0
		sb.border_width_bottom = 0
		sb.content_margin_left = pad + 3
	return sb


static func _flat(color: Color, radius := 7, pad_h := 10, pad_v := 5, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v
	if bw > 0:
		sb.border_color = border
		sb.set_border_width_all(bw)
	sb.anti_aliasing = true
	return sb


## Tema común de toda la interfaz (HUD, paneles, menú principal, minimapa).
static func make_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = 15
	t.set_stylebox("panel", "PanelContainer", float_style())
	t.set_stylebox("panel", "Panel", float_style())
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_constant("line_separation", "RichTextLabel", 2)
	t.set_constant("table_h_separation", "RichTextLabel", 8)
	t.set_constant("table_v_separation", "RichTextLabel", 3)
	t.set_color("table_odd_row_bg", "RichTextLabel", Color(1, 1, 1, 0.035))
	t.set_color("table_even_row_bg", "RichTextLabel", Color(0, 0, 0, 0))
	t.set_color("font_selected_color", "RichTextLabel", TEXT)
	t.set_color("selection_color", "RichTextLabel", Color(ACCENT, 0.35))
	# Botones
	var normal := _flat(BG_RAISED, 7, 10, 5, BORDER, 1)
	var hover := _flat(BG_HOVER, 7, 10, 5, Color(ACCENT, 0.45), 1)
	var pressed := _flat(Color(0.42, 0.33, 0.14), 7, 10, 5, ACCENT, 1)
	var disabled := _flat(Color(0.12, 0.125, 0.145, 0.85), 7, 10, 5, Color(1, 1, 1, 0.04), 1)
	var focus := _flat(Color(0, 0, 0, 0), 7, 10, 5, Color(ACCENT, 0.55), 1)
	focus.draw_center = false
	for type in ["Button", "OptionButton", "MenuButton", "CheckButton"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("hover_pressed", type, pressed)
		t.set_stylebox("disabled", type, disabled)
		t.set_stylebox("focus", type, focus)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, Color(1.0, 0.93, 0.75))
		t.set_color("font_hover_pressed_color", type, Color(1.0, 0.93, 0.75))
		t.set_color("font_focus_color", type, TEXT)
		t.set_color("font_disabled_color", type, Color(0.47, 0.48, 0.52))
		t.set_color("icon_normal_color", type, TEXT_DIM)
		t.set_color("icon_hover_color", type, Color.WHITE)
		t.set_color("icon_pressed_color", type, ACCENT)
		t.set_color("icon_hover_pressed_color", type, ACCENT)
		t.set_color("icon_focus_color", type, TEXT)
		t.set_color("icon_disabled_color", type, Color(0.4, 0.4, 0.44))
		t.set_constant("h_separation", type, 6)
	t.set_constant("icon_max_width", "Button", 20)
	t.set_icon("arrow", "OptionButton", UIIcons.tex("chevron_down", 14))
	# CheckBox
	var cb_style := _flat(Color(0, 0, 0, 0), 6, 4, 3)
	cb_style.draw_center = false
	for st in ["normal", "pressed", "hover", "hover_pressed", "focus", "disabled"]:
		t.set_stylebox(st, "CheckBox", cb_style if st != "hover" and st != "hover_pressed" else _flat(Color(1, 1, 1, 0.05), 6, 4, 3))
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_hover_color", "CheckBox", Color.WHITE)
	t.set_color("font_pressed_color", "CheckBox", TEXT)
	t.set_color("font_hover_pressed_color", "CheckBox", Color.WHITE)
	t.set_icon("checked", "CheckBox", UIIcons.checkbox(true))
	t.set_icon("unchecked", "CheckBox", UIIcons.checkbox(false))
	t.set_icon("radio_checked", "CheckBox", UIIcons.checkbox(true, true))
	t.set_icon("radio_unchecked", "CheckBox", UIIcons.checkbox(false, true))
	# Pestañas: subrayado dorado en la activa
	var tab_sel := _flat(Color(1, 1, 1, 0.06), 6, 10, 5)
	tab_sel.corner_radius_bottom_left = 0
	tab_sel.corner_radius_bottom_right = 0
	tab_sel.border_color = ACCENT
	tab_sel.border_width_bottom = 2
	var tab_un := _flat(Color(0, 0, 0, 0), 6, 10, 5)
	tab_un.border_color = Color(1, 1, 1, 0.06)
	tab_un.border_width_bottom = 2
	var tab_hov := _flat(Color(1, 1, 1, 0.04), 6, 10, 5)
	tab_hov.border_color = Color(ACCENT, 0.4)
	tab_hov.border_width_bottom = 2
	for type in ["TabContainer", "TabBar"]:
		t.set_stylebox("tab_selected", type, tab_sel)
		t.set_stylebox("tab_unselected", type, tab_un)
		t.set_stylebox("tab_hovered", type, tab_hov)
		t.set_stylebox("tab_disabled", type, tab_un)
		t.set_stylebox("tab_focus", type, StyleBoxEmpty.new())
		t.set_color("font_selected_color", type, ACCENT)
		t.set_color("font_unselected_color", type, TEXT_DIM)
		t.set_color("font_hovered_color", type, Color.WHITE)
		t.set_color("font_disabled_color", type, TEXT_FAINT)
		t.set_font_size("font_size", type, 14)
		t.set_constant("h_separation", type, 4)
	var tab_panel := StyleBoxFlat.new()
	tab_panel.bg_color = Color(0, 0, 0, 0)
	tab_panel.content_margin_top = 8
	tab_panel.content_margin_left = 2
	tab_panel.content_margin_right = 2
	t.set_stylebox("panel", "TabContainer", tab_panel)
	t.set_stylebox("tabbar_background", "TabContainer", StyleBoxEmpty.new())
	t.set_constant("side_margin", "TabContainer", 0)
	# Campos de texto
	var le := _flat(Color(0.06, 0.065, 0.08, 1.0), 6, 8, 5, BORDER_STRONG, 1)
	var le_focus := _flat(Color(0.06, 0.065, 0.08, 1.0), 6, 8, 5, Color(ACCENT, 0.8), 1)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", le_focus)
	t.set_stylebox("read_only", "LineEdit", _flat(Color(0.08, 0.085, 0.1, 1.0), 6, 8, 5, BORDER, 1))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_FAINT)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", Color(ACCENT, 0.35))
	# Menús emergentes (OptionButton, MenuButton)
	var pop := float_style(Color(0.1, 0.11, 0.135, 0.98), 8, 6)
	t.set_stylebox("panel", "PopupMenu", pop)
	t.set_stylebox("hover", "PopupMenu", _flat(Color(ACCENT, 0.2), 5, 8, 4))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_color("font_disabled_color", "PopupMenu", TEXT_FAINT)
	t.set_constant("v_separation", "PopupMenu", 6)
	t.set_stylebox("panel", "PopupPanel", pop)
	# Tooltips
	var tip := float_style(Color(0.07, 0.075, 0.09, 0.97), 7, 8)
	tip.border_color = Color(ACCENT, 0.35)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", 13)
	# Barras de progreso
	var pb_bg := _flat(Color(1, 1, 1, 0.07), 5, 0, 0)
	var pb_fill := _flat(ACCENT, 5, 0, 0)
	t.set_stylebox("background", "ProgressBar", pb_bg)
	t.set_stylebox("fill", "ProgressBar", pb_fill)
	t.set_color("font_color", "ProgressBar", TEXT)
	t.set_color("font_outline_color", "ProgressBar", Color(0, 0, 0, 0.8))
	t.set_constant("outline_size", "ProgressBar", 3)
	t.set_font_size("font_size", "ProgressBar", 12)
	# Barras de desplazamiento finas y redondeadas
	for type in ["VScrollBar", "HScrollBar"]:
		var sc := StyleBoxFlat.new()
		sc.bg_color = Color(1, 1, 1, 0.025)
		sc.set_corner_radius_all(4)
		sc.set_content_margin_all(3 if type == "VScrollBar" else 2)
		t.set_stylebox("scroll", type, sc)
		t.set_stylebox("scroll_focus", type, sc)
		t.set_stylebox("grabber", type, _flat(Color(1, 1, 1, 0.18), 4, 3, 3))
		t.set_stylebox("grabber_highlight", type, _flat(Color(1, 1, 1, 0.3), 4, 3, 3))
		t.set_stylebox("grabber_pressed", type, _flat(Color(ACCENT, 0.7), 4, 3, 3))
	# Listas
	t.set_stylebox("panel", "ItemList", _flat(BG_DEEP, 8, 6, 6, BORDER, 1))
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("hovered", "ItemList", _flat(Color(1, 1, 1, 0.05), 5, 4, 2))
	t.set_stylebox("selected", "ItemList", _flat(Color(ACCENT, 0.22), 5, 4, 2))
	t.set_stylebox("selected_focus", "ItemList", _flat(Color(ACCENT, 0.28), 5, 4, 2))
	t.set_stylebox("cursor", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("cursor_unfocused", "ItemList", StyleBoxEmpty.new())
	t.set_color("font_color", "ItemList", TEXT)
	t.set_color("font_selected_color", "ItemList", Color.WHITE)
	t.set_color("font_hovered_color", "ItemList", Color.WHITE)
	t.set_color("guide_color", "ItemList", Color(1, 1, 1, 0.04))
	t.set_constant("v_separation", "ItemList", 6)
	# Separadores
	var sep := StyleBoxLine.new()
	sep.color = Color(1, 1, 1, 0.08)
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 8)
	var vsep := StyleBoxLine.new()
	vsep.color = Color(1, 1, 1, 0.08)
	vsep.vertical = true
	t.set_stylebox("separator", "VSeparator", vsep)
	# SpinBox: flechas visibles
	t.set_icon("updown", "SpinBox", UIIcons.tex("updown", 16))
	# Deslizadores (opciones)
	t.set_stylebox("slider", "HSlider", _flat(Color(1, 1, 1, 0.1), 3, 0, 2))
	t.set_stylebox("grabber_area", "HSlider", _flat(Color(ACCENT, 0.8), 3, 0, 2))
	t.set_stylebox("grabber_area_highlight", "HSlider", _flat(ACCENT, 3, 0, 2))
	t.set_icon("grabber", "HSlider", UIIcons.dot(16, ACCENT))
	t.set_icon("grabber_highlight", "HSlider", UIIcons.dot(18, Color(1.0, 0.86, 0.5)))
	_theme = t
	return t


# --- Escala (Retina / tamaño de interfaz) ------------------------------------------------------------

static func user_scale() -> float:
	if _user_scale < 0.0:
		var cfg := ConfigFile.new()
		_user_scale = 1.0
		if cfg.load(SETTINGS_PATH) == OK:
			_user_scale = clampf(float(cfg.get_value("ui", "scale", 1.0)), 0.7, 1.6)
	return _user_scale


static func set_user_scale(v: float, win: Window = null) -> void:
	_user_scale = clampf(v, 0.7, 1.6)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("ui", "scale", _user_scale)
	cfg.save(SETTINGS_PATH)
	if win != null:
		apply_scale(win)


## Escala automática: pantallas Retina/HiDPI (escala del sistema) y ventanas grandes, por el ajuste
## del jugador. Nunca deja un área lógica menor que 1200×700 (para que todo quepa).
static func auto_scale(win: Window) -> float:
	var px := Vector2(win.size)
	if px.x <= 0.0 or px.y <= 0.0:
		return 1.0
	var screen := 1.0
	if DisplayServer.get_name() != "headless":
		screen = maxf(1.0, DisplayServer.screen_get_scale(win.current_screen))
	var by_size := minf(px.x / 1600.0, px.y / 900.0)
	var s := maxf(screen, maxf(1.0, by_size)) * user_scale()
	s = minf(s, minf(px.x / 1200.0, px.y / 700.0))
	return snappedf(maxf(0.6, s), 0.05)


static func apply_scale(win: Window) -> void:
	if win == null:
		return
	var s := auto_scale(win)
	if not is_equal_approx(win.content_scale_factor, s):
		win.content_scale_factor = s


## Conecta el reescalado automático a los cambios de tamaño de la ventana.
static func hook_scale(node: Node) -> void:
	var win := node.get_window()
	if win == null:
		return
	apply_scale(win)
	if not win.size_changed.is_connected(_on_win_resized.bind(win)):
		win.size_changed.connect(_on_win_resized.bind(win))


static func _on_win_resized(win: Window) -> void:
	apply_scale(win)


# --- Animaciones ------------------------------------------------------------------------------------

## Entrada suave: opacidad y desplazamiento (px lógicos). Seguro en controles fuera de contenedores.
static func animate_in(c: Control, offset := Vector2(18, 0), dur := 0.18) -> void:
	if c == null or not c.is_inside_tree():
		return
	c.modulate.a = 0.0
	var in_container := c.get_parent() is Container
	var tw := c.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, dur)
	if not in_container and offset != Vector2.ZERO:
		var p0 := c.position
		c.position = p0 + offset
		tw.tween_property(c, "position", p0, dur)


## Salida: opacidad y desplazamiento; al terminar llama a `done` (p. ej., ocultar).
static func animate_out(c: Control, done: Callable, offset := Vector2(18, 0), dur := 0.14) -> void:
	if c == null or not c.is_inside_tree():
		done.call()
		return
	var in_container := c.get_parent() is Container
	var p0 := c.position
	var tw := c.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(c, "modulate:a", 0.0, dur)
	if not in_container and offset != Vector2.ZERO:
		tw.tween_property(c, "position", p0 + offset, dur)
	tw.chain().tween_callback(func():
		if not in_container:
			c.position = p0
		c.modulate.a = 1.0
		done.call())


## Escala suave para ventanas modales (desde el centro).
static func pop_in(c: Control, dur := 0.16) -> void:
	if c == null or not c.is_inside_tree():
		return
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2(0.96, 0.96)
	c.modulate.a = 0.0
	var tw := c.create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", Vector2.ONE, dur)
	tw.tween_property(c, "modulate:a", 1.0, dur * 0.8)


# --- Constructores ----------------------------------------------------------------------------------

static func label(text: String, size := 15, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, callback: Callable, min_width := 0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.x = min_width
	b.pressed.connect(callback)
	return b


## Botón con icono (y texto opcional). `size` = tamaño del icono.
static func icon_button(icon: String, callback: Callable, tip := "", text := "", size := 18) -> Button:
	var b := Button.new()
	b.icon = UIIcons.tex(icon, size)
	b.text = text
	b.tooltip_text = tip
	b.add_theme_constant_override("icon_max_width", size)
	b.pressed.connect(callback)
	if text == "":
		b.custom_minimum_size = Vector2(size + 14, size + 12)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return b


## Botón primario (dorado) para la acción principal de un grupo.
static func primary(b: Button) -> Button:
	b.add_theme_stylebox_override("normal", _flat(Color(0.52, 0.4, 0.15), 7, 10, 5, ACCENT, 1))
	b.add_theme_stylebox_override("hover", _flat(Color(0.62, 0.48, 0.18), 7, 10, 5, Color(1.0, 0.86, 0.5), 1))
	b.add_theme_color_override("font_color", Color(1.0, 0.95, 0.82))
	return b


## Botón de peligro (rojo) para acciones destructivas.
static func danger(b: Button) -> Button:
	b.add_theme_stylebox_override("normal", _flat(Color(0.3, 0.12, 0.12), 7, 10, 5, Color(BAD, 0.5), 1))
	b.add_theme_stylebox_override("hover", _flat(Color(0.42, 0.15, 0.15), 7, 10, 5, BAD, 1))
	return b


static func icon(name: String, size := 18, color := TEXT_DIM) -> TextureRect:
	var r := TextureRect.new()
	r.texture = UIIcons.tex(name, size)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(size, size)
	r.modulate = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Cabecera estándar de panel: icono + título + botones extra + cerrar. Devuelve el Label del título.
static func header(parent: Control, icon_name: String, title: String, close_cb: Callable, extra: Array = []) -> Label:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	parent.add_child(head)
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", _flat(Color(ACCENT, 0.16), 8, 5, 5))
	badge.add_child(icon(icon_name, 20, ACCENT))
	head.add_child(badge)
	var t := label(title, FS_TITLE, ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(t)
	for b in extra:
		head.add_child(b)
	var x := icon_button("close", close_cb, "Cerrar (Esc)", "", 16)
	x.name = "Close"
	head.add_child(x)
	return t


## Sección plegable: título con flecha; devuelve el contenedor del contenido.
static func section(parent: Control, title: String, icon_name := "", open := true, key := "") -> VBoxContainer:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 6)
	parent.add_child(wrap)
	var head := Button.new()
	head.flat = true
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.text = title
	head.add_theme_font_size_override("font_size", FS_H2)
	head.add_theme_color_override("font_color", ACCENT)
	head.add_theme_color_override("font_hover_color", Color(1.0, 0.86, 0.5))
	head.add_theme_color_override("font_pressed_color", ACCENT)
	head.add_theme_color_override("font_focus_color", ACCENT)
	head.add_theme_color_override("icon_normal_color", ACCENT)
	head.add_theme_color_override("icon_hover_color", Color(1.0, 0.86, 0.5))
	head.add_theme_color_override("icon_pressed_color", ACCENT)
	head.add_theme_color_override("icon_focus_color", ACCENT)
	head.add_theme_stylebox_override("normal", _flat(Color(0, 0, 0, 0), 6, 2, 3))
	head.add_theme_stylebox_override("hover", _flat(Color(1, 1, 1, 0.04), 6, 2, 3))
	head.add_theme_stylebox_override("pressed", _flat(Color(0, 0, 0, 0), 6, 2, 3))
	head.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	head.add_theme_constant_override("icon_max_width", 14)
	wrap.add_child(head)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	wrap.add_child(body)
	var k := key if key != "" else title
	var is_open: bool = bool(_folds.get(k, open))
	body.visible = is_open
	head.icon = UIIcons.tex("chevron_down" if is_open else "chevron_right", 14)
	head.tooltip_text = "Clic para plegar o desplegar"
	head.pressed.connect(func():
		body.visible = not body.visible
		_folds[k] = body.visible
		head.icon = UIIcons.tex("chevron_down" if body.visible else "chevron_right", 14))
	if icon_name != "":
		pass
	return body


static var _folds := {}


## Etiqueta tipo "chip" (estado, categoría).
static func chip(text: String, color: Color, icon_name := "", size := FS_SMALL) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _flat(Color(color, 0.16), 9, 7, 2, Color(color, 0.45), 1))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	p.add_child(h)
	if icon_name != "":
		h.add_child(icon(icon_name, size + 1, color))
	h.add_child(label(text, size, color.lightened(0.2)))
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	return p


## Barra de progreso compacta coloreada (0-1). Si `thresholds`, verde/ámbar/rojo según el valor.
static func progress(ratio: float, color := ACCENT, height := 8, thresholds := false, text := "") -> ProgressBar:
	var pb := ProgressBar.new()
	pb.min_value = 0.0
	pb.max_value = 1.0
	pb.value = clampf(ratio, 0.0, 1.0)
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(40, height)
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var c := level_color(ratio) if thresholds else color
	pb.add_theme_stylebox_override("fill", _flat(c, 4, 0, 0))
	pb.add_theme_stylebox_override("background", _flat(Color(1, 1, 1, 0.07), 4, 0, 0))
	if text != "":
		pb.tooltip_text = text
	return pb


## Fila "icono · etiqueta · barra · valor" para indicadores (necesidades, salud, felicidad…).
static func meter_row(icon_name: String, text: String, ratio: float, value_text := "", thresholds := true, color := ACCENT) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var c := level_color(ratio) if thresholds else color
	h.add_child(icon(icon_name, 16, c))
	var l := label(text, FS_SMALL, TEXT_DIM)
	l.custom_minimum_size.x = 84
	h.add_child(l)
	var pb := progress(ratio, c, 8)
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(pb)
	var v := label(value_text if value_text != "" else Fmt.pct(ratio * 100.0), FS_SMALL, c)
	v.custom_minimum_size.x = 40
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(v)
	return h


## Verde ≥ 0,6 · ámbar ≥ 0,35 · rojo debajo.
static func level_color(ratio: float) -> Color:
	if ratio >= 0.6:
		return GOOD
	if ratio >= 0.35:
		return WARN
	return BAD


## Verde si positivo, rojo si negativo, gris si cero.
static func sign_color(v: float) -> Color:
	if v > 0.0001:
		return GOOD
	if v < -0.0001:
		return BAD
	return NEUTRAL


## Etiqueta de dinero coloreada por signo.
static func money_label(v: float, size := FS_BODY, signed := false) -> Label:
	var txt := Fmt.money(v)
	if signed and v > 0.0:
		txt = "+" + txt
	return label(txt, size, sign_color(v))


## "▲ 3,2%" en verde / "▼ 1,0%" en rojo. `invert` cuando subir es malo (precios, crimen).
static func trend_bbcode(delta_ratio: float, invert := false) -> String:
	if absf(delta_ratio) < 0.005:
		return "[color=#8a8f99]＝[/color]"
	var up := delta_ratio > 0.0
	var good := up != invert
	var col := GOOD if good else BAD
	return "[color=#%s]%s %s[/color]" % [col.to_html(false), "▲" if up else "▼", Fmt.pct_1(absf(delta_ratio) * 100.0)]


## Ventana modal centrada con fondo oscurecido. Devuelve {root, panel, body, title}.
static func modal(parent: Node, title: String, min_size := Vector2(460, 0), icon_name := "") -> Dictionary:
	var root := ColorRect.new()
	root.color = Color(0.02, 0.025, 0.035, 0.55)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(root)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = min_size
	panel.add_theme_stylebox_override("panel", float_style(BG, 14, 18))
	center.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	panel.add_child(body)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	body.add_child(head)
	if icon_name != "":
		head.add_child(icon(icon_name, 22, ACCENT))
	var t := label(title, 21, ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	body.add_child(HSeparator.new())
	root.visible = false
	root.visibility_changed.connect(func():
		if root.visible:
			root.move_to_front.call_deferred()   # por encima de todo (p. ej., el minimapa)
			pop_in(panel))
	return {"root": root, "panel": panel, "body": body, "title": t, "head": head}


static func clear(node: Node) -> void:
	for ch in node.get_children():
		node.remove_child(ch)
		ch.queue_free()


static func spin(min_v: float, max_v: float, step: float, value: float, on_change: Callable, width := 110) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.custom_minimum_size.x = width
	s.value_changed.connect(on_change)
	return s


static func rich(min_size := Vector2(0, 0)) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.custom_minimum_size = min_size
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return r


static func scroll_box(min_size: Vector2) -> Dictionary:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = min_size
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	sc.add_child(v)
	return {"scroll": sc, "box": v}


## Rejilla de tarjetas que se adapta al ancho (HFlowContainer).
static func flow(h_sep := 8, v_sep := 8) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", h_sep)
	f.add_theme_constant_override("v_separation", v_sep)
	f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return f


## Tarjeta (PanelContainer + VBox). Devuelve {panel, box}.
static func card(stripe := Color(0, 0, 0, 0), pad := 8, min_w := 0.0) -> Dictionary:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", card_style(stripe, pad))
	p.custom_minimum_size.x = min_w
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	return {"panel": p, "box": v}


## Tarjeta de indicador: icono, título, valor grande, tendencia y sparkline.
static func kpi_card(icon_name: String, title: String, value: String, trend := "", spark: Array = [], color := ACCENT, tip := "", width := 196.0) -> PanelContainer:
	var c := card(Color(0, 0, 0, 0), 8, width)
	var p: PanelContainer = c["panel"]
	var v: VBoxContainer = c["box"]
	p.tooltip_text = tip
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	v.add_theme_constant_override("separation", 2)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	v.add_child(h)
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", _flat(Color(color, 0.16), 6, 4, 4))
	badge.add_child(icon(icon_name, 16, color))
	h.add_child(badge)
	var tl := label(title, FS_SMALL, TEXT_DIM)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.clip_text = true
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(tl)
	var row := HBoxContainer.new()
	v.add_child(row)
	var vl := label(value, 19, TEXT)
	vl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(vl)
	if trend != "":
		var tr := rich()
		tr.fit_content = true
		tr.autowrap_mode = TextServer.AUTOWRAP_OFF
		tr.size_flags_horizontal = Control.SIZE_SHRINK_END
		tr.add_theme_font_size_override("normal_font_size", FS_SMALL)
		tr.text = trend
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(tr)
	if spark.size() >= 2:
		var sp := Sparkline.new()
		sp.custom_minimum_size = Vector2(0, 26)
		sp.set_values(spark, color)
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(sp)
	return p


## Panel lateral derecho (bajo la barra superior).
static func right_panel(width: float) -> PanelContainer:
	var p := PanelContainer.new()
	p.anchor_left = 1.0
	p.anchor_right = 1.0
	p.anchor_bottom = 1.0
	p.offset_left = -width - 10
	p.offset_right = -10
	p.offset_top = 54
	p.offset_bottom = -10
	p.visible = false
	return p
