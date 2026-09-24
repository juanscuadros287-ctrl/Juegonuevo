class_name LineChart
extends Control
## Gráfica de líneas simple para series históricas.

var series: Array = []      # [{label, color, values: Array[float]}]
var title := ""
var format_money := true


func set_data(p_title: String, p_series: Array, money := true) -> void:
	title = p_title
	series = p_series
	format_money = money
	queue_redraw()


func _fmt(v: float) -> String:
	if format_money:
		return Fmt.money(v)
	return String.num(v, 2)


func _draw() -> void:
	var font := get_theme_default_font()
	var fs := 12
	var r := Rect2(Vector2(58, 22), size - Vector2(66, 44))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.13, 0.14, 0.17, 0.9))
	draw_string(font, Vector2(8, 15), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIKit.ACCENT)
	var lo := INF
	var hi := -INF
	var n := 0
	for s in series:
		for v in s["values"]:
			lo = minf(lo, float(v))
			hi = maxf(hi, float(v))
		n = maxi(n, s["values"].size())
	if n < 2:
		draw_string(font, r.position + Vector2(0, r.size.y * 0.5), "Sin datos todavía (se registra cada mes)", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UIKit.TEXT_DIM)
		return
	if is_equal_approx(lo, hi):
		hi = lo + 1.0
	lo = minf(lo, 0.0) if lo >= 0.0 and lo < hi * 0.3 else lo
	for i in range(3):
		var t := i / 2.0
		var y := r.position.y + r.size.y * (1.0 - t)
		draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(1, 1, 1, 0.07))
		draw_string(font, Vector2(2, y + 4), _fmt(lerpf(lo, hi, t)), HORIZONTAL_ALIGNMENT_LEFT, 54, 10, UIKit.TEXT_DIM)
	if lo < 0.0 and hi > 0.0:
		var y0 := r.position.y + r.size.y * (1.0 - (0.0 - lo) / (hi - lo))
		draw_line(Vector2(r.position.x, y0), Vector2(r.end.x, y0), Color(1, 1, 1, 0.25))
	var lx := r.position.x
	for s in series:
		var vals: Array = s["values"]
		var pts := PackedVector2Array()
		for i in range(vals.size()):
			var x := r.position.x + r.size.x * float(i) / float(maxi(1, n - 1))
			var y := r.position.y + r.size.y * (1.0 - (float(vals[i]) - lo) / (hi - lo))
			pts.append(Vector2(x, y))
		if pts.size() >= 2:
			draw_polyline(pts, s["color"], 2.0, true)
		draw_rect(Rect2(Vector2(lx, size.y - 14), Vector2(10, 10)), s["color"])
		draw_string(font, Vector2(lx + 14, size.y - 5), str(s["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.9, 0.9, 0.9))
		lx += 24 + font.get_string_size(str(s["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
