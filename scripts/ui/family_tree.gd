class_name FamilyTree
extends Control
## Árbol familiar simple: padres arriba, la persona y su cónyuge al centro, hijos abajo.
## Cada miembro es un retrato con nombre y edad; clic → selecciona a esa persona.
## Los ya fallecidos (no están en GameState.citizens) se muestran en gris.

signal person_clicked(id: int)

const NODE_W := 70.0
const NODE_H := 62.0
const ROW_GAP := 18.0

var _rows: Array = []    # [[{id, name, age, alive, female, seed}]]
var _pos := {}           # id -> Vector2 (centro del retrato)
var _center_id := -1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS


func set_person(c: Citizen) -> void:
	UIKit.clear(self)
	_center_id = c.id
	_rows = []
	var parents := c.parent_ids.map(func(p): return _info(int(p)))
	var mid := [_info(c.id)]
	if c.spouse_id >= 0:
		mid.append(_info(c.spouse_id))
	var kids := c.children_ids.slice(0, 6).map(func(k): return _info(int(k)))
	if not parents.is_empty():
		_rows.append(parents)
	_rows.append(mid)
	if not kids.is_empty():
		_rows.append(kids)
	custom_minimum_size.y = _rows.size() * (NODE_H + ROW_GAP) - ROW_GAP + 6.0
	_layout_nodes()


func _info(id: int) -> Dictionary:
	if GameState.citizens.has(id):
		var p: Citizen = GameState.citizens[id]
		return {"id": id, "name": p.first_name, "age": p.age_years(GameState.today()), "alive": true, "female": p.gender == "F", "seed": p.visual_seed if p.visual_seed != 0 else id * 7919}
	var nm := GameState.person_name(id)
	return {"id": id, "name": nm.get_slice(" ", 0) if nm != "" else "—", "age": -1, "alive": false, "female": id % 2 == 0, "seed": id * 7919}


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_nodes()


func _layout_nodes() -> void:
	for ch in get_children():
		ch.queue_free()
	_pos.clear()
	var w := maxf(size.x, 300.0)
	for ri in range(_rows.size()):
		var row: Array = _rows[ri]
		var n := row.size()
		var gap := minf(NODE_W + 12.0, (w - 8.0) / maxf(1.0, n))
		var x0 := w * 0.5 - gap * (n - 1) * 0.5
		for i in range(n):
			var m: Dictionary = row[i]
			var cx := x0 + gap * i
			var cy := ri * (NODE_H + ROW_GAP) + 20.0
			_pos[int(m["id"])] = Vector2(cx, cy)
			var b := Button.new()
			b.flat = true
			b.position = Vector2(cx - NODE_W * 0.5, cy - 20.0)
			b.size = Vector2(NODE_W, NODE_H)
			b.tooltip_text = GameState.person_name(int(m["id"])) + ("" if bool(m["alive"]) else " (fallecido/a)")
			b.add_theme_stylebox_override("hover", UIKit._flat(Color(1, 1, 1, 0.06), 6, 0, 0))
			b.add_theme_stylebox_override("pressed", UIKit._flat(Color(UIKit.ACCENT, 0.12), 6, 0, 0))
			b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
			b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
			var mid := int(m["id"])
			b.pressed.connect(func(): person_clicked.emit(mid))
			b.disabled = not bool(m["alive"])
			add_child(b)
			var p := Portrait.new()
			p.set_person(maxi(0, int(m["age"])) if int(m["age"]) >= 0 else 60, bool(m["female"]), int(m["seed"]), GameState.era())
			p.highlight = mid == _center_id
			p.dead = not bool(m["alive"])
			p.custom_minimum_size = Vector2(36, 36)
			p.position = Vector2(NODE_W * 0.5 - 18.0, 2.0)
			p.size = Vector2(36, 36)
			p.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(p)
			var l := UIKit.label("%s%s" % [m["name"], " %d" % int(m["age"]) if int(m["age"]) >= 0 else " †"], 10, UIKit.TEXT if bool(m["alive"]) else UIKit.TEXT_FAINT)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.position = Vector2(0, 40)
			l.size = Vector2(NODE_W, 16)
			l.clip_text = true
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(l)
	queue_redraw()


func _draw() -> void:
	var col := Color(UIKit.ACCENT, 0.35)
	if _rows.is_empty():
		return
	var has_parents: bool = _rows.size() >= 2 and not _rows[0].is_empty() and _rows[0][0]["id"] != _center_id
	var mid_row: int = 1 if has_parents else 0
	var center: Vector2 = _pos.get(_center_id, Vector2.ZERO)
	# Pareja
	for m in _rows[mid_row]:
		if int(m["id"]) != _center_id:
			var p: Vector2 = _pos[int(m["id"])]
			draw_line(center + Vector2(20, 0), p - Vector2(20, 0), Color(0.95, 0.62, 0.85, 0.6), 2.0)
	# Padres → persona
	if has_parents:
		var ys: float = center.y - 20.0 - ROW_GAP * 0.5
		for m in _rows[0]:
			var p: Vector2 = _pos[int(m["id"])]
			draw_line(p + Vector2(0, 36), Vector2(p.x, ys), col, 1.5)
			draw_line(Vector2(p.x, ys), Vector2(center.x, ys), col, 1.5)
		draw_line(Vector2(center.x, ys), center - Vector2(0, 20), col, 1.5)
	# Persona → hijos
	if _rows.size() > mid_row + 1:
		var src := center
		if _rows[mid_row].size() > 1:
			src = (center + _pos[int(_rows[mid_row][1]["id"])]) * 0.5
		var yk := src.y + 36.0 + ROW_GAP * 0.5
		draw_line(src + Vector2(0, 0 if src != center else 36), Vector2(src.x, yk), col, 1.5)
		for m in _rows[mid_row + 1]:
			var p: Vector2 = _pos[int(m["id"])]
			draw_line(Vector2(src.x, yk), Vector2(p.x, yk), col, 1.5)
			draw_line(Vector2(p.x, yk), p - Vector2(0, 20), col, 1.5)
