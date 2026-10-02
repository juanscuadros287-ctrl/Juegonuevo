class_name CostsTab
extends RefCounted
## Pestaña "Costos" del panel de un negocio productor: costo por unidad del mes anterior desglosado (insumos,
## sueldos, mantenimiento y energía, transporte, depreciación, impuestos) con dona, precio de venta promedio,
## margen por unidad, punto de equilibrio, historial y la calculadora a plantilla completa. Lógica en CostSim.


static func applies(gs, b: Dictionary) -> bool:
	return gs.owned_by_player(b) and CostSim.is_producer_def(gs.building_def(b))


static func build(gs, b: Dictionary) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	var c: Dictionary = b.get("costing", {})
	var product := GameData.good_label(CostSim.product_of(gs.building_def(b)))
	if c.is_empty() or float(c.get("units", 0.0)) <= 0.0:
		v.add_child(_note("El costo por unidad se calcula al cerrar cada mes con lo que produjo y gastó %s." % gs.building_label(b)))
	else:
		var units := float(c["units"])
		var head := UIKit.rich()
		var margin := float(c["margin"])
		var be := float(c["break_even"])
		head.text = "[b]Costo por unidad de %s: %s[/b] (%s unidades el mes pasado, costo total %s)\nPrecio de venta promedio %s · margen por unidad [color=%s]%s (%s)[/color]\nPunto de equilibrio: %s" % [
			product.to_lower(), Fmt.money2(float(c["unit_cost"])), Fmt.thousands(units), Fmt.money(float(c["total"])), Fmt.money2(float(c["price"])),
			"#6c6" if margin >= 0.0 else "#e66", Fmt.money2(margin), Fmt.pct_1(float(c["margin_pct"]) * 100.0),
			("%s unidades/mes (fijos %s; variable %s por unidad)" % [Fmt.thousands(be), Fmt.money(float(c["fixed"])), Fmt.money2(float(c["var_unit"]))]) if be != INF else "no se alcanza: el precio no cubre el costo variable"]
		v.add_child(head)
		var slices := []
		var rows := []
		var i := 0
		for k in CostSim.PARTS:
			var amt := float(c["parts"][k])
			slices.append({"label": CostSim.PART_LABELS[k], "value": amt, "color": UIKit.SERIES[i % UIKit.SERIES.size()]})
			rows.append({"label": CostSim.PART_LABELS[k], "month": amt, "unit": float(c["per_unit"][k]), "share": amt / maxf(0.0001, float(c["total"]))})
			i += 1
		var donut := DonutChart.new()
		donut.set_data("Costo por unidad: de qué se compone", slices, Fmt.money2(float(c["unit_cost"])), "por unidad")
		v.add_child(donut)
		var dt := DataTable.new()
		dt.set_data([{"title": "Concepto", "key": "label", "w": 1.6}, {"title": "Mes", "key": "month", "w": 1.0, "fmt": "money"},
			{"title": "Por unidad", "key": "unit", "w": 1.0, "fmt": "money2"}, {"title": "Parte", "key": "share", "w": 1.0, "fmt": "bar", "max": 1.0}], rows, 8)
		v.add_child(dt)
		var notes := []
		if float(c.get("alloc", 0.0)) > 0.0:
			notes.append("Transporte asignado por tu división de transporte: %s." % Fmt.money(float(c["alloc"])))
		if float(c.get("energy", 0.0)) > 0.0:
			notes.append("Electricidad y otros consumos: %s." % Fmt.money(float(c["energy"])))
		notes.append("Insumos de la receta valorados a tu costo si los produces tú; si no, a precio de mercado.")
		v.add_child(_note(" ".join(notes)))
	var h: Array = b.get("cost_hist", [])
	if h.size() >= 2:
		var lc := LineChart.new()
		lc.custom_minimum_size.y = 160
		lc.set_data("Costo por unidad y precio de venta", [{"label": "Costo/u", "color": UIKit.BAD, "values": h.map(func(e): return float(e[1]))},
			{"label": "Precio", "color": UIKit.GOOD, "values": h.map(func(e): return float(e[2]))}], true, h.map(func(e): return Fmt.short_date(int(e[0]))))
		v.add_child(lc)
	var est := CostSim.estimate(gs, str(b["type"]), int(b["level"]))
	var r := UIKit.rich()
	r.text = "[color=#c9a24a]Calculadora a plantilla completa (precios de hoy):[/color]\n" + CostSim.estimate_text(est)
	v.add_child(r)
	return v


static func _note(t: String) -> Label:
	var l := UIKit.label(t, 12, UIKit.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 320
	return l
