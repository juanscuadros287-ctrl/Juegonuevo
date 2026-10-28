class_name PartnersTab
extends RefCounted
## Pestaña «Socios» del panel de edificio (docs/SOCIAL.md): socios del negocio, su parte y lo que
## han cobrado, su satisfacción, comprar o vender participación, resolver desacuerdos y traer socios.


static func applies(gs, b: Dictionary) -> bool:
	return PartnersSim.business_ok(gs, b)


static func build(gs, b: Dictionary, hud, on_change: Callable) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	var bid := int(b["id"])
	var partners := PartnersSim.partners_of(gs, b)
	var total := PartnersSim.total_share(gs, b)
	var head := UIKit.flow(6, 4)
	v.add_child(head)
	head.add_child(UIKit.chip("Tu parte: %d %%" % int(round((1.0 - total) * 100.0)), UIKit.ACCENT, "character"))
	head.add_child(UIKit.chip("Socios: %d (%d %%)" % [partners.size(), int(round(total * 100.0))], Color(0.72, 0.62, 0.98), "handshake"))
	head.add_child(UIKit.chip("Valor: %s" % Fmt.money_compact(PartnersSim.valuation(gs, b)), UIKit.ACCENT_2, "treasury"))
	var mult := PartnersSim.output_mult(gs, b)
	if not is_equal_approx(mult, 1.0):
		head.add_child(UIKit.chip("Producción %+d %%" % int(round((mult - 1.0) * 100.0)), UIKit.GOOD if mult > 1.0 else UIKit.BAD, "trend_up" if mult > 1.0 else "trend_down"))
	var note := UIKit.label("Los socios aportan capital (dinero) o habilidades (más producción) y cobran su parte de la utilidad de cada mes. Tú conservas siempre al menos el 51 %.", 12, UIKit.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 360
	v.add_child(note)
	var msg := func(t: String):
		if hud != null and t != "":
			hud.toast(t, "negocio")
		on_change.call()
	for p in partners:
		var pid := int(p["id"])
		var c: Citizen = gs.citizens.get(int(p["cid"]))
		var dispute := not (p["dispute"] as Dictionary).is_empty()
		var card := UIKit.card(UIKit.WARN if dispute else Color(0.72, 0.62, 0.98), 8)
		v.add_child(card["panel"])
		var box: VBoxContainer = card["box"]
		var top := HBoxContainer.new()
		box.add_child(top)
		var nm := UIKit.label(c.full_name() if c != null else "—", 15, UIKit.ACCENT)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(nm)
		if c != null:
			var cid := c.id
			top.add_child(UIKit.icon_button("eye", func(): EventBus.citizen_selected.emit(cid), "Ver su ficha", "", 14))
		box.add_child(UIKit.label("%s · %d %% de utilidades · aportó %s · cobrado %s (último mes %s)" % [str(PartnersSim.KIND_LABELS.get(str(p["kind"]), "")), int(round(float(p["share"]) * 100.0)),
			Fmt.money(float(p["capital"])) if float(p["capital"]) > 0.0 else "experiencia", Fmt.money(float(p["paid"])), Fmt.money(float(p["last_pay"]))], 12, UIKit.TEXT_DIM))
		box.add_child(UIKit.meter_row("happiness", "Satisfacción", float(p["sat"]) / 100.0, str(int(p["sat"]))))
		if dispute:
			box.add_child(UIKit.label(PartnersSim.dispute_text(gs, p), 13, UIKit.WARN))
			var dr := UIKit.flow(4, 4)
			box.add_child(dr)
			dr.add_child(UIKit.button("Negociar (≈%d %%)" % int(PartnersSim.negotiate_chance(gs, p) * 100.0), func(): msg.call(PartnersSim.resolve(GameState, pid, "negociar"))))
			var comp := PartnersSim.compensation(gs, p)
			var cb := UIKit.button("Compensar (%s)" % Fmt.money(comp), func(): msg.call(PartnersSim.resolve(GameState, pid, "compensar")))
			cb.disabled = gs.money < comp
			dr.add_child(cb)
			var ce := UIKit.button("Ceder %d %%" % int(round(float(PartnersSim.cfg().get("cede_share", 0.03)) * 100.0)), func(): msg.call(PartnersSim.resolve(GameState, pid, "ceder")))
			ce.disabled = PartnersSim.room(gs, b) <= 0.0
			dr.add_child(ce)
			dr.add_child(UIKit.danger(UIKit.button("Ignorar", func(): msg.call(PartnersSim.resolve(GameState, pid, "ignorar")))))
		var row := UIKit.flow(4, 4)
		box.add_child(row)
		var price := PartnersSim.buyout_price(gs, p)
		var bb := UIKit.button("Comprar su parte (%s)" % Fmt.money(price), func(): msg.call(PartnersSim.buy_out(GameState, pid, 1.0)))
		bb.disabled = gs.money < price
		row.add_child(bb)
		var low := UIKit.button("Ofrecer 85 %% (%s)" % Fmt.money(price * 0.85), func(): msg.call(PartnersSim.buy_out(GameState, pid, 0.85)))
		low.disabled = gs.money < price * 0.85
		row.add_child(low)
		var extra := minf(0.05, PartnersSim.room(gs, b))
		if extra >= 0.01:
			var sb := UIKit.button("Venderle %d %% más (%s)" % [int(round(extra * 100.0)), Fmt.money(PartnersSim.sell_price(gs, p, extra))], func(): msg.call(PartnersSim.sell_more(GameState, pid, extra)))
			sb.disabled = c == null or c.money < PartnersSim.sell_price(gs, p, extra)
			row.add_child(sb)
	if partners.is_empty():
		v.add_child(UIKit.label("Este negocio aún no tiene socios.", 13, UIKit.TEXT_DIM))
	var add := UIKit.primary(UIKit.button("Traer un socio…", func():
		if hud != null and hud.get("social_ui") != null:
			hud.social_ui.open_partner_picker(bid)))
	add.disabled = PartnersSim.room(gs, b) < PartnersSim.min_share() or partners.size() >= int(PartnersSim.cfg().get("max_per_business", 3))
	v.add_child(add)
	var lg: Array = PartnersSim.state(gs)["log"] if gs.player.has("socios") else []
	var mine := lg.filter(func(t): return str(t).contains(gs.building_label(b)))
	if not mine.is_empty():
		v.add_child(UIKit.label("Historial", 13, UIKit.ACCENT))
		for t in mine.slice(maxi(0, mine.size() - 5)):
			var l := UIKit.label("• " + str(t), 12, UIKit.TEXT_DIM)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = 360
			v.add_child(l)
	return v
