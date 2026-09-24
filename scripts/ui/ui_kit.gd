class_name UIKit
extends RefCounted
## Estilos y constructores de controles reutilizables.

const BG := Color(0.1, 0.11, 0.13, 0.92)
const BG_LIGHT := Color(0.16, 0.17, 0.2, 0.95)
const ACCENT := Color(0.93, 0.76, 0.35)
const TEXT_DIM := Color(0.75, 0.75, 0.78)

const CATEGORY_COLORS := {
	"info": Color(0.75, 0.8, 0.9), "nacimiento": Color(0.55, 0.85, 0.55),
	"muerte": Color(0.8, 0.55, 0.55), "salud": Color(0.95, 0.7, 0.4),
	"boda": Color(0.95, 0.65, 0.85), "emigracion": Color(0.95, 0.5, 0.35),
	"clima": Color(0.6, 0.8, 0.95), "importante": Color(1.0, 0.85, 0.3),
	"jugador": Color(1.0, 0.4, 0.4), "negocio": Color(0.6, 0.9, 0.75),
	"construccion": Color(0.9, 0.8, 0.55), "familia": Color(1.0, 0.7, 0.9),
}


static func panel_style(color := BG, radius := 8, pad := 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(pad)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.set_border_width_all(1)
	return sb


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 15
	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_stylebox("panel", "Panel", panel_style())
	t.set_color("font_color", "Label", Color(0.95, 0.95, 0.95))
	var btn := panel_style(Color(0.22, 0.24, 0.28), 6, 6)
	var btn_h := panel_style(Color(0.3, 0.33, 0.38), 6, 6)
	var btn_p := panel_style(Color(0.55, 0.43, 0.18), 6, 6)
	var btn_d := panel_style(Color(0.16, 0.16, 0.18, 0.8), 6, 6)
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover", "Button", btn_h)
	t.set_stylebox("pressed", "Button", btn_p)
	t.set_stylebox("hover_pressed", "Button", btn_p)
	t.set_stylebox("disabled", "Button", btn_d)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.5, 0.5))
	return t


static func label(text: String, size := 15, color := Color(0.95, 0.95, 0.95)) -> Label:
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


## Ventana modal centrada con fondo oscurecido. Devuelve {root, panel, body, title}.
static func modal(parent: Node, title: String, min_size := Vector2(460, 0)) -> Dictionary:
	var root := ColorRect.new()
	root.color = Color(0, 0, 0, 0.45)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(root)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = min_size
	panel.add_theme_stylebox_override("panel", panel_style(BG, 10, 18))
	center.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	panel.add_child(body)
	var t := label(title, 22, ACCENT)
	body.add_child(t)
	body.add_child(HSeparator.new())
	root.visible = false
	return {"root": root, "panel": panel, "body": body, "title": t}


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
	return r


static func scroll_box(min_size: Vector2) -> Dictionary:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = min_size
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 4)
	sc.add_child(v)
	return {"scroll": sc, "box": v}


## Panel lateral derecho (bajo la barra superior).
static func right_panel(width: float) -> PanelContainer:
	var p := PanelContainer.new()
	p.anchor_left = 1.0
	p.anchor_right = 1.0
	p.anchor_bottom = 1.0
	p.offset_left = -width - 12
	p.offset_right = -12
	p.offset_top = 58
	p.offset_bottom = -12
	p.visible = false
	return p
