class_name PyramidChart
extends Control
## Pirámide de población por edad (grupos de 10 años) y sexo: hombres a la izquierda, mujeres a la
## derecha. set_citizens(dict de Citizen) o set_buckets(hombres[], mujeres[]).

const GROUPS := ["0-9", "10-19", "20-29", "30-39", "40-49", "50-59", "60-69", "70-79", "80+"]
const MEN := Color(0.4, 0.66, 0.92)
const WOMEN := Color(0.93, 0.5, 0.66)

var men: Array = []
var women: Array = []
var _progress := 1.0
var _hover := -1


func _init() -> void:
	custom_minimum_size = Vector2(240, 210)
	mouse_filter = Control.MOUSE_FILTER_PASS


func set_citizens(citizens: Dictionary, today: int) -> void:
	var m := []
	var f := []
	m.resize(GROUPS.size())
	f.resize(GROUPS.size())
	m.fill(0)
	f.fill(0)
	for c in citizens.values():
		var g := mini(GROUPS.size() - 1, int(c.age_years(today) / 10))
		if c.gender == "F":
			f[g] += 1
		else:
			m[g] += 1
	set_buckets(m, f)


func set_buckets(m: Array, f: Array) -> void:
	men = m
	women = f
	_progress = 0.0
	if is_inside_tree():
		create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).tween_method(func(v: float): _progress = v; queue_redraw(), 0.0, 1.0, 0.6)
	else:
		_progress = 1.0
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var rh := (size.y - 48.0) / GROUPS.size()
		var i := GROUPS.size() - 1 - int((event.position.y - 26.0) / rh)
		i = i if i >= 0 and i < GROUPS.size() and event.position.y > 26.0 else -1
		if i != _hover:
			_hover = i
			queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hover != -1:
		_hover = -1
		queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	draw_style_box(UIKit._flat(UIKit.BG_DEEP, 8, 0, 0, UIKit.BORDER, 1), Rect2(Vector2.ZERO, size))
	draw_string(font, Vector2(10, 17), "Pirámide de población", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIKit.ACCENT)
	if men.is_empty():
		return
	var mx := 1
	var tm := 0
	var tf := 0
	for i in range(GROUPS.size()):
		mx = maxi(mx, maxi(int(men[i]), int(women[i])))
		tm += int(men[i])
		tf += int(women[i])
	var cx := size.x * 0.5
	var lab_w := 40.0
	var half := cx - lab_w * 0.5 - 12.0
	var rh := (size.y - 48.0) / GROUPS.size()
	for i in range(GROUPS.size()):
		var y := 26.0 + (GROUPS.size() - 1 - i) * rh
		if i == _hover:
			draw_rect(Rect2(Vector2(4, y), Vector2(size.x - 8, rh)), Color(1, 1, 1, 0.05))
		var wm := half * float(men[i]) / mx * _progress
		var wf := half * float(women[i]) / mx * _progress
		draw_style_box(UIKit._flat(MEN, 3, 0, 0), Rect2(Vector2(cx - lab_w * 0.5 - wm, y + 2), Vector2(maxf(wm, 0.0), rh - 4)))
		draw_style_box(UIKit._flat(WOMEN, 3, 0, 0), Rect2(Vector2(cx + lab_w * 0.5, y + 2), Vector2(maxf(wf, 0.0), rh - 4)))
		var gw := font.get_string_size(GROUPS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_string(font, Vector2(cx - gw * 0.5, y + rh * 0.5 + 4), GROUPS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIKit.TEXT_DIM)
		if i == _hover:
			draw_string(font, Vector2(cx - lab_w * 0.5 - wm - 22, y + rh * 0.5 + 4), str(men[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, MEN.lightened(0.3))
			draw_string(font, Vector2(cx + lab_w * 0.5 + wf + 4, y + rh * 0.5 + 4), str(women[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, WOMEN.lightened(0.3))
	draw_circle(Vector2(14, size.y - 10), 4, MEN)
	draw_string(font, Vector2(22, size.y - 6), "Hombres %d" % tm, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIKit.TEXT_DIM)
	var t2 := "Mujeres %d" % tf
	var w2 := font.get_string_size(t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_circle(Vector2(size.x - w2 - 20, size.y - 10), 4, WOMEN)
	draw_string(font, Vector2(size.x - w2 - 12, size.y - 6), t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIKit.TEXT_DIM)
