class_name Gauge
extends Control
## Medidor semicircular (0-1) con color por umbral (verde/ámbar/rojo) y aguja animada.
## invert = true cuando un valor alto es malo (crimen, contaminación).

var value := 0.0
var label_text := ""
var value_text := ""
var invert := false
var _shown := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(96, 70)
	mouse_filter = Control.MOUSE_FILTER_PASS


func set_value(v: float, p_label := "", p_text := "", p_invert := false) -> void:
	value = clampf(v, 0.0, 1.0)
	label_text = p_label
	value_text = p_text
	invert = p_invert
	if is_inside_tree():
		create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).tween_method(func(x: float): _shown = x; queue_redraw(), _shown, value, 0.6)
	else:
		_shown = value
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	var rad := minf(size.x * 0.42, (size.y - 22.0))
	var c := Vector2(size.x * 0.5, rad + 6.0)
	var a0 := PI
	var a1 := TAU
	draw_arc(c, rad, a0, a1, 48, Color(1, 1, 1, 0.08), 8.0, true)
	var q := 1.0 - _shown if invert else _shown
	var col := UIKit.level_color(q)
	draw_arc(c, rad, a0, lerpf(a0, a1, _shown), 48, col, 8.0, true)
	var ang := lerpf(a0, a1, _shown)
	draw_line(c, c + Vector2(cos(ang), sin(ang)) * (rad - 10.0), UIKit.TEXT, 2.0, true)
	draw_circle(c, 3.5, UIKit.TEXT)
	var vt := value_text if value_text != "" else Fmt.pct(value * 100.0)
	var w := font.get_string_size(vt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string(font, Vector2(c.x - w * 0.5, c.y + 18), vt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col.lightened(0.2))
	if label_text != "":
		var w2 := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(font, Vector2(c.x - w2 * 0.5, c.y + 32), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIKit.TEXT_DIM)
