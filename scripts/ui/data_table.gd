class_name DataTable
extends Control
## Tabla dibujada con _draw (rápida con miles de filas: no crea un nodo por celda).
## Encabezado fijo, filas alternadas, orden por columna (clic en el encabezado), barras de progreso
## en línea, colores por valor, fila bajo el mouse y clic en fila (señal row_clicked).
##
## columns: [{title, key, w (proporción), align ("left"/"right"/"center"), fmt ("text"/"int"/"money"/
##            "money2"/"pct"/"bar"/"trend"), color_key (opcional: clave con Color), max (para "bar"),
##            invert (para "trend": subir es malo)}]
## rows: [Dictionary] — cada fila puede traer "_color" (color del texto) o "_icon".

signal row_clicked(row: Dictionary)

const HEAD_H := 26.0

var columns: Array = []
var rows: Array = []
var row_h := 24.0
var sort_col := -1
var sort_desc := true
var max_visible_rows := 14
var _scroll := 0.0
var _hover := -1
var _view: Array = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	focus_mode = Control.FOCUS_NONE


func set_data(p_columns: Array, p_rows: Array, p_max_rows := 14) -> void:
	columns = p_columns
	rows = p_rows
	max_visible_rows = p_max_rows
	custom_minimum_size.y = HEAD_H + row_h * mini(maxi(1, rows.size()), max_visible_rows) + 2.0
	_apply_sort()
	_scroll = clampf(_scroll, 0.0, _max_scroll())
	queue_redraw()


func _apply_sort() -> void:
	_view = rows.duplicate()
	if sort_col < 0 or sort_col >= columns.size():
		return
	var key := str(columns[sort_col]["key"])
	var desc := sort_desc
	_view.sort_custom(func(a, b):
		var va = a.get(key, "")
		var vb = b.get(key, "")
		if (va is float or va is int) and (vb is float or vb is int):
			return float(va) > float(vb) if desc else float(va) < float(vb)
		return str(va).naturalnocasecmp_to(str(vb)) > 0 if desc else str(va).naturalnocasecmp_to(str(vb)) < 0)


func _max_scroll() -> float:
	return maxf(0.0, _view.size() * row_h - (size.y - HEAD_H))


func _col_x() -> Array:
	var tot := 0.0
	for c in columns:
		tot += float(c.get("w", 1.0))
	var xs := [0.0]
	var x := 0.0
	for c in columns:
		x += (size.x - 10.0) * float(c.get("w", 1.0)) / tot
		xs.append(x)
	return xs


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN or event.button_index == MOUSE_BUTTON_WHEEL_UP:
			var ms := _max_scroll()
			if ms <= 0.0:
				return  # deja pasar la rueda al contenedor
			_scroll = clampf(_scroll + (row_h * 3.0 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -row_h * 3.0), 0.0, ms)
			queue_redraw()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.position.y < HEAD_H:
				var xs := _col_x()
				for i in range(columns.size()):
					if event.position.x >= xs[i] and event.position.x < xs[i + 1]:
						if sort_col == i:
							sort_desc = not sort_desc
						else:
							sort_col = i
							sort_desc = true
						_apply_sort()
						queue_redraw()
						break
			else:
				var i := int((event.position.y - HEAD_H + _scroll) / row_h)
				if i >= 0 and i < _view.size():
					row_clicked.emit(_view[i])
			accept_event()
	elif event is InputEventMouseMotion:
		var h := int((event.position.y - HEAD_H + _scroll) / row_h) if event.position.y >= HEAD_H else -1
		if h >= _view.size():
			h = -1
		if h != _hover:
			_hover = h
			queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hover != -1:
		_hover = -1
		queue_redraw()
	elif what == NOTIFICATION_RESIZED:
		_scroll = clampf(_scroll, 0.0, _max_scroll())


func _cell_text(col: Dictionary, v) -> String:
	match str(col.get("fmt", "text")):
		"int":
			return Fmt.thousands(float(v))
		"money":
			return Fmt.money(float(v))
		"money2":
			return Fmt.money2(float(v))
		"pct":
			return Fmt.pct(float(v) * 100.0)
		"trend":
			var d := float(v)
			if absf(d) < 0.005:
				return "＝"
			return "%s %s" % ["▲" if d > 0.0 else "▼", Fmt.pct_1(absf(d) * 100.0)]
	return str(v)


func _draw() -> void:
	var font := get_theme_default_font()
	draw_style_box(UIKit._flat(UIKit.BG_DEEP, 8, 0, 0, UIKit.BORDER, 1), Rect2(Vector2.ZERO, size))
	var xs := _col_x()
	var fs := 12
	# Filas
	var first := int(_scroll / row_h)
	var last := mini(_view.size(), first + int(ceil((size.y - HEAD_H) / row_h)) + 1)
	for i in range(first, last):
		var r: Dictionary = _view[i]
		var y := HEAD_H + i * row_h - _scroll
		if i % 2 == 1:
			draw_rect(Rect2(Vector2(1, y), Vector2(size.x - 2, row_h)), Color(1, 1, 1, 0.03))
		if i == _hover:
			draw_rect(Rect2(Vector2(1, y), Vector2(size.x - 2, row_h)), Color(UIKit.ACCENT, 0.1))
		for ci in range(columns.size()):
			var col: Dictionary = columns[ci]
			var v = r.get(str(col["key"]), "")
			var x0: float = xs[ci] + 8.0
			var w: float = xs[ci + 1] - xs[ci] - 8.0
			var color: Color = r.get("_color", UIKit.TEXT) if ci == 0 else UIKit.TEXT
			if col.has("color_key") and r.has(str(col["color_key"])):
				color = r[str(col["color_key"])]
			var fmt := str(col.get("fmt", "text"))
			if fmt == "bar":
				var ratio := clampf(float(v) / float(col.get("max", 1.0)), 0.0, 1.0)
				var bc: Color = color if col.has("color_key") else UIKit.level_color(ratio if not col.get("invert", false) else 1.0 - ratio)
				var bw := w - 38.0
				draw_style_box(UIKit._flat(Color(1, 1, 1, 0.07), 3, 0, 0), Rect2(Vector2(x0, y + row_h * 0.5 - 3), Vector2(bw, 6)))
				draw_style_box(UIKit._flat(bc, 3, 0, 0), Rect2(Vector2(x0, y + row_h * 0.5 - 3), Vector2(maxf(2.0, bw * ratio), 6)))
				draw_string(font, Vector2(x0 + bw + 4, y + row_h * 0.5 + 4), Fmt.pct(ratio * 100.0), HORIZONTAL_ALIGNMENT_LEFT, 36, 11, bc.lightened(0.2))
				continue
			if fmt == "trend":
				var d := float(v)
				color = UIKit.NEUTRAL if absf(d) < 0.005 else UIKit.sign_color(-d if col.get("invert", false) else d)
			elif fmt == "money" and not col.has("color_key") and float(v) < 0.0:
				color = UIKit.BAD
			var txt := _cell_text(col, v)
			var al := str(col.get("align", "right" if fmt in ["int", "money", "money2", "pct", "trend"] else "left"))
			var halign := HORIZONTAL_ALIGNMENT_RIGHT if al == "right" else (HORIZONTAL_ALIGNMENT_CENTER if al == "center" else HORIZONTAL_ALIGNMENT_LEFT)
			if al == "right":
				w -= 4.0
			draw_string(font, Vector2(x0, y + row_h * 0.5 + 4), txt, halign, w, fs, color)
	if _view.is_empty():
		draw_string(font, Vector2(10, HEAD_H + 17), "Sin datos", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UIKit.TEXT_DIM)
	# Encabezado fijo
	draw_style_box(UIKit._flat(Color(0.13, 0.14, 0.17, 1.0), 8, 0, 0), Rect2(Vector2(1, 1), Vector2(size.x - 2, HEAD_H - 1)))
	draw_line(Vector2(1, HEAD_H), Vector2(size.x - 1, HEAD_H), Color(UIKit.ACCENT, 0.35))
	for ci in range(columns.size()):
		var col: Dictionary = columns[ci]
		var fmt := str(col.get("fmt", "text"))
		var al := str(col.get("align", "right" if fmt in ["int", "money", "money2", "pct", "trend"] else "left"))
		var x0: float = xs[ci] + 8.0
		var w: float = xs[ci + 1] - xs[ci] - 12.0
		var t := str(col["title"])
		if ci == sort_col:
			t = ("▼ " if sort_desc else "▲ ") + t if al == "right" else t + (" ▼" if sort_desc else " ▲")
		draw_string(font, Vector2(x0, HEAD_H * 0.5 + 5), t, HORIZONTAL_ALIGNMENT_RIGHT if al == "right" else HORIZONTAL_ALIGNMENT_LEFT, w, 11, UIKit.ACCENT if ci == sort_col else UIKit.TEXT_DIM)
	# Barra de desplazamiento
	var ms := _max_scroll()
	if ms > 0.0:
		var track := size.y - HEAD_H - 6.0
		var hh := maxf(24.0, track * (size.y - HEAD_H) / (_view.size() * row_h))
		var yy := HEAD_H + 3.0 + (track - hh) * _scroll / ms
		draw_style_box(UIKit._flat(Color(1, 1, 1, 0.2), 3, 0, 0), Rect2(Vector2(size.x - 7, yy), Vector2(4, hh)))
