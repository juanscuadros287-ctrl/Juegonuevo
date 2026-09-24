class_name GoodsCatalog
extends Control
## Catálogo de bienes (economía real): cada bien con su modelo 3D girando (SubViewport), su cadena
## de producción (de qué se hace, qué fábrica lo produce, qué lo usa, dónde se vende), precio de
## mercado y época de aparición. Pantalla completa, como el árbol de investigación.
##
## Uso desde el HUD:  var cat := GoodsCatalog.new(); root.add_child(cat); cat.setup(); … cat.open()
## (open() también llama a setup() si hace falta). open("acero") abre con un bien seleccionado.

const CATEGORIES := [
	["", "Todos"], ["materia_prima", "Materias primas"], ["intermedio", "Intermedios"],
	["producto", "Productos"], ["energia", "Energía"], ["servicio", "Servicios"],
]
const CAT_COLORS := {
	"materia_prima": Color(0.62, 0.48, 0.3), "intermedio": Color(0.45, 0.55, 0.7),
	"producto": Color(0.4, 0.68, 0.42), "energia": Color(0.92, 0.75, 0.25), "servicio": Color(0.68, 0.5, 0.75),
}
const CAT_ORDER := {"materia_prima": 0, "intermedio": 1, "producto": 2, "energia": 3, "servicio": 4}

var selected := ""
var cat_filter := ""
var era_filter := 0
var only_available := false
var _built := false
var header: RichTextLabel
var grid: GridContainer
var detail: RichTextLabel
var model_title: Label
var viewport: SubViewport
var pivot: Node3D
var cards := {}   # bien -> Button
var era_opt: OptionButton
var cat_buttons := {}


# --- Datos (estáticos: se pueden usar sin interfaz) ----------------------------------------------

static func category_of(good: String) -> String:
	var g: Dictionary = GameData.goods.get(good, {})
	if g.has("category"):
		return str(g["category"])
	if bool(g.get("raw", false)):
		return "materia_prima"
	if bool(g.get("intermediate", false)):
		return "intermedio"
	return "producto"


static func category_label(cat: String) -> String:
	for c in CATEGORIES:
		if c[0] == cat:
			return str(c[1])
	return cat


## Bienes del catálogo (sin los internos), ordenados por categoría y orden.
static func good_ids(cat := "", era := 0) -> Array:
	var out := []
	for g in GameData.goods:
		var d: Dictionary = GameData.goods[g]
		if str(g).begins_with("_") or bool(d.get("internal", false)):
			continue
		if cat != "" and category_of(g) != cat:
			continue
		if era > 0 and era_of(g) != era:
			continue
		out.append(g)
	out.sort_custom(func(a, b):
		var ca := int(CAT_ORDER.get(category_of(a), 9))
		var cb := int(CAT_ORDER.get(category_of(b), 9))
		if ca != cb:
			return ca < cb
		return int(GameData.goods[a].get("order", 0)) < int(GameData.goods[b].get("order", 0)))
	return out


static func era_of(good: String) -> int:
	return int(GameData.goods.get(good, {}).get("era", 1))


## Negocios que lo producen: [{type, level, label, tech, inputs, business}] (un registro por nivel).
static func producers(good: String) -> Array:
	var out := []
	for t in GameData.businesses:
		var def: Dictionary = GameData.businesses[t]
		if str(t).begins_with("_") or str(def.get("product", "")) != good:
			continue
		var levels: Array = def.get("levels", [])
		for i in range(levels.size()):
			var ld: Dictionary = levels[i]
			out.append({"type": t, "level": i + 1, "label": str(ld.get("label", def.get("label", t))), "business": str(def.get("label", t)),
				"tech": str(ld.get("tech", "")), "inputs": ld.get("inputs", def.get("inputs", {})), "deposit": str(ld.get("requires_deposit", ""))})
	return out


## Bienes con los que se fabrica (unión de las recetas de todos los niveles).
static func inputs_of(good: String) -> Array:
	var out := []
	for p in producers(good):
		for g in p["inputs"]:
			if not out.has(g):
				out.append(g)
	return out


## Productos que usan este bien como insumo: [{good, business}] sin repetir.
static func consumers(good: String) -> Array:
	var out := []
	var seen := {}
	for t in GameData.businesses:
		var def: Dictionary = GameData.businesses[t]
		if str(t).begins_with("_"):
			continue
		for ld in def.get("levels", []):
			if ld.get("inputs", def.get("inputs", {})).has(good):
				var key := "%s|%s" % [def.get("product", ""), t]
				if not seen.has(key):
					seen[key] = true
					out.append({"good": str(def.get("product", "")), "business": str(def.get("label", t)), "type": t})
				break
	return out


## Primera tecnología con la que se puede producir (o la declarada en el bien).
static func first_tech(good: String) -> String:
	var g: Dictionary = GameData.goods.get(good, {})
	if g.has("tech"):
		return str(g["tech"])
	var best := ""
	var best_era := 99
	for p in producers(good):
		var tech := str(p["tech"])
		var e := int(GameData.technologies.get(tech, {}).get("era", 1)) if tech != "" else 0
		if e < best_era:
			best_era = e
			best = tech
	return best


## Modelo 3D del bien (piezas de MeshLib) o una caja del color de su categoría.
static func build_good_model(good: String) -> Node3D:
	var parts: Array = GameData.goods.get(good, {}).get("model", [])
	if parts.is_empty():
		var col: Color = CAT_COLORS.get(category_of(good), Color(0.7, 0.7, 0.7))
		parts = [{"s": "box", "size": [0.6, 0.6, 0.6], "pos": [0, 0.3, 0], "c": [col.r, col.g, col.b]}]
	return MeshLib.build_model(parts)


## Tamaño aproximado (ancho, alto) de las piezas para encuadrar la cámara.
static func model_extent(good: String) -> Vector2:
	var w := 0.4
	var h := 0.4
	for p in GameData.goods.get(good, {}).get("model", []):
		var s: Array = p.get("size", [1, 1, 1])
		var pos: Array = p.get("pos", [0, 0, 0])
		var sx := float(s[0])
		var sz := float(s[2])
		if str(p.get("s", "")) == "cyl":
			sx = maxf(float(s[0]), float(s[2])) * 2.0
			sz = sx
		w = maxf(w, maxf(absf(float(pos[0])) * 2.0 + sx, absf(float(pos[2])) * 2.0 + sz))
		h = maxf(h, float(pos[1]) + float(s[1]) * 0.5)
	return Vector2(w, h)


# --- Interfaz ------------------------------------------------------------------------------------

func setup() -> void:
	if _built:
		return
	_built = true
	name = "GoodsCatalog"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.09, 0.97)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 16
	root.offset_right = -16
	root.offset_top = 12
	root.offset_bottom = -12
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	# Encabezado y filtros.
	var head := HBoxContainer.new()
	root.add_child(head)
	header = UIKit.rich()
	head.add_child(header)
	head.add_child(UIKit.button("Cerrar (Esc)", func(): close(), 120))
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 6)
	root.add_child(filters)
	for c in CATEGORIES:
		var cid: String = c[0]
		var b := UIKit.button(str(c[1]), func(): _set_category(cid))
		b.toggle_mode = true
		filters.add_child(b)
		cat_buttons[cid] = b
	filters.add_child(VSeparator.new())
	filters.add_child(UIKit.label("Época:"))
	era_opt = OptionButton.new()
	era_opt.add_item("Todas")
	for e in GameData.eras.get("eras", []):
		era_opt.add_item(str(e["label"]))
	era_opt.item_selected.connect(_on_era)
	filters.add_child(era_opt)
	var avail := CheckBox.new()
	avail.text = "Solo lo que ya se puede producir"
	avail.toggled.connect(_on_available)
	filters.add_child(avail)
	# Cuerpo: tarjetas a la izquierda, modelo 3D y ficha a la derecha.
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	root.add_child(body)
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(sc)
	grid = GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	sc.add_child(grid)
	var side := PanelContainer.new()
	side.custom_minimum_size = Vector2(520, 0)
	body.add_child(side)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 6)
	side.add_child(sv)
	model_title = UIKit.label("", 20, UIKit.ACCENT)
	sv.add_child(model_title)
	sv.add_child(_build_viewport())
	var dsc := ScrollContainer.new()
	dsc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sv.add_child(dsc)
	detail = UIKit.rich()
	detail.meta_clicked.connect(func(meta): select(str(meta)))
	dsc.add_child(detail)
	_rebuild_cards()


func _build_viewport() -> Control:
	var cont := SubViewportContainer.new()
	cont.custom_minimum_size = Vector2(500, 300)
	cont.stretch = true
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.size = Vector2i(500, 300)
	cont.add_child(viewport)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.12, 0.13, 0.16)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.75, 0.8)
	e.ambient_light_energy = 0.55
	env.environment = e
	viewport.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	viewport.add_child(sun)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.1, 2.4)
	cam.fov = 40
	viewport.add_child(cam)
	cam.look_at_from_position(cam.position, Vector3(0, 0.38, 0))
	var pedestal := MeshLib.mesh_node(MeshLib.cylinder(0.85, 0.95, 0.12, 24), MeshLib.mat(Color(0.3, 0.28, 0.26)), Vector3(0, -0.06, 0))
	viewport.add_child(pedestal)
	pivot = Node3D.new()
	viewport.add_child(pivot)
	return cont


func open(good := "") -> void:
	setup()
	visible = true
	_rebuild_cards()
	if good != "" and GameData.goods.has(good):
		select(good)
	elif selected == "" or not GameData.goods.has(selected):
		var ids := good_ids()
		if not ids.is_empty():
			select(str(ids[0]))
	else:
		select(selected)


func close() -> void:
	visible = false


func _process(delta: float) -> void:
	if visible and pivot != null:
		pivot.rotate_y(delta * 0.7)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _on_era(i: int) -> void:
	era_filter = i
	_rebuild_cards()


func _on_available(on: bool) -> void:
	only_available = on
	_rebuild_cards()


func _set_category(cid: String) -> void:
	cat_filter = cid
	_rebuild_cards()


func _visible_ids() -> Array:
	var ids := good_ids(cat_filter, era_filter)
	if only_available:
		ids = ids.filter(func(g): return GameState.has_tech(first_tech(g)))
	return ids


func _rebuild_cards() -> void:
	if grid == null:
		return
	for cid in cat_buttons:
		cat_buttons[cid].button_pressed = cid == cat_filter
	UIKit.clear(grid)
	cards.clear()
	var ids := _visible_ids()
	for g in ids:
		var b := Button.new()
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(170, 64)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 13)
		var col: Color = CAT_COLORS.get(category_of(g), Color.WHITE)
		var sb := UIKit.panel_style(Color(0.16, 0.17, 0.2), 6, 8)
		sb.border_color = col
		sb.border_width_left = 5
		b.add_theme_stylebox_override("normal", sb)
		var sbp := sb.duplicate()
		sbp.bg_color = Color(0.32, 0.28, 0.16)
		b.add_theme_stylebox_override("pressed", sbp)
		b.add_theme_stylebox_override("hover_pressed", sbp)
		var tech := first_tech(g)
		var lock := "" if GameState.has_tech(tech) else "  (bloqueado)"
		b.text = "%s\n%s · %s%s" % [GameData.good_label(g), Fmt.money2(EconomySim.market_price(GameState, g)), str(GameData.eras.get("eras", [])[clampi(era_of(g) - 1, 0, 2)].get("short", "")), lock]
		b.tooltip_text = str(GameData.goods[g].get("description", ""))
		var gid: String = g
		b.pressed.connect(func(): select(gid))
		grid.add_child(b)
		cards[g] = b
	header.text = "[font_size=22][color=#%s]Catálogo de bienes[/color][/font_size]   %d bienes · materias primas → intermedios → productos · nivel de precios %.2f" % [
		UIKit.ACCENT.to_html(false), ids.size(), GameState.price_level()]
	if cards.has(selected):
		cards[selected].button_pressed = true


func select(good: String) -> void:
	if not GameData.goods.has(good):
		return
	selected = good
	for g in cards:
		cards[g].button_pressed = g == good
	if model_title != null:
		model_title.text = GameData.good_label(good)
	if pivot != null:
		for ch in pivot.get_children():
			pivot.remove_child(ch)
			ch.queue_free()
		var m := build_good_model(good)
		var ext := model_extent(good)
		var s := 1.25 / maxf(ext.x, ext.y * 1.25)
		m.scale = Vector3(s, s, s)
		pivot.add_child(m)
	if detail != null:
		detail.text = detail_text(good)


func _link(g: String) -> String:
	return "[url=%s]%s[/url]" % [g, GameData.good_label(g)]


## Ficha BBCode del bien (pública para pruebas).
func detail_text(good: String) -> String:
	var gs = GameState
	var g: Dictionary = GameData.goods[good]
	var cat := category_of(good)
	var col: Color = CAT_COLORS.get(cat, Color.WHITE)
	var s := "[color=#%s][b]%s[/b][/color] · %s" % [col.to_html(false), category_label(cat), GameData.era_label(era_of(good))]
	var tech := first_tech(good)
	if tech != "":
		s += " · requiere [i]%s[/i]%s" % [GameData.tech_label(tech), " ✔" if gs.has_tech(tech) else " (sin investigar)"]
	s += "\n%s\n\n" % str(g.get("description", ""))
	var price := EconomySim.market_price(gs, good)
	var f := EconomySim.good_factor(gs, good) * EconomySim.fluct(gs, good)
	var tag := "escasez" if f > 1.08 else ("exceso de oferta" if f < 0.92 else "normal")
	s += "[b]Precio de mercado:[/b] %s por unidad (%s; base %s × dificultad e inflación)\n" % [Fmt.money2(price), tag, Fmt.money2(float(g.get("base_price", 0.0)))]
	if float(g.get("import_price", 0.0)) > 0.0:
		s += "Importado: %s · " % Fmt.money2(float(g["import_price"]) * gs.price_mult())
	var tg: Dictionary = GameData.extra("trade").get("goods", {}).get(good, {})
	if not tg.is_empty():
		s += "Otros pueblos pagan ≈ %s" % Fmt.money2(float(tg.get("base", 0.0)) * gs.price_mult())
	s += "\n"
	if bool(g.get("storable", true)):
		s += "En tus almacenes: %s u.\n" % Fmt.thousands(WarehouseSim.stock(gs, good))
	# Cadena.
	var prods := producers(good)
	s += "\n[b]Se produce en:[/b]\n"
	if prods.is_empty():
		s += "  (no se produce en el pueblo: se compra afuera)\n"
	for p in prods:
		var recipe := "yacimiento de %s" % RegionSim.resource_label(str(p["deposit"])).to_lower() if str(p["deposit"]) != "" else "materia prima"
		var ins: Dictionary = p["inputs"]
		if not ins.is_empty():
			var parts := []
			for ig in ins:
				parts.append("%s %s" % [_num(float(ins[ig])), _link(ig)])
			recipe = " + ".join(parts) + " → 1"
		var t := str(p["tech"])
		s += "  • %s — nivel %d «%s»: %s%s\n" % [p["business"], int(p["level"]), p["label"], recipe,
			(" · [color=#aaa]%s[/color]" % GameData.tech_label(t)) if t != "" else ""]
	var ins_all := inputs_of(good)
	if not ins_all.is_empty():
		s += "[b]Se hace con:[/b] %s\n" % ", ".join(ins_all.map(func(x): return _link(x)))
	var cons := consumers(good)
	if not cons.is_empty():
		s += "[b]Se usa para fabricar:[/b] %s\n" % ", ".join(cons.map(func(x): return "%s (%s)" % [_link(str(x["good"])), x["business"]]))
	var shops := ShopSim.shops_selling(good)
	if not shops.is_empty():
		s += "[b]Se vende en:[/b] %s\n" % ", ".join(shops.map(func(t): return str(GameData.building_def(t).get("label", t))))
	var wants := ShopSim.wants_for(good)
	if not wants.is_empty():
		var rows := ShopSim.wants_report(gs)
		var parts := []
		for r in rows:
			if wants.has(r["id"]):
				parts.append("%s (cada ~%d días; el último mes %d compras, %d sin tienda, %d sin existencias)" % [r["label"],
					int(GameData.citizens.get("wants", {}).get(r["id"], {}).get("every_days", 30)), int(r["bought"]), int(r["no_shop"]), int(r["no_stock"])])
		s += "[b]Lo compran los vecinos:[/b] %s\n" % "; ".join(parts)
	if good == EnergySim.PRODUCT:
		var e := EnergySim.summary(gs)
		s += "\n[b]Red eléctrica del pueblo:[/b] %s\n" % ("activa" if bool(e["active"]) else "aún no (investiga Dínamo y centrales eléctricas)")
		if bool(e["active"]):
			s += "Producción %.0f/día · demanda de fábricas %.0f/día · red regional %.0f/día · hogares %.0f/día · desperdicio %.0f/día\n" % [
				float(e["supply_day"]), float(e["demand_day"]), float(e["grid_day"]), float(e["homes_day"]), float(e["wasted_day"])]
			s += "Producción perdida por apagones el último mes: %s\n" % Fmt.money(float(e["lost_value"]))
	if bool(g.get("export", false)):
		s += "\n[color=#9c9]Producto de exportación: se vende a otros pueblos (Comercio exterior).[/color]\n"
	return s


static func _num(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else ("%.2f" % v).rstrip("0").replace(".", ",")
