class_name BusTab
extends RefCounted
## Pestaña "Buses" del panel de edificio de una Empresa de buses (docs/TRANSPORTE.md).


static func applies(gs, b: Dictionary) -> bool:
	return gs.owned_by_player(b) and TransitSim.is_depot_type(gs.building_def(b))


static func build(gs, b: Dictionary, hud, on_change: Callable) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	if str(b.get("status", "")) != "activo":
		v.add_child(UIKit.label("En obra: aún no opera.", 12, UIKit.TEXT_DIM))
	v.add_child(TransitPanel.depot_box(gs, b, hud, on_change))
	var n := 0
	for r in TransitSim.routes(gs):
		if int(r["depot"]) == int(b["id"]):
			n += 1
	var note := UIKit.label("%d ruta(s). Paraderos y rutas manuales: panel «Transporte público»." % n, 12, UIKit.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	return v
