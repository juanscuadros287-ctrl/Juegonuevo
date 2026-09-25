class_name Sparkline
extends Control
## Mini-gráfica de tendencia (sin ejes) con relleno suave y punto final.

var values: Array = []
var color := UIKit.ACCENT
var baseline_zero := false


func _init() -> void:
	custom_minimum_size = Vector2(60, 22)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_values(p_values: Array, p_color := UIKit.ACCENT) -> void:
	values = p_values
	color = p_color
	queue_redraw()


func _draw() -> void:
	if values.size() < 2:
		return
	var lo := INF
	var hi := -INF
	for v in values:
		lo = minf(lo, float(v))
		hi = maxf(hi, float(v))
	if baseline_zero:
		lo = minf(lo, 0.0)
	if is_equal_approx(lo, hi):
		lo -= 1.0
		hi += 1.0
	var pts := PackedVector2Array()
	var h := size.y - 4.0
	for i in range(values.size()):
		pts.append(Vector2(size.x * float(i) / float(values.size() - 1), 2.0 + h * (1.0 - (float(values[i]) - lo) / (hi - lo))))
	var c := LineChart.curve(pts, true, 4)
	var poly := c.duplicate()
	poly.append(Vector2(size.x, size.y))
	poly.append(Vector2(0, size.y))
	var cols := PackedColorArray()
	for p in poly:
		cols.append(Color(color, 0.0 if p.y >= size.y - 0.5 else 0.22 * (1.0 - p.y / size.y)))
	if Geometry2D.triangulate_polygon(poly).size() > 0:
		draw_polygon(poly, cols)
	draw_polyline(c, color, 1.6, true)
	draw_circle(pts[pts.size() - 1], 2.4, color)
