class_name MineTab
extends RefCounted
## Pestaña "Mina" del panel de edificio (docs/MINAS.md): reserva restante, ley, frentes
## (número y capacidad), producción estimada y botones "Agregar frente" (modo de colocación
## dentro del área del yacimiento). building_panel.gd solo llama applies() y build().

const GREEN := "#5fd35f"
const RED := "#ff6b5e"
const AMBER := "#f0c050"


static func applies(gs, b: Dictionary) -> bool:
	return gs.owned_by_player(b) and MineSim.is_mine(gs, b)


static func text(gs, b: Dictionary) -> String:
	var s := ""
	var dep := RegionSim.deposit_for(gs, b)
	var product := GameData.good_label(str(gs.building_def(b).get("product", "")))
	if dep.is_empty():
		s += "[color=%s]Sin yacimiento con reserva: la mina no produce.[/color]\n" % RED
	else:
		var frac := MineSim.reserve_frac(dep)
		var colr := GREEN if frac > 0.3 else (AMBER if frac > float(MineSim.cfg().get("deplete_warn", 0.2)) else RED)
		s += "[b]Yacimiento de %s[/b] (área de %d m de radio)\n" % [RegionSim.resource_label(str(dep["type"])).to_lower(), int(float(dep["radius"]))]
		s += "Reserva: [color=%s]%s de %s (%d %%)[/color]\n" % [colr, Fmt.thousands(float(dep["amount"])), Fmt.thousands(float(dep.get("initial", dep["amount"]))), int(round(frac * 100.0))]
		s += "Ley: %s" % MineSim.grade_text(float(dep.get("grade", 1.0)))
		var dm := MineSim.depletion_mult(dep)
		if dm < 0.999:
			s += " · [color=%s]rendimiento %d %% (queda poca reserva)[/color]" % [AMBER, int(round(dm * 100.0))]
		s += "\n"
	var m := MineSim.state(b)
	var fc := MineSim.face_count(b)
	s += "\n[b]Frentes:[/b] %d de %d posibles en este nivel\n" % [fc, MineSim.max_faces(gs, b)]
	s += "  • Centro de excavación: %d puestos\n" % MineSim.center_capacity(gs, b)
	if int(m["implicit"]) > 0:
		s += "  • %d frente(s) original(es) de la mina: %d puestos c/u\n" % [int(m["implicit"]), MineSim.face_capacity(gs, b, MineSim.basic_kind(str(b["type"])))]
	for p in MineSim.parts(b):
		var kind := str(p["kind"])
		if str(p.get("status", "")) == "obra":
			s += "  • %s: [color=%s]en obra (%d días)[/color]\n" % [MineSim.kind_label(kind), AMBER, int(ceil(float(p.get("days_left", 0))))]
		elif MineSim.is_face_kind(kind):
			s += "  • %s: %d puestos\n" % [MineSim.kind_label(kind), MineSim.face_capacity(gs, b, kind)]
		else:
			s += "  • %s: +%d %% producción\n" % [MineSim.kind_label(kind), int(round(float(MineSim.kind_def(kind).get("bonus", 0.0)) * 100.0))]
	var emp := 0
	for c in gs.employees_of(int(b["id"])):
		if c.job_kind == "empleo":
			emp += 1
	var cap := MineSim.capacity(gs, b)
	s += "Capacidad de extracción: [b]%d puestos[/b] · empleados %d" % [cap, emp]
	if emp > cap:
		s += " ([color=%s]%d sin frente donde trabajar[/color])" % [RED, emp - cap]
	s += "\n"
	if fc == 0:
		s += "[color=%s]Sin frentes solo trabaja el centro: produce poco. Agrega un frente dentro del área.[/color]\n" % AMBER
	s += "\n[b]Producción:[/b] %.1f %s/día ahora · ≈ %.1f/día con todos los puestos cubiertos\n" % [BusinessSim.expected_output(gs, b), product.to_lower(), MineSim.potential_output(gs, b)]
	if str(b.get("chain_status", "")) != "":
		s += "Estado: %s\n" % str(b["chain_status"])
	return s


static func build(gs, b: Dictionary, hud, on_change: Callable) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	var rl := UIKit.rich()
	rl.custom_minimum_size.x = 380
	rl.text = text(gs, b)
	v.add_child(rl)
	var bid := int(b["id"])
	v.add_child(UIKit.label("Agregar frente o escombrera (se coloca dentro del área teñida):", 13, UIKit.TEXT_DIM))
	for k in MineSim.available_kinds(gs, b):
		var kind := str(k["kind"])
		var reason := str(k["reason"])
		var kd := MineSim.kind_def(kind)
		var extra := "+%d puestos" % MineSim.face_capacity(gs, b, kind) if MineSim.is_face_kind(kind) else "+%d %% producción" % int(round(float(kd.get("bonus", 0.0)) * 100.0))
		var btn := UIKit.button("＋ %s · %s · %d días" % [str(kd.get("label", kind)), Fmt.money(MineSim.part_cost(gs, b, kind)), int(kd.get("build_days", 8))], func():
			if MiningVisuals.instance:
				MiningVisuals.instance.start_part_placement(bid, kind)
				if hud and hud.has_method("toast"):
					hud.toast("Coloca el %s dentro del área del yacimiento (verde = se puede)." % str(kd.get("label", kind)).to_lower(), "info")
			elif hud and hud.has_method("toast"):
				hud.toast("Abre el mapa para colocar el frente.", "jugador"))
		btn.disabled = reason != ""
		btn.tooltip_text = str(kd.get("description", ""))
		v.add_child(btn)
		var why := UIKit.label("   %s%s" % [extra, " · " + reason if reason != "" else ""], 12, UIKit.TEXT_DIM)
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		why.custom_minimum_size.x = 380
		v.add_child(why)
	for p in MineSim.parts(b):
		var pid := int(p["id"])
		v.add_child(UIKit.button("Demoler %s #%d" % [str(MineSim.kind_def(str(p["kind"])).get("short", p["kind"])), pid], func():
			MineSim.remove_part(gs, gs.get_building(bid), pid)
			on_change.call()))
	var note := UIKit.label("Producción ≈ mín(empleados, puestos de los frentes) × productividad × ley del yacimiento. Con poca reserva (menos del %d %%) rinde menos; al agotarse la mina cierra." % int(round(float(MineSim.cfg().get("decline_start", 0.3)) * 100.0)), 12, UIKit.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 380
	v.add_child(note)
	return v
