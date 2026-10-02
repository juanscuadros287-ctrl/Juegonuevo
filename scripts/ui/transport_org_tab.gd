class_name TransportOrgTab
extends RefCounted
## Pestaña "Organización" de un edificio de transporte (división interna o empresa aparte) y la sección de
## Finanzas "Transporte y consolidado del grupo". Lógica en TransportDivSim.


static func applies(gs, b: Dictionary) -> bool:
	return TransportDivSim.is_transport(gs, b)


static func build(gs, b: Dictionary, on_change: Callable) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	var bid := int(b["id"])
	var org := TransportDivSim.org(b)
	v.add_child(UIKit.label("¿Cómo se organiza este transporte?", 14, UIKit.ACCENT))
	var opt := OptionButton.new()
	opt.add_item("División interna (ministerio de transporte de tu empresa)")
	opt.add_item("Empresa de transporte aparte (razón social propia)")
	opt.selected = 1 if org == "empresa" else 0
	v.add_child(opt)
	var name_edit := LineEdit.new()
	name_edit.text = TransportDivSim.company_name(gs, b)
	name_edit.placeholder_text = "Razón social"
	name_edit.visible = org == "empresa"
	v.add_child(name_edit)
	var legal := OptionButton.new()
	for lt in GameData.sorted_ids(GameData.legal_types):
		legal.add_item(str(GameData.legal_types[lt].get("label", lt)))
		legal.set_item_metadata(legal.item_count - 1, str(lt))
		if str(lt) == str(b.get("legal", "sas")):
			legal.selected = legal.item_count - 1
	legal.visible = org == "empresa"
	v.add_child(legal)
	opt.item_selected.connect(func(i):
		name_edit.visible = i == 1
		legal.visible = i == 1)
	var rate_row := HBoxContainer.new()
	rate_row.add_child(UIKit.label("Tarifa por unidad·km (0 = de mercado %s):" % Fmt.money2(TransportDivSim.market_rate(gs)), 12, UIKit.TEXT_DIM))
	var rate := UIKit.spin(0.0, 100.0, 0.001, float(b.get("freight_rate", 0.0)), func(_v): pass, 100)
	rate_row.add_child(rate)
	v.add_child(rate_row)
	v.add_child(UIKit.primary(UIKit.button("Aplicar", func():
		var B: Dictionary = GameState.get_building(bid)
		TransportDivSim.set_org(GameState, B, "empresa" if opt.selected == 1 else "interna", name_edit.text, str(legal.get_item_metadata(maxi(0, legal.selected))))
		TransportDivSim.set_rate(B, rate.value)
		on_change.call())))
	var note := UIKit.label("Interna: sus costos se reparten cada mes entre los negocios que usaron sus envíos (según unidades·km) y aparecen en el costeo de cada fábrica. "
		+ "Empresa aparte: cobra un flete a tus negocios por cada envío (traspaso dentro del grupo, sin IVA) y, con capacidad ociosa, a empresas NPC; tiene sus propios ingresos y ganancias.", 12, UIKit.TEXT_FAINT)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 320
	v.add_child(note)
	# Resultado del mes anterior
	var inc := TransportDivSim.income(b)
	var cost := TransportDivSim.expenses(b)
	var r := UIKit.rich()
	r.text = "[b]Mes anterior[/b] · ingresos %s (fletes a tus negocios %s, a clientes NPC %s) · costos %s · resultado [color=%s]%s[/color]" % [
		Fmt.money(inc), Fmt.money(float(b.get("fletes_internos_last", 0.0))), Fmt.money(float(b.get("fletes_npc_last", 0.0))), Fmt.money(cost),
		"#6c6" if inc - cost >= 0.0 else "#e66", Fmt.money(inc - cost)]
	v.add_child(r)
	if org == "interna":
		var lines := []
		for k in TransportDivSim.st(gs)["alloc"]:
			var a: Dictionary = TransportDivSim.st(gs)["alloc"][k]
			var part := float(a.get("by", {}).get(str(bid), 0.0))
			if part > 0.0:
				lines.append("%s: %s" % [gs.building_label(gs.get_building(int(k))), Fmt.money(part)])
		v.add_child(UIKit.label("Costo asignado: " + (", ".join(lines) if not lines.is_empty() else "sin envíos el mes pasado (queda en la división)"), 12, UIKit.TEXT_DIM))
	return v


## Sección de Finanzas: cada edificio de transporte como línea propia y el consolidado sin contar dos veces.
static func finance_section(gs, body: VBoxContainer) -> void:
	var sec := UIKit.section(body, "Transporte y consolidado del grupo", "logistics", true, "fin_transport")
	var rows := TransportDivSim.finance_rows(gs)
	if rows.is_empty():
		sec.add_child(UIKit.label("Sin edificios de transporte. Cuando los tengas, elige en su panel si son división interna o empresa aparte.", 12, UIKit.TEXT_DIM))
	else:
		var dt := DataTable.new()
		for rw in rows:
			rw["res_col"] = UIKit.sign_color(float(rw["result"]))
		dt.set_data([{"title": "Transporte", "key": "name", "w": 1.6}, {"title": "Forma", "key": "org_label", "w": 1.1},
			{"title": "Ingresos", "key": "income", "w": 0.9, "fmt": "money"}, {"title": "Internos", "key": "internal", "w": 0.9, "fmt": "money"},
			{"title": "Costos", "key": "costs", "w": 0.9, "fmt": "money"}, {"title": "Resultado", "key": "result", "w": 0.9, "fmt": "money", "color_key": "res_col"}], rows, 6)
		sec.add_child(dt)
	var c := TransportDivSim.consolidated(gs)
	var r := UIKit.rich()
	r.text = "[b]Consolidado del grupo (mes anterior)[/b]: ingresos %s · gastos %s · resultado [color=%s]%s[/color]\n[color=#8a8f99]Se eliminan %s de fletes entre tus empresas (cuentan como venta de la transportadora y gasto del negocio, pero el dinero no sale del grupo).[/color]" % [
		Fmt.money(float(c["income"])), Fmt.money(float(c["expenses"])), "#6c6" if float(c["result"]) >= 0.0 else "#e66", Fmt.money(float(c["result"])), Fmt.money(float(c["internal"]))]
	sec.add_child(r)
