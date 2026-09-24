class_name StatsPanel
extends VBoxContainer
## Estadísticas: comercio por bien, necesidades, empleo, vivienda, población y recomendaciones.

signal closed

var body: VBoxContainer


func setup() -> void:
	add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	add_child(head)
	var t := UIKit.label("Estadísticas del pueblo", 20, UIKit.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UIKit.button("✕", func(): closed.emit(), 32))
	var sb := UIKit.scroll_box(Vector2(0, 200))
	sb["scroll"].size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(sb["scroll"])
	body = sb["box"]


func _arrow(v: float) -> String:
	if v > 0.02:
		return "[color=#e88]▲ %d%%[/color]" % int(round(v * 100.0))
	if v < -0.02:
		return "[color=#8e8]▼ %d%%[/color]" % int(round(-v * 100.0))
	return "[color=#aaa]=[/color]"


func _section(title: String, text: String) -> void:
	body.add_child(UIKit.label(title, 16, UIKit.ACCENT))
	var rl := UIKit.rich()
	rl.text = text
	body.add_child(rl)


func refresh() -> void:
	UIKit.clear(body)
	var gs := GameState
	var tips := StatsSim.advice(gs)
	_section("Recomendaciones", "\n".join(tips.map(func(t): return "• " + t)))

	var goods := StatsSim.goods_table(gs)
	var s := "[table=5][cell][b]Bien[/b][/cell][cell][b]Precio[/b][/cell][cell][b]Pedido/mes[/b][/cell][cell][b]Tus ventas[/b][/cell][cell][b]Sin cubrir[/b][/cell]"
	for r in goods:
		s += "[cell]%s[/cell][cell]%s %s[/cell][cell]%d %s[/cell][cell]%d%%[/cell][cell]%d[/cell]" % [
			r["label"], Fmt.money2(r["price"]), _arrow(r["price_change"]), int(r["demand"]), _arrow(r["demand_change"]),
			int(r["local_share"] * 100.0), int(r["uncovered"])]
	s += "[/table]\n[color=#999]Tus ventas = % de lo pedido que compraron a tus negocios. Sin cubrir = unidades que se autoabastecieron o importaron (demanda que podrías captar).[/color]\n"
	var by_demand := goods.duplicate()
	by_demand.sort_custom(func(a, b): return a["demand"] > b["demand"])
	var active := by_demand.filter(func(r): return r["demand"] > 0.0)
	if not active.is_empty():
		s += "Más pedido: [b]%s[/b] · Menos pedido: [b]%s[/b]\n" % [active[0]["label"], active[-1]["label"]]
	var ups := goods.filter(func(r): return r["price_change"] > 0.02).map(func(r): return r["label"])
	var downs := goods.filter(func(r): return r["price_change"] < -0.02).map(func(r): return r["label"])
	s += "Suben de precio: %s · Bajan: %s\n" % [", ".join(ups) if not ups.is_empty() else "—", ", ".join(downs) if not downs.is_empty() else "—"]
	var rev := 0.0
	for r in goods:
		rev += float(r["revenue"])
	s += "Ventas totales de tus negocios en el mes: %s" % Fmt.money(rev)
	_section("Comercio (último mes)", s)

	var n := "[table=4][cell][b]Necesidad[/b][/cell][cell][b]Cubierta[/b][/cell][cell][b]A medias[/b][/cell][cell][b]Sin cubrir[/b][/cell]"
	for r in StatsSim.needs_table(gs):
		n += "[cell]%s[/cell][cell]%d%%[/cell][cell]%d%%[/cell][cell]%s[/cell]" % [r["label"], int(r["met"] * 100), int(r["partial"] * 100),
			("[color=#e66]%d%%[/color]" % int(r["unmet"] * 100)) if r["unmet"] > 0.05 else "%d%%" % int(r["unmet"] * 100)]
	n += "[/table]\n[color=#999]A medias = autoabastecimiento (cultivar, buscar agua y leña): peor calidad de vida. Lo que la gente necesita comprar y no encuentra es tu oportunidad.[/color]"
	_section("¿Qué necesita la gente?", n)

	var e := StatsSim.employment(gs)
	var sk: Dictionary = e["by_skill"]
	var skills := sk.keys()
	skills.sort_custom(func(a, b): return sk[a] > sk[b])
	var es := "Fuerza laboral: %d · Con empleo: %d · Jornaleros: %d · [b]Buscan empleo: %d (%s)[/b]\n" % [e["workforce"], e["employed"], e["day_laborers"], e["unemployed"], Fmt.pct(100.0 * e["unemployed"] / maxf(1.0, e["workforce"]))]
	es += "Vacantes en tus negocios: %d · Salario promedio: %s/día\n" % [e["vacancies"], Fmt.money2(e["avg_wage"])]
	es += "Desempleados por habilidad: %s\n" % ", ".join(skills.slice(0, 6).map(func(k): return "%s %d" % [GameData.skill_label(k), sk[k]]))
	var edu: Dictionary = e["education"]
	es += "Educación (adultos): %s\n" % ", ".join([0, 1, 2, 3].map(func(l): return "%s %d" % [GameData.education_label(l), int(edu.get(l, 0))]))
	var pr: Dictionary = e["professions"]
	es += "Profesionales: %s" % (", ".join(pr.keys().map(func(k): return "%s %d" % [GameData.profession_label(k), pr[k]])) if not pr.is_empty() else "ninguno (se forman en la universidad)")
	_section("Empleo", es)

	var h := StatsSim.housing(gs)
	var hs := "Familias: %d · Sin hogar: [b]%d[/b] · Hacinadas: [b]%d[/b] · Quieren mudarse: %d\n" % [h["households"], h["homeless"], h["crowded"], h["wants_move"]]
	hs += "En chozas del pueblo: %d · Alquilan tus casas: %d · Propietarias: %d\n" % [h["in_town_huts"], h["renting"], h["owners"]]
	hs += "[table=3][cell][b]Calidad[/b][/cell][cell][b]Familias que pueden pagarla[/b][/cell][cell][b]Cupos libres en tus casas[/b][/cell]"
	for tier in Housing.TIERS:
		hs += "[cell]%s[/cell][cell]%d[/cell][cell]%d[/cell]" % [Housing.tier_label(tier), int(h["can_afford"].get(tier, 0)), int(h["vacant"].get(tier, 0))]
	hs += "[/table]"
	_section("Vivienda", hs)

	var p := StatsSim.population(gs)
	_section("Población", "Habitantes: %d · Niños: %d · Adultos: %d · Mayores: %d\nÚltimos 12 meses: %d nacimientos, %d muertes · Felicidad: %s · Salud: %s\n[color=#999]La población solo crece por nacimientos. Con caminos a otros pueblos (Fase 6) llegarán inmigrantes y comercio.[/color]" % [
		gs.citizens.size(), p["children"], p["adults"], p["elderly"], p["births_year"], p["deaths_year"], Fmt.pct(gs.avg_happiness()), Fmt.pct(gs.avg_health())])

	var hist: Array = gs.economy.get("stats_hist", [])
	if hist.size() >= 2:
		var series := []
		var colors := [Color(0.95, 0.8, 0.3), Color(0.5, 0.7, 0.95), Color(0.6, 0.45, 0.3), Color(0.8, 0.5, 0.9)]
		var i := 0
		for g in ["comida", "agua", "lena", "ocio"]:
			series.append({"label": GameData.good_label(g), "color": colors[i], "values": hist.map(func(e): return float(e["goods"].get(g, {}).get("demand", 0.0)) + float(e["goods"].get(g, {}).get("extra", 0.0)))})
			i += 1
		var c1 := LineChart.new()
		c1.custom_minimum_size = Vector2(390, 160)
		c1.set_data("Demanda mensual por bien (unidades)", series, false)
		body.add_child(c1)
		var ps := []
		i = 0
		for g in ["comida", "agua", "lena", "ocio"]:
			ps.append({"label": GameData.good_label(g), "color": colors[i], "values": hist.map(func(e): return float(e.get("prices", {}).get(g, 0.0)))})
			i += 1
		var c2 := LineChart.new()
		c2.custom_minimum_size = Vector2(390, 160)
		c2.set_data("Precio de mercado por bien", ps, true)
		body.add_child(c2)
