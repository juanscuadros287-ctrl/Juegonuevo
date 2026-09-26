class_name AirSim
extends RefCounted
## Fase 10 — Aviones, aeropuertos y carga entre países (docs/FASE10.md).
## - El Aeropuerto (businesses_comercio.json) es un almacén grande (warehouse_capacity 3000/8000): los
##   camiones distribuyen desde ahí con las rutas de la Fase 6 (Logística → Transporte).
## - Hangar: se compran aviones de carga (LogisticsSim.buy_vehicle). Dentro del país vuelan entre
##   aeropuertos con las rutas de la Fase 6 (medio "avion"; `domestic_block_reason`). Entre países vuelan
##   con `ship` (manual) o con rutas automáticas de este sistema.
## - Vuelo comercial: sin aviones propios; se paga por unidad (según la distancia) y cada salida tiene
##   capacidad limitada. Sirve dentro del país y entre países.
## - ENTRE PAÍSES LA MERCANCÍA SOLO VA POR AVIÓN (propio o comercial). Al llegar se cobra el arancel del
##   destino (el mayor entre el tariff del país y import_mult de su gobierno − 1) sobre el valor del bien en el destino,
##   convertido a su moneda con el tipo de cambio de GlobalEconSim; se paga en tu moneda y va al tesoro
##   del destino. Combustible y fletes comerciales salen de la economía (proveedor extranjero).
## Estado: countries.air = {flights [], routes [], commercial {"de|a|día": usado}, next_id, stats {}}

const MODES_INTL := ["avion", "comercial"]


static func cfg() -> Dictionary:
	return CountriesSim.cfg().get("air", {})


static func init_state(gs) -> void:
	var a: Dictionary = gs.countries.get("air", {})
	for k in ["flights", "routes"]:
		if not (a.get(k) is Array):
			a[k] = []
	if not (a.get("commercial") is Dictionary):
		a["commercial"] = {}
	if not (a.get("stats") is Dictionary):
		a["stats"] = {}
	for k in ["tariffs", "fuel", "fees", "flights", "units"]:
		a["stats"][k] = float(a["stats"].get(k, 0.0))
	a["next_id"] = int(a.get("next_id", 1))
	gs.countries["air"] = a


static func st(gs) -> Dictionary:
	return gs.countries.get("air", {})


# --- Aeropuertos, almacenes y flota (del país cargado o de otro) ------------------------------------

static func is_airport(gs, id: int) -> bool:
	var b: Dictionary = gs.get_building(id)
	return not b.is_empty() and str(b.get("type", "")) == "aeropuerto" and gs.owned_by_player(b) and gs.is_active(b)


static func airports(gs) -> Array:
	var out := []
	for b in gs.buildings:
		if str(b.get("type", "")) == "aeropuerto" and gs.owned_by_player(b) and gs.is_active(b):
			out.append(b)
	return out


## Rutas de avión de la Fase 6 (dentro del país): solo entre aeropuertos tuyos.
static func domestic_block_reason(gs, from_id: int, to_id: int) -> String:
	if not is_airport(gs, from_id) or not is_airport(gs, to_id):
		return "Los aviones vuelan entre aeropuertos: origen y destino deben ser aeropuertos tuyos activos"
	return ""


static func _muni(gs, b: Dictionary) -> String:
	var r := MapSim.region_at(gs, float(b["x"]), float(b["z"]))
	return str(r.get("name", ""))


## [{id, label, municipio, stock, capacity}] de los aeropuertos del jugador en el país.
static func airports_in(gs, iso: String) -> Array:
	var r = CountriesSim.with_country(gs, iso, func() -> Array:
		var out := []
		for b in airports(gs):
			var id := int(b["id"])
			out.append({"id": id, "label": gs.building_label(b), "municipio": _muni(gs, b),
					"stock": WarehouseSim.used_in(gs, id), "capacity": WarehouseSim.capacity_of(gs, id)})
		return out)
	return r if r is Array else []


## Almacenes del país (bodega de la plaza, almacenes y aeropuertos): [{id, label}].
static func warehouses_in(gs, iso: String) -> Array:
	var r = CountriesSim.with_country(gs, iso, func() -> Array:
		var out := []
		for id in LogisticsSim.endpoints(gs):
			if LogisticsSim.is_warehouse_endpoint(gs, int(id)):
				out.append({"id": int(id), "label": LogisticsSim.endpoint_label(gs, int(id))})
		return out)
	return r if r is Array else []


## Aviones del país: [{id, name, base, busy}].
static func planes_in(gs, iso: String) -> Array:
	var now := float(gs.today()) + TimeManager.hour_float() / 24.0
	var r = CountriesSim.with_country(gs, iso, func() -> Array:
		var out := []
		for v in LogisticsSim.vehicles(gs):
			if str(v.get("mode", "")) == "avion":
				out.append({"id": int(v["id"]), "name": str(v.get("name", "Avión")), "base": int(v["base"]),
						"busy": LogisticsSim.vehicle_busy(gs, int(v["id"]), now), "km": float(v.get("km", 0.0)), "trips": int(v.get("trips", 0))})
		return out)
	return r if r is Array else []


## Hangares activos del país: [{id, label, planes, garage}].
static func hangars_in(gs, iso: String) -> Array:
	var r = CountriesSim.with_country(gs, iso, func() -> Array:
		var out := []
		for b in LogisticsSim.stations(gs):
			if str(b.get("type", "")) == "hangar":
				out.append({"id": int(b["id"]), "label": gs.building_label(b), "planes": LogisticsSim.vehicles_of(gs, int(b["id"]), "avion").size(),
						"garage": LogisticsSim.garage_capacity(gs, b), "crew": LogisticsSim.crew_size(gs, b)})
		return out)
	return r if r is Array else []


## Compra un avión de carga en un hangar del país.
static func buy_plane(gs, iso: String, hangar_id: int) -> String:
	var r = CountriesSim.with_country(gs, iso, func():
		var h: Dictionary = gs.get_building(hangar_id)
		if h.is_empty():
			return "Ese hangar no existe"
		var reason := CountriesSim.control_block_reason(gs)
		if reason != "":
			return reason
		var res := LogisticsSim.buy_vehicle(gs, h, "avion")
		return str(res.get("error", "")))
	return str(r) if r != null else "Sin presencia en ese país"


# --- Precios, aranceles y cambio ------------------------------------------------------------------

## Arancel (fracción) de la carga que entra al país: el mayor entre el arancel base del país
## (fase10.json) y la política de importación de su gobierno (GovSim.import_mult − 1).
static func tariff_rate(gs, iso: String) -> float:
	var r = CountriesSim.with_country(gs, iso, func(): return maxf(0.0, GovSim.import_mult(gs) - 1.0))
	return maxf(float(CountriesSim.mods(iso).get("tariff", 0.1)), float(r if r != null else 0.0))


static func _home_pm(gs) -> float:
	var r = CountriesSim.with_country(gs, CountriesSim.home_id(gs), func(): return gs.price_mult())
	return float(r) if r != null else float(gs.price_mult())


## Distancia de un envío: km reales entre países o km del juego entre dos puntos del mismo país.
static func distance(gs, from_iso: String, from_id: int, to_iso: String, to_id: int) -> float:
	if from_iso != to_iso:
		return TravelSim.distance_km(from_iso, to_iso)
	var r = CountriesSim.with_country(gs, from_iso, func():
		return LogisticsSim.endpoint_pos(gs, from_id).distance_to(LogisticsSim.endpoint_pos(gs, to_id)) / 1000.0)
	return float(r) if r != null else 0.0


static func flight_days(km: float, intl: bool) -> int:
	if not intl:
		return 1
	return maxi(1, int(ceil(km / maxf(100.0, float(cfg().get("plane_km_per_day", 6000))))))


## Flete comercial por unidad.
static func commercial_unit_fee(gs, km: float, intl: bool) -> float:
	var c: Dictionary = cfg().get("commercial", {})
	var base := float(c.get("per_unit_base", 0.5)) + float(c.get("per_unit_per_1000km", 0.7)) * km / 1000.0 if intl \
			else float(c.get("domestic_per_unit", 0.35)) + float(c.get("domestic_per_km", 0.05)) * km
	return snappedf(base * _home_pm(gs), 0.01)


## Próxima salida comercial con espacio: {day, free}.
static func commercial_slot(gs, from_iso: String, to_iso: String, from_day := -1) -> Dictionary:
	var c: Dictionary = cfg().get("commercial", {})
	var every := maxi(1, int(c.get("every_days", 3)))
	var cap := float(c.get("capacity", 150))
	var day: int = from_day if from_day >= 0 else gs.today()
	var dep := int(ceil(float(day) / every)) * every
	for i in range(6):
		var used := float(st(gs)["commercial"].get("%s|%s|%d" % [from_iso, to_iso, dep], 0.0))
		if used < cap - 0.01:
			return {"day": dep, "free": cap - used}
		dep += every
	return {"day": dep, "free": 0.0}


static func plane_fuel(gs, km: float) -> float:
	return snappedf(km * float(cfg().get("intl_fuel_per_km", 0.45)) * float(GameData.extra("trade").get("fuel_price", 1.0)) * _home_pm(gs), 0.01)


# --- Envíos -----------------------------------------------------------------------------------------

## Envía carga. opts: from_iso, from, to_iso, to, good, qty, mode ("avion" propio | "comercial"), vehicle.
## Devuelve {"error"} o {"flight"}.
static func ship(gs, opts: Dictionary) -> Dictionary:
	var from_iso := str(opts.get("from_iso", CountriesSim.current_id()))
	var to_iso := str(opts.get("to_iso", from_iso))
	var from_id := int(opts.get("from", 0))
	var to_id := int(opts.get("to", 0))
	var good := str(opts.get("good", ""))
	var qty := float(opts.get("qty", 0.0))
	var mode := str(opts.get("mode", "comercial"))
	var intl := from_iso != to_iso
	if intl and not MODES_INTL.has(mode):
		return {"error": "Entre países la mercancía solo va por avión (avión propio o vuelo comercial)"}
	if not intl and mode == "avion":
		return {"error": "Dentro del país los aviones propios usan las rutas de Logística → Transporte (entre aeropuertos)"}
	if not MODES_INTL.has(mode):
		return {"error": "Medio desconocido"}
	for iso in [from_iso, to_iso]:
		if not CountriesSim.has_presence(gs, iso):
			return {"error": "No tienes presencia en %s" % CountriesSim.country_label(iso)}
	if not CountriesSim.can_control(gs, from_iso):
		return {"error": "Sin gerente en %s: nadie despacha la carga" % CountriesSim.country_label(from_iso)}
	if not LogisticsSim.transportable_goods().has(good):
		return {"error": "Elige un bien para transportar"}
	if qty <= 0.0:
		return {"error": "La cantidad debe ser mayor que cero"}
	if not gs.has_tech("aviacion"):
		return {"error": "Requiere investigar: %s" % GameData.tech_label("aviacion")}
	var km := distance(gs, from_iso, from_id, to_iso, to_id)
	var days := flight_days(km, intl)
	var fee := 0.0
	var fuel := 0.0
	var vid := int(opts.get("vehicle", -1))
	var depart_day: int = gs.today()
	# Validación en el origen.
	var chk = CountriesSim.with_country(gs, from_iso, func() -> Dictionary:
		if not LogisticsSim.endpoint_valid(gs, from_id) or not LogisticsSim.is_warehouse_endpoint(gs, from_id):
			return {"error": "El origen debe ser un almacén tuyo (bodega, almacén o aeropuerto)"}
		if mode == "avion":
			if not is_airport(gs, from_id):
				return {"error": "El avión propio sale de un aeropuerto tuyo"}
			var now := float(gs.today()) + TimeManager.hour_float() / 24.0
			var pick := -1
			for v in LogisticsSim.vehicles(gs):
				if str(v.get("mode", "")) != "avion" or (vid >= 0 and int(v["id"]) != vid):
					continue
				var h: Dictionary = gs.get_building(int(v["base"]))
				if h.is_empty() or not gs.is_active(h) or LogisticsSim.crew_size(gs, h) <= 0:
					continue
				if not LogisticsSim.vehicle_busy(gs, int(v["id"]), now):
					pick = int(v["id"])
					break
			if pick < 0:
				return {"error": "No hay aviones libres con tripulación en %s (compra uno en un hangar)" % CountriesSim.country_label(from_iso)}
			return {"vehicle": pick, "stock": LogisticsSim.endpoint_stock(gs, from_id, good)}
		return {"stock": LogisticsSim.endpoint_stock(gs, from_id, good)})
	if chk == null or (chk as Dictionary).has("error"):
		return {"error": str((chk as Dictionary).get("error", "Origen inválido")) if chk != null else "Origen inválido"}
	var chk_to = CountriesSim.with_country(gs, to_iso, func() -> String:
		if not LogisticsSim.endpoint_valid(gs, to_id) or not LogisticsSim.is_warehouse_endpoint(gs, to_id):
			return "El destino debe ser un almacén tuyo (bodega, almacén o aeropuerto)"
		if mode == "avion" and not is_airport(gs, to_id):
			return "El avión propio aterriza en un aeropuerto tuyo del destino"
		return "")
	if str(chk_to) != "":
		return {"error": str(chk_to)}
	qty = minf(qty, float(chk["stock"]))
	if qty <= 0.01:
		return {"error": "Sin %s en el origen" % GameData.good_label(good).to_lower()}
	if mode == "avion":
		vid = int(chk["vehicle"])
		qty = minf(qty, float(LogisticsSim.mode_def("avion").get("capacity", 400)))
		fuel = plane_fuel(gs, km * 2.0)   # ida y vuelta (regresa vacío)
		if gs.money < fuel:
			return {"error": "Dinero insuficiente para el combustible (%s)" % Fmt.money(fuel)}
	else:
		var slot := commercial_slot(gs, from_iso, to_iso)
		if float(slot["free"]) <= 0.0:
			return {"error": "Los vuelos comerciales de esa ruta están llenos"}
		qty = minf(qty, float(slot["free"]))
		depart_day = int(slot["day"])
		var unit := commercial_unit_fee(gs, km, intl)
		fee = snappedf(unit * qty, 0.01)
		if gs.money < fee:
			qty = floorf(maxf(0.0, gs.money) / maxf(0.01, unit))
			fee = snappedf(unit * qty, 0.01)
			if qty <= 0.0:
				return {"error": "Dinero insuficiente para el flete (%s por unidad)" % Fmt.money2(unit)}
	# Carga: sale del almacén de origen; el valor declarado es el del mercado de origen.
	var taken_val = CountriesSim.with_country(gs, from_iso, func() -> Array:
		var t := LogisticsSim.endpoint_take(gs, from_id, good, qty)
		var val := t * EconomySim.market_price(gs, good)
		if fuel > 0.0:
			var v := LogisticsSim.get_vehicle(gs, vid)
			var h: Dictionary = gs.get_building(int(v.get("base", -1)))
			if not h.is_empty():
				BusinessSim.pay(gs, h, fuel, "insumos")
			else:
				gs.add_money(-fuel)
			v["km"] = float(v.get("km", 0.0)) + km * 2.0
			v["trips"] = int(v.get("trips", 0)) + 1
			v["air_busy_until"] = float(gs.today()) + 2.0 * days
		return [t, val])
	var taken := float(taken_val[0])
	if fee > 0.0:
		gs.add_money(-fee)
		var ck := "%s|%s|%d" % [from_iso, to_iso, depart_day]
		st(gs)["commercial"][ck] = float(st(gs)["commercial"].get(ck, 0.0)) + taken
	CountriesSim.add_outflow(gs, fee + fuel)
	var a := st(gs)
	var id := int(a["next_id"])
	a["next_id"] = id + 1
	var f := {"id": id, "mode": mode, "from_iso": from_iso, "from": from_id, "to_iso": to_iso, "to": to_id, "good": good,
			"qty": taken, "depart": depart_day, "arrive": depart_day + days, "vehicle": vid, "fee": fee, "fuel": fuel,
			"km": snappedf(km, 0.1), "value_origin": float(taken_val[1]), "delivered": false, "status": "en vuelo" if depart_day <= gs.today() else "esperando salida",
			"route": int(opts.get("route", -1))}
	a["flights"].append(f)
	a["stats"]["fees"] = float(a["stats"]["fees"]) + fee
	a["stats"]["fuel"] = float(a["stats"]["fuel"]) + fuel
	gs.notify("Carga aérea %s: %s %s de %s a %s (%s, llega en %d días)." % ["en avión propio" if mode == "avion" else "en vuelo comercial",
			_num(taken), GameData.good_label(good).to_lower(), CountriesSim.country_label(from_iso), CountriesSim.country_label(to_iso),
			Fmt.money(fee + fuel), depart_day + days - gs.today()], "negocio")
	return {"flight": f}


## Entrega los vuelos que llegan hoy: arancel y cambio en el destino, carga al almacén.
static func _deliver(gs, f: Dictionary) -> void:
	var from_iso := str(f["from_iso"])
	var to_iso := str(f["to_iso"])
	var home := CountriesSim.home_id(gs)
	var intl := from_iso != to_iso
	var qty := float(f["qty"])
	var good := str(f["good"])
	var rate := tariff_rate(gs, to_iso) if intl else 0.0
	var fx_to := GlobalEconSim.fx(gs, home, to_iso)       # unidades de la moneda del destino por 1 de la tuya
	var res = CountriesSim.with_country(gs, to_iso, func() -> Dictionary:
		var value_dest := qty * EconomySim.market_price(gs, good)   # en tu dinero, a precios del destino
		var value_local := value_dest * fx_to
		var tariff_local := value_local * rate
		var tariff_money := tariff_local / maxf(0.000001, fx_to)
		if tariff_money > 0.0:
			gs.add_money(-tariff_money)
			GovSim.add_treasury(gs, tariff_money)   # Aduana: al tesoro del país de destino.
		var put := LogisticsSim.endpoint_put(gs, int(f["to"]), good, qty)
		var rest := qty - put
		if rest > 0.01:
			rest -= LogisticsSim.endpoint_put(gs, 0, good, rest)   # lo que no cabe queda en la bodega de la plaza
		return {"value_dest": value_dest, "value_local": value_local, "tariff_local": tariff_local, "tariff_money": tariff_money, "lost": maxf(0.0, rest)})
	var r: Dictionary = res if res is Dictionary else {}
	f["delivered"] = true
	f["status"] = "entregado"
	f["tariff_rate"] = rate
	f["fx"] = fx_to
	for k in ["value_dest", "value_local", "tariff_local", "tariff_money", "lost"]:
		f[k] = float(r.get(k, 0.0))
	var a := st(gs)
	a["stats"]["tariffs"] = float(a["stats"]["tariffs"]) + float(f["tariff_money"])
	a["stats"]["flights"] = float(a["stats"]["flights"]) + 1.0
	a["stats"]["units"] = float(a["stats"]["units"]) + qty
	var txt := "Llegó la carga aérea a %s: %s %s" % [CountriesSim.country_label(to_iso), _num(qty), GameData.good_label(good).to_lower()]
	if intl:
		txt += ". Arancel %d %%: %s %s (%s)" % [int(rate * 100.0), _num(snappedf(float(f["tariff_local"]), 0.01)), GlobalEconSim.currency_symbol(to_iso), Fmt.money2(float(f["tariff_money"]))]
	if float(f["lost"]) > 0.0:
		txt += ". Sin espacio: se perdieron %s" % _num(float(f["lost"]))
	gs.notify(txt + ".", "negocio")


static func daily(gs) -> void:
	if not CountriesSim.ready(gs):
		return
	var a := st(gs)
	if a.is_empty():
		return
	var today: int = gs.today()
	for f in a["flights"]:
		if bool(f.get("delivered", false)):
			continue
		if today >= int(f["arrive"]):
			_deliver(gs, f)
		elif today >= int(f["depart"]):
			f["status"] = "en vuelo"
	# Guarda solo los últimos vuelos entregados.
	var keep := []
	var done := []
	for f in a["flights"]:
		(done if bool(f.get("delivered", false)) else keep).append(f)
	a["flights"] = done.slice(maxi(0, done.size() - 30)) + keep
	for k in a["commercial"].keys():
		if int(str(k).get_slice("|", 2)) < today:
			a["commercial"].erase(k)
	for r in a["routes"]:
		if not bool(r.get("active", true)) or today < int(r.get("next_day", 0)):
			continue
		var res := ship(gs, {"from_iso": r["from_iso"], "from": r["from"], "to_iso": r["to_iso"], "to": r["to"], "good": r["good"],
				"qty": r["qty"], "mode": r["mode"], "vehicle": r.get("vehicle", -1), "route": r["id"]})
		if res.has("error"):
			r["status"] = str(res["error"])
			r["next_day"] = today + 1
		else:
			r["status"] = "Envío %d en camino (%s)" % [int(res["flight"]["id"]), _num(float(res["flight"]["qty"]))]
			r["trips"] = int(r.get("trips", 0)) + 1
			r["next_day"] = today + maxi(1, int(r.get("every", 7)))


# --- Rutas automáticas entre países -------------------------------------------------------------------

static func create_route(gs, opts: Dictionary) -> Dictionary:
	var from_iso := str(opts.get("from_iso", ""))
	var to_iso := str(opts.get("to_iso", ""))
	var mode := str(opts.get("mode", "comercial"))
	if from_iso != to_iso and not MODES_INTL.has(mode):
		return {"error": "Entre países la mercancía solo va por avión (avión propio o vuelo comercial)"}
	if from_iso == to_iso and mode != "comercial":
		return {"error": "Dentro del país usa las rutas de Logística → Transporte (aviones entre aeropuertos)"}
	if float(opts.get("qty", 0.0)) <= 0.0 or not LogisticsSim.transportable_goods().has(str(opts.get("good", ""))):
		return {"error": "Elige un bien y una cantidad"}
	var a := st(gs)
	var id := int(a["next_id"])
	a["next_id"] = id + 1
	var r := {"id": id, "from_iso": from_iso, "from": int(opts.get("from", 0)), "to_iso": to_iso, "to": int(opts.get("to", 0)),
			"good": str(opts["good"]), "qty": float(opts["qty"]), "mode": mode, "vehicle": int(opts.get("vehicle", -1)),
			"every": maxi(1, int(opts.get("every", 7))), "next_day": gs.today(), "active": true, "status": "", "trips": 0}
	a["routes"].append(r)
	return {"route": r}


static func remove_route(gs, id: int) -> void:
	var rs: Array = st(gs)["routes"]
	for i in range(rs.size()):
		if int(rs[i]["id"]) == id:
			rs.remove_at(i)
			return


## Vuelos en curso con su posición (lon/lat) para dibujarlos en el mapa mundial.
static func flights_in_air(gs) -> Array:
	var out := []
	for f in st(gs).get("flights", []):
		if bool(f.get("delivered", false)) or str(f["from_iso"]) == str(f["to_iso"]):
			continue
		var tot := maxf(1.0, float(int(f["arrive"]) - int(f["depart"])))
		var t := clampf((float(gs.today()) + TimeManager.hour_float() / 24.0 - float(f["depart"])) / tot, 0.0, 1.0)
		out.append({"flight": f, "t": t, "a": TravelSim.coords(str(f["from_iso"])), "b": TravelSim.coords(str(f["to_iso"]))})
	return out


static func _num(v: float) -> String:
	return ("%.1f" % v).replace(".", ",").trim_suffix(",0")
