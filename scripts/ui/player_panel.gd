class_name PlayerPanel
extends VBoxContainer
## "Mi Personaje": salud, familia, hogar, relaciones y acciones personales, más la sección C:
## familia con talentos y educación, orden de herederos, propuestas de matrimonio y política.

signal closed
signal message(text: String, category: String)

var hud: Hud
var info: RichTextLabel
var actions: VBoxContainer
var profile: VBoxContainer
var _scroll: ScrollContainer
var _family_title: Control


func setup(p_hud: Hud) -> void:
	hud = p_hud
	add_theme_constant_override("separation", 8)
	UIKit.header(self, "dynasty", "Mi personaje y dinastía", func(): closed.emit())
	var sb := UIKit.scroll_box(Vector2(0, 200))
	sb["scroll"].size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll = sb["scroll"]
	add_child(sb["scroll"])
	profile = VBoxContainer.new()
	profile.add_theme_constant_override("separation", 6)
	sb["box"].add_child(profile)
	info = UIKit.rich()
	info.meta_clicked.connect(hud.on_meta_clicked)
	sb["box"].add_child(info)
	actions = VBoxContainer.new()
	sb["box"].add_child(actions)


func refresh() -> void:
	var p := GameState.player_citizen()
	if p == null:
		info.text = "Sin personaje."
		return
	var today := GameState.today()
	_build_profile(p)
	var s := ""
	var home := PlayerSim.player_home(GameState)
	s += "Hogar: %s\n\n" % ("Sin hogar" if home.is_empty() else "%s (%s)" % [GameState.building_label(home), Housing.tier_label(str(home.get("tier", "normal")))])
	s += "[b]Familia[/b]\n"
	s += "Cónyuge: %s\n" % (hud.link(p.spouse_id) if p.spouse_id >= 0 else "—")
	var kids := PlayerSim.heir_candidates(GameState)
	s += "Hijos: %s\n" % (", ".join(kids.map(func(k): return "%s (%d)" % [hud.link(k.id), k.age_years(today)])) if not kids.is_empty() else "—")
	var first: Citizen = HeirsSim.pick_heir(GameState, p)
	var heir := int(GameState.player.get("heir_id", -1))
	if first != null:
		s += "Heredero: %s (n.º 1 de tu lista)\n" % hud.link(first.id)
	else:
		s += "Heredero: %s\n" % (hud.link(heir) if GameState.citizens.has(heir) else ("el hijo(a) mayor" if not kids.is_empty() else "[color=#e66]ninguno: si mueres, termina la partida[/color]"))
	s += "Tus talentos: %s\nBonos como jefe de familia: %s\n" % [HeirsSim.talents_text(GameState, p), HeirsSim.bonus_text(GameState)]
	s += "Planificación familiar: %s\n\n" % ("buscando hijos" if bool(GameState.player.get("family_planning", true)) else "no desean hijos")
	s += _dynasty_text(p, kids)
	var rel: Dictionary = GameState.player.get("relations", {})
	var known := rel.keys()
	known.sort_custom(func(a, b): return float(rel[a]) > float(rel[b]))
	s += "[b]Personas que conoces[/b]\n"
	var n := 0
	for k in known:
		var id := int(k)
		if GameState.citizens.has(id) and n < 15:
			s += "• %s — %s\n" % [hud.link(id), PlayerSim.relation_label(GameState, GameState.citizens[id])]
			n += 1
	if n == 0:
		s += "[color=#999]Haz clic en personas del pueblo para conocerlas.[/color]\n"
	info.text = s
	_rebuild_actions(p, kids)


## Dinastía (Fase 8): aviso de sucesión, impuesto a la herencia, deudas heredables y jefes de familia.
func _dynasty_text(p: Citizen, kids: Array) -> String:
	var s := "[b]Dinastía[/b] · generación %d\n" % DynastySim.generation(GameState)
	var age := p.age_years(GameState.today())
	if kids.is_empty() and age >= int(DynastySim.cfg().get("old_age_warning", 60)):
		s += "[color=#e66]⚠ Tienes %d años y no tienes heredero. Ten hijos o adopta antes de que sea tarde.[/color]\n" % age
	var est := DynastySim.estimate_tax(GameState)
	s += "Impuesto a la herencia del gobierno actual: %s sobre el patrimonio que supere %s\n" % [Fmt.pct(float(est["rate"]) * 100.0), Fmt.money(float(est["exempt"]))]
	s += "Si murieras hoy: patrimonio %s → impuesto ≈ %s\n" % [Fmt.money(float(est["net_worth"])), Fmt.money(float(est["tax"]))]
	if float(est["debt"]) > 0.0:
		s += "Deudas que heredaría tu sucesor: %s (%d préstamo(s))\n" % [Fmt.money(float(est["debt"])), BankSim.player_loans(GameState).size()]
	if float(est["pending"]) > 0.0:
		s += "[color=#dc4]Impuesto a la herencia pendiente: %s (cuota mensual %s)[/color]\n" % [Fmt.money(float(est["pending"])), Fmt.money(minf(float(est["pending"]), float(GameState.player.get("inheritance_installment", 0.0))))]
	s += "[color=#aaa]Jefes de familia:[/color]\n"
	var list := DynastySim.heads(GameState)
	for i in range(list.size() - 1, -1, -1):
		var h: Dictionary = list[i]
		var end_year := int(h.get("end_year", -1))
		var years := DynastySim.years_of(GameState, h)
		var worth := float(h["net_worth_end"]) if end_year >= 0 else EconomySim.net_worth(GameState)
		s += "%d. %s — %d–%s (%d años al frente) · patrimonio %s%s\n" % [i + 1, str(h.get("name", "")), int(h.get("start_year", 0)),
			str(end_year) if end_year >= 0 else "hoy", years, Fmt.money(worth),
			" · impuesto %s" % Fmt.money(float(h.get("tax_paid", 0.0))) if float(h.get("tax_paid", 0.0)) > 0.0 else ""]
	return s + "\n"


func _rebuild_actions(p: Citizen, kids: Array) -> void:
	UIKit.clear(actions)
	var home := PlayerSim.player_home(GameState)
	if not home.is_empty():
		actions.add_child(UIKit.button("Ver mi casa por dentro", func(): EventBus.interior_requested.emit(int(home["id"]))))
	if p.spouse_id >= 0:
		actions.add_child(UIKit.button("Buscar un bebé con mi pareja", func(): _do(PlayerSim.try_child(GameState))))
	var fp := CheckBox.new()
	fp.text = "Queremos tener hijos"
	fp.button_pressed = bool(GameState.player.get("family_planning", true))
	fp.toggled.connect(func(on): GameState.player["family_planning"] = on)
	actions.add_child(fp)
	actions.add_child(UIKit.button("Adoptar un bebé de otro pueblo (%s)" % Fmt.money(float(PlayerSim.cfg().get("adopt_baby_fee", 400)) * GameState.price_mult()), func(): _do(PlayerSim.adopt_baby(GameState))))
	actions.add_child(UIKit.button("Ir al médico (%s)" % Fmt.money(float(PlayerSim.cfg().get("doctor_fee", 30)) * GameState.price_mult()), func(): _do(PlayerSim.visit_doctor(GameState))))
	_family_section(p)
	_heirs_section()
	_marriage_section(p)
	_politics_section()
	actions.add_child(UIKit.button("Ir a mi personaje (cámara)", func():
		var world := hud.get_parent()
		if world.has_method("focus_citizen"):
			world.focus_citizen(GameState.player_id)))


func _do(text: String) -> void:
	message.emit(text, "familia")
	refresh()


# --- Sección C: familia y dinastía ----------------------------------------------------------------------

func _title(text: String) -> void:
	actions.add_child(HSeparator.new())
	var l := UIKit.label(text, 17, UIKit.ACCENT)
	actions.add_child(l)
	if text.begins_with("Familia"):
		_family_title = l


## Desplaza la vista hasta la sección de familia (menú Mi dinastía → Familia y herederos).
func scroll_to_family() -> void:
	if _scroll == null:
		return
	await get_tree().process_frame
	if is_instance_valid(_family_title):
		_scroll.ensure_control_visible(_family_title)
		_scroll.scroll_vertical = int(_family_title.position.y + actions.position.y) - 8


## Ficha visual: retrato, indicadores, patrimonio, talentos y árbol familiar.
func _build_profile(p: Citizen) -> void:
	UIKit.clear(profile)
	var gs := GameState
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	profile.add_child(head)
	var por := Portrait.new()
	por.custom_minimum_size = Vector2(72, 72)
	por.set_citizen(p, true)
	head.add_child(por)
	var nv := VBoxContainer.new()
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.add_theme_constant_override("separation", 3)
	head.add_child(nv)
	nv.add_child(UIKit.label(p.full_name(), 19, UIKit.ACCENT))
	var chips := UIKit.flow(4, 4)
	nv.add_child(chips)
	chips.add_child(UIKit.chip("%s · %d años" % ["Mujer" if p.gender == "F" else "Hombre", p.age_years(gs.today())], UIKit.TEXT_DIM, "character"))
	chips.add_child(UIKit.chip("Generación %d" % DynastySim.generation(gs), UIKit.ACCENT, "dynasty"))
	if p.sick:
		chips.add_child(UIKit.chip("Enfermo/a", UIKit.BAD, "health"))
	if not DynastySim.has_heir(gs):
		chips.add_child(UIKit.chip("Sin heredero", UIKit.BAD, "alert"))
	profile.add_child(UIKit.meter_row("health", "Salud", p.health / 100.0))
	profile.add_child(UIKit.meter_row("happiness", "Felicidad", p.happiness / 100.0))
	var money_row := HBoxContainer.new()
	money_row.add_theme_constant_override("separation", 6)
	profile.add_child(money_row)
	for spec in [["money", "Dinero", Fmt.money(gs.money), UIKit.ACCENT], ["finance", "Deudas", Fmt.money(EconomySim.player_debt(gs)), UIKit.BAD if EconomySim.player_debt(gs) > 0 else UIKit.NEUTRAL],
			["treasury", "Patrimonio", Fmt.money_compact(EconomySim.net_worth(gs)), UIKit.GOOD]]:
		var c := UIKit.card(Color(0, 0, 0, 0), 6)
		c["panel"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 4)
		h.add_child(UIKit.icon(spec[0], 14, spec[3]))
		h.add_child(UIKit.label(spec[1], 11, UIKit.TEXT_DIM))
		c["box"].add_child(h)
		c["box"].add_child(UIKit.label(spec[2], 15, (spec[3] as Color).lerp(UIKit.TEXT, 0.3)))
		money_row.add_child(c["panel"])
	var tal := HeirsSim.talents(gs, p)
	if not tal.is_empty():
		var ts := UIKit.section(profile, "Talentos del jefe de familia", "dynasty", true, "pp_talents")
		for k in HeirsSim.TALENTS:
			if tal.has(k):
				ts.add_child(UIKit.meter_row("dynasty", HeirsSim.talent_label(k), float(tal[k]) / 100.0, str(int(tal[k])), false, UIKit.ACCENT))
	var fs := UIKit.section(profile, "Árbol familiar", "family", true, "pp_tree")
	var tree := FamilyTree.new()
	tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fs.add_child(tree)
	tree.set_person(p)
	tree.person_clicked.connect(func(pid): hud.on_meta_clicked(pid))


func _rich(text: String) -> void:
	var r := UIKit.rich()
	r.text = text
	r.meta_clicked.connect(hud.on_meta_clicked)
	actions.add_child(r)


## Familia con talentos y educación (plan y talento a reforzar por hijo/hermano).
func _family_section(p: Citizen) -> void:
	_title("Familia: talentos y educación")
	var gs := GameState
	var members := HeirsSim.family_members(gs)
	if members.is_empty():
		_rich("[color=#999]Aún no tienes familia. Cásate, ten hijos o adopta.[/color]")
		return
	for c in members:
		var e := HeirsSim.edu_of(gs, c)
		var plan := str(e.get("plan", "ninguna"))
		var months: Dictionary = e.get("months", {})
		var studied := []
		for k in months:
			studied.append("%s %d m" % [str(HeirsSim.plan_def(k).get("label", k)).to_lower(), int(months[k])])
		var line := "[b]%s[/b] — %s, %d años · %s\n[color=#aaa]%s[/color]" % [hud.link(c.id), HeirsSim.relation_of(gs, c), c.age_years(gs.today()),
			GameData.education_label(c.education), HeirsSim.talents_text(gs, c)]
		if plan != "ninguna" or not studied.is_empty():
			line += "\n[color=#9cf]Educación: %s%s[/color]" % [HeirsSim.plan_def(plan).get("label", plan), " · cursado: " + ", ".join(studied) if not studied.is_empty() else ""]
		_rich(line)
		if not (p.children_ids.has(c.id) or HeirsSim.siblings(gs, p).has(c)):
			continue
		var row := HBoxContainer.new()
		var opt := OptionButton.new()
		for id in HeirsSim.plan_ids():
			if id != plan and HeirsSim.plan_block_reason(gs, c, id) != "":
				continue
			var fee := HeirsSim.plan_fee(gs, id)
			opt.add_item("%s%s" % [HeirsSim.plan_def(id).get("label", id), " (%s/mes)" % Fmt.money(fee) if fee > 0.0 else ""])
			opt.set_item_metadata(opt.item_count - 1, id)
			if id == plan:
				opt.select(opt.item_count - 1)
		var focus := OptionButton.new()
		for t in HeirsSim.TALENTS:
			focus.add_item(HeirsSim.talent_label(t))
			focus.set_item_metadata(focus.item_count - 1, t)
			if t == str(e.get("focus", "")):
				focus.select(focus.item_count - 1)
		var cid: int = c.id
		var apply := func(_i):
			if GameState.citizens.has(cid) and opt.selected >= 0 and focus.selected >= 0:
				_do(HeirsSim.set_plan(GameState, GameState.citizens[cid], str(opt.get_item_metadata(opt.selected)), str(focus.get_item_metadata(focus.selected))))
		opt.item_selected.connect(apply)
		focus.item_selected.connect(apply)
		row.add_child(UIKit.label("Educación:", 13))
		row.add_child(opt)
		row.add_child(UIKit.label("reforzar:", 13))
		row.add_child(focus)
		actions.add_child(row)


## Orden de herederos: solo el jugador lo decide (subir, bajar, quitar, añadir).
func _heirs_section() -> void:
	_title("Orden de herederos")
	var gs := GameState
	var order := HeirsSim.heir_order(gs)
	if order.is_empty():
		_rich("[color=#aaa]Lista vacía: hereda el heredero designado o el hijo(a) mayor.[/color]")
	var n := 0
	for id in order:
		var iid := int(id)
		if not gs.citizens.has(iid):
			continue
		n += 1
		var c: Citizen = gs.citizens[iid]
		var row := HBoxContainer.new()
		var l := UIKit.label("%d.º %s (%s, %d años)" % [n, c.full_name(), HeirsSim.relation_of(gs, c), c.age_years(gs.today())], 14)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(UIKit.button("▲", func(): HeirsSim.move_heir(GameState, iid, -1); refresh(), 30))
		row.add_child(UIKit.button("▼", func(): HeirsSim.move_heir(GameState, iid, 1); refresh(), 30))
		row.add_child(UIKit.button("✕", func(): _do(HeirsSim.remove_heir(GameState, iid)), 30))
		actions.add_child(row)
	var pool := HeirsSim.heir_pool(gs).filter(func(c): return not order.has(c.id))
	if pool.is_empty():
		return
	var add_row := HBoxContainer.new()
	var opt := OptionButton.new()
	for c in pool:
		opt.add_item("%s (%s)" % [c.full_name(), HeirsSim.relation_of(gs, c)])
		opt.set_item_metadata(opt.item_count - 1, c.id)
	add_row.add_child(opt)
	add_row.add_child(UIKit.button("Añadir a la lista", func(): _do(HeirsSim.add_heir(GameState, int(opt.get_item_metadata(opt.selected))))))
	actions.add_child(add_row)


## Propuestas de matrimonio con ficha de patrimonio (tuyas y de tus hijos/hermanos).
func _marriage_section(p: Citizen) -> void:
	_title("Matrimonio y alianzas")
	var gs := GameState
	if p.spouse_id < 0:
		var rel: Dictionary = gs.player.get("relations", {})
		var ids := rel.keys()
		ids.sort_custom(func(a, b): return float(rel[a]) > float(rel[b]))
		var shown := 0
		for k in ids:
			var c: Citizen = gs.citizens.get(int(k))
			if c == null or PlayerSim.can_court(gs, c) != "" or shown >= 4:
				continue
			shown += 1
			var ch := MarriageSim.proposal_chance(gs, c)
			_rich("[b]%s[/b] (%d años) — %s\n%s" % [hud.link(c.id), c.age_years(gs.today()), PlayerSim.relation_label(gs, c), MarriageSim.sheet_text(gs, c)])
			var cid: int = c.id
			actions.add_child(UIKit.button("Proponerle matrimonio (≈%d%%)" % int(ch * 100.0), func(): _do(MarriageSim.propose(GameState, GameState.citizens[cid]))))
		if shown == 0:
			_rich("[color=#999]Conoce gente soltera (clic en una persona → Conversar) para ver su ficha y proponer.[/color]")
	for m in MarriageSim.marriageable_relatives(gs):
		var cands := MarriageSim.strategic_candidates(gs, m)
		_rich("[b]Casar a %s[/b] (%d años)" % [hud.link(m.id), m.age_years(gs.today())])
		var mid: int = m.id
		if not cands.is_empty():
			var t0: Citizen = cands[0]
			_rich(MarriageSim.sheet_text(gs, t0))
			var row := HBoxContainer.new()
			var opt := OptionButton.new()
			for c in cands:
				opt.add_item("%s (%d) · familia %s" % [c.full_name(), c.age_years(gs.today()), Fmt.money(MarriageSim.family_wealth(gs, c))])
				opt.set_item_metadata(opt.item_count - 1, c.id)
			var dowry := CheckBox.new()
			dowry.text = "Pedir dote"
			var merge := CheckBox.new()
			merge.text = "Unir empresas"
			row.add_child(opt)
			row.add_child(dowry)
			row.add_child(merge)
			actions.add_child(row)
			actions.add_child(UIKit.button("Proponer a su familia", func():
				var tid := int(opt.get_item_metadata(opt.selected))
				if GameState.citizens.has(tid) and GameState.citizens.has(mid):
					_do(MarriageSim.arrange(GameState, GameState.citizens[mid], GameState.citizens[tid], dowry.button_pressed, merge.button_pressed))))
		if not MarriageSim.foreign_towns(gs).is_empty():
			actions.add_child(UIKit.button("Buscar pareja en otro pueblo (boda %s, ≈%d%%)" % [Fmt.money(MarriageSim.foreign_cost(gs)), int(MarriageSim.foreign_chance(gs, m) * 100.0)],
				func(): _do(MarriageSim.arrange_foreign(GameState, GameState.citizens[mid]))))


## Política: facciones/campañas, cargos, lobby y escándalos.
func _politics_section() -> void:
	_title("Política")
	var gs := GameState
	var st := PoliticsSim.state(gs)
	var s := "Reputación de la familia: %d/100 · Corrupción: %d (riesgo de escándalo %.1f%%/mes) · Escándalos: %d\n" % [int(PoliticsSim.reputation(gs)), int(PoliticsSim.corruption(gs)), PoliticsSim.scandal_chance(gs) * 100.0, int(st["scandals"])]
	for o in st["offices"]:
		var d := PoliticsSim.office_def(str(o["office"]))
		s += "• %s es %s hasta %s (sueldo %s/mes, −%s impuesto)\n" % [hud.link(int(o["cid"])), str(d.get("label", "")).to_lower(), TimeManager.date_from_day(int(o["until"]), TimeManager.start_year()),
			Fmt.money(float(d.get("salary", 0)) * gs.price_mult()), Fmt.pct(float(d.get("tax_cut", 0)) * 100.0)]
	for c in st["campaigns"]:
		s += "• En campaña: %s para %s (elección el %s)\n" % [hud.link(int(c["cid"])), str(PoliticsSim.office_def(str(c["office"])).get("label", "")).to_lower(), TimeManager.date_from_day(int(c["resolve_day"]), TimeManager.start_year())]
	for l in st["lobbies"]:
		s += "• %s: %s hasta %s%s\n" % ["Rebaja de impuesto" if str(l["kind"]) == "impuesto" else "Licencia", str(l["target"]), TimeManager.date_from_day(int(l["until"]), TimeManager.start_year()), " [color=#e88](soborno)[/color]" if bool(l.get("bribe", false)) else ""]
	_rich(s)
	# Facciones o campañas.
	var amount: float = snappedf(100.0 * gs.price_mult(), 1.0)
	var sup := PoliticsSim.supportable(gs)
	if not sup.is_empty():
		var fc := PoliticsSim.faction_chance(gs)
		_rich("[color=#aaa]%s[/color]" % ("Financia una campaña: cada aporte suma votos." if PoliticsSim.is_election(gs) else "Financia una facción ante la Corona: más probable que llegue al poder en el próximo cambio (ahora %d%%)." % int(float(fc["chance"]) * 100.0)))
		var frow := HFlowContainer.new()
		for g in sup:
			var gid := str(g)
			frow.add_child(UIKit.button("%s (%s)" % [GovSim.cfg()["governments"][gid].get("label", gid), Fmt.money(amount)], func(): _do(PoliticsSim.fund(GameState, gid, amount))))
		actions.add_child(frow)
	# Cargos.
	var people := [gs.player_citizen()]
	people.append_array(HeirsSim.family_members(gs))
	for c in people:
		for office in PoliticsSim.offices_available(gs):
			var off := str(office)
			if PoliticsSim.can_run(gs, c, off) != "":
				continue
			var cid: int = c.id
			var cost := PoliticsSim.campaign_cost(gs, off)
			actions.add_child(UIKit.button("Postular a %s como %s (campaña %s, ≈%d%%)" % [c.first_name, str(PoliticsSim.office_def(off).get("label", off)).to_lower(),
				Fmt.money(cost), int(PoliticsSim.win_chance(gs, c, off, cost) * 100.0)],
				func(): _do(PoliticsSim.run_for_office(GameState, GameState.citizens[cid], off))))
	# Lobby.
	var targets := []
	for sec in PoliticsSim.player_sectors(gs):
		if PoliticsSim.active_lobby(gs, "impuesto", sec).is_empty():
			targets.append(["impuesto", sec, "Bajar impuesto al sector %s" % sec])
	if not PoliticsSim.has_license(gs, "ambiental"):
		targets.append(["licencia", "ambiental", "Licencia ambiental (sin multas)"])
	if not targets.is_empty():
		_rich("[color=#aaa]Lobby: legal (%d%%) o soborno (%d%%, más barato pero suma corrupción y riesgo de escándalo).[/color]" % [int(PoliticsSim.lobby_chance(gs, false) * 100.0), int(PoliticsSim.lobby_chance(gs, true) * 100.0)])
	for t in targets:
		var kind := str(t[0])
		var target := str(t[1])
		var row := HBoxContainer.new()
		var l := UIKit.label(str(t[2]), 13)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(UIKit.button("Legal %s" % Fmt.money(PoliticsSim.lobby_cost(gs, kind, false)), func(): _do(PoliticsSim.lobby(GameState, kind, target, false))))
		row.add_child(UIKit.button("Soborno %s" % Fmt.money(PoliticsSim.lobby_cost(gs, kind, true)), func(): _do(PoliticsSim.lobby(GameState, kind, target, true))))
		actions.add_child(row)
	var hist: Array = st["log"]
	if not hist.is_empty():
		var txt := "[color=#aaa]Últimos hechos:[/color]\n"
		for i in range(hist.size() - 1, maxi(-1, hist.size() - 6), -1):
			txt += "• %s\n" % str(hist[i]["text"])
		_rich(txt)
