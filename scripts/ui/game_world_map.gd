class_name GameWorldMap
extends WorldMap
## Fase 10: mapa mundial jugable dentro de la partida (reutiliza el dibujo de WorldMap).
## Marca los países con presencia (dorado), con licencia (contorno), dónde está el personaje (punto),
## el viaje en curso (línea) y los aviones de carga en ruta entre países.

signal selected_changed(iso: String)


func _ready() -> void:
	_load()
	map_area = self
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(420, 260)
	draw.connect(_draw_map)
	gui_input.connect(_map_input)
	resized.connect(queue_redraw)


func select(iso: String) -> void:
	selected = iso
	selected_changed.emit(iso)
	queue_redraw()


func _draw_map() -> void:
	if size.x < 10.0:
		return
	super._draw_map()
	var gs := GameState
	if not CountriesSim.ready(gs):
		return
	var font := get_theme_default_font()
	for iso in CountriesSim.licensed_ids(gs):
		var p := to_px(TravelSim.coords(iso))
		var full := CountriesSim.has_presence(gs, iso)
		draw_circle(p, 7.0, Color(0.1, 0.08, 0.02, 0.8))
		draw_circle(p, 5.0, Color(1.0, 0.8, 0.25) if full else Color(0.75, 0.75, 0.8))
	var loc := CountriesSim.location(gs)
	if loc != "":
		var lp := to_px(TravelSim.coords(loc))
		draw_arc(lp, 11.0, 0.0, TAU, 24, Color(0.4, 1.0, 0.6), 2.5)
		draw_string_outline(font, lp + Vector2(12, -10), "Tú", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color(0, 0, 0, 0.9))
		draw_string(font, lp + Vector2(12, -10), "Tú", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 1.0, 0.7))
	if TravelSim.traveling(gs):
		var t: Dictionary = gs.countries["travel"]
		var a := to_px(TravelSim.coords(str(t["from"])))
		var b := to_px(TravelSim.coords(str(t["to"])))
		draw_dashed_line(a, b, Color(0.4, 1.0, 0.6, 0.9), 2.0, 6.0)
		draw_circle(a.lerp(b, TravelSim.progress(gs)), 5.0, Color(0.4, 1.0, 0.6))
	for fl in AirSim.flights_in_air(gs):
		var a2 := to_px(fl["a"])
		var b2 := to_px(fl["b"])
		draw_line(a2, b2, Color(0.55, 0.8, 1.0, 0.7), 1.5)
		var p2: Vector2 = a2.lerp(b2, float(fl["t"]))
		var dir := (b2 - a2).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([p2 + dir * 9.0, p2 - dir * 6.0 + nrm * 6.0, p2 - dir * 3.0, p2 - dir * 6.0 - nrm * 6.0]), Color(0.75, 0.9, 1.0))
