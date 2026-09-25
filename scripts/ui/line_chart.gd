class_name LineChart
extends Control
## Gráfica de líneas para series históricas: curvas suavizadas, relleno degradado, ejes limpios,
## leyenda, animación de dibujo y punto con valor y fecha al pasar el mouse.
## set_data(titulo, [{label, color, values: Array[float]}], dinero?, etiquetas_x?)

var series: Array = []      # [{label, color, values: Array[float]}]
var title := ""
var format_money := true
var x_labels: Array = []     # textos del eje X (fechas), opcionales
var smooth := true
var fill := true
var suffix := ""             # unidad para valores no monetarios ("%", " hab.")

var _progress := 1.0
var _hover := -1
var _tween: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = Vector2(200, 150)
	clip_contents = true


func set_data(p_title: String, p_series: Array, money := true, p_x_labels: Array = []) -> void:
	title = p_title
	series = p_series
	format_money = money
	x_labels = p_x_labels
	_animate()


func _animate() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_progress = 0.0
	if is_inside_tree():
		_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tween.tween_method(func(v: float): _progress = v; queue_redraw(), 0.0, 1.0, 0.6)
	else:
		_progress = 1.0
	queue_redraw()


func _fmt(v: float) -> String:
	if format_money:
		return Fmt.money_compact(v)
	return Fmt.compact(v) + suffix


func _fmt_full(v: float) -> String:
	if format_money:
		return Fmt.money(v) if absf(v) >= 100.0 else Fmt.money2(v)
	return (String.num(v, 2).replace(".", ",") if absf(v) < 100.0 else Fmt.thousands(v)) + suffix


func _count() -> int:
	var n := 0
	for s in series:
		n = maxi(n, (s["values"] as Array).size())
	return n


func _range() -> Vector2:
	var lo := INF
	var hi := -INF
	for s in series:
		for v in s["values"]:
			lo = minf(lo, float(v))
			hi = maxf(hi, float(v))
	if is_equal_approx(lo, hi):
		hi = lo + maxf(1.0, absf(lo) * 0.1)
	if lo >= 0.0 and lo < hi * 0.35:
		lo = 0.0
	var pad := (hi - lo) * 0.08
	return Vector2(lo - (pad if lo != 0.0 else 0.0), hi + pad)


func _plot_rect() -> Rect2:
	var top := 24.0 if title != "" else 8.0
	return Rect2(Vector2(50, top + 4), size - Vector2(58, top + 4 + 20))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var n := _count()
		if n < 2:
			return
		var r := _plot_rect()
		var i := int(roundf((event.position.x - r.position.x) / r.size.x * float(n - 1)))
		i = clampi(i, 0, n - 1) if r.grow(12).has_point(event.position) else -1
		if i != _hover:
			_hover = i
			queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hover != -1:
		_hover = -1
		queue_redraw()


## Puntos de la curva (Catmull-Rom si `smooth`).
static func curve(pts: PackedVector2Array, do_smooth: bool, steps := 6) -> PackedVector2Array:
	if not do_smooth or pts.size() < 3:
		return pts
	var out := PackedVector2Array()
	for i in range(pts.size() - 1):
		var p0 := pts[maxi(0, i - 1)]
		var p1 := pts[i]
		var p2 := pts[i + 1]
		var p3 := pts[mini(pts.size() - 1, i + 2)]
		for k in range(steps):
			var t := float(k) / steps
			var t2 := t * t
			var t3 := t2 * t
			var p := 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
			p.y = clampf(p.y, minf(p1.y, p2.y) - 6.0, maxf(p1.y, p2.y) + 6.0)
			out.append(p)
	out.append(pts[pts.size() - 1])
	return out


func _draw() -> void:
	var font := get_theme_default_font()
	draw_style_box(UIKit._flat(UIKit.BG_DEEP, 8, 0, 0, UIKit.BORDER, 1), Rect2(Vector2.ZERO, size))
	if title != "":
		draw_string(font, Vector2(10, 17), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, 13, UIKit.ACCENT)
	var r := _plot_rect()
	var n := _count()
	if n < 2:
		draw_string(font, r.position + Vector2(0, r.size.y * 0.5), "Sin datos todavía (se registra cada mes)", HORIZONTAL_ALIGNMENT_LEFT, r.size.x, 12, UIKit.TEXT_DIM)
		return
	var rg := _range()
	var lo := rg.x
	var hi := rg.y
	# Rejilla y eje Y
	for i in range(4):
		var t := i / 3.0
		var y := r.position.y + r.size.y * (1.0 - t)
		draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(1, 1, 1, 0.05 if i > 0 else 0.12))
		draw_string(font, Vector2(4, y + 4), _fmt(lerpf(lo, hi, t)), HORIZONTAL_ALIGNMENT_RIGHT, r.position.x - 8, 10, UIKit.TEXT_FAINT)
	if lo < 0.0 and hi > 0.0:
		var y0 := r.position.y + r.size.y * (1.0 - (0.0 - lo) / (hi - lo))
		draw_dashed_line(Vector2(r.position.x, y0), Vector2(r.end.x, y0), Color(1, 1, 1, 0.3), 1.0, 4.0)
	# Eje X: 3 etiquetas (inicio, medio, fin)
	if x_labels.size() == n:
		for i in [0, n / 2, n - 1]:
			var x := r.position.x + r.size.x * float(i) / float(n - 1)
			var txt := str(x_labels[i])
			var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			draw_string(font, Vector2(clampf(x - w * 0.5, r.position.x, r.end.x - w), r.end.y + 13), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIKit.TEXT_FAINT)
	# Series
	var clip_x := r.position.x + r.size.x * _progress
	var legend_x := size.x - 8.0
	for si in range(series.size() - 1, -1, -1):
		var s: Dictionary = series[si]
		var vals: Array = s["values"]
		var col: Color = s["color"]
		var pts := PackedVector2Array()
		for i in range(vals.size()):
			var x := r.position.x + r.size.x * float(i) / float(maxi(1, n - 1))
			var y := r.position.y + r.size.y * (1.0 - (float(vals[i]) - lo) / (hi - lo))
			pts.append(Vector2(x, y))
		var cpts := curve(pts, smooth)
		var vis := PackedVector2Array()
		for p in cpts:
			if p.x <= clip_x:
				vis.append(p)
		if vis.size() >= 2:
			if fill and series.size() <= 3:
				var poly := vis.duplicate()
				poly.append(Vector2(vis[vis.size() - 1].x, r.end.y))
				poly.append(Vector2(vis[0].x, r.end.y))
				var cols := PackedColorArray()
				for p in poly:
					var a := 0.0 if p.y >= r.end.y - 0.5 else lerpf(0.28, 0.02, (p.y - r.position.y) / maxf(1.0, r.size.y))
					cols.append(Color(col, a / float(series.size())))
				if Geometry2D.triangulate_polygon(poly).size() > 0:
					draw_polygon(poly, cols)
			draw_polyline(vis, col, 2.0, true)
			if _progress >= 1.0:
				draw_circle(vis[vis.size() - 1], 3.0, col)
		# Leyenda (derecha, arriba)
		if series.size() > 1 or title == "":
			var lab := str(s["label"])
			var lw := font.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			var title_end := 14.0 + font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			if legend_x - lw - 12 > title_end:
				legend_x -= lw
				draw_string(font, Vector2(legend_x, 16), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIKit.TEXT_DIM)
				legend_x -= 12
				draw_circle(Vector2(legend_x + 4, 12.5), 3.5, col)
				legend_x -= 10
	# Hover: línea vertical, puntos y globo con valor y fecha
	if _hover >= 0 and _progress >= 1.0:
		var hx := r.position.x + r.size.x * float(_hover) / float(n - 1)
		draw_line(Vector2(hx, r.position.y), Vector2(hx, r.end.y), Color(1, 1, 1, 0.25), 1.0)
		var lines: Array = []
		if x_labels.size() == n:
			lines.append([str(x_labels[_hover]), UIKit.TEXT_DIM])
		for s in series:
			var vals: Array = s["values"]
			if _hover < vals.size():
				var v := float(vals[_hover])
				var y := r.position.y + r.size.y * (1.0 - (v - lo) / (hi - lo))
				draw_circle(Vector2(hx, y), 4.5, UIKit.BG_DEEP)
				draw_circle(Vector2(hx, y), 3.2, s["color"])
				lines.append(["%s: %s" % [s["label"], _fmt_full(v)], s["color"]])
		var bw := 0.0
		for l in lines:
			bw = maxf(bw, font.get_string_size(l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x)
		var box := Rect2(Vector2(hx + 10, r.position.y + 2), Vector2(bw + 14, 8 + 15 * lines.size()))
		if box.end.x > size.x - 4:
			box.position.x = hx - box.size.x - 10
		draw_style_box(UIKit._flat(Color(0.05, 0.055, 0.07, 0.95), 6, 0, 0, Color(1, 1, 1, 0.15), 1), box)
		for i in range(lines.size()):
			draw_string(font, box.position + Vector2(7, 16 + 15 * i), lines[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, (lines[i][1] as Color).lightened(0.15))
