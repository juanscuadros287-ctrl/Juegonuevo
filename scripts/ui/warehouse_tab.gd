class_name WarehouseTab
extends RefCounted
## Pestaña "Almacén" del panel de edificio (almacenes individuales):
## - en un almacén: stock, capacidad y los negocios vinculados que abastece;
## - en una fábrica, taller, mina o campo: su almacén vinculado (verde) o ninguno (rojo),
##   su receta, lo que espera en el sitio y acciones rápidas.
## building_panel.gd solo llama applies(), build() y summary_line().

const GREEN := "#5fd35f"
const RED := "#ff6b5e"


static func applies(gs, b: Dictionary) -> bool:
	return WarehouseSim.is_warehouse_building(gs, b) or WarehouseSim.is_linkable(gs, b)


## Línea para el resumen del edificio ("" si no aplica).
static func summary_line(gs, b: Dictionary) -> String:
	if WarehouseSim.is_warehouse_building(gs, b):
		var wid := int(b["id"])
		return "Almacén: %s / %s ocupado · abastece a [color=%s]%d negocio(s)[/color]\n" % [
			Fmt.thousands(WarehouseSim.used_in(gs, wid)), Fmt.thousands(WarehouseSim.capacity_of(gs, wid)), GREEN, WarehouseSim.linked_to(gs, wid).size()]
	if WarehouseSim.is_linkable(gs, b):
		var wid := WarehouseSim.warehouse_for(gs, b)
		if wid >= 0:
			return "Almacén vinculado: [color=%s]%s ✔[/color]\n" % [GREEN, WarehouseSim.label_of(gs, wid)]
		return "Almacén vinculado: [color=%s]ninguno[/color] (la producción queda en el sitio)\n" % RED
	return ""


static func build(gs, b: Dictionary, hud) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	var rl := UIKit.rich()
	rl.custom_minimum_size.x = 380
	v.add_child(rl)
	if WarehouseSim.is_warehouse_building(gs, b):
		rl.text = warehouse_text(gs, int(b["id"]))
		_add_links(v, gs, int(b["id"]), hud)
	else:
		rl.text = factory_text(gs, b)
		var wid := WarehouseSim.warehouse_for(gs, b)
		if wid > 0:
			v.add_child(UIKit.button("Abrir el almacén vinculado", func(): hud.open_building(wid)))
		elif wid < 0:
			v.add_child(UIKit.button("Construir un almacén al lado", func(): EventBus.build_mode_requested.emit("almacen", "normal")))
		v.add_child(UIKit.button("Rutas de transporte (Logística)", func(): hud._show_dock("logistics")))
	var note := UIKit.label("Una fábrica, taller, mina o campo queda vinculado (en verde) al almacén cuyo borde esté a menos de %d m del suyo. Toma los insumos y guarda lo producido SOLO en ese almacén; si se llena, la producción se detiene. Sin almacén al lado, lo producido queda en el sitio y hay que llevarlo con rutas." % int(WarehouseSim.link_distance()), 12, UIKit.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 380
	v.add_child(note)
	return v


static func _add_links(v: VBoxContainer, gs, wid: int, hud) -> void:
	for lb in WarehouseSim.linked_to(gs, wid):
		var id := int(lb["id"])
		var row := HBoxContainer.new()
		var l := UIKit.label("● %s — %s" % [gs.building_label(lb), LogisticsSim.recipe_text(str(lb["type"]), int(lb["level"]))], 13, Color(0.45, 0.85, 0.45))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		row.add_child(l)
		row.add_child(UIKit.button("Abrir", func(): hud.open_building(id), 60))
		v.add_child(row)


static func warehouse_text(gs, wid: int) -> String:
	var cap := WarehouseSim.capacity_of(gs, wid)
	var used := WarehouseSim.used_in(gs, wid)
	var pct := used / maxf(1.0, cap)
	var col := GREEN if pct < 0.8 else ("#e9b949" if pct < 0.98 else RED)
	var s := "[b]%s[/b]\nOcupado: [color=%s][b]%s / %s[/b] (%d%%)[/color] · valor %s\n" % [WarehouseSim.label_of(gs, wid), col,
		Fmt.thousands(used), Fmt.thousands(cap), int(pct * 100.0), Fmt.money(WarehouseSim.value_in(gs, wid))]
	s += _bar(pct, col) + "\n"
	var st := WarehouseSim.stock_all_in(gs, wid)
	if st.is_empty():
		s += "[color=#aaa]Vacío.[/color]\n"
	var keys := st.keys()
	keys.sort_custom(func(a, c): return float(st[a]) > float(st[c]))
	for g in keys:
		s += "• %s: %s\n" % [GameData.good_label(str(g)), Fmt.thousands(float(st[g]))]
	var linked := WarehouseSim.linked_to(gs, wid)
	s += "\n[b]Abastece a[/b] (%d): " % linked.size()
	if linked.is_empty():
		s += "[color=#aaa]ningún negocio al lado. Construye fábricas, talleres, minas o campos a menos de %d m.[/color]\n" % int(WarehouseSim.link_distance())
	else:
		s += "[color=%s]%s[/color]\n" % [GREEN, ", ".join(linked.map(func(lb): return gs.building_label(lb)))]
	return s


static func factory_text(gs, b: Dictionary) -> String:
	var wid := WarehouseSim.warehouse_for(gs, b)
	var s := ""
	if wid >= 0:
		s += "Almacén vinculado: [color=%s][b]%s ✔[/b][/color]\n" % [GREEN, WarehouseSim.label_of(gs, wid)]
		s += "Espacio libre en ese almacén: %s de %s\n" % [Fmt.thousands(WarehouseSim.free_in(gs, wid)), Fmt.thousands(WarehouseSim.capacity_of(gs, wid))]
	else:
		s += "Almacén vinculado: [color=%s][b]ninguno[/b][/color]\n" % RED
		s += "[color=#aaa]Lo producido queda en el sitio (máx. %s) y los insumos deben llegar aquí con rutas.[/color]\n" % Fmt.thousands(LogisticsSim.local_capacity(gs, b))
	s += "Receta: %s\n" % LogisticsSim.recipe_text(str(b["type"]), int(b["level"]))
	var inv: Dictionary = b.get("inventory", {})
	var parts := []
	for g in inv:
		if float(inv[g]) > 0.05:
			parts.append("%s %s" % [Fmt.thousands(float(inv[g])), GameData.good_label(str(g)).to_lower()])
	if not parts.is_empty():
		s += "En el sitio: %s\n" % ", ".join(parts)
	s += "Producción hoy: %.1f\n" % float(b.get("produced_today", 0.0))
	var st := str(b.get("chain_status", ""))
	if st != "":
		s += "[color=#e9b949]⚠ %s[/color]\n" % st
	return s


static func _bar(pct: float, col: String) -> String:
	var n := 24
	var full := clampi(int(round(pct * n)), 0, n)
	return "[color=%s]%s[/color][color=#555]%s[/color]" % [col, "█".repeat(full), "█".repeat(n - full)]
