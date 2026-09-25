class_name DonutChart
extends Control
## Gráfica de dona (o torta si hole = 0) con leyenda, total al centro, animación de barrido y
## resaltado del sector bajo el mouse. set_data(titulo, [{label, value, color?}], texto_central)

var title := ""
var slices: Array = []
var center_text := ""
var center_sub := ""
var hole := 0.58
var _progress := 1.0
var _hover := -1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = Vector2(200, 170)


func set_data(p_title: String, p_slices: Array, p_center := "", p_sub := "") -> void:
	title = p_title
	slices = p_slices.filter(func(s): return float(s["value"]) > 0.0)
	center_text = p_center
	center_sub = p_sub
	custom_minimum_size.y = maxf(170.0, 36.0 + slices.size() * 17.0)
	_progress = 0.0
	if is_inside_tree():
		create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).tween_method(func(v: float): _progress = v; queue_redraw(), 0.0, 1.0, 0.7)
	else:
		_progress = 1.0
	queue_redraw()


func _total() -> float:
	var t := 0.0
	for s in slices:
		t += float(s["value"])
	return t


func _geom() -> Array:
	var rad := minf((size.y - 34.0) * 0.5, size.x * 0.22)
	var c := Vector2(14.0 + rad, 26.0 + (size.y - 26.0) * 0.5)
	return [c, rad]


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var g := _geom()
		var d: Vector2 = event.position - g[0]
		var h := -1
		if d.length() <= float(g[1]) + 4.0 and d.length() >= float(g[1]) * hole - 2.0:
			var ang := fposmod(atan2(d.y, d.x) + PI * 0.5, TAU)
			var acc := 0.0
			var tot := _total()
			for i in range(slices.size()):
				acc += float(slices[i]["value"]) / tot * TAU
				if ang <= acc:
					h = i
					break
		else:
			# Sobre la leyenda
			for i in range(slices.size()):
				var ly := 34.0 + i * 17.0
				if event.position.x > float(g[0].x) + float(g[1]) + 10 and event.position.y >= ly - 12 and event.position.y < ly + 5:
					h = i
		if h != _hover:
			_hover = h
			queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hover != -1:
		_hover = -1
		queue_redraw()


func _color(i: int) -> Color:
	var s: Dictionary = slices[i]
	return s["color"] if s.has("color") else UIKit.SERIES[i % UIKit.SERIES.size()]


func _draw() -> void:
	var font := get_theme_default_font()
	draw_style_box(UIKit._flat(UIKit.BG_DEEP, 8, 0, 0, UIKit.BORDER, 1), Rect2(Vector2.ZERO, size))
	draw_string(font, Vector2(10, 17), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, 13, UIKit.ACCENT)
	var tot := _total()
	if tot <= 0.0:
		draw_string(font, Vector2(10, 50), "Sin datos todavía", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIKit.TEXT_DIM)
		return
	var g := _geom()
	var c: Vector2 = g[0]
	var rad: float = g[1]
	var a0 := -PI * 0.5
	var sweep_total := TAU * _progress
	var done := 0.0
	for i in range(slices.size()):
		var frac := float(slices[i]["value"]) / tot
		var a1 := a0 + frac * TAU
		var draw_end := minf(a1, -PI * 0.5 + sweep_total)
		if draw_end > a0:
			var r_out := rad + (4.0 if i == _hover else 0.0)
			var pts := PackedVector2Array()
			var steps := maxi(2, int((draw_end - a0) / 0.06))
			for k in range(steps + 1):
				var a := lerpf(a0, draw_end, float(k) / steps)
				pts.append(c + Vector2(cos(a), sin(a)) * r_out)
			for k in range(steps, -1, -1):
				var a := lerpf(a0, draw_end, float(k) / steps)
				pts.append(c + Vector2(cos(a), sin(a)) * rad * hole)
			var col := _color(i)
			draw_colored_polygon(pts, col if _hover < 0 or i == _hover else col.darkened(0.35))
		done += frac
		a0 = a1
	# Separadores finos entre sectores
	a0 = -PI * 0.5
	if _progress >= 1.0 and slices.size() > 1:
		for i in range(slices.size()):
			var dir := Vector2(cos(a0), sin(a0))
			draw_line(c + dir * rad * hole, c + dir * (rad + 4.0), UIKit.BG_DEEP, 2.0, true)
			a0 += float(slices[i]["value"]) / tot * TAU
	# Centro
	var ct := center_text
	var cs := center_sub
	if _hover >= 0:
		ct = Fmt.pct(float(slices[_hover]["value"]) / tot * 100.0)
		cs = str(slices[_hover]["label"])
	if ct != "":
		var w := font.get_string_size(ct, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		draw_string(font, c + Vector2(-w * 0.5, 4 if cs == "" else 0), ct, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UIKit.TEXT)
	if cs != "":
		var w2 := minf(rad * 2.0 * hole - 6.0, font.get_string_size(cs, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x)
		draw_string(font, c + Vector2(-w2 * 0.5, 14), cs, HORIZONTAL_ALIGNMENT_LEFT, rad * 2.0 * hole - 6.0, 10, UIKit.TEXT_DIM)
	# Leyenda
	var lx := c.x + rad + 16.0
	for i in range(slices.size()):
		var ly := 34.0 + i * 17.0
		if ly > size.y - 4:
			break
		var col := _color(i)
		draw_rect(Rect2(Vector2(lx, ly - 8), Vector2(9, 9)), col)
		var txt := "%s  %s" % [str(slices[i]["label"]), Fmt.pct(float(slices[i]["value"]) / tot * 100.0)]
		draw_string(font, Vector2(lx + 14, ly), txt, HORIZONTAL_ALIGNMENT_LEFT, size.x - lx - 18, 11, Color.WHITE if i == _hover else UIKit.TEXT_DIM)
