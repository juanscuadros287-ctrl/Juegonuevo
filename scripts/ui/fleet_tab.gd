class_name FleetTab
extends RefCounted
## Vehículos de una compañía (pestaña "Vehículos" del edificio y panel de Logística). Rutas y barcos
## (docs/RUTAS_BARCOS.md): la compra, la venta y la asignación se hacen en el panel central «Vehículos»;
## aquí se ven los vehículos que tienen su parqueadero en este negocio, su cupo (módulo Flota), el
## surtidor de combustible y un botón para abrir el panel. `on_change` refresca tras un cambio.


static func applies(gs, b: Dictionary) -> bool:
	return gs.owned_by_player(b) and (gs.level_def(b).has("transport_modes") or not LogisticsSim.vehicles_of(gs, int(b["id"])).is_empty())


static func build(gs, st: Dictionary, hud, on_change: Callable) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	var sid := int(st["id"])
	var ld: Dictionary = gs.level_def(st)
	var crew := LogisticsSim.crew_size(gs, st)
	v.add_child(UIKit.label("%s (%s) — %d empleados · %d vehículos" % [gs.building_label(st), str(ld.get("label", "")), crew, LogisticsSim.vehicles_of(gs, sid).size()], 14, UIKit.ACCENT))
	if str(st.get("status", "")) != "activo":
		v.add_child(UIKit.label("En obra: aún no opera.", 12, UIKit.TEXT_DIM))
	var caps := []
	for t in FleetSim.fleet_types(gs, st):
		var lim := FleetSim.fleet_limit(gs, st, str(t))
		if lim > 0:
			caps.append("%s %d/%d" % [VehicleCatalog.tipo_label(str(t)).to_lower(), FleetSim.used(gs, st, str(t)), lim])
	if not caps.is_empty():
		v.add_child(_note("Cupos del parqueadero (módulo Flota): " + " · ".join(caps)))
	for m in ld.get("transport_modes", []):
		var mode := str(m)
		if not LogisticsSim.is_vehicle(mode):
			v.add_child(_note("%s: %d disponibles (cada empleado lleva %d u. por viaje)." % [LogisticsSim.mode_label(mode), crew, int(LogisticsSim.mode_def(mode).get("capacity", 10))]))
		elif LogisticsSim.included_at(gs, st, mode) > 0:
			v.add_child(_note("%s incluidos con el nivel: %d." % [LogisticsSim.mode_label(mode), LogisticsSim.included_at(gs, st, mode)]))
	var open := UIKit.primary(UIKit.button("Comprar, vender y asignar en el panel Vehículos", func():
		if hud and hud.get("root"):
			RoutesWindow.open_in(hud, "vehicles")))
	v.add_child(open)
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
		var busy := LogisticsSim.vehicle_busy(gs, int(veh["id"]), now)
		var extra := ""
		if VehicleCatalog.is_train(str(veh["mode"])):
			extra = " · " + VehicleCatalog.comp_text(VehicleCatalog.comp_of(veh))
		var why := FleetSim.base_reason(gs, st, str(veh["mode"]))
		var l := UIKit.label("• %s (%s) — %s · %d u. · %d viajes · %.1f km%s%s" % [str(veh["name"]), LogisticsSim.mode_label(str(veh["mode"])), "de viaje" if busy else "libre",
				int(LogisticsSim.vehicle_capacity(gs, veh)), int(veh.get("trips", 0)), float(veh.get("km", 0.0)), extra, " · " + why if why != "" else ""], 13,
				UIKit.BAD if why != "" else (Color(0.95, 0.8, 0.45) if busy else Color(0.75, 0.95, 0.75)))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)
	return v


static func _note(text: String) -> Label:
	var l := UIKit.label(text, 12, UIKit.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 360
	return l
