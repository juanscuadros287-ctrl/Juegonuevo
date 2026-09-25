class_name StatsPanel
extends VBoxContainer
## Estadísticas del pueblo en pestañas:
## Resumen (tarjetas de indicadores con tendencia y sparkline + recomendaciones), Población
## (pirámide, empleo por sector, necesidades, vivienda), Mercado (tabla ordenable de bienes y
## precios), Comercio (barras), Pueblos vecinos (tarjetas) y Empresas de otros ciudadanos.
## Se reconstruye al abrir, al cambiar de pestaña o con ↻ (nunca cada frame).

signal closed

const TABS := [["resumen", "Resumen", "grid"], ["poblacion", "Población", "population"], ["mercado", "Mercado", "economy"],
	["comercio", "Comercio", "trade"], ["pueblos", "Pueblos", "town"], ["empresas", "Empresas", "companies"]]

var body: VBoxContainer
var tab_bar: HBoxContainer
var current_tab := "resumen"
var _scroll: ScrollContainer


func setup() -> void:
	add_theme_constant_override("separation", 8)
	var refresh_btn := UIKit.icon_button("refresh", refresh, "Actualizar", "", 16)
	UIKit.header(self, "stats", "Estadísticas del pueblo", func(): closed.emit(), [refresh_btn])
	tab_bar = HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 2)
	add_child(tab_bar)
	for t in TABS:
		var id := str(t[0])
		var b := Button.new()
		b.icon = UIIcons.tex(str(t[2]), 16)
		b.tooltip_text = str(t[1])
		b.text = str(t[1]) if id in ["resumen"] else ""
		b.toggle_mode = true
		b.name = id
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 32
		b.add_theme_stylebox_override("normal", UIKit._flat(Color(0, 0, 0, 0), 6, 6, 4))
		b.add_theme_stylebox_override("pressed", UIKit._flat(Color(UIKit.ACCENT, 0.18), 6, 6, 4, Color(UIKit.ACCENT, 0.6), 1))
		b.add_theme_stylebox_override("hover_pressed", UIKit._flat(Color(UIKit.ACCENT, 0.24), 6, 6, 4, UIKit.ACCENT, 1))
		b.pressed.connect(func(): show_tab(id))
		tab_bar.add_child(b)
	var sb := UIKit.scroll_box(Vector2(0, 200))
	_scroll = sb["scroll"]
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_scroll)
	body = sb["box"]
	body.add_theme_constant_override("separation", 10)


func show_tab(id: String) -> void:
	current_tab = id
	refresh()
	_scroll.scroll_vertical = 0


func refresh() -> void:
	if body == null:
		return
	for b in tab_bar.get_children():
		var on: bool = b.name == current_tab
		(b as Button).set_pressed_no_signal(on)
		for t in TABS:
			if t[0] == b.name:
				(b as Button).text = str(t[1]) if on else ""
	UIKit.clear(body)
	match current_tab:
		"poblacion":
			_population_tab()
		"mercado":
			_market_tab()
		"comercio":
			_trade_tab()
		"pueblos":
			_towns_tab()
		"empresas":
			_companies_tab()
		_:
			_summary_tab()


# --- Utilidades -------------------------------------------------------------------------------------

func _hist(key: String) -> Array:
	return GameState.history.slice(maxi(0, GameState.history.size() - 24)).map(func(e): return float(e.get(key, 0.0)))


func _hist_dates() -> Array:
	return GameState.history.slice(maxi(0, GameState.history.size() - 24)).map(func(e): return Fmt.short_date(int(e.get("day", 0))))


func _delta(arr: Array) -> float:
	if arr.size() < 2:
		return 0.0
	return (float(arr[-1]) - float(arr[-2])) / maxf(0.0001, absf(float(arr[-2])))


func _note(text: String, parent: Control = null) -> void:
	var l := UIKit.label(text, 12, UIKit.TEXT_FAINT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 360
	(parent if parent != null else body).add_child(l)


func _grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(g)
	return g


func _kpi(g: GridContainer, icon_name: String, title: String, value: String, arr: Array, color: Color, tip: String, invert := false, pts := false) -> void:
	var trend := ""
	if arr.size() >= 2:
		if pts:
			var d := float(arr[-1]) - float(arr[-2])
			trend = "[color=#8a8f99]＝[/color]" if absf(d) < 0.5 else "[color=#%s]%s %d[/color]" % [(UIKit.GOOD if (d > 0.0) != invert else UIKit.BAD).to_html(false), "▲" if d > 0.0 else "▼", int(roundf(absf(d)))]
		else:
			trend = UIKit.trend_bbcode(_delta(arr), invert)
	var card := UIKit.kpi_card(icon_name, title, value, trend, arr, color, tip, 0.0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_child(card)


## PIB aproximado del pueblo: valor de las ventas locales de bienes por mes.
static func gdp_series(gs) -> Array:
	var out := []
	for e in gs.economy.get("stats_hist", []):
		var tot := 0.0
		var goods: Dictionary = e.get("goods", {})
		for g in goods:
			tot += float(goods[g].get("revenue", 0.0))
		out.append(tot)
	return out


# --- Resumen --------------------------------------------------------------------------------------

func _summary_tab() -> void:
	var gs := GameState
	var g := _grid()
	var pop := _hist("population")
	pop.append(float(gs.citizens.size()))
	_kpi(g, "population", "Población", Fmt.thousands(gs.citizens.size()), pop, UIKit.ACCENT_2, "Habitantes del pueblo (serie mensual)")
	var unemp := EconomySim.unemployment(gs)
	var emp := _hist("unemployment").map(func(v): return (1.0 - float(v)) * 100.0)
	emp.append((1.0 - unemp) * 100.0)
	_kpi(g, "employment", "Empleo", Fmt.pct((1.0 - unemp) * 100.0), emp, UIKit.GOOD, "Adultos en edad de trabajar con trabajo (desempleo %s)" % Fmt.pct(unemp * 100.0), false, true)
	var hap := _hist("happiness")
	hap.append(gs.avg_happiness())
	_kpi(g, "happiness", "Felicidad", Fmt.pct(gs.avg_happiness()), hap, UIKit.level_color(gs.avg_happiness() / 100.0), "Felicidad promedio", false, true)
	var hea := _hist("health")
	hea.append(gs.avg_health())
	_kpi(g, "health", "Salud", Fmt.pct(gs.avg_health()), hea, Color(0.95, 0.5, 0.55), "Salud promedio", false, true)
	var crime := float(gs.problems.get("crime", 0.0))
	var cr := _hist("crime")
	_kpi(g, "crime", "Crimen", "%d/100" % int(crime), cr, UIKit.level_color(1.0 - crime / 100.0), "Índice de crimen (sube con pobreza, desempleo e infelicidad; baja con policía)", true, true)
	var infl := EconomySim.annual_inflation(gs)
	var inf := _hist("inflation").map(func(v): return float(v) * 100.0)
	_kpi(g, "inflation", "Inflación anual", Fmt.pct_1(infl * 100.0), inf, UIKit.WARN, "Inflación anualizada · nivel de precios ×%s" % String.num(gs.price_level(), 2), true, true)
	var gdp := gdp_series(gs)
	_kpi(g, "gdp", "PIB del pueblo (mes)", Fmt.money_compact(gdp[-1] if not gdp.is_empty() else 0.0), gdp, UIKit.ACCENT, "Valor de las ventas locales de bienes en el mes (aproximación del PIB)")
	var tre := float(gs.government.get("treasury", 0.0))
	var tr_arr := UIHistory.treasury.duplicate()
	_kpi(g, "treasury", "Tesoro público", Fmt.money_compact(tre), tr_arr, Color(0.7, 0.6, 0.95), "Caja del gobierno (impuestos, subsidios, obras)")
	# Medidores
	var gauges := HBoxContainer.new()
	gauges.add_theme_constant_override("separation", 4)
	body.add_child(gauges)
	var needs := StatsSim.needs_table(gs)
	var met := 0.0
	for r in needs:
		met += float(r["met"]) + float(r["partial"]) * 0.5
	met /= maxf(1.0, needs.size())
	for spec in [[met, "Necesidades", false], [1.0 - unemp, "Empleo", false], [crime / 100.0, "Crimen", true], [float(gs.problems.get("pollution", 0.0)) / 100.0, "Contaminación", true]]:
		var ga := Gauge.new()
		ga.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ga.custom_minimum_size = Vector2(92, 78)
		gauges.add_child(ga)
		ga.set_value(float(spec[0]), str(spec[1]), "", bool(spec[2]))
	# Evolución
	if gs.history.size() >= 2:
		var ch := LineChart.new()
		ch.custom_minimum_size = Vector2(0, 170)
		ch.suffix = "%"
		ch.set_data("Felicidad y salud (%)", [{"label": "Felicidad", "color": UIKit.GOOD, "values": _hist("happiness")}, {"label": "Salud", "color": Color(0.95, 0.5, 0.55), "values": _hist("health")}], false, _hist_dates())
		body.add_child(ch)
	var rec := UIKit.section(body, "Recomendaciones", "info", true, "stats_rec")
	for t in StatsSim.advice(gs):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var ic := UIKit.icon("alert" if str(t).contains("escas") or str(t).contains("pérdid") else "info", 14, UIKit.WARN if str(t).contains("escas") else UIKit.INFO)
		ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(ic)
		var l := UIKit.label(str(t), 12, UIKit.TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		rec.add_child(row)


# --- Población ------------------------------------------------------------------------------------

func _population_tab() -> void:
	var gs := GameState
	var pyr := PyramidChart.new()
	pyr.custom_minimum_size = Vector2(0, 230)
	body.add_child(pyr)
	pyr.set_citizens(gs.citizens, gs.today())
	var p := StatsSim.population(gs)
	_note("Últimos 12 meses: %d nacimientos · %d muertes · niños %d · adultos %d · mayores %d" % [p["births_year"], p["deaths_year"], p["children"], p["adults"], p["elderly"]])
	# Empleo por sector
	var sectors := {}
	var today := gs.today()
	var adult := int(GameData.citizens.get("adult_age", 16))
	var retire := int(GameData.citizens.get("retirement_age", 65))
	for c in gs.citizens.values():
		var age: int = c.age_years(today)
		if age < adult or age >= retire or gs.is_player(c.id):
			continue
		var key := "Sin empleo"
		if c.job_kind == "obra":
			key = "Construcción"
		elif c.job_kind == "empleo":
			var b := gs.get_building(c.job_id)
			key = str(gs.building_def(b).get("sector", "")).capitalize() if not b.is_empty() else "Otros"
			if key == "":
				key = str(gs.building_def(b).get("label", "Otros"))
		sectors[key] = int(sectors.get(key, 0)) + 1
	var keys := sectors.keys()
	keys.sort_custom(func(a, b): return int(sectors[a]) > int(sectors[b]))
	var slices := []
	var i := 0
	for k in keys:
		var col: Color = UIKit.SERIES[i % UIKit.SERIES.size()]
		if k == "Sin empleo":
			col = Color(0.45, 0.47, 0.52)
		slices.append({"label": k, "value": float(sectors[k]), "color": col})
		i += 1
	var donut := DonutChart.new()
	donut.custom_minimum_size = Vector2(0, 180)
	body.add_child(donut)
	var e := StatsSim.employment(gs)
	donut.set_data("Empleo por sector", slices, str(e["workforce"]), "trabajadores")
	_note("Con empleo %d · jornaleros %d · buscan empleo %d · vacantes en tus negocios %d · salario promedio %s/día" % [e["employed"], e["day_laborers"], e["unemployed"], e["vacancies"], Fmt.money2(e["avg_wage"])])
	# Necesidades
	var ns := UIKit.section(body, "¿Qué necesita la gente?", "sprout", true, "stats_needs")
	var nrows := StatsSim.needs_table(gs).map(func(r): return {"label": r["label"], "met": r["met"], "partial": r["partial"], "unmet": r["unmet"]})
	var nt := DataTable.new()
	nt.set_data([{"title": "Necesidad", "key": "label", "w": 1.4}, {"title": "Cubierta", "key": "met", "w": 1.5, "fmt": "bar"},
		{"title": "A medias", "key": "partial", "w": 0.9, "fmt": "pct"}, {"title": "Sin cubrir", "key": "unmet", "w": 0.9, "fmt": "pct"}], nrows, 10)
	ns.add_child(nt)
	_note("A medias = autoabastecimiento (cultivar, buscar agua y leña). Lo que la gente necesita comprar y no encuentra es tu oportunidad.", ns)
	# Vivienda
	var vs := UIKit.section(body, "Vivienda", "realestate", true, "stats_housing")
	var h := StatsSim.housing(gs)
	var hf := UIKit.flow(6, 6)
	vs.add_child(hf)
	hf.add_child(UIKit.chip("Familias %d" % h["households"], UIKit.TEXT_DIM, "family"))
	hf.add_child(UIKit.chip("Sin hogar %d" % h["homeless"], UIKit.BAD if int(h["homeless"]) > 0 else UIKit.GOOD, "alert"))
	hf.add_child(UIKit.chip("Hacinadas %d" % h["crowded"], UIKit.WARN if int(h["crowded"]) > 0 else UIKit.GOOD, "population"))
	hf.add_child(UIKit.chip("Alquilan tus casas %d" % h["renting"], UIKit.ACCENT, "key"))
	var hrows := []
	for tier in Housing.TIERS:
		hrows.append({"tier": Housing.tier_label(tier), "afford": int(h["can_afford"].get(tier, 0)), "vacant": int(h["vacant"].get(tier, 0))})
	var ht := DataTable.new()
	ht.set_data([{"title": "Calidad", "key": "tier", "w": 1.2}, {"title": "Pueden pagarla", "key": "afford", "w": 1.2, "fmt": "int"}, {"title": "Cupos libres tuyos", "key": "vacant", "w": 1.2, "fmt": "int"}], hrows, 6)
	vs.add_child(ht)
	if gs.history.size() >= 2:
		var ch := LineChart.new()
		ch.custom_minimum_size = Vector2(0, 160)
		ch.set_data("Población", [{"label": "Habitantes", "color": UIKit.ACCENT_2, "values": _hist("population")}], false, _hist_dates())
		body.add_child(ch)


# --- Mercado --------------------------------------------------------------------------------------

func _market_tab() -> void:
	var gs := GameState
	var goods := StatsSim.goods_table(gs)
	var rows := goods.map(func(r): return {"label": r["label"], "price": r["price"], "pchg": r["price_change"], "demand": r["demand"], "share": r["local_share"], "uncovered": r["uncovered"]})
	var t := DataTable.new()
	t.sort_col = 3
	t.set_data([{"title": "Bien", "key": "label", "w": 1.5}, {"title": "Precio", "key": "price", "w": 0.9, "fmt": "money2"},
		{"title": "Var.", "key": "pchg", "w": 0.8, "fmt": "trend", "invert": true}, {"title": "Pedido", "key": "demand", "w": 0.8, "fmt": "int"},
		{"title": "Tus ventas", "key": "share", "w": 1.4, "fmt": "bar"}, {"title": "Sin cubrir", "key": "uncovered", "w": 0.9, "fmt": "int"}], rows, 12)
	body.add_child(t)
	_note("Clic en un encabezado para ordenar. Tus ventas = % de lo pedido que compraron a tus negocios. Sin cubrir = demanda que podrías captar.")
	var rev := 0.0
	for r in goods:
		rev += float(r["revenue"])
	var hf := UIKit.flow(6, 6)
	body.add_child(hf)
	hf.add_child(UIKit.chip("Ventas del mes %s" % Fmt.money(rev), UIKit.GOOD, "money"))
	var ups := goods.filter(func(r): return r["price_change"] > 0.02).size()
	var downs := goods.filter(func(r): return r["price_change"] < -0.02).size()
	hf.add_child(UIKit.chip("Suben %d" % ups, UIKit.BAD, "trend_up"))
	hf.add_child(UIKit.chip("Bajan %d" % downs, UIKit.GOOD, "trend_down"))
	var hist: Array = gs.economy.get("stats_hist", [])
	if hist.size() >= 2:
		var by_demand := goods.duplicate()
		by_demand.sort_custom(func(a, b): return a["demand"] > b["demand"])
		var top := by_demand.slice(0, 4).map(func(r): return str(r["good"]))
		var dates := hist.map(func(e): return Fmt.short_date(int(e.get("day", 0))))
		var ps := []
		var ds := []
		for i in range(top.size()):
			var g: String = top[i]
			ps.append({"label": GameData.good_label(g), "color": UIKit.SERIES[i], "values": hist.map(func(e): return float(e.get("prices", {}).get(g, 0.0)))})
			ds.append({"label": GameData.good_label(g), "color": UIKit.SERIES[i], "values": hist.map(func(e): return float(e["goods"].get(g, {}).get("demand", 0.0)) + float(e["goods"].get(g, {}).get("extra", 0.0)))})
		var c1 := LineChart.new()
		c1.custom_minimum_size = Vector2(0, 180)
		c1.fill = false
		c1.set_data("Precios de los bienes más pedidos", ps, true, dates)
		body.add_child(c1)
		var c2 := LineChart.new()
		c2.custom_minimum_size = Vector2(0, 170)
		c2.fill = false
		c2.set_data("Demanda mensual (unidades)", ds, false, dates)
		body.add_child(c2)
	else:
		_note("Las gráficas de precios aparecen tras el primer mes.")


# --- Comercio -------------------------------------------------------------------------------------

func _trade_tab() -> void:
	var gs := GameState
	var goods := StatsSim.goods_table(gs).filter(func(r): return float(r["demand"]) > 0.0)
	goods.sort_custom(func(a, b): return a["demand"] > b["demand"])
	var rows := goods.slice(0, 10).map(func(r): return {"label": r["label"], "values": [float(r["local"]), float(r["imported"]), float(r["self"])]})
	var bc := BarChart.new()
	bc.set_data("Abastecimiento por bien (unidades/mes)", rows, [{"label": "Negocios locales", "color": UIKit.GOOD}, {"label": "Importado", "color": UIKit.ACCENT_2}, {"label": "Autoabastecido", "color": Color(0.55, 0.57, 0.62)}], false)
	body.add_child(bc)
	var m: Dictionary = gs.trade.get("last_month", {})
	var hf := UIKit.flow(6, 6)
	body.add_child(hf)
	hf.add_child(UIKit.chip("Exportaciones %s" % Fmt.money(float(m.get("exports", 0.0))), UIKit.GOOD, "trend_up"))
	hf.add_child(UIKit.chip("Importaciones %s" % Fmt.money(float(m.get("imports", 0.0))), UIKit.BAD, "trend_down"))
	hf.add_child(UIKit.chip("Fletes %s" % Fmt.money(float(m.get("transport", 0.0))), UIKit.TEXT_DIM, "logistics"))
	var trows := []
	for t in TradeSim.towns(gs):
		var conn := TradeSim.connection(gs, str(t["id"]))
		if not conn.is_empty():
			trows.append({"label": str(t["name"]), "values": [float(conn.get("exported", 0.0)), float(conn.get("imported", 0.0))]})
	if not trows.is_empty():
		var tc := BarChart.new()
		tc.set_data("Tu comercio por pueblo (total)", trows, [{"label": "Exportado", "color": UIKit.GOOD}, {"label": "Importado", "color": UIKit.BAD}], true)
		body.add_child(tc)
	else:
		_note("Aún no hay rutas con otros pueblos. Ábrelas en Comercio exterior (X) para exportar e importar.")
	var b := UIKit.button("Abrir Comercio exterior", func(): _open_dock("trade"))
	b.icon = UIIcons.tex("trade", 16)
	body.add_child(b)


func _open_dock(mode: String) -> void:
	var hud := get_parent()
	while hud != null and not hud is Hud:
		hud = hud.get_parent()
	if hud != null:
		(hud as Hud)._show_dock(mode)


# --- Pueblos vecinos ------------------------------------------------------------------------------

func _towns_tab() -> void:
	var gs := GameState
	var towns := TradeSim.towns(gs)
	if towns.is_empty():
		_note("No se conocen otros pueblos.")
		return
	_note("Pueblos de la región: población, sectores, precios, relación contigo y tu reputación. Comercia desde Comercio exterior (X).")
	for t in towns:
		_town_card(gs, t)


func _town_card(gs, t: Dictionary) -> void:
	var tid := str(t["id"])
	var conn := TradeSim.connection(gs, tid)
	var proj := TradeSim.project(gs, tid)
	var rel_txt := "Sin ruta"
	var rel_col := UIKit.NEUTRAL
	if not proj.is_empty():
		rel_txt = "Camino en obra"
		rel_col = UIKit.WARN
	elif not conn.is_empty():
		rel_txt = "Ruta: " + TradeSim.road_label(int(conn.get("road", 1)))
		rel_col = UIKit.GOOD
	var c := UIKit.card(rel_col, 8)
	body.add_child(c["panel"])
	var v: VBoxContainer = c["box"]
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	v.add_child(head)
	head.add_child(UIKit.icon("town", 20, UIKit.ACCENT))
	var n := UIKit.label(str(t["name"]), 16, UIKit.ACCENT)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(n)
	head.add_child(UIKit.chip(rel_txt, rel_col))
	var info := UIKit.flow(5, 4)
	v.add_child(info)
	info.add_child(UIKit.chip(TradeSim.archetype_label(t), UIKit.ACCENT_2))
	info.add_child(UIKit.chip("%s hab." % Fmt.thousands(float(t["population"])), UIKit.TEXT_DIM, "population"))
	info.add_child(UIKit.chip("%d km" % int(t["distance"]), UIKit.TEXT_DIM, "road"))
	info.add_child(UIKit.chip("crece %s/año" % Fmt.pct_1(TownEconomySim.growth_rate(gs, t) * 100.0), UIKit.GOOD, "trend_up"))
	if bool(t.get("water", false)):
		info.add_child(UIKit.chip("puerto", UIKit.INFO, "anchor"))
	# Reputación y sectores
	var rep := ContractSim.reputation(gs, "town:" + tid)
	v.add_child(UIKit.meter_row("trophy", "Reputación", rep / 100.0, "%d" % int(rep)))
	var sectors: Dictionary = t.get("sectors", {})
	if not sectors.is_empty():
		var keys := sectors.keys()
		keys.sort_custom(func(a, b): return int(sectors[a]) > int(sectors[b]))
		var total := TownEconomySim.total_businesses(t)
		var sl := UIKit.label("Sectores (%d negocios)" % total, 11, UIKit.TEXT_DIM)
		v.add_child(sl)
		for k in keys.slice(0, 3):
			v.add_child(UIKit.meter_row("companies", TradeSim.good_label(str(k)), float(sectors[k]) / maxf(1.0, float(total)), str(int(sectors[k])), false, UIKit.ACCENT_2))
	# Precios: lo que vende (compras) y lo que pide (ventas)
	var prices := HBoxContainer.new()
	prices.add_theme_constant_override("separation", 8)
	v.add_child(prices)
	var sells := VBoxContainer.new()
	sells.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prices.add_child(sells)
	sells.add_child(UIKit.label("Vende (tú compras)", 11, UIKit.GOOD))
	for g in t.get("produces", []).slice(0, 3):
		sells.add_child(_price_line(TradeSim.good_label(str(g)), TradeSim.import_price(gs, tid, str(g))))
	var buys := VBoxContainer.new()
	buys.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prices.add_child(buys)
	buys.add_child(UIKit.label("Pide (tú vendes)", 11, UIKit.WARN))
	for g in t.get("demands", []).slice(0, 3):
		buys.add_child(_price_line(TradeSim.good_label(str(g)), TradeSim.export_price(gs, tid, str(g))))


func _price_line(label_text: String, price: float) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := UIKit.label(label_text, 12, UIKit.TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	h.add_child(l)
	h.add_child(UIKit.label(Fmt.money2(price), 12, UIKit.ACCENT))
	return h


# --- Empresas de otros ciudadanos -------------------------------------------------------------------

func _companies_tab() -> void:
	var gs := GameState
	var rows := NpcBusinessSim.summary_rows(gs)
	var data := []
	var states := {"obra": 0, "venta": 0, "activas": 0}
	for r in rows:
		var st := "activa"
		var col := UIKit.GOOD if float(r["profit"]) >= 0.0 else UIKit.BAD
		if r["state"] == NpcBusinessSim.STATE_BUILDING:
			st = "en obra"
			col = UIKit.WARN
			states["obra"] += 1
		elif r["state"] == NpcBusinessSim.STATE_FOR_SALE:
			st = "en venta"
			col = UIKit.INFO
			states["venta"] += 1
		else:
			states["activas"] += 1
		data.append({"name": r["name"], "owner": r["owner"], "state": st, "staff": float(r["staff"]) / maxf(1.0, float(r["jobs"])), "profit": r["profit"], "_color": col, "id": r["id"]})
	var hf := UIKit.flow(6, 6)
	body.add_child(hf)
	hf.add_child(UIKit.chip("Activas %d" % states["activas"], UIKit.GOOD, "companies"))
	hf.add_child(UIKit.chip("En obra %d" % states["obra"], UIKit.WARN, "build"))
	hf.add_child(UIKit.chip("En venta %d" % states["venta"], UIKit.INFO, "key"))
	var t := DataTable.new()
	t.sort_col = 4
	t.set_data([{"title": "Empresa", "key": "name", "w": 1.8}, {"title": "Dueño", "key": "owner", "w": 1.3}, {"title": "Estado", "key": "state", "w": 0.8},
		{"title": "Personal", "key": "staff", "w": 1.3, "fmt": "bar"}, {"title": "Resultado", "key": "profit", "w": 1.0, "fmt": "money"}], data, 14)
	t.row_clicked.connect(func(r): EventBus.building_selected.emit(int(r["id"])))
	body.add_child(t)
	if rows.is_empty():
		_note("Aún no hay. Los ciudadanos con ahorros abren negocios donde nadie vende lo que se pide.")
	else:
		_note("Clic en una empresa para ver su ficha.")
