class_name MenuBackground
extends Control
## Fondo ilustrado del menú principal, dibujado con código: cielo al atardecer en degradado, sol,
## nubes que se desplazan despacio, colinas en capas, un pueblo colonial en silueta con iglesia y
## ventanas encendidas, árboles y viñeta. Sin imágenes externas.

var _t := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t += delta
	if is_visible_in_tree():
		queue_redraw()


func _grad_rect(r: Rect2, top: Color, bottom: Color) -> void:
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([top, top, bottom, bottom]))


func _hill(base_y: float, amp: float, freq: float, phase: float, color: Color) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps := 64
	for i in range(steps + 1):
		var x := size.x * float(i) / steps
		var y := base_y - amp * (0.6 * sin(x * freq + phase) + 0.4 * sin(x * freq * 2.3 + phase * 1.7))
		pts.append(Vector2(x, y))
	pts.append(Vector2(size.x, size.y))
	pts.append(Vector2(0, size.y))
	draw_colored_polygon(pts, color)
	return pts


func _hill_y(pts: PackedVector2Array, x: float) -> float:
	var steps := pts.size() - 3
	var f := clampf(x / size.x * steps, 0.0, float(steps) - 0.001)
	var i := int(f)
	return lerpf(pts[i].y, pts[i + 1].y, f - i)


func _draw() -> void:
	var w := size.x
	var h := size.y
	var horizon := h * 0.62
	# Cielo
	_grad_rect(Rect2(0, 0, w, horizon * 0.55), Color(0.09, 0.12, 0.25), Color(0.32, 0.3, 0.45))
	_grad_rect(Rect2(0, horizon * 0.55, w, horizon * 0.45 + 2), Color(0.32, 0.3, 0.45), Color(0.96, 0.62, 0.36))
	_grad_rect(Rect2(0, horizon, w, h - horizon), Color(0.96, 0.62, 0.36), Color(0.5, 0.3, 0.25))
	# Sol con halo
	var sun := Vector2(w * 0.68, horizon - h * 0.05)
	for i in range(6, 0, -1):
		draw_circle(sun, h * 0.035 * i, Color(1.0, 0.8, 0.45, 0.05))
	draw_circle(sun, h * 0.05, Color(1.0, 0.88, 0.6))
	# Estrellas tenues arriba
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in range(60):
		var p := Vector2(rng.randf() * w, rng.randf() * horizon * 0.4)
		var a := 0.25 + 0.25 * sin(_t * 1.5 + i)
		draw_circle(p, 1.0 + rng.randf(), Color(1, 1, 1, a * (1.0 - p.y / (horizon * 0.4))))
	# Nubes
	for i in range(5):
		var cx := fposmod(w * (0.15 + i * 0.22) + _t * (6.0 + i * 2.0), w + 300.0) - 150.0
		var cy := horizon * (0.25 + 0.09 * (i % 3))
		var col := Color(1.0, 0.78, 0.68, 0.22)
		for k in range(4):
			draw_circle(Vector2(cx + k * 34.0 - 50.0, cy + (8.0 if k % 2 == 0 else 0.0)), 26.0 + (k % 2) * 10.0, col)
	# Colinas lejanas → cercanas
	_hill(horizon + 10.0, 40.0, 0.004, 1.0, Color(0.36, 0.3, 0.42))
	var mid := _hill(horizon + 60.0, 34.0, 0.006, 2.3, Color(0.2, 0.22, 0.3))
	# Pueblo en silueta sobre la colina media
	var town_x := w * 0.28
	var sil := Color(0.12, 0.12, 0.17)
	var win := Color(1.0, 0.8, 0.42)
	for i in range(11):
		var x := town_x + i * 34.0 + (i % 3) * 6.0
		var gy := _hill_y(mid, x + 14.0) + 6.0
		var bw := 26.0 + (i % 2) * 8.0
		var bh := 22.0 + (i * 7 % 3) * 7.0
		draw_rect(Rect2(x, gy - bh, bw, bh), sil)
		draw_colored_polygon(PackedVector2Array([Vector2(x - 4, gy - bh), Vector2(x + bw * 0.5, gy - bh - 14.0), Vector2(x + bw + 4, gy - bh)]), sil)
		if (i * 5) % 3 != 0:
			var lit := 0.75 + 0.25 * sin(_t * 0.8 + i * 1.3)
			draw_rect(Rect2(x + bw * 0.3, gy - bh * 0.6, 5, 6), Color(win, lit))
		if i == 5:
			# Iglesia con torre y cruz
			var tx := x + bw + 6.0
			draw_rect(Rect2(tx, gy - 78.0, 18.0, 78.0), sil)
			draw_colored_polygon(PackedVector2Array([Vector2(tx - 3, gy - 78), Vector2(tx + 9, gy - 100), Vector2(tx + 21, gy - 78)]), sil)
			draw_line(Vector2(tx + 9, gy - 100), Vector2(tx + 9, gy - 112), sil, 2.0)
			draw_line(Vector2(tx + 4, gy - 107), Vector2(tx + 14, gy - 107), sil, 2.0)
			draw_rect(Rect2(tx + 6, gy - 62, 6, 9), Color(win, 0.9))
	# Colina cercana con árboles
	var near := _hill(h * 0.86, 30.0, 0.005, 4.1, Color(0.08, 0.1, 0.12))
	rng.seed = 11
	for i in range(26):
		var x := rng.randf() * w
		if x > town_x - 40.0 and x < town_x + 420.0 and rng.randf() < 0.7:
			continue
		var gy := _hill_y(near, x) + 4.0
		var th := 26.0 + rng.randf() * 30.0
		draw_colored_polygon(PackedVector2Array([Vector2(x - th * 0.32, gy), Vector2(x, gy - th), Vector2(x + th * 0.32, gy)]), Color(0.06, 0.08, 0.09))
	# Viñeta
	_grad_rect(Rect2(0, 0, w, h * 0.25), Color(0, 0, 0, 0.35), Color(0, 0, 0, 0))
	_grad_rect(Rect2(0, h * 0.75, w, h * 0.25), Color(0, 0, 0, 0), Color(0, 0, 0, 0.45))
