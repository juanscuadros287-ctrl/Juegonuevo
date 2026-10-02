class_name PricesTab
extends RefCounted
## Pestaña "Precios" de Estadísticas: tabla de todos los bienes con precio actual, variación a 1 mes, 12 meses y
## 5 años, mínimo, máximo, tendencia y causa de la fluctuación; gráfica con varios bienes a elegir y rango de
## tiempo, más el IPC, el salario promedio y el valor del suelo. Datos de PriceHistorySim.

static var selected: Array = []
static var range_months := 60
const RANGES := [[12, "1 año"], [60, "5 años"], [240, "20 años"], [0, "Todo"]]
const INDEXES := [["ipc", "IPC (precios)"], ["w", "Salario promedio"], ["land", "Valor del suelo"]]


static func build(gs, body: VBoxContainer, refresh_cb: Callable) -> void:
	var goods := PriceHistorySim.goods_list()
	if selected.is_empty():
		for g in ["trigo", "madera", "herramientas"]:
			if goods.has(g):
				selected.append(g)
	var rows := []
	for g in goods:
		var now := EconomySim.market_price(gs, g)
		var mm := PriceHistorySim.min_max(gs, g)
		var sp: Array = PriceHistorySim.series(gs, g, 24)["values"]
		sp = sp.duplicate()
		sp.append(now)
		var cs := PriceHistorySim.causes(gs, g)
		rows.append({"good": g, "label": GameData.good_label(g), "price": now, "c1": _chg(gs, g, 1, now), "c12": _chg(gs, g, 12, now),
			"c60": _chg(gs, g, 60, now), "min": minf(mm.x, now), "max": maxf(mm.y, now), "spark": sp,
			"cause": ", ".join(cs) if not cs.is_empty() else "estable",
			"_color": UIKit.ACCENT if selected.has(g) else UIKit.TEXT})
	var dt := DataTable.new()
	dt.set_data([{"title": "Bien", "key": "label", "w": 1.3}, {"title": "Precio", "key": "price", "w": 0.8, "fmt": "money2"},
		{"title": "1 mes", "key": "c1", "w": 0.7, "fmt": "trend", "invert": true}, {"title": "12 m", "key": "c12", "w": 0.7, "fmt": "trend", "invert": true},
		{"title": "5 años", "key": "c60", "w": 0.7, "fmt": "trend", "invert": true}, {"title": "Mín", "key": "min", "w": 0.7, "fmt": "money2"},
		{"title": "Máx", "key": "max", "w": 0.7, "fmt": "money2"}, {"title": "Tendencia", "key": "spark", "w": 0.8, "fmt": "spark"},
		{"title": "Causa", "key": "cause", "w": 1.8}], rows, 14)
	dt.row_clicked.connect(func(r):
		var g := str(r["good"])
		if selected.has(g):
			selected.erase(g)
		elif selected.size() < 6:
			selected.append(g)
		refresh_cb.call())
	body.add_child(dt)
	var note := UIKit.label("Clic en un bien para agregarlo o quitarlo de la gráfica (máx. 6). Variaciones contra el historial mensual guardado en la partida (20 años mensual, luego anual).", 12, UIKit.TEXT_FAINT)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 360
	body.add_child(note)
	var rr := HBoxContainer.new()
	rr.add_theme_constant_override("separation", 4)
	rr.add_child(UIKit.label("Rango:", 12, UIKit.TEXT_DIM))
	for r in RANGES:
		var m := int(r[0])
		var b := UIKit.button(str(r[1]), func():
			range_months = m
			refresh_cb.call())
		b.toggle_mode = true
		b.set_pressed_no_signal(m == range_months)
		rr.add_child(b)
	body.add_child(rr)
	# Gráfica: índice base 100 al inicio del rango (bienes de precios muy distintos en una misma escala).
	var series := []
	var labels := []
	var i := 0
	for g in selected:
		var s := PriceHistorySim.series(gs, g, range_months)
		var vals: Array = s["values"].duplicate()
		vals.append(EconomySim.market_price(gs, g))
		if labels.is_empty():
			labels = (s["days"] as Array).map(func(d): return Fmt.short_date(int(d)))
			labels.append("hoy")
		series.append({"label": GameData.good_label(g), "color": UIKit.SERIES[i % UIKit.SERIES.size()], "values": _base100(vals)})
		i += 1
	for ix in INDEXES:
		var s2 := PriceHistorySim.series(gs, str(ix[0]), range_months)
		var v2: Array = s2["values"].duplicate()
		if v2.size() < 1:
			continue
		var key := str(ix[0])
		v2.append(gs.price_level() if key == "ipc" else (PriceHistorySim.avg_wage(gs) if key == "w" else PriceHistorySim.land_index(gs)))
		series.append({"label": str(ix[1]), "color": UIKit.SERIES[i % UIKit.SERIES.size()].darkened(0.1), "values": _base100(v2)})
		i += 1
	if series.is_empty() or (series[0]["values"] as Array).size() < 2:
		body.add_child(UIKit.label("La gráfica aparece al cerrar el primer mes (el historial se guarda en la partida).", 12, UIKit.TEXT_DIM))
		return
	var lc := LineChart.new()
	lc.custom_minimum_size.y = 220
	lc.suffix = ""
	lc.set_data("Precios e índices (base 100 al inicio del rango)", series, false, labels)
	body.add_child(lc)
	var chips := UIKit.flow(6, 6)
	body.add_child(chips)
	chips.add_child(UIKit.chip("IPC %s · inflación anual %s" % [String.num(gs.price_level(), 3), Fmt.pct_1(EconomySim.annual_inflation(gs) * 100.0)], UIKit.WARN, "inflation", 11))
	chips.add_child(UIKit.chip("Salario promedio %s/día" % Fmt.money2(PriceHistorySim.avg_wage(gs)), UIKit.TEXT_DIM, "employment", 11))
	chips.add_child(UIKit.chip("Suelo %s (100 = normal)" % String.num(PriceHistorySim.land_index(gs), 1), UIKit.TEXT_DIM, "map", 11))


static func _chg(gs, g: String, months: int, now: float):
	var c := PriceHistorySim.change(gs, g, months, now)
	return "—" if is_nan(c) else c


static func _base100(vals: Array) -> Array:
	if vals.is_empty():
		return vals
	var b := float(vals[0])
	if b <= 0.0:
		return vals.map(func(_v): return 100.0)
	return vals.map(func(v): return float(v) / b * 100.0)
