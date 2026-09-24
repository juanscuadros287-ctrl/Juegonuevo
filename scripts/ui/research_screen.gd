class_name ResearchScreen
extends Control
## Árbol de investigación visual: columnas por época, filas por rama, líneas de prerrequisitos.

const NODE_W := 168.0
const NODE_H := 50.0
const COL_W := 196.0
const ROW_H := 74.0
const ERA_GAP := 40.0
const TOP := 34.0
const LEFT := 150.0

var canvas: Control
var header: RichTextLabel
var detail: RichTextLabel
var detail_buttons: HBoxContainer
var progress: ProgressBar
var selected := ""
var positions := {}       # id -> Vector2 (esquina)
var buttons := {}         # id -> Button
var era_x := {}           # era -> [x0, x1]


func setup() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
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
	add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	header = UIKit.rich()
	header.fit_content = true
	head.add_child(header)
	progress = ProgressBar.new()
	progress.custom_minimum_size = Vector2(260, 22)
	head.add_child(progress)
	head.add_child(UIKit.button("Cerrar (Esc)", func(): close(), 120))
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(sc)
	canvas = Control.new()
	canvas.draw.connect(_draw_canvas)
	sc.add_child(canvas)
	var side := PanelContainer.new()
	side.custom_minimum_size = Vector2(360, 0)
	body.add_child(side)
	var sv := VBoxContainer.new()
	side.add_child(sv)
	detail = UIKit.rich()
	sv.add_child(detail)
	detail_buttons = HBoxContainer.new()
	sv.add_child(detail_buttons)
	_layout()


func _layout() -> void:
	var ids := GameData.tech_ids()
	var branches: Array = GameData.eras.get("branches", [])
	var row_of := {}
	for i in range(branches.size()):
		row_of[branches[i][0]] = i
	# Profundidad dentro de la época (cadena de prerrequisitos de la misma época).
	var depth := {}
	for _pass in range(8):
		for id in ids:
			var t := TechSim.tech(id)
			var d := 0
			for r in t.get("requires", []):
				if int(TechSim.tech(r).get("era", 1)) == int(t.get("era", 1)):
					d = maxi(d, int(depth.get(r, 0)) + 1)
			depth[id] = d
	var eras: Array = GameData.eras.get("eras", [])
	var x := LEFT
	for e in eras:
		var eid := int(e["id"])
		# Ubicar cada tecnología en su fila (rama); si la celda está ocupada, pasa a la siguiente columna.
		var occupied := {}
		var max_col := 0
		var era_ids := ids.filter(func(i): return int(TechSim.tech(i).get("era", 1)) == eid)
		era_ids.sort_custom(func(a, b): return int(depth[a]) < int(depth[b]))
		var col_of := {}
		for id in era_ids:
			var t := TechSim.tech(id)
			var row := int(row_of.get(str(t.get("branch", "")), 0))
			var col := int(depth[id])
			for r in t.get("requires", []):
				if col_of.has(r):
					col = maxi(col, int(col_of[r]) + 1)
			while occupied.has("%d_%d" % [row, col]):
				col += 1
			occupied["%d_%d" % [row, col]] = true
			col_of[id] = col
			max_col = maxi(max_col, col)
			positions[id] = Vector2(x + col * COL_W, TOP + row * ROW_H)
		era_x[eid] = [x, x + (max_col + 1) * COL_W]
		x += (max_col + 1) * COL_W + ERA_GAP
	canvas.custom_minimum_size = Vector2(x + 20, TOP + branches.size() * ROW_H + 40)
	for id in ids:
		var b := Button.new()
		b.position = positions[id]
		b.size = Vector2(NODE_W, NODE_H)
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 12)
		var tid: String = id
		b.pressed.connect(func(): _select(tid))
		canvas.add_child(b)
		buttons[id] = b


func open() -> void:
	visible = true
	refresh()


func close() -> void:
	visible = false


func refresh() -> void:
	var gs := GameState
	var r: Dictionary = gs.research
	var cur := str(r.get("current", ""))
	var labs := 0
	for b in gs.player_buildings("negocio"):
		if str(gs.building_def(b).get("product", "")) == "investigacion":
			labs += 1
	header.text = "[font_size=22][color=#edc259]Investigación[/color][/font_size]   %s · Laboratorios: %d · Puntos/día: %.1f · Proyecto: [b]%s[/b]%s" % [
		GameData.era_label(gs.era()), labs, float(r.get("points_yesterday", 0.0)),
		GameData.tech_label(cur) if cur != "" else "ninguno", "   Cola: %d" % r.get("queue", []).size() if not r.get("queue", []).is_empty() else ""]
	progress.max_value = TechSim.cost(cur) if cur != "" else 1.0
	progress.value = float(r.get("progress", 0.0)) if cur != "" else 0.0
	for id in buttons:
		var b: Button = buttons[id]
		var t := TechSim.tech(id)
		var state := "done" if gs.techs.has(id) else ("current" if id == cur else ("ok" if TechSim.block_reason(gs, id) == "" else "locked"))
		var col: Color = {"done": Color(0.25, 0.5, 0.3), "current": Color(0.25, 0.4, 0.7), "ok": Color(0.55, 0.45, 0.18), "locked": Color(0.2, 0.2, 0.23)}[state]
		b.add_theme_stylebox_override("normal", UIKit.panel_style(col, 6, 4))
		b.add_theme_stylebox_override("hover", UIKit.panel_style(col.lightened(0.15), 6, 4))
		var mark: String = {"done": "✔ ", "current": "▶ ", "ok": "", "locked": ""}[state]
		var qpos: int = r.get("queue", []).find(id)
		b.text = "%s%s\n%d pts%s" % [mark, t.get("label", id), int(t.get("cost", 0)), "  · cola %d" % (qpos + 1) if qpos >= 0 else ""]
		b.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95) if state != "locked" else Color(0.6, 0.6, 0.6))
	canvas.queue_redraw()
	if selected != "":
		_select(selected)
	else:
		detail.text = "[color=#aaa]Haz clic en una tecnología para ver sus efectos.\n\n🟩 investigada · 🟦 en curso · 🟨 disponible · ⬛ bloqueada\n\nLos laboratorios producen los puntos. Especialízalos en una rama para avanzar 50% más rápido en ella.[/color]"


func _select(id: String) -> void:
	selected = id
	var gs := GameState
	var t := TechSim.tech(id)
	var s := "[font_size=19][color=#edc259]%s[/color][/font_size]\n" % t.get("label", id)
	s += "%s · %s · %d puntos\n\n" % [GameData.era_label(int(t.get("era", 1))), GameData.branch_label(str(t.get("branch", ""))), int(t.get("cost", 0))]
	s += "%s\n\n" % t.get("description", "")
	var eff := TechSim.effects_text(id)
	if not eff.is_empty():
		s += "[b]Efectos[/b]\n" + "\n".join(eff.map(func(e): return "• " + e)) + "\n"
	var unl := TechSim.unlocks_of(id)
	if not unl.is_empty():
		s += "[b]Desbloquea[/b]\n" + "\n".join(unl.map(func(u): return "• " + u)) + "\n"
	if t.has("future"):
		s += "[color=#999]• %s[/color]\n" % t["future"]
	var req: Array = t.get("requires", [])
	if not req.is_empty():
		s += "\n[b]Requiere[/b]: %s\n" % ", ".join(req.map(func(r): return ("✔ " if gs.techs.has(r) else "✖ ") + GameData.tech_label(r)))
	var reason := TechSim.block_reason(gs, id)
	if gs.techs.has(id):
		s += "\n[color=#6c6]Ya investigada.[/color]"
	elif reason != "":
		s += "\n[color=#e88]%s[/color]" % reason
	var pts := float(gs.research.get("points_yesterday", 0.0))
	if pts > 0.0 and not gs.techs.has(id):
		s += "\n[color=#aaa]Tiempo estimado al ritmo actual: %d días[/color]" % int(ceil(TechSim.cost(id) / pts))
	detail.text = s
	UIKit.clear(detail_buttons)
	if not gs.techs.has(id):
		var b1 := UIKit.button("Investigar ahora", func():
			var err := TechSim.set_current(GameState, id)
			if err != "":
				GameState.notify(err, "jugador")
			refresh())
		b1.disabled = reason != ""
		detail_buttons.add_child(b1)
		detail_buttons.add_child(UIKit.button("Añadir a la cola", func():
			_enqueue_with_prereqs(id)
			refresh()))


## Encola los prerrequisitos que falten y luego la tecnología.
func _enqueue_with_prereqs(id: String) -> void:
	for r in TechSim.tech(id).get("requires", []):
		if not GameState.techs.has(r):
			_enqueue_with_prereqs(r)
	TechSim.enqueue(GameState, id)


func _draw_canvas() -> void:
	var font := get_theme_default_font()
	var branches: Array = GameData.eras.get("branches", [])
	for i in range(branches.size()):
		var y := TOP + i * ROW_H
		canvas.draw_rect(Rect2(Vector2(0, y - 6), Vector2(canvas.custom_minimum_size.x, ROW_H - 4)), Color(1, 1, 1, 0.025 if i % 2 == 0 else 0.0))
		canvas.draw_string(font, Vector2(8, y + 28), str(branches[i][1]), HORIZONTAL_ALIGNMENT_LEFT, LEFT - 16, 13, UIKit.TEXT_DIM)
	for eid in era_x:
		var xs: Array = era_x[eid]
		var active := GameState.era() >= int(eid)
		canvas.draw_string(font, Vector2(xs[0], 20), GameData.era_label(int(eid)), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UIKit.ACCENT if active else Color(0.5, 0.5, 0.5))
		canvas.draw_line(Vector2(xs[1] + ERA_GAP * 0.5, 0), Vector2(xs[1] + ERA_GAP * 0.5, canvas.custom_minimum_size.y), Color(1, 1, 1, 0.15), 2.0)
	for id in positions:
		for r in TechSim.tech(id).get("requires", []):
			if not positions.has(r):
				continue
			var a: Vector2 = positions[r] + Vector2(NODE_W, NODE_H * 0.5)
			var b: Vector2 = positions[id] + Vector2(0, NODE_H * 0.5)
			var col := Color(0.4, 0.75, 0.45, 0.8) if GameState.techs.has(r) else Color(0.6, 0.6, 0.6, 0.35)
			var mid := (a.x + b.x) * 0.5
			canvas.draw_polyline(PackedVector2Array([a, Vector2(mid, a.y), Vector2(mid, b.y), b]), col, 2.0, true)
