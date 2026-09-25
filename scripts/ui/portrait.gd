class_name Portrait
extends Control
## Retrato simple generado: silueta de busto con piel, pelo y ropa según edad, sexo, época y una
## semilla visual (cada persona se ve distinta pero siempre igual). Marco dorado para el jugador.

const SKINS := [Color(0.96, 0.82, 0.7), Color(0.89, 0.72, 0.58), Color(0.78, 0.6, 0.45), Color(0.62, 0.45, 0.32), Color(0.45, 0.32, 0.23)]
const HAIRS := [Color(0.12, 0.09, 0.07), Color(0.3, 0.2, 0.12), Color(0.5, 0.33, 0.18), Color(0.75, 0.55, 0.3), Color(0.55, 0.22, 0.12)]
## Paleta de ropa por época (1: colonial … 5+: moderna).
const CLOTHES := {
	1: [Color(0.45, 0.32, 0.22), Color(0.35, 0.38, 0.3), Color(0.55, 0.5, 0.42)],
	2: [Color(0.28, 0.3, 0.42), Color(0.45, 0.25, 0.22), Color(0.35, 0.33, 0.3)],
	3: [Color(0.2, 0.22, 0.28), Color(0.38, 0.3, 0.24), Color(0.25, 0.32, 0.4)],
	4: [Color(0.25, 0.35, 0.55), Color(0.55, 0.3, 0.3), Color(0.3, 0.45, 0.35)],
	5: [Color(0.2, 0.5, 0.7), Color(0.75, 0.35, 0.35), Color(0.35, 0.6, 0.45)],
}

var age := 30
var female := false
var seed_v := 0
var era := 1
var highlight := false
var dead := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS


func set_citizen(c: Citizen, is_player := false) -> void:
	age = c.age_years(GameState.today())
	female = c.gender == "F"
	seed_v = c.visual_seed if c.visual_seed != 0 else c.id * 7919
	era = GameState.era()
	highlight = is_player
	queue_redraw()


func set_person(p_age: int, p_female: bool, p_seed: int, p_era := 1) -> void:
	age = p_age
	female = p_female
	seed_v = p_seed
	era = p_era
	queue_redraw()


func _pick(arr: Array, salt: int) -> Color:
	return arr[absi(hash(seed_v * 31 + salt)) % arr.size()]


func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := Vector2((size.x - s) * 0.5, (size.y - s) * 0.5)
	var c := o + Vector2(s * 0.5, s * 0.5)
	var bgc := Color(0.16, 0.18, 0.22) if not highlight else Color(0.3, 0.24, 0.12)
	draw_circle(c, s * 0.5, bgc)
	var skin := _pick(SKINS, 1)
	var hair := _pick(HAIRS, 2)
	if age >= 60:
		hair = Color(0.82, 0.82, 0.8) if age >= 70 else hair.lerp(Color(0.8, 0.8, 0.78), 0.5)
	var pal: Array = CLOTHES.get(clampi(era, 1, 5), CLOTHES[1])
	var cloth := _pick(pal, 3)
	var child := age < 13
	var head_r := s * (0.2 if child else 0.17)
	var head_c := c + Vector2(0, -s * (0.02 if child else 0.07))
	# Hombros / ropa (clipped al círculo aproximando con polígono)
	var sh_w := s * (0.3 if child else 0.38)
	var sh_top := head_c.y + head_r * 1.05
	var body := PackedVector2Array()
	var steps := 18
	for i in range(steps + 1):
		var a := PI + PI * float(i) / steps
		body.append(Vector2(c.x + cos(a) * sh_w, sh_top + s * 0.1 + sin(a) * s * 0.14))
	# Base del busto siguiendo el borde inferior del círculo
	for i in range(steps + 1):
		var a := lerpf(0.0, PI, float(i) / steps)
		var p := c + Vector2(cos(a), sin(a)) * s * 0.5
		if p.y >= sh_top:
			body.append(p)
	if body.size() >= 3 and Geometry2D.triangulate_polygon(body).size() > 0:
		draw_colored_polygon(body, cloth)
	# Cuello
	draw_rect(Rect2(Vector2(head_c.x - head_r * 0.35, head_c.y + head_r * 0.6), Vector2(head_r * 0.7, head_r * 0.6)), skin.darkened(0.1))
	# Cabello largo detrás (mujeres)
	if female and not child:
		draw_rect(Rect2(head_c + Vector2(-head_r * 1.08, -head_r * 0.2), Vector2(head_r * 2.16, head_r * 1.55)), hair)
	elif female:
		draw_circle(head_c + Vector2(0, head_r * 0.2), head_r * 1.08, hair)
	# Cabeza
	draw_circle(head_c, head_r, skin)
	# Pelo superior
	var cap := PackedVector2Array()
	for i in range(steps + 1):
		var a := PI + PI * float(i) / steps
		cap.append(head_c + Vector2(cos(a) * head_r * 1.06, sin(a) * head_r * 1.08))
	if age < 75 or female or absi(seed_v) % 3 != 0:
		cap.append(head_c + Vector2(head_r * 1.06, head_r * 0.1))
		cap.append(head_c + Vector2(-head_r * 1.06, head_r * 0.1))
		draw_colored_polygon(cap, hair)
		draw_circle(head_c + Vector2(0, head_r * 0.12), head_r * 0.92, skin)
	else:
		draw_arc(head_c, head_r * 1.02, PI * 0.85, PI * 1.15, 8, hair, 3.0)
		draw_arc(head_c, head_r * 1.02, -PI * 0.15, PI * 0.15, 8, hair, 3.0)
	# Ojos
	var eye := Color(0.12, 0.1, 0.1)
	draw_circle(head_c + Vector2(-head_r * 0.35, head_r * 0.1), maxf(1.0, head_r * 0.09), eye)
	draw_circle(head_c + Vector2(head_r * 0.35, head_r * 0.1), maxf(1.0, head_r * 0.09), eye)
	# Barba/bigote en algunos hombres adultos
	if not female and age >= 22 and absi(seed_v) % 4 == 1:
		draw_arc(head_c + Vector2(0, head_r * 0.25), head_r * 0.62, 0.3, PI - 0.3, 10, hair, maxf(2.0, head_r * 0.22))
	# Sombrero en épocas antiguas (algunos)
	if era <= 2 and not child and absi(seed_v) % 3 == 2:
		var hat := cloth.darkened(0.45)
		draw_rect(Rect2(head_c + Vector2(-head_r * 1.35, -head_r * 0.85), Vector2(head_r * 2.7, head_r * 0.22)), hat)
		draw_rect(Rect2(head_c + Vector2(-head_r * 0.8, -head_r * 1.45), Vector2(head_r * 1.6, head_r * 0.65)), hat)
	# Marco
	var ring := UIKit.ACCENT if highlight else Color(1, 1, 1, 0.14)
	draw_arc(c, s * 0.5 - 1.0, 0.0, TAU, 48, ring, 2.0 if highlight else 1.0, true)
	if dead:
		draw_circle(c, s * 0.5, Color(0, 0, 0, 0.45))
