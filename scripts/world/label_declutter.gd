class_name LabelDeclutter
extends Node
## Mapa v2 — etiquetas 3D sin solaparse. Cada 0,1 s proyecta en pantalla las etiquetas registradas
## (grupo GROUP), estima su rectángulo y las coloca por prioridad (y, a igual prioridad, la más
## cercana primero): si choca con una ya colocada prueba a desplazarla arriba o abajo y, si tampoco
## cabe, la oculta. Los cambios se animan (desvanecido con `transparency` y desplazamiento suave del
## `offset`), así no parpadean. Metadatos que usa:
## - decl_prio: prioridad (mayor = más importante). La pone register() o MeshLib.style_label().
## - decl_fade: 0..1 opcional, desvanecido extra que decide el dueño (p. ej. por altura o distancia).

const GROUP := "declutter_labels"
const PAD := 3.0
const RELAYOUT := 0.1

var _timer := 0.0
var last_hidden := 0      # etiquetas ocultas por choque en el último cálculo (pruebas y capturas)
var last_moved := 0


static func register(lab: Label3D, prio: float) -> void:
	lab.set_meta("decl_prio", prio)
	lab.set_meta("decl_base_off", lab.offset)
	if not lab.is_in_group(GROUP):
		lab.add_to_group(GROUP)


## Cambia el offset "de diseño" de una etiqueta ya registrada (el desplazamiento se suma encima).
static func set_base_offset(lab: Label3D, off: Vector2) -> void:
	lab.set_meta("decl_base_off", off)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = RELAYOUT
		layout(cam)
	var k := 1.0 - exp(-12.0 * delta)
	for n in get_tree().get_nodes_in_group(GROUP):
		var lab := n as Label3D
		if lab == null:
			continue
		var target := float(lab.get_meta("decl_target", 1.0)) * float(lab.get_meta("decl_fade", 1.0))
		var a := move_toward(float(lab.get_meta("decl_a", 1.0)), target, delta * 4.0)
		lab.set_meta("decl_a", a)
		lab.transparency = 1.0 - a
		var base: Vector2 = lab.get_meta("decl_base_off", lab.offset)
		var want: Vector2 = base + (lab.get_meta("decl_shift", Vector2.ZERO) as Vector2)
		lab.offset = lab.offset.lerp(want, k)


## Escala píxeles de pantalla por unidad de la etiqueta (texto de font_size × pixel_size).
static func _px_scale(lab: Label3D, cam: Camera3D, dist: float, vp_h: float) -> float:
	var s := lab.pixel_size * vp_h / (2.0 * tan(deg_to_rad(cam.fov) * 0.5))
	if not lab.fixed_size:
		s /= maxf(dist, 0.01)
	return s


## Calcula qué etiquetas se ven, dónde, y cuáles se ocultan. Devuelve los rectángulos colocados.
func layout(cam: Camera3D) -> Array:
	var vp := get_viewport().get_visible_rect().size
	var cp := cam.global_position
	var items := []
	for n in get_tree().get_nodes_in_group(GROUP):
		var lab := n as Label3D
		if lab == null or not lab.is_visible_in_tree() or lab.text == "":
			continue
		var pos := lab.global_position
		var dist := cp.distance_to(pos)
		if lab.visibility_range_end > 0.0 and dist > lab.visibility_range_end + lab.visibility_range_end_margin:
			continue
		if float(lab.get_meta("decl_fade", 1.0)) < 0.05 or cam.is_position_behind(pos):
			continue
		var sp := cam.unproject_position(pos)
		if sp.x < -200.0 or sp.y < -100.0 or sp.x > vp.x + 200.0 or sp.y > vp.y + 100.0:
			lab.set_meta("decl_target", 1.0)
			continue
		var k := _px_scale(lab, cam, dist, vp.y)
		var font: Font = lab.font if lab.font != null else ThemeDB.fallback_font
		var sz := (font.get_multiline_string_size(lab.text, HORIZONTAL_ALIGNMENT_CENTER, -1, lab.font_size) + Vector2.ONE * lab.outline_size) * k
		var base: Vector2 = lab.get_meta("decl_base_off", lab.offset)
		var c := sp + Vector2(base.x, -base.y) * k
		items.append({"lab": lab, "rect": Rect2(c - sz * 0.5, sz).grow(PAD), "prio": float(lab.get_meta("decl_prio", 1.0)), "dist": dist, "k": k})
	items.sort_custom(func(a, b): return float(a["prio"]) > float(b["prio"]) or (float(a["prio"]) == float(b["prio"]) and float(a["dist"]) < float(b["dist"])))
	var placed: Array = []
	last_hidden = 0
	last_moved = 0
	for it in items:
		var r: Rect2 = it["rect"]
		var lab: Label3D = it["lab"]
		var shift := Vector2.ZERO
		var ok := _free(r, placed)
		if not ok:
			for dy in [-(r.size.y + 1.0), r.size.y + 1.0]:
				var r2 := Rect2(r.position + Vector2(0, dy), r.size)
				if _free(r2, placed):
					r = r2
					shift = Vector2(0, -dy / float(it["k"]))
					ok = true
					break
		if ok:
			placed.append(r)
			lab.set_meta("decl_target", 1.0)
			lab.set_meta("decl_shift", shift)
			if shift != Vector2.ZERO:
				last_moved += 1
		else:
			lab.set_meta("decl_target", 0.0)
			last_hidden += 1
	return placed


static func _free(r: Rect2, placed: Array) -> bool:
	for q in placed:
		if (q as Rect2).intersects(r):
			return false
	return true
