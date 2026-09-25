class_name Minimap
extends Control
## Fase 9A — Minimapa del país (esquina inferior izquierda del HUD).
## Capas: biomas con relieve, niebla de lo no explorado, fronteras tenues entre municipios, tu terreno,
## pueblos (el tuyo en dorado), yacimientos, carreteras y rutas comerciales, y el encuadre de la cámara.
## Clic o arrastre: mueve la cámara. "Ampliar" abre el mapa grande con información del territorio y
## expediciones pagadas para explorar (revelar ≠ comprar: comprar sigue en Construir → Comprar terreno).

const SMALL := 210.0
const BIG := 620.0

var world: Node
var terrain: Terrain
var small_panel: PanelContainer
var big_panel: PanelContainer
var small_map: MapView
var big_map: MapView
var info: RichTextLabel
var exp_btn: Button
var view_btn: Button
var selected := Vector2i(999999, 999999)
var _redraw_t := 0.0


func setup(p_world: Node) -> void:
	world = p_world
	terrain = world.terrain
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Pequeño
	small_panel = PanelContainer.new()
	small_panel.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.08, 0.09, 0.11, 0.86), 6, 6))
	small_panel.anchor_top = 1.0
	small_panel.anchor_bottom = 1.0
	small_panel.offset_left = 184
	small_panel.offset_top = -(SMALL + 52)
	small_panel.offset_bottom = -10
	small_panel.offset_right = 184 + SMALL + 12
	add_child(small_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	small_panel.add_child(v)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	v.add_child(row)
	view_btn = UIKit.button("Ver país (M)", _toggle_country, 104)
	view_btn.tooltip_text = "Aleja la cámara hasta ver el país completo, o vuelve al pueblo"
	row.add_child(view_btn)
	var big_btn := UIKit.button("Ampliar", func(): set_expanded(true), 96)
	big_btn.tooltip_text = "Mapa grande del país: territorios, municipios y expediciones"
	row.add_child(big_btn)
	small_map = MapView.new()
	small_map.custom_minimum_size = Vector2(SMALL, SMALL)
	small_map.owner_map = self
	v.add_child(small_map)
	# Grande
	big_panel = PanelContainer.new()
	big_panel.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.08, 0.09, 0.11, 0.95), 8, 10))
	big_panel.set_anchors_preset(Control.PRESET_CENTER)
	big_panel.offset_left = -(BIG + 330) * 0.5
	big_panel.offset_right = (BIG + 330) * 0.5
	big_panel.offset_top = -(BIG + 20) * 0.5
	big_panel.offset_bottom = (BIG + 20) * 0.5
	big_panel.visible = false
	add_child(big_panel)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	big_panel.add_child(h)
	big_map = MapView.new()
	big_map.custom_minimum_size = Vector2(BIG, BIG)
	big_map.owner_map = self
	big_map.big = true
	h.add_child(big_map)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 300
	side.add_theme_constant_override("separation", 8)
	h.add_child(side)
	var cd := MapSim.country_def(MapSim.country_id(GameState))
	side.add_child(UIKit.label("País: %s" % str(cd.get("label", "")), 18, UIKit.ACCENT))
	var desc := UIKit.label("%s\n%d×%d chunks de 400 m (%.1f km por lado)" % [str(cd.get("description", "")), terrain.gen.size, terrain.gen.size, terrain.gen.size * 0.4], 12, UIKit.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(desc)
	info = UIKit.rich()
	info.custom_minimum_size = Vector2(300, 300)
	info.fit_content = false
	info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(info)
	exp_btn = UIKit.button("Enviar expedición", _send_expedition, 300)
	side.add_child(exp_btn)
	var legend := UIKit.label("Clic: seleccionar y mover la cámara · Revelar el mapa (expediciones, rutas comerciales) no te hace dueño: el terreno se compra en Construir → Comprar terreno.", 11, UIKit.TEXT_DIM)
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(legend)
	var brow := HBoxContainer.new()
	side.add_child(brow)
	brow.add_child(UIKit.button("Ver país", func(): world.camera_rig.view_country(), 96))
	brow.add_child(UIKit.button("Volver al pueblo", func(): world.camera_rig.view_town(), 130))
	brow.add_child(UIKit.button("Cerrar", func(): set_expanded(false), 70))
	EventBus.map_changed.connect(_on_map_changed)
	EventBus.zones_changed.connect(_on_map_changed)
	_select(Vector2i.ZERO)


func set_expanded(on: bool) -> void:
	big_panel.visible = on
	if on:
		_update_info()


func is_expanded() -> bool:
	return big_panel.visible


func _toggle_country() -> void:
	var cr: CameraRig = world.camera_rig
	if cr.is_country_view():
		cr.view_town()
	else:
		cr.view_country()


func _on_map_changed() -> void:
	small_map.invalidate()
	big_map.invalidate()
	_update_info()


func _process(delta: float) -> void:
	_redraw_t -= delta
	if _redraw_t <= 0.0:
		_redraw_t = 0.1
		small_map.queue_redraw()
		if big_panel.visible:
			big_map.queue_redraw()
		view_btn.text = "Volver al pueblo" if world.camera_rig.is_country_view() else "Ver país (M)"


func _unhandled_input(event: InputEvent) -> void:
	if big_panel.visible and event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		set_expanded(false)
		get_viewport().set_input_as_handled()


## Clic en el mapa: mueve la cámara (y en el grande selecciona el chunk).
func clicked(world_pos: Vector2, big: bool) -> void:
	var cr: CameraRig = world.camera_rig
	cr.focus(Vector3(world_pos.x, 0, world_pos.y), -1.0)
	if big:
		_select(MapSim.chunk_of(world_pos.x, world_pos.y))


func _select(c: Vector2i) -> void:
	selected = c
	_update_info()


func _update_info() -> void:
	if info == null:
		return
	var gs = GameState
	var c := selected
	var center := Vector2(c.x, c.y) * CountryGen.CHUNK
	var lines := []
	var inside := MapSim.in_country_chunk(gs, c.x, c.y)
	lines.append("[b]Territorio (%d, %d)[/b] · a %.1f km de la plaza" % [c.x, c.y, center.length() / 1000.0])
	if not inside:
		lines.append("Fuera del país.")
		exp_btn.disabled = true
		info.text = "\n".join(lines)
		return
	var rev := MapSim.is_revealed(gs, c.x, c.y)
	var mun := MapSim.municipality_at(gs, center.x, center.y)
	lines.append("Municipio: %s" % ("con pueblo (%s)" % str(mun.get("placeholder_name", GameState.settings.get("town_name", ""))) if bool(mun.get("town", false)) else "zona libre, sin pueblo"))
	if rev:
		var cl := MapSim.climate_at(center.x, center.y, gs)
		lines.append("Bioma: %s · altura %d m · %+.1f °C respecto al pueblo" % [MapSim.biome_label(str(cl["biome"])), int(cl["altitude"]), float(cl["temp_offset_c"])])
		var owned := 0
		for zy in range(c.y * 5, c.y * 5 + 5):
			for zx in range(c.x * 5, c.x * 5 + 5):
				if gs.is_zone_unlocked(zx, zy):
					owned += 1
		lines.append("Tu terreno aquí: %d de 25 parcelas" % owned if owned > 0 else "Dueño: Estado (se compra por parcelas de 80 m)")
		exp_btn.text = "Explorado"
		exp_btn.disabled = true
	else:
		lines.append("[color=#aab]Sin explorar: se ve en la niebla.[/color]")
		var reason := MapSim.expedition_block_reason(gs, c.x, c.y)
		lines.append("Expedición: %s · %d días%s" % [Fmt.money(MapSim.expedition_cost(gs, c.x, c.y)), MapSim.expedition_days(gs, c.x, c.y), "" if reason == "" else "\n[color=#e88]%s[/color]" % reason])
		exp_btn.text = "Enviar expedición (%s)" % Fmt.money(MapSim.expedition_cost(gs, c.x, c.y))
		exp_btn.disabled = reason != ""
	var active: Array = gs.map.get("expeditions", [])
	if not active.is_empty():
		lines.append("")
		lines.append("[b]Expediciones en camino[/b]")
		for ex in active:
			lines.append("· (%d, %d): faltan %d días" % [int(ex["cx"]), int(ex["cy"]), int(ex["days_left"])])
	lines.append("")
	lines.append("Explorado: %d de %d territorios" % [MapSim.revealed_count(gs), terrain.gen.size * terrain.gen.size])
	info.text = "\n".join(lines)


func _send_expedition() -> void:
	var err := MapSim.start_expedition(GameState, selected.x, selected.y)
	if err != "" and world.hud:
		world.hud.toast(err, "jugador")
	_update_info()


# =============================================================================================

class MapView:
	extends Control
	## Dibujo del mapa del país (sirve para el pequeño y el grande).

	var owner_map: Minimap
	var big := false
	var _borders: PackedVector2Array = PackedVector2Array()
	var _dragging := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true

	func invalidate() -> void:
		queue_redraw()

	func _bounds() -> Rect2:
		return owner_map.terrain.country_rect_m()

	func to_px(p: Vector2) -> Vector2:
		var b := _bounds()
		return (p - b.position) / b.size * size

	func to_world(px: Vector2) -> Vector2:
		var b := _bounds()
		return b.position + px / size * b.size

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_dragging = (event as InputEventMouseButton).pressed
			if _dragging:
				owner_map.clicked(to_world((event as InputEventMouseButton).position), big)
			accept_event()
		elif event is InputEventMouseMotion and _dragging:
			owner_map.clicked(to_world((event as InputEventMouseMotion).position), false)
			accept_event()

	func _build_borders() -> void:
		var g := owner_map.terrain.gen
		_borders = PackedVector2Array()
		for cy in range(g.c0, g.c1 + 1):
			for cx in range(g.c0, g.c1 + 1):
				var zi := g.zone_index(cx, cy)
				if cx < g.c1 and g.zone_index(cx + 1, cy) != zi:
					var x := cx * CountryGen.CHUNK + CountryGen.HALF_CHUNK
					_borders.append(Vector2(x, cy * CountryGen.CHUNK - CountryGen.HALF_CHUNK))
					_borders.append(Vector2(x, cy * CountryGen.CHUNK + CountryGen.HALF_CHUNK))
				if cy < g.c1 and g.zone_index(cx, cy + 1) != zi:
					var z := cy * CountryGen.CHUNK + CountryGen.HALF_CHUNK
					_borders.append(Vector2(cx * CountryGen.CHUNK - CountryGen.HALF_CHUNK, z))
					_borders.append(Vector2(cx * CountryGen.CHUNK + CountryGen.HALF_CHUNK, z))

	func _draw() -> void:
		var t := owner_map.terrain
		if t == null or t.gen == null:
			return
		var g := t.gen
		var gs = GameState
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.74, 0.77, 0.82))
		# Biomas (textura que llena el terreno al construir la capa lejana).
		if t.map_texture != null:
			var src := Rect2(t.ring * 8, t.ring * 8, g.size * 8, g.size * 8)
			draw_texture_rect_region(t.map_texture, Rect2(Vector2.ZERO, size), src)
		var cpx := size.x / g.size
		# Niebla de lo no explorado.
		for cy in range(g.c0, g.c1 + 1):
			for cx in range(g.c0, g.c1 + 1):
				if not MapSim.is_revealed(gs, cx, cy):
					draw_rect(Rect2((cx - g.c0) * cpx, (cy - g.c0) * cpx, cpx + 0.5, cpx + 0.5), Color(0.8, 0.83, 0.88, 0.62))
		# Fronteras tenues entre municipios.
		if _borders.is_empty():
			_build_borders()
		for i in range(0, _borders.size(), 2):
			draw_line(to_px(_borders[i]), to_px(_borders[i + 1]), Color(1, 1, 1, 0.38), 1.0)
		# Tu terreno (parcelas de 80 m).
		var zs: float = gs.MAP_SIZE / gs.ZONE_GRID
		for z in gs.unlocked_zones:
			var p0 := to_px(Vector2(int(z[0]) * zs - 200.0, int(z[1]) * zs - 200.0))
			var p1 := to_px(Vector2((int(z[0]) + 1) * zs - 200.0, (int(z[1]) + 1) * zs - 200.0))
			draw_rect(Rect2(p0, (p1 - p0).max(Vector2(2, 2))), Color(1.0, 0.78, 0.2, 0.9))
		# Carreteras y rutas comerciales.
		for r in RoadSim.roads(gs):
			draw_line(to_px(RoadSim.seg_a(r)), to_px(RoadSim.seg_b(r)), Color(0.45, 0.3, 0.18), 1.5)
		for c in TradeSim.connected_towns(gs):
			var tp := MapSim.trade_town_pos(gs, str(c.get("town_id", "")))
			if tp != Vector2.INF:
				draw_dashed_line(to_px(Vector2.ZERO), to_px(tp), Color(0.95, 0.85, 0.5, 0.9), 1.5, 4.0)
		# Yacimientos.
		for d in gs.logistics.get("deposits", []):
			var dp := to_px(Vector2(float(d.get("x", 0.0)), float(d.get("z", 0.0))))
			draw_circle(dp, 3.0 if big else 2.0, Color(0, 0, 0, 0.7))
			draw_circle(dp, 2.2 if big else 1.4, RegionSim.resource_color(str(d.get("type", ""))))
		# Pueblos (también los que siguen en la niebla).
		var font := get_theme_default_font()
		for z in g.zones:
			if not bool(z["town"]):
				continue
			var tpx := to_px(z["town_pos"])
			var ch: Vector2i = z["town_chunk"]
			var rev := MapSim.is_revealed(gs, ch.x, ch.y)
			if bool(z["player"]):
				draw_circle(tpx, 5.5 if big else 4.0, Color(0, 0, 0, 0.8))
				draw_circle(tpx, 4.2 if big else 3.0, Color(1.0, 0.8, 0.2))
			else:
				draw_circle(tpx, 3.6 if big else 2.6, Color(0, 0, 0, 0.6))
				draw_circle(tpx, 2.6 if big else 1.8, Color(1, 1, 1) if rev else Color(0.6, 0.64, 0.7))
			if big:
				var nm := str(z.get("placeholder_name", ""))
				if bool(z["player"]):
					nm = str(gs.settings.get("town_name", nm))
				draw_string_outline(font, tpx + Vector2(6, 4), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color(0, 0, 0, 0.8))
				draw_string(font, tpx + Vector2(6, 4), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.9, 0.5) if bool(z["player"]) else (Color.WHITE if rev else Color(0.85, 0.88, 0.92)))
		# Selección (mapa grande).
		if big and MapSim.in_country_chunk(gs, owner_map.selected.x, owner_map.selected.y):
			var sr := CountryGen.chunk_rect(owner_map.selected.x, owner_map.selected.y)
			draw_rect(Rect2(to_px(sr.position), to_px(sr.end) - to_px(sr.position)), Color(1, 1, 1, 0.95), false, 2.0)
		# Encuadre de la cámara.
		var cr: CameraRig = owner_map.world.camera_rig
		if cr:
			var cp := to_px(Vector2(cr.position.x, cr.position.z))
			var half_w: float = maxf(4.0, cr.distance * 0.75 / _bounds().size.x * size.x)
			draw_rect(Rect2(cp - Vector2(half_w, half_w * 0.62), Vector2(half_w * 2.0, half_w * 1.24)), Color(1, 1, 1, 0.9), false, 1.5)
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.35), false, 1.0)
