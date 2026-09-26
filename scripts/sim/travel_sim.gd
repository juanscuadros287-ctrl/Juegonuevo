class_name TravelSim
extends RefCounted
## Fase 10 — Viajes del personaje entre países (docs/FASE10.md).
## El personaje está físicamente en un solo país (countries.location). Viajar toma días y cuesta según la
## distancia real (círculo máximo entre los países del mapa mundial) y la época: barco de vela y
## diligencia (colonial), barco de vapor y tren (industrial), avión comercial (con Aviación).
## Durante el viaje location = "" (en tránsito). Al llegar, la interfaz muestra ese país.
## El pasaje se paga a una naviera o aerolínea de fuera (sale de la economía, como una importación).

const EARTH_R := 6371.0


static func cfg() -> Dictionary:
	return CountriesSim.cfg().get("travel", {})


## [lon, lat] del país: centro de su etiqueta en el mapa mundial (o inventado para los de respaldo).
static func coords(iso: String) -> Vector2:
	for c in WorldData.world().get("countries", []):
		if str(c.get("iso", "")) == iso:
			return Vector2(float(c["label"][0]), float(c["label"][1]))
	var fb: Array = CountriesSim.cfg().get("fallback_coords", {}).get(iso, [0.0, 0.0])
	return Vector2(float(fb[0]), float(fb[1]))


## Distancia real en km (haversine).
static func distance_km(a: String, b: String) -> float:
	if a == b:
		return 0.0
	var p := coords(a)
	var q := coords(b)
	var la1 := deg_to_rad(p.y)
	var la2 := deg_to_rad(q.y)
	var dla := la2 - la1
	var dlo := deg_to_rad(q.x - p.x)
	var h := sin(dla * 0.5) * sin(dla * 0.5) + cos(la1) * cos(la2) * sin(dlo * 0.5) * sin(dlo * 0.5)
	return 2.0 * EARTH_R * asin(minf(1.0, sqrt(h)))


## Medio de viaje de la época (el más moderno disponible).
static func mode(gs) -> Dictionary:
	var best := {}
	for m in cfg().get("modes", []):
		if int(m.get("era", 1)) <= gs.era() and gs.has_tech(str(m.get("tech", ""))):
			best = m
	if best.is_empty() and not cfg().get("modes", []).is_empty():
		best = cfg()["modes"][0]
	return best


## {km, days, cost, mode, label}
static func quote(gs, from_iso: String, to_iso: String) -> Dictionary:
	var m := mode(gs)
	var km := distance_km(from_iso, to_iso)
	var days := maxi(int(m.get("min_days", 1)), int(ceil(km / maxf(1.0, float(m.get("km_per_day", 500.0))))))
	var cost := snappedf((float(m.get("base_cost", 150.0)) + float(m.get("per_1000km", 150.0)) * km / 1000.0) * gs.price_mult(), 1.0)
	return {"km": roundf(km), "days": days, "cost": cost, "mode": str(m.get("id", "")), "label": str(m.get("label", ""))}


static func traveling(gs) -> bool:
	return CountriesSim.ready(gs) and not (gs.countries.get("travel", {}) as Dictionary).is_empty()


static func block_reason(gs, to_iso: String) -> String:
	if not CountriesSim.ready(gs):
		return "Sin estado de países"
	if traveling(gs):
		return "Ya estás de viaje"
	var here := CountriesSim.location(gs)
	if to_iso == here:
		return "Ya estás en %s" % CountriesSim.country_label(to_iso)
	if not CountriesSim.has_context(gs, to_iso):
		return "Primero compra la licencia de inversión en %s" % CountriesSim.country_label(to_iso)
	var q := quote(gs, here, to_iso)
	if gs.money < float(q["cost"]):
		return "Dinero insuficiente (%s)" % Fmt.money(float(q["cost"]))
	return ""


static func start(gs, to_iso: String) -> String:
	var reason := block_reason(gs, to_iso)
	if reason != "":
		return reason
	var from_iso := CountriesSim.location(gs)
	var q := quote(gs, from_iso, to_iso)
	gs.add_money(-float(q["cost"]))
	CountriesSim.add_outflow(gs, float(q["cost"]))
	gs.countries["stats"]["travel_spent"] = float(gs.countries["stats"].get("travel_spent", 0.0)) + float(q["cost"])
	gs.countries["travel"] = {"from": from_iso, "to": to_iso, "depart": gs.today(), "arrive": gs.today() + int(q["days"]),
			"cost": q["cost"], "mode": q["mode"], "label": q["label"], "km": q["km"]}
	gs.countries["location"] = ""
	gs.notify("Viajas de %s a %s en %s: %d km, %d días, %s." % [CountriesSim.country_label(from_iso), CountriesSim.country_label(to_iso),
			str(q["label"]).to_lower(), int(q["km"]), int(q["days"]), Fmt.money(float(q["cost"]))], "jugador")
	return ""


## Días que faltan (0 si no hay viaje).
static func days_left(gs) -> int:
	if not traveling(gs):
		return 0
	return maxi(0, int(gs.countries["travel"]["arrive"]) - gs.today())


## Fracción del viaje hecha (para dibujar el trayecto).
static func progress(gs) -> float:
	if not traveling(gs):
		return 0.0
	var t: Dictionary = gs.countries["travel"]
	var total := maxf(1.0, float(int(t["arrive"]) - int(t["depart"])))
	return clampf(float(gs.today() - int(t["depart"])) / total, 0.0, 1.0)


static func daily(gs) -> void:
	if not traveling(gs):
		return
	var t: Dictionary = gs.countries["travel"]
	if gs.today() < int(t["arrive"]):
		return
	var to := str(t["to"])
	gs.countries["location"] = to
	gs.countries["travel"] = {}
	var trips: Array = gs.countries["trips"]
	trips.append({"from": t["from"], "to": to, "depart": t["depart"], "arrive": gs.today(), "cost": t["cost"], "mode": t["mode"]})
	while trips.size() > 30:
		trips.pop_front()
	gs.countries["pending_view"] = to   # La interfaz cambia la cámara a ese país (CountriesSim.set_active).
	gs.notify("Llegaste a %s. Ya puedes construir y dirigir tus negocios aquí en persona." % CountriesSim.country_label(to), "importante")
