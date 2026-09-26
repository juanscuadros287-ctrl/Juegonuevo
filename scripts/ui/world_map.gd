class_name WorldMap
extends Control
## Mapa mundial con los países reales (Natural Earth 1:110m, dominio público; data/world/world.json).
## Los países jugables se resaltan por continente; clic para seleccionar y "Elegir" para fundar ahí.
## Proyección equirectangular (lon −180..180, lat −58..84).

signal chosen(iso: String)

const LAT_TOP := 84.0
const LAT_BOTTOM := -58.0
const CONT_COLORS := {"South America": Color(0.55, 0.78, 0.45), "North America": Color(0.86, 0.72, 0.45),
		"Europe": Color(0.55, 0.68, 0.9), "Africa": Color(0.9, 0.62, 0.42), "Asia": Color(0.86, 0.55, 0.6),
		"Oceania": Color(0.5, 0.78, 0.8)}

var countries: Array = []        # [{iso, name, continent, label, playable, polys: [PackedVector2Array (lon,lat)], tris}]
var selected := ""
var hovered := ""
var info: RichTextLabel
var choose_btn: Button
var map_area: Control


func _ready() -> void:
	_load()
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.1, 0.96)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 16
	h.offset_top = 16
	h.offset_right = -16
	h.offset_bottom = -16
	h.add_theme_constant_override("separation", 14)
	add_child(h)
	map_area = Control.new()
	map_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_area.mouse_filter = Control.MOUSE_FILTER_STOP
	map_area.draw.connect(_draw_map)
	map_area.gui_input.connect(_map_input)
	h.add_child(map_area)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 330
	side.add_theme_constant_override("separation", 8)
	h.add_child(side)
	side.add_child(UIKit.label("Mapa mundial", 22, UIKit.ACCENT))
	var note := UIKit.label("Elige el país donde fundarás tu pueblo. Los países de color son jugables; cada uno se genera a escala con su forma, relieve, ríos y clima reales.", 13, UIKit.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(note)
	info = UIKit.rich()
	info.custom_minimum_size = Vector2(330, 360)
	info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(info)
	choose_btn = UIKit.button("Elegir este país", func(): if selected != "": chosen.emit(selected), 330)
	side.add_child(choose_btn)
	side.add_child(UIKit.button("Cerrar", func(): visible = false, 330))
	var attr := UIKit.label("Geografía: Natural Earth (dominio público) · Relieve: ETOPO1 (NOAA, dominio público)", 10, UIKit.TEXT_DIM)
	attr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(attr)
	select(selected if selected != "" else MapSim.DEFAULT_REAL)


func _load() -> void:
	countries = []
	for c in WorldData.world().get("countries", []):
		var polys := []
		var tris := []
		for ring in c.get("rings", []):
			var pts := PackedVector2Array()
			var arr: Array = ring
			for i in range(0, arr.size() - 1, 2):
				pts.append(Vector2(float(arr[i]), float(arr[i + 1])))
			if pts.size() >= 3:
				polys.append(pts)
				tris.append(Geometry2D.triangulate_polygon(pts))
		var iso := str(c.get("iso", ""))
		countries.append({"iso": iso, "name": str(c.get("name", "")), "continent": str(c.get("continent", "")),
				"label": Vector2(float(c["label"][0]), float(c["label"][1])), "playable": WorldData.is_real(iso),
				"polys": polys, "tris": tris})


func to_px(lonlat: Vector2) -> Vector2:
	var s := map_area.size
	return Vector2((lonlat.x + 180.0) / 360.0 * s.x, (LAT_TOP - lonlat.y) / (LAT_TOP - LAT_BOTTOM) * s.y)


func to_lonlat(px: Vector2) -> Vector2:
	var s := map_area.size
	return Vector2(px.x / s.x * 360.0 - 180.0, LAT_TOP - px.y / s.y * (LAT_TOP - LAT_BOTTOM))


func country_at(lonlat: Vector2) -> String:
	for c in countries:
		for p in c["polys"]:
			if Geometry2D.is_point_in_polygon(lonlat, p):
				return str(c["iso"])
	return ""


func select(iso: String) -> void:
	selected = iso
	var playable := WorldData.is_real(iso)
	choose_btn.disabled = not playable
	if iso == "":
		info.text = "Haz clic en un país."
	elif not playable:
		info.text = "[b]%s[/b]\n[color=#aab]Aún no es jugable (valores por defecto). Elige un país de color.[/color]" % _name(iso)
	else:
		var cd := MapSim.country_def(iso)
		var p := WorldData.profile(iso)
		var d := WorldData.country_meta(iso)
		info.text = "[b][color=#f2c65a]%s[/color][/b]\nIdioma: %s\nMoneda: %s (%s) · inflación base %.1f%%\nRecursos: %s\nTerritorio en el juego: %d×%d chunks de 400 m (1 chunk ≈ %.0f km reales)\nFundas tu pueblo cerca de: %s\n%d lugares reales para municipios" % [
			cd.get("label", iso), p.get("language", ""), p.get("currency", {}).get("name", ""), p.get("currency", {}).get("symbol", ""),
			float(p.get("base_inflation", 0.0)) * 100.0, ", ".join(PackedStringArray(p.get("real_resources", []))),
			int(d.get("country_chunks_side", 0)), int(d.get("country_chunks_side", 0)), float(d.get("km_per_chunk", 0.0)),
			str(d.get("start_name", "")), (d.get("places", []) as Array).size()]
	map_area.queue_redraw()


func _name(iso: String) -> String:
	for c in countries:
		if str(c["iso"]) == iso:
			return str(c["name"])
	return iso


func _map_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := country_at(to_lonlat((event as InputEventMouseMotion).position))
		if h != hovered:
			hovered = h
			map_area.queue_redraw()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var iso := country_at(to_lonlat((event as InputEventMouseButton).position))
		if iso != "":
			select(iso)
			if (event as InputEventMouseButton).double_click and WorldData.is_real(iso):
				chosen.emit(iso)


func _draw_map() -> void:
	var s := map_area.size
	map_area.draw_rect(Rect2(Vector2.ZERO, s), Color(0.12, 0.27, 0.42))
	# Meridianos y paralelos.
	for lon in range(-180, 181, 30):
		map_area.draw_line(to_px(Vector2(lon, LAT_TOP)), to_px(Vector2(lon, LAT_BOTTOM)), Color(1, 1, 1, 0.06), 1.0)
	for lat in range(-60, 90, 30):
		map_area.draw_line(to_px(Vector2(-180, lat)), to_px(Vector2(180, lat)), Color(1, 1, 1, 0.06 if lat != 0 else 0.14), 1.0)
	for c in countries:
		var iso := str(c["iso"])
		var col: Color = CONT_COLORS.get(str(c["continent"]), Color(0.6, 0.6, 0.6)) if bool(c["playable"]) else Color(0.42, 0.45, 0.43)
		if iso == hovered:
			col = col.lightened(0.25)
		if iso == selected:
			col = Color(1.0, 0.8, 0.25)
		var polys: Array = c["polys"]
		for k in range(polys.size()):
			var pts: PackedVector2Array = polys[k]
			var px := PackedVector2Array()
			px.resize(pts.size())
			for i in range(pts.size()):
				px[i] = to_px(pts[i])
			var tri: PackedInt32Array = c["tris"][k]
			if not tri.is_empty():
				var cols := PackedColorArray()
				cols.resize(px.size())
				cols.fill(col)
				RenderingServer.canvas_item_add_triangle_array(map_area.get_canvas_item(), tri, px, cols)
			var outline := px.duplicate()
			outline.append(px[0])
			map_area.draw_polyline(outline, Color(0.08, 0.1, 0.12, 0.8), 1.0)
	# Nombres de los países jugables.
	var font := get_theme_default_font()
	for c in countries:
		if not bool(c["playable"]):
			continue
		var p := to_px(c["label"])
		var nm := str(WorldData.country_name(str(c["iso"])))
		var fs := 12 if s.x > 900 else 10
		var w := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		map_area.draw_string_outline(font, p - Vector2(w * 0.5, -4), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.85))
		map_area.draw_string(font, p - Vector2(w * 0.5, -4), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE if str(c["iso"]) != selected else Color(1, 0.95, 0.7))
