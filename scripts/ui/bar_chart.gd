class_name BarChart
extends Control
## Barras horizontales (una o dos series por categoría) con animación de crecimiento y valor al
## pasar el mouse. set_data(titulo, [{label, values: [v1, v2?]}], [{label, color}], dinero?)

var title := ""
var rows: Array = []        # [{label, values: Array[float]}]
var legend: Array = []      # [{label, color}] por serie
var format_money := true
var row_h := 20.0
var _progress := 1.0
var _hover := -1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = true


func set_data(p_title: String, p_rows: Array, p_legend: Array, money := true) -> void:
	title = p_title
	rows = p_rows
	legend = p_legend
	format_money = money
	var nser := maxi(1, legend.size())
	custom_minimum_size.y = 34.0 + rows.size() * (row_h + 2.0 * (nser - 1) + 4.0) + 18.0
	_progress = 0.0
	if is_inside_tree():
		create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).tween_method(func(v: float): _progress = v; queue_redraw(), 0.0, 1.0, 0.55)
	else:
		_progress = 1.0
	queue_redraw()


func _fmt(v: float) -> String:
	return Fmt.money_compact(v) if format_money else Fmt.compact(v)


func _row_y(i: int) -> float:
	var nser := maxi(1, legend.size())
	return 28.0 + i * (row_h + 2.0 * (nser - 1) + 4.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := -1
		for i in range(rows.size()):
			if event.position.y >= _row_y(i) and event.position.y < _row_y(i + 1):
				h = i
		if h != _hover:
			_hover = h
			queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hover != -1:
		_hover = -1
		queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	draw_style_box(UIKit._flat(UIKit.BG_DEEP, 8, 0, 0, UIKit.BORDER, 1), Rect2(Vector2.ZERO, size))
	draw_string(font, Vector2(10, 17), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, 13, UIKit.ACCENT)
	if rows.is_empty():
		draw_string(font, Vector2(10, 44), "Sin datos todavía", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIKit.TEXT_DIM)
		return
	var mx := 0.0001
	for r in rows:
		for v in r["values"]:
			mx = maxf(mx, absf(float(v)))
	var label_w := 92.0
	var x0 := label_w + 14.0
	var w := size.x - x0 - 64.0
	var nser := maxi(1, legend.size())
	var bh := (row_h - 2.0 * (nser - 1)) / float(nser) if nser > 1 else row_h - 6.0
	for i in range(rows.size()):
		var r: Dictionary = rows[i]
		var y := _row_y(i)
		if i == _hover:
			draw_rect(Rect2(Vector2(4, y - 2), Vector2(size.x - 8, row_h + 2.0 * (nser - 1) + 2)), Color(1, 1, 1, 0.05))
		draw_string(font, Vector2(10, y + row_h * 0.5 + 4), str(r["label"]), HORIZONTAL_ALIGNMENT_LEFT, label_w, 11, UIKit.TEXT_DIM)
		var vals: Array = r["values"]
		for s in range(vals.size()):
			var v := float(vals[s])
			var col: Color = legend[s]["color"] if s < legend.size() else UIKit.SERIES[s % UIKit.SERIES.size()]
			if r.has("color"):
				col = r["color"]
			var by := y + (3.0 if nser == 1 else s * (bh + 2.0))
			var bw := maxf(2.0, w * absf(v) / mx * _progress)
			draw_style_box(UIKit._flat(col if i == _hover else col.darkened(0.12), 3, 0, 0), Rect2(Vector2(x0, by), Vector2(bw, bh)))
			if nser == 1 or i == _hover:
				draw_string(font, Vector2(x0 + bw + 5, by + bh * 0.5 + 4), _fmt(v), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col.lightened(0.25))
	# Leyenda
	if legend.size() > 1:
		var lx := 10.0
		for l in legend:
			draw_circle(Vector2(lx + 4, size.y - 9.5), 3.5, l["color"])
			draw_string(font, Vector2(lx + 12, size.y - 6), str(l["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIKit.TEXT_DIM)
			lx += 24 + font.get_string_size(str(l["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
