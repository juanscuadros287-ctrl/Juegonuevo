class_name FleetTab
extends RefCounted
## Flota de una estación de transporte (Central de transporte, Caballeriza, Depósito de camiones,
## Hangar): comprar y vender vehículos individuales, surtidor de combustible y estado de cada
## vehículo. La usan el panel de Logística (pestaña Transporte) y el panel de edificio
## (pestaña "Vehículos"). `on_change` se llama después de comprar/vender para refrescar.


static func applies(gs, b: Dictionary) -> bool:
	return gs.owned_by_player(b) and gs.level_def(b).has("transport_modes")


static func build(gs, st: Dictionary, hud, on_change: Callable) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	var sid := int(st["id"])
	var ld: Dictionary = gs.level_def(st)
	var modes: Array = ld.get("transport_modes", [])
	var crew := LogisticsSim.crew_size(gs, st)
	var head := "%s (%s) — %d empleados" % [gs.building_label(st), str(ld.get("label", "")), crew]
	if LogisticsSim.garage_capacity(gs, st) > 0:
		head += " · %d/%d vehículos comprados" % [LogisticsSim.bought_vehicles(gs, st), LogisticsSim.garage_capacity(gs, st)]
	v.add_child(UIKit.label(head, 14, UIKit.ACCENT))
	if str(st.get("status", "")) != "activo":
		v.add_child(UIKit.label("En obra: aún no opera.", 12, UIKit.TEXT_DIM))
	var pm: float = gs.price_mult()
	for m in modes:
		var mode := str(m)
		var md := LogisticsSim.mode_def(mode)
		if not LogisticsSim.is_vehicle(mode):
			v.add_child(_note("%s: %d disponibles (cada empleado lleva %d u. por viaje)." % [LogisticsSim.mode_label(mode), crew, int(md.get("capacity", 10))]))
			continue
		var inc := LogisticsSim.included_at(gs, st, mode)
		if inc > 0:
			v.add_child(_note("%s incluidos con el nivel: %d (%d u./viaje)." % [LogisticsSim.mode_label(mode), inc, int(md.get("capacity", 0))]))
		if str(st.get("type", "")) != LogisticsSim.mode_base(mode):
			continue
		var cost_txt := "%s %s/día" % ["alimento" if bool(md.get("animal", false)) else "mant.", Fmt.money2(float(md.get("upkeep", 0.0)) * pm)]
		if float(md.get("fuel_per_km", 0.0)) > 0.0:
			cost_txt += " · combustible %s/km" % Fmt.money2(float(md["fuel_per_km"]) * pm)
		var row := HBoxContainer.new()
		var l := UIKit.label("%s: %d u./viaje · %s%s" % [str(md.get("unit", mode)), int(md.get("capacity", 0)), cost_txt,
				" · PREVISTO (fase posterior)" if LogisticsSim.is_planned(mode) else ""], 13)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(l)
		var reason := LogisticsSim.buy_block_reason(gs, st, mode)
		var btn := UIKit.button("Comprar (%s)" % Fmt.money(LogisticsSim.vehicle_price(gs, mode)), func():
			var r := LogisticsSim.buy_vehicle(GameState, GameState.get_building(sid), mode)
			if hud:
				hud.toast(str(r["error"]) if r.has("error") else "Compraste: %s." % str(r["vehicle"]["name"]), "jugador" if r.has("error") else "negocio")
			on_change.call(), 140)
		btn.disabled = reason != ""
		btn.tooltip_text = reason
		row.add_child(btn)
		v.add_child(row)
	if LogisticsSim.fuel_pump_price(gs, st) > 0.0:
		if bool(st.get("fuel_pump", false)):
			v.add_child(_note("Surtidor propio instalado: combustible %d%% más barato." % int(LogisticsSim.fuel_discount(gs, st) * 100.0)))
		else:
			var pb := UIKit.button("Instalar surtidor de combustible (%s): −%d%% combustible" % [Fmt.money(LogisticsSim.fuel_pump_price(gs, st)),
					int(float(ld.get("fuel_pump_discount", 0.0)) * 100.0)], func():
				var err := LogisticsSim.buy_fuel_pump(GameState, GameState.get_building(sid))
				if hud:
					hud.toast(err if err != "" else "Surtidor instalado.", "jugador" if err != "" else "negocio")
				on_change.call())
			pb.disabled = gs.money < LogisticsSim.fuel_pump_price(gs, st)
			v.add_child(pb)
	var now: float = float(gs.today()) + TimeManager.hour_float() / 24.0
	for veh in LogisticsSim.vehicles_of(gs, sid):
		var vid := int(veh["id"])
		var row := HBoxContainer.new()
		var busy := LogisticsSim.vehicle_busy(gs, vid, now)
		var rnames := []
		for r in LogisticsSim.routes(gs):
			if int(r.get("vehicle", -1)) == vid:
				rnames.append("%s→%s" % [LogisticsSim.endpoint_label(gs, int(r["from"])).get_slice(" (", 0), LogisticsSim.endpoint_label(gs, int(r["to"])).get_slice(" (", 0)])
		var l := UIKit.label("• %s — %s · %d viajes · %.1f km%s" % [str(veh["name"]), "de viaje" if busy else "libre", int(veh.get("trips", 0)), float(veh.get("km", 0.0)),
				" · rutas: " + ", ".join(rnames) if not rnames.is_empty() else " · sin ruta"], 13, Color(0.95, 0.8, 0.45) if busy else Color(0.75, 0.95, 0.75))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		row.add_child(l)
		var sell := UIKit.button("Vender", func():
			var err := LogisticsSim.sell_vehicle(GameState, vid)
			if hud:
				hud.toast(err if err != "" else "Vehículo vendido (40 % de su precio).", "jugador" if err != "" else "negocio")
			on_change.call(), 70)
		sell.disabled = busy
		row.add_child(sell)
		v.add_child(row)
	return v


static func _note(text: String) -> Label:
	var l := UIKit.label(text, 12, UIKit.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 360
	return l
