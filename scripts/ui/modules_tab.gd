class_name ModulesTab
extends RefCounted
## Secciones de módulos de la pestaña «Mejorar» del panel de edificio (docs/MODULOS.md):
## «Almacén» y «Parqueadero y flota», cada una con su nivel actual, el siguiente nivel con sus
## beneficios, costo, tiempo y mantenimiento, los requisitos (tecnología y nivel del edificio) y el
## botón Mejorar. building_panel.gd solo llama add_sections().

const OK := "#5fd35f"
const BAD := "#ff6b5e"


static func add_sections(parent: VBoxContainer, gs, b: Dictionary, on_change: Callable, msg: Callable) -> void:
	for m in ModulesSim.module_ids():
		var mid := str(m)
		if not ModulesSim.applies(gs, b, mid):
			continue
		var body := UIKit.section(parent, ModulesSim.label(mid), "", true, "modulo_" + mid)
		body.name = "Modulo_" + mid
		_build(body, gs, b, mid, on_change, msg)


static func _build(v: VBoxContainer, gs, b: Dictionary, m: String, on_change: Callable, msg: Callable) -> void:
	var bid := int(b["id"])
	var lvl := ModulesSim.level(b, m)
	var t := ""
	if lvl > 0:
		t += "Nivel actual: [b]%d — %s[/b]\n%s\n" % [lvl, str(ModulesSim.mlevel(m, lvl).get("label", "")), ModulesSim.benefits_text(gs, b, m, lvl)]
	else:
		t += "Nivel actual: [color=#aaa]sin módulo[/color]\n"
	if m == ModulesSim.ALMACEN and WarehouseSim.is_warehouse_building(gs, b):
		t += "Ocupado: %s / %s\n" % [Fmt.thousands(WarehouseSim.used_in(gs, bid)), Fmt.thousands(WarehouseSim.capacity_of(gs, bid))]
	var w := ModulesSim.work(b)
	if not w.is_empty() and str(w.get("module", "")) == m:
		t += "[color=#e9b949]En obra: nivel %d · faltan %d días (el negocio sigue facturando)[/color]\n" % [int(w["target"]), ModulesSim.days_left(gs, b)]
	var next := lvl + 1
	var nd := ModulesSim.mlevel(m, next)
	if nd.is_empty():
		t += "[color=#aaa]Nivel máximo del módulo.[/color]\n"
		var rl0 := UIKit.rich()
		rl0.text = t
		v.add_child(rl0)
		return
	var c := ModulesSim.cost(gs, m, next)
	t += "\n[b]Siguiente: nivel %d — %s[/b]\n%s\n" % [next, str(nd.get("label", "")), ModulesSim.benefits_text(gs, b, m, next)]
	t += "Costo: %s (incluye %s de materiales que faltan) · obra %d días · mantenimiento %s/mes\n" % [
		Fmt.money(float(c["total"])), Fmt.money(float(c["import_cost"])), int(c["days"]), Fmt.money(float(nd.get("upkeep", 0.0)) * gs.price_mult())]
	var tech := str(nd.get("tech", ""))
	var need := ModulesSim.min_building_level(b, m, next)
	t += "Requisitos: %s · %s\n" % [
		"[color=%s]%s %s[/color]" % [OK if gs.has_tech(tech) else BAD, "✔" if gs.has_tech(tech) else "✘", "sin investigación" if tech == "" else GameData.tech_label(tech)],
		"[color=%s]%s edificio nivel %d[/color]" % [OK if int(b["level"]) >= need else BAD, "✔" if int(b["level"]) >= need else "✘", need]]
	var reason := ModulesSim.block_reason(gs, b, m)
	if reason != "":
		t += "[color=#e66]%s[/color]\n" % reason
	var rl := UIKit.rich()
	rl.text = t
	v.add_child(rl)
	var btn := UIKit.button("Mejorar %s" % ModulesSim.label(m).to_lower(), func():
		msg.call(ModulesSim.start(GameState, GameState.get_building(bid), m))
		on_change.call())
	btn.name = "Mejorar_" + m
	btn.disabled = reason != ""
	btn.tooltip_text = reason
	v.add_child(btn)
