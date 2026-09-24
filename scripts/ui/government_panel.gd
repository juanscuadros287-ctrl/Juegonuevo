class_name GovernmentPanel
extends VBoxContainer
## Gobierno: régimen y políticas, tus impuestos, elecciones, misiones, licitaciones y problemas del pueblo.

signal closed
signal message(text: String, category: String)

var hud: Hud
var body: VBoxContainer
var bid_spin: SpinBox


func setup(p_hud: Hud) -> void:
	hud = p_hud
	add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	add_child(head)
	var t := UIKit.label("Gobierno", 20, UIKit.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UIKit.button("✕", func(): closed.emit(), 32))
	var sb := UIKit.scroll_box(Vector2(0, 200))
	sb["scroll"].size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(sb["scroll"])
	body = sb["box"]


func _section(title: String, text: String) -> void:
	body.add_child(UIKit.label(title, 16, UIKit.ACCENT))
	var rl := UIKit.rich()
	rl.text = text
	body.add_child(rl)


func _msg(text: String, cat := "importante") -> void:
	message.emit(text, cat)
	refresh()


func _pct(v: float) -> String:
	return "%.1f%%" % (v * 100.0)


func refresh() -> void:
	UIKit.clear(body)
	var gs := GameState
	var g: Dictionary = gs.government
	var p := GovSim.policy(gs)
	var r := GovSim.regime(gs)
	var s := "[b]%s[/b] · %s\n[color=#aaa]%s[/color]\n" % [r.get("label", ""), p.get("label", ""), p.get("description", "")]
	s += "En el poder desde: %s\n" % TimeManager.date_from_day(int(g.get("since_day", 0)), TimeManager.start_year())
	if str(r.get("type", "")) == "election":
		s += "Próximas elecciones: %s\n" % TimeManager.date_from_day(int(g.get("election_day", 0)), TimeManager.start_year())
	else:
		s += "Cambio de virrey previsto: hacia %d\n" % (TimeManager.start_year() + int(g.get("next_change_day", 0)) / 365)
	s += "Tesoro público: %s · Tu reputación ante el gobierno: %d/100" % [Fmt.money(float(g.get("treasury", 0.0))), int(g.get("reputation", 50.0))]
	_section("Gobierno actual", s)

	var laws := "Impuesto a las ganancias: [b]%s[/b] (fundaciones exentas)\n" % _pct(float(p.get("profit_tax", 0)))
	laws += "Impuesto a la propiedad: [b]%s anual[/b] · Impuesto a la nómina: [b]%s[/b]\n" % [_pct(float(p.get("property_tax", 0))), _pct(float(p.get("wage_tax", 0)))]
	laws += "Salario mínimo: [b]%s[/b] · Arancel a importaciones: [b]%s[/b]\n" % ["ninguno" if GovSim.min_wage(gs) <= 0.0 else Fmt.money2(GovSim.min_wage(gs)) + "/día", "+" + _pct(float(p.get("import_tariff", 1.0)) - 1.0)]
	laws += "Subsidio a servicios públicos: [b]%s de los salarios[/b] · Ayuda a los pobres: [b]%s[/b]\n" % [_pct(float(p.get("public_service_subsidy", 0))), "sí" if float(p.get("poor_relief", 0)) > 0.0 else "no"]
	laws += "Multa ambiental: [b]%s[/b]" % ("ninguna" if float(p.get("env_fine", 0)) <= 0.0 else "%s por punto de contaminación" % Fmt.money(float(p.get("env_fine", 0)) * 10.0 * gs.price_level()))
	_section("Leyes y políticas", laws)

	var tl: Dictionary = g.get("taxes_last", {})
	var tx := "Renta %s · Propiedad %s · Nómina %s · Multas %s\n" % [Fmt.money(float(tl.get("renta", 0))), Fmt.money(float(tl.get("propiedad", 0))), Fmt.money(float(tl.get("nomina", 0))), Fmt.money(float(tl.get("multas", 0)))]
	tx += "Subsidios recibidos: %s" % Fmt.money(float(g.get("subsidies_last", 0.0)))
	if GovSim.exempt(gs, "profit_tax"):
		tx += "\n[color=#6c6]Exento de impuesto a las ganancias hasta el %s[/color]" % TimeManager.date_from_day(int(g["exemptions"]["profit_tax"]), TimeManager.start_year())
	_section("Tus impuestos (mes anterior)", tx)

	var cands: Array = g.get("candidates", [])
	if not cands.is_empty():
		body.add_child(UIKit.label("Campaña electoral", 16, UIKit.ACCENT))
		for gid in cands:
			var gd: Dictionary = GovSim.cfg()["governments"][gid]
			var row := HBoxContainer.new()
			var l := UIKit.label("%s — renta %s, salario mín. %s, social %d%% · aportes %s" % [gd.get("label", gid), _pct(float(gd.get("profit_tax", 0))), Fmt.money2(float(gd.get("min_wage", 0)) * gs.price_level()), int(float(gd.get("social", 0)) * 100), Fmt.money(float(g.get("donations", {}).get(gid, 0.0)))], 13)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(l)
			var amount := 200.0 * gs.price_level()
			var id: String = gid
			row.add_child(UIKit.button("Aportar %s" % Fmt.money(amount), func(): _msg(GovSim.donate(GameState, id, amount), "info")))
			body.add_child(row)

	body.add_child(UIKit.label("Misiones del gobierno", 16, UIKit.ACCENT))
	var avail: Array = g.get("missions_available", [])
	for i in range(avail.size()):
		var m: Dictionary = avail[i]
		var row := HBoxContainer.new()
		var l := UIKit.label("%s · recompensa %s%s · plazo %d meses" % [m["label"], Fmt.money(float(m.get("reward_money", 0))), " + %d meses sin renta" % int(m["reward_exemption_months"]) if int(m.get("reward_exemption_months", 0)) > 0 else "", int(m.get("months", 24))], 13)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var idx := i
		row.add_child(UIKit.button("Aceptar", func(): _msg(GovSim.accept_mission(GameState, idx), "info")))
		body.add_child(row)
	var ma := ""
	for m in g.get("missions_active", []):
		ma += "• [b]%s[/b] — progreso %s · vence %s\n" % [m["label"], GovSim.mission_progress(gs, m), TimeManager.date_from_day(int(m["deadline"]), TimeManager.start_year())]
	ma += "Cumplidas: %d · Fallidas: %d" % [int(g.get("missions_done", 0)), int(g.get("missions_failed", 0))]
	if avail.is_empty() and g.get("missions_active", []).is_empty():
		ma = "[color=#999]El gobierno propone misiones cada 6 meses según las necesidades del pueblo.[/color]\n" + ma
	var mr := UIKit.rich()
	mr.text = ma
	body.add_child(mr)

	body.add_child(UIKit.label("Licitaciones de obras públicas", 16, UIKit.ACCENT))
	var tenders := GovSim.open_tenders(gs)
	if tenders.is_empty():
		body.add_child(UIKit.label("No hay licitaciones abiertas. El gobierno publica obras (plazas, iglesias, acueductos, puentes, hospitales de caridad) de vez en cuando.", 13, UIKit.TEXT_DIM))
	for t in tenders:
		var ld := GameData.level_def(str(t["type"]), 1)
		var eff: Dictionary = ld.get("effects", {})
		var tl2 := UIKit.label("%s · valor de referencia %s · efecto: %s" % [ld.get("label", ""), Fmt.money(float(t["value"])), _effects_text(eff)], 13)
		tl2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tl2.custom_minimum_size.x = 380
		body.add_child(tl2)
		var row := HBoxContainer.new()
		if t["status"] == "open":
			bid_spin = UIKit.spin(float(t["value"]) * 0.5, float(t["value"]) * 2.0, 10, float(t["value"]), func(_v): pass, 130)
			row.add_child(UIKit.label("Tu oferta:"))
			row.add_child(bid_spin)
			var tender: Dictionary = t
			row.add_child(UIKit.button("Ofertar", func(): _msg(GovSim.bid(GameState, tender, bid_spin.value))))
		else:
			var tender2: Dictionary = t
			row.add_child(UIKit.label("Ganada por %s. Costos iniciales ~%s + jornales." % [Fmt.money(float(t["bid"])), Fmt.money(float(t["value"]) * 0.6)], 13, Color(0.5, 0.85, 0.5)))
			row.add_child(UIKit.button("Colocar obra", func():
				var world := hud.get_parent()
				if world.has_method("start_public_placement"):
					world.start_public_placement(tender2)
					closed.emit()))
		body.add_child(row)

	body.add_child(UIKit.label("Plan de gobierno", 16, UIKit.ACCENT))
	var ptxt := ""
	var shown := 0
	var plist: Array = GovPlansSim.plans(gs)
	for i in range(plist.size() - 1, -1, -1):
		var pl: Dictionary = plist[i]
		if shown >= 8:
			break
		shown += 1
		var col := "#6c6" if str(pl["status"]) == "terminado" else ("#e66" if str(pl["status"]) == "cancelado" else "#e9b949")
		var extra := ""
		if str(pl["status"]) == "en_obra":
			var pb: Dictionary = gs.get_building(int(pl.get("bid", -1)))
			if not pb.is_empty():
				extra = " · %d%%" % int(100.0 * float(pb["work_done"]) / maxf(1.0, float(pb["work_needed"])))
		ptxt += "• [b]%s[/b] — %s · [color=%s]%s%s[/color] · %s\n" % [pl["label"], GovPlansSim.need_label(str(pl["need"])), col, GovPlansSim.status_label(str(pl["status"])), extra, Fmt.money(float(pl.get("cost", 0.0)))]
	if ptxt == "":
		ptxt = "[color=#999]El gobierno revisa cada trimestre salud, crimen, vivienda, educación y felicidad, y construye con el tesoro (o licita la obra).[/color]\n"
	var nd := GovPlansSim.needs(gs)
	if not nd.is_empty():
		ptxt += "Necesidades medidas: %s\n" % ", ".join(nd.map(func(n): return GovPlansSim.need_label(str(n["need"]))))
	ptxt += "Alumnos en escuelas públicas: %d" % GovPlansSim.students(gs)
	var prl := UIKit.rich()
	prl.text = ptxt
	body.add_child(prl)

	var pr: Dictionary = gs.problems
	var cov: Dictionary = pr.get("coverage", {})
	var ps := "Crimen: [b]%d/100[/b] · Robos el mes pasado: %d · Arrestos: %d · Presos: %d/%d\n" % [int(pr.get("crime", 0)), int(pr.get("incidents_last", 0)), int(pr.get("arrests_last", 0)),
		gs.citizens.values().filter(func(c): return c.prison_until >= 0).size(), int(cov.get("carcel_capacity", 0))]
	ps += "Contaminación: [b]%d/100[/b] · Incendios este año: %d\n" % [int(pr.get("pollution", 0)), int(pr.get("fires_year", 0))]
	ps += "Cobertura — policía %s · bomberos %s · salud %s\n" % [Fmt.pct(float(cov.get("policia", 0)) * 100), Fmt.pct(float(cov.get("bomberos", 0)) * 100), Fmt.pct(float(cov.get("salud", 0)) * 100)]
	var evs := []
	for e in pr.get("events", []):
		evs.append("%s (hasta %s)" % [EventsSim.cfg()["events"][e["id"]].get("label", e["id"]), TimeManager.date_from_day(int(e["until"]), TimeManager.start_year())])
	ps += "Eventos activos: %s" % (", ".join(evs) if not evs.is_empty() else "ninguno")
	_section("Problemas del pueblo", ps)



func _effects_text(eff: Dictionary) -> String:
	var parts := []
	for k in eff:
		var v := float(eff[k])
		match str(k):
			"happiness":
				parts.append("felicidad +%d" % int(v))
			"disease":
				parts.append("enfermedades −%d%%" % int(round((1.0 - v) * 100.0)))
			"mortality":
				parts.append("mortalidad −%d%%" % int(round((1.0 - v) * 100.0)))
	return ", ".join(parts) if not parts.is_empty() else "—"
