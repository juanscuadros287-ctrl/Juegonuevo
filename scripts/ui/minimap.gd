class_name Minimap
extends Control
## Fase 9A/9B — Minimapa del país (esquina inferior izquierda del HUD).
## Capas: biomas con relieve, velo de lo no explorado, fronteras de municipios, tu terreno, pueblos (el tuyo
## en dorado), yacimientos, carreteras y rutas comerciales, y el encuadre de la cámara.
## Clic o arrastre: mueve la cámara. "Ampliar" abre el mapa grande: al seleccionar un territorio se ve su
## municipio (alcalde, política, misiones regionales), su dueño y su precio, con Comprar / Licitar / Ofertar,
## y una capa de propiedad (Estado, particulares, tuyo). También expediciones pagadas para explorar.

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
var layer_btn: Button
var buy_btn: Button
var tender_btn: Button
var offer_btn: Button
var amount_spin: SpinBox
var mission_btn: Button
var selected := Vector2i(999999, 999999)
var show_owner := false
var _redraw_t := 0.0
var fog_texture: ImageTexture
var owner_texture: ImageTexture


func setup(p_world: Node) -> void:
	world = p_world
	terrain = world.terrain
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Pequeño
	# Mapa v2: esquina inferior izquierda, alineado con la barra de categorías (x = 8) y con su mismo
	# estilo flotante de UIKit; si la ventana es baja y chocaría con la barra, se corre a su derecha.
	small_panel = PanelContainer.new()
	small_panel.add_theme_stylebox_override("panel", UIKit.float_style(Color(0.075, 0.082, 0.1, 0.9), 12, 6))
	small_panel.anchor_top = 1.0
	small_panel.anchor_bottom = 1.0
	add_child(small_panel)
	_place_small()
	resized.connect(_place_small)
	_place_small.call_deferred()
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
	big_btn.tooltip_text = "Mapa grande del país: municipios, tierras en venta, misiones y expediciones"
	row.add_child(big_btn)
	small_map = MapView.new()
	small_map.custom_minimum_size = Vector2(SMALL, SMALL)
	small_map.owner_map = self
	v.add_child(small_map)
	# Grande
	big_panel = PanelContainer.new()
	big_panel.add_theme_stylebox_override("panel", UIKit.float_style(Color(0.075, 0.082, 0.1, 0.96), 12, 10))
	big_panel.anchor_left = 0.5
	big_panel.anchor_right = 0.5
	big_panel.anchor_top = 0.5
	big_panel.anchor_bottom = 0.5
	big_panel.offset_left = -(BIG + 370) * 0.5
	big_panel.offset_right = (BIG + 370) * 0.5
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
	side.custom_minimum_size.x = 340
	side.add_theme_constant_override("separation", 6)
	h.add_child(side)
	var cd := MapSim.country_def(MapSim.country_id(GameState))
	side.add_child(UIKit.label("País: %s" % str(cd.get("label", "")), 18, UIKit.ACCENT))
	var desc := UIKit.label("%d×%d territorios de 400 m (%.1f km por lado) · %d municipios" % [terrain.gen.size, terrain.gen.size, terrain.gen.size * 0.4, terrain.gen.zones.size()], 12, UIKit.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(desc)
	var lrow := HBoxContainer.new()
	side.add_child(lrow)
	layer_btn = UIKit.button("Capa: biomas", _toggle_layer, 160)
	layer_btn.tooltip_text = "Alterna la capa de propiedad: Estado, particulares y lo tuyo"
	lrow.add_child(layer_btn)
	info = UIKit.rich()
	info.custom_minimum_size = Vector2(340, 300)
	info.fit_content = false
	info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(info)
	var arow := HBoxContainer.new()
	arow.add_theme_constant_override("separation", 4)
	side.add_child(arow)
	arow.add_child(UIKit.label("Monto:", 13))
	amount_spin = UIKit.spin(0, 1e9, 10, 0, func(_v): pass, 130)
	arow.add_child(amount_spin)
	var brow1 := HBoxContainer.new()
	brow1.add_theme_constant_override("separation", 4)
	side.add_child(brow1)
	buy_btn = UIKit.button("Comprar", _buy_fixed, 110)
	buy_btn.tooltip_text = "Comprar al Estado a precio fijo"
	brow1.add_child(buy_btn)
	tender_btn = UIKit.button("Licitar", _tender, 105)
	tender_btn.tooltip_text = "Licitación del Estado: puja con el monto indicado; gana la mejor oferta"
	brow1.add_child(tender_btn)
	offer_btn = UIKit.button("Ofertar", _offer, 105)
	offer_btn.tooltip_text = "Oferta al dueño particular: acepta o rechaza en unos días"
	brow1.add_child(offer_btn)
	mission_btn = UIKit.button("Aceptar misión del municipio", _accept_mission, 330)
	side.add_child(mission_btn)
	exp_btn = UIKit.button("Enviar expedición", _send_expedition, 330)
	side.add_child(exp_btn)
	var legend := UIKit.label("Clic: seleccionar y mover la cámara · Explorar no te hace dueño: compra al Estado (precio fijo o licitación) o haz una oferta al particular.", 11, UIKit.TEXT_DIM)
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(legend)
	var brow := HBoxContainer.new()
	side.add_child(brow)
	brow.add_child(UIKit.button("Ver país", func(): world.camera_rig.view_country(), 96))
	brow.add_child(UIKit.button("Volver al pueblo", func(): world.camera_rig.view_town(), 130))
	brow.add_child(UIKit.button("Cerrar", func(): set_expanded(false), 70))
	EventBus.map_changed.connect(_on_map_changed)
	EventBus.zones_changed.connect(_on_map_changed)
	_rebuild_layers()
	_select(Vector2i.ZERO)


## Coloca el minimapa pequeño abajo a la izquierda sin tapar la barra de categorías del HUD.
func _place_small() -> void:
	if small_panel == null:
		return
	var left := 8.0
	var h := SMALL + 52.0
	var rail: Control = world.hud.side_menu if world != null and world.get("hud") != null and world.hud.get("side_menu") != null else null
	if rail != null and size.y > 0.0 and size.y - 10.0 - h < rail.position.y + rail.size.y + 8.0:
		left = rail.position.x + rail.size.x + 8.0
	small_panel.offset_left = left
	small_panel.offset_right = left + SMALL + 12.0
	small_panel.offset_top = -(h + 10.0)
	small_panel.offset_bottom = -10.0


func set_expanded(on: bool) -> void:
	big_panel.visible = on
	if on:
		_update_info()


func is_expanded() -> bool:
	return big_panel.visible


func set_owner_layer(on: bool) -> void:
	show_owner = on
	layer_btn.text = "Capa: propiedad" if on else "Capa: biomas"
	_rebuild_layers()
	big_map.queue_redraw()


func _toggle_layer() -> void:
	set_owner_layer(not show_owner)


func _toggle_country() -> void:
	var cr: CameraRig = world.camera_rig
	if cr.is_country_view():
		cr.view_town()
	else:
		cr.view_country()


func _on_map_changed() -> void:
	_rebuild_layers()
	small_map.invalidate()
	big_map.invalidate()
	_update_info()


## Texturas de velo (niebla) y de propiedad: una celda por territorio, filtradas al dibujar.
func _rebuild_layers() -> void:
	var g := terrain.gen
	var gs = GameState
	var img := Image.create(g.size, g.size, false, Image.FORMAT_RGBA8)
	for cy in range(g.c0, g.c1 + 1):
		for cx in range(g.c0, g.c1 + 1):
			var lvl := MapSim.fog_level(gs, cx, cy)
			var a: float = [0.0, 0.22, 0.5, 0.8][lvl]
			img.set_pixel(cx - g.c0, cy - g.c0, Color(0.86, 0.88, 0.92, a))
	if fog_texture == null:
		fog_texture = ImageTexture.create_from_image(img)
	else:
		fog_texture.update(img)
	if not show_owner:
		return
	var grid := LandSim.owner_grid(gs)
	var oi := Image.create(g.size, g.size, false, Image.FORMAT_RGBA8)
	var cols := [Color(0.35, 0.62, 0.95, 0.35), Color(0.78, 0.3, 0.72, 0.55), Color(1.0, 0.78, 0.2, 0.85), Color(1.0, 0.86, 0.45, 0.6), Color(0, 0, 0, 0)]
	for j in range(g.size):
		for i in range(g.size):
			oi.set_pixel(i, j, cols[grid[j * g.size + i]])
	if owner_texture == null:
		owner_texture = ImageTexture.create_from_image(oi)
	else:
		owner_texture.update(oi)


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


## Clic en el mapa: mueve la cámara (y en el grande selecciona el territorio).
func clicked(world_pos: Vector2, big: bool) -> void:
	var cr: CameraRig = world.camera_rig
	cr.focus(Vector3(world_pos.x, 0, world_pos.y), -1.0)
	if big:
		_select(MapSim.chunk_of(world_pos.x, world_pos.y))


func _select(c: Vector2i) -> void:
	var changed := c != selected
	selected = c
	if changed and amount_spin != null and MapSim.in_country_chunk(GameState, c.x, c.y):
		amount_spin.value = LandSim.remaining_price(GameState, c.x, c.y)
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
	for b in [buy_btn, tender_btn, offer_btn, mission_btn, exp_btn]:
		b.disabled = true
	if not inside:
		lines.append("Fuera del país.")
		info.text = "\n".join(lines)
		return
	var rev := MapSim.is_revealed(gs, c.x, c.y)
	# Municipio: alcalde, departamento y política.
	var reg := MapSim.region_at(gs, center.x, center.y)
	var zid := int(reg.get("municipality_id", -1))
	var mayor: Dictionary = reg.get("mayor", {})
	lines.append("[b][color=#f2c65a]%s[/color][/b] · dpto. %s · %s" % [reg.get("name", ""), reg.get("department_name", ""), "con pueblo (%s hab.)" % Fmt.thousands(float(reg.get("population", 0))) if bool(reg.get("town", false)) else "zona rural"])
	lines.append("%s: %s (%s)" % [mayor.get("title", "Alcalde"), mayor.get("name", ""), MunicipalSim.stance_label(str(mayor.get("stance", "")))])
	lines.append("[color=#bbc]%s[/color]" % MunicipalSim.policy_text(gs, zid))
	if rev:
		var cl := MapSim.climate_at(center.x, center.y, gs)
		lines.append("Bioma: %s · altura %d m · %+.1f °C respecto al pueblo" % [MapSim.biome_label(str(cl["biome"])), int(cl["altitude"]), float(cl["temp_offset_c"])])
		var own := LandSim.owner_info(gs, c.x, c.y)
		var price := LandSim.remaining_price(gs, c.x, c.y)
		lines.append("")
		lines.append("[b]Dueño:[/b] %s%s" % [LandSim.owner_label(own), " (tuyas %d de 25 parcelas)" % int(own["player_parcels"]) if int(own["player_parcels"]) > 0 and str(own["owner"]) != "jugador" else ""])
		if str(own["owner"]) != "jugador":
			lines.append("[b]Precio de mercado:[/b] %s (%s por parcela) · índice del municipio ×%.2f" % [Fmt.money(price), Fmt.money(price / maxf(1.0, 25.0 - float(own["player_parcels"]))), LandSim.index_of(gs, zid) * LandSim.demand_of(gs, zid)])
		var amt := float(amount_spin.value)
		buy_btn.text = "Comprar %s" % Fmt.money(price)
		buy_btn.disabled = LandSim.buy_block_reason(gs, c.x, c.y, "fijo") != ""
		buy_btn.tooltip_text = LandSim.buy_block_reason(gs, c.x, c.y, "fijo") if buy_btn.disabled else "Comprar al Estado a precio fijo"
		tender_btn.disabled = LandSim.buy_block_reason(gs, c.x, c.y, "licitacion", amt) != ""
		tender_btn.tooltip_text = LandSim.buy_block_reason(gs, c.x, c.y, "licitacion", amt) if tender_btn.disabled else "Pujar %s en la licitación" % Fmt.money(amt)
		offer_btn.disabled = LandSim.buy_block_reason(gs, c.x, c.y, "oferta", amt) != ""
		offer_btn.tooltip_text = LandSim.buy_block_reason(gs, c.x, c.y, "oferta", amt) if offer_btn.disabled else "Ofrecer %s al dueño" % Fmt.money(amt)
		exp_btn.text = "Explorado"
	else:
		lines.append("[color=#aab]Sin explorar: se ve bajo el velo.[/color]")
		var reason := MapSim.expedition_block_reason(gs, c.x, c.y)
		lines.append("Expedición: %s · %d días%s" % [Fmt.money(MapSim.expedition_cost(gs, c.x, c.y)), MapSim.expedition_days(gs, c.x, c.y), "" if reason == "" else "\n[color=#e88]%s[/color]" % reason])
		exp_btn.text = "Enviar expedición (%s)" % Fmt.money(MapSim.expedition_cost(gs, c.x, c.y))
		exp_btn.disabled = reason != ""
	# Misiones regionales del municipio.
	var rm: Dictionary = gs.map.get("region_missions", {})
	var any := false
	for m in rm.get("available", []):
		if int(m["zone"]) == zid:
			if not any:
				lines.append("")
				lines.append("[b]Misión propuesta por %s[/b]" % str(m.get("mayor", "")))
			any = true
			lines.append("· %s — recompensa %s%s" % [m["label"], Fmt.money(float(m.get("reward_money", 0.0))), " y %d meses sin impuesto local" % int(m.get("reward_tax_months", 0)) if int(m.get("reward_tax_months", 0)) > 0 else ""])
			mission_btn.disabled = false
	for m in rm.get("active", []):
		if int(m["zone"]) == zid:
			lines.append("· En curso: %s (%s)" % [m["label"], MunicipalSim.mission_progress(gs, m)])
	# Ofertas y licitaciones pendientes.
	var pend := []
	for o in gs.map.get("land_offers", []):
		pend.append("· Oferta a %s por (%d, %d): %s, responde en %d días" % [o["seller"], int(o["cx"]), int(o["cy"]), Fmt.money(float(o["amount"])), maxi(0, int(o["reply_day"]) - gs.today())])
	for t in gs.map.get("land_tenders", []):
		pend.append("· Licitación (%d, %d): pujaste %s, se adjudica en %d días" % [int(t["cx"]), int(t["cy"]), Fmt.money(float(t["bid"])), maxi(0, int(t["close_day"]) - gs.today())])
	var active: Array = gs.map.get("expeditions", [])
	for ex in active:
		pend.append("· Expedición a (%d, %d): faltan %d días" % [int(ex["cx"]), int(ex["cy"]), int(ex["days_left"])])
	if not pend.is_empty():
		lines.append("")
		lines.append("[b]En trámite[/b]")
		lines.append_array(pend)
	lines.append("")
	lines.append("Explorado: %d de %d territorios" % [MapSim.revealed_count(gs), MapSim.country_chunk_count(gs)])
	info.text = "\n".join(lines)


func _toast(err: String) -> void:
	if err != "" and world.hud:
		world.hud.toast(err, "jugador")


func _send_expedition() -> void:
	_toast(MapSim.start_expedition(GameState, selected.x, selected.y))
	_update_info()


func _buy_fixed() -> void:
	_toast(LandSim.buy_from_state(GameState, selected.x, selected.y))
	_update_info()


func _tender() -> void:
	_toast(LandSim.start_tender(GameState, selected.x, selected.y, float(amount_spin.value)))
	_update_info()


func _offer() -> void:
	_toast(LandSim.make_offer(GameState, selected.x, selected.y, float(amount_spin.value)))
	_update_info()


func _accept_mission() -> void:
	var gs = GameState
	var reg := MapSim.region_at(gs, selected.x * CountryGen.CHUNK, selected.y * CountryGen.CHUNK)
	var avail: Array = gs.map.get("region_missions", {}).get("available", [])
	for i in range(avail.size()):
		if int(avail[i]["zone"]) == int(reg.get("municipality_id", -1)):
			_toast(MunicipalSim.accept_mission(gs, i))
			break
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
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

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
		var full := Rect2(Vector2.ZERO, size)
		draw_rect(full, Color(0.74, 0.77, 0.82))
		# Biomas (textura que llena el terreno al construir la capa lejana).
		if t.map_texture != null:
			var src := Rect2(t.ring * Terrain.MAP_PX, t.ring * Terrain.MAP_PX, g.size * Terrain.MAP_PX, g.size * Terrain.MAP_PX)
			draw_texture_rect_region(t.map_texture, full, src)
		# Velo de lo no explorado (translúcido) y capa de propiedad.
		if owner_map.fog_texture != null:
			draw_texture_rect(owner_map.fog_texture, full, false)
		if big and owner_map.show_owner and owner_map.owner_texture != null:
			draw_texture_rect(owner_map.owner_texture, full, false)
		# Fronteras entre municipios.
		if _borders.is_empty():
			_build_borders()
		var pts := PackedVector2Array()
		pts.resize(_borders.size())
		for i in range(_borders.size()):
			pts[i] = to_px(_borders[i])
		if not pts.is_empty():
			draw_multiline(pts, Color(1, 1, 1, 0.4), 1.0)
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
		# Pueblos (también los que siguen en la niebla) y nombres de los municipios.
		var font := get_theme_default_font()
		for z in g.zones:
			var zid := int(z["id"])
			var rev := MapSim.zone_revealed_any(gs, zid)
			var player := bool(z["player"])
			var anchor: Vector2 = to_px(z["centroid"])
			if bool(z["town"]):
				var tpx := to_px(z["town_pos"])
				anchor = tpx
				if player:
					draw_circle(tpx, 5.5 if big else 4.0, Color(0, 0, 0, 0.8))
					draw_circle(tpx, 4.2 if big else 3.0, Color(1.0, 0.8, 0.2))
				else:
					draw_circle(tpx, 3.6 if big else 2.6, Color(0, 0, 0, 0.6))
					draw_circle(tpx, 2.6 if big else 1.8, Color(1, 1, 1) if rev else Color(0.6, 0.64, 0.7))
			if big:
				var nm := str(gs.settings.get("town_name", "")) if player else MunicipalSim.name_of(gs, zid)
				var fs := 13 if player else 11
				var off := Vector2(6, 4) if bool(z["town"]) else Vector2(-font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * 0.5, 4)
				draw_string_outline(font, anchor + off, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.8))
				draw_string(font, anchor + off, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.9, 0.5) if player else (Color.WHITE if rev else Color(0.85, 0.88, 0.92, 0.85)))
		# Selección (mapa grande).
		if big and MapSim.in_country_chunk(gs, owner_map.selected.x, owner_map.selected.y):
			var sr := CountryGen.chunk_rect(owner_map.selected.x, owner_map.selected.y)
			draw_rect(Rect2(to_px(sr.position), to_px(sr.end) - to_px(sr.position)), Color(1, 1, 1, 0.95), false, 2.0)
		# Leyenda de la capa de propiedad.
		if big and owner_map.show_owner:
			var y := size.y - 70.0
			draw_rect(Rect2(6, y - 6, 150, 66), Color(0, 0, 0, 0.55))
			var items := [["Estado", Color(0.35, 0.62, 0.95)], ["Particulares", Color(0.78, 0.3, 0.72)], ["Tuyo", Color(1.0, 0.78, 0.2)]]
			for i in range(items.size()):
				draw_rect(Rect2(12, y + i * 18, 12, 12), items[i][1])
				draw_string(font, Vector2(30, y + i * 18 + 11), str(items[i][0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
		# Encuadre de la cámara.
		var cr: CameraRig = owner_map.world.camera_rig
		if cr:
			var cp := to_px(Vector2(cr.position.x, cr.position.z))
			var half_w: float = maxf(4.0, cr.distance * 0.75 / _bounds().size.x * size.x)
			draw_rect(Rect2(cp - Vector2(half_w, half_w * 0.62), Vector2(half_w * 2.0, half_w * 1.24)), Color(1, 1, 1, 0.9), false, 1.5)
		draw_rect(full, Color(1, 1, 1, 0.35), false, 1.0)
