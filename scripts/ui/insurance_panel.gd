class_name InsurancePanel
extends VBoxContainer
## Seguros (InsuranceSim): tus pólizas por edificio con la aseguradora externa, seguro de carga y
## la gestión de tu propia aseguradora (tarifa, clientes, primas y siniestros).

signal message(text: String, category: String)

var head: RichTextLabel
var own_box: VBoxContainer
var list: VBoxContainer
var log_text: RichTextLabel


func setup() -> void:
	add_theme_constant_override("separation", 8)
	head = UIKit.rich()
	add_child(head)
	own_box = VBoxContainer.new()
	own_box.add_theme_constant_override("separation", 6)
	add_child(own_box)
	add_child(HSeparator.new())
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	add_child(list)
	add_child(HSeparator.new())
	add_child(UIKit.label("Siniestros recientes", 15, UIKit.ACCENT))
	log_text = UIKit.rich()
	add_child(log_text)


func refresh() -> void:
	var gs := GameState
	if head == null or not GlobalEconSim.ready(gs):
		return
	UIKit.clear(own_box)
	UIKit.clear(list)
	var s := InsuranceSim.st(gs)
	var lm: Dictionary = s.get("last_month", {})
	var txt := "[b]Seguros[/b] con %s (caja %s)\n" % [InsuranceSim.external_label(), Fmt.money(InsuranceSim.external_cash(gs))]
	txt += "Primas este mes: [b]%s[/b] · Mes anterior: primas %s, indemnizaciones %s\n" % [Fmt.money2(InsuranceSim.total_premiums(gs)),
		Fmt.money(float(lm.get("premiums", 0.0))), Fmt.money(float(lm.get("claims", 0.0)))]
	for t in InsuranceSim.TYPES:
		var td := InsuranceSim.type_def(t)
		txt += "[color=#aaa]• %s: %s Deducible %d %%.[/color]\n" % [InsuranceSim.type_label(t), str(td.get("description", "")), int(float(td.get("deductible", 0.1)) * 100.0)]
	head.text = txt
	var cargo := CheckBox.new()
	cargo.text = "Seguro de carga del comercio exterior (%s/mes)" % Fmt.money2(InsuranceSim.cargo_premium(gs))
	cargo.button_pressed = bool(s.get("cargo", false))
	cargo.toggled.connect(func(on): InsuranceSim.set_cargo(GameState, on))
	own_box.add_child(cargo)
	for b in gs.player_buildings():
		if InsuranceSim.is_insurer(gs, b):
			own_box.add_child(_insurer_row(gs, b))
	for b in gs.player_buildings():
		if InsuranceSim.eligible(gs, b, "incendio"):
			list.add_child(_building_row(gs, b))
	var l: Array = s.get("log", [])
	var out := ""
	for i in range(l.size() - 1, maxi(-1, l.size() - 11), -1):
		out += "[color=#aaa]%s[/color] %s\n" % [l[i]["date"], l[i]["text"]]
	log_text.text = out if out != "" else "[color=#aaa]Sin siniestros.[/color]"


func _building_row(gs, b: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var name := UIKit.label(gs.building_label(b), 14)
	name.custom_minimum_size.x = 170
	name.clip_text = true
	row.add_child(name)
	var bid := int(b["id"])
	for t in ["incendio", "robo", "cosecha"]:
		if not InsuranceSim.eligible(gs, b, t):
			continue
		var cb := CheckBox.new()
		cb.text = "%s %s" % [InsuranceSim.type_label(t), Fmt.money2(InsuranceSim.premium(gs, b, t))]
		cb.button_pressed = InsuranceSim.has_policy(gs, b, t)
		var tt: String = t
		cb.toggled.connect(func(on):
			var err := InsuranceSim.set_policy(GameState, GameState.get_building(bid), tt, on)
			if err != "":
				message.emit(err, "jugador"))
		row.add_child(cb)
	return row


func _insurer_row(gs, b: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.BG_LIGHT, 6, 6))
	var v := VBoxContainer.new()
	panel.add_child(v)
	var o := InsuranceSim.own_state(gs, b)
	var last: Dictionary = o.get("last", {})
	var tot: Dictionary = o.get("total", {})
	var t := UIKit.rich()
	t.text = "[b]Tu aseguradora: %s[/b]\nClientes %d de %d posibles · %d %% de los interesados compra con tu tarifa\nMes anterior: primas %s · siniestros %s · Total: primas %s, siniestros %s" % [
		gs.building_label(b), InsuranceSim.own_clients(gs, b), InsuranceSim.capacity(gs, b), int(InsuranceSim.demand_share(float(o.get("rate", 1.2))) * 100.0),
		Fmt.money(float(last.get("premiums", 0.0))), Fmt.money(float(last.get("claims", 0.0))), Fmt.money(float(tot.get("premiums", 0.0))), Fmt.money(float(tot.get("claims", 0.0)))]
	v.add_child(t)
	var row := HBoxContainer.new()
	row.add_child(UIKit.label("Tarifa (× prima justa):", 14, UIKit.TEXT_DIM))
	var bid := int(b["id"])
	var oc := InsuranceSim.own_cfg()
	var on_rate := func(val): InsuranceSim.set_rate(GameState, GameState.get_building(bid), float(val))
	row.add_child(UIKit.spin(float(oc.get("min_rate", 0.5)), float(oc.get("max_rate", 2.5)), 0.05, float(o.get("rate", 1.2)), on_rate, 90))
	v.add_child(row)
	return panel
